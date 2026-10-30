import 'package:flutter/material.dart';

/// Scrolling ECG-style trace drawn from the samples the data source emits.
///
/// It visualises the incoming signal; it is not a diagnostic waveform.
class LiveTrace extends StatelessWidget {
  const LiveTrace({
    super.key,
    required this.samples,
    required this.color,
    this.height = 90,
    this.windowSize = 90,
  });

  final List<double> samples;
  final Color color;
  final double height;

  /// How many samples fit across the full width.
  final int windowSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TracePainter(
          samples: samples,
          color: color,
          baselineColor: theme.colorScheme.outlineVariant.withValues(
            alpha: 0.55,
          ),
          windowSize: windowSize,
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.samples,
    required this.color,
    required this.baselineColor,
    required this.windowSize,
  });

  final List<double> samples;
  final Color color;
  final Color baselineColor;
  final int windowSize;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = baselineColor
        ..strokeWidth = 1,
    );

    if (samples.length < 2) return;

    final step = size.width / (windowSize - 1);
    final amplitude = size.height * 0.42;

    final path = Path();
    // Right-align the samples so new data appears at the leading edge.
    final offset = windowSize - samples.length;
    for (var i = 0; i < samples.length; i++) {
      final x = (offset + i) * step;
      final y = midY - samples[i] * amplitude;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TracePainter oldDelegate) =>
      oldDelegate.samples.length != samples.length ||
      oldDelegate.color != color;
}
