import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../remote/remote_app_data_materializer.dart';
import '../session/session_lifecycle_service.dart';
import '../ssh/ssh_client_factory.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';
import 'session_connect_orchestrator.dart';
import 'manifest_executor.dart';
import 'workspace_provision_coordinator.dart';
import 'workspace_provisioner.dart';

SessionConnectOrchestrator buildSessionConnectOrchestrator({
  required SessionLifecycleService lifecycle,
  required CliToolRegistry registry,
  required SshClientFactory sshClientFactory,
  required SshProfile? Function(String profileId) profileById,
  required Future<RuntimeContext> Function(RuntimeTarget target) contextForTarget,
  required RuntimeContext Function() homeContext,
  required RuntimeTarget Function() homeTarget,
  required Future<bool> Function(String targetId) isCredentialOptIn,
  required Future<bool> Function(String targetId) isInstallOptIn,
  required Future<String?> Function(String targetId, String cliValue)
  cliPathOverride,
  required Future<void> Function(String targetId, String cliValue, String path)
  setCliPathOverride,
  required LocalCredentialsLoader loadLocalCredentials,
  required Future<String> Function(CliTool cli) localCliPath,
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
    isInstallOptIn: isInstallOptIn,
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
  );
}

/// Local-default orchestrator when [ChatCubit] is constructed without explicit
/// wiring (tests, lightweight harnesses). Production uses [app_shell] DI.
SessionConnectOrchestrator buildDefaultSessionConnectOrchestrator({
  required SessionLifecycleService lifecycle,
  required Future<String> Function(CliTool cli) localCliPath,
  SshClientFactory? sshClientFactory,
  SshProfile? Function(String profileId)? profileById,
  RuntimeTarget Function()? homeTarget,
}) {
  RuntimeContext homeContext() {
    final paths = AppStorage.paths;
    return RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: AppStorage.fs,
      home: AppStorage.home,
      cwd: AppStorage.cwd,
      appDataRoot: paths.basePath,
      paths: paths,
    );
  }

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
    isInstallOptIn: (_) async => false,
    cliPathOverride: (_, __) async => null,
    setCliPathOverride: (_, __, ___) async {},
    loadLocalCredentials: (_) async => const [],
    localCliPath: localCliPath,
  );
}
