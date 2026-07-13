import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/workspace.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_launch_context.dart';
import '../models/app_session.dart';
import '../services/team/member_presence_service.dart';
import '../models/workspace_icon_picker_result.dart';
import '../models/workspace_icon_ref.dart';
import '../models/team_config.dart';
import '../models/runtime_target.dart';
import '../../repositories/launch_profile_repository.dart';
import '../models/automation_tab_scope.dart';
import '../repositories/automation_repository.dart';
import '../repositories/session_repository.dart';
import '../services/workspace/workspace_icon_service.dart';
import '../services/workspace/workspace_icon_storage.dart';
import '../services/storage/app_storage.dart';
import '../services/session/session_lifecycle_service.dart';
import '../services/storage/targets_repository.dart';
import '../services/team_bus/artifacts/artifact_registry.dart';
import '../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../services/launch/launch_factory.dart';
import '../services/launch/session_connect_orchestrator.dart';
import '../services/launch/workspace_provision_coordinator.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_for_launch.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../utils/workspace_sessions.dart';
import '../../widgets/workspace_icon_picker_dialog.dart';
import 'chat/chat_connect_state_mixin.dart';
import 'chat/session_data_store.dart';
import 'chat/chat_session_shell_factory.dart';
import 'chat/chat_tab_store.dart';
import 'chat/session_launch_host.dart';
import 'chat/session_launch_service.dart';
import 'chat/tab_member_materializer.dart';
import 'chat/tab_session_runtime_coordinator.dart';
import 'chat/tab_team_bus_coordinator.dart';
import 'layout_cubit.dart';
import 'member_presence_cubit.dart';
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';
import 'chat/model/session_connect_request.dart';
import 'chat/model/session_create_request.dart';
import 'chat/model/session_open_request.dart';
import 'chat/model/session_open_status.dart';
import 'chat/model/session_workbench_view.dart';
import 'chat/session_continue_overrides_controller.dart';
import '../models/cli_preset.dart';

