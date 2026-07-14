// Adapted from flutter-shadcn-ui Textarea grip; App* naming.
import 'package:flutter/material.dart';

/// Hit-target size for the resize grip (visual paint stays smaller).
const double kAppTextareaResizeGripHitSize = 20;

/// Painted grip size (matches ShadDefaultResizeGrip).
const double kAppTextareaResizeGripVisualSize = 8;

/// A small visual grip used to indicate that an [AppTextareaShell] is
/// resizable. Drag handling lives on the shell's [GestureDetector].
class AppDefaultResizeGrip extends StatelessWidget {
  const AppDefaultResizeGrip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('app-textarea-resize-grip'),
      width: kAppTextareaResizeGripHitSize,
      height: kAppTextareaResizeGripHitSize,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 2, bottom: 2),
          child: SizedBox(
            width: kAppTextareaResizeGripVisualSize,
            height: kAppTextareaResizeGripVisualSize,
            child: CustomPaint(
              painter: AppResizeGripPainter(
                color: scheme.outline.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagonal resize grip lines for the bottom-trailing corner.
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
