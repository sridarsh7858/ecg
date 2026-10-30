# NeuroPulse

**ECG-Based Stress Level Estimation with Gamified Biofeedback**

A Flutter mobile application that estimates a stress level from heart-rate
variability features, suggests a calming activity to match, and tracks how
things change over time.

The app runs end to end today on simulated physiological data and a **trained
stress model** — a 4.7 KB TFLite classifier learned from WESAD chest ECG, which
runs on-device with no network. ECG hardware is the remaining piece: the BLE
interface and GATT contract are defined, and nothing above them has to change
when the wearable lands.

---

## Status

| Component | State |
| --- | --- |
| Mobile application | Complete and running |
| Physiological data | Simulated (`DemoPhysiologicalDataSource`) |
| Stress engine | Trained model (`MLStressPredictionService`, `ml-1.0.0`) |
| ESP32 + AD8232 over BLE | Interface and GATT contract defined, not implemented |
| Trained ML model | WESAD, 15 subjects, leave-one-subject-out. 0.790 ± 0.128 accuracy, 0.927 ± 0.117 AUROC. See the [model card](mobile/assets/models/model_card.md) |
| Storage | Local, on-device |
| Tests | 189 passing, `flutter analyze` clean |

Every accuracy figure in this repository was measured by `training/train.py` on
this dataset; none is quoted from a paper. Simulated input is still labelled as
demo data in the UI, independently of which engine scored it — the badge
describes where the *data* came from, the model version describes what scored
it.

---

## The pipeline

Where the project is heading:

```
ECG hardware → AD8232 → ESP32 → HR/RR/HRV features → BLE
    → Mobile app → ML model → Stress level 1–5
    → Recommended game → Biofeedback → Re-measurement
```

What runs today:

```
Demo / Manual inputs → Trained model (TFLite, on-device) → Stress level 1–5
    → Recommended game → Game → Simulated post-session result → History
```

Both flows use the *same* interfaces, models and screens. Only the two ends
differ.

```
PhysiologicalDataSource  ──▶  PhysiologicalFeatures
                                       │
                                       ▼
                          StressPredictionService
                                       │
                                       ▼
                              StressPrediction
                                       │
                                       ▼
                    Application (dashboard, games, history)
```

---

## Architecture

Four layers, dependencies pointing one way:

```
features/  →  state/  →  domain/ + data/
```

- **`lib/app/`** — root widget and the composition root
- **`lib/core/`** — theme tokens, shared widgets, formatting
- **`lib/data/`** — typed models, local store, repository interfaces
- **`lib/domain/`** — stress levels and engine, data sources, game system
- **`lib/features/`** — one folder per screen area
- **`lib/state/`** — three `ChangeNotifier` controllers

`lib/app/dependencies.dart` is the **only** file that names a concrete
implementation. Swapping the demo engine for a trained model, or local storage
for Firebase, is a change there and nowhere else.

Dependencies are deliberately minimal: `provider`, `shared_preferences`,
`crypto`. Charts are hand-drawn with `CustomPaint`; the games use no game
engine.

Full detail: [`docs/architecture.md`](docs/architecture.md).

---

## Features

**Onboarding** — four short slides, skippable, shown once.

**Accounts** — register, sign in, forgot password, log out. Local and offline,
behind `AuthRepository`. Collects a name, email, age and password only.

**Home** — greeting, an animated stress gauge, the four HRV values with
baseline comparison, the recommended activity with a large PLAY NOW button, and
tappable streak and average stats.

**Measure** — a polished `START → MEASURING → PROCESSING → RESULT` flow with a
countdown, progress bar, live ECG-style trace, and live HR / R-R / signal
readouts. Duration configurable from 15 to 60 seconds.

**Stress result** — the estimated level, the readings behind it, expandable
details, the recommended game, and save-to-history.

**Games** — five real playable mini-games, each adapting to the current
estimate.

**History** — 7 / 30 / 90-day filters, trend charts for stress level, heart
rate and RMSSD, a session list, and a full record for each session.

**Profile** — account, four statistics, the calm baseline with per-feature
comparison, and the current device / data source / model.

**Settings** — theme, reduce motion, demo mode, measurement duration, sound,
haptics, data export, clear history, and the developer panel.

Full detail: [`docs/app_features.md`](docs/app_features.md).

---

## Stress levels

