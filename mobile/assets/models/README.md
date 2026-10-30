# Models

The trained stress model the app runs on. These files are loaded at startup by
`MLStressPredictionService` (`lib/domain/stress/ml_stress_prediction_service.dart`)
and are bundled into the APK through the `assets/models/` entry in
`pubspec.yaml`.

```
stress_model.tflite    4.7 KB   raw features in, calibrated P(stress) out
feature_scaler.json      638 B  reference constants - already baked into the graph
model_card.md          ~4 KB    measured metrics, limitations, provenance
```

All three are **generated**, never hand-edited. `training/export.py` writes them
and refuses to write anything if the Keras model and the converted TFLite model
disagree by more than 1e-4.

## What the model file actually contains

The graph takes the raw feature vector `[hr, meanRR, rmssd, sdnn, pnn50]` and
returns one calibrated probability that the 30-second window came from a
stressed state. The standardiser is baked in as the first layer and the Platt
calibration as the last, so **Dart does no arithmetic on the features at all**.
That is deliberate: a Dart-side scaler is how a silently transposed or
mis-scaled vector ships unnoticed. `feature_scaler.json` is kept for the model
card and for ESP32 range checks, not for the app to apply.

The app bands that one probability into its five levels with
`StressScoring.levelForScore()`. The five levels are a banding of one binary
probability, not five separately validated states.

## Read the model card before quoting a number

`model_card.md` is generated from the training run's own measurements - nothing
in it is quoted from literature. It records the leave-one-subject-out results,
the per-subject spread, and the limitations, including two that matter for how
the app presents results:

- the displayed percentage is **not** well calibrated
- the model has **not** been validated on AD8232 dry-electrode data

## Regenerating these files

```bash
cd training
python preprocess.py --wesad <path to WESAD>   # -> windows.csv
python train.py                                # -> artifacts/
python export.py                               # -> this folder
```

See `training/README.md`. If `stress_model.tflite` is missing or will not load,
`MLStressPredictionService` falls back to `DummyStressPredictionService` and
relabels itself as the demo engine, so the app keeps working and no heuristic
reading is ever presented as a model output.
