import '../../installer_types.dart';
import '../../registry/installer/installer_context.dart';
import '../../registry/installer/npm_installer_capability.dart';
import '../../registry/installer/teampilot_node_install.dart';
import '../../registry/installer/termux_remote_detect.dart';

/// In-app npm installer for Claude Code (`@anthropic-ai/claude-code`).
///
/// On Termux/Android, official `@latest` skips native binaries
/// (`process.platform === 'android'`) and leaves a stub that exits with
/// "native binary not installed". TeamPilot therefore installs a pinned
/// JS-era release and disables the in-process auto-updater.
///
/// Newer Claude on Termux needs a community glibc-runner install
/// (e.g. claude-code-android); that flow is interactive (~233 MB) and is
/// documented in [termuxCommunityInstallHint], not run unattended over SSH.
final class ClaudeInstallerCapability extends NpmInstallerCapability {
  const ClaudeInstallerCapability();

  /// Last upstream release that still provided a usable JS entry on Android.
  /// See anthropics/claude-code#50270.
  static const termuxPinnedPackage = '@anthropic-ai/claude-code@2.1.112';

  static const termuxCommunityInstallHint =
      'For a newer Claude on Termux, install via the community script in a '
      'Termux session: '
      'https://github.com/ferrumclaudepilgrim/claude-code-android';

  @override
  String get npmPackage => '@anthropic-ai/claude-code';

  @override
  String get executableName => 'claude';

  @override
  String get displayName => 'Claude Code';

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    if (context.mode == CliInstallMode.ssh) {
      final termux = await _installSshTermuxIfNeeded(context);
      if (termux != null) return termux;
    }
    return super.install(context);
  }

  /// Returns a result when the remote is Termux; otherwise `null`.
  Future<CliInstallResult?> _installSshTermuxIfNeeded(
    CliInstallContext context,
  ) async {
    final profile = context.sshProfile;
    if (profile == null) return null;

    final host = context.host;
    final probe = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(TermuxRemoteDetect.probeScript()),
    );
    if (!TermuxRemoteDetect.isTermuxFromProbeOutput(probe.stdout)) {
      return null;
    }

    host.report(CliInstallPhase.locatingExecutable);
    final existing = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(
        NpmInstallerCapability.remotePostInstallLocateScript(executableName),
      ),
    );
    final existingPath = firstInstallerOutputLine(existing);
    if (existingPath != null) {
      final smoke = await host.runSsh(
        profile,
        CliInstallerCommand.unixShellScript(
          '${TermuxRemoteDetect.exportPrefixPathShell}\n'
          '"$existingPath" --version >/dev/null 2>&1',
        ),
      );
      if (smoke.exitCode == 0) {
        return CliInstallResult(
          success: true,
          message:
              '$displayName already present on ${profile.hostIdentifier}.',
          executablePath: existingPath,
        );
      }
    }

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

    host.report(CliInstallPhase.installingCli, detail: displayName);
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(termuxPinnedInstallScript()),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Termux $displayName install failed',
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
            'located on ${profile.hostIdentifier}. $termuxCommunityInstallHint',
      );
    }

    final verify = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(
        '${TermuxRemoteDetect.exportPrefixPathShell}\n'
        '"$path" --version >/dev/null 2>&1',
      ),
    );
    if (verify.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message:
            'Installed $termuxPinnedPackage but `claude --version` failed. '
            '$termuxCommunityInstallHint',
        executablePath: path,
      );
    }

    return CliInstallResult(
      success: true,
      message:
          '$displayName $termuxPinnedPackage installed on '
          '${profile.hostIdentifier} (Termux-compatible pin). '
          '$termuxCommunityInstallHint',
      executablePath: path,
    );
  }

  /// Non-interactive Termux install: pin JS-era package + block auto-updater.
  static String termuxPinnedInstallScript() =>
      '''
set -e
${TermuxRemoteDetect.ensurePrefixAndFlagShell}
${TermuxRemoteDetect.exportPrefixPathShell}
export DISABLE_AUTOUPDATER=1
export PATH="\$HOME/.local/bin:\$PATH"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm not found; install nodejs first (pkg install nodejs)" >&2
  exit 5
fi

# Drop broken @latest stubs from prior TeamPilot / npm installs.
npm uninstall -g --prefix "\$HOME/.local" @anthropic-ai/claude-code >/dev/null 2>&1 || true
if [ -n "\${PREFIX:-}" ] && [ -d "\$PREFIX" ]; then
  npm uninstall -g --prefix "\$PREFIX" @anthropic-ai/claude-code >/dev/null 2>&1 || true
fi
rm -f "\$HOME/.local/bin/claude" 2>/dev/null || true

# Prefer Termux prefix so the binary is on the interactive Termux PATH.
if [ -n "\${PREFIX:-}" ] && [ -d "\$PREFIX" ]; then
  npm install -g --prefix "\$PREFIX" $termuxPinnedPackage
  CLAUDE_DIR="\$PREFIX/lib/node_modules/@anthropic-ai/claude-code"
else
  npm install -g --prefix "\$HOME/.local" $termuxPinnedPackage
  CLAUDE_DIR="\$HOME/.local/lib/node_modules/@anthropic-ai/claude-code"
fi

# Best-effort: stop in-process auto-updater from overwriting the pin.
if [ -d "\$CLAUDE_DIR" ]; then
  chmod -R a-w "\$CLAUDE_DIR" 2>/dev/null || true
fi

command -v claude
''';
}
