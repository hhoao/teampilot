import '../../registry/capabilities/cli_config_ui_capability.dart';

final class CursorConfigUi implements CliConfigUiCapability {
  const CursorConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: null,
    subtitleKey: null,
    fieldKey: 'cursorCliExecutablePathField',
    browseKey: 'cursorCliExecutablePathBrowseButton',
    resetKey: 'cursorCliExecutablePathResetButton',
    debouncerTag: 'cursor_cli_executable_path',
    installKey: 'cursorCliInstallButton',
    showDividerBelow: true,
  );
}
