import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/physiological_input_packet.dart';
import 'package:neuropulse/domain/ble/device_capabilities.dart';
import 'package:neuropulse/domain/physiological/manual_physiological_data_source.dart';
import 'package:neuropulse/domain/physiological/physiological_data_source.dart';
import 'package:neuropulse/domain/stress/dummy_stress_prediction_service.dart';
import 'package:neuropulse/domain/stress/feature_registry.dart';
import 'package:neuropulse/domain/stress/stress_feature_vector.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';
import 'package:neuropulse/domain/stress/stress_scoring.dart';

/// Sections 2, 5, 6, 8, 10, 27, 30 and 32.
void main() {
  PhysiologicalInputPacket packetWith({
    double? hr = 72,
    double? rmssd = 40,
    double? sdnn = 50,
    double? pnn50 = 15,
    double? gsr,
    int? gsrPeaks,
    double? accelX,
    double? accelY,
    double? accelZ,
    PhysiologicalSource source = PhysiologicalSource.manual,
  }) {
    return PhysiologicalInputPacket(
      timestamp: DateTime(2026, 1, 1, 12),
      source: source,
      heartRate: hr,
      rmssd: rmssd,
      sdnn: sdnn,
      pnn50: pnn50,
      gsrValue: gsr,
      gsrPeaks: gsrPeaks,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
    );
  }

  group('PhysiologicalInputPacket', () {
    test('every sensor field is optional', () {
      final packet = PhysiologicalInputPacket(
        timestamp: DateTime(2026),
        source: PhysiologicalSource.demo,
      );

      expect(packet.hasCardiovascular, isFalse);
      expect(packet.hasGsr, isFalse);
      expect(packet.hasMovement, isFalse);
      expect(packet.hasBattery, isFalse);
      expect(packet.isUsable, isFalse);
    });

    test('survives a JSON round trip with sparse fields', () {
      final original = packetWith(gsr: 2.5, gsrPeaks: 4);
      final restored = PhysiologicalInputPacket.fromJson(original.toJson());

      expect(restored.heartRate, original.heartRate);
      expect(restored.gsrValue, 2.5);
      expect(restored.gsrPeaks, 4);
      expect(restored.source, PhysiologicalSource.manual);
      // Absent stays absent across the round trip.
      expect(restored.accelX, isNull);
      expect(restored.batteryPercentage, isNull);
    });

    test('source tags are stable and tolerantly parsed', () {
      expect(PhysiologicalSource.demo.tag, 'DEMO');
      expect(PhysiologicalSource.manual.tag, 'MANUAL');
      expect(PhysiologicalSource.bluetooth.tag, 'BLE');

      expect(PhysiologicalSource.fromTag('BLE'), PhysiologicalSource.bluetooth);
      expect(
        PhysiologicalSource.fromTag('BLUETOOTH'),
        PhysiologicalSource.bluetooth,
        reason: 'both spellings must load, so old history still reads',
      );
      expect(PhysiologicalSource.fromTag('manual'), PhysiologicalSource.manual);
      expect(PhysiologicalSource.fromTag(null), PhysiologicalSource.demo);
    });

    test('movement intensity is computed from the accelerometer', () {
      // A device lying still still reads 1 g total, so a still reading must
      // come out near zero rather than near one.
      final still = packetWith(accelX: 0, accelY: 0, accelZ: 1.0);
      expect(still.effectiveMovementIntensity, closeTo(0, 0.01));
      expect(still.movementLabel, 'Still');
      expect(still.hasMotionArtefactRisk, isFalse);

      final moving = packetWith(accelX: 0.5, accelY: 0.5, accelZ: 1.2);
      expect(moving.effectiveMovementIntensity! > 0.5, isTrue);
      expect(moving.hasMotionArtefactRisk, isTrue);
    });

    test('movement is null, not zero, when there is no accelerometer', () {
      expect(packetWith().effectiveMovementIntensity, isNull);
      expect(packetWith().movementLabel, isNull);
    });
  });

  group('FeatureRegistry', () {
    test('vector order is stable and declaration-ordered', () {
      final registry = FeatureRegistry();
      expect(registry.featureKeys, ['hr', 'meanRR', 'rmssd', 'sdnn', 'pnn50']);

      // Enabling in a different order must not change the vector order, or a
      // model would silently receive its inputs transposed.
      final shuffled = FeatureRegistry(
        enabled: {
          StressFeature.pnn50,
          StressFeature.hr,
          StressFeature.sdnn,
          StressFeature.rmssd,
          StressFeature.meanRR,
        },
      );
      expect(shuffled.featureKeys, registry.featureKeys);
    });

    test('GSR and movement are declared but off by default', () {
      final registry = FeatureRegistry();
      expect(registry.isEnabled(StressFeature.gsrLevel), isFalse);
      expect(registry.isEnabled(StressFeature.movementIntensity), isFalse);
      expect(FeatureRegistry.available, contains(StressFeature.gsrLevel));
    });

    test('can be built from the columns a dataset actually has', () {
      final registry = FeatureRegistry.forDatasetColumns([
        'hr',
        'rmssd',
        'gsrLevel',
        'some_column_the_app_cannot_supply',
      ]);

      expect(registry.featureKeys, ['hr', 'rmssd', 'gsrLevel']);
    });
  });

  group('StressFeatureVector', () {
    test('reports what is missing instead of substituting values', () {
      final vector = StressFeatureVector.from(
        packetWith(sdnn: null, pnn50: null),
        registry: FeatureRegistry(),
      );

      expect(vector.isComplete, isFalse);
      expect(
        vector.missingFeatures,
        containsAll([StressFeature.sdnn, StressFeature.pnn50]),
      );
      expect(vector[StressFeature.sdnn], isNull);
      expect(vector.completeness, closeTo(0.6, 0.001));
    });

    test('densifying requires the caller to choose a substitute', () {
      final vector = StressFeatureVector.from(
        packetWith(sdnn: null),
        registry: FeatureRegistry(),
      );

      final dense = vector.toDense((_) => -1);
      expect(dense, hasLength(5));
      expect(dense[3], -1, reason: 'sdnn slot uses the given substitute');
    });
  });

  group('DummyStressPredictionService', () {
    test('is honest about not being a model', () {
      final service = DummyStressPredictionService();
      expect(service.isDemo, isTrue);
      expect(service.modelVersion, 'demo-1.0.0');
      expect(service.displayName, 'Demo Stress Engine');
      expect(service.displayName.toLowerCase(), isNot(contains('ai')));
    });

    test('produces all five levels across the input range', () async {
      final service = DummyStressPredictionService();
      final levels = <StressLevel>{};

      // Sweep the score axis rather than guessing a heart-rate range: the
      // score is what the bands are defined over, so this genuinely covers
      // the full output space.
      for (var score = 0.0; score <= 1.0; score += 0.02) {
        final features = StressScoring.featuresForScore(score);
        final packet = PhysiologicalInputPacket.fromLegacyFeatures(
          features,
          source: PhysiologicalSource.manual,
        );
        levels.add((await service.predictFromPacket(packet)).level);
      }

      expect(
        levels,
        hasLength(5),
        reason: 'every one of the five levels must be reachable',
      );
    });

    test('round-trips a requested level back to the same level', () async {
      // Demo mode inverts the scoring to build features, so asking for a
      // level must produce features that score as that level. If this ever
      // breaks, the demo stops being self-consistent.
      final service = DummyStressPredictionService();

      for (final level in StressLevel.values) {
        final features = StressScoring.featuresForScore(
          StressScoring.bandCentre(level),
        );
        final prediction = await service.predictFromPacket(
          PhysiologicalInputPacket.fromLegacyFeatures(features),
        );
        expect(prediction.level, level);
        expect(prediction.label, StressLevelConfig.of(level).title);
      }
    });

    test('a missing feature does not vote toward calm', () async {
      final service = DummyStressPredictionService();

      final complete = await service.predictFromPacket(
        packetWith(hr: 100, rmssd: 15, sdnn: 20, pnn50: 3),
      );
      final partial = await service.predictFromPacket(
        packetWith(hr: 100, rmssd: 15, sdnn: null, pnn50: null),
      );

      // Weights are renormalised, so dropping two stressed-looking features
      // must not drag the estimate down a level.
      expect(partial.level, complete.level);

      // But it is genuinely less certain, and says so.
      expect(partial.confidence < complete.confidence, isTrue);
    });

    test('carries the source through to the prediction', () async {
      final service = DummyStressPredictionService();
      final prediction = await service.predictFromPacket(
        packetWith(source: PhysiologicalSource.bluetooth),
      );
      expect(prediction.source, 'BLE');
    });
  });

  group('ManualPhysiologicalDataSource', () {
    test('is not ready until values are entered', () {
      final source = ManualPhysiologicalDataSource();
      expect(source.isReady, isFalse);
      expect(source.mode, MeasurementMode.manual);
    });

    test('forces the manual tag even if told otherwise', () async {
      final source = ManualPhysiologicalDataSource()
        ..submit(packetWith(source: PhysiologicalSource.bluetooth));

      expect(source.isReady, isTrue);
      final packet = await source.readPacket();
      expect(
        packet.source,
        PhysiologicalSource.manual,
        reason: 'typed values must never be recorded as hardware readings',
      );
    });

    test('measuring with an empty form throws rather than inventing data', () {
      final source = ManualPhysiologicalDataSource();
      expect(
        source.measure(const Duration(milliseconds: 10)).drain<void>(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DeviceCapabilities', () {
    test('observes sensors from packets that actually carry them', () {
      var capabilities = DeviceCapabilities.unknown;
      expect(capabilities.has(SensorKind.gsr), isFalse);

      capabilities = capabilities.observing(packetWith(gsr: 2.0));
      expect(capabilities.hasSeen(SensorKind.gsr), isTrue);
      expect(capabilities.hasSeen(SensorKind.gyroscope), isFalse);
    });

    test('a partial packet does not retract an observed sensor', () {
      // BLE packets are allowed to be partial, so one packet without GSR is
      // not evidence that the GSR sensor vanished.
      var capabilities = DeviceCapabilities.unknown
          .observing(packetWith(gsr: 2.0))
          .observing(packetWith());

      expect(capabilities.hasSeen(SensorKind.gsr), isTrue);
    });

    test('distinguishes declared from actually seen', () {
      final capabilities = DeviceCapabilities.fromDeviceInfo({
        'fw': '1.0.0',
        'sensors': ['ecg', 'gsr', 'gyro'],
      });

      expect(capabilities.has(SensorKind.gyroscope), isTrue);
      expect(capabilities.hasSeen(SensorKind.gyroscope), isFalse);
      expect(capabilities.declaredButUnseen, contains(SensorKind.gyroscope));
      expect(capabilities.firmwareVersion, '1.0.0');
    });

    test('summary lists every sensor, present or not', () {
      expect(
        DeviceCapabilities.unknown.summary,
        hasLength(SensorKind.values.length),
      );
    });
  });
}
