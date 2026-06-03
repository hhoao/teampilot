import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/app_project.dart';
import '../models/connection_mode.dart';
import '../models/app_session.dart';
import '../models/session_member_binding.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../utils/logger.dart';
import '../utils/session_display_title.dart';
import 'chat/chat_connect_state_mixin.dart';
import 'chat/session_data_store.dart';
import 'chat/chat_session_shell_factory.dart';
import 'chat/chat_tab_store.dart';
import 'chat/tab_team_bus_coordinator.dart';
import 'member_presence_cubit.dart';
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';
import 'chat/model/chat_tab_info.dart';

export 'chat/model/chat_state.dart';
export 'chat/model/chat_tab_info.dart';

class ChatCubit extends Cubit<ChatState>
    with ChatConnectStateMixin
    implements MemberConnector {
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
  late final TabTeamBusCoordinator _busCoordinator = TabTeamBusCoordinator(
    tabStore: _tabStore,
    shellFactory: _shellFactory,
    connector: this,
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

  static const _uuid = Uuid();

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
  }) async {
    final existingIdx = _tabStore.indexOfSession(session.sessionId);
    if (existingIdx != -1) {
      final existing = _tabStore.tabs[existingIdx];
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
    final ts = _shellFactory.newSession(
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
    emit(
      state.copyWith(
        tabs: [...state.tabs, info],
        activeTabIndex: _tabStore.length - 1,
        activeSessionId: session.sessionId,
        selectedMemberId: internalTab.selectedMemberId,
      ),
    );
    if (team != null) {
      _activeTeam = team;
      _pushPresenceTarget();
      if (team.teamMode == TeamMode.mixed) {
        await _busCoordinator.installBusForTab(internalTab, team, session);
      }
    }
    // mixed：打开/恢复 tab 只建 bus + MCP，不 spawn PTY（等用户 connect 或 mailbox 物化）。
    final connectNow = connectImmediately && team?.teamMode != TeamMode.mixed;
    if (connectNow) {
      beginSessionConnect(info.id);
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
            emitLaunchWarnings(plan.warnings);
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
                  failSessionConnect(info.id, message),
              onProcessExited: () => updateTabRunning(info.id),
              onProcessStarted: () {
                clearLaunchError(info.id);
                finishSessionConnect(info.id);
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
          updateTabRunning(info.id);
        } on Object catch (e, st) {
          appLogger.e(
            '[session] prepareLaunch/connect failed for ${info.id}: $e',
            error: e,
            stackTrace: st,
          );
          final message = 'Failed to resume session: $e';
          ts.write('\r\n[$message]\r\n');
          failSessionConnect(info.id, message);
        }
      });
    } else {
      updateTabRunning(info.id);
    }
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
      selectMember(keepSelectedMemberId);
    }
  }

  Future<void> _materializeDefaultWorkspaceSession(
    TeamConfig team,
    SessionRepository repo, {
    required bool connectImmediately,
    required TeamMemberConfig memberForInitialShell,
  }) async {
    if (!_tabStore.isEmpty) return;
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
    if (_tabStore.isEmpty && r != null) {
      beginSessionConnect('pending');
      try {
        await _materializeDefaultWorkspaceSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: member,
        );
        if (isClosed) return;
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
        failSessionConnect('pending', 'Failed to create session: $e');
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
    if (isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessions = state.sessions.map((s) {
      if (s.sessionId != sessionId) return s;
      return s.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }).toList();
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        projects: state.projects,
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

  AppSession? _sessionForMemberConnect(ChatTab tab, TeamConfig team) {
    final cached = _tabStore.sessionForTab(tab, state.sessions);
    if (cached != null) return cached;
    if (!tab.info.id.startsWith('local-')) return null;
    final launch = _tabStore.workingDirectoryAndAddDirsForTab(tab, state.sessions);
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
      failSessionConnect(
        tab.info.id,
        'Session is missing CLI team identity (cliTeamName). '
        'Create a new team session.',
      );
      return;
    }
    if (!session.sessionId.startsWith('local-') && session.members.isEmpty) {
      failSessionConnect(
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
    emitLaunchWarnings(plan.warnings);
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
      busUserInputRouting: _busCoordinator.busUserInputRouting(tab, team, member),
      onFirstUserLineSubmitted: _autoRenameOnFirstPrompt(
        activeSession.sessionId,
      ),
      onProcessFailed: (message) => failSessionConnect(tab.info.id, message),
      onProcessExited: () => updateTabRunning(tab.info.id),
      onProcessStarted: () {
        tab.teamBus?.markMemberRunning(member.id);
        clearLaunchError(tab.info.id);
        finishSessionConnect(tab.info.id);
        _busCoordinator.markMemberReady(tab.info.id, member.id);
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

  void _scheduleMemberConnect(
    TeamConfig team,
    TeamMemberConfig member,
    ChatTab tab,
  ) {
    tab.selectedMemberId = member.id;
    final shell = tab.memberShells.putIfAbsent(
      member.id,
      () => _shellFactory.newSession(member.cliWithin(team)),
    );
    emit(
      state.copyWith(
        tabs: _tabStore.toInfos(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
      ),
    );
    if (shell.isRunning || shell.isConnecting) {
      updateTabRunning(tab.info.id);
      return;
    }
    if (tab.membersPendingConnect.contains(member.id)) {
      return;
    }
    tab.membersPendingConnect.add(member.id);
    _tabStore.workingDirectoryAndAddDirsForTab(tab, state.sessions);
    beginSessionConnect(tab.info.id);
    _postFrameScheduler(() async {
      try {
        if (shell.isRunning) {
          finishSessionConnect(tab.info.id);
          return;
        }
        final session = _sessionForMemberConnect(tab, team);
        if (session == null) {
          failSessionConnect(
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
        updateTabRunning(tab.info.id);
      } on Object catch (e, st) {
        appLogger.e(
          '[session] prepareLaunch/connect failed for member ${member.name}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to start session: $e';
        shell.write('\r\n[$message]\r\n');
        failSessionConnect(tab.info.id, message);
      } finally {
        tab.membersPendingConnect.remove(member.id);
      }
    });
  }

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
  }) async {
    final r = repo ?? _sessionRepository;
    final validMembers = team.members.where((m) => m.isValid).toList();
    if (validMembers.isEmpty) return;
    if (_tabStore.isEmpty && r != null) {
      try {
        await _materializeDefaultWorkspaceSession(
          team,
          r,
          connectImmediately: true,
          memberForInitialShell: validMembers.first,
        );
        if (isClosed) return;
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
      tab.selectedMemberId = _tabStore.defaultMemberId(team);
    }
    if (tab.selectedMemberId.isNotEmpty) {
      final memberId = tab.selectedMemberId;
      return tab.memberShells.putIfAbsent(
        memberId,
        () => _shellFactory.newSession(_shellFactory.cliForMember(team, memberId)),
      );
    }
    return tab.resumeSession ??= _shellFactory.newSession(team.cli);
  }

  Future<void> connectSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
    if (state.isActiveSessionConnecting) return;

    final r = repo ?? _sessionRepository;
    if (_tabStore.isEmpty && r == null) {
      _appendLocalTab(team, emitChange: true);
    }

    if (_autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = state.selectedMemberId.isNotEmpty
          ? state.selectedMemberId
          : _tabStore.defaultMemberId(team);
      if (keepId.isEmpty) {
        final session = ensureSession(team);
        const message =
            'No member selected. Choose a team member and try again.';
        session?.write('\r\n[$message]\r\n');
        failSessionConnect(_activeTab?.info.id ?? 'pending', message);
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
      memberId = _tabStore.defaultMemberId(team);
    }
    if (memberId.isEmpty || team.members.isEmpty) {
      final session = ensureSession(team);
      const message = 'No member selected. Choose a team member and try again.';
      session?.write('\r\n[$message]\r\n');
      failSessionConnect(_activeTab?.info.id ?? 'pending', message);
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
    clearLaunchError(tab.info.id);
    updateTabRunning(tab.info.id);
  }

  Future<void> restartSession(
    TeamConfig team, {
    SessionRepository? repo,
  }) async {
    final r = repo ?? _sessionRepository;
    final activeId = _activeTab?.info.id ?? state.activeSessionId ?? 'pending';
    beginSessionConnect(activeId);
    if (_autoLaunchAllMembersOnConnect?.call() == true) {
      final keepId = state.selectedMemberId.isNotEmpty
          ? state.selectedMemberId
          : _tabStore.defaultMemberId(team);
      final tab = _activeTab;
      if (tab != null) {
        tab.membersPendingConnect.clear();
        for (final shell in tab.memberShells.values) {
          shell.disconnect();
        }
        updateTabRunning(tab.info.id);
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

  ChatTab _appendLocalTab(TeamConfig team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
    if (emitChange) {
      emit(
        state.copyWith(
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

  @visibleForTesting
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
