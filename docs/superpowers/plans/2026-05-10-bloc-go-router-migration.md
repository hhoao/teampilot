# BLoC + go_router Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 5 ChangeNotifier controllers with BLoC Cubits and setState navigation with go_router ShellRoute.

**Architecture:** 5 Cubs (Team, Chat, Config, LlmConfig, Layout) with Equatable state, wrapped in MultiBlocProvider above MaterialApp.router. go_router ShellRoute renders ContextSidebar + route content in a Row.

**Tech Stack:** flutter_bloc ^9.1.0, bloc_concurrency ^0.3.0, equatable ^2.0.5, go_router ^16.3.0, path_provider ^2.1.2, path ^1.9.0, json_annotation ^4.9.0, uuid ^4.5.1, window_manager ^0.5.1, web_socket_channel ^2.4.0, multi_split_view ^3.6.1, logger ^2.6.0, build_runner ^2.6.0, json_serializable ^6.9.5

---

### Task 1: Update pubspec.yaml and install dependencies

**Files:**
- Modify: `client/pubspec.yaml`

- [ ] **Step 1: Replace pubspec.yaml dependencies**

```bash
cd /home/hhoa/git/hhoa/flashskyai-ui/client
```

Replace the `dependencies` and `dev_dependencies` sections with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  cupertino_icons: ^1.0.8
  shared_preferences: ^2.5.3
  xterm: ^4.0.0
  flutter_pty: ^0.4.2

  flutter_bloc: ^9.1.0
  bloc_concurrency: ^0.3.0
  equatable: ^2.0.5
  go_router: ^16.3.0
  path_provider: ^2.1.2
  path: ^1.9.0
  json_annotation: ^4.9.0
  uuid: ^4.5.1
  window_manager: ^0.5.1
  web_socket_channel: ^2.4.0
  multi_split_view: ^3.6.1
  logger: ^2.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  build_runner: ^2.6.0
  json_serializable: ^6.9.5
```

- [ ] **Step 2: Run flutter pub get**

```bash
flutter pub get
```

Expected: exits 0, no errors.

---

### Task 2: Create directory structure for cubits and router

**Files:**
- Create: `client/lib/cubits/` (directory)
- Create: `client/lib/router/` (directory)

- [ ] **Step 1: Create directories**

```bash
mkdir -p /home/hhoa/git/hhoa/flashskyai-ui/client/lib/cubits
mkdir -p /home/hhoa/git/hhoa/flashskyai-ui/client/lib/router
```

---

### Task 3: Create TeamCubit

**Files:**
- Create: `client/lib/cubits/team_cubit.dart`

- [ ] **Step 1: Write TeamState and TeamCubit**

```dart
import 'dart:io';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../repositories/team_repository.dart';
import '../services/launch_command_builder.dart';

class TeamState extends Equatable {
  const TeamState({
    this.teams = const [],
    this.selectedTeamId,
    this.statusMessage = '',
    this.isLoading = true,
    this.isLaunching = false,
  });

  final List<TeamConfig> teams;
  final String? selectedTeamId;
  final String statusMessage;
  final bool isLoading;
  final bool isLaunching;

  TeamConfig? get selectedTeam {
    for (final team in teams) {
      if (team.id == selectedTeamId) return team;
    }
    return teams.isEmpty ? null : teams.first;
  }

  TeamState copyWith({
    List<TeamConfig>? teams,
    String? selectedTeamId,
    String? statusMessage,
    bool? isLoading,
    bool? isLaunching,
    bool clearSelectedTeamId = false,
  }) {
    return TeamState(
      teams: teams ?? this.teams,
      selectedTeamId: clearSelectedTeamId ? null : (selectedTeamId ?? this.selectedTeamId),
      statusMessage: statusMessage ?? this.statusMessage,
      isLoading: isLoading ?? this.isLoading,
      isLaunching: isLaunching ?? this.isLaunching,
    );
  }

  @override
  List<Object?> get props => [teams, selectedTeamId, statusMessage, isLoading, isLaunching];
}

typedef TeamLauncher = Future<void> Function(TeamConfig team, TeamMemberConfig member);
typedef StringProvider = String Function();

class TeamCubit extends Cubit<TeamState> {
  TeamCubit({
    required TeamRepository repository,
    TeamLauncher? launcher,
    StringProvider? currentDirectoryProvider,
    StringProvider? idProvider,
  }) : _repository = repository,
       _launcher = launcher ?? ((team, member) => LaunchCommandBuilder.launch(team, member: member)),
       _currentDirectoryProvider = currentDirectoryProvider ?? (() => Directory.current.path),
       _idProvider = idProvider ?? (() => DateTime.now().microsecondsSinceEpoch.toString()),
       super(const TeamState());

