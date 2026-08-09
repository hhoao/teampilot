import '../../registry/capabilities/cli_config_ui_capability.dart';

final class OpencodeConfigUi implements CliConfigUiCapability {
  const OpencodeConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: null,
    subtitleKey: null,
    fieldKey: 'opencodeCliExecutablePathField',
    browseKey: 'opencodeCliExecutablePathBrowseButton',
    resetKey: 'opencodeCliExecutablePathResetButton',
    debouncerTag: 'opencode_cli_executable_path',
    installKey: 'opencodeCliInstallButton',
    showDividerBelow: true,
  );
}
