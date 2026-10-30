import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../domain/games/game_catalog.dart';

/// Shared chrome for every mini-game: title bar, a HUD strip, a pause overlay
/// and a confirmation before abandoning a session.
///
/// Each game supplies only its own play area and HUD values, which keeps the
/// five games consistent without them sharing any gameplay code.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.game,
    required this.child,
    this.hud = const [],
    this.isPaused = false,
    this.onPause,
    this.onResume,
    this.onEnd,
    this.footer,
    this.background,
  });

  final GameDefinition game;

  /// The play area.
  final Widget child;

  /// Small live values shown under the app bar.
  final List<GameHudItem> hud;

  final bool isPaused;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  /// Called when the user chooses to finish. The game is responsible for
  /// popping with its [GameResult].
  final VoidCallback? onEnd;

  final Widget? footer;
  final Color? background;

  Future<bool> _confirmExit(BuildContext context) async {
    if (onEnd == null) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text('Your progress so far will still be recorded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit(context)) onEnd?.call();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          title: Text(game.name),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'End session',
            onPressed: () async {
              if (await _confirmExit(context)) onEnd?.call();
            },
          ),
          actions: [
            if (onPause != null)
              IconButton(
                tooltip: isPaused ? 'Resume' : 'Pause',
                onPressed: isPaused ? onResume : onPause,
                icon: Icon(
                  isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (hud.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    0,
                    AppSpacing.page,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      for (final item in hud)
                        Expanded(child: _HudTile(item: item)),
                    ],
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: child),
                    if (isPaused)
                      Positioned.fill(
                        child: _PauseOverlay(
                          onResume: onResume,
                          onEnd: onEnd,
                          accent: game.accent,
                        ),
                      ),
                  ],
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.md,
                    AppSpacing.page,
                    AppSpacing.lg,
                  ),
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodyMedium!,
                    child: footer!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One value in the HUD strip.
class GameHudItem {
  const GameHudItem({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;
}

class _HudTile extends StatelessWidget {
  const _HudTile({required this.item});

  final GameHudItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${item.label} ${item.value}',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.onResume,
    required this.onEnd,
    required this.accent,
  });

  final VoidCallback? onResume;
  final VoidCallback? onEnd;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface.withValues(alpha: 0.90),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pause_circle_outline_rounded, size: 56, color: accent),
              const SizedBox(height: AppSpacing.lg),
              Text('Paused', style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Take your time. Nothing is running.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('RESUME'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onEnd, child: const Text('End session')),
            ],
          ),
        ),
      ),
    );
  }
}
