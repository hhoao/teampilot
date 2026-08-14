import '../../../../l10n/app_localizations.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// OpenCode identity & binary, plus its in-app npm installer (`opencode-ai`).
final class OpencodeExecutableCapability extends NpmInstallerCapability
    implements CliExecutableCapability {
  const OpencodeExecutableCapability();

  @override
  String get npmPackage => 'opencode-ai';

  @override
  String get executableName => 'opencode';

  @override
  String get displayName => 'OpenCode';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolOpencode;

  @override
  String get defaultExecutableName => 'opencode';

  @override
  String get preferencesPathKey => 'opencode';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('opencode').locate(run);

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
}
