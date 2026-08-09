// lib/cubits/workbench/workbench_tab_bar.dart
import 'package:equatable/equatable.dart';

import 'tab_strip.dart';
import 'workbench_tab.dart';

/// Per-workspace tab state: the center strip (session/file/diff) and the
/// floating strip (shell/run). Both are [TabStrip]s — one owner each.
class WorkspaceTabBar extends Equatable {
  const WorkspaceTabBar({
    this.center = const TabStrip(),
    this.floating = const TabStrip(),
  });

  final TabStrip center;
  final TabStrip floating;

  /// Back-compat (Task 6 deletes these): old readers iterated
  /// `state.byWorkspace.entries` and read `.tabOrder` off the value
  /// (e.g. `migrate_legacy_workbench_tabs.dart`).
  List<WorkbenchTabId> get tabOrder => center.order;

  /// Back-compat (Task 6 deletes these): old readers iterated
  /// `state.byWorkspace.entries` and read `.activeTabId` off the value
  /// (e.g. `file_editor_toolbar.dart`).
  WorkbenchTabId? get activeTabId => center.activeId;

  WorkspaceTabBar copyWith({TabStrip? center, TabStrip? floating}) =>
      WorkspaceTabBar(
        center: center ?? this.center,
        floating: floating ?? this.floating,
      );

  @override
  List<Object?> get props => [center, floating];
}
