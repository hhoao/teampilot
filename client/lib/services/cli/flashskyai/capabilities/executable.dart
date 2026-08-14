import '../../../../l10n/app_localizations.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/installer_context.dart';

/// Flashskyai identity & binary; no in-app installer.
final class FlashskyaiExecutableCapability implements CliExecutableCapability {
  const FlashskyaiExecutableCapability();

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolFlashskyai;

  @override
  String get defaultExecutableName => 'flashskyai';

  @override
  String get preferencesPathKey => 'flashskyai';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('flashskyai').locate(run);

  @override
  bool get supportsInstaller => false;

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    return const CliInstallResult(
      success: false,
      message: 'In-app installation is not supported for this CLI.',
    );
  }

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'cli-executable-path-field',
        browseKey: 'cli-executable-path-browse-button',
        resetKey: 'cli-executable-path-reset-button',
        debouncerTag: 'flashskyai_cli_executable_path',
        installKey: 'cli-install-flashskyai-button',
        showDividerBelow: false,
      );
}
