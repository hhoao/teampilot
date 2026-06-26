import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/workspace_folder.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/member_instance.dart';
import '../../models/personal_profile.dart';
import '../../services/storage/launch_profile_provisioner.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace_tab_ref.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/registry/config_profile/config_profile_context.dart';
import '../../services/launch/session_connect_orchestrator.dart';
import '../../services/launch/workspace_provision_coordinator.dart';
import '../../services/session/remote_ssh_launch_constraints.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../services/storage/app_storage.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/team_bus/mcp/bus_bridge_locator.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../services/team_bus/remote/member_bus_mcp_config.dart';
import '../../services/ssh/ssh_member_session.dart';
import '../../services/storage/targets_repository.dart';
import '../../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../../services/team_bus/remote/remote_bus_mount.dart';
import '../../services/team_bus/remote/ssh_remote_bus_mount_factory.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/capabilities/bus_transport_capability.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logger.dart';
import '../../utils/workspace_path_utils.dart';
import '../../utils/session_display_title.dart';
import '../../utils/team_member_naming.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';
import 'model/session_connect_request.dart';
import 'session_data_store.dart';
import 'tab_team_bus_coordinator.dart';

/// Seam [SessionLaunchService] uses to read/emit ChatState and reach the other
/// collaborators. Implemented by ChatCubit, which stays the sole emit owner
/// (the service routes every state write through [applyState] / the connect
/// state-machine methods).
abstract interface class SessionLaunchHost {
  ChatState get state;
  bool get isClosed;

  /// Single emit entry point (wraps the cubit's protected emit).
  void applyState(ChatState next);
  void emitSnapshot(ChatDataSnapshot snapshot);

  // Connect state-machine (ChatConnectStateMixin).
  void beginSessionConnect(String sessionId);
  void failSessionConnect(String sessionId, String rawMessage);
  void finishSessionConnect(String sessionId);
  void clearLaunchError(String sessionId);
  void emitLaunchWarnings(List<String> warnings);
  void emitTeamConfigValidation(TeamConfigValidation validation);
  void updateTabRunning(String tabId);

  // Cubit-owned facade methods the launch flow drives.
  void selectMember(String memberId);
  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  );
  Future<void> loadWorkspaceData(SessionRepository repo);
  void pushPresenceTarget();

  ChatTab? get activeTab;
  set activeTeam(TeamProfile? team);

  // Collaborators.
  ChatTabStore get tabStore;
  ChatSessionShellFactory get shellFactory;
  TabTeamBusCoordinator get busCoordinator;
  SessionLifecycleService get lifecycle;
  SessionDataStore get dataStore;

  // Resolvers.
  SessionRepository? get sessionRepository;
  PostFrameScheduler get postFrameScheduler;
  bool Function()? get autoLaunchAllMembersOnConnect;

  /// P3b (#1): resolves a remote member's reverse-tunnel bus binding. Null when
  /// remote-member-over-tunnel is not wired (then all members use local
  /// transport — pre-P3b behavior).
  RemoteBusBindingResolver? get remoteBusResolver;

  SessionConnectOrchestrator get sessionConnect;

  /// Exposes workspace Phase A for team / mixed off-home paths.
  WorkspaceProvisionCoordinator get workspaceProvision;
}

/// Owns the entire connect / launch flow: opening (or restoring) session tabs,
/// scheduling and wiring per-member shells, the team-bus materialize path, and
/// the connect/restart/disconnect user commands. ChatCubit delegates here and
/// keeps only its data/tab facades + getters.
class SessionLaunchService implements MemberConnector {
  SessionLaunchService(this._h);

  final SessionLaunchHost _h;

  static const _uuid = Uuid();
  final _teamConfigValidator = TeamConfigLaunchValidator();
  final _lastTouchTimes = <String, int>{};

  ChatState get _state => _h.state;
  ChatTabStore get _tabStore => _h.tabStore;
  ChatTab? get _activeTab => _h.activeTab;

  /// Returns false when the tab was closed or [shell] was disposed while an
  /// async connect prep was in flight — avoids [shell.connect] on a dead engine.
  bool _connectShellStillValid({
    required ChatTab tab,
    required TerminalSession shell,
  }) {
    if (_h.isClosed) return false;
    if (_tabStore.indexOfSession(tab.info.id) == -1) return false;
    if (shell.isDisposed) return false;
    return true;
  }

  void _abortConnectShellIfStale({
    required ChatTab tab,
    required TerminalSession shell,
    required String reason,
    String? remoteMemberKey,
  }) {
    if (_connectShellStillValid(tab: tab, shell: shell)) return;
    appLogger.d(
      '[session-launch] connectShell aborted session=${tab.info.id} '
      'reason=$reason',
    );
    if (remoteMemberKey != null) {
      unawaited(tab.closeMemberRemotePlane(remoteMemberKey));
    }
    if (_state.sessionConnectingId == tab.info.id) {
      _h.finishSessionConnect(tab.info.id);
    }
  }

