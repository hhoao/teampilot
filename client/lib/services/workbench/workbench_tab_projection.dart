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
  Map<String, String> runTitles = const {},
  Map<String, bool> runWorking = const {},
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
        ),
        WorkbenchTabKind.diff => TabInfo(
          id: tab.id,
          title: _diffTitle(tab, editorBucket),
          icon: Icons.difference_outlined,
          preview: previewTabIds.contains(tab),
        ),
        WorkbenchTabKind.run => TabInfo(
          id: tab.id,
          title: runTitles[tab.id] ?? tab.id,
          icon: Icons.play_arrow_rounded,
          working: runWorking[tab.id] ?? false,
          pinnable: false,
        ),
        WorkbenchTabKind.file || WorkbenchTabKind.shell => throw StateError(
          'file/shell tabs are filtered before center-strip projection',
        ),
      },
  ];
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
