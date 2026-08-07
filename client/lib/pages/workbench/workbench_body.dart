import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/workbench/workbench_center_mode.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat/keep_alive_session_stack.dart';
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
          _SessionKeepAliveHosts(
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

/// One [ChatWorkbench] per open session, kept alive inside a
/// [KeepAliveSessionStack]. Each host is scoped to its own session id (per-host
/// [ChatWorkbenchSlice]) so switching conversations changes only the active
/// index — no remount, no history reload.
class _SessionKeepAliveHosts extends StatelessWidget {
  const _SessionKeepAliveHosts({
    required this.workspaceId,
    required this.tabScopeId,
    required this.profileId,
    required this.routeActive,
    required this.sessionId,
    required this.isPersonalContext,
    required this.team,
    required this.workbenchSlice,
  });

  final String workspaceId;
  final String tabScopeId;
  final String? profileId;
  final bool routeActive;
  final String? sessionId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final ChatWorkbenchSlice workbenchSlice;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatCubit>();
    final tabs = chat.tabStore.tabsForWorkspace(tabScopeId);
    final activeId = workbenchSlice.activeSessionId;
    return KeepAliveSessionStack(
      sessionIds: [for (final t in tabs) t.info.id],
      activeSessionId: activeId,
      hosts: [
        for (var i = 0; i < tabs.length; i++)
          ChatWorkbench(
            key: ValueKey('session-host-${tabs[i].info.id}'),
            workspaceId: workspaceId,
            tabScopeId: tabScopeId,
            profileId: profileId,
            // Only the active host is route-active: offstage hosts must not
            // spawn placeholder shells or claim terminal input focus.
            routeActive: routeActive && tabs[i].info.id == activeId,
            sessionId: sessionId,
            isPersonalContext: isPersonalContext,
            team: team,
            workbenchSlice: _sliceForSession(chat.state, tabs[i]),
          ),
      ],
    );
  }
}

/// Scopes a workbench slice to a single session so an offstage host resolves
/// only its own tab/shell — never the active conversation's.
ChatWorkbenchSlice _sliceForSession(ChatState state, ChatTab tab) {
  return ChatWorkbenchSlice(
    stateVersion: state.stateVersion,
    activeSessionId: tab.info.id,
    selectedMemberId: tab.selectedMemberId,
    activeTabIndex: 0,
    tabCount: 1,
    newChatActive: false,
    sessionConnectingId: state.sessionConnectingId == tab.info.id
        ? state.sessionConnectingId
        : null,
    sessionLaunchError: tab.info.launchError,
  );
}
