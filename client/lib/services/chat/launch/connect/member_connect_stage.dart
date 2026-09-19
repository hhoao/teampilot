import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../chat_tab_store.dart';
import '../../../../cubits/chat_state.dart';
import '../../model/chat_tab.dart';
import '../../model/session_connect_request.dart';
import '../../model/session_open_request.dart';
import '../../host/session_launch_host.dart';
import '../../../../models/app_session.dart';
import '../../../../models/member_instance.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../repositories/session_repository.dart';
import '../../../terminal/terminal_session.dart';
import '../../../../utils/logging/logger.dart';
import '../contracts/member_connect_types.dart';
import '../session/session_default_materializer.dart';
import '../session/session_launch_coordinator.dart';
import 'session_connect_job.dart';
import 'session_connect_scheduler.dart';

/// Flow B — connecting a member's seat.
///
/// Owns member-terminal intent: choosing the target member, materializing a
/// first session when none is open, scheduling per-seat connects, and tearing
/// shells down on restart.
class MemberConnectStage {
  MemberConnectStage({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    required ChatState Function() state,
    required SessionDefaultMaterializer materializer,
    required SessionLaunchIntentPort coordinator,
    required SessionConnectSchedulerPort scheduler,
    required SessionForMemberConnectFn sessionForMemberConnect,
    required void Function() disconnectSession,
    required TerminalSession? Function(TeamProfile team) ensureSession,
    required ChatTab Function(TeamProfile team, {required bool emitChange})
    appendLocalTab,
    required ChatTab Function(TeamProfile team, {required bool emitChange})
    ensureActiveSessionTab,
    required void Function() resetTeamConfigValidationSurface,
    required Future<void> Function(TeamProfile team)
    scheduleTeamConfigValidation,
    required ChatTab? Function() activeTab,
    required bool Function() autoLaunchAllMembersOnConnect,
    required Workspace? Function(String workspaceId) workspaceById,
  }) : _host = host,
       _tabStore = tabStore,
       _state = state,
       _materializer = materializer,
       _coordinator = coordinator,
       _scheduler = scheduler,
       _sessionForMemberConnect = sessionForMemberConnect,
       _disconnectSession = disconnectSession,
       _ensureSession = ensureSession,
       _appendLocalTab = appendLocalTab,
       _ensureActiveSessionTab = ensureActiveSessionTab,
       _resetTeamConfigValidationSurface = resetTeamConfigValidationSurface,
       _scheduleTeamConfigValidation = scheduleTeamConfigValidation,
       _activeTab = activeTab,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _workspaceById = workspaceById;

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final ChatState Function() _state;
  final SessionDefaultMaterializer _materializer;
  final SessionLaunchIntentPort _coordinator;
  final SessionConnectSchedulerPort _scheduler;
  final SessionForMemberConnectFn _sessionForMemberConnect;
  final void Function() _disconnectSession;
  final TerminalSession? Function(TeamProfile team) _ensureSession;
  final ChatTab Function(TeamProfile team, {required bool emitChange})
  _appendLocalTab;
  final ChatTab Function(TeamProfile team, {required bool emitChange})
  _ensureActiveSessionTab;
  final void Function() _resetTeamConfigValidationSurface;
  final Future<void> Function(TeamProfile team) _scheduleTeamConfigValidation;
  final ChatTab? Function() _activeTab;
  final bool Function() _autoLaunchAllMembersOnConnect;
  final Workspace? Function(String workspaceId) _workspaceById;

