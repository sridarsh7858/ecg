import '../../data/models/game_recommendation.dart';
import '../stress/stress_level.dart';
import 'game_catalog.dart';

/// Chooses which activity to suggest for a given stress level.
///
/// The mapping itself lives in [StressLevelConfig] so that level semantics stay
/// in one place; this service resolves those ids into [GameDefinition]s and
/// attaches the copy shown next to the suggestion.
class GameRecommendationService {
  const GameRecommendationService();

  GameRecommendation recommendFor(StressLevel level) {
    final info = StressLevelConfig.of(level);
    final games = info.suggestedGameIds
        .map(GameCatalog.tryById)
        .whereType<GameDefinition>()
        .toList(growable: false);

    // Defensive fallback: a mistyped id in the config must never crash the
    // dashboard, so fall back to the always-safe calming activity.
    final primary = games.isNotEmpty ? games.first : GameCatalog.calmBreathing;
    final alternatives = games.length > 1
        ? games.sublist(1)
        : const <GameDefinition>[];

    return GameRecommendation(
      level: level,
      primary: primary,
      alternatives: alternatives,
      reason: _reasonFor(level, primary),
    );
  }

  GameRecommendation recommendForNumber(int levelNumber) =>
      recommendFor(StressLevel.fromNumber(levelNumber));

  String _reasonFor(StressLevel level, GameDefinition primary) {
    return switch (level) {
      StressLevel.veryLow =>
        'You are settled, so ${primary.name} is here purely to enjoy.',
      StressLevel.low =>
        'A light session keeps things steady without demanding much.',
      StressLevel.moderate =>
        'A short reset now can stop tension building further.',
      StressLevel.high =>
        'Paced breathing is the gentlest way to give yourself a break.',
      StressLevel.veryHigh =>
        'Start slow. A longer breathing session asks nothing of you.',
    };
  }
}
