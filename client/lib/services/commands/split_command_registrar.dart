import 'package:flutter/widgets.dart' show Axis;

import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires the workbench split-group keyboard commands onto [bus].
///
/// All commands act on the **center** layout of the active workspace
/// (`chat.tabStore.activeWorkspaceId` — empty means no active workspace and
/// every handler is a silent no-op). The floating panel's split layout is
/// driven by its own tab-strip menus and tab drags, not these chords.
///
/// Call once during app bootstrap (see `buildAppShell`); handlers stay
/// registered for the app's lifetime.
void registerSplitCommands(
  CommandBus bus,
  ChatCubit chat,
  WorkbenchCubit workbench,
) {
  String? activeWorkspaceId() {
    final id = chat.tabStore.activeWorkspaceId.trim();
    return id.isEmpty ? null : id;
  }

  void splitFocusedActiveTab(Axis axis) {
    final ws = activeWorkspaceId();
    if (ws == null) return;
    final tab = workbench.centerActiveId(ws);
    if (tab == null) return;
    workbench.splitTab(ws, tab, axis: axis, before: false);
  }

  bus.register(
    CommandIds.workbenchSplitRight,
    () => splitFocusedActiveTab(Axis.horizontal),
  );
  bus.register(
    CommandIds.workbenchSplitDown,
    () => splitFocusedActiveTab(Axis.vertical),
  );
  bus.register(CommandIds.workbenchSplitReset, () {
    final ws = activeWorkspaceId();
    if (ws == null) return;
    workbench.collapseSplitLayout(ws);
    workbench.collapseSplitLayout(ws, floating: true);
  });
  bus.register(CommandIds.workbenchFocusNextGroup, () {
    final ws = activeWorkspaceId();
    if (ws == null) return;
    final layout = workbench.centerLayout(ws);
    final leaves = layout.leafGroupIds;
    if (leaves.length < 2) return;
    final index = leaves.indexOf(layout.focusedGroupId);
    workbench.focusGroup(ws, leaves[(index + 1) % leaves.length]);
  });
  bus.register(CommandIds.workbenchMoveTabToNextGroup, () {
    final ws = activeWorkspaceId();
    if (ws == null) return;
    final layout = workbench.centerLayout(ws);
    final leaves = layout.leafGroupIds;
    if (leaves.length < 2) return;
    final focusedId = layout.focusedGroupId;
    final tab = layout.groups[focusedId]?.activeId;
    if (tab == null) return;
    final index = leaves.indexOf(focusedId);
    workbench.moveTab(ws, tab, leaves[(index + 1) % leaves.length]);
  });
}
