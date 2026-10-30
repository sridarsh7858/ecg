import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/game_session.dart';
import '../../domain/games/game_catalog.dart';
import '../../domain/stress/stress_level.dart';

/// Shown after a game finishes: what happened, and the before/after estimate.
///
/// The post-session level is simulated for now, and the copy says so. It
/// describes a change in the estimate, and makes no claim that the game
/// treated anything.
class GameResultScreen extends StatelessWidget {
  const GameResultScreen({
    super.key,
    required this.session,
    required this.game,
  });

  final GameSession session;
  final GameDefinition game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final before = StressLevelConfig.of(session.preStressLevel);
    final after = StressLevelConfig.of(session.postStressLevel);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Session complete'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: game.accent.withValues(alpha: 0.14),
                    ),
                    child: Icon(game.icon, size: 44, color: game.accent),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Session Complete',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  game.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'Duration',
                          value: Formatters.duration(session.duration),
                          icon: Icons.schedule_rounded,
                          compact: true,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Score',
                          value: '${session.score}',
                          icon: Icons.star_outline_rounded,
                          compact: true,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Completed',
                          value: '${(session.completion * 100).round()}%',
                          icon: Icons.check_circle_outline_rounded,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.metrics.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Session detail',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final entry in session.metrics.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _humanise(entry.key),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatMetric(entry.key, entry.value),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(
                  title: 'Estimated stress level',
                  subtitle: 'Before and after this session',
                ),
                AppCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _LevelBlock(label: 'BEFORE', info: before),
                          ),
                          Icon(
                            session.improved
                                ? Icons.arrow_forward_rounded
                                : Icons.horizontal_rule_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          Expanded(
                            child: _LevelBlock(label: 'AFTER', info: after),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        session.improved
                            ? 'Your estimated stress level changed during '
                                  'this session.'
                            : 'Your estimated stress level stayed where it '
                                  'was during this session.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'The after value is simulated for this prototype. '
                        'Once the sensor is connected it will come from a '
                        'fresh measurement.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('DONE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "placedThisSession" -> "Placed this session"
  static String _humanise(String key) {
    final spaced = key.replaceAllMapped(
      RegExp(r'(?<=[a-z])(?=[A-Z])'),
      (_) => ' ',
    );
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }

  static String _formatMetric(String key, num value) {
    if (key == 'accuracy') return '${(value * 100).round()}%';
    if (value is int || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _LevelBlock extends StatelessWidget {
  const _LevelBlock({required this.label, required this.info});

  final String label;
  final StressLevelInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = info.colorOf(context);

    return Semantics(
      label: '$label level ${info.number}, ${info.title}',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${info.number}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            info.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
