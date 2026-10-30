"""
Tests for the HRV core, runnable before WESAD is downloaded.

Synthesises ECG with known R-R statistics, then asserts the full chain
recovers them. If these fail, nothing downstream is worth training.

    python -m pytest training/test_hrv.py -v
    python training/test_hrv.py            # also works, no pytest needed
"""

from __future__ import annotations

import numpy as np

import hrv

FS = 700.0  # WESAD chest ECG sampling rate


def synth_ecg(rr_ms, fs=FS, noise=0.0, seed=0):
    """
    Build an ECG-like signal whose R peaks sit at the given R-R intervals.

    Each beat is a sharp biphasic QRS (a narrow Gaussian minus a wider one),
    which is enough structure for a QRS detector to lock onto.
    """
    rng = np.random.default_rng(seed)
    rr_ms = np.asarray(rr_ms, dtype=np.float64)

    peak_times = np.concatenate([[1.0], 1.0 + np.cumsum(rr_ms) / 1000.0])
    total = peak_times[-1] + 1.0
    t = np.arange(0, total, 1.0 / fs)
    sig = np.zeros_like(t)

    for pt in peak_times:
        dt = t - pt
        sig += 1.0 * np.exp(-(dt ** 2) / (2 * 0.010 ** 2))   # sharp R
        sig -= 0.25 * np.exp(-(dt ** 2) / (2 * 0.025 ** 2))  # broader S/Q

    # Baseline wander plus mains-ish and white noise -- the bandpass should
    # reject the first two entirely.
    sig += 0.30 * np.sin(2 * np.pi * 0.25 * t)
    if noise > 0:
        sig += noise * np.sin(2 * np.pi * 50.0 * t)
        sig += noise * rng.standard_normal(t.size)

    return sig, peak_times


def rr_series(n, mean_ms, sd_ms, seed=0):
    rng = np.random.default_rng(seed)
    return rng.normal(mean_ms, sd_ms, n)


# --------------------------------------------------------------------------

def test_peak_detection_recovers_beat_count():
    rr = rr_series(45, 800.0, 30.0, seed=1)
    sig, expected = synth_ecg(rr)
    peaks = hrv.detect_r_peaks(sig, FS)
    assert abs(peaks.size - expected.size) <= 1, (
        f"found {peaks.size} peaks, expected {expected.size}"
    )


def test_peak_timing_is_accurate():
    rr = rr_series(40, 850.0, 25.0, seed=2)
    sig, expected = synth_ecg(rr)
    found = hrv.detect_r_peaks(sig, FS) / FS

    n = min(found.size, expected.size)
    err_ms = np.abs(found[:n] - expected[:n]) * 1000.0
    # RMSSD and pNN50 are differences between adjacent intervals, so peak
    # timing error is the binding constraint on feature quality.
    assert np.median(err_ms) < 10.0, f"median timing error {np.median(err_ms):.1f} ms"


def test_features_recover_known_heart_rate():
    rr = rr_series(50, 750.0, 20.0, seed=3)   # 80 BPM
    sig, _ = synth_ecg(rr)
    f = hrv.features_from_ecg(sig, FS)

    assert f is not None
    assert abs(f["hr"] - 80.0) < 2.0, f"hr={f['hr']:.1f}, expected ~80"
    assert abs(f["meanRR"] - 750.0) < 20.0
    assert abs(f["hr"] - 60000.0 / f["meanRR"]) < 1e-6  # the redundancy holds


def test_low_variability_reads_as_low_variability():
    """A rigid rhythm must produce small SDNN/RMSSD; a loose one, large."""
    rigid, _ = synth_ecg(rr_series(50, 750.0, 8.0, seed=4))
    loose, _ = synth_ecg(rr_series(50, 750.0, 60.0, seed=5))

    a = hrv.features_from_ecg(rigid, FS)
    b = hrv.features_from_ecg(loose, FS)
    assert a is not None and b is not None
    assert a["sdnn"] < b["sdnn"], f"{a['sdnn']:.1f} !< {b['sdnn']:.1f}"
    assert a["rmssd"] < b["rmssd"]
    assert a["pnn50"] < b["pnn50"]


def test_artifact_rejection_drops_impossible_intervals():
    rr = np.array([800.0] * 30)
    rr[10] = 120.0    # double-detection
    rr[20] = 2500.0   # missed beat
    mask = hrv.valid_rr_mask(rr)
    assert not mask[10] and not mask[20]
    assert mask.sum() == 28


def test_ectopic_beat_rejected_by_median_rule():
    """In-range but wildly off the local median -- rule 1 misses it, rule 2 does not."""
    rr = np.array([800.0] * 30)
    rr[15] = 1150.0   # inside 300-2000 ms, but +44% off the median
    mask = hrv.valid_rr_mask(rr)
    assert not mask[15]


def test_successive_differences_do_not_bridge_a_gap():
    """
    The subtle one. Dropping index 15 must NOT create a difference between
    intervals 14 and 16 -- they were never adjacent.
    """
    rr = np.array([800.0] * 30)
    rr[15] = 5000.0
    mask = hrv.valid_rr_mask(rr)
    diffs = hrv.successive_differences(rr, mask)

    assert diffs.size == 27          # 29 adjacent pairs, minus the 2 touching index 15
    assert np.all(diffs < 1.0)       # every surviving pair is 800 vs 800
    assert np.max(diffs) < 50.0      # so pNN50 stays 0 rather than being inflated


def test_short_window_returns_none():
    assert hrv.hrv_features(np.array([800.0] * 5)) is None
    assert hrv.features_from_ecg(np.zeros(100), FS) is None


def test_survives_noise():
    rr = rr_series(45, 800.0, 30.0, seed=6)
    sig, _ = synth_ecg(rr, noise=0.15)
    f = hrv.features_from_ecg(sig, FS)
    assert f is not None
    assert abs(f["hr"] - 75.0) < 4.0, f"hr={f['hr']:.1f} under noise"


def test_feature_order_matches_the_flutter_contract():
    f = hrv.features_from_ecg(synth_ecg(rr_series(50, 800.0, 25.0, seed=7))[0], FS)
    assert hrv.FEATURE_ORDER == ["hr", "meanRR", "rmssd", "sdnn", "pnn50"]
    assert hrv.to_vector(f).shape == (5,)
    assert hrv.to_vector(f)[0] == f["hr"]


if __name__ == "__main__":
    passed = failed = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        try:
            fn()
            print(f"  PASS  {name}")
            passed += 1
        except AssertionError as exc:
            print(f"  FAIL  {name}: {exc}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    raise SystemExit(1 if failed else 0)
