import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/workbench/workbench_body_keep_alive.dart';
import '../../services/workbench/workbench_center_mode.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat_workbench.dart';
import 'diff_editor_surface.dart';
import 'run_tab_surface.dart';
import 'workbench_welcome_page.dart';

/// Center workbench body: session / diff / run, with keep-alive for run so
/// output survives tab switches. File and shell live in the floating panel.
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
    final tabOrder = context.select<WorkbenchCubit, List<WorkbenchTabId>>(
      (c) => c.tabOrder(workspaceId),
    );
    final liveRunIds = context.select<RunCubit, List<String>>(
      (c) => c.state.sessions.map((s) => s.id).toList(growable: false),
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
          'WorkbenchBody: file and shell tabs must not be active on the '
          'center workbench strip',
        );
        return true;
      }());
      return const WorkbenchWelcomePage();
    }

    final plan = resolveWorkbenchBodyKeepAlive(
      tabOrder: tabOrder,
      active: selected,
      liveRunSessionIds: liveRunIds,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Primary kinds: mount only while selected (same as pre-shell/run).
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
        else if (selected.kind == WorkbenchTabKind.diff)
          DiffEditorSurface(
            key: ValueKey(selected.id),
            workspaceId: workspaceId,
            diffKey: selected.id,
          ),
        for (final runId in plan.runSessionIds)
          Offstage(
            offstage: plan.runOffstage(runId),
            child: IgnorePointer(
              ignoring: plan.runOffstage(runId),
              child: RunTabSurface(sessionId: runId),
            ),
          ),
      ],
    );
  }
}
