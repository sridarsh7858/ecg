import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// One point on a trend chart.
class TrendPoint {
  const TrendPoint({required this.time, required this.value});

  final DateTime time;
  final double value;
}

/// A compact line chart drawn with [CustomPaint].
///
/// Hand-drawn rather than pulled from a charting package: the app only needs
/// one chart shape, and this keeps the dependency list to two packages.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.color,
    this.minY,
    this.maxY,
    this.height = 160,
    this.yLabelBuilder,
    this.gridLines = 4,
    this.showArea = true,
  });

  final List<TrendPoint> points;
  final Color color;

  /// Fixed axis bounds. When omitted the range is derived from the data with
  /// a little padding.
  final double? minY;
  final double? maxY;

  final double height;

  /// Formats the value labels on the left axis.
  final String Function(double value)? yLabelBuilder;

  final int gridLines;
  final bool showArea;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'No data for this period'
                : 'One reading so far - check in again to see a trend',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final values = points.map((p) => p.value).toList();
    var lower = minY ?? values.reduce(math.min);
    var upper = maxY ?? values.reduce(math.max);
    if (upper - lower < 0.001) {
      lower -= 1;
      upper += 1;
    } else if (minY == null && maxY == null) {
      final padding = (upper - lower) * 0.15;
      lower -= padding;
      upper += padding;
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TrendPainter(
          points: points,
          color: color,
          minY: lower,
          maxY: upper,
          gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          labelStyle: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          yLabelBuilder: yLabelBuilder ?? (v) => v.toStringAsFixed(0),
          gridLines: gridLines,
          showArea: showArea,
          textDirection: Directionality.of(context),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.color,
    required this.minY,
    required this.maxY,
    required this.gridColor,
    required this.labelStyle,
    required this.yLabelBuilder,
    required this.gridLines,
    required this.showArea,
    required this.textDirection,
  });

  final List<TrendPoint> points;
  final Color color;
  final double minY;
  final double maxY;
  final Color gridColor;
  final TextStyle labelStyle;
  final String Function(double) yLabelBuilder;
  final int gridLines;
  final bool showArea;
  final TextDirection textDirection;

  /// Room reserved on the left for value labels.
  static const double _labelGutter = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(
      _labelGutter,
      6,
      size.width - _labelGutter - 4,
      size.height - 12,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= gridLines; i++) {
      final t = i / gridLines;
      final y = plot.bottom - plot.height * t;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);

      final label = yLabelBuilder(minY + (maxY - minY) * t);
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: textDirection,
      )..layout();
      painter.paint(
        canvas,
        Offset(plot.left - painter.width - 6, y - painter.height / 2),
      );
    }

    Offset toOffset(int index) {
      final x =
          plot.left +
          (points.length == 1
              ? plot.width / 2
              : plot.width * index / (points.length - 1));
      final normalised = ((points[index].value - minY) / (maxY - minY)).clamp(
        0.0,
        1.0,
      );
      return Offset(x, plot.bottom - plot.height * normalised);
    }

    final offsets = [for (var i = 0; i < points.length; i++) toOffset(i)];

    // A smoothed path reads better than raw segments without hiding the data.
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 0; i < offsets.length - 1; i++) {
      final current = offsets[i];
      final next = offsets[i + 1];
      final controlX = (current.dx + next.dx) / 2;
      path.cubicTo(controlX, current.dy, controlX, next.dy, next.dx, next.dy);
    }

    if (showArea) {
      final areaPath = Path.from(path)
        ..lineTo(offsets.last.dx, plot.bottom)
        ..lineTo(offsets.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(plot),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // Only mark the most recent point, so dense histories stay readable.
    canvas.drawCircle(offsets.last, 5, Paint()..color = color);
    canvas.drawCircle(
      offsets.last,
      2.2,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.minY != minY ||
      oldDelegate.maxY != maxY;
}

/// Chart wrapped in a titled card, as used on the History screen.
class TrendChartCard extends StatelessWidget {
  const TrendChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.color,
    this.minY,
    this.maxY,
    this.yLabelBuilder,
  });

  final String title;
  final String subtitle;
  final List<TrendPoint> points;
  final Color color;
  final double? minY;
  final double? maxY;
  final String Function(double value)? yLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TrendChart(
              points: points,
              color: color,
              minY: minY,
              maxY: maxY,
              yLabelBuilder: yLabelBuilder,
            ),
          ],
        ),
      ),
    );
  }
}
