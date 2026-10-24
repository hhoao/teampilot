import '../../../../l10n/app_localizations.dart';
import '../../cli_tool_locator.dart';
import '../../installer_types.dart';
import '../installer/installer_context.dart';
import '../cli_capability.dart';

/// Result of a single remote command (over the target transport).
class SshCommandResult {
  const SshCommandResult({
    required this.exitCode,
    required this.stdout,
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs one command on the work machine over its transport (SSH exec). Injected
/// so remote locate/install is unit-testable without real SSH.
typedef SshCommandRunner = Future<SshCommandResult> Function(String command);

/// Metadata for one CLI's executable-path settings row in [CliConfigSection].
///
/// Replaces the 5 hardcoded [CliExecutablePathSettingsRow] blocks — each CLI
/// provides one const instance; the UI iterates and builds widgets from data.
final class CliExecutablePathRowSpec {
  const CliExecutablePathRowSpec({
    required this.titleKey,
    required this.subtitleKey,
    this.sshSubtitleKey,
    required this.fieldKey,
    required this.browseKey,
    required this.resetKey,
    required this.debouncerTag,
    required this.installKey,
    this.showDividerBelow = true,
    this.isCustomTitle = false,
  });

  /// Key into [AppLocalizations], or `null` for the default `cliExecutablePathLabelFor(...)`.
  final String? titleKey;

  /// Key for the deskop subtitle, or `null` for the default.
  final String? subtitleKey;

  /// Key for the SSH-mode subtitle, or `null` to fall back to [subtitleKey].
  final String? sshSubtitleKey;

  /// [AppKeys] debug key suffix for the text field.
  final String fieldKey;

  final String browseKey;
  final String resetKey;
  final String debouncerTag;
  final String installKey;
  final bool showDividerBelow;

  /// When `true`, the title comes directly from [cliDisplayName] rather than
  /// a specific localized label (used by claude).
  final bool isCustomTitle;
}

/// CLI identity & binary: display label, executable resolution, remote
/// location, in-app install, and the settings-page executable-path row.
///
/// One implementation per CLI tool, registered on the tool definition.
abstract interface class CliExecutableCapability implements CliCapability {
  /// Localized display label for the CLI (UI text, not the binary name).
  String label(AppLocalizations l10n);

  /// Binary name the CLI resolves to on PATH (e.g. `claude`, `cursor-agent`).
  String get defaultExecutableName;

  /// Preferences key under which a user-configured executable path is stored.
  String get preferencesPathKey;

  /// Locates the CLI's absolute path on a remote work machine over the
  /// injected [SshCommandRunner] (P3c, generalized across all 5 CLIs).
  Future<String?> locateRemote(SshCommandRunner run);

  /// Whether the app can install this CLI in-process (local and/or SSH).
  bool get supportsInstaller;

  /// Installs the CLI via the injected [CliInstallContext] facade.
  Future<CliInstallResult> install(CliInstallContext context);

  /// Settings-row metadata for the executable-path control.
  CliExecutablePathRowSpec get executablePathRowSpec;
}

/// Optional local locate override so a CLI can probe well-known install dirs
/// before PATH / `~/.local/bin`.
abstract interface class CliLocalExecutableLocator implements CliCapability {
  Future<String?> locateLocal({
    required ProcessRunner runner,
    bool includeShellFallback = true,
  });
}

/// Optional rewrite of the path TeamPilot will spawn, e.g. skip a leftover
/// installer when the official binary exists.
abstract interface class CliPreferredLaunchExecutable implements CliCapability {
  String? preferLaunchExecutable({
    required String userPath,
    required String? discoveredPath,
  });
}

/// Optional guard for a per-target remote path override.
///
/// `RemoteCliLocator` normally honours a manual override verbatim. When the
/// override is known to be a stale/incorrect binary (e.g. a leftover npm shim)
/// the CLI can reject it so remote discovery runs and its well-known probes
/// (official install dirs first) win — mirroring [CliPreferredLaunchExecutable]
/// on the local side.
abstract interface class CliRemoteOverrideGuard implements CliCapability {
  /// True to honour [overridePath]; false to ignore it and run discovery.
  bool acceptRemoteOverride(String overridePath);
}
