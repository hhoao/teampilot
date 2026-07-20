import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/workbench/workbench_body_keep_alive.dart';
import '../../widgets/workspace_terminal_panel.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat_workbench.dart';
import '../home_workspace/workspace/workspace_compose_landing_pane.dart';
import 'diff_editor_surface.dart';
import 'file_editor_surface.dart';
import 'run_tab_surface.dart';
import 'shell_terminal_surface.dart';

/// Center workbench body: session / file / diff / shell / run, with keep-alive
/// for shell + run so PTY scrollback and Run output survive tab switches.
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
    this.workingDirectory,
    this.holdHandle,
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

  /// CWD for the workspace shell PTY (worktree / first folder).
  final String? workingDirectory;

  /// PTY resize hold; bound by the center [ShellTerminalSurface] panel.
  final WorkspaceTerminalHoldHandle? holdHandle;

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

    // Spec: if activeTabId != null, body is never compose.
    if (active == null) {
      return WorkspaceComposeLandingPane(workspace: workspace);
    }

    final plan = resolveWorkbenchBodyKeepAlive(
      tabOrder: tabOrder,
      active: active,
      liveRunSessionIds: liveRunIds,
    );
    final cwd = workingDirectory;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Primary kinds: mount only while selected (same as pre-shell/run).
        if (active.kind == WorkbenchTabKind.session)
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
        else if (active.kind == WorkbenchTabKind.file)
          FileEditorSurface(
            key: ValueKey(active.id),
            workspaceId: workspaceId,
            path: active.id,
          )
        else if (active.kind == WorkbenchTabKind.diff)
          DiffEditorSurface(
            key: ValueKey(active.id),
            workspaceId: workspaceId,
            diffKey: active.id,
          ),
        // One shell panel for all shell tabs (HoldHandle binds once).
        if (plan.mountShell && cwd != null)
          Offstage(
            offstage: plan.shellOffstage,
            child: IgnorePointer(
              ignoring: plan.shellOffstage,
              child: ShellTerminalSurface(
                workspaceId: workspaceId,
                tabScopeId: tabScopeId,
                workingDirectory: cwd,
                holdHandle: holdHandle,
                activeEntryId: plan.shellActiveEntryId,
              ),
            ),
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
