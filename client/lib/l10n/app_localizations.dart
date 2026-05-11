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
  String get teamSessions => _strings['teamSessions']!;
  String get renameConversation => _strings['renameConversation']!;
  String get deleteConversation => _strings['deleteConversation']!;
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
  String get layout => _strings['layout']!;
  String get layoutSubtitle => _strings['layoutSubtitle']!;
  String get memberQuickList => _strings['memberQuickList']!;
  String get providers => _strings['providers']!;
  String get shellChatWorkbench => _strings['shellChatWorkbench']!;

  String get teamName => _strings['teamName']!;
  String get workingDirectory => _strings['workingDirectory']!;
  String get teamExtraArgs => _strings['teamExtraArgs']!;
  String get teamExtraArgsHint => _strings['teamExtraArgsHint']!;
  String get memberLaunchOrder => _strings['memberLaunchOrder']!;
  String get save => _strings['save']!;
  String get editTeamSubtitle => _strings['editTeamSubtitle']!;

  String get memberName => _strings['memberName']!;
  String get provider => _strings['provider']!;
  String get model => _strings['model']!;
  String get agent => _strings['agent']!;
  String get memberExtraArgs => _strings['memberExtraArgs']!;
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
    'teamSessions': {'en': 'Team Sessions', 'zh': '团队会话'},
    'renameConversation': {'en': 'Rename conversation', 'zh': '重命名对话'},
    'deleteConversation': {'en': 'Delete conversation', 'zh': '删除对话'},
    'renameConversationTitle': {
      'en': 'Rename Conversation',
      'zh': '重命名对话',
    },
    'deleteConversationConfirm': {
      'en': 'Delete conversation "{name}"? This cannot be undone.',
      'zh': '删除对话 "{name}"？此操作不可撤销。',
    },
    'conversationName': {'en': 'Conversation name', 'zh': '对话名称'},
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
    'llmConfig': {'en': 'LLM Config', 'zh': 'LLM 配置'},
    'llmConfigSubtitle': {'en': 'providers and models', 'zh': '提供商和模型'},
    'layout': {'en': 'Layout', 'zh': '布局'},
    'layoutSubtitle': {'en': 'global workbench', 'zh': '全局工作台'},
    'memberQuickList': {'en': 'MEMBER QUICK LIST', 'zh': '成员快速列表'},
    'providers': {'en': 'PROVIDERS', 'zh': '提供商'},
    'shellChatWorkbench': {'en': 'Shell chat workbench', 'zh': 'Shell 聊天工作台'},

    'teamName': {'en': 'Team name', 'zh': '团队名称'},
    'workingDirectory': {'en': 'Working directory', 'zh': '工作目录'},
    'teamExtraArgs': {'en': 'Team extra CLI arguments', 'zh': '团队额外 CLI 参数'},
    'teamExtraArgsHint': {
      'en': '--permission-mode acceptEdits',
      'zh': '--permission-mode acceptEdits',
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
    'memberExtraArgs': {
      'en': 'Member extra CLI arguments',
      'zh': '成员额外 CLI 参数',
    },
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
