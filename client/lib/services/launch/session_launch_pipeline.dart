import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_connect_request.dart';
import '../../cubits/chat/model/session_create_request.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../cubits/chat/model/session_persist_params.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/session_repository.dart';
import '../../services/session/session_member_cli_locks.dart';
import '../../services/session/team_session_member_plan.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import 'launch_operation.dart';
import 'launch_outcome.dart';
import 'session_default_materializer.dart';
import 'session_launch_bundle.dart';
import 'session_launch_open_validator.dart';
import 'session_launch_workspace_index.dart';
import 'session_provisional_builder.dart';
import 'session_tab_surface_coordinator.dart';

/// Routes [LaunchOperation] through validate → surface → connect stages.
class SessionLaunchPipeline {
  SessionLaunchPipeline({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    required ChatState Function() state,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required SessionTabSurfaceCoordinator tabSurface,
    required SessionDefaultMaterializer materializer,
    required ScheduleMemberConnectFn scheduleMemberConnect,
    required void Function() disconnectSession,
    required TerminalSession? Function(TeamProfile team) ensureSession,
    required ChatTab Function(TeamProfile team, {required bool emitChange})
    appendLocalTab,
    required ChatTab Function(TeamProfile team, {required bool emitChange})
    ensureActiveSessionTab,
    required void Function() resetTeamConfigValidationSurface,
    required Future<void> Function(TeamProfile team) scheduleTeamConfigValidation,
    required ChatTab? Function() activeTab,
    required bool Function() autoLaunchAllMembersOnConnect,
    required Uuid uuid,
  }) : _host = host,
       _tabStore = tabStore,
       _state = state,
       _workspaceIndex = workspaceIndex,
       _tabSurface = tabSurface,
       _materializer = materializer,
       _scheduleMemberConnect = scheduleMemberConnect,
       _disconnectSession = disconnectSession,
       _ensureSession = ensureSession,
       _appendLocalTab = appendLocalTab,
       _ensureActiveSessionTab = ensureActiveSessionTab,
       _resetTeamConfigValidationSurface = resetTeamConfigValidationSurface,
       _scheduleTeamConfigValidation = scheduleTeamConfigValidation,
       _activeTab = activeTab,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _uuid = uuid;

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final ChatState Function() _state;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final SessionTabSurfaceCoordinator _tabSurface;
  final SessionDefaultMaterializer _materializer;
  final ScheduleMemberConnectFn _scheduleMemberConnect;
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
  final Uuid _uuid;

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex().byId(workspaceId);

  Future<LaunchOutcome> run(LaunchOperation operation) async {
    return switch (operation) {
      OpenSessionOperation(:final request) => _runOpen(request),
      CreateSessionOperation(:final request) => _runCreate(request),
      ConnectWorkspaceOperation(:final request, :final repo) =>
        _runConnect(request, repo: repo),
      RestartWorkspaceOperation(:final request, :final repo) =>
        _runRestart(request, repo: repo),
      OpenMemberTabOperation(
        :final team,
        :final member,
        :final repo,
        :final workspaceCwd,
        :final scheduleTeamConfigValidation,
      ) =>
        _runOpenMemberTab(
          team,
          member,
          repo: repo,
          workspaceCwd: workspaceCwd,
          scheduleTeamConfigValidation: scheduleTeamConfigValidation,
        ),
      LaunchAllMembersOperation(:final team, :final repo, :final workspaceCwd) =>
        _runLaunchAllMembers(team, repo: repo, workspaceCwd: workspaceCwd),
    };
  }

  Future<LaunchOpened> _runOpen(SessionOpenRequest request) async {
    var session = request.session;
    final isPersonal = request.isPersonal;
    appLogger.d(
      '[session-launch] pipeline open start '
      'session=${session.sessionId} personal=$isPersonal '
      'member=${request.member?.id ?? ''} team=${request.team?.id ?? ''} '
      'connectImmediately=${request.connectImmediately}',
    );

    final blocked = validateSessionOpenRequest(
      request: request,
      session: session,
      workspaceById: _workspaceById,
    );
    if (blocked != null) return LaunchOpened(blocked);

    final existing = _tabStore.openTabBySessionId(session.sessionId);
    if (existing != null) {
      final status = _tabSurface.surfaceExistingTab(
        request: request.withSession(session),
        existing: existing,
      );
      return LaunchOpened(status);
    }
    final status = _tabSurface.surfaceNewTab(
      request: request.withSession(session),
      session: session,
    );
    return LaunchOpened(status);
  }

