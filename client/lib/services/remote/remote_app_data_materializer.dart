import '../cli/registry/capabilities/remote_app_data_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../../models/team_config.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../cli/opencode/provider/opencode_shared_plugin_deps.dart';
import '../storage/runtime_layout.dart';
import 'materialization_manifest.dart';
import 'remote_credential_materializer.dart';
import 'work_machine_materializer.dart';

/// Loads the locally-generated credential files for [cli] (per-CLI credential
/// services produce them locally). Injected so the work-machine materialize is
/// unit-testable without touching real credential stores.
typedef LocalCredentialsLoader =
    Future<List<CredentialFile>> Function(CliTool cli);

/// Seeds home `cli-defaults/opencode` plugin deps (local npm). Injected so
/// materialize tests can assert call order without a real `npm install`.
typedef HomeOpencodeSharedPluginDepsSeeder =
    Future<void> Function({
      required Filesystem homeFs,
      required String homeRoot,
    });

/// Links a CLI's team skills/plugins on the work machine (over its [workFs]).
/// Injected; the real linkers are fs-injected services (run on-device against
/// SFTP). [B4]
typedef RemoteResourceLinker =
    Future<void> Function({
      required Filesystem workFs,
      required String machineRoot,
      required CliTool cli,
      required String workspaceId,
    });

/// Materializes the relay (P3b) onto the work machine for a long-blocking CLI.
/// Injected; real impl runs `RelayProvisioner` over the work transport. [B4]
typedef RemoteRelayProvisioner =
    Future<void> Function({
      required Filesystem workFs,
      required String machineRoot,
      required CliTool cli,
    });

/// Composes the full work-machine app-data materialize (P3c §3.3): ancestry +
/// inheritance ([WorkMachineMaterializer]) → skills/plugins linking → relay →
/// per-target opt-in credentials ([RemoteCredentialMaterializer]). Every side
/// effect goes through injected fs/loaders, so it is unit-testable with two
/// in-memory filesystems; only the real SFTP/SSH writes are on-device.
class RemoteAppDataMaterializer {
  RemoteAppDataMaterializer({
    required this.loadLocalCredentials,
    this.linkResources,
    this.provisionRelay,
    this.ensureOpencodeSharedPluginDeps,
  });

  final LocalCredentialsLoader loadLocalCredentials;
  final RemoteResourceLinker? linkResources;
  final RemoteRelayProvisioner? provisionRelay;
  final HomeOpencodeSharedPluginDepsSeeder? ensureOpencodeSharedPluginDeps;

  Future<void> materialize({
    required Filesystem homeFs,
    required String homeRoot,
    required Filesystem workFs,
    required String machineRoot,
    required CliTool cli,
    required String workspaceId,
    required bool optInCredentials,
  }) async {
    final sw = Stopwatch()..start();
    void step(String name) {
      appLogger.d(
        '[workspace-provision] materialize $name '
        'cli=${cli.value} workspace=$workspaceId '
        'elapsedMs=${sw.elapsedMilliseconds}',
      );
    }

    final manifest = MaterializationManifest(
      fs: workFs,
      machineRoot: machineRoot,
    );

    // Seed shared opencode plugin deps on home before reconcile copies
    // cli-defaults onto the work machine. Never npm-install on workFs/SFTP.
    final remoteAppData = CliToolRegistry.builtIn()
        .capability<RemoteAppDataCapability>(cli);
    if (remoteAppData?.needsSharedPluginDepsBeforeReconcile == true) {
      step('shared-plugin-deps begin');
      await remoteAppData!.seedSharedPluginDeps(
        homeFs: homeFs,
        homeRoot: homeRoot,
      );
      step('shared-plugin-deps done');
    }

    step('reconcile begin');
    await WorkMachineMaterializer(
      homeFs: homeFs,
      homeRoot: homeRoot,
      workFs: workFs,
      machineRoot: machineRoot,
      manifest: manifest,
    ).reconcile(tools: {cli.value}, workspaceId: workspaceId);
    step('reconcile done');

    // B4: skills/plugins link in-root + relay (long-blocking CLI).
    if (linkResources != null) {
      step('link-resources begin');
      await linkResources!(
        workFs: workFs,
        machineRoot: machineRoot,
        cli: cli,
        workspaceId: workspaceId,
      );
      step('link-resources done');
    }
    if (provisionRelay != null) {
      step('provision-relay begin');
      await provisionRelay!(
        workFs: workFs,
        machineRoot: machineRoot,
        cli: cli,
      );
      step('provision-relay done');
    }

    // B1: per-target opt-in credential push (off → no key leaves local).
    step('credentials begin optIn=$optInCredentials');
    final credentials = RemoteCredentialMaterializer(manifest: manifest);
    await credentials.materialize(
      cli: cli,
      workFs: workFs,
      machineRoot: machineRoot,
      localRoot: homeRoot,
      optIn: optInCredentials,
      localCredentials: optInCredentials
          ? await loadLocalCredentials(cli)
          : const [],
    );
    step('credentials done');
  }
}
