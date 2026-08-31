import 'package:flutter/widgets.dart';

import '../../models/team_config.dart';

class AppKeys {
  const AppKeys._();

  /// Path field finder key for [cli] (`{value}-cli-executable-path-field`).
  static Key cliExecutablePathFieldFor(CliTool cli) =>
      Key('${cli.value}-cli-executable-path-field');

  /// Install button finder key for [cli] (`{value}-cli-install-button`).
  static Key cliInstallButtonFor(CliTool cli) =>
      Key('${cli.value}-cli-install-button');

  static const sectionBarChatChip = Key('section-bar-chat-chip');
  static const sectionBarRunsChip = Key('section-bar-runs-chip');
  static const contextSidebar = Key('context-sidebar');
  static const workspaceTopbar = Key('workspace-topbar');
  static const chatWorkspace = Key('chat-workspace');
  static const configWorkspace = Key('config-workspace');
  static const configSettingsHub = Key('config-settings-hub');
  static const rightToolsPanel = Key('right-tools-panel');
  static const rightToolsDivider = Key('right-tools-divider');
  static const membersPanel = Key('members-panel');
  static const fileTreePanel = Key('file-tree-panel');
  static const workspaceTerminalPanel = Key('workspace-terminal-panel');
  static const workspaceChatLandingBackButton = Key(
    'workspace-chat-landing-back-button',
  );
  static const appRailVisibilitySwitch = Key('app-rail-visibility-switch');
  static const contextSidebarVisibilitySwitch = Key(
    'context-sidebar-visibility-switch',
  );
  static const rightToolsVisibilitySwitch = Key('right-tools-visibility-switch');
  static const membersVisibilitySwitch = Key('members-visibility-switch');
  static const fileTreeVisibilitySwitch = Key('file-tree-visibility-switch');
  static const boardVisibilitySwitch = Key('boardVisibilitySwitch');
  static const autoLaunchAllMembersOnConnectSwitch = Key(
    'auto-launch-all-members-on-connect-switch',
  );
  static const openExistingSessionStartsTerminalSwitch = Key(
    'open-existing-session-starts-terminal-switch',
  );
  static const chatSubmitSwitchesToTerminalSwitch = Key(
    'chat-submit-switches-to-terminal-switch',
  );
  static const simpleModeDefaultFullAccessSwitch = Key(
    'simple-mode-default-full-access-switch',
  );
  static const sessionWorkbenchViewToggle = Key(
    'session-workbench-view-toggle',
  );
  static const agentPermissionAttentionBanner = Key(
    'agent-permission-attention-banner',
  );
  static const agentPermissionOpenTerminalButton = Key(
    'agent-permission-open-terminal-button',
  );
  static const askUserQuestionCard = Key('ask-user-question-card');
  static const askUserQuestionBubble = Key('ask-user-question-bubble');
  static const askUserQuestionBubbleHeader = Key(
    'ask-user-question-bubble-header',
  );
  static const exitPlanModeCard = Key('exit-plan-mode-card');
  static const workflowCard = Key('workflow-card');
  static Key workflowAgentRow(String runId, String agentId) =>
      Key('workflow-agent-row-$runId-$agentId');
  static const askUserQuestionSubmitButton = Key(
    'ask-user-question-submit-button',
  );
  static const askUserQuestionContinueButton = Key(
    'ask-user-question-continue-button',
  );
  static const askUserQuestionInlineError = Key(
    'ask-user-question-inline-error',
  );
  static const exitPlanModeApproveButton = Key('exit-plan-mode-approve-button');
  static const exitPlanModeRejectButton = Key('exit-plan-mode-reject-button');
  static const exitPlanModeCopyPlanButton = Key(
    'exit-plan-mode-copy-plan-button',
  );
  static const exitPlanModeExpandButton = Key('exit-plan-mode-expand-button');
  static const exitPlanModeOpenPlanFileButton = Key(
    'exit-plan-mode-open-plan-file-button',
  );
  static const exitPlanModeInlineError = Key('exit-plan-mode-inline-error');
  static const opencodePermissionCard = Key('opencode-permission-card');
  static const opencodePermissionAllowOnceButton = Key(
    'opencode-permission-allow-once-button',
  );
  static const opencodePermissionAlwaysButton = Key(
    'opencode-permission-always-button',
  );
  static const opencodePermissionRejectButton = Key(
    'opencode-permission-reject-button',
  );
  static const opencodePermissionInlineError = Key(
    'opencode-permission-inline-error',
  );

