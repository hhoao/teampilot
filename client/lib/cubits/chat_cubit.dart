import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_project.dart';
import '../models/connection_mode.dart';
import '../models/app_session.dart';
import '../models/member_presence.dart';
import '../models/project_icon_picker_result.dart';
import '../models/project_icon_ref.dart';
import '../models/team_config.dart';
import '../../repositories/identity_repository.dart';
import '../repositories/session_repository.dart';
import '../services/project/project_icon_service.dart';
import '../services/project/project_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../widgets/project_icon_picker_dialog.dart';
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
    onWorkingSessionsChanged: _updateWorkingSessions,
  );
  MemberPresenceCubit? _presenceCubit;
  TeamIdentity? _activeTeam;
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
  set activeTeam(TeamIdentity? team) => _activeTeam = team;

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

  /// Pushed by [TabTeamBusCoordinator] (1s idle-watch tick) whenever the set of
  /// sessions with a member in-turn changes. Drives the working spinner on tabs
  /// / sidebar list items. Set is already change-filtered upstream.
  void _updateWorkingSessions(Set<String> ids) {
    if (isClosed || setEquals(ids, state.workingSessionIds)) return;
    emit(state.copyWith(workingSessionIds: ids));
  }

  @visibleForTesting
  void updateWorkingSessionsForTest(Set<String> ids) => _updateWorkingSessions(ids);

  @visibleForTesting
  void debugTickIdleWatch() => _busCoordinator.debugTickIdleWatch();

  void _pushPresenceTarget() {
    final cubit = _presenceCubit;
    if (cubit == null) return;
    final tab = _activeTab;
    if (tab == null) {
      cubit.updateTarget(null);
      return;
    }
    cubit.updateTarget(
      PresenceTarget(
        cliTeamName: tab.cliTeamName,
        memberToolConfigDir: tab.memberToolConfigDir,
        memberShells: tab.memberShells,
        workloadResolver: _busWorkloadResolver(tab),
      ),
    );
  }

  /// mixed 模式:成员工作态**纯取 TeamBus 回合真值**,不再用 PTY 字节兜底 ——
  /// 终端输出无法证明 working(spinner / 状态行重绘会把空闲成员喷成「工作中」),
  /// 所以只认正向回合事件:
  ///   - 阻塞在 `wait_for_message` → idle;
  ///   - bus 在回合中(`isMemberInTurn` = `isActive`)→ working;否则 idle。
  /// working 的 `active` 由三类正向边置位:物化完成 / 收到 mail / **用户在 prompt 直接
  /// 提交**(`markTurnStarted`,补上了 leader 用户回合这条以前没接回 bus 的路)。idle 由
  /// `wait` / Stop hook / `_tickIdleWatch` 的 PTY 长静默边沿漏空 —— Stop 漏发也不会卡死。
  /// 这样空闲成员(含 leader)即便 spinner 喷输出也保持 idle,`_tickIdleWatch` 只清不设。
  /// native 单 CLI 返回 null。
  MemberWorkload Function(String memberId)? _busWorkloadResolver(ChatTab tab) {
    final bus = tab.teamBus;
    if (_activeTeam?.teamMode != TeamMode.mixed || bus == null) return null;
    return (memberId) =>
        bus.isMemberInTurn(memberId) && !bus.isWaitingForMessage(memberId)
        ? MemberWorkload.working
        : MemberWorkload.idle;
  }

  /// Switches the active project bucket and republishes its tabs into state.
  /// Called by the project page whenever the active project changes.
  void setActiveProject(String projectId) {
    final restoredIndex = _tabStore.setActiveProject(
      projectId,
      currentActiveIndex: state.activeTabIndex,
    );
    _publishActiveProjectTabs(restoredIndex);
  }

  /// Re-emits the active bucket's tab infos without changing the project, after
  /// callers mutate the active bucket directly via [tabStore].
  void refreshActiveProjectTabs() =>
      _publishActiveProjectTabs(state.activeTabIndex);

  void _publishActiveProjectTabs(int desiredIndex) {
    if (_tabStore.isEmpty) {
      emit(
        state.copyWith(
          tabs: const [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          selectedMemberId: '',
        ),
      );
      _pushPresenceTarget();
      return;
    }
    final index = desiredIndex.clamp(0, _tabStore.length - 1);
    final tab = _tabStore.tabs[index];
    emit(
      state.copyWith(
        tabs: _tabStore.toInfos(),
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
      ),
    );
    _pushPresenceTarget();
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
    CliTool? cli,
  }) async {
    final session = await _dataStore.createSession(
      projectId,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      cli: cli,
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
    IdentityRepository? identityRepository,
  }) async {
    final result = await _dataStore.createProjectWithFirstSession(
      primaryPath,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      additionalPaths: additionalPaths,
      display: display,
      identityRepository: identityRepository,
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

  Future<void> applyProjectIcon(
    SessionRepository repo,
    String projectId,
    ProjectIconRef icon,
  ) async {
    _emitSnapshot(await _dataStore.applyProjectIcon(repo, projectId, icon));
  }

  Future<void> importCustomProjectIcon(
    SessionRepository repo,
    String projectId,
    String localSourcePath,
  ) async {
    _emitSnapshot(
      await _dataStore.importCustomProjectIcon(
        repo,
        projectId,
        localSourcePath,
      ),
    );
  }

  /// Opens the icon picker and applies the user's choice.
  ///
  /// Returns an error message when custom import fails; otherwise `null`.
  Future<String?> editProjectIcon(
    BuildContext context,
    SessionRepository repo,
    AppProject project,
  ) async {
    final result = await showProjectIconPickerDialog(context, project: project);
    return switch (result) {
      ProjectIconPickerCancelled() => null,
      ProjectIconPickerUploadRequested() => _pickAndImportCustomIcon(
        repo,
        project.projectId,
      ),
      ProjectIconPickerCommitted(:final icon) => _applyCommittedIcon(
        repo,
        project.projectId,
        icon,
      ),
    };
  }

  Future<String?> _pickAndImportCustomIcon(
    SessionRepository repo,
    String projectId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ProjectIconStorage.allowedExtensions
          .where((ext) => ext != 'jpeg')
          .toList(growable: false),
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;

    try {
      await importCustomProjectIcon(repo, projectId, path);
      return null;
    } on ProjectIconImportException catch (error) {
      return error.message;
    }
  }

  Future<String?> _applyCommittedIcon(
    SessionRepository repo,
    String projectId,
    ProjectIconRef icon,
  ) async {
    await applyProjectIcon(repo, projectId, icon);
    return null;
  }

  Future<void> openSessionTab(
    AppSession session, {
    TeamIdentity? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
    String emptyDisplayTitleFallback = 'New Chat',
    bool connectImmediately = true,
  }) => _launchService.openSessionTab(
    session,
    team: team,
    member: member,
    repo: repo,
    emptyDisplayTitleFallback: emptyDisplayTitleFallback,
    connectImmediately: connectImmediately,
  );

  Future<void> openMemberTab(
    TeamIdentity team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) => _launchService.openMemberTab(
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

  /// Number of open session-backed tabs in [projectId]'s bucket (excludes
  /// `local-` scratch tabs, which have no persisted project session).
  int openTabCountForProject(String projectId) =>
      _tabStore.sessionBackedCountForProject(projectId);

  /// Closes (terminates) every open tab belonging to [projectId] by dropping
  /// its whole bucket and disposing each tab's sessions and team-bus.
  void closeTabsForProject(String projectId) {
    final removed = _tabStore.removeProject(projectId);
    if (removed.isEmpty) return;
    for (final tab in removed) {
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _busCoordinator.maybeStopIdleWatch();
    // Republish whenever the active bucket was affected: either it was the
    // named bucket for this project, or it is the legacy empty-string bucket
    // and tabs were removed from it (legacy path before setActiveProject).
    final activeIsAffected =
        projectId == _tabStore.activeProjectId ||
        _tabStore.activeProjectId.isEmpty;
    if (activeIsAffected) {
      _publishActiveProjectTabs(0);
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

  void syncTeam(TeamIdentity team) {
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
    TeamIdentity team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) => _launchService.launchAllMembers(
    team,
    repo: repo,
    workspaceCwd: workspaceCwd,
  );

  String selectedMemberName(TeamIdentity team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession? ensureSession(TeamIdentity team) =>
      _launchService.ensureSession(team);

  Future<void> connectSession(TeamIdentity team, {SessionRepository? repo}) =>
      _launchService.connectSession(team, repo: repo);

  void disconnectSession() => _launchService.disconnectSession();

  Future<void> restartSession(TeamIdentity team, {SessionRepository? repo}) =>
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
      _dataStore.deriveSnapshot(projects: state.projects, sessions: sessions),
      base: state.copyWith(sessions: sessions, tabs: tabs),
    );
  }

  Future<void> touchSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.touchSession(sessionId);
    _emitSnapshot(await _dataStore.loadProjectData(repo));
  }

  /// Persists a manual session arrangement. [orderedSessionIds] is the new
  /// top-to-bottom order (used by [AppSessionSort.manual]).
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    // Optimistic: stamp the new sortOrder in memory and emit immediately so the
    // list stays where the user dropped it, then persist on disk in the
    // background. Awaiting the per-file writes + a full reload first made the
    // row snap back, then jump once persistence finished (~1-2s later).
    final orderById = <String, int>{
      for (var i = 0; i < orderedSessionIds.length; i++)
        orderedSessionIds[i]: i + 1,
    };
    final sessions = [
      for (final s in state.sessions)
        orderById.containsKey(s.sessionId)
            ? s.copyWith(sortOrder: orderById[s.sessionId])
            : s,
    ];
    _emitSnapshot(
      _dataStore.deriveSnapshot(projects: state.projects, sessions: sessions),
      base: state.copyWith(sessions: sessions),
    );
    await repo.reorderSessions(orderedSessionIds);
  }

  Future<void> toggleSessionPin(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.toggleSessionPin(sessionId);
    _emitSnapshot(await _dataStore.loadProjectData(repo));
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
      final newIdx = idx < _tabStore.length ? idx : _tabStore.length - 1;
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
    for (final tab in _tabStore.allTabs) {
      for (final session in tab.sessions) {
        session.dispose();
      }
      await tab.disposeBus();
    }
    _tabStore.clear();
    await super.close();
  }
}
