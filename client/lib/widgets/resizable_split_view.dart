import 'package:flutter/material.dart';

class ResizableSplitView extends StatefulWidget {
  const ResizableSplitView({
    super.key,
    required this.left,
    required this.right,
    this.initialLeftWidth = 180,
    this.initialLeftFraction,
    this.minLeftWidth = 120,
    this.maxLeftWidth = 500,
    this.dividerWidth = 2,
    this.onWidthChanged,
  });

  final Widget left;
  final Widget right;
  final double initialLeftWidth;

  /// When set (0–1), the first layout uses this fraction of total width for the
  /// left pane instead of [initialLeftWidth]. Result is still clamped by
  /// [minLeftWidth] / [maxLeftWidth].
  final double? initialLeftFraction;
  final double minLeftWidth;
  final double maxLeftWidth;
  final double dividerWidth;
  final ValueChanged<double>? onWidthChanged;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  double? _fraction;
  bool _initialized = false;

  double _leftWidth(double availableWidth) {
    if (!_initialized) {
      if (widget.initialLeftFraction != null) {
        _fraction = widget.initialLeftFraction!.clamp(0.0, 1.0);
      } else {
        _fraction = (widget.initialLeftWidth / availableWidth).clamp(0.0, 1.0);
      }
      _initialized = true;
    }
    return (availableWidth * _fraction!).clamp(
      widget.minLeftWidth,
      widget.maxLeftWidth.clamp(0.0, availableWidth - widget.dividerWidth),
    );
  }

  double _fractionFromWidth(double availableWidth, double width) {
    return (width / availableWidth).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE5E7EB);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final currentLeftWidth = _leftWidth(availableWidth);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: currentLeftWidth, child: widget.left),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                final maxWidth = widget.maxLeftWidth.clamp(
                  0.0,
                  availableWidth - widget.dividerWidth,
                );
                final newWidth = (currentLeftWidth + details.delta.dx).clamp(
                  widget.minLeftWidth,
                  maxWidth,
                );
                setState(() {
                  _fraction = _fractionFromWidth(availableWidth, newWidth);
                });
              },
              onHorizontalDragEnd: (_) {
                widget.onWidthChanged?.call(_leftWidth(availableWidth));
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: widget.dividerWidth,
                  color: dividerColor,
                ),
              ),
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }
}
