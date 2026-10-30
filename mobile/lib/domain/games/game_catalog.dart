import 'package:flutter/material.dart';

/// Static description of a mini-game.
///
/// Games register here once; the games grid, the recommendation service and
/// history all read from this catalogue rather than repeating names or icons.
@immutable
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.accent,
    required this.estimatedDuration,
    required this.recommendedLevels,
    required this.isCalming,
  });

  final String id;
  final String name;

  /// One short line shown on the game card.
  final String tagline;

  /// Longer copy shown before the session starts.
  final String description;

  final IconData icon;
  final Color accent;
  final Duration estimatedDuration;

  /// Stress levels (1..5) this game suits.
  final List<int> recommendedLevels;

  /// True for games whose purpose is downregulation rather than play.
  final bool isCalming;

  /// e.g. "3 min"
  String get durationLabel {
    final minutes = estimatedDuration.inMinutes;
    if (minutes < 1) return '${estimatedDuration.inSeconds} sec';
    return '$minutes min';
  }

  /// e.g. "Levels 3-5"
  String get levelsLabel {
    final sorted = [...recommendedLevels]..sort();
    if (sorted.isEmpty) return 'Any level';
    if (sorted.length == 1) return 'Level ${sorted.first}';
    final isContiguous = sorted.last - sorted.first == sorted.length - 1;
    if (isContiguous) return 'Levels ${sorted.first}-${sorted.last}';
    return 'Levels ${sorted.join(', ')}';
  }
}

/// Ids of the built-in games, kept as constants so nothing depends on strings
/// typed by hand at call sites.
class GameIds {
  const GameIds._();

  static const String calmBreathing = 'calm_breathing';
  static const String pulseRunner = 'pulse_runner';
  static const String zenGarden = 'zen_garden';
  static const String focusBlocks = 'focus_blocks';
  static const String calmCatch = 'calm_catch';
}

/// The five playable activities.
class GameCatalog {
  const GameCatalog._();

  static const GameDefinition calmBreathing = GameDefinition(
    id: GameIds.calmBreathing,
    name: 'Calm Breathing',
    tagline: 'Guided paced breathing',
    description:
        'Follow the circle: breathe in as it grows, out as it settles. '
        'A slow, even rhythm is the core biofeedback activity in NeuroPulse.',
    icon: Icons.air_rounded,
    accent: Color(0xFF3E8E7E),
    estimatedDuration: Duration(minutes: 2),
    recommendedLevels: [3, 4, 5],
    isCalming: true,
  );

  static const GameDefinition pulseRunner = GameDefinition(
    id: GameIds.pulseRunner,
    name: 'Pulse Runner',
    tagline: 'Gentle endless runner',
    description:
        'Hop over obstacles and collect orbs. The pace adapts to your current '
        'estimate, so a higher reading gives you a calmer run.',
    icon: Icons.directions_run_rounded,
    accent: Color(0xFF6C7BE0),
    estimatedDuration: Duration(minutes: 2),
    recommendedLevels: [1, 2],
    isCalming: false,
  );

  static const GameDefinition zenGarden = GameDefinition(
    id: GameIds.zenGarden,
    name: 'Zen Garden',
    tagline: 'Arrange a calm space',
    description:
        'Place stones, flowers and water wherever you like. Nothing to win, '
        'nothing to lose. Your garden is saved between sessions.',
    icon: Icons.local_florist_rounded,
    accent: Color(0xFF7FA65C),
    estimatedDuration: Duration(minutes: 3),
    recommendedLevels: [1, 2, 4, 5],
    isCalming: true,
  );

  static const GameDefinition focusBlocks = GameDefinition(
    id: GameIds.focusBlocks,
    name: 'Focus Blocks',
    tagline: 'Remember the sequence',
    description:
        'Watch the blocks light up, then repeat the pattern. Sequence length '
        'adapts to your current estimate.',
    icon: Icons.grid_view_rounded,
    accent: Color(0xFF9B6CC4),
    estimatedDuration: Duration(minutes: 2),
    recommendedLevels: [2, 3],
    isCalming: false,
  );

  static const GameDefinition calmCatch = GameDefinition(
    id: GameIds.calmCatch,
    name: 'Calm Catch',
    tagline: 'Catch what falls',
    description:
        'Gather stars, leaves and droplets in your basket. Fall speed eases '
        'off when your estimate is higher.',
    icon: Icons.auto_awesome_rounded,
    accent: Color(0xFFD79A4A),
    estimatedDuration: Duration(minutes: 2),
    recommendedLevels: [1, 2, 3],
    isCalming: false,
  );

  /// All games, in the order shown on the Games screen.
  static const List<GameDefinition> all = [
    calmBreathing,
    pulseRunner,
    zenGarden,
    focusBlocks,
    calmCatch,
  ];

  static GameDefinition byId(String id) => all.firstWhere(
    (game) => game.id == id,
    orElse: () => throw ArgumentError('Unknown game id: $id'),
  );

  static GameDefinition? tryById(String id) {
    for (final game in all) {
      if (game.id == id) return game;
    }
    return null;
  }
}
