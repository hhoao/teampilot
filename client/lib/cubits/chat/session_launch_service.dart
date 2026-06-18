import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/member_instance.dart';
import '../../models/personal_identity.dart';
import '../../services/storage/identity_provisioner.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/registry/config_profile/config_profile_context.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/team/default_team_project_service.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../services/storage/runtime_storage_context.dart';
import '../../services/team_bus/mcp/bus_bridge_locator.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logger.dart';
import '../../utils/project_path_utils.dart';
import '../../utils/session_display_title.dart';
import '../../utils/team_member_naming.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';
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
  Future<void> loadProjectData(SessionRepository repo);
  void pushPresenceTarget();

  ChatTab? get activeTab;
  set activeTeam(TeamIdentity? team);

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

  Future<void> openSessionTab(
    AppSession session, {
    TeamIdentity? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
    String emptyDisplayTitleFallback = 'New Chat',
    bool connectImmediately = true,
  }) async {
    final existingIdx = _tabStore.indexOfSession(session.sessionId);
    if (existingIdx != -1) {
      final existing = _tabStore.tabs[existingIdx];
      final memberId = member?.id ?? existing.selectedMemberId;
      _h.applyState(
        _state.copyWith(
          activeTabIndex: existingIdx,
          activeSessionId: session.sessionId,
          selectedMemberId: memberId,
        ),
      );
      return;
    }
    final project = _projectById(session.projectId);
    final isPersonal = session.sessionTeam.trim().isEmpty;
    PersonalIdentity? personalIdentity;
    TeamMemberConfig? personalMember;
    CliPreset? personalPreset;
    if (isPersonal) {
      if (project == null) {
        throw StateError(
          'openSessionTab requires project for personal sessions',
        );
      }
      // Prefer the identity the session was created under (persisted on the
      // session), then the project's remembered default, then the default
      // personal. Validate existence so a deleted identity falls back cleanly.
      var identityId = session.identityId.trim();
      if (identityId.isEmpty) {
        identityId = project.defaultIdentityId.trim();
      }
      if (identityId.isEmpty) {
        identityId = IdentityProvisioner.defaultPersonalId;
      } else if (await _h.lifecycle.loadIdentity(identityId) == null) {
        identityId = IdentityProvisioner.defaultPersonalId;
      }
      personalIdentity = await _h.lifecycle.loadPersonalIdentity(identityId);
      personalPreset =
          await _h.lifecycle.resolveActivePresetForPersonal(personalIdentity);
      personalMember = standaloneMemberFromPersonal(
        personalIdentity,
        preset: personalPreset,
      );
    }
    if (!isPersonal && (team == null || member == null)) {
      throw StateError(
        'openSessionTab requires team and member for non-personal sessions',
      );
    }
    final effectiveMember = isPersonal ? personalMember! : member!;
    final effectiveTeam = isPersonal ? null : team;
    final ts = _h.shellFactory.newSession(
      isPersonal
          // Honor the session's pinned CLI so an existing simple-mode session
          // resumes under the CLI it was created with, even when the project's
          // active preset has since been switched to another CLI.
          ? (session.cli ?? personalPreset?.cli ?? CliTool.claude)
          : member!.cliWithin(team!),
    );
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.resolveDisplayTitle(emptyDisplayTitleFallback),
      subtitle: session.primaryPath,
    );
    final launched = session.launchState == AppSessionLaunchState.started;
    final cliTeamName = session.cliTeamName;
    final internalTab = ChatTab(info: info, cliTeamName: cliTeamName)
      ..persistedSession = session;
    internalTab.memberShells[effectiveMember.id] = ts;
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
      // Non-blocking pre-launch config check: warn (via dialog) when the team
      // lacks a usable provider/model (and CLI, in mixed mode). Runs async (it
      // reads the provider catalog to waive model for official providers) and
      // must not delay the connect, so it is fire-and-forget.
      unawaited(_emitTeamConfigValidation(effectiveTeam));
      if (effectiveTeam.teamMode == TeamMode.mixed) {
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
      _h.beginSessionConnect(info.id);
      _h.postFrameScheduler(() async {
        try {
          await _connectShell(
            tab: internalTab,
            session: session,
            shell: ts,
            repo: repo,
            launched: launched,
            team: isPersonal ? null : team,
            member: isPersonal ? null : member,
            project: isPersonal ? project : null,
            personal: isPersonal ? personalIdentity : null,
          );
          if (!isPersonal &&
              _h.autoLaunchAllMembersOnConnect?.call() == true) {
            _launchRemainingMembersForTab(team!, member!.id, internalTab);
          }
          _h.updateTabRunning(info.id);
        } on Object catch (e, st) {
          appLogger.e(
            '[session] prepareLaunch/connect failed for ${info.id}: $e',
            error: e,
            stackTrace: st,
          );
          final message = 'Failed to resume session: $e';
          ts.write('\r\n[$message]\r\n');
          _h.failSessionConnect(info.id, message);
        }
      });
    } else {
      _h.updateTabRunning(info.id);
    }
  }

  Future<void> _emitTeamConfigValidation(TeamIdentity team) async {
    if (_h.isClosed) return;
    final validation = await _teamConfigValidator.validate(team);
    if (_h.isClosed) return;
    _h.emitTeamConfigValidation(validation);
  }

  void _launchRemainingMembersForTab(
    TeamIdentity team,
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
    TeamIdentity team,
    SessionRepository repo, {
    required bool connectImmediately,
    required TeamMemberConfig memberForInitialShell,
    String? workspaceCwd,
  }) async {
    if (!_tabStore.isEmpty) return;

    final existingSession = _existingSessionForMaterialize(
      team,
      workspaceCwd: workspaceCwd,
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

    final primaryPath = _materializePrimaryPath(team, workspaceCwd: workspaceCwd);
    final project = await repo.createProject(primaryPath);
    var session = _firstSessionForProject(project.projectId);
    session ??= await repo.createSession(
      project.projectId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    await _h.loadProjectData(repo);
    if (_h.isClosed) return;
    await openSessionTab(
      session,
      team: team,
      member: memberForInitialShell,
      repo: repo,
      connectImmediately: connectImmediately,
    );
  }

  AppSession? _existingSessionForMaterialize(
    TeamIdentity team, {
    String? workspaceCwd,
  }) {
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      final project = _projectMatchingPath(workspaceCwd);
      if (project != null) {
        final session = _firstSessionForProjectAndTeam(
          project.projectId,
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

  String _materializePrimaryPath(TeamIdentity team, {String? workspaceCwd}) {
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      return normalizeProjectPath(workspaceCwd);
    }
    return DefaultTeamProjectService.primaryPathForTeam(team.id);
  }

  AppProject? _projectMatchingPath(String primaryPath) {
    for (final project in _state.projects) {
      if (projectPathsEqual(project.primaryPath, primaryPath)) return project;
    }
    return null;
  }

  AppSession? _firstSessionForProjectAndTeam(String projectId, String teamId) {
    for (final session in _state.sessions) {
      if (session.projectId != projectId) continue;
      if (session.sessionTeam.trim() != teamId) continue;
      return session;
    }
    return null;
  }

  AppProject? _projectById(String projectId) {
    for (final project in _state.projects) {
      if (project.projectId == projectId) return project;
    }
    return null;
  }

  AppSession? _firstSessionForProject(String projectId) {
    for (final session in _state.sessions) {
      if (session.projectId == projectId) return session;
    }
    return null;
  }

  Future<void> openMemberTab(
    TeamIdentity team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) async {
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
        projects: _state.projects,
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
        projects: _state.projects,
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

  AppSession? _sessionForMemberConnect(ChatTab tab, TeamIdentity team) {
    final cached = _tabStore.sessionForTab(tab, _state.sessions);
    if (cached != null) return cached;
    if (!tab.info.id.startsWith('local-')) return null;
    final launch = _tabStore.workingDirectoryAndAddDirsForTab(
      tab,
      _state.sessions,
    );
    final session =
        tab.persistedSession ??
        AppSession(
          sessionId: tab.info.id,
          projectId: '',
          primaryPath: launch.$1,
          additionalPaths: launch.$2,
          sessionTeam: team.id,
          cliTeamName: tab.cliTeamName,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
    tab.persistedSession = session;
    return session;
  }

  @override
  void scheduleMemberConnect(
    TeamIdentity team,
    TeamMemberConfig member,
    ChatTab tab,
  ) =>
      _scheduleMemberConnect(team, member, tab);

  Future<void> _connectMemberShell({
    required ChatTab tab,
    required AppSession session,
    required TeamIdentity team,
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
    TeamIdentity? team,
    TeamMemberConfig? member,
    AppProject? project,
    PersonalIdentity? personal,
  }) async {
    final isPersonal = project != null;
    if (isPersonal) {
      if (personal == null) {
        _h.failSessionConnect(
          tab.info.id,
          'Personal session is missing personal identity.',
        );
        return;
      }
    } else if (team == null || member == null) {
      _h.failSessionConnect(
        tab.info.id,
        'Team session requires team and member to connect.',
      );
      return;
    }

    if (team != null) {
      if (session.cliTeamName.isEmpty) {
        _h.failSessionConnect(
          tab.info.id,
          'Session is missing CLI team identity (cliTeamName). '
          'Create a new team session.',
        );
        return;
      }
      if (!session.sessionId.startsWith('local-') && session.members.isEmpty) {
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

    final launchMember = member;
    final mixedBus =
        team != null &&
        launchMember != null &&
        team.teamMode == TeamMode.mixed &&
        tab.mcpServer != null;
    final shellLaunch = await _h.lifecycle.prepareShellLaunch(
      session: activeSession,
      team: team,
      member: launchMember,
      memberBinding: binding,
      project: project,
      personal: personal,
      extraMcpServers: mixedBus
          ? {
              teammateBusMcpServerName: _busMcpServerConfig(
                endpoint: tab.mcpServer!.endpoint,
                memberId: launchMember.id,
                cli: launchMember.cliWithin(team),
              ),
            }
          : null,
      busIdleUrl: mixedBus ? tab.mcpServer!.idleEndpoint.toString() : null,
    );
    final plan = shellLaunch.plan;
    final configDir = plan.memberConfigDir.trim();
    if (configDir.isNotEmpty) {
      tab.memberToolConfigDir = configDir;
    }
    _h.emitLaunchWarnings(plan.warnings);
    // The plan already resolved the native create/resume ids per CLI (incl.
    // cursor pre-allocation on first launch), so map them through directly —
    // no `launched` gating. See docs/session-resume-architecture.md.
    await _persistNativeSessionId(repo, tab, activeSession, binding, plan);
    shell.connect(
      workingDirectory: activeSession.primaryPath,
      additionalDirectories: activeSession.additionalPaths,
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
      onProcessFailed: (message) => _h.failSessionConnect(tab.info.id, message),
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
  }

  /// 选择 teammate-bus MCP 的传输方式。claude + 本地 PTY（native 后端）+ 桥接 exe
  /// 可解析 → stdio（经 `teammate_bus_bridge` 绕开 claude HTTP 的 ~6 分钟单请求死线，
  /// 让 `wait_for_message` 真正阻塞、不再 transport dropped）。其余情况（非 claude、
  /// SSH/WSL 远端够不到本地 loopback、或桥接未随包分发）回落到 HTTP，不破坏现状。
  Map<String, Object?> _busMcpServerConfig({
    required Uri endpoint,
    required String memberId,
    required CliTool cli,
  }) {
    final localNative = !RuntimeStorageContext.isInstalled ||
        RuntimeStorageContext.current.mode == StorageBackendMode.native;
    if (cli == CliTool.claude && localNative) {
      final bridge = BusBridgeLocator.resolve();
      if (bridge != null) {
        return teammateBusMcpServerConfigStdio(
          bridgePath: bridge,
          endpoint: endpoint,
          memberId: memberId,
        );
      }
    }
    return teammateBusMcpServerConfig(endpoint: endpoint, memberId: memberId);
  }

  void _scheduleMemberConnect(
    TeamIdentity team,
    TeamMemberConfig member,
    ChatTab tab,
  ) {
    tab.selectedMemberId = member.id;
    final shell = tab.memberShells.putIfAbsent(
      member.id,
      () => _h.shellFactory.newSession(member.cliWithin(team)),
    );
    _h.applyState(
      _state.copyWith(
        tabs: _tabStore.toInfos(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
      ),
    );
    if (shell.isRunning || shell.isConnecting) {
      _h.updateTabRunning(tab.info.id);
      return;
    }
    if (tab.membersPendingConnect.contains(member.id)) {
      return;
    }
    tab.membersPendingConnect.add(member.id);
    _tabStore.workingDirectoryAndAddDirsForTab(tab, _state.sessions);
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
          '[session] prepareLaunch/connect failed for member ${member.name}: $e',
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
    TeamIdentity team, {
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

  TerminalSession? ensureSession(TeamIdentity team) {
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

  Future<void> connectSession(
    TeamIdentity team, {
    SessionRepository? repo,
  }) async {
    if (_state.isActiveSessionConnecting) return;

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
    await openMemberTab(team, member, repo: r);
  }

  void disconnectSession() {
    final tab = _activeTab;
    if (tab == null) return;
    tab.membersPendingConnect.remove(tab.selectedMemberId);
    tab.memberShells[tab.selectedMemberId]?.disconnect();
    _h.clearLaunchError(tab.info.id);
    _h.updateTabRunning(tab.info.id);
  }

  Future<void> restartSession(
    TeamIdentity team, {
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
        _h.updateTabRunning(tab.info.id);
      }
      await launchAllMembers(team, repo: r);
      if (keepId.isNotEmpty && team.members.any((m) => m.id == keepId)) {
        _h.selectMember(keepId);
      }
      return;
    }
    disconnectSession();
    await connectSession(team, repo: r);
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

  ChatTab _appendLocalTab(TeamIdentity team, {required bool emitChange}) {
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
    TeamIdentity team, {
    required bool emitChange,
  }) {
    final existing = _activeTab;
    if (existing != null) return existing;
    return _appendLocalTab(team, emitChange: emitChange);
  }
}
