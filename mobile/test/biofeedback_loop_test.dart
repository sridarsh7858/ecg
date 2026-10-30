import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/app/dependencies.dart';
import 'package:neuropulse/data/models/game_session.dart';
import 'package:neuropulse/domain/games/game_catalog.dart';
import 'package:neuropulse/domain/stress/dummy_stress_prediction_service.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';

import 'support/test_harness.dart';

/// Exercises the whole loop through the real controllers and repositories:
///
///   demo level -> measurement -> prediction -> recommendation
///     -> game session -> post level -> saved history
void main() {
  test('every demo level flows end to end and is persisted', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    for (final level in StressLevel.values) {
      final deps = await TestHarness.dependencies();
      final stress = deps.stressController;

      // 1. Select the demo level.
      await stress.setDemoLevel(level);
      expect(stress.demoLevel, level);

      // 2. The current estimate follows it.
      expect(stress.currentLevel, level, reason: 'level ${level.number}');
      expect(stress.currentInfo.title, StressLevelConfig.of(level).title);

      // 3. A measurement produces the same level.
      final prediction = await stress.refreshCurrent();
      expect(prediction.level, level);
      expect(prediction.isDemo, isTrue);
      expect(prediction.modelVersion, 'demo-1.0.0');

      // 4. The recommendation matches the configured mapping.
      final recommendation = stress.recommendation;
      expect(
        recommendation.primary.id,
        StressLevelConfig.of(level).suggestedGameIds.first,
      );

      // 5. Saving the check-in puts it in History.
      final measurement = await stress.saveMeasurement(
        prediction,
        durationSeconds: 30,
      );
      expect(stress.history, hasLength(1));
      expect(stress.history.first.prediction.level, level);

      // 6. Playing the recommended game records a session linked to it.
      final session = await stress.recordGameResult(
        result: GameResult(
          gameId: recommendation.primary.id,
          duration: const Duration(minutes: 2),
          score: 120,
          completion: 1,
        ),
        startTime: DateTime.now(),
        measurementId: measurement.id,
      );

      expect(stress.gameSessions, hasLength(1));
      expect(session.preStressLevel, level);
      expect(session.postStressLevel.number, lessThanOrEqualTo(level.number));

      // 7. The check-in now carries the before/after pair.
      final stored = stress.history.first;
      expect(stored.hasGame, isTrue);
      expect(stored.gameName, recommendation.primary.name);
      expect(stored.postStressLevel, session.postStressLevel.number);

      // 8. The app view of the user follows the post-session estimate.
      expect(stress.currentLevel, session.postStressLevel);
    }
  });

  test(
    'a completed calming session lowers the estimate from level 5',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final deps = await TestHarness.dependencies();
      final stress = deps.stressController;

      await stress.setDemoLevel(StressLevel.veryHigh);
      final prediction = await stress.refreshCurrent();
      final measurement = await stress.saveMeasurement(
        prediction,
        durationSeconds: 30,
      );

      final session = await stress.recordGameResult(
        result: const GameResult(
          gameId: GameIds.calmBreathing,
          duration: Duration(minutes: 3),
          score: 180,
          completion: 1,
        ),
        startTime: DateTime.now(),
        measurementId: measurement.id,
      );

      expect(session.preStressLevel, StressLevel.veryHigh);
      expect(session.postStressLevel, StressLevel.moderate);
      expect(session.improved, isTrue);
      expect(stress.currentLevel, StressLevel.moderate);
    },
  );

  test('history, baseline and statistics persist and can be cleared', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final deps = await TestHarness.dependencies();
    final stress = deps.stressController;

    await stress.seedDemoHistory(days: 30, seed: 1);
    expect(stress.totalMeasurements, greaterThan(5));
    expect(stress.averageLevel(days: 30), isNotNull);
    expect(
      stress.historyWithin(7).length,
      lessThanOrEqualTo(stress.historyWithin(30).length),
    );

    // Charts read oldest-first.
    final window = stress.historyWithin(30);
    for (var i = 1; i < window.length; i++) {
      expect(
        window[i].recordedAt.isAfter(window[i - 1].recordedAt),
        isTrue,
        reason: 'historyWithin should be oldest first',
      );
    }

    await stress.setBaselineFromFeatures(stress.generateDemoFeatures());
    expect(stress.hasBaseline, isTrue);
    expect(stress.baselineComparison, isNotNull);

    await stress.clearHistory();
    expect(stress.totalMeasurements, 0);
    expect(stress.totalGamesPlayed, 0);
    expect(stress.currentStreak, 0);

    await stress.clearBaseline();
    expect(stress.hasBaseline, isFalse);
  });

  test('state survives a restart', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final first = await TestHarness.dependencies();
    await first.stressController.setDemoLevel(StressLevel.high);
    final prediction = await first.stressController.refreshCurrent(
      persist: true,
    );
    await first.stressController.saveMeasurement(
      prediction,
      durationSeconds: 30,
    );

    // Rebuilding the object graph over the same backing store is a cold start.
    final second = await AppDependencies.bootstrap(
      store: first.store,
      predictionServiceOverride: DummyStressPredictionService(),
    );

    expect(second.stressController.demoLevel, StressLevel.high);
    expect(second.stressController.currentLevel, StressLevel.high);
    expect(second.stressController.totalMeasurements, 1);
  });
}