export 'chat/model/chat_state.dart';
export 'chat/model/chat_tab_info.dart';
export 'chat/model/session_create_request.dart';
export 'chat/model/session_open_request.dart';
export 'chat/model/session_open_status.dart';
export 'chat/model/session_workbench_view.dart';

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
    SshProfileByIdResolver? sshProfileById,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    RuntimeTarget Function()? defaultTargetResolver,
    int Function()? terminalScrollbackLinesResolver,
    RemoteBusBindingResolver? remoteBusResolver,
    SessionConnectOrchestrator? sessionConnect,
    TeammateBusMcpGateway? teammateBusMcpGateway,
    Future<TeamProfile?> Function(String teamId)? teamById,
    required AutomationRepository automationRepository,
    LayoutCubit? layoutCubit,
  }) : _remoteBusResolver = remoteBusResolver,
       _sessionConnect = sessionConnect,
       _teamById = teamById,
       _teammateBusMcpGateway =
           teammateBusMcpGateway ?? TeammateBusMcpGateway(),
       _automationRepository = automationRepository,
       _layoutCubit = layoutCubit,
       _shellFactory = ChatSessionShellFactory(
         executableResolver: executableResolver,
         cliExecutableResolver: cliExecutableResolver,
         terminalSessionFactory: terminalSessionFactory,
         transportFactory: transportFactory,
         sshProfileResolver: sshProfileResolver,
         sshProfileById: sshProfileById,
         sshDefaultWorkingDirectoryResolver: sshDefaultWorkingDirectoryResolver,
         sshUseLoginShellResolver: sshUseLoginShellResolver,
         defaultTargetResolver: defaultTargetResolver,
         terminalScrollbackLinesResolver: terminalScrollbackLinesResolver,
       ),
       _postFrameScheduler = postFrameScheduler ?? _defaultPostFrameScheduler,
       _autoLaunchAllMembersOnConnect = autoLaunchAllMembersOnConnect,
       _lifecycle = lifecycleService ?? SessionLifecycleService(),
       _sessionRepository = sessionRepository,
       super(const ChatState());

  /// Fired when History should drop cache / reload (disconnect or switch back).
  void Function(String sessionId)? onSessionHistoryStale;

  final RemoteBusBindingResolver? _remoteBusResolver;
  final SessionConnectOrchestrator? _sessionConnect;
  final Future<TeamProfile?> Function(String teamId)? _teamById;
  final TeammateBusMcpGateway _teammateBusMcpGateway;
  final AutomationRepository _automationRepository;
  final LayoutCubit? _layoutCubit;
  VoidCallback? _onAutomationsChanged;
  SessionConnectOrchestrator? _defaultSessionConnect;

  void bindAutomationsChangeNotifier(VoidCallback listener) {
    _onAutomationsChanged = listener;
  }

  void _notifyAutomationsChanged() => _onAutomationsChanged?.call();
  final ChatTabStore _tabStore = ChatTabStore();
  final SessionDataStore _dataStore = SessionDataStore();
  static const _continueOverridesController =
      SessionContinueOverridesController();
  final Map<String, Future<void>> _sessionHydrationByWorkspace = {};
  late final SessionLaunchService _launchService = SessionLaunchService(this);
  late final TabSessionRuntimeCoordinator _sessionRuntime =
      TabSessionRuntimeCoordinator(
        tabStore: _tabStore,
        shellFactory: _shellFactory,
        activeTeam: () => _activeTeam,
        isClosed: () => isClosed,
        globalPresets: () => _lifecycle.globalPresets,
        activeSessionId: () => state.activeSessionId,
        presence: () => _presenceCubit?.state.presence ?? const {},
        onAfterIdleWatchTick: () => unawaited(_onIdleWatchTick()),
        onAfterTurnLatched: _recomputeWorkingSessions,
      );
  late final TabMemberMaterializer _memberMaterializer = TabMemberMaterializer(
    runtime: _sessionRuntime,
    tabStore: _tabStore,
    connector: _launchService,
    activeTeam: () => _activeTeam,
    isClosed: () => isClosed,
    isMixedBusRegistered: _teammateBusMcpGateway.isSessionRegistered,
    isMemberConnectOwnedElsewhere: _launchService.isMemberConnectOwnedElsewhere,
    isDirectPtyLifecycleReady: _launchService.isMemberDirectPtyLifecycleReady,
  );
  late final TabTeamBusCoordinator _teamBus = TabTeamBusCoordinator(
    gateway: _teammateBusMcpGateway,
    tabStore: _tabStore,
    materializer: _memberMaterializer,
    globalPresets: () => _lifecycle.globalPresets,
    onAfterTurnLatched: _recomputeWorkingSessions,
    artifactServiceFactory: _buildArtifactService,
  );

  /// P3d: a per-session cross-machine artifact transfer service. The registry is
  /// session-scoped (one per bus install), so published handles live only as
  /// long as the session. Resolvers reuse the launch path's member→target and
  /// work-context seams so publisher/fetcher bytes move on the right machines.
  ArtifactTransferService _buildArtifactService(AppSession session) {
    return ArtifactTransferService(
      registry: ArtifactRegistry(),
      resolveFs: (targetId) async =>
          (await _lifecycle.resolveWorkContextForTargetId(targetId)).filesystem,
      targetForMember: (memberId) {
        final workspace = state.workspaces
            .where((w) => w.workspaceId == session.workspaceId)
            .firstOrNull;
        return _lifecycle
            .launchWorkTarget(
              WorkspaceLaunchContext(
                session: session,
                workspace:
                    workspace ??
                    Workspace(
                      workspaceId: session.workspaceId,
                      folders: session.folders,
                      createdAt: 0,
                    ),
              ),
              memberId: memberId,
            )
            .id;
      },
      inboxDirFor: (memberId) {
        final workspace = state.workspaces
            .where((w) => w.workspaceId == session.workspaceId)
            .firstOrNull;
        final ctx = WorkspaceLaunchContext(
          session: session,
          workspace:
              workspace ??
              Workspace(
                workspaceId: session.workspaceId,
                folders: session.folders,
                createdAt: 0,
              ),
        );
        final cwd = _lifecycle.memberWorkDirs(ctx, memberId).workingDirectory;
        return cwd.isEmpty ? '.teampilot-inbox' : '$cwd/.teampilot-inbox';
      },
    );
  }

  MemberPresenceCubit? _presenceCubit;
  TeamProfile? _activeTeam;
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
  void applyState(ChatState next) {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (next.composeActive) {
      _tabStore.setComposeActive(workspaceId, true);
    } else {
      _tabStore.setComposeActive(workspaceId, false);
    }
    emit(next);
  }

  @override
  void emitSnapshot(ChatDataSnapshot snapshot) => _emitSnapshot(snapshot);

  @override
  void appendSessionSnapshot(AppSession session) {
    _emitSnapshot(
      _dataStore.appendSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
  }

  @override
  void replaceSessionSnapshot(AppSession session) {
    _emitSnapshot(
      _dataStore.replaceSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
  }

  @override
  void removeSessionSnapshot(String sessionId) {
    _emitSnapshot(
      _dataStore.removeSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        sessionId,
      ),
    );
  }

  @override
  void closeSessionTab(String sessionId) {
    final idx = _tabStore.activeIndexOfSession(sessionId);
    if (idx != -1) closeTab(idx);
  }

  @override
  void pushPresenceTarget() => _pushPresenceTarget();

  @override
  ChatTab? get activeTab => _activeTab;

  @override
  set activeTeam(TeamProfile? team) => _activeTeam = team;

  @override
  ChatSessionShellFactory get shellFactory => _shellFactory;

  @override
  TabSessionRuntimeCoordinator get sessionRuntime => _sessionRuntime;

  @override
  TabTeamBusCoordinator get teamBus => _teamBus;

  @override
  TabMemberMaterializer get memberMaterializer => _memberMaterializer;

  @override
  TeammateBusMcpGateway get teammateBusMcpGateway => _teammateBusMcpGateway;

  @override
  SessionLifecycleService get lifecycle => _lifecycle;

  @override
  SessionDataStore get dataStore => _dataStore;

  /// True once [ensureSessionsForWorkspace] has loaded this workspace's
  /// sessions from disk. The UI uses this to tell "still loading" apart from
  /// "genuinely empty" so a cold tab switch shows a skeleton, not a flash of
  /// the empty-conversations placeholder.
  bool sessionsLoadedForWorkspace(String workspaceId) =>
      _dataStore.sessionsLoadedForWorkspace(workspaceId);

  @override
  SessionRepository? get sessionRepository => _sessionRepository;

  @override
  PostFrameScheduler get postFrameScheduler => _postFrameScheduler;

  @override
  bool Function()? get autoLaunchAllMembersOnConnect =>
      _autoLaunchAllMembersOnConnect;

  @override
  RemoteBusBindingResolver? get remoteBusResolver => _remoteBusResolver;

  @override
  SessionConnectOrchestrator get sessionConnect =>
      _sessionConnect ??
      (_defaultSessionConnect ??= buildDefaultSessionConnectOrchestrator(
        lifecycle: _lifecycle,
        localCliPath: (cli) async => _shellFactory.executableFor(cli),
        sshClientFactory: _shellFactory.sshClientFactory,
        profileById: _shellFactory.profileById,
      ));

  @override
  WorkspaceProvisionCoordinator get workspaceProvision =>
      sessionConnect.workspaceProvision;

  @override
  CliToolRegistry get cliRegistry => _lifecycle.cliToolRegistry;

  @override
  Future<TeamProfile?> teamProfileById(String teamId) async {
    final id = teamId.trim();
    if (id.isEmpty) return null;
    if (_activeTeam?.id == id) return _activeTeam;
    return _teamById?.call(id);
  }

  @override
  Future<bool> isRootSandboxEnvOptIn(String targetId) =>
      TargetsRepository().isRootSandboxEnvOptIn(targetId);

  @override
  TerminalTheme? resolveTerminalThemeForLaunch() {
    final layout = _layoutCubit;
    if (layout == null) return null;
    return resolveTerminalThemeFromLayout(
      preferences: layout.state.preferences,
      platformBrightness: SchedulerBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  /// Drops cached Phase A provision for [workspace] (e.g. after folder/target edits).
  void invalidateWorkspaceProvision(Workspace workspace) {
    sessionConnect.invalidateWorkspaceProvision(workspace);
  }

  /// Wired by app_shell after both cubits are constructed.
  void bindPresenceCubit(MemberPresenceCubit cubit) => _presenceCubit = cubit;

  /// Pushed after each idle-watch tick once member presence has been refreshed.
  /// Session spinners follow the members panel ([MemberAvailability.working]).
  void _updateWorkingSessions(Set<String> ids) {
    if (isClosed || setEquals(ids, state.workingSessionIds)) return;
    emit(state.copyWith(workingSessionIds: ids));
  }

  Future<void> _onIdleWatchTick() async {
    await _presenceCubit?.tickFromIdleWatch();
    if (isClosed) return;
    _recomputeWorkingSessions();
  }

  void _recomputeWorkingSessions() {
    _updateWorkingSessions(_sessionRuntime.recomputeWorkingSessions());
  }

  @visibleForTesting
  void updateWorkingSessionsForTest(Set<String> ids) =>
      _updateWorkingSessions(ids);

  @visibleForTesting
  void debugTickIdleWatch() => _sessionRuntime.debugTickIdleWatch();

  @visibleForTesting
  void debugRecomputeWorkingSessions() => _recomputeWorkingSessions();

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
        cliTeamName: tab.effectiveCliTeamName,
        memberToolConfigDir: tab.memberToolConfigDir,
        memberShells: tab.memberShells,
        session: _presenceSessionContext(tab),
      ),
    );
  }

  PresenceSessionContext? _presenceSessionContext(ChatTab tab) {
    final team = _activeTeam;
    if (team == null) return null;
    return PresenceSessionContext(
      team: team,
      appSession: tab.persistedSession,
      teamBus: tab.teamBus,
      globalPresets: _lifecycle.globalPresets,
    );
  }

  /// Switches the active workspace bucket and republishes its tabs into state.
  /// Called by the workspace page whenever the active workspace changes.
  void setActiveWorkspace(String workspaceId) {
    final restoredIndex = _tabStore.setActiveWorkspace(
      workspaceId,
      currentActiveIndex: state.activeTabIndex,
    );
    _publishActiveWorkspaceTabs(restoredIndex);
  }

  /// Switches the chat tab bucket and session visibility scope in one [emit].
  /// Use on workspace tab activation so [setTeamSessionScope] does not fire a
  /// second rebuild on the next frame.
  void activateWorkspaceTab({
    required String workspaceTabKey,
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    final restoredIndex = _tabStore.setActiveWorkspace(
      workspaceTabKey,
      currentActiveIndex: state.activeTabIndex,
    );
    final scopeChanged = _dataStore.setScope(
      scopeSessionsToSelectedTeam: scopeSessionsToSelectedTeam,
      selectedTeamId: selectedTeamId,
    );
    final snapshot = scopeChanged
        ? _dataStore.deriveSnapshot(
            workspaces: state.workspaces,
            sessions: state.sessions,
          )
        : null;
    _publishActiveWorkspaceTabs(restoredIndex, snapshot: snapshot);
  }

  /// Re-emits the active bucket's tab infos without changing the workspace, after
  /// callers mutate the active bucket directly via [tabStore].
  @override
  void refreshActiveWorkspaceTabs() =>
      _publishActiveWorkspaceTabs(state.activeTabIndex);

  void _publishActiveWorkspaceTabs(
    int desiredIndex, {
    ChatDataSnapshot? snapshot,
  }) {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setComposeActive(workspaceId, true);
      final empty = snapshot;
      emit(
        state.copyWith(
          tabs: const [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          clearSessionConnectingId: true,
          selectedMemberId: '',
          composeActive: true,
          workspaces: empty?.workspaces,
          sessions: empty?.sessions,
          visibleWorkspaces: empty?.visibleWorkspaces,
          visibleSessions: empty?.visibleSessions,
        ),
      );
      _pushPresenceTarget();
      return;
    }
    final index = desiredIndex.clamp(0, _tabStore.activeTabCount - 1);
    final composeActive = _tabStore.isComposeActive(workspaceId);
    if (composeActive) {
      emit(
        state.copyWith(
          tabs: _tabStore.activeTabInfos(),
          activeTabIndex: index,
          clearActiveSessionId: true,
          selectedMemberId: '',
          composeActive: true,
          workspaces: snapshot?.workspaces,
          sessions: snapshot?.sessions,
          visibleWorkspaces: snapshot?.visibleWorkspaces,
          visibleSessions: snapshot?.visibleSessions,
        ),
      );
      _pushPresenceTarget();
      return;
    }
    final tab = _tabStore.activeTabs[index];
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        composeActive: false,
        workspaces: snapshot?.workspaces,
        sessions: snapshot?.sessions,
        visibleWorkspaces: snapshot?.visibleWorkspaces,
        visibleSessions: snapshot?.visibleSessions,
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
        workspaces: state.workspaces,
        sessions: state.sessions,
      ),
    );
  }

  void _emitSnapshot(ChatDataSnapshot snap, {ChatState? base}) {
    final s = base ?? state;
    emit(
      s.copyWith(
        workspaces: snap.workspaces,
        sessions: snap.sessions,
        visibleWorkspaces: snap.visibleWorkspaces,
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

  /// Session workspace path for the active tab (used to resolve relative file links).
  String get activeTabWorkingDirectory {
    final tab = _activeTab;
    if (tab == null) return AppStorage.cwd;
    return _tabStore
        .workingDirectoryAndAddDirsForTab(
          tab,
          state.sessions,
          workspaces: state.workspaces,
        )
        .$1;
  }

  /// Last launch failure for the active tab, or [ChatState.sessionLaunchError].
  String? get activeLaunchError {
    if (!_tabStore.activeTabsIsEmpty) {
      final index = state.activeTabIndex.clamp(0, _tabStore.activeTabCount - 1);
      final error = _tabStore.activeTabs[index].info.launchError;
      if (error != null && error.isNotEmpty) return error;
    }
    final pending = state.sessionLaunchError;
    if (pending != null && pending.isNotEmpty) return pending;
    return null;
  }

  @override
  Future<void> loadWorkspaceData(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  /// Home index: workspace manifests only; sessions hydrate separately.
  Future<void> loadWorkspaceIndex(SessionRepository repo) async {
    _emitSnapshot(await _dataStore.loadWorkspaceIndex(repo));
  }

  Future<void> hydrateAllSessions(SessionRepository repo) async {
    final sessions = await _dataStore.loadSessions(repo);
    _dataStore.markWorkspacesSessionsHydrated(
      state.workspaces.map((workspace) => workspace.workspaceId),
    );
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  /// Loads [workspaceId] sessions from disk when the UI needs them.
  Future<void> ensureSessionsForWorkspace(String workspaceId) async {
    final repo = _sessionRepository;
    final id = workspaceId.trim();
    if (repo == null || id.isEmpty) return;
    if (_dataStore.sessionsLoadedForWorkspace(id)) return;

    final inflight = _sessionHydrationByWorkspace[id];
    if (inflight != null) {
      await inflight;
      return;
    }

    final load = _hydrateWorkspaceSessions(repo, id);
    _sessionHydrationByWorkspace[id] = load;
    try {
      await load;
    } finally {
      _sessionHydrationByWorkspace.remove(id);
    }
  }

  Future<List<AppSession>> sessionsForWorkspaceReady(String workspaceId) async {
    await ensureSessionsForWorkspace(workspaceId);
    return sessionsForWorkspace(
      state.workspaces.where((w) => w.workspaceId == workspaceId).firstOrNull ??
          Workspace(workspaceId: workspaceId, folders: const [], createdAt: 0),
      state.sessions,
    );
  }

  Future<void> _hydrateWorkspaceSessions(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final sessions = await _dataStore.loadSessionsForWorkspace(
      repo,
      workspaceId,
    );
    if (isClosed) return;
    _emitSnapshot(
      _dataStore.mergeWorkspaceSessions(
        current: ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        workspaceId: workspaceId,
        workspaceSessions: sessions,
      ),
    );
  }

  /// Updates persisted-index mirrors in state and recomputes team-scoped sidebar lists.
  void ingestWorkspaceSessionSnapshot({
    required List<Workspace> workspaces,
    required List<AppSession> sessions,
  }) {
    _emitSnapshot(
      _dataStore.deriveSnapshot(workspaces: workspaces, sessions: sessions),
    );
  }

  Future<AppSession> createSession(
    String workspaceId,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    CliTool? cli,
    String? workingDirectory,
    String? fixedSessionId,
  }) async {
    final session = await _dataStore.createSession(
      workspaceId,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      cli: cli,
      workingDirectory: workingDirectory,
      fixedSessionId: fixedSessionId,
    );
    _emitSnapshot(
      _dataStore.appendSession(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        session,
      ),
    );
    return session;
  }

  Future<SessionOpenStatus> requestCreateAndOpenSession(
    SessionCreateRequest request,
  ) => _launchService.requestCreateAndOpenSession(request);

  /// Creates (or reuses) the workspace for [primaryPath], seeds a first session,
  /// reloads workspace data, and returns the workspace id so callers can navigate
  /// straight to the new workspace.
  Future<String> createWorkspaceWithFirstSession(
    List<WorkspaceFolder> folders,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    String display = '',
    bool allowDuplicate = false,
    LaunchProfileRepository? identityRepository,
  }) async {
    final result = await _dataStore.createWorkspaceWithFirstSession(
      folders,
      repo,
      sessionTeamId: sessionTeamId,
      rosterMembers: rosterMembers,
      display: display,
      allowDuplicate: allowDuplicate,
      identityRepository: identityRepository,
    );
    _emitSnapshot(result.snapshot);
    return result.workspaceId;
  }

  Future<void> addWorkspaceDirectory(
    SessionRepository repo,
    Workspace workspace,
    WorkspaceFolder folder,
  ) async {
    final snap = await _dataStore.addWorkspaceDirectory(
      repo,
      workspace,
      folder,
    );
    if (snap != null) _emitSnapshot(snap);
  }

  Future<void> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
  }) async {
    _emitSnapshot(
      await _dataStore.updateWorkspaceMetadata(
        repo,
        workspaceId,
        display: display,
        defaultProfileId: defaultProfileId,
      ),
    );
  }

  Future<void> applyWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    _emitSnapshot(await _dataStore.applyWorkspaceIcon(repo, workspaceId, icon));
  }

  Future<void> importCustomWorkspaceIcon(
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    _emitSnapshot(
      await _dataStore.importCustomWorkspaceIcon(
        repo,
        workspaceId,
        localSourcePath,
      ),
    );
  }

  /// Opens the icon picker and applies the user's choice.
  ///
  /// Returns an error message when custom import fails; otherwise `null`.
  Future<String?> editWorkspaceIcon(
    BuildContext context,
    SessionRepository repo,
    Workspace workspace,
  ) async {
    final result = await showWorkspaceIconPickerDialog(
      context,
      workspace: workspace,
    );
    return switch (result) {
      WorkspaceIconPickerCancelled() => null,
      WorkspaceIconPickerUploadRequested() => _pickAndImportCustomIcon(
        repo,
        workspace.workspaceId,
      ),
      WorkspaceIconPickerCommitted(:final icon) => _applyCommittedIcon(
        repo,
        workspace.workspaceId,
        icon,
      ),
    };
  }

  Future<String?> _pickAndImportCustomIcon(
    SessionRepository repo,
    String workspaceId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: WorkspaceIconStorage.allowedExtensions
          .where((ext) => ext != 'jpeg')
          .toList(growable: false),
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;

    try {
      await importCustomWorkspaceIcon(repo, workspaceId, path);
      return null;
    } on WorkspaceIconImportException catch (error) {
      return error.message;
    }
  }

  Future<String?> _applyCommittedIcon(
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    await applyWorkspaceIcon(repo, workspaceId, icon);
    return null;
  }

  Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) =>
      _launchService.requestOpenSession(request);

  Future<void> scheduleTeamConfigValidation(TeamProfile team) =>
      _launchService.scheduleTeamConfigValidation(team);

  Future<void> openMemberTab(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
    bool scheduleTeamConfigValidation = true,
  }) => _launchService.openMemberTab(
    team,
    member,
    repo: repo,
    workspaceCwd: workspaceCwd,
    scheduleTeamConfigValidation: scheduleTeamConfigValidation,
  );

  Future<void> reconnectSshProfile(String profileId) =>
      _launchService.reconnectSshProfile(profileId);

  Future<void> _tearDownTab(ChatTab tab) async {
    for (final session in tab.sessions) {
      session.dispose();
    }
    await _teamBus.disposeSessionBus(tab.info.id);
    await tab.disposeBus();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final tab = _tabStore.removeAt(index);
    unawaited(_tearDownTab(tab));
    _sessionRuntime.maybeStopIdleWatch();
    if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setComposeActive(_tabStore.activeWorkspaceId, true);
      emit(
        state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          composeActive: true,
        ),
      );
    } else {
      final newIdx = state.activeTabIndex >= _tabStore.activeTabCount
          ? _tabStore.activeTabCount - 1
          : state.activeTabIndex;
      final nextTab = _tabStore.activeTabs[newIdx];
      emit(
        state.copyWith(
          tabs: _tabStore.activeTabInfos(),
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
          composeActive: false,
        ),
      );
    }
    _pushPresenceTarget();
  }

  /// Number of open session-backed tabs in [workspaceId]'s bucket (excludes
  /// `local-` scratch tabs, which have no persisted workspace session).
  int openTabCountForWorkspace(String workspaceId) =>
      _tabStore.sessionBackedCountForWorkspace(workspaceId);

  /// Closes (terminates) every open tab belonging to [workspaceId] by dropping
  /// its whole bucket and disposing each tab's sessions and team-bus.
  void closeTabsForWorkspace(String workspaceId) {
    final removed = _tabStore.removeWorkspace(workspaceId);
    if (removed.isEmpty) return;
    for (final tab in removed) {
      unawaited(_tearDownTab(tab));
    }
    _sessionRuntime.maybeStopIdleWatch();
    // Republish whenever the active bucket was affected: either it was the
    // named bucket for this workspace, or it is the legacy empty-string bucket
    // and tabs were removed from it (legacy path before setActiveWorkspace).
    final activeIsAffected =
        workspaceId == _tabStore.activeWorkspaceId ||
        _tabStore.activeWorkspaceId.isEmpty;
    if (activeIsAffected) {
      _publishActiveWorkspaceTabs(0);
    }
  }

  void closeOtherTabs(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    for (var i = _tabStore.activeTabCount - 1; i >= 0; i--) {
      if (i == index) continue;
      final tab = _tabStore.removeAt(i);
      unawaited(_tearDownTab(tab));
    }
    _sessionRuntime.maybeStopIdleWatch();
    final kept = _tabStore.activeTabs.single;
    _tabStore.setComposeActive(_tabStore.activeWorkspaceId, false);
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: 0,
        activeSessionId: kept.info.id,
        selectedMemberId: kept.selectedMemberId,
        composeActive: false,
      ),
    );
    _pushPresenceTarget();
  }

  void closeRightTabs(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    for (var i = _tabStore.activeTabCount - 1; i > index; i--) {
      final tab = _tabStore.removeAt(i);
      unawaited(_tearDownTab(tab));
    }
    _sessionRuntime.maybeStopIdleWatch();
    final active = _activeTab;
    _tabStore.setComposeActive(_tabStore.activeWorkspaceId, false);
    emit(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeTabIndex: state.activeTabIndex.clamp(0, _tabStore.activeTabCount - 1),
        activeSessionId: active?.info.id,
        selectedMemberId: active?.selectedMemberId ?? '',
        composeActive: false,
      ),
    );
    _pushPresenceTarget();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabStore.activeTabCount) return;
    final tab = _tabStore.activeTabs[index];
    _tabStore.setComposeActive(_tabStore.activeWorkspaceId, false);
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        composeActive: false,
      ),
    );
    _pushPresenceTarget();
  }

  /// Moves to the next open session tab, wrapping from the last tab back to
  /// the first. No-op when there are no open tabs (compose-only landing).
  ///
  /// If the compose landing is showing while tabs still exist, this still
  /// selects a tab (clearing compose) rather than treating compose as "no
  /// tabs" — [state.activeTabIndex] is preserved while compose is active, so
  /// navigation resumes from the last selected tab.
  void selectNextSessionTab() {
    final count = _tabStore.activeTabCount;
    if (count == 0) return;
    selectTab((state.activeTabIndex + 1) % count);
  }

  /// Moves to the previous open session tab, wrapping from the first tab
  /// back to the last. See [selectNextSessionTab] for compose-landing
  /// semantics.
  void selectPreviousSessionTab() {
    final count = _tabStore.activeTabCount;
    if (count == 0) return;
    selectTab((state.activeTabIndex - 1 + count) % count);
  }

  /// Selects the session tab at 1-based [ordinal] (Alt+1…9 / Alt+0 → 10).
  ///
  /// No-op when [ordinal] is out of range or there is no tab at that index.
  /// Clears compose landing when a tab is selected (same as [selectTab]).
  void selectSessionTabAt(int ordinal) {
    if (ordinal < 1 || ordinal > 10) return;
    selectTab(ordinal - 1);
  }

  /// Sets History vs Terminal center body for an open session tab.
  void setSessionWorkbenchView(
    String sessionId,
    SessionWorkbenchView view,
  ) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null || tab.workbenchView == view) return;
    tab.workbenchView = view;
    emit(state.copyWith(stateVersion: state.stateVersion + 1));
    if (view == SessionWorkbenchView.history) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  /// Shows the compose landing for [workspaceId] without closing open tabs.
  void enterComposeMode(String workspaceId) {
    final wasActive = _tabStore.activeWorkspaceId == workspaceId;
    if (!wasActive) {
      _tabStore.setComposeActive(workspaceId, true);
      return;
    }
    _tabStore.setComposeActive(workspaceId, true);
    final index = state.activeTabIndex.clamp(
      0,
      _tabStore.activeTabCount == 0 ? 0 : _tabStore.activeTabCount - 1,
    );
    emit(
      state.copyWith(
        activeTabIndex: index,
        clearActiveSessionId: true,
        selectedMemberId: '',
        composeActive: true,
      ),
    );
    _pushPresenceTarget();
  }

  /// Leaves compose mode and selects the remembered session tab index.
  void exitComposeMode() {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (!_tabStore.isComposeActive(workspaceId)) return;
    _tabStore.setComposeActive(workspaceId, false);
    if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setComposeActive(workspaceId, true);
      emit(state.copyWith(composeActive: true));
      return;
    }
    final index = state.activeTabIndex.clamp(0, _tabStore.activeTabCount - 1);
    final tab = _tabStore.activeTabs[index];
    emit(
      state.copyWith(
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
        composeActive: false,
      ),
    );
    _pushPresenceTarget();
  }

  /// Clears compose without selecting a session (e.g. opening a file/diff tab).
  void dismissCompose() {
    final workspaceId = _tabStore.activeWorkspaceId;
    if (!_tabStore.isComposeActive(workspaceId) && !state.composeActive) {
      return;
    }
    _tabStore.setComposeActive(workspaceId, false);
    if (state.composeActive) {
      emit(state.copyWith(composeActive: false));
    }
  }

  void syncTeam(TeamProfile team) {
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
    TeamProfile team, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) => _launchService.launchAllMembers(
    team,
    repo: repo,
    workspaceCwd: workspaceCwd,
  );

  String selectedMemberName(TeamProfile team) {
    for (final m in team.members) {
      if (m.id == state.selectedMemberId) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession? ensureSession(TeamProfile team) =>
      _launchService.ensureSession(team);

  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _launchService.connectWorkspaceSession(request, repo: repo);

  void disconnectSession() {
    final tab = activeTab;
    final sessionId = tab?.info.id;
    _launchService.disconnectSession();
    if (sessionId != null && sessionId.isNotEmpty) {
      onSessionHistoryStale?.call(sessionId);
    }
  }

  Future<void> restartWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) => _launchService.restartWorkspaceSession(request, repo: repo);

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
    for (final tab in _tabStore.openTabs) {
      if (tab.info.id == sessionId) {
        tab.info = tab.info.copyWith(title: newName);
      }
    }
    _emitSnapshot(
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions, tabs: tabs),
    );
  }

  /// Compose-landing / inject path: rename untitled session from first prompt.
  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) =>
      _launchService.applyFirstPromptTitle(sessionId, firstPrompt);

  Future<void> touchSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.touchSession(sessionId);
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  /// Persists session-level or per-member continue permission overrides.
  ///
  /// Returns false when the repo/session is missing or persistence fails.
  Future<bool> setSessionContinuePermission({
    required String sessionId,
    required bool dangerouslySkipPermissions,
    String? memberId,
  }) async {
    final repo = _sessionRepository;
    if (repo == null) return false;
    final session = _continueOverridesController.sessionIn(
      state.sessions,
      sessionId,
    );
    if (session == null) return false;
    final patched = _continueOverridesController.patchPermission(
      session: session,
      dangerouslySkipPermissions: dangerouslySkipPermissions,
      memberId: memberId,
    );
    try {
      await _continueOverridesController.persistPermission(
        repo: repo,
        patched: patched,
      );
      replaceSessionSnapshot(patched);
      return true;
    } on Object {
      return false;
    }
  }

  /// Persists a same-CLI preset for Simple identity or a team member override.
  ///
  /// Returns false when [preset.cli] does not match [lockedCli] (no disk write).
  Future<bool> setSessionContinuePreset({
    required String sessionId,
    required CliPreset preset,
    String? memberId,
    required CliTool lockedCli,
  }) async {
    final repo = _sessionRepository;
    if (repo == null) return false;
    final session = _continueOverridesController.sessionIn(
      state.sessions,
      sessionId,
    );
    if (session == null) return false;
    final patched = _continueOverridesController.patchPreset(
      session: session,
      preset: preset,
      memberId: memberId,
      lockedCli: lockedCli,
    );
    if (patched == null) return false;
    await _continueOverridesController.persistPreset(
      repo: repo,
      patched: patched,
      memberId: memberId,
    );
    replaceSessionSnapshot(patched);
    return true;
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
      _dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
      base: state.copyWith(sessions: sessions),
    );
    await repo.reorderSessions(orderedSessionIds);
  }

  Future<void> toggleSessionPin(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    await repo.toggleSessionPin(sessionId);
    _emitSnapshot(await _dataStore.loadWorkspaceData(repo));
  }

  Future<void> deleteSession(SessionRepository repo, String sessionId) async {
    final session = state.sessions
        .where((s) => s.sessionId == sessionId)
        .firstOrNull;
    final wasActive = state.activeSessionId == sessionId;
    final sessions = state.sessions
        .where((s) => s.sessionId != sessionId)
        .toList();
    final idx = _tabStore.activeIndexOfSession(sessionId);
    if (idx != -1) {
      final tab = _tabStore.removeAt(idx);
      await _tearDownTab(tab);
      _sessionRuntime.maybeStopIdleWatch();
    }
    final tabs = _tabStore.activeTabs.map((t) => t.info).toList();

    if (wasActive && !_tabStore.activeTabsIsEmpty) {
      final newIdx = idx < _tabStore.activeTabCount ? idx : _tabStore.activeTabCount - 1;
      final nextTab = _tabStore.activeTabs[newIdx];
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(
          tabs: tabs,
          activeTabIndex: newIdx,
          activeSessionId: nextTab.info.id,
          selectedMemberId: nextTab.selectedMemberId,
        ),
      );
    } else if (_tabStore.activeTabsIsEmpty) {
      _tabStore.setComposeActive(_tabStore.activeWorkspaceId, true);
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(
          tabs: [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          composeActive: true,
        ),
      );
    } else {
      _emitSnapshot(
        _dataStore.deriveSnapshot(
          workspaces: state.workspaces,
          sessions: sessions,
        ),
        base: state.copyWith(tabs: tabs),
      );
    }

    _emitSnapshot(await _dataStore.deleteSessionRecord(repo, sessionId));
    if (session != null) {
      await _automationRepository.disableForSession(
        AutomationTabScope.fromSession(session),
        sessionId,
      );
      _notifyAutomationsChanged();
    }
  }

  Future<Workspace> cloneWorkspace(
    SessionRepository repo,
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final result = await _dataStore.cloneWorkspace(
      repo,
      sourceWorkspaceId,
      display: display,
      rosterMembers: rosterMembers,
    );
    _emitSnapshot(result.snapshot);
    return result.workspace;
  }

  Future<void> deleteWorkspace(
    SessionRepository repo,
    String workspaceId,
  ) async {
    Workspace? workspace;
    for (final p in state.workspaces) {
      if (p.workspaceId == workspaceId) {
        workspace = p;
        break;
      }
    }
    if (workspace == null) return;
    for (final sid in workspace.sessionIds.toList()) {
      await deleteSession(repo, sid);
    }
    await _automationRepository.removeWorkspace(workspaceId);
    _notifyAutomationsChanged();
    _emitSnapshot(await _dataStore.deleteWorkspaceRecord(repo, workspaceId));
  }

  void addSystemMessage(String content) {
    final target = currentSession;
    target?.write('\r\n[system] $content\r\n');
  }

  bool hasTeamBusResources(String sessionId) =>
      _teamBus.hasTeamBusResources(sessionId);

  @visibleForTesting
  Uri? teammateBusMcpEndpointForSession(String sessionId) =>
      _teamBus.teammateBusMcpEndpointForSession(sessionId);

  @override
  Future<void> close() async {
    if (isClosed) return;
    _sessionRuntime.disposeIdleWatch();
    final busDisposals = <Future<void>>[];
    for (final tab in _tabStore.openTabs) {
      busDisposals.add(_tearDownTab(tab));
    }
    await Future.wait(busDisposals);
    _tabStore.clear();
    await super.close();
  }
}
