import '../../registry/capabilities/cli_config_ui_capability.dart';

final class CodexConfigUi implements CliConfigUiCapability {
  const CodexConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: null,
    subtitleKey: null,
    fieldKey: 'codex-cli-executable-path-field',
    browseKey: 'codex-cli-executable-path-browse-button',
    resetKey: 'codex-cli-executable-path-reset-button',
    debouncerTag: 'codex_cli_executable_path',
    installKey: 'codex-cli-install-button',
    showDividerBelow: true,
  );
}
