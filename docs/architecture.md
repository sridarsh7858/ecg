# Architecture

NeuroPulse is a Flutter application organised in four layers. Dependencies
point in one direction only: `features` depends on `state`, which depends on
`domain` and `data`. Nothing in `data` or `domain` imports a screen.

```
              ┌─────────────────────────────────────────┐
              │  features/   screens and widgets        │
              └───────────────────┬─────────────────────┘
                                  │ reads / calls
              ┌───────────────────▼─────────────────────┐
              │  state/      ChangeNotifier controllers  │
              └───────────────────┬─────────────────────┘
                     ┌────────────┴────────────┐
       ┌─────────────▼───────────┐  ┌──────────▼──────────────┐
       │  domain/   engine,      │  │  data/   models,        │
       │            data source, │  │          repositories,  │
       │            games        │  │          local store    │
       └─────────────────────────┘  └─────────────────────────┘
```

## The pipeline

This is the contract the whole project is built around, and it does not change
when the hardware and the trained model arrive:

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

Both ends are interfaces. The engine end already resolves to
`MLStressPredictionService`, the trained TFLite model; the input end resolves to
`DemoPhysiologicalDataSource` or `ManualPhysiologicalDataSource` today and to
`BlePhysiologicalDataSource` when the wearable lands. The middle of the diagram
— the models and everything above them — is unchanged in every case, which is
the point of the seam: swapping the demo heuristic for the trained model touched
one line here and no screen at all.

## Composition root

`lib/app/dependencies.dart` is the only file that names concrete
implementations. It builds the object graph once at startup, before the first
frame, and hands it to `NeuroPulseApp`.

```dart
final predictionService = MLStressPredictionService();          // the engine
final demoDataSource    = DemoPhysiologicalDataSource(...);    // the input
```

Because every screen resolves its collaborators from Provider rather than
constructing them, swapping either line changes the whole app.

## Directory map

| Path | Holds |
| --- | --- |
| `lib/app/` | Root widget, root gate, composition root |
| `lib/core/theme/` | Colour tokens, spacing scale, motion, Material 3 themes |
| `lib/core/widgets/` | Reusable widgets: cards, gauge, charts, HRV grid |
| `lib/core/utils/` | Date and number formatting |
| `lib/data/models/` | Typed models, each with `toJson` / `fromJson` |
| `lib/data/local/` | `LocalStore`, a JSON wrapper over SharedPreferences |
| `lib/data/repositories/` | Repository interfaces plus local implementations |
| `lib/domain/stress/` | Stress levels, scoring, prediction services |
| `lib/domain/physiological/` | Data source interface, demo source, BLE stub |
| `lib/domain/games/` | Game catalogue, recommendation, session manager |
| `lib/features/` | One folder per screen area |
| `lib/state/` | `AuthController`, `SettingsController`, `StressController` |

## State management

`provider` with `ChangeNotifier`. Three controllers, each with one job:

- **`AuthController`** — the signed-in user and the onboarding flag.
- **`SettingsController`** — `AppSettings`, persisted on every change.
- **`StressController`** — the current estimate, the demo level, the baseline,
  and the session history. This is the hub: when the demo level changes here,
  the dashboard, the recommendation, the measure screen and the result screen
  all follow, because they all read from it.

`MeasureController` is a fourth, shorter-lived controller scoped to the measure
screen. It owns one measurement: stream, then predict.

## Repositories

Every repository is an interface with a local implementation:

| Interface | Local implementation |
| --- | --- |
| `AuthRepository` | `LocalAuthRepository` |
| `UserRepository` | `LocalUserRepository` |
| `MeasurementRepository` | `LocalMeasurementRepository` |
| `GameSessionRepository` | `LocalGameSessionRepository` |

Firebase is not a dependency of this build and is not required to run the app.
When credentials exist, add `FirebaseAuthRepository`, `FirestoreMeasurement‐
Repository` and so on implementing the same interfaces, and change the
composition root. No UI code refers to a repository implementation.

## Storage

