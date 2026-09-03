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
  Map<String, String> shellTitles = const {},
  Color? sessionAccent,
}) {
  return [
    for (final tab in tabOrder)
      if (isCenterStripWorkbenchTab(tab.kind))
        switch (tab.kind) {
        WorkbenchTabKind.session => TabInfo(
          id: tab.id,
          sessionId: tab.id,
          title: sessionTitles[tab.id] ?? '',
          working: sessionWorking[tab.id] ?? false,
          cli: sessionCli[tab.id],
          accentColor: sessionAccent,
          icon: Icons.terminal_rounded,
          preview: previewTabIds.contains(tab),
          pinnable: true,
          pinned: sessionPinned[tab.id] ?? false,
          kind: WorkbenchTabKind.session,
        ),
        WorkbenchTabKind.file => TabInfo(
          id: tab.id,
          title: p.basename(tab.id),
          icon: Icons.description_outlined,
          preview: previewTabIds.contains(tab),
          kind: WorkbenchTabKind.file,
          filePath: tab.id,
        ),
        WorkbenchTabKind.diff => TabInfo(
          id: tab.id,
          title: _diffTitle(tab, editorBucket),
          icon: Icons.difference_outlined,
          preview: previewTabIds.contains(tab),
          kind: WorkbenchTabKind.diff,
          filePath: tab.diffAbsolutePath,
        ),
        WorkbenchTabKind.shell ||
        WorkbenchTabKind.run ||
        WorkbenchTabKind.htmlPreview ||
        WorkbenchTabKind.gitGraph ||
        WorkbenchTabKind.gitCompare => throw StateError(
          'shell/run/htmlPreview/gitGraph/gitCompare tabs are filtered before center-strip projection',
        ),
      },
  ];
}

String _diffTitle(WorkbenchTabId tab, WorkspaceEditorBucket bucket) {
  final state = bucket.openDiffs[tab.id];
  final base = state?.title ?? p.basename(tab.diffAbsolutePath ?? tab.id);
  if (state == null) return base;
  return state.staged ? '$base (staged)' : base;
}