| # | Title | Recommendation |
| --- | --- | --- |
| 1 | Very Low | Maintain your relaxed state with a gentle activity. |
| 2 | Low | A light, playful session will keep things steady. |
| 3 | Moderate | A short focus or breathing session can help you reset. |
| 4 | High | Take a short calming break with guided breathing. |
| 5 | Very High | Give yourself a longer guided breathing session. |

Everything about a level — title, description, recommendation, motivational
line, suggested games, icon, colours — lives in `StressLevelConfig`, in one
file. Nothing else in the app hard-codes level semantics.

The demo engine scores four HRV features (`hr`, `rmssd`, `sdnn`, `pnn50`) into
a 0..1 arousal score and buckets it into five equal bands. The demo data
generator **inverts** that same maths, so asking for level 4 produces
level-4-looking numbers that the engine genuinely scores as level 4 — the demo
is self-consistent rather than cosmetic.

> The heuristic is for demonstrating the application. It is not a validated
> physiological model and makes no clinical claim.

Full detail: [`docs/stress_system.md`](docs/stress_system.md).

---

## Games

| Game | Mechanic | Adapts to level |
| --- | --- | --- |
| **Calm Breathing** | Paced breathing circle, 4 s in / 6 s out | Session length, 90 s → 180 s |
| **Pulse Runner** | Endless runner, tap to hop | Speed and obstacle spacing |
| **Zen Garden** | Place stones, flowers, water; persists | Open-ended |
| **Focus Blocks** | Memory sequence on a 3×3 grid | Sequence length and flash speed |
| **Calm Catch** | Catch falling stars, leaves, droplets | Fall speed and distractions |

A higher reading always makes a game calmer and slower, never harder. Nothing
punishes the user for being stressed.

### Recommendation mapping

| Level | Primary | Also offered |
| --- | --- | --- |
| 1 | Zen Garden | Calm Catch, Pulse Runner |
| 2 | Zen Garden | Calm Catch, Pulse Runner |
| 3 | Calm Breathing | Focus Blocks, Calm Catch |
| 4 | Calm Breathing | Zen Garden, Calm Catch |
| 5 | Calm Breathing | Zen Garden |

Shown on Home, on the stress result screen, and pinned atop the Games screen.

### Biofeedback loop

```
Check-in → level → recommended game → play → session
        → simulated post-session level → before/after → History
```

The post-session level is a demo rule (a meaningfully completed session lowers
the estimate by one; a fully completed calming session at level 4–5 lowers it
by two, never below 1). The result screen says the value is simulated and
describes a *change in the estimate* — it never claims a game treated anything.

Full detail: [`docs/game_system.md`](docs/game_system.md).

---

## How to run

Requires Flutter 3.35+ (built against 3.47.2).

```bash
cd mobile
flutter pub get
flutter run
```

Create an account with any name, email, age and a six-character password. It is
stored on the device; no network call is made.

Builds:

```bash
flutter build apk --release     # Android
flutter build appbundle         # Play Store
flutter build ios               # macOS + Xcode required
```

---

## How to test

```bash
cd mobile
dart format .
flutter analyze                 # expected: no issues
flutter test                    # 100 tests, no device needed
```

| Suite | Covers |
| --- | --- |
| `stress_level_test.dart` | The five levels and their configuration |
| `dummy_stress_prediction_test.dart` | Scoring, demo engine, level round trip |
| `game_recommendation_test.dart` | Catalogue and level-to-game mapping |
| `game_session_manager_test.dart` | Session building, post-level simulation |
| `serialization_test.dart` | JSON round trip for every model |
| `measure_controller_test.dart` | Measurement flow and the BLE stub |
| `games_test.dart` | All five games driven for real |
| `app_flow_test.dart` | Onboarding, auth, navigation, dashboard, history |

---

## Demo mode

The app ships in demo mode; every simulated value is labelled in the UI.

**Settings → Developer / demo mode**

- **Select stress level 1–5** — the whole app follows: Home, the recommended
  game, the next measurement, the result screen and what gets saved to History.
- **Generate demo measurement** — saves a check-in straight to History.
- **Seed 60 days of history** — populates the trend charts.
- **View current dummy feature vector** — shows HR / RMSSD / SDNN / pNN50, the
  computed arousal score, the predicted level and the confidence.
- **Test recommended game**, **reset baseline**, **clear history**.

To verify a level end to end: pick the level, go to Measure, run a check-in,
confirm the result screen shows that level, save it, then find it in History.

