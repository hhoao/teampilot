import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/team/default_team_project_service.dart';
import '../../services/team/team_config_launch_validator.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logger.dart';
import '../../utils/project_path_utils.dart';
import '../../utils/session_display_title.dart';
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
  set activeTeam(TeamConfig? team);

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

  ChatState get _state => _h.state;
  ChatTabStore get _tabStore => _h.tabStore;
  ChatTab? get _activeTab => _h.activeTab;

  Future<void> openSessionTab(
    AppSession session, {
    TeamConfig? team,
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
    final ts = _h.shellFactory.newSession(
      team != null && member != null
          ? member.cliWithin(team)
          : (team?.cli ?? TeamCli.flashskyai),
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
    if (team != null && member != null) {
      internalTab.memberShells[member.id] = ts;
      internalTab.selectedMemberId = member.id;
    } else {
      internalTab.resumeSession = ts;
    }
    _tabStore.append(internalTab);
    _h.applyState(
      _state.copyWith(
        tabs: [..._state.tabs, info],
        activeTabIndex: _tabStore.length - 1,
        activeSessionId: session.sessionId,
        selectedMemberId: internalTab.selectedMemberId,
      ),
    );
    if (team != null) {
      _h.activeTeam = team;
      _h.pushPresenceTarget();
      // Non-blocking pre-launch config check: warn (via dialog) when the team
      // lacks a usable provider/model (and CLI, in mixed mode). Runs async (it
      // reads the provider catalog to waive model for official providers) and
      // must not delay the connect, so it is fire-and-forget.
      unawaited(_emitTeamConfigValidation(team));
      if (team.teamMode == TeamMode.mixed) {
        await _h.busCoordinator.installBusForTab(internalTab, team, session);
      }
    }
    // mixed：打开/恢复 tab 只建 bus + MCP，不 spawn PTY（等用户 connect 或 mailbox 物化）。
    final connectNow = connectImmediately && team?.teamMode != TeamMode.mixed;
    if (connectNow) {
      _h.beginSessionConnect(info.id);
      _h.postFrameScheduler(() async {
        try {
          if (team != null && member != null) {
            await _connectMemberShell(
              tab: internalTab,
              session: session,
              team: team,
              member: member,
              shell: ts,
              repo: repo,
              launched: launched,
            );
            if (_h.autoLaunchAllMembersOnConnect?.call() == true) {
              _launchRemainingMembersForTab(team, member.id, internalTab);
            }
          } else {
            final plan = await _h.lifecycle.prepareLaunch(
              session: session,
              team: team,
              member: member,
            );
            final configDir = plan.memberConfigDir.trim();
            if (configDir.isNotEmpty) {
              internalTab.memberToolConfigDir = configDir;
            }
            _h.emitLaunchWarnings(plan.warnings);
            final useResume = launched && plan.resume;
            ts.connect(
              workingDirectory: session.primaryPath,
              additionalDirectories: session.additionalPaths,
              fixedSessionId: useResume ? null : plan.taskId,
              resumeSessionId: useResume ? plan.taskId : null,
              team: team,
              member: member,
              sessionTeam: cliTeamName.isNotEmpty ? cliTeamName : null,
              extraEnvironment: plan.env.isEmpty ? null : plan.env,
              onFirstUserLineSubmitted: _autoRenameOnFirstPrompt(
                session.sessionId,
              ),
              onProcessFailed: (message) =>
                  _h.failSessionConnect(info.id, message),
              onProcessExited: () => _h.updateTabRunning(info.id),
              onProcessStarted: () {
                _h.clearLaunchError(info.id);
                _h.finishSessionConnect(info.id);
                if (repo == null) return;
                unawaited(
                  _persistSessionStarted(repo, session.sessionId).onError(
                    (e, st) => appLogger.w(
                      '[session] persist after start failed: $e',
                      error: e,
                      stackTrace: st,
                    ),
                  ),
                );
              },
            );
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

  Future<void> _emitTeamConfigValidation(TeamConfig team) async {
    if (_h.isClosed) return;
    final validation = await _teamConfigValidator.validate(team);
    if (_h.isClosed) return;
    _h.emitTeamConfigValidation(validation);
  }

  void _launchRemainingMembersForTab(
    TeamConfig team,
    String keepSelectedMemberId,
    ChatTab tab,
  ) {
    for (final candidate in team.members.where((m) => m.isValid)) {
      if (candidate.id == keepSelectedMemberId) continue;
      _scheduleMemberConnect(team, candidate, tab);
    }
    if (team.members.any((m) => m.id == keepSelectedMemberId)) {
      _h.selectMember(keepSelectedMemberId);
    }
  }

  Future<void> _materializeDefaultWorkspaceSession(
    TeamConfig team,
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
    final project = await repo.createProject(primaryPath, teamId: team.id);
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
    TeamConfig team, {
    String? workspaceCwd,
  }) {
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      final project = _projectMatchingPath(workspaceCwd, teamId: team.id);
      if (project != null) {
        final session = _firstSessionForProject(project.projectId);
        if (session != null) return session;
      }
    }
    for (final session in _state.sessions) {
      final project = _projectById(session.projectId);
      if (project?.teamId == team.id) return session;
    }
    return null;
  }

  String _materializePrimaryPath(TeamConfig team, {String? workspaceCwd}) {
    if (workspaceCwd != null && workspaceCwd.trim().isNotEmpty) {
      return normalizeProjectPath(workspaceCwd);
    }
    return DefaultTeamProjectService.primaryPathForTeam(team.id);
  }

  AppProject? _projectMatchingPath(String primaryPath, {required String teamId}) {
    for (final project in _state.projects) {
      if (project.teamId != teamId) continue;
      if (projectPathsEqual(project.primaryPath, primaryPath)) return project;
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
    TeamConfig team,
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

  AppSession? _sessionForMemberConnect(ChatTab tab, TeamConfig team) {
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
    TeamConfig team,
    TeamMemberConfig member,
    ChatTab tab,
  ) =>
      _scheduleMemberConnect(team, member, tab);

  Future<void> _connectMemberShell({
    required ChatTab tab,
    required AppSession session,
    required TeamConfig team,
    required TeamMemberConfig member,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
  }) async {
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
    final binding = await _resolveMemberBinding(
      session: session,
      member: member,
      tab: tab,
      repo: repo,
    );
    final activeSession = tab.persistedSession ?? session;
    final plan = await _h.lifecycle.prepareLaunch(
      session: activeSession,
      team: team,
      member: member,
      memberBinding: binding,
      extraMcpServers: team.teamMode == TeamMode.mixed && tab.mcpServer != null
          ? {
              teammateBusMcpServerName: teammateBusMcpServerConfig(
                endpoint: tab.mcpServer!.endpoint,
                memberId: member.id,
              ),
            }
          : null,
      busIdleUrl: team.teamMode == TeamMode.mixed && tab.mcpServer != null
          ? tab.mcpServer!.idleEndpoint.toString()
          : null,
    );
    final configDir = plan.memberConfigDir.trim();
    if (configDir.isNotEmpty) {
      tab.memberToolConfigDir = configDir;
    }
    _h.emitLaunchWarnings(plan.warnings);
    final useResume = launched && plan.resume;
    shell.connect(
      workingDirectory: activeSession.primaryPath,
      additionalDirectories: activeSession.additionalPaths,
      fixedSessionId: useResume ? null : plan.taskId,
      resumeSessionId: useResume ? plan.taskId : null,
      team: team,
      member: member,
      sessionTeam: activeSession.cliTeamName,
      extraEnvironment: plan.env.isEmpty ? null : plan.env,
      busUserInputRouting: _h.busCoordinator.busUserInputRouting(
        tab,
        team,
        member,
      ),
      onFirstUserLineSubmitted: _autoRenameOnFirstPrompt(
        activeSession.sessionId,
      ),
      onProcessFailed: (message) => _h.failSessionConnect(tab.info.id, message),
      onProcessExited: () => _h.updateTabRunning(tab.info.id),
      onProcessStarted: () {
        tab.teamBus?.markMemberRunning(member.id);
        _h.clearLaunchError(tab.info.id);
        _h.finishSessionConnect(tab.info.id);
        _h.busCoordinator.markMemberReady(tab.info.id, member.id);
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

  void _scheduleMemberConnect(
    TeamConfig team,
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
    TeamConfig team, {
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

  TerminalSession? ensureSession(TeamConfig team) {
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
    TeamConfig team, {
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
    TeamConfig team, {
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

  ChatTab _appendLocalTab(TeamConfig team, {required bool emitChange}) {
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
    TeamConfig team, {
    required bool emitChange,
  }) {
    final existing = _activeTab;
    if (existing != null) return existing;
    return _appendLocalTab(team, emitChange: emitChange);
  }
}
