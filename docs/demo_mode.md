# Demo mode

Runs the entire app on simulated values, with no hardware and no typing. It is
the default mode on first launch.

## What it does

`DemoPhysiologicalDataSource` generates a feature vector for a requested stress
level by **inverting the scoring maths** the demo engine uses. That makes the
demo end-to-end self-consistent: ask for level 4, get level-4-looking features,
and the engine scores them as level 4. A test pins this round trip for all five
levels.

It also simulates the optional sensors — GSR, accelerometer, gyroscope, battery,
signal quality — so every panel in the UI can be exercised. All of it is tagged
`DEMO` and displayed as **Demo data**.

Demo mode is the *only* mode that fabricates optional sensor values. Bluetooth
mode never does.

## Choosing the level

Profile → Settings → **Developer / demo mode** → pick a level. The whole app
follows: dashboard, next measurement, recommended game.

## Simulating the wearable without a wearable

`FakeBleService` is a full `BleService` implementation that behaves like a
device: it advertises `NeuroPulse-ESP32 (Simulated)`, takes realistic time to
scan and connect, declares capabilities, and streams packets.

Crucially, it emits **encoded JSON through the real `BleProtocol` parser**
rather than constructing packets directly. Every simulated packet therefore
exercises the same parsing and validation the firmware output will hit, and the
JSON shape stays honest — if the real firmware sends what the fake sends, it
parses.

Install it at the composition root:

```dart
AppDependencies.bootstrap(bleServiceOverride: FakeBleService());
```

Tests do this constantly (`test/data_source_modes_test.dart`). It also accepts
arbitrary payloads, which is how the "malformed packet does not drop the link"
test works:

```dart
service.emitRaw('{ this is not json');
```

## Testing all five levels without hardware

1. Developer panel → select each level → check Home and the recommendation.
2. Or Measure → Manual → **Quick Demo** → Level 1…5 → ANALYZE.
3. Or unit-level: `test/physiological_input_test.dart` sweeps the score axis and
   asserts all five levels are reachable and round-trip correctly.

## Honesty rules

- Every demo reading is tagged `DEMO` and badged **Demo data** on screen.
- The engine is shown as **Demo Stress Engine**, never as AI or a model.
- No accuracy figure is displayed anywhere, because none has been measured.
- Demo values are illustrative. They are not medically validated and are not
  measurements of anyone.

Demo mode exists to demonstrate and test the application, not to suggest the
application can measure stress today.
