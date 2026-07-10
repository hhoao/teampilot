import 'package:flutter/material.dart';

import 'package:panes/panes.dart';

/// Minimal "Islands" chrome wrapper for a single [WorkspaceIdeShell] region.
///
/// Task 5 keeps this deliberately thin: it isolates each region behind a
/// [RepaintBoundary] (so toggling a sibling pane does not repaint the whole
/// tree) and lets Task 7 layer in gutters / rounded surfaces without touching
/// the shell wiring.
class WorkspaceIdePaneChrome extends StatelessWidget {
  const WorkspaceIdePaneChrome({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: child);
  }
}

/// Builds a [PaneThemeData] from the app [ColorScheme] so the panes resizers
/// match the surrounding TeamPilot chrome instead of the package defaults.
PaneThemeData workspaceIdePaneTheme(ColorScheme cs) {
  return PaneThemeData(
    resizerColor: cs.outlineVariant.withValues(alpha: 0.5),
    resizerHoverColor: cs.primary.withValues(alpha: 0.6),
    resizerFocusedColor: cs.primary,
    resizerThickness: 1.0,
    resizerHitTestThickness: 8.0,
  );
}
