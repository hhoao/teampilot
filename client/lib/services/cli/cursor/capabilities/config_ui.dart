import '../../registry/capabilities/cli_config_ui_capability.dart';

final class CursorConfigUi implements CliConfigUiCapability {
  const CursorConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: null,
    subtitleKey: null,
    fieldKey: 'cursor-cli-executable-path-field',
    browseKey: 'cursor-cli-executable-path-browse-button',
    resetKey: 'cursor-cli-executable-path-reset-button',
    debouncerTag: 'cursor_cli_executable_path',
    installKey: 'cursor-cli-install-button',
    showDividerBelow: true,
  );
}
