import 'package:flutter/material.dart';

class ResizableSplitView extends StatefulWidget {
  const ResizableSplitView({
    super.key,
    required this.left,
    required this.right,
    this.initialLeftWidth = 180,
    this.minLeftWidth = 120,
    this.maxLeftWidth = 500,
    this.dividerWidth = 6,
    this.onWidthChanged,
  });

  final Widget left;
  final Widget right;
  final double initialLeftWidth;
  final double minLeftWidth;
  final double maxLeftWidth;
  final double dividerWidth;
  final ValueChanged<double>? onWidthChanged;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  late double _leftWidth;

  @override
  void initState() {
    super.initState();
    _leftWidth = widget.initialLeftWidth;
  }

  @override
  void didUpdateWidget(covariant ResizableSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLeftWidth != oldWidget.initialLeftWidth) {
      _leftWidth = widget.initialLeftWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE5E7EB);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _leftWidth, child: widget.left),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              _leftWidth = (_leftWidth + details.delta.dx).clamp(
                widget.minLeftWidth,
                widget.maxLeftWidth,
              );
            });
          },
          onHorizontalDragEnd: (_) {
            widget.onWidthChanged?.call(_leftWidth);
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
  }
}
