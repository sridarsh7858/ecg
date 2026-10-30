# Training pipeline

Trains the model that replaces `DummyStressPredictionService`. Python only —
nothing here is part of the Flutter build.

```
WESAD ─▶ ECG ─▶ R-peaks ─▶ R-R ─▶ artifact reject ─▶ 30 s windows
   ─▶ 5 HRV features ─▶ binary label ─▶ LOSO train ─▶ calibrate
   ─▶ stress_model.tflite ─▶ Flutter
```

## Run it

```bash
pip install -r requirements.txt

python test_hrv.py                          # works without the dataset
python preprocess.py --wesad path/to/WESAD  # -> windows.csv
python train.py                             # -> artifacts/
python export.py                            # -> ../mobile/assets/models/
```

`test_hrv.py` runs standalone on synthetic ECG. Run it first — if the feature
core is wrong, nothing downstream is worth training.

## The dataset

**WESAD** (Wearable Stress and Affect Detection), Schmidt et al., ICMI 2018.
Free, ~2.1 GB, no data-request form. UCI ML Repository or the Uni Siegen mirror.

15 subjects, chest ECG at 700 Hz, four blocks: baseline, amusement, stress
(Trier Social Stress Test), meditation. Unzip so the layout is `WESAD/S2/S2.pkl`.

Chosen because it is the only free no-paperwork dataset with **raw** chest ECG
plus a validated stressor. Raw ECG matters: it lets the pipeline run the same
chain the ESP32 will run, instead of trusting someone else's precomputed RMSSD.

## Five levels from a two-class dataset

No public dataset has five stress levels. WESAD has two usable ones. So the
model predicts **one calibrated probability** — P(stressed) for a 30 s window —
and the app bands it into the five existing levels using
`StressScoring.levelForScore()` (`mobile/lib/domain/stress/stress_scoring.dart:66`),
which already cuts 0..1 into fifths.

```
P(stress) = 0.79
        ↓
0.0 ─ 0.2 ─ 0.4 ─ 0.6 ─[0.79]─ 1.0
  L1    L2    L3    L4     L5
        ↓
Level 4, "High"
```

The percentage the UI can show is that probability. It is one measured
quantity, not a rescaled class index — which is what makes it defensible in the
model card.

## Four things that are easy to get wrong

**Window length is 30 seconds, and that is load-bearing.** `MeasureController`
captures for 30 s (`measure_controller.dart:34`). SDNN, RMSSD and pNN50 are all
window-length dependent, so SDNN over 30 s is not the same quantity as SDNN
over the 5-minute windows most HRV papers report. Training on 5-minute windows
gives a model that is miscalibrated from its first reading on real hardware.

**Leave-one-subject-out, never a random split.** 15 subjects. A random split
puts the same person's heartbeats on both sides; resting heart rate alone then
identifies the subject and the accuracy figure measures nothing. Windows also
overlap by 50%, so a random split would additionally put literally shared beats
in train and test.

**Amusement is a negative.** It is high-arousal, low-stress. Putting it in the
negative class is what forces the model to learn stress rather than "fast heart
rate" — which is precisely the failure mode the current hand-written heuristic
has by construction.

**Successive differences must not bridge a rejected beat.** Drop an artifact,
compact the array, then diff it, and you manufacture a large difference between
two intervals that were never adjacent — inflating RMSSD and pNN50 exactly on
the noisy windows where they are already least trustworthy. `hrv.py` keeps a
validity mask and diffs only genuinely adjacent surviving pairs.
`test_hrv.py::test_successive_differences_do_not_bridge_a_gap` pins this.

## Firmware parity

`hrv.py` is the contract, not just a script. At runtime the **ESP32** computes
the feature vector, not the phone (`docs/ble_architecture.md`) — so the
firmware must reimplement `hrv.py` in C, including:

- the 5–15 Hz bandpass and the 250 ms refractory period
- `RR_MIN_MS` / `RR_MAX_MS` (300 / 2000)
- the 20%-from-running-median rejection rule
- population standard deviation for SDNN (ddof=0, matching a streaming accumulator)
- pNN50 as a **percentage**, 0–100, not 0–1

