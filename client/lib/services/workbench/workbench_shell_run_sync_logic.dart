import '../../cubits/workbench/workbench_tab.dart';

/// Diff between workbench strip shell/run tabs and live domain ids.
class WorkbenchShellRunSyncPlan {
  const WorkbenchShellRunSyncPlan({
    required this.shellIdsToEnsure,
    required this.shellTabsToRemove,
    required this.runIdsToEnsureAndSelect,
    required this.runTabsToRemove,
  });

  /// Registry entry ids missing from [tabOrder] — ensure without selecting.
  final List<String> shellIdsToEnsure;

  /// Shell tabs whose registry entry no longer exists.
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

/// Registry entry ids not yet present as shell tabs.
List<String> shellIdsToEnsure({
  required List<WorkbenchTabId> tabOrder,
  required Iterable<String> registryEntryIds,
}) {
  final existing = {
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.shell) tab.id,
  };
  return [
    for (final id in registryEntryIds)
      if (!existing.contains(id)) id,
  ];
}

/// Shell tabs whose entry id is absent from the registry.
List<WorkbenchTabId> shellTabsToRemove({
  required List<WorkbenchTabId> tabOrder,
  required Iterable<String> registryEntryIds,
}) {
  final live = registryEntryIds.toSet();
  return [
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.shell && !live.contains(tab.id)) tab,
  ];
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

/// Full shell/run strip reconciliation plan for the current domain snapshot.
WorkbenchShellRunSyncPlan planWorkbenchShellRunSync({
  required List<WorkbenchTabId> tabOrder,
  required Iterable<String> registryEntryIds,
  required Iterable<String> runPanelSessionIds,
}) {
  return WorkbenchShellRunSyncPlan(
    shellIdsToEnsure: shellIdsToEnsure(
      tabOrder: tabOrder,
      registryEntryIds: registryEntryIds,
    ),
    shellTabsToRemove: shellTabsToRemove(
      tabOrder: tabOrder,
      registryEntryIds: registryEntryIds,
    ),
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
