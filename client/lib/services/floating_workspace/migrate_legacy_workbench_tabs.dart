import 'package:path/path.dart' as p;

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
import '../workbench/workbench_shell_launcher.dart';

/// One-shot migration of leftover center-strip `file` / `shell` tabs into the
/// floating workspace bucket.
///
/// **Why this exists:** Task 7 rejects *new* file/shell via
/// [WorkbenchCubit.ensureTab], and [WorkbenchCubit.syncSessions] already drops
/// leftovers on the next session sync. This helper covers in-memory buckets
/// that still hold file/shell before sync runs (mid-session upgrade, tests,
/// or any path that seeded tabs before the reject landed).
///
/// **What it does:** For each workbench workspace bucket, move every
/// `WorkbenchTabKind.file` / `.shell` into the matching floating bucket
/// (`filePreview` / `terminal` tab ids), then [WorkbenchCubit.removeTab] them
/// from the center strip. Domain state (`EditorCubit` open files, terminal
/// registry entries) is left alone — only the strip membership moves.
///
/// Returns the number of tabs moved. Safe to call multiple times (idempotent
/// once the strip is clean). Does not open the floating panel.
int migrateLegacyWorkbenchTabsToFloating({
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
}) {
  final previousActive = floating.state.activeWorkspaceId;
  var moved = 0;

  try {
    for (final entry in workbench.state.byWorkspace.entries) {
      final workspaceId = entry.key;
      final leftovers = entry.value.tabOrder
          .where(
            (t) =>
                t.kind == WorkbenchTabKind.file ||
                t.kind == WorkbenchTabKind.shell,
          )
          .toList(growable: false);
      if (leftovers.isEmpty) continue;

      floating.setActiveWorkspace(workspaceId);
      for (final tab in leftovers) {
        switch (tab.kind) {
          case WorkbenchTabKind.file:
            final path = tab.filePath ?? tab.id;
            floating.ensureTab(
              FloatingTab(
                id: 'file:$path',
                surfaceId: 'filePreview',
                title: p.basename(path),
                payload: path,
              ),
            );
          case WorkbenchTabKind.shell:
            final entryId = tab.id;
            floating.ensureTab(
              FloatingTab(
                id: floatingShellTabId(entryId),
                surfaceId: 'terminal',
                title: entryId,
                payload: entryId,
              ),
            );
          case WorkbenchTabKind.session:
          case WorkbenchTabKind.diff:
          case WorkbenchTabKind.run:
            continue;
        }
        workbench.removeTab(workspaceId, tab);
        moved++;
      }
    }
  } finally {
    if (floating.state.activeWorkspaceId != previousActive) {
      floating.setActiveWorkspace(previousActive);
    }
  }

  return moved;
}