  /// Option row key for a single-question AskUserQuestion card (`{index}`).
  static Key askUserQuestionOption(int index) =>
      Key('ask-user-question-option-$index');

  /// Option row key for multi-question AskUserQuestion cards.
  static Key askUserQuestionOptionAt({
    required int questionIndex,
    required int optionIndex,
  }) => Key('ask-user-question-option-$questionIndex-$optionIndex');
  static const sidebarSessionWaitingMarker = Key(
    'sidebar-session-waiting-marker',
  );
  static const scopeSessionsToSelectedTeamSwitch = Key(
    'scope-sessions-to-selected-team-switch',
  );
  static const terminalLinkClickOpensInAppSwitch = Key(
    'terminal-link-click-opens-in-app-switch',
  );
  static const configTeamSectionButton = Key('config-team-section-button');
  static const configMembersSectionButton = Key(
    'config-members-section-button',
  );
  static const configLayoutSectionButton = Key('config-layout-section-button');
  static const homeWorkspaceProvidersButton = Key(
    'home-workspace-providers-button',
  );
  static const configSessionSectionButton = Key(
    'config-session-section-button',
  );
  static const configCliSectionButton = Key('config-cli-section-button');
  static const configAiFeaturesSectionButton = Key(
    'config-ai-features-section-button',
  );
  static const configSshProfilesSectionButton = Key(
    'config-ssh-profiles-section-button',
  );
  static const connectQrCode = Key('connect-qr-code');
  static const connectScanQr = Key('connect-scan-qr');
  static const connectPasteCode = Key('connect-paste-code');
  static const connectSshdEnableCta = Key('connect-sshd-enable-cta');
  static const connectRegenerateQr = Key('connect-regenerate-qr');
  static const configGithubSectionButton = Key('config-github-section-button');
  static const configDiscoverySectionButton = Key(
    'config-discovery-section-button',
  );
  static const configShortcutsSectionButton = Key(
    'config-shortcuts-section-button',
  );
  static const configLogsSectionButton = Key('config-logs-section-button');
  static const configAboutSectionButton = Key('config-about-section-button');
  static const aboutPage = Key('about-page');
  static const aboutCheckUpdatesButton = Key('about-check-updates-button');
  static const aboutViewReleasesButton = Key('about-view-releases-button');
  static const aboutGitHubButton = Key('about-github-button');
  static const aboutDownloadInstallButton = Key(
    'about-download-install-button',
  );
  static const aboutAutoCheckUpdatesSwitch = Key(
    'about-auto-check-updates-switch',
  );
  static const cliExecutablePathField = Key('cli-executable-path-field');
  static const cliExecutablePathBrowseButton = Key(
    'cli-executable-path-browse-button',
  );
  static const cliExecutablePathResetButton = Key(
    'cli-executable-path-reset-button',
  );
  static const claudeCliExecutablePathField = Key(
    'claude-cli-executable-path-field',
  );
  static const claudeCliExecutablePathBrowseButton = Key(
    'claude-cli-executable-path-browse-button',
  );
  static const claudeCliExecutablePathResetButton = Key(
    'claude-cli-executable-path-reset-button',
  );
  static const claudeCliInstallButton = Key('claude-cli-install-button');
  static const codexCliExecutablePathField = Key(
    'codex-cli-executable-path-field',
  );
  static const codexCliExecutablePathBrowseButton = Key(
    'codex-cli-executable-path-browse-button',
  );
  static const codexCliExecutablePathResetButton = Key(
    'codex-cli-executable-path-reset-button',
  );
  static const codexCliInstallButton = Key('codex-cli-install-button');
  static const opencodeCliExecutablePathField = Key(
    'opencode-cli-executable-path-field',
  );
  static const opencodeCliExecutablePathBrowseButton = Key(
    'opencode-cli-executable-path-browse-button',
  );
  static const opencodeCliExecutablePathResetButton = Key(
    'opencode-cli-executable-path-reset-button',
  );
  static const opencodeCliInstallButton = Key('opencode-cli-install-button');
  static const cursorCliExecutablePathField = Key(
    'cursor-cli-executable-path-field',
  );
  static const cursorCliExecutablePathBrowseButton = Key(
    'cursor-cli-executable-path-browse-button',
  );
  static const cursorCliExecutablePathResetButton = Key(
    'cursor-cli-executable-path-reset-button',
  );
  static const cursorCliInstallButton = Key('cursor-cli-install-button');
  static const gitToolchainPathField = Key('git-toolchain-path-field');
  static const gitToolchainPathBrowseButton = Key(
    'git-toolchain-path-browse-button',
  );
  static const gitToolchainPathResetButton = Key(
    'git-toolchain-path-reset-button',
  );
  static const gitToolchainInstallButton = Key('git-toolchain-install-button');
  static const nodeToolchainPathField = Key('node-toolchain-path-field');
  static const nodeToolchainPathBrowseButton = Key(
    'node-toolchain-path-browse-button',
  );
  static const nodeToolchainPathResetButton = Key(
    'node-toolchain-path-reset-button',
  );
  static const nodeToolchainInstallButton = Key(
    'node-toolchain-install-button',
  );
  static const llmConfigPathOverrideField = Key(
    'llm-config-path-override-field',
  );
  static const llmConfigPathOverrideBrowseButton = Key(
    'llm-config-path-override-browse-button',
  );
  static const llmConfigPathOverrideResetButton = Key(
    'llm-config-path-override-reset-button',
  );
  static const llmConfigOpenSessionSettingsButton = Key(
    'llm-config-open-session-settings-button',
  );
  static const newChatSidebarTile = Key('new-chat-sidebar-tile');
  static const searchSidebarTile = Key('search-sidebar-tile');
  static const workspaceTabRowNewChatButton = Key('workspace-tab-row-new-chat');
  static const newChatCliMenuButton = Key('new-chat-cli-menu-button');
  static const homeWorkspaceWorkspaceManagementTile = Key(
    'home-workspace-workspace-management-tile',
  );
  static const mobileHomeSidebarScrim = Key('mobile-home-sidebar-scrim');
  static const mobileWorkspaceDrawerScrim = Key(
    'mobile-workspace-drawer-scrim',
  );
  static const mobileWorkspaceDrawerModeSwitch = Key(
    'mobile-workspace-drawer-mode-switch',
  );
  static const workspaceConfigWorkspace = Key('workspace-config-workspace');
  static const teamConfigHub = Key('team-config-hub');
  static const teamConfigWorkspace = Key('team-config-workspace');
  static const skillsWorkspace = Key('skills-workspace');
  static const pluginsWorkspace = Key('plugins-workspace');
  static const mcpWorkspace = Key('mcp-workspace');
  static const mcpFormDetail = Key('mcp-form-detail');
  static const extensionsWorkspace = Key('extensions-workspace');
  static const hooksWorkspace = Key('hooks-workspace');
  static const memberConfigWorkspace = Key('member-config-workspace');
  static const llmConfigWorkspace = Key('llm-config-workspace');
  static const llmProviderDetail = Key('llm-provider-detail');
  static const llmProviderModels = Key('llm-provider-models');
  static const llmProvidersTab = Key('llm-providers-tab');
  static const llmModelsTab = Key('llm-models-tab');
  static const llmRawJsonTab = Key('llm-raw-json-tab');
  static const llmValidationSummary = Key('llm-validation-summary');
  static const llmRawJsonPreview = Key('llm-raw-json-preview');
  static const saveLlmConfigButton = Key('save-llm-config-button');
  static const memberConfigSaveButton = Key('save-member-config-button');
  static const memberConfigValidationMessage = Key(
    'member-config-validation-message',
  );
  static const memberConfigCommandPreview = Key(
    'member-config-command-preview',
  );
  static const chatInput = Key('chat-input');
  static const sessionLaunchErrorBanner = Key('session-launch-error-banner');
  static const sessionLaunchErrorReviewButton = Key(
    'session-launch-error-review-button',
  );
  static const sessionLaunchErrorRetryButton = Key(
    'session-launch-error-retry-button',
  );
  static const sendPromptButton = Key('send-prompt-button');
  static const copyPromptButton = Key('copy-prompt-button');
  static const openTeamLeadButton = Key('open-team-lead-button');
  static const openTeamButton = Key('open-team-button');
  static const openRightToolsButton = Key('open-right-tools-button');
  static const rightToolsVisibilityButton = Key(
    'right-tools-visibility-button',
  );
  static const sidebarVisibilityButton = Key('sidebar-visibility-button');

