// Adapted from flutter-shadcn-ui Textarea; App* naming.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_textarea_resize_grip.dart';

/// Owns min/max height, drag-resize, and derived line count for multiline
/// controls. Does not apply outline decoration — compose stays borderless.
class AppTextareaShell extends StatefulWidget {
  const AppTextareaShell({
    super.key,
    required this.builder,
    this.minHeight = 80,
    this.maxHeight = 500,
    this.initialHeight,
    this.resizable = true,
    this.onHeightChanged,
    this.resizeHandleBuilder,
    this.textStyle,
  });

  final Widget Function(BuildContext context, int lineCount) builder;
  final double minHeight;
  final double maxHeight;
  final double? initialHeight;
  final bool resizable;
  final ValueChanged<double>? onHeightChanged;
  final WidgetBuilder? resizeHandleBuilder;
  final TextStyle? textStyle;

  @override
  State<AppTextareaShell> createState() => _AppTextareaShellState();
}

class _AppTextareaShellState extends State<AppTextareaShell> {
  late double _height;

  @override
  void initState() {
    super.initState();
    _height = _clampHeight(widget.initialHeight ?? widget.minHeight);
  }

  @override
  void didUpdateWidget(covariant AppTextareaShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clamped = _clampHeight(_height);
    if (clamped != _height) {
      setState(() => _height = clamped);
      widget.onHeightChanged?.call(clamped);
    }
  }

  double _clampHeight(double value) =>
      value.clamp(widget.minHeight, widget.maxHeight);

  void _handleResize(DragUpdateDetails details) {
    final newHeight = _clampHeight(_height + details.delta.dy);
    if (newHeight != _height) {
      setState(() => _height = newHeight);
      widget.onHeightChanged?.call(newHeight);
    }
  }

  int _calculateLineCount(TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    final heightFactor = style.height ?? 20 / 14;
    final lineHeight = fontSize * heightFactor;
    return (_height / lineHeight).floor().clamp(1, 100);
  }

  TextStyle _effectiveTextStyle(BuildContext context) {
    return widget.textStyle ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = _calculateLineCount(_effectiveTextStyle(context));

    return Stack(
      children: [
        SizedBox(
          height: _height,
          width: double.infinity,
          child: widget.builder(context, lineCount),
        ),
        if (widget.resizable)
          Positioned(
            bottom: 2,
            right: 2,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                onPanUpdate: _handleResize,
                behavior: HitTestBehavior.translucent,
                child: widget.resizeHandleBuilder != null
                    ? Builder(builder: widget.resizeHandleBuilder!)
                    : const AppDefaultResizeGrip(),
              ),
            ),
          ),
      ],
    );
  }
}
