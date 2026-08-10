import '../../models/team_config.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import 'installer_types.dart';
import 'remote_cli_locator.dart';

/// Performs the actual install of [cli] on the work machine over its transport,
/// reporting progress. Returns the absolute remote executable path the install
/// step resolved (production: [CliInstallResult.executablePath]).
typedef RemoteInstallAction =
    Future<String> Function({
      required SshCommandRunner run,
      required void Function(CliInstallProgress progress) onProgress,
    });

enum RemoteCliUnavailableReason {
  /// CLI not found and connect/locate-only path will not install.
  notInstalled,
  optInOff,
  noInstaller,
  installFailed,
}

class RemoteCliUnavailableException implements Exception {
  RemoteCliUnavailableException(this.cli, this.reason);
  final CliTool cli;
  final RemoteCliUnavailableReason reason;

  @override
  String toString() => switch (reason) {
    RemoteCliUnavailableReason.notInstalled =>
      '${cli.value} is not installed on the remote host. Open Machines and '
          'install it, or set a manual CLI path for this target.',
    RemoteCliUnavailableReason.optInOff =>
      '${cli.value} not found on the remote host and auto-install is '
          'disabled for this target. Re-enable it or set a manual CLI path.',
    RemoteCliUnavailableReason.noInstaller =>
      '${cli.value} not found and has no installer; set a manual CLI path '
          'for this target.',
    RemoteCliUnavailableReason.installFailed =>
      '${cli.value} install finished but did not report an executable path '
          'on the remote host.',
  };
}

/// Locates and optionally installs [cli] on a remote work machine.
class RemoteCliInstaller {
  RemoteCliInstaller({RemoteCliLocator? locator})
    : _locator = locator ?? RemoteCliLocator();

  final RemoteCliLocator _locator;

  /// Locate only (manual override or remote probes). Never installs.
  Future<String?> locate({
    required CliTool cli,
    required SshCommandRunner run,
    String manualPathOverride = '',
  }) {
    return _locator.resolve(
      cli: cli,
      run: run,
      manualPathOverride: manualPathOverride,
    );
  }

  /// Locate → optional install. Used for **user-driven** Machines install only.
  Future<String> ensure({
    required CliTool cli,
    required SshCommandRunner run,
    required bool optIn,
    required bool supportsInstaller,
    RemoteInstallAction? install,
    void Function(CliInstallProgress progress)? onProgress,
    String manualPathOverride = '',
  }) async {
    appLogger.d(
      '[remote-cli] locate begin cli=${cli.value} '
      'manualOverride=${manualPathOverride.trim().isNotEmpty}',
    );
    final existing = await locate(
      cli: cli,
      run: run,
      manualPathOverride: manualPathOverride,
    );
    if (existing != null) {
      appLogger.d(
        '[remote-cli] locate hit cli=${cli.value} path=$existing',
      );
      return existing;
    }
    appLogger.d(
      '[remote-cli] locate miss cli=${cli.value} '
      'optIn=$optIn supportsInstaller=$supportsInstaller',
    );

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

    appLogger.d('[remote-cli] install begin cli=${cli.value}');
    final installedPath = (await install(
      run: run,
      onProgress: onProgress ?? (_) {},
    )).trim();
    if (installedPath.isNotEmpty) {
      appLogger.d(
        '[remote-cli] install done cli=${cli.value} path=$installedPath',
      );
      return installedPath;
    }
    throw RemoteCliUnavailableException(
      cli,
      RemoteCliUnavailableReason.installFailed,
    );
  }
}
