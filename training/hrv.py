"""
R-peak detection and HRV feature extraction.

This module is the **firmware-parity core**. Everything in here has to be
reimplementable in C on the ESP32, because the ESP32 -- not the phone -- is
what computes the feature vector at runtime (see docs/ble_architecture.md).
If the firmware computes RMSSD differently from this file, the model is fed a
feature distribution it never saw in training, and it will behave worse on
hardware than the offline metrics suggest.

Deliberately no neurokit2 / biosppy dependency. A published library would give
slightly better peaks on clean lab ECG, but it cannot run on the ESP32, so
matching it would create exactly the mismatch described above. This is a
simplified Pan-Tompkins, which is what the firmware will run.

Feature order is fixed and must match PhysiologicalFeatures in
mobile/lib/data/models/physiological_features.dart:

    hr, meanRR, rmssd, sdnn, pnn50
"""

from __future__ import annotations

import numpy as np
from scipy.signal import butter, filtfilt, find_peaks

# The feature contract. Changing this list is a breaking change against the
# Flutter app and the ESP32 firmware.
FEATURE_ORDER = ["hr", "meanRR", "rmssd", "sdnn", "pnn50"]

# --- Artifact rejection constants (the firmware must use the same values) ---
RR_MIN_MS = 300.0            # 200 BPM -- faster than this is a double-detection
RR_MAX_MS = 2000.0           # 30 BPM  -- slower than this is a missed beat
RR_MEDIAN_TOLERANCE = 0.20   # reject intervals >20% from the local median
RR_MEDIAN_WINDOW = 5         # beats in the running median
MIN_VALID_INTERVALS = 20     # below this a 30 s window is not trustworthy


# --------------------------------------------------------------------------
# R-peak detection
# --------------------------------------------------------------------------

def _bandpass(sig, fs, lo=5.0, hi=15.0):
    """5-15 Hz passband: the QRS complex sits here, drift and T-waves do not."""
    nyq = 0.5 * fs
    hi = min(hi, nyq * 0.99)
    b, a = butter(2, [lo / nyq, hi / nyq], btype="band")
    return filtfilt(b, a, sig)


def detect_r_peaks(ecg, fs):
    """
    Simplified Pan-Tompkins. Returns R-peak sample indices.

    Stages: bandpass -> derivative -> square -> moving-window integrate ->
    adaptive threshold with a refractory period -> refine onto the raw peak.
    """
    ecg = np.asarray(ecg, dtype=np.float64).ravel()
    if ecg.size < int(fs):
        return np.array([], dtype=int)

    filtered = _bandpass(ecg, fs)

    # Derivative emphasises the steep QRS slope; squaring makes it positive
    # and amplifies it relative to lower-frequency noise.
    deriv = np.ediff1d(filtered, to_begin=0.0)
    squared = deriv * deriv

    # ~150 ms integration window: wide enough to span one QRS, narrow enough
    # not to merge two beats.
    win = max(1, int(round(0.150 * fs)))
    integrated = np.convolve(squared, np.ones(win) / win, mode="same")

    # 250 ms refractory -- no two real beats are closer than this.
    refractory = max(1, int(round(0.25 * fs)))
    candidates, _ = find_peaks(integrated, distance=refractory)
    if candidates.size == 0:
        return np.array([], dtype=int)

    # Pan-Tompkins adaptive thresholding: running estimates of the signal peak
    # level (spki) and the noise peak level (npki).
    warmup = integrated[: int(2 * fs)] if integrated.size > int(2 * fs) else integrated
    spki = float(np.max(warmup)) * 0.25
    npki = float(np.mean(warmup)) * 0.50

    accepted = []
    for idx in candidates:
        threshold = npki + 0.25 * (spki - npki)
        if integrated[idx] > threshold:
            accepted.append(idx)
            spki = 0.125 * integrated[idx] + 0.875 * spki
        else:
            npki = 0.125 * integrated[idx] + 0.875 * npki

    if not accepted:
        return np.array([], dtype=int)

    # The integrator delays and smears the peak. Refine each detection onto the
    # largest |filtered| sample nearby, which is the actual R deflection.
    search = max(1, int(round(0.05 * fs)))
    refined = []
    for idx in accepted:
        lo = max(0, idx - search)
        hi = min(filtered.size, idx + search + 1)
        refined.append(lo + int(np.argmax(np.abs(filtered[lo:hi]))))

    return np.unique(np.asarray(refined, dtype=int))


