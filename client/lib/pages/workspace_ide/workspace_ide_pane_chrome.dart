import 'package:flutter/material.dart';

import 'package:panes/panes.dart';

/// Medium "Islands" chrome for a single [WorkspaceIdeShell] region.
///
/// Applies a shared gutter and rounded clip so panes read as floating panels
/// without replacing TeamPilot product chrome (tab strips, tool rails, etc.).
class WorkspaceIdePaneChrome extends StatelessWidget {
  const WorkspaceIdePaneChrome({required this.child, super.key});

  /// Half-gutter on each pane edge → ~[gutter] between adjacent panes.
  static const double paneInset = 4;

  /// Outer padding around the whole IDE shell content.
  static const double shellGutter = 8;

  static const double paneRadius = 10;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(paneInset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(paneRadius),
          child: ColoredBox(
            color: cs.surface,
            child: child,
          ),
        ),
      ),
    );
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
