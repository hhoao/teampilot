import '../../registry/capabilities/cli_config_ui_capability.dart';

final class ClaudeConfigUi implements CliConfigUiCapability {
  const ClaudeConfigUi();

  @override
  CliExecutablePathRowSpec get executablePathRowSpec => const CliExecutablePathRowSpec(
    titleKey: 'claudeCliExecutablePathLabel',
    subtitleKey: 'claudeCliExecutablePathDescription',
    sshSubtitleKey: 'claudeCliExecutablePathDescriptionSsh',
    fieldKey: 'claudeCliExecutablePathField',
    browseKey: 'claudeCliExecutablePathBrowseButton',
    resetKey: 'claudeCliExecutablePathResetButton',
    debouncerTag: 'claude_cli_executable_path',
    installKey: 'claudeCliInstallButton',
    showDividerBelow: true,
    isCustomTitle: true,
  );
}
