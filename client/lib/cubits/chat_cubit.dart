import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_project.dart';
import '../models/connection_mode.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_transport_factory.dart';
import 'chat/chat_connect_state_mixin.dart';
import 'chat/session_data_store.dart';
import 'chat/chat_session_shell_factory.dart';
import 'chat/chat_tab_store.dart';
import 'chat/session_launch_service.dart';
import 'chat/tab_team_bus_coordinator.dart';
import 'member_presence_cubit.dart';
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';

export 'chat/model/chat_state.dart';
export 'chat/model/chat_tab_info.dart';

class ChatCubit extends Cubit<ChatState>
    with ChatConnectStateMixin
    implements SessionLaunchHost {
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
  }) : _shellFactory = ChatSessionShellFactory(
         executableResolver: executableResolver,
         cliExecutableResolver: cliExecutableResolver,
         terminalSessionFactory: terminalSessionFactory,
         transportFactory: transportFactory,
         sshProfileResolver: sshProfileResolver,
         sshDefaultWorkingDirectoryResolver: sshDefaultWorkingDirectoryResolver,
         sshUseLoginShellResolver: sshUseLoginShellResolver,
         connectionModeResolver: connectionModeResolver,
         terminalScrollbackLinesResolver: terminalScrollbackLinesResolver,
       ),
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _lifecycle = lifecycleService ?? SessionLifecycleService(),
       _sessionRepository = sessionRepository,
       super(const ChatState());

  final ChatTabStore _tabStore = ChatTabStore();
  final SessionDataStore _dataStore = SessionDataStore();
  late final SessionLaunchService _launchService = SessionLaunchService(this);
  late final TabTeamBusCoordinator _busCoordinator = TabTeamBusCoordinator(
    tabStore: _tabStore,
    shellFactory: _shellFactory,
    connector: _launchService,
    activeTeam: () => _activeTeam,
    isClosed: () => isClosed,
  );
  MemberPresenceCubit? _presenceCubit;
  TeamConfig? _activeTeam;
  final ChatSessionShellFactory _shellFactory;
  final PostFrameScheduler _postFrameScheduler;
  final bool Function()? _autoLaunchAllMembersOnConnect;
  final SessionLifecycleService _lifecycle;
  final SessionRepository? _sessionRepository;

  @override
  ChatTabStore get tabStore => _tabStore;

  @override
  void onTabRunningChanged() => _pushPresenceTarget();

  // ===== SessionLaunchHost =====

  @override
  void applyState(ChatState next) => emit(next);

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) => _emitSnapshot(snapshot);

  @override
  void pushPresenceTarget() => _pushPresenceTarget();

  @override
  ChatTab? get activeTab => _activeTab;

  @override
  set activeTeam(TeamConfig? team) => _activeTeam = team;

  @override
  ChatSessionShellFactory get shellFactory => _shellFactory;

  @override
  TabTeamBusCoordinator get busCoordinator => _busCoordinator;

  @override
  SessionLifecycleService get lifecycle => _lifecycle;

  @override
  SessionDataStore get dataStore => _dataStore;

  @override
  SessionRepository? get sessionRepository => _sessionRepository;

  @override
  PostFrameScheduler get postFrameScheduler => _postFrameScheduler;

  @override
  bool Function()? get autoLaunchAllMembersOnConnect =>
      _autoLaunchAllMembersOnConnect;

  /// Wired by app_shell after both cubits are constructed.
  void bindPresenceCubit(MemberPresenceCubit cubit) => _presenceCubit = cubit;

  void _pushPresenceTarget() {
    final cubit = _presenceCubit;
    if (cubit == null) return;
    final tab = _activeTab;
    cubit.updateTarget(
      tab == null
          ? null
          : PresenceTarget(
              cliTeamName: tab.cliTeamName,
              memberToolConfigDir: tab.memberToolConfigDir,
              memberShells: tab.memberShells,
            ),
    );
  }

  static void _defaultPostFrameScheduler(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }

  void setTeamSessionScope({
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    if (!_dataStore.setScope(
      scopeSessionsToSelectedTeam: scopeSessionsToSelectedTeam,
      selectedTeamId: selectedTeamId,
    )) {
      return;
    }
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        projects: state.projects,
        sessions: state.sessions,
      ),
    );
  }

  void _emitSnapshot(ChatDataSnapshot snap, {ChatState? base}) {
    final s = base ?? state;
    emit(
      s.copyWith(
        projects: snap.projects,
        sessions: snap.sessions,
        visibleProjects: snap.visibleProjects,
        visibleSessions: snap.visibleSessions,
      ),
    );
  }

  ChatTab? get _activeTab => _tabStore.activeTab(state.activeTabIndex);

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
    return _tabStore.workingDirectoryAndAddDirsForTab(tab, state.sessions).$1;
  }

  /// Last launch failure for the active tab, or [ChatState.sessionLaunchError].
  String? get activeLaunchError {
    if (!_tabStore.isEmpty) {
      final index = state.activeTabIndex.clamp(0, _tabStore.length - 1);
      final error = _tabStore.tabs[index].info.launchError;
      if (error != null && error.isNotEmpty) return error;
    }
    final pending = state.sessionLaunchError;
    if (pending != null && pending.isNotEmpty) return pending;
    return null;
  }

  @override
  Future<void> loadProjectData(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadProjectData(repo));
  }

  /// Updates persisted-index mirrors in state and recomputes team-scoped sidebar lists.
  void ingestProjectSessionSnapshot({
    required List<AppProject> projects,
    required List<AppSession> sessions,
  }) {
    _emitSnapshot(
      _dataStore.deriveSnapshot(projects: projects, sessions: sessions),
    );
  }

  Future<AppSession> createSession(
    String projectId,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final session = await _dataStore.createSession(
      projectId,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
    );
    _emitSnapshot(await _dataStore.loadProjectData(repo));
    return session;
  }

  /// Creates (or reuses) the project for [primaryPath], seeds a first session,
  /// reloads project data, and returns the project id so callers can navigate
  /// straight to the new project.
  Future<String> createProjectWithFirstSession(
    String primaryPath,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    List<String> additionalPaths = const [],
    String display = '',
  }) async {
    final result = await _dataStore.createProjectWithFirstSession(
      primaryPath,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      additionalPaths: additionalPaths,
      display: display,
    );
    _emitSnapshot(result.snapshot);
    return result.projectId;
  }

  Future<void> addProjectDirectory(
    SessionRepository repo,
    AppProject project,
    String directoryPath,
  ) async {
    final snap = await _dataStore.addProjectDirectory(
      repo,
      project,
      directoryPath,
    );
    if (snap != null) _emitSnapshot(snap);
  }

  Future<void> updateProjectMetadata(
    SessionRepository repo,
    String projectId, {
    String? display,
    List<String>? additionalPaths,
  }) async {
    _emitSnapshot(
      await _dataStore.updateProjectMetadata(
        repo,
        projectId,
        display: display,
        additionalPaths: additionalPaths,
      ),
    );
  }

  Future<void> openSessionTab(
    AppSession session, {
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
    String emptyDisplayTitleFallback = 'New Chat',
    bool connectImmediately = true,
  }) =>
      _launchService.openSessionTab(
        session,
        team: team,
        member: member,
        repo: repo,
        emptyDisplayTitleFallback: emptyDisplayTitleFallback,
        connectImmediately: connectImmediately,
      );

  Future<void> openMemberTab(
    TeamConfig team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) =>
      _launchService.openMemberTab(
        team,
        member,
        repo: repo,
        workspaceCwd: workspaceCwd,
      );

  void closeTab(int index) {
    if (index < 0 || index >= _tabStore.length) return;
    final tab = _tabStore.removeAt(index);
    for (final session in tab.sessions) {
      session.dispose();
    }
    // ignore: discarded_futures
    tab.disposeBus();
    _busCoordinator.maybeStopIdleWatch();
    if (_tabStore.isEmpty) {
      emit(
        state.copyWith(tabs: [], activeTabIndex: 0, clearActiveSessionId: true),
      );
    } else {
      final newIdx = state.activeTabIndex >= _tabStore.length
          ? _tabStore.length - 1
          : state.activeTabIndex;
      final nextTab = _tabStore.tabs[newIdx];
      emit(
        state.copyWith(
          tabs: _tabStore.toInfos(),
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
        ),
      );
    }
    _pushPresenceTarget();
  }

  /// Open terminal tabs whose backing session belongs to [projectId].
  /// `local-` scratch tabs have no project and are excluded.
  List<int> _tabIndicesForProject(String projectId) {
    final result = <int>[];
    for (var i = 0; i < _tabStore.length; i++) {
      final session = _tabStore.sessionForTab(
        _tabStore.tabs[i],
        state.sessions,
      );
      if (session != null && session.projectId == projectId) result.add(i);
    }
    return result;
  }

  /// Number of open terminal tabs backed by sessions in [projectId].
  int openTabCountForProject(String projectId) =>
      _tabIndicesForProject(projectId).length;

  /// Closes (terminates) every open terminal tab belonging to [projectId].
  void closeTabsForProject(String projectId) {
    // Close highest index first so earlier indices stay valid as the list
    // shrinks; [closeTab] disposes the terminal sessions and team-bus.
    final indices = _tabIndicesForProject(projectId)
      ..sort((a, b) => b.compareTo(a));
    for (final i in indices) {
      closeTab(i);
    }
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _tabStore.length) return;
    for (var i = _tabStore.length - 1; i >= 0; i--) {
      if (i == index) continue;
      final tab = _tabStore.removeAt(i);
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _busCoordinator.maybeStopIdleWatch();
    final kept = _tabStore.tabs.single;
    emit(
      state.copyWith(
        tabs: _tabStore.toInfos(),
        activeTabIndex: 0,
        activeSessionId: kept.info.id,
        selectedMemberId: kept.selectedMemberId,
      ),
    );
    _pushPresenceTarget();
  }

  void closeRightTabs(int index) {
    if (index < 0 || index >= _tabStore.length) return;
    for (var i = _tabStore.length - 1; i > index; i--) {
      final tab = _tabStore.removeAt(i);
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _busCoordinator.maybeStopIdleWatch();
    final active = _activeTab;
    emit(
      state.copyWith(
        tabs: _tabStore.toInfos(),
        activeTabIndex: state.activeTabIndex.clamp(0, _tabStore.length - 1),
        activeSessionId: active?.info.id,
        selectedMemberId: active?.selectedMemberId ?? '',
      ),
    );
    _pushPresenceTarget();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabStore.length) return;
    final tab = _tabStore.tabs[index];
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
      ),
    );
    _pushPresenceTarget();
  }

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      emit(state.copyWith(selectedMemberId: ''));
      return;
    }
    if (team.members.any((m) => m.id == state.selectedMemberId)) return;
    final newId = _tabStore.defaultMemberId(team);
    _activeTab?.selectedMemberId = newId;
    emit(state.copyWith(selectedMemberId: newId));
  }

  @override
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

  Future<void> launchAllMembers(
    TeamConfig team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) =>
      _launchService.launchAllMembers(
        team,
        repo: repo,
        workspaceCwd: workspaceCwd,
      );

  String selectedMemberName(TeamConfig team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession? ensureSession(TeamConfig team) =>
      _launchService.ensureSession(team);

  Future<void> connectSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) =>
      _launchService.connectSession(team, repo: repo);

  void disconnectSession() => _launchService.disconnectSession();

  Future<void> restartSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) =>
      _launchService.restartSession(team, repo: repo);

  @override
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
    for (final tab in _tabStore.tabs) {
      if (tab.info.id == sessionId) {
        tab.info = tab.info.copyWith(title: newName);
      }
    }
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        projects: state.projects,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions, tabs: tabs),
    );
  }

  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final wasActive = state.activeSessionId == sessionId;
    final sessions = state.sessions
        .where((s) => s.sessionId != sessionId)
        .toList();
    final idx = _tabStore.indexOfSession(sessionId);
    if (idx != -1) {
      final tab = _tabStore.removeAt(idx);
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
      _busCoordinator.maybeStopIdleWatch();
    }
    final tabs = _tabStore.tabs.map((t) => t.info).toList();

    if (wasActive && !_tabStore.isEmpty) {
      final newIdx = idx < _tabStore.length
          ? idx
          : _tabStore.length - 1;
      final nextTab = _tabStore.tabs[newIdx];
      _emitSnapshot(
        _dataStore.deriveSnapshot(projects: state.projects, sessions: sessions),
        base: state.copyWith(
          tabs: tabs,
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
        ),
      );
    } else if (_tabStore.isEmpty) {
      _emitSnapshot(
        _dataStore.deriveSnapshot(projects: state.projects, sessions: sessions),
        base: state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
        ),
      );
    } else {
      _emitSnapshot(
        _dataStore.deriveSnapshot(projects: state.projects, sessions: sessions),
        base: state.copyWith(tabs: tabs),
      );
    }

    _emitSnapshot(await _dataStore.deleteSessionRecord(repo, sessionId));
  }

  Future<AppProject> cloneProject(
    SessionRepository repo,
    String sourceProjectId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final result = await _dataStore.cloneProject(
      repo,
      sourceProjectId,
      display: display,
      rosterMembers: rosterMembers,
    );
    _emitSnapshot(result.snapshot);
    return result.project;
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
    _emitSnapshot(await _dataStore.deleteProjectRecord(repo, projectId));
  }

  void selectSession(String sessionId) {
    final idx = _tabStore.indexOfSession(sessionId);
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

  bool hasTeamBusResources(String sessionId) =>
      _busCoordinator.hasTeamBusResources(sessionId);

  @visibleForTesting
  Uri? teammateBusMcpEndpointForSession(String sessionId) =>
      _busCoordinator.teammateBusMcpEndpointForSession(sessionId);

  @override
  Future<void> close() async {
    if (isClosed) return;
    _busCoordinator.disposeIdleWatch();
    for (final tab in _tabStore.tabs) {
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _tabStore.clear();
    await super.close();
  }
}
