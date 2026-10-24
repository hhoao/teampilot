import 'dart:io';

import '../../../../l10n/app_localizations.dart';
import '../../../../utils/logging/logger.dart';
import '../../cli_tool_locator.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';
import '../../registry/installer/npm_installer_capability.dart';
import '../../registry/installer/termux_remote_detect.dart';
import '../opencode_bin.dart';

/// OpenCode identity & binary, plus its in-app v2 curl installer.
///
/// Installs from https://opencode.ai/v2/install (native `opencode` binary).
/// Termux/Android is rejected up front — the official script targets
/// desktop glibc/musl Linux and macOS, not bionic.
final class OpencodeExecutableCapability
    implements
        CliExecutableCapability,
        CliLocalExecutableLocator,
        CliPreferredLaunchExecutable,
        CliRemoteOverrideGuard {
  const OpencodeExecutableCapability();

  static const installUrl = 'https://opencode.ai/v2/install';
  static const executableName = 'opencode';
  static const displayName = 'OpenCode';

  static const termuxUnsupportedMessage =
      'OpenCode v2 install is not supported on Termux (Android). '
      'Install opencode manually if you have a Termux-compatible build, '
      'then use Detect — or skip OpenCode on this device.';

  static String get unixInstallScript => 'curl -fsSL $installUrl | bash';

  static String get _postInstallLocateScript => opencodePostInstallLocateScript(
    fallbackScript: NpmInstallerCapability.remotePostInstallLocateScript(
      executableName,
    ),
  );

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolOpencode;

  @override
  String get defaultExecutableName => executableName;

  @override
  String get preferencesPathKey => 'opencode';

  @override
  Future<String?> locateRemote(SshCommandRunner run) async {
    final path = await const DefaultRemoteCliLocator(
      executableName,
      extraWellKnownProbes: [opencodeOfficialRemoteBinProbe],
    ).locate(run);
    final resolved = path?.trim() ?? '';
    if (resolved.isEmpty) return null;
    if (await _remoteIsPreV2(run, resolved)) {
      appLogger.w(
        '[opencode] remote $resolved is older than '
        'v$opencodeMinimumRemoteMajorVersion; TeamPilot writes v2 opencode.json '
        'so it is reported as not ready',
      );
      return null;
    }
    return resolved;
  }

  /// True when the remote binary at [path] answers `--version` with a major
  /// below [opencodeMinimumRemoteMajorVersion]. Unreadable banners fail open
  /// (keep the path) so a probe hiccup never hides an existing install.
  static Future<bool> _remoteIsPreV2(SshCommandRunner run, String path) async {
    try {
      final result = await run(opencodeRemoteVersionProbeCommand(path));
      if (result.exitCode != 0) return false;
      final major = opencodeMajorVersionFromBanner(result.stdout);
      if (major == null) return false;
      return major < opencodeMinimumRemoteMajorVersion;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> locateLocal({
    required ProcessRunner runner,
    bool includeShellFallback = true,
  }) async {
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim() ??
        '';
    final wellKnown = opencodeOfficialExecutablePath(
      homeDirectory: home,
      isWindows: Platform.isWindows,
    );
    if (wellKnown != null) {
      final probed = await _probeExistingPath(runner, wellKnown);
      if (probed != null) return probed;
    }
    return CliToolLocator(
      executableName,
    ).locate(runner: runner, includeShellFallback: includeShellFallback);
  }

  @override
  String? preferLaunchExecutable({
    required String userPath,
    required String? discoveredPath,
  }) {
    final home =
        Platform.environment['HOME']?.trim() ??
        Platform.environment['USERPROFILE']?.trim() ??
        '';
    final wellKnown = opencodeOfficialExecutablePath(
      homeDirectory: home,
      isWindows: Platform.isWindows,
    );
    final wellKnownExists = wellKnown != null && File(wellKnown).existsSync();
    return preferOpencodeLaunchExecutable(
      userPath: userPath,
      discoveredPath: discoveredPath,
      wellKnownPath: wellKnownExists ? wellKnown : null,
      isStaleInstall: (path) =>
          isStaleOpencodeNpmInstall(path, linkTarget: _linkTarget(path)),
    );
  }

  @override
  bool acceptRemoteOverride(String overridePath) =>
      !isStaleOpencodeNpmInstall(overridePath);

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
    final located = await host.runLocal(
      CliInstallerCommand.unixShellScript(_postInstallLocateScript),
      phase: CliInstallPhase.locatingExecutable,
    );
    final path =
        firstInstallerOutputLine(located) ??
        await host.locateExecutable(executableName);
    if (path == null) {
      return CliInstallResult(
        success: false,
        message:
            '$displayName install finished but the executable could not be '
            'located. Add ~/.opencode/bin to PATH if needed.',
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
        CliInstallerCommand.unixShellScript(_postInstallLocateScript),
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
      CliInstallerCommand.unixShellScript(_postInstallLocateScript),
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

  static Future<String?> _probeExistingPath(
    ProcessRunner runner,
    String path,
  ) async {
    try {
      final quoted = path.replaceAll("'", r"'\''");
      final result = await runner('sh', [
        '-c',
        'test -x \'$quoted\' && printf \'%s\\n\' \'$quoted\'',
      ]);
      if (result.exitCode != 0) return null;
      return CliToolLocator.parseFirstStdoutLine(result.stdout);
    } on Object {
      return null;
    }
  }

  static String? _linkTarget(String path) {
    try {
      if (FileSystemEntity.isLinkSync(path)) {
        return Link(path).targetSync();
      }
    } on Object {
      return null;
    }
    return null;
  }
}
