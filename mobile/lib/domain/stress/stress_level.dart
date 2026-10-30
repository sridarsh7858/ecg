import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The five project-defined stress levels.
///
/// These are *project* levels, not clinical categories. The numbering is fixed
/// (1..5) and is the contract shared by the prediction engine, the UI, the game
/// recommendation service and the persisted history.
enum StressLevel {
  veryLow(1),
  low(2),
  moderate(3),
  high(4),
  veryHigh(5);

  const StressLevel(this.number);

  /// 1..5
  final int number;

  /// Maps an integer 1..5 to a [StressLevel]. Values outside the range are
  /// clamped rather than throwing, so bad persisted data cannot crash the app.
  static StressLevel fromNumber(int number) {
    final clamped = number.clamp(1, 5);
    return StressLevel.values.firstWhere((level) => level.number == clamped);
  }

  StressLevel get previous => fromNumber(number - 1);

  StressLevel get next => fromNumber(number + 1);
}

/// Everything the UI needs to render a stress level.
///
/// Instances are created only by [StressLevelConfig] so that level semantics
/// live in exactly one place.
@immutable
class StressLevelInfo {
  const StressLevelInfo({
    required this.level,
    required this.title,
    required this.description,
    required this.recommendation,
    required this.motivation,
    required this.suggestedGameIds,
    required this.icon,
    required this.lightColor,
    required this.darkColor,
  });

  final StressLevel level;

  /// Short display title, e.g. "Moderate".
  final String title;

  /// One sentence describing the state, in supportive language.
  final String description;

  /// What the app suggests the user does next.
  final String recommendation;

  /// Encouraging one-liner shown on result screens.
  final String motivation;

  /// Ordered game ids; the first entry is the primary recommendation.
  final List<String> suggestedGameIds;

  /// Non-colour visual cue, so meaning is never carried by colour alone.
  final IconData icon;

  final Color lightColor;
  final Color darkColor;

  int get number => level.number;

  /// Uppercase label used by the large stress readout, e.g. "MODERATE".
  String get upperTitle => title.toUpperCase();

  /// e.g. "Level 3"
  String get levelLabel => 'Level $number';

  /// Resolves the accent colour for the active brightness.
  Color color(Brightness brightness) =>
      brightness == Brightness.dark ? darkColor : lightColor;

  /// Convenience for widgets that already have a [BuildContext].
  Color colorOf(BuildContext context) => color(Theme.of(context).brightness);
}

/// Central registry of stress-level metadata.
///
/// Nothing else in the app is allowed to hard-code a level's title, colour,
/// copy or recommended game. Adding a level, renaming one, or re-tuning the
/// recommendations is a single-file change.
class StressLevelConfig {
  const StressLevelConfig._();

  static const Map<StressLevel, StressLevelInfo> _levels = {
    StressLevel.veryLow: StressLevelInfo(
      level: StressLevel.veryLow,
      title: 'Very Low',
      description: "You're in a calm, settled state.",
      recommendation: 'Maintain your relaxed state with a gentle activity.',
      motivation: 'Lovely. Calm is a skill, and you are practising it.',
      suggestedGameIds: ['zen_garden', 'calm_catch', 'pulse_runner'],
      icon: Icons.spa_outlined,
      lightColor: AppColors.level1,
      darkColor: AppColors.level1Dark,
    ),
    StressLevel.low: StressLevelInfo(
      level: StressLevel.low,
      title: 'Low',
      description: 'You seem relaxed with plenty of headroom.',
      recommendation: 'A light, playful session will keep things steady.',
      motivation: 'Nicely balanced. Enjoy the easy pace.',
      suggestedGameIds: ['zen_garden', 'calm_catch', 'pulse_runner'],
      icon: Icons.self_improvement_outlined,
      lightColor: AppColors.level2,
      darkColor: AppColors.level2Dark,
    ),
    StressLevel.moderate: StressLevelInfo(
      level: StressLevel.moderate,
      title: 'Moderate',
      description: 'You are alert and engaged, with some tension building.',
      recommendation: 'A short focus or breathing session can help you reset.',
      motivation: 'A good moment for a small reset. A few minutes is enough.',
      suggestedGameIds: ['calm_breathing', 'focus_blocks', 'calm_catch'],
      icon: Icons.air_outlined,
      lightColor: AppColors.level3,
      darkColor: AppColors.level3Dark,
    ),
    StressLevel.high: StressLevelInfo(
      level: StressLevel.high,
      title: 'High',
      description: 'Your readings suggest you are carrying a fair bit of load.',
      recommendation: 'Take a short calming break with guided breathing.',
      motivation: 'Be kind to yourself. Slowing down is progress.',
      suggestedGameIds: ['calm_breathing', 'zen_garden', 'calm_catch'],
      icon: Icons.waves_outlined,
      lightColor: AppColors.level4,
      darkColor: AppColors.level4Dark,
    ),
    StressLevel.veryHigh: StressLevelInfo(
      level: StressLevel.veryHigh,
      title: 'Very High',
      description: 'You appear to be under a lot of pressure right now.',
      recommendation: 'Give yourself a longer guided breathing session.',
      motivation: 'One slow breath at a time. You have already started.',
      suggestedGameIds: ['calm_breathing', 'zen_garden'],
      icon: Icons.nights_stay_outlined,
      lightColor: AppColors.level5,
      darkColor: AppColors.level5Dark,
    ),
  };

  /// All levels ordered 1 -> 5.
  static List<StressLevelInfo> get all =>
      StressLevel.values.map(of).toList(growable: false);

  static StressLevelInfo of(StressLevel level) => _levels[level]!;

  static StressLevelInfo ofNumber(int number) =>
      of(StressLevel.fromNumber(number));
}
