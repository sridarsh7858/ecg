import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/stress/stress_level.dart';
import '../theme/app_spacing.dart';
import '../theme/motion.dart';

/// The signature stress readout: an arc gauge with the level number, the
/// written label and an icon.
///
/// Meaning is carried by the number, the label and the icon as well as the
/// colour, so the reading is never colour-dependent.
class StressGauge extends StatelessWidget {
  const StressGauge({
    super.key,
    required this.level,
    this.confidence,
    this.size = 220,
    this.reduceMotion = false,
    this.caption,
  });

  final StressLevel level;

  /// 0..1, shown under the label when provided.
  final double? confidence;

  final double size;
  final bool reduceMotion;

  /// Replaces the confidence line, e.g. "Estimated stress level".
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = StressLevelConfig.of(level);
    final accent = info.colorOf(context);

    return Semantics(
      label: 'Estimated stress level ${info.number} of 5, ${info.title}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: info.number / 5),
        duration: AppMotion.scale(AppMotion.reveal, reduceMotion: reduceMotion),
        curve: AppMotion.emphasised,
        builder: (context, value, _) {
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _GaugePainter(
                progress: value,
                accent: accent,
                track: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                segments: StressLevel.values.length,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(info.icon, size: size * 0.13, color: accent),
                    SizedBox(height: size * 0.03),
                    Text(
                      'LEVEL',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${info.number}',
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: size * 0.34,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    Text(
                      info.upperTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (caption != null || confidence != null) ...[
                      SizedBox(height: size * 0.02),
                      Text(
                        caption ??
                            'Confidence ${((confidence ?? 0) * 100).round()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.accent,
    required this.track,
    required this.segments,
  });

  /// 0..1 of the arc that should be filled.
  final double progress;
  final Color accent;
  final Color track;
  final int segments;

  /// The gauge is a 270-degree arc opening at the bottom.
  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);

    // Tick marks between the five bands give a non-colour cue to position.
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = track;
    final centre = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2 - stroke * 0.15;
    final inner = outer - stroke * 0.7;
    for (var i = 1; i < segments; i++) {
      final angle = _startAngle + _sweepAngle * (i / segments);
      canvas.drawLine(
        centre + Offset(math.cos(angle), math.sin(angle)) * inner,
        centre + Offset(math.cos(angle), math.sin(angle)) * outer,
        tickPaint,
      );
    }

    if (progress <= 0) return;

    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _startAngle,
        endAngle: _startAngle + _sweepAngle,
        colors: [accent.withValues(alpha: 0.55), accent],
        transform: GradientRotation(_startAngle),
      ).createShader(rect);

    canvas.drawArc(rect, _startAngle, _sweepAngle * progress, false, fillPaint);
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track;
}

/// A compact horizontal 1-5 scale, used where the full gauge is too large.
class StressLevelBar extends StatelessWidget {
  const StressLevelBar({
    super.key,
    required this.level,
    this.showLabels = true,
  });

  final StressLevel level;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = StressLevelConfig.of(level);
    final accent = info.colorOf(context);

    return Semantics(
      label: 'Level ${info.number} of 5, ${info.title}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final candidate in StressLevel.values) ...[
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: candidate.number <= info.number
                          ? accent.withValues(
                              alpha: 0.35 + 0.65 * candidate.number / 5,
                            )
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                if (candidate != StressLevel.values.last)
                  const SizedBox(width: 4),
              ],
            ],
          ),
          if (showLabels) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Very low',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Very high',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
