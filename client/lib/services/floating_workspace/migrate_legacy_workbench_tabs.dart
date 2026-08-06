import 'package:path/path.dart' as p;

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/layout_preferences.dart';
import '../workbench/workbench_run_intent.dart';
import '../workbench/workbench_shell_launcher.dart';
import 'surfaces/diff_preview_floating_surface.dart';

/// One-shot migration of leftover center-strip `file` / `diff` / `shell` / `run`
/// tabs into the floating workspace bucket.
///
/// When [migrateFiles] is false (center file-preview preference), only shell
/// and run tabs move; file and diff tabs stay on the center strip.
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
                t.kind == WorkbenchTabKind.run ||
                (migrateFiles &&
                    (t.kind == WorkbenchTabKind.file ||
                        t.kind == WorkbenchTabKind.diff)),
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
          case WorkbenchTabKind.diff:
            final path = tab.diffAbsolutePath ?? tab.id;
            final source = tab.diffSource ?? WorkbenchDiffSource.changes;
            final stagedSuffix =
                source == WorkbenchDiffSource.staged ? ' (staged)' : '';
            floating.ensureTab(
              FloatingTab(
                id: floatingDiffTabId(tab.id),
                surfaceId: 'diffPreview',
                title: '${p.basename(path)}$stagedSuffix',
                payload: tab.id,
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
          case WorkbenchTabKind.run:
            final runSessionId = tab.id;
            floating.ensureTab(
              FloatingTab(
                id: floatingRunTabId(runSessionId),
                surfaceId: 'run',
                title: runSessionId,
                payload: runSessionId,
              ),
            );
          case WorkbenchTabKind.session:
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

/// Moves open floating `filePreview` / `diffPreview` tabs onto the center
/// workbench strip.
///
/// Does **not** call surface [onTabClosed] — editor/diff sessions stay open and
/// are only re-hosted. Shell tabs remain floating.
int migrateFloatingFileTabsToWorkbench({
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
}) {
  final previousActive = floating.state.activeWorkspaceId;
  var moved = 0;

  try {
    final snapshot = Map<String, FloatingWorkspaceBucket>.of(
      floating.buckets,
    );
    for (final entry in snapshot.entries) {
      final workspaceId = entry.key;
      final previewTabs = entry.value.tabs
          .where(
            (t) => t.surfaceId == 'filePreview' || t.surfaceId == 'diffPreview',
          )
          .toList(growable: false);
      if (previewTabs.isEmpty) continue;

      floating.setActiveWorkspace(workspaceId);
      for (final tab in previewTabs) {
        final payload = tab.payload is String
            ? (tab.payload! as String).trim()
            : '';
        if (payload.isEmpty) {
          floating.removeTab(tab.id);
          continue;
        }
        if (tab.surfaceId == 'diffPreview') {
          final parsed = WorkbenchTabId.parseDiffKey(payload);
          if (parsed == null) {
            floating.removeTab(tab.id);
            continue;
          }
          workbench.ensureTab(
            workspaceId,
            WorkbenchTabId.diff(parsed.$1, source: parsed.$2),
            preview: false,
          );
        } else {
          workbench.ensureTab(
            workspaceId,
            WorkbenchTabId.file(payload),
            preview: false,
          );
        }
        floating.removeTab(tab.id);
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

/// Aligns in-memory file/diff tabs with [host] after a runtime preference change.
///
/// Shell and run leftovers always migrate to floating; file/diff tabs follow
/// [host].
int syncFilePreviewHostTabs({
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
  required FilePreviewHost host,
}) {
  switch (host) {
    case FilePreviewHost.floating:
      return migrateLegacyWorkbenchTabsToFloating(
        workbench: workbench,
        floating: floating,
        migrateFiles: true,
      );
    case FilePreviewHost.center:
      final shells = migrateLegacyWorkbenchTabsToFloating(
        workbench: workbench,
        floating: floating,
        migrateFiles: false,
      );
      final files = migrateFloatingFileTabsToWorkbench(
        workbench: workbench,
        floating: floating,
      );
      return shells + files;
  }
}