  /// Connects [request]'s target. Returns [LaunchSkipped] when an in-flight
  /// connect already owns it.
  Future<void> run(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    // Same-target connect guard. Different sessions launch concurrently: their
    // config provisioning writes are session-scoped (`sessions/{id}/runtime/`),
    // so there is no shared-write race. Only the target session's own in-flight
    // connect (or pre-session materialization, which has no session pod yet)
    // must serialize.
    if (shouldSerializeConnect(
      request: request,
      tabStore: _tabStore,
      isSessionConnecting: _host.isSessionConnecting,
      isMaterializingInFlight: _host.isMaterializingInFlight,
    )) {
      return;
    }

    switch (request) {
      case TeamSessionConnect(:final team):
        await _connectTeamSession(team, repo: repo);
      case PersonalSessionConnect(:final workspaceId, :final cliOverride):
        await _connectPersonalSession(
          workspaceId: workspaceId,
          cliOverride: cliOverride,
          repo: repo,
        );
      case ExistingSessionConnect(
        :final session,
        :final team,
        :final member,
        :final workspace,
        :final preserveWorkbenchView,
      ):
        await _connectExistingSession(
          session: session,
          team: team,
          member: member,
          workspace: workspace,
          preserveWorkbenchView: preserveWorkbenchView,
          repo: repo,
        );
    }
  }

  /// Tears the current seat down first, then reconnects.
  Future<void> restart(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    switch (request) {
      case TeamSessionConnect(:final team):
        await _restartTeamSession(team, repo: repo);
      case PersonalSessionConnect():
        _disconnectSession();
        await run(request, repo: repo);
      case ExistingSessionConnect():
        _disconnectSession();
        await run(request, repo: repo);
    }
  }

