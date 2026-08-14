import '../../../../l10n/app_localizations.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// Codex identity & binary, plus its in-app npm installer (`@openai/codex`).
final class CodexExecutableCapability extends NpmInstallerCapability
    implements CliExecutableCapability {
  const CodexExecutableCapability();

  @override
  String get npmPackage => '@openai/codex';

  @override
  String get executableName => 'codex';

  @override
  String get displayName => 'Codex';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolCodex;

  @override
  String get defaultExecutableName => 'codex';

  @override
  String get preferencesPathKey => 'codex';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('codex').locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'codex-cli-executable-path-field',
        browseKey: 'codex-cli-executable-path-browse-button',
        resetKey: 'codex-cli-executable-path-reset-button',
        debouncerTag: 'codex_cli_executable_path',
        installKey: 'codex-cli-install-button',
        showDividerBelow: true,
      );
}
