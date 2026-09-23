import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../models/runtime_target.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_launch_context.dart';
import '../../../models/workspace_folder.dart';
import '../../../models/app_session.dart';
import '../../../models/member_instance.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';
import 'session/session_launch_readiness.dart';
import 'connect/connect_shell_result.dart';
import 'connect/member_connect_stage.dart';
import 'connect/session_connect_executor.dart';
import 'connect/session_connect_job.dart';
import 'connect/session_connect_scheduler.dart';
import 'connect/launch_generation_store.dart';
import 'connect/session_personal_shell.dart';
import 'connect/session_ssh_profile_reconnect.dart';
import 'connect/session_lifecycle_connect_coordinator.dart';
import 'session/session_prompt_metadata_sync.dart';
import 'connect/session_shell_connector.dart';
import 'session/session_launch_coordinator.dart';
import 'session/session_launch_workspace_index.dart';
import '../../cli/preset_resolver.dart';
import 'session/session_launch_config_snapshot.dart';
import 'session/session_member_cli_locks.dart';
import '../../storage/home_storage.dart';
import '../../storage/work_target_canonicalizer.dart';
import 'session/team_config_launch_validator.dart';
import '../session/session_member_cli_resolver.dart';
import 'session_launch_host.dart';

export 'session_launch_host.dart';
import '../../terminal/terminal_session.dart';
import '../../../utils/logging/logger.dart';
import '../session/chat_tab_store.dart';
import 'chat_state_port.dart';
import '../session/chat_tab.dart';
import '../session/session_create_request.dart';
import '../session/session_open_request.dart';
import '../session/session_open_status.dart';
import '../session/session_connect_request.dart';
import 'connect/member_connector.dart';

