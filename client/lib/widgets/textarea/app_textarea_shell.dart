// Adapted from flutter-shadcn-ui Textarea; App* naming.
import 'package:flutter/material.dart';

import 'app_textarea_resize_grip.dart';

/// Owns min/max height, drag-resize, and derived line count for multiline
/// controls. Does not apply outline decoration — compose stays borderless.
///
/// [minHeight] / [maxHeight] are outer shell heights. When the child is an
/// outlined [AppTextarea], pass [verticalChrome] (padding + border) so
/// [lineCount] is derived from content height = `_height - verticalChrome`.
/// Borderless compose leaves [verticalChrome] at 0.
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
    this.verticalChrome = 0,
    this.focusNode,
  });

  final Widget Function(BuildContext context, int lineCount) builder;
  final double minHeight;
  final double maxHeight;
  final double? initialHeight;
  final bool resizable;
  final ValueChanged<double>? onHeightChanged;
  final WidgetBuilder? resizeHandleBuilder;
  final TextStyle? textStyle;

  /// Vertical inset subtracted before deriving [lineCount] (padding + borders).
  final double verticalChrome;

  /// When set, drag-resize requests focus (matches ShadTextarea).
  final FocusNode? focusNode;

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
    widget.focusNode?.requestFocus();
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
    final contentHeight = (_height - widget.verticalChrome).clamp(
      lineHeight,
      double.infinity,
    );
    return (contentHeight / lineHeight).floor().clamp(1, 100);
  }

  TextStyle _effectiveTextStyle(BuildContext context) {
    return widget.textStyle ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle();
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
            bottom: 0,
            right: 0,
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
