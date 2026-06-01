// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TeamPilot';

  @override
  String get appRailChat => 'Chat';

  @override
  String get appRailRuns => 'Runs';

  @override
  String get appRailConfig => 'Config';

  @override
  String get copy => 'copy';

  @override
  String get settings => 'Settings';

  @override
  String get settingsPageSubtitle =>
      'Manage FlashskyAI team and model settings.';

  @override
  String get layout => 'Layout';

  @override
  String get layoutSubtitle => 'global workbench';

  @override
  String get save => 'Save';

  @override
  String get layoutPageSubtitle =>
      'Structure controls are global and apply across teams.';

  @override
  String get toolPlacement => 'Tool Placement';

  @override
  String get right => 'Right';

  @override
  String get bottom => 'Bottom';

  @override
  String get rightTools => 'Right Tools';

  @override
  String get openRightTools => 'Tools';

  @override
  String get rightToolsPanelVisible => 'Show tools panel';

  @override
  String get rightToolsPanelHidden => 'Hide tools panel';

  @override
  String get bottomTray => 'Bottom Tray';

  @override
  String get stacked => 'Stacked';

  @override
  String get tabs => 'Tabs';

  @override
  String get stackedTools => 'Stacked Tools';

  @override
  String get tabbedTools => 'Tabbed Tools';

  @override
  String get regionVisibility => 'Region Visibility';

  @override
  String get appRail => 'App rail';

  @override
  String get toolPlacementDescription =>
      'Dock tool panels on the right or along the bottom edge.';

  @override
  String get visibilityTeamSessionsHint =>
      'Show the team sessions list in the left sidebar.';

  @override
  String get visibilityMembersHint =>
      'Show the member list next to tools or terminals.';

  @override
  String get visibilityFileTreeHint =>
      'Show the project file tree for quick navigation.';

  @override
  String get extensionsSettingsTitle => 'Extensions';

  @override
  String get extensionsSettingsDescription =>
      'Install and enable external tools that augment your agents.';

  @override
  String get extensionEnableLabel => 'Enabled';

  @override
  String get extensionInstall => 'Install';

  @override
  String get extensionUninstall => 'Uninstall';

  @override
  String get extensionInstallGuide => 'Install guide';

  @override
  String get extensionStatusNotInstalled => 'Not installed';

  @override
  String get extensionStatusReady => 'Ready';

  @override
  String extensionStatusReadyVersion(String version) {
    return 'Ready ($version)';
  }

  @override
  String get extensionStatusDependencyMissing => 'Missing dependency';

  @override
  String get extensionStatusVersionTooOld => 'Installed version is too old';

  @override
  String get extensionKindMcpServer => 'Code intelligence (MCP)';

  @override
  String get extensionKindSettingsHook => 'Token savings (hook)';

  @override
  String get rtkSettingsTitle => 'RTK token savings';

  @override
  String get rtkSettingsEnableTitle => 'Enable RTK';

  @override
  String get rtkSettingsDescription =>
      'Compress Agent Bash command output before it reaches the model (requires rtk and jq on PATH).';

  @override
  String get rtkSettingsStatusTitle => 'Host status';

  @override
  String get rtkSettingsInstallLink => 'Install guide';

  @override
  String get rtkStatusNotFound => 'rtk not found on PATH';

  @override
  String get rtkStatusJqMissing => 'jq not found on PATH';

  @override
  String get rtkStatusInstalledGeneric => 'rtk ready';

  @override
  String rtkStatusInstalled(String version) {
    return 'rtk $version ready';
  }

  @override
  String rtkStatusVersionTooOld(String version) {
    return 'rtk $version is too old (need >= 0.23.0)';
  }

  @override
  String get rtkBashOnlyHint =>
      'Only applies to Agent Bash tool calls. Built-in Read, Grep, and Glob are not rewritten.';

  @override
  String get themeModeTitle => 'Theme mode';

  @override
  String get themeModeDescription =>
      'Light, dark, or match the operating system appearance.';

  @override
  String get themeColorPresetTitle => 'Theme colors';

  @override
  String get themeColorPresetDescription =>
      'Primary and accent colors for buttons, toggles, and highlights.';

  @override
  String get typographyScaleTitle => 'Text size';

  @override
  String get typographyScaleDescription =>
      'Overall UI text scale for menus, lists, forms, and the terminal.';

  @override
  String get typographyScaleCompact => 'Small';

  @override
  String get typographyScaleStandard => 'Standard';

  @override
  String get typographyScaleComfortable => 'Large';

  @override
  String get typographyScaleCustom => 'Custom';

  @override
  String get typographyScaleCustomLabel => 'Scale';

  @override
  String get typographyScaleCustomHint => '75–135';

  @override
  String get themePresetGraphite => 'Graphite';

  @override
  String get themePresetOcean => 'Ocean';

  @override
  String get themePresetViolet => 'Violet';

  @override
  String get themePresetAmber => 'Amber';

  @override
  String get themePresetForest => 'Forest';

  @override
  String get languageDescription =>
      'Language used for menus, buttons, and labels.';

  @override
  String get cancel => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get chatTo => 'To:';

  @override
  String get copyPrompt => 'Copy prompt';

  @override
  String get sendPrompt => 'Send prompt';

  @override
  String get chatHintText => 'Write a prompt for team-lead...';

  @override
  String get emptyTimeline =>
      'Local shell-mode conversation notes will appear here.';

  @override
  String get fileTree => 'File Tree';

  @override
  String get openTeam => 'Open Team';

  @override
  String get openMember => 'Open member';

  @override
  String get memberPresenceOffline => 'Offline';

  @override
  String get memberPresenceConnecting => 'Connecting…';

  @override
  String get memberPresenceIdle => 'Idle';

  @override
  String get memberPresenceWorking => 'Working';

  @override
  String get filterFiles => 'Filter files';

  @override
  String get selectTeam => 'Select team';

  @override
  String get addTeamTooltip => 'Add team';

  @override
  String get addTeamTitle => 'Add team';

  @override
  String get teamCliLabel => 'CLI backend';

  @override
  String get teamCliSubtitle =>
      'Chosen when the team is created and cannot be changed later.';

  @override
  String get teamCliComingSoon => 'Coming soon';

  @override
  String get teamCliLockedSubtitle => 'Set when this team was created.';

  @override
  String get teamNameRequired => 'Team name is required.';

  @override
  String teamNameAlreadyExists(String name) {
    return 'A team named \"$name\" already exists.';
  }

  @override
  String get projects => 'Projects';

  @override
  String get newProject => 'New Project';

  @override
  String get newProjectTooltip => 'Create a project';

  @override
  String get switchProjectTooltip => 'Switch project';

  @override
  String get create => 'Create';

  @override
  String get pickPrimaryDirectory => 'Pick primary directory';

  @override
  String get projectPrimaryPathRequired => 'Select a primary directory first.';

  @override
  String get projectPrimaryPathNotSelected => 'No primary directory selected';

  @override
  String get projectDirectoryAdded => 'Directory added to project';

  @override
  String get newSessionTooltip => 'New session';

  @override
  String get defaultNewChatSessionTitle => 'New Chat';

  @override
  String get sessionStarting => 'Starting session…';

  @override
  String get sessionReadyTitle => 'Ready to chat';

  @override
  String sessionReadySubtitle(String memberName) {
    return 'Start a conversation with $memberName in this workspace.';
  }

  @override
  String get sessionReadySubtitleGeneric =>
      'Start a conversation in this workspace.';

  @override
  String get sessionReadyHint =>
      'Describe what you want in everyday language — no terminal commands needed.';

  @override
  String get sessionStartButton => 'Start conversation';

  @override
  String get sessionFailedTitle => 'Couldn\'t start session';

  @override
  String get sessionRetryButton => 'Try again';

  @override
  String get openFolder => 'Open Folder';

  @override
  String get copyFolderPath => 'Copy Folder Path';

  @override
  String pathCopied(String path) {
    return 'Path copied: $path';
  }

  @override
  String get projectDetails => 'Project details';

  @override
  String get projectDetailsTitle => 'Project Details';

  @override
  String get addProjectDirectory => 'Add directory';

  @override
  String get removeProjectDirectory => 'Remove directory';

  @override
  String get projectDisplayName => 'Display name';

  @override
  String get projectPrimaryPath => 'Primary directory';

  @override
  String get projectAdditionalDirectories => 'Additional directories';

  @override
  String get projectNoAdditionalDirectories => 'No additional directories';

  @override
  String get projectSessionCount => 'Sessions';

  @override
  String get projectCreatedAt => 'Created';

  @override
  String get projectUpdatedAt => 'Updated';

  @override
  String get projectDirectoryAlreadyPrimary =>
      'This path is already the primary directory.';

  @override
  String get projectDirectoryAlreadyAdded =>
      'This directory is already in the project.';

  @override
  String get deleteProject => 'Delete Project';

  @override
  String deleteProjectConfirm(String name) {
    return 'Delete project \"$name\" and all its sessions? This cannot be undone.';
  }

  @override
  String get noSessions => 'No sessions yet';

  @override
  String get unknownFolder => 'Unknown';

  @override
  String get renameConversation => 'Rename conversation';

  @override
  String get deleteConversation => 'Delete conversation';

  @override
  String get renameConversationTitle => 'Rename Conversation';

  @override
  String deleteConversationConfirm(String name) {
    return 'Delete conversation \"$name\"? This cannot be undone.';
  }

  @override
  String get conversationName => 'Conversation name';

  @override
  String get closeTab => 'Close';

  @override
  String get closeOtherTabs => 'Close Others';

  @override
  String get closeRightTabs => 'Close to the Right';

  @override
  String get session => 'Session';

  @override
  String get sessionPageSubtitle =>
      'Configure shell session launch and the LLM config file path.';

  @override
  String get connectionModeLabel => 'Runtime mode';

  @override
  String get connectionModeDescription =>
      'Local runs flashskyai on this device. SSH runs it on the selected remote server.';

  @override
  String get connectionModeLocal => 'Local';

  @override
  String get connectionModeSsh => 'SSH';

  @override
  String get sshProfilesSettingsTitle => 'SSH servers';

  @override
  String get sshProfileSelectorTooltip => 'Switch SSH server';

  @override
  String get sshProfileSelectorManage => 'Manage SSH servers…';

  @override
  String get cliExecutablePathLabel => 'flashskyai CLI path';

  @override
  String get cliExecutablePathDescription =>
      'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.';

  @override
  String get cliExecutablePathDescriptionSsh =>
      'Absolute path to flashskyai on the remote SSH host. Leave empty to auto-discover over SSH.';

  @override
  String get cliExecutablePathBrowse => 'Browse…';

  @override
  String get cliExecutablePathApply => 'Apply';

  @override
  String get cliExecutablePathReset => 'Reset';

  @override
  String get cliExecutablePathUsing => 'Using: ';

  @override
  String get cliExecutablePathUsingFallback => 'Using PATH lookup';

  @override
  String get cliInstallButton => 'Install';

  @override
  String get cliInstallInstalling => 'Installing…';

  @override
  String get cliInstallProgressCheckingNpm => 'Checking for npm…';

  @override
  String get cliInstallProgressBootstrappingNode => 'Installing Node.js…';

  @override
  String get cliInstallProgressInstallingClaude => 'Installing Claude Code…';

  @override
  String get cliInstallProgressLocatingExecutable =>
      'Locating Claude Code executable…';

  @override
  String get claudeCliExecutablePathLabel => 'Claude Code CLI path';

  @override
  String get claudeCliExecutablePathDescription =>
      'Absolute path to the Claude Code executable. Leave empty to use the one on PATH.';

  @override
  String get claudeCliExecutablePathDescriptionSsh =>
      'Absolute path to Claude Code on the remote SSH host. Leave empty to resolve claude from the remote PATH.';

  @override
  String get shellChatWorkbench => 'Shell chat workbench';

  @override
  String get shellSession => 'Shell session';

  @override
  String get terminalFind => 'Find in terminal';

  @override
  String get terminalFindNoResults => 'No results';

  @override
  String get editorTitle => 'Editor';

  @override
  String get editorSave => 'Save';

  @override
  String get editorCut => 'Cut';

  @override
  String get editorCopy => 'Copy';

  @override
  String get editorCopyAsAiContext => 'Copy as AI context';

  @override
  String get editorPaste => 'Paste';

  @override
  String get editorSelectAll => 'Select all';

  @override
  String get editorUndoEdit => 'Undo';

  @override
  String get editorRedoEdit => 'Redo';

  @override
  String get editorRevertChanges => 'Revert changes';

  @override
  String get editorClose => 'Close editor';

  @override
  String get editorUnsavedChangesTitle => 'Unsaved changes';

  @override
  String editorUnsavedChangesDiscardFile(String fileName) {
    return 'Discard unsaved changes to \"$fileName\"?';
  }

  @override
  String editorUnsavedChangesDiscardMultiple(int count) {
    return 'Discard unsaved changes in $count file(s)?';
  }

  @override
  String get editorDiscard => 'Discard';

  @override
  String get editorNotReady => 'Editor not ready';

  @override
  String get editorNoFileOpen => 'No file open';

  @override
  String get editorBinaryFileHint =>
      'Binary files open with the system default app.';

  @override
  String get editorFileNotFound => 'File not found';

  @override
  String get editorFileTooLarge =>
      'File is too large to edit in TeamPilot (max 2 MB).';

  @override
  String get editorCouldNotReadFile => 'Could not read file';

  @override
  String get editorFileReadOnly => 'File is read-only';

  @override
  String editorSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get fileTreeRevealActiveFile => 'Reveal active file';

  @override
  String get fileTreeRevealFailed => 'Cannot reveal this file in the file tree';

  @override
  String get fileTreeOpenWithSystemApp => 'Open with system app';

  @override
  String get fileTreeCopyPath => 'Copy path';

  @override
  String get fileTreeDeleteItemTitle => 'Delete';

  @override
  String fileTreeDeleteItemConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get terminalOpenLink => 'Open link';

  @override
  String get terminalExportScrollback => 'Export scrollback…';

  @override
  String get terminalCopySelectHint => 'Shift+drag to copy';

  @override
  String get workspaceTerminal => 'Terminal';

  @override
  String get workspaceTerminalShow => 'Show terminal';

  @override
  String get workspaceTerminalHide => 'Hide terminal';

  @override
  String get workspaceTerminalClose => 'Close terminal panel';

  @override
  String get workspaceTerminalNoWorkingDirectory =>
      'Connect a session to open the shell terminal';

  @override
  String get workspaceTerminalNewSession => 'New terminal';

  @override
  String get workspaceTerminalCloseSession => 'Close terminal';

  @override
  String get terminalScrollbackLinesTitle => 'Terminal scrollback lines';

  @override
  String get terminalScrollbackLinesDescription =>
      'Maximum lines kept in each session terminal buffer';

  @override
  String get autoLaunchAllMembersTitle => 'Start all members on connect';

  @override
  String get autoLaunchAllMembersDescription =>
      'When enabled, Connect and Restart launch every valid member shell; otherwise only the selected member starts.';

  @override
  String get scopeSessionsToSelectedTeamTitle =>
      'Scope sessions to selected team';

  @override
  String get scopeSessionsToSelectedTeamDescription =>
      'When enabled, the sidebar shows only sessions assigned to the current team. New sessions are always tagged with the selected team so they appear here if you turn this on later.';

  @override
  String get windowsStorageBackendTitle => 'Data storage location';

  @override
  String get windowsStorageBackendDescription =>
      'Where teams, skills, projects, and config profiles are stored. Switching uses a separate data tree; nothing is migrated automatically.';

  @override
  String get windowsStorageBackendNative => 'Windows local';

  @override
  String get windowsStorageBackendWsl => 'WSL';

  @override
  String windowsStorageBackendCurrentRoot(String path) {
    return 'Current root: $path';
  }

  @override
  String get windowsStorageBackendSwitchConfirmTitle =>
      'Switch storage location?';

  @override
  String get windowsStorageBackendSwitchConfirmBody =>
      'This uses a different data directory. Teams, projects, and skills from the other location will not appear until you switch back.';

  @override
  String get windowsStorageBackendSwitchConfirmAction => 'Switch';

  @override
  String get windowsStorageBackendWslUnavailable =>
      'WSL is not available. Install or start WSL before using WSL storage.';

  @override
  String get windowsStorageCliMismatchNativeCli =>
      'CLI runs in WSL but data is stored in Windows AppData. Config may not match.';

  @override
  String get windowsStorageCliMismatchWslCli =>
      'CLI runs on Windows but data is stored in WSL. Config may not match.';

  @override
  String get windowsStorageSwitchReloadHint =>
      'Reconnect open sessions after switching storage.';

  @override
  String bootstrapStartupFailed(String error) {
    return 'Startup failed: $error';
  }

  @override
  String get bootstrapUseNativeStorageInstead =>
      'Use Windows local storage instead';

  @override
  String get runsPlaceholder => 'Run history will appear here.';

  @override
  String get llmConfig => 'Provider';

  @override
  String get llmConfigSubtitle => 'providers and models';

  @override
  String get llmConfigPathLabel => 'LLM config file';

  @override
  String get llmConfigPathHint => 'Leave empty to use the default path';

  @override
  String get llmConfigPathBrowse => 'Browse...';

  @override
  String get llmConfigPathSave => 'Apply';

  @override
  String get llmConfigPathReset => 'Use default';

  @override
  String get llmConfigPathBadgeDefault => 'default';

  @override
  String get llmConfigPathBadgeCustom => 'custom';

  @override
  String get llmConfigPathPickerTitle => 'Select llm_config.json';

  @override
  String get llmConfigPathSessionCardDescription =>
      'Absolute path to the LLM config file (llm_config.json). Leave empty to use the default path next to the CLI install.';

  @override
  String get llmConfigPathSessionCardDescriptionSsh =>
      'Absolute path to llm_config.json on the remote SSH host. Leave empty to use the default path next to the remote CLI install.';

  @override
  String get llmConfigCurrentEffectivePathPrefix => 'Active file:';

  @override
  String get llmConfigEffectivePathUnresolved =>
      'Could not resolve a path yet (set the CLI location or enter a path).';

  @override
  String get llmConfigOpenSessionSettings => 'Session settings…';

  @override
  String get providers => 'PROVIDERS';

  @override
  String get llmConfigPageSubtitle => 'Manage LLM providers and models.';

  @override
  String get providersTab => 'Providers';

  @override
  String get modelsTab => 'Models';

  @override
  String get rawJsonTab => 'Raw JSON';

  @override
  String get addProvider => 'Add Provider';

  @override
  String get providerName => 'Provider name';

  @override
  String get renameProviderName => 'Rename';

  @override
  String get renameProviderTitle => 'Rename provider';

  @override
  String get deleteProvider => 'Delete Provider';

  @override
  String deleteProviderConfirm(String name) {
    return 'Delete provider $name?';
  }

  @override
  String get providerList => 'Provider List';

  @override
  String get filterProviders => 'Filter providers...';

  @override
  String get appProviderImport => 'Import';

  @override
  String get appProviderImportNothing => 'No providers found to import.';

  @override
  String appProviderImportSuccess(int count, int mirrored, int skipped) {
    return 'Imported $count providers. Mirrored $mirrored to FlashskyAI, skipped $skipped existing.';
  }

  @override
  String modelsUsingProvider(int count) {
    return 'Models using this provider: $count';
  }

  @override
  String providerListModelCount(int count) {
    return '$count models';
  }

  @override
  String get proxyOnShort => 'Proxy on';

  @override
  String get proxyOffShort => 'Proxy off';

  @override
  String providerDetailSubtitle(int count, String type) {
    return '$type provider · $count models';
  }

  @override
  String get type => 'Type';

  @override
  String get providerType => 'Provider type';

  @override
  String get providerTypeHint => 'openai, claude, or custom';

  @override
  String get proxy => 'Proxy';

  @override
  String get proxyUrl => 'Proxy URL';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get appProviderApiKeyEditHint =>
      'Leave blank to keep the existing key';

  @override
  String get reveal => 'Reveal';

  @override
  String get hide => 'Hide';

  @override
  String get replaceKey => 'Replace key';

  @override
  String get deleteProviderTooltip => 'Delete provider';

  @override
  String deleteProviderWithCredentialsConfirm(String name) {
    return 'Delete provider $name? Saved Claude login credentials for this provider will also be removed.';
  }

  @override
  String get claudeOfficialCredentialsTitle => 'Claude Official login';

  @override
  String get claudeOfficialCredentialsReady => 'Credentials ready';

  @override
  String get claudeOfficialCredentialsMissing =>
      'No credentials saved for this provider';

  @override
  String get claudeOfficialCredentialsAuthenticated => 'Authenticated';

  @override
  String get claudeOfficialCredentialsUnauthenticated => 'Unauthenticated';

  @override
  String get claudeOfficialCredentialsLogin => 'Sign in with Claude';

  @override
  String get claudeOfficialCredentialsImportGlobal => 'Import from ~/.claude';

  @override
  String get claudeOfficialCredentialsImportFile => 'Import file…';

  @override
  String get claudeOfficialCredentialsRevoke => 'Sign out';

  @override
  String claudeOfficialCredentialsRevokeConfirm(String name) {
    return 'Sign out and remove saved credentials for $name?';
  }

  @override
  String get claudeOfficialCredentialsActionSuccess => 'Credentials updated';

  @override
  String get claudeOfficialCredentialsActionFailed =>
      'Could not update credentials';

  @override
  String get claudeLaunchCredentialsMissingWarning =>
      'Claude Official credentials are missing for this team provider. Sign in from Providers settings.';

  @override
  String get noModelsUsingProvider => 'No models are using this provider.';

  @override
  String get modelsUsingProviderTitle => 'Models using this provider';

  @override
  String get selectProvider => 'Select a provider from the list';

  @override
  String get accountCredentialPath => 'Account credential path';

  @override
  String get removePath => 'Remove path';

  @override
  String get addAccountPath => 'Add account path';

  @override
  String get api => 'api';

  @override
  String get account => 'account';

  @override
  String get models => 'Models';

  @override
  String get addModel => 'Add Model';

  @override
  String get modelName => 'Model alias/name';

  @override
  String get modelId => 'Model ID';

  @override
  String get enabled => 'Enabled';

  @override
  String get edit => 'Edit';

  @override
  String editModelTitle(String name) {
    return 'Edit $name';
  }

  @override
  String get name => 'Name';

  @override
  String get actualModel => 'Actual Model';

  @override
  String get noModelsConfigured => 'No models configured';

  @override
  String get missingProvider => 'Missing provider:';

  @override
  String get summary => 'Summary';

  @override
  String get statProviders => 'providers';

  @override
  String get statModels => 'models';

  @override
  String get statMissingRefs => 'missing refs';

  @override
  String get statEmptyKeys => 'empty keys';

  @override
  String get validation => 'Validation';

  @override
  String get allChecksPassed => 'All checks passed.';

  @override
  String get validate => 'Validate';

  @override
  String get back => 'Back';

  @override
  String get jsonPreview => 'JSON Preview';

  @override
  String get skillsTitle => 'Skills';

  @override
  String get skillsSubtitle => 'Manage installable skills';

  @override
  String get skillsSidebarLabel => 'Skills';

  @override
  String get skillsNavInstalled => 'Installed';

  @override
  String get skillsNavDiscovery => 'Discovery';

  @override
  String get skillsNavRepos => 'Repos';

  @override
  String skillsInstalledCount(int count) {
    return '$count installed';
  }

  @override
  String get skillsCheckUpdates => 'Check updates';

  @override
  String get skillsCheckingUpdates => 'Checking…';

  @override
  String skillsUpdateAll(int count) {
    return 'Update all ($count)';
  }

  @override
  String get skillsImportFromDisk => 'Import from disk';

  @override
  String get skillsInstallFromZip => 'Install from ZIP';

  @override
  String get skillsNoInstalled => 'No skills installed yet';

  @override
  String get skillsNoInstalledHint =>
      'Open Discovery to install your first skill.';

  @override
  String get skillsGoDiscovery => 'Go to Discovery';

  @override
  String get skillsSourceRepos => 'Repos';

  @override
  String get skillsSourceSkillsSh => 'skills.sh';

  @override
  String get skillsSearchPlaceholder => 'Search skills…';

  @override
  String get skillsSkillsShPlaceholder => 'Search skills.sh (≥ 2 chars)…';

  @override
  String get skillsFilterRepoAll => 'All repos';

  @override
  String get skillsFilterAll => 'All';

  @override
  String get skillsFilterInstalled => 'Installed';

  @override
  String get skillsFilterUninstalled => 'Not installed';

  @override
  String get skillsCardInstall => 'Install';

  @override
  String get skillsCardDetails => 'Details';

  @override
  String get skillsCardInstalled => 'Installed';

  @override
  String get skillsCardUpdate => 'Update';

  @override
  String get skillsCardUninstall => 'Uninstall';

  @override
  String get skillsUpdateAvailable => 'Update available';

  @override
  String get skillsLocal => 'local';

  @override
  String get skillsReposEmpty => 'No repos yet';

  @override
  String get skillsRepoAdd => 'Add repo';

  @override
  String get skillsDiscoverySyncing =>
      'Checking repos for updates and syncing skills in the background…';

  @override
  String get skillsRepoSyncing => 'Updating';

  @override
  String get skillsRepoInvalidUrl =>
      'Enter a valid GitHub repo URL, e.g. https://github.com/owner/repo';

  @override
  String get skillsRepoUrl => 'Repository URL';

  @override
  String get skillsRepoUrlHint => 'https://github.com/owner/repo';

  @override
  String get skillsRepoBranch => 'Branch';

  @override
  String get skillsRepoRemove => 'Remove';

  @override
  String skillsRepoRemoveConfirm(String name) {
    return 'Remove repo $name?';
  }

  @override
  String skillsUninstallConfirm(String name) {
    return 'Uninstall $name?';
  }

  @override
  String skillsOverwriteConfirm(String name) {
    return '$name already installed. Overwrite?';
  }

  @override
  String skillsInstallSuccess(String name) {
    return 'Installed $name';
  }

  @override
  String skillsUninstallSuccess(String name) {
    return 'Uninstalled $name';
  }

  @override
  String skillsUpdateSuccess(String name) {
    return 'Updated $name';
  }

  @override
  String get skillsNoUpdates => 'All skills are up to date';

  @override
  String get skillsImportTitle => 'Import unmanaged skills';

  @override
  String get skillsImportNothing => 'No unmanaged skills found.';

  @override
  String skillsImportSelected(int count) {
    return 'Import $count selected';
  }

  @override
  String get skillsZipNoSkills => 'No SKILL.md found in the archive.';

  @override
  String get skillsSkillsShLoadMore => 'Load more';

  @override
  String get skillsSkillsShPoweredBy => 'Powered by skills.sh';

  @override
  String get skillsSkillsShSearch => 'Search';

  @override
  String get skillsDiscoveryEmpty => 'No skills discovered';

  @override
  String get skillsDiscoveryEmptyHint =>
      'Add a repo or try skills.sh to find skills.';

  @override
  String get skillsAdd => 'Add';

  @override
  String get skillsRemove => 'Remove';

  @override
  String get skillsEnabled => 'Enabled';

  @override
  String skillsInstalls(int count) {
    return '$count installs';
  }

  @override
  String get pluginsTitle => 'Plugins';

  @override
  String get pluginsSubtitle => 'Manage Claude Code-style plugin bundles';

  @override
  String get pluginsSidebarLabel => 'Plugins';

  @override
  String get pluginsNavInstalled => 'Installed';

  @override
  String get pluginsNavDiscovery => 'Discovery';

  @override
  String get pluginsNavMarketplaces => 'Marketplaces';

  @override
  String pluginsInstalledCount(int count) {
    return '$count installed';
  }

  @override
  String pluginsUpdateAll(int count) {
    return 'Update all ($count)';
  }

  @override
  String get pluginsImportFromDisk => 'Import from disk';

  @override
  String get pluginsImportTitle => 'Import unmanaged plugins';

  @override
  String get pluginsImportNothing => 'No unmanaged plugins found.';

  @override
  String get pluginsInstallFromZip => 'Install from ZIP';

  @override
  String get pluginsCheckUpdates => 'Check updates';

  @override
  String get pluginsCheckingUpdates => 'Checking…';

  @override
  String get pluginsNoInstalled => 'No plugins installed';

  @override
  String get pluginsNoInstalledHint =>
      'Add a marketplace and install plugins from the Discovery tab.';

  @override
  String get pluginsGoDiscovery => 'Browse marketplace';

  @override
  String get pluginsCardInstall => 'Install';

  @override
  String get pluginsCardDetails => 'Details';

  @override
  String get pluginsCardInstalled => 'Installed';

  @override
  String get pluginsCardViewSource => 'View source';

  @override
  String get pluginsCardUpdate => 'Update';

  @override
  String get pluginsCardUninstall => 'Uninstall';

  @override
  String get pluginsMarketplaceAdd => 'Add marketplace';

  @override
  String get pluginsMarketplaceUrl => 'GitHub repository URL';

  @override
  String get pluginsMarketplaceUrlHint =>
      'https://github.com/owner/marketplace';

  @override
  String get pluginsMarketplaceBranch => 'Branch';

  @override
  String get pluginsMarketplaceRemove => 'Remove marketplace';

  @override
  String pluginsMarketplaceRemoveConfirm(String url) {
    return 'Remove marketplace $url? Installed plugins are kept.';
  }

  @override
  String get pluginsMarketplaceInvalidUrl =>
      'Please enter a valid GitHub repository URL.';

  @override
  String get pluginsMarketplacesEmpty => 'No marketplaces configured';

  @override
  String get pluginsSearchPlaceholder => 'Search plugins';

  @override
  String get pluginsFilterMarketplaceAll => 'All marketplaces';

  @override
  String get pluginsFilterAll => 'All';

  @override
  String get pluginsFilterInstalled => 'Installed';

  @override
  String get pluginsFilterUninstalled => 'Not installed';

  @override
  String get pluginsDiscoveryEmpty => 'No matching plugins';

  @override
  String get pluginsDiscoverySyncing =>
      'Checking marketplaces for updates and syncing plugins in the background…';

  @override
  String pluginsUninstallConfirm(String name, int n) {
    return 'Uninstall $name? This may affect $n team(s).';
  }

  @override
  String get pluginsUninstallImpactList => 'Affected teams:';

  @override
  String pluginsUninstallSuccess(String name) {
    return 'Uninstalled $name';
  }

  @override
  String get members => 'Members';

  @override
  String get teamSessions => 'Team Sessions';

  @override
  String get configure => 'Configure';

  @override
  String get teamConfig => 'Team Config';

  @override
  String get teamSettings => 'Team Settings';

  @override
  String get teamSettingsSubtitle => 'workspace teams';

  @override
  String get membersSubtitle => 'team agents';

  @override
  String get teamSkillsNav => 'Skills';

  @override
  String teamSkillsAssignedCount(int assigned, int total) {
    return '$assigned of $total enabled';
  }

  @override
  String get teamSkillsManage => 'All skills';

  @override
  String get teamPluginsNav => 'Plugins';

  @override
  String get teamExtensionsNav => 'Extensions';

  @override
  String get teamExtensionsTitle => 'Extensions for this team';

  @override
  String get teamExtensionsSubtitle =>
      'Override which extensions run for this team. Default follows the global setting.';

  @override
  String get teamExtensionFollowGlobal => 'Follow global';

  @override
  String get teamExtensionForceOn => 'On';

  @override
  String get teamExtensionForceOff => 'Off';

  @override
  String get teamExtensionEffectiveOn => 'Active for this team';

  @override
  String get teamExtensionEffectiveOff => 'Inactive for this team';

  @override
  String get teamExtensionRtkGlobalOnlyHint =>
      'rtk currently applies globally; per-team override is not yet effective.';

  @override
  String get teamMcpNav => 'MCP';

  @override
  String teamMcpAssignedCount(int assigned, int total) {
    return '$assigned of $total enabled';
  }

  @override
  String get teamMcpManage => 'All MCP servers';

  @override
  String get mcpNavTitle => 'MCP Servers';

  @override
  String get mcpSubtitle =>
      'Manage MCP servers for Claude and FlashskyAI sessions.';

  @override
  String get mcpNavInstalled => 'Installed';

  @override
  String get mcpNavDiscovery => 'Discovery';

  @override
  String get mcpNavRegistries => 'Registry';

  @override
  String get mcpInstalledSectionTitle => 'Installed MCP servers';

  @override
  String mcpInstalledCount(int count) {
    return '$count installed';
  }

  @override
  String get mcpNoInstalled => 'No MCP servers installed yet';

  @override
  String get mcpNoInstalledHint =>
      'Open Discovery to add servers from built-in templates or registries.';

  @override
  String get mcpDiscoverySectionTitle => 'Discover MCP servers';

  @override
  String get mcpDiscoverySectionHint =>
      'Browse built-in templates and remote catalogs configured under Registries.';

  @override
  String get mcpDiscoverySourceBuiltin => 'Built-in';

  @override
  String get mcpSmitheryApiTokenLabel => 'API token';

  @override
  String get mcpSmitheryApiTokenHint => 'Smithery API key (Bearer)';

  @override
  String get mcpSmitheryApiTokenSet => 'token set';

  @override
  String get mcpRegistryEditTitle => 'Edit API URL';

  @override
  String get mcpRegistryResetTitle => 'Reset to default';

  @override
  String mcpRegistryResetConfirm(String name) {
    return 'Reset \"$name\" to the default API URL?';
  }

  @override
  String get mcpRepoApiUrlLabel => 'API base URL';

  @override
  String get mcpRepoTestConnection => 'Test connection';

  @override
  String get mcpRepoResetDefault => 'Reset default';

  @override
  String get mcpRepoConfigSaved => 'Registry API settings saved';

  @override
  String get mcpRepoTestOk => 'Connection successful';

  @override
  String mcpRepoTestFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get mcpRepoDisabledHint =>
      'This catalog source is disabled. Enable it under Registries.';

  @override
  String get mcpRegistrySmithery => 'Smithery';

  @override
  String get mcpRegistryOfficial => 'Official registry';

  @override
  String get mcpRegistrySmitheryHint => 'Smithery — https://api.smithery.ai';

  @override
  String get mcpRegistryOfficialHint =>
      'Official MCP Registry — https://registry.modelcontextprotocol.io';

  @override
  String get mcpRegistrySearchHint => 'Search servers (e.g. github)';

  @override
  String get mcpRegistryLoadMore => 'Load more';

  @override
  String get mcpCatalogAdd => 'Add';

  @override
  String get mcpCatalogInstalled => 'Installed';

  @override
  String get mcpCatalogAdded => 'MCP server added to catalog';

  @override
  String get mcpCatalogEmpty => 'No servers found';

  @override
  String get mcpCatalogVerified => 'Verified';

  @override
  String get mcpEmptyGoDiscovery => 'Browse built-in templates';

  @override
  String get mcpEmptyGoRegistries => 'Open registry settings';

  @override
  String get mcpAdd => 'Add MCP server';

  @override
  String get mcpEdit => 'Edit MCP server';

  @override
  String get mcpOpenHomepage => 'Open link';

  @override
  String get mcpFormDetailHint =>
      'Select a server to edit, or add a new MCP server.';

  @override
  String get mcpServerNotFound => 'MCP server not found';

  @override
  String get mcpImport => 'Import from machine';

  @override
  String get mcpImportEmpty =>
      'No MCP servers found in ~/.claude.json or ~/.flashskyai.json';

  @override
  String mcpImportSummary(int added, int conflicts) {
    return '$added new, $conflicts conflicts';
  }

  @override
  String get mcpImportOverwrite => 'Overwrite conflicts';

  @override
  String get mcpImportDone => 'MCP catalog updated';

  @override
  String get mcpEmpty => 'No MCP servers in catalog';

  @override
  String get mcpDeleteConfirm => 'Delete MCP server?';

  @override
  String get mcpFieldName => 'Name';

  @override
  String get mcpFieldCommand => 'Command';

  @override
  String get mcpFieldArgs => 'Arguments (space-separated)';

  @override
  String get mcpAddTitle => 'Add MCP';

  @override
  String get mcpAddButton => 'Add MCP';

  @override
  String get mcpImportExisting => 'Import existing';

  @override
  String mcpConfiguredCount(int count) {
    return '$count MCP server(s) configured';
  }

  @override
  String mcpOAuthConnectTitle(String name) {
    return 'Connect $name';
  }

  @override
  String get mcpOAuthConnectHint =>
      'Sign in with the MCP provider in your browser. Tokens are stored in Claude Code format under app config (same as /mcp → Authenticate).';

  @override
  String get mcpOAuthDiscovering => 'Discovering authorization server…';

  @override
  String get mcpOAuthOpenBrowser => 'Open browser';

  @override
  String get mcpOAuthCallbackUrlLabel => 'Redirect URL';

  @override
  String get mcpOAuthCallbackUrlHint =>
      'Paste the full URL after sign-in (contains ?code=)';

  @override
  String get mcpOAuthSubmitCallback => 'Submit URL';

  @override
  String get mcpOAuthStartConnect => 'Connect';

  @override
  String get mcpOAuthConnectAction => 'Connect';

  @override
  String get mcpOAuthConnectSuccess => 'MCP OAuth connected';

  @override
  String get mcpOAuthStatusConnected => 'OAuth connected';

  @override
  String get mcpOAuthStatusNeedsAuth => 'Needs OAuth';

  @override
  String get mcpPresetDescFetch =>
      'Fetch web pages and convert HTML to markdown for LLMs.';

  @override
  String get mcpPresetDescTime =>
      'Current time, timezone conversion, and date calculations.';

  @override
  String get mcpPresetDescMemory =>
      'Persistent memory graph for knowledge across sessions.';

  @override
  String get mcpPresetDescSequentialThinking =>
      'Structured step-by-step reasoning for complex problems.';

  @override
  String get mcpPresetDescContext7 =>
      'Up-to-date library documentation via Context7.';

  @override
  String get mcpFormIdLabel => 'MCP ID (unique) *';

  @override
  String get mcpFormDisplayNameLabel => 'Display name';

  @override
  String get mcpFormDisplayNameHint => 'e.g. @modelcontextprotocol/server-time';

  @override
  String get mcpFormMetadata => 'Additional info';

  @override
  String get mcpFormDescriptionLabel => 'Description';

  @override
  String get mcpFormDescriptionHint => 'Optional description';

  @override
  String get mcpFormTagsLabel => 'Tags (comma-separated)';

  @override
  String get mcpFormTagsHint => 'stdio, time, utility';

  @override
  String get mcpFormHomepageLabel => 'Homepage';

  @override
  String get mcpFormDocsLabel => 'Documentation';

  @override
  String get mcpFormJsonLabel => 'Full JSON configuration';

  @override
  String get mcpFormFormatJson => 'Format';

  @override
  String get mcpFormRequiredFields => 'MCP ID and display name are required.';

  @override
  String get mcpFormSubmitAdd => 'Add';

  @override
  String get confirm => 'Confirm';

  @override
  String teamPluginsAssignedCount(int assigned, int total) {
    return '$assigned of $total installed';
  }

  @override
  String get teamPluginsManage => 'All plugins';

  @override
  String get teamPluginsEmpty => 'No plugins installed';

  @override
  String get teamPluginsEmptyHint =>
      'Install plugins from Discovery to enable them per team.';

  @override
  String get teamPluginsGoDiscovery => 'Browse marketplace';

  @override
  String teamPluginsMissing(int count) {
    return '$count enabled plugin(s) missing on disk. Reinstall or remove below.';
  }

  @override
  String get teamPluginsRemoveMissing => 'Remove';

  @override
  String get teamPluginsMissingLabel => 'Missing on disk';

  @override
  String teamPluginsNameConflict(String dir) {
    return 'Linked as $dir due to name conflict';
  }

  @override
  String get teamPluginsCliUnsupportedBanner =>
      'This team\'s CLI does not support plugins yet. Selections are saved but ignored at launch.';

  @override
  String get memberQuickList => 'MEMBER QUICK LIST';

  @override
  String get teamName => 'Team name';

  @override
  String get teamDescription => 'Team description';

  @override
  String get teamDescriptionHint =>
      'Optional note for Claude roster and team context';

  @override
  String get deleteTeam => 'Delete team';

  @override
  String get deleteTeamSubtitle =>
      'Removes this team from the UI and the shared flashskyai data directory. This cannot be undone.';

  @override
  String deleteTeamConfirm(String name) {
    return 'Delete team \"$name\"? This cannot be undone.';
  }

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get teamExtraArgs => 'Team extra CLI arguments';

  @override
  String get teamExtraArgsHint => '--permission-mode acceptEdits';

  @override
  String get teamLoop => 'Phase loop';

  @override
  String get teamLoopSubtitle =>
      'Team mode: true auto-advances phases; false requires your confirmation.';

  @override
  String get teamLoopDefault => 'Default';

  @override
  String get teamLoopTrue => 'true — auto-advance';

  @override
  String get teamLoopFalse => 'false — confirm each phase';

  @override
  String get teamLeadBadge => 'Leader';

  @override
  String get teamLeadDelegateOnlyTitle => 'Team lead: plan and delegate only';

  @override
  String get teamLeadDelegateOnlySubtitle =>
      'When enabled, the team lead is blocked from using some tools.';

  @override
  String get memberLaunchOrder => 'Member launch order';

  @override
  String get saveMember => 'Save Member';

  @override
  String get editTeamSubtitle =>
      'Edit team identity, working directory, and launch order.';

  @override
  String get memberName => 'Member name';

  @override
  String get memberNameSubtitle =>
      'Display only in TeamPilot (sidebar, member list). To define responsibilities and boundaries, edit the prompt below.';

  @override
  String get provider => 'Provider';

  @override
  String get model => 'Model';

  @override
  String get agent => 'Agent';

  @override
  String get selectAgent => 'Select an agent';

  @override
  String get agentBuiltInNone => 'Default';

  @override
  String get agentBuiltInCustom => 'Custom…';

  @override
  String get agentBuiltInSubtitle =>
      'Which agent role this member uses; shapes behavior and capabilities.';

  @override
  String get agentCustomIdHint => 'Custom agent id';

  @override
  String get memberExtraArgs => 'Member extra CLI arguments';

  @override
  String get memberExtraArgsSubtitle =>
      'Extra flags applied only when this member starts.';

  @override
  String get memberDangerouslySkipPermissions => 'Skip all permission checks';

  @override
  String get memberDangerouslySkipPermissionsHint =>
      'Only for isolated / no-network sandboxes. Extremely risky otherwise.';

  @override
  String get prompt => 'Prompt';

  @override
  String get memberPromptSubtitle =>
      'Brief duty boundaries and role notes for the team lead.';

  @override
  String get memberPromptPresetsLabel => 'Presets';

  @override
  String get memberPromptPresetTeamLead => 'Team lead';

  @override
  String get memberPromptPresetTeamLeadText =>
      'Coordinate the team: break the user\'s request into a task list (each item with scope and acceptance criteria), then assign teammates to implement. Unless blocked, do not do large implementation yourself—you may read code and docs to understand the situation.\nTalk to the user in this session window. When assigning and following up, contact only other teammates (by member name); do not assign work to yourself. After teammates finish, reply to the user with conclusions, relevant files, and next steps.';

  @override
  String get memberPromptPresetDeveloper => 'Developer';

  @override
  String get memberPromptPresetDeveloperText =>
      'Implement assigned tasks only within the agreed scope.\nPrefer minimal diffs, run relevant tests, and report changed files with brief rationale.';

  @override
  String get memberPromptPresetReviewer => 'Reviewer';

  @override
  String get memberPromptPresetReviewerText =>
      'Review code only; do not modify files unless asked.\nEach finding must include file path, line, issue, and suggested fix.';

  @override
  String get memberPromptPresetResearcher => 'Researcher';

  @override
  String get memberPromptPresetResearcherText =>
      'Investigate and report only; do not change production code unless asked.\nOutput findings with file paths, relevant symbols, and recommended next steps.';

  @override
  String get selectModel => 'Select a model';

  @override
  String get memberOfficialClaudeModelHint =>
      'Uses your Claude account default model. Manage Official login in Providers settings.';

  @override
  String get editMemberSubtitle =>
      'Edit provider, model, agent, and command arguments.';

  @override
  String get teamLeadNameRequired =>
      'FlashskyAI team delegation expects this member to be named exactly team-lead.';

  @override
  String get teamLeadNotice =>
      'FlashskyAI team delegation expects this member to be named exactly team-lead.';

  @override
  String get membersAndFileTree => 'Members and File Tree';

  @override
  String get membersAndFileTreeDescription =>
      'Show members and file tree stacked or as tabs.';

  @override
  String get appProviderCatalogLabel => 'App provider catalog';

  @override
  String get appProviderCatalogHint =>
      'TeamPilot stores unified providers here; team launches generate per-tool configs.';

  @override
  String get appProviderPresetLabel => 'Preset';

  @override
  String get appProviderPresetCustom => 'Custom';

  @override
  String get appProviderClaudeApiFormatAnthropic =>
      'Anthropic Messages (native)';

  @override
  String get appProviderClaudeApiFormatOpenaiChat => 'OpenAI Chat Completions';

  @override
  String get appProviderClaudeApiFormatOpenaiResponses => 'OpenAI Responses';

  @override
  String get appProviderClaudeApiFormatGeminiNative => 'Gemini Native';

  @override
  String get appProviderClaudeAuthTokenDefault =>
      'ANTHROPIC_AUTH_TOKEN (default)';

  @override
  String get appProviderClaudeAuthApiKey => 'ANTHROPIC_API_KEY';

  @override
  String get appProviderAdvancedJson => 'Advanced JSON editor';

  @override
  String get appProviderAdvancedOptions => 'Advanced options';

  @override
  String get appProviderWebsite => 'Website';

  @override
  String get appProviderEnabledTools => 'Enabled tools';

  @override
  String get appProviderToolFlashskyai => 'FlashskyAI';

  @override
  String get appProviderToolCodex => 'Codex';

  @override
  String get appProviderToolClaude => 'Claude Code';

  @override
  String get appProviderTeamToolSection => 'Tool providers for this team';

  @override
  String get appProviderTeamToolSubtitle =>
      'Select which unified provider each tool uses when this team starts.';

  @override
  String get appProviderTeamNone => 'None';

  @override
  String get appProviderClaudeApiFormat => 'API format';

  @override
  String get appProviderClaudeApiFormatHint =>
      'Select the provider API input format.';

  @override
  String get appProviderClaudeAuthField => 'Authentication field';

  @override
  String get appProviderClaudeAuthFieldHint =>
      'Select the authentication environment variable written to settings.';

  @override
  String get appProviderClaudeModelMapping => 'Model mapping';

  @override
  String get appProviderClaudeModelMappingHint =>
      'Leave these empty for native Claude providers. Fill them only when a provider maps Claude model roles to different model names.';

  @override
  String get appProviderClaudeHaikuModel => 'Haiku default model';

  @override
  String get appProviderClaudeSonnetModel => 'Sonnet default model';

  @override
  String get appProviderClaudeOpusModel => 'Opus default model';

  @override
  String get notes => 'Notes';

  @override
  String get defaultModel => 'Default model';

  @override
  String get editProvider => 'Edit provider';

  @override
  String get invalidJson => 'Invalid JSON. Fix the syntax and try again.';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutPageSubtitle => 'TeamPilot version and application updates.';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutCurrentVersion => 'Current version';

  @override
  String get aboutVersionLoading => 'Loading…';

  @override
  String get appUpdateCheck => 'Check for updates';

  @override
  String get appUpdateDownloadInstall => 'Download and install';

  @override
  String get appUpdateUpToDate => 'You are on the latest version.';

  @override
  String get appUpdateDownloading => 'Downloading update…';

  @override
  String get appUpdateInstalling => 'Installing update…';

  @override
  String get appUpdateViewRelease => 'View release on GitHub';

  @override
  String get appUpdateViewReleases => 'Releases';

  @override
  String appUpdateNewVersion(String version) {
    return 'Version $version available';
  }

  @override
  String get appUpdateDialogTitle => 'New version available';

  @override
  String get appUpdateLatestVersion => 'Latest version';

  @override
  String get appUpdateUnknownVersion => 'Unknown';

  @override
  String get appUpdateChangelogTitle => 'What\'s new';

  @override
  String get appUpdateChangelogDefaultSection => 'Updates';

  @override
  String get appUpdateReadyToDownload => 'Ready to download';

  @override
  String get appUpdateLater => 'Later';

  @override
  String get appUpdateDownloadNow => 'Download now';

  @override
  String get appUpdateDownloadInBackground => 'Download in background';

  @override
  String get appUpdateInstallNow => 'Install now';

  @override
  String get appUpdateBrowserDownload => 'Download in browser';

  @override
  String get appUpdateInvalidPackagePath => 'Invalid package path';

  @override
  String get appUpdateReleaseBuildRequired =>
      'Use a release build for in-app installation';

  @override
  String get appUpdatePackagePlatformMismatch =>
      'Package type does not match this system';

  @override
  String appUpdateInstallFailed(String message) {
    return 'Install failed: $message';
  }

  @override
  String get appUpdateInstallNoResult => 'Install returned no result';

  @override
  String get appUpdateInstallComplete => 'Installation complete';

  @override
  String get appUpdateRedirectBrowserOnly =>
      'This link must be downloaded in the browser';

  @override
  String get appUpdateDownloadStarting => 'Starting download…';

  @override
  String get appUpdateDownloadComplete => 'Download complete';

  @override
  String get appUpdateDownloadFailed => 'Download failed';

  @override
  String appUpdateDownloadError(String error) {
    return 'Error while downloading: $error';
  }

  @override
  String get appUpdateResolvingDownloadUrl => 'Resolving download link…';

  @override
  String get appUpdateBrowserOpened => 'Opened download link in the browser';

  @override
  String get appUpdateCannotOpenDownloadLink => 'Could not open download link';

  @override
  String appUpdateBrowserOpenFailed(String error) {
    return 'Failed to open browser: $error';
  }

  @override
  String get onboardingTitle => 'First-time setup';

  @override
  String onboardingProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingPrevious => 'Previous';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingStepAppearance => 'Language & theme';

  @override
  String get onboardingStepSsh => 'SSH';

  @override
  String get onboardingStepCli => 'Claude Code CLI';

  @override
  String get onboardingStepProviderImport => 'Import providers';

  @override
  String get onboardingStepDefaultProvider => 'Default provider';

  @override
  String get onboardingAppearanceTitle => 'Choose language and appearance';

  @override
  String get onboardingAppearanceSubtitle =>
      'You can change these later in Settings → Layout.';

  @override
  String get onboardingSshTitle => 'Configure SSH connection';

  @override
  String get onboardingSshSubtitle =>
      'Android runs Claude Code on a remote host over SSH.';

  @override
  String get onboardingCliTitle => 'Detect Claude Code CLI';

  @override
  String get onboardingCliSubtitle =>
      'TeamPilot needs the Claude Code executable to start sessions.';

  @override
  String get onboardingCliFound => 'CLI found';

  @override
  String get onboardingCliNotFound => 'CLI not detected on PATH';

  @override
  String get onboardingCliRedetect => 'Scan again';

  @override
  String get onboardingProviderImportTitle => 'Import Claude providers';

  @override
  String get onboardingProviderImportSubtitle =>
      'Scan ~/.claude settings and cc-switch for existing provider configs.';

  @override
  String get onboardingProviderImportResults => 'Import results';

  @override
  String get onboardingProviderImportEmpty =>
      'No Claude providers detected. You can configure them later in Settings.';

  @override
  String get onboardingProviderImportFailed => 'Import failed';

  @override
  String get onboardingProviderImportRescan => 'Scan again';

  @override
  String get onboardingDefaultProviderTitle => 'Choose default Claude provider';

  @override
  String get onboardingDefaultProviderSubtitle =>
      'New sessions will use this provider and default model.';

  @override
  String get onboardingDefaultProviderEmpty =>
      'No providers to choose from. Skip this step or add providers in Settings.';

  @override
  String get onboardingDefaultProviderPick =>
      'Select the default Claude Code provider';

  @override
  String get onboardingDefaultProviderModelHint =>
      'Primary model id for this provider';

  @override
  String get onboardingRerunSetup => 'Run setup wizard again';

  @override
  String get logViewerTitle => 'Logs';

  @override
  String get logViewerSubtitle =>
      'Application and error logs under your TeamPilot app data folder.';

  @override
  String get logViewerFileLabel => 'Log file';

  @override
  String get logViewerSearchHint => 'Search logs…';

  @override
  String get logViewerFilterTitle => 'Filters';

  @override
  String get logViewerFilterLevel => 'Level';

  @override
  String get logViewerWrapLines => 'Wrap lines';

  @override
  String get logViewerReverseOrder => 'Newest first';

  @override
  String get logViewerCompactView => 'Compact view';

  @override
  String logViewerLineCount(int count) {
    return '$count lines';
  }

  @override
  String get logViewerActionsMenu => 'More actions';

  @override
  String get logViewerRefresh => 'Refresh';

  @override
  String get logViewerCopyPath => 'Copy log path';

  @override
  String get logViewerClearOld => 'Remove old logs';

  @override
  String get logViewerEmpty => 'No log files yet';

  @override
  String get logViewerEmptyHint => 'Logs are created while the app runs.';

  @override
  String get logViewerPendingTitle => 'Logs not on disk yet';

  @override
  String get logViewerPendingBody =>
      'Buffered entries waiting for file logging:';

  @override
  String logViewerLoadFilesFailed(String error) {
    return 'Failed to list logs: $error';
  }

  @override
  String logViewerReadFailed(String error) {
    return 'Failed to read log: $error';
  }

  @override
  String get logViewerClearDone => 'Old log files removed';

  @override
  String logViewerClearFailed(String error) {
    return 'Cleanup failed: $error';
  }

  @override
  String logViewerPathCopied(String name) {
    return 'Copied path: $name';
  }

  @override
  String get initErrorTitle => 'Startup failed';

  @override
  String get initErrorDetails => 'Error details';

  @override
  String get initErrorStackTrace => 'Stack trace';

  @override
  String get initErrorPendingLogs => 'Pending logs';

  @override
  String get initErrorViewLogs => 'View logs';

  @override
  String get initErrorCopyReport => 'Copy report';

  @override
  String get initErrorCopy => 'Copy';

  @override
  String get initErrorCopied => 'Copied';

  @override
  String get initErrorStackEmpty => 'Stack trace is empty.';

  @override
  String initErrorVersion(String version, String build) {
    return 'Version $version ($build)';
  }
}
