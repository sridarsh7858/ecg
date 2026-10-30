# Setup

## Requirements

- Flutter **3.35+** (stable). Built and tested against Flutter 3.47.2 / Dart 3.13.2.
- Android Studio with the Android SDK, or Xcode for iOS.
- JDK 17 or newer for Android builds.

No hardware, no dataset, no model file and no Firebase project are needed. The
app is fully functional without all four.

## Install Flutter

If `flutter --version` is not on your PATH:

```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git C:\src\flutter
```

Add `C:\src\flutter\bin` to PATH, then confirm the toolchain:

```bash
flutter doctor
```

Android licences, if not already accepted:

```bash
flutter doctor --android-licenses
```

## Run the app

```bash
cd mobile
flutter pub get
flutter run
```

On first launch you will see onboarding, then the sign-in screen. Create an
account with any name, email, age and a password of six or more characters —
it is stored locally on the device, and no network call is made.

## Run the checks

```bash
cd mobile

dart format .        # formatting
flutter analyze      # static analysis, expected: no issues
flutter test         # 100 tests, no device required
```

To run one suite:

```bash
flutter test test/games_test.dart
flutter test test/dummy_stress_prediction_test.dart
```

## Build

```bash
flutter build apk --debug       # debug APK
flutter build apk --release     # release APK
flutter build appbundle         # Play Store bundle
flutter build ios               # iOS, requires macOS and Xcode
```

## Project layout

```
ecg/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── app_features.md
│   ├── stress_system.md
│   ├── game_system.md
│   ├── ble_architecture.md
│   ├── future_ml_integration.md
│   └── setup.md
└── mobile/                     the Flutter application
    ├── lib/
    ├── test/
    ├── assets/models/          empty; the trained model goes here later
    ├── android/
    ├── ios/
    └── pubspec.yaml
```

## Demo mode

The app ships in demo mode: readings are simulated on-device and labelled as
such throughout the UI. To drive it:

**Settings → Developer / demo mode**

- Select stress level 1 to 5 — the whole app follows the selection.
- Generate a demo measurement, saved straight to History.
- Seed 60 days of history to populate the charts.
- View the current dummy feature vector and what the engine makes of it.
- Test the recommended game, reset the baseline, clear history.

Settings also has the ordinary user-facing controls: theme (light / dark /
system), reduce motion, measurement duration, sound, haptics, data export and
clearing local history.

## Troubleshooting

**`flutter pub get` fails** — check network access to `pub.dev`. The project
uses only `provider`, `shared_preferences` and `crypto`.

**Gradle fails on the first Android build** — the first build downloads the
Gradle distribution and Android dependencies and can take several minutes. Let
it finish before retrying.

**Tests hang** — the games run a continuous `Ticker` by design, so
`pumpAndSettle` never settles inside a game. Use bounded `tester.pump(...)`
calls, as `test/games_test.dart` does.

**Nothing in History** — that is the correct empty state on a fresh install.
Complete a check-in, or use the developer panel to seed history.
