import '../../../../models/ssh_profile.dart';
import '../../installer_types.dart';
import '../capabilities/installer_capability.dart';
import 'installer_context.dart';
import 'teampilot_node_install.dart';

/// In-app npm installer for Claude Code (`@anthropic-ai/claude-code`).
final class ClaudeInstallerCapability implements InstallerCapability {
  const ClaudeInstallerCapability();

  static const npmPackage = '@anthropic-ai/claude-code';
  static const executableName = 'claude';

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
    final node = context.node;

    host.report(CliInstallPhase.checkingNpm);
    final npmResolution = await node.resolveLocalNpm(host);
    if (npmResolution case LocalNpmBootstrapFailed(:final result)) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Local Node/npm install failed',
          result,
        ),
      );
    }

    final CliInstallerCommand installCommand = switch (npmResolution) {
      LocalNpmFound(:final npmPath) => node.existingNpmPackageInstall(
        isWindows: host.isWindows,
        npmPath: npmPath,
        package: npmPackage,
      ),
      LocalNpmBootstrapped() => node.bootstrappedLocalPackageInstall(
        runner: host.scriptRunner,
        package: npmPackage,
      ),
      LocalNpmBootstrapFailed() => throw StateError('handled above'),
    };

    final install = await host.runLocal(
      installCommand,
      phase: CliInstallPhase.installingClaude,
      streamOutput: true,
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage('Claude Code install failed', install),
      );
    }

    host.report(CliInstallPhase.locatingExecutable);
    final path = await host.locateExecutable(executableName);
    return CliInstallResult(
      success: true,
      message: 'Claude Code installed.',
      executablePath: path,
    );
  }

  Future<CliInstallResult> _installSsh(CliInstallContext context) async {
    final profile = context.sshProfile;
    if (profile == null) {
      return const CliInstallResult(
        success: false,
        message: 'Select an SSH server before installing Claude Code remotely.',
      );
    }

    final host = context.host;
    final node = context.node;

    host.report(CliInstallPhase.checkingNpm);
    final npmResolution = await node.resolveRemoteNpm(host, profile);
    if (npmResolution case RemoteNpmBootstrapFailed(:final result)) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Remote Node/npm install failed',
          result,
        ),
      );
    }

    final npmCommand = switch (npmResolution) {
      RemoteNpmFound(:final npmCommand) => npmCommand,
      RemoteNpmBootstrapFailed() => throw StateError('handled above'),
    };

    host.report(CliInstallPhase.installingClaude);
    final install = await host.runSsh(
      profile,
      node.remotePackageInstall(npmCommand: npmCommand, package: npmPackage),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Remote Claude Code install failed',
          install,
        ),
      );
    }

    host.report(CliInstallPhase.locatingExecutable);
    final resolved = await host.runSsh(
      profile,
      CliInstallerCommand('command', ['-v', executableName]),
    );
    final path = firstInstallerOutputLine(resolved);
    return CliInstallResult(
      success: true,
      message: 'Claude Code installed on ${profile.hostIdentifier}.',
      executablePath: path,
    );
  }
}
