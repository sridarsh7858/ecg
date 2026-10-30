import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/game_session.dart';
import '../../../domain/games/game_catalog.dart';
import '../../../domain/stress/stress_level.dart';
import '../../../state/settings_controller.dart';
import '../../../state/stress_controller.dart';
import '../widgets/game_scaffold.dart';

/// What the game is doing right now.
enum FocusPhase { ready, showing, recalling, feedback, over }

/// A memory and sequence game on a 3x3 grid.
///
/// Difficulty adapts to the current estimate: a higher reading gives a shorter
/// starting sequence and a slower flash, so the game stays approachable rather
/// than becoming another source of pressure.
class FocusBlocksScreen extends StatefulWidget {
  const FocusBlocksScreen({super.key});

  @override
  State<FocusBlocksScreen> createState() => _FocusBlocksScreenState();
}

class _FocusBlocksScreenState extends State<FocusBlocksScreen> {
  static const int gridSize = 3;
  static const int cells = gridSize * gridSize;

  /// The run ends after this many mistakes.
  static const int maxMistakes = 3;

  static const List<Color> _blockColors = [
    Color(0xFF3E8E7E),
    Color(0xFF6C7BE0),
    Color(0xFF9B6CC4),
    Color(0xFFD79A4A),
    Color(0xFF57A85B),
    Color(0xFFC96B7E),
    Color(0xFF4A9BC4),
    Color(0xFFB0894A),
    Color(0xFF7FA65C),
  ];

  final math.Random _random = math.Random();
  final List<int> _sequence = [];

  late final DateTime _startedAt;
  late final _FocusTuning _tuning;

  Timer? _timer;
  FocusPhase _phase = FocusPhase.ready;
  int _highlighted = -1;
  int _inputIndex = 0;
  int _round = 0;
  int _score = 0;
  int _mistakes = 0;
  int _correctTaps = 0;
  int _totalTaps = 0;
  bool _lastTapCorrect = true;
  bool _paused = false;
  bool _finished = false;

