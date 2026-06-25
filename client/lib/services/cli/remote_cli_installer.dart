import '../../models/team_config.dart';
import 'remote_cli_locator.dart';

/// Performs the actual install of [cli] on the work machine over its transport,
/// reporting progress. Injected so the orchestration is unit-testable without
/// real SSH (production binds it to `InstallerCapability.install` over a
/// target-bound `HostScriptRunner`).
typedef RemoteInstallAction = Future<void> Function({
  required SshCommandRunner run,
  required void Function(String message) onProgress,
});

enum RemoteCliUnavailableReason { optInOff, noInstaller, installFailed }

class RemoteCliUnavailableException implements Exception {
  RemoteCliUnavailableException(this.cli, this.reason);
  final CliTool cli;
  final RemoteCliUnavailableReason reason;

  @override
  String toString() => switch (reason) {
        RemoteCliUnavailableReason.optInOff =>
          '${cli.value} not found on the remote host and auto-install is '
              'disabled for this target. Re-enable it or set a manual CLI path.',
        RemoteCliUnavailableReason.noInstaller =>
          '${cli.value} not found and has no installer; set a manual CLI path '
              'for this target.',
        RemoteCliUnavailableReason.installFailed =>
          '${cli.value} install completed but the CLI still could not be located '
              'on the remote host.',
      };
}

/// Ensures [cli] is present on the work machine (P3c §3.2): locate → (opt-in)
/// install → re-locate. Returns the absolute remote path or throws a clear
/// [RemoteCliUnavailableException].
class RemoteCliInstaller {
  RemoteCliInstaller({RemoteCliLocator? locator})
      : _locator = locator ?? RemoteCliLocator();

  final RemoteCliLocator _locator;

  Future<String> ensure({
    required CliTool cli,
    required SshCommandRunner run,
    required bool optIn,
    required bool supportsInstaller,
    RemoteInstallAction? install,
    void Function(String message)? onProgress,
    String manualPathOverride = '',
  }) async {
    final existing = await _locator.resolve(
      cli: cli,
      run: run,
      manualPathOverride: manualPathOverride,
    );
    if (existing != null) return existing;

    if (!optIn) {
      throw RemoteCliUnavailableException(
        cli,
        RemoteCliUnavailableReason.optInOff,
      );
    }
    if (!supportsInstaller || install == null) {
      throw RemoteCliUnavailableException(
        cli,
        RemoteCliUnavailableReason.noInstaller,
      );
    }

    await install(run: run, onProgress: onProgress ?? (_) {});

    final located = await _locator.resolve(cli: cli, run: run);
    if (located != null) return located;
    throw RemoteCliUnavailableException(
      cli,
      RemoteCliUnavailableReason.installFailed,
    );
  }
}
