import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_widgets.dart';
import '../../domain/games/game_catalog.dart';
import '../../state/stress_controller.dart';
import 'game_launcher.dart';
import 'widgets/game_card.dart';

/// The activity picker. The recommendation is pinned to the top and repeated
/// in place, so the suggested game is impossible to miss but never the only
/// option.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stress = context.watch<StressController>();
    final recommendation = stress.recommendation;
    final info = stress.currentInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose an activity')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    color: info.colorOf(context).withValues(alpha: 0.10),
                    child: Row(
                      children: [
                        Icon(info.icon, color: info.colorOf(context)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Suggestions are based on your current estimate: '
                            'level ${info.number}, ${info.title.toLowerCase()}.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Recommended for you'),
                  RecommendedGameCard(
                    game: recommendation.primary,
                    reason: recommendation.reason,
                    onPlay: () =>
                        GameLauncher.play(context, recommendation.primary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(
                    title: 'All activities',
                    subtitle: 'Play whichever appeals right now',
                  ),
                  for (final game in GameCatalog.all) ...[
                    GameCard(
                      game: game,
                      isRecommended: game.id == recommendation.primary.id,
                      onPlay: () => GameLauncher.play(context, game),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