  Future<LaunchOpened> _runCreate(SessionCreateRequest request) async {
    appLogger.d(
      '[session-launch] pipeline create start '
      'workspace=${request.workspace.workspaceId} personal=${request.isPersonal}',
    );

    if (!request.isPersonal &&
        (request.team == null || request.member == null)) {
      return LaunchOpened(SessionOpenStatus.missingTeamMember);
    }

    final sessionTeamId = request.isPersonal
        ? ''
        : (request.team?.id ?? '').trim();
    if (!request.isPersonal) {
      final team = request.team!;
      final workspace = request.workspace;
      if (workspaceNeedsMixedPlacementInit(
        folders: workspace.folders,
        teamId: team.id,
        initializedByTeam: workspace.memberPlacementInitializedByTeam,
      )) {
        return LaunchOpened(SessionOpenStatus.blockedMixedMemberTargets);
      }
      final valid = team.members.where((m) => m.isValid).toList();
      final targets = rememberedMemberTargets(
        workspace.memberTargetsByTeam,
        sessionTeamId,
      );
      final mustValidateLead =
          targets.isNotEmpty ||
          workspaceTopologyOf(workspace.folders) == WorkspaceTopology.mixed;
      if (mustValidateLead &&
          !leadPlacementValid(
            folders: workspace.folders,
            members: valid,
            targets: targets,
          )) {
        return LaunchOpened(SessionOpenStatus.blockedMixedMemberTargets);
      }
    }

    final fixedId = request.fixedSessionId?.trim();
    final sessionId = fixedId != null && fixedId.isNotEmpty
        ? fixedId
        : _uuid.v4();
    var provisional = buildProvisionalSession(
      sessionId: sessionId,
      workspace: request.workspace,
      isPersonal: request.isPersonal,
      cli: request.cli,
      simpleIdentity: request.simpleIdentity,
      workingDirectory: request.workingDirectory,
      sessionTeamId: sessionTeamId,
      expertKey: request.expertKey,
      home: _host.lifecycle.currentHome,
    );

    // Team sessions need provisional member bindings so history loading (which
    // fires immediately after the UI mounts) can resolve session.requireBinding
    // before persistence completes asynchronously.
    if (!request.isPersonal && request.team != null) {
      try {
        final memberClis = resolveSessionMemberCliLocks(
          team: request.team!,
          rosterMembers: request.team!.members,
          globalPresets: _host.lifecycle.globalPresets,
        );
        final plan = buildTeamSessionMemberPlan(
          workspace: request.workspace,
          teamId: sessionTeamId,
          rosterMembers: request.team!.members,
          memberClis: memberClis,
        );
        provisional = provisional.copyWith(
          members: plan.members,
          memberTargets: plan.memberTargets,
        );
      } on StateError catch (e) {
        final msg = e.message;
        if (msg == 'lead_placement_invalid' ||
            msg == 'mixed_workspace_member_placement_uninitialized') {
          return LaunchOpened(SessionOpenStatus.blockedMixedMemberTargets);
        }
        rethrow;
      }
    }
    _host.appendSessionSnapshot(provisional);

    final persistParams = SessionPersistParams(
      sessionTeamId: sessionTeamId,
      rosterMembers: request.isPersonal
          ? const []
          : (request.team?.members ?? const []),
      cli: request.cli,
      simpleIdentity: request.simpleIdentity,
      workingDirectory: request.workingDirectory,
      expertKey: request.expertKey,
      continueOverrides: request.continueOverrides,
    );

    final status = _tabSurface.surfaceNewTab(
      request: SessionOpenRequest(
        session: provisional,
        workspace: request.workspace,
        team: request.team,
        member: request.member,
        repo: request.repo,
        emptyDisplayTitleFallback: request.emptyDisplayTitleFallback,
        preserveWorkbenchView: request.preserveWorkbenchView,
        persistParams: persistParams,
      ),
      session: provisional,
    );
    return LaunchOpened(status);
  }

