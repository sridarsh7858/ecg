> **Historical. Superseded by [`future_ml_training.md`](future_ml_training.md).**
>
> The model has since been trained and integrated. Two details below were
> deliberately *not* followed: Dart does not load `feature_scaler.json` and does
> not scale (the scaler and the calibration are baked into the TFLite graph, so
> the app passes raw features and receives a probability), and the model emits
> one calibrated probability rather than five class scores. See
> `training/export.py` and `mobile/assets/models/README.md`.
>
> This document planned the ML integration around `PhysiologicalFeatures` and a
> Dart-side feature scaler. The implemented architecture instead passes a
> `StressFeatureVector` built through a `FeatureRegistry`, which keeps missing
> sensors nullable all the way to the engine and lets the feature set be
> matched to whatever dataset eventually arrives. Where the two disagree,
> `future_ml_training.md` is correct. Kept for design history.

# Future ML integration

This document explains exactly how the trained model replaces
`DummyStressPredictionService`. **No model is trained in this phase**, and no
placeholder model file is committed — a fake model would make the app look as
though it were producing trained predictions when it is not.

## The seam

Every consumer in the app depends on one interface:

```dart
// lib/domain/stress/stress_prediction_service.dart
abstract class StressPredictionService {
  String get modelVersion;                 // "demo-1.0.0" -> "ml-1.0.0"
  String get displayName;                  // shown in Profile and About
  bool   get isDemo;                       // drives the "Demo data" badges

  Future<void> initialise();
  Future<StressPrediction> predict(PhysiologicalFeatures features);
  Future<void> dispose();
}
```

| | Today | After training |
| --- | --- | --- |
| Implementation | `DummyStressPredictionService` | `MLStressPredictionService` |
| `modelVersion` | `demo-1.0.0` | `ml-1.0.0` |
| `displayName` | `Demo Stress Engine` | `ML Model v1.0` |
| `isDemo` | `true` | `false` |
| Input | `PhysiologicalFeatures` | `PhysiologicalFeatures` (unchanged) |
| Output | `StressPrediction` | `StressPrediction` (unchanged) |

Because the input and output types do not change, **no screen, controller,
repository or model changes**. The dashboard, measure flow, recommendation,
result screen and history all keep working as they are.

## What changes, concretely

### 1. Add the model artefacts

Drop the exported model into the folder that already exists:

```
mobile/assets/models/
  stress_model.tflite      # 4 features -> 5 classes
  feature_scaler.json      # normalisation constants used in training
  model_card.md            # dataset, metrics, limitations, version
```

`assets/models/` is already declared in `pubspec.yaml`, so no manifest change
is needed.

### 2. Add the runtime dependency

```yaml
dependencies:
  tflite_flutter: ^0.11.0    # or whichever runtime the export targets
```

### 3. Write the new implementation

```dart
// lib/domain/stress/ml_stress_prediction_service.dart
class MLStressPredictionService implements StressPredictionService {
  MLStressPredictionService({this.assetPath = 'assets/models/stress_model.tflite'});

  final String assetPath;
  Interpreter? _interpreter;
  late FeatureScaler _scaler;

  @override String get modelVersion => 'ml-1.0.0';
  @override String get displayName  => 'ML Model v1.0';
  @override bool   get isDemo       => false;

  @override
  Future<void> initialise() async {
    _interpreter ??= await Interpreter.fromAsset(assetPath);
    _scaler = await FeatureScaler.loadFromAsset(
      'assets/models/feature_scaler.json',
    );
  }

  @override
  Future<StressPrediction> predict(PhysiologicalFeatures f) async {
    // 1. Scale exactly as in training - same order, same constants.
    final input = [_scaler.transform([f.hr, f.rmssd, f.sdnn, f.pnn50])];
    final output = List.filled(1 * 5, 0.0).reshape([1, 5]);

    // 2. Run inference.
    _interpreter!.run(input, output);

    // 3. Take the argmax as the level and the softmax peak as confidence.
    final probabilities = (output[0] as List).cast<double>();
    final index = _argMax(probabilities);
    final level = StressLevel.fromNumber(index + 1);

    return StressPrediction(
      level: level,
      label: StressLevelConfig.of(level).title,
      confidence: probabilities[index],
      features: f,
      timestamp: DateTime.now(),
      source: f.source,          // DEMO or BLE - describes the input data
      modelVersion: modelVersion,
    );
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }
}
```

### 4. Flip one line at the composition root

```dart
// lib/app/dependencies.dart
final predictionService = MLStressPredictionService();
```

That is the entire integration. `initialise()` is already awaited by
`StressController.load()` during startup.

### 5. Update the tests

`dummy_stress_prediction_test.dart` stays as it is — the demo engine remains in
the codebase for offline demos and for tests that need a deterministic engine.
Add `ml_stress_prediction_test.dart` asserting that the loaded model produces a
level in 1..5 and a confidence in 0..1 for known input vectors.

## What the app does automatically

Once `isDemo` returns `false`:

- The **"Demo data"** badges stop appearing wherever the source is no longer
  `DEMO`.
- **Profile** shows `ML Model v1.0` in place of `Demo Stress Engine`.
- **History** records the new `modelVersion` on every session, so old demo
  sessions and new model sessions stay distinguishable forever.
- The **result screen** footer reports the engine that produced the estimate.

No code change is needed for any of these — they already read from the service.

## Training pipeline (a later, separate phase)

Not part of this repository yet. When the dataset is provided:

```
Dataset  ─▶  ECG preprocessing  ─▶  R-peak detection  ─▶  R-R intervals
   ─▶  HRV features (hr, meanRR, rmssd, sdnn, pnn50)
   ─▶  Label mapping to the five project levels
   ─▶  Train / validate / test split
   ─▶  Training and evaluation
   ─▶  Export (.tflite) + scaler constants + model card
   ─▶  MLStressPredictionService
   ─▶  Flutter app
```

Two rules for that phase:

1. **The feature contract is fixed.** The pipeline must emit exactly
   `hr, meanRR, rmssd, sdnn, pnn50`, in that order, in the units documented in
   `stress_system.md`. If training needs different features, change
   `PhysiologicalFeatures` first and let the compiler find every call site.
2. **Report real metrics only.** The model card records the actual dataset,
   split, and evaluation numbers. Nothing in the app should claim an accuracy
   figure that has not been measured.

## Personal baseline

`Baseline` is currently stored for visualisation only and is not an input to
prediction. If the trained model benefits from per-user normalisation, that is
a deliberate design decision to make at training time — pass the baseline into
`MLStressPredictionService` explicitly rather than having it leak in.
