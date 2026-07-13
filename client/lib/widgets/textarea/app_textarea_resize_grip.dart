// Adapted from flutter-shadcn-ui Textarea grip; App* naming.
import 'package:flutter/material.dart';

/// A small visual grip used to indicate that an [AppTextareaShell] is
/// resizable by the user.
///
/// This widget appears in the bottom-right corner and allows the user to drag
/// and resize the textarea vertically.
class AppDefaultResizeGrip extends StatelessWidget {
  const AppDefaultResizeGrip({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('app-textarea-resize-grip'),
      width: 8,
      height: 8,
      child: CustomPaint(
        painter: AppResizeGripPainter(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

/// A customizable painter for drawing diagonal resize grip lines, typically
/// used in the bottom-right corner of a resizable widget.
class AppResizeGripPainter extends CustomPainter {
  const AppResizeGripPainter({
    required this.color,
    this.strokeWidth = 0.8,
    this.lineCount = 3,
    this.spacing = 4.0,
  });

  final Color color;
  final double strokeWidth;
  final int lineCount;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;

    for (var i = 0; i < lineCount; i++) {
      final offset = spacing * i;
      canvas.drawLine(
        Offset(size.width - offset, size.height),
        Offset(size.width, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AppResizeGripPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.lineCount != lineCount ||
        oldDelegate.spacing != spacing;
  }
}
