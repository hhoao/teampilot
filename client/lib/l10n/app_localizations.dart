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

  /// No description provided for @skillsNavBackups.
  ///
  /// In en, this message translates to:
  /// **'Backups'**
  String get skillsNavBackups;

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

  /// No description provided for @skillsRepoOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get skillsRepoOwner;

  /// No description provided for @skillsRepoName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get skillsRepoName;

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

  /// No description provided for @skillsBackupsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get skillsBackupsEmpty;

  /// No description provided for @skillsBackupRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get skillsBackupRestore;

  /// No description provided for @skillsBackupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get skillsBackupDelete;

  /// No description provided for @skillsBackupDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete backup {name}? This cannot be undone.'**
  String skillsBackupDeleteConfirm(String name);

  /// No description provided for @skillsBackupCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get skillsBackupCreatedAt;

  /// No description provided for @skillsUninstallConfirm.
  ///
  /// In en, this message translates to:
  /// **'Uninstall {name}? Files will be moved to backups.'**
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
  /// **'Preset built-in agents.'**
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

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select a model'**
  String get selectModel;

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
