import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot'**
  String get appTitle;

  /// No description provided for @appRailChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get appRailChat;

  /// No description provided for @appRailRuns.
  ///
  /// In en, this message translates to:
  /// **'Runs'**
  String get appRailRuns;

  /// No description provided for @appRailConfig.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get appRailConfig;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'copy'**
  String get copy;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage FlashskyAI team and model settings.'**
  String get settingsPageSubtitle;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @layoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'global workbench'**
  String get layoutSubtitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @layoutPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Structure controls are global and apply across teams.'**
  String get layoutPageSubtitle;

  /// No description provided for @toolPlacement.
  ///
  /// In en, this message translates to:
  /// **'Tool Placement'**
  String get toolPlacement;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// No description provided for @bottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get bottom;

  /// No description provided for @rightTools.
  ///
  /// In en, this message translates to:
  /// **'Right Tools'**
  String get rightTools;

  /// No description provided for @openRightTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get openRightTools;

  /// No description provided for @rightToolsPanelVisible.
  ///
  /// In en, this message translates to:
  /// **'Show tools panel'**
  String get rightToolsPanelVisible;

  /// No description provided for @rightToolsPanelHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide tools panel'**
  String get rightToolsPanelHidden;

  /// No description provided for @bottomTray.
  ///
  /// In en, this message translates to:
  /// **'Bottom Tray'**
  String get bottomTray;

  /// No description provided for @stacked.
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get stacked;

  /// No description provided for @tabs.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get tabs;

  /// No description provided for @stackedTools.
  ///
  /// In en, this message translates to:
  /// **'Stacked Tools'**
  String get stackedTools;

  /// No description provided for @tabbedTools.
  ///
  /// In en, this message translates to:
  /// **'Tabbed Tools'**
  String get tabbedTools;

  /// No description provided for @regionVisibility.
  ///
  /// In en, this message translates to:
  /// **'Region Visibility'**
  String get regionVisibility;

  /// No description provided for @appRail.
  ///
  /// In en, this message translates to:
  /// **'App rail'**
  String get appRail;

  /// No description provided for @toolPlacementDescription.
  ///
  /// In en, this message translates to:
  /// **'Dock tool panels on the right or along the bottom edge.'**
  String get toolPlacementDescription;

  /// No description provided for @visibilityTeamSessionsHint.
  ///
  /// In en, this message translates to:
  /// **'Show the team sessions list in the left sidebar.'**
  String get visibilityTeamSessionsHint;

  /// No description provided for @visibilityMembersHint.
  ///
  /// In en, this message translates to:
  /// **'Show the member list next to tools or terminals.'**
  String get visibilityMembersHint;

  /// No description provided for @visibilityFileTreeHint.
  ///
  /// In en, this message translates to:
  /// **'Show the project file tree for quick navigation.'**
  String get visibilityFileTreeHint;

  /// No description provided for @rtkSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'RTK token savings'**
  String get rtkSettingsTitle;

  /// No description provided for @rtkSettingsEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable RTK'**
  String get rtkSettingsEnableTitle;

  /// No description provided for @rtkSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Compress Agent Bash command output before it reaches the model (requires rtk and jq on PATH).'**
  String get rtkSettingsDescription;

  /// No description provided for @rtkSettingsStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Host status'**
  String get rtkSettingsStatusTitle;

  /// No description provided for @rtkSettingsInstallLink.
  ///
  /// In en, this message translates to:
  /// **'Install guide'**
  String get rtkSettingsInstallLink;

  /// No description provided for @rtkStatusNotFound.
  ///
  /// In en, this message translates to:
  /// **'rtk not found on PATH'**
  String get rtkStatusNotFound;

  /// No description provided for @rtkStatusJqMissing.
  ///
  /// In en, this message translates to:
  /// **'jq not found on PATH'**
  String get rtkStatusJqMissing;

  /// No description provided for @rtkStatusInstalledGeneric.
  ///
  /// In en, this message translates to:
  /// **'rtk ready'**
  String get rtkStatusInstalledGeneric;

  /// No description provided for @rtkStatusInstalled.
  ///
  /// In en, this message translates to:
  /// **'rtk {version} ready'**
  String rtkStatusInstalled(String version);

  /// No description provided for @rtkStatusVersionTooOld.
  ///
  /// In en, this message translates to:
  /// **'rtk {version} is too old (need >= 0.23.0)'**
  String rtkStatusVersionTooOld(String version);

  /// No description provided for @rtkBashOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Only applies to Agent Bash tool calls. Built-in Read, Grep, and Glob are not rewritten.'**
  String get rtkBashOnlyHint;

  /// No description provided for @themeModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeModeTitle;

  /// No description provided for @themeModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Light, dark, or match the operating system appearance.'**
  String get themeModeDescription;

  /// No description provided for @themeColorPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme colors'**
  String get themeColorPresetTitle;

  /// No description provided for @themeColorPresetDescription.
  ///
  /// In en, this message translates to:
  /// **'Primary and accent colors for buttons, toggles, and highlights.'**
  String get themeColorPresetDescription;

  /// No description provided for @themePresetGraphite.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get themePresetGraphite;

  /// No description provided for @themePresetOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get themePresetOcean;

  /// No description provided for @themePresetViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get themePresetViolet;

  /// No description provided for @themePresetAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get themePresetAmber;

  /// No description provided for @themePresetForest.
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get themePresetForest;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Language used for menus, buttons, and labels.'**
  String get languageDescription;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @chatTo.
  ///
  /// In en, this message translates to:
  /// **'To:'**
  String get chatTo;

  /// No description provided for @copyPrompt.
  ///
  /// In en, this message translates to:
  /// **'Copy prompt'**
  String get copyPrompt;

  /// No description provided for @sendPrompt.
  ///
  /// In en, this message translates to:
  /// **'Send prompt'**
  String get sendPrompt;

  /// No description provided for @chatHintText.
  ///
  /// In en, this message translates to:
  /// **'Write a prompt for team-lead...'**
  String get chatHintText;

  /// No description provided for @emptyTimeline.
  ///
  /// In en, this message translates to:
  /// **'Local shell-mode conversation notes will appear here.'**
  String get emptyTimeline;

  /// No description provided for @fileTree.
  ///
  /// In en, this message translates to:
  /// **'File Tree'**
  String get fileTree;

  /// No description provided for @openTeam.
  ///
  /// In en, this message translates to:
  /// **'Open Team'**
  String get openTeam;

  /// No description provided for @openMember.
  ///
  /// In en, this message translates to:
  /// **'Open member'**
  String get openMember;

  /// No description provided for @filterFiles.
  ///
  /// In en, this message translates to:
  /// **'Filter files'**
  String get filterFiles;

  /// No description provided for @selectTeam.
  ///
  /// In en, this message translates to:
  /// **'Select team'**
  String get selectTeam;

  /// No description provided for @addTeamTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add team'**
  String get addTeamTooltip;

  /// No description provided for @addTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Add team'**
  String get addTeamTitle;

  /// No description provided for @teamCliLabel.
  ///
  /// In en, this message translates to:
  /// **'CLI backend'**
  String get teamCliLabel;

  /// No description provided for @teamCliSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Chosen when the team is created and cannot be changed later.'**
  String get teamCliSubtitle;

  /// No description provided for @teamCliComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get teamCliComingSoon;

  /// No description provided for @teamCliLockedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set when this team was created.'**
  String get teamCliLockedSubtitle;

  /// No description provided for @teamNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Team name is required.'**
  String get teamNameRequired;

  /// No description provided for @teamNameAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A team named \"{name}\" already exists.'**
  String teamNameAlreadyExists(String name);

  /// No description provided for @projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get newProject;

  /// No description provided for @newProjectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create a project with one or more directories'**
  String get newProjectTooltip;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @pickPrimaryDirectory.
  ///
  /// In en, this message translates to:
  /// **'Pick primary directory'**
  String get pickPrimaryDirectory;

  /// No description provided for @projectPrimaryPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a primary directory first.'**
  String get projectPrimaryPathRequired;

  /// No description provided for @projectPrimaryPathNotSelected.
  ///
  /// In en, this message translates to:
  /// **'No primary directory selected'**
  String get projectPrimaryPathNotSelected;

  /// No description provided for @projectDirectoryAdded.
  ///
  /// In en, this message translates to:
  /// **'Directory added to project'**
  String get projectDirectoryAdded;

  /// No description provided for @newSessionTooltip.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSessionTooltip;

  /// No description provided for @defaultNewChatSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get defaultNewChatSessionTitle;

  /// No description provided for @sessionStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting session…'**
  String get sessionStarting;

  /// No description provided for @sessionReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to chat'**
  String get sessionReadyTitle;

  /// No description provided for @sessionReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation with {memberName} in this workspace.'**
  String sessionReadySubtitle(String memberName);

  /// No description provided for @sessionReadySubtitleGeneric.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation in this workspace.'**
  String get sessionReadySubtitleGeneric;

  /// No description provided for @sessionReadyHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what you want in everyday language — no terminal commands needed.'**
  String get sessionReadyHint;

  /// No description provided for @sessionStartButton.
  ///
  /// In en, this message translates to:
  /// **'Start conversation'**
  String get sessionStartButton;

  /// No description provided for @sessionFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start session'**
  String get sessionFailedTitle;

  /// No description provided for @sessionRetryButton.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sessionRetryButton;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openFolder;

  /// No description provided for @copyFolderPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Folder Path'**
  String get copyFolderPath;

  /// No description provided for @pathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied: {path}'**
  String pathCopied(String path);

  /// No description provided for @projectDetails.
  ///
  /// In en, this message translates to:
  /// **'Project details'**
  String get projectDetails;

  /// No description provided for @projectDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Project Details'**
  String get projectDetailsTitle;

  /// No description provided for @addProjectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Add directory'**
  String get addProjectDirectory;

  /// No description provided for @removeProjectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Remove directory'**
  String get removeProjectDirectory;

  /// No description provided for @projectDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get projectDisplayName;

  /// No description provided for @projectPrimaryPath.
  ///
  /// In en, this message translates to:
  /// **'Primary directory'**
  String get projectPrimaryPath;

  /// No description provided for @projectAdditionalDirectories.
  ///
  /// In en, this message translates to:
  /// **'Additional directories'**
  String get projectAdditionalDirectories;

  /// No description provided for @projectNoAdditionalDirectories.
  ///
  /// In en, this message translates to:
  /// **'No additional directories'**
  String get projectNoAdditionalDirectories;

  /// No description provided for @projectSessionCount.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get projectSessionCount;

  /// No description provided for @projectCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get projectCreatedAt;

  /// No description provided for @projectUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get projectUpdatedAt;

  /// No description provided for @projectDirectoryAlreadyPrimary.
  ///
  /// In en, this message translates to:
  /// **'This path is already the primary directory.'**
  String get projectDirectoryAlreadyPrimary;

  /// No description provided for @projectDirectoryAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'This directory is already in the project.'**
  String get projectDirectoryAlreadyAdded;

  /// No description provided for @deleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete Project'**
  String get deleteProject;

  /// No description provided for @deleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete project \"{name}\" and all its sessions? This cannot be undone.'**
  String deleteProjectConfirm(String name);

  /// No description provided for @noSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get noSessions;

  /// No description provided for @unknownFolder.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownFolder;

  /// No description provided for @renameConversation.
  ///
  /// In en, this message translates to:
  /// **'Rename conversation'**
  String get renameConversation;

  /// No description provided for @deleteConversation.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get deleteConversation;

  /// No description provided for @renameConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Conversation'**
  String get renameConversationTitle;

  /// No description provided for @deleteConversationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation \"{name}\"? This cannot be undone.'**
  String deleteConversationConfirm(String name);

  /// No description provided for @conversationName.
  ///
  /// In en, this message translates to:
  /// **'Conversation name'**
  String get conversationName;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTab;

  /// No description provided for @closeOtherTabs.
  ///
  /// In en, this message translates to:
  /// **'Close Others'**
  String get closeOtherTabs;

  /// No description provided for @closeRightTabs.
  ///
  /// In en, this message translates to:
  /// **'Close to the Right'**
  String get closeRightTabs;

  /// No description provided for @session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// No description provided for @sessionPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure shell session launch and the LLM config file path.'**
  String get sessionPageSubtitle;

  /// No description provided for @connectionModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Runtime mode'**
  String get connectionModeLabel;

  /// No description provided for @connectionModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Local runs flashskyai on this device. SSH runs it on the selected remote server.'**
  String get connectionModeDescription;

  /// No description provided for @connectionModeLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get connectionModeLocal;

  /// No description provided for @connectionModeSsh.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get connectionModeSsh;

  /// No description provided for @sshProfilesSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH servers'**
  String get sshProfilesSettingsTitle;

  /// No description provided for @sshProfileSelectorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch SSH server'**
  String get sshProfileSelectorTooltip;

  /// No description provided for @sshProfileSelectorManage.
  ///
  /// In en, this message translates to:
  /// **'Manage SSH servers…'**
  String get sshProfileSelectorManage;

  /// No description provided for @cliExecutablePathLabel.
  ///
  /// In en, this message translates to:
  /// **'flashskyai CLI path'**
  String get cliExecutablePathLabel;

  /// No description provided for @cliExecutablePathDescription.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to the flashskyai executable. Leave empty to use the one on PATH.'**
  String get cliExecutablePathDescription;

  /// No description provided for @cliExecutablePathDescriptionSsh.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to flashskyai on the remote SSH host. Leave empty to auto-discover over SSH.'**
  String get cliExecutablePathDescriptionSsh;

  /// No description provided for @cliExecutablePathBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get cliExecutablePathBrowse;

  /// No description provided for @cliExecutablePathApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get cliExecutablePathApply;

  /// No description provided for @cliExecutablePathReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get cliExecutablePathReset;

  /// No description provided for @cliExecutablePathUsing.
  ///
  /// In en, this message translates to:
  /// **'Using: '**
  String get cliExecutablePathUsing;

  /// No description provided for @cliExecutablePathUsingFallback.
  ///
  /// In en, this message translates to:
  /// **'Using PATH lookup'**
  String get cliExecutablePathUsingFallback;

  /// No description provided for @cliInstallButton.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get cliInstallButton;

  /// No description provided for @cliInstallInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get cliInstallInstalling;

  /// No description provided for @cliInstallProgressCheckingNpm.
  ///
  /// In en, this message translates to:
  /// **'Checking for npm…'**
  String get cliInstallProgressCheckingNpm;

  /// No description provided for @cliInstallProgressBootstrappingNode.
  ///
  /// In en, this message translates to:
  /// **'Installing Node.js…'**
  String get cliInstallProgressBootstrappingNode;

  /// No description provided for @cliInstallProgressInstallingClaude.
  ///
  /// In en, this message translates to:
  /// **'Installing Claude Code…'**
  String get cliInstallProgressInstallingClaude;

  /// No description provided for @cliInstallProgressLocatingExecutable.
  ///
  /// In en, this message translates to:
  /// **'Locating Claude Code executable…'**
  String get cliInstallProgressLocatingExecutable;

  /// No description provided for @claudeCliExecutablePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Claude Code CLI path'**
  String get claudeCliExecutablePathLabel;

  /// No description provided for @claudeCliExecutablePathDescription.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to the Claude Code executable. Leave empty to use the one on PATH.'**
  String get claudeCliExecutablePathDescription;

  /// No description provided for @claudeCliExecutablePathDescriptionSsh.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to Claude Code on the remote SSH host. Leave empty to resolve claude from the remote PATH.'**
  String get claudeCliExecutablePathDescriptionSsh;

  /// No description provided for @shellChatWorkbench.
  ///
  /// In en, this message translates to:
  /// **'Shell chat workbench'**
  String get shellChatWorkbench;

  /// No description provided for @shellSession.
  ///
  /// In en, this message translates to:
  /// **'Shell session'**
  String get shellSession;

  /// No description provided for @terminalFind.
  ///
  /// In en, this message translates to:
  /// **'Find in terminal'**
  String get terminalFind;

  /// No description provided for @terminalFindNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get terminalFindNoResults;

  /// No description provided for @editorTitle.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorTitle;

  /// No description provided for @editorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editorSave;

  /// No description provided for @editorCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get editorCut;

  /// No description provided for @editorCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get editorCopy;

  /// No description provided for @editorCopyAsAiContext.
  ///
  /// In en, this message translates to:
  /// **'Copy as AI context'**
  String get editorCopyAsAiContext;

  /// No description provided for @editorPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get editorPaste;

  /// No description provided for @editorSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get editorSelectAll;

  /// No description provided for @editorUndoEdit.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get editorUndoEdit;

  /// No description provided for @editorRedoEdit.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get editorRedoEdit;

  /// No description provided for @editorRevertChanges.
  ///
  /// In en, this message translates to:
  /// **'Revert changes'**
  String get editorRevertChanges;

  /// No description provided for @editorClose.
  ///
  /// In en, this message translates to:
  /// **'Close editor'**
  String get editorClose;

  /// No description provided for @editorUnsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get editorUnsavedChangesTitle;

  /// No description provided for @editorUnsavedChangesDiscardFile.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes to \"{fileName}\"?'**
  String editorUnsavedChangesDiscardFile(String fileName);

  /// No description provided for @editorUnsavedChangesDiscardMultiple.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes in {count} file(s)?'**
  String editorUnsavedChangesDiscardMultiple(int count);

  /// No description provided for @editorDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editorDiscard;

  /// No description provided for @editorNotReady.
  ///
  /// In en, this message translates to:
  /// **'Editor not ready'**
  String get editorNotReady;

  /// No description provided for @editorNoFileOpen.
  ///
  /// In en, this message translates to:
  /// **'No file open'**
  String get editorNoFileOpen;

  /// No description provided for @editorBinaryFileHint.
  ///
  /// In en, this message translates to:
  /// **'Binary files open with the system default app.'**
  String get editorBinaryFileHint;

  /// No description provided for @editorFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get editorFileNotFound;

  /// No description provided for @editorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File is too large to edit in TeamPilot (max 2 MB).'**
  String get editorFileTooLarge;

  /// No description provided for @editorCouldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get editorCouldNotReadFile;

  /// No description provided for @editorFileReadOnly.
  ///
  /// In en, this message translates to:
  /// **'File is read-only'**
  String get editorFileReadOnly;

  /// No description provided for @editorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String editorSaveFailed(String error);

  /// No description provided for @fileTreeOpenWithSystemApp.
  ///
  /// In en, this message translates to:
  /// **'Open with system app'**
  String get fileTreeOpenWithSystemApp;

  /// No description provided for @fileTreeCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get fileTreeCopyPath;

  /// No description provided for @fileTreeDeleteItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get fileTreeDeleteItemTitle;

  /// No description provided for @fileTreeDeleteItemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String fileTreeDeleteItemConfirm(String name);

  /// No description provided for @terminalOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get terminalOpenLink;

  /// No description provided for @terminalExportScrollback.
  ///
  /// In en, this message translates to:
  /// **'Export scrollback…'**
  String get terminalExportScrollback;

  /// No description provided for @terminalScrollbackLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal scrollback lines'**
  String get terminalScrollbackLinesTitle;

  /// No description provided for @terminalScrollbackLinesDescription.
  ///
  /// In en, this message translates to:
  /// **'Maximum lines kept in each session terminal buffer (1000–200000).'**
  String get terminalScrollbackLinesDescription;

  /// No description provided for @autoLaunchAllMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Start all members on connect'**
  String get autoLaunchAllMembersTitle;

  /// No description provided for @autoLaunchAllMembersDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, Connect and Restart launch every valid member shell; otherwise only the selected member starts.'**
  String get autoLaunchAllMembersDescription;

  /// No description provided for @scopeSessionsToSelectedTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Scope sessions to selected team'**
  String get scopeSessionsToSelectedTeamTitle;

  /// No description provided for @scopeSessionsToSelectedTeamDescription.
  ///
  /// In en, this message translates to:
  /// **'When enabled, the sidebar shows only sessions assigned to the current team. New sessions are always tagged with the selected team so they appear here if you turn this on later.'**
  String get scopeSessionsToSelectedTeamDescription;

  /// No description provided for @windowsStorageBackendTitle.
  ///
  /// In en, this message translates to:
  /// **'Data storage location'**
  String get windowsStorageBackendTitle;

  /// No description provided for @windowsStorageBackendDescription.
  ///
  /// In en, this message translates to:
  /// **'Where teams, skills, projects, and config profiles are stored. Switching uses a separate data tree; nothing is migrated automatically.'**
  String get windowsStorageBackendDescription;

  /// No description provided for @windowsStorageBackendNative.
  ///
  /// In en, this message translates to:
  /// **'Windows local'**
  String get windowsStorageBackendNative;

  /// No description provided for @windowsStorageBackendWsl.
  ///
  /// In en, this message translates to:
  /// **'WSL'**
  String get windowsStorageBackendWsl;

  /// No description provided for @windowsStorageBackendCurrentRoot.
  ///
  /// In en, this message translates to:
  /// **'Current root: {path}'**
  String windowsStorageBackendCurrentRoot(String path);

  /// No description provided for @windowsStorageBackendSwitchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch storage location?'**
  String get windowsStorageBackendSwitchConfirmTitle;

  /// No description provided for @windowsStorageBackendSwitchConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This uses a different data directory. Teams, projects, and skills from the other location will not appear until you switch back.'**
  String get windowsStorageBackendSwitchConfirmBody;

  /// No description provided for @windowsStorageBackendSwitchConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get windowsStorageBackendSwitchConfirmAction;

  /// No description provided for @windowsStorageBackendWslUnavailable.
  ///
  /// In en, this message translates to:
  /// **'WSL is not available. Install or start WSL before using WSL storage.'**
  String get windowsStorageBackendWslUnavailable;

  /// No description provided for @windowsStorageCliMismatchNativeCli.
  ///
  /// In en, this message translates to:
  /// **'CLI runs in WSL but data is stored in Windows AppData. Config may not match.'**
  String get windowsStorageCliMismatchNativeCli;

  /// No description provided for @windowsStorageCliMismatchWslCli.
  ///
  /// In en, this message translates to:
  /// **'CLI runs on Windows but data is stored in WSL. Config may not match.'**
  String get windowsStorageCliMismatchWslCli;

  /// No description provided for @windowsStorageSwitchReloadHint.
  ///
  /// In en, this message translates to:
  /// **'Reconnect open sessions after switching storage.'**
  String get windowsStorageSwitchReloadHint;

  /// No description provided for @bootstrapStartupFailed.
  ///
  /// In en, this message translates to:
  /// **'Startup failed: {error}'**
  String bootstrapStartupFailed(String error);

  /// No description provided for @bootstrapUseNativeStorageInstead.
  ///
  /// In en, this message translates to:
  /// **'Use Windows local storage instead'**
  String get bootstrapUseNativeStorageInstead;

  /// No description provided for @runsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Run history will appear here.'**
  String get runsPlaceholder;

  /// No description provided for @llmConfig.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get llmConfig;

  /// No description provided for @llmConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'providers and models'**
  String get llmConfigSubtitle;

  /// No description provided for @llmConfigPathLabel.
  ///
  /// In en, this message translates to:
  /// **'LLM config file'**
  String get llmConfigPathLabel;

  /// No description provided for @llmConfigPathHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the default path'**
  String get llmConfigPathHint;

  /// No description provided for @llmConfigPathBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse...'**
  String get llmConfigPathBrowse;

  /// No description provided for @llmConfigPathSave.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get llmConfigPathSave;

  /// No description provided for @llmConfigPathReset.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get llmConfigPathReset;

  /// No description provided for @llmConfigPathBadgeDefault.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get llmConfigPathBadgeDefault;

  /// No description provided for @llmConfigPathBadgeCustom.
  ///
  /// In en, this message translates to:
  /// **'custom'**
  String get llmConfigPathBadgeCustom;

  /// No description provided for @llmConfigPathPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select llm_config.json'**
  String get llmConfigPathPickerTitle;

  /// No description provided for @llmConfigPathSessionCardDescription.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to the LLM config file (llm_config.json). Leave empty to use the default path next to the CLI install.'**
  String get llmConfigPathSessionCardDescription;

  /// No description provided for @llmConfigPathSessionCardDescriptionSsh.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to llm_config.json on the remote SSH host. Leave empty to use the default path next to the remote CLI install.'**
  String get llmConfigPathSessionCardDescriptionSsh;

  /// No description provided for @llmConfigCurrentEffectivePathPrefix.
  ///
  /// In en, this message translates to:
  /// **'Active file:'**
  String get llmConfigCurrentEffectivePathPrefix;

  /// No description provided for @llmConfigEffectivePathUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve a path yet (set the CLI location or enter a path).'**
  String get llmConfigEffectivePathUnresolved;

  /// No description provided for @llmConfigOpenSessionSettings.
  ///
  /// In en, this message translates to:
  /// **'Session settings…'**
  String get llmConfigOpenSessionSettings;

  /// No description provided for @providers.
  ///
  /// In en, this message translates to:
  /// **'PROVIDERS'**
  String get providers;

  /// No description provided for @llmConfigPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage LLM providers and models.'**
  String get llmConfigPageSubtitle;

  /// No description provided for @providersTab.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get providersTab;

  /// No description provided for @modelsTab.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get modelsTab;

  /// No description provided for @rawJsonTab.
  ///
  /// In en, this message translates to:
  /// **'Raw JSON'**
  String get rawJsonTab;

  /// No description provided for @addProvider.
  ///
  /// In en, this message translates to:
  /// **'Add Provider'**
  String get addProvider;

  /// No description provided for @providerName.
  ///
  /// In en, this message translates to:
  /// **'Provider name'**
  String get providerName;

  /// No description provided for @renameProviderName.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameProviderName;

  /// No description provided for @renameProviderTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename provider'**
  String get renameProviderTitle;

  /// No description provided for @deleteProvider.
  ///
  /// In en, this message translates to:
  /// **'Delete Provider'**
  String get deleteProvider;

  /// No description provided for @deleteProviderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete provider {name}?'**
  String deleteProviderConfirm(String name);

  /// No description provided for @providerList.
  ///
  /// In en, this message translates to:
  /// **'Provider List'**
  String get providerList;

  /// No description provided for @filterProviders.
  ///
  /// In en, this message translates to:
  /// **'Filter providers...'**
  String get filterProviders;

  /// No description provided for @appProviderImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get appProviderImport;

  /// No description provided for @appProviderImportNothing.
  ///
  /// In en, this message translates to:
  /// **'No providers found to import.'**
  String get appProviderImportNothing;

  /// No description provided for @appProviderImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} providers. Mirrored {mirrored} to FlashskyAI, skipped {skipped} existing.'**
  String appProviderImportSuccess(int count, int mirrored, int skipped);

  /// No description provided for @modelsUsingProvider.
  ///
  /// In en, this message translates to:
  /// **'Models using this provider: {count}'**
  String modelsUsingProvider(int count);

  /// No description provided for @providerListModelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} models'**
  String providerListModelCount(int count);

  /// No description provided for @proxyOnShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy on'**
  String get proxyOnShort;

  /// No description provided for @proxyOffShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy off'**
  String get proxyOffShort;

  /// No description provided for @providerDetailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{type} provider · {count} models'**
  String providerDetailSubtitle(int count, String type);

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @providerType.
  ///
  /// In en, this message translates to:
  /// **'Provider type'**
  String get providerType;

  /// No description provided for @providerTypeHint.
  ///
  /// In en, this message translates to:
  /// **'openai, claude, or custom'**
  String get providerTypeHint;

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @proxyUrl.
  ///
  /// In en, this message translates to:
  /// **'Proxy URL'**
  String get proxyUrl;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @appProviderApiKeyEditHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the existing key'**
  String get appProviderApiKeyEditHint;

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @replaceKey.
  ///
  /// In en, this message translates to:
  /// **'Replace key'**
  String get replaceKey;

  /// No description provided for @deleteProviderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete provider'**
  String get deleteProviderTooltip;

  /// No description provided for @deleteProviderWithCredentialsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete provider {name}? Saved Claude login credentials for this provider will also be removed.'**
  String deleteProviderWithCredentialsConfirm(String name);

  /// No description provided for @claudeOfficialCredentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Claude Official login'**
  String get claudeOfficialCredentialsTitle;

  /// No description provided for @claudeOfficialCredentialsReady.
  ///
  /// In en, this message translates to:
  /// **'Credentials ready'**
  String get claudeOfficialCredentialsReady;

  /// No description provided for @claudeOfficialCredentialsMissing.
  ///
  /// In en, this message translates to:
  /// **'No credentials saved for this provider'**
  String get claudeOfficialCredentialsMissing;

  /// No description provided for @claudeOfficialCredentialsLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Claude'**
  String get claudeOfficialCredentialsLogin;

  /// No description provided for @claudeOfficialCredentialsImportGlobal.
  ///
  /// In en, this message translates to:
  /// **'Import from ~/.claude'**
  String get claudeOfficialCredentialsImportGlobal;

  /// No description provided for @claudeOfficialCredentialsImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import file…'**
  String get claudeOfficialCredentialsImportFile;

  /// No description provided for @claudeOfficialCredentialsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get claudeOfficialCredentialsRevoke;

  /// No description provided for @claudeOfficialCredentialsRevokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out and remove saved credentials for {name}?'**
  String claudeOfficialCredentialsRevokeConfirm(String name);

  /// No description provided for @claudeOfficialCredentialsActionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Credentials updated'**
  String get claudeOfficialCredentialsActionSuccess;

  /// No description provided for @claudeOfficialCredentialsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update credentials'**
  String get claudeOfficialCredentialsActionFailed;

  /// No description provided for @claudeLaunchCredentialsMissingWarning.
  ///
  /// In en, this message translates to:
  /// **'Claude Official credentials are missing for this team provider. Sign in from Providers settings.'**
  String get claudeLaunchCredentialsMissingWarning;

  /// No description provided for @noModelsUsingProvider.
  ///
  /// In en, this message translates to:
  /// **'No models are using this provider.'**
  String get noModelsUsingProvider;

  /// No description provided for @modelsUsingProviderTitle.
  ///
  /// In en, this message translates to:
  /// **'Models using this provider'**
  String get modelsUsingProviderTitle;

  /// No description provided for @selectProvider.
  ///
  /// In en, this message translates to:
  /// **'Select a provider from the list'**
  String get selectProvider;

  /// No description provided for @accountCredentialPath.
  ///
  /// In en, this message translates to:
  /// **'Account credential path'**
  String get accountCredentialPath;

  /// No description provided for @removePath.
  ///
  /// In en, this message translates to:
  /// **'Remove path'**
  String get removePath;

  /// No description provided for @addAccountPath.
  ///
  /// In en, this message translates to:
  /// **'Add account path'**
  String get addAccountPath;

  /// No description provided for @api.
  ///
  /// In en, this message translates to:
  /// **'api'**
  String get api;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'account'**
  String get account;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get addModel;

  /// No description provided for @modelName.
  ///
  /// In en, this message translates to:
  /// **'Model alias/name'**
  String get modelName;

  /// No description provided for @modelId.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
  String get modelId;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String editModelTitle(String name);

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @actualModel.
  ///
  /// In en, this message translates to:
  /// **'Actual Model'**
  String get actualModel;

  /// No description provided for @noModelsConfigured.
  ///
  /// In en, this message translates to:
  /// **'No models configured'**
  String get noModelsConfigured;

  /// No description provided for @missingProvider.
  ///
  /// In en, this message translates to:
  /// **'Missing provider:'**
  String get missingProvider;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @statProviders.
  ///
  /// In en, this message translates to:
  /// **'providers'**
  String get statProviders;

  /// No description provided for @statModels.
  ///
  /// In en, this message translates to:
  /// **'models'**
  String get statModels;

  /// No description provided for @statMissingRefs.
  ///
  /// In en, this message translates to:
  /// **'missing refs'**
  String get statMissingRefs;

  /// No description provided for @statEmptyKeys.
  ///
  /// In en, this message translates to:
  /// **'empty keys'**
  String get statEmptyKeys;

  /// No description provided for @validation.
  ///
  /// In en, this message translates to:
  /// **'Validation'**
  String get validation;

  /// No description provided for @allChecksPassed.
  ///
  /// In en, this message translates to:
  /// **'All checks passed.'**
  String get allChecksPassed;

  /// No description provided for @validate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get validate;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @jsonPreview.
  ///
  /// In en, this message translates to:
  /// **'JSON Preview'**
  String get jsonPreview;

  /// No description provided for @skillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skillsTitle;

  /// No description provided for @skillsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage installable skills'**
  String get skillsSubtitle;

  /// No description provided for @skillsSidebarLabel.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skillsSidebarLabel;

  /// No description provided for @skillsNavInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get skillsNavInstalled;

  /// No description provided for @skillsNavDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get skillsNavDiscovery;

  /// No description provided for @skillsNavRepos.
  ///
  /// In en, this message translates to:
  /// **'Repos'**
  String get skillsNavRepos;

  /// No description provided for @skillsInstalledCount.
  ///
  /// In en, this message translates to:
  /// **'{count} installed'**
  String skillsInstalledCount(int count);

  /// No description provided for @skillsCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check updates'**
  String get skillsCheckUpdates;

  /// No description provided for @skillsCheckingUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get skillsCheckingUpdates;

  /// No description provided for @skillsUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'Update all ({count})'**
  String skillsUpdateAll(int count);

  /// No description provided for @skillsImportFromDisk.
  ///
  /// In en, this message translates to:
  /// **'Import from disk'**
  String get skillsImportFromDisk;

  /// No description provided for @skillsInstallFromZip.
  ///
  /// In en, this message translates to:
  /// **'Install from ZIP'**
  String get skillsInstallFromZip;

  /// No description provided for @skillsNoInstalled.
  ///
  /// In en, this message translates to:
  /// **'No skills installed yet'**
  String get skillsNoInstalled;

  /// No description provided for @skillsNoInstalledHint.
  ///
  /// In en, this message translates to:
  /// **'Open Discovery to install your first skill.'**
  String get skillsNoInstalledHint;

  /// No description provided for @skillsGoDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Go to Discovery'**
  String get skillsGoDiscovery;

  /// No description provided for @skillsSourceRepos.
  ///
  /// In en, this message translates to:
  /// **'Repos'**
  String get skillsSourceRepos;

  /// No description provided for @skillsSourceSkillsSh.
  ///
  /// In en, this message translates to:
  /// **'skills.sh'**
  String get skillsSourceSkillsSh;

  /// No description provided for @skillsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search skills…'**
  String get skillsSearchPlaceholder;

  /// No description provided for @skillsSkillsShPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search skills.sh (≥ 2 chars)…'**
  String get skillsSkillsShPlaceholder;

  /// No description provided for @skillsFilterRepoAll.
  ///
  /// In en, this message translates to:
  /// **'All repos'**
  String get skillsFilterRepoAll;

  /// No description provided for @skillsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get skillsFilterAll;

  /// No description provided for @skillsFilterInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get skillsFilterInstalled;

  /// No description provided for @skillsFilterUninstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get skillsFilterUninstalled;

  /// No description provided for @skillsCardInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get skillsCardInstall;

  /// No description provided for @skillsCardDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get skillsCardDetails;

  /// No description provided for @skillsCardInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get skillsCardInstalled;

  /// No description provided for @skillsCardUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get skillsCardUpdate;

  /// No description provided for @skillsCardUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get skillsCardUninstall;

  /// No description provided for @skillsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get skillsUpdateAvailable;

  /// No description provided for @skillsLocal.
  ///
  /// In en, this message translates to:
  /// **'local'**
  String get skillsLocal;

  /// No description provided for @skillsReposEmpty.
  ///
  /// In en, this message translates to:
  /// **'No repos yet'**
  String get skillsReposEmpty;

  /// No description provided for @skillsRepoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add repo'**
  String get skillsRepoAdd;

  /// No description provided for @skillsDiscoverySyncing.
  ///
  /// In en, this message translates to:
  /// **'Checking repos for updates and syncing skills in the background…'**
  String get skillsDiscoverySyncing;

  /// No description provided for @skillsRepoSyncing.
  ///
  /// In en, this message translates to:
  /// **'Updating'**
  String get skillsRepoSyncing;

  /// No description provided for @skillsRepoInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid GitHub repo URL, e.g. https://github.com/owner/repo'**
  String get skillsRepoInvalidUrl;

  /// No description provided for @skillsRepoUrl.
  ///
  /// In en, this message translates to:
  /// **'Repository URL'**
  String get skillsRepoUrl;

  /// No description provided for @skillsRepoUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://github.com/owner/repo'**
  String get skillsRepoUrlHint;

  /// No description provided for @skillsRepoBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get skillsRepoBranch;

  /// No description provided for @skillsRepoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get skillsRepoRemove;

  /// No description provided for @skillsRepoRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove repo {name}?'**
  String skillsRepoRemoveConfirm(String name);

  /// No description provided for @skillsUninstallConfirm.
  ///
  /// In en, this message translates to:
  /// **'Uninstall {name}?'**
  String skillsUninstallConfirm(String name);

  /// No description provided for @skillsOverwriteConfirm.
  ///
  /// In en, this message translates to:
  /// **'{name} already installed. Overwrite?'**
  String skillsOverwriteConfirm(String name);

  /// No description provided for @skillsInstallSuccess.
  ///
  /// In en, this message translates to:
  /// **'Installed {name}'**
  String skillsInstallSuccess(String name);

  /// No description provided for @skillsUninstallSuccess.
  ///
  /// In en, this message translates to:
  /// **'Uninstalled {name}'**
  String skillsUninstallSuccess(String name);

  /// No description provided for @skillsUpdateSuccess.
  ///
  /// In en, this message translates to:
  /// **'Updated {name}'**
  String skillsUpdateSuccess(String name);

  /// No description provided for @skillsNoUpdates.
  ///
  /// In en, this message translates to:
  /// **'All skills are up to date'**
  String get skillsNoUpdates;

  /// No description provided for @skillsImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import unmanaged skills'**
  String get skillsImportTitle;

  /// No description provided for @skillsImportNothing.
  ///
  /// In en, this message translates to:
  /// **'No unmanaged skills found.'**
  String get skillsImportNothing;

  /// No description provided for @skillsImportSelected.
  ///
  /// In en, this message translates to:
  /// **'Import {count} selected'**
  String skillsImportSelected(int count);

  /// No description provided for @skillsZipNoSkills.
  ///
  /// In en, this message translates to:
  /// **'No SKILL.md found in the archive.'**
  String get skillsZipNoSkills;

  /// No description provided for @skillsSkillsShLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get skillsSkillsShLoadMore;

  /// No description provided for @skillsSkillsShPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Powered by skills.sh'**
  String get skillsSkillsShPoweredBy;

  /// No description provided for @skillsSkillsShSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get skillsSkillsShSearch;

  /// No description provided for @skillsDiscoveryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No skills discovered'**
  String get skillsDiscoveryEmpty;

  /// No description provided for @skillsDiscoveryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add a repo or try skills.sh to find skills.'**
  String get skillsDiscoveryEmptyHint;

  /// No description provided for @skillsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get skillsAdd;

  /// No description provided for @skillsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get skillsRemove;

  /// No description provided for @skillsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get skillsEnabled;

  /// No description provided for @skillsInstalls.
  ///
  /// In en, this message translates to:
  /// **'{count} installs'**
  String skillsInstalls(int count);

  /// No description provided for @pluginsTitle.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get pluginsTitle;

  /// No description provided for @pluginsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Claude Code-style plugin bundles'**
  String get pluginsSubtitle;

  /// No description provided for @pluginsSidebarLabel.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get pluginsSidebarLabel;

  /// No description provided for @pluginsNavInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get pluginsNavInstalled;

  /// No description provided for @pluginsNavDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get pluginsNavDiscovery;

  /// No description provided for @pluginsNavMarketplaces.
  ///
  /// In en, this message translates to:
  /// **'Marketplaces'**
  String get pluginsNavMarketplaces;

  /// No description provided for @pluginsInstalledCount.
  ///
  /// In en, this message translates to:
  /// **'{count} installed'**
  String pluginsInstalledCount(int count);

  /// No description provided for @pluginsUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'Update all ({count})'**
  String pluginsUpdateAll(int count);

  /// No description provided for @pluginsImportFromDisk.
  ///
  /// In en, this message translates to:
  /// **'Import from disk'**
  String get pluginsImportFromDisk;

  /// No description provided for @pluginsImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import unmanaged plugins'**
  String get pluginsImportTitle;

  /// No description provided for @pluginsImportNothing.
  ///
  /// In en, this message translates to:
  /// **'No unmanaged plugins found.'**
  String get pluginsImportNothing;

  /// No description provided for @pluginsInstallFromZip.
  ///
  /// In en, this message translates to:
  /// **'Install from ZIP'**
  String get pluginsInstallFromZip;

  /// No description provided for @pluginsCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check updates'**
  String get pluginsCheckUpdates;

  /// No description provided for @pluginsCheckingUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get pluginsCheckingUpdates;

  /// No description provided for @pluginsNoInstalled.
  ///
  /// In en, this message translates to:
  /// **'No plugins installed'**
  String get pluginsNoInstalled;

  /// No description provided for @pluginsNoInstalledHint.
  ///
  /// In en, this message translates to:
  /// **'Add a marketplace and install plugins from the Discovery tab.'**
  String get pluginsNoInstalledHint;

  /// No description provided for @pluginsGoDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Browse marketplace'**
  String get pluginsGoDiscovery;

  /// No description provided for @pluginsCardInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get pluginsCardInstall;

  /// No description provided for @pluginsCardDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get pluginsCardDetails;

  /// No description provided for @pluginsCardInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get pluginsCardInstalled;

  /// No description provided for @pluginsCardViewSource.
  ///
  /// In en, this message translates to:
  /// **'View source'**
  String get pluginsCardViewSource;

  /// No description provided for @pluginsCardUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get pluginsCardUpdate;

  /// No description provided for @pluginsCardUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get pluginsCardUninstall;

  /// No description provided for @pluginsMarketplaceAdd.
  ///
  /// In en, this message translates to:
  /// **'Add marketplace'**
  String get pluginsMarketplaceAdd;

  /// No description provided for @pluginsMarketplaceUrl.
  ///
  /// In en, this message translates to:
  /// **'GitHub repository URL'**
  String get pluginsMarketplaceUrl;

  /// No description provided for @pluginsMarketplaceUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://github.com/owner/marketplace'**
  String get pluginsMarketplaceUrlHint;

  /// No description provided for @pluginsMarketplaceBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get pluginsMarketplaceBranch;

  /// No description provided for @pluginsMarketplaceRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove marketplace'**
  String get pluginsMarketplaceRemove;

  /// No description provided for @pluginsMarketplaceRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove marketplace {url}? Installed plugins are kept.'**
  String pluginsMarketplaceRemoveConfirm(String url);

  /// No description provided for @pluginsMarketplaceInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid GitHub repository URL.'**
  String get pluginsMarketplaceInvalidUrl;

  /// No description provided for @pluginsMarketplacesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No marketplaces configured'**
  String get pluginsMarketplacesEmpty;

  /// No description provided for @pluginsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search plugins'**
  String get pluginsSearchPlaceholder;

  /// No description provided for @pluginsFilterMarketplaceAll.
  ///
  /// In en, this message translates to:
  /// **'All marketplaces'**
  String get pluginsFilterMarketplaceAll;

  /// No description provided for @pluginsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get pluginsFilterAll;

  /// No description provided for @pluginsFilterInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get pluginsFilterInstalled;

  /// No description provided for @pluginsFilterUninstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get pluginsFilterUninstalled;

  /// No description provided for @pluginsDiscoveryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching plugins'**
  String get pluginsDiscoveryEmpty;

  /// No description provided for @pluginsDiscoverySyncing.
  ///
  /// In en, this message translates to:
  /// **'Checking marketplaces for updates and syncing plugins in the background…'**
  String get pluginsDiscoverySyncing;

  /// No description provided for @pluginsUninstallConfirm.
  ///
  /// In en, this message translates to:
  /// **'Uninstall {name}? This may affect {n} team(s).'**
  String pluginsUninstallConfirm(String name, int n);

  /// No description provided for @pluginsUninstallImpactList.
  ///
  /// In en, this message translates to:
  /// **'Affected teams:'**
  String get pluginsUninstallImpactList;

  /// No description provided for @pluginsUninstallSuccess.
  ///
  /// In en, this message translates to:
  /// **'Uninstalled {name}'**
  String pluginsUninstallSuccess(String name);

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @teamSessions.
  ///
  /// In en, this message translates to:
  /// **'Team Sessions'**
  String get teamSessions;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @teamConfig.
  ///
  /// In en, this message translates to:
  /// **'Team Config'**
  String get teamConfig;

  /// No description provided for @teamSettings.
  ///
  /// In en, this message translates to:
  /// **'Team Settings'**
  String get teamSettings;

  /// No description provided for @teamSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'workspace teams'**
  String get teamSettingsSubtitle;

  /// No description provided for @membersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'team agents'**
  String get membersSubtitle;

  /// No description provided for @teamSkillsNav.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get teamSkillsNav;

  /// No description provided for @teamSkillsAssignedCount.
  ///
  /// In en, this message translates to:
  /// **'{assigned} of {total} enabled'**
  String teamSkillsAssignedCount(int assigned, int total);

  /// No description provided for @teamSkillsManage.
  ///
  /// In en, this message translates to:
  /// **'All skills'**
  String get teamSkillsManage;

  /// No description provided for @teamPluginsNav.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get teamPluginsNav;

  /// No description provided for @teamPluginsAssignedCount.
  ///
  /// In en, this message translates to:
  /// **'{assigned} of {total} installed'**
  String teamPluginsAssignedCount(int assigned, int total);

  /// No description provided for @teamPluginsManage.
  ///
  /// In en, this message translates to:
  /// **'All plugins'**
  String get teamPluginsManage;

  /// No description provided for @teamPluginsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No plugins installed'**
  String get teamPluginsEmpty;

  /// No description provided for @teamPluginsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Install plugins from Discovery to enable them per team.'**
  String get teamPluginsEmptyHint;

  /// No description provided for @teamPluginsGoDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Browse marketplace'**
  String get teamPluginsGoDiscovery;

  /// No description provided for @teamPluginsMissing.
  ///
  /// In en, this message translates to:
  /// **'{count} enabled plugin(s) missing on disk. Reinstall or remove below.'**
  String teamPluginsMissing(int count);

  /// No description provided for @teamPluginsRemoveMissing.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get teamPluginsRemoveMissing;

  /// No description provided for @teamPluginsMissingLabel.
  ///
  /// In en, this message translates to:
  /// **'Missing on disk'**
  String get teamPluginsMissingLabel;

  /// No description provided for @teamPluginsNameConflict.
  ///
  /// In en, this message translates to:
  /// **'Linked as {dir} due to name conflict'**
  String teamPluginsNameConflict(String dir);

  /// No description provided for @teamPluginsCliUnsupportedBanner.
  ///
  /// In en, this message translates to:
  /// **'This team\'s CLI does not support plugins yet. Selections are saved but ignored at launch.'**
  String get teamPluginsCliUnsupportedBanner;

  /// No description provided for @memberQuickList.
  ///
  /// In en, this message translates to:
  /// **'MEMBER QUICK LIST'**
  String get memberQuickList;

  /// No description provided for @teamName.
  ///
  /// In en, this message translates to:
  /// **'Team name'**
  String get teamName;

  /// No description provided for @teamDescription.
  ///
  /// In en, this message translates to:
  /// **'Team description'**
  String get teamDescription;

  /// No description provided for @teamDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional note for Claude roster and team context'**
  String get teamDescriptionHint;

  /// No description provided for @deleteTeam.
  ///
  /// In en, this message translates to:
  /// **'Delete team'**
  String get deleteTeam;

  /// No description provided for @deleteTeamSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes this team from the UI and the shared flashskyai data directory. This cannot be undone.'**
  String get deleteTeamSubtitle;

  /// No description provided for @deleteTeamConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete team \"{name}\"? This cannot be undone.'**
  String deleteTeamConfirm(String name);

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @teamExtraArgs.
  ///
  /// In en, this message translates to:
  /// **'Team extra CLI arguments'**
  String get teamExtraArgs;

  /// No description provided for @teamExtraArgsHint.
  ///
  /// In en, this message translates to:
  /// **'--permission-mode acceptEdits'**
  String get teamExtraArgsHint;

  /// No description provided for @teamLoop.
  ///
  /// In en, this message translates to:
  /// **'Phase loop'**
  String get teamLoop;

  /// No description provided for @teamLoopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Team mode: true auto-advances phases; false requires your confirmation.'**
  String get teamLoopSubtitle;

  /// No description provided for @teamLoopDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get teamLoopDefault;

  /// No description provided for @teamLoopTrue.
  ///
  /// In en, this message translates to:
  /// **'true — auto-advance'**
  String get teamLoopTrue;

  /// No description provided for @teamLoopFalse.
  ///
  /// In en, this message translates to:
  /// **'false — confirm each phase'**
  String get teamLoopFalse;

  /// No description provided for @teamLeadDelegateOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Team lead: plan and delegate only'**
  String get teamLeadDelegateOnlyTitle;

  /// No description provided for @teamLeadDelegateOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, the team lead is blocked from using some tools.'**
  String get teamLeadDelegateOnlySubtitle;

  /// No description provided for @memberLaunchOrder.
  ///
  /// In en, this message translates to:
  /// **'Member launch order'**
  String get memberLaunchOrder;

  /// No description provided for @saveMember.
  ///
  /// In en, this message translates to:
  /// **'Save Member'**
  String get saveMember;

  /// No description provided for @editTeamSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit team identity, working directory, and launch order.'**
  String get editTeamSubtitle;

  /// No description provided for @memberName.
  ///
  /// In en, this message translates to:
  /// **'Member name'**
  String get memberName;

  /// No description provided for @memberNameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shown in the sidebar and when assigning work.'**
  String get memberNameSubtitle;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @agent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agent;

  /// No description provided for @selectAgent.
  ///
  /// In en, this message translates to:
  /// **'Select an agent'**
  String get selectAgent;

  /// No description provided for @agentBuiltInNone.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get agentBuiltInNone;

  /// No description provided for @agentBuiltInCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get agentBuiltInCustom;

  /// No description provided for @agentBuiltInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which agent role this member uses; shapes behavior and capabilities.'**
  String get agentBuiltInSubtitle;

  /// No description provided for @agentCustomIdHint.
  ///
  /// In en, this message translates to:
  /// **'Custom agent id'**
  String get agentCustomIdHint;

  /// No description provided for @memberExtraArgs.
  ///
  /// In en, this message translates to:
  /// **'Member extra CLI arguments'**
  String get memberExtraArgs;

  /// No description provided for @memberExtraArgsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Extra flags applied only when this member starts.'**
  String get memberExtraArgsSubtitle;

  /// No description provided for @memberDangerouslySkipPermissions.
  ///
  /// In en, this message translates to:
  /// **'Skip all permission checks'**
  String get memberDangerouslySkipPermissions;

  /// No description provided for @memberDangerouslySkipPermissionsHint.
  ///
  /// In en, this message translates to:
  /// **'Only for isolated / no-network sandboxes. Extremely risky otherwise.'**
  String get memberDangerouslySkipPermissionsHint;

  /// No description provided for @prompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get prompt;

  /// No description provided for @memberPromptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Brief duty boundaries and role notes for the team lead.'**
  String get memberPromptSubtitle;

  /// No description provided for @memberPromptPresetsLabel.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get memberPromptPresetsLabel;

  /// No description provided for @memberPromptPresetTeamLead.
  ///
  /// In en, this message translates to:
  /// **'Team lead'**
  String get memberPromptPresetTeamLead;

  /// No description provided for @memberPromptPresetTeamLeadText.
  ///
  /// In en, this message translates to:
  /// **'Coordinate the team. Break work into scoped tasks with clear done criteria before implementation.\nDo not implement large changes yourself unless blocking.\nReply to the user in this chat; never SendMessage to team-lead. Assign tasks and spawn Agent only for other member names.'**
  String get memberPromptPresetTeamLeadText;

  /// No description provided for @memberPromptPresetDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get memberPromptPresetDeveloper;

  /// No description provided for @memberPromptPresetDeveloperText.
  ///
  /// In en, this message translates to:
  /// **'Implement assigned tasks only within the agreed scope.\nPrefer minimal diffs, run relevant tests, and report changed files with brief rationale.'**
  String get memberPromptPresetDeveloperText;

  /// No description provided for @memberPromptPresetReviewer.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get memberPromptPresetReviewer;

  /// No description provided for @memberPromptPresetReviewerText.
  ///
  /// In en, this message translates to:
  /// **'Review code only; do not modify files unless asked.\nEach finding must include file path, line, issue, and suggested fix.'**
  String get memberPromptPresetReviewerText;

  /// No description provided for @memberPromptPresetResearcher.
  ///
  /// In en, this message translates to:
  /// **'Researcher'**
  String get memberPromptPresetResearcher;

  /// No description provided for @memberPromptPresetResearcherText.
  ///
  /// In en, this message translates to:
  /// **'Investigate and report only; do not change production code unless asked.\nOutput findings with file paths, relevant symbols, and recommended next steps.'**
  String get memberPromptPresetResearcherText;

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select a model'**
  String get selectModel;

  /// No description provided for @memberOfficialClaudeModelHint.
  ///
  /// In en, this message translates to:
  /// **'Uses your Claude account default model. Manage Official login in Providers settings.'**
  String get memberOfficialClaudeModelHint;

  /// No description provided for @editMemberSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit provider, model, agent, and command arguments.'**
  String get editMemberSubtitle;

  /// No description provided for @teamLeadNameRequired.
  ///
  /// In en, this message translates to:
  /// **'FlashskyAI team delegation expects this member to be named exactly team-lead.'**
  String get teamLeadNameRequired;

  /// No description provided for @teamLeadNotice.
  ///
  /// In en, this message translates to:
  /// **'FlashskyAI team delegation expects this member to be named exactly team-lead.'**
  String get teamLeadNotice;

  /// No description provided for @membersAndFileTree.
  ///
  /// In en, this message translates to:
  /// **'Members and File Tree'**
  String get membersAndFileTree;

  /// No description provided for @membersAndFileTreeDescription.
  ///
  /// In en, this message translates to:
  /// **'Show members and file tree stacked or as tabs.'**
  String get membersAndFileTreeDescription;

  /// No description provided for @appProviderCatalogLabel.
  ///
  /// In en, this message translates to:
  /// **'App provider catalog'**
  String get appProviderCatalogLabel;

  /// No description provided for @appProviderCatalogHint.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot stores unified providers here; team launches generate per-tool configs.'**
  String get appProviderCatalogHint;

  /// No description provided for @appProviderPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get appProviderPresetLabel;

  /// No description provided for @appProviderPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get appProviderPresetCustom;

  /// No description provided for @appProviderClaudeApiFormatAnthropic.
  ///
  /// In en, this message translates to:
  /// **'Anthropic Messages (native)'**
  String get appProviderClaudeApiFormatAnthropic;

  /// No description provided for @appProviderClaudeApiFormatOpenaiChat.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Chat Completions'**
  String get appProviderClaudeApiFormatOpenaiChat;

  /// No description provided for @appProviderClaudeApiFormatOpenaiResponses.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Responses'**
  String get appProviderClaudeApiFormatOpenaiResponses;

  /// No description provided for @appProviderClaudeApiFormatGeminiNative.
  ///
  /// In en, this message translates to:
  /// **'Gemini Native'**
  String get appProviderClaudeApiFormatGeminiNative;

  /// No description provided for @appProviderClaudeAuthTokenDefault.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_AUTH_TOKEN (default)'**
  String get appProviderClaudeAuthTokenDefault;

  /// No description provided for @appProviderClaudeAuthApiKey.
  ///
  /// In en, this message translates to:
  /// **'ANTHROPIC_API_KEY'**
  String get appProviderClaudeAuthApiKey;

  /// No description provided for @appProviderAdvancedJson.
  ///
  /// In en, this message translates to:
  /// **'Advanced JSON editor'**
  String get appProviderAdvancedJson;

  /// No description provided for @appProviderAdvancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get appProviderAdvancedOptions;

  /// No description provided for @appProviderWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get appProviderWebsite;

  /// No description provided for @appProviderEnabledTools.
  ///
  /// In en, this message translates to:
  /// **'Enabled tools'**
  String get appProviderEnabledTools;

  /// No description provided for @appProviderToolFlashskyai.
  ///
  /// In en, this message translates to:
  /// **'FlashskyAI'**
  String get appProviderToolFlashskyai;

  /// No description provided for @appProviderToolCodex.
  ///
  /// In en, this message translates to:
  /// **'Codex'**
  String get appProviderToolCodex;

  /// No description provided for @appProviderToolClaude.
  ///
  /// In en, this message translates to:
  /// **'Claude Code'**
  String get appProviderToolClaude;

  /// No description provided for @appProviderTeamToolSection.
  ///
  /// In en, this message translates to:
  /// **'Tool providers for this team'**
  String get appProviderTeamToolSection;

  /// No description provided for @appProviderTeamToolSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select which unified provider each tool uses when this team starts.'**
  String get appProviderTeamToolSubtitle;

  /// No description provided for @appProviderTeamNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get appProviderTeamNone;

  /// No description provided for @appProviderClaudeApiFormat.
  ///
  /// In en, this message translates to:
  /// **'API format'**
  String get appProviderClaudeApiFormat;

  /// No description provided for @appProviderClaudeApiFormatHint.
  ///
  /// In en, this message translates to:
  /// **'Select the provider API input format.'**
  String get appProviderClaudeApiFormatHint;

  /// No description provided for @appProviderClaudeAuthField.
  ///
  /// In en, this message translates to:
  /// **'Authentication field'**
  String get appProviderClaudeAuthField;

  /// No description provided for @appProviderClaudeAuthFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Select the authentication environment variable written to settings.'**
  String get appProviderClaudeAuthFieldHint;

  /// No description provided for @appProviderClaudeModelMapping.
  ///
  /// In en, this message translates to:
  /// **'Model mapping'**
  String get appProviderClaudeModelMapping;

  /// No description provided for @appProviderClaudeModelMappingHint.
  ///
  /// In en, this message translates to:
  /// **'Leave these empty for native Claude providers. Fill them only when a provider maps Claude model roles to different model names.'**
  String get appProviderClaudeModelMappingHint;

  /// No description provided for @appProviderClaudeHaikuModel.
  ///
  /// In en, this message translates to:
  /// **'Haiku default model'**
  String get appProviderClaudeHaikuModel;

  /// No description provided for @appProviderClaudeSonnetModel.
  ///
  /// In en, this message translates to:
  /// **'Sonnet default model'**
  String get appProviderClaudeSonnetModel;

  /// No description provided for @appProviderClaudeOpusModel.
  ///
  /// In en, this message translates to:
  /// **'Opus default model'**
  String get appProviderClaudeOpusModel;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @defaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get defaultModel;

  /// No description provided for @editProvider.
  ///
  /// In en, this message translates to:
  /// **'Edit provider'**
  String get editProvider;

  /// No description provided for @invalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON. Fix the syntax and try again.'**
  String get invalidJson;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot version and application updates.'**
  String get aboutPageSubtitle;

  /// No description provided for @aboutGitHub.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get aboutGitHub;

  /// No description provided for @aboutCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get aboutCurrentVersion;

  /// No description provided for @aboutVersionLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get aboutVersionLoading;

  /// No description provided for @appUpdateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get appUpdateCheck;

  /// No description provided for @appUpdateDownloadInstall.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get appUpdateDownloadInstall;

  /// No description provided for @appUpdateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are on the latest version.'**
  String get appUpdateUpToDate;

  /// No description provided for @appUpdateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get appUpdateDownloading;

  /// No description provided for @appUpdateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing update…'**
  String get appUpdateInstalling;

  /// No description provided for @appUpdateViewRelease.
  ///
  /// In en, this message translates to:
  /// **'View release on GitHub'**
  String get appUpdateViewRelease;

  /// No description provided for @appUpdateViewReleases.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get appUpdateViewReleases;

  /// No description provided for @appUpdateNewVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} available'**
  String appUpdateNewVersion(String version);

  /// No description provided for @appUpdateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get appUpdateDialogTitle;

  /// No description provided for @appUpdateLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest version'**
  String get appUpdateLatestVersion;

  /// No description provided for @appUpdateUnknownVersion.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get appUpdateUnknownVersion;

  /// No description provided for @appUpdateChangelogTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get appUpdateChangelogTitle;

  /// No description provided for @appUpdateChangelogDefaultSection.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get appUpdateChangelogDefaultSection;

  /// No description provided for @appUpdateReadyToDownload.
  ///
  /// In en, this message translates to:
  /// **'Ready to download'**
  String get appUpdateReadyToDownload;

  /// No description provided for @appUpdateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get appUpdateLater;

  /// No description provided for @appUpdateDownloadNow.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get appUpdateDownloadNow;

  /// No description provided for @appUpdateDownloadInBackground.
  ///
  /// In en, this message translates to:
  /// **'Download in background'**
  String get appUpdateDownloadInBackground;

  /// No description provided for @appUpdateInstallNow.
  ///
  /// In en, this message translates to:
  /// **'Install now'**
  String get appUpdateInstallNow;

  /// No description provided for @appUpdateBrowserDownload.
  ///
  /// In en, this message translates to:
  /// **'Download in browser'**
  String get appUpdateBrowserDownload;

  /// No description provided for @appUpdateInvalidPackagePath.
  ///
  /// In en, this message translates to:
  /// **'Invalid package path'**
  String get appUpdateInvalidPackagePath;

  /// No description provided for @appUpdateReleaseBuildRequired.
  ///
  /// In en, this message translates to:
  /// **'Use a release build for in-app installation'**
  String get appUpdateReleaseBuildRequired;

  /// No description provided for @appUpdatePackagePlatformMismatch.
  ///
  /// In en, this message translates to:
  /// **'Package type does not match this system'**
  String get appUpdatePackagePlatformMismatch;

  /// No description provided for @appUpdateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Install failed: {message}'**
  String appUpdateInstallFailed(String message);

  /// No description provided for @appUpdateInstallNoResult.
  ///
  /// In en, this message translates to:
  /// **'Install returned no result'**
  String get appUpdateInstallNoResult;

  /// No description provided for @appUpdateInstallComplete.
  ///
  /// In en, this message translates to:
  /// **'Installation complete'**
  String get appUpdateInstallComplete;

  /// No description provided for @appUpdateRedirectBrowserOnly.
  ///
  /// In en, this message translates to:
  /// **'This link must be downloaded in the browser'**
  String get appUpdateRedirectBrowserOnly;

  /// No description provided for @appUpdateDownloadStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting download…'**
  String get appUpdateDownloadStarting;

  /// No description provided for @appUpdateDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get appUpdateDownloadComplete;

  /// No description provided for @appUpdateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get appUpdateDownloadFailed;

  /// No description provided for @appUpdateDownloadError.
  ///
  /// In en, this message translates to:
  /// **'Error while downloading: {error}'**
  String appUpdateDownloadError(String error);

  /// No description provided for @appUpdateResolvingDownloadUrl.
  ///
  /// In en, this message translates to:
  /// **'Resolving download link…'**
  String get appUpdateResolvingDownloadUrl;

  /// No description provided for @appUpdateBrowserOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened download link in the browser'**
  String get appUpdateBrowserOpened;

  /// No description provided for @appUpdateCannotOpenDownloadLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open download link'**
  String get appUpdateCannotOpenDownloadLink;

  /// No description provided for @appUpdateBrowserOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open browser: {error}'**
  String appUpdateBrowserOpenFailed(String error);

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'First-time setup'**
  String get onboardingTitle;

  /// No description provided for @onboardingProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingProgress(int current, int total);

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get onboardingPrevious;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingStepAppearance.
  ///
  /// In en, this message translates to:
  /// **'Language & theme'**
  String get onboardingStepAppearance;

  /// No description provided for @onboardingStepSsh.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get onboardingStepSsh;

  /// No description provided for @onboardingStepCli.
  ///
  /// In en, this message translates to:
  /// **'Claude Code CLI'**
  String get onboardingStepCli;

  /// No description provided for @onboardingStepProviderImport.
  ///
  /// In en, this message translates to:
  /// **'Import providers'**
  String get onboardingStepProviderImport;

  /// No description provided for @onboardingStepDefaultProvider.
  ///
  /// In en, this message translates to:
  /// **'Default provider'**
  String get onboardingStepDefaultProvider;

  /// No description provided for @onboardingAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language and appearance'**
  String get onboardingAppearanceTitle;

  /// No description provided for @onboardingAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can change these later in Settings → Layout.'**
  String get onboardingAppearanceSubtitle;

  /// No description provided for @onboardingSshTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure SSH connection'**
  String get onboardingSshTitle;

  /// No description provided for @onboardingSshSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Android runs Claude Code on a remote host over SSH.'**
  String get onboardingSshSubtitle;

  /// No description provided for @onboardingCliTitle.
  ///
  /// In en, this message translates to:
  /// **'Detect Claude Code CLI'**
  String get onboardingCliTitle;

  /// No description provided for @onboardingCliSubtitle.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot needs the Claude Code executable to start sessions.'**
  String get onboardingCliSubtitle;

  /// No description provided for @onboardingCliFound.
  ///
  /// In en, this message translates to:
  /// **'CLI found'**
  String get onboardingCliFound;

  /// No description provided for @onboardingCliNotFound.
  ///
  /// In en, this message translates to:
  /// **'CLI not detected on PATH'**
  String get onboardingCliNotFound;

  /// No description provided for @onboardingCliRedetect.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get onboardingCliRedetect;

  /// No description provided for @onboardingProviderImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Claude providers'**
  String get onboardingProviderImportTitle;

  /// No description provided for @onboardingProviderImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan ~/.claude settings and cc-switch for existing provider configs.'**
  String get onboardingProviderImportSubtitle;

  /// No description provided for @onboardingProviderImportResults.
  ///
  /// In en, this message translates to:
  /// **'Import results'**
  String get onboardingProviderImportResults;

  /// No description provided for @onboardingProviderImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Claude providers detected. You can configure them later in Settings.'**
  String get onboardingProviderImportEmpty;

  /// No description provided for @onboardingProviderImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get onboardingProviderImportFailed;

  /// No description provided for @onboardingProviderImportRescan.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get onboardingProviderImportRescan;

  /// No description provided for @onboardingDefaultProviderTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose default Claude provider'**
  String get onboardingDefaultProviderTitle;

  /// No description provided for @onboardingDefaultProviderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'New sessions will use this provider and default model.'**
  String get onboardingDefaultProviderSubtitle;

  /// No description provided for @onboardingDefaultProviderEmpty.
  ///
  /// In en, this message translates to:
  /// **'No providers to choose from. Skip this step or add providers in Settings.'**
  String get onboardingDefaultProviderEmpty;

  /// No description provided for @onboardingDefaultProviderPick.
  ///
  /// In en, this message translates to:
  /// **'Select the default Claude Code provider'**
  String get onboardingDefaultProviderPick;

  /// No description provided for @onboardingDefaultProviderModelHint.
  ///
  /// In en, this message translates to:
  /// **'Primary model id for this provider'**
  String get onboardingDefaultProviderModelHint;

  /// No description provided for @onboardingRerunSetup.
  ///
  /// In en, this message translates to:
  /// **'Run setup wizard again'**
  String get onboardingRerunSetup;

  /// No description provided for @logViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logViewerTitle;

  /// No description provided for @logViewerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Application and error logs under your TeamPilot app data folder.'**
  String get logViewerSubtitle;

  /// No description provided for @logViewerFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Log file'**
  String get logViewerFileLabel;

  /// No description provided for @logViewerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search logs…'**
  String get logViewerSearchHint;

  /// No description provided for @logViewerFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get logViewerFilterTitle;

  /// No description provided for @logViewerFilterLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get logViewerFilterLevel;

  /// No description provided for @logViewerWrapLines.
  ///
  /// In en, this message translates to:
  /// **'Wrap lines'**
  String get logViewerWrapLines;

  /// No description provided for @logViewerReverseOrder.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get logViewerReverseOrder;

  /// No description provided for @logViewerCompactView.
  ///
  /// In en, this message translates to:
  /// **'Compact view'**
  String get logViewerCompactView;

  /// No description provided for @logViewerLineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String logViewerLineCount(int count);

  /// No description provided for @logViewerActionsMenu.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get logViewerActionsMenu;

  /// No description provided for @logViewerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get logViewerRefresh;

  /// No description provided for @logViewerCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy log path'**
  String get logViewerCopyPath;

  /// No description provided for @logViewerClearOld.
  ///
  /// In en, this message translates to:
  /// **'Remove old logs'**
  String get logViewerClearOld;

  /// No description provided for @logViewerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No log files yet'**
  String get logViewerEmpty;

  /// No description provided for @logViewerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Logs are created while the app runs.'**
  String get logViewerEmptyHint;

  /// No description provided for @logViewerPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Logs not on disk yet'**
  String get logViewerPendingTitle;

  /// No description provided for @logViewerPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Buffered entries waiting for file logging:'**
  String get logViewerPendingBody;

  /// No description provided for @logViewerLoadFilesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to list logs: {error}'**
  String logViewerLoadFilesFailed(String error);

  /// No description provided for @logViewerReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to read log: {error}'**
  String logViewerReadFailed(String error);

  /// No description provided for @logViewerClearDone.
  ///
  /// In en, this message translates to:
  /// **'Old log files removed'**
  String get logViewerClearDone;

  /// No description provided for @logViewerClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed: {error}'**
  String logViewerClearFailed(String error);

  /// No description provided for @logViewerPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied path: {name}'**
  String logViewerPathCopied(String name);

  /// No description provided for @initErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Startup failed'**
  String get initErrorTitle;

  /// No description provided for @initErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Error details'**
  String get initErrorDetails;

  /// No description provided for @initErrorStackTrace.
  ///
  /// In en, this message translates to:
  /// **'Stack trace'**
  String get initErrorStackTrace;

  /// No description provided for @initErrorPendingLogs.
  ///
  /// In en, this message translates to:
  /// **'Pending logs'**
  String get initErrorPendingLogs;

  /// No description provided for @initErrorViewLogs.
  ///
  /// In en, this message translates to:
  /// **'View logs'**
  String get initErrorViewLogs;

  /// No description provided for @initErrorCopyReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get initErrorCopyReport;

  /// No description provided for @initErrorCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get initErrorCopy;

  /// No description provided for @initErrorCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get initErrorCopied;

  /// No description provided for @initErrorStackEmpty.
  ///
  /// In en, this message translates to:
  /// **'Stack trace is empty.'**
  String get initErrorStackEmpty;

  /// No description provided for @initErrorVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String initErrorVersion(String version, String build);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
