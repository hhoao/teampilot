import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/workspace_folder.dart';
import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/session_continue_overrides.dart';
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
import '../../services/session/session_launch_config_snapshot.dart';
import '../../services/session/session_member_cli_locks.dart';
import '../../services/storage/work_target_canonicalizer.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import 'session_launch_host.dart';

export 'session_launch_host.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
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
  SessionLaunchService(
    this._h, {
    TermuxWorkOpsBlockResolver? termuxWorkOpsBlockFor,
    this.onSessionTabOpened,
  }) : _termuxWorkOpsBlockFor = termuxWorkOpsBlockFor;

  final SessionLaunchHost _h;
  final TermuxWorkOpsBlockResolver? _termuxWorkOpsBlockFor;

  /// Domain → bar handshake for newly staged session tabs (wired by the app
  /// shell to [WorkbenchChatBridge.onSessionTabOpened]).
  final void Function(
    String workspaceId,
    String sessionId, {
    bool preview,
    bool activate,
  })? onSessionTabOpened;
  late final SessionShellConnector _shellConnector = SessionShellConnector(
    _h,
    this,
    termuxWorkOpsBlockFor: _termuxWorkOpsBlockFor,
  );
  late final SessionMemberConnectScheduler _memberConnectScheduler =
      SessionMemberConnectScheduler(
        host: _h,
        shellConnector: _shellConnector,
        shellForLaunch: _shellForLaunch,
        sessionForMemberConnect: _sessionForMemberConnect,
        tabStore: _tabStore,
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
      onSessionTabOpened: onSessionTabOpened,
    ),
  );
  SessionLaunchPipeline get _pipeline => _launch.pipeline;
  late final SessionSshProfileReconnect _sshReconnect =
      SessionSshProfileReconnect(
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
        tabOpen: (sessionId) => _tabStore.openTabBySessionId(sessionId) != null,
      );
  late final SessionPromptMetadataSync _promptMetadata =
      SessionPromptMetadataSync(host: _h, state: () => _h.state);
  static const _uuid = Uuid();
  final _teamConfigValidator = TeamConfigLaunchValidator();

  SessionTabConnectPrepCallbacks get _tabConnectCallbacks => (
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
    // Selected member lives on the ChatTab; the tab-connect prep writes
    // tab.selectedMemberId. The bar is the single session-identity source.
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

  Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) =>
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

    final sw = Stopwatch()..start();
    final teamId = params.sessionTeamId.trim();
    final memberClis = teamId.isEmpty
        ? const <String, CliTool>{}
        : resolveSessionMemberCliLocks(
            team: request.team!,
            rosterMembers: params.rosterMembers,
            globalPresets: _h.lifecycle.globalPresets,
          );

    final continueOverrides = params.sessionTeamId.trim().isEmpty
        ? params.continueOverrides
        : snapshotTeamSessionContinueOverrides(
            base: params.continueOverrides ?? const SessionContinueOverrides(),
            team: request.team!,
            bindings: session.members,
            globalPresets: _h.lifecycle.globalPresets,
          );
    final persisted = (await repo.createSession(
      session.workspaceId,
      sessionTeam: params.sessionTeamId,
      rosterMembers: params.rosterMembers,
      memberClis: memberClis,
      cli: params.simpleIdentity?.cli ?? params.cli,
      provider: params.simpleIdentity?.provider,
      model: params.simpleIdentity?.model,
      effort: params.simpleIdentity?.effort,
      presetId: params.simpleIdentity?.presetId,
      workingDirectory: params.workingDirectory,
      fixedSessionId: session.sessionId,
      expertKey: params.simpleIdentity?.expertKey ?? params.expertKey,
      continueOverrides: continueOverrides,
      members: session.members,
      memberTargets: session.memberTargets,
      knownWorkspace: request.workspace,
    )).session;
    appLogger.d(
      '[session-launch] createSession '
      'session=${persisted.sessionId} ms=${sw.elapsedMilliseconds}',
    );
    var persistedWithTitle = persisted;
    final stagedTitle = _state
        .sessions
        .where((s) => s.sessionId == session.sessionId)
        .firstOrNull
        ?.display
        .trim();
    if (stagedTitle != null &&
        stagedTitle.isNotEmpty &&
        persistedWithTitle.display.trim().isEmpty) {
      await repo.renameSession(session.sessionId, stagedTitle);
      persistedWithTitle = persistedWithTitle.copyWith(display: stagedTitle);
    }
    tab.persistedSession = persistedWithTitle;
    _h.replaceSessionSnapshot(persistedWithTitle);
    return persistedWithTitle;
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
    if (_tabStore.openTabBySessionId(tab.info.id) == null) return false;
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
      final identity = session.simpleIdentity;
      final cli = identity.cli;
      // Member persona comes from SessionRuntimePlan at connect time.
      final member = TeamMemberConfig(
        id: session.sessionId,
        name: session.sessionId,
        cli: cli,
      );
      return (team: null, member: member, cli: cli);
    }
    final team = request.team!;
    final member = request.member!;
    return (
      team: team,
      member: member,
      cli: sessionMemberLaunchCli(
        session: session,
        team: team,
        member: member,
        globalPresets: _h.lifecycle.globalPresets,
      ),
    );
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
    final queuedAt = DateTime.now();
    appLogger.d(
      '[session-launch] scheduleShellConnect queued '
      'session=${session.sessionId}',
    );
    _h.postFrameScheduler(() async {
      appLogger.d(
        '[session-launch] scheduleShellConnect frame '
        'session=${session.sessionId} '
        'waitMs=${DateTime.now().difference(queuedAt).inMilliseconds}',
      );
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
            if (member != null) {
              tab.reclaimedMemberIds.remove(member.id);
            }
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
    final instances =
        (session == null
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
  }) => _lifecycleCoordinator.gateBeforeAttach(
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
  /// launch target (local PTY vs SSH) and whose executable matches [cli].
  TerminalSession _shellForLaunch({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required AppSession session,
    String? rosterMemberId,
  }) {
    final workTarget = _launchWorkTarget(session, memberId: rosterMemberId);
    final needsRemoteLaunch = usesSshTransport(workTarget.kind);
    _discardIdleShellIfMismatched(
      tab: tab,
      shellKey: shellKey,
      cli: cli,
      needsRemoteLaunch: needsRemoteLaunch,
      sessionId: tab.info.id,
    );
    return tab.memberShells.putIfAbsent(
      shellKey,
      () => _h.shellFactory.newSession(cli, workTarget: workTarget),
    );
  }

  /// Drop an idle shell when transport or CLI executable no longer matches.
  ///
  /// Connect launches [TerminalSession.executable]; keeping a stale shell after
  /// a profile change would spawn the wrong CLI despite a locked binding.
  void _discardIdleShellIfMismatched({
    required ChatTab tab,
    required String shellKey,
    required CliTool cli,
    required bool needsRemoteLaunch,
    String? sessionId,
  }) {
    final existing = tab.memberShells[shellKey];
    if (existing == null) return;
    if (existing.isRunning || existing.isConnecting) return;
    final expectedExecutable = _h.shellFactory.executableFor(cli);
    final transportMismatch = needsRemoteLaunch != existing.usesRemoteTransport;
    final cliMismatch = existing.executable != expectedExecutable;
    if (!transportMismatch && !cliMismatch) return;
    existing.disconnect();
    tab.memberShells.remove(shellKey);
    if (sessionId != null) {
      _h.clearAgentStatusSeat(sessionId: sessionId, memberId: shellKey);
    }
  }

  Future<void> openMemberTab(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
    bool scheduleTeamConfigValidation = true,
  }) => _pipeline.run(
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
    final homeTargetId = WorkTargetCanonicalizer.defaultFolderTargetId(
      _h.lifecycle.currentHome,
    );
    final session =
        tab.persistedSession ??
        AppSession(
          sessionId: tab.info.id,
          workspaceId: '',
          folders: [
            if (launch.$1.isNotEmpty)
              WorkspaceFolder(path: launch.$1, targetId: homeTargetId),
            for (final p in launch.$2)
              if (p.isNotEmpty)
                WorkspaceFolder(path: p, targetId: homeTargetId),
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
    if (_h.isSessionConnecting(sessionId)) return true;
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
  }) => _pipeline.run(
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
      final session = tab.persistedSession;
      final cli = session != null
          ? SessionMemberCliResolver.resolve(
              persistedSession: session,
              team: team,
              memberId: memberId,
              globalPresets: _h.lifecycle.globalPresets,
              cliForMember: _h.shellFactory.cliForMember,
            )
          : _h.shellFactory.cliForMember(
              team,
              memberId,
              globalPresets: _h.lifecycle.globalPresets,
            );
      if (session != null) {
        return _shellForLaunch(
          tab: tab,
          shellKey: memberId,
          cli: cli,
          session: session,
          rosterMemberId: memberId,
        );
      }
      _discardIdleShellIfMismatched(
        tab: tab,
        shellKey: memberId,
        cli: cli,
        needsRemoteLaunch: false,
      );
      return tab.memberShells.putIfAbsent(
        memberId,
        () => _h.shellFactory.newSession(cli),
      );
    }
    return tab.resumeSession ??= _h.shellFactory.newSession(team.cli);
  }

  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _pipeline.run(ConnectWorkspaceOperation(request, repo: repo));

  Future<void> reconnectSshProfile(String profileId) =>
      _sshReconnect.reconnect(profileId);

  void disconnectSession() {
    final tab = _activeTab;
    if (tab == null) return;
    final memberId = tab.selectedMemberId;
    tab.membersPendingConnect.remove(memberId);
    tab.memberShells[memberId]?.disconnect();
    unawaited(tab.closeMemberRemotePlane(memberId));
    _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: memberId);
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  /// Disconnects [memberId] on [sessionId]'s open tab (any tab, not only active).
  ///
  /// Mirrors [disconnectSession] cleanup for one member shell without closing
  /// the session workbench tab. Used by Resource Manager kill.
  void disconnectMemberShell(String sessionId, String memberId) {
    final id = sessionId.trim();
    final mid = memberId.trim();
    if (id.isEmpty || mid.isEmpty) return;
    final tab = _tabStore.openTabBySessionId(id);
    if (tab == null) return;
    tab.membersPendingConnect.remove(mid);
    tab.memberShells[mid]?.disconnect();
    unawaited(tab.closeMemberRemotePlane(mid));
    _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: mid);
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  /// Reclaims an idle member's live terminal (Chrome-style discard).
  ///
  /// Synchronous: flips the TeamBus lifecycle to `declared` before tearing down
  /// the shell so no send-into-dead-PTY window exists. The materialize funnel or
  /// [ensureMemberTerminalForView] re-brings the member online on demand (resume).
  void discardMemberTerminal(String sessionId, String memberId) {
    final id = sessionId.trim();
    final mid = memberId.trim();
    if (id.isEmpty || mid.isEmpty) return;
    final tab = _tabStore.openTabBySessionId(id);
    if (tab == null) return;
    final shell = tab.memberShells[mid];
    if (shell == null || !shell.isRunning) return;
    tab.teamBus?.markMemberDiscarded(mid);
    tab.membersPendingConnect.remove(mid);
    shell.disconnect();
    tab.memberShells.remove(mid);
    tab.reclaimedMemberIds.add(mid);
    unawaited(tab.closeMemberRemotePlane(mid));
    _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: mid);
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  /// Lazy-spawn / restore entry for "member selected + terminal view visible".
  ///
  /// No-op when the shell is already up, connecting, or a connect is pending.
  /// Team sessions resolve the roster member and schedule a connect (resume).
  /// Simple sessions are intentionally not handled here — their restore is the
  /// existing chat-submit / history-review connect path.
  Future<void> ensureMemberTerminalForView(
    String sessionId,
    String memberId,
  ) async {
    final id = sessionId.trim();
    final mid = memberId.trim();
    if (id.isEmpty || mid.isEmpty) return;
    final tab = _tabStore.openTabBySessionId(id);
    if (tab == null) return;
    final shell = tab.memberShells[mid];
    if (shell != null && (shell.isRunning || shell.isConnecting)) return;
    if (tab.membersPendingConnect.contains(mid)) return;
    final session = tab.persistedSession;
    if (session == null) return;
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return; // Simple mode — not this path.
    final team = await _h.teamProfileById(teamId);
    if (team == null) return;
    final member = sessionRosterMembers(session, team)
        .where((m) => m.id == mid)
        .firstOrNull;
    if (member == null || !member.isValid) return;
    _memberConnectScheduler.schedule(team, member, tab);
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _pipeline.run(RestartWorkspaceOperation(request, repo: repo));

  @override
  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) =>
      _promptMetadata.autoRenameOnFirstPrompt(sessionId);

  @override
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) =>
      _promptMetadata.autoTouchOnEveryPrompt(sessionId);

  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _promptMetadata.applyFirstPromptTitle(sessionId, firstPrompt);

  void touchOnUserActivity(String sessionId) =>
      _promptMetadata.touchOnUserActivity(sessionId);

  ChatTab _appendLocalTab(TeamProfile team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
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
