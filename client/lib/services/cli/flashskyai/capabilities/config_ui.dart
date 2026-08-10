import '../../registry/capabilities/cli_config_ui_capability.dart';

final class FlashskyaiConfigUi implements CliConfigUiCapability {
  const FlashskyaiConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: null,
    subtitleKey: null,
    fieldKey: 'cliExecutablePathField',
    browseKey: 'cliExecutablePathBrowseButton',
    resetKey: 'cliExecutablePathResetButton',
    debouncerTag: 'flashskyai_cli_executable_path',
    installKey: 'cliInstallFlashskyaiButton',
    showDividerBelow: false,
  );
}
