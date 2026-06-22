import 'package:flutter/material.dart';

import '../../models/layout_preferences.dart';
import '../../widgets/resizable_split_view.dart';

/// Project-page-level host that lays out the center workbench and the right
/// tools panel. Delegates resize to [ResizableSplitView] — the same widget
/// used by the workspace sidebar, file-tree split, and workspace shell.
///
/// Show/hide is instant. The panel stays mounted via [Offstage] so toggling
/// never rebuilds its subtree (IndexedStack of file tree, git, members).
///
/// The center child (terminal) is ALWAYS in the flex position — structurally
/// stable, never reparents across show/hide.
class RightToolsHost extends StatelessWidget {
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

  static const double _minCenterWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    final showPanel = preferences.rightToolsVisible;
    final storedWidth = preferences.rightToolsWidth.clamp(
      LayoutPreferences.minRightToolsWidth,
      double.infinity,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxPanel = (maxW - _minCenterWidth)
            .clamp(LayoutPreferences.minRightToolsWidth, maxW);

        return ResizableSplitView(
          axis: Axis.horizontal,
          primaryAtEnd: true,
          first: ClipRect(child: child),
          // Offstage keeps the panel mounted when hidden, preserving element
          // state (IndexedStack) so show is just a visibility flip.
          second: Offstage(
            offstage: !showPanel,
            child: ClipRect(
              child: SizedBox(width: storedWidth, child: rightTools),
            ),
          ),
          initialPrimarySize: showPanel ? storedWidth : 0,
          minPrimarySize: showPanel ? LayoutPreferences.minRightToolsWidth : 0,
          minSecondarySize: _minCenterWidth,
          maxPrimarySize: showPanel ? maxPanel : 0,
          dividerThickness: showPanel ? 1 : 0,
          dividerHitBuffer: showPanel ? 5 : 0,
          onPrimarySizeChanged: onRightToolsWidthChanged,
        );
      },
    );
  }
}
