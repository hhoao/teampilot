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
  String get ok => '确定';

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
  String get rightToolsPanelVisible => '显示工具栏';

  @override
  String get rightToolsPanelHidden => '隐藏工具栏';

  @override
  String get sidebarPanelVisible => '显示侧边栏';

  @override
  String get sidebarPanelHidden => '隐藏侧边栏';

  @override
  String get bottomDockPanelVisible => '显示底部栏';

  @override
  String get bottomDockPanelHidden => '隐藏底部栏';

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
  String get visibilityFileTreeHint => '显示工作区文件树以便快速浏览。';

  @override
  String get visibilityGitHint => '显示当前仓库的源代码管理面板。';

  @override
  String get extensionsSettingsTitle => '扩展';

  @override
  String get extensionsSettingsDescription => '安装并启用增强 Agent 的外部工具。';

  @override
  String get extensionsNavInstalled => '已安装';

  @override
  String get extensionsEmptyTitle => '暂无可用扩展';

  @override
  String get extensionsEmptyHint => '扩展目录加载后会显示在这里。';

  @override
  String get extensionEnableLabel => '已启用';

  @override
  String get extensionInstall => '安装';

  @override
  String get extensionUninstall => '卸载';

  @override
  String get extensionInstallGuide => '安装指引';

  @override
  String get extensionStatusNotInstalled => '未安装';

  @override
  String get extensionStatusReady => '就绪';

  @override
  String extensionStatusReadyVersion(String version) {
    return '就绪（$version）';
  }

  @override
  String get extensionStatusDependencyMissing => '缺少依赖';

  @override
  String extensionStatusDependencyMissingNamed(String deps) {
    return '缺少：$deps';
  }

  @override
  String extensionDependencyMissingHint(String deps) {
    return '需要 PATH 中有 $deps。安装后点击重新检测。';
  }

  @override
  String get extensionCopyCommand => '复制';

  @override
  String get extensionCommandCopied => '命令已复制到剪贴板';

  @override
  String get extensionRecheck => '重新检测';

  @override
  String get extensionStatusVersionTooOld => '已安装版本过旧';

  @override
  String get extensionKindMcpServer => '代码智能（MCP）';

  @override
  String get extensionKindSettingsHook => 'Token 节省（hook）';

  @override
  String get rtkSettingsTitle => 'RTK 省 token';

  @override
  String get rtkSettingsEnableTitle => '启用 RTK';

  @override
  String get rtkSettingsDescription =>
      '在命令输出进入模型前压缩 Agent Bash 结果（需本机 PATH 中有 rtk 与 jq）。';

  @override
  String get rtkSettingsStatusTitle => '本机状态';

  @override
  String get rtkSettingsInstallLink => '安装说明';

  @override
  String get rtkStatusNotFound => 'PATH 中未找到 rtk';

  @override
  String get rtkStatusJqMissing => 'PATH 中未找到 jq';

  @override
  String get rtkStatusInstalledGeneric => 'rtk 已就绪';

  @override
  String rtkStatusInstalled(String version) {
    return 'rtk $version 已就绪';
  }

  @override
  String rtkStatusVersionTooOld(String version) {
    return 'rtk $version 版本过低（需要 >= 0.23.0）';
  }

  @override
  String get rtkBashOnlyHint =>
      '仅作用于 Agent 的 Bash 工具调用；内置 Read、Grep、Glob 不会自动改写。';

  @override
  String get themeModeTitle => '主题模式';

  @override
  String get themeModeDescription => '浅色、深色，或与系统外观一致。';

  @override
  String get themeColorPresetTitle => '主题色';

  @override
  String get themeColorPresetDescription => '用于按钮、开关与高亮的主色与强调色。';

  @override
  String get typographyScaleTitle => '文字大小';

  @override
  String get typographyScaleDescription => '界面文字大小。「标准」跟随系统；不改变图标与间距。';

  @override
  String get typographyScaleCompact => '紧凑';

  @override
  String get typographyScaleStandard => '标准';

  @override
  String get typographyScaleComfortable => '宽松';

  @override
  String get typographyScaleCustom => '自定义';

  @override
  String get typographyScaleCustomLabel => '缩放比例';

  @override
  String get typographyScaleCustomHint => '50–200';

  @override
  String get fontUiTitle => '界面字体';

  @override
  String get fontUiDescription => '界面文字。系统跟随操作系统默认字体。重启后生效。';

  @override
  String get fontMonoTitle => '等宽字体';

  @override
  String get fontMonoDescription => '终端、编辑器与 diff。重启后生效。';

  @override
  String get fontChangeAppliesOnRestart => '字体已保存，重启 TeamPilot 后生效。';

  @override
  String get fontOptionSystem => '系统';

  @override
  String get fontOptionNotoSansSc => 'Noto Sans SC';

  @override
  String get fontOptionJetbrainsMono => 'JetBrains Mono';

  @override
  String get fontOptionUbuntuSansMono => 'Ubuntu Sans Mono';

  @override
  String get fontInstalledSection => '已安装';

  @override
  String get fontSearchHint => '搜索字体';

  @override
  String get uiZoomTitle => '界面缩放';

  @override
  String get uiZoomDescription => '整体缩放界面——文字、图标与间距一起。「标准」按系统缩放自动匹配。';

  @override
  String get markdownOpenModeTitle => '打开 Markdown 为';

  @override
  String get markdownOpenModeDescription =>
      '在编辑器中打开 .md 文件时的默认视图。「记住上次」仅在本次应用会话内有效。';

  @override
  String get markdownOpenModePreview => '预览';

  @override
  String get markdownOpenModeSource => '源码';

  @override
  String get markdownOpenModeRemember => '记住上次';

  @override
  String get thinkingProcessSectionTitle => '思考过程';

  @override
  String get cotExpandReasoningOnOpenTitle => '打开时展开推理';

  @override
  String get cotExpandReasoningOnOpenDescription => '展开「思考过程」时，自动展开内部推理步骤。';

  @override
  String get cotExpandToolsOnOpenTitle => '打开时展开工具';

  @override
  String get cotExpandToolsOnOpenDescription => '展开「思考过程」时，自动展开内部工具调用详情。';

  @override
  String get thinkingProcessFoldSectionTitle => '折叠进思考过程';

  @override
  String get toolCategoryRead => '读取文件';

  @override
  String get toolCategoryWrite => '写入文件';

  @override
  String get toolCategoryEdit => '编辑文件';

  @override
  String get toolCategoryCommand => 'Shell 命令';

  @override
  String get toolCategorySearch => '网络搜索';

  @override
  String get toolCategoryBrowser => '浏览器';

  @override
  String get toolCategorySubagent => '子代理';

  @override
  String get toolCategoryAskUser => '询问用户';

  @override
  String get toolCategoryPlan => '计划';

  @override
  String get toolCategoryTask => '任务与待办';

  @override
  String get toolCategoryMcp => 'MCP';

  @override
  String get toolCategoryOther => '其他';

  @override
  String get contentDisplayModeSectionTitle => '内容显示';

  @override
  String get chatUserMessageModeTitle => '用户消息';

  @override
  String get chatUserMessageModeDescription => '聊天中超大用户消息的呈现方式。';

  @override
  String get chatCodeBlockModeTitle => '聊天·代码块';

  @override
  String get chatCodeBlockModeDescription => '聊天中超大代码块的呈现方式。';

  @override
  String get fileCodeBlockModeTitle => '文件预览·代码块';

  @override
  String get fileCodeBlockModeDescription => 'markdown 文件预览中超大代码块的呈现方式。';

  @override
  String get contentDisplayModeFoldFixedHeight => '折叠·固定高度';

  @override
  String get contentDisplayModeFoldExpandFull => '折叠·全部展开';

  @override
  String get contentDisplayModeFlatten => '铺平（自然高度）';

  @override
  String get markdownViewToggleSource => '源码';

  @override
  String get markdownViewTogglePreview => '预览';

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
  String get workspaceEntryModeTitle => '启动视图';

  @override
  String get workspaceEntryModeDescription => 'App 启动后默认打开的页面。';

  @override
  String get workspaceEntryModeHome => '主页';

  @override
  String get workspaceEntryModeLastWorkspace => '恢复上次工作区';

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
  String get languageSystem => '跟随系统';

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
  String get sourceControl => '源代码管理';

  @override
  String get gitStagedChanges => '暂存的更改';

  @override
  String get gitChanges => '更改';

  @override
  String get gitNoChanges => '没有更改';

  @override
  String get gitNotARepository => '当前文件夹不是 Git 仓库';

  @override
  String get gitNotInstalled => '未找到 Git。安装 Git 后即可使用源代码管理。';

  @override
  String get gitCommit => '提交';

  @override
  String gitCommitMessageHint(String branch) {
    return '消息（提交到 \"$branch\"）';
  }

  @override
  String get treeExpandAllFolders => '展开所有目录';

  @override
  String get treeCollapseAllFolders => '折叠所有目录';

  @override
  String get gitDiscard => '放弃更改';

  @override
  String get gitOpenFile => '打开文件';

  @override
  String get gitIncludeInCommit => '纳入本次提交';

  @override
  String get gitExcludeFromCommit => '排除出本次提交';

  @override
  String get gitIncludeFolderInCommit => '纳入文件夹到本次提交';

  @override
  String get gitExcludeFolderFromCommit => '从本次提交排除文件夹';

  @override
  String get gitShowDiff => '显示差异';

  @override
  String get gitCopyPath => '复制路径';

  @override
  String get gitDiscardFolder => '放弃文件夹中的更改';

  @override
  String get gitDiscardSelected => '放弃所选更改';

  @override
  String get gitDiscardAllUnstaged => '放弃全部未暂存更改';

  @override
  String get gitDiscardAllConfirmTitle => '放弃所有更改？';

  @override
  String get gitDiscardAllConfirmBody => '放弃工作区中的所有未暂存更改？此操作无法撤销。';

  @override
  String get gitDiscardFolderConfirmTitle => '放弃文件夹更改？';

  @override
  String gitDiscardFolderConfirmBody(String path) {
    return '放弃 $path 中的所有更改？此操作无法撤销。';
  }

  @override
  String get gitDiscardConfirmTitle => '放弃更改？';

  @override
  String gitDiscardConfirmBody(String path) {
    return '放弃 $path 中的所有更改？此操作无法撤销。';
  }

  @override
  String get gitPush => '推送';

  @override
  String get gitPull => '拉取';

  @override
  String get gitRefresh => '刷新';

  @override
  String get gitChangesListView => '列表视图';

  @override
  String get gitChangesTreeView => '树形视图';

  @override
  String get gitSwitchBranch => '切换分支';

  @override
  String get gitCreateBranch => '新建分支';

  @override
  String get gitNewBranchHint => '新分支名称';

  @override
  String gitError(String message) {
    return 'Git：$message';
  }

  @override
  String gitAheadBehind(int ahead, int behind) {
    return '↑$ahead ↓$behind';
  }

  @override
  String get openTeam => '启动所有成员';

  @override
  String get openMember => '打开成员';

  @override
  String get switchToMember => '切换到成员';

  @override
  String get memberPresenceOffline => '未连接';

  @override
  String get memberPresenceConnecting => '连接中…';

  @override
  String get memberPresenceBooting => '启动中…';

  @override
  String get memberPresenceIdle => '空闲';

  @override
  String get memberPresenceWorking => '工作中';

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
  String get teamModeLabel => '团队模式';

  @override
  String get teamModeNative => '原生（单 CLI）';

  @override
  String get teamModeMixed => '混合（跨 CLI bus）';

  @override
  String get memberCliInheritHint => '继承团队默认';

  @override
  String get memberLaunchConfigTitle => '模型配置';

  @override
  String get memberLaunchConfigSubtitle => '本成员的 CLI 后端、提供商、模型与 Effort。';

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
  String get workspaces => '工作区';

  @override
  String get newWorkspace => '新建工作区';

  @override
  String get homeWorkspaceMainWindow => '主窗口';

  @override
  String get windowControlMinimize => '最小化';

  @override
  String get windowControlMaximize => '最大化';

  @override
  String get windowControlRestore => '还原';

  @override
  String get windowControlClose => '关闭';

  @override
  String get windowControlAlwaysOnTop => '置顶';

  @override
  String get homeWorkspaceMyFavorites => '我的收藏';

  @override
  String get homeWorkspaceRecentVisits => '最近访问';

  @override
  String get homeWorkspacePersonal => '简单模式';

  @override
  String get homeWorkspaceAllWorkspaces => '全部工作区';

  @override
  String get homeWorkspaceDefaultPersonalWorkspaceName => '个人助手';

  @override
  String get homeWorkspaceDefaultNativeTeamName => '默认原生团队';

  @override
  String get homeWorkspaceDefaultMixedTeamName => '默认混合团队';

  @override
  String get homeWorkspacePersonalSubtitle => '不用组队，直接拉起一个 CLI 开聊。';

  @override
  String get homeWorkspaceNoData => '暂无数据';

  @override
  String get homeWorkspaceRecentlyClosed => '最近关闭';

  @override
  String get homeWorkspaceOpenTabs => '已打开';

  @override
  String get homeWorkspaceRecentlyClosedEmpty => '暂无最近关闭的工作区';

  @override
  String get homeWorkspaceNewTeam => '新建团队';

  @override
  String get homeWorkspaceProviders => '供应商';

  @override
  String get homeWorkspaceTeamWorkspaces => '团队工作区';

  @override
  String get homeWorkspaceOwner => '团队所有者';

  @override
  String get homeWorkspaceImportWorkspace => '导入工作区';

  @override
  String get homeWorkspaceSessionsLabel => '会话';

  @override
  String get homeWorkspaceEmptyWorkspaces => '该团队还没有工作区';

  @override
  String get homeWorkspaceEmptyWorkspacesHint => '新建或导入一个工作区开始吧';

  @override
  String get homeWorkspaceWorkspaceSort => '排序工作区';

  @override
  String get homeWorkspaceWorkspaceSortRecentlyUpdated => '最近更新';

  @override
  String get homeWorkspaceWorkspaceSortNameAsc => '名称（A–Z）';

  @override
  String get homeWorkspaceWorkspaceSortNameDesc => '名称（Z–A）';

  @override
  String get homeWorkspaceWorkspaceSortCreatedDesc => '创建时间';

  @override
  String get homeWorkspaceWorkspaceSortSessionCountDesc => '会话数量';

  @override
  String get homeWorkspaceComingSoon => '功能开发中';

  @override
  String get homeWorkspaceNewTeamSubtitle => '选择团队协作模式，并填写团队名称。';

  @override
  String get homeWorkspaceNewTeamMethodCustom => '自定义模式';

  @override
  String get homeWorkspaceNewTeamMethodAi => 'AI 生成';

  @override
  String get homeWorkspaceNewTeamSubtitleAi => '描述团队需求，用 AI 生成团队配置草稿。';

  @override
  String get homeWorkspaceNewTeamRecommended => '推荐';

  @override
  String get homeWorkspaceNewTeamModeBeta => 'Beta';

  @override
  String get homeWorkspaceNewTeamNameHint => '请输入团队名称';

  @override
  String get homeWorkspaceCreateTeam => '创建团队';

  @override
  String get teamModeNativeTitle => '原生模式';

  @override
  String get teamModeMixedTitle => '混合模式';

  @override
  String get teamModeNativeDescription => '全部成员共用同一个 CLI，原生协同，配置简单。';

  @override
  String get teamModeMixedDescription => '不同成员可使用不同 CLI，通过 TeamBus 跨工具协作。';

  @override
  String get teamHubCloneOptionsTitle => '克隆选项';

  @override
  String get homeWorkspaceNewWorkspaceSubtitle => '选择工作区的工作目录，并为它命名。';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryLabel => '工作区目录';

  @override
  String get homeWorkspaceNewWorkspaceChooseDirectory => '选择文件夹';

  @override
  String get homeWorkspaceNewWorkspaceDirectoryHint => '尚未选择目录';

  @override
  String get homeWorkspaceNewWorkspaceNameHint => '默认使用文件夹名';

  @override
  String get homeWorkspaceCreateWorkspace => '创建工作区';

  @override
  String get homeWorkspaceCloseWorkspaceTitle => '关闭工作区？';

  @override
  String homeWorkspaceCloseWorkspaceMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '关闭该标签会终止此工作区中 $count 个运行中的会话。',
      one: '关闭该标签会终止此工作区中 1 个运行中的会话。',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceCloseWorkspaceConfirm => '关闭并终止会话';

  @override
  String get homeWorkspaceCloseAllTabsTitle => '关闭全部标签？';

  @override
  String homeWorkspaceCloseAllTabsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '关闭全部标签会终止 $count 个运行中的会话。',
      one: '关闭全部标签会终止 1 个运行中的会话。',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceWorkspaceManagement => '工作区管理';

  @override
  String get homeWorkspaceWorkspaceList => '工作区列表';

  @override
  String get homeWorkspaceConversations => '对话管理';

  @override
  String get homeWorkspaceConversationsSection => '对话';

  @override
  String get workspaceRunningSessionsSection => '正在运行';

  @override
  String get homeWorkspaceWorkspaceAgent => '智能体';

  @override
  String get workspaceAgentBuiltInSubtitle =>
      '当前 CLI 为 flashskyai 时，对应其 --agent 参数。';

  @override
  String get workspaceAgentExtraArgs => '额外 CLI 参数';

  @override
  String get workspaceAgentExtraArgsSubtitle => '附加在本工作区 Agent 启动时的 CLI 参数。';

  @override
  String get workspaceWorkbenchAdvancedSettingsSubtitle =>
      '本工作区的 Agent 预设与额外 CLI 参数。';

  @override
  String get workspaceAgentPromptSubtitle => '编写系统提示词，定义 Agent 在本工作区中的职责与行为边界。';

  @override
  String get workspaceAgentPromptPresetGeneral => '通用';

  @override
  String get workspaceAgentPromptPresetGeneralText =>
      '全面协助完成本工作区中的开发任务。先理解需求与现有代码，再给出清晰方案并实施；优先小范围改动，完成后说明涉及文件与后续建议。';

  @override
  String get workspaceAgentPromptPresetDeveloper => '开发';

  @override
  String get workspaceAgentPromptPresetDeveloperText =>
      '专注实现功能与修复问题。优先小 diff，跑相关测试，并简要说明改了哪些文件及原因。';

  @override
  String get workspaceAgentPromptPresetReviewer => '审查';

  @override
  String get workspaceAgentPromptPresetReviewerText =>
      '只做代码审查，除非被要求否则不要改文件。\n每条意见需包含：文件路径、行号、问题、建议改法。';

  @override
  String get workspaceAgentPromptPresetResearcher => '调研';

  @override
  String get workspaceAgentPromptPresetResearcherText =>
      '只调研并汇报，除非被要求否则不要改生产代码。\n输出需含文件路径、相关符号与建议的下一步。';

  @override
  String get workspaceCliEffortInheritHint => '使用提供商默认';

  @override
  String get workspaceCliDefaultSubtitle => '本工作区新建对话时使用的默认 CLI。';

  @override
  String get workspaceCliDefaultsTitle => 'CLI 默认配置';

  @override
  String get workspaceCliDefaultsSubtitle => '为本工作区使用的每个 CLI 设置默认提供商与模型。';

  @override
  String get workspaceCliProviderModelTitle => '提供商与模型';

  @override
  String get workspaceCliEffortLevel => '推理力度';

  @override
  String get workspaceCliEffortLevelSubtitle =>
      '本工作区使用该 CLI 时的默认力度（留空则使用提供商默认）。';

  @override
  String get workspaceCliConfigure => '配置';

  @override
  String get workspaceCliConfigured => '已配置';

  @override
  String get workspaceCliNotConfigured => '未配置';

  @override
  String get workspaceCliNotConfiguredHint => '选择提供商';

  @override
  String get workspaceCliNoProviderCatalog => '此 CLI 无需配置提供商';

  @override
  String workspaceCliConfigSummary(String provider, String model) {
    return '$provider · $model';
  }

  @override
  String get workspaceCliAddPresetTitle => '添加预设';

  @override
  String get workspaceCliEditPresetTitle => '编辑预设';

  @override
  String get workspaceCliPresetNameLabel => '预设名称';

  @override
  String get workspaceCliPresetsManageTitle => '管理预设';

  @override
  String get workspaceCliPresetsEmptyHint => '还没有预设，创建一个开始使用';

  @override
  String get workspaceCliDeletePresetTitle => '删除预设';

  @override
  String workspaceCliDeletePresetConfirm(String name) {
    return '删除预设\'$name\'？此操作不可撤销。';
  }

  @override
  String get workspaceCliPresetLabel => '当前预设';

  @override
  String get workspaceCliNoPresetHint => '未选择预设';

  @override
  String get workspaceCliManagePresets => '管理';

  @override
  String get workspaceCliProviderConfig => '供应商配置';

  @override
  String get teamDefaultPresetLabel => '默认模型预设';

  @override
  String get teamDefaultPresetSubtitle => '可选的默认预设，未单独设置的成员将继承此配置。';

  @override
  String get teamDefaultPresetNone => '无';

  @override
  String get teamDefaultPresetChange => '更改';

  @override
  String get teamDefaultPresetManage => '管理';

  @override
  String get teamDefaultCliMixedSubtitle => '成员未指定时使用。';

  @override
  String get teamDefaultDialogEffortSubtitle => '团队默认力度。';

  @override
  String get presetPickerTitle => '选择预设';

  @override
  String get presetPickerNoneOption => '无（不设默认）';

  @override
  String get memberPresetLabel => '预设';

  @override
  String get memberLaunchConfigTypeLabel => '配置类型';

  @override
  String get memberLaunchConfigTypePreset => '预设';

  @override
  String get memberLaunchConfigInheritHint => '使用团队的默认 CLI、服务商、模型与 Effort。';

  @override
  String get memberLaunchConfigInheritUnset => '团队默认尚未配置。';

  @override
  String get memberPresetInheritTeam => '继承团队默认';

  @override
  String get memberPresetInheritTeamNone => '团队未设置默认';

  @override
  String get memberPresetSelectPreset => '选择预设';

  @override
  String get memberPresetCustom => '自定义配置';

  @override
  String memberPresetViaPreset(String presetName) {
    return '$presetName（通过预设）';
  }

  @override
  String memberPresetViaTeamDefault(String presetName) {
    return '$presetName（通过团队默认）';
  }

  @override
  String get homeWorkspaceWorkspaceSkills => '技能';

  @override
  String get homeWorkspaceWorkspacePlugins => '插件';

  @override
  String get homeWorkspaceWorkspaceMcp => 'MCP';

  @override
  String get homeWorkspaceWorkspaceExtensions => '扩展';

  @override
  String workspaceSkillsAssignedCount(int assigned, int total) {
    return '已为本工作区启用 $assigned/$total';
  }

  @override
  String get workspaceSkillsManage => '管理 Skills';

  @override
  String workspaceMcpAssignedCount(int assigned, int total) {
    return '已为本工作区启用 $assigned/$total';
  }

  @override
  String get workspaceMcpManage => '管理 MCP';

  @override
  String workspacePluginsAssignedCount(int assigned, int total) {
    return '已为本工作区选用 $assigned/$total';
  }

  @override
  String get workspacePluginsManage => '管理插件';

  @override
  String get workspacePluginsEmpty => '尚未安装插件';

  @override
  String get workspacePluginsEmptyHint => '在「发现」中安装插件后，可在此处为本工作区启用。';

  @override
  String get workspaceExtensionsTitle => '本工作区的扩展';

  @override
  String get workspaceExtensionsSubtitle => '覆盖本工作区启用哪些扩展，默认跟随全局设置。';

  @override
  String get workspaceExtensionEffectiveOn => '本工作区已启用';

  @override
  String get workspaceExtensionEffectiveOff => '本工作区未启用';

  @override
  String get homeWorkspaceTeamConfig => '团队配置';

  @override
  String get homeWorkspaceWorkspaceSettings => '工作区设置';

  @override
  String get homeWorkspaceWorkspaceMembers => '成员';

  @override
  String get homeWorkspaceWorkspaceSettingsSectionBasic => '基本设置';

  @override
  String get homeWorkspaceWorkspaceSettingsBasicInfo => '基本信息';

  @override
  String get homeWorkspaceWorkspaceId => '工作区 ID';

  @override
  String homeWorkspaceWorkspaceAdditionalDirsCount(int count) {
    return '$count 个附加目录';
  }

  @override
  String get homeWorkspaceWorkspaceSettingsPathsHint =>
      '在「附加目录」行点击编辑，可添加或移除工作区附加目录。';

  @override
  String get deleteWorkspaceSubtitle => '将删除该工作区及其下所有会话，且无法恢复。';

  @override
  String get homeWorkspaceInviteMembers => '邀请成员';

  @override
  String get homeWorkspaceNewConversation => '新建对话';

  @override
  String get homeWorkspaceNewConversationChooseCli => '选择 CLI 新建对话';

  @override
  String get workbenchStripNewMenuTooltip => '新建';

  @override
  String get homeWorkspaceNoConversations => '该工作区还没有对话';

  @override
  String get homeWorkspaceSearchHint => '搜索';

  @override
  String get homeWorkspaceNoSearchResults => '没有匹配的对话';

  @override
  String get workspaceSearchTitle => '搜索';

  @override
  String get workspaceSearchHint => '搜索会话、文件和会话内容';

  @override
  String get workspaceSearchFilesSection => '文件';

  @override
  String get workspaceSearchSearching => '正在搜索文件…';

  @override
  String get workspaceSearchIndexing => '正在索引…';

  @override
  String get workspaceSearchRecentSessions => '最近会话';

  @override
  String get workspaceSearchFilterAll => '全部';

  @override
  String get workspaceSearchFilterConversations => '任务';

  @override
  String get workspaceSearchFilterFiles => '文件';

  @override
  String get workspaceSearchShowMore => '查看更多结果';

  @override
  String get workspaceSearchFilesEmptyHint => '输入关键词搜索文件';

  @override
  String get workspaceSearchNoResults => '没有匹配结果';

  @override
  String get appDropdownSearchHint => '搜索…';

  @override
  String get appDropdownSearchNoResults => '未找到结果';

  @override
  String get homeWorkspaceOpenWorkspaceInNewTab => '在新标签页中打开';

  @override
  String get homeWorkspaceOpenInNewTabWithOtherIdentity => '以其他身份在新标签页打开…';

  @override
  String get homeWorkspaceFavoriteWorkspace => '收藏工作区';

  @override
  String get homeWorkspaceUnfavoriteWorkspace => '取消收藏';

  @override
  String get homeWorkspaceRenameWorkspace => '修改名称';

  @override
  String get homeWorkspaceCloneWorkspace => '克隆工作区';

  @override
  String homeWorkspaceCloneWorkspaceDisplayName(Object name) {
    return '$name（副本）';
  }

  @override
  String homeWorkspaceCloneWorkspaceSuccess(Object name) {
    return '已克隆「$name」。';
  }

  @override
  String get homeWorkspaceCloneWorkspaceFailed => '无法克隆工作区';

  @override
  String get newWorkspaceTooltip => '创建工作区';

  @override
  String get switchWorkspaceTooltip => '切换工作区';

  @override
  String get create => '创建';

  @override
  String get pickPrimaryDirectory => '选择主目录';

  @override
  String get workspacePrimaryPathRequired => '请先选择主目录。';

  @override
  String get workspacePrimaryPathNotSelected => '尚未选择主目录';

  @override
  String get workspaceDirectoryAdded => '已添加目录到工作区';

  @override
  String get newSessionTooltip => '新建会话';

  @override
  String get defaultNewChatSessionTitle => '新对话';

  @override
  String get sessionIdleNotificationTitle => 'Agent 已就绪';

  @override
  String get sessionIdleNotificationSubtitle => '可以继续对话了';

  @override
  String get sessionStarting => '正在启动会话…';

  @override
  String get sessionHistoryLoading => '正在加载对话历史…';

  @override
  String get sessionHistoryRefreshing => '正在刷新对话…';

  @override
  String get sessionHistoryEmpty => '该成员暂无历史消息。';

  @override
  String get sessionHistoryError => '无法加载对话历史。';

  @override
  String get sessionHistorySoftReloadError => '无法刷新对话历史。';

  @override
  String get agentPermissionAttentionBanner => '此智能体需要在终端中确认。';

  @override
  String get agentPermissionOpenTerminal => '打开终端';

  @override
  String get exitPlanModeTitle => '计划已就绪，等待批准';

  @override
  String get exitPlanModeApprove => '批准';

  @override
  String get exitPlanModeReject => '拒绝';

  @override
  String get exitPlanModeCopyPlan => '复制计划';

  @override
  String get exitPlanModeExpand => '展开';

  @override
  String get exitPlanModeCollapse => '收起';

  @override
  String get exitPlanModeOpenPlanFile => '打开计划文件';

  @override
  String get exitPlanModeApproveFailed => '批准计划失败';

  @override
  String get exitPlanModeRejectFailed => '拒绝计划失败';

  @override
  String get agentAskUserQuestionTitle => '正在向你提问';

  @override
  String get agentAskAnswerInTerminal => '在终端回答';

  @override
  String get agentAskCancelQuestion => '取消提问';

  @override
  String get agentAskAnswerFailed => '无法提交回答。请重试或在终端中回答。';

  @override
  String get agentAskTerminalDisconnected => '终端已断开。请重新连接或在终端中回答。';

  @override
  String get agentAskSubmitAnswers => '提交';

  @override
  String get agentAskContinue => '继续';

  @override
  String get agentAskIgnore => '忽略';

  @override
  String get agentAskKeyboardHint => '使用 Tab / 上下键选择，回车或空格选中';

  @override
  String get agentAskCustomAnswerHint => '输入你的回答…';

  @override
  String get agentAskEscToCancel => 'Esc 取消';

  @override
  String agentAskQuestionTabFallback(int index) {
    return '问题$index';
  }

  @override
  String get opencodePermissionTitle => 'OpenCode 需要你的授权';

  @override
  String get opencodePermissionAllowOnce => '允许一次';

  @override
  String get opencodePermissionAllowAlways => '总是允许';

  @override
  String get opencodePermissionReject => '拒绝';

  @override
  String get opencodePermissionAnswerFailed => '无法提交你的决定。请重试或在终端中处理。';

  @override
  String get opencodePermissionAnswerInTerminal => '在终端处理';

  @override
  String get sessionHistoryRetry => '重试';

  @override
  String get sessionHistoryToolTurn => '工具';

  @override
  String get sessionHistoryRoleUser => '你';

  @override
  String get sessionHistoryRoleAssistant => '助手';

  @override
  String get sessionHistoryRoleSystem => '系统';

  @override
  String get sessionHistoryComposeHint => '继续对话… @ 引用文件，/ 调用技能与指令';

  @override
  String get sessionHistoryComposeStop => '停止生成';

  @override
  String get sessionHistoryContinueSaveFailed => '无法保存继续会话设置。';

  @override
  String get sessionHistoryLoadOlderHint => '上滑查看更早消息';

  @override
  String get sessionHistoryNewMessages => '新消息';

  @override
  String get sessionHistoryStarting => '启动中…';

  @override
  String get sessionHistoryRunning => '运行中…';

  @override
  String sessionHistoryMailboxQueued(int count) {
    return '$count 已排队';
  }

  @override
  String get sessionHistoryMailboxQueuedDismiss => '关闭';

  @override
  String sessionFollowUpQueued(int count) {
    return '$count 排队中';
  }

  @override
  String get sessionFollowUpAddPlaceholder => '添加跟进消息';

  @override
  String get sessionFollowUpResume => '继续队列';

  @override
  String get sessionFollowUpEdit => '编辑';

  @override
  String get sessionFollowUpMoveUp => '上移';

  @override
  String get sessionFollowUpDelete => '删除';

  @override
  String get aiMessageUsedTool => '已使用工具';

  @override
  String get aiMessageCancelledTool => '已取消工具';

  @override
  String aiMessageToolsUsed(Object count) {
    return '已使用 $count 个工具';
  }

  @override
  String get aiMessageReasoning => '推理';

  @override
  String get aiMessageToolResult => '结果';

  @override
  String get aiMessageCopied => '已复制';

  @override
  String get aiMessageExportMarkdown => '导出 Markdown';

  @override
  String get aiMessageIncomplete => '消息未完成';

  @override
  String get aiMessageCancelled => '消息已取消';

  @override
  String get aiMessageScrollToBottom => '滚动到底部';

  @override
  String get aiMessageShowMore => '显示更多';

  @override
  String get aiMessageShowLess => '收起';

  @override
  String get aiMessageThinkingProcess => '思考过程';

  @override
  String aiMessageThinkingProcessSteps(int count) {
    return '思考过程 · $count 步';
  }

  @override
  String aiToolFileNotFound(String path) {
    return '找不到文件：$path';
  }

  @override
  String get subagentPreviewUnavailable => '无法打开该子会话预览';

  @override
  String get subagentPreviewBack => '返回';

  @override
  String get subagentPreviewEmpty => '暂无子会话内容';

  @override
  String get workflowCardRunMissing => '未找到该调用的 Workflow 运行记录';

  @override
  String workflowCardAgents(int count) {
    return '$count 个 agent';
  }

  @override
  String subagentPreviewTitleAgent(String title) {
    return '$title';
  }

  @override
  String get sessionWorkbenchShowChat => '显示聊天';

  @override
  String get sessionWorkbenchShowTerminal => '显示终端';

  @override
  String get sessionReadyTitle => '准备开始对话';

  @override
  String sessionReadySubtitle(String memberName) {
    return '与 $memberName 在此工作区中开始对话';
  }

  @override
  String get sessionReadySubtitleGeneric => '在此工作区中开始新对话';

  @override
  String get sessionReadyHint => '用日常语言描述你想做的事即可，无需输入命令。';

  @override
  String get workspaceChatLandingInputHint => '今天帮你做些什么？ @ 引用对话文件，/ 调用技能与指令';

  @override
  String get workspaceChatLandingBackToStart => '返回启动页';

  @override
  String get workspaceChatLandingSelectWorkspace => '选择工作空间 >';

  @override
  String get workspaceChatLandingSelectProject => '选择项目 >';

  @override
  String get workspaceChatLandingSelectWorktree => '选择 worktree >';

  @override
  String get workspaceChatLandingSelectLaunchDirectory => '选择目录 >';

  @override
  String get workspaceChatLandingModeTeam => '团队';

  @override
  String get workspaceChatLandingModeSimple => '简单对话';

  @override
  String get workspaceChatLandingUsePreset => '使用预设';

  @override
  String get workspaceChatLandingCustomLaunch => '自定义…';

  @override
  String get workspaceChatLandingCustomLaunchTitle => '自定义启动';

  @override
  String get workspaceChatLandingFullAccessPermissions => '完全访问权限';

  @override
  String get workspaceChatLandingSkills => '技能';

  @override
  String get workspaceChatLandingConnectApps => '连应用';

  @override
  String get workspaceChatLandingDefaultPermissions => '默认权限';

  @override
  String get workspaceChatLandingAttach => '附加文件';

  @override
  String get workspaceChatLandingEnhance => '优化提示词';

  @override
  String get workspaceChatLandingVoice => '语音输入';

  @override
  String get workspaceChatLandingVoiceCancel => '取消录音';

  @override
  String get workspaceChatLandingVoiceStop => '停止录音';

  @override
  String get workspaceChatLandingEnhanceEmpty => '请先输入内容再优化';

  @override
  String get workspaceChatLandingEnhanceNotConfigured =>
      '请先配置 CLI 预设或团队 Provider';

  @override
  String get workspaceChatLandingEnhanceFailed => '无法优化提示词';

  @override
  String get workspaceChatLandingVoiceUnavailable => '此设备不支持语音输入';

  @override
  String get workspaceChatLandingVoicePermissionDenied => '未获得麦克风权限';

  @override
  String get landingTeamSettingsNavTeam => '团队默认';

  @override
  String get landingTeamSettingsNavMachines => '机器分配';

  @override
  String get landingTeamSettingsGlobalHint => '更改将应用于该团队的全局配置。';

  @override
  String get workspaceChatLandingTeamLaunchBlocked =>
      '请先在团队设置中配置团队与成员的模型预设，再发送消息。';

  @override
  String get landingLaunchRemoteCliMissing => '启动前请在远程机器上安装所需的 CLI。';

  @override
  String landingLaunchRemoteCliMissingDetail(String cli, String host) {
    return '$host 上缺少 $cli';
  }

  @override
  String get remoteCliMachineReadinessTitle => '此机器上需要的 CLI';

  @override
  String get remoteCliMachineReadinessProbing => '正在检测…';

  @override
  String remoteCliMachineReadinessReady(String cli, String path) {
    return '$cli 已就绪：$path';
  }

  @override
  String remoteCliMachineReadinessMissing(String cli) {
    return '未找到 $cli — 请安装或设置手动路径';
  }

  @override
  String remoteCliMachineReadinessFailed(String cli, String message) {
    return '$cli：$message';
  }

  @override
  String get remoteCliMachineReadinessInstallHint =>
      '对每个缺失的 CLI 点击安装，或在目标设置中指定手动路径。';

  @override
  String get sessionStartButton => '开始对话';

  @override
  String get sessionFailedTitle => '未能启动会话';

  @override
  String get sessionRetryButton => '重试';

  @override
  String get openFolder => '打开文件夹';

  @override
  String get copyFolderPath => '复制文件夹路径';

  @override
  String pathCopied(String path) {
    return '已复制路径：$path';
  }

  @override
  String get workspaceDetails => '工作区详情';

  @override
  String get workspaceDetailsTitle => '工作区详情';

  @override
  String get addWorkspaceDirectory => '添加目录';

  @override
  String get removeWorkspaceDirectory => '移除目录';

  @override
  String get workspaceDisplayName => '显示名称';

  @override
  String get workspaceIcon => '图标';

  @override
  String get workspaceIconPickerTitle => '选择工作区图标';

  @override
  String get workspaceIconUseDefault => '使用默认';

  @override
  String get workspaceIconUpload => '上传图标';

  @override
  String get workspaceIconUploadFailed => '无法保存图标，请使用 PNG、JPG、WEBP 或 SVG。';

  @override
  String get workspacePrimaryPath => '主目录';

  @override
  String get workspaceAdditionalDirectories => '附加目录';

  @override
  String get workspaceNoAdditionalDirectories => '暂无附加目录';

  @override
  String get workspaceSessionCount => '会话数';

  @override
  String get workspaceCreatedAt => '创建时间';

  @override
  String get workspaceUpdatedAt => '更新时间';

  @override
  String get workspaceDirectoryAlreadyPrimary => '该路径已是工作区主目录。';

  @override
  String get workspaceDirectoryAlreadyAdded => '该目录已在工作区中。';

  @override
  String get editWorkspacePrimaryPath => '编辑主目录';

  @override
  String get remoteDirectoryBrowserTitle => '浏览远程目录';

  @override
  String get remoteDirectoryBrowserUpOneLevel => '上一级';

  @override
  String get remoteDirectoryBrowserUseThisDirectory => '使用此目录';

  @override
  String get remoteDirectoryBrowserTypePathLabel => '或手动输入路径';

  @override
  String get remoteDirectoryBrowserTypePathHint => '~/work/workspace';

  @override
  String get remoteDirectoryBrowserUseTypedPath => '使用路径';

  @override
  String get remoteDirectoryBrowserError => '无法打开远程目录。你仍可在下方手动输入路径。';

  @override
  String get remoteDirectoryBrowserEmpty => '此处没有子目录';

  @override
  String get deleteWorkspace => '删除工作区';

  @override
  String deleteWorkspaceConfirm(String name) {
    return '删除工作区 \"$name\" 及其所有会话？此操作不可撤销。';
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
  String get pinConversation => '置顶对话';

  @override
  String get unpinConversation => '取消置顶';

  @override
  String get sessionSortManual => '手动排序';

  @override
  String get sessionSortRecentlyUpdated => '最近更新';

  @override
  String get sessionSortCreatedDesc => '创建时间';

  @override
  String get sessionSortTooltip => '排序对话';

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
  String get closeAllTabs => '关闭全部';

  @override
  String get session => '会话';

  @override
  String get sessionPageSubtitle => '配置 Shell 会话启动方式、终端行为与存储后端。';

  @override
  String get cliConfig => 'CLI';

  @override
  String get cliConfigPageSubtitle => '配置 AI 代理 CLI 可执行文件路径，并安装缺失的工具。';

  @override
  String get sshProfilesSettingsTitle => 'SSH 服务器';

  @override
  String get sshProfilesPageTitle => 'SSH 远程主机';

  @override
  String get sshProfilesPageSubtitle => '通过 SSH 使用已有机器处理文件、终端、Git 和工作区。';

  @override
  String get sshProfilesTargetsTitle => '目标';

  @override
  String get sshProfilesTargetsSubtitle => '添加远程主机以在 TeamPilot 中连接到它。';

  @override
  String get sshProfilesImport => '导入';

  @override
  String get sshProfilesImportUnavailable => '暂不支持从 ~/.ssh/config 导入。';

  @override
  String get sshProfilesAddTarget => '添加目标';

  @override
  String get sshProfilesEmpty => '尚未配置 SSH 目标。';

  @override
  String get sshProfileStatusDisconnected => '未连接';

  @override
  String get sshProfileStatusConnecting => '连接中…';

  @override
  String get sshProfileStatusConnected => '已连接';

  @override
  String get sshProfileStatusError => '错误';

  @override
  String get sshProfileStatusReconnecting => '重连中…';

  @override
  String get sshProfileStatusAuthFailed => '认证失败';

  @override
  String sshHostsPillCount(int count) {
    return '$count 台主机';
  }

  @override
  String get sshHostsPillConnecting => '连接中…';

  @override
  String get sshHostsPanelTitle => '远程主机';

  @override
  String get sshHostsRowKind => 'SSH 主机';

  @override
  String get sshHostsManage => '管理远程主机';

  @override
  String get sshProfileTest => '测试';

  @override
  String get sshProfileConnect => '连接';

  @override
  String get sshProfileDisconnect => '断开';

  @override
  String get sshProfileEdit => '编辑';

  @override
  String get sshProfileDelete => '删除';

  @override
  String get sshProfileRefresh => '刷新';

  @override
  String get sshProfileTestSuccess => '连接成功';

  @override
  String get sshProfileTestFailed => '连接测试失败';

  @override
  String get sshProfileTestFailedHostKey => '主机密钥未获信任';

  @override
  String get sshProfileTestFailedAuth => '身份验证失败';

  @override
  String sshProfileTestFailedAborted(String detail) {
    return '登录前连接已断开：$detail';
  }

  @override
  String sshProfileTestFailedDetail(String detail) {
    return '连接测试失败：$detail';
  }

  @override
  String sshProfileConnectSuccess(String host) {
    return '已连接到 $host';
  }

  @override
  String get sshHostKeyUnknownTitle => '验证 SSH 主机密钥';

  @override
  String sshHostKeyUnknownBody(String host) {
    return 'TeamPilot 尚未见过 $host。请确认指纹与该机器一致后再信任。';
  }

  @override
  String get sshHostKeyMismatchTitle => 'SSH 主机密钥已变更';

  @override
  String sshHostKeyMismatchBody(String host) {
    return '$host 的主机密钥与 TeamPilot 先前保存的不一致。可能是系统重装，也可能是连接被劫持。';
  }

  @override
  String get sshHostKeyFingerprintLabel => '指纹';

  @override
  String get sshHostKeyPreviousFingerprintLabel => '先前信任的指纹';

  @override
  String sshHostKeyKeyTypeLabel(String keyType) {
    return '密钥类型：$keyType';
  }

  @override
  String get sshHostKeyTrust => '信任并继续';

  @override
  String get sshHostKeyReplaceTrust => '替换并信任';

  @override
  String get sshProfileFormTitleNew => '新的 SSH 目标';

  @override
  String get sshProfileFormTitleEdit => '编辑 SSH 目标';

  @override
  String get sshProfileFormLabel => '标签';

  @override
  String get sshProfileFormLabelHint => '我的服务器';

  @override
  String get sshProfileFormHost => '主机或别名';

  @override
  String get sshProfileFormHostHint => 'server、deploy@server:2222';

  @override
  String get sshProfileFormUsername => '用户名';

  @override
  String get sshProfileFormUsernameHint => 'deploy';

  @override
  String get sshProfileFormPort => '端口';

  @override
  String get sshProfileFormPortInvalid => '端口须在 1–65535 之间';

  @override
  String get sshProfileFormIdentityFile => '身份文件';

  @override
  String get sshProfileFormIdentityFileHint => '~/.ssh/id_ed25519';

  @override
  String get sshProfileFormIdentityFileHelper => '可选。填写后从磁盘读取私钥。';

  @override
  String get sshProfileFormIdentityFileBrowse => '浏览…';

  @override
  String get sshProfileFormIdentityFileMissing => '找不到身份文件';

  @override
  String get sshProfileFormPassphrase => '密钥口令';

  @override
  String get sshProfileFormPassphraseHint => '可选';

  @override
  String get sshProfileFormPassword => '密码';

  @override
  String get sshProfileFormPasswordHint => '未设置身份文件时使用';

  @override
  String get sshProfileFormPasswordHintEdit => '留空则保留已保存密码';

  @override
  String get sshProfileFormPasswordHelper => '若已提供身份文件则可不填。';

  @override
  String get sshProfileFormCredentialRequired => '请提供身份文件或密码。';

  @override
  String get sshProfileFormCredentialSaveFailed =>
      '目标已保存，但无法写入凭据。请解锁系统钥匙环后编辑该目标并重新填写。';

  @override
  String get sshProfileFormFieldRequired => '必填';

  @override
  String get sshProfileSelectorTooltip => '切换 SSH 服务器';

  @override
  String get sshProfileSelectorManage => '管理 SSH 服务器…';

  @override
  String get sshDefaultWorkingDirectoryTitle => 'SSH 默认工作目录';

  @override
  String get sshDefaultWorkingDirectorySubtitle =>
      'SSH 启动没有工作区路径时使用的远端工作目录；留空则不切换目录。';

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
  String get cliExecutablePathLocate => '定位';

  @override
  String cliExecutablePathLocateFailed(String name) {
    return '未能在 PATH 上找到 $name。';
  }

  @override
  String cliExecutablePathLocateSuccess(String name, String path) {
    return '已定位 $name：$path。';
  }

  @override
  String get cliExecutablePathLocateRemoteUnsupported => '远程工作面不支持定位此工具。';

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
  String get cliInstallProgressInstallingCli => '正在安装 CLI…';

  @override
  String get cliInstallProgressLocatingExecutable => '正在定位 CLI 可执行文件…';

  @override
  String get cliInstallProgressSyncingRemoteWorkspace => '正在同步远程工作区…';

  @override
  String get sessionRemoteProvisionPreparing => '正在准备远程环境…';

  @override
  String sessionRemoteProvisionPreparingOnHost(String host) {
    return '正在准备远程环境（$host）';
  }

  @override
  String sessionRemoteProvisionTitle(String member, String host) {
    return '正在准备 $member（$host）';
  }

  @override
  String get sessionRemoteProvisionFailed => '远程准备失败';

  @override
  String cliExecutablePathLabelFor(String cli) {
    return '$cli CLI 路径';
  }

  @override
  String cliExecutablePathDescriptionFor(String cli) {
    return '$cli 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';
  }

  @override
  String cliExecutablePathDescriptionSshFor(String cli) {
    return '远程 SSH 主机上 $cli 的绝对路径。留空则通过 SSH 自动探测。';
  }

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
  String get terminalFind => '在终端中查找';

  @override
  String get terminalFindNoResults => '无匹配';

  @override
  String get terminalDropCrossMachineRejected => '无法将本地文件拖入远程终端';

  @override
  String get editorTitle => '编辑器';

  @override
  String get editorSave => '保存';

  @override
  String get editorCut => '剪切';

  @override
  String get editorCopy => '复制';

  @override
  String get editorCopyAsAiContext => '复制为 AI 上下文';

  @override
  String get selectionAskAi => '用 AI 提问…';

  @override
  String get editorPaste => '粘贴';

  @override
  String get editorSelectAll => '全选';

  @override
  String get editorUndoEdit => '撤销';

  @override
  String get editorRedoEdit => '重做';

  @override
  String get editorRevertChanges => '撤销修改';

  @override
  String get editorClose => '关闭编辑器';

  @override
  String get editorUnsavedChangesTitle => '未保存的更改';

  @override
  String editorUnsavedChangesDiscardFile(String fileName) {
    return '放弃对「$fileName」的未保存修改？';
  }

  @override
  String editorUnsavedChangesDiscardMultiple(int count) {
    return '放弃 $count 个文件中的未保存修改？';
  }

  @override
  String get editorDiscard => '放弃';

  @override
  String get editorNotReady => '编辑器未就绪';

  @override
  String get editorNoFileOpen => '未打开文件';

  @override
  String get editorBinaryFileHint => '二进制文件将使用系统默认应用打开。';

  @override
  String get editorFileNotFound => '找不到文件';

  @override
  String get editorFileTooLarge => '文件过大，无法在 TeamPilot 中编辑（上限 2 MB）。';

  @override
  String get editorImageTooLarge => '图片过大，无法在 TeamPilot 中预览（上限 25 MB）。';

  @override
  String get editorImageDecodeFailed => '无法解码此图片。';

  @override
  String get editorCouldNotReadFile => '无法读取文件';

  @override
  String get editorFileReadOnly => '文件为只读';

  @override
  String editorSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get editorFindHint => '查找';

  @override
  String get editorFindReplaceHint => '替换';

  @override
  String get editorFindReplaceAll => '全部替换';

  @override
  String get editorFindPrevious => '上一个匹配';

  @override
  String get editorFindNext => '下一个匹配';

  @override
  String get editorFindClose => '关闭';

  @override
  String get editorFindMatchCase => '区分大小写';

  @override
  String get editorFindUseRegex => '使用正则表达式';

  @override
  String get editorFindWholeWord => '全字匹配';

  @override
  String get editorFindToggleReplace => '切换替换';

  @override
  String get editorFindInSelection => '在选定内容中查找';

  @override
  String get editorFindReplacePreserveCase => '保留大小写';

  @override
  String get editorFindReplaceOne => '替换';

  @override
  String get editorFindNoResults => '无匹配';

  @override
  String get fileTreeRevealActiveFile => '定位当前文件';

  @override
  String get fileTreeRefresh => '刷新';

  @override
  String get fileTreeShowFilter => '显示筛选';

  @override
  String get fileTreeHideFilter => '隐藏筛选';

  @override
  String get fileTreeRevealFailed => '无法在文件树中定位该文件';

  @override
  String get fileTreeOpenWithSystemApp => '用系统应用打开';

  @override
  String get fileTreeCopyPath => '复制路径';

  @override
  String get fileTreeCopyRelativePath => '复制相对路径';

  @override
  String get fileTreeDeleteItemTitle => '删除';

  @override
  String fileTreeDeleteItemConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get fileTreeNewFile => '新建文件';

  @override
  String get fileTreeNewFolder => '新建文件夹';

  @override
  String get fileTreeCreateNameHint => '名称';

  @override
  String get fileTreeCut => '剪切';

  @override
  String get fileTreeCopy => '复制';

  @override
  String get fileTreePaste => '粘贴';

  @override
  String get fileTreeRename => '重命名';

  @override
  String get fileTreeRenameTitle => '重命名';

  @override
  String get fileTreeOpenInFileManager => '在文件管理器中打开';

  @override
  String get fileTreeOpenInTerminal => '在终端中打开';

  @override
  String get fileTreePasteDone => '已粘贴';

  @override
  String get fileTreeFileCreated => '已创建文件';

  @override
  String get fileTreeFolderCreated => '已创建文件夹';

  @override
  String get fileTreeRenameDone => '已重命名';

  @override
  String get fileTreeDeleteDone => '已删除';

  @override
  String get fileTreeInvalidName => '名称无效';

  @override
  String get fileTreeItemExists => '同名项目已存在';

  @override
  String get fileTreeSourceMissing => '源文件不存在';

  @override
  String get fileTreeInvalidPasteTarget => '无法粘贴到此处';

  @override
  String get fileTreeOpenInTerminalFailed => '无法打开终端';

  @override
  String get fileTreeImportConflictTitle => '项目已存在';

  @override
  String fileTreeImportConflictBody(String name) {
    return '目标位置已存在「$name」。';
  }

  @override
  String fileTreeImportConflictRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '之后还有 $count 个冲突。',
      zero: '没有更多冲突。',
    );
    return '$_temp0';
  }

  @override
  String get fileTreeImportConflictTypeMismatch => '文件和文件夹不能互相替换。';

  @override
  String get fileTreeImportOverwrite => '覆盖';

  @override
  String get fileTreeImportSkip => '跳过';

  @override
  String get fileTreeImportCancelAll => '全部取消';

  @override
  String get fileTreeImportApplyRemaining => '应用于剩余冲突';

  @override
  String get fileTreeImportProgressTitle => '正在导入…';

  @override
  String get fileTreeImportProgressCancel => '取消';

  @override
  String fileTreeImportProgressCurrent(String name) {
    return '$name';
  }

  @override
  String fileTreeImportProgressItems(int completed, int total) {
    return '$completed / $total';
  }

  @override
  String fileTreeImportSummary(int succeeded, int skipped, int failed) {
    return '成功 $succeeded，跳过 $skipped，失败 $failed';
  }

  @override
  String get fileTreeImportSummaryCancelledSuffix => ' — 已取消';

  @override
  String get fileTreeImportRejectSelf => '无法将项目移动到自身或其子目录中。';

  @override
  String get fileTreeImportDropCopy => '复制';

  @override
  String get fileTreeImportDropMove => '移动';

  @override
  String get terminalOpenLink => '打开链接';

  @override
  String get terminalExportScrollback => '导出滚动缓冲…';

  @override
  String get terminalCopySelectHint => '按住 Shift 选择复制';

  @override
  String get workspaceTerminal => '终端';

  @override
  String get workspaceTerminalClose => '关闭终端面板';

  @override
  String get workspaceTerminalNoWorkingDirectory => '请先连接会话以打开 Shell 终端';

  @override
  String get workspaceTerminalNewSession => '新建终端';

  @override
  String get workspaceTerminalNewSessionMenu => '新建终端会话菜单';

  @override
  String get workspaceTerminalNewSshSession => '新建 SSH 会话…';

  @override
  String get workspaceTerminalSettings => '设置';

  @override
  String get terminalThemeModeTitle => '终端主题';

  @override
  String get terminalThemeModeDescription => '跟随主题色或使用固定风格';

  @override
  String get workspaceTerminalThemeAdaptive => '跟随主题';

  @override
  String get workspaceTerminalThemeClassicDark => '经典暗色';

  @override
  String get workspaceTerminalThemeHighContrast => '高对比';

  @override
  String get workspaceTerminalSshConnectFailed => 'SSH 配置未找到或连接失败';

  @override
  String get workspaceToolsResolveFailed => '无法打开工作区工具';

  @override
  String get workspaceToolsResolveFailedHint => '请确认远程机器可连通后再重试。';

  @override
  String get workspaceTerminalCloseSession => '关闭终端';

  @override
  String get terminalScrollbackLinesTitle => '终端滚动缓冲行数';

  @override
  String get terminalScrollbackLinesDescription => '每个会话终端保留的最大行数';

  @override
  String get terminalLinkClickOpensInAppTitle => '在应用内打开终端链接';

  @override
  String get terminalLinkClickOpensInAppDescription =>
      '左键点击链接和文件路径时在 TeamPilot 内打开，而不是交给正在运行的程序。Ctrl/Cmd+点击始终在应用内打开。';

  @override
  String terminalParkedSendPending(String content) {
    return '已发送，等待接收：$content';
  }

  @override
  String get terminalParkedSendDismiss => '关闭';

  @override
  String get mailbox => '信箱';

  @override
  String get mailboxEmpty => '暂无消息';

  @override
  String get board => '看板';

  @override
  String get boardEmpty => '暂无任务';

  @override
  String get boardPending => '待认领';

  @override
  String get boardClaimed => '进行中';

  @override
  String get boardDone => '已完成';

  @override
  String get visibilityBoardHint => '显示混合模式团队的任务看板。';

  @override
  String get autoLaunchAllMembersTitle => '连接时启动全部成员';

  @override
  String get autoLaunchAllMembersDescription =>
      '开启后，点击连接或重启会为每个有效成员启动终端；关闭则仅启动当前选中的成员。';

  @override
  String get memberTerminalReclaimedTitle => '终端已回收以释放内存';

  @override
  String get memberTerminalReclaimedBody => '点击重新连接（会话会恢复）';

  @override
  String get memberTerminalNotStartedTitle => '终端未启动 — 点击启动';

  @override
  String get reclaimIdleTerminalsTitle => '回收空闲终端';

  @override
  String get reclaimIdleTerminalsDescription => '空闲超时后关闭成员/会话终端以释放内存；需要时自动重连。';

  @override
  String get reclaimIdleTerminalMinutesTitle => '空闲回收超时（分钟）';

  @override
  String get reclaimIdleTerminalMinutesDescription => '终端可保持空闲多少分钟后被回收。';

  @override
  String get openExistingSessionStartsTerminalTitle => '打开已有会话时直接启动终端';

  @override
  String get openExistingSessionStartsTerminalDescription =>
      '开启后，从侧边栏打开对话会立即连接终端。关闭（默认）时先显示聊天视图，发送消息后才启动终端。';

  @override
  String get chatSubmitSwitchesToTerminalTitle => '发送后切换到终端';

  @override
  String get chatSubmitSwitchesToTerminalDescription =>
      '关闭（默认）时，在聊天页发送（新建或继续）后仍留在聊天视图，终端在后台运行。开启后，发送后切换到终端。';

  @override
  String get simpleModeDefaultFullAccessTitle => '简单模式默认：完全访问';

  @override
  String get simpleModeDefaultFullAccessDescription =>
      '开启（默认）时，简单模式落地页默认使用完全访问权限。工作区里权限芯片的选择仍会覆盖并按工作区持久化。';

  @override
  String get scopeSessionsToSelectedTeamTitle => '按所选团队筛选会话';

  @override
  String get scopeSessionsToSelectedTeamDescription =>
      '开启后，侧边栏仅显示归属当前团队的会话。新建会话仍会写入当前所选团队，之后开启本选项即可看到它们。';

  @override
  String get notifyOnSessionIdleTitle => 'Agent 空闲系统通知';

  @override
  String get notifyOnSessionIdleDescription =>
      '会话结束一轮工作并进入空闲时，除应用内通知中心外，同时发送操作系统通知。';

  @override
  String get memberTargetAssignmentTitle => '成员所在机器';

  @override
  String memberTargetAssignmentSubtitle(Object member) {
    return '$member 运行所在的机器（其分配的工作区目录）。';
  }

  @override
  String get memberTargetAssignmentInherit => '继承工作区目录';

  @override
  String get memberAssignFoldersAction => '分配目录…';

  @override
  String get credentialPushOptInTitle => '把凭证推送到此机器';

  @override
  String get credentialPushOptInSubtitle => '供远程成员认证使用。';

  @override
  String get credentialPushConfirmTitle => '确认把凭证推送到远程主机？';

  @override
  String credentialPushConfirmBody(Object host) {
    return 'provider 密钥将写入远程主机 $host。请仅对你信任的机器开启。轮换密钥后需重推到每台已开启的机器。';
  }

  @override
  String get credentialPushConfirmAction => '推送凭证';

  @override
  String get rootSandboxEnvOptInTitle => '为 root 注入 IS_SANDBOX';

  @override
  String get rootSandboxEnvOptInSubtitle =>
      'root 启动 Claude 时保留 skip-permissions。';

  @override
  String get rootSandboxEnvConfirmTitle => '确认为 root 启用 sandbox 环境变量？';

  @override
  String rootSandboxEnvConfirmBody(Object host) {
    return '在 $host 上以 root 启动 Claude 时，TeamPilot 将设置 IS_SANDBOX=1 并保留 --dangerously-skip-permissions。请仅对你信任的机器开启。';
  }

  @override
  String get rootSandboxEnvConfirmAction => '启用';

  @override
  String get workspaceTargetTitle => '工作区所在机器';

  @override
  String get workspaceTargetSubtitle =>
      '该工作区的目录所在并运行的机器。会话在此 target 上启动；切换不会移动文件。';

  @override
  String get workspaceFoldersSectionTitle => '工作区目录与机器';

  @override
  String get workspaceFoldersEditorHint =>
      '每个目录单独指定所在机器与路径。全部本地 = 本地工作区；全部同一远程 = 项目远程；跨机 = 混合工作区（成员远程）。';

  @override
  String get workspaceFoldersMixedTargetsLockedHint =>
      '混合工作区：各目录所在机器已固定。可在上方现有机器上添加路径；成员分配请使用下方「分配」按钮。';

  @override
  String get workspaceFoldersPersonalTargetsLockedHint =>
      '个人身份下无法更改目录所在机器。请切换到团队身份配置机器与目录。';

  @override
  String get workspaceFoldersPickMixedTarget => '添加到机器';

  @override
  String get workspaceTopologyLocal => '本地工作区';

  @override
  String get workspaceTopologyRemote => '远程工作区';

  @override
  String get workspaceTopologyMixed => '混合工作区';

  @override
  String get workspaceTypeLabel => '类型';

  @override
  String get mixedWorkspaceRequiresTeamLaunch =>
      '混合工作区只能通过团队身份启动。请切换到团队，并在团队设置中确认机器分配。';

  @override
  String get mixedWorkspacePersonalLaunchBlockedHint =>
      '这是混合工作区。请切换到团队标签页启动对话，并确认机器分配。';

  @override
  String get mixedWorkspaceMemberAssignmentTitle => '分配成员到机器';

  @override
  String get mixedWorkspaceMemberAssignmentSubtitle =>
      '左侧选择机器，右侧用 + / − 放置各成员的实例。';

  @override
  String get mixedWorkspaceMemberAssignmentIncomplete =>
      '混合工作区首次启动前，请先确认成员的机器分配。';

  @override
  String get mixedWorkspaceLeadPlacementInvalid =>
      '工作区包含本地文件夹时，团队负责人必须分配到本地主机。';

  @override
  String get mixedWorkspaceMemberAssignmentConfirm => '启动团队';

  @override
  String get workspaceMemberTargetsSectionTitle => '成员机器分配';

  @override
  String get workspaceMemberTargetsSectionSubtitle =>
      '与本团队新建对话时的默认分配。已有对话保持创建时的分配不变。';

  @override
  String get workspaceMemberTargetsSave => '保存分配';

  @override
  String get workspaceMemberTargetsSaved => '成员分配已保存。';

  @override
  String get workspaceMemberTargetsAssignAction => '分配';

  @override
  String get workspaceMemberTargetsAssigned => '已分配';

  @override
  String get workspaceMemberTargetsUnassigned => '未分配';

  @override
  String get workspaceMemberTargetsNeedsConfirmation => '需要确认';

  @override
  String get workspaceMemberTargetsPartiallyAssigned => '部分分配';

  @override
  String get mixedWorkspaceCreateSessionBlocked =>
      '请先在团队设置中确认机器分配，再在此混合工作区新建对话。';

  @override
  String get mixedWorkspaceSessionLaunchBlocked =>
      '该对话的机器分配已失效。请在团队设置中确认分配后新建对话。';

  @override
  String get sessionLaunchMissingWorkspace => '找不到该对话所属的工作区。';

  @override
  String get sessionLaunchMissingTeamMember => '团队成员不可用，请选择团队后重试。';

  @override
  String mixedWorkspaceMemberPlacementProgress(int placed, int total) {
    return '已分配 $placed / $total';
  }

  @override
  String mixedWorkspaceMemberPlacementOnMachine(int count) {
    return '本机 $count 个';
  }

  @override
  String get workspaceFolderTargetLabel => '所在机器';

  @override
  String get workspaceFolderPathLabel => '目录';

  @override
  String get workspaceFoldersChangeTarget => '更换';

  @override
  String get workspaceFoldersAddOnAnotherMachine => '在其他机器上添加';

  @override
  String get workspaceFoldersPickTarget => '选择机器';

  @override
  String get workspaceFoldersPickPath => '选择目录';

  @override
  String get workspaceFoldersApplyAllLocal => '全部设为本地';

  @override
  String get workspaceFoldersApplyAllRemote => '全部设为远程…';

  @override
  String get workspaceFoldersPickRemoteTarget => '选择远程机器';

  @override
  String get workspaceDeadTargetBadge => '机器不可用';

  @override
  String get workspaceDeadTargetRemap => '重新映射…';

  @override
  String get workspaceDeadTargetRemapTitle => '重新映射机器';

  @override
  String workspaceDeadTargetRemapBody(String from) {
    return '将 $from 替换为另一台机器。目录路径不会改动，目标机器上必须已有相同路径。';
  }

  @override
  String get workspaceDeadTargetRemapPickFrom => '失效机器';

  @override
  String get workspaceDeadTargetRemapPickTo => '替换为';

  @override
  String get workspaceDeadTargetRemapConfirm => '重新映射';

  @override
  String get workspaceDeadTargetRemapNothing => '没有可映射的目标。';

  @override
  String get workspaceDeadTargetRemapFailed => '无法重新映射机器。';

  @override
  String get workspaceDeadTargetRemapFromLaunch => '重新映射机器…';

  @override
  String get homeTargetTitle => '主设备';

  @override
  String get homeTargetSubtitle =>
      'TeamPilot 存放团队、工作区与配置的位置（控制面）。切换会使用独立的数据目录，不会自动迁移。';

  @override
  String get homeTargetSingleOptionHint => '当前平台只有这一个可用的主设备。';

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
  String get bootstrapLoadingApp => '正在启动 TeamPilot…';

  @override
  String get bootstrapLoadingWorkspaces => '正在加载工作区…';

  @override
  String get bootstrapLoadingLibraries => '正在加载资源库…';

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
  String get providerCredentialsAuthenticated => '已认证';

  @override
  String get providerCredentialsUnauthenticated => '未认证';

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
  String get cursorCredentialsLogin => 'Cursor 登录';

  @override
  String get cursorCredentialsImportGlobal => '从 ~/.cursor 导入';

  @override
  String get cursorCredentialsImportFile => '导入目录…';

  @override
  String get cursorCredentialsRevoke => '退出登录';

  @override
  String cursorCredentialsRevokeConfirm(String name) {
    return '退出登录并删除 $name 的已保存凭据？';
  }

  @override
  String get cursorCredentialsActionSuccess => '凭据已更新';

  @override
  String get cursorCredentialsActionFailed => '凭据更新失败';

  @override
  String get codexCredentialsLogin => 'OpenAI 登录';

  @override
  String get codexCredentialsImportGlobal => '从 ~/.codex 导入';

  @override
  String get codexCredentialsImportFile => '导入 auth.json…';

  @override
  String get codexCredentialsRevoke => '退出登录';

  @override
  String codexCredentialsRevokeConfirm(String name) {
    return '退出登录并删除 $name 的已保存凭据？';
  }

  @override
  String get codexCredentialsActionSuccess => '凭据已更新';

  @override
  String get codexCredentialsActionFailed => '凭据更新失败';

  @override
  String get opencodeCredentialsLogin => 'Provider 登录';

  @override
  String get opencodeCredentialsImportGlobal => '从 opencode 凭据导入';

  @override
  String get opencodeCredentialsImportFile => '导入 auth.json…';

  @override
  String get opencodeCredentialsRevoke => '退出登录';

  @override
  String opencodeCredentialsRevokeConfirm(String name) {
    return '退出登录并删除 $name 的已保存凭据？';
  }

  @override
  String get opencodeCredentialsActionSuccess => '凭据已更新';

  @override
  String get opencodeCredentialsActionFailed => '凭据更新失败';

  @override
  String get providerCredentialsFailureUnsupported => '不支持此凭据操作';

  @override
  String get providerCredentialsFailureServiceUnavailable => '凭据服务不可用';

  @override
  String get providerCredentialsFailureProviderNotFound => '未找到 Provider';

  @override
  String get providerCredentialsFailurePathRequired => '请先选择文件或目录';

  @override
  String providerCredentialsFailureSourceMissing(String path) {
    return '未找到凭据文件：$path';
  }

  @override
  String providerCredentialsFailureSourceUnreadable(String path) {
    return '无法读取凭据文件：$path';
  }

  @override
  String providerCredentialsFailureProviderEntryMissing(
    String providerId,
    String path,
  ) {
    return '在 $path 中未找到 \"$providerId\" 的凭据';
  }

  @override
  String providerCredentialsFailureProviderEntryMissingWithKeys(
    String providerId,
    String path,
    String keys,
  ) {
    return '在 $path 中未找到 \"$providerId\" 的凭据。已有：$keys';
  }

  @override
  String get providerCredentialsFailureInvalidCredential => '凭据格式无效或不完整';

  @override
  String get providerCredentialsFailureDestinationExists =>
      '凭据已存在。请先退出登录，或再次导入以覆盖。';

  @override
  String providerCredentialsFailureRequiredFileMissing(String path) {
    return '缺少必需文件：$path';
  }

  @override
  String providerCredentialsFailureLoginFailed(int exitCode) {
    return '登录失败（退出码 $exitCode）';
  }

  @override
  String providerCredentialsFailureLoginProcessError(String detail) {
    return '无法运行登录命令：$detail';
  }

  @override
  String get providerCredentialsFailureRevokeFailed => '无法退出登录或删除凭据';

  @override
  String get providerCredentialsFailureVerifyFailed => '凭据已写入但校验失败';

  @override
  String get providerCredentialsFailureStatusRefreshFailed => '凭据已更新但状态刷新失败';

  @override
  String get claudeLaunchCredentialsMissingWarning =>
      '该 Team 绑定的 Claude Official Provider 缺少凭据，请在 Providers 设置中登录。';

  @override
  String get teamConfigIncompleteTitle => '团队配置不完整';

  @override
  String teamConfigIncompleteBody(String team) {
    return '团队“$team”缺少启动所需的配置。会话仍会启动，但缺少这些配置时智能体可能无法正常工作：';
  }

  @override
  String get teamConfigIncompleteGoConfigure => '前往配置';

  @override
  String get teamConfigIncompleteDismiss => '稍后';

  @override
  String get teamConfigGroupTeamDefault => '团队默认';

  @override
  String get teamConfigAspectDefaultProvider => '默认服务商';

  @override
  String get teamConfigAspectProvider => '服务商';

  @override
  String get teamConfigAspectModel => '模型';

  @override
  String get teamConfigAspectCli => 'CLI';

  @override
  String get teamConfigAspectSeparator => '、';

  @override
  String teamConfigIssueSemanticLabel(String subject, String aspects) {
    return '$subject缺少：$aspects';
  }

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
  String get providerModelBackgroundTier => '用于后台/快速任务（Claude haiku 档）';

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
  String get skillsCardDetails => '详情';

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
  String get pluginsCardDetails => '详情';

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
  String get pluginsDiscoverySyncing => '正在后台检查 marketplace 更新并同步插件…';

  @override
  String pluginsUninstallConfirm(String name, int n) {
    return '确认卸载 $name？将影响 $n 个团队。';
  }

  @override
  String get pluginsUninstallImpactList => '受影响的团队：';

  @override
  String pluginCliSupportFully(String cli) {
    return '$cli：完全支持';
  }

  @override
  String pluginCliSupportPartial(String cli, String dropped) {
    return '$cli：部分支持（丢弃 $dropped）';
  }

  @override
  String pluginCliSupportNotApplicable(String cli) {
    return '$cli：不适用';
  }

  @override
  String get pluginComponentSkills => '技能';

  @override
  String get pluginComponentAgents => '代理';

  @override
  String get pluginComponentCommands => '命令';

  @override
  String get pluginComponentHooks => '钩子';

  @override
  String get pluginComponentMcp => 'MCP';

  @override
  String get pluginComponentRules => '规则';

  @override
  String get pluginComponentApps => '应用';

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
  String get teamSettingsSubtitle => '团队代理';

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
  String get teamExtensionsNav => '扩展';

  @override
  String get teamExtensionsTitle => '本团队的扩展';

  @override
  String get teamExtensionsSubtitle => '覆盖本团队启用哪些扩展，默认跟随全局设置。';

  @override
  String get teamExtensionFollowGlobal => '跟随全局';

  @override
  String get teamExtensionForceOn => '开启';

  @override
  String get teamExtensionForceOff => '关闭';

  @override
  String get teamExtensionEffectiveOn => '本团队已启用';

  @override
  String get teamExtensionEffectiveOff => '本团队未启用';

  @override
  String get teamMcpNav => 'MCP';

  @override
  String get myTeamsNav => '我的团队';

  @override
  String get myTeamsTitle => '我的团队';

  @override
  String get myTeamsSubtitle => '管理本地团队配置';

  @override
  String myTeamsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 名成员',
    );
    return '$_temp0';
  }

  @override
  String myTeamsCreatedAt(Object date) {
    return '创建于 $date';
  }

  @override
  String get myTeamsEmptyTitle => '还没有团队';

  @override
  String get myTeamsEmptyHint => '创建团队以管理成员、技能与插件。';

  @override
  String get myExpertsNav => '我的专家';

  @override
  String get myExpertsTitle => '我的专家';

  @override
  String get myExpertsSubtitle => '管理本地专家人设';

  @override
  String get myExpertsEmptyTitle => '还没有专家';

  @override
  String get myExpertsEmptyHint => '创建本地专家人设，以便在多个团队中复用。';

  @override
  String get myExpertsCreate => '新建专家';

  @override
  String get myExpertsEdit => '编辑';

  @override
  String get myExpertsDelete => '删除';

  @override
  String myExpertsDeleteConfirm(Object name) {
    return '删除专家「$name」？此操作无法撤销。';
  }

  @override
  String myExpertsDeleteReferenced(Object name) {
    return '无法删除「$name」——仍有团队花名册引用该专家。请先改派相关成员。';
  }

  @override
  String get myExpertsUpload => '上传';

  @override
  String get myTeamsUpload => '上传';

  @override
  String get githubSettingsTitle => 'GitHub';

  @override
  String get githubSettingsSubtitle => '连接 GitHub，以便将专家和团队发布到 Hub';

  @override
  String get downloadSourcesSettingsTitle => '下载源';

  @override
  String get downloadSourcesSettingsSubtitle =>
      '配置 GitHub 下载镜像（应用更新、Termux APK）';

  @override
  String get downloadSourcesMirrorBaseUrl => '镜像基础 URL';

  @override
  String get downloadSourcesMirrorHint => 'https://mirror.example';

  @override
  String get downloadSourcesSave => '保存';

  @override
  String get downloadSourcesRestoreDefaults => '恢复默认';

  @override
  String get downloadSourcesIdentity => '直连（官方）';

  @override
  String get downloadSourcesEnabledSources => '已启用源';

  @override
  String get githubSignIn => '使用 GitHub 登录';

  @override
  String githubConnectedAs(Object login) {
    return '已连接为 @$login';
  }

  @override
  String get githubConnectedGeneric => '已连接到 GitHub';

  @override
  String get githubDisconnect => '断开连接';

  @override
  String get githubSwitchAccount => '切换账号';

  @override
  String get githubWaitingCodeHint => '如有提示，请在 GitHub 上输入此验证码';

  @override
  String get githubBrowserOpened => '已打开浏览器进行授权';

  @override
  String get githubReopenBrowser => '重新打开浏览器';

  @override
  String get githubDeviceFlowUnavailable => '此构建暂不支持 GitHub 登录。请使用个人访问令牌。';

  @override
  String get githubAuthExpired => 'GitHub 登录已失效';

  @override
  String get githubAuthDenied => '已取消 GitHub 授权';

  @override
  String get githubAuthExpiredRetry => '授权已过期，请重试。';

  @override
  String get githubAdvancedPat => '使用个人访问令牌';

  @override
  String get githubAdvancedPatSubtitle => '无法使用 GitHub 登录时，或你更想用带 repo 权限的令牌时。';

  @override
  String get githubNetworkError => '无法连接 GitHub，请重试。';

  @override
  String get hubPublishExpertTitle => '发布专家到 Hub';

  @override
  String get hubPublishTeamTitle => '发布团队到 Hub';

  @override
  String get hubPublishAuthHint => '使用 GitHub 登录并授权，以向 Hub 仓库发起基于 fork 的拉取请求。';

  @override
  String get hubPublishTokenLabel => 'GitHub 令牌';

  @override
  String get hubPublishTokenHint => 'ghp_…';

  @override
  String get hubPublishTokenStored => '已保存令牌，可在下方替换。';

  @override
  String get hubPublishTokenRequired => '发布需要 GitHub 令牌';

  @override
  String get hubPublishTokenSaveFailed => '无法保存 GitHub 令牌';

  @override
  String get hubPublishNext => '下一步';

  @override
  String get hubPublishPublish => '发布';

  @override
  String get hubPublishDone => '完成';

  @override
  String get hubPublishSlugLabel => '标识（slug）';

  @override
  String get hubPublishSlugHint => 'url-safe-id';

  @override
  String get hubPublishSlugRequired => '标识为必填项';

  @override
  String get hubPublishCategoryRequired => '分类为必填项';

  @override
  String get hubPublishAuthorLabel => '作者';

  @override
  String get hubPublishLocalExpertHint => '花名册中的本地专家须先映射为已发布或内置专家，才能上传。';

  @override
  String get hubPublishLocalExpertBlocked => '请先映射所有本地专家后再继续';

  @override
  String get hubPublishRemapLabel => '发布为';

  @override
  String get hubPublishNonPortableHint => '以下依赖没有可移植来源。请先从团队配置中移除后再发布：';

  @override
  String get hubPublishNonPortableBlocked => '请先移除不可移植依赖后再继续';

  @override
  String get hubPublishGatesClear => '依赖均可移植，可继续确认。';

  @override
  String get hubPublishConfirmHint => '请核对包元数据，然后发布基于 fork 的拉取请求。';

  @override
  String get hubPublishKindLabel => '类型';

  @override
  String get hubPublishKindExpert => '专家';

  @override
  String get hubPublishKindTeam => '团队';

  @override
  String get hubPublishSuccessHint => '拉取请求已创建。可复制或打开下方链接。';

  @override
  String get hubPublishCopyLink => '复制链接';

  @override
  String get hubPublishOpenPr => '打开 PR';

  @override
  String get hubPublishBadgePrOpen => 'PR 已开';

  @override
  String get hubPublishBadgePublished => '已发布';

  @override
  String get expertHubCreate => '新建';

  @override
  String get expertEditorCreateTitle => '新建专家';

  @override
  String get expertEditorEditTitle => '编辑专家';

  @override
  String get expertEditorDescription => '描述';

  @override
  String get expertEditorCategory => '分类';

  @override
  String get expertEditorTags => '标签';

  @override
  String get expertEditorTagsHint => '逗号分隔';

  @override
  String get expertEditorNameRequired => '名称为必填项。';

  @override
  String get expertEditorPromptRequired => '职责为必填项。';

  @override
  String get expertEditorPromptHint => '描述该专家的职责与工作范围。';

  @override
  String get expertEditorPlaybookHint => '可选。该专家应遵循的工作步骤与规范。';

  @override
  String get expertEditorSkillsSection => '技能';

  @override
  String get expertEditorPluginsSection => '插件';

  @override
  String get expertEditorMcpSection => 'MCP';

  @override
  String get expertEditorDepsHint => '从本机已安装库中配置依赖。没有可移植来源的项会在保存时跳过。';

  @override
  String get expertEditorConfigureSkillsTitle => '配置技能';

  @override
  String get expertEditorConfigurePluginsTitle => '配置插件';

  @override
  String get expertEditorConfigureMcpTitle => '配置 MCP';

  @override
  String get expertEditorDepPickerDone => '完成';

  @override
  String expertEditorNonPortableSkipped(int count) {
    return '已跳过 $count 个没有可移植来源的本地项。';
  }

  @override
  String get expertEditorOrphanDeps => '已挂载（本机未安装）';

  @override
  String get expertEditorOrphanRemove => '移除';

  @override
  String get teamHubNav => '团队中心';

  @override
  String get teamHubSubtitle => '发现更多公开团队';

  @override
  String get teamHubTitle => '团队中心';

  @override
  String get teamHubDiscovery => '发现';

  @override
  String get teamHubFavorites => '我的收藏';

  @override
  String get teamHubSearchHint => '搜索公开团队';

  @override
  String get teamHubSortName => '名称';

  @override
  String get teamHubSortUpdated => '最近更新';

  @override
  String get teamHubCategoryAll => '全部';

  @override
  String get teamHubClone => '克隆为我的团队';

  @override
  String get teamHubCloning => '正在克隆…';

  @override
  String teamHubCloneSuccess(Object name) {
    return '已克隆「$name」。';
  }

  @override
  String teamHubCloneSuccessWithDeps(
    Object name,
    int skillCount,
    int pluginCount,
    int mcpCount,
    int expertCount,
  ) {
    return '已克隆「$name」。已安装 $skillCount 个 Skill、$pluginCount 个插件、$mcpCount 个 MCP 服务,并克隆了 $expertCount 个专家。';
  }

  @override
  String teamHubClonePartial(
    Object name,
    int skillCount,
    int pluginCount,
    int mcpCount,
    int expertCount,
    int failedCount,
    Object failedNames,
  ) {
    return '已克隆「$name」。已安装 $skillCount 个 Skill、$pluginCount 个插件、$mcpCount 个 MCP 服务,克隆了 $expertCount 个专家;$failedCount 个未能安装:$failedNames。';
  }

  @override
  String get teamHubCloneFailed => '无法克隆该团队。';

  @override
  String get teamHubEmptyTitle => '暂无公开团队';

  @override
  String get teamHubEmptyHint => '点击刷新从注册表拉取团队。';

  @override
  String get teamHubFavoritesEmptyTitle => '暂无收藏';

  @override
  String get teamHubFavoritesEmptyHint => '点击团队上的星标即可收藏到这里。';

  @override
  String get teamHubRefresh => '刷新';

  @override
  String get teamHubLoadError => '无法加载公开团队。';

  @override
  String get teamHubDepInstalled => '已安装';

  @override
  String get teamHubDepToInstall => '将安装';

  @override
  String get teamHubMembersLabel => '成员';

  @override
  String get teamHubSkillsLabel => '技能';

  @override
  String get teamHubPluginsLabel => '插件';

  @override
  String get teamHubMcpLabel => 'MCP';

  @override
  String get teamHubBrowseAll => '浏览全部团队';

  @override
  String get teamHubConfirmSelection => '确认';

  @override
  String get teamHubAlreadyAdded => '已添加';

  @override
  String get teamHubNotFound => '未找到该团队。';

  @override
  String get expertHubNav => '专家中心';

  @override
  String get expertHubTitle => '专家中心';

  @override
  String get expertHubSubtitle => '发现成员角色与模板';

  @override
  String get expertHubSearchHint => '搜索专家';

  @override
  String get expertHubFavorites => '收藏';

  @override
  String get expertHubMyTemplates => '我的模板';

  @override
  String get expertHubFromTeams => '来自团队';

  @override
  String get expertHubCategoryAll => '全部';

  @override
  String get expertHubSortName => '名称';

  @override
  String get expertHubSortUpdated => '最近更新';

  @override
  String get expertHubAddToTeam => '添加到团队';

  @override
  String get expertHubLaunchInWorkspace => '在工作区启动';

  @override
  String get expertHubAdding => '添加中…';

  @override
  String get expertHubAddFailed => '无法添加该成员。';

  @override
  String get expertHubEmptyTitle => '暂无专家';

  @override
  String get expertHubEmptyHint => '刷新以从注册表获取专家。';

  @override
  String get expertHubFavoritesEmptyTitle => '暂无收藏';

  @override
  String get expertHubFavoritesEmptyHint => '点击专家卡片上的星标即可收藏。';

  @override
  String get expertHubRefresh => '刷新';

  @override
  String get expertHubLoadError => '无法加载专家。';

  @override
  String get expertHubSourceBuiltin => '内置';

  @override
  String get expertHubSourceRegistry => '注册表';

  @override
  String get expertHubSourceLocal => '我的模板';

  @override
  String get expertHubSourceTeamExtract => '来自团队';

  @override
  String get expertHubSourceClone => '克隆';

  @override
  String get expertHubPrompt => '职责';

  @override
  String get expertHubPlaybook => '工作手册';

  @override
  String get expertHubCapabilities => '能力';

  @override
  String expertHubAddSuccess(Object name) {
    return '已将「$name」添加到团队。';
  }

  @override
  String expertHubAddSuccessWithSkills(Object name, int skillCount) {
    return '已添加「$name」。安装了 $skillCount 个技能。';
  }

  @override
  String expertHubAddPartial(
    Object name,
    int skillCount,
    int failedCount,
    Object failedNames,
  ) {
    return '已添加「$name」。安装了 $skillCount 个技能。$failedCount 个无法安装：$failedNames。';
  }

  @override
  String get expertHubNoneSelected => '未选择专家';

  @override
  String get expertHubBrowseAll => '浏览全部专家';

  @override
  String get expertHubConfirmSelection => '确认';

  @override
  String get expertHubRecent => '最近使用';

  @override
  String get expertHubIgnoredInTeamMode => '专家仅在简单模式下可用。请切换到简单模式以召唤专家。';

  @override
  String get expertHubNotFound => '未找到该专家。';

  @override
  String expertHubPreflightPartial(
    Object name,
    int failedCount,
    Object failedNames,
  ) {
    return '已选择「$name」。$failedCount 个能力无法安装：$failedNames。';
  }

  @override
  String get expertHubAddFromHub => '从专家中心添加';

  @override
  String get expertHubViewInHub => '在专家中心查看';

  @override
  String get expertHubViewOriginTeam => '查看来源团队';

  @override
  String teamMcpAssignedCount(int assigned, int total) {
    return '已启用 $assigned/$total';
  }

  @override
  String get teamMcpManage => '管理 MCP';

  @override
  String get mcpNavTitle => 'MCP 服务器';

  @override
  String get mcpSubtitle => '为 Agent 会话管理 MCP 服务器配置。';

  @override
  String get mcpNavInstalled => '已安装';

  @override
  String get mcpNavDiscovery => '发现';

  @override
  String get mcpNavRegistries => '注册中心';

  @override
  String get mcpInstalledSectionTitle => '已安装的 MCP';

  @override
  String mcpInstalledCount(int count) {
    return '已安装 $count';
  }

  @override
  String get mcpNoInstalled => '还没有安装 MCP 服务器';

  @override
  String get mcpNoInstalledHint => '打开发现页，从内置模板或注册中心添加。';

  @override
  String get mcpDiscoverySectionTitle => '发现 MCP 服务器';

  @override
  String get mcpDiscoverySectionHint => '浏览内置模板，以及「仓库」中配置的远程目录。';

  @override
  String get mcpDiscoverySourceAll => '全部';

  @override
  String get mcpDiscoverySourceBuiltin => '内置';

  @override
  String get mcpSmitheryApiTokenLabel => 'API Token';

  @override
  String get mcpSmitheryApiTokenHint => 'Smithery API 密钥（Bearer）';

  @override
  String get mcpSmitheryApiTokenSet => '已配置 Token';

  @override
  String get mcpRegistryEditTitle => '编辑 API 地址';

  @override
  String get mcpRegistryResetTitle => '恢复默认';

  @override
  String mcpRegistryResetConfirm(String name) {
    return '将「$name」恢复为默认 API 地址？';
  }

  @override
  String get mcpRepoApiUrlLabel => 'API 基础地址';

  @override
  String get mcpRepoTestConnection => '测试连接';

  @override
  String get mcpRepoResetDefault => '恢复默认';

  @override
  String get mcpRepoConfigSaved => '目录 API 设置已保存';

  @override
  String get mcpRepoTestOk => '连接成功';

  @override
  String mcpRepoTestFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get mcpRepoDisabledHint => '该目录源已禁用，请在「仓库」中启用。';

  @override
  String get mcpRegistrySmithery => 'Smithery';

  @override
  String get mcpRegistryOfficial => '官方注册表';

  @override
  String get mcpRegistrySmitheryHint => 'Smithery — https://api.smithery.ai';

  @override
  String get mcpRegistryOfficialHint =>
      '官方 MCP Registry — https://registry.modelcontextprotocol.io';

  @override
  String get mcpRegistrySearchHint => '搜索服务器（如 github）';

  @override
  String get mcpRegistryLoadMore => '加载更多';

  @override
  String get mcpCatalogAdd => '添加';

  @override
  String get mcpCatalogInstalled => '已安装';

  @override
  String get mcpCatalogAdded => '已加入 MCP 目录';

  @override
  String get mcpCatalogEmpty => '未找到服务器';

  @override
  String get mcpCatalogVerified => '已认证';

  @override
  String get mcpEmptyGoDiscovery => '浏览内置模板';

  @override
  String get mcpEmptyGoRegistries => '打开注册中心';

  @override
  String get mcpAdd => '添加 MCP';

  @override
  String get mcpEdit => '编辑 MCP';

  @override
  String get mcpOpenHomepage => '打开链接';

  @override
  String get mcpFormDetailHint => '选择服务器进行编辑，或添加新的 MCP 服务器。';

  @override
  String get mcpServerNotFound => '未找到该 MCP 服务器';

  @override
  String get mcpImport => '从本机导入';

  @override
  String get mcpImportEmpty => '在 ~/.claude.json 与 ~/.flashskyai.json 中未找到 MCP';

  @override
  String mcpImportSummary(int added, int conflicts) {
    return '新增 $added 个，冲突 $conflicts 个';
  }

  @override
  String get mcpImportOverwrite => '覆盖冲突项';

  @override
  String get mcpImportDone => 'MCP 目录已更新';

  @override
  String get mcpEmpty => '目录中暂无 MCP 服务器';

  @override
  String get mcpDeleteConfirm => '删除该 MCP 服务器？';

  @override
  String get mcpFieldName => '名称';

  @override
  String get mcpFieldCommand => '命令';

  @override
  String get mcpFieldArgs => '参数（空格分隔）';

  @override
  String get mcpAddTitle => '新增 MCP';

  @override
  String get mcpAddButton => '添加 MCP';

  @override
  String get mcpImportExisting => '导入已有';

  @override
  String mcpConfiguredCount(int count) {
    return '已配置 $count 个 MCP 服务器';
  }

  @override
  String mcpOAuthConnectTitle(String name) {
    return '连接 $name';
  }

  @override
  String get mcpOAuthConnectHint =>
      '在浏览器中完成 MCP 提供商登录。令牌按 Claude Code 格式写入应用配置目录（等同终端 /mcp → Authenticate）。';

  @override
  String get mcpOAuthDiscovering => '正在发现授权服务器…';

  @override
  String get mcpOAuthOpenBrowser => '打开浏览器';

  @override
  String get mcpOAuthCallbackUrlLabel => '回调地址';

  @override
  String get mcpOAuthCallbackUrlHint => '登录后粘贴完整 URL（含 ?code=）';

  @override
  String get mcpOAuthSubmitCallback => '提交地址';

  @override
  String get mcpOAuthStartConnect => '连接';

  @override
  String get mcpOAuthConnectAction => '连接';

  @override
  String get mcpOAuthConnectSuccess => 'MCP OAuth 已连接';

  @override
  String get mcpOAuthStatusConnected => 'OAuth 已连接';

  @override
  String get mcpOAuthStatusNeedsAuth => '需要 OAuth';

  @override
  String get mcpPresetDescFetch => '抓取网页并将 HTML 转为 Markdown，供模型使用。';

  @override
  String get mcpPresetDescTime => '时间查询：当前时间、时区转换、日期计算等。';

  @override
  String get mcpPresetDescMemory => '跨会话的持久化记忆图谱。';

  @override
  String get mcpPresetDescSequentialThinking => '结构化分步推理，适合复杂问题。';

  @override
  String get mcpPresetDescContext7 => '通过 Context7 获取最新库文档。';

  @override
  String get mcpFormIdLabel => 'MCP 标题（唯一）*';

  @override
  String get mcpFormDisplayNameLabel => '显示名称';

  @override
  String get mcpFormDisplayNameHint => '例如 @modelcontextprotocol/server-time';

  @override
  String get mcpFormMetadata => '附加信息';

  @override
  String get mcpFormDescriptionLabel => '描述';

  @override
  String get mcpFormDescriptionHint => '可选的描述信息';

  @override
  String get mcpFormTagsLabel => '标签（逗号分隔）';

  @override
  String get mcpFormTagsHint => 'stdio, time, utility';

  @override
  String get mcpFormHomepageLabel => '主页链接';

  @override
  String get mcpFormDocsLabel => '文档链接';

  @override
  String get mcpFormJsonLabel => '完整的 JSON 配置';

  @override
  String get mcpFormFormatJson => '格式化';

  @override
  String get mcpFormRequiredFields => '请填写 MCP 标题与显示名称。';

  @override
  String get mcpFormSubmitAdd => '添加';

  @override
  String get confirm => '确认';

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
  String get teamEffortLevel => '推理力度';

  @override
  String get teamEffortLevelSubtitle =>
      '团队默认力度（Claude effortLevel / Codex model_reasoning_effort）。';

  @override
  String get memberEffortLevel => '成员力度覆盖';

  @override
  String get memberEffortLevelSubtitle => '设置后覆盖团队默认值。';

  @override
  String get memberEffortInheritHint => '继承团队默认';

  @override
  String get providerEffortLevel => '推理力度';

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
  String get teamLeadBadge => 'Leader';

  @override
  String get teamLeadDelegateOnlyTitle => '队长仅规划分派';

  @override
  String get teamLeadDelegateOnlySubtitle => '开启后将禁止队长使用一些工具。';

  @override
  String get teamForceWaitBeforeStopTitle => '让成员保持在等待循环';

  @override
  String get teamForceWaitBeforeStopSubtitle =>
      '开启后,成员结束一个回合时会被推回 wait_for_message 而不是停止,从而持续待命接收新消息和任务。关闭则允许成员“休息”(正常停止)。';

  @override
  String get memberLaunchOrder => '成员启动顺序';

  @override
  String get saveMember => '保存成员';

  @override
  String get editTeamSubtitle => '编辑团队标识、工作目录和启动顺序。';

  @override
  String get memberName => '成员名称';

  @override
  String get memberNameSubtitle => '仅作界面展示用。若要指明职责与边界，请编辑下方的职责。';

  @override
  String get provider => '提供商';

  @override
  String get model => '模型';

  @override
  String get agent => 'Agent 预设';

  @override
  String get selectAgent => '选择预设';

  @override
  String get agentBuiltInNone => '默认';

  @override
  String get agentBuiltInCustom => '自定义…';

  @override
  String get agentBuiltInSubtitle => '指定该成员以哪种 Agent 身份协作，影响其行为与可用能力。';

  @override
  String get agentFlashskyaiPresetSubtitle =>
      '对应 flashskyai 的 --agent 参数，可选内置或自定义子 Agent。';

  @override
  String get agentClaudeTypeSubtitle =>
      '写入 Claude 团队 roster 的 agentType；留空则使用成员 ID。';

  @override
  String get agentClaudeTypeHint => '例如 Explore、Plan 或自定义类型';

  @override
  String get agentCustomIdHint => '自定义 Agent 标识';

  @override
  String get memberExtraArgs => '成员额外 CLI 参数';

  @override
  String get memberExtraArgsSubtitle => '仅附加在该成员的 CLI 启动参数。';

  @override
  String get workspaceAdvancedSettings => '高级配置';

  @override
  String get workspaceAdvancedSettingsSubtitle => 'Agent 预设与本成员的额外 CLI 参数。';

  @override
  String get memberDangerouslySkipPermissions => '跳过所有权限检查';

  @override
  String get memberDangerouslySkipPermissionsHint => '仅限隔离或无网络沙箱使用，否则风险极高。';

  @override
  String get prompt => '提示词';

  @override
  String get memberResponsibilities => '职责';

  @override
  String get memberPromptSubtitle => '该成员负责什么、不应做什么。会写入 Agent 的角色说明。';

  @override
  String get memberPromptPresetsLabel => '预设';

  @override
  String get memberPromptPresetTeamLead => '队长';

  @override
  String get memberPromptPresetTeamLeadText =>
      '协调全队：将用户需求拆成任务清单（每条写明范围与验收标准），再分配给各队友实现；除阻塞性问题外，不要亲自做大块开发，可先阅读代码与文档了解现状。\n在本会话窗口与用户直接沟通。指派与跟进时只联系其他队友（按成员名称），不要把任务派给自己。汇总队友结果后回复用户，写清结论、涉及文件与后续步骤。';

  @override
  String get memberPromptPresetDeveloper => '开发';

  @override
  String get memberPromptPresetDeveloperText =>
      '在约定范围内实现分配的任务。未经要求，不要扩大范围或顺手重构无关代码。';

  @override
  String get memberPromptPresetReviewer => '审查';

  @override
  String get memberPromptPresetReviewerText => '只做代码审查。除非被明确要求，否则不要改动文件。';

  @override
  String get memberPromptPresetResearcher => '调研';

  @override
  String get memberPromptPresetResearcherText => '只调研并汇报。除非被要求，否则不要改动生产代码。';

  @override
  String get memberPlaybook => '工作手册';

  @override
  String get memberPlaybookSubtitle => '接到任务后怎么执行：步骤、检查点、汇报格式。会作为 Agent 的操作指令。';

  @override
  String get memberPersonaEmptyNoExpert => '选择专家后可查看人设内容。';

  @override
  String get memberResponsibilitiesEmpty => '该专家未填写职责';

  @override
  String get memberPlaybookEmpty => '该专家未填写工作手册';

  @override
  String get memberPlaybookPresetDeveloperText =>
      '测试先行：实现前先写一个会失败的测试，再用最小 diff 让它通过。每次改动后跑相关测试，并说明改了哪些文件及原因。不要把无关改动混在一起；到约定检查点要停下。若团队装有 test-driven-development skill，就遵循它。';

  @override
  String get memberPlaybookPresetReviewerText =>
      '按序审查：①确认测试覆盖了改动；②正确性与边界情况；③可维护性及与周边代码的一致性。每条意见都要写明文件路径、行号、问题与具体改法——不要空泛夸奖，也不要只挑刺却不给改法。缺测试要显式指出。';

  @override
  String get memberPlaybookPresetResearcherText =>
      '动手前先厘清意图：复述问题与你的假设，然后在代码库里先广度排查再深入。汇报时给出文件路径、相关符号与建议的下一步——只提建议，不改生产代码。若团队装有 brainstorming skill，先用它框定问题。';

  @override
  String get selectModel => '选择一个模型';

  @override
  String get appProviderModelEnterCustom => '输入自定义模型 ID';

  @override
  String get appProviderModelPickFromList => '从列表选择';

  @override
  String get memberOfficialClaudeModelHint =>
      '使用 Claude 账号默认模型；请在 Providers 设置中管理 Official 登录。';

  @override
  String get editMemberSubtitle => '编辑提供商、模型、可选 Agent 预设与命令参数。';

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
  String get appProviderToolOpencode => 'OpenCode';

  @override
  String get appProviderToolCursor => 'Cursor';

  @override
  String get appProviderTeamToolSection => '团队默认服务商';

  @override
  String get appProviderTeamToolSubtitle => '选择本团队启动时，各工具使用的统一服务商。';

  @override
  String get appProviderTeamNone => '无';

  @override
  String get appProviderClaudeAuthField => '认证字段';

  @override
  String get appProviderClaudeAuthFieldHint => '选择写入 settings 的认证环境变量。';

  @override
  String get appProviderClaudeCredentialBinding => 'OAuth 凭证来源';

  @override
  String get appProviderClaudeCredentialBindingLinked => '跟随全局（~/.claude）';

  @override
  String get appProviderClaudeCredentialBindingIsolated => '隔离副本（仅 TeamPilot）';

  @override
  String get appProviderClaudeCredentialBindingLinkedHint =>
      '与终端里 Claude Code 共用同一份 OAuth 会话，刷新会自动保持同步。';

  @override
  String get appProviderClaudeCredentialBindingIsolatedHint =>
      '在 TeamPilot 目录保存独立凭证副本；适用于不能与全局 Claude Code 共用登录的场景。';

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
  String get aboutGitHub => 'GitHub';

  @override
  String get aboutCurrentVersion => '当前版本';

  @override
  String get aboutVersionLoading => '加载中…';

  @override
  String get appUpdateCheck => '检查更新';

  @override
  String get appUpdateAutoCheck => '自动检查更新';

  @override
  String get appUpdateAutoCheckHint => '每次启动时自动从 GitHub 检查新版本。';

  @override
  String get appUpdateSkipVersion => '跳过此版本';

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
  String get appUpdateViewReleases => '查看发布';

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
  String get onboardingStepCli => 'CLI 工具';

  @override
  String get onboardingStepProviderImport => '导入 Provider';

  @override
  String get onboardingStepDefaultPreset => '默认预设';

  @override
  String get onboardingAppearanceTitle => '选择语言与外观';

  @override
  String get onboardingAppearanceSubtitle => '可随时在「设置 → 布局」中修改。';

  @override
  String get onboardingSshTitle => '配置 SSH 连接';

  @override
  String get onboardingSshSubtitle => 'Android 通过 SSH 在远程主机运行 AI CLI。';

  @override
  String get onboardingWorkHomeTitle => '选择工作环境';

  @override
  String get onboardingWorkHomeSubtitle => '先连接本机 Termux 或远程 SSH，再检测 AI CLI。';

  @override
  String get onboardingCliTitle => '检测 CLI 工具';

  @override
  String get onboardingCliSubtitle => '定位用于启动会话的可执行文件。可安装缺失项，或稍后在设置中指定路径。';

  @override
  String get onboardingCliFound => '已找到 CLI';

  @override
  String get onboardingCliNotFound => '未在 PATH 中';

  @override
  String get onboardingCliScanning => '正在扫描 PATH 中的 CLI…';

  @override
  String get onboardingCliRedetect => '重新检测';

  @override
  String get onboardingProviderImportTitle => '导入 CLI Provider';

  @override
  String get onboardingProviderImportSubtitle => '扫描本机各 CLI 配置中的现有 Provider。';

  @override
  String get onboardingProviderImportResults => '导入结果';

  @override
  String get onboardingProviderImportEmpty => '未检测到 Provider，可稍后在设置中配置。';

  @override
  String get onboardingProviderImportFailed => '导入失败';

  @override
  String get onboardingProviderImportRescan => '重新扫描';

  @override
  String get onboardingDefaultPresetTitle => '配置默认启动预设';

  @override
  String get onboardingDefaultPresetSubtitle => '个人工作区与团队默认启动配置将共用此 CLI 预设。';

  @override
  String get onboardingDefaultPresetEmpty => '暂无可选 Provider，可跳过或在设置中添加。';

  @override
  String get onboardingDefaultPresetSelectExisting => '使用已有预设';

  @override
  String get onboardingDefaultPresetDefaultName => '默认';

  @override
  String get onboardingDefaultPresetModelHint => '该预设的主模型';

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

  @override
  String get diffIgnoreWhitespace => '忽略空白';

  @override
  String get diffPreviousChange => '上一处更改';

  @override
  String get diffNextChange => '下一处更改';

  @override
  String get diffViewSideBySide => '并排';

  @override
  String get diffViewUnified => '统一';

  @override
  String get diffOpenSourceFile => '打开源文件';

  @override
  String get diffShowAllLines => '显示全部';

  @override
  String get diffNoChanges => '没有更改';

  @override
  String get fileDiffToggleFile => '文件';

  @override
  String get fileDiffToggleDiff => 'Diff';

  @override
  String diffChangeCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get diffApplyHunkTooltip => '应用到工作区';

  @override
  String get diffDiscardEditsApplyTitle => '丢弃编辑？';

  @override
  String get diffDiscardEditsApplyBody => '应用此更改将丢弃 diff 中未保存的编辑。';

  @override
  String diffApplyFailed(String error) {
    return '无法应用更改：$error';
  }

  @override
  String diffSaveFailed(String error) {
    return '无法保存：$error';
  }

  @override
  String get diffReloadAfterSaveFailed => '已保存，但刷新 diff 失败。';

  @override
  String get diffFileReloadedAfterDiffWrite => '已从磁盘重新加载文件页。';

  @override
  String get diffDiscardDiffBeforeFileSaveTitle => '丢弃 diff 编辑？';

  @override
  String get diffDiscardDiffBeforeFileSaveBody => '保存文件将丢弃 diff 视图中未保存的编辑。';

  @override
  String get diffApplyDisabledNoPath => '无法应用：文件路径不可用';

  @override
  String get aiFeatures => 'AI 功能';

  @override
  String get aiFeaturesPageSubtitle =>
      '为每个 AI 功能选择使用的 CLI provider、模型与 effort。';

  @override
  String get aiFeatureCommitMessageTitle => '提交信息生成';

  @override
  String get aiFeatureCommitMessageSubtitle => '由源代码管理面板里的 ✨ 按钮使用。';

  @override
  String get aiFeatureTeamGenerateTitle => '团队配置生成';

  @override
  String get aiFeatureTeamGenerateSubtitle => '从描述生成团队时使用。';

  @override
  String get aiFeatureCliLabel => 'CLI';

  @override
  String get aiFeatureModelLabel => '模型';

  @override
  String get aiFeatureEffortLabel => 'Effort';

  @override
  String aiFeatureConfigSummary(String cli, String provider, String model) {
    return '$cli · $provider · $model';
  }

  @override
  String get gitGenerateCommitMessage => '用 AI 生成提交信息';

  @override
  String get gitGenerateCommitMessageNoProvider =>
      '请先在 设置 → AI 功能 中配置 AI provider。';

  @override
  String get teamGenTitle => '用 AI 生成';

  @override
  String get teamGenDescriptionHint => '描述你想要的团队（例如：做 Flutter 前端、需要代码审查和测试）';

  @override
  String get teamGenButton => '生成';

  @override
  String get teamGenNoProvider => '请先在 设置 → AI 功能 中配置 AI provider。';

  @override
  String get teamGenFailed => '无法生成团队，请手动编辑。';

  @override
  String get teamGenApplied => '草稿已应用，创建前请检查调整。';

  @override
  String get notificationCenterTitle => '通知';

  @override
  String get notificationOngoingSection => '进行中';

  @override
  String progressActivitiesMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个活动进行中',
    );
    return '$_temp0';
  }

  @override
  String get progressActivitiesPanelTitle => '进行中的活动';

  @override
  String get notificationHistorySection => '历史';

  @override
  String get notificationEmpty => '暂无通知';

  @override
  String get notificationMarkAllRead => '全部标为已读';

  @override
  String get notificationClearAll => '清空';

  @override
  String get notificationMarkRead => '标为已读';

  @override
  String get notificationDelete => '删除';

  @override
  String get notificationTimeJustNow => '刚刚';

  @override
  String notificationTimeMinutesAgo(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String notificationTimeHoursAgo(int hours) {
    return '$hours 小时';
  }

  @override
  String notificationTimeDaysAgo(int days) {
    return '$days 天';
  }

  @override
  String get memberDetailTitle => '成员详情';

  @override
  String get memberDetailViewAction => '查看成员详情';

  @override
  String get memberDetailOpenConfigDir => '打开配置目录';

  @override
  String get memberDetailOpenInFileManager => '在文件管理器中打开';

  @override
  String get memberDetailBrowseConfigDirTitle => '配置目录';

  @override
  String get memberDetailNeedsSession => '请先打开一个会话';

  @override
  String get memberDetailTabOverview => '概览';

  @override
  String get memberDetailTabSkills => 'Skills';

  @override
  String get memberDetailTabMcp => 'MCP';

  @override
  String get memberDetailTabPlugins => '插件';

  @override
  String get memberDetailTabSettings => '设置';

  @override
  String get memberDetailSourceRuntime => '运行会话配置';

  @override
  String get memberDetailSourceTeam => '团队层配置（该成员未在此会话中启动）';

  @override
  String get memberDetailEmpty => '该成员尚未在此会话中启动，且团队层无配置。';

  @override
  String get memberDetailLoadError => '读取该成员的配置目录失败。';

  @override
  String get memberDetailOpenConfigDirFailed => '无法在文件管理器中打开配置目录。';

  @override
  String memberDetailOpenConfigDirFailedOnHost(String host) {
    return '无法在 $host 上打开配置目录，远程主机可能没有桌面文件管理器。';
  }

  @override
  String get memberDetailSectionEmpty => '无';

  @override
  String get cliConfigAiCliGroup => 'AI CLI';

  @override
  String get cliConfigToolchainGroup => '工具链';

  @override
  String get toolchainGitLabel => 'Git 可执行文件路径';

  @override
  String get toolchainNodeLabel => 'Node.js / npm 路径';

  @override
  String toolchainPathDescription(String tool) {
    return '$tool 可执行文件的绝对路径。留空则使用 PATH 中的版本。';
  }

  @override
  String toolchainPathDescriptionSsh(String tool) {
    return '远程 SSH 主机上 $tool 的绝对路径。留空则自动发现。';
  }

  @override
  String get cliCursorExecutablePathLabel => 'Cursor CLI 路径';

  @override
  String toolchainInstallProgressChecking(String tool) {
    return '正在检查 $tool...';
  }

  @override
  String get toolchainGit => 'Git';

  @override
  String get toolchainNode => 'Node.js';

  @override
  String get homeWorkspaceLaunchWorkspaceTitle => '选择启动方式';

  @override
  String get homeWorkspaceSimpleMode => '简单模式';

  @override
  String get homeWorkspaceRememberLaunchChoice => '记住选择';

  @override
  String get worktreeCreateTitle => '新建 worktree';

  @override
  String get worktreeBranchLabel => '分支名';

  @override
  String get worktreeModeNewBranch => '新建分支';

  @override
  String get worktreeModeExistingBranch => '已有分支';

  @override
  String get worktreeBaseRefLabel => '基线（可选）';

  @override
  String get worktreeBaseRefHint => '默认当前 HEAD';

  @override
  String get worktreePathLabel => '位置';

  @override
  String get worktreeStartConversation => '创建后在此开始一个会话';

  @override
  String get worktreeCreateAction => '创建';

  @override
  String worktreeCreateFailed(Object error) {
    return '创建 worktree 失败：$error';
  }

  @override
  String get worktreeDeleteTitle => '删除 worktree';

  @override
  String worktreeDeleteBody(Object branch) {
    return '删除 $branch 的 worktree？';
  }

  @override
  String get worktreeDeleteForce => '即使有未提交改动也强制删除';

  @override
  String get worktreeDeleteBranchToo => '同时删除分支';

  @override
  String worktreeDeleteSessionsToo(Object count) {
    return '同时删除该 worktree 下的 $count 个会话';
  }

  @override
  String get worktreeDeleteAction => '删除';

  @override
  String worktreeDeleteFailed(Object error) {
    return '删除 worktree 失败：$error';
  }

  @override
  String get worktreeOrphanGroup => '其他';

  @override
  String get worktreeNewWorktreeTooltip => '新建 worktree';

  @override
  String get worktreeRefreshTooltip => '刷新 worktree 列表';

  @override
  String get worktreeNewConversationHere => '在此新建会话';

  @override
  String get worktreeMenuCopyPath => '复制路径';

  @override
  String get worktreeMenuRemove => '删除 worktree';

  @override
  String worktreeShowMore(Object count) {
    return '显示更多 $count 个';
  }

  @override
  String get worktreeMore => '更多';

  @override
  String get worktreeShowLess => '收起';

  @override
  String get worktreeDeleteBusyWarning => '请先停止该 worktree 下正在运行的会话，再删除。';

  @override
  String get automationsTitle => '全部自动化';

  @override
  String get automationsSubtitle => '跨项目与会话定时发送消息或启动 prompt。';

  @override
  String get automationsNew => '新建自动化';

  @override
  String get automationsScheduleHourly => '每小时';

  @override
  String get automationsScheduleDaily => '每天';

  @override
  String get automationsScheduleWeekdays => '工作日';

  @override
  String get automationsScheduleWeekly => '每周';

  @override
  String get automationsScheduleCustom => '自定义 cron';

  @override
  String get automationsSchedule => '调度';

  @override
  String get automationsSessionContextMenu => '定时消息…';

  @override
  String get automationsManageSessionContextMenu => '管理定时消息';

  @override
  String automationsNextRun(String time) {
    return '下次运行：$time';
  }

  @override
  String get automationsNextRunNone => '暂无计划运行';

  @override
  String get automationsRunNow => '立即运行';

  @override
  String get automationsRunHistory => '运行历史';

  @override
  String get automationsRunHistoryEmpty => '暂无运行记录';

  @override
  String get automationsSkippedUnavailable => '已跳过 — 会话不可用';

  @override
  String get automationsDispatchFailed => '分发失败';

  @override
  String get automationsEdit => '编辑';

  @override
  String get automationsDelete => '删除';

  @override
  String get automationsDeleteConfirm => '删除此自动化？';

  @override
  String get automationsEmpty => '暂无自动化';

  @override
  String get automationsName => '名称';

  @override
  String get automationsMessage => '消息';

  @override
  String get automationsEnabled => '已启用';

  @override
  String get automationsCli => 'CLI';

  @override
  String get automationsReuseSession => '复用会话';

  @override
  String get automationsReuseSessionSubtitleOff => '每次运行都会新建一个对话。';

  @override
  String get automationsReuseSessionSubtitlePending => '首次运行会创建对话，之后在同一会话中继续。';

  @override
  String automationsReuseSessionSubtitleBound(String sessionId) {
    return '已绑定会话 $sessionId';
  }

  @override
  String automationsReuseSessionListHint(String sessionId) {
    return '复用对话 $sessionId';
  }

  @override
  String get automationsTargetMember => '目标成员';

  @override
  String get automationsCustomCron => 'Cron 表达式';

  @override
  String get automationsInvalidCron => '无效的 cron 表达式（需要 5 个字段）';

  @override
  String get automationsInvalidTime => '时间格式须为 HH:mm';

  @override
  String get automationsValidationRequired => '名称和消息为必填项';

  @override
  String get automationsTime => '时间';

  @override
  String get automationsCreateTitle => '新建自动化';

  @override
  String get automationsEditTitle => '编辑自动化';

  @override
  String get automationsCompactTitle => '定时消息';

  @override
  String automationsHeaderCount(int count) {
    return '自动化 · $count';
  }

  @override
  String get automationsSidebarTitle => '自动化';

  @override
  String automationsSidebarWithNextRun(String time) {
    return '自动化 · $time';
  }

  @override
  String get automationsFilterAll => '全部';

  @override
  String get automationsFilterEnabled => '仅已启用';

  @override
  String get automationsFilterDisabled => '仅已禁用';

  @override
  String get automationsFilterStatusLabel => '状态';

  @override
  String get automationsFilterActionLabel => '类型';

  @override
  String get automationsFilterActionAll => '全部类型';

  @override
  String get automationsFilterScheduledMessage => '定时消息';

  @override
  String get automationsFilterLaunchPrompt => '启动 prompt';

  @override
  String get automationsSort => '排序自动化';

  @override
  String get automationsSortNameAsc => '名称 (A–Z)';

  @override
  String get automationsSortNameDesc => '名称 (Z–A)';

  @override
  String get automationsSortNextRun => '下次运行';

  @override
  String get automationsSortRecentlyUpdated => '最近更新';

  @override
  String get automationsShowFilter => '显示筛选';

  @override
  String get automationsHideFilter => '隐藏筛选';

  @override
  String automationsScheduleSummaryHourly(int minute) {
    return '每小时 :$minute';
  }

  @override
  String automationsScheduleSummaryDaily(String time) {
    return '每天 $time';
  }

  @override
  String automationsScheduleSummaryWeekdays(String time) {
    return '工作日 $time';
  }

  @override
  String automationsScheduleSummaryWeekly(String day, String time) {
    return '每周$day $time';
  }

  @override
  String get automationsDayMonday => '周一';

  @override
  String get automationsDayTuesday => '周二';

  @override
  String get automationsDayWednesday => '周三';

  @override
  String get automationsDayThursday => '周四';

  @override
  String get automationsDayFriday => '周五';

  @override
  String get automationsDaySaturday => '周六';

  @override
  String get automationsDaySunday => '周日';

  @override
  String automationsSessionDefaultName(String title) {
    return '$title — 定时消息';
  }

  @override
  String get automationsRunStatusCompleted => '已完成';

  @override
  String get automationsRunStatusPending => '等待中';

  @override
  String get automationsRunStatusDispatching => '分发中';

  @override
  String get automationsRunStatusDispatched => '已分发';

  @override
  String get automationsRunStatusSkippedMissed => '已跳过 — 错过窗口';

  @override
  String get automationsMaxRunCount => '运行次数上限';

  @override
  String get automationsMaxRunCountHint => '留空表示无限制';

  @override
  String get automationsInvalidMaxRunCount => '运行次数上限须为正整数';

  @override
  String automationsRunCountUnlimited(int count) {
    return '已运行 $count 次';
  }

  @override
  String automationsRunCountLimited(int count, int max) {
    return '已运行 $count / $max';
  }

  @override
  String automationsScopeModePersonal(String profile) {
    return '个人 · $profile';
  }

  @override
  String automationsScopeModeTeam(String team) {
    return '团队 · $team';
  }

  @override
  String automationsScopePersonal(String preset) {
    return '个人 · $preset';
  }

  @override
  String automationsScopeTeam(String team, String member) {
    return '团队 · $team · $member';
  }

  @override
  String automationsScopeTeamMember(String member) {
    return '团队 · $member';
  }

  @override
  String automationsScopeScheduledMessage(String sessionId) {
    return '定时消息 · $sessionId';
  }

  @override
  String get automationsLaunchMode => '对话模式';

  @override
  String get automationsLaunchProject => '项目';

  @override
  String get automationsLaunchWorktree => 'Worktree';

  @override
  String get automationsPermissions => '权限';

  @override
  String get automationsLaunchProfile => '启动身份';

  @override
  String get shortcutsWorkspaceNextTab => '下一个工作区标签';

  @override
  String get shortcutsWorkspacePrevTab => '上一个工作区标签';

  @override
  String get shortcutsWorkspaceCloseTab => '关闭工作区标签';

  @override
  String get shortcutsWorkspaceReopenClosed => '重新打开已关闭的工作区标签';

  @override
  String get shortcutsWorkspaceSearch => '搜索工作区（双击 Shift）';

  @override
  String get shortcutsStripNextTab => '下一个标签';

  @override
  String get shortcutsStripPrevTab => '上一个标签';

  @override
  String get shortcutsSessionNewTab => '新建会话标签';

  @override
  String get shortcutsSessionNewChat => '新建对话';

  @override
  String get shortcutsSessionCloseTab => '关闭会话标签';

  @override
  String shortcutsStripFocusTab(int n) {
    return '切换到第 $n 个标签';
  }

  @override
  String get shortcutsToggleSidebar => '切换侧边栏';

  @override
  String get shortcutsTogglePanel => '切换终端面板';

  @override
  String get shortcutsToggleSecondarySidebar => '切换次侧边栏';

  @override
  String get shortcutsFloatingToggle => '切换浮动工作区';

  @override
  String get shortcutsFloatingMaximize => '最大化浮动工作区';

  @override
  String get shortcutsFloatingMinimize => '最小化浮动工作区';

  @override
  String get shortcutsFloatingNewTerminal => '新建浮动终端';

  @override
  String get shortcutsFloatingOpenFile => '在浮动工作区打开文件';

  @override
  String get shortcutsZoomIn => '放大';

  @override
  String get shortcutsZoomOut => '缩小';

  @override
  String get shortcutsZoomReset => '重置缩放';

  @override
  String get shortcutsComposeSubmit => '发送消息';

  @override
  String get shortcutsComposeNewline => '插入换行';

  @override
  String get shortcutsShowCheatsheet => '显示键盘快捷键';

  @override
  String get shortcutsCategoryNavigation => '导航';

  @override
  String get shortcutsCategoryTabs => '标签';

  @override
  String get shortcutsCategoryView => '视图';

  @override
  String get shortcutsCategoryZoom => '缩放';

  @override
  String get shortcutsCategoryCompose => '输入框';

  @override
  String get shortcutsCategoryMeta => '通用';

  @override
  String get shortcutsSettingsTitle => '键盘快捷键';

  @override
  String get shortcutsPageSubtitle => '查看并自定义导航、标签、缩放和输入框的键盘快捷键。';

  @override
  String get shortcutsSearchHint => '搜索快捷键';

  @override
  String get shortcutsChangeAction => '更改…';

  @override
  String get shortcutsResetAction => '恢复默认';

  @override
  String get shortcutsUnbindAction => '取消绑定';

  @override
  String get shortcutsNotSet => '未设置';

  @override
  String get shortcutsResetAll => '全部重置';

  @override
  String get shortcutsResetAllConfirmTitle => '重置所有快捷键？';

  @override
  String get shortcutsResetAllConfirmMessage => '这会将所有键盘快捷键恢复为默认绑定。';

  @override
  String get shortcutsExport => '导出…';

  @override
  String get shortcutsImport => '导入…';

  @override
  String get shortcutsExportSuccess => '快捷键已导出。';

  @override
  String get shortcutsExportFailed => '无法导出快捷键。';

  @override
  String get shortcutsImportSuccess => '快捷键已导入。';

  @override
  String get shortcutsImportInvalidFile => '该文件不是有效的快捷键导出文件。';

  @override
  String get shortcutsImportConflictTitle => '替换冲突的快捷键？';

  @override
  String shortcutsImportConflictMessage(int count) {
    return '导入的快捷键与 $count 个现有绑定冲突。是否替换？';
  }

  @override
  String get shortcutsCheatsheetButton => '查看速查表';

  @override
  String get shortcutsCheatsheetTitle => '键盘快捷键';

  @override
  String get shortcutsCheatsheetEmpty => '没有匹配的快捷键。';

  @override
  String get shortcutsPressShortcutTitle => '按下快捷键';

  @override
  String get shortcutsPressShortcutHint =>
      '按下组合键进行绑定。按 Escape 取消，按 Backspace 取消绑定。';

  @override
  String get shortcutsPressShortcutUnsupportedKey => '该键无法绑定。';

  @override
  String shortcutsConflictMessage(String title) {
    return '已被“$title”使用。';
  }

  @override
  String get shortcutsReplaceAction => '替换';

  @override
  String get shortcutsConflictBadgeTooltip => '与另一个快捷键冲突';

  @override
  String get runAction => '运行';

  @override
  String get runStop => '停止';

  @override
  String get runRestart => '重新运行';

  @override
  String get runNewInstance => '新实例';

  @override
  String get runDebug => '调试';

  @override
  String get runDebugUnavailable => '调试功能尚未提供';

  @override
  String get runBuild => '构建';

  @override
  String get runBuildUnavailable => '构建功能尚未提供';

  @override
  String get runMoreActions => '更多运行操作';

  @override
  String get runSelectConfiguration => '启动';

  @override
  String get runEditorSelectConfiguration => '选择配置';

  @override
  String runCompoundConfiguration(String name) {
    return '$name（组合）';
  }

  @override
  String runSuggestedConfiguration(String name) {
    return '$name（建议）';
  }

  @override
  String get runAcceptRecommendation => '将建议配置添加到 launch.json';

  @override
  String get runRefreshDiscover => '刷新发现建议';

  @override
  String get runConfigurationTooltip => '运行配置';

  @override
  String get runOpenLaunchJson => '打开 launch.json';

  @override
  String get runAlreadyRunningTitle => '配置已在运行';

  @override
  String get runAlreadyRunningMessage => '重新运行当前会话，还是再启动一个新实例？';

  @override
  String get runStopSessionTitle => '停止正在运行的会话？';

  @override
  String runStopSessionMessage(String name) {
    return '“$name”仍在运行。停止并关闭此标签页？';
  }

  @override
  String get runStopAndClose => '停止并关闭';

  @override
  String get runNoSessions => '暂无运行会话';

  @override
  String get runClearExited => '清除已退出的会话';

  @override
  String get runLoadingOutput => '正在加载运行输出…';

  @override
  String get runEmptyOutputHint => '运行配置后，输出将显示在这里';

  @override
  String runTypeUnknown(String type) {
    return '未知启动类型：$type';
  }

  @override
  String runTypeUnavailable(String type) {
    return '启动类型“$type”在此目标上不可用';
  }

  @override
  String runTypeUnavailableRemote(String type) {
    return '启动类型“$type”在远程目标上不可用';
  }

  @override
  String get runErrorNoConfiguration => '未选择配置';

  @override
  String get runErrorNoFolder => '没有工作区文件夹';

  @override
  String get runErrorSshProfileMissing => '找不到此运行目标的 SSH 配置';

  @override
  String get runErrorSshSpawnerMissing => '未配置 SSH 进程执行';

  @override
  String get runConfigureLaunchItems => '配置启动项';

  @override
  String get runConfigurationsEmpty => '暂无启动配置';

  @override
  String get runEditConfigurations => '编辑配置';

  @override
  String get runAddConfiguration => '添加配置';

  @override
  String get runDeleteConfiguration => '删除';

  @override
  String runDeleteConfigurationConfirm(String name) {
    return '删除配置“$name”？';
  }

  @override
  String get runStopAndDelete => '停止并删除';

  @override
  String get runApply => '应用';

  @override
  String get runDiscard => '放弃';

  @override
  String get runDiscardChangesTitle => '放弃更改？';

  @override
  String get runDiscardChangesMessage => '此配置有未保存的更改。应用、放弃，还是取消？';

  @override
  String get runSelectFolder => '选择文件夹';

  @override
  String get runConfigurationName => '名称';

  @override
  String get runConfigurationType => '类型';

  @override
  String get runTypeShellScript => 'Shell 脚本';

  @override
  String get runPickLaunchType => '选择启动类型';

  @override
  String get runFieldCommand => '命令';

  @override
  String get runFieldArgs => '参数';

  @override
  String get runFieldEnv => '环境变量';

  @override
  String get runFieldCwd => '工作目录';

  @override
  String get runFieldShell => '在 Shell 中运行';

  @override
  String get runFieldScriptPath => '脚本路径';

  @override
  String get runFieldScriptText => '脚本内容';

  @override
  String get runFieldExecute => '执行方式';

  @override
  String get runFieldScriptOptions => '脚本选项';

  @override
  String get runFieldInterpreterPath => '解释器路径';

  @override
  String get runFieldInterpreterPathEditTooltip => '编辑解释器路径';

  @override
  String get runFieldInterpreterOptions => '解释器选项';

  @override
  String get runFieldExecuteInTerminal => '在终端中执行';

  @override
  String get runFieldAllowMultipleInstances => '允许运行多个实例';

  @override
  String get runFieldActivateToolWindow => '激活工具窗口';

  @override
  String get runFieldFocusToolWindow => '聚焦工具窗口';

  @override
  String get runExecuteScriptFile => '脚本文件';

  @override
  String get runExecuteScriptText => '脚本内容';

  @override
  String get runValidationCommandRequired => '命令不能为空';

  @override
  String get runValidationArgsMustBeStringList => '参数必须是字符串列表';

  @override
  String get runValidationEnvMustBeStringMap => '环境变量必须是字符串映射';

  @override
  String get runValidationCwdMustBeString => '工作目录必须是字符串';

  @override
  String get runValidationShellMustBeBoolean => 'Shell 必须是布尔值';

  @override
  String get runValidationConfigurationMustBeMap => '配置必须是对象';

  @override
  String get runValidationExecuteRequired => '必须选择执行方式';

  @override
  String get runValidationExecuteInvalid => '执行方式必须是脚本文件或脚本内容';

  @override
  String get runValidationScriptPathRequired => '脚本路径不能为空';

  @override
  String get runValidationScriptTextRequired => '脚本内容不能为空';

  @override
  String get runValidationInterpreterPathMustBeString => '解释器路径必须是字符串';

  @override
  String get runValidationExecuteInTerminalMustBeBoolean => '在终端中执行必须是布尔值';

  @override
  String get runValidationAllowMultipleInstancesMustBeBoolean =>
      '允许运行多个实例必须是布尔值';

  @override
  String get runValidationActivateToolWindowMustBeBoolean => '激活工具窗口必须是布尔值';

  @override
  String get runValidationFocusToolWindowMustBeBoolean => '聚焦工具窗口必须是布尔值';

  @override
  String get shortcutsRunSelected => '运行所选配置';

  @override
  String get shortcutsRunStop => '停止运行';

  @override
  String get shortcutsRunRestart => '重新运行';

  @override
  String get shortcutsCategoryRun => '运行';

  @override
  String get resourceManagerTitle => '资源管理器';

  @override
  String get resourceManagerPanelTitle => '资源管理器 - 会话';

  @override
  String resourceManagerTooltip(int count) {
    return '资源管理器 - $count 个运行中会话';
  }

  @override
  String get resourceManagerTooltipHint => '跨所有工作区的运行中会话。';

  @override
  String get resourceManagerColumnName => '名称';

  @override
  String get resourceManagerColumnCpu => 'CPU';

  @override
  String get resourceManagerColumnMemory => '内存';

  @override
  String get resourceManagerRefresh => '刷新';

  @override
  String get resourceManagerKill => '结束';

  @override
  String get resourceManagerKillAll => '全部结束';

  @override
  String get resourceManagerKillAllConfirmTitle => '结束全部运行中会话？';

  @override
  String get resourceManagerKillAllConfirmBody => '将断开列表中的全部运行中会话与终端。';

  @override
  String get resourceManagerSpace => '空间';

  @override
  String get resourceManagerSpaceBeta => 'Beta';

  @override
  String get resourceManagerSpaceNotScanned => '不会扫描工作区磁盘占用。';

  @override
  String resourceManagerSystemMemoryPercent(String percent) {
    return '系统内存 $percent%';
  }

  @override
  String resourceManagerTerminalsCount(int count) {
    return '$count 个运行中会话';
  }

  @override
  String get resourceManagerEmptyTree => '当前没有运行中的会话。';

  @override
  String get resourceManagerAppProcess => '应用';

  @override
  String get resourceManagerMetricsError => '无法刷新进程指标。';

  @override
  String get resourceManagerKillFailed => '无法结束会话。';

  @override
  String get floatingWorkspaceNewTerminal => '新 Terminal';

  @override
  String get floatingWorkspaceOpenFile => '打开文件';

  @override
  String get floatingWorkspaceMinimize => '最小化';

  @override
  String get floatingWorkspaceMaximize => '最大化';

  @override
  String get floatingWorkspaceCloseTab => '关闭标签';

  @override
  String get floatingWorkspaceAddTooltip => '在浮动工作区打开';

  @override
  String get floatingWorkspaceToggleTooltip => '浮动工作区';

  @override
  String get filePreviewHostTitle => '文件预览位置';

  @override
  String get filePreviewHostDescription => '在浮动工作区或中间工作台打开文件。';

  @override
  String get filePreviewHostFloating => '浮动';

  @override
  String get filePreviewHostCenter => '中间';

  @override
  String get termuxSetupTitle => 'Termux 设置';

  @override
  String get termuxSetupIntro =>
      '安装 Termux，粘贴一条配置脚本，然后连接 TeamPilot 的本地 SSH 服务。';

  @override
  String get termuxSetupStepInstallTermux => '1. 安装 Termux';

  @override
  String get termuxSetupInstallPlayStore => 'Play 商店';

  @override
  String get termuxSetupInstallFDroid => 'F-Droid';

  @override
  String get termuxSetupInstallGitHub => 'GitHub';

  @override
  String get termuxSetupDownloadInstall => '下载并安装 Termux';

  @override
  String get termuxSetupDownloading => '正在下载 Termux…';

  @override
  String get termuxSetupInstalling => '正在安装…';

  @override
  String get termuxSetupDownloadFailed => '无法下载 Termux。请重试或使用应用商店链接。';

  @override
  String get termuxSetupInstallDenied => '安装已取消或被阻止。如需要请启用未知来源应用，然后重试。';

  @override
  String get termuxSetupTermuxInstalled => 'Termux 已安装';

  @override
  String get termuxSetupStepRunScript => '2. 在 Termux 中粘贴这条脚本';

  @override
  String get termuxSetupScriptHint =>
      '弹出存储授权时请允许。脚本会用 termux-services 启用 sshd（打开 Termux 即启动）。若需开机且不打开 Termux，可另装 Termux:Boot（F-Droid）。最后一行会打印用户名（例如 u0_a399）。';

  @override
  String get termuxSetupUsernameLabel => '3. 粘贴 Termux 用户名';

  @override
  String get termuxSetupUsernameHint => '例如 u0_a399';

  @override
  String get termuxSetupUsernameError => '请输入有效的 Termux 用户名（以 u 开头）';

  @override
  String get termuxSetupConnect => '连接';

  @override
  String get termuxSetupConnecting => '正在连接…';

  @override
  String get termuxSetupConnectSuccess => '已连接到 Termux';

  @override
  String get termuxSetupConnectFailed => '无法连接到 Termux';

  @override
  String termuxSetupConnectFailedWithDetail(String detail) {
    return '无法连接到 Termux：$detail';
  }

  @override
  String get termuxSetupClearSetup => '清除设置';

  @override
  String get termuxSetupClearConfirmTitle => '清除 Termux 设置？';

  @override
  String get termuxSetupClearConfirmBody =>
      '将删除已保存的 Termux 密钥和用户名，需要重新完成 Termux 设置。';

  @override
  String get termuxSetupClearConfirmAction => '清除设置';

  @override
  String get termuxDisconnectedBannerMessage =>
      'Termux 已断开连接。请重新连接后再使用 Shell、Git 和 Agent 会话。';

  @override
  String get termuxDisconnectedReconnect => '重新连接';

  @override
  String get termuxDisconnectedWorkOpsBlocked => 'Termux 已断开连接。请通过顶部横幅重新连接后再试。';

  @override
  String get sshHomeDisconnectedBannerMessage =>
      '远程 SSH 工作环境已断开。请重新连接后再使用 Shell、Git 和 Agent 会话。';

  @override
  String get sshHomeDisconnectedReconnect => '重新连接';

  @override
  String get bootstrapRetry => '重试';

  @override
  String get bootstrapChooseWorkEnvironment => '选择工作环境';

  @override
  String get androidWorkEnvironmentSelectorLabel => '工作环境';

  @override
  String get androidWorkEnvironmentSelectorTermux => 'Termux';

  @override
  String androidWorkEnvironmentSelectorTermuxWithUser(String username) {
    return 'Termux · $username';
  }

  @override
  String get androidWorkEnvironmentSelectorManageTermux => 'Termux 设置…';

  @override
  String get cliTaskBoardTitle => '任务';

  @override
  String cliTaskBoardCount(int completed, int total) {
    return '$completed/$total';
  }

  @override
  String cliTaskBoardMore(int count) {
    return '… +$count 更多';
  }

  @override
  String get cliTaskStatusPending => '待处理';

  @override
  String get cliTaskStatusInProgress => '进行中';

  @override
  String get cliTaskStatusCompleted => '已完成';

  @override
  String get cliTaskStatusCancelled => '已取消';

  @override
  String get cliTaskStatusUnknown => '未知';

  @override
  String get cliTaskBoardShowLess => '收起';

  @override
  String get chatFindHint => '在对话中查找';

  @override
  String get chatFindNoResults => '无匹配';

  @override
  String get chatFindResults => '匹配结果';

  @override
  String get chatFindPrevious => '上一个匹配';

  @override
  String get chatFindNext => '下一个匹配';

  @override
  String get chatFindClose => '关闭查找';

  @override
  String get chatFindMatchCase => '区分大小写';

  @override
  String get chatFindWholeWord => '全字匹配';

  @override
  String get chatFindUseRegex => '使用正则表达式';
}
