import 'package:flutter/widgets.dart';

class AppKeys {
  const AppKeys._();

  static const appRailChatButton = Key('app-rail-chat-button');
  static const appRailRunsButton = Key('app-rail-runs-button');
  static const appRailConfigButton = Key('app-rail-config-button');
  static const contextSidebar = Key('context-sidebar');
  static const workspaceTopbar = Key('workspace-topbar');
  static const chatWorkspace = Key('chat-workspace');
  static const configWorkspace = Key('config-workspace');
  static const rightToolsPanel = Key('right-tools-panel');
  static const bottomToolsPanel = Key('bottom-tools-panel');
  static const rightToolsDivider = Key('right-tools-divider');
  static const membersPanel = Key('members-panel');
  static const fileTreePanel = Key('file-tree-panel');
  static const appRailVisibilitySwitch = Key('app-rail-visibility-switch');
  static const contextSidebarVisibilitySwitch = Key(
    'context-sidebar-visibility-switch',
  );
  static const membersVisibilitySwitch = Key('members-visibility-switch');
  static const fileTreeVisibilitySwitch = Key('file-tree-visibility-switch');
  static const toolPlacementRightButton = Key('tool-placement-right-button');
  static const toolPlacementBottomButton = Key('tool-placement-bottom-button');
  static const toolsArrangementStackedButton = Key(
    'tools-arrangement-stacked-button',
  );
  static const toolsArrangementTabsButton = Key(
    'tools-arrangement-tabs-button',
  );
  static const configTeamSectionButton = Key('config-team-section-button');
  static const configMembersSectionButton = Key(
    'config-members-section-button',
  );
  static const configLayoutSectionButton = Key('config-layout-section-button');
  static const configLlmSectionButton = Key('config-llm-section-button');
  static const teamConfigWorkspace = Key('team-config-workspace');
  static const memberConfigWorkspace = Key('member-config-workspace');
  static const llmConfigWorkspace = Key('llm-config-workspace');
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
  static const sendPromptButton = Key('send-prompt-button');
  static const copyPromptButton = Key('copy-prompt-button');
  static const openTeamLeadButton = Key('open-team-lead-button');
  static const openTeamButton = Key('open-team-button');

  static const teamNameField = Key('team-name-field');
  static const workingDirectoryField = Key('working-directory-field');
  static const extraArgsField = Key('extra-args-field');
  static const saveButton = Key('save-team-button');
  static const launchButton = Key('launch-team-button');
  static const addButton = Key('add-team-button');
  static const deleteButton = Key('delete-team-button');
  static const addMemberButton = Key('add-member-button');

  static Key memberRow(String id) => Key('member-row-$id');
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

  static Key deleteProviderButton(String name) =>
      Key('delete-provider-$name');
  static Key editProviderButton(String name) =>
      Key('edit-provider-$name');
  static Key deleteModelButton(String id) =>
      Key('delete-model-$id');
  static Key editModelButton(String id) =>
      Key('edit-model-$id');
}
