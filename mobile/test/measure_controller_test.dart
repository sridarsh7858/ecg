import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/domain/ble/ble_protocol.dart';
import 'package:neuropulse/domain/ble/ble_service.dart';
import 'package:neuropulse/domain/ble/fake_ble_service.dart';
import 'package:neuropulse/domain/physiological/ble_physiological_data_source.dart';
import 'package:neuropulse/domain/physiological/demo_physiological_data_source.dart';
import 'package:neuropulse/domain/physiological/physiological_data_source.dart';
import 'package:neuropulse/domain/stress/dummy_stress_prediction_service.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';
import 'package:neuropulse/features/measure/measure_controller.dart';

void main() {
  MeasureController controllerFor(StressLevel level) {
    return MeasureController(
      dataSource: DemoPhysiologicalDataSource(
        targetLevel: () => level,
        random: math.Random(level.number),
        tickInterval: const Duration(milliseconds: 1),
      ),
      predictionService: DummyStressPredictionService(),
    );
  }

  group('MeasureController', () {
    test('starts idle and ready', () {
      final controller = controllerFor(StressLevel.moderate);
      expect(controller.phase, MeasurePhase.idle);
      expect(controller.isRunning, isFalse);
      expect(controller.deviceReady, isTrue);
      expect(controller.deviceName, 'Demo Mode');
      expect(controller.progress, 0);
      controller.dispose();
    });

    test('runs the full flow and produces a prediction', () async {
      final controller = controllerFor(StressLevel.high);
      final phases = <MeasurePhase>[];
      controller.addListener(() {
        if (phases.isEmpty || phases.last != controller.phase) {
          phases.add(controller.phase);
        }
      });

      await controller.start(const Duration(milliseconds: 30));

      expect(phases.first, MeasurePhase.measuring);
      expect(phases, contains(MeasurePhase.processing));
      expect(controller.phase, MeasurePhase.complete);
      expect(controller.progress, 1);
      expect(controller.prediction, isNotNull);
      expect(controller.prediction!.level, StressLevel.high);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('every demo level flows through to the matching prediction', () async {
      for (final level in StressLevel.values) {
        final controller = controllerFor(level);
        await controller.start(const Duration(milliseconds: 20));
        expect(
          controller.prediction!.level,
          level,
          reason: 'level ${level.number}',
        );
        controller.dispose();
      }
    });

    test('the waveform buffer is bounded', () async {
      final controller = controllerFor(StressLevel.low);
      await controller.start(const Duration(milliseconds: 300));
      expect(
        controller.waveform.length,
        lessThanOrEqualTo(MeasureController.waveformWindow),
      );
      controller.dispose();
    });

    test('reset clears the last result', () async {
      final controller = controllerFor(StressLevel.moderate);
      await controller.start(const Duration(milliseconds: 20));
      expect(controller.prediction, isNotNull);

      controller.reset();
      expect(controller.prediction, isNull);
      expect(controller.phase, MeasurePhase.idle);
      expect(controller.waveform, isEmpty);
      controller.dispose();
    });

    test(
      'a failing data source surfaces an error instead of throwing',
      () async {
        // A BLE source with nothing connected is the realistic failure: the
        // user selects Bluetooth mode before pairing a wearable.
        final service = FakeBleService(autoStream: false);
        addTearDown(service.dispose);

        final controller = MeasureController(
          dataSource: BlePhysiologicalDataSource(service),
          predictionService: DummyStressPredictionService(),
        );

        await controller.start(const Duration(milliseconds: 10));

        expect(controller.error, isNotNull);
        expect(controller.phase, MeasurePhase.idle);
        expect(controller.prediction, isNull);
        controller.dispose();
      },
    );
  });

  group('BlePhysiologicalDataSource', () {
    test('is not ready until a wearable is connected', () {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final source = BlePhysiologicalDataSource(service);
      expect(source.isReady, isFalse);
      expect(source.status, DataSourceStatus.disconnected);
      expect(source.id, 'ble');
      expect(source.sourceTag, 'BLE');
      expect(source.mode, MeasurementMode.bluetooth);
    });

    test('becomes ready once connected', () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final source = BlePhysiologicalDataSource(service);
      await service.connect(FakeBleService.simulatedDevice);

      expect(source.isReady, isTrue);
      expect(source.status, DataSourceStatus.connected);
    });

    test('connecting without a device gives an actionable error', () {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      expect(
        BlePhysiologicalDataSource(service).connect,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Open Devices'),
          ),
        ),
      );
    });

    test('averages a window of packets into one reading', () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final source = BlePhysiologicalDataSource(service);
      await service.connect(FakeBleService.simulatedDevice);

      // Feed three packets while a short measurement runs.
      final measurement = source.measure(const Duration(milliseconds: 250));
      final done = measurement.drain<void>();

      for (final hr in [60, 70, 80]) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        service.emitRaw('{"hr": $hr, "rmssd": 40}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      service.emitRaw('{"hr": 80, "rmssd": 40}');
      await done;

      final packet = await source.readPacket();
      expect(packet.heartRate, closeTo(70, 5));
      expect(packet.source.tag, 'BLE');
    });
  });

  group('GATT contract', () {
    test('publishes fixed identifiers for the firmware', () {
      // These identifiers are the contract the ESP32 firmware is written
      // against, so a change here is a breaking change. They live in BleUuids
      // so that firmware authors have one place to read them from.
      expect(
        BleUuids.neuropulseServiceUuid,
        '6e1a0001-b5a3-f393-e0a9-e50e24dcca9e',
      );
      expect(BleUuids.deviceNamePrefix, 'NeuroPulse');
      expect(
        {
          BleUuids.physiologyCharacteristicUuid,
          BleUuids.deviceInfoCharacteristicUuid,
          BleUuids.batteryCharacteristicUuid,
          BleUuids.rawEcgCharacteristicUuid,
          BleUuids.controlCharacteristicUuid,
        }.length,
        5,
        reason: 'every characteristic must have a distinct UUID',
      );
    });

    test('UUID matching survives case and short-form differences', () {
      expect(
        BleUuids.matches(
          '6E1A0002-B5A3-F393-E0A9-E50E24DCCA9E',
          BleUuids.physiologyCharacteristicUuid,
        ),
        isTrue,
      );
      // Android often reports the SIG battery characteristic in short form.
      expect(
        BleUuids.matches('2a19', BleUuids.standardBatteryLevelUuid),
        isTrue,
      );
    });
  });

  group('FakeBleService', () {
    test('drives scan, connect and streaming with no hardware', () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);

      final seen = <List<DiscoveredDevice>>[];
      service.scanResults.listen(seen.add);

      await service.startScan();
      // Broadcast stream events are delivered asynchronously, so give the
      // event loop a turn before asserting on what the listener saw.
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.single.name, contains('NeuroPulse'));

      await service.connect(seen.last.single);
      expect(service.currentStatus.isConnected, isTrue);

      final packets = <String>[];
      service.packets.listen((packet) => packets.add(packet.source.tag));
      service.emitPacket();
      await Future<void>.delayed(Duration.zero);

      expect(packets, ['BLE']);

      await service.disconnect();
      expect(service.currentStatus.isConnected, isFalse);
    });

    test('a malformed packet is rejected without dropping the link', () async {
      final service = FakeBleService(autoStream: false);
      addTearDown(service.dispose);
      await service.connect(FakeBleService.simulatedDevice);

      final rejected = <InvalidPacketResult>[];
      service.rejectedPackets.listen(rejected.add);

      service.emitRaw('{ this is not json');
      await Future<void>.delayed(Duration.zero);

      expect(rejected, hasLength(1));
      expect(service.currentStatus.isConnected, isTrue,
          reason: 'bad firmware output must not disconnect the wearable');
      expect(service.currentStatus.packetsRejected, 1);
    });
  });
}
