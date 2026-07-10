import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/workspace_folder.dart';
import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/launch/session_launch_readiness.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/launch/launch_operation.dart';
import '../../services/launch/launch_outcome.dart';
import '../../services/launch/session_launch_bundle.dart';
import '../../services/launch/session_launch_pipeline.dart';
import '../../services/launch/session_member_connect_scheduler.dart';
import '../../services/launch/session_ssh_profile_reconnect.dart';
import '../../services/launch/session_lifecycle_connect_coordinator.dart';
import '../../services/launch/session_prompt_metadata_sync.dart';
import '../../services/launch/session_shell_connector.dart';
import '../../services/launch/session_tab_connect_prep.dart';
import '../../services/launch/session_launch_workspace_index.dart';
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
import 'model/session_connect_request.dart';
import 'member_connector.dart';

/// Owns session launch orchestration: delegates user operations to
/// [SessionLaunchPipeline], wires member/shell collaborators, and implements
/// [MemberConnector] for mid-connect lifecycle callbacks.
class SessionLaunchService
    implements MemberConnector, SessionShellConnectorDelegate {
  SessionLaunchService(this._h);

  final SessionLaunchHost _h;
  late final SessionShellConnector _shellConnector = SessionShellConnector(
    _h,
    this,
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
  late final SessionLaunchBundle _launch = SessionLaunchBundle.create(
    SessionLaunchBundleDeps(
      host: _h,
      tabStore: _tabStore,
      state: () => _h.state,
      workspaceIndex: () => _workspaceIndex,
      workspaceById: _workspaceById,
      prepCallbacks: _tabConnectCallbacks,
      shouldAutoConnect: _shouldAutoConnect,
      scheduleShellConnect: _scheduleShellConnect,
      rollbackStagedLaunch: _rollbackStagedLaunch,
      installTeamRuntimeIfNeeded: _installTeamRuntimeIfNeeded,
      personalPresetIdOverride: _personalPresetIdOverride,
      scheduleMemberConnect: _memberConnectScheduler.schedule,
      disconnectSession: disconnectSession,
      ensureSession: ensureSession,
      appendLocalTab: _appendLocalTab,
      ensureActiveSessionTab: _ensureActiveSessionTab,
      resetTeamConfigValidationSurface: resetTeamConfigValidationSurface,
      scheduleTeamConfigValidation: scheduleTeamConfigValidation,
      activeTab: () => _activeTab,
      autoLaunchAllMembersOnConnect: () =>
          _h.autoLaunchAllMembersOnConnect?.call() == true,
      isTabsEmpty: () => _tabStore.activeTabsIsEmpty,
      activeBucketKey: () => _tabStore.activeWorkspaceId,
      uuid: _uuid,
    ),
  );
  SessionLaunchPipeline get _pipeline => _launch.pipeline;
  late final SessionSshProfileReconnect _sshReconnect = SessionSshProfileReconnect(
    host: _h,
    shellConnector: _shellConnector,
    launchContextFor: launchContextFor,
    scheduleMemberConnect: _memberConnectScheduler.schedule,
    workspaceIndex: () => _workspaceIndex,
    openTabs: () => _tabStore.openTabs,
  );
  late final SessionLifecycleConnectCoordinator _lifecycleCoordinator =
      SessionLifecycleConnectCoordinator(
        host: _h,
        launchContextFor: launchContextFor,
        launchWorkTarget: _launchWorkTarget,
        scheduleMemberConnect: _memberConnectScheduler.schedule,
        tabIndexOfSession: _tabStore.activeIndexOfSession,
      );
  late final SessionPromptMetadataSync _promptMetadata = SessionPromptMetadataSync(
    host: _h,
    state: () => _h.state,
  );
  static const _uuid = Uuid();
  final _teamConfigValidator = TeamConfigLaunchValidator();

  SessionTabConnectPrepCallbacks get _tabConnectCallbacks =>
      (
        persistSessionIfNeeded: _persistSessionIfNeeded,
        ensureTeamSessionReady: _ensureTeamSessionReady,
        onMixedPlacementNotReady: _onMixedPlacementNotReady,
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

  void _onMixedPlacementNotReady({
    required ChatTab tab,
    required AppSession launchSession,
    required SessionOpenRequest request,
  }) {
    if (request.persistParams != null) {
      _rollbackStagedLaunch(
        tab: tab,
        sessionId: launchSession.sessionId,
        request: request,
        message: 'mixed_workspace_member_placement_uninitialized',
      );
    } else {
      _h.failSessionConnect(
        launchSession.sessionId,
        'mixed_workspace_member_placement_uninitialized',
      );
    }
  }

  Future<SessionOpenStatus> requestOpenSession(
    SessionOpenRequest request,
  ) =>
      _launch.openSession(request);

  /// Stages a new conversation tab immediately, then persists and connects async.
  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) async {
    final outcome = await _pipeline.run(CreateSessionOperation(request));
    return switch (outcome) {
      LaunchOpened(:final status) => status,
      _ => SessionOpenStatus.opened,
    };
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
      rosterMembers: params.rosterMembers,
      cli: params.cli,
      workingDirectory: params.workingDirectory,
      fixedSessionId: session.sessionId,
      expertKey: params.expertKey,
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
    if (_tabStore.activeIndexOfSession(tab.info.id) == -1) return false;
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

  Future<ResolvedLaunchMembers> _resolveLaunchMembers({
    required AppSession session,
    required SessionOpenRequest request,
    Workspace? workspace,
  }) async {
    if (request.isPersonal) {
      final resolvedWorkspace =
          workspace ?? _workspaceById(session.workspaceId);
      if (resolvedWorkspace == null) {
        throw StateError('Simple session requires workspace');
      }
      final presetOverride = _personalPresetIdOverride(request);
      CliPreset? preset;
      if (presetOverride.isNotEmpty) {
        preset = await _h.lifecycle.resolvePresetById(presetOverride);
      }
      final cli = session.cli ?? preset?.cli ?? CliTool.claude;
      // Member persona comes from SessionRuntimePlan at connect time.
      final member = TeamMemberConfig(
        id: session.sessionId,
        name: session.sessionId,
        cli: cli,
      );
      return (
        team: null,
        member: member,
        cli: cli,
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
    final session = tab.persistedSession;
    final instances = (session == null
            ? runtimeRosterMembers(team)
            : sessionRosterMembers(session, team))
        .where((m) => m.isValid);
    for (final candidate in instances) {
      if (candidate.id == keepSelectedMemberId) continue;
      _memberConnectScheduler.schedule(team, candidate, tab);
    }
    if (instances.any((m) => m.id == keepSelectedMemberId)) {
      _h.selectMember(keepSelectedMemberId);
    }
  }

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
    final tab = _tabStore.openTabBySessionId(sessionId);
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
  }) =>
      _pipeline.run(
        OpenMemberTabOperation(
          team,
          member,
          repo: repo,
          workspaceCwd: workspaceCwd,
          scheduleTeamConfigValidation: scheduleTeamConfigValidation,
        ),
      );

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
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return false;
    if (tab.membersPendingConnect.contains(memberId)) return true;
    final shell = tab.memberShells[memberId];
    return shell?.isConnecting ?? false;
  }


  Future<void> launchAllMembers(
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) =>
      _pipeline.run(
        LaunchAllMembersOperation(team, repo: repo, workspaceCwd: workspaceCwd),
      );

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
  }) =>
      _pipeline.run(ConnectWorkspaceOperation(request, repo: repo));

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
  }) =>
      _pipeline.run(RestartWorkspaceOperation(request, repo: repo));

  @override
  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) =>
      _promptMetadata.autoRenameOnFirstPrompt(sessionId);

  @override
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) =>
      _promptMetadata.autoTouchOnEveryPrompt(sessionId);

  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _promptMetadata.applyFirstPromptTitle(sessionId, firstPrompt);

  ChatTab _appendLocalTab(TeamProfile team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
    if (emitChange) {
      _h.applyState(
        _state.copyWith(
          tabs: _tabStore.activeTabInfos(),
          activeTabIndex: _tabStore.activeTabCount - 1,
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