`LocalStore` wraps `SharedPreferences` with JSON get/set helpers. Everything
persisted today is small — a profile, settings, a few hundred session records —
so a document database would be over-engineering. Corrupt values are dropped
rather than thrown, so a bad write from an older build cannot brick the app.

Keys are declared as constants on `LocalStore`, and `clearAll()` removes
exactly the keys this app owns.

## Dependencies

Deliberately minimal, so the project keeps building as the Flutter SDK moves:

- `provider` — state management
- `shared_preferences` — local persistence
- `crypto` — password hashing for the local prototype auth

Charts are drawn with `CustomPaint` (`lib/core/widgets/trend_chart.dart`)
rather than pulling in a charting package. The games are plain Flutter —
`Ticker`, `AnimationController` and `CustomPaint` — with no game engine.

## Testing

`flutter test` runs 100 tests with no device or emulator:

| File | Covers |
| --- | --- |
| `stress_level_test.dart` | The five levels and their configuration |
| `dummy_stress_prediction_test.dart` | Scoring, the demo engine, level round trip |
| `game_recommendation_test.dart` | Catalogue and level-to-game mapping |
| `game_session_manager_test.dart` | Session building and post-level simulation |
| `serialization_test.dart` | JSON round trip for every model |
| `measure_controller_test.dart` | The measurement flow and the BLE stub |
| `games_test.dart` | All five games driven for real |
| `app_flow_test.dart` | Onboarding, auth, navigation, dashboard, history |


## Physiological data flow

Three interchangeable data sources feed one model. Nothing downstream of the
packet knows which produced it.

```
   Demo  ─┐
   Manual ┼─▶ PhysiologicalInputPacket ─▶ StressFeatureVector ─▶ StressPredictionService
   BLE   ─┘        (all fields nullable)      (via FeatureRegistry)        │
                                                                          ▼
                                    history ◀─ game ◀─ recommendation ◀─ Level 1–5
```

| Concern | Type | File |
| --- | --- | --- |
| The one input model | `PhysiologicalInputPacket` | `data/models/physiological_input_packet.dart` |
| Raw ECG bursts | `RawEcgPacket`, `RawEcgBuffer` | `data/models/raw_ecg_packet.dart` |
| Which mode is active | `MeasurementModeController` | `state/measurement_mode_controller.dart` |
| Demo source | `DemoPhysiologicalDataSource` | `domain/physiological/` |
| Manual source | `ManualPhysiologicalDataSource` | `domain/physiological/` |
| BLE source | `BlePhysiologicalDataSource` | `domain/physiological/` |
| BLE abstraction | `BleService` | `domain/ble/ble_service.dart` |
| BLE implementation | `FlutterBlueBleService` | `domain/ble/flutter_blue_ble_service.dart` |
| BLE simulator | `FakeBleService` | `domain/ble/fake_ble_service.dart` |
| Wire format | `BleProtocol`, `BleUuids` | `domain/ble/ble_protocol.dart` |
| Sensor detection | `DeviceCapabilities` | `domain/ble/device_capabilities.dart` |
| ML feature set | `FeatureRegistry`, `StressFeatureVector` | `domain/stress/` |
| Engine contract | `StressPredictionService` | `domain/stress/` |

### Two boundaries that matter

**`flutter_blue_plus` is imported in exactly one file.** Everything above
`BleService` sees plain Dart types, which is what allows `FakeBleService` to
drive the entire Bluetooth path — scan, connect, capabilities, streaming,
malformed packets — in a widget test with no radio and no plugin.

**The engine is named in exactly one place.** `lib/app/dependencies.dart` is
the only file that mentions a concrete `StressPredictionService`. Swapping the
demo heuristic for a trained model is a one-line change there.

### Related documents

- [`physiological_inputs.md`](physiological_inputs.md) — the inputs and the
  rules about what they do and do not mean
- [`ble_protocol.md`](ble_protocol.md) — the firmware contract
- [`esp32_integration.md`](esp32_integration.md) — the hardware side
- [`manual_mode.md`](manual_mode.md) / [`demo_mode.md`](demo_mode.md) — running
  without hardware
- [`future_ml_training.md`](future_ml_training.md) — where a model plugs in