def rr_intervals_ms(peaks, fs):
    """R-peak indices -> R-R intervals in milliseconds."""
    peaks = np.asarray(peaks)
    if peaks.size < 2:
        return np.array([], dtype=np.float64)
    return np.diff(peaks).astype(np.float64) / fs * 1000.0


# --------------------------------------------------------------------------
# Artifact rejection
# --------------------------------------------------------------------------

def valid_rr_mask(rr):
    """
    Boolean mask of physiologically plausible R-R intervals.

    Two rules, both cheap enough for the ESP32:
      1. absolute range 300-2000 ms
      2. within 20% of the local running median, which catches ectopic beats
         and missed detections that are individually inside the range
    """
    rr = np.asarray(rr, dtype=np.float64)
    if rr.size == 0:
        return np.zeros(0, dtype=bool)

    mask = (rr >= RR_MIN_MS) & (rr <= RR_MAX_MS)
    if mask.sum() < 3:
        return mask

    half = RR_MEDIAN_WINDOW // 2
    for i in range(rr.size):
        if not mask[i]:
            continue
        lo = max(0, i - half)
        hi = min(rr.size, i + half + 1)
        neighbourhood = rr[lo:hi][mask[lo:hi]]
        if neighbourhood.size < 2:
            continue
        median = float(np.median(neighbourhood))
        if median > 0 and abs(rr[i] - median) / median > RR_MEDIAN_TOLERANCE:
            mask[i] = False

    return mask


def successive_differences(rr, mask):
    """
    |RR[i+1] - RR[i]| for pairs where BOTH intervals survived rejection.

    This matters more than it looks. If you drop an artifact and then diff the
    compacted array, you manufacture a large difference between two intervals
    that were never adjacent -- which inflates RMSSD and pNN50 precisely on the
    noisy windows where they are already least reliable.
    """
    rr = np.asarray(rr, dtype=np.float64)
    mask = np.asarray(mask, dtype=bool)
    both = mask[:-1] & mask[1:]
    if not np.any(both):
        return np.array([], dtype=np.float64)
    return np.abs(rr[1:][both] - rr[:-1][both])


# --------------------------------------------------------------------------
# Features
# --------------------------------------------------------------------------

def hrv_features(rr):
    """
    R-R intervals (ms) -> the five-feature vector, or None if the window is
    too corrupt to trust.

    Units match docs/stress_system.md: hr in BPM, meanRR/rmssd/sdnn in ms,
    pnn50 as a percentage (0-100, not 0-1).
    """
    rr = np.asarray(rr, dtype=np.float64)
    mask = valid_rr_mask(rr)
    valid = rr[mask]

    if valid.size < MIN_VALID_INTERVALS:
        return None

    mean_rr = float(np.mean(valid))
    if mean_rr <= 0:
        return None

    diffs = successive_differences(rr, mask)
    if diffs.size < 2:
        return None

    return {
        "hr": 60000.0 / mean_rr,
        "meanRR": mean_rr,
        # population std (ddof=0), matching a streaming firmware accumulator
        "sdnn": float(np.std(valid)),
        "rmssd": float(np.sqrt(np.mean(diffs ** 2))),
        "pnn50": float(100.0 * np.count_nonzero(diffs > 50.0) / diffs.size),
    }


def features_from_ecg(ecg, fs):
    """Full chain: raw ECG window -> feature vector. The ESP32 runs this."""
    peaks = detect_r_peaks(ecg, fs)
    return hrv_features(rr_intervals_ms(peaks, fs))


def to_vector(features):
    """Dict -> array in the fixed FEATURE_ORDER."""
    return np.array([features[name] for name in FEATURE_ORDER], dtype=np.float64)
