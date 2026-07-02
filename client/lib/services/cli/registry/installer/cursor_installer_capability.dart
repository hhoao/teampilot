import '../../installer_types.dart';
import '../capabilities/installer_capability.dart';
import 'installer_context.dart';
import 'npm_installer_capability.dart';

/// In-app installer for Cursor CLI (`cursor-agent`).
///
/// Uses the official install scripts from
/// https://cursor.com/docs/cli/installation (curl|bash on Unix, PowerShell on
/// Windows native).
final class CursorInstallerCapability implements InstallerCapability {
  const CursorInstallerCapability();

  static const installUrl = 'https://cursor.com/install';
  static const winInstallUrl = 'https://cursor.com/install?win32=true';
  static const executableName = 'cursor-agent';
  static const displayName = 'Cursor CLI';

  @override
  bool get supportsInstaller => true;

  @override
  Future<CliInstallResult> install(CliInstallContext context) {
    return switch (context.mode) {
      CliInstallMode.local => _installLocal(context),
      CliInstallMode.ssh => _installSsh(context),
    };
  }

  Future<CliInstallResult> _installLocal(CliInstallContext context) async {
    final host = context.host;
    final installCommand = host.isWindows
        ? CliInstallerCommand('powershell', [
            '-NoProfile',
            '-Command',
            "irm '$winInstallUrl' | iex",
          ])
        : CliInstallerCommand.unixShellScript(
            'curl $installUrl -fsS | bash',
          );

    final install = await host.runLocal(
      installCommand,
      phase: CliInstallPhase.installingCli,
      streamOutput: true,
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage('$displayName install failed', install),
      );
    }

    host.report(CliInstallPhase.locatingExecutable);
    final path = await host.locateExecutable(executableName);
    if (path == null) {
      return CliInstallResult(
        success: false,
        message:
            '$displayName install finished but the executable could not be '
            'located. Add ~/.local/bin to PATH if needed.',
      );
    }
    return CliInstallResult(
      success: true,
      message: '$displayName installed.',
      executablePath: path,
    );
  }

  Future<CliInstallResult> _installSsh(CliInstallContext context) async {
    final profile = context.sshProfile;
    if (profile == null) {
      return CliInstallResult(
        success: false,
        message:
            'Select an SSH server before installing $displayName remotely.',
      );
    }

    final host = context.host;
    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(
        'curl $installUrl -fsS | bash',
      ),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Remote $displayName install failed',
          install,
        ),
      );
    }

    host.report(CliInstallPhase.locatingExecutable);
    final resolved = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(
        NpmInstallerCapability.remotePostInstallLocateScript(executableName),
      ),
    );
    final path = firstInstallerOutputLine(resolved);
    if (path == null) {
      return CliInstallResult(
        success: false,
        message:
            '$displayName install finished but the executable could not be '
            'located on ${profile.hostIdentifier}.',
      );
    }
    return CliInstallResult(
      success: true,
      message: '$displayName installed on ${profile.hostIdentifier}.',
      executablePath: path,
    );
  }
}
