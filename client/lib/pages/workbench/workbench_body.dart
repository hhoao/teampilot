import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/workbench/workbench_center_mode.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat_workbench.dart';
import 'diff_editor_surface.dart';
import 'file_editor_surface.dart';
import 'workbench_welcome_page.dart';

/// Center workbench body: session / file / diff. Shell and run live floating.
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

    // Compose mounts only via newChatActive IDE path; here we are never compose.
    final centerMode = resolveWorkbenchCenterMode(
      newChatActive: false,
      activeTabId: active,
    );
    if (centerMode == WorkbenchCenterMode.welcome) {
      return const WorkbenchWelcomePage();
    }
    final selected = active!;
    if (!isCenterStripWorkbenchTab(selected.kind)) {
      assert(() {
        debugPrint(
          'WorkbenchBody: shell/run tabs must not be active on the '
          'center workbench strip',
        );
        return true;
      }());
      return const WorkbenchWelcomePage();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (selected.kind == WorkbenchTabKind.session)
          ChatWorkbench(
            workspaceId: workspaceId,
            tabScopeId: tabScopeId,
            profileId: profileId,
            routeActive: routeActive,
            sessionId: sessionId,
            isPersonalContext: isPersonalContext,
            team: team,
            workbenchSlice: workbenchSlice,
          )
        else if (selected.kind == WorkbenchTabKind.file)
          FileEditorSurface(
            key: ValueKey(selected.id),
            workspaceId: workspaceId,
            path: selected.id,
          )
        else if (selected.kind == WorkbenchTabKind.diff)
          DiffEditorSurface(
            key: ValueKey(selected.id),
            workspaceId: workspaceId,
            diffKey: selected.id,
          ),
      ],
    );
  }
}
