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
  String get filterFiles => 'Filter files';

  @override
  String get selectTeam => 'Select team';

  @override
  String get addTeamTooltip => 'Add team';

  @override
  String get projects => 'Projects';

  @override
  String get newProject => 'New Project';

  @override
  String get newSessionTooltip => 'New session';

  @override
  String get defaultNewChatSessionTitle => 'New Chat';

  @override
  String get openFolder => 'Open Folder';

  @override
  String get copyFolderPath => 'Copy Folder Path';

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
  String get cliExecutablePathLabel => 'flashskyai CLI path';

  @override
  String get cliExecutablePathDescription =>
      'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.';

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
  String get shellChatWorkbench => 'Shell chat workbench';

  @override
  String get shellSession => 'Shell session';

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
  String get reveal => 'Reveal';

  @override
  String get hide => 'Hide';

  @override
  String get replaceKey => 'Replace key';

  @override
  String get deleteProviderTooltip => 'Delete provider';

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
  String get skillsNavBackups => 'Backups';

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
  String get skillsRepoOwner => 'Owner';

  @override
  String get skillsRepoName => 'Name';

  @override
  String get skillsRepoBranch => 'Branch';

  @override
  String get skillsRepoRemove => 'Remove';

  @override
  String skillsRepoRemoveConfirm(String name) {
    return 'Remove repo $name?';
  }

  @override
  String get skillsBackupsEmpty => 'No backups yet';

  @override
  String get skillsBackupRestore => 'Restore';

  @override
  String get skillsBackupDelete => 'Delete';

  @override
  String skillsBackupDeleteConfirm(String name) {
    return 'Delete backup $name? This cannot be undone.';
  }

  @override
  String get skillsBackupCreatedAt => 'Created at';

  @override
  String skillsUninstallConfirm(String name) {
    return 'Uninstall $name? Files will be moved to backups.';
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
  String get memberQuickList => 'MEMBER QUICK LIST';

  @override
  String get teamName => 'Team name';

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
  String get memberLaunchOrder => 'Member launch order';

  @override
  String get saveMember => 'Save Member';

  @override
  String get editTeamSubtitle =>
      'Edit team identity, working directory, and launch order.';

  @override
  String get memberName => 'Member name';

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
  String get agentBuiltInSubtitle => 'Preset built-in agents.';

  @override
  String get agentCustomIdHint => 'Custom agent id';

  @override
  String get memberExtraArgs => 'Member extra CLI arguments';

  @override
  String get memberDangerouslySkipPermissions => 'Skip all permission checks';

  @override
  String get memberDangerouslySkipPermissionsHint =>
      'Only for isolated / no-network sandboxes. Extremely risky otherwise.';

  @override
  String get prompt => 'Prompt';

  @override
  String get selectModel => 'Select a model';

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
}
