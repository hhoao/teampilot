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
  /// **'Show the workspace file tree for quick navigation.'**
  String get visibilityFileTreeHint;

  /// No description provided for @visibilityGitHint.
  ///
  /// In en, this message translates to:
  /// **'Show the source control panel for the current repository.'**
  String get visibilityGitHint;

  /// No description provided for @extensionsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get extensionsSettingsTitle;

  /// No description provided for @extensionsSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Install and enable external tools that augment your agents.'**
  String get extensionsSettingsDescription;

  /// No description provided for @extensionsNavInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get extensionsNavInstalled;

  /// No description provided for @extensionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No extensions available'**
  String get extensionsEmptyTitle;

  /// No description provided for @extensionsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Extensions will appear here once the catalog loads.'**
  String get extensionsEmptyHint;

  /// No description provided for @extensionEnableLabel.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get extensionEnableLabel;

  /// No description provided for @extensionInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get extensionInstall;

  /// No description provided for @extensionUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get extensionUninstall;

  /// No description provided for @extensionInstallGuide.
  ///
  /// In en, this message translates to:
  /// **'Install guide'**
  String get extensionInstallGuide;

  /// No description provided for @extensionStatusNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get extensionStatusNotInstalled;

  /// No description provided for @extensionStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get extensionStatusReady;

  /// No description provided for @extensionStatusReadyVersion.
  ///
  /// In en, this message translates to:
  /// **'Ready ({version})'**
  String extensionStatusReadyVersion(String version);

  /// No description provided for @extensionStatusDependencyMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing dependency'**
  String get extensionStatusDependencyMissing;

  /// No description provided for @extensionStatusDependencyMissingNamed.
  ///
  /// In en, this message translates to:
  /// **'Missing: {deps}'**
  String extensionStatusDependencyMissingNamed(String deps);

  /// No description provided for @extensionDependencyMissingHint.
  ///
  /// In en, this message translates to:
  /// **'Needs {deps} on your PATH. Install it, then re-check.'**
  String extensionDependencyMissingHint(String deps);

  /// No description provided for @extensionCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get extensionCopyCommand;

  /// No description provided for @extensionCommandCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied to clipboard'**
  String get extensionCommandCopied;

  /// No description provided for @extensionRecheck.
  ///
  /// In en, this message translates to:
  /// **'Re-check'**
  String get extensionRecheck;

  /// No description provided for @extensionStatusVersionTooOld.
  ///
  /// In en, this message translates to:
  /// **'Installed version is too old'**
  String get extensionStatusVersionTooOld;

  /// No description provided for @extensionKindMcpServer.
  ///
  /// In en, this message translates to:
  /// **'Code intelligence (MCP)'**
  String get extensionKindMcpServer;

  /// No description provided for @extensionKindSettingsHook.
  ///
  /// In en, this message translates to:
  /// **'Token savings (hook)'**
  String get extensionKindSettingsHook;

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

  /// No description provided for @typographyScaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get typographyScaleTitle;

  /// No description provided for @typographyScaleDescription.
  ///
  /// In en, this message translates to:
  /// **'Size of UI text. Standard follows your system; does not change icons or spacing.'**
  String get typographyScaleDescription;

  /// No description provided for @typographyScaleCompact.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get typographyScaleCompact;

  /// No description provided for @typographyScaleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get typographyScaleStandard;

  /// No description provided for @typographyScaleComfortable.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get typographyScaleComfortable;

  /// No description provided for @typographyScaleCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get typographyScaleCustom;

  /// No description provided for @typographyScaleCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get typographyScaleCustomLabel;

  /// No description provided for @typographyScaleCustomHint.
  ///
  /// In en, this message translates to:
  /// **'50–200'**
  String get typographyScaleCustomHint;

  /// No description provided for @uiZoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Interface zoom'**
  String get uiZoomTitle;

  /// No description provided for @uiZoomDescription.
  ///
  /// In en, this message translates to:
  /// **'Zoom the whole UI together — text, icons, and spacing. Standard follows your display scaling.'**
  String get uiZoomDescription;

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

  /// No description provided for @workspaceEntryModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Startup view'**
  String get workspaceEntryModeTitle;

  /// No description provided for @workspaceEntryModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Where the app opens after launch.'**
  String get workspaceEntryModeDescription;

  /// No description provided for @workspaceEntryModeHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get workspaceEntryModeHome;

  /// No description provided for @workspaceEntryModeLastWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Last workspace'**
  String get workspaceEntryModeLastWorkspace;

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

  /// No description provided for @sourceControl.
  ///
  /// In en, this message translates to:
  /// **'Source Control'**
  String get sourceControl;

  /// No description provided for @gitStagedChanges.
  ///
  /// In en, this message translates to:
  /// **'Staged Changes'**
  String get gitStagedChanges;

  /// No description provided for @gitChanges.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get gitChanges;

  /// No description provided for @gitNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get gitNoChanges;

  /// No description provided for @gitNotARepository.
  ///
  /// In en, this message translates to:
  /// **'This folder is not a Git repository'**
  String get gitNotARepository;

  /// No description provided for @gitNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Git was not found. Install Git to use source control.'**
  String get gitNotInstalled;

  /// No description provided for @gitCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get gitCommit;

  /// No description provided for @gitCommitMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Message (commit to \"{branch}\")'**
  String gitCommitMessageHint(String branch);

  /// No description provided for @gitStage.
  ///
  /// In en, this message translates to:
  /// **'Stage changes'**
  String get gitStage;

  /// No description provided for @gitUnstage.
  ///
  /// In en, this message translates to:
  /// **'Unstage changes'**
  String get gitUnstage;

  /// No description provided for @gitStageAll.
  ///
  /// In en, this message translates to:
  /// **'Stage all changes'**
  String get gitStageAll;

  /// No description provided for @gitUnstageAll.
  ///
  /// In en, this message translates to:
  /// **'Unstage all changes'**
  String get gitUnstageAll;

  /// No description provided for @gitStageFolder.
  ///
  /// In en, this message translates to:
  /// **'Stage changes in folder'**
  String get gitStageFolder;

  /// No description provided for @gitUnstageFolder.
  ///
  /// In en, this message translates to:
  /// **'Unstage changes in folder'**
  String get gitUnstageFolder;

  /// No description provided for @treeExpandAllFolders.
  ///
  /// In en, this message translates to:
  /// **'Expand all folders'**
  String get treeExpandAllFolders;

  /// No description provided for @treeCollapseAllFolders.
  ///
  /// In en, this message translates to:
  /// **'Collapse all folders'**
  String get treeCollapseAllFolders;

  /// No description provided for @gitDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get gitDiscard;

  /// No description provided for @gitDiscardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get gitDiscardConfirmTitle;

  /// No description provided for @gitDiscardConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Discard all changes in {path}? This cannot be undone.'**
  String gitDiscardConfirmBody(String path);

  /// No description provided for @gitPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get gitPush;

  /// No description provided for @gitPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get gitPull;

  /// No description provided for @gitRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get gitRefresh;

  /// No description provided for @gitChangesListView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get gitChangesListView;

  /// No description provided for @gitChangesTreeView.
  ///
  /// In en, this message translates to:
  /// **'Tree view'**
  String get gitChangesTreeView;

  /// No description provided for @gitSwitchBranch.
  ///
  /// In en, this message translates to:
  /// **'Switch branch'**
  String get gitSwitchBranch;

  /// No description provided for @gitCreateBranch.
  ///
  /// In en, this message translates to:
  /// **'Create branch'**
  String get gitCreateBranch;

  /// No description provided for @gitNewBranchHint.
  ///
  /// In en, this message translates to:
  /// **'New branch name'**
  String get gitNewBranchHint;

  /// No description provided for @gitError.
  ///
  /// In en, this message translates to:
  /// **'Git: {message}'**
  String gitError(String message);

  /// No description provided for @gitAheadBehind.
  ///
  /// In en, this message translates to:
  /// **'↑{ahead} ↓{behind}'**
  String gitAheadBehind(int ahead, int behind);

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

  /// No description provided for @memberPresenceOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get memberPresenceOffline;

  /// No description provided for @memberPresenceConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get memberPresenceConnecting;

  /// No description provided for @memberPresenceIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get memberPresenceIdle;

  /// No description provided for @memberPresenceWorking.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get memberPresenceWorking;

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

  /// No description provided for @teamModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Team mode'**
  String get teamModeLabel;

  /// No description provided for @teamModeNative.
  ///
  /// In en, this message translates to:
  /// **'Native (single CLI)'**
  String get teamModeNative;

  /// No description provided for @teamModeMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed (cross-CLI bus)'**
  String get teamModeMixed;

  /// No description provided for @memberCliInheritHint.
  ///
  /// In en, this message translates to:
  /// **'Inherit team default'**
  String get memberCliInheritHint;

  /// No description provided for @memberLaunchConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Model settings'**
  String get memberLaunchConfigTitle;

  /// No description provided for @memberLaunchConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'CLI backend, provider, model, and effort for this member.'**
  String get memberLaunchConfigSubtitle;

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

  /// No description provided for @workspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspaces;

  /// No description provided for @newWorkspace.
  ///
  /// In en, this message translates to:
  /// **'New Workspace'**
  String get newWorkspace;

  /// No description provided for @homeWorkspaceMainWindow.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get homeWorkspaceMainWindow;

  /// No description provided for @windowControlMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowControlMinimize;

  /// No description provided for @windowControlMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowControlMaximize;

  /// No description provided for @windowControlRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowControlRestore;

  /// No description provided for @windowControlClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowControlClose;

  /// No description provided for @windowControlAlwaysOnTop.
  ///
  /// In en, this message translates to:
  /// **'Always on top'**
  String get windowControlAlwaysOnTop;

  /// No description provided for @homeWorkspaceMyFavorites.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get homeWorkspaceMyFavorites;

  /// No description provided for @homeWorkspaceRecentVisits.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeWorkspaceRecentVisits;

  /// No description provided for @homeWorkspacePersonal.
  ///
  /// In en, this message translates to:
  /// **'Simple mode'**
  String get homeWorkspacePersonal;

  /// No description provided for @homeWorkspaceAllWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'All workspaces'**
  String get homeWorkspaceAllWorkspaces;

  /// Short personal-workspace label in title-bar tab tooltips.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get homeWorkspaceWorkspaceTabKindPersonal;

  /// Name shown for the built-in personal workspace in simple mode.
  ///
  /// In en, this message translates to:
  /// **'Personal assistant'**
  String get homeWorkspaceDefaultPersonalWorkspaceName;

  /// Name shown for the built-in default team created on first launch.
  ///
  /// In en, this message translates to:
  /// **'Default Team'**
  String get homeWorkspaceDefaultTeamName;

  /// No description provided for @homeWorkspacePersonalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Skip the team setup — just launch a single CLI and start chatting.'**
  String get homeWorkspacePersonalSubtitle;

  /// No description provided for @homeWorkspaceNoData.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get homeWorkspaceNoData;

  /// No description provided for @homeWorkspaceRecentlyClosed.
  ///
  /// In en, this message translates to:
  /// **'Recently closed'**
  String get homeWorkspaceRecentlyClosed;

  /// No description provided for @homeWorkspaceRecentlyClosedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recently closed workspaces'**
  String get homeWorkspaceRecentlyClosedEmpty;

  /// No description provided for @homeWorkspaceMyTeams.
  ///
  /// In en, this message translates to:
  /// **'My Teams'**
  String get homeWorkspaceMyTeams;

  /// No description provided for @homeWorkspaceNewTeam.
  ///
  /// In en, this message translates to:
  /// **'New Team'**
  String get homeWorkspaceNewTeam;

  /// No description provided for @homeWorkspaceProviders.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get homeWorkspaceProviders;

  /// No description provided for @homeWorkspaceTeamWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get homeWorkspaceTeamWorkspaces;

  /// No description provided for @homeWorkspaceOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get homeWorkspaceOwner;

  /// No description provided for @homeWorkspaceImportWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get homeWorkspaceImportWorkspace;

  /// No description provided for @homeWorkspaceSessionsLabel.
  ///
  /// In en, this message translates to:
  /// **'sessions'**
  String get homeWorkspaceSessionsLabel;

  /// No description provided for @homeWorkspaceEmptyWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'No workspaces in this team yet'**
  String get homeWorkspaceEmptyWorkspaces;

  /// No description provided for @homeWorkspaceEmptyWorkspacesHint.
  ///
  /// In en, this message translates to:
  /// **'Create or import a workspace to get started'**
  String get homeWorkspaceEmptyWorkspacesHint;

  /// No description provided for @homeWorkspaceWorkspaceSort.
  ///
  /// In en, this message translates to:
  /// **'Sort workspaces'**
  String get homeWorkspaceWorkspaceSort;

  /// No description provided for @homeWorkspaceWorkspaceSortRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get homeWorkspaceWorkspaceSortRecentlyUpdated;

  /// No description provided for @homeWorkspaceWorkspaceSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name (A–Z)'**
  String get homeWorkspaceWorkspaceSortNameAsc;

  /// No description provided for @homeWorkspaceWorkspaceSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name (Z–A)'**
  String get homeWorkspaceWorkspaceSortNameDesc;

  /// No description provided for @homeWorkspaceWorkspaceSortCreatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get homeWorkspaceWorkspaceSortCreatedDesc;

  /// No description provided for @homeWorkspaceWorkspaceSortSessionCountDesc.
  ///
  /// In en, this message translates to:
  /// **'Session count'**
  String get homeWorkspaceWorkspaceSortSessionCountDesc;

  /// No description provided for @homeWorkspaceComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get homeWorkspaceComingSoon;

  /// No description provided for @homeWorkspaceNewTeamSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick how the team collaborates, then name it.'**
  String get homeWorkspaceNewTeamSubtitle;

  /// No description provided for @homeWorkspaceNewTeamMethodCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get homeWorkspaceNewTeamMethodCustom;

  /// No description provided for @homeWorkspaceNewTeamMethodAi.
  ///
  /// In en, this message translates to:
  /// **'AI generate'**
  String get homeWorkspaceNewTeamMethodAi;

  /// No description provided for @homeWorkspaceNewTeamMethodSolo.
  ///
  /// In en, this message translates to:
  /// **'Solo'**
  String get homeWorkspaceNewTeamMethodSolo;

  /// No description provided for @homeWorkspaceNewTeamSubtitleAi.
  ///
  /// In en, this message translates to:
  /// **'Describe your team and generate a draft with AI.'**
  String get homeWorkspaceNewTeamSubtitleAi;

  /// No description provided for @homeWorkspaceNewTeamSubtitleSolo.
  ///
  /// In en, this message translates to:
  /// **'Simple single-CLI chat — switch CLI, model, and provider freely.'**
  String get homeWorkspaceNewTeamSubtitleSolo;

  /// No description provided for @homeWorkspaceNewSoloNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a team name'**
  String get homeWorkspaceNewSoloNameHint;

  /// No description provided for @homeWorkspaceCreateSolo.
  ///
  /// In en, this message translates to:
  /// **'Create solo team'**
  String get homeWorkspaceCreateSolo;

  /// No description provided for @homeWorkspaceNewTeamRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get homeWorkspaceNewTeamRecommended;

  /// No description provided for @homeWorkspaceNewTeamModeBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get homeWorkspaceNewTeamModeBeta;

  /// No description provided for @homeWorkspaceNewTeamNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a team name'**
  String get homeWorkspaceNewTeamNameHint;

  /// No description provided for @homeWorkspaceCreateTeam.
  ///
  /// In en, this message translates to:
  /// **'Create team'**
  String get homeWorkspaceCreateTeam;

  /// No description provided for @teamModeNativeTitle.
  ///
  /// In en, this message translates to:
  /// **'Native mode'**
  String get teamModeNativeTitle;

  /// No description provided for @teamModeMixedTitle.
  ///
  /// In en, this message translates to:
  /// **'Mixed mode'**
  String get teamModeMixedTitle;

  /// No description provided for @teamModeNativeDescription.
  ///
  /// In en, this message translates to:
  /// **'All members share one CLI for native, low-config collaboration.'**
  String get teamModeNativeDescription;

  /// No description provided for @teamModeMixedDescription.
  ///
  /// In en, this message translates to:
  /// **'Members can run different CLIs and collaborate across tools over TeamBus.'**
  String get teamModeMixedDescription;

  /// No description provided for @homeWorkspaceNewWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a working directory and name your workspace.'**
  String get homeWorkspaceNewWorkspaceSubtitle;

  /// No description provided for @homeWorkspaceNewWorkspaceDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspace directory'**
  String get homeWorkspaceNewWorkspaceDirectoryLabel;

  /// No description provided for @homeWorkspaceNewWorkspaceChooseDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get homeWorkspaceNewWorkspaceChooseDirectory;

  /// No description provided for @homeWorkspaceNewWorkspaceDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'No directory selected yet'**
  String get homeWorkspaceNewWorkspaceDirectoryHint;

  /// No description provided for @homeWorkspaceNewWorkspaceNameHint.
  ///
  /// In en, this message translates to:
  /// **'Defaults to the folder name'**
  String get homeWorkspaceNewWorkspaceNameHint;

  /// No description provided for @homeWorkspaceCreateWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Create workspace'**
  String get homeWorkspaceCreateWorkspace;

  /// No description provided for @homeWorkspaceCloseWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Close workspace?'**
  String get homeWorkspaceCloseWorkspaceTitle;

  /// No description provided for @homeWorkspaceCloseWorkspaceMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Closing this tab will end 1 running session in this workspace.} other{Closing this tab will end {count} running sessions in this workspace.}}'**
  String homeWorkspaceCloseWorkspaceMessage(int count);

  /// No description provided for @homeWorkspaceCloseWorkspaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Close & end sessions'**
  String get homeWorkspaceCloseWorkspaceConfirm;

  /// No description provided for @homeWorkspaceWorkspaceManagement.
  ///
  /// In en, this message translates to:
  /// **'Workspace management'**
  String get homeWorkspaceWorkspaceManagement;

  /// No description provided for @homeWorkspaceWorkspaceList.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get homeWorkspaceWorkspaceList;

  /// No description provided for @homeWorkspaceConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get homeWorkspaceConversations;

  /// No description provided for @homeWorkspaceConversationsSection.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get homeWorkspaceConversationsSection;

  /// No description provided for @homeWorkspaceWorkspaceAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get homeWorkspaceWorkspaceAgent;

  /// No description provided for @workspaceAgentBuiltInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maps to flashskyai --agent when that CLI is active.'**
  String get workspaceAgentBuiltInSubtitle;

  /// No description provided for @workspaceAgentExtraArgs.
  ///
  /// In en, this message translates to:
  /// **'Extra CLI arguments'**
  String get workspaceAgentExtraArgs;

  /// No description provided for @workspaceAgentExtraArgsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Extra flags appended when starting the agent in this workspace.'**
  String get workspaceAgentExtraArgsSubtitle;

  /// No description provided for @workspaceWorkbenchAdvancedSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Agent preset and extra CLI flags for this workspace.'**
  String get workspaceWorkbenchAdvancedSettingsSubtitle;

  /// No description provided for @workspaceAgentPromptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System prompt defining the agent\'s role and boundaries in this workspace.'**
  String get workspaceAgentPromptSubtitle;

  /// No description provided for @workspaceAgentPromptPresetGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get workspaceAgentPromptPresetGeneral;

  /// No description provided for @workspaceAgentPromptPresetGeneralText.
  ///
  /// In en, this message translates to:
  /// **'Help with development in this workspace end to end. Understand the request and codebase, propose a clear approach, then implement with minimal diffs; summarize changed files and suggested next steps.'**
  String get workspaceAgentPromptPresetGeneralText;

  /// No description provided for @workspaceAgentPromptPresetDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get workspaceAgentPromptPresetDeveloper;

  /// No description provided for @workspaceAgentPromptPresetDeveloperText.
  ///
  /// In en, this message translates to:
  /// **'Focus on implementation and fixes. Prefer minimal diffs, run relevant tests, and briefly explain changed files and rationale.'**
  String get workspaceAgentPromptPresetDeveloperText;

  /// No description provided for @workspaceAgentPromptPresetReviewer.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get workspaceAgentPromptPresetReviewer;

  /// No description provided for @workspaceAgentPromptPresetReviewerText.
  ///
  /// In en, this message translates to:
  /// **'Review code only; do not modify files unless asked.\nEach finding must include file path, line, issue, and suggested fix.'**
  String get workspaceAgentPromptPresetReviewerText;

  /// No description provided for @workspaceAgentPromptPresetResearcher.
  ///
  /// In en, this message translates to:
  /// **'Researcher'**
  String get workspaceAgentPromptPresetResearcher;

  /// No description provided for @workspaceAgentPromptPresetResearcherText.
  ///
  /// In en, this message translates to:
  /// **'Investigate and report only; do not change production code unless asked.\nOutput findings with file paths, relevant symbols, and recommended next steps.'**
  String get workspaceAgentPromptPresetResearcherText;

  /// No description provided for @workspaceCliEffortInheritHint.
  ///
  /// In en, this message translates to:
  /// **'Use provider default'**
  String get workspaceCliEffortInheritHint;

  /// No description provided for @workspaceCliDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default CLI for new conversations in this workspace.'**
  String get workspaceCliDefaultSubtitle;

  /// No description provided for @workspaceCliDefaultsTitle.
  ///
  /// In en, this message translates to:
  /// **'CLI defaults'**
  String get workspaceCliDefaultsTitle;

  /// No description provided for @workspaceCliDefaultsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set the default provider and model for each CLI used in this workspace.'**
  String get workspaceCliDefaultsSubtitle;

  /// No description provided for @workspaceCliProviderModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Provider & model'**
  String get workspaceCliProviderModelTitle;

  /// No description provided for @workspaceCliEffortLevel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get workspaceCliEffortLevel;

  /// No description provided for @workspaceCliEffortLevelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default effort for this CLI in the workspace (leave empty to use provider default).'**
  String get workspaceCliEffortLevelSubtitle;

  /// No description provided for @workspaceCliConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get workspaceCliConfigure;

  /// No description provided for @workspaceCliConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get workspaceCliConfigured;

  /// No description provided for @workspaceCliNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get workspaceCliNotConfigured;

  /// No description provided for @workspaceCliNotConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'No default provider selected yet'**
  String get workspaceCliNotConfiguredHint;

  /// No description provided for @workspaceCliNoProviderCatalog.
  ///
  /// In en, this message translates to:
  /// **'No provider setup required for this CLI'**
  String get workspaceCliNoProviderCatalog;

  /// No description provided for @workspaceCliConfigSummary.
  ///
  /// In en, this message translates to:
  /// **'{provider} · {model}'**
  String workspaceCliConfigSummary(String provider, String model);

  /// No description provided for @workspaceCliAddPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Preset'**
  String get workspaceCliAddPresetTitle;

  /// No description provided for @workspaceCliEditPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Preset'**
  String get workspaceCliEditPresetTitle;

  /// No description provided for @workspaceCliPresetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset Name'**
  String get workspaceCliPresetNameLabel;

  /// No description provided for @workspaceCliPresetsManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Presets'**
  String get workspaceCliPresetsManageTitle;

  /// No description provided for @workspaceCliPresetsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No presets yet. Create one to get started.'**
  String get workspaceCliPresetsEmptyHint;

  /// No description provided for @workspaceCliDeletePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Preset'**
  String get workspaceCliDeletePresetTitle;

  /// No description provided for @workspaceCliDeletePresetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete preset \'{name}\'? This cannot be undone.'**
  String workspaceCliDeletePresetConfirm(String name);

  /// No description provided for @workspaceCliPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Active Preset'**
  String get workspaceCliPresetLabel;

  /// No description provided for @workspaceCliNoPresetHint.
  ///
  /// In en, this message translates to:
  /// **'No preset selected'**
  String get workspaceCliNoPresetHint;

  /// No description provided for @workspaceCliManagePresets.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get workspaceCliManagePresets;

  /// No description provided for @teamDefaultPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Default Model Preset'**
  String get teamDefaultPresetLabel;

  /// No description provided for @teamDefaultPresetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional default preset applied to members that don\'t override it.'**
  String get teamDefaultPresetSubtitle;

  /// No description provided for @teamDefaultPresetNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get teamDefaultPresetNone;

  /// No description provided for @teamDefaultPresetChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get teamDefaultPresetChange;

  /// No description provided for @teamDefaultPresetManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get teamDefaultPresetManage;

  /// No description provided for @teamDefaultCliMixedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a member has no CLI override.'**
  String get teamDefaultCliMixedSubtitle;

  /// No description provided for @teamDefaultDialogEffortSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Team default effort.'**
  String get teamDefaultDialogEffortSubtitle;

  /// No description provided for @presetPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Preset'**
  String get presetPickerTitle;

  /// No description provided for @presetPickerNoneOption.
  ///
  /// In en, this message translates to:
  /// **'None (no default)'**
  String get presetPickerNoneOption;

  /// No description provided for @memberPresetLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get memberPresetLabel;

  /// No description provided for @memberLaunchConfigTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Configuration type'**
  String get memberLaunchConfigTypeLabel;

  /// No description provided for @memberLaunchConfigTypePreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get memberLaunchConfigTypePreset;

  /// No description provided for @memberLaunchConfigInheritHint.
  ///
  /// In en, this message translates to:
  /// **'Uses the team\'s default CLI, provider, model, and effort.'**
  String get memberLaunchConfigInheritHint;

  /// No description provided for @memberLaunchConfigInheritUnset.
  ///
  /// In en, this message translates to:
  /// **'Team default is not configured yet.'**
  String get memberLaunchConfigInheritUnset;

  /// No description provided for @memberPresetInheritTeam.
  ///
  /// In en, this message translates to:
  /// **'Inherit team default'**
  String get memberPresetInheritTeam;

  /// No description provided for @memberPresetInheritTeamNone.
  ///
  /// In en, this message translates to:
  /// **'No team default set'**
  String get memberPresetInheritTeamNone;

  /// No description provided for @memberPresetSelectPreset.
  ///
  /// In en, this message translates to:
  /// **'Select a preset'**
  String get memberPresetSelectPreset;

  /// No description provided for @memberPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom configuration'**
  String get memberPresetCustom;

  /// No description provided for @memberPresetViaPreset.
  ///
  /// In en, this message translates to:
  /// **'{presetName} (via preset)'**
  String memberPresetViaPreset(String presetName);

  /// No description provided for @memberPresetViaTeamDefault.
  ///
  /// In en, this message translates to:
  /// **'{presetName} (via team default)'**
  String memberPresetViaTeamDefault(String presetName);

  /// No description provided for @homeWorkspaceWorkspaceSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get homeWorkspaceWorkspaceSkills;

  /// No description provided for @homeWorkspaceWorkspacePlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get homeWorkspaceWorkspacePlugins;

  /// No description provided for @homeWorkspaceWorkspaceMcp.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get homeWorkspaceWorkspaceMcp;

  /// No description provided for @homeWorkspaceWorkspaceExtensions.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get homeWorkspaceWorkspaceExtensions;

  /// No description provided for @workspaceSkillsAssignedCount.
  ///
  /// In en, this message translates to:
  /// **'{assigned} of {total} enabled for this workspace'**
  String workspaceSkillsAssignedCount(int assigned, int total);

  /// No description provided for @workspaceSkillsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage skills'**
  String get workspaceSkillsManage;

  /// No description provided for @workspaceMcpAssignedCount.
  ///
  /// In en, this message translates to:
  /// **'{assigned} of {total} enabled for this workspace'**
  String workspaceMcpAssignedCount(int assigned, int total);

  /// No description provided for @workspaceMcpManage.
  ///
  /// In en, this message translates to:
  /// **'Manage MCP'**
  String get workspaceMcpManage;

  /// No description provided for @workspacePluginsAssignedCount.
  ///
  /// In en, this message translates to:
  /// **'{assigned} of {total} linked to this workspace'**
  String workspacePluginsAssignedCount(int assigned, int total);

  /// No description provided for @workspacePluginsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage plugins'**
  String get workspacePluginsManage;

  /// No description provided for @workspacePluginsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No plugins installed'**
  String get workspacePluginsEmpty;

  /// No description provided for @workspacePluginsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Install plugins from Discovery to enable them for this workspace.'**
  String get workspacePluginsEmptyHint;

  /// No description provided for @workspaceExtensionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions for this workspace'**
  String get workspaceExtensionsTitle;

  /// No description provided for @workspaceExtensionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Override which extensions run for this workspace. Default follows the global setting.'**
  String get workspaceExtensionsSubtitle;

  /// No description provided for @workspaceExtensionEffectiveOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled for this workspace'**
  String get workspaceExtensionEffectiveOn;

  /// No description provided for @workspaceExtensionEffectiveOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled for this workspace'**
  String get workspaceExtensionEffectiveOff;

  /// No description provided for @homeWorkspaceTeamConfig.
  ///
  /// In en, this message translates to:
  /// **'Team config'**
  String get homeWorkspaceTeamConfig;

  /// No description provided for @homeWorkspaceWorkspaceSettings.
  ///
  /// In en, this message translates to:
  /// **'Workspace settings'**
  String get homeWorkspaceWorkspaceSettings;

  /// No description provided for @homeWorkspaceWorkspaceMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get homeWorkspaceWorkspaceMembers;

  /// No description provided for @homeWorkspaceWorkspaceSettingsSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get homeWorkspaceWorkspaceSettingsSectionBasic;

  /// No description provided for @homeWorkspaceWorkspaceSettingsBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get homeWorkspaceWorkspaceSettingsBasicInfo;

  /// No description provided for @homeWorkspaceWorkspaceId.
  ///
  /// In en, this message translates to:
  /// **'Workspace ID'**
  String get homeWorkspaceWorkspaceId;

  /// No description provided for @homeWorkspaceWorkspaceAdditionalDirsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 additional directory} other{{count} additional directories}}'**
  String homeWorkspaceWorkspaceAdditionalDirsCount(int count);

  /// No description provided for @homeWorkspaceWorkspaceSettingsPathsHint.
  ///
  /// In en, this message translates to:
  /// **'Use Manage on additional directories to add or remove folders in this workspace.'**
  String get homeWorkspaceWorkspaceSettingsPathsHint;

  /// No description provided for @deleteWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Deletes this workspace and all conversations in it. This cannot be undone.'**
  String get deleteWorkspaceSubtitle;

  /// No description provided for @homeWorkspaceInviteMembers.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get homeWorkspaceInviteMembers;

  /// No description provided for @homeWorkspaceNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get homeWorkspaceNewConversation;

  /// No description provided for @homeWorkspaceNewConversationChooseCli.
  ///
  /// In en, this message translates to:
  /// **'New conversation with CLI…'**
  String get homeWorkspaceNewConversationChooseCli;

  /// No description provided for @homeWorkspaceNoConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations in this workspace yet'**
  String get homeWorkspaceNoConversations;

  /// No description provided for @homeWorkspaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get homeWorkspaceSearchHint;

  /// No description provided for @homeWorkspaceNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No conversations match your search'**
  String get homeWorkspaceNoSearchResults;

  /// No description provided for @workspaceSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get workspaceSearchTitle;

  /// No description provided for @workspaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search sessions and files'**
  String get workspaceSearchHint;

  /// No description provided for @workspaceSearchFilesSection.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get workspaceSearchFilesSection;

  /// No description provided for @workspaceSearchSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching files…'**
  String get workspaceSearchSearching;

  /// No description provided for @workspaceSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get workspaceSearchNoResults;

  /// No description provided for @workspaceSearchFilesTruncated.
  ///
  /// In en, this message translates to:
  /// **'More files match — refine your search'**
  String get workspaceSearchFilesTruncated;

  /// No description provided for @homeWorkspaceOpenWorkspaceInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in new tab'**
  String get homeWorkspaceOpenWorkspaceInNewTab;

  /// No description provided for @homeWorkspaceOpenInNewTabWithOtherIdentity.
  ///
  /// In en, this message translates to:
  /// **'Open in new tab with other identity…'**
  String get homeWorkspaceOpenInNewTabWithOtherIdentity;

  /// No description provided for @homeWorkspaceFavoriteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Favorite workspace'**
  String get homeWorkspaceFavoriteWorkspace;

  /// No description provided for @homeWorkspaceUnfavoriteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get homeWorkspaceUnfavoriteWorkspace;

  /// No description provided for @homeWorkspaceRenameWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get homeWorkspaceRenameWorkspace;

  /// No description provided for @homeWorkspaceCloneWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Clone workspace'**
  String get homeWorkspaceCloneWorkspace;

  /// No description provided for @homeWorkspaceCloneWorkspaceDisplayName.
  ///
  /// In en, this message translates to:
  /// **'{name} (copy)'**
  String homeWorkspaceCloneWorkspaceDisplayName(Object name);

  /// No description provided for @homeWorkspaceCloneWorkspaceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cloned \"{name}\".'**
  String homeWorkspaceCloneWorkspaceSuccess(Object name);

  /// No description provided for @homeWorkspaceCloneWorkspaceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clone workspace'**
  String get homeWorkspaceCloneWorkspaceFailed;

  /// No description provided for @newWorkspaceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create a workspace'**
  String get newWorkspaceTooltip;

  /// No description provided for @switchWorkspaceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch workspace'**
  String get switchWorkspaceTooltip;

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

  /// No description provided for @workspacePrimaryPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a primary directory first.'**
  String get workspacePrimaryPathRequired;

  /// No description provided for @workspacePrimaryPathNotSelected.
  ///
  /// In en, this message translates to:
  /// **'No primary directory selected'**
  String get workspacePrimaryPathNotSelected;

  /// No description provided for @workspaceDirectoryAdded.
  ///
  /// In en, this message translates to:
  /// **'Directory added to workspace'**
  String get workspaceDirectoryAdded;

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

  /// No description provided for @workspaceDetails.
  ///
  /// In en, this message translates to:
  /// **'Workspace details'**
  String get workspaceDetails;

  /// No description provided for @workspaceDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace Details'**
  String get workspaceDetailsTitle;

  /// No description provided for @addWorkspaceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Add directory'**
  String get addWorkspaceDirectory;

  /// No description provided for @removeWorkspaceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Remove directory'**
  String get removeWorkspaceDirectory;

  /// No description provided for @workspaceDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get workspaceDisplayName;

  /// No description provided for @workspaceIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get workspaceIcon;

  /// No description provided for @workspaceIconPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose workspace icon'**
  String get workspaceIconPickerTitle;

  /// No description provided for @workspaceIconUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get workspaceIconUseDefault;

  /// No description provided for @workspaceIconUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload icon'**
  String get workspaceIconUpload;

  /// No description provided for @workspaceIconUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save icon. Use PNG, JPG, WEBP, or SVG.'**
  String get workspaceIconUploadFailed;

  /// No description provided for @workspacePrimaryPath.
  ///
  /// In en, this message translates to:
  /// **'Primary directory'**
  String get workspacePrimaryPath;

  /// No description provided for @workspaceAdditionalDirectories.
  ///
  /// In en, this message translates to:
  /// **'Additional directories'**
  String get workspaceAdditionalDirectories;

  /// No description provided for @workspaceNoAdditionalDirectories.
  ///
  /// In en, this message translates to:
  /// **'No additional directories'**
  String get workspaceNoAdditionalDirectories;

  /// No description provided for @workspaceSessionCount.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get workspaceSessionCount;

  /// No description provided for @workspaceCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get workspaceCreatedAt;

  /// No description provided for @workspaceUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get workspaceUpdatedAt;

  /// No description provided for @workspaceDirectoryAlreadyPrimary.
  ///
  /// In en, this message translates to:
  /// **'This path is already the primary directory.'**
  String get workspaceDirectoryAlreadyPrimary;

  /// No description provided for @workspaceDirectoryAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'This directory is already in the workspace.'**
  String get workspaceDirectoryAlreadyAdded;

  /// No description provided for @editWorkspacePrimaryPath.
  ///
  /// In en, this message translates to:
  /// **'Edit primary directory'**
  String get editWorkspacePrimaryPath;

  /// No description provided for @remoteDirectoryBrowserTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse remote directory'**
  String get remoteDirectoryBrowserTitle;

  /// No description provided for @remoteDirectoryBrowserUpOneLevel.
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get remoteDirectoryBrowserUpOneLevel;

  /// No description provided for @remoteDirectoryBrowserUseThisDirectory.
  ///
  /// In en, this message translates to:
  /// **'Use this directory'**
  String get remoteDirectoryBrowserUseThisDirectory;

  /// No description provided for @remoteDirectoryBrowserTypePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Or type a path'**
  String get remoteDirectoryBrowserTypePathLabel;

  /// No description provided for @remoteDirectoryBrowserTypePathHint.
  ///
  /// In en, this message translates to:
  /// **'~/work/workspace'**
  String get remoteDirectoryBrowserTypePathHint;

  /// No description provided for @remoteDirectoryBrowserUseTypedPath.
  ///
  /// In en, this message translates to:
  /// **'Use path'**
  String get remoteDirectoryBrowserUseTypedPath;

  /// No description provided for @remoteDirectoryBrowserError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the remote directory. You can still type a path below.'**
  String get remoteDirectoryBrowserError;

  /// No description provided for @remoteDirectoryBrowserEmpty.
  ///
  /// In en, this message translates to:
  /// **'No subdirectories here'**
  String get remoteDirectoryBrowserEmpty;

  /// No description provided for @deleteWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Delete Workspace'**
  String get deleteWorkspace;

  /// No description provided for @deleteWorkspaceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace \"{name}\" and all its sessions? This cannot be undone.'**
  String deleteWorkspaceConfirm(String name);

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

  /// No description provided for @pinConversation.
  ///
  /// In en, this message translates to:
  /// **'Pin conversation'**
  String get pinConversation;

  /// No description provided for @unpinConversation.
  ///
  /// In en, this message translates to:
  /// **'Unpin conversation'**
  String get unpinConversation;

  /// No description provided for @sessionSortManual.
  ///
  /// In en, this message translates to:
  /// **'Manual order'**
  String get sessionSortManual;

  /// No description provided for @sessionSortRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get sessionSortRecentlyUpdated;

  /// No description provided for @sessionSortCreatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get sessionSortCreatedDesc;

  /// No description provided for @sessionSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort conversations'**
  String get sessionSortTooltip;

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
  /// **'Configure shell session launch, terminal behavior, and storage backend.'**
  String get sessionPageSubtitle;

  /// No description provided for @cliConfig.
  ///
  /// In en, this message translates to:
  /// **'CLI'**
  String get cliConfig;

  /// No description provided for @cliConfigPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure AI agent CLI executable paths and install missing tools.'**
  String get cliConfigPageSubtitle;

  /// No description provided for @sshProfilesSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH servers'**
  String get sshProfilesSettingsTitle;

  /// No description provided for @sshProfilesPageTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH remote hosts'**
  String get sshProfilesPageTitle;

  /// No description provided for @sshProfilesPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to existing machines over SSH for files, terminals, Git, and workspaces.'**
  String get sshProfilesPageSubtitle;

  /// No description provided for @sshProfilesTargetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Targets'**
  String get sshProfilesTargetsTitle;

  /// No description provided for @sshProfilesTargetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a remote host to connect from TeamPilot.'**
  String get sshProfilesTargetsSubtitle;

  /// No description provided for @sshProfilesImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get sshProfilesImport;

  /// No description provided for @sshProfilesImportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Import from ~/.ssh/config is not available yet.'**
  String get sshProfilesImportUnavailable;

  /// No description provided for @sshProfilesAddTarget.
  ///
  /// In en, this message translates to:
  /// **'Add target'**
  String get sshProfilesAddTarget;

  /// No description provided for @sshProfilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No SSH targets configured.'**
  String get sshProfilesEmpty;

  /// No description provided for @sshProfileStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get sshProfileStatusDisconnected;

  /// No description provided for @sshProfileStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get sshProfileStatusConnecting;

  /// No description provided for @sshProfileStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get sshProfileStatusConnected;

  /// No description provided for @sshProfileStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get sshProfileStatusError;

  /// No description provided for @sshProfileTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get sshProfileTest;

  /// No description provided for @sshProfileConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get sshProfileConnect;

  /// No description provided for @sshProfileDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get sshProfileDisconnect;

  /// No description provided for @sshProfileEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get sshProfileEdit;

  /// No description provided for @sshProfileDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sshProfileDelete;

  /// No description provided for @sshProfileRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get sshProfileRefresh;

  /// No description provided for @sshProfileTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get sshProfileTestSuccess;

  /// No description provided for @sshProfileTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection test failed'**
  String get sshProfileTestFailed;

  /// No description provided for @sshProfileConnectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connected to {host}'**
  String sshProfileConnectSuccess(String host);

  /// No description provided for @sshProfileFormTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New SSH target'**
  String get sshProfileFormTitleNew;

  /// No description provided for @sshProfileFormTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit SSH target'**
  String get sshProfileFormTitleEdit;

  /// No description provided for @sshProfileFormLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get sshProfileFormLabel;

  /// No description provided for @sshProfileFormLabelHint.
  ///
  /// In en, this message translates to:
  /// **'My server'**
  String get sshProfileFormLabelHint;

  /// No description provided for @sshProfileFormHost.
  ///
  /// In en, this message translates to:
  /// **'Host or alias'**
  String get sshProfileFormHost;

  /// No description provided for @sshProfileFormHostHint.
  ///
  /// In en, this message translates to:
  /// **'server, deploy@server:2222'**
  String get sshProfileFormHostHint;

  /// No description provided for @sshProfileFormUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get sshProfileFormUsername;

  /// No description provided for @sshProfileFormUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'deploy'**
  String get sshProfileFormUsernameHint;

  /// No description provided for @sshProfileFormPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get sshProfileFormPort;

  /// No description provided for @sshProfileFormPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Port must be between 1 and 65535'**
  String get sshProfileFormPortInvalid;

  /// No description provided for @sshProfileFormIdentityFile.
  ///
  /// In en, this message translates to:
  /// **'Identity file'**
  String get sshProfileFormIdentityFile;

  /// No description provided for @sshProfileFormIdentityFileHint.
  ///
  /// In en, this message translates to:
  /// **'~/.ssh/id_ed25519'**
  String get sshProfileFormIdentityFileHint;

  /// No description provided for @sshProfileFormIdentityFileHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional. Reads the private key from disk when set.'**
  String get sshProfileFormIdentityFileHelper;

  /// No description provided for @sshProfileFormIdentityFileBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get sshProfileFormIdentityFileBrowse;

  /// No description provided for @sshProfileFormIdentityFileMissing.
  ///
  /// In en, this message translates to:
  /// **'Identity file not found'**
  String get sshProfileFormIdentityFileMissing;

  /// No description provided for @sshProfileFormPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Key passphrase'**
  String get sshProfileFormPassphrase;

  /// No description provided for @sshProfileFormPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get sshProfileFormPassphraseHint;

  /// No description provided for @sshProfileFormPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get sshProfileFormPassword;

  /// No description provided for @sshProfileFormPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Use when no identity file is set'**
  String get sshProfileFormPasswordHint;

  /// No description provided for @sshProfileFormPasswordHintEdit.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep saved password'**
  String get sshProfileFormPasswordHintEdit;

  /// No description provided for @sshProfileFormPasswordHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional if an identity file is provided.'**
  String get sshProfileFormPasswordHelper;

  /// No description provided for @sshProfileFormCredentialRequired.
  ///
  /// In en, this message translates to:
  /// **'Provide an identity file or password.'**
  String get sshProfileFormCredentialRequired;

  /// No description provided for @sshProfileFormFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get sshProfileFormFieldRequired;

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

  /// No description provided for @sshDefaultWorkingDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'SSH default working directory'**
  String get sshDefaultWorkingDirectoryTitle;

  /// No description provided for @sshDefaultWorkingDirectorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remote working directory used when the SSH launch has no workspace path; leave empty to skip changing directory.'**
  String get sshDefaultWorkingDirectorySubtitle;

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

  /// No description provided for @cliInstallProgressInstallingCli.
  ///
  /// In en, this message translates to:
  /// **'Installing CLI…'**
  String get cliInstallProgressInstallingCli;

  /// No description provided for @cliInstallProgressLocatingExecutable.
  ///
  /// In en, this message translates to:
  /// **'Locating CLI executable…'**
  String get cliInstallProgressLocatingExecutable;

  /// No description provided for @cliExecutablePathLabelFor.
  ///
  /// In en, this message translates to:
  /// **'{cli} CLI path'**
  String cliExecutablePathLabelFor(String cli);

  /// No description provided for @cliExecutablePathDescriptionFor.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to the {cli} executable. Leave empty to use the one on PATH.'**
  String cliExecutablePathDescriptionFor(String cli);

  /// No description provided for @cliExecutablePathDescriptionSshFor.
  ///
  /// In en, this message translates to:
  /// **'Absolute path to {cli} on the remote SSH host. Leave empty to auto-discover over SSH.'**
  String cliExecutablePathDescriptionSshFor(String cli);

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

  /// Shown when a dragged file lives on a different machine than the terminal it was dropped on.
  ///
  /// In en, this message translates to:
  /// **'Can\'t drop a local file onto a remote terminal'**
  String get terminalDropCrossMachineRejected;

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

  /// No description provided for @fileTreeRevealActiveFile.
  ///
  /// In en, this message translates to:
  /// **'Reveal active file'**
  String get fileTreeRevealActiveFile;

  /// No description provided for @fileTreeRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get fileTreeRefresh;

  /// No description provided for @fileTreeShowFilter.
  ///
  /// In en, this message translates to:
  /// **'Show file filter'**
  String get fileTreeShowFilter;

  /// No description provided for @fileTreeHideFilter.
  ///
  /// In en, this message translates to:
  /// **'Hide file filter'**
  String get fileTreeHideFilter;

  /// No description provided for @fileTreeRevealFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot reveal this file in the file tree'**
  String get fileTreeRevealFailed;

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

  /// No description provided for @fileTreeNewFile.
  ///
  /// In en, this message translates to:
  /// **'New File'**
  String get fileTreeNewFile;

  /// No description provided for @fileTreeNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get fileTreeNewFolder;

  /// No description provided for @fileTreeCreateNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fileTreeCreateNameHint;

  /// No description provided for @fileTreeCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get fileTreeCut;

  /// No description provided for @fileTreeCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get fileTreeCopy;

  /// No description provided for @fileTreePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get fileTreePaste;

  /// No description provided for @fileTreeRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fileTreeRename;

  /// No description provided for @fileTreeRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get fileTreeRenameTitle;

  /// No description provided for @fileTreeOpenInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Reveal in File Manager'**
  String get fileTreeOpenInFileManager;

  /// No description provided for @fileTreeOpenInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open in Terminal'**
  String get fileTreeOpenInTerminal;

  /// No description provided for @fileTreePasteDone.
  ///
  /// In en, this message translates to:
  /// **'Pasted'**
  String get fileTreePasteDone;

  /// No description provided for @fileTreeFileCreated.
  ///
  /// In en, this message translates to:
  /// **'File created'**
  String get fileTreeFileCreated;

  /// No description provided for @fileTreeFolderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder created'**
  String get fileTreeFolderCreated;

  /// No description provided for @fileTreeRenameDone.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get fileTreeRenameDone;

  /// No description provided for @fileTreeDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get fileTreeDeleteDone;

  /// No description provided for @fileTreeInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Invalid name'**
  String get fileTreeInvalidName;

  /// No description provided for @fileTreeItemExists.
  ///
  /// In en, this message translates to:
  /// **'An item with that name already exists'**
  String get fileTreeItemExists;

  /// No description provided for @fileTreeSourceMissing.
  ///
  /// In en, this message translates to:
  /// **'The copied item no longer exists'**
  String get fileTreeSourceMissing;

  /// No description provided for @fileTreeInvalidPasteTarget.
  ///
  /// In en, this message translates to:
  /// **'Cannot paste here'**
  String get fileTreeInvalidPasteTarget;

  /// No description provided for @fileTreeOpenInTerminalFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open a terminal'**
  String get fileTreeOpenInTerminalFailed;

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

  /// No description provided for @terminalCopySelectHint.
  ///
  /// In en, this message translates to:
  /// **'Shift+drag to copy'**
  String get terminalCopySelectHint;

  /// No description provided for @workspaceTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get workspaceTerminal;

  /// No description provided for @workspaceTerminalShow.
  ///
  /// In en, this message translates to:
  /// **'Show terminal'**
  String get workspaceTerminalShow;

  /// No description provided for @workspaceTerminalHide.
  ///
  /// In en, this message translates to:
  /// **'Hide terminal'**
  String get workspaceTerminalHide;

  /// No description provided for @workspaceTerminalClose.
  ///
  /// In en, this message translates to:
  /// **'Close terminal panel'**
  String get workspaceTerminalClose;

  /// No description provided for @workspaceTerminalNoWorkingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Connect a session to open the shell terminal'**
  String get workspaceTerminalNoWorkingDirectory;

  /// No description provided for @workspaceTerminalNewSession.
  ///
  /// In en, this message translates to:
  /// **'New terminal'**
  String get workspaceTerminalNewSession;

  /// No description provided for @workspaceTerminalNewSessionMenu.
  ///
  /// In en, this message translates to:
  /// **'New terminal session menu'**
  String get workspaceTerminalNewSessionMenu;

  /// No description provided for @workspaceTerminalNewSshSession.
  ///
  /// In en, this message translates to:
  /// **'New SSH Session…'**
  String get workspaceTerminalNewSshSession;

  /// No description provided for @workspaceTerminalSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get workspaceTerminalSettings;

  /// No description provided for @workspaceTerminalThemeAdaptive.
  ///
  /// In en, this message translates to:
  /// **'Match app theme'**
  String get workspaceTerminalThemeAdaptive;

  /// No description provided for @workspaceTerminalThemeClassicDark.
  ///
  /// In en, this message translates to:
  /// **'Classic dark'**
  String get workspaceTerminalThemeClassicDark;

  /// No description provided for @workspaceTerminalThemeHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get workspaceTerminalThemeHighContrast;

  /// No description provided for @workspaceTerminalSshConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'SSH profile not found or connection failed'**
  String get workspaceTerminalSshConnectFailed;

  /// No description provided for @workspaceTerminalCloseSession.
  ///
  /// In en, this message translates to:
  /// **'Close terminal'**
  String get workspaceTerminalCloseSession;

  /// No description provided for @terminalScrollbackLinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal scrollback lines'**
  String get terminalScrollbackLinesTitle;

  /// No description provided for @terminalScrollbackLinesDescription.
  ///
  /// In en, this message translates to:
  /// **'Maximum lines kept in each session terminal buffer'**
  String get terminalScrollbackLinesDescription;

  /// No description provided for @terminalLinkClickOpensInAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Open terminal links in app'**
  String get terminalLinkClickOpensInAppTitle;

  /// No description provided for @terminalLinkClickOpensInAppDescription.
  ///
  /// In en, this message translates to:
  /// **'Left-click links and file paths to open them in TeamPilot instead of the running program. Ctrl/Cmd-click always opens in app.'**
  String get terminalLinkClickOpensInAppDescription;

  /// No description provided for @terminalParkedSendPending.
  ///
  /// In en, this message translates to:
  /// **'Sent, awaiting receipt: {content}'**
  String terminalParkedSendPending(String content);

  /// No description provided for @terminalParkedSendDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get terminalParkedSendDismiss;

  /// No description provided for @mailbox.
  ///
  /// In en, this message translates to:
  /// **'Mailbox'**
  String get mailbox;

  /// No description provided for @mailboxEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get mailboxEmpty;

  /// No description provided for @board.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get board;

  /// No description provided for @boardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get boardEmpty;

  /// No description provided for @boardPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get boardPending;

  /// No description provided for @boardClaimed.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get boardClaimed;

  /// No description provided for @boardDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get boardDone;

  /// No description provided for @visibilityBoardHint.
  ///
  /// In en, this message translates to:
  /// **'Show the task board for mixed-mode teams.'**
  String get visibilityBoardHint;

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

  /// No description provided for @memberTargetAssignmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Member machine'**
  String get memberTargetAssignmentTitle;

  /// No description provided for @memberTargetAssignmentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which machine {member} runs on (its assigned workspace folders).'**
  String memberTargetAssignmentSubtitle(Object member);

  /// No description provided for @memberTargetAssignmentInherit.
  ///
  /// In en, this message translates to:
  /// **'Inherit workspace folders'**
  String get memberTargetAssignmentInherit;

  /// No description provided for @memberAssignFoldersAction.
  ///
  /// In en, this message translates to:
  /// **'Assign folders…'**
  String get memberAssignFoldersAction;

  /// No description provided for @credentialPushOptInTitle.
  ///
  /// In en, this message translates to:
  /// **'Push credentials to this machine'**
  String get credentialPushOptInTitle;

  /// No description provided for @credentialPushOptInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Materialize provider keys onto {host} so remote members can authenticate. Off by default.'**
  String credentialPushOptInSubtitle(Object host);

  /// No description provided for @credentialPushConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Push credentials to remote host?'**
  String get credentialPushConfirmTitle;

  /// No description provided for @credentialPushConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Provider keys will be written to the remote host {host}. Only enable this for machines you trust. Rotating a key requires re-pushing to every opted-in machine.'**
  String credentialPushConfirmBody(Object host);

  /// No description provided for @credentialPushConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Push credentials'**
  String get credentialPushConfirmAction;

  /// No description provided for @rootSandboxEnvOptInTitle.
  ///
  /// In en, this message translates to:
  /// **'Inject IS_SANDBOX for root'**
  String get rootSandboxEnvOptInTitle;

  /// No description provided for @rootSandboxEnvOptInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When Claude launches as root on {host} outside a container, set IS_SANDBOX=1 so skip-permissions is kept. Off by default.'**
  String rootSandboxEnvOptInSubtitle(Object host);

  /// No description provided for @rootSandboxEnvConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable root sandbox env?'**
  String get rootSandboxEnvConfirmTitle;

  /// No description provided for @rootSandboxEnvConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'TeamPilot will set IS_SANDBOX=1 when launching Claude as root on {host}, keeping --dangerously-skip-permissions. Only enable on machines you trust.'**
  String rootSandboxEnvConfirmBody(Object host);

  /// No description provided for @rootSandboxEnvConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get rootSandboxEnvConfirmAction;

  /// No description provided for @workspaceTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace machine'**
  String get workspaceTargetTitle;

  /// No description provided for @workspaceTargetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The machine this workspace\'s folders live and run on. Sessions launch on this target; switching does not move files.'**
  String get workspaceTargetSubtitle;

  /// No description provided for @workspaceFoldersSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Directories & machines'**
  String get workspaceFoldersSectionTitle;

  /// No description provided for @workspaceFoldersEditorHint.
  ///
  /// In en, this message translates to:
  /// **'Set machine and path per directory. All local = local workspace; all one remote = project-remote; cross-machine = mixed (member-remote).'**
  String get workspaceFoldersEditorHint;

  /// No description provided for @workspaceFoldersMixedTargetsLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Mixed workspace: folder machines are fixed. Add paths on existing machines above; use Assign to change member machine assignment.'**
  String get workspaceFoldersMixedTargetsLockedHint;

  /// No description provided for @workspaceFoldersPersonalTargetsLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Personal identity cannot change folder machines. Switch to a team identity to configure machines and directories.'**
  String get workspaceFoldersPersonalTargetsLockedHint;

  /// No description provided for @workspaceFoldersPickMixedTarget.
  ///
  /// In en, this message translates to:
  /// **'Add directory on machine'**
  String get workspaceFoldersPickMixedTarget;

  /// No description provided for @workspaceTopologyLocal.
  ///
  /// In en, this message translates to:
  /// **'Local workspace'**
  String get workspaceTopologyLocal;

  /// No description provided for @workspaceTopologyRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote workspace'**
  String get workspaceTopologyRemote;

  /// No description provided for @workspaceTopologyMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed workspace'**
  String get workspaceTopologyMixed;

  /// No description provided for @workspaceTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workspaceTypeLabel;

  /// No description provided for @mixedWorkspaceRequiresTeamLaunch.
  ///
  /// In en, this message translates to:
  /// **'Mixed workspaces can only be started with a team identity. Switch to a team and assign each member to a machine.'**
  String get mixedWorkspaceRequiresTeamLaunch;

  /// No description provided for @mixedWorkspacePersonalLaunchBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'This is a mixed workspace. Switch to a team tab to start conversations and assign members to machines.'**
  String get mixedWorkspacePersonalLaunchBlockedHint;

  /// No description provided for @mixedWorkspaceMemberAssignmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Assign members to machines'**
  String get mixedWorkspaceMemberAssignmentTitle;

  /// No description provided for @mixedWorkspaceMemberAssignmentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a machine on the left, then use + / − to place each member\'s instances on it.'**
  String get mixedWorkspaceMemberAssignmentSubtitle;

  /// No description provided for @mixedWorkspaceMemberAssignmentIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Every member instance must be assigned to a machine.'**
  String get mixedWorkspaceMemberAssignmentIncomplete;

  /// No description provided for @mixedWorkspaceMemberAssignmentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Start team'**
  String get mixedWorkspaceMemberAssignmentConfirm;

  /// No description provided for @workspaceMemberTargetsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Member machine assignment'**
  String get workspaceMemberTargetsSectionTitle;

  /// No description provided for @workspaceMemberTargetsSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default for new conversations with this team. Existing conversations keep the assignment from when they were created.'**
  String get workspaceMemberTargetsSectionSubtitle;

  /// No description provided for @workspaceMemberTargetsSave.
  ///
  /// In en, this message translates to:
  /// **'Save assignment'**
  String get workspaceMemberTargetsSave;

  /// No description provided for @workspaceMemberTargetsSaved.
  ///
  /// In en, this message translates to:
  /// **'Member assignment saved.'**
  String get workspaceMemberTargetsSaved;

  /// No description provided for @workspaceMemberTargetsAssignAction.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get workspaceMemberTargetsAssignAction;

  /// No description provided for @workspaceMemberTargetsAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get workspaceMemberTargetsAssigned;

  /// No description provided for @workspaceMemberTargetsUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get workspaceMemberTargetsUnassigned;

  /// No description provided for @workspaceMemberTargetsPartiallyAssigned.
  ///
  /// In en, this message translates to:
  /// **'Partially assigned'**
  String get workspaceMemberTargetsPartiallyAssigned;

  /// No description provided for @mixedWorkspaceCreateSessionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Complete member machine assignment in workspace settings before starting a conversation.'**
  String get mixedWorkspaceCreateSessionBlocked;

  /// No description provided for @mixedWorkspaceSessionLaunchBlocked.
  ///
  /// In en, this message translates to:
  /// **'This conversation has incomplete member assignments. Configure assignment in workspace settings and start a new conversation.'**
  String get mixedWorkspaceSessionLaunchBlocked;

  /// No description provided for @sessionLaunchMissingWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace not found for this session.'**
  String get sessionLaunchMissingWorkspace;

  /// No description provided for @sessionLaunchMissingTeamMember.
  ///
  /// In en, this message translates to:
  /// **'Team member is not available. Select a team and try again.'**
  String get sessionLaunchMissingTeamMember;

  /// No description provided for @mixedWorkspaceMemberPlacementProgress.
  ///
  /// In en, this message translates to:
  /// **'{placed} / {total} assigned'**
  String mixedWorkspaceMemberPlacementProgress(int placed, int total);

  /// No description provided for @mixedWorkspaceMemberPlacementOnMachine.
  ///
  /// In en, this message translates to:
  /// **'{count} on this machine'**
  String mixedWorkspaceMemberPlacementOnMachine(int count);

  /// No description provided for @workspaceFolderTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get workspaceFolderTargetLabel;

  /// No description provided for @workspaceFolderPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get workspaceFolderPathLabel;

  /// No description provided for @workspaceFoldersChangeTarget.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get workspaceFoldersChangeTarget;

  /// No description provided for @workspaceFoldersAddOnAnotherMachine.
  ///
  /// In en, this message translates to:
  /// **'Add on another machine'**
  String get workspaceFoldersAddOnAnotherMachine;

  /// No description provided for @workspaceFoldersPickTarget.
  ///
  /// In en, this message translates to:
  /// **'Choose machine'**
  String get workspaceFoldersPickTarget;

  /// No description provided for @workspaceFoldersPickPath.
  ///
  /// In en, this message translates to:
  /// **'Choose directory'**
  String get workspaceFoldersPickPath;

  /// No description provided for @workspaceFoldersApplyAllLocal.
  ///
  /// In en, this message translates to:
  /// **'Set all to local'**
  String get workspaceFoldersApplyAllLocal;

  /// No description provided for @workspaceFoldersApplyAllRemote.
  ///
  /// In en, this message translates to:
  /// **'Set all to remote…'**
  String get workspaceFoldersApplyAllRemote;

  /// No description provided for @workspaceFoldersPickRemoteTarget.
  ///
  /// In en, this message translates to:
  /// **'Choose remote machine'**
  String get workspaceFoldersPickRemoteTarget;

  /// No description provided for @homeTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Home device'**
  String get homeTargetTitle;

  /// No description provided for @homeTargetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where TeamPilot stores teams, workspaces, and config (the control plane). Switching uses a separate data tree; nothing is migrated automatically.'**
  String get homeTargetSubtitle;

  /// No description provided for @homeTargetSingleOptionHint.
  ///
  /// In en, this message translates to:
  /// **'This is the only available home on this platform.'**
  String get homeTargetSingleOptionHint;

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

  /// No description provided for @bootstrapLoadingApp.
  ///
  /// In en, this message translates to:
  /// **'Starting TeamPilot…'**
  String get bootstrapLoadingApp;

  /// No description provided for @bootstrapLoadingWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Loading workspaces…'**
  String get bootstrapLoadingWorkspaces;

  /// No description provided for @bootstrapLoadingLibraries.
  ///
  /// In en, this message translates to:
  /// **'Loading libraries…'**
  String get bootstrapLoadingLibraries;

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

  /// No description provided for @claudeOfficialCredentialsAuthenticated.
  ///
  /// In en, this message translates to:
  /// **'Authenticated'**
  String get claudeOfficialCredentialsAuthenticated;

  /// No description provided for @claudeOfficialCredentialsUnauthenticated.
  ///
  /// In en, this message translates to:
  /// **'Unauthenticated'**
  String get claudeOfficialCredentialsUnauthenticated;

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

  /// No description provided for @cursorCredentialsAuthenticated.
  ///
  /// In en, this message translates to:
  /// **'Authenticated'**
  String get cursorCredentialsAuthenticated;

  /// No description provided for @cursorCredentialsUnauthenticated.
  ///
  /// In en, this message translates to:
  /// **'Unauthenticated'**
  String get cursorCredentialsUnauthenticated;

  /// No description provided for @cursorCredentialsLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Cursor'**
  String get cursorCredentialsLogin;

  /// No description provided for @cursorCredentialsImportGlobal.
  ///
  /// In en, this message translates to:
  /// **'Import from ~/.cursor'**
  String get cursorCredentialsImportGlobal;

  /// No description provided for @cursorCredentialsImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import directory…'**
  String get cursorCredentialsImportFile;

  /// No description provided for @cursorCredentialsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get cursorCredentialsRevoke;

  /// No description provided for @cursorCredentialsRevokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out and remove saved credentials for {name}?'**
  String cursorCredentialsRevokeConfirm(String name);

  /// No description provided for @cursorCredentialsActionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Credentials updated'**
  String get cursorCredentialsActionSuccess;

  /// No description provided for @cursorCredentialsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update credentials'**
  String get cursorCredentialsActionFailed;

  /// No description provided for @codexCredentialsLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with OpenAI'**
  String get codexCredentialsLogin;

  /// No description provided for @codexCredentialsImportGlobal.
  ///
  /// In en, this message translates to:
  /// **'Import from ~/.codex'**
  String get codexCredentialsImportGlobal;

  /// No description provided for @codexCredentialsImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import auth.json…'**
  String get codexCredentialsImportFile;

  /// No description provided for @codexCredentialsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get codexCredentialsRevoke;

  /// No description provided for @codexCredentialsRevokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out and remove saved credentials for {name}?'**
  String codexCredentialsRevokeConfirm(String name);

  /// No description provided for @codexCredentialsActionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Credentials updated'**
  String get codexCredentialsActionSuccess;

  /// No description provided for @codexCredentialsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update credentials'**
  String get codexCredentialsActionFailed;

  /// No description provided for @opencodeCredentialsLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with provider'**
  String get opencodeCredentialsLogin;

  /// No description provided for @opencodeCredentialsImportGlobal.
  ///
  /// In en, this message translates to:
  /// **'Import from opencode auth'**
  String get opencodeCredentialsImportGlobal;

  /// No description provided for @opencodeCredentialsImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import auth.json…'**
  String get opencodeCredentialsImportFile;

  /// No description provided for @opencodeCredentialsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get opencodeCredentialsRevoke;

  /// No description provided for @opencodeCredentialsRevokeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out and remove saved credentials for {name}?'**
  String opencodeCredentialsRevokeConfirm(String name);

  /// No description provided for @opencodeCredentialsActionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Credentials updated'**
  String get opencodeCredentialsActionSuccess;

  /// No description provided for @opencodeCredentialsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update credentials'**
  String get opencodeCredentialsActionFailed;

  /// No description provided for @providerCredentialsFailureUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This credential action is not supported'**
  String get providerCredentialsFailureUnsupported;

  /// No description provided for @providerCredentialsFailureServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Credential service is not available'**
  String get providerCredentialsFailureServiceUnavailable;

  /// No description provided for @providerCredentialsFailureProviderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Provider not found'**
  String get providerCredentialsFailureProviderNotFound;

  /// No description provided for @providerCredentialsFailurePathRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a file or directory first'**
  String get providerCredentialsFailurePathRequired;

  /// No description provided for @providerCredentialsFailureSourceMissing.
  ///
  /// In en, this message translates to:
  /// **'Credential file not found: {path}'**
  String providerCredentialsFailureSourceMissing(String path);

  /// No description provided for @providerCredentialsFailureSourceUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read credential file: {path}'**
  String providerCredentialsFailureSourceUnreadable(String path);

  /// No description provided for @providerCredentialsFailureProviderEntryMissing.
  ///
  /// In en, this message translates to:
  /// **'No credential for \"{providerId}\" in {path}'**
  String providerCredentialsFailureProviderEntryMissing(
    String providerId,
    String path,
  );

  /// No description provided for @providerCredentialsFailureProviderEntryMissingWithKeys.
  ///
  /// In en, this message translates to:
  /// **'No credential for \"{providerId}\" in {path}. Available: {keys}'**
  String providerCredentialsFailureProviderEntryMissingWithKeys(
    String providerId,
    String path,
    String keys,
  );

  /// No description provided for @providerCredentialsFailureInvalidCredential.
  ///
  /// In en, this message translates to:
  /// **'Credential format is invalid or incomplete'**
  String get providerCredentialsFailureInvalidCredential;

  /// No description provided for @providerCredentialsFailureDestinationExists.
  ///
  /// In en, this message translates to:
  /// **'Credentials already exist. Sign out first or import again to replace.'**
  String get providerCredentialsFailureDestinationExists;

  /// No description provided for @providerCredentialsFailureRequiredFileMissing.
  ///
  /// In en, this message translates to:
  /// **'Required file missing: {path}'**
  String providerCredentialsFailureRequiredFileMissing(String path);

  /// No description provided for @providerCredentialsFailureLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed (exit code {exitCode})'**
  String providerCredentialsFailureLoginFailed(int exitCode);

  /// No description provided for @providerCredentialsFailureLoginProcessError.
  ///
  /// In en, this message translates to:
  /// **'Could not run login command: {detail}'**
  String providerCredentialsFailureLoginProcessError(String detail);

  /// No description provided for @providerCredentialsFailureRevokeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sign out or remove credentials'**
  String get providerCredentialsFailureRevokeFailed;

  /// No description provided for @providerCredentialsFailureVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Credentials were saved but verification failed'**
  String get providerCredentialsFailureVerifyFailed;

  /// No description provided for @providerCredentialsFailureStatusRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Credentials updated but status could not be refreshed'**
  String get providerCredentialsFailureStatusRefreshFailed;

  /// No description provided for @claudeLaunchCredentialsMissingWarning.
  ///
  /// In en, this message translates to:
  /// **'Claude Official credentials are missing for this team provider. Sign in from Providers settings.'**
  String get claudeLaunchCredentialsMissingWarning;

  /// No description provided for @teamConfigIncompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Team configuration incomplete'**
  String get teamConfigIncompleteTitle;

  /// No description provided for @teamConfigIncompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Team \"{team}\" is missing settings needed to launch. The session still starts, but agents may fail without them:'**
  String teamConfigIncompleteBody(String team);

  /// No description provided for @teamConfigIncompleteGoConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure team'**
  String get teamConfigIncompleteGoConfigure;

  /// No description provided for @teamConfigIncompleteDismiss.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get teamConfigIncompleteDismiss;

  /// No description provided for @teamConfigGroupTeamDefault.
  ///
  /// In en, this message translates to:
  /// **'Team default'**
  String get teamConfigGroupTeamDefault;

  /// No description provided for @teamConfigAspectDefaultProvider.
  ///
  /// In en, this message translates to:
  /// **'Default provider'**
  String get teamConfigAspectDefaultProvider;

  /// No description provided for @teamConfigAspectProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get teamConfigAspectProvider;

  /// No description provided for @teamConfigAspectModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get teamConfigAspectModel;

  /// No description provided for @teamConfigAspectCli.
  ///
  /// In en, this message translates to:
  /// **'CLI'**
  String get teamConfigAspectCli;

  /// No description provided for @teamConfigAspectSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get teamConfigAspectSeparator;

  /// No description provided for @teamConfigIssueSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'{subject} is missing: {aspects}'**
  String teamConfigIssueSemanticLabel(String subject, String aspects);

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

  /// No description provided for @providerModelBackgroundTier.
  ///
  /// In en, this message translates to:
  /// **'Use for background/fast tasks (Claude haiku tier)'**
  String get providerModelBackgroundTier;

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

  /// No description provided for @pluginCliSupportFully.
  ///
  /// In en, this message translates to:
  /// **'{cli}: Fully supported'**
  String pluginCliSupportFully(String cli);

  /// No description provided for @pluginCliSupportPartial.
  ///
  /// In en, this message translates to:
  /// **'{cli}: Partially supported ({dropped} dropped)'**
  String pluginCliSupportPartial(String cli, String dropped);

  /// No description provided for @pluginCliSupportNotApplicable.
  ///
  /// In en, this message translates to:
  /// **'{cli}: Not applicable'**
  String pluginCliSupportNotApplicable(String cli);

  /// No description provided for @pluginComponentSkills.
  ///
  /// In en, this message translates to:
  /// **'skills'**
  String get pluginComponentSkills;

  /// No description provided for @pluginComponentAgents.
  ///
  /// In en, this message translates to:
  /// **'agents'**
  String get pluginComponentAgents;

  /// No description provided for @pluginComponentCommands.
  ///
  /// In en, this message translates to:
  /// **'commands'**
  String get pluginComponentCommands;

  /// No description provided for @pluginComponentHooks.
  ///
  /// In en, this message translates to:
  /// **'hooks'**
  String get pluginComponentHooks;

  /// No description provided for @pluginComponentMcp.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get pluginComponentMcp;

  /// No description provided for @pluginComponentRules.
  ///
  /// In en, this message translates to:
  /// **'rules'**
  String get pluginComponentRules;

  /// No description provided for @pluginComponentApps.
  ///
  /// In en, this message translates to:
  /// **'apps'**
  String get pluginComponentApps;

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
  /// **'Team agents'**
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

  /// No description provided for @teamExtensionsNav.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get teamExtensionsNav;

  /// No description provided for @teamExtensionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Extensions for this team'**
  String get teamExtensionsTitle;

  /// No description provided for @teamExtensionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Override which extensions run for this team. Default follows the global setting.'**
  String get teamExtensionsSubtitle;

  /// No description provided for @teamExtensionFollowGlobal.
  ///
  /// In en, this message translates to:
  /// **'Follow global'**
  String get teamExtensionFollowGlobal;

  /// No description provided for @teamExtensionForceOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get teamExtensionForceOn;

  /// No description provided for @teamExtensionForceOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get teamExtensionForceOff;

  /// No description provided for @teamExtensionEffectiveOn.
  ///
  /// In en, this message translates to:
  /// **'Active for this team'**
  String get teamExtensionEffectiveOn;

  /// No description provided for @teamExtensionEffectiveOff.
  ///
  /// In en, this message translates to:
  /// **'Inactive for this team'**
  String get teamExtensionEffectiveOff;

  /// No description provided for @teamMcpNav.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get teamMcpNav;

  /// No description provided for @teamHubNav.
  ///
  /// In en, this message translates to:
  /// **'TeamHub'**
  String get teamHubNav;

  /// No description provided for @teamHubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discover more public teams'**
  String get teamHubSubtitle;

  /// No description provided for @teamHubTitle.
  ///
  /// In en, this message translates to:
  /// **'TeamHub'**
  String get teamHubTitle;

  /// No description provided for @teamHubDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get teamHubDiscovery;

  /// No description provided for @teamHubFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get teamHubFavorites;

  /// No description provided for @teamHubSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search public teams'**
  String get teamHubSearchHint;

  /// No description provided for @teamHubSortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get teamHubSortName;

  /// No description provided for @teamHubSortUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently updated'**
  String get teamHubSortUpdated;

  /// No description provided for @teamHubCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get teamHubCategoryAll;

  /// No description provided for @teamHubClone.
  ///
  /// In en, this message translates to:
  /// **'Clone to my teams'**
  String get teamHubClone;

  /// No description provided for @teamHubCloning.
  ///
  /// In en, this message translates to:
  /// **'Cloning…'**
  String get teamHubCloning;

  /// No description provided for @teamHubCloneSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cloned \"{name}\".'**
  String teamHubCloneSuccess(Object name);

  /// No description provided for @teamHubCloneSuccessWithDeps.
  ///
  /// In en, this message translates to:
  /// **'Cloned \"{name}\". Installed {skillCount} skills, {pluginCount} plugins, and {mcpCount} MCP servers.'**
  String teamHubCloneSuccessWithDeps(
    Object name,
    int skillCount,
    int pluginCount,
    int mcpCount,
  );

  /// No description provided for @teamHubClonePartial.
  ///
  /// In en, this message translates to:
  /// **'Cloned \"{name}\". Installed {skillCount} skills, {pluginCount} plugins, {mcpCount} MCP. {failedCount} could not be installed: {failedNames}.'**
  String teamHubClonePartial(
    Object name,
    int skillCount,
    int pluginCount,
    int mcpCount,
    int failedCount,
    Object failedNames,
  );

  /// No description provided for @teamHubCloneFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clone this team.'**
  String get teamHubCloneFailed;

  /// No description provided for @teamHubEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No public teams yet'**
  String get teamHubEmptyTitle;

  /// No description provided for @teamHubEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Refresh to fetch teams from the registry.'**
  String get teamHubEmptyHint;

  /// No description provided for @teamHubFavoritesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get teamHubFavoritesEmptyTitle;

  /// No description provided for @teamHubFavoritesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the star on a team to save it here.'**
  String get teamHubFavoritesEmptyHint;

  /// No description provided for @teamHubRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get teamHubRefresh;

  /// No description provided for @teamHubLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load public teams.'**
  String get teamHubLoadError;

  /// No description provided for @teamHubDepInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get teamHubDepInstalled;

  /// No description provided for @teamHubDepToInstall.
  ///
  /// In en, this message translates to:
  /// **'Will be installed'**
  String get teamHubDepToInstall;

  /// No description provided for @teamHubMembersLabel.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get teamHubMembersLabel;

  /// No description provided for @teamHubSkillsLabel.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get teamHubSkillsLabel;

  /// No description provided for @teamHubPluginsLabel.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get teamHubPluginsLabel;

  /// No description provided for @teamHubMcpLabel.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get teamHubMcpLabel;

  /// No description provided for @teamMcpAssignedCount.
  ///
  /// In en, this message translates to:
  /// **'{assigned} of {total} enabled'**
  String teamMcpAssignedCount(int assigned, int total);

  /// No description provided for @teamMcpManage.
  ///
  /// In en, this message translates to:
  /// **'All MCP servers'**
  String get teamMcpManage;

  /// No description provided for @mcpNavTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP Servers'**
  String get mcpNavTitle;

  /// No description provided for @mcpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage MCP servers for Claude and FlashskyAI sessions.'**
  String get mcpSubtitle;

  /// No description provided for @mcpNavInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get mcpNavInstalled;

  /// No description provided for @mcpNavDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get mcpNavDiscovery;

  /// No description provided for @mcpNavRegistries.
  ///
  /// In en, this message translates to:
  /// **'Registry'**
  String get mcpNavRegistries;

  /// No description provided for @mcpInstalledSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Installed MCP servers'**
  String get mcpInstalledSectionTitle;

  /// No description provided for @mcpInstalledCount.
  ///
  /// In en, this message translates to:
  /// **'{count} installed'**
  String mcpInstalledCount(int count);

  /// No description provided for @mcpNoInstalled.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers installed yet'**
  String get mcpNoInstalled;

  /// No description provided for @mcpNoInstalledHint.
  ///
  /// In en, this message translates to:
  /// **'Open Discovery to add servers from built-in templates or registries.'**
  String get mcpNoInstalledHint;

  /// No description provided for @mcpDiscoverySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover MCP servers'**
  String get mcpDiscoverySectionTitle;

  /// No description provided for @mcpDiscoverySectionHint.
  ///
  /// In en, this message translates to:
  /// **'Browse built-in templates and remote catalogs configured under Registries.'**
  String get mcpDiscoverySectionHint;

  /// No description provided for @mcpDiscoverySourceAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mcpDiscoverySourceAll;

  /// No description provided for @mcpDiscoverySourceBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get mcpDiscoverySourceBuiltin;

  /// No description provided for @mcpSmitheryApiTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get mcpSmitheryApiTokenLabel;

  /// No description provided for @mcpSmitheryApiTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Smithery API key (Bearer)'**
  String get mcpSmitheryApiTokenHint;

  /// No description provided for @mcpSmitheryApiTokenSet.
  ///
  /// In en, this message translates to:
  /// **'token set'**
  String get mcpSmitheryApiTokenSet;

  /// No description provided for @mcpRegistryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit API URL'**
  String get mcpRegistryEditTitle;

  /// No description provided for @mcpRegistryResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get mcpRegistryResetTitle;

  /// No description provided for @mcpRegistryResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset \"{name}\" to the default API URL?'**
  String mcpRegistryResetConfirm(String name);

  /// No description provided for @mcpRepoApiUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get mcpRepoApiUrlLabel;

  /// No description provided for @mcpRepoTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get mcpRepoTestConnection;

  /// No description provided for @mcpRepoResetDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset default'**
  String get mcpRepoResetDefault;

  /// No description provided for @mcpRepoConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Registry API settings saved'**
  String get mcpRepoConfigSaved;

  /// No description provided for @mcpRepoTestOk.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get mcpRepoTestOk;

  /// No description provided for @mcpRepoTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String mcpRepoTestFailed(String error);

  /// No description provided for @mcpRepoDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'This catalog source is disabled. Enable it under Registries.'**
  String get mcpRepoDisabledHint;

  /// No description provided for @mcpRegistrySmithery.
  ///
  /// In en, this message translates to:
  /// **'Smithery'**
  String get mcpRegistrySmithery;

  /// No description provided for @mcpRegistryOfficial.
  ///
  /// In en, this message translates to:
  /// **'Official registry'**
  String get mcpRegistryOfficial;

  /// No description provided for @mcpRegistrySmitheryHint.
  ///
  /// In en, this message translates to:
  /// **'Smithery — https://api.smithery.ai'**
  String get mcpRegistrySmitheryHint;

  /// No description provided for @mcpRegistryOfficialHint.
  ///
  /// In en, this message translates to:
  /// **'Official MCP Registry — https://registry.modelcontextprotocol.io'**
  String get mcpRegistryOfficialHint;

  /// No description provided for @mcpRegistrySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search servers (e.g. github)'**
  String get mcpRegistrySearchHint;

  /// No description provided for @mcpRegistryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get mcpRegistryLoadMore;

  /// No description provided for @mcpCatalogAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get mcpCatalogAdd;

  /// No description provided for @mcpCatalogInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get mcpCatalogInstalled;

  /// No description provided for @mcpCatalogAdded.
  ///
  /// In en, this message translates to:
  /// **'MCP server added to catalog'**
  String get mcpCatalogAdded;

  /// No description provided for @mcpCatalogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No servers found'**
  String get mcpCatalogEmpty;

  /// No description provided for @mcpCatalogVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get mcpCatalogVerified;

  /// No description provided for @mcpEmptyGoDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Browse built-in templates'**
  String get mcpEmptyGoDiscovery;

  /// No description provided for @mcpEmptyGoRegistries.
  ///
  /// In en, this message translates to:
  /// **'Open registry settings'**
  String get mcpEmptyGoRegistries;

  /// No description provided for @mcpAdd.
  ///
  /// In en, this message translates to:
  /// **'Add MCP server'**
  String get mcpAdd;

  /// No description provided for @mcpEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit MCP server'**
  String get mcpEdit;

  /// No description provided for @mcpOpenHomepage.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get mcpOpenHomepage;

  /// No description provided for @mcpFormDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Select a server to edit, or add a new MCP server.'**
  String get mcpFormDetailHint;

  /// No description provided for @mcpServerNotFound.
  ///
  /// In en, this message translates to:
  /// **'MCP server not found'**
  String get mcpServerNotFound;

  /// No description provided for @mcpImport.
  ///
  /// In en, this message translates to:
  /// **'Import from machine'**
  String get mcpImport;

  /// No description provided for @mcpImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers found in ~/.claude.json or ~/.flashskyai.json'**
  String get mcpImportEmpty;

  /// No description provided for @mcpImportSummary.
  ///
  /// In en, this message translates to:
  /// **'{added} new, {conflicts} conflicts'**
  String mcpImportSummary(int added, int conflicts);

  /// No description provided for @mcpImportOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite conflicts'**
  String get mcpImportOverwrite;

  /// No description provided for @mcpImportDone.
  ///
  /// In en, this message translates to:
  /// **'MCP catalog updated'**
  String get mcpImportDone;

  /// No description provided for @mcpEmpty.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers in catalog'**
  String get mcpEmpty;

  /// No description provided for @mcpDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete MCP server?'**
  String get mcpDeleteConfirm;

  /// No description provided for @mcpFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mcpFieldName;

  /// No description provided for @mcpFieldCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get mcpFieldCommand;

  /// No description provided for @mcpFieldArgs.
  ///
  /// In en, this message translates to:
  /// **'Arguments (space-separated)'**
  String get mcpFieldArgs;

  /// No description provided for @mcpAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add MCP'**
  String get mcpAddTitle;

  /// No description provided for @mcpAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add MCP'**
  String get mcpAddButton;

  /// No description provided for @mcpImportExisting.
  ///
  /// In en, this message translates to:
  /// **'Import existing'**
  String get mcpImportExisting;

  /// No description provided for @mcpConfiguredCount.
  ///
  /// In en, this message translates to:
  /// **'{count} MCP server(s) configured'**
  String mcpConfiguredCount(int count);

  /// No description provided for @mcpOAuthConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect {name}'**
  String mcpOAuthConnectTitle(String name);

  /// No description provided for @mcpOAuthConnectHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the MCP provider in your browser. Tokens are stored in Claude Code format under app config (same as /mcp → Authenticate).'**
  String get mcpOAuthConnectHint;

  /// No description provided for @mcpOAuthDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Discovering authorization server…'**
  String get mcpOAuthDiscovering;

  /// No description provided for @mcpOAuthOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open browser'**
  String get mcpOAuthOpenBrowser;

  /// No description provided for @mcpOAuthCallbackUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Redirect URL'**
  String get mcpOAuthCallbackUrlLabel;

  /// No description provided for @mcpOAuthCallbackUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the full URL after sign-in (contains ?code=)'**
  String get mcpOAuthCallbackUrlHint;

  /// No description provided for @mcpOAuthSubmitCallback.
  ///
  /// In en, this message translates to:
  /// **'Submit URL'**
  String get mcpOAuthSubmitCallback;

  /// No description provided for @mcpOAuthStartConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get mcpOAuthStartConnect;

  /// No description provided for @mcpOAuthConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get mcpOAuthConnectAction;

  /// No description provided for @mcpOAuthConnectSuccess.
  ///
  /// In en, this message translates to:
  /// **'MCP OAuth connected'**
  String get mcpOAuthConnectSuccess;

  /// No description provided for @mcpOAuthStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'OAuth connected'**
  String get mcpOAuthStatusConnected;

  /// No description provided for @mcpOAuthStatusNeedsAuth.
  ///
  /// In en, this message translates to:
  /// **'Needs OAuth'**
  String get mcpOAuthStatusNeedsAuth;

  /// No description provided for @mcpPresetDescFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch web pages and convert HTML to markdown for LLMs.'**
  String get mcpPresetDescFetch;

  /// No description provided for @mcpPresetDescTime.
  ///
  /// In en, this message translates to:
  /// **'Current time, timezone conversion, and date calculations.'**
  String get mcpPresetDescTime;

  /// No description provided for @mcpPresetDescMemory.
  ///
  /// In en, this message translates to:
  /// **'Persistent memory graph for knowledge across sessions.'**
  String get mcpPresetDescMemory;

  /// No description provided for @mcpPresetDescSequentialThinking.
  ///
  /// In en, this message translates to:
  /// **'Structured step-by-step reasoning for complex problems.'**
  String get mcpPresetDescSequentialThinking;

  /// No description provided for @mcpPresetDescContext7.
  ///
  /// In en, this message translates to:
  /// **'Up-to-date library documentation via Context7.'**
  String get mcpPresetDescContext7;

  /// No description provided for @mcpFormIdLabel.
  ///
  /// In en, this message translates to:
  /// **'MCP ID (unique) *'**
  String get mcpFormIdLabel;

  /// No description provided for @mcpFormDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get mcpFormDisplayNameLabel;

  /// No description provided for @mcpFormDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. @modelcontextprotocol/server-time'**
  String get mcpFormDisplayNameHint;

  /// No description provided for @mcpFormMetadata.
  ///
  /// In en, this message translates to:
  /// **'Additional info'**
  String get mcpFormMetadata;

  /// No description provided for @mcpFormDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get mcpFormDescriptionLabel;

  /// No description provided for @mcpFormDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional description'**
  String get mcpFormDescriptionHint;

  /// No description provided for @mcpFormTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma-separated)'**
  String get mcpFormTagsLabel;

  /// No description provided for @mcpFormTagsHint.
  ///
  /// In en, this message translates to:
  /// **'stdio, time, utility'**
  String get mcpFormTagsHint;

  /// No description provided for @mcpFormHomepageLabel.
  ///
  /// In en, this message translates to:
  /// **'Homepage'**
  String get mcpFormHomepageLabel;

  /// No description provided for @mcpFormDocsLabel.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get mcpFormDocsLabel;

  /// No description provided for @mcpFormJsonLabel.
  ///
  /// In en, this message translates to:
  /// **'Full JSON configuration'**
  String get mcpFormJsonLabel;

  /// No description provided for @mcpFormFormatJson.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get mcpFormFormatJson;

  /// No description provided for @mcpFormRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'MCP ID and display name are required.'**
  String get mcpFormRequiredFields;

  /// No description provided for @mcpFormSubmitAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get mcpFormSubmitAdd;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

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

  /// No description provided for @teamEffortLevel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get teamEffortLevel;

  /// No description provided for @teamEffortLevelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default effort for this team (Claude effortLevel / Codex model_reasoning_effort).'**
  String get teamEffortLevelSubtitle;

  /// No description provided for @memberEffortLevel.
  ///
  /// In en, this message translates to:
  /// **'Member effort override'**
  String get memberEffortLevel;

  /// No description provided for @memberEffortLevelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Overrides team default when set.'**
  String get memberEffortLevelSubtitle;

  /// No description provided for @memberEffortInheritHint.
  ///
  /// In en, this message translates to:
  /// **'Inherit team default'**
  String get memberEffortInheritHint;

  /// No description provided for @providerEffortLevel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get providerEffortLevel;

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

  /// No description provided for @teamLeadBadge.
  ///
  /// In en, this message translates to:
  /// **'Leader'**
  String get teamLeadBadge;

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

  /// No description provided for @teamForceWaitBeforeStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep members in the wait loop'**
  String get teamForceWaitBeforeStopTitle;

  /// No description provided for @teamForceWaitBeforeStopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, a member finishing a turn is pushed back into wait_for_message instead of stopping, so it stays available for new messages and tasks. Disable to let members rest (stop normally).'**
  String get teamForceWaitBeforeStopSubtitle;

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
  /// **'Display only in TeamPilot (sidebar, member list). To define responsibilities and boundaries, edit Responsibilities below.'**
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
  /// **'Agent preset'**
  String get agent;

  /// No description provided for @selectAgent.
  ///
  /// In en, this message translates to:
  /// **'Select preset'**
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

  /// No description provided for @agentFlashskyaiPresetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Passed as flashskyai --agent; pick a built-in or custom sub-agent.'**
  String get agentFlashskyaiPresetSubtitle;

  /// No description provided for @agentClaudeTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Written to the Claude team roster as agentType; leave empty to use the member id.'**
  String get agentClaudeTypeSubtitle;

  /// No description provided for @agentClaudeTypeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Explore, Plan, or a custom type'**
  String get agentClaudeTypeHint;

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

  /// No description provided for @memberReplicas.
  ///
  /// In en, this message translates to:
  /// **'Replicas'**
  String get memberReplicas;

  /// No description provided for @memberReplicasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Run this role as N interchangeable instances (pods) that share its task queue. 1 = a single instance.'**
  String get memberReplicasSubtitle;

  /// No description provided for @workspaceAdvancedSettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get workspaceAdvancedSettings;

  /// No description provided for @workspaceAdvancedSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Agent preset and extra CLI flags for this member.'**
  String get workspaceAdvancedSettingsSubtitle;

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

  /// No description provided for @memberResponsibilities.
  ///
  /// In en, this message translates to:
  /// **'Responsibilities'**
  String get memberResponsibilities;

  /// No description provided for @memberPromptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What this member owns and must not do. Written into the agent\'s role definition.'**
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
  /// **'Coordinate the team: break the user\'s request into a task list (each item with scope and acceptance criteria), then assign teammates to implement. Unless blocked, do not do large implementation yourself—you may read code and docs to understand the situation.\nTalk to the user in this session window. When assigning and following up, contact only other teammates (by member name); do not assign work to yourself. After teammates finish, reply to the user with conclusions, relevant files, and next steps.'**
  String get memberPromptPresetTeamLeadText;

  /// No description provided for @memberPromptPresetDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get memberPromptPresetDeveloper;

  /// No description provided for @memberPromptPresetDeveloperText.
  ///
  /// In en, this message translates to:
  /// **'Implement assigned tasks, staying within the agreed scope. Do not expand scope or refactor unrelated code without being asked.'**
  String get memberPromptPresetDeveloperText;

  /// No description provided for @memberPromptPresetReviewer.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get memberPromptPresetReviewer;

  /// No description provided for @memberPromptPresetReviewerText.
  ///
  /// In en, this message translates to:
  /// **'Review code only. Do not modify files unless explicitly asked.'**
  String get memberPromptPresetReviewerText;

  /// No description provided for @memberPromptPresetResearcher.
  ///
  /// In en, this message translates to:
  /// **'Researcher'**
  String get memberPromptPresetResearcher;

  /// No description provided for @memberPromptPresetResearcherText.
  ///
  /// In en, this message translates to:
  /// **'Investigate and report only. Do not change production code unless asked.'**
  String get memberPromptPresetResearcherText;

  /// No description provided for @memberPlaybook.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get memberPlaybook;

  /// No description provided for @memberPlaybookSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How to execute assigned work: steps, checkpoints, and report format. Sent to the agent as operating instructions.'**
  String get memberPlaybookSubtitle;

  /// No description provided for @memberPlaybookPresetDeveloperText.
  ///
  /// In en, this message translates to:
  /// **'Work test-first: before implementing, write a failing test, then make it pass with the smallest diff. Run the relevant tests after each change and report which files changed and why. Do not bundle unrelated edits; stop at agreed checkpoints. If a test-driven-development skill is available, follow it.'**
  String get memberPlaybookPresetDeveloperText;

  /// No description provided for @memberPlaybookPresetReviewerText.
  ///
  /// In en, this message translates to:
  /// **'Review in order: (1) confirm tests cover the change; (2) correctness and edge cases; (3) maintainability and consistency with surrounding code. Every finding states file path, line, the problem, and a concrete fix—no vague praise and no nit without a fix. Flag missing tests explicitly.'**
  String get memberPlaybookPresetReviewerText;

  /// No description provided for @memberPlaybookPresetResearcherText.
  ///
  /// In en, this message translates to:
  /// **'Clarify intent before digging: restate the question and your assumptions, then investigate breadth-first across the codebase before going deep. Report findings with file paths, relevant symbols, and recommended next steps—propose, do not change production code. If a brainstorming skill is available, use it to frame the problem first.'**
  String get memberPlaybookPresetResearcherText;

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select a model'**
  String get selectModel;

  /// No description provided for @appProviderModelEnterCustom.
  ///
  /// In en, this message translates to:
  /// **'Enter custom model ID'**
  String get appProviderModelEnterCustom;

  /// No description provided for @appProviderModelPickFromList.
  ///
  /// In en, this message translates to:
  /// **'Choose from list'**
  String get appProviderModelPickFromList;

  /// No description provided for @memberOfficialClaudeModelHint.
  ///
  /// In en, this message translates to:
  /// **'Uses your Claude account default model. Manage Official login in Providers settings.'**
  String get memberOfficialClaudeModelHint;

  /// No description provided for @editMemberSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit provider, model, optional agent preset, and command arguments.'**
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

  /// No description provided for @appProviderToolOpencode.
  ///
  /// In en, this message translates to:
  /// **'OpenCode'**
  String get appProviderToolOpencode;

  /// No description provided for @appProviderToolCursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get appProviderToolCursor;

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

  /// No description provided for @appProviderClaudeCredentialBinding.
  ///
  /// In en, this message translates to:
  /// **'OAuth credential source'**
  String get appProviderClaudeCredentialBinding;

  /// No description provided for @appProviderClaudeCredentialBindingLinked.
  ///
  /// In en, this message translates to:
  /// **'Follow global (~/.claude)'**
  String get appProviderClaudeCredentialBindingLinked;

  /// No description provided for @appProviderClaudeCredentialBindingIsolated.
  ///
  /// In en, this message translates to:
  /// **'Isolated copy (TeamPilot only)'**
  String get appProviderClaudeCredentialBindingIsolated;

  /// No description provided for @appProviderClaudeCredentialBindingLinkedHint.
  ///
  /// In en, this message translates to:
  /// **'Shares the same OAuth session as Claude Code in your terminal. Refreshes stay in sync.'**
  String get appProviderClaudeCredentialBindingLinkedHint;

  /// No description provided for @appProviderClaudeCredentialBindingIsolatedHint.
  ///
  /// In en, this message translates to:
  /// **'Keeps a separate credential copy under TeamPilot. Use when this provider must not share login with global Claude Code.'**
  String get appProviderClaudeCredentialBindingIsolatedHint;

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

  /// No description provided for @appUpdateAutoCheck.
  ///
  /// In en, this message translates to:
  /// **'Auto-check for updates'**
  String get appUpdateAutoCheck;

  /// No description provided for @appUpdateAutoCheckHint.
  ///
  /// In en, this message translates to:
  /// **'Check GitHub for a newer version each time the app starts.'**
  String get appUpdateAutoCheckHint;

  /// No description provided for @appUpdateSkipVersion.
  ///
  /// In en, this message translates to:
  /// **'Skip this version'**
  String get appUpdateSkipVersion;

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

  /// No description provided for @onboardingStepDefaultPreset.
  ///
  /// In en, this message translates to:
  /// **'Default preset'**
  String get onboardingStepDefaultPreset;

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

  /// No description provided for @onboardingDefaultPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure default launch preset'**
  String get onboardingDefaultPresetTitle;

  /// No description provided for @onboardingDefaultPresetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personal workspaces and team default launch configs will use this CLI preset.'**
  String get onboardingDefaultPresetSubtitle;

  /// No description provided for @onboardingDefaultPresetEmpty.
  ///
  /// In en, this message translates to:
  /// **'No providers to choose from. Skip this step or add providers in Settings.'**
  String get onboardingDefaultPresetEmpty;

  /// No description provided for @onboardingDefaultPresetSelectExisting.
  ///
  /// In en, this message translates to:
  /// **'Use existing preset'**
  String get onboardingDefaultPresetSelectExisting;

  /// No description provided for @onboardingDefaultPresetDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get onboardingDefaultPresetDefaultName;

  /// No description provided for @onboardingDefaultPresetModelHint.
  ///
  /// In en, this message translates to:
  /// **'Primary model for this preset'**
  String get onboardingDefaultPresetModelHint;

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

  /// No description provided for @diffIgnoreWhitespace.
  ///
  /// In en, this message translates to:
  /// **'Ignore whitespace'**
  String get diffIgnoreWhitespace;

  /// No description provided for @diffPreviousChange.
  ///
  /// In en, this message translates to:
  /// **'Previous change'**
  String get diffPreviousChange;

  /// No description provided for @diffNextChange.
  ///
  /// In en, this message translates to:
  /// **'Next change'**
  String get diffNextChange;

  /// No description provided for @diffViewSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get diffViewSideBySide;

  /// No description provided for @diffViewUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified'**
  String get diffViewUnified;

  /// No description provided for @diffOpenSourceFile.
  ///
  /// In en, this message translates to:
  /// **'Open source file'**
  String get diffOpenSourceFile;

  /// No description provided for @diffShowAllLines.
  ///
  /// In en, this message translates to:
  /// **'Show all lines'**
  String get diffShowAllLines;

  /// No description provided for @diffNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get diffNoChanges;

  /// No description provided for @diffChangeCounter.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String diffChangeCounter(int current, int total);

  /// No description provided for @aiFeatures.
  ///
  /// In en, this message translates to:
  /// **'AI Features'**
  String get aiFeatures;

  /// No description provided for @aiFeaturesPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose which CLI provider, model, and effort each AI feature uses.'**
  String get aiFeaturesPageSubtitle;

  /// No description provided for @aiFeatureCommitMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Commit message generation'**
  String get aiFeatureCommitMessageTitle;

  /// No description provided for @aiFeatureCommitMessageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used by the ✨ button in the source control panel.'**
  String get aiFeatureCommitMessageSubtitle;

  /// No description provided for @aiFeatureTeamGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Team configuration generation'**
  String get aiFeatureTeamGenerateTitle;

  /// No description provided for @aiFeatureTeamGenerateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used when generating a team from a description.'**
  String get aiFeatureTeamGenerateSubtitle;

  /// No description provided for @aiFeatureCliLabel.
  ///
  /// In en, this message translates to:
  /// **'CLI'**
  String get aiFeatureCliLabel;

  /// No description provided for @aiFeatureModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiFeatureModelLabel;

  /// No description provided for @aiFeatureEffortLabel.
  ///
  /// In en, this message translates to:
  /// **'Effort'**
  String get aiFeatureEffortLabel;

  /// No description provided for @aiFeatureConfigSummary.
  ///
  /// In en, this message translates to:
  /// **'{cli} · {provider} · {model}'**
  String aiFeatureConfigSummary(String cli, String provider, String model);

  /// No description provided for @gitGenerateCommitMessage.
  ///
  /// In en, this message translates to:
  /// **'Generate commit message with AI'**
  String get gitGenerateCommitMessage;

  /// No description provided for @gitGenerateCommitMessageNoProvider.
  ///
  /// In en, this message translates to:
  /// **'Configure an AI provider in Settings → AI Features first.'**
  String get gitGenerateCommitMessageNoProvider;

  /// No description provided for @teamGenTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate with AI'**
  String get teamGenTitle;

  /// No description provided for @teamGenDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the team you want (e.g. Flutter frontend with code review and tests)'**
  String get teamGenDescriptionHint;

  /// No description provided for @teamGenButton.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get teamGenButton;

  /// No description provided for @teamGenNoProvider.
  ///
  /// In en, this message translates to:
  /// **'Configure an AI provider in Settings → AI Features first.'**
  String get teamGenNoProvider;

  /// No description provided for @teamGenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not generate a team. Please edit manually.'**
  String get teamGenFailed;

  /// No description provided for @teamGenApplied.
  ///
  /// In en, this message translates to:
  /// **'Draft applied. Review and adjust before creating.'**
  String get teamGenApplied;

  /// No description provided for @notificationCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationCenterTitle;

  /// No description provided for @notificationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get notificationEmpty;

  /// No description provided for @notificationMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationMarkAllRead;

  /// No description provided for @notificationClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get notificationClearAll;

  /// No description provided for @notificationMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get notificationMarkRead;

  /// No description provided for @notificationDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get notificationDelete;

  /// No description provided for @notificationTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get notificationTimeJustNow;

  /// No description provided for @notificationTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String notificationTimeMinutesAgo(int minutes);

  /// No description provided for @notificationTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours} h ago'**
  String notificationTimeHoursAgo(int hours);

  /// No description provided for @notificationTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} d ago'**
  String notificationTimeDaysAgo(int days);

  /// No description provided for @memberDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Member detail'**
  String get memberDetailTitle;

  /// No description provided for @memberDetailViewAction.
  ///
  /// In en, this message translates to:
  /// **'View member detail'**
  String get memberDetailViewAction;

  /// No description provided for @memberDetailOpenConfigDir.
  ///
  /// In en, this message translates to:
  /// **'Open config directory'**
  String get memberDetailOpenConfigDir;

  /// No description provided for @memberDetailOpenInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Open in file manager'**
  String get memberDetailOpenInFileManager;

  /// No description provided for @memberDetailBrowseConfigDirTitle.
  ///
  /// In en, this message translates to:
  /// **'Config directory'**
  String get memberDetailBrowseConfigDirTitle;

  /// No description provided for @memberDetailNeedsSession.
  ///
  /// In en, this message translates to:
  /// **'Open a session first'**
  String get memberDetailNeedsSession;

  /// No description provided for @memberDetailTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get memberDetailTabOverview;

  /// No description provided for @memberDetailTabSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get memberDetailTabSkills;

  /// No description provided for @memberDetailTabMcp.
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get memberDetailTabMcp;

  /// No description provided for @memberDetailTabPlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get memberDetailTabPlugins;

  /// No description provided for @memberDetailTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get memberDetailTabSettings;

  /// No description provided for @memberDetailSourceRuntime.
  ///
  /// In en, this message translates to:
  /// **'Live session config'**
  String get memberDetailSourceRuntime;

  /// No description provided for @memberDetailSourceTeam.
  ///
  /// In en, this message translates to:
  /// **'Team-level config (member not launched in this session)'**
  String get memberDetailSourceTeam;

  /// No description provided for @memberDetailEmpty.
  ///
  /// In en, this message translates to:
  /// **'This member has no config yet in this session, and the team layer is empty.'**
  String get memberDetailEmpty;

  /// No description provided for @memberDetailLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to read this member\'s config directory.'**
  String get memberDetailLoadError;

  /// No description provided for @memberDetailOpenConfigDirFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the config directory in a file manager.'**
  String get memberDetailOpenConfigDirFailed;

  /// No description provided for @memberDetailOpenConfigDirFailedOnHost.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the config directory on {host}. The remote host may have no desktop file manager.'**
  String memberDetailOpenConfigDirFailedOnHost(String host);

  /// No description provided for @memberDetailSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get memberDetailSectionEmpty;

  /// Section header for AI CLI tools in CLI config page
  ///
  /// In en, this message translates to:
  /// **'AI CLI'**
  String get cliConfigAiCliGroup;

  /// Section header for toolchain tools (git, node) in CLI config page
  ///
  /// In en, this message translates to:
  /// **'Toolchain'**
  String get cliConfigToolchainGroup;

  /// Label for Git executable path setting
  ///
  /// In en, this message translates to:
  /// **'Git executable path'**
  String get toolchainGitLabel;

  /// Label for Node.js/npm path setting
  ///
  /// In en, this message translates to:
  /// **'Node.js / npm path'**
  String get toolchainNodeLabel;

  /// Description for toolchain path setting
  ///
  /// In en, this message translates to:
  /// **'Absolute path to the {tool} executable. Leave empty to use the one on PATH.'**
  String toolchainPathDescription(String tool);

  /// Description for toolchain path setting in SSH mode
  ///
  /// In en, this message translates to:
  /// **'Absolute path to {tool} on the remote SSH host. Leave empty to auto-discover.'**
  String toolchainPathDescriptionSsh(String tool);

  /// Label for Cursor CLI executable path setting
  ///
  /// In en, this message translates to:
  /// **'Cursor CLI path'**
  String get cliCursorExecutablePathLabel;

  /// Progress message when checking for a toolchain tool
  ///
  /// In en, this message translates to:
  /// **'Checking for {tool}...'**
  String toolchainInstallProgressChecking(String tool);

  /// No description provided for @toolchainGit.
  ///
  /// In en, this message translates to:
  /// **'Git'**
  String get toolchainGit;

  /// No description provided for @toolchainNode.
  ///
  /// In en, this message translates to:
  /// **'Node.js'**
  String get toolchainNode;

  /// No description provided for @homeWorkspaceLaunchWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Open with…'**
  String get homeWorkspaceLaunchWorkspaceTitle;

  /// No description provided for @homeWorkspaceSimpleMode.
  ///
  /// In en, this message translates to:
  /// **'Simple mode'**
  String get homeWorkspaceSimpleMode;

  /// No description provided for @homeWorkspaceRememberLaunchChoice.
  ///
  /// In en, this message translates to:
  /// **'Remember my choice'**
  String get homeWorkspaceRememberLaunchChoice;

  /// No description provided for @worktreeCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New worktree'**
  String get worktreeCreateTitle;

  /// No description provided for @worktreeBranchLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get worktreeBranchLabel;

  /// No description provided for @worktreeModeNewBranch.
  ///
  /// In en, this message translates to:
  /// **'New branch'**
  String get worktreeModeNewBranch;

  /// No description provided for @worktreeModeExistingBranch.
  ///
  /// In en, this message translates to:
  /// **'Existing branch'**
  String get worktreeModeExistingBranch;

  /// No description provided for @worktreeBaseRefLabel.
  ///
  /// In en, this message translates to:
  /// **'Base (optional)'**
  String get worktreeBaseRefLabel;

  /// No description provided for @worktreeBaseRefHint.
  ///
  /// In en, this message translates to:
  /// **'Defaults to current HEAD'**
  String get worktreeBaseRefHint;

  /// No description provided for @worktreePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get worktreePathLabel;

  /// No description provided for @worktreeStartConversation.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation here after creating'**
  String get worktreeStartConversation;

  /// No description provided for @worktreeCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get worktreeCreateAction;

  /// No description provided for @worktreeCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create worktree: {error}'**
  String worktreeCreateFailed(Object error);

  /// No description provided for @worktreeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove worktree'**
  String get worktreeDeleteTitle;

  /// No description provided for @worktreeDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove the worktree for {branch}?'**
  String worktreeDeleteBody(Object branch);

  /// No description provided for @worktreeDeleteForce.
  ///
  /// In en, this message translates to:
  /// **'Force-remove even if it has uncommitted changes'**
  String get worktreeDeleteForce;

  /// No description provided for @worktreeDeleteBranchToo.
  ///
  /// In en, this message translates to:
  /// **'Also delete the branch'**
  String get worktreeDeleteBranchToo;

  /// No description provided for @worktreeDeleteSessionsToo.
  ///
  /// In en, this message translates to:
  /// **'Also delete the {count} conversations in this worktree'**
  String worktreeDeleteSessionsToo(Object count);

  /// No description provided for @worktreeDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get worktreeDeleteAction;

  /// No description provided for @worktreeDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove worktree: {error}'**
  String worktreeDeleteFailed(Object error);

  /// No description provided for @worktreeOrphanGroup.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get worktreeOrphanGroup;

  /// No description provided for @worktreeNewWorktreeTooltip.
  ///
  /// In en, this message translates to:
  /// **'New worktree'**
  String get worktreeNewWorktreeTooltip;

  /// No description provided for @worktreeRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh worktrees'**
  String get worktreeRefreshTooltip;

  /// No description provided for @worktreeNewConversationHere.
  ///
  /// In en, this message translates to:
  /// **'New conversation here'**
  String get worktreeNewConversationHere;

  /// No description provided for @worktreeMenuCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get worktreeMenuCopyPath;

  /// No description provided for @worktreeMenuRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove worktree'**
  String get worktreeMenuRemove;

  /// No description provided for @worktreeShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String worktreeShowMore(Object count);

  /// No description provided for @worktreeShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get worktreeShowLess;

  /// No description provided for @worktreeDeleteBusyWarning.
  ///
  /// In en, this message translates to:
  /// **'Stop the running conversations in this worktree before removing it.'**
  String get worktreeDeleteBusyWarning;
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
