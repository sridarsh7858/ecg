import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../domain/games/game_catalog.dart';

/// A game entry in the Games list.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onPlay,
    this.isRecommended = false,
  });

  final GameDefinition game;
  final VoidCallback onPlay;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onPlay,
      semanticLabel: isRecommended
          ? '${game.name}, recommended for you. ${game.tagline}'
          : '${game.name}. ${game.tagline}',
      border: isRecommended
          ? BorderSide(color: game.accent.withValues(alpha: 0.55), width: 1.6)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRecommended) ...[
            AppChip(
              label: 'Recommended for you',
              icon: Icons.auto_awesome_rounded,
              color: game.accent,
              dense: true,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: game.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(game.icon, color: game.accent, size: 26),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.tagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            game.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppChip(
                      label: game.durationLabel,
                      icon: Icons.schedule_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                      dense: true,
                    ),
                    AppChip(
                      label: game.levelsLabel,
                      icon: Icons.stacked_line_chart_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                      dense: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: onPlay,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 44),
                  backgroundColor: game.accent.withValues(alpha: 0.16),
                  foregroundColor: game.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                ),
                child: const Text('PLAY'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The large "Recommended for you" block used on Home and the result screen.
class RecommendedGameCard extends StatelessWidget {
  const RecommendedGameCard({
    super.key,
    required this.game,
    required this.reason,
    required this.onPlay,
    this.buttonLabel = 'PLAY NOW',
  });

  final GameDefinition game;
  final String reason;
  final VoidCallback onPlay;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  game.accent.withValues(alpha: 0.20),
                  game.accent.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(game.icon, color: game.accent, size: 28),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${game.tagline}  -  ${game.durationLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  reason,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onPlay,
                  style: FilledButton.styleFrom(
                    backgroundColor: game.accent,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(buttonLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
