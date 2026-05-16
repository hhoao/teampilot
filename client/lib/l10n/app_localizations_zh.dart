// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'TeamPilot';

  @override
  String get appRailChat => '聊天';

  @override
  String get appRailRuns => '运行';

  @override
  String get appRailConfig => '配置';

  @override
  String get copy => '复制';

  @override
  String get settings => '设置';

  @override
  String get settingsPageSubtitle => '管理 FlashskyAI 团队和模型设置。';

  @override
  String get layout => '通用';

  @override
  String get layoutSubtitle => '全局工作台';

  @override
  String get save => '保存';

  @override
  String get layoutPageSubtitle => '结构控件为全局设置，适用于所有团队。';

  @override
  String get toolPlacement => '工具栏位置';

  @override
  String get right => '右侧';

  @override
  String get bottom => '底部';

  @override
  String get rightTools => '右侧工具栏';

  @override
  String get bottomTray => '底部托盘';

  @override
  String get stacked => '堆叠';

  @override
  String get tabs => '标签页';

  @override
  String get stackedTools => '堆叠工具栏';

  @override
  String get tabbedTools => '标签工具栏';

  @override
  String get regionVisibility => '区域可见性';

  @override
  String get appRail => '应用导航栏';

  @override
  String get toolPlacementDescription => '将工具面板固定在右侧或沿底部边缘排列。';

  @override
  String get visibilityTeamSessionsHint => '在左侧边栏显示团队会话列表。';

  @override
  String get visibilityMembersHint => '在工具或终端旁显示成员列表。';

  @override
  String get visibilityFileTreeHint => '显示项目文件树以便快速浏览。';

  @override
  String get themeModeTitle => '主题模式';

  @override
  String get themeModeDescription => '浅色、深色，或与系统外观一致。';

  @override
  String get themeColorPresetTitle => '主题色';

  @override
  String get themeColorPresetDescription => '用于按钮、开关与高亮的主色与强调色。';

  @override
  String get themePresetGraphite => '石墨';

  @override
  String get themePresetOcean => '海洋';

  @override
  String get themePresetViolet => '紫罗兰';

  @override
  String get themePresetAmber => '琥珀';

  @override
  String get themePresetForest => '森林';

  @override
  String get languageDescription => '菜单、按钮与标签所使用的语言。';

  @override
  String get cancel => '取消';

  @override
  String get add => '添加';

  @override
  String get delete => '删除';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get language => '语言';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get chatTo => '发送至：';

  @override
  String get copyPrompt => '复制提示';

  @override
  String get sendPrompt => '发送提示';

  @override
  String get chatHintText => '为 team-lead 编写提示...';

  @override
  String get emptyTimeline => '本地 shell 模式对话记录将显示在此处。';

  @override
  String get fileTree => '文件树';

  @override
  String get openTeam => '打开团队';

  @override
  String get openMember => '打开成员';

  @override
  String get filterFiles => '筛选文件';

  @override
  String get selectTeam => '选择团队';

  @override
  String get addTeamTooltip => '添加团队';

  @override
  String get projects => '项目';

  @override
  String get newProject => '新建项目';

  @override
  String get newSessionTooltip => '新建会话';

  @override
  String get defaultNewChatSessionTitle => '新对话';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get copyFolderPath => '复制文件夹路径';

  @override
  String get deleteProject => '删除项目';

  @override
  String deleteProjectConfirm(String name) {
    return '删除项目 \"$name\" 及其所有会话？此操作不可撤销。';
  }

  @override
  String get noSessions => '暂无会话';

  @override
  String get unknownFolder => '未知';

  @override
  String get renameConversation => '重命名对话';

  @override
  String get deleteConversation => '删除对话';

  @override
  String get renameConversationTitle => '重命名对话';

  @override
  String deleteConversationConfirm(String name) {
    return '删除对话 \"$name\"？此操作不可撤销。';
  }

  @override
  String get conversationName => '对话名称';

  @override
  String get closeTab => '关闭';

  @override
  String get closeOtherTabs => '关闭其他标签';

  @override
  String get closeRightTabs => '关闭右侧标签';

  @override
  String get session => '会话';

  @override
  String get sessionPageSubtitle => '配置 Shell 会话启动方式与 LLM 配置文件路径。';

  @override
  String get cliExecutablePathLabel => 'flashskyai CLI 路径';

  @override
  String get cliExecutablePathDescription =>
      'flashskyai 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';

  @override
  String get cliExecutablePathBrowse => '浏览…';

  @override
  String get cliExecutablePathApply => '更新';

  @override
  String get cliExecutablePathReset => '重置';

  @override
  String get cliExecutablePathUsing => '当前生效：';

  @override
  String get cliExecutablePathUsingFallback => '使用 PATH 中查找的版本';

  @override
  String get shellChatWorkbench => 'Shell 聊天工作台';

  @override
  String get shellSession => 'Shell 会话';

  @override
  String get autoLaunchAllMembersTitle => '连接时启动全部成员';

  @override
  String get autoLaunchAllMembersDescription =>
      '开启后，点击连接或重启会为每个有效成员启动终端；关闭则仅启动当前选中的成员。';

  @override
  String get scopeSessionsToSelectedTeamTitle => '按所选团队筛选会话';

  @override
  String get scopeSessionsToSelectedTeamDescription =>
      '开启后，侧边栏仅显示归属当前团队的会话。新建会话仍会写入当前所选团队，之后开启本选项即可看到它们。';

  @override
  String get runsPlaceholder => '运行历史将显示在此处。';

  @override
  String get llmConfig => '服务商';

  @override
  String get llmConfigSubtitle => '提供商和模型';

  @override
  String get llmConfigPathLabel => 'LLM 配置文件';

  @override
  String get llmConfigPathHint => '留空则使用默认路径';

  @override
  String get llmConfigPathBrowse => '选择文件';

  @override
  String get llmConfigPathSave => '更新';

  @override
  String get llmConfigPathReset => '默认';

  @override
  String get llmConfigPathBadgeDefault => '默认';

  @override
  String get llmConfigPathBadgeCustom => '自定义';

  @override
  String get llmConfigPathPickerTitle => '选择 llm_config.json';

  @override
  String get llmConfigPathSessionCardDescription =>
      'LLM 配置文件（llm_config.json）的绝对路径。留空则使用 CLI 安装目录旁的默认路径。';

  @override
  String get llmConfigCurrentEffectivePathPrefix => '当前文件：';

  @override
  String get llmConfigEffectivePathUnresolved => '尚未解析出路径（请指定 CLI 或自定义路径）';

  @override
  String get llmConfigOpenSessionSettings => '会话设置…';

  @override
  String get providers => '提供商';

  @override
  String get llmConfigPageSubtitle => '管理 LLM 提供商和模型。';

  @override
  String get providersTab => '提供商';

  @override
  String get modelsTab => '模型';

  @override
  String get rawJsonTab => '原始 JSON';

  @override
  String get addProvider => '添加提供商';

  @override
  String get providerName => '提供商名称';

  @override
  String get deleteProvider => '删除提供商';

  @override
  String deleteProviderConfirm(String name) {
    return '删除提供商 $name？';
  }

  @override
  String get providerList => '提供商列表';

  @override
  String get filterProviders => '筛选提供商...';

  @override
  String modelsUsingProvider(int count) {
    return '使用此提供商的模型： $count';
  }

  @override
  String providerListModelCount(int count) {
    return '$count 个模型';
  }

  @override
  String get proxyOnShort => '代理开';

  @override
  String get proxyOffShort => '代理关';

  @override
  String providerDetailSubtitle(int count, String type) {
    return '$type 提供商 · $count 个模型';
  }

  @override
  String get type => '类型';

  @override
  String get providerType => '提供商类型';

  @override
  String get providerTypeHint => 'openai, claude 或自定义';

  @override
  String get proxy => '代理';

  @override
  String get proxyUrl => '代理 URL';

  @override
  String get baseUrl => '基础 URL';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get reveal => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get replaceKey => '替换密钥';

  @override
  String get deleteProviderTooltip => '删除提供商';

  @override
  String get noModelsUsingProvider => '没有模型使用此提供商。';

  @override
  String get modelsUsingProviderTitle => '使用此提供商的模型';

  @override
  String get selectProvider => '从列表中选择一个提供商';

  @override
  String get accountCredentialPath => '账户凭证路径';

  @override
  String get removePath => '移除路径';

  @override
  String get addAccountPath => '添加账户路径';

  @override
  String get api => 'api';

  @override
  String get account => 'account';

  @override
  String get models => '模型';

  @override
  String get addModel => '添加模型';

  @override
  String get modelName => '模型别名/名称';

  @override
  String get modelId => '模型 ID';

  @override
  String get enabled => '启用';

  @override
  String get edit => '编辑';

  @override
  String editModelTitle(String name) {
    return '编辑 $name';
  }

  @override
  String get name => '名称';

  @override
  String get actualModel => '实际模型';

  @override
  String get noModelsConfigured => '未配置模型';

  @override
  String get missingProvider => '缺少提供商：';

  @override
  String get summary => '摘要';

  @override
  String get statProviders => '个提供商';

  @override
  String get statModels => '个模型';

  @override
  String get statMissingRefs => '缺失引用';

  @override
  String get statEmptyKeys => '空密钥';

  @override
  String get validation => '验证';

  @override
  String get allChecksPassed => '所有检查通过。';

  @override
  String get validate => '校验';

  @override
  String get back => '返回';

  @override
  String get jsonPreview => 'JSON 预览';

  @override
  String get skillsTitle => 'Skills';

  @override
  String get skillsSubtitle => '管理可安装的 Skill';

  @override
  String get skillsSidebarLabel => 'Skills';

  @override
  String get skillsNavInstalled => '已安装';

  @override
  String get skillsNavDiscovery => '发现';

  @override
  String get skillsNavRepos => '仓库';

  @override
  String get skillsNavBackups => '备份';

  @override
  String skillsInstalledCount(int count) {
    return '已安装 $count';
  }

  @override
  String get skillsCheckUpdates => '检查更新';

  @override
  String get skillsCheckingUpdates => '检查中…';

  @override
  String skillsUpdateAll(int count) {
    return '全部更新 ($count)';
  }

  @override
  String get skillsImportFromDisk => '从磁盘导入';

  @override
  String get skillsInstallFromZip => '从 ZIP 安装';

  @override
  String get skillsNoInstalled => '还没有安装 Skill';

  @override
  String get skillsNoInstalledHint => '打开发现页安装你的第一个 Skill。';

  @override
  String get skillsGoDiscovery => '前往发现';

  @override
  String get skillsSourceRepos => '仓库';

  @override
  String get skillsSourceSkillsSh => 'skills.sh';

  @override
  String get skillsSearchPlaceholder => '搜索 Skill…';

  @override
  String get skillsSkillsShPlaceholder => '搜索 skills.sh (≥2 字)…';

  @override
  String get skillsFilterRepoAll => '所有仓库';

  @override
  String get skillsFilterAll => '全部';

  @override
  String get skillsFilterInstalled => '已安装';

  @override
  String get skillsFilterUninstalled => '未安装';

  @override
  String get skillsCardInstall => '安装';

  @override
  String get skillsCardInstalled => '已安装';

  @override
  String get skillsCardUpdate => '更新';

  @override
  String get skillsCardUninstall => '卸载';

  @override
  String get skillsUpdateAvailable => '有新版本';

  @override
  String get skillsLocal => '本地';

  @override
  String get skillsReposEmpty => '暂无仓库';

  @override
  String get skillsRepoAdd => '添加仓库';

  @override
  String get skillsRepoOwner => 'Owner';

  @override
  String get skillsRepoName => '名称';

  @override
  String get skillsRepoBranch => '分支';

  @override
  String get skillsRepoRemove => '移除';

  @override
  String skillsRepoRemoveConfirm(String name) {
    return '确认移除仓库 $name？';
  }

  @override
  String get skillsBackupsEmpty => '暂无备份';

  @override
  String get skillsBackupRestore => '恢复';

  @override
  String get skillsBackupDelete => '删除';

  @override
  String skillsBackupDeleteConfirm(String name) {
    return '删除备份 $name？此操作不可撤销。';
  }

  @override
  String get skillsBackupCreatedAt => '创建时间';

  @override
  String skillsUninstallConfirm(String name) {
    return '卸载 $name？文件会移入备份目录。';
  }

  @override
  String skillsOverwriteConfirm(String name) {
    return '$name 已安装。是否覆盖？';
  }

  @override
  String skillsInstallSuccess(String name) {
    return '已安装 $name';
  }

  @override
  String skillsUninstallSuccess(String name) {
    return '已卸载 $name';
  }

  @override
  String skillsUpdateSuccess(String name) {
    return '已更新 $name';
  }

  @override
  String get skillsNoUpdates => '所有 Skill 均为最新';

  @override
  String get skillsImportTitle => '导入未管理的 Skill';

  @override
  String get skillsImportNothing => '未发现未管理的 Skill。';

  @override
  String skillsImportSelected(int count) {
    return '导入选中 $count 个';
  }

  @override
  String get skillsZipNoSkills => '压缩包中未发现 SKILL.md。';

  @override
  String get skillsSkillsShLoadMore => '加载更多';

  @override
  String get skillsSkillsShPoweredBy => '由 skills.sh 提供';

  @override
  String get skillsSkillsShSearch => '搜索';

  @override
  String get skillsDiscoveryEmpty => '未发现可用 Skill';

  @override
  String get skillsDiscoveryEmptyHint => '添加仓库或试用 skills.sh 来发现 Skill。';

  @override
  String get skillsAdd => '添加';

  @override
  String get skillsRemove => '移除';

  @override
  String get skillsEnabled => '启用';

  @override
  String skillsInstalls(int count) {
    return '$count 次安装';
  }

  @override
  String get members => '成员';

  @override
  String get teamSessions => '团队会话';

  @override
  String get configure => '配置';

  @override
  String get teamConfig => '团队配置';

  @override
  String get teamSettings => '团队设置';

  @override
  String get teamSettingsSubtitle => '工作区团队';

  @override
  String get membersSubtitle => '团队代理';

  @override
  String get teamSkillsNav => 'Skills';

  @override
  String teamSkillsAssignedCount(int assigned, int total) {
    return '已启用 $assigned/$total';
  }

  @override
  String get teamSkillsManage => '全部 Skills';

  @override
  String get memberQuickList => '成员快速列表';

  @override
  String get teamName => '团队名称';

  @override
  String get deleteTeam => '删除团队';

  @override
  String get deleteTeamSubtitle => '从 UI 和共享的 flashskyai 数据目录中移除该团队。此操作不可撤销。';

  @override
  String deleteTeamConfirm(String name) {
    return '删除团队 \"$name\"？此操作不可撤销。';
  }

  @override
  String get dangerZone => '危险操作';

  @override
  String get teamExtraArgs => '团队额外 CLI 参数';

  @override
  String get teamExtraArgsHint => '--permission-mode acceptEdits';

  @override
  String get teamLoop => '阶段循环';

  @override
  String get teamLoopSubtitle => '团队模式：true 自动推进阶段；false 需你确认后再继续。';

  @override
  String get teamLoopDefault => '默认';

  @override
  String get teamLoopTrue => 'true — 自动推进';

  @override
  String get teamLoopFalse => 'false — 每阶段确认';

  @override
  String get memberLaunchOrder => '成员启动顺序';

  @override
  String get saveMember => '保存成员';

  @override
  String get editTeamSubtitle => '编辑团队标识、工作目录和启动顺序。';

  @override
  String get memberName => '成员名称';

  @override
  String get provider => '提供商';

  @override
  String get model => '模型';

  @override
  String get agent => '代理';

  @override
  String get selectAgent => '选择 Agent';

  @override
  String get agentBuiltInNone => '默认';

  @override
  String get agentBuiltInCustom => '自定义…';

  @override
  String get agentBuiltInSubtitle => '内置预设 Agent。';

  @override
  String get agentCustomIdHint => '自定义 Agent 标识';

  @override
  String get memberExtraArgs => '成员额外 CLI 参数';

  @override
  String get memberDangerouslySkipPermissions => '跳过所有权限检查';

  @override
  String get memberDangerouslySkipPermissionsHint => '仅限隔离或无网络沙箱使用，否则风险极高。';

  @override
  String get prompt => '提示词';

  @override
  String get selectModel => '选择一个模型';

  @override
  String get editMemberSubtitle => '编辑提供商、模型、代理和命令参数。';

  @override
  String get teamLeadNameRequired => 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。';

  @override
  String get teamLeadNotice => 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。';

  @override
  String get membersAndFileTree => '成员和文件树';

  @override
  String get membersAndFileTreeDescription => '将成员列表与文件树堆叠显示，或以标签页切换。';
}