  final TeamRepository _repository;
  final TeamLauncher _launcher;
  final StringProvider _currentDirectoryProvider;
  final StringProvider _idProvider;

  String previewFor(TeamMemberConfig member) {
    final team = state.selectedTeam;
    return team == null ? '' : LaunchCommandBuilder.preview(team, member);
  }

  String get selectedCommandPreview {
    final team = state.selectedTeam;
    if (team == null || team.members.isEmpty) return '';
    return LaunchCommandBuilder.preview(team, team.members.first);
  }

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    var teams = await _repository.loadTeams();
    if (teams.isEmpty) {
      teams = [_defaultTeam()];
      await _repository.saveTeams(teams);
    }
    emit(state.copyWith(
      teams: teams,
      selectedTeamId: teams.first.id,
      isLoading: false,
      statusMessage: 'Ready.',
    ));
  }

  void selectTeam(String id) {
    if (state.teams.any((team) => team.id == id)) {
      final team = state.teams.firstWhere((t) => t.id == id);
      emit(state.copyWith(selectedTeamId: id, statusMessage: 'Selected ${team.name}.'));
    }
  }

  Future<void> addTeam() async {
    final team = TeamConfig(
      id: _idProvider(),
      name: 'New Team',
      workingDirectory: _currentDirectoryProvider(),
      members: [TeamMemberConfig(id: _idProvider(), name: 'New Member')],
    );
    final teams = [...state.teams, team];
    emit(state.copyWith(teams: teams, selectedTeamId: team.id, statusMessage: 'Added ${team.name}.'));
    await _repository.saveTeams(teams);
  }

  Future<void> updateSelected(TeamConfig updated) async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    final normalized = updated.members.isEmpty ? updated.copyWith(members: [_defaultMember()]) : updated;
    final teams = [for (final team in state.teams) if (team.id == selected.id) normalized else team];
    emit(state.copyWith(
      teams: teams,
      selectedTeamId: normalized.id,
      statusMessage: normalized.isValid ? 'Saved ${normalized.name}.' : 'Team name and directory are required.',
    ));
    await _repository.saveTeams(teams);
  }

  Future<void> deleteSelected() async {
    final selected = state.selectedTeam;
    if (selected == null) return;
    var teams = state.teams.where((team) => team.id != selected.id).toList();
    if (teams.isEmpty) teams = [_defaultTeam()];
    emit(state.copyWith(teams: teams, selectedTeamId: teams.first.id, statusMessage: 'Deleted ${selected.name}.'));
    await _repository.saveTeams(teams);
  }

  Future<void> addMember() async {
    final team = state.selectedTeam;
    if (team == null) return;
    final member = TeamMemberConfig(id: _idProvider(), name: 'New Member');
    await updateSelected(team.copyWith(members: [...team.members, member]));
    emit(state.copyWith(statusMessage: 'Added ${member.name}.'));
  }

  Future<void> updateMember(String memberId, TeamMemberConfig updated) async {
    final team = state.selectedTeam;
    if (team == null) return;
    await updateSelected(team.copyWith(
      members: [for (final m in team.members) if (m.id == memberId) updated else m],
    ));
  }

  Future<void> deleteMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null) return;
    if (team.members.length == 1) {
      emit(state.copyWith(statusMessage: 'A team needs at least one member.'));
      return;
    }
    final deleted = team.members.firstWhere((m) => m.id == memberId);
    await updateSelected(team.copyWith(
      members: team.members.where((m) => m.id != memberId).toList(growable: false),
    ));
    emit(state.copyWith(statusMessage: 'Deleted ${deleted.name}.'));
  }

  Future<void> launchMember(String memberId) async {
    final team = state.selectedTeam;
    if (team == null || !team.isValid) {
      emit(state.copyWith(statusMessage: 'Team name and directory are required.'));
      return;
    }
    final member = team.members.firstWhere((m) => m.id == memberId, orElse: () => const TeamMemberConfig(id: '', name: ''));
    if (!member.isValid) {
      emit(state.copyWith(statusMessage: 'Member name is required.'));
      return;
    }
    emit(state.copyWith(isLaunching: true, statusMessage: 'Starting ${member.name}...'));
    try {
      await _launcher(team, member);
      emit(state.copyWith(isLaunching: false, statusMessage: 'Started ${member.name}: ${LaunchCommandBuilder.preview(team, member)}'));
    } on Object catch (error) {
      emit(state.copyWith(isLaunching: false, statusMessage: 'Launch failed: $error'));
    }
  }

  Future<void> launchSelectedTeam() async {
    final team = state.selectedTeam;
    if (team == null || !team.isValid) {
      emit(state.copyWith(statusMessage: 'Team name and directory are required.'));
      return;
    }
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) {
      emit(state.copyWith(statusMessage: 'At least one valid member is required.'));
      return;
    }
    emit(state.copyWith(isLaunching: true, statusMessage: 'Starting ${validMembers.length} members...'));
    try {
      for (final member in validMembers) {
        await _launcher(team, member);
      }
      emit(state.copyWith(isLaunching: false, statusMessage: 'Started ${validMembers.length} members.'));
    } on Object catch (error) {
      emit(state.copyWith(isLaunching: false, statusMessage: 'Launch failed: $error'));
    }
  }

  TeamConfig _defaultTeam() => TeamConfig(
    id: 'default',
    name: 'Default Team',
    workingDirectory: _currentDirectoryProvider(),
    members: [_defaultMember()],
  );

  TeamMemberConfig _defaultMember() => const TeamMemberConfig(id: 'team-lead', name: 'team-lead');
}
```

---

### Task 4: Create ChatCubit

**Files:**
- Create: `client/lib/cubits/chat_cubit.dart`

- [ ] **Step 1: Write ChatState and ChatCubit**

```dart
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
    return ChatTabInfo(id: id, title: title, subtitle: subtitle, isRunning: isRunning ?? this.isRunning);
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
      activeSessionId: clearActiveSessionId ? null : (activeSessionId ?? this.activeSessionId),
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
    );
  }

  @override
  List<Object?> get props => [tabs, activeTabIndex, sessions, activeSessionId, selectedMemberId];
}