  Future<LaunchOutcome> _runConnect(
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
      return LaunchSkipped();
    }

    switch (request) {
      case TeamSessionConnect(:final team):
        await _connectTeamSession(team, repo: repo);
      case PersonalSessionConnect(
        :final workspaceId,
        :final cliOverride,
      ):
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
    return LaunchCompleted();
  }

  Future<LaunchOutcome> _runRestart(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    switch (request) {
      case TeamSessionConnect(:final team):
        await _restartTeamSession(team, repo: repo);
      case PersonalSessionConnect():
        _disconnectSession();
        await _runConnect(request, repo: repo);
      case ExistingSessionConnect():
        _disconnectSession();
        await _runConnect(request, repo: repo);
    }
    return LaunchCompleted();
  }

  Future<LaunchCompleted> _runOpenMemberTab(
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
        if (_host.isClosed) return LaunchCompleted();
        if (team.teamMode == TeamMode.mixed) {
          final tab = _activeTab();
          if (tab != null) {
            _scheduleMemberConnect(team, member, tab);
          }
        }
      } on Object catch (e, st) {
        appLogger.e(
          'openMemberTab: default session failed: $e',
          stackTrace: st,
        );
        _host.failSessionConnect('pending', 'Failed to create session: $e');
      }
      return LaunchCompleted();
    }
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    _scheduleMemberConnect(team, member, tab);
    return LaunchCompleted();
  }

  Future<LaunchCompleted> _runLaunchAllMembers(
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) async {
    final r = repo ?? _host.sessionRepository;
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) return LaunchCompleted();

    if (_tabStore.activeTabsIsEmpty && r != null) {
      try {
        await _materializer.materializeTeamSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: validMembers.first,
          workspaceCwd: workspaceCwd,
        );
        if (_host.isClosed) return LaunchCompleted();
        if (team.teamMode == TeamMode.mixed) {
          final tab = _activeTab();
          if (tab != null) {
            for (final member in validMembers) {
              _scheduleMemberConnect(team, member, tab);
            }
          }
        }
      } on Object catch (e, st) {
        appLogger.e(
          'launchAllMembers: default session failed: $e',
          stackTrace: st,
        );
      }
      return LaunchCompleted();
    }

    final tab = _ensureActiveSessionTab(team, emitChange: true);
    for (final member in validMembers) {
      _scheduleMemberConnect(team, member, tab);
    }
    return LaunchCompleted();
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
        _host.failSessionConnect('pending', 'Failed to create session: $e');
      }
      return;
    }
    final tab = _activeTab();
    final session = tab?.persistedSession;
    if (tab == null || session == null) {
      _host.failSessionConnect('pending', 'No active personal session tab.');
      return;
    }
    await _runOpen(
      SessionOpenRequest(
        session: session,
        workspace: _workspaceById(session.workspaceId),
        repo: r,
        connectImmediately: true,
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
      _host.failSessionConnect(session.sessionId, 'Session repository unavailable.');
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

    await _runOpen(
      SessionOpenRequest(
        session: launchSession,
        workspace: workspace ?? _workspaceById(session.workspaceId),
        team: isPersonal ? null : team,
        member: isPersonal ? null : member,
        repo: r,
        connectImmediately: true,
        preserveWorkbenchView: preserveWorkbenchView,
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

    if (_autoLaunchAllMembersOnConnect()) {
      final keepId = _selectedMemberIdOrDefault(team);
      if (keepId.isEmpty) {
        _failNoMemberSelected(team);
        return;
      }
      await _runLaunchAllMembers(team, repo: r);
      if (team.members.any((m) => m.id == keepId)) {
        _host.selectMember(keepId);
      }
      return;
    }

    final member = _resolveConnectMember(team);
    if (member == null) return;
    await _runOpenMemberTab(
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
    if (_autoLaunchAllMembersOnConnect()) {
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
      await _runLaunchAllMembers(team, repo: r);
      if (keepId.isNotEmpty && team.members.any((m) => m.id == keepId)) {
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
    var memberId = _selectedMemberIdOrDefault(team);
    if (memberId.isEmpty || team.members.isEmpty) {
      _failNoMemberSelected(team);
      return null;
    }
    return team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => team.members.first,
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
