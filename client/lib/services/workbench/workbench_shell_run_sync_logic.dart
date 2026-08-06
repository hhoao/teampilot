import '../../cubits/workbench/workbench_tab.dart';

/// Diff between workbench strip run tabs and live RunPanel session ids.
///
/// Shell terminals live on the floating workspace surface — this plan never
/// projects `shell` onto the center strip (`shellIdsToEnsure` /
/// `shellTabsToRemove` are always empty).
class WorkbenchShellRunSyncPlan {
  const WorkbenchShellRunSyncPlan({
    required this.shellIdsToEnsure,
    required this.shellTabsToRemove,
    required this.runIdsToEnsureAndSelect,
    required this.runTabsToRemove,
  });

  /// Always empty — floating surface owns shell tabs.
  final List<String> shellIdsToEnsure;

  /// Always empty — floating surface owns shell tabs.
  final List<WorkbenchTabId> shellTabsToRemove;

  /// Always empty — floating surface owns run tabs.
  final List<String> runIdsToEnsureAndSelect;

  /// Run tabs whose RunPanel session no longer exists.
  final List<WorkbenchTabId> runTabsToRemove;

  bool get isEmpty =>
      shellIdsToEnsure.isEmpty &&
      shellTabsToRemove.isEmpty &&
      runIdsToEnsureAndSelect.isEmpty &&
      runTabsToRemove.isEmpty;
}

/// RunPanel session ids not yet present as run tabs (order preserved).
List<String> runIdsToEnsureAndSelect({
  required List<WorkbenchTabId> tabOrder,
  required Iterable<String> runPanelSessionIds,
}) {
  final existing = {
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.run) tab.id,
  };
  return [
    for (final id in runPanelSessionIds)
      if (!existing.contains(id)) id,
  ];
}

/// Live RunPanel session ids not yet present as floating run tabs.
List<String> floatingRunIdsToEnsure({
  required Iterable<String> existingFloatingRunSessionIds,
  required Iterable<String> liveRunPanelSessionIds,
}) {
  final existing = existingFloatingRunSessionIds.toSet();
  return [
    for (final id in liveRunPanelSessionIds)
      if (!existing.contains(id)) id,
  ];
}

/// Whether passive reconcile should mutate floating run tabs for [bridgeWorkspaceId].
///
/// Returns false when there is nothing to ensure/remove, or when the floating
/// panel is focused on a different workspace (avoids hijacking active workspace).
bool shouldSyncFloatingRuns({
  required String bridgeWorkspaceId,
  required String floatingActiveWorkspaceId,
  required bool hasFloatingMutations,
}) {
  if (!hasFloatingMutations) return false;
  return floatingActiveWorkspaceId.trim() == bridgeWorkspaceId.trim();
}

/// Floating run session ids whose RunPanel session no longer exists.
List<String> floatingRunIdsToRemove({
  required Iterable<String> existingFloatingRunSessionIds,
  required Iterable<String> liveRunPanelSessionIds,
}) {
  final live = liveRunPanelSessionIds.toSet();
  return [
    for (final id in existingFloatingRunSessionIds)
      if (!live.contains(id)) id,
  ];
}

/// Run tabs whose RunPanel session id is gone.
List<WorkbenchTabId> runTabsToRemove({
  required List<WorkbenchTabId> tabOrder,
  required Iterable<String> runPanelSessionIds,
}) {
  final live = runPanelSessionIds.toSet();
  return [
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.run && !live.contains(tab.id)) tab,
  ];
}

/// Run-only strip reconciliation plan (shell projection discontinued).
///
/// [registryEntryIds] is accepted for call-site compatibility but ignored —
/// workspace shells are no longer mirrored into [WorkbenchCubit].
WorkbenchShellRunSyncPlan planWorkbenchShellRunSync({
  required List<WorkbenchTabId> tabOrder,
  required Iterable<String> registryEntryIds,
  required Iterable<String> runPanelSessionIds,
}) {
  return WorkbenchShellRunSyncPlan(
    shellIdsToEnsure: const [],
    shellTabsToRemove: const [],
    runIdsToEnsureAndSelect: const [],
    runTabsToRemove: runTabsToRemove(
      tabOrder: tabOrder,
      runPanelSessionIds: runPanelSessionIds,
    ),
  );
}
