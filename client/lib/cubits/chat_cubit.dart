import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/app_project.dart';
import '../models/connection_mode.dart';
import '../models/app_session.dart';
import '../models/session_member_binding.dart';
import '../models/launch_target.dart';
import '../models/ssh_profile.dart';
import '../models/member_presence.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/team/member_presence_service.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/team_bus/agent_node.dart';
import '../services/team_bus/chat_cubit_member_launcher.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../services/team_bus/team_bus.dart';
import '../services/terminal/terminal_session.dart';
import '../utils/team_member_naming.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../utils/logger.dart';
import '../utils/project_path_utils.dart';
import '../utils/session_display_title.dart';
import '../utils/session_launch_error.dart';

typedef TerminalSessionFactory = TerminalSession Function({
  required String executable,
  int scrollbackLines,
});

TerminalSession defaultTerminalSessionFactory({
  required String executable,
  int scrollbackLines = 10000,
}) {
  return TerminalSession(
    executable: executable,
    scrollbackLines: scrollbackLines,
  );
}

typedef PostFrameScheduler = void Function(VoidCallback callback);
typedef SshActiveProfileResolver = SshProfile? Function();
typedef CliExecutableResolver = String Function(TeamCli cli);

class ChatTabInfo extends Equatable {
  const ChatTabInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isRunning = false,
    this.launchError,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool isRunning;

  /// User-facing summary when the last connect attempt failed (placeholder P0).
  final String? launchError;

  ChatTabInfo copyWith({
    String? title,
    String? subtitle,
    bool? isRunning,
    String? launchError,
    bool clearLaunchError = false,
  }) {
    return ChatTabInfo(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isRunning: isRunning ?? this.isRunning,
      launchError: clearLaunchError
          ? null
          : (launchError ?? this.launchError),
    );
  }

  @override
  List<Object?> get props => [id, title, subtitle, isRunning, launchError];
}

class _InternalTab {
  _InternalTab({
    required this.info,
    required this.cliTeamName,
    this.selectedMemberId = '',
  });

  ChatTabInfo info;
  TerminalSession? resumeSession;
  String selectedMemberId;

  /// CLI `--team-name` and config-profiles runtime id ([AppSession.cliTeamName]).
  final String cliTeamName;

  /// Persisted session for team member connect (may be absent before index load).
  AppSession? persistedSession;

  /// Shared [LaunchPlan.memberConfigDir] from first successful member connect.
  String? memberToolConfigDir;

  final Map<String, TerminalSession> memberShells = {};

  /// mixed 模式：本 team 会话的进程内总线与其 loopback MCP server（随 tab 建/销）。
  TeamBus? teamBus;
  TeammateBusMcpServer? mcpServer;

  Future<void> disposeBus() async {
    teamBus?.abortAll();
    await mcpServer?.stop();
    teamBus = null;
    mcpServer = null;
  }

  /// Member ids with a scheduled or in-flight [_scheduleMemberConnect].
  final Set<String> membersPendingConnect = {};

  Iterable<TerminalSession> get sessions sync* {
    if (resumeSession != null) yield resumeSession!;
    yield* memberShells.values;
  }

  bool get isRunning => sessions.any((session) => session.isRunning);
}

class ChatState extends Equatable {
  const ChatState({
    this.tabs = const [],
    this.activeTabIndex = 0,
    this.projects = const [],
    this.sessions = const [],
    this.visibleProjects = const [],
    this.visibleSessions = const [],
    this.activeSessionId,
    this.selectedMemberId = '',
    this.stateVersion = 0,
    this.snackbarMessage,
    this.sessionConnectingId,
    this.sessionLaunchError,
    this.memberPresence = const {},
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final List<AppProject> projects;
  final List<AppSession> sessions;
  final List<AppProject> visibleProjects;
  final List<AppSession> visibleSessions;
  final String? activeSessionId;
  final String selectedMemberId;
  final int stateVersion;
  final String? snackbarMessage;

  /// Session id while prepareLaunch / terminal spawn is in progress.
  final String? sessionConnectingId;

  /// Launch error when connect fails before a tab exists (empty workbench).
  final String? sessionLaunchError;

  /// Per [TeamMemberConfig.id] for the members panel (active team session).
  final Map<String, MemberPresence> memberPresence;

  ChatState copyWith({
    List<ChatTabInfo>? tabs,
    int? activeTabIndex,
    List<AppProject>? projects,
    List<AppSession>? sessions,
    List<AppProject>? visibleProjects,
    List<AppSession>? visibleSessions,
    String? activeSessionId,
    String? selectedMemberId,
    bool clearActiveSessionId = false,
    int? stateVersion,
    String? snackbarMessage,
    bool clearSnackbarMessage = false,
    String? sessionConnectingId,
    bool clearSessionConnectingId = false,
    String? sessionLaunchError,
    bool clearSessionLaunchError = false,
    Map<String, MemberPresence>? memberPresence,
  }) {
    return ChatState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      projects: projects ?? this.projects,
      sessions: sessions ?? this.sessions,
      visibleProjects: visibleProjects ?? this.visibleProjects,
      visibleSessions: visibleSessions ?? this.visibleSessions,
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
      stateVersion: stateVersion ?? this.stateVersion,
      snackbarMessage: clearSnackbarMessage
          ? null
          : (snackbarMessage ?? this.snackbarMessage),
      sessionConnectingId: clearSessionConnectingId
          ? null
          : (sessionConnectingId ?? this.sessionConnectingId),
      sessionLaunchError: clearSessionLaunchError
          ? null
          : (sessionLaunchError ?? this.sessionLaunchError),
      memberPresence: memberPresence ?? this.memberPresence,
    );
  }

  bool get isActiveSessionConnecting {
    final id = sessionConnectingId;
    final active = activeSessionId;
    if (id == null || id.isEmpty) return false;
    if (id == 'pending') return true;
    if (active == null || active.isEmpty) return true;
    return id == active;
  }

  @override
  List<Object?> get props => [
    tabs,
    activeTabIndex,
    projects,
    sessions,
    visibleProjects,
    visibleSessions,
    activeSessionId,
    selectedMemberId,
    stateVersion,
    snackbarMessage,
    sessionConnectingId,
    sessionLaunchError,
    memberPresence,
  ];
}

class ChatCubit extends Cubit<ChatState> implements MemberMaterializer {
  ChatCubit({
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TerminalSessionFactory terminalSessionFactory =
        defaultTerminalSessionFactory,
    PostFrameScheduler? postFrameScheduler,
    bool Function()? autoLaunchAllMembersOnConnect,
    SessionLifecycleService? lifecycleService,
    SessionRepository? sessionRepository,
    TerminalTransportFactory? transportFactory,
    SshActiveProfileResolver? sshProfileResolver,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    ConnectionMode Function()? connectionModeResolver,
    int Function()? terminalScrollbackLinesResolver,
    MemberPresenceService? memberPresenceService,
  }) : _terminalSessionFactory = terminalSessionFactory,
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _lifecycle = lifecycleService ?? SessionLifecycleService(),
       _sessionRepository = sessionRepository,
       _executableResolver = executableResolver,
       _cliExecutableResolver = cliExecutableResolver,
       _transportFactory = transportFactory,
       _sshProfileResolver = sshProfileResolver,
       _sshDefaultWorkingDirectoryResolver = sshDefaultWorkingDirectoryResolver,
       _sshUseLoginShellResolver = sshUseLoginShellResolver,
       _connectionModeResolver = connectionModeResolver,
       _terminalScrollbackLinesResolver = terminalScrollbackLinesResolver,
       _memberPresenceService =
           memberPresenceService ?? MemberPresenceService(),
       super(const ChatState());

