import '../../registry/capabilities/cli_config_ui_capability.dart';

final class ClaudeConfigUi implements CliConfigUiCapability {
  const ClaudeConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: 'claudeCliExecutablePathLabel',
    subtitleKey: 'claudeCliExecutablePathDescription',
    sshSubtitleKey: 'claudeCliExecutablePathDescriptionSsh',
    fieldKey: 'claude-cli-executable-path-field',
    browseKey: 'claude-cli-executable-path-browse-button',
    resetKey: 'claude-cli-executable-path-reset-button',
    debouncerTag: 'claude_cli_executable_path',
    installKey: 'claude-cli-install-button',
    showDividerBelow: true,
    isCustomTitle: true,
  );
}
