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
  String get openRightTools => '工具';

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
  String get addTeamTitle => '添加团队';

  @override
  String get teamCliLabel => 'CLI 后端';

  @override
  String get teamCliSubtitle => '创建团队时选定，之后不可更改。';

  @override
  String get teamCliComingSoon => '即将支持';

  @override
  String get teamCliLockedSubtitle => '在创建团队时已选定。';

  @override
  String get teamNameRequired => '团队名称不能为空。';

  @override
  String teamNameAlreadyExists(String name) {
    return '已存在名为「$name」的团队。';
  }

  @override
  String get projects => '项目';

  @override
  String get newProject => '新建项目';

  @override
  String get newProjectTooltip => '创建项目，可添加主目录与附加目录';

  @override
  String get create => '创建';

  @override
  String get pickPrimaryDirectory => '选择主目录';

  @override
  String get projectPrimaryPathRequired => '请先选择主目录。';

  @override
  String get projectPrimaryPathNotSelected => '尚未选择主目录';

  @override
  String get projectDirectoryAdded => '已添加目录到项目';

  @override
  String get newSessionTooltip => '新建会话';

  @override
  String get defaultNewChatSessionTitle => '新对话';

  @override
  String get sessionStarting => '正在启动会话…';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get copyFolderPath => '复制文件夹路径';

  @override
  String pathCopied(String path) {
    return '已复制路径：$path';
  }

  @override
  String get projectDetails => '项目详情';

  @override
  String get projectDetailsTitle => '项目详情';

  @override
  String get addProjectDirectory => '添加目录';

  @override
  String get removeProjectDirectory => '移除目录';

  @override
  String get projectDisplayName => '显示名称';

  @override
  String get projectPrimaryPath => '主目录';

  @override
  String get projectAdditionalDirectories => '附加目录';

  @override
  String get projectNoAdditionalDirectories => '暂无附加目录';

  @override
  String get projectSessionCount => '会话数';

  @override
  String get projectCreatedAt => '创建时间';

  @override
  String get projectUpdatedAt => '更新时间';

  @override
  String get projectDirectoryAlreadyPrimary => '该路径已是项目主目录。';

  @override
  String get projectDirectoryAlreadyAdded => '该目录已在项目中。';

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
  String get connectionModeLabel => '运行模式';

  @override
  String get connectionModeDescription =>
      '本机模式在当前设备运行 flashskyai；SSH 模式在选中的远程服务器上运行。';

  @override
  String get connectionModeLocal => '本机';

  @override
  String get connectionModeSsh => 'SSH';

  @override
  String get sshProfilesSettingsTitle => 'SSH 服务器';

  @override
  String get sshProfileSelectorTooltip => '切换 SSH 服务器';

  @override
  String get sshProfileSelectorManage => '管理 SSH 服务器…';

  @override
  String get cliExecutablePathLabel => 'flashskyai CLI 路径';

  @override
  String get cliExecutablePathDescription =>
      'flashskyai 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';

  @override
  String get cliExecutablePathDescriptionSsh =>
      '远程 SSH 主机上 flashskyai 的绝对路径。留空则通过 SSH 自动探测。';

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
  String get cliInstallButton => '安装';

  @override
  String get cliInstallInstalling => '安装中…';

  @override
  String get cliInstallProgressCheckingNpm => '正在检测 npm…';

  @override
  String get cliInstallProgressBootstrappingNode => '正在安装 Node.js…';

  @override
  String get cliInstallProgressInstallingClaude => '正在安装 Claude Code…';

  @override
  String get cliInstallProgressLocatingExecutable => '正在定位 Claude Code 可执行文件…';

  @override
  String get claudeCliExecutablePathLabel => 'Claude Code CLI 路径';

  @override
  String get claudeCliExecutablePathDescription =>
      'Claude Code 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';

  @override
  String get claudeCliExecutablePathDescriptionSsh =>
      '远程 SSH 主机上 Claude Code 的绝对路径。留空则从远端 PATH 解析 claude。';

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
  String get windowsStorageBackendTitle => '数据存储位置';

  @override
  String get windowsStorageBackendDescription =>
      '团队、技能、项目与配置文件的读写位置。切换会使用另一套数据目录，不会自动迁移。';

  @override
  String get windowsStorageBackendNative => 'Windows 本地';

  @override
  String get windowsStorageBackendWsl => 'WSL';

  @override
  String windowsStorageBackendCurrentRoot(String path) {
    return '当前根目录：$path';
  }

  @override
  String get windowsStorageBackendSwitchConfirmTitle => '切换存储位置？';

  @override
  String get windowsStorageBackendSwitchConfirmBody =>
      '将使用另一套数据目录。另一位置下的团队、项目与技能需切回后才能看到。';

  @override
  String get windowsStorageBackendSwitchConfirmAction => '切换';

  @override
  String get windowsStorageBackendWslUnavailable =>
      'WSL 不可用。请先安装或启动 WSL 后再选择 WSL 存储。';

  @override
  String get windowsStorageCliMismatchNativeCli =>
      'CLI 在 WSL 中运行，但数据保存在 Windows AppData，配置可能不一致。';

  @override
  String get windowsStorageCliMismatchWslCli =>
      'CLI 在 Windows 上运行，但数据保存在 WSL，配置可能不一致。';

  @override
  String get windowsStorageSwitchReloadHint => '切换存储后建议重连已打开的会话。';

  @override
  String bootstrapStartupFailed(String error) {
    return '启动失败：$error';
  }

  @override
  String get bootstrapUseNativeStorageInstead => '改用 Windows 本地存储';

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
  String get llmConfigPathSessionCardDescriptionSsh =>
      'SSH 远端主机上 llm_config.json 的绝对路径。留空则使用远端 CLI 安装目录旁的默认路径。';

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
  String get renameProviderName => '修改名称';

  @override
  String get renameProviderTitle => '修改提供商名称';

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
  String get appProviderImport => '导入';

  @override
  String get appProviderImportNothing => '未发现可导入的提供商。';

  @override
  String appProviderImportSuccess(int count, int mirrored, int skipped) {
    return '已导入 $count 个提供商，同步到 FlashskyAI $mirrored 个，跳过已存在 $skipped 个。';
  }

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
  String get appProviderApiKeyEditHint => '留空则保留原密钥';

  @override
  String get reveal => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get replaceKey => '替换密钥';

  @override
  String get deleteProviderTooltip => '删除提供商';

  @override
  String deleteProviderWithCredentialsConfirm(String name) {
    return '删除提供商 $name？将同时删除该 Provider 已保存的 Claude 登录凭据。';
  }

  @override
  String get claudeOfficialCredentialsTitle => 'Claude Official 登录';

  @override
  String get claudeOfficialCredentialsReady => '凭据已就绪';

  @override
  String get claudeOfficialCredentialsMissing => '该 Provider 尚未保存凭据';

  @override
  String get claudeOfficialCredentialsLogin => 'Claude 登录';

  @override
  String get claudeOfficialCredentialsImportGlobal => '从 ~/.claude 导入';

  @override
  String get claudeOfficialCredentialsImportFile => '导入文件…';

  @override
  String get claudeOfficialCredentialsRevoke => '退出登录';

  @override
  String claudeOfficialCredentialsRevokeConfirm(String name) {
    return '退出登录并删除 $name 的已保存凭据？';
  }

  @override
  String get claudeOfficialCredentialsActionSuccess => '凭据已更新';

  @override
  String get claudeOfficialCredentialsActionFailed => '凭据更新失败';

  @override
  String get claudeLaunchCredentialsMissingWarning =>
      '该 Team 绑定的 Claude Official Provider 缺少凭据，请在 Providers 设置中登录。';

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
  String get skillsDiscoverySyncing => '正在后台检查仓库更新并同步 Skill…';

  @override
  String get skillsRepoSyncing => '更新中';

  @override
  String get skillsRepoInvalidUrl =>
      '请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repo';

  @override
  String get skillsRepoUrl => '仓库地址';

  @override
  String get skillsRepoUrlHint => 'https://github.com/owner/repo';

  @override
  String get skillsRepoBranch => '分支';

  @override
  String get skillsRepoRemove => '移除';

  @override
  String skillsRepoRemoveConfirm(String name) {
    return '确认移除仓库 $name？';
  }

  @override
  String skillsUninstallConfirm(String name) {
    return '卸载 $name？';
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
  String get pluginsTitle => '插件';

  @override
  String get pluginsSubtitle => '管理 Claude Code 风格插件包';

  @override
  String get pluginsSidebarLabel => '插件';

  @override
  String get pluginsNavInstalled => '已安装';

  @override
  String get pluginsNavDiscovery => '发现';

  @override
  String get pluginsNavMarketplaces => 'Marketplaces';

  @override
  String pluginsInstalledCount(int count) {
    return '已安装 $count 个';
  }

  @override
  String pluginsUpdateAll(int count) {
    return '全部更新 ($count)';
  }

  @override
  String get pluginsImportFromDisk => '从目录导入';

  @override
  String get pluginsImportTitle => '导入未管理的插件';

  @override
  String get pluginsImportNothing => '未发现未管理的插件。';

  @override
  String get pluginsInstallFromZip => '从 ZIP 安装';

  @override
  String get pluginsCheckUpdates => '检查更新';

  @override
  String get pluginsCheckingUpdates => '检查中…';

  @override
  String get pluginsNoInstalled => '尚未安装插件';

  @override
  String get pluginsNoInstalledHint =>
      '在 Marketplaces 选项卡添加 marketplace，然后在 Discovery 中安装。';

  @override
  String get pluginsGoDiscovery => '浏览 marketplace';

  @override
  String get pluginsCardInstall => '安装';

  @override
  String get pluginsCardInstalled => '已安装';

  @override
  String get pluginsCardViewSource => '查看来源';

  @override
  String get pluginsCardUpdate => '更新';

  @override
  String get pluginsCardUninstall => '卸载';

  @override
  String get pluginsMarketplaceAdd => '添加 marketplace';

  @override
  String get pluginsMarketplaceUrl => 'GitHub 仓库地址';

  @override
  String get pluginsMarketplaceUrlHint =>
      'https://github.com/owner/marketplace';

  @override
  String get pluginsMarketplaceBranch => '分支';

  @override
  String get pluginsMarketplaceRemove => '移除 marketplace';

  @override
  String pluginsMarketplaceRemoveConfirm(String url) {
    return '确认移除 marketplace $url？已安装的插件会保留。';
  }

  @override
  String get pluginsMarketplaceInvalidUrl => '请输入合法的 GitHub 仓库地址。';

  @override
  String get pluginsMarketplacesEmpty => '尚未配置 marketplace';

  @override
  String get pluginsSearchPlaceholder => '搜索插件';

  @override
  String get pluginsFilterMarketplaceAll => '全部 marketplace';

  @override
  String get pluginsFilterAll => '全部';

  @override
  String get pluginsFilterInstalled => '已安装';

  @override
  String get pluginsFilterUninstalled => '未安装';

  @override
  String get pluginsDiscoveryEmpty => '无匹配的插件';

  @override
  String pluginsUninstallConfirm(String name, int n) {
    return '确认卸载 $name？将影响 $n 个团队。';
  }

  @override
  String get pluginsUninstallImpactList => '受影响的团队：';

  @override
  String pluginsUninstallSuccess(String name) {
    return '已卸载 $name';
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
  String get teamPluginsNav => '插件';

  @override
  String teamPluginsAssignedCount(int assigned, int total) {
    return '已安装 $assigned/$total';
  }

  @override
  String get teamPluginsManage => '全部插件';

  @override
  String get teamPluginsEmpty => '尚未安装插件';

  @override
  String get teamPluginsEmptyHint => '在「发现」中安装插件后，可在此处按团队启用。';

  @override
  String get teamPluginsGoDiscovery => '浏览 marketplace';

  @override
  String teamPluginsMissing(int count) {
    return '有 $count 个已启用插件在磁盘上缺失，重新安装或手动移除。';
  }

  @override
  String get teamPluginsRemoveMissing => '移除';

  @override
  String get teamPluginsMissingLabel => '磁盘上缺失';

  @override
  String teamPluginsNameConflict(String dir) {
    return '因名称冲突，已链接为 $dir';
  }

  @override
  String get teamPluginsCliUnsupportedBanner => '当前团队 CLI 暂不支持插件，启用记录已保存但不会生效。';

  @override
  String get memberQuickList => '成员快速列表';

  @override
  String get teamName => '团队名称';

  @override
  String get teamDescription => '团队描述';

  @override
  String get teamDescriptionHint => '可选，写入 Claude roster 的 description 字段';

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
  String get agentBuiltInSubtitle => '内置预设及 ~/.flashskyai/agents 下的用户 Agent。';

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
  String get memberOfficialClaudeModelHint =>
      '使用 Claude 账号默认模型；请在 Providers 设置中管理 Official 登录。';

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

  @override
  String get appProviderCatalogLabel => '应用级服务商目录';

  @override
  String get appProviderCatalogHint => 'TeamPilot 在此维护统一服务商；团队启动时会为各工具生成隔离配置。';

  @override
  String get appProviderPresetLabel => '预设';

  @override
  String get appProviderPresetCustom => '自定义';

  @override
  String get appProviderClaudeApiFormatAnthropic => 'Anthropic Messages（原生）';

  @override
  String get appProviderClaudeApiFormatOpenaiChat => 'OpenAI Chat Completions';

  @override
  String get appProviderClaudeApiFormatOpenaiResponses => 'OpenAI Responses';

  @override
  String get appProviderClaudeApiFormatGeminiNative => 'Gemini Native';

  @override
  String get appProviderClaudeAuthTokenDefault => 'ANTHROPIC_AUTH_TOKEN（默认）';

  @override
  String get appProviderClaudeAuthApiKey => 'ANTHROPIC_API_KEY';

  @override
  String get appProviderAdvancedJson => '高级 JSON 编辑';

  @override
  String get appProviderAdvancedOptions => '高级选项';

  @override
  String get appProviderWebsite => '官网';

  @override
  String get appProviderEnabledTools => '启用的工具';

  @override
  String get appProviderToolFlashskyai => 'FlashskyAI';

  @override
  String get appProviderToolCodex => 'Codex';

  @override
  String get appProviderToolClaude => 'Claude Code';

  @override
  String get appProviderTeamToolSection => '团队工具服务商';

  @override
  String get appProviderTeamToolSubtitle => '选择本团队启动时，各工具使用的统一服务商。';

  @override
  String get appProviderTeamNone => '无';

  @override
  String get appProviderClaudeApiFormat => 'API 格式';

  @override
  String get appProviderClaudeApiFormatHint => '选择服务商 API 的输入格式。';

  @override
  String get appProviderClaudeAuthField => '认证字段';

  @override
  String get appProviderClaudeAuthFieldHint => '选择写入 settings 的认证环境变量。';

  @override
  String get appProviderClaudeModelMapping => '模型映射';

  @override
  String get appProviderClaudeModelMappingHint =>
      '原生 Claude 服务商可留空；仅在服务商将 Claude 模型角色映射为不同模型名称时填写。';

  @override
  String get appProviderClaudeHaikuModel => 'Haiku 默认模型';

  @override
  String get appProviderClaudeSonnetModel => 'Sonnet 默认模型';

  @override
  String get appProviderClaudeOpusModel => 'Opus 默认模型';

  @override
  String get notes => '备注';

  @override
  String get defaultModel => '默认模型';

  @override
  String get editProvider => '编辑服务商';

  @override
  String get invalidJson => 'JSON 无效，请修正语法后重试。';

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutPageSubtitle => 'TeamPilot 版本与应用更新。';

  @override
  String get aboutCurrentVersion => '当前版本';

  @override
  String get aboutVersionLoading => '加载中…';

  @override
  String get appUpdateCheck => '检查更新';

  @override
  String get appUpdateDownloadInstall => '下载并安装';

  @override
  String get appUpdateUpToDate => '已是最新版本。';

  @override
  String get appUpdateDownloading => '正在下载更新…';

  @override
  String get appUpdateInstalling => '正在安装更新…';

  @override
  String get appUpdateViewRelease => '在 GitHub 查看发布';

  @override
  String appUpdateNewVersion(String version) {
    return '新版本 $version 可用';
  }

  @override
  String get appUpdateDialogTitle => '发现新版本';

  @override
  String get appUpdateLatestVersion => '最新版本';

  @override
  String get appUpdateUnknownVersion => '未知';

  @override
  String get appUpdateChangelogTitle => '更新内容';

  @override
  String get appUpdateChangelogDefaultSection => '更新';

  @override
  String get appUpdateReadyToDownload => '准备下载';

  @override
  String get appUpdateLater => '以后更新';

  @override
  String get appUpdateDownloadNow => '立即下载';

  @override
  String get appUpdateDownloadInBackground => '后台下载';

  @override
  String get appUpdateInstallNow => '立即安装';

  @override
  String get appUpdateBrowserDownload => '浏览器下载';

  @override
  String get appUpdateInvalidPackagePath => '安装包路径无效';

  @override
  String get appUpdateReleaseBuildRequired => '请使用 Release 构建包进行应用内安装';

  @override
  String get appUpdatePackagePlatformMismatch => '安装包类型与当前系统不匹配';

  @override
  String appUpdateInstallFailed(String message) {
    return '安装失败：$message';
  }

  @override
  String get appUpdateInstallNoResult => '安装未返回结果';

  @override
  String get appUpdateInstallComplete => '安装完成';

  @override
  String get appUpdateRedirectBrowserOnly => '该链接需要在浏览器中下载';

  @override
  String get appUpdateDownloadStarting => '开始下载…';

  @override
  String get appUpdateDownloadComplete => '下载完成';

  @override
  String get appUpdateDownloadFailed => '下载失败';

  @override
  String appUpdateDownloadError(String error) {
    return '下载过程中发生错误：$error';
  }

  @override
  String get appUpdateResolvingDownloadUrl => '正在获取下载链接…';

  @override
  String get appUpdateBrowserOpened => '已在浏览器中打开下载链接';

  @override
  String get appUpdateCannotOpenDownloadLink => '无法打开下载链接';

  @override
  String appUpdateBrowserOpenFailed(String error) {
    return '打开浏览器失败：$error';
  }

  @override
  String get onboardingTitle => '首次设置';

  @override
  String onboardingProgress(int current, int total) {
    return '第 $current / $total 步';
  }

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingPrevious => '上一步';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingStepAppearance => '语言 / 主题';

  @override
  String get onboardingStepSsh => 'SSH';

  @override
  String get onboardingStepCli => 'Claude Code CLI';

  @override
  String get onboardingStepProviderImport => '导入 Provider';

  @override
  String get onboardingStepDefaultProvider => '默认 Provider';

  @override
  String get onboardingAppearanceTitle => '选择语言与外观';

  @override
  String get onboardingAppearanceSubtitle => '可随时在「设置 → 布局」中修改。';

  @override
  String get onboardingSshTitle => '配置 SSH 连接';

  @override
  String get onboardingSshSubtitle => 'Android 通过 SSH 在远程主机运行 Claude Code。';

  @override
  String get onboardingCliTitle => '检测 Claude Code CLI';

  @override
  String get onboardingCliSubtitle => '应用需要 Claude Code 可执行文件才能启动会话。';

  @override
  String get onboardingCliFound => '已找到 CLI';

  @override
  String get onboardingCliNotFound => '未在 PATH 中检测到 CLI';

  @override
  String get onboardingCliRedetect => '重新检测';

  @override
  String get onboardingProviderImportTitle => '导入 Claude Provider';

  @override
  String get onboardingProviderImportSubtitle =>
      '扫描 ~/.claude 配置与 cc-switch 中的现有 Provider。';

  @override
  String get onboardingProviderImportResults => '导入结果';

  @override
  String get onboardingProviderImportEmpty => '未检测到 Claude Provider，可稍后在设置中配置。';

  @override
  String get onboardingProviderImportFailed => '导入失败';

  @override
  String get onboardingProviderImportRescan => '重新扫描';

  @override
  String get onboardingDefaultProviderTitle => '选择默认 Claude Provider';

  @override
  String get onboardingDefaultProviderSubtitle => '新建会话时将使用此 Provider 与默认模型。';

  @override
  String get onboardingDefaultProviderEmpty => '暂无可选 Provider，可跳过或在设置中添加。';

  @override
  String get onboardingDefaultProviderPick => '选择 Claude Code 默认 Provider';

  @override
  String get onboardingDefaultProviderModelHint => '该 Provider 的主模型 ID';

  @override
  String get onboardingRerunSetup => '重新运行设置向导';

  @override
  String get logViewerTitle => '日志';

  @override
  String get logViewerSubtitle => '应用数据目录下的运行日志与错误记录。';

  @override
  String get logViewerFileLabel => '日志文件';

  @override
  String get logViewerSearchHint => '搜索日志…';

  @override
  String get logViewerFilterTitle => '过滤';

  @override
  String get logViewerFilterLevel => '级别';

  @override
  String get logViewerWrapLines => '自动换行';

  @override
  String get logViewerReverseOrder => '从最新内容开始';

  @override
  String get logViewerCompactView => '简洁视图';

  @override
  String logViewerLineCount(int count) {
    return '$count 行';
  }

  @override
  String get logViewerActionsMenu => '更多操作';

  @override
  String get logViewerRefresh => '刷新';

  @override
  String get logViewerCopyPath => '复制日志路径';

  @override
  String get logViewerClearOld => '清理过期日志';

  @override
  String get logViewerEmpty => '暂无日志文件';

  @override
  String get logViewerEmptyHint => '应用运行后会在此生成日志。';

  @override
  String get logViewerPendingTitle => '日志尚未写入磁盘';

  @override
  String get logViewerPendingBody => '以下为等待写入文件的缓冲条目：';

  @override
  String logViewerLoadFilesFailed(String error) {
    return '加载日志列表失败：$error';
  }

  @override
  String logViewerReadFailed(String error) {
    return '读取日志失败：$error';
  }

  @override
  String get logViewerClearDone => '已清理过期日志';

  @override
  String logViewerClearFailed(String error) {
    return '清理失败：$error';
  }

  @override
  String logViewerPathCopied(String name) {
    return '已复制路径：$name';
  }

  @override
  String get initErrorTitle => '应用启动失败';

  @override
  String get initErrorDetails => '错误信息';

  @override
  String get initErrorStackTrace => '堆栈跟踪';

  @override
  String get initErrorPendingLogs => '待写入日志';

  @override
  String get initErrorViewLogs => '查看日志';

  @override
  String get initErrorCopyReport => '复制报告';

  @override
  String get initErrorCopy => '复制';

  @override
  String get initErrorCopied => '已复制';

  @override
  String get initErrorStackEmpty => '（堆栈为空）';

  @override
  String initErrorVersion(String version, String build) {
    return '版本 $version（$build）';
  }
}
