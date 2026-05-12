import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/temp_team_cleaner.dart';
import '../services/terminal_session.dart';
import '../utils/logger.dart';

typedef TerminalSessionFactory = TerminalSession Function();
typedef PostFrameScheduler = void Function(VoidCallback callback);

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
    this.sessions = const [],
    this.activeSessionId,
    this.selectedMemberId = '',
    this.stateVersion = 0,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final List<FlashskySession> sessions;
  final String? activeSessionId;
  final String selectedMemberId;
  final int stateVersion;

  ChatState copyWith({
    List<ChatTabInfo>? tabs,
    int? activeTabIndex,
    List<FlashskySession>? sessions,
    String? activeSessionId,
    String? selectedMemberId,
    bool clearActiveSessionId = false,
    int? stateVersion,
  }) {
    return ChatState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      sessions: sessions ?? this.sessions,
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
    sessions,
    activeSessionId,
    selectedMemberId,
    stateVersion,
  ];
}

class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    TerminalSessionFactory terminalSessionFactory = TerminalSession.new,
    PostFrameScheduler? postFrameScheduler,
    TempTeamCleaner? tempTeamCleaner,
  }) : _terminalSessionFactory = terminalSessionFactory,
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _tempTeamCleaner = tempTeamCleaner,
       super(const ChatState());

  final List<_InternalTab> _internalTabs = [];
  final TerminalSessionFactory _terminalSessionFactory;
  final PostFrameScheduler _postFrameScheduler;
  final TempTeamCleaner? _tempTeamCleaner;
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
    final cleaner = _tempTeamCleaner;
    if (cleaner != null) {
      appLogger.d('Recording temp team "$name"');
      cleaner.record(name).catchError((e) {
        appLogger.w('Failed to record temp team "$name": $e');
      });
    }
    return name;
  }

  static void _defaultPostFrameScheduler(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
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

  Future<void> loadSessions(SessionRepository repo) async {
    final sessions = await repo.loadSessions();
    emit(state.copyWith(sessions: sessions));
  }

  Future<void> createSession(String cwd, SessionRepository repo) async {
    final session = await repo.createSession(cwd);
    final sessions = [...state.sessions, session]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    emit(state.copyWith(sessions: sessions));
  }

  void openSessionTab(FlashskySession session, {TeamConfig? team, TeamMemberConfig? member, SessionRepository? repo}) {
    final sw = Stopwatch()..start();
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
    final ts = _terminalSessionFactory();
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.displayTitle,
      subtitle: session.cwd,
    );
    final sessionTeamName = _assignSessionTeam(session.sessionId, team, repo);
    final internalTab = _InternalTab(
      info: info,
      sessionTeamName: sessionTeamName,
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
    appLogger.d('[perf] openSessionTab emit: ${sw.elapsedMilliseconds}ms');
    _postFrameScheduler(() {
      try {
        final sw2 = Stopwatch()..start();
        ts.connect(
          workingDirectory: session.cwd,
          team: team,
          member: member,
          sessionTeam: sessionTeamName,
        );
        appLogger.d('[perf] connect: ${sw2.elapsedMilliseconds}ms');
        _updateTabRunning(info.id);
      } on Object catch (e) {
        ts.terminal.write('\r\n[Failed to resume session: $e]\r\n');
      }
    });
  }

  void ensureSessionTab(TeamConfig team) {
    if (_internalTabs.isEmpty) {
      final info = _localSessionInfo(team);
      _internalTabs.add(
        _InternalTab(
          info: info,
          sessionTeamName: _allocSessionTeamName(team.name),
          selectedMemberId: _defaultMemberId(team),
        ),
      );
    }
    final tab = _activeTab;
    if (tab == null) return;
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
      ),
    );
  }

  void openMemberTab(TeamConfig team, TeamMemberConfig member) {
    final sw = Stopwatch()..start();
    final tab = _ensureActiveSessionTab(team, emitChange: true);
    tab.selectedMemberId = member.id;
    final shell = tab.memberShells.putIfAbsent(
      member.id,
      _terminalSessionFactory,
    );
    emit(
      state.copyWith(
        tabs: _visibleTabs(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
      ),
    );
    appLogger.d('[perf] openMemberTab emit: ${sw.elapsedMilliseconds}ms');
    if (shell.isRunning) {
      _updateTabRunning(tab.info.id);
      return;
    }
    _postFrameScheduler(() {
      try {
        final sw2 = Stopwatch()..start();
        shell.connect(
          workingDirectory: Directory.current.path,
          team: team,
          member: member,
          sessionTeam: tab.sessionTeamName,
        );
        appLogger.d('[perf] connect: ${sw2.elapsedMilliseconds}ms');
        _updateTabRunning(tab.info.id);
      } on Object catch (e) {
        shell.terminal.write('\r\n[Failed to start session: $e]\r\n');
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
    emit(state.copyWith(
      tabs: _visibleTabs(),
      activeTabIndex: 0,
      activeSessionId: kept.info.id,
      selectedMemberId: kept.selectedMemberId,
    ));
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
    emit(state.copyWith(
      tabs: _visibleTabs(),
      activeTabIndex: state.activeTabIndex.clamp(0, _internalTabs.length - 1),
      activeSessionId: active?.info.id,
      selectedMemberId: active?.selectedMemberId ?? '',
    ));
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

  void launchAllMembers(TeamConfig team) {
    final validMembers = team.members.where((m) => m.isValid).toList();
    for (final member in validMembers) {
      openMemberTab(team, member);
    }
  }

  String selectedMemberName(TeamConfig team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession ensureSession(TeamConfig team) {
    final tab = _ensureActiveSessionTab(team, emitChange: false);
    if (tab.selectedMemberId.isEmpty) {
      tab.selectedMemberId = _defaultMemberId(team);
    }
    if (tab.selectedMemberId.isNotEmpty) {
      return tab.memberShells.putIfAbsent(
        tab.selectedMemberId,
        _terminalSessionFactory,
      );
    }
    return tab.resumeSession ??= _terminalSessionFactory();
  }

  void connectSession(TeamConfig team) {
    final memberId = state.selectedMemberId;
    if (memberId.isEmpty) {
      final session = ensureSession(team);
      session.terminal.write('\r\n[No member selected]\r\n');
      return;
    }
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => team.members.first,
    );
    openMemberTab(team, member);
  }

  void disconnectSession() {
    final tab = _activeTab;
    if (tab == null) return;
    tab.memberShells[tab.selectedMemberId]?.disconnect();
    _updateTabRunning(tab.info.id);
  }

  void restartSession(TeamConfig team) {
    disconnectSession();
    connectSession(team);
  }

  Future<void> renameSession(SessionRepository repo, String sessionId, String newName) async {
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
    emit(state.copyWith(sessions: sessions, tabs: tabs));
  }

  void deleteSession(SessionRepository repo, String sessionId) {
    final wasActive = state.activeSessionId == sessionId;
    final sessions = state.sessions.where((s) => s.sessionId != sessionId).toList();
    final idx = _internalTabs.indexWhere((t) => t.info.id == sessionId);
    if (idx != -1) {
      final tab = _internalTabs.removeAt(idx);
      for (final session in tab.sessions) {
        session.dispose();
      }
    }
    final tabs = _internalTabs.map((t) => t.info).toList();

    if (wasActive && _internalTabs.isNotEmpty) {
      final newIdx = idx < _internalTabs.length ? idx : _internalTabs.length - 1;
      final nextTab = _internalTabs[newIdx];
      emit(state.copyWith(
        sessions: sessions,
        tabs: tabs,
        activeTabIndex: newIdx,
        activeSessionId: nextTab.info.id,
        selectedMemberId: nextTab.selectedMemberId,
      ));
    } else if (_internalTabs.isEmpty) {
      emit(state.copyWith(
        sessions: sessions,
        tabs: [],
        activeTabIndex: 0,
        clearActiveSessionId: true,
      ));
    } else {
      emit(state.copyWith(sessions: sessions, tabs: tabs));
    }

    repo.deleteSession(sessionId);
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
    emit(state.copyWith(tabs: _visibleTabs(), stateVersion: state.stateVersion + 1));
  }

  _InternalTab _ensureActiveSessionTab(
    TeamConfig team, {
    required bool emitChange,
  }) {
    final existing = _activeTab;
    if (existing != null) return existing;

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

  ChatTabInfo _localSessionInfo(TeamConfig team) {
    return ChatTabInfo(
      id: 'local-${team.id}',
      title: team.name,
      subtitle: 'local session',
    );
  }

  String _assignSessionTeam(String sessionId, TeamConfig? team, SessionRepository? repo) {
    final fallbackName = team?.name.trim().isNotEmpty == true
        ? team!.name
        : 'session';
    final name = _allocSessionTeamName(fallbackName);
    if (repo != null) {
      repo.updateSessionTeam(sessionId, name);
    }
    return name;
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