If the firmware differs, the model is fed a feature distribution it never saw
in training, and it will do worse on hardware than the offline metrics suggest.
This is the single most likely way this project produces good numbers and a bad
product.

No `neurokit2` dependency for exactly this reason: a better detector that
cannot run on an ESP32 would guarantee the mismatch it appears to avoid.

## What export.py produces

Into `mobile/assets/models/` (already declared in `pubspec.yaml:32-34`):

| File | |
| --- | --- |
| `stress_model.tflite` | ~5 KB, raw features in, calibrated probability out |
| `feature_scaler.json` | reference only — already baked into the graph |
| `model_card.md` | generated from measured numbers, never from literature |

**This deviates from `docs/future_ml_integration.md` on purpose.** That document
has Dart load the scaler and standardise before inference. The exporter instead
bakes the scaler in as the first layer and the Platt calibration in as the last.
Dart cannot scale wrongly if Dart never scales, and a silently reordered feature
vector is the classic way this class of bug ships. `export.py` refuses to write
anything if Keras and TFLite disagree by more than 1e-4.

The converter is pinned to `TFLITE_BUILTINS` only. If conversion ever fails, fix
the offending layer rather than enabling `SELECT_TF_OPS` — that would drag the
Flex delegate into the app.

## What this run produced

The shipped `ml-1.0.0` came out of this pipeline on WESAD. 2845 windows from
15 subjects, 1 discarded for too few valid intervals; 2121 trainable, 724
meditation windows held out.

| Metric | LOSO, 15 folds |
| --- | --- |
| Accuracy | 0.790 +/- 0.128 (worst subject 0.473) |
| Macro F1 | 0.683 +/- 0.211 |
| AUROC | 0.927 +/- 0.117 |
| ECE | 0.195 +/- 0.082 |

The GBM baseline scores 0.800 +/- 0.127 on the same split, so the shipped MLP
does not beat what five tabular features already support - it matches it. That
belongs in the model card rather than being quietly dropped, and it is there.

The meditation check came back **INDIFFERENT**, which is neither the pass nor
the failure this README originally anticipated. See below.

## Reported numbers

`train.py` prints per-subject accuracy, macro F1, AUROC and expected
calibration error, then the mean ± std across folds. **The spread matters more
than the mean**: a model that is excellent on 12 people and useless on 3 is a
different product from one that is uniformly decent.

ECE is reported because the app displays the probability as a percentage.
That display makes an implicit claim — windows called 70% were stressed about
70% of the time — so the claim gets measured.

Published WESAD binary results sit around 85–93%, but those mostly use longer
windows and more features. **Put the number this pipeline actually measures in
the model card, not that one.**

A gradient-boosted-tree baseline runs on the same split to show what five
tabular features can support. If the shipped MLP trails it badly, that gap
belongs in the model card rather than being quietly dropped.

## Sanity check before believing any metric

Meditation windows are excluded from training and scored at the end. A correct
model should not rank them **above** baseline. If it does, something is wrong in
extraction or labelling, and the headline metrics are not meaningful yet.

**Comparing the two mean probabilities cannot decide this, and on this dataset
it does not.** The run returns 0.227 for meditation against 0.224 for baseline:
both sit on the floor of the calibrated scale, because the model separates
stress from rest and both of these are rest. A strict `meditation < baseline`
test on those two numbers reports a failure that is really a coin flip.

So `train.py` asks the question the check is actually about - does the model
*rank* meditation below baseline - as an AUROC over the pooled out-of-fold
windows, and reports three outcomes rather than two:

| AUROC | Verdict | Meaning |
| --- | --- | --- |
| < 0.50 | FAIL | wrong direction; fix extraction before trusting anything |
| 0.50-0.55 | INDIFFERENT | the model does not separate the two rest states |
| >= 0.55 | PASS | meditation ranks calmer, as the protocol says it should |

This model measures 0.513: indifferent. That is expected behaviour for a binary
stress detector once both classes sit far from its decision boundary, and it is
not evidence of a bug - the extracted features do differ in the right direction
(meditation has lower HR and higher HRV than baseline, by a clear margin in
`windows.csv`). It is also **not a pass**, and nothing about it licenses a claim
that the model can tell calm from very calm. Worth holding onto, given that the
app bands that one probability into five levels.