  final List<_InternalTab> _internalTabs = [];
  final MemberPresenceService _memberPresenceService;
  Timer? _presencePollTimer;
  TeamConfig? _presenceTeam;
  int _presencePollGeneration = 0;
  bool _presenceUiAttached = false;
  bool _presenceTickInFlight = false;
  Timer? _idleWatchTimer;
  final Map<String, bool> _lastWorking = {};
  var _scopeSessionsToSelectedTeam = false;
  String? _selectedTeamId;
  final TerminalSessionFactory _terminalSessionFactory;
  final PostFrameScheduler _postFrameScheduler;
  final bool Function()? _autoLaunchAllMembersOnConnect;
  final SessionLifecycleService _lifecycle;
  final SessionRepository? _sessionRepository;
  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final TerminalTransportFactory? _transportFactory;
  final SshActiveProfileResolver? _sshProfileResolver;
  final String Function()? _sshDefaultWorkingDirectoryResolver;
  final bool Function()? _sshUseLoginShellResolver;
  final ConnectionMode Function()? _connectionModeResolver;
  final int Function()? _terminalScrollbackLinesResolver;

  final Map<(String, String), Completer<void>> _memberReady = {};

  ConnectionMode get _connectionMode =>
      _connectionModeResolver?.call() ?? ConnectionMode.localPty;

  bool get _useSsh =>
      _connectionMode == ConnectionMode.ssh &&
      _transportFactory != null &&
      _sshProfileResolver != null &&
      _sshProfileResolver() != null;

  String _resolveExecutableFor(TeamCli cli) {
    return _cliExecutableResolver?.call(cli) ?? _executableResolver();
  }

  int get _scrollbackLines => _terminalScrollbackLinesResolver?.call() ?? 10000;

  TerminalSession _newSession([TeamCli cli = TeamCli.flashskyai]) {
    final executable = _resolveExecutableFor(cli);
    final scrollback = _scrollbackLines;
    if (_useSsh) {
      final profile = _sshProfileResolver?.call();
      if (profile == null) {
        return _terminalSessionFactory(
          executable: executable,
          scrollbackLines: scrollback,
        );
      }
      return TerminalSession(
        executable: executable,
        scrollbackLines: scrollback,
        validateLaunch: false,
        parseExecutable: false,
        transportStarter:
            (
              String executable, {
              required List<String> arguments,
              required String workingDirectory,
              required int columns,
              required int rows,
              Map<String, String>? environment,
            }) async {
              final remoteEnvironment = <String, String>{
                if (environment != null) ...environment,
              };
              final remoteWorkingDirectory = workingDirectory.isNotEmpty
                  ? workingDirectory
                  : (_sshDefaultWorkingDirectoryResolver?.call() ?? '');
              return _transportFactory!.startTransport(
                LaunchTarget.ssh(
                  sshProfileId: profile.id,
                  remoteExecutable: executable,
                  remoteWorkingDirectory: remoteWorkingDirectory,
                  remoteEnvironment: remoteEnvironment,
                  useLoginShell: _sshUseLoginShellResolver?.call() ?? false,
                ),
                arguments: arguments,
                columns: columns,
                rows: rows,
              );
            },
      );
    }
    return _terminalSessionFactory(
      executable: executable,
      scrollbackLines: scrollback,
    );
  }

