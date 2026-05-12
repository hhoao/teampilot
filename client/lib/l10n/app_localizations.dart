import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this._strings);

  final Map<String, String> _strings;

  String get appTitle => _strings['appTitle']!;
  String get appRailChat => _strings['appRailChat']!;
  String get appRailRuns => _strings['appRailRuns']!;
  String get appRailConfig => _strings['appRailConfig']!;

  String get chatTo => _strings['chatTo']!;
  String get copyPrompt => _strings['copyPrompt']!;
  String get sendPrompt => _strings['sendPrompt']!;
  String get chatHintText => _strings['chatHintText']!;
  String get emptyTimeline => _strings['emptyTimeline']!;

  String get members => _strings['members']!;
  String get fileTree => _strings['fileTree']!;
  String get openTeam => _strings['openTeam']!;
  String get openMember => _strings['openMember']!;
  String get filterFiles => _strings['filterFiles']!;
  String get copy => _strings['copy']!;

  String get selectTeam => _strings['selectTeam']!;
  String get addTeamTooltip => _strings['addTeamTooltip']!;
  String get projects => _strings['projects']!;
  String get newProject => _strings['newProject']!;
  String get newSessionTooltip => _strings['newSessionTooltip']!;
  String get defaultNewChatSessionTitle =>
      _strings['defaultNewChatSessionTitle']!;
  String get openFolder => _strings['openFolder']!;
  String get copyFolderPath => _strings['copyFolderPath']!;
  String get deleteProject => _strings['deleteProject']!;
  String deleteProjectConfirm(String name) =>
      _strings['deleteProjectConfirm']!.replaceFirst('{name}', name);
  String get noSessions => _strings['noSessions']!;
  String get unknownFolder => _strings['unknownFolder']!;
  String get teamSessions => _strings['teamSessions']!;
  String get renameConversation => _strings['renameConversation']!;
  String get deleteConversation => _strings['deleteConversation']!;
  String get closeTab => _strings['closeTab']!;
  String get closeOtherTabs => _strings['closeOtherTabs']!;
  String get closeRightTabs => _strings['closeRightTabs']!;
  String get renameConversationTitle => _strings['renameConversationTitle']!;
  String deleteConversationConfirm(String name) =>
      _strings['deleteConversationConfirm']!.replaceFirst('{name}', name);
  String get conversationName => _strings['conversationName']!;
  String get settings => _strings['settings']!;
  String get settingsPageSubtitle => _strings['settingsPageSubtitle']!;
  String get configure => _strings['configure']!;
  String get teamConfig => _strings['teamConfig']!;
  String get teamSettings => _strings['teamSettings']!;
  String get teamSettingsSubtitle => _strings['teamSettingsSubtitle']!;
  String get membersSubtitle => _strings['membersSubtitle']!;
  String get llmConfig => _strings['llmConfig']!;
  String get llmConfigSubtitle => _strings['llmConfigSubtitle']!;
  String get llmConfigPathLabel => _strings['llmConfigPathLabel']!;
  String get llmConfigPathHint => _strings['llmConfigPathHint']!;
  String get llmConfigPathBrowse => _strings['llmConfigPathBrowse']!;
  String get llmConfigPathSave => _strings['llmConfigPathSave']!;
  String get llmConfigPathReset => _strings['llmConfigPathReset']!;
  String get llmConfigPathBadgeDefault =>
      _strings['llmConfigPathBadgeDefault']!;
  String get llmConfigPathBadgeCustom => _strings['llmConfigPathBadgeCustom']!;
  String get llmConfigPathPickerTitle =>
      _strings['llmConfigPathPickerTitle']!;
  String get layout => _strings['layout']!;
  String get layoutSubtitle => _strings['layoutSubtitle']!;
  String get memberQuickList => _strings['memberQuickList']!;
  String get providers => _strings['providers']!;
  String get shellChatWorkbench => _strings['shellChatWorkbench']!;

  String get teamName => _strings['teamName']!;
  String get teamExtraArgs => _strings['teamExtraArgs']!;
  String get teamExtraArgsHint => _strings['teamExtraArgsHint']!;
  String get teamLoop => _strings['teamLoop']!;
  String get teamLoopSubtitle => _strings['teamLoopSubtitle']!;
  String get teamLoopDefault => _strings['teamLoopDefault']!;
  String get teamLoopTrue => _strings['teamLoopTrue']!;
  String get teamLoopFalse => _strings['teamLoopFalse']!;
  String get memberLaunchOrder => _strings['memberLaunchOrder']!;
  String get save => _strings['save']!;
  String get editTeamSubtitle => _strings['editTeamSubtitle']!;

  String get memberName => _strings['memberName']!;
  String get provider => _strings['provider']!;
  String get model => _strings['model']!;
  String get agent => _strings['agent']!;
  String get selectAgent => _strings['selectAgent']!;
  String get agentBuiltInNone => _strings['agentBuiltInNone']!;
  String get agentBuiltInCustom => _strings['agentBuiltInCustom']!;
  String get agentBuiltInSubtitle => _strings['agentBuiltInSubtitle']!;
  String get agentCustomIdHint => _strings['agentCustomIdHint']!;
  String get memberExtraArgs => _strings['memberExtraArgs']!;
  String get memberDangerouslySkipPermissions =>
      _strings['memberDangerouslySkipPermissions']!;
  String get memberDangerouslySkipPermissionsHint =>
      _strings['memberDangerouslySkipPermissionsHint']!;
  String get prompt => _strings['prompt']!;
  String get selectModel => _strings['selectModel']!;
  String get editMemberSubtitle => _strings['editMemberSubtitle']!;
  String get saveMember => _strings['saveMember']!;
  String get teamLeadNameRequired => _strings['teamLeadNameRequired']!;
  String get teamLeadNotice => _strings['teamLeadNotice']!;

  String get layoutPageSubtitle => _strings['layoutPageSubtitle']!;
  String get toolPlacement => _strings['toolPlacement']!;
  String get right => _strings['right']!;
  String get bottom => _strings['bottom']!;
  String get rightTools => _strings['rightTools']!;
  String get bottomTray => _strings['bottomTray']!;
  String get membersAndFileTree => _strings['membersAndFileTree']!;
  String get stacked => _strings['stacked']!;
  String get tabs => _strings['tabs']!;
  String get stackedTools => _strings['stackedTools']!;
  String get tabbedTools => _strings['tabbedTools']!;
  String get regionVisibility => _strings['regionVisibility']!;
  String get appRail => _strings['appRail']!;
  String get toolPlacementDescription => _strings['toolPlacementDescription']!;
  String get membersAndFileTreeDescription =>
      _strings['membersAndFileTreeDescription']!;
  String get visibilityTeamSessionsHint =>
      _strings['visibilityTeamSessionsHint']!;
  String get visibilityMembersHint => _strings['visibilityMembersHint']!;
  String get visibilityFileTreeHint => _strings['visibilityFileTreeHint']!;
  String get shellSession => _strings['shellSession']!;
  String get autoLaunchAllMembersTitle =>
      _strings['autoLaunchAllMembersTitle']!;
  String get autoLaunchAllMembersDescription =>
      _strings['autoLaunchAllMembersDescription']!;
  String get themeModeTitle => _strings['themeModeTitle']!;
  String get themeModeDescription => _strings['themeModeDescription']!;
  String get languageDescription => _strings['languageDescription']!;

  String get llmConfigPageSubtitle => _strings['llmConfigPageSubtitle']!;
  String get providersTab => _strings['providersTab']!;
  String get modelsTab => _strings['modelsTab']!;
  String get rawJsonTab => _strings['rawJsonTab']!;
  String get addProvider => _strings['addProvider']!;
  String get providerName => _strings['providerName']!;
  String get cancel => _strings['cancel']!;
  String get add => _strings['add']!;
  String get delete => _strings['delete']!;
  String get deleteProvider => _strings['deleteProvider']!;
  String deleteProviderConfirm(String name) =>
      _strings['deleteProviderConfirm']!.replaceFirst('{name}', name);
  String get providerList => _strings['providerList']!;
  String get filterProviders => _strings['filterProviders']!;
  String modelsUsingProvider(int count) =>
      '${_strings['modelsUsingProvider']!} $count';
  String providerListCaption(int modelCount, bool proxyEnabled) {
    final countPart = _strings['providerListModelCount']!.replaceFirst(
      '{n}',
      '$modelCount',
    );
    final proxyPart = proxyEnabled
        ? _strings['proxyOnShort']!
        : _strings['proxyOffShort']!;
    return '$countPart · $proxyPart';
  }

  String providerDetailSubtitle(String typeLabel, int count) =>
      _strings['providerDetailSubtitle']!
          .replaceFirst('{type}', typeLabel)
          .replaceFirst('{count}', '$count');
  String get type => _strings['type']!;
  String get providerType => _strings['providerType']!;
  String get providerTypeHint => _strings['providerTypeHint']!;
  String get proxy => _strings['proxy']!;
  String get proxyUrl => _strings['proxyUrl']!;
  String get baseUrl => _strings['baseUrl']!;
  String get apiKey => _strings['apiKey']!;
  String get reveal => _strings['reveal']!;
  String get hide => _strings['hide']!;
  String get replaceKey => _strings['replaceKey']!;
  String get deleteProviderTooltip => _strings['deleteProviderTooltip']!;
  String get noModelsUsingProvider => _strings['noModelsUsingProvider']!;
  String get modelsUsingProviderTitle => _strings['modelsUsingProviderTitle']!;
  String get selectProvider => _strings['selectProvider']!;
  String get accountCredentialPath => _strings['accountCredentialPath']!;
  String get removePath => _strings['removePath']!;
  String get addAccountPath => _strings['addAccountPath']!;
  String get api => _strings['api']!;
  String get account => _strings['account']!;

  String get models => _strings['models']!;
  String get addModel => _strings['addModel']!;
  String get modelName => _strings['modelName']!;
  String get modelId => _strings['modelId']!;
  String get enabled => _strings['enabled']!;
  String get edit => _strings['edit']!;
  String editModelTitle(String name) =>
      _strings['editModelTitle']!.replaceFirst('{name}', name);
  String get name => _strings['name']!;
  String get actualModel => _strings['actualModel']!;
  String get noModelsConfigured => _strings['noModelsConfigured']!;
  String get missingProvider => _strings['missingProvider']!;

  String get summary => _strings['summary']!;
  String get statProviders => _strings['statProviders']!;
  String get statModels => _strings['statModels']!;
  String get statMissingRefs => _strings['statMissingRefs']!;
  String get statEmptyKeys => _strings['statEmptyKeys']!;
  String get validation => _strings['validation']!;
  String get allChecksPassed => _strings['allChecksPassed']!;
  String get validate => _strings['validate']!;
  String get back => _strings['back']!;
  String get jsonPreview => _strings['jsonPreview']!;

  String get runsPlaceholder => _strings['runsPlaceholder']!;

  String get appearance => _strings['appearance']!;
  String get theme => _strings['theme']!;
  String get themeSystem => _strings['themeSystem']!;
  String get themeDark => _strings['themeDark']!;
  String get themeLight => _strings['themeLight']!;
  String get language => _strings['language']!;
  String get languageEnglish => _strings['languageEnglish']!;
  String get languageChinese => _strings['languageChinese']!;

  // Skills
  String get skillsTitle => _strings['skillsTitle']!;
  String get skillsSubtitle => _strings['skillsSubtitle']!;
  String get skillsSidebarLabel => _strings['skillsSidebarLabel']!;
  String get skillsNavInstalled => _strings['skillsNavInstalled']!;
  String get skillsNavDiscovery => _strings['skillsNavDiscovery']!;
  String get skillsNavRepos => _strings['skillsNavRepos']!;
  String get skillsNavBackups => _strings['skillsNavBackups']!;
  String skillsInstalledCount(int count) =>
      _strings['skillsInstalledCount']!.replaceFirst('{count}', '$count');
  String get skillsCheckUpdates => _strings['skillsCheckUpdates']!;
  String get skillsCheckingUpdates => _strings['skillsCheckingUpdates']!;
  String skillsUpdateAll(int count) =>
      _strings['skillsUpdateAll']!.replaceFirst('{count}', '$count');
  String get skillsImportFromDisk => _strings['skillsImportFromDisk']!;
  String get skillsInstallFromZip => _strings['skillsInstallFromZip']!;
  String get skillsNoInstalled => _strings['skillsNoInstalled']!;
  String get skillsNoInstalledHint => _strings['skillsNoInstalledHint']!;
  String get skillsGoDiscovery => _strings['skillsGoDiscovery']!;
  String get skillsSourceRepos => _strings['skillsSourceRepos']!;
  String get skillsSourceSkillsSh => _strings['skillsSourceSkillsSh']!;
  String get skillsSearchPlaceholder => _strings['skillsSearchPlaceholder']!;
  String get skillsSkillsShPlaceholder =>
      _strings['skillsSkillsShPlaceholder']!;
  String get skillsFilterRepoAll => _strings['skillsFilterRepoAll']!;
  String get skillsFilterAll => _strings['skillsFilterAll']!;
  String get skillsFilterInstalled => _strings['skillsFilterInstalled']!;
  String get skillsFilterUninstalled => _strings['skillsFilterUninstalled']!;
  String get skillsCardInstall => _strings['skillsCardInstall']!;
  String get skillsCardInstalled => _strings['skillsCardInstalled']!;
  String get skillsCardUpdate => _strings['skillsCardUpdate']!;
  String get skillsCardUninstall => _strings['skillsCardUninstall']!;
  String get skillsUpdateAvailable => _strings['skillsUpdateAvailable']!;
  String get skillsLocal => _strings['skillsLocal']!;
  String get skillsReposEmpty => _strings['skillsReposEmpty']!;
  String get skillsRepoAdd => _strings['skillsRepoAdd']!;
  String get skillsRepoOwner => _strings['skillsRepoOwner']!;
  String get skillsRepoName => _strings['skillsRepoName']!;
  String get skillsRepoBranch => _strings['skillsRepoBranch']!;
  String get skillsRepoRemove => _strings['skillsRepoRemove']!;
  String skillsRepoRemoveConfirm(String name) =>
      _strings['skillsRepoRemoveConfirm']!.replaceFirst('{name}', name);
  String get skillsBackupsEmpty => _strings['skillsBackupsEmpty']!;
  String get skillsBackupRestore => _strings['skillsBackupRestore']!;
  String get skillsBackupDelete => _strings['skillsBackupDelete']!;
  String skillsBackupDeleteConfirm(String name) =>
      _strings['skillsBackupDeleteConfirm']!.replaceFirst('{name}', name);
  String get skillsBackupCreatedAt => _strings['skillsBackupCreatedAt']!;
  String skillsUninstallConfirm(String name) =>
      _strings['skillsUninstallConfirm']!.replaceFirst('{name}', name);
  String skillsOverwriteConfirm(String name) =>
      _strings['skillsOverwriteConfirm']!.replaceFirst('{name}', name);
  String skillsInstallSuccess(String name) =>
      _strings['skillsInstallSuccess']!.replaceFirst('{name}', name);
  String skillsUninstallSuccess(String name) =>
      _strings['skillsUninstallSuccess']!.replaceFirst('{name}', name);
  String skillsUpdateSuccess(String name) =>
      _strings['skillsUpdateSuccess']!.replaceFirst('{name}', name);
  String get skillsNoUpdates => _strings['skillsNoUpdates']!;
  String get skillsImportTitle => _strings['skillsImportTitle']!;
  String get skillsImportNothing => _strings['skillsImportNothing']!;
  String skillsImportSelected(int count) =>
      _strings['skillsImportSelected']!.replaceFirst('{count}', '$count');
  String get skillsZipNoSkills => _strings['skillsZipNoSkills']!;
  String get skillsSkillsShLoadMore => _strings['skillsSkillsShLoadMore']!;
  String get skillsSkillsShPoweredBy => _strings['skillsSkillsShPoweredBy']!;
  String get skillsSkillsShSearch => _strings['skillsSkillsShSearch']!;
  String get skillsDiscoveryEmpty => _strings['skillsDiscoveryEmpty']!;
  String get skillsDiscoveryEmptyHint => _strings['skillsDiscoveryEmptyHint']!;
  String get skillsAdd => _strings['skillsAdd']!;
  String get skillsRemove => _strings['skillsRemove']!;
  String get skillsEnabled => _strings['skillsEnabled']!;
  String skillsInstalls(int count) =>
      _strings['skillsInstalls']!.replaceFirst('{count}', '$count');

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const delegate = _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  static const _supportedLocales = [Locale('en'), Locale('zh')];

  static const _strings = <String, Map<String, String>>{
    'appTitle': {'en': 'FlashskyAI Teams', 'zh': 'FlashskyAI 团队'},
    'appRailChat': {'en': 'Chat', 'zh': '聊天'},
    'appRailRuns': {'en': 'Runs', 'zh': '运行'},
    'appRailConfig': {'en': 'Config', 'zh': '配置'},

    'chatTo': {'en': 'To:', 'zh': '发送至：'},
    'copyPrompt': {'en': 'Copy prompt', 'zh': '复制提示'},
    'sendPrompt': {'en': 'Send prompt', 'zh': '发送提示'},
    'chatHintText': {
      'en': 'Write a prompt for team-lead...',
      'zh': '为 team-lead 编写提示...',
    },
    'emptyTimeline': {
      'en': 'Local shell-mode conversation notes will appear here.',
      'zh': '本地 shell 模式对话记录将显示在此处。',
    },

    'members': {'en': 'Members', 'zh': '成员'},
    'fileTree': {'en': 'File Tree', 'zh': '文件树'},
    'openTeam': {'en': 'Open Team', 'zh': '打开团队'},
    'openMember': {'en': 'Open member', 'zh': '打开成员'},
    'filterFiles': {'en': 'Filter files', 'zh': '筛选文件'},
    'copy': {'en': 'copy', 'zh': '复制'},

    'selectTeam': {'en': 'Select team', 'zh': '选择团队'},
    'addTeamTooltip': {'en': 'Add team', 'zh': '添加团队'},
    'projects': {'en': 'Projects', 'zh': '项目'},
    'newProject': {'en': 'New Project', 'zh': '新建项目'},
    'newSessionTooltip': {'en': 'New session', 'zh': '新建会话'},
    'defaultNewChatSessionTitle': {
      'en': 'New Chat',
      'zh': '新对话',
    },
    'openFolder': {'en': 'Open Folder', 'zh': '打开文件夹'},
    'copyFolderPath': {'en': 'Copy Folder Path', 'zh': '复制文件夹路径'},
    'deleteProject': {'en': 'Delete Project', 'zh': '删除项目'},
    'deleteProjectConfirm': {
      'en':
          'Delete project "{name}" and all its sessions? This cannot be undone.',
      'zh': '删除项目 "{name}" 及其所有会话？此操作不可撤销。',
    },
    'noSessions': {'en': 'No sessions yet', 'zh': '暂无会话'},
    'unknownFolder': {'en': 'Unknown', 'zh': '未知'},
    'teamSessions': {'en': 'Team Sessions', 'zh': '团队会话'},
    'renameConversation': {'en': 'Rename conversation', 'zh': '重命名对话'},
    'deleteConversation': {'en': 'Delete conversation', 'zh': '删除对话'},
    'renameConversationTitle': {'en': 'Rename Conversation', 'zh': '重命名对话'},
    'deleteConversationConfirm': {
      'en': 'Delete conversation "{name}"? This cannot be undone.',
      'zh': '删除对话 "{name}"？此操作不可撤销。',
    },
    'conversationName': {'en': 'Conversation name', 'zh': '对话名称'},
    'closeTab': {'en': 'Close', 'zh': '关闭'},
    'closeOtherTabs': {'en': 'Close Others', 'zh': '关闭其他标签'},
    'closeRightTabs': {'en': 'Close to the Right', 'zh': '关闭右侧标签'},
    'settings': {'en': 'Settings', 'zh': '设置'},
    'settingsPageSubtitle': {
      'en': 'Manage FlashskyAI team and model settings.',
      'zh': '管理 FlashskyAI 团队和模型设置。',
    },
    'configure': {'en': 'Configure', 'zh': '配置'},
    'teamConfig': {'en': 'Team Config', 'zh': '团队配置'},
    'teamSettings': {'en': 'Team Settings', 'zh': '团队设置'},
    'teamSettingsSubtitle': {'en': 'workspace teams', 'zh': '工作区团队'},
    'membersSubtitle': {'en': 'team agents', 'zh': '团队代理'},
    'llmConfig': {'en': 'Provider', 'zh': '服务商'},
    'llmConfigSubtitle': {'en': 'providers and models', 'zh': '提供商和模型'},
    'llmConfigPathLabel': {
      'en': 'LLM config file',
      'zh': 'LLM 配置文件',
    },
    'llmConfigPathHint': {
      'en': 'Leave empty to use the default path',
      'zh': '留空则使用默认路径',
    },
    'llmConfigPathBrowse': {'en': 'Browse...', 'zh': '浏览...'},
    'llmConfigPathSave': {'en': 'Apply', 'zh': '应用'},
    'llmConfigPathReset': {'en': 'Use default', 'zh': '使用默认'},
    'llmConfigPathBadgeDefault': {'en': 'default', 'zh': '默认'},
    'llmConfigPathBadgeCustom': {'en': 'custom', 'zh': '自定义'},
    'llmConfigPathPickerTitle': {
      'en': 'Select llm_config.json',
      'zh': '选择 llm_config.json',
    },
    'layout': {'en': 'Layout', 'zh': '通用'},
    'layoutSubtitle': {'en': 'global workbench', 'zh': '全局工作台'},
    'memberQuickList': {'en': 'MEMBER QUICK LIST', 'zh': '成员快速列表'},
    'providers': {'en': 'PROVIDERS', 'zh': '提供商'},
    'shellChatWorkbench': {'en': 'Shell chat workbench', 'zh': 'Shell 聊天工作台'},

    'teamName': {'en': 'Team name', 'zh': '团队名称'},
    'teamExtraArgs': {'en': 'Team extra CLI arguments', 'zh': '团队额外 CLI 参数'},
    'teamExtraArgsHint': {
      'en': '--permission-mode acceptEdits',
      'zh': '--permission-mode acceptEdits',
    },
    'teamLoop': {
      'en': 'Phase loop',
      'zh': '阶段循环',
    },
    'teamLoopSubtitle': {
      'en':
          'Team mode: true auto-advances phases; false requires your confirmation.',
      'zh': '团队模式：true 自动推进阶段；false 需你确认后再继续。',
    },
    'teamLoopDefault': {
      'en': 'Default',
      'zh': '默认',
    },
    'teamLoopTrue': {
      'en': 'true — auto-advance',
      'zh': 'true — 自动推进',
    },
    'teamLoopFalse': {
      'en': 'false — confirm each phase',
      'zh': 'false — 每阶段确认',
    },
    'memberLaunchOrder': {'en': 'Member launch order', 'zh': '成员启动顺序'},
    'save': {'en': 'Save', 'zh': '保存'},
    'saveMember': {'en': 'Save Member', 'zh': '保存成员'},
    'editTeamSubtitle': {
      'en': 'Edit team identity, working directory, and launch order.',
      'zh': '编辑团队标识、工作目录和启动顺序。',
    },

    'memberName': {'en': 'Member name', 'zh': '成员名称'},
    'provider': {'en': 'Provider', 'zh': '提供商'},
    'model': {'en': 'Model', 'zh': '模型'},
    'agent': {'en': 'Agent', 'zh': '代理'},
    'selectAgent': {
      'en': 'Select an agent',
      'zh': '选择 Agent',
    },
    'agentBuiltInNone': {
      'en': 'Default',
      'zh': '默认',
    },
    'agentBuiltInCustom': {
      'en': 'Custom…',
      'zh': '自定义…',
    },
    'agentBuiltInSubtitle': {
      'en': 'Preset built-in agents.',
      'zh': '内置预设 Agent。',
    },
    'agentCustomIdHint': {
      'en': 'Custom agent id',
      'zh': '自定义 Agent 标识',
    },
    'memberExtraArgs': {
      'en': 'Member extra CLI arguments',
      'zh': '成员额外 CLI 参数',
    },
    'memberDangerouslySkipPermissions': {
      'en': 'Skip all permission checks',
      'zh': '跳过所有权限检查',
    },
    'memberDangerouslySkipPermissionsHint': {
      'en': 'Only for isolated / no-network sandboxes. Extremely risky otherwise.',
      'zh': '仅限隔离或无网络沙箱使用，否则风险极高。',
    },
    'prompt': {'en': 'Prompt', 'zh': '提示词'},
    'selectModel': {'en': 'Select a model', 'zh': '选择一个模型'},
    'editMemberSubtitle': {
      'en': 'Edit provider, model, agent, and command arguments.',
      'zh': '编辑提供商、模型、代理和命令参数。',
    },
    'teamLeadNameRequired': {
      'en':
          'FlashskyAI team delegation expects this member to be named exactly team-lead.',
      'zh': 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。',
    },
    'teamLeadNotice': {
      'en':
          'FlashskyAI team delegation expects this member to be named exactly team-lead.',
      'zh': 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。',
    },

    'layoutPageSubtitle': {
      'en': 'Structure controls are global and apply across teams.',
      'zh': '结构控件为全局设置，适用于所有团队。',
    },
    'toolPlacement': {'en': 'Tool Placement', 'zh': '工具栏位置'},
    'right': {'en': 'Right', 'zh': '右侧'},
    'bottom': {'en': 'Bottom', 'zh': '底部'},
    'rightTools': {'en': 'Right Tools', 'zh': '右侧工具栏'},
    'bottomTray': {'en': 'Bottom Tray', 'zh': '底部托盘'},
    'membersAndFileTree': {'en': 'Members and File Tree', 'zh': '成员和文件树'},
    'stacked': {'en': 'Stacked', 'zh': '堆叠'},
    'tabs': {'en': 'Tabs', 'zh': '标签页'},
    'stackedTools': {'en': 'Stacked Tools', 'zh': '堆叠工具栏'},
    'tabbedTools': {'en': 'Tabbed Tools', 'zh': '标签工具栏'},
    'regionVisibility': {'en': 'Region Visibility', 'zh': '区域可见性'},
    'appRail': {'en': 'App rail', 'zh': '应用导航栏'},
    'toolPlacementDescription': {
      'en': 'Dock tool panels on the right or along the bottom edge.',
      'zh': '将工具面板固定在右侧或沿底部边缘排列。',
    },
    'membersAndFileTreeDescription': {
      'en': 'Show members and file tree stacked or as tabs.',
      'zh': '将成员列表与文件树堆叠显示，或以标签页切换。',
    },
    'visibilityTeamSessionsHint': {
      'en': 'Show the team sessions list in the left sidebar.',
      'zh': '在左侧边栏显示团队会话列表。',
    },
    'visibilityMembersHint': {
      'en': 'Show the member list next to tools or terminals.',
      'zh': '在工具或终端旁显示成员列表。',
    },
    'visibilityFileTreeHint': {
      'en': 'Show the project file tree for quick navigation.',
      'zh': '显示项目文件树以便快速浏览。',
    },
    'shellSession': {'en': 'Shell session', 'zh': 'Shell 会话'},
    'autoLaunchAllMembersTitle': {
      'en': 'Start all members on connect',
      'zh': '连接时启动全部成员',
    },
    'autoLaunchAllMembersDescription': {
      'en':
          'When enabled, Connect and Restart launch every valid member shell; otherwise only the selected member starts.',
      'zh':
          '开启后，点击连接或重启会为每个有效成员启动终端；关闭则仅启动当前选中的成员。',
    },
    'themeModeTitle': {'en': 'Theme mode', 'zh': '主题模式'},
    'themeModeDescription': {
      'en': 'Light, dark, or match the operating system appearance.',
      'zh': '浅色、深色，或与系统外观一致。',
    },
    'languageDescription': {
      'en': 'Language used for menus, buttons, and labels.',
      'zh': '菜单、按钮与标签所使用的语言。',
    },

    'llmConfigPageSubtitle': {
      'en': 'Manage LLM providers and models.',
      'zh': '管理 LLM 提供商和模型。',
    },
    'providersTab': {'en': 'Providers', 'zh': '提供商'},
    'modelsTab': {'en': 'Models', 'zh': '模型'},
    'rawJsonTab': {'en': 'Raw JSON', 'zh': '原始 JSON'},
    'addProvider': {'en': 'Add Provider', 'zh': '添加提供商'},
    'providerName': {'en': 'Provider name', 'zh': '提供商名称'},
    'cancel': {'en': 'Cancel', 'zh': '取消'},
    'add': {'en': 'Add', 'zh': '添加'},
    'delete': {'en': 'Delete', 'zh': '删除'},
    'deleteProvider': {'en': 'Delete Provider', 'zh': '删除提供商'},
    'deleteProviderConfirm': {
      'en': 'Delete provider {name}?',
      'zh': '删除提供商 {name}？',
    },
    'providerList': {'en': 'Provider List', 'zh': '提供商列表'},
    'filterProviders': {'en': 'Filter providers...', 'zh': '筛选提供商...'},
    'modelsUsingProvider': {
      'en': 'Models using this provider:',
      'zh': '使用此提供商的模型：',
    },
    'providerListModelCount': {'en': '{n} models', 'zh': '{n} 个模型'},
    'proxyOnShort': {'en': 'Proxy on', 'zh': '代理开'},
    'proxyOffShort': {'en': 'Proxy off', 'zh': '代理关'},
    'providerDetailSubtitle': {
      'en': '{type} provider · {count} models',
      'zh': '{type} 提供商 · {count} 个模型',
    },
    'type': {'en': 'Type', 'zh': '类型'},
    'providerType': {'en': 'Provider type', 'zh': '提供商类型'},
    'providerTypeHint': {
      'en': 'openai, claude, or custom',
      'zh': 'openai, claude 或自定义',
    },
    'proxy': {'en': 'Proxy', 'zh': '代理'},
    'proxyUrl': {'en': 'Proxy URL', 'zh': '代理 URL'},
    'baseUrl': {'en': 'Base URL', 'zh': '基础 URL'},
    'apiKey': {'en': 'API Key', 'zh': 'API 密钥'},
    'reveal': {'en': 'Reveal', 'zh': '显示'},
    'hide': {'en': 'Hide', 'zh': '隐藏'},
    'replaceKey': {'en': 'Replace key', 'zh': '替换密钥'},
    'deleteProviderTooltip': {'en': 'Delete provider', 'zh': '删除提供商'},
    'noModelsUsingProvider': {
      'en': 'No models are using this provider.',
      'zh': '没有模型使用此提供商。',
    },
    'modelsUsingProviderTitle': {
      'en': 'Models using this provider',
      'zh': '使用此提供商的模型',
    },
    'selectProvider': {
      'en': 'Select a provider from the list',
      'zh': '从列表中选择一个提供商',
    },
    'accountCredentialPath': {'en': 'Account credential path', 'zh': '账户凭证路径'},
    'removePath': {'en': 'Remove path', 'zh': '移除路径'},
    'addAccountPath': {'en': 'Add account path', 'zh': '添加账户路径'},
    'api': {'en': 'api', 'zh': 'api'},
    'account': {'en': 'account', 'zh': 'account'},

    'models': {'en': 'Models', 'zh': '模型'},
    'addModel': {'en': 'Add Model', 'zh': '添加模型'},
    'modelName': {'en': 'Model alias/name', 'zh': '模型别名/名称'},
    'modelId': {'en': 'Model ID', 'zh': '模型 ID'},
    'enabled': {'en': 'Enabled', 'zh': '启用'},
    'edit': {'en': 'Edit', 'zh': '编辑'},
    'editModelTitle': {'en': 'Edit {name}', 'zh': '编辑 {name}'},
    'name': {'en': 'Name', 'zh': '名称'},
    'actualModel': {'en': 'Actual Model', 'zh': '实际模型'},
    'noModelsConfigured': {'en': 'No models configured', 'zh': '未配置模型'},
    'missingProvider': {'en': 'Missing provider:', 'zh': '缺少提供商：'},

    'summary': {'en': 'Summary', 'zh': '摘要'},
    'statProviders': {'en': 'providers', 'zh': '个提供商'},
    'statModels': {'en': 'models', 'zh': '个模型'},
    'statMissingRefs': {'en': 'missing refs', 'zh': '缺失引用'},
    'statEmptyKeys': {'en': 'empty keys', 'zh': '空密钥'},
    'validation': {'en': 'Validation', 'zh': '验证'},
    'allChecksPassed': {'en': 'All checks passed.', 'zh': '所有检查通过。'},
    'validate': {'en': 'Validate', 'zh': '校验'},
    'back': {'en': 'Back', 'zh': '返回'},
    'jsonPreview': {'en': 'JSON Preview', 'zh': 'JSON 预览'},

    'runsPlaceholder': {
      'en': 'Run history will appear here.',
      'zh': '运行历史将显示在此处。',
    },
    'appearance': {'en': 'Appearance', 'zh': '外观'},
    'theme': {'en': 'Theme', 'zh': '主题'},
    'themeSystem': {'en': 'System', 'zh': '跟随系统'},
    'themeDark': {'en': 'Dark', 'zh': '深色'},
    'themeLight': {'en': 'Light', 'zh': '浅色'},
    'language': {'en': 'Language', 'zh': '语言'},
    'languageEnglish': {'en': 'English', 'zh': 'English'},
    'languageChinese': {'en': '中文', 'zh': '中文'},

    // Skills
    'skillsTitle': {'en': 'Skills', 'zh': 'Skills'},
    'skillsSubtitle': {'en': 'Manage installable skills', 'zh': '管理可安装的 Skill'},
    'skillsSidebarLabel': {'en': 'Skills', 'zh': 'Skills'},
    'skillsNavInstalled': {'en': 'Installed', 'zh': '已安装'},
    'skillsNavDiscovery': {'en': 'Discovery', 'zh': '发现'},
    'skillsNavRepos': {'en': 'Repos', 'zh': '仓库'},
    'skillsNavBackups': {'en': 'Backups', 'zh': '备份'},
    'skillsInstalledCount': {'en': '{count} installed', 'zh': '已安装 {count}'},
    'skillsCheckUpdates': {'en': 'Check updates', 'zh': '检查更新'},
    'skillsCheckingUpdates': {'en': 'Checking…', 'zh': '检查中…'},
    'skillsUpdateAll': {'en': 'Update all ({count})', 'zh': '全部更新 ({count})'},
    'skillsImportFromDisk': {'en': 'Import from disk', 'zh': '从磁盘导入'},
    'skillsInstallFromZip': {'en': 'Install from ZIP', 'zh': '从 ZIP 安装'},
    'skillsNoInstalled': {'en': 'No skills installed yet', 'zh': '还没有安装 Skill'},
    'skillsNoInstalledHint': {
      'en': 'Open Discovery to install your first skill.',
      'zh': '打开发现页安装你的第一个 Skill。',
    },
    'skillsGoDiscovery': {'en': 'Go to Discovery', 'zh': '前往发现'},
    'skillsSourceRepos': {'en': 'Repos', 'zh': '仓库'},
    'skillsSourceSkillsSh': {'en': 'skills.sh', 'zh': 'skills.sh'},
    'skillsSearchPlaceholder': {'en': 'Search skills…', 'zh': '搜索 Skill…'},
    'skillsSkillsShPlaceholder': {
      'en': 'Search skills.sh (≥ 2 chars)…',
      'zh': '搜索 skills.sh (≥2 字)…',
    },
    'skillsFilterRepoAll': {'en': 'All repos', 'zh': '所有仓库'},
    'skillsFilterAll': {'en': 'All', 'zh': '全部'},
    'skillsFilterInstalled': {'en': 'Installed', 'zh': '已安装'},
    'skillsFilterUninstalled': {'en': 'Not installed', 'zh': '未安装'},
    'skillsCardInstall': {'en': 'Install', 'zh': '安装'},
    'skillsCardInstalled': {'en': 'Installed', 'zh': '已安装'},
    'skillsCardUpdate': {'en': 'Update', 'zh': '更新'},
    'skillsCardUninstall': {'en': 'Uninstall', 'zh': '卸载'},
    'skillsUpdateAvailable': {'en': 'Update available', 'zh': '有新版本'},
    'skillsLocal': {'en': 'local', 'zh': '本地'},
    'skillsReposEmpty': {'en': 'No repos yet', 'zh': '暂无仓库'},
    'skillsRepoAdd': {'en': 'Add repo', 'zh': '添加仓库'},
    'skillsRepoOwner': {'en': 'Owner', 'zh': 'Owner'},
    'skillsRepoName': {'en': 'Name', 'zh': '名称'},
    'skillsRepoBranch': {'en': 'Branch', 'zh': '分支'},
    'skillsRepoRemove': {'en': 'Remove', 'zh': '移除'},
    'skillsRepoRemoveConfirm': {
      'en': 'Remove repo {name}?',
      'zh': '确认移除仓库 {name}？',
    },
    'skillsBackupsEmpty': {'en': 'No backups yet', 'zh': '暂无备份'},
    'skillsBackupRestore': {'en': 'Restore', 'zh': '恢复'},
    'skillsBackupDelete': {'en': 'Delete', 'zh': '删除'},
    'skillsBackupDeleteConfirm': {
      'en': 'Delete backup {name}? This cannot be undone.',
      'zh': '删除备份 {name}？此操作不可撤销。',
    },
    'skillsBackupCreatedAt': {'en': 'Created at', 'zh': '创建时间'},
    'skillsUninstallConfirm': {
      'en': 'Uninstall {name}? Files will be moved to backups.',
      'zh': '卸载 {name}？文件会移入备份目录。',
    },
    'skillsOverwriteConfirm': {
      'en': '{name} already installed. Overwrite?',
      'zh': '{name} 已安装。是否覆盖？',
    },
    'skillsInstallSuccess': {'en': 'Installed {name}', 'zh': '已安装 {name}'},
    'skillsUninstallSuccess': {'en': 'Uninstalled {name}', 'zh': '已卸载 {name}'},
    'skillsUpdateSuccess': {'en': 'Updated {name}', 'zh': '已更新 {name}'},
    'skillsNoUpdates': {
      'en': 'All skills are up to date',
      'zh': '所有 Skill 均为最新',
    },
    'skillsImportTitle': {
      'en': 'Import unmanaged skills',
      'zh': '导入未管理的 Skill',
    },
    'skillsImportNothing': {
      'en': 'No unmanaged skills found.',
      'zh': '未发现未管理的 Skill。',
    },
    'skillsImportSelected': {
      'en': 'Import {count} selected',
      'zh': '导入选中 {count} 个',
    },
    'skillsZipNoSkills': {
      'en': 'No SKILL.md found in the archive.',
      'zh': '压缩包中未发现 SKILL.md。',
    },
    'skillsSkillsShLoadMore': {'en': 'Load more', 'zh': '加载更多'},
    'skillsSkillsShPoweredBy': {
      'en': 'Powered by skills.sh',
      'zh': '由 skills.sh 提供',
    },
    'skillsSkillsShSearch': {'en': 'Search', 'zh': '搜索'},
    'skillsDiscoveryEmpty': {'en': 'No skills discovered', 'zh': '未发现可用 Skill'},
    'skillsDiscoveryEmptyHint': {
      'en': 'Add a repo or try skills.sh to find skills.',
      'zh': '添加仓库或试用 skills.sh 来发现 Skill。',
    },
    'skillsAdd': {'en': 'Add', 'zh': '添加'},
    'skillsRemove': {'en': 'Remove', 'zh': '移除'},
    'skillsEnabled': {'en': 'Enabled', 'zh': '启用'},
    'skillsInstalls': {'en': '{count} installs', 'zh': '{count} 次安装'},
  };

  @override
  bool isSupported(Locale locale) =>
      _supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final langCode =
        _supportedLocales.any((l) => l.languageCode == locale.languageCode)
        ? locale.languageCode
        : 'en';
    final strings = <String, String>{};
    for (final entry in _strings.entries) {
      strings[entry.key] = entry.value[langCode] ?? entry.value['en'] ?? '';
    }
    return Future.value(AppLocalizations(strings));
  }

  @override
  bool shouldReload(covariant _AppLocalizationsDelegate old) => false;
}

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
