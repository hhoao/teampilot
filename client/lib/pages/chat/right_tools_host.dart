import 'package:flutter/material.dart';

import '../../models/layout_preferences.dart';

/// Project-page-level host that lays out the center workbench and the right
/// tools panel as a full-height, three-column-style row (peer of the left
/// workspace sidebar). The panel is NOT owned by `WorkspaceShell` — keeping it a
/// sibling here means toggling it never restructures the center subtree.
///
/// Show/hide is instant (no transition animation). Layout is structurally
/// stable: [child] (the center shell, terminal included) is ALWAYS
/// `Row.children[0]` (an [Expanded]), whether or not the panel is present. A
/// Row's first child keeps its element/State when trailing children come and go,
/// so showing/hiding the tools never reparents — and therefore never remounts —
/// the terminal.
class RightToolsHost extends StatefulWidget {
  const RightToolsHost({
    super.key,
    required this.preferences,
    required this.child,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final Widget rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;

  @override
  State<RightToolsHost> createState() => _RightToolsHostState();
}

class _RightToolsHostState extends State<RightToolsHost> {
  /// Live panel width while the divider is being dragged; null when not
  /// dragging (width then comes from [LayoutPreferences.rightToolsWidth]).
  /// Persist only on drag end.
  double? _dragWidth;

  static const double _minCenterWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final minTools = LayoutPreferences.minRightToolsWidth;
        final maxPanel = (maxW - _minCenterWidth).clamp(0.0, maxW);
        final fullWidth = (_dragWidth ?? widget.preferences.rightToolsWidth)
            .clamp(
              0.0,
              maxPanel == 0 ? widget.preferences.rightToolsWidth : maxPanel,
            );
        final showPanel = widget.preferences.rightToolsVisible;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Terminal is always Row.children[0]'s Expanded child → stable
            // position, never remounts. ClipRect is REQUIRED: the terminal grid
            // can momentarily be wider than this pane (its reflow is debounced /
            // deferred a frame), and its CustomPaint does not self-clip, so
            // without this it paints over the gutter and the right panel.
            Expanded(child: ClipRect(child: widget.child)),
            if (showPanel) _buildGutter(context, maxW, minTools),
            // Keep the panel MOUNTED across show/hide (Offstage, not a
            // conditional subtree). The panel's TabbedPanel builds every tool
            // view (file tree, git, members, …) eagerly via an IndexedStack, so
            // unmounting it on hide means every show rebuilds that whole subtree
            // from scratch — the real cost behind "show is janky, hide is fast".
            // Offstage drops it from layout/paint when hidden (terminal gets the
            // full width) while preserving its element + state, so showing again
            // is just a visibility flip, not a rebuild.
            Offstage(
              offstage: !showPanel,
              child: ClipRect(
                child: SizedBox(width: fullWidth, child: widget.rightTools),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Draggable divider between the center pane and the right tools. Updates a
  /// live local width during the drag and persists once via
  /// [RightToolsHost.onRightToolsWidthChanged] on release.
  Widget _buildGutter(BuildContext context, double maxW, double minTools) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white12 : const Color(0xFFE5E7EB);
    final maxTools = (maxW - _minCenterWidth).clamp(minTools, maxW);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _dragWidth = widget.preferences.rightToolsWidth;
        },
        onHorizontalDragUpdate: (details) {
          // Dragging left (negative dx) widens the right panel.
          setState(() {
            _dragWidth =
                ((_dragWidth ?? widget.preferences.rightToolsWidth) -
                        details.delta.dx)
                    .clamp(minTools, maxTools);
          });
        },
        onHorizontalDragEnd: (_) {
          final width = _dragWidth;
          if (width != null) widget.onRightToolsWidthChanged?.call(width);
          setState(() => _dragWidth = null);
        },
        onHorizontalDragCancel: () => setState(() => _dragWidth = null),
        child: SizedBox(
          width: 7,
          child: Center(
            child: SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}
