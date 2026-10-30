import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/data/models/game_session.dart';
import 'package:neuropulse/data/models/physiological_features.dart';
import 'package:neuropulse/domain/games/game_catalog.dart';
import 'package:neuropulse/domain/games/game_session_manager.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';

void main() {
  const manager = GameSessionManager();
  final start = DateTime.utc(2026, 9, 4, 10);

  GameResult result({
    String gameId = GameIds.calmBreathing,
    double completion = 1,
    int score = 100,
  }) {
    return GameResult(
      gameId: gameId,
      duration: const Duration(minutes: 2),
      score: score,
      completion: completion,
      metrics: const {'breaths': 12},
    );
  }

  group('buildSession', () {
    test('carries the result through to the stored session', () {
      final session = manager.buildSession(
        result: result(),
        preStressLevel: StressLevel.high,
        startTime: start,
        source: DataSourceTag.demo,
      );

      expect(session.gameId, GameIds.calmBreathing);
      expect(session.gameName, 'Calm Breathing');
      expect(session.startTime, start);
      expect(session.endTime, start.add(const Duration(minutes: 2)));
      expect(session.duration, const Duration(minutes: 2));
      expect(session.score, 100);
      expect(session.preStressLevel, StressLevel.high);
      expect(session.source, DataSourceTag.demo);
      expect(session.metrics['breaths'], 12);
      expect(session.id, isNotEmpty);
    });

    test('an unknown game id falls back to the id as its name', () {
      final session = manager.buildSession(
        result: result(gameId: 'mystery'),
        preStressLevel: StressLevel.low,
        startTime: start,
        source: DataSourceTag.demo,
      );
      expect(session.gameName, 'mystery');
    });
  });

  group('simulatePostLevel', () {
    test('an abandoned session leaves the estimate alone', () {
      for (final level in StressLevel.values) {
        expect(
          manager.simulatePostLevel(
            pre: level,
            result: result(completion: 0.2),
          ),
          level,
        );
      }
    });

    test('a completed session lowers the estimate by at least one level', () {
      expect(
        manager.simulatePostLevel(
          pre: StressLevel.high,
          result: result(gameId: GameIds.focusBlocks, completion: 0.8),
        ),
        StressLevel.moderate,
      );
    });

    test('a fully completed calming session at a high level drops two', () {
      expect(
        manager.simulatePostLevel(
          pre: StressLevel.veryHigh,
          result: result(completion: 1),
        ),
        StressLevel.moderate,
      );
      expect(
        manager.simulatePostLevel(
          pre: StressLevel.high,
          result: result(completion: 1),
        ),
        StressLevel.low,
      );
    });

    test('a non-calming game never drops more than one level', () {
      expect(
        manager.simulatePostLevel(
          pre: StressLevel.veryHigh,
          result: result(gameId: GameIds.pulseRunner, completion: 1),
        ),
        StressLevel.high,
      );
    });

    test('the estimate never falls below level 1', () {
      for (final gameId in GameCatalog.all.map((game) => game.id)) {
        final post = manager.simulatePostLevel(
          pre: StressLevel.veryLow,
          result: result(gameId: gameId, completion: 1),
        );
        expect(post, StressLevel.veryLow);
        expect(post.number, greaterThanOrEqualTo(1));
      }
    });

    test('the post level is reachable from every starting level', () {
      for (final level in StressLevel.values) {
        final post = manager.simulatePostLevel(
          pre: level,
          result: result(completion: 1),
        );
        expect(post.number, inInclusiveRange(1, level.number));
      }
    });
  });

  group('GameResult', () {
    test('completion decides whether a session counts as meaningful', () {
      expect(result(completion: 0.74).isMeaningfullyComplete, isFalse);
      expect(result(completion: 0.75).isMeaningfullyComplete, isTrue);
      expect(result(completion: 1).isMeaningfullyComplete, isTrue);
    });
  });
}
