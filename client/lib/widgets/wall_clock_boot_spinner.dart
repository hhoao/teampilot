import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Boot loading indicator that advances by wall-clock time, not fixed animation
/// steps. When the UI thread drops frames during bootstrap, each repaint still
/// shows the correct rotation angle — motion looks continuous instead of
/// "freeze then jump" like [CircularProgressIndicator].
class WallClockBootSpinner extends StatefulWidget {
  const WallClockBootSpinner({super.key, this.size = 36, this.strokeWidth = 3});

  final double size;
  final double strokeWidth;

  @override
  State<WallClockBootSpinner> createState() => _WallClockBootSpinnerState();
}

class _WallClockBootSpinnerState extends State<WallClockBootSpinner>
    with SingleTickerProviderStateMixin {
  static const _periodMs = 1100;

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rotation = (ms % _periodMs) / _periodMs * 2 * math.pi;
    final color = Theme.of(context).colorScheme.primary;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _WallClockBootSpinnerPainter(
            rotation: rotation,
            color: color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _WallClockBootSpinnerPainter extends CustomPainter {
  const _WallClockBootSpinnerPainter({
    required this.rotation,
    required this.color,
    required this.strokeWidth,
  });

  final double rotation;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, rotation - math.pi / 2, math.pi * 1.45, false, paint);
  }

  @override
  bool shouldRepaint(covariant _WallClockBootSpinnerPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
