import '../../models/personal_profile.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../utils/logger.dart';
import '../cli/registry/capabilities/installer_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/remote_cli_locator.dart';
import '../provider/config_profile_service.dart';
import '../remote/remote_app_data_materializer.dart';
import '../remote/remote_preflight_cli_install.dart';
import '../remote/remember_remote_cli_path.dart';
import '../ssh/ssh_client_factory.dart';
import '../storage/runtime_context.dart';
import 'launch_artifacts.dart';

typedef WorkspaceContextResolver = Future<RuntimeContext> Function(
  RuntimeTarget target,
);

/// Phase A: workspace-level machine preparation (ancestry, workspace profile,
/// CLI on path). Not invoked from the session connect hot path once [ready].
class WorkspaceProvisioner {
  WorkspaceProvisioner({
    required this.registry,
    required this.sshClientFactory,
    required this.profileById,
    required this.contextForTarget,
    required this.homeContext,
    required this.isCredentialOptIn,
    required this.isInstallOptIn,
    required this.cliPathOverride,
    required this.setCliPathOverride,
    required this.loadLocalCredentials,
    required this.configProfileFactory,
    required this.localCliPath,
    this.linkResources,
    this.provisionRelay,
    RemoteInstallAction Function(
      CliTool cli,
      SshProfile profile,
      SshCommandRunner run,
    )? installActionBuilder,
  }) : _installer = RemoteCliInstaller(locator: RemoteCliLocator(registry: registry)),
       _appData = RemoteAppDataMaterializer(
         loadLocalCredentials: loadLocalCredentials,
         linkResources: linkResources,
         provisionRelay: provisionRelay,
       ),
       _installActionBuilder = installActionBuilder;

  final CliToolRegistry registry;
  final SshClientFactory sshClientFactory;
  final SshProfile? Function(String profileId) profileById;
  final WorkspaceContextResolver contextForTarget;
  final RuntimeContext Function() homeContext;
  final Future<bool> Function(String targetId) isCredentialOptIn;
  final Future<bool> Function(String targetId) isInstallOptIn;
  final Future<String?> Function(String targetId, String cliValue)
  cliPathOverride;
  final Future<void> Function(String targetId, String cliValue, String path)
  setCliPathOverride;
  final LocalCredentialsLoader loadLocalCredentials;
  final Future<ConfigProfileService> Function(RuntimeContext workContext)
  configProfileFactory;
  final Future<String> Function(CliTool cli) localCliPath;
  final RemoteResourceLinker? linkResources;
  final RemoteRelayProvisioner? provisionRelay;

  final RemoteCliInstaller _installer;
  final RemoteAppDataMaterializer _appData;
  final RemoteInstallAction Function(
    CliTool cli,
    SshProfile profile,
    SshCommandRunner run,
  )? _installActionBuilder;

  Future<WorkspaceProvisionResult> provision({
    required RuntimeTarget target,
    required String workspaceId,
    required CliTool cli,
    PersonalProfile? personal,
    Iterable<String> trustedDirectories = const [],
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    appLogger.d(
      '[workspace-provision] start target=${target.id} '
      'workspace=$trimmedWorkspaceId cli=${cli.value}',
    );
    final workContext = await contextForTarget(target);
    final remoteCliPath = await _ensureCli(target: target, cli: cli);
    final home = homeContext();
    if (target.kind == RuntimeKind.ssh) {
      await _appData.materialize(
        homeFs: home.fs,
        homeRoot: home.appDataRoot,
        workFs: workContext.fs,
        machineRoot: workContext.appDataRoot,
        cli: cli,
        workspaceId: trimmedWorkspaceId,
        optInCredentials: await isCredentialOptIn(target.id),
      );
    }
    if (personal != null) {
      final configProfile = await configProfileFactory(workContext);
      await configProfile.provisionWorkspace(
        workspaceId: trimmedWorkspaceId,
        cli: cli,
        personal: personal,
        trustedDirectories: trustedDirectories,
      );
    }
    appLogger.d(
      '[workspace-provision] done target=${target.id} '
      'workspace=$trimmedWorkspaceId cli=${cli.value}',
    );
    return WorkspaceProvisionResult(
      workContext: workContext,
      remoteCliPath: remoteCliPath,
    );
  }

  Future<String> _ensureCli({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    if (target.kind != RuntimeKind.ssh) {
      return localCliPath(cli);
    }
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      throw StateError('No SSH profile for target "${target.id}".');
    }
    final client = await sshClientFactory.clientFor(profile);
    final run = RemoteCliLocator.runnerForClient(client);
    final storedPath = (await cliPathOverride(target.id, cli.value) ?? '').trim();
    final path = await _installer.ensure(
      cli: cli,
      run: run,
      optIn: await isInstallOptIn(target.id),
      supportsInstaller:
          registry.capability<InstallerCapability>(cli)?.supportsInstaller ??
          false,
      install:
          _installActionBuilder?.call(cli, profile, run) ??
          buildRemotePreflightCliInstall(
            registry: registry,
            profile: profile,
            cli: cli,
          ),
      manualPathOverride: storedPath,
    );
    await rememberRemoteCliPathIfNeeded(
      targetId: target.id,
      cli: cli,
      resolvedPath: path,
      readCliPathOverride: cliPathOverride,
      writeCliPathOverride: setCliPathOverride,
    );
    return path;
  }
}
