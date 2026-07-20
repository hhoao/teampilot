import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../pages/workspace_shell/workspace_shell_models.dart';

/// Builds [TabInfo] rows for [WorkspaceShell] from workbench + domain state.
List<TabInfo> projectWorkbenchTabs({
  required List<WorkbenchTabId> tabOrder,
  required Map<String, String> sessionTitles,
  required Map<String, bool> sessionWorking,
  required Map<String, CliTool?> sessionCli,
  required WorkspaceEditorBucket editorBucket,
  required Set<WorkbenchTabId> previewTabIds,
  Map<String, bool> sessionPinned = const {},
  Color? sessionAccent,
}) {
  return [
    for (final tab in tabOrder)
      switch (tab.kind) {
        WorkbenchTabKind.session => TabInfo(
          id: tab.id,
          title: sessionTitles[tab.id] ?? tab.id,
          working: sessionWorking[tab.id] ?? false,
          cli: sessionCli[tab.id],
          accentColor: sessionAccent,
          icon: Icons.terminal_rounded,
          preview: previewTabIds.contains(tab),
          pinnable: true,
          pinned: sessionPinned[tab.id] ?? false,
        ),
        WorkbenchTabKind.file => TabInfo(
          id: tab.id,
          title: _fileTitle(tab.id, editorBucket),
          icon: Icons.description_outlined,
          preview: previewTabIds.contains(tab),
        ),
        WorkbenchTabKind.diff => TabInfo(
          id: tab.id,
          title: _diffTitle(tab, editorBucket),
          icon: Icons.difference_outlined,
          preview: previewTabIds.contains(tab),
        ),
        WorkbenchTabKind.shell || WorkbenchTabKind.run => TabInfo(
          id: tab.id,
          title: tab.id,
        ),
      },
  ];
}

String _fileTitle(String path, WorkspaceEditorBucket bucket) {
  final name = p.basename(path);
  return bucket.isDirty(path) ? '$name •' : name;
}

String _diffTitle(WorkbenchTabId tab, WorkspaceEditorBucket bucket) {
  final state = bucket.openDiffs[tab.id];
  final base = state?.title ?? p.basename(tab.diffAbsolutePath ?? tab.id);
  if (state == null) return base;
  return switch (state.source) {
    WorkbenchDiffSource.staged => '$base (staged)',
    WorkbenchDiffSource.unstaged => base,
    WorkbenchDiffSource.changes => base,
  };
}
