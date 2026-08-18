import 'package:flutter/material.dart';

/// One segment in the workspace workbench status bar.
abstract class WorkspaceStatusBarItem {
  String get id;

  Widget buildSegment(BuildContext context, {required bool compact});
}

/// Extensible bottom strip for the workspace window (right-cluster layout).
///
/// Sits on the page chrome under the floating card — transparent, no fill or
/// top rule, so pills read as chrome controls rather than a second bar.
/// Small vertical inset keeps a breath of chrome above and below the strip.
///
/// Compact mode kicks in when the bar width is under 720 logical pixels so
/// items can drop labels (Resource Manager pill, etc.).
class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({
    this.items = const [],
    this.leadingItems = const [],
    this.trailingItems,
    super.key,
  });

  /// Content row height (excluding [verticalInset]).
  static const double height = 24;

  /// Chrome breath above and below the content row.
  static const double verticalInset = 4;

  /// Full chrome height consumed under the workbench body.
  static const double totalHeight = height + verticalInset * 2;

  static const double compactBreakpoint = 720;

  /// Legacy trailing group. Existing callers can continue to pass [items].
  final List<WorkspaceStatusBarItem> items;

  /// Items pinned to the lower-left edge of the shell.
  final List<WorkspaceStatusBarItem> leadingItems;

  /// Explicit trailing group. When omitted, [items] is used.
  final List<WorkspaceStatusBarItem>? trailingItems;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: verticalInset,
        ),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < compactBreakpoint;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < leadingItems.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    leadingItems[i].buildSegment(context, compact: compact),
                  ],
                  if (leadingItems.isNotEmpty) const Spacer(),
                  for (var i = 0; i < (trailingItems ?? items).length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    (trailingItems ?? items)[i].buildSegment(
                      context,
                      compact: compact,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
