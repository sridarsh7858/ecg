import '../../domain/games/game_catalog.dart';
import '../../domain/stress/stress_level.dart';

/// What the app suggests the user plays next, and why.
class GameRecommendation {
  const GameRecommendation({
    required this.level,
    required this.primary,
    required this.alternatives,
    required this.reason,
  });

  final StressLevel level;

  /// The single game shown behind the big "PLAY NOW" button.
  final GameDefinition primary;

  /// Other suitable games for this level, most suitable first.
  final List<GameDefinition> alternatives;

  /// Short sentence explaining the suggestion, shown under the card.
  final String reason;

  /// Primary plus alternatives, in order.
  List<GameDefinition> get all => [primary, ...alternatives];

  bool includes(String gameId) => all.any((game) => game.id == gameId);
}
