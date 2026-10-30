"""
Export the trained model to TFLite for the Flutter app.

    python export.py [--artifacts artifacts/] [--assets ../mobile/assets/models]

A DELIBERATE DEVIATION FROM docs/future_ml_integration.md

That document has the Dart side load feature_scaler.json and scale the vector
before inference. This exporter instead bakes the scaler in as the first layer
and the Platt calibration in as the last, so:

    TFLite input  = raw [hr, meanRR, rmssd, sdnn, pnn50]
    TFLite output = calibrated P(stress), directly usable as the percentage

The plan warned that "a silently reordered vector is the classic way this class
of bug ships". Baking the constants into the graph removes that failure mode
entirely rather than guarding against it -- Dart cannot scale wrongly if Dart
never scales. feature_scaler.json is still written, marked as reference: the
model card needs it, and the ESP32 wants it for range sanity checks.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

import hrv

MODEL_VERSION = "ml-1.0.0"


def build_deployable(trained, scaler_mean, scaler_std, platt_coef, platt_intercept):
    """
    Wrap the trained network with the scaler in front and Platt behind.

    Normalization rather than a Lambda layer on purpose: Lambda serialises as an
    opaque TF op and drags in SELECT_TF_OPS, which would force the Flex delegate
    into the Flutter app and roughly double its size. Normalization converts to
    plain TFLite builtins.
    """
    raw_input = tf.keras.Input(shape=(len(hrv.FEATURE_ORDER),), name="features")

    standardise = tf.keras.layers.Normalization(
        axis=-1, mean=scaler_mean, variance=scaler_std ** 2, name="standardise",
    )
    score = trained(standardise(raw_input))

    # Keras 3 removed the `weights=` constructor kwarg, so build then set.
    calibrate = tf.keras.layers.Dense(1, activation="sigmoid", name="calibrate")
    calibrated = calibrate(score)
    calibrate.set_weights([
        np.array([[platt_coef]], dtype=np.float32),
        np.array([platt_intercept], dtype=np.float32),
    ])

    return tf.keras.Model(raw_input, calibrated, name="neuropulse_stress")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifacts", type=Path, default=Path("artifacts"))
    ap.add_argument("--assets", type=Path, default=Path("../mobile/assets/models"))
    args = ap.parse_args()

    summary_path = args.artifacts / "training_summary.json"
    if not summary_path.exists():
        raise SystemExit(f"{summary_path} not found -- run train.py first.")

    summary = json.loads(summary_path.read_text())
    trained = tf.keras.models.load_model(args.artifacts / "stress_model.keras")

    mean = np.array(summary["scaler"]["mean"], dtype=np.float32)
    std = np.array(summary["scaler"]["std"], dtype=np.float32)
    deployable = build_deployable(
        trained, mean, std,
        summary["platt"]["coef"], summary["platt"]["intercept"],
    )

    converter = tf.lite.TFLiteConverter.from_keras_model(deployable)
    # Builtins only. If this ever fails, fix the offending layer rather than
    # adding SELECT_TF_OPS -- that would require shipping the Flex delegate.
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    tflite_model = converter.convert()

    args.assets.mkdir(parents=True, exist_ok=True)
    (args.assets / "stress_model.tflite").write_bytes(tflite_model)

    # --- Parity check: Keras and TFLite must agree ---------------------------
    rng = np.random.default_rng(0)
    probe = np.column_stack([
        rng.uniform(50, 110, 40),    # hr
        rng.uniform(545, 1200, 40),  # meanRR
        rng.uniform(8, 90, 40),      # rmssd
        rng.uniform(12, 110, 40),    # sdnn
        rng.uniform(0, 60, 40),      # pnn50
    ]).astype(np.float32)

    keras_out = deployable.predict(probe, verbose=0).ravel()

    interpreter = tf.lite.Interpreter(model_content=tflite_model)
    interpreter.allocate_tensors()
    in_detail = interpreter.get_input_details()[0]
    out_detail = interpreter.get_output_details()[0]
    tflite_out = []
    for row in probe:
        interpreter.set_tensor(in_detail["index"], row.reshape(1, -1))
        interpreter.invoke()
        tflite_out.append(float(interpreter.get_tensor(out_detail["index"])[0][0]))
    tflite_out = np.array(tflite_out)

    max_diff = float(np.max(np.abs(keras_out - tflite_out)))
    print(f"Keras vs TFLite max difference: {max_diff:.2e}")
    if max_diff > 1e-4:
        raise SystemExit(
            f"PARITY CHECK FAILED ({max_diff:.2e} > 1e-4).\n"
            "The exported model does not match the trained one. Do not ship this."
        )
    print("Parity check passed.")

    # --- Scaler, for reference and for the firmware --------------------------
    (args.assets / "feature_scaler.json").write_text(json.dumps({
        "note": ("Already baked into stress_model.tflite. The app passes RAW "
                 "features and receives a calibrated probability. Provided for "
                 "the model card and for ESP32 range sanity checks."),
        "order": hrv.FEATURE_ORDER,
        "mean": summary["scaler"]["mean"],
        "std": summary["scaler"]["std"],
        "platt": summary["platt"],
    }, indent=2))

    # --- Model card, generated from measured numbers only --------------------
    loso = summary["loso"]
    med = summary["meditation_check"]

    # The card's reading of the meditation check has to follow the verdict the
    # run actually produced. Hard-coding the current one would leave a future
    # export contradicting its own table.
    med_reading = {
        "FAIL": (
            "The model ranks meditation as MORE stressed than baseline. That is "
            "the wrong direction, and it points at extraction or labelling "
            "rather than at the model. **Do not ship this model.** The metrics "
            "above are not meaningful until it is fixed."
        ),
        "INDIFFERENT": (
            "At this value, over windows that overlap by 50%, the model is "
            "indifferent between the two rest states. That is what a binary "
            "stress detector does once both classes sit far from its decision "
            "boundary, and it is not evidence of a fault: the extracted "
            "features do differ in the physiologically expected direction, "
            "meditation showing lower heart rate and higher HRV than baseline. "
            "**It is also not a pass.** Nothing measured here supports a claim "
            "that this model can tell calm from very calm - worth remembering "
            "given that the app bands its output into five levels."
        ),
        "PASS": (
            "The model ranks meditation below baseline, which is the direction "
            "the protocol says it should."
        ),
    }.get(med.get("verdict"), "No verdict was recorded for this run.")
    fmt = lambda m: (f"{loso[m]['mean']:.3f} +/- {loso[m]['std']:.3f} "
                     f"(worst subject {loso[m]['worst']:.3f})")

    (args.assets / "model_card.md").write_text(f"""# NeuroPulse stress model {MODEL_VERSION}

