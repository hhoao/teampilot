import '../../../models/runtime_target.dart';
import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import 'session_launch_service.dart';
import '../host/session_launch_host.dart';
import '../../../repositories/ssh_credential_store.dart';
import '../../../repositories/ssh_known_host_repository.dart';
import '../../../repositories/session_repository.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../expert_hub/expert_capability_resolver.dart';
import '../../expert_hub/local_expert_store.dart';
import '../../remote/remote_app_data_materializer.dart';
import '../session/session_lifecycle_service.dart';
import '../../ssh/ssh_client_factory.dart';
import '../../storage/home_storage.dart';
import '../../storage/runtime_context.dart';
import 'staging/session_connect_orchestrator.dart';
import 'staging/session_runtime_plan_builder.dart';
import 'staging/manifest/manifest_executor.dart';
import 'workspace/workspace_provision_coordinator.dart';
import 'workspace/workspace_provisioner.dart';
import 'connect/member_connect_stage.dart';
import 'connect/session_connect_executor.dart';
import 'connect/session_connect_scheduler.dart';
import '../runtime/inflight/session_lifecycle_connect_coordinator.dart';
import 'connect/session_shell_connector.dart';
import 'connect/session_ssh_profile_reconnect.dart';
import 'session/session_default_materializer.dart';
import 'session/session_launch_coordinator.dart';
import 'session/session_launch_workspace_index.dart';
import 'session/session_prompt_metadata_sync.dart';
import 'session/session_persistence_writer.dart';
import 'tab/session_tab_surface_coordinator.dart';
import 'team_config_launch_validator.dart';

SessionConnectOrchestrator buildSessionConnectOrchestrator({
  required SessionLifecycleService lifecycle,
  required CliToolRegistry registry,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function(String profileId) profileById,
  required Future<RuntimeContext> Function(RuntimeTarget target)
  contextForTarget,
  required RuntimeContext Function() homeContext,
  required RuntimeTarget Function() homeTarget,
  required Future<bool> Function(String targetId) isCredentialOptIn,
  required Future<String?> Function(String targetId, String cliValue)
  cliPathOverride,
  required Future<void> Function(String targetId, String cliValue, String path)
  setCliPathOverride,
  required LocalCredentialsLoader loadLocalCredentials,
  required Future<String> Function(CliTool cli) localCliPath,
  required SessionRuntimePlanBuilder runtimePlanBuilder,
  RemoteResourceLinker? linkResources,
  RemoteRelayProvisioner? provisionRelay,
}) {
  final provisioner = WorkspaceProvisioner(
    registry: registry,
    sshClientFactory: sshClientFactory,
    profileById: profileById,
    contextForTarget: contextForTarget,
    homeContext: homeContext,
    isCredentialOptIn: isCredentialOptIn,
    cliPathOverride: cliPathOverride,
    setCliPathOverride: setCliPathOverride,
    loadLocalCredentials: loadLocalCredentials,
    localCliPath: localCliPath,
    linkResources: linkResources,
    provisionRelay: provisionRelay,
    configProfileFactory: lifecycle.configProfileServiceFor,
  );

  final workspaceProvision = WorkspaceProvisionCoordinator(
    provisioner: provisioner,
    homeTarget: homeTarget,
  );

  final manifestExecutor = ManifestExecutor(
    sshClientFactory: sshClientFactory,
    profileById: profileById,
  );

  return SessionConnectOrchestrator(
    lifecycle: lifecycle,
    workspaceProvision: workspaceProvision,
    configProfileFor: lifecycle.configProfileServiceFor,
    homeContext: homeContext,
    manifestExecutor: manifestExecutor,
    runtimePlanBuilder: runtimePlanBuilder,
    registry: registry,
  );
}

/// Local-default orchestrator when [ChatCubit] is constructed without explicit
/// wiring (tests, lightweight harnesses). Production uses [app_shell] DI.
SessionConnectOrchestrator buildDefaultSessionConnectOrchestrator({
  required SessionLifecycleService lifecycle,
  required HomeStorage storage,
  required Future<String> Function(CliTool cli) localCliPath,
  SessionRuntimePlanBuilder? runtimePlanBuilder,
  SshClientFactory? sshClientFactory,
  SshProfile? Function(String profileId)? profileById,
  RuntimeTarget Function()? homeTarget,
}) {
  RuntimeContext homeContext() {
    final paths = storage.paths;
    return RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: storage.fs,
      home: storage.home,
      cwd: storage.cwd,
      appDataRoot: paths.basePath,
      paths: paths,
    );
  }

  final builder =
      runtimePlanBuilder ??
      SessionRuntimePlanBuilder(
        expertResolver: ExpertCapabilityResolver(
          installSkill: (_) async => null,
          installPlugin: (_) async => null,
          installMcp: (_) async => null,
          localStore: LocalExpertStore(
            fs: storage.fs,
            dirOverride: storage.paths.memberHubLocalTemplatesDir,
          ),
        ),
        workspaceProjectConfig: WorkspaceProjectConfigRepository(
          storage: storage,
        ),
      );

  return buildSessionConnectOrchestrator(
    lifecycle: lifecycle,
    registry: CliToolRegistry.builtIn(),
    sshClientFactory:
        sshClientFactory ??
        SshClientFactory(
          credentialStore: InMemorySshCredentialStore(),
          knownHostRepository: InMemorySshKnownHostRepository(),
        ),
    profileById: profileById ?? (_) => null,
    contextForTarget: (target) =>
        lifecycle.resolveWorkContextForTargetId(target.id),
    homeContext: homeContext,
    homeTarget: homeTarget ?? RuntimeTarget.local,
    isCredentialOptIn: (_) async => false,
    cliPathOverride: (_, __) async => null,
    setCliPathOverride: (_, __, ___) async {},
    loadLocalCredentials: (_) async => const [],
    localCliPath: localCliPath,
    runtimePlanBuilder: builder,
  );
}

