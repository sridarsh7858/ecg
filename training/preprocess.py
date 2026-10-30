"""
WESAD -> 30-second HRV feature windows.

    python preprocess.py --wesad <path to WESAD dir> [--out windows.csv]

WESAD (Schmidt et al., ICMI 2018) is free, needs no data-request form, and is
about 2.1 GB. Download it from the UCI ML Repository or the Uni Siegen mirror
and unzip so the layout is:

    WESAD/
      S2/S2.pkl
      S3/S3.pkl
      ...            (S2-S17; S1 and S12 were dropped by the authors)

WINDOW LENGTH IS 30 SECONDS AND THAT IS NOT ARBITRARY.

MeasureController defaults to a 30 s capture
(mobile/lib/features/measure/measure_controller.dart:34). SDNN, RMSSD and
pNN50 all depend on window length -- SDNN over 30 s is simply not the same
quantity as SDNN over the 5-minute windows most HRV literature reports. Train
on 5-minute windows and the model is miscalibrated in production from the
first reading.
"""

from __future__ import annotations

import argparse
import pickle
import sys
from pathlib import Path

import numpy as np
import pandas as pd

import hrv

FS = 700.0            # RespiBAN chest ECG
WINDOW_S = 30.0       # must match the app capture duration
HOP_S = 15.0          # 50% overlap, for augmentation only (see note below)

# WESAD label codes, as documented with the dataset.
CONDITIONS = {1: "baseline", 2: "stress", 3: "amusement", 4: "meditation"}

# Amusement is in the NEGATIVE class deliberately: it is high-arousal but
# low-stress. Including it forces the model to learn stress rather than "fast
# heart rate", which is exactly the failure mode the current hand-written
# heuristic has by construction.
TARGET = {"baseline": 0, "stress": 1, "amusement": 0}
# Meditation is held out entirely -- it is a sanity check, not a training
# class. A correct model should score it BELOW baseline. See train.py.


def load_subject(pkl_path):
    """WESAD pickles are Python 2 pickles, hence encoding='latin1'."""
    with open(pkl_path, "rb") as fh:
        data = pickle.load(fh, encoding="latin1")
    ecg = np.asarray(data["signal"]["chest"]["ECG"], dtype=np.float64).ravel()
    labels = np.asarray(data["label"]).ravel()
    n = min(ecg.size, labels.size)
    return ecg[:n], labels[:n]


def windows_for_subject(subject, ecg, labels):
    """Slice into 30 s windows and extract features from each."""
    size = int(WINDOW_S * FS)
    hop = int(HOP_S * FS)
    rows, skipped = [], 0

    for start in range(0, ecg.size - size + 1, hop):
        stop = start + size
        window_labels = labels[start:stop]

        # Reject any window straddling a protocol transition. A window that is
        # half baseline and half stress has no honest label.
        code = int(window_labels[0])
        if code not in CONDITIONS or not np.all(window_labels == code):
            continue

        features = hrv.features_from_ecg(ecg[start:stop], FS)
        if features is None:
            skipped += 1
            continue

        rows.append({
            "subject": subject,
            "condition": CONDITIONS[code],
            "start_s": start / FS,
            **features,
        })

    return rows, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wesad", required=True, type=Path,
                    help="path to the unzipped WESAD directory")
    ap.add_argument("--out", type=Path, default=Path("windows.csv"))
    args = ap.parse_args()

    if not args.wesad.is_dir():
        sys.exit(
            f"Not a directory: {args.wesad}\n\n"
            "Download WESAD (~2.1 GB, free, no data-request form) from the UCI\n"
            "ML Repository or the Uni Siegen mirror, unzip it, and pass the\n"
            "directory containing S2/, S3/, ... here."
        )

    pkls = sorted(args.wesad.glob("S*/S*.pkl"),
                  key=lambda p: int("".join(c for c in p.stem if c.isdigit())))
    if not pkls:
        sys.exit(f"No S*/S*.pkl files under {args.wesad}. Is the archive unzipped?")

    all_rows, total_skipped = [], 0
    for pkl in pkls:
        subject = pkl.stem
        ecg, labels = load_subject(pkl)
        rows, skipped = windows_for_subject(subject, ecg, labels)
        total_skipped += skipped
        all_rows.extend(rows)

        counts = pd.Series([r["condition"] for r in rows]).value_counts().to_dict()
        print(f"{subject:>4}  {len(rows):4d} windows  "
              f"({skipped} unusable)  {counts}")

    if not all_rows:
        sys.exit("No usable windows extracted. Check the ECG channel and sampling rate.")

    df = pd.DataFrame(all_rows)
    df["target"] = df["condition"].map(TARGET)   # NaN for meditation, by design

    df.to_csv(args.out, index=False)

    trainable = df["target"].notna().sum()
    print(f"\n{len(df)} windows from {df['subject'].nunique()} subjects "
          f"-> {args.out}")
    print(f"  trainable (baseline/stress/amusement): {trainable}")
    print(f"  held out  (meditation, sanity check):  {(~df['target'].notna()).sum()}")
    print(f"  discarded (too few valid intervals):   {total_skipped}")
    print("\nClass balance among trainable windows:")
    print(df[df["target"].notna()]["condition"].value_counts().to_string())
    print(
        "\nNote: windows overlap by 50%, so they share beats. That is fine for\n"
        "augmentation but must never be cited as an effective sample size --\n"
        "train.py splits leave-one-subject-out, which is the split that matters."
    )


if __name__ == "__main__":
    main()
