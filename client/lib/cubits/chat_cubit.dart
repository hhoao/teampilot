import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_project.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/app_storage.dart';
import '../services/temp_team_cleaner.dart';
import '../services/terminal_session.dart';
import '../utils/logger.dart';

typedef TerminalSessionFactory =
    TerminalSession Function({required String executable});
typedef PostFrameScheduler = void Function(VoidCallback callback);
typedef CliSessionDescriptorExists =
    bool Function(String sessionId, String primaryPath);

class ChatTabInfo extends Equatable {
  const ChatTabInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isRunning = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool isRunning;

  ChatTabInfo copyWith({String? title, String? subtitle, bool? isRunning}) {
    return ChatTabInfo(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  List<Object?> get props => [id, title, subtitle, isRunning];
}

class _InternalTab {
  _InternalTab({
    required this.info,
    required this.sessionTeamName,
    this.selectedMemberId = '',
  });

  ChatTabInfo info;
  TerminalSession? resumeSession;
  String selectedMemberId;
  final String sessionTeamName;
  final Map<String, TerminalSession> memberShells = {};

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
    );
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
  ];
}

class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    required String Function() executableResolver,
    TerminalSessionFactory terminalSessionFactory = TerminalSession.new,
    PostFrameScheduler? postFrameScheduler,
    TempTeamCleaner? tempTeamCleaner,
    String? Function()? llmConfigPathOverride,
    bool Function()? autoLaunchAllMembersOnConnect,
    CliSessionDescriptorExists? cliSessionDescriptorExists,
    SessionRepository? sessionRepository,
  }) : _terminalSessionFactory = terminalSessionFactory,
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _tempTeamCleaner = tempTeamCleaner,
       _llmConfigPathOverride = llmConfigPathOverride,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _cliSessionDescriptorExists =
           cliSessionDescriptorExists ??
           ((String sid, String path) =>
               AppStorage.cliSessionDescriptorExists(sid, path)),
       _sessionRepository = sessionRepository,
       _executableResolver = executableResolver,
       super(const ChatState());

  final List<_InternalTab> _internalTabs = [];
  var _scopeSessionsToSelectedTeam = false;
  String? _selectedTeamId;
  final TerminalSessionFactory _terminalSessionFactory;
  final PostFrameScheduler _postFrameScheduler;
  final TempTeamCleaner? _tempTeamCleaner;
  final String? Function()? _llmConfigPathOverride;
  final bool Function()? _autoLaunchAllMembersOnConnect;
  final CliSessionDescriptorExists _cliSessionDescriptorExists;
  final SessionRepository? _sessionRepository;
  final String Function() _executableResolver;

  TerminalSession _newSession() =>
      _terminalSessionFactory(executable: _executableResolver());

  Map<String, String>? _spawnEnvironment() {
    final override = _llmConfigPathOverride?.call();
    if (override == null || override.isEmpty) return null;
    return {'LLM_CONFIG_PATH': override};
  }

  var _sessionCounter = 0;

  int _nextCounter() => _sessionCounter++;

  /// Generates a session-team name the CLI will use as a directory name under
  /// `~/.flashskyai/teams/`.  The CLI normalises names by lowercasing and
  /// replacing non-alphanumeric runs with a single dash, so we produce the
  /// same format here so the [TempTeamCleaner] can reliably locate and remove
  /// the directories later.
  static String _cliTeamName(String baseName, int counter) {
    final slug = baseName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$slug-$counter';
  }

  String _allocSessionTeamName(String baseName) {
    final name = _cliTeamName(baseName, _nextCounter());
    // Register this temp team name so [TempTeamCleaner.cleanup] can remove
    // the CLI dir later (on next app startup or on app close). Fire-and-forget
    // — the registry write is async and best-effort.
    final cleaner = _tempTeamCleaner;
    if (cleaner != null) {
      unawaited(
        cleaner.record(name).catchError((Object e) {
          appLogger.w('TempTeamCleaner.record failed for $name: $e');
        }),
      );
    }
    return name;
  }

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
  }) async {
    final session = await repo.createSession(
      projectId,
      sessionTeam: sessionTeamId,
    );
    await loadProjectData(repo);
    return session;
  }

  Future<void> createProjectWithFirstSession(
    String primaryPath,
    SessionRepository repo, {
    String sessionTeamId = '',
  }) async {
    final project = await repo.createProject(primaryPath);
    await repo.createSession(project.projectId, sessionTeam: sessionTeamId);
    await loadProjectData(repo);
  }

  void openSessionTab(
    AppSession session, {
    TeamConfig? team,
    TeamMemberConfig? member,
    SessionRepository? repo,
    String emptyDisplayTitleFallback = 'New Chat',
    bool connectImmediately = true,
  }) {
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
    final ts = _newSession();
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.resolveDisplayTitle(emptyDisplayTitleFallback),
      subtitle: session.primaryPath,
    );
    final launched = session.launchState == AppSessionLaunchState.started;
    final cliHasSession = _cliSessionDescriptorExists(
      session.sessionId,
      session.primaryPath,
    );
    final useResume = launched && cliHasSession;
    final cliTeamDirName = useResume
        ? () {
            final d = session.effectiveCliTeamDirectory.trim();
            return d.isNotEmpty ? d : _assignSessionTeam(team);
          }()
        : _assignSessionTeam(team);
    final internalTab = _InternalTab(
      info: info,
      sessionTeamName: cliTeamDirName,
    );
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
    if (connectImmediately) {
      _postFrameScheduler(() {
        try {
          ts.connect(
            workingDirectory: session.primaryPath,
            additionalDirectories: session.additionalPaths,
            fixedSessionId: useResume ? null : session.sessionId,
            resumeSessionId: useResume ? session.sessionId : null,
            team: team,
            member: member,
            sessionTeam: cliTeamDirName,
            extraEnvironment: _spawnEnvironment(),
            onProcessFailed: () => _updateTabRunning(info.id),
            onProcessStarted: repo == null
                ? null
                : () {
                    unawaited(
                      repo
                          .markSessionLaunched(
                            session.sessionId,
                            launchTeam: cliTeamDirName,
                          )
                          .then((_) {
                            if (isClosed) return;
                            final sessions = state.sessions.map((s) {
                              if (s.sessionId != session.sessionId) {
                                return s;
                              }
                              final lt = cliTeamDirName.trim();
                              return s.copyWith(
                                launchState: AppSessionLaunchState.started,
                                launchTeam: lt.isNotEmpty ? lt : s.launchTeam,
                                updatedAt:
                                    DateTime.now().millisecondsSinceEpoch,
                              );
                            }).toList();
                            _emitWithDerivedSessionsAndProjects(
                              state.copyWith(sessions: sessions),
                            );
                          }),
                    );
                  },
          );
          _updateTabRunning(info.id);
          if (_autoLaunchAllMembersOnConnect?.call() == true &&
              team != null &&
              member != null) {
            _launchRemainingMembersForTab(team, member.id, internalTab);
          }
        } on Object catch (e) {
          ts.terminal.write('\r\n[Failed to resume session: $e]\r\n');
          _updateTabRunning(info.id);
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
    final cwd = Directory.current.path.trim();
    final project = await repo.createProject(cwd);
    final session = await repo.createSession(
      project.projectId,
      sessionTeam: team.id,
    );
    await loadProjectData(repo);
    if (isClosed) return;
    openSessionTab(
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
      }
      return;
    }
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    _scheduleMemberConnect(team, member, tab);
  }

  void _scheduleMemberConnect(
    TeamConfig team,
    TeamMemberConfig member,
    _InternalTab tab,
  ) {
    tab.selectedMemberId = member.id;
    final shell = tab.memberShells.putIfAbsent(member.id, _newSession);
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
      ),
    );
    if (shell.isRunning) {
      _updateTabRunning(tab.info.id);
      return;
    }
    final launch = _workingDirectoryAndAddDirsForTab(tab);
    _postFrameScheduler(() {
      try {
        if (shell.isRunning) {
          _updateTabRunning(tab.info.id);
          return;
        }
        shell.connect(
          workingDirectory: launch.$1,
          additionalDirectories: launch.$2,
          team: team,
          member: member,
          sessionTeam: tab.sessionTeamName,
          extraEnvironment: _spawnEnvironment(),
          onProcessStarted: () => _updateTabRunning(tab.info.id),
          onProcessFailed: () => _updateTabRunning(tab.info.id),
        );
        _updateTabRunning(tab.info.id);
      } on Object catch (e) {
        shell.terminal.write('\r\n[Failed to start session: $e]\r\n');
        _updateTabRunning(tab.info.id);
      }
    });
  }

  void closeTab(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    final tab = _internalTabs.removeAt(index);
    for (final session in tab.sessions) {
      session.dispose();
    }
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
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    for (var i = _internalTabs.length - 1; i >= 0; i--) {
      if (i == index) continue;
      final tab = _internalTabs.removeAt(i);
      for (final session in tab.sessions) {
        session.dispose();
      }
    }
    final kept = _internalTabs.single;
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeTabIndex: 0,
        activeSessionId: kept.info.id,
        selectedMemberId: kept.selectedMemberId,
      ),
    );
  }

  void closeRightTabs(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    for (var i = _internalTabs.length - 1; i > index; i--) {
      final tab = _internalTabs.removeAt(i);
      for (final session in tab.sessions) {
        session.dispose();
      }
    }
    final active = _activeTab;
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeTabIndex: state.activeTabIndex.clamp(0, _internalTabs.length - 1),
        activeSessionId: active?.info.id,
        selectedMemberId: active?.selectedMemberId ?? '',
      ),
    );
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

  bool isMemberRunning(String memberId) {
    final shell = _activeTab?.memberShells[memberId];
    return shell?.isRunning ?? false;
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
      return tab.memberShells.putIfAbsent(tab.selectedMemberId, _newSession);
    }
    return tab.resumeSession ??= _newSession();
  }

  Future<void> connectSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
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
        session?.terminal.write('\r\n[No member selected]\r\n');
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
      session?.terminal.write('\r\n[No member selected]\r\n');
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
    tab.memberShells[tab.selectedMemberId]?.disconnect();
    _updateTabRunning(tab.info.id);
  }

  Future<void> restartSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _sessionRepository;
    if (_autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = state.selectedMemberId.isNotEmpty
          ? state.selectedMemberId
          : _defaultMemberId(team);
      final tab = _activeTab;
      if (tab != null) {
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
    target?.terminal.write('\r\n[system] $content\r\n');
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
  }

  /// [openSessionTab] / sidebar session tabs use the persisted [AppSession]
  /// id as [ChatTabInfo.id]; local-only tabs use `local-<teamId>`.
  (String, List<String>) _workingDirectoryAndAddDirsForTab(_InternalTab tab) {
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (Directory.current.path, const <String>[]);
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
      return (Directory.current.path, addl);
    }
    return (Directory.current.path, const <String>[]);
  }

  _InternalTab _appendLocalTab(TeamConfig team, {required bool emitChange}) {
    final info = _localSessionInfo(team);
    final tab = _InternalTab(
      info: info,
      sessionTeamName: _allocSessionTeamName(team.name),
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

  String _assignSessionTeam(TeamConfig? team) {
    final fallbackName = team?.name.trim().isNotEmpty == true
        ? team!.name
        : 'session';
    // Persisted as [AppSession.launchTeam] via [SessionRepository.markSessionLaunched]
    // when the process starts ([openSessionTab] onProcessStarted).
    return _allocSessionTeamName(fallbackName);
  }

  String _defaultMemberId(TeamConfig team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.name == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  List<ChatTabInfo> _visibleTabs() {
    return _internalTabs.map((t) => t.info).toList();
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    for (final tab in _internalTabs) {
      for (final session in tab.sessions) {
        session.dispose();
      }
    }
    _internalTabs.clear();
    final cleaner = _tempTeamCleaner;
    if (cleaner != null) {
      try {
        await cleaner.cleanup();
      } on Object catch (e) {
        appLogger.w('TempTeamCleaner failed on close: $e');
      }
    }
    await super.close();
  }
}
