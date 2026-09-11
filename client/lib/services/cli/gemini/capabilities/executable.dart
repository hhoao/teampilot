import '../../../../l10n/app_localizations.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// Gemini identity & binary, plus its in-app npm installer
/// (`@google/gemini-cli`).
final class GeminiExecutableCapability extends NpmInstallerCapability
    implements CliExecutableCapability {
  const GeminiExecutableCapability();

  @override
  String get npmPackage => '@google/gemini-cli';

  @override
  String get executableName => 'gemini';

  @override
  String get displayName => 'Gemini CLI';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolGemini;

  @override
  String get defaultExecutableName => 'gemini';

  @override
  String get preferencesPathKey => 'gemini';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('gemini').locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'gemini-cli-executable-path-field',
        browseKey: 'gemini-cli-executable-path-browse-button',
        resetKey: 'gemini-cli-executable-path-reset-button',
        debouncerTag: 'gemini_cli_executable_path',
        installKey: 'gemini-cli-install-button',
        showDividerBelow: true,
      );
}