---

## Future hardware integration

```
Electrodes → AD8232 → ESP32 → R-peak detection → R-R intervals
    → HRV features → BLE GATT → BlePhysiologicalDataSource → app
```

Feature computation happens **on the ESP32**; the phone receives a finished
feature vector, so the raw ECG never leaves the device.

`BlePhysiologicalDataSource` already exists, implements the interface, reports
itself unavailable, and publishes the GATT contract — service and characteristic
UUIDs, packet layouts and control commands — as constants pinned by a test.
Firmware can be written against it today.

Enabling it: add `flutter_blue_plus`, add the platform permissions, implement
the methods in that one file, and switch the active source at the composition
root. No screen changes.

Full detail: [`docs/ble_architecture.md`](docs/ble_architecture.md).

---

## The stress model

Everything depends on one interface, and only the engine behind it changed:

```dart
abstract class StressPredictionService {
  String get modelVersion;
  String get displayName;
  bool   get isDemo;
  Future<void> initialise();
  Future<StressPrediction> predict(PhysiologicalFeatures features);
  Future<void> dispose();
}
```

| | Demo engine | Shipped engine |
| --- | --- | --- |
| Implementation | `DummyStressPredictionService` | `MLStressPredictionService` |
| `modelVersion` | `demo-1.0.0` | `ml-1.0.0` |
| `isDemo` | `true` | `false` |
| Input / output | `PhysiologicalFeatures` → `StressPrediction` | unchanged |

The integration was: export the artefacts into `mobile/assets/models/`, add
`tflite_flutter`, write the new class, and change one line in
`lib/app/dependencies.dart`. No screen, controller, repository or model changed,
which is what the seam was for. The demo engine stays in the codebase for tests,
for offline demos, and as the documented fallback.

### What it learned, and what it did not

WESAD (Schmidt et al., ICMI 2018), 15 subjects of chest ECG at 700 Hz, cut into
the same 30-second windows the app captures, scored leave-one-subject-out:

| Metric | LOSO, 15 folds |
| --- | --- |
| Accuracy | 0.790 ± 0.128 (worst subject 0.473) |
| Macro F1 | 0.683 ± 0.211 |
| AUROC | 0.927 ± 0.117 |
| Expected calibration error | 0.195 ± 0.082 |

Three things worth knowing before quoting those numbers:

- **The spread is the story.** The model is strong on most subjects and close to
  useless on the worst one. A mean of 0.790 across 15 people describes a
  different product from 0.790 on everyone.
- **The percentage the UI shows is not a reliable frequency.** An ECE of 0.195
  means windows called 70% were not stressed 70% of the time.
- **Five levels are a banding of one number.** The model outputs a single
  probability; `StressScoring.levelForScore()` cuts it into the five existing
  levels. No dataset provides five-level stress ground truth, and the model is
  measurably indifferent between resting and deeply relaxed states.

Nothing here has been validated on AD8232 dry-electrode data. Until the firmware
reproduces `training/hrv.py` exactly, on-device accuracy is unknown.

Full detail: the generated [model card](mobile/assets/models/model_card.md) and
[`training/README.md`](training/README.md).

---

## Disclaimer

> NeuroPulse is a student research and wellness prototype. Stress estimates are
> based on physiological signals and machine-learning models and are not medical
> diagnoses. This application is not intended to diagnose, treat, cure, or
> prevent disease.

All data is stored on the device. Nothing is uploaded. The app collects a name,
email and age, and no other personal information.

---

## Documentation

| Document | Contents |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | Layers, composition root, state, storage |
| [`docs/app_features.md`](docs/app_features.md) | Every screen, accessibility, responsiveness |
| [`docs/stress_system.md`](docs/stress_system.md) | The five levels, scoring maths, baseline |
| [`docs/game_system.md`](docs/game_system.md) | Game architecture and all five games |
| [`docs/ble_architecture.md`](docs/ble_architecture.md) | GATT contract and enablement steps |
| [`training/README.md`](training/README.md) | The training pipeline, and the four things easy to get wrong |
| [`mobile/assets/models/model_card.md`](mobile/assets/models/model_card.md) | Measured metrics, provenance, limitations |
| [`docs/future_ml_integration.md`](docs/future_ml_integration.md) | Design history of the engine seam |
| [`docs/setup.md`](docs/setup.md) | Install, run, test, troubleshoot |
