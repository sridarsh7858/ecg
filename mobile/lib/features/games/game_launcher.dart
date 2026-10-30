import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/game_session.dart';
import '../../domain/games/game_catalog.dart';
import '../../state/stress_controller.dart';
import 'calm_catch/calm_catch_screen.dart';
import 'breathing/breathing_screen.dart';
import 'focus_blocks/focus_blocks_screen.dart';
import 'game_result_screen.dart';
import 'pulse_runner/pulse_runner_screen.dart';
import 'zen_garden/zen_garden_screen.dart';

/// Single entry point for starting any game.
///
/// Every game screen returns a [GameResult] (or null when abandoned). The
/// launcher records it through [StressController] and then shows the shared
/// before/after result screen, so no individual game deals with persistence or
/// with the biofeedback comparison.
class GameLauncher {
  const GameLauncher._();

  /// Builds the screen for [game]. Kept separate so the mapping is testable.
  static Widget screenFor(GameDefinition game) {
    return switch (game.id) {
      GameIds.calmBreathing => const BreathingScreen(),
      GameIds.pulseRunner => const PulseRunnerScreen(),
      GameIds.zenGarden => const ZenGardenScreen(),
      GameIds.focusBlocks => const FocusBlocksScreen(),
      GameIds.calmCatch => const CalmCatchScreen(),
      _ => const BreathingScreen(),
    };
  }

  /// Plays [game], records the outcome and shows the result screen.
  ///
  /// [measurementId] links the play-through back to the check-in it came from,
  /// which is what lets History show a before/after pair.
  static Future<GameSession?> play(
    BuildContext context,
    GameDefinition game, {
    String? measurementId,
  }) async {
    final controller = context.read<StressController>();
    final preLevel = controller.currentLevel;
    final startedAt = DateTime.now();
    final navigator = Navigator.of(context);

    final result = await navigator.push<GameResult>(
      MaterialPageRoute(builder: (_) => screenFor(game)),
    );

    if (result == null) return null;

    final session = await controller.recordGameResult(
      result: result,
      startTime: startedAt,
      preLevel: preLevel,
      measurementId: measurementId,
    );

    if (!navigator.mounted) return session;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => GameResultScreen(session: session, game: game),
      ),
    );

    return session;
  }
}
