import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/physiological_features.dart';
import 'package:neuropulse/domain/stress/feature_registry.dart';
import 'package:neuropulse/domain/stress/ml_stress_prediction_service.dart';

/// Tests for the trained engine's *contract*, not its arithmetic.
///
/// The arithmetic is verified where it can actually be verified: `export.py`
/// refuses to write the asset unless Keras and TFLite agree to within 1e-4 on
/// 40 probe vectors. Inference cannot run here - `tflite_flutter` needs a
/// native TensorFlow Lite library that the host Dart VM does not load - so
/// asserting numbers in this file would test a stub, not the shipped model.
///
/// What is worth pinning here is everything that could silently break the
/// shipped model without changing a single number: the feature order, and the
/// promise that a service which cannot load its asset says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('feature contract', () {
    test('the registry order is the order the model was trained on', () async {
      // training/hrv.py FEATURE_ORDER. A transposed vector is the classic way
      // a model ships and quietly does nothing, so this is pinned on both
      // sides: here, and again at runtime in initialise().
      const trainedOrder = ['hr', 'meanRR', 'rmssd', 'sdnn', 'pnn50'];
      expect(FeatureRegistry().featureKeys, trainedOrder);
    });

    test('the shipped scaler declares that same order', () async {
      final raw = await rootBundle.loadString(
        'assets/models/feature_scaler.json',
      );
      final scaler = jsonDecode(raw) as Map<String, dynamic>;
      expect(
        (scaler['order'] as List).cast<String>(),
        FeatureRegistry().featureKeys,
      );
      expect((scaler['mean'] as List).length, 5);
      expect((scaler['std'] as List).length, 5);
    });

    test('the model asset is present and is a TFLite flatbuffer', () async {
      final bytes = await rootBundle.load('assets/models/stress_model.tflite');
      expect(bytes.lengthInBytes, greaterThan(0));

      // TFLite flatbuffers carry "TFL3" at byte offset 4.
      final identifier = String.fromCharCodes(
        bytes.buffer.asUint8List(4, 4),
      );
      expect(identifier, 'TFL3');
    });
  });

  group('when the interpreter cannot load', () {
    test('it labels itself demo instead of claiming to be the model', () async {
      final service = MLStressPredictionService();
      await service.initialise();

      // Under `flutter test` there is no native TFLite library, so this is the
      // fallback path by construction. If a host ever does load it, the
      // assertions below still hold - they only say the two states agree with
      // each other, which is the property that matters.
      if (service.isReady) {
        expect(service.isDemo, isFalse);
        expect(service.modelVersion, 'ml-1.0.0');
        expect(service.displayName, 'Stress Model v1');
      } else {
        expect(service.isDemo, isTrue);
        expect(service.modelVersion, 'demo-1.0.0');
        expect(service.loadError, isNotNull);
      }
    });

    test('it still returns a usable prediction', () async {
      final service = MLStressPredictionService();
      await service.initialise();

      final prediction = await service.predict(
        PhysiologicalFeatures.fromHr(
          hr: 88,
          rmssd: 21,
          sdnn: 31,
          pnn50: 6,
        ),
      );

      expect(prediction.levelNumber, inInclusiveRange(1, 5));
      expect(prediction.confidence, inInclusiveRange(0.0, 1.0));
      // The version on the result always names the engine that produced it,
      // so history can never attribute a heuristic reading to the model.
      expect(prediction.modelVersion, service.modelVersion);
    });
  });
}
