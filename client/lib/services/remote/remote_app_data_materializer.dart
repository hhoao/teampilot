import '../../models/team_config.dart';
import '../io/filesystem.dart';
import 'materialization_manifest.dart';
import 'remote_credential_materializer.dart';
import 'work_machine_materializer.dart';

/// Loads the locally-generated credential files for [cli] (per-CLI credential
/// services produce them locally). Injected so the work-machine materialize is
/// unit-testable without touching real credential stores.
typedef LocalCredentialsLoader = Future<List<CredentialFile>> Function(
    CliTool cli);

/// Links a CLI's team skills/plugins on the work machine (over its [workFs]).
/// Injected; the real linkers are fs-injected services (run on-device against
/// SFTP). [B4]
typedef RemoteResourceLinker = Future<void> Function({
  required Filesystem workFs,
  required String machineRoot,
  required CliTool cli,
  required String workspaceId,
});

/// Materializes the relay (P3b) onto the work machine for a long-blocking CLI.
/// Injected; real impl runs `RelayProvisioner` over the work transport. [B4]
typedef RemoteRelayProvisioner = Future<void> Function({
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
  });

  final LocalCredentialsLoader loadLocalCredentials;
  final RemoteResourceLinker? linkResources;
  final RemoteRelayProvisioner? provisionRelay;

  Future<void> materialize({
    required Filesystem homeFs,
    required String homeRoot,
    required Filesystem workFs,
    required String machineRoot,
    required CliTool cli,
    required String workspaceId,
    required bool optInCredentials,
  }) async {
    final manifest =
        MaterializationManifest(fs: workFs, machineRoot: machineRoot);

    await WorkMachineMaterializer(
      homeFs: homeFs,
      homeRoot: homeRoot,
      workFs: workFs,
      machineRoot: machineRoot,
      manifest: manifest,
    ).reconcile(tools: {cli.value}, workspaceId: workspaceId);

    // B4: skills/plugins link in-root + relay (long-blocking CLI).
    await linkResources?.call(
      workFs: workFs,
      machineRoot: machineRoot,
      cli: cli,
      workspaceId: workspaceId,
    );
    await provisionRelay?.call(
      workFs: workFs,
      machineRoot: machineRoot,
      cli: cli,
    );

    // B1: per-target opt-in credential push (off → no key leaves local).
    final credentials = RemoteCredentialMaterializer(manifest: manifest);
    await credentials.materialize(
      cli: cli,
      workFs: workFs,
      machineRoot: machineRoot,
      localRoot: homeRoot,
      optIn: optInCredentials,
      localCredentials:
          optInCredentials ? await loadLocalCredentials(cli) : const [],
    );
  }
}