  Future<void> openMemberTab(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
    bool scheduleTeamConfigValidation = true,
  }) async {
    if (scheduleTeamConfigValidation) {
      unawaited(_scheduleTeamConfigValidation(team));
    }
    final r = repo ?? _host.sessionRepository;
    if (_tabStore.activeTabsIsEmpty && r != null) {
      _host.beginSessionConnect('pending');
      try {
        await _materializer.materializeTeamSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: member,
          workspaceCwd: workspaceCwd,
        );
        if (_host.isClosed) return;
        if (team.teamMode == TeamMode.mixed) {
          final tab = _activeTab();
          if (tab != null) {
            await scheduleMemberConnectAndWait(
              team,
              member,
              tab,
              repo: r,
              reason: LaunchReason.memberSelected,
            );
          }
        }
      } on Object catch (e, st) {
        appLogger.e(
          'openMemberTab: default session failed: $e',
          stackTrace: st,
        );
        _host.failSessionConnect(
          'pending',
          'Failed to create session: $e',
          error: e,
          stackTrace: st,
        );
      }
      return;
    }
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    await scheduleMemberConnectAndWait(
      team,
      member,
      tab,
      repo: r,
      reason: LaunchReason.memberSelected,
    );
  }

  Future<void> launchAllMembers(
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) async {
    final r = repo ?? _host.sessionRepository;
    final existingSession = _activeTab()?.persistedSession;
    final validMembers =
        (existingSession == null
                ? runtimeRosterMembers(team)
                : sessionRosterMembers(existingSession, team))
            .where((m) => m.isValid)
            .toList();
    if (validMembers.isEmpty) return;

    if (_tabStore.activeTabsIsEmpty && r != null) {
      try {
        final initialMember = validMembers.first;
        await _materializer.materializeTeamSession(
          team,
          r,
          // All members are scheduled below through the completion-aware
          // fan-out. Avoid leaving the initial member on a fire-and-forget
          // scheduler callback that this public operation cannot await.
          connectImmediately: false,
          scheduleConnect: false,
          memberForInitialShell: initialMember,
          workspaceCwd: workspaceCwd,
        );
        if (_host.isClosed) return;
        final tab = _activeTab();
        if (tab != null) {
          await _scheduleMembersAndWait(tab, team, repo: r);
        }
      } on Object catch (e, st) {
        appLogger.e(
          'launchAllMembers: default session failed: $e',
          stackTrace: st,
        );
      }
      return;
    }

    final tab = _ensureActiveSessionTab(team, emitChange: true);
    await _scheduleMembersAndWait(tab, team, repo: r);
  }

  /// Enqueues a member connect through the shared scheduler.
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab, {
    bool selectMember = true,
    LaunchReason? reason,
  }) {
    unawaited(
      _scheduleMemberConnect(
        team,
        member,
        tab,
        selectMember: selectMember,
        reason: reason,
      ),
    );
  }

  /// Enqueues a member connect and waits for its shell/materialization work.
  ///
  /// Public launch operations use this completion-aware path. The
  /// [MemberConnector] callback above intentionally remains fire-and-forget
  /// for background materialization and restore work.
  Future<void> scheduleMemberConnectAndWait(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab, {
    SessionRepository? repo,
    bool selectMember = true,
    LaunchReason? reason,
  }) => _scheduleMemberConnect(
    team,
    member,
    tab,
    repo: repo,
    selectMember: selectMember,
    reason: reason,
    waitForCompletion: true,
  );

  Future<void> _scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab, {
    SessionRepository? repo,
    bool selectMember = true,
    LaunchReason? reason,
    bool waitForCompletion = false,
  }) async {
    final memberId = member.id.trim();
    if (memberId.isEmpty || !member.isValid) return;
    if (selectMember) {
      _host.assignSelectedMember(tab, memberId);
    }
    final activeSession =
        tab.persistedSession ?? _sessionForMemberConnect(tab, team);
    if (activeSession == null) {
      _host.failSessionConnect(
        tab.info.id,
        'No persisted session for this tab. Create a team session first.',
      );
      return;
    }
    tab.persistedSession = activeSession;
    final shell = tab.memberShells[memberId];
    final memberConnectPending = tab.membersPendingConnect.contains(memberId);
    if (shell != null &&
        (shell.isRunning || shell.isConnecting) &&
        !(waitForCompletion && memberConnectPending)) {
      _host.memberMaterializer.markMemberReady(tab.info.id, memberId);
      _host.updateTabRunning(tab.info.id);
      return;
    }
    // Re-submit a pending identity for completion-aware callers so the
    // scheduler returns the existing member future instead of an early no-op.
    if (memberConnectPending && !waitForCompletion) return;
    _tabStore.workingDirectoryAndAddDirsForTab(
      tab,
      _state().sessions,
      workspaces: _state().workspaces,
    );
    final request = SessionOpenRequest(
      session: activeSession,
      workspace: _workspaceById(activeSession.workspaceId),
      team: team,
      member: member,
      repo: repo ?? _host.sessionRepository,
    );
    final job = SessionConnectJob(
      tab: tab,
      session: activeSession,
      request: request,
      generation: tab.launchGeneration,
      workspace: request.workspace,
      team: team,
      member: member,
      reason: reason ?? LaunchReason.memberSelected,
    );
    appLogger.d(
      '[session-launch] scheduleMemberConnect '
      'session=${job.sessionId} member=${job.memberId} reason=${job.reason.name}',
    );
    await _scheduler.enqueue(job, waitForCompletion: waitForCompletion);
  }

  List<TeamMemberConfig> _membersForTab(ChatTab? tab, TeamProfile team) {
    final session = tab?.persistedSession;
    final members = session == null
        ? runtimeRosterMembers(team)
        : sessionRosterMembers(session, team);
    return members.where((member) => member.isValid).toList();
  }

  Future<void> _scheduleMembersAndWait(
    ChatTab tab,
    TeamProfile team, {
    SessionRepository? repo,
  }) async {
    final members = _membersForTab(tab, team);
    if (members.isEmpty) return;
    // The first member owns team-runtime installation. Complete that boundary
    // before fanning out the remaining seats, which may still connect in
    // parallel without racing the shared per-tab runtime setup.
    await scheduleMemberConnectAndWait(
      team,
      members.first,
      tab,
      repo: repo,
      selectMember: false,
      reason: LaunchReason.restore,
    );
    await Future.wait([
      for (final member in members.skip(1))
        // Callers own the final member selection; background members must not
        // stomp it.
        scheduleMemberConnectAndWait(
          team,
          member,
          tab,
          repo: repo,
          selectMember: false,
          reason: LaunchReason.restore,
        ),
    ]);
  }

  Future<void> _connectPersonalSession({
    required String workspaceId,
    CliTool? cliOverride,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _host.sessionRepository;
    if (r == null) {
      _host.failSessionConnect('pending', 'Session repository unavailable.');
      return;
    }
    final workspace = _workspaceById(workspaceId);
    if (workspace == null) {
      _host.failSessionConnect('pending', 'Workspace not found.');
      return;
    }
    if (_tabStore.activeTabsIsEmpty) {
      _host.beginSessionConnect('pending');
      try {
        await _materializer.materializePersonalSession(
          workspace,
          r,
          connectImmediately: true,
          cliOverride: cliOverride,
        );
      } on Object catch (e, st) {
        appLogger.e(
          'connectPersonalSession: materialize failed: $e',
          stackTrace: st,
        );
        _host.failSessionConnect(
          'pending',
          'Failed to create session: $e',
          error: e,
          stackTrace: st,
        );
      }
      return;
    }
    final tab = _activeTab();
    final session = tab?.persistedSession;
    if (tab == null || session == null) {
      _host.failSessionConnect('pending', 'No active personal session tab.');
      return;
    }
    await _coordinator.open(
      SessionOpenRequest(
        session: session,
        workspace: _workspaceById(session.workspaceId),
        repo: r,
        connectImmediately: true,
        waitForCompletion: true,
      ),
    );
  }

  Future<void> _connectExistingSession({
    required AppSession session,
    TeamProfile? team,
    TeamMemberConfig? member,
    Workspace? workspace,
    bool preserveWorkbenchView = false,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _host.sessionRepository;
    if (r == null) {
      _host.failSessionConnect(
        session.sessionId,
        'Session repository unavailable.',
      );
      return;
    }

    final tab = _tabStore.openTabBySessionId(session.sessionId);
    if (tab == null) {
      _host.failSessionConnect(session.sessionId, 'Session tab is not open.');
      return;
    }

    final isPersonal = session.sessionTeam.trim().isEmpty;
    final memberId = isPersonal
        ? session.sessionId
        : (member?.id.trim().isNotEmpty == true
              ? member!.id.trim()
              : tab.selectedMemberId.trim());
    if (memberId.isNotEmpty) {
      _host.assignSelectedMember(tab, memberId);
    }

    // Prefer the freshest in-memory snapshot (launchState / native ids) over a
    // stale tab.persistedSession left at create-time.
    AppSession launchSession = tab.persistedSession ?? session;
    for (final s in _state().sessions) {
      if (s.sessionId == session.sessionId) {
        launchSession = s;
        break;
      }
    }
    tab.persistedSession = launchSession;

    if (_tabStore.openTabBySessionId(session.sessionId) == null) {
      appLogger.w(
        '[session-launch] existing session connect tab not open '
        'session=${session.sessionId} active=${_tabStore.activeWorkspaceId} '
        'tabWorkspace=${tab.workspaceId}',
      );
      _host.failSessionConnect(
        session.sessionId,
        'Session tab is not active in this workspace.',
      );
      return;
    }

    await _coordinator.open(
      SessionOpenRequest(
        session: launchSession,
        workspace: workspace ?? _workspaceById(session.workspaceId),
        team: isPersonal ? null : team,
        member: isPersonal ? null : member,
        repo: r,
        connectImmediately: true,
        preserveWorkbenchView: preserveWorkbenchView,
        waitForCompletion: true,
      ),
    );
  }

  Future<void> _connectTeamSession(
    TeamProfile team, {
    SessionRepository? repo,
  }) async {
    _resetTeamConfigValidationSurface();
    unawaited(_scheduleTeamConfigValidation(team));

    final r = repo ?? _host.sessionRepository;
    if (_tabStore.activeTabsIsEmpty && r == null) {
      _appendLocalTab(team, emitChange: true);
    }

    if (shouldLaunchAllMembers(
      team: team,
      autoLaunchAllMembersOnConnect: _autoLaunchAllMembersOnConnect(),
    )) {
      final keepId = _selectedMemberIdOrDefault(team);
      if (keepId.isEmpty) {
        _failNoMemberSelected(team);
        return;
      }
      await launchAllMembers(team, repo: r);
      if (_membersForTab(_activeTab(), team).any((m) => m.id == keepId)) {
        _host.selectMember(keepId);
      }
      return;
    }

    final member = _resolveConnectMember(team);
    if (member == null) return;
    await openMemberTab(
      team,
      member,
      repo: r,
      scheduleTeamConfigValidation: false,
    );
  }

  Future<void> _restartTeamSession(
    TeamProfile team, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _host.sessionRepository;
    final activeId = _activeTab()?.info.id ?? 'pending';
    _host.beginSessionConnect(activeId);
    // Restart disconnect() nulls onProcessExited without calling it, so sticky
    // waiting would survive until TTL unless seats are cleared here.
    final restartTab = _activeTab();
    if (restartTab != null) {
      _host.clearAgentStatusSession(restartTab.info.id);
    }
    if (shouldLaunchAllMembers(
      team: team,
      autoLaunchAllMembersOnConnect: _autoLaunchAllMembersOnConnect(),
    )) {
      final keepId = _selectedMemberIdOrDefault(team);
      final tab = restartTab ?? _activeTab();
      if (tab != null) {
        tab.membersPendingConnect.clear();
        for (final shell in tab.memberShells.values) {
          shell.disconnect();
        }
        for (final memberId in tab.memberSshSessions.keys.toList()) {
          unawaited(tab.closeMemberRemotePlane(memberId));
        }
        _host.updateTabRunning(tab.info.id);
      }
      await launchAllMembers(team, repo: r);
      if (keepId.isNotEmpty &&
          _membersForTab(_activeTab(), team).any((m) => m.id == keepId)) {
        _host.selectMember(keepId);
      }
      return;
    }
    _disconnectSession();
    await _connectTeamSession(team, repo: r);
  }

  String _selectedMemberIdOrDefault(TeamProfile team) {
    final selected = _activeTab()?.selectedMemberId ?? '';
    if (selected.isNotEmpty) return selected;
    return _tabStore.defaultMemberId(team);
  }

  TeamMemberConfig? _resolveConnectMember(TeamProfile team) {
    final memberId = _selectedMemberIdOrDefault(team);
    final members = _membersForTab(_activeTab(), team);
    if (memberId.isEmpty || members.isEmpty) {
      _failNoMemberSelected(team);
      return null;
    }
    return members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => members.first,
    );
  }

  void _failNoMemberSelected(TeamProfile team) {
    const message = 'No member selected. Choose a team member and try again.';
    final session = _ensureSession(team);
    session?.write('\r\n[$message]\r\n');
    _host.failSessionConnect(_activeTab()?.info.id ?? 'pending', message);
  }
}

