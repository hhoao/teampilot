import 'dart:async';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/chat_tab_info.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../cubits/chat/model/session_workbench_view.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';

typedef PrepareNewTabConnectFn =
    Future<void> Function({
      required int generation,
      required ChatTab tab,
      required AppSession session,
      required SessionOpenRequest request,
      required Workspace? workspace,
      required bool connect,
    });

typedef PrepareExistingTabConnectFn =
    Future<void> Function({
      required int generation,
      required ChatTab tab,
      required SessionOpenRequest request,
      required bool connect,
    });

typedef PrepareDeferredTeamTabFn =
    Future<void> Function({
      required int generation,
      required ChatTab tab,
      required AppSession session,
      required SessionOpenRequest request,
    });

/// Stages new or reuses existing conversation tabs before async connect prep.
class SessionTabSurfaceCoordinator {
  SessionTabSurfaceCoordinator({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    required ChatState Function() state,
    required Workspace? Function(String workspaceId) workspaceById,
    required bool Function(SessionOpenRequest request) shouldAutoConnect,
    required PrepareNewTabConnectFn prepareNewTabConnect,
    required PrepareExistingTabConnectFn prepareExistingTabConnect,
    required PrepareDeferredTeamTabFn prepareDeferredTeamTab,
  }) : _host = host,
       _tabStore = tabStore,
       _state = state,
       _workspaceById = workspaceById,
       _shouldAutoConnect = shouldAutoConnect,
       _prepareNewTabConnect = prepareNewTabConnect,
       _prepareExistingTabConnect = prepareExistingTabConnect,
       _prepareDeferredTeamTab = prepareDeferredTeamTab;

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final ChatState Function() _state;
  final Workspace? Function(String workspaceId) _workspaceById;
  final bool Function(SessionOpenRequest request) _shouldAutoConnect;
  final PrepareNewTabConnectFn _prepareNewTabConnect;
  final PrepareExistingTabConnectFn _prepareExistingTabConnect;
  final PrepareDeferredTeamTabFn _prepareDeferredTeamTab;

  SessionOpenStatus surfaceExistingTab({
    required SessionOpenRequest request,
    required int existingIdx,
  }) {
    final session = request.session;
    appLogger.d(
      '[session-launch] requestOpenSession reuse existing tab '
      'session=${session.sessionId} idx=$existingIdx',
    );
    final existing = _tabStore.activeTabs[existingIdx];
    final memberId = request.isPersonal
        ? existing.selectedMemberId
        : (request.member?.id ?? existing.selectedMemberId);
    if (memberId.isNotEmpty) {
      existing.selectedMemberId = memberId;
    }
    final state = _state();
    final connectAlreadyScheduled =
        state.sessionConnectingId == session.sessionId;
    if (!connectAlreadyScheduled) {
      existing.bumpLaunchGeneration();
    }
    final generation = existing.launchGeneration;
    _host.applyState(
      state.copyWith(
        activeTabIndex: existingIdx,
        activeSessionId: session.sessionId,
        selectedMemberId: memberId.isNotEmpty ? memberId : null,
        composeActive: false,
      ),
    );
    _host.refreshActiveWorkspaceTabs();
    if (!request.connectImmediately) {
      unawaited(
        _prepareExistingTabConnect(
          generation: generation,
          tab: existing,
          request: request,
          connect: false,
        ),
      );
      return SessionOpenStatus.opened;
    }
    // History continue connects the PTY while staying on History; do not
    // force-switch the workbench (would unmount SessionHistoryReview).
    if (!request.preserveWorkbenchView) {
      existing.workbenchView = SessionWorkbenchView.terminal;
    }
    if (_shouldAutoConnect(request) && !connectAlreadyScheduled) {
      _host.beginSessionConnect(session.sessionId);
    }
    if (connectAlreadyScheduled && request.connectImmediately) {
      appLogger.d(
        '[session-launch] requestOpenSession skip duplicate connect '
        'session=${session.sessionId}',
      );
      return SessionOpenStatus.opened;
    }
    unawaited(
      _prepareExistingTabConnect(
        generation: generation,
        tab: existing,
        request: request,
        connect: _shouldAutoConnect(request),
      ),
    );
    return SessionOpenStatus.opened;
  }

  SessionOpenStatus surfaceNewTab({
    required SessionOpenRequest request,
    required AppSession session,
  }) {
    final workspace = request.workspace ?? _workspaceById(session.workspaceId);
    if (request.isPersonal && workspace == null) {
      return SessionOpenStatus.missingWorkspace;
    }

    final placeholderMemberId = request.isPersonal
        ? ''
        : (request.member?.id ?? TeamMemberNaming.teamLeadName);
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.resolveDisplayTitle(request.emptyDisplayTitleFallback),
      subtitle: session.firstFolderPath,
    );
    final tab =
        ChatTab(
            info: info,
            cliTeamName: session.cliTeamName,
            workspaceId: session.workspaceId,
          )
          ..persistedSession = session
          ..selectedMemberId = placeholderMemberId;
    tab.bumpLaunchGeneration();
    final generation = tab.launchGeneration;

    _tabStore.append(tab);
    _host.sessionRuntime.ensureIdleWatch();
    _host.applyState(
      _state().copyWith(
        activeTabIndex: _tabStore.activeTabCount - 1,
        activeSessionId: session.sessionId,
        selectedMemberId: placeholderMemberId,
        composeActive: false,
      ),
    );
    _host.refreshActiveWorkspaceTabs();

    if (!request.connectImmediately) {
      unawaited(
        _prepareNewTabConnect(
          generation: generation,
          tab: tab,
          session: session,
          request: request,
          workspace: workspace,
          connect: false,
        ),
      );
      return SessionOpenStatus.opened;
    }

    if (!request.preserveWorkbenchView) {
      tab.workbenchView = SessionWorkbenchView.terminal;
    }
    if (_shouldAutoConnect(request)) {
      _host.beginSessionConnect(session.sessionId);
      unawaited(
        _prepareNewTabConnect(
          generation: generation,
          tab: tab,
          session: session,
          request: request,
          workspace: workspace,
          connect: true,
        ),
      );
    } else {
      unawaited(
        _prepareDeferredTeamTab(
          generation: generation,
          tab: tab,
          session: session,
          request: request,
        ),
      );
      _host.updateTabRunning(session.sessionId);
    }
    return SessionOpenStatus.opened;
  }
}
