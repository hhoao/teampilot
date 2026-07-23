import 'package:flutter/material.dart';

/// Compact oldest-first memory history sparkline (Orca-style polyline).
class ResourceMemorySparkline extends StatelessWidget {
  const ResourceMemorySparkline({
    required this.samples,
    this.width = 48,
    this.height = 14,
    super.key,
  });

  final List<int> samples;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant.withValues(
          alpha: 0.7,
        );
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(samples: samples, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.samples, required this.color});

  final List<int> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (samples.length < 2) {
      final midY = size.height / 2;
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);
      return;
    }

    var min = samples.first;
    var max = samples.first;
    for (final v in samples) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = (max - min).abs() < 1 ? 1 : (max - min);
    final stepX = size.width / (samples.length - 1);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i * stepX;
      final y = size.height - ((samples[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (identical(oldDelegate.samples, samples)) return false;
    if (oldDelegate.samples.length != samples.length) return true;
    for (var i = 0; i < samples.length; i++) {
      if (oldDelegate.samples[i] != samples[i]) return true;
    }
    return false;
  }
}
