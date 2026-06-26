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
      'Show the workspace file tree for quick navigation.';

  @override
  String get visibilityGitHint =>
      'Show the source control panel for the current repository.';

  @override
  String get extensionsSettingsTitle => 'Extensions';

  @override
  String get extensionsSettingsDescription =>
      'Install and enable external tools that augment your agents.';

  @override
  String get extensionsNavInstalled => 'Installed';

  @override
  String get extensionsEmptyTitle => 'No extensions available';

  @override
  String get extensionsEmptyHint =>
      'Extensions will appear here once the catalog loads.';

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
  String extensionStatusDependencyMissingNamed(String deps) {
    return 'Missing: $deps';
  }

  @override
  String extensionDependencyMissingHint(String deps) {
    return 'Needs $deps on your PATH. Install it, then re-check.';
  }

  @override
  String get extensionCopyCommand => 'Copy';

  @override
  String get extensionCommandCopied => 'Command copied to clipboard';

  @override
  String get extensionRecheck => 'Re-check';

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
      'Size of UI text. Standard follows your system; does not change icons or spacing.';

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
  String get typographyScaleCustomHint => '50–200';

  @override
  String get uiZoomTitle => 'Interface zoom';

  @override
  String get uiZoomDescription =>
      'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.';

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
  String get workspaceEntryModeTitle => 'Startup view';

  @override
  String get workspaceEntryModeDescription =>
      'Where the app opens after launch.';

  @override
  String get workspaceEntryModeHome => 'Home';

  @override
  String get workspaceEntryModeLastWorkspace => 'Last workspace';

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
  String get sourceControl => 'Source Control';

  @override
  String get gitStagedChanges => 'Staged Changes';

  @override
  String get gitChanges => 'Changes';

  @override
  String get gitNoChanges => 'No changes';

  @override
  String get gitNotARepository => 'This folder is not a Git repository';

  @override
  String get gitNotInstalled =>
      'Git was not found. Install Git to use source control.';

  @override
  String get gitCommit => 'Commit';

  @override
  String gitCommitMessageHint(String branch) {
    return 'Message (commit to \"$branch\")';
  }

  @override
  String get gitStage => 'Stage changes';

  @override
  String get gitUnstage => 'Unstage changes';

  @override
  String get gitStageAll => 'Stage all changes';

  @override
  String get gitUnstageAll => 'Unstage all changes';

  @override
  String get gitStageFolder => 'Stage changes in folder';

  @override
  String get gitUnstageFolder => 'Unstage changes in folder';

  @override
  String get treeExpandAllFolders => 'Expand all folders';

  @override
  String get treeCollapseAllFolders => 'Collapse all folders';

  @override
  String get gitDiscard => 'Discard changes';

  @override
  String get gitDiscardConfirmTitle => 'Discard changes?';

  @override
  String gitDiscardConfirmBody(String path) {
    return 'Discard all changes in $path? This cannot be undone.';
  }

  @override
  String get gitPush => 'Push';

  @override
  String get gitPull => 'Pull';

  @override
  String get gitRefresh => 'Refresh';

  @override
  String get gitChangesListView => 'List view';

  @override
  String get gitChangesTreeView => 'Tree view';

  @override
  String get gitSwitchBranch => 'Switch branch';

  @override
  String get gitCreateBranch => 'Create branch';

  @override
  String get gitNewBranchHint => 'New branch name';

  @override
  String gitError(String message) {
    return 'Git: $message';
  }

  @override
  String gitAheadBehind(int ahead, int behind) {
    return '↑$ahead ↓$behind';
  }

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
  String get teamModeLabel => 'Team mode';

  @override
  String get teamModeNative => 'Native (single CLI)';

  @override
  String get teamModeMixed => 'Mixed (cross-CLI bus)';

  @override
  String get memberCliInheritHint => 'Inherit team default';

  @override
  String get memberLaunchConfigTitle => 'Model settings';

  @override
  String get memberLaunchConfigSubtitle =>
      'CLI backend, provider, model, and effort for this member.';

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
  String get workspaces => 'Workspaces';

  @override
  String get newWorkspace => 'New Workspace';

  @override
  String get homeWorkspaceMainWindow => 'Workspace';

  @override
  String get windowControlMinimize => 'Minimize';

  @override
  String get windowControlMaximize => 'Maximize';

  @override
  String get windowControlRestore => 'Restore';

  @override
  String get windowControlClose => 'Close';

  @override
  String get windowControlAlwaysOnTop => 'Always on top';

  @override
  String get homeWorkspaceMyFavorites => 'My favorites';

  @override
  String get homeWorkspaceRecentVisits => 'Recent';

  @override
  String get homeWorkspacePersonal => 'Simple mode';

  @override
  String get homeWorkspaceAllWorkspaces => 'All workspaces';

  @override
  String get homeWorkspaceWorkspaceTabKindPersonal => 'Personal';

  @override
  String get homeWorkspaceDefaultPersonalWorkspaceName => 'Personal assistant';

  @override
  String get homeWorkspaceDefaultTeamName => 'Default Team';

  @override
  String get homeWorkspacePersonalSubtitle =>
      'Skip the team setup — just launch a single CLI and start chatting.';

  @override
  String get homeWorkspaceNoData => 'No data yet';

  @override
  String get homeWorkspaceRecentlyClosed => 'Recently closed';

  @override
  String get homeWorkspaceRecentlyClosedEmpty =>
      'No recently closed workspaces';

  @override
  String get homeWorkspaceMyTeams => 'My Teams';

  @override
  String get homeWorkspaceNewTeam => 'New Team';

  @override
  String get homeWorkspaceProviders => 'Providers';

  @override
  String get homeWorkspaceTeamWorkspaces => 'Workspaces';

  @override
  String get homeWorkspaceOwner => 'Owner';

  @override
  String get homeWorkspaceImportWorkspace => 'Import';

  @override
  String get homeWorkspaceSessionsLabel => 'sessions';

  @override
  String get homeWorkspaceEmptyWorkspaces => 'No workspaces in this team yet';

  @override
  String get homeWorkspaceEmptyWorkspacesHint =>
      'Create or import a workspace to get started';

  @override
  String get homeWorkspaceWorkspaceSort => 'Sort workspaces';

  @override
  String get homeWorkspaceWorkspaceSortRecentlyUpdated => 'Recently updated';

  @override
  String get homeWorkspaceWorkspaceSortNameAsc => 'Name (A–Z)';

  @override
  String get homeWorkspaceWorkspaceSortNameDesc => 'Name (Z–A)';

  @override
  String get homeWorkspaceWorkspaceSortCreatedDesc => 'Date created';

  @override
  String get homeWorkspaceWorkspaceSortSessionCountDesc => 'Session count';

  @override
  String get homeWorkspaceComingSoon => 'Coming soon';

  @override
  String get homeWorkspaceNewTeamSubtitle =>
      'Pick how the team collaborates, then name it.';

  @override
  String get homeWorkspaceNewTeamMethodCustom => 'Custom';

  @override
  String get homeWorkspaceNewTeamMethodAi => 'AI generate';

  @override
  String get homeWorkspaceNewTeamMethodSolo => 'Solo';

  @override
  String get homeWorkspaceNewTeamSubtitleAi =>
      'Describe your team and generate a draft with AI.';

  @override
  String get homeWorkspaceNewTeamSubtitleSolo =>
      'Simple single-CLI chat — switch CLI, model, and provider freely.';

  @override
  String get homeWorkspaceNewSoloNameHint => 'Enter a team name';

  @override
  String get homeWorkspaceCreateSolo => 'Create solo team';

  @override
  String get homeWorkspaceNewTeamRecommended => 'Recommended';

  @override
  String get homeWorkspaceNewTeamModeBeta => 'Beta';

  @override
  String get homeWorkspaceNewTeamNameHint => 'Enter a team name';

  @override
  String get homeWorkspaceCreateTeam => 'Create team';

  @override
  String get teamModeNativeTitle => 'Native mode';

  @override
  String get teamModeMixedTitle => 'Mixed mode';

  @override
  String get teamModeNativeDescription =>
      'All members share one CLI for native, low-config collaboration.';

  @override
  String get teamModeMixedDescription =>
      'Members can run different CLIs and collaborate across tools over TeamBus.';

  @override
  String get homeWorkspaceNewWorkspaceSubtitle =>
      'Choose a working directory and name your workspace.';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryLabel => 'Workspace directory';

  @override
  String get homeWorkspaceNewWorkspaceChooseDirectory => 'Choose folder';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryHint =>
      'No directory selected yet';

  @override
  String get homeWorkspaceNewWorkspaceNameHint => 'Defaults to the folder name';

  @override
  String get homeWorkspaceCreateWorkspace => 'Create workspace';

  @override
  String get homeWorkspaceCloseWorkspaceTitle => 'Close workspace?';

  @override
  String homeWorkspaceCloseWorkspaceMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Closing this tab will end $count running sessions in this workspace.',
      one: 'Closing this tab will end 1 running session in this workspace.',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceCloseWorkspaceConfirm => 'Close & end sessions';

  @override
  String get homeWorkspaceWorkspaceManagement => 'Workspace management';

  @override
  String get homeWorkspaceWorkspaceList => 'Workspaces';

  @override
  String get homeWorkspaceConversations => 'Conversations';

  @override
  String get homeWorkspaceConversationsSection => 'Conversations';

  @override
  String get homeWorkspaceWorkspaceAgent => 'Agent';

  @override
  String get workspaceAgentBuiltInSubtitle =>
      'Maps to flashskyai --agent when that CLI is active.';

  @override
  String get workspaceAgentExtraArgs => 'Extra CLI arguments';

  @override
  String get workspaceAgentExtraArgsSubtitle =>
      'Extra flags appended when starting the agent in this workspace.';

  @override
  String get workspaceWorkbenchAdvancedSettingsSubtitle =>
      'Agent preset and extra CLI flags for this workspace.';

  @override
  String get workspaceAgentPromptSubtitle =>
      'System prompt defining the agent\'s role and boundaries in this workspace.';

  @override
  String get workspaceAgentPromptPresetGeneral => 'General';

  @override
  String get workspaceAgentPromptPresetGeneralText =>
      'Help with development in this workspace end to end. Understand the request and codebase, propose a clear approach, then implement with minimal diffs; summarize changed files and suggested next steps.';

  @override
  String get workspaceAgentPromptPresetDeveloper => 'Developer';

  @override
  String get workspaceAgentPromptPresetDeveloperText =>
      'Focus on implementation and fixes. Prefer minimal diffs, run relevant tests, and briefly explain changed files and rationale.';

  @override
  String get workspaceAgentPromptPresetReviewer => 'Reviewer';

  @override
  String get workspaceAgentPromptPresetReviewerText =>
      'Review code only; do not modify files unless asked.\nEach finding must include file path, line, issue, and suggested fix.';

  @override
  String get workspaceAgentPromptPresetResearcher => 'Researcher';

  @override
  String get workspaceAgentPromptPresetResearcherText =>
      'Investigate and report only; do not change production code unless asked.\nOutput findings with file paths, relevant symbols, and recommended next steps.';

  @override
  String get workspaceCliEffortInheritHint => 'Use provider default';

  @override
  String get workspaceCliDefaultSubtitle =>
      'Default CLI for new conversations in this workspace.';

  @override
  String get workspaceCliDefaultsTitle => 'CLI defaults';

  @override
  String get workspaceCliDefaultsSubtitle =>
      'Set the default provider and model for each CLI used in this workspace.';

  @override
  String get workspaceCliProviderModelTitle => 'Provider & model';

  @override
  String get workspaceCliEffortLevel => 'Reasoning effort';

  @override
  String get workspaceCliEffortLevelSubtitle =>
      'Default effort for this CLI in the workspace (leave empty to use provider default).';

  @override
  String get workspaceCliConfigure => 'Configure';

  @override
  String get workspaceCliConfigured => 'Configured';

  @override
  String get workspaceCliNotConfigured => 'Not configured';

  @override
  String get workspaceCliNotConfiguredHint =>
      'No default provider selected yet';

  @override
  String get workspaceCliNoProviderCatalog =>
      'No provider setup required for this CLI';

  @override
  String workspaceCliConfigSummary(String provider, String model) {
    return '$provider · $model';
  }

  @override
  String get workspaceCliAddPresetTitle => 'Add Preset';

  @override
  String get workspaceCliEditPresetTitle => 'Edit Preset';

  @override
  String get workspaceCliPresetNameLabel => 'Preset Name';

  @override
  String get workspaceCliPresetsManageTitle => 'Manage Presets';

  @override
  String get workspaceCliPresetsEmptyHint =>
      'No presets yet. Create one to get started.';

  @override
  String get workspaceCliDeletePresetTitle => 'Delete Preset';

  @override
  String workspaceCliDeletePresetConfirm(String name) {
    return 'Delete preset \'$name\'? This cannot be undone.';
  }

  @override
  String get workspaceCliPresetLabel => 'Active Preset';

  @override
  String get workspaceCliNoPresetHint => 'No preset selected';

  @override
  String get workspaceCliManagePresets => 'Manage';

  @override
  String get teamDefaultPresetLabel => 'Default Model Preset';

  @override
  String get teamDefaultPresetSubtitle =>
      'Optional default preset applied to members that don\'t override it.';

  @override
  String get teamDefaultPresetNone => 'None';

  @override
  String get teamDefaultPresetChange => 'Change';

  @override
  String get teamDefaultPresetManage => 'Manage';

  @override
  String get teamDefaultCliMixedSubtitle =>
      'When a member has no CLI override.';

  @override
  String get teamDefaultDialogEffortSubtitle => 'Team default effort.';

  @override
  String get presetPickerTitle => 'Select Preset';

  @override
  String get presetPickerNoneOption => 'None (no default)';

  @override
  String get memberPresetLabel => 'Preset';

  @override
  String get memberPresetInheritTeam => 'Inherit team default';

  @override
  String get memberPresetInheritTeamNone => 'No team default set';

  @override
  String get memberPresetSelectPreset => 'Select a preset';

  @override
  String get memberPresetCustom => 'Custom configuration';

  @override
  String memberPresetViaPreset(String presetName) {
    return '$presetName (via preset)';
  }

  @override
  String memberPresetViaTeamDefault(String presetName) {
    return '$presetName (via team default)';
  }

  @override
  String get homeWorkspaceWorkspaceSkills => 'Skills';

  @override
  String get homeWorkspaceWorkspacePlugins => 'Plugins';

  @override
  String get homeWorkspaceWorkspaceMcp => 'MCP';

  @override
  String get homeWorkspaceWorkspaceExtensions => 'Extensions';

  @override
  String workspaceSkillsAssignedCount(int assigned, int total) {
    return '$assigned of $total enabled for this workspace';
  }

  @override
  String get workspaceSkillsManage => 'Manage skills';

  @override
  String workspaceMcpAssignedCount(int assigned, int total) {
    return '$assigned of $total enabled for this workspace';
  }

  @override
  String get workspaceMcpManage => 'Manage MCP';

  @override
  String workspacePluginsAssignedCount(int assigned, int total) {
    return '$assigned of $total linked to this workspace';
  }

  @override
  String get workspacePluginsManage => 'Manage plugins';

  @override
  String get workspacePluginsEmpty => 'No plugins installed';

  @override
  String get workspacePluginsEmptyHint =>
      'Install plugins from Discovery to enable them for this workspace.';

  @override
  String get workspaceExtensionsTitle => 'Extensions for this workspace';

  @override
  String get workspaceExtensionsSubtitle =>
      'Override which extensions run for this workspace. Default follows the global setting.';

  @override
  String get workspaceExtensionEffectiveOn => 'Enabled for this workspace';

  @override
  String get workspaceExtensionEffectiveOff => 'Disabled for this workspace';

  @override
  String get homeWorkspaceTeamConfig => 'Team config';

  @override
  String get homeWorkspaceWorkspaceSettings => 'Workspace settings';

  @override
  String get homeWorkspaceWorkspaceMembers => 'Members';

  @override
  String get homeWorkspaceWorkspaceSettingsSectionBasic => 'Basic';

  @override
  String get homeWorkspaceWorkspaceSettingsBasicInfo => 'Basic information';

  @override
  String get homeWorkspaceWorkspaceId => 'Workspace ID';

  @override
  String homeWorkspaceWorkspaceAdditionalDirsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count additional directories',
      one: '1 additional directory',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceWorkspaceSettingsPathsHint =>
      'Use Manage on additional directories to add or remove folders in this workspace.';

  @override
  String get deleteWorkspaceSubtitle =>
      'Deletes this workspace and all conversations in it. This cannot be undone.';

  @override
  String get homeWorkspaceInviteMembers => 'Invite';

  @override
  String get homeWorkspaceNewConversation => 'New Conversation';

  @override
  String get homeWorkspaceNewConversationChooseCli =>
      'New conversation with CLI…';

  @override
  String get homeWorkspaceNoConversations =>
      'No conversations in this workspace yet';

  @override
  String get homeWorkspaceSearchHint => 'Search';

  @override
  String get homeWorkspaceNoSearchResults =>
      'No conversations match your search';

  @override
  String get workspaceSearchTitle => 'Search';

  @override
  String get workspaceSearchHint => 'Search sessions and files';

  @override
  String get workspaceSearchFilesSection => 'Files';

  @override
  String get workspaceSearchSearching => 'Searching files…';

  @override
  String get workspaceSearchNoResults => 'No matches';

  @override
  String get workspaceSearchFilesTruncated =>
      'More files match — refine your search';

  @override
  String get homeWorkspaceOpenWorkspaceInNewTab => 'Open in new tab';

  @override
  String get homeWorkspaceOpenInNewTabWithOtherIdentity =>
      'Open in new tab with other identity…';

  @override
  String get homeWorkspaceFavoriteWorkspace => 'Favorite workspace';

  @override
  String get homeWorkspaceUnfavoriteWorkspace => 'Remove from favorites';

  @override
  String get homeWorkspaceRenameWorkspace => 'Rename workspace';

  @override
  String get homeWorkspaceCloneWorkspace => 'Clone workspace';

  @override
  String homeWorkspaceCloneWorkspaceDisplayName(Object name) {
    return '$name (copy)';
  }

  @override
  String homeWorkspaceCloneWorkspaceSuccess(Object name) {
    return 'Cloned \"$name\".';
  }

  @override
  String get homeWorkspaceCloneWorkspaceFailed => 'Could not clone workspace';

  @override
  String get newWorkspaceTooltip => 'Create a workspace';

  @override
  String get switchWorkspaceTooltip => 'Switch workspace';

  @override
  String get create => 'Create';

  @override
  String get pickPrimaryDirectory => 'Pick primary directory';

  @override
  String get workspacePrimaryPathRequired =>
      'Select a primary directory first.';

  @override
  String get workspacePrimaryPathNotSelected => 'No primary directory selected';

  @override
  String get workspaceDirectoryAdded => 'Directory added to workspace';

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
  String get workspaceDetails => 'Workspace details';

  @override
  String get workspaceDetailsTitle => 'Workspace Details';

  @override
  String get addWorkspaceDirectory => 'Add directory';

  @override
  String get removeWorkspaceDirectory => 'Remove directory';

  @override
  String get workspaceDisplayName => 'Display name';

  @override
  String get workspaceIcon => 'Icon';

  @override
  String get workspaceIconPickerTitle => 'Choose workspace icon';

  @override
  String get workspaceIconUseDefault => 'Use default';

  @override
  String get workspaceIconUpload => 'Upload icon';

  @override
  String get workspaceIconUploadFailed =>
      'Could not save icon. Use PNG, JPG, WEBP, or SVG.';

  @override
  String get workspacePrimaryPath => 'Primary directory';

  @override
  String get workspaceAdditionalDirectories => 'Additional directories';

  @override
  String get workspaceNoAdditionalDirectories => 'No additional directories';

  @override
  String get workspaceSessionCount => 'Sessions';

  @override
  String get workspaceCreatedAt => 'Created';

  @override
  String get workspaceUpdatedAt => 'Updated';

  @override
  String get workspaceDirectoryAlreadyPrimary =>
      'This path is already the primary directory.';

  @override
  String get workspaceDirectoryAlreadyAdded =>
      'This directory is already in the workspace.';

  @override
  String get editWorkspacePrimaryPath => 'Edit primary directory';

  @override
  String get remoteDirectoryBrowserTitle => 'Browse remote directory';

  @override
  String get remoteDirectoryBrowserUpOneLevel => 'Up one level';

  @override
  String get remoteDirectoryBrowserUseThisDirectory => 'Use this directory';

  @override
  String get remoteDirectoryBrowserTypePathLabel => 'Or type a path';

  @override
  String get remoteDirectoryBrowserTypePathHint => '~/work/workspace';

  @override
  String get remoteDirectoryBrowserUseTypedPath => 'Use path';

  @override
  String get remoteDirectoryBrowserError =>
      'Couldn\'t open the remote directory. You can still type a path below.';

  @override
  String get remoteDirectoryBrowserEmpty => 'No subdirectories here';

  @override
  String get deleteWorkspace => 'Delete Workspace';

  @override
  String deleteWorkspaceConfirm(String name) {
    return 'Delete workspace \"$name\" and all its sessions? This cannot be undone.';
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
  String get pinConversation => 'Pin conversation';

  @override
  String get unpinConversation => 'Unpin conversation';

  @override
  String get sessionSortManual => 'Manual order';

  @override
  String get sessionSortRecentlyUpdated => 'Recently updated';

  @override
  String get sessionSortCreatedDesc => 'Date created';

  @override
  String get sessionSortTooltip => 'Sort conversations';

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
      'Configure shell session launch, terminal behavior, and storage backend.';

  @override
  String get cliConfig => 'CLI';

  @override
  String get cliConfigPageSubtitle =>
      'Configure AI agent CLI executable paths and install missing tools.';

  @override
  String get sshProfilesSettingsTitle => 'SSH servers';

  @override
  String get sshProfilesPageTitle => 'SSH remote hosts';

  @override
  String get sshProfilesPageSubtitle =>
      'Connect to existing machines over SSH for files, terminals, Git, and workspaces.';

  @override
  String get sshProfilesTargetsTitle => 'Targets';

  @override
  String get sshProfilesTargetsSubtitle =>
      'Add a remote host to connect from TeamPilot.';

  @override
  String get sshProfilesImport => 'Import';

  @override
  String get sshProfilesImportUnavailable =>
      'Import from ~/.ssh/config is not available yet.';

  @override
  String get sshProfilesAddTarget => 'Add target';

  @override
  String get sshProfilesEmpty => 'No SSH targets configured.';

  @override
  String get sshProfileStatusDisconnected => 'Disconnected';

  @override
  String get sshProfileStatusConnecting => 'Connecting…';

  @override
  String get sshProfileStatusConnected => 'Connected';

  @override
  String get sshProfileStatusError => 'Error';

  @override
  String get sshProfileTest => 'Test';

  @override
  String get sshProfileConnect => 'Connect';

  @override
  String get sshProfileDisconnect => 'Disconnect';

  @override
  String get sshProfileEdit => 'Edit';

  @override
  String get sshProfileDelete => 'Delete';

  @override
  String get sshProfileRefresh => 'Refresh';

  @override
  String get sshProfileTestSuccess => 'Connection successful';

  @override
  String get sshProfileTestFailed => 'Connection test failed';

  @override
  String sshProfileConnectSuccess(String host) {
    return 'Connected to $host';
  }

  @override
  String get sshProfileFormTitleNew => 'New SSH target';

  @override
  String get sshProfileFormTitleEdit => 'Edit SSH target';

  @override
  String get sshProfileFormLabel => 'Label';

  @override
  String get sshProfileFormLabelHint => 'My server';

  @override
  String get sshProfileFormHost => 'Host or alias';

  @override
  String get sshProfileFormHostHint => 'server, deploy@server:2222';

  @override
  String get sshProfileFormUsername => 'Username';

  @override
  String get sshProfileFormUsernameHint => 'deploy';

  @override
  String get sshProfileFormPort => 'Port';

  @override
  String get sshProfileFormPortInvalid => 'Port must be between 1 and 65535';

  @override
  String get sshProfileFormIdentityFile => 'Identity file';

  @override
  String get sshProfileFormIdentityFileHint => '~/.ssh/id_ed25519';

  @override
  String get sshProfileFormIdentityFileHelper =>
      'Optional. Reads the private key from disk when set.';

  @override
  String get sshProfileFormIdentityFileBrowse => 'Browse…';

  @override
  String get sshProfileFormIdentityFileMissing => 'Identity file not found';

  @override
  String get sshProfileFormPassphrase => 'Key passphrase';

  @override
  String get sshProfileFormPassphraseHint => 'Optional';

  @override
  String get sshProfileFormPassword => 'Password';

  @override
  String get sshProfileFormPasswordHint => 'Use when no identity file is set';

  @override
  String get sshProfileFormPasswordHintEdit =>
      'Leave empty to keep saved password';

  @override
  String get sshProfileFormPasswordHelper =>
      'Optional if an identity file is provided.';

  @override
  String get sshProfileFormCredentialRequired =>
      'Provide an identity file or password.';

  @override
  String get sshProfileFormFieldRequired => 'Required';

  @override
  String get sshProfileSelectorTooltip => 'Switch SSH server';

  @override
  String get sshProfileSelectorManage => 'Manage SSH servers…';

  @override
  String get sshDefaultWorkingDirectoryTitle => 'SSH default working directory';

  @override
  String get sshDefaultWorkingDirectorySubtitle =>
      'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.';

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
  String get cliInstallProgressInstallingCli => 'Installing CLI…';

  @override
  String get cliInstallProgressLocatingExecutable => 'Locating CLI executable…';

  @override
  String cliExecutablePathLabelFor(String cli) {
    return '$cli CLI path';
  }

  @override
  String cliExecutablePathDescriptionFor(String cli) {
    return 'Absolute path to the $cli executable. Leave empty to use the one on PATH.';
  }

  @override
  String cliExecutablePathDescriptionSshFor(String cli) {
    return 'Absolute path to $cli on the remote SSH host. Leave empty to auto-discover over SSH.';
  }

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
  String get terminalDropCrossMachineRejected =>
      'Can\'t drop a local file onto a remote terminal';

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
  String get fileTreeRefresh => 'Refresh';

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
  String get fileTreeNewFile => 'New File';

  @override
  String get fileTreeNewFolder => 'New Folder';

  @override
  String get fileTreeCreateNameHint => 'Name';

  @override
  String get fileTreeCut => 'Cut';

  @override
  String get fileTreeCopy => 'Copy';

  @override
  String get fileTreePaste => 'Paste';

  @override
  String get fileTreeRename => 'Rename';

  @override
  String get fileTreeRenameTitle => 'Rename';

  @override
  String get fileTreeOpenInFileManager => 'Reveal in File Manager';

  @override
  String get fileTreeOpenInTerminal => 'Open in Terminal';

  @override
  String get fileTreePasteDone => 'Pasted';

  @override
  String get fileTreeFileCreated => 'File created';

  @override
  String get fileTreeFolderCreated => 'Folder created';

  @override
  String get fileTreeRenameDone => 'Renamed';

  @override
  String get fileTreeDeleteDone => 'Deleted';

  @override
  String get fileTreeInvalidName => 'Invalid name';

  @override
  String get fileTreeItemExists => 'An item with that name already exists';

  @override
  String get fileTreeSourceMissing => 'The copied item no longer exists';

  @override
  String get fileTreeInvalidPasteTarget => 'Cannot paste here';

  @override
  String get fileTreeOpenInTerminalFailed => 'Could not open a terminal';

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
  String get terminalLinkClickOpensInAppTitle => 'Open terminal links in app';

  @override
  String get terminalLinkClickOpensInAppDescription =>
      'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.';

  @override
  String terminalParkedSendPending(String content) {
    return 'Sent, awaiting receipt: $content';
  }

  @override
  String get terminalParkedSendDismiss => 'Dismiss';

  @override
  String get mailbox => 'Mailbox';

  @override
  String get mailboxEmpty => 'No messages yet';

  @override
  String get board => 'Board';

  @override
  String get boardEmpty => 'No tasks yet';

  @override
  String get boardPending => 'Pending';

  @override
  String get boardClaimed => 'In progress';

  @override
  String get boardDone => 'Done';

  @override
  String get visibilityBoardHint => 'Show the task board for mixed-mode teams.';

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
  String get memberTargetAssignmentTitle => 'Member machine';

  @override
  String memberTargetAssignmentSubtitle(Object member) {
    return 'Which machine $member runs on (its assigned workspace folders).';
  }

  @override
  String get memberTargetAssignmentInherit => 'Inherit workspace folders';

  @override
  String get memberAssignFoldersAction => 'Assign folders…';

  @override
  String get credentialPushOptInTitle => 'Push credentials to this machine';

  @override
  String credentialPushOptInSubtitle(Object host) {
    return 'Materialize provider keys onto $host so remote members can authenticate. Off by default.';
  }

  @override
  String get credentialPushConfirmTitle => 'Push credentials to remote host?';

  @override
  String credentialPushConfirmBody(Object host) {
    return 'Provider keys will be written to the remote host $host. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.';
  }

  @override
  String get credentialPushConfirmAction => 'Push credentials';

  @override
  String get rootSandboxEnvOptInTitle => 'Inject IS_SANDBOX for root';

  @override
  String rootSandboxEnvOptInSubtitle(Object host) {
    return 'When Claude launches as root on $host outside a container, set IS_SANDBOX=1 so skip-permissions is kept. Off by default.';
  }

  @override
  String get rootSandboxEnvConfirmTitle => 'Enable root sandbox env?';

  @override
  String rootSandboxEnvConfirmBody(Object host) {
    return 'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on $host, keeping --dangerously-skip-permissions. Only enable on machines you trust.';
  }

  @override
  String get rootSandboxEnvConfirmAction => 'Enable';

  @override
  String get workspaceTargetTitle => 'Workspace machine';

  @override
  String get workspaceTargetSubtitle =>
      'The machine this workspace\'s folders live and run on. Sessions launch on this target; switching does not move files.';

  @override
  String get workspaceFoldersSectionTitle => 'Directories & machines';

  @override
  String get workspaceFoldersEditorHint =>
      'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).';

  @override
  String get workspaceFoldersMixedTargetsLockedHint =>
      'Mixed workspace: folder machines are fixed. Add paths on existing machines above; use Assign to change member machine assignment.';

  @override
  String get workspaceFoldersPersonalTargetsLockedHint =>
      'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.';

  @override
  String get workspaceFoldersPickMixedTarget => 'Add directory on machine';

  @override
  String get workspaceTopologyLocal => 'Local workspace';

  @override
  String get workspaceTopologyRemote => 'Remote workspace';

  @override
  String get workspaceTopologyMixed => 'Mixed workspace';

  @override
  String get workspaceTypeLabel => 'Type';

  @override
  String get mixedWorkspaceRequiresTeamLaunch =>
      'Mixed workspaces can only be started with a team identity. Switch to a team and assign each member to a machine.';

  @override
  String get mixedWorkspacePersonalLaunchBlockedHint =>
      'This is a mixed workspace. Switch to a team tab to start conversations and assign members to machines.';

  @override
  String get mixedWorkspaceMemberAssignmentTitle =>
      'Assign members to machines';

  @override
  String get mixedWorkspaceMemberAssignmentSubtitle =>
      'Select a machine on the left, then use + / − to place each member\'s instances on it.';

  @override
  String get mixedWorkspaceMemberAssignmentIncomplete =>
      'Every member instance must be assigned to a machine.';

  @override
  String get mixedWorkspaceMemberAssignmentConfirm => 'Start team';

  @override
  String get workspaceMemberTargetsSectionTitle => 'Member machine assignment';

  @override
  String get workspaceMemberTargetsSectionSubtitle =>
      'Default for new conversations with this team. Existing conversations keep the assignment from when they were created.';

  @override
  String get workspaceMemberTargetsSave => 'Save assignment';

  @override
  String get workspaceMemberTargetsSaved => 'Member assignment saved.';

  @override
  String get workspaceMemberTargetsAssignAction => 'Assign';

  @override
  String get workspaceMemberTargetsAssigned => 'Assigned';

  @override
  String get workspaceMemberTargetsUnassigned => 'Not assigned';

  @override
  String get workspaceMemberTargetsPartiallyAssigned => 'Partially assigned';

  @override
  String get mixedWorkspaceCreateSessionBlocked =>
      'Complete member machine assignment in workspace settings before starting a conversation.';

  @override
  String get mixedWorkspaceSessionLaunchBlocked =>
      'This conversation has incomplete member assignments. Configure assignment in workspace settings and start a new conversation.';

  @override
  String get sessionLaunchMissingWorkspace =>
      'Workspace not found for this session.';

  @override
  String get sessionLaunchMissingTeamMember =>
      'Team member is not available. Select a team and try again.';

  @override
  String mixedWorkspaceMemberPlacementProgress(int placed, int total) {
    return '$placed / $total assigned';
  }

  @override
  String mixedWorkspaceMemberPlacementOnMachine(int count) {
    return '$count on this machine';
  }

  @override
  String get workspaceFolderTargetLabel => 'Machine';

  @override
  String get workspaceFolderPathLabel => 'Directory';

  @override
  String get workspaceFoldersChangeTarget => 'Change';

  @override
  String get workspaceFoldersAddOnAnotherMachine => 'Add on another machine';

  @override
  String get workspaceFoldersPickTarget => 'Choose machine';

  @override
  String get workspaceFoldersPickPath => 'Choose directory';

  @override
  String get workspaceFoldersApplyAllLocal => 'Set all to local';

  @override
  String get workspaceFoldersApplyAllRemote => 'Set all to remote…';

  @override
  String get workspaceFoldersPickRemoteTarget => 'Choose remote machine';

  @override
  String get homeTargetTitle => 'Home device';

  @override
  String get homeTargetSubtitle =>
      'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.';

  @override
  String get homeTargetSingleOptionHint =>
      'This is the only available home on this platform.';

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
  String get cursorCredentialsAuthenticated => 'Authenticated';

  @override
  String get cursorCredentialsUnauthenticated => 'Unauthenticated';

  @override
  String get cursorCredentialsLogin => 'Sign in with Cursor';

  @override
  String get cursorCredentialsImportGlobal => 'Import from ~/.cursor';

  @override
  String get cursorCredentialsImportFile => 'Import directory…';

  @override
  String get cursorCredentialsRevoke => 'Sign out';

  @override
  String cursorCredentialsRevokeConfirm(String name) {
    return 'Sign out and remove saved credentials for $name?';
  }

  @override
  String get cursorCredentialsActionSuccess => 'Credentials updated';

  @override
  String get cursorCredentialsActionFailed => 'Could not update credentials';

  @override
  String get codexCredentialsLogin => 'Sign in with OpenAI';

  @override
  String get codexCredentialsImportGlobal => 'Import from ~/.codex';

  @override
  String get codexCredentialsImportFile => 'Import auth.json…';

  @override
  String get codexCredentialsRevoke => 'Sign out';

  @override
  String codexCredentialsRevokeConfirm(String name) {
    return 'Sign out and remove saved credentials for $name?';
  }

  @override
  String get codexCredentialsActionSuccess => 'Credentials updated';

  @override
  String get codexCredentialsActionFailed => 'Could not update credentials';

  @override
  String get opencodeCredentialsLogin => 'Sign in with provider';

  @override
  String get opencodeCredentialsImportGlobal => 'Import from opencode auth';

  @override
  String get opencodeCredentialsImportFile => 'Import auth.json…';

  @override
  String get opencodeCredentialsRevoke => 'Sign out';

  @override
  String opencodeCredentialsRevokeConfirm(String name) {
    return 'Sign out and remove saved credentials for $name?';
  }

  @override
  String get opencodeCredentialsActionSuccess => 'Credentials updated';

  @override
  String get opencodeCredentialsActionFailed => 'Could not update credentials';

  @override
  String get providerCredentialsFailureUnsupported =>
      'This credential action is not supported';

  @override
  String get providerCredentialsFailureServiceUnavailable =>
      'Credential service is not available';

  @override
  String get providerCredentialsFailureProviderNotFound => 'Provider not found';

  @override
  String get providerCredentialsFailurePathRequired =>
      'Choose a file or directory first';

  @override
  String providerCredentialsFailureSourceMissing(String path) {
    return 'Credential file not found: $path';
  }

  @override
  String providerCredentialsFailureSourceUnreadable(String path) {
    return 'Could not read credential file: $path';
  }

  @override
  String providerCredentialsFailureProviderEntryMissing(
    String providerId,
    String path,
  ) {
    return 'No credential for \"$providerId\" in $path';
  }

  @override
  String providerCredentialsFailureProviderEntryMissingWithKeys(
    String providerId,
    String path,
    String keys,
  ) {
    return 'No credential for \"$providerId\" in $path. Available: $keys';
  }

  @override
  String get providerCredentialsFailureInvalidCredential =>
      'Credential format is invalid or incomplete';

  @override
  String get providerCredentialsFailureDestinationExists =>
      'Credentials already exist. Sign out first or import again to replace.';

  @override
  String providerCredentialsFailureRequiredFileMissing(String path) {
    return 'Required file missing: $path';
  }

  @override
  String providerCredentialsFailureLoginFailed(int exitCode) {
    return 'Login failed (exit code $exitCode)';
  }

  @override
  String providerCredentialsFailureLoginProcessError(String detail) {
    return 'Could not run login command: $detail';
  }

  @override
  String get providerCredentialsFailureRevokeFailed =>
      'Could not sign out or remove credentials';

  @override
  String get providerCredentialsFailureVerifyFailed =>
      'Credentials were saved but verification failed';

  @override
  String get providerCredentialsFailureStatusRefreshFailed =>
      'Credentials updated but status could not be refreshed';

  @override
  String get claudeLaunchCredentialsMissingWarning =>
      'Claude Official credentials are missing for this team provider. Sign in from Providers settings.';

  @override
  String get teamConfigIncompleteTitle => 'Team configuration incomplete';

  @override
  String teamConfigIncompleteBody(String team) {
    return 'Team \"$team\" is missing settings needed to launch. The session still starts, but agents may fail without them:';
  }

  @override
  String get teamConfigIncompleteGoConfigure => 'Configure team';

  @override
  String get teamConfigIncompleteDismiss => 'Later';

  @override
  String get teamConfigGroupTeamDefault => 'Team default';

  @override
  String get teamConfigAspectDefaultProvider => 'Default provider';

  @override
  String get teamConfigAspectProvider => 'Provider';

  @override
  String get teamConfigAspectModel => 'Model';

  @override
  String get teamConfigAspectCli => 'CLI';

  @override
  String get teamConfigAspectSeparator => ', ';

  @override
  String teamConfigIssueSemanticLabel(String subject, String aspects) {
    return '$subject is missing: $aspects';
  }

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
  String get providerModelBackgroundTier =>
      'Use for background/fast tasks (Claude haiku tier)';

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
  String pluginCliSupportFully(String cli) {
    return '$cli: Fully supported';
  }

  @override
  String pluginCliSupportPartial(String cli, String dropped) {
    return '$cli: Partially supported ($dropped dropped)';
  }

  @override
  String pluginCliSupportNotApplicable(String cli) {
    return '$cli: Not applicable';
  }

  @override
  String get pluginComponentSkills => 'skills';

  @override
  String get pluginComponentAgents => 'agents';

  @override
  String get pluginComponentCommands => 'commands';

  @override
  String get pluginComponentHooks => 'hooks';

  @override
  String get pluginComponentMcp => 'MCP';

  @override
  String get pluginComponentRules => 'rules';

  @override
  String get pluginComponentApps => 'apps';

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
  String get teamSettingsSubtitle => 'Team agents';

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
  String get teamMcpNav => 'MCP';

  @override
  String get teamHubNav => 'TeamHub';

  @override
  String get teamHubSubtitle => 'Discover more public teams';

  @override
  String get teamHubTitle => 'TeamHub';

  @override
  String get teamHubDiscovery => 'Discovery';

  @override
  String get teamHubFavorites => 'Favorites';

  @override
  String get teamHubSearchHint => 'Search public teams';

  @override
  String get teamHubSortName => 'Name';

  @override
  String get teamHubSortUpdated => 'Recently updated';

  @override
  String get teamHubCategoryAll => 'All';

  @override
  String get teamHubClone => 'Clone to my teams';

  @override
  String get teamHubCloning => 'Cloning…';

  @override
  String teamHubCloneSuccess(Object name) {
    return 'Cloned \"$name\".';
  }

  @override
  String teamHubClonePartial(Object name, Object count) {
    return 'Cloned \"$name\"; $count dependencies could not be installed automatically.';
  }

  @override
  String get teamHubCloneFailed => 'Could not clone this team.';

  @override
  String get teamHubEmptyTitle => 'No public teams yet';

  @override
  String get teamHubEmptyHint => 'Refresh to fetch teams from the registry.';

  @override
  String get teamHubFavoritesEmptyTitle => 'No favorites yet';

  @override
  String get teamHubFavoritesEmptyHint =>
      'Tap the star on a team to save it here.';

  @override
  String get teamHubRefresh => 'Refresh';

  @override
  String get teamHubLoadError => 'Could not load public teams.';

  @override
  String get teamHubDepInstalled => 'Installed';

  @override
  String get teamHubDepToInstall => 'Will be installed';

  @override
  String get teamHubMembersLabel => 'Members';

  @override
  String get teamHubSkillsLabel => 'Skills';

  @override
  String get teamHubPluginsLabel => 'Plugins';

  @override
  String get teamHubMcpLabel => 'MCP';

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
  String get teamEffortLevel => 'Reasoning effort';

  @override
  String get teamEffortLevelSubtitle =>
      'Default effort for this team (Claude effortLevel / Codex model_reasoning_effort).';

  @override
  String get memberEffortLevel => 'Member effort override';

  @override
  String get memberEffortLevelSubtitle => 'Overrides team default when set.';

  @override
  String get memberEffortInheritHint => 'Inherit team default';

  @override
  String get providerEffortLevel => 'Reasoning effort';

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
  String get teamForceWaitBeforeStopTitle => 'Keep members in the wait loop';

  @override
  String get teamForceWaitBeforeStopSubtitle =>
      'When enabled, a member finishing a turn is pushed back into wait_for_message instead of stopping, so it stays available for new messages and tasks. Disable to let members rest (stop normally).';

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
  String get agent => 'Agent preset';

  @override
  String get selectAgent => 'Select preset';

  @override
  String get agentBuiltInNone => 'Default';

  @override
  String get agentBuiltInCustom => 'Custom…';

  @override
  String get agentBuiltInSubtitle =>
      'Which agent role this member uses; shapes behavior and capabilities.';

  @override
  String get agentFlashskyaiPresetSubtitle =>
      'Passed as flashskyai --agent; pick a built-in or custom sub-agent.';

  @override
  String get agentClaudeTypeSubtitle =>
      'Written to the Claude team roster as agentType; leave empty to use the member id.';

  @override
  String get agentClaudeTypeHint => 'e.g. Explore, Plan, or a custom type';

  @override
  String get agentCustomIdHint => 'Custom agent id';

  @override
  String get memberExtraArgs => 'Member extra CLI arguments';

  @override
  String get memberExtraArgsSubtitle =>
      'Extra flags applied only when this member starts.';

  @override
  String get memberReplicas => 'Replicas';

  @override
  String get memberReplicasSubtitle =>
      'Run this role as N interchangeable instances (pods) that share its task queue. 1 = a single instance.';

  @override
  String get workspaceAdvancedSettings => 'Advanced';

  @override
  String get workspaceAdvancedSettingsSubtitle =>
      'Agent preset and extra CLI flags for this member.';

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
      'Implement assigned tasks, staying within the agreed scope. Do not expand scope or refactor unrelated code without being asked.';

  @override
  String get memberPromptPresetReviewer => 'Reviewer';

  @override
  String get memberPromptPresetReviewerText =>
      'Review code only. Do not modify files unless explicitly asked.';

  @override
  String get memberPromptPresetResearcher => 'Researcher';

  @override
  String get memberPromptPresetResearcherText =>
      'Investigate and report only. Do not change production code unless asked.';

  @override
  String get memberPlaybook => 'Working method';

  @override
  String get memberPlaybookSubtitle =>
      'How this role operates—a concrete procedure (HOW). May reference a team skill, but is plain instructions, not a fixed skill.';

  @override
  String get memberPlaybookPresetDeveloperText =>
      'Work test-first: before implementing, write a failing test, then make it pass with the smallest diff. Run the relevant tests after each change and report which files changed and why. Do not bundle unrelated edits; stop at agreed checkpoints. If a test-driven-development skill is available, follow it.';

  @override
  String get memberPlaybookPresetReviewerText =>
      'Review in order: (1) confirm tests cover the change; (2) correctness and edge cases; (3) maintainability and consistency with surrounding code. Every finding states file path, line, the problem, and a concrete fix—no vague praise and no nit without a fix. Flag missing tests explicitly.';

  @override
  String get memberPlaybookPresetResearcherText =>
      'Clarify intent before digging: restate the question and your assumptions, then investigate breadth-first across the codebase before going deep. Report findings with file paths, relevant symbols, and recommended next steps—propose, do not change production code. If a brainstorming skill is available, use it to frame the problem first.';

  @override
  String get selectModel => 'Select a model';

  @override
  String get appProviderModelEnterCustom => 'Enter custom model ID';

  @override
  String get appProviderModelPickFromList => 'Choose from list';

  @override
  String get memberOfficialClaudeModelHint =>
      'Uses your Claude account default model. Manage Official login in Providers settings.';

  @override
  String get editMemberSubtitle =>
      'Edit provider, model, optional agent preset, and command arguments.';

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
  String get appProviderToolOpencode => 'OpenCode';

  @override
  String get appProviderToolCursor => 'Cursor';

  @override
  String get appProviderTeamToolSection => 'Tool providers for this team';

  @override
  String get appProviderTeamToolSubtitle =>
      'Select which unified provider each tool uses when this team starts.';

  @override
  String get appProviderTeamNone => 'None';

  @override
  String get appProviderClaudeAuthField => 'Authentication field';

  @override
  String get appProviderClaudeAuthFieldHint =>
      'Select the authentication environment variable written to settings.';

  @override
  String get appProviderClaudeCredentialBinding => 'OAuth credential source';

  @override
  String get appProviderClaudeCredentialBindingLinked =>
      'Follow global (~/.claude)';

  @override
  String get appProviderClaudeCredentialBindingIsolated =>
      'Isolated copy (TeamPilot only)';

  @override
  String get appProviderClaudeCredentialBindingLinkedHint =>
      'Shares the same OAuth session as Claude Code in your terminal. Refreshes stay in sync.';

  @override
  String get appProviderClaudeCredentialBindingIsolatedHint =>
      'Keeps a separate credential copy under TeamPilot. Use when this provider must not share login with global Claude Code.';

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
  String get appUpdateAutoCheck => 'Auto-check for updates';

  @override
  String get appUpdateAutoCheckHint =>
      'Check GitHub for a newer version each time the app starts.';

  @override
  String get appUpdateSkipVersion => 'Skip this version';

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
  String get onboardingStepDefaultPreset => 'Default preset';

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
  String get onboardingDefaultPresetTitle => 'Configure default launch preset';

  @override
  String get onboardingDefaultPresetSubtitle =>
      'Personal workspaces and team default launch configs will use this CLI preset.';

  @override
  String get onboardingDefaultPresetEmpty =>
      'No providers to choose from. Skip this step or add providers in Settings.';

  @override
  String get onboardingDefaultPresetSelectExisting => 'Use existing preset';

  @override
  String get onboardingDefaultPresetDefaultName => 'Default';

  @override
  String get onboardingDefaultPresetModelHint =>
      'Primary model for this preset';

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

  @override
  String get diffIgnoreWhitespace => 'Ignore whitespace';

  @override
  String get diffPreviousChange => 'Previous change';

  @override
  String get diffNextChange => 'Next change';

  @override
  String get diffViewSideBySide => 'Side by side';

  @override
  String get diffViewUnified => 'Unified';

  @override
  String get diffOpenSourceFile => 'Open source file';

  @override
  String get diffShowAllLines => 'Show all lines';

  @override
  String get diffNoChanges => 'No changes';

  @override
  String diffChangeCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get aiFeatures => 'AI Features';

  @override
  String get aiFeaturesPageSubtitle =>
      'Choose which CLI provider, model, and effort each AI feature uses.';

  @override
  String get aiFeatureCommitMessageTitle => 'Commit message generation';

  @override
  String get aiFeatureCommitMessageSubtitle =>
      'Used by the ✨ button in the source control panel.';

  @override
  String get aiFeatureTeamGenerateTitle => 'Team configuration generation';

  @override
  String get aiFeatureTeamGenerateSubtitle =>
      'Used when generating a team from a description.';

  @override
  String get aiFeatureCliLabel => 'CLI';

  @override
  String get aiFeatureModelLabel => 'Model';

  @override
  String get aiFeatureEffortLabel => 'Effort';

  @override
  String aiFeatureConfigSummary(String cli, String provider, String model) {
    return '$cli · $provider · $model';
  }

  @override
  String get gitGenerateCommitMessage => 'Generate commit message with AI';

  @override
  String get gitGenerateCommitMessageNoProvider =>
      'Configure an AI provider in Settings → AI Features first.';

  @override
  String get teamGenTitle => 'Generate with AI';

  @override
  String get teamGenDescriptionHint =>
      'Describe the team you want (e.g. Flutter frontend with code review and tests)';

  @override
  String get teamGenButton => 'Generate';

  @override
  String get teamGenNoProvider =>
      'Configure an AI provider in Settings → AI Features first.';

  @override
  String get teamGenFailed =>
      'Could not generate a team. Please edit manually.';

  @override
  String get teamGenApplied =>
      'Draft applied. Review and adjust before creating.';

  @override
  String get notificationCenterTitle => 'Notifications';

  @override
  String get notificationEmpty => 'No notifications';

  @override
  String get notificationMarkAllRead => 'Mark all as read';

  @override
  String get notificationClearAll => 'Clear';

  @override
  String get notificationMarkRead => 'Mark as read';

  @override
  String get notificationDelete => 'Delete';

  @override
  String get notificationTimeJustNow => 'Just now';

  @override
  String notificationTimeMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String notificationTimeHoursAgo(int hours) {
    return '$hours h ago';
  }

  @override
  String get memberDetailTitle => 'Member detail';

  @override
  String get memberDetailViewAction => 'View member detail';

  @override
  String get memberDetailOpenConfigDir => 'Open config directory';

  @override
  String get memberDetailOpenInFileManager => 'Open in file manager';

  @override
  String get memberDetailBrowseConfigDirTitle => 'Config directory';

  @override
  String get memberDetailNeedsSession => 'Open a session first';

  @override
  String get memberDetailTabOverview => 'Overview';

  @override
  String get memberDetailTabSkills => 'Skills';

  @override
  String get memberDetailTabMcp => 'MCP';

  @override
  String get memberDetailTabPlugins => 'Plugins';

  @override
  String get memberDetailTabSettings => 'Settings';

  @override
  String get memberDetailSourceRuntime => 'Live session config';

  @override
  String get memberDetailSourceTeam =>
      'Team-level config (member not launched in this session)';

  @override
  String get memberDetailEmpty =>
      'This member has no config yet in this session, and the team layer is empty.';

  @override
  String get memberDetailLoadError =>
      'Failed to read this member\'s config directory.';

  @override
  String get memberDetailOpenConfigDirFailed =>
      'Couldn\'t open the config directory in a file manager.';

  @override
  String memberDetailOpenConfigDirFailedOnHost(String host) {
    return 'Couldn\'t open the config directory on $host. The remote host may have no desktop file manager.';
  }

  @override
  String get memberDetailSectionEmpty => 'None';

  @override
  String get cliConfigAiCliGroup => 'AI CLI';

  @override
  String get cliConfigToolchainGroup => 'Toolchain';

  @override
  String get toolchainGitLabel => 'Git executable path';

  @override
  String get toolchainNodeLabel => 'Node.js / npm path';

  @override
  String toolchainPathDescription(String tool) {
    return 'Absolute path to the $tool executable. Leave empty to use the one on PATH.';
  }

  @override
  String toolchainPathDescriptionSsh(String tool) {
    return 'Absolute path to $tool on the remote SSH host. Leave empty to auto-discover.';
  }

  @override
  String get cliCursorExecutablePathLabel => 'Cursor CLI path';

  @override
  String toolchainInstallProgressChecking(String tool) {
    return 'Checking for $tool...';
  }

  @override
  String get toolchainGit => 'Git';

  @override
  String get toolchainNode => 'Node.js';

  @override
  String get homeWorkspaceLaunchWorkspaceTitle => 'Open with…';

  @override
  String get homeWorkspaceSimpleMode => 'Simple mode';

  @override
  String get homeWorkspaceRememberLaunchChoice => 'Remember my choice';

  @override
  String get worktreeCreateTitle => 'New worktree';

  @override
  String get worktreeBranchLabel => 'Branch name';

  @override
  String get worktreeModeNewBranch => 'New branch';

  @override
  String get worktreeModeExistingBranch => 'Existing branch';

  @override
  String get worktreeBaseRefLabel => 'Base (optional)';

  @override
  String get worktreeBaseRefHint => 'Defaults to current HEAD';

  @override
  String get worktreePathLabel => 'Location';

  @override
  String get worktreeStartConversation =>
      'Start a conversation here after creating';

  @override
  String get worktreeCreateAction => 'Create';

  @override
  String worktreeCreateFailed(Object error) {
    return 'Failed to create worktree: $error';
  }

  @override
  String get worktreeDeleteTitle => 'Remove worktree';

  @override
  String worktreeDeleteBody(Object branch) {
    return 'Remove the worktree for $branch?';
  }

  @override
  String get worktreeDeleteForce =>
      'Force-remove even if it has uncommitted changes';

  @override
  String get worktreeDeleteBranchToo => 'Also delete the branch';

  @override
  String worktreeDeleteSessionsToo(Object count) {
    return 'Also delete the $count conversations in this worktree';
  }

  @override
  String get worktreeDeleteAction => 'Remove';

  @override
  String worktreeDeleteFailed(Object error) {
    return 'Failed to remove worktree: $error';
  }

  @override
  String get worktreeOrphanGroup => 'Other';

  @override
  String get worktreeNewWorktreeTooltip => 'New worktree';

  @override
  String get worktreeRefreshTooltip => 'Refresh worktrees';

  @override
  String get worktreeNewConversationHere => 'New conversation here';

  @override
  String get worktreeMenuCopyPath => 'Copy path';

  @override
  String get worktreeMenuRemove => 'Remove worktree';

  @override
  String worktreeShowMore(Object count) {
    return 'Show $count more';
  }

  @override
  String get worktreeShowLess => 'Show less';

  @override
  String get worktreeDeleteBusyWarning =>
      'Stop the running conversations in this worktree before removing it.';
}
