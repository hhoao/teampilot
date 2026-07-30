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

  /// New RunPanel session ids — ensure and select (last wins if several).
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
    runIdsToEnsureAndSelect: runIdsToEnsureAndSelect(
      tabOrder: tabOrder,
      runPanelSessionIds: runPanelSessionIds,
    ),
    runTabsToRemove: runTabsToRemove(
      tabOrder: tabOrder,
      runPanelSessionIds: runPanelSessionIds,
    ),
  );
}
