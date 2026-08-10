import '../cli_capability.dart';

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

/// Declares UI configuration for the CLI settings section.
abstract interface class CliConfigUiCapability implements CliCapability {
  /// Settings-row metadata for the executable-path control.
  CliExecutablePathRowSpec get executablePathRowSpec;
}
