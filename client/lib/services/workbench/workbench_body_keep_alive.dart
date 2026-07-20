import '../../cubits/workbench/workbench_tab.dart';

/// Which shell/run surfaces [WorkbenchBody] should keep mounted.
class WorkbenchBodyKeepAlivePlan {
  const WorkbenchBodyKeepAlivePlan({
    required this.shellEntryIds,
    required this.shellActiveEntryId,
    required this.shellOffstage,
    required this.runSessionIds,
    required this.active,
  });

  /// Shell entry ids in strip order (tabOrder filtered by kind).
  final List<String> shellEntryIds;

  /// Entry id passed to the single [WorkspaceTerminalPanel] (needs a valid id
  /// even when offstage).
  final String? shellActiveEntryId;

  /// True when the shell surface is mounted but not the active tab.
  final bool shellOffstage;

  /// Run session ids in strip order that are still live in RunCubit.
  final List<String> runSessionIds;

  final WorkbenchTabId? active;

  bool get mountShell => shellEntryIds.isNotEmpty;

  bool runOffstage(String sessionId) {
    final a = active;
    return a == null ||
        a.kind != WorkbenchTabKind.run ||
        a.id != sessionId;
  }
}

/// Derive keep-alive mounts from strip order ∩ live domain ids.
WorkbenchBodyKeepAlivePlan resolveWorkbenchBodyKeepAlive({
  required List<WorkbenchTabId> tabOrder,
  required WorkbenchTabId? active,
  required Iterable<String> liveRunSessionIds,
}) {
  final shellEntryIds = [
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.shell) tab.id,
  ];

  final liveRuns = liveRunSessionIds.toSet();
  final runSessionIds = [
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.run && liveRuns.contains(tab.id))
        tab.id,
  ];

  String? shellActiveEntryId;
  var shellOffstage = true;
  if (shellEntryIds.isNotEmpty) {
    if (active?.kind == WorkbenchTabKind.shell) {
      shellActiveEntryId = active!.id;
      shellOffstage = false;
    } else {
      // Panel needs a valid id while offstage; prefer last shell in strip order.
      shellActiveEntryId = shellEntryIds.last;
      shellOffstage = true;
    }
  }

  return WorkbenchBodyKeepAlivePlan(
    shellEntryIds: shellEntryIds,
    shellActiveEntryId: shellActiveEntryId,
    shellOffstage: shellOffstage,
    runSessionIds: runSessionIds,
    active: active,
  );
}
