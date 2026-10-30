import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/physiological_features.dart';
import 'package:neuropulse/domain/physiological/demo_physiological_data_source.dart';
import 'package:neuropulse/domain/stress/dummy_stress_prediction_service.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';
import 'package:neuropulse/domain/stress/stress_scoring.dart';

void main() {
  final service = DummyStressPredictionService();

  group('StressScoring', () {
    test('a calm feature vector scores low', () {
      final calm = PhysiologicalFeatures.fromHr(
        hr: 58,
        rmssd: 70,
        sdnn: 85,
        pnn50: 42,
      );
      expect(StressScoring.score(calm), lessThan(0.2));
      expect(
        StressScoring.levelForScore(StressScoring.score(calm)),
        StressLevel.veryLow,
      );
    });

    test('a high-arousal feature vector scores high', () {
      final tense = PhysiologicalFeatures.fromHr(
        hr: 102,
        rmssd: 14,
        sdnn: 20,
        pnn50: 3,
      );
      expect(StressScoring.score(tense), greaterThan(0.8));
      expect(
        StressScoring.levelForScore(StressScoring.score(tense)),
        StressLevel.veryHigh,
      );
    });

    test('scores stay inside 0..1 for out-of-range inputs', () {
      final extreme = PhysiologicalFeatures.fromHr(
        hr: 250,
        rmssd: -10,
        sdnn: -50,
        pnn50: 900,
      );
      final score = StressScoring.score(extreme);
      expect(score, inInclusiveRange(0, 1));
    });

    test('band centres map back to their own level', () {
      for (final level in StressLevel.values) {
        final centre = StressScoring.bandCentre(level);
        expect(StressScoring.levelForScore(centre), level);
      }
    });

    test('confidence is highest at a band centre and lower at an edge', () {
      final centre = StressScoring.confidenceForScore(
        StressScoring.bandCentre(StressLevel.moderate),
      );
      final edge = StressScoring.confidenceForScore(0.401);
      expect(centre, greaterThan(edge));
      expect(centre, inInclusiveRange(0.62, 0.96));
      expect(edge, inInclusiveRange(0.62, 0.96));
    });

    test('weights sum to one, so the score is a true weighted mean', () {
      final total =
          StressScoring.hrWeight +
          StressScoring.rmssdWeight +
          StressScoring.sdnnWeight +
          StressScoring.pnn50Weight;
      expect(total, closeTo(1.0, 1e-9));
    });
  });

  group('DummyStressPredictionService', () {
    test('reports itself as a demo engine', () {
      expect(service.isDemo, isTrue);
      expect(service.modelVersion, 'demo-1.0.0');
      expect(service.displayName, 'Demo Stress Engine');
    });

    test(
      'prediction carries the features and the source it was given',
      () async {
        final features = PhysiologicalFeatures.fromHr(
          hr: 91,
          rmssd: 24,
          sdnn: 31,
          pnn50: 7,
        );
        final prediction = await service.predict(features);

        expect(prediction.features, features);
        expect(prediction.source, DataSourceTag.demo);
        expect(prediction.modelVersion, 'demo-1.0.0');
        expect(prediction.label, StressLevelConfig.of(prediction.level).title);
        expect(prediction.confidence, inInclusiveRange(0, 1));
      },
    );

    test('the example vector from the brief predicts level 4', () async {
      // HR 91, RMSSD 24, SDNN 31, pNN50 7 is the worked example in the spec.
      final prediction = await service.predict(
        PhysiologicalFeatures.fromHr(hr: 91, rmssd: 24, sdnn: 31, pnn50: 7),
      );
      expect(prediction.level, StressLevel.high);
    });

    test('predictions are deterministic for the same input', () async {
      final features = PhysiologicalFeatures.fromHr(
        hr: 74,
        rmssd: 42,
        sdnn: 52,
        pnn50: 20,
      );
      final first = await service.predict(features);
      final second = await service.predict(features);
      expect(first.level, second.level);
      expect(first.confidence, second.confidence);
    });

    test('initialise and dispose are safe to call repeatedly', () async {
      await service.initialise();
      await service.initialise();
      await service.dispose();
    });
  });

  group('demo data source round trip', () {
    test('generated features predict the level that was requested', () async {
      // The demo generator inverts the scoring maths, so every level must come
      // back out of the engine unchanged. This is what makes levels 1-5
      // testable end to end.
      for (final level in StressLevel.values) {
        final source = DemoPhysiologicalDataSource(
          targetLevel: () => level,
          random: math.Random(level.number),
        );

        for (var i = 0; i < 40; i++) {
          final features = source.generateFeatures();
          final prediction = await service.predict(features);
          expect(
            prediction.level,
            level,
            reason: 'iteration $i for level ${level.number} gave $features',
          );
        }
      }
    });

    test('generated values stay physiologically plausible', () {
      for (final level in StressLevel.values) {
        final source = DemoPhysiologicalDataSource(
          targetLevel: () => level,
          random: math.Random(11),
        );
        for (var i = 0; i < 30; i++) {
          final f = source.generateFeatures();
          expect(f.hr, inInclusiveRange(45, 120));
          expect(f.rmssd, greaterThan(0));
          expect(f.sdnn, greaterThan(0));
          expect(f.pnn50, greaterThanOrEqualTo(0));
          expect(f.meanRR, closeTo(60000 / f.hr, 0.01));
          expect(f.source, DataSourceTag.demo);
        }
      }
    });

    test('higher levels produce higher heart rate and lower variability', () {
      final random = math.Random(3);
      double meanHr(StressLevel level) {
        final source = DemoPhysiologicalDataSource(
          targetLevel: () => level,
          random: random,
        );
        var total = 0.0;
        for (var i = 0; i < 50; i++) {
          total += source.generateFeatures().hr;
        }
        return total / 50;
      }

      expect(meanHr(StressLevel.veryLow), lessThan(meanHr(StressLevel.high)));
      expect(
        meanHr(StressLevel.moderate),
        lessThan(meanHr(StressLevel.veryHigh)),
      );
    });

    test('measure emits ticks and ends with matching features', () async {
      final source = DemoPhysiologicalDataSource(
        targetLevel: () => StressLevel.moderate,
        random: math.Random(5),
        tickInterval: const Duration(milliseconds: 1),
      );

      final ticks = await source
          .measure(const Duration(milliseconds: 20))
          .toList();

      expect(ticks, isNotEmpty);
      expect(ticks.first.progress, lessThan(ticks.last.progress));
      expect(ticks.last.progress, closeTo(1.0, 0.001));
      expect(ticks.last.remaining, Duration.zero);
      for (final tick in ticks) {
        expect(tick.waveformSample, inInclusiveRange(-1.0, 1.0));
        expect(tick.hr, greaterThan(0));
      }

      final features = await source.readFeatures();
      final prediction = await service.predict(features);
      expect(prediction.level, StressLevel.moderate);
    });
  });
}
