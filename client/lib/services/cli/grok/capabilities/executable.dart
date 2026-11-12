import 'dart:io';

import '../../../../l10n/app_localizations.dart';
import '../../cli_tool_locator.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';
import '../../registry/installer/npm_installer_capability.dart';
import '../../registry/installer/termux_remote_detect.dart';
import '../grok_bin.dart';
import '../grok_constants.dart';

/// Grok identity & binary, plus the official curl/PowerShell installer.
///
/// The official binary lives at `~/.grok/bin/grok`; Termux/Android is rejected
/// because the published build targets desktop glibc/musl Linux and macOS.
/// Use SSH from Android instead.
final class GrokExecutableCapability
    implements
        CliExecutableCapability,
        CliLocalExecutableLocator,
        CliPreferredLaunchExecutable {
  const GrokExecutableCapability();

  static const termuxUnsupportedMessage =
      'Grok CLI install is not supported on Termux (Android). '
      'Install a Termux-compatible build manually, then use Detect — or run '
      'Grok on an SSH host.';

  static String get unixInstallScript =>
      'curl -fsSL ${GrokConstants.installUrl} | bash';

  static String get _postInstallLocateScript => grokPostInstallLocateScript(
    fallbackScript: NpmInstallerCapability.remotePostInstallLocateScript(
      GrokConstants.executableName,
    ),
  );

  @override
  String label(AppLocalizations l10n) => l10n.appProvider.toolGrok;

  @override
  String get defaultExecutableName => GrokConstants.executableName;

  @override
  String get preferencesPathKey => GrokConstants.executableName;

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator(
        GrokConstants.executableName,
        extraWellKnownProbes: [grokOfficialRemoteBinProbe],
      ).locate(run);

  @override
  Future<String?> locateLocal({
    required ProcessRunner runner,
    bool includeShellFallback = true,
  }) async {
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim() ??
        '';
    final wellKnown = grokOfficialExecutablePath(
      homeDirectory: home,
      isWindows: Platform.isWindows,
    );
    if (wellKnown != null) {
      final probed = await _probeExistingPath(
        runner,
        wellKnown,
        isWindows: Platform.isWindows,
      );
      if (probed != null) return probed;
    }
    return CliToolLocator(
      GrokConstants.executableName,
    ).locate(runner: runner, includeShellFallback: includeShellFallback);
  }

  @override
  String? preferLaunchExecutable({
    required String userPath,
    required String? discoveredPath,
  }) {
    final user = userPath.trim();
    if (user.isNotEmpty) return user;
    final discovered = discoveredPath?.trim() ?? '';
    if (discovered.isNotEmpty) return discovered;
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim() ??
        '';
    final wellKnown = grokOfficialExecutablePath(
      homeDirectory: home,
      isWindows: Platform.isWindows,
    );
    if (wellKnown != null && File(wellKnown).existsSync()) return wellKnown;
    return null;
  }

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'grok-cli-executable-path-field',
        browseKey: 'grok-cli-executable-path-browse-button',
        resetKey: 'grok-cli-executable-path-reset-button',
        debouncerTag: 'grok_cli_executable_path',
        installKey: 'grok-cli-install-button',
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
            "irm '${GrokConstants.powershellInstallUrl}' | iex",
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
          '${GrokConstants.displayName} install failed',
          install,
        ),
      );
    }

    host.report(CliInstallPhase.locatingExecutable);
    final located = host.isWindows
        ? null
        : await host.runLocal(
            CliInstallerCommand.unixShellScript(_postInstallLocateScript),
            phase: CliInstallPhase.locatingExecutable,
          );
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim() ??
        '';
    final wellKnown = grokOfficialExecutablePath(
      homeDirectory: home,
      isWindows: Platform.isWindows,
    );
    final path =
        (located == null ? null : firstInstallerOutputLine(located)) ??
        (wellKnown != null && File(wellKnown).existsSync()
            ? wellKnown
            : null) ??
        await host.locateExecutable(GrokConstants.executableName);
    if (path == null) {
      return CliInstallResult(
        success: false,
        message:
            '${GrokConstants.displayName} install finished but the executable '
            'could not be located. Add ~/.grok/bin to PATH if needed.',
      );
    }
    return CliInstallResult(
      success: true,
      message: '${GrokConstants.displayName} installed.',
      executablePath: path,
    );
  }

  Future<CliInstallResult> _installSsh(CliInstallContext context) async {
    final profile = context.sshProfile;
    if (profile == null) {
      return CliInstallResult(
        success: false,
        message:
            'Select an SSH server before installing '
            '${GrokConstants.displayName} remotely.',
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
        CliInstallerCommand.unixShellScript(_postInstallLocateScript),
      );
      final path = firstInstallerOutputLine(existing);
      if (path != null) {
        return CliInstallResult(
          success: true,
          message:
              '${GrokConstants.displayName} already present on '
              '${profile.hostIdentifier}.',
          executablePath: path,
        );
      }
      return const CliInstallResult(
        success: false,
        message: termuxUnsupportedMessage,
      );
    }

    host.report(
      CliInstallPhase.installingCli,
      detail: GrokConstants.displayName,
    );
    final install = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(unixInstallScript),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage(
          'Remote ${GrokConstants.displayName} install failed',
          install,
        ),
      );
    }

    host.report(CliInstallPhase.locatingExecutable);
    final resolved = await host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(_postInstallLocateScript),
    );
    final path = firstInstallerOutputLine(resolved);
    if (path == null) {
      return CliInstallResult(
        success: false,
        message:
            '${GrokConstants.displayName} install finished but the executable '
            'could not be located on ${profile.hostIdentifier}.',
      );
    }
    return CliInstallResult(
      success: true,
      message:
          '${GrokConstants.displayName} installed on '
          '${profile.hostIdentifier}.',
      executablePath: path,
    );
  }

  static Future<String?> _probeExistingPath(
    ProcessRunner runner,
    String path, {
    required bool isWindows,
  }) async {
    if (isWindows) {
      // Windows tests never exercise this branch; keep the check cheap and
      // avoid spawning a shell for a path we were handed directly.
      return File(path).existsSync() ? path : null;
    }
    try {
      final quoted = path.replaceAll("'", r"'\''");
      final result = await runner('sh', [
        '-c',
        "test -x '$quoted' && printf '%s\n' '$quoted'",
      ]);
      if (result.exitCode != 0) return null;
      return CliToolLocator.parseFirstStdoutLine(result.stdout);
    } on Object {
      return null;
    }
  }
}