  Future<void> openSessionTab(
    AppSession session, {
    TeamProfile? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
    String emptyDisplayTitleFallback = 'New Chat',
    bool connectImmediately = true,
  }) async {
    final isPersonal = session.sessionTeam.trim().isEmpty;
    appLogger.i(
      '[session-launch] openSessionTab start '
      'session=${session.sessionId} personal=$isPersonal '
      'member=${member?.id ?? ''} team=${team?.id ?? ''} '
      'connectImmediately=$connectImmediately',
    );
    final existingIdx = _tabStore.indexOfSession(session.sessionId);
    if (existingIdx != -1) {
      appLogger.i(
        '[session-launch] openSessionTab reuse existing tab '
        'session=${session.sessionId} idx=$existingIdx',
      );
      final existing = _tabStore.tabs[existingIdx];
      final memberId = member?.id ?? existing.selectedMemberId;
      existing.selectedMemberId = memberId;
      _h.applyState(
        _state.copyWith(
          activeTabIndex: existingIdx,
          activeSessionId: session.sessionId,
          selectedMemberId: memberId,
        ),
      );
      if (connectImmediately) {
        await _connectExistingTabIfNeeded(
          tab: existing,
          session: session,
          team: team,
          member: member,
          repo: repo,
        );
      }
      return;
    }
    final workspace = _workspaceById(session.workspaceId);
    final isPersonalSession = session.sessionTeam.trim().isEmpty;
    PersonalProfile? personalIdentity;
    TeamMemberConfig? personalMember;
    CliPreset? personalPreset;
    if (isPersonalSession) {
      if (workspace == null) {
        throw StateError(
          'openSessionTab requires workspace for personal sessions',
        );
      }
      final personalCtx = await _resolvePersonalMember(
        session: session,
        workspace: workspace,
      );
      personalIdentity = personalCtx.personalIdentity;
      personalPreset = personalCtx.personalPreset;
      personalMember = personalCtx.personalMember;
    }
    if (!isPersonalSession && (team == null || member == null)) {
      throw StateError(
        'openSessionTab requires team and member for non-personal sessions',
      );
    }
    final effectiveMember = isPersonalSession ? personalMember! : member!;
    final effectiveTeam = isPersonalSession ? null : team;
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.resolveDisplayTitle(emptyDisplayTitleFallback),
      subtitle: session.firstFolderPath,
    );
    final launched = session.launchState == AppSessionLaunchState.started;
    final cliTeamName = session.cliTeamName;
    final internalTab = ChatTab(info: info, cliTeamName: cliTeamName)
      ..persistedSession = session;
    final ts = _shellForLaunch(
      tab: internalTab,
      shellKey: effectiveMember.id,
      cli: isPersonalSession
          // Honor the session's pinned CLI so an existing simple-mode session
          // resumes under the CLI it was created with, even when the workspace's
          // active preset has since been switched to another CLI.
          ? (session.cli ?? personalPreset?.cli ?? CliTool.claude)
          : member!.cliWithin(team!),
      session: session,
      rosterMemberId: isPersonalSession ? null : effectiveMember.id,
    );
    internalTab.selectedMemberId = effectiveMember.id;
    _tabStore.append(internalTab);
    // 驱动 working 指示器（侧栏 tile + tab spinner）。mixed 模式靠总线 turn 真相，
    // 简单 / 原生单 CLI 靠 shell 活动检测——两条路径都需要这只 1s 看门狗在跑。
    _h.busCoordinator.ensureIdleWatch();
    _h.applyState(
      _state.copyWith(
        tabs: [..._state.tabs, info],
        activeTabIndex: _tabStore.length - 1,
        activeSessionId: session.sessionId,
        selectedMemberId: internalTab.selectedMemberId,
      ),
    );
    if (effectiveTeam != null) {
      _h.activeTeam = effectiveTeam;
      _h.pushPresenceTarget();
      if (effectiveTeam.teamMode == TeamMode.mixed) {
        appLogger.i(
          '[session-launch] installing team bus '
          'session=${session.sessionId} team=${effectiveTeam.id}',
        );
        await _h.busCoordinator.installBusForTab(
          internalTab,
          effectiveTeam,
          session,
        );
      }
    }
    // mixed：非 team-lead 只建 bus + MCP，不 spawn PTY；team-lead 打开 tab 时自动 connect。
    final connectNow =
        connectImmediately &&
        (effectiveTeam?.teamMode != TeamMode.mixed ||
            TeamMemberNaming.isTeamLead(effectiveMember));
    if (connectNow) {
      appLogger.i(
        '[session-launch] connect scheduled '
        'session=${info.id} member=${effectiveMember.id} '
        'teamMode=${effectiveTeam?.teamMode.name ?? 'personal'}',
      );
      _h.beginSessionConnect(info.id);
      _h.postFrameScheduler(() async {
        try {
          await _connectShell(
            tab: internalTab,
            session: session,
            shell: ts,
            repo: repo,
            launched: launched,
            team: isPersonalSession ? null : team,
            member: isPersonalSession ? null : member,
            workspace: isPersonalSession ? workspace : null,
            personal: isPersonalSession ? personalIdentity : null,
          );
          if (!isPersonalSession &&
              _h.autoLaunchAllMembersOnConnect?.call() == true) {
            _launchRemainingMembersForTab(team!, member!.id, internalTab);
          }
          _h.updateTabRunning(info.id);
        } on Object catch (e, st) {
          appLogger.e(
            '[session-launch] prepareLaunch/connect failed for ${info.id}: $e',
            error: e,
            stackTrace: st,
          );
          final message = 'Failed to resume session: $e';
          ts.write('\r\n[$message]\r\n');
          _h.failSessionConnect(info.id, message);
        }
      });
    } else {
      appLogger.i(
        '[session-launch] connect deferred '
        'session=${info.id} connectImmediately=$connectImmediately '
        'teamMode=${effectiveTeam?.teamMode.name ?? 'personal'} '
        'member=${effectiveMember.id}',
      );
      _h.updateTabRunning(info.id);
    }
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
      _scheduleMemberConnect(team, candidate, tab);
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
  }) async {
    if (!_tabStore.isEmpty) return;

    final cwd = _resolveWorkspaceCwd(workspaceCwd);
    final existingSession = _existingSessionForMaterialize(
      team,
      workspaceCwd: cwd,
    );
    if (existingSession != null) {
      await openSessionTab(
        existingSession,
        team: team,
        member: memberForInitialShell,
        repo: repo,
        connectImmediately: connectImmediately,
      );
      return;
    }

    if (cwd == null || cwd.isEmpty) {
      const message = 'Open a workspace before starting a team session.';
      appLogger.w('[session] $message');
      _h.failSessionConnect('pending', message);
      return;
    }

    final workspace = _workspaceMatchingPath(cwd);
    if (workspace == null) {
      final message = 'Workspace not found for $cwd.';
      appLogger.w('[session] $message');
      _h.failSessionConnect('pending', message);
      return;
    }

    var session = _firstSessionForWorkspaceAndTeam(workspace.workspaceId, team.id);
    session ??= await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    await _h.loadWorkspaceData(repo);
    if (_h.isClosed) return;
    await openSessionTab(
      session,
      team: team,
      member: memberForInitialShell,
      repo: repo,
      connectImmediately: connectImmediately,
    );
  }

  String? _resolveWorkspaceCwd(String? workspaceCwd) {
    final explicit = workspaceCwd?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final bucketKey = _tabStore.activeWorkspaceId.trim();
    if (bucketKey.isEmpty) return null;
    final tab = WorkspaceTabRef.decodeTabKey(bucketKey);
    final workspaceId = tab?.workspaceId ?? bucketKey;
    return _workspaceById(workspaceId)?.firstFolderPath;
  }

  AppSession? _existingSessionForMaterialize(
    TeamProfile team, {
    String? workspaceCwd,
  }) {
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      final workspace = _workspaceMatchingPath(workspaceCwd);
      if (workspace != null) {
        final session = _firstSessionForWorkspaceAndTeam(
          workspace.workspaceId,
          team.id,
        );
        if (session != null) return session;
      }
    }
    for (final session in _state.sessions) {
      if (session.sessionTeam.trim() != team.id) continue;
      return session;
    }
    return null;
  }

  Workspace? _workspaceMatchingPath(String primaryPath) {
    for (final workspace in _state.workspaces) {
      if (workspacePathsEqual(workspace.firstFolderPath, primaryPath)) return workspace;
    }
    return null;
  }

  AppSession? _firstSessionForWorkspaceAndTeam(String workspaceId, String teamId) {
    for (final session in _state.sessions) {
      if (session.workspaceId != workspaceId) continue;
      if (session.sessionTeam.trim() != teamId) continue;
      return session;
    }
    return null;
  }

  AppSession? _firstSessionForPersonalWorkspace(String workspaceId) {
    return _firstSessionForWorkspaceAndTeam(workspaceId, '');
  }

  Future<
    ({
      PersonalProfile personalIdentity,
      CliPreset? personalPreset,
      TeamMemberConfig personalMember,
    })
  >
  _resolvePersonalMember({
    required AppSession session,
    required Workspace workspace,
    String personalIdentityIdOverride = '',
  }) async {
    var profileId = personalIdentityIdOverride.trim();
    if (profileId.isEmpty) {
      profileId = session.profileId.trim();
    }
    if (profileId.isEmpty) {
      profileId = workspace.defaultProfileId.trim();
    }
    if (profileId.isEmpty) {
      profileId = LaunchProfileProvisioner.defaultPersonalId;
    } else if (await _h.lifecycle.loadIdentity(profileId) == null) {
      profileId = LaunchProfileProvisioner.defaultPersonalId;
    }
    final personalIdentity = await _h.lifecycle.loadPersonalProfile(profileId);
    final personalPreset =
        await _h.lifecycle.resolveActivePresetForPersonal(personalIdentity);
    final personalMember = standaloneMemberFromPersonal(
      personalIdentity,
      preset: personalPreset,
    );
    return (
      personalIdentity: personalIdentity,
      personalPreset: personalPreset,
      personalMember: personalMember,
    );
  }

  Future<void> _materializeDefaultPersonalWorkspaceSession(
    Workspace workspace,
    SessionRepository repo, {
    required bool connectImmediately,
    String personalIdentityId = '',
    CliTool? cliOverride,
  }) async {
    if (!_tabStore.isEmpty) return;

    final existingSession = _firstSessionForPersonalWorkspace(workspace.workspaceId);
    if (existingSession != null) {
      await openSessionTab(
        existingSession,
        repo: repo,
        connectImmediately: connectImmediately,
      );
      return;
    }

    final personalCtx = await _resolvePersonalMember(
      session: AppSession(
        sessionId: '',
        workspaceId: workspace.workspaceId,
        folders: [
          if (workspace.firstFolderPath.isNotEmpty)
            WorkspaceFolder(path: workspace.firstFolderPath),
        ],
        sessionTeam: '',
        cliTeamName: '',
        createdAt: 0,
        profileId: personalIdentityId,
      ),
      workspace: workspace,
      personalIdentityIdOverride: personalIdentityId,
    );
    final cli =
        cliOverride ??
        personalCtx.personalPreset?.cli ??
        CliTool.claude;

    final session = await repo.createSession(
      workspace.workspaceId,
      personalIdentityId: personalCtx.personalIdentity.id,
      cli: cli,
    );
    await _h.loadWorkspaceData(repo);
    if (_h.isClosed) return;
    await openSessionTab(
      session,
      repo: repo,
      connectImmediately: connectImmediately,
    );
  }

  Future<void> _connectExistingTabIfNeeded({
    required ChatTab tab,
    required AppSession session,
    TeamProfile? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
  }) async {
    appLogger.i(
      '[session-launch] reconnect existing tab '
      'session=${session.sessionId} member=${member?.id ?? ''}',
    );
    final isPersonal = session.sessionTeam.trim().isEmpty;
    final workspace = isPersonal ? _workspaceById(session.workspaceId) : null;
    late final TeamMemberConfig effectiveMember;
    PersonalProfile? personalIdentity;
    TeamProfile? effectiveTeam;
    CliPreset? personalPreset;

    if (isPersonal) {
      if (workspace == null) return;
      final personalCtx = await _resolvePersonalMember(
        session: session,
        workspace: workspace,
      );
      personalIdentity = personalCtx.personalIdentity;
      personalPreset = personalCtx.personalPreset;
      effectiveMember = personalCtx.personalMember;
    } else {
      if (team == null || member == null) return;
      effectiveTeam = team;
      effectiveMember = member;
    }

    tab.selectedMemberId = effectiveMember.id;
    final shell = _shellForLaunch(
      tab: tab,
      shellKey: effectiveMember.id,
      cli: isPersonal
          ? (session.cli ?? personalPreset?.cli ?? CliTool.claude)
          : member!.cliWithin(team!),
      session: session,
      rosterMemberId: isPersonal ? null : effectiveMember.id,
    );

    if (shell.isRunning || shell.isConnecting) {
      appLogger.d(
        '[session-launch] reconnect skip session=${tab.info.id} '
        'reason=shell_active running=${shell.isRunning} '
        'connecting=${shell.isConnecting}',
      );
      _h.updateTabRunning(tab.info.id);
      return;
    }
    if (tab.membersPendingConnect.contains(effectiveMember.id)) {
      appLogger.d(
        '[session-launch] reconnect skip session=${tab.info.id} '
        'reason=pending member=${effectiveMember.id}',
      );
      return;
    }

    tab.membersPendingConnect.add(effectiveMember.id);
    final launched = session.launchState == AppSessionLaunchState.started;
    _h.beginSessionConnect(tab.info.id);
    _h.postFrameScheduler(() async {
      try {
        await _connectShell(
          tab: tab,
          session: session,
          shell: shell,
          repo: repo,
          launched: launched,
          team: isPersonal ? null : effectiveTeam,
          member: isPersonal ? null : effectiveMember,
          workspace: isPersonal ? workspace : null,
          personal: isPersonal ? personalIdentity : null,
        );
        if (!isPersonal &&
            effectiveTeam != null &&
            member != null &&
            _h.autoLaunchAllMembersOnConnect?.call() == true) {
          _launchRemainingMembersForTab(effectiveTeam, member.id, tab);
        }
        _h.updateTabRunning(tab.info.id);
      } on Object catch (e, st) {
        appLogger.e(
          '[session-launch] reconnect failed for ${tab.info.id}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to resume session: $e';
        shell.write('\r\n[$message]\r\n');
        unawaited(tab.closeMemberRemotePlane(effectiveMember.id));
        _h.failSessionConnect(tab.info.id, message);
      } finally {
        tab.membersPendingConnect.remove(effectiveMember.id);
      }
    });
  }

  Workspace? _workspaceById(String workspaceId) {
    for (final workspace in _state.workspaces) {
      if (workspace.workspaceId == workspaceId) return workspace;
    }
    return null;
  }

  Future<SshMemberSession?> _beginRemoteMemberSshSession({
    required ChatTab tab,
    required String memberKey,
    required RuntimeTarget launchTarget,
  }) async {
    if (launchTarget.kind != RuntimeKind.ssh) return null;
    final factory = _h.shellFactory.transportFactory?.sshClientFactory;
    final profile = _h.shellFactory.profileFor(launchTarget);
    if (factory == null || profile == null) return null;

    await tab.closeMemberRemotePlane(memberKey);

    final session = await SshMemberSession.open(factory, profile);
    tab.memberSshSessions[memberKey] = session;
    return session;
  }

  WorkspaceLaunchContext _launchContextFor(AppSession session) =>
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

  RuntimeTarget _launchWorkTarget(
    AppSession session, {
    String? memberId,
  }) =>
      _h.lifecycle.launchWorkTarget(
        _launchContextFor(session),
        memberId: memberId,
      );

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
            _scheduleMemberConnect(team, member, tab);
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
    _scheduleMemberConnect(team, member, tab);
  }

  /// Persists the CLI-native resume id the launch plan resolved (cursor
  /// pre-allocated chat id; codex/opencode captured ids), so the next open
  /// resumes precisely. Updates both disk **and** the in-memory session/tab —
  /// otherwise a same-run reconnect/reopen would pass a stale session and the
  /// strategy would re-allocate (losing the conversation). No-op for
  /// clientPinned CLIs, local-only sessions, and when already recorded.
  Future<void> _persistNativeSessionId(
    SessionRepository? repo,
    ChatTab tab,
    AppSession session,
    SessionMemberBinding? binding,
    LaunchPlan plan,
  ) async {
    final id = plan.nativeSessionIdToPersist?.trim() ?? '';
    final tool = plan.toolValue?.trim() ?? '';
    final r = repo ?? _h.sessionRepository;
    if (r == null ||
        id.isEmpty ||
        tool.isEmpty ||
        session.sessionId.startsWith('local-')) {
      return;
    }

    AppSession applyNative(AppSession s) {
      if (binding != null) {
        return s.copyWith(
          members: [
            for (final m in s.members)
              if (m.rosterMemberId == binding.rosterMemberId)
                m.withNativeSessionId(tool, id)
              else
                m,
          ],
        );
      }
      return s.withNativeSessionId(tool, id);
    }

    // Already recorded in memory (e.g. true resume) → nothing to do.
    final current = tab.persistedSession ?? session;
    if (identical(applyNative(current), current)) return;

    try {
      await r.recordNativeSessionId(
        session.sessionId,
        tool: tool,
        nativeId: id,
        rosterMemberId: binding?.rosterMemberId,
      );
    } on Object catch (e, st) {
      appLogger.w(
        '[session] persist native session id failed: $e',
        error: e,
        stackTrace: st,
      );
      return;
    }
    if (_h.isClosed) return;

    tab.persistedSession = applyNative(current);
    final sessions = _state.sessions
        .map((s) => s.sessionId == session.sessionId ? applyNative(s) : s)
        .toList();
    _h.emitSnapshot(
      _h.dataStore.deriveSnapshot(
        workspaces: _state.workspaces,
        sessions: sessions,
      ),
    );
  }

  Future<void> _persistSessionStarted(
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.markSessionLaunched(sessionId);
    if (_h.isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessions = _state.sessions.map((s) {
      if (s.sessionId != sessionId) return s;
      return s.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }).toList();
    _h.emitSnapshot(
      _h.dataStore.deriveSnapshot(
        workspaces: _state.workspaces,
        sessions: sessions,
      ),
    );
  }

  Future<SessionMemberBinding> _resolveMemberBinding({
    required AppSession session,
    required TeamMemberConfig member,
    required ChatTab tab,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _h.sessionRepository;
    final isLocal = session.sessionId.startsWith('local-');
    if (r != null && !isLocal) {
      return r.ensureMemberBinding(session.sessionId, member.id);
    }
    final existing = session.bindingFor(member.id);
    if (existing != null) return existing;
    final binding = SessionMemberBinding(
      rosterMemberId: member.id,
      taskId: _uuid.v4(),
    );
    tab.persistedSession = session.copyWith(
      members: [...session.members, binding],
    );
    return binding;
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
          cliTeamName: tab.cliTeamName,
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
  ) =>
      _scheduleMemberConnect(team, member, tab);

  Future<void> _connectMemberShell({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
  }) => _connectShell(
    tab: tab,
    session: session,
    shell: shell,
    repo: repo,
    launched: launched,
    team: team,
    member: member,
  );

  Future<void> _connectShell({
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
    TeamProfile? team,
    TeamMemberConfig? member,
    Workspace? workspace,
    PersonalProfile? personal,
  }) async {
    final isPersonal = workspace != null;
    final memberLabel = isPersonal ? session.sessionId : (member?.id ?? '');
    appLogger.i(
      '[session-launch] connectShell start '
      'session=${tab.info.id} member=$memberLabel personal=$isPersonal '
      'launched=$launched',
    );
    if (isPersonal) {
      if (personal == null) {
        appLogger.w(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=missing_personal_identity',
        );
        _h.failSessionConnect(
          tab.info.id,
          'Personal session is missing personal identity.',
        );
        return;
      }
    } else if (team == null || member == null) {
      appLogger.w(
        '[session-launch] connectShell aborted session=${tab.info.id} '
        'reason=missing_team_or_member',
      );
      _h.failSessionConnect(
        tab.info.id,
        'Team session requires team and member to connect.',
      );
      return;
    }

    if (team != null) {
      if (session.cliTeamName.isEmpty) {
        appLogger.w(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=missing_cli_team_name',
        );
        _h.failSessionConnect(
          tab.info.id,
          'Session is missing CLI team identity (cliTeamName). '
          'Create a new team session.',
        );
        return;
      }
      if (!session.sessionId.startsWith('local-') && session.members.isEmpty) {
        appLogger.w(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=missing_member_bindings',
        );
        _h.failSessionConnect(
          tab.info.id,
          'Session is missing member task bindings. Create a new team session.',
        );
        return;
      }
    }

    final activeSession = tab.persistedSession ?? session;
    final SessionMemberBinding? binding = team != null && member != null
        ? await _resolveMemberBinding(
            session: session,
            member: member,
            tab: tab,
            repo: repo,
          )
        : null;

    if (!_connectShellStillValid(tab: tab, shell: shell)) {
      _abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_after_member_binding',
      );
      return;
    }

    final launchMember = member;
    final launchCtx = _launchContextFor(activeSession);
    final rosterMemberId = binding?.rosterMemberId;
    final launchTarget = _h.lifecycle.launchWorkTarget(
      launchCtx,
      memberId: isPersonal ? null : (rosterMemberId ?? launchMember?.id),
    );
    final launchCli = isPersonal
        ? (activeSession.cli ?? CliTool.claude)
        : launchMember!.cliWithin(team!);
    final preflightMemberId = isPersonal
        ? activeSession.sessionId
        : (rosterMemberId ?? launchMember!.id);

    final sshMemberKey = preflightMemberId;
    String? remoteMemberKeyForRollback;
    try {
      final memberSshSession = await _beginRemoteMemberSshSession(
        tab: tab,
        memberKey: sshMemberKey,
        launchTarget: launchTarget,
      );
      if (memberSshSession != null) {
        remoteMemberKeyForRollback = sshMemberKey;
      }
      shell.sshMemberSession = memberSshSession;

    appLogger.d(
      '[session-launch] launch target resolved '
      'session=${tab.info.id} member=$preflightMemberId '
      'cli=${launchCli.value} target=${launchTarget.kind.name} '
      'targetId=${launchTarget.id}',
    );

    final mixedBus =
        team != null &&
        launchMember != null &&
        team.teamMode == TeamMode.mixed &&
        tab.mcpServer != null;
    // P3b (#1): a remote (ssh) member connects back to the in-process bus over a
    // reverse tunnel; the resolver returns its binding (relay/HTTP over tunnel),
    // or null for a local member (unchanged transport). Android-mixed fix.
    RemoteBusBinding? remoteBinding;
    String? remoteCliPath;
    ShellLaunchSpec shellLaunch;
    final launchWarnings = <String>[];

    if (isPersonal) {
      final connectResult = await _h.sessionConnect.preparePersonalConnect(
        session: activeSession,
        workspace: workspace!,
        personal: personal!,
        preset: await _h.lifecycle.resolveActivePresetForSession(
          activeSession,
          personal!,
        ),
        launchTarget: launchTarget,
      );
      shellLaunch = connectResult.shellLaunch;
      remoteCliPath = connectResult.remoteCliPath;
      launchWarnings.addAll(connectResult.warnings);
    } else {
      if (mixedBus && memberSshSession != null) {
        appLogger.d(
          '[session-launch] mixed bus remote setup start '
          'session=${tab.info.id} member=$preflightMemberId',
        );
        final resolver = _h.remoteBusResolver;
        if (resolver != null) {
          final workCtx = await _h.lifecycle.resolveWorkContextForTargetId(
            launchTarget.id,
          );
          final arch = archFromUname(await memberSshSession.run('uname -m'));
          final mount = buildRemoteBusMount(
            memberSession: memberSshSession,
            busServer: tab.mcpServer!,
            storageFs: workCtx.fs,
            arch: arch,
          );
          tab.memberRemoteBusMounts[preflightMemberId] = mount;
          remoteBinding = await resolver.bindMember(
            mount: mount,
            memberId: preflightMemberId,
            cli: launchCli,
          );
        }
      }
      final memberWork = activeSession.workDirsForMember(
        rosterMemberId ?? launchMember!.id,
        folders: _launchContextFor(activeSession).folderCatalog,
      );
      final connectResult = await _h.sessionConnect.prepareTeamConnect(
        session: activeSession,
        team: team!,
        member: launchMember!,
        memberBinding: binding,
        workspace: workspace,
        launchTarget: launchTarget,
        workingDirectory: memberWork.workingDirectory,
        additionalDirectories: memberWork.addDirs,
        extraMcpServers: mixedBus
            ? {
                teammateBusMcpServerName: _busMcpServerConfig(
                  endpoint: tab.mcpServer!.endpoint,
                  memberId: launchMember.id,
                  cli: launchMember.cliWithin(team),
                  remoteBinding: remoteBinding,
                ),
              }
            : null,
        busIdleUrl: mixedBus ? tab.mcpServer!.idleEndpoint.toString() : null,
      );
      shellLaunch = connectResult.shellLaunch;
      remoteCliPath = connectResult.remoteCliPath;
      launchWarnings.addAll(connectResult.warnings);
    }

    if (!_connectShellStillValid(tab: tab, shell: shell)) {
      _abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_after_prepare_connect',
        remoteMemberKey: remoteMemberKeyForRollback,
      );
      return;
    }

    if (launchTarget.kind == RuntimeKind.ssh) {
      final injectRootSandboxEnv = await TargetsRepository()
          .isRootSandboxEnvOptIn(launchTarget.id);
      shellLaunch = await applyRemoteSshLaunchConstraints(
        spec: shellLaunch,
        memberTarget: launchTarget,
        memberSession: memberSshSession,
        profile: _h.shellFactory.profileFor(launchTarget),
        injectRootSandboxEnv: injectRootSandboxEnv,
      );
    }

    if (!_connectShellStillValid(tab: tab, shell: shell)) {
      _abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_after_ssh_constraints',
        remoteMemberKey: remoteMemberKeyForRollback,
      );
      return;
    }

    final plan = shellLaunch.plan;
    appLogger.i(
      '[session-launch] launch plan ready '
      'session=${tab.info.id} member=$memberLabel '
      'resume=${plan.resume} create=${plan.createSessionId ?? ''} '
      'resumeId=${plan.resumeSessionId ?? ''} warnings=${plan.warnings.length}',
    );
    final configDir = plan.memberConfigDir.trim();
    if (configDir.isNotEmpty) {
      tab.memberToolConfigDir = configDir;
    }
    _h.emitLaunchWarnings([...launchWarnings, ...plan.warnings]);
    // The plan already resolved the native create/resume ids per CLI (incl.
    // cursor pre-allocation on first launch), so map them through directly —
    // no `launched` gating. See docs/session-resume-architecture.md.
    await _persistNativeSessionId(repo, tab, activeSession, binding, plan);

    if (!_connectShellStillValid(tab: tab, shell: shell)) {
      _abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_after_persist_native_id',
        remoteMemberKey: remoteMemberKeyForRollback,
      );
      return;
    }

    // P3a: the member runs in its assigned working directory (default = session
    // first folder). Personal sessions inherit (null memberId).
    final memberWork = activeSession.workDirsForMember(
      isPersonal ? null : binding?.rosterMemberId,
      folders: _launchContextFor(activeSession).folderCatalog,
    );
    appLogger.i(
      '[session-launch] shell.connect '
      'session=${tab.info.id} member=$memberLabel '
      'cwd=${memberWork.workingDirectory} addDirs=${memberWork.addDirs.length}',
    );
    shell.connect(
      workingDirectory: memberWork.workingDirectory,
      additionalDirectories: memberWork.addDirs,
      // P3c: off-home members launch the CLI at the preflight-located remote path.
      executableOverride: remoteCliPath,
      fixedSessionId: plan.createSessionId,
      resumeSessionId: plan.resumeSessionId,
      shellLaunch: shellLaunch,
      extraEnvironment: plan.env.isEmpty ? null : plan.env,
      busUserInputRouting: team != null && member != null
          ? _h.busCoordinator.busUserInputRouting(tab, team, member)
          : null,
      onFirstUserLineSubmitted: _autoRenameOnFirstPrompt(
        activeSession.sessionId,
      ),
      onEveryUserLineSubmitted: _autoTouchOnEveryPrompt(
        activeSession.sessionId,
      ),
      onProcessFailed: (message) {
        if (remoteMemberKeyForRollback != null) {
          unawaited(tab.closeMemberRemotePlane(remoteMemberKeyForRollback!));
        }
        _h.failSessionConnect(tab.info.id, message);
      },
      onProcessExited: () => _h.updateTabRunning(tab.info.id),
      onProcessStarted: () {
        if (team != null && member != null) {
          tab.teamBus?.markMemberRunning(member.id);
          _h.busCoordinator.markMemberReady(tab.info.id, member.id);
        }
        _h.clearLaunchError(tab.info.id);
        _h.finishSessionConnect(tab.info.id);
        final r = repo ?? _h.sessionRepository;
        if (r != null && !activeSession.sessionId.startsWith('local-')) {
          unawaited(
            _persistSessionStarted(r, activeSession.sessionId).onError(
              (e, st) => appLogger.w(
                '[session] persist after start failed: $e',
                error: e,
                stackTrace: st,
              ),
            ),
          );
        }
      },
    );
      remoteMemberKeyForRollback = null;
    } on Object catch (e, st) {
      if (remoteMemberKeyForRollback != null) {
        await tab.closeMemberRemotePlane(remoteMemberKeyForRollback!);
      }
      appLogger.e(
        '[session-launch] connectShell failed session=${tab.info.id} '
        'member=$memberLabel: $e',
        error: e,
        stackTrace: st,
      );
      _h.failSessionConnect(tab.info.id, 'Failed to connect session: $e');
    }
  }

  /// 选择 teammate-bus MCP 的传输方式（P3b：按成员 target + 能力位分流）。
  ///
  /// - **本地成员**：claude + 本地 PTY（native 后端）+ 桥接 exe 可解析 → stdio（经
  ///   `teammate_bus_bridge` 绕开 claude HTTP 的 ~6 分钟单请求死线，让
  ///   `wait_for_message` 真正阻塞）；其余回落到 HTTP（不破坏现状）。
  /// - **远程成员**（[remoteBinding] 非空，target 为 ssh）：长阻塞 CLI
  ///   （claude/flashskyai/codex/opencode）→ relay-over-tunnel（stdio↔127.0.0.1:<P>，
  ///   带 token 握手）；cursor（门铃式）→ HTTP-over-tunnel（127.0.0.1:<P> + token header）。
  ///   远程成员配置指向**隧道端口 <P>**而非远端够不到的裸 loopback——即 Android mixed 修点。
  Map<String, Object?> _busMcpServerConfig({
    required Uri endpoint,
    required String memberId,
    required CliTool cli,
    RemoteBusBinding? remoteBinding,
  }) {
    final longBlocking = CliToolRegistry.builtIn()
            .capability<BusTransportCapability>(cli)
            ?.longBlockingWaitForMessage ??
        true;
    String? localBridge;
    if (remoteBinding == null) {
      final localNative = !AppStorage.isInstalled ||
          AppStorage.context.mode == StorageBackendMode.native;
      if (cli == CliTool.claude && localNative) {
        localBridge = BusBridgeLocator.resolve();
      }
    }
    return buildMemberBusMcpConfig(
      memberId: memberId,
      localEndpoint: endpoint,
      longBlocking: longBlocking,
      localStdioBridgePath: localBridge,
      remote: remoteBinding,
    );
  }

  TerminalSession _memberShellForConnect({
    required ChatTab tab,
    required TeamProfile team,
    required TeamMemberConfig member,
    AppSession? session,
  }) {
    final activeSession = session ?? tab.persistedSession;
    if (activeSession == null) {
      return tab.memberShells.putIfAbsent(
        member.id,
        () => _h.shellFactory.newSession(member.cliWithin(team)),
      );
    }
    return _shellForLaunch(
      tab: tab,
      shellKey: member.id,
      cli: member.cliWithin(team),
      session: activeSession,
      rosterMemberId: member.id,
    );
  }

  void _scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab,
  ) {
    appLogger.i(
      '[session-launch] scheduleMemberConnect '
      'session=${tab.info.id} member=${member.id} team=${team.id}',
    );
    tab.selectedMemberId = member.id;
    final session =
        tab.persistedSession ?? _sessionForMemberConnect(tab, team);
    final shell = _memberShellForConnect(
      tab: tab,
      team: team,
      member: member,
      session: session,
    );
    _h.applyState(
      _state.copyWith(
        tabs: _tabStore.toInfos(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
      ),
    );
    if (shell.isRunning || shell.isConnecting) {
      appLogger.d(
        '[session-launch] scheduleMemberConnect skip '
        'session=${tab.info.id} member=${member.id} '
        'reason=shell_active running=${shell.isRunning} '
        'connecting=${shell.isConnecting}',
      );
      _h.updateTabRunning(tab.info.id);
      return;
    }
    if (tab.membersPendingConnect.contains(member.id)) {
      appLogger.d(
        '[session-launch] scheduleMemberConnect skip '
        'session=${tab.info.id} member=${member.id} reason=pending',
      );
      return;
    }
    tab.membersPendingConnect.add(member.id);
    _tabStore.workingDirectoryAndAddDirsForTab(
      tab,
      _state.sessions,
      workspaces: _state.workspaces,
    );
    _h.beginSessionConnect(tab.info.id);
    _h.postFrameScheduler(() async {
      try {
        if (shell.isRunning) {
          _h.finishSessionConnect(tab.info.id);
          return;
        }
        final session = _sessionForMemberConnect(tab, team);
        if (session == null) {
          _h.failSessionConnect(
            tab.info.id,
            'No persisted session for this tab. Create a team session first.',
          );
          return;
        }
        await _connectMemberShell(
          tab: tab,
          session: session,
          team: team,
          member: member,
          shell: shell,
          launched: session.launchState == AppSessionLaunchState.started,
        );
        _h.updateTabRunning(tab.info.id);
      } on Object catch (e, st) {
        appLogger.e(
          '[session-launch] member connect failed for ${member.name}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to start session: $e';
        shell.write('\r\n[$message]\r\n');
        _h.failSessionConnect(tab.info.id, message);
      } finally {
        tab.membersPendingConnect.remove(member.id);
      }
    });
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
      return;
    }
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    for (final member in validMembers) {
      _scheduleMemberConnect(team, member, tab);
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
          _h.shellFactory.cliForMember(team, memberId),
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
    await openSessionTab(session, repo: r, connectImmediately: true);
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

  void Function(String line)? _autoRenameOnFirstPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    final repo = _h.sessionRepository;
    if (repo == null) return null;
    return (line) {
      unawaited(_maybeAutoRenameSessionFromFirstPrompt(repo, sessionId, line));
    };
  }

  /// Bumps session updatedAt on every user-submitted line (debounced per
  /// session: at most once every 5 seconds). Called from the PTY engine output
  /// listener via [EveryUserLineCapture].
  void Function(String line)? _autoTouchOnEveryPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    final repo = _h.sessionRepository;
    if (repo == null) return null;
    return (line) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastTouchTimes[sessionId] ?? 0;
      if (now - last < 5000) return;
      _lastTouchTimes[sessionId] = now;
      unawaited(repo.touchSession(sessionId));
      // Lightweight in-memory update — no full disk reload.
      if (_h.isClosed) return;
      _h.applyState(_state.copyWith(
        sessions: _state.sessions.map((s) {
          if (s.sessionId != sessionId) return s;
          return s.copyWith(updatedAt: now);
        }).toList(),
      ));
    };
  }

  Future<void> _maybeAutoRenameSessionFromFirstPrompt(
    SessionRepository repo,
    String sessionId,
    String firstPrompt,
  ) async {
    if (_h.isClosed) return;
    AppSession? session;
    for (final s in _state.sessions) {
      if (s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    if (session == null || session.display.trim().isNotEmpty) return;
    final title = deriveSessionTitleFromFirstPrompt(firstPrompt);
    if (title.isEmpty) return;
    await _h.renameSession(repo, sessionId, title);
  }

  ChatTab _appendLocalTab(TeamProfile team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
    if (emitChange) {
      _h.applyState(
        _state.copyWith(
          tabs: _tabStore.toInfos(),
          activeTabIndex: _tabStore.length - 1,
          activeSessionId: tab.info.id,
          selectedMemberId: tab.selectedMemberId,
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
