import 'package:path/path.dart' as p;

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
import '../workbench/workbench_shell_launcher.dart';

/// One-shot migration of leftover center-strip `file` / `shell` tabs into the
/// floating workspace bucket.
///
/// **Why this exists:** Task 7 rejects *new* shell tabs via
/// [WorkbenchCubit.ensureTab], and [WorkbenchCubit.syncSessions] already drops
/// shell leftovers on the next session sync. This helper covers in-memory
/// buckets that still hold shell (and optionally file) before sync runs.
///
/// When [migrateFiles] is false (center file-preview preference), only shell
/// tabs move; file tabs stay on the center strip.
///
/// Returns the number of tabs moved. Safe to call multiple times (idempotent
/// once the strip is clean). Does not open the floating panel.
int migrateLegacyWorkbenchTabsToFloating({
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
  bool migrateFiles = true,
}) {
  final previousActive = floating.state.activeWorkspaceId;
  var moved = 0;

  try {
    for (final entry in workbench.state.byWorkspace.entries) {
      final workspaceId = entry.key;
      final leftovers = entry.value.tabOrder
          .where(
            (t) =>
                t.kind == WorkbenchTabKind.shell ||
                (migrateFiles && t.kind == WorkbenchTabKind.file),
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
