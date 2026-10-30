import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

/// A gentle endless runner. Tap anywhere to hop.
///
/// The pace is set by the current estimate: a higher reading gives a calmer,
/// slower run with more spacing between obstacles. Hitting something costs a
/// little momentum and nothing else - the game never punishes a high reading.
class PulseRunnerScreen extends StatefulWidget {
  const PulseRunnerScreen({super.key});

  @override
  State<PulseRunnerScreen> createState() => _PulseRunnerScreenState();
}

class _PulseRunnerScreenState extends State<PulseRunnerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _runLength = Duration(seconds: 60);

  /// World units are fractions of the play area, so the game is resolution
  /// independent and cannot overflow on a small phone.
  static const double _groundY = 0.78;
  static const double _playerX = 0.18;
  static const double _playerRadius = 0.055;
  static const double _gravity = 3.4;
  static const double _jumpVelocity = -1.28;

  late final Ticker _ticker;
  late final DateTime _startedAt;
  late final _RunnerTuning _tuning;

  final math.Random _random = math.Random();
  final List<_Obstacle> _obstacles = [];
  final List<_Orb> _orbs = [];

  Duration _lastTick = Duration.zero;
  double _elapsed = 0;
  double _distance = 0;
  double _playerY = 0;
  double _velocity = 0;
  int _orbsCollected = 0;
  int _stumbles = 0;
  double _spawnCooldown = 0.8;
  double _speedFactor = 1;
  bool _paused = false;
  bool _finished = false;

  bool get _isGrounded => _playerY >= -0.0001;

  int get _score => _orbsCollected * 10 + (_distance * 4).round();

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _tuning = _RunnerTuning.forLevel(
      context.read<StressController>().currentLevel,
    );
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration now) {
    if (_paused || _finished) {
      _lastTick = now;
      return;
    }

    final dt = _lastTick == Duration.zero
        ? 0.016
        : ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;

    _elapsed += dt;
    if (_elapsed >= _runLength.inSeconds) {
      _finish();
      return;
    }

    // Momentum recovers smoothly after a stumble.
    _speedFactor = math.min(1, _speedFactor + dt * 0.5);
    final speed = _tuning.speed * _speedFactor;
    _distance += speed * dt;

    // Vertical motion.
    if (!_isGrounded || _velocity < 0) {
      _velocity += _gravity * dt;
      _playerY += _velocity * dt;
      if (_playerY >= 0) {
        _playerY = 0;
        _velocity = 0;
      }
    }

    _spawn(dt, speed);
    _move(dt, speed);
    _collide();

    setState(() {});
  }

  void _spawn(double dt, double speed) {
    _spawnCooldown -= dt;
    if (_spawnCooldown > 0) return;

    _spawnCooldown =
        _tuning.spawnInterval + _random.nextDouble() * _tuning.spawnJitter;

    // Roughly two thirds orbs, one third obstacles: collecting should be the
    // main activity, dodging the occasional punctuation.
    if (_random.nextDouble() < 0.62) {
      _orbs.add(
        _Orb(x: 1.15, y: _groundY - 0.10 - _random.nextDouble() * 0.22),
      );
    } else {
      _obstacles.add(
        _Obstacle(
          x: 1.15,
          width: 0.055 + _random.nextDouble() * 0.03,
          height: 0.07 + _random.nextDouble() * 0.05,
        ),
      );
    }
  }

  void _move(double dt, double speed) {
    for (final obstacle in _obstacles) {
      obstacle.x -= speed * dt;
    }
    for (final orb in _orbs) {
      orb.x -= speed * dt;
    }
    _obstacles.removeWhere((o) => o.x < -0.2);
    _orbs.removeWhere((o) => o.x < -0.2 || o.collected);
  }

  void _collide() {
    final playerCentreY = _groundY - _playerRadius + _playerY;
    final haptics = context.read<SettingsController>().hapticsEnabled;

    for (final orb in _orbs) {
      if (orb.collected) continue;
      final dx = orb.x - _playerX;
      final dy = orb.y - playerCentreY;
      if (math.sqrt(dx * dx + dy * dy) < _playerRadius + 0.035) {
        orb.collected = true;
        _orbsCollected++;
        if (haptics) HapticFeedback.selectionClick();
      }
    }

    for (final obstacle in _obstacles) {
      if (obstacle.hit) continue;
      final overlapsX =
          (obstacle.x - _playerX).abs() < _playerRadius + obstacle.width / 2;
      final overlapsY =
          playerCentreY + _playerRadius > _groundY - obstacle.height;
      if (overlapsX && overlapsY) {
        obstacle.hit = true;
        _stumbles++;
        // A stumble only costs momentum, briefly.
        _speedFactor = 0.55;
        if (haptics) HapticFeedback.lightImpact();
      }
    }
  }

  void _jump() {
    if (_paused || _finished || !_isGrounded) return;
    _velocity = _jumpVelocity;
    _playerY = -0.0001;
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker.stop();

    Navigator.of(context).pop(
      GameResult(
        gameId: GameIds.pulseRunner,
        duration: DateTime.now().difference(_startedAt),
        score: _score,
        completion: (_elapsed / _runLength.inSeconds).clamp(0.0, 1.0),
        metrics: {
          'orbs': _orbsCollected,
          'stumbles': _stumbles,
          'distance': double.parse(_distance.toStringAsFixed(1)),
        },
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = GameCatalog.pulseRunner;
    final remaining = math.max(0, _runLength.inSeconds - _elapsed).round();

    return GameScaffold(
      game: game,
      isPaused: _paused,
      onPause: () => setState(() => _paused = true),
      onResume: () => setState(() => _paused = false),
      onEnd: _finish,
      hud: [
        GameHudItem(label: 'Score', value: '$_score'),
        GameHudItem(
          label: 'Distance',
          value: '${_distance.toStringAsFixed(0)} m',
        ),
        GameHudItem(
          label: 'Time left',
          value: Formatters.duration(Duration(seconds: remaining)),
        ),
      ],
      footer: Text(
        _tuning.hint,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _jump(),
        child: Semantics(
          label: 'Pulse Runner play area. Tap to hop.',
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: CustomPaint(
                painter: _RunnerPainter(
                  obstacles: _obstacles,
                  orbs: _orbs,
                  playerY: _playerY,
                  distance: _distance,
                  accent: game.accent,
                  ground: theme.colorScheme.outlineVariant,
                  sky: theme.colorScheme.surfaceContainerHighest,
                  orbColor: theme.colorScheme.tertiary,
                  obstacleColor: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-level pacing. Higher estimates run slower with more breathing room.
class _RunnerTuning {
  const _RunnerTuning({
    required this.speed,
    required this.spawnInterval,
    required this.spawnJitter,
    required this.hint,
  });

  /// World units per second.
  final double speed;
  final double spawnInterval;
  final double spawnJitter;
  final String hint;

  factory _RunnerTuning.forLevel(StressLevel level) {
    return switch (level) {
      StressLevel.veryLow => const _RunnerTuning(
        speed: 0.62,
        spawnInterval: 0.72,
        spawnJitter: 0.35,
        hint: 'Full pace. Tap to hop over the blocks.',
      ),
      StressLevel.low => const _RunnerTuning(
        speed: 0.56,
        spawnInterval: 0.80,
        spawnJitter: 0.35,
        hint: 'A lively pace. Tap to hop.',
      ),
      StressLevel.moderate => const _RunnerTuning(
        speed: 0.48,
        spawnInterval: 0.95,
        spawnJitter: 0.40,
        hint: 'An easy pace. Tap to hop.',
      ),
      StressLevel.high => const _RunnerTuning(
        speed: 0.40,
        spawnInterval: 1.15,
        spawnJitter: 0.45,
        hint: 'Slowed down for you. No rush.',
      ),
      StressLevel.veryHigh => const _RunnerTuning(
        speed: 0.34,
        spawnInterval: 1.35,
        spawnJitter: 0.50,
        hint: 'Gentle mode. Collect what you like and ignore the rest.',
      ),
    };
  }
}

class _Obstacle {
  _Obstacle({required this.x, required this.width, required this.height});

  double x;
  final double width;
  final double height;
  bool hit = false;
}

class _Orb {
  _Orb({required this.x, required this.y});

  double x;
  final double y;
  bool collected = false;
}

class _RunnerPainter extends CustomPainter {
  _RunnerPainter({
    required this.obstacles,
    required this.orbs,
    required this.playerY,
    required this.distance,
    required this.accent,
    required this.ground,
    required this.sky,
    required this.orbColor,
    required this.obstacleColor,
  });

  final List<_Obstacle> obstacles;
  final List<_Orb> orbs;
  final double playerY;
  final double distance;
  final Color accent;
  final Color ground;
  final Color sky;
  final Color orbColor;
  final Color obstacleColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = sky);

    final groundY = size.height * _PulseRunnerScreenState._groundY;

    // Parallax hills, scrolled at a fraction of the run speed.
    final hillPaint = Paint()..color = accent.withValues(alpha: 0.10);
    for (var i = -1; i < 4; i++) {
      final offset = ((distance * 0.22 + i * 0.42) % 1.8 - 0.4) * size.width;
      canvas.drawCircle(
        Offset(offset, groundY + size.height * 0.05),
        size.width * 0.28,
        hillPaint,
      );
    }

    canvas.drawLine(
      Offset(0, groundY),
      Offset(size.width, groundY),
      Paint()
        ..color = ground
        ..strokeWidth = 2,
    );

    // Ground texture ticks, so motion is visible even with nothing on screen.
    final tickPaint = Paint()
      ..color = ground.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 14; i++) {
      final x = ((distance * 0.9 + i * 0.09) % 1.0) * size.width;
      canvas.drawLine(
        Offset(size.width - x, groundY + 6),
        Offset(size.width - x - 10, groundY + 6),
        tickPaint,
      );
    }

    for (final obstacle in obstacles) {
      final height = obstacle.height * size.height;
      final width = obstacle.width * size.width;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          obstacle.x * size.width - width / 2,
          groundY - height,
          width,
          height,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = obstacle.hit
              ? obstacleColor.withValues(alpha: 0.35)
              : obstacleColor,
      );
    }

    for (final orb in orbs) {
      if (orb.collected) continue;
      final centre = Offset(orb.x * size.width, orb.y * size.height);
      canvas.drawCircle(
        centre,
        size.width * 0.030,
        Paint()..color = orbColor.withValues(alpha: 0.25),
      );
      canvas.drawCircle(centre, size.width * 0.018, Paint()..color = orbColor);
    }

    final radius = size.width * _PulseRunnerScreenState._playerRadius;
    final playerCentre = Offset(
      size.width * _PulseRunnerScreenState._playerX,
      groundY - radius + playerY * size.height,
    );

    // Soft shadow that shrinks as the player rises, for depth.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(playerCentre.dx, groundY + 3),
        width: radius * (2.0 + playerY * 2),
        height: radius * 0.45,
      ),
      Paint()..color = ground.withValues(alpha: 0.35),
    );

    canvas.drawCircle(playerCentre, radius, Paint()..color = accent);
    canvas.drawCircle(
      playerCentre,
      radius * 0.45,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_RunnerPainter oldDelegate) => true;
}