/// Whether [request] must wait behind an in-flight connect.
///
/// Only the *target* session's own connect blocks a new one (same-session
/// double-connect, or a member of that session already owned by the member
/// scheduler). Different sessions connect concurrently — their config
/// provisioning writes are session-scoped, so there is no shared-write race.
/// Pre-session materialization (no session pod yet) still serializes.
@visibleForTesting
bool shouldSerializeConnect({
  required SessionConnectRequest request,
  required ChatTabStore tabStore,
  required bool Function(String sessionId) isSessionConnecting,
  required bool isMaterializingInFlight,
}) {
  if (request case ExistingSessionConnect(:final session, :final member)) {
    final memberId = member?.id;
    final tab = tabStore.openTabBySessionId(session.sessionId);
    final memberOwnedElsewhere =
        memberId != null &&
        memberId.isNotEmpty &&
        tab != null &&
        (tab.membersPendingConnect.contains(memberId) ||
            tab.memberShells[memberId]?.isConnecting == true);
    return isSessionConnecting(session.sessionId) || memberOwnedElsewhere;
  }
  return isMaterializingInFlight;
}

/// Whether connecting this team must launch every valid member shell.
///
/// Native teams break when any member is missing (the CLI coordinates the
/// roster itself), so they always launch all members regardless of the user
/// preference. Mixed teams honor [autoLaunchAllMembersOnConnect].
bool shouldLaunchAllMembers({
  required TeamProfile team,
  required bool autoLaunchAllMembersOnConnect,
}) => team.teamMode != TeamMode.mixed || autoLaunchAllMembersOnConnect;
