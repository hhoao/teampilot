///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'translations.g.dart';

// Path: <root>
typedef AppLocalizationsEn = AppLocalizations; // ignore: unused_element
class AppLocalizations with BaseTranslations<AppLocale, AppLocalizations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final l10n = AppLocalizations.of(context);
	static AppLocalizations of(BuildContext context) => InheritedLocaleData.of<AppLocale, AppLocalizations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	AppLocalizations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, AppLocalizations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	final TranslationMetadata<AppLocale, AppLocalizations> _meta;
	@override TranslationMetadata<AppLocale, AppLocalizations> get $meta => _meta;

	/// Access flat map
	dynamic operator[](String key) => _meta.getTranslation(key);

	late final AppLocalizations _root = this; // ignore: unused_field

	AppLocalizations $copyWith({TranslationMetadata<AppLocale, AppLocalizations>? meta}) => AppLocalizations(meta: meta ?? this.$meta);

	// Translations

	/// en: 'Current version'
	String get aboutCurrentVersion => 'Current version';

	/// en: 'GitHub'
	String get aboutGitHub => 'GitHub';

	/// en: 'TeamPilot version and application updates.'
	String get aboutPageSubtitle => 'TeamPilot version and application updates.';

	/// en: 'About'
	String get aboutTitle => 'About';

	/// en: 'Loading…'
	String get aboutVersionLoading => 'Loading…';

	/// en: 'account'
	String get account => 'account';

	/// en: 'Account credential path'
	String get accountCredentialPath => 'Account credential path';

	/// en: 'Actual Model'
	String get actualModel => 'Actual Model';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Add account path'
	String get addAccountPath => 'Add account path';

	/// en: 'Add Model'
	String get addModel => 'Add Model';

	/// en: 'Add Provider'
	String get addProvider => 'Add Provider';

	/// en: 'Add team'
	String get addTeamTitle => 'Add team';

	/// en: 'Add team'
	String get addTeamTooltip => 'Add team';

	/// en: 'Add directory'
	String get addWorkspaceDirectory => 'Add directory';

	/// en: 'All checks passed.'
	String get allChecksPassed => 'All checks passed.';

	/// en: 'Work environment'
	String get androidWorkEnvironmentSelectorLabel => 'Work environment';

	/// en: 'Termux setup…'
	String get androidWorkEnvironmentSelectorManageTermux => 'Termux setup…';

	/// en: 'Termux'
	String get androidWorkEnvironmentSelectorTermux => 'Termux';

	/// en: 'Termux · {username: String}'
	String androidWorkEnvironmentSelectorTermuxWithUser({required String username}) => 'Termux · ${username}';

	/// en: 'api'
	String get api => 'api';

	/// en: 'API Key'
	String get apiKey => 'API Key';

	/// en: 'Appearance'
	String get appearance => 'Appearance';

	/// en: 'Archive'
	String get archiveConversation => 'Archive';

	/// en: '(one) {Asked {count: int} question} (other) {Asked {count: int} questions}'
	String askUserQuestionBubbleAsked({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'Asked ${count} question',
		other: 'Asked ${count} questions',
	);

	/// en: 'Asking questions'
	String get askUserQuestionBubbleAsking => 'Asking questions';

	/// en: 'Unanswered'
	String get askUserQuestionBubbleUnanswered => 'Unanswered';

	/// en: 'Mixed teams only: when enabled, Connect and Restart launch every valid member shell; native teams always launch all members.'
	String get autoLaunchAllMembersDescription => 'Mixed teams only: when enabled, Connect and Restart launch every valid member shell; native teams always launch all members.';

	/// en: 'Start all members on connect'
	String get autoLaunchAllMembersTitle => 'Start all members on connect';

	/// en: 'When a subagent starts running, open its preview automatically and follow it live. Press Back to stop following for this session.'
	String get autoOpenSubagentPreviewDescription => 'When a subagent starts running, open its preview automatically and follow it live. Press Back to stop following for this session.';

	/// en: 'Auto-open subagent preview'
	String get autoOpenSubagentPreviewTitle => 'Auto-open subagent preview';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Base URL'
	String get baseUrl => 'Base URL';

	/// en: 'Board'
	String get board => 'Board';

	/// en: 'In progress'
	String get boardClaimed => 'In progress';

	/// en: 'Done'
	String get boardDone => 'Done';

	/// en: 'No tasks yet'
	String get boardEmpty => 'No tasks yet';

	/// en: 'Pending'
	String get boardPending => 'Pending';

	/// en: 'Choose work environment'
	String get bootstrapChooseWorkEnvironment => 'Choose work environment';

	/// en: 'Starting TeamPilot…'
	String get bootstrapLoadingApp => 'Starting TeamPilot…';

	/// en: 'Loading libraries…'
	String get bootstrapLoadingLibraries => 'Loading libraries…';

	/// en: 'Loading workspaces…'
	String get bootstrapLoadingWorkspaces => 'Loading workspaces…';

	/// en: 'Retry'
	String get bootstrapRetry => 'Retry';

	/// en: 'Startup failed: {error: String}'
	String bootstrapStartupFailed({required String error}) => 'Startup failed: ${error}';

	/// en: 'Use Windows local storage instead'
	String get bootstrapUseNativeStorageInstead => 'Use Windows local storage instead';

	/// en: 'Bottom'
	String get bottom => 'Bottom';

	/// en: 'Hide bottom panel'
	String get bottomDockPanelHidden => 'Hide bottom panel';

	/// en: 'Show bottom panel'
	String get bottomDockPanelVisible => 'Show bottom panel';

	/// en: 'Bottom Tray'
	String get bottomTray => 'Bottom Tray';

	/// en: 'Failed to send the edited message'
	String get branchEditFailed => 'Failed to send the edited message';

	/// en: 'Next version'
	String get branchNext => 'Next version';

	/// en: 'Previous version'
	String get branchPrevious => 'Previous version';

	/// en: 'Failed to switch version'
	String get branchSwitchFailed => 'Failed to switch version';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Close All'
	String get closeAllTabs => 'Close All';

	/// en: 'Close conversation'
	String get closeConversation => 'Close conversation';

	/// en: 'Close Others'
	String get closeOtherTabs => 'Close Others';

	/// en: 'Close to the Right'
	String get closeRightTabs => 'Close to the Right';

	/// en: 'Close'
	String get closeTab => 'Close';

	/// en: 'Configure'
	String get configure => 'Configure';

	/// en: 'Confirm'
	String get confirm => 'Confirm';

	/// en: 'Flatten (natural height)'
	String get contentDisplayModeFlatten => 'Flatten (natural height)';

	/// en: 'Fold · expand full'
	String get contentDisplayModeFoldExpandFull => 'Fold · expand full';

	/// en: 'Fold · fixed height'
	String get contentDisplayModeFoldFixedHeight => 'Fold · fixed height';

	/// en: 'Content display'
	String get contentDisplayModeSectionTitle => 'Content display';

	/// en: 'The new provider/model is saved. A running session still uses the old config, so the switch only takes effect after a restart.'
	String get continueSwitchRestartBody => 'The new provider/model is saved. A running session still uses the old config, so the switch only takes effect after a restart.';

	/// en: 'Later'
	String get continueSwitchRestartLater => 'Later';

	/// en: 'Restart now'
	String get continueSwitchRestartNow => 'Restart now';

	/// en: 'Restart to apply switch?'
	String get continueSwitchRestartTitle => 'Restart to apply switch?';

	/// en: 'Conversation name'
	String get conversationName => 'Conversation name';

	/// en: 'copy'
	String get copy => 'copy';

	/// en: 'Copy Folder Path'
	String get copyFolderPath => 'Copy Folder Path';

	/// en: 'Copy prompt'
	String get copyPrompt => 'Copy prompt';

	/// en: 'Auto-expand the thinking process of the latest message while the agent is still thinking, then fold it once that output ends.'
	String get cotExpandLatestOnOpenDescription => 'Auto-expand the thinking process of the latest message while the agent is still thinking, then fold it once that output ends.';

	/// en: 'Expand latest thinking process'
	String get cotExpandLatestOnOpenTitle => 'Expand latest thinking process';

	/// en: 'When you open a thinking-process block, expand nested reasoning steps automatically.'
	String get cotExpandReasoningOnOpenDescription => 'When you open a thinking-process block, expand nested reasoning steps automatically.';

	/// en: 'Expand reasoning when opening'
	String get cotExpandReasoningOnOpenTitle => 'Expand reasoning when opening';

	/// en: 'When you open a thinking-process block, expand nested tool call details automatically.'
	String get cotExpandToolsOnOpenDescription => 'When you open a thinking-process block, expand nested tool call details automatically.';

	/// en: 'Expand tools when opening'
	String get cotExpandToolsOnOpenTitle => 'Expand tools when opening';

	/// en: 'Create'
	String get create => 'Create';

	/// en: 'Push credentials'
	String get credentialPushConfirmAction => 'Push credentials';

	/// en: 'Provider keys will be written to the remote host {host}. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.'
	String credentialPushConfirmBody({required Object host}) => 'Provider keys will be written to the remote host ${host}. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.';

	/// en: 'Push credentials to remote host?'
	String get credentialPushConfirmTitle => 'Push credentials to remote host?';

	/// en: 'Provider keys for remote member authentication.'
	String get credentialPushOptInSubtitle => 'Provider keys for remote member authentication.';

	/// en: 'Push credentials to this machine'
	String get credentialPushOptInTitle => 'Push credentials to this machine';

	/// en: 'Danger zone'
	String get dangerZone => 'Danger zone';

	/// en: 'Default model'
	String get defaultModel => 'Default model';

	/// en: 'New Chat'
	String get defaultNewChatSessionTitle => 'New Chat';

	/// en: 'When on, opening discovery pages checks for updates when the cache is older than 24 hours. Manual refresh always updates.'
	String get discoveryAutoRefreshSubtitle => 'When on, opening discovery pages checks for updates when the cache is older than 24 hours. Manual refresh always updates.';

	/// en: 'Auto-refresh discovery content'
	String get discoveryAutoRefreshTitle => 'Auto-refresh discovery content';

	/// en: 'How skills, plugins and MCP discovery content refreshes.'
	String get discoverySettingsSubtitle => 'How skills, plugins and MCP discovery content refreshes.';

	/// en: 'Discovery & Marketplaces'
	String get discoverySettingsTitle => 'Discovery & Marketplaces';

	/// en: 'Duplicate conversation'
	String get duplicateConversation => 'Duplicate conversation';

	/// en: 'Local shell-mode conversation notes will appear here.'
	String get emptyTimeline => 'Local shell-mode conversation notes will appear here.';

	/// en: 'Enabled'
	String get enabled => 'Enabled';

	/// en: 'Added'
	String get expertsCatalogAdoption => 'Added';

	/// en: 'Extensions will appear here once the catalog loads.'
	String get extensionsEmptyHint => 'Extensions will appear here once the catalog loads.';

	/// en: 'No extensions available'
	String get extensionsEmptyTitle => 'No extensions available';

	/// en: 'Installed'
	String get extensionsNavInstalled => 'Installed';

	/// en: 'Install and enable external tools that augment your agents.'
	String get extensionsSettingsDescription => 'Install and enable external tools that augment your agents.';

	/// en: 'Extensions'
	String get extensionsSettingsTitle => 'Extensions';

	/// en: 'Filter files'
	String get filterFiles => 'Filter files';

	/// en: 'Filter providers...'
	String get filterProviders => 'Filter providers...';

	/// en: 'Fork from here'
	String get forkFromHere => 'Fork from here';

	/// en: 'This field is required.'
	String get formFieldRequired => 'This field is required.';

	/// en: 'Hide'
	String get hide => 'Hide';

	/// en: 'No hooks'
	String get hooksNoInstalled => 'No hooks';

	/// en: 'Create a hook to run commands on CLI events.'
	String get hooksNoInstalledHint => 'Create a hook to run commands on CLI events.';

	/// en: 'The file could not be loaded for preview.'
	String get htmlPreviewErrorBody => 'The file could not be loaded for preview.';

	/// en: 'Preview unavailable'
	String get htmlPreviewErrorTitle => 'Preview unavailable';

	/// en: 'Open in System Browser'
	String get htmlPreviewOpenBrowser => 'Open in System Browser';

	/// en: 'Preview opened in your system browser. Use this panel to open it again.'
	String get htmlPreviewOpenedInBrowser => 'Preview opened in your system browser. Use this panel to open it again.';

	/// en: 'Edit'
	String get htmlViewToggleEdit => 'Edit';

	/// en: 'Preview'
	String get htmlViewTogglePreview => 'Preview';

	/// en: 'Local and remote seats can run commands and transfer files on this workspace's SSH machines via MCP. Reconnect sessions after changing.'
	String get injectSessionSshMcpSubtitle => 'Local and remote seats can run commands and transfer files on this workspace\'s SSH machines via MCP. Reconnect sessions after changing.';

	/// en: 'Inject Session SSH MCP'
	String get injectSessionSshMcpTitle => 'Inject Session SSH MCP';

	/// en: 'Invalid JSON. Fix the syntax and try again.'
	String get invalidJson => 'Invalid JSON. Fix the syntax and try again.';

	/// en: 'JSON Preview'
	String get jsonPreview => 'JSON Preview';

	/// en: 'Language'
	String get language => 'Language';

	/// en: '中文'
	String get languageChinese => '中文';

	/// en: 'Language used for menus, buttons, and labels.'
	String get languageDescription => 'Language used for menus, buttons, and labels.';

	/// en: 'English'
	String get languageEnglish => 'English';

	/// en: 'System'
	String get languageSystem => 'System';

	/// en: 'Layout'
	String get layout => 'Layout';

	/// en: 'Structure controls are global and apply across teams.'
	String get layoutPageSubtitle => 'Structure controls are global and apply across teams.';

	/// en: 'global workbench'
	String get layoutSubtitle => 'global workbench';

	/// en: 'Mailbox'
	String get mailbox => 'Mailbox';

	/// en: 'No messages yet'
	String get mailboxEmpty => 'No messages yet';

	/// en: 'Default view when opening .md files in the editor. Remember lasts for this app session only.'
	String get markdownOpenModeDescription => 'Default view when opening .md files in the editor. Remember lasts for this app session only.';

	/// en: 'Preview'
	String get markdownOpenModePreview => 'Preview';

	/// en: 'Remember last'
	String get markdownOpenModeRemember => 'Remember last';

	/// en: 'Source'
	String get markdownOpenModeSource => 'Source';

	/// en: 'Open Markdown as'
	String get markdownOpenModeTitle => 'Open Markdown as';

	/// en: 'Preview'
	String get markdownViewTogglePreview => 'Preview';

	/// en: 'Source'
	String get markdownViewToggleSource => 'Source';

	/// en: 'Members'
	String get members => 'Members';

	/// en: 'Members and File Tree'
	String get membersAndFileTree => 'Members and File Tree';

	/// en: 'Show members and file tree stacked or as tabs.'
	String get membersAndFileTreeDescription => 'Show members and file tree stacked or as tabs.';

	/// en: 'team agents'
	String get membersSubtitle => 'team agents';

	/// en: 'Missing provider:'
	String get missingProvider => 'Missing provider:';

	/// en: 'Model'
	String get model => 'Model';

	/// en: 'Model ID'
	String get modelId => 'Model ID';

	/// en: 'Model alias/name'
	String get modelName => 'Model alias/name';

	/// en: 'Models'
	String get models => 'Models';

	/// en: 'Models'
	String get modelsTab => 'Models';

	/// en: 'Models using this provider: {count: int}'
	String modelsUsingProvider({required int count}) => 'Models using this provider: ${count}';

	/// en: 'Models using this provider'
	String get modelsUsingProviderTitle => 'Models using this provider';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'New session'
	String get newSessionTooltip => 'New session';

	/// en: 'New Workspace'
	String get newWorkspace => 'New Workspace';

	/// en: 'Create a workspace'
	String get newWorkspaceTooltip => 'Create a workspace';

	/// en: 'No models configured'
	String get noModelsConfigured => 'No models configured';

	/// en: 'No models are using this provider.'
	String get noModelsUsingProvider => 'No models are using this provider.';

	/// en: 'No sessions yet'
	String get noSessions => 'No sessions yet';

	/// en: 'Notes'
	String get notes => 'Notes';

	/// en: 'When a session finishes a turn and becomes idle, show an OS notification in addition to the in-app notification center.'
	String get notifyOnSessionIdleDescription => 'When a session finishes a turn and becomes idle, show an OS notification in addition to the in-app notification center.';

	/// en: 'Agent idle system notification'
	String get notifyOnSessionIdleTitle => 'Agent idle system notification';

	/// en: 'OK'
	String get ok => 'OK';

	/// en: 'When enabled, opening a conversation from the sidebar connects the terminal immediately. When off (default), open the Chat view first; send from Chat to start the terminal.'
	String get openExistingSessionStartsTerminalDescription => 'When enabled, opening a conversation from the sidebar connects the terminal immediately. When off (default), open the Chat view first; send from Chat to start the terminal.';

	/// en: 'Open existing sessions in terminal'
	String get openExistingSessionStartsTerminalTitle => 'Open existing sessions in terminal';

	/// en: 'Open Folder'
	String get openFolder => 'Open Folder';

	/// en: 'Open member'
	String get openMember => 'Open member';

	/// en: 'Tools'
	String get openRightTools => 'Tools';

	/// en: 'Open session folder'
	String get openSessionDirectory => 'Open session folder';

	/// en: 'Open Team'
	String get openTeam => 'Open Team';

	/// en: 'Path copied: {path: String}'
	String pathCopied({required String path}) => 'Path copied: ${path}';

	/// en: 'Pick primary directory'
	String get pickPrimaryDirectory => 'Pick primary directory';

	/// en: 'Pin conversation'
	String get pinConversation => 'Pin conversation';

	/// en: 'None (no default)'
	String get presetPickerNoneOption => 'None (no default)';

	/// en: 'Select Preset'
	String get presetPickerTitle => 'Select Preset';

	/// en: '(one) {1 activity in progress} (other) {{count: int} activities in progress}'
	String progressActivitiesMany({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '1 activity in progress',
		other: '${count} activities in progress',
	);

	/// en: 'Activities in progress'
	String get progressActivitiesPanelTitle => 'Activities in progress';

	/// en: 'Other'
	String get projectTreeOther => 'Other';

	/// en: 'Prompt'
	String get prompt => 'Prompt';

	/// en: 'PROVIDERS'
	String get providers => 'PROVIDERS';

	/// en: 'Providers'
	String get providersTab => 'Providers';

	/// en: 'Proxy'
	String get proxy => 'Proxy';

	/// en: 'Proxy off'
	String get proxyOffShort => 'Proxy off';

	/// en: 'Proxy on'
	String get proxyOnShort => 'Proxy on';

	/// en: 'Proxy URL'
	String get proxyUrl => 'Proxy URL';

	/// en: 'Raw JSON'
	String get rawJsonTab => 'Raw JSON';

	/// en: 'Minutes a terminal may sit idle before it is reclaimed.'
	String get reclaimIdleTerminalMinutesDescription => 'Minutes a terminal may sit idle before it is reclaimed.';

	/// en: 'Idle reclaim timeout (minutes)'
	String get reclaimIdleTerminalMinutesTitle => 'Idle reclaim timeout (minutes)';

	/// en: 'Close idle member/session terminals after a timeout to free memory; they reconnect on demand.'
	String get reclaimIdleTerminalsDescription => 'Close idle member/session terminals after a timeout to free memory; they reconnect on demand.';

	/// en: 'Reclaim idle terminals'
	String get reclaimIdleTerminalsTitle => 'Reclaim idle terminals';

	/// en: 'Reference conversation'
	String get referenceConversation => 'Reference conversation';

	/// en: 'Failed to prepare conversation reference'
	String get referenceConversationFailed => 'Failed to prepare conversation reference';

	/// en: 'Region Visibility'
	String get regionVisibility => 'Region Visibility';

	/// en: 'Remove path'
	String get removePath => 'Remove path';

	/// en: 'Remove directory'
	String get removeWorkspaceDirectory => 'Remove directory';

	/// en: 'Remove machine'
	String get removeWorkspaceMachine => 'Remove machine';

	/// en: 'Rename conversation'
	String get renameConversation => 'Rename conversation';

	/// en: 'Rename Conversation'
	String get renameConversationTitle => 'Rename Conversation';

	/// en: 'Rename'
	String get renameProviderName => 'Rename';

	/// en: 'Rename provider'
	String get renameProviderTitle => 'Rename provider';

	/// en: 'Replace key'
	String get replaceKey => 'Replace key';

	/// en: 'Restore'
	String get restoreConversation => 'Restore';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Reveal'
	String get reveal => 'Reveal';

	/// en: 'Right'
	String get right => 'Right';

	/// en: 'Right Tools'
	String get rightTools => 'Right Tools';

	/// en: 'All tools are already open.'
	String get rightToolsOpenTabEmpty => 'All tools are already open.';

	/// en: 'Choose a tool to open in the side panel.'
	String get rightToolsOpenTabSubtitle => 'Choose a tool to open in the side panel.';

	/// en: 'Open a tab'
	String get rightToolsOpenTabTitle => 'Open a tab';

	/// en: 'Hide tools panel'
	String get rightToolsPanelHidden => 'Hide tools panel';

	/// en: 'Show tools panel'
	String get rightToolsPanelVisible => 'Show tools panel';

	/// en: 'Enable'
	String get rootSandboxEnvConfirmAction => 'Enable';

	/// en: 'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on {host}, keeping --dangerously-skip-permissions. Only enable on machines you trust.'
	String rootSandboxEnvConfirmBody({required Object host}) => 'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on ${host}, keeping --dangerously-skip-permissions. Only enable on machines you trust.';

	/// en: 'Enable root sandbox env?'
	String get rootSandboxEnvConfirmTitle => 'Enable root sandbox env?';

	/// en: 'Keep skip-permissions when Claude runs as root.'
	String get rootSandboxEnvOptInSubtitle => 'Keep skip-permissions when Claude runs as root.';

	/// en: 'Inject IS_SANDBOX for root'
	String get rootSandboxEnvOptInTitle => 'Inject IS_SANDBOX for root';

	/// en: 'Run history will appear here.'
	String get runsPlaceholder => 'Run history will appear here.';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Save Member'
	String get saveMember => 'Save Member';

	/// en: 'When enabled, the sidebar shows only sessions assigned to the current team. New sessions are always tagged with the selected team so they appear here if you turn this on later.'
	String get scopeSessionsToSelectedTeamDescription => 'When enabled, the sidebar shows only sessions assigned to the current team. New sessions are always tagged with the selected team so they appear here if you turn this on later.';

	/// en: 'Scope sessions to selected team'
	String get scopeSessionsToSelectedTeamTitle => 'Scope sessions to selected team';

	/// en: 'Select preset'
	String get selectAgent => 'Select preset';

	/// en: 'Select a model'
	String get selectModel => 'Select a model';

	/// en: 'Select a provider from the list'
	String get selectProvider => 'Select a provider from the list';

	/// en: 'Select team'
	String get selectTeam => 'Select team';

	/// en: 'Ask AI…'
	String get selectionAskAi => 'Ask AI…';

	/// en: 'Send prompt'
	String get sendPrompt => 'Send prompt';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Manage FlashskyAI team and model settings.'
	String get settingsPageSubtitle => 'Manage FlashskyAI team and model settings.';

	/// en: 'Shell chat workbench'
	String get shellChatWorkbench => 'Shell chat workbench';

	/// en: 'Shell session'
	String get shellSession => 'Shell session';

	/// en: 'Hide sidebar'
	String get sidebarPanelHidden => 'Hide sidebar';

	/// en: 'Show sidebar'
	String get sidebarPanelVisible => 'Show sidebar';

	/// en: 'Source Control'
	String get sourceControl => 'Source Control';

	/// en: 'Stacked'
	String get stacked => 'Stacked';

	/// en: 'Stacked Tools'
	String get stackedTools => 'Stacked Tools';

	/// en: 'empty keys'
	String get statEmptyKeys => 'empty keys';

	/// en: 'missing refs'
	String get statMissingRefs => 'missing refs';

	/// en: 'models'
	String get statModels => 'models';

	/// en: 'providers'
	String get statProviders => 'providers';

	/// en: 'Back'
	String get subagentPreviewBack => 'Back';

	/// en: 'No subagent content yet'
	String get subagentPreviewEmpty => 'No subagent content yet';

	/// en: '{title: String}'
	String subagentPreviewTitleAgent({required String title}) => '${title}';

	/// en: 'Subagent preview is unavailable for this tool call.'
	String get subagentPreviewUnavailable => 'Subagent preview is unavailable for this tool call.';

	/// en: 'Summary'
	String get summary => 'Summary';

	/// en: 'Switch to member'
	String get switchToMember => 'Switch to member';

	/// en: 'Switch workspace'
	String get switchWorkspaceTooltip => 'Switch workspace';

	/// en: 'Split Down'
	String get tabMenuSplitDown => 'Split Down';

	/// en: 'Split Right'
	String get tabMenuSplitRight => 'Split Right';

	/// en: 'Tabbed Tools'
	String get tabbedTools => 'Tabbed Tools';

	/// en: 'Tabs'
	String get tabs => 'Tabs';

	/// en: 'Added'
	String get teamsCatalogAdoption => 'Added';

	/// en: 'Fold into thinking process'
	String get thinkingProcessFoldSectionTitle => 'Fold into thinking process';

	/// en: 'Thinking process'
	String get thinkingProcessSectionTitle => 'Thinking process';

	/// en: 'Git'
	String get toolchainGit => 'Git';

	/// Label for Git executable path setting
	///
	/// en: 'Git executable path'
	String get toolchainGitLabel => 'Git executable path';

	/// Progress message when checking for a toolchain tool
	///
	/// en: 'Checking for {tool: String}...'
	String toolchainInstallProgressChecking({required String tool}) => 'Checking for ${tool}...';

	/// en: 'Node.js'
	String get toolchainNode => 'Node.js';

	/// Label for Node.js/npm path setting
	///
	/// en: 'Node.js / npm path'
	String get toolchainNodeLabel => 'Node.js / npm path';

	/// Description for toolchain path setting
	///
	/// en: 'Absolute path to the {tool: String} executable. Leave empty to use the one on PATH.'
	String toolchainPathDescription({required String tool}) => 'Absolute path to the ${tool} executable. Leave empty to use the one on PATH.';

	/// Description for toolchain path setting in SSH mode
	///
	/// en: 'Absolute path to {tool: String} on the remote SSH host. Leave empty to auto-discover.'
	String toolchainPathDescriptionSsh({required String tool}) => 'Absolute path to ${tool} on the remote SSH host. Leave empty to auto-discover.';

	/// en: 'Collapse all folders'
	String get treeCollapseAllFolders => 'Collapse all folders';

	/// en: 'Expand all folders'
	String get treeExpandAllFolders => 'Expand all folders';

	/// en: 'Type'
	String get type => 'Type';

	/// en: 'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.'
	String get uiZoomDescription => 'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.';

	/// en: 'Interface zoom'
	String get uiZoomTitle => 'Interface zoom';

	/// en: 'Unknown'
	String get unknownFolder => 'Unknown';

	/// en: 'Unpin conversation'
	String get unpinConversation => 'Unpin conversation';

	/// en: 'Validate'
	String get validate => 'Validate';

	/// en: 'Validation'
	String get validation => 'Validation';

	/// en: 'Show the task board for mixed-mode teams.'
	String get visibilityBoardHint => 'Show the task board for mixed-mode teams.';

	/// en: 'Show the workspace file tree for quick navigation.'
	String get visibilityFileTreeHint => 'Show the workspace file tree for quick navigation.';

	/// en: 'Show the source control panel for the current repository.'
	String get visibilityGitHint => 'Show the source control panel for the current repository.';

	/// en: 'Show the member list next to tools or terminals.'
	String get visibilityMembersHint => 'Show the member list next to tools or terminals.';

	/// en: 'Show the right tools panel when opening a session.'
	String get visibilityRightToolsHint => 'Show the right tools panel when opening a session.';

	/// en: 'Show the team sessions list in the left sidebar.'
	String get visibilityTeamSessionsHint => 'Show the team sessions list in the left sidebar.';

	/// en: 'Always on top'
	String get windowControlAlwaysOnTop => 'Always on top';

	/// en: 'Close'
	String get windowControlClose => 'Close';

	/// en: 'Maximize'
	String get windowControlMaximize => 'Maximize';

	/// en: 'Minimize'
	String get windowControlMinimize => 'Minimize';

	/// en: 'Restore'
	String get windowControlRestore => 'Restore';

	/// en: 'CLI runs in WSL but data is stored in Windows AppData. Config may not match.'
	String get windowsStorageCliMismatchNativeCli => 'CLI runs in WSL but data is stored in Windows AppData. Config may not match.';

	/// en: 'CLI runs on Windows but data is stored in WSL. Config may not match.'
	String get windowsStorageCliMismatchWslCli => 'CLI runs on Windows but data is stored in WSL. Config may not match.';

	/// en: 'Reconnect open sessions after switching storage.'
	String get windowsStorageSwitchReloadHint => 'Reconnect open sessions after switching storage.';

	/// en: 'Lock Group'
	String get workbenchLockGroup => 'Lock Group';

	/// en: 'New'
	String get workbenchStripNewMenuTooltip => 'New';

	/// en: 'Unlock Group'
	String get workbenchUnlockGroup => 'Unlock Group';

	/// en: '{count: int} agents'
	String workflowCardAgents({required int count}) => '${count} agents';

	/// en: 'Workflow run not found for this tool call.'
	String get workflowCardRunMissing => 'Workflow run not found for this tool call.';

	/// en: 'Workspaces'
	String get workspaces => 'Workspaces';

	late final AppLocalizations$acp$en acp = AppLocalizations$acp$en.internal(_root);
	late final AppLocalizations$agent$en agent = AppLocalizations$agent$en.internal(_root);
	late final AppLocalizations$ai$en ai = AppLocalizations$ai$en.internal(_root);
	late final AppLocalizations$antigravity$en antigravity = AppLocalizations$antigravity$en.internal(_root);
	late final AppLocalizations$app$en app = AppLocalizations$app$en.internal(_root);
	late final AppLocalizations$appProvider$en appProvider = AppLocalizations$appProvider$en.internal(_root);
	late final AppLocalizations$automations$en automations = AppLocalizations$automations$en.internal(_root);
	late final AppLocalizations$catalog$en catalog = AppLocalizations$catalog$en.internal(_root);
	late final AppLocalizations$chat$en chat = AppLocalizations$chat$en.internal(_root);
	late final AppLocalizations$claude$en claude = AppLocalizations$claude$en.internal(_root);
	late final AppLocalizations$cli$en cli = AppLocalizations$cli$en.internal(_root);
	late final AppLocalizations$clone$en clone = AppLocalizations$clone$en.internal(_root);
	late final AppLocalizations$codebuddy$en codebuddy = AppLocalizations$codebuddy$en.internal(_root);
	late final AppLocalizations$codex$en codex = AppLocalizations$codex$en.internal(_root);
	late final AppLocalizations$compose$en compose = AppLocalizations$compose$en.internal(_root);
	late final AppLocalizations$connect$en connect = AppLocalizations$connect$en.internal(_root);
	late final AppLocalizations$cursor$en cursor = AppLocalizations$cursor$en.internal(_root);
	late final AppLocalizations$delete$en delete = AppLocalizations$delete$en.internal(_root);
	late final AppLocalizations$diff$en diff = AppLocalizations$diff$en.internal(_root);
	late final AppLocalizations$download$en download = AppLocalizations$download$en.internal(_root);
	late final AppLocalizations$edit$en edit = AppLocalizations$edit$en.internal(_root);
	late final AppLocalizations$editor$en editor = AppLocalizations$editor$en.internal(_root);
	late final AppLocalizations$exit$en exit = AppLocalizations$exit$en.internal(_root);
	late final AppLocalizations$expert$en expert = AppLocalizations$expert$en.internal(_root);
	late final AppLocalizations$extension$en extension = AppLocalizations$extension$en.internal(_root);
	late final AppLocalizations$file$en file = AppLocalizations$file$en.internal(_root);
	late final AppLocalizations$fileTree$en fileTree = AppLocalizations$fileTree$en.internal(_root);
	late final AppLocalizations$floating$en floating = AppLocalizations$floating$en.internal(_root);
	late final AppLocalizations$font$en font = AppLocalizations$font$en.internal(_root);
	late final AppLocalizations$git$en git = AppLocalizations$git$en.internal(_root);
	late final AppLocalizations$gitGraph$en gitGraph = AppLocalizations$gitGraph$en.internal(_root);
	late final AppLocalizations$github$en github = AppLocalizations$github$en.internal(_root);
	late final AppLocalizations$grok$en grok = AppLocalizations$grok$en.internal(_root);
	late final AppLocalizations$home$en home = AppLocalizations$home$en.internal(_root);
	late final AppLocalizations$homeWorkspace$en homeWorkspace = AppLocalizations$homeWorkspace$en.internal(_root);
	late final AppLocalizations$hook$en hook = AppLocalizations$hook$en.internal(_root);
	late final AppLocalizations$hub$en hub = AppLocalizations$hub$en.internal(_root);
	late final AppLocalizations$init$en init = AppLocalizations$init$en.internal(_root);
	late final AppLocalizations$landing$en landing = AppLocalizations$landing$en.internal(_root);
	late final AppLocalizations$llm$en llm = AppLocalizations$llm$en.internal(_root);
	late final AppLocalizations$log$en log = AppLocalizations$log$en.internal(_root);
	late final AppLocalizations$managedProviders$en managedProviders = AppLocalizations$managedProviders$en.internal(_root);
	late final AppLocalizations$mcp$en mcp = AppLocalizations$mcp$en.internal(_root);
	late final AppLocalizations$member$en member = AppLocalizations$member$en.internal(_root);
	late final AppLocalizations$mixed$en mixed = AppLocalizations$mixed$en.internal(_root);
	late final AppLocalizations$my$en my = AppLocalizations$my$en.internal(_root);
	late final AppLocalizations$notification$en notification = AppLocalizations$notification$en.internal(_root);
	late final AppLocalizations$onboarding$en onboarding = AppLocalizations$onboarding$en.internal(_root);
	late final AppLocalizations$opencode$en opencode = AppLocalizations$opencode$en.internal(_root);
	late final AppLocalizations$plugin$en plugin = AppLocalizations$plugin$en.internal(_root);
	late final AppLocalizations$plugins$en plugins = AppLocalizations$plugins$en.internal(_root);
	late final AppLocalizations$provider$en provider = AppLocalizations$provider$en.internal(_root);
	late final AppLocalizations$qoder$en qoder = AppLocalizations$qoder$en.internal(_root);
	late final AppLocalizations$remote$en remote = AppLocalizations$remote$en.internal(_root);
	late final AppLocalizations$resource$en resource = AppLocalizations$resource$en.internal(_root);
	late final AppLocalizations$rtk$en rtk = AppLocalizations$rtk$en.internal(_root);
	late final AppLocalizations$run$en run = AppLocalizations$run$en.internal(_root);
	late final AppLocalizations$session$en session = AppLocalizations$session$en.internal(_root);
	late final AppLocalizations$sessionUsage$en sessionUsage = AppLocalizations$sessionUsage$en.internal(_root);
	late final AppLocalizations$shortcuts$en shortcuts = AppLocalizations$shortcuts$en.internal(_root);
	late final AppLocalizations$skills$en skills = AppLocalizations$skills$en.internal(_root);
	late final AppLocalizations$ssh$en ssh = AppLocalizations$ssh$en.internal(_root);
	late final AppLocalizations$sshProfile$en sshProfile = AppLocalizations$sshProfile$en.internal(_root);
	late final AppLocalizations$team$en team = AppLocalizations$team$en.internal(_root);
	late final AppLocalizations$teamHub$en teamHub = AppLocalizations$teamHub$en.internal(_root);
	late final AppLocalizations$terminal$en terminal = AppLocalizations$terminal$en.internal(_root);
	late final AppLocalizations$termux$en termux = AppLocalizations$termux$en.internal(_root);
	late final AppLocalizations$theme$en theme = AppLocalizations$theme$en.internal(_root);
	late final AppLocalizations$tool$en tool = AppLocalizations$tool$en.internal(_root);
	late final AppLocalizations$typography$en typography = AppLocalizations$typography$en.internal(_root);
	late final AppLocalizations$vault$en vault = AppLocalizations$vault$en.internal(_root);
	late final AppLocalizations$workspace$en workspace = AppLocalizations$workspace$en.internal(_root);
	late final AppLocalizations$worktree$en worktree = AppLocalizations$worktree$en.internal(_root);
}

// Path: acp
class AppLocalizations$acp$en {
	AppLocalizations$acp$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Couldn't start {cliName: String}. Make sure the CLI is installed and try again.'
	String chatLaunchFailed({required String cliName}) => 'Couldn\'t start ${cliName}. Make sure the CLI is installed and try again.';

	/// en: 'The agent isn't logged in. Sign in under Settings → Providers, then try again.'
	String get chatNotLoggedIn => 'The agent isn\'t logged in. Sign in under Settings → Providers, then try again.';

	/// en: '{cliName: String} exited unexpectedly'
	String chatProcessExited({required String cliName}) => '${cliName} exited unexpectedly';

	/// en: 'Couldn't open the {cliName: String} session.'
	String chatSessionOpenFailed({required String cliName}) => 'Couldn\'t open the ${cliName} session.';

	/// en: 'This turn failed'
	String get chatTurnFailed => 'This turn failed';

	/// en: 'Could not start the Claude ACP adapter (claude-agent-acp). Install it and try again.'
	String get launchFailedAdapter => 'Could not start the Claude ACP adapter (claude-agent-acp). Install it and try again.';

	/// en: 'This CLI version does not support ACP chat mode. Update the CLI and try again.'
	String get launchFailedVersion => 'This CLI version does not support ACP chat mode. Update the CLI and try again.';

	/// en: 'Agent model'
	String get modelSectionAgent => 'Agent model';

	/// en: 'Launch config'
	String get modelSectionLaunch => 'Launch config';

	/// en: 'Couldn't switch the ACP model. Try again.'
	String get modelSwitchFailed => 'Couldn\'t switch the ACP model. Try again.';

	/// en: 'Ask'
	String get permissionAskLabel => 'Ask';

	/// en: 'Full access'
	String get permissionFullAccessLabel => 'Full access';
}

// Path: agent
class AppLocalizations$agent$en {
	AppLocalizations$agent$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Agent preset'
	String get agent => 'Agent preset';

	/// en: 'Couldn't submit your answer. Try again or answer in the Terminal.'
	String get askAnswerFailed => 'Couldn\'t submit your answer. Try again or answer in the Terminal.';

	/// en: 'Answer in terminal'
	String get askAnswerInTerminal => 'Answer in terminal';

	/// en: 'Cancel question'
	String get askCancelQuestion => 'Cancel question';

	/// en: 'Continue'
	String get askContinue => 'Continue';

	/// en: 'Enter your answer…'
	String get askCustomAnswerHint => 'Enter your answer…';

	/// en: 'Esc to cancel'
	String get askEscToCancel => 'Esc to cancel';

	/// en: 'Ignore'
	String get askIgnore => 'Ignore';

	/// en: 'Use Tab / ↑↓ to select, Enter or Space to confirm'
	String get askKeyboardHint => 'Use Tab / ↑↓ to select, Enter or Space to confirm';

	/// en: 'Q{index: int}'
	String askQuestionTabFallback({required int index}) => 'Q${index}';

	/// en: 'Submit'
	String get askSubmitAnswers => 'Submit';

	/// en: 'Terminal is disconnected. Reconnect or answer in the Terminal.'
	String get askTerminalDisconnected => 'Terminal is disconnected. Reconnect or answer in the Terminal.';

	/// en: 'Agent is asking you a question'
	String get askUserQuestionTitle => 'Agent is asking you a question';

	/// en: 'Custom…'
	String get builtInCustom => 'Custom…';

	/// en: 'Default'
	String get builtInNone => 'Default';

	/// en: 'Which agent role this member uses; shapes behavior and capabilities.'
	String get builtInSubtitle => 'Which agent role this member uses; shapes behavior and capabilities.';

	/// en: 'e.g. Explore, Plan, or a custom type'
	String get claudeTypeHint => 'e.g. Explore, Plan, or a custom type';

	/// en: 'Written to the Claude team roster as agentType; leave empty to use the member id.'
	String get claudeTypeSubtitle => 'Written to the Claude team roster as agentType; leave empty to use the member id.';

	/// en: 'Custom agent id'
	String get customIdHint => 'Custom agent id';

	/// en: 'Passed as flashskyai --agent; pick a built-in or custom sub-agent.'
	String get flashskyaiPresetSubtitle => 'Passed as flashskyai --agent; pick a built-in or custom sub-agent.';

	/// en: 'Always allow {rule}'
	String permissionAlwaysAllowRule({required Object rule}) => 'Always allow ${rule}';

	/// en: 'This agent needs confirmation in the Terminal.'
	String get permissionAttentionBanner => 'This agent needs confirmation in the Terminal.';

	/// en: 'Open Terminal'
	String get permissionOpenTerminal => 'Open Terminal';

	/// en: '{cliName: String} needs your permission'
	String permissionTitle({required String cliName}) => '${cliName} needs your permission';

	/// en: 'Needs your permission'
	String get permissionTitleGeneric => 'Needs your permission';
}

// Path: ai
class AppLocalizations$ai$en {
	AppLocalizations$ai$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'CLI'
	String get featureCliLabel => 'CLI';

	/// en: 'Used by the ✨ button in the source control panel.'
	String get featureCommitMessageSubtitle => 'Used by the ✨ button in the source control panel.';

	/// en: 'Commit message generation'
	String get featureCommitMessageTitle => 'Commit message generation';

	/// en: '{cli: String} · {provider: String} · {model: String}'
	String featureConfigSummary({required String cli, required String provider, required String model}) => '${cli} · ${provider} · ${model}';

	/// en: 'Effort'
	String get featureEffortLabel => 'Effort';

	/// en: 'Model'
	String get featureModelLabel => 'Model';

	/// en: 'Used when generating a team from a description.'
	String get featureTeamGenerateSubtitle => 'Used when generating a team from a description.';

	/// en: 'Team configuration generation'
	String get featureTeamGenerateTitle => 'Team configuration generation';

	/// en: 'AI Features'
	String get features => 'AI Features';

	/// en: 'Choose which CLI provider, model, and effort each AI feature uses.'
	String get featuresPageSubtitle => 'Choose which CLI provider, model, and effort each AI feature uses.';

	/// en: 'Message cancelled'
	String get messageCancelled => 'Message cancelled';

	/// en: 'Cancelled tool'
	String get messageCancelledTool => 'Cancelled tool';

	/// en: 'Copied'
	String get messageCopied => 'Copied';

	/// en: 'Export Markdown'
	String get messageExportMarkdown => 'Export Markdown';

	/// en: 'Message incomplete'
	String get messageIncomplete => 'Message incomplete';

	/// en: 'Reasoning'
	String get messageReasoning => 'Reasoning';

	/// en: 'Scroll to bottom'
	String get messageScrollToBottom => 'Scroll to bottom';

	/// en: 'Show less'
	String get messageShowLess => 'Show less';

	/// en: 'Show more'
	String get messageShowMore => 'Show more';

	/// en: '(one) {ran 1 command} (other) {ran {count: int} commands}'
	String messageThinkingCommands({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'ran 1 command',
		other: 'ran ${count} commands',
	);

	/// en: '(one) {edited 1 file} (other) {edited {count: int} files}'
	String messageThinkingEditedFiles({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'edited 1 file',
		other: 'edited ${count} files',
	);

	/// en: '(one) {explored 1 file} (other) {explored {count: int} files}'
	String messageThinkingExploredFiles({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'explored 1 file',
		other: 'explored ${count} files',
	);

	/// en: 'Thinking process'
	String get messageThinkingProcess => 'Thinking process';

	/// en: 'Thinking process · {steps: int} steps · {toolCalls: int} tool calls'
	String messageThinkingProcessStats({required int steps, required int toolCalls}) => 'Thinking process · ${steps} steps · ${toolCalls} tool calls';

	/// en: 'Thinking process · {count: int} steps'
	String messageThinkingProcessSteps({required int count}) => 'Thinking process · ${count} steps';

	/// en: ', '
	String get messageThinkingProcessSummarySeparator => ', ';

	/// en: '(one) {1 search} (other) {{count: int} searches}'
	String messageThinkingSearches({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '1 search',
		other: '${count} searches',
	);

	/// en: 'Result'
	String get messageToolResult => 'Result';

	/// en: 'Used {count} tools'
	String messageToolsUsed({required Object count}) => 'Used ${count} tools';

	/// en: 'Used tool'
	String get messageUsedTool => 'Used tool';

	/// en: 'Could not find file: {path: String}'
	String toolFileNotFound({required String path}) => 'Could not find file: ${path}';
}

// Path: antigravity
class AppLocalizations$antigravity$en {
	AppLocalizations$antigravity$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Antigravity sign-in failed.'
	String get credentialsActionFailed => 'Antigravity sign-in failed.';

	/// en: 'Cancel'
	String get credentialsCancel => 'Cancel';

	/// en: 'Done'
	String get credentialsDone => 'Done';

	/// en: 'Sign in'
	String get credentialsLogin => 'Sign in';

	/// en: 'Antigravity exited. Close this dialog and start the sign-in again.'
	String get credentialsLoginExited => 'Antigravity exited. Close this dialog and start the sign-in again.';

	/// en: 'Could not start the login terminal: {error: String}'
	String credentialsLoginFailed({required String error}) => 'Could not start the login terminal: ${error}';

	/// en: 'Complete the Google sign-in in the terminal below, then press Done. Antigravity keeps the account in the OS keyring, so the account is shared by all Antigravity sessions and every official Antigravity provider row.'
	String get credentialsLoginIntro => 'Complete the Google sign-in in the terminal below, then press Done. Antigravity keeps the account in the OS keyring, so the account is shared by all Antigravity sessions and every official Antigravity provider row.';

	/// en: 'Starting Antigravity…'
	String get credentialsLoginStarting => 'Starting Antigravity…';

	/// en: 'Sign in to Antigravity'
	String get credentialsLoginTitle => 'Sign in to Antigravity';

	/// en: 'Antigravity did not confirm the sign-in (agy models failed). Finish the sign-in, then press Done again.'
	String get credentialsLoginVerifyFailed => 'Antigravity did not confirm the sign-in (agy models failed). Finish the sign-in, then press Done again.';

	/// en: 'Retry'
	String get credentialsRetry => 'Retry';

	/// en: 'Signed in to Antigravity.'
	String get credentialsSignedIn => 'Signed in to Antigravity.';
}

// Path: app
class AppLocalizations$app$en {
	AppLocalizations$app$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Search…'
	String get dropdownSearchHint => 'Search…';

	/// en: 'No results found.'
	String get dropdownSearchNoResults => 'No results found.';

	/// en: 'App rail'
	String get rail => 'App rail';

	/// en: 'Chat'
	String get railChat => 'Chat';

	/// en: 'Config'
	String get railConfig => 'Config';

	/// en: 'Runs'
	String get railRuns => 'Runs';

	/// en: 'TeamPilot'
	String get title => 'TeamPilot';

	/// en: 'Auto-check for updates'
	String get updateAutoCheck => 'Auto-check for updates';

	/// en: 'Check GitHub for a newer version each time the app starts.'
	String get updateAutoCheckHint => 'Check GitHub for a newer version each time the app starts.';

	/// en: 'Download in browser'
	String get updateBrowserDownload => 'Download in browser';

	/// en: 'Failed to open browser: {error: String}'
	String updateBrowserOpenFailed({required String error}) => 'Failed to open browser: ${error}';

	/// en: 'Opened download link in the browser'
	String get updateBrowserOpened => 'Opened download link in the browser';

	/// en: 'Could not open download link'
	String get updateCannotOpenDownloadLink => 'Could not open download link';

	/// en: 'Updates'
	String get updateChangelogDefaultSection => 'Updates';

	/// en: 'What's new'
	String get updateChangelogTitle => 'What\'s new';

	/// en: 'Check for updates'
	String get updateCheck => 'Check for updates';

	/// en: 'New version available'
	String get updateDialogTitle => 'New version available';

	/// en: 'Download complete'
	String get updateDownloadComplete => 'Download complete';

	/// en: 'Error while downloading: {error: String}'
	String updateDownloadError({required String error}) => 'Error while downloading: ${error}';

	/// en: 'Download failed'
	String get updateDownloadFailed => 'Download failed';

	/// en: 'Download in background'
	String get updateDownloadInBackground => 'Download in background';

	/// en: 'Download and install'
	String get updateDownloadInstall => 'Download and install';

	/// en: 'Download now'
	String get updateDownloadNow => 'Download now';

	/// en: 'Starting download…'
	String get updateDownloadStarting => 'Starting download…';

	/// en: 'Downloading update…'
	String get updateDownloading => 'Downloading update…';

	/// en: 'Installation complete'
	String get updateInstallComplete => 'Installation complete';

	/// en: 'Install failed: {message: String}'
	String updateInstallFailed({required String message}) => 'Install failed: ${message}';

	/// en: 'Install returned no result'
	String get updateInstallNoResult => 'Install returned no result';

	/// en: 'Install now'
	String get updateInstallNow => 'Install now';

	/// en: 'Installing update…'
	String get updateInstalling => 'Installing update…';

	/// en: 'Invalid package path'
	String get updateInvalidPackagePath => 'Invalid package path';

	/// en: 'Later'
	String get updateLater => 'Later';

	/// en: 'Latest version'
	String get updateLatestVersion => 'Latest version';

	/// en: 'Version {version: String} available'
	String updateNewVersion({required String version}) => 'Version ${version} available';

	/// en: 'Package type does not match this system'
	String get updatePackagePlatformMismatch => 'Package type does not match this system';

	/// en: 'Ready to download'
	String get updateReadyToDownload => 'Ready to download';

	/// en: 'This link must be downloaded in the browser'
	String get updateRedirectBrowserOnly => 'This link must be downloaded in the browser';

	/// en: 'Use a release build for in-app installation'
	String get updateReleaseBuildRequired => 'Use a release build for in-app installation';

	/// en: 'Resolving download link…'
	String get updateResolvingDownloadUrl => 'Resolving download link…';

	/// en: 'Skip this version'
	String get updateSkipVersion => 'Skip this version';

	/// en: 'Unknown'
	String get updateUnknownVersion => 'Unknown';

	/// en: 'You are on the latest version.'
	String get updateUpToDate => 'You are on the latest version.';

	/// en: 'View release on GitHub'
	String get updateViewRelease => 'View release on GitHub';

	/// en: 'Releases'
	String get updateViewReleases => 'Releases';
}

// Path: appProvider
class AppLocalizations$appProvider$en {
	AppLocalizations$appProvider$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Advanced JSON editor'
	String get advancedJson => 'Advanced JSON editor';

	/// en: 'Advanced options'
	String get advancedOptions => 'Advanced options';

	/// en: 'Leave blank to keep the existing key'
	String get apiKeyEditHint => 'Leave blank to keep the existing key';

	/// en: 'TeamPilot stores unified providers here; team launches generate per-tool configs.'
	String get catalogHint => 'TeamPilot stores unified providers here; team launches generate per-tool configs.';

	/// en: 'App provider catalog'
	String get catalogLabel => 'App provider catalog';

	/// en: 'ANTHROPIC_API_KEY'
	String get claudeAuthApiKey => 'ANTHROPIC_API_KEY';

	/// en: 'Authentication field'
	String get claudeAuthField => 'Authentication field';

	/// en: 'Select the authentication environment variable written to settings.'
	String get claudeAuthFieldHint => 'Select the authentication environment variable written to settings.';

	/// en: 'ANTHROPIC_AUTH_TOKEN (default)'
	String get claudeAuthTokenDefault => 'ANTHROPIC_AUTH_TOKEN (default)';

	/// en: 'OAuth credential source'
	String get claudeCredentialBinding => 'OAuth credential source';

	/// en: 'Isolated copy (TeamPilot only)'
	String get claudeCredentialBindingIsolated => 'Isolated copy (TeamPilot only)';

	/// en: 'Keeps a separate credential copy under TeamPilot. Use when this provider must not share login with global Claude Code.'
	String get claudeCredentialBindingIsolatedHint => 'Keeps a separate credential copy under TeamPilot. Use when this provider must not share login with global Claude Code.';

	/// en: 'Follow global (~/.claude)'
	String get claudeCredentialBindingLinked => 'Follow global (~/.claude)';

	/// en: 'Shares the same OAuth session as Claude Code in your terminal. Refreshes stay in sync.'
	String get claudeCredentialBindingLinkedHint => 'Shares the same OAuth session as Claude Code in your terminal. Refreshes stay in sync.';

	/// en: 'No secret-backed balance entries yet'
	String get credentialLinkEmpty => 'No secret-backed balance entries yet';

	/// en: 'API key source'
	String get credentialLinkMode => 'API key source';

	/// en: 'Use own API key'
	String get credentialLinkOwnKey => 'Use own API key';

	/// en: 'Using secret of {entry}'
	String credentialLinkedTo({required Object entry}) => 'Using secret of ${entry}';

	/// en: 'Display name'
	String get displayName => 'Display name';

	/// en: 'Enabled tools'
	String get enabledTools => 'Enabled tools';

	/// en: 'Import'
	String get import => 'Import';

	/// en: 'No providers found to import.'
	String get importNothing => 'No providers found to import.';

	/// en: 'Imported {count: int} providers. Mirrored {mirrored: int} to FlashskyAI, skipped {skipped: int} existing.'
	String importSuccess({required int count, required int mirrored, required int skipped}) => 'Imported ${count} providers. Mirrored ${mirrored} to FlashskyAI, skipped ${skipped} existing.';

	/// en: 'Internal id: {id: String}'
	String internalIdPreview({required String id}) => 'Internal id: ${id}';

	/// en: 'Enter custom model ID'
	String get modelEnterCustom => 'Enter custom model ID';

	/// en: 'Choose from list'
	String get modelPickFromList => 'Choose from list';

	/// en: 'Subscription'
	String get opencodeSubscription => 'Subscription';

	/// en: 'Free models only. Bind OpenCode Go to use subscription models.'
	String get opencodeSubscriptionOff => 'Free models only. Bind OpenCode Go to use subscription models.';

	/// en: 'OpenCode Go bound — subscription and free models are both available.'
	String get opencodeSubscriptionOn => 'OpenCode Go bound — subscription and free models are both available.';

	/// en: 'Custom'
	String get presetCustom => 'Custom';

	/// en: 'Preset'
	String get presetLabel => 'Preset';

	/// en: 'None'
	String get teamNone => 'None';

	/// en: 'Tool providers for this team'
	String get teamToolSection => 'Tool providers for this team';

	/// en: 'Select which unified provider each tool uses when this team starts.'
	String get teamToolSubtitle => 'Select which unified provider each tool uses when this team starts.';

	/// en: 'Antigravity'
	String get toolAntigravity => 'Antigravity';

	/// en: 'Claude Code'
	String get toolClaude => 'Claude Code';

	/// en: 'CodeBuddy'
	String get toolCodebuddy => 'CodeBuddy';

	/// en: 'Codex'
	String get toolCodex => 'Codex';

	/// en: 'Cursor'
	String get toolCursor => 'Cursor';

	/// en: 'FlashskyAI'
	String get toolFlashskyai => 'FlashskyAI';

	/// en: 'Gemini CLI'
	String get toolGemini => 'Gemini CLI';

	/// en: 'OpenCode'
	String get toolOpencode => 'OpenCode';

	/// en: 'Qoder'
	String get toolQoder => 'Qoder';

	/// en: 'Qoder CN'
	String get toolQoderCn => 'Qoder CN';

	/// en: 'Website'
	String get website => 'Website';

	/// en: 'Grok CLI'
	String get toolGrok => 'Grok CLI';
}

// Path: automations
class AppLocalizations$automations$en {
	AppLocalizations$automations$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Bound session'
	String get boundSession => 'Bound session';

	/// en: 'A session is bound after the first run'
	String get boundSessionPending => 'A session is bound after the first run';

	/// en: 'Session unavailable — switch or unbind'
	String get boundSessionUnavailable => 'Session unavailable — switch or unbind';

	/// en: 'Catch up once after startup'
	String get catchUpOnce => 'Catch up once after startup';

	/// en: 'CLI'
	String get cli => 'CLI';

	/// en: 'Command'
	String get command => 'Command';

	/// en: 'Runs only while TeamPilot is running. Missed runs older than the grace window are skipped unless catch-up is on.'
	String get commandHelp => 'Runs only while TeamPilot is running. Missed runs older than the grace window are skipped unless catch-up is on.';

	/// en: 'Command is required'
	String get commandRequired => 'Command is required';

	/// en: 'Timeout (seconds)'
	String get commandTimeout => 'Timeout (seconds)';

	/// en: 'Timeout must be a whole number of seconds'
	String get commandTimeoutInvalid => 'Timeout must be a whole number of seconds';

	/// en: 'Timeout must be between 30 and 1800 seconds'
	String get commandTimeoutRange => 'Timeout must be between 30 and 1800 seconds';

	/// en: 'Command must be at most 2000 characters'
	String get commandTooLong => 'Command must be at most 2000 characters';

	/// en: 'Working directory'
	String get commandWorkingDirectory => 'Working directory';

	/// en: 'Workspace default folder'
	String get commandWorkingDirectoryMain => 'Workspace default folder';

	/// en: 'Scheduled message'
	String get compactTitle => 'Scheduled message';

	/// en: 'Custom'
	String get countdownCustom => 'Custom';

	/// en: '{hours: int} h'
	String countdownHours({required int hours}) => '${hours} h';

	/// en: '{minutes: int} min'
	String countdownMinutes({required int minutes}) => '${minutes} min';

	/// en: 'Runs at {dateTime: String}'
	String countdownPreview({required String dateTime}) => 'Runs at ${dateTime}';

	/// en: 'New automation'
	String get createTitle => 'New automation';

	/// en: 'Cron expression'
	String get customCron => 'Cron expression';

	/// en: 'Friday'
	String get dayFriday => 'Friday';

	/// en: 'Monday'
	String get dayMonday => 'Monday';

	/// en: 'Saturday'
	String get daySaturday => 'Saturday';

	/// en: 'Sunday'
	String get daySunday => 'Sunday';

	/// en: 'Thursday'
	String get dayThursday => 'Thursday';

	/// en: 'Tuesday'
	String get dayTuesday => 'Tuesday';

	/// en: 'Wednesday'
	String get dayWednesday => 'Wednesday';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Delete this automation?'
	String get deleteConfirm => 'Delete this automation?';

	/// en: 'Dispatch failed'
	String get dispatchFailed => 'Dispatch failed';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Edit automation'
	String get editTitle => 'Edit automation';

	/// en: 'No automations yet'
	String get empty => 'No automations yet';

	/// en: 'Enabled'
	String get enabled => 'Enabled';

	/// en: 'Exit code {code: int}'
	String exitCode({required int code}) => 'Exit code ${code}';

	/// en: 'All actions'
	String get filterActionAll => 'All actions';

	/// en: 'Action type'
	String get filterActionLabel => 'Action type';

	/// en: 'All'
	String get filterAll => 'All';

	/// en: 'Disabled only'
	String get filterDisabled => 'Disabled only';

	/// en: 'Enabled only'
	String get filterEnabled => 'Enabled only';

	/// en: 'Launch prompts'
	String get filterLaunchPrompt => 'Launch prompts';

	/// en: 'Scheduled messages'
	String get filterScheduledMessage => 'Scheduled messages';

	/// en: 'Status'
	String get filterStatusLabel => 'Status';

	/// en: 'Hide filters'
	String get hideFilter => 'Hide filters';

	/// en: 'Invalid cron expression (5 fields required)'
	String get invalidCron => 'Invalid cron expression (5 fields required)';

	/// Validation error for run limit field
	///
	/// en: 'Run limit must be a positive number'
	String get invalidMaxRunCount => 'Run limit must be a positive number';

	/// en: 'Time must be HH:mm'
	String get invalidTime => 'Time must be HH:mm';

	/// Simple vs team launch mode for automation editor
	///
	/// en: 'Conversation mode'
	String get launchMode => 'Conversation mode';

	/// Deprecated — use automationsLaunchMode
	///
	/// en: 'Launch identity'
	String get launchProfile => 'Launch identity';

	/// Workspace project folder for launch-prompt automations
	///
	/// en: 'Project'
	String get launchProject => 'Project';

	/// Git worktree cwd for launch-prompt automations
	///
	/// en: 'Worktree'
	String get launchWorktree => 'Worktree';

	/// en: 'Manage all scheduled tasks'
	String get manageAll => 'Manage all scheduled tasks';

	/// en: 'Manage scheduled messages'
	String get manageSessionContextMenu => 'Manage scheduled messages';

	/// Label for optional max automation run count
	///
	/// en: 'Run limit'
	String get maxRunCount => 'Run limit';

	/// Hint for run limit field
	///
	/// en: 'Leave empty for unlimited'
	String get maxRunCountHint => 'Leave empty for unlimited';

	/// en: 'Message'
	String get message => 'Message';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'New automation'
	String get kNew => 'New automation';

	/// en: 'Next run: {time: String}'
	String nextRun({required String time}) => 'Next run: ${time}';

	/// en: 'No upcoming run'
	String get nextRunNone => 'No upcoming run';

	/// en: 'The selected preset does not match the bound session's CLI.'
	String get presetCliMismatch => 'The selected preset does not match the bound session\'s CLI.';

	/// en: 'No presets available for this CLI.'
	String get presetEmptyForCli => 'No presets available for this CLI.';

	/// en: 'Bound to a session — only presets for that session's CLI are shown.'
	String get presetScopeHint => 'Bound to a session — only presets for that session\'s CLI are shown.';

	/// en: 'Reuse session'
	String get reuseSession => 'Reuse session';

	/// en: 'Reuses conversation {sessionId: String}'
	String reuseSessionListHint({required String sessionId}) => 'Reuses conversation ${sessionId}';

	/// en: 'Bound to session {sessionId: String}'
	String reuseSessionSubtitleBound({required String sessionId}) => 'Bound to session ${sessionId}';

	/// en: 'Each run opens a new conversation.'
	String get reuseSessionSubtitleOff => 'Each run opens a new conversation.';

	/// en: 'First run creates a conversation; later runs reuse it.'
	String get reuseSessionSubtitlePending => 'First run creates a conversation; later runs reuse it.';

	/// en: 'Ran {count: int} / {max: int}'
	String runCountLimited({required int count, required int max}) => 'Ran ${count} / ${max}';

	/// en: 'Ran {count: int} times'
	String runCountUnlimited({required int count}) => 'Ran ${count} times';

	/// en: 'Took {milliseconds: int} ms'
	String runDurationMilliseconds({required int milliseconds}) => 'Took ${milliseconds} ms';

	/// en: 'Took {seconds: int}s'
	String runDurationSeconds({required int seconds}) => 'Took ${seconds}s';

	/// en: 'Error: {error: String}'
	String runError({required String error}) => 'Error: ${error}';

	/// en: 'Run history'
	String get runHistory => 'Run history';

	/// en: 'No runs yet'
	String get runHistoryEmpty => 'No runs yet';

	/// en: 'Run now'
	String get runNow => 'Run now';

	/// en: 'Output truncated'
	String get runOutputTruncated => 'Output truncated';

	/// en: 'Completed'
	String get runStatusCompleted => 'Completed';

	/// en: 'Dispatched'
	String get runStatusDispatched => 'Dispatched';

	/// en: 'Dispatching'
	String get runStatusDispatching => 'Dispatching';

	/// en: 'Failed'
	String get runStatusFailed => 'Failed';

	/// en: 'Pending'
	String get runStatusPending => 'Pending';

	/// en: 'Skipped — missed window'
	String get runStatusSkippedMissed => 'Skipped — missed window';

	/// en: 'Skipped (still running)'
	String get runStatusSkippedOverlap => 'Skipped (still running)';

	/// en: 'Timed out'
	String get runStatusTimedOut => 'Timed out';

	/// en: 'stderr'
	String get runStderr => 'stderr';

	/// en: 'stdout'
	String get runStdout => 'stdout';

	/// en: 'Schedule'
	String get schedule => 'Schedule';

	/// en: 'Custom cron'
	String get scheduleCustom => 'Custom cron';

	/// en: 'Daily'
	String get scheduleDaily => 'Daily';

	/// en: 'Date'
	String get scheduleDate => 'Date';

	/// en: 'Hourly'
	String get scheduleHourly => 'Hourly';

	/// en: 'Countdown'
	String get scheduleModeCountdown => 'Countdown';

	/// en: 'Once'
	String get scheduleModeOnce => 'Once';

	/// en: 'Recurring'
	String get scheduleModeRecurring => 'Recurring';

	/// en: 'Once'
	String get scheduleOnce => 'Once';

	/// en: 'Choose a time in the future'
	String get schedulePastTime => 'Choose a time in the future';

	/// en: 'Daily at {time: String}'
	String scheduleSummaryDaily({required String time}) => 'Daily at ${time}';

	/// en: 'Hourly at :{minute: int}'
	String scheduleSummaryHourly({required int minute}) => 'Hourly at :${minute}';

	/// en: 'Once at {time: String}'
	String scheduleSummaryOnce({required String time}) => 'Once at ${time}';

	/// en: 'Weekdays at {time: String}'
	String scheduleSummaryWeekdays({required String time}) => 'Weekdays at ${time}';

	/// en: 'Weekly on {day: String} at {time: String}'
	String scheduleSummaryWeekly({required String day, required String time}) => 'Weekly on ${day} at ${time}';

	/// en: 'Type'
	String get scheduleType => 'Type';

	/// en: 'Weekdays'
	String get scheduleWeekdays => 'Weekdays';

	/// en: 'Weekly'
	String get scheduleWeekly => 'Weekly';

	/// en: 'Personal · {profile: String}'
	String scopeModePersonal({required String profile}) => 'Personal · ${profile}';

	/// en: 'Team · {team: String}'
	String scopeModeTeam({required String team}) => 'Team · ${team}';

	/// en: 'Personal · {preset: String}'
	String scopePersonal({required String preset}) => 'Personal · ${preset}';

	/// en: 'Scheduled message · {sessionId: String}'
	String scopeScheduledMessage({required String sessionId}) => 'Scheduled message · ${sessionId}';

	/// en: 'Team · {team: String} · {member: String}'
	String scopeTeam({required String team, required String member}) => 'Team · ${team} · ${member}';

	/// en: 'Team · {member: String}'
	String scopeTeamMember({required String member}) => 'Team · ${member}';

	/// en: 'Scheduled message…'
	String get sessionContextMenu => 'Scheduled message…';

	/// en: '{title: String} — scheduled message'
	String sessionDefaultName({required String title}) => '${title} — scheduled message';

	/// en: 'No sessions available to bind'
	String get sessionPickerEmpty => 'No sessions available to bind';

	/// en: 'Select a session'
	String get sessionPickerTitle => 'Select a session';

	/// en: 'Session title'
	String get sessionTitle => 'Session title';

	/// en: 'Leave empty to use the automation name.'
	String get sessionTitleHint => 'Leave empty to use the automation name.';

	/// en: 'Show filters'
	String get showFilter => 'Show filters';

	/// en: 'Scheduled tasks'
	String get sidebarTitle => 'Scheduled tasks';

	/// en: 'Skipped — session unavailable'
	String get skippedUnavailable => 'Skipped — session unavailable';

	/// en: 'Sort automations'
	String get sort => 'Sort automations';

	/// en: 'Name (A–Z)'
	String get sortNameAsc => 'Name (A–Z)';

	/// en: 'Name (Z–A)'
	String get sortNameDesc => 'Name (Z–A)';

	/// en: 'Next run'
	String get sortNextRun => 'Next run';

	/// en: 'Recently updated'
	String get sortRecentlyUpdated => 'Recently updated';

	/// en: 'No active scheduled tasks'
	String get statusBarEmpty => 'No active scheduled tasks';

	/// Subtitle for automations management page
	///
	/// en: 'Schedule messages and prompts across workspaces and sessions.'
	String get subtitle => 'Schedule messages and prompts across workspaces and sessions.';

	/// en: 'Switch session'
	String get switchSession => 'Switch session';

	/// en: 'Target member'
	String get targetMember => 'Target member';

	/// en: 'Time'
	String get time => 'Time';

	/// Title for automations management UI
	///
	/// en: 'Automations'
	String get title => 'Automations';

	/// en: 'Unbind'
	String get unbindSession => 'Unbind';

	/// en: 'Name and message are required'
	String get validationRequired => 'Name and message are required';
}

// Path: catalog
class AppLocalizations$catalog$en {
	AppLocalizations$catalog$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: '{name: String}, from {source: String}'
	String cardAccessibilityLabel({required String name, required String source}) => '${name}, from ${source}';

	/// en: 'No data'
	String get metricMissing => 'No data';

	/// en: 'No data available'
	String get metricMissingTooltip => 'No data available';

	/// en: 'Name'
	String get metricName => 'Name';

	/// en: 'Published'
	String get metricPublished => 'Published';

	/// en: 'Rating'
	String get metricRating => 'Rating';

	/// en: 'Updated'
	String get metricUpdated => 'Updated';

	/// en: '{label: String}: no data available'
	String missingMetricAccessibilityLabel({required String label}) => '${label}: no data available';

	/// en: 'Refresh catalog'
	String get refreshAccessibilityLabel => 'Refresh catalog';

	/// en: 'Sort catalog entries'
	String get sortAccessibilityLabel => 'Sort catalog entries';

	/// en: 'Most adopted'
	String get sortAdoption => 'Most adopted';

	/// en: 'Name'
	String get sortName => 'Name';

	/// en: 'Recently published'
	String get sortPublished => 'Recently published';

	/// en: 'Highest rated'
	String get sortRating => 'Highest rated';

	/// en: 'Recently updated'
	String get sortUpdated => 'Recently updated';

	/// en: '{count: int} catalog source(s) failed to load'
	String sourceWarningAccessibilityLabel({required int count}) => '${count} catalog source(s) failed to load';

	/// en: '{source: String}: {error: String}'
	String sourceWarningEntry({required String source, required String error}) => '${source}: ${error}';

	/// en: 'Some catalog sources failed to load'
	String get sourceWarningLabel => 'Some catalog sources failed to load';
}

// Path: chat
class AppLocalizations$chat$en {
	AppLocalizations$chat$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'How oversized code blocks render in chat.'
	String get codeBlockModeDescription => 'How oversized code blocks render in chat.';

	/// en: 'Code blocks in chat'
	String get codeBlockModeTitle => 'Code blocks in chat';

	/// en: 'Close find'
	String get findClose => 'Close find';

	/// en: 'Find in conversation'
	String get findHint => 'Find in conversation';

	/// en: 'Match case'
	String get findMatchCase => 'Match case';

	/// en: 'Next match'
	String get findNext => 'Next match';

	/// en: 'No matches'
	String get findNoResults => 'No matches';

	/// en: 'Previous match'
	String get findPrevious => 'Previous match';

	/// en: 'Matches'
	String get findResults => 'Matches';

	/// en: 'Use regular expression'
	String get findUseRegex => 'Use regular expression';

	/// en: 'Match whole word'
	String get findWholeWord => 'Match whole word';

	/// en: 'Write a prompt for team-lead...'
	String get hintText => 'Write a prompt for team-lead...';

	/// en: 'When off (default), sending from Chat (new conversation or continue) stays on the Chat view while the terminal runs in the background. When on, switch to the Terminal after send.'
	String get submitSwitchesToTerminalDescription => 'When off (default), sending from Chat (new conversation or continue) stays on the Chat view while the terminal runs in the background. When on, switch to the Terminal after send.';

	/// en: 'Switch to Terminal after Chat send'
	String get submitSwitchesToTerminalTitle => 'Switch to Terminal after Chat send';

	/// en: 'To:'
	String get to => 'To:';

	/// en: 'How oversized user messages render in chat.'
	String get userMessageModeDescription => 'How oversized user messages render in chat.';

	/// en: 'User messages'
	String get userMessageModeTitle => 'User messages';

	/// en: 'Empty message'
	String get userMessageRailEmptyPreview => 'Empty message';

	/// en: 'User message {index: int} of {total: int}'
	String userMessageRailSemanticLabel({required int index, required int total}) => 'User message ${index} of ${total}';
}

// Path: claude
class AppLocalizations$claude$en {
	AppLocalizations$claude$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Absolute path to the Claude Code executable. Leave empty to use the one on PATH.'
	String get cliExecutablePathDescription => 'Absolute path to the Claude Code executable. Leave empty to use the one on PATH.';

	/// en: 'Absolute path to Claude Code on the remote SSH host. Leave empty to resolve claude from the remote PATH.'
	String get cliExecutablePathDescriptionSsh => 'Absolute path to Claude Code on the remote SSH host. Leave empty to resolve claude from the remote PATH.';

	/// en: 'Claude Code CLI path'
	String get cliExecutablePathLabel => 'Claude Code CLI path';

	/// en: 'Claude Official credentials are missing for this team provider. Sign in from Providers settings.'
	String get launchCredentialsMissingWarning => 'Claude Official credentials are missing for this team provider. Sign in from Providers settings.';

	/// en: 'Could not update credentials'
	String get officialCredentialsActionFailed => 'Could not update credentials';

	/// en: 'Credentials updated'
	String get officialCredentialsActionSuccess => 'Credentials updated';

	/// en: 'Import file…'
	String get officialCredentialsImportFile => 'Import file…';

	/// en: 'Import from ~/.claude'
	String get officialCredentialsImportGlobal => 'Import from ~/.claude';

	/// en: 'Sign in with Claude'
	String get officialCredentialsLogin => 'Sign in with Claude';

	/// en: 'No credentials saved for this provider'
	String get officialCredentialsMissing => 'No credentials saved for this provider';

	/// en: 'Credentials ready'
	String get officialCredentialsReady => 'Credentials ready';

	/// en: 'Sign out'
	String get officialCredentialsRevoke => 'Sign out';

	/// en: 'Sign out and remove saved credentials for {name: String}?'
	String officialCredentialsRevokeConfirm({required String name}) => 'Sign out and remove saved credentials for ${name}?';

	/// en: 'Claude Official login'
	String get officialCredentialsTitle => 'Claude Official login';
}

// Path: cli
class AppLocalizations$cli$en {
	AppLocalizations$cli$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'CLI'
	String get config => 'CLI';

	/// Section header for AI CLI tools in CLI config page
	///
	/// en: 'AI CLI'
	String get configAiCliGroup => 'AI CLI';

	/// en: 'Configure AI agent CLI executable paths and install missing tools.'
	String get configPageSubtitle => 'Configure AI agent CLI executable paths and install missing tools.';

	/// Section header for toolchain tools (git, node) in CLI config page
	///
	/// en: 'Toolchain'
	String get configToolchainGroup => 'Toolchain';

	/// Label for Cursor CLI executable path setting
	///
	/// en: 'Cursor CLI path'
	String get cursorExecutablePathLabel => 'Cursor CLI path';

	/// en: 'Apply'
	String get executablePathApply => 'Apply';

	/// en: 'Browse…'
	String get executablePathBrowse => 'Browse…';

	/// en: 'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.'
	String get executablePathDescription => 'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.';

	/// en: 'Absolute path to the {cli: String} executable. Leave empty to use the one on PATH.'
	String executablePathDescriptionFor({required String cli}) => 'Absolute path to the ${cli} executable. Leave empty to use the one on PATH.';

	/// en: 'Absolute path to flashskyai on the remote SSH host. Leave empty to auto-discover over SSH.'
	String get executablePathDescriptionSsh => 'Absolute path to flashskyai on the remote SSH host. Leave empty to auto-discover over SSH.';

	/// en: 'Absolute path to {cli: String} on the remote SSH host. Leave empty to auto-discover over SSH.'
	String executablePathDescriptionSshFor({required String cli}) => 'Absolute path to ${cli} on the remote SSH host. Leave empty to auto-discover over SSH.';

	/// en: 'flashskyai CLI path'
	String get executablePathLabel => 'flashskyai CLI path';

	/// en: '{cli: String} CLI path'
	String executablePathLabelFor({required String cli}) => '${cli} CLI path';

	/// en: 'Locate'
	String get executablePathLocate => 'Locate';

	/// en: 'Could not find {name: String} on PATH.'
	String executablePathLocateFailed({required String name}) => 'Could not find ${name} on PATH.';

	/// en: 'Remote locate is not supported for this tool.'
	String get executablePathLocateRemoteUnsupported => 'Remote locate is not supported for this tool.';

	/// en: 'Located {name: String} at {path: String}.'
	String executablePathLocateSuccess({required String name, required String path}) => 'Located ${name} at ${path}.';

	/// en: 'Reset'
	String get executablePathReset => 'Reset';

	/// en: 'Using: '
	String get executablePathUsing => 'Using: ';

	/// en: 'Using PATH lookup'
	String get executablePathUsingFallback => 'Using PATH lookup';

	/// en: 'Install'
	String get installButton => 'Install';

	/// en: 'Installing…'
	String get installInstalling => 'Installing…';

	/// en: 'Installing Node.js…'
	String get installProgressBootstrappingNode => 'Installing Node.js…';

	/// en: 'Checking for npm…'
	String get installProgressCheckingNpm => 'Checking for npm…';

	/// en: 'Downloading adapter…'
	String get installProgressDownloading => 'Downloading adapter…';

	/// en: 'Extracting adapter…'
	String get installProgressExtracting => 'Extracting adapter…';

	/// en: 'Installing CLI…'
	String get installProgressInstallingCli => 'Installing CLI…';

	/// en: 'Locating CLI executable…'
	String get installProgressLocatingExecutable => 'Locating CLI executable…';

	/// en: 'Syncing remote workspace…'
	String get installProgressSyncingRemoteWorkspace => 'Syncing remote workspace…';

	/// en: 'Upgrading…'
	String get installUpgrading => 'Upgrading…';

	/// en: 'adapter not found'
	String get readinessAdapterMissing => 'adapter not found';

	/// en: 'Needs setup'
	String get readinessNeedsSetup => 'Needs setup';

	/// en: 'Ready'
	String get readinessReady => 'Ready';

	/// en: 'ACP'
	String get readinessRowAcp => 'ACP';

	/// en: 'CLI'
	String get readinessRowCli => 'CLI';

	/// en: 'Update available'
	String get readinessUpdateAvailable => 'Update available';

	/// en: 'uses CLI · acp'
	String get readinessUsesCli => 'uses CLI · acp';

	/// en: '—'
	String get readinessVersionUnknown => '—';

	/// en: '{completed: int}/{total: int}'
	String taskBoardCount({required int completed, required int total}) => '${completed}/${total}';

	/// en: '… +{count: int} more'
	String taskBoardMore({required int count}) => '… +${count} more';

	/// en: 'Show less'
	String get taskBoardShowLess => 'Show less';

	/// en: 'Tasks'
	String get taskBoardTitle => 'Tasks';

	/// en: 'Cancelled'
	String get taskStatusCancelled => 'Cancelled';

	/// en: 'Done'
	String get taskStatusCompleted => 'Done';

	/// en: 'In progress'
	String get taskStatusInProgress => 'In progress';

	/// en: 'Pending'
	String get taskStatusPending => 'Pending';

	/// en: 'Unknown'
	String get taskStatusUnknown => 'Unknown';

	/// en: 'New sessions default to chat (ACP)'
	String get transportDefaultChat => 'New sessions default to chat (ACP)';

	/// en: 'New sessions default to the terminal (PTY)'
	String get transportDefaultTerminal => 'New sessions default to the terminal (PTY)';

	/// en: 'Upgrade'
	String get upgradeButton => 'Upgrade';

	/// Machine card for the ACP proxy on a remote SSH host
	///
	/// en: 'Cloud keep-alive'
	String get acpProxyTitle => 'Cloud keep-alive';

	/// en: 'Keeps a cloud-model turn running after this device disconnects. Install and start it on this machine. Sending a message does not install it.'
	String get acpProxySubtitle => 'Keeps a cloud-model turn running after this device disconnects. Install and start it on this machine. Sending a message does not install it.';

	/// en: 'Start'
	String get acpProxyStart => 'Start';

	/// en: 'Checking the remote machine…'
	String get acpProxyChecking => 'Checking the remote machine…';

	/// en: 'Not installed'
	String get acpProxyMissing => 'Not installed';

	/// en: 'Installed, not running'
	String get acpProxyStopped => 'Installed, not running';

	/// en: 'Update available'
	String get acpProxyOutdated => 'Update available';

	/// en: 'Retry'
	String get acpProxyRetry => 'Retry';

	/// en: 'Select an SSH server before installing keep-alive.'
	String get acpProxyNoSsh => 'Select an SSH server before installing keep-alive.';
}

// Path: clone
class AppLocalizations$clone$en {
	AppLocalizations$clone$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Added {repo} to workspace {workspace}'
	String repositoryAddToExistingSucceeded({required Object repo, required Object workspace}) => 'Added ${repo} to workspace ${workspace}';

	/// en: 'Add to existing workspace…'
	String get repositoryAddToWorkspace => 'Add to existing workspace…';

	/// en: 'Clone cancelled: {repo}'
	String repositoryCancelled({required Object repo}) => 'Clone cancelled: ${repo}';

	/// en: 'Choose a workspace'
	String get repositoryChooseWorkspace => 'Choose a workspace';

	/// en: '{path} is ready.'
	String repositoryCompletedBody({required Object path}) => '${path} is ready.';

	/// en: 'Clone complete'
	String get repositoryCompletedTitle => 'Clone complete';

	/// en: 'New workspace'
	String get repositoryCreateWorkspace => 'New workspace';

	/// en: 'Folder already exists and is not empty'
	String get repositoryDestExists => 'Folder already exists and is not empty';

	/// en: 'Folder name'
	String get repositoryDirNameLabel => 'Folder name';

	/// en: 'Enter a folder name'
	String get repositoryDirNameRequired => 'Enter a folder name';

	/// en: 'Clone failed: {repo}'
	String repositoryFailed({required Object repo}) => 'Clone failed: ${repo}';

	/// en: 'git was not found on the selected target machine'
	String get repositoryGitMissing => 'git was not found on the selected target machine';

	/// en: 'Clone Repository…'
	String get repositoryMenu => 'Clone Repository…';

	/// en: 'Clone into folder'
	String get repositoryParentDirLabel => 'Clone into folder';

	/// en: 'Choose a destination folder'
	String get repositoryParentDirRequired => 'Choose a destination folder';

	/// en: 'Cloning {repo}'
	String repositoryProgressTitle({required Object repo}) => 'Cloning ${repo}';

	/// en: 'Cloning {url} started'
	String repositoryStarted({required Object url}) => 'Cloning ${url} started';

	/// en: 'Clone'
	String get repositorySubmit => 'Clone';

	/// en: 'Cloned {repo}'
	String repositorySucceeded({required Object repo}) => 'Cloned ${repo}';

	/// en: 'Clone to target'
	String get repositoryTargetLabel => 'Clone to target';

	/// en: 'Clone Repository'
	String get repositoryTitle => 'Clone Repository';

	/// en: 'https://github.com/owner/repo.git'
	String get repositoryUrlHint => 'https://github.com/owner/repo.git';

	/// en: 'Enter a valid git URL (https://, git@, git://, ssh://)'
	String get repositoryUrlInvalid => 'Enter a valid git URL (https://, git@, git://, ssh://)';

	/// en: 'Repository URL'
	String get repositoryUrlLabel => 'Repository URL';
}

// Path: codebuddy
class AppLocalizations$codebuddy$en {
	AppLocalizations$codebuddy$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'CodeBuddy sign-in failed.'
	String get credentialsActionFailed => 'CodeBuddy sign-in failed.';

	/// en: 'Cancel'
	String get credentialsCancel => 'Cancel';

	/// en: 'Done'
	String get credentialsDone => 'Done';

	/// en: 'Sign in'
	String get credentialsLogin => 'Sign in';

	/// en: 'CodeBuddy exited. Close this dialog and start the sign-in again.'
	String get credentialsLoginExited => 'CodeBuddy exited. Close this dialog and start the sign-in again.';

	/// en: 'Could not start the login terminal: {error: String}'
	String credentialsLoginFailed({required String error}) => 'Could not start the login terminal: ${error}';

	/// en: 'Complete the sign-in in the terminal below. If a login-method list appears, choose one first (e.g. WeChat / enterprise domain). The CLI may open a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.'
	String get credentialsLoginIntro => 'Complete the sign-in in the terminal below. If a login-method list appears, choose one first (e.g. WeChat / enterprise domain). The CLI may open a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.';

	/// en: 'Starting CodeBuddy…'
	String get credentialsLoginStarting => 'Starting CodeBuddy…';

	/// en: 'Sign in to CodeBuddy'
	String get credentialsLoginTitle => 'Sign in to CodeBuddy';

	/// en: 'Retry'
	String get credentialsRetry => 'Retry';

	/// en: 'Send /login'
	String get credentialsSendLogin => 'Send /login';

	/// en: 'Signed in to CodeBuddy.'
	String get credentialsSignedIn => 'Signed in to CodeBuddy.';
}

// Path: codex
class AppLocalizations$codex$en {
	AppLocalizations$codex$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Codex isn't logged in. Sign in with ChatGPT under Settings → Providers, or switch to an API key.'
	String get acpChatNotLoggedIn => 'Codex isn\'t logged in. Sign in with ChatGPT under Settings → Providers, or switch to an API key.';

	/// en: 'Could not start the Codex ACP adapter (codex-acp). Install it and try again.'
	String get acpLaunchFailedAdapter => 'Could not start the Codex ACP adapter (codex-acp). Install it and try again.';

	/// en: 'Could not update credentials'
	String get credentialsActionFailed => 'Could not update credentials';

	/// en: 'Credentials updated'
	String get credentialsActionSuccess => 'Credentials updated';

	/// en: 'Import auth.json…'
	String get credentialsImportFile => 'Import auth.json…';

	/// en: 'Import from ~/.codex'
	String get credentialsImportGlobal => 'Import from ~/.codex';

	/// en: 'Sign in with OpenAI'
	String get credentialsLogin => 'Sign in with OpenAI';

	/// en: 'Sign out'
	String get credentialsRevoke => 'Sign out';

	/// en: 'Sign out and remove saved credentials for {name: String}?'
	String credentialsRevokeConfirm({required String name}) => 'Sign out and remove saved credentials for ${name}?';
}

// Path: compose
class AppLocalizations$compose$en {
	AppLocalizations$compose$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Custom model ID…'
	String get cascadeCustomModelId => 'Custom model ID…';

	/// en: 'Custom model ID'
	String get cascadeCustomModelIdTitle => 'Custom model ID';

	/// en: 'Default'
	String get cascadeDefaultEffort => 'Default';

	/// en: 'No model catalog'
	String get cascadeNoModels => 'No model catalog';

	/// en: 'No providers configured'
	String get cascadeNoProviders => 'No providers configured';

	/// en: 'Presets'
	String get cascadePresets => 'Presets';

	/// en: 'Save current as preset…'
	String get cascadeSavePreset => 'Save current as preset…';

	/// en: 'Experimental'
	String get commandExperimental => 'Experimental';

	/// en: 'Native'
	String get commandNative => 'Native';

	/// en: 'Plugin'
	String get commandPlugin => 'Plugin';

	/// en: 'Compact the active conversation context.'
	String get nativeCommandCompact => 'Compact the active conversation context.';

	/// en: 'Keep a durable objective for long-running work.'
	String get nativeCommandGoal => 'Keep a durable objective for long-running work.';

	/// en: 'Show commands available in this CLI session.'
	String get nativeCommandHelp => 'Show commands available in this CLI session.';

	/// en: 'Switch the session into a planning workflow.'
	String get nativeCommandPlan => 'Switch the session into a planning workflow.';

	/// en: 'Edit pasted text'
	String get pasteClipEdit => 'Edit pasted text';

	/// en: 'Pasted text'
	String get pasteClipLabel => 'Pasted text';

	/// en: '{lines: int} lines'
	String pasteClipLines({required int lines}) => '${lines} lines';

	/// en: 'Remove pasted text'
	String get pasteClipRemove => 'Remove pasted text';

	/// en: 'Done'
	String get pasteEditorDone => 'Done';

	/// en: 'Remove'
	String get pasteEditorRemove => 'Remove';

	/// en: 'Edit pasted text · {lines: int} lines'
	String pasteEditorTitle({required int lines}) => 'Edit pasted text · ${lines} lines';
}

// Path: connect
class AppLocalizations$connect$en {
	AppLocalizations$connect$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Add address'
	String get addEndpoint => 'Add address';

	/// en: 'Add SSH addresses that are reachable outside this LAN.'
	String get advancedSubtitle => 'Add SSH addresses that are reachable outside this LAN.';

	/// en: 'Reachability'
	String get advancedTitle => 'Reachability';

	/// en: 'Scan a QR from desktop TeamPilot.'
	String get androidScanHint => 'Scan a QR from desktop TeamPilot.';

	/// en: 'Copy link'
	String get copyLink => 'Copy link';

	/// en: 'Connect could not refresh pairing. Try again.'
	String get error => 'Connect could not refresh pairing. Try again.';

	/// en: 'Host'
	String get extraHost => 'Host';

	/// en: 'Port'
	String get extraPort => 'Port';

	/// en: 'Network interface'
	String get interfaceLabel => 'Network interface';

	/// en: 'Every address needs a host and a port from 1 to 65535.'
	String get invalidEndpoint => 'Every address needs a host and a port from 1 to 65535.';

	/// en: 'LAN only'
	String get lanOnlyStatus => 'LAN only';

	/// en: 'Join the same Wi-Fi as this computer, or set a relay on the desktop first.'
	String get needLanOrRelay => 'Join the same Wi-Fi as this computer, or set a relay on the desktop first.';

	/// en: 'No non-loopback IPv4 network interface is available.'
	String get noNetworkAddress => 'No non-loopback IPv4 network interface is available.';

	/// en: 'No phones are paired yet.'
	String get noPairedDevices => 'No phones are paired yet.';

	/// en: 'Open settings'
	String get openSettings => 'Open settings';

	/// en: 'teampilot://pair-ssh?code=…'
	String get pairCodeHint => 'teampilot://pair-ssh?code=…';

	/// en: 'Code expired. Scan again.'
	String get pairExpired => 'Code expired. Scan again.';

	/// en: 'Could not pair with this desktop. Try again.'
	String get pairFailed => 'Could not pair with this desktop. Try again.';

	/// en: 'This pairing code is invalid.'
	String get pairInvalid => 'This pairing code is invalid.';

	/// en: 'Pair'
	String get pairNow => 'Pair';

	/// en: 'Scan the QR shown by desktop TeamPilot, or paste its pairing code.'
	String get pairSheetSubtitle => 'Scan the QR shown by desktop TeamPilot, or paste its pairing code.';

	/// en: 'Pair with a desktop'
	String get pairSheetTitle => 'Pair with a desktop';

	/// en: 'Update TeamPilot to scan this code.'
	String get pairUpdateApp => 'Update TeamPilot to scan this code.';

	/// en: 'Paired devices'
	String get pairedDevicesTitle => 'Paired devices';

	/// en: 'Pairing…'
	String get pairing => 'Pairing…';

	/// en: 'Paste code'
	String get pasteCode => 'Paste code';

	/// en: 'Tap the QR code to enlarge it for easier scanning.'
	String get qrEnlargeHint => 'Tap the QR code to enlarge it for easier scanning.';

	/// en: 'Regenerate'
	String get regenerate => 'Regenerate';

	/// en: 'Relay URL'
	String get relayUrl => 'Relay URL';

	/// en: 'Optional relay service URL'
	String get relayUrlHint => 'Optional relay service URL';

	/// en: 'LAN and remote'
	String get remoteReadyStatus => 'LAN and remote';

	/// en: 'Remove address'
	String get removeEndpoint => 'Remove address';

	/// en: 'The desktop has been upgraded — re-scan its pairing code to reconnect.'
	String get repairHint => 'The desktop has been upgraded — re-scan its pairing code to reconnect.';

	/// en: 'Revoke'
	String get revokeDevice => 'Revoke';

	/// en: 'New logins are blocked. Already-open OpenSSH sessions may stay connected until they disconnect.'
	String get revokeSystemHint => 'New logins are blocked. Already-open OpenSSH sessions may stay connected until they disconnect.';

	/// en: 'Save reachability'
	String get saveSettings => 'Save reachability';

	/// en: 'Scan this code in TeamPilot on your phone.'
	String get scanHint => 'Scan this code in TeamPilot on your phone.';

	/// en: 'Scan QR'
	String get scanQr => 'Scan QR';

	/// en: 'Hold 10–30 cm from the desktop QR. Pinch to zoom; use the flashlight in dim light.'
	String get scannerHint => 'Hold 10–30 cm from the desktop QR. Pinch to zoom; use the flashlight in dim light.';

	/// en: 'Camera permission is required to scan QR codes.'
	String get scannerPermissionDenied => 'Camera permission is required to scan QR codes.';

	/// en: 'The camera scanner is unavailable. Paste the code instead.'
	String get scannerUnavailable => 'The camera scanner is unavailable. Paste the code instead.';

	/// en: 'Pair a phone over SSH'
	String get settingsSubtitle => 'Pair a phone over SSH';

	/// en: 'Phone'
	String get settingsTitle => 'Phone';

	/// en: 'Embedded'
	String get sshBackendEmbedded => 'Embedded';

	/// en: 'Compare the built-in server with this computer's OpenSSH. Switching requires re-scanning the pairing code.'
	String get sshBackendHelp => 'Compare the built-in server with this computer\'s OpenSSH. Switching requires re-scanning the pairing code.';

	/// en: 'SSH server'
	String get sshBackendLabel => 'SSH server';

	/// en: 'Paired phones must re-scan this computer's pairing code.'
	String get sshBackendRePair => 'Paired phones must re-scan this computer\'s pairing code.';

	/// en: 'System OpenSSH (22)'
	String get sshBackendSystem => 'System OpenSSH (22)';

	/// en: 'The embedded connection server failed to start. Retry or restart the app.'
	String get sshdDown => 'The embedded connection server failed to start. Retry or restart the app.';

	/// en: 'Retry'
	String get sshdRetry => 'Retry';

	/// en: 'No SSH server is listening on port 22. Start the OpenSSH sshd service, then retry.'
	String get systemSshdDownLinux => 'No SSH server is listening on port 22. Start the OpenSSH sshd service, then retry.';

	/// en: 'No SSH server is listening on port 22. Enable Remote Login in Sharing settings, then retry.'
	String get systemSshdDownMacos => 'No SSH server is listening on port 22. Enable Remote Login in Sharing settings, then retry.';
}

// Path: cursor
class AppLocalizations$cursor$en {
	AppLocalizations$cursor$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Cursor accounts'
	String get accountUsageSession => 'Cursor accounts';

	/// en: 'Could not update credentials'
	String get credentialsActionFailed => 'Could not update credentials';

	/// en: 'Credentials updated'
	String get credentialsActionSuccess => 'Credentials updated';

	/// en: 'Import directory…'
	String get credentialsImportFile => 'Import directory…';

	/// en: 'Import from ~/.cursor'
	String get credentialsImportGlobal => 'Import from ~/.cursor';

	/// en: 'Sign in with Cursor'
	String get credentialsLogin => 'Sign in with Cursor';

	/// en: 'Sign out'
	String get credentialsRevoke => 'Sign out';

	/// en: 'Sign out and remove saved credentials for {name: String}?'
	String credentialsRevokeConfirm({required String name}) => 'Sign out and remove saved credentials for ${name}?';
}

// Path: delete
class AppLocalizations$delete$en {
	AppLocalizations$delete$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Delete conversation'
	String get conversation => 'Delete conversation';

	/// en: 'Delete conversation "{name: String}"? This cannot be undone.'
	String conversationConfirm({required String name}) => 'Delete conversation "${name}"? This cannot be undone.';

	/// en: 'Delete Provider'
	String get provider => 'Delete Provider';

	/// en: 'Delete provider {name: String}?'
	String providerConfirm({required String name}) => 'Delete provider ${name}?';

	/// en: 'Delete provider'
	String get providerTooltip => 'Delete provider';

	/// en: 'Delete provider {name: String}? Saved Claude login credentials for this provider will also be removed.'
	String providerWithCredentialsConfirm({required String name}) => 'Delete provider ${name}? Saved Claude login credentials for this provider will also be removed.';

	/// en: 'Delete team'
	String get team => 'Delete team';

	/// en: 'Delete team "{name: String}"? This cannot be undone.'
	String teamConfirm({required String name}) => 'Delete team "${name}"? This cannot be undone.';

	/// en: 'Removes this team from the UI and the shared flashskyai data directory. This cannot be undone.'
	String get teamSubtitle => 'Removes this team from the UI and the shared flashskyai data directory. This cannot be undone.';

	/// en: 'Delete Workspace'
	String get workspace => 'Delete Workspace';

	/// en: 'Delete workspace "{name: String}" and all its sessions? This cannot be undone.'
	String workspaceConfirm({required String name}) => 'Delete workspace "${name}" and all its sessions? This cannot be undone.';

	/// en: 'Deletes this workspace and all conversations in it. This cannot be undone.'
	String get workspaceSubtitle => 'Deletes this workspace and all conversations in it. This cannot be undone.';
}

// Path: diff
class AppLocalizations$diff$en {
	AppLocalizations$diff$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Cannot apply: file path unavailable'
	String get applyDisabledNoPath => 'Cannot apply: file path unavailable';

	/// en: 'Could not apply change: {error: String}'
	String applyFailed({required String error}) => 'Could not apply change: ${error}';

	/// en: 'Apply change to working tree'
	String get applyHunkTooltip => 'Apply change to working tree';

	/// en: '{current: int} / {total: int}'
	String changeCounter({required int current, required int total}) => '${current} / ${total}';

	/// en: 'Saving the file will discard unsaved edits in the diff view.'
	String get discardDiffBeforeFileSaveBody => 'Saving the file will discard unsaved edits in the diff view.';

	/// en: 'Discard diff edits?'
	String get discardDiffBeforeFileSaveTitle => 'Discard diff edits?';

	/// en: 'Applying this change discards unsaved edits in the diff.'
	String get discardEditsApplyBody => 'Applying this change discards unsaved edits in the diff.';

	/// en: 'Discard edits?'
	String get discardEditsApplyTitle => 'Discard edits?';

	/// en: 'File tab reloaded from disk.'
	String get fileReloadedAfterDiffWrite => 'File tab reloaded from disk.';

	/// en: 'Ignore whitespace'
	String get ignoreWhitespace => 'Ignore whitespace';

	/// en: 'Next change'
	String get nextChange => 'Next change';

	/// en: 'No changes'
	String get noChanges => 'No changes';

	/// en: 'Open source file'
	String get openSourceFile => 'Open source file';

	/// en: 'Previous change'
	String get previousChange => 'Previous change';

	/// en: 'Saved, but refreshing the diff failed.'
	String get reloadAfterSaveFailed => 'Saved, but refreshing the diff failed.';

	/// en: 'Could not save: {error: String}'
	String saveFailed({required String error}) => 'Could not save: ${error}';

	/// en: 'Show all lines'
	String get showAllLines => 'Show all lines';

	/// en: 'Side by side'
	String get viewSideBySide => 'Side by side';

	/// en: 'Unified'
	String get viewUnified => 'Unified';
}

// Path: download
class AppLocalizations$download$en {
	AppLocalizations$download$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Enabled sources'
	String get sourcesEnabledSources => 'Enabled sources';

	/// en: 'identity (official)'
	String get sourcesIdentity => 'identity (official)';

	/// en: 'Mirror base URL'
	String get sourcesMirrorBaseUrl => 'Mirror base URL';

	/// en: 'https://mirror.example'
	String get sourcesMirrorHint => 'https://mirror.example';

	/// en: 'Restore defaults'
	String get sourcesRestoreDefaults => 'Restore defaults';

	/// en: 'Save'
	String get sourcesSave => 'Save';

	/// en: 'Configure mirrors for GitHub downloads (app updates, Termux APK)'
	String get sourcesSettingsSubtitle => 'Configure mirrors for GitHub downloads (app updates, Termux APK)';

	/// en: 'Download sources'
	String get sourcesSettingsTitle => 'Download sources';
}

// Path: edit
class AppLocalizations$edit$en {
	AppLocalizations$edit$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Edit provider, model, optional agent preset, and command arguments.'
	String get memberSubtitle => 'Edit provider, model, optional agent preset, and command arguments.';

	/// en: 'Edit {name: String}'
	String modelTitle({required String name}) => 'Edit ${name}';

	/// en: 'Edit provider'
	String get provider => 'Edit provider';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Send'
	String get send => 'Send';

	/// en: 'Edit team identity, working directory, and launch order.'
	String get teamSubtitle => 'Edit team identity, working directory, and launch order.';

	/// en: 'Edit message'
	String get userMessage => 'Edit message';

	/// en: 'Edit primary directory'
	String get workspacePrimaryPath => 'Edit primary directory';
}

// Path: editor
class AppLocalizations$editor$en {
	AppLocalizations$editor$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Binary files open with the system default app.'
	String get binaryFileHint => 'Binary files open with the system default app.';

	/// en: 'Close editor'
	String get close => 'Close editor';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Copy as AI context'
	String get copyAsAiContext => 'Copy as AI context';

	/// en: 'Could not read file'
	String get couldNotReadFile => 'Could not read file';

	/// en: 'Cut'
	String get cut => 'Cut';

	/// en: 'Discard'
	String get discard => 'Discard';

	/// en: 'File not found'
	String get fileNotFound => 'File not found';

	/// en: 'File is read-only'
	String get fileReadOnly => 'File is read-only';

	/// en: 'File is too large to edit in TeamPilot (max 2 MB).'
	String get fileTooLarge => 'File is too large to edit in TeamPilot (max 2 MB).';

	/// en: 'Close'
	String get findClose => 'Close';

	/// en: 'Find'
	String get findHint => 'Find';

	/// en: 'Find in selection'
	String get findInSelection => 'Find in selection';

	/// en: 'Invalid regular expression'
	String get findInvalidRegex => 'Invalid regular expression';

	/// en: 'Match case'
	String get findMatchCase => 'Match case';

	/// en: 'Next match'
	String get findNext => 'Next match';

	/// en: 'No matches'
	String get findNoResults => 'No matches';

	/// en: 'Previous match'
	String get findPrevious => 'Previous match';

	/// en: 'Replace all'
	String get findReplaceAll => 'Replace all';

	/// en: 'Replace'
	String get findReplaceHint => 'Replace';

	/// en: 'Replace'
	String get findReplaceOne => 'Replace';

	/// en: 'Preserve case'
	String get findReplacePreserveCase => 'Preserve case';

	/// en: 'Toggle replace'
	String get findToggleReplace => 'Toggle replace';

	/// en: 'Use regular expression'
	String get findUseRegex => 'Use regular expression';

	/// en: 'Match whole word'
	String get findWholeWord => 'Match whole word';

	/// en: 'Could not decode this image.'
	String get imageDecodeFailed => 'Could not decode this image.';

	/// en: 'Image is too large to preview in TeamPilot (max 25 MB).'
	String get imageTooLarge => 'Image is too large to preview in TeamPilot (max 25 MB).';

	/// en: 'No file open'
	String get noFileOpen => 'No file open';

	/// en: 'Editor not ready'
	String get notReady => 'Editor not ready';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Redo'
	String get redoEdit => 'Redo';

	/// en: 'Revert changes'
	String get revertChanges => 'Revert changes';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Save failed: {error: String}'
	String saveFailed({required String error}) => 'Save failed: ${error}';

	/// en: 'Select all'
	String get selectAll => 'Select all';

	/// en: 'Editor'
	String get title => 'Editor';

	/// en: 'Undo'
	String get undoEdit => 'Undo';

	/// en: 'Discard unsaved changes to "{fileName: String}"?'
	String unsavedChangesDiscardFile({required String fileName}) => 'Discard unsaved changes to "${fileName}"?';

	/// en: 'Discard unsaved changes in {count: int} file(s)?'
	String unsavedChangesDiscardMultiple({required int count}) => 'Discard unsaved changes in ${count} file(s)?';

	/// en: 'Unsaved changes'
	String get unsavedChangesTitle => 'Unsaved changes';
}

// Path: exit
class AppLocalizations$exit$en {
	AppLocalizations$exit$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Approve'
	String get planModeApprove => 'Approve';

	/// en: 'Couldn't approve the plan'
	String get planModeApproveFailed => 'Couldn\'t approve the plan';

	/// en: 'Copy plan'
	String get planModeCopyPlan => 'Copy plan';

	/// en: 'Open plan file'
	String get planModeOpenPlanFile => 'Open plan file';

	/// en: 'Plan preview'
	String get planModePreviewTitle => 'Plan preview';

	/// en: 'Reject'
	String get planModeReject => 'Reject';

	/// en: 'Couldn't reject the plan'
	String get planModeRejectFailed => 'Couldn\'t reject the plan';

	/// en: 'Plan ready for approval'
	String get planModeTitle => 'Plan ready for approval';

	/// en: 'View plan'
	String get planModeViewPlan => 'View plan';
}

// Path: expert
class AppLocalizations$expert$en {
	AppLocalizations$expert$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Category'
	String get editorCategory => 'Category';

	/// en: 'Configure MCP'
	String get editorConfigureMcpTitle => 'Configure MCP';

	/// en: 'Configure plugins'
	String get editorConfigurePluginsTitle => 'Configure plugins';

	/// en: 'Configure skills'
	String get editorConfigureSkillsTitle => 'Configure skills';

	/// en: 'New expert'
	String get editorCreateTitle => 'New expert';

	/// en: 'Done'
	String get editorDepPickerDone => 'Done';

	/// en: 'Configure dependencies from your installed library. Items without a portable source are skipped on save.'
	String get editorDepsHint => 'Configure dependencies from your installed library. Items without a portable source are skipped on save.';

	/// en: 'Description'
	String get editorDescription => 'Description';

	/// en: 'Edit expert'
	String get editorEditTitle => 'Edit expert';

	/// en: 'MCP'
	String get editorMcpSection => 'MCP';

	/// en: 'Name is required.'
	String get editorNameRequired => 'Name is required.';

	/// en: 'Skipped {count: int} local-only item(s) without portable provenance.'
	String editorNonPortableSkipped({required int count}) => 'Skipped ${count} local-only item(s) without portable provenance.';

	/// en: 'Attached (not installed locally)'
	String get editorOrphanDeps => 'Attached (not installed locally)';

	/// en: 'Remove'
	String get editorOrphanRemove => 'Remove';

	/// en: 'Optional step-by-step guidance this expert should follow.'
	String get editorPlaybookHint => 'Optional step-by-step guidance this expert should follow.';

	/// en: 'Plugins'
	String get editorPluginsSection => 'Plugins';

	/// en: 'Describe this expert's role and what they are responsible for.'
	String get editorPromptHint => 'Describe this expert\'s role and what they are responsible for.';

	/// en: 'Responsibilities are required.'
	String get editorPromptRequired => 'Responsibilities are required.';

	/// en: 'Skills'
	String get editorSkillsSection => 'Skills';

	/// en: 'Tags'
	String get editorTags => 'Tags';

	/// en: 'Comma-separated'
	String get editorTagsHint => 'Comma-separated';

	/// en: 'Could not add this member.'
	String get hubAddFailed => 'Could not add this member.';

	/// en: 'Add from Expert Hub'
	String get hubAddFromHub => 'Add from Expert Hub';

	/// en: 'Added "{name}". Installed {skillCount: int} skills. {failedCount: int} could not be installed: {failedNames}.'
	String hubAddPartial({required Object name, required int skillCount, required int failedCount, required Object failedNames}) => 'Added "${name}". Installed ${skillCount} skills. ${failedCount} could not be installed: ${failedNames}.';

	/// en: 'Added "{name}" to team.'
	String hubAddSuccess({required Object name}) => 'Added "${name}" to team.';

	/// en: 'Added "{name}". Installed {skillCount: int} skills.'
	String hubAddSuccessWithSkills({required Object name, required int skillCount}) => 'Added "${name}". Installed ${skillCount} skills.';

	/// en: 'Add to team'
	String get hubAddToTeam => 'Add to team';

	/// en: 'Adding…'
	String get hubAdding => 'Adding…';

	/// en: 'Browse all experts'
	String get hubBrowseAll => 'Browse all experts';

	/// en: 'Capabilities'
	String get hubCapabilities => 'Capabilities';

	/// en: 'None'
	String get hubCardNoDescription => 'None';

	/// en: 'All'
	String get hubCategoryAll => 'All';

	/// en: 'Confirm'
	String get hubConfirmSelection => 'Confirm';

	/// en: 'New'
	String get hubCreate => 'New';

	/// en: 'Refresh to fetch experts from the registry.'
	String get hubEmptyHint => 'Refresh to fetch experts from the registry.';

	/// en: 'No experts yet'
	String get hubEmptyTitle => 'No experts yet';

	/// en: 'Favorites'
	String get hubFavorites => 'Favorites';

	/// en: 'Tap the star on an expert to save it here.'
	String get hubFavoritesEmptyHint => 'Tap the star on an expert to save it here.';

	/// en: 'No favorites yet'
	String get hubFavoritesEmptyTitle => 'No favorites yet';

	/// en: 'From teams'
	String get hubFromTeams => 'From teams';

	/// en: 'Experts are only available in Simple mode. Switch to Simple to summon an expert.'
	String get hubIgnoredInTeamMode => 'Experts are only available in Simple mode. Switch to Simple to summon an expert.';

	/// en: 'Launch in workspace'
	String get hubLaunchInWorkspace => 'Launch in workspace';

	/// en: 'Could not load experts.'
	String get hubLoadError => 'Could not load experts.';

	/// en: 'My templates'
	String get hubMyTemplates => 'My templates';

	/// en: 'Expert Hub'
	String get hubNav => 'Expert Hub';

	/// en: 'No expert'
	String get hubNoneSelected => 'No expert';

	/// en: 'Expert not found.'
	String get hubNotFound => 'Expert not found.';

	/// en: 'Playbook'
	String get hubPlaybook => 'Playbook';

	/// en: 'Selected "{name}". {failedCount: int} capabilities could not be installed: {failedNames}.'
	String hubPreflightPartial({required Object name, required int failedCount, required Object failedNames}) => 'Selected "${name}". ${failedCount} capabilities could not be installed: ${failedNames}.';

	/// en: 'Responsibilities'
	String get hubPrompt => 'Responsibilities';

	/// en: 'Recent'
	String get hubRecent => 'Recent';

	/// en: 'Refresh'
	String get hubRefresh => 'Refresh';

	/// en: 'Search experts'
	String get hubSearchHint => 'Search experts';

	/// en: 'Name'
	String get hubSortName => 'Name';

	/// en: 'Recently updated'
	String get hubSortUpdated => 'Recently updated';

	/// en: 'Built-in'
	String get hubSourceBuiltin => 'Built-in';

	/// en: 'Cloned'
	String get hubSourceClone => 'Cloned';

	/// en: 'My template'
	String get hubSourceLocal => 'My template';

	/// en: 'Registry'
	String get hubSourceRegistry => 'Registry';

	/// en: 'From team'
	String get hubSourceTeamExtract => 'From team';

	/// en: 'Discover member personas and templates'
	String get hubSubtitle => 'Discover member personas and templates';

	/// en: 'Expert Hub'
	String get hubTitle => 'Expert Hub';

	/// en: 'View in Expert Hub'
	String get hubViewInHub => 'View in Expert Hub';

	/// en: 'View origin team'
	String get hubViewOriginTeam => 'View origin team';
}

// Path: extension
class AppLocalizations$extension$en {
	AppLocalizations$extension$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Command copied to clipboard'
	String get commandCopied => 'Command copied to clipboard';

	/// en: 'Copy'
	String get copyCommand => 'Copy';

	/// en: 'Needs {deps: String} on your PATH. Install it, then re-check.'
	String dependencyMissingHint({required String deps}) => 'Needs ${deps} on your PATH. Install it, then re-check.';

	/// en: 'Enabled'
	String get enableLabel => 'Enabled';

	/// en: 'Install'
	String get install => 'Install';

	/// en: 'Install guide'
	String get installGuide => 'Install guide';

	/// en: 'Code intelligence (MCP)'
	String get kindMcpServer => 'Code intelligence (MCP)';

	/// en: 'Token savings (hook)'
	String get kindSettingsHook => 'Token savings (hook)';

	/// en: 'Re-check'
	String get recheck => 'Re-check';

	/// en: 'Missing dependency'
	String get statusDependencyMissing => 'Missing dependency';

	/// en: 'Missing: {deps: String}'
	String statusDependencyMissingNamed({required String deps}) => 'Missing: ${deps}';

	/// en: 'Not installed'
	String get statusNotInstalled => 'Not installed';

	/// en: 'Ready'
	String get statusReady => 'Ready';

	/// en: 'Ready ({version: String})'
	String statusReadyVersion({required String version}) => 'Ready (${version})';

	/// en: 'Installed version is too old'
	String get statusVersionTooOld => 'Installed version is too old';

	/// en: 'Uninstall'
	String get uninstall => 'Uninstall';
}

// Path: file
class AppLocalizations$file$en {
	AppLocalizations$file$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'How oversized code blocks render in the markdown file preview.'
	String get codeBlockModeDescription => 'How oversized code blocks render in the markdown file preview.';

	/// en: 'Code blocks in file preview'
	String get codeBlockModeTitle => 'Code blocks in file preview';

	/// en: 'Diff'
	String get diffToggleDiff => 'Diff';

	/// en: 'File'
	String get diffToggleFile => 'File';

	/// en: 'Center'
	String get previewHostCenter => 'Center';

	/// en: 'Open files in the floating workspace or the center workbench.'
	String get previewHostDescription => 'Open files in the floating workspace or the center workbench.';

	/// en: 'Floating'
	String get previewHostFloating => 'Floating';

	/// en: 'File preview'
	String get previewHostTitle => 'File preview';
}

// Path: fileTree
class AppLocalizations$fileTree$en {
	AppLocalizations$fileTree$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'File Tree'
	String get fileTree => 'File Tree';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Copy path'
	String get copyPath => 'Copy path';

	/// en: 'Copy relative path'
	String get copyRelativePath => 'Copy relative path';

	/// en: 'Name'
	String get createNameHint => 'Name';

	/// en: 'Cut'
	String get cut => 'Cut';

	/// en: 'Deleted'
	String get deleteDone => 'Deleted';

	/// en: 'Delete "{name: String}"?'
	String deleteItemConfirm({required String name}) => 'Delete "${name}"?';

	/// en: 'Delete'
	String get deleteItemTitle => 'Delete';

	/// en: 'File created'
	String get fileCreated => 'File created';

	/// en: 'Folder created'
	String get folderCreated => 'Folder created';

	/// en: 'Hide file filter'
	String get hideFilter => 'Hide file filter';

	/// en: 'Apply to remaining conflicts'
	String get importApplyRemaining => 'Apply to remaining conflicts';

	/// en: 'Cancel all'
	String get importCancelAll => 'Cancel all';

	/// en: '"{name: String}" already exists at the destination.'
	String importConflictBody({required String name}) => '"${name}" already exists at the destination.';

	/// en: '(one) {1 more conflict after this.} (other) {{count: int} more conflicts after this.}'
	String importConflictRemaining({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '1 more conflict after this.',
		other: '${count} more conflicts after this.',
	);

	/// en: 'No further conflicts.'
	String get importConflictRemainingZero => 'No further conflicts.';

	/// en: 'Item already exists'
	String get importConflictTitle => 'Item already exists';

	/// en: 'A file and a folder cannot replace each other.'
	String get importConflictTypeMismatch => 'A file and a folder cannot replace each other.';

	/// en: 'Copy'
	String get importDropCopy => 'Copy';

	/// en: 'Move'
	String get importDropMove => 'Move';

	/// en: 'Overwrite'
	String get importOverwrite => 'Overwrite';

	/// en: 'Cancel'
	String get importProgressCancel => 'Cancel';

	/// en: '{name: String}'
	String importProgressCurrent({required String name}) => '${name}';

	/// en: '{completed: int} / {total: int}'
	String importProgressItems({required int completed, required int total}) => '${completed} / ${total}';

	/// en: 'Importing…'
	String get importProgressTitle => 'Importing…';

	/// en: 'Cannot move or copy an item into itself or its children.'
	String get importRejectSelf => 'Cannot move or copy an item into itself or its children.';

	/// en: 'Skip'
	String get importSkip => 'Skip';

	/// en: '{succeeded: int} succeeded, {skipped: int} skipped, {failed: int} failed'
	String importSummary({required int succeeded, required int skipped, required int failed}) => '${succeeded} succeeded, ${skipped} skipped, ${failed} failed';

	/// en: ' — cancelled'
	String get importSummaryCancelledSuffix => ' — cancelled';

	/// en: 'Invalid name'
	String get invalidName => 'Invalid name';

	/// en: 'Cannot paste here'
	String get invalidPasteTarget => 'Cannot paste here';

	/// en: 'An item with that name already exists'
	String get itemExists => 'An item with that name already exists';

	/// en: 'New File'
	String get newFile => 'New File';

	/// en: 'New Folder'
	String get newFolder => 'New Folder';

	/// en: 'Reveal in File Manager'
	String get openInFileManager => 'Reveal in File Manager';

	/// en: 'Open in Terminal'
	String get openInTerminal => 'Open in Terminal';

	/// en: 'Could not open a terminal'
	String get openInTerminalFailed => 'Could not open a terminal';

	/// en: 'Open with system app'
	String get openWithSystemApp => 'Open with system app';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Pasted'
	String get pasteDone => 'Pasted';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Rename'
	String get rename => 'Rename';

	/// en: 'Renamed'
	String get renameDone => 'Renamed';

	/// en: 'Rename'
	String get renameTitle => 'Rename';

	/// en: 'Reveal active file'
	String get revealActiveFile => 'Reveal active file';

	/// en: 'Cannot reveal this file in the file tree'
	String get revealFailed => 'Cannot reveal this file in the file tree';

	/// en: 'Show file filter'
	String get showFilter => 'Show file filter';

	/// en: 'The copied item no longer exists'
	String get sourceMissing => 'The copied item no longer exists';
}

// Path: floating
class AppLocalizations$floating$en {
	AppLocalizations$floating$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'File and diff previews share one replaceable tab in the floating panel until pinned.'
	String get previewTabsDescription => 'File and diff previews share one replaceable tab in the floating panel until pinned.';

	/// en: 'Single preview tab'
	String get previewTabsTitle => 'Single preview tab';

	/// en: 'Keep floating terminal tabs across restarts; a tab reconnects only when you first open it.'
	String get restoreTerminalSessionsDescription => 'Keep floating terminal tabs across restarts; a tab reconnects only when you first open it.';

	/// en: 'Restore terminal tabs'
	String get restoreTerminalSessionsTitle => 'Restore terminal tabs';

	/// en: 'Open in floating workspace'
	String get workspaceAddTooltip => 'Open in floating workspace';

	/// en: 'Close tab'
	String get workspaceCloseTab => 'Close tab';

	/// en: 'Maximize'
	String get workspaceMaximize => 'Maximize';

	/// en: 'Minimize'
	String get workspaceMinimize => 'Minimize';

	/// en: 'New Terminal'
	String get workspaceNewTerminal => 'New Terminal';

	/// en: 'Open File'
	String get workspaceOpenFile => 'Open File';

	/// en: 'Floating workspace'
	String get workspaceToggleTooltip => 'Floating workspace';
}

// Path: font
class AppLocalizations$font$en {
	AppLocalizations$font$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Font saved. Restart TeamPilot to apply.'
	String get changeAppliesOnRestart => 'Font saved. Restart TeamPilot to apply.';

	/// en: 'Installed'
	String get installedSection => 'Installed';

	/// en: 'Terminal, editor, and diffs. Takes effect after restart.'
	String get monoDescription => 'Terminal, editor, and diffs. Takes effect after restart.';

	/// en: 'Monospace font'
	String get monoTitle => 'Monospace font';

	/// en: 'JetBrains Mono'
	String get optionJetbrainsMono => 'JetBrains Mono';

	/// en: 'Noto Sans SC'
	String get optionNotoSansSc => 'Noto Sans SC';

	/// en: 'System'
	String get optionSystem => 'System';

	/// en: 'Ubuntu Sans Mono'
	String get optionUbuntuSansMono => 'Ubuntu Sans Mono';

	/// en: 'Search fonts'
	String get searchHint => 'Search fonts';

	/// en: 'UI text. System follows the OS default. Takes effect after restart.'
	String get uiDescription => 'UI text. System follows the OS default. Takes effect after restart.';

	/// en: 'Interface font'
	String get uiTitle => 'Interface font';
}

// Path: git
class AppLocalizations$git$en {
	AppLocalizations$git$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: '↑{ahead: int} ↓{behind: int}'
	String aheadBehind({required int ahead, required int behind}) => '↑${ahead} ↓${behind}';

	/// en: 'Amend'
	String get amend => 'Amend';

	/// en: 'Amend Commit'
	String get amendCommit => 'Amend Commit';

	/// en: 'This rewrites the last commit. If it was already pushed to a remote, a force push will be required afterwards.'
	String get amendConfirmMessage => 'This rewrites the last commit. If it was already pushed to a remote, a force push will be required afterwards.';

	/// en: 'Amend last commit?'
	String get amendConfirmTitle => 'Amend last commit?';

	/// en: 'Periodically run a non-interactive git fetch --all --prune for the repository shown in the source-control panel, keeping ahead/behind counts fresh.'
	String get autoFetchDescription => 'Periodically run a non-interactive git fetch --all --prune for the repository shown in the source-control panel, keeping ahead/behind counts fresh.';

	/// en: 'How often the selected repository is fetched while the panel is open.'
	String get autoFetchIntervalDescription => 'How often the selected repository is fetched while the panel is open.';

	/// en: 'Every {minutes: int} min'
	String autoFetchIntervalMinutesOption({required int minutes}) => 'Every ${minutes} min';

	/// en: 'Auto-fetch interval (minutes)'
	String get autoFetchIntervalTitle => 'Auto-fetch interval (minutes)';

	/// en: 'Auto-fetch remote updates'
	String get autoFetchTitle => 'Auto-fetch remote updates';

	/// en: 'Changes'
	String get changes => 'Changes';

	/// en: 'List view'
	String get changesListView => 'List view';

	/// en: 'Tree view'
	String get changesTreeView => 'Tree view';

	/// en: 'Commit'
	String get commit => 'Commit';

	/// en: 'Message (commit to "{branch: String}")'
	String commitMessageHint({required String branch}) => 'Message (commit to "${branch}")';

	/// en: 'Committing…'
	String get committing => 'Committing…';

	/// en: 'No differences'
	String get compareEmpty => 'No differences';

	/// en: 'Could not load differences'
	String get compareLoadError => 'Could not load differences';

	/// en: 'Difference between {ref: String} and current working tree'
	String compareSubtitle({required String ref}) => 'Difference between ${ref} and current working tree';

	/// en: 'Working Tree'
	String get compareWorkingTree => 'Working Tree';

	/// en: 'Copy Path'
	String get copyPath => 'Copy Path';

	/// en: 'Create branch'
	String get createBranch => 'Create branch';

	/// en: 'Discard changes'
	String get discard => 'Discard changes';

	/// en: 'Discard all unstaged changes in the working tree? This cannot be undone.'
	String get discardAllConfirmBody => 'Discard all unstaged changes in the working tree? This cannot be undone.';

	/// en: 'Discard all changes?'
	String get discardAllConfirmTitle => 'Discard all changes?';

	/// en: 'Discard All Unstaged Changes'
	String get discardAllUnstaged => 'Discard All Unstaged Changes';

	/// en: 'Discard all changes in {path: String}? This cannot be undone.'
	String discardConfirmBody({required String path}) => 'Discard all changes in ${path}? This cannot be undone.';

	/// en: 'Discard changes?'
	String get discardConfirmTitle => 'Discard changes?';

	/// en: 'Discard changes in folder'
	String get discardFolder => 'Discard changes in folder';

	/// en: 'Discard all changes in {path: String}? This cannot be undone.'
	String discardFolderConfirmBody({required String path}) => 'Discard all changes in ${path}? This cannot be undone.';

	/// en: 'Discard folder changes?'
	String get discardFolderConfirmTitle => 'Discard folder changes?';

	/// en: 'Discard Selected Change'
	String get discardSelected => 'Discard Selected Change';

	/// en: 'Git: {message: String}'
	String error({required String message}) => 'Git: ${message}';

	/// Context-menu action to exclude a folder and its changed files from the next commit.
	///
	/// en: 'Exclude Folder from Commit'
	String get excludeFolderFromCommit => 'Exclude Folder from Commit';

	/// Context-menu action to exclude a file from the next commit.
	///
	/// en: 'Exclude from Commit'
	String get excludeFromCommit => 'Exclude from Commit';

	/// en: 'Fetch from remote'
	String get fetch => 'Fetch from remote';

	/// en: 'Fetched from remote'
	String get fetchDone => 'Fetched from remote';

	/// en: 'Fetching from remote…'
	String get fetching => 'Fetching from remote…';

	/// en: 'Generate commit message with AI'
	String get generateCommitMessage => 'Generate commit message with AI';

	/// en: 'Configure an AI provider in Settings → AI Features first.'
	String get generateCommitMessageNoProvider => 'Configure an AI provider in Settings → AI Features first.';

	/// en: 'Generating commit message…'
	String get generatingCommitMessage => 'Generating commit message…';

	/// Context-menu action to include a folder and its changed files in the next commit.
	///
	/// en: 'Include Folder in Commit'
	String get includeFolderInCommit => 'Include Folder in Commit';

	/// Context-menu action to include a file in the next commit.
	///
	/// en: 'Include in Commit'
	String get includeInCommit => 'Include in Commit';

	/// en: 'Create Git repository'
	String get initializeRepository => 'Create Git repository';

	/// en: 'New branch name'
	String get newBranchHint => 'New branch name';

	/// en: 'No changes'
	String get noChanges => 'No changes';

	/// en: 'This folder is not a Git repository'
	String get notARepository => 'This folder is not a Git repository';

	/// en: 'Git was not found. Install Git to use source control.'
	String get notInstalled => 'Git was not found. Install Git to use source control.';

	/// en: 'Open File'
	String get openFile => 'Open File';

	/// en: 'Pull'
	String get pull => 'Pull';

	/// en: 'Pull completed'
	String get pullDone => 'Pull completed';

	/// en: 'Pulling…'
	String get pulling => 'Pulling…';

	/// en: 'Push'
	String get push => 'Push';

	/// en: 'Push completed'
	String get pushDone => 'Push completed';

	/// en: 'Pushing…'
	String get pushing => 'Pushing…';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Refreshing…'
	String get refreshing => 'Refreshing…';

	/// en: 'Show Diff'
	String get showDiff => 'Show Diff';

	/// en: 'Staged Changes'
	String get stagedChanges => 'Staged Changes';

	/// en: 'Switch branch'
	String get switchBranch => 'Switch branch';

	/// en: 'Unversioned Files'
	String get unversionedFiles => 'Unversioned Files';
}

// Path: gitGraph
class AppLocalizations$gitGraph$en {
	AppLocalizations$gitGraph$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'All branches'
	String get allBranches => 'All branches';

	/// en: 'Branch name'
	String get branchNameLabel => 'Branch name';

	/// en: 'Branches & tags'
	String get branchesTags => 'Branches & tags';

	/// en: 'Checkout {branch: String}'
	String checkoutBranch({required String branch}) => 'Checkout ${branch}';

	/// en: 'Checkout this commit (detached HEAD)'
	String get checkoutCommit => 'Checkout this commit (detached HEAD)';

	/// en: 'Checkout {hash: String} with detached HEAD?'
	String checkoutCommitConfirmBody({required String hash}) => 'Checkout ${hash} with detached HEAD?';

	/// en: 'Cherry-pick'
	String get cherryPick => 'Cherry-pick';

	/// en: 'Author'
	String get columnAuthor => 'Author';

	/// en: 'Commit'
	String get columnCommit => 'Commit';

	/// en: 'Date'
	String get columnDate => 'Date';

	/// en: 'Description'
	String get columnDescription => 'Description';

	/// en: 'Graph'
	String get columnGraph => 'Graph';

	/// en: 'Column header'
	String get columnHeaderLabel => 'Column header';

	/// en: 'Columns'
	String get columns => 'Columns';

	/// en: 'Commits'
	String get commits => 'Commits';

	/// en: 'Filter branches, tags, and commits'
	String get compareFilterHint => 'Filter branches, tags, and commits';

	/// en: 'Compare with…'
	String get compareWith => 'Compare with…';

	/// en: 'Working Tree ({branch: String})'
	String compareWorkingTree({required String branch}) => 'Working Tree (${branch})';

	/// en: 'Resolve the conflicts, stage the files, then commit to continue.'
	String get conflictHint => 'Resolve the conflicts, stage the files, then commit to continue.';

	/// en: 'Copy hash'
	String get copyHash => 'Copy hash';

	/// en: 'Copy subject'
	String get copySubject => 'Copy subject';

	/// en: 'Create'
	String get create => 'Create';

	/// en: 'Create branch here'
	String get createBranchHere => 'Create branch here';

	/// en: 'Create branch'
	String get createBranchTitle => 'Create branch';

	/// en: 'Create tag here'
	String get createTagHere => 'Create tag here';

	/// en: 'Create tag'
	String get createTagTitle => 'Create tag';

	/// en: 'Current branch'
	String get currentBranch => 'Current branch';

	/// en: 'Delete branch {name: String}'
	String deleteBranch({required String name}) => 'Delete branch ${name}';

	/// en: 'Delete branch "{name: String}"? Commits only reachable from it may become unreachable. This cannot be undone.'
	String deleteBranchConfirmBody({required String name}) => 'Delete branch "${name}"? Commits only reachable from it may become unreachable. This cannot be undone.';

	/// en: 'Delete branch'
	String get deleteBranchTitle => 'Delete branch';

	/// en: 'Delete remote branch "{name: String}" on the shared repository? This affects all collaborators and cannot be undone.'
	String deleteRemoteBranchConfirmBody({required String name}) => 'Delete remote branch "${name}" on the shared repository? This affects all collaborators and cannot be undone.';

	/// en: 'Delete remote branch'
	String get deleteRemoteBranchTitle => 'Delete remote branch';

	/// en: 'Delete tag {name: String}'
	String deleteTag({required String name}) => 'Delete tag ${name}';

	/// en: 'Delete tag "{name: String}"? This cannot be undone.'
	String deleteTagConfirmBody({required String name}) => 'Delete tag "${name}"? This cannot be undone.';

	/// en: 'Delete tag'
	String get deleteTagTitle => 'Delete tag';

	/// en: 'Fetch'
	String get fetch => 'Fetch';

	/// en: 'Hash copied to clipboard'
	String get hashCopied => 'Hash copied to clipboard';

	/// en: 'No loaded commit matches this hash. Scroll down or click "Load more" to fetch older history.'
	String get hashSearchEmptyHint => 'No loaded commit matches this hash. Scroll down or click "Load more" to fetch older history.';

	/// en: 'Hide {column: String}'
	String hideColumn({required String column}) => 'Hide ${column}';

	/// en: 'Hide column header'
	String get hideColumnHeader => 'Hide column header';

	/// en: 'Load more'
	String get loadMore => 'Load more';

	/// en: 'Loading…'
	String get loadingMore => 'Loading…';

	/// en: 'Local branches'
	String get localBranches => 'Local branches';

	/// en: 'Merge {branch: String} into current branch'
	String mergeIntoCurrent({required String branch}) => 'Merge ${branch} into current branch';

	/// en: 'No commits found'
	String get noCommits => 'No commits found';

	/// en: 'Not a git repository'
	String get notARepository => 'Not a git repository';

	/// en: 'Pull'
	String get pull => 'Pull';

	/// en: 'Push'
	String get push => 'Push';

	/// en: 'Push tag {name: String}'
	String pushTag({required String name}) => 'Push tag ${name}';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'No matches'
	String get refsFilterEmpty => 'No matches';

	/// en: 'Filter branches and tags'
	String get refsFilterHint => 'Filter branches and tags';

	/// en: 'Remote branches'
	String get remoteBranches => 'Remote branches';

	/// en: 'Rename branch…'
	String get renameBranch => 'Rename branch…';

	/// en: 'Rename branch'
	String get renameBranchTitle => 'Rename branch';

	/// en: 'Reset'
	String get reset => 'Reset';

	/// en: 'Hard'
	String get resetHard => 'Hard';

	/// en: 'Hard reset moves "{branch: String}" to this commit and discards ALL uncommitted changes. Type "{branch: String}" to confirm.'
	String resetHardConfirmBody({required String branch}) => 'Hard reset moves "${branch}" to this commit and discards ALL uncommitted changes. Type "${branch}" to confirm.';

	/// en: 'Mixed'
	String get resetMixed => 'Mixed';

	/// en: 'Soft'
	String get resetSoft => 'Soft';

	/// en: 'Revert'
	String get revert => 'Revert';

	/// en: 'Revert commit {hash: String}? A new commit undoing it will be created.'
	String revertConfirmBody({required String hash}) => 'Revert commit ${hash}? A new commit undoing it will be created.';

	/// en: 'Search commits (message / author / hash)'
	String get searchHint => 'Search commits (message / author / hash)';

	/// en: 'Author'
	String get searchModeAuthor => 'Author';

	/// en: 'Hash'
	String get searchModeHash => 'Hash';

	/// en: 'Message'
	String get searchModeMessage => 'Message';

	/// en: 'Select a commit to view details'
	String get selectCommit => 'Select a commit to view details';

	/// en: 'Show column header'
	String get showColumnHeader => 'Show column header';

	/// en: 'Stash'
	String get stash => 'Stash';

	/// en: 'Apply'
	String get stashApply => 'Apply';

	/// en: 'Drop'
	String get stashDrop => 'Drop';

	/// en: 'Drop {selector: String}? This cannot be undone.'
	String stashDropConfirmBody({required String selector}) => 'Drop ${selector}? This cannot be undone.';

	/// en: 'Pop'
	String get stashPop => 'Pop';

	/// en: 'Subject copied to clipboard'
	String get subjectCopied => 'Subject copied to clipboard';

	/// en: 'Message (optional)'
	String get tagMessageLabel => 'Message (optional)';

	/// en: 'Tag name'
	String get tagNameLabel => 'Tag name';

	/// en: 'Tags'
	String get tags => 'Tags';

	/// en: 'Git Graph'
	String get title => 'Git Graph';

	/// en: 'Uncommitted changes'
	String get uncommittedChanges => 'Uncommitted changes';

	/// en: 'View this branch's history'
	String get viewBranchHistory => 'View this branch\'s history';

	/// en: 'View this tag's history'
	String get viewTagHistory => 'View this tag\'s history';
}

// Path: github
class AppLocalizations$github$en {
	AppLocalizations$github$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Use a personal access token'
	String get advancedPat => 'Use a personal access token';

	/// en: 'When GitHub sign-in is unavailable, or you prefer a token with repo scope.'
	String get advancedPatSubtitle => 'When GitHub sign-in is unavailable, or you prefer a token with repo scope.';

	/// en: 'GitHub authorization cancelled'
	String get authDenied => 'GitHub authorization cancelled';

	/// en: 'GitHub sign-in expired'
	String get authExpired => 'GitHub sign-in expired';

	/// en: 'Authorization expired. Try again.'
	String get authExpiredRetry => 'Authorization expired. Try again.';

	/// en: 'Browser opened for authorization'
	String get browserOpened => 'Browser opened for authorization';

	/// en: 'Connected as @{login}'
	String connectedAs({required Object login}) => 'Connected as @${login}';

	/// en: 'Connected to GitHub'
	String get connectedGeneric => 'Connected to GitHub';

	/// en: 'GitHub sign-in is unavailable in this build. Use a personal access token.'
	String get deviceFlowUnavailable => 'GitHub sign-in is unavailable in this build. Use a personal access token.';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Could not reach GitHub. Try again.'
	String get networkError => 'Could not reach GitHub. Try again.';

	/// en: 'Reopen browser'
	String get reopenBrowser => 'Reopen browser';

	/// en: 'Connect GitHub to publish experts and teams to Hub'
	String get settingsSubtitle => 'Connect GitHub to publish experts and teams to Hub';

	/// en: 'GitHub'
	String get settingsTitle => 'GitHub';

	/// en: 'Sign in with GitHub'
	String get signIn => 'Sign in with GitHub';

	/// en: 'Switch account'
	String get switchAccount => 'Switch account';

	/// en: 'Enter this code on GitHub if prompted'
	String get waitingCodeHint => 'Enter this code on GitHub if prompted';
}

// Path: grok
class AppLocalizations$grok$en {
	AppLocalizations$grok$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'The Grok action failed'
	String get credentialsActionFailed => 'The Grok action failed';

	/// en: 'Cancel'
	String get credentialsCancel => 'Cancel';

	/// en: 'Done'
	String get credentialsDone => 'Done';

	/// en: 'Sign in'
	String get credentialsLogin => 'Sign in';

	/// en: 'Grok CLI exited. Close this dialog and start the sign-in again.'
	String get credentialsLoginExited => 'Grok CLI exited. Close this dialog and start the sign-in again.';

	/// en: 'Could not start the login terminal: {error: String}'
	String credentialsLoginFailed({required String error}) => 'Could not start the login terminal: ${error}';

	/// en: 'Complete the device sign-in in the terminal below. Grok prints a code and opens a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.'
	String get credentialsLoginIntro => 'Complete the device sign-in in the terminal below. Grok prints a code and opens a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.';

	/// en: 'Starting Grok CLI…'
	String get credentialsLoginStarting => 'Starting Grok CLI…';

	/// en: 'Sign in to Grok'
	String get credentialsLoginTitle => 'Sign in to Grok';

	/// en: 'Relaunch'
	String get credentialsRelaunch => 'Relaunch';

	/// en: 'Signed in'
	String get credentialsSignedIn => 'Signed in';

	/// en: 'Import existing login'
	String get credentialsImportGlobal => 'Import existing login';
}

// Path: home
class AppLocalizations$home$en {
	AppLocalizations$home$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Stop retrying'
	String get connectionCancelRetry => 'Stop retrying';

	/// en: 'Authentication failed'
	String get connectionErrorAuth => 'Authentication failed';

	/// en: 'Host identity changed — re-pair or confirm the new key'
	String get connectionErrorHostKey => 'Host identity changed — re-pair or confirm the new key';

	/// en: 'Network unreachable'
	String get connectionErrorTcp => 'Network unreachable';

	/// en: 'Connection timed out'
	String get connectionErrorTimeout => 'Connection timed out';

	/// en: 'Connection error'
	String get connectionErrorTransport => 'Connection error';

	/// en: 'Unknown error'
	String get connectionErrorUnknown => 'Unknown error';

	/// en: 'Retry now'
	String get connectionRetryNow => 'Retry now';

	/// en: 'Retrying… attempt {count: int}'
	String connectionRetrying({required int count}) => 'Retrying… attempt ${count}';

	/// en: 'Switch connection'
	String get connectionSwitch => 'Switch connection';

	/// en: 'Can't reach {host: String}:{port: int}'
	String connectionUnreachable({required String host, required int port}) => 'Can\'t reach ${host}:${port}';

	/// en: 'This is the only available home on this platform.'
	String get targetSingleOptionHint => 'This is the only available home on this platform.';

	/// en: 'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.'
	String get targetSubtitle => 'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.';

	/// en: 'Home device'
	String get targetTitle => 'Home device';
}

// Path: homeWorkspace
class AppLocalizations$homeWorkspace$en {
	AppLocalizations$homeWorkspace$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'All workspaces'
	String get allWorkspaces => 'All workspaces';

	/// en: 'Clone workspace'
	String get cloneWorkspace => 'Clone workspace';

	/// en: '{name} (copy)'
	String cloneWorkspaceDisplayName({required Object name}) => '${name} (copy)';

	/// en: 'Could not clone workspace'
	String get cloneWorkspaceFailed => 'Could not clone workspace';

	/// en: 'Cloned "{name}".'
	String cloneWorkspaceSuccess({required Object name}) => 'Cloned "${name}".';

	/// en: '(one) {Closing all tabs will end 1 running session.} (other) {Closing all tabs will end {count: int} running sessions.}'
	String closeAllTabsMessage({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'Closing all tabs will end 1 running session.',
		other: 'Closing all tabs will end ${count} running sessions.',
	);

	/// en: 'Close all tabs?'
	String get closeAllTabsTitle => 'Close all tabs?';

	/// en: 'Close & end sessions'
	String get closeWorkspaceConfirm => 'Close & end sessions';

	/// en: '(one) {Closing this tab will end 1 running session in this workspace.} (other) {Closing this tab will end {count: int} running sessions in this workspace.}'
	String closeWorkspaceMessage({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'Closing this tab will end 1 running session in this workspace.',
		other: 'Closing this tab will end ${count} running sessions in this workspace.',
	);

	/// en: 'Close workspace?'
	String get closeWorkspaceTitle => 'Close workspace?';

	/// en: 'Coming soon'
	String get comingSoon => 'Coming soon';

	/// en: 'Conversations'
	String get conversations => 'Conversations';

	/// en: 'Conversations'
	String get conversationsSection => 'Conversations';

	/// en: 'Create team'
	String get createTeam => 'Create team';

	/// en: 'Create workspace'
	String get createWorkspace => 'Create workspace';

	/// Name shown for the built-in default mixed team created on first launch.
	///
	/// en: 'Default Mixed Team'
	String get defaultMixedTeamName => 'Default Mixed Team';

	/// Name shown for the built-in default native team created on first launch.
	///
	/// en: 'Default Native Team'
	String get defaultNativeTeamName => 'Default Native Team';

	/// Name shown for the built-in personal workspace in simple mode.
	///
	/// en: 'Personal assistant'
	String get defaultPersonalWorkspaceName => 'Personal assistant';

	/// en: 'No workspaces in this team yet'
	String get emptyWorkspaces => 'No workspaces in this team yet';

	/// en: 'Create or import a workspace to get started'
	String get emptyWorkspacesHint => 'Create or import a workspace to get started';

	/// en: 'Favorite workspace'
	String get favoriteWorkspace => 'Favorite workspace';

	/// en: 'Import'
	String get importWorkspace => 'Import';

	/// en: 'Invite'
	String get inviteMembers => 'Invite';

	/// en: 'Open with…'
	String get launchWorkspaceTitle => 'Open with…';

	/// en: 'Workspace'
	String get mainWindow => 'Workspace';

	/// en: 'My favorites'
	String get myFavorites => 'My favorites';

	/// en: 'New Conversation'
	String get newConversation => 'New Conversation';

	/// en: 'New conversation with CLI…'
	String get newConversationChooseCli => 'New conversation with CLI…';

	/// en: 'New Team'
	String get newTeam => 'New Team';

	/// en: 'AI generate'
	String get newTeamMethodAi => 'AI generate';

	/// en: 'Custom'
	String get newTeamMethodCustom => 'Custom';

	/// en: 'Beta'
	String get newTeamModeBeta => 'Beta';

	/// en: 'Enter a team name'
	String get newTeamNameHint => 'Enter a team name';

	/// en: 'Recommended'
	String get newTeamRecommended => 'Recommended';

	/// en: 'Pick how the team collaborates, then name it.'
	String get newTeamSubtitle => 'Pick how the team collaborates, then name it.';

	/// en: 'Describe your team and generate a draft with AI.'
	String get newTeamSubtitleAi => 'Describe your team and generate a draft with AI.';

	/// en: 'Choose folder'
	String get newWorkspaceChooseDirectory => 'Choose folder';

	/// en: 'No directory selected yet'
	String get newWorkspaceDirectoryHint => 'No directory selected yet';

	/// en: 'Workspace directory'
	String get newWorkspaceDirectoryLabel => 'Workspace directory';

	/// en: 'Defaults to the folder name'
	String get newWorkspaceNameHint => 'Defaults to the folder name';

	/// en: 'Choose a working directory and name your workspace.'
	String get newWorkspaceSubtitle => 'Choose a working directory and name your workspace.';

	/// en: 'No conversations in this workspace yet'
	String get noConversations => 'No conversations in this workspace yet';

	/// en: 'No data yet'
	String get noData => 'No data yet';

	/// en: 'No conversations match your search'
	String get noSearchResults => 'No conversations match your search';

	/// en: 'Open in new tab with other identity…'
	String get openInNewTabWithOtherIdentity => 'Open in new tab with other identity…';

	/// en: 'Open'
	String get openTabs => 'Open';

	/// en: 'Open in new tab'
	String get openWorkspaceInNewTab => 'Open in new tab';

	/// en: 'Owner'
	String get owner => 'Owner';

	/// en: 'Simple mode'
	String get personal => 'Simple mode';

	/// en: 'Skip the team setup — just launch a single CLI and start chatting.'
	String get personalSubtitle => 'Skip the team setup — just launch a single CLI and start chatting.';

	/// en: 'Providers'
	String get providers => 'Providers';

	/// en: 'Recent'
	String get recentVisits => 'Recent';

	/// en: 'Recently closed'
	String get recentlyClosed => 'Recently closed';

	/// en: 'No recently closed workspaces'
	String get recentlyClosedEmpty => 'No recently closed workspaces';

	/// en: 'Remember my choice'
	String get rememberLaunchChoice => 'Remember my choice';

	/// en: 'Rename workspace'
	String get renameWorkspace => 'Rename workspace';

	/// en: 'Search'
	String get searchHint => 'Search';

	/// en: 'sessions'
	String get sessionsLabel => 'sessions';

	/// en: 'Simple mode'
	String get simpleMode => 'Simple mode';

	/// en: 'Team config'
	String get teamConfig => 'Team config';

	/// en: 'Workspaces'
	String get teamWorkspaces => 'Workspaces';

	/// en: 'Remove from favorites'
	String get unfavoriteWorkspace => 'Remove from favorites';

	/// en: '(one) {1 additional directory} (other) {{count: int} additional directories}'
	String workspaceAdditionalDirsCount({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '1 additional directory',
		other: '${count} additional directories',
	);

	/// en: 'Agent'
	String get workspaceAgent => 'Agent';

	/// en: 'Extensions'
	String get workspaceExtensions => 'Extensions';

	/// en: 'No workspaces match your filter'
	String get workspaceFilterEmpty => 'No workspaces match your filter';

	/// en: 'Filter workspaces'
	String get workspaceFilterHint => 'Filter workspaces';

	/// en: 'Hooks'
	String get workspaceHooks => 'Hooks';

	/// en: 'Workspace ID'
	String get workspaceId => 'Workspace ID';

	/// en: 'Workspaces'
	String get workspaceList => 'Workspaces';

	/// en: 'Workspace management'
	String get workspaceManagement => 'Workspace management';

	/// en: 'MCP'
	String get workspaceMcp => 'MCP';

	/// en: 'Members'
	String get workspaceMembers => 'Members';

	/// en: 'Workspace path'
	String get workspacePath => 'Workspace path';

	/// en: 'Plugins'
	String get workspacePlugins => 'Plugins';

	/// en: 'Workspace settings'
	String get workspaceSettings => 'Workspace settings';

	/// en: 'Basic information'
	String get workspaceSettingsBasicInfo => 'Basic information';

	/// en: 'Use Manage on additional directories to add or remove folders in this workspace.'
	String get workspaceSettingsPathsHint => 'Use Manage on additional directories to add or remove folders in this workspace.';

	/// en: 'Basic'
	String get workspaceSettingsSectionBasic => 'Basic';

	/// en: 'Skills'
	String get workspaceSkills => 'Skills';

	/// en: 'Sort workspaces'
	String get workspaceSort => 'Sort workspaces';

	/// en: 'Date created'
	String get workspaceSortCreatedDesc => 'Date created';

	/// en: 'Name (A–Z)'
	String get workspaceSortNameAsc => 'Name (A–Z)';

	/// en: 'Name (Z–A)'
	String get workspaceSortNameDesc => 'Name (Z–A)';

	/// en: 'Recently updated'
	String get workspaceSortRecentlyUpdated => 'Recently updated';

	/// en: 'Session count'
	String get workspaceSortSessionCountDesc => 'Session count';
}

// Path: hook
class AppLocalizations$hook$en {
	AppLocalizations$hook$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Command'
	String get actionCommand => 'Command';

	/// en: 'Script'
	String get actionScript => 'Script';

	/// en: 'Capability matrix'
	String get capabilityMatrix => 'Capability matrix';

	/// en: 'Description'
	String get description => 'Description';

	/// en: 'Edit hook'
	String get edit => 'Edit hook';

	/// en: 'Environment (KEY=VALUE per line)'
	String get env => 'Environment (KEY=VALUE per line)';

	/// en: 'Event'
	String get event => 'Event';

	/// en: 'Import'
	String get import => 'Import';

	/// en: 'CLI'
	String get importCli => 'CLI';

	/// en: '(one) {Import {count: int} hook} (other) {Import {count: int} hooks}'
	String importDone({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: 'Import ${count} hook',
		other: 'Import ${count} hooks',
	);

	/// en: 'Hooks imported'
	String get importDoneToast => 'Hooks imported';

	/// en: 'Invalid hook JSON'
	String get importInvalidJson => 'Invalid hook JSON';

	/// en: 'Hook JSON'
	String get importJson => 'Hook JSON';

	/// en: 'Paste settings.json hooks, hooks.json, or a hooks fragment…'
	String get importJsonHint => 'Paste settings.json hooks, hooks.json, or a hooks fragment…';

	/// en: 'No hooks found'
	String get importNoHooks => 'No hooks found';

	/// en: 'Will overwrite'
	String get importOverwrite => 'Will overwrite';

	/// en: 'Parse'
	String get importParse => 'Parse';

	/// en: '{count: int} installed'
	String installedCount({required int count}) => '${count} installed';

	/// en: 'Matcher'
	String get matcher => 'Matcher';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Name is required'
	String get nameRequired => 'Name is required';

	/// en: 'Hooks'
	String get navTitle => 'Hooks';

	/// en: 'New hook'
	String get kNew => 'New hook';

	/// en: 'Policy'
	String get policy => 'Policy';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Failed to save hook.'
	String get saveFailed => 'Failed to save hook.';

	/// en: 'View support matrix'
	String get supportMatrix => 'View support matrix';

	/// en: 'Timeout (seconds)'
	String get timeoutSec => 'Timeout (seconds)';
}

// Path: hub
class AppLocalizations$hub$en {
	AppLocalizations$hub$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Sign in with GitHub to authorize a fork-based pull request into the Hub registry.'
	String get publishAuthHint => 'Sign in with GitHub to authorize a fork-based pull request into the Hub registry.';

	/// en: 'Author'
	String get publishAuthorLabel => 'Author';

	/// en: 'PR open'
	String get publishBadgePrOpen => 'PR open';

	/// en: 'Published'
	String get publishBadgePublished => 'Published';

	/// en: 'Category is required'
	String get publishCategoryRequired => 'Category is required';

	/// en: 'Review the package metadata, then publish a fork-based pull request.'
	String get publishConfirmHint => 'Review the package metadata, then publish a fork-based pull request.';

	/// en: 'Copy link'
	String get publishCopyLink => 'Copy link';

	/// en: 'Done'
	String get publishDone => 'Done';

	/// en: 'Publish expert to Hub'
	String get publishExpertTitle => 'Publish expert to Hub';

	/// en: 'All dependencies look portable. Continue to confirm.'
	String get publishGatesClear => 'All dependencies look portable. Continue to confirm.';

	/// en: 'Expert'
	String get publishKindExpert => 'Expert';

	/// en: 'Kind'
	String get publishKindLabel => 'Kind';

	/// en: 'Team'
	String get publishKindTeam => 'Team';

	/// en: 'Remap every local expert before continuing'
	String get publishLocalExpertBlocked => 'Remap every local expert before continuing';

	/// en: 'Local experts on the roster must be remapped to a published or builtin expert before upload.'
	String get publishLocalExpertHint => 'Local experts on the roster must be remapped to a published or builtin expert before upload.';

	/// en: 'Next'
	String get publishNext => 'Next';

	/// en: 'Remove non-portable dependencies before continuing'
	String get publishNonPortableBlocked => 'Remove non-portable dependencies before continuing';

	/// en: 'These dependencies have no portable provenance. Remove them from the team bundle before publishing:'
	String get publishNonPortableHint => 'These dependencies have no portable provenance. Remove them from the team bundle before publishing:';

	/// en: 'Open PR'
	String get publishOpenPr => 'Open PR';

	/// en: 'Publish'
	String get publishPublish => 'Publish';

	/// en: 'Publish as'
	String get publishRemapLabel => 'Publish as';

	/// en: 'url-safe-id'
	String get publishSlugHint => 'url-safe-id';

	/// en: 'Slug'
	String get publishSlugLabel => 'Slug';

	/// en: 'Slug is required'
	String get publishSlugRequired => 'Slug is required';

	/// en: 'Pull request opened. Share or open the link below.'
	String get publishSuccessHint => 'Pull request opened. Share or open the link below.';

	/// en: 'Publish team to Hub'
	String get publishTeamTitle => 'Publish team to Hub';

	/// en: 'ghp_…'
	String get publishTokenHint => 'ghp_…';

	/// en: 'GitHub token'
	String get publishTokenLabel => 'GitHub token';

	/// en: 'GitHub token is required to publish'
	String get publishTokenRequired => 'GitHub token is required to publish';

	/// en: 'Could not save the GitHub token'
	String get publishTokenSaveFailed => 'Could not save the GitHub token';

	/// en: 'A token is already saved. You can replace it below.'
	String get publishTokenStored => 'A token is already saved. You can replace it below.';
}

// Path: init
class AppLocalizations$init$en {
	AppLocalizations$init$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Copied'
	String get errorCopied => 'Copied';

	/// en: 'Copy'
	String get errorCopy => 'Copy';

	/// en: 'Copy report'
	String get errorCopyReport => 'Copy report';

	/// en: 'Error details'
	String get errorDetails => 'Error details';

	/// en: 'Pending logs'
	String get errorPendingLogs => 'Pending logs';

	/// en: 'Stack trace is empty.'
	String get errorStackEmpty => 'Stack trace is empty.';

	/// en: 'Stack trace'
	String get errorStackTrace => 'Stack trace';

	/// en: 'Startup failed'
	String get errorTitle => 'Startup failed';

	/// en: 'Version {version: String} ({build: String})'
	String errorVersion({required String version, required String build}) => 'Version ${version} (${build})';

	/// en: 'View logs'
	String get errorViewLogs => 'View logs';
}

// Path: landing
class AppLocalizations$landing$en {
	AppLocalizations$landing$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: '{cli: String} only supports ACP chat, and the selected target ({target: String}) cannot run ACP. Choose a local, SSH, or Termux target, or pick a CLI with terminal support.'
	String launchAcpUnsupported({required String cli, required String target}) => '${cli} only supports ACP chat, and the selected target (${target}) cannot run ACP. Choose a local, SSH, or Termux target, or pick a CLI with terminal support.';

	/// en: '{cli: String} ACP adapter not found'
	String launchLocalAdapterMissingDetail({required String cli}) => '${cli} ACP adapter not found';

	/// en: 'Install the required AI CLIs on this device before starting.'
	String get launchLocalCliMissing => 'Install the required AI CLIs on this device before starting.';

	/// en: '{cli: String} not found'
	String launchLocalCliMissingDetail({required String cli}) => '${cli} not found';

	/// en: 'Install it here, or set its executable path in Settings → CLI.'
	String get launchLocalCliMissingHint => 'Install it here, or set its executable path in Settings → CLI.';

	/// en: 'Required AI CLIs on this device'
	String get launchLocalCliMissingTitle => 'Required AI CLIs on this device';

	/// en: 'Open settings'
	String get launchLocalCliOpenSettings => 'Open settings';

	/// en: 'Install required CLIs on remote machines before starting.'
	String get launchRemoteCliMissing => 'Install required CLIs on remote machines before starting.';

	/// en: '{cli: String} on {host: String}'
	String launchRemoteCliMissingDetail({required String cli, required String host}) => '${cli} on ${host}';

	/// en: 'Changes apply to this team's global configuration.'
	String get teamSettingsGlobalHint => 'Changes apply to this team\'s global configuration.';

	/// en: 'Machine assignment'
	String get teamSettingsNavMachines => 'Machine assignment';

	/// en: 'Team defaults'
	String get teamSettingsNavTeam => 'Team defaults';
}

// Path: llm
class AppLocalizations$llm$en {
	AppLocalizations$llm$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Provider'
	String get config => 'Provider';

	/// en: 'Active file:'
	String get configCurrentEffectivePathPrefix => 'Active file:';

	/// en: 'Could not resolve a path yet (set the CLI location or enter a path).'
	String get configEffectivePathUnresolved => 'Could not resolve a path yet (set the CLI location or enter a path).';

	/// en: 'Session settings…'
	String get configOpenSessionSettings => 'Session settings…';

	/// en: 'Manage LLM providers and models.'
	String get configPageSubtitle => 'Manage LLM providers and models.';

	/// en: 'custom'
	String get configPathBadgeCustom => 'custom';

	/// en: 'default'
	String get configPathBadgeDefault => 'default';

	/// en: 'Browse...'
	String get configPathBrowse => 'Browse...';

	/// en: 'Leave empty to use the default path'
	String get configPathHint => 'Leave empty to use the default path';

	/// en: 'LLM config file'
	String get configPathLabel => 'LLM config file';

	/// en: 'Select llm_config.json'
	String get configPathPickerTitle => 'Select llm_config.json';

	/// en: 'Use default'
	String get configPathReset => 'Use default';

	/// en: 'Apply'
	String get configPathSave => 'Apply';

	/// en: 'Absolute path to the LLM config file (llm_config.json). Leave empty to use the default path next to the CLI install.'
	String get configPathSessionCardDescription => 'Absolute path to the LLM config file (llm_config.json). Leave empty to use the default path next to the CLI install.';

	/// en: 'Absolute path to llm_config.json on the remote SSH host. Leave empty to use the default path next to the remote CLI install.'
	String get configPathSessionCardDescriptionSsh => 'Absolute path to llm_config.json on the remote SSH host. Leave empty to use the default path next to the remote CLI install.';

	/// en: 'providers and models'
	String get configSubtitle => 'providers and models';
}

// Path: log
class AppLocalizations$log$en {
	AppLocalizations$log$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'ACP protocol frames (off by default)'
	String get viewerAcpFrames => 'ACP protocol frames (off by default)';

	/// en: 'More actions'
	String get viewerActionsMenu => 'More actions';

	/// en: 'All filtered logs copied'
	String get viewerAllCopied => 'All filtered logs copied';

	/// en: 'Old log files removed'
	String get viewerClearDone => 'Old log files removed';

	/// en: 'Cleanup failed: {error: String}'
	String viewerClearFailed({required String error}) => 'Cleanup failed: ${error}';

	/// en: 'Remove old logs'
	String get viewerClearOld => 'Remove old logs';

	/// en: 'Compact view'
	String get viewerCompactView => 'Compact view';

	/// en: 'Copy all logs'
	String get viewerCopyAll => 'Copy all logs';

	/// en: 'Copy log path'
	String get viewerCopyPath => 'Copy log path';

	/// en: 'No log files yet'
	String get viewerEmpty => 'No log files yet';

	/// en: 'Logs are created while the app runs.'
	String get viewerEmptyHint => 'Logs are created while the app runs.';

	/// en: 'Log file'
	String get viewerFileLabel => 'Log file';

	/// en: 'Level'
	String get viewerFilterLevel => 'Level';

	/// en: 'Filters'
	String get viewerFilterTitle => 'Filters';

	/// en: '{count: int} lines'
	String viewerLineCount({required int count}) => '${count} lines';

	/// en: 'Failed to list logs: {error: String}'
	String viewerLoadFilesFailed({required String error}) => 'Failed to list logs: ${error}';

	/// en: 'Copied path: {name: String}'
	String viewerPathCopied({required String name}) => 'Copied path: ${name}';

	/// en: 'Buffered entries waiting for file logging:'
	String get viewerPendingBody => 'Buffered entries waiting for file logging:';

	/// en: 'Logs not on disk yet'
	String get viewerPendingTitle => 'Logs not on disk yet';

	/// en: 'Failed to read log: {error: String}'
	String viewerReadFailed({required String error}) => 'Failed to read log: ${error}';

	/// en: 'Refresh'
	String get viewerRefresh => 'Refresh';

	/// en: 'Newest first'
	String get viewerReverseOrder => 'Newest first';

	/// en: 'Search logs…'
	String get viewerSearchHint => 'Search logs…';

	/// en: 'Application and error logs under your TeamPilot app data folder.'
	String get viewerSubtitle => 'Application and error logs under your TeamPilot app data folder.';

	/// en: 'Logs'
	String get viewerTitle => 'Logs';

	/// en: 'Wrap lines'
	String get viewerWrapLines => 'Wrap lines';
}

// Path: managedProviders
class AppLocalizations$managedProviders$en {
	AppLocalizations$managedProviders$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Adapter'
	String get adapter => 'Adapter';

	/// en: 'http-json or a registered adapter id'
	String get adapterHint => 'http-json or a registered adapter id';

	/// en: 'Add provider'
	String get add => 'Add provider';

	/// en: 'Adapter, kind, and internal reference.'
	String get advancedSectionSubtitle => 'Adapter, kind, and internal reference.';

	/// en: 'Adapter, kind, and reference'
	String get advancedSectionTitle => 'Adapter, kind, and reference';

	/// en: 'Provider authentication failed.'
	String get authenticationFailed => 'Provider authentication failed.';

	/// en: 'Name and any required secret.'
	String get basicsSectionSubtitle => 'Name and any required secret.';

	/// en: 'Name and API key'
	String get basicsSectionTitle => 'Name and API key';

	/// en: 'Pick a preset, name the provider, and add a secret if needed.'
	String get basicsSummary => 'Pick a preset, name the provider, and add a secret if needed.';

	/// en: 'Cached usage'
	String get cachedUsage => 'Cached usage';

	/// en: 'Cached usage · needs refresh'
	String get cachedUsageStale => 'Cached usage · needs refresh';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Credential configured · secret is masked'
	String get credentialConfigured => 'Credential configured · secret is masked';

	/// en: 'Secret field name'
	String get credentialField => 'Secret field name';

	/// en: 'Field name in local storage.'
	String get credentialFieldHelper => 'Field name in local storage.';

	/// en: 'apiKey or accessToken'
	String get credentialFieldHint => 'apiKey or accessToken';

	/// en: 'Enter the credential field before saving the API key.'
	String get credentialFieldRequired => 'Enter the credential field before saving the API key.';

	/// en: 'No API-key providers configured yet'
	String get credentialLinkEmpty => 'No API-key providers configured yet';

	/// en: 'Enter secret manually'
	String get credentialLinkManual => 'Enter secret manually';

	/// en: 'Credential source mode'
	String get credentialLinkMode => 'Credential source mode';

	/// en: 'Using credential of {provider}'
	String credentialLinkedTo({required Object provider}) => 'Using credential of ${provider}';

	/// en: 'Credential parameter name'
	String get credentialName => 'Credential parameter name';

	/// en: 'Parameter name on the request.'
	String get credentialNameHelper => 'Parameter name on the request.';

	/// en: 'Authorization or Cookie'
	String get credentialNameHint => 'Authorization or Cookie';

	/// en: 'No credential configured'
	String get credentialNone => 'No credential configured';

	/// en: 'Credential placement'
	String get credentialPlacement => 'Credential placement';

	/// en: 'header or query.'
	String get credentialPlacementHelper => 'header or query.';

	/// en: 'header or query'
	String get credentialPlacementHint => 'header or query';

	/// en: 'Credential reference'
	String get credentialRef => 'Credential reference';

	/// en: 'Reference only; secret values are never shown'
	String get credentialRefHint => 'Reference only; secret values are never shown';

	/// en: 'Unable to save provider credentials securely.'
	String get credentialSaveFailed => 'Unable to save provider credentials securely.';

	/// en: 'API key / token'
	String get credentialSecret => 'API key / token';

	/// en: 'Leave blank to keep the stored secret'
	String get credentialSecretExistingHint => 'Leave blank to keep the stored secret';

	/// en: 'Leave blank to keep the stored secret.'
	String get credentialSecretHelper => 'Leave blank to keep the stored secret.';

	/// en: 'Paste the provider API key or token'
	String get credentialSecretHint => 'Paste the provider API key or token';

	/// en: 'Credential source'
	String get credentialSource => 'Credential source';

	/// en: 'secret reads the form; cli:… reads CLI login.'
	String get credentialSourceHelper => 'secret reads the form; cli:… reads CLI login.';

	/// en: 'secret or cli:cursor-mp-<entry>'
	String get credentialSourceHint => 'secret or cli:cursor-mp-<entry>';

	/// en: 'Credential template'
	String get credentialTemplate => 'Credential template';

	/// en: 'Builds the final credential; often a Cookie with brace variables.'
	String get credentialTemplateHelper => 'Builds the final credential; often a Cookie with brace variables.';

	/// en: 'e.g. WorkosCursorSessionToken=user::token'
	String get credentialTemplateHint => 'e.g. WorkosCursorSessionToken=user::token';

	/// en: 'Credentials'
	String get credentials => 'Credentials';

	/// en: 'Credential source and how it is sent.'
	String get credentialsSectionSubtitle => 'Credential source and how it is sent.';

	/// en: 'Credential source and delivery'
	String get credentialsSectionTitle => 'Credential source and delivery';

	/// en: 'Currency'
	String get currency => 'Currency';

	/// en: 'Currency is read from the response mapping when set.'
	String get currencyMappingHelper => 'Currency is read from the response mapping when set.';

	/// en: 'Decimal places must be a whole number.'
	String get decimalError => 'Decimal places must be a whole number.';

	/// en: 'Decimals'
	String get decimals => 'Decimals';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Delete “{name}” and its cached usage?'
	String deleteContent({required Object name}) => 'Delete “${name}” and its cached usage?';

	/// en: 'Unable to delete managed provider.'
	String get deleteFailed => 'Unable to delete managed provider.';

	/// en: 'Delete managed provider?'
	String get deleteTitle => 'Delete managed provider?';

	/// en: 'Disable'
	String get disable => 'Disable';

	/// en: 'Disabled'
	String get disabled => 'Disabled';

	/// en: 'Display configuration'
	String get display => 'Display configuration';

	/// en: 'How balances and quotas are shown.'
	String get displaySectionSubtitle => 'How balances and quotas are shown.';

	/// en: 'Balance and quota display'
	String get displaySectionTitle => 'Balance and quota display';

	/// en: 'Currency comes from the response mapping.'
	String get dynamicCurrencyHelper => 'Currency comes from the response mapping.';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Edit Managed Provider'
	String get editTitle => 'Edit Managed Provider';

	/// en: 'Add a provider to track balances and quotas independently from CLI providers.'
	String get emptyHint => 'Add a provider to track balances and quotas independently from CLI providers.';

	/// en: 'No managed providers'
	String get emptyTitle => 'No managed providers';

	/// en: 'Enable'
	String get enable => 'Enable';

	/// en: 'Enabled'
	String get enabled => 'Enabled';

	/// en: 'Hides the provider and stops queries when off.'
	String get enabledSubtitle => 'Hides the provider and stops queries when off.';

	/// en: 'Enabled'
	String get enabledTitle => 'Enabled';

	/// en: 'Usage API URL'
	String get endpoint => 'Usage API URL';

	/// en: 'Enter an HTTPS or loopback endpoint for this HTTP adapter.'
	String get endpointError => 'Enter an HTTPS or loopback endpoint for this HTTP adapter.';

	/// en: 'URL used to fetch usage data.'
	String get endpointHelper => 'URL used to fetch usage data.';

	/// en: 'https://api.example.com/usage'
	String get endpointHint => 'https://api.example.com/usage';

	/// en: 'Error'
	String get error => 'Error';

	/// en: 'Example'
	String get fieldExampleLabel => 'Example';

	/// en: 'Field mappings must be a secret-free JSON object.'
	String get fieldMappingError => 'Field mappings must be a secret-free JSON object.';

	/// en: 'List item field mappings (JSON)'
	String get fieldMappings => 'List item field mappings (JSON)';

	/// en: '$ path per field inside each array item.'
	String get fieldMappingsHelper => '\$ path per field inside each array item.';

	/// en: 'Request headers (JSON)'
	String get headers => 'Request headers (JSON)';

	/// en: 'Extra headers; values may use brace placeholders.'
	String get headersHelper => 'Extra headers; values may use brace placeholders.';

	/// en: 'Accept: application/json'
	String get headersHint => 'Accept: application/json';

	/// en: 'Provider service returned an error.'
	String get httpFailed => 'Provider service returned an error.';

	/// en: 'Identity'
	String get identity => 'Identity';

	/// en: 'See $ syntax in Usage API and JSON parsing ℹ️'
	String get jsonPathSeeAlso => 'See \$ syntax in Usage API and JSON parsing ℹ️';

	/// en: 'Kind'
	String get kind => 'Kind';

	/// en: 'API balance'
	String get kindApiBalance => 'API balance';

	/// en: 'Custom HTTP'
	String get kindCustomHttp => 'Custom HTTP';

	/// en: 'Locked by the selected preset or provider template.'
	String get kindPresetLockedHelper => 'Locked by the selected preset or provider template.';

	/// en: 'Subscription quota'
	String get kindSubscriptionQuota => 'Subscription quota';

	/// en: 'Last query failed'
	String get lastQueryFailed => 'Last query failed';

	/// en: 'Unable to load managed providers.'
	String get loadFailed => 'Unable to load managed providers.';

	/// en: 'Loading usage'
	String get loadingUsage => 'Loading usage';

	/// en: 'Usage list ($)'
	String get measuresPath => 'Usage list (\$)';

	/// en: '$ path to a balance array (e.g. DeepSeek).'
	String get measuresPathHelper => '\$ path to a balance array (e.g. DeepSeek).';

	/// en: '$.balance_infos'
	String get measuresPathHint => '\$.balance_infos';

	/// en: 'HTTP method'
	String get method => 'HTTP method';

	/// en: 'Usually GET.'
	String get methodHelper => 'Usually GET.';

	/// en: 'Provider credentials are missing.'
	String get missingCredential => 'Provider credentials are missing.';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Name and adapter are required.'
	String get nameAdapterError => 'Name and adapter are required.';

	/// en: 'Visible name'
	String get nameHint => 'Visible name';

	/// en: 'Managed Providers'
	String get nav => 'Managed Providers';

	/// en: 'Provider network request failed.'
	String get networkFailed => 'Provider network request failed.';

	/// en: 'New Managed Provider'
	String get newTitle => 'New Managed Provider';

	/// en: 'No usage queried yet'
	String get noUsage => 'No usage queried yet';

	/// en: 'Enable a provider to show it in the status bar and include it in queries.'
	String get noneEnabledHint => 'Enable a provider to show it in the status bar and include it in queries.';

	/// en: 'No enabled providers'
	String get noneEnabledTitle => 'No enabled providers';

	/// en: 'Provider query completed.'
	String get queryCompleted => 'Provider query completed.';

	/// en: 'Unable to query provider usage.'
	String get queryFailed => 'Unable to query provider usage.';

	/// en: 'Usage API and JSON parsing.'
	String get querySectionSubtitle => 'Usage API and JSON parsing.';

	/// en: 'Usage API and JSON parsing'
	String get querySectionTitle => 'Usage API and JSON parsing';

	/// en: 'Query unsupported'
	String get queryUnsupported => 'Query unsupported';

	/// en: 'Claude Code'
	String get quickPresetClaudeCode => 'Claude Code';

	/// en: 'Sign in or import credentials below, or fill the same fields manually.'
	String get quickPresetClaudeCodeHint => 'Sign in or import credentials below, or fill the same fields manually.';

	/// en: 'CodeBuddy'
	String get quickPresetCodebuddy => 'CodeBuddy';

	/// en: 'Query credit balance with your CodeBuddy sign-in.'
	String get quickPresetCodebuddyHint => 'Query credit balance with your CodeBuddy sign-in.';

	/// en: 'Codex'
	String get quickPresetCodex => 'Codex';

	/// en: 'Sign in or import credentials below, or fill the same fields manually.'
	String get quickPresetCodexHint => 'Sign in or import credentials below, or fill the same fields manually.';

	/// en: 'Cursor'
	String get quickPresetCursor => 'Cursor';

	/// en: 'Sign in or import credentials below, or fill the same fields manually.'
	String get quickPresetCursorHint => 'Sign in or import credentials below, or fill the same fields manually.';

	/// en: 'Grok / Cursor / X'
	String get quickPresetGrokX => 'Grok / Cursor / X';

	/// en: 'Query the unified weekly pool and prepaid balance with your Cursor sign-in.'
	String get quickPresetGrokXHint => 'Query the unified weekly pool and prepaid balance with your Cursor sign-in.';

	/// en: 'Custom'
	String get quickPresetCustom => 'Custom';

	/// en: 'Configure endpoint, credentials, and display from scratch.'
	String get quickPresetCustomHint => 'Configure endpoint, credentials, and display from scratch.';

	/// en: 'DeepSeek'
	String get quickPresetDeepSeek => 'DeepSeek';

	/// en: 'Balance API preset; add a secret.'
	String get quickPresetDeepSeekHint => 'Balance API preset; add a secret.';

	/// en: 'Starts with safe defaults; add your credential before querying.'
	String get quickPresetHint => 'Starts with safe defaults; add your credential before querying.';

	/// en: 'OpenCode Go'
	String get quickPresetOpencodeGo => 'OpenCode Go';

	/// en: 'Zen Go subscription quota preset; add your API key.'
	String get quickPresetOpencodeGoHint => 'Zen Go subscription quota preset; add your API key.';

	/// en: 'Qoder'
	String get quickPresetQoder => 'Qoder';

	/// en: 'Qoder CN'
	String get quickPresetQoderCn => 'Qoder CN';

	/// en: 'Query plan credits with a PAT from qoder.com.cn/account/integrations.'
	String get quickPresetQoderCnHint => 'Query plan credits with a PAT from qoder.com.cn/account/integrations.';

	/// en: 'Query plan credits with a PAT from qoder.com/account/integrations.'
	String get quickPresetQoderHint => 'Query plan credits with a PAT from qoder.com/account/integrations.';

	/// en: 'Quick preset'
	String get quickPresetTitle => 'Quick preset';

	/// en: '$ — read from the HTTP response JSON $ is the whole response; $.field descends with dots. E.g. $.data, $.balance_infos[0].total_balance, $.rate_limit.used_percent Use $ in response root and quota windows (used / total / remaining / resetsAt). Braces — fill dynamic values into the request (not from the response) Put a variable name inside braces; it is replaced when the request is sent. • accessToken — access token • accountId — account id • jwt.sub — JWT sub Used in headers, cookies, and credential templates. Values come from cli:… login.'
	String get referenceSyntaxHelper => '\$ — read from the HTTP response JSON\n\$ is the whole response; \$.field descends with dots.\nE.g. \$.data, \$.balance_infos[0].total_balance, \$.rate_limit.used_percent\n\nUse \$ in response root and quota windows (used / total / remaining / resetsAt).\n\nBraces — fill dynamic values into the request (not from the response)\nPut a variable name inside braces; it is replaced when the request is sent.\n• accessToken — access token\n• accountId — account id\n• jwt.sub — JWT sub\n\nUsed in headers, cookies, and credential templates. Values come from cli:… login.';

	/// en: 'Unable to refresh provider usage.'
	String get refreshFailed => 'Unable to refresh provider usage.';

	/// en: '{percent: String}% remaining'
	String remainingPercent({required String percent}) => '${percent}% remaining';

	/// en: 'Request body (JSON)'
	String get requestMapping => 'Request body (JSON)';

	/// en: 'Request mapping must be a JSON object.'
	String get requestMappingError => 'Request mapping must be a JSON object.';

	/// en: 'For POST; leave blank for GET.'
	String get requestMappingHelper => 'For POST; leave blank for GET.';

	/// en: 'Resets in {duration: String}'
	String resetsIn({required String duration}) => 'Resets in ${duration}';

	/// en: 'Resets soon'
	String get resetsSoon => 'Resets soon';

	/// en: 'Provider response could not be parsed.'
	String get responseParseFailed => 'Provider response could not be parsed.';

	/// en: 'Response root ($)'
	String get responsePath => 'Response root (\$)';

	/// en: 'Use $ to unwrap nested data; blank starts at the response root.'
	String get responsePathHelper => 'Use \$ to unwrap nested data; blank starts at the response root.';

	/// en: '$.data'
	String get responsePathHint => '\$.data';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Unable to save managed provider.'
	String get saveFailed => 'Unable to save managed provider.';

	/// en: 'Save provider'
	String get saveProvider => 'Save provider';

	/// en: 'Managed provider saved.'
	String get saved => 'Managed provider saved.';

	/// en: 'Saving…'
	String get saving => 'Saving…';

	/// en: 'Use a credential reference instead of putting secrets in the request mapping.'
	String get secretMappingError => 'Use a credential reference instead of putting secrets in the request mapping.';

	/// en: 'Configured'
	String get sectionConfiguredBadge => 'Configured';

	/// en: 'Show percentage'
	String get showPercent => 'Show percentage';

	/// en: 'Stale'
	String get stale => 'Stale';

	/// en: 'Balances and quotas independent from CLI provider configuration.'
	String get subtitle => 'Balances and quotas independent from CLI provider configuration.';

	/// en: 'See brace syntax in Credential source and delivery ℹ️'
	String get templateVariablesSeeAlsoCredentials => 'See brace syntax in Credential source and delivery ℹ️';

	/// en: 'See brace syntax in Usage API and JSON parsing ℹ️'
	String get templateVariablesSeeAlsoQuery => 'See brace syntax in Usage API and JSON parsing ℹ️';

	/// en: 'Test provider query'
	String get testProviderQuery => 'Test provider query';

	/// en: 'Test query'
	String get testQuery => 'Test query';

	/// en: 'Managed Providers'
	String get title => 'Managed Providers';

	/// en: 'Unit'
	String get unit => 'Unit';

	/// en: 'Unknown usage status'
	String get unknownUsage => 'Unknown usage status';

	/// en: 'Provider usage was invalidated.'
	String get usageInvalidated => 'Provider usage was invalidated.';

	/// en: 'Unable to load provider usage.'
	String get usageLoadFailed => 'Unable to load provider usage.';

	/// en: 'Balances & usage'
	String get usageNav => 'Balances & usage';

	/// en: 'Unable to save provider usage.'
	String get usagePersistenceFailed => 'Unable to save provider usage.';

	/// en: 'Quota windows (JSON)'
	String get windows => 'Quota windows (JSON)';

	/// en: 'One window per quota line. Write label and $ paths for used / total / remaining / resetsAt. For array items, hard-code the index, e.g. $.balance_infos[0].total_balance.'
	String get windowsHelper => 'One window per quota line. Write label and \$ paths for used / total / remaining / resetsAt. For array items, hard-code the index, e.g. \$.balance_infos[0].total_balance.';

	/// en: 'JSON array; each item has label and $ paths'
	String get windowsHint => 'JSON array; each item has label and \$ paths';
}

// Path: mcp
class AppLocalizations$mcp$en {
	AppLocalizations$mcp$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Add MCP server'
	String get add => 'Add MCP server';

	/// en: 'Add MCP'
	String get addButton => 'Add MCP';

	/// en: 'Add MCP'
	String get addTitle => 'Add MCP';

	/// en: 'Add'
	String get catalogAdd => 'Add';

	/// en: 'MCP server added to catalog'
	String get catalogAdded => 'MCP server added to catalog';

	/// en: 'Uses'
	String get catalogAdoption => 'Uses';

	/// en: 'None'
	String get catalogCardNoDescription => 'None';

	/// en: 'No servers found'
	String get catalogEmpty => 'No servers found';

	/// en: 'Installed'
	String get catalogInstalled => 'Installed';

	/// en: 'Verified'
	String get catalogVerified => 'Verified';

	/// en: '{count: int} MCP server(s) configured'
	String configuredCount({required int count}) => '${count} MCP server(s) configured';

	/// en: 'Delete MCP server?'
	String get deleteConfirm => 'Delete MCP server?';

	/// en: 'Browse built-in templates and remote catalogs configured under Registries.'
	String get discoverySectionHint => 'Browse built-in templates and remote catalogs configured under Registries.';

	/// en: 'Discover MCP servers'
	String get discoverySectionTitle => 'Discover MCP servers';

	/// en: 'All'
	String get discoverySourceAll => 'All';

	/// en: 'Built-in'
	String get discoverySourceBuiltin => 'Built-in';

	/// en: 'Edit MCP server'
	String get edit => 'Edit MCP server';

	/// en: 'No MCP servers in catalog'
	String get empty => 'No MCP servers in catalog';

	/// en: 'Browse built-in templates'
	String get emptyGoDiscovery => 'Browse built-in templates';

	/// en: 'Open registry settings'
	String get emptyGoRegistries => 'Open registry settings';

	/// en: 'Arguments (space-separated)'
	String get fieldArgs => 'Arguments (space-separated)';

	/// en: 'Command'
	String get fieldCommand => 'Command';

	/// en: 'Name'
	String get fieldName => 'Name';

	/// en: 'Optional description'
	String get formDescriptionHint => 'Optional description';

	/// en: 'Description'
	String get formDescriptionLabel => 'Description';

	/// en: 'Select a server to edit, or add a new MCP server.'
	String get formDetailHint => 'Select a server to edit, or add a new MCP server.';

	/// en: 'e.g. @modelcontextprotocol/server-time'
	String get formDisplayNameHint => 'e.g. @modelcontextprotocol/server-time';

	/// en: 'Display name'
	String get formDisplayNameLabel => 'Display name';

	/// en: 'Documentation'
	String get formDocsLabel => 'Documentation';

	/// en: 'Format'
	String get formFormatJson => 'Format';

	/// en: 'Homepage'
	String get formHomepageLabel => 'Homepage';

	/// en: 'MCP ID (unique) *'
	String get formIdLabel => 'MCP ID (unique) *';

	/// en: 'Full JSON configuration'
	String get formJsonLabel => 'Full JSON configuration';

	/// en: 'Additional info'
	String get formMetadata => 'Additional info';

	/// en: 'MCP ID and display name are required.'
	String get formRequiredFields => 'MCP ID and display name are required.';

	/// en: 'Add'
	String get formSubmitAdd => 'Add';

	/// en: 'stdio, time, utility'
	String get formTagsHint => 'stdio, time, utility';

	/// en: 'Tags (comma-separated)'
	String get formTagsLabel => 'Tags (comma-separated)';

	/// en: 'Import from machine'
	String get import => 'Import from machine';

	/// en: 'MCP catalog updated'
	String get importDone => 'MCP catalog updated';

	/// en: 'No MCP servers found in ~/.claude.json or ~/.flashskyai.json'
	String get importEmpty => 'No MCP servers found in ~/.claude.json or ~/.flashskyai.json';

	/// en: 'Import existing'
	String get importExisting => 'Import existing';

	/// en: 'Overwrite conflicts'
	String get importOverwrite => 'Overwrite conflicts';

	/// en: '{added: int} new, {conflicts: int} conflicts'
	String importSummary({required int added, required int conflicts}) => '${added} new, ${conflicts} conflicts';

	/// en: '{count: int} installed'
	String installedCount({required int count}) => '${count} installed';

	/// en: 'Installed MCP servers'
	String get installedSectionTitle => 'Installed MCP servers';

	/// en: 'Discovery'
	String get navDiscovery => 'Discovery';

	/// en: 'Installed'
	String get navInstalled => 'Installed';

	/// en: 'Registry'
	String get navRegistries => 'Registry';

	/// en: 'MCP Servers'
	String get navTitle => 'MCP Servers';

	/// en: 'No MCP servers installed yet'
	String get noInstalled => 'No MCP servers installed yet';

	/// en: 'Open Discovery to add servers from built-in templates or registries.'
	String get noInstalledHint => 'Open Discovery to add servers from built-in templates or registries.';

	/// en: 'Paste the full URL after sign-in (contains ?code=)'
	String get oAuthCallbackUrlHint => 'Paste the full URL after sign-in (contains ?code=)';

	/// en: 'Redirect URL'
	String get oAuthCallbackUrlLabel => 'Redirect URL';

	/// en: 'Connect'
	String get oAuthConnectAction => 'Connect';

	/// en: 'Sign in with the MCP provider in your browser. Tokens are stored in Claude Code format under app config (same as /mcp → Authenticate).'
	String get oAuthConnectHint => 'Sign in with the MCP provider in your browser. Tokens are stored in Claude Code format under app config (same as /mcp → Authenticate).';

	/// en: 'MCP OAuth connected'
	String get oAuthConnectSuccess => 'MCP OAuth connected';

	/// en: 'Connect {name: String}'
	String oAuthConnectTitle({required String name}) => 'Connect ${name}';

	/// en: 'Discovering authorization server…'
	String get oAuthDiscovering => 'Discovering authorization server…';

	/// en: 'Open browser'
	String get oAuthOpenBrowser => 'Open browser';

	/// en: 'Connect'
	String get oAuthStartConnect => 'Connect';

	/// en: 'OAuth connected'
	String get oAuthStatusConnected => 'OAuth connected';

	/// en: 'Needs OAuth'
	String get oAuthStatusNeedsAuth => 'Needs OAuth';

	/// en: 'Submit URL'
	String get oAuthSubmitCallback => 'Submit URL';

	/// en: 'Open link'
	String get openHomepage => 'Open link';

	/// en: 'Up-to-date library documentation via Context7.'
	String get presetDescContext7 => 'Up-to-date library documentation via Context7.';

	/// en: 'Fetch web pages and convert HTML to markdown for LLMs.'
	String get presetDescFetch => 'Fetch web pages and convert HTML to markdown for LLMs.';

	/// en: 'Persistent memory graph for knowledge across sessions.'
	String get presetDescMemory => 'Persistent memory graph for knowledge across sessions.';

	/// en: 'Structured step-by-step reasoning for complex problems.'
	String get presetDescSequentialThinking => 'Structured step-by-step reasoning for complex problems.';

	/// en: 'Current time, timezone conversion, and date calculations.'
	String get presetDescTime => 'Current time, timezone conversion, and date calculations.';

	/// en: 'Checking…'
	String get probeChecking => 'Checking…';

	/// en: 'Needs authorization'
	String get probeNeedsAuth => 'Needs authorization';

	/// en: 'Offline'
	String get probeOffline => 'Offline';

	/// en: 'Could not reach this MCP server.'
	String get probeOfflineHint => 'Could not reach this MCP server.';

	/// en: 'Refresh status'
	String get probeRefreshAll => 'Refresh status';

	/// en: '{count: int} tools'
	String probeToolCount({required int count}) => '${count} tools';

	/// en: 'Edit API URL'
	String get registryEditTitle => 'Edit API URL';

	/// en: 'Load more'
	String get registryLoadMore => 'Load more';

	/// en: 'Official registry'
	String get registryOfficial => 'Official registry';

	/// en: 'Official MCP Registry — https://registry.modelcontextprotocol.io'
	String get registryOfficialHint => 'Official MCP Registry — https://registry.modelcontextprotocol.io';

	/// en: 'Reset "{name: String}" to the default API URL?'
	String registryResetConfirm({required String name}) => 'Reset "${name}" to the default API URL?';

	/// en: 'Reset to default'
	String get registryResetTitle => 'Reset to default';

	/// en: 'Search servers (e.g. github)'
	String get registrySearchHint => 'Search servers (e.g. github)';

	/// en: 'Smithery'
	String get registrySmithery => 'Smithery';

	/// en: 'Smithery — https://api.smithery.ai'
	String get registrySmitheryHint => 'Smithery — https://api.smithery.ai';

	/// en: 'API base URL'
	String get repoApiUrlLabel => 'API base URL';

	/// en: 'Registry API settings saved'
	String get repoConfigSaved => 'Registry API settings saved';

	/// en: 'This catalog source is disabled. Enable it under Registries.'
	String get repoDisabledHint => 'This catalog source is disabled. Enable it under Registries.';

	/// en: 'Reset default'
	String get repoResetDefault => 'Reset default';

	/// en: 'Test connection'
	String get repoTestConnection => 'Test connection';

	/// en: 'Connection failed: {error: String}'
	String repoTestFailed({required String error}) => 'Connection failed: ${error}';

	/// en: 'Connection successful'
	String get repoTestOk => 'Connection successful';

	/// en: 'MCP server not found'
	String get serverNotFound => 'MCP server not found';

	/// en: 'Smithery API key (Bearer)'
	String get smitheryApiTokenHint => 'Smithery API key (Bearer)';

	/// en: 'API token'
	String get smitheryApiTokenLabel => 'API token';

	/// en: 'token set'
	String get smitheryApiTokenSet => 'token set';

	/// en: 'Manage MCP servers for agent sessions.'
	String get subtitle => 'Manage MCP servers for agent sessions.';

	/// en: '{name: String} tools'
	String toolsDialogTitle({required String name}) => '${name} tools';

	/// en: 'Done'
	String get toolsDone => 'Done';

	/// en: 'This server has no tools.'
	String get toolsEmpty => 'This server has no tools.';

	/// en: 'Reload'
	String get toolsReload => 'Reload';

	/// en: 'Tools'
	String get toolsSection => 'Tools';
}

// Path: member
class AppLocalizations$member$en {
	AppLocalizations$member$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Assign folders…'
	String get assignFoldersAction => 'Assign folders…';

	/// en: 'Inherit team default'
	String get cliInheritHint => 'Inherit team default';

	/// en: 'Config directory'
	String get detailBrowseConfigDirTitle => 'Config directory';

	/// en: 'This member has no config yet in this session, and the team layer is empty.'
	String get detailEmpty => 'This member has no config yet in this session, and the team layer is empty.';

	/// en: 'Failed to read this member's config directory.'
	String get detailLoadError => 'Failed to read this member\'s config directory.';

	/// en: 'Open a session first'
	String get detailNeedsSession => 'Open a session first';

	/// en: 'Open config directory'
	String get detailOpenConfigDir => 'Open config directory';

	/// en: 'Couldn't open the config directory in a file manager.'
	String get detailOpenConfigDirFailed => 'Couldn\'t open the config directory in a file manager.';

	/// en: 'Couldn't open the config directory on {host: String}. The remote host may have no desktop file manager.'
	String detailOpenConfigDirFailedOnHost({required String host}) => 'Couldn\'t open the config directory on ${host}. The remote host may have no desktop file manager.';

	/// en: 'Open in file manager'
	String get detailOpenInFileManager => 'Open in file manager';

	/// en: 'None'
	String get detailSectionEmpty => 'None';

	/// en: 'Live session config'
	String get detailSourceRuntime => 'Live session config';

	/// en: 'Team-level config (member not launched in this session)'
	String get detailSourceTeam => 'Team-level config (member not launched in this session)';

	/// en: 'MCP'
	String get detailTabMcp => 'MCP';

	/// en: 'Overview'
	String get detailTabOverview => 'Overview';

	/// en: 'Plugins'
	String get detailTabPlugins => 'Plugins';

	/// en: 'Settings'
	String get detailTabSettings => 'Settings';

	/// en: 'Skills'
	String get detailTabSkills => 'Skills';

	/// en: 'Member detail'
	String get detailTitle => 'Member detail';

	/// en: 'View member detail'
	String get detailViewAction => 'View member detail';

	/// en: 'Inherit team default'
	String get effortInheritHint => 'Inherit team default';

	/// en: 'Member effort override'
	String get effortLevel => 'Member effort override';

	/// en: 'Overrides team default when set.'
	String get effortLevelSubtitle => 'Overrides team default when set.';

	/// en: 'Member extra CLI arguments'
	String get extraArgs => 'Member extra CLI arguments';

	/// en: 'Extra flags applied only when this member starts.'
	String get extraArgsSubtitle => 'Extra flags applied only when this member starts.';

	/// en: 'Uses the team's default CLI, provider, model, and effort.'
	String get launchConfigInheritHint => 'Uses the team\'s default CLI, provider, model, and effort.';

	/// en: 'Team default is not configured yet.'
	String get launchConfigInheritUnset => 'Team default is not configured yet.';

	/// en: 'CLI backend, provider, model, and effort for this member.'
	String get launchConfigSubtitle => 'CLI backend, provider, model, and effort for this member.';

	/// en: 'Model settings'
	String get launchConfigTitle => 'Model settings';

	/// en: 'Configuration type'
	String get launchConfigTypeLabel => 'Configuration type';

	/// en: 'Preset'
	String get launchConfigTypePreset => 'Preset';

	/// en: 'Member launch order'
	String get launchOrder => 'Member launch order';

	/// en: 'Member name'
	String get name => 'Member name';

	/// en: 'Display only in TeamPilot (sidebar, member list). To define responsibilities and boundaries, edit Responsibilities below.'
	String get nameSubtitle => 'Display only in TeamPilot (sidebar, member list). To define responsibilities and boundaries, edit Responsibilities below.';

	/// en: 'Uses your Claude account default model. Manage Official login in Providers settings.'
	String get officialClaudeModelHint => 'Uses your Claude account default model. Manage Official login in Providers settings.';

	/// en: 'Select an expert to see persona text.'
	String get personaEmptyNoExpert => 'Select an expert to see persona text.';

	/// en: 'Playbook'
	String get playbook => 'Playbook';

	/// en: 'No playbook on this expert'
	String get playbookEmpty => 'No playbook on this expert';

	/// en: 'Work test-first: before implementing, write a failing test, then make it pass with the smallest diff. Run the relevant tests after each change and report which files changed and why. Do not bundle unrelated edits; stop at agreed checkpoints. If a test-driven-development skill is available, follow it.'
	String get playbookPresetDeveloperText => 'Work test-first: before implementing, write a failing test, then make it pass with the smallest diff. Run the relevant tests after each change and report which files changed and why. Do not bundle unrelated edits; stop at agreed checkpoints. If a test-driven-development skill is available, follow it.';

	/// en: 'Clarify intent before digging: restate the question and your assumptions, then investigate breadth-first across the codebase before going deep. Report findings with file paths, relevant symbols, and recommended next steps—propose, do not change production code. If a brainstorming skill is available, use it to frame the problem first.'
	String get playbookPresetResearcherText => 'Clarify intent before digging: restate the question and your assumptions, then investigate breadth-first across the codebase before going deep. Report findings with file paths, relevant symbols, and recommended next steps—propose, do not change production code. If a brainstorming skill is available, use it to frame the problem first.';

	/// en: 'Review in order: (1) confirm tests cover the change; (2) correctness and edge cases; (3) maintainability and consistency with surrounding code. Every finding states file path, line, the problem, and a concrete fix—no vague praise and no nit without a fix. Flag missing tests explicitly.'
	String get playbookPresetReviewerText => 'Review in order: (1) confirm tests cover the change; (2) correctness and edge cases; (3) maintainability and consistency with surrounding code. Every finding states file path, line, the problem, and a concrete fix—no vague praise and no nit without a fix. Flag missing tests explicitly.';

	/// en: 'How to execute assigned work: steps, checkpoints, and report format. Sent to the agent as operating instructions.'
	String get playbookSubtitle => 'How to execute assigned work: steps, checkpoints, and report format. Sent to the agent as operating instructions.';

	/// en: 'Starting…'
	String get presenceBooting => 'Starting…';

	/// en: 'Connecting…'
	String get presenceConnecting => 'Connecting…';

	/// en: 'Idle'
	String get presenceIdle => 'Idle';

	/// en: 'Offline'
	String get presenceOffline => 'Offline';

	/// en: 'Working'
	String get presenceWorking => 'Working';

	/// en: 'Custom configuration'
	String get presetCustom => 'Custom configuration';

	/// en: 'Inherit team default'
	String get presetInheritTeam => 'Inherit team default';

	/// en: 'No team default set'
	String get presetInheritTeamNone => 'No team default set';

	/// en: 'Preset'
	String get presetLabel => 'Preset';

	/// en: 'Select a preset'
	String get presetSelectPreset => 'Select a preset';

	/// en: '{presetName: String} (via preset)'
	String presetViaPreset({required String presetName}) => '${presetName} (via preset)';

	/// en: '{presetName: String} (via team default)'
	String presetViaTeamDefault({required String presetName}) => '${presetName} (via team default)';

	/// en: 'Developer'
	String get promptPresetDeveloper => 'Developer';

	/// en: 'Implement assigned tasks, staying within the agreed scope. Do not expand scope or refactor unrelated code without being asked.'
	String get promptPresetDeveloperText => 'Implement assigned tasks, staying within the agreed scope. Do not expand scope or refactor unrelated code without being asked.';

	/// en: 'Researcher'
	String get promptPresetResearcher => 'Researcher';

	/// en: 'Investigate and report only. Do not change production code unless asked.'
	String get promptPresetResearcherText => 'Investigate and report only. Do not change production code unless asked.';

	/// en: 'Reviewer'
	String get promptPresetReviewer => 'Reviewer';

	/// en: 'Review code only. Do not modify files unless explicitly asked.'
	String get promptPresetReviewerText => 'Review code only. Do not modify files unless explicitly asked.';

	/// en: 'Team lead'
	String get promptPresetTeamLead => 'Team lead';

	/// en: 'Coordinate the team: break the user's request into a task list (each item with scope and acceptance criteria), then assign teammates to implement. Unless blocked, do not do large implementation yourself—you may read code and docs to understand the situation. Talk to the user in this session window. When assigning and following up, contact only other teammates (by member name); do not assign work to yourself. After teammates finish, reply to the user with conclusions, relevant files, and next steps.'
	String get promptPresetTeamLeadText => 'Coordinate the team: break the user\'s request into a task list (each item with scope and acceptance criteria), then assign teammates to implement. Unless blocked, do not do large implementation yourself—you may read code and docs to understand the situation.\nTalk to the user in this session window. When assigning and following up, contact only other teammates (by member name); do not assign work to yourself. After teammates finish, reply to the user with conclusions, relevant files, and next steps.';

	/// en: 'Presets'
	String get promptPresetsLabel => 'Presets';

	/// en: 'What this member owns and must not do. Written into the agent's role definition.'
	String get promptSubtitle => 'What this member owns and must not do. Written into the agent\'s role definition.';

	/// en: 'MEMBER QUICK LIST'
	String get quickList => 'MEMBER QUICK LIST';

	/// en: 'Responsibilities'
	String get responsibilities => 'Responsibilities';

	/// en: 'No responsibilities on this expert'
	String get responsibilitiesEmpty => 'No responsibilities on this expert';

	/// en: 'Inherit workspace folders'
	String get targetAssignmentInherit => 'Inherit workspace folders';

	/// en: 'Which machine {member} runs on (its assigned workspace folders).'
	String targetAssignmentSubtitle({required Object member}) => 'Which machine ${member} runs on (its assigned workspace folders).';

	/// en: 'Member machine'
	String get targetAssignmentTitle => 'Member machine';

	/// en: 'Terminal not started — tap to launch'
	String get terminalNotStartedTitle => 'Terminal not started — tap to launch';

	/// en: 'Tap to reconnect (the session resumes)'
	String get terminalReclaimedBody => 'Tap to reconnect (the session resumes)';

	/// en: 'Terminal reclaimed to save memory'
	String get terminalReclaimedTitle => 'Terminal reclaimed to save memory';
}

// Path: mixed
class AppLocalizations$mixed$en {
	AppLocalizations$mixed$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Confirm machine assignment in Team Settings before starting a conversation in this mixed workspace.'
	String get workspaceCreateSessionBlocked => 'Confirm machine assignment in Team Settings before starting a conversation in this mixed workspace.';

	/// en: 'Team lead must be assigned to the local machine when this workspace has a local folder.'
	String get workspaceLeadPlacementInvalid => 'Team lead must be assigned to the local machine when this workspace has a local folder.';

	/// en: 'Start team'
	String get workspaceMemberAssignmentConfirm => 'Start team';

	/// en: 'Confirm machine assignment once before starting this team in a mixed workspace.'
	String get workspaceMemberAssignmentIncomplete => 'Confirm machine assignment once before starting this team in a mixed workspace.';

	/// en: 'Select a machine on the left, then use + / − to place each member's instances on it.'
	String get workspaceMemberAssignmentSubtitle => 'Select a machine on the left, then use + / − to place each member\'s instances on it.';

	/// en: 'Assign members to machines'
	String get workspaceMemberAssignmentTitle => 'Assign members to machines';

	/// en: '{count: int} on this machine'
	String workspaceMemberPlacementOnMachine({required int count}) => '${count} on this machine';

	/// en: '{placed: int} / {total: int} assigned'
	String workspaceMemberPlacementProgress({required int placed, required int total}) => '${placed} / ${total} assigned';

	/// en: 'This is a mixed workspace. Switch to a team tab to start conversations and confirm machine assignment.'
	String get workspacePersonalLaunchBlockedHint => 'This is a mixed workspace. Switch to a team tab to start conversations and confirm machine assignment.';

	/// en: 'Mixed workspaces can only be started with a team identity. Switch to a team and confirm machine assignment in Team Settings.'
	String get workspaceRequiresTeamLaunch => 'Mixed workspaces can only be started with a team identity. Switch to a team and confirm machine assignment in Team Settings.';

	/// en: 'Machine assignment for this conversation is no longer valid. Confirm assignment in Team Settings and start a new conversation.'
	String get workspaceSessionLaunchBlocked => 'Machine assignment for this conversation is no longer valid. Confirm assignment in Team Settings and start a new conversation.';
}

// Path: my
class AppLocalizations$my$en {
	AppLocalizations$my$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'New Expert'
	String get expertsCreate => 'New Expert';

	/// en: 'Delete'
	String get expertsDelete => 'Delete';

	/// en: 'Delete expert "{name}"? This cannot be undone.'
	String expertsDeleteConfirm({required Object name}) => 'Delete expert "${name}"? This cannot be undone.';

	/// en: 'Cannot delete "{name}" — it is still referenced by one or more teams. Reassign those roster slots first.'
	String expertsDeleteReferenced({required Object name}) => 'Cannot delete "${name}" — it is still referenced by one or more teams. Reassign those roster slots first.';

	/// en: 'Edit'
	String get expertsEdit => 'Edit';

	/// en: 'Create a local expert persona to reuse across teams.'
	String get expertsEmptyHint => 'Create a local expert persona to reuse across teams.';

	/// en: 'No experts yet'
	String get expertsEmptyTitle => 'No experts yet';

	/// en: 'My Experts'
	String get expertsNav => 'My Experts';

	/// en: 'Manage your local expert personas'
	String get expertsSubtitle => 'Manage your local expert personas';

	/// en: 'My Experts'
	String get expertsTitle => 'My Experts';

	/// en: 'Upload'
	String get expertsUpload => 'Upload';

	/// en: 'Created {date}'
	String teamsCreatedAt({required Object date}) => 'Created ${date}';

	/// en: 'Create a team to manage members, skills, and plugins.'
	String get teamsEmptyHint => 'Create a team to manage members, skills, and plugins.';

	/// en: 'No teams yet'
	String get teamsEmptyTitle => 'No teams yet';

	/// en: '(one) {1 member} (other) {{count: int} members}'
	String teamsMemberCount({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '1 member',
		other: '${count} members',
	);

	/// en: 'My Teams'
	String get teamsNav => 'My Teams';

	/// en: 'Manage your local team configurations'
	String get teamsSubtitle => 'Manage your local team configurations';

	/// en: 'My Teams'
	String get teamsTitle => 'My Teams';

	/// en: 'Upload'
	String get teamsUpload => 'Upload';
}

// Path: notification
class AppLocalizations$notification$en {
	AppLocalizations$notification$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Notifications'
	String get centerTitle => 'Notifications';

	/// en: 'Clear'
	String get clearAll => 'Clear';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'No notifications'
	String get empty => 'No notifications';

	/// en: 'History'
	String get historySection => 'History';

	/// en: 'Mark all as read'
	String get markAllRead => 'Mark all as read';

	/// en: 'Mark as read'
	String get markRead => 'Mark as read';

	/// en: 'Ongoing'
	String get ongoingSection => 'Ongoing';

	/// en: '{days: int} d ago'
	String timeDaysAgo({required int days}) => '${days} d ago';

	/// en: '{hours: int} h ago'
	String timeHoursAgo({required int hours}) => '${hours} h ago';

	/// en: 'Just now'
	String get timeJustNow => 'Just now';

	/// en: '{minutes: int} min ago'
	String timeMinutesAgo({required int minutes}) => '${minutes} min ago';
}

// Path: onboarding
class AppLocalizations$onboarding$en {
	AppLocalizations$onboarding$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'You can change these later in Settings → Layout.'
	String get appearanceSubtitle => 'You can change these later in Settings → Layout.';

	/// en: 'Choose language and appearance'
	String get appearanceTitle => 'Choose language and appearance';

	/// en: 'CLI found'
	String get cliFound => 'CLI found';

	/// en: 'Not on PATH'
	String get cliNotFound => 'Not on PATH';

	/// en: 'Scan again'
	String get cliRedetect => 'Scan again';

	/// en: 'Scanning PATH for CLI tools…'
	String get cliScanning => 'Scanning PATH for CLI tools…';

	/// en: 'Locate executables used to launch sessions. Install missing ones, or set a path later in Settings.'
	String get cliSubtitle => 'Locate executables used to launch sessions. Install missing ones, or set a path later in Settings.';

	/// en: 'Detect CLI tools'
	String get cliTitle => 'Detect CLI tools';

	/// en: 'Default'
	String get defaultPresetDefaultName => 'Default';

	/// en: 'No providers to choose from. Skip this step or add providers in Settings.'
	String get defaultPresetEmpty => 'No providers to choose from. Skip this step or add providers in Settings.';

	/// en: 'Primary model for this preset'
	String get defaultPresetModelHint => 'Primary model for this preset';

	/// en: 'Use existing preset'
	String get defaultPresetSelectExisting => 'Use existing preset';

	/// en: 'Personal workspaces and team default launch configs will use this CLI preset.'
	String get defaultPresetSubtitle => 'Personal workspaces and team default launch configs will use this CLI preset.';

	/// en: 'Configure default launch preset'
	String get defaultPresetTitle => 'Configure default launch preset';

	/// en: 'Get started'
	String get getStarted => 'Get started';

	/// en: 'Next'
	String get next => 'Next';

	/// en: 'Previous'
	String get previous => 'Previous';

	/// en: 'Step {current: int} of {total: int}'
	String progress({required int current, required int total}) => 'Step ${current} of ${total}';

	/// en: 'No providers detected. You can configure them later in Settings.'
	String get providerImportEmpty => 'No providers detected. You can configure them later in Settings.';

	/// en: 'Import failed'
	String get providerImportFailed => 'Import failed';

	/// en: 'Scan again'
	String get providerImportRescan => 'Scan again';

	/// en: 'Import results'
	String get providerImportResults => 'Import results';

	/// en: 'Scan local CLI configs for existing provider settings.'
	String get providerImportSubtitle => 'Scan local CLI configs for existing provider settings.';

	/// en: 'Import CLI providers'
	String get providerImportTitle => 'Import CLI providers';

	/// en: 'Run setup wizard again'
	String get rerunSetup => 'Run setup wizard again';

	/// en: 'Skip'
	String get skip => 'Skip';

	/// en: 'Android runs AI CLIs on a remote host over SSH.'
	String get sshSubtitle => 'Android runs AI CLIs on a remote host over SSH.';

	/// en: 'Configure SSH connection'
	String get sshTitle => 'Configure SSH connection';

	/// en: 'Language & theme'
	String get stepAppearance => 'Language & theme';

	/// en: 'CLI tools'
	String get stepCli => 'CLI tools';

	/// en: 'Default preset'
	String get stepDefaultPreset => 'Default preset';

	/// en: 'Import providers'
	String get stepProviderImport => 'Import providers';

	/// en: 'SSH'
	String get stepSsh => 'SSH';

	/// en: 'First-time setup'
	String get title => 'First-time setup';

	/// en: 'Connect Termux on this device or a remote SSH host before detecting AI CLIs.'
	String get workHomeSubtitle => 'Connect Termux on this device or a remote SSH host before detecting AI CLIs.';

	/// en: 'Choose work environment'
	String get workHomeTitle => 'Choose work environment';
}

// Path: opencode
class AppLocalizations$opencode$en {
	AppLocalizations$opencode$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Could not update credentials'
	String get credentialsActionFailed => 'Could not update credentials';

	/// en: 'Credentials updated'
	String get credentialsActionSuccess => 'Credentials updated';

	/// en: 'Import auth.json…'
	String get credentialsImportFile => 'Import auth.json…';

	/// en: 'Import from opencode auth'
	String get credentialsImportGlobal => 'Import from opencode auth';

	/// en: 'Sign in with provider'
	String get credentialsLogin => 'Sign in with provider';

	/// en: 'Sign out'
	String get credentialsRevoke => 'Sign out';

	/// en: 'Sign out and remove saved credentials for {name: String}?'
	String credentialsRevokeConfirm({required String name}) => 'Sign out and remove saved credentials for ${name}?';

	/// en: 'Always allow'
	String get permissionAllowAlways => 'Always allow';

	/// en: 'Allow once'
	String get permissionAllowOnce => 'Allow once';

	/// en: 'Couldn't submit your decision. Try again or answer in the Terminal.'
	String get permissionAnswerFailed => 'Couldn\'t submit your decision. Try again or answer in the Terminal.';

	/// en: 'Answer in terminal'
	String get permissionAnswerInTerminal => 'Answer in terminal';

	/// en: 'Reject'
	String get permissionReject => 'Reject';

	/// en: 'OpenCode needs your permission'
	String get permissionTitle => 'OpenCode needs your permission';
}

// Path: plugin
class AppLocalizations$plugin$en {
	AppLocalizations$plugin$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: '{cli: String}: Fully supported'
	String cliSupportFully({required String cli}) => '${cli}: Fully supported';

	/// en: '{cli: String}: Not applicable'
	String cliSupportNotApplicable({required String cli}) => '${cli}: Not applicable';

	/// en: '{cli: String}: Partially supported ({dropped: String} dropped)'
	String cliSupportPartial({required String cli, required String dropped}) => '${cli}: Partially supported (${dropped} dropped)';

	/// en: 'agents'
	String get componentAgents => 'agents';

	/// en: 'apps'
	String get componentApps => 'apps';

	/// en: 'commands'
	String get componentCommands => 'commands';

	/// en: 'hooks'
	String get componentHooks => 'hooks';

	/// en: 'MCP'
	String get componentMcp => 'MCP';

	/// en: 'rules'
	String get componentRules => 'rules';

	/// en: 'skills'
	String get componentSkills => 'skills';
}

// Path: plugins
class AppLocalizations$plugins$en {
	AppLocalizations$plugins$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Details'
	String get cardDetails => 'Details';

	/// en: 'Install'
	String get cardInstall => 'Install';

	/// en: 'Installed'
	String get cardInstalled => 'Installed';

	/// en: 'Uninstall'
	String get cardUninstall => 'Uninstall';

	/// en: 'Update'
	String get cardUpdate => 'Update';

	/// en: 'View source'
	String get cardViewSource => 'View source';

	/// en: 'Installs'
	String get catalogAdoption => 'Installs';

	/// en: 'None'
	String get catalogCardNoDescription => 'None';

	/// en: 'Check updates'
	String get checkUpdates => 'Check updates';

	/// en: 'Checking…'
	String get checkingUpdates => 'Checking…';

	/// en: 'No matching plugins'
	String get discoveryEmpty => 'No matching plugins';

	/// en: 'Checking marketplaces for updates and syncing plugins in the background…'
	String get discoverySyncing => 'Checking marketplaces for updates and syncing plugins in the background…';

	/// en: 'All'
	String get filterAll => 'All';

	/// en: 'Installed'
	String get filterInstalled => 'Installed';

	/// en: 'All marketplaces'
	String get filterMarketplaceAll => 'All marketplaces';

	/// en: 'Not installed'
	String get filterUninstalled => 'Not installed';

	/// en: 'Browse marketplace'
	String get goDiscovery => 'Browse marketplace';

	/// en: 'Import from disk'
	String get importFromDisk => 'Import from disk';

	/// en: 'No unmanaged plugins found.'
	String get importNothing => 'No unmanaged plugins found.';

	/// en: 'Import unmanaged plugins'
	String get importTitle => 'Import unmanaged plugins';

	/// en: 'Install from ZIP'
	String get installFromZip => 'Install from ZIP';

	/// en: '{count: int} installed'
	String installedCount({required int count}) => '${count} installed';

	/// en: 'local'
	String get local => 'local';

	/// en: 'Add marketplace'
	String get marketplaceAdd => 'Add marketplace';

	/// en: 'Branch'
	String get marketplaceBranch => 'Branch';

	/// en: 'Display name'
	String get marketplaceDisplayName => 'Display name';

	/// en: 'Please enter a valid GitHub repository URL.'
	String get marketplaceInvalidUrl => 'Please enter a valid GitHub repository URL.';

	/// en: 'Remove marketplace'
	String get marketplaceRemove => 'Remove marketplace';

	/// en: 'Remove marketplace {url: String}? Installed plugins are kept.'
	String marketplaceRemoveConfirm({required String url}) => 'Remove marketplace ${url}? Installed plugins are kept.';

	/// en: 'GitHub repository URL'
	String get marketplaceUrl => 'GitHub repository URL';

	/// en: 'https://github.com/owner/marketplace'
	String get marketplaceUrlHint => 'https://github.com/owner/marketplace';

	/// en: 'No marketplaces configured'
	String get marketplacesEmpty => 'No marketplaces configured';

	/// en: 'Discovery'
	String get navDiscovery => 'Discovery';

	/// en: 'Installed'
	String get navInstalled => 'Installed';

	/// en: 'Marketplaces'
	String get navMarketplaces => 'Marketplaces';

	/// en: 'No plugins installed'
	String get noInstalled => 'No plugins installed';

	/// en: 'Add a marketplace and install plugins from the Discovery tab.'
	String get noInstalledHint => 'Add a marketplace and install plugins from the Discovery tab.';

	/// en: 'Search plugins'
	String get searchPlaceholder => 'Search plugins';

	/// en: 'Plugins'
	String get sidebarLabel => 'Plugins';

	/// en: 'Manage Claude Code-style plugin bundles'
	String get subtitle => 'Manage Claude Code-style plugin bundles';

	/// en: 'Plugins'
	String get title => 'Plugins';

	/// en: 'Uninstall {name: String}? This may affect {n: int} team(s).'
	String uninstallConfirm({required String name, required int n}) => 'Uninstall ${name}? This may affect ${n} team(s).';

	/// en: 'Affected teams:'
	String get uninstallImpactList => 'Affected teams:';

	/// en: 'Uninstalled {name: String}'
	String uninstallSuccess({required String name}) => 'Uninstalled ${name}';

	/// en: 'Update all ({count: int})'
	String updateAll({required int count}) => 'Update all (${count})';

	/// en: 'Update available'
	String get updateAvailable => 'Update available';
}

// Path: provider
class AppLocalizations$provider$en {
	AppLocalizations$provider$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Provider'
	String get provider => 'Provider';

	/// en: 'Authenticated'
	String get credentialsAuthenticated => 'Authenticated';

	/// en: 'Browser opened for authorization'
	String get credentialsBrowserOpened => 'Browser opened for authorization';

	/// en: 'Enter this one-time code in the browser (expires in 15 minutes)'
	String get credentialsDeviceCodeHint => 'Enter this one-time code in the browser (expires in 15 minutes)';

	/// en: 'Device code'
	String get credentialsDeviceCodeTitle => 'Device code';

	/// en: 'Credentials already exist. Sign out first or import again to replace.'
	String get credentialsFailureDestinationExists => 'Credentials already exist. Sign out first or import again to replace.';

	/// en: 'Credential format is invalid or incomplete'
	String get credentialsFailureInvalidCredential => 'Credential format is invalid or incomplete';

	/// en: 'Login failed (exit code {exitCode: int})'
	String credentialsFailureLoginFailed({required int exitCode}) => 'Login failed (exit code ${exitCode})';

	/// en: 'Could not run login command: {detail: String}'
	String credentialsFailureLoginProcessError({required String detail}) => 'Could not run login command: ${detail}';

	/// en: 'Choose a file or directory first'
	String get credentialsFailurePathRequired => 'Choose a file or directory first';

	/// en: 'No credential for "{providerId: String}" in {path: String}'
	String credentialsFailureProviderEntryMissing({required String providerId, required String path}) => 'No credential for "${providerId}" in ${path}';

	/// en: 'No credential for "{providerId: String}" in {path: String}. Available: {keys: String}'
	String credentialsFailureProviderEntryMissingWithKeys({required String providerId, required String path, required String keys}) => 'No credential for "${providerId}" in ${path}. Available: ${keys}';

	/// en: 'Provider not found'
	String get credentialsFailureProviderNotFound => 'Provider not found';

	/// en: 'Required file missing: {path: String}'
	String credentialsFailureRequiredFileMissing({required String path}) => 'Required file missing: ${path}';

	/// en: 'Could not sign out or remove credentials'
	String get credentialsFailureRevokeFailed => 'Could not sign out or remove credentials';

	/// en: 'Credential service is not available'
	String get credentialsFailureServiceUnavailable => 'Credential service is not available';

	/// en: 'Credential file not found: {path: String}'
	String credentialsFailureSourceMissing({required String path}) => 'Credential file not found: ${path}';

	/// en: 'Could not read credential file: {path: String}'
	String credentialsFailureSourceUnreadable({required String path}) => 'Could not read credential file: ${path}';

	/// en: 'Credentials updated but status could not be refreshed'
	String get credentialsFailureStatusRefreshFailed => 'Credentials updated but status could not be refreshed';

	/// en: 'This credential action is not supported'
	String get credentialsFailureUnsupported => 'This credential action is not supported';

	/// en: 'Credentials were saved but verification failed'
	String get credentialsFailureVerifyFailed => 'Credentials were saved but verification failed';

	/// en: 'Reopen browser'
	String get credentialsReopenBrowser => 'Reopen browser';

	/// en: 'Unauthenticated'
	String get credentialsUnauthenticated => 'Unauthenticated';

	/// en: '{type: String} provider · {count: int} models'
	String detailSubtitle({required String type, required int count}) => '${type} provider · ${count} models';

	/// en: 'Reasoning effort'
	String get effortLevel => 'Reasoning effort';

	/// en: 'Provider List'
	String get list => 'Provider List';

	/// en: '{count: int} models'
	String listModelCount({required int count}) => '${count} models';

	/// en: 'Use for background/fast tasks (Claude haiku tier)'
	String get modelBackgroundTier => 'Use for background/fast tasks (Claude haiku tier)';

	/// en: 'Provider name'
	String get name => 'Provider name';

	/// en: 'Provider type'
	String get type => 'Provider type';

	/// en: 'openai, claude, or custom'
	String get typeHint => 'openai, claude, or custom';
}

// Path: qoder
class AppLocalizations$qoder$en {
	AppLocalizations$qoder$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Context window (tokens)'
	String get contextWindow => 'Context window (tokens)';

	/// en: 'Leave empty to use the model default.'
	String get contextWindowHint => 'Leave empty to use the model default.';

	/// en: 'The Qoder action failed'
	String get credentialsActionFailed => 'The Qoder action failed';

	/// en: 'Cancel'
	String get credentialsCancel => 'Cancel';

	/// en: 'Done'
	String get credentialsDone => 'Done';

	/// en: 'Sign in'
	String get credentialsLogin => 'Sign in';

	/// en: 'Qoder CLI exited. Close this dialog and start the sign-in again.'
	String get credentialsLoginExited => 'Qoder CLI exited. Close this dialog and start the sign-in again.';

	/// en: 'Could not start the login terminal: {error: String}'
	String credentialsLoginFailed({required String error}) => 'Could not start the login terminal: ${error}';

	/// en: 'Complete the sign-in in the terminal below. The CLI opens a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.'
	String get credentialsLoginIntro => 'Complete the sign-in in the terminal below. The CLI opens a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.';

	/// en: 'Starting Qoder CLI…'
	String get credentialsLoginStarting => 'Starting Qoder CLI…';

	/// en: 'Sign in to Qoder'
	String get credentialsLoginTitle => 'Sign in to Qoder';

	/// en: 'Relaunch'
	String get credentialsRelaunch => 'Relaunch';

	/// en: 'Signed in'
	String get credentialsSignedIn => 'Signed in';
}

// Path: remote
class AppLocalizations$remote$en {
	AppLocalizations$remote$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// Landing readiness row label for a separate ACP adapter binary.
	///
	/// en: '{cli: String} ACP adapter'
	String cliMachineReadinessAdapterLabel({required String cli}) => '${cli} ACP adapter';

	/// en: '{cli: String}: {message: String}'
	String cliMachineReadinessFailed({required String cli, required String message}) => '${cli}: ${message}';

	/// en: 'Use Install for each missing CLI, or set a manual path in target settings.'
	String get cliMachineReadinessInstallHint => 'Use Install for each missing CLI, or set a manual path in target settings.';

	/// en: '{cli: String} not found — install or set a manual path'
	String cliMachineReadinessMissing({required String cli}) => '${cli} not found — install or set a manual path';

	/// en: 'Checking…'
	String get cliMachineReadinessProbing => 'Checking…';

	/// en: '{cli: String} ready at {path: String}'
	String cliMachineReadinessReady({required String cli, required String path}) => '${cli} ready at ${path}';

	/// en: 'Required CLIs on this machine'
	String get cliMachineReadinessTitle => 'Required CLIs on this machine';

	/// en: 'Manage the hosts saved on this device, connect, and switch your work home. Available even while offline.'
	String get connectionsSubtitle => 'Manage the hosts saved on this device, connect, and switch your work home. Available even while offline.';

	/// en: 'Remote connections'
	String get connectionsTitle => 'Remote connections';

	/// en: 'No subdirectories here'
	String get directoryBrowserEmpty => 'No subdirectories here';

	/// en: 'Couldn't open the remote directory. You can still type a path below.'
	String get directoryBrowserError => 'Couldn\'t open the remote directory. You can still type a path below.';

	/// en: 'Browse remote directory'
	String get directoryBrowserTitle => 'Browse remote directory';

	/// en: '~/work/workspace'
	String get directoryBrowserTypePathHint => '~/work/workspace';

	/// en: 'Or type a path'
	String get directoryBrowserTypePathLabel => 'Or type a path';

	/// en: 'Up one level'
	String get directoryBrowserUpOneLevel => 'Up one level';

	/// en: 'Use this directory'
	String get directoryBrowserUseThisDirectory => 'Use this directory';

	/// en: 'Use path'
	String get directoryBrowserUseTypedPath => 'Use path';
}

// Path: resource
class AppLocalizations$resource$en {
	AppLocalizations$resource$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'App'
	String get managerAppProcess => 'App';

	/// en: 'CPU'
	String get managerColumnCpu => 'CPU';

	/// en: 'Memory'
	String get managerColumnMemory => 'Memory';

	/// en: 'Name'
	String get managerColumnName => 'Name';

	/// en: 'Nothing running right now.'
	String get managerEmptyTree => 'Nothing running right now.';

	/// en: 'Kill'
	String get managerKill => 'Kill';

	/// en: 'Kill all'
	String get managerKillAll => 'Kill all';

	/// en: 'This disconnects every running session and shell in the list.'
	String get managerKillAllConfirmBody => 'This disconnects every running session and shell in the list.';

	/// en: 'Kill all running sessions?'
	String get managerKillAllConfirmTitle => 'Kill all running sessions?';

	/// en: 'Could not kill session.'
	String get managerKillFailed => 'Could not kill session.';

	/// en: 'Could not refresh process metrics.'
	String get managerMetricsError => 'Could not refresh process metrics.';

	/// en: 'Resource Manager - Sessions'
	String get managerPanelTitle => 'Resource Manager - Sessions';

	/// en: 'Refresh'
	String get managerRefresh => 'Refresh';

	/// en: 'Space'
	String get managerSpace => 'Space';

	/// en: 'Beta'
	String get managerSpaceBeta => 'Beta';

	/// en: 'Does not scan workspace disk usage.'
	String get managerSpaceNotScanned => 'Does not scan workspace disk usage.';

	/// en: '{percent: String}% system memory'
	String managerSystemMemoryPercent({required String percent}) => '${percent}% system memory';

	/// en: '{count: int} running sessions'
	String managerTerminalsCount({required int count}) => '${count} running sessions';

	/// en: 'Resource Manager'
	String get managerTitle => 'Resource Manager';

	/// en: 'Resource Manager - {count: int} running sessions'
	String managerTooltip({required int count}) => 'Resource Manager - ${count} running sessions';

	/// en: 'Running sessions across all workspaces.'
	String get managerTooltipHint => 'Running sessions across all workspaces.';
}

// Path: rtk
class AppLocalizations$rtk$en {
	AppLocalizations$rtk$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Only applies to Agent Bash tool calls. Built-in Read, Grep, and Glob are not rewritten.'
	String get bashOnlyHint => 'Only applies to Agent Bash tool calls. Built-in Read, Grep, and Glob are not rewritten.';

	/// en: 'Compress Agent Bash command output before it reaches the model (requires rtk and jq on PATH).'
	String get settingsDescription => 'Compress Agent Bash command output before it reaches the model (requires rtk and jq on PATH).';

	/// en: 'Enable RTK'
	String get settingsEnableTitle => 'Enable RTK';

	/// en: 'Install guide'
	String get settingsInstallLink => 'Install guide';

	/// en: 'Host status'
	String get settingsStatusTitle => 'Host status';

	/// en: 'RTK token savings'
	String get settingsTitle => 'RTK token savings';

	/// en: 'rtk {version: String} ready'
	String statusInstalled({required String version}) => 'rtk ${version} ready';

	/// en: 'rtk ready'
	String get statusInstalledGeneric => 'rtk ready';

	/// en: 'jq not found on PATH'
	String get statusJqMissing => 'jq not found on PATH';

	/// en: 'rtk not found on PATH'
	String get statusNotFound => 'rtk not found on PATH';

	/// en: 'rtk {version: String} is too old (need >= 0.23.0)'
	String statusVersionTooOld({required String version}) => 'rtk ${version} is too old (need >= 0.23.0)';
}

// Path: run
class AppLocalizations$run$en {
	AppLocalizations$run$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Add suggested configuration to launch.json'
	String get acceptRecommendation => 'Add suggested configuration to launch.json';

	/// en: 'Run'
	String get action => 'Run';

	/// en: 'Add configuration'
	String get addConfiguration => 'Add configuration';

	/// en: 'Restart the running session, or start a new instance?'
	String get alreadyRunningMessage => 'Restart the running session, or start a new instance?';

	/// en: 'Configuration already running'
	String get alreadyRunningTitle => 'Configuration already running';

	/// en: 'Apply'
	String get apply => 'Apply';

	/// en: 'Build'
	String get build => 'Build';

	/// en: 'Build is not available yet'
	String get buildUnavailable => 'Build is not available yet';

	/// en: 'Clear exited sessions'
	String get clearExited => 'Clear exited sessions';

	/// en: '{name: String} (compound)'
	String compoundConfiguration({required String name}) => '${name} (compound)';

	/// en: 'Name'
	String get configurationName => 'Name';

	/// en: 'Run configuration'
	String get configurationTooltip => 'Run configuration';

	/// en: 'Type'
	String get configurationType => 'Type';

	/// en: 'No launch configurations yet'
	String get configurationsEmpty => 'No launch configurations yet';

	/// en: 'Configure launch configurations'
	String get configureLaunchItems => 'Configure launch configurations';

	/// en: 'Debug'
	String get debug => 'Debug';

	/// en: 'Debug is not available yet'
	String get debugUnavailable => 'Debug is not available yet';

	/// en: 'Delete'
	String get deleteConfiguration => 'Delete';

	/// en: 'Delete configuration "{name: String}"?'
	String deleteConfigurationConfirm({required String name}) => 'Delete configuration "${name}"?';

	/// en: 'Discard'
	String get discard => 'Discard';

	/// en: 'You have unsaved changes to this configuration. Apply them, discard them, or cancel?'
	String get discardChangesMessage => 'You have unsaved changes to this configuration. Apply them, discard them, or cancel?';

	/// en: 'Discard changes?'
	String get discardChangesTitle => 'Discard changes?';

	/// en: 'Edit configuration'
	String get editConfigurations => 'Edit configuration';

	/// en: 'Select configuration'
	String get editorSelectConfiguration => 'Select configuration';

	/// en: 'Run a configuration to see output here'
	String get emptyOutputHint => 'Run a configuration to see output here';

	/// en: 'No configuration selected'
	String get errorNoConfiguration => 'No configuration selected';

	/// en: 'No workspace folder'
	String get errorNoFolder => 'No workspace folder';

	/// en: 'SSH profile not found for this run target'
	String get errorSshProfileMissing => 'SSH profile not found for this run target';

	/// en: 'SSH process execution is not configured'
	String get errorSshSpawnerMissing => 'SSH process execution is not configured';

	/// en: 'Script file'
	String get executeScriptFile => 'Script file';

	/// en: 'Script text'
	String get executeScriptText => 'Script text';

	/// en: 'Activate tool window'
	String get fieldActivateToolWindow => 'Activate tool window';

	/// en: 'Allow multiple instances'
	String get fieldAllowMultipleInstances => 'Allow multiple instances';

	/// en: 'Arguments'
	String get fieldArgs => 'Arguments';

	/// en: 'Command'
	String get fieldCommand => 'Command';

	/// en: 'Working directory'
	String get fieldCwd => 'Working directory';

	/// en: 'Environment variables'
	String get fieldEnv => 'Environment variables';

	/// en: 'Execute'
	String get fieldExecute => 'Execute';

	/// en: 'Execute in the terminal'
	String get fieldExecuteInTerminal => 'Execute in the terminal';

	/// en: 'Focus tool window'
	String get fieldFocusToolWindow => 'Focus tool window';

	/// en: 'Interpreter options'
	String get fieldInterpreterOptions => 'Interpreter options';

	/// en: 'Interpreter path'
	String get fieldInterpreterPath => 'Interpreter path';

	/// en: 'Edit interpreter path'
	String get fieldInterpreterPathEditTooltip => 'Edit interpreter path';

	/// en: 'Script options'
	String get fieldScriptOptions => 'Script options';

	/// en: 'Script path'
	String get fieldScriptPath => 'Script path';

	/// en: 'Script text'
	String get fieldScriptText => 'Script text';

	/// en: 'Run in shell'
	String get fieldShell => 'Run in shell';

	/// en: 'Loading run output…'
	String get loadingOutput => 'Loading run output…';

	/// en: 'More run actions'
	String get moreActions => 'More run actions';

	/// en: 'New instance'
	String get newInstance => 'New instance';

	/// en: 'No run sessions'
	String get noSessions => 'No run sessions';

	/// en: 'Open launch.json'
	String get openLaunchJson => 'Open launch.json';

	/// en: 'Select launch type'
	String get pickLaunchType => 'Select launch type';

	/// en: 'Refresh discover recommendations'
	String get refreshDiscover => 'Refresh discover recommendations';

	/// en: 'Restart'
	String get restart => 'Restart';

	/// en: 'Launch'
	String get selectConfiguration => 'Launch';

	/// en: 'Select folder'
	String get selectFolder => 'Select folder';

	/// en: 'Stop'
	String get stop => 'Stop';

	/// en: 'Stop and close'
	String get stopAndClose => 'Stop and close';

	/// en: 'Stop and delete'
	String get stopAndDelete => 'Stop and delete';

	/// en: '"{name: String}" is still running. Stop it and close this tab?'
	String stopSessionMessage({required String name}) => '"${name}" is still running. Stop it and close this tab?';

	/// en: 'Stop running session?'
	String get stopSessionTitle => 'Stop running session?';

	/// en: '{name: String} (Suggested)'
	String suggestedConfiguration({required String name}) => '${name} (Suggested)';

	/// en: 'Shell Script'
	String get typeShellScript => 'Shell Script';

	/// en: 'Launch type "{type: String}" is not available on this target'
	String typeUnavailable({required String type}) => 'Launch type "${type}" is not available on this target';

	/// en: 'Launch type "{type: String}" is not available on remote targets'
	String typeUnavailableRemote({required String type}) => 'Launch type "${type}" is not available on remote targets';

	/// en: 'Unknown launch type: {type: String}'
	String typeUnknown({required String type}) => 'Unknown launch type: ${type}';

	/// en: 'Activate tool window must be a boolean'
	String get validationActivateToolWindowMustBeBoolean => 'Activate tool window must be a boolean';

	/// en: 'Allow multiple instances must be a boolean'
	String get validationAllowMultipleInstancesMustBeBoolean => 'Allow multiple instances must be a boolean';

	/// en: 'Arguments must be a list of strings'
	String get validationArgsMustBeStringList => 'Arguments must be a list of strings';

	/// en: 'Command is required'
	String get validationCommandRequired => 'Command is required';

	/// en: 'Configuration must be a map'
	String get validationConfigurationMustBeMap => 'Configuration must be a map';

	/// en: 'Working directory must be a string'
	String get validationCwdMustBeString => 'Working directory must be a string';

	/// en: 'Environment must be a map of strings'
	String get validationEnvMustBeStringMap => 'Environment must be a map of strings';

	/// en: 'Execute in the terminal must be a boolean'
	String get validationExecuteInTerminalMustBeBoolean => 'Execute in the terminal must be a boolean';

	/// en: 'Execute must be Script file or Script text'
	String get validationExecuteInvalid => 'Execute must be Script file or Script text';

	/// en: 'Execute mode is required'
	String get validationExecuteRequired => 'Execute mode is required';

	/// en: 'Focus tool window must be a boolean'
	String get validationFocusToolWindowMustBeBoolean => 'Focus tool window must be a boolean';

	/// en: 'Interpreter path must be a string'
	String get validationInterpreterPathMustBeString => 'Interpreter path must be a string';

	/// en: 'Script path is required'
	String get validationScriptPathRequired => 'Script path is required';

	/// en: 'Script text is required'
	String get validationScriptTextRequired => 'Script text is required';

	/// en: 'Shell must be a boolean'
	String get validationShellMustBeBoolean => 'Shell must be a boolean';
}

// Path: session
class AppLocalizations$session$en {
	AppLocalizations$session$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Session'
	String get session => 'Session';

	/// en: 'No archived conversations'
	String get archiveEmpty => 'No archived conversations';

	/// en: 'Archived conversations'
	String get archiveEntryTooltip => 'Archived conversations';

	/// en: 'Archive'
	String get archiveTitle => 'Archive';

	/// en: 'Failed to duplicate conversation'
	String get duplicateFailed => 'Failed to duplicate conversation';

	/// en: 'Conversation duplicated'
	String get duplicated => 'Conversation duplicated';

	/// en: 'Couldn't start session'
	String get failedTitle => 'Couldn\'t start session';

	/// en: 'Add a follow-up'
	String get followUpAddPlaceholder => 'Add a follow-up';

	/// en: 'Delete'
	String get followUpDelete => 'Delete';

	/// en: 'Edit'
	String get followUpEdit => 'Edit';

	/// en: 'Move up'
	String get followUpMoveUp => 'Move up';

	/// en: '{count: int} Queued'
	String followUpQueued({required int count}) => '${count} Queued';

	/// en: 'Resume'
	String get followUpResume => 'Resume';

	/// en: 'Failed to fork conversation'
	String get forkFailed => 'Failed to fork conversation';

	/// en: 'Add conversations'
	String get groupAddSessionsTitle => 'Add conversations';

	/// en: 'Add conversations'
	String get groupAddSessionsTooltip => 'Add conversations';

	/// en: 'New Group'
	String get groupCreateTitle => 'New Group';

	/// en: 'New group'
	String get groupCreateTooltip => 'New group';

	/// en: 'No conversations'
	String get groupEmpty => 'No conversations';

	/// en: 'Remove group'
	String get groupMenuRemove => 'Remove group';

	/// en: 'Group name'
	String get groupNameLabel => 'Group name';

	/// en: 'Rename Group'
	String get groupRenameTitle => 'Rename Group';

	/// en: 'Background work running…'
	String get historyBackgroundRunning => 'Background work running…';

	/// en: 'Continue this conversation… @ reference files, / invoke skills'
	String get historyComposeHint => 'Continue this conversation… @ reference files, / invoke skills';

	/// en: 'Stop generating'
	String get historyComposeStop => 'Stop generating';

	/// en: 'Couldn't save continue settings.'
	String get historyContinueSaveFailed => 'Couldn\'t save continue settings.';

	/// en: 'No prior messages for this member yet.'
	String get historyEmpty => 'No prior messages for this member yet.';

	/// en: 'Couldn't load conversation history.'
	String get historyError => 'Couldn\'t load conversation history.';

	/// en: 'Scroll up for earlier messages'
	String get historyLoadOlderHint => 'Scroll up for earlier messages';

	/// en: 'Loading conversation history…'
	String get historyLoading => 'Loading conversation history…';

	/// en: '{count: int} Queued'
	String historyMailboxQueued({required int count}) => '${count} Queued';

	/// en: 'Dismiss'
	String get historyMailboxQueuedDismiss => 'Dismiss';

	/// en: 'Refreshing conversation…'
	String get historyRefreshing => 'Refreshing conversation…';

	/// en: 'Retry'
	String get historyRetry => 'Retry';

	/// en: 'Assistant'
	String get historyRoleAssistant => 'Assistant';

	/// en: 'System'
	String get historyRoleSystem => 'System';

	/// en: 'You'
	String get historyRoleUser => 'You';

	/// en: 'Running…'
	String get historyRunning => 'Running…';

	/// en: 'Couldn't refresh conversation history.'
	String get historySoftReloadError => 'Couldn\'t refresh conversation history.';

	/// en: 'Starting…'
	String get historyStarting => 'Starting…';

	/// en: 'Tool'
	String get historyToolTurn => 'Tool';

	/// en: 'Ready for your next message'
	String get idleNotificationSubtitle => 'Ready for your next message';

	/// en: 'Agent ready'
	String get idleNotificationTitle => 'Agent ready';

	/// en: 'Hide details'
	String get launchErrorHideDetails => 'Hide details';

	/// en: 'View details'
	String get launchErrorReviewDetails => 'View details';

	/// en: 'Team member is not available. Select a team and try again.'
	String get launchMissingTeamMember => 'Team member is not available. Select a team and try again.';

	/// en: 'Workspace not found for this session.'
	String get launchMissingWorkspace => 'Workspace not found for this session.';

	/// en: 'Open to the Side'
	String get openToSide => 'Open to the Side';

	/// en: 'Configure shell session launch, terminal behavior, and storage backend.'
	String get pageSubtitle => 'Configure shell session launch, terminal behavior, and storage backend.';

	/// en: 'Describe what you want in everyday language — no terminal commands needed.'
	String get readyHint => 'Describe what you want in everyday language — no terminal commands needed.';

	/// en: 'Start a conversation with {memberName: String} in this workspace.'
	String readySubtitle({required String memberName}) => 'Start a conversation with ${memberName} in this workspace.';

	/// en: 'Start a conversation in this workspace.'
	String get readySubtitleGeneric => 'Start a conversation in this workspace.';

	/// en: 'Ready to chat'
	String get readyTitle => 'Ready to chat';

	/// en: 'Remote setup failed'
	String get remoteProvisionFailed => 'Remote setup failed';

	/// en: 'Preparing remote environment…'
	String get remoteProvisionPreparing => 'Preparing remote environment…';

	/// en: 'Preparing remote environment ({host: String})'
	String remoteProvisionPreparingOnHost({required String host}) => 'Preparing remote environment (${host})';

	/// en: 'Preparing {member: String} on {host: String}'
	String remoteProvisionTitle({required String member, required String host}) => 'Preparing ${member} on ${host}';

	/// en: 'Try again'
	String get retryButton => 'Try again';

	/// en: 'Date created'
	String get sortCreatedDesc => 'Date created';

	/// en: 'Manual order'
	String get sortManual => 'Manual order';

	/// en: 'Recently updated'
	String get sortRecentlyUpdated => 'Recently updated';

	/// en: 'Sort conversations'
	String get sortTooltip => 'Sort conversations';

	/// en: 'Start conversation'
	String get startButton => 'Start conversation';

	/// en: 'Starting session…'
	String get starting => 'Starting session…';

	/// en: 'Session tab bar'
	String get tabBarTitle => 'Session tab bar';

	/// en: 'Show the tab strip above the workbench center column.'
	String get tabBarVisibilityHint => 'Show the tab strip above the workbench center column.';

	/// en: '(copy)'
	String get titleCopySuffix => '(copy)';

	/// en: 'Chat'
	String get workbenchViewChat => 'Chat';

	/// en: 'Terminal'
	String get workbenchViewTerminal => 'Terminal';
}

// Path: sessionUsage
class AppLocalizations$sessionUsage$en {
	AppLocalizations$sessionUsage$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'All accounts'
	String get accountAll => 'All accounts';

	/// en: 'Auto-scan session logs'
	String get autoScan => 'Auto-scan session logs';

	/// en: 'Scans when this page opens, then every {minutes: int} minutes in the background.'
	String autoScanHint({required int minutes}) => 'Scans when this page opens, then every ${minutes} minutes in the background.';

	/// en: 'Hit {percent: String}'
	String cacheHit({required String percent}) => 'Hit ${percent}';

	/// en: 'Cache read'
	String get cacheRead => 'Cache read';

	/// en: 'Cache read share {percent: String}'
	String cacheReadShare({required String percent}) => 'Cache read share ${percent}';

	/// en: 'Cache'
	String get cacheShort => 'Cache';

	/// en: 'Write {tokens: String}'
	String cacheWrite({required String tokens}) => 'Write ${tokens}';

	/// en: 'Cancel'
	String get cancelSync => 'Cancel';

	/// en: 'Cancel usage sync'
	String get cancelSyncTooltip => 'Cancel usage sync';

	/// en: 'Cancelling…'
	String get cancelling => 'Cancelling…';

	/// en: '{tokens: String} / day'
	String chartAverage({required String tokens}) => '${tokens} / day';

	/// en: 'Stacked by CLI'
	String get chartSubtitle => 'Stacked by CLI';

	/// en: 'Last 7 days'
	String get chartTitle => 'Last 7 days';

	/// en: '{tokens: String} total'
	String chartTotal({required String tokens}) => '${tokens} total';

	/// en: 'All'
	String get cliAll => 'All';

	/// en: 'CLI distribution'
	String get cliBreakdown => 'CLI distribution';

	/// en: 'Reset to default'
	String get columnReset => 'Reset to default';

	/// en: 'Columns'
	String get columnSettings => 'Columns';

	/// en: 'Cost'
	String get cost => 'Cost';

	/// en: 'Partial: {count: int} events unpriced'
	String costPartial({required int count}) => 'Partial: ${count} events unpriced';

	/// en: '{priced: int} priced · {unpriced: int} unpriced'
	String costPricedUnpriced({required int priced, required int unpriced}) => '${priced} priced · ${unpriced} unpriced';

	/// en: 'Cost'
	String get costShort => 'Cost';

	/// en: 'Unpriced'
	String get costUnpriced => 'Unpriced';

	/// en: 'Data source'
	String get dataSource => 'Data source';

	/// en: 'Dismiss'
	String get dismiss => 'Dismiss';

	/// en: 'Run a Claude, Codex, or OpenCode session, then sync. You can also reset filters.'
	String get emptyBody => 'Run a Claude, Codex, or OpenCode session, then sync. You can also reset filters.';

	/// en: 'No token usage yet'
	String get emptyTitle => 'No token usage yet';

	/// en: 'End time'
	String get endTime => 'End time';

	/// en: 'Group by'
	String get groupBy => 'Group by';

	/// en: 'CLI'
	String get groupCli => 'CLI';

	/// en: '{count: int} groups'
	String groupCount({required int count}) => '${count} groups';

	/// en: 'Member'
	String get groupMember => 'Member';

	/// en: 'Model'
	String get groupModel => 'Model';

	/// en: 'Name'
	String get groupName => 'Name';

	/// en: 'Session'
	String get groupSession => 'Session';

	/// en: 'Less'
	String get heatmapLess => 'Less';

	/// en: 'Hit rate'
	String get heatmapMetricHitRate => 'Hit rate';

	/// en: 'Tokens'
	String get heatmapMetricTokens => 'Tokens';

	/// en: 'More'
	String get heatmapMore => 'More';

	/// en: 'Show earlier'
	String get heatmapShowEarlier => 'Show earlier';

	/// en: 'Show less'
	String get heatmapShowLess => 'Show less';

	/// en: '{tokens: String} tokens · {requests: String} requests · {cost: String}'
	String heatmapSpanSummary({required String tokens, required String requests, required String cost}) => '${tokens} tokens · ${requests} requests · ${cost}';

	/// en: 'Last 53 weeks · hover or long-press a day'
	String get heatmapSubtitle => 'Last 53 weeks · hover or long-press a day';

	/// en: 'Usage heatmap'
	String get heatmapTitle => 'Usage heatmap';

	/// en: 'Input'
	String get inputShort => 'Input';

	/// en: 'Input'
	String get inputTokens => 'Input';

	/// en: 'Every {minutes: int} min'
	String intervalMinutes({required int minutes}) => 'Every ${minutes} min';

	/// en: 'Last sync {time: String}'
	String lastSync({required String time}) => 'Last sync ${time}';

	/// en: 'End time follows now'
	String get liveEnd => 'End time follows now';

	/// en: 'Could not load usage data.'
	String get loadFailed => 'Could not load usage data.';

	/// en: 'Loading usage…'
	String get loading => 'Loading usage…';

	/// en: 'Compact events'
	String get maintenanceCompact => 'Compact events';

	/// en: 'Merge superseded revisions. Current events are kept.'
	String get maintenanceCompactHint => 'Merge superseded revisions. Current events are kept.';

	/// en: 'Usage storage compacted.'
	String get maintenanceCompacted => 'Usage storage compacted.';

	/// en: 'Storage and Cursor maintenance'
	String get maintenanceEntry => 'Storage and Cursor maintenance';

	/// en: 'Couldn't compact usage storage.'
	String get maintenanceFailed => 'Couldn\'t compact usage storage.';

	/// en: 'Full rescan'
	String get maintenanceFull => 'Full rescan';

	/// en: 'Full usage rescan complete.'
	String get maintenanceFullDone => 'Full usage rescan complete.';

	/// en: 'Rebuild all sources and scan every session. Use this if history is missing.'
	String get maintenanceFullHint => 'Rebuild all sources and scan every session. Use this if history is missing.';

	/// en: '{lines: int} lines · {events: int} events'
	String maintenanceLines({required int lines, required int events}) => '${lines} lines · ${events} events';

	/// en: '{size: String} KB'
	String maintenanceSize({required String size}) => '${size} KB';

	/// en: 'Usage storage'
	String get maintenanceTitle => 'Usage storage';

	/// en: 'Manage pricing'
	String get managePricing => 'Manage pricing';

	/// en: 'Mixed'
	String get mixedCli => 'Mixed';

	/// en: 'Token usage'
	String get nav => 'Token usage';

	/// en: 'Not synced yet'
	String get neverSynced => 'Not synced yet';

	/// en: 'Next page'
	String get nextPage => 'Next page';

	/// en: 'No data'
	String get noData => 'No data';

	/// en: 'Output'
	String get outputShort => 'Output';

	/// en: 'Output'
	String get outputTokens => 'Output';

	/// en: 'Page {page: int} / {pages: int}'
	String pageOf({required int page, required int pages}) => 'Page ${page} / ${pages}';

	/// en: '{start: int}–{end: int} of {total: int} groups'
	String pageRange({required int start, required int end, required int total}) => '${start}–${end} of ${total} groups';

	/// en: 'Previous page'
	String get prevPage => 'Previous page';

	/// en: 'Add rule'
	String get pricingAdd => 'Add rule';

	/// en: 'Cache read'
	String get pricingCacheRead => 'Cache read';

	/// en: 'Cache write'
	String get pricingCacheWrite => 'Cache write';

	/// en: '1h cache write'
	String get pricingCacheWrite1h => '1h cache write';

	/// en: 'Pricing file was unreadable. Using built-in prices.'
	String get pricingCorrupt => 'Pricing file was unreadable. Using built-in prices.';

	/// en: 'Delete'
	String get pricingDelete => 'Delete';

	/// en: 'Effective date'
	String get pricingEffectiveDate => 'Effective date';

	/// en: 'YYYY-MM-DD'
	String get pricingEffectiveHint => 'YYYY-MM-DD';

	/// en: 'No custom rules. Built-in prices are active.'
	String get pricingEmpty => 'No custom rules. Built-in prices are active.';

	/// en: 'Couldn't save pricing.'
	String get pricingFailed => 'Couldn\'t save pricing.';

	/// en: 'USD per 1M tokens. User rules override built-in reference prices.'
	String get pricingHint => 'USD per 1M tokens. User rules override built-in reference prices.';

	/// en: 'Input'
	String get pricingInput => 'Input';

	/// en: 'Check model and price values.'
	String get pricingInvalid => 'Check model and price values.';

	/// en: 'Model'
	String get pricingModel => 'Model';

	/// en: 'Output'
	String get pricingOutput => 'Output';

	/// en: 'Reset defaults'
	String get pricingReset => 'Reset defaults';

	/// en: 'Remove all custom pricing rules?'
	String get pricingResetConfirm => 'Remove all custom pricing rules?';

	/// en: 'Save'
	String get pricingSave => 'Save';

	/// en: 'Pricing saved'
	String get pricingSaved => 'Pricing saved';

	/// en: 'Model pricing'
	String get pricingTitle => 'Model pricing';

	/// en: 'Usage sync'
	String get progressTitle => 'Usage sync';

	/// en: 'All time'
	String get rangeAll => 'All time';

	/// en: 'Last 14 days'
	String get rangeFourteenDays => 'Last 14 days';

	/// en: 'Date and time, up to 30 days'
	String get rangeHint => 'Date and time, up to 30 days';

	/// en: 'Start time cannot be later than end time'
	String get rangeInvalidOrder => 'Start time cannot be later than end time';

	/// en: 'Last 24 hours'
	String get rangeLast24Hours => 'Last 24 hours';

	/// en: 'Last 7 days'
	String get rangeSevenDays => 'Last 7 days';

	/// en: 'Last 30 days'
	String get rangeThirtyDays => 'Last 30 days';

	/// en: 'Today'
	String get rangeToday => 'Today';

	/// en: 'Range cannot exceed 30 days'
	String get rangeTooLong => 'Range cannot exceed 30 days';

	/// en: 'Requests'
	String get requests => 'Requests';

	/// en: '{requests: int} requests · {sessions: int} sessions'
	String requestsSessions({required int requests, required int sessions}) => '${requests} requests · ${sessions} sessions';

	/// en: 'Req.'
	String get requestsShort => 'Req.';

	/// en: 'Reset filters'
	String get resetFilters => 'Reset filters';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Rows per page'
	String get rowsPerPage => 'Rows per page';

	/// en: 'Scan interval'
	String get scanInterval => 'Scan interval';

	/// en: 'Local + SSH · attributed by TeamPilot session'
	String get scopeHint => 'Local + SSH · attributed by TeamPilot session';

	/// en: 'Search sessions, members, models'
	String get searchHint => 'Search sessions, members, models';

	/// en: 'Sessions'
	String get sessions => 'Sessions';

	/// en: 'Sess.'
	String get sessionsShort => 'Sess.';

	/// en: 'Usage settings'
	String get settings => 'Usage settings';

	/// en: '{percent: String} of total'
	String share({required String percent}) => '${percent} of total';

	/// en: 'Share'
	String get shareShort => 'Share';

	/// en: 'Showing {shown: int} / {total: int} rows'
	String showing({required int shown, required int total}) => 'Showing ${shown} / ${total} rows';

	/// en: 'Simple session'
	String get simpleSeat => 'Simple session';

	/// en: 'Sort ascending'
	String get sortAscending => 'Sort ascending';

	/// en: 'Sort descending'
	String get sortDescending => 'Sort descending';

	/// en: 'Start time'
	String get startTime => 'Start time';

	/// en: 'Storage'
	String get storage => 'Storage';

	/// en: 'Sync'
	String get sync => 'Sync';

	/// en: 'Usage sync cancelled.'
	String get syncCancelled => 'Usage sync cancelled.';

	/// en: 'Sync failed. Showing cached data.'
	String get syncFatal => 'Sync failed. Showing cached data.';

	/// en: 'Full sync'
	String get syncFull => 'Full sync';

	/// en: 'Rescan every transcript from scratch'
	String get syncFullHint => 'Rescan every transcript from scratch';

	/// en: 'Incremental sync'
	String get syncIncremental => 'Incremental sync';

	/// en: 'Scan only files changed since the last sync'
	String get syncIncrementalHint => 'Scan only files changed since the last sync';

	/// en: 'Sync now'
	String get syncNow => 'Sync now';

	/// en: '{count: int} sources failed to sync. Showing cached data.'
	String syncPartial({required int count}) => '${count} sources failed to sync. Showing cached data.';

	/// en: 'Preparing scan…'
	String get syncPreparing => 'Preparing scan…';

	/// en: 'Scanning {done: int}/{total: int} sessions · {inserted: int} new events'
	String syncProgress({required int done, required int total, required int inserted}) => 'Scanning ${done}/${total} sessions · ${inserted} new events';

	/// en: 'Scan CLI transcripts for new usage'
	String get syncTooltip => 'Scan CLI transcripts for new usage';

	/// en: 'Synced just now'
	String get syncedJustNow => 'Synced just now';

	/// en: 'Usage synced'
	String get syncedToast => 'Usage synced';

	/// en: 'Syncing'
	String get syncing => 'Syncing';

	/// en: 'No matching rows'
	String get tableEmpty => 'No matching rows';

	/// en: 'Try a different search or reset the filters.'
	String get tableEmptyHint => 'Try a different search or reset the filters.';

	/// en: 'Token usage'
	String get title => 'Token usage';

	/// en: 'Today'
	String get today => 'Today';

	/// en: 'Total'
	String get totalShort => 'Total';

	/// en: 'Total tokens'
	String get totalTokens => 'Total tokens';

	/// en: 'Unknown model'
	String get unknownModel => 'Unknown model';

	/// en: 'Unknown session'
	String get unknownSession => 'Unknown session';

	/// en: 'Unassigned team'
	String get unknownTeam => 'Unassigned team';
}

// Path: shortcuts
class AppLocalizations$shortcuts$en {
	AppLocalizations$shortcuts$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Compose'
	String get categoryCompose => 'Compose';

	/// en: 'General'
	String get categoryMeta => 'General';

	/// en: 'Navigation'
	String get categoryNavigation => 'Navigation';

	/// en: 'Run'
	String get categoryRun => 'Run';

	/// en: 'Tabs'
	String get categoryTabs => 'Tabs';

	/// en: 'View'
	String get categoryView => 'View';

	/// en: 'Zoom'
	String get categoryZoom => 'Zoom';

	/// en: 'Change…'
	String get changeAction => 'Change…';

	/// en: 'View Cheatsheet'
	String get cheatsheetButton => 'View Cheatsheet';

	/// en: 'No shortcuts match your search.'
	String get cheatsheetEmpty => 'No shortcuts match your search.';

	/// en: 'Keyboard Shortcuts'
	String get cheatsheetTitle => 'Keyboard Shortcuts';

	/// en: 'Insert Newline'
	String get composeNewline => 'Insert Newline';

	/// en: 'Send Message'
	String get composeSubmit => 'Send Message';

	/// en: 'Conflicts with another shortcut'
	String get conflictBadgeTooltip => 'Conflicts with another shortcut';

	/// en: 'Already used by "{title: String}".'
	String conflictMessage({required String title}) => 'Already used by "${title}".';

	/// en: 'Export…'
	String get export => 'Export…';

	/// en: 'Couldn't export shortcuts.'
	String get exportFailed => 'Couldn\'t export shortcuts.';

	/// en: 'Shortcuts exported.'
	String get exportSuccess => 'Shortcuts exported.';

	/// en: 'Maximize Floating Workspace'
	String get floatingMaximize => 'Maximize Floating Workspace';

	/// en: 'Minimize Floating Workspace'
	String get floatingMinimize => 'Minimize Floating Workspace';

	/// en: 'New Floating Terminal'
	String get floatingNewTerminal => 'New Floating Terminal';

	/// en: 'Open File in Floating Workspace'
	String get floatingOpenFile => 'Open File in Floating Workspace';

	/// en: 'Toggle Floating Workspace'
	String get floatingToggle => 'Toggle Floating Workspace';

	/// en: 'Import…'
	String get import => 'Import…';

	/// en: 'The imported shortcuts conflict with {count: int} existing binding(s). Replace them?'
	String importConflictMessage({required int count}) => 'The imported shortcuts conflict with ${count} existing binding(s). Replace them?';

	/// en: 'Replace Conflicting Shortcuts?'
	String get importConflictTitle => 'Replace Conflicting Shortcuts?';

	/// en: 'That file isn't a valid shortcuts export.'
	String get importInvalidFile => 'That file isn\'t a valid shortcuts export.';

	/// en: 'Shortcuts imported.'
	String get importSuccess => 'Shortcuts imported.';

	/// en: 'Not set'
	String get notSet => 'Not set';

	/// en: 'View and customize keyboard shortcuts for navigation, tabs, zoom, and compose.'
	String get pageSubtitle => 'View and customize keyboard shortcuts for navigation, tabs, zoom, and compose.';

	/// en: 'Press a key combination to bind it. Press Escape to cancel, Backspace to unbind.'
	String get pressShortcutHint => 'Press a key combination to bind it. Press Escape to cancel, Backspace to unbind.';

	/// en: 'Press a Shortcut'
	String get pressShortcutTitle => 'Press a Shortcut';

	/// en: 'That key can't be bound.'
	String get pressShortcutUnsupportedKey => 'That key can\'t be bound.';

	/// en: 'Replace'
	String get replaceAction => 'Replace';

	/// en: 'Reset to Default'
	String get resetAction => 'Reset to Default';

	/// en: 'Reset All'
	String get resetAll => 'Reset All';

	/// en: 'This restores every keyboard shortcut to its default binding.'
	String get resetAllConfirmMessage => 'This restores every keyboard shortcut to its default binding.';

	/// en: 'Reset All Shortcuts?'
	String get resetAllConfirmTitle => 'Reset All Shortcuts?';

	/// en: 'Restart Run'
	String get runRestart => 'Restart Run';

	/// en: 'Run Selected Configuration'
	String get runSelected => 'Run Selected Configuration';

	/// en: 'Stop Run'
	String get runStop => 'Stop Run';

	/// en: 'Search shortcuts'
	String get searchHint => 'Search shortcuts';

	/// en: 'Close Session Tab'
	String get sessionCloseTab => 'Close Session Tab';

	/// en: 'New Conversation'
	String get sessionNewChat => 'New Conversation';

	/// en: 'New Session Tab'
	String get sessionNewTab => 'New Session Tab';

	/// en: 'Keyboard Shortcuts'
	String get settingsTitle => 'Keyboard Shortcuts';

	/// en: 'Show Keyboard Shortcuts'
	String get showCheatsheet => 'Show Keyboard Shortcuts';

	/// en: 'Go to Tab {n: int}'
	String stripFocusTab({required int n}) => 'Go to Tab ${n}';

	/// en: 'Next Tab'
	String get stripNextTab => 'Next Tab';

	/// en: 'Previous Tab'
	String get stripPrevTab => 'Previous Tab';

	/// en: 'Toggle Terminal Panel'
	String get togglePanel => 'Toggle Terminal Panel';

	/// en: 'Toggle Secondary Sidebar'
	String get toggleSecondarySidebar => 'Toggle Secondary Sidebar';

	/// en: 'Toggle Sidebar'
	String get toggleSidebar => 'Toggle Sidebar';

	/// en: 'Unbind'
	String get unbindAction => 'Unbind';

	/// en: 'Focus Next Editor Group'
	String get workbenchFocusNextGroup => 'Focus Next Editor Group';

	/// en: 'Move Tab to Next Editor Group'
	String get workbenchMoveTabToNextGroup => 'Move Tab to Next Editor Group';

	/// en: 'Split Editor Down'
	String get workbenchSplitDown => 'Split Editor Down';

	/// en: 'Reset Editor Layout'
	String get workbenchSplitReset => 'Reset Editor Layout';

	/// en: 'Split Editor Right'
	String get workbenchSplitRight => 'Split Editor Right';

	/// en: 'Close Workspace Tab'
	String get workspaceCloseTab => 'Close Workspace Tab';

	/// en: 'Find in Files'
	String get workspaceContentSearch => 'Find in Files';

	/// en: 'Go to Workspace {n: int}'
	String workspaceFocusTab({required int n}) => 'Go to Workspace ${n}';

	/// en: 'Next Workspace Tab'
	String get workspaceNextTab => 'Next Workspace Tab';

	/// en: 'Previous Workspace Tab'
	String get workspacePrevTab => 'Previous Workspace Tab';

	/// en: 'Reopen Closed Workspace Tab'
	String get workspaceReopenClosed => 'Reopen Closed Workspace Tab';

	/// en: 'Search Workspace (double-tap Shift)'
	String get workspaceSearch => 'Search Workspace (double-tap Shift)';

	/// en: 'Zoom In'
	String get zoomIn => 'Zoom In';

	/// en: 'Zoom Out'
	String get zoomOut => 'Zoom Out';

	/// en: 'Reset Zoom'
	String get zoomReset => 'Reset Zoom';
}

// Path: skills
class AppLocalizations$skills$en {
	AppLocalizations$skills$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Details'
	String get cardDetails => 'Details';

	/// en: 'Install'
	String get cardInstall => 'Install';

	/// en: 'Installed'
	String get cardInstalled => 'Installed';

	/// en: '{count: int} stars'
	String cardStars({required int count}) => '${count} stars';

	/// en: 'Uninstall'
	String get cardUninstall => 'Uninstall';

	/// en: 'Update'
	String get cardUpdate => 'Update';

	/// en: 'Updated {date: String}'
	String cardUpdatedAt({required String date}) => 'Updated ${date}';

	/// en: 'View'
	String get cardView => 'View';

	/// en: 'Installs'
	String get catalogAdoption => 'Installs';

	/// en: 'None'
	String get catalogCardNoDescription => 'None';

	/// en: 'Check updates'
	String get checkUpdates => 'Check updates';

	/// en: 'Checking…'
	String get checkingUpdates => 'Checking…';

	/// en: 'No SKILL.md found for this skill.'
	String get detailMissing => 'No SKILL.md found for this skill.';

	/// en: 'Could not read SKILL.md.'
	String get detailReadError => 'Could not read SKILL.md.';

	/// en: 'No skills discovered'
	String get discoveryEmpty => 'No skills discovered';

	/// en: 'Add a repo or try skills.sh to find skills.'
	String get discoveryEmptyHint => 'Add a repo or try skills.sh to find skills.';

	/// en: 'Discovery failed'
	String get discoveryErrorTitle => 'Discovery failed';

	/// en: 'Checking repos for updates and syncing skills in the background…'
	String get discoverySyncing => 'Checking repos for updates and syncing skills in the background…';

	/// en: 'Enabled'
	String get enabled => 'Enabled';

	/// en: 'All'
	String get filterAll => 'All';

	/// en: 'All'
	String get filterAnyCategory => 'All';

	/// en: 'Any'
	String get filterAnyLanguage => 'Any';

	/// en: 'All'
	String get filterAnyOccupation => 'All';

	/// en: 'Category'
	String get filterCategory => 'Category';

	/// en: 'Installed'
	String get filterInstalled => 'Installed';

	/// en: 'Language'
	String get filterLanguage => 'Language';

	/// en: 'Occupation'
	String get filterOccupation => 'Occupation';

	/// en: 'All repos'
	String get filterRepoAll => 'All repos';

	/// en: 'Sort'
	String get filterSortBy => 'Sort';

	/// en: 'Recent'
	String get filterSortByRecent => 'Recent';

	/// en: 'Stars'
	String get filterSortByStars => 'Stars';

	/// en: 'Not installed'
	String get filterUninstalled => 'Not installed';

	/// en: 'Go to Discovery'
	String get goDiscovery => 'Go to Discovery';

	/// en: 'Import from disk'
	String get importFromDisk => 'Import from disk';

	/// en: 'No unmanaged skills found.'
	String get importNothing => 'No unmanaged skills found.';

	/// en: 'Import {count: int} selected'
	String importSelected({required int count}) => 'Import ${count} selected';

	/// en: 'Import unmanaged skills'
	String get importTitle => 'Import unmanaged skills';

	/// en: 'Install from ZIP'
	String get installFromZip => 'Install from ZIP';

	/// en: 'Installed {name: String}'
	String installSuccess({required String name}) => 'Installed ${name}';

	/// en: '{count: int} installed'
	String installedCount({required int count}) => '${count} installed';

	/// en: '{count: int} installs'
	String installs({required int count}) => '${count} installs';

	/// en: 'local'
	String get local => 'local';

	/// en: 'Add repo'
	String get marketplaceAddRepo => 'Add repo';

	/// en: 'Load more'
	String get marketplaceLoadMore => 'Load more';

	/// en: 'Repo added to skill sources; install individual skills in the Repos tab'
	String get marketplaceRepoAdded => 'Repo added to skill sources; install individual skills in the Repos tab';

	/// en: 'SkillsMP anonymous quota (50/day) exhausted. Set a free API key to continue.'
	String get mpQuotaHint => 'SkillsMP anonymous quota (50/day) exhausted. Set a free API key to continue.';

	/// en: 'Discovery'
	String get navDiscovery => 'Discovery';

	/// en: 'Installed'
	String get navInstalled => 'Installed';

	/// en: 'Registries'
	String get navRegistries => 'Registries';

	/// en: 'Repos'
	String get navRepos => 'Repos';

	/// en: 'No skills installed yet'
	String get noInstalled => 'No skills installed yet';

	/// en: 'Open Discovery to install your first skill.'
	String get noInstalledHint => 'Open Discovery to install your first skill.';

	/// en: 'All skills are up to date'
	String get noUpdates => 'All skills are up to date';

	/// en: '{name: String} already installed. Overwrite?'
	String overwriteConfirm({required String name}) => '${name} already installed. Overwrite?';

	/// en: 'Add registry source'
	String get registryAddSource => 'Add registry source';

	/// en: 'API key set'
	String get registryApiKeySet => 'API key set';

	/// en: 'Base URL'
	String get registryBaseUrlLabel => 'Base URL';

	/// en: 'Default browse query'
	String get registryBrowseQueryLabel => 'Default browse query';

	/// en: 'Edit registry source'
	String get registryEditTitle => 'Edit registry source';

	/// en: 'Set API key in Registries'
	String get registryGoSetKey => 'Set API key in Registries';

	/// en: 'Display name'
	String get registryNameLabel => 'Display name';

	/// en: 'Repository'
	String get registryNameOfRepoLabel => 'Repository';

	/// en: 'Owner'
	String get registryOwnerLabel => 'Owner';

	/// en: 'Protocol'
	String get registryProtocolLabel => 'Protocol';

	/// en: 'SkillsMP compatible'
	String get registryProtocolSkillsMp => 'SkillsMP compatible';

	/// en: 'skills.sh compatible'
	String get registryProtocolSkillsSh => 'skills.sh compatible';

	/// en: 'Reset registry'
	String get registryRemoveTitle => 'Reset registry';

	/// en: 'Reset {name: String} to defaults?'
	String registryResetConfirm({required String name}) => 'Reset ${name} to defaults?';

	/// en: 'Retry'
	String get registryRetry => 'Retry';

	/// en: 'This registry source already exists'
	String get registrySourceExists => 'This registry source already exists';

	/// en: 'Source type'
	String get registrySourceKind => 'Source type';

	/// en: 'API source'
	String get registrySourceKindApi => 'API source';

	/// en: 'Git repository'
	String get registrySourceKindGit => 'Git repository';

	/// en: 'Connection failed: {error: String}'
	String registryTestFailed({required String error}) => 'Connection failed: ${error}';

	/// en: 'Connection OK'
	String get registryTestOk => 'Connection OK';

	/// en: 'API Key'
	String get registryTokenLabel => 'API Key';

	/// en: 'Remove'
	String get remove => 'Remove';

	/// en: 'Add repo'
	String get repoAdd => 'Add repo';

	/// en: 'Branch'
	String get repoBranch => 'Branch';

	/// en: 'Enter a valid GitHub repo URL, e.g. https://github.com/owner/repo'
	String get repoInvalidUrl => 'Enter a valid GitHub repo URL, e.g. https://github.com/owner/repo';

	/// en: 'Remove'
	String get repoRemove => 'Remove';

	/// en: 'Remove repo {name: String}?'
	String repoRemoveConfirm({required String name}) => 'Remove repo ${name}?';

	/// en: 'Updating'
	String get repoSyncing => 'Updating';

	/// en: 'Repository URL'
	String get repoUrl => 'Repository URL';

	/// en: 'https://github.com/owner/repo'
	String get repoUrlHint => 'https://github.com/owner/repo';

	/// en: 'Search skills…'
	String get searchPlaceholder => 'Search skills…';

	/// en: 'Skills'
	String get sidebarLabel => 'Skills';

	/// en: 'Manage installable skills'
	String get subtitle => 'Manage installable skills';

	/// en: 'Skills'
	String get title => 'Skills';

	/// en: 'Uninstall {name: String}?'
	String uninstallConfirm({required String name}) => 'Uninstall ${name}?';

	/// en: 'Uninstalled {name: String}'
	String uninstallSuccess({required String name}) => 'Uninstalled ${name}';

	/// en: 'Update all ({count: int})'
	String updateAll({required int count}) => 'Update all (${count})';

	/// en: 'Update available'
	String get updateAvailable => 'Update available';

	/// en: 'Updated {name: String}'
	String updateSuccess({required String name}) => 'Updated ${name}';

	/// en: 'No SKILL.md found in the archive.'
	String get zipNoSkills => 'No SKILL.md found in the archive.';
}

// Path: ssh
class AppLocalizations$ssh$en {
	AppLocalizations$ssh$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Credentials'
	String get credentialSource => 'Credentials';

	/// en: 'This device's keychain'
	String get credentialSourceKeychain => 'This device\'s keychain';

	/// en: 'Deleted vault entry'
	String get credentialVaultDeleted => 'Deleted vault entry';

	/// en: 'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.'
	String get defaultWorkingDirectorySubtitle => 'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.';

	/// en: 'SSH default working directory'
	String get defaultWorkingDirectoryTitle => 'SSH default working directory';

	/// en: 'Remote SSH work home is disconnected. Shell, Git, and agent sessions are paused until you reconnect.'
	String get homeDisconnectedBannerMessage => 'Remote SSH work home is disconnected. Shell, Git, and agent sessions are paused until you reconnect.';

	/// en: 'Reconnect'
	String get homeDisconnectedReconnect => 'Reconnect';

	/// en: 'Fingerprint'
	String get hostKeyFingerprintLabel => 'Fingerprint';

	/// en: 'Key type: {keyType: String}'
	String hostKeyKeyTypeLabel({required String keyType}) => 'Key type: ${keyType}';

	/// en: 'The host key for {host: String} does not match the one TeamPilot saved earlier. This can happen after a reinstall — or if someone is intercepting the connection.'
	String hostKeyMismatchBody({required String host}) => 'The host key for ${host} does not match the one TeamPilot saved earlier. This can happen after a reinstall — or if someone is intercepting the connection.';

	/// en: 'SSH host key changed'
	String get hostKeyMismatchTitle => 'SSH host key changed';

	/// en: 'Previously trusted'
	String get hostKeyPreviousFingerprintLabel => 'Previously trusted';

	/// en: 'Replace and trust'
	String get hostKeyReplaceTrust => 'Replace and trust';

	/// en: 'Trust and continue'
	String get hostKeyTrust => 'Trust and continue';

	/// en: 'TeamPilot has not seen {host: String} before. Confirm the fingerprint matches this machine before trusting it.'
	String hostKeyUnknownBody({required String host}) => 'TeamPilot has not seen ${host} before. Confirm the fingerprint matches this machine before trusting it.';

	/// en: 'Verify SSH host key'
	String get hostKeyUnknownTitle => 'Verify SSH host key';

	/// en: 'Manage Remote Hosts…'
	String get hostsManage => 'Manage Remote Hosts…';

	/// en: 'Open Terminal'
	String get hostsOpenTerminal => 'Open Terminal';

	/// en: 'Open a workspace first to start a terminal.'
	String get hostsOpenTerminalNoWorkspace => 'Open a workspace first to start a terminal.';

	/// en: 'Remote Hosts'
	String get hostsPanelTitle => 'Remote Hosts';

	/// en: 'Connecting…'
	String get hostsPillConnecting => 'Connecting…';

	/// en: '(one) {1 host} (other) {{count: int} hosts}'
	String hostsPillCount({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '1 host',
		other: '${count} hosts',
	);

	/// en: 'SSH Host'
	String get hostsRowKind => 'SSH Host';

	/// en: 'Move to vault'
	String get migrateToVault => 'Move to vault';

	/// en: 'The server temporarily refused the connection (its anti-brute-force protection was triggered). Wait about a minute and try again.'
	String get penaltyRefused => 'The server temporarily refused the connection (its anti-brute-force protection was triggered). Wait about a minute and try again.';

	/// en: 'Save to vault'
	String get saveToVault => 'Save to vault';

	/// en: 'No SSH servers saved on this host yet.'
	String get serversEmpty => 'No SSH servers saved on this host yet.';

	/// en: 'Could not load the SSH servers. Check the connection and try again.'
	String get serversLoadError => 'Could not load the SSH servers. Check the connection and try again.';

	/// en: 'Not connected to a remote host.'
	String get serversNotConnected => 'Not connected to a remote host.';

	/// en: 'SSH servers'
	String get serversTitle => 'SSH servers';

	/// en: 'Vault'
	String get vaultBadge => 'Vault';
}

// Path: sshProfile
class AppLocalizations$sshProfile$en {
	AppLocalizations$sshProfile$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Connect'
	String get connect => 'Connect';

	/// en: 'Connected to {host: String}'
	String connectSuccess({required String host}) => 'Connected to ${host}';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Saving will remove the credential stored for the other authentication method.'
	String get formAuthChangeBody => 'Saving will remove the credential stored for the other authentication method.';

	/// en: 'Switch and save'
	String get formAuthChangeConfirm => 'Switch and save';

	/// en: 'Switch authentication?'
	String get formAuthChangeTitle => 'Switch authentication?';

	/// en: 'Private key'
	String get formAuthPrivateKey => 'Private key';

	/// en: 'Authentication'
	String get formAuthType => 'Authentication';

	/// en: 'Provide a private key or password.'
	String get formCredentialRequired => 'Provide a private key or password.';

	/// en: 'Target saved, but credentials could not be stored. Unlock the system keyring and edit the target to re-enter them.'
	String get formCredentialSaveFailed => 'Target saved, but credentials could not be stored. Unlock the system keyring and edit the target to re-enter them.';

	/// en: 'Required'
	String get formFieldRequired => 'Required';

	/// en: 'Host or alias'
	String get formHost => 'Host or alias';

	/// en: 'server, deploy@server:2222'
	String get formHostHint => 'server, deploy@server:2222';

	/// en: 'Private key'
	String get formIdentityFile => 'Private key';

	/// en: 'Paste the private key, or import it from a file.'
	String get formIdentityFileHelper => 'Paste the private key, or import it from a file.';

	/// en: '-----BEGIN OPENSSH PRIVATE KEY-----'
	String get formIdentityFileHint => '-----BEGIN OPENSSH PRIVATE KEY-----';

	/// en: 'Import from file'
	String get formIdentityFileImport => 'Import from file';

	/// en: 'Could not read the selected file; paste the key instead'
	String get formIdentityFileImportFailed => 'Could not read the selected file; paste the key instead';

	/// en: 'Label'
	String get formLabel => 'Label';

	/// en: 'My server'
	String get formLabelHint => 'My server';

	/// en: 'Key passphrase'
	String get formPassphrase => 'Key passphrase';

	/// en: 'Optional'
	String get formPassphraseHint => 'Optional';

	/// en: 'Password'
	String get formPassword => 'Password';

	/// en: 'Login password'
	String get formPasswordHint => 'Login password';

	/// en: 'Leave empty to keep saved password'
	String get formPasswordHintEdit => 'Leave empty to keep saved password';

	/// en: 'Port'
	String get formPort => 'Port';

	/// en: 'Port must be between 1 and 65535'
	String get formPortInvalid => 'Port must be between 1 and 65535';

	/// en: 'Edit SSH target'
	String get formTitleEdit => 'Edit SSH target';

	/// en: 'New SSH target'
	String get formTitleNew => 'New SSH target';

	/// en: 'Username'
	String get formUsername => 'Username';

	/// en: 'deploy'
	String get formUsernameHint => 'deploy';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Manage SSH servers…'
	String get selectorManage => 'Manage SSH servers…';

	/// en: 'Switch SSH server'
	String get selectorTooltip => 'Switch SSH server';

	/// en: 'Authentication failed'
	String get statusAuthFailed => 'Authentication failed';

	/// en: 'Connected'
	String get statusConnected => 'Connected';

	/// en: 'Connecting…'
	String get statusConnecting => 'Connecting…';

	/// en: 'Disconnected'
	String get statusDisconnected => 'Disconnected';

	/// en: 'Error'
	String get statusError => 'Error';

	/// en: 'Reconnecting…'
	String get statusReconnecting => 'Reconnecting…';

	/// en: 'Test'
	String get test => 'Test';

	/// en: 'Connection test failed'
	String get testFailed => 'Connection test failed';

	/// en: 'Connection closed before login: {detail: String}'
	String testFailedAborted({required String detail}) => 'Connection closed before login: ${detail}';

	/// en: 'Authentication failed'
	String get testFailedAuth => 'Authentication failed';

	/// en: 'Connection test failed: {detail: String}'
	String testFailedDetail({required String detail}) => 'Connection test failed: ${detail}';

	/// en: 'Host key was not trusted'
	String get testFailedHostKey => 'Host key was not trusted';

	/// en: 'Connection successful'
	String get testSuccess => 'Connection successful';

	/// en: 'Add target'
	String get sAddTarget => 'Add target';

	/// en: 'No SSH targets configured.'
	String get sEmpty => 'No SSH targets configured.';

	/// en: 'Import'
	String get sImport => 'Import';

	/// en: 'Import from ~/.ssh/config is not available yet.'
	String get sImportUnavailable => 'Import from ~/.ssh/config is not available yet.';

	/// en: 'SSH server configurations stored on the host behind the current home; every device paired to it shares this list.'
	String get sPageSubtitle => 'SSH server configurations stored on the host behind the current home; every device paired to it shares this list.';

	/// en: 'Remote SSH servers'
	String get sPageTitle => 'Remote SSH servers';

	/// en: 'SSH servers'
	String get sSettingsTitle => 'SSH servers';

	/// en: 'Add a remote host to connect from TeamPilot.'
	String get sTargetsSubtitle => 'Add a remote host to connect from TeamPilot.';

	/// en: 'Targets'
	String get sTargetsTitle => 'Targets';
}

// Path: team
class AppLocalizations$team$en {
	AppLocalizations$team$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Coming soon'
	String get cliComingSoon => 'Coming soon';

	/// en: 'CLI backend'
	String get cliLabel => 'CLI backend';

	/// en: 'Set when this team was created.'
	String get cliLockedSubtitle => 'Set when this team was created.';

	/// en: 'Chosen when the team is created and cannot be changed later.'
	String get cliSubtitle => 'Chosen when the team is created and cannot be changed later.';

	/// en: 'Team Config'
	String get config => 'Team Config';

	/// en: 'CLI'
	String get configAspectCli => 'CLI';

	/// en: 'Default provider'
	String get configAspectDefaultProvider => 'Default provider';

	/// en: 'Model'
	String get configAspectModel => 'Model';

	/// en: 'Provider'
	String get configAspectProvider => 'Provider';

	/// en: ', '
	String get configAspectSeparator => ', ';

	/// en: 'Team default'
	String get configGroupTeamDefault => 'Team default';

	/// en: 'Team "{team: String}" is missing settings needed to launch. The session still starts, but agents may fail without them:'
	String configIncompleteBody({required String team}) => 'Team "${team}" is missing settings needed to launch. The session still starts, but agents may fail without them:';

	/// en: 'Later'
	String get configIncompleteDismiss => 'Later';

	/// en: 'Configure team'
	String get configIncompleteGoConfigure => 'Configure team';

	/// en: 'Team configuration incomplete'
	String get configIncompleteTitle => 'Team configuration incomplete';

	/// en: '{subject: String} is missing: {aspects: String}'
	String configIssueSemanticLabel({required String subject, required String aspects}) => '${subject} is missing: ${aspects}';

	/// en: 'When a member has no CLI override.'
	String get defaultCliMixedSubtitle => 'When a member has no CLI override.';

	/// en: 'Team default effort.'
	String get defaultDialogEffortSubtitle => 'Team default effort.';

	/// en: 'Change'
	String get defaultPresetChange => 'Change';

	/// en: 'Default Model Preset'
	String get defaultPresetLabel => 'Default Model Preset';

	/// en: 'Manage'
	String get defaultPresetManage => 'Manage';

	/// en: 'None'
	String get defaultPresetNone => 'None';

	/// en: 'Optional default preset applied to members that don't override it.'
	String get defaultPresetSubtitle => 'Optional default preset applied to members that don\'t override it.';

	/// en: 'Team description'
	String get description => 'Team description';

	/// en: 'Optional note for Claude roster and team context'
	String get descriptionHint => 'Optional note for Claude roster and team context';

	/// en: 'Reasoning effort'
	String get effortLevel => 'Reasoning effort';

	/// en: 'Default effort for this team (Claude effortLevel / Codex model_reasoning_effort).'
	String get effortLevelSubtitle => 'Default effort for this team (Claude effortLevel / Codex model_reasoning_effort).';

	/// en: 'Inactive for this team'
	String get extensionEffectiveOff => 'Inactive for this team';

	/// en: 'Active for this team'
	String get extensionEffectiveOn => 'Active for this team';

	/// en: 'Follow global'
	String get extensionFollowGlobal => 'Follow global';

	/// en: 'Off'
	String get extensionForceOff => 'Off';

	/// en: 'On'
	String get extensionForceOn => 'On';

	/// en: 'Extensions'
	String get extensionsNav => 'Extensions';

	/// en: 'Override which extensions run for this team. Default follows the global setting.'
	String get extensionsSubtitle => 'Override which extensions run for this team. Default follows the global setting.';

	/// en: 'Extensions for this team'
	String get extensionsTitle => 'Extensions for this team';

	/// en: 'Team extra CLI arguments'
	String get extraArgs => 'Team extra CLI arguments';

	/// en: '--permission-mode acceptEdits'
	String get extraArgsHint => '--permission-mode acceptEdits';

	/// en: 'When enabled, a member finishing a turn is pushed back into wait_for_message instead of stopping, so it stays available for new messages and tasks. Disable to let members rest (stop normally).'
	String get forceWaitBeforeStopSubtitle => 'When enabled, a member finishing a turn is pushed back into wait_for_message instead of stopping, so it stays available for new messages and tasks. Disable to let members rest (stop normally).';

	/// en: 'Keep members in the wait loop'
	String get forceWaitBeforeStopTitle => 'Keep members in the wait loop';

	/// en: 'Draft applied. Review and adjust before creating.'
	String get genApplied => 'Draft applied. Review and adjust before creating.';

	/// en: 'Generate'
	String get genButton => 'Generate';

	/// en: 'Describe the team you want (e.g. Flutter frontend with code review and tests)'
	String get genDescriptionHint => 'Describe the team you want (e.g. Flutter frontend with code review and tests)';

	/// en: 'Could not generate a team. Please edit manually.'
	String get genFailed => 'Could not generate a team. Please edit manually.';

	/// en: 'Configure an AI provider in Settings → AI Features first.'
	String get genNoProvider => 'Configure an AI provider in Settings → AI Features first.';

	/// en: 'Generate with AI'
	String get genTitle => 'Generate with AI';

	/// en: 'Add model configuration'
	String get generateAddModel => 'Add model configuration';

	/// en: 'Team Builder'
	String get generateBuilderTitle => 'Team Builder';

	/// en: 'Cancel generation'
	String get generateCancel => 'Cancel generation';

	/// en: 'The temporary session and staged resources will be removed.'
	String get generateCancelBody => 'The temporary session and staged resources will be removed.';

	/// en: 'Cancel team generation?'
	String get generateCancelTitle => 'Cancel team generation?';

	/// en: 'Team Builder will check workspace machines and may acquire skills, plugins, and MCP servers for the generated team.'
	String get generateCapabilityNote => 'Team Builder will check workspace machines and may acquire skills, plugins, and MCP servers for the generated team.';

	/// en: 'Continue setup'
	String get generateContinueSetup => 'Continue setup';

	/// en: 'It arrived'
	String get generateDeliveryArrived => 'It arrived';

	/// en: 'The lead might receive the task twice.'
	String get generateDeliveryRetryBody => 'The lead might receive the task twice.';

	/// en: 'Send the task again?'
	String get generateDeliveryRetryTitle => 'Send the task again?';

	/// en: 'Send again…'
	String get generateDeliverySendAgain => 'Send again…';

	/// en: 'Strengths and best uses'
	String get generateDescription => 'Strengths and best uses';

	/// en: 'No configurations yet. Add the strongest one first.'
	String get generateEmptyPool => 'No configurations yet. Add the strongest one first.';

	/// en: 'Configure the generator model first.'
	String get generateErrorAiNotConfigured => 'Configure the generator model first.';

	/// en: 'Describe the task to generate a team.'
	String get generateErrorDescriptionRequired => 'Describe the task to generate a team.';

	/// en: 'The generator CLI must support sessions, skills, and MCP.'
	String get generateErrorGeneratorUnsupported => 'The generator CLI must support sessions, skills, and MCP.';

	/// en: 'The selected CLI does not support native teams.'
	String get generateErrorNativeUnsupported => 'The selected CLI does not support native teams.';

	/// en: 'Add at least one valid model configuration.'
	String get generateErrorPoolEmpty => 'Add at least one valid model configuration.';

	/// en: 'TeamPilot cannot confirm whether the lead received the task.'
	String get generateErrorPromptDeliveryUnknown => 'TeamPilot cannot confirm whether the lead received the task.';

	/// en: 'Recovery data could not be verified. The temporary session was kept.'
	String get generateErrorRecoveryIntegrity => 'Recovery data could not be verified. The temporary session was kept.';

	/// en: 'This resource needs a manual installation step and cannot be staged safely.'
	String get generateErrorStagingUnsupported => 'This resource needs a manual installation step and cannot be staged safely.';

	/// en: 'Team generation could not start. Try again.'
	String get generateErrorStartFailed => 'Team generation could not start. Try again.';

	/// en: 'A required machine or CLI is unavailable.'
	String get generateErrorTargetUnavailable => 'A required machine or CLI is unavailable.';

	/// en: 'Team generation is unavailable right now. Restart TeamPilot and try again.'
	String get generateErrorUnavailable => 'Team generation is unavailable right now. Restart TeamPilot and try again.';

	/// en: 'Complete the required sign-in or configuration, then retry.'
	String get generateErrorUserActionRequired => 'Complete the required sign-in or configuration, then retry.';

	/// en: 'Generator model'
	String get generateGeneratorModel => 'Generator model';

	/// en: '{count: int} configurations are hidden because they use another CLI.'
	String generateHiddenPresets({required int count}) => '${count} configurations are hidden because they use another CLI.';

	/// en: 'Generate and launch'
	String get generateLaunch => 'Generate and launch';

	/// en: 'Loading settings…'
	String get generateLoading => 'Loading settings…';

	/// en: 'Minimum team members'
	String get generateMinimumMemberCount => 'Minimum team members';

	/// en: 'The generated team will include at least this many distinct roles.'
	String get generateMinimumMemberCountHint => 'The generated team will include at least this many distinct roles.';

	/// en: 'Minimum must be at least 3.'
	String get generateMinimumMemberCountInvalid => 'Minimum must be at least 3.';

	/// en: 'Preset “{presetId: String}” no longer exists.'
	String generateMissingPreset({required String presetId}) => 'Preset “${presetId}” no longer exists.';

	/// en: 'Mixed'
	String get generateMixed => 'Mixed';

	/// en: 'Model configuration pool'
	String get generateModelPool => 'Model configuration pool';

	/// en: 'Rank 1 is strongest. Prefer earlier entries for the team lead.'
	String get generateModelPoolHint => 'Rank 1 is strongest. Prefer earlier entries for the team lead.';

	/// en: 'Move down'
	String get generateMoveDown => 'Move down';

	/// en: 'Move up'
	String get generateMoveUp => 'Move up';

	/// en: 'Native'
	String get generateNative => 'Native';

	/// en: 'Native CLI'
	String get generateNativeCli => 'Native CLI';

	/// en: 'Open lead session'
	String get generateOpenLeadSession => 'Open lead session';

	/// en: 'Open generation settings'
	String get generateOpenSettings => 'Open generation settings';

	/// en: 'Choose a preset'
	String get generatePickPreset => 'Choose a preset';

	/// en: 'Remove'
	String get generateRemove => 'Remove';

	/// en: 'Keep Builder Session for troubleshooting'
	String get generateRetainBuilderSession => 'Keep Builder Session for troubleshooting';

	/// en: 'When enabled, the generated team opens normally but the Builder Session is kept for inspecting the generation process.'
	String get generateRetainBuilderSessionHint => 'When enabled, the generated team opens normally but the Builder Session is kept for inspecting the generation process.';

	/// en: 'Retry'
	String get generateRetry => 'Retry';

	/// en: 'How Team Builder plans the roster, and which model configurations it may assign.'
	String get generateSettingsSubtitle => 'How Team Builder plans the roster, and which model configurations it may assign.';

	/// en: 'Generate and launch settings'
	String get generateSettingsTitle => 'Generate and launch settings';

	/// en: 'Tags'
	String get generateTags => 'Tags';

	/// en: 'Team mode'
	String get generateTeamMode => 'Team mode';

	/// en: '{assigned: int} of {total: int} enabled'
	String hooksAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} enabled';

	/// en: 'Manage hooks'
	String get hooksManage => 'Manage hooks';

	/// en: 'Hooks'
	String get hooksNav => 'Hooks';

	/// en: 'Leader'
	String get leadBadge => 'Leader';

	/// en: 'When enabled, the team lead is blocked from using some tools.'
	String get leadDelegateOnlySubtitle => 'When enabled, the team lead is blocked from using some tools.';

	/// en: 'Team lead: plan and delegate only'
	String get leadDelegateOnlyTitle => 'Team lead: plan and delegate only';

	/// en: 'FlashskyAI team delegation expects this member to be named exactly team-lead.'
	String get leadNameRequired => 'FlashskyAI team delegation expects this member to be named exactly team-lead.';

	/// en: 'FlashskyAI team delegation expects this member to be named exactly team-lead.'
	String get leadNotice => 'FlashskyAI team delegation expects this member to be named exactly team-lead.';

	/// en: 'Phase loop'
	String get loop => 'Phase loop';

	/// en: 'Default'
	String get loopDefault => 'Default';

	/// en: 'false — confirm each phase'
	String get loopFalse => 'false — confirm each phase';

	/// en: 'Team mode: true auto-advances phases; false requires your confirmation.'
	String get loopSubtitle => 'Team mode: true auto-advances phases; false requires your confirmation.';

	/// en: 'true — auto-advance'
	String get loopTrue => 'true — auto-advance';

	/// en: '{assigned: int} of {total: int} enabled'
	String mcpAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} enabled';

	/// en: 'All MCP servers'
	String get mcpManage => 'All MCP servers';

	/// en: 'MCP'
	String get mcpNav => 'MCP';

	/// en: 'Team mode'
	String get modeLabel => 'Team mode';

	/// en: 'Mixed (cross-CLI bus)'
	String get modeMixed => 'Mixed (cross-CLI bus)';

	/// en: 'Members can run different CLIs and collaborate across tools over TeamBus.'
	String get modeMixedDescription => 'Members can run different CLIs and collaborate across tools over TeamBus.';

	/// en: 'Mixed mode'
	String get modeMixedTitle => 'Mixed mode';

	/// en: 'Native (single CLI)'
	String get modeNative => 'Native (single CLI)';

	/// en: 'All members share one CLI for native, low-config collaboration.'
	String get modeNativeDescription => 'All members share one CLI for native, low-config collaboration.';

	/// en: 'Native mode'
	String get modeNativeTitle => 'Native mode';

	/// en: 'Choose a team mode first.'
	String get modeRequired => 'Choose a team mode first.';

	/// en: 'Team name'
	String get name => 'Team name';

	/// en: 'A team named "{name: String}" already exists.'
	String nameAlreadyExists({required String name}) => 'A team named "${name}" already exists.';

	/// en: 'Team name is required.'
	String get nameRequired => 'Team name is required.';

	/// en: '{assigned: int} of {total: int} installed'
	String pluginsAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} installed';

	/// en: 'This team's CLI does not support plugins yet. Selections are saved but ignored at launch.'
	String get pluginsCliUnsupportedBanner => 'This team\'s CLI does not support plugins yet. Selections are saved but ignored at launch.';

	/// en: 'No plugins installed'
	String get pluginsEmpty => 'No plugins installed';

	/// en: 'Install plugins from Discovery to enable them per team.'
	String get pluginsEmptyHint => 'Install plugins from Discovery to enable them per team.';

	/// en: 'Browse marketplace'
	String get pluginsGoDiscovery => 'Browse marketplace';

	/// en: 'All plugins'
	String get pluginsManage => 'All plugins';

	/// en: '{count: int} enabled plugin(s) missing on disk. Reinstall or remove below.'
	String pluginsMissing({required int count}) => '${count} enabled plugin(s) missing on disk. Reinstall or remove below.';

	/// en: 'Missing on disk'
	String get pluginsMissingLabel => 'Missing on disk';

	/// en: 'Linked as {dir: String} due to name conflict'
	String pluginsNameConflict({required String dir}) => 'Linked as ${dir} due to name conflict';

	/// en: 'Plugins'
	String get pluginsNav => 'Plugins';

	/// en: 'Remove'
	String get pluginsRemoveMissing => 'Remove';

	/// en: 'Team Sessions'
	String get sessions => 'Team Sessions';

	/// en: 'Team Settings'
	String get settings => 'Team Settings';

	/// en: 'Team agents'
	String get settingsSubtitle => 'Team agents';

	/// en: '{assigned: int} of {total: int} enabled'
	String skillsAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} enabled';

	/// en: 'All skills'
	String get skillsManage => 'All skills';

	/// en: 'Skills'
	String get skillsNav => 'Skills';
}

// Path: teamHub
class AppLocalizations$teamHub$en {
	AppLocalizations$teamHub$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Already added'
	String get alreadyAdded => 'Already added';

	/// en: 'Browse all teams'
	String get browseAll => 'Browse all teams';

	/// en: 'None'
	String get cardNoDescription => 'None';

	/// en: 'All'
	String get categoryAll => 'All';

	/// en: 'Clone to my teams'
	String get clone => 'Clone to my teams';

	/// en: 'Could not clone this team.'
	String get cloneFailed => 'Could not clone this team.';

	/// en: 'Clone options'
	String get cloneOptionsTitle => 'Clone options';

	/// en: 'Cloned "{name}". Installed {skillCount: int} skills, {pluginCount: int} plugins, {mcpCount: int} MCP servers, cloned {expertCount: int} experts. {failedCount: int} could not be installed: {failedNames}.'
	String clonePartial({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount, required int failedCount, required Object failedNames}) => 'Cloned "${name}". Installed ${skillCount} skills, ${pluginCount} plugins, ${mcpCount} MCP servers, cloned ${expertCount} experts. ${failedCount} could not be installed: ${failedNames}.';

	/// en: 'Cloned "{name}".'
	String cloneSuccess({required Object name}) => 'Cloned "${name}".';

	/// en: 'Cloned "{name}". Installed {skillCount: int} skills, {pluginCount: int} plugins, and {mcpCount: int} MCP servers, and cloned {expertCount: int} experts.'
	String cloneSuccessWithDeps({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount}) => 'Cloned "${name}". Installed ${skillCount} skills, ${pluginCount} plugins, and ${mcpCount} MCP servers, and cloned ${expertCount} experts.';

	/// en: 'Cloning…'
	String get cloning => 'Cloning…';

	/// en: 'Confirm'
	String get confirmSelection => 'Confirm';

	/// en: 'Installed'
	String get depInstalled => 'Installed';

	/// en: 'Will be installed'
	String get depToInstall => 'Will be installed';

	/// en: 'Discovery'
	String get discovery => 'Discovery';

	/// en: 'Refresh to fetch teams from the registry.'
	String get emptyHint => 'Refresh to fetch teams from the registry.';

	/// en: 'No public teams yet'
	String get emptyTitle => 'No public teams yet';

	/// en: 'Favorites'
	String get favorites => 'Favorites';

	/// en: 'Tap the star on a team to save it here.'
	String get favoritesEmptyHint => 'Tap the star on a team to save it here.';

	/// en: 'No favorites yet'
	String get favoritesEmptyTitle => 'No favorites yet';

	/// en: 'Could not load public teams.'
	String get loadError => 'Could not load public teams.';

	/// en: 'MCP'
	String get mcpLabel => 'MCP';

	/// en: 'Members'
	String get membersLabel => 'Members';

	/// en: 'TeamHub'
	String get nav => 'TeamHub';

	/// en: 'Team not found.'
	String get notFound => 'Team not found.';

	/// en: 'Plugins'
	String get pluginsLabel => 'Plugins';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Search public teams'
	String get searchHint => 'Search public teams';

	/// en: 'Skills'
	String get skillsLabel => 'Skills';

	/// en: 'Name'
	String get sortName => 'Name';

	/// en: 'Recently updated'
	String get sortUpdated => 'Recently updated';

	/// en: 'Discover more public teams'
	String get subtitle => 'Discover more public teams';

	/// en: 'TeamHub'
	String get title => 'TeamHub';
}

// Path: terminal
class AppLocalizations$terminal$en {
	AppLocalizations$terminal$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Clear terminal'
	String get clear => 'Clear terminal';

	/// en: 'Shift+drag to copy'
	String get copySelectHint => 'Shift+drag to copy';

	/// Shown when a dragged file lives on a different machine than the terminal it was dropped on.
	///
	/// en: 'Can't drop a local file onto a remote terminal'
	String get dropCrossMachineRejected => 'Can\'t drop a local file onto a remote terminal';

	/// en: 'Export scrollback…'
	String get exportScrollback => 'Export scrollback…';

	/// en: 'Find in terminal'
	String get find => 'Find in terminal';

	/// en: 'No results'
	String get findNoResults => 'No results';

	/// en: 'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.'
	String get linkClickOpensInAppDescription => 'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.';

	/// en: 'Open terminal links in app'
	String get linkClickOpensInAppTitle => 'Open terminal links in app';

	/// en: 'Open link'
	String get openLink => 'Open link';

	/// en: 'Dismiss'
	String get parkedSendDismiss => 'Dismiss';

	/// en: 'Sent, awaiting receipt: {content: String}'
	String parkedSendPending({required String content}) => 'Sent, awaiting receipt: ${content}';

	/// en: 'Maximum lines kept in each session terminal buffer'
	String get scrollbackLinesDescription => 'Maximum lines kept in each session terminal buffer';

	/// en: 'Terminal scrollback lines'
	String get scrollbackLinesTitle => 'Terminal scrollback lines';

	/// en: 'Match app colors or use a fixed style'
	String get themeModeDescription => 'Match app colors or use a fixed style';

	/// en: 'Terminal theme'
	String get themeModeTitle => 'Terminal theme';
}

// Path: termux
class AppLocalizations$termux$en {
	AppLocalizations$termux$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Termux is disconnected. Shell, Git, and agent sessions are paused until you reconnect.'
	String get disconnectedBannerMessage => 'Termux is disconnected. Shell, Git, and agent sessions are paused until you reconnect.';

	/// en: 'Reconnect'
	String get disconnectedReconnect => 'Reconnect';

	/// en: 'Termux is disconnected. Reconnect from the banner, then try again.'
	String get disconnectedWorkOpsBlocked => 'Termux is disconnected. Reconnect from the banner, then try again.';

	/// en: 'Clear setup'
	String get setupClearConfirmAction => 'Clear setup';

	/// en: 'This removes saved Termux keys and username. You will need to set up Termux again.'
	String get setupClearConfirmBody => 'This removes saved Termux keys and username. You will need to set up Termux again.';

	/// en: 'Clear Termux setup?'
	String get setupClearConfirmTitle => 'Clear Termux setup?';

	/// en: 'Clear setup'
	String get setupClearSetup => 'Clear setup';

	/// en: 'Connect'
	String get setupConnect => 'Connect';

	/// en: 'Could not connect to Termux'
	String get setupConnectFailed => 'Could not connect to Termux';

	/// en: 'Could not connect to Termux: {detail: String}'
	String setupConnectFailedWithDetail({required String detail}) => 'Could not connect to Termux: ${detail}';

	/// en: 'Connected to Termux'
	String get setupConnectSuccess => 'Connected to Termux';

	/// en: 'Connecting…'
	String get setupConnecting => 'Connecting…';

	/// en: 'Could not download Termux. Retry or use a store link.'
	String get setupDownloadFailed => 'Could not download Termux. Retry or use a store link.';

	/// en: 'Download & install Termux'
	String get setupDownloadInstall => 'Download & install Termux';

	/// en: 'Downloading Termux…'
	String get setupDownloading => 'Downloading Termux…';

	/// en: 'Install was cancelled or blocked. Enable unknown apps if needed, then retry.'
	String get setupInstallDenied => 'Install was cancelled or blocked. Enable unknown apps if needed, then retry.';

	/// en: 'F-Droid'
	String get setupInstallFDroid => 'F-Droid';

	/// en: 'GitHub'
	String get setupInstallGitHub => 'GitHub';

	/// en: 'Play Store'
	String get setupInstallPlayStore => 'Play Store';

	/// en: 'Installing…'
	String get setupInstalling => 'Installing…';

	/// en: 'Install Termux, paste one setup script, then connect TeamPilot to the local SSH server.'
	String get setupIntro => 'Install Termux, paste one setup script, then connect TeamPilot to the local SSH server.';

	/// en: 'Allow storage access when prompted. sshd is enabled via termux-services (starts when Termux opens). Optional: install Termux:Boot from F-Droid for reboot without opening Termux. The last line prints your username (e.g. u0_a399).'
	String get setupScriptHint => 'Allow storage access when prompted. sshd is enabled via termux-services (starts when Termux opens). Optional: install Termux:Boot from F-Droid for reboot without opening Termux. The last line prints your username (e.g. u0_a399).';

	/// en: '1. Install Termux'
	String get setupStepInstallTermux => '1. Install Termux';

	/// en: '2. Paste this script in Termux'
	String get setupStepRunScript => '2. Paste this script in Termux';

	/// en: 'Termux is installed'
	String get setupTermuxInstalled => 'Termux is installed';

	/// en: 'Termux setup'
	String get setupTitle => 'Termux setup';

	/// en: 'Enter a valid Termux username (starts with u)'
	String get setupUsernameError => 'Enter a valid Termux username (starts with u)';

	/// en: 'e.g. u0_a399'
	String get setupUsernameHint => 'e.g. u0_a399';

	/// en: '3. Paste your Termux username'
	String get setupUsernameLabel => '3. Paste your Termux username';
}

// Path: theme
class AppLocalizations$theme$en {
	AppLocalizations$theme$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Theme'
	String get theme => 'Theme';

	/// en: 'Primary and accent colors for buttons, toggles, and highlights.'
	String get colorPresetDescription => 'Primary and accent colors for buttons, toggles, and highlights.';

	/// en: 'Theme colors'
	String get colorPresetTitle => 'Theme colors';

	/// en: 'Dark'
	String get dark => 'Dark';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Light, dark, or match the operating system appearance.'
	String get modeDescription => 'Light, dark, or match the operating system appearance.';

	/// en: 'Theme mode'
	String get modeTitle => 'Theme mode';

	/// en: 'Amber'
	String get presetAmber => 'Amber';

	/// en: 'Forest'
	String get presetForest => 'Forest';

	/// en: 'Graphite'
	String get presetGraphite => 'Graphite';

	/// en: 'Ocean'
	String get presetOcean => 'Ocean';

	/// en: 'Violet'
	String get presetViolet => 'Violet';

	/// en: 'System'
	String get system => 'System';
}

// Path: tool
class AppLocalizations$tool$en {
	AppLocalizations$tool$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Ask user'
	String get categoryAskUser => 'Ask user';

	/// en: 'Browser'
	String get categoryBrowser => 'Browser';

	/// en: 'Shell command'
	String get categoryCommand => 'Shell command';

	/// en: 'Edit file'
	String get categoryEdit => 'Edit file';

	/// en: 'MCP'
	String get categoryMcp => 'MCP';

	/// en: 'Other'
	String get categoryOther => 'Other';

	/// en: 'Plan'
	String get categoryPlan => 'Plan';

	/// en: 'Read file'
	String get categoryRead => 'Read file';

	/// en: 'Web search'
	String get categorySearch => 'Web search';

	/// en: 'Subagent'
	String get categorySubagent => 'Subagent';

	/// en: 'Tasks & todos'
	String get categoryTask => 'Tasks & todos';

	/// en: 'Write file'
	String get categoryWrite => 'Write file';

	/// en: 'Tool Placement'
	String get placement => 'Tool Placement';

	/// en: 'Dock tool panels on the right or along the bottom edge.'
	String get placementDescription => 'Dock tool panels on the right or along the bottom edge.';
}

// Path: typography
class AppLocalizations$typography$en {
	AppLocalizations$typography$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Large'
	String get scaleComfortable => 'Large';

	/// en: 'Small'
	String get scaleCompact => 'Small';

	/// en: 'Custom'
	String get scaleCustom => 'Custom';

	/// en: '50–200'
	String get scaleCustomHint => '50–200';

	/// en: 'Scale'
	String get scaleCustomLabel => 'Scale';

	/// en: 'Size of UI text. Standard follows your system; does not change icons or spacing.'
	String get scaleDescription => 'Size of UI text. Standard follows your system; does not change icons or spacing.';

	/// en: 'Standard'
	String get scaleStandard => 'Standard';

	/// en: 'Text size'
	String get scaleTitle => 'Text size';
}

// Path: vault
class AppLocalizations$vault$en {
	AppLocalizations$vault$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Copied'
	String get copied => 'Copied';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Delete'
	String get deleteConfirm => 'Delete';

	/// en: 'This entry is still used by:'
	String get deleteReferenced => 'This entry is still used by:';

	/// en: 'Delete entry?'
	String get deleteTitle => 'Delete entry?';

	/// en: 'Disable encrypted vault'
	String get disableEncryption => 'Disable encrypted vault';

	/// en: 'Save SSH passwords, private keys or provider API keys here.'
	String get emptyHint => 'Save SSH passwords, private keys or provider API keys here.';

	/// en: 'No entries yet'
	String get emptyTitle => 'No entries yet';

	/// en: 'Enable encrypted vault'
	String get enableEncryption => 'Enable encrypted vault';

	/// en: 'Favorite'
	String get entryFavorite => 'Favorite';

	/// en: 'Notes'
	String get entryNotes => 'Notes';

	/// en: 'Tags (comma separated)'
	String get entryTags => 'Tags (comma separated)';

	/// en: 'Title'
	String get entryTitle => 'Title';

	/// en: 'Type'
	String get entryType => 'Type';

	/// en: 'Hide'
	String get hide => 'Hide';

	/// en: 'Not connected to the remote host. Business credentials stored there are unavailable until it reconnects.'
	String get homeOfflineHint => 'Not connected to the remote host. Business credentials stored there are unavailable until it reconnects.';

	/// en: 'Lock now'
	String get lock => 'Lock now';

	/// en: 'Unlock the vault to query usage.'
	String get lockedQueryBlocked => 'Unlock the vault to query usage.';

	/// en: 'Unlock the vault to save credentials.'
	String get lockedSaveBlocked => 'Unlock the vault to save credentials.';

	/// en: 'New entry'
	String get newEntry => 'New entry';

	/// en: 'Not referenced yet'
	String get noReferences => 'Not referenced yet';

	/// en: 'Copy only'
	String get onlyCopy => 'Copy only';

	/// en: 'SSH passwords, private keys and provider API keys'
	String get pageSubtitle => 'SSH passwords, private keys and provider API keys';

	/// en: 'Credential Vault'
	String get pageTitle => 'Credential Vault';

	/// en: 'Master passphrase'
	String get passphrase => 'Master passphrase';

	/// en: 'Confirm passphrase'
	String get passphraseConfirm => 'Confirm passphrase';

	/// en: 'Passphrases do not match'
	String get passphraseMismatch => 'Passphrases do not match';

	/// en: 'Passphrase is required'
	String get passphraseRequired => 'Passphrase is required';

	/// en: 'Used by'
	String get references => 'Used by';

	/// en: 'Reveal'
	String get reveal => 'Reveal';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Search title, fields or tags'
	String get searchHint => 'Search title, fields or tags';

	/// en: 'Encrypted vault · locked'
	String get statusEncrypted => 'Encrypted vault · locked';

	/// en: 'System keychain · no unlock needed'
	String get statusKeychain => 'System keychain · no unlock needed';

	/// en: 'Encrypted vault · unlocked'
	String get statusUnlocked => 'Encrypted vault · unlocked';

	/// en: 'Stored in vault'
	String get storedInVault => 'Stored in vault';

	/// en: 'Provider API key'
	String get typeApiKey => 'Provider API key';

	/// en: 'Custom'
	String get typeCustom => 'Custom';

	/// en: 'Login'
	String get typeLogin => 'Login';

	/// en: 'Secure note'
	String get typeSecureNote => 'Secure note';

	/// en: 'SSH password'
	String get typeSshPassword => 'SSH password';

	/// en: 'SSH private key'
	String get typeSshPrivateKey => 'SSH private key';

	/// en: 'Token'
	String get typeToken => 'Token';

	/// en: 'Credential vault is unavailable.'
	String get unavailable => 'Credential vault is unavailable.';

	/// en: 'Unlock'
	String get unlock => 'Unlock';

	/// en: 'Could not unlock the vault'
	String get unlockFailed => 'Could not unlock the vault';

	/// en: 'Unlock vault'
	String get unlockTitle => 'Unlock vault';

	/// en: 'Wrong passphrase or damaged file. Data was not modified.'
	String get wrongPassphraseHint => 'Wrong passphrase or damaged file. Data was not modified.';
}

// Path: workspace
class AppLocalizations$workspace$en {
	AppLocalizations$workspace$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Additional directories'
	String get additionalDirectories => 'Additional directories';

	/// en: 'Advanced'
	String get advancedSettings => 'Advanced';

	/// en: 'Agent preset and extra CLI flags for this member.'
	String get advancedSettingsSubtitle => 'Agent preset and extra CLI flags for this member.';

	/// en: 'Maps to flashskyai --agent when that CLI is active.'
	String get agentBuiltInSubtitle => 'Maps to flashskyai --agent when that CLI is active.';

	/// en: 'Extra CLI arguments'
	String get agentExtraArgs => 'Extra CLI arguments';

	/// en: 'Extra flags appended when starting the agent in this workspace.'
	String get agentExtraArgsSubtitle => 'Extra flags appended when starting the agent in this workspace.';

	/// en: 'Developer'
	String get agentPromptPresetDeveloper => 'Developer';

	/// en: 'Focus on implementation and fixes. Prefer minimal diffs, run relevant tests, and briefly explain changed files and rationale.'
	String get agentPromptPresetDeveloperText => 'Focus on implementation and fixes. Prefer minimal diffs, run relevant tests, and briefly explain changed files and rationale.';

	/// en: 'General'
	String get agentPromptPresetGeneral => 'General';

	/// en: 'Help with development in this workspace end to end. Understand the request and codebase, propose a clear approach, then implement with minimal diffs; summarize changed files and suggested next steps.'
	String get agentPromptPresetGeneralText => 'Help with development in this workspace end to end. Understand the request and codebase, propose a clear approach, then implement with minimal diffs; summarize changed files and suggested next steps.';

	/// en: 'Researcher'
	String get agentPromptPresetResearcher => 'Researcher';

	/// en: 'Investigate and report only; do not change production code unless asked. Output findings with file paths, relevant symbols, and recommended next steps.'
	String get agentPromptPresetResearcherText => 'Investigate and report only; do not change production code unless asked.\nOutput findings with file paths, relevant symbols, and recommended next steps.';

	/// en: 'Reviewer'
	String get agentPromptPresetReviewer => 'Reviewer';

	/// en: 'Review code only; do not modify files unless asked. Each finding must include file path, line, issue, and suggested fix.'
	String get agentPromptPresetReviewerText => 'Review code only; do not modify files unless asked.\nEach finding must include file path, line, issue, and suggested fix.';

	/// en: 'System prompt defining the agent's role and boundaries in this workspace.'
	String get agentPromptSubtitle => 'System prompt defining the agent\'s role and boundaries in this workspace.';

	/// en: 'Attach files'
	String get chatLandingAttach => 'Attach files';

	/// en: 'Back to workbench'
	String get chatLandingBackToWorkbench => 'Back to workbench';

	/// en: 'Connect apps'
	String get chatLandingConnectApps => 'Connect apps';

	/// en: 'Custom…'
	String get chatLandingCustomLaunch => 'Custom…';

	/// en: 'Custom launch'
	String get chatLandingCustomLaunchTitle => 'Custom launch';

	/// en: 'What can I help you with today? @ reference files, / invoke skills'
	String get chatLandingInputHint => 'What can I help you with today? @ reference files, / invoke skills';

	/// en: 'Simple chat'
	String get chatLandingModeSimple => 'Simple chat';

	/// en: 'Team'
	String get chatLandingModeTeam => 'Team';

	/// en: 'Select directory >'
	String get chatLandingSelectLaunchDirectory => 'Select directory >';

	/// en: 'Select project >'
	String get chatLandingSelectProject => 'Select project >';

	/// en: 'Select workspace >'
	String get chatLandingSelectWorkspace => 'Select workspace >';

	/// en: 'Select worktree >'
	String get chatLandingSelectWorktree => 'Select worktree >';

	/// en: 'Skills'
	String get chatLandingSkills => 'Skills';

	/// en: 'Configure team and member model presets in Team Settings before sending.'
	String get chatLandingTeamLaunchBlocked => 'Configure team and member model presets in Team Settings before sending.';

	/// en: 'Use preset'
	String get chatLandingUsePreset => 'Use preset';

	/// en: 'Voice input'
	String get chatLandingVoice => 'Voice input';

	/// en: 'Cancel recording'
	String get chatLandingVoiceCancel => 'Cancel recording';

	/// en: 'Voice input cannot request macOS speech permissions when TeamPilot is launched from the IDE. Run build/macos/Build/Products/Debug/TeamPilot.app directly, or launch from Xcode.'
	String get chatLandingVoiceMacOsIdeLaunch => 'Voice input cannot request macOS speech permissions when TeamPilot is launched from the IDE. Run build/macos/Build/Products/Debug/TeamPilot.app directly, or launch from Xcode.';

	/// en: 'Microphone permission denied'
	String get chatLandingVoicePermissionDenied => 'Microphone permission denied';

	/// en: 'Stop recording'
	String get chatLandingVoiceStop => 'Stop recording';

	/// en: 'Voice input is not available on this device'
	String get chatLandingVoiceUnavailable => 'Voice input is not available on this device';

	/// en: 'Add Preset'
	String get cliAddPresetTitle => 'Add Preset';

	/// en: '{provider: String} · {model: String}'
	String cliConfigSummary({required String provider, required String model}) => '${provider} · ${model}';

	/// en: 'Configure'
	String get cliConfigure => 'Configure';

	/// en: 'Configured'
	String get cliConfigured => 'Configured';

	/// en: 'Default CLI for new conversations in this workspace.'
	String get cliDefaultSubtitle => 'Default CLI for new conversations in this workspace.';

	/// en: 'Set the default provider and model for each CLI used in this workspace.'
	String get cliDefaultsSubtitle => 'Set the default provider and model for each CLI used in this workspace.';

	/// en: 'CLI defaults'
	String get cliDefaultsTitle => 'CLI defaults';

	/// en: 'Delete preset '{name: String}'? This cannot be undone.'
	String cliDeletePresetConfirm({required String name}) => 'Delete preset \'${name}\'? This cannot be undone.';

	/// en: 'Delete Preset'
	String get cliDeletePresetTitle => 'Delete Preset';

	/// en: 'Edit Preset'
	String get cliEditPresetTitle => 'Edit Preset';

	/// en: 'Use provider default'
	String get cliEffortInheritHint => 'Use provider default';

	/// en: 'Reasoning effort'
	String get cliEffortLevel => 'Reasoning effort';

	/// en: 'Default effort for this CLI in the workspace (leave empty to use provider default).'
	String get cliEffortLevelSubtitle => 'Default effort for this CLI in the workspace (leave empty to use provider default).';

	/// en: 'Manage'
	String get cliManagePresets => 'Manage';

	/// en: 'No preset selected'
	String get cliNoPresetHint => 'No preset selected';

	/// en: 'No provider setup required for this CLI'
	String get cliNoProviderCatalog => 'No provider setup required for this CLI';

	/// en: 'Not configured'
	String get cliNotConfigured => 'Not configured';

	/// en: 'No default provider selected yet'
	String get cliNotConfiguredHint => 'No default provider selected yet';

	/// en: 'Active Preset'
	String get cliPresetLabel => 'Active Preset';

	/// en: 'Preset Name'
	String get cliPresetNameLabel => 'Preset Name';

	/// en: 'No presets yet. Create one to get started.'
	String get cliPresetsEmptyHint => 'No presets yet. Create one to get started.';

	/// en: 'Manage Presets'
	String get cliPresetsManageTitle => 'Manage Presets';

	/// en: 'Provider configuration'
	String get cliProviderConfig => 'Provider configuration';

	/// en: 'Provider & model'
	String get cliProviderModelTitle => 'Provider & model';

	/// en: 'Created'
	String get createdAt => 'Created';

	/// en: 'Missing machine'
	String get deadTargetBadge => 'Missing machine';

	/// en: 'Remap…'
	String get deadTargetRemap => 'Remap…';

	/// en: 'Replace {from: String} with another machine. Directory paths are not changed — they must already exist on the destination.'
	String deadTargetRemapBody({required String from}) => 'Replace ${from} with another machine. Directory paths are not changed — they must already exist on the destination.';

	/// en: 'Remap'
	String get deadTargetRemapConfirm => 'Remap';

	/// en: 'Could not remap machine.'
	String get deadTargetRemapFailed => 'Could not remap machine.';

	/// en: 'Remap machine…'
	String get deadTargetRemapFromLaunch => 'Remap machine…';

	/// en: 'Nothing to remap.'
	String get deadTargetRemapNothing => 'Nothing to remap.';

	/// en: 'Dead machine'
	String get deadTargetRemapPickFrom => 'Dead machine';

	/// en: 'Replacement machine'
	String get deadTargetRemapPickTo => 'Replacement machine';

	/// en: 'Remap machine'
	String get deadTargetRemapTitle => 'Remap machine';

	/// en: 'Workspace details'
	String get details => 'Workspace details';

	/// en: 'Directory added to workspace'
	String get directoryAdded => 'Directory added to workspace';

	/// en: 'This directory is already in the workspace.'
	String get directoryAlreadyAdded => 'This directory is already in the workspace.';

	/// en: 'This path is already the primary directory.'
	String get directoryAlreadyPrimary => 'This path is already the primary directory.';

	/// en: 'Display name'
	String get displayName => 'Display name';

	/// en: 'Where the app opens after launch.'
	String get entryModeDescription => 'Where the app opens after launch.';

	/// en: 'Home'
	String get entryModeHome => 'Home';

	/// en: 'Last workspace'
	String get entryModeLastWorkspace => 'Last workspace';

	/// en: 'Startup view'
	String get entryModeTitle => 'Startup view';

	/// en: 'Disabled for this workspace'
	String get extensionEffectiveOff => 'Disabled for this workspace';

	/// en: 'Enabled for this workspace'
	String get extensionEffectiveOn => 'Enabled for this workspace';

	/// en: 'Override which extensions run for this workspace. Default follows the global setting.'
	String get extensionsSubtitle => 'Override which extensions run for this workspace. Default follows the global setting.';

	/// en: 'Extensions for this workspace'
	String get extensionsTitle => 'Extensions for this workspace';

	/// en: 'Directory'
	String get folderPathLabel => 'Directory';

	/// en: 'Machine'
	String get folderTargetLabel => 'Machine';

	/// en: 'Add other host directories'
	String get foldersAddOnAnotherMachine => 'Add other host directories';

	/// en: 'Set all to local'
	String get foldersApplyAllLocal => 'Set all to local';

	/// en: 'Set all to remote…'
	String get foldersApplyAllRemote => 'Set all to remote…';

	/// en: 'Change'
	String get foldersChangeTarget => 'Change';

	/// en: 'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).'
	String get foldersEditorHint => 'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).';

	/// en: 'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.'
	String get foldersPersonalTargetsLockedHint => 'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.';

	/// en: 'Add directory on machine'
	String get foldersPickMixedTarget => 'Add directory on machine';

	/// en: 'Choose directory'
	String get foldersPickPath => 'Choose directory';

	/// en: 'Choose remote machine'
	String get foldersPickRemoteTarget => 'Choose remote machine';

	/// en: 'Choose machine'
	String get foldersPickTarget => 'Choose machine';

	/// en: 'Directories & machines'
	String get foldersSectionTitle => 'Directories & machines';

	/// en: '{assigned: int} of {total: int} enabled for this workspace'
	String hooksAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} enabled for this workspace';

	/// en: 'Manage hooks'
	String get hooksManage => 'Manage hooks';

	/// en: 'Icon'
	String get icon => 'Icon';

	/// en: 'Choose workspace icon'
	String get iconPickerTitle => 'Choose workspace icon';

	/// en: 'Upload icon'
	String get iconUpload => 'Upload icon';

	/// en: 'Could not save icon. Use PNG, JPG, WEBP, or SVG.'
	String get iconUploadFailed => 'Could not save icon. Use PNG, JPG, WEBP, or SVG.';

	/// en: 'Use default'
	String get iconUseDefault => 'Use default';

	/// en: '{assigned: int} of {total: int} enabled for this workspace'
	String mcpAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} enabled for this workspace';

	/// en: 'Manage MCP'
	String get mcpManage => 'Manage MCP';

	/// en: 'No additional directories'
	String get noAdditionalDirectories => 'No additional directories';

	/// en: '{assigned: int} of {total: int} linked to this workspace'
	String pluginsAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} linked to this workspace';

	/// en: 'No plugins installed'
	String get pluginsEmpty => 'No plugins installed';

	/// en: 'Install plugins from Discovery to enable them for this workspace.'
	String get pluginsEmptyHint => 'Install plugins from Discovery to enable them for this workspace.';

	/// en: 'Manage plugins'
	String get pluginsManage => 'Manage plugins';

	/// en: 'Primary directory'
	String get primaryPath => 'Primary directory';

	/// en: 'No primary directory selected'
	String get primaryPathNotSelected => 'No primary directory selected';

	/// en: 'Select a primary directory first.'
	String get primaryPathRequired => 'Select a primary directory first.';

	/// en: 'Open'
	String get runningSessionsSection => 'Open';

	/// en: 'Engine: {backend: String}'
	String searchBackend({required String backend}) => 'Engine: ${backend}';

	/// en: 'Cancel'
	String get searchCancel => 'Cancel';

	/// en: 'Aa'
	String get searchCaseSensitive => 'Aa';

	/// en: 'Content'
	String get searchContent => 'Content';

	/// en: 'Type to search file contents'
	String get searchEmptyHint => 'Type to search file contents';

	/// en: 'Search failed — check the pattern'
	String get searchError => 'Search failed — check the pattern';

	/// en: 'Exclude (glob, comma-separated)'
	String get searchExcludeHint => 'Exclude (glob, comma-separated)';

	/// en: 'Type to search files'
	String get searchFilesEmptyHint => 'Type to search files';

	/// en: 'Files'
	String get searchFilesSection => 'Files';

	/// en: 'Files to exclude:'
	String get searchFilesToExclude => 'Files to exclude:';

	/// en: 'Files to include:'
	String get searchFilesToInclude => 'Files to include:';

	/// en: 'All'
	String get searchFilterAll => 'All';

	/// en: 'Tasks'
	String get searchFilterConversations => 'Tasks';

	/// en: 'Files'
	String get searchFilterFiles => 'Files';

	/// en: '.gitignore'
	String get searchGitignore => '.gitignore';

	/// en: 'Search sessions, files and transcript content'
	String get searchHint => 'Search sessions, files and transcript content';

	/// en: 'Include (glob, comma-separated)'
	String get searchIncludeHint => 'Include (glob, comma-separated)';

	/// en: 'Indexing…'
	String get searchIndexing => 'Indexing…';

	/// en: 'No matches'
	String get searchNoResults => 'No matches';

	/// en: 'Search'
	String get searchPanel => 'Search';

	/// en: 'Search files'
	String get searchQueryHint => 'Search files';

	/// en: 'Recent sessions'
	String get searchRecentSessions => 'Recent sessions';

	/// en: 'Regex'
	String get searchRegex => 'Regex';

	/// en: 'Replace'
	String get searchReplace => 'Replace';

	/// en: 'Replace All'
	String get searchReplaceAll => 'Replace All';

	/// en: 'Replace {count: int} occurrence(s)?'
	String searchReplaceAllMessage({required int count}) => 'Replace ${count} occurrence(s)?';

	/// en: 'Replace all?'
	String get searchReplaceAllTitle => 'Replace all?';

	/// en: 'Replace with'
	String get searchReplaceHint => 'Replace with';

	/// en: 'Replaced {count: int}'
	String searchReplacedCount({required int count}) => 'Replaced ${count}';

	/// en: '{matches: int} results in {files: int} files'
	String searchResultSummary({required int matches, required int files}) => '${matches} results in ${files} files';

	/// en: 'Searching files…'
	String get searchSearching => 'Searching files…';

	/// en: 'Show more results'
	String get searchShowMore => 'Show more results';

	/// en: 'Search failed in "{directory: String}"'
	String searchSliceError({required String directory}) => 'Search failed in "${directory}"';

	/// en: 'Search'
	String get searchTitle => 'Search';

	/// en: 'Toggle search details'
	String get searchToggleDetails => 'Toggle search details';

	/// en: 'Results truncated — refine your query'
	String get searchTruncated => 'Results truncated — refine your query';

	/// en: 'Use .gitignore settings'
	String get searchUseGitignore => 'Use .gitignore settings';

	/// en: 'Sessions'
	String get sessionCount => 'Sessions';

	/// en: 'Groups'
	String get sidebarGroupsView => 'Groups';

	/// en: 'Project tree'
	String get sidebarProjectTreeView => 'Project tree';

	/// en: '{assigned: int} of {total: int} enabled for this workspace'
	String skillsAssignedCount({required int assigned, required int total}) => '${assigned} of ${total} enabled for this workspace';

	/// en: 'Manage skills'
	String get skillsManage => 'Manage skills';

	/// en: 'The machine this workspace's folders live and run on. Sessions launch on this target; switching does not move files.'
	String get targetSubtitle => 'The machine this workspace\'s folders live and run on. Sessions launch on this target; switching does not move files.';

	/// en: 'Workspace machine'
	String get targetTitle => 'Workspace machine';

	/// en: 'Terminal'
	String get terminal => 'Terminal';

	/// en: 'Close terminal panel'
	String get terminalClose => 'Close terminal panel';

	/// en: 'Close terminal'
	String get terminalCloseSession => 'Close terminal';

	/// en: 'New terminal'
	String get terminalNewSession => 'New terminal';

	/// en: 'New terminal session menu'
	String get terminalNewSessionMenu => 'New terminal session menu';

	/// en: 'New SSH Session…'
	String get terminalNewSshSession => 'New SSH Session…';

	/// en: 'Connect a session to open the shell terminal'
	String get terminalNoWorkingDirectory => 'Connect a session to open the shell terminal';

	/// en: 'Restoring terminal…'
	String get terminalRestoring => 'Restoring terminal…';

	/// en: 'Settings'
	String get terminalSettings => 'Settings';

	/// en: 'SSH profile not found or connection failed'
	String get terminalSshConnectFailed => 'SSH profile not found or connection failed';

	/// en: 'Match app theme'
	String get terminalThemeAdaptive => 'Match app theme';

	/// en: 'Classic dark'
	String get terminalThemeClassicDark => 'Classic dark';

	/// en: 'High contrast'
	String get terminalThemeHighContrast => 'High contrast';

	/// en: 'Could not open workspace tools'
	String get toolsResolveFailed => 'Could not open workspace tools';

	/// en: 'Check that remote machines are reachable, then try again.'
	String get toolsResolveFailedHint => 'Check that remote machines are reachable, then try again.';

	/// en: 'Local workspace'
	String get topologyLocal => 'Local workspace';

	/// en: 'Mixed workspace'
	String get topologyMixed => 'Mixed workspace';

	/// en: 'Remote workspace'
	String get topologyRemote => 'Remote workspace';

	/// en: 'Type'
	String get typeLabel => 'Type';

	/// en: 'Updated'
	String get updatedAt => 'Updated';

	/// en: 'Agent preset and extra CLI flags for this workspace.'
	String get workbenchAdvancedSettingsSubtitle => 'Agent preset and extra CLI flags for this workspace.';
}

// Path: worktree
class AppLocalizations$worktree$en {
	AppLocalizations$worktree$en.internal(this._root);

	final AppLocalizations _root; // ignore: unused_field

	// Translations

	/// en: 'Branch or ref'
	String get baseSelectorHint => 'Branch or ref';

	/// en: 'Branch name'
	String get branchLabel => 'Branch name';

	/// en: 'Create'
	String get createAction => 'Create';

	/// en: 'Failed to create worktree: {error}'
	String createFailed({required Object error}) => 'Failed to create worktree: ${error}';

	/// en: 'New worktree'
	String get createTitle => 'New worktree';

	/// en: 'Creating…'
	String get creating => 'Creating…';

	/// en: 'Remove'
	String get deleteAction => 'Remove';

	/// en: 'Remove the worktree for {branch}?'
	String deleteBody({required Object branch}) => 'Remove the worktree for ${branch}?';

	/// en: 'Also delete the branch'
	String get deleteBranchToo => 'Also delete the branch';

	/// en: 'Stop the running conversations in this worktree before removing it.'
	String get deleteBusyWarning => 'Stop the running conversations in this worktree before removing it.';

	/// en: 'Failed to remove worktree: {error}'
	String deleteFailed({required Object error}) => 'Failed to remove worktree: ${error}';

	/// en: 'Force-remove even if it has uncommitted changes'
	String get deleteForce => 'Force-remove even if it has uncommitted changes';

	/// en: 'Also delete the {count} conversations in this worktree'
	String deleteSessionsToo({required Object count}) => 'Also delete the ${count} conversations in this worktree';

	/// en: 'Remove worktree'
	String get deleteTitle => 'Remove worktree';

	/// en: 'Copy path'
	String get menuCopyPath => 'Copy path';

	/// en: 'Remove worktree'
	String get menuRemove => 'Remove worktree';

	/// en: 'More'
	String get more => 'More';

	/// en: 'New conversation here'
	String get newConversationHere => 'New conversation here';

	/// en: 'New worktree'
	String get newWorktreeTooltip => 'New worktree';

	/// en: 'Other'
	String get orphanGroup => 'Other';

	/// en: 'Location'
	String get pathLabel => 'Location';

	/// en: 'Random name'
	String get randomNameTooltip => 'Random name';

	/// en: 'Refresh worktrees'
	String get refreshTooltip => 'Refresh worktrees';

	/// en: 'Show less'
	String get showLess => 'Show less';

	/// en: 'Show {count} more'
	String showMore({required Object count}) => 'Show ${count} more';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on AppLocalizations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'aboutCurrentVersion' => 'Current version',
			'aboutGitHub' => 'GitHub',
			'aboutPageSubtitle' => 'TeamPilot version and application updates.',
			'aboutTitle' => 'About',
			'aboutVersionLoading' => 'Loading…',
			'account' => 'account',
			'accountCredentialPath' => 'Account credential path',
			'actualModel' => 'Actual Model',
			'add' => 'Add',
			'addAccountPath' => 'Add account path',
			'addModel' => 'Add Model',
			'addProvider' => 'Add Provider',
			'addTeamTitle' => 'Add team',
			'addTeamTooltip' => 'Add team',
			'addWorkspaceDirectory' => 'Add directory',
			'allChecksPassed' => 'All checks passed.',
			'androidWorkEnvironmentSelectorLabel' => 'Work environment',
			'androidWorkEnvironmentSelectorManageTermux' => 'Termux setup…',
			'androidWorkEnvironmentSelectorTermux' => 'Termux',
			'androidWorkEnvironmentSelectorTermuxWithUser' => ({required String username}) => 'Termux · ${username}',
			'api' => 'api',
			'apiKey' => 'API Key',
			'appearance' => 'Appearance',
			'archiveConversation' => 'Archive',
			'askUserQuestionBubbleAsked' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'Asked ${count} question', other: 'Asked ${count} questions', ), 
			'askUserQuestionBubbleAsking' => 'Asking questions',
			'askUserQuestionBubbleUnanswered' => 'Unanswered',
			'autoLaunchAllMembersDescription' => 'Mixed teams only: when enabled, Connect and Restart launch every valid member shell; native teams always launch all members.',
			'autoLaunchAllMembersTitle' => 'Start all members on connect',
			'autoOpenSubagentPreviewDescription' => 'When a subagent starts running, open its preview automatically and follow it live. Press Back to stop following for this session.',
			'autoOpenSubagentPreviewTitle' => 'Auto-open subagent preview',
			'back' => 'Back',
			'baseUrl' => 'Base URL',
			'board' => 'Board',
			'boardClaimed' => 'In progress',
			'boardDone' => 'Done',
			'boardEmpty' => 'No tasks yet',
			'boardPending' => 'Pending',
			'bootstrapChooseWorkEnvironment' => 'Choose work environment',
			'bootstrapLoadingApp' => 'Starting TeamPilot…',
			'bootstrapLoadingLibraries' => 'Loading libraries…',
			'bootstrapLoadingWorkspaces' => 'Loading workspaces…',
			'bootstrapRetry' => 'Retry',
			'bootstrapStartupFailed' => ({required String error}) => 'Startup failed: ${error}',
			'bootstrapUseNativeStorageInstead' => 'Use Windows local storage instead',
			'bottom' => 'Bottom',
			'bottomDockPanelHidden' => 'Hide bottom panel',
			'bottomDockPanelVisible' => 'Show bottom panel',
			'bottomTray' => 'Bottom Tray',
			'branchEditFailed' => 'Failed to send the edited message',
			'branchNext' => 'Next version',
			'branchPrevious' => 'Previous version',
			'branchSwitchFailed' => 'Failed to switch version',
			'cancel' => 'Cancel',
			'closeAllTabs' => 'Close All',
			'closeConversation' => 'Close conversation',
			'closeOtherTabs' => 'Close Others',
			'closeRightTabs' => 'Close to the Right',
			'closeTab' => 'Close',
			'configure' => 'Configure',
			'confirm' => 'Confirm',
			'contentDisplayModeFlatten' => 'Flatten (natural height)',
			'contentDisplayModeFoldExpandFull' => 'Fold · expand full',
			'contentDisplayModeFoldFixedHeight' => 'Fold · fixed height',
			'contentDisplayModeSectionTitle' => 'Content display',
			'continueSwitchRestartBody' => 'The new provider/model is saved. A running session still uses the old config, so the switch only takes effect after a restart.',
			'continueSwitchRestartLater' => 'Later',
			'continueSwitchRestartNow' => 'Restart now',
			'continueSwitchRestartTitle' => 'Restart to apply switch?',
			'conversationName' => 'Conversation name',
			'copy' => 'copy',
			'copyFolderPath' => 'Copy Folder Path',
			'copyPrompt' => 'Copy prompt',
			'cotExpandLatestOnOpenDescription' => 'Auto-expand the thinking process of the latest message while the agent is still thinking, then fold it once that output ends.',
			'cotExpandLatestOnOpenTitle' => 'Expand latest thinking process',
			'cotExpandReasoningOnOpenDescription' => 'When you open a thinking-process block, expand nested reasoning steps automatically.',
			'cotExpandReasoningOnOpenTitle' => 'Expand reasoning when opening',
			'cotExpandToolsOnOpenDescription' => 'When you open a thinking-process block, expand nested tool call details automatically.',
			'cotExpandToolsOnOpenTitle' => 'Expand tools when opening',
			'create' => 'Create',
			'credentialPushConfirmAction' => 'Push credentials',
			'credentialPushConfirmBody' => ({required Object host}) => 'Provider keys will be written to the remote host ${host}. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.',
			'credentialPushConfirmTitle' => 'Push credentials to remote host?',
			'credentialPushOptInSubtitle' => 'Provider keys for remote member authentication.',
			'credentialPushOptInTitle' => 'Push credentials to this machine',
			'dangerZone' => 'Danger zone',
			'defaultModel' => 'Default model',
			'defaultNewChatSessionTitle' => 'New Chat',
			'discoveryAutoRefreshSubtitle' => 'When on, opening discovery pages checks for updates when the cache is older than 24 hours. Manual refresh always updates.',
			'discoveryAutoRefreshTitle' => 'Auto-refresh discovery content',
			'discoverySettingsSubtitle' => 'How skills, plugins and MCP discovery content refreshes.',
			'discoverySettingsTitle' => 'Discovery & Marketplaces',
			'duplicateConversation' => 'Duplicate conversation',
			'emptyTimeline' => 'Local shell-mode conversation notes will appear here.',
			'enabled' => 'Enabled',
			'expertsCatalogAdoption' => 'Added',
			'extensionsEmptyHint' => 'Extensions will appear here once the catalog loads.',
			'extensionsEmptyTitle' => 'No extensions available',
			'extensionsNavInstalled' => 'Installed',
			'extensionsSettingsDescription' => 'Install and enable external tools that augment your agents.',
			'extensionsSettingsTitle' => 'Extensions',
			'filterFiles' => 'Filter files',
			'filterProviders' => 'Filter providers...',
			'forkFromHere' => 'Fork from here',
			'formFieldRequired' => 'This field is required.',
			'hide' => 'Hide',
			'hooksNoInstalled' => 'No hooks',
			'hooksNoInstalledHint' => 'Create a hook to run commands on CLI events.',
			'htmlPreviewErrorBody' => 'The file could not be loaded for preview.',
			'htmlPreviewErrorTitle' => 'Preview unavailable',
			'htmlPreviewOpenBrowser' => 'Open in System Browser',
			'htmlPreviewOpenedInBrowser' => 'Preview opened in your system browser. Use this panel to open it again.',
			'htmlViewToggleEdit' => 'Edit',
			'htmlViewTogglePreview' => 'Preview',
			'injectSessionSshMcpSubtitle' => 'Local and remote seats can run commands and transfer files on this workspace\'s SSH machines via MCP. Reconnect sessions after changing.',
			'injectSessionSshMcpTitle' => 'Inject Session SSH MCP',
			'invalidJson' => 'Invalid JSON. Fix the syntax and try again.',
			'jsonPreview' => 'JSON Preview',
			'language' => 'Language',
			'languageChinese' => '中文',
			'languageDescription' => 'Language used for menus, buttons, and labels.',
			'languageEnglish' => 'English',
			'languageSystem' => 'System',
			'layout' => 'Layout',
			'layoutPageSubtitle' => 'Structure controls are global and apply across teams.',
			'layoutSubtitle' => 'global workbench',
			'mailbox' => 'Mailbox',
			'mailboxEmpty' => 'No messages yet',
			'markdownOpenModeDescription' => 'Default view when opening .md files in the editor. Remember lasts for this app session only.',
			'markdownOpenModePreview' => 'Preview',
			'markdownOpenModeRemember' => 'Remember last',
			'markdownOpenModeSource' => 'Source',
			'markdownOpenModeTitle' => 'Open Markdown as',
			'markdownViewTogglePreview' => 'Preview',
			'markdownViewToggleSource' => 'Source',
			'members' => 'Members',
			'membersAndFileTree' => 'Members and File Tree',
			'membersAndFileTreeDescription' => 'Show members and file tree stacked or as tabs.',
			'membersSubtitle' => 'team agents',
			'missingProvider' => 'Missing provider:',
			'model' => 'Model',
			'modelId' => 'Model ID',
			'modelName' => 'Model alias/name',
			'models' => 'Models',
			'modelsTab' => 'Models',
			'modelsUsingProvider' => ({required int count}) => 'Models using this provider: ${count}',
			'modelsUsingProviderTitle' => 'Models using this provider',
			'name' => 'Name',
			'newSessionTooltip' => 'New session',
			'newWorkspace' => 'New Workspace',
			'newWorkspaceTooltip' => 'Create a workspace',
			'noModelsConfigured' => 'No models configured',
			'noModelsUsingProvider' => 'No models are using this provider.',
			'noSessions' => 'No sessions yet',
			'notes' => 'Notes',
			'notifyOnSessionIdleDescription' => 'When a session finishes a turn and becomes idle, show an OS notification in addition to the in-app notification center.',
			'notifyOnSessionIdleTitle' => 'Agent idle system notification',
			'ok' => 'OK',
			'openExistingSessionStartsTerminalDescription' => 'When enabled, opening a conversation from the sidebar connects the terminal immediately. When off (default), open the Chat view first; send from Chat to start the terminal.',
			'openExistingSessionStartsTerminalTitle' => 'Open existing sessions in terminal',
			'openFolder' => 'Open Folder',
			'openMember' => 'Open member',
			'openRightTools' => 'Tools',
			'openSessionDirectory' => 'Open session folder',
			'openTeam' => 'Open Team',
			'pathCopied' => ({required String path}) => 'Path copied: ${path}',
			'pickPrimaryDirectory' => 'Pick primary directory',
			'pinConversation' => 'Pin conversation',
			'presetPickerNoneOption' => 'None (no default)',
			'presetPickerTitle' => 'Select Preset',
			'progressActivitiesMany' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '1 activity in progress', other: '${count} activities in progress', ), 
			'progressActivitiesPanelTitle' => 'Activities in progress',
			'projectTreeOther' => 'Other',
			'prompt' => 'Prompt',
			'providers' => 'PROVIDERS',
			'providersTab' => 'Providers',
			'proxy' => 'Proxy',
			'proxyOffShort' => 'Proxy off',
			'proxyOnShort' => 'Proxy on',
			'proxyUrl' => 'Proxy URL',
			'rawJsonTab' => 'Raw JSON',
			'reclaimIdleTerminalMinutesDescription' => 'Minutes a terminal may sit idle before it is reclaimed.',
			'reclaimIdleTerminalMinutesTitle' => 'Idle reclaim timeout (minutes)',
			'reclaimIdleTerminalsDescription' => 'Close idle member/session terminals after a timeout to free memory; they reconnect on demand.',
			'reclaimIdleTerminalsTitle' => 'Reclaim idle terminals',
			'referenceConversation' => 'Reference conversation',
			'referenceConversationFailed' => 'Failed to prepare conversation reference',
			'regionVisibility' => 'Region Visibility',
			'removePath' => 'Remove path',
			'removeWorkspaceDirectory' => 'Remove directory',
			'removeWorkspaceMachine' => 'Remove machine',
			'renameConversation' => 'Rename conversation',
			'renameConversationTitle' => 'Rename Conversation',
			'renameProviderName' => 'Rename',
			'renameProviderTitle' => 'Rename provider',
			'replaceKey' => 'Replace key',
			'restoreConversation' => 'Restore',
			'retry' => 'Retry',
			'reveal' => 'Reveal',
			'right' => 'Right',
			'rightTools' => 'Right Tools',
			'rightToolsOpenTabEmpty' => 'All tools are already open.',
			'rightToolsOpenTabSubtitle' => 'Choose a tool to open in the side panel.',
			'rightToolsOpenTabTitle' => 'Open a tab',
			'rightToolsPanelHidden' => 'Hide tools panel',
			'rightToolsPanelVisible' => 'Show tools panel',
			'rootSandboxEnvConfirmAction' => 'Enable',
			'rootSandboxEnvConfirmBody' => ({required Object host}) => 'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on ${host}, keeping --dangerously-skip-permissions. Only enable on machines you trust.',
			'rootSandboxEnvConfirmTitle' => 'Enable root sandbox env?',
			'rootSandboxEnvOptInSubtitle' => 'Keep skip-permissions when Claude runs as root.',
			'rootSandboxEnvOptInTitle' => 'Inject IS_SANDBOX for root',
			'runsPlaceholder' => 'Run history will appear here.',
			'save' => 'Save',
			'saveMember' => 'Save Member',
			'scopeSessionsToSelectedTeamDescription' => 'When enabled, the sidebar shows only sessions assigned to the current team. New sessions are always tagged with the selected team so they appear here if you turn this on later.',
			'scopeSessionsToSelectedTeamTitle' => 'Scope sessions to selected team',
			'selectAgent' => 'Select preset',
			'selectModel' => 'Select a model',
			'selectProvider' => 'Select a provider from the list',
			'selectTeam' => 'Select team',
			'selectionAskAi' => 'Ask AI…',
			'sendPrompt' => 'Send prompt',
			'settings' => 'Settings',
			'settingsPageSubtitle' => 'Manage FlashskyAI team and model settings.',
			'shellChatWorkbench' => 'Shell chat workbench',
			'shellSession' => 'Shell session',
			'sidebarPanelHidden' => 'Hide sidebar',
			'sidebarPanelVisible' => 'Show sidebar',
			'sourceControl' => 'Source Control',
			'stacked' => 'Stacked',
			'stackedTools' => 'Stacked Tools',
			'statEmptyKeys' => 'empty keys',
			'statMissingRefs' => 'missing refs',
			'statModels' => 'models',
			'statProviders' => 'providers',
			'subagentPreviewBack' => 'Back',
			'subagentPreviewEmpty' => 'No subagent content yet',
			'subagentPreviewTitleAgent' => ({required String title}) => '${title}',
			'subagentPreviewUnavailable' => 'Subagent preview is unavailable for this tool call.',
			'summary' => 'Summary',
			'switchToMember' => 'Switch to member',
			'switchWorkspaceTooltip' => 'Switch workspace',
			'tabMenuSplitDown' => 'Split Down',
			'tabMenuSplitRight' => 'Split Right',
			'tabbedTools' => 'Tabbed Tools',
			'tabs' => 'Tabs',
			'teamsCatalogAdoption' => 'Added',
			'thinkingProcessFoldSectionTitle' => 'Fold into thinking process',
			'thinkingProcessSectionTitle' => 'Thinking process',
			'toolchainGit' => 'Git',
			'toolchainGitLabel' => 'Git executable path',
			'toolchainInstallProgressChecking' => ({required String tool}) => 'Checking for ${tool}...',
			'toolchainNode' => 'Node.js',
			'toolchainNodeLabel' => 'Node.js / npm path',
			'toolchainPathDescription' => ({required String tool}) => 'Absolute path to the ${tool} executable. Leave empty to use the one on PATH.',
			'toolchainPathDescriptionSsh' => ({required String tool}) => 'Absolute path to ${tool} on the remote SSH host. Leave empty to auto-discover.',
			'treeCollapseAllFolders' => 'Collapse all folders',
			'treeExpandAllFolders' => 'Expand all folders',
			'type' => 'Type',
			'uiZoomDescription' => 'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.',
			'uiZoomTitle' => 'Interface zoom',
			'unknownFolder' => 'Unknown',
			'unpinConversation' => 'Unpin conversation',
			'validate' => 'Validate',
			'validation' => 'Validation',
			'visibilityBoardHint' => 'Show the task board for mixed-mode teams.',
			'visibilityFileTreeHint' => 'Show the workspace file tree for quick navigation.',
			'visibilityGitHint' => 'Show the source control panel for the current repository.',
			'visibilityMembersHint' => 'Show the member list next to tools or terminals.',
			'visibilityRightToolsHint' => 'Show the right tools panel when opening a session.',
			'visibilityTeamSessionsHint' => 'Show the team sessions list in the left sidebar.',
			'windowControlAlwaysOnTop' => 'Always on top',
			'windowControlClose' => 'Close',
			'windowControlMaximize' => 'Maximize',
			'windowControlMinimize' => 'Minimize',
			'windowControlRestore' => 'Restore',
			'windowsStorageCliMismatchNativeCli' => 'CLI runs in WSL but data is stored in Windows AppData. Config may not match.',
			'windowsStorageCliMismatchWslCli' => 'CLI runs on Windows but data is stored in WSL. Config may not match.',
			'windowsStorageSwitchReloadHint' => 'Reconnect open sessions after switching storage.',
			'workbenchLockGroup' => 'Lock Group',
			'workbenchStripNewMenuTooltip' => 'New',
			'workbenchUnlockGroup' => 'Unlock Group',
			'workflowCardAgents' => ({required int count}) => '${count} agents',
			'workflowCardRunMissing' => 'Workflow run not found for this tool call.',
			'workspaces' => 'Workspaces',
			'acp.chatLaunchFailed' => ({required String cliName}) => 'Couldn\'t start ${cliName}. Make sure the CLI is installed and try again.',
			'acp.chatNotLoggedIn' => 'The agent isn\'t logged in. Sign in under Settings → Providers, then try again.',
			'acp.chatProcessExited' => ({required String cliName}) => '${cliName} exited unexpectedly',
			'acp.chatSessionOpenFailed' => ({required String cliName}) => 'Couldn\'t open the ${cliName} session.',
			'acp.chatTurnFailed' => 'This turn failed',
			'acp.launchFailedAdapter' => 'Could not start the Claude ACP adapter (claude-agent-acp). Install it and try again.',
			'acp.launchFailedVersion' => 'This CLI version does not support ACP chat mode. Update the CLI and try again.',
			'acp.modelSectionAgent' => 'Agent model',
			'acp.modelSectionLaunch' => 'Launch config',
			'acp.modelSwitchFailed' => 'Couldn\'t switch the ACP model. Try again.',
			'acp.permissionAskLabel' => 'Ask',
			'acp.permissionFullAccessLabel' => 'Full access',
			'agent.agent' => 'Agent preset',
			'agent.askAnswerFailed' => 'Couldn\'t submit your answer. Try again or answer in the Terminal.',
			'agent.askAnswerInTerminal' => 'Answer in terminal',
			'agent.askCancelQuestion' => 'Cancel question',
			'agent.askContinue' => 'Continue',
			'agent.askCustomAnswerHint' => 'Enter your answer…',
			'agent.askEscToCancel' => 'Esc to cancel',
			'agent.askIgnore' => 'Ignore',
			'agent.askKeyboardHint' => 'Use Tab / ↑↓ to select, Enter or Space to confirm',
			'agent.askQuestionTabFallback' => ({required int index}) => 'Q${index}',
			'agent.askSubmitAnswers' => 'Submit',
			'agent.askTerminalDisconnected' => 'Terminal is disconnected. Reconnect or answer in the Terminal.',
			'agent.askUserQuestionTitle' => 'Agent is asking you a question',
			'agent.builtInCustom' => 'Custom…',
			'agent.builtInNone' => 'Default',
			'agent.builtInSubtitle' => 'Which agent role this member uses; shapes behavior and capabilities.',
			'agent.claudeTypeHint' => 'e.g. Explore, Plan, or a custom type',
			'agent.claudeTypeSubtitle' => 'Written to the Claude team roster as agentType; leave empty to use the member id.',
			'agent.customIdHint' => 'Custom agent id',
			'agent.flashskyaiPresetSubtitle' => 'Passed as flashskyai --agent; pick a built-in or custom sub-agent.',
			'agent.permissionAlwaysAllowRule' => ({required Object rule}) => 'Always allow ${rule}',
			'agent.permissionAttentionBanner' => 'This agent needs confirmation in the Terminal.',
			'agent.permissionOpenTerminal' => 'Open Terminal',
			'agent.permissionTitle' => ({required String cliName}) => '${cliName} needs your permission',
			'agent.permissionTitleGeneric' => 'Needs your permission',
			'ai.featureCliLabel' => 'CLI',
			'ai.featureCommitMessageSubtitle' => 'Used by the ✨ button in the source control panel.',
			'ai.featureCommitMessageTitle' => 'Commit message generation',
			'ai.featureConfigSummary' => ({required String cli, required String provider, required String model}) => '${cli} · ${provider} · ${model}',
			'ai.featureEffortLabel' => 'Effort',
			'ai.featureModelLabel' => 'Model',
			'ai.featureTeamGenerateSubtitle' => 'Used when generating a team from a description.',
			'ai.featureTeamGenerateTitle' => 'Team configuration generation',
			'ai.features' => 'AI Features',
			'ai.featuresPageSubtitle' => 'Choose which CLI provider, model, and effort each AI feature uses.',
			'ai.messageCancelled' => 'Message cancelled',
			'ai.messageCancelledTool' => 'Cancelled tool',
			'ai.messageCopied' => 'Copied',
			'ai.messageExportMarkdown' => 'Export Markdown',
			'ai.messageIncomplete' => 'Message incomplete',
			'ai.messageReasoning' => 'Reasoning',
			'ai.messageScrollToBottom' => 'Scroll to bottom',
			'ai.messageShowLess' => 'Show less',
			'ai.messageShowMore' => 'Show more',
			'ai.messageThinkingCommands' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'ran 1 command', other: 'ran ${count} commands', ), 
			'ai.messageThinkingEditedFiles' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'edited 1 file', other: 'edited ${count} files', ), 
			'ai.messageThinkingExploredFiles' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'explored 1 file', other: 'explored ${count} files', ), 
			'ai.messageThinkingProcess' => 'Thinking process',
			'ai.messageThinkingProcessStats' => ({required int steps, required int toolCalls}) => 'Thinking process · ${steps} steps · ${toolCalls} tool calls',
			'ai.messageThinkingProcessSteps' => ({required int count}) => 'Thinking process · ${count} steps',
			'ai.messageThinkingProcessSummarySeparator' => ', ',
			'ai.messageThinkingSearches' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '1 search', other: '${count} searches', ), 
			'ai.messageToolResult' => 'Result',
			'ai.messageToolsUsed' => ({required Object count}) => 'Used ${count} tools',
			'ai.messageUsedTool' => 'Used tool',
			'ai.toolFileNotFound' => ({required String path}) => 'Could not find file: ${path}',
			'antigravity.credentialsActionFailed' => 'Antigravity sign-in failed.',
			'antigravity.credentialsCancel' => 'Cancel',
			'antigravity.credentialsDone' => 'Done',
			'antigravity.credentialsLogin' => 'Sign in',
			'antigravity.credentialsLoginExited' => 'Antigravity exited. Close this dialog and start the sign-in again.',
			'antigravity.credentialsLoginFailed' => ({required String error}) => 'Could not start the login terminal: ${error}',
			'antigravity.credentialsLoginIntro' => 'Complete the Google sign-in in the terminal below, then press Done. Antigravity keeps the account in the OS keyring, so the account is shared by all Antigravity sessions and every official Antigravity provider row.',
			'antigravity.credentialsLoginStarting' => 'Starting Antigravity…',
			'antigravity.credentialsLoginTitle' => 'Sign in to Antigravity',
			'antigravity.credentialsLoginVerifyFailed' => 'Antigravity did not confirm the sign-in (agy models failed). Finish the sign-in, then press Done again.',
			'antigravity.credentialsRetry' => 'Retry',
			'antigravity.credentialsSignedIn' => 'Signed in to Antigravity.',
			'app.dropdownSearchHint' => 'Search…',
			'app.dropdownSearchNoResults' => 'No results found.',
			'app.rail' => 'App rail',
			'app.railChat' => 'Chat',
			'app.railConfig' => 'Config',
			'app.railRuns' => 'Runs',
			'app.title' => 'TeamPilot',
			'app.updateAutoCheck' => 'Auto-check for updates',
			'app.updateAutoCheckHint' => 'Check GitHub for a newer version each time the app starts.',
			'app.updateBrowserDownload' => 'Download in browser',
			'app.updateBrowserOpenFailed' => ({required String error}) => 'Failed to open browser: ${error}',
			'app.updateBrowserOpened' => 'Opened download link in the browser',
			'app.updateCannotOpenDownloadLink' => 'Could not open download link',
			'app.updateChangelogDefaultSection' => 'Updates',
			'app.updateChangelogTitle' => 'What\'s new',
			'app.updateCheck' => 'Check for updates',
			'app.updateDialogTitle' => 'New version available',
			'app.updateDownloadComplete' => 'Download complete',
			'app.updateDownloadError' => ({required String error}) => 'Error while downloading: ${error}',
			'app.updateDownloadFailed' => 'Download failed',
			'app.updateDownloadInBackground' => 'Download in background',
			'app.updateDownloadInstall' => 'Download and install',
			'app.updateDownloadNow' => 'Download now',
			'app.updateDownloadStarting' => 'Starting download…',
			'app.updateDownloading' => 'Downloading update…',
			'app.updateInstallComplete' => 'Installation complete',
			'app.updateInstallFailed' => ({required String message}) => 'Install failed: ${message}',
			'app.updateInstallNoResult' => 'Install returned no result',
			'app.updateInstallNow' => 'Install now',
			'app.updateInstalling' => 'Installing update…',
			'app.updateInvalidPackagePath' => 'Invalid package path',
			'app.updateLater' => 'Later',
			'app.updateLatestVersion' => 'Latest version',
			'app.updateNewVersion' => ({required String version}) => 'Version ${version} available',
			'app.updatePackagePlatformMismatch' => 'Package type does not match this system',
			'app.updateReadyToDownload' => 'Ready to download',
			'app.updateRedirectBrowserOnly' => 'This link must be downloaded in the browser',
			'app.updateReleaseBuildRequired' => 'Use a release build for in-app installation',
			'app.updateResolvingDownloadUrl' => 'Resolving download link…',
			'app.updateSkipVersion' => 'Skip this version',
			'app.updateUnknownVersion' => 'Unknown',
			'app.updateUpToDate' => 'You are on the latest version.',
			'app.updateViewRelease' => 'View release on GitHub',
			'app.updateViewReleases' => 'Releases',
			'appProvider.advancedJson' => 'Advanced JSON editor',
			'appProvider.advancedOptions' => 'Advanced options',
			'appProvider.apiKeyEditHint' => 'Leave blank to keep the existing key',
			'appProvider.catalogHint' => 'TeamPilot stores unified providers here; team launches generate per-tool configs.',
			'appProvider.catalogLabel' => 'App provider catalog',
			'appProvider.claudeAuthApiKey' => 'ANTHROPIC_API_KEY',
			'appProvider.claudeAuthField' => 'Authentication field',
			'appProvider.claudeAuthFieldHint' => 'Select the authentication environment variable written to settings.',
			'appProvider.claudeAuthTokenDefault' => 'ANTHROPIC_AUTH_TOKEN (default)',
			'appProvider.claudeCredentialBinding' => 'OAuth credential source',
			'appProvider.claudeCredentialBindingIsolated' => 'Isolated copy (TeamPilot only)',
			'appProvider.claudeCredentialBindingIsolatedHint' => 'Keeps a separate credential copy under TeamPilot. Use when this provider must not share login with global Claude Code.',
			'appProvider.claudeCredentialBindingLinked' => 'Follow global (~/.claude)',
			'appProvider.claudeCredentialBindingLinkedHint' => 'Shares the same OAuth session as Claude Code in your terminal. Refreshes stay in sync.',
			'appProvider.credentialLinkEmpty' => 'No secret-backed balance entries yet',
			'appProvider.credentialLinkMode' => 'API key source',
			'appProvider.credentialLinkOwnKey' => 'Use own API key',
			'appProvider.credentialLinkedTo' => ({required Object entry}) => 'Using secret of ${entry}',
			'appProvider.displayName' => 'Display name',
			'appProvider.enabledTools' => 'Enabled tools',
			'appProvider.import' => 'Import',
			'appProvider.importNothing' => 'No providers found to import.',
			'appProvider.importSuccess' => ({required int count, required int mirrored, required int skipped}) => 'Imported ${count} providers. Mirrored ${mirrored} to FlashskyAI, skipped ${skipped} existing.',
			'appProvider.internalIdPreview' => ({required String id}) => 'Internal id: ${id}',
			'appProvider.modelEnterCustom' => 'Enter custom model ID',
			'appProvider.modelPickFromList' => 'Choose from list',
			'appProvider.opencodeSubscription' => 'Subscription',
			'appProvider.opencodeSubscriptionOff' => 'Free models only. Bind OpenCode Go to use subscription models.',
			'appProvider.opencodeSubscriptionOn' => 'OpenCode Go bound — subscription and free models are both available.',
			'appProvider.presetCustom' => 'Custom',
			'appProvider.presetLabel' => 'Preset',
			'appProvider.teamNone' => 'None',
			'appProvider.teamToolSection' => 'Tool providers for this team',
			'appProvider.teamToolSubtitle' => 'Select which unified provider each tool uses when this team starts.',
			'appProvider.toolAntigravity' => 'Antigravity',
			'appProvider.toolClaude' => 'Claude Code',
			'appProvider.toolCodebuddy' => 'CodeBuddy',
			'appProvider.toolCodex' => 'Codex',
			'appProvider.toolCursor' => 'Cursor',
			'appProvider.toolFlashskyai' => 'FlashskyAI',
			'appProvider.toolGemini' => 'Gemini CLI',
			'appProvider.toolOpencode' => 'OpenCode',
			'appProvider.toolQoder' => 'Qoder',
			'appProvider.toolQoderCn' => 'Qoder CN',
			'appProvider.website' => 'Website',
			'appProvider.toolGrok' => 'Grok CLI',
			'automations.boundSession' => 'Bound session',
			'automations.boundSessionPending' => 'A session is bound after the first run',
			'automations.boundSessionUnavailable' => 'Session unavailable — switch or unbind',
			'automations.catchUpOnce' => 'Catch up once after startup',
			'automations.cli' => 'CLI',
			'automations.command' => 'Command',
			'automations.commandHelp' => 'Runs only while TeamPilot is running. Missed runs older than the grace window are skipped unless catch-up is on.',
			'automations.commandRequired' => 'Command is required',
			'automations.commandTimeout' => 'Timeout (seconds)',
			'automations.commandTimeoutInvalid' => 'Timeout must be a whole number of seconds',
			'automations.commandTimeoutRange' => 'Timeout must be between 30 and 1800 seconds',
			'automations.commandTooLong' => 'Command must be at most 2000 characters',
			'automations.commandWorkingDirectory' => 'Working directory',
			'automations.commandWorkingDirectoryMain' => 'Workspace default folder',
			'automations.compactTitle' => 'Scheduled message',
			'automations.countdownCustom' => 'Custom',
			'automations.countdownHours' => ({required int hours}) => '${hours} h',
			'automations.countdownMinutes' => ({required int minutes}) => '${minutes} min',
			'automations.countdownPreview' => ({required String dateTime}) => 'Runs at ${dateTime}',
			'automations.createTitle' => 'New automation',
			'automations.customCron' => 'Cron expression',
			'automations.dayFriday' => 'Friday',
			'automations.dayMonday' => 'Monday',
			'automations.daySaturday' => 'Saturday',
			'automations.daySunday' => 'Sunday',
			'automations.dayThursday' => 'Thursday',
			'automations.dayTuesday' => 'Tuesday',
			'automations.dayWednesday' => 'Wednesday',
			'automations.delete' => 'Delete',
			'automations.deleteConfirm' => 'Delete this automation?',
			'automations.dispatchFailed' => 'Dispatch failed',
			'automations.edit' => 'Edit',
			'automations.editTitle' => 'Edit automation',
			'automations.empty' => 'No automations yet',
			'automations.enabled' => 'Enabled',
			'automations.exitCode' => ({required int code}) => 'Exit code ${code}',
			'automations.filterActionAll' => 'All actions',
			'automations.filterActionLabel' => 'Action type',
			'automations.filterAll' => 'All',
			'automations.filterDisabled' => 'Disabled only',
			'automations.filterEnabled' => 'Enabled only',
			'automations.filterLaunchPrompt' => 'Launch prompts',
			'automations.filterScheduledMessage' => 'Scheduled messages',
			'automations.filterStatusLabel' => 'Status',
			'automations.hideFilter' => 'Hide filters',
			'automations.invalidCron' => 'Invalid cron expression (5 fields required)',
			'automations.invalidMaxRunCount' => 'Run limit must be a positive number',
			'automations.invalidTime' => 'Time must be HH:mm',
			'automations.launchMode' => 'Conversation mode',
			'automations.launchProfile' => 'Launch identity',
			'automations.launchProject' => 'Project',
			'automations.launchWorktree' => 'Worktree',
			'automations.manageAll' => 'Manage all scheduled tasks',
			'automations.manageSessionContextMenu' => 'Manage scheduled messages',
			'automations.maxRunCount' => 'Run limit',
			'automations.maxRunCountHint' => 'Leave empty for unlimited',
			'automations.message' => 'Message',
			_ => null,
		} ?? switch (path) {
			'automations.name' => 'Name',
			'automations.kNew' => 'New automation',
			'automations.nextRun' => ({required String time}) => 'Next run: ${time}',
			'automations.nextRunNone' => 'No upcoming run',
			'automations.presetCliMismatch' => 'The selected preset does not match the bound session\'s CLI.',
			'automations.presetEmptyForCli' => 'No presets available for this CLI.',
			'automations.presetScopeHint' => 'Bound to a session — only presets for that session\'s CLI are shown.',
			'automations.reuseSession' => 'Reuse session',
			'automations.reuseSessionListHint' => ({required String sessionId}) => 'Reuses conversation ${sessionId}',
			'automations.reuseSessionSubtitleBound' => ({required String sessionId}) => 'Bound to session ${sessionId}',
			'automations.reuseSessionSubtitleOff' => 'Each run opens a new conversation.',
			'automations.reuseSessionSubtitlePending' => 'First run creates a conversation; later runs reuse it.',
			'automations.runCountLimited' => ({required int count, required int max}) => 'Ran ${count} / ${max}',
			'automations.runCountUnlimited' => ({required int count}) => 'Ran ${count} times',
			'automations.runDurationMilliseconds' => ({required int milliseconds}) => 'Took ${milliseconds} ms',
			'automations.runDurationSeconds' => ({required int seconds}) => 'Took ${seconds}s',
			'automations.runError' => ({required String error}) => 'Error: ${error}',
			'automations.runHistory' => 'Run history',
			'automations.runHistoryEmpty' => 'No runs yet',
			'automations.runNow' => 'Run now',
			'automations.runOutputTruncated' => 'Output truncated',
			'automations.runStatusCompleted' => 'Completed',
			'automations.runStatusDispatched' => 'Dispatched',
			'automations.runStatusDispatching' => 'Dispatching',
			'automations.runStatusFailed' => 'Failed',
			'automations.runStatusPending' => 'Pending',
			'automations.runStatusSkippedMissed' => 'Skipped — missed window',
			'automations.runStatusSkippedOverlap' => 'Skipped (still running)',
			'automations.runStatusTimedOut' => 'Timed out',
			'automations.runStderr' => 'stderr',
			'automations.runStdout' => 'stdout',
			'automations.schedule' => 'Schedule',
			'automations.scheduleCustom' => 'Custom cron',
			'automations.scheduleDaily' => 'Daily',
			'automations.scheduleDate' => 'Date',
			'automations.scheduleHourly' => 'Hourly',
			'automations.scheduleModeCountdown' => 'Countdown',
			'automations.scheduleModeOnce' => 'Once',
			'automations.scheduleModeRecurring' => 'Recurring',
			'automations.scheduleOnce' => 'Once',
			'automations.schedulePastTime' => 'Choose a time in the future',
			'automations.scheduleSummaryDaily' => ({required String time}) => 'Daily at ${time}',
			'automations.scheduleSummaryHourly' => ({required int minute}) => 'Hourly at :${minute}',
			'automations.scheduleSummaryOnce' => ({required String time}) => 'Once at ${time}',
			'automations.scheduleSummaryWeekdays' => ({required String time}) => 'Weekdays at ${time}',
			'automations.scheduleSummaryWeekly' => ({required String day, required String time}) => 'Weekly on ${day} at ${time}',
			'automations.scheduleType' => 'Type',
			'automations.scheduleWeekdays' => 'Weekdays',
			'automations.scheduleWeekly' => 'Weekly',
			'automations.scopeModePersonal' => ({required String profile}) => 'Personal · ${profile}',
			'automations.scopeModeTeam' => ({required String team}) => 'Team · ${team}',
			'automations.scopePersonal' => ({required String preset}) => 'Personal · ${preset}',
			'automations.scopeScheduledMessage' => ({required String sessionId}) => 'Scheduled message · ${sessionId}',
			'automations.scopeTeam' => ({required String team, required String member}) => 'Team · ${team} · ${member}',
			'automations.scopeTeamMember' => ({required String member}) => 'Team · ${member}',
			'automations.sessionContextMenu' => 'Scheduled message…',
			'automations.sessionDefaultName' => ({required String title}) => '${title} — scheduled message',
			'automations.sessionPickerEmpty' => 'No sessions available to bind',
			'automations.sessionPickerTitle' => 'Select a session',
			'automations.sessionTitle' => 'Session title',
			'automations.sessionTitleHint' => 'Leave empty to use the automation name.',
			'automations.showFilter' => 'Show filters',
			'automations.sidebarTitle' => 'Scheduled tasks',
			'automations.skippedUnavailable' => 'Skipped — session unavailable',
			'automations.sort' => 'Sort automations',
			'automations.sortNameAsc' => 'Name (A–Z)',
			'automations.sortNameDesc' => 'Name (Z–A)',
			'automations.sortNextRun' => 'Next run',
			'automations.sortRecentlyUpdated' => 'Recently updated',
			'automations.statusBarEmpty' => 'No active scheduled tasks',
			'automations.subtitle' => 'Schedule messages and prompts across workspaces and sessions.',
			'automations.switchSession' => 'Switch session',
			'automations.targetMember' => 'Target member',
			'automations.time' => 'Time',
			'automations.title' => 'Automations',
			'automations.unbindSession' => 'Unbind',
			'automations.validationRequired' => 'Name and message are required',
			'catalog.cardAccessibilityLabel' => ({required String name, required String source}) => '${name}, from ${source}',
			'catalog.metricMissing' => 'No data',
			'catalog.metricMissingTooltip' => 'No data available',
			'catalog.metricName' => 'Name',
			'catalog.metricPublished' => 'Published',
			'catalog.metricRating' => 'Rating',
			'catalog.metricUpdated' => 'Updated',
			'catalog.missingMetricAccessibilityLabel' => ({required String label}) => '${label}: no data available',
			'catalog.refreshAccessibilityLabel' => 'Refresh catalog',
			'catalog.sortAccessibilityLabel' => 'Sort catalog entries',
			'catalog.sortAdoption' => 'Most adopted',
			'catalog.sortName' => 'Name',
			'catalog.sortPublished' => 'Recently published',
			'catalog.sortRating' => 'Highest rated',
			'catalog.sortUpdated' => 'Recently updated',
			'catalog.sourceWarningAccessibilityLabel' => ({required int count}) => '${count} catalog source(s) failed to load',
			'catalog.sourceWarningEntry' => ({required String source, required String error}) => '${source}: ${error}',
			'catalog.sourceWarningLabel' => 'Some catalog sources failed to load',
			'chat.codeBlockModeDescription' => 'How oversized code blocks render in chat.',
			'chat.codeBlockModeTitle' => 'Code blocks in chat',
			'chat.findClose' => 'Close find',
			'chat.findHint' => 'Find in conversation',
			'chat.findMatchCase' => 'Match case',
			'chat.findNext' => 'Next match',
			'chat.findNoResults' => 'No matches',
			'chat.findPrevious' => 'Previous match',
			'chat.findResults' => 'Matches',
			'chat.findUseRegex' => 'Use regular expression',
			'chat.findWholeWord' => 'Match whole word',
			'chat.hintText' => 'Write a prompt for team-lead...',
			'chat.submitSwitchesToTerminalDescription' => 'When off (default), sending from Chat (new conversation or continue) stays on the Chat view while the terminal runs in the background. When on, switch to the Terminal after send.',
			'chat.submitSwitchesToTerminalTitle' => 'Switch to Terminal after Chat send',
			'chat.to' => 'To:',
			'chat.userMessageModeDescription' => 'How oversized user messages render in chat.',
			'chat.userMessageModeTitle' => 'User messages',
			'chat.userMessageRailEmptyPreview' => 'Empty message',
			'chat.userMessageRailSemanticLabel' => ({required int index, required int total}) => 'User message ${index} of ${total}',
			'claude.cliExecutablePathDescription' => 'Absolute path to the Claude Code executable. Leave empty to use the one on PATH.',
			'claude.cliExecutablePathDescriptionSsh' => 'Absolute path to Claude Code on the remote SSH host. Leave empty to resolve claude from the remote PATH.',
			'claude.cliExecutablePathLabel' => 'Claude Code CLI path',
			'claude.launchCredentialsMissingWarning' => 'Claude Official credentials are missing for this team provider. Sign in from Providers settings.',
			'claude.officialCredentialsActionFailed' => 'Could not update credentials',
			'claude.officialCredentialsActionSuccess' => 'Credentials updated',
			'claude.officialCredentialsImportFile' => 'Import file…',
			'claude.officialCredentialsImportGlobal' => 'Import from ~/.claude',
			'claude.officialCredentialsLogin' => 'Sign in with Claude',
			'claude.officialCredentialsMissing' => 'No credentials saved for this provider',
			'claude.officialCredentialsReady' => 'Credentials ready',
			'claude.officialCredentialsRevoke' => 'Sign out',
			'claude.officialCredentialsRevokeConfirm' => ({required String name}) => 'Sign out and remove saved credentials for ${name}?',
			'claude.officialCredentialsTitle' => 'Claude Official login',
			'cli.config' => 'CLI',
			'cli.configAiCliGroup' => 'AI CLI',
			'cli.configPageSubtitle' => 'Configure AI agent CLI executable paths and install missing tools.',
			'cli.configToolchainGroup' => 'Toolchain',
			'cli.cursorExecutablePathLabel' => 'Cursor CLI path',
			'cli.executablePathApply' => 'Apply',
			'cli.executablePathBrowse' => 'Browse…',
			'cli.executablePathDescription' => 'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.',
			'cli.executablePathDescriptionFor' => ({required String cli}) => 'Absolute path to the ${cli} executable. Leave empty to use the one on PATH.',
			'cli.executablePathDescriptionSsh' => 'Absolute path to flashskyai on the remote SSH host. Leave empty to auto-discover over SSH.',
			'cli.executablePathDescriptionSshFor' => ({required String cli}) => 'Absolute path to ${cli} on the remote SSH host. Leave empty to auto-discover over SSH.',
			'cli.executablePathLabel' => 'flashskyai CLI path',
			'cli.executablePathLabelFor' => ({required String cli}) => '${cli} CLI path',
			'cli.executablePathLocate' => 'Locate',
			'cli.executablePathLocateFailed' => ({required String name}) => 'Could not find ${name} on PATH.',
			'cli.executablePathLocateRemoteUnsupported' => 'Remote locate is not supported for this tool.',
			'cli.executablePathLocateSuccess' => ({required String name, required String path}) => 'Located ${name} at ${path}.',
			'cli.executablePathReset' => 'Reset',
			'cli.executablePathUsing' => 'Using: ',
			'cli.executablePathUsingFallback' => 'Using PATH lookup',
			'cli.installButton' => 'Install',
			'cli.installInstalling' => 'Installing…',
			'cli.installProgressBootstrappingNode' => 'Installing Node.js…',
			'cli.installProgressCheckingNpm' => 'Checking for npm…',
			'cli.installProgressDownloading' => 'Downloading adapter…',
			'cli.installProgressExtracting' => 'Extracting adapter…',
			'cli.installProgressInstallingCli' => 'Installing CLI…',
			'cli.installProgressLocatingExecutable' => 'Locating CLI executable…',
			'cli.installProgressSyncingRemoteWorkspace' => 'Syncing remote workspace…',
			'cli.installUpgrading' => 'Upgrading…',
			'cli.readinessAdapterMissing' => 'adapter not found',
			'cli.readinessNeedsSetup' => 'Needs setup',
			'cli.readinessReady' => 'Ready',
			'cli.readinessRowAcp' => 'ACP',
			'cli.readinessRowCli' => 'CLI',
			'cli.readinessUpdateAvailable' => 'Update available',
			'cli.readinessUsesCli' => 'uses CLI · acp',
			'cli.readinessVersionUnknown' => '—',
			'cli.taskBoardCount' => ({required int completed, required int total}) => '${completed}/${total}',
			'cli.taskBoardMore' => ({required int count}) => '… +${count} more',
			'cli.taskBoardShowLess' => 'Show less',
			'cli.taskBoardTitle' => 'Tasks',
			'cli.taskStatusCancelled' => 'Cancelled',
			'cli.taskStatusCompleted' => 'Done',
			'cli.taskStatusInProgress' => 'In progress',
			'cli.taskStatusPending' => 'Pending',
			'cli.taskStatusUnknown' => 'Unknown',
			'cli.transportDefaultChat' => 'New sessions default to chat (ACP)',
			'cli.transportDefaultTerminal' => 'New sessions default to the terminal (PTY)',
			'cli.upgradeButton' => 'Upgrade',
			'cli.acpProxyTitle' => 'Cloud keep-alive',
			'cli.acpProxySubtitle' => 'Keeps a cloud-model turn running after this device disconnects. Install and start it on this machine. Sending a message does not install it.',
			'cli.acpProxyStart' => 'Start',
			'cli.acpProxyChecking' => 'Checking the remote machine…',
			'cli.acpProxyMissing' => 'Not installed',
			'cli.acpProxyStopped' => 'Installed, not running',
			'cli.acpProxyOutdated' => 'Update available',
			'cli.acpProxyRetry' => 'Retry',
			'cli.acpProxyNoSsh' => 'Select an SSH server before installing keep-alive.',
			'clone.repositoryAddToExistingSucceeded' => ({required Object repo, required Object workspace}) => 'Added ${repo} to workspace ${workspace}',
			'clone.repositoryAddToWorkspace' => 'Add to existing workspace…',
			'clone.repositoryCancelled' => ({required Object repo}) => 'Clone cancelled: ${repo}',
			'clone.repositoryChooseWorkspace' => 'Choose a workspace',
			'clone.repositoryCompletedBody' => ({required Object path}) => '${path} is ready.',
			'clone.repositoryCompletedTitle' => 'Clone complete',
			'clone.repositoryCreateWorkspace' => 'New workspace',
			'clone.repositoryDestExists' => 'Folder already exists and is not empty',
			'clone.repositoryDirNameLabel' => 'Folder name',
			'clone.repositoryDirNameRequired' => 'Enter a folder name',
			'clone.repositoryFailed' => ({required Object repo}) => 'Clone failed: ${repo}',
			'clone.repositoryGitMissing' => 'git was not found on the selected target machine',
			'clone.repositoryMenu' => 'Clone Repository…',
			'clone.repositoryParentDirLabel' => 'Clone into folder',
			'clone.repositoryParentDirRequired' => 'Choose a destination folder',
			'clone.repositoryProgressTitle' => ({required Object repo}) => 'Cloning ${repo}',
			'clone.repositoryStarted' => ({required Object url}) => 'Cloning ${url} started',
			'clone.repositorySubmit' => 'Clone',
			'clone.repositorySucceeded' => ({required Object repo}) => 'Cloned ${repo}',
			'clone.repositoryTargetLabel' => 'Clone to target',
			'clone.repositoryTitle' => 'Clone Repository',
			'clone.repositoryUrlHint' => 'https://github.com/owner/repo.git',
			'clone.repositoryUrlInvalid' => 'Enter a valid git URL (https://, git@, git://, ssh://)',
			'clone.repositoryUrlLabel' => 'Repository URL',
			'codebuddy.credentialsActionFailed' => 'CodeBuddy sign-in failed.',
			'codebuddy.credentialsCancel' => 'Cancel',
			'codebuddy.credentialsDone' => 'Done',
			'codebuddy.credentialsLogin' => 'Sign in',
			'codebuddy.credentialsLoginExited' => 'CodeBuddy exited. Close this dialog and start the sign-in again.',
			'codebuddy.credentialsLoginFailed' => ({required String error}) => 'Could not start the login terminal: ${error}',
			'codebuddy.credentialsLoginIntro' => 'Complete the sign-in in the terminal below. If a login-method list appears, choose one first (e.g. WeChat / enterprise domain). The CLI may open a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.',
			'codebuddy.credentialsLoginStarting' => 'Starting CodeBuddy…',
			'codebuddy.credentialsLoginTitle' => 'Sign in to CodeBuddy',
			'codebuddy.credentialsRetry' => 'Retry',
			'codebuddy.credentialsSendLogin' => 'Send /login',
			'codebuddy.credentialsSignedIn' => 'Signed in to CodeBuddy.',
			'codex.acpChatNotLoggedIn' => 'Codex isn\'t logged in. Sign in with ChatGPT under Settings → Providers, or switch to an API key.',
			'codex.acpLaunchFailedAdapter' => 'Could not start the Codex ACP adapter (codex-acp). Install it and try again.',
			'codex.credentialsActionFailed' => 'Could not update credentials',
			'codex.credentialsActionSuccess' => 'Credentials updated',
			'codex.credentialsImportFile' => 'Import auth.json…',
			'codex.credentialsImportGlobal' => 'Import from ~/.codex',
			'codex.credentialsLogin' => 'Sign in with OpenAI',
			'codex.credentialsRevoke' => 'Sign out',
			'codex.credentialsRevokeConfirm' => ({required String name}) => 'Sign out and remove saved credentials for ${name}?',
			'compose.cascadeCustomModelId' => 'Custom model ID…',
			'compose.cascadeCustomModelIdTitle' => 'Custom model ID',
			'compose.cascadeDefaultEffort' => 'Default',
			'compose.cascadeNoModels' => 'No model catalog',
			'compose.cascadeNoProviders' => 'No providers configured',
			'compose.cascadePresets' => 'Presets',
			'compose.cascadeSavePreset' => 'Save current as preset…',
			'compose.commandExperimental' => 'Experimental',
			'compose.commandNative' => 'Native',
			'compose.commandPlugin' => 'Plugin',
			'compose.nativeCommandCompact' => 'Compact the active conversation context.',
			'compose.nativeCommandGoal' => 'Keep a durable objective for long-running work.',
			'compose.nativeCommandHelp' => 'Show commands available in this CLI session.',
			'compose.nativeCommandPlan' => 'Switch the session into a planning workflow.',
			'compose.pasteClipEdit' => 'Edit pasted text',
			'compose.pasteClipLabel' => 'Pasted text',
			'compose.pasteClipLines' => ({required int lines}) => '${lines} lines',
			'compose.pasteClipRemove' => 'Remove pasted text',
			'compose.pasteEditorDone' => 'Done',
			'compose.pasteEditorRemove' => 'Remove',
			'compose.pasteEditorTitle' => ({required int lines}) => 'Edit pasted text · ${lines} lines',
			'connect.addEndpoint' => 'Add address',
			'connect.advancedSubtitle' => 'Add SSH addresses that are reachable outside this LAN.',
			'connect.advancedTitle' => 'Reachability',
			'connect.androidScanHint' => 'Scan a QR from desktop TeamPilot.',
			'connect.copyLink' => 'Copy link',
			'connect.error' => 'Connect could not refresh pairing. Try again.',
			'connect.extraHost' => 'Host',
			'connect.extraPort' => 'Port',
			'connect.interfaceLabel' => 'Network interface',
			'connect.invalidEndpoint' => 'Every address needs a host and a port from 1 to 65535.',
			'connect.lanOnlyStatus' => 'LAN only',
			'connect.needLanOrRelay' => 'Join the same Wi-Fi as this computer, or set a relay on the desktop first.',
			'connect.noNetworkAddress' => 'No non-loopback IPv4 network interface is available.',
			'connect.noPairedDevices' => 'No phones are paired yet.',
			'connect.openSettings' => 'Open settings',
			'connect.pairCodeHint' => 'teampilot://pair-ssh?code=…',
			'connect.pairExpired' => 'Code expired. Scan again.',
			'connect.pairFailed' => 'Could not pair with this desktop. Try again.',
			'connect.pairInvalid' => 'This pairing code is invalid.',
			'connect.pairNow' => 'Pair',
			'connect.pairSheetSubtitle' => 'Scan the QR shown by desktop TeamPilot, or paste its pairing code.',
			'connect.pairSheetTitle' => 'Pair with a desktop',
			'connect.pairUpdateApp' => 'Update TeamPilot to scan this code.',
			'connect.pairedDevicesTitle' => 'Paired devices',
			'connect.pairing' => 'Pairing…',
			'connect.pasteCode' => 'Paste code',
			'connect.qrEnlargeHint' => 'Tap the QR code to enlarge it for easier scanning.',
			'connect.regenerate' => 'Regenerate',
			'connect.relayUrl' => 'Relay URL',
			'connect.relayUrlHint' => 'Optional relay service URL',
			'connect.remoteReadyStatus' => 'LAN and remote',
			'connect.removeEndpoint' => 'Remove address',
			'connect.repairHint' => 'The desktop has been upgraded — re-scan its pairing code to reconnect.',
			'connect.revokeDevice' => 'Revoke',
			'connect.revokeSystemHint' => 'New logins are blocked. Already-open OpenSSH sessions may stay connected until they disconnect.',
			'connect.saveSettings' => 'Save reachability',
			'connect.scanHint' => 'Scan this code in TeamPilot on your phone.',
			'connect.scanQr' => 'Scan QR',
			'connect.scannerHint' => 'Hold 10–30 cm from the desktop QR. Pinch to zoom; use the flashlight in dim light.',
			'connect.scannerPermissionDenied' => 'Camera permission is required to scan QR codes.',
			'connect.scannerUnavailable' => 'The camera scanner is unavailable. Paste the code instead.',
			'connect.settingsSubtitle' => 'Pair a phone over SSH',
			'connect.settingsTitle' => 'Phone',
			'connect.sshBackendEmbedded' => 'Embedded',
			'connect.sshBackendHelp' => 'Compare the built-in server with this computer\'s OpenSSH. Switching requires re-scanning the pairing code.',
			'connect.sshBackendLabel' => 'SSH server',
			'connect.sshBackendRePair' => 'Paired phones must re-scan this computer\'s pairing code.',
			'connect.sshBackendSystem' => 'System OpenSSH (22)',
			'connect.sshdDown' => 'The embedded connection server failed to start. Retry or restart the app.',
			'connect.sshdRetry' => 'Retry',
			'connect.systemSshdDownLinux' => 'No SSH server is listening on port 22. Start the OpenSSH sshd service, then retry.',
			'connect.systemSshdDownMacos' => 'No SSH server is listening on port 22. Enable Remote Login in Sharing settings, then retry.',
			'cursor.accountUsageSession' => 'Cursor accounts',
			'cursor.credentialsActionFailed' => 'Could not update credentials',
			'cursor.credentialsActionSuccess' => 'Credentials updated',
			'cursor.credentialsImportFile' => 'Import directory…',
			'cursor.credentialsImportGlobal' => 'Import from ~/.cursor',
			'cursor.credentialsLogin' => 'Sign in with Cursor',
			'cursor.credentialsRevoke' => 'Sign out',
			'cursor.credentialsRevokeConfirm' => ({required String name}) => 'Sign out and remove saved credentials for ${name}?',
			'delete.delete' => 'Delete',
			'delete.conversation' => 'Delete conversation',
			'delete.conversationConfirm' => ({required String name}) => 'Delete conversation "${name}"? This cannot be undone.',
			'delete.provider' => 'Delete Provider',
			'delete.providerConfirm' => ({required String name}) => 'Delete provider ${name}?',
			'delete.providerTooltip' => 'Delete provider',
			'delete.providerWithCredentialsConfirm' => ({required String name}) => 'Delete provider ${name}? Saved Claude login credentials for this provider will also be removed.',
			'delete.team' => 'Delete team',
			'delete.teamConfirm' => ({required String name}) => 'Delete team "${name}"? This cannot be undone.',
			'delete.teamSubtitle' => 'Removes this team from the UI and the shared flashskyai data directory. This cannot be undone.',
			'delete.workspace' => 'Delete Workspace',
			'delete.workspaceConfirm' => ({required String name}) => 'Delete workspace "${name}" and all its sessions? This cannot be undone.',
			'delete.workspaceSubtitle' => 'Deletes this workspace and all conversations in it. This cannot be undone.',
			'diff.applyDisabledNoPath' => 'Cannot apply: file path unavailable',
			'diff.applyFailed' => ({required String error}) => 'Could not apply change: ${error}',
			'diff.applyHunkTooltip' => 'Apply change to working tree',
			'diff.changeCounter' => ({required int current, required int total}) => '${current} / ${total}',
			'diff.discardDiffBeforeFileSaveBody' => 'Saving the file will discard unsaved edits in the diff view.',
			'diff.discardDiffBeforeFileSaveTitle' => 'Discard diff edits?',
			'diff.discardEditsApplyBody' => 'Applying this change discards unsaved edits in the diff.',
			'diff.discardEditsApplyTitle' => 'Discard edits?',
			'diff.fileReloadedAfterDiffWrite' => 'File tab reloaded from disk.',
			'diff.ignoreWhitespace' => 'Ignore whitespace',
			'diff.nextChange' => 'Next change',
			'diff.noChanges' => 'No changes',
			'diff.openSourceFile' => 'Open source file',
			'diff.previousChange' => 'Previous change',
			'diff.reloadAfterSaveFailed' => 'Saved, but refreshing the diff failed.',
			'diff.saveFailed' => ({required String error}) => 'Could not save: ${error}',
			'diff.showAllLines' => 'Show all lines',
			'diff.viewSideBySide' => 'Side by side',
			'diff.viewUnified' => 'Unified',
			'download.sourcesEnabledSources' => 'Enabled sources',
			'download.sourcesIdentity' => 'identity (official)',
			'download.sourcesMirrorBaseUrl' => 'Mirror base URL',
			'download.sourcesMirrorHint' => 'https://mirror.example',
			'download.sourcesRestoreDefaults' => 'Restore defaults',
			'download.sourcesSave' => 'Save',
			'download.sourcesSettingsSubtitle' => 'Configure mirrors for GitHub downloads (app updates, Termux APK)',
			'download.sourcesSettingsTitle' => 'Download sources',
			'edit.cancel' => 'Cancel',
			'edit.edit' => 'Edit',
			'edit.memberSubtitle' => 'Edit provider, model, optional agent preset, and command arguments.',
			'edit.modelTitle' => ({required String name}) => 'Edit ${name}',
			'edit.provider' => 'Edit provider',
			'edit.retry' => 'Retry',
			'edit.send' => 'Send',
			'edit.teamSubtitle' => 'Edit team identity, working directory, and launch order.',
			'edit.userMessage' => 'Edit message',
			'edit.workspacePrimaryPath' => 'Edit primary directory',
			'editor.binaryFileHint' => 'Binary files open with the system default app.',
			'editor.close' => 'Close editor',
			'editor.copy' => 'Copy',
			'editor.copyAsAiContext' => 'Copy as AI context',
			'editor.couldNotReadFile' => 'Could not read file',
			'editor.cut' => 'Cut',
			'editor.discard' => 'Discard',
			'editor.fileNotFound' => 'File not found',
			'editor.fileReadOnly' => 'File is read-only',
			'editor.fileTooLarge' => 'File is too large to edit in TeamPilot (max 2 MB).',
			'editor.findClose' => 'Close',
			'editor.findHint' => 'Find',
			'editor.findInSelection' => 'Find in selection',
			'editor.findInvalidRegex' => 'Invalid regular expression',
			'editor.findMatchCase' => 'Match case',
			'editor.findNext' => 'Next match',
			'editor.findNoResults' => 'No matches',
			'editor.findPrevious' => 'Previous match',
			'editor.findReplaceAll' => 'Replace all',
			'editor.findReplaceHint' => 'Replace',
			'editor.findReplaceOne' => 'Replace',
			'editor.findReplacePreserveCase' => 'Preserve case',
			'editor.findToggleReplace' => 'Toggle replace',
			'editor.findUseRegex' => 'Use regular expression',
			'editor.findWholeWord' => 'Match whole word',
			'editor.imageDecodeFailed' => 'Could not decode this image.',
			'editor.imageTooLarge' => 'Image is too large to preview in TeamPilot (max 25 MB).',
			'editor.noFileOpen' => 'No file open',
			'editor.notReady' => 'Editor not ready',
			'editor.paste' => 'Paste',
			'editor.redoEdit' => 'Redo',
			'editor.revertChanges' => 'Revert changes',
			'editor.save' => 'Save',
			'editor.saveFailed' => ({required String error}) => 'Save failed: ${error}',
			'editor.selectAll' => 'Select all',
			'editor.title' => 'Editor',
			'editor.undoEdit' => 'Undo',
			'editor.unsavedChangesDiscardFile' => ({required String fileName}) => 'Discard unsaved changes to "${fileName}"?',
			'editor.unsavedChangesDiscardMultiple' => ({required int count}) => 'Discard unsaved changes in ${count} file(s)?',
			'editor.unsavedChangesTitle' => 'Unsaved changes',
			'exit.planModeApprove' => 'Approve',
			'exit.planModeApproveFailed' => 'Couldn\'t approve the plan',
			'exit.planModeCopyPlan' => 'Copy plan',
			'exit.planModeOpenPlanFile' => 'Open plan file',
			'exit.planModePreviewTitle' => 'Plan preview',
			'exit.planModeReject' => 'Reject',
			'exit.planModeRejectFailed' => 'Couldn\'t reject the plan',
			'exit.planModeTitle' => 'Plan ready for approval',
			'exit.planModeViewPlan' => 'View plan',
			'expert.editorCategory' => 'Category',
			'expert.editorConfigureMcpTitle' => 'Configure MCP',
			'expert.editorConfigurePluginsTitle' => 'Configure plugins',
			'expert.editorConfigureSkillsTitle' => 'Configure skills',
			'expert.editorCreateTitle' => 'New expert',
			'expert.editorDepPickerDone' => 'Done',
			'expert.editorDepsHint' => 'Configure dependencies from your installed library. Items without a portable source are skipped on save.',
			'expert.editorDescription' => 'Description',
			'expert.editorEditTitle' => 'Edit expert',
			'expert.editorMcpSection' => 'MCP',
			'expert.editorNameRequired' => 'Name is required.',
			'expert.editorNonPortableSkipped' => ({required int count}) => 'Skipped ${count} local-only item(s) without portable provenance.',
			'expert.editorOrphanDeps' => 'Attached (not installed locally)',
			'expert.editorOrphanRemove' => 'Remove',
			'expert.editorPlaybookHint' => 'Optional step-by-step guidance this expert should follow.',
			'expert.editorPluginsSection' => 'Plugins',
			'expert.editorPromptHint' => 'Describe this expert\'s role and what they are responsible for.',
			'expert.editorPromptRequired' => 'Responsibilities are required.',
			'expert.editorSkillsSection' => 'Skills',
			'expert.editorTags' => 'Tags',
			'expert.editorTagsHint' => 'Comma-separated',
			'expert.hubAddFailed' => 'Could not add this member.',
			'expert.hubAddFromHub' => 'Add from Expert Hub',
			'expert.hubAddPartial' => ({required Object name, required int skillCount, required int failedCount, required Object failedNames}) => 'Added "${name}". Installed ${skillCount} skills. ${failedCount} could not be installed: ${failedNames}.',
			'expert.hubAddSuccess' => ({required Object name}) => 'Added "${name}" to team.',
			'expert.hubAddSuccessWithSkills' => ({required Object name, required int skillCount}) => 'Added "${name}". Installed ${skillCount} skills.',
			'expert.hubAddToTeam' => 'Add to team',
			'expert.hubAdding' => 'Adding…',
			'expert.hubBrowseAll' => 'Browse all experts',
			'expert.hubCapabilities' => 'Capabilities',
			'expert.hubCardNoDescription' => 'None',
			'expert.hubCategoryAll' => 'All',
			'expert.hubConfirmSelection' => 'Confirm',
			'expert.hubCreate' => 'New',
			'expert.hubEmptyHint' => 'Refresh to fetch experts from the registry.',
			'expert.hubEmptyTitle' => 'No experts yet',
			'expert.hubFavorites' => 'Favorites',
			'expert.hubFavoritesEmptyHint' => 'Tap the star on an expert to save it here.',
			'expert.hubFavoritesEmptyTitle' => 'No favorites yet',
			'expert.hubFromTeams' => 'From teams',
			'expert.hubIgnoredInTeamMode' => 'Experts are only available in Simple mode. Switch to Simple to summon an expert.',
			'expert.hubLaunchInWorkspace' => 'Launch in workspace',
			'expert.hubLoadError' => 'Could not load experts.',
			'expert.hubMyTemplates' => 'My templates',
			'expert.hubNav' => 'Expert Hub',
			'expert.hubNoneSelected' => 'No expert',
			'expert.hubNotFound' => 'Expert not found.',
			'expert.hubPlaybook' => 'Playbook',
			'expert.hubPreflightPartial' => ({required Object name, required int failedCount, required Object failedNames}) => 'Selected "${name}". ${failedCount} capabilities could not be installed: ${failedNames}.',
			'expert.hubPrompt' => 'Responsibilities',
			'expert.hubRecent' => 'Recent',
			'expert.hubRefresh' => 'Refresh',
			'expert.hubSearchHint' => 'Search experts',
			'expert.hubSortName' => 'Name',
			'expert.hubSortUpdated' => 'Recently updated',
			'expert.hubSourceBuiltin' => 'Built-in',
			'expert.hubSourceClone' => 'Cloned',
			'expert.hubSourceLocal' => 'My template',
			'expert.hubSourceRegistry' => 'Registry',
			'expert.hubSourceTeamExtract' => 'From team',
			'expert.hubSubtitle' => 'Discover member personas and templates',
			'expert.hubTitle' => 'Expert Hub',
			'expert.hubViewInHub' => 'View in Expert Hub',
			'expert.hubViewOriginTeam' => 'View origin team',
			'extension.commandCopied' => 'Command copied to clipboard',
			'extension.copyCommand' => 'Copy',
			'extension.dependencyMissingHint' => ({required String deps}) => 'Needs ${deps} on your PATH. Install it, then re-check.',
			'extension.enableLabel' => 'Enabled',
			'extension.install' => 'Install',
			'extension.installGuide' => 'Install guide',
			'extension.kindMcpServer' => 'Code intelligence (MCP)',
			'extension.kindSettingsHook' => 'Token savings (hook)',
			'extension.recheck' => 'Re-check',
			'extension.statusDependencyMissing' => 'Missing dependency',
			'extension.statusDependencyMissingNamed' => ({required String deps}) => 'Missing: ${deps}',
			'extension.statusNotInstalled' => 'Not installed',
			'extension.statusReady' => 'Ready',
			'extension.statusReadyVersion' => ({required String version}) => 'Ready (${version})',
			'extension.statusVersionTooOld' => 'Installed version is too old',
			'extension.uninstall' => 'Uninstall',
			'file.codeBlockModeDescription' => 'How oversized code blocks render in the markdown file preview.',
			'file.codeBlockModeTitle' => 'Code blocks in file preview',
			'file.diffToggleDiff' => 'Diff',
			'file.diffToggleFile' => 'File',
			'file.previewHostCenter' => 'Center',
			'file.previewHostDescription' => 'Open files in the floating workspace or the center workbench.',
			'file.previewHostFloating' => 'Floating',
			'file.previewHostTitle' => 'File preview',
			'fileTree.fileTree' => 'File Tree',
			'fileTree.copy' => 'Copy',
			'fileTree.copyPath' => 'Copy path',
			'fileTree.copyRelativePath' => 'Copy relative path',
			'fileTree.createNameHint' => 'Name',
			'fileTree.cut' => 'Cut',
			'fileTree.deleteDone' => 'Deleted',
			'fileTree.deleteItemConfirm' => ({required String name}) => 'Delete "${name}"?',
			'fileTree.deleteItemTitle' => 'Delete',
			'fileTree.fileCreated' => 'File created',
			'fileTree.folderCreated' => 'Folder created',
			'fileTree.hideFilter' => 'Hide file filter',
			_ => null,
		} ?? switch (path) {
			'fileTree.importApplyRemaining' => 'Apply to remaining conflicts',
			'fileTree.importCancelAll' => 'Cancel all',
			'fileTree.importConflictBody' => ({required String name}) => '"${name}" already exists at the destination.',
			'fileTree.importConflictRemaining' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '1 more conflict after this.', other: '${count} more conflicts after this.', ), 
			'fileTree.importConflictRemainingZero' => 'No further conflicts.',
			'fileTree.importConflictTitle' => 'Item already exists',
			'fileTree.importConflictTypeMismatch' => 'A file and a folder cannot replace each other.',
			'fileTree.importDropCopy' => 'Copy',
			'fileTree.importDropMove' => 'Move',
			'fileTree.importOverwrite' => 'Overwrite',
			'fileTree.importProgressCancel' => 'Cancel',
			'fileTree.importProgressCurrent' => ({required String name}) => '${name}',
			'fileTree.importProgressItems' => ({required int completed, required int total}) => '${completed} / ${total}',
			'fileTree.importProgressTitle' => 'Importing…',
			'fileTree.importRejectSelf' => 'Cannot move or copy an item into itself or its children.',
			'fileTree.importSkip' => 'Skip',
			'fileTree.importSummary' => ({required int succeeded, required int skipped, required int failed}) => '${succeeded} succeeded, ${skipped} skipped, ${failed} failed',
			'fileTree.importSummaryCancelledSuffix' => ' — cancelled',
			'fileTree.invalidName' => 'Invalid name',
			'fileTree.invalidPasteTarget' => 'Cannot paste here',
			'fileTree.itemExists' => 'An item with that name already exists',
			'fileTree.newFile' => 'New File',
			'fileTree.newFolder' => 'New Folder',
			'fileTree.openInFileManager' => 'Reveal in File Manager',
			'fileTree.openInTerminal' => 'Open in Terminal',
			'fileTree.openInTerminalFailed' => 'Could not open a terminal',
			'fileTree.openWithSystemApp' => 'Open with system app',
			'fileTree.paste' => 'Paste',
			'fileTree.pasteDone' => 'Pasted',
			'fileTree.refresh' => 'Refresh',
			'fileTree.rename' => 'Rename',
			'fileTree.renameDone' => 'Renamed',
			'fileTree.renameTitle' => 'Rename',
			'fileTree.revealActiveFile' => 'Reveal active file',
			'fileTree.revealFailed' => 'Cannot reveal this file in the file tree',
			'fileTree.showFilter' => 'Show file filter',
			'fileTree.sourceMissing' => 'The copied item no longer exists',
			'floating.previewTabsDescription' => 'File and diff previews share one replaceable tab in the floating panel until pinned.',
			'floating.previewTabsTitle' => 'Single preview tab',
			'floating.restoreTerminalSessionsDescription' => 'Keep floating terminal tabs across restarts; a tab reconnects only when you first open it.',
			'floating.restoreTerminalSessionsTitle' => 'Restore terminal tabs',
			'floating.workspaceAddTooltip' => 'Open in floating workspace',
			'floating.workspaceCloseTab' => 'Close tab',
			'floating.workspaceMaximize' => 'Maximize',
			'floating.workspaceMinimize' => 'Minimize',
			'floating.workspaceNewTerminal' => 'New Terminal',
			'floating.workspaceOpenFile' => 'Open File',
			'floating.workspaceToggleTooltip' => 'Floating workspace',
			'font.changeAppliesOnRestart' => 'Font saved. Restart TeamPilot to apply.',
			'font.installedSection' => 'Installed',
			'font.monoDescription' => 'Terminal, editor, and diffs. Takes effect after restart.',
			'font.monoTitle' => 'Monospace font',
			'font.optionJetbrainsMono' => 'JetBrains Mono',
			'font.optionNotoSansSc' => 'Noto Sans SC',
			'font.optionSystem' => 'System',
			'font.optionUbuntuSansMono' => 'Ubuntu Sans Mono',
			'font.searchHint' => 'Search fonts',
			'font.uiDescription' => 'UI text. System follows the OS default. Takes effect after restart.',
			'font.uiTitle' => 'Interface font',
			'git.aheadBehind' => ({required int ahead, required int behind}) => '↑${ahead} ↓${behind}',
			'git.amend' => 'Amend',
			'git.amendCommit' => 'Amend Commit',
			'git.amendConfirmMessage' => 'This rewrites the last commit. If it was already pushed to a remote, a force push will be required afterwards.',
			'git.amendConfirmTitle' => 'Amend last commit?',
			'git.autoFetchDescription' => 'Periodically run a non-interactive git fetch --all --prune for the repository shown in the source-control panel, keeping ahead/behind counts fresh.',
			'git.autoFetchIntervalDescription' => 'How often the selected repository is fetched while the panel is open.',
			'git.autoFetchIntervalMinutesOption' => ({required int minutes}) => 'Every ${minutes} min',
			'git.autoFetchIntervalTitle' => 'Auto-fetch interval (minutes)',
			'git.autoFetchTitle' => 'Auto-fetch remote updates',
			'git.changes' => 'Changes',
			'git.changesListView' => 'List view',
			'git.changesTreeView' => 'Tree view',
			'git.commit' => 'Commit',
			'git.commitMessageHint' => ({required String branch}) => 'Message (commit to "${branch}")',
			'git.committing' => 'Committing…',
			'git.compareEmpty' => 'No differences',
			'git.compareLoadError' => 'Could not load differences',
			'git.compareSubtitle' => ({required String ref}) => 'Difference between ${ref} and current working tree',
			'git.compareWorkingTree' => 'Working Tree',
			'git.copyPath' => 'Copy Path',
			'git.createBranch' => 'Create branch',
			'git.discard' => 'Discard changes',
			'git.discardAllConfirmBody' => 'Discard all unstaged changes in the working tree? This cannot be undone.',
			'git.discardAllConfirmTitle' => 'Discard all changes?',
			'git.discardAllUnstaged' => 'Discard All Unstaged Changes',
			'git.discardConfirmBody' => ({required String path}) => 'Discard all changes in ${path}? This cannot be undone.',
			'git.discardConfirmTitle' => 'Discard changes?',
			'git.discardFolder' => 'Discard changes in folder',
			'git.discardFolderConfirmBody' => ({required String path}) => 'Discard all changes in ${path}? This cannot be undone.',
			'git.discardFolderConfirmTitle' => 'Discard folder changes?',
			'git.discardSelected' => 'Discard Selected Change',
			'git.error' => ({required String message}) => 'Git: ${message}',
			'git.excludeFolderFromCommit' => 'Exclude Folder from Commit',
			'git.excludeFromCommit' => 'Exclude from Commit',
			'git.fetch' => 'Fetch from remote',
			'git.fetchDone' => 'Fetched from remote',
			'git.fetching' => 'Fetching from remote…',
			'git.generateCommitMessage' => 'Generate commit message with AI',
			'git.generateCommitMessageNoProvider' => 'Configure an AI provider in Settings → AI Features first.',
			'git.generatingCommitMessage' => 'Generating commit message…',
			'git.includeFolderInCommit' => 'Include Folder in Commit',
			'git.includeInCommit' => 'Include in Commit',
			'git.initializeRepository' => 'Create Git repository',
			'git.newBranchHint' => 'New branch name',
			'git.noChanges' => 'No changes',
			'git.notARepository' => 'This folder is not a Git repository',
			'git.notInstalled' => 'Git was not found. Install Git to use source control.',
			'git.openFile' => 'Open File',
			'git.pull' => 'Pull',
			'git.pullDone' => 'Pull completed',
			'git.pulling' => 'Pulling…',
			'git.push' => 'Push',
			'git.pushDone' => 'Push completed',
			'git.pushing' => 'Pushing…',
			'git.refresh' => 'Refresh',
			'git.refreshing' => 'Refreshing…',
			'git.showDiff' => 'Show Diff',
			'git.stagedChanges' => 'Staged Changes',
			'git.switchBranch' => 'Switch branch',
			'git.unversionedFiles' => 'Unversioned Files',
			'gitGraph.allBranches' => 'All branches',
			'gitGraph.branchNameLabel' => 'Branch name',
			'gitGraph.branchesTags' => 'Branches & tags',
			'gitGraph.checkoutBranch' => ({required String branch}) => 'Checkout ${branch}',
			'gitGraph.checkoutCommit' => 'Checkout this commit (detached HEAD)',
			'gitGraph.checkoutCommitConfirmBody' => ({required String hash}) => 'Checkout ${hash} with detached HEAD?',
			'gitGraph.cherryPick' => 'Cherry-pick',
			'gitGraph.columnAuthor' => 'Author',
			'gitGraph.columnCommit' => 'Commit',
			'gitGraph.columnDate' => 'Date',
			'gitGraph.columnDescription' => 'Description',
			'gitGraph.columnGraph' => 'Graph',
			'gitGraph.columnHeaderLabel' => 'Column header',
			'gitGraph.columns' => 'Columns',
			'gitGraph.commits' => 'Commits',
			'gitGraph.compareFilterHint' => 'Filter branches, tags, and commits',
			'gitGraph.compareWith' => 'Compare with…',
			'gitGraph.compareWorkingTree' => ({required String branch}) => 'Working Tree (${branch})',
			'gitGraph.conflictHint' => 'Resolve the conflicts, stage the files, then commit to continue.',
			'gitGraph.copyHash' => 'Copy hash',
			'gitGraph.copySubject' => 'Copy subject',
			'gitGraph.create' => 'Create',
			'gitGraph.createBranchHere' => 'Create branch here',
			'gitGraph.createBranchTitle' => 'Create branch',
			'gitGraph.createTagHere' => 'Create tag here',
			'gitGraph.createTagTitle' => 'Create tag',
			'gitGraph.currentBranch' => 'Current branch',
			'gitGraph.deleteBranch' => ({required String name}) => 'Delete branch ${name}',
			'gitGraph.deleteBranchConfirmBody' => ({required String name}) => 'Delete branch "${name}"? Commits only reachable from it may become unreachable. This cannot be undone.',
			'gitGraph.deleteBranchTitle' => 'Delete branch',
			'gitGraph.deleteRemoteBranchConfirmBody' => ({required String name}) => 'Delete remote branch "${name}" on the shared repository? This affects all collaborators and cannot be undone.',
			'gitGraph.deleteRemoteBranchTitle' => 'Delete remote branch',
			'gitGraph.deleteTag' => ({required String name}) => 'Delete tag ${name}',
			'gitGraph.deleteTagConfirmBody' => ({required String name}) => 'Delete tag "${name}"? This cannot be undone.',
			'gitGraph.deleteTagTitle' => 'Delete tag',
			'gitGraph.fetch' => 'Fetch',
			'gitGraph.hashCopied' => 'Hash copied to clipboard',
			'gitGraph.hashSearchEmptyHint' => 'No loaded commit matches this hash. Scroll down or click "Load more" to fetch older history.',
			'gitGraph.hideColumn' => ({required String column}) => 'Hide ${column}',
			'gitGraph.hideColumnHeader' => 'Hide column header',
			'gitGraph.loadMore' => 'Load more',
			'gitGraph.loadingMore' => 'Loading…',
			'gitGraph.localBranches' => 'Local branches',
			'gitGraph.mergeIntoCurrent' => ({required String branch}) => 'Merge ${branch} into current branch',
			'gitGraph.noCommits' => 'No commits found',
			'gitGraph.notARepository' => 'Not a git repository',
			'gitGraph.pull' => 'Pull',
			'gitGraph.push' => 'Push',
			'gitGraph.pushTag' => ({required String name}) => 'Push tag ${name}',
			'gitGraph.refresh' => 'Refresh',
			'gitGraph.refsFilterEmpty' => 'No matches',
			'gitGraph.refsFilterHint' => 'Filter branches and tags',
			'gitGraph.remoteBranches' => 'Remote branches',
			'gitGraph.renameBranch' => 'Rename branch…',
			'gitGraph.renameBranchTitle' => 'Rename branch',
			'gitGraph.reset' => 'Reset',
			'gitGraph.resetHard' => 'Hard',
			'gitGraph.resetHardConfirmBody' => ({required String branch}) => 'Hard reset moves "${branch}" to this commit and discards ALL uncommitted changes. Type "${branch}" to confirm.',
			'gitGraph.resetMixed' => 'Mixed',
			'gitGraph.resetSoft' => 'Soft',
			'gitGraph.revert' => 'Revert',
			'gitGraph.revertConfirmBody' => ({required String hash}) => 'Revert commit ${hash}? A new commit undoing it will be created.',
			'gitGraph.searchHint' => 'Search commits (message / author / hash)',
			'gitGraph.searchModeAuthor' => 'Author',
			'gitGraph.searchModeHash' => 'Hash',
			'gitGraph.searchModeMessage' => 'Message',
			'gitGraph.selectCommit' => 'Select a commit to view details',
			'gitGraph.showColumnHeader' => 'Show column header',
			'gitGraph.stash' => 'Stash',
			'gitGraph.stashApply' => 'Apply',
			'gitGraph.stashDrop' => 'Drop',
			'gitGraph.stashDropConfirmBody' => ({required String selector}) => 'Drop ${selector}? This cannot be undone.',
			'gitGraph.stashPop' => 'Pop',
			'gitGraph.subjectCopied' => 'Subject copied to clipboard',
			'gitGraph.tagMessageLabel' => 'Message (optional)',
			'gitGraph.tagNameLabel' => 'Tag name',
			'gitGraph.tags' => 'Tags',
			'gitGraph.title' => 'Git Graph',
			'gitGraph.uncommittedChanges' => 'Uncommitted changes',
			'gitGraph.viewBranchHistory' => 'View this branch\'s history',
			'gitGraph.viewTagHistory' => 'View this tag\'s history',
			'github.advancedPat' => 'Use a personal access token',
			'github.advancedPatSubtitle' => 'When GitHub sign-in is unavailable, or you prefer a token with repo scope.',
			'github.authDenied' => 'GitHub authorization cancelled',
			'github.authExpired' => 'GitHub sign-in expired',
			'github.authExpiredRetry' => 'Authorization expired. Try again.',
			'github.browserOpened' => 'Browser opened for authorization',
			'github.connectedAs' => ({required Object login}) => 'Connected as @${login}',
			'github.connectedGeneric' => 'Connected to GitHub',
			'github.deviceFlowUnavailable' => 'GitHub sign-in is unavailable in this build. Use a personal access token.',
			'github.disconnect' => 'Disconnect',
			'github.networkError' => 'Could not reach GitHub. Try again.',
			'github.reopenBrowser' => 'Reopen browser',
			'github.settingsSubtitle' => 'Connect GitHub to publish experts and teams to Hub',
			'github.settingsTitle' => 'GitHub',
			'github.signIn' => 'Sign in with GitHub',
			'github.switchAccount' => 'Switch account',
			'github.waitingCodeHint' => 'Enter this code on GitHub if prompted',
			'grok.credentialsActionFailed' => 'The Grok action failed',
			'grok.credentialsCancel' => 'Cancel',
			'grok.credentialsDone' => 'Done',
			'grok.credentialsLogin' => 'Sign in',
			'grok.credentialsLoginExited' => 'Grok CLI exited. Close this dialog and start the sign-in again.',
			'grok.credentialsLoginFailed' => ({required String error}) => 'Could not start the login terminal: ${error}',
			'grok.credentialsLoginIntro' => 'Complete the device sign-in in the terminal below. Grok prints a code and opens a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.',
			'grok.credentialsLoginStarting' => 'Starting Grok CLI…',
			'grok.credentialsLoginTitle' => 'Sign in to Grok',
			'grok.credentialsRelaunch' => 'Relaunch',
			'grok.credentialsSignedIn' => 'Signed in',
			'grok.credentialsImportGlobal' => 'Import existing login',
			'home.connectionCancelRetry' => 'Stop retrying',
			'home.connectionErrorAuth' => 'Authentication failed',
			'home.connectionErrorHostKey' => 'Host identity changed — re-pair or confirm the new key',
			'home.connectionErrorTcp' => 'Network unreachable',
			'home.connectionErrorTimeout' => 'Connection timed out',
			'home.connectionErrorTransport' => 'Connection error',
			'home.connectionErrorUnknown' => 'Unknown error',
			'home.connectionRetryNow' => 'Retry now',
			'home.connectionRetrying' => ({required int count}) => 'Retrying… attempt ${count}',
			'home.connectionSwitch' => 'Switch connection',
			'home.connectionUnreachable' => ({required String host, required int port}) => 'Can\'t reach ${host}:${port}',
			'home.targetSingleOptionHint' => 'This is the only available home on this platform.',
			'home.targetSubtitle' => 'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.',
			'home.targetTitle' => 'Home device',
			'homeWorkspace.allWorkspaces' => 'All workspaces',
			'homeWorkspace.cloneWorkspace' => 'Clone workspace',
			'homeWorkspace.cloneWorkspaceDisplayName' => ({required Object name}) => '${name} (copy)',
			'homeWorkspace.cloneWorkspaceFailed' => 'Could not clone workspace',
			'homeWorkspace.cloneWorkspaceSuccess' => ({required Object name}) => 'Cloned "${name}".',
			'homeWorkspace.closeAllTabsMessage' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'Closing all tabs will end 1 running session.', other: 'Closing all tabs will end ${count} running sessions.', ), 
			'homeWorkspace.closeAllTabsTitle' => 'Close all tabs?',
			'homeWorkspace.closeWorkspaceConfirm' => 'Close & end sessions',
			'homeWorkspace.closeWorkspaceMessage' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'Closing this tab will end 1 running session in this workspace.', other: 'Closing this tab will end ${count} running sessions in this workspace.', ), 
			'homeWorkspace.closeWorkspaceTitle' => 'Close workspace?',
			'homeWorkspace.comingSoon' => 'Coming soon',
			'homeWorkspace.conversations' => 'Conversations',
			'homeWorkspace.conversationsSection' => 'Conversations',
			'homeWorkspace.createTeam' => 'Create team',
			'homeWorkspace.createWorkspace' => 'Create workspace',
			'homeWorkspace.defaultMixedTeamName' => 'Default Mixed Team',
			'homeWorkspace.defaultNativeTeamName' => 'Default Native Team',
			'homeWorkspace.defaultPersonalWorkspaceName' => 'Personal assistant',
			'homeWorkspace.emptyWorkspaces' => 'No workspaces in this team yet',
			'homeWorkspace.emptyWorkspacesHint' => 'Create or import a workspace to get started',
			'homeWorkspace.favoriteWorkspace' => 'Favorite workspace',
			'homeWorkspace.importWorkspace' => 'Import',
			'homeWorkspace.inviteMembers' => 'Invite',
			'homeWorkspace.launchWorkspaceTitle' => 'Open with…',
			'homeWorkspace.mainWindow' => 'Workspace',
			'homeWorkspace.myFavorites' => 'My favorites',
			'homeWorkspace.newConversation' => 'New Conversation',
			'homeWorkspace.newConversationChooseCli' => 'New conversation with CLI…',
			'homeWorkspace.newTeam' => 'New Team',
			'homeWorkspace.newTeamMethodAi' => 'AI generate',
			'homeWorkspace.newTeamMethodCustom' => 'Custom',
			'homeWorkspace.newTeamModeBeta' => 'Beta',
			'homeWorkspace.newTeamNameHint' => 'Enter a team name',
			'homeWorkspace.newTeamRecommended' => 'Recommended',
			'homeWorkspace.newTeamSubtitle' => 'Pick how the team collaborates, then name it.',
			'homeWorkspace.newTeamSubtitleAi' => 'Describe your team and generate a draft with AI.',
			'homeWorkspace.newWorkspaceChooseDirectory' => 'Choose folder',
			'homeWorkspace.newWorkspaceDirectoryHint' => 'No directory selected yet',
			'homeWorkspace.newWorkspaceDirectoryLabel' => 'Workspace directory',
			'homeWorkspace.newWorkspaceNameHint' => 'Defaults to the folder name',
			'homeWorkspace.newWorkspaceSubtitle' => 'Choose a working directory and name your workspace.',
			'homeWorkspace.noConversations' => 'No conversations in this workspace yet',
			'homeWorkspace.noData' => 'No data yet',
			'homeWorkspace.noSearchResults' => 'No conversations match your search',
			'homeWorkspace.openInNewTabWithOtherIdentity' => 'Open in new tab with other identity…',
			'homeWorkspace.openTabs' => 'Open',
			'homeWorkspace.openWorkspaceInNewTab' => 'Open in new tab',
			'homeWorkspace.owner' => 'Owner',
			'homeWorkspace.personal' => 'Simple mode',
			'homeWorkspace.personalSubtitle' => 'Skip the team setup — just launch a single CLI and start chatting.',
			'homeWorkspace.providers' => 'Providers',
			'homeWorkspace.recentVisits' => 'Recent',
			'homeWorkspace.recentlyClosed' => 'Recently closed',
			'homeWorkspace.recentlyClosedEmpty' => 'No recently closed workspaces',
			'homeWorkspace.rememberLaunchChoice' => 'Remember my choice',
			'homeWorkspace.renameWorkspace' => 'Rename workspace',
			'homeWorkspace.searchHint' => 'Search',
			'homeWorkspace.sessionsLabel' => 'sessions',
			'homeWorkspace.simpleMode' => 'Simple mode',
			'homeWorkspace.teamConfig' => 'Team config',
			'homeWorkspace.teamWorkspaces' => 'Workspaces',
			'homeWorkspace.unfavoriteWorkspace' => 'Remove from favorites',
			'homeWorkspace.workspaceAdditionalDirsCount' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '1 additional directory', other: '${count} additional directories', ), 
			'homeWorkspace.workspaceAgent' => 'Agent',
			'homeWorkspace.workspaceExtensions' => 'Extensions',
			'homeWorkspace.workspaceFilterEmpty' => 'No workspaces match your filter',
			'homeWorkspace.workspaceFilterHint' => 'Filter workspaces',
			'homeWorkspace.workspaceHooks' => 'Hooks',
			'homeWorkspace.workspaceId' => 'Workspace ID',
			'homeWorkspace.workspaceList' => 'Workspaces',
			'homeWorkspace.workspaceManagement' => 'Workspace management',
			'homeWorkspace.workspaceMcp' => 'MCP',
			'homeWorkspace.workspaceMembers' => 'Members',
			'homeWorkspace.workspacePath' => 'Workspace path',
			'homeWorkspace.workspacePlugins' => 'Plugins',
			'homeWorkspace.workspaceSettings' => 'Workspace settings',
			'homeWorkspace.workspaceSettingsBasicInfo' => 'Basic information',
			'homeWorkspace.workspaceSettingsPathsHint' => 'Use Manage on additional directories to add or remove folders in this workspace.',
			'homeWorkspace.workspaceSettingsSectionBasic' => 'Basic',
			'homeWorkspace.workspaceSkills' => 'Skills',
			'homeWorkspace.workspaceSort' => 'Sort workspaces',
			'homeWorkspace.workspaceSortCreatedDesc' => 'Date created',
			'homeWorkspace.workspaceSortNameAsc' => 'Name (A–Z)',
			'homeWorkspace.workspaceSortNameDesc' => 'Name (Z–A)',
			'homeWorkspace.workspaceSortRecentlyUpdated' => 'Recently updated',
			'homeWorkspace.workspaceSortSessionCountDesc' => 'Session count',
			'hook.actionCommand' => 'Command',
			'hook.actionScript' => 'Script',
			'hook.capabilityMatrix' => 'Capability matrix',
			'hook.description' => 'Description',
			'hook.edit' => 'Edit hook',
			'hook.env' => 'Environment (KEY=VALUE per line)',
			'hook.event' => 'Event',
			'hook.import' => 'Import',
			'hook.importCli' => 'CLI',
			'hook.importDone' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: 'Import ${count} hook', other: 'Import ${count} hooks', ), 
			'hook.importDoneToast' => 'Hooks imported',
			'hook.importInvalidJson' => 'Invalid hook JSON',
			'hook.importJson' => 'Hook JSON',
			'hook.importJsonHint' => 'Paste settings.json hooks, hooks.json, or a hooks fragment…',
			'hook.importNoHooks' => 'No hooks found',
			'hook.importOverwrite' => 'Will overwrite',
			'hook.importParse' => 'Parse',
			'hook.installedCount' => ({required int count}) => '${count} installed',
			'hook.matcher' => 'Matcher',
			'hook.name' => 'Name',
			'hook.nameRequired' => 'Name is required',
			'hook.navTitle' => 'Hooks',
			'hook.kNew' => 'New hook',
			'hook.policy' => 'Policy',
			'hook.save' => 'Save',
			'hook.saveFailed' => 'Failed to save hook.',
			'hook.supportMatrix' => 'View support matrix',
			'hook.timeoutSec' => 'Timeout (seconds)',
			'hub.publishAuthHint' => 'Sign in with GitHub to authorize a fork-based pull request into the Hub registry.',
			'hub.publishAuthorLabel' => 'Author',
			'hub.publishBadgePrOpen' => 'PR open',
			'hub.publishBadgePublished' => 'Published',
			'hub.publishCategoryRequired' => 'Category is required',
			'hub.publishConfirmHint' => 'Review the package metadata, then publish a fork-based pull request.',
			'hub.publishCopyLink' => 'Copy link',
			'hub.publishDone' => 'Done',
			'hub.publishExpertTitle' => 'Publish expert to Hub',
			'hub.publishGatesClear' => 'All dependencies look portable. Continue to confirm.',
			'hub.publishKindExpert' => 'Expert',
			'hub.publishKindLabel' => 'Kind',
			'hub.publishKindTeam' => 'Team',
			'hub.publishLocalExpertBlocked' => 'Remap every local expert before continuing',
			'hub.publishLocalExpertHint' => 'Local experts on the roster must be remapped to a published or builtin expert before upload.',
			'hub.publishNext' => 'Next',
			'hub.publishNonPortableBlocked' => 'Remove non-portable dependencies before continuing',
			'hub.publishNonPortableHint' => 'These dependencies have no portable provenance. Remove them from the team bundle before publishing:',
			'hub.publishOpenPr' => 'Open PR',
			'hub.publishPublish' => 'Publish',
			'hub.publishRemapLabel' => 'Publish as',
			'hub.publishSlugHint' => 'url-safe-id',
			'hub.publishSlugLabel' => 'Slug',
			'hub.publishSlugRequired' => 'Slug is required',
			'hub.publishSuccessHint' => 'Pull request opened. Share or open the link below.',
			'hub.publishTeamTitle' => 'Publish team to Hub',
			'hub.publishTokenHint' => 'ghp_…',
			'hub.publishTokenLabel' => 'GitHub token',
			'hub.publishTokenRequired' => 'GitHub token is required to publish',
			'hub.publishTokenSaveFailed' => 'Could not save the GitHub token',
			'hub.publishTokenStored' => 'A token is already saved. You can replace it below.',
			'init.errorCopied' => 'Copied',
			'init.errorCopy' => 'Copy',
			'init.errorCopyReport' => 'Copy report',
			'init.errorDetails' => 'Error details',
			'init.errorPendingLogs' => 'Pending logs',
			'init.errorStackEmpty' => 'Stack trace is empty.',
			'init.errorStackTrace' => 'Stack trace',
			'init.errorTitle' => 'Startup failed',
			'init.errorVersion' => ({required String version, required String build}) => 'Version ${version} (${build})',
			'init.errorViewLogs' => 'View logs',
			'landing.launchAcpUnsupported' => ({required String cli, required String target}) => '${cli} only supports ACP chat, and the selected target (${target}) cannot run ACP. Choose a local, SSH, or Termux target, or pick a CLI with terminal support.',
			'landing.launchLocalAdapterMissingDetail' => ({required String cli}) => '${cli} ACP adapter not found',
			'landing.launchLocalCliMissing' => 'Install the required AI CLIs on this device before starting.',
			'landing.launchLocalCliMissingDetail' => ({required String cli}) => '${cli} not found',
			'landing.launchLocalCliMissingHint' => 'Install it here, or set its executable path in Settings → CLI.',
			'landing.launchLocalCliMissingTitle' => 'Required AI CLIs on this device',
			'landing.launchLocalCliOpenSettings' => 'Open settings',
			'landing.launchRemoteCliMissing' => 'Install required CLIs on remote machines before starting.',
			'landing.launchRemoteCliMissingDetail' => ({required String cli, required String host}) => '${cli} on ${host}',
			'landing.teamSettingsGlobalHint' => 'Changes apply to this team\'s global configuration.',
			'landing.teamSettingsNavMachines' => 'Machine assignment',
			'landing.teamSettingsNavTeam' => 'Team defaults',
			'llm.config' => 'Provider',
			'llm.configCurrentEffectivePathPrefix' => 'Active file:',
			'llm.configEffectivePathUnresolved' => 'Could not resolve a path yet (set the CLI location or enter a path).',
			'llm.configOpenSessionSettings' => 'Session settings…',
			'llm.configPageSubtitle' => 'Manage LLM providers and models.',
			'llm.configPathBadgeCustom' => 'custom',
			'llm.configPathBadgeDefault' => 'default',
			'llm.configPathBrowse' => 'Browse...',
			'llm.configPathHint' => 'Leave empty to use the default path',
			'llm.configPathLabel' => 'LLM config file',
			'llm.configPathPickerTitle' => 'Select llm_config.json',
			'llm.configPathReset' => 'Use default',
			'llm.configPathSave' => 'Apply',
			'llm.configPathSessionCardDescription' => 'Absolute path to the LLM config file (llm_config.json). Leave empty to use the default path next to the CLI install.',
			'llm.configPathSessionCardDescriptionSsh' => 'Absolute path to llm_config.json on the remote SSH host. Leave empty to use the default path next to the remote CLI install.',
			'llm.configSubtitle' => 'providers and models',
			'log.viewerAcpFrames' => 'ACP protocol frames (off by default)',
			'log.viewerActionsMenu' => 'More actions',
			'log.viewerAllCopied' => 'All filtered logs copied',
			'log.viewerClearDone' => 'Old log files removed',
			'log.viewerClearFailed' => ({required String error}) => 'Cleanup failed: ${error}',
			'log.viewerClearOld' => 'Remove old logs',
			'log.viewerCompactView' => 'Compact view',
			'log.viewerCopyAll' => 'Copy all logs',
			'log.viewerCopyPath' => 'Copy log path',
			'log.viewerEmpty' => 'No log files yet',
			'log.viewerEmptyHint' => 'Logs are created while the app runs.',
			'log.viewerFileLabel' => 'Log file',
			'log.viewerFilterLevel' => 'Level',
			'log.viewerFilterTitle' => 'Filters',
			'log.viewerLineCount' => ({required int count}) => '${count} lines',
			'log.viewerLoadFilesFailed' => ({required String error}) => 'Failed to list logs: ${error}',
			'log.viewerPathCopied' => ({required String name}) => 'Copied path: ${name}',
			'log.viewerPendingBody' => 'Buffered entries waiting for file logging:',
			'log.viewerPendingTitle' => 'Logs not on disk yet',
			'log.viewerReadFailed' => ({required String error}) => 'Failed to read log: ${error}',
			'log.viewerRefresh' => 'Refresh',
			'log.viewerReverseOrder' => 'Newest first',
			'log.viewerSearchHint' => 'Search logs…',
			'log.viewerSubtitle' => 'Application and error logs under your TeamPilot app data folder.',
			'log.viewerTitle' => 'Logs',
			'log.viewerWrapLines' => 'Wrap lines',
			'managedProviders.adapter' => 'Adapter',
			'managedProviders.adapterHint' => 'http-json or a registered adapter id',
			'managedProviders.add' => 'Add provider',
			'managedProviders.advancedSectionSubtitle' => 'Adapter, kind, and internal reference.',
			'managedProviders.advancedSectionTitle' => 'Adapter, kind, and reference',
			'managedProviders.authenticationFailed' => 'Provider authentication failed.',
			'managedProviders.basicsSectionSubtitle' => 'Name and any required secret.',
			'managedProviders.basicsSectionTitle' => 'Name and API key',
			'managedProviders.basicsSummary' => 'Pick a preset, name the provider, and add a secret if needed.',
			'managedProviders.cachedUsage' => 'Cached usage',
			'managedProviders.cachedUsageStale' => 'Cached usage · needs refresh',
			'managedProviders.cancel' => 'Cancel',
			'managedProviders.credentialConfigured' => 'Credential configured · secret is masked',
			'managedProviders.credentialField' => 'Secret field name',
			'managedProviders.credentialFieldHelper' => 'Field name in local storage.',
			'managedProviders.credentialFieldHint' => 'apiKey or accessToken',
			'managedProviders.credentialFieldRequired' => 'Enter the credential field before saving the API key.',
			'managedProviders.credentialLinkEmpty' => 'No API-key providers configured yet',
			'managedProviders.credentialLinkManual' => 'Enter secret manually',
			'managedProviders.credentialLinkMode' => 'Credential source mode',
			'managedProviders.credentialLinkedTo' => ({required Object provider}) => 'Using credential of ${provider}',
			'managedProviders.credentialName' => 'Credential parameter name',
			'managedProviders.credentialNameHelper' => 'Parameter name on the request.',
			'managedProviders.credentialNameHint' => 'Authorization or Cookie',
			'managedProviders.credentialNone' => 'No credential configured',
			'managedProviders.credentialPlacement' => 'Credential placement',
			'managedProviders.credentialPlacementHelper' => 'header or query.',
			'managedProviders.credentialPlacementHint' => 'header or query',
			'managedProviders.credentialRef' => 'Credential reference',
			'managedProviders.credentialRefHint' => 'Reference only; secret values are never shown',
			'managedProviders.credentialSaveFailed' => 'Unable to save provider credentials securely.',
			'managedProviders.credentialSecret' => 'API key / token',
			'managedProviders.credentialSecretExistingHint' => 'Leave blank to keep the stored secret',
			'managedProviders.credentialSecretHelper' => 'Leave blank to keep the stored secret.',
			'managedProviders.credentialSecretHint' => 'Paste the provider API key or token',
			'managedProviders.credentialSource' => 'Credential source',
			'managedProviders.credentialSourceHelper' => 'secret reads the form; cli:… reads CLI login.',
			'managedProviders.credentialSourceHint' => 'secret or cli:cursor-mp-<entry>',
			'managedProviders.credentialTemplate' => 'Credential template',
			'managedProviders.credentialTemplateHelper' => 'Builds the final credential; often a Cookie with brace variables.',
			'managedProviders.credentialTemplateHint' => 'e.g. WorkosCursorSessionToken=user::token',
			'managedProviders.credentials' => 'Credentials',
			'managedProviders.credentialsSectionSubtitle' => 'Credential source and how it is sent.',
			'managedProviders.credentialsSectionTitle' => 'Credential source and delivery',
			'managedProviders.currency' => 'Currency',
			'managedProviders.currencyMappingHelper' => 'Currency is read from the response mapping when set.',
			'managedProviders.decimalError' => 'Decimal places must be a whole number.',
			'managedProviders.decimals' => 'Decimals',
			'managedProviders.delete' => 'Delete',
			'managedProviders.deleteContent' => ({required Object name}) => 'Delete “${name}” and its cached usage?',
			'managedProviders.deleteFailed' => 'Unable to delete managed provider.',
			'managedProviders.deleteTitle' => 'Delete managed provider?',
			'managedProviders.disable' => 'Disable',
			'managedProviders.disabled' => 'Disabled',
			'managedProviders.display' => 'Display configuration',
			'managedProviders.displaySectionSubtitle' => 'How balances and quotas are shown.',
			'managedProviders.displaySectionTitle' => 'Balance and quota display',
			'managedProviders.dynamicCurrencyHelper' => 'Currency comes from the response mapping.',
			'managedProviders.edit' => 'Edit',
			_ => null,
		} ?? switch (path) {
			'managedProviders.editTitle' => 'Edit Managed Provider',
			'managedProviders.emptyHint' => 'Add a provider to track balances and quotas independently from CLI providers.',
			'managedProviders.emptyTitle' => 'No managed providers',
			'managedProviders.enable' => 'Enable',
			'managedProviders.enabled' => 'Enabled',
			'managedProviders.enabledSubtitle' => 'Hides the provider and stops queries when off.',
			'managedProviders.enabledTitle' => 'Enabled',
			'managedProviders.endpoint' => 'Usage API URL',
			'managedProviders.endpointError' => 'Enter an HTTPS or loopback endpoint for this HTTP adapter.',
			'managedProviders.endpointHelper' => 'URL used to fetch usage data.',
			'managedProviders.endpointHint' => 'https://api.example.com/usage',
			'managedProviders.error' => 'Error',
			'managedProviders.fieldExampleLabel' => 'Example',
			'managedProviders.fieldMappingError' => 'Field mappings must be a secret-free JSON object.',
			'managedProviders.fieldMappings' => 'List item field mappings (JSON)',
			'managedProviders.fieldMappingsHelper' => '\$ path per field inside each array item.',
			'managedProviders.headers' => 'Request headers (JSON)',
			'managedProviders.headersHelper' => 'Extra headers; values may use brace placeholders.',
			'managedProviders.headersHint' => 'Accept: application/json',
			'managedProviders.httpFailed' => 'Provider service returned an error.',
			'managedProviders.identity' => 'Identity',
			'managedProviders.jsonPathSeeAlso' => 'See \$ syntax in Usage API and JSON parsing ℹ️',
			'managedProviders.kind' => 'Kind',
			'managedProviders.kindApiBalance' => 'API balance',
			'managedProviders.kindCustomHttp' => 'Custom HTTP',
			'managedProviders.kindPresetLockedHelper' => 'Locked by the selected preset or provider template.',
			'managedProviders.kindSubscriptionQuota' => 'Subscription quota',
			'managedProviders.lastQueryFailed' => 'Last query failed',
			'managedProviders.loadFailed' => 'Unable to load managed providers.',
			'managedProviders.loadingUsage' => 'Loading usage',
			'managedProviders.measuresPath' => 'Usage list (\$)',
			'managedProviders.measuresPathHelper' => '\$ path to a balance array (e.g. DeepSeek).',
			'managedProviders.measuresPathHint' => '\$.balance_infos',
			'managedProviders.method' => 'HTTP method',
			'managedProviders.methodHelper' => 'Usually GET.',
			'managedProviders.missingCredential' => 'Provider credentials are missing.',
			'managedProviders.name' => 'Name',
			'managedProviders.nameAdapterError' => 'Name and adapter are required.',
			'managedProviders.nameHint' => 'Visible name',
			'managedProviders.nav' => 'Managed Providers',
			'managedProviders.networkFailed' => 'Provider network request failed.',
			'managedProviders.newTitle' => 'New Managed Provider',
			'managedProviders.noUsage' => 'No usage queried yet',
			'managedProviders.noneEnabledHint' => 'Enable a provider to show it in the status bar and include it in queries.',
			'managedProviders.noneEnabledTitle' => 'No enabled providers',
			'managedProviders.queryCompleted' => 'Provider query completed.',
			'managedProviders.queryFailed' => 'Unable to query provider usage.',
			'managedProviders.querySectionSubtitle' => 'Usage API and JSON parsing.',
			'managedProviders.querySectionTitle' => 'Usage API and JSON parsing',
			'managedProviders.queryUnsupported' => 'Query unsupported',
			'managedProviders.quickPresetClaudeCode' => 'Claude Code',
			'managedProviders.quickPresetClaudeCodeHint' => 'Sign in or import credentials below, or fill the same fields manually.',
			'managedProviders.quickPresetCodebuddy' => 'CodeBuddy',
			'managedProviders.quickPresetCodebuddyHint' => 'Query credit balance with your CodeBuddy sign-in.',
			'managedProviders.quickPresetCodex' => 'Codex',
			'managedProviders.quickPresetCodexHint' => 'Sign in or import credentials below, or fill the same fields manually.',
			'managedProviders.quickPresetCursor' => 'Cursor',
			'managedProviders.quickPresetCursorHint' => 'Sign in or import credentials below, or fill the same fields manually.',
			'managedProviders.quickPresetGrokX' => 'Grok / Cursor / X',
			'managedProviders.quickPresetGrokXHint' => 'Query the unified weekly pool and prepaid balance with your Cursor sign-in.',
			'managedProviders.quickPresetCustom' => 'Custom',
			'managedProviders.quickPresetCustomHint' => 'Configure endpoint, credentials, and display from scratch.',
			'managedProviders.quickPresetDeepSeek' => 'DeepSeek',
			'managedProviders.quickPresetDeepSeekHint' => 'Balance API preset; add a secret.',
			'managedProviders.quickPresetHint' => 'Starts with safe defaults; add your credential before querying.',
			'managedProviders.quickPresetOpencodeGo' => 'OpenCode Go',
			'managedProviders.quickPresetOpencodeGoHint' => 'Zen Go subscription quota preset; add your API key.',
			'managedProviders.quickPresetQoder' => 'Qoder',
			'managedProviders.quickPresetQoderCn' => 'Qoder CN',
			'managedProviders.quickPresetQoderCnHint' => 'Query plan credits with a PAT from qoder.com.cn/account/integrations.',
			'managedProviders.quickPresetQoderHint' => 'Query plan credits with a PAT from qoder.com/account/integrations.',
			'managedProviders.quickPresetTitle' => 'Quick preset',
			'managedProviders.referenceSyntaxHelper' => '\$ — read from the HTTP response JSON\n\$ is the whole response; \$.field descends with dots.\nE.g. \$.data, \$.balance_infos[0].total_balance, \$.rate_limit.used_percent\n\nUse \$ in response root and quota windows (used / total / remaining / resetsAt).\n\nBraces — fill dynamic values into the request (not from the response)\nPut a variable name inside braces; it is replaced when the request is sent.\n• accessToken — access token\n• accountId — account id\n• jwt.sub — JWT sub\n\nUsed in headers, cookies, and credential templates. Values come from cli:… login.',
			'managedProviders.refreshFailed' => 'Unable to refresh provider usage.',
			'managedProviders.remainingPercent' => ({required String percent}) => '${percent}% remaining',
			'managedProviders.requestMapping' => 'Request body (JSON)',
			'managedProviders.requestMappingError' => 'Request mapping must be a JSON object.',
			'managedProviders.requestMappingHelper' => 'For POST; leave blank for GET.',
			'managedProviders.resetsIn' => ({required String duration}) => 'Resets in ${duration}',
			'managedProviders.resetsSoon' => 'Resets soon',
			'managedProviders.responseParseFailed' => 'Provider response could not be parsed.',
			'managedProviders.responsePath' => 'Response root (\$)',
			'managedProviders.responsePathHelper' => 'Use \$ to unwrap nested data; blank starts at the response root.',
			'managedProviders.responsePathHint' => '\$.data',
			'managedProviders.retry' => 'Retry',
			'managedProviders.save' => 'Save',
			'managedProviders.saveFailed' => 'Unable to save managed provider.',
			'managedProviders.saveProvider' => 'Save provider',
			'managedProviders.saved' => 'Managed provider saved.',
			'managedProviders.saving' => 'Saving…',
			'managedProviders.secretMappingError' => 'Use a credential reference instead of putting secrets in the request mapping.',
			'managedProviders.sectionConfiguredBadge' => 'Configured',
			'managedProviders.showPercent' => 'Show percentage',
			'managedProviders.stale' => 'Stale',
			'managedProviders.subtitle' => 'Balances and quotas independent from CLI provider configuration.',
			'managedProviders.templateVariablesSeeAlsoCredentials' => 'See brace syntax in Credential source and delivery ℹ️',
			'managedProviders.templateVariablesSeeAlsoQuery' => 'See brace syntax in Usage API and JSON parsing ℹ️',
			'managedProviders.testProviderQuery' => 'Test provider query',
			'managedProviders.testQuery' => 'Test query',
			'managedProviders.title' => 'Managed Providers',
			'managedProviders.unit' => 'Unit',
			'managedProviders.unknownUsage' => 'Unknown usage status',
			'managedProviders.usageInvalidated' => 'Provider usage was invalidated.',
			'managedProviders.usageLoadFailed' => 'Unable to load provider usage.',
			'managedProviders.usageNav' => 'Balances & usage',
			'managedProviders.usagePersistenceFailed' => 'Unable to save provider usage.',
			'managedProviders.windows' => 'Quota windows (JSON)',
			'managedProviders.windowsHelper' => 'One window per quota line. Write label and \$ paths for used / total / remaining / resetsAt. For array items, hard-code the index, e.g. \$.balance_infos[0].total_balance.',
			'managedProviders.windowsHint' => 'JSON array; each item has label and \$ paths',
			'mcp.add' => 'Add MCP server',
			'mcp.addButton' => 'Add MCP',
			'mcp.addTitle' => 'Add MCP',
			'mcp.catalogAdd' => 'Add',
			'mcp.catalogAdded' => 'MCP server added to catalog',
			'mcp.catalogAdoption' => 'Uses',
			'mcp.catalogCardNoDescription' => 'None',
			'mcp.catalogEmpty' => 'No servers found',
			'mcp.catalogInstalled' => 'Installed',
			'mcp.catalogVerified' => 'Verified',
			'mcp.configuredCount' => ({required int count}) => '${count} MCP server(s) configured',
			'mcp.deleteConfirm' => 'Delete MCP server?',
			'mcp.discoverySectionHint' => 'Browse built-in templates and remote catalogs configured under Registries.',
			'mcp.discoverySectionTitle' => 'Discover MCP servers',
			'mcp.discoverySourceAll' => 'All',
			'mcp.discoverySourceBuiltin' => 'Built-in',
			'mcp.edit' => 'Edit MCP server',
			'mcp.empty' => 'No MCP servers in catalog',
			'mcp.emptyGoDiscovery' => 'Browse built-in templates',
			'mcp.emptyGoRegistries' => 'Open registry settings',
			'mcp.fieldArgs' => 'Arguments (space-separated)',
			'mcp.fieldCommand' => 'Command',
			'mcp.fieldName' => 'Name',
			'mcp.formDescriptionHint' => 'Optional description',
			'mcp.formDescriptionLabel' => 'Description',
			'mcp.formDetailHint' => 'Select a server to edit, or add a new MCP server.',
			'mcp.formDisplayNameHint' => 'e.g. @modelcontextprotocol/server-time',
			'mcp.formDisplayNameLabel' => 'Display name',
			'mcp.formDocsLabel' => 'Documentation',
			'mcp.formFormatJson' => 'Format',
			'mcp.formHomepageLabel' => 'Homepage',
			'mcp.formIdLabel' => 'MCP ID (unique) *',
			'mcp.formJsonLabel' => 'Full JSON configuration',
			'mcp.formMetadata' => 'Additional info',
			'mcp.formRequiredFields' => 'MCP ID and display name are required.',
			'mcp.formSubmitAdd' => 'Add',
			'mcp.formTagsHint' => 'stdio, time, utility',
			'mcp.formTagsLabel' => 'Tags (comma-separated)',
			'mcp.import' => 'Import from machine',
			'mcp.importDone' => 'MCP catalog updated',
			'mcp.importEmpty' => 'No MCP servers found in ~/.claude.json or ~/.flashskyai.json',
			'mcp.importExisting' => 'Import existing',
			'mcp.importOverwrite' => 'Overwrite conflicts',
			'mcp.importSummary' => ({required int added, required int conflicts}) => '${added} new, ${conflicts} conflicts',
			'mcp.installedCount' => ({required int count}) => '${count} installed',
			'mcp.installedSectionTitle' => 'Installed MCP servers',
			'mcp.navDiscovery' => 'Discovery',
			'mcp.navInstalled' => 'Installed',
			'mcp.navRegistries' => 'Registry',
			'mcp.navTitle' => 'MCP Servers',
			'mcp.noInstalled' => 'No MCP servers installed yet',
			'mcp.noInstalledHint' => 'Open Discovery to add servers from built-in templates or registries.',
			'mcp.oAuthCallbackUrlHint' => 'Paste the full URL after sign-in (contains ?code=)',
			'mcp.oAuthCallbackUrlLabel' => 'Redirect URL',
			'mcp.oAuthConnectAction' => 'Connect',
			'mcp.oAuthConnectHint' => 'Sign in with the MCP provider in your browser. Tokens are stored in Claude Code format under app config (same as /mcp → Authenticate).',
			'mcp.oAuthConnectSuccess' => 'MCP OAuth connected',
			'mcp.oAuthConnectTitle' => ({required String name}) => 'Connect ${name}',
			'mcp.oAuthDiscovering' => 'Discovering authorization server…',
			'mcp.oAuthOpenBrowser' => 'Open browser',
			'mcp.oAuthStartConnect' => 'Connect',
			'mcp.oAuthStatusConnected' => 'OAuth connected',
			'mcp.oAuthStatusNeedsAuth' => 'Needs OAuth',
			'mcp.oAuthSubmitCallback' => 'Submit URL',
			'mcp.openHomepage' => 'Open link',
			'mcp.presetDescContext7' => 'Up-to-date library documentation via Context7.',
			'mcp.presetDescFetch' => 'Fetch web pages and convert HTML to markdown for LLMs.',
			'mcp.presetDescMemory' => 'Persistent memory graph for knowledge across sessions.',
			'mcp.presetDescSequentialThinking' => 'Structured step-by-step reasoning for complex problems.',
			'mcp.presetDescTime' => 'Current time, timezone conversion, and date calculations.',
			'mcp.probeChecking' => 'Checking…',
			'mcp.probeNeedsAuth' => 'Needs authorization',
			'mcp.probeOffline' => 'Offline',
			'mcp.probeOfflineHint' => 'Could not reach this MCP server.',
			'mcp.probeRefreshAll' => 'Refresh status',
			'mcp.probeToolCount' => ({required int count}) => '${count} tools',
			'mcp.registryEditTitle' => 'Edit API URL',
			'mcp.registryLoadMore' => 'Load more',
			'mcp.registryOfficial' => 'Official registry',
			'mcp.registryOfficialHint' => 'Official MCP Registry — https://registry.modelcontextprotocol.io',
			'mcp.registryResetConfirm' => ({required String name}) => 'Reset "${name}" to the default API URL?',
			'mcp.registryResetTitle' => 'Reset to default',
			'mcp.registrySearchHint' => 'Search servers (e.g. github)',
			'mcp.registrySmithery' => 'Smithery',
			'mcp.registrySmitheryHint' => 'Smithery — https://api.smithery.ai',
			'mcp.repoApiUrlLabel' => 'API base URL',
			'mcp.repoConfigSaved' => 'Registry API settings saved',
			'mcp.repoDisabledHint' => 'This catalog source is disabled. Enable it under Registries.',
			'mcp.repoResetDefault' => 'Reset default',
			'mcp.repoTestConnection' => 'Test connection',
			'mcp.repoTestFailed' => ({required String error}) => 'Connection failed: ${error}',
			'mcp.repoTestOk' => 'Connection successful',
			'mcp.serverNotFound' => 'MCP server not found',
			'mcp.smitheryApiTokenHint' => 'Smithery API key (Bearer)',
			'mcp.smitheryApiTokenLabel' => 'API token',
			'mcp.smitheryApiTokenSet' => 'token set',
			'mcp.subtitle' => 'Manage MCP servers for agent sessions.',
			'mcp.toolsDialogTitle' => ({required String name}) => '${name} tools',
			'mcp.toolsDone' => 'Done',
			'mcp.toolsEmpty' => 'This server has no tools.',
			'mcp.toolsReload' => 'Reload',
			'mcp.toolsSection' => 'Tools',
			'member.assignFoldersAction' => 'Assign folders…',
			'member.cliInheritHint' => 'Inherit team default',
			'member.detailBrowseConfigDirTitle' => 'Config directory',
			'member.detailEmpty' => 'This member has no config yet in this session, and the team layer is empty.',
			'member.detailLoadError' => 'Failed to read this member\'s config directory.',
			'member.detailNeedsSession' => 'Open a session first',
			'member.detailOpenConfigDir' => 'Open config directory',
			'member.detailOpenConfigDirFailed' => 'Couldn\'t open the config directory in a file manager.',
			'member.detailOpenConfigDirFailedOnHost' => ({required String host}) => 'Couldn\'t open the config directory on ${host}. The remote host may have no desktop file manager.',
			'member.detailOpenInFileManager' => 'Open in file manager',
			'member.detailSectionEmpty' => 'None',
			'member.detailSourceRuntime' => 'Live session config',
			'member.detailSourceTeam' => 'Team-level config (member not launched in this session)',
			'member.detailTabMcp' => 'MCP',
			'member.detailTabOverview' => 'Overview',
			'member.detailTabPlugins' => 'Plugins',
			'member.detailTabSettings' => 'Settings',
			'member.detailTabSkills' => 'Skills',
			'member.detailTitle' => 'Member detail',
			'member.detailViewAction' => 'View member detail',
			'member.effortInheritHint' => 'Inherit team default',
			'member.effortLevel' => 'Member effort override',
			'member.effortLevelSubtitle' => 'Overrides team default when set.',
			'member.extraArgs' => 'Member extra CLI arguments',
			'member.extraArgsSubtitle' => 'Extra flags applied only when this member starts.',
			'member.launchConfigInheritHint' => 'Uses the team\'s default CLI, provider, model, and effort.',
			'member.launchConfigInheritUnset' => 'Team default is not configured yet.',
			'member.launchConfigSubtitle' => 'CLI backend, provider, model, and effort for this member.',
			'member.launchConfigTitle' => 'Model settings',
			'member.launchConfigTypeLabel' => 'Configuration type',
			'member.launchConfigTypePreset' => 'Preset',
			'member.launchOrder' => 'Member launch order',
			'member.name' => 'Member name',
			'member.nameSubtitle' => 'Display only in TeamPilot (sidebar, member list). To define responsibilities and boundaries, edit Responsibilities below.',
			'member.officialClaudeModelHint' => 'Uses your Claude account default model. Manage Official login in Providers settings.',
			'member.personaEmptyNoExpert' => 'Select an expert to see persona text.',
			'member.playbook' => 'Playbook',
			'member.playbookEmpty' => 'No playbook on this expert',
			'member.playbookPresetDeveloperText' => 'Work test-first: before implementing, write a failing test, then make it pass with the smallest diff. Run the relevant tests after each change and report which files changed and why. Do not bundle unrelated edits; stop at agreed checkpoints. If a test-driven-development skill is available, follow it.',
			'member.playbookPresetResearcherText' => 'Clarify intent before digging: restate the question and your assumptions, then investigate breadth-first across the codebase before going deep. Report findings with file paths, relevant symbols, and recommended next steps—propose, do not change production code. If a brainstorming skill is available, use it to frame the problem first.',
			'member.playbookPresetReviewerText' => 'Review in order: (1) confirm tests cover the change; (2) correctness and edge cases; (3) maintainability and consistency with surrounding code. Every finding states file path, line, the problem, and a concrete fix—no vague praise and no nit without a fix. Flag missing tests explicitly.',
			'member.playbookSubtitle' => 'How to execute assigned work: steps, checkpoints, and report format. Sent to the agent as operating instructions.',
			'member.presenceBooting' => 'Starting…',
			'member.presenceConnecting' => 'Connecting…',
			'member.presenceIdle' => 'Idle',
			'member.presenceOffline' => 'Offline',
			'member.presenceWorking' => 'Working',
			'member.presetCustom' => 'Custom configuration',
			'member.presetInheritTeam' => 'Inherit team default',
			'member.presetInheritTeamNone' => 'No team default set',
			'member.presetLabel' => 'Preset',
			'member.presetSelectPreset' => 'Select a preset',
			'member.presetViaPreset' => ({required String presetName}) => '${presetName} (via preset)',
			'member.presetViaTeamDefault' => ({required String presetName}) => '${presetName} (via team default)',
			'member.promptPresetDeveloper' => 'Developer',
			'member.promptPresetDeveloperText' => 'Implement assigned tasks, staying within the agreed scope. Do not expand scope or refactor unrelated code without being asked.',
			'member.promptPresetResearcher' => 'Researcher',
			'member.promptPresetResearcherText' => 'Investigate and report only. Do not change production code unless asked.',
			'member.promptPresetReviewer' => 'Reviewer',
			'member.promptPresetReviewerText' => 'Review code only. Do not modify files unless explicitly asked.',
			'member.promptPresetTeamLead' => 'Team lead',
			'member.promptPresetTeamLeadText' => 'Coordinate the team: break the user\'s request into a task list (each item with scope and acceptance criteria), then assign teammates to implement. Unless blocked, do not do large implementation yourself—you may read code and docs to understand the situation.\nTalk to the user in this session window. When assigning and following up, contact only other teammates (by member name); do not assign work to yourself. After teammates finish, reply to the user with conclusions, relevant files, and next steps.',
			'member.promptPresetsLabel' => 'Presets',
			'member.promptSubtitle' => 'What this member owns and must not do. Written into the agent\'s role definition.',
			'member.quickList' => 'MEMBER QUICK LIST',
			'member.responsibilities' => 'Responsibilities',
			'member.responsibilitiesEmpty' => 'No responsibilities on this expert',
			'member.targetAssignmentInherit' => 'Inherit workspace folders',
			'member.targetAssignmentSubtitle' => ({required Object member}) => 'Which machine ${member} runs on (its assigned workspace folders).',
			'member.targetAssignmentTitle' => 'Member machine',
			'member.terminalNotStartedTitle' => 'Terminal not started — tap to launch',
			'member.terminalReclaimedBody' => 'Tap to reconnect (the session resumes)',
			'member.terminalReclaimedTitle' => 'Terminal reclaimed to save memory',
			'mixed.workspaceCreateSessionBlocked' => 'Confirm machine assignment in Team Settings before starting a conversation in this mixed workspace.',
			'mixed.workspaceLeadPlacementInvalid' => 'Team lead must be assigned to the local machine when this workspace has a local folder.',
			'mixed.workspaceMemberAssignmentConfirm' => 'Start team',
			'mixed.workspaceMemberAssignmentIncomplete' => 'Confirm machine assignment once before starting this team in a mixed workspace.',
			'mixed.workspaceMemberAssignmentSubtitle' => 'Select a machine on the left, then use + / − to place each member\'s instances on it.',
			'mixed.workspaceMemberAssignmentTitle' => 'Assign members to machines',
			'mixed.workspaceMemberPlacementOnMachine' => ({required int count}) => '${count} on this machine',
			'mixed.workspaceMemberPlacementProgress' => ({required int placed, required int total}) => '${placed} / ${total} assigned',
			'mixed.workspacePersonalLaunchBlockedHint' => 'This is a mixed workspace. Switch to a team tab to start conversations and confirm machine assignment.',
			'mixed.workspaceRequiresTeamLaunch' => 'Mixed workspaces can only be started with a team identity. Switch to a team and confirm machine assignment in Team Settings.',
			'mixed.workspaceSessionLaunchBlocked' => 'Machine assignment for this conversation is no longer valid. Confirm assignment in Team Settings and start a new conversation.',
			'my.expertsCreate' => 'New Expert',
			'my.expertsDelete' => 'Delete',
			'my.expertsDeleteConfirm' => ({required Object name}) => 'Delete expert "${name}"? This cannot be undone.',
			'my.expertsDeleteReferenced' => ({required Object name}) => 'Cannot delete "${name}" — it is still referenced by one or more teams. Reassign those roster slots first.',
			'my.expertsEdit' => 'Edit',
			'my.expertsEmptyHint' => 'Create a local expert persona to reuse across teams.',
			'my.expertsEmptyTitle' => 'No experts yet',
			'my.expertsNav' => 'My Experts',
			'my.expertsSubtitle' => 'Manage your local expert personas',
			'my.expertsTitle' => 'My Experts',
			'my.expertsUpload' => 'Upload',
			'my.teamsCreatedAt' => ({required Object date}) => 'Created ${date}',
			'my.teamsEmptyHint' => 'Create a team to manage members, skills, and plugins.',
			'my.teamsEmptyTitle' => 'No teams yet',
			'my.teamsMemberCount' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '1 member', other: '${count} members', ), 
			'my.teamsNav' => 'My Teams',
			'my.teamsSubtitle' => 'Manage your local team configurations',
			'my.teamsTitle' => 'My Teams',
			'my.teamsUpload' => 'Upload',
			'notification.centerTitle' => 'Notifications',
			'notification.clearAll' => 'Clear',
			'notification.delete' => 'Delete',
			'notification.empty' => 'No notifications',
			'notification.historySection' => 'History',
			'notification.markAllRead' => 'Mark all as read',
			'notification.markRead' => 'Mark as read',
			'notification.ongoingSection' => 'Ongoing',
			'notification.timeDaysAgo' => ({required int days}) => '${days} d ago',
			'notification.timeHoursAgo' => ({required int hours}) => '${hours} h ago',
			'notification.timeJustNow' => 'Just now',
			'notification.timeMinutesAgo' => ({required int minutes}) => '${minutes} min ago',
			'onboarding.appearanceSubtitle' => 'You can change these later in Settings → Layout.',
			'onboarding.appearanceTitle' => 'Choose language and appearance',
			'onboarding.cliFound' => 'CLI found',
			'onboarding.cliNotFound' => 'Not on PATH',
			'onboarding.cliRedetect' => 'Scan again',
			'onboarding.cliScanning' => 'Scanning PATH for CLI tools…',
			'onboarding.cliSubtitle' => 'Locate executables used to launch sessions. Install missing ones, or set a path later in Settings.',
			'onboarding.cliTitle' => 'Detect CLI tools',
			'onboarding.defaultPresetDefaultName' => 'Default',
			'onboarding.defaultPresetEmpty' => 'No providers to choose from. Skip this step or add providers in Settings.',
			'onboarding.defaultPresetModelHint' => 'Primary model for this preset',
			'onboarding.defaultPresetSelectExisting' => 'Use existing preset',
			'onboarding.defaultPresetSubtitle' => 'Personal workspaces and team default launch configs will use this CLI preset.',
			'onboarding.defaultPresetTitle' => 'Configure default launch preset',
			'onboarding.getStarted' => 'Get started',
			'onboarding.next' => 'Next',
			'onboarding.previous' => 'Previous',
			'onboarding.progress' => ({required int current, required int total}) => 'Step ${current} of ${total}',
			'onboarding.providerImportEmpty' => 'No providers detected. You can configure them later in Settings.',
			'onboarding.providerImportFailed' => 'Import failed',
			'onboarding.providerImportRescan' => 'Scan again',
			'onboarding.providerImportResults' => 'Import results',
			'onboarding.providerImportSubtitle' => 'Scan local CLI configs for existing provider settings.',
			'onboarding.providerImportTitle' => 'Import CLI providers',
			'onboarding.rerunSetup' => 'Run setup wizard again',
			'onboarding.skip' => 'Skip',
			'onboarding.sshSubtitle' => 'Android runs AI CLIs on a remote host over SSH.',
			'onboarding.sshTitle' => 'Configure SSH connection',
			'onboarding.stepAppearance' => 'Language & theme',
			'onboarding.stepCli' => 'CLI tools',
			'onboarding.stepDefaultPreset' => 'Default preset',
			'onboarding.stepProviderImport' => 'Import providers',
			'onboarding.stepSsh' => 'SSH',
			'onboarding.title' => 'First-time setup',
			'onboarding.workHomeSubtitle' => 'Connect Termux on this device or a remote SSH host before detecting AI CLIs.',
			'onboarding.workHomeTitle' => 'Choose work environment',
			'opencode.credentialsActionFailed' => 'Could not update credentials',
			'opencode.credentialsActionSuccess' => 'Credentials updated',
			'opencode.credentialsImportFile' => 'Import auth.json…',
			'opencode.credentialsImportGlobal' => 'Import from opencode auth',
			'opencode.credentialsLogin' => 'Sign in with provider',
			'opencode.credentialsRevoke' => 'Sign out',
			'opencode.credentialsRevokeConfirm' => ({required String name}) => 'Sign out and remove saved credentials for ${name}?',
			'opencode.permissionAllowAlways' => 'Always allow',
			'opencode.permissionAllowOnce' => 'Allow once',
			'opencode.permissionAnswerFailed' => 'Couldn\'t submit your decision. Try again or answer in the Terminal.',
			'opencode.permissionAnswerInTerminal' => 'Answer in terminal',
			'opencode.permissionReject' => 'Reject',
			'opencode.permissionTitle' => 'OpenCode needs your permission',
			'plugin.cliSupportFully' => ({required String cli}) => '${cli}: Fully supported',
			'plugin.cliSupportNotApplicable' => ({required String cli}) => '${cli}: Not applicable',
			'plugin.cliSupportPartial' => ({required String cli, required String dropped}) => '${cli}: Partially supported (${dropped} dropped)',
			'plugin.componentAgents' => 'agents',
			'plugin.componentApps' => 'apps',
			'plugin.componentCommands' => 'commands',
			'plugin.componentHooks' => 'hooks',
			'plugin.componentMcp' => 'MCP',
			'plugin.componentRules' => 'rules',
			'plugin.componentSkills' => 'skills',
			'plugins.cardDetails' => 'Details',
			'plugins.cardInstall' => 'Install',
			'plugins.cardInstalled' => 'Installed',
			'plugins.cardUninstall' => 'Uninstall',
			'plugins.cardUpdate' => 'Update',
			'plugins.cardViewSource' => 'View source',
			'plugins.catalogAdoption' => 'Installs',
			'plugins.catalogCardNoDescription' => 'None',
			'plugins.checkUpdates' => 'Check updates',
			'plugins.checkingUpdates' => 'Checking…',
			'plugins.discoveryEmpty' => 'No matching plugins',
			'plugins.discoverySyncing' => 'Checking marketplaces for updates and syncing plugins in the background…',
			'plugins.filterAll' => 'All',
			'plugins.filterInstalled' => 'Installed',
			'plugins.filterMarketplaceAll' => 'All marketplaces',
			'plugins.filterUninstalled' => 'Not installed',
			'plugins.goDiscovery' => 'Browse marketplace',
			'plugins.importFromDisk' => 'Import from disk',
			'plugins.importNothing' => 'No unmanaged plugins found.',
			'plugins.importTitle' => 'Import unmanaged plugins',
			'plugins.installFromZip' => 'Install from ZIP',
			'plugins.installedCount' => ({required int count}) => '${count} installed',
			'plugins.local' => 'local',
			'plugins.marketplaceAdd' => 'Add marketplace',
			'plugins.marketplaceBranch' => 'Branch',
			'plugins.marketplaceDisplayName' => 'Display name',
			'plugins.marketplaceInvalidUrl' => 'Please enter a valid GitHub repository URL.',
			'plugins.marketplaceRemove' => 'Remove marketplace',
			'plugins.marketplaceRemoveConfirm' => ({required String url}) => 'Remove marketplace ${url}? Installed plugins are kept.',
			'plugins.marketplaceUrl' => 'GitHub repository URL',
			'plugins.marketplaceUrlHint' => 'https://github.com/owner/marketplace',
			'plugins.marketplacesEmpty' => 'No marketplaces configured',
			'plugins.navDiscovery' => 'Discovery',
			'plugins.navInstalled' => 'Installed',
			'plugins.navMarketplaces' => 'Marketplaces',
			'plugins.noInstalled' => 'No plugins installed',
			'plugins.noInstalledHint' => 'Add a marketplace and install plugins from the Discovery tab.',
			'plugins.searchPlaceholder' => 'Search plugins',
			'plugins.sidebarLabel' => 'Plugins',
			'plugins.subtitle' => 'Manage Claude Code-style plugin bundles',
			'plugins.title' => 'Plugins',
			'plugins.uninstallConfirm' => ({required String name, required int n}) => 'Uninstall ${name}? This may affect ${n} team(s).',
			'plugins.uninstallImpactList' => 'Affected teams:',
			'plugins.uninstallSuccess' => ({required String name}) => 'Uninstalled ${name}',
			'plugins.updateAll' => ({required int count}) => 'Update all (${count})',
			'plugins.updateAvailable' => 'Update available',
			'provider.provider' => 'Provider',
			'provider.credentialsAuthenticated' => 'Authenticated',
			'provider.credentialsBrowserOpened' => 'Browser opened for authorization',
			'provider.credentialsDeviceCodeHint' => 'Enter this one-time code in the browser (expires in 15 minutes)',
			'provider.credentialsDeviceCodeTitle' => 'Device code',
			'provider.credentialsFailureDestinationExists' => 'Credentials already exist. Sign out first or import again to replace.',
			'provider.credentialsFailureInvalidCredential' => 'Credential format is invalid or incomplete',
			'provider.credentialsFailureLoginFailed' => ({required int exitCode}) => 'Login failed (exit code ${exitCode})',
			'provider.credentialsFailureLoginProcessError' => ({required String detail}) => 'Could not run login command: ${detail}',
			'provider.credentialsFailurePathRequired' => 'Choose a file or directory first',
			'provider.credentialsFailureProviderEntryMissing' => ({required String providerId, required String path}) => 'No credential for "${providerId}" in ${path}',
			'provider.credentialsFailureProviderEntryMissingWithKeys' => ({required String providerId, required String path, required String keys}) => 'No credential for "${providerId}" in ${path}. Available: ${keys}',
			'provider.credentialsFailureProviderNotFound' => 'Provider not found',
			'provider.credentialsFailureRequiredFileMissing' => ({required String path}) => 'Required file missing: ${path}',
			'provider.credentialsFailureRevokeFailed' => 'Could not sign out or remove credentials',
			'provider.credentialsFailureServiceUnavailable' => 'Credential service is not available',
			'provider.credentialsFailureSourceMissing' => ({required String path}) => 'Credential file not found: ${path}',
			'provider.credentialsFailureSourceUnreadable' => ({required String path}) => 'Could not read credential file: ${path}',
			'provider.credentialsFailureStatusRefreshFailed' => 'Credentials updated but status could not be refreshed',
			'provider.credentialsFailureUnsupported' => 'This credential action is not supported',
			'provider.credentialsFailureVerifyFailed' => 'Credentials were saved but verification failed',
			'provider.credentialsReopenBrowser' => 'Reopen browser',
			'provider.credentialsUnauthenticated' => 'Unauthenticated',
			'provider.detailSubtitle' => ({required String type, required int count}) => '${type} provider · ${count} models',
			'provider.effortLevel' => 'Reasoning effort',
			'provider.list' => 'Provider List',
			'provider.listModelCount' => ({required int count}) => '${count} models',
			'provider.modelBackgroundTier' => 'Use for background/fast tasks (Claude haiku tier)',
			'provider.name' => 'Provider name',
			'provider.type' => 'Provider type',
			'provider.typeHint' => 'openai, claude, or custom',
			'qoder.contextWindow' => 'Context window (tokens)',
			'qoder.contextWindowHint' => 'Leave empty to use the model default.',
			'qoder.credentialsActionFailed' => 'The Qoder action failed',
			'qoder.credentialsCancel' => 'Cancel',
			'qoder.credentialsDone' => 'Done',
			'qoder.credentialsLogin' => 'Sign in',
			'qoder.credentialsLoginExited' => 'Qoder CLI exited. Close this dialog and start the sign-in again.',
			'qoder.credentialsLoginFailed' => ({required String error}) => 'Could not start the login terminal: ${error}',
			'qoder.credentialsLoginIntro' => 'Complete the sign-in in the terminal below. The CLI opens a browser tab; if it does not, open the URL it prints. This is also where you switch accounts.',
			'qoder.credentialsLoginStarting' => 'Starting Qoder CLI…',
			'qoder.credentialsLoginTitle' => 'Sign in to Qoder',
			'qoder.credentialsRelaunch' => 'Relaunch',
			'qoder.credentialsSignedIn' => 'Signed in',
			'remote.cliMachineReadinessAdapterLabel' => ({required String cli}) => '${cli} ACP adapter',
			'remote.cliMachineReadinessFailed' => ({required String cli, required String message}) => '${cli}: ${message}',
			'remote.cliMachineReadinessInstallHint' => 'Use Install for each missing CLI, or set a manual path in target settings.',
			'remote.cliMachineReadinessMissing' => ({required String cli}) => '${cli} not found — install or set a manual path',
			'remote.cliMachineReadinessProbing' => 'Checking…',
			'remote.cliMachineReadinessReady' => ({required String cli, required String path}) => '${cli} ready at ${path}',
			'remote.cliMachineReadinessTitle' => 'Required CLIs on this machine',
			'remote.connectionsSubtitle' => 'Manage the hosts saved on this device, connect, and switch your work home. Available even while offline.',
			'remote.connectionsTitle' => 'Remote connections',
			'remote.directoryBrowserEmpty' => 'No subdirectories here',
			'remote.directoryBrowserError' => 'Couldn\'t open the remote directory. You can still type a path below.',
			'remote.directoryBrowserTitle' => 'Browse remote directory',
			'remote.directoryBrowserTypePathHint' => '~/work/workspace',
			'remote.directoryBrowserTypePathLabel' => 'Or type a path',
			'remote.directoryBrowserUpOneLevel' => 'Up one level',
			'remote.directoryBrowserUseThisDirectory' => 'Use this directory',
			'remote.directoryBrowserUseTypedPath' => 'Use path',
			'resource.managerAppProcess' => 'App',
			'resource.managerColumnCpu' => 'CPU',
			'resource.managerColumnMemory' => 'Memory',
			'resource.managerColumnName' => 'Name',
			'resource.managerEmptyTree' => 'Nothing running right now.',
			'resource.managerKill' => 'Kill',
			'resource.managerKillAll' => 'Kill all',
			'resource.managerKillAllConfirmBody' => 'This disconnects every running session and shell in the list.',
			'resource.managerKillAllConfirmTitle' => 'Kill all running sessions?',
			'resource.managerKillFailed' => 'Could not kill session.',
			'resource.managerMetricsError' => 'Could not refresh process metrics.',
			'resource.managerPanelTitle' => 'Resource Manager - Sessions',
			'resource.managerRefresh' => 'Refresh',
			'resource.managerSpace' => 'Space',
			'resource.managerSpaceBeta' => 'Beta',
			'resource.managerSpaceNotScanned' => 'Does not scan workspace disk usage.',
			'resource.managerSystemMemoryPercent' => ({required String percent}) => '${percent}% system memory',
			'resource.managerTerminalsCount' => ({required int count}) => '${count} running sessions',
			'resource.managerTitle' => 'Resource Manager',
			'resource.managerTooltip' => ({required int count}) => 'Resource Manager - ${count} running sessions',
			_ => null,
		} ?? switch (path) {
			'resource.managerTooltipHint' => 'Running sessions across all workspaces.',
			'rtk.bashOnlyHint' => 'Only applies to Agent Bash tool calls. Built-in Read, Grep, and Glob are not rewritten.',
			'rtk.settingsDescription' => 'Compress Agent Bash command output before it reaches the model (requires rtk and jq on PATH).',
			'rtk.settingsEnableTitle' => 'Enable RTK',
			'rtk.settingsInstallLink' => 'Install guide',
			'rtk.settingsStatusTitle' => 'Host status',
			'rtk.settingsTitle' => 'RTK token savings',
			'rtk.statusInstalled' => ({required String version}) => 'rtk ${version} ready',
			'rtk.statusInstalledGeneric' => 'rtk ready',
			'rtk.statusJqMissing' => 'jq not found on PATH',
			'rtk.statusNotFound' => 'rtk not found on PATH',
			'rtk.statusVersionTooOld' => ({required String version}) => 'rtk ${version} is too old (need >= 0.23.0)',
			'run.acceptRecommendation' => 'Add suggested configuration to launch.json',
			'run.action' => 'Run',
			'run.addConfiguration' => 'Add configuration',
			'run.alreadyRunningMessage' => 'Restart the running session, or start a new instance?',
			'run.alreadyRunningTitle' => 'Configuration already running',
			'run.apply' => 'Apply',
			'run.build' => 'Build',
			'run.buildUnavailable' => 'Build is not available yet',
			'run.clearExited' => 'Clear exited sessions',
			'run.compoundConfiguration' => ({required String name}) => '${name} (compound)',
			'run.configurationName' => 'Name',
			'run.configurationTooltip' => 'Run configuration',
			'run.configurationType' => 'Type',
			'run.configurationsEmpty' => 'No launch configurations yet',
			'run.configureLaunchItems' => 'Configure launch configurations',
			'run.debug' => 'Debug',
			'run.debugUnavailable' => 'Debug is not available yet',
			'run.deleteConfiguration' => 'Delete',
			'run.deleteConfigurationConfirm' => ({required String name}) => 'Delete configuration "${name}"?',
			'run.discard' => 'Discard',
			'run.discardChangesMessage' => 'You have unsaved changes to this configuration. Apply them, discard them, or cancel?',
			'run.discardChangesTitle' => 'Discard changes?',
			'run.editConfigurations' => 'Edit configuration',
			'run.editorSelectConfiguration' => 'Select configuration',
			'run.emptyOutputHint' => 'Run a configuration to see output here',
			'run.errorNoConfiguration' => 'No configuration selected',
			'run.errorNoFolder' => 'No workspace folder',
			'run.errorSshProfileMissing' => 'SSH profile not found for this run target',
			'run.errorSshSpawnerMissing' => 'SSH process execution is not configured',
			'run.executeScriptFile' => 'Script file',
			'run.executeScriptText' => 'Script text',
			'run.fieldActivateToolWindow' => 'Activate tool window',
			'run.fieldAllowMultipleInstances' => 'Allow multiple instances',
			'run.fieldArgs' => 'Arguments',
			'run.fieldCommand' => 'Command',
			'run.fieldCwd' => 'Working directory',
			'run.fieldEnv' => 'Environment variables',
			'run.fieldExecute' => 'Execute',
			'run.fieldExecuteInTerminal' => 'Execute in the terminal',
			'run.fieldFocusToolWindow' => 'Focus tool window',
			'run.fieldInterpreterOptions' => 'Interpreter options',
			'run.fieldInterpreterPath' => 'Interpreter path',
			'run.fieldInterpreterPathEditTooltip' => 'Edit interpreter path',
			'run.fieldScriptOptions' => 'Script options',
			'run.fieldScriptPath' => 'Script path',
			'run.fieldScriptText' => 'Script text',
			'run.fieldShell' => 'Run in shell',
			'run.loadingOutput' => 'Loading run output…',
			'run.moreActions' => 'More run actions',
			'run.newInstance' => 'New instance',
			'run.noSessions' => 'No run sessions',
			'run.openLaunchJson' => 'Open launch.json',
			'run.pickLaunchType' => 'Select launch type',
			'run.refreshDiscover' => 'Refresh discover recommendations',
			'run.restart' => 'Restart',
			'run.selectConfiguration' => 'Launch',
			'run.selectFolder' => 'Select folder',
			'run.stop' => 'Stop',
			'run.stopAndClose' => 'Stop and close',
			'run.stopAndDelete' => 'Stop and delete',
			'run.stopSessionMessage' => ({required String name}) => '"${name}" is still running. Stop it and close this tab?',
			'run.stopSessionTitle' => 'Stop running session?',
			'run.suggestedConfiguration' => ({required String name}) => '${name} (Suggested)',
			'run.typeShellScript' => 'Shell Script',
			'run.typeUnavailable' => ({required String type}) => 'Launch type "${type}" is not available on this target',
			'run.typeUnavailableRemote' => ({required String type}) => 'Launch type "${type}" is not available on remote targets',
			'run.typeUnknown' => ({required String type}) => 'Unknown launch type: ${type}',
			'run.validationActivateToolWindowMustBeBoolean' => 'Activate tool window must be a boolean',
			'run.validationAllowMultipleInstancesMustBeBoolean' => 'Allow multiple instances must be a boolean',
			'run.validationArgsMustBeStringList' => 'Arguments must be a list of strings',
			'run.validationCommandRequired' => 'Command is required',
			'run.validationConfigurationMustBeMap' => 'Configuration must be a map',
			'run.validationCwdMustBeString' => 'Working directory must be a string',
			'run.validationEnvMustBeStringMap' => 'Environment must be a map of strings',
			'run.validationExecuteInTerminalMustBeBoolean' => 'Execute in the terminal must be a boolean',
			'run.validationExecuteInvalid' => 'Execute must be Script file or Script text',
			'run.validationExecuteRequired' => 'Execute mode is required',
			'run.validationFocusToolWindowMustBeBoolean' => 'Focus tool window must be a boolean',
			'run.validationInterpreterPathMustBeString' => 'Interpreter path must be a string',
			'run.validationScriptPathRequired' => 'Script path is required',
			'run.validationScriptTextRequired' => 'Script text is required',
			'run.validationShellMustBeBoolean' => 'Shell must be a boolean',
			'session.session' => 'Session',
			'session.archiveEmpty' => 'No archived conversations',
			'session.archiveEntryTooltip' => 'Archived conversations',
			'session.archiveTitle' => 'Archive',
			'session.duplicateFailed' => 'Failed to duplicate conversation',
			'session.duplicated' => 'Conversation duplicated',
			'session.failedTitle' => 'Couldn\'t start session',
			'session.followUpAddPlaceholder' => 'Add a follow-up',
			'session.followUpDelete' => 'Delete',
			'session.followUpEdit' => 'Edit',
			'session.followUpMoveUp' => 'Move up',
			'session.followUpQueued' => ({required int count}) => '${count} Queued',
			'session.followUpResume' => 'Resume',
			'session.forkFailed' => 'Failed to fork conversation',
			'session.groupAddSessionsTitle' => 'Add conversations',
			'session.groupAddSessionsTooltip' => 'Add conversations',
			'session.groupCreateTitle' => 'New Group',
			'session.groupCreateTooltip' => 'New group',
			'session.groupEmpty' => 'No conversations',
			'session.groupMenuRemove' => 'Remove group',
			'session.groupNameLabel' => 'Group name',
			'session.groupRenameTitle' => 'Rename Group',
			'session.historyBackgroundRunning' => 'Background work running…',
			'session.historyComposeHint' => 'Continue this conversation… @ reference files, / invoke skills',
			'session.historyComposeStop' => 'Stop generating',
			'session.historyContinueSaveFailed' => 'Couldn\'t save continue settings.',
			'session.historyEmpty' => 'No prior messages for this member yet.',
			'session.historyError' => 'Couldn\'t load conversation history.',
			'session.historyLoadOlderHint' => 'Scroll up for earlier messages',
			'session.historyLoading' => 'Loading conversation history…',
			'session.historyMailboxQueued' => ({required int count}) => '${count} Queued',
			'session.historyMailboxQueuedDismiss' => 'Dismiss',
			'session.historyRefreshing' => 'Refreshing conversation…',
			'session.historyRetry' => 'Retry',
			'session.historyRoleAssistant' => 'Assistant',
			'session.historyRoleSystem' => 'System',
			'session.historyRoleUser' => 'You',
			'session.historyRunning' => 'Running…',
			'session.historySoftReloadError' => 'Couldn\'t refresh conversation history.',
			'session.historyStarting' => 'Starting…',
			'session.historyToolTurn' => 'Tool',
			'session.idleNotificationSubtitle' => 'Ready for your next message',
			'session.idleNotificationTitle' => 'Agent ready',
			'session.launchErrorHideDetails' => 'Hide details',
			'session.launchErrorReviewDetails' => 'View details',
			'session.launchMissingTeamMember' => 'Team member is not available. Select a team and try again.',
			'session.launchMissingWorkspace' => 'Workspace not found for this session.',
			'session.openToSide' => 'Open to the Side',
			'session.pageSubtitle' => 'Configure shell session launch, terminal behavior, and storage backend.',
			'session.readyHint' => 'Describe what you want in everyday language — no terminal commands needed.',
			'session.readySubtitle' => ({required String memberName}) => 'Start a conversation with ${memberName} in this workspace.',
			'session.readySubtitleGeneric' => 'Start a conversation in this workspace.',
			'session.readyTitle' => 'Ready to chat',
			'session.remoteProvisionFailed' => 'Remote setup failed',
			'session.remoteProvisionPreparing' => 'Preparing remote environment…',
			'session.remoteProvisionPreparingOnHost' => ({required String host}) => 'Preparing remote environment (${host})',
			'session.remoteProvisionTitle' => ({required String member, required String host}) => 'Preparing ${member} on ${host}',
			'session.retryButton' => 'Try again',
			'session.sortCreatedDesc' => 'Date created',
			'session.sortManual' => 'Manual order',
			'session.sortRecentlyUpdated' => 'Recently updated',
			'session.sortTooltip' => 'Sort conversations',
			'session.startButton' => 'Start conversation',
			'session.starting' => 'Starting session…',
			'session.tabBarTitle' => 'Session tab bar',
			'session.tabBarVisibilityHint' => 'Show the tab strip above the workbench center column.',
			'session.titleCopySuffix' => '(copy)',
			'session.workbenchViewChat' => 'Chat',
			'session.workbenchViewTerminal' => 'Terminal',
			'sessionUsage.accountAll' => 'All accounts',
			'sessionUsage.autoScan' => 'Auto-scan session logs',
			'sessionUsage.autoScanHint' => ({required int minutes}) => 'Scans when this page opens, then every ${minutes} minutes in the background.',
			'sessionUsage.cacheHit' => ({required String percent}) => 'Hit ${percent}',
			'sessionUsage.cacheRead' => 'Cache read',
			'sessionUsage.cacheReadShare' => ({required String percent}) => 'Cache read share ${percent}',
			'sessionUsage.cacheShort' => 'Cache',
			'sessionUsage.cacheWrite' => ({required String tokens}) => 'Write ${tokens}',
			'sessionUsage.cancelSync' => 'Cancel',
			'sessionUsage.cancelSyncTooltip' => 'Cancel usage sync',
			'sessionUsage.cancelling' => 'Cancelling…',
			'sessionUsage.chartAverage' => ({required String tokens}) => '${tokens} / day',
			'sessionUsage.chartSubtitle' => 'Stacked by CLI',
			'sessionUsage.chartTitle' => 'Last 7 days',
			'sessionUsage.chartTotal' => ({required String tokens}) => '${tokens} total',
			'sessionUsage.cliAll' => 'All',
			'sessionUsage.cliBreakdown' => 'CLI distribution',
			'sessionUsage.columnReset' => 'Reset to default',
			'sessionUsage.columnSettings' => 'Columns',
			'sessionUsage.cost' => 'Cost',
			'sessionUsage.costPartial' => ({required int count}) => 'Partial: ${count} events unpriced',
			'sessionUsage.costPricedUnpriced' => ({required int priced, required int unpriced}) => '${priced} priced · ${unpriced} unpriced',
			'sessionUsage.costShort' => 'Cost',
			'sessionUsage.costUnpriced' => 'Unpriced',
			'sessionUsage.dataSource' => 'Data source',
			'sessionUsage.dismiss' => 'Dismiss',
			'sessionUsage.emptyBody' => 'Run a Claude, Codex, or OpenCode session, then sync. You can also reset filters.',
			'sessionUsage.emptyTitle' => 'No token usage yet',
			'sessionUsage.endTime' => 'End time',
			'sessionUsage.groupBy' => 'Group by',
			'sessionUsage.groupCli' => 'CLI',
			'sessionUsage.groupCount' => ({required int count}) => '${count} groups',
			'sessionUsage.groupMember' => 'Member',
			'sessionUsage.groupModel' => 'Model',
			'sessionUsage.groupName' => 'Name',
			'sessionUsage.groupSession' => 'Session',
			'sessionUsage.heatmapLess' => 'Less',
			'sessionUsage.heatmapMetricHitRate' => 'Hit rate',
			'sessionUsage.heatmapMetricTokens' => 'Tokens',
			'sessionUsage.heatmapMore' => 'More',
			'sessionUsage.heatmapShowEarlier' => 'Show earlier',
			'sessionUsage.heatmapShowLess' => 'Show less',
			'sessionUsage.heatmapSpanSummary' => ({required String tokens, required String requests, required String cost}) => '${tokens} tokens · ${requests} requests · ${cost}',
			'sessionUsage.heatmapSubtitle' => 'Last 53 weeks · hover or long-press a day',
			'sessionUsage.heatmapTitle' => 'Usage heatmap',
			'sessionUsage.inputShort' => 'Input',
			'sessionUsage.inputTokens' => 'Input',
			'sessionUsage.intervalMinutes' => ({required int minutes}) => 'Every ${minutes} min',
			'sessionUsage.lastSync' => ({required String time}) => 'Last sync ${time}',
			'sessionUsage.liveEnd' => 'End time follows now',
			'sessionUsage.loadFailed' => 'Could not load usage data.',
			'sessionUsage.loading' => 'Loading usage…',
			'sessionUsage.maintenanceCompact' => 'Compact events',
			'sessionUsage.maintenanceCompactHint' => 'Merge superseded revisions. Current events are kept.',
			'sessionUsage.maintenanceCompacted' => 'Usage storage compacted.',
			'sessionUsage.maintenanceEntry' => 'Storage and Cursor maintenance',
			'sessionUsage.maintenanceFailed' => 'Couldn\'t compact usage storage.',
			'sessionUsage.maintenanceFull' => 'Full rescan',
			'sessionUsage.maintenanceFullDone' => 'Full usage rescan complete.',
			'sessionUsage.maintenanceFullHint' => 'Rebuild all sources and scan every session. Use this if history is missing.',
			'sessionUsage.maintenanceLines' => ({required int lines, required int events}) => '${lines} lines · ${events} events',
			'sessionUsage.maintenanceSize' => ({required String size}) => '${size} KB',
			'sessionUsage.maintenanceTitle' => 'Usage storage',
			'sessionUsage.managePricing' => 'Manage pricing',
			'sessionUsage.mixedCli' => 'Mixed',
			'sessionUsage.nav' => 'Token usage',
			'sessionUsage.neverSynced' => 'Not synced yet',
			'sessionUsage.nextPage' => 'Next page',
			'sessionUsage.noData' => 'No data',
			'sessionUsage.outputShort' => 'Output',
			'sessionUsage.outputTokens' => 'Output',
			'sessionUsage.pageOf' => ({required int page, required int pages}) => 'Page ${page} / ${pages}',
			'sessionUsage.pageRange' => ({required int start, required int end, required int total}) => '${start}–${end} of ${total} groups',
			'sessionUsage.prevPage' => 'Previous page',
			'sessionUsage.pricingAdd' => 'Add rule',
			'sessionUsage.pricingCacheRead' => 'Cache read',
			'sessionUsage.pricingCacheWrite' => 'Cache write',
			'sessionUsage.pricingCacheWrite1h' => '1h cache write',
			'sessionUsage.pricingCorrupt' => 'Pricing file was unreadable. Using built-in prices.',
			'sessionUsage.pricingDelete' => 'Delete',
			'sessionUsage.pricingEffectiveDate' => 'Effective date',
			'sessionUsage.pricingEffectiveHint' => 'YYYY-MM-DD',
			'sessionUsage.pricingEmpty' => 'No custom rules. Built-in prices are active.',
			'sessionUsage.pricingFailed' => 'Couldn\'t save pricing.',
			'sessionUsage.pricingHint' => 'USD per 1M tokens. User rules override built-in reference prices.',
			'sessionUsage.pricingInput' => 'Input',
			'sessionUsage.pricingInvalid' => 'Check model and price values.',
			'sessionUsage.pricingModel' => 'Model',
			'sessionUsage.pricingOutput' => 'Output',
			'sessionUsage.pricingReset' => 'Reset defaults',
			'sessionUsage.pricingResetConfirm' => 'Remove all custom pricing rules?',
			'sessionUsage.pricingSave' => 'Save',
			'sessionUsage.pricingSaved' => 'Pricing saved',
			'sessionUsage.pricingTitle' => 'Model pricing',
			'sessionUsage.progressTitle' => 'Usage sync',
			'sessionUsage.rangeAll' => 'All time',
			'sessionUsage.rangeFourteenDays' => 'Last 14 days',
			'sessionUsage.rangeHint' => 'Date and time, up to 30 days',
			'sessionUsage.rangeInvalidOrder' => 'Start time cannot be later than end time',
			'sessionUsage.rangeLast24Hours' => 'Last 24 hours',
			'sessionUsage.rangeSevenDays' => 'Last 7 days',
			'sessionUsage.rangeThirtyDays' => 'Last 30 days',
			'sessionUsage.rangeToday' => 'Today',
			'sessionUsage.rangeTooLong' => 'Range cannot exceed 30 days',
			'sessionUsage.requests' => 'Requests',
			'sessionUsage.requestsSessions' => ({required int requests, required int sessions}) => '${requests} requests · ${sessions} sessions',
			'sessionUsage.requestsShort' => 'Req.',
			'sessionUsage.resetFilters' => 'Reset filters',
			'sessionUsage.retry' => 'Retry',
			'sessionUsage.rowsPerPage' => 'Rows per page',
			'sessionUsage.scanInterval' => 'Scan interval',
			'sessionUsage.scopeHint' => 'Local + SSH · attributed by TeamPilot session',
			'sessionUsage.searchHint' => 'Search sessions, members, models',
			'sessionUsage.sessions' => 'Sessions',
			'sessionUsage.sessionsShort' => 'Sess.',
			'sessionUsage.settings' => 'Usage settings',
			'sessionUsage.share' => ({required String percent}) => '${percent} of total',
			'sessionUsage.shareShort' => 'Share',
			'sessionUsage.showing' => ({required int shown, required int total}) => 'Showing ${shown} / ${total} rows',
			'sessionUsage.simpleSeat' => 'Simple session',
			'sessionUsage.sortAscending' => 'Sort ascending',
			'sessionUsage.sortDescending' => 'Sort descending',
			'sessionUsage.startTime' => 'Start time',
			'sessionUsage.storage' => 'Storage',
			'sessionUsage.sync' => 'Sync',
			'sessionUsage.syncCancelled' => 'Usage sync cancelled.',
			'sessionUsage.syncFatal' => 'Sync failed. Showing cached data.',
			'sessionUsage.syncFull' => 'Full sync',
			'sessionUsage.syncFullHint' => 'Rescan every transcript from scratch',
			'sessionUsage.syncIncremental' => 'Incremental sync',
			'sessionUsage.syncIncrementalHint' => 'Scan only files changed since the last sync',
			'sessionUsage.syncNow' => 'Sync now',
			'sessionUsage.syncPartial' => ({required int count}) => '${count} sources failed to sync. Showing cached data.',
			'sessionUsage.syncPreparing' => 'Preparing scan…',
			'sessionUsage.syncProgress' => ({required int done, required int total, required int inserted}) => 'Scanning ${done}/${total} sessions · ${inserted} new events',
			'sessionUsage.syncTooltip' => 'Scan CLI transcripts for new usage',
			'sessionUsage.syncedJustNow' => 'Synced just now',
			'sessionUsage.syncedToast' => 'Usage synced',
			'sessionUsage.syncing' => 'Syncing',
			'sessionUsage.tableEmpty' => 'No matching rows',
			'sessionUsage.tableEmptyHint' => 'Try a different search or reset the filters.',
			'sessionUsage.title' => 'Token usage',
			'sessionUsage.today' => 'Today',
			'sessionUsage.totalShort' => 'Total',
			'sessionUsage.totalTokens' => 'Total tokens',
			'sessionUsage.unknownModel' => 'Unknown model',
			'sessionUsage.unknownSession' => 'Unknown session',
			'sessionUsage.unknownTeam' => 'Unassigned team',
			'shortcuts.categoryCompose' => 'Compose',
			'shortcuts.categoryMeta' => 'General',
			'shortcuts.categoryNavigation' => 'Navigation',
			'shortcuts.categoryRun' => 'Run',
			'shortcuts.categoryTabs' => 'Tabs',
			'shortcuts.categoryView' => 'View',
			'shortcuts.categoryZoom' => 'Zoom',
			'shortcuts.changeAction' => 'Change…',
			'shortcuts.cheatsheetButton' => 'View Cheatsheet',
			'shortcuts.cheatsheetEmpty' => 'No shortcuts match your search.',
			'shortcuts.cheatsheetTitle' => 'Keyboard Shortcuts',
			'shortcuts.composeNewline' => 'Insert Newline',
			'shortcuts.composeSubmit' => 'Send Message',
			'shortcuts.conflictBadgeTooltip' => 'Conflicts with another shortcut',
			'shortcuts.conflictMessage' => ({required String title}) => 'Already used by "${title}".',
			'shortcuts.export' => 'Export…',
			'shortcuts.exportFailed' => 'Couldn\'t export shortcuts.',
			'shortcuts.exportSuccess' => 'Shortcuts exported.',
			'shortcuts.floatingMaximize' => 'Maximize Floating Workspace',
			'shortcuts.floatingMinimize' => 'Minimize Floating Workspace',
			'shortcuts.floatingNewTerminal' => 'New Floating Terminal',
			'shortcuts.floatingOpenFile' => 'Open File in Floating Workspace',
			'shortcuts.floatingToggle' => 'Toggle Floating Workspace',
			'shortcuts.import' => 'Import…',
			'shortcuts.importConflictMessage' => ({required int count}) => 'The imported shortcuts conflict with ${count} existing binding(s). Replace them?',
			'shortcuts.importConflictTitle' => 'Replace Conflicting Shortcuts?',
			'shortcuts.importInvalidFile' => 'That file isn\'t a valid shortcuts export.',
			'shortcuts.importSuccess' => 'Shortcuts imported.',
			'shortcuts.notSet' => 'Not set',
			'shortcuts.pageSubtitle' => 'View and customize keyboard shortcuts for navigation, tabs, zoom, and compose.',
			'shortcuts.pressShortcutHint' => 'Press a key combination to bind it. Press Escape to cancel, Backspace to unbind.',
			'shortcuts.pressShortcutTitle' => 'Press a Shortcut',
			'shortcuts.pressShortcutUnsupportedKey' => 'That key can\'t be bound.',
			'shortcuts.replaceAction' => 'Replace',
			'shortcuts.resetAction' => 'Reset to Default',
			'shortcuts.resetAll' => 'Reset All',
			'shortcuts.resetAllConfirmMessage' => 'This restores every keyboard shortcut to its default binding.',
			'shortcuts.resetAllConfirmTitle' => 'Reset All Shortcuts?',
			'shortcuts.runRestart' => 'Restart Run',
			'shortcuts.runSelected' => 'Run Selected Configuration',
			'shortcuts.runStop' => 'Stop Run',
			'shortcuts.searchHint' => 'Search shortcuts',
			'shortcuts.sessionCloseTab' => 'Close Session Tab',
			'shortcuts.sessionNewChat' => 'New Conversation',
			'shortcuts.sessionNewTab' => 'New Session Tab',
			'shortcuts.settingsTitle' => 'Keyboard Shortcuts',
			'shortcuts.showCheatsheet' => 'Show Keyboard Shortcuts',
			'shortcuts.stripFocusTab' => ({required int n}) => 'Go to Tab ${n}',
			'shortcuts.stripNextTab' => 'Next Tab',
			'shortcuts.stripPrevTab' => 'Previous Tab',
			'shortcuts.togglePanel' => 'Toggle Terminal Panel',
			'shortcuts.toggleSecondarySidebar' => 'Toggle Secondary Sidebar',
			'shortcuts.toggleSidebar' => 'Toggle Sidebar',
			'shortcuts.unbindAction' => 'Unbind',
			'shortcuts.workbenchFocusNextGroup' => 'Focus Next Editor Group',
			'shortcuts.workbenchMoveTabToNextGroup' => 'Move Tab to Next Editor Group',
			'shortcuts.workbenchSplitDown' => 'Split Editor Down',
			'shortcuts.workbenchSplitReset' => 'Reset Editor Layout',
			'shortcuts.workbenchSplitRight' => 'Split Editor Right',
			'shortcuts.workspaceCloseTab' => 'Close Workspace Tab',
			'shortcuts.workspaceContentSearch' => 'Find in Files',
			'shortcuts.workspaceFocusTab' => ({required int n}) => 'Go to Workspace ${n}',
			'shortcuts.workspaceNextTab' => 'Next Workspace Tab',
			'shortcuts.workspacePrevTab' => 'Previous Workspace Tab',
			'shortcuts.workspaceReopenClosed' => 'Reopen Closed Workspace Tab',
			'shortcuts.workspaceSearch' => 'Search Workspace (double-tap Shift)',
			'shortcuts.zoomIn' => 'Zoom In',
			'shortcuts.zoomOut' => 'Zoom Out',
			'shortcuts.zoomReset' => 'Reset Zoom',
			'skills.add' => 'Add',
			'skills.cardDetails' => 'Details',
			'skills.cardInstall' => 'Install',
			'skills.cardInstalled' => 'Installed',
			'skills.cardStars' => ({required int count}) => '${count} stars',
			'skills.cardUninstall' => 'Uninstall',
			'skills.cardUpdate' => 'Update',
			'skills.cardUpdatedAt' => ({required String date}) => 'Updated ${date}',
			'skills.cardView' => 'View',
			'skills.catalogAdoption' => 'Installs',
			'skills.catalogCardNoDescription' => 'None',
			'skills.checkUpdates' => 'Check updates',
			'skills.checkingUpdates' => 'Checking…',
			'skills.detailMissing' => 'No SKILL.md found for this skill.',
			'skills.detailReadError' => 'Could not read SKILL.md.',
			'skills.discoveryEmpty' => 'No skills discovered',
			'skills.discoveryEmptyHint' => 'Add a repo or try skills.sh to find skills.',
			'skills.discoveryErrorTitle' => 'Discovery failed',
			'skills.discoverySyncing' => 'Checking repos for updates and syncing skills in the background…',
			'skills.enabled' => 'Enabled',
			'skills.filterAll' => 'All',
			'skills.filterAnyCategory' => 'All',
			'skills.filterAnyLanguage' => 'Any',
			'skills.filterAnyOccupation' => 'All',
			'skills.filterCategory' => 'Category',
			'skills.filterInstalled' => 'Installed',
			'skills.filterLanguage' => 'Language',
			'skills.filterOccupation' => 'Occupation',
			'skills.filterRepoAll' => 'All repos',
			'skills.filterSortBy' => 'Sort',
			'skills.filterSortByRecent' => 'Recent',
			'skills.filterSortByStars' => 'Stars',
			'skills.filterUninstalled' => 'Not installed',
			'skills.goDiscovery' => 'Go to Discovery',
			'skills.importFromDisk' => 'Import from disk',
			'skills.importNothing' => 'No unmanaged skills found.',
			'skills.importSelected' => ({required int count}) => 'Import ${count} selected',
			'skills.importTitle' => 'Import unmanaged skills',
			'skills.installFromZip' => 'Install from ZIP',
			'skills.installSuccess' => ({required String name}) => 'Installed ${name}',
			'skills.installedCount' => ({required int count}) => '${count} installed',
			'skills.installs' => ({required int count}) => '${count} installs',
			'skills.local' => 'local',
			'skills.marketplaceAddRepo' => 'Add repo',
			'skills.marketplaceLoadMore' => 'Load more',
			'skills.marketplaceRepoAdded' => 'Repo added to skill sources; install individual skills in the Repos tab',
			'skills.mpQuotaHint' => 'SkillsMP anonymous quota (50/day) exhausted. Set a free API key to continue.',
			'skills.navDiscovery' => 'Discovery',
			'skills.navInstalled' => 'Installed',
			'skills.navRegistries' => 'Registries',
			'skills.navRepos' => 'Repos',
			'skills.noInstalled' => 'No skills installed yet',
			'skills.noInstalledHint' => 'Open Discovery to install your first skill.',
			'skills.noUpdates' => 'All skills are up to date',
			'skills.overwriteConfirm' => ({required String name}) => '${name} already installed. Overwrite?',
			'skills.registryAddSource' => 'Add registry source',
			'skills.registryApiKeySet' => 'API key set',
			'skills.registryBaseUrlLabel' => 'Base URL',
			'skills.registryBrowseQueryLabel' => 'Default browse query',
			'skills.registryEditTitle' => 'Edit registry source',
			'skills.registryGoSetKey' => 'Set API key in Registries',
			'skills.registryNameLabel' => 'Display name',
			'skills.registryNameOfRepoLabel' => 'Repository',
			'skills.registryOwnerLabel' => 'Owner',
			'skills.registryProtocolLabel' => 'Protocol',
			'skills.registryProtocolSkillsMp' => 'SkillsMP compatible',
			'skills.registryProtocolSkillsSh' => 'skills.sh compatible',
			'skills.registryRemoveTitle' => 'Reset registry',
			'skills.registryResetConfirm' => ({required String name}) => 'Reset ${name} to defaults?',
			'skills.registryRetry' => 'Retry',
			'skills.registrySourceExists' => 'This registry source already exists',
			'skills.registrySourceKind' => 'Source type',
			'skills.registrySourceKindApi' => 'API source',
			'skills.registrySourceKindGit' => 'Git repository',
			'skills.registryTestFailed' => ({required String error}) => 'Connection failed: ${error}',
			'skills.registryTestOk' => 'Connection OK',
			'skills.registryTokenLabel' => 'API Key',
			'skills.remove' => 'Remove',
			'skills.repoAdd' => 'Add repo',
			'skills.repoBranch' => 'Branch',
			'skills.repoInvalidUrl' => 'Enter a valid GitHub repo URL, e.g. https://github.com/owner/repo',
			'skills.repoRemove' => 'Remove',
			'skills.repoRemoveConfirm' => ({required String name}) => 'Remove repo ${name}?',
			'skills.repoSyncing' => 'Updating',
			'skills.repoUrl' => 'Repository URL',
			'skills.repoUrlHint' => 'https://github.com/owner/repo',
			'skills.searchPlaceholder' => 'Search skills…',
			'skills.sidebarLabel' => 'Skills',
			'skills.subtitle' => 'Manage installable skills',
			'skills.title' => 'Skills',
			'skills.uninstallConfirm' => ({required String name}) => 'Uninstall ${name}?',
			'skills.uninstallSuccess' => ({required String name}) => 'Uninstalled ${name}',
			'skills.updateAll' => ({required int count}) => 'Update all (${count})',
			'skills.updateAvailable' => 'Update available',
			'skills.updateSuccess' => ({required String name}) => 'Updated ${name}',
			'skills.zipNoSkills' => 'No SKILL.md found in the archive.',
			'ssh.credentialSource' => 'Credentials',
			'ssh.credentialSourceKeychain' => 'This device\'s keychain',
			'ssh.credentialVaultDeleted' => 'Deleted vault entry',
			'ssh.defaultWorkingDirectorySubtitle' => 'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.',
			'ssh.defaultWorkingDirectoryTitle' => 'SSH default working directory',
			'ssh.homeDisconnectedBannerMessage' => 'Remote SSH work home is disconnected. Shell, Git, and agent sessions are paused until you reconnect.',
			'ssh.homeDisconnectedReconnect' => 'Reconnect',
			'ssh.hostKeyFingerprintLabel' => 'Fingerprint',
			'ssh.hostKeyKeyTypeLabel' => ({required String keyType}) => 'Key type: ${keyType}',
			'ssh.hostKeyMismatchBody' => ({required String host}) => 'The host key for ${host} does not match the one TeamPilot saved earlier. This can happen after a reinstall — or if someone is intercepting the connection.',
			'ssh.hostKeyMismatchTitle' => 'SSH host key changed',
			'ssh.hostKeyPreviousFingerprintLabel' => 'Previously trusted',
			'ssh.hostKeyReplaceTrust' => 'Replace and trust',
			'ssh.hostKeyTrust' => 'Trust and continue',
			'ssh.hostKeyUnknownBody' => ({required String host}) => 'TeamPilot has not seen ${host} before. Confirm the fingerprint matches this machine before trusting it.',
			'ssh.hostKeyUnknownTitle' => 'Verify SSH host key',
			'ssh.hostsManage' => 'Manage Remote Hosts…',
			'ssh.hostsOpenTerminal' => 'Open Terminal',
			'ssh.hostsOpenTerminalNoWorkspace' => 'Open a workspace first to start a terminal.',
			'ssh.hostsPanelTitle' => 'Remote Hosts',
			'ssh.hostsPillConnecting' => 'Connecting…',
			'ssh.hostsPillCount' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '1 host', other: '${count} hosts', ), 
			'ssh.hostsRowKind' => 'SSH Host',
			'ssh.migrateToVault' => 'Move to vault',
			'ssh.penaltyRefused' => 'The server temporarily refused the connection (its anti-brute-force protection was triggered). Wait about a minute and try again.',
			'ssh.saveToVault' => 'Save to vault',
			'ssh.serversEmpty' => 'No SSH servers saved on this host yet.',
			'ssh.serversLoadError' => 'Could not load the SSH servers. Check the connection and try again.',
			'ssh.serversNotConnected' => 'Not connected to a remote host.',
			'ssh.serversTitle' => 'SSH servers',
			'ssh.vaultBadge' => 'Vault',
			'sshProfile.connect' => 'Connect',
			'sshProfile.connectSuccess' => ({required String host}) => 'Connected to ${host}',
			'sshProfile.delete' => 'Delete',
			'sshProfile.disconnect' => 'Disconnect',
			'sshProfile.edit' => 'Edit',
			_ => null,
		} ?? switch (path) {
			'sshProfile.formAuthChangeBody' => 'Saving will remove the credential stored for the other authentication method.',
			'sshProfile.formAuthChangeConfirm' => 'Switch and save',
			'sshProfile.formAuthChangeTitle' => 'Switch authentication?',
			'sshProfile.formAuthPrivateKey' => 'Private key',
			'sshProfile.formAuthType' => 'Authentication',
			'sshProfile.formCredentialRequired' => 'Provide a private key or password.',
			'sshProfile.formCredentialSaveFailed' => 'Target saved, but credentials could not be stored. Unlock the system keyring and edit the target to re-enter them.',
			'sshProfile.formFieldRequired' => 'Required',
			'sshProfile.formHost' => 'Host or alias',
			'sshProfile.formHostHint' => 'server, deploy@server:2222',
			'sshProfile.formIdentityFile' => 'Private key',
			'sshProfile.formIdentityFileHelper' => 'Paste the private key, or import it from a file.',
			'sshProfile.formIdentityFileHint' => '-----BEGIN OPENSSH PRIVATE KEY-----',
			'sshProfile.formIdentityFileImport' => 'Import from file',
			'sshProfile.formIdentityFileImportFailed' => 'Could not read the selected file; paste the key instead',
			'sshProfile.formLabel' => 'Label',
			'sshProfile.formLabelHint' => 'My server',
			'sshProfile.formPassphrase' => 'Key passphrase',
			'sshProfile.formPassphraseHint' => 'Optional',
			'sshProfile.formPassword' => 'Password',
			'sshProfile.formPasswordHint' => 'Login password',
			'sshProfile.formPasswordHintEdit' => 'Leave empty to keep saved password',
			'sshProfile.formPort' => 'Port',
			'sshProfile.formPortInvalid' => 'Port must be between 1 and 65535',
			'sshProfile.formTitleEdit' => 'Edit SSH target',
			'sshProfile.formTitleNew' => 'New SSH target',
			'sshProfile.formUsername' => 'Username',
			'sshProfile.formUsernameHint' => 'deploy',
			'sshProfile.refresh' => 'Refresh',
			'sshProfile.selectorManage' => 'Manage SSH servers…',
			'sshProfile.selectorTooltip' => 'Switch SSH server',
			'sshProfile.statusAuthFailed' => 'Authentication failed',
			'sshProfile.statusConnected' => 'Connected',
			'sshProfile.statusConnecting' => 'Connecting…',
			'sshProfile.statusDisconnected' => 'Disconnected',
			'sshProfile.statusError' => 'Error',
			'sshProfile.statusReconnecting' => 'Reconnecting…',
			'sshProfile.test' => 'Test',
			'sshProfile.testFailed' => 'Connection test failed',
			'sshProfile.testFailedAborted' => ({required String detail}) => 'Connection closed before login: ${detail}',
			'sshProfile.testFailedAuth' => 'Authentication failed',
			'sshProfile.testFailedDetail' => ({required String detail}) => 'Connection test failed: ${detail}',
			'sshProfile.testFailedHostKey' => 'Host key was not trusted',
			'sshProfile.testSuccess' => 'Connection successful',
			'sshProfile.sAddTarget' => 'Add target',
			'sshProfile.sEmpty' => 'No SSH targets configured.',
			'sshProfile.sImport' => 'Import',
			'sshProfile.sImportUnavailable' => 'Import from ~/.ssh/config is not available yet.',
			'sshProfile.sPageSubtitle' => 'SSH server configurations stored on the host behind the current home; every device paired to it shares this list.',
			'sshProfile.sPageTitle' => 'Remote SSH servers',
			'sshProfile.sSettingsTitle' => 'SSH servers',
			'sshProfile.sTargetsSubtitle' => 'Add a remote host to connect from TeamPilot.',
			'sshProfile.sTargetsTitle' => 'Targets',
			'team.cliComingSoon' => 'Coming soon',
			'team.cliLabel' => 'CLI backend',
			'team.cliLockedSubtitle' => 'Set when this team was created.',
			'team.cliSubtitle' => 'Chosen when the team is created and cannot be changed later.',
			'team.config' => 'Team Config',
			'team.configAspectCli' => 'CLI',
			'team.configAspectDefaultProvider' => 'Default provider',
			'team.configAspectModel' => 'Model',
			'team.configAspectProvider' => 'Provider',
			'team.configAspectSeparator' => ', ',
			'team.configGroupTeamDefault' => 'Team default',
			'team.configIncompleteBody' => ({required String team}) => 'Team "${team}" is missing settings needed to launch. The session still starts, but agents may fail without them:',
			'team.configIncompleteDismiss' => 'Later',
			'team.configIncompleteGoConfigure' => 'Configure team',
			'team.configIncompleteTitle' => 'Team configuration incomplete',
			'team.configIssueSemanticLabel' => ({required String subject, required String aspects}) => '${subject} is missing: ${aspects}',
			'team.defaultCliMixedSubtitle' => 'When a member has no CLI override.',
			'team.defaultDialogEffortSubtitle' => 'Team default effort.',
			'team.defaultPresetChange' => 'Change',
			'team.defaultPresetLabel' => 'Default Model Preset',
			'team.defaultPresetManage' => 'Manage',
			'team.defaultPresetNone' => 'None',
			'team.defaultPresetSubtitle' => 'Optional default preset applied to members that don\'t override it.',
			'team.description' => 'Team description',
			'team.descriptionHint' => 'Optional note for Claude roster and team context',
			'team.effortLevel' => 'Reasoning effort',
			'team.effortLevelSubtitle' => 'Default effort for this team (Claude effortLevel / Codex model_reasoning_effort).',
			'team.extensionEffectiveOff' => 'Inactive for this team',
			'team.extensionEffectiveOn' => 'Active for this team',
			'team.extensionFollowGlobal' => 'Follow global',
			'team.extensionForceOff' => 'Off',
			'team.extensionForceOn' => 'On',
			'team.extensionsNav' => 'Extensions',
			'team.extensionsSubtitle' => 'Override which extensions run for this team. Default follows the global setting.',
			'team.extensionsTitle' => 'Extensions for this team',
			'team.extraArgs' => 'Team extra CLI arguments',
			'team.extraArgsHint' => '--permission-mode acceptEdits',
			'team.forceWaitBeforeStopSubtitle' => 'When enabled, a member finishing a turn is pushed back into wait_for_message instead of stopping, so it stays available for new messages and tasks. Disable to let members rest (stop normally).',
			'team.forceWaitBeforeStopTitle' => 'Keep members in the wait loop',
			'team.genApplied' => 'Draft applied. Review and adjust before creating.',
			'team.genButton' => 'Generate',
			'team.genDescriptionHint' => 'Describe the team you want (e.g. Flutter frontend with code review and tests)',
			'team.genFailed' => 'Could not generate a team. Please edit manually.',
			'team.genNoProvider' => 'Configure an AI provider in Settings → AI Features first.',
			'team.genTitle' => 'Generate with AI',
			'team.generateAddModel' => 'Add model configuration',
			'team.generateBuilderTitle' => 'Team Builder',
			'team.generateCancel' => 'Cancel generation',
			'team.generateCancelBody' => 'The temporary session and staged resources will be removed.',
			'team.generateCancelTitle' => 'Cancel team generation?',
			'team.generateCapabilityNote' => 'Team Builder will check workspace machines and may acquire skills, plugins, and MCP servers for the generated team.',
			'team.generateContinueSetup' => 'Continue setup',
			'team.generateDeliveryArrived' => 'It arrived',
			'team.generateDeliveryRetryBody' => 'The lead might receive the task twice.',
			'team.generateDeliveryRetryTitle' => 'Send the task again?',
			'team.generateDeliverySendAgain' => 'Send again…',
			'team.generateDescription' => 'Strengths and best uses',
			'team.generateEmptyPool' => 'No configurations yet. Add the strongest one first.',
			'team.generateErrorAiNotConfigured' => 'Configure the generator model first.',
			'team.generateErrorDescriptionRequired' => 'Describe the task to generate a team.',
			'team.generateErrorGeneratorUnsupported' => 'The generator CLI must support sessions, skills, and MCP.',
			'team.generateErrorNativeUnsupported' => 'The selected CLI does not support native teams.',
			'team.generateErrorPoolEmpty' => 'Add at least one valid model configuration.',
			'team.generateErrorPromptDeliveryUnknown' => 'TeamPilot cannot confirm whether the lead received the task.',
			'team.generateErrorRecoveryIntegrity' => 'Recovery data could not be verified. The temporary session was kept.',
			'team.generateErrorStagingUnsupported' => 'This resource needs a manual installation step and cannot be staged safely.',
			'team.generateErrorStartFailed' => 'Team generation could not start. Try again.',
			'team.generateErrorTargetUnavailable' => 'A required machine or CLI is unavailable.',
			'team.generateErrorUnavailable' => 'Team generation is unavailable right now. Restart TeamPilot and try again.',
			'team.generateErrorUserActionRequired' => 'Complete the required sign-in or configuration, then retry.',
			'team.generateGeneratorModel' => 'Generator model',
			'team.generateHiddenPresets' => ({required int count}) => '${count} configurations are hidden because they use another CLI.',
			'team.generateLaunch' => 'Generate and launch',
			'team.generateLoading' => 'Loading settings…',
			'team.generateMinimumMemberCount' => 'Minimum team members',
			'team.generateMinimumMemberCountHint' => 'The generated team will include at least this many distinct roles.',
			'team.generateMinimumMemberCountInvalid' => 'Minimum must be at least 3.',
			'team.generateMissingPreset' => ({required String presetId}) => 'Preset “${presetId}” no longer exists.',
			'team.generateMixed' => 'Mixed',
			'team.generateModelPool' => 'Model configuration pool',
			'team.generateModelPoolHint' => 'Rank 1 is strongest. Prefer earlier entries for the team lead.',
			'team.generateMoveDown' => 'Move down',
			'team.generateMoveUp' => 'Move up',
			'team.generateNative' => 'Native',
			'team.generateNativeCli' => 'Native CLI',
			'team.generateOpenLeadSession' => 'Open lead session',
			'team.generateOpenSettings' => 'Open generation settings',
			'team.generatePickPreset' => 'Choose a preset',
			'team.generateRemove' => 'Remove',
			'team.generateRetainBuilderSession' => 'Keep Builder Session for troubleshooting',
			'team.generateRetainBuilderSessionHint' => 'When enabled, the generated team opens normally but the Builder Session is kept for inspecting the generation process.',
			'team.generateRetry' => 'Retry',
			'team.generateSettingsSubtitle' => 'How Team Builder plans the roster, and which model configurations it may assign.',
			'team.generateSettingsTitle' => 'Generate and launch settings',
			'team.generateTags' => 'Tags',
			'team.generateTeamMode' => 'Team mode',
			'team.hooksAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} enabled',
			'team.hooksManage' => 'Manage hooks',
			'team.hooksNav' => 'Hooks',
			'team.leadBadge' => 'Leader',
			'team.leadDelegateOnlySubtitle' => 'When enabled, the team lead is blocked from using some tools.',
			'team.leadDelegateOnlyTitle' => 'Team lead: plan and delegate only',
			'team.leadNameRequired' => 'FlashskyAI team delegation expects this member to be named exactly team-lead.',
			'team.leadNotice' => 'FlashskyAI team delegation expects this member to be named exactly team-lead.',
			'team.loop' => 'Phase loop',
			'team.loopDefault' => 'Default',
			'team.loopFalse' => 'false — confirm each phase',
			'team.loopSubtitle' => 'Team mode: true auto-advances phases; false requires your confirmation.',
			'team.loopTrue' => 'true — auto-advance',
			'team.mcpAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} enabled',
			'team.mcpManage' => 'All MCP servers',
			'team.mcpNav' => 'MCP',
			'team.modeLabel' => 'Team mode',
			'team.modeMixed' => 'Mixed (cross-CLI bus)',
			'team.modeMixedDescription' => 'Members can run different CLIs and collaborate across tools over TeamBus.',
			'team.modeMixedTitle' => 'Mixed mode',
			'team.modeNative' => 'Native (single CLI)',
			'team.modeNativeDescription' => 'All members share one CLI for native, low-config collaboration.',
			'team.modeNativeTitle' => 'Native mode',
			'team.modeRequired' => 'Choose a team mode first.',
			'team.name' => 'Team name',
			'team.nameAlreadyExists' => ({required String name}) => 'A team named "${name}" already exists.',
			'team.nameRequired' => 'Team name is required.',
			'team.pluginsAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} installed',
			'team.pluginsCliUnsupportedBanner' => 'This team\'s CLI does not support plugins yet. Selections are saved but ignored at launch.',
			'team.pluginsEmpty' => 'No plugins installed',
			'team.pluginsEmptyHint' => 'Install plugins from Discovery to enable them per team.',
			'team.pluginsGoDiscovery' => 'Browse marketplace',
			'team.pluginsManage' => 'All plugins',
			'team.pluginsMissing' => ({required int count}) => '${count} enabled plugin(s) missing on disk. Reinstall or remove below.',
			'team.pluginsMissingLabel' => 'Missing on disk',
			'team.pluginsNameConflict' => ({required String dir}) => 'Linked as ${dir} due to name conflict',
			'team.pluginsNav' => 'Plugins',
			'team.pluginsRemoveMissing' => 'Remove',
			'team.sessions' => 'Team Sessions',
			'team.settings' => 'Team Settings',
			'team.settingsSubtitle' => 'Team agents',
			'team.skillsAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} enabled',
			'team.skillsManage' => 'All skills',
			'team.skillsNav' => 'Skills',
			'teamHub.alreadyAdded' => 'Already added',
			'teamHub.browseAll' => 'Browse all teams',
			'teamHub.cardNoDescription' => 'None',
			'teamHub.categoryAll' => 'All',
			'teamHub.clone' => 'Clone to my teams',
			'teamHub.cloneFailed' => 'Could not clone this team.',
			'teamHub.cloneOptionsTitle' => 'Clone options',
			'teamHub.clonePartial' => ({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount, required int failedCount, required Object failedNames}) => 'Cloned "${name}". Installed ${skillCount} skills, ${pluginCount} plugins, ${mcpCount} MCP servers, cloned ${expertCount} experts. ${failedCount} could not be installed: ${failedNames}.',
			'teamHub.cloneSuccess' => ({required Object name}) => 'Cloned "${name}".',
			'teamHub.cloneSuccessWithDeps' => ({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount}) => 'Cloned "${name}". Installed ${skillCount} skills, ${pluginCount} plugins, and ${mcpCount} MCP servers, and cloned ${expertCount} experts.',
			'teamHub.cloning' => 'Cloning…',
			'teamHub.confirmSelection' => 'Confirm',
			'teamHub.depInstalled' => 'Installed',
			'teamHub.depToInstall' => 'Will be installed',
			'teamHub.discovery' => 'Discovery',
			'teamHub.emptyHint' => 'Refresh to fetch teams from the registry.',
			'teamHub.emptyTitle' => 'No public teams yet',
			'teamHub.favorites' => 'Favorites',
			'teamHub.favoritesEmptyHint' => 'Tap the star on a team to save it here.',
			'teamHub.favoritesEmptyTitle' => 'No favorites yet',
			'teamHub.loadError' => 'Could not load public teams.',
			'teamHub.mcpLabel' => 'MCP',
			'teamHub.membersLabel' => 'Members',
			'teamHub.nav' => 'TeamHub',
			'teamHub.notFound' => 'Team not found.',
			'teamHub.pluginsLabel' => 'Plugins',
			'teamHub.refresh' => 'Refresh',
			'teamHub.searchHint' => 'Search public teams',
			'teamHub.skillsLabel' => 'Skills',
			'teamHub.sortName' => 'Name',
			'teamHub.sortUpdated' => 'Recently updated',
			'teamHub.subtitle' => 'Discover more public teams',
			'teamHub.title' => 'TeamHub',
			'terminal.clear' => 'Clear terminal',
			'terminal.copySelectHint' => 'Shift+drag to copy',
			'terminal.dropCrossMachineRejected' => 'Can\'t drop a local file onto a remote terminal',
			'terminal.exportScrollback' => 'Export scrollback…',
			'terminal.find' => 'Find in terminal',
			'terminal.findNoResults' => 'No results',
			'terminal.linkClickOpensInAppDescription' => 'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.',
			'terminal.linkClickOpensInAppTitle' => 'Open terminal links in app',
			'terminal.openLink' => 'Open link',
			'terminal.parkedSendDismiss' => 'Dismiss',
			'terminal.parkedSendPending' => ({required String content}) => 'Sent, awaiting receipt: ${content}',
			'terminal.scrollbackLinesDescription' => 'Maximum lines kept in each session terminal buffer',
			'terminal.scrollbackLinesTitle' => 'Terminal scrollback lines',
			'terminal.themeModeDescription' => 'Match app colors or use a fixed style',
			'terminal.themeModeTitle' => 'Terminal theme',
			'termux.disconnectedBannerMessage' => 'Termux is disconnected. Shell, Git, and agent sessions are paused until you reconnect.',
			'termux.disconnectedReconnect' => 'Reconnect',
			'termux.disconnectedWorkOpsBlocked' => 'Termux is disconnected. Reconnect from the banner, then try again.',
			'termux.setupClearConfirmAction' => 'Clear setup',
			'termux.setupClearConfirmBody' => 'This removes saved Termux keys and username. You will need to set up Termux again.',
			'termux.setupClearConfirmTitle' => 'Clear Termux setup?',
			'termux.setupClearSetup' => 'Clear setup',
			'termux.setupConnect' => 'Connect',
			'termux.setupConnectFailed' => 'Could not connect to Termux',
			'termux.setupConnectFailedWithDetail' => ({required String detail}) => 'Could not connect to Termux: ${detail}',
			'termux.setupConnectSuccess' => 'Connected to Termux',
			'termux.setupConnecting' => 'Connecting…',
			'termux.setupDownloadFailed' => 'Could not download Termux. Retry or use a store link.',
			'termux.setupDownloadInstall' => 'Download & install Termux',
			'termux.setupDownloading' => 'Downloading Termux…',
			'termux.setupInstallDenied' => 'Install was cancelled or blocked. Enable unknown apps if needed, then retry.',
			'termux.setupInstallFDroid' => 'F-Droid',
			'termux.setupInstallGitHub' => 'GitHub',
			'termux.setupInstallPlayStore' => 'Play Store',
			'termux.setupInstalling' => 'Installing…',
			'termux.setupIntro' => 'Install Termux, paste one setup script, then connect TeamPilot to the local SSH server.',
			'termux.setupScriptHint' => 'Allow storage access when prompted. sshd is enabled via termux-services (starts when Termux opens). Optional: install Termux:Boot from F-Droid for reboot without opening Termux. The last line prints your username (e.g. u0_a399).',
			'termux.setupStepInstallTermux' => '1. Install Termux',
			'termux.setupStepRunScript' => '2. Paste this script in Termux',
			'termux.setupTermuxInstalled' => 'Termux is installed',
			'termux.setupTitle' => 'Termux setup',
			'termux.setupUsernameError' => 'Enter a valid Termux username (starts with u)',
			'termux.setupUsernameHint' => 'e.g. u0_a399',
			'termux.setupUsernameLabel' => '3. Paste your Termux username',
			'theme.theme' => 'Theme',
			'theme.colorPresetDescription' => 'Primary and accent colors for buttons, toggles, and highlights.',
			'theme.colorPresetTitle' => 'Theme colors',
			'theme.dark' => 'Dark',
			'theme.light' => 'Light',
			'theme.modeDescription' => 'Light, dark, or match the operating system appearance.',
			'theme.modeTitle' => 'Theme mode',
			'theme.presetAmber' => 'Amber',
			'theme.presetForest' => 'Forest',
			'theme.presetGraphite' => 'Graphite',
			'theme.presetOcean' => 'Ocean',
			'theme.presetViolet' => 'Violet',
			'theme.system' => 'System',
			'tool.categoryAskUser' => 'Ask user',
			'tool.categoryBrowser' => 'Browser',
			'tool.categoryCommand' => 'Shell command',
			'tool.categoryEdit' => 'Edit file',
			'tool.categoryMcp' => 'MCP',
			'tool.categoryOther' => 'Other',
			'tool.categoryPlan' => 'Plan',
			'tool.categoryRead' => 'Read file',
			'tool.categorySearch' => 'Web search',
			'tool.categorySubagent' => 'Subagent',
			'tool.categoryTask' => 'Tasks & todos',
			'tool.categoryWrite' => 'Write file',
			'tool.placement' => 'Tool Placement',
			'tool.placementDescription' => 'Dock tool panels on the right or along the bottom edge.',
			'typography.scaleComfortable' => 'Large',
			'typography.scaleCompact' => 'Small',
			'typography.scaleCustom' => 'Custom',
			'typography.scaleCustomHint' => '50–200',
			'typography.scaleCustomLabel' => 'Scale',
			'typography.scaleDescription' => 'Size of UI text. Standard follows your system; does not change icons or spacing.',
			'typography.scaleStandard' => 'Standard',
			'typography.scaleTitle' => 'Text size',
			'vault.cancel' => 'Cancel',
			'vault.copied' => 'Copied',
			'vault.copy' => 'Copy',
			'vault.deleteConfirm' => 'Delete',
			'vault.deleteReferenced' => 'This entry is still used by:',
			'vault.deleteTitle' => 'Delete entry?',
			'vault.disableEncryption' => 'Disable encrypted vault',
			'vault.emptyHint' => 'Save SSH passwords, private keys or provider API keys here.',
			'vault.emptyTitle' => 'No entries yet',
			'vault.enableEncryption' => 'Enable encrypted vault',
			'vault.entryFavorite' => 'Favorite',
			'vault.entryNotes' => 'Notes',
			'vault.entryTags' => 'Tags (comma separated)',
			'vault.entryTitle' => 'Title',
			'vault.entryType' => 'Type',
			'vault.hide' => 'Hide',
			'vault.homeOfflineHint' => 'Not connected to the remote host. Business credentials stored there are unavailable until it reconnects.',
			'vault.lock' => 'Lock now',
			'vault.lockedQueryBlocked' => 'Unlock the vault to query usage.',
			'vault.lockedSaveBlocked' => 'Unlock the vault to save credentials.',
			'vault.newEntry' => 'New entry',
			'vault.noReferences' => 'Not referenced yet',
			'vault.onlyCopy' => 'Copy only',
			'vault.pageSubtitle' => 'SSH passwords, private keys and provider API keys',
			'vault.pageTitle' => 'Credential Vault',
			'vault.passphrase' => 'Master passphrase',
			'vault.passphraseConfirm' => 'Confirm passphrase',
			'vault.passphraseMismatch' => 'Passphrases do not match',
			'vault.passphraseRequired' => 'Passphrase is required',
			'vault.references' => 'Used by',
			'vault.reveal' => 'Reveal',
			'vault.save' => 'Save',
			'vault.searchHint' => 'Search title, fields or tags',
			'vault.statusEncrypted' => 'Encrypted vault · locked',
			'vault.statusKeychain' => 'System keychain · no unlock needed',
			'vault.statusUnlocked' => 'Encrypted vault · unlocked',
			'vault.storedInVault' => 'Stored in vault',
			'vault.typeApiKey' => 'Provider API key',
			'vault.typeCustom' => 'Custom',
			'vault.typeLogin' => 'Login',
			'vault.typeSecureNote' => 'Secure note',
			'vault.typeSshPassword' => 'SSH password',
			'vault.typeSshPrivateKey' => 'SSH private key',
			'vault.typeToken' => 'Token',
			'vault.unavailable' => 'Credential vault is unavailable.',
			'vault.unlock' => 'Unlock',
			'vault.unlockFailed' => 'Could not unlock the vault',
			'vault.unlockTitle' => 'Unlock vault',
			'vault.wrongPassphraseHint' => 'Wrong passphrase or damaged file. Data was not modified.',
			'workspace.additionalDirectories' => 'Additional directories',
			'workspace.advancedSettings' => 'Advanced',
			'workspace.advancedSettingsSubtitle' => 'Agent preset and extra CLI flags for this member.',
			'workspace.agentBuiltInSubtitle' => 'Maps to flashskyai --agent when that CLI is active.',
			'workspace.agentExtraArgs' => 'Extra CLI arguments',
			'workspace.agentExtraArgsSubtitle' => 'Extra flags appended when starting the agent in this workspace.',
			'workspace.agentPromptPresetDeveloper' => 'Developer',
			'workspace.agentPromptPresetDeveloperText' => 'Focus on implementation and fixes. Prefer minimal diffs, run relevant tests, and briefly explain changed files and rationale.',
			'workspace.agentPromptPresetGeneral' => 'General',
			'workspace.agentPromptPresetGeneralText' => 'Help with development in this workspace end to end. Understand the request and codebase, propose a clear approach, then implement with minimal diffs; summarize changed files and suggested next steps.',
			'workspace.agentPromptPresetResearcher' => 'Researcher',
			'workspace.agentPromptPresetResearcherText' => 'Investigate and report only; do not change production code unless asked.\nOutput findings with file paths, relevant symbols, and recommended next steps.',
			'workspace.agentPromptPresetReviewer' => 'Reviewer',
			'workspace.agentPromptPresetReviewerText' => 'Review code only; do not modify files unless asked.\nEach finding must include file path, line, issue, and suggested fix.',
			'workspace.agentPromptSubtitle' => 'System prompt defining the agent\'s role and boundaries in this workspace.',
			'workspace.chatLandingAttach' => 'Attach files',
			'workspace.chatLandingBackToWorkbench' => 'Back to workbench',
			'workspace.chatLandingConnectApps' => 'Connect apps',
			'workspace.chatLandingCustomLaunch' => 'Custom…',
			'workspace.chatLandingCustomLaunchTitle' => 'Custom launch',
			'workspace.chatLandingInputHint' => 'What can I help you with today? @ reference files, / invoke skills',
			'workspace.chatLandingModeSimple' => 'Simple chat',
			'workspace.chatLandingModeTeam' => 'Team',
			'workspace.chatLandingSelectLaunchDirectory' => 'Select directory >',
			'workspace.chatLandingSelectProject' => 'Select project >',
			'workspace.chatLandingSelectWorkspace' => 'Select workspace >',
			'workspace.chatLandingSelectWorktree' => 'Select worktree >',
			'workspace.chatLandingSkills' => 'Skills',
			'workspace.chatLandingTeamLaunchBlocked' => 'Configure team and member model presets in Team Settings before sending.',
			'workspace.chatLandingUsePreset' => 'Use preset',
			'workspace.chatLandingVoice' => 'Voice input',
			'workspace.chatLandingVoiceCancel' => 'Cancel recording',
			'workspace.chatLandingVoiceMacOsIdeLaunch' => 'Voice input cannot request macOS speech permissions when TeamPilot is launched from the IDE. Run build/macos/Build/Products/Debug/TeamPilot.app directly, or launch from Xcode.',
			'workspace.chatLandingVoicePermissionDenied' => 'Microphone permission denied',
			'workspace.chatLandingVoiceStop' => 'Stop recording',
			'workspace.chatLandingVoiceUnavailable' => 'Voice input is not available on this device',
			'workspace.cliAddPresetTitle' => 'Add Preset',
			'workspace.cliConfigSummary' => ({required String provider, required String model}) => '${provider} · ${model}',
			'workspace.cliConfigure' => 'Configure',
			'workspace.cliConfigured' => 'Configured',
			'workspace.cliDefaultSubtitle' => 'Default CLI for new conversations in this workspace.',
			'workspace.cliDefaultsSubtitle' => 'Set the default provider and model for each CLI used in this workspace.',
			'workspace.cliDefaultsTitle' => 'CLI defaults',
			'workspace.cliDeletePresetConfirm' => ({required String name}) => 'Delete preset \'${name}\'? This cannot be undone.',
			'workspace.cliDeletePresetTitle' => 'Delete Preset',
			'workspace.cliEditPresetTitle' => 'Edit Preset',
			'workspace.cliEffortInheritHint' => 'Use provider default',
			'workspace.cliEffortLevel' => 'Reasoning effort',
			'workspace.cliEffortLevelSubtitle' => 'Default effort for this CLI in the workspace (leave empty to use provider default).',
			'workspace.cliManagePresets' => 'Manage',
			'workspace.cliNoPresetHint' => 'No preset selected',
			'workspace.cliNoProviderCatalog' => 'No provider setup required for this CLI',
			'workspace.cliNotConfigured' => 'Not configured',
			'workspace.cliNotConfiguredHint' => 'No default provider selected yet',
			'workspace.cliPresetLabel' => 'Active Preset',
			'workspace.cliPresetNameLabel' => 'Preset Name',
			'workspace.cliPresetsEmptyHint' => 'No presets yet. Create one to get started.',
			'workspace.cliPresetsManageTitle' => 'Manage Presets',
			'workspace.cliProviderConfig' => 'Provider configuration',
			'workspace.cliProviderModelTitle' => 'Provider & model',
			'workspace.createdAt' => 'Created',
			'workspace.deadTargetBadge' => 'Missing machine',
			'workspace.deadTargetRemap' => 'Remap…',
			'workspace.deadTargetRemapBody' => ({required String from}) => 'Replace ${from} with another machine. Directory paths are not changed — they must already exist on the destination.',
			'workspace.deadTargetRemapConfirm' => 'Remap',
			'workspace.deadTargetRemapFailed' => 'Could not remap machine.',
			'workspace.deadTargetRemapFromLaunch' => 'Remap machine…',
			'workspace.deadTargetRemapNothing' => 'Nothing to remap.',
			'workspace.deadTargetRemapPickFrom' => 'Dead machine',
			'workspace.deadTargetRemapPickTo' => 'Replacement machine',
			'workspace.deadTargetRemapTitle' => 'Remap machine',
			'workspace.details' => 'Workspace details',
			'workspace.directoryAdded' => 'Directory added to workspace',
			'workspace.directoryAlreadyAdded' => 'This directory is already in the workspace.',
			'workspace.directoryAlreadyPrimary' => 'This path is already the primary directory.',
			'workspace.displayName' => 'Display name',
			'workspace.entryModeDescription' => 'Where the app opens after launch.',
			'workspace.entryModeHome' => 'Home',
			'workspace.entryModeLastWorkspace' => 'Last workspace',
			'workspace.entryModeTitle' => 'Startup view',
			'workspace.extensionEffectiveOff' => 'Disabled for this workspace',
			'workspace.extensionEffectiveOn' => 'Enabled for this workspace',
			'workspace.extensionsSubtitle' => 'Override which extensions run for this workspace. Default follows the global setting.',
			'workspace.extensionsTitle' => 'Extensions for this workspace',
			'workspace.folderPathLabel' => 'Directory',
			'workspace.folderTargetLabel' => 'Machine',
			'workspace.foldersAddOnAnotherMachine' => 'Add other host directories',
			'workspace.foldersApplyAllLocal' => 'Set all to local',
			'workspace.foldersApplyAllRemote' => 'Set all to remote…',
			'workspace.foldersChangeTarget' => 'Change',
			'workspace.foldersEditorHint' => 'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).',
			'workspace.foldersPersonalTargetsLockedHint' => 'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.',
			'workspace.foldersPickMixedTarget' => 'Add directory on machine',
			'workspace.foldersPickPath' => 'Choose directory',
			'workspace.foldersPickRemoteTarget' => 'Choose remote machine',
			'workspace.foldersPickTarget' => 'Choose machine',
			'workspace.foldersSectionTitle' => 'Directories & machines',
			'workspace.hooksAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} enabled for this workspace',
			'workspace.hooksManage' => 'Manage hooks',
			'workspace.icon' => 'Icon',
			'workspace.iconPickerTitle' => 'Choose workspace icon',
			'workspace.iconUpload' => 'Upload icon',
			'workspace.iconUploadFailed' => 'Could not save icon. Use PNG, JPG, WEBP, or SVG.',
			'workspace.iconUseDefault' => 'Use default',
			'workspace.mcpAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} enabled for this workspace',
			'workspace.mcpManage' => 'Manage MCP',
			'workspace.noAdditionalDirectories' => 'No additional directories',
			'workspace.pluginsAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} linked to this workspace',
			'workspace.pluginsEmpty' => 'No plugins installed',
			'workspace.pluginsEmptyHint' => 'Install plugins from Discovery to enable them for this workspace.',
			'workspace.pluginsManage' => 'Manage plugins',
			'workspace.primaryPath' => 'Primary directory',
			'workspace.primaryPathNotSelected' => 'No primary directory selected',
			'workspace.primaryPathRequired' => 'Select a primary directory first.',
			'workspace.runningSessionsSection' => 'Open',
			'workspace.searchBackend' => ({required String backend}) => 'Engine: ${backend}',
			'workspace.searchCancel' => 'Cancel',
			'workspace.searchCaseSensitive' => 'Aa',
			'workspace.searchContent' => 'Content',
			'workspace.searchEmptyHint' => 'Type to search file contents',
			'workspace.searchError' => 'Search failed — check the pattern',
			'workspace.searchExcludeHint' => 'Exclude (glob, comma-separated)',
			'workspace.searchFilesEmptyHint' => 'Type to search files',
			'workspace.searchFilesSection' => 'Files',
			'workspace.searchFilesToExclude' => 'Files to exclude:',
			'workspace.searchFilesToInclude' => 'Files to include:',
			'workspace.searchFilterAll' => 'All',
			'workspace.searchFilterConversations' => 'Tasks',
			'workspace.searchFilterFiles' => 'Files',
			'workspace.searchGitignore' => '.gitignore',
			'workspace.searchHint' => 'Search sessions, files and transcript content',
			'workspace.searchIncludeHint' => 'Include (glob, comma-separated)',
			'workspace.searchIndexing' => 'Indexing…',
			'workspace.searchNoResults' => 'No matches',
			'workspace.searchPanel' => 'Search',
			'workspace.searchQueryHint' => 'Search files',
			'workspace.searchRecentSessions' => 'Recent sessions',
			'workspace.searchRegex' => 'Regex',
			'workspace.searchReplace' => 'Replace',
			'workspace.searchReplaceAll' => 'Replace All',
			'workspace.searchReplaceAllMessage' => ({required int count}) => 'Replace ${count} occurrence(s)?',
			'workspace.searchReplaceAllTitle' => 'Replace all?',
			'workspace.searchReplaceHint' => 'Replace with',
			'workspace.searchReplacedCount' => ({required int count}) => 'Replaced ${count}',
			'workspace.searchResultSummary' => ({required int matches, required int files}) => '${matches} results in ${files} files',
			'workspace.searchSearching' => 'Searching files…',
			'workspace.searchShowMore' => 'Show more results',
			'workspace.searchSliceError' => ({required String directory}) => 'Search failed in "${directory}"',
			'workspace.searchTitle' => 'Search',
			'workspace.searchToggleDetails' => 'Toggle search details',
			'workspace.searchTruncated' => 'Results truncated — refine your query',
			'workspace.searchUseGitignore' => 'Use .gitignore settings',
			'workspace.sessionCount' => 'Sessions',
			'workspace.sidebarGroupsView' => 'Groups',
			'workspace.sidebarProjectTreeView' => 'Project tree',
			'workspace.skillsAssignedCount' => ({required int assigned, required int total}) => '${assigned} of ${total} enabled for this workspace',
			'workspace.skillsManage' => 'Manage skills',
			'workspace.targetSubtitle' => 'The machine this workspace\'s folders live and run on. Sessions launch on this target; switching does not move files.',
			_ => null,
		} ?? switch (path) {
			'workspace.targetTitle' => 'Workspace machine',
			'workspace.terminal' => 'Terminal',
			'workspace.terminalClose' => 'Close terminal panel',
			'workspace.terminalCloseSession' => 'Close terminal',
			'workspace.terminalNewSession' => 'New terminal',
			'workspace.terminalNewSessionMenu' => 'New terminal session menu',
			'workspace.terminalNewSshSession' => 'New SSH Session…',
			'workspace.terminalNoWorkingDirectory' => 'Connect a session to open the shell terminal',
			'workspace.terminalRestoring' => 'Restoring terminal…',
			'workspace.terminalSettings' => 'Settings',
			'workspace.terminalSshConnectFailed' => 'SSH profile not found or connection failed',
			'workspace.terminalThemeAdaptive' => 'Match app theme',
			'workspace.terminalThemeClassicDark' => 'Classic dark',
			'workspace.terminalThemeHighContrast' => 'High contrast',
			'workspace.toolsResolveFailed' => 'Could not open workspace tools',
			'workspace.toolsResolveFailedHint' => 'Check that remote machines are reachable, then try again.',
			'workspace.topologyLocal' => 'Local workspace',
			'workspace.topologyMixed' => 'Mixed workspace',
			'workspace.topologyRemote' => 'Remote workspace',
			'workspace.typeLabel' => 'Type',
			'workspace.updatedAt' => 'Updated',
			'workspace.workbenchAdvancedSettingsSubtitle' => 'Agent preset and extra CLI flags for this workspace.',
			'worktree.baseSelectorHint' => 'Branch or ref',
			'worktree.branchLabel' => 'Branch name',
			'worktree.createAction' => 'Create',
			'worktree.createFailed' => ({required Object error}) => 'Failed to create worktree: ${error}',
			'worktree.createTitle' => 'New worktree',
			'worktree.creating' => 'Creating…',
			'worktree.deleteAction' => 'Remove',
			'worktree.deleteBody' => ({required Object branch}) => 'Remove the worktree for ${branch}?',
			'worktree.deleteBranchToo' => 'Also delete the branch',
			'worktree.deleteBusyWarning' => 'Stop the running conversations in this worktree before removing it.',
			'worktree.deleteFailed' => ({required Object error}) => 'Failed to remove worktree: ${error}',
			'worktree.deleteForce' => 'Force-remove even if it has uncommitted changes',
			'worktree.deleteSessionsToo' => ({required Object count}) => 'Also delete the ${count} conversations in this worktree',
			'worktree.deleteTitle' => 'Remove worktree',
			'worktree.menuCopyPath' => 'Copy path',
			'worktree.menuRemove' => 'Remove worktree',
			'worktree.more' => 'More',
			'worktree.newConversationHere' => 'New conversation here',
			'worktree.newWorktreeTooltip' => 'New worktree',
			'worktree.orphanGroup' => 'Other',
			'worktree.pathLabel' => 'Location',
			'worktree.randomNameTooltip' => 'Random name',
			'worktree.refreshTooltip' => 'Refresh worktrees',
			'worktree.showLess' => 'Show less',
			'worktree.showMore' => ({required Object count}) => 'Show ${count} more',
			_ => null,
		};
	}
}
