import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/workspace_folder.dart';
import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/session_repository.dart';
import '../../services/launch/personal_launch_context_resolver.dart';
import '../../services/launch/session_launch_readiness.dart';
import '../../services/launch/session_provisional_builder.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/launch/session_default_materializer.dart';
import '../../services/launch/session_launch_workspace_index.dart';
import '../../services/launch/session_member_connect_scheduler.dart';
import '../../services/launch/session_ssh_profile_reconnect.dart';
import '../../services/launch/session_lifecycle_connect_coordinator.dart';
import '../../services/launch/session_prompt_metadata_sync.dart';
import '../../services/launch/session_shell_connector.dart';
import '../../services/launch/session_tab_connect_prep.dart';
import '../../services/launch/session_tab_surface_coordinator.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/team/team_config_launch_validator.dart';
import 'session_launch_host.dart';

export 'session_launch_host.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logger.dart';
import '../../utils/team_member_naming.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'model/session_create_request.dart';
import 'model/session_open_request.dart';
import 'model/session_open_status.dart';
import 'model/session_persist_params.dart';
import 'model/session_connect_request.dart';
import 'member_connector.dart';

/// Owns the entire connect / launch flow: opening (or restoring) session tabs,
/// scheduling and wiring per-member shells, the team-bus materialize path, and
/// the connect/restart/disconnect user commands. ChatCubit delegates here and
/// keeps only its data/tab facades + getters.
class SessionLaunchService
    implements MemberConnector, SessionShellConnectorDelegate {
  SessionLaunchService(this._h)
    : _personalContext = PersonalLaunchContextResolver(_h.lifecycle);

  final SessionLaunchHost _h;
  final PersonalLaunchContextResolver _personalContext;
  late final SessionShellConnector _shellConnector = SessionShellConnector(
    _h,
    this,
  );
  late final SessionDefaultMaterializer _defaultMaterializer =
      SessionDefaultMaterializer(
        host: _h,
        personalContext: _personalContext,
        openSession: requestOpenSession,
        workspaceIndex: () => _workspaceIndex,
        isTabsEmpty: () => _tabStore.isEmpty,
        activeBucketKey: () => _tabStore.activeWorkspaceId,
      );
  late final SessionMemberConnectScheduler _memberConnectScheduler =
      SessionMemberConnectScheduler(
        host: _h,
        shellConnector: _shellConnector,
        shellForLaunch: _shellForLaunch,
        sessionForMemberConnect: _sessionForMemberConnect,
        tabStore: _tabStore,
        state: () => _h.state,
      );
  late final SessionSshProfileReconnect _sshReconnect = SessionSshProfileReconnect(
    host: _h,
    shellConnector: _shellConnector,
    personalContext: _personalContext,
    launchContextFor: launchContextFor,
    scheduleMemberConnect: _memberConnectScheduler.schedule,
    workspaceIndex: () => _workspaceIndex,
    allTabs: () => _tabStore.allTabs,
  );
  late final SessionLifecycleConnectCoordinator _lifecycleCoordinator =
      SessionLifecycleConnectCoordinator(
        host: _h,
        launchContextFor: launchContextFor,
        launchWorkTarget: _launchWorkTarget,
        scheduleMemberConnect: _memberConnectScheduler.schedule,
        tabIndexOfSession: _tabStore.indexOfSession,
      );
  late final SessionPromptMetadataSync _promptMetadata = SessionPromptMetadataSync(
    host: _h,
    state: () => _h.state,
  );
  late final SessionTabSurfaceCoordinator _tabSurface =
      SessionTabSurfaceCoordinator(
        host: _h,
        tabStore: _tabStore,
        state: () => _h.state,
        workspaceById: _workspaceById,
        personalPresetIdOverride: _personalPresetIdOverride,
        shouldAutoConnect: _shouldAutoConnect,
        prepareNewTabConnect: _prepareNewTabConnect,
        prepareExistingTabConnect: _prepareExistingTabConnect,
        prepareDeferredTeamTab: _prepareDeferredTeamTab,
      );
  static const _uuid = Uuid();
  final _teamConfigValidator = TeamConfigLaunchValidator();

  SessionTabConnectPrepCallbacks get _tabConnectCallbacks =>
      (
        persistSessionIfNeeded: _persistSessionIfNeeded,
        ensureTeamSessionReady: _ensureTeamSessionReady,
        onMixedMemberTargetsIncomplete: _onMixedMemberTargetsIncomplete,
        resolveLaunchMembers: _resolveLaunchMembers,
        installTeamRuntimeIfNeeded: _installTeamRuntimeIfNeeded,
        updateSelectedMember: _updateSelectedMember,
        shellForLaunch: _shellForLaunch,
        launchStillValid: _launchStillValid,
      );

  ChatState get _state => _h.state;
  ChatTabStore get _tabStore => _h.tabStore;
  ChatTab? get _activeTab => _h.activeTab;

  SessionLaunchWorkspaceIndex get _workspaceIndex =>
      SessionLaunchWorkspaceIndex(
        workspaces: _state.workspaces,
        sessions: _state.sessions,
      );

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex.byId(workspaceId);

  void _updateSelectedMember(String memberId) {
    final tabMemberId = memberId;
    if (_state.selectedMemberId != tabMemberId) {
      _h.applyState(_state.copyWith(selectedMemberId: tabMemberId));
    }
  }

  void _onMixedMemberTargetsIncomplete({
    required ChatTab tab,
    required AppSession launchSession,
    required SessionOpenRequest request,
  }) {
    if (request.persistParams != null) {
      _rollbackStagedLaunch(
        tab: tab,
        sessionId: launchSession.sessionId,
        request: request,
        message: 'mixed_workspace_member_targets_incomplete',
      );
    } else {
      _h.failSessionConnect(
        launchSession.sessionId,
        'mixed_workspace_member_targets_incomplete',
      );
    }
  }

  Future<void> _handleTabConnectPrepFailure({
    required Object error,
    required StackTrace stackTrace,
    required String logLabel,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
    required int generation,
  }) async {
    appLogger.e(
      '[session-launch] $logLabel session=${session.sessionId}: $error',
      error: error,
      stackTrace: stackTrace,
    );
    if (_launchStillValid(tab, generation)) {
      if (request.persistParams != null) {
        _rollbackStagedLaunch(
          tab: tab,
          sessionId: session.sessionId,
          request: request,
          message: error.toString(),
        );
      } else {
        _h.failSessionConnect(session.sessionId, error.toString());
      }
    }
  }

  Future<SessionOpenStatus> requestOpenSession(
    SessionOpenRequest request,
  ) async {
    var session = request.session;
    final isPersonal = request.isPersonal;
    appLogger.d(
      '[session-launch] requestOpenSession start '
      'session=${session.sessionId} personal=$isPersonal '
      'member=${request.member?.id ?? ''} team=${request.team?.id ?? ''} '
      'connectImmediately=${request.connectImmediately}',
    );

    if (isPersonal) {
      final workspace =
          request.workspace ?? _workspaceById(session.workspaceId);
      if (workspace == null) return SessionOpenStatus.missingWorkspace;
    } else if (request.team == null || request.member == null) {
      return SessionOpenStatus.missingTeamMember;
    } else {
      final workspace =
          request.workspace ?? _workspaceById(session.workspaceId);
      final team = request.team!;
      if (workspace != null &&
          workspaceTopologyRequiresMemberAssignment(workspace.folders) &&
          !memberTargetsComplete(
            workspaceFolders: workspace.folders,
            members: team.members.where((m) => m.isValid).toList(),
            targets: session.memberTargets,
          )) {
        return SessionOpenStatus.blockedMixedMemberTargets;
      }
    }

    final existingIdx = _tabStore.indexOfSession(session.sessionId);
    if (existingIdx != -1) {
      return _tabSurface.surfaceExistingTab(
        request: request.withSession(session),
        existingIdx: existingIdx,
      );
    }
    return _tabSurface.surfaceNewTab(
      request: request.withSession(session),
      session: session,
    );
  }

  /// Stages a new conversation tab immediately, then persists and connects async.
  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) async {
    appLogger.d(
      '[session-launch] requestCreateAndOpenSession start '
      'workspace=${request.workspace.workspaceId} personal=${request.isPersonal}',
    );

    if (!request.isPersonal &&
        (request.team == null || request.member == null)) {
      return SessionOpenStatus.missingTeamMember;
    }

    final sessionTeamId = request.isPersonal
        ? ''
        : (request.team?.id ?? '').trim();
    if (!request.isPersonal &&
        workspaceTopologyRequiresMemberAssignment(request.workspace.folders)) {
      final team = request.team!;
      final valid = team.members.where((m) => m.isValid).toList();
      final targets = rememberedMemberTargets(
        request.workspace.memberTargetsByTeam,
        sessionTeamId,
      );
      if (!memberTargetsComplete(
        workspaceFolders: request.workspace.folders,
        members: valid,
        targets: targets,
      )) {
        return SessionOpenStatus.blockedMixedMemberTargets;
      }
    }

    final fixedId = request.fixedSessionId?.trim();
    final sessionId = fixedId != null && fixedId.isNotEmpty
        ? fixedId
        : _uuid.v4();
    final provisional = buildProvisionalSession(
      sessionId: sessionId,
      workspace: request.workspace,
      isPersonal: request.isPersonal,
      personalIdentityId: request.personalIdentityId,
      cli: request.cli,
      workingDirectory: request.workingDirectory,
      sessionTeamId: sessionTeamId,
    );
    _h.appendSessionSnapshot(provisional);

    final persistParams = SessionPersistParams(
      sessionTeamId: sessionTeamId,
      personalIdentityId: request.personalIdentityId,
      rosterMembers: request.isPersonal
          ? const []
          : (request.team?.members ?? const []),
      cli: request.cli,
      personalPresetId: request.personalPresetId,
      workingDirectory: request.workingDirectory,
    );

    return _tabSurface.surfaceNewTab(
      request: SessionOpenRequest(
        session: provisional,
        workspace: request.workspace,
        team: request.team,
        member: request.member,
        repo: request.repo,
        emptyDisplayTitleFallback: request.emptyDisplayTitleFallback,
        persistParams: persistParams,
        personalPresetId: request.personalPresetId,
      ),
      session: provisional,
    );
  }

  Future<AppSession> _persistSessionIfNeeded({
    required SessionOpenRequest request,
    required AppSession session,
    required ChatTab tab,
  }) async {
    final params = request.persistParams;
    if (params == null) return session;

    final repo = request.repo ?? _h.sessionRepository;
    if (repo == null) {
      throw StateError('Session repository unavailable');
    }

    final persisted = await repo.createSession(
      session.workspaceId,
      sessionTeam: params.sessionTeamId,
      personalIdentityId: params.personalIdentityId,
      rosterMembers: params.rosterMembers,
      cli: params.cli,
      workingDirectory: params.workingDirectory,
      fixedSessionId: session.sessionId,
    );
    tab.persistedSession = persisted;
    _h.replaceSessionSnapshot(persisted);
    return persisted;
  }

  void _rollbackStagedLaunch({
    required ChatTab tab,
    required String sessionId,
    required SessionOpenRequest request,
    required String message,
  }) {
    _h.failSessionConnect(sessionId, message);
    if (request.persistParams == null) return;
    _h.closeSessionTab(sessionId);
    _h.removeSessionSnapshot(sessionId);
  }


  bool _shouldAutoConnect(SessionOpenRequest request) {
    if (!request.connectImmediately) return false;
    if (request.isPersonal) return true;
    final team = request.team!;
    if (team.teamMode != TeamMode.mixed) return true;
    return TeamMemberNaming.isTeamLead(request.member!);
  }

  bool _launchStillValid(ChatTab tab, int generation) {
    if (_h.isClosed) return false;
    if (_tabStore.indexOfSession(tab.info.id) == -1) return false;
    return tab.launchGeneration == generation;
  }

  Future<AppSession?> _ensureTeamSessionReady({
    required SessionOpenRequest request,
    required AppSession session,
    required Workspace? workspace,
  }) async {
    if (request.isPersonal) return session;
    final team = request.team;
    final repo = request.repo ?? _h.sessionRepository;
    if (team == null || workspace == null || repo == null) return session;
    return ensureSessionLaunchReady(
      workspace: workspace,
      session: session,
      team: team,
      repository: repo,
    );
  }

  Future<void> _prepareNewTabConnect({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
    required Workspace? workspace,
    required bool connect,
  }) async {
    try {
      final prep = await runSessionTabConnectPrep(
        callbacks: _tabConnectCallbacks,
        generation: generation,
        tab: tab,
        session: session,
        request: request,
        workspace: workspace,
        installTeamRuntime: true,
      );
      if (prep == null) return;

      if (!connect) {
        _h.updateTabRunning(prep.launchSession.sessionId);
        return;
      }
      final launched =
          prep.launchSession.launchState == AppSessionLaunchState.started;
      _scheduleShellConnect(
        generation: generation,
        tab: tab,
        session: prep.launchSession,
        shell: prep.shell,
        request: request,
        launched: launched,
        workspace: workspace,
        personal: prep.resolved.personalIdentity,
        team: prep.resolved.team,
        member: request.isPersonal ? null : prep.resolved.member,
      );
    } on Object catch (e, st) {
      await _handleTabConnectPrepFailure(
        error: e,
        stackTrace: st,
        logLabel: 'prepare new tab failed',
        tab: tab,
        session: session,
        request: request,
        generation: generation,
      );
    }
  }

  Future<void> _prepareDeferredTeamTab({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
  }) async {
    final team = request.team;
    if (team == null || request.member == null) return;
    try {
      await _installTeamRuntimeIfNeeded(
        tab: tab,
        session: session,
        team: team,
        generation: generation,
      );
      if (!_launchStillValid(tab, generation)) return;
      tab.selectedMemberId = request.member!.id;
      _h.applyState(_state.copyWith(selectedMemberId: request.member!.id));
      _h.updateTabRunning(session.sessionId);
    } on Object catch (e, st) {
      appLogger.e(
        '[session-launch] deferred team tab prep failed session=${session.sessionId}: $e',
        error: e,
        stackTrace: st,
      );
      if (_launchStillValid(tab, generation)) {
        _h.setLaunchError(session.sessionId, e.toString());
      }
    }
  }

  Future<void> _prepareExistingTabConnect({
    required int generation,
    required ChatTab tab,
    required SessionOpenRequest request,
    required bool connect,
  }) async {
    var session = request.session;
    final persisted = tab.persistedSession;
    if (!request.isPersonal &&
        session.cliTeamName.isEmpty &&
        persisted != null &&
        persisted.cliTeamName.isNotEmpty) {
      session = persisted;
    }
    final workspace = request.workspace ?? _workspaceById(session.workspaceId);
    if (request.isPersonal && workspace == null) return;

    try {
      final prep = await runSessionTabConnectPrep(
        callbacks: _tabConnectCallbacks,
        generation: generation,
        tab: tab,
        session: session,
        request: request,
        workspace: workspace,
        installTeamRuntime: false,
      );
      if (prep == null) return;

      final launchSession = prep.launchSession;
      final shell = prep.shell;

      if (shell.isRunning || shell.isConnecting) {
        _h.updateTabRunning(tab.info.id);
        if (_state.sessionConnectingId == launchSession.sessionId) {
          _h.finishSessionConnect(launchSession.sessionId);
        }
        return;
      }
      if (tab.membersPendingConnect.contains(prep.resolved.member.id)) return;

      if (!connect) {
        _h.updateTabRunning(tab.info.id);
        return;
      }

      if (_shouldAutoConnect(request) &&
          _state.sessionConnectingId != launchSession.sessionId) {
        _h.beginSessionConnect(launchSession.sessionId);
      }

      tab.membersPendingConnect.add(prep.resolved.member.id);
      final launched =
          launchSession.launchState == AppSessionLaunchState.started;
      _scheduleShellConnect(
        generation: generation,
        tab: tab,
        session: launchSession,
        shell: shell,
        request: request,
        launched: launched,
        workspace: workspace,
        personal: prep.resolved.personalIdentity,
        team: prep.resolved.team,
        member: request.isPersonal ? null : prep.resolved.member,
        onFinally: () => tab.membersPendingConnect.remove(prep.resolved.member.id),
      );
    } on Object catch (e, st) {
      await _handleTabConnectPrepFailure(
        error: e,
        stackTrace: st,
        logLabel: 'prepare existing tab failed',
        tab: tab,
        session: session,
        request: request,
        generation: generation,
      );
    }
  }

  Future<ResolvedLaunchMembers> _resolveLaunchMembers({
    required AppSession session,
    required SessionOpenRequest request,
    Workspace? workspace,
  }) async {
    if (request.isPersonal) {
      final resolvedWorkspace =
          workspace ?? _workspaceById(session.workspaceId);
      if (resolvedWorkspace == null) {
        throw StateError('Personal session requires workspace');
      }
      final personalCtx = await _personalContext.resolve(
        session: session,
        workspace: resolvedWorkspace,
        presetIdOverride: _personalPresetIdOverride(request),
      );
      final presetOverride = _personalPresetIdOverride(request);
      final cli = presetOverride.isNotEmpty
          ? (personalCtx.personalPreset?.cli ?? CliTool.claude)
          : (session.cli ??
                personalCtx.personalPreset?.cli ??
                CliTool.claude);
      return (
        team: null,
        member: personalCtx.personalMember,
        cli: cli,
        personalIdentity: personalCtx.personalIdentity,
      );
    }
    final team = request.team!;
    final member = request.member!;
    return (
      team: team,
      member: member,
      cli: memberLaunchCli(
        team: team,
        member: member,
        globalPresets: _h.lifecycle.globalPresets,
      ),
      personalIdentity: null,
    );
  }

  String _personalPresetIdOverride(SessionOpenRequest request) {
    final direct = request.personalPresetId?.trim() ?? '';
    if (direct.isNotEmpty) return direct;
    return request.persistParams?.personalPresetId?.trim() ?? '';
  }

  Future<void> _installTeamRuntimeIfNeeded({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile? team,
    required int generation,
  }) async {
    if (team == null) return;
    _h.activeTeam = team;
    _h.pushPresenceTarget();
    if (team.teamMode != TeamMode.mixed) return;
    appLogger.d(
      '[session-launch] installing team bus '
      'session=${session.sessionId} team=${team.id}',
    );
    await _h.teamBus.installBusForTab(tab, team, session);
    if (!_launchStillValid(tab, generation)) return;
  }

  void _scheduleShellConnect({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    required SessionOpenRequest request,
    required bool launched,
    required Workspace? workspace,
    required PersonalProfile? personal,
    required TeamProfile? team,
    required TeamMemberConfig? member,
    VoidCallback? onFinally,
  }) {
    _h.postFrameScheduler(() async {
      if (!_launchStillValid(tab, generation)) {
        _shellConnector.abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'launch_generation_stale',
          remoteMemberKey: member?.id,
        );
        return;
      }
      try {
        final result = await _shellConnector.connect(
          tab: tab,
          session: session,
          shell: shell,
          repo: request.repo,
          launched: launched,
          team: team,
          member: member,
          workspace: workspace,
          personal: personal,
        );
        switch (result) {
          case ConnectShellResult.attached:
            if (!request.isPersonal &&
                team != null &&
                member != null &&
                _h.autoLaunchAllMembersOnConnect?.call() == true) {
              _launchRemainingMembersForTab(team, member.id, tab);
            }
            _h.updateTabRunning(tab.info.id);
          case ConnectShellResult.deferred:
            break;
          case ConnectShellResult.failed:
          case ConnectShellResult.aborted:
            break;
        }
      } on Object catch (e, st) {
        appLogger.e(
          '[session-launch] connect failed for ${tab.info.id}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to resume session: $e';
        shell.write('\r\n[$message]\r\n');
        if (member != null) {
          unawaited(tab.closeMemberRemotePlane(member.id));
        }
        if (_launchStillValid(tab, generation)) {
          _h.failSessionConnect(tab.info.id, message);
        }
      } finally {
        onFinally?.call();
      }
    });
  }

  TeamConfigValidation? _lastSurfacedTeamConfigValidation;

  void resetTeamConfigValidationSurface() {
    _lastSurfacedTeamConfigValidation = null;
  }

  /// Warns (via dialog) when team provider/model config is incomplete. Launch
  /// is never blocked. Call once per user connect action — not per tab open.
  Future<void> scheduleTeamConfigValidation(TeamProfile team) async {
    await _emitTeamConfigValidation(team);
  }

  Future<void> _emitTeamConfigValidation(TeamProfile team) async {
    if (_h.isClosed) return;
    final validation = await _teamConfigValidator.validate(
      team,
      globalPresets: _h.lifecycle.globalPresets,
    );
    if (_h.isClosed || !validation.hasIssues) return;
    if (_lastSurfacedTeamConfigValidation == validation) return;
    _lastSurfacedTeamConfigValidation = validation;
    _h.emitTeamConfigValidation(validation);
  }

  void _launchRemainingMembersForTab(
    TeamProfile team,
    String keepSelectedMemberId,
    ChatTab tab,
  ) {
    final instances = runtimeRosterMembers(team).where((m) => m.isValid);
    for (final candidate in instances) {
      if (candidate.id == keepSelectedMemberId) continue;
      _memberConnectScheduler.schedule(team, candidate, tab);
    }
    if (instances.any((m) => m.id == keepSelectedMemberId)) {
      _h.selectMember(keepSelectedMemberId);
    }
  }

  Future<void> _materializeDefaultWorkspaceSession(
    TeamProfile team,
    SessionRepository repo, {
    required bool connectImmediately,
    required TeamMemberConfig memberForInitialShell,
    String? workspaceCwd,
  }) =>
      _defaultMaterializer.materializeTeamSession(
        team,
        repo,
        connectImmediately: connectImmediately,
        memberForInitialShell: memberForInitialShell,
        workspaceCwd: workspaceCwd,
      );

  Future<void> _materializeDefaultPersonalWorkspaceSession(
    Workspace workspace,
    SessionRepository repo, {
    required bool connectImmediately,
    String personalIdentityId = '',
    CliTool? cliOverride,
  }) =>
      _defaultMaterializer.materializePersonalSession(
        workspace,
        repo,
        connectImmediately: connectImmediately,
        personalIdentityId: personalIdentityId,
        cliOverride: cliOverride,
      );

  @override
  WorkspaceLaunchContext launchContextFor(AppSession session) =>
      WorkspaceLaunchContext(
        session: session,
        workspace:
            _workspaceById(session.workspaceId) ??
            Workspace(
              workspaceId: session.workspaceId,
              folders: session.folders,
              createdAt: 0,
            ),
      );

  RuntimeTarget _launchWorkTarget(AppSession session, {String? memberId}) => _h
      .lifecycle
      .launchWorkTarget(launchContextFor(session), memberId: memberId);

  @override
  void cancelLifecycleConnectRetry(String sessionId, String memberId) =>
      _lifecycleCoordinator.cancelRetry(sessionId, memberId);

  @override
  Future<ConnectShellResult?> lifecycleGateBeforeAttach({
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required ChatTab tab,
    String? remoteMemberKeyForRollback,
  }) =>
      _lifecycleCoordinator.gateBeforeAttach(
        team: team,
        member: member,
        session: session,
        tab: tab,
        remoteMemberKeyForRollback: remoteMemberKeyForRollback,
      );

  /// Compose-landing direct PTY inject waits past lifecycle gate, not only boot frame.
  Future<bool> isMemberDirectPtyLifecycleReady(
    String sessionId,
    String memberId,
  ) async {
    final tab = _tabStore.bySessionId(sessionId);
    if (tab == null) return false;
    final session = tab.persistedSession;
    if (session == null || session.sessionTeam.trim().isEmpty) return true;

    final team = await _h.teamProfileById(session.sessionTeam);
    if (team == null) return false;

    final member = team.members.where((m) => m.id == memberId).firstOrNull;
    if (member == null || !member.isValid) return false;

    return _lifecycleCoordinator.isDirectPtyInputReady(
      tab: tab,
      session: session,
      team: team,
      member: member,
    );
  }

  /// Ensures [tab] holds a [TerminalSession] whose transport matches [session]'s
  /// launch target (local PTY vs SSH).
  TerminalSession _shellForLaunch({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required AppSession session,
    String? rosterMemberId,
  }) {
    final workTarget = _launchWorkTarget(session, memberId: rosterMemberId);
    final needsRemoteLaunch = workTarget.kind == RuntimeKind.ssh;
    final existing = tab.memberShells[shellKey];
    if (existing != null &&
        !existing.isRunning &&
        !existing.isConnecting &&
        needsRemoteLaunch != existing.usesRemoteTransport) {
      existing.disconnect();
      tab.memberShells.remove(shellKey);
    }
    return tab.memberShells.putIfAbsent(
      shellKey,
      () => _h.shellFactory.newSession(cli, workTarget: workTarget),
    );
  }

  Future<void> openMemberTab(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
    bool scheduleTeamConfigValidation = true,
  }) async {
    if (scheduleTeamConfigValidation) {
      unawaited(this.scheduleTeamConfigValidation(team));
    }
    final r = repo ?? _h.sessionRepository;
    if (_tabStore.isEmpty && r != null) {
      _h.beginSessionConnect('pending');
      try {
        await _materializeDefaultWorkspaceSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: member,
          workspaceCwd: workspaceCwd,
        );
        if (_h.isClosed) return;
        if (team.teamMode == TeamMode.mixed) {
          final tab = _activeTab;
          if (tab != null) {
            _memberConnectScheduler.schedule(team, member, tab);
          }
        }
      } on Object catch (e, st) {
        appLogger.e(
          'openMemberTab: default session failed: $e',
          stackTrace: st,
        );
        _h.failSessionConnect('pending', 'Failed to create session: $e');
      }
      return;
    }
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    _memberConnectScheduler.schedule(team, member, tab);
  }

  AppSession? _sessionForMemberConnect(ChatTab tab, TeamProfile team) {
    final cached = _tabStore.sessionForTab(tab, _state.sessions);
    if (cached != null) return cached;
    if (!tab.info.id.startsWith('local-')) return null;
    final launch = _tabStore.workingDirectoryAndAddDirsForTab(
      tab,
      _state.sessions,
      workspaces: _state.workspaces,
    );
    final session =
        tab.persistedSession ??
        AppSession(
          sessionId: tab.info.id,
          workspaceId: '',
          folders: [
            if (launch.$1.isNotEmpty) WorkspaceFolder(path: launch.$1),
            for (final p in launch.$2)
              if (p.isNotEmpty) WorkspaceFolder(path: p),
          ],
          sessionTeam: team.id,
          cliTeamName: tab.effectiveCliTeamName,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
    tab.persistedSession = session;
    return session;
  }

  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab,
  ) => _memberConnectScheduler.schedule(team, member, tab);

  /// True when another launch path already owns PTY connect for [memberId].
  bool isMemberConnectOwnedElsewhere(String sessionId, String memberId) {
    if (_state.sessionConnectingId == sessionId) return true;
    final tab = _tabStore.bySessionId(sessionId);
    if (tab == null) return false;
    if (tab.membersPendingConnect.contains(memberId)) return true;
    final shell = tab.memberShells[memberId];
    return shell?.isConnecting ?? false;
  }


  Future<void> launchAllMembers(
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) async {
    final r = repo ?? _h.sessionRepository;
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) return;
    if (_tabStore.isEmpty && r != null) {
      try {
        await _materializeDefaultWorkspaceSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: validMembers.first,
          workspaceCwd: workspaceCwd,
        );
        if (_h.isClosed) return;
        if (team.teamMode == TeamMode.mixed) {
          final tab = _activeTab;
          if (tab != null) {
            for (final member in validMembers) {
              _memberConnectScheduler.schedule(team, member, tab);
            }
          }
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
    for (final member in validMembers) {
      _memberConnectScheduler.schedule(team, member, tab);
    }
  }

  TerminalSession? ensureSession(TeamProfile team) {
    var tab = _activeTab;
    if (tab == null && _h.sessionRepository == null) {
      tab = _appendLocalTab(team, emitChange: false);
    }
    if (tab == null) return null;
    if (tab.selectedMemberId.isEmpty) {
      tab.selectedMemberId = _tabStore.defaultMemberId(team);
    }
    if (tab.selectedMemberId.isNotEmpty) {
      final memberId = tab.selectedMemberId;
      return tab.memberShells.putIfAbsent(
        memberId,
        () => _h.shellFactory.newSession(
          _h.shellFactory.cliForMember(
            team,
            memberId,
            globalPresets: _h.lifecycle.globalPresets,
          ),
        ),
      );
    }
    return tab.resumeSession ??= _h.shellFactory.newSession(team.cli);
  }

  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    if (_state.isActiveSessionConnecting) return;

    switch (request) {
      case TeamSessionConnect(:final team):
        await _connectTeamSession(team, repo: repo);
      case PersonalSessionConnect(
        :final workspaceId,
        :final personalIdentityId,
        :final cliOverride,
      ):
        await _connectPersonalSession(
          workspaceId: workspaceId,
          personalIdentityId: personalIdentityId,
          cliOverride: cliOverride,
          repo: repo,
        );
    }
  }

  Future<void> _connectPersonalSession({
    required String workspaceId,
    String personalIdentityId = '',
    CliTool? cliOverride,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _h.sessionRepository;
    if (r == null) {
      _h.failSessionConnect('pending', 'Session repository unavailable.');
      return;
    }
    final workspace = _workspaceById(workspaceId);
    if (workspace == null) {
      _h.failSessionConnect('pending', 'Workspace not found.');
      return;
    }
    if (_tabStore.isEmpty) {
      _h.beginSessionConnect('pending');
      try {
        await _materializeDefaultPersonalWorkspaceSession(
          workspace,
          r,
          connectImmediately: true,
          personalIdentityId: personalIdentityId,
          cliOverride: cliOverride,
        );
      } on Object catch (e, st) {
        appLogger.e(
          'connectPersonalSession: materialize failed: $e',
          stackTrace: st,
        );
        _h.failSessionConnect('pending', 'Failed to create session: $e');
      }
      return;
    }
    final tab = _activeTab;
    final session = tab?.persistedSession;
    if (tab == null || session == null) {
      _h.failSessionConnect('pending', 'No active personal session tab.');
      return;
    }
    await requestOpenSession(
      SessionOpenRequest(
        session: session,
        workspace: _workspaceById(session.workspaceId),
        repo: r,
        connectImmediately: true,
      ),
    );
  }

  Future<void> _connectTeamSession(
    TeamProfile team, {
    SessionRepository? repo,
  }) async {
    resetTeamConfigValidationSurface();
    unawaited(scheduleTeamConfigValidation(team));

    final r = repo ?? _h.sessionRepository;
    if (_tabStore.isEmpty && r == null) {
      _appendLocalTab(team, emitChange: true);
    }

    if (_h.autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = _state.selectedMemberId.isNotEmpty
          ? _state.selectedMemberId
          : _tabStore.defaultMemberId(team);
      if (keepId.isEmpty) {
        final session = ensureSession(team);
        const message =
            'No member selected. Choose a team member and try again.';
        session?.write('\r\n[$message]\r\n');
        _h.failSessionConnect(_activeTab?.info.id ?? 'pending', message);
        return;
      }
      await launchAllMembers(team, repo: r);
      if (team.members.any((m) => m.id == keepId)) {
        _h.selectMember(keepId);
      }
      return;
    }

    var memberId = _state.selectedMemberId;
    if (memberId.isEmpty) {
      memberId = _tabStore.defaultMemberId(team);
    }
    if (memberId.isEmpty || team.members.isEmpty) {
      final session = ensureSession(team);
      const message = 'No member selected. Choose a team member and try again.';
      session?.write('\r\n[$message]\r\n');
      _h.failSessionConnect(_activeTab?.info.id ?? 'pending', message);
      return;
    }
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => team.members.first,
    );
    await openMemberTab(
      team,
      member,
      repo: r,
      scheduleTeamConfigValidation: false,
    );
  }

  Future<void> reconnectSshProfile(String profileId) =>
      _sshReconnect.reconnect(profileId);

  void disconnectSession() {
    final tab = _activeTab;
    if (tab == null) return;
    final memberId = tab.selectedMemberId;
    tab.membersPendingConnect.remove(memberId);
    tab.memberShells[memberId]?.disconnect();
    unawaited(tab.closeMemberRemotePlane(memberId));
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    switch (request) {
      case TeamSessionConnect(:final team):
        await restartTeamSession(team, repo: repo);
      case PersonalSessionConnect():
        disconnectSession();
        await connectWorkspaceSession(request, repo: repo);
    }
  }

  Future<void> restartTeamSession(
    TeamProfile team, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _h.sessionRepository;
    final activeId = _activeTab?.info.id ?? _state.activeSessionId ?? 'pending';
    _h.beginSessionConnect(activeId);
    if (_h.autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = _state.selectedMemberId.isNotEmpty
          ? _state.selectedMemberId
          : _tabStore.defaultMemberId(team);
      final tab = _activeTab;
      if (tab != null) {
        tab.membersPendingConnect.clear();
        for (final shell in tab.memberShells.values) {
          shell.disconnect();
        }
        for (final memberId in tab.memberSshSessions.keys.toList()) {
          unawaited(tab.closeMemberRemotePlane(memberId));
        }
        _h.updateTabRunning(tab.info.id);
      }
      await launchAllMembers(team, repo: r);
      if (keepId.isNotEmpty && team.members.any((m) => m.id == keepId)) {
        _h.selectMember(keepId);
      }
      return;
    }
    disconnectSession();
    await connectWorkspaceSession(TeamSessionConnect(team), repo: r);
  }

  @override
  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) =>
      _promptMetadata.autoRenameOnFirstPrompt(sessionId);

  @override
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) =>
      _promptMetadata.autoTouchOnEveryPrompt(sessionId);

  ChatTab _appendLocalTab(TeamProfile team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
    if (emitChange) {
      _h.applyState(
        _state.copyWith(
          tabs: _tabStore.toInfos(),
          activeTabIndex: _tabStore.length - 1,
          activeSessionId: tab.info.id,
          selectedMemberId: tab.selectedMemberId,
          composeActive: false,
        ),
      );
    }
    return tab;
  }

  ChatTab _ensureActiveSessionTab(
    TeamProfile team, {
    required bool emitChange,
  }) {
    final existing = _activeTab;
    if (existing != null) return existing;
    return _appendLocalTab(team, emitChange: emitChange);
  }
}
