import '../../registry/capabilities/cli_config_ui_capability.dart';

final class FlashskyaiConfigUi implements CliConfigUiCapability {
  const FlashskyaiConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
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