  double get _accuracy => _totalTaps == 0 ? 1 : _correctTaps / _totalTaps;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _tuning = _FocusTuning.forLevel(
      context.read<StressController>().currentLevel,
    );
    // A short beat before the first sequence, so the grid is not already
    // flashing when the screen appears.
    _timer = Timer(const Duration(milliseconds: 600), _nextRound);
  }

  void _nextRound() {
    if (!mounted || _finished) return;

    _round++;
    _inputIndex = 0;
    _sequence.clear();

    final length = _tuning.startLength + (_round - 1) ~/ 2;
    var previous = -1;
    for (var i = 0; i < length; i++) {
      // Avoid repeating the same cell twice in a row: it reads as one long
      // flash rather than two steps.
      var next = _random.nextInt(cells);
      while (next == previous) {
        next = _random.nextInt(cells);
      }
      _sequence.add(next);
      previous = next;
    }

    setState(() => _phase = FocusPhase.showing);
    _playSequence(0);
  }

  void _playSequence(int index) {
    if (!mounted || _finished) return;
    if (_paused) {
      // Resume picks the sequence up from the same step.
      _timer = Timer(
        const Duration(milliseconds: 300),
        () => _playSequence(index),
      );
      return;
    }

    if (index >= _sequence.length) {
      setState(() {
        _highlighted = -1;
        _phase = FocusPhase.recalling;
      });
      return;
    }

    setState(() => _highlighted = _sequence[index]);
    _timer = Timer(_tuning.flashOn, () {
      if (!mounted) return;
      setState(() => _highlighted = -1);
      _timer = Timer(_tuning.flashOff, () => _playSequence(index + 1));
    });
  }

  void _onTap(int index) {
    if (_phase != FocusPhase.recalling || _paused || _finished) return;

    final haptics = context.read<SettingsController>().hapticsEnabled;
    _totalTaps++;

    if (_sequence[_inputIndex] == index) {
      _correctTaps++;
      _inputIndex++;
      _lastTapCorrect = true;
      if (haptics) HapticFeedback.selectionClick();

      setState(() => _highlighted = index);
      _timer = Timer(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        setState(() => _highlighted = -1);
      });

      if (_inputIndex >= _sequence.length) {
        // Longer sequences are worth more, so progress feels earned.
        _score += _sequence.length * 10;
        setState(() => _phase = FocusPhase.feedback);
        _timer = Timer(const Duration(milliseconds: 700), _nextRound);
      }
      return;
    }

    _mistakes++;
    _lastTapCorrect = false;
    if (haptics) HapticFeedback.mediumImpact();

    if (_mistakes >= maxMistakes) {
      setState(() => _phase = FocusPhase.over);
      _timer = Timer(const Duration(milliseconds: 900), _finish);
      return;
    }

    // A mistake replays the same sequence rather than ending the round.
    setState(() => _phase = FocusPhase.feedback);
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || _finished) return;
      _inputIndex = 0;
      setState(() => _phase = FocusPhase.showing);
      _playSequence(0);
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();

    Navigator.of(context).pop(
      GameResult(
        gameId: GameIds.focusBlocks,
        duration: DateTime.now().difference(_startedAt),
        score: _score,
        // Reaching round three is treated as a full session.
        completion: (_round / 3).clamp(0.0, 1.0),
        metrics: {
          'rounds': _round,
          'accuracy': double.parse(_accuracy.toStringAsFixed(2)),
          'mistakes': _mistakes,
          'longestSequence': _sequence.length,
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _statusText => switch (_phase) {
    FocusPhase.ready => 'Get ready',
    FocusPhase.showing => 'Watch the sequence',
    FocusPhase.recalling => 'Your turn - repeat it',
    FocusPhase.feedback =>
      _lastTapCorrect ? 'Nice. Here comes the next one' : 'Close. Watch again',
    FocusPhase.over => 'Session complete',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = GameCatalog.focusBlocks;
    final elapsed = DateTime.now().difference(_startedAt);

    return GameScaffold(
      game: game,
      isPaused: _paused,
      onPause: () => setState(() => _paused = true),
      onResume: () => setState(() => _paused = false),
      onEnd: _finish,
      hud: [
        GameHudItem(label: 'Score', value: '$_score'),
        GameHudItem(label: 'Round', value: '$_round'),
        GameHudItem(label: 'Accuracy', value: '${(_accuracy * 100).round()}%'),
        GameHudItem(label: 'Time', value: Formatters.duration(elapsed)),
      ],
      footer: Column(
        children: [
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < maxMistakes; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    i < maxMistakes - _mistakes
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'lives',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AspectRatio(
            aspectRatio: 1,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridSize,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
              ),
              itemCount: cells,
              itemBuilder: (context, index) {
                final isLit = _highlighted == index;
                final color = _blockColors[index];
                final interactive = _phase == FocusPhase.recalling;

                return Semantics(
                  button: true,
                  enabled: interactive,
                  label: 'Block ${index + 1}${isLit ? ", lit" : ""}',
                  child: GestureDetector(
                    onTap: () => _onTap(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: isLit
                            ? color
                            : color.withValues(
                                alpha: interactive ? 0.20 : 0.12,
                              ),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isLit ? color : color.withValues(alpha: 0.35),
                          width: isLit ? 3 : 1.5,
                        ),
                      ),
                      // A shape as well as a colour change, so the lit state
                      // is visible without relying on colour perception.
                      child: Center(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 140),
                          scale: isLit ? 1 : 0,
                          child: Icon(
                            Icons.circle,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Difficulty settings derived from the current estimate.
class _FocusTuning {
  const _FocusTuning({
    required this.startLength,
    required this.flashOn,
    required this.flashOff,
  });

  final int startLength;
  final Duration flashOn;
  final Duration flashOff;

  factory _FocusTuning.forLevel(StressLevel level) {
    return switch (level) {
      StressLevel.veryLow || StressLevel.low => const _FocusTuning(
        startLength: 4,
        flashOn: Duration(milliseconds: 420),
        flashOff: Duration(milliseconds: 160),
      ),
      StressLevel.moderate => const _FocusTuning(
        startLength: 3,
        flashOn: Duration(milliseconds: 520),
        flashOff: Duration(milliseconds: 200),
      ),
      StressLevel.high || StressLevel.veryHigh => const _FocusTuning(
        startLength: 2,
        flashOn: Duration(milliseconds: 640),
        flashOff: Duration(milliseconds: 260),
      ),
    };
  }
}
