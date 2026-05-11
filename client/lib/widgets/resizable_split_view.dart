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
  });

  final Widget left;
  final Widget right;
  final double initialLeftWidth;
  final double minLeftWidth;
  final double maxLeftWidth;
  final double dividerWidth;

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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? Colors.white12
        : const Color(0xFFE5E7EB);

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
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: Container(
              width: widget.dividerWidth,
              color: colors,
            ),
          ),
        ),
        Expanded(child: widget.right),
      ],
    );
  }
}
