import 'dart:io' show Platform;

import '../../../../l10n/app_localizations.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// Qoder CLI CN (`qoderclicn`) identity and installer.
///
/// The CN distribution uses the official `https://qoder.com.cn/install`
/// script (which redirects to `static.qoder.com.cn`). It is not published on
/// npm, so the global npm installer does not apply.
final class QoderCnExecutableCapability implements CliExecutableCapability {
  const QoderCnExecutableCapability();

  static const executableName = 'qoderclicn';
  static const displayName = 'Qoder CLI CN';
  static const installScript =
      'curl -fsSL https://qoder.com.cn/install | bash';

  @override
  String label(AppLocalizations l10n) => l10n.appProvider.toolQoderCn;

  @override
  String get defaultExecutableName => executableName;

  @override
  String get preferencesPathKey => 'qoder-cn';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator(executableName).locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'qoder-cn-cli-executable-path-field',
        browseKey: 'qoder-cn-cli-executable-path-browse-button',
        resetKey: 'qoder-cn-cli-executable-path-reset-button',
        debouncerTag: 'qoder_cn_cli_executable_path',
        installKey: 'qoder-cn-cli-install-button',
        showDividerBelow: true,
      );

  @override
  bool get supportsInstaller => !Platform.isWindows;

  @override
  Future<CliInstallResult> install(CliInstallContext context) {
    if (Platform.isWindows) {
      return Future.value(
        const CliInstallResult(
          success: false,
          message:
              'Qoder CLI CN has no supported in-app installer on Windows. '
              'Install qoderclicn manually, then set its path here.',
        ),
      );
    }
    return switch (context.mode) {
      CliInstallMode.local => _installLocal(context),
      CliInstallMode.ssh => _installSsh(context),
    };
  }

  Future<CliInstallResult> _installLocal(CliInstallContext context) async {
    final host = context.host;
    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runLocal(
      CliInstallerCommand.unixShellScript(installScript),
      phase: CliInstallPhase.installingCli,
      streamOutput: true,
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage('$displayName install failed', install),
      );
    }
    if (host.isCancelled) return _cancelled();
    host.report(CliInstallPhase.locatingExecutable);
    final path = await host.locateExecutable(executableName);
    if (path == null) {
      return const CliInstallResult(
        success: false,
        message:
            'Qoder CLI CN install finished but qoderclicn could not be '
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
      return const CliInstallResult(
        success: false,
        message: 'Select an SSH server before installing Qoder CLI CN remotely.',
      );
    }
    final host = context.host;
    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(installScript),
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
    if (host.isCancelled) return _cancelled();
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
            '$displayName install finished but qoderclicn could not be '
            'located on ${profile.hostIdentifier}.',
      );
    }
    return CliInstallResult(
      success: true,
      message: '$displayName installed on ${profile.hostIdentifier}.',
      executablePath: path,
    );
  }

  static CliInstallResult _cancelled() =>
      const CliInstallResult(success: false, message: 'Cancelled');
}
