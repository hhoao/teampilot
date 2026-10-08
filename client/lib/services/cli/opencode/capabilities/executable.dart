import '../../../../l10n/app_localizations.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';
import '../../registry/installer/npm_installer_capability.dart';
import '../../registry/installer/termux_remote_detect.dart';

/// OpenCode identity & binary, plus its in-app v2 curl installer.
///
/// Installs from https://opencode.ai/v2/install (native `opencode` binary).
/// Termux/Android is rejected up front — the official script targets
/// desktop glibc/musl Linux and macOS, not bionic.
final class OpencodeExecutableCapability implements CliExecutableCapability {
  const OpencodeExecutableCapability();

  static const installUrl = 'https://opencode.ai/v2/install';
  static const executableName = 'opencode';
  static const displayName = 'OpenCode';

  static const termuxUnsupportedMessage =
      'OpenCode v2 install is not supported on Termux (Android). '
      'Install opencode manually if you have a Termux-compatible build, '
      'then use Detect — or skip OpenCode on this device.';

  static String get unixInstallScript => 'curl -fsSL $installUrl | bash';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolOpencode;

  @override
  String get defaultExecutableName => executableName;

  @override
  String get preferencesPathKey => 'opencode';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator(executableName).locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'opencode-cli-executable-path-field',
        browseKey: 'opencode-cli-executable-path-browse-button',
        resetKey: 'opencode-cli-executable-path-reset-button',
        debouncerTag: 'opencode_cli_executable_path',
        installKey: 'opencode-cli-install-button',
        showDividerBelow: true,
      );

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
            "curl.exe -fsSL '$installUrl' | bash",
          ])
        : CliInstallerCommand.unixShellScript(unixInstallScript);

    final install = await host.runLocal(
      installCommand,
      phase: CliInstallPhase.installingCli,
      streamOutput: true,
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          '$displayName install failed',
          install,
        ),
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

    final probe = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(TermuxRemoteDetect.probeScript()),
    );
    if (TermuxRemoteDetect.isTermuxFromProbeOutput(probe.stdout)) {
      host.report(CliInstallPhase.locatingExecutable);
      final existing = await host.runSsh(
        profile,
        CliInstallerCommand.unixShellScript(
          NpmInstallerCapability.remotePostInstallLocateScript(executableName),
        ),
      );
      final path = firstInstallerOutputLine(existing);
      if (path != null) {
        return CliInstallResult(
          success: true,
          message: '$displayName already present on ${profile.hostIdentifier}.',
          executablePath: path,
        );
      }
      return const CliInstallResult(
        success: false,
        message: termuxUnsupportedMessage,
      );
    }

    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(unixInstallScript),
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