/// Builds the complete session launch graph at the application composition
/// root. The service is the typed preparation/delegate boundary used by the
/// executor, while all queueing and intent collaborators are assembled here.
SessionLaunchService buildSessionLaunchService({
  required SessionLaunchHost host,
  required HomeStorage storage,
  TermuxWorkOpsBlockResolver? termuxWorkOpsBlockFor,
  void Function(
    String workspaceId,
    String sessionId, {
    bool preview,
    bool activate,
  })?
  onSessionTabOpened,
}) {
  final dataStore = host.dataStore;
  final postFrame = host.postFrameScheduler;
  final tabStore = host.tabStore;
  final service = SessionLaunchService(
    host,
    storage: storage,
    onSessionTabOpened: onSessionTabOpened,
  );
  final persistence = SessionPersistenceWriter(
    repository: host,
    snapshots: host,
    chatState: host,
    tabs: host,
    environment: host,
    dataStore: dataStore,
  );
  final shellConnector = SessionShellConnector(
    host,
    service,
    persister: persistence,
    isLocalNative: () => storage.context.mode == StorageBackendMode.native,
    termuxWorkOpsBlockFor: termuxWorkOpsBlockFor,
  );
  final executor = SessionConnectExecutor(
    preparation: service,
    shellConnector: shellConnector,
    onResult: service.onConnectResult,
  );
  final scheduler = SessionConnectScheduler(
    executor: executor,
    postFrame: postFrame,
    isJobValid: service.isValid,
    onBegin: host.beginSessionConnect,
    onFinish: (sessionId) {
      if (host.isSessionConnecting(sessionId)) {
        host.finishSessionConnect(sessionId);
      }
    },
  );
  final tabSurface = SessionTabSurfaceCoordinator(
    host: host,
    tabStore: tabStore,
    onSessionTabOpened: onSessionTabOpened,
  );
  final workspaceIndex = () => SessionLaunchWorkspaceIndex(
    workspaces: host.state.workspaces,
    sessions: host.state.sessions,
    usesPosixPaths: storage.usesPosixPaths,
  );
  late final MemberConnectStage memberConnect;
  final coordinator = SessionLaunchCoordinator(
    host: host,
    tabStore: tabStore,
    tabSurface: tabSurface,
    scheduler: scheduler,
    workspaceIndex: workspaceIndex,
    openMemberIntent:
        (team, member, {SessionRepository? repo, String? workspaceCwd}) =>
            memberConnect.openMemberTab(
              team,
              member,
              repo: repo,
              workspaceCwd: workspaceCwd,
            ),
  );
  final materializer = SessionDefaultMaterializer(
    host: host,
    coordinator: coordinator,
    workspaceIndex: workspaceIndex,
    isTabsEmpty: () => tabStore.activeTabsIsEmpty,
    activeBucketKey: () => tabStore.activeWorkspaceId,
  );
  memberConnect = MemberConnectStage(
    host: host,
    tabStore: tabStore,
    state: () => host.state,
    materializer: materializer,
    coordinator: coordinator,
    scheduler: scheduler,
    sessionForMemberConnect: service.sessionForMemberConnect,
    disconnectSession: service.disconnectSession,
    ensureSession: service.ensureSession,
    appendLocalTab: service.appendLocalTab,
    ensureActiveSessionTab: service.ensureActiveSessionTab,
    resetTeamConfigValidationSurface: service.resetTeamConfigValidationSurface,
    scheduleTeamConfigValidation: service.scheduleTeamConfigValidation,
    activeTab: () => host.activeTab,
    autoLaunchAllMembersOnConnect: () =>
        host.autoLaunchAllMembersOnConnect?.call() == true,
    workspaceById: service.workspaceById,
  );
  final sshReconnect = SessionSshProfileReconnect(
    host: host,
    coordinator: coordinator,
    launchContextFor: service.launchContextFor,
    workspaceIndex: workspaceIndex,
    openTabs: () => tabStore.openTabs,
  );
  final lifecycleCoordinator = SessionLifecycleConnectCoordinator(
    host: host,
    launchContextFor: service.launchContextFor,
    launchWorkTarget: service.launchWorkTarget,
    scheduleMemberConnect: memberConnect.scheduleMemberConnect,
    tabOpen: (sessionId) => tabStore.openTabBySessionId(sessionId) != null,
  );
  service.configureLaunchComponents(
    connectScheduler: scheduler,
    coordinator: coordinator,
    memberConnect: memberConnect,
    sshReconnect: sshReconnect,
    lifecycleCoordinator: lifecycleCoordinator,
    promptMetadata: SessionPromptMetadataSync(
      host: host,
      state: () => host.state,
    ),
    teamConfigValidator: TeamConfigLaunchValidator(storage: storage),
  );
  return service;
}