  static const teamNameField = Key('team-name-field');
  static const teamNameDialogField = Key('team-name-dialog-field');
  static const extraArgsField = Key('extra-args-field');
  static const saveButton = Key('save-team-button');
  static const launchButton = Key('launch-team-button');
  static const addButton = Key('add-team-button');
  static const deleteButton = Key('delete-team-button');
  static const addMemberButton = Key('add-member-button');

  static Key memberRow(String id) => Key('member-row-$id');
  static Key sessionTile(String id) => Key('session-tile-$id');
  static Key memberNameField(String id) => Key('member-name-field-$id');
  static Key memberProviderField(String id) => Key('member-provider-field-$id');
  static Key memberModelField(String id) => Key('member-model-field-$id');
  static Key memberAgentField(String id) => Key('member-agent-field-$id');
  static Key memberExtraArgsField(String id) =>
      Key('member-extra-args-field-$id');
  static Key memberOpenButton(String id) => Key('member-open-button-$id');
  static Key memberDeleteButton(String id) => Key('member-delete-button-$id');

  static const addProviderButton = Key('add-provider-button');
  static const addModelButton = Key('add-model-button');
  static const providerNameDialogField = Key('provider-name-dialog-field');
  static const providerRenameDialogField = Key('provider-rename-dialog-field');
  static const modelNameDialogField = Key('model-name-dialog-field');
  static const providerEditForm = Key('provider-edit-form');
  static const modelEditForm = Key('model-edit-form');
  static const revealApiKeyButton = Key('reveal-api-key-button');
  static const replaceApiKeyButton = Key('replace-api-key-button');
  static const apiKeyField = Key('api-key-field');
  static const providerTypeField = Key('provider-type-field');
  static const baseUrlField = Key('base-url-field');
  static const modelProviderField = Key('model-provider-field');
  static const modelModelIdField = Key('model-model-id-field');
  static const modelEnabledToggle = Key('model-enabled-toggle');
  static const providerProxyToggle = Key('provider-proxy-toggle');
  static const proxyUrlField = Key('proxy-url-field');
  static const addAccountPathButton = Key('add-account-path-button');
  static const deleteAccountPathButton = Key('delete-account-path-button');
  static const accountPathField = Key('account-path-field');
  static const llmProviderSearch = Key('llm-provider-search');
  static const llmProviderList = Key('llm-provider-list');
  static const llmSidePanel = Key('llm-side-panel');
  static const llmSummaryStats = Key('llm-summary-stats');
  static const providerModelsTable = Key('provider-models-table');
  static const llmModelsTable = Key('llm-models-table');

  static Key deleteProviderButton(String name) => Key('delete-provider-$name');
  static Key editProviderButton(String name) => Key('edit-provider-$name');
  static Key deleteModelButton(String id) => Key('delete-model-$id');
  static Key editModelButton(String id) => Key('edit-model-$id');

  static const themeSystemButton = Key('theme-system-button');
  static const themeDarkButton = Key('theme-dark-button');
  static const themeLightButton = Key('theme-light-button');
  static const languageSystemButton = Key('language-system-button');
  static const languageEnButton = Key('language-en-button');
  static const languageZhButton = Key('language-zh-button');

  static const automationsWorkspace = Key('automations-workspace');

  static const bootstrapRetryButton = Key('bootstrap-retry-button');
  static const bootstrapChooseWorkEnvironmentButton = Key(
    'bootstrap-choose-work-environment-button',
  );
  static const bootstrapNativeStorageFallbackButton = Key(
    'bootstrap-native-storage-fallback-button',
  );
}