/// Owns application/state adapters for the launch coordinator and connect
/// executor. Construction of the launch graph belongs to `launch_factory.dart`.
class SessionLaunchService
    implements
        MemberConnector,
        SessionShellConnectorDelegate,
        SessionConnectPreparationPort {
  SessionLaunchService(
    this._h, {
    required HomeStorage storage,
    this.onSessionTabOpened,
    LaunchGenerationStore? generations,
  }) : _storage = storage,
       _generations = generations ?? LaunchGenerationStore();

  final SessionLaunchHost _h;
  final HomeStorage _storage;
  final LaunchGenerationStore _generations;

  /// Domain → bar handshake for newly staged session tabs (wired by the app
  /// shell to [WorkbenchChatBridge.onSessionTabOpened]).
  final void Function(
    String workspaceId,
    String sessionId, {
    bool preview,
    bool activate,
  })?
  onSessionTabOpened;

  static const _uuid = Uuid();
  SessionConnectScheduler? _connectScheduler;
  late final SessionLaunchCoordinator _coordinator;
  late final MemberConnectStage _memberConnect;
  late final SessionSshProfileReconnect _sshReconnect;
  late final SessionLifecycleConnectCoordinator _lifecycleCoordinator;
  late final SessionPromptMetadataSync _promptMetadata;
  late final TeamConfigLaunchValidator _teamConfigValidator;

  /// Called by the launch composition root after the service has been created
  /// as the preparation/delegate boundary for the executor and shell connector.
  void configureLaunchComponents({
    required SessionConnectScheduler connectScheduler,
    required SessionLaunchCoordinator coordinator,
    required MemberConnectStage memberConnect,
    required SessionSshProfileReconnect sshReconnect,
    required SessionLifecycleConnectCoordinator lifecycleCoordinator,
    required SessionPromptMetadataSync promptMetadata,
    required TeamConfigLaunchValidator teamConfigValidator,
  }) {
    _connectScheduler = connectScheduler;
    _coordinator = coordinator;
    _memberConnect = memberConnect;
    _sshReconnect = sshReconnect;
    _lifecycleCoordinator = lifecycleCoordinator;
    _promptMetadata = promptMetadata;
    _teamConfigValidator = teamConfigValidator;
  }

  ChatDataSnapshot get _state => _h.stateSnapshot();
  ChatTabStore get _tabStore => _h.tabStore;
  ChatTab? get _activeTab => _h.activeTab;

  ChatTab? _openTab(String sessionId) =>
      _tabStore.getOpenTabBySessionId(sessionId);

  ChatTab _requireTab(String sessionId) {
    final tab = _openTab(sessionId);
    if (tab == null) {
      throw StateError('launch tab missing session=$sessionId');
    }
    return tab;
  }

  SessionLaunchWorkspaceIndex get _workspaceIndex =>
      SessionLaunchWorkspaceIndex(
        workspaces: _state.workspaces,
        sessions: _state.sessions,
        usesPosixPaths: _storage.usesPosixPaths,
      );

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex.byId(workspaceId);

  Workspace? workspaceById(String workspaceId) => _workspaceById(workspaceId);

  void _assignSelectedMemberOnTab({
    required ChatTab tab,
    required String memberId,
  }) {
    _h.assignSelectedMember(tab, memberId);
  }

  Future<SessionOpenStatus> requestOpenSession(
    SessionOpenRequest request, {
    LaunchReason reason = LaunchReason.openExisting,
    bool waitForCompletion = false,
  }) => _coordinator.open(
    request,
    reason: reason,
    waitForCompletion: waitForCompletion,
  );

  /// Stages a new conversation tab immediately, then persists and connects async.
  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) => _coordinator.createAndOpen(request);

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
      purpose: params.purpose,
      workflowId: params.workflowId,
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
    final stagedTitle = _state.sessions
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
    required String sessionId,
    required SessionOpenRequest request,
    required String message,
  }) {
    _h.failSessionConnect(sessionId, message);
    if (request.persistParams == null) return;
    _h.closeSessionTab(sessionId);
    _h.removeSessionSnapshot(sessionId);
  }

  bool _launchStillValid(String sessionId, int generation) {
    if (_h.isClosed) return false;
    if (_openTab(sessionId) == null) return false;
    return _generations.matches(sessionId, generation);
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
    if (!_launchStillValid(session.sessionId, generation)) return;
  }

  Future<void> onConnectResult(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
    ConnectShellResult result,
  ) async {
    if (result != ConnectShellResult.attached) return;
    final tab = _requireTab(job.sessionId);
    final member = resolved.member;
    tab.reclaimedMemberIds.remove(member.id);
    final team = resolved.team;
    if (team != null &&
        shouldFanOutRemainingMembers(
          job,
          team: team,
          autoLaunchAllMembersOnConnect:
              _h.autoLaunchAllMembersOnConnect?.call() == true,
        )) {
      await _launchRemainingMembersForTab(
        team,
        member.id,
        tab,
        repo: job.request.repo,
      );
    }
    _h.updateTabRunning(tab.info.id);
  }

  @override
  Future<AppSession> persist(SessionConnectJob job) => _persistSessionIfNeeded(
    request: job.request,
    session: job.session,
    tab: _requireTab(job.sessionId),
  );

  @override
  Future<AppSession?> ensureReady(
    SessionConnectJob job,
    AppSession session,
  ) async {
    final ready = await _ensureTeamSessionReady(
      request: job.request,
      session: session,
      workspace: job.workspace,
    );
    if (ready == null) {
      throw StateError('mixed_workspace_member_placement_uninitialized');
    }
    _requireTab(job.sessionId).persistedSession = ready;
    return ready;
  }

  @override
  Future<ResolvedLaunchMembers> resolveMember(
    SessionConnectJob job,
    AppSession session,
  ) => _resolveLaunchMembers(
    session: session,
    request: job.request,
    workspace: job.workspace,
  );

  @override
  Future<void> installTeamRuntime(
    SessionConnectJob job,
    AppSession session,
    TeamProfile? team,
  ) async {
    final tab = _requireTab(job.sessionId);
    if (team != null && tab.teamBus == null) {
      await _installTeamRuntimeIfNeeded(
        tab: tab,
        session: session,
        team: team,
        generation: job.generation,
      );
    }
  }

  @override
  Future<void> markDeferredReady(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  ) async {
    final tab = _requireTab(job.sessionId);
    if (resolved.team != null) {
      _assignSelectedMemberOnTab(tab: tab, memberId: resolved.member.id);
    }
    _h.updateTabRunning(tab.info.id);
  }

  @override
  void markConnectFailed(SessionConnectJob job, String memberId) {
    _h.memberMaterializer.markMemberReady(job.sessionId, memberId);
    _h.updateTabRunning(job.sessionId);
  }

  @override
  TerminalSession shellForLaunch(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  ) {
    final tab = _requireTab(job.sessionId);
    if (job.request.shellAcquisition ==
        SessionShellAcquisition.personalResumeSession) {
      final resumeSession = displayedPersonalResumeShell(
        sessionId: session.sessionId,
        resumeSession: tab.resumeSession,
        memberShells: tab.memberShells,
      );
      if (resumeSession == null || resumeSession.isDisposed) {
        throw StateError(
          'personal reconnect resume session is no longer available',
        );
      }
      return resumeSession;
    }
    if (job.reason != LaunchReason.restore &&
        job.reason != LaunchReason.sshReconnect) {
      _assignSelectedMemberOnTab(tab: tab, memberId: resolved.member.id);
    }
    return _shellForLaunch(
      tab: tab,
      shellKey: resolved.member.id,
      cli: resolved.cli,
      session: session,
      rosterMemberId: job.request.isPersonal ? null : resolved.member.id,
    );
  }

  @override
  bool isValid(SessionConnectJob job) =>
      _launchStillValid(job.sessionId, job.generation);

  @override
  void rollback(SessionConnectJob job, AppSession session) {
    _rollbackStagedLaunch(
      sessionId: session.sessionId,
      request: job.request,
      message: 'Failed to connect session.',
    );
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

  Future<void> _launchRemainingMembersForTab(
    TeamProfile team,
    String keepSelectedMemberId,
    ChatTab tab, {
    SessionRepository? repo,
  }) async {
    final session = tab.persistedSession;
    final instances =
        (session == null
                ? runtimeRosterMembers(team)
                : sessionRosterMembers(session, team))
            .where((m) => m.isValid);
    final completions = <Future<void>>[];
    for (final candidate in instances) {
      if (candidate.id == keepSelectedMemberId) continue;
      completions.add(
        _memberConnect.scheduleMemberConnectAndWait(
          team,
          candidate,
          tab.info.id,
          repo: repo,
          selectMember: false,
          reason: LaunchReason.restore,
        ),
      );
    }
    // Only re-assert selection for the connected member when no other member
    // owns the tab selection (e.g. a later explicit member switch while the
    // first shell was still connecting).
    if (instances.any((m) => m.id == keepSelectedMemberId) &&
        (tab.selectedMemberId.isEmpty ||
            tab.selectedMemberId == keepSelectedMemberId)) {
      _h.selectMember(keepSelectedMemberId);
    }
    await Future.wait(completions);
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
        usesPosixPaths: _storage.usesPosixPaths,
      );

  RuntimeTarget _launchWorkTarget(AppSession session, {String? memberId}) => _h
      .lifecycle
      .launchWorkTarget(launchContextFor(session), memberId: memberId);

  RuntimeTarget launchWorkTarget(AppSession session, {String? memberId}) =>
      _launchWorkTarget(session, memberId: memberId);

  @override
  void cancelLifecycleConnectRetry(String sessionId, String memberId) =>
      _lifecycleCoordinator.cancelRetry(sessionId, memberId);

  @override
  Future<ConnectShellResult?> lifecycleGateBeforeAttach({
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required String sessionId,
    required bool teamBusInstalled,
    String? remoteMemberKeyForRollback,
    Map<String, Map<String, Object?>>? extraMcpServers,
  }) => _lifecycleCoordinator.gateBeforeAttach(
    team: team,
    member: member,
    session: session,
    sessionId: sessionId,
    teamBusInstalled: teamBusInstalled,
    remoteMemberKeyForRollback: remoteMemberKeyForRollback,
    extraMcpServers: extraMcpServers,
  );

  /// Compose-landing direct PTY inject waits past lifecycle gate, not only boot frame.
  Future<bool> isMemberDirectPtyLifecycleReady(
    String sessionId,
    String memberId,
  ) async {
    final tab = _tabStore.getOpenTabBySessionId(sessionId);
    if (tab == null) return false;
    final session = tab.persistedSession;
    if (session == null || session.sessionTeam.trim().isEmpty) return true;

    final team = await _h.teamProfileById(session.sessionTeam);
    if (team == null) return false;

    final members = session.members.isNotEmpty
        ? sessionRosterMembers(session, team)
        : runtimeRosterMembers(team);
    final member = members.where((m) => m.id == memberId).firstOrNull;
    if (member == null || !member.isValid) return false;

    return _lifecycleCoordinator.isDirectPtyInputReady(
      sessionId: sessionId,
      session: session,
      team: team,
      member: member,
      teamBusInstalled: tab.teamBus != null,
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
  }) => _memberConnect.openMemberTab(
    team,
    member,
    repo: repo,
    workspaceCwd: workspaceCwd,
    scheduleTeamConfigValidation: scheduleTeamConfigValidation,
  );

  AppSession? _sessionForMemberConnect(String sessionId, TeamProfile team) {
    final tab = _openTab(sessionId);
    if (tab == null) return null;
    final freshest = _freshestSessionForTab(tab);
    if (freshest != null) {
      tab.persistedSession = freshest;
      return freshest;
    }
    if (!sessionId.startsWith('local-')) return null;
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
          sessionId: sessionId,
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

  AppSession? sessionForMemberConnect(String sessionId, TeamProfile team) =>
      _sessionForMemberConnect(sessionId, team);

  /// Latest [AppSession] for [tab]: in-memory snapshot first, then tab cache.
  AppSession? _freshestSessionForTab(ChatTab tab) =>
      _tabStore.sessionForTab(tab, _state.sessions);

  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    String sessionId, {
    bool selectMember = true,
  }) => _memberConnect.scheduleMemberConnect(
    team,
    member,
    sessionId,
    selectMember: selectMember,
    reason: LaunchReason.restore,
  );

  /// True when another launch path already owns PTY connect for [memberId].
  bool isMemberConnectOwnedElsewhere(String sessionId, String memberId) {
    final tab = _tabStore.getOpenTabBySessionId(sessionId);
    if (tab == null) return false;
    if (tab.membersPendingConnect.contains(memberId) ||
        _connectScheduler?.isPending(
              sessionId: sessionId,
              memberId: memberId,
            ) ==
            true) {
      return true;
    }
    final shell = tab.memberShells[memberId];
    return shell?.isConnecting ?? false;
  }

  Future<void> launchAllMembers(
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) => _memberConnect.launchAllMembers(
    team,
    repo: repo,
    workspaceCwd: workspaceCwd,
  );

  TerminalSession? ensureSession(TeamProfile team) {
    var tab = _activeTab;
    if (tab == null && _h.sessionRepository == null) {
      tab = _appendLocalTab(team, emitChange: false);
    }
    if (tab == null) return null;
    if (tab.selectedMemberId.isEmpty) {
      _h.assignSelectedMember(tab, _tabStore.defaultMemberId(team));
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
  }) => _memberConnect.run(request, repo: repo);

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
    final tab = _tabStore.getOpenTabBySessionId(id);
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
    final tab = _tabStore.getOpenTabBySessionId(id);
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
    final tab = _tabStore.getOpenTabBySessionId(id);
    if (tab == null) return;
    final shell = tab.memberShells[mid];
    if (shell != null && (shell.isRunning || shell.isConnecting)) return;
    if (tab.membersPendingConnect.contains(mid)) return;
    final session = _freshestSessionForTab(tab);
    if (session == null) return;
    tab.persistedSession = session;
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return; // Simple mode — not this path.
    final team = await _h.teamProfileById(teamId);
    if (team == null) return;
    final member = sessionRosterMembers(
      session,
      team,
    ).where((m) => m.id == mid).firstOrNull;
    if (member == null || !member.isValid) return;
    _memberConnect.scheduleMemberConnect(
      team,
      member,
      id,
      selectMember: false,
      reason: LaunchReason.restore,
    );
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _memberConnect.restart(request, repo: repo);

  @override
  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) =>
      _promptMetadata.autoRenameOnFirstPrompt(sessionId);

  @override
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) =>
      _promptMetadata.autoTouchOnEveryPrompt(sessionId);

  Future<void> applyFirstPromptTitle(
    String sessionId,
    String firstPrompt, {
    bool allowTeamGeneration = false,
  }) => _promptMetadata.applyFirstPromptTitle(
    sessionId,
    firstPrompt,
    allowTeamGeneration: allowTeamGeneration,
  );

  void touchOnUserActivity(String sessionId) =>
      _promptMetadata.touchOnUserActivity(sessionId);

  ChatTab _appendLocalTab(TeamProfile team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
    return tab;
  }

  ChatTab appendLocalTab(TeamProfile team, {required bool emitChange}) =>
      _appendLocalTab(team, emitChange: emitChange);

  ChatTab _ensureActiveSessionTab(
    TeamProfile team, {
    required bool emitChange,
  }) {
    final existing = _activeTab;
    if (existing != null) return existing;
    return _appendLocalTab(team, emitChange: emitChange);
  }

  ChatTab ensureActiveSessionTab(
    TeamProfile team, {
    required bool emitChange,
  }) => _ensureActiveSessionTab(team, emitChange: emitChange);
}

/// Returns whether a successful result should schedule members not in [job].
///
/// SSH reconnect already submits one job per affected member, so fanning out
/// from any reconnect result would execute those members a second time when
/// their original reconnect requests are processed.
bool shouldFanOutRemainingMembers(
  SessionConnectJob job, {
  required TeamProfile team,
  bool autoLaunchAllMembersOnConnect = false,
}) =>
    job.reason != LaunchReason.restore &&
    job.reason != LaunchReason.sshReconnect &&
    shouldLaunchAllMembers(
      team: team,
      autoLaunchAllMembersOnConnect: autoLaunchAllMembersOnConnect,
    );
