import '../../../../l10n/app_localizations.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// CodeBuddy Code identity & binary, plus its in-app npm installer
/// (`@tencent-ai/codebuddy-code`). `cbc` is the same binary alias.
final class CodebuddyExecutableCapability extends NpmInstallerCapability
    implements CliExecutableCapability {
  const CodebuddyExecutableCapability();

  static const packageName = '@tencent-ai/codebuddy-code';

  @override
  String get npmPackage => packageName;

  @override
  String get executableName => 'codebuddy';

  @override
  String get displayName => 'CodeBuddy Code';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolCodebuddy;

  @override
  String get defaultExecutableName => 'codebuddy';

  @override
  String get preferencesPathKey => 'codebuddy';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('codebuddy').locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'codebuddy-cli-executable-path-field',
        browseKey: 'codebuddy-cli-executable-path-browse-button',
        resetKey: 'codebuddy-cli-executable-path-reset-button',
        debouncerTag: 'codebuddy_cli_executable_path',
        installKey: 'codebuddy-cli-install-button',
        showDividerBelow: true,
      );
}
