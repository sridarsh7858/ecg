"""
Leave-One-Subject-Out training and calibration.

    python train.py [--windows windows.csv] [--out artifacts/]

WHAT THIS PRODUCES

One calibrated number per 30 s window: the probability that the window came
from a stressed state. The Flutter app bands that 0..1 probability into the
five existing levels with StressScoring.levelForScore(), so the percentage the
UI shows is a measured quantity, not a rescaled class index.

WHY LEAVE-ONE-SUBJECT-OUT

WESAD has 15 subjects. A random train/test split puts the same person's
heartbeats on both sides -- resting heart rate alone then identifies the
subject, and the reported accuracy measures nothing. LOSO is the only split
that answers the question the app actually asks: does this work on a person
the model has never seen?

WHY CALIBRATION

A raw sigmoid output is a score, not a probability. The app displays it as a
percentage, so it has to mean what it says: windows called 70% should be
stressed about 70% of the time. Each fold holds out two further subjects to
fit a Platt scaler, so the reported calibration error is out-of-sample too.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
from sklearn.preprocessing import StandardScaler

import tensorflow as tf

import hrv

SEED = 1337
N_CALIBRATION_SUBJECTS = 2   # held out inside each fold, to fit Platt honestly


def build_mlp(n_features):
    """5 -> 16 -> 8 -> 1. Tiny on purpose: 5 tabular features cannot support more."""
    tf.keras.utils.set_random_seed(SEED)
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(n_features,)),
        tf.keras.layers.Dense(16, activation="relu"),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(8, activation="relu"),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="binary_crossentropy")
    return model


def expected_calibration_error(y_true, p, bins=10):
    """
    Mean gap between confidence and accuracy, weighted by bin population.

    This is the number that says whether the displayed percentage is honest.
    """
    edges = np.linspace(0.0, 1.0, bins + 1)
    ece = 0.0
    for lo, hi in zip(edges[:-1], edges[1:]):
        in_bin = (p > lo) & (p <= hi) if lo > 0 else (p >= lo) & (p <= hi)
        if not np.any(in_bin):
            continue
        ece += in_bin.mean() * abs(y_true[in_bin].mean() - p[in_bin].mean())
    return float(ece)


def fit_fold(x_train, y_train, x_val, y_val, n_features):
    model = build_mlp(n_features)
    counts = np.bincount(y_train.astype(int), minlength=2)
    class_weight = {
        0: len(y_train) / (2.0 * max(counts[0], 1)),
        1: len(y_train) / (2.0 * max(counts[1], 1)),
    }
    model.fit(
        x_train, y_train,
        validation_data=(x_val, y_val),
        epochs=200, batch_size=32, verbose=0,
        class_weight=class_weight,
        callbacks=[tf.keras.callbacks.EarlyStopping(
            monitor="val_loss", patience=20, restore_best_weights=True)],
    )
    return model


def _provenance_path(path):
    """Repo-relative path where possible, absolute only as a last resort."""
    resolved = path.resolve()
    repo_root = Path(__file__).resolve().parent.parent
    try:
        return resolved.relative_to(repo_root).as_posix()
    except ValueError:
        return str(resolved)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows", type=Path, default=Path("windows.csv"))
    ap.add_argument("--out", type=Path, default=Path("artifacts"))
    args = ap.parse_args()

    if not args.windows.exists():
        raise SystemExit(f"{args.windows} not found -- run preprocess.py first.")

    args.out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)

    df = pd.read_csv(args.windows)
    train_df = df[df["target"].notna()].reset_index(drop=True)
    meditation_df = df[df["condition"] == "meditation"].reset_index(drop=True)
    # Sort numerically so S9 precedes S10 in the per-fold log.
    subjects = sorted(train_df["subject"].unique(),
                      key=lambda s: int("".join(c for c in s if c.isdigit())))

    print(f"{len(train_df)} trainable windows, {len(subjects)} subjects, "
          f"{len(meditation_df)} meditation windows held out\n")

    x_all = train_df[hrv.FEATURE_ORDER].to_numpy(np.float64)
    y_all = train_df["target"].to_numpy(np.int32)
    groups = train_df["subject"].to_numpy()

    per_subject, oof_p, oof_y, oof_subject = [], [], [], []
    meditation_scores, baseline_scores = [], []
    # Every out-of-fold meditation and baseline window, kept individually. The
    # mean-vs-mean comparison below cannot answer the question on its own --
    # see the ranking check after the loop.
    meditation_windows, baseline_windows = [], []

    for held_out in subjects:
        test_mask = groups == held_out
        pool = [s for s in subjects if s != held_out]

        # Two more subjects come out of the training pool to fit the Platt
        # scaler, so calibration is never fitted on data the model trained on.
        calib_subjects = list(rng.choice(pool, size=N_CALIBRATION_SUBJECTS,
                                         replace=False))
        calib_mask = np.isin(groups, calib_subjects)
        fit_mask = ~test_mask & ~calib_mask

        scaler = StandardScaler().fit(x_all[fit_mask])
        xs = lambda m: scaler.transform(x_all[m])

        model = fit_fold(xs(fit_mask), y_all[fit_mask],
                         xs(calib_mask), y_all[calib_mask],
                         x_all.shape[1])

        raw_calib = model.predict(xs(calib_mask), verbose=0).ravel()
        raw_test = model.predict(xs(test_mask), verbose=0).ravel()

        platt = LogisticRegression().fit(raw_calib.reshape(-1, 1), y_all[calib_mask])
        p_test = platt.predict_proba(raw_test.reshape(-1, 1))[:, 1]

        y_test = y_all[test_mask]
        row = {
            "subject": held_out,
            "n": int(test_mask.sum()),
            "accuracy": accuracy_score(y_test, p_test >= 0.5),
            "f1": f1_score(y_test, p_test >= 0.5, average="macro", zero_division=0),
            "auroc": (roc_auc_score(y_test, p_test)
                      if len(np.unique(y_test)) > 1 else float("nan")),
            "ece": expected_calibration_error(y_test, p_test),
        }
        per_subject.append(row)
        oof_p.append(p_test); oof_y.append(y_test)
        oof_subject.extend([held_out] * int(test_mask.sum()))

        # Sanity check: score this subject's meditation windows with the model
        # that never saw them, and compare against their baseline windows.
        med = meditation_df[meditation_df["subject"] == held_out]
        if len(med):
            mp = platt.predict_proba(model.predict(
                scaler.transform(med[hrv.FEATURE_ORDER].to_numpy(np.float64)),
                verbose=0).ravel().reshape(-1, 1))[:, 1]
            meditation_scores.append(mp.mean())
            meditation_windows.extend(mp.tolist())
        base = test_mask & (train_df["condition"] == "baseline").to_numpy()
        if base.any():
            bp = p_test[(train_df["condition"][test_mask]
                         == "baseline").to_numpy()]
            baseline_scores.append(bp.mean())
            baseline_windows.extend(bp.tolist())

        print(f"{held_out:>4}  n={row['n']:3d}  acc={row['accuracy']:.3f}  "
              f"f1={row['f1']:.3f}  auroc={row['auroc']:.3f}  ece={row['ece']:.3f}")

    results = pd.DataFrame(per_subject)
    oof_p = np.concatenate(oof_p); oof_y = np.concatenate(oof_y)

    print("\n" + "=" * 62)
    print("LEAVE-ONE-SUBJECT-OUT RESULTS")
    print("=" * 62)
    for metric in ("accuracy", "f1", "auroc", "ece"):
        vals = results[metric].dropna()
        # ECE is an error: its worst subject is the largest, not the smallest.
        worst = vals.max() if metric == "ece" else vals.min()
        print(f"  {metric:9s} {vals.mean():.3f} +/- {vals.std():.3f}   "
              f"(worst subject {worst:.3f})")
    print("\nThe spread matters more than the mean: a model that is excellent")
    print("on 12 people and useless on 3 is a different product from one that")
    print("is uniformly decent.")

    # --- GBM reference, to show what the 5 features can support -------------
    gbm_scores = []
    for held_out in subjects:
        m = groups == held_out
        gbm = HistGradientBoostingClassifier(max_iter=200, random_state=SEED)
        gbm.fit(x_all[~m], y_all[~m])
        gbm_scores.append(accuracy_score(y_all[m], gbm.predict(x_all[m])))
    print(f"\nGBM reference (same LOSO split): "
          f"{np.mean(gbm_scores):.3f} +/- {np.std(gbm_scores):.3f}")
    print("If the MLP trails this badly, the gap belongs in the model card.")

    # --- Meditation sanity check --------------------------------------------
    #
    # Comparing the two MEANS is too blunt to decide this, and that is not
    # hypothetical: this pipeline returns ~0.227 for meditation and ~0.224 for
    # baseline. Both sit on the floor of the calibrated scale. The model was
    # trained to separate stress from not-stress, and meditation is further
    # from stress than baseline is, so the sigmoid saturates for both and the
    # gap between the two means carries almost no information.
    #
    # What the check is really asking is whether the model RANKS meditation
    # below baseline, so ask that directly: AUROC over the pooled out-of-fold
    # windows with baseline as the positive class. 0.5 is indifference, above
    # 0.5 means meditation is ranked calmer, and unlike the means it is not
    # compressed by the calibration.
    med_auroc = None
    print("\n" + "-" * 62)
    if meditation_scores and baseline_scores:
        med_mean, base_mean = np.mean(meditation_scores), np.mean(baseline_scores)

        scores = np.array(baseline_windows + meditation_windows)
        is_baseline = np.array([1] * len(baseline_windows)
                               + [0] * len(meditation_windows))
        med_auroc = float(roc_auc_score(is_baseline, scores))

        # Three outcomes, not two. A bare > 0.5 test would report the 0.513
        # this pipeline measures as a PASS, and 0.513 over windows that overlap
        # by 50% is indifference, not evidence of anything. Only a result on
        # the wrong side of chance says the upstream is broken.
        if med_auroc < 0.5:
            verdict = "FAIL"
        elif med_auroc < 0.55:
            verdict = "INDIFFERENT"
        else:
            verdict = "PASS"

        print(f"Meditation sanity check: {verdict}")
        print(f"  mean p(stress) during meditation {med_mean:.3f}")
        print(f"  mean p(stress) during baseline   {base_mean:.3f}")
        print(f"  baseline-above-meditation AUROC  {med_auroc:.3f} "
              f"({len(baseline_windows)} baseline vs "
              f"{len(meditation_windows)} meditation windows)")
        if verdict == "FAIL":
            print("  Meditation ranks MORE stressed than baseline. Something is")
            print("  wrong upstream -- fix extraction before trusting any metric")
            print("  above.")
        elif verdict == "INDIFFERENT":
            print("  The model does not separate the two rest states: it ranks")
            print("  meditation and baseline about equally. That is what a")
            print("  stress-vs-rest classifier is expected to do once both")
            print("  classes sit far from its decision boundary, and the")
            print("  extracted features do differ in the right direction")
            print("  (meditation has lower HR and higher HRV than baseline).")
            print("  It is not a pass. Nothing here licenses a claim that the")
            print("  model can tell calm from very calm.")
        else:
            print("  Meditation ranks calmer than baseline, which is the")
            print("  direction the protocol says it should.")
    else:
        print("Meditation sanity check: skipped (no meditation windows)")

    # --- Final model, trained on every subject -------------------------------
    print("-" * 62 + "\nTraining final model on all subjects...")
    final_scaler = StandardScaler().fit(x_all)
    x_scaled = final_scaler.transform(x_all)

    hold = np.isin(groups, list(rng.choice(subjects, size=2, replace=False)))
    final_model = fit_fold(x_scaled[~hold], y_all[~hold],
                           x_scaled[hold], y_all[hold], x_all.shape[1])

    # Calibrate the shipped model on the pooled out-of-fold predictions -- the
    # only genuinely out-of-sample scores available. The final model is trained
    # on more data than any fold model, so this mapping is approximate; the
    # model card says so.
    final_platt = LogisticRegression().fit(oof_p.reshape(-1, 1), oof_y)

    final_model.save(args.out / "stress_model.keras")
    np.save(args.out / "oof_predictions.npy",
            np.column_stack([oof_p, oof_y]))
    results.to_csv(args.out / "loso_metrics.csv", index=False)

    summary = {
        "dataset": "WESAD",
        # Recorded so a model card can never misattribute its data: if this is
        # not the output of preprocess.py on WESAD, the card is wrong. Stored
        # relative to the repository when it sits inside one - the card ends up
        # inside the shipped APK, and an absolute path would put whoever ran
        # the training in there with it.
        "windows_file": _provenance_path(args.windows),
        "subjects": len(subjects),
        "windows": int(len(train_df)),
        "window_seconds": 30,
        "features": hrv.FEATURE_ORDER,
        "positive_class": "stress (TSST)",
        "negative_class": "baseline + amusement",
        "held_out": "meditation",
        "loso": {m: {"mean": float(results[m].dropna().mean()),
                     "std": float(results[m].dropna().std()),
                     # "worst" is the largest value for ECE (an error) and the
                     # smallest for accuracy/f1/auroc (scores).
                     "worst": float(results[m].dropna().max() if m == "ece"
                                    else results[m].dropna().min())}
                 for m in ("accuracy", "f1", "auroc", "ece")},
        "gbm_reference_accuracy": float(np.mean(gbm_scores)),
        "meditation_check": {
            "meditation_mean_p": float(np.mean(meditation_scores)) if meditation_scores else None,
            "baseline_mean_p": float(np.mean(baseline_scores)) if baseline_scores else None,
            # The discriminating number - see the comment at the check itself
            # for why the two means above cannot decide this alone.
            "baseline_above_meditation_auroc": med_auroc,
            "verdict": verdict if meditation_scores and baseline_scores else None,
            "meditation_windows": len(meditation_windows),
            "baseline_windows": len(baseline_windows),
        },
        "scaler": {
            "order": hrv.FEATURE_ORDER,
            "mean": final_scaler.mean_.tolist(),
            "std": final_scaler.scale_.tolist(),
        },
        "platt": {
            "coef": float(final_platt.coef_[0][0]),
            "intercept": float(final_platt.intercept_[0]),
        },
    }
    (args.out / "training_summary.json").write_text(json.dumps(summary, indent=2))

    print(f"\nWrote {args.out}/stress_model.keras, loso_metrics.csv, "
          f"training_summary.json")
    print("Next: python export.py")


if __name__ == "__main__":
    main()
