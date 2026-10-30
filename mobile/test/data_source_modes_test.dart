import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/physiological_input_packet.dart';
import 'package:neuropulse/domain/ble/fake_ble_service.dart';
import 'package:neuropulse/domain/physiological/physiological_data_source.dart';
import 'package:neuropulse/features/devices/devices_screen.dart';
import 'package:neuropulse/features/measure/manual_input_screen.dart';
import 'package:neuropulse/features/shell/main_shell.dart';
import 'package:neuropulse/state/device_controller.dart';
import 'package:provider/provider.dart';

import 'support/test_harness.dart';

/// Sections 15, 20, 27, 29 and 40: the three modes end to end, no hardware.
///
/// A note on structure. [FakeBleService] deliberately takes real time to scan
/// and connect, because a link that completes within one frame would not
/// exercise the intermediate states the UI has to render. `testWidgets` runs
/// in fake async where those timers never fire on their own, so anything that
/// awaits the fake wearable either runs in `tester.runAsync` or in a plain
/// `test`. That is a property of the harness, not a workaround.
void main() {
  group('mode selection', () {
    testWidgets('offers Demo, Manual and Bluetooth', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
        bleService: FakeBleService(autoStream: false),
      );

      await tester.tap(find.text('Measure'));
      await tester.pumpAndSettle();

      expect(find.text('Demo'), findsWidgets);
      expect(find.text('Manual'), findsWidgets);
      expect(find.text('Bluetooth'), findsWidgets);
    });

    testWidgets('starts in Demo and is immediately ready', (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
        bleService: FakeBleService(autoStream: false),
      );

      expect(deps.modeController.mode, MeasurementMode.demo);
      expect(deps.modeController.isReady, isTrue);
      expect(deps.modeController.blockedReason, isNull);
    });

    testWidgets('Manual mode is blocked until values are entered',
        (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
        bleService: FakeBleService(autoStream: false),
      );

      await deps.modeController.setMode(MeasurementMode.manual);
      await tester.pumpAndSettle();

      expect(deps.modeController.isReady, isFalse);
      expect(deps.modeController.blockedReason, contains('Enter your values'));

      deps.manualDataSource.submit(
        PhysiologicalInputPacket(
          timestamp: DateTime.now(),
          source: PhysiologicalSource.manual,
          heartRate: 78,
          rmssd: 35,
        ),
      );
      deps.modeController.refresh();
      await tester.pumpAndSettle();

      expect(deps.modeController.isReady, isTrue);
      expect(deps.modeController.blockedReason, isNull);
    });

    testWidgets('Bluetooth mode is blocked until a device connects',
        (tester) async {
      final service = FakeBleService(autoStream: false);
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
        bleService: service,
      );

      await deps.modeController.setMode(MeasurementMode.bluetooth);
      await tester.pumpAndSettle();

      expect(deps.modeController.isReady, isFalse);
      expect(deps.modeController.blockedReason, contains('No wearable'));

      await tester.runAsync(
        () => service.connect(FakeBleService.simulatedDevice),
      );
      await tester.pumpAndSettle();

      // Connecting must unblock Analyze without the user touching the mode
      // selector again - that wiring lives in the composition root.
      expect(deps.modeController.isReady, isTrue);
      expect(deps.modeController.blockedReason, isNull);
    });

    testWidgets('Bluetooth is never restored as the launch mode',
        (tester) async {
      // Launching straight into a mode that cannot produce a reading is a
      // worse first impression than launching into Demo.
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: {
          ...TestHarness.signedInPrefs(),
          'measurement_mode': 'ble',
        },
        bleService: FakeBleService(autoStream: false),
      );

      expect(deps.modeController.mode, MeasurementMode.demo);
    });

    testWidgets('Manual mode survives a restart, Demo is the fallback',
        (tester) async {
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: {
          ...TestHarness.signedInPrefs(),
          'measurement_mode': 'manual',
        },
        bleService: FakeBleService(autoStream: false),
      );

      expect(deps.modeController.mode, MeasurementMode.manual);
    });
  });

  group('manual input screen', () {
    /// The form is deliberately long - it covers every field the wearable
    /// will eventually send - so these tests use a tall viewport rather than
    /// scrolling to each group in turn.
    Future<void> pumpForm(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ManualInputScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('groups the fields and offers Quick Demo', (tester) async {
      await pumpForm(tester);

      expect(find.text('Cardiovascular'), findsOneWidget);
      expect(find.text('GSR / EDA'), findsOneWidget);
      expect(find.text('Movement'), findsOneWidget);
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('Context'), findsOneWidget);
      expect(find.text('ANALYZE'), findsOneWidget);
      expect(find.text('Quick Demo'), findsOneWidget);
    });

    testWidgets('refuses to analyze an empty form', (tester) async {
      await pumpForm(tester);

      await tester.ensureVisible(find.text('ANALYZE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ANALYZE'));
      await tester.pumpAndSettle();

      // Still on the form: an empty form must never yield a reading.
      expect(find.byType(ManualInputScreen), findsOneWidget);
      expect(find.textContaining('required'), findsWidgets);
    });

    testWidgets('Quick Demo fills the cardiovascular fields', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('Level 5'));
      await tester.pumpAndSettle();

      // The heart-rate field is the first text field on the expanded
      // Cardiovascular group and must now hold a value.
      final fields = tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      );
      expect(fields, isNotEmpty);
      expect(
        fields.any((f) => (f.controller?.text ?? '').isNotEmpty),
        isTrue,
      );
      expect(find.textContaining('illustrative'), findsWidgets);
    });
  });

  group('devices screen', () {
    testWidgets('renders and reports the adapter state', (tester) async {
      final service = FakeBleService(autoStream: false);
      final deps = await TestHarness.dependencies(bleService: service);

      await tester.pumpWidget(
        ChangeNotifierProvider<DeviceController>.value(
          value: deps.deviceController,
          child: const MaterialApp(home: DevicesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DevicesScreen), findsOneWidget);
      expect(find.text('Bluetooth'), findsWidgets);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('No devices yet'), findsOneWidget);
    });

    testWidgets('shows the connected device and a Disconnect action',
        (tester) async {
      final service = FakeBleService(autoStream: false);
      final deps = await TestHarness.dependencies(bleService: service);

      await tester.pumpWidget(
        ChangeNotifierProvider<DeviceController>.value(
          value: deps.deviceController,
          child: const MaterialApp(home: DevicesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(
        () => service.connect(FakeBleService.simulatedDevice),
      );
      await tester.pumpAndSettle();

      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.textContaining('NeuroPulse-ESP32'), findsWidgets);
      expect(find.text('Sensors'), findsOneWidget);
    });

    testWidgets('works when Bluetooth is unsupported', (tester) async {
      // A phone with no BLE radio, or a test process with no platform
      // channel. Demo and Manual must keep working regardless.
      final deps = await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
      );

      expect(deps.modeController.mode, MeasurementMode.demo);
      expect(deps.modeController.isReady, isTrue);
    });
  });

  group('main shell', () {
    testWidgets('all five tabs remain reachable', (tester) async {
      await TestHarness.pumpApp(
        tester,
        initialPrefs: TestHarness.signedInPrefs(),
        bleService: FakeBleService(autoStream: false),
      );

      expect(find.byType(MainShell), findsOneWidget);
      for (final tab in ['Home', 'Measure', 'Games', 'History', 'Profile']) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
      }
    });
  });

  // Real-time paths, outside the widget binding's fake clock.
  group('end-to-end over the simulated wearable', () {
    test('a BLE reading stays tagged BLE all the way into history', () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final deps = await TestHarness.dependencies(bleService: service);
      await service.connect(FakeBleService.simulatedDevice);
      await deps.modeController.setMode(MeasurementMode.bluetooth);

      final source = deps.bleDataSource;
      final done = source.measure(const Duration(milliseconds: 150)).drain<void>();

      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        service.emitPacket();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      service.emitPacket();
      await done;

      final packet = await source.readPacket();
      expect(packet.source, PhysiologicalSource.bluetooth);
      expect(packet.heartRate, isNotNull);

      final prediction = await deps.predictionService.predictFromPacket(packet);
      expect(prediction.source, 'BLE');

      final session = await deps.stressController.saveMeasurement(
        prediction,
        durationSeconds: 30,
        packet: packet,
      );
      expect(session.source, PhysiologicalSource.bluetooth);

      // And it survives the storage round trip with its source intact.
      final restored = deps.stressController.history.first;
      expect(restored.source, PhysiologicalSource.bluetooth);
      expect(restored.packet?.heartRate, isNotNull);
    });

    test('a measurement with no packets fails instead of inventing one',
        () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final deps = await TestHarness.dependencies(bleService: service);
      await service.connect(FakeBleService.simulatedDevice);

      // Connected but silent: firmware not sampling, or electrodes off.
      expect(
        deps.bleDataSource.measure(const Duration(seconds: 1)).drain<void>(),
        throwsA(isA<StateError>()),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('sources are never silently mixed', () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final deps = await TestHarness.dependencies(bleService: service);

      final demoPacket = await deps.demoDataSource.readPacket();
      expect(demoPacket.source, PhysiologicalSource.demo);

      deps.manualDataSource.submit(
        PhysiologicalInputPacket(
          timestamp: DateTime.now(),
          source: PhysiologicalSource.manual,
          heartRate: 70,
        ),
      );
      final manualPacket = await deps.manualDataSource.readPacket();
      expect(manualPacket.source, PhysiologicalSource.manual);

      expect(demoPacket.source, isNot(manualPacket.source));
    });
  });
}
