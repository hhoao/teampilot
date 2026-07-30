import 'dart:async';

import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../cli/installer_types.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/remote_cli_locator.dart';
import '../provider/config_profile_service.dart';
import '../remote/remote_app_data_materializer.dart';
import '../remote/remember_remote_cli_path.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_storage_io.dart';
import '../ssh/ssh_transport_close.dart';
import '../storage/runtime_context.dart';
import 'launch_artifacts.dart';

typedef WorkspaceContextResolver =
    Future<RuntimeContext> Function(RuntimeTarget target);

/// Phase A: workspace-level machine preparation (ancestry, workspace profile,
/// CLI on path). Not invoked from the session connect hot path once [ready].
///
/// Remote CLI **install** is user-driven (Machines). This provisioner only
/// locates an existing remote CLI (or uses a path override).
class WorkspaceProvisioner {
  WorkspaceProvisioner({
    required this.registry,
    required this.sshClientFactory,
    required this.profileById,
    required this.contextForTarget,
    required this.homeContext,
    required this.isCredentialOptIn,
    required this.cliPathOverride,
    required this.setCliPathOverride,
    required this.loadLocalCredentials,
    required this.configProfileFactory,
    required this.localCliPath,
    this.linkResources,
    this.provisionRelay,
  }) : _installer = RemoteCliInstaller(
         locator: RemoteCliLocator(registry: registry),
       ),
       _appData = RemoteAppDataMaterializer(
         loadLocalCredentials: loadLocalCredentials,
         linkResources: linkResources,
         provisionRelay: provisionRelay,
       );

  final CliToolRegistry registry;
  final SshClientFactory sshClientFactory;
  final SshProfile? Function(String profileId) profileById;
  final WorkspaceContextResolver contextForTarget;
  final RuntimeContext Function() homeContext;
  final Future<bool> Function(String targetId) isCredentialOptIn;
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

  Future<WorkspaceProvisionResult> provision({
    required RuntimeTarget target,
    required String workspaceId,
    required CliTool cli,
    Iterable<String> trustedDirectories = const [],
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final sw = Stopwatch()..start();
    void step(String name) {
      appLogger.d(
        '[workspace-provision] $name target=${target.id} '
        'workspace=$trimmedWorkspaceId cli=${cli.value} '
        'elapsedMs=${sw.elapsedMilliseconds}',
      );
    }

    void report(CliInstallPhase phase, {String? detail}) {
      final progress = CliInstallProgress(phase: phase, detail: detail);
      onProgress?.call(progress);
      appLogger.d(
        '[workspace-provision] progress phase=${phase.name} '
        'detail=${detail ?? ''} target=${target.id} '
        'elapsedMs=${sw.elapsedMilliseconds}',
      );
    }

    step('start');
    report(CliInstallPhase.locatingExecutable, detail: 'resolve-work-ctx');
    step('resolve-work-ctx begin');
    final workContext = await SshStorageIo.awaitOrThrow(
      contextForTarget(target),
      timeout: SshStorageIo.locateTimeout,
      operation: 'resolve work context (${target.id})',
    );
    step('resolve-work-ctx done root=${workContext.appDataRoot}');

    report(CliInstallPhase.locatingExecutable, detail: 'ensure-cli');
    step('ensure-cli begin');
    final remoteCliPath = await _ensureCli(target: target, cli: cli);
    step('ensure-cli done path=$remoteCliPath');

    final home = homeContext();
    if (target.kind == RuntimeKind.ssh) {
      final optInCredentials = await isCredentialOptIn(target.id);
      report(
        CliInstallPhase.syncingRemoteWorkspace,
        detail: 'materialize',
      );
      step('materialize-app-data begin optInCredentials=$optInCredentials');
      await SshStorageIo.awaitOrThrow(
        _appData.materialize(
          homeFs: home.fs,
          homeRoot: home.appDataRoot,
          workFs: workContext.fs,
          machineRoot: workContext.appDataRoot,
          cli: cli,
          workspaceId: trimmedWorkspaceId,
          optInCredentials: optInCredentials,
        ),
        timeout: SshStorageIo.provisionPhaseTimeout,
        operation: 'materialize app data',
      );
      step('materialize-app-data done');
    }

    step('config-profile begin');
    final configProfile = await configProfileFactory(workContext);
    if (target.kind == RuntimeKind.ssh) {
      report(
        CliInstallPhase.syncingRemoteWorkspace,
        detail: 'workspace-config',
      );
    }
    step('provision-workspace begin trusted=${trustedDirectories.length}');
    await SshStorageIo.awaitOrThrow(
      configProfile.provisionWorkspace(
        workspaceId: trimmedWorkspaceId,
        cli: cli,
        trustedDirectories: trustedDirectories,
      ),
      timeout: SshStorageIo.provisionPhaseTimeout,
      operation: 'provision workspace config',
    );
    step('done');
    return WorkspaceProvisionResult(
      workContext: workContext,
      remoteCliPath: remoteCliPath,
    );
  }

  /// Locate-only. Never installs — install from Machines UI.
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
    final sw = Stopwatch()..start();
    appLogger.d(
      '[workspace-provision] ensure-cli locate begin '
      'target=${target.id} cli=${cli.value} host=${profile.host}',
    );
    final client = await sshClientFactory.clientForStorage(profile);
    final run = RemoteCliLocator.runnerForClient(
      client,
      timeout: SshStorageIo.locateTimeout,
    );
    final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
        .trim();
    try {
      final path = await SshStorageIo.awaitOrThrow(
        _installer.locate(
          cli: cli,
          run: run,
          manualPathOverride: storedPath,
        ),
        timeout: SshStorageIo.locateTimeout,
        operation: 'remote CLI locate (${cli.value})',
      );
      if (path == null || path.trim().isEmpty) {
        throw RemoteCliUnavailableException(
          cli,
          RemoteCliUnavailableReason.notInstalled,
        );
      }
      appLogger.d(
        '[workspace-provision] ensure-cli locate hit '
        'target=${target.id} path=$path '
        'elapsedMs=${sw.elapsedMilliseconds}',
      );
      await rememberRemoteCliPathIfNeeded(
        targetId: target.id,
        cli: cli,
        resolvedPath: path,
        readCliPathOverride: cliPathOverride,
        writeCliPathOverride: setCliPathOverride,
      );
      return path;
    } on TimeoutException {
      sshClientFactory.disconnectProfile(
        profile.id,
        reason: SshTransportCloseReason.transportError,
      );
      rethrow;
    }
  }
}
