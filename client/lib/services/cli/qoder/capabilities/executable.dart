import '../../../../l10n/app_localizations.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// Qoder CLI identity and npm installer (`@qoder-ai/qodercli`).
final class QoderExecutableCapability extends NpmInstallerCapability
    implements CliExecutableCapability {
  const QoderExecutableCapability();

  static const packageName = '@qoder-ai/qodercli';

  @override
  String get npmPackage => packageName;

  @override
  String get executableName => 'qodercli';

  @override
  String get displayName => 'Qoder CLI';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolQoder;

  @override
  String get defaultExecutableName => 'qodercli';

  @override
  String get preferencesPathKey => 'qoder';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('qodercli').locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'qoder-cli-executable-path-field',
        browseKey: 'qoder-cli-executable-path-browse-button',
        resetKey: 'qoder-cli-executable-path-reset-button',
        debouncerTag: 'qoder_cli_executable_path',
        installKey: 'qoder-cli-install-button',
        showDividerBelow: true,
      );
}
