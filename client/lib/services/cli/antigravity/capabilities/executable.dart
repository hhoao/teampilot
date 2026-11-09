import '../../../../l10n/app_localizations.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';

final class AntigravityExecutableCapability implements CliExecutableCapability {
  const AntigravityExecutableCapability();

  @override
  String get defaultExecutableName => 'agy';

  @override
  String get preferencesPathKey => 'cli.antigravity.path';

  @override
  String label(AppLocalizations l10n) => l10n.appProvider.toolAntigravity;

  @override
  bool get supportsInstaller => true;

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('agy').locate(run);

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    if (context.mode == CliInstallMode.ssh) {
      return _installSsh(context);
    }
    context.host.report(CliInstallPhase.installingCli);
    final script = context.host.isWindows
        ? 'irm https://antigravity.google/cli/install.ps1 | iex'
        : 'curl -fsSL https://antigravity.google/cli/install.sh | bash';
    final result = await context.host.runLocal(
      context.host.isWindows
          ? CliInstallerCommand('powershell', [
              '-NoProfile',
              '-Command',
              script,
            ])
          : CliInstallerCommand.unixShellScript(script),
      phase: CliInstallPhase.installingCli,
      streamOutput: true,
    );
    if (result.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Antigravity CLI install failed',
          result,
        ),
      );
    }
    final path = await context.host.locateExecutable('agy');
    return CliInstallResult(
      success: path != null,
      message: path == null
          ? 'agy installed but was not found on PATH.'
          : 'Antigravity CLI installed.',
      executablePath: path,
    );
  }

  Future<CliInstallResult> _installSsh(CliInstallContext context) async {
    final profile = context.sshProfile;
    if (profile == null) {
      return const CliInstallResult(
        success: false,
        message: 'Select an SSH server before installing Antigravity remotely.',
      );
    }
    context.host.report(
      CliInstallPhase.installingCli,
      detail: 'Antigravity CLI',
    );
    final install = await context.host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(
        'curl -fsSL https://antigravity.google/cli/install.sh | bash',
      ),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Remote Antigravity CLI install failed',
          install,
        ),
      );
    }
    context.host.report(CliInstallPhase.locatingExecutable);
    final path = await const DefaultRemoteCliLocator('agy').locate((
      command,
    ) async {
      final result = await context.host.runSsh(
        profile,
        CliInstallerCommand.unixShellScript(command),
      );
      return SshCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    });
    return CliInstallResult(
      success: path != null,
      message: path == null
          ? 'agy installed but was not found on the remote PATH.'
          : 'Antigravity CLI installed.',
      executablePath: path,
    );
  }

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'antigravity-cli-executable-path-field',
        browseKey: 'antigravity-cli-executable-path-browse-button',
        resetKey: 'antigravity-cli-executable-path-reset-button',
        debouncerTag: 'antigravity_cli_executable_path',
        installKey: 'antigravity-cli-install-button',
      );
}