  static const _uuid = Uuid();

  static void _defaultPostFrameScheduler(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  void setTeamSessionScope({
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    final normalized = (selectedTeamId != null && selectedTeamId.isNotEmpty)
        ? selectedTeamId
        : null;
    if (_scopeSessionsToSelectedTeam == scopeSessionsToSelectedTeam &&
        _selectedTeamId == normalized) {
      return;
    }
    _scopeSessionsToSelectedTeam = scopeSessionsToSelectedTeam;
    _selectedTeamId = normalized;
    _refreshVisibleLists();
  }

  List<AppSession> _computeVisibleSessions(List<AppSession> all) {
    if (!_scopeSessionsToSelectedTeam) return all;
    final tid = _selectedTeamId;
    if (tid == null || tid.isEmpty) return [];
    return all.where((s) => s.sessionTeam == tid).toList();
  }

  List<AppProject> _computeVisibleProjects(
    List<AppProject> all,
    List<AppSession> visibleSessions,
  ) {
    if (!_scopeSessionsToSelectedTeam) return all;
    return all
        .where((p) => visibleSessions.any((s) => s.projectId == p.projectId))
        .toList();
  }

  void _emitWithDerivedSessionsAndProjects(ChatState next) {
    final visS = _computeVisibleSessions(next.sessions);
    final visP = _computeVisibleProjects(next.projects, visS);
    emit(next.copyWith(visibleSessions: visS, visibleProjects: visP));
  }

  void _refreshVisibleLists() {
    final visS = _computeVisibleSessions(state.sessions);
    final visP = _computeVisibleProjects(state.projects, visS);
    emit(state.copyWith(visibleSessions: visS, visibleProjects: visP));
  }

  _InternalTab? get _activeTab {
    if (_internalTabs.isEmpty) return null;
    final index = state.activeTabIndex.clamp(0, _internalTabs.length - 1);
    return _internalTabs[index];
  }

  TerminalSession? get currentSession {
    final tab = _activeTab;
    if (tab == null) return null;
    final memberShell = tab.memberShells[tab.selectedMemberId];
    return memberShell ?? tab.resumeSession;
  }

  /// Session project path for the active tab (used to resolve relative file links).
  String get activeTabWorkingDirectory {
    final tab = _activeTab;
    if (tab == null) return AppStorage.cwd;
    return _workingDirectoryAndAddDirsForTab(tab).$1;
  }

  /// Last launch failure for the active tab, or [ChatState.sessionLaunchError].
  String? get activeLaunchError {
    if (_internalTabs.isNotEmpty) {
      final index = state.activeTabIndex.clamp(0, _internalTabs.length - 1);
      final error = _internalTabs[index].info.launchError;
      if (error != null && error.isNotEmpty) return error;
    }
    final pending = state.sessionLaunchError;
    if (pending != null && pending.isNotEmpty) return pending;
    return null;
  }

  Future<void> loadProjectData(SessionRepository repo) async {
    final projects = await repo.loadProjects();
    final sessions = await repo.loadSessions();
    _emitWithDerivedSessionsAndProjects(
      state.copyWith(projects: projects, sessions: sessions),
    );
  }

  /// Updates persisted-index mirrors in state and recomputes team-scoped sidebar lists.
  void ingestProjectSessionSnapshot({
    required List<AppProject> projects,
    required List<AppSession> sessions,
  }) {
    _emitWithDerivedSessionsAndProjects(
      state.copyWith(projects: projects, sessions: sessions),
    );
  }

  Future<AppSession> createSession(
    String projectId,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final session = await repo.createSession(
      projectId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
    );
    await loadProjectData(repo);
    return session;
  }

  Future<void> createProjectWithFirstSession(
    String primaryPath,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    List<String> additionalPaths = const [],
    String display = '',
  }) async {
    final project = await repo.createProject(
      primaryPath,
      additionalPaths: additionalPaths,
      display: display,
    );
    await repo.createSession(
      project.projectId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
    );
    await loadProjectData(repo);
  }

  Future<void> addProjectDirectory(
    SessionRepository repo,
    AppProject project,
    String directoryPath,
  ) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) return;
    if (projectPathsEqual(trimmed, project.primaryPath)) return;
    if (projectPathsContains(project.additionalPaths, trimmed)) return;
    await repo.createProject(project.primaryPath, additionalPaths: [trimmed]);
    await loadProjectData(repo);
  }

  Future<void> updateProjectMetadata(
    SessionRepository repo,
    String projectId, {
    String? display,
    List<String>? additionalPaths,
  }) async {
    await repo.updateProjectMetadata(
      projectId,
      display: display,
      additionalPaths: additionalPaths,
    );
    await loadProjectData(repo);
  }