class ChatCubit extends Cubit<ChatState> {
  ChatCubit() : super(const ChatState());

  final List<_InternalTab> _internalTabs = [];
  TerminalSession? _legacySession;
  String? _legacyTeamId;
  String? _legacyMemberId;

  TerminalSession? get currentSession {
    if (_internalTabs.isNotEmpty) return _internalTabs[state.activeTabIndex].session;
    return _legacySession;
  }

  Future<void> loadSessions(SessionRepository repo) async {
    final sessions = await repo.loadSessions();
    emit(state.copyWith(sessions: sessions));
  }

  void openSessionTab(FlashskySession session) {
    final existingIdx = _internalTabs.indexWhere((t) => t.info.id == session.sessionId);
    if (existingIdx != -1) {
      emit(state.copyWith(activeTabIndex: existingIdx, activeSessionId: session.sessionId));
      return;
    }
    final ts = TerminalSession();
    final info = ChatTabInfo(
      id: session.sessionId,
      title: session.display.isNotEmpty ? session.display : session.kind,
      subtitle: session.cwd,
      isRunning: false,
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
    final existingIdx = _internalTabs.indexWhere((t) => t.info.id == tabId);
    if (existingIdx != -1) {
      emit(state.copyWith(activeTabIndex: existingIdx, selectedMemberId: member.id));
      return;
    }
    final ts = TerminalSession();
    final info = ChatTabInfo(id: tabId, title: member.name, subtitle: '${team.name} / local', isRunning: false);
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
      emit(state.copyWith(tabs: [], activeTabIndex: 0, clearActiveSessionId: true));
    } else {
      final newIdx = state.activeTabIndex >= _internalTabs.length ? _internalTabs.length - 1 : state.activeTabIndex;
      emit(state.copyWith(tabs: _internalTabs.map((t) => t.info).toList(), activeTabIndex: newIdx));
    }
  }