Generated by `training/export.py`. Every number here was measured by
`training/train.py` on this machine. Nothing is quoted from literature.

## What it does

Input: `{', '.join(hrv.FEATURE_ORDER)}` computed over a **30-second** window.
Output: a single calibrated probability that the window came from a stressed
state.

The app bands that probability into its five levels using the existing
`StressScoring.levelForScore()`. **The five levels are a banding of one binary
probability, not five separately validated states.** No dataset provides
five-level stress ground truth.

## Data

- **{summary['dataset']}** (Schmidt et al., ICMI 2018), chest ECG at 700 Hz
- {summary['subjects']} subjects, {summary['windows']} usable 30 s windows
- Extracted from: `{summary.get('windows_file', 'unknown')}`
- Positive class: {summary['positive_class']}
- Negative class: {summary['negative_class']}
- Held out: {summary['held_out']} (used only as a sanity check)

Amusement sits in the negative class on purpose. It is high-arousal but
low-stress, so including it stops the model from simply learning "fast heart
rate".

## Results (leave-one-subject-out, {summary['subjects']} folds)

| Metric | Value |
| --- | --- |
| Accuracy | {fmt('accuracy')} |
| Macro F1 | {fmt('f1')} |
| AUROC | {fmt('auroc')} |
| Expected calibration error | {fmt('ece')} |

Gradient-boosted-tree reference on the same split:
{summary['gbm_reference_accuracy']:.3f} accuracy.

The per-subject spread matters more than the mean. Per-fold numbers are in
`training/artifacts/loso_metrics.csv`.

Calibration was fitted on subjects held out from each fold, so the calibration
error above is out-of-sample. The shipped model is trained on all subjects and
calibrated on the pooled out-of-fold predictions, which is an approximation:
the final model is trained on more data than any fold model was.

## Sanity check: meditation

Meditation windows were held out of training entirely and scored by the fold
model that never saw the subject.

| | |
| --- | --- |
| Mean P(stress), meditation | {med['meditation_mean_p']:.3f} |
| Mean P(stress), baseline | {med['baseline_mean_p']:.3f} |
| Baseline-above-meditation AUROC | {med['baseline_above_meditation_auroc']:.3f} |
| Verdict | **{med['verdict']}** |

The two means are not the test. Both sit on the floor of the calibrated scale -
the model separates stress from rest, and both of these are rest - so the gap
between them carries almost no information. The AUROC is the test: it asks
whether the model *ranks* meditation below baseline, 0.5 being indifference.

{med_reading}

## Limitations

- **The displayed percentage is not well calibrated.** Expected calibration
  error is {loso['ece']['mean']:.3f} on average and {loso['ece']['worst']:.3f}
  on the worst subject, so a window the app shows as 70% was not stressed 70%
  of the time. The number is a measured model output, not a reliable
  frequency, and the five-level banding inherits that error.
- {summary['subjects']} healthy young adults in a laboratory. Not validated on
  any other population.
- Trained on clean chest ECG at 700 Hz. **Not yet validated on AD8232 dry
  electrode data.** Until firmware parity is confirmed, on-device accuracy is
  unknown and is not claimed to match the numbers above.
- 30-second windows only. Features are window-length dependent; a different
  capture duration invalidates this model.
- Not a medical device. This is an estimate, not a diagnosis.
""")

    print(f"\nWrote to {args.assets}:")
    print(f"  stress_model.tflite   ({len(tflite_model) / 1024:.1f} KB)")
    print("  feature_scaler.json")
    print("  model_card.md")
    print("\nThe TFLite model takes RAW features and returns a calibrated")
    print("probability. Dart does no scaling. See the note in feature_scaler.json.")


if __name__ == "__main__":
    main()