  Future<void> openSessionTab(
    AppSession session, {
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
    String emptyDisplayTitleFallback = 'New Chat',
    bool connectImmediately = true,
  }) async {
    final existingIdx = _internalTabs.indexWhere(
      (t) => t.info.id == session.sessionId,
    );
    if (existingIdx != -1) {
      final existing = _internalTabs[existingIdx];
      final memberId = member?.id ?? existing.selectedMemberId;
      emit(
        state.copyWith(
          activeTabIndex: existingIdx,
          activeSessionId: session.sessionId,
          selectedMemberId: memberId,
        ),
      );
      return;
    }
    final ts = _newSession(team?.cli ?? TeamCli.flashskyai);
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.resolveDisplayTitle(emptyDisplayTitleFallback),
      subtitle: session.primaryPath,
    );
    final launched = session.launchState == AppSessionLaunchState.started;
    final cliTeamName = session.cliTeamName;
    final internalTab = _InternalTab(
      info: info,
      cliTeamName: cliTeamName,
    )..persistedSession = session;
    if (team != null && member != null) {
      internalTab.memberShells[member.id] = ts;
      internalTab.selectedMemberId = member.id;
    } else {
      internalTab.resumeSession = ts;
    }
    _internalTabs.add(internalTab);
    emit(
      state.copyWith(
        tabs: [...state.tabs, info],
        activeTabIndex: _internalTabs.length - 1,
        activeSessionId: session.sessionId,
        selectedMemberId: internalTab.selectedMemberId,
      ),
    );
    if (team != null) {
      _presenceTeam = team;
      refreshPresencePolling();
      if (team.teamMode == TeamMode.mixed) {
        final bus = TeamBus(
          launcher: ChatCubitMemberLauncher(
            materializer: this,
            sessionId: info.id,
          ),
        );
        for (final m in team.members) {
          final lead = TeamMemberNaming.isTeamLead(m);
          bus.declareMember(
            AgentNode(
              memberId: m.id,
              state: lead ? MemberState.busy : MemberState.declared,
            ),
          );
        }
        final server = TeammateBusMcpServer(
          handler: TeammateBusMcpHandler(bus: bus),
        );
        await server.start();
        internalTab.teamBus = bus;
        internalTab.mcpServer = server;
        _ensureIdleWatch();
      }
    }
    if (connectImmediately) {
      _beginSessionConnect(info.id);
      _postFrameScheduler(() async {
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
            if (_autoLaunchAllMembersOnConnect?.call() == true) {
              _launchRemainingMembersForTab(team, member.id, internalTab);
            }
          } else {
            final plan = await _lifecycle.prepareLaunch(
              session: session,
              team: team,
              member: member,
            );
            final configDir = plan.memberConfigDir.trim();
            if (configDir.isNotEmpty) {
              internalTab.memberToolConfigDir = configDir;
            }
            _emitLaunchWarnings(plan.warnings);
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
                  _failSessionConnect(info.id, message),
              onProcessExited: () => _updateTabRunning(info.id),
              onProcessStarted: () {
                _clearLaunchError(info.id);
                _finishSessionConnect(info.id);
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
          _updateTabRunning(info.id);
        } on Object catch (e, st) {
          appLogger.e(
            '[session] prepareLaunch/connect failed for ${info.id}: $e',
            error: e,
            stackTrace: st,
          );
          final message = 'Failed to resume session: $e';
          ts.write('\r\n[$message]\r\n');
          _failSessionConnect(info.id, message);
        }
      });
    } else {
      _updateTabRunning(info.id);
    }
  }

  void _launchRemainingMembersForTab(
    TeamConfig team,
    String keepSelectedMemberId,
    _InternalTab tab,
  ) {
    for (final candidate in team.members.where((m) => m.isValid)) {
      if (candidate.id == keepSelectedMemberId) continue;
      _scheduleMemberConnect(team, candidate, tab);
    }
    if (team.members.any((m) => m.id == keepSelectedMemberId)) {
      selectMember(keepSelectedMemberId);
    }
  }

  Future<void> _materializeDefaultWorkspaceSession(
    TeamConfig team,
    SessionRepository repo, {
    required bool connectImmediately,
    required TeamMemberConfig memberForInitialShell,
  }) async {
    if (_internalTabs.isNotEmpty) return;
    final cwd = AppStorage.cwd.trim();
    final project = await repo.createProject(cwd);
    final session = await repo.createSession(
      project.projectId,
      sessionTeam: team.id,
      rosterMembers: team.members,
    );
    await loadProjectData(repo);
    if (isClosed) return;
    await openSessionTab(
      session,
      team: team,
      member: memberForInitialShell,
      repo: repo,
      connectImmediately: connectImmediately,
    );
  }

  Future<void> openMemberTab(
    TeamConfig team,
    TeamMemberConfig member, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _sessionRepository;
    if (_internalTabs.isEmpty && r != null) {
      _beginSessionConnect('pending');
      try {
        await _materializeDefaultWorkspaceSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: member,
        );
      } on Object catch (e, st) {
        appLogger.e(
          'openMemberTab: default session failed: $e',
          stackTrace: st,
        );
        _failSessionConnect(
          'pending',
          'Failed to create session: $e',
        );
      }
      return;
    }
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    _scheduleMemberConnect(team, member, tab);
  }

  AppSession? _sessionForTab(_InternalTab tab) {
    final cached = tab.persistedSession;
    if (cached != null) return cached;
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return null;
    for (final s in state.sessions) {
      if (s.sessionId == tabId) return s;
    }
    return null;
  }

  Future<void> _persistSessionStarted(
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.markSessionLaunched(sessionId);
    if (isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessions = state.sessions.map((s) {
      if (s.sessionId != sessionId) return s;
      return s.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }).toList();
    _emitWithDerivedSessionsAndProjects(state.copyWith(sessions: sessions));
  }

  Future<SessionMemberBinding> _resolveMemberBinding({
    required AppSession session,
    required TeamMemberConfig member,
    required _InternalTab tab,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _sessionRepository;
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

  AppSession? _sessionForMemberConnect(_InternalTab tab, TeamConfig team) {
    final cached = _sessionForTab(tab);
    if (cached != null) return cached;
    if (!tab.info.id.startsWith('local-')) return null;
    final launch = _workingDirectoryAndAddDirsForTab(tab);
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

  Future<void> _connectMemberShell({
    required _InternalTab tab,
    required AppSession session,
    required TeamConfig team,
    required TeamMemberConfig member,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
  }) async {
    if (session.cliTeamName.isEmpty) {
      _failSessionConnect(
        tab.info.id,
        'Session is missing CLI team identity (cliTeamName). '
        'Create a new team session.',
      );
      return;
    }
    if (!session.sessionId.startsWith('local-') && session.members.isEmpty) {
      _failSessionConnect(
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
    final plan = await _lifecycle.prepareLaunch(
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
    _emitLaunchWarnings(plan.warnings);
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
      onFirstUserLineSubmitted: _autoRenameOnFirstPrompt(activeSession.sessionId),
      onProcessFailed: (message) => _failSessionConnect(tab.info.id, message),
      onProcessExited: () => _updateTabRunning(tab.info.id),
      onProcessStarted: () {
        _clearLaunchError(tab.info.id);
        _finishSessionConnect(tab.info.id);
        _memberReady.remove((tab.info.id, member.id))?.complete();
        final r = repo ?? _sessionRepository;
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

  _InternalTab? _tabBySessionId(String id) {
    for (final tab in _internalTabs) {
      if (tab.info.id == id) return tab;
    }
    return null;
  }

  @override
  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  ) async {
    final tab = _tabBySessionId(sessionId);
    final team = _presenceTeam;
    if (tab == null || team == null) return;
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) return;
    final ready = Completer<void>();
    _memberReady[(sessionId, memberId)] = ready;
    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      ready.complete();
    } else {
      _scheduleMemberConnect(team, member, tab);
    }
    await ready.future;
  }

  @override
  void injectMemberStdin(String sessionId, String memberId, String text) {
    final shell = _tabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    shell.writeln(trimmed);
  }

  void _scheduleMemberConnect(
    TeamConfig team,
    TeamMemberConfig member,
    _InternalTab tab,
  ) {
    tab.selectedMemberId = member.id;
    final shell = tab.memberShells.putIfAbsent(
      member.id,
      () => _newSession(member.cliWithin(team)),
    );
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
      ),
    );
    if (shell.isRunning || shell.isConnecting) {
      _updateTabRunning(tab.info.id);
      return;
    }
    if (tab.membersPendingConnect.contains(member.id)) {
      return;
    }
    tab.membersPendingConnect.add(member.id);
    _workingDirectoryAndAddDirsForTab(tab);
    _beginSessionConnect(tab.info.id);
    _postFrameScheduler(() async {
      try {
        if (shell.isRunning) {
          _finishSessionConnect(tab.info.id);
          return;
        }
        final session = _sessionForMemberConnect(tab, team);
        if (session == null) {
          _failSessionConnect(
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
        _updateTabRunning(tab.info.id);
      } on Object catch (e, st) {
        appLogger.e(
          '[session] prepareLaunch/connect failed for member ${member.name}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to start session: $e';
        shell.write('\r\n[$message]\r\n');
        _failSessionConnect(tab.info.id, message);
      } finally {
        tab.membersPendingConnect.remove(member.id);
      }
    });
  }

  void closeTab(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    final tab = _internalTabs.removeAt(index);
    for (final session in tab.sessions) {
      session.dispose();
    }
    // ignore: discarded_futures
    tab.disposeBus();
    _maybeStopIdleWatch();
    if (_internalTabs.isEmpty) {
      emit(
        state.copyWith(tabs: [], activeTabIndex: 0, clearActiveSessionId: true),
      );
    } else {
      final newIdx = state.activeTabIndex >= _internalTabs.length
          ? _internalTabs.length - 1
          : state.activeTabIndex;
      final nextTab = _internalTabs[newIdx];
      emit(
        state.copyWith(
          tabs: _visibleTabs(),
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
        ),
      );
    }
    refreshPresencePolling();
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    for (var i = _internalTabs.length - 1; i >= 0; i--) {
      if (i == index) continue;
      final tab = _internalTabs.removeAt(i);
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _maybeStopIdleWatch();
    final kept = _internalTabs.single;
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeTabIndex: 0,
        activeSessionId: kept.info.id,
        selectedMemberId: kept.selectedMemberId,
      ),
    );
    refreshPresencePolling();
  }

  void closeRightTabs(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    for (var i = _internalTabs.length - 1; i > index; i--) {
      final tab = _internalTabs.removeAt(i);
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _maybeStopIdleWatch();
    final active = _activeTab;
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeTabIndex: state.activeTabIndex.clamp(0, _internalTabs.length - 1),
        activeSessionId: active?.info.id,
        selectedMemberId: active?.selectedMemberId ?? '',
      ),
    );
    refreshPresencePolling();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    final tab = _internalTabs[index];
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
      ),
    );
    refreshPresencePolling();
  }

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      emit(state.copyWith(selectedMemberId: ''));
      return;
    }
    if (team.members.any((m) => m.id == state.selectedMemberId)) return;
    final newId = _defaultMemberId(team);
    _activeTab?.selectedMemberId = newId;
    emit(state.copyWith(selectedMemberId: newId));
  }

  void selectMember(String memberId) {
    if (state.selectedMemberId == memberId) return;
    _activeTab?.selectedMemberId = memberId;
    emit(state.copyWith(selectedMemberId: memberId));
  }

  /// Whether the member's PTY is up (spawning through running).
  bool isMemberRunning(String memberId) {
    final shell = _activeTab?.memberShells[memberId];
    return shell?.isRunning ?? false;
  }

  MemberPresence memberPresenceFor(String memberId) {
    return state.memberPresence[memberId] ?? const MemberPresence.offline();
  }

  /// Members panel mounted — polling may run when tab is eligible.
  void attachPresenceUi() {
    if (_presenceUiAttached) return;
    _presenceUiAttached = true;
    _schedulePresencePollingRestart();
  }

  /// Members panel unmounted — stop timer and clear displayed presence.
  void detachPresenceUi() {
    if (!_presenceUiAttached) return;
    _presenceUiAttached = false;
    _invalidatePresencePolls();
    if (state.memberPresence.isNotEmpty) {
      _emitMemberPresence(const {});
    }
  }

  /// Stops polling, clears team binding, and invalidates in-flight ticks.
  void stopPresencePolling() {
    _presenceTeam = null;
    _presenceUiAttached = false;
    _invalidatePresencePolls();
    if (state.memberPresence.isNotEmpty) {
      _emitMemberPresence(const {});
    }
  }

  void _invalidatePresencePolls() {
    _presencePollGeneration++;
    _presencePollTimer?.cancel();
    _presencePollTimer = null;
  }

  /// Stores the roster to poll; starts the 1s timer only when the active tab
  /// is a team session ([_tabEligibleForPresencePoll]).
  void syncPresenceTeam(TeamConfig? team) {
    if (_samePresenceTeam(_presenceTeam, team)) {
      return;
    }
    _presenceTeam = team;
    _schedulePresencePollingRestart();
  }

  /// Re-evaluate whether polling should run (e.g. after opening a session tab).
  void refreshPresencePolling() {
    _schedulePresencePollingRestart();
  }

  /// Avoid emit / timer setup during build or semantics traversal.
  void _schedulePresencePollingRestart() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      _restartPresencePolling();
    });
  }

  void _emitMemberPresence(Map<String, MemberPresence> next) {
    if (isClosed || mapEquals(next, state.memberPresence)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed || mapEquals(next, state.memberPresence)) return;
      emit(state.copyWith(memberPresence: next));
    });
  }

  bool _shouldPollPresence() {
    if (!_presenceUiAttached || _presenceTeam == null) return false;
    final tab = _activeTab;
    if (tab == null) return false;
    return _tabEligibleForPresencePoll(tab);
  }

  bool _tabEligibleForPresencePoll(_InternalTab tab) {
    if (tab.memberShells.isNotEmpty) return true;
    final configDir = tab.memberToolConfigDir?.trim() ?? '';
    return configDir.isNotEmpty;
  }

  static bool _samePresenceTeam(TeamConfig? a, TeamConfig? b) {
    if (a == null || b == null) return a == b;
    if (a.id != b.id || a.cli != b.cli) return false;
    if (a.members.length != b.members.length) return false;
    for (var i = 0; i < a.members.length; i++) {
      if (a.members[i].id != b.members[i].id) return false;
    }
    return true;
  }

  void _restartPresencePolling() {
    _presencePollTimer?.cancel();
    _presencePollTimer = null;
    final team = _presenceTeam;
    if (team == null || team.members.isEmpty) {
      if (state.memberPresence.isNotEmpty) {
        _emitMemberPresence(const {});
      }
      return;
    }
    if (!_shouldPollPresence()) {
      if (state.memberPresence.isNotEmpty) {
        _emitMemberPresence(const {});
      }
      return;
    }
    final generation = _presencePollGeneration;
    _presencePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tickMemberPresence(team, generation));
    });
    unawaited(_tickMemberPresence(team, generation));
  }

  Future<void> _tickMemberPresence(TeamConfig team, int generation) async {
    if (isClosed || generation != _presencePollGeneration) return;
    if (!_shouldPollPresence()) return;
    if (_presenceTickInFlight) return;

    final tab = _activeTab;
    if (tab == null) return;

    _presenceTickInFlight = true;
    try {
      final next = await _memberPresenceService.compute(
        teamCli: team.cli,
        members: team.members,
        cliTeamName: tab.cliTeamName,
        memberToolConfigDir: tab.memberToolConfigDir,
        memberShells: tab.memberShells,
      );
      if (isClosed ||
          generation != _presencePollGeneration ||
          !_shouldPollPresence()) {
        return;
      }
      _emitMemberPresence(next);
    } finally {
      _presenceTickInFlight = false;
    }
  }

  void _ensureIdleWatch() {
    if (_idleWatchTimer != null) return;
    _idleWatchTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickIdleWatch(),
    );
  }

  void _maybeStopIdleWatch() {
    final anyBus = _internalTabs.any((t) => t.teamBus != null);
    if (!anyBus) {
      _idleWatchTimer?.cancel();
      _idleWatchTimer = null;
      _lastWorking.clear();
    }
  }

  void _tickIdleWatch() {
    if (isClosed) return;
    for (final tab in _internalTabs) {
      final bus = tab.teamBus;
      if (bus == null) continue;
      tab.memberShells.forEach((memberId, shell) {
        final key = '${tab.info.id}:$memberId';
        final working = shell.activityTracker.isWorking;
        final was = _lastWorking[key] ?? false;
        _lastWorking[key] = working;
        if (was && !working) {
          bus.onMemberIdle(memberId);
        }
      });
    }
  }

  Future<void> launchAllMembers(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _sessionRepository;
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) return;
    if (_internalTabs.isEmpty && r != null) {
      try {
        await _materializeDefaultWorkspaceSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: validMembers.first,
        );
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

  String selectedMemberName(TeamConfig team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession? ensureSession(TeamConfig team) {
    var tab = _activeTab;
    if (tab == null && _sessionRepository == null) {
      tab = _appendLocalTab(team, emitChange: false);
    }
    if (tab == null) return null;
    if (tab.selectedMemberId.isEmpty) {
      tab.selectedMemberId = _defaultMemberId(team);
    }
    if (tab.selectedMemberId.isNotEmpty) {
      return tab.memberShells.putIfAbsent(
        tab.selectedMemberId,
        () => _newSession(team.cli),
      );
    }
    return tab.resumeSession ??= _newSession(team.cli);
  }

  Future<void> connectSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
    if (state.isActiveSessionConnecting) return;

    final r = repo ?? _sessionRepository;
    if (_internalTabs.isEmpty && r == null) {
      _appendLocalTab(team, emitChange: true);
    }

    if (_autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = state.selectedMemberId.isNotEmpty
          ? state.selectedMemberId
          : _defaultMemberId(team);
      if (keepId.isEmpty) {
        final session = ensureSession(team);
        const message =
            'No member selected. Choose a team member and try again.';
        session?.write('\r\n[$message]\r\n');
        _failSessionConnect(_activeTab?.info.id ?? 'pending', message);
        return;
      }
      await launchAllMembers(team, repo: r);
      if (team.members.any((m) => m.id == keepId)) {
        selectMember(keepId);
      }
      return;
    }

    var memberId = state.selectedMemberId;
    if (memberId.isEmpty) {
      memberId = _defaultMemberId(team);
    }
    if (memberId.isEmpty || team.members.isEmpty) {
      final session = ensureSession(team);
      const message =
          'No member selected. Choose a team member and try again.';
      session?.write('\r\n[$message]\r\n');
      _failSessionConnect(_activeTab?.info.id ?? 'pending', message);
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
    _clearLaunchError(tab.info.id);
    _updateTabRunning(tab.info.id);
  }

  Future<void> restartSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _sessionRepository;
    final activeId = _activeTab?.info.id ?? state.activeSessionId ?? 'pending';
    _beginSessionConnect(activeId);
    if (_autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = state.selectedMemberId.isNotEmpty
          ? state.selectedMemberId
          : _defaultMemberId(team);
      final tab = _activeTab;
      if (tab != null) {
        tab.membersPendingConnect.clear();
        for (final shell in tab.memberShells.values) {
          shell.disconnect();
        }
        _updateTabRunning(tab.info.id);
      }
      await launchAllMembers(team, repo: r);
      if (keepId.isNotEmpty && team.members.any((m) => m.id == keepId)) {
        selectMember(keepId);
      }
      return;
    }
    disconnectSession();
    await connectSession(team, repo: r);
  }

  void Function(String line)? _autoRenameOnFirstPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    final repo = _sessionRepository;
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
    if (isClosed) return;
    AppSession? session;
    for (final s in state.sessions) {
      if (s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    if (session == null || session.display.trim().isNotEmpty) return;
    final title = deriveSessionTitleFromFirstPrompt(firstPrompt);
    if (title.isEmpty) return;
    await renameSession(repo, sessionId, title);
  }

  Future<void> renameSession(
    SessionRepository repo,
    String sessionId,
    String newName,
  ) async {
    await repo.renameSession(sessionId, newName);
    final sessions = state.sessions.map((s) {
      if (s.sessionId == sessionId) return s.copyWith(display: newName);
      return s;
    }).toList();
    final tabs = state.tabs.map((t) {
      if (t.id == sessionId) return t.copyWith(title: newName);
      return t;
    }).toList();
    for (final tab in _internalTabs) {
      if (tab.info.id == sessionId) {
        tab.info = tab.info.copyWith(title: newName);
      }
    }
    _emitWithDerivedSessionsAndProjects(
      state.copyWith(sessions: sessions, tabs: tabs),
    );
  }

  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final wasActive = state.activeSessionId == sessionId;
    final sessions = state.sessions
        .where((s) => s.sessionId != sessionId)
        .toList();
    final idx = _internalTabs.indexWhere((t) => t.info.id == sessionId);
    if (idx != -1) {
      final tab = _internalTabs.removeAt(idx);
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
      _maybeStopIdleWatch();
    }
    final tabs = _internalTabs.map((t) => t.info).toList();

    if (wasActive && _internalTabs.isNotEmpty) {
      final newIdx = idx < _internalTabs.length
          ? idx
          : _internalTabs.length - 1;
      final nextTab = _internalTabs[newIdx];
      _emitWithDerivedSessionsAndProjects(
        state.copyWith(
          sessions: sessions,
          tabs: tabs,
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
        ),
      );
    } else if (_internalTabs.isEmpty) {
      _emitWithDerivedSessionsAndProjects(
        state.copyWith(
          sessions: sessions,
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
        ),
      );
    } else {
      _emitWithDerivedSessionsAndProjects(
        state.copyWith(sessions: sessions, tabs: tabs),
      );
    }

    await repo.deleteSession(sessionId);
    await loadProjectData(repo);
  }

  Future<void> deleteProject(SessionRepository repo, String projectId) async {
    AppProject? project;
    for (final p in state.projects) {
      if (p.projectId == projectId) {
        project = p;
        break;
      }
    }
    if (project == null) return;
    for (final sid in project.sessionIds.toList()) {
      await deleteSession(repo, sid);
    }
    await repo.deleteProject(projectId);
    await loadProjectData(repo);
  }

  void selectSession(String sessionId) {
    final idx = _internalTabs.indexWhere((t) => t.info.id == sessionId);
    if (idx == -1) {
      emit(state.copyWith(activeSessionId: sessionId));
      return;
    }
    selectTab(idx);
  }

  void addSystemMessage(String content) {
    final target = currentSession;
    target?.write('\r\n[system] $content\r\n');
  }

  void _updateTabRunning(String tabId) {
    final idx = _internalTabs.indexWhere((t) => t.info.id == tabId);
    if (idx == -1) return;
    _internalTabs[idx].info = _internalTabs[idx].info.copyWith(
      isRunning: _internalTabs[idx].isRunning,
    );
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        stateVersion: state.stateVersion + 1,
      ),
    );
    refreshPresencePolling();
  }

  void _beginSessionConnect(String sessionId) {
    _clearLaunchError(sessionId);
    if (state.sessionConnectingId == sessionId) return;
    emit(
      state.copyWith(
        sessionConnectingId: sessionId,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void _setLaunchError(String sessionId, String rawMessage) {
    final message = formatSessionLaunchError(rawMessage);
    if (message.isEmpty) return;
    final idx = _internalTabs.indexWhere((t) => t.info.id == sessionId);
    if (idx != -1) {
      _internalTabs[idx].info = _internalTabs[idx].info.copyWith(
        launchError: message,
      );
      emit(
        state.copyWith(
          tabs: _visibleTabs(),
          clearSessionLaunchError: true,
          stateVersion: state.stateVersion + 1,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        sessionLaunchError: message,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void _clearLaunchError(String sessionId) {
    var tabChanged = false;
    final idx = _internalTabs.indexWhere((t) => t.info.id == sessionId);
    if (idx != -1 && _internalTabs[idx].info.launchError != null) {
      _internalTabs[idx].info = _internalTabs[idx].info.copyWith(
        clearLaunchError: true,
      );
      tabChanged = true;
    }
    if (!tabChanged && state.sessionLaunchError == null) return;
    emit(
      state.copyWith(
        tabs: tabChanged ? _visibleTabs() : state.tabs,
        clearSessionLaunchError: true,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void _failSessionConnect(String sessionId, String rawMessage) {
    _setLaunchError(sessionId, rawMessage);
    _finishSessionConnect(sessionId);
  }

  void _finishSessionConnect(String sessionId) {
    _updateTabRunning(sessionId);
    if (state.sessionConnectingId != sessionId) return;
    emit(
      state.copyWith(
        clearSessionConnectingId: true,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  /// [openSessionTab] / sidebar session tabs use the persisted [AppSession]
  /// id as [ChatTabInfo.id]; local-only tabs use `local-<teamId>`.
  (String, List<String>) _workingDirectoryAndAddDirsForTab(_InternalTab tab) {
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (AppStorage.cwd, const <String>[]);
    }
    for (final s in state.sessions) {
      if (s.sessionId != tabId) continue;
      final wd = s.primaryPath.trim();
      final addl = s.additionalPaths
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (wd.isNotEmpty) {
        return (wd, addl);
      }
      return (AppStorage.cwd, addl);
    }
    return (AppStorage.cwd, const <String>[]);
  }

  _InternalTab _appendLocalTab(TeamConfig team, {required bool emitChange}) {
    final info = _localSessionInfo(team);
    final tab = _InternalTab(
      info: info,
      cliTeamName: _uuid.v4(),
      selectedMemberId: _defaultMemberId(team),
    );
    _internalTabs.add(tab);
    if (emitChange) {
      emit(
        state.copyWith(
          tabs: _visibleTabs(),
          activeTabIndex: _internalTabs.length - 1,
          activeSessionId: info.id,
          selectedMemberId: tab.selectedMemberId,
        ),
      );
    }
    return tab;
  }

  _InternalTab _ensureActiveSessionTab(
    TeamConfig team, {
    required bool emitChange,
  }) {
    final existing = _activeTab;
    if (existing != null) return existing;
    return _appendLocalTab(team, emitChange: emitChange);
  }

  ChatTabInfo _localSessionInfo(TeamConfig team) {
    return ChatTabInfo(
      id: 'local-${team.id}',
      title: team.name,
      subtitle: 'local session',
    );
  }

  String _defaultMemberId(TeamConfig team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  List<ChatTabInfo> _visibleTabs() {
    return _internalTabs.map((t) => t.info).toList();
  }

  void _emitLaunchWarnings(List<String> warnings) {
    if (warnings.isEmpty || isClosed) return;
    emit(
      state.copyWith(
        snackbarMessage: warnings.first,
        stateVersion: state.stateVersion + 1,
      ),
    );
  }

  void clearSnackbarMessage() {
    if (isClosed || state.snackbarMessage == null) return;
    emit(state.copyWith(clearSnackbarMessage: true));
  }

  @visibleForTesting
  bool hasTeamBusResources(String sessionId) {
    final tab = _tabBySessionId(sessionId);
    return tab?.teamBus != null && tab?.mcpServer != null;
  }

  @visibleForTesting
  Uri? teammateBusMcpEndpointForSession(String sessionId) {
    final server = _tabBySessionId(sessionId)?.mcpServer;
    if (server == null) return null;
    try {
      return server.endpoint;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    _invalidatePresencePolls();
    _idleWatchTimer?.cancel();
    _idleWatchTimer = null;
    _lastWorking.clear();
    for (final tab in _internalTabs) {
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _internalTabs.clear();
    await super.close();
  }
}
