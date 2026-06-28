import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../cli/cli_installer_service.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/registry/capabilities/remote_cli_locator_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../host/host_execution_environment.dart';

/// Runs the full remote CLI install path (npm locate → Node bootstrap →
/// `npm install -g`) over an existing [SshCommandRunner] during P3c preflight.
///
/// Reuses [CliInstallerService] with an injected [SshCliInstallRunner] so the
/// install shares the preflight SSH session instead of opening a second client.
RemoteInstallAction buildRemotePreflightCliInstall({
  required CliToolRegistry registry,
  required SshProfile profile,
  required CliTool cli,
}) {
  return ({required run, required onProgress}) async {
    final installer = CliInstallerService(
      cliToolRegistry: registry,
      hostEnvironment: HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        forceRemoteUnix: true,
      ),
      sshRunner: preflightSshInstallRunner(profile, run),
      sshClientFactory: null,
    );
    final result = await installer.install(
      cli: cli,
      mode: CliInstallMode.ssh,
      sshProfile: profile,
      onProgress: (progress) => onProgress(_progressLabel(progress)),
    );
    if (!result.success) {
      throw StateError(result.message);
    }
    final path = result.executablePath?.trim() ?? '';
    if (path.isEmpty) {
      throw StateError(
        '${cli.value} install finished but did not report an executable path.',
      );
    }
    return path;
  };
}

String _progressLabel(CliInstallProgress progress) {
  final detail = progress.detail?.trim();
  return switch (progress.phase) {
    CliInstallPhase.checkingNpm => 'Checking remote npm',
    CliInstallPhase.bootstrappingNode =>
      'Bootstrapping Node.js on remote host',
    CliInstallPhase.installingCli => detail == null || detail.isEmpty
        ? 'Installing CLI on remote host'
        : 'Installing $detail',
    CliInstallPhase.locatingExecutable => 'Locating remote CLI',
  };
}

/// Adapts preflight's [SshCommandRunner] to [CliInstallerService]'s SSH runner.
/// Transport edge: always send [CliInstallerCommand.commandLine].
SshCliInstallRunner preflightSshInstallRunner(
  SshProfile profile,
  SshCommandRunner run,
) {
  return (SshProfile sshProfile, CliInstallerCommand command) async {
    if (sshProfile.id != profile.id) {
      throw StateError('SSH profile mismatch during remote preflight install');
    }
    final result = await run(command.commandLine);
    return CliInstallerCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
    );
  };
}
