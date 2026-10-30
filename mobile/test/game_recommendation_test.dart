import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/domain/games/game_catalog.dart';
import 'package:neuropulse/domain/games/game_recommendation_service.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';

void main() {
  const service = GameRecommendationService();

  group('GameCatalog', () {
    test('holds the five project games with unique ids', () {
      expect(GameCatalog.all.length, 5);
      final ids = GameCatalog.all.map((game) => game.id).toSet();
      expect(ids.length, 5);
      expect(ids, {
        GameIds.calmBreathing,
        GameIds.pulseRunner,
        GameIds.zenGarden,
        GameIds.focusBlocks,
        GameIds.calmCatch,
      });
    });

    test('every game is fully described', () {
      for (final game in GameCatalog.all) {
        expect(game.name, isNotEmpty);
        expect(game.tagline, isNotEmpty);
        expect(game.description, isNotEmpty);
        expect(game.recommendedLevels, isNotEmpty);
        expect(game.estimatedDuration.inSeconds, greaterThan(0));
        expect(game.durationLabel, isNotEmpty);
        expect(game.levelsLabel, isNotEmpty);
      }
    });

    test('byId resolves known games and rejects unknown ones', () {
      expect(GameCatalog.byId(GameIds.zenGarden).name, 'Zen Garden');
      expect(() => GameCatalog.byId('nope'), throwsArgumentError);
      expect(GameCatalog.tryById('nope'), isNull);
    });

    test('levelsLabel renders contiguous and sparse ranges', () {
      expect(GameCatalog.calmBreathing.levelsLabel, 'Levels 3-5');
      expect(GameCatalog.pulseRunner.levelsLabel, 'Levels 1-2');
      expect(GameCatalog.zenGarden.levelsLabel, 'Levels 1, 2, 4, 5');
    });
  });

  group('GameRecommendationService', () {
    test('level 1 recommends Zen Garden, with Calm Catch offered too', () {
      final recommendation = service.recommendFor(StressLevel.veryLow);
      expect(recommendation.primary.id, GameIds.zenGarden);
      expect(recommendation.includes(GameIds.calmCatch), isTrue);
    });

    test('level 2 recommends Zen Garden, with Calm Catch offered too', () {
      final recommendation = service.recommendFor(StressLevel.low);
      expect(recommendation.primary.id, GameIds.zenGarden);
      expect(recommendation.includes(GameIds.calmCatch), isTrue);
    });

    test(
      'level 3 recommends Calm Breathing, with Focus Blocks offered too',
      () {
        final recommendation = service.recommendFor(StressLevel.moderate);
        expect(recommendation.primary.id, GameIds.calmBreathing);
        expect(recommendation.includes(GameIds.focusBlocks), isTrue);
      },
    );

    test('level 4 recommends Calm Breathing', () {
      final recommendation = service.recommendFor(StressLevel.high);
      expect(recommendation.primary.id, GameIds.calmBreathing);
    });

    test('level 5 recommends Calm Breathing', () {
      final recommendation = service.recommendFor(StressLevel.veryHigh);
      expect(recommendation.primary.id, GameIds.calmBreathing);
    });

    test('levels 3 to 5 always lead with a calming activity', () {
      for (final level in [
        StressLevel.moderate,
        StressLevel.high,
        StressLevel.veryHigh,
      ]) {
        expect(service.recommendFor(level).primary.isCalming, isTrue);
      }
    });

    test('every level produces a usable recommendation with a reason', () {
      for (final level in StressLevel.values) {
        final recommendation = service.recommendFor(level);
        expect(recommendation.level, level);
        expect(recommendation.reason, isNotEmpty);
        expect(recommendation.all, isNotEmpty);
        expect(recommendation.all.first, recommendation.primary);
        // No duplicates between the primary suggestion and the alternatives.
        final ids = recommendation.all.map((game) => game.id).toList();
        expect(ids.toSet().length, ids.length);
      }
    });

    test('recommendForNumber agrees with recommendFor', () {
      for (var number = 1; number <= 5; number++) {
        expect(
          service.recommendForNumber(number).primary.id,
          service.recommendFor(StressLevel.fromNumber(number)).primary.id,
        );
      }
    });

    test('recommendations reference real games only', () {
      for (final level in StressLevel.values) {
        for (final id in StressLevelConfig.of(level).suggestedGameIds) {
          expect(GameCatalog.tryById(id), isNotNull, reason: id);
        }
      }
    });
  });
}
