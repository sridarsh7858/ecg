import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuropulse/app/dependencies.dart';
import 'package:neuropulse/data/local/local_store.dart';
import 'package:neuropulse/data/models/game_session.dart';
import 'package:neuropulse/domain/games/game_catalog.dart';
import 'package:neuropulse/domain/stress/stress_level.dart';
import 'package:neuropulse/features/games/game_launcher.dart';
import 'package:neuropulse/state/settings_controller.dart';
import 'package:neuropulse/state/stress_controller.dart';
import 'package:provider/provider.dart';

import 'support/test_harness.dart';

/// Drives each of the five games for real: renders it, plays for a moment,
/// ends it, and checks the standardised [GameResult] that comes back.
void main() {
  /// Advances a fixed number of frames.
  ///
  /// The games drive a Ticker or a repeating AnimationController on purpose,
  /// so there is never a settled frame to wait for - pumpAndSettle would time
  /// out. Pumping a bounded number of frames is the correct tool here.
  Future<void> advance(
    WidgetTester tester, {
    int frames = 12,
    Duration step = const Duration(milliseconds: 40),
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  /// Pumps [game] and returns the result it pops with.
  Future<GameResult?> playGame(
    WidgetTester tester,
    GameDefinition game, {
    required Future<void> Function(WidgetTester tester) interact,
    StressLevel level = StressLevel.moderate,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final deps = await TestHarness.dependencies(
      initialPrefs: TestHarness.signedInPrefs(),
    );
    await deps.stressController.setDemoLevel(level);

    GameResult? result;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDependencies>.value(value: deps),
          Provider<LocalStore>.value(value: deps.store),
          ChangeNotifierProvider<SettingsController>.value(
            value: deps.settingsController,
          ),
          ChangeNotifierProvider<StressController>.value(
            value: deps.stressController,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<GameResult>(
                      MaterialPageRoute(
                        builder: (_) => GameLauncher.screenFor(game),
                      ),
                    );
                  },
                  child: const Text('start'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await advance(tester);

    expect(find.text(game.name), findsWidgets, reason: 'title for ${game.id}');

    await interact(tester);
    await advance(tester);

    return result;
  }

  /// Ends a game through the app-bar close button and its confirmation.
  Future<void> endViaAppBar(WidgetTester tester) async {
    await tester.tap(find.byTooltip('End session'));
    await advance(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'End session'));
    await advance(tester);
  }

  void expectValidResult(GameResult? result, String expectedGameId) {
    expect(result, isNotNull, reason: 'no result from $expectedGameId');
    expect(result!.gameId, expectedGameId);
    expect(result.completion, inInclusiveRange(0.0, 1.0));
    expect(result.score, greaterThanOrEqualTo(0));
    expect(result.duration, greaterThanOrEqualTo(Duration.zero));
  }

  testWidgets('Calm Breathing runs and reports breaths', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.calmBreathing,
      interact: (tester) async {
        // Let the animation run through part of a breath cycle.
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Breathe in'), findsOneWidget);

        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Breathe out'), findsOneWidget);

        await tester.tap(find.text('END'));
      },
    );

    expectValidResult(result, GameIds.calmBreathing);
    expect(result!.metrics.containsKey('breaths'), isTrue);
    expect(result.metrics.containsKey('targetSeconds'), isTrue);
  });

  testWidgets('Calm Breathing pauses and resumes', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.calmBreathing,
      interact: (tester) async {
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('PAUSE'));
        await advance(tester);

        expect(find.text('Paused'), findsOneWidget);
        expect(find.text('RESUME'), findsWidgets);

        await tester.tap(find.text('RESUME').last);
        await advance(tester);
        expect(find.text('Paused'), findsNothing);

        await tester.tap(find.text('END'));
      },
    );

    expectValidResult(result, GameIds.calmBreathing);
  });

  // The session length adapts to the current estimate: a higher reading earns
  // a longer reset. Asserted as two tests rather than one, because pumping two
  // full app trees into a single tester leaves navigation mid-flight.
  testWidgets('Calm Breathing runs a short session at level 1', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.calmBreathing,
      level: StressLevel.veryLow,
      interact: (tester) async => tester.tap(find.text('END')),
    );

    expectValidResult(result, GameIds.calmBreathing);
    expect(result!.metrics['targetSeconds'], 90);
  });

  testWidgets('Calm Breathing runs a longer session at level 5', (
    tester,
  ) async {
    final result = await playGame(
      tester,
      GameCatalog.calmBreathing,
      level: StressLevel.veryHigh,
      interact: (tester) async => tester.tap(find.text('END')),
    );

    expectValidResult(result, GameIds.calmBreathing);
    expect(result!.metrics['targetSeconds'], 180);
  });

  testWidgets('Pulse Runner runs, accepts a jump and ends', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.pulseRunner,
      interact: (tester) async {
        await tester.pump(const Duration(milliseconds: 300));
        // Tap the play area to hop.
        await tester.tapAt(const Offset(210, 500));
        await tester.pump(const Duration(milliseconds: 600));
        await endViaAppBar(tester);
      },
    );

    expectValidResult(result, GameIds.pulseRunner);
    expect(result!.metrics.containsKey('orbs'), isTrue);
    expect(result.metrics.containsKey('distance'), isTrue);
  });

  testWidgets('Zen Garden places objects and persists them', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.zenGarden,
      interact: (tester) async {
        expect(find.textContaining('Tap anywhere to place'), findsOneWidget);

        for (final offset in [
          const Offset(120, 400),
          const Offset(220, 450),
          const Offset(300, 380),
        ]) {
          await tester.tapAt(offset);
          await advance(tester);
        }

        // Selecting a different item keeps the canvas working.
        await tester.tap(find.text('Flower'));
        await advance(tester);
        await tester.tapAt(const Offset(180, 520));
        await advance(tester);

        await tester.tap(find.text('DONE'));
      },
    );

    expectValidResult(result, GameIds.zenGarden);
    expect(result!.metrics['placedThisSession'], 4);
    expect(result.metrics['gardenSize'], 4);
  });

  testWidgets('Zen Garden undo removes the last object', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.zenGarden,
      interact: (tester) async {
        await tester.tapAt(const Offset(150, 400));
        await advance(tester);
        await tester.tapAt(const Offset(250, 430));
        await advance(tester);

        await tester.tap(find.text('UNDO'));
        await advance(tester);

        await tester.tap(find.text('DONE'));
      },
    );

    expectValidResult(result, GameIds.zenGarden);
    expect(result!.metrics['gardenSize'], 1);
  });

  testWidgets('Focus Blocks shows a sequence and accepts input', (
    tester,
  ) async {
    final result = await playGame(
      tester,
      GameCatalog.focusBlocks,
      interact: (tester) async {
        expect(find.text('Get ready'), findsOneWidget);

        // Let the first sequence play out.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 4));
        expect(find.textContaining('Your turn'), findsOneWidget);

        await endViaAppBar(tester);
      },
    );

    expectValidResult(result, GameIds.focusBlocks);
    expect(result!.metrics.containsKey('accuracy'), isTrue);
    expect(result.metrics.containsKey('rounds'), isTrue);
  });

  testWidgets('Focus Blocks reaches recall at a high stress level too', (
    tester,
  ) async {
    // Level 5 starts at a two-block sequence with slower flashes, so it must
    // still reach the recall phase within the same window.
    final result = await playGame(
      tester,
      GameCatalog.focusBlocks,
      level: StressLevel.veryHigh,
      interact: (tester) async {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 5));
        expect(find.textContaining('Your turn'), findsOneWidget);
        await endViaAppBar(tester);
      },
    );
    expectValidResult(result, GameIds.focusBlocks);
  });

  testWidgets('Calm Catch runs, moves the basket and ends', (tester) async {
    final result = await playGame(
      tester,
      GameCatalog.calmCatch,
      interact: (tester) async {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.drag(find.byType(CustomPaint).last, const Offset(-60, 0));
        await tester.pump(const Duration(milliseconds: 600));
        await endViaAppBar(tester);
      },
    );

    expectValidResult(result, GameIds.calmCatch);
    expect(result!.metrics.containsKey('caught'), isTrue);
    expect(result.metrics.containsKey('accuracy'), isTrue);
  });

  testWidgets('every catalogued game has a screen', (tester) async {
    for (final game in GameCatalog.all) {
      expect(
        GameLauncher.screenFor(game),
        isA<Widget>(),
        reason: 'no screen registered for ${game.id}',
      );
    }
  });
}
