import '../../installer_types.dart';
import '../capabilities/installer_capability.dart';
import 'installer_context.dart';
import 'teampilot_node_install.dart';

/// Shared in-app npm installer for Node-based CLIs (local + SSH).
///
/// Subclasses only supply the npm [npmPackage], the resulting [executableName],
/// and a human-readable [displayName]; the local/remote Node bootstrap, install,
/// and executable resolution flow is identical across tools.
abstract class NpmInstallerCapability implements InstallerCapability {
  const NpmInstallerCapability();

  /// Global npm package to install (e.g. `@anthropic-ai/claude-code`).
  String get npmPackage;

  /// Executable name to locate after install (e.g. `claude`).
  String get executableName;

  /// Tool name for progress detail and result messages (e.g. `Claude Code`).
  String get displayName;

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

    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.npmGlobalInstall(
        npmCommand: npmCommand,
        package: npmPackage,
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
        _remotePostInstallLocateScript(executableName),
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

  /// Mirrors [DefaultRemoteCliLocator] probes in one remote shell script.
  static String _remotePostInstallLocateScript(String executableName) => '''
if command -v $executableName >/dev/null 2>&1; then
  command -v $executableName
  exit 0
fi
for s in bash zsh; do
  for f in -ilc -lc; do
    p=\$(\$s \$f 'command -v $executableName' 2>/dev/null) || true
    if [ -n "\$p" ]; then
      printf '%s\\n' "\$p"
      exit 0
    fi
  done
done
if [ -x "\$HOME/.local/bin/$executableName" ]; then
  printf '%s\\n' "\$HOME/.local/bin/$executableName"
  exit 0
fi
exit 1
''';
}
