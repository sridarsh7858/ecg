# ML training

> **This has happened.** The model described here as future work was trained on
> WESAD and ships in the app as `ml-1.0.0`. The seam below is the one it was
> slotted into, unchanged. For what was actually measured, read the generated
> [model card](../mobile/assets/models/model_card.md); for how to reproduce it,
> [`training/README.md`](../training/README.md). The rest of this document
> still describes the architecture correctly.

This document describes where the trained model slots in, and what was built so
that slotting it in required no redesign.

## Where things stand

```
SHIPPED
  Demo / Manual / BLE
    ─▶ PhysiologicalInputPacket
    ─▶ StressFeatureVector        (via FeatureRegistry)
    ─▶ MLStressPredictionService  (TFLite, on-device)
    ─▶ StressPrediction ─▶ Level 1–5 ─▶ game

HOW THE MODEL GOT THERE
  WESAD
    ─▶ preprocessing ─▶ feature extraction   (training/preprocess.py, hrv.py)
    ─▶ leave-one-subject-out training        (training/train.py)
    ─▶ calibration ─▶ TFLite export          (training/export.py)
    ─▶ mobile/assets/models/
```

`DummyStressPredictionService` is still in the codebase: tests use it for a
deterministic engine, and `MLStressPredictionService` degrades to it - relabelling
itself as the demo engine - if the model asset will not load.

Only the engine changes. The UI, controllers, repositories and games are written
against `StressPredictionService` and never see a concrete engine.

## What the current engine actually is

`DummyStressPredictionService` normalises each available HRV feature to 0–1 over
a plausible adult range, inverts the ones where lower means more aroused,
combines them with fixed weights, and cuts the result into five equal bands.
That is the whole thing. It is written out in full in the class doc comment so
nobody can mistake it for something that learned from data.

It reports `isDemo == true` and `modelVersion == "demo-1.0.0"`, and the UI
labels every result accordingly.

One detail worth keeping in a real engine: weights are **renormalised over the
features actually present**. A missing SDNN does not vote "calm" — it does not
vote at all. Confidence drops instead, which is the honest response to having
less to go on.

## The insertion point

```dart
class MLStressPredictionService extends StressPredictionService {
  @override bool get isDemo => false;
  @override String get modelVersion => 'ml-1.0.0';
  @override String get displayName => 'Stress Model v1';
  @override FeatureRegistry get featureRegistry => _registry;

  @override
  Future<void> initialise() async { /* load the asset */ }

  @override
  Future<StressPrediction> predictFromVector(StressFeatureVector vector) async {
    /* run the model */
  }
}
```

Then change one line in `lib/app/dependencies.dart`. That is the entire
integration. There is no UI work.

## The feature registry

`FeatureRegistry` decides which features the engine receives and **in what
order**. Order comes from the declaration order of the `StressFeature` enum, not
from set iteration, so it is stable across runs and platforms — a silently
transposed feature vector is a classic way to ship a model that quietly does
nothing.

Available today:

| Key | Group | Enabled by default |
| --- | --- | --- |
| `hr` | cardiovascular | yes |
| `meanRR` | cardiovascular | yes |
| `rmssd` | cardiovascular | yes |
| `sdnn` | cardiovascular | yes |
| `pnn50` | cardiovascular | yes |
| `gsrLevel` | electrodermal | **no** |
| `gsrPeaks` | electrodermal | **no** |
| `movementIntensity` | movement | **no** |

When a dataset arrives, build the registry from its columns:

```dart
FeatureRegistry.forDatasetColumns(['hr', 'rmssd', 'sdnn', 'gsrLevel'])
```

It enables the intersection of what the dataset has and what the app can
extract, and ignores the rest.

## Missing features are the engine's problem, deliberately

`StressFeatureVector` keeps values nullable all the way to the engine and
exposes `missingFeatures`, `presentFeatures` and `completeness`. Densifying
requires an explicit substitute:

```dart
vector.toDense((feature) => trainingSetMean[feature]!);
```

There is no default. Imputation is a modelling decision and has to be made
visibly by whoever trains the model, not silently by a data class.

## Do not fix the dataset now

The brief is explicit and it is correct: the dataset determines which features
are available, which sensors are represented, which labels exist, and which
model is appropriate. Choosing now would mean building the app around
assumptions that the data may contradict.

Some things worth deciding **when** you have data, not before:

- **Window length must match the app.** HRV features are window-length
  dependent — SDNN over 30 s is not the same quantity as SDNN over the 5-minute
  windows most HRV papers report. The app captures 30 s
  (`MeasureController`), so train on 30 s or change both together.
- **Split by subject, never randomly.** A random split puts the same person's
  beats on both sides, and resting heart rate alone then identifies the subject.
  The accuracy figure would measure nothing.
- **Firmware parity.** Whatever preprocessing the training pipeline applies to
  raw ECG, the ESP32 must reproduce exactly — same filter, same refractory
  period, same artefact rejection, same definition of SDNN. Otherwise the model
  meets a feature distribution in the field that it never saw in training, and
  performs worse on hardware than the offline numbers suggest.
- **Five levels from fewer classes.** No public dataset has five stress levels.
  If the model outputs one probability, band it with
  `StressScoring.levelForScore()` and say plainly in the model card that the
  five levels are a banding of one number, not five validated states.

## When you do ship a model

Put the numbers you measured in a model card — not numbers from a paper.
Report the spread across subjects, not just the mean: a model that is excellent
on twelve people and useless on three is a different product from one that is
uniformly decent.
