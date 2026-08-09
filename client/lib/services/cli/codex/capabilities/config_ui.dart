import '../../registry/capabilities/cli_config_ui_capability.dart';

final class CodexConfigUi implements CliConfigUiCapability {
  const CodexConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: null,
    subtitleKey: null,
    fieldKey: 'codexCliExecutablePathField',
    browseKey: 'codexCliExecutablePathBrowseButton',
    resetKey: 'codexCliExecutablePathResetButton',
    debouncerTag: 'codex_cli_executable_path',
    installKey: 'codexCliInstallButton',
    showDividerBelow: true,
  );
}
