import 'package:flutter/material.dart';

class DottedBorderContainer extends StatelessWidget {
  const DottedBorderContainer({
    required this.child,
    required this.color,
    required this.radius,
    super.key,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    const dashLength = 6.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length);
        dashed.addPath(
          metric.extractPath(distance, next.toDouble()),
          Offset.zero,
        );
        distance = next + gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