  void selectTab(int index) {
    if (index < 0 || index >= _internalTabs.length) return;
    final tab = _internalTabs[index];
    final memberId = tab.info.id.startsWith('member-') ? tab.info.id.replaceFirst('member-', '') : state.selectedMemberId;
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
    final newId = lead.isEmpty ? team.members.first.id : lead.first.id;
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
    if (_legacySession != null && _legacyTeamId == team.id && _legacyMemberId == state.selectedMemberId) {
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
    final member = team.members.firstWhere((m) => m.id == memberId, orElse: () => team.members.first);
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
    final target = _internalTabs.isNotEmpty ? _internalTabs[state.activeTabIndex].session : _legacySession;
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
    _internalTabs[idx].info = _internalTabs[idx].info.copyWith(isRunning: isRunning);
    emit(state.copyWith(tabs: _internalTabs.map((t) => t.info).toList()));
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
```

---

### Task 5: Create ConfigCubit

**Files:**
- Create: `client/lib/cubits/config_cubit.dart`

- [ ] **Step 1: Write ConfigState and ConfigCubit**

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';

enum ConfigSection { team, members, layout, llm }

class ConfigState extends Equatable {
  const ConfigState({this.section = ConfigSection.team, this.selectedMemberId = ''});

  final ConfigSection section;
  final String selectedMemberId;

  String get title => switch (section) {
    ConfigSection.team => 'Team Configuration',
    ConfigSection.members => 'Member Configuration',
    ConfigSection.layout => 'Layout Configuration',
    ConfigSection.llm => 'LLM Configuration',
  };

  String get breadcrumb => switch (section) {
    ConfigSection.team => 'Config / Team',
    ConfigSection.members => 'Config / Members',
    ConfigSection.layout => 'Config / Layout',
    ConfigSection.llm => 'Config / LLM',
  };

  ConfigState copyWith({ConfigSection? section, String? selectedMemberId}) {
    return ConfigState(
      section: section ?? this.section,
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
    );
  }

  @override
  List<Object?> get props => [section, selectedMemberId];
}

class ConfigCubit extends Cubit<ConfigState> {
  ConfigCubit() : super(const ConfigState());

  void selectSection(ConfigSection section) {
    if (state.section == section) return;
    emit(state.copyWith(section: section));
  }

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      if (state.selectedMemberId.isEmpty) return;
      emit(state.copyWith(selectedMemberId: ''));
      return;
    }
    if (team.members.any((m) => m.id == state.selectedMemberId)) return;
    emit(state.copyWith(selectedMemberId: team.members.first.id));
  }

  void selectMember(String memberId) {
    if (state.selectedMemberId == memberId) return;
    emit(state.copyWith(selectedMemberId: memberId, section: ConfigSection.members));
  }
}
```

---

### Task 6: Create LlmConfigCubit

**Files:**
- Create: `client/lib/cubits/llm_config_cubit.dart`

- [ ] **Step 1: Write LlmConfigState and LlmConfigCubit**

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/llm_config.dart';
import '../repositories/llm_config_repository.dart';

class LlmConfigState extends Equatable {
  const LlmConfigState({
    this.config = const LlmConfig(),
    this.savedConfig = const LlmConfig(),
    this.isLoading = false,
    this.statusMessage = '',
    this.selectedProviderName,
    this.filePath = 'flashshkyai/llm/llm_config.json',
  });

  final LlmConfig config;
  final LlmConfig savedConfig;
  final bool isLoading;
  final String statusMessage;
  final String? selectedProviderName;
  final String filePath;

  String? get effectiveProviderName {
    if (selectedProviderName != null && config.providers.containsKey(selectedProviderName)) {
      return selectedProviderName;
    }
    return config.providers.keys.firstOrNull;
  }

  LlmConfigState copyWith({
    LlmConfig? config,
    LlmConfig? savedConfig,
    bool? isLoading,
    String? statusMessage,
    String? selectedProviderName,
    String? filePath,
  }) {
    return LlmConfigState(
      config: config ?? this.config,
      savedConfig: savedConfig ?? this.savedConfig,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      selectedProviderName: selectedProviderName ?? this.selectedProviderName,
      filePath: filePath ?? this.filePath,
    );
  }

  @override
  List<Object?> get props => [config, savedConfig, isLoading, statusMessage, selectedProviderName, filePath];
}

class LlmConfigCubit extends Cubit<LlmConfigState> {
  LlmConfigCubit({LlmConfigRepository? repository, LlmConfig initialConfig = const LlmConfig()})
      : _repository = repository,
        super(LlmConfigState(config: initialConfig, savedConfig: initialConfig));

  final LlmConfigRepository? _repository;

  void selectProvider(String name) {
    if (state.selectedProviderName == name) return;
    emit(state.copyWith(selectedProviderName: name));
  }

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final config = await _repository?.load() ?? const LlmConfig();
    emit(state.copyWith(config: config, savedConfig: config, isLoading: false, statusMessage: 'Loaded LLM config.'));
  }

  Future<void> save() async {
    await _repository?.save(state.config, previous: state.savedConfig);
    emit(state.copyWith(savedConfig: state.config, statusMessage: 'Saved LLM config.'));
  }

  void addProvider(LlmProviderConfig provider) {
    final config = state.config.copyWith(providers: {...state.config.providers, provider.name: provider});
    emit(state.copyWith(config: config, statusMessage: 'Added provider ${provider.name}.'));
  }

  void updateProvider(String name, LlmProviderConfig provider) {
    final updated = Map<String, LlmProviderConfig>.from(state.config.providers);
    updated[name] = provider;
    emit(state.copyWith(config: state.config.copyWith(providers: updated), statusMessage: 'Updated provider $name.'));
  }

  void deleteProvider(String name) {
    final updated = Map<String, LlmProviderConfig>.from(state.config.providers);
    updated.remove(name);
    final newSelected = state.selectedProviderName == name ? updated.keys.firstOrNull : state.selectedProviderName;
    emit(state.copyWith(
      config: state.config.copyWith(providers: updated),
      selectedProviderName: newSelected,
      statusMessage: 'Deleted provider $name.',
    ));
  }

  void addModel(LlmModelConfig model) {
    emit(state.copyWith(
      config: state.config.copyWith(models: {...state.config.models, model.id: model}),
      statusMessage: 'Added model ${model.name}.',
    ));
  }

  void updateModel(String id, LlmModelConfig model) {
    final updated = Map<String, LlmModelConfig>.from(state.config.models);
    updated[id] = model;
    emit(state.copyWith(config: state.config.copyWith(models: updated), statusMessage: 'Updated model ${model.name}.'));
  }

  void deleteModel(String id) {
    final updated = Map<String, LlmModelConfig>.from(state.config.models);
    updated.remove(id);
    emit(state.copyWith(config: state.config.copyWith(models: updated), statusMessage: 'Deleted model $id.'));
  }

  String revealApiKey(String providerName) {
    return state.savedConfig.providers[providerName]?.apiKey ?? '';
  }
}
```

---

### Task 7: Create LayoutCubit

**Files:**
- Create: `client/lib/cubits/layout_cubit.dart`

- [ ] **Step 1: Write LayoutState and LayoutCubit**

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/layout_preferences.dart';
import '../repositories/layout_repository.dart';

class LayoutState extends Equatable {
  const LayoutState({this.preferences = const LayoutPreferences(), this.isLoading = true});

  final LayoutPreferences preferences;
  final bool isLoading;

  LayoutState copyWith({LayoutPreferences? preferences, bool? isLoading}) {
    return LayoutState(preferences: preferences ?? this.preferences, isLoading: isLoading ?? this.isLoading);
  }

  @override
  List<Object?> get props => [preferences, isLoading];
}

class LayoutCubit extends Cubit<LayoutState> {
  LayoutCubit({LayoutRepository? repository}) : _repository = repository, super(const LayoutState());

  final LayoutRepository? _repository;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository?.load() ?? const LayoutPreferences();
    emit(state.copyWith(preferences: prefs, isLoading: false));
  }

  Future<void> _save(LayoutPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    await _repository?.save(preferences);
  }

  Future<void> setPreset(LayoutPreset preset) => _save(state.preferences.copyWith(preset: preset));
  Future<void> setToolPlacement(ToolPanelPlacement placement) => _save(state.preferences.copyWith(toolPlacement: placement));
  Future<void> setToolsArrangement(ToolsArrangement arrangement) => _save(state.preferences.copyWith(toolsArrangement: arrangement));

  Future<void> setRegionVisibility({
    required bool appRailVisible,
    required bool contextSidebarVisible,
    required bool membersVisible,
    required bool fileTreeVisible,
  }) {
    return _save(state.preferences.copyWith(
      appRailVisible: appRailVisible,
      contextSidebarVisible: contextSidebarVisible,
      membersVisible: membersVisible,
      fileTreeVisible: fileTreeVisible,
    ));
  }

  Future<void> setRightToolsWidth(double width) => _save(state.preferences.copyWith(rightToolsWidth: width));
  Future<void> setBottomToolsHeight(double height) => _save(state.preferences.copyWith(bottomToolsHeight: height));
  Future<void> setMembersSplit(double split) => _save(state.preferences.copyWith(membersSplit: split));
  Future<void> setThemeMode(String mode) => _save(state.preferences.copyWith(themeMode: mode));
  Future<void> setLocale(String locale) => _save(state.preferences.copyWith(locale: locale));
}
```

---

### Task 8: Create go_router configuration

**Files:**
- Create: `client/lib/router/app_router.dart`

- [ ] **Step 1: Write app_router.dart**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../pages/chat_workbench.dart';
import '../pages/config_workspace.dart';
import '../widgets/context_sidebar.dart';

final appRouter = GoRouter(
  initialLocation: '/chat',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final layoutCubit = context.read<LayoutCubit>();
        final preferences = layoutCubit.state.preferences;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (preferences.contextSidebarVisible)
                  const ContextSidebar(),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
      routes: [
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) => const NoTransitionPage(child: ChatWorkbench()),
          routes: [
            GoRoute(
              path: 'session/:sessionId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ChatWorkbench(sessionId: state.pathParameters['sessionId']),
              ),
            ),
          ],
        ),
        GoRoute(path: '/config', redirect: (context, state) => '/config/team'),
        GoRoute(
          path: '/config/team',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.team),
          ),
        ),
        GoRoute(
          path: '/config/members',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.members),
          ),
        ),
        GoRoute(
          path: '/config/layout',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.layout),
          ),
        ),
        GoRoute(
          path: '/config/llm',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.llm),
          ),
        ),
      ],
    ),
  ],
);
```

---

### Task 9: Rewrite main.dart

**Files:**
- Rewrite: `client/lib/main.dart`

- [ ] **Step 1: Rewrite main.dart with MultiBlocProvider + MaterialApp.router**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cubits/chat_cubit.dart';
import 'cubits/config_cubit.dart';
import 'cubits/layout_cubit.dart';
import 'cubits/llm_config_cubit.dart';
import 'cubits/team_cubit.dart';
import 'l10n/app_localizations.dart';
import 'repositories/layout_repository.dart';
import 'repositories/llm_config_repository.dart';
import 'repositories/team_repository.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => TeamCubit(repository: TeamRepository(preferences))..load()),
        BlocProvider(create: (_) => ChatCubit()),
        BlocProvider(create: (_) => ConfigCubit()),
        BlocProvider(create: (_) => LlmConfigCubit(repository: LlmConfigRepository(File('../flashshkyai/llm/llm_config.json')))..load()),
        BlocProvider(create: (_) => LayoutCubit(repository: LayoutRepository(preferences))..load()),
      ],
      child: const FlashskyAiClientApp(),
    ),
  );
}

class FlashskyAiClientApp extends StatelessWidget {
  const FlashskyAiClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    final layoutState = context.watch<LayoutCubit>().state;
    final prefs = layoutState.preferences;
    final savedLocale = prefs.locale;

    ThemeMode themeModeFromPrefs(String mode) => switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'FlashskyAI Teams',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeModeFromPrefs(prefs.themeMode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      locale: savedLocale.isNotEmpty ? Locale(savedLocale) : null,
      localeResolutionCallback: (locale, supportedLocales) {
        if (savedLocale.isNotEmpty) return Locale(savedLocale);
        for (final supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode) return supportedLocale;
        }
        return const Locale('en');
      },
      routerConfig: appRouter,
    );
  }
}
```

