import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/terminal_session.dart';

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

  ChatTabInfo copyWith({bool? isRunning}) {
    return ChatTabInfo(
      id: id,
      title: title,
      subtitle: subtitle,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  List<Object?> get props => [id, title, subtitle, isRunning];
}

class _InternalTab {
  _InternalTab({required this.info, required this.session});
  ChatTabInfo info;
  final TerminalSession session;
}

class ChatState extends Equatable {
  const ChatState({
    this.tabs = const [],
    this.activeTabIndex = 0,
    this.sessions = const [],
    this.activeSessionId,
    this.selectedMemberId = '',
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final List<FlashskySession> sessions;
  final String? activeSessionId;
  final String selectedMemberId;

  ChatState copyWith({
    List<ChatTabInfo>? tabs,
    int? activeTabIndex,
    List<FlashskySession>? sessions,
    String? activeSessionId,
    String? selectedMemberId,
    bool clearActiveSessionId = false,
  }) {
    return ChatState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      sessions: sessions ?? this.sessions,
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
    );
  }

  @override
  List<Object?> get props =>
      [tabs, activeTabIndex, sessions, activeSessionId, selectedMemberId];
}

class ChatCubit extends Cubit<ChatState> {
  ChatCubit() : super(const ChatState());

  final List<_InternalTab> _internalTabs = [];
  TerminalSession? _legacySession;
  String? _legacyTeamId;
  String? _legacyMemberId;

  TerminalSession? get currentSession {
    if (_internalTabs.isNotEmpty) {
      return _internalTabs[state.activeTabIndex].session;
    }
    return _legacySession;
  }

  Future<void> loadSessions(SessionRepository repo) async {
    final sessions = await repo.loadSessions();
    emit(state.copyWith(sessions: sessions));
  }

  void openSessionTab(FlashskySession session) {
    final existingIdx =
        _internalTabs.indexWhere((t) => t.info.id == session.sessionId);
    if (existingIdx != -1) {
      emit(state.copyWith(
          activeTabIndex: existingIdx,
          activeSessionId: session.sessionId));
      return;
    }
    final ts = TerminalSession();
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.display.isNotEmpty ? session.display : session.kind,
      subtitle: session.cwd,
    );
    _internalTabs.add(_InternalTab(info: info, session: ts));
    emit(state.copyWith(
      tabs: [...state.tabs, info],
      activeTabIndex: _internalTabs.length - 1,
      activeSessionId: session.sessionId,
    ));
    try {
      ts.connectResume(session.sessionId);
      _updateTabRunning(info.id, true);
    } on Object catch (e) {
      ts.terminal.write('\r\n[Failed to resume session: $e]\r\n');
    }
  }

  void openMemberTab(TeamConfig team, TeamMemberConfig member) {
    final tabId = 'member-${member.id}';
    final existingIdx =
        _internalTabs.indexWhere((t) => t.info.id == tabId);
    if (existingIdx != -1) {
      emit(state.copyWith(
          activeTabIndex: existingIdx, selectedMemberId: member.id));
      return;
    }
    final ts = TerminalSession();
    final info = ChatTabInfo(
      id: tabId,
      title: member.name,
      subtitle: '${team.name} / local',
    );
    _internalTabs.add(_InternalTab(info: info, session: ts));
    emit(state.copyWith(
      tabs: [...state.tabs, info],
      activeTabIndex: _internalTabs.length - 1,
      selectedMemberId: member.id,
    ));
    try {
      ts.connect(team, member);
      _updateTabRunning(tabId, true);
    } on Object catch (e) {
      ts.terminal.write('\r\n[Failed to start session: $e]\r\n');
    }
  }

  void closeTab(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    final tab = _internalTabs.removeAt(index);
    tab.session.dispose();
    if (_internalTabs.isEmpty) {
      emit(state.copyWith(
          tabs: [], activeTabIndex: 0, clearActiveSessionId: true));
    } else {
      final newIdx = state.activeTabIndex >= _internalTabs.length
          ? _internalTabs.length - 1
          : state.activeTabIndex;
      emit(state.copyWith(
          tabs: _internalTabs.map((t) => t.info).toList(),
          activeTabIndex: newIdx));
    }
  }

  void selectTab(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    final tab = _internalTabs[index];
    final memberId = tab.info.id.startsWith('member-')
        ? tab.info.id.replaceFirst('member-', '')
        : state.selectedMemberId;
    emit(state.copyWith(activeTabIndex: index, selectedMemberId: memberId));
  }

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      _killLegacySession();
      emit(state.copyWith(selectedMemberId: ''));
      return;
    }
    if (team.members.any((m) => m.id == state.selectedMemberId)) return;
    final lead = team.members.where((m) => m.name == 'team-lead');
    final newId =
        lead.isEmpty ? team.members.first.id : lead.first.id;
    _killLegacySession();
    emit(state.copyWith(selectedMemberId: newId));
  }

  void selectMember(String memberId) {
    if (state.selectedMemberId == memberId) return;
    _killLegacySession();
    emit(state.copyWith(selectedMemberId: memberId));
  }

  String selectedMemberName(TeamConfig team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession ensureSession(TeamConfig team) {
    if (_legacySession != null &&
        _legacyTeamId == team.id &&
        _legacyMemberId == state.selectedMemberId) {
      return _legacySession!;
    }
    _legacySession?.dispose();
    _legacySession = TerminalSession();
    _legacyTeamId = team.id;
    _legacyMemberId = state.selectedMemberId;
    return _legacySession!;
  }

  void connectSession(TeamConfig team) {
    final session = ensureSession(team);
    if (session.isRunning) return;
    final memberId = state.selectedMemberId;
    if (memberId.isEmpty) {
      session.terminal.write('\r\n[No member selected]\r\n');
      return;
    }
    final member = team.members.firstWhere((m) => m.id == memberId,
        orElse: () => team.members.first);
    session.connect(team, member);
  }

  void disconnectSession() {
    _legacySession?.disconnect();
  }

  void restartSession(TeamConfig team) {
    _killLegacySession();
    ensureSession(team);
    connectSession(team);
  }

  void addSystemMessage(String content) {
    final target = _internalTabs.isNotEmpty
        ? _internalTabs[state.activeTabIndex].session
        : _legacySession;
    target?.terminal.write('\r\n[system] $content\r\n');
  }

  void _killLegacySession() {
    _legacySession?.dispose();
    _legacySession = null;
    _legacyTeamId = null;
    _legacyMemberId = null;
  }

  void _updateTabRunning(String tabId, bool isRunning) {
    final idx = _internalTabs.indexWhere((t) => t.info.id == tabId);
    if (idx == -1) return;
    _internalTabs[idx].info =
        _internalTabs[idx].info.copyWith(isRunning: isRunning);
    emit(state.copyWith(
        tabs: _internalTabs.map((t) => t.info).toList()));
  }

  @override
  Future<void> close() async {
    _killLegacySession();
    for (final tab in _internalTabs) {
      tab.session.dispose();
    }
    _internalTabs.clear();
    await super.close();
  }
}
