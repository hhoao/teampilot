import '../../registry/capabilities/cli_config_ui_capability.dart';

final class OpencodeConfigUi implements CliConfigUiCapability {
  const OpencodeConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
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