---

### Task 10: Update ContextSidebar to use Cubits

**Files:**
- Rewrite: `client/lib/widgets/context_sidebar.dart`

- [ ] **Step 1: Rewrite ContextSidebar without controller parameters**

Read current file, then rewrite to use `context.watch<>()` / `context.read<>()` instead of controller parameters.

Key changes:
- Remove `final TeamController controller` → use `context.watch<TeamCubit>()`
- Remove `final ChatController chatController` → use `context.read<ChatCubit>()`
- `controller.selectedTeam` → `teamCubit.state.selectedTeam`
- `chatController.sessions` → `chatCubit.state.sessions`
- `controller.selectTeam(id)` → `teamCubit.selectTeam(id)`
- `onSettingsTap` → `context.go('/config/team')`
- `onNewSession` remains a callback parameter

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';

class ContextSidebar extends StatelessWidget {
  const ContextSidebar({this.onNewSession, super.key});

  final VoidCallback? onNewSession;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final selected = teamCubit.state.selectedTeam;

    return Container(
      key: AppKeys.contextSidebar,
      width: 260,
      color: colors.sidebarBackground,
      padding: const EdgeInsets.all(13),
      child: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamSelector(teams: teamCubit.state.teams, selected: selected, onSelect: teamCubit.selectTeam),
                const SizedBox(height: 14),
                _SidebarSectionTitle(title: l10n.teamSessions, actionLabel: '+', onAction: onNewSession),
                Expanded(
                  child: ListView(
                    children: [
                      for (final session in chatCubit.state.sessions)
                        _SidebarTile(
                          key: AppKeys.sessionTile(session.sessionId),
                          title: session.display.isNotEmpty ? session.display : session.kind,
                          subtitle: session.cwd,
                          selected: chatCubit.state.activeSessionId == session.sessionId,
                          onTap: () => context.read<ChatCubit>().openSessionTab(session),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _SettingsTile(onTap: () => context.go('/config/team')),
              ],
            ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      key: AppKeys.sidebarSettingsButton,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.tune_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, color: textBase)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamSelector extends StatelessWidget {
  const _TeamSelector({required this.teams, required this.selected, required this.onSelect});
  final List<TeamConfig> teams; // will need import
  final dynamic selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.selectTeam,
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final team in teams)
          PopupMenuItem(value: team.id, child: Text(team.name)),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.teamSelectorBackground,
          border: Border.all(color: colors.teamSelectorBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(selected.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

// _SidebarSectionTitle, _SidebarTile unchanged - keep existing implementations
```

Note: The actual file rewrite will preserve the existing `_SidebarSectionTitle` and `_SidebarTile` widget implementations unchanged since they don't depend on controllers. Only the top-level `ContextSidebar`, `_TeamSelector`, and `_SettingsTile` need changes.

---

### Task 11: Update RightToolsPanel to use Cubits

**Files:**
- Modify: `client/lib/widgets/right_tools_panel.dart`

- [ ] **Step 1: Replace controller parameters with cubit reads**

Change the constructor from accepting `ChatController` + `TeamConfig` + `OpenMemberCallback` to using `context.read<>()`:

- `final TeamConfig team` → `context.watch<TeamCubit>().state.selectedTeam`
- `final ChatController chatController` → `context.watch<ChatCubit>()`
- `chatController.selectedMemberId` → `chatState.selectedMemberId`
- `chatController.selectMember(id)` → `context.read<ChatCubit>().selectMember(id)`
- `onOpenMember` → `context.read<TeamCubit>().launchMember(id)`

The `RightToolsPanel` constructor removes `team`, `chatController`, `onOpenMember` parameters. Keep `preferences` and `panelKey` optional parameters.

For the `launchMember` callback, after calling `teamCubit.launchMember(id)`, also call `chatCubit.addSystemMessage(teamCubit.state.statusMessage)`.

---

### Task 12: Update WorkspaceShell (no controller changes needed)

**Files:**
- Modify: `client/lib/pages/workspace_shell.dart` — minimal changes

The `WorkspaceShell` is a pure presentational widget. All it needs is `build()` context. No controller dependencies. The only change: remove unused imports that referenced controllers.

---

### Task 13: Update ChatWorkbench to use Cubits

**Files:**
- Rewrite: `client/lib/pages/chat_workbench.dart`

- [ ] **Step 1: Replace controller with cubit reads**

Change from StatefulWidget with `addListener` to StatelessWidget with `BlocBuilder`:

- `final TeamConfig team` → `context.watch<TeamCubit>().state.selectedTeam`
- `final ChatController chatController` → `context.read<ChatCubit>()` for actions, `context.watch<ChatCubit>()` for state
- `chatController.session` → `chatCubit.currentSession`
- `chatController.ensureSession(team)` → `chatCubit.ensureSession(team)`
- `chatController.connectSession(team)` → `chatCubit.connectSession(team)`
- `chatController.disconnectSession()` → `chatCubit.disconnectSession()`
- `chatController.restartSession(team)` → `chatCubit.restartSession(team)`
- `chatController.selectedMemberName(team)` → `chatCubit.selectedMemberName(team)`

The `_ChatWorkbenchState` holding `_session` via `addListener` + `setState` becomes a `BlocBuilder<ChatCubit, ChatState>` wrapping the terminal view.

Keep `_TerminalToolbar`, `_TerminalPlaceholder` as-is (they receive callbacks, no controller dependency).

---

### Task 14: Update ConfigWorkspace to use Cubits

**Files:**
- Rewrite: `client/lib/pages/config_workspace.dart`

- [ ] **Step 1: Replace all controller parameters**

Remove all constructor parameters (`configController`, `layoutController`, `llmConfigController`, `teamController`). Replace with `context.read<>`/`context.watch<>`:

- `configController.section` → `context.watch<ConfigCubit>().state.section`
- `configController.selectSection(s)` → `context.read<ConfigCubit>().selectSection(s)` + `context.go('/config/${s.name}')`
- `configController.selectedMemberId` → `configState.selectedMemberId`
- `layoutController.preferences` → `context.watch<LayoutCubit>().state.preferences`
- `layoutController.setXxx(v)` → `context.read<LayoutCubit>().setXxx(v)`
- `teamController.selectedTeam` → `context.watch<TeamCubit>().state.selectedTeam`
- All `teamController.*` calls → `context.read<TeamCubit>().*`
- `llmConfigController` → `context.read<LlmConfigCubit>()`

The `ConfigWorkspace` becomes a `StatelessWidget` reading from cubit state. The `Component sub-workspaces (`TeamConfigWorkspace`, `MemberConfigWorkspace`, `LayoutConfigWorkspace`) get their cubits from context instead of constructor params.

The `_ConfigNavPanel` tabs trigger both `configCubit.selectSection()` AND `context.go('/config/xxx')` to sync BLoC state with URL.

The `LlmConfigWorkspace` in config_workspace.dart delegates to the standalone `llm_config_workspace.dart` widget. That widget needs equivalent changes.

---

### Task 15: Update LlmConfigWorkspace to use Cubits

**Files:**
- Modify: `client/lib/pages/llm_config_workspace.dart`

- [ ] **Step 1: Replace controller parameter**

Change `final LlmConfigController controller` → read from `context.watch<LlmConfigCubit>()`:

- `controller.config` → `llmConfigState.config`
- `controller.addProvider(...)` → `context.read<LlmConfigCubit>().addProvider(...)`
- All other `controller.*` → `context.read<LlmConfigCubit>().*`

---

### Task 16: Delete old controller files

**Files:**
- Delete: `client/lib/controllers/chat_controller.dart`
- Delete: `client/lib/controllers/config_controller.dart`
- Delete: `client/lib/controllers/layout_controller.dart`
- Delete: `client/lib/controllers/llm_config_controller.dart`
- Delete: `client/lib/controllers/team_controller.dart`

- [ ] **Step 1: Remove controller files**

```bash
rm /home/hhoa/git/hhoa/flashskyai-ui/client/lib/controllers/chat_controller.dart
rm /home/hhoa/git/hhoa/flashskyai-ui/client/lib/controllers/config_controller.dart
rm /home/hhoa/git/hhoa/flashskyai-ui/client/lib/controllers/layout_controller.dart
rm /home/hhoa/git/hhoa/flashskyai-ui/client/lib/controllers/llm_config_controller.dart
rm /home/hhoa/git/hhoa/flashskyai-ui/client/lib/controllers/team_controller.dart
```

If the controllers directory is now empty, remove it:

```bash
rmdir /home/hhoa/git/hhoa/flashskyai-ui/client/lib/controllers 2>/dev/null || true
```

---

### Task 17: Rewrite test file for BLoC

**Files:**
- Rewrite: `client/test/widget_test.dart`

- [ ] **Step 1: Rewrite tests to use Cubits + MaterialApp.router**

Replace all `createController()` helpers with Cubit creation via `BlocProvider`. Wrap test app with `MultiBlocProvider` + `MaterialApp.router`.

Key changes to test helpers:
- Replace `createController()` with `createTeamCubit()`
- Replace `createLayoutController()` with `createLayoutCubit()`
- Replace `createLlmController()` with `createLlmConfigCubit()`
- Replace `createApp(controller, ...)` with a widget that wraps `MultiBlocProvider` + `MaterialApp.router`
- Replace `pumpDesktopApp(tester, controller, ...)` with a version that accepts cubits

All test assertions that checked `controller.selectedTeam?.name` etc. should check `teamCubit.state.selectedTeam?.name` instead.

The ShellRoute wraps everything in ContextSidebar + child, so tests that pump the full app should still find widgets by key.

---

### Task 18: Run flutter analyze and fix errors

**Files:**
- All modified files

- [ ] **Step 1: Run flutter analyze**

```bash
cd /home/hhoa/git/hhoa/flashskyai-ui/client
flutter analyze
```

Fix any issues. Expected: no errors.

- [ ] **Step 2: Run tests**

```bash
flutter test
```

Fix any failing tests. All 11 tests should pass.

---

### Task 19: Commit

**Files:**
- All changed files

- [ ] **Step 1: Git add and commit**

```bash
cd /home/hhoa/git/hhoa/flashskyai-ui
git add client/pubspec.yaml client/pubspec.lock
git add client/lib/cubits/
git add client/lib/router/
git add client/lib/main.dart
git add client/lib/widgets/context_sidebar.dart
git add client/lib/widgets/right_tools_panel.dart
git add client/lib/pages/
git rm client/lib/controllers/chat_controller.dart
git rm client/lib/controllers/config_controller.dart
git rm client/lib/controllers/layout_controller.dart
git rm client/lib/controllers/llm_config_controller.dart
git rm client/lib/controllers/team_controller.dart
git add client/test/widget_test.dart
git add docs/superpowers/specs/2026-05-10-bloc-go-router-migration-design.md
git add docs/superpowers/plans/2026-05-10-bloc-go-router-migration.md
git commit -m "refactor: migrate to BLoC Cubits and go_router ShellRoute

Replace 5 ChangeNotifier controllers with flutter_bloc Cubits and
setState-based navigation with go_router ShellRoute navigation.
State is now Equatable and immutable; widgets use BlocBuilder.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```
