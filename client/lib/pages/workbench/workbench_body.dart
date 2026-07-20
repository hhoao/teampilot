import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat_workbench.dart';
import '../home_workspace/workspace/workspace_compose_landing_pane.dart';
import 'diff_editor_surface.dart';
import 'file_editor_surface.dart';

/// Center workbench body: session terminal, file editor, diff, or compose.
class WorkbenchBody extends StatelessWidget {
  const WorkbenchBody({
    required this.workspaceId,
    required this.tabScopeId,
    required this.workspace,
    required this.workbenchSlice,
    this.profileId,
    this.routeActive = true,
    this.sessionId,
    this.isPersonalContext = false,
    this.team,
    super.key,
  });

  final String workspaceId;
  final String tabScopeId;
  final Workspace workspace;
  final ChatWorkbenchSlice workbenchSlice;
  final String? profileId;
  final bool routeActive;
  final String? sessionId;
  final bool isPersonalContext;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    final active = context.select<WorkbenchCubit, WorkbenchTabId?>(
      (c) => c.activeTabId(workspaceId),
    );

    // Spec: if activeTabId != null, body is never compose.
    if (active == null) {
      return WorkspaceComposeLandingPane(workspace: workspace);
    }

    switch (active.kind) {
      case WorkbenchTabKind.session:
        return ChatWorkbench(
          workspaceId: workspaceId,
          tabScopeId: tabScopeId,
          profileId: profileId,
          routeActive: routeActive,
          sessionId: sessionId,
          isPersonalContext: isPersonalContext,
          team: team,
          workbenchSlice: workbenchSlice,
        );
      case WorkbenchTabKind.file:
        return FileEditorSurface(
          key: ValueKey(active.id),
          workspaceId: workspaceId,
          path: active.id,
        );
      case WorkbenchTabKind.diff:
        return DiffEditorSurface(
          key: ValueKey(active.id),
          workspaceId: workspaceId,
          diffKey: active.id,
        );
      case WorkbenchTabKind.shell:
      case WorkbenchTabKind.run:
        return const SizedBox.shrink();
    }
  }
}
