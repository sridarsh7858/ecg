import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/app/app.dart';
import 'package:neuropulse/app/dependencies.dart';
import 'package:neuropulse/data/local/local_store.dart';
import 'package:neuropulse/domain/ble/ble_service.dart';
import 'package:neuropulse/domain/stress/dummy_stress_prediction_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared setup for widget tests.
///
/// Builds the real object graph over mocked SharedPreferences and a zero-delay
/// engine, so tests exercise the same wiring the app uses at runtime.
class TestHarness {
  const TestHarness._();

  /// Builds dependencies with [initialPrefs] already in local storage.
  ///
  /// [bleService] lets a test drive the whole Bluetooth path with a
  /// [FakeBleService]. When omitted the real service is built, which in a
  /// `flutter test` process has no platform channel and correctly reports
  /// itself unsupported - exactly what a device without BLE would do.
  static Future<AppDependencies> dependencies({
    Map<String, Object> initialPrefs = const {},
    BleService? bleService,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    return AppDependencies.bootstrap(
      store: await LocalStore.open(),
      predictionServiceOverride: DummyStressPredictionService(),
      bleServiceOverride: bleService,
    );
  }

  /// Prefs representing a user who has finished onboarding and is signed in.
  static Map<String, Object> signedInPrefs({
    String name = 'Asha Ramesh',
    String email = 'asha@example.com',
    int age = 21,
  }) {
    return {
      LocalStore.keyOnboardingSeen: true,
      LocalStore.keyCurrentUserId: 'u_test',
      LocalStore.keyUsers:
          '[{"id":"u_test","name":"$name","email":"$email","age":$age,'
          '"createdAt":"2026-09-01T00:00:00.000Z","avatarSeed":"$email"}]',
    };
  }

  /// Pumps the full app and waits for the first frame to settle.
  static Future<AppDependencies> pumpApp(
    WidgetTester tester, {
    Map<String, Object> initialPrefs = const {},
    Size surfaceSize = const Size(420, 900),
    BleService? bleService,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final deps = await dependencies(
      initialPrefs: initialPrefs,
      bleService: bleService,
    );
    await tester.pumpWidget(NeuroPulseApp(dependencies: deps));
    await tester.pumpAndSettle();
    return deps;
  }
}
