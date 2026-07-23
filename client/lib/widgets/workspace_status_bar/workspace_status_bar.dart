import 'package:flutter/material.dart';

import '../../theme/workspace_surface_layers.dart';

/// One segment in the workspace workbench status bar.
abstract class WorkspaceStatusBarItem {
  String get id;

  Widget buildSegment(BuildContext context, {required bool compact});
}

/// Extensible bottom strip for [WorkspacePage] (right-cluster layout).
///
/// Compact mode kicks in when the bar width is under 720 logical pixels so
/// items can drop labels (Task 8 Resource Manager pill, etc.).
class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({required this.items, super.key});

  static const double height = 30;
  static const double compactBreakpoint = 720;

  final List<WorkspaceStatusBarItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.workspaceSubtleSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < compactBreakpoint;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      items[i].buildSegment(context, compact: compact),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
