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

/// The phase of one breath cycle.
enum BreathPhase {
  inhale('Breathe in'),
  holdIn('Hold'),
  exhale('Breathe out');

  const BreathPhase(this.label);

  final String label;
}

/// Guided paced breathing - the primary biofeedback activity.
///
/// The default rhythm is 4 seconds in, a short hold, then 6 seconds out. A
/// longer exhale than inhale is the conventional pacing for downregulation.
/// Higher current estimates get a slightly longer, slower session.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _inhale = Duration(milliseconds: 4000);
  static const Duration _holdIn = Duration(milliseconds: 700);
  static const Duration _exhale = Duration(milliseconds: 6000);

  late final AnimationController _cycle;
  late final Duration _target;
  late final DateTime _startedAt;

  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  int _breaths = 0;
  bool _paused = false;
  bool _finished = false;
  BreathPhase _phase = BreathPhase.inhale;

  static final Duration _cycleLength = _inhale + _holdIn + _exhale;

  /// Fractions of the cycle spent in each phase.
  static final double _inhaleEnd =
      _inhale.inMilliseconds / _cycleLength.inMilliseconds;
  static final double _holdEnd =
      (_inhale + _holdIn).inMilliseconds / _cycleLength.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _target = _targetDuration();

    _cycle = AnimationController(vsync: this, duration: _cycleLength)
      ..addListener(_onCycleTick)
      ..repeat();

    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_paused || _finished) return;
      setState(() => _elapsed += const Duration(milliseconds: 200));
      if (_elapsed >= _target) _finish();
    });
  }

  /// A higher current estimate earns a longer session, since that is when a
  /// longer reset is most useful.
  Duration _targetDuration() {
    final level = context.read<StressController>().currentLevel;
    return switch (level) {
      StressLevel.veryLow || StressLevel.low => const Duration(seconds: 90),
      StressLevel.moderate => const Duration(seconds: 120),
      StressLevel.high => const Duration(seconds: 150),
      StressLevel.veryHigh => const Duration(seconds: 180),
    };
  }

  void _onCycleTick() {
    final value = _cycle.value;
    final phase = value < _inhaleEnd
        ? BreathPhase.inhale
        : value < _holdEnd
        ? BreathPhase.holdIn
        : BreathPhase.exhale;

    if (phase == _phase) return;

    // A completed breath is the wrap from the end of an exhale back to an
    // inhale, which is also where a gentle haptic cue belongs.
    if (_phase == BreathPhase.exhale && phase == BreathPhase.inhale) {
      _breaths++;
      if (context.read<SettingsController>().hapticsEnabled) {
        HapticFeedback.selectionClick();
      }
    }

    setState(() => _phase = phase);
  }

  /// Circle scale in 0.45 .. 1.0, expanding on the inhale.
  double get _scale {
    final value = _cycle.value;
    if (value < _inhaleEnd) {
      final t = value / _inhaleEnd;
      return 0.45 + 0.55 * Curves.easeInOut.transform(t);
    }
    if (value < _holdEnd) return 1.0;
    final t = (value - _holdEnd) / (1 - _holdEnd);
    return 1.0 - 0.55 * Curves.easeInOut.transform(t);
  }

  void _pause() {
    _cycle.stop();
    setState(() => _paused = true);
  }

  void _resume() {
    _cycle.repeat();
    setState(() => _paused = false);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _cycle.stop();
    _ticker?.cancel();

    final completion = (_elapsed.inMilliseconds / _target.inMilliseconds).clamp(
      0.0,
      1.0,
    );

    Navigator.of(context).pop(
      GameResult(
        gameId: GameIds.calmBreathing,
        duration: DateTime.now().difference(_startedAt),
        // A calm session is scored on breaths completed, not on speed.
        score: _breaths * 10,
        completion: completion,
        metrics: {
          'breaths': _breaths,
          'targetSeconds': _target.inSeconds,
          'elapsedSeconds': _elapsed.inSeconds,
        },
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = GameCatalog.calmBreathing;
    final progress = (_elapsed.inMilliseconds / _target.inMilliseconds).clamp(
      0.0,
      1.0,
    );

    return GameScaffold(
      game: game,
      isPaused: _paused,
      onPause: _pause,
      onResume: _resume,
      onEnd: _finish,
      hud: [
        GameHudItem(label: 'Breaths', value: '$_breaths'),
        GameHudItem(label: 'Elapsed', value: Formatters.duration(_elapsed)),
        GameHudItem(
          label: 'Remaining',
          value: Formatters.duration(
            _target - _elapsed < Duration.zero
                ? Duration.zero
                : _target - _elapsed,
          ),
        ),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _paused ? _resume : _pause,
                  icon: Icon(
                    _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 20,
                  ),
                  label: Text(_paused ? 'RESUME' : 'PAUSE'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('END'),
                ),
              ),
            ],
          ),
        ],
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _cycle,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final maxSize = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final diameter = maxSize * 0.82 * _scale;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: maxSize * 0.85,
                      height: maxSize * 0.85,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Static guide ring showing the full extent.
                          Container(
                            width: maxSize * 0.84,
                            height: maxSize * 0.84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: game.accent.withValues(alpha: 0.18),
                                width: 1.5,
                              ),
                            ),
                          ),
                          Container(
                            width: diameter,
                            height: diameter,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  game.accent.withValues(alpha: 0.42),
                                  game.accent.withValues(alpha: 0.14),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: diameter * 0.62,
                            height: diameter * 0.62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: game.accent.withValues(alpha: 0.22),
                            ),
                          ),
                          Semantics(
                            liveRegion: true,
                            label: _phase.label,
                            child: Text(
                              _phase.label,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'In for 4, out for 6. Let the circle lead.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
