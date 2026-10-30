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

/// The kinds of thing that fall.
enum FallingKind {
  star('Star', true),
  leaf('Leaf', true),
  drop('Droplet', true),
  distraction('Distraction', false);

  const FallingKind(this.label, this.isWanted);

  final String label;

  /// Wanted items score; distractions are simply better left alone.
  final bool isWanted;
}

/// Catch the good things in your basket. Drag or tap to move.
///
/// Fall speed and the share of distractions both ease off as the current
/// estimate rises, so a higher reading gives a calmer game.
class CalmCatchScreen extends StatefulWidget {
  const CalmCatchScreen({super.key});

  @override
  State<CalmCatchScreen> createState() => _CalmCatchScreenState();
}

class _CalmCatchScreenState extends State<CalmCatchScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _roundLength = Duration(seconds: 60);

  /// Play area coordinates are 0..1 fractions in both axes.
  static const double _basketY = 0.88;
  static const double _basketHalfWidth = 0.11;
  static const double _catchRadius = 0.055;

  late final Ticker _ticker;
  late final DateTime _startedAt;
  late final _CatchTuning _tuning;

  final math.Random _random = math.Random();
  final List<_FallingItem> _items = [];

  Duration _lastTick = Duration.zero;
  double _elapsed = 0;
  double _basketX = 0.5;
  double _spawnCooldown = 0.6;
  int _caught = 0;
  int _missed = 0;
  int _distractionsCaught = 0;
  int _score = 0;
  bool _paused = false;
  bool _finished = false;

  /// Share of wanted items that reached the basket.
  double get _accuracy {
    final total = _caught + _missed;
    return total == 0 ? 1 : _caught / total;
  }

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _tuning = _CatchTuning.forLevel(
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
    if (_elapsed >= _roundLength.inSeconds) {
      _finish();
      return;
    }

    _spawn(dt);
    _update(dt);
    setState(() {});
  }

  void _spawn(double dt) {
    _spawnCooldown -= dt;
    if (_spawnCooldown > 0) return;

    _spawnCooldown =
        _tuning.spawnInterval + _random.nextDouble() * _tuning.spawnJitter;

    final isDistraction = _random.nextDouble() < _tuning.distractionChance;
    final kind = isDistraction
        ? FallingKind.distraction
        : [FallingKind.star, FallingKind.leaf, FallingKind.drop][_random
              .nextInt(3)];

    _items.add(
      _FallingItem(
        kind: kind,
        x: 0.10 + _random.nextDouble() * 0.80,
        y: -0.06,
        speed: _tuning.fallSpeed * (0.88 + _random.nextDouble() * 0.28),
        spin: (_random.nextDouble() - 0.5) * 2.4,
      ),
    );
  }

  void _update(double dt) {
    final haptics = context.read<SettingsController>().hapticsEnabled;

    for (final item in _items) {
      if (item.resolved) continue;
      item.y += item.speed * dt;
      item.rotation += item.spin * dt;

      final withinBasket =
          (item.x - _basketX).abs() < _basketHalfWidth &&
          (item.y - _basketY).abs() < _catchRadius;

      if (withinBasket) {
        item.resolved = true;
        if (item.kind.isWanted) {
          _caught++;
          _score += 10;
          if (haptics) HapticFeedback.selectionClick();
        } else {
          _distractionsCaught++;
          // Catching a distraction costs a little score but never goes
          // negative, and never ends the round.
          _score = math.max(0, _score - 5);
        }
        continue;
      }

      if (item.y > 1.05) {
        item.resolved = true;
        if (item.kind.isWanted) _missed++;
      }
    }

    _items.removeWhere((item) => item.resolved);
  }

  void _moveBasket(double x, double width) {
    if (_paused || _finished) return;
    setState(() {
      _basketX = (x / width).clamp(_basketHalfWidth, 1 - _basketHalfWidth);
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker.stop();

    Navigator.of(context).pop(
      GameResult(
        gameId: GameIds.calmCatch,
        duration: DateTime.now().difference(_startedAt),
        score: _score,
        completion: (_elapsed / _roundLength.inSeconds).clamp(0.0, 1.0),
        metrics: {
          'caught': _caught,
          'missed': _missed,
          'distractions': _distractionsCaught,
          'accuracy': double.parse(_accuracy.toStringAsFixed(2)),
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
    final game = GameCatalog.calmCatch;
    final remaining = math.max(0, _roundLength.inSeconds - _elapsed).round();

    return GameScaffold(
      game: game,
      isPaused: _paused,
      onPause: () => setState(() => _paused = true),
      onResume: () => setState(() => _paused = false),
      onEnd: _finish,
      hud: [
        GameHudItem(label: 'Score', value: '$_score'),
        GameHudItem(label: 'Caught', value: '$_caught'),
        GameHudItem(label: 'Accuracy', value: '${(_accuracy * 100).round()}%'),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  _moveBasket(details.localPosition.dx, width),
              onTapDown: (details) =>
                  _moveBasket(details.localPosition.dx, width),
              child: Semantics(
                label: 'Calm Catch play area. Drag to move the basket.',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: CustomPaint(
                    painter: _CatchPainter(
                      items: _items,
                      basketX: _basketX,
                      accent: game.accent,
                      background: theme.colorScheme.surfaceContainerHighest,
                      basketColor: theme.colorScheme.primary,
                      distractionColor: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.55),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Fall speed and clutter, tuned by the current estimate.
class _CatchTuning {
  const _CatchTuning({
    required this.fallSpeed,
    required this.spawnInterval,
    required this.spawnJitter,
    required this.distractionChance,
    required this.hint,
  });

  /// Fractions of the play area per second.
  final double fallSpeed;
  final double spawnInterval;
  final double spawnJitter;
  final double distractionChance;
  final String hint;

  factory _CatchTuning.forLevel(StressLevel level) {
    return switch (level) {
      StressLevel.veryLow => const _CatchTuning(
        fallSpeed: 0.46,
        spawnInterval: 0.52,
        spawnJitter: 0.30,
        distractionChance: 0.26,
        hint: 'Full speed. Skip the grey shapes.',
      ),
      StressLevel.low => const _CatchTuning(
        fallSpeed: 0.41,
        spawnInterval: 0.58,
        spawnJitter: 0.32,
        distractionChance: 0.22,
        hint: 'Catch the stars, leaves and droplets.',
      ),
      StressLevel.moderate => const _CatchTuning(
        fallSpeed: 0.34,
        spawnInterval: 0.68,
        spawnJitter: 0.35,
        distractionChance: 0.18,
        hint: 'An unhurried pace. Catch what you can.',
      ),
      StressLevel.high => const _CatchTuning(
        fallSpeed: 0.27,
        spawnInterval: 0.82,
        spawnJitter: 0.40,
        distractionChance: 0.10,
        hint: 'Slowed right down. Nothing to chase.',
      ),
      StressLevel.veryHigh => const _CatchTuning(
        fallSpeed: 0.22,
        spawnInterval: 0.95,
        spawnJitter: 0.45,
        distractionChance: 0.05,
        hint: 'Gentle mode. Drift along with it.',
      ),
    };
  }
}

class _FallingItem {
  _FallingItem({
    required this.kind,
    required this.x,
    required this.y,
    required this.speed,
    required this.spin,
  });

  final FallingKind kind;
  final double x;
  double y;
  final double speed;
  final double spin;
  double rotation = 0;
  bool resolved = false;
}

class _CatchPainter extends CustomPainter {
  _CatchPainter({
    required this.items,
    required this.basketX,
    required this.accent,
    required this.background,
    required this.basketColor,
    required this.distractionColor,
  });

  final List<_FallingItem> items;
  final double basketX;
  final Color accent;
  final Color background;
  final Color basketColor;
  final Color distractionColor;

  static const Color _starColor = Color(0xFFE8B84B);
  static const Color _leafColor = Color(0xFF7FA65C);
  static const Color _dropColor = Color(0xFF5FA3CC);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    for (final item in items) {
      if (item.resolved) continue;
      final centre = Offset(item.x * size.width, item.y * size.height);
      final radius = size.width * 0.036;

      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(item.rotation);

      switch (item.kind) {
        case FallingKind.star:
          _drawStar(canvas, radius, _starColor);
        case FallingKind.leaf:
          _drawLeaf(canvas, radius, _leafColor);
        case FallingKind.drop:
          _drawDrop(canvas, radius, _dropColor);
        case FallingKind.distraction:
          _drawDistraction(canvas, radius, distractionColor);
      }

      canvas.restore();
    }

    _drawBasket(canvas, size);
  }

  void _drawStar(Canvas canvas, double radius, Color color) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : radius * 0.45;
      final angle = i * math.pi / points - math.pi / 2;
      final point = Offset(math.cos(angle), math.sin(angle)) * r;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawLeaf(Canvas canvas, double radius, Color color) {
    final path = Path()
      ..moveTo(0, -radius)
      ..quadraticBezierTo(radius, -radius * 0.2, 0, radius)
      ..quadraticBezierTo(-radius, -radius * 0.2, 0, -radius)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(0, -radius * 0.8),
      Offset(0, radius * 0.8),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1.4,
    );
  }

  void _drawDrop(Canvas canvas, double radius, Color color) {
    final path = Path()
      ..moveTo(0, -radius)
      ..quadraticBezierTo(radius * 0.95, radius * 0.25, 0, radius * 0.9)
      ..quadraticBezierTo(-radius * 0.95, radius * 0.25, 0, -radius)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// Distractions are a hollow square: a different shape as well as a duller
  /// colour, so they can be told apart without relying on colour.
  void _drawDistraction(Canvas canvas, double radius, Color color) {
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 1.5,
        height: radius * 1.5,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  void _drawBasket(Canvas canvas, Size size) {
    final centreX = basketX * size.width;
    final centreY = _CalmCatchScreenState._basketY * size.height;
    final halfWidth = _CalmCatchScreenState._basketHalfWidth * size.width;
    final height = size.height * 0.055;

    final path = Path()
      ..moveTo(centreX - halfWidth, centreY - height / 2)
      ..lineTo(centreX + halfWidth, centreY - height / 2)
      ..lineTo(centreX + halfWidth * 0.7, centreY + height / 2)
      ..lineTo(centreX - halfWidth * 0.7, centreY + height / 2)
      ..close();

    canvas.drawPath(path, Paint()..color = basketColor);
    canvas.drawLine(
      Offset(centreX - halfWidth, centreY - height / 2),
      Offset(centreX + halfWidth, centreY - height / 2),
      Paint()
        ..color = accent
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CatchPainter oldDelegate) => true;
}
