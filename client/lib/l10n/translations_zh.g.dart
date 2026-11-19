///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'translations.g.dart';

// Path: <root>
class AppLocalizationsZh extends AppLocalizations with BaseTranslations<AppLocale, AppLocalizations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	AppLocalizationsZh({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, AppLocalizations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zh,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh>.
	final TranslationMetadata<AppLocale, AppLocalizations> _meta;
	@override TranslationMetadata<AppLocale, AppLocalizations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final AppLocalizationsZh _root = this; // ignore: unused_field

	@override 
	AppLocalizationsZh $copyWith({TranslationMetadata<AppLocale, AppLocalizations>? meta}) => AppLocalizationsZh(meta: meta ?? this.$meta);

	// Translations
	@override String get aboutCurrentVersion => '当前版本';
	@override String get aboutGitHub => 'GitHub';
	@override String get aboutPageSubtitle => 'TeamPilot 版本与应用更新。';
	@override String get aboutTitle => '关于';
	@override String get aboutVersionLoading => '加载中…';
	@override String get account => 'account';
	@override String get accountCredentialPath => '账户凭证路径';
	@override String get actualModel => '实际模型';
	@override String get add => '添加';
	@override String get addAccountPath => '添加账户路径';
	@override String get addModel => '添加模型';
	@override String get addProvider => '添加提供商';
	@override String get addTeamTitle => '添加团队';
	@override String get addTeamTooltip => '添加团队';
	@override String get addWorkspaceDirectory => '添加目录';
	@override String get allChecksPassed => '所有检查通过。';
	@override String get androidWorkEnvironmentSelectorLabel => '工作环境';
	@override String get androidWorkEnvironmentSelectorManageTermux => 'Termux 设置…';
	@override String get androidWorkEnvironmentSelectorTermux => 'Termux';
	@override String androidWorkEnvironmentSelectorTermuxWithUser({required String username}) => 'Termux · ${username}';
	@override String get api => 'api';
	@override String get apiKey => 'API 密钥';
	@override String get appearance => '外观';
	@override String get archiveConversation => '归档';
	@override String get askUserQuestionBubbleAsking => '正在提问';
	@override String get askUserQuestionBubbleUnanswered => '未回答';
	@override String get autoLaunchAllMembersDescription => '仅对混合团队生效：开启后连接或重启会为每个有效成员启动终端；native 团队始终全员启动。';
	@override String get autoLaunchAllMembersTitle => '连接时启动全部成员';
	@override String get autoOpenSubagentPreviewDescription => '子 agent 开始运行时自动弹出预览并实时跟随;按返回后停止本会话的跟随。';
	@override String get autoOpenSubagentPreviewTitle => '自动打开子会话预览';
	@override String get back => '返回';
	@override String get baseUrl => '基础 URL';
	@override String get board => '看板';
	@override String get boardClaimed => '进行中';
	@override String get boardDone => '已完成';
	@override String get boardEmpty => '暂无任务';
	@override String get boardPending => '待认领';
	@override String get bootstrapChooseWorkEnvironment => '选择工作环境';
	@override String get bootstrapLoadingApp => '正在启动 TeamPilot…';
	@override String get bootstrapLoadingLibraries => '正在加载资源库…';
	@override String get bootstrapLoadingWorkspaces => '正在加载工作区…';
	@override String get bootstrapRetry => '重试';
	@override String bootstrapStartupFailed({required String error}) => '启动失败：${error}';
	@override String get bootstrapUseNativeStorageInstead => '改用 Windows 本地存储';
	@override String get bottom => '底部';
	@override String get bottomDockPanelHidden => '隐藏底部栏';
	@override String get bottomDockPanelVisible => '显示底部栏';
	@override String get bottomTray => '底部托盘';
	@override String get branchEditFailed => '改后的消息发送失败';
	@override String get branchNext => '下一版本';
	@override String get branchPrevious => '上一版本';
	@override String get branchSwitchFailed => '切换版本失败';
	@override String get cancel => '取消';
	@override String get closeAllTabs => '关闭全部';
	@override String get closeConversation => '关闭会话';
	@override String get closeOtherTabs => '关闭其他标签';
	@override String get closeRightTabs => '关闭右侧标签';
	@override String get closeTab => '关闭';
	@override String get configure => '配置';
	@override String get confirm => '确认';
	@override String get contentDisplayModeFlatten => '铺平（自然高度）';
	@override String get contentDisplayModeFoldExpandFull => '折叠·全部展开';
	@override String get contentDisplayModeFoldFixedHeight => '折叠·固定高度';
	@override String get contentDisplayModeSectionTitle => '内容显示';
	@override String get continueSwitchRestartBody => '新的供应商/模型已保存。正在运行的会话仍在使用旧配置，重启后切换才会生效。';
	@override String get continueSwitchRestartLater => '稍后';
	@override String get continueSwitchRestartNow => '立即重启';
	@override String get continueSwitchRestartTitle => '重启以应用切换？';
	@override String get conversationName => '对话名称';
	@override String get copy => '复制';
	@override String get copyFolderPath => '复制文件夹路径';
	@override String get copyPrompt => '复制提示';
	@override String get cotExpandLatestOnOpenDescription => '自动展开最新消息的思考过程（含推理与工具调用），思考输出结束后自动收起。';
	@override String get cotExpandLatestOnOpenTitle => '自动展开最新消息的思考过程';
	@override String get cotExpandReasoningOnOpenDescription => '展开「思考过程」时，自动展开内部推理步骤。';
	@override String get cotExpandReasoningOnOpenTitle => '打开时展开推理';
	@override String get cotExpandToolsOnOpenDescription => '展开「思考过程」时，自动展开内部工具调用详情。';
	@override String get cotExpandToolsOnOpenTitle => '打开时展开工具';
	@override String get create => '创建';
	@override String get credentialPushConfirmAction => '推送凭证';
	@override String credentialPushConfirmBody({required Object host}) => 'provider 密钥将写入远程主机 ${host}。请仅对你信任的机器开启。轮换密钥后需重推到每台已开启的机器。';
	@override String get credentialPushConfirmTitle => '确认把凭证推送到远程主机？';
	@override String get credentialPushOptInSubtitle => '供远程成员认证使用。';
	@override String get credentialPushOptInTitle => '把凭证推送到此机器';
	@override String get dangerZone => '危险操作';
	@override String get defaultModel => '默认模型';
	@override String get defaultNewChatSessionTitle => '新对话';
	@override String get discoveryAutoRefreshSubtitle => '开启后，打开发现页时若缓存超过 24 小时将自动检查更新；手动刷新始终有效。';
	@override String get discoveryAutoRefreshTitle => '自动刷新发现内容';
	@override String get discoverySettingsSubtitle => '技能、插件与 MCP 发现内容的刷新方式。';
	@override String get discoverySettingsTitle => '发现与市场';
	@override String get duplicateConversation => '复制对话';
	@override String get emptyTimeline => '本地 shell 模式对话记录将显示在此处。';
	@override String get enabled => '启用';
	@override String get expertsCatalogAdoption => '添加量';
	@override String get extensionsEmptyHint => '扩展目录加载后会显示在这里。';
	@override String get extensionsEmptyTitle => '暂无可用扩展';
	@override String get extensionsNavInstalled => '已安装';
	@override String get extensionsSettingsDescription => '安装并启用增强 Agent 的外部工具。';
	@override String get extensionsSettingsTitle => '扩展';
	@override String get filterFiles => '筛选文件';
	@override String get filterProviders => '筛选提供商...';
	@override String get forkFromHere => '从这里 fork';
	@override String get formFieldRequired => '此项为必填。';
	@override String get hide => '隐藏';
	@override String get hooksNoInstalled => '暂无 hooks';
	@override String get hooksNoInstalledHint => '创建 hook，在 CLI 事件时运行命令。';
	@override String get htmlPreviewErrorBody => '无法加载文件进行预览。';
	@override String get htmlPreviewErrorTitle => '预览不可用';
	@override String get htmlPreviewOpenBrowser => '在系统浏览器打开';
	@override String get htmlPreviewOpenedInBrowser => '预览已在系统浏览器中打开，此面板可随时重新打开。';
	@override String get htmlViewToggleEdit => '编辑';
	@override String get htmlViewTogglePreview => '预览';
	@override String get injectSessionSshMcpSubtitle => '本机和远程座位都可通过 MCP 在本工作区的 SSH 机器上执行命令和传文件。更改后需重连 session。';
	@override String get injectSessionSshMcpTitle => '注入 Session SSH MCP';
	@override String get invalidJson => 'JSON 无效，请修正语法后重试。';
	@override String get jsonPreview => 'JSON 预览';
	@override String get language => '语言';
	@override String get languageChinese => '中文';
	@override String get languageDescription => '菜单、按钮与标签所使用的语言。';
	@override String get languageEnglish => 'English';
	@override String get languageSystem => '跟随系统';
	@override String get layout => '通用';
	@override String get layoutPageSubtitle => '结构控件为全局设置，适用于所有团队。';
	@override String get layoutSubtitle => '全局工作台';
	@override String get mailbox => '信箱';
	@override String get mailboxEmpty => '暂无消息';
	@override String get markdownOpenModeDescription => '在编辑器中打开 .md 文件时的默认视图。「记住上次」仅在本次应用会话内有效。';
	@override String get markdownOpenModePreview => '预览';
	@override String get markdownOpenModeRemember => '记住上次';
	@override String get markdownOpenModeSource => '源码';
	@override String get markdownOpenModeTitle => '打开 Markdown 为';
	@override String get markdownViewTogglePreview => '预览';
	@override String get markdownViewToggleSource => '源码';
	@override String get members => '成员';
	@override String get membersAndFileTree => '成员和文件树';
	@override String get membersAndFileTreeDescription => '将成员列表与文件树堆叠显示，或以标签页切换。';
	@override String get membersSubtitle => '团队代理';
	@override String get missingProvider => '缺少提供商：';
	@override String get model => '模型';
	@override String get modelId => '模型 ID';
	@override String get modelName => '模型别名/名称';
	@override String get models => '模型';
	@override String get modelsTab => '模型';
	@override String modelsUsingProvider({required int count}) => '使用此提供商的模型： ${count}';
	@override String get modelsUsingProviderTitle => '使用此提供商的模型';
	@override String get name => '名称';
	@override String get newSessionTooltip => '新建会话';
	@override String get newWorkspace => '新建工作区';
	@override String get newWorkspaceTooltip => '创建工作区';
	@override String get noModelsConfigured => '未配置模型';
	@override String get noModelsUsingProvider => '没有模型使用此提供商。';
	@override String get noSessions => '暂无会话';
	@override String get notes => '备注';
	@override String get notifyOnSessionIdleDescription => '会话结束一轮工作并进入空闲时，除应用内通知中心外，同时发送操作系统通知。';
	@override String get notifyOnSessionIdleTitle => 'Agent 空闲系统通知';
	@override String get ok => '确定';
	@override String get openExistingSessionStartsTerminalDescription => '开启后，从侧边栏打开对话会立即连接终端。关闭（默认）时先显示聊天视图，发送消息后才启动终端。';
	@override String get openExistingSessionStartsTerminalTitle => '打开已有会话时直接启动终端';
	@override String get openFolder => '打开文件夹';
	@override String get openMember => '打开成员';
	@override String get openRightTools => '工具';
	@override String get openSessionDirectory => '打开会话目录';
	@override String get openTeam => '启动所有成员';
	@override String pathCopied({required String path}) => '已复制路径：${path}';
	@override String get pickPrimaryDirectory => '选择主目录';
	@override String get pinConversation => '置顶对话';
	@override String get presetPickerNoneOption => '无（不设默认）';
	@override String get presetPickerTitle => '选择预设';
	@override String progressActivitiesMany({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '${count} 个活动进行中',
	);
	@override String get progressActivitiesPanelTitle => '进行中的活动';
	@override String get projectTreeOther => '其他';
	@override String get prompt => '提示词';
	@override String get providers => '提供商';
	@override String get providersTab => '提供商';
	@override String get proxy => '代理';
	@override String get proxyOffShort => '代理关';
	@override String get proxyOnShort => '代理开';
	@override String get proxyUrl => '代理 URL';
	@override String get rawJsonTab => '原始 JSON';
	@override String get reclaimIdleTerminalMinutesDescription => '终端可保持空闲多少分钟后被回收。';
	@override String get reclaimIdleTerminalMinutesTitle => '空闲回收超时（分钟）';
	@override String get reclaimIdleTerminalsDescription => '空闲超时后关闭成员/会话终端以释放内存；需要时自动重连。';
	@override String get reclaimIdleTerminalsTitle => '回收空闲终端';
	@override String get referenceConversation => '引用会话';
	@override String get referenceConversationFailed => '准备会话引用失败';
	@override String get regionVisibility => '区域可见性';
	@override String get removePath => '移除路径';
	@override String get removeWorkspaceDirectory => '移除目录';
	@override String get removeWorkspaceMachine => '移除机器';
	@override String get renameConversation => '重命名对话';
	@override String get renameConversationTitle => '重命名对话';
	@override String get renameProviderName => '修改名称';
	@override String get renameProviderTitle => '修改提供商名称';
	@override String get replaceKey => '替换密钥';
	@override String get restoreConversation => '恢复';
	@override String get retry => '重试';
	@override String get reveal => '显示';
	@override String get right => '右侧';
	@override String get rightTools => '右侧工具栏';
	@override String get rightToolsOpenTabEmpty => '所有工具均已打开。';
	@override String get rightToolsOpenTabSubtitle => '选择要在侧边面板中打开的标签';
	@override String get rightToolsOpenTabTitle => '打开标签页';
	@override String get rightToolsPanelHidden => '隐藏工具栏';
	@override String get rightToolsPanelVisible => '显示工具栏';
	@override String get rootSandboxEnvConfirmAction => '启用';
	@override String rootSandboxEnvConfirmBody({required Object host}) => '在 ${host} 上以 root 启动 Claude 时，TeamPilot 将设置 IS_SANDBOX=1 并保留 --dangerously-skip-permissions。请仅对你信任的机器开启。';
	@override String get rootSandboxEnvConfirmTitle => '确认为 root 启用 sandbox 环境变量？';
	@override String get rootSandboxEnvOptInSubtitle => 'root 启动 Claude 时保留 skip-permissions。';
	@override String get rootSandboxEnvOptInTitle => '为 root 注入 IS_SANDBOX';
	@override String get runsPlaceholder => '运行历史将显示在此处。';
	@override String get save => '保存';
	@override String get saveMember => '保存成员';
	@override String get scopeSessionsToSelectedTeamDescription => '开启后，侧边栏仅显示归属当前团队的会话。新建会话仍会写入当前所选团队，之后开启本选项即可看到它们。';
	@override String get scopeSessionsToSelectedTeamTitle => '按所选团队筛选会话';
	@override String get selectAgent => '选择预设';
	@override String get selectModel => '选择一个模型';
	@override String get selectProvider => '从列表中选择一个提供商';
	@override String get selectTeam => '选择团队';
	@override String get selectionAskAi => '用 AI 提问…';
	@override String get sendPrompt => '发送提示';
	@override String get settings => '设置';
	@override String get settingsPageSubtitle => '管理 FlashskyAI 团队和模型设置。';
	@override String get shellChatWorkbench => 'Shell 聊天工作台';
	@override String get shellSession => 'Shell 会话';
	@override String get sidebarPanelHidden => '隐藏侧边栏';
	@override String get sidebarPanelVisible => '显示侧边栏';
	@override String get sourceControl => '源代码管理';
	@override String get stacked => '堆叠';
	@override String get stackedTools => '堆叠工具栏';
	@override String get statEmptyKeys => '空密钥';
	@override String get statMissingRefs => '缺失引用';
	@override String get statModels => '个模型';
	@override String get statProviders => '个提供商';
	@override String get subagentPreviewBack => '返回';
	@override String get subagentPreviewEmpty => '暂无子会话内容';
	@override String subagentPreviewTitleAgent({required String title}) => '${title}';
	@override String get subagentPreviewUnavailable => '无法打开该子会话预览';
	@override String get summary => '摘要';
	@override String get switchToMember => '切换到成员';
	@override String get switchWorkspaceTooltip => '切换工作区';
	@override String get tabMenuSplitDown => '向下拆分';
	@override String get tabMenuSplitRight => '向右拆分';
	@override String get tabbedTools => '标签工具栏';
	@override String get tabs => '标签页';
	@override String get teamsCatalogAdoption => '添加量';
	@override String get thinkingProcessFoldSectionTitle => '折叠进思考过程';
	@override String get thinkingProcessSectionTitle => '思考过程';
	@override String get toolchainGit => 'Git';

	/// Label for Git executable path setting
	@override String get toolchainGitLabel => 'Git 可执行文件路径';

	/// Progress message when checking for a toolchain tool
	@override String toolchainInstallProgressChecking({required String tool}) => '正在检查 ${tool}...';

	@override String get toolchainNode => 'Node.js';

	/// Label for Node.js/npm path setting
	@override String get toolchainNodeLabel => 'Node.js / npm 路径';

	/// Description for toolchain path setting
	@override String toolchainPathDescription({required String tool}) => '${tool} 可执行文件的绝对路径。留空则使用 PATH 中的版本。';

	/// Description for toolchain path setting in SSH mode
	@override String toolchainPathDescriptionSsh({required String tool}) => '远程 SSH 主机上 ${tool} 的绝对路径。留空则自动发现。';

	@override String get treeCollapseAllFolders => '折叠所有目录';
	@override String get treeExpandAllFolders => '展开所有目录';
	@override String get type => '类型';
	@override String get uiZoomDescription => '整体缩放界面——文字、图标与间距一起。「标准」按系统缩放自动匹配。';
	@override String get uiZoomTitle => '界面缩放';
	@override String get unknownFolder => '未知';
	@override String get unpinConversation => '取消置顶';
	@override String get validate => '校验';
	@override String get validation => '验证';
	@override String get visibilityBoardHint => '显示混合模式团队的任务看板。';
	@override String get visibilityFileTreeHint => '显示工作区文件树以便快速浏览。';
	@override String get visibilityGitHint => '显示当前仓库的源代码管理面板。';
	@override String get visibilityMembersHint => '在工具或终端旁显示成员列表。';
	@override String get visibilityRightToolsHint => '打开会话时显示右侧工具栏。';
	@override String get visibilityTeamSessionsHint => '在左侧边栏显示团队会话列表。';
	@override String get windowControlAlwaysOnTop => '置顶';
	@override String get windowControlClose => '关闭';
	@override String get windowControlMaximize => '最大化';
	@override String get windowControlMinimize => '最小化';
	@override String get windowControlRestore => '还原';
	@override String get windowsStorageCliMismatchNativeCli => 'CLI 在 WSL 中运行，但数据保存在 Windows AppData，配置可能不一致。';
	@override String get windowsStorageCliMismatchWslCli => 'CLI 在 Windows 上运行，但数据保存在 WSL，配置可能不一致。';
	@override String get windowsStorageSwitchReloadHint => '切换存储后建议重连已打开的会话。';
	@override String get workbenchLockGroup => '锁定组';
	@override String get workbenchStripNewMenuTooltip => '新建';
	@override String get workbenchUnlockGroup => '解锁组';
	@override String workflowCardAgents({required int count}) => '${count} 个 agent';
	@override String get workflowCardRunMissing => '未找到该调用的 Workflow 运行记录';
	@override String get workspaces => '工作区';
	@override String askUserQuestionBubbleAsked({required int count}) => '已询问 ${count} 个问题';
	@override late final _AppLocalizations$acp$zh acp = _AppLocalizations$acp$zh._(_root);
	@override late final _AppLocalizations$agent$zh agent = _AppLocalizations$agent$zh._(_root);
	@override late final _AppLocalizations$ai$zh ai = _AppLocalizations$ai$zh._(_root);
	@override late final _AppLocalizations$antigravity$zh antigravity = _AppLocalizations$antigravity$zh._(_root);
	@override late final _AppLocalizations$app$zh app = _AppLocalizations$app$zh._(_root);
	@override late final _AppLocalizations$appProvider$zh appProvider = _AppLocalizations$appProvider$zh._(_root);
	@override late final _AppLocalizations$automations$zh automations = _AppLocalizations$automations$zh._(_root);
	@override late final _AppLocalizations$catalog$zh catalog = _AppLocalizations$catalog$zh._(_root);
	@override late final _AppLocalizations$chat$zh chat = _AppLocalizations$chat$zh._(_root);
	@override late final _AppLocalizations$claude$zh claude = _AppLocalizations$claude$zh._(_root);
	@override late final _AppLocalizations$cli$zh cli = _AppLocalizations$cli$zh._(_root);
	@override late final _AppLocalizations$clone$zh clone = _AppLocalizations$clone$zh._(_root);
	@override late final _AppLocalizations$codebuddy$zh codebuddy = _AppLocalizations$codebuddy$zh._(_root);
	@override late final _AppLocalizations$codex$zh codex = _AppLocalizations$codex$zh._(_root);
	@override late final _AppLocalizations$compose$zh compose = _AppLocalizations$compose$zh._(_root);
	@override late final _AppLocalizations$connect$zh connect = _AppLocalizations$connect$zh._(_root);
	@override late final _AppLocalizations$cursor$zh cursor = _AppLocalizations$cursor$zh._(_root);
	@override late final _AppLocalizations$delete$zh delete = _AppLocalizations$delete$zh._(_root);
	@override late final _AppLocalizations$diff$zh diff = _AppLocalizations$diff$zh._(_root);
	@override late final _AppLocalizations$download$zh download = _AppLocalizations$download$zh._(_root);
	@override late final _AppLocalizations$edit$zh edit = _AppLocalizations$edit$zh._(_root);
	@override late final _AppLocalizations$editor$zh editor = _AppLocalizations$editor$zh._(_root);
	@override late final _AppLocalizations$exit$zh exit = _AppLocalizations$exit$zh._(_root);
	@override late final _AppLocalizations$expert$zh expert = _AppLocalizations$expert$zh._(_root);
	@override late final _AppLocalizations$extension$zh extension = _AppLocalizations$extension$zh._(_root);
	@override late final _AppLocalizations$file$zh file = _AppLocalizations$file$zh._(_root);
	@override late final _AppLocalizations$fileTree$zh fileTree = _AppLocalizations$fileTree$zh._(_root);
	@override late final _AppLocalizations$floating$zh floating = _AppLocalizations$floating$zh._(_root);
	@override late final _AppLocalizations$font$zh font = _AppLocalizations$font$zh._(_root);
	@override late final _AppLocalizations$git$zh git = _AppLocalizations$git$zh._(_root);
	@override late final _AppLocalizations$gitGraph$zh gitGraph = _AppLocalizations$gitGraph$zh._(_root);
	@override late final _AppLocalizations$github$zh github = _AppLocalizations$github$zh._(_root);
	@override late final _AppLocalizations$grok$zh grok = _AppLocalizations$grok$zh._(_root);
	@override late final _AppLocalizations$home$zh home = _AppLocalizations$home$zh._(_root);
	@override late final _AppLocalizations$homeWorkspace$zh homeWorkspace = _AppLocalizations$homeWorkspace$zh._(_root);
	@override late final _AppLocalizations$hook$zh hook = _AppLocalizations$hook$zh._(_root);
	@override late final _AppLocalizations$hub$zh hub = _AppLocalizations$hub$zh._(_root);
	@override late final _AppLocalizations$init$zh init = _AppLocalizations$init$zh._(_root);
	@override late final _AppLocalizations$landing$zh landing = _AppLocalizations$landing$zh._(_root);
	@override late final _AppLocalizations$llm$zh llm = _AppLocalizations$llm$zh._(_root);
	@override late final _AppLocalizations$log$zh log = _AppLocalizations$log$zh._(_root);
	@override late final _AppLocalizations$managedProviders$zh managedProviders = _AppLocalizations$managedProviders$zh._(_root);
	@override late final _AppLocalizations$mcp$zh mcp = _AppLocalizations$mcp$zh._(_root);
	@override late final _AppLocalizations$member$zh member = _AppLocalizations$member$zh._(_root);
	@override late final _AppLocalizations$mixed$zh mixed = _AppLocalizations$mixed$zh._(_root);
	@override late final _AppLocalizations$my$zh my = _AppLocalizations$my$zh._(_root);
	@override late final _AppLocalizations$notification$zh notification = _AppLocalizations$notification$zh._(_root);
	@override late final _AppLocalizations$onboarding$zh onboarding = _AppLocalizations$onboarding$zh._(_root);
	@override late final _AppLocalizations$opencode$zh opencode = _AppLocalizations$opencode$zh._(_root);
	@override late final _AppLocalizations$plugin$zh plugin = _AppLocalizations$plugin$zh._(_root);
	@override late final _AppLocalizations$plugins$zh plugins = _AppLocalizations$plugins$zh._(_root);
	@override late final _AppLocalizations$provider$zh provider = _AppLocalizations$provider$zh._(_root);
	@override late final _AppLocalizations$qoder$zh qoder = _AppLocalizations$qoder$zh._(_root);
	@override late final _AppLocalizations$remote$zh remote = _AppLocalizations$remote$zh._(_root);
	@override late final _AppLocalizations$resource$zh resource = _AppLocalizations$resource$zh._(_root);
	@override late final _AppLocalizations$rtk$zh rtk = _AppLocalizations$rtk$zh._(_root);
	@override late final _AppLocalizations$run$zh run = _AppLocalizations$run$zh._(_root);
	@override late final _AppLocalizations$session$zh session = _AppLocalizations$session$zh._(_root);
	@override late final _AppLocalizations$sessionUsage$zh sessionUsage = _AppLocalizations$sessionUsage$zh._(_root);
	@override late final _AppLocalizations$shortcuts$zh shortcuts = _AppLocalizations$shortcuts$zh._(_root);
	@override late final _AppLocalizations$skills$zh skills = _AppLocalizations$skills$zh._(_root);
	@override late final _AppLocalizations$ssh$zh ssh = _AppLocalizations$ssh$zh._(_root);
	@override late final _AppLocalizations$sshProfile$zh sshProfile = _AppLocalizations$sshProfile$zh._(_root);
	@override late final _AppLocalizations$team$zh team = _AppLocalizations$team$zh._(_root);
	@override late final _AppLocalizations$teamHub$zh teamHub = _AppLocalizations$teamHub$zh._(_root);
	@override late final _AppLocalizations$terminal$zh terminal = _AppLocalizations$terminal$zh._(_root);
	@override late final _AppLocalizations$termux$zh termux = _AppLocalizations$termux$zh._(_root);
	@override late final _AppLocalizations$theme$zh theme = _AppLocalizations$theme$zh._(_root);
	@override late final _AppLocalizations$tool$zh tool = _AppLocalizations$tool$zh._(_root);
	@override late final _AppLocalizations$typography$zh typography = _AppLocalizations$typography$zh._(_root);
	@override late final _AppLocalizations$vault$zh vault = _AppLocalizations$vault$zh._(_root);
	@override late final _AppLocalizations$workspace$zh workspace = _AppLocalizations$workspace$zh._(_root);
	@override late final _AppLocalizations$worktree$zh worktree = _AppLocalizations$worktree$zh._(_root);
}

// Path: acp
class _AppLocalizations$acp$zh extends AppLocalizations$acp$en {
	_AppLocalizations$acp$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String chatLaunchFailed({required String cliName}) => '无法启动 ${cliName}，请确认已安装对应 CLI 后重试。';
	@override String get chatNotLoggedIn => '代理尚未登录。请到设置 → 服务商完成登录后重试。';
	@override String chatProcessExited({required String cliName}) => '${cliName} 意外退出';
	@override String chatSessionOpenFailed({required String cliName}) => '无法打开 ${cliName} 会话。';
	@override String get chatTurnFailed => '本轮对话失败';
	@override String get launchFailedAdapter => '无法启动 Claude ACP 适配器（claude-agent-acp）。请安装后重试。';
	@override String get launchFailedVersion => '当前 CLI 版本不支持 ACP 聊天模式，请更新后再试。';
	@override String get modelSectionAgent => 'Agent 模型';
	@override String get modelSectionLaunch => '启动配置';
	@override String get modelSwitchFailed => '无法切换 ACP 模型，请重试。';
	@override String get permissionAskLabel => '询问';
	@override String get permissionFullAccessLabel => '完全访问';
}

// Path: agent
class _AppLocalizations$agent$zh extends AppLocalizations$agent$en {
	_AppLocalizations$agent$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get agent => 'Agent 预设';
	@override String get askAnswerFailed => '无法提交回答。请重试或在终端中回答。';
	@override String get askAnswerInTerminal => '在终端回答';
	@override String get askCancelQuestion => '取消提问';
	@override String get askContinue => '继续';
	@override String get askCustomAnswerHint => '输入你的回答…';
	@override String get askEscToCancel => 'Esc 取消';
	@override String get askIgnore => '忽略';
	@override String get askKeyboardHint => '使用 Tab / 上下键选择，回车或空格选中';
	@override String askQuestionTabFallback({required int index}) => '问题${index}';
	@override String get askSubmitAnswers => '提交';
	@override String get askTerminalDisconnected => '终端已断开。请重新连接或在终端中回答。';
	@override String get askUserQuestionTitle => '正在向你提问';
	@override String get builtInCustom => '自定义…';
	@override String get builtInNone => '默认';
	@override String get builtInSubtitle => '指定该成员以哪种 Agent 身份协作，影响其行为与可用能力。';
	@override String get claudeTypeHint => '例如 Explore、Plan 或自定义类型';
	@override String get claudeTypeSubtitle => '写入 Claude 团队 roster 的 agentType；留空则使用成员 ID。';
	@override String get customIdHint => '自定义 Agent 标识';
	@override String get flashskyaiPresetSubtitle => '对应 flashskyai 的 --agent 参数，可选内置或自定义子 Agent。';
	@override String permissionAlwaysAllowRule({required Object rule}) => '始终允许 ${rule}';
	@override String get permissionAttentionBanner => '此智能体需要在终端中确认。';
	@override String get permissionOpenTerminal => '打开终端';
	@override String permissionTitle({required String cliName}) => '${cliName} 需要你的授权';
	@override String get permissionTitleGeneric => '需要你的授权';
}

// Path: ai
class _AppLocalizations$ai$zh extends AppLocalizations$ai$en {
	_AppLocalizations$ai$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get featureCliLabel => 'CLI';
	@override String get featureCommitMessageSubtitle => '由源代码管理面板里的 ✨ 按钮使用。';
	@override String get featureCommitMessageTitle => '提交信息生成';
	@override String featureConfigSummary({required String cli, required String provider, required String model}) => '${cli} · ${provider} · ${model}';
	@override String get featureEffortLabel => 'Effort';
	@override String get featureModelLabel => '模型';
	@override String get featureTeamGenerateSubtitle => '从描述生成团队时使用。';
	@override String get featureTeamGenerateTitle => '团队配置生成';
	@override String get features => 'AI 功能';
	@override String get featuresPageSubtitle => '为每个 AI 功能选择使用的 CLI provider、模型与 effort。';
	@override String get messageCancelled => '消息已取消';
	@override String get messageCancelledTool => '已取消工具';
	@override String get messageCopied => '已复制';
	@override String get messageExportMarkdown => '导出 Markdown';
	@override String get messageIncomplete => '消息未完成';
	@override String get messageReasoning => '推理';
	@override String get messageScrollToBottom => '滚动到底部';
	@override String get messageShowLess => '收起';
	@override String get messageShowMore => '显示更多';
	@override String messageThinkingCommands({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '运行了 ${count} 条命令',
	);
	@override String messageThinkingEditedFiles({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '编辑了 ${count} 个文件',
	);
	@override String messageThinkingExploredFiles({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '探索了 ${count} 个文件',
	);
	@override String get messageThinkingProcess => '思考过程';
	@override String messageThinkingProcessStats({required int steps, required int toolCalls}) => '思考过程 · ${steps} 步 · ${toolCalls} 次工具调用';
	@override String messageThinkingProcessSteps({required int count}) => '思考过程 · ${count} 步';
	@override String get messageThinkingProcessSummarySeparator => '，';
	@override String messageThinkingSearches({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '${count} 次搜索',
	);
	@override String get messageToolResult => '结果';
	@override String messageToolsUsed({required Object count}) => '已使用 ${count} 个工具';
	@override String get messageUsedTool => '已使用工具';
	@override String toolFileNotFound({required String path}) => '找不到文件：${path}';
}

// Path: antigravity
class _AppLocalizations$antigravity$zh extends AppLocalizations$antigravity$en {
	_AppLocalizations$antigravity$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get credentialsActionFailed => 'Antigravity 登录失败。';
	@override String get credentialsCancel => '取消';
	@override String get credentialsDone => '完成';
	@override String get credentialsLogin => '登录';
	@override String get credentialsLoginExited => 'Antigravity 已退出。请关闭此对话框后重新登录。';
	@override String credentialsLoginFailed({required String error}) => '无法启动登录终端：${error}';
	@override String get credentialsLoginIntro => '在下方终端完成 Google 登录，然后点击“完成”。Antigravity 将账号保存在系统钥匙串中，所有 Antigravity 会话以及所有官方 Antigravity 供应商行都会共享该账号。';
	@override String get credentialsLoginStarting => '正在启动 Antigravity…';
	@override String get credentialsLoginTitle => '登录 Antigravity';
	@override String get credentialsLoginVerifyFailed => 'Antigravity 未确认登录成功（agy models 执行失败）。请完成登录后再次点击“完成”。';
	@override String get credentialsRetry => '重试';
	@override String get credentialsSignedIn => '已登录 Antigravity。';
}

// Path: app
class _AppLocalizations$app$zh extends AppLocalizations$app$en {
	_AppLocalizations$app$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get dropdownSearchHint => '搜索…';
	@override String get dropdownSearchNoResults => '未找到结果';
	@override String get rail => '应用导航栏';
	@override String get railChat => '聊天';
	@override String get railConfig => '配置';
	@override String get railRuns => '运行';
	@override String get title => 'TeamPilot';
	@override String get updateAutoCheck => '自动检查更新';
	@override String get updateAutoCheckHint => '每次启动时自动从 GitHub 检查新版本。';
	@override String get updateBrowserDownload => '浏览器下载';
	@override String updateBrowserOpenFailed({required String error}) => '打开浏览器失败：${error}';
	@override String get updateBrowserOpened => '已在浏览器中打开下载链接';
	@override String get updateCannotOpenDownloadLink => '无法打开下载链接';
	@override String get updateChangelogDefaultSection => '更新';
	@override String get updateChangelogTitle => '更新内容';
	@override String get updateCheck => '检查更新';
	@override String get updateDialogTitle => '发现新版本';
	@override String get updateDownloadComplete => '下载完成';
	@override String updateDownloadError({required String error}) => '下载过程中发生错误：${error}';
	@override String get updateDownloadFailed => '下载失败';
	@override String get updateDownloadInBackground => '后台下载';
	@override String get updateDownloadInstall => '下载并安装';
	@override String get updateDownloadNow => '立即下载';
	@override String get updateDownloadStarting => '开始下载…';
	@override String get updateDownloading => '正在下载更新…';
	@override String get updateInstallComplete => '安装完成';
	@override String updateInstallFailed({required String message}) => '安装失败：${message}';
	@override String get updateInstallNoResult => '安装未返回结果';
	@override String get updateInstallNow => '立即安装';
	@override String get updateInstalling => '正在安装更新…';
	@override String get updateInvalidPackagePath => '安装包路径无效';
	@override String get updateLater => '以后更新';
	@override String get updateLatestVersion => '最新版本';
	@override String updateNewVersion({required String version}) => '新版本 ${version} 可用';
	@override String get updatePackagePlatformMismatch => '安装包类型与当前系统不匹配';
	@override String get updateReadyToDownload => '准备下载';
	@override String get updateRedirectBrowserOnly => '该链接需要在浏览器中下载';
	@override String get updateReleaseBuildRequired => '请使用 Release 构建包进行应用内安装';
	@override String get updateResolvingDownloadUrl => '正在获取下载链接…';
	@override String get updateSkipVersion => '跳过此版本';
	@override String get updateUnknownVersion => '未知';
	@override String get updateUpToDate => '已是最新版本。';
	@override String get updateViewRelease => '在 GitHub 查看发布';
	@override String get updateViewReleases => '查看发布';
}

// Path: appProvider
class _AppLocalizations$appProvider$zh extends AppLocalizations$appProvider$en {
	_AppLocalizations$appProvider$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get advancedJson => '高级 JSON 编辑';
	@override String get advancedOptions => '高级选项';
	@override String get apiKeyEditHint => '留空则保留原密钥';
	@override String get catalogHint => 'TeamPilot 在此维护统一服务商；团队启动时会为各工具生成隔离配置。';
	@override String get catalogLabel => '应用级服务商目录';
	@override String get claudeAuthApiKey => 'ANTHROPIC_API_KEY';
	@override String get claudeAuthField => '认证字段';
	@override String get claudeAuthFieldHint => '选择写入 settings 的认证环境变量。';
	@override String get claudeAuthTokenDefault => 'ANTHROPIC_AUTH_TOKEN（默认）';
	@override String get claudeCredentialBinding => 'OAuth 凭证来源';
	@override String get claudeCredentialBindingIsolated => '隔离副本（仅 TeamPilot）';
	@override String get claudeCredentialBindingIsolatedHint => '在 TeamPilot 目录保存独立凭证副本；适用于不能与全局 Claude Code 共用登录的场景。';
	@override String get claudeCredentialBindingLinked => '跟随全局（~/.claude）';
	@override String get claudeCredentialBindingLinkedHint => '与终端里 Claude Code 共用同一份 OAuth 会话，刷新会自动保持同步。';
	@override String get credentialLinkEmpty => '还没有存有密钥的余额条目';
	@override String get credentialLinkMode => 'API Key 来源';
	@override String get credentialLinkOwnKey => '使用自己的 API Key';
	@override String credentialLinkedTo({required Object entry}) => '使用 ${entry} 的密钥';
	@override String get displayName => '显示名称';
	@override String get enabledTools => '启用的工具';
	@override String get import => '导入';
	@override String get importNothing => '未发现可导入的提供商。';
	@override String importSuccess({required int count, required int mirrored, required int skipped}) => '已导入 ${count} 个提供商，同步到 FlashskyAI ${mirrored} 个，跳过已存在 ${skipped} 个。';
	@override String internalIdPreview({required String id}) => '内部 id：${id}';
	@override String get modelEnterCustom => '输入自定义模型 ID';
	@override String get modelPickFromList => '从列表选择';
	@override String get opencodeSubscription => '订阅';
	@override String get opencodeSubscriptionOff => '仅免费模型。绑定 OpenCode Go 后可使用订阅模型。';
	@override String get opencodeSubscriptionOn => '已绑定 OpenCode Go，订阅模型与免费模型均可用。';
	@override String get presetCustom => '自定义';
	@override String get presetLabel => '预设';
	@override String get teamNone => '无';
	@override String get teamToolSection => '团队默认服务商';
	@override String get teamToolSubtitle => '选择本团队启动时，各工具使用的统一服务商。';
	@override String get toolAntigravity => 'Antigravity';
	@override String get toolClaude => 'Claude Code';
	@override String get toolCodebuddy => 'CodeBuddy';
	@override String get toolCodex => 'Codex';
	@override String get toolCursor => 'Cursor';
	@override String get toolFlashskyai => 'FlashskyAI';
	@override String get toolGemini => 'Gemini CLI';
	@override String get toolOpencode => 'OpenCode';
	@override String get toolQoder => 'Qoder';
	@override String get toolQoderCn => 'Qoder 国内版';
	@override String get website => '官网';
	@override String get toolGrok => 'Grok CLI';
}

// Path: automations
class _AppLocalizations$automations$zh extends AppLocalizations$automations$en {
	_AppLocalizations$automations$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get boundSession => '绑定会话';
	@override String get boundSessionPending => '首次运行后自动绑定会话';
	@override String get boundSessionUnavailable => '会话不可用，请切换或解绑';
	@override String get catchUpOnce => '启动后补跑一次';
	@override String get cli => 'CLI';
	@override String get command => '命令';
	@override String get commandHelp => '仅在 TeamPilot 运行时执行。超过宽限期的错过运行会被跳过，除非开启了补跑。';
	@override String get commandRequired => '命令不能为空';
	@override String get commandTimeout => '超时（秒）';
	@override String get commandTimeoutInvalid => '超时时间必须是整数秒';
	@override String get commandTimeoutRange => '超时时间须在 30 到 1800 秒之间';
	@override String get commandTooLong => '命令不能超过 2000 个字符';
	@override String get commandWorkingDirectory => '工作目录';
	@override String get commandWorkingDirectoryMain => '工作区默认目录';
	@override String get compactTitle => '定时消息';
	@override String get countdownCustom => '自定义';
	@override String countdownHours({required int hours}) => '${hours} 小时';
	@override String countdownMinutes({required int minutes}) => '${minutes} 分钟';
	@override String countdownPreview({required String dateTime}) => '将在 ${dateTime} 执行';
	@override String get createTitle => '新建自动化';
	@override String get customCron => 'Cron 表达式';
	@override String get dayFriday => '周五';
	@override String get dayMonday => '周一';
	@override String get daySaturday => '周六';
	@override String get daySunday => '周日';
	@override String get dayThursday => '周四';
	@override String get dayTuesday => '周二';
	@override String get dayWednesday => '周三';
	@override String get delete => '删除';
	@override String get deleteConfirm => '删除此自动化？';
	@override String get dispatchFailed => '分发失败';
	@override String get edit => '编辑';
	@override String get editTitle => '编辑自动化';
	@override String get empty => '暂无自动化';
	@override String get enabled => '已启用';
	@override String exitCode({required int code}) => '退出码 ${code}';
	@override String get filterActionAll => '全部类型';
	@override String get filterActionLabel => '类型';
	@override String get filterAll => '全部';
	@override String get filterDisabled => '仅已禁用';
	@override String get filterEnabled => '仅已启用';
	@override String get filterLaunchPrompt => '启动 prompt';
	@override String get filterScheduledMessage => '定时消息';
	@override String get filterStatusLabel => '状态';
	@override String get hideFilter => '隐藏筛选';
	@override String get invalidCron => '无效的 cron 表达式（需要 5 个字段）';

	/// Validation error for run limit field
	@override String get invalidMaxRunCount => '运行次数上限须为正整数';

	@override String get invalidTime => '时间格式须为 HH:mm';

	/// Simple vs team launch mode for automation editor
	@override String get launchMode => '对话模式';

	/// Deprecated — use automationsLaunchMode
	@override String get launchProfile => '启动身份';

	/// Workspace project folder for launch-prompt automations
	@override String get launchProject => '项目';

	/// Git worktree cwd for launch-prompt automations
	@override String get launchWorktree => 'Worktree';

	@override String get manageAll => '管理全部定时任务';
	@override String get manageSessionContextMenu => '管理定时消息';

	/// Label for optional max automation run count
	@override String get maxRunCount => '运行次数上限';

	/// Hint for run limit field
	@override String get maxRunCountHint => '留空表示无限制';

	@override String get message => '消息';
	@override String get name => '名称';
	@override String get kNew => '新建自动化';
	@override String nextRun({required String time}) => '下次运行：${time}';
	@override String get nextRunNone => '暂无计划运行';
	@override String get presetCliMismatch => '所选预设与绑定会话的 CLI 不一致。';
	@override String get presetEmptyForCli => '该 CLI 暂无可用预设。';
	@override String get presetScopeHint => '已绑定会话，仅显示该会话 CLI 的预设。';
	@override String get reuseSession => '复用会话';
	@override String reuseSessionListHint({required String sessionId}) => '复用对话 ${sessionId}';
	@override String reuseSessionSubtitleBound({required String sessionId}) => '已绑定会话 ${sessionId}';
	@override String get reuseSessionSubtitleOff => '每次运行都会新建一个对话。';
	@override String get reuseSessionSubtitlePending => '首次运行会创建对话，之后在同一会话中继续。';
	@override String runCountLimited({required int count, required int max}) => '已运行 ${count} / ${max}';
	@override String runCountUnlimited({required int count}) => '已运行 ${count} 次';
	@override String runDurationMilliseconds({required int milliseconds}) => '耗时 ${milliseconds} 毫秒';
	@override String runDurationSeconds({required int seconds}) => '耗时 ${seconds} 秒';
	@override String runError({required String error}) => '错误：${error}';
	@override String get runHistory => '运行历史';
	@override String get runHistoryEmpty => '暂无运行记录';
	@override String get runNow => '立即运行';
	@override String get runOutputTruncated => '输出已截断';
	@override String get runStatusCompleted => '已完成';
	@override String get runStatusDispatched => '已分发';
	@override String get runStatusDispatching => '分发中';
	@override String get runStatusFailed => '失败';
	@override String get runStatusPending => '等待中';
	@override String get runStatusSkippedMissed => '已跳过 — 错过窗口';
	@override String get runStatusSkippedOverlap => '已跳过（上次仍在运行）';
	@override String get runStatusTimedOut => '超时';
	@override String get runStderr => '标准错误';
	@override String get runStdout => '标准输出';
	@override String get schedule => '调度';
	@override String get scheduleCustom => '自定义 cron';
	@override String get scheduleDaily => '每天';
	@override String get scheduleDate => '日期';
	@override String get scheduleHourly => '每小时';
	@override String get scheduleModeCountdown => '倒计时';
	@override String get scheduleModeOnce => '一次';
	@override String get scheduleModeRecurring => '循环';
	@override String get scheduleOnce => '一次';
	@override String get schedulePastTime => '请选择未来的时间';
	@override String scheduleSummaryDaily({required String time}) => '每天 ${time}';
	@override String scheduleSummaryHourly({required int minute}) => '每小时 :${minute}';
	@override String scheduleSummaryOnce({required String time}) => '一次，${time}';
	@override String scheduleSummaryWeekdays({required String time}) => '工作日 ${time}';
	@override String scheduleSummaryWeekly({required String day, required String time}) => '每周${day} ${time}';
	@override String get scheduleType => '类型';
	@override String get scheduleWeekdays => '工作日';
	@override String get scheduleWeekly => '每周';
	@override String scopeModePersonal({required String profile}) => '个人 · ${profile}';
	@override String scopeModeTeam({required String team}) => '团队 · ${team}';
	@override String scopePersonal({required String preset}) => '个人 · ${preset}';
	@override String scopeScheduledMessage({required String sessionId}) => '定时消息 · ${sessionId}';
	@override String scopeTeam({required String team, required String member}) => '团队 · ${team} · ${member}';
	@override String scopeTeamMember({required String member}) => '团队 · ${member}';
	@override String get sessionContextMenu => '定时消息…';
	@override String sessionDefaultName({required String title}) => '${title} — 定时消息';
	@override String get sessionPickerEmpty => '没有可绑定的会话';
	@override String get sessionPickerTitle => '选择会话';
	@override String get sessionTitle => '会话标题';
	@override String get sessionTitleHint => '留空则使用定时任务名称。';
	@override String get showFilter => '显示筛选';
	@override String get sidebarTitle => '定时任务';
	@override String get skippedUnavailable => '已跳过 — 会话不可用';
	@override String get sort => '排序自动化';
	@override String get sortNameAsc => '名称 (A–Z)';
	@override String get sortNameDesc => '名称 (Z–A)';
	@override String get sortNextRun => '下次运行';
	@override String get sortRecentlyUpdated => '最近更新';
	@override String get statusBarEmpty => '暂无启用的定时任务';

	/// Subtitle for automations management page
	@override String get subtitle => '跨项目与会话定时发送消息或启动 prompt。';

	@override String get switchSession => '切换会话';
	@override String get targetMember => '目标成员';
	@override String get time => '时间';

	/// Title for automations management UI
	@override String get title => '全部自动化';

	@override String get unbindSession => '解绑';
	@override String get validationRequired => '名称和消息为必填项';
}

// Path: catalog
class _AppLocalizations$catalog$zh extends AppLocalizations$catalog$en {
	_AppLocalizations$catalog$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String cardAccessibilityLabel({required String name, required String source}) => '${name}，来源：${source}';
	@override String get metricMissing => '暂无数据';
	@override String get metricMissingTooltip => '暂无可用数据';
	@override String get metricName => '名称';
	@override String get metricPublished => '发布日期';
	@override String get metricRating => '评分';
	@override String get metricUpdated => '最近更新';
	@override String missingMetricAccessibilityLabel({required String label}) => '${label}：暂无可用数据';
	@override String get refreshAccessibilityLabel => '刷新目录';
	@override String get sortAccessibilityLabel => '排列目录条目';
	@override String get sortAdoption => '采用量最高';
	@override String get sortName => '名称';
	@override String get sortPublished => '最近发布';
	@override String get sortRating => '评分最高';
	@override String get sortUpdated => '最近更新';
	@override String sourceWarningAccessibilityLabel({required int count}) => '有 ${count} 个目录源加载失败';
	@override String sourceWarningEntry({required String source, required String error}) => '${source}：${error}';
	@override String get sourceWarningLabel => '部分目录源加载失败';
}

// Path: chat
class _AppLocalizations$chat$zh extends AppLocalizations$chat$en {
	_AppLocalizations$chat$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get codeBlockModeDescription => '聊天中超大代码块的呈现方式。';
	@override String get codeBlockModeTitle => '聊天·代码块';
	@override String get findClose => '关闭查找';
	@override String get findHint => '在对话中查找';
	@override String get findMatchCase => '区分大小写';
	@override String get findNext => '下一个匹配';
	@override String get findNoResults => '无匹配';
	@override String get findPrevious => '上一个匹配';
	@override String get findResults => '匹配结果';
	@override String get findUseRegex => '使用正则表达式';
	@override String get findWholeWord => '全字匹配';
	@override String get hintText => '为 team-lead 编写提示...';
	@override String get submitSwitchesToTerminalDescription => '关闭（默认）时，在聊天页发送（新建或继续）后仍留在聊天视图，终端在后台运行。开启后，发送后切换到终端。';
	@override String get submitSwitchesToTerminalTitle => '发送后切换到终端';
	@override String get to => '发送至：';
	@override String get userMessageModeDescription => '聊天中超大用户消息的呈现方式。';
	@override String get userMessageModeTitle => '用户消息';
	@override String get userMessageRailEmptyPreview => '空消息';
	@override String userMessageRailSemanticLabel({required int index, required int total}) => '用户消息第 ${index} 条，共 ${total} 条';
}

// Path: claude
class _AppLocalizations$claude$zh extends AppLocalizations$claude$en {
	_AppLocalizations$claude$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get cliExecutablePathDescription => 'Claude Code 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';
	@override String get cliExecutablePathDescriptionSsh => '远程 SSH 主机上 Claude Code 的绝对路径。留空则从远端 PATH 解析 claude。';
	@override String get cliExecutablePathLabel => 'Claude Code CLI 路径';
	@override String get launchCredentialsMissingWarning => '该 Team 绑定的 Claude Official Provider 缺少凭据，请在 Providers 设置中登录。';
	@override String get officialCredentialsActionFailed => '凭据更新失败';
	@override String get officialCredentialsActionSuccess => '凭据已更新';
	@override String get officialCredentialsImportFile => '导入文件…';
	@override String get officialCredentialsImportGlobal => '从 ~/.claude 导入';
	@override String get officialCredentialsLogin => 'Claude 登录';
	@override String get officialCredentialsMissing => '该 Provider 尚未保存凭据';
	@override String get officialCredentialsReady => '凭据已就绪';
	@override String get officialCredentialsRevoke => '退出登录';
	@override String officialCredentialsRevokeConfirm({required String name}) => '退出登录并删除 ${name} 的已保存凭据？';
	@override String get officialCredentialsTitle => 'Claude Official 登录';
}

// Path: cli
class _AppLocalizations$cli$zh extends AppLocalizations$cli$en {
	_AppLocalizations$cli$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get config => 'CLI';

	/// Section header for AI CLI tools in CLI config page
	@override String get configAiCliGroup => 'AI CLI';

	@override String get configPageSubtitle => '配置 AI 代理 CLI 可执行文件路径，并安装缺失的工具。';

	/// Section header for toolchain tools (git, node) in CLI config page
	@override String get configToolchainGroup => '工具链';

	/// Label for Cursor CLI executable path setting
	@override String get cursorExecutablePathLabel => 'Cursor CLI 路径';

	@override String get executablePathApply => '更新';
	@override String get executablePathBrowse => '浏览…';
	@override String get executablePathDescription => 'flashskyai 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';
	@override String executablePathDescriptionFor({required String cli}) => '${cli} 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。';
	@override String get executablePathDescriptionSsh => '远程 SSH 主机上 flashskyai 的绝对路径。留空则通过 SSH 自动探测。';
	@override String executablePathDescriptionSshFor({required String cli}) => '远程 SSH 主机上 ${cli} 的绝对路径。留空则通过 SSH 自动探测。';
	@override String get executablePathLabel => 'flashskyai CLI 路径';
	@override String executablePathLabelFor({required String cli}) => '${cli} CLI 路径';
	@override String get executablePathLocate => '定位';
	@override String executablePathLocateFailed({required String name}) => '未能在 PATH 上找到 ${name}。';
	@override String get executablePathLocateRemoteUnsupported => '远程工作面不支持定位此工具。';
	@override String executablePathLocateSuccess({required String name, required String path}) => '已定位 ${name}：${path}。';
	@override String get executablePathReset => '重置';
	@override String get executablePathUsing => '当前生效：';
	@override String get executablePathUsingFallback => '使用 PATH 中查找的版本';
	@override String get installButton => '安装';
	@override String get installInstalling => '安装中…';
	@override String get installProgressBootstrappingNode => '正在安装 Node.js…';
	@override String get installProgressCheckingNpm => '正在检测 npm…';
	@override String get installProgressDownloading => '正在下载适配器…';
	@override String get installProgressExtracting => '正在解压适配器…';
	@override String get installProgressInstallingCli => '正在安装 CLI…';
	@override String get installProgressLocatingExecutable => '正在定位 CLI 可执行文件…';
	@override String get installProgressSyncingRemoteWorkspace => '正在同步远程工作区…';
	@override String get installUpgrading => '正在升级…';
	@override String get readinessAdapterMissing => '未找到适配器';
	@override String get readinessNeedsSetup => '需要安装';
	@override String get readinessReady => '就绪';
	@override String get readinessRowAcp => 'ACP';
	@override String get readinessRowCli => 'CLI';
	@override String get readinessUpdateAvailable => '有更新';
	@override String get readinessUsesCli => '使用 CLI · acp';
	@override String get readinessVersionUnknown => '—';
	@override String taskBoardCount({required int completed, required int total}) => '${completed}/${total}';
	@override String taskBoardMore({required int count}) => '… +${count} 更多';
	@override String get taskBoardShowLess => '收起';
	@override String get taskBoardTitle => '任务';
	@override String get taskStatusCancelled => '已取消';
	@override String get taskStatusCompleted => '已完成';
	@override String get taskStatusInProgress => '进行中';
	@override String get taskStatusPending => '待处理';
	@override String get taskStatusUnknown => '未知';
	@override String get transportDefaultChat => '新会话默认使用对话（ACP）';
	@override String get transportDefaultTerminal => '新会话默认使用终端（PTY）';
	@override String get upgradeButton => '升级';

	/// 远程 SSH 机器上的 ACP 代理卡片
	@override String get acpProxyTitle => '云端保活';

	@override String get acpProxySubtitle => '手机断开后，云端模型的这一轮仍会跑完。在这台机器上安装并启动。发送消息不会安装它。';
	@override String get acpProxyStart => '启动';
	@override String get acpProxyChecking => '正在检查远程机器…';
	@override String get acpProxyMissing => '未安装';
	@override String get acpProxyStopped => '已安装，未运行';
	@override String get acpProxyOutdated => '有可用更新';
	@override String get acpProxyRetry => '重试';
	@override String get acpProxyNoSsh => '安装保活前请先选择 SSH 服务器。';
}

// Path: clone
class _AppLocalizations$clone$zh extends AppLocalizations$clone$en {
	_AppLocalizations$clone$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String repositoryAddToExistingSucceeded({required Object repo, required Object workspace}) => '已将 ${repo} 加入工作区 ${workspace}';
	@override String get repositoryAddToWorkspace => '加入现有工作区…';
	@override String repositoryCancelled({required Object repo}) => '已取消克隆：${repo}';
	@override String get repositoryChooseWorkspace => '选择工作区';
	@override String repositoryCompletedBody({required Object path}) => '${path} 已就绪。';
	@override String get repositoryCompletedTitle => '克隆完成';
	@override String get repositoryCreateWorkspace => '新建工作区';
	@override String get repositoryDestExists => '文件夹已存在且不为空';
	@override String get repositoryDirNameLabel => '文件夹名称';
	@override String get repositoryDirNameRequired => '请输入文件夹名称';
	@override String repositoryFailed({required Object repo}) => '克隆失败：${repo}';
	@override String get repositoryGitMissing => '所选目标机器上未找到 git';
	@override String get repositoryMenu => '克隆仓库…';
	@override String get repositoryParentDirLabel => '克隆到文件夹';
	@override String get repositoryParentDirRequired => '请选择目标文件夹';
	@override String repositoryProgressTitle({required Object repo}) => '正在克隆 ${repo}';
	@override String repositoryStarted({required Object url}) => '已开始克隆 ${url}';
	@override String get repositorySubmit => '克隆';
	@override String repositorySucceeded({required Object repo}) => '已克隆 ${repo}';
	@override String get repositoryTargetLabel => '克隆到目标';
	@override String get repositoryTitle => '克隆仓库';
	@override String get repositoryUrlHint => 'https://github.com/owner/repo.git';
	@override String get repositoryUrlInvalid => '请输入有效的 git URL（https://、git@、git://、ssh://）';
	@override String get repositoryUrlLabel => '仓库 URL';
}

// Path: codebuddy
class _AppLocalizations$codebuddy$zh extends AppLocalizations$codebuddy$en {
	_AppLocalizations$codebuddy$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get credentialsActionFailed => 'CodeBuddy 登录失败。';
	@override String get credentialsCancel => '取消';
	@override String get credentialsDone => '完成';
	@override String get credentialsLogin => '登录';
	@override String get credentialsLoginExited => 'CodeBuddy 已退出。请关闭此对话框后重新登录。';
	@override String credentialsLoginFailed({required String error}) => '无法启动登录终端：${error}';
	@override String get credentialsLoginIntro => '在下方终端完成登录。如果出现登录方式选择，请先选择（如微信 / 企业域名）。CLI 可能会打开浏览器；如果没有打开，请手动访问它输出的链接。也可以在这里切换账号。';
	@override String get credentialsLoginStarting => '正在启动 CodeBuddy…';
	@override String get credentialsLoginTitle => '登录 CodeBuddy';
	@override String get credentialsRetry => '重试';
	@override String get credentialsSendLogin => '发送 /login';
	@override String get credentialsSignedIn => '已登录 CodeBuddy。';
}

// Path: codex
class _AppLocalizations$codex$zh extends AppLocalizations$codex$en {
	_AppLocalizations$codex$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get acpChatNotLoggedIn => 'Codex 尚未登录。请到设置 → 服务商完成 ChatGPT 登录，或改用 API Key。';
	@override String get acpLaunchFailedAdapter => '无法启动 Codex ACP 适配器（codex-acp）。请安装后重试。';
	@override String get credentialsActionFailed => '凭据更新失败';
	@override String get credentialsActionSuccess => '凭据已更新';
	@override String get credentialsImportFile => '导入 auth.json…';
	@override String get credentialsImportGlobal => '从 ~/.codex 导入';
	@override String get credentialsLogin => 'OpenAI 登录';
	@override String get credentialsRevoke => '退出登录';
	@override String credentialsRevokeConfirm({required String name}) => '退出登录并删除 ${name} 的已保存凭据？';
}

// Path: compose
class _AppLocalizations$compose$zh extends AppLocalizations$compose$en {
	_AppLocalizations$compose$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get cascadeCustomModelId => '自定义模型 ID…';
	@override String get cascadeCustomModelIdTitle => '自定义模型 ID';
	@override String get cascadeDefaultEffort => '默认';
	@override String get cascadeNoModels => '暂无模型目录';
	@override String get cascadeNoProviders => '尚未配置任何服务商';
	@override String get cascadePresets => '预设';
	@override String get cascadeSavePreset => '保存当前为预设…';
	@override String get commandExperimental => '实验性';
	@override String get commandNative => '原生命令';
	@override String get commandPlugin => '插件';
	@override String get nativeCommandCompact => '压缩当前对话上下文。';
	@override String get nativeCommandGoal => '为长时间运行的工作保留持久目标。';
	@override String get nativeCommandHelp => '显示此 CLI 会话中可用的命令。';
	@override String get nativeCommandPlan => '将会话切换到规划工作流。';
	@override String get pasteClipEdit => '编辑已粘贴文本';
	@override String get pasteClipLabel => '粘贴文本';
	@override String pasteClipLines({required int lines}) => '${lines} 行';
	@override String get pasteClipRemove => '移除已粘贴文本';
	@override String get pasteEditorDone => '完成';
	@override String get pasteEditorRemove => '移除';
	@override String pasteEditorTitle({required int lines}) => '编辑已粘贴文本 · ${lines} 行';
}

// Path: connect
class _AppLocalizations$connect$zh extends AppLocalizations$connect$en {
	_AppLocalizations$connect$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get addEndpoint => '添加地址';
	@override String get advancedSubtitle => '添加可从当前局域网外访问的 SSH 地址。';
	@override String get advancedTitle => '可达地址';
	@override String get androidScanHint => '扫描桌面版 TeamPilot 显示的二维码。';
	@override String get copyLink => '复制链接';
	@override String get error => '无法刷新配对信息，请重试。';
	@override String get extraHost => '主机';
	@override String get extraPort => '端口';
	@override String get interfaceLabel => '网络接口';
	@override String get invalidEndpoint => '每个地址都需要主机名和 1 至 65535 的端口。';
	@override String get lanOnlyStatus => '仅局域网';
	@override String get needLanOrRelay => '请连同一 Wi-Fi，或先在桌面填写中继地址。';
	@override String get noNetworkAddress => '没有可用的非回环 IPv4 网络接口。';
	@override String get noPairedDevices => '尚未配对手机。';
	@override String get openSettings => '去设置';
	@override String get pairCodeHint => 'teampilot://pair-ssh?code=…';
	@override String get pairExpired => '配对码已过期，请重新扫描。';
	@override String get pairFailed => '无法与此电脑配对，请重试。';
	@override String get pairInvalid => '此配对码无效。';
	@override String get pairNow => '配对';
	@override String get pairSheetSubtitle => '扫描桌面版 TeamPilot 显示的二维码，或粘贴配对码。';
	@override String get pairSheetTitle => '与电脑配对';
	@override String get pairUpdateApp => '请更新 TeamPilot 后再扫描此配对码。';
	@override String get pairedDevicesTitle => '已配对设备';
	@override String get pairing => '正在配对…';
	@override String get pasteCode => '粘贴配对码';
	@override String get qrEnlargeHint => '点击二维码可放大后再扫。';
	@override String get regenerate => '重新生成';
	@override String get relayUrl => '中继 URL';
	@override String get relayUrlHint => '可选的中继服务 URL';
	@override String get remoteReadyStatus => '局域网和远程';
	@override String get removeEndpoint => '移除地址';
	@override String get repairHint => '桌面端已升级——请重新扫码配对以恢复连接。';
	@override String get revokeDevice => '撤销';
	@override String get revokeSystemHint => '新登录会被拒绝。已经建立的 OpenSSH 会话可能要等断开后才会失效。';
	@override String get saveSettings => '保存可达地址';
	@override String get scanHint => '在手机上的 TeamPilot 中扫描此码。';
	@override String get scanQr => '扫描二维码';
	@override String get scannerHint => '距离桌面二维码 10–30 cm；双指捏合可缩放，光线不足时打开手电筒。';
	@override String get scannerPermissionDenied => '需要相机权限才能扫描二维码。';
	@override String get scannerUnavailable => '相机扫描器不可用，请改为粘贴配对码。';
	@override String get settingsSubtitle => '扫码用 SSH 连接这台电脑';
	@override String get settingsTitle => '手机';
	@override String get sshBackendEmbedded => '内置';
	@override String get sshBackendHelp => '用本机 OpenSSH 对比内置服务器。切换后需重新扫码配对。';
	@override String get sshBackendLabel => 'SSH 服务器';
	@override String get sshBackendRePair => '已配对的手机需重新扫描此电脑的配对码。';
	@override String get sshBackendSystem => '系统 OpenSSH (22)';
	@override String get sshdDown => '内嵌连接服务启动失败。请重试或重启应用。';
	@override String get sshdRetry => '重试';
	@override String get systemSshdDownLinux => '22 端口没有 SSH 服务在听。请启动 OpenSSH 的 sshd，然后重试。';
	@override String get systemSshdDownMacos => '22 端口没有 SSH 服务在听。请在「共享」中打开远程登录，然后重试。';
}

// Path: cursor
class _AppLocalizations$cursor$zh extends AppLocalizations$cursor$en {
	_AppLocalizations$cursor$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get accountUsageSession => 'Cursor 账号';
	@override String get credentialsActionFailed => '凭据更新失败';
	@override String get credentialsActionSuccess => '凭据已更新';
	@override String get credentialsImportFile => '导入目录…';
	@override String get credentialsImportGlobal => '从 ~/.cursor 导入';
	@override String get credentialsLogin => 'Cursor 登录';
	@override String get credentialsRevoke => '退出登录';
	@override String credentialsRevokeConfirm({required String name}) => '退出登录并删除 ${name} 的已保存凭据？';
}

// Path: delete
class _AppLocalizations$delete$zh extends AppLocalizations$delete$en {
	_AppLocalizations$delete$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get delete => '删除';
	@override String get conversation => '删除对话';
	@override String conversationConfirm({required String name}) => '删除对话 "${name}"？此操作不可撤销。';
	@override String get provider => '删除提供商';
	@override String providerConfirm({required String name}) => '删除提供商 ${name}？';
	@override String get providerTooltip => '删除提供商';
	@override String providerWithCredentialsConfirm({required String name}) => '删除提供商 ${name}？将同时删除该 Provider 已保存的 Claude 登录凭据。';
	@override String get team => '删除团队';
	@override String teamConfirm({required String name}) => '删除团队 "${name}"？此操作不可撤销。';
	@override String get teamSubtitle => '从 UI 和共享的 flashskyai 数据目录中移除该团队。此操作不可撤销。';
	@override String get workspace => '删除工作区';
	@override String workspaceConfirm({required String name}) => '删除工作区 "${name}" 及其所有会话？此操作不可撤销。';
	@override String get workspaceSubtitle => '将删除该工作区及其下所有会话，且无法恢复。';
}

// Path: diff
class _AppLocalizations$diff$zh extends AppLocalizations$diff$en {
	_AppLocalizations$diff$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get applyDisabledNoPath => '无法应用：文件路径不可用';
	@override String applyFailed({required String error}) => '无法应用更改：${error}';
	@override String get applyHunkTooltip => '应用到工作区';
	@override String changeCounter({required int current, required int total}) => '${current} / ${total}';
	@override String get discardDiffBeforeFileSaveBody => '保存文件将丢弃 diff 视图中未保存的编辑。';
	@override String get discardDiffBeforeFileSaveTitle => '丢弃 diff 编辑？';
	@override String get discardEditsApplyBody => '应用此更改将丢弃 diff 中未保存的编辑。';
	@override String get discardEditsApplyTitle => '丢弃编辑？';
	@override String get fileReloadedAfterDiffWrite => '已从磁盘重新加载文件页。';
	@override String get ignoreWhitespace => '忽略空白';
	@override String get nextChange => '下一处更改';
	@override String get noChanges => '没有更改';
	@override String get openSourceFile => '打开源文件';
	@override String get previousChange => '上一处更改';
	@override String get reloadAfterSaveFailed => '已保存，但刷新 diff 失败。';
	@override String saveFailed({required String error}) => '无法保存：${error}';
	@override String get showAllLines => '显示全部';
	@override String get viewSideBySide => '并排';
	@override String get viewUnified => '统一';
}

// Path: download
class _AppLocalizations$download$zh extends AppLocalizations$download$en {
	_AppLocalizations$download$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get sourcesEnabledSources => '已启用源';
	@override String get sourcesIdentity => '直连（官方）';
	@override String get sourcesMirrorBaseUrl => '镜像基础 URL';
	@override String get sourcesMirrorHint => 'https://mirror.example';
	@override String get sourcesRestoreDefaults => '恢复默认';
	@override String get sourcesSave => '保存';
	@override String get sourcesSettingsSubtitle => '配置 GitHub 下载镜像（应用更新、Termux APK）';
	@override String get sourcesSettingsTitle => '下载源';
}

// Path: edit
class _AppLocalizations$edit$zh extends AppLocalizations$edit$en {
	_AppLocalizations$edit$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get cancel => '取消';
	@override String get edit => '编辑';
	@override String get memberSubtitle => '编辑提供商、模型、可选 Agent 预设与命令参数。';
	@override String modelTitle({required String name}) => '编辑 ${name}';
	@override String get provider => '编辑服务商';
	@override String get retry => '重试';
	@override String get send => '发送';
	@override String get teamSubtitle => '编辑团队标识、工作目录和启动顺序。';
	@override String get userMessage => '编辑消息';
	@override String get workspacePrimaryPath => '编辑主目录';
}

// Path: editor
class _AppLocalizations$editor$zh extends AppLocalizations$editor$en {
	_AppLocalizations$editor$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get binaryFileHint => '二进制文件将使用系统默认应用打开。';
	@override String get close => '关闭编辑器';
	@override String get copy => '复制';
	@override String get copyAsAiContext => '复制为 AI 上下文';
	@override String get couldNotReadFile => '无法读取文件';
	@override String get cut => '剪切';
	@override String get discard => '放弃';
	@override String get fileNotFound => '找不到文件';
	@override String get fileReadOnly => '文件为只读';
	@override String get fileTooLarge => '文件过大，无法在 TeamPilot 中编辑（上限 2 MB）。';
	@override String get findClose => '关闭';
	@override String get findHint => '查找';
	@override String get findInSelection => '在选定内容中查找';
	@override String get findInvalidRegex => '正则表达式无效';
	@override String get findMatchCase => '区分大小写';
	@override String get findNext => '下一个匹配';
	@override String get findNoResults => '无匹配';
	@override String get findPrevious => '上一个匹配';
	@override String get findReplaceAll => '全部替换';
	@override String get findReplaceHint => '替换';
	@override String get findReplaceOne => '替换';
	@override String get findReplacePreserveCase => '保留大小写';
	@override String get findToggleReplace => '切换替换';
	@override String get findUseRegex => '使用正则表达式';
	@override String get findWholeWord => '全字匹配';
	@override String get imageDecodeFailed => '无法解码此图片。';
	@override String get imageTooLarge => '图片过大，无法在 TeamPilot 中预览（上限 25 MB）。';
	@override String get noFileOpen => '未打开文件';
	@override String get notReady => '编辑器未就绪';
	@override String get paste => '粘贴';
	@override String get redoEdit => '重做';
	@override String get revertChanges => '撤销修改';
	@override String get save => '保存';
	@override String saveFailed({required String error}) => '保存失败：${error}';
	@override String get selectAll => '全选';
	@override String get title => '编辑器';
	@override String get undoEdit => '撤销';
	@override String unsavedChangesDiscardFile({required String fileName}) => '放弃对「${fileName}」的未保存修改？';
	@override String unsavedChangesDiscardMultiple({required int count}) => '放弃 ${count} 个文件中的未保存修改？';
	@override String get unsavedChangesTitle => '未保存的更改';
}

// Path: exit
class _AppLocalizations$exit$zh extends AppLocalizations$exit$en {
	_AppLocalizations$exit$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get planModeApprove => '批准';
	@override String get planModeApproveFailed => '批准计划失败';
	@override String get planModeCopyPlan => '复制计划';
	@override String get planModeOpenPlanFile => '打开计划文件';
	@override String get planModePreviewTitle => '计划预览';
	@override String get planModeReject => '拒绝';
	@override String get planModeRejectFailed => '拒绝计划失败';
	@override String get planModeTitle => '计划已就绪，等待批准';
	@override String get planModeViewPlan => '查看计划';
}

// Path: expert
class _AppLocalizations$expert$zh extends AppLocalizations$expert$en {
	_AppLocalizations$expert$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get editorCategory => '分类';
	@override String get editorConfigureMcpTitle => '配置 MCP';
	@override String get editorConfigurePluginsTitle => '配置插件';
	@override String get editorConfigureSkillsTitle => '配置技能';
	@override String get editorCreateTitle => '新建专家';
	@override String get editorDepPickerDone => '完成';
	@override String get editorDepsHint => '从本机已安装库中配置依赖。没有可移植来源的项会在保存时跳过。';
	@override String get editorDescription => '描述';
	@override String get editorEditTitle => '编辑专家';
	@override String get editorMcpSection => 'MCP';
	@override String get editorNameRequired => '名称为必填项。';
	@override String editorNonPortableSkipped({required int count}) => '已跳过 ${count} 个没有可移植来源的本地项。';
	@override String get editorOrphanDeps => '已挂载（本机未安装）';
	@override String get editorOrphanRemove => '移除';
	@override String get editorPlaybookHint => '可选。该专家应遵循的工作步骤与规范。';
	@override String get editorPluginsSection => '插件';
	@override String get editorPromptHint => '描述该专家的职责与工作范围。';
	@override String get editorPromptRequired => '职责为必填项。';
	@override String get editorSkillsSection => '技能';
	@override String get editorTags => '标签';
	@override String get editorTagsHint => '逗号分隔';
	@override String get hubAddFailed => '无法添加该成员。';
	@override String get hubAddFromHub => '从专家中心添加';
	@override String hubAddPartial({required Object name, required int skillCount, required int failedCount, required Object failedNames}) => '已添加「${name}」。安装了 ${skillCount} 个技能。${failedCount} 个无法安装：${failedNames}。';
	@override String hubAddSuccess({required Object name}) => '已将「${name}」添加到团队。';
	@override String hubAddSuccessWithSkills({required Object name, required int skillCount}) => '已添加「${name}」。安装了 ${skillCount} 个技能。';
	@override String get hubAddToTeam => '添加到团队';
	@override String get hubAdding => '添加中…';
	@override String get hubBrowseAll => '浏览全部专家';
	@override String get hubCapabilities => '能力';
	@override String get hubCardNoDescription => '无';
	@override String get hubCategoryAll => '全部';
	@override String get hubConfirmSelection => '确认';
	@override String get hubCreate => '新建';
	@override String get hubEmptyHint => '刷新以从注册表获取专家。';
	@override String get hubEmptyTitle => '暂无专家';
	@override String get hubFavorites => '收藏';
	@override String get hubFavoritesEmptyHint => '点击专家卡片上的星标即可收藏。';
	@override String get hubFavoritesEmptyTitle => '暂无收藏';
	@override String get hubFromTeams => '来自团队';
	@override String get hubIgnoredInTeamMode => '专家仅在简单模式下可用。请切换到简单模式以召唤专家。';
	@override String get hubLaunchInWorkspace => '在工作区启动';
	@override String get hubLoadError => '无法加载专家。';
	@override String get hubMyTemplates => '我的模板';
	@override String get hubNav => '专家中心';
	@override String get hubNoneSelected => '未选择专家';
	@override String get hubNotFound => '未找到该专家。';
	@override String get hubPlaybook => '工作手册';
	@override String hubPreflightPartial({required Object name, required int failedCount, required Object failedNames}) => '已选择「${name}」。${failedCount} 个能力无法安装：${failedNames}。';
	@override String get hubPrompt => '职责';
	@override String get hubRecent => '最近使用';
	@override String get hubRefresh => '刷新';
	@override String get hubSearchHint => '搜索专家';
	@override String get hubSortName => '名称';
	@override String get hubSortUpdated => '最近更新';
	@override String get hubSourceBuiltin => '内置';
	@override String get hubSourceClone => '克隆';
	@override String get hubSourceLocal => '我的模板';
	@override String get hubSourceRegistry => '注册表';
	@override String get hubSourceTeamExtract => '来自团队';
	@override String get hubSubtitle => '发现成员角色与模板';
	@override String get hubTitle => '专家中心';
	@override String get hubViewInHub => '在专家中心查看';
	@override String get hubViewOriginTeam => '查看来源团队';
}

// Path: extension
class _AppLocalizations$extension$zh extends AppLocalizations$extension$en {
	_AppLocalizations$extension$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get commandCopied => '命令已复制到剪贴板';
	@override String get copyCommand => '复制';
	@override String dependencyMissingHint({required String deps}) => '需要 PATH 中有 ${deps}。安装后点击重新检测。';
	@override String get enableLabel => '已启用';
	@override String get install => '安装';
	@override String get installGuide => '安装指引';
	@override String get kindMcpServer => '代码智能（MCP）';
	@override String get kindSettingsHook => 'Token 节省（hook）';
	@override String get recheck => '重新检测';
	@override String get statusDependencyMissing => '缺少依赖';
	@override String statusDependencyMissingNamed({required String deps}) => '缺少：${deps}';
	@override String get statusNotInstalled => '未安装';
	@override String get statusReady => '就绪';
	@override String statusReadyVersion({required String version}) => '就绪（${version}）';
	@override String get statusVersionTooOld => '已安装版本过旧';
	@override String get uninstall => '卸载';
}

// Path: file
class _AppLocalizations$file$zh extends AppLocalizations$file$en {
	_AppLocalizations$file$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get codeBlockModeDescription => 'markdown 文件预览中超大代码块的呈现方式。';
	@override String get codeBlockModeTitle => '文件预览·代码块';
	@override String get diffToggleDiff => 'Diff';
	@override String get diffToggleFile => '文件';
	@override String get previewHostCenter => '中间';
	@override String get previewHostDescription => '在浮动工作区或中间工作台打开文件。';
	@override String get previewHostFloating => '浮动';
	@override String get previewHostTitle => '文件预览位置';
}

// Path: fileTree
class _AppLocalizations$fileTree$zh extends AppLocalizations$fileTree$en {
	_AppLocalizations$fileTree$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get fileTree => '文件树';
	@override String get copy => '复制';
	@override String get copyPath => '复制路径';
	@override String get copyRelativePath => '复制相对路径';
	@override String get createNameHint => '名称';
	@override String get cut => '剪切';
	@override String get deleteDone => '已删除';
	@override String deleteItemConfirm({required String name}) => '删除「${name}」？';
	@override String get deleteItemTitle => '删除';
	@override String get fileCreated => '已创建文件';
	@override String get folderCreated => '已创建文件夹';
	@override String get hideFilter => '隐藏筛选';
	@override String get importApplyRemaining => '应用于剩余冲突';
	@override String get importCancelAll => '全部取消';
	@override String importConflictBody({required String name}) => '目标位置已存在「${name}」。';
	@override String importConflictRemaining({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '之后还有 ${count} 个冲突。',
	);
	@override String get importConflictRemainingZero => '没有更多冲突。';
	@override String get importConflictTitle => '项目已存在';
	@override String get importConflictTypeMismatch => '文件和文件夹不能互相替换。';
	@override String get importDropCopy => '复制';
	@override String get importDropMove => '移动';
	@override String get importOverwrite => '覆盖';
	@override String get importProgressCancel => '取消';
	@override String importProgressCurrent({required String name}) => '${name}';
	@override String importProgressItems({required int completed, required int total}) => '${completed} / ${total}';
	@override String get importProgressTitle => '正在导入…';
	@override String get importRejectSelf => '无法将项目移动到自身或其子目录中。';
	@override String get importSkip => '跳过';
	@override String importSummary({required int succeeded, required int skipped, required int failed}) => '成功 ${succeeded}，跳过 ${skipped}，失败 ${failed}';
	@override String get importSummaryCancelledSuffix => ' — 已取消';
	@override String get invalidName => '名称无效';
	@override String get invalidPasteTarget => '无法粘贴到此处';
	@override String get itemExists => '同名项目已存在';
	@override String get newFile => '新建文件';
	@override String get newFolder => '新建文件夹';
	@override String get openInFileManager => '在文件管理器中打开';
	@override String get openInTerminal => '在终端中打开';
	@override String get openInTerminalFailed => '无法打开终端';
	@override String get openWithSystemApp => '用系统应用打开';
	@override String get paste => '粘贴';
	@override String get pasteDone => '已粘贴';
	@override String get refresh => '刷新';
	@override String get rename => '重命名';
	@override String get renameDone => '已重命名';
	@override String get renameTitle => '重命名';
	@override String get revealActiveFile => '定位当前文件';
	@override String get revealFailed => '无法在文件树中定位该文件';
	@override String get showFilter => '显示筛选';
	@override String get sourceMissing => '源文件不存在';
}

// Path: floating
class _AppLocalizations$floating$zh extends AppLocalizations$floating$en {
	_AppLocalizations$floating$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get previewTabsDescription => '文件与 diff 预览在浮动面板中共享一个可替换的标签页，固定后保留。';
	@override String get previewTabsTitle => '单个预览标签页';
	@override String get restoreTerminalSessionsDescription => '重启后保留浮动终端标签，首次打开该标签时才重新连接。';
	@override String get restoreTerminalSessionsTitle => '恢复终端标签';
	@override String get workspaceAddTooltip => '在浮动工作区打开';
	@override String get workspaceCloseTab => '关闭标签';
	@override String get workspaceMaximize => '最大化';
	@override String get workspaceMinimize => '最小化';
	@override String get workspaceNewTerminal => '新 Terminal';
	@override String get workspaceOpenFile => '打开文件';
	@override String get workspaceToggleTooltip => '浮动工作区';
}

// Path: font
class _AppLocalizations$font$zh extends AppLocalizations$font$en {
	_AppLocalizations$font$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get changeAppliesOnRestart => '字体已保存，重启 TeamPilot 后生效。';
	@override String get installedSection => '已安装';
	@override String get monoDescription => '终端、编辑器与 diff。重启后生效。';
	@override String get monoTitle => '等宽字体';
	@override String get optionJetbrainsMono => 'JetBrains Mono';
	@override String get optionNotoSansSc => 'Noto Sans SC';
	@override String get optionSystem => '系统';
	@override String get optionUbuntuSansMono => 'Ubuntu Sans Mono';
	@override String get searchHint => '搜索字体';
	@override String get uiDescription => '界面文字。系统跟随操作系统默认字体。重启后生效。';
	@override String get uiTitle => '界面字体';
}

// Path: git
class _AppLocalizations$git$zh extends AppLocalizations$git$en {
	_AppLocalizations$git$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String aheadBehind({required int ahead, required int behind}) => '↑${ahead} ↓${behind}';
	@override String get amend => '修正';
	@override String get amendCommit => '修改提交';
	@override String get amendConfirmMessage => '这将改写最后一次提交。如果该提交已推送到远程，之后需要强制推送。';
	@override String get amendConfirmTitle => '修改上一次提交？';
	@override String get autoFetchDescription => '定时对源代码管理面板当前显示的仓库执行非交互的 git fetch --all --prune，保持提交/拉取计数最新。';
	@override String get autoFetchIntervalDescription => '面板打开时对选中仓库执行 fetch 的频率。';
	@override String autoFetchIntervalMinutesOption({required int minutes}) => '每 ${minutes} 分钟';
	@override String get autoFetchIntervalTitle => '自动拉取间隔（分钟）';
	@override String get autoFetchTitle => '自动拉取远程更新';
	@override String get changes => '要提交的变更';
	@override String get changesListView => '列表视图';
	@override String get changesTreeView => '树形视图';
	@override String get commit => '提交';
	@override String commitMessageHint({required String branch}) => '消息（提交到 "${branch}"）';
	@override String get committing => '正在提交…';
	@override String get compareEmpty => '没有差异';
	@override String get compareLoadError => '无法加载差异';
	@override String compareSubtitle({required String ref}) => '${ref} 与当前工作区的差异';
	@override String get compareWorkingTree => '工作区';
	@override String get copyPath => '复制路径';
	@override String get createBranch => '新建分支';
	@override String get discard => '放弃更改';
	@override String get discardAllConfirmBody => '放弃工作区中的所有未暂存更改？此操作无法撤销。';
	@override String get discardAllConfirmTitle => '放弃所有更改？';
	@override String get discardAllUnstaged => '放弃全部未暂存更改';
	@override String discardConfirmBody({required String path}) => '放弃 ${path} 中的所有更改？此操作无法撤销。';
	@override String get discardConfirmTitle => '放弃更改？';
	@override String get discardFolder => '放弃文件夹中的更改';
	@override String discardFolderConfirmBody({required String path}) => '放弃 ${path} 中的所有更改？此操作无法撤销。';
	@override String get discardFolderConfirmTitle => '放弃文件夹更改？';
	@override String get discardSelected => '放弃所选更改';
	@override String error({required String message}) => 'Git：${message}';

	/// Context-menu action to exclude a folder and its changed files from the next commit.
	@override String get excludeFolderFromCommit => '从本次提交排除文件夹';

	/// Context-menu action to exclude a file from the next commit.
	@override String get excludeFromCommit => '排除出本次提交';

	@override String get fetch => '从远端获取';
	@override String get fetchDone => '已获取远端更新';
	@override String get fetching => '正在获取远端更新…';
	@override String get generateCommitMessage => '用 AI 生成提交信息';
	@override String get generateCommitMessageNoProvider => '请先在 设置 → AI 功能 中配置 AI provider。';
	@override String get generatingCommitMessage => '正在生成提交信息…';

	/// Context-menu action to include a folder and its changed files in the next commit.
	@override String get includeFolderInCommit => '纳入文件夹到本次提交';

	/// Context-menu action to include a file in the next commit.
	@override String get includeInCommit => '纳入本次提交';

	@override String get initializeRepository => '创建 Git 仓库';
	@override String get newBranchHint => '新分支名称';
	@override String get noChanges => '没有更改';
	@override String get notARepository => '当前文件夹不是 Git 仓库';
	@override String get notInstalled => '未找到 Git。安装 Git 后即可使用源代码管理。';
	@override String get openFile => '打开文件';
	@override String get pull => '拉取';
	@override String get pullDone => '拉取完成';
	@override String get pulling => '正在拉取…';
	@override String get push => '推送';
	@override String get pushDone => '推送完成';
	@override String get pushing => '正在推送…';
	@override String get refresh => '刷新';
	@override String get refreshing => '正在刷新…';
	@override String get showDiff => '显示差异';
	@override String get stagedChanges => '暂存的更改';
	@override String get switchBranch => '切换分支';
	@override String get unversionedFiles => '未暂存的文件';
}

// Path: gitGraph
class _AppLocalizations$gitGraph$zh extends AppLocalizations$gitGraph$en {
	_AppLocalizations$gitGraph$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get allBranches => '所有分支';
	@override String get branchNameLabel => '分支名称';
	@override String get branchesTags => '分支与标签';
	@override String checkoutBranch({required String branch}) => '检出 ${branch}';
	@override String get checkoutCommit => '检出该提交（分离 HEAD）';
	@override String checkoutCommitConfirmBody({required String hash}) => '以分离 HEAD 状态检出 ${hash} 吗？';
	@override String get cherryPick => '摘取（Cherry-pick）';
	@override String get columnAuthor => '作者';
	@override String get columnCommit => '提交';
	@override String get columnDate => '日期';
	@override String get columnDescription => '说明';
	@override String get columnGraph => '图';
	@override String get columnHeaderLabel => '列头';
	@override String get columns => '列';
	@override String get commits => '提交';
	@override String get compareFilterHint => '过滤分支、标签与提交';
	@override String get compareWith => '与…比较';
	@override String compareWorkingTree({required String branch}) => '工作区（${branch}）';
	@override String get conflictHint => '请先解决冲突并暂存相关文件，然后提交以继续。';
	@override String get copyHash => '复制哈希';
	@override String get copySubject => '复制说明';
	@override String get create => '创建';
	@override String get createBranchHere => '在此创建分支';
	@override String get createBranchTitle => '创建分支';
	@override String get createTagHere => '在此创建标签';
	@override String get createTagTitle => '创建标签';
	@override String get currentBranch => '当前分支';
	@override String deleteBranch({required String name}) => '删除分支 ${name}';
	@override String deleteBranchConfirmBody({required String name}) => '确定删除分支“${name}”吗？仅能从该分支到达的提交可能变得不可达，此操作无法撤销。';
	@override String get deleteBranchTitle => '删除分支';
	@override String deleteRemoteBranchConfirmBody({required String name}) => '确定删除共享仓库上的远程分支“${name}”吗？这将影响所有协作者，且无法撤销。';
	@override String get deleteRemoteBranchTitle => '删除远程分支';
	@override String deleteTag({required String name}) => '删除标签 ${name}';
	@override String deleteTagConfirmBody({required String name}) => '确定删除标签“${name}”吗？此操作无法撤销。';
	@override String get deleteTagTitle => '删除标签';
	@override String get fetch => '抓取';
	@override String get hashCopied => '哈希已复制到剪贴板';
	@override String get hashSearchEmptyHint => '已加载的提交中没有匹配该哈希的记录，请继续向下滚动或点击“加载更多”以载入更早的历史。';
	@override String hideColumn({required String column}) => '隐藏${column}';
	@override String get hideColumnHeader => '隐藏列头';
	@override String get loadMore => '加载更多';
	@override String get loadingMore => '加载中…';
	@override String get localBranches => '本地分支';
	@override String mergeIntoCurrent({required String branch}) => '合并 ${branch} 到当前分支';
	@override String get noCommits => '未找到提交';
	@override String get notARepository => '不是 Git 仓库';
	@override String get pull => '拉取';
	@override String get push => '推送';
	@override String pushTag({required String name}) => '推送标签 ${name}';
	@override String get refresh => '刷新';
	@override String get refsFilterEmpty => '无匹配项';
	@override String get refsFilterHint => '过滤分支与标签';
	@override String get remoteBranches => '远程分支';
	@override String get renameBranch => '重命名分支…';
	@override String get renameBranchTitle => '重命名分支';
	@override String get reset => '重置（Reset）';
	@override String get resetHard => '硬重置（Hard）';
	@override String resetHardConfirmBody({required String branch}) => '硬重置会把“${branch}”移动到此提交，并丢弃所有未提交的更改。输入“${branch}”以确认。';
	@override String get resetMixed => '混合重置（Mixed）';
	@override String get resetSoft => '软重置（Soft）';
	@override String get revert => '回退（Revert）';
	@override String revertConfirmBody({required String hash}) => '确定回退提交 ${hash} 吗？将创建一个撤销该提交的新提交。';
	@override String get searchHint => '搜索提交（消息 / 作者 / 哈希）';
	@override String get searchModeAuthor => '作者';
	@override String get searchModeHash => '哈希';
	@override String get searchModeMessage => '消息';
	@override String get selectCommit => '选择一个提交查看详情';
	@override String get showColumnHeader => '显示列头';
	@override String get stash => '贮藏';
	@override String get stashApply => '应用';
	@override String get stashDrop => '丢弃';
	@override String stashDropConfirmBody({required String selector}) => '确定丢弃 ${selector} 吗？此操作无法撤销。';
	@override String get stashPop => '弹出';
	@override String get subjectCopied => '说明已复制到剪贴板';
	@override String get tagMessageLabel => '说明（可选）';
	@override String get tagNameLabel => '标签名称';
	@override String get tags => '标签';
	@override String get title => '提交图';
	@override String get uncommittedChanges => '未提交的更改';
	@override String get viewBranchHistory => '查看此分支历史';
	@override String get viewTagHistory => '查看此标签历史';
}

// Path: github
class _AppLocalizations$github$zh extends AppLocalizations$github$en {
	_AppLocalizations$github$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get advancedPat => '使用个人访问令牌';
	@override String get advancedPatSubtitle => '无法使用 GitHub 登录时，或你更想用带 repo 权限的令牌时。';
	@override String get authDenied => '已取消 GitHub 授权';
	@override String get authExpired => 'GitHub 登录已失效';
	@override String get authExpiredRetry => '授权已过期，请重试。';
	@override String get browserOpened => '已打开浏览器进行授权';
	@override String connectedAs({required Object login}) => '已连接为 @${login}';
	@override String get connectedGeneric => '已连接到 GitHub';
	@override String get deviceFlowUnavailable => '此构建暂不支持 GitHub 登录。请使用个人访问令牌。';
	@override String get disconnect => '断开连接';
	@override String get networkError => '无法连接 GitHub，请重试。';
	@override String get reopenBrowser => '重新打开浏览器';
	@override String get settingsSubtitle => '连接 GitHub，以便将专家和团队发布到 Hub';
	@override String get settingsTitle => 'GitHub';
	@override String get signIn => '使用 GitHub 登录';
	@override String get switchAccount => '切换账号';
	@override String get waitingCodeHint => '如有提示，请在 GitHub 上输入此验证码';
}

// Path: grok
class _AppLocalizations$grok$zh extends AppLocalizations$grok$en {
	_AppLocalizations$grok$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get credentialsActionFailed => 'Grok 操作失败';
	@override String get credentialsCancel => '取消';
	@override String get credentialsDone => '完成';
	@override String get credentialsLogin => '登录';
	@override String get credentialsLoginExited => 'Grok CLI 已退出。请关闭此对话框后重新登录。';
	@override String credentialsLoginFailed({required String error}) => '无法启动登录终端：${error}';
	@override String get credentialsLoginIntro => '在下方终端完成设备登录。Grok 会显示验证码并打开浏览器；如果没有打开，请手动访问它输出的链接。也可以在这里切换账号。';
	@override String get credentialsLoginStarting => '正在启动 Grok CLI…';
	@override String get credentialsLoginTitle => '登录 Grok';
	@override String get credentialsRelaunch => '重新启动';
	@override String get credentialsSignedIn => '已登录';
	@override String get credentialsImportGlobal => '导入已有登录';
}

// Path: home
class _AppLocalizations$home$zh extends AppLocalizations$home$en {
	_AppLocalizations$home$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get connectionCancelRetry => '取消重试';
	@override String get connectionErrorAuth => '认证失败';
	@override String get connectionErrorHostKey => '主机身份已变更 — 请重新配对或确认新密钥';
	@override String get connectionErrorTcp => '网络不可达';
	@override String get connectionErrorTimeout => '连接超时';
	@override String get connectionErrorTransport => '连接出错';
	@override String get connectionErrorUnknown => '未知错误';
	@override String get connectionRetryNow => '继续重试';
	@override String connectionRetrying({required int count}) => '正在重试…第 ${count} 次';
	@override String get connectionSwitch => '切换连接';
	@override String connectionUnreachable({required String host, required int port}) => '无法连接 ${host}:${port}';
	@override String get targetSingleOptionHint => '当前平台只有这一个可用的主设备。';
	@override String get targetSubtitle => 'TeamPilot 存放团队、工作区与配置的位置（控制面）。切换会使用独立的数据目录，不会自动迁移。';
	@override String get targetTitle => '主设备';
}

// Path: homeWorkspace
class _AppLocalizations$homeWorkspace$zh extends AppLocalizations$homeWorkspace$en {
	_AppLocalizations$homeWorkspace$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get allWorkspaces => '全部工作区';
	@override String get cloneWorkspace => '克隆工作区';
	@override String cloneWorkspaceDisplayName({required Object name}) => '${name}（副本）';
	@override String get cloneWorkspaceFailed => '无法克隆工作区';
	@override String cloneWorkspaceSuccess({required Object name}) => '已克隆「${name}」。';
	@override String closeAllTabsMessage({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		one: '关闭全部标签会终止 1 个运行中的会话。',
		other: '关闭全部标签会终止 ${count} 个运行中的会话。',
	);
	@override String get closeAllTabsTitle => '关闭全部标签？';
	@override String get closeWorkspaceConfirm => '关闭并终止会话';
	@override String closeWorkspaceMessage({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		one: '关闭该标签会终止此工作区中 1 个运行中的会话。',
		other: '关闭该标签会终止此工作区中 ${count} 个运行中的会话。',
	);
	@override String get closeWorkspaceTitle => '关闭工作区？';
	@override String get comingSoon => '功能开发中';
	@override String get conversations => '对话管理';
	@override String get conversationsSection => '对话';
	@override String get createTeam => '创建团队';
	@override String get createWorkspace => '创建工作区';

	/// Name shown for the built-in default mixed team created on first launch.
	@override String get defaultMixedTeamName => '默认混合团队';

	/// Name shown for the built-in default native team created on first launch.
	@override String get defaultNativeTeamName => '默认原生团队';

	/// Name shown for the built-in personal workspace in simple mode.
	@override String get defaultPersonalWorkspaceName => '个人助手';

	@override String get emptyWorkspaces => '该团队还没有工作区';
	@override String get emptyWorkspacesHint => '新建或导入一个工作区开始吧';
	@override String get favoriteWorkspace => '收藏工作区';
	@override String get importWorkspace => '导入工作区';
	@override String get inviteMembers => '邀请成员';
	@override String get launchWorkspaceTitle => '选择启动方式';
	@override String get mainWindow => '主窗口';
	@override String get myFavorites => '我的收藏';
	@override String get newConversation => '新建对话';
	@override String get newConversationChooseCli => '选择 CLI 新建对话';
	@override String get newTeam => '新建团队';
	@override String get newTeamMethodAi => 'AI 生成';
	@override String get newTeamMethodCustom => '自定义模式';
	@override String get newTeamModeBeta => 'Beta';
	@override String get newTeamNameHint => '请输入团队名称';
	@override String get newTeamRecommended => '推荐';
	@override String get newTeamSubtitle => '选择团队协作模式，并填写团队名称。';
	@override String get newTeamSubtitleAi => '描述团队需求，用 AI 生成团队配置草稿。';
	@override String get newWorkspaceChooseDirectory => '选择文件夹';
	@override String get newWorkspaceDirectoryHint => '尚未选择目录';
	@override String get newWorkspaceDirectoryLabel => '工作区目录';
	@override String get newWorkspaceNameHint => '默认使用文件夹名';
	@override String get newWorkspaceSubtitle => '选择工作区的工作目录，并为它命名。';
	@override String get noConversations => '该工作区还没有对话';
	@override String get noData => '暂无数据';
	@override String get noSearchResults => '没有匹配的对话';
	@override String get openInNewTabWithOtherIdentity => '以其他身份在新标签页打开…';
	@override String get openTabs => '已打开';
	@override String get openWorkspaceInNewTab => '在新标签页中打开';
	@override String get owner => '团队所有者';
	@override String get personal => '简单模式';
	@override String get personalSubtitle => '不用组队，直接拉起一个 CLI 开聊。';
	@override String get providers => '供应商';
	@override String get recentVisits => '最近访问';
	@override String get recentlyClosed => '最近关闭';
	@override String get recentlyClosedEmpty => '暂无最近关闭的工作区';
	@override String get rememberLaunchChoice => '记住选择';
	@override String get renameWorkspace => '修改名称';
	@override String get searchHint => '搜索';
	@override String get sessionsLabel => '会话';
	@override String get simpleMode => '简单模式';
	@override String get teamConfig => '团队配置';
	@override String get teamWorkspaces => '团队工作区';
	@override String get unfavoriteWorkspace => '取消收藏';
	@override String get workspaceAgent => '智能体';
	@override String get workspaceExtensions => '扩展';
	@override String get workspaceFilterEmpty => '没有匹配的工作区';
	@override String get workspaceFilterHint => '过滤工作区';
	@override String get workspaceHooks => 'Hooks';
	@override String get workspaceId => '工作区 ID';
	@override String get workspaceList => '工作区列表';
	@override String get workspaceManagement => '工作区管理';
	@override String get workspaceMcp => 'MCP';
	@override String get workspaceMembers => '成员';
	@override String get workspacePath => '工作区路径';
	@override String get workspacePlugins => '插件';
	@override String get workspaceSettings => '工作区设置';
	@override String get workspaceSettingsBasicInfo => '基本信息';
	@override String get workspaceSettingsPathsHint => '在「附加目录」行点击编辑，可添加或移除工作区附加目录。';
	@override String get workspaceSettingsSectionBasic => '基本设置';
	@override String get workspaceSkills => '技能';
	@override String get workspaceSort => '排序工作区';
	@override String get workspaceSortCreatedDesc => '创建时间';
	@override String get workspaceSortNameAsc => '名称（A–Z）';
	@override String get workspaceSortNameDesc => '名称（Z–A）';
	@override String get workspaceSortRecentlyUpdated => '最近更新';
	@override String get workspaceSortSessionCountDesc => '会话数量';
	@override String workspaceAdditionalDirsCount({required int count}) => '${count} 个附加目录';
}

// Path: hook
class _AppLocalizations$hook$zh extends AppLocalizations$hook$en {
	_AppLocalizations$hook$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get actionCommand => '命令';
	@override String get actionScript => '脚本';
	@override String get capabilityMatrix => '能力矩阵';
	@override String get description => '描述';
	@override String get edit => '编辑 hook';
	@override String get env => '环境变量（每行 KEY=VALUE）';
	@override String get event => '事件';
	@override String get import => '导入';
	@override String get importCli => 'CLI';
	@override String get importDoneToast => '已导入 hooks';
	@override String get importInvalidJson => 'Hook JSON 无效';
	@override String get importJson => 'Hook JSON';
	@override String get importJsonHint => '粘贴 settings.json hooks、hooks.json 或 hooks 片段…';
	@override String get importNoHooks => '未找到 hooks';
	@override String get importOverwrite => '将覆盖';
	@override String get importParse => '解析';
	@override String installedCount({required int count}) => '已安装 ${count}';
	@override String get matcher => '匹配器';
	@override String get name => '名称';
	@override String get nameRequired => '名称为必填项';
	@override String get navTitle => 'Hooks';
	@override String get kNew => '新建 hook';
	@override String get policy => '策略';
	@override String get save => '保存';
	@override String get saveFailed => '保存 Hook 失败。';
	@override String get supportMatrix => '查看受支持程度';
	@override String get timeoutSec => '超时（秒）';
	@override String importDone({required int count}) => '导入 ${count} 条';
}

// Path: hub
class _AppLocalizations$hub$zh extends AppLocalizations$hub$en {
	_AppLocalizations$hub$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get publishAuthHint => '使用 GitHub 登录并授权，以向 Hub 仓库发起基于 fork 的拉取请求。';
	@override String get publishAuthorLabel => '作者';
	@override String get publishBadgePrOpen => 'PR 已开';
	@override String get publishBadgePublished => '已发布';
	@override String get publishCategoryRequired => '分类为必填项';
	@override String get publishConfirmHint => '请核对包元数据，然后发布基于 fork 的拉取请求。';
	@override String get publishCopyLink => '复制链接';
	@override String get publishDone => '完成';
	@override String get publishExpertTitle => '发布专家到 Hub';
	@override String get publishGatesClear => '依赖均可移植，可继续确认。';
	@override String get publishKindExpert => '专家';
	@override String get publishKindLabel => '类型';
	@override String get publishKindTeam => '团队';
	@override String get publishLocalExpertBlocked => '请先映射所有本地专家后再继续';
	@override String get publishLocalExpertHint => '花名册中的本地专家须先映射为已发布或内置专家，才能上传。';
	@override String get publishNext => '下一步';
	@override String get publishNonPortableBlocked => '请先移除不可移植依赖后再继续';
	@override String get publishNonPortableHint => '以下依赖没有可移植来源。请先从团队配置中移除后再发布：';
	@override String get publishOpenPr => '打开 PR';
	@override String get publishPublish => '发布';
	@override String get publishRemapLabel => '发布为';
	@override String get publishSlugHint => 'url-safe-id';
	@override String get publishSlugLabel => '标识（slug）';
	@override String get publishSlugRequired => '标识为必填项';
	@override String get publishSuccessHint => '拉取请求已创建。可复制或打开下方链接。';
	@override String get publishTeamTitle => '发布团队到 Hub';
	@override String get publishTokenHint => 'ghp_…';
	@override String get publishTokenLabel => 'GitHub 令牌';
	@override String get publishTokenRequired => '发布需要 GitHub 令牌';
	@override String get publishTokenSaveFailed => '无法保存 GitHub 令牌';
	@override String get publishTokenStored => '已保存令牌，可在下方替换。';
}

// Path: init
class _AppLocalizations$init$zh extends AppLocalizations$init$en {
	_AppLocalizations$init$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get errorCopied => '已复制';
	@override String get errorCopy => '复制';
	@override String get errorCopyReport => '复制报告';
	@override String get errorDetails => '错误信息';
	@override String get errorPendingLogs => '待写入日志';
	@override String get errorStackEmpty => '（堆栈为空）';
	@override String get errorStackTrace => '堆栈跟踪';
	@override String get errorTitle => '应用启动失败';
	@override String errorVersion({required String version, required String build}) => '版本 ${version}（${build}）';
	@override String get errorViewLogs => '查看日志';
}

// Path: landing
class _AppLocalizations$landing$zh extends AppLocalizations$landing$en {
	_AppLocalizations$landing$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String launchAcpUnsupported({required String cli, required String target}) => '${cli} 仅支持 ACP 对话，当前目标（${target}）无法运行 ACP。请选择本机、SSH 或 Termux 目标，或改用支持终端的 CLI。';
	@override String launchLocalAdapterMissingDetail({required String cli}) => '未找到 ${cli} ACP 适配器';
	@override String get launchLocalCliMissing => '启动前请先在本机安装所需的 AI CLI。';
	@override String launchLocalCliMissingDetail({required String cli}) => '未找到 ${cli}';
	@override String get launchLocalCliMissingHint => '可直接在此安装，或在设置 → CLI 中指定可执行文件路径。';
	@override String get launchLocalCliMissingTitle => '本机需要的 AI CLI';
	@override String get launchLocalCliOpenSettings => '打开设置';
	@override String get launchRemoteCliMissing => '启动前请在远程机器上安装所需的 CLI。';
	@override String launchRemoteCliMissingDetail({required String host, required String cli}) => '${host} 上缺少 ${cli}';
	@override String get teamSettingsGlobalHint => '更改将应用于该团队的全局配置。';
	@override String get teamSettingsNavMachines => '机器分配';
	@override String get teamSettingsNavTeam => '团队默认';
}

// Path: llm
class _AppLocalizations$llm$zh extends AppLocalizations$llm$en {
	_AppLocalizations$llm$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get config => '服务商';
	@override String get configCurrentEffectivePathPrefix => '当前文件：';
	@override String get configEffectivePathUnresolved => '尚未解析出路径（请指定 CLI 或自定义路径）';
	@override String get configOpenSessionSettings => '会话设置…';
	@override String get configPageSubtitle => '管理 LLM 提供商和模型。';
	@override String get configPathBadgeCustom => '自定义';
	@override String get configPathBadgeDefault => '默认';
	@override String get configPathBrowse => '选择文件';
	@override String get configPathHint => '留空则使用默认路径';
	@override String get configPathLabel => 'LLM 配置文件';
	@override String get configPathPickerTitle => '选择 llm_config.json';
	@override String get configPathReset => '默认';
	@override String get configPathSave => '更新';
	@override String get configPathSessionCardDescription => 'LLM 配置文件（llm_config.json）的绝对路径。留空则使用 CLI 安装目录旁的默认路径。';
	@override String get configPathSessionCardDescriptionSsh => 'SSH 远端主机上 llm_config.json 的绝对路径。留空则使用远端 CLI 安装目录旁的默认路径。';
	@override String get configSubtitle => '提供商和模型';
}

// Path: log
class _AppLocalizations$log$zh extends AppLocalizations$log$en {
	_AppLocalizations$log$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get installJobCopy => '复制';
	@override String get installJobEmpty => '暂无输出。';
	@override String get installJobPaused => '已暂停';
	@override String get installJobResume => '跟随';
	@override String get installJobTitle => '安装日志';
	@override String get installJobUnavailable => '日志不可用——文件已被清理。';
	@override String get installJobViewLog => '查看日志';
	@override String get viewerAcpFrames => 'ACP 协议帧日志（默认关闭）';
	@override String get viewerActionsMenu => '更多操作';
	@override String get viewerAllCopied => '已复制全部过滤后的日志';
	@override String get viewerClearDone => '已清理过期日志';
	@override String viewerClearFailed({required String error}) => '清理失败：${error}';
	@override String get viewerClearOld => '清理过期日志';
	@override String get viewerCompactView => '简洁视图';
	@override String get viewerCopyAll => '复制全部日志';
	@override String get viewerCopyPath => '复制日志路径';
	@override String get viewerEmpty => '暂无日志文件';
	@override String get viewerEmptyHint => '应用运行后会在此生成日志。';
	@override String get viewerFileLabel => '日志文件';
	@override String get viewerFilterLevel => '级别';
	@override String get viewerFilterTitle => '过滤';
	@override String viewerLineCount({required int count}) => '${count} 行';
	@override String viewerLoadFilesFailed({required String error}) => '加载日志列表失败：${error}';
	@override String viewerPathCopied({required String name}) => '已复制路径：${name}';
	@override String get viewerPendingBody => '以下为等待写入文件的缓冲条目：';
	@override String get viewerPendingTitle => '日志尚未写入磁盘';
	@override String viewerReadFailed({required String error}) => '读取日志失败：${error}';
	@override String get viewerRefresh => '刷新';
	@override String get viewerReverseOrder => '从最新内容开始';
	@override String get viewerSearchHint => '搜索日志…';
	@override String get viewerSubtitle => '应用数据目录下的运行日志与错误记录。';
	@override String get viewerTitle => '日志';
	@override String get viewerWrapLines => '自动换行';
}

// Path: managedProviders
class _AppLocalizations$managedProviders$zh extends AppLocalizations$managedProviders$en {
	_AppLocalizations$managedProviders$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get adapter => '适配器';
	@override String get adapterHint => 'http-json 或已注册的适配器 ID';
	@override String get add => '添加 Provider';
	@override String get advancedSectionSubtitle => '适配器、类型与内部引用。';
	@override String get advancedSectionTitle => '适配器、类型与引用';
	@override String get authenticationFailed => 'Provider 身份验证失败。';
	@override String get basicsSectionSubtitle => '命名与必要密钥。';
	@override String get basicsSectionTitle => '名称与密钥';
	@override String get basicsSummary => '选择预设、命名，并按需填写密钥。';
	@override String get cachedUsage => '缓存用量';
	@override String get cachedUsageStale => '缓存用量 · 需要刷新';
	@override String get cancel => '取消';
	@override String get credentialConfigured => '已配置凭据 · 密钥已隐藏';
	@override String get credentialField => '密钥字段名';
	@override String get credentialFieldHelper => '本地存储用的字段名。';
	@override String get credentialFieldHint => 'apiKey 或 accessToken';
	@override String get credentialFieldRequired => '保存 API Key 前请先填写凭据字段。';
	@override String get credentialLinkEmpty => '还没有可引用的供应商配置';
	@override String get credentialLinkManual => '手动输入密钥';
	@override String get credentialLinkMode => '凭据来源方式';
	@override String credentialLinkedTo({required Object provider}) => '使用 ${provider} 的凭证';
	@override String get credentialName => '凭据参数名';
	@override String get credentialNameHelper => '写入请求时的参数名。';
	@override String get credentialNameHint => 'Authorization 或 Cookie';
	@override String get credentialNone => '未配置凭据';
	@override String get credentialPlacement => '凭据位置';
	@override String get credentialPlacementHelper => 'header 或 query。';
	@override String get credentialPlacementHint => 'header 或 query';
	@override String get credentialRef => '凭据引用';
	@override String get credentialRefHint => '仅保存引用，不会显示密钥';
	@override String get credentialSaveFailed => '无法安全保存 Provider 凭据。';
	@override String get credentialSecret => 'API Key / Token';
	@override String get credentialSecretExistingHint => '留空保留已保存密钥';
	@override String get credentialSecretHelper => '留空保留已保存密钥。';
	@override String get credentialSecretHint => '填入 Provider 的 API Key 或 Token';
	@override String get credentialSource => '凭据来源';
	@override String get credentialSourceHelper => 'secret 读表单；cli:… 读 CLI 登录。';
	@override String get credentialSourceHint => 'secret 或 cli:cursor-mp-<entry>';
	@override String get credentialTemplate => '凭据拼接模板';
	@override String get credentialTemplateHelper => '拼成最终凭据值，常用于 Cookie；用花括号填变量。';
	@override String get credentialTemplateHint => '例如 WorkosCursorSessionToken=user::token';
	@override String get credentials => '凭据';
	@override String get credentialsSectionSubtitle => '凭据来源及写入请求的方式。';
	@override String get credentialsSectionTitle => '凭据来源与请求写入';
	@override String get currency => '货币';
	@override String get currencyMappingHelper => '已配置映射时从响应读取货币。';
	@override String get decimalError => '小数位必须是整数。';
	@override String get decimals => '小数位';
	@override String get delete => '删除';
	@override String deleteContent({required Object name}) => '删除“${name}”及其缓存用量？';
	@override String get deleteFailed => '无法删除管理 Provider。';
	@override String get deleteTitle => '删除管理 Provider？';
	@override String get disable => '禁用';
	@override String get disabled => '已禁用';
	@override String get display => '显示配置';
	@override String get displaySectionSubtitle => '余额与额度的显示格式。';
	@override String get displaySectionTitle => '余额与额度显示';
	@override String get dynamicCurrencyHelper => '货币从响应映射读取。';
	@override String get edit => '编辑';
	@override String get editTitle => '编辑管理 Provider';
	@override String get emptyHint => '添加 Provider 以独立跟踪余额和配额。';
	@override String get emptyTitle => '暂无管理 Provider';
	@override String get enable => '启用';
	@override String get enabled => '已启用';
	@override String get enabledSubtitle => '关闭后隐藏并停止查询。';
	@override String get enabledTitle => '启用';
	@override String get endpoint => '用量 API 地址';
	@override String get endpointError => '此 HTTP 适配器需要 HTTPS 或回环地址。';
	@override String get endpointHelper => '获取用量数据的请求地址。';
	@override String get endpointHint => 'https://api.example.com/usage';
	@override String get error => '错误';
	@override String get fieldExampleLabel => '示例';
	@override String get fieldMappingError => '字段映射必须是无密钥的 JSON 对象。';
	@override String get fieldMappings => '列表项字段映射（JSON）';
	@override String get fieldMappingsHelper => '数组每项各字段在响应中的 \$ 路径。';
	@override String get headers => '请求头（JSON）';
	@override String get headersHelper => '额外请求头；值可用花括号占位。';
	@override String get headersHint => 'Accept: application/json';
	@override String get httpFailed => 'Provider 服务返回错误。';
	@override String get identity => '基本信息';
	@override String get jsonPathSeeAlso => '\$ 用法详见「用量 API 与 JSON 解析」ℹ️';
	@override String get kind => '类型';
	@override String get kindApiBalance => 'API 余额';
	@override String get kindCustomHttp => '自定义 HTTP';
	@override String get kindPresetLockedHelper => '当前预设或模板已锁定类型。';
	@override String get kindSubscriptionQuota => '订阅额度';
	@override String get lastQueryFailed => '上次查询失败';
	@override String get loadFailed => '无法加载管理 Provider。';
	@override String get loadingUsage => '正在加载用量';
	@override String get measuresPath => '用量列表（\$）';
	@override String get measuresPathHelper => '每项一条余额的 \$ 路径（如 DeepSeek）。';
	@override String get measuresPathHint => '\$.balance_infos';
	@override String get method => 'HTTP 方法';
	@override String get methodHelper => '一般为 GET。';
	@override String get missingCredential => 'Provider 凭据缺失。';
	@override String get name => '名称';
	@override String get nameAdapterError => '名称和适配器不能为空。';
	@override String get nameHint => '显示名称';
	@override String get nav => '管理 Provider';
	@override String get networkFailed => 'Provider 网络请求失败。';
	@override String get newTitle => '新建管理 Provider';
	@override String get noUsage => '尚未查询用量';
	@override String get noneEnabledHint => '启用 Provider 后才会显示在状态栏并参与查询。';
	@override String get noneEnabledTitle => '没有已启用的 Provider';
	@override String get queryCompleted => 'Provider 查询完成。';
	@override String get queryFailed => '无法查询 Provider 用量。';
	@override String get querySectionSubtitle => '用量 API 与 JSON 解析。';
	@override String get querySectionTitle => '用量 API 与 JSON 解析';
	@override String get queryUnsupported => '不支持查询';
	@override String get quickPresetClaudeCode => 'Claude Code';
	@override String get quickPresetClaudeCodeHint => '登录或导入，或手填相同字段。';
	@override String get quickPresetCodebuddy => 'CodeBuddy';
	@override String get quickPresetCodebuddyHint => '使用 CodeBuddy 登录态查询积分余额。';
	@override String get quickPresetCodex => 'Codex';
	@override String get quickPresetCodexHint => '登录或导入，或手填相同字段。';
	@override String get quickPresetCursor => 'Cursor';
	@override String get quickPresetCursorHint => '登录或导入，或手填相同字段。';
	@override String get quickPresetGrokX => 'Grok / Cursor / X';
	@override String get quickPresetGrokXHint => '使用 Cursor 登录态查询合一后的周额度和预付费。';
	@override String get quickPresetCustom => '自定义';
	@override String get quickPresetCustomHint => '从零配置接口、凭据与显示格式。';
	@override String get quickPresetDeepSeek => 'DeepSeek';
	@override String get quickPresetDeepSeekHint => '已配余额接口，需填密钥。';
	@override String get quickPresetHint => '使用安全默认值开始；查询前请补充凭据。';
	@override String get quickPresetOpencodeGo => 'OpenCode Go';
	@override String get quickPresetOpencodeGoHint => 'Zen Go 订阅用量预设，需填 API 密钥。';
	@override String get quickPresetQoder => 'Qoder';
	@override String get quickPresetQoderCn => 'Qoder CN';
	@override String get quickPresetQoderCnHint => '使用 qoder.com.cn/account/integrations 生成的 PAT 查询套餐积分。';
	@override String get quickPresetQoderHint => '使用 qoder.com/account/integrations 生成的 PAT 查询套餐积分。';
	@override String get quickPresetTitle => '快速预设';
	@override String get referenceSyntaxHelper => '\$ — 从 HTTP 响应的 JSON 里读数\n\$ 表示整段响应，\$.字段名 用点号一层层往下取。\n例：\$.data、\$.balance_infos[0].total_balance、\$.rate_limit.used_percent\n\n用于「响应根路径」和额度窗口里的 used / total / remaining / resetsAt 等字段。\n\n花括号 — 往请求里填动态值（不是读响应）\n花括号内写变量名，发送时替换为凭据里的值。\n• accessToken — 访问令牌\n• accountId — 账号 ID\n• jwt.sub — JWT 的 sub\n\n用于请求头、Cookie、凭据模板。cli:… 登录后才有这些值。';
	@override String get refreshFailed => '无法刷新 Provider 用量。';
	@override String remainingPercent({required String percent}) => '${percent}剩余 %';
	@override String get requestMapping => '请求体（JSON）';
	@override String get requestMappingError => '请求映射必须是 JSON 对象。';
	@override String get requestMappingHelper => 'POST 时用；GET 留空。';
	@override String resetsIn({required String duration}) => '${duration}后重置';
	@override String get resetsSoon => '即将重置';
	@override String get responseParseFailed => '无法解析 Provider 响应。';
	@override String get responsePath => '响应根路径（\$）';
	@override String get responsePathHelper => '数据在嵌套层时用 \$ 先定位；留空从响应根解析。';
	@override String get responsePathHint => '\$.data';
	@override String get retry => '重试';
	@override String get save => '保存';
	@override String get saveFailed => '无法保存管理 Provider。';
	@override String get saveProvider => '保存 Provider';
	@override String get saved => '管理 Provider 已保存。';
	@override String get saving => '保存中…';
	@override String get secretMappingError => '请使用凭据引用，不要将密钥放入请求映射。';
	@override String get sectionConfiguredBadge => '已配置';
	@override String get showPercent => '显示百分比';
	@override String get stale => '已过期';
	@override String get subtitle => '独立于 CLI Provider 配置查看余额和配额。';
	@override String get templateVariablesSeeAlsoCredentials => '花括号用法详见「凭据来源与请求写入」ℹ️';
	@override String get templateVariablesSeeAlsoQuery => '花括号用法详见「用量 API 与 JSON 解析」ℹ️';
	@override String get testProviderQuery => '测试 Provider 查询';
	@override String get testQuery => '测试查询';
	@override String get title => '管理 Provider';
	@override String get unit => '单位';
	@override String get unknownUsage => '未知用量状态';
	@override String get usageInvalidated => 'Provider 用量已失效。';
	@override String get usageLoadFailed => '无法加载 Provider 用量。';
	@override String get usageNav => '余额与用量';
	@override String get usagePersistenceFailed => '无法保存 Provider 用量。';
	@override String get windows => '额度窗口（JSON）';
	@override String get windowsHelper => '每条额度写一行。每项写 label 与 used / total / remaining / resetsAt 的 \$ 路径。数组项请写死下标，如 \$.balance_infos[0].total_balance。';
	@override String get windowsHint => 'JSON 数组；每项含 label 与 \$ 路径';
}

// Path: mcp
class _AppLocalizations$mcp$zh extends AppLocalizations$mcp$en {
	_AppLocalizations$mcp$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get add => '添加 MCP';
	@override String get addButton => '添加 MCP';
	@override String get addTitle => '新增 MCP';
	@override String get catalogAdd => '添加';
	@override String get catalogAdded => '已加入 MCP 目录';
	@override String get catalogAdoption => '使用量';
	@override String get catalogCardNoDescription => '无';
	@override String get catalogEmpty => '未找到服务器';
	@override String get catalogInstalled => '已安装';
	@override String get catalogVerified => '已认证';
	@override String configuredCount({required int count}) => '已配置 ${count} 个 MCP 服务器';
	@override String get deleteConfirm => '删除该 MCP 服务器？';
	@override String get discoverySectionHint => '浏览内置模板，以及「仓库」中配置的远程目录。';
	@override String get discoverySectionTitle => '发现 MCP 服务器';
	@override String get discoverySourceAll => '全部';
	@override String get discoverySourceBuiltin => '内置';
	@override String get edit => '编辑 MCP';
	@override String get empty => '目录中暂无 MCP 服务器';
	@override String get emptyGoDiscovery => '浏览内置模板';
	@override String get emptyGoRegistries => '打开注册中心';
	@override String get fieldArgs => '参数（空格分隔）';
	@override String get fieldCommand => '命令';
	@override String get fieldName => '名称';
	@override String get formDescriptionHint => '可选的描述信息';
	@override String get formDescriptionLabel => '描述';
	@override String get formDetailHint => '选择服务器进行编辑，或添加新的 MCP 服务器。';
	@override String get formDisplayNameHint => '例如 @modelcontextprotocol/server-time';
	@override String get formDisplayNameLabel => '显示名称';
	@override String get formDocsLabel => '文档链接';
	@override String get formFormatJson => '格式化';
	@override String get formHomepageLabel => '主页链接';
	@override String get formIdLabel => 'MCP 标题（唯一）*';
	@override String get formJsonLabel => '完整的 JSON 配置';
	@override String get formMetadata => '附加信息';
	@override String get formRequiredFields => '请填写 MCP 标题与显示名称。';
	@override String get formSubmitAdd => '添加';
	@override String get formTagsHint => 'stdio, time, utility';
	@override String get formTagsLabel => '标签（逗号分隔）';
	@override String get import => '从本机导入';
	@override String get importDone => 'MCP 目录已更新';
	@override String get importEmpty => '在 ~/.claude.json 与 ~/.flashskyai.json 中未找到 MCP';
	@override String get importExisting => '导入已有';
	@override String get importOverwrite => '覆盖冲突项';
	@override String importSummary({required int added, required int conflicts}) => '新增 ${added} 个，冲突 ${conflicts} 个';
	@override String installedCount({required int count}) => '已安装 ${count}';
	@override String get installedSectionTitle => '已安装的 MCP';
	@override String get navDiscovery => '发现';
	@override String get navInstalled => '已安装';
	@override String get navRegistries => '注册中心';
	@override String get navTitle => 'MCP 服务器';
	@override String get noInstalled => '还没有安装 MCP 服务器';
	@override String get noInstalledHint => '打开发现页，从内置模板或注册中心添加。';
	@override String get oAuthCallbackUrlHint => '登录后粘贴完整 URL（含 ?code=）';
	@override String get oAuthCallbackUrlLabel => '回调地址';
	@override String get oAuthConnectAction => '连接';
	@override String get oAuthConnectHint => '在浏览器中完成 MCP 提供商登录。令牌按 Claude Code 格式写入应用配置目录（等同终端 /mcp → Authenticate）。';
	@override String get oAuthConnectSuccess => 'MCP OAuth 已连接';
	@override String oAuthConnectTitle({required String name}) => '连接 ${name}';
	@override String get oAuthDiscovering => '正在发现授权服务器…';
	@override String get oAuthOpenBrowser => '打开浏览器';
	@override String get oAuthStartConnect => '连接';
	@override String get oAuthStatusConnected => 'OAuth 已连接';
	@override String get oAuthStatusNeedsAuth => '需要 OAuth';
	@override String get oAuthSubmitCallback => '提交地址';
	@override String get openHomepage => '打开链接';
	@override String get presetDescContext7 => '通过 Context7 获取最新库文档。';
	@override String get presetDescFetch => '抓取网页并将 HTML 转为 Markdown，供模型使用。';
	@override String get presetDescMemory => '跨会话的持久化记忆图谱。';
	@override String get presetDescSequentialThinking => '结构化分步推理，适合复杂问题。';
	@override String get presetDescTime => '时间查询：当前时间、时区转换、日期计算等。';
	@override String get probeChecking => '检测中…';
	@override String get probeNeedsAuth => '需要授权';
	@override String get probeOffline => '离线';
	@override String get probeOfflineHint => '无法连接此 MCP 服务器。';
	@override String get probeRefreshAll => '刷新状态';
	@override String probeToolCount({required int count}) => '${count} 个工具';
	@override String get registryEditTitle => '编辑 API 地址';
	@override String get registryLoadMore => '加载更多';
	@override String get registryOfficial => '官方注册表';
	@override String get registryOfficialHint => '官方 MCP Registry — https://registry.modelcontextprotocol.io';
	@override String registryResetConfirm({required String name}) => '将「${name}」恢复为默认 API 地址？';
	@override String get registryResetTitle => '恢复默认';
	@override String get registrySearchHint => '搜索服务器（如 github）';
	@override String get registrySmithery => 'Smithery';
	@override String get registrySmitheryHint => 'Smithery — https://api.smithery.ai';
	@override String get repoApiUrlLabel => 'API 基础地址';
	@override String get repoConfigSaved => '目录 API 设置已保存';
	@override String get repoDisabledHint => '该目录源已禁用，请在「仓库」中启用。';
	@override String get repoResetDefault => '恢复默认';
	@override String get repoTestConnection => '测试连接';
	@override String repoTestFailed({required String error}) => '连接失败：${error}';
	@override String get repoTestOk => '连接成功';
	@override String get serverNotFound => '未找到该 MCP 服务器';
	@override String get smitheryApiTokenHint => 'Smithery API 密钥（Bearer）';
	@override String get smitheryApiTokenLabel => 'API Token';
	@override String get smitheryApiTokenSet => '已配置 Token';
	@override String get subtitle => '为 Agent 会话管理 MCP 服务器配置。';
	@override String toolsDialogTitle({required String name}) => '${name} 的工具';
	@override String get toolsDone => '完成';
	@override String get toolsEmpty => '该服务器没有工具。';
	@override String get toolsReload => '重新加载';
	@override String get toolsSection => '工具';
}

// Path: member
class _AppLocalizations$member$zh extends AppLocalizations$member$en {
	_AppLocalizations$member$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get assignFoldersAction => '分配目录…';
	@override String get cliInheritHint => '继承团队默认';
	@override String get detailBrowseConfigDirTitle => '配置目录';
	@override String get detailEmpty => '该成员尚未在此会话中启动，且团队层无配置。';
	@override String get detailLoadError => '读取该成员的配置目录失败。';
	@override String get detailNeedsSession => '请先打开一个会话';
	@override String get detailOpenConfigDir => '打开配置目录';
	@override String get detailOpenConfigDirFailed => '无法在文件管理器中打开配置目录。';
	@override String detailOpenConfigDirFailedOnHost({required String host}) => '无法在 ${host} 上打开配置目录，远程主机可能没有桌面文件管理器。';
	@override String get detailOpenInFileManager => '在文件管理器中打开';
	@override String get detailSectionEmpty => '无';
	@override String get detailSourceRuntime => '运行会话配置';
	@override String get detailSourceTeam => '团队层配置（该成员未在此会话中启动）';
	@override String get detailTabMcp => 'MCP';
	@override String get detailTabOverview => '概览';
	@override String get detailTabPlugins => '插件';
	@override String get detailTabSettings => '设置';
	@override String get detailTabSkills => 'Skills';
	@override String get detailTitle => '成员详情';
	@override String get detailViewAction => '查看成员详情';
	@override String get effortInheritHint => '继承团队默认';
	@override String get effortLevel => '成员力度覆盖';
	@override String get effortLevelSubtitle => '设置后覆盖团队默认值。';
	@override String get extraArgs => '成员额外 CLI 参数';
	@override String get extraArgsSubtitle => '仅附加在该成员的 CLI 启动参数。';
	@override String get launchConfigInheritHint => '使用团队的默认 CLI、服务商、模型与 Effort。';
	@override String get launchConfigInheritUnset => '团队默认尚未配置。';
	@override String get launchConfigSubtitle => '本成员的 CLI 后端、提供商、模型与 Effort。';
	@override String get launchConfigTitle => '模型配置';
	@override String get launchConfigTypeLabel => '配置类型';
	@override String get launchConfigTypePreset => '预设';
	@override String get launchOrder => '成员启动顺序';
	@override String get name => '成员名称';
	@override String get nameSubtitle => '仅作界面展示用。若要指明职责与边界，请编辑下方的职责。';
	@override String get officialClaudeModelHint => '使用 Claude 账号默认模型；请在 Providers 设置中管理 Official 登录。';
	@override String get personaEmptyNoExpert => '选择专家后可查看人设内容。';
	@override String get playbook => '工作手册';
	@override String get playbookEmpty => '该专家未填写工作手册';
	@override String get playbookPresetDeveloperText => '测试先行：实现前先写一个会失败的测试，再用最小 diff 让它通过。每次改动后跑相关测试，并说明改了哪些文件及原因。不要把无关改动混在一起；到约定检查点要停下。若团队装有 test-driven-development skill，就遵循它。';
	@override String get playbookPresetResearcherText => '动手前先厘清意图：复述问题与你的假设，然后在代码库里先广度排查再深入。汇报时给出文件路径、相关符号与建议的下一步——只提建议，不改生产代码。若团队装有 brainstorming skill，先用它框定问题。';
	@override String get playbookPresetReviewerText => '按序审查：①确认测试覆盖了改动；②正确性与边界情况；③可维护性及与周边代码的一致性。每条意见都要写明文件路径、行号、问题与具体改法——不要空泛夸奖，也不要只挑刺却不给改法。缺测试要显式指出。';
	@override String get playbookSubtitle => '接到任务后怎么执行：步骤、检查点、汇报格式。会作为 Agent 的操作指令。';
	@override String get presenceBooting => '启动中…';
	@override String get presenceConnecting => '连接中…';
	@override String get presenceIdle => '空闲';
	@override String get presenceOffline => '未连接';
	@override String get presenceWorking => '工作中';
	@override String get presetCustom => '自定义配置';
	@override String get presetInheritTeam => '继承团队默认';
	@override String get presetInheritTeamNone => '团队未设置默认';
	@override String get presetLabel => '预设';
	@override String get presetSelectPreset => '选择预设';
	@override String presetViaPreset({required String presetName}) => '${presetName}（通过预设）';
	@override String presetViaTeamDefault({required String presetName}) => '${presetName}（通过团队默认）';
	@override String get promptPresetDeveloper => '开发';
	@override String get promptPresetDeveloperText => '在约定范围内实现分配的任务。未经要求，不要扩大范围或顺手重构无关代码。';
	@override String get promptPresetResearcher => '调研';
	@override String get promptPresetResearcherText => '只调研并汇报。除非被要求，否则不要改动生产代码。';
	@override String get promptPresetReviewer => '审查';
	@override String get promptPresetReviewerText => '只做代码审查。除非被明确要求，否则不要改动文件。';
	@override String get promptPresetTeamLead => '队长';
	@override String get promptPresetTeamLeadText => '协调全队：将用户需求拆成任务清单（每条写明范围与验收标准），再分配给各队友实现；除阻塞性问题外，不要亲自做大块开发，可先阅读代码与文档了解现状。\n在本会话窗口与用户直接沟通。指派与跟进时只联系其他队友（按成员名称），不要把任务派给自己。汇总队友结果后回复用户，写清结论、涉及文件与后续步骤。';
	@override String get promptPresetsLabel => '预设';
	@override String get promptSubtitle => '该成员负责什么、不应做什么。会写入 Agent 的角色说明。';
	@override String get quickList => '成员快速列表';
	@override String get responsibilities => '职责';
	@override String get responsibilitiesEmpty => '该专家未填写职责';
	@override String get targetAssignmentInherit => '继承工作区目录';
	@override String targetAssignmentSubtitle({required Object member}) => '${member} 运行所在的机器（其分配的工作区目录）。';
	@override String get targetAssignmentTitle => '成员所在机器';
	@override String get terminalNotStartedTitle => '终端未启动 — 点击启动';
	@override String get terminalReclaimedBody => '点击重新连接（会话会恢复）';
	@override String get terminalReclaimedTitle => '终端已回收以释放内存';
}

// Path: mixed
class _AppLocalizations$mixed$zh extends AppLocalizations$mixed$en {
	_AppLocalizations$mixed$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get workspaceCreateSessionBlocked => '请先在团队设置中确认机器分配，再在此混合工作区新建对话。';
	@override String get workspaceLeadPlacementInvalid => '工作区包含本地文件夹时，团队负责人必须分配到本地主机。';
	@override String get workspaceMemberAssignmentConfirm => '启动团队';
	@override String get workspaceMemberAssignmentIncomplete => '混合工作区首次启动前，请先确认成员的机器分配。';
	@override String get workspaceMemberAssignmentSubtitle => '左侧选择机器，右侧用 + / − 放置各成员的实例。';
	@override String get workspaceMemberAssignmentTitle => '分配成员到机器';
	@override String workspaceMemberPlacementOnMachine({required int count}) => '本机 ${count} 个';
	@override String workspaceMemberPlacementProgress({required int placed, required int total}) => '已分配 ${placed} / ${total}';
	@override String get workspacePersonalLaunchBlockedHint => '这是混合工作区。请切换到团队标签页启动对话，并确认机器分配。';
	@override String get workspaceRequiresTeamLaunch => '混合工作区只能通过团队身份启动。请切换到团队，并在团队设置中确认机器分配。';
	@override String get workspaceSessionLaunchBlocked => '该对话的机器分配已失效。请在团队设置中确认分配后新建对话。';
}

// Path: my
class _AppLocalizations$my$zh extends AppLocalizations$my$en {
	_AppLocalizations$my$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get expertsCreate => '新建专家';
	@override String get expertsDelete => '删除';
	@override String expertsDeleteConfirm({required Object name}) => '删除专家「${name}」？此操作无法撤销。';
	@override String expertsDeleteReferenced({required Object name}) => '无法删除「${name}」——仍有团队花名册引用该专家。请先改派相关成员。';
	@override String get expertsEdit => '编辑';
	@override String get expertsEmptyHint => '创建本地专家人设，以便在多个团队中复用。';
	@override String get expertsEmptyTitle => '还没有专家';
	@override String get expertsNav => '我的专家';
	@override String get expertsSubtitle => '管理本地专家人设';
	@override String get expertsTitle => '我的专家';
	@override String get expertsUpload => '上传';
	@override String teamsCreatedAt({required Object date}) => '创建于 ${date}';
	@override String get teamsEmptyHint => '创建团队以管理成员、技能与插件。';
	@override String get teamsEmptyTitle => '还没有团队';
	@override String teamsMemberCount({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count,
		other: '${count} 名成员',
	);
	@override String get teamsNav => '我的团队';
	@override String get teamsSubtitle => '管理本地团队配置';
	@override String get teamsTitle => '我的团队';
	@override String get teamsUpload => '上传';
}

// Path: notification
class _AppLocalizations$notification$zh extends AppLocalizations$notification$en {
	_AppLocalizations$notification$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get centerTitle => '通知';
	@override String get clearAll => '清空';
	@override String get delete => '删除';
	@override String get empty => '暂无通知';
	@override String get historySection => '历史';
	@override String get markAllRead => '全部标为已读';
	@override String get markRead => '标为已读';
	@override String get ongoingSection => '进行中';
	@override String timeDaysAgo({required int days}) => '${days} 天';
	@override String timeHoursAgo({required int hours}) => '${hours} 小时';
	@override String get timeJustNow => '刚刚';
	@override String timeMinutesAgo({required int minutes}) => '${minutes} 分钟';
}

// Path: onboarding
class _AppLocalizations$onboarding$zh extends AppLocalizations$onboarding$en {
	_AppLocalizations$onboarding$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get appearanceSubtitle => '可随时在「设置 → 布局」中修改。';
	@override String get appearanceTitle => '选择语言与外观';
	@override String get cliFound => '已找到 CLI';
	@override String get cliNotFound => '未在 PATH 中';
	@override String get cliRedetect => '重新检测';
	@override String get cliScanning => '正在扫描 PATH 中的 CLI…';
	@override String get cliSubtitle => '定位用于启动会话的可执行文件。可安装缺失项，或稍后在设置中指定路径。';
	@override String get cliTitle => '检测 CLI 工具';
	@override String get defaultPresetDefaultName => '默认';
	@override String get defaultPresetEmpty => '暂无可选 Provider，可跳过或在设置中添加。';
	@override String get defaultPresetModelHint => '该预设的主模型';
	@override String get defaultPresetSelectExisting => '使用已有预设';
	@override String get defaultPresetSubtitle => '个人工作区与团队默认启动配置将共用此 CLI 预设。';
	@override String get defaultPresetTitle => '配置默认启动预设';
	@override String get getStarted => '开始使用';
	@override String get next => '下一步';
	@override String get previous => '上一步';
	@override String progress({required int current, required int total}) => '第 ${current} / ${total} 步';
	@override String get providerImportEmpty => '未检测到 Provider，可稍后在设置中配置。';
	@override String get providerImportFailed => '导入失败';
	@override String get providerImportRescan => '重新扫描';
	@override String get providerImportResults => '导入结果';
	@override String get providerImportSubtitle => '扫描本机各 CLI 配置中的现有 Provider。';
	@override String get providerImportTitle => '导入 CLI Provider';
	@override String get rerunSetup => '重新运行设置向导';
	@override String get skip => '跳过';
	@override String get sshSubtitle => 'Android 通过 SSH 在远程主机运行 AI CLI。';
	@override String get sshTitle => '配置 SSH 连接';
	@override String get stepAppearance => '语言 / 主题';
	@override String get stepCli => 'CLI 工具';
	@override String get stepDefaultPreset => '默认预设';
	@override String get stepProviderImport => '导入 Provider';
	@override String get stepSsh => 'SSH';
	@override String get title => '首次设置';
	@override String get workHomeSubtitle => '先连接本机 Termux 或远程 SSH，再检测 AI CLI。';
	@override String get workHomeTitle => '选择工作环境';
}

// Path: opencode
class _AppLocalizations$opencode$zh extends AppLocalizations$opencode$en {
	_AppLocalizations$opencode$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get credentialsActionFailed => '凭据更新失败';
	@override String get credentialsActionSuccess => '凭据已更新';
	@override String get credentialsImportFile => '导入 auth.json…';
	@override String get credentialsImportGlobal => '从 opencode 凭据导入';
	@override String get credentialsLogin => 'Provider 登录';
	@override String get credentialsRevoke => '退出登录';
	@override String credentialsRevokeConfirm({required String name}) => '退出登录并删除 ${name} 的已保存凭据？';
	@override String get permissionAllowAlways => '总是允许';
	@override String get permissionAllowOnce => '允许一次';
	@override String get permissionAnswerFailed => '无法提交你的决定。请重试或在终端中处理。';
	@override String get permissionAnswerInTerminal => '在终端处理';
	@override String get permissionReject => '拒绝';
	@override String get permissionTitle => 'OpenCode 需要你的授权';
}

// Path: plugin
class _AppLocalizations$plugin$zh extends AppLocalizations$plugin$en {
	_AppLocalizations$plugin$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String cliSupportFully({required String cli}) => '${cli}：完全支持';
	@override String cliSupportNotApplicable({required String cli}) => '${cli}：不适用';
	@override String cliSupportPartial({required String cli, required String dropped}) => '${cli}：部分支持（丢弃 ${dropped}）';
	@override String get componentAgents => '代理';
	@override String get componentApps => '应用';
	@override String get componentCommands => '命令';
	@override String get componentHooks => '钩子';
	@override String get componentMcp => 'MCP';
	@override String get componentRules => '规则';
	@override String get componentSkills => '技能';
}

// Path: plugins
class _AppLocalizations$plugins$zh extends AppLocalizations$plugins$en {
	_AppLocalizations$plugins$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get cardDetails => '详情';
	@override String get cardInstall => '安装';
	@override String get cardInstalled => '已安装';
	@override String get cardUninstall => '卸载';
	@override String get cardUpdate => '更新';
	@override String get cardViewSource => '查看来源';
	@override String get catalogAdoption => '安装量';
	@override String get catalogCardNoDescription => '无';
	@override String get checkUpdates => '检查更新';
	@override String get checkingUpdates => '检查中…';
	@override String get discoveryEmpty => '无匹配的插件';
	@override String get discoverySyncing => '正在后台检查 marketplace 更新并同步插件…';
	@override String get filterAll => '全部';
	@override String get filterInstalled => '已安装';
	@override String get filterMarketplaceAll => '全部 marketplace';
	@override String get filterUninstalled => '未安装';
	@override String get goDiscovery => '浏览 marketplace';
	@override String get importFromDisk => '从目录导入';
	@override String get importNothing => '未发现未管理的插件。';
	@override String get importTitle => '导入未管理的插件';
	@override String get installFromZip => '从 ZIP 安装';
	@override String installedCount({required int count}) => '已安装 ${count} 个';
	@override String get local => '本地';
	@override String get marketplaceAdd => '添加 marketplace';
	@override String get marketplaceBranch => '分支';
	@override String get marketplaceDisplayName => '显示名称';
	@override String get marketplaceInvalidUrl => '请输入合法的 GitHub 仓库地址。';
	@override String get marketplaceRemove => '移除 marketplace';
	@override String marketplaceRemoveConfirm({required String url}) => '确认移除 marketplace ${url}？已安装的插件会保留。';
	@override String get marketplaceUrl => 'GitHub 仓库地址';
	@override String get marketplaceUrlHint => 'https://github.com/owner/marketplace';
	@override String get marketplacesEmpty => '尚未配置 marketplace';
	@override String get navDiscovery => '发现';
	@override String get navInstalled => '已安装';
	@override String get navMarketplaces => 'Marketplaces';
	@override String get noInstalled => '尚未安装插件';
	@override String get noInstalledHint => '在 Marketplaces 选项卡添加 marketplace，然后在 Discovery 中安装。';
	@override String get searchPlaceholder => '搜索插件';
	@override String get sidebarLabel => '插件';
	@override String get subtitle => '管理 Claude Code 风格插件包';
	@override String get title => '插件';
	@override String uninstallConfirm({required String name, required int n}) => '确认卸载 ${name}？将影响 ${n} 个团队。';
	@override String get uninstallImpactList => '受影响的团队：';
	@override String uninstallSuccess({required String name}) => '已卸载 ${name}';
	@override String updateAll({required int count}) => '全部更新 (${count})';
	@override String get updateAvailable => '有新版本';
}

// Path: provider
class _AppLocalizations$provider$zh extends AppLocalizations$provider$en {
	_AppLocalizations$provider$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get provider => '提供商';
	@override String get credentialsAuthenticated => '已认证';
	@override String get credentialsBrowserOpened => '已打开浏览器进行授权';
	@override String get credentialsDeviceCodeHint => '请在浏览器中输入此一次性验证码（15 分钟内有效）';
	@override String get credentialsDeviceCodeTitle => '设备验证码';
	@override String get credentialsFailureDestinationExists => '凭据已存在。请先退出登录，或再次导入以覆盖。';
	@override String get credentialsFailureInvalidCredential => '凭据格式无效或不完整';
	@override String credentialsFailureLoginFailed({required int exitCode}) => '登录失败（退出码 ${exitCode}）';
	@override String credentialsFailureLoginProcessError({required String detail}) => '无法运行登录命令：${detail}';
	@override String get credentialsFailurePathRequired => '请先选择文件或目录';
	@override String credentialsFailureProviderEntryMissing({required String path, required String providerId}) => '在 ${path} 中未找到 "${providerId}" 的凭据';
	@override String credentialsFailureProviderEntryMissingWithKeys({required String path, required String providerId, required String keys}) => '在 ${path} 中未找到 "${providerId}" 的凭据。已有：${keys}';
	@override String get credentialsFailureProviderNotFound => '未找到 Provider';
	@override String credentialsFailureRequiredFileMissing({required String path}) => '缺少必需文件：${path}';
	@override String get credentialsFailureRevokeFailed => '无法退出登录或删除凭据';
	@override String get credentialsFailureServiceUnavailable => '凭据服务不可用';
	@override String credentialsFailureSourceMissing({required String path}) => '未找到凭据文件：${path}';
	@override String credentialsFailureSourceUnreadable({required String path}) => '无法读取凭据文件：${path}';
	@override String get credentialsFailureStatusRefreshFailed => '凭据已更新但状态刷新失败';
	@override String get credentialsFailureUnsupported => '不支持此凭据操作';
	@override String get credentialsFailureVerifyFailed => '凭据已写入但校验失败';
	@override String get credentialsReopenBrowser => '重新打开浏览器';
	@override String get credentialsUnauthenticated => '未认证';
	@override String detailSubtitle({required String type, required int count}) => '${type} 提供商 · ${count} 个模型';
	@override String get effortLevel => '推理力度';
	@override String get list => '提供商列表';
	@override String listModelCount({required int count}) => '${count} 个模型';
	@override String get modelBackgroundTier => '用于后台/快速任务（Claude haiku 档）';
	@override String get name => '提供商名称';
	@override String get type => '提供商类型';
	@override String get typeHint => 'openai, claude 或自定义';
}

// Path: qoder
class _AppLocalizations$qoder$zh extends AppLocalizations$qoder$en {
	_AppLocalizations$qoder$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get contextWindow => '上下文窗口（tokens）';
	@override String get contextWindowHint => '留空则使用模型默认值。';
	@override String get credentialsActionFailed => 'Qoder 操作失败';
	@override String get credentialsCancel => '取消';
	@override String get credentialsDone => '完成';
	@override String get credentialsLogin => '登录';
	@override String get credentialsLoginExited => 'Qoder CLI 已退出。请关闭此对话框后重新登录。';
	@override String credentialsLoginFailed({required String error}) => '无法启动登录终端：${error}';
	@override String get credentialsLoginIntro => '在下方终端完成登录。CLI 会打开浏览器；如果没有打开，请手动访问它输出的链接。也可以在这里切换账号。';
	@override String get credentialsLoginStarting => '正在启动 Qoder CLI…';
	@override String get credentialsLoginTitle => '登录 Qoder';
	@override String get credentialsRelaunch => '重新启动';
	@override String get credentialsSignedIn => '已登录';
}

// Path: remote
class _AppLocalizations$remote$zh extends AppLocalizations$remote$en {
	_AppLocalizations$remote$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations

	/// Landing readiness row label for a separate ACP adapter binary.
	@override String cliMachineReadinessAdapterLabel({required String cli}) => '${cli} ACP 适配器';

	@override String cliMachineReadinessFailed({required String cli, required String message}) => '${cli}：${message}';
	@override String get cliMachineReadinessInstallHint => '对每个缺失的 CLI 点击安装，或在目标设置中指定手动路径。';
	@override String cliMachineReadinessMissing({required String cli}) => '未找到 ${cli} — 请安装或设置手动路径';
	@override String get cliMachineReadinessProbing => '正在检测…';
	@override String cliMachineReadinessReady({required String cli, required String path}) => '${cli} 已就绪：${path}';
	@override String get cliMachineReadinessTitle => '此机器上需要的 CLI';
	@override String get connectionsSubtitle => '管理本机保存的远程主机、连接与切换工作主目录；断线时同样可用。';
	@override String get connectionsTitle => '远程连接';
	@override String get directoryBrowserEmpty => '此处没有子目录';
	@override String get directoryBrowserError => '无法打开远程目录。你仍可在下方手动输入路径。';
	@override String get directoryBrowserTitle => '浏览远程目录';
	@override String get directoryBrowserTypePathHint => '~/work/workspace';
	@override String get directoryBrowserTypePathLabel => '或手动输入路径';
	@override String get directoryBrowserUpOneLevel => '上一级';
	@override String get directoryBrowserUseThisDirectory => '使用此目录';
	@override String get directoryBrowserUseTypedPath => '使用路径';
}

// Path: resource
class _AppLocalizations$resource$zh extends AppLocalizations$resource$en {
	_AppLocalizations$resource$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get managerAppProcess => '应用';
	@override String get managerColumnCpu => 'CPU';
	@override String get managerColumnMemory => '内存';
	@override String get managerColumnName => '名称';
	@override String get managerEmptyTree => '当前没有运行中的会话。';
	@override String get managerKill => '结束';
	@override String get managerKillAll => '全部结束';
	@override String get managerKillAllConfirmBody => '将断开列表中的全部运行中会话与终端。';
	@override String get managerKillAllConfirmTitle => '结束全部运行中会话？';
	@override String get managerKillFailed => '无法结束会话。';
	@override String get managerMetricsError => '无法刷新进程指标。';
	@override String get managerPanelTitle => '资源管理器 - 会话';
	@override String get managerRefresh => '刷新';
	@override String get managerSpace => '空间';
	@override String get managerSpaceBeta => 'Beta';
	@override String get managerSpaceNotScanned => '不会扫描工作区磁盘占用。';
	@override String managerSystemMemoryPercent({required String percent}) => '系统内存 ${percent}%';
	@override String managerTerminalsCount({required int count}) => '${count} 个运行中会话';
	@override String get managerTitle => '资源管理器';
	@override String managerTooltip({required int count}) => '资源管理器 - ${count} 个运行中会话';
	@override String get managerTooltipHint => '跨所有工作区的运行中会话。';
}

// Path: rtk
class _AppLocalizations$rtk$zh extends AppLocalizations$rtk$en {
	_AppLocalizations$rtk$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get bashOnlyHint => '仅作用于 Agent 的 Bash 工具调用；内置 Read、Grep、Glob 不会自动改写。';
	@override String get settingsDescription => '在命令输出进入模型前压缩 Agent Bash 结果（需本机 PATH 中有 rtk 与 jq）。';
	@override String get settingsEnableTitle => '启用 RTK';
	@override String get settingsInstallLink => '安装说明';
	@override String get settingsStatusTitle => '本机状态';
	@override String get settingsTitle => 'RTK 省 token';
	@override String statusInstalled({required String version}) => 'rtk ${version} 已就绪';
	@override String get statusInstalledGeneric => 'rtk 已就绪';
	@override String get statusJqMissing => 'PATH 中未找到 jq';
	@override String get statusNotFound => 'PATH 中未找到 rtk';
	@override String statusVersionTooOld({required String version}) => 'rtk ${version} 版本过低（需要 >= 0.23.0）';
}

// Path: run
class _AppLocalizations$run$zh extends AppLocalizations$run$en {
	_AppLocalizations$run$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get acceptRecommendation => '将建议配置添加到 launch.json';
	@override String get action => '运行';
	@override String get addConfiguration => '添加配置';
	@override String get alreadyRunningMessage => '重新运行当前会话，还是再启动一个新实例？';
	@override String get alreadyRunningTitle => '配置已在运行';
	@override String get apply => '应用';
	@override String get build => '构建';
	@override String get buildUnavailable => '构建功能尚未提供';
	@override String get clearExited => '清除已退出的会话';
	@override String compoundConfiguration({required String name}) => '${name}（组合）';
	@override String get configurationName => '名称';
	@override String get configurationTooltip => '运行配置';
	@override String get configurationType => '类型';
	@override String get configurationsEmpty => '暂无启动配置';
	@override String get configureLaunchItems => '配置启动项';
	@override String get debug => '调试';
	@override String get debugUnavailable => '调试功能尚未提供';
	@override String get deleteConfiguration => '删除';
	@override String deleteConfigurationConfirm({required String name}) => '删除配置“${name}”？';
	@override String get discard => '放弃';
	@override String get discardChangesMessage => '此配置有未保存的更改。应用、放弃，还是取消？';
	@override String get discardChangesTitle => '放弃更改？';
	@override String get editConfigurations => '编辑配置';
	@override String get editorSelectConfiguration => '选择配置';
	@override String get emptyOutputHint => '运行配置后，输出将显示在这里';
	@override String get errorNoConfiguration => '未选择配置';
	@override String get errorNoFolder => '没有工作区文件夹';
	@override String get errorSshProfileMissing => '找不到此运行目标的 SSH 配置';
	@override String get errorSshSpawnerMissing => '未配置 SSH 进程执行';
	@override String get executeScriptFile => '脚本文件';
	@override String get executeScriptText => '脚本内容';
	@override String get fieldActivateToolWindow => '激活工具窗口';
	@override String get fieldAllowMultipleInstances => '允许运行多个实例';
	@override String get fieldArgs => '参数';
	@override String get fieldCommand => '命令';
	@override String get fieldCwd => '工作目录';
	@override String get fieldEnv => '环境变量';
	@override String get fieldExecute => '执行方式';
	@override String get fieldExecuteInTerminal => '在终端中执行';
	@override String get fieldFocusToolWindow => '聚焦工具窗口';
	@override String get fieldInterpreterOptions => '解释器选项';
	@override String get fieldInterpreterPath => '解释器路径';
	@override String get fieldInterpreterPathEditTooltip => '编辑解释器路径';
	@override String get fieldScriptOptions => '脚本选项';
	@override String get fieldScriptPath => '脚本路径';
	@override String get fieldScriptText => '脚本内容';
	@override String get fieldShell => '在 Shell 中运行';
	@override String get loadingOutput => '正在加载运行输出…';
	@override String get moreActions => '更多运行操作';
	@override String get newInstance => '新实例';
	@override String get noSessions => '暂无运行会话';
	@override String get openLaunchJson => '打开 launch.json';
	@override String get pickLaunchType => '选择启动类型';
	@override String get refreshDiscover => '刷新发现建议';
	@override String get restart => '重新运行';
	@override String get selectConfiguration => '启动';
	@override String get selectFolder => '选择文件夹';
	@override String get stop => '停止';
	@override String get stopAndClose => '停止并关闭';
	@override String get stopAndDelete => '停止并删除';
	@override String stopSessionMessage({required String name}) => '“${name}”仍在运行。停止并关闭此标签页？';
	@override String get stopSessionTitle => '停止正在运行的会话？';
	@override String suggestedConfiguration({required String name}) => '${name}（建议）';
	@override String get typeShellScript => 'Shell 脚本';
	@override String typeUnavailable({required String type}) => '启动类型“${type}”在此目标上不可用';
	@override String typeUnavailableRemote({required String type}) => '启动类型“${type}”在远程目标上不可用';
	@override String typeUnknown({required String type}) => '未知启动类型：${type}';
	@override String get validationActivateToolWindowMustBeBoolean => '激活工具窗口必须是布尔值';
	@override String get validationAllowMultipleInstancesMustBeBoolean => '允许运行多个实例必须是布尔值';
	@override String get validationArgsMustBeStringList => '参数必须是字符串列表';
	@override String get validationCommandRequired => '命令不能为空';
	@override String get validationConfigurationMustBeMap => '配置必须是对象';
	@override String get validationCwdMustBeString => '工作目录必须是字符串';
	@override String get validationEnvMustBeStringMap => '环境变量必须是字符串映射';
	@override String get validationExecuteInTerminalMustBeBoolean => '在终端中执行必须是布尔值';
	@override String get validationExecuteInvalid => '执行方式必须是脚本文件或脚本内容';
	@override String get validationExecuteRequired => '必须选择执行方式';
	@override String get validationFocusToolWindowMustBeBoolean => '聚焦工具窗口必须是布尔值';
	@override String get validationInterpreterPathMustBeString => '解释器路径必须是字符串';
	@override String get validationScriptPathRequired => '脚本路径不能为空';
	@override String get validationScriptTextRequired => '脚本内容不能为空';
	@override String get validationShellMustBeBoolean => 'Shell 必须是布尔值';
}

// Path: session
class _AppLocalizations$session$zh extends AppLocalizations$session$en {
	_AppLocalizations$session$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get session => '会话';
	@override String get archiveEmpty => '暂无归档会话';
	@override String get archiveEntryTooltip => '归档会话';
	@override String get archiveTitle => '归档';
	@override String get duplicateFailed => '复制对话失败';
	@override String get duplicated => '对话已复制';
	@override String get failedTitle => '未能启动会话';
	@override String get followUpAddPlaceholder => '添加跟进消息';
	@override String get followUpDelete => '删除';
	@override String get followUpEdit => '编辑';
	@override String get followUpMoveUp => '上移';
	@override String followUpQueued({required int count}) => '${count} 排队中';
	@override String get followUpResume => '继续队列';
	@override String get forkFailed => 'Fork 对话失败';
	@override String get groupAddSessionsTitle => '添加会话';
	@override String get groupAddSessionsTooltip => '添加会话';
	@override String get groupCreateTitle => '新建分组';
	@override String get groupCreateTooltip => '新建分组';
	@override String get groupEmpty => '暂无会话';
	@override String get groupMenuRemove => '删除分组';
	@override String get groupNameLabel => '分组名称';
	@override String get groupRenameTitle => '重命名分组';
	@override String get historyBackgroundRunning => '后台任务运行中…';
	@override String get historyComposeHint => '继续对话… @ 引用文件，/ 调用技能与指令';
	@override String get historyComposeStop => '停止生成';
	@override String get historyContinueSaveFailed => '无法保存继续会话设置。';
	@override String get historyEmpty => '该成员暂无历史消息。';
	@override String get historyError => '无法加载对话历史。';
	@override String get historyLoadOlderHint => '上滑查看更早消息';
	@override String get historyLoading => '正在加载对话历史…';
	@override String historyMailboxQueued({required int count}) => '${count} 已排队';
	@override String get historyMailboxQueuedDismiss => '关闭';
	@override String get historyRefreshing => '正在刷新对话…';
	@override String get historyRetry => '重试';
	@override String get historyRoleAssistant => '助手';
	@override String get historyRoleSystem => '系统';
	@override String get historyRoleUser => '你';
	@override String get historyRunning => '运行中…';
	@override String get historySoftReloadError => '无法刷新对话历史。';
	@override String get historyStarting => '启动中…';
	@override String get historyToolTurn => '工具';
	@override String get idleNotificationSubtitle => '可以继续对话了';
	@override String get idleNotificationTitle => 'Agent 已就绪';
	@override String get launchErrorHideDetails => '收起详情';
	@override String get launchErrorReviewDetails => '查看详情';
	@override String get launchMissingTeamMember => '团队成员不可用，请选择团队后重试。';
	@override String get launchMissingWorkspace => '找不到该对话所属的工作区。';
	@override String get openToSide => '在右侧分栏打开';
	@override String get pageSubtitle => '配置 Shell 会话启动方式、终端行为与存储后端。';
	@override String get readyHint => '用日常语言描述你想做的事即可，无需输入命令。';
	@override String readySubtitle({required String memberName}) => '与 ${memberName} 在此工作区中开始对话';
	@override String get readySubtitleGeneric => '在此工作区中开始新对话';
	@override String get readyTitle => '准备开始对话';
	@override String get remoteProvisionFailed => '远程准备失败';
	@override String get remoteProvisionPreparing => '正在准备远程环境…';
	@override String remoteProvisionPreparingOnHost({required String host}) => '正在准备远程环境（${host}）';
	@override String remoteProvisionTitle({required String member, required String host}) => '正在准备 ${member}（${host}）';
	@override String get retryButton => '重试';
	@override String get sortCreatedDesc => '创建时间';
	@override String get sortManual => '手动排序';
	@override String get sortRecentlyUpdated => '最近更新';
	@override String get sortTooltip => '排序对话';
	@override String get startButton => '开始对话';
	@override String get starting => '正在启动会话…';
	@override String get tabBarTitle => '会话标签栏';
	@override String get tabBarVisibilityHint => '在工作台中心列上方显示标签栏。';
	@override String get titleCopySuffix => '（副本）';
	@override String get workbenchViewChat => '聊天';
	@override String get workbenchViewTerminal => '终端';
}

// Path: sessionUsage
class _AppLocalizations$sessionUsage$zh extends AppLocalizations$sessionUsage$en {
	_AppLocalizations$sessionUsage$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get accountAll => '全部账号';
	@override String get autoScan => '自动扫描会话日志';
	@override String autoScanHint({required int minutes}) => '打开本页时立即扫描，之后每 ${minutes} 分钟在后台扫描。';
	@override String cacheHit({required String percent}) => '命中率 ${percent}';
	@override String get cacheRead => '缓存读取';
	@override String cacheReadShare({required String percent}) => '缓存读占比 ${percent}';
	@override String get cacheShort => '缓存';
	@override String cacheWrite({required String tokens}) => '写入 ${tokens}';
	@override String get cancelSync => '取消';
	@override String get cancelSyncTooltip => '取消用量同步';
	@override String get cancelling => '正在取消…';
	@override String chartAverage({required String tokens}) => '日均 ${tokens}';
	@override String get chartSubtitle => '按 CLI 堆叠';
	@override String get chartTitle => '近 7 天消耗';
	@override String chartTotal({required String tokens}) => '合计 ${tokens}';
	@override String get cliAll => '全部';
	@override String get cliBreakdown => 'CLI 分布';
	@override String get columnReset => '恢复默认';
	@override String get columnSettings => '显示的列';
	@override String get cost => '成本';
	@override String costPartial({required int count}) => '部分成本：${count} 条未定价';
	@override String costPricedUnpriced({required int priced, required int unpriced}) => '已定价 ${priced} 条 · 未定价 ${unpriced} 条';
	@override String get costShort => '成本';
	@override String get costUnpriced => '未定价';
	@override String get dataSource => '数据来源';
	@override String get dismiss => '关闭';
	@override String get emptyBody => '运行一次 Claude、Codex 或 OpenCode 会话后点击同步。也可以先清除筛选条件。';
	@override String get emptyTitle => '还没有 Token 用量';
	@override String get endTime => '结束时间';
	@override String get groupBy => '分组';
	@override String get groupCli => 'CLI';
	@override String groupCount({required int count}) => '${count} 组';
	@override String get groupMember => '成员';
	@override String get groupModel => '模型';
	@override String get groupName => '名称';
	@override String get groupSession => '会话';
	@override String get heatmapLess => '少';
	@override String get heatmapMetricHitRate => '命中率';
	@override String get heatmapMetricTokens => 'Token';
	@override String get heatmapMore => '多';
	@override String get heatmapShowEarlier => '显示更早';
	@override String get heatmapShowLess => '收起更早';
	@override String heatmapSpanSummary({required String tokens, required String requests, required String cost}) => '${tokens} Token · ${requests} 请求 · ${cost}';
	@override String get heatmapSubtitle => '近 53 周 · 悬停或长按查看当天明细';
	@override String get heatmapTitle => '用量热力图';
	@override String get inputShort => '输入';
	@override String get inputTokens => '输入';
	@override String intervalMinutes({required int minutes}) => '每 ${minutes} 分钟';
	@override String lastSync({required String time}) => '上次同步 ${time}';
	@override String get liveEnd => '结束时间跟随当前时刻';
	@override String get loadFailed => '无法加载用量数据。';
	@override String get loading => '正在加载用量…';
	@override String get maintenanceCompact => '压缩事件';
	@override String get maintenanceCompactHint => '合并被覆盖的历史修订，保留当前事件。';
	@override String get maintenanceCompacted => '用量存储已压缩。';
	@override String get maintenanceEntry => '存储与 Cursor 维护';
	@override String get maintenanceFailed => '用量存储压缩失败。';
	@override String get maintenanceFull => '全量重扫';
	@override String get maintenanceFullDone => '全量用量重扫完成。';
	@override String get maintenanceFullHint => '重建全部数据源并扫描所有会话；历史缺失时使用。';
	@override String maintenanceLines({required int lines, required int events}) => '${lines} 行 · ${events} 条事件';
	@override String maintenanceSize({required String size}) => '${size} KB';
	@override String get maintenanceTitle => '用量存储';
	@override String get managePricing => '管理定价';
	@override String get mixedCli => '混合';
	@override String get nav => 'Token 用量';
	@override String get neverSynced => '尚未同步';
	@override String get nextPage => '下一页';
	@override String get noData => '暂无数据';
	@override String get outputShort => '输出';
	@override String get outputTokens => '输出';
	@override String pageOf({required int page, required int pages}) => '第 ${page} / ${pages} 页';
	@override String pageRange({required int start, required int end, required int total}) => '第 ${start}–${end} 条 · 共 ${total} 组';
	@override String get prevPage => '上一页';
	@override String get pricingAdd => '新增规则';
	@override String get pricingCacheRead => '缓存读';
	@override String get pricingCacheWrite => '缓存写';
	@override String get pricingCacheWrite1h => '1 小时缓存写';
	@override String get pricingCorrupt => '定价文件无法读取，已使用内置价格。';
	@override String get pricingDelete => '删除';
	@override String get pricingEffectiveDate => '生效日期';
	@override String get pricingEffectiveHint => 'YYYY-MM-DD';
	@override String get pricingEmpty => '没有自定义规则，当前使用内置价格。';
	@override String get pricingFailed => '定价保存失败。';
	@override String get pricingHint => '每百万 token 的美元价格；自定义规则优先于内置参考价。';
	@override String get pricingInput => '输入';
	@override String get pricingInvalid => '请检查模型和价格输入。';
	@override String get pricingModel => '模型';
	@override String get pricingOutput => '输出';
	@override String get pricingReset => '恢复默认';
	@override String get pricingResetConfirm => '移除所有自定义定价规则？';
	@override String get pricingSave => '保存';
	@override String get pricingSaved => '定价已保存';
	@override String get pricingTitle => '模型定价';
	@override String get progressTitle => '用量同步';
	@override String get rangeAll => '全部';
	@override String get rangeFourteenDays => '近 14 天';
	@override String get rangeHint => '支持日期与时间，最长 30 天';
	@override String get rangeInvalidOrder => '开始时间不能晚于结束时间';
	@override String get rangeLast24Hours => '近 24 小时';
	@override String get rangeSevenDays => '近 7 天';
	@override String get rangeThirtyDays => '近 30 天';
	@override String get rangeToday => '今天';
	@override String get rangeTooLong => '时间范围不能超过 30 天';
	@override String get requests => '请求';
	@override String requestsSessions({required int requests, required int sessions}) => '${requests} 请求 · ${sessions} 会话';
	@override String get requestsShort => '请求';
	@override String get resetFilters => '清除筛选';
	@override String get retry => '重试';
	@override String get rowsPerPage => '每页条数';
	@override String get scanInterval => '扫描间隔';
	@override String get scopeHint => '本地 + SSH · 按 TeamPilot 会话归属';
	@override String get searchHint => '搜索会话、成员或模型';
	@override String get sessions => '会话';
	@override String get sessionsShort => '会话';
	@override String get settings => '用量设置';
	@override String share({required String percent}) => '占总用量 ${percent}';
	@override String get shareShort => '占比';
	@override String showing({required int shown, required int total}) => '显示 ${shown} / ${total} 条记录';
	@override String get simpleSeat => '简单会话';
	@override String get sortAscending => '升序';
	@override String get sortDescending => '降序';
	@override String get startTime => '开始时间';
	@override String get storage => '存储';
	@override String get sync => '同步';
	@override String get syncCancelled => '已取消用量同步。';
	@override String get syncFatal => '同步失败，当前显示缓存数据。';
	@override String get syncFull => '全量同步';
	@override String get syncFullHint => '从头重新扫描全部记录';
	@override String get syncIncremental => '增量同步';
	@override String get syncIncrementalHint => '只扫描上次同步后变化的文件';
	@override String get syncNow => '立即同步';
	@override String syncPartial({required int count}) => '${count} 个来源同步失败，当前显示缓存数据。';
	@override String get syncPreparing => '正在准备扫描…';
	@override String syncProgress({required int done, required int total, required int inserted}) => '正在扫描 ${done}/${total} 个会话 · 新增 ${inserted} 条';
	@override String get syncTooltip => '扫描 CLI 记录以获取新用量';
	@override String get syncedJustNow => '刚刚同步';
	@override String get syncedToast => '用量同步完成';
	@override String get syncing => '同步中';
	@override String get tableEmpty => '没有匹配的记录';
	@override String get tableEmptyHint => '换个搜索词，或清除筛选条件。';
	@override String get title => 'Token 用量';
	@override String get today => '今天';
	@override String get totalShort => '总计';
	@override String get totalTokens => '总 Token';
	@override String get unknownModel => '未知模型';
	@override String get unknownSession => '未知会话';
	@override String get unknownTeam => '未归属团队';
}

// Path: shortcuts
class _AppLocalizations$shortcuts$zh extends AppLocalizations$shortcuts$en {
	_AppLocalizations$shortcuts$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get categoryCompose => '输入框';
	@override String get categoryMeta => '通用';
	@override String get categoryNavigation => '导航';
	@override String get categoryRun => '运行';
	@override String get categoryTabs => '标签';
	@override String get categoryView => '视图';
	@override String get categoryZoom => '缩放';
	@override String get changeAction => '更改…';
	@override String get cheatsheetButton => '查看速查表';
	@override String get cheatsheetEmpty => '没有匹配的快捷键。';
	@override String get cheatsheetTitle => '键盘快捷键';
	@override String get composeNewline => '插入换行';
	@override String get composeSubmit => '发送消息';
	@override String get conflictBadgeTooltip => '与另一个快捷键冲突';
	@override String conflictMessage({required String title}) => '已被“${title}”使用。';
	@override String get export => '导出…';
	@override String get exportFailed => '无法导出快捷键。';
	@override String get exportSuccess => '快捷键已导出。';
	@override String get floatingMaximize => '最大化浮动工作区';
	@override String get floatingMinimize => '最小化浮动工作区';
	@override String get floatingNewTerminal => '新建浮动终端';
	@override String get floatingOpenFile => '在浮动工作区打开文件';
	@override String get floatingToggle => '切换浮动工作区';
	@override String get import => '导入…';
	@override String importConflictMessage({required int count}) => '导入的快捷键与 ${count} 个现有绑定冲突。是否替换？';
	@override String get importConflictTitle => '替换冲突的快捷键？';
	@override String get importInvalidFile => '该文件不是有效的快捷键导出文件。';
	@override String get importSuccess => '快捷键已导入。';
	@override String get notSet => '未设置';
	@override String get pageSubtitle => '查看并自定义导航、标签、缩放和输入框的键盘快捷键。';
	@override String get pressShortcutHint => '按下组合键进行绑定。按 Escape 取消，按 Backspace 取消绑定。';
	@override String get pressShortcutTitle => '按下快捷键';
	@override String get pressShortcutUnsupportedKey => '该键无法绑定。';
	@override String get replaceAction => '替换';
	@override String get resetAction => '恢复默认';
	@override String get resetAll => '全部重置';
	@override String get resetAllConfirmMessage => '这会将所有键盘快捷键恢复为默认绑定。';
	@override String get resetAllConfirmTitle => '重置所有快捷键？';
	@override String get runRestart => '重新运行';
	@override String get runSelected => '运行所选配置';
	@override String get runStop => '停止运行';
	@override String get searchHint => '搜索快捷键';
	@override String get sessionCloseTab => '关闭会话标签';
	@override String get sessionNewChat => '新建对话';
	@override String get sessionNewTab => '新建会话标签';
	@override String get settingsTitle => '键盘快捷键';
	@override String get showCheatsheet => '显示键盘快捷键';
	@override String stripFocusTab({required int n}) => '切换到第 ${n} 个标签';
	@override String get stripNextTab => '下一个标签';
	@override String get stripPrevTab => '上一个标签';
	@override String get togglePanel => '切换终端面板';
	@override String get toggleSecondarySidebar => '切换次侧边栏';
	@override String get toggleSidebar => '切换侧边栏';
	@override String get unbindAction => '取消绑定';
	@override String get workbenchFocusNextGroup => '聚焦下一个编辑组';
	@override String get workbenchMoveTabToNextGroup => '将标签页移到下一个编辑组';
	@override String get workbenchSplitDown => '向下拆分编辑组';
	@override String get workbenchSplitReset => '重置编辑组布局';
	@override String get workbenchSplitRight => '向右拆分编辑组';
	@override String get workspaceCloseTab => '关闭工作区标签';
	@override String get workspaceContentSearch => '在文件中查找';
	@override String workspaceFocusTab({required int n}) => '切换到第 ${n} 个工作区';
	@override String get workspaceNextTab => '下一个工作区标签';
	@override String get workspacePrevTab => '上一个工作区标签';
	@override String get workspaceReopenClosed => '重新打开已关闭的工作区标签';
	@override String get workspaceSearch => '搜索工作区（双击 Shift）';
	@override String get zoomIn => '放大';
	@override String get zoomOut => '缩小';
	@override String get zoomReset => '重置缩放';
}

// Path: skills
class _AppLocalizations$skills$zh extends AppLocalizations$skills$en {
	_AppLocalizations$skills$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get add => '添加';
	@override String get cardDetails => '详情';
	@override String get cardInstall => '安装';
	@override String get cardInstalled => '已安装';
	@override String cardStars({required int count}) => '${count} 星';
	@override String get cardUninstall => '卸载';
	@override String get cardUpdate => '更新';
	@override String cardUpdatedAt({required String date}) => '更新于 ${date}';
	@override String get cardView => '查看';
	@override String get catalogAdoption => '安装量';
	@override String get catalogCardNoDescription => '无';
	@override String get checkUpdates => '检查更新';
	@override String get checkingUpdates => '检查中…';
	@override String get detailMissing => '未找到该 skill 的 SKILL.md。';
	@override String get detailReadError => '无法读取 SKILL.md。';
	@override String get discoveryEmpty => '未发现可用 Skill';
	@override String get discoveryEmptyHint => '添加仓库或试用 skills.sh 来发现 Skill。';
	@override String get discoveryErrorTitle => '发现失败';
	@override String get discoverySyncing => '正在后台检查仓库更新并同步 Skill…';
	@override String get enabled => '启用';
	@override String get filterAll => '全部';
	@override String get filterAnyCategory => '全部';
	@override String get filterAnyLanguage => '全部';
	@override String get filterAnyOccupation => '全部';
	@override String get filterCategory => '分类';
	@override String get filterInstalled => '已安装';
	@override String get filterLanguage => '语言';
	@override String get filterOccupation => '职业';
	@override String get filterRepoAll => '所有仓库';
	@override String get filterSortBy => '排序';
	@override String get filterSortByRecent => '最新';
	@override String get filterSortByStars => '星数';
	@override String get filterUninstalled => '未安装';
	@override String get goDiscovery => '前往发现';
	@override String get importFromDisk => '从磁盘导入';
	@override String get importNothing => '未发现未管理的 Skill。';
	@override String importSelected({required int count}) => '导入选中 ${count} 个';
	@override String get importTitle => '导入未管理的 Skill';
	@override String get installFromZip => '从 ZIP 安装';
	@override String installSuccess({required String name}) => '已安装 ${name}';
	@override String installedCount({required int count}) => '已安装 ${count}';
	@override String installs({required int count}) => '${count} 次安装';
	@override String get local => '本地';
	@override String get marketplaceAddRepo => '添加仓库';
	@override String get marketplaceLoadMore => '加载更多';
	@override String get marketplaceRepoAdded => '已添加到仓库源，可在 Repos 页安装具体技能';
	@override String get mpQuotaHint => 'SkillsMP 匿名额度（每天 50 次）已用完。设置免费 API Key 后继续。';
	@override String get navDiscovery => '发现';
	@override String get navInstalled => '已安装';
	@override String get navRegistries => '注册中心';
	@override String get navRepos => '仓库';
	@override String get noInstalled => '还没有安装 Skill';
	@override String get noInstalledHint => '打开发现页安装你的第一个 Skill。';
	@override String get noUpdates => '所有 Skill 均为最新';
	@override String overwriteConfirm({required String name}) => '${name} 已安装。是否覆盖？';
	@override String get registryAddSource => '添加注册源';
	@override String get registryApiKeySet => '已设置 API Key';
	@override String get registryBaseUrlLabel => 'API 地址';
	@override String get registryBrowseQueryLabel => '默认浏览词';
	@override String get registryEditTitle => '编辑注册源';
	@override String get registryGoSetKey => '去注册中心设置 API Key';
	@override String get registryNameLabel => '显示名称';
	@override String get registryNameOfRepoLabel => '仓库名';
	@override String get registryOwnerLabel => 'Owner';
	@override String get registryProtocolLabel => '协议';
	@override String get registryProtocolSkillsMp => 'SkillsMP 兼容';
	@override String get registryProtocolSkillsSh => 'skills.sh 兼容';
	@override String get registryRemoveTitle => '重置注册源';
	@override String registryResetConfirm({required String name}) => '将 ${name} 重置为默认值？';
	@override String get registryRetry => '重试';
	@override String get registrySourceExists => '该注册源已存在';
	@override String get registrySourceKind => '源类型';
	@override String get registrySourceKindApi => 'API 源';
	@override String get registrySourceKindGit => 'Git 仓库';
	@override String registryTestFailed({required String error}) => '连接失败：${error}';
	@override String get registryTestOk => '连接成功';
	@override String get registryTokenLabel => 'API Key';
	@override String get remove => '移除';
	@override String get repoAdd => '添加仓库';
	@override String get repoBranch => '分支';
	@override String get repoInvalidUrl => '请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repo';
	@override String get repoRemove => '移除';
	@override String repoRemoveConfirm({required String name}) => '确认移除仓库 ${name}？';
	@override String get repoSyncing => '更新中';
	@override String get repoUrl => '仓库地址';
	@override String get repoUrlHint => 'https://github.com/owner/repo';
	@override String get searchPlaceholder => '搜索 Skill…';
	@override String get sidebarLabel => 'Skills';
	@override String get subtitle => '管理可安装的 Skill';
	@override String get title => 'Skills';
	@override String uninstallConfirm({required String name}) => '卸载 ${name}？';
	@override String uninstallSuccess({required String name}) => '已卸载 ${name}';
	@override String updateAll({required int count}) => '全部更新 (${count})';
	@override String get updateAvailable => '有新版本';
	@override String updateSuccess({required String name}) => '已更新 ${name}';
	@override String get zipNoSkills => '压缩包中未发现 SKILL.md。';
}

// Path: ssh
class _AppLocalizations$ssh$zh extends AppLocalizations$ssh$en {
	_AppLocalizations$ssh$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get credentialSource => '凭据来源';
	@override String get credentialSourceKeychain => '本机钥匙串';
	@override String get credentialVaultDeleted => '已删除的条目';
	@override String get defaultWorkingDirectorySubtitle => 'SSH 启动没有工作区路径时使用的远端工作目录；留空则不切换目录。';
	@override String get defaultWorkingDirectoryTitle => 'SSH 默认工作目录';
	@override String get homeDisconnectedBannerMessage => '远程 SSH 工作环境已断开。请重新连接后再使用 Shell、Git 和 Agent 会话。';
	@override String get homeDisconnectedReconnect => '重新连接';
	@override String get hostKeyFingerprintLabel => '指纹';
	@override String hostKeyKeyTypeLabel({required String keyType}) => '密钥类型：${keyType}';
	@override String hostKeyMismatchBody({required String host}) => '${host} 的主机密钥与 TeamPilot 先前保存的不一致。可能是系统重装，也可能是连接被劫持。';
	@override String get hostKeyMismatchTitle => 'SSH 主机密钥已变更';
	@override String get hostKeyPreviousFingerprintLabel => '先前信任的指纹';
	@override String get hostKeyReplaceTrust => '替换并信任';
	@override String get hostKeyTrust => '信任并继续';
	@override String hostKeyUnknownBody({required String host}) => 'TeamPilot 尚未见过 ${host}。请确认指纹与该机器一致后再信任。';
	@override String get hostKeyUnknownTitle => '验证 SSH 主机密钥';
	@override String get hostsManage => '管理远程主机';
	@override String get hostsOpenTerminal => '打开终端';
	@override String get hostsOpenTerminalNoWorkspace => '请先打开一个工作区再启动终端。';
	@override String get hostsPanelTitle => '远程主机';
	@override String get hostsPillConnecting => '连接中…';
	@override String get hostsRowKind => 'SSH 主机';
	@override String get migrateToVault => '迁移到保险库';
	@override String get penaltyRefused => '服务器暂时拒绝了连接（触发了防暴力破解保护），请等待约一分钟后重试。';
	@override String get saveToVault => '保存到保险库';
	@override String get serversEmpty => '此主机上还没有保存的 SSH 服务器。';
	@override String get serversNeedsConnectionHint => '本机清单中存在，但尚未在这台设备上建立连接';
	@override String get serversNotConnectedOnDevice => '尚未在这台设备上建立连接';
	@override String get serversLoadError => '无法加载 SSH 服务器，请检查连接后重试。';
	@override String get serversNotConnected => '未连接远程主机。';
	@override String get serversTitle => 'SSH 服务器';
	@override String get vaultBadge => '保险库';
	@override String hostsPillCount({required int count}) => '${count} 台主机';
}

// Path: sshProfile
class _AppLocalizations$sshProfile$zh extends AppLocalizations$sshProfile$en {
	_AppLocalizations$sshProfile$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get connect => '连接';
	@override String connectSuccess({required String host}) => '已连接到 ${host}';
	@override String get delete => '删除';
	@override String get disconnect => '断开';
	@override String get edit => '编辑';
	@override String get formAuthChangeBody => '保存后会清除该目标另一种认证方式已保存的凭据。';
	@override String get formAuthChangeConfirm => '切换并保存';
	@override String get formAuthChangeTitle => '切换认证方式？';
	@override String get formAuthPrivateKey => '私钥';
	@override String get formAuthType => '认证方式';
	@override String get formCredentialRequired => '请提供私钥或密码。';
	@override String get formCredentialSaveFailed => '目标已保存，但无法写入凭据。请解锁系统钥匙环后编辑该目标并重新填写。';
	@override String get formFieldRequired => '必填';
	@override String get formHost => '主机或别名';
	@override String get formHostHint => 'server、deploy@server:2222';
	@override String get formIdentityFile => '私钥内容';
	@override String get formIdentityFileHelper => '可直接粘贴私钥，或从文件导入。';
	@override String get formIdentityFileHint => '-----BEGIN OPENSSH PRIVATE KEY-----';
	@override String get formIdentityFileImport => '从文件导入';
	@override String get formIdentityFileImportFailed => '无法读取所选文件，请直接粘贴私钥';
	@override String get formLabel => '标签';
	@override String get formLabelHint => '我的服务器';
	@override String get formPassphrase => '密钥口令';
	@override String get formPassphraseHint => '可选';
	@override String get formPassword => '密码';
	@override String get formPasswordHint => '登录密码';
	@override String get formPasswordHintEdit => '留空则保留已保存密码';
	@override String get formPort => '端口';
	@override String get formPortInvalid => '端口须在 1–65535 之间';
	@override String get formTitleEdit => '编辑 SSH 目标';
	@override String get formTitleNew => '新的 SSH 目标';
	@override String get formUsername => '用户名';
	@override String get formUsernameHint => 'deploy';
	@override String get refresh => '刷新';
	@override String get selectorManage => '管理 SSH 服务器…';
	@override String get selectorTooltip => '切换 SSH 服务器';
	@override String get statusAuthFailed => '认证失败';
	@override String get statusConnected => '已连接';
	@override String get statusConnecting => '连接中…';
	@override String get statusDisconnected => '未连接';
	@override String get statusError => '错误';
	@override String get statusReconnecting => '重连中…';
	@override String get test => '测试';
	@override String get testFailed => '连接测试失败';
	@override String testFailedAborted({required String detail}) => '登录前连接已断开：${detail}';
	@override String get testFailedAuth => '身份验证失败';
	@override String testFailedDetail({required String detail}) => '连接测试失败：${detail}';
	@override String get testFailedHostKey => '主机密钥未获信任';
	@override String get testSuccess => '连接成功';
	@override String get sAddTarget => '添加目标';
	@override String get sEmpty => '尚未配置 SSH 目标。';
	@override String get sImport => '导入';
	@override String get sImportUnavailable => '暂不支持从 ~/.ssh/config 导入。';
	@override String get sPageSubtitle => '当前主目录所在主机上保存的 SSH 服务器配置；配对了同一主目录的设备共享这份清单。';
	@override String get sPageTitle => '远程 SSH 服务器';
	@override String get sSettingsTitle => 'SSH 服务器';
	@override String get sTargetsSubtitle => '添加远程主机以在 TeamPilot 中连接到它。';
	@override String get sTargetsTitle => '目标';
}

// Path: team
class _AppLocalizations$team$zh extends AppLocalizations$team$en {
	_AppLocalizations$team$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get cliComingSoon => '即将支持';
	@override String get cliLabel => 'CLI 后端';
	@override String get cliLockedSubtitle => '在创建团队时已选定。';
	@override String get cliSubtitle => '创建团队时选定，之后不可更改。';
	@override String get config => '团队配置';
	@override String get configAspectCli => 'CLI';
	@override String get configAspectDefaultProvider => '默认服务商';
	@override String get configAspectModel => '模型';
	@override String get configAspectProvider => '服务商';
	@override String get configAspectSeparator => '、';
	@override String get configGroupTeamDefault => '团队默认';
	@override String configIncompleteBody({required String team}) => '团队“${team}”缺少启动所需的配置。会话仍会启动，但缺少这些配置时智能体可能无法正常工作：';
	@override String get configIncompleteDismiss => '稍后';
	@override String get configIncompleteGoConfigure => '前往配置';
	@override String get configIncompleteTitle => '团队配置不完整';
	@override String configIssueSemanticLabel({required String subject, required String aspects}) => '${subject}缺少：${aspects}';
	@override String get defaultCliMixedSubtitle => '成员未指定时使用。';
	@override String get defaultDialogEffortSubtitle => '团队默认力度。';
	@override String get defaultPresetChange => '更改';
	@override String get defaultPresetLabel => '默认模型预设';
	@override String get defaultPresetManage => '管理';
	@override String get defaultPresetNone => '无';
	@override String get defaultPresetSubtitle => '可选的默认预设，未单独设置的成员将继承此配置。';
	@override String get description => '团队描述';
	@override String get descriptionHint => '可选，写入 Claude roster 的 description 字段';
	@override String get effortLevel => '推理力度';
	@override String get effortLevelSubtitle => '团队默认力度（Claude effortLevel / Codex model_reasoning_effort）。';
	@override String get extensionEffectiveOff => '本团队未启用';
	@override String get extensionEffectiveOn => '本团队已启用';
	@override String get extensionFollowGlobal => '跟随全局';
	@override String get extensionForceOff => '关闭';
	@override String get extensionForceOn => '开启';
	@override String get extensionsNav => '扩展';
	@override String get extensionsSubtitle => '覆盖本团队启用哪些扩展，默认跟随全局设置。';
	@override String get extensionsTitle => '本团队的扩展';
	@override String get extraArgs => '团队额外 CLI 参数';
	@override String get extraArgsHint => '--permission-mode acceptEdits';
	@override String get forceWaitBeforeStopSubtitle => '开启后,成员结束一个回合时会被推回 wait_for_message 而不是停止,从而持续待命接收新消息和任务。关闭则允许成员“休息”(正常停止)。';
	@override String get forceWaitBeforeStopTitle => '让成员保持在等待循环';
	@override String get genApplied => '草稿已应用，创建前请检查调整。';
	@override String get genButton => '生成';
	@override String get genDescriptionHint => '描述你想要的团队（例如：做 Flutter 前端、需要代码审查和测试）';
	@override String get genFailed => '无法生成团队，请手动编辑。';
	@override String get genNoProvider => '请先在 设置 → AI 功能 中配置 AI provider。';
	@override String get genTitle => '用 AI 生成';
	@override String get generateAddModel => '添加模型配置';
	@override String get generateBuilderTitle => '团队构建器';
	@override String get generateCancel => '取消生成';
	@override String get generateCancelBody => '临时会话和暂存资源将被移除。';
	@override String get generateCancelTitle => '取消团队生成？';
	@override String get generateCapabilityNote => '团队构建器将检查工作区机器，并可能为生成的团队获取技能、插件和 MCP 服务器。';
	@override String get generateContinueSetup => '继续配置';
	@override String get generateDeliveryArrived => '已收到';
	@override String get generateDeliveryRetryBody => '负责人可能会收到两次任务。';
	@override String get generateDeliveryRetryTitle => '再次发送任务？';
	@override String get generateDeliverySendAgain => '再次发送…';
	@override String get generateDescription => '强项与适用场景';
	@override String get generateEmptyPool => '还没有配置。请先添加最强的一项。';
	@override String get generateErrorAiNotConfigured => '请先配置生成模型。';
	@override String get generateErrorDescriptionRequired => '请先描述需要团队处理的任务。';
	@override String get generateErrorGeneratorUnsupported => '生成 CLI 必须支持会话、技能和 MCP。';
	@override String get generateErrorNativeUnsupported => '所选 CLI 不支持原生团队。';
	@override String get generateErrorPoolEmpty => '请至少添加一个有效的模型配置。';
	@override String get generateErrorPromptDeliveryUnknown => 'TeamPilot 无法确认负责人是否已收到任务。';
	@override String get generateErrorRecoveryIntegrity => '无法验证恢复数据，临时会话已保留。';
	@override String get generateErrorStagingUnsupported => '此资源需要人工安装，无法安全暂存。';
	@override String get generateErrorStartFailed => '无法启动团队生成。请重试。';
	@override String get generateErrorTargetUnavailable => '所需机器或 CLI 当前不可用。';
	@override String get generateErrorUnavailable => '团队生成当前不可用。请重启 TeamPilot 后重试。';
	@override String get generateErrorUserActionRequired => '请完成所需的登录或配置，然后重试。';
	@override String get generateGeneratorModel => '生成模型';
	@override String generateHiddenPresets({required int count}) => '${count} 个配置因使用其他 CLI 而隐藏。';
	@override String get generateLaunch => '生成并启动';
	@override String get generateLoading => '正在加载设置…';
	@override String get generateMinimumMemberCount => '团队最少成员数';
	@override String get generateMinimumMemberCountHint => '生成的团队至少包含这么多不同的角色。';
	@override String get generateMinimumMemberCountInvalid => '最少需要 3 名成员。';
	@override String generateMissingPreset({required String presetId}) => '预设“${presetId}”已不存在。';
	@override String get generateMixed => '混合';
	@override String get generateModelPool => '模型配置池';
	@override String get generateModelPoolHint => '排名 1 最强。关键角色（如 team-lead）优先用靠前的配置。';
	@override String get generateMoveDown => '下移';
	@override String get generateMoveUp => '上移';
	@override String get generateNative => '原生';
	@override String get generateNativeCli => '原生 CLI';
	@override String get generateOpenLeadSession => '打开负责人会话';
	@override String get generateOpenSettings => '打开生成设置';
	@override String get generatePickPreset => '选择预设';
	@override String get generateRemove => '移除';
	@override String get generateRetainBuilderSession => '保留团队构建 Session 以便排错';
	@override String get generateRetainBuilderSessionHint => '开启后仍会正常打开生成的团队，但会保留构建 Session，方便查看团队生成过程。';
	@override String get generateRetry => '重试';
	@override String get generateSettingsSubtitle => '设定团队构建器如何规划阵容，以及可分配的模型配置。';
	@override String get generateSettingsTitle => '生成并启动设置';
	@override String get generateTags => '标签';
	@override String get generateTeamMode => '团队模式';
	@override String hooksAssignedCount({required int assigned, required int total}) => '已启用 ${assigned}/${total}';
	@override String get hooksManage => '管理 Hooks';
	@override String get hooksNav => 'Hooks';
	@override String get leadBadge => 'Leader';
	@override String get leadDelegateOnlySubtitle => '开启后将禁止队长使用一些工具。';
	@override String get leadDelegateOnlyTitle => '队长仅规划分派';
	@override String get leadNameRequired => 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。';
	@override String get leadNotice => 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。';
	@override String get loop => '阶段循环';
	@override String get loopDefault => '默认';
	@override String get loopFalse => 'false — 每阶段确认';
	@override String get loopSubtitle => '团队模式：true 自动推进阶段；false 需你确认后再继续。';
	@override String get loopTrue => 'true — 自动推进';
	@override String mcpAssignedCount({required int assigned, required int total}) => '已启用 ${assigned}/${total}';
	@override String get mcpManage => '管理 MCP';
	@override String get mcpNav => 'MCP';
	@override String get modeLabel => '团队模式';
	@override String get modeMixed => '混合（跨 CLI bus）';
	@override String get modeMixedDescription => '不同成员可使用不同 CLI，通过 TeamBus 跨工具协作。';
	@override String get modeMixedTitle => '混合模式';
	@override String get modeNative => '原生（单 CLI）';
	@override String get modeNativeDescription => '全部成员共用同一个 CLI，原生协同，配置简单。';
	@override String get modeNativeTitle => '原生模式';
	@override String get modeRequired => '请先选择团队模式。';
	@override String get name => '团队名称';
	@override String nameAlreadyExists({required String name}) => '已存在名为「${name}」的团队。';
	@override String get nameRequired => '团队名称不能为空。';
	@override String pluginsAssignedCount({required int assigned, required int total}) => '已安装 ${assigned}/${total}';
	@override String get pluginsCliUnsupportedBanner => '当前团队 CLI 暂不支持插件，启用记录已保存但不会生效。';
	@override String get pluginsEmpty => '尚未安装插件';
	@override String get pluginsEmptyHint => '在「发现」中安装插件后，可在此处按团队启用。';
	@override String get pluginsGoDiscovery => '浏览 marketplace';
	@override String get pluginsManage => '全部插件';
	@override String pluginsMissing({required int count}) => '有 ${count} 个已启用插件在磁盘上缺失，重新安装或手动移除。';
	@override String get pluginsMissingLabel => '磁盘上缺失';
	@override String pluginsNameConflict({required String dir}) => '因名称冲突，已链接为 ${dir}';
	@override String get pluginsNav => '插件';
	@override String get pluginsRemoveMissing => '移除';
	@override String get sessions => '团队会话';
	@override String get settings => '团队设置';
	@override String get settingsSubtitle => '团队代理';
	@override String skillsAssignedCount({required int assigned, required int total}) => '已启用 ${assigned}/${total}';
	@override String get skillsManage => '全部 Skills';
	@override String get skillsNav => 'Skills';
}

// Path: teamHub
class _AppLocalizations$teamHub$zh extends AppLocalizations$teamHub$en {
	_AppLocalizations$teamHub$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get alreadyAdded => '已添加';
	@override String get browseAll => '浏览全部团队';
	@override String get cardNoDescription => '无';
	@override String get categoryAll => '全部';
	@override String get clone => '克隆为我的团队';
	@override String get cloneFailed => '无法克隆该团队。';
	@override String get cloneOptionsTitle => '克隆选项';
	@override String clonePartial({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount, required int failedCount, required Object failedNames}) => '已克隆「${name}」。已安装 ${skillCount} 个 Skill、${pluginCount} 个插件、${mcpCount} 个 MCP 服务,克隆了 ${expertCount} 个专家;${failedCount} 个未能安装:${failedNames}。';
	@override String cloneSuccess({required Object name}) => '已克隆「${name}」。';
	@override String cloneSuccessWithDeps({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount}) => '已克隆「${name}」。已安装 ${skillCount} 个 Skill、${pluginCount} 个插件、${mcpCount} 个 MCP 服务,并克隆了 ${expertCount} 个专家。';
	@override String get cloning => '正在克隆…';
	@override String get confirmSelection => '确认';
	@override String get depInstalled => '已安装';
	@override String get depToInstall => '将安装';
	@override String get discovery => '发现';
	@override String get emptyHint => '点击刷新从注册表拉取团队。';
	@override String get emptyTitle => '暂无公开团队';
	@override String get favorites => '我的收藏';
	@override String get favoritesEmptyHint => '点击团队上的星标即可收藏到这里。';
	@override String get favoritesEmptyTitle => '暂无收藏';
	@override String get loadError => '无法加载公开团队。';
	@override String get mcpLabel => 'MCP';
	@override String get membersLabel => '成员';
	@override String get nav => '团队中心';
	@override String get notFound => '未找到该团队。';
	@override String get pluginsLabel => '插件';
	@override String get refresh => '刷新';
	@override String get searchHint => '搜索公开团队';
	@override String get skillsLabel => '技能';
	@override String get sortName => '名称';
	@override String get sortUpdated => '最近更新';
	@override String get subtitle => '发现更多公开团队';
	@override String get title => '团队中心';
}

// Path: terminal
class _AppLocalizations$terminal$zh extends AppLocalizations$terminal$en {
	_AppLocalizations$terminal$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get clear => '清除终端';
	@override String get copySelectHint => '按住 Shift 选择复制';

	/// Shown when a dragged file lives on a different machine than the terminal it was dropped on.
	@override String get dropCrossMachineRejected => '无法将本地文件拖入远程终端';

	@override String get exportScrollback => '导出滚动缓冲…';
	@override String get find => '在终端中查找';
	@override String get findNoResults => '无匹配';
	@override String get linkClickOpensInAppDescription => '左键点击链接和文件路径时在 TeamPilot 内打开，而不是交给正在运行的程序。Ctrl/Cmd+点击始终在应用内打开。';
	@override String get linkClickOpensInAppTitle => '在应用内打开终端链接';
	@override String get openLink => '打开链接';
	@override String get parkedSendDismiss => '关闭';
	@override String parkedSendPending({required String content}) => '已发送，等待接收：${content}';
	@override String get scrollbackLinesDescription => '每个会话终端保留的最大行数';
	@override String get scrollbackLinesTitle => '终端滚动缓冲行数';
	@override String get themeModeDescription => '跟随主题色或使用固定风格';
	@override String get themeModeTitle => '终端主题';
}

// Path: termux
class _AppLocalizations$termux$zh extends AppLocalizations$termux$en {
	_AppLocalizations$termux$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get disconnectedBannerMessage => 'Termux 已断开连接。请重新连接后再使用 Shell、Git 和 Agent 会话。';
	@override String get disconnectedReconnect => '重新连接';
	@override String get disconnectedWorkOpsBlocked => 'Termux 已断开连接。请通过顶部横幅重新连接后再试。';
	@override String get setupClearConfirmAction => '清除设置';
	@override String get setupClearConfirmBody => '将删除已保存的 Termux 密钥和用户名，需要重新完成 Termux 设置。';
	@override String get setupClearConfirmTitle => '清除 Termux 设置？';
	@override String get setupClearSetup => '清除设置';
	@override String get setupConnect => '连接';
	@override String get setupConnectFailed => '无法连接到 Termux';
	@override String setupConnectFailedWithDetail({required String detail}) => '无法连接到 Termux：${detail}';
	@override String get setupConnectSuccess => '已连接到 Termux';
	@override String get setupConnecting => '正在连接…';
	@override String get setupDownloadFailed => '无法下载 Termux。请重试或使用应用商店链接。';
	@override String get setupDownloadInstall => '下载并安装 Termux';
	@override String get setupDownloading => '正在下载 Termux…';
	@override String get setupInstallDenied => '安装已取消或被阻止。如需要请启用未知来源应用，然后重试。';
	@override String get setupInstallFDroid => 'F-Droid';
	@override String get setupInstallGitHub => 'GitHub';
	@override String get setupInstallPlayStore => 'Play 商店';
	@override String get setupInstalling => '正在安装…';
	@override String get setupIntro => '安装 Termux，粘贴一条配置脚本，然后连接 TeamPilot 的本地 SSH 服务。';
	@override String get setupScriptHint => '弹出存储授权时请允许。脚本会用 termux-services 启用 sshd（打开 Termux 即启动）。若需开机且不打开 Termux，可另装 Termux:Boot（F-Droid）。最后一行会打印用户名（例如 u0_a399）。';
	@override String get setupStepInstallTermux => '1. 安装 Termux';
	@override String get setupStepRunScript => '2. 在 Termux 中粘贴这条脚本';
	@override String get setupTermuxInstalled => 'Termux 已安装';
	@override String get setupTitle => 'Termux 设置';
	@override String get setupUsernameError => '请输入有效的 Termux 用户名（以 u 开头）';
	@override String get setupUsernameHint => '例如 u0_a399';
	@override String get setupUsernameLabel => '3. 粘贴 Termux 用户名';
}

// Path: theme
class _AppLocalizations$theme$zh extends AppLocalizations$theme$en {
	_AppLocalizations$theme$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get theme => '主题';
	@override String get colorPresetDescription => '用于按钮、开关与高亮的主色与强调色。';
	@override String get colorPresetTitle => '主题色';
	@override String get dark => '深色';
	@override String get light => '浅色';
	@override String get modeDescription => '浅色、深色，或与系统外观一致。';
	@override String get modeTitle => '主题模式';
	@override String get presetAmber => '琥珀';
	@override String get presetForest => '森林';
	@override String get presetGraphite => '石墨';
	@override String get presetOcean => '海洋';
	@override String get presetViolet => '紫罗兰';
	@override String get system => '跟随系统';
}

// Path: tool
class _AppLocalizations$tool$zh extends AppLocalizations$tool$en {
	_AppLocalizations$tool$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get categoryAskUser => '询问用户';
	@override String get categoryBrowser => '浏览器';
	@override String get categoryCommand => 'Shell 命令';
	@override String get categoryEdit => '编辑文件';
	@override String get categoryMcp => 'MCP';
	@override String get categoryOther => '其他';
	@override String get categoryPlan => '计划';
	@override String get categoryRead => '读取文件';
	@override String get categorySearch => '网络搜索';
	@override String get categorySubagent => '子代理';
	@override String get categoryTask => '任务与待办';
	@override String get categoryWrite => '写入文件';
	@override String get placement => '工具栏位置';
	@override String get placementDescription => '将工具面板固定在右侧或沿底部边缘排列。';
}

// Path: typography
class _AppLocalizations$typography$zh extends AppLocalizations$typography$en {
	_AppLocalizations$typography$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get scaleComfortable => '宽松';
	@override String get scaleCompact => '紧凑';
	@override String get scaleCustom => '自定义';
	@override String get scaleCustomHint => '50–200';
	@override String get scaleCustomLabel => '缩放比例';
	@override String get scaleDescription => '界面文字大小。「标准」跟随系统；不改变图标与间距。';
	@override String get scaleStandard => '标准';
	@override String get scaleTitle => '文字大小';
}

// Path: vault
class _AppLocalizations$vault$zh extends AppLocalizations$vault$en {
	_AppLocalizations$vault$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get cancel => '取消';
	@override String get copied => '已复制';
	@override String get copy => '复制';
	@override String get deleteConfirm => '删除';
	@override String get deleteReferenced => '该条目仍被以下位置使用：';
	@override String get deleteTitle => '删除条目？';
	@override String get disableEncryption => '停用加密保险库';
	@override String get emptyHint => '在这里保存 SSH 密码、私钥或供应商 API Key。';
	@override String get emptyTitle => '还没有条目';
	@override String get enableEncryption => '启用加密保险库';
	@override String get entryFavorite => '收藏';
	@override String get entryNotes => '备注';
	@override String get entryTags => '标签（逗号分隔）';
	@override String get entryTitle => '标题';
	@override String get entryType => '类型';
	@override String get hide => '隐藏';
	@override String get homeOfflineHint => '未连接远程主机，保存在该主机上的业务凭据暂时不可用，重连后即可查看。';
	@override String get lock => '立即锁定';
	@override String get lockedQueryBlocked => '请先解锁保险库再查询用量。';
	@override String get lockedSaveBlocked => '请先解锁保险库再保存凭据。';
	@override String get newEntry => '新建条目';
	@override String get noReferences => '尚未被引用';
	@override String get onlyCopy => '仅复制';
	@override String get pageSubtitle => 'SSH 密码、私钥与供应商 API Key';
	@override String get pageTitle => '保险库';
	@override String get passphrase => '主密码';
	@override String get passphraseConfirm => '确认主密码';
	@override String get passphraseMismatch => '两次输入的密码不一致';
	@override String get passphraseRequired => '请输入主密码';
	@override String get references => '被引用';
	@override String get reveal => '显示';
	@override String get save => '保存';
	@override String get searchHint => '搜索标题、字段或标签';
	@override String get statusEncrypted => '加密保险库 · 已锁定';
	@override String get statusKeychain => '系统钥匙串 · 无需解锁';
	@override String get statusUnlocked => '加密保险库 · 已解锁';
	@override String get storedInVault => '已存入保险库';
	@override String get typeApiKey => '供应商 API Key';
	@override String get typeCustom => '自定义';
	@override String get typeLogin => '账号密码';
	@override String get typeSecureNote => '安全笔记';
	@override String get typeSshPassword => 'SSH 密码';
	@override String get typeSshPrivateKey => 'SSH 私钥';
	@override String get typeToken => '令牌';
	@override String get unavailable => '凭据保险库不可用。';
	@override String get unlock => '解锁';
	@override String get unlockFailed => '解锁失败';
	@override String get unlockTitle => '解锁保险库';
	@override String get wrongPassphraseHint => '密码错误或文件损坏，数据未被修改。';
}

// Path: workspace
class _AppLocalizations$workspace$zh extends AppLocalizations$workspace$en {
	_AppLocalizations$workspace$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get additionalDirectories => '附加目录';
	@override String get advancedSettings => '高级配置';
	@override String get advancedSettingsSubtitle => 'Agent 预设与本成员的额外 CLI 参数。';
	@override String get agentBuiltInSubtitle => '当前 CLI 为 flashskyai 时，对应其 --agent 参数。';
	@override String get agentExtraArgs => '额外 CLI 参数';
	@override String get agentExtraArgsSubtitle => '附加在本工作区 Agent 启动时的 CLI 参数。';
	@override String get agentPromptPresetDeveloper => '开发';
	@override String get agentPromptPresetDeveloperText => '专注实现功能与修复问题。优先小 diff，跑相关测试，并简要说明改了哪些文件及原因。';
	@override String get agentPromptPresetGeneral => '通用';
	@override String get agentPromptPresetGeneralText => '全面协助完成本工作区中的开发任务。先理解需求与现有代码，再给出清晰方案并实施；优先小范围改动，完成后说明涉及文件与后续建议。';
	@override String get agentPromptPresetResearcher => '调研';
	@override String get agentPromptPresetResearcherText => '只调研并汇报，除非被要求否则不要改生产代码。\n输出需含文件路径、相关符号与建议的下一步。';
	@override String get agentPromptPresetReviewer => '审查';
	@override String get agentPromptPresetReviewerText => '只做代码审查，除非被要求否则不要改文件。\n每条意见需包含：文件路径、行号、问题、建议改法。';
	@override String get agentPromptSubtitle => '编写系统提示词，定义 Agent 在本工作区中的职责与行为边界。';
	@override String get chatLandingAttach => '附加文件';
	@override String get chatLandingBackToWorkbench => '返回工作台';
	@override String get chatLandingConnectApps => '连应用';
	@override String get chatLandingCustomLaunch => '自定义…';
	@override String get chatLandingCustomLaunchTitle => '自定义启动';
	@override String get chatLandingInputHint => '今天帮你做些什么？ @ 引用对话文件，/ 调用技能与指令';
	@override String get chatLandingModeSimple => '简单对话';
	@override String get chatLandingModeTeam => '团队';
	@override String get chatLandingSelectLaunchDirectory => '选择目录 >';
	@override String get chatLandingSelectProject => '选择项目 >';
	@override String get chatLandingSelectWorkspace => '选择工作空间 >';
	@override String get chatLandingSelectWorktree => '选择 worktree >';
	@override String get chatLandingSkills => '技能';
	@override String get chatLandingTeamLaunchBlocked => '请先在团队设置中配置团队与成员的模型预设，再发送消息。';
	@override String get chatLandingUsePreset => '使用预设';
	@override String get chatLandingVoice => '语音输入';
	@override String get chatLandingVoiceCancel => '取消录音';
	@override String get chatLandingVoiceMacOsIdeLaunch => '从 IDE 启动时 macOS 不会把语音识别权限授予 TeamPilot。请直接运行 build/macos/Build/Products/Debug/TeamPilot.app，或在 Xcode 中启动。';
	@override String get chatLandingVoicePermissionDenied => '未获得麦克风权限';
	@override String get chatLandingVoiceStop => '停止录音';
	@override String get chatLandingVoiceUnavailable => '此设备不支持语音输入';
	@override String get cliAddPresetTitle => '添加预设';
	@override String cliConfigSummary({required String provider, required String model}) => '${provider} · ${model}';
	@override String get cliConfigure => '配置';
	@override String get cliConfigured => '已配置';
	@override String get cliDefaultSubtitle => '本工作区新建对话时使用的默认 CLI。';
	@override String get cliDefaultsSubtitle => '为本工作区使用的每个 CLI 设置默认提供商与模型。';
	@override String get cliDefaultsTitle => 'CLI 默认配置';
	@override String cliDeletePresetConfirm({required String name}) => '删除预设\'${name}\'？此操作不可撤销。';
	@override String get cliDeletePresetTitle => '删除预设';
	@override String get cliEditPresetTitle => '编辑预设';
	@override String get cliEffortInheritHint => '使用提供商默认';
	@override String get cliEffortLevel => '推理力度';
	@override String get cliEffortLevelSubtitle => '本工作区使用该 CLI 时的默认力度（留空则使用提供商默认）。';
	@override String get cliManagePresets => '管理';
	@override String get cliNoPresetHint => '未选择预设';
	@override String get cliNoProviderCatalog => '此 CLI 无需配置提供商';
	@override String get cliNotConfigured => '未配置';
	@override String get cliNotConfiguredHint => '选择提供商';
	@override String get cliPresetLabel => '当前预设';
	@override String get cliPresetNameLabel => '预设名称';
	@override String get cliPresetsEmptyHint => '还没有预设，创建一个开始使用';
	@override String get cliPresetsManageTitle => '管理预设';
	@override String get cliProviderConfig => '供应商配置';
	@override String get cliProviderModelTitle => '提供商与模型';
	@override String get createdAt => '创建时间';
	@override String get deadTargetBadge => '机器不可用';
	@override String get deadTargetRemap => '重新映射…';
	@override String deadTargetRemapBody({required String from}) => '将 ${from} 替换为另一台机器。目录路径不会改动，目标机器上必须已有相同路径。';
	@override String get deadTargetRemapConfirm => '重新映射';
	@override String get deadTargetRemapFailed => '无法重新映射机器。';
	@override String get deadTargetRemapFromLaunch => '重新映射机器…';
	@override String get deadTargetRemapNothing => '没有可映射的目标。';
	@override String get deadTargetRemapPickFrom => '失效机器';
	@override String get deadTargetRemapPickTo => '替换为';
	@override String get deadTargetRemapTitle => '重新映射机器';
	@override String get details => '工作区详情';
	@override String get directoryAdded => '已添加目录到工作区';
	@override String get directoryAlreadyAdded => '该目录已在工作区中。';
	@override String get directoryAlreadyPrimary => '该路径已是工作区主目录。';
	@override String get displayName => '显示名称';
	@override String get entryModeDescription => 'App 启动后默认打开的页面。';
	@override String get entryModeHome => '主页';
	@override String get entryModeLastWorkspace => '恢复上次工作区';
	@override String get entryModeTitle => '启动视图';
	@override String get extensionEffectiveOff => '本工作区未启用';
	@override String get extensionEffectiveOn => '本工作区已启用';
	@override String get extensionsSubtitle => '覆盖本工作区启用哪些扩展，默认跟随全局设置。';
	@override String get extensionsTitle => '本工作区的扩展';
	@override String get folderPathLabel => '目录';
	@override String get folderTargetLabel => '所在机器';
	@override String get foldersAddOnAnotherMachine => '添加其他主机目录';
	@override String get foldersApplyAllLocal => '全部设为本地';
	@override String get foldersApplyAllRemote => '全部设为远程…';
	@override String get foldersChangeTarget => '更换';
	@override String get foldersEditorHint => '每个目录单独指定所在机器与路径。全部本地 = 本地工作区；全部同一远程 = 项目远程；跨机 = 混合工作区（成员远程）。';
	@override String get foldersPersonalTargetsLockedHint => '个人身份下无法更改目录所在机器。请切换到团队身份配置机器与目录。';
	@override String get foldersPickMixedTarget => '添加到机器';
	@override String get foldersPickPath => '选择目录';
	@override String get foldersPickRemoteTarget => '选择远程机器';
	@override String get foldersPickTarget => '选择机器';
	@override String get foldersSectionTitle => '工作区目录与机器';
	@override String hooksAssignedCount({required int assigned, required int total}) => '已为本工作区启用 ${assigned}/${total}';
	@override String get hooksManage => '管理 Hooks';
	@override String get icon => '图标';
	@override String get iconPickerTitle => '选择工作区图标';
	@override String get iconUpload => '上传图标';
	@override String get iconUploadFailed => '无法保存图标，请使用 PNG、JPG、WEBP 或 SVG。';
	@override String get iconUseDefault => '使用默认';
	@override String mcpAssignedCount({required int assigned, required int total}) => '已为本工作区启用 ${assigned}/${total}';
	@override String get mcpManage => '管理 MCP';
	@override String get noAdditionalDirectories => '暂无附加目录';
	@override String pluginsAssignedCount({required int assigned, required int total}) => '已为本工作区选用 ${assigned}/${total}';
	@override String get pluginsEmpty => '尚未安装插件';
	@override String get pluginsEmptyHint => '在「发现」中安装插件后，可在此处为本工作区启用。';
	@override String get pluginsManage => '管理插件';
	@override String get primaryPath => '主目录';
	@override String get primaryPathNotSelected => '尚未选择主目录';
	@override String get primaryPathRequired => '请先选择主目录。';
	@override String get runningSessionsSection => '已打开';
	@override String searchBackend({required String backend}) => '引擎：${backend}';
	@override String get searchCancel => '取消';
	@override String get searchCaseSensitive => '大小写';
	@override String get searchContent => '内容';
	@override String get searchEmptyHint => '输入以搜索文件内容';
	@override String get searchError => '搜索失败——请检查正则';
	@override String get searchExcludeHint => '排除 (glob，逗号分隔)';
	@override String get searchFilesEmptyHint => '输入关键词搜索文件';
	@override String get searchFilesSection => '文件';
	@override String get searchFilesToExclude => '排除的文件：';
	@override String get searchFilesToInclude => '包含的文件：';
	@override String get searchFilterAll => '全部';
	@override String get searchFilterConversations => '任务';
	@override String get searchFilterFiles => '文件';
	@override String get searchGitignore => '.gitignore';
	@override String get searchHint => '搜索会话、文件和会话内容';
	@override String get searchIncludeHint => '包含 (glob，逗号分隔)';
	@override String get searchIndexing => '正在索引…';
	@override String get searchNoResults => '没有匹配结果';
	@override String get searchPanel => '搜索';
	@override String get searchQueryHint => '搜索文件';
	@override String get searchRecentSessions => '最近会话';
	@override String get searchRegex => '正则';
	@override String get searchReplace => '替换';
	@override String get searchReplaceAll => '全部替换';
	@override String searchReplaceAllMessage({required int count}) => '替换 ${count} 处匹配？';
	@override String get searchReplaceAllTitle => '全部替换？';
	@override String get searchReplaceHint => '替换为';
	@override String searchReplacedCount({required int count}) => '已替换 ${count} 处';
	@override String searchResultSummary({required int matches, required int files}) => '${matches} 个结果 · ${files} 个文件';
	@override String get searchSearching => '正在搜索文件…';
	@override String get searchShowMore => '查看更多结果';
	@override String searchSliceError({required String directory}) => '「${directory}」目录搜索失败';
	@override String get searchTitle => '搜索';
	@override String get searchToggleDetails => '展开搜索选项';
	@override String get searchTruncated => '结果过多已截断——请细化查询';
	@override String get searchUseGitignore => '使用 .gitignore 设置';
	@override String get sessionCount => '会话数';
	@override String get sidebarGroupsView => '分组';
	@override String get sidebarProjectTreeView => '项目树';
	@override String skillsAssignedCount({required int assigned, required int total}) => '已为本工作区启用 ${assigned}/${total}';
	@override String get skillsManage => '管理 Skills';
	@override String get targetSubtitle => '该工作区的目录所在并运行的机器。会话在此 target 上启动；切换不会移动文件。';
	@override String get targetTitle => '工作区所在机器';
	@override String get terminal => '终端';
	@override String get terminalClose => '关闭终端面板';
	@override String get terminalCloseSession => '关闭终端';
	@override String get terminalNewSession => '新建终端';
	@override String get terminalNewSessionMenu => '新建终端会话菜单';
	@override String get terminalNewSshSession => '新建 SSH 会话…';
	@override String get terminalNoWorkingDirectory => '请先连接会话以打开 Shell 终端';
	@override String get terminalRestoring => '正在恢复终端…';
	@override String get terminalSettings => '设置';
	@override String get terminalSshConnectFailed => 'SSH 配置未找到或连接失败';
	@override String get terminalThemeAdaptive => '跟随主题';
	@override String get terminalThemeClassicDark => '经典暗色';
	@override String get terminalThemeHighContrast => '高对比';
	@override String get toolsResolveFailed => '无法打开工作区工具';
	@override String get toolsResolveFailedHint => '请确认远程机器可连通后再重试。';
	@override String get topologyLocal => '本地工作区';
	@override String get topologyMixed => '混合工作区';
	@override String get topologyRemote => '远程工作区';
	@override String get typeLabel => '类型';
	@override String get updatedAt => '更新时间';
	@override String get workbenchAdvancedSettingsSubtitle => '本工作区的 Agent 预设与额外 CLI 参数。';
}

// Path: worktree
class _AppLocalizations$worktree$zh extends AppLocalizations$worktree$en {
	_AppLocalizations$worktree$zh._(AppLocalizationsZh root) : this._root = root, super.internal(root);

	final AppLocalizationsZh _root; // ignore: unused_field

	// Translations
	@override String get baseSelectorHint => '分支或基线';
	@override String get branchLabel => '分支名';
	@override String get createAction => '创建';
	@override String createFailed({required Object error}) => '创建 worktree 失败：${error}';
	@override String get createTitle => '新建 worktree';
	@override String get creating => '正在创建…';
	@override String get deleteAction => '删除';
	@override String deleteBody({required Object branch}) => '删除 ${branch} 的 worktree？';
	@override String get deleteBranchToo => '同时删除分支';
	@override String get deleteBusyWarning => '请先停止该 worktree 下正在运行的会话，再删除。';
	@override String deleteFailed({required Object error}) => '删除 worktree 失败：${error}';
	@override String get deleteForce => '即使有未提交改动也强制删除';
	@override String deleteSessionsToo({required Object count}) => '同时删除该 worktree 下的 ${count} 个会话';
	@override String get deleteTitle => '删除 worktree';
	@override String get menuCopyPath => '复制路径';
	@override String get menuRemove => '删除 worktree';
	@override String get more => '更多';
	@override String get newConversationHere => '在此新建会话';
	@override String get newWorktreeTooltip => '新建 worktree';
	@override String get orphanGroup => '其他';
	@override String get pathLabel => '位置';
	@override String get randomNameTooltip => '随机名称';
	@override String get refreshTooltip => '刷新 worktree 列表';
	@override String get showLess => '收起';
	@override String showMore({required Object count}) => '显示更多 ${count} 个';
}

/// The flat map containing all translations for locale <zh>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on AppLocalizationsZh {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'aboutCurrentVersion' => '当前版本',
			'aboutGitHub' => 'GitHub',
			'aboutPageSubtitle' => 'TeamPilot 版本与应用更新。',
			'aboutTitle' => '关于',
			'aboutVersionLoading' => '加载中…',
			'account' => 'account',
			'accountCredentialPath' => '账户凭证路径',
			'actualModel' => '实际模型',
			'add' => '添加',
			'addAccountPath' => '添加账户路径',
			'addModel' => '添加模型',
			'addProvider' => '添加提供商',
			'addTeamTitle' => '添加团队',
			'addTeamTooltip' => '添加团队',
			'addWorkspaceDirectory' => '添加目录',
			'allChecksPassed' => '所有检查通过。',
			'androidWorkEnvironmentSelectorLabel' => '工作环境',
			'androidWorkEnvironmentSelectorManageTermux' => 'Termux 设置…',
			'androidWorkEnvironmentSelectorTermux' => 'Termux',
			'androidWorkEnvironmentSelectorTermuxWithUser' => ({required String username}) => 'Termux · ${username}',
			'api' => 'api',
			'apiKey' => 'API 密钥',
			'appearance' => '外观',
			'archiveConversation' => '归档',
			'askUserQuestionBubbleAsking' => '正在提问',
			'askUserQuestionBubbleUnanswered' => '未回答',
			'autoLaunchAllMembersDescription' => '仅对混合团队生效：开启后连接或重启会为每个有效成员启动终端；native 团队始终全员启动。',
			'autoLaunchAllMembersTitle' => '连接时启动全部成员',
			'autoOpenSubagentPreviewDescription' => '子 agent 开始运行时自动弹出预览并实时跟随;按返回后停止本会话的跟随。',
			'autoOpenSubagentPreviewTitle' => '自动打开子会话预览',
			'back' => '返回',
			'baseUrl' => '基础 URL',
			'board' => '看板',
			'boardClaimed' => '进行中',
			'boardDone' => '已完成',
			'boardEmpty' => '暂无任务',
			'boardPending' => '待认领',
			'bootstrapChooseWorkEnvironment' => '选择工作环境',
			'bootstrapLoadingApp' => '正在启动 TeamPilot…',
			'bootstrapLoadingLibraries' => '正在加载资源库…',
			'bootstrapLoadingWorkspaces' => '正在加载工作区…',
			'bootstrapRetry' => '重试',
			'bootstrapStartupFailed' => ({required String error}) => '启动失败：${error}',
			'bootstrapUseNativeStorageInstead' => '改用 Windows 本地存储',
			'bottom' => '底部',
			'bottomDockPanelHidden' => '隐藏底部栏',
			'bottomDockPanelVisible' => '显示底部栏',
			'bottomTray' => '底部托盘',
			'branchEditFailed' => '改后的消息发送失败',
			'branchNext' => '下一版本',
			'branchPrevious' => '上一版本',
			'branchSwitchFailed' => '切换版本失败',
			'cancel' => '取消',
			'closeAllTabs' => '关闭全部',
			'closeConversation' => '关闭会话',
			'closeOtherTabs' => '关闭其他标签',
			'closeRightTabs' => '关闭右侧标签',
			'closeTab' => '关闭',
			'configure' => '配置',
			'confirm' => '确认',
			'contentDisplayModeFlatten' => '铺平（自然高度）',
			'contentDisplayModeFoldExpandFull' => '折叠·全部展开',
			'contentDisplayModeFoldFixedHeight' => '折叠·固定高度',
			'contentDisplayModeSectionTitle' => '内容显示',
			'continueSwitchRestartBody' => '新的供应商/模型已保存。正在运行的会话仍在使用旧配置，重启后切换才会生效。',
			'continueSwitchRestartLater' => '稍后',
			'continueSwitchRestartNow' => '立即重启',
			'continueSwitchRestartTitle' => '重启以应用切换？',
			'conversationName' => '对话名称',
			'copy' => '复制',
			'copyFolderPath' => '复制文件夹路径',
			'copyPrompt' => '复制提示',
			'cotExpandLatestOnOpenDescription' => '自动展开最新消息的思考过程（含推理与工具调用），思考输出结束后自动收起。',
			'cotExpandLatestOnOpenTitle' => '自动展开最新消息的思考过程',
			'cotExpandReasoningOnOpenDescription' => '展开「思考过程」时，自动展开内部推理步骤。',
			'cotExpandReasoningOnOpenTitle' => '打开时展开推理',
			'cotExpandToolsOnOpenDescription' => '展开「思考过程」时，自动展开内部工具调用详情。',
			'cotExpandToolsOnOpenTitle' => '打开时展开工具',
			'create' => '创建',
			'credentialPushConfirmAction' => '推送凭证',
			'credentialPushConfirmBody' => ({required Object host}) => 'provider 密钥将写入远程主机 ${host}。请仅对你信任的机器开启。轮换密钥后需重推到每台已开启的机器。',
			'credentialPushConfirmTitle' => '确认把凭证推送到远程主机？',
			'credentialPushOptInSubtitle' => '供远程成员认证使用。',
			'credentialPushOptInTitle' => '把凭证推送到此机器',
			'dangerZone' => '危险操作',
			'defaultModel' => '默认模型',
			'defaultNewChatSessionTitle' => '新对话',
			'discoveryAutoRefreshSubtitle' => '开启后，打开发现页时若缓存超过 24 小时将自动检查更新；手动刷新始终有效。',
			'discoveryAutoRefreshTitle' => '自动刷新发现内容',
			'discoverySettingsSubtitle' => '技能、插件与 MCP 发现内容的刷新方式。',
			'discoverySettingsTitle' => '发现与市场',
			'duplicateConversation' => '复制对话',
			'emptyTimeline' => '本地 shell 模式对话记录将显示在此处。',
			'enabled' => '启用',
			'expertsCatalogAdoption' => '添加量',
			'extensionsEmptyHint' => '扩展目录加载后会显示在这里。',
			'extensionsEmptyTitle' => '暂无可用扩展',
			'extensionsNavInstalled' => '已安装',
			'extensionsSettingsDescription' => '安装并启用增强 Agent 的外部工具。',
			'extensionsSettingsTitle' => '扩展',
			'filterFiles' => '筛选文件',
			'filterProviders' => '筛选提供商...',
			'forkFromHere' => '从这里 fork',
			'formFieldRequired' => '此项为必填。',
			'hide' => '隐藏',
			'hooksNoInstalled' => '暂无 hooks',
			'hooksNoInstalledHint' => '创建 hook，在 CLI 事件时运行命令。',
			'htmlPreviewErrorBody' => '无法加载文件进行预览。',
			'htmlPreviewErrorTitle' => '预览不可用',
			'htmlPreviewOpenBrowser' => '在系统浏览器打开',
			'htmlPreviewOpenedInBrowser' => '预览已在系统浏览器中打开，此面板可随时重新打开。',
			'htmlViewToggleEdit' => '编辑',
			'htmlViewTogglePreview' => '预览',
			'injectSessionSshMcpSubtitle' => '本机和远程座位都可通过 MCP 在本工作区的 SSH 机器上执行命令和传文件。更改后需重连 session。',
			'injectSessionSshMcpTitle' => '注入 Session SSH MCP',
			'invalidJson' => 'JSON 无效，请修正语法后重试。',
			'jsonPreview' => 'JSON 预览',
			'language' => '语言',
			'languageChinese' => '中文',
			'languageDescription' => '菜单、按钮与标签所使用的语言。',
			'languageEnglish' => 'English',
			'languageSystem' => '跟随系统',
			'layout' => '通用',
			'layoutPageSubtitle' => '结构控件为全局设置，适用于所有团队。',
			'layoutSubtitle' => '全局工作台',
			'mailbox' => '信箱',
			'mailboxEmpty' => '暂无消息',
			'markdownOpenModeDescription' => '在编辑器中打开 .md 文件时的默认视图。「记住上次」仅在本次应用会话内有效。',
			'markdownOpenModePreview' => '预览',
			'markdownOpenModeRemember' => '记住上次',
			'markdownOpenModeSource' => '源码',
			'markdownOpenModeTitle' => '打开 Markdown 为',
			'markdownViewTogglePreview' => '预览',
			'markdownViewToggleSource' => '源码',
			'members' => '成员',
			'membersAndFileTree' => '成员和文件树',
			'membersAndFileTreeDescription' => '将成员列表与文件树堆叠显示，或以标签页切换。',
			'membersSubtitle' => '团队代理',
			'missingProvider' => '缺少提供商：',
			'model' => '模型',
			'modelId' => '模型 ID',
			'modelName' => '模型别名/名称',
			'models' => '模型',
			'modelsTab' => '模型',
			'modelsUsingProvider' => ({required int count}) => '使用此提供商的模型： ${count}',
			'modelsUsingProviderTitle' => '使用此提供商的模型',
			'name' => '名称',
			'newSessionTooltip' => '新建会话',
			'newWorkspace' => '新建工作区',
			'newWorkspaceTooltip' => '创建工作区',
			'noModelsConfigured' => '未配置模型',
			'noModelsUsingProvider' => '没有模型使用此提供商。',
			'noSessions' => '暂无会话',
			'notes' => '备注',
			'notifyOnSessionIdleDescription' => '会话结束一轮工作并进入空闲时，除应用内通知中心外，同时发送操作系统通知。',
			'notifyOnSessionIdleTitle' => 'Agent 空闲系统通知',
			'ok' => '确定',
			'openExistingSessionStartsTerminalDescription' => '开启后，从侧边栏打开对话会立即连接终端。关闭（默认）时先显示聊天视图，发送消息后才启动终端。',
			'openExistingSessionStartsTerminalTitle' => '打开已有会话时直接启动终端',
			'openFolder' => '打开文件夹',
			'openMember' => '打开成员',
			'openRightTools' => '工具',
			'openSessionDirectory' => '打开会话目录',
			'openTeam' => '启动所有成员',
			'pathCopied' => ({required String path}) => '已复制路径：${path}',
			'pickPrimaryDirectory' => '选择主目录',
			'pinConversation' => '置顶对话',
			'presetPickerNoneOption' => '无（不设默认）',
			'presetPickerTitle' => '选择预设',
			'progressActivitiesMany' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '${count} 个活动进行中', ), 
			'progressActivitiesPanelTitle' => '进行中的活动',
			'projectTreeOther' => '其他',
			'prompt' => '提示词',
			'providers' => '提供商',
			'providersTab' => '提供商',
			'proxy' => '代理',
			'proxyOffShort' => '代理关',
			'proxyOnShort' => '代理开',
			'proxyUrl' => '代理 URL',
			'rawJsonTab' => '原始 JSON',
			'reclaimIdleTerminalMinutesDescription' => '终端可保持空闲多少分钟后被回收。',
			'reclaimIdleTerminalMinutesTitle' => '空闲回收超时（分钟）',
			'reclaimIdleTerminalsDescription' => '空闲超时后关闭成员/会话终端以释放内存；需要时自动重连。',
			'reclaimIdleTerminalsTitle' => '回收空闲终端',
			'referenceConversation' => '引用会话',
			'referenceConversationFailed' => '准备会话引用失败',
			'regionVisibility' => '区域可见性',
			'removePath' => '移除路径',
			'removeWorkspaceDirectory' => '移除目录',
			'removeWorkspaceMachine' => '移除机器',
			'renameConversation' => '重命名对话',
			'renameConversationTitle' => '重命名对话',
			'renameProviderName' => '修改名称',
			'renameProviderTitle' => '修改提供商名称',
			'replaceKey' => '替换密钥',
			'restoreConversation' => '恢复',
			'retry' => '重试',
			'reveal' => '显示',
			'right' => '右侧',
			'rightTools' => '右侧工具栏',
			'rightToolsOpenTabEmpty' => '所有工具均已打开。',
			'rightToolsOpenTabSubtitle' => '选择要在侧边面板中打开的标签',
			'rightToolsOpenTabTitle' => '打开标签页',
			'rightToolsPanelHidden' => '隐藏工具栏',
			'rightToolsPanelVisible' => '显示工具栏',
			'rootSandboxEnvConfirmAction' => '启用',
			'rootSandboxEnvConfirmBody' => ({required Object host}) => '在 ${host} 上以 root 启动 Claude 时，TeamPilot 将设置 IS_SANDBOX=1 并保留 --dangerously-skip-permissions。请仅对你信任的机器开启。',
			'rootSandboxEnvConfirmTitle' => '确认为 root 启用 sandbox 环境变量？',
			'rootSandboxEnvOptInSubtitle' => 'root 启动 Claude 时保留 skip-permissions。',
			'rootSandboxEnvOptInTitle' => '为 root 注入 IS_SANDBOX',
			'runsPlaceholder' => '运行历史将显示在此处。',
			'save' => '保存',
			'saveMember' => '保存成员',
			'scopeSessionsToSelectedTeamDescription' => '开启后，侧边栏仅显示归属当前团队的会话。新建会话仍会写入当前所选团队，之后开启本选项即可看到它们。',
			'scopeSessionsToSelectedTeamTitle' => '按所选团队筛选会话',
			'selectAgent' => '选择预设',
			'selectModel' => '选择一个模型',
			'selectProvider' => '从列表中选择一个提供商',
			'selectTeam' => '选择团队',
			'selectionAskAi' => '用 AI 提问…',
			'sendPrompt' => '发送提示',
			'settings' => '设置',
			'settingsPageSubtitle' => '管理 FlashskyAI 团队和模型设置。',
			'shellChatWorkbench' => 'Shell 聊天工作台',
			'shellSession' => 'Shell 会话',
			'sidebarPanelHidden' => '隐藏侧边栏',
			'sidebarPanelVisible' => '显示侧边栏',
			'sourceControl' => '源代码管理',
			'stacked' => '堆叠',
			'stackedTools' => '堆叠工具栏',
			'statEmptyKeys' => '空密钥',
			'statMissingRefs' => '缺失引用',
			'statModels' => '个模型',
			'statProviders' => '个提供商',
			'subagentPreviewBack' => '返回',
			'subagentPreviewEmpty' => '暂无子会话内容',
			'subagentPreviewTitleAgent' => ({required String title}) => '${title}',
			'subagentPreviewUnavailable' => '无法打开该子会话预览',
			'summary' => '摘要',
			'switchToMember' => '切换到成员',
			'switchWorkspaceTooltip' => '切换工作区',
			'tabMenuSplitDown' => '向下拆分',
			'tabMenuSplitRight' => '向右拆分',
			'tabbedTools' => '标签工具栏',
			'tabs' => '标签页',
			'teamsCatalogAdoption' => '添加量',
			'thinkingProcessFoldSectionTitle' => '折叠进思考过程',
			'thinkingProcessSectionTitle' => '思考过程',
			'toolchainGit' => 'Git',
			'toolchainGitLabel' => 'Git 可执行文件路径',
			'toolchainInstallProgressChecking' => ({required String tool}) => '正在检查 ${tool}...',
			'toolchainNode' => 'Node.js',
			'toolchainNodeLabel' => 'Node.js / npm 路径',
			'toolchainPathDescription' => ({required String tool}) => '${tool} 可执行文件的绝对路径。留空则使用 PATH 中的版本。',
			'toolchainPathDescriptionSsh' => ({required String tool}) => '远程 SSH 主机上 ${tool} 的绝对路径。留空则自动发现。',
			'treeCollapseAllFolders' => '折叠所有目录',
			'treeExpandAllFolders' => '展开所有目录',
			'type' => '类型',
			'uiZoomDescription' => '整体缩放界面——文字、图标与间距一起。「标准」按系统缩放自动匹配。',
			'uiZoomTitle' => '界面缩放',
			'unknownFolder' => '未知',
			'unpinConversation' => '取消置顶',
			'validate' => '校验',
			'validation' => '验证',
			'visibilityBoardHint' => '显示混合模式团队的任务看板。',
			'visibilityFileTreeHint' => '显示工作区文件树以便快速浏览。',
			'visibilityGitHint' => '显示当前仓库的源代码管理面板。',
			'visibilityMembersHint' => '在工具或终端旁显示成员列表。',
			'visibilityRightToolsHint' => '打开会话时显示右侧工具栏。',
			'visibilityTeamSessionsHint' => '在左侧边栏显示团队会话列表。',
			'windowControlAlwaysOnTop' => '置顶',
			'windowControlClose' => '关闭',
			'windowControlMaximize' => '最大化',
			'windowControlMinimize' => '最小化',
			'windowControlRestore' => '还原',
			'windowsStorageCliMismatchNativeCli' => 'CLI 在 WSL 中运行，但数据保存在 Windows AppData，配置可能不一致。',
			'windowsStorageCliMismatchWslCli' => 'CLI 在 Windows 上运行，但数据保存在 WSL，配置可能不一致。',
			'windowsStorageSwitchReloadHint' => '切换存储后建议重连已打开的会话。',
			'workbenchLockGroup' => '锁定组',
			'workbenchStripNewMenuTooltip' => '新建',
			'workbenchUnlockGroup' => '解锁组',
			'workflowCardAgents' => ({required int count}) => '${count} 个 agent',
			'workflowCardRunMissing' => '未找到该调用的 Workflow 运行记录',
			'workspaces' => '工作区',
			'askUserQuestionBubbleAsked' => ({required int count}) => '已询问 ${count} 个问题',
			'acp.chatLaunchFailed' => ({required String cliName}) => '无法启动 ${cliName}，请确认已安装对应 CLI 后重试。',
			'acp.chatNotLoggedIn' => '代理尚未登录。请到设置 → 服务商完成登录后重试。',
			'acp.chatProcessExited' => ({required String cliName}) => '${cliName} 意外退出',
			'acp.chatSessionOpenFailed' => ({required String cliName}) => '无法打开 ${cliName} 会话。',
			'acp.chatTurnFailed' => '本轮对话失败',
			'acp.launchFailedAdapter' => '无法启动 Claude ACP 适配器（claude-agent-acp）。请安装后重试。',
			'acp.launchFailedVersion' => '当前 CLI 版本不支持 ACP 聊天模式，请更新后再试。',
			'acp.modelSectionAgent' => 'Agent 模型',
			'acp.modelSectionLaunch' => '启动配置',
			'acp.modelSwitchFailed' => '无法切换 ACP 模型，请重试。',
			'acp.permissionAskLabel' => '询问',
			'acp.permissionFullAccessLabel' => '完全访问',
			'agent.agent' => 'Agent 预设',
			'agent.askAnswerFailed' => '无法提交回答。请重试或在终端中回答。',
			'agent.askAnswerInTerminal' => '在终端回答',
			'agent.askCancelQuestion' => '取消提问',
			'agent.askContinue' => '继续',
			'agent.askCustomAnswerHint' => '输入你的回答…',
			'agent.askEscToCancel' => 'Esc 取消',
			'agent.askIgnore' => '忽略',
			'agent.askKeyboardHint' => '使用 Tab / 上下键选择，回车或空格选中',
			'agent.askQuestionTabFallback' => ({required int index}) => '问题${index}',
			'agent.askSubmitAnswers' => '提交',
			'agent.askTerminalDisconnected' => '终端已断开。请重新连接或在终端中回答。',
			'agent.askUserQuestionTitle' => '正在向你提问',
			'agent.builtInCustom' => '自定义…',
			'agent.builtInNone' => '默认',
			'agent.builtInSubtitle' => '指定该成员以哪种 Agent 身份协作，影响其行为与可用能力。',
			'agent.claudeTypeHint' => '例如 Explore、Plan 或自定义类型',
			'agent.claudeTypeSubtitle' => '写入 Claude 团队 roster 的 agentType；留空则使用成员 ID。',
			'agent.customIdHint' => '自定义 Agent 标识',
			'agent.flashskyaiPresetSubtitle' => '对应 flashskyai 的 --agent 参数，可选内置或自定义子 Agent。',
			'agent.permissionAlwaysAllowRule' => ({required Object rule}) => '始终允许 ${rule}',
			'agent.permissionAttentionBanner' => '此智能体需要在终端中确认。',
			'agent.permissionOpenTerminal' => '打开终端',
			'agent.permissionTitle' => ({required String cliName}) => '${cliName} 需要你的授权',
			'agent.permissionTitleGeneric' => '需要你的授权',
			'ai.featureCliLabel' => 'CLI',
			'ai.featureCommitMessageSubtitle' => '由源代码管理面板里的 ✨ 按钮使用。',
			'ai.featureCommitMessageTitle' => '提交信息生成',
			'ai.featureConfigSummary' => ({required String cli, required String provider, required String model}) => '${cli} · ${provider} · ${model}',
			'ai.featureEffortLabel' => 'Effort',
			'ai.featureModelLabel' => '模型',
			'ai.featureTeamGenerateSubtitle' => '从描述生成团队时使用。',
			'ai.featureTeamGenerateTitle' => '团队配置生成',
			'ai.features' => 'AI 功能',
			'ai.featuresPageSubtitle' => '为每个 AI 功能选择使用的 CLI provider、模型与 effort。',
			'ai.messageCancelled' => '消息已取消',
			'ai.messageCancelledTool' => '已取消工具',
			'ai.messageCopied' => '已复制',
			'ai.messageExportMarkdown' => '导出 Markdown',
			'ai.messageIncomplete' => '消息未完成',
			'ai.messageReasoning' => '推理',
			'ai.messageScrollToBottom' => '滚动到底部',
			'ai.messageShowLess' => '收起',
			'ai.messageShowMore' => '显示更多',
			'ai.messageThinkingCommands' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '运行了 ${count} 条命令', ), 
			'ai.messageThinkingEditedFiles' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '编辑了 ${count} 个文件', ), 
			'ai.messageThinkingExploredFiles' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '探索了 ${count} 个文件', ), 
			'ai.messageThinkingProcess' => '思考过程',
			'ai.messageThinkingProcessStats' => ({required int steps, required int toolCalls}) => '思考过程 · ${steps} 步 · ${toolCalls} 次工具调用',
			'ai.messageThinkingProcessSteps' => ({required int count}) => '思考过程 · ${count} 步',
			'ai.messageThinkingProcessSummarySeparator' => '，',
			'ai.messageThinkingSearches' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '${count} 次搜索', ), 
			'ai.messageToolResult' => '结果',
			'ai.messageToolsUsed' => ({required Object count}) => '已使用 ${count} 个工具',
			'ai.messageUsedTool' => '已使用工具',
			'ai.toolFileNotFound' => ({required String path}) => '找不到文件：${path}',
			'antigravity.credentialsActionFailed' => 'Antigravity 登录失败。',
			'antigravity.credentialsCancel' => '取消',
			'antigravity.credentialsDone' => '完成',
			'antigravity.credentialsLogin' => '登录',
			'antigravity.credentialsLoginExited' => 'Antigravity 已退出。请关闭此对话框后重新登录。',
			'antigravity.credentialsLoginFailed' => ({required String error}) => '无法启动登录终端：${error}',
			'antigravity.credentialsLoginIntro' => '在下方终端完成 Google 登录，然后点击“完成”。Antigravity 将账号保存在系统钥匙串中，所有 Antigravity 会话以及所有官方 Antigravity 供应商行都会共享该账号。',
			'antigravity.credentialsLoginStarting' => '正在启动 Antigravity…',
			'antigravity.credentialsLoginTitle' => '登录 Antigravity',
			'antigravity.credentialsLoginVerifyFailed' => 'Antigravity 未确认登录成功（agy models 执行失败）。请完成登录后再次点击“完成”。',
			'antigravity.credentialsRetry' => '重试',
			'antigravity.credentialsSignedIn' => '已登录 Antigravity。',
			'app.dropdownSearchHint' => '搜索…',
			'app.dropdownSearchNoResults' => '未找到结果',
			'app.rail' => '应用导航栏',
			'app.railChat' => '聊天',
			'app.railConfig' => '配置',
			'app.railRuns' => '运行',
			'app.title' => 'TeamPilot',
			'app.updateAutoCheck' => '自动检查更新',
			'app.updateAutoCheckHint' => '每次启动时自动从 GitHub 检查新版本。',
			'app.updateBrowserDownload' => '浏览器下载',
			'app.updateBrowserOpenFailed' => ({required String error}) => '打开浏览器失败：${error}',
			'app.updateBrowserOpened' => '已在浏览器中打开下载链接',
			'app.updateCannotOpenDownloadLink' => '无法打开下载链接',
			'app.updateChangelogDefaultSection' => '更新',
			'app.updateChangelogTitle' => '更新内容',
			'app.updateCheck' => '检查更新',
			'app.updateDialogTitle' => '发现新版本',
			'app.updateDownloadComplete' => '下载完成',
			'app.updateDownloadError' => ({required String error}) => '下载过程中发生错误：${error}',
			'app.updateDownloadFailed' => '下载失败',
			'app.updateDownloadInBackground' => '后台下载',
			'app.updateDownloadInstall' => '下载并安装',
			'app.updateDownloadNow' => '立即下载',
			'app.updateDownloadStarting' => '开始下载…',
			'app.updateDownloading' => '正在下载更新…',
			'app.updateInstallComplete' => '安装完成',
			'app.updateInstallFailed' => ({required String message}) => '安装失败：${message}',
			'app.updateInstallNoResult' => '安装未返回结果',
			'app.updateInstallNow' => '立即安装',
			'app.updateInstalling' => '正在安装更新…',
			'app.updateInvalidPackagePath' => '安装包路径无效',
			'app.updateLater' => '以后更新',
			'app.updateLatestVersion' => '最新版本',
			'app.updateNewVersion' => ({required String version}) => '新版本 ${version} 可用',
			'app.updatePackagePlatformMismatch' => '安装包类型与当前系统不匹配',
			'app.updateReadyToDownload' => '准备下载',
			'app.updateRedirectBrowserOnly' => '该链接需要在浏览器中下载',
			'app.updateReleaseBuildRequired' => '请使用 Release 构建包进行应用内安装',
			'app.updateResolvingDownloadUrl' => '正在获取下载链接…',
			'app.updateSkipVersion' => '跳过此版本',
			'app.updateUnknownVersion' => '未知',
			'app.updateUpToDate' => '已是最新版本。',
			'app.updateViewRelease' => '在 GitHub 查看发布',
			'app.updateViewReleases' => '查看发布',
			'appProvider.advancedJson' => '高级 JSON 编辑',
			'appProvider.advancedOptions' => '高级选项',
			'appProvider.apiKeyEditHint' => '留空则保留原密钥',
			'appProvider.catalogHint' => 'TeamPilot 在此维护统一服务商；团队启动时会为各工具生成隔离配置。',
			'appProvider.catalogLabel' => '应用级服务商目录',
			'appProvider.claudeAuthApiKey' => 'ANTHROPIC_API_KEY',
			'appProvider.claudeAuthField' => '认证字段',
			'appProvider.claudeAuthFieldHint' => '选择写入 settings 的认证环境变量。',
			'appProvider.claudeAuthTokenDefault' => 'ANTHROPIC_AUTH_TOKEN（默认）',
			'appProvider.claudeCredentialBinding' => 'OAuth 凭证来源',
			'appProvider.claudeCredentialBindingIsolated' => '隔离副本（仅 TeamPilot）',
			'appProvider.claudeCredentialBindingIsolatedHint' => '在 TeamPilot 目录保存独立凭证副本；适用于不能与全局 Claude Code 共用登录的场景。',
			'appProvider.claudeCredentialBindingLinked' => '跟随全局（~/.claude）',
			'appProvider.claudeCredentialBindingLinkedHint' => '与终端里 Claude Code 共用同一份 OAuth 会话，刷新会自动保持同步。',
			'appProvider.credentialLinkEmpty' => '还没有存有密钥的余额条目',
			'appProvider.credentialLinkMode' => 'API Key 来源',
			'appProvider.credentialLinkOwnKey' => '使用自己的 API Key',
			'appProvider.credentialLinkedTo' => ({required Object entry}) => '使用 ${entry} 的密钥',
			'appProvider.displayName' => '显示名称',
			'appProvider.enabledTools' => '启用的工具',
			'appProvider.import' => '导入',
			'appProvider.importNothing' => '未发现可导入的提供商。',
			'appProvider.importSuccess' => ({required int count, required int mirrored, required int skipped}) => '已导入 ${count} 个提供商，同步到 FlashskyAI ${mirrored} 个，跳过已存在 ${skipped} 个。',
			'appProvider.internalIdPreview' => ({required String id}) => '内部 id：${id}',
			'appProvider.modelEnterCustom' => '输入自定义模型 ID',
			'appProvider.modelPickFromList' => '从列表选择',
			'appProvider.opencodeSubscription' => '订阅',
			'appProvider.opencodeSubscriptionOff' => '仅免费模型。绑定 OpenCode Go 后可使用订阅模型。',
			'appProvider.opencodeSubscriptionOn' => '已绑定 OpenCode Go，订阅模型与免费模型均可用。',
			'appProvider.presetCustom' => '自定义',
			'appProvider.presetLabel' => '预设',
			'appProvider.teamNone' => '无',
			'appProvider.teamToolSection' => '团队默认服务商',
			'appProvider.teamToolSubtitle' => '选择本团队启动时，各工具使用的统一服务商。',
			'appProvider.toolAntigravity' => 'Antigravity',
			'appProvider.toolClaude' => 'Claude Code',
			'appProvider.toolCodebuddy' => 'CodeBuddy',
			'appProvider.toolCodex' => 'Codex',
			'appProvider.toolCursor' => 'Cursor',
			'appProvider.toolFlashskyai' => 'FlashskyAI',
			'appProvider.toolGemini' => 'Gemini CLI',
			'appProvider.toolOpencode' => 'OpenCode',
			'appProvider.toolQoder' => 'Qoder',
			'appProvider.toolQoderCn' => 'Qoder 国内版',
			'appProvider.website' => '官网',
			'appProvider.toolGrok' => 'Grok CLI',
			'automations.boundSession' => '绑定会话',
			'automations.boundSessionPending' => '首次运行后自动绑定会话',
			'automations.boundSessionUnavailable' => '会话不可用，请切换或解绑',
			'automations.catchUpOnce' => '启动后补跑一次',
			'automations.cli' => 'CLI',
			'automations.command' => '命令',
			'automations.commandHelp' => '仅在 TeamPilot 运行时执行。超过宽限期的错过运行会被跳过，除非开启了补跑。',
			'automations.commandRequired' => '命令不能为空',
			'automations.commandTimeout' => '超时（秒）',
			'automations.commandTimeoutInvalid' => '超时时间必须是整数秒',
			'automations.commandTimeoutRange' => '超时时间须在 30 到 1800 秒之间',
			'automations.commandTooLong' => '命令不能超过 2000 个字符',
			'automations.commandWorkingDirectory' => '工作目录',
			'automations.commandWorkingDirectoryMain' => '工作区默认目录',
			'automations.compactTitle' => '定时消息',
			'automations.countdownCustom' => '自定义',
			'automations.countdownHours' => ({required int hours}) => '${hours} 小时',
			'automations.countdownMinutes' => ({required int minutes}) => '${minutes} 分钟',
			'automations.countdownPreview' => ({required String dateTime}) => '将在 ${dateTime} 执行',
			'automations.createTitle' => '新建自动化',
			'automations.customCron' => 'Cron 表达式',
			'automations.dayFriday' => '周五',
			'automations.dayMonday' => '周一',
			'automations.daySaturday' => '周六',
			'automations.daySunday' => '周日',
			'automations.dayThursday' => '周四',
			'automations.dayTuesday' => '周二',
			'automations.dayWednesday' => '周三',
			'automations.delete' => '删除',
			'automations.deleteConfirm' => '删除此自动化？',
			'automations.dispatchFailed' => '分发失败',
			'automations.edit' => '编辑',
			'automations.editTitle' => '编辑自动化',
			'automations.empty' => '暂无自动化',
			'automations.enabled' => '已启用',
			'automations.exitCode' => ({required int code}) => '退出码 ${code}',
			'automations.filterActionAll' => '全部类型',
			'automations.filterActionLabel' => '类型',
			'automations.filterAll' => '全部',
			'automations.filterDisabled' => '仅已禁用',
			'automations.filterEnabled' => '仅已启用',
			'automations.filterLaunchPrompt' => '启动 prompt',
			'automations.filterScheduledMessage' => '定时消息',
			'automations.filterStatusLabel' => '状态',
			'automations.hideFilter' => '隐藏筛选',
			'automations.invalidCron' => '无效的 cron 表达式（需要 5 个字段）',
			'automations.invalidMaxRunCount' => '运行次数上限须为正整数',
			'automations.invalidTime' => '时间格式须为 HH:mm',
			'automations.launchMode' => '对话模式',
			'automations.launchProfile' => '启动身份',
			'automations.launchProject' => '项目',
			'automations.launchWorktree' => 'Worktree',
			'automations.manageAll' => '管理全部定时任务',
			'automations.manageSessionContextMenu' => '管理定时消息',
			'automations.maxRunCount' => '运行次数上限',
			'automations.maxRunCountHint' => '留空表示无限制',
			'automations.message' => '消息',
			_ => null,
		} ?? switch (path) {
			'automations.name' => '名称',
			'automations.kNew' => '新建自动化',
			'automations.nextRun' => ({required String time}) => '下次运行：${time}',
			'automations.nextRunNone' => '暂无计划运行',
			'automations.presetCliMismatch' => '所选预设与绑定会话的 CLI 不一致。',
			'automations.presetEmptyForCli' => '该 CLI 暂无可用预设。',
			'automations.presetScopeHint' => '已绑定会话，仅显示该会话 CLI 的预设。',
			'automations.reuseSession' => '复用会话',
			'automations.reuseSessionListHint' => ({required String sessionId}) => '复用对话 ${sessionId}',
			'automations.reuseSessionSubtitleBound' => ({required String sessionId}) => '已绑定会话 ${sessionId}',
			'automations.reuseSessionSubtitleOff' => '每次运行都会新建一个对话。',
			'automations.reuseSessionSubtitlePending' => '首次运行会创建对话，之后在同一会话中继续。',
			'automations.runCountLimited' => ({required int count, required int max}) => '已运行 ${count} / ${max}',
			'automations.runCountUnlimited' => ({required int count}) => '已运行 ${count} 次',
			'automations.runDurationMilliseconds' => ({required int milliseconds}) => '耗时 ${milliseconds} 毫秒',
			'automations.runDurationSeconds' => ({required int seconds}) => '耗时 ${seconds} 秒',
			'automations.runError' => ({required String error}) => '错误：${error}',
			'automations.runHistory' => '运行历史',
			'automations.runHistoryEmpty' => '暂无运行记录',
			'automations.runNow' => '立即运行',
			'automations.runOutputTruncated' => '输出已截断',
			'automations.runStatusCompleted' => '已完成',
			'automations.runStatusDispatched' => '已分发',
			'automations.runStatusDispatching' => '分发中',
			'automations.runStatusFailed' => '失败',
			'automations.runStatusPending' => '等待中',
			'automations.runStatusSkippedMissed' => '已跳过 — 错过窗口',
			'automations.runStatusSkippedOverlap' => '已跳过（上次仍在运行）',
			'automations.runStatusTimedOut' => '超时',
			'automations.runStderr' => '标准错误',
			'automations.runStdout' => '标准输出',
			'automations.schedule' => '调度',
			'automations.scheduleCustom' => '自定义 cron',
			'automations.scheduleDaily' => '每天',
			'automations.scheduleDate' => '日期',
			'automations.scheduleHourly' => '每小时',
			'automations.scheduleModeCountdown' => '倒计时',
			'automations.scheduleModeOnce' => '一次',
			'automations.scheduleModeRecurring' => '循环',
			'automations.scheduleOnce' => '一次',
			'automations.schedulePastTime' => '请选择未来的时间',
			'automations.scheduleSummaryDaily' => ({required String time}) => '每天 ${time}',
			'automations.scheduleSummaryHourly' => ({required int minute}) => '每小时 :${minute}',
			'automations.scheduleSummaryOnce' => ({required String time}) => '一次，${time}',
			'automations.scheduleSummaryWeekdays' => ({required String time}) => '工作日 ${time}',
			'automations.scheduleSummaryWeekly' => ({required String day, required String time}) => '每周${day} ${time}',
			'automations.scheduleType' => '类型',
			'automations.scheduleWeekdays' => '工作日',
			'automations.scheduleWeekly' => '每周',
			'automations.scopeModePersonal' => ({required String profile}) => '个人 · ${profile}',
			'automations.scopeModeTeam' => ({required String team}) => '团队 · ${team}',
			'automations.scopePersonal' => ({required String preset}) => '个人 · ${preset}',
			'automations.scopeScheduledMessage' => ({required String sessionId}) => '定时消息 · ${sessionId}',
			'automations.scopeTeam' => ({required String team, required String member}) => '团队 · ${team} · ${member}',
			'automations.scopeTeamMember' => ({required String member}) => '团队 · ${member}',
			'automations.sessionContextMenu' => '定时消息…',
			'automations.sessionDefaultName' => ({required String title}) => '${title} — 定时消息',
			'automations.sessionPickerEmpty' => '没有可绑定的会话',
			'automations.sessionPickerTitle' => '选择会话',
			'automations.sessionTitle' => '会话标题',
			'automations.sessionTitleHint' => '留空则使用定时任务名称。',
			'automations.showFilter' => '显示筛选',
			'automations.sidebarTitle' => '定时任务',
			'automations.skippedUnavailable' => '已跳过 — 会话不可用',
			'automations.sort' => '排序自动化',
			'automations.sortNameAsc' => '名称 (A–Z)',
			'automations.sortNameDesc' => '名称 (Z–A)',
			'automations.sortNextRun' => '下次运行',
			'automations.sortRecentlyUpdated' => '最近更新',
			'automations.statusBarEmpty' => '暂无启用的定时任务',
			'automations.subtitle' => '跨项目与会话定时发送消息或启动 prompt。',
			'automations.switchSession' => '切换会话',
			'automations.targetMember' => '目标成员',
			'automations.time' => '时间',
			'automations.title' => '全部自动化',
			'automations.unbindSession' => '解绑',
			'automations.validationRequired' => '名称和消息为必填项',
			'catalog.cardAccessibilityLabel' => ({required String name, required String source}) => '${name}，来源：${source}',
			'catalog.metricMissing' => '暂无数据',
			'catalog.metricMissingTooltip' => '暂无可用数据',
			'catalog.metricName' => '名称',
			'catalog.metricPublished' => '发布日期',
			'catalog.metricRating' => '评分',
			'catalog.metricUpdated' => '最近更新',
			'catalog.missingMetricAccessibilityLabel' => ({required String label}) => '${label}：暂无可用数据',
			'catalog.refreshAccessibilityLabel' => '刷新目录',
			'catalog.sortAccessibilityLabel' => '排列目录条目',
			'catalog.sortAdoption' => '采用量最高',
			'catalog.sortName' => '名称',
			'catalog.sortPublished' => '最近发布',
			'catalog.sortRating' => '评分最高',
			'catalog.sortUpdated' => '最近更新',
			'catalog.sourceWarningAccessibilityLabel' => ({required int count}) => '有 ${count} 个目录源加载失败',
			'catalog.sourceWarningEntry' => ({required String source, required String error}) => '${source}：${error}',
			'catalog.sourceWarningLabel' => '部分目录源加载失败',
			'chat.codeBlockModeDescription' => '聊天中超大代码块的呈现方式。',
			'chat.codeBlockModeTitle' => '聊天·代码块',
			'chat.findClose' => '关闭查找',
			'chat.findHint' => '在对话中查找',
			'chat.findMatchCase' => '区分大小写',
			'chat.findNext' => '下一个匹配',
			'chat.findNoResults' => '无匹配',
			'chat.findPrevious' => '上一个匹配',
			'chat.findResults' => '匹配结果',
			'chat.findUseRegex' => '使用正则表达式',
			'chat.findWholeWord' => '全字匹配',
			'chat.hintText' => '为 team-lead 编写提示...',
			'chat.submitSwitchesToTerminalDescription' => '关闭（默认）时，在聊天页发送（新建或继续）后仍留在聊天视图，终端在后台运行。开启后，发送后切换到终端。',
			'chat.submitSwitchesToTerminalTitle' => '发送后切换到终端',
			'chat.to' => '发送至：',
			'chat.userMessageModeDescription' => '聊天中超大用户消息的呈现方式。',
			'chat.userMessageModeTitle' => '用户消息',
			'chat.userMessageRailEmptyPreview' => '空消息',
			'chat.userMessageRailSemanticLabel' => ({required int index, required int total}) => '用户消息第 ${index} 条，共 ${total} 条',
			'claude.cliExecutablePathDescription' => 'Claude Code 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。',
			'claude.cliExecutablePathDescriptionSsh' => '远程 SSH 主机上 Claude Code 的绝对路径。留空则从远端 PATH 解析 claude。',
			'claude.cliExecutablePathLabel' => 'Claude Code CLI 路径',
			'claude.launchCredentialsMissingWarning' => '该 Team 绑定的 Claude Official Provider 缺少凭据，请在 Providers 设置中登录。',
			'claude.officialCredentialsActionFailed' => '凭据更新失败',
			'claude.officialCredentialsActionSuccess' => '凭据已更新',
			'claude.officialCredentialsImportFile' => '导入文件…',
			'claude.officialCredentialsImportGlobal' => '从 ~/.claude 导入',
			'claude.officialCredentialsLogin' => 'Claude 登录',
			'claude.officialCredentialsMissing' => '该 Provider 尚未保存凭据',
			'claude.officialCredentialsReady' => '凭据已就绪',
			'claude.officialCredentialsRevoke' => '退出登录',
			'claude.officialCredentialsRevokeConfirm' => ({required String name}) => '退出登录并删除 ${name} 的已保存凭据？',
			'claude.officialCredentialsTitle' => 'Claude Official 登录',
			'cli.config' => 'CLI',
			'cli.configAiCliGroup' => 'AI CLI',
			'cli.configPageSubtitle' => '配置 AI 代理 CLI 可执行文件路径，并安装缺失的工具。',
			'cli.configToolchainGroup' => '工具链',
			'cli.cursorExecutablePathLabel' => 'Cursor CLI 路径',
			'cli.executablePathApply' => '更新',
			'cli.executablePathBrowse' => '浏览…',
			'cli.executablePathDescription' => 'flashskyai 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。',
			'cli.executablePathDescriptionFor' => ({required String cli}) => '${cli} 可执行文件的绝对路径。留空则使用 PATH 中查找到的版本。',
			'cli.executablePathDescriptionSsh' => '远程 SSH 主机上 flashskyai 的绝对路径。留空则通过 SSH 自动探测。',
			'cli.executablePathDescriptionSshFor' => ({required String cli}) => '远程 SSH 主机上 ${cli} 的绝对路径。留空则通过 SSH 自动探测。',
			'cli.executablePathLabel' => 'flashskyai CLI 路径',
			'cli.executablePathLabelFor' => ({required String cli}) => '${cli} CLI 路径',
			'cli.executablePathLocate' => '定位',
			'cli.executablePathLocateFailed' => ({required String name}) => '未能在 PATH 上找到 ${name}。',
			'cli.executablePathLocateRemoteUnsupported' => '远程工作面不支持定位此工具。',
			'cli.executablePathLocateSuccess' => ({required String name, required String path}) => '已定位 ${name}：${path}。',
			'cli.executablePathReset' => '重置',
			'cli.executablePathUsing' => '当前生效：',
			'cli.executablePathUsingFallback' => '使用 PATH 中查找的版本',
			'cli.installButton' => '安装',
			'cli.installInstalling' => '安装中…',
			'cli.installProgressBootstrappingNode' => '正在安装 Node.js…',
			'cli.installProgressCheckingNpm' => '正在检测 npm…',
			'cli.installProgressDownloading' => '正在下载适配器…',
			'cli.installProgressExtracting' => '正在解压适配器…',
			'cli.installProgressInstallingCli' => '正在安装 CLI…',
			'cli.installProgressLocatingExecutable' => '正在定位 CLI 可执行文件…',
			'cli.installProgressSyncingRemoteWorkspace' => '正在同步远程工作区…',
			'cli.installUpgrading' => '正在升级…',
			'cli.readinessAdapterMissing' => '未找到适配器',
			'cli.readinessNeedsSetup' => '需要安装',
			'cli.readinessReady' => '就绪',
			'cli.readinessRowAcp' => 'ACP',
			'cli.readinessRowCli' => 'CLI',
			'cli.readinessUpdateAvailable' => '有更新',
			'cli.readinessUsesCli' => '使用 CLI · acp',
			'cli.readinessVersionUnknown' => '—',
			'cli.taskBoardCount' => ({required int completed, required int total}) => '${completed}/${total}',
			'cli.taskBoardMore' => ({required int count}) => '… +${count} 更多',
			'cli.taskBoardShowLess' => '收起',
			'cli.taskBoardTitle' => '任务',
			'cli.taskStatusCancelled' => '已取消',
			'cli.taskStatusCompleted' => '已完成',
			'cli.taskStatusInProgress' => '进行中',
			'cli.taskStatusPending' => '待处理',
			'cli.taskStatusUnknown' => '未知',
			'cli.transportDefaultChat' => '新会话默认使用对话（ACP）',
			'cli.transportDefaultTerminal' => '新会话默认使用终端（PTY）',
			'cli.upgradeButton' => '升级',
			'cli.acpProxyTitle' => '云端保活',
			'cli.acpProxySubtitle' => '手机断开后，云端模型的这一轮仍会跑完。在这台机器上安装并启动。发送消息不会安装它。',
			'cli.acpProxyStart' => '启动',
			'cli.acpProxyChecking' => '正在检查远程机器…',
			'cli.acpProxyMissing' => '未安装',
			'cli.acpProxyStopped' => '已安装，未运行',
			'cli.acpProxyOutdated' => '有可用更新',
			'cli.acpProxyRetry' => '重试',
			'cli.acpProxyNoSsh' => '安装保活前请先选择 SSH 服务器。',
			'clone.repositoryAddToExistingSucceeded' => ({required Object repo, required Object workspace}) => '已将 ${repo} 加入工作区 ${workspace}',
			'clone.repositoryAddToWorkspace' => '加入现有工作区…',
			'clone.repositoryCancelled' => ({required Object repo}) => '已取消克隆：${repo}',
			'clone.repositoryChooseWorkspace' => '选择工作区',
			'clone.repositoryCompletedBody' => ({required Object path}) => '${path} 已就绪。',
			'clone.repositoryCompletedTitle' => '克隆完成',
			'clone.repositoryCreateWorkspace' => '新建工作区',
			'clone.repositoryDestExists' => '文件夹已存在且不为空',
			'clone.repositoryDirNameLabel' => '文件夹名称',
			'clone.repositoryDirNameRequired' => '请输入文件夹名称',
			'clone.repositoryFailed' => ({required Object repo}) => '克隆失败：${repo}',
			'clone.repositoryGitMissing' => '所选目标机器上未找到 git',
			'clone.repositoryMenu' => '克隆仓库…',
			'clone.repositoryParentDirLabel' => '克隆到文件夹',
			'clone.repositoryParentDirRequired' => '请选择目标文件夹',
			'clone.repositoryProgressTitle' => ({required Object repo}) => '正在克隆 ${repo}',
			'clone.repositoryStarted' => ({required Object url}) => '已开始克隆 ${url}',
			'clone.repositorySubmit' => '克隆',
			'clone.repositorySucceeded' => ({required Object repo}) => '已克隆 ${repo}',
			'clone.repositoryTargetLabel' => '克隆到目标',
			'clone.repositoryTitle' => '克隆仓库',
			'clone.repositoryUrlHint' => 'https://github.com/owner/repo.git',
			'clone.repositoryUrlInvalid' => '请输入有效的 git URL（https://、git@、git://、ssh://）',
			'clone.repositoryUrlLabel' => '仓库 URL',
			'codebuddy.credentialsActionFailed' => 'CodeBuddy 登录失败。',
			'codebuddy.credentialsCancel' => '取消',
			'codebuddy.credentialsDone' => '完成',
			'codebuddy.credentialsLogin' => '登录',
			'codebuddy.credentialsLoginExited' => 'CodeBuddy 已退出。请关闭此对话框后重新登录。',
			'codebuddy.credentialsLoginFailed' => ({required String error}) => '无法启动登录终端：${error}',
			'codebuddy.credentialsLoginIntro' => '在下方终端完成登录。如果出现登录方式选择，请先选择（如微信 / 企业域名）。CLI 可能会打开浏览器；如果没有打开，请手动访问它输出的链接。也可以在这里切换账号。',
			'codebuddy.credentialsLoginStarting' => '正在启动 CodeBuddy…',
			'codebuddy.credentialsLoginTitle' => '登录 CodeBuddy',
			'codebuddy.credentialsRetry' => '重试',
			'codebuddy.credentialsSendLogin' => '发送 /login',
			'codebuddy.credentialsSignedIn' => '已登录 CodeBuddy。',
			'codex.acpChatNotLoggedIn' => 'Codex 尚未登录。请到设置 → 服务商完成 ChatGPT 登录，或改用 API Key。',
			'codex.acpLaunchFailedAdapter' => '无法启动 Codex ACP 适配器（codex-acp）。请安装后重试。',
			'codex.credentialsActionFailed' => '凭据更新失败',
			'codex.credentialsActionSuccess' => '凭据已更新',
			'codex.credentialsImportFile' => '导入 auth.json…',
			'codex.credentialsImportGlobal' => '从 ~/.codex 导入',
			'codex.credentialsLogin' => 'OpenAI 登录',
			'codex.credentialsRevoke' => '退出登录',
			'codex.credentialsRevokeConfirm' => ({required String name}) => '退出登录并删除 ${name} 的已保存凭据？',
			'compose.cascadeCustomModelId' => '自定义模型 ID…',
			'compose.cascadeCustomModelIdTitle' => '自定义模型 ID',
			'compose.cascadeDefaultEffort' => '默认',
			'compose.cascadeNoModels' => '暂无模型目录',
			'compose.cascadeNoProviders' => '尚未配置任何服务商',
			'compose.cascadePresets' => '预设',
			'compose.cascadeSavePreset' => '保存当前为预设…',
			'compose.commandExperimental' => '实验性',
			'compose.commandNative' => '原生命令',
			'compose.commandPlugin' => '插件',
			'compose.nativeCommandCompact' => '压缩当前对话上下文。',
			'compose.nativeCommandGoal' => '为长时间运行的工作保留持久目标。',
			'compose.nativeCommandHelp' => '显示此 CLI 会话中可用的命令。',
			'compose.nativeCommandPlan' => '将会话切换到规划工作流。',
			'compose.pasteClipEdit' => '编辑已粘贴文本',
			'compose.pasteClipLabel' => '粘贴文本',
			'compose.pasteClipLines' => ({required int lines}) => '${lines} 行',
			'compose.pasteClipRemove' => '移除已粘贴文本',
			'compose.pasteEditorDone' => '完成',
			'compose.pasteEditorRemove' => '移除',
			'compose.pasteEditorTitle' => ({required int lines}) => '编辑已粘贴文本 · ${lines} 行',
			'connect.addEndpoint' => '添加地址',
			'connect.advancedSubtitle' => '添加可从当前局域网外访问的 SSH 地址。',
			'connect.advancedTitle' => '可达地址',
			'connect.androidScanHint' => '扫描桌面版 TeamPilot 显示的二维码。',
			'connect.copyLink' => '复制链接',
			'connect.error' => '无法刷新配对信息，请重试。',
			'connect.extraHost' => '主机',
			'connect.extraPort' => '端口',
			'connect.interfaceLabel' => '网络接口',
			'connect.invalidEndpoint' => '每个地址都需要主机名和 1 至 65535 的端口。',
			'connect.lanOnlyStatus' => '仅局域网',
			'connect.needLanOrRelay' => '请连同一 Wi-Fi，或先在桌面填写中继地址。',
			'connect.noNetworkAddress' => '没有可用的非回环 IPv4 网络接口。',
			'connect.noPairedDevices' => '尚未配对手机。',
			'connect.openSettings' => '去设置',
			'connect.pairCodeHint' => 'teampilot://pair-ssh?code=…',
			'connect.pairExpired' => '配对码已过期，请重新扫描。',
			'connect.pairFailed' => '无法与此电脑配对，请重试。',
			'connect.pairInvalid' => '此配对码无效。',
			'connect.pairNow' => '配对',
			'connect.pairSheetSubtitle' => '扫描桌面版 TeamPilot 显示的二维码，或粘贴配对码。',
			'connect.pairSheetTitle' => '与电脑配对',
			'connect.pairUpdateApp' => '请更新 TeamPilot 后再扫描此配对码。',
			'connect.pairedDevicesTitle' => '已配对设备',
			'connect.pairing' => '正在配对…',
			'connect.pasteCode' => '粘贴配对码',
			'connect.qrEnlargeHint' => '点击二维码可放大后再扫。',
			'connect.regenerate' => '重新生成',
			'connect.relayUrl' => '中继 URL',
			'connect.relayUrlHint' => '可选的中继服务 URL',
			'connect.remoteReadyStatus' => '局域网和远程',
			'connect.removeEndpoint' => '移除地址',
			'connect.repairHint' => '桌面端已升级——请重新扫码配对以恢复连接。',
			'connect.revokeDevice' => '撤销',
			'connect.revokeSystemHint' => '新登录会被拒绝。已经建立的 OpenSSH 会话可能要等断开后才会失效。',
			'connect.saveSettings' => '保存可达地址',
			'connect.scanHint' => '在手机上的 TeamPilot 中扫描此码。',
			'connect.scanQr' => '扫描二维码',
			'connect.scannerHint' => '距离桌面二维码 10–30 cm；双指捏合可缩放，光线不足时打开手电筒。',
			'connect.scannerPermissionDenied' => '需要相机权限才能扫描二维码。',
			'connect.scannerUnavailable' => '相机扫描器不可用，请改为粘贴配对码。',
			'connect.settingsSubtitle' => '扫码用 SSH 连接这台电脑',
			'connect.settingsTitle' => '手机',
			'connect.sshBackendEmbedded' => '内置',
			'connect.sshBackendHelp' => '用本机 OpenSSH 对比内置服务器。切换后需重新扫码配对。',
			'connect.sshBackendLabel' => 'SSH 服务器',
			'connect.sshBackendRePair' => '已配对的手机需重新扫描此电脑的配对码。',
			'connect.sshBackendSystem' => '系统 OpenSSH (22)',
			'connect.sshdDown' => '内嵌连接服务启动失败。请重试或重启应用。',
			'connect.sshdRetry' => '重试',
			'connect.systemSshdDownLinux' => '22 端口没有 SSH 服务在听。请启动 OpenSSH 的 sshd，然后重试。',
			'connect.systemSshdDownMacos' => '22 端口没有 SSH 服务在听。请在「共享」中打开远程登录，然后重试。',
			'cursor.accountUsageSession' => 'Cursor 账号',
			'cursor.credentialsActionFailed' => '凭据更新失败',
			'cursor.credentialsActionSuccess' => '凭据已更新',
			'cursor.credentialsImportFile' => '导入目录…',
			'cursor.credentialsImportGlobal' => '从 ~/.cursor 导入',
			'cursor.credentialsLogin' => 'Cursor 登录',
			'cursor.credentialsRevoke' => '退出登录',
			'cursor.credentialsRevokeConfirm' => ({required String name}) => '退出登录并删除 ${name} 的已保存凭据？',
			'delete.delete' => '删除',
			'delete.conversation' => '删除对话',
			'delete.conversationConfirm' => ({required String name}) => '删除对话 "${name}"？此操作不可撤销。',
			'delete.provider' => '删除提供商',
			'delete.providerConfirm' => ({required String name}) => '删除提供商 ${name}？',
			'delete.providerTooltip' => '删除提供商',
			'delete.providerWithCredentialsConfirm' => ({required String name}) => '删除提供商 ${name}？将同时删除该 Provider 已保存的 Claude 登录凭据。',
			'delete.team' => '删除团队',
			'delete.teamConfirm' => ({required String name}) => '删除团队 "${name}"？此操作不可撤销。',
			'delete.teamSubtitle' => '从 UI 和共享的 flashskyai 数据目录中移除该团队。此操作不可撤销。',
			'delete.workspace' => '删除工作区',
			'delete.workspaceConfirm' => ({required String name}) => '删除工作区 "${name}" 及其所有会话？此操作不可撤销。',
			'delete.workspaceSubtitle' => '将删除该工作区及其下所有会话，且无法恢复。',
			'diff.applyDisabledNoPath' => '无法应用：文件路径不可用',
			'diff.applyFailed' => ({required String error}) => '无法应用更改：${error}',
			'diff.applyHunkTooltip' => '应用到工作区',
			'diff.changeCounter' => ({required int current, required int total}) => '${current} / ${total}',
			'diff.discardDiffBeforeFileSaveBody' => '保存文件将丢弃 diff 视图中未保存的编辑。',
			'diff.discardDiffBeforeFileSaveTitle' => '丢弃 diff 编辑？',
			'diff.discardEditsApplyBody' => '应用此更改将丢弃 diff 中未保存的编辑。',
			'diff.discardEditsApplyTitle' => '丢弃编辑？',
			'diff.fileReloadedAfterDiffWrite' => '已从磁盘重新加载文件页。',
			'diff.ignoreWhitespace' => '忽略空白',
			'diff.nextChange' => '下一处更改',
			'diff.noChanges' => '没有更改',
			'diff.openSourceFile' => '打开源文件',
			'diff.previousChange' => '上一处更改',
			'diff.reloadAfterSaveFailed' => '已保存，但刷新 diff 失败。',
			'diff.saveFailed' => ({required String error}) => '无法保存：${error}',
			'diff.showAllLines' => '显示全部',
			'diff.viewSideBySide' => '并排',
			'diff.viewUnified' => '统一',
			'download.sourcesEnabledSources' => '已启用源',
			'download.sourcesIdentity' => '直连（官方）',
			'download.sourcesMirrorBaseUrl' => '镜像基础 URL',
			'download.sourcesMirrorHint' => 'https://mirror.example',
			'download.sourcesRestoreDefaults' => '恢复默认',
			'download.sourcesSave' => '保存',
			'download.sourcesSettingsSubtitle' => '配置 GitHub 下载镜像（应用更新、Termux APK）',
			'download.sourcesSettingsTitle' => '下载源',
			'edit.cancel' => '取消',
			'edit.edit' => '编辑',
			'edit.memberSubtitle' => '编辑提供商、模型、可选 Agent 预设与命令参数。',
			'edit.modelTitle' => ({required String name}) => '编辑 ${name}',
			'edit.provider' => '编辑服务商',
			'edit.retry' => '重试',
			'edit.send' => '发送',
			'edit.teamSubtitle' => '编辑团队标识、工作目录和启动顺序。',
			'edit.userMessage' => '编辑消息',
			'edit.workspacePrimaryPath' => '编辑主目录',
			'editor.binaryFileHint' => '二进制文件将使用系统默认应用打开。',
			'editor.close' => '关闭编辑器',
			'editor.copy' => '复制',
			'editor.copyAsAiContext' => '复制为 AI 上下文',
			'editor.couldNotReadFile' => '无法读取文件',
			'editor.cut' => '剪切',
			'editor.discard' => '放弃',
			'editor.fileNotFound' => '找不到文件',
			'editor.fileReadOnly' => '文件为只读',
			'editor.fileTooLarge' => '文件过大，无法在 TeamPilot 中编辑（上限 2 MB）。',
			'editor.findClose' => '关闭',
			'editor.findHint' => '查找',
			'editor.findInSelection' => '在选定内容中查找',
			'editor.findInvalidRegex' => '正则表达式无效',
			'editor.findMatchCase' => '区分大小写',
			'editor.findNext' => '下一个匹配',
			'editor.findNoResults' => '无匹配',
			'editor.findPrevious' => '上一个匹配',
			'editor.findReplaceAll' => '全部替换',
			'editor.findReplaceHint' => '替换',
			'editor.findReplaceOne' => '替换',
			'editor.findReplacePreserveCase' => '保留大小写',
			'editor.findToggleReplace' => '切换替换',
			'editor.findUseRegex' => '使用正则表达式',
			'editor.findWholeWord' => '全字匹配',
			'editor.imageDecodeFailed' => '无法解码此图片。',
			'editor.imageTooLarge' => '图片过大，无法在 TeamPilot 中预览（上限 25 MB）。',
			'editor.noFileOpen' => '未打开文件',
			'editor.notReady' => '编辑器未就绪',
			'editor.paste' => '粘贴',
			'editor.redoEdit' => '重做',
			'editor.revertChanges' => '撤销修改',
			'editor.save' => '保存',
			'editor.saveFailed' => ({required String error}) => '保存失败：${error}',
			'editor.selectAll' => '全选',
			'editor.title' => '编辑器',
			'editor.undoEdit' => '撤销',
			'editor.unsavedChangesDiscardFile' => ({required String fileName}) => '放弃对「${fileName}」的未保存修改？',
			'editor.unsavedChangesDiscardMultiple' => ({required int count}) => '放弃 ${count} 个文件中的未保存修改？',
			'editor.unsavedChangesTitle' => '未保存的更改',
			'exit.planModeApprove' => '批准',
			'exit.planModeApproveFailed' => '批准计划失败',
			'exit.planModeCopyPlan' => '复制计划',
			'exit.planModeOpenPlanFile' => '打开计划文件',
			'exit.planModePreviewTitle' => '计划预览',
			'exit.planModeReject' => '拒绝',
			'exit.planModeRejectFailed' => '拒绝计划失败',
			'exit.planModeTitle' => '计划已就绪，等待批准',
			'exit.planModeViewPlan' => '查看计划',
			'expert.editorCategory' => '分类',
			'expert.editorConfigureMcpTitle' => '配置 MCP',
			'expert.editorConfigurePluginsTitle' => '配置插件',
			'expert.editorConfigureSkillsTitle' => '配置技能',
			'expert.editorCreateTitle' => '新建专家',
			'expert.editorDepPickerDone' => '完成',
			'expert.editorDepsHint' => '从本机已安装库中配置依赖。没有可移植来源的项会在保存时跳过。',
			'expert.editorDescription' => '描述',
			'expert.editorEditTitle' => '编辑专家',
			'expert.editorMcpSection' => 'MCP',
			'expert.editorNameRequired' => '名称为必填项。',
			'expert.editorNonPortableSkipped' => ({required int count}) => '已跳过 ${count} 个没有可移植来源的本地项。',
			'expert.editorOrphanDeps' => '已挂载（本机未安装）',
			'expert.editorOrphanRemove' => '移除',
			'expert.editorPlaybookHint' => '可选。该专家应遵循的工作步骤与规范。',
			'expert.editorPluginsSection' => '插件',
			'expert.editorPromptHint' => '描述该专家的职责与工作范围。',
			'expert.editorPromptRequired' => '职责为必填项。',
			'expert.editorSkillsSection' => '技能',
			'expert.editorTags' => '标签',
			'expert.editorTagsHint' => '逗号分隔',
			'expert.hubAddFailed' => '无法添加该成员。',
			'expert.hubAddFromHub' => '从专家中心添加',
			'expert.hubAddPartial' => ({required Object name, required int skillCount, required int failedCount, required Object failedNames}) => '已添加「${name}」。安装了 ${skillCount} 个技能。${failedCount} 个无法安装：${failedNames}。',
			'expert.hubAddSuccess' => ({required Object name}) => '已将「${name}」添加到团队。',
			'expert.hubAddSuccessWithSkills' => ({required Object name, required int skillCount}) => '已添加「${name}」。安装了 ${skillCount} 个技能。',
			'expert.hubAddToTeam' => '添加到团队',
			'expert.hubAdding' => '添加中…',
			'expert.hubBrowseAll' => '浏览全部专家',
			'expert.hubCapabilities' => '能力',
			'expert.hubCardNoDescription' => '无',
			'expert.hubCategoryAll' => '全部',
			'expert.hubConfirmSelection' => '确认',
			'expert.hubCreate' => '新建',
			'expert.hubEmptyHint' => '刷新以从注册表获取专家。',
			'expert.hubEmptyTitle' => '暂无专家',
			'expert.hubFavorites' => '收藏',
			'expert.hubFavoritesEmptyHint' => '点击专家卡片上的星标即可收藏。',
			'expert.hubFavoritesEmptyTitle' => '暂无收藏',
			'expert.hubFromTeams' => '来自团队',
			'expert.hubIgnoredInTeamMode' => '专家仅在简单模式下可用。请切换到简单模式以召唤专家。',
			'expert.hubLaunchInWorkspace' => '在工作区启动',
			'expert.hubLoadError' => '无法加载专家。',
			'expert.hubMyTemplates' => '我的模板',
			'expert.hubNav' => '专家中心',
			'expert.hubNoneSelected' => '未选择专家',
			'expert.hubNotFound' => '未找到该专家。',
			'expert.hubPlaybook' => '工作手册',
			'expert.hubPreflightPartial' => ({required Object name, required int failedCount, required Object failedNames}) => '已选择「${name}」。${failedCount} 个能力无法安装：${failedNames}。',
			'expert.hubPrompt' => '职责',
			'expert.hubRecent' => '最近使用',
			'expert.hubRefresh' => '刷新',
			'expert.hubSearchHint' => '搜索专家',
			'expert.hubSortName' => '名称',
			'expert.hubSortUpdated' => '最近更新',
			'expert.hubSourceBuiltin' => '内置',
			'expert.hubSourceClone' => '克隆',
			'expert.hubSourceLocal' => '我的模板',
			'expert.hubSourceRegistry' => '注册表',
			'expert.hubSourceTeamExtract' => '来自团队',
			'expert.hubSubtitle' => '发现成员角色与模板',
			'expert.hubTitle' => '专家中心',
			'expert.hubViewInHub' => '在专家中心查看',
			'expert.hubViewOriginTeam' => '查看来源团队',
			'extension.commandCopied' => '命令已复制到剪贴板',
			'extension.copyCommand' => '复制',
			'extension.dependencyMissingHint' => ({required String deps}) => '需要 PATH 中有 ${deps}。安装后点击重新检测。',
			'extension.enableLabel' => '已启用',
			'extension.install' => '安装',
			'extension.installGuide' => '安装指引',
			'extension.kindMcpServer' => '代码智能（MCP）',
			'extension.kindSettingsHook' => 'Token 节省（hook）',
			'extension.recheck' => '重新检测',
			'extension.statusDependencyMissing' => '缺少依赖',
			'extension.statusDependencyMissingNamed' => ({required String deps}) => '缺少：${deps}',
			'extension.statusNotInstalled' => '未安装',
			'extension.statusReady' => '就绪',
			'extension.statusReadyVersion' => ({required String version}) => '就绪（${version}）',
			'extension.statusVersionTooOld' => '已安装版本过旧',
			'extension.uninstall' => '卸载',
			'file.codeBlockModeDescription' => 'markdown 文件预览中超大代码块的呈现方式。',
			'file.codeBlockModeTitle' => '文件预览·代码块',
			'file.diffToggleDiff' => 'Diff',
			'file.diffToggleFile' => '文件',
			'file.previewHostCenter' => '中间',
			'file.previewHostDescription' => '在浮动工作区或中间工作台打开文件。',
			'file.previewHostFloating' => '浮动',
			'file.previewHostTitle' => '文件预览位置',
			'fileTree.fileTree' => '文件树',
			'fileTree.copy' => '复制',
			'fileTree.copyPath' => '复制路径',
			'fileTree.copyRelativePath' => '复制相对路径',
			'fileTree.createNameHint' => '名称',
			'fileTree.cut' => '剪切',
			'fileTree.deleteDone' => '已删除',
			'fileTree.deleteItemConfirm' => ({required String name}) => '删除「${name}」？',
			'fileTree.deleteItemTitle' => '删除',
			'fileTree.fileCreated' => '已创建文件',
			'fileTree.folderCreated' => '已创建文件夹',
			'fileTree.hideFilter' => '隐藏筛选',
			_ => null,
		} ?? switch (path) {
			'fileTree.importApplyRemaining' => '应用于剩余冲突',
			'fileTree.importCancelAll' => '全部取消',
			'fileTree.importConflictBody' => ({required String name}) => '目标位置已存在「${name}」。',
			'fileTree.importConflictRemaining' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '之后还有 ${count} 个冲突。', ), 
			'fileTree.importConflictRemainingZero' => '没有更多冲突。',
			'fileTree.importConflictTitle' => '项目已存在',
			'fileTree.importConflictTypeMismatch' => '文件和文件夹不能互相替换。',
			'fileTree.importDropCopy' => '复制',
			'fileTree.importDropMove' => '移动',
			'fileTree.importOverwrite' => '覆盖',
			'fileTree.importProgressCancel' => '取消',
			'fileTree.importProgressCurrent' => ({required String name}) => '${name}',
			'fileTree.importProgressItems' => ({required int completed, required int total}) => '${completed} / ${total}',
			'fileTree.importProgressTitle' => '正在导入…',
			'fileTree.importRejectSelf' => '无法将项目移动到自身或其子目录中。',
			'fileTree.importSkip' => '跳过',
			'fileTree.importSummary' => ({required int succeeded, required int skipped, required int failed}) => '成功 ${succeeded}，跳过 ${skipped}，失败 ${failed}',
			'fileTree.importSummaryCancelledSuffix' => ' — 已取消',
			'fileTree.invalidName' => '名称无效',
			'fileTree.invalidPasteTarget' => '无法粘贴到此处',
			'fileTree.itemExists' => '同名项目已存在',
			'fileTree.newFile' => '新建文件',
			'fileTree.newFolder' => '新建文件夹',
			'fileTree.openInFileManager' => '在文件管理器中打开',
			'fileTree.openInTerminal' => '在终端中打开',
			'fileTree.openInTerminalFailed' => '无法打开终端',
			'fileTree.openWithSystemApp' => '用系统应用打开',
			'fileTree.paste' => '粘贴',
			'fileTree.pasteDone' => '已粘贴',
			'fileTree.refresh' => '刷新',
			'fileTree.rename' => '重命名',
			'fileTree.renameDone' => '已重命名',
			'fileTree.renameTitle' => '重命名',
			'fileTree.revealActiveFile' => '定位当前文件',
			'fileTree.revealFailed' => '无法在文件树中定位该文件',
			'fileTree.showFilter' => '显示筛选',
			'fileTree.sourceMissing' => '源文件不存在',
			'floating.previewTabsDescription' => '文件与 diff 预览在浮动面板中共享一个可替换的标签页，固定后保留。',
			'floating.previewTabsTitle' => '单个预览标签页',
			'floating.restoreTerminalSessionsDescription' => '重启后保留浮动终端标签，首次打开该标签时才重新连接。',
			'floating.restoreTerminalSessionsTitle' => '恢复终端标签',
			'floating.workspaceAddTooltip' => '在浮动工作区打开',
			'floating.workspaceCloseTab' => '关闭标签',
			'floating.workspaceMaximize' => '最大化',
			'floating.workspaceMinimize' => '最小化',
			'floating.workspaceNewTerminal' => '新 Terminal',
			'floating.workspaceOpenFile' => '打开文件',
			'floating.workspaceToggleTooltip' => '浮动工作区',
			'font.changeAppliesOnRestart' => '字体已保存，重启 TeamPilot 后生效。',
			'font.installedSection' => '已安装',
			'font.monoDescription' => '终端、编辑器与 diff。重启后生效。',
			'font.monoTitle' => '等宽字体',
			'font.optionJetbrainsMono' => 'JetBrains Mono',
			'font.optionNotoSansSc' => 'Noto Sans SC',
			'font.optionSystem' => '系统',
			'font.optionUbuntuSansMono' => 'Ubuntu Sans Mono',
			'font.searchHint' => '搜索字体',
			'font.uiDescription' => '界面文字。系统跟随操作系统默认字体。重启后生效。',
			'font.uiTitle' => '界面字体',
			'git.aheadBehind' => ({required int ahead, required int behind}) => '↑${ahead} ↓${behind}',
			'git.amend' => '修正',
			'git.amendCommit' => '修改提交',
			'git.amendConfirmMessage' => '这将改写最后一次提交。如果该提交已推送到远程，之后需要强制推送。',
			'git.amendConfirmTitle' => '修改上一次提交？',
			'git.autoFetchDescription' => '定时对源代码管理面板当前显示的仓库执行非交互的 git fetch --all --prune，保持提交/拉取计数最新。',
			'git.autoFetchIntervalDescription' => '面板打开时对选中仓库执行 fetch 的频率。',
			'git.autoFetchIntervalMinutesOption' => ({required int minutes}) => '每 ${minutes} 分钟',
			'git.autoFetchIntervalTitle' => '自动拉取间隔（分钟）',
			'git.autoFetchTitle' => '自动拉取远程更新',
			'git.changes' => '要提交的变更',
			'git.changesListView' => '列表视图',
			'git.changesTreeView' => '树形视图',
			'git.commit' => '提交',
			'git.commitMessageHint' => ({required String branch}) => '消息（提交到 "${branch}"）',
			'git.committing' => '正在提交…',
			'git.compareEmpty' => '没有差异',
			'git.compareLoadError' => '无法加载差异',
			'git.compareSubtitle' => ({required String ref}) => '${ref} 与当前工作区的差异',
			'git.compareWorkingTree' => '工作区',
			'git.copyPath' => '复制路径',
			'git.createBranch' => '新建分支',
			'git.discard' => '放弃更改',
			'git.discardAllConfirmBody' => '放弃工作区中的所有未暂存更改？此操作无法撤销。',
			'git.discardAllConfirmTitle' => '放弃所有更改？',
			'git.discardAllUnstaged' => '放弃全部未暂存更改',
			'git.discardConfirmBody' => ({required String path}) => '放弃 ${path} 中的所有更改？此操作无法撤销。',
			'git.discardConfirmTitle' => '放弃更改？',
			'git.discardFolder' => '放弃文件夹中的更改',
			'git.discardFolderConfirmBody' => ({required String path}) => '放弃 ${path} 中的所有更改？此操作无法撤销。',
			'git.discardFolderConfirmTitle' => '放弃文件夹更改？',
			'git.discardSelected' => '放弃所选更改',
			'git.error' => ({required String message}) => 'Git：${message}',
			'git.excludeFolderFromCommit' => '从本次提交排除文件夹',
			'git.excludeFromCommit' => '排除出本次提交',
			'git.fetch' => '从远端获取',
			'git.fetchDone' => '已获取远端更新',
			'git.fetching' => '正在获取远端更新…',
			'git.generateCommitMessage' => '用 AI 生成提交信息',
			'git.generateCommitMessageNoProvider' => '请先在 设置 → AI 功能 中配置 AI provider。',
			'git.generatingCommitMessage' => '正在生成提交信息…',
			'git.includeFolderInCommit' => '纳入文件夹到本次提交',
			'git.includeInCommit' => '纳入本次提交',
			'git.initializeRepository' => '创建 Git 仓库',
			'git.newBranchHint' => '新分支名称',
			'git.noChanges' => '没有更改',
			'git.notARepository' => '当前文件夹不是 Git 仓库',
			'git.notInstalled' => '未找到 Git。安装 Git 后即可使用源代码管理。',
			'git.openFile' => '打开文件',
			'git.pull' => '拉取',
			'git.pullDone' => '拉取完成',
			'git.pulling' => '正在拉取…',
			'git.push' => '推送',
			'git.pushDone' => '推送完成',
			'git.pushing' => '正在推送…',
			'git.refresh' => '刷新',
			'git.refreshing' => '正在刷新…',
			'git.showDiff' => '显示差异',
			'git.stagedChanges' => '暂存的更改',
			'git.switchBranch' => '切换分支',
			'git.unversionedFiles' => '未暂存的文件',
			'gitGraph.allBranches' => '所有分支',
			'gitGraph.branchNameLabel' => '分支名称',
			'gitGraph.branchesTags' => '分支与标签',
			'gitGraph.checkoutBranch' => ({required String branch}) => '检出 ${branch}',
			'gitGraph.checkoutCommit' => '检出该提交（分离 HEAD）',
			'gitGraph.checkoutCommitConfirmBody' => ({required String hash}) => '以分离 HEAD 状态检出 ${hash} 吗？',
			'gitGraph.cherryPick' => '摘取（Cherry-pick）',
			'gitGraph.columnAuthor' => '作者',
			'gitGraph.columnCommit' => '提交',
			'gitGraph.columnDate' => '日期',
			'gitGraph.columnDescription' => '说明',
			'gitGraph.columnGraph' => '图',
			'gitGraph.columnHeaderLabel' => '列头',
			'gitGraph.columns' => '列',
			'gitGraph.commits' => '提交',
			'gitGraph.compareFilterHint' => '过滤分支、标签与提交',
			'gitGraph.compareWith' => '与…比较',
			'gitGraph.compareWorkingTree' => ({required String branch}) => '工作区（${branch}）',
			'gitGraph.conflictHint' => '请先解决冲突并暂存相关文件，然后提交以继续。',
			'gitGraph.copyHash' => '复制哈希',
			'gitGraph.copySubject' => '复制说明',
			'gitGraph.create' => '创建',
			'gitGraph.createBranchHere' => '在此创建分支',
			'gitGraph.createBranchTitle' => '创建分支',
			'gitGraph.createTagHere' => '在此创建标签',
			'gitGraph.createTagTitle' => '创建标签',
			'gitGraph.currentBranch' => '当前分支',
			'gitGraph.deleteBranch' => ({required String name}) => '删除分支 ${name}',
			'gitGraph.deleteBranchConfirmBody' => ({required String name}) => '确定删除分支“${name}”吗？仅能从该分支到达的提交可能变得不可达，此操作无法撤销。',
			'gitGraph.deleteBranchTitle' => '删除分支',
			'gitGraph.deleteRemoteBranchConfirmBody' => ({required String name}) => '确定删除共享仓库上的远程分支“${name}”吗？这将影响所有协作者，且无法撤销。',
			'gitGraph.deleteRemoteBranchTitle' => '删除远程分支',
			'gitGraph.deleteTag' => ({required String name}) => '删除标签 ${name}',
			'gitGraph.deleteTagConfirmBody' => ({required String name}) => '确定删除标签“${name}”吗？此操作无法撤销。',
			'gitGraph.deleteTagTitle' => '删除标签',
			'gitGraph.fetch' => '抓取',
			'gitGraph.hashCopied' => '哈希已复制到剪贴板',
			'gitGraph.hashSearchEmptyHint' => '已加载的提交中没有匹配该哈希的记录，请继续向下滚动或点击“加载更多”以载入更早的历史。',
			'gitGraph.hideColumn' => ({required String column}) => '隐藏${column}',
			'gitGraph.hideColumnHeader' => '隐藏列头',
			'gitGraph.loadMore' => '加载更多',
			'gitGraph.loadingMore' => '加载中…',
			'gitGraph.localBranches' => '本地分支',
			'gitGraph.mergeIntoCurrent' => ({required String branch}) => '合并 ${branch} 到当前分支',
			'gitGraph.noCommits' => '未找到提交',
			'gitGraph.notARepository' => '不是 Git 仓库',
			'gitGraph.pull' => '拉取',
			'gitGraph.push' => '推送',
			'gitGraph.pushTag' => ({required String name}) => '推送标签 ${name}',
			'gitGraph.refresh' => '刷新',
			'gitGraph.refsFilterEmpty' => '无匹配项',
			'gitGraph.refsFilterHint' => '过滤分支与标签',
			'gitGraph.remoteBranches' => '远程分支',
			'gitGraph.renameBranch' => '重命名分支…',
			'gitGraph.renameBranchTitle' => '重命名分支',
			'gitGraph.reset' => '重置（Reset）',
			'gitGraph.resetHard' => '硬重置（Hard）',
			'gitGraph.resetHardConfirmBody' => ({required String branch}) => '硬重置会把“${branch}”移动到此提交，并丢弃所有未提交的更改。输入“${branch}”以确认。',
			'gitGraph.resetMixed' => '混合重置（Mixed）',
			'gitGraph.resetSoft' => '软重置（Soft）',
			'gitGraph.revert' => '回退（Revert）',
			'gitGraph.revertConfirmBody' => ({required String hash}) => '确定回退提交 ${hash} 吗？将创建一个撤销该提交的新提交。',
			'gitGraph.searchHint' => '搜索提交（消息 / 作者 / 哈希）',
			'gitGraph.searchModeAuthor' => '作者',
			'gitGraph.searchModeHash' => '哈希',
			'gitGraph.searchModeMessage' => '消息',
			'gitGraph.selectCommit' => '选择一个提交查看详情',
			'gitGraph.showColumnHeader' => '显示列头',
			'gitGraph.stash' => '贮藏',
			'gitGraph.stashApply' => '应用',
			'gitGraph.stashDrop' => '丢弃',
			'gitGraph.stashDropConfirmBody' => ({required String selector}) => '确定丢弃 ${selector} 吗？此操作无法撤销。',
			'gitGraph.stashPop' => '弹出',
			'gitGraph.subjectCopied' => '说明已复制到剪贴板',
			'gitGraph.tagMessageLabel' => '说明（可选）',
			'gitGraph.tagNameLabel' => '标签名称',
			'gitGraph.tags' => '标签',
			'gitGraph.title' => '提交图',
			'gitGraph.uncommittedChanges' => '未提交的更改',
			'gitGraph.viewBranchHistory' => '查看此分支历史',
			'gitGraph.viewTagHistory' => '查看此标签历史',
			'github.advancedPat' => '使用个人访问令牌',
			'github.advancedPatSubtitle' => '无法使用 GitHub 登录时，或你更想用带 repo 权限的令牌时。',
			'github.authDenied' => '已取消 GitHub 授权',
			'github.authExpired' => 'GitHub 登录已失效',
			'github.authExpiredRetry' => '授权已过期，请重试。',
			'github.browserOpened' => '已打开浏览器进行授权',
			'github.connectedAs' => ({required Object login}) => '已连接为 @${login}',
			'github.connectedGeneric' => '已连接到 GitHub',
			'github.deviceFlowUnavailable' => '此构建暂不支持 GitHub 登录。请使用个人访问令牌。',
			'github.disconnect' => '断开连接',
			'github.networkError' => '无法连接 GitHub，请重试。',
			'github.reopenBrowser' => '重新打开浏览器',
			'github.settingsSubtitle' => '连接 GitHub，以便将专家和团队发布到 Hub',
			'github.settingsTitle' => 'GitHub',
			'github.signIn' => '使用 GitHub 登录',
			'github.switchAccount' => '切换账号',
			'github.waitingCodeHint' => '如有提示，请在 GitHub 上输入此验证码',
			'grok.credentialsActionFailed' => 'Grok 操作失败',
			'grok.credentialsCancel' => '取消',
			'grok.credentialsDone' => '完成',
			'grok.credentialsLogin' => '登录',
			'grok.credentialsLoginExited' => 'Grok CLI 已退出。请关闭此对话框后重新登录。',
			'grok.credentialsLoginFailed' => ({required String error}) => '无法启动登录终端：${error}',
			'grok.credentialsLoginIntro' => '在下方终端完成设备登录。Grok 会显示验证码并打开浏览器；如果没有打开，请手动访问它输出的链接。也可以在这里切换账号。',
			'grok.credentialsLoginStarting' => '正在启动 Grok CLI…',
			'grok.credentialsLoginTitle' => '登录 Grok',
			'grok.credentialsRelaunch' => '重新启动',
			'grok.credentialsSignedIn' => '已登录',
			'grok.credentialsImportGlobal' => '导入已有登录',
			'home.connectionCancelRetry' => '取消重试',
			'home.connectionErrorAuth' => '认证失败',
			'home.connectionErrorHostKey' => '主机身份已变更 — 请重新配对或确认新密钥',
			'home.connectionErrorTcp' => '网络不可达',
			'home.connectionErrorTimeout' => '连接超时',
			'home.connectionErrorTransport' => '连接出错',
			'home.connectionErrorUnknown' => '未知错误',
			'home.connectionRetryNow' => '继续重试',
			'home.connectionRetrying' => ({required int count}) => '正在重试…第 ${count} 次',
			'home.connectionSwitch' => '切换连接',
			'home.connectionUnreachable' => ({required String host, required int port}) => '无法连接 ${host}:${port}',
			'home.targetSingleOptionHint' => '当前平台只有这一个可用的主设备。',
			'home.targetSubtitle' => 'TeamPilot 存放团队、工作区与配置的位置（控制面）。切换会使用独立的数据目录，不会自动迁移。',
			'home.targetTitle' => '主设备',
			'homeWorkspace.allWorkspaces' => '全部工作区',
			'homeWorkspace.cloneWorkspace' => '克隆工作区',
			'homeWorkspace.cloneWorkspaceDisplayName' => ({required Object name}) => '${name}（副本）',
			'homeWorkspace.cloneWorkspaceFailed' => '无法克隆工作区',
			'homeWorkspace.cloneWorkspaceSuccess' => ({required Object name}) => '已克隆「${name}」。',
			'homeWorkspace.closeAllTabsMessage' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, one: '关闭全部标签会终止 1 个运行中的会话。', other: '关闭全部标签会终止 ${count} 个运行中的会话。', ), 
			'homeWorkspace.closeAllTabsTitle' => '关闭全部标签？',
			'homeWorkspace.closeWorkspaceConfirm' => '关闭并终止会话',
			'homeWorkspace.closeWorkspaceMessage' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, one: '关闭该标签会终止此工作区中 1 个运行中的会话。', other: '关闭该标签会终止此工作区中 ${count} 个运行中的会话。', ), 
			'homeWorkspace.closeWorkspaceTitle' => '关闭工作区？',
			'homeWorkspace.comingSoon' => '功能开发中',
			'homeWorkspace.conversations' => '对话管理',
			'homeWorkspace.conversationsSection' => '对话',
			'homeWorkspace.createTeam' => '创建团队',
			'homeWorkspace.createWorkspace' => '创建工作区',
			'homeWorkspace.defaultMixedTeamName' => '默认混合团队',
			'homeWorkspace.defaultNativeTeamName' => '默认原生团队',
			'homeWorkspace.defaultPersonalWorkspaceName' => '个人助手',
			'homeWorkspace.emptyWorkspaces' => '该团队还没有工作区',
			'homeWorkspace.emptyWorkspacesHint' => '新建或导入一个工作区开始吧',
			'homeWorkspace.favoriteWorkspace' => '收藏工作区',
			'homeWorkspace.importWorkspace' => '导入工作区',
			'homeWorkspace.inviteMembers' => '邀请成员',
			'homeWorkspace.launchWorkspaceTitle' => '选择启动方式',
			'homeWorkspace.mainWindow' => '主窗口',
			'homeWorkspace.myFavorites' => '我的收藏',
			'homeWorkspace.newConversation' => '新建对话',
			'homeWorkspace.newConversationChooseCli' => '选择 CLI 新建对话',
			'homeWorkspace.newTeam' => '新建团队',
			'homeWorkspace.newTeamMethodAi' => 'AI 生成',
			'homeWorkspace.newTeamMethodCustom' => '自定义模式',
			'homeWorkspace.newTeamModeBeta' => 'Beta',
			'homeWorkspace.newTeamNameHint' => '请输入团队名称',
			'homeWorkspace.newTeamRecommended' => '推荐',
			'homeWorkspace.newTeamSubtitle' => '选择团队协作模式，并填写团队名称。',
			'homeWorkspace.newTeamSubtitleAi' => '描述团队需求，用 AI 生成团队配置草稿。',
			'homeWorkspace.newWorkspaceChooseDirectory' => '选择文件夹',
			'homeWorkspace.newWorkspaceDirectoryHint' => '尚未选择目录',
			'homeWorkspace.newWorkspaceDirectoryLabel' => '工作区目录',
			'homeWorkspace.newWorkspaceNameHint' => '默认使用文件夹名',
			'homeWorkspace.newWorkspaceSubtitle' => '选择工作区的工作目录，并为它命名。',
			'homeWorkspace.noConversations' => '该工作区还没有对话',
			'homeWorkspace.noData' => '暂无数据',
			'homeWorkspace.noSearchResults' => '没有匹配的对话',
			'homeWorkspace.openInNewTabWithOtherIdentity' => '以其他身份在新标签页打开…',
			'homeWorkspace.openTabs' => '已打开',
			'homeWorkspace.openWorkspaceInNewTab' => '在新标签页中打开',
			'homeWorkspace.owner' => '团队所有者',
			'homeWorkspace.personal' => '简单模式',
			'homeWorkspace.personalSubtitle' => '不用组队，直接拉起一个 CLI 开聊。',
			'homeWorkspace.providers' => '供应商',
			'homeWorkspace.recentVisits' => '最近访问',
			'homeWorkspace.recentlyClosed' => '最近关闭',
			'homeWorkspace.recentlyClosedEmpty' => '暂无最近关闭的工作区',
			'homeWorkspace.rememberLaunchChoice' => '记住选择',
			'homeWorkspace.renameWorkspace' => '修改名称',
			'homeWorkspace.searchHint' => '搜索',
			'homeWorkspace.sessionsLabel' => '会话',
			'homeWorkspace.simpleMode' => '简单模式',
			'homeWorkspace.teamConfig' => '团队配置',
			'homeWorkspace.teamWorkspaces' => '团队工作区',
			'homeWorkspace.unfavoriteWorkspace' => '取消收藏',
			'homeWorkspace.workspaceAgent' => '智能体',
			'homeWorkspace.workspaceExtensions' => '扩展',
			'homeWorkspace.workspaceFilterEmpty' => '没有匹配的工作区',
			'homeWorkspace.workspaceFilterHint' => '过滤工作区',
			'homeWorkspace.workspaceHooks' => 'Hooks',
			'homeWorkspace.workspaceId' => '工作区 ID',
			'homeWorkspace.workspaceList' => '工作区列表',
			'homeWorkspace.workspaceManagement' => '工作区管理',
			'homeWorkspace.workspaceMcp' => 'MCP',
			'homeWorkspace.workspaceMembers' => '成员',
			'homeWorkspace.workspacePath' => '工作区路径',
			'homeWorkspace.workspacePlugins' => '插件',
			'homeWorkspace.workspaceSettings' => '工作区设置',
			'homeWorkspace.workspaceSettingsBasicInfo' => '基本信息',
			'homeWorkspace.workspaceSettingsPathsHint' => '在「附加目录」行点击编辑，可添加或移除工作区附加目录。',
			'homeWorkspace.workspaceSettingsSectionBasic' => '基本设置',
			'homeWorkspace.workspaceSkills' => '技能',
			'homeWorkspace.workspaceSort' => '排序工作区',
			'homeWorkspace.workspaceSortCreatedDesc' => '创建时间',
			'homeWorkspace.workspaceSortNameAsc' => '名称（A–Z）',
			'homeWorkspace.workspaceSortNameDesc' => '名称（Z–A）',
			'homeWorkspace.workspaceSortRecentlyUpdated' => '最近更新',
			'homeWorkspace.workspaceSortSessionCountDesc' => '会话数量',
			'homeWorkspace.workspaceAdditionalDirsCount' => ({required int count}) => '${count} 个附加目录',
			'hook.actionCommand' => '命令',
			'hook.actionScript' => '脚本',
			'hook.capabilityMatrix' => '能力矩阵',
			'hook.description' => '描述',
			'hook.edit' => '编辑 hook',
			'hook.env' => '环境变量（每行 KEY=VALUE）',
			'hook.event' => '事件',
			'hook.import' => '导入',
			'hook.importCli' => 'CLI',
			'hook.importDoneToast' => '已导入 hooks',
			'hook.importInvalidJson' => 'Hook JSON 无效',
			'hook.importJson' => 'Hook JSON',
			'hook.importJsonHint' => '粘贴 settings.json hooks、hooks.json 或 hooks 片段…',
			'hook.importNoHooks' => '未找到 hooks',
			'hook.importOverwrite' => '将覆盖',
			'hook.importParse' => '解析',
			'hook.installedCount' => ({required int count}) => '已安装 ${count}',
			'hook.matcher' => '匹配器',
			'hook.name' => '名称',
			'hook.nameRequired' => '名称为必填项',
			'hook.navTitle' => 'Hooks',
			'hook.kNew' => '新建 hook',
			'hook.policy' => '策略',
			'hook.save' => '保存',
			'hook.saveFailed' => '保存 Hook 失败。',
			'hook.supportMatrix' => '查看受支持程度',
			'hook.timeoutSec' => '超时（秒）',
			'hook.importDone' => ({required int count}) => '导入 ${count} 条',
			'hub.publishAuthHint' => '使用 GitHub 登录并授权，以向 Hub 仓库发起基于 fork 的拉取请求。',
			'hub.publishAuthorLabel' => '作者',
			'hub.publishBadgePrOpen' => 'PR 已开',
			'hub.publishBadgePublished' => '已发布',
			'hub.publishCategoryRequired' => '分类为必填项',
			'hub.publishConfirmHint' => '请核对包元数据，然后发布基于 fork 的拉取请求。',
			'hub.publishCopyLink' => '复制链接',
			'hub.publishDone' => '完成',
			'hub.publishExpertTitle' => '发布专家到 Hub',
			'hub.publishGatesClear' => '依赖均可移植，可继续确认。',
			'hub.publishKindExpert' => '专家',
			'hub.publishKindLabel' => '类型',
			'hub.publishKindTeam' => '团队',
			'hub.publishLocalExpertBlocked' => '请先映射所有本地专家后再继续',
			'hub.publishLocalExpertHint' => '花名册中的本地专家须先映射为已发布或内置专家，才能上传。',
			'hub.publishNext' => '下一步',
			'hub.publishNonPortableBlocked' => '请先移除不可移植依赖后再继续',
			'hub.publishNonPortableHint' => '以下依赖没有可移植来源。请先从团队配置中移除后再发布：',
			'hub.publishOpenPr' => '打开 PR',
			'hub.publishPublish' => '发布',
			'hub.publishRemapLabel' => '发布为',
			'hub.publishSlugHint' => 'url-safe-id',
			'hub.publishSlugLabel' => '标识（slug）',
			'hub.publishSlugRequired' => '标识为必填项',
			'hub.publishSuccessHint' => '拉取请求已创建。可复制或打开下方链接。',
			'hub.publishTeamTitle' => '发布团队到 Hub',
			'hub.publishTokenHint' => 'ghp_…',
			'hub.publishTokenLabel' => 'GitHub 令牌',
			'hub.publishTokenRequired' => '发布需要 GitHub 令牌',
			'hub.publishTokenSaveFailed' => '无法保存 GitHub 令牌',
			'hub.publishTokenStored' => '已保存令牌，可在下方替换。',
			'init.errorCopied' => '已复制',
			'init.errorCopy' => '复制',
			'init.errorCopyReport' => '复制报告',
			'init.errorDetails' => '错误信息',
			'init.errorPendingLogs' => '待写入日志',
			'init.errorStackEmpty' => '（堆栈为空）',
			'init.errorStackTrace' => '堆栈跟踪',
			'init.errorTitle' => '应用启动失败',
			'init.errorVersion' => ({required String version, required String build}) => '版本 ${version}（${build}）',
			'init.errorViewLogs' => '查看日志',
			'landing.launchAcpUnsupported' => ({required String cli, required String target}) => '${cli} 仅支持 ACP 对话，当前目标（${target}）无法运行 ACP。请选择本机、SSH 或 Termux 目标，或改用支持终端的 CLI。',
			'landing.launchLocalAdapterMissingDetail' => ({required String cli}) => '未找到 ${cli} ACP 适配器',
			'landing.launchLocalCliMissing' => '启动前请先在本机安装所需的 AI CLI。',
			'landing.launchLocalCliMissingDetail' => ({required String cli}) => '未找到 ${cli}',
			'landing.launchLocalCliMissingHint' => '可直接在此安装，或在设置 → CLI 中指定可执行文件路径。',
			'landing.launchLocalCliMissingTitle' => '本机需要的 AI CLI',
			'landing.launchLocalCliOpenSettings' => '打开设置',
			'landing.launchRemoteCliMissing' => '启动前请在远程机器上安装所需的 CLI。',
			'landing.launchRemoteCliMissingDetail' => ({required String host, required String cli}) => '${host} 上缺少 ${cli}',
			'landing.teamSettingsGlobalHint' => '更改将应用于该团队的全局配置。',
			'landing.teamSettingsNavMachines' => '机器分配',
			'landing.teamSettingsNavTeam' => '团队默认',
			'llm.config' => '服务商',
			'llm.configCurrentEffectivePathPrefix' => '当前文件：',
			'llm.configEffectivePathUnresolved' => '尚未解析出路径（请指定 CLI 或自定义路径）',
			'llm.configOpenSessionSettings' => '会话设置…',
			'llm.configPageSubtitle' => '管理 LLM 提供商和模型。',
			'llm.configPathBadgeCustom' => '自定义',
			'llm.configPathBadgeDefault' => '默认',
			'llm.configPathBrowse' => '选择文件',
			'llm.configPathHint' => '留空则使用默认路径',
			'llm.configPathLabel' => 'LLM 配置文件',
			'llm.configPathPickerTitle' => '选择 llm_config.json',
			'llm.configPathReset' => '默认',
			'llm.configPathSave' => '更新',
			'llm.configPathSessionCardDescription' => 'LLM 配置文件（llm_config.json）的绝对路径。留空则使用 CLI 安装目录旁的默认路径。',
			'llm.configPathSessionCardDescriptionSsh' => 'SSH 远端主机上 llm_config.json 的绝对路径。留空则使用远端 CLI 安装目录旁的默认路径。',
			'llm.configSubtitle' => '提供商和模型',
			'log.installJobCopy' => '复制',
			'log.installJobEmpty' => '暂无输出。',
			'log.installJobPaused' => '已暂停',
			'log.installJobResume' => '跟随',
			'log.installJobTitle' => '安装日志',
			'log.installJobUnavailable' => '日志不可用——文件已被清理。',
			'log.installJobViewLog' => '查看日志',
			'log.viewerAcpFrames' => 'ACP 协议帧日志（默认关闭）',
			'log.viewerActionsMenu' => '更多操作',
			'log.viewerAllCopied' => '已复制全部过滤后的日志',
			'log.viewerClearDone' => '已清理过期日志',
			'log.viewerClearFailed' => ({required String error}) => '清理失败：${error}',
			'log.viewerClearOld' => '清理过期日志',
			'log.viewerCompactView' => '简洁视图',
			'log.viewerCopyAll' => '复制全部日志',
			'log.viewerCopyPath' => '复制日志路径',
			'log.viewerEmpty' => '暂无日志文件',
			'log.viewerEmptyHint' => '应用运行后会在此生成日志。',
			'log.viewerFileLabel' => '日志文件',
			'log.viewerFilterLevel' => '级别',
			'log.viewerFilterTitle' => '过滤',
			'log.viewerLineCount' => ({required int count}) => '${count} 行',
			'log.viewerLoadFilesFailed' => ({required String error}) => '加载日志列表失败：${error}',
			'log.viewerPathCopied' => ({required String name}) => '已复制路径：${name}',
			'log.viewerPendingBody' => '以下为等待写入文件的缓冲条目：',
			'log.viewerPendingTitle' => '日志尚未写入磁盘',
			'log.viewerReadFailed' => ({required String error}) => '读取日志失败：${error}',
			'log.viewerRefresh' => '刷新',
			'log.viewerReverseOrder' => '从最新内容开始',
			'log.viewerSearchHint' => '搜索日志…',
			'log.viewerSubtitle' => '应用数据目录下的运行日志与错误记录。',
			'log.viewerTitle' => '日志',
			'log.viewerWrapLines' => '自动换行',
			'managedProviders.adapter' => '适配器',
			'managedProviders.adapterHint' => 'http-json 或已注册的适配器 ID',
			'managedProviders.add' => '添加 Provider',
			'managedProviders.advancedSectionSubtitle' => '适配器、类型与内部引用。',
			'managedProviders.advancedSectionTitle' => '适配器、类型与引用',
			'managedProviders.authenticationFailed' => 'Provider 身份验证失败。',
			'managedProviders.basicsSectionSubtitle' => '命名与必要密钥。',
			'managedProviders.basicsSectionTitle' => '名称与密钥',
			'managedProviders.basicsSummary' => '选择预设、命名，并按需填写密钥。',
			'managedProviders.cachedUsage' => '缓存用量',
			'managedProviders.cachedUsageStale' => '缓存用量 · 需要刷新',
			'managedProviders.cancel' => '取消',
			'managedProviders.credentialConfigured' => '已配置凭据 · 密钥已隐藏',
			'managedProviders.credentialField' => '密钥字段名',
			'managedProviders.credentialFieldHelper' => '本地存储用的字段名。',
			'managedProviders.credentialFieldHint' => 'apiKey 或 accessToken',
			'managedProviders.credentialFieldRequired' => '保存 API Key 前请先填写凭据字段。',
			'managedProviders.credentialLinkEmpty' => '还没有可引用的供应商配置',
			'managedProviders.credentialLinkManual' => '手动输入密钥',
			'managedProviders.credentialLinkMode' => '凭据来源方式',
			'managedProviders.credentialLinkedTo' => ({required Object provider}) => '使用 ${provider} 的凭证',
			'managedProviders.credentialName' => '凭据参数名',
			'managedProviders.credentialNameHelper' => '写入请求时的参数名。',
			'managedProviders.credentialNameHint' => 'Authorization 或 Cookie',
			'managedProviders.credentialNone' => '未配置凭据',
			'managedProviders.credentialPlacement' => '凭据位置',
			'managedProviders.credentialPlacementHelper' => 'header 或 query。',
			'managedProviders.credentialPlacementHint' => 'header 或 query',
			'managedProviders.credentialRef' => '凭据引用',
			'managedProviders.credentialRefHint' => '仅保存引用，不会显示密钥',
			'managedProviders.credentialSaveFailed' => '无法安全保存 Provider 凭据。',
			'managedProviders.credentialSecret' => 'API Key / Token',
			'managedProviders.credentialSecretExistingHint' => '留空保留已保存密钥',
			'managedProviders.credentialSecretHelper' => '留空保留已保存密钥。',
			'managedProviders.credentialSecretHint' => '填入 Provider 的 API Key 或 Token',
			'managedProviders.credentialSource' => '凭据来源',
			'managedProviders.credentialSourceHelper' => 'secret 读表单；cli:… 读 CLI 登录。',
			'managedProviders.credentialSourceHint' => 'secret 或 cli:cursor-mp-<entry>',
			'managedProviders.credentialTemplate' => '凭据拼接模板',
			'managedProviders.credentialTemplateHelper' => '拼成最终凭据值，常用于 Cookie；用花括号填变量。',
			'managedProviders.credentialTemplateHint' => '例如 WorkosCursorSessionToken=user::token',
			'managedProviders.credentials' => '凭据',
			'managedProviders.credentialsSectionSubtitle' => '凭据来源及写入请求的方式。',
			'managedProviders.credentialsSectionTitle' => '凭据来源与请求写入',
			'managedProviders.currency' => '货币',
			'managedProviders.currencyMappingHelper' => '已配置映射时从响应读取货币。',
			'managedProviders.decimalError' => '小数位必须是整数。',
			'managedProviders.decimals' => '小数位',
			'managedProviders.delete' => '删除',
			'managedProviders.deleteContent' => ({required Object name}) => '删除“${name}”及其缓存用量？',
			'managedProviders.deleteFailed' => '无法删除管理 Provider。',
			'managedProviders.deleteTitle' => '删除管理 Provider？',
			_ => null,
		} ?? switch (path) {
			'managedProviders.disable' => '禁用',
			'managedProviders.disabled' => '已禁用',
			'managedProviders.display' => '显示配置',
			'managedProviders.displaySectionSubtitle' => '余额与额度的显示格式。',
			'managedProviders.displaySectionTitle' => '余额与额度显示',
			'managedProviders.dynamicCurrencyHelper' => '货币从响应映射读取。',
			'managedProviders.edit' => '编辑',
			'managedProviders.editTitle' => '编辑管理 Provider',
			'managedProviders.emptyHint' => '添加 Provider 以独立跟踪余额和配额。',
			'managedProviders.emptyTitle' => '暂无管理 Provider',
			'managedProviders.enable' => '启用',
			'managedProviders.enabled' => '已启用',
			'managedProviders.enabledSubtitle' => '关闭后隐藏并停止查询。',
			'managedProviders.enabledTitle' => '启用',
			'managedProviders.endpoint' => '用量 API 地址',
			'managedProviders.endpointError' => '此 HTTP 适配器需要 HTTPS 或回环地址。',
			'managedProviders.endpointHelper' => '获取用量数据的请求地址。',
			'managedProviders.endpointHint' => 'https://api.example.com/usage',
			'managedProviders.error' => '错误',
			'managedProviders.fieldExampleLabel' => '示例',
			'managedProviders.fieldMappingError' => '字段映射必须是无密钥的 JSON 对象。',
			'managedProviders.fieldMappings' => '列表项字段映射（JSON）',
			'managedProviders.fieldMappingsHelper' => '数组每项各字段在响应中的 \$ 路径。',
			'managedProviders.headers' => '请求头（JSON）',
			'managedProviders.headersHelper' => '额外请求头；值可用花括号占位。',
			'managedProviders.headersHint' => 'Accept: application/json',
			'managedProviders.httpFailed' => 'Provider 服务返回错误。',
			'managedProviders.identity' => '基本信息',
			'managedProviders.jsonPathSeeAlso' => '\$ 用法详见「用量 API 与 JSON 解析」ℹ️',
			'managedProviders.kind' => '类型',
			'managedProviders.kindApiBalance' => 'API 余额',
			'managedProviders.kindCustomHttp' => '自定义 HTTP',
			'managedProviders.kindPresetLockedHelper' => '当前预设或模板已锁定类型。',
			'managedProviders.kindSubscriptionQuota' => '订阅额度',
			'managedProviders.lastQueryFailed' => '上次查询失败',
			'managedProviders.loadFailed' => '无法加载管理 Provider。',
			'managedProviders.loadingUsage' => '正在加载用量',
			'managedProviders.measuresPath' => '用量列表（\$）',
			'managedProviders.measuresPathHelper' => '每项一条余额的 \$ 路径（如 DeepSeek）。',
			'managedProviders.measuresPathHint' => '\$.balance_infos',
			'managedProviders.method' => 'HTTP 方法',
			'managedProviders.methodHelper' => '一般为 GET。',
			'managedProviders.missingCredential' => 'Provider 凭据缺失。',
			'managedProviders.name' => '名称',
			'managedProviders.nameAdapterError' => '名称和适配器不能为空。',
			'managedProviders.nameHint' => '显示名称',
			'managedProviders.nav' => '管理 Provider',
			'managedProviders.networkFailed' => 'Provider 网络请求失败。',
			'managedProviders.newTitle' => '新建管理 Provider',
			'managedProviders.noUsage' => '尚未查询用量',
			'managedProviders.noneEnabledHint' => '启用 Provider 后才会显示在状态栏并参与查询。',
			'managedProviders.noneEnabledTitle' => '没有已启用的 Provider',
			'managedProviders.queryCompleted' => 'Provider 查询完成。',
			'managedProviders.queryFailed' => '无法查询 Provider 用量。',
			'managedProviders.querySectionSubtitle' => '用量 API 与 JSON 解析。',
			'managedProviders.querySectionTitle' => '用量 API 与 JSON 解析',
			'managedProviders.queryUnsupported' => '不支持查询',
			'managedProviders.quickPresetClaudeCode' => 'Claude Code',
			'managedProviders.quickPresetClaudeCodeHint' => '登录或导入，或手填相同字段。',
			'managedProviders.quickPresetCodebuddy' => 'CodeBuddy',
			'managedProviders.quickPresetCodebuddyHint' => '使用 CodeBuddy 登录态查询积分余额。',
			'managedProviders.quickPresetCodex' => 'Codex',
			'managedProviders.quickPresetCodexHint' => '登录或导入，或手填相同字段。',
			'managedProviders.quickPresetCursor' => 'Cursor',
			'managedProviders.quickPresetCursorHint' => '登录或导入，或手填相同字段。',
			'managedProviders.quickPresetGrokX' => 'Grok / Cursor / X',
			'managedProviders.quickPresetGrokXHint' => '使用 Cursor 登录态查询合一后的周额度和预付费。',
			'managedProviders.quickPresetCustom' => '自定义',
			'managedProviders.quickPresetCustomHint' => '从零配置接口、凭据与显示格式。',
			'managedProviders.quickPresetDeepSeek' => 'DeepSeek',
			'managedProviders.quickPresetDeepSeekHint' => '已配余额接口，需填密钥。',
			'managedProviders.quickPresetHint' => '使用安全默认值开始；查询前请补充凭据。',
			'managedProviders.quickPresetOpencodeGo' => 'OpenCode Go',
			'managedProviders.quickPresetOpencodeGoHint' => 'Zen Go 订阅用量预设，需填 API 密钥。',
			'managedProviders.quickPresetQoder' => 'Qoder',
			'managedProviders.quickPresetQoderCn' => 'Qoder CN',
			'managedProviders.quickPresetQoderCnHint' => '使用 qoder.com.cn/account/integrations 生成的 PAT 查询套餐积分。',
			'managedProviders.quickPresetQoderHint' => '使用 qoder.com/account/integrations 生成的 PAT 查询套餐积分。',
			'managedProviders.quickPresetTitle' => '快速预设',
			'managedProviders.referenceSyntaxHelper' => '\$ — 从 HTTP 响应的 JSON 里读数\n\$ 表示整段响应，\$.字段名 用点号一层层往下取。\n例：\$.data、\$.balance_infos[0].total_balance、\$.rate_limit.used_percent\n\n用于「响应根路径」和额度窗口里的 used / total / remaining / resetsAt 等字段。\n\n花括号 — 往请求里填动态值（不是读响应）\n花括号内写变量名，发送时替换为凭据里的值。\n• accessToken — 访问令牌\n• accountId — 账号 ID\n• jwt.sub — JWT 的 sub\n\n用于请求头、Cookie、凭据模板。cli:… 登录后才有这些值。',
			'managedProviders.refreshFailed' => '无法刷新 Provider 用量。',
			'managedProviders.remainingPercent' => ({required String percent}) => '${percent}剩余 %',
			'managedProviders.requestMapping' => '请求体（JSON）',
			'managedProviders.requestMappingError' => '请求映射必须是 JSON 对象。',
			'managedProviders.requestMappingHelper' => 'POST 时用；GET 留空。',
			'managedProviders.resetsIn' => ({required String duration}) => '${duration}后重置',
			'managedProviders.resetsSoon' => '即将重置',
			'managedProviders.responseParseFailed' => '无法解析 Provider 响应。',
			'managedProviders.responsePath' => '响应根路径（\$）',
			'managedProviders.responsePathHelper' => '数据在嵌套层时用 \$ 先定位；留空从响应根解析。',
			'managedProviders.responsePathHint' => '\$.data',
			'managedProviders.retry' => '重试',
			'managedProviders.save' => '保存',
			'managedProviders.saveFailed' => '无法保存管理 Provider。',
			'managedProviders.saveProvider' => '保存 Provider',
			'managedProviders.saved' => '管理 Provider 已保存。',
			'managedProviders.saving' => '保存中…',
			'managedProviders.secretMappingError' => '请使用凭据引用，不要将密钥放入请求映射。',
			'managedProviders.sectionConfiguredBadge' => '已配置',
			'managedProviders.showPercent' => '显示百分比',
			'managedProviders.stale' => '已过期',
			'managedProviders.subtitle' => '独立于 CLI Provider 配置查看余额和配额。',
			'managedProviders.templateVariablesSeeAlsoCredentials' => '花括号用法详见「凭据来源与请求写入」ℹ️',
			'managedProviders.templateVariablesSeeAlsoQuery' => '花括号用法详见「用量 API 与 JSON 解析」ℹ️',
			'managedProviders.testProviderQuery' => '测试 Provider 查询',
			'managedProviders.testQuery' => '测试查询',
			'managedProviders.title' => '管理 Provider',
			'managedProviders.unit' => '单位',
			'managedProviders.unknownUsage' => '未知用量状态',
			'managedProviders.usageInvalidated' => 'Provider 用量已失效。',
			'managedProviders.usageLoadFailed' => '无法加载 Provider 用量。',
			'managedProviders.usageNav' => '余额与用量',
			'managedProviders.usagePersistenceFailed' => '无法保存 Provider 用量。',
			'managedProviders.windows' => '额度窗口（JSON）',
			'managedProviders.windowsHelper' => '每条额度写一行。每项写 label 与 used / total / remaining / resetsAt 的 \$ 路径。数组项请写死下标，如 \$.balance_infos[0].total_balance。',
			'managedProviders.windowsHint' => 'JSON 数组；每项含 label 与 \$ 路径',
			'mcp.add' => '添加 MCP',
			'mcp.addButton' => '添加 MCP',
			'mcp.addTitle' => '新增 MCP',
			'mcp.catalogAdd' => '添加',
			'mcp.catalogAdded' => '已加入 MCP 目录',
			'mcp.catalogAdoption' => '使用量',
			'mcp.catalogCardNoDescription' => '无',
			'mcp.catalogEmpty' => '未找到服务器',
			'mcp.catalogInstalled' => '已安装',
			'mcp.catalogVerified' => '已认证',
			'mcp.configuredCount' => ({required int count}) => '已配置 ${count} 个 MCP 服务器',
			'mcp.deleteConfirm' => '删除该 MCP 服务器？',
			'mcp.discoverySectionHint' => '浏览内置模板，以及「仓库」中配置的远程目录。',
			'mcp.discoverySectionTitle' => '发现 MCP 服务器',
			'mcp.discoverySourceAll' => '全部',
			'mcp.discoverySourceBuiltin' => '内置',
			'mcp.edit' => '编辑 MCP',
			'mcp.empty' => '目录中暂无 MCP 服务器',
			'mcp.emptyGoDiscovery' => '浏览内置模板',
			'mcp.emptyGoRegistries' => '打开注册中心',
			'mcp.fieldArgs' => '参数（空格分隔）',
			'mcp.fieldCommand' => '命令',
			'mcp.fieldName' => '名称',
			'mcp.formDescriptionHint' => '可选的描述信息',
			'mcp.formDescriptionLabel' => '描述',
			'mcp.formDetailHint' => '选择服务器进行编辑，或添加新的 MCP 服务器。',
			'mcp.formDisplayNameHint' => '例如 @modelcontextprotocol/server-time',
			'mcp.formDisplayNameLabel' => '显示名称',
			'mcp.formDocsLabel' => '文档链接',
			'mcp.formFormatJson' => '格式化',
			'mcp.formHomepageLabel' => '主页链接',
			'mcp.formIdLabel' => 'MCP 标题（唯一）*',
			'mcp.formJsonLabel' => '完整的 JSON 配置',
			'mcp.formMetadata' => '附加信息',
			'mcp.formRequiredFields' => '请填写 MCP 标题与显示名称。',
			'mcp.formSubmitAdd' => '添加',
			'mcp.formTagsHint' => 'stdio, time, utility',
			'mcp.formTagsLabel' => '标签（逗号分隔）',
			'mcp.import' => '从本机导入',
			'mcp.importDone' => 'MCP 目录已更新',
			'mcp.importEmpty' => '在 ~/.claude.json 与 ~/.flashskyai.json 中未找到 MCP',
			'mcp.importExisting' => '导入已有',
			'mcp.importOverwrite' => '覆盖冲突项',
			'mcp.importSummary' => ({required int added, required int conflicts}) => '新增 ${added} 个，冲突 ${conflicts} 个',
			'mcp.installedCount' => ({required int count}) => '已安装 ${count}',
			'mcp.installedSectionTitle' => '已安装的 MCP',
			'mcp.navDiscovery' => '发现',
			'mcp.navInstalled' => '已安装',
			'mcp.navRegistries' => '注册中心',
			'mcp.navTitle' => 'MCP 服务器',
			'mcp.noInstalled' => '还没有安装 MCP 服务器',
			'mcp.noInstalledHint' => '打开发现页，从内置模板或注册中心添加。',
			'mcp.oAuthCallbackUrlHint' => '登录后粘贴完整 URL（含 ?code=）',
			'mcp.oAuthCallbackUrlLabel' => '回调地址',
			'mcp.oAuthConnectAction' => '连接',
			'mcp.oAuthConnectHint' => '在浏览器中完成 MCP 提供商登录。令牌按 Claude Code 格式写入应用配置目录（等同终端 /mcp → Authenticate）。',
			'mcp.oAuthConnectSuccess' => 'MCP OAuth 已连接',
			'mcp.oAuthConnectTitle' => ({required String name}) => '连接 ${name}',
			'mcp.oAuthDiscovering' => '正在发现授权服务器…',
			'mcp.oAuthOpenBrowser' => '打开浏览器',
			'mcp.oAuthStartConnect' => '连接',
			'mcp.oAuthStatusConnected' => 'OAuth 已连接',
			'mcp.oAuthStatusNeedsAuth' => '需要 OAuth',
			'mcp.oAuthSubmitCallback' => '提交地址',
			'mcp.openHomepage' => '打开链接',
			'mcp.presetDescContext7' => '通过 Context7 获取最新库文档。',
			'mcp.presetDescFetch' => '抓取网页并将 HTML 转为 Markdown，供模型使用。',
			'mcp.presetDescMemory' => '跨会话的持久化记忆图谱。',
			'mcp.presetDescSequentialThinking' => '结构化分步推理，适合复杂问题。',
			'mcp.presetDescTime' => '时间查询：当前时间、时区转换、日期计算等。',
			'mcp.probeChecking' => '检测中…',
			'mcp.probeNeedsAuth' => '需要授权',
			'mcp.probeOffline' => '离线',
			'mcp.probeOfflineHint' => '无法连接此 MCP 服务器。',
			'mcp.probeRefreshAll' => '刷新状态',
			'mcp.probeToolCount' => ({required int count}) => '${count} 个工具',
			'mcp.registryEditTitle' => '编辑 API 地址',
			'mcp.registryLoadMore' => '加载更多',
			'mcp.registryOfficial' => '官方注册表',
			'mcp.registryOfficialHint' => '官方 MCP Registry — https://registry.modelcontextprotocol.io',
			'mcp.registryResetConfirm' => ({required String name}) => '将「${name}」恢复为默认 API 地址？',
			'mcp.registryResetTitle' => '恢复默认',
			'mcp.registrySearchHint' => '搜索服务器（如 github）',
			'mcp.registrySmithery' => 'Smithery',
			'mcp.registrySmitheryHint' => 'Smithery — https://api.smithery.ai',
			'mcp.repoApiUrlLabel' => 'API 基础地址',
			'mcp.repoConfigSaved' => '目录 API 设置已保存',
			'mcp.repoDisabledHint' => '该目录源已禁用，请在「仓库」中启用。',
			'mcp.repoResetDefault' => '恢复默认',
			'mcp.repoTestConnection' => '测试连接',
			'mcp.repoTestFailed' => ({required String error}) => '连接失败：${error}',
			'mcp.repoTestOk' => '连接成功',
			'mcp.serverNotFound' => '未找到该 MCP 服务器',
			'mcp.smitheryApiTokenHint' => 'Smithery API 密钥（Bearer）',
			'mcp.smitheryApiTokenLabel' => 'API Token',
			'mcp.smitheryApiTokenSet' => '已配置 Token',
			'mcp.subtitle' => '为 Agent 会话管理 MCP 服务器配置。',
			'mcp.toolsDialogTitle' => ({required String name}) => '${name} 的工具',
			'mcp.toolsDone' => '完成',
			'mcp.toolsEmpty' => '该服务器没有工具。',
			'mcp.toolsReload' => '重新加载',
			'mcp.toolsSection' => '工具',
			'member.assignFoldersAction' => '分配目录…',
			'member.cliInheritHint' => '继承团队默认',
			'member.detailBrowseConfigDirTitle' => '配置目录',
			'member.detailEmpty' => '该成员尚未在此会话中启动，且团队层无配置。',
			'member.detailLoadError' => '读取该成员的配置目录失败。',
			'member.detailNeedsSession' => '请先打开一个会话',
			'member.detailOpenConfigDir' => '打开配置目录',
			'member.detailOpenConfigDirFailed' => '无法在文件管理器中打开配置目录。',
			'member.detailOpenConfigDirFailedOnHost' => ({required String host}) => '无法在 ${host} 上打开配置目录，远程主机可能没有桌面文件管理器。',
			'member.detailOpenInFileManager' => '在文件管理器中打开',
			'member.detailSectionEmpty' => '无',
			'member.detailSourceRuntime' => '运行会话配置',
			'member.detailSourceTeam' => '团队层配置（该成员未在此会话中启动）',
			'member.detailTabMcp' => 'MCP',
			'member.detailTabOverview' => '概览',
			'member.detailTabPlugins' => '插件',
			'member.detailTabSettings' => '设置',
			'member.detailTabSkills' => 'Skills',
			'member.detailTitle' => '成员详情',
			'member.detailViewAction' => '查看成员详情',
			'member.effortInheritHint' => '继承团队默认',
			'member.effortLevel' => '成员力度覆盖',
			'member.effortLevelSubtitle' => '设置后覆盖团队默认值。',
			'member.extraArgs' => '成员额外 CLI 参数',
			'member.extraArgsSubtitle' => '仅附加在该成员的 CLI 启动参数。',
			'member.launchConfigInheritHint' => '使用团队的默认 CLI、服务商、模型与 Effort。',
			'member.launchConfigInheritUnset' => '团队默认尚未配置。',
			'member.launchConfigSubtitle' => '本成员的 CLI 后端、提供商、模型与 Effort。',
			'member.launchConfigTitle' => '模型配置',
			'member.launchConfigTypeLabel' => '配置类型',
			'member.launchConfigTypePreset' => '预设',
			'member.launchOrder' => '成员启动顺序',
			'member.name' => '成员名称',
			'member.nameSubtitle' => '仅作界面展示用。若要指明职责与边界，请编辑下方的职责。',
			'member.officialClaudeModelHint' => '使用 Claude 账号默认模型；请在 Providers 设置中管理 Official 登录。',
			'member.personaEmptyNoExpert' => '选择专家后可查看人设内容。',
			'member.playbook' => '工作手册',
			'member.playbookEmpty' => '该专家未填写工作手册',
			'member.playbookPresetDeveloperText' => '测试先行：实现前先写一个会失败的测试，再用最小 diff 让它通过。每次改动后跑相关测试，并说明改了哪些文件及原因。不要把无关改动混在一起；到约定检查点要停下。若团队装有 test-driven-development skill，就遵循它。',
			'member.playbookPresetResearcherText' => '动手前先厘清意图：复述问题与你的假设，然后在代码库里先广度排查再深入。汇报时给出文件路径、相关符号与建议的下一步——只提建议，不改生产代码。若团队装有 brainstorming skill，先用它框定问题。',
			'member.playbookPresetReviewerText' => '按序审查：①确认测试覆盖了改动；②正确性与边界情况；③可维护性及与周边代码的一致性。每条意见都要写明文件路径、行号、问题与具体改法——不要空泛夸奖，也不要只挑刺却不给改法。缺测试要显式指出。',
			'member.playbookSubtitle' => '接到任务后怎么执行：步骤、检查点、汇报格式。会作为 Agent 的操作指令。',
			'member.presenceBooting' => '启动中…',
			'member.presenceConnecting' => '连接中…',
			'member.presenceIdle' => '空闲',
			'member.presenceOffline' => '未连接',
			'member.presenceWorking' => '工作中',
			'member.presetCustom' => '自定义配置',
			'member.presetInheritTeam' => '继承团队默认',
			'member.presetInheritTeamNone' => '团队未设置默认',
			'member.presetLabel' => '预设',
			'member.presetSelectPreset' => '选择预设',
			'member.presetViaPreset' => ({required String presetName}) => '${presetName}（通过预设）',
			'member.presetViaTeamDefault' => ({required String presetName}) => '${presetName}（通过团队默认）',
			'member.promptPresetDeveloper' => '开发',
			'member.promptPresetDeveloperText' => '在约定范围内实现分配的任务。未经要求，不要扩大范围或顺手重构无关代码。',
			'member.promptPresetResearcher' => '调研',
			'member.promptPresetResearcherText' => '只调研并汇报。除非被要求，否则不要改动生产代码。',
			'member.promptPresetReviewer' => '审查',
			'member.promptPresetReviewerText' => '只做代码审查。除非被明确要求，否则不要改动文件。',
			'member.promptPresetTeamLead' => '队长',
			'member.promptPresetTeamLeadText' => '协调全队：将用户需求拆成任务清单（每条写明范围与验收标准），再分配给各队友实现；除阻塞性问题外，不要亲自做大块开发，可先阅读代码与文档了解现状。\n在本会话窗口与用户直接沟通。指派与跟进时只联系其他队友（按成员名称），不要把任务派给自己。汇总队友结果后回复用户，写清结论、涉及文件与后续步骤。',
			'member.promptPresetsLabel' => '预设',
			'member.promptSubtitle' => '该成员负责什么、不应做什么。会写入 Agent 的角色说明。',
			'member.quickList' => '成员快速列表',
			'member.responsibilities' => '职责',
			'member.responsibilitiesEmpty' => '该专家未填写职责',
			'member.targetAssignmentInherit' => '继承工作区目录',
			'member.targetAssignmentSubtitle' => ({required Object member}) => '${member} 运行所在的机器（其分配的工作区目录）。',
			'member.targetAssignmentTitle' => '成员所在机器',
			'member.terminalNotStartedTitle' => '终端未启动 — 点击启动',
			'member.terminalReclaimedBody' => '点击重新连接（会话会恢复）',
			'member.terminalReclaimedTitle' => '终端已回收以释放内存',
			'mixed.workspaceCreateSessionBlocked' => '请先在团队设置中确认机器分配，再在此混合工作区新建对话。',
			'mixed.workspaceLeadPlacementInvalid' => '工作区包含本地文件夹时，团队负责人必须分配到本地主机。',
			'mixed.workspaceMemberAssignmentConfirm' => '启动团队',
			'mixed.workspaceMemberAssignmentIncomplete' => '混合工作区首次启动前，请先确认成员的机器分配。',
			'mixed.workspaceMemberAssignmentSubtitle' => '左侧选择机器，右侧用 + / − 放置各成员的实例。',
			'mixed.workspaceMemberAssignmentTitle' => '分配成员到机器',
			'mixed.workspaceMemberPlacementOnMachine' => ({required int count}) => '本机 ${count} 个',
			'mixed.workspaceMemberPlacementProgress' => ({required int placed, required int total}) => '已分配 ${placed} / ${total}',
			'mixed.workspacePersonalLaunchBlockedHint' => '这是混合工作区。请切换到团队标签页启动对话，并确认机器分配。',
			'mixed.workspaceRequiresTeamLaunch' => '混合工作区只能通过团队身份启动。请切换到团队，并在团队设置中确认机器分配。',
			'mixed.workspaceSessionLaunchBlocked' => '该对话的机器分配已失效。请在团队设置中确认分配后新建对话。',
			'my.expertsCreate' => '新建专家',
			'my.expertsDelete' => '删除',
			'my.expertsDeleteConfirm' => ({required Object name}) => '删除专家「${name}」？此操作无法撤销。',
			'my.expertsDeleteReferenced' => ({required Object name}) => '无法删除「${name}」——仍有团队花名册引用该专家。请先改派相关成员。',
			'my.expertsEdit' => '编辑',
			'my.expertsEmptyHint' => '创建本地专家人设，以便在多个团队中复用。',
			'my.expertsEmptyTitle' => '还没有专家',
			'my.expertsNav' => '我的专家',
			'my.expertsSubtitle' => '管理本地专家人设',
			'my.expertsTitle' => '我的专家',
			'my.expertsUpload' => '上传',
			'my.teamsCreatedAt' => ({required Object date}) => '创建于 ${date}',
			'my.teamsEmptyHint' => '创建团队以管理成员、技能与插件。',
			'my.teamsEmptyTitle' => '还没有团队',
			'my.teamsMemberCount' => ({required int count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(count, other: '${count} 名成员', ), 
			'my.teamsNav' => '我的团队',
			'my.teamsSubtitle' => '管理本地团队配置',
			'my.teamsTitle' => '我的团队',
			'my.teamsUpload' => '上传',
			'notification.centerTitle' => '通知',
			'notification.clearAll' => '清空',
			'notification.delete' => '删除',
			'notification.empty' => '暂无通知',
			'notification.historySection' => '历史',
			'notification.markAllRead' => '全部标为已读',
			'notification.markRead' => '标为已读',
			'notification.ongoingSection' => '进行中',
			'notification.timeDaysAgo' => ({required int days}) => '${days} 天',
			'notification.timeHoursAgo' => ({required int hours}) => '${hours} 小时',
			'notification.timeJustNow' => '刚刚',
			'notification.timeMinutesAgo' => ({required int minutes}) => '${minutes} 分钟',
			'onboarding.appearanceSubtitle' => '可随时在「设置 → 布局」中修改。',
			'onboarding.appearanceTitle' => '选择语言与外观',
			'onboarding.cliFound' => '已找到 CLI',
			'onboarding.cliNotFound' => '未在 PATH 中',
			'onboarding.cliRedetect' => '重新检测',
			'onboarding.cliScanning' => '正在扫描 PATH 中的 CLI…',
			'onboarding.cliSubtitle' => '定位用于启动会话的可执行文件。可安装缺失项，或稍后在设置中指定路径。',
			'onboarding.cliTitle' => '检测 CLI 工具',
			'onboarding.defaultPresetDefaultName' => '默认',
			'onboarding.defaultPresetEmpty' => '暂无可选 Provider，可跳过或在设置中添加。',
			'onboarding.defaultPresetModelHint' => '该预设的主模型',
			'onboarding.defaultPresetSelectExisting' => '使用已有预设',
			'onboarding.defaultPresetSubtitle' => '个人工作区与团队默认启动配置将共用此 CLI 预设。',
			'onboarding.defaultPresetTitle' => '配置默认启动预设',
			'onboarding.getStarted' => '开始使用',
			'onboarding.next' => '下一步',
			'onboarding.previous' => '上一步',
			'onboarding.progress' => ({required int current, required int total}) => '第 ${current} / ${total} 步',
			'onboarding.providerImportEmpty' => '未检测到 Provider，可稍后在设置中配置。',
			'onboarding.providerImportFailed' => '导入失败',
			'onboarding.providerImportRescan' => '重新扫描',
			'onboarding.providerImportResults' => '导入结果',
			'onboarding.providerImportSubtitle' => '扫描本机各 CLI 配置中的现有 Provider。',
			'onboarding.providerImportTitle' => '导入 CLI Provider',
			'onboarding.rerunSetup' => '重新运行设置向导',
			'onboarding.skip' => '跳过',
			'onboarding.sshSubtitle' => 'Android 通过 SSH 在远程主机运行 AI CLI。',
			'onboarding.sshTitle' => '配置 SSH 连接',
			'onboarding.stepAppearance' => '语言 / 主题',
			'onboarding.stepCli' => 'CLI 工具',
			'onboarding.stepDefaultPreset' => '默认预设',
			'onboarding.stepProviderImport' => '导入 Provider',
			'onboarding.stepSsh' => 'SSH',
			'onboarding.title' => '首次设置',
			'onboarding.workHomeSubtitle' => '先连接本机 Termux 或远程 SSH，再检测 AI CLI。',
			'onboarding.workHomeTitle' => '选择工作环境',
			'opencode.credentialsActionFailed' => '凭据更新失败',
			'opencode.credentialsActionSuccess' => '凭据已更新',
			'opencode.credentialsImportFile' => '导入 auth.json…',
			'opencode.credentialsImportGlobal' => '从 opencode 凭据导入',
			'opencode.credentialsLogin' => 'Provider 登录',
			'opencode.credentialsRevoke' => '退出登录',
			'opencode.credentialsRevokeConfirm' => ({required String name}) => '退出登录并删除 ${name} 的已保存凭据？',
			'opencode.permissionAllowAlways' => '总是允许',
			'opencode.permissionAllowOnce' => '允许一次',
			'opencode.permissionAnswerFailed' => '无法提交你的决定。请重试或在终端中处理。',
			'opencode.permissionAnswerInTerminal' => '在终端处理',
			'opencode.permissionReject' => '拒绝',
			'opencode.permissionTitle' => 'OpenCode 需要你的授权',
			'plugin.cliSupportFully' => ({required String cli}) => '${cli}：完全支持',
			'plugin.cliSupportNotApplicable' => ({required String cli}) => '${cli}：不适用',
			'plugin.cliSupportPartial' => ({required String cli, required String dropped}) => '${cli}：部分支持（丢弃 ${dropped}）',
			'plugin.componentAgents' => '代理',
			'plugin.componentApps' => '应用',
			'plugin.componentCommands' => '命令',
			'plugin.componentHooks' => '钩子',
			'plugin.componentMcp' => 'MCP',
			'plugin.componentRules' => '规则',
			'plugin.componentSkills' => '技能',
			'plugins.cardDetails' => '详情',
			'plugins.cardInstall' => '安装',
			'plugins.cardInstalled' => '已安装',
			'plugins.cardUninstall' => '卸载',
			'plugins.cardUpdate' => '更新',
			'plugins.cardViewSource' => '查看来源',
			'plugins.catalogAdoption' => '安装量',
			'plugins.catalogCardNoDescription' => '无',
			'plugins.checkUpdates' => '检查更新',
			'plugins.checkingUpdates' => '检查中…',
			'plugins.discoveryEmpty' => '无匹配的插件',
			'plugins.discoverySyncing' => '正在后台检查 marketplace 更新并同步插件…',
			'plugins.filterAll' => '全部',
			'plugins.filterInstalled' => '已安装',
			'plugins.filterMarketplaceAll' => '全部 marketplace',
			'plugins.filterUninstalled' => '未安装',
			'plugins.goDiscovery' => '浏览 marketplace',
			'plugins.importFromDisk' => '从目录导入',
			'plugins.importNothing' => '未发现未管理的插件。',
			'plugins.importTitle' => '导入未管理的插件',
			'plugins.installFromZip' => '从 ZIP 安装',
			'plugins.installedCount' => ({required int count}) => '已安装 ${count} 个',
			'plugins.local' => '本地',
			'plugins.marketplaceAdd' => '添加 marketplace',
			'plugins.marketplaceBranch' => '分支',
			'plugins.marketplaceDisplayName' => '显示名称',
			'plugins.marketplaceInvalidUrl' => '请输入合法的 GitHub 仓库地址。',
			'plugins.marketplaceRemove' => '移除 marketplace',
			'plugins.marketplaceRemoveConfirm' => ({required String url}) => '确认移除 marketplace ${url}？已安装的插件会保留。',
			'plugins.marketplaceUrl' => 'GitHub 仓库地址',
			'plugins.marketplaceUrlHint' => 'https://github.com/owner/marketplace',
			'plugins.marketplacesEmpty' => '尚未配置 marketplace',
			'plugins.navDiscovery' => '发现',
			'plugins.navInstalled' => '已安装',
			'plugins.navMarketplaces' => 'Marketplaces',
			'plugins.noInstalled' => '尚未安装插件',
			'plugins.noInstalledHint' => '在 Marketplaces 选项卡添加 marketplace，然后在 Discovery 中安装。',
			'plugins.searchPlaceholder' => '搜索插件',
			'plugins.sidebarLabel' => '插件',
			'plugins.subtitle' => '管理 Claude Code 风格插件包',
			'plugins.title' => '插件',
			'plugins.uninstallConfirm' => ({required String name, required int n}) => '确认卸载 ${name}？将影响 ${n} 个团队。',
			'plugins.uninstallImpactList' => '受影响的团队：',
			'plugins.uninstallSuccess' => ({required String name}) => '已卸载 ${name}',
			'plugins.updateAll' => ({required int count}) => '全部更新 (${count})',
			'plugins.updateAvailable' => '有新版本',
			'provider.provider' => '提供商',
			'provider.credentialsAuthenticated' => '已认证',
			'provider.credentialsBrowserOpened' => '已打开浏览器进行授权',
			'provider.credentialsDeviceCodeHint' => '请在浏览器中输入此一次性验证码（15 分钟内有效）',
			'provider.credentialsDeviceCodeTitle' => '设备验证码',
			'provider.credentialsFailureDestinationExists' => '凭据已存在。请先退出登录，或再次导入以覆盖。',
			'provider.credentialsFailureInvalidCredential' => '凭据格式无效或不完整',
			'provider.credentialsFailureLoginFailed' => ({required int exitCode}) => '登录失败（退出码 ${exitCode}）',
			'provider.credentialsFailureLoginProcessError' => ({required String detail}) => '无法运行登录命令：${detail}',
			'provider.credentialsFailurePathRequired' => '请先选择文件或目录',
			'provider.credentialsFailureProviderEntryMissing' => ({required String path, required String providerId}) => '在 ${path} 中未找到 "${providerId}" 的凭据',
			'provider.credentialsFailureProviderEntryMissingWithKeys' => ({required String path, required String providerId, required String keys}) => '在 ${path} 中未找到 "${providerId}" 的凭据。已有：${keys}',
			'provider.credentialsFailureProviderNotFound' => '未找到 Provider',
			'provider.credentialsFailureRequiredFileMissing' => ({required String path}) => '缺少必需文件：${path}',
			'provider.credentialsFailureRevokeFailed' => '无法退出登录或删除凭据',
			'provider.credentialsFailureServiceUnavailable' => '凭据服务不可用',
			'provider.credentialsFailureSourceMissing' => ({required String path}) => '未找到凭据文件：${path}',
			'provider.credentialsFailureSourceUnreadable' => ({required String path}) => '无法读取凭据文件：${path}',
			'provider.credentialsFailureStatusRefreshFailed' => '凭据已更新但状态刷新失败',
			'provider.credentialsFailureUnsupported' => '不支持此凭据操作',
			'provider.credentialsFailureVerifyFailed' => '凭据已写入但校验失败',
			'provider.credentialsReopenBrowser' => '重新打开浏览器',
			'provider.credentialsUnauthenticated' => '未认证',
			'provider.detailSubtitle' => ({required String type, required int count}) => '${type} 提供商 · ${count} 个模型',
			'provider.effortLevel' => '推理力度',
			'provider.list' => '提供商列表',
			'provider.listModelCount' => ({required int count}) => '${count} 个模型',
			'provider.modelBackgroundTier' => '用于后台/快速任务（Claude haiku 档）',
			'provider.name' => '提供商名称',
			'provider.type' => '提供商类型',
			'provider.typeHint' => 'openai, claude 或自定义',
			'qoder.contextWindow' => '上下文窗口（tokens）',
			'qoder.contextWindowHint' => '留空则使用模型默认值。',
			'qoder.credentialsActionFailed' => 'Qoder 操作失败',
			'qoder.credentialsCancel' => '取消',
			'qoder.credentialsDone' => '完成',
			'qoder.credentialsLogin' => '登录',
			'qoder.credentialsLoginExited' => 'Qoder CLI 已退出。请关闭此对话框后重新登录。',
			'qoder.credentialsLoginFailed' => ({required String error}) => '无法启动登录终端：${error}',
			'qoder.credentialsLoginIntro' => '在下方终端完成登录。CLI 会打开浏览器；如果没有打开，请手动访问它输出的链接。也可以在这里切换账号。',
			'qoder.credentialsLoginStarting' => '正在启动 Qoder CLI…',
			'qoder.credentialsLoginTitle' => '登录 Qoder',
			'qoder.credentialsRelaunch' => '重新启动',
			'qoder.credentialsSignedIn' => '已登录',
			'remote.cliMachineReadinessAdapterLabel' => ({required String cli}) => '${cli} ACP 适配器',
			'remote.cliMachineReadinessFailed' => ({required String cli, required String message}) => '${cli}：${message}',
			'remote.cliMachineReadinessInstallHint' => '对每个缺失的 CLI 点击安装，或在目标设置中指定手动路径。',
			'remote.cliMachineReadinessMissing' => ({required String cli}) => '未找到 ${cli} — 请安装或设置手动路径',
			'remote.cliMachineReadinessProbing' => '正在检测…',
			'remote.cliMachineReadinessReady' => ({required String cli, required String path}) => '${cli} 已就绪：${path}',
			'remote.cliMachineReadinessTitle' => '此机器上需要的 CLI',
			'remote.connectionsSubtitle' => '管理本机保存的远程主机、连接与切换工作主目录；断线时同样可用。',
			'remote.connectionsTitle' => '远程连接',
			'remote.directoryBrowserEmpty' => '此处没有子目录',
			'remote.directoryBrowserError' => '无法打开远程目录。你仍可在下方手动输入路径。',
			'remote.directoryBrowserTitle' => '浏览远程目录',
			'remote.directoryBrowserTypePathHint' => '~/work/workspace',
			'remote.directoryBrowserTypePathLabel' => '或手动输入路径',
			'remote.directoryBrowserUpOneLevel' => '上一级',
			'remote.directoryBrowserUseThisDirectory' => '使用此目录',
			'remote.directoryBrowserUseTypedPath' => '使用路径',
			'resource.managerAppProcess' => '应用',
			'resource.managerColumnCpu' => 'CPU',
			'resource.managerColumnMemory' => '内存',
			'resource.managerColumnName' => '名称',
			'resource.managerEmptyTree' => '当前没有运行中的会话。',
			'resource.managerKill' => '结束',
			'resource.managerKillAll' => '全部结束',
			'resource.managerKillAllConfirmBody' => '将断开列表中的全部运行中会话与终端。',
			'resource.managerKillAllConfirmTitle' => '结束全部运行中会话？',
			'resource.managerKillFailed' => '无法结束会话。',
			'resource.managerMetricsError' => '无法刷新进程指标。',
			'resource.managerPanelTitle' => '资源管理器 - 会话',
			'resource.managerRefresh' => '刷新',
			_ => null,
		} ?? switch (path) {
			'resource.managerSpace' => '空间',
			'resource.managerSpaceBeta' => 'Beta',
			'resource.managerSpaceNotScanned' => '不会扫描工作区磁盘占用。',
			'resource.managerSystemMemoryPercent' => ({required String percent}) => '系统内存 ${percent}%',
			'resource.managerTerminalsCount' => ({required int count}) => '${count} 个运行中会话',
			'resource.managerTitle' => '资源管理器',
			'resource.managerTooltip' => ({required int count}) => '资源管理器 - ${count} 个运行中会话',
			'resource.managerTooltipHint' => '跨所有工作区的运行中会话。',
			'rtk.bashOnlyHint' => '仅作用于 Agent 的 Bash 工具调用；内置 Read、Grep、Glob 不会自动改写。',
			'rtk.settingsDescription' => '在命令输出进入模型前压缩 Agent Bash 结果（需本机 PATH 中有 rtk 与 jq）。',
			'rtk.settingsEnableTitle' => '启用 RTK',
			'rtk.settingsInstallLink' => '安装说明',
			'rtk.settingsStatusTitle' => '本机状态',
			'rtk.settingsTitle' => 'RTK 省 token',
			'rtk.statusInstalled' => ({required String version}) => 'rtk ${version} 已就绪',
			'rtk.statusInstalledGeneric' => 'rtk 已就绪',
			'rtk.statusJqMissing' => 'PATH 中未找到 jq',
			'rtk.statusNotFound' => 'PATH 中未找到 rtk',
			'rtk.statusVersionTooOld' => ({required String version}) => 'rtk ${version} 版本过低（需要 >= 0.23.0）',
			'run.acceptRecommendation' => '将建议配置添加到 launch.json',
			'run.action' => '运行',
			'run.addConfiguration' => '添加配置',
			'run.alreadyRunningMessage' => '重新运行当前会话，还是再启动一个新实例？',
			'run.alreadyRunningTitle' => '配置已在运行',
			'run.apply' => '应用',
			'run.build' => '构建',
			'run.buildUnavailable' => '构建功能尚未提供',
			'run.clearExited' => '清除已退出的会话',
			'run.compoundConfiguration' => ({required String name}) => '${name}（组合）',
			'run.configurationName' => '名称',
			'run.configurationTooltip' => '运行配置',
			'run.configurationType' => '类型',
			'run.configurationsEmpty' => '暂无启动配置',
			'run.configureLaunchItems' => '配置启动项',
			'run.debug' => '调试',
			'run.debugUnavailable' => '调试功能尚未提供',
			'run.deleteConfiguration' => '删除',
			'run.deleteConfigurationConfirm' => ({required String name}) => '删除配置“${name}”？',
			'run.discard' => '放弃',
			'run.discardChangesMessage' => '此配置有未保存的更改。应用、放弃，还是取消？',
			'run.discardChangesTitle' => '放弃更改？',
			'run.editConfigurations' => '编辑配置',
			'run.editorSelectConfiguration' => '选择配置',
			'run.emptyOutputHint' => '运行配置后，输出将显示在这里',
			'run.errorNoConfiguration' => '未选择配置',
			'run.errorNoFolder' => '没有工作区文件夹',
			'run.errorSshProfileMissing' => '找不到此运行目标的 SSH 配置',
			'run.errorSshSpawnerMissing' => '未配置 SSH 进程执行',
			'run.executeScriptFile' => '脚本文件',
			'run.executeScriptText' => '脚本内容',
			'run.fieldActivateToolWindow' => '激活工具窗口',
			'run.fieldAllowMultipleInstances' => '允许运行多个实例',
			'run.fieldArgs' => '参数',
			'run.fieldCommand' => '命令',
			'run.fieldCwd' => '工作目录',
			'run.fieldEnv' => '环境变量',
			'run.fieldExecute' => '执行方式',
			'run.fieldExecuteInTerminal' => '在终端中执行',
			'run.fieldFocusToolWindow' => '聚焦工具窗口',
			'run.fieldInterpreterOptions' => '解释器选项',
			'run.fieldInterpreterPath' => '解释器路径',
			'run.fieldInterpreterPathEditTooltip' => '编辑解释器路径',
			'run.fieldScriptOptions' => '脚本选项',
			'run.fieldScriptPath' => '脚本路径',
			'run.fieldScriptText' => '脚本内容',
			'run.fieldShell' => '在 Shell 中运行',
			'run.loadingOutput' => '正在加载运行输出…',
			'run.moreActions' => '更多运行操作',
			'run.newInstance' => '新实例',
			'run.noSessions' => '暂无运行会话',
			'run.openLaunchJson' => '打开 launch.json',
			'run.pickLaunchType' => '选择启动类型',
			'run.refreshDiscover' => '刷新发现建议',
			'run.restart' => '重新运行',
			'run.selectConfiguration' => '启动',
			'run.selectFolder' => '选择文件夹',
			'run.stop' => '停止',
			'run.stopAndClose' => '停止并关闭',
			'run.stopAndDelete' => '停止并删除',
			'run.stopSessionMessage' => ({required String name}) => '“${name}”仍在运行。停止并关闭此标签页？',
			'run.stopSessionTitle' => '停止正在运行的会话？',
			'run.suggestedConfiguration' => ({required String name}) => '${name}（建议）',
			'run.typeShellScript' => 'Shell 脚本',
			'run.typeUnavailable' => ({required String type}) => '启动类型“${type}”在此目标上不可用',
			'run.typeUnavailableRemote' => ({required String type}) => '启动类型“${type}”在远程目标上不可用',
			'run.typeUnknown' => ({required String type}) => '未知启动类型：${type}',
			'run.validationActivateToolWindowMustBeBoolean' => '激活工具窗口必须是布尔值',
			'run.validationAllowMultipleInstancesMustBeBoolean' => '允许运行多个实例必须是布尔值',
			'run.validationArgsMustBeStringList' => '参数必须是字符串列表',
			'run.validationCommandRequired' => '命令不能为空',
			'run.validationConfigurationMustBeMap' => '配置必须是对象',
			'run.validationCwdMustBeString' => '工作目录必须是字符串',
			'run.validationEnvMustBeStringMap' => '环境变量必须是字符串映射',
			'run.validationExecuteInTerminalMustBeBoolean' => '在终端中执行必须是布尔值',
			'run.validationExecuteInvalid' => '执行方式必须是脚本文件或脚本内容',
			'run.validationExecuteRequired' => '必须选择执行方式',
			'run.validationFocusToolWindowMustBeBoolean' => '聚焦工具窗口必须是布尔值',
			'run.validationInterpreterPathMustBeString' => '解释器路径必须是字符串',
			'run.validationScriptPathRequired' => '脚本路径不能为空',
			'run.validationScriptTextRequired' => '脚本内容不能为空',
			'run.validationShellMustBeBoolean' => 'Shell 必须是布尔值',
			'session.session' => '会话',
			'session.archiveEmpty' => '暂无归档会话',
			'session.archiveEntryTooltip' => '归档会话',
			'session.archiveTitle' => '归档',
			'session.duplicateFailed' => '复制对话失败',
			'session.duplicated' => '对话已复制',
			'session.failedTitle' => '未能启动会话',
			'session.followUpAddPlaceholder' => '添加跟进消息',
			'session.followUpDelete' => '删除',
			'session.followUpEdit' => '编辑',
			'session.followUpMoveUp' => '上移',
			'session.followUpQueued' => ({required int count}) => '${count} 排队中',
			'session.followUpResume' => '继续队列',
			'session.forkFailed' => 'Fork 对话失败',
			'session.groupAddSessionsTitle' => '添加会话',
			'session.groupAddSessionsTooltip' => '添加会话',
			'session.groupCreateTitle' => '新建分组',
			'session.groupCreateTooltip' => '新建分组',
			'session.groupEmpty' => '暂无会话',
			'session.groupMenuRemove' => '删除分组',
			'session.groupNameLabel' => '分组名称',
			'session.groupRenameTitle' => '重命名分组',
			'session.historyBackgroundRunning' => '后台任务运行中…',
			'session.historyComposeHint' => '继续对话… @ 引用文件，/ 调用技能与指令',
			'session.historyComposeStop' => '停止生成',
			'session.historyContinueSaveFailed' => '无法保存继续会话设置。',
			'session.historyEmpty' => '该成员暂无历史消息。',
			'session.historyError' => '无法加载对话历史。',
			'session.historyLoadOlderHint' => '上滑查看更早消息',
			'session.historyLoading' => '正在加载对话历史…',
			'session.historyMailboxQueued' => ({required int count}) => '${count} 已排队',
			'session.historyMailboxQueuedDismiss' => '关闭',
			'session.historyRefreshing' => '正在刷新对话…',
			'session.historyRetry' => '重试',
			'session.historyRoleAssistant' => '助手',
			'session.historyRoleSystem' => '系统',
			'session.historyRoleUser' => '你',
			'session.historyRunning' => '运行中…',
			'session.historySoftReloadError' => '无法刷新对话历史。',
			'session.historyStarting' => '启动中…',
			'session.historyToolTurn' => '工具',
			'session.idleNotificationSubtitle' => '可以继续对话了',
			'session.idleNotificationTitle' => 'Agent 已就绪',
			'session.launchErrorHideDetails' => '收起详情',
			'session.launchErrorReviewDetails' => '查看详情',
			'session.launchMissingTeamMember' => '团队成员不可用，请选择团队后重试。',
			'session.launchMissingWorkspace' => '找不到该对话所属的工作区。',
			'session.openToSide' => '在右侧分栏打开',
			'session.pageSubtitle' => '配置 Shell 会话启动方式、终端行为与存储后端。',
			'session.readyHint' => '用日常语言描述你想做的事即可，无需输入命令。',
			'session.readySubtitle' => ({required String memberName}) => '与 ${memberName} 在此工作区中开始对话',
			'session.readySubtitleGeneric' => '在此工作区中开始新对话',
			'session.readyTitle' => '准备开始对话',
			'session.remoteProvisionFailed' => '远程准备失败',
			'session.remoteProvisionPreparing' => '正在准备远程环境…',
			'session.remoteProvisionPreparingOnHost' => ({required String host}) => '正在准备远程环境（${host}）',
			'session.remoteProvisionTitle' => ({required String member, required String host}) => '正在准备 ${member}（${host}）',
			'session.retryButton' => '重试',
			'session.sortCreatedDesc' => '创建时间',
			'session.sortManual' => '手动排序',
			'session.sortRecentlyUpdated' => '最近更新',
			'session.sortTooltip' => '排序对话',
			'session.startButton' => '开始对话',
			'session.starting' => '正在启动会话…',
			'session.tabBarTitle' => '会话标签栏',
			'session.tabBarVisibilityHint' => '在工作台中心列上方显示标签栏。',
			'session.titleCopySuffix' => '（副本）',
			'session.workbenchViewChat' => '聊天',
			'session.workbenchViewTerminal' => '终端',
			'sessionUsage.accountAll' => '全部账号',
			'sessionUsage.autoScan' => '自动扫描会话日志',
			'sessionUsage.autoScanHint' => ({required int minutes}) => '打开本页时立即扫描，之后每 ${minutes} 分钟在后台扫描。',
			'sessionUsage.cacheHit' => ({required String percent}) => '命中率 ${percent}',
			'sessionUsage.cacheRead' => '缓存读取',
			'sessionUsage.cacheReadShare' => ({required String percent}) => '缓存读占比 ${percent}',
			'sessionUsage.cacheShort' => '缓存',
			'sessionUsage.cacheWrite' => ({required String tokens}) => '写入 ${tokens}',
			'sessionUsage.cancelSync' => '取消',
			'sessionUsage.cancelSyncTooltip' => '取消用量同步',
			'sessionUsage.cancelling' => '正在取消…',
			'sessionUsage.chartAverage' => ({required String tokens}) => '日均 ${tokens}',
			'sessionUsage.chartSubtitle' => '按 CLI 堆叠',
			'sessionUsage.chartTitle' => '近 7 天消耗',
			'sessionUsage.chartTotal' => ({required String tokens}) => '合计 ${tokens}',
			'sessionUsage.cliAll' => '全部',
			'sessionUsage.cliBreakdown' => 'CLI 分布',
			'sessionUsage.columnReset' => '恢复默认',
			'sessionUsage.columnSettings' => '显示的列',
			'sessionUsage.cost' => '成本',
			'sessionUsage.costPartial' => ({required int count}) => '部分成本：${count} 条未定价',
			'sessionUsage.costPricedUnpriced' => ({required int priced, required int unpriced}) => '已定价 ${priced} 条 · 未定价 ${unpriced} 条',
			'sessionUsage.costShort' => '成本',
			'sessionUsage.costUnpriced' => '未定价',
			'sessionUsage.dataSource' => '数据来源',
			'sessionUsage.dismiss' => '关闭',
			'sessionUsage.emptyBody' => '运行一次 Claude、Codex 或 OpenCode 会话后点击同步。也可以先清除筛选条件。',
			'sessionUsage.emptyTitle' => '还没有 Token 用量',
			'sessionUsage.endTime' => '结束时间',
			'sessionUsage.groupBy' => '分组',
			'sessionUsage.groupCli' => 'CLI',
			'sessionUsage.groupCount' => ({required int count}) => '${count} 组',
			'sessionUsage.groupMember' => '成员',
			'sessionUsage.groupModel' => '模型',
			'sessionUsage.groupName' => '名称',
			'sessionUsage.groupSession' => '会话',
			'sessionUsage.heatmapLess' => '少',
			'sessionUsage.heatmapMetricHitRate' => '命中率',
			'sessionUsage.heatmapMetricTokens' => 'Token',
			'sessionUsage.heatmapMore' => '多',
			'sessionUsage.heatmapShowEarlier' => '显示更早',
			'sessionUsage.heatmapShowLess' => '收起更早',
			'sessionUsage.heatmapSpanSummary' => ({required String tokens, required String requests, required String cost}) => '${tokens} Token · ${requests} 请求 · ${cost}',
			'sessionUsage.heatmapSubtitle' => '近 53 周 · 悬停或长按查看当天明细',
			'sessionUsage.heatmapTitle' => '用量热力图',
			'sessionUsage.inputShort' => '输入',
			'sessionUsage.inputTokens' => '输入',
			'sessionUsage.intervalMinutes' => ({required int minutes}) => '每 ${minutes} 分钟',
			'sessionUsage.lastSync' => ({required String time}) => '上次同步 ${time}',
			'sessionUsage.liveEnd' => '结束时间跟随当前时刻',
			'sessionUsage.loadFailed' => '无法加载用量数据。',
			'sessionUsage.loading' => '正在加载用量…',
			'sessionUsage.maintenanceCompact' => '压缩事件',
			'sessionUsage.maintenanceCompactHint' => '合并被覆盖的历史修订，保留当前事件。',
			'sessionUsage.maintenanceCompacted' => '用量存储已压缩。',
			'sessionUsage.maintenanceEntry' => '存储与 Cursor 维护',
			'sessionUsage.maintenanceFailed' => '用量存储压缩失败。',
			'sessionUsage.maintenanceFull' => '全量重扫',
			'sessionUsage.maintenanceFullDone' => '全量用量重扫完成。',
			'sessionUsage.maintenanceFullHint' => '重建全部数据源并扫描所有会话；历史缺失时使用。',
			'sessionUsage.maintenanceLines' => ({required int lines, required int events}) => '${lines} 行 · ${events} 条事件',
			'sessionUsage.maintenanceSize' => ({required String size}) => '${size} KB',
			'sessionUsage.maintenanceTitle' => '用量存储',
			'sessionUsage.managePricing' => '管理定价',
			'sessionUsage.mixedCli' => '混合',
			'sessionUsage.nav' => 'Token 用量',
			'sessionUsage.neverSynced' => '尚未同步',
			'sessionUsage.nextPage' => '下一页',
			'sessionUsage.noData' => '暂无数据',
			'sessionUsage.outputShort' => '输出',
			'sessionUsage.outputTokens' => '输出',
			'sessionUsage.pageOf' => ({required int page, required int pages}) => '第 ${page} / ${pages} 页',
			'sessionUsage.pageRange' => ({required int start, required int end, required int total}) => '第 ${start}–${end} 条 · 共 ${total} 组',
			'sessionUsage.prevPage' => '上一页',
			'sessionUsage.pricingAdd' => '新增规则',
			'sessionUsage.pricingCacheRead' => '缓存读',
			'sessionUsage.pricingCacheWrite' => '缓存写',
			'sessionUsage.pricingCacheWrite1h' => '1 小时缓存写',
			'sessionUsage.pricingCorrupt' => '定价文件无法读取，已使用内置价格。',
			'sessionUsage.pricingDelete' => '删除',
			'sessionUsage.pricingEffectiveDate' => '生效日期',
			'sessionUsage.pricingEffectiveHint' => 'YYYY-MM-DD',
			'sessionUsage.pricingEmpty' => '没有自定义规则，当前使用内置价格。',
			'sessionUsage.pricingFailed' => '定价保存失败。',
			'sessionUsage.pricingHint' => '每百万 token 的美元价格；自定义规则优先于内置参考价。',
			'sessionUsage.pricingInput' => '输入',
			'sessionUsage.pricingInvalid' => '请检查模型和价格输入。',
			'sessionUsage.pricingModel' => '模型',
			'sessionUsage.pricingOutput' => '输出',
			'sessionUsage.pricingReset' => '恢复默认',
			'sessionUsage.pricingResetConfirm' => '移除所有自定义定价规则？',
			'sessionUsage.pricingSave' => '保存',
			'sessionUsage.pricingSaved' => '定价已保存',
			'sessionUsage.pricingTitle' => '模型定价',
			'sessionUsage.progressTitle' => '用量同步',
			'sessionUsage.rangeAll' => '全部',
			'sessionUsage.rangeFourteenDays' => '近 14 天',
			'sessionUsage.rangeHint' => '支持日期与时间，最长 30 天',
			'sessionUsage.rangeInvalidOrder' => '开始时间不能晚于结束时间',
			'sessionUsage.rangeLast24Hours' => '近 24 小时',
			'sessionUsage.rangeSevenDays' => '近 7 天',
			'sessionUsage.rangeThirtyDays' => '近 30 天',
			'sessionUsage.rangeToday' => '今天',
			'sessionUsage.rangeTooLong' => '时间范围不能超过 30 天',
			'sessionUsage.requests' => '请求',
			'sessionUsage.requestsSessions' => ({required int requests, required int sessions}) => '${requests} 请求 · ${sessions} 会话',
			'sessionUsage.requestsShort' => '请求',
			'sessionUsage.resetFilters' => '清除筛选',
			'sessionUsage.retry' => '重试',
			'sessionUsage.rowsPerPage' => '每页条数',
			'sessionUsage.scanInterval' => '扫描间隔',
			'sessionUsage.scopeHint' => '本地 + SSH · 按 TeamPilot 会话归属',
			'sessionUsage.searchHint' => '搜索会话、成员或模型',
			'sessionUsage.sessions' => '会话',
			'sessionUsage.sessionsShort' => '会话',
			'sessionUsage.settings' => '用量设置',
			'sessionUsage.share' => ({required String percent}) => '占总用量 ${percent}',
			'sessionUsage.shareShort' => '占比',
			'sessionUsage.showing' => ({required int shown, required int total}) => '显示 ${shown} / ${total} 条记录',
			'sessionUsage.simpleSeat' => '简单会话',
			'sessionUsage.sortAscending' => '升序',
			'sessionUsage.sortDescending' => '降序',
			'sessionUsage.startTime' => '开始时间',
			'sessionUsage.storage' => '存储',
			'sessionUsage.sync' => '同步',
			'sessionUsage.syncCancelled' => '已取消用量同步。',
			'sessionUsage.syncFatal' => '同步失败，当前显示缓存数据。',
			'sessionUsage.syncFull' => '全量同步',
			'sessionUsage.syncFullHint' => '从头重新扫描全部记录',
			'sessionUsage.syncIncremental' => '增量同步',
			'sessionUsage.syncIncrementalHint' => '只扫描上次同步后变化的文件',
			'sessionUsage.syncNow' => '立即同步',
			'sessionUsage.syncPartial' => ({required int count}) => '${count} 个来源同步失败，当前显示缓存数据。',
			'sessionUsage.syncPreparing' => '正在准备扫描…',
			'sessionUsage.syncProgress' => ({required int done, required int total, required int inserted}) => '正在扫描 ${done}/${total} 个会话 · 新增 ${inserted} 条',
			'sessionUsage.syncTooltip' => '扫描 CLI 记录以获取新用量',
			'sessionUsage.syncedJustNow' => '刚刚同步',
			'sessionUsage.syncedToast' => '用量同步完成',
			'sessionUsage.syncing' => '同步中',
			'sessionUsage.tableEmpty' => '没有匹配的记录',
			'sessionUsage.tableEmptyHint' => '换个搜索词，或清除筛选条件。',
			'sessionUsage.title' => 'Token 用量',
			'sessionUsage.today' => '今天',
			'sessionUsage.totalShort' => '总计',
			'sessionUsage.totalTokens' => '总 Token',
			'sessionUsage.unknownModel' => '未知模型',
			'sessionUsage.unknownSession' => '未知会话',
			'sessionUsage.unknownTeam' => '未归属团队',
			'shortcuts.categoryCompose' => '输入框',
			'shortcuts.categoryMeta' => '通用',
			'shortcuts.categoryNavigation' => '导航',
			'shortcuts.categoryRun' => '运行',
			'shortcuts.categoryTabs' => '标签',
			'shortcuts.categoryView' => '视图',
			'shortcuts.categoryZoom' => '缩放',
			'shortcuts.changeAction' => '更改…',
			'shortcuts.cheatsheetButton' => '查看速查表',
			'shortcuts.cheatsheetEmpty' => '没有匹配的快捷键。',
			'shortcuts.cheatsheetTitle' => '键盘快捷键',
			'shortcuts.composeNewline' => '插入换行',
			'shortcuts.composeSubmit' => '发送消息',
			'shortcuts.conflictBadgeTooltip' => '与另一个快捷键冲突',
			'shortcuts.conflictMessage' => ({required String title}) => '已被“${title}”使用。',
			'shortcuts.export' => '导出…',
			'shortcuts.exportFailed' => '无法导出快捷键。',
			'shortcuts.exportSuccess' => '快捷键已导出。',
			'shortcuts.floatingMaximize' => '最大化浮动工作区',
			'shortcuts.floatingMinimize' => '最小化浮动工作区',
			'shortcuts.floatingNewTerminal' => '新建浮动终端',
			'shortcuts.floatingOpenFile' => '在浮动工作区打开文件',
			'shortcuts.floatingToggle' => '切换浮动工作区',
			'shortcuts.import' => '导入…',
			'shortcuts.importConflictMessage' => ({required int count}) => '导入的快捷键与 ${count} 个现有绑定冲突。是否替换？',
			'shortcuts.importConflictTitle' => '替换冲突的快捷键？',
			'shortcuts.importInvalidFile' => '该文件不是有效的快捷键导出文件。',
			'shortcuts.importSuccess' => '快捷键已导入。',
			'shortcuts.notSet' => '未设置',
			'shortcuts.pageSubtitle' => '查看并自定义导航、标签、缩放和输入框的键盘快捷键。',
			'shortcuts.pressShortcutHint' => '按下组合键进行绑定。按 Escape 取消，按 Backspace 取消绑定。',
			'shortcuts.pressShortcutTitle' => '按下快捷键',
			'shortcuts.pressShortcutUnsupportedKey' => '该键无法绑定。',
			'shortcuts.replaceAction' => '替换',
			'shortcuts.resetAction' => '恢复默认',
			'shortcuts.resetAll' => '全部重置',
			'shortcuts.resetAllConfirmMessage' => '这会将所有键盘快捷键恢复为默认绑定。',
			'shortcuts.resetAllConfirmTitle' => '重置所有快捷键？',
			'shortcuts.runRestart' => '重新运行',
			'shortcuts.runSelected' => '运行所选配置',
			'shortcuts.runStop' => '停止运行',
			'shortcuts.searchHint' => '搜索快捷键',
			'shortcuts.sessionCloseTab' => '关闭会话标签',
			'shortcuts.sessionNewChat' => '新建对话',
			'shortcuts.sessionNewTab' => '新建会话标签',
			'shortcuts.settingsTitle' => '键盘快捷键',
			'shortcuts.showCheatsheet' => '显示键盘快捷键',
			'shortcuts.stripFocusTab' => ({required int n}) => '切换到第 ${n} 个标签',
			'shortcuts.stripNextTab' => '下一个标签',
			'shortcuts.stripPrevTab' => '上一个标签',
			'shortcuts.togglePanel' => '切换终端面板',
			'shortcuts.toggleSecondarySidebar' => '切换次侧边栏',
			'shortcuts.toggleSidebar' => '切换侧边栏',
			'shortcuts.unbindAction' => '取消绑定',
			'shortcuts.workbenchFocusNextGroup' => '聚焦下一个编辑组',
			'shortcuts.workbenchMoveTabToNextGroup' => '将标签页移到下一个编辑组',
			'shortcuts.workbenchSplitDown' => '向下拆分编辑组',
			'shortcuts.workbenchSplitReset' => '重置编辑组布局',
			'shortcuts.workbenchSplitRight' => '向右拆分编辑组',
			'shortcuts.workspaceCloseTab' => '关闭工作区标签',
			'shortcuts.workspaceContentSearch' => '在文件中查找',
			'shortcuts.workspaceFocusTab' => ({required int n}) => '切换到第 ${n} 个工作区',
			'shortcuts.workspaceNextTab' => '下一个工作区标签',
			'shortcuts.workspacePrevTab' => '上一个工作区标签',
			'shortcuts.workspaceReopenClosed' => '重新打开已关闭的工作区标签',
			'shortcuts.workspaceSearch' => '搜索工作区（双击 Shift）',
			'shortcuts.zoomIn' => '放大',
			'shortcuts.zoomOut' => '缩小',
			'shortcuts.zoomReset' => '重置缩放',
			'skills.add' => '添加',
			'skills.cardDetails' => '详情',
			'skills.cardInstall' => '安装',
			'skills.cardInstalled' => '已安装',
			'skills.cardStars' => ({required int count}) => '${count} 星',
			'skills.cardUninstall' => '卸载',
			'skills.cardUpdate' => '更新',
			'skills.cardUpdatedAt' => ({required String date}) => '更新于 ${date}',
			'skills.cardView' => '查看',
			'skills.catalogAdoption' => '安装量',
			'skills.catalogCardNoDescription' => '无',
			'skills.checkUpdates' => '检查更新',
			'skills.checkingUpdates' => '检查中…',
			'skills.detailMissing' => '未找到该 skill 的 SKILL.md。',
			'skills.detailReadError' => '无法读取 SKILL.md。',
			'skills.discoveryEmpty' => '未发现可用 Skill',
			'skills.discoveryEmptyHint' => '添加仓库或试用 skills.sh 来发现 Skill。',
			'skills.discoveryErrorTitle' => '发现失败',
			'skills.discoverySyncing' => '正在后台检查仓库更新并同步 Skill…',
			'skills.enabled' => '启用',
			'skills.filterAll' => '全部',
			'skills.filterAnyCategory' => '全部',
			'skills.filterAnyLanguage' => '全部',
			'skills.filterAnyOccupation' => '全部',
			'skills.filterCategory' => '分类',
			'skills.filterInstalled' => '已安装',
			'skills.filterLanguage' => '语言',
			'skills.filterOccupation' => '职业',
			'skills.filterRepoAll' => '所有仓库',
			'skills.filterSortBy' => '排序',
			'skills.filterSortByRecent' => '最新',
			'skills.filterSortByStars' => '星数',
			'skills.filterUninstalled' => '未安装',
			'skills.goDiscovery' => '前往发现',
			'skills.importFromDisk' => '从磁盘导入',
			'skills.importNothing' => '未发现未管理的 Skill。',
			'skills.importSelected' => ({required int count}) => '导入选中 ${count} 个',
			'skills.importTitle' => '导入未管理的 Skill',
			'skills.installFromZip' => '从 ZIP 安装',
			'skills.installSuccess' => ({required String name}) => '已安装 ${name}',
			'skills.installedCount' => ({required int count}) => '已安装 ${count}',
			'skills.installs' => ({required int count}) => '${count} 次安装',
			'skills.local' => '本地',
			'skills.marketplaceAddRepo' => '添加仓库',
			'skills.marketplaceLoadMore' => '加载更多',
			'skills.marketplaceRepoAdded' => '已添加到仓库源，可在 Repos 页安装具体技能',
			'skills.mpQuotaHint' => 'SkillsMP 匿名额度（每天 50 次）已用完。设置免费 API Key 后继续。',
			'skills.navDiscovery' => '发现',
			'skills.navInstalled' => '已安装',
			'skills.navRegistries' => '注册中心',
			'skills.navRepos' => '仓库',
			'skills.noInstalled' => '还没有安装 Skill',
			'skills.noInstalledHint' => '打开发现页安装你的第一个 Skill。',
			'skills.noUpdates' => '所有 Skill 均为最新',
			'skills.overwriteConfirm' => ({required String name}) => '${name} 已安装。是否覆盖？',
			'skills.registryAddSource' => '添加注册源',
			'skills.registryApiKeySet' => '已设置 API Key',
			'skills.registryBaseUrlLabel' => 'API 地址',
			'skills.registryBrowseQueryLabel' => '默认浏览词',
			'skills.registryEditTitle' => '编辑注册源',
			'skills.registryGoSetKey' => '去注册中心设置 API Key',
			'skills.registryNameLabel' => '显示名称',
			'skills.registryNameOfRepoLabel' => '仓库名',
			'skills.registryOwnerLabel' => 'Owner',
			'skills.registryProtocolLabel' => '协议',
			'skills.registryProtocolSkillsMp' => 'SkillsMP 兼容',
			'skills.registryProtocolSkillsSh' => 'skills.sh 兼容',
			'skills.registryRemoveTitle' => '重置注册源',
			'skills.registryResetConfirm' => ({required String name}) => '将 ${name} 重置为默认值？',
			'skills.registryRetry' => '重试',
			'skills.registrySourceExists' => '该注册源已存在',
			'skills.registrySourceKind' => '源类型',
			'skills.registrySourceKindApi' => 'API 源',
			'skills.registrySourceKindGit' => 'Git 仓库',
			'skills.registryTestFailed' => ({required String error}) => '连接失败：${error}',
			'skills.registryTestOk' => '连接成功',
			'skills.registryTokenLabel' => 'API Key',
			'skills.remove' => '移除',
			'skills.repoAdd' => '添加仓库',
			'skills.repoBranch' => '分支',
			'skills.repoInvalidUrl' => '请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repo',
			'skills.repoRemove' => '移除',
			'skills.repoRemoveConfirm' => ({required String name}) => '确认移除仓库 ${name}？',
			'skills.repoSyncing' => '更新中',
			'skills.repoUrl' => '仓库地址',
			'skills.repoUrlHint' => 'https://github.com/owner/repo',
			'skills.searchPlaceholder' => '搜索 Skill…',
			'skills.sidebarLabel' => 'Skills',
			'skills.subtitle' => '管理可安装的 Skill',
			'skills.title' => 'Skills',
			'skills.uninstallConfirm' => ({required String name}) => '卸载 ${name}？',
			'skills.uninstallSuccess' => ({required String name}) => '已卸载 ${name}',
			'skills.updateAll' => ({required int count}) => '全部更新 (${count})',
			'skills.updateAvailable' => '有新版本',
			'skills.updateSuccess' => ({required String name}) => '已更新 ${name}',
			'skills.zipNoSkills' => '压缩包中未发现 SKILL.md。',
			'ssh.credentialSource' => '凭据来源',
			'ssh.credentialSourceKeychain' => '本机钥匙串',
			'ssh.credentialVaultDeleted' => '已删除的条目',
			'ssh.defaultWorkingDirectorySubtitle' => 'SSH 启动没有工作区路径时使用的远端工作目录；留空则不切换目录。',
			'ssh.defaultWorkingDirectoryTitle' => 'SSH 默认工作目录',
			'ssh.homeDisconnectedBannerMessage' => '远程 SSH 工作环境已断开。请重新连接后再使用 Shell、Git 和 Agent 会话。',
			'ssh.homeDisconnectedReconnect' => '重新连接',
			'ssh.hostKeyFingerprintLabel' => '指纹',
			'ssh.hostKeyKeyTypeLabel' => ({required String keyType}) => '密钥类型：${keyType}',
			'ssh.hostKeyMismatchBody' => ({required String host}) => '${host} 的主机密钥与 TeamPilot 先前保存的不一致。可能是系统重装，也可能是连接被劫持。',
			'ssh.hostKeyMismatchTitle' => 'SSH 主机密钥已变更',
			'ssh.hostKeyPreviousFingerprintLabel' => '先前信任的指纹',
			'ssh.hostKeyReplaceTrust' => '替换并信任',
			'ssh.hostKeyTrust' => '信任并继续',
			'ssh.hostKeyUnknownBody' => ({required String host}) => 'TeamPilot 尚未见过 ${host}。请确认指纹与该机器一致后再信任。',
			'ssh.hostKeyUnknownTitle' => '验证 SSH 主机密钥',
			'ssh.hostsManage' => '管理远程主机',
			'ssh.hostsOpenTerminal' => '打开终端',
			'ssh.hostsOpenTerminalNoWorkspace' => '请先打开一个工作区再启动终端。',
			'ssh.hostsPanelTitle' => '远程主机',
			'ssh.hostsPillConnecting' => '连接中…',
			'ssh.hostsRowKind' => 'SSH 主机',
			'ssh.migrateToVault' => '迁移到保险库',
			'ssh.penaltyRefused' => '服务器暂时拒绝了连接（触发了防暴力破解保护），请等待约一分钟后重试。',
			'ssh.saveToVault' => '保存到保险库',
			'ssh.serversEmpty' => '此主机上还没有保存的 SSH 服务器。',
			'ssh.serversNeedsConnectionHint' => '本机清单中存在，但尚未在这台设备上建立连接',
			'ssh.serversNotConnectedOnDevice' => '尚未在这台设备上建立连接',
			'ssh.serversLoadError' => '无法加载 SSH 服务器，请检查连接后重试。',
			_ => null,
		} ?? switch (path) {
			'ssh.serversNotConnected' => '未连接远程主机。',
			'ssh.serversTitle' => 'SSH 服务器',
			'ssh.vaultBadge' => '保险库',
			'ssh.hostsPillCount' => ({required int count}) => '${count} 台主机',
			'sshProfile.connect' => '连接',
			'sshProfile.connectSuccess' => ({required String host}) => '已连接到 ${host}',
			'sshProfile.delete' => '删除',
			'sshProfile.disconnect' => '断开',
			'sshProfile.edit' => '编辑',
			'sshProfile.formAuthChangeBody' => '保存后会清除该目标另一种认证方式已保存的凭据。',
			'sshProfile.formAuthChangeConfirm' => '切换并保存',
			'sshProfile.formAuthChangeTitle' => '切换认证方式？',
			'sshProfile.formAuthPrivateKey' => '私钥',
			'sshProfile.formAuthType' => '认证方式',
			'sshProfile.formCredentialRequired' => '请提供私钥或密码。',
			'sshProfile.formCredentialSaveFailed' => '目标已保存，但无法写入凭据。请解锁系统钥匙环后编辑该目标并重新填写。',
			'sshProfile.formFieldRequired' => '必填',
			'sshProfile.formHost' => '主机或别名',
			'sshProfile.formHostHint' => 'server、deploy@server:2222',
			'sshProfile.formIdentityFile' => '私钥内容',
			'sshProfile.formIdentityFileHelper' => '可直接粘贴私钥，或从文件导入。',
			'sshProfile.formIdentityFileHint' => '-----BEGIN OPENSSH PRIVATE KEY-----',
			'sshProfile.formIdentityFileImport' => '从文件导入',
			'sshProfile.formIdentityFileImportFailed' => '无法读取所选文件，请直接粘贴私钥',
			'sshProfile.formLabel' => '标签',
			'sshProfile.formLabelHint' => '我的服务器',
			'sshProfile.formPassphrase' => '密钥口令',
			'sshProfile.formPassphraseHint' => '可选',
			'sshProfile.formPassword' => '密码',
			'sshProfile.formPasswordHint' => '登录密码',
			'sshProfile.formPasswordHintEdit' => '留空则保留已保存密码',
			'sshProfile.formPort' => '端口',
			'sshProfile.formPortInvalid' => '端口须在 1–65535 之间',
			'sshProfile.formTitleEdit' => '编辑 SSH 目标',
			'sshProfile.formTitleNew' => '新的 SSH 目标',
			'sshProfile.formUsername' => '用户名',
			'sshProfile.formUsernameHint' => 'deploy',
			'sshProfile.refresh' => '刷新',
			'sshProfile.selectorManage' => '管理 SSH 服务器…',
			'sshProfile.selectorTooltip' => '切换 SSH 服务器',
			'sshProfile.statusAuthFailed' => '认证失败',
			'sshProfile.statusConnected' => '已连接',
			'sshProfile.statusConnecting' => '连接中…',
			'sshProfile.statusDisconnected' => '未连接',
			'sshProfile.statusError' => '错误',
			'sshProfile.statusReconnecting' => '重连中…',
			'sshProfile.test' => '测试',
			'sshProfile.testFailed' => '连接测试失败',
			'sshProfile.testFailedAborted' => ({required String detail}) => '登录前连接已断开：${detail}',
			'sshProfile.testFailedAuth' => '身份验证失败',
			'sshProfile.testFailedDetail' => ({required String detail}) => '连接测试失败：${detail}',
			'sshProfile.testFailedHostKey' => '主机密钥未获信任',
			'sshProfile.testSuccess' => '连接成功',
			'sshProfile.sAddTarget' => '添加目标',
			'sshProfile.sEmpty' => '尚未配置 SSH 目标。',
			'sshProfile.sImport' => '导入',
			'sshProfile.sImportUnavailable' => '暂不支持从 ~/.ssh/config 导入。',
			'sshProfile.sPageSubtitle' => '当前主目录所在主机上保存的 SSH 服务器配置；配对了同一主目录的设备共享这份清单。',
			'sshProfile.sPageTitle' => '远程 SSH 服务器',
			'sshProfile.sSettingsTitle' => 'SSH 服务器',
			'sshProfile.sTargetsSubtitle' => '添加远程主机以在 TeamPilot 中连接到它。',
			'sshProfile.sTargetsTitle' => '目标',
			'team.cliComingSoon' => '即将支持',
			'team.cliLabel' => 'CLI 后端',
			'team.cliLockedSubtitle' => '在创建团队时已选定。',
			'team.cliSubtitle' => '创建团队时选定，之后不可更改。',
			'team.config' => '团队配置',
			'team.configAspectCli' => 'CLI',
			'team.configAspectDefaultProvider' => '默认服务商',
			'team.configAspectModel' => '模型',
			'team.configAspectProvider' => '服务商',
			'team.configAspectSeparator' => '、',
			'team.configGroupTeamDefault' => '团队默认',
			'team.configIncompleteBody' => ({required String team}) => '团队“${team}”缺少启动所需的配置。会话仍会启动，但缺少这些配置时智能体可能无法正常工作：',
			'team.configIncompleteDismiss' => '稍后',
			'team.configIncompleteGoConfigure' => '前往配置',
			'team.configIncompleteTitle' => '团队配置不完整',
			'team.configIssueSemanticLabel' => ({required String subject, required String aspects}) => '${subject}缺少：${aspects}',
			'team.defaultCliMixedSubtitle' => '成员未指定时使用。',
			'team.defaultDialogEffortSubtitle' => '团队默认力度。',
			'team.defaultPresetChange' => '更改',
			'team.defaultPresetLabel' => '默认模型预设',
			'team.defaultPresetManage' => '管理',
			'team.defaultPresetNone' => '无',
			'team.defaultPresetSubtitle' => '可选的默认预设，未单独设置的成员将继承此配置。',
			'team.description' => '团队描述',
			'team.descriptionHint' => '可选，写入 Claude roster 的 description 字段',
			'team.effortLevel' => '推理力度',
			'team.effortLevelSubtitle' => '团队默认力度（Claude effortLevel / Codex model_reasoning_effort）。',
			'team.extensionEffectiveOff' => '本团队未启用',
			'team.extensionEffectiveOn' => '本团队已启用',
			'team.extensionFollowGlobal' => '跟随全局',
			'team.extensionForceOff' => '关闭',
			'team.extensionForceOn' => '开启',
			'team.extensionsNav' => '扩展',
			'team.extensionsSubtitle' => '覆盖本团队启用哪些扩展，默认跟随全局设置。',
			'team.extensionsTitle' => '本团队的扩展',
			'team.extraArgs' => '团队额外 CLI 参数',
			'team.extraArgsHint' => '--permission-mode acceptEdits',
			'team.forceWaitBeforeStopSubtitle' => '开启后,成员结束一个回合时会被推回 wait_for_message 而不是停止,从而持续待命接收新消息和任务。关闭则允许成员“休息”(正常停止)。',
			'team.forceWaitBeforeStopTitle' => '让成员保持在等待循环',
			'team.genApplied' => '草稿已应用，创建前请检查调整。',
			'team.genButton' => '生成',
			'team.genDescriptionHint' => '描述你想要的团队（例如：做 Flutter 前端、需要代码审查和测试）',
			'team.genFailed' => '无法生成团队，请手动编辑。',
			'team.genNoProvider' => '请先在 设置 → AI 功能 中配置 AI provider。',
			'team.genTitle' => '用 AI 生成',
			'team.generateAddModel' => '添加模型配置',
			'team.generateBuilderTitle' => '团队构建器',
			'team.generateCancel' => '取消生成',
			'team.generateCancelBody' => '临时会话和暂存资源将被移除。',
			'team.generateCancelTitle' => '取消团队生成？',
			'team.generateCapabilityNote' => '团队构建器将检查工作区机器，并可能为生成的团队获取技能、插件和 MCP 服务器。',
			'team.generateContinueSetup' => '继续配置',
			'team.generateDeliveryArrived' => '已收到',
			'team.generateDeliveryRetryBody' => '负责人可能会收到两次任务。',
			'team.generateDeliveryRetryTitle' => '再次发送任务？',
			'team.generateDeliverySendAgain' => '再次发送…',
			'team.generateDescription' => '强项与适用场景',
			'team.generateEmptyPool' => '还没有配置。请先添加最强的一项。',
			'team.generateErrorAiNotConfigured' => '请先配置生成模型。',
			'team.generateErrorDescriptionRequired' => '请先描述需要团队处理的任务。',
			'team.generateErrorGeneratorUnsupported' => '生成 CLI 必须支持会话、技能和 MCP。',
			'team.generateErrorNativeUnsupported' => '所选 CLI 不支持原生团队。',
			'team.generateErrorPoolEmpty' => '请至少添加一个有效的模型配置。',
			'team.generateErrorPromptDeliveryUnknown' => 'TeamPilot 无法确认负责人是否已收到任务。',
			'team.generateErrorRecoveryIntegrity' => '无法验证恢复数据，临时会话已保留。',
			'team.generateErrorStagingUnsupported' => '此资源需要人工安装，无法安全暂存。',
			'team.generateErrorStartFailed' => '无法启动团队生成。请重试。',
			'team.generateErrorTargetUnavailable' => '所需机器或 CLI 当前不可用。',
			'team.generateErrorUnavailable' => '团队生成当前不可用。请重启 TeamPilot 后重试。',
			'team.generateErrorUserActionRequired' => '请完成所需的登录或配置，然后重试。',
			'team.generateGeneratorModel' => '生成模型',
			'team.generateHiddenPresets' => ({required int count}) => '${count} 个配置因使用其他 CLI 而隐藏。',
			'team.generateLaunch' => '生成并启动',
			'team.generateLoading' => '正在加载设置…',
			'team.generateMinimumMemberCount' => '团队最少成员数',
			'team.generateMinimumMemberCountHint' => '生成的团队至少包含这么多不同的角色。',
			'team.generateMinimumMemberCountInvalid' => '最少需要 3 名成员。',
			'team.generateMissingPreset' => ({required String presetId}) => '预设“${presetId}”已不存在。',
			'team.generateMixed' => '混合',
			'team.generateModelPool' => '模型配置池',
			'team.generateModelPoolHint' => '排名 1 最强。关键角色（如 team-lead）优先用靠前的配置。',
			'team.generateMoveDown' => '下移',
			'team.generateMoveUp' => '上移',
			'team.generateNative' => '原生',
			'team.generateNativeCli' => '原生 CLI',
			'team.generateOpenLeadSession' => '打开负责人会话',
			'team.generateOpenSettings' => '打开生成设置',
			'team.generatePickPreset' => '选择预设',
			'team.generateRemove' => '移除',
			'team.generateRetainBuilderSession' => '保留团队构建 Session 以便排错',
			'team.generateRetainBuilderSessionHint' => '开启后仍会正常打开生成的团队，但会保留构建 Session，方便查看团队生成过程。',
			'team.generateRetry' => '重试',
			'team.generateSettingsSubtitle' => '设定团队构建器如何规划阵容，以及可分配的模型配置。',
			'team.generateSettingsTitle' => '生成并启动设置',
			'team.generateTags' => '标签',
			'team.generateTeamMode' => '团队模式',
			'team.hooksAssignedCount' => ({required int assigned, required int total}) => '已启用 ${assigned}/${total}',
			'team.hooksManage' => '管理 Hooks',
			'team.hooksNav' => 'Hooks',
			'team.leadBadge' => 'Leader',
			'team.leadDelegateOnlySubtitle' => '开启后将禁止队长使用一些工具。',
			'team.leadDelegateOnlyTitle' => '队长仅规划分派',
			'team.leadNameRequired' => 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。',
			'team.leadNotice' => 'FlashskyAI 团队委托要求此成员名称必须为 team-lead。',
			'team.loop' => '阶段循环',
			'team.loopDefault' => '默认',
			'team.loopFalse' => 'false — 每阶段确认',
			'team.loopSubtitle' => '团队模式：true 自动推进阶段；false 需你确认后再继续。',
			'team.loopTrue' => 'true — 自动推进',
			'team.mcpAssignedCount' => ({required int assigned, required int total}) => '已启用 ${assigned}/${total}',
			'team.mcpManage' => '管理 MCP',
			'team.mcpNav' => 'MCP',
			'team.modeLabel' => '团队模式',
			'team.modeMixed' => '混合（跨 CLI bus）',
			'team.modeMixedDescription' => '不同成员可使用不同 CLI，通过 TeamBus 跨工具协作。',
			'team.modeMixedTitle' => '混合模式',
			'team.modeNative' => '原生（单 CLI）',
			'team.modeNativeDescription' => '全部成员共用同一个 CLI，原生协同，配置简单。',
			'team.modeNativeTitle' => '原生模式',
			'team.modeRequired' => '请先选择团队模式。',
			'team.name' => '团队名称',
			'team.nameAlreadyExists' => ({required String name}) => '已存在名为「${name}」的团队。',
			'team.nameRequired' => '团队名称不能为空。',
			'team.pluginsAssignedCount' => ({required int assigned, required int total}) => '已安装 ${assigned}/${total}',
			'team.pluginsCliUnsupportedBanner' => '当前团队 CLI 暂不支持插件，启用记录已保存但不会生效。',
			'team.pluginsEmpty' => '尚未安装插件',
			'team.pluginsEmptyHint' => '在「发现」中安装插件后，可在此处按团队启用。',
			'team.pluginsGoDiscovery' => '浏览 marketplace',
			'team.pluginsManage' => '全部插件',
			'team.pluginsMissing' => ({required int count}) => '有 ${count} 个已启用插件在磁盘上缺失，重新安装或手动移除。',
			'team.pluginsMissingLabel' => '磁盘上缺失',
			'team.pluginsNameConflict' => ({required String dir}) => '因名称冲突，已链接为 ${dir}',
			'team.pluginsNav' => '插件',
			'team.pluginsRemoveMissing' => '移除',
			'team.sessions' => '团队会话',
			'team.settings' => '团队设置',
			'team.settingsSubtitle' => '团队代理',
			'team.skillsAssignedCount' => ({required int assigned, required int total}) => '已启用 ${assigned}/${total}',
			'team.skillsManage' => '全部 Skills',
			'team.skillsNav' => 'Skills',
			'teamHub.alreadyAdded' => '已添加',
			'teamHub.browseAll' => '浏览全部团队',
			'teamHub.cardNoDescription' => '无',
			'teamHub.categoryAll' => '全部',
			'teamHub.clone' => '克隆为我的团队',
			'teamHub.cloneFailed' => '无法克隆该团队。',
			'teamHub.cloneOptionsTitle' => '克隆选项',
			'teamHub.clonePartial' => ({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount, required int failedCount, required Object failedNames}) => '已克隆「${name}」。已安装 ${skillCount} 个 Skill、${pluginCount} 个插件、${mcpCount} 个 MCP 服务,克隆了 ${expertCount} 个专家;${failedCount} 个未能安装:${failedNames}。',
			'teamHub.cloneSuccess' => ({required Object name}) => '已克隆「${name}」。',
			'teamHub.cloneSuccessWithDeps' => ({required Object name, required int skillCount, required int pluginCount, required int mcpCount, required int expertCount}) => '已克隆「${name}」。已安装 ${skillCount} 个 Skill、${pluginCount} 个插件、${mcpCount} 个 MCP 服务,并克隆了 ${expertCount} 个专家。',
			'teamHub.cloning' => '正在克隆…',
			'teamHub.confirmSelection' => '确认',
			'teamHub.depInstalled' => '已安装',
			'teamHub.depToInstall' => '将安装',
			'teamHub.discovery' => '发现',
			'teamHub.emptyHint' => '点击刷新从注册表拉取团队。',
			'teamHub.emptyTitle' => '暂无公开团队',
			'teamHub.favorites' => '我的收藏',
			'teamHub.favoritesEmptyHint' => '点击团队上的星标即可收藏到这里。',
			'teamHub.favoritesEmptyTitle' => '暂无收藏',
			'teamHub.loadError' => '无法加载公开团队。',
			'teamHub.mcpLabel' => 'MCP',
			'teamHub.membersLabel' => '成员',
			'teamHub.nav' => '团队中心',
			'teamHub.notFound' => '未找到该团队。',
			'teamHub.pluginsLabel' => '插件',
			'teamHub.refresh' => '刷新',
			'teamHub.searchHint' => '搜索公开团队',
			'teamHub.skillsLabel' => '技能',
			'teamHub.sortName' => '名称',
			'teamHub.sortUpdated' => '最近更新',
			'teamHub.subtitle' => '发现更多公开团队',
			'teamHub.title' => '团队中心',
			'terminal.clear' => '清除终端',
			'terminal.copySelectHint' => '按住 Shift 选择复制',
			'terminal.dropCrossMachineRejected' => '无法将本地文件拖入远程终端',
			'terminal.exportScrollback' => '导出滚动缓冲…',
			'terminal.find' => '在终端中查找',
			'terminal.findNoResults' => '无匹配',
			'terminal.linkClickOpensInAppDescription' => '左键点击链接和文件路径时在 TeamPilot 内打开，而不是交给正在运行的程序。Ctrl/Cmd+点击始终在应用内打开。',
			'terminal.linkClickOpensInAppTitle' => '在应用内打开终端链接',
			'terminal.openLink' => '打开链接',
			'terminal.parkedSendDismiss' => '关闭',
			'terminal.parkedSendPending' => ({required String content}) => '已发送，等待接收：${content}',
			'terminal.scrollbackLinesDescription' => '每个会话终端保留的最大行数',
			'terminal.scrollbackLinesTitle' => '终端滚动缓冲行数',
			'terminal.themeModeDescription' => '跟随主题色或使用固定风格',
			'terminal.themeModeTitle' => '终端主题',
			'termux.disconnectedBannerMessage' => 'Termux 已断开连接。请重新连接后再使用 Shell、Git 和 Agent 会话。',
			'termux.disconnectedReconnect' => '重新连接',
			'termux.disconnectedWorkOpsBlocked' => 'Termux 已断开连接。请通过顶部横幅重新连接后再试。',
			'termux.setupClearConfirmAction' => '清除设置',
			'termux.setupClearConfirmBody' => '将删除已保存的 Termux 密钥和用户名，需要重新完成 Termux 设置。',
			'termux.setupClearConfirmTitle' => '清除 Termux 设置？',
			'termux.setupClearSetup' => '清除设置',
			'termux.setupConnect' => '连接',
			'termux.setupConnectFailed' => '无法连接到 Termux',
			'termux.setupConnectFailedWithDetail' => ({required String detail}) => '无法连接到 Termux：${detail}',
			'termux.setupConnectSuccess' => '已连接到 Termux',
			'termux.setupConnecting' => '正在连接…',
			'termux.setupDownloadFailed' => '无法下载 Termux。请重试或使用应用商店链接。',
			'termux.setupDownloadInstall' => '下载并安装 Termux',
			'termux.setupDownloading' => '正在下载 Termux…',
			'termux.setupInstallDenied' => '安装已取消或被阻止。如需要请启用未知来源应用，然后重试。',
			'termux.setupInstallFDroid' => 'F-Droid',
			'termux.setupInstallGitHub' => 'GitHub',
			'termux.setupInstallPlayStore' => 'Play 商店',
			'termux.setupInstalling' => '正在安装…',
			'termux.setupIntro' => '安装 Termux，粘贴一条配置脚本，然后连接 TeamPilot 的本地 SSH 服务。',
			'termux.setupScriptHint' => '弹出存储授权时请允许。脚本会用 termux-services 启用 sshd（打开 Termux 即启动）。若需开机且不打开 Termux，可另装 Termux:Boot（F-Droid）。最后一行会打印用户名（例如 u0_a399）。',
			'termux.setupStepInstallTermux' => '1. 安装 Termux',
			'termux.setupStepRunScript' => '2. 在 Termux 中粘贴这条脚本',
			'termux.setupTermuxInstalled' => 'Termux 已安装',
			'termux.setupTitle' => 'Termux 设置',
			'termux.setupUsernameError' => '请输入有效的 Termux 用户名（以 u 开头）',
			'termux.setupUsernameHint' => '例如 u0_a399',
			'termux.setupUsernameLabel' => '3. 粘贴 Termux 用户名',
			'theme.theme' => '主题',
			'theme.colorPresetDescription' => '用于按钮、开关与高亮的主色与强调色。',
			'theme.colorPresetTitle' => '主题色',
			'theme.dark' => '深色',
			'theme.light' => '浅色',
			'theme.modeDescription' => '浅色、深色，或与系统外观一致。',
			'theme.modeTitle' => '主题模式',
			'theme.presetAmber' => '琥珀',
			'theme.presetForest' => '森林',
			'theme.presetGraphite' => '石墨',
			'theme.presetOcean' => '海洋',
			'theme.presetViolet' => '紫罗兰',
			'theme.system' => '跟随系统',
			'tool.categoryAskUser' => '询问用户',
			'tool.categoryBrowser' => '浏览器',
			'tool.categoryCommand' => 'Shell 命令',
			'tool.categoryEdit' => '编辑文件',
			'tool.categoryMcp' => 'MCP',
			'tool.categoryOther' => '其他',
			'tool.categoryPlan' => '计划',
			'tool.categoryRead' => '读取文件',
			'tool.categorySearch' => '网络搜索',
			'tool.categorySubagent' => '子代理',
			'tool.categoryTask' => '任务与待办',
			'tool.categoryWrite' => '写入文件',
			'tool.placement' => '工具栏位置',
			'tool.placementDescription' => '将工具面板固定在右侧或沿底部边缘排列。',
			'typography.scaleComfortable' => '宽松',
			'typography.scaleCompact' => '紧凑',
			'typography.scaleCustom' => '自定义',
			'typography.scaleCustomHint' => '50–200',
			'typography.scaleCustomLabel' => '缩放比例',
			'typography.scaleDescription' => '界面文字大小。「标准」跟随系统；不改变图标与间距。',
			'typography.scaleStandard' => '标准',
			'typography.scaleTitle' => '文字大小',
			'vault.cancel' => '取消',
			'vault.copied' => '已复制',
			'vault.copy' => '复制',
			'vault.deleteConfirm' => '删除',
			'vault.deleteReferenced' => '该条目仍被以下位置使用：',
			'vault.deleteTitle' => '删除条目？',
			'vault.disableEncryption' => '停用加密保险库',
			'vault.emptyHint' => '在这里保存 SSH 密码、私钥或供应商 API Key。',
			'vault.emptyTitle' => '还没有条目',
			'vault.enableEncryption' => '启用加密保险库',
			'vault.entryFavorite' => '收藏',
			'vault.entryNotes' => '备注',
			'vault.entryTags' => '标签（逗号分隔）',
			'vault.entryTitle' => '标题',
			'vault.entryType' => '类型',
			'vault.hide' => '隐藏',
			'vault.homeOfflineHint' => '未连接远程主机，保存在该主机上的业务凭据暂时不可用，重连后即可查看。',
			'vault.lock' => '立即锁定',
			'vault.lockedQueryBlocked' => '请先解锁保险库再查询用量。',
			'vault.lockedSaveBlocked' => '请先解锁保险库再保存凭据。',
			'vault.newEntry' => '新建条目',
			'vault.noReferences' => '尚未被引用',
			'vault.onlyCopy' => '仅复制',
			'vault.pageSubtitle' => 'SSH 密码、私钥与供应商 API Key',
			'vault.pageTitle' => '保险库',
			'vault.passphrase' => '主密码',
			'vault.passphraseConfirm' => '确认主密码',
			'vault.passphraseMismatch' => '两次输入的密码不一致',
			'vault.passphraseRequired' => '请输入主密码',
			'vault.references' => '被引用',
			'vault.reveal' => '显示',
			'vault.save' => '保存',
			'vault.searchHint' => '搜索标题、字段或标签',
			'vault.statusEncrypted' => '加密保险库 · 已锁定',
			'vault.statusKeychain' => '系统钥匙串 · 无需解锁',
			'vault.statusUnlocked' => '加密保险库 · 已解锁',
			'vault.storedInVault' => '已存入保险库',
			'vault.typeApiKey' => '供应商 API Key',
			'vault.typeCustom' => '自定义',
			'vault.typeLogin' => '账号密码',
			'vault.typeSecureNote' => '安全笔记',
			'vault.typeSshPassword' => 'SSH 密码',
			'vault.typeSshPrivateKey' => 'SSH 私钥',
			'vault.typeToken' => '令牌',
			'vault.unavailable' => '凭据保险库不可用。',
			'vault.unlock' => '解锁',
			'vault.unlockFailed' => '解锁失败',
			'vault.unlockTitle' => '解锁保险库',
			'vault.wrongPassphraseHint' => '密码错误或文件损坏，数据未被修改。',
			'workspace.additionalDirectories' => '附加目录',
			'workspace.advancedSettings' => '高级配置',
			'workspace.advancedSettingsSubtitle' => 'Agent 预设与本成员的额外 CLI 参数。',
			'workspace.agentBuiltInSubtitle' => '当前 CLI 为 flashskyai 时，对应其 --agent 参数。',
			'workspace.agentExtraArgs' => '额外 CLI 参数',
			'workspace.agentExtraArgsSubtitle' => '附加在本工作区 Agent 启动时的 CLI 参数。',
			'workspace.agentPromptPresetDeveloper' => '开发',
			'workspace.agentPromptPresetDeveloperText' => '专注实现功能与修复问题。优先小 diff，跑相关测试，并简要说明改了哪些文件及原因。',
			'workspace.agentPromptPresetGeneral' => '通用',
			'workspace.agentPromptPresetGeneralText' => '全面协助完成本工作区中的开发任务。先理解需求与现有代码，再给出清晰方案并实施；优先小范围改动，完成后说明涉及文件与后续建议。',
			'workspace.agentPromptPresetResearcher' => '调研',
			'workspace.agentPromptPresetResearcherText' => '只调研并汇报，除非被要求否则不要改生产代码。\n输出需含文件路径、相关符号与建议的下一步。',
			'workspace.agentPromptPresetReviewer' => '审查',
			'workspace.agentPromptPresetReviewerText' => '只做代码审查，除非被要求否则不要改文件。\n每条意见需包含：文件路径、行号、问题、建议改法。',
			'workspace.agentPromptSubtitle' => '编写系统提示词，定义 Agent 在本工作区中的职责与行为边界。',
			'workspace.chatLandingAttach' => '附加文件',
			'workspace.chatLandingBackToWorkbench' => '返回工作台',
			'workspace.chatLandingConnectApps' => '连应用',
			'workspace.chatLandingCustomLaunch' => '自定义…',
			'workspace.chatLandingCustomLaunchTitle' => '自定义启动',
			'workspace.chatLandingInputHint' => '今天帮你做些什么？ @ 引用对话文件，/ 调用技能与指令',
			'workspace.chatLandingModeSimple' => '简单对话',
			'workspace.chatLandingModeTeam' => '团队',
			'workspace.chatLandingSelectLaunchDirectory' => '选择目录 >',
			'workspace.chatLandingSelectProject' => '选择项目 >',
			'workspace.chatLandingSelectWorkspace' => '选择工作空间 >',
			'workspace.chatLandingSelectWorktree' => '选择 worktree >',
			'workspace.chatLandingSkills' => '技能',
			'workspace.chatLandingTeamLaunchBlocked' => '请先在团队设置中配置团队与成员的模型预设，再发送消息。',
			'workspace.chatLandingUsePreset' => '使用预设',
			'workspace.chatLandingVoice' => '语音输入',
			'workspace.chatLandingVoiceCancel' => '取消录音',
			'workspace.chatLandingVoiceMacOsIdeLaunch' => '从 IDE 启动时 macOS 不会把语音识别权限授予 TeamPilot。请直接运行 build/macos/Build/Products/Debug/TeamPilot.app，或在 Xcode 中启动。',
			'workspace.chatLandingVoicePermissionDenied' => '未获得麦克风权限',
			'workspace.chatLandingVoiceStop' => '停止录音',
			'workspace.chatLandingVoiceUnavailable' => '此设备不支持语音输入',
			'workspace.cliAddPresetTitle' => '添加预设',
			'workspace.cliConfigSummary' => ({required String provider, required String model}) => '${provider} · ${model}',
			'workspace.cliConfigure' => '配置',
			'workspace.cliConfigured' => '已配置',
			'workspace.cliDefaultSubtitle' => '本工作区新建对话时使用的默认 CLI。',
			'workspace.cliDefaultsSubtitle' => '为本工作区使用的每个 CLI 设置默认提供商与模型。',
			'workspace.cliDefaultsTitle' => 'CLI 默认配置',
			'workspace.cliDeletePresetConfirm' => ({required String name}) => '删除预设\'${name}\'？此操作不可撤销。',
			'workspace.cliDeletePresetTitle' => '删除预设',
			'workspace.cliEditPresetTitle' => '编辑预设',
			'workspace.cliEffortInheritHint' => '使用提供商默认',
			'workspace.cliEffortLevel' => '推理力度',
			'workspace.cliEffortLevelSubtitle' => '本工作区使用该 CLI 时的默认力度（留空则使用提供商默认）。',
			'workspace.cliManagePresets' => '管理',
			'workspace.cliNoPresetHint' => '未选择预设',
			'workspace.cliNoProviderCatalog' => '此 CLI 无需配置提供商',
			'workspace.cliNotConfigured' => '未配置',
			'workspace.cliNotConfiguredHint' => '选择提供商',
			'workspace.cliPresetLabel' => '当前预设',
			'workspace.cliPresetNameLabel' => '预设名称',
			'workspace.cliPresetsEmptyHint' => '还没有预设，创建一个开始使用',
			'workspace.cliPresetsManageTitle' => '管理预设',
			'workspace.cliProviderConfig' => '供应商配置',
			'workspace.cliProviderModelTitle' => '提供商与模型',
			'workspace.createdAt' => '创建时间',
			'workspace.deadTargetBadge' => '机器不可用',
			'workspace.deadTargetRemap' => '重新映射…',
			'workspace.deadTargetRemapBody' => ({required String from}) => '将 ${from} 替换为另一台机器。目录路径不会改动，目标机器上必须已有相同路径。',
			'workspace.deadTargetRemapConfirm' => '重新映射',
			'workspace.deadTargetRemapFailed' => '无法重新映射机器。',
			'workspace.deadTargetRemapFromLaunch' => '重新映射机器…',
			'workspace.deadTargetRemapNothing' => '没有可映射的目标。',
			'workspace.deadTargetRemapPickFrom' => '失效机器',
			'workspace.deadTargetRemapPickTo' => '替换为',
			'workspace.deadTargetRemapTitle' => '重新映射机器',
			'workspace.details' => '工作区详情',
			'workspace.directoryAdded' => '已添加目录到工作区',
			'workspace.directoryAlreadyAdded' => '该目录已在工作区中。',
			'workspace.directoryAlreadyPrimary' => '该路径已是工作区主目录。',
			'workspace.displayName' => '显示名称',
			'workspace.entryModeDescription' => 'App 启动后默认打开的页面。',
			'workspace.entryModeHome' => '主页',
			'workspace.entryModeLastWorkspace' => '恢复上次工作区',
			'workspace.entryModeTitle' => '启动视图',
			'workspace.extensionEffectiveOff' => '本工作区未启用',
			'workspace.extensionEffectiveOn' => '本工作区已启用',
			'workspace.extensionsSubtitle' => '覆盖本工作区启用哪些扩展，默认跟随全局设置。',
			'workspace.extensionsTitle' => '本工作区的扩展',
			'workspace.folderPathLabel' => '目录',
			'workspace.folderTargetLabel' => '所在机器',
			'workspace.foldersAddOnAnotherMachine' => '添加其他主机目录',
			'workspace.foldersApplyAllLocal' => '全部设为本地',
			'workspace.foldersApplyAllRemote' => '全部设为远程…',
			'workspace.foldersChangeTarget' => '更换',
			'workspace.foldersEditorHint' => '每个目录单独指定所在机器与路径。全部本地 = 本地工作区；全部同一远程 = 项目远程；跨机 = 混合工作区（成员远程）。',
			'workspace.foldersPersonalTargetsLockedHint' => '个人身份下无法更改目录所在机器。请切换到团队身份配置机器与目录。',
			'workspace.foldersPickMixedTarget' => '添加到机器',
			'workspace.foldersPickPath' => '选择目录',
			'workspace.foldersPickRemoteTarget' => '选择远程机器',
			'workspace.foldersPickTarget' => '选择机器',
			'workspace.foldersSectionTitle' => '工作区目录与机器',
			'workspace.hooksAssignedCount' => ({required int assigned, required int total}) => '已为本工作区启用 ${assigned}/${total}',
			'workspace.hooksManage' => '管理 Hooks',
			'workspace.icon' => '图标',
			'workspace.iconPickerTitle' => '选择工作区图标',
			'workspace.iconUpload' => '上传图标',
			'workspace.iconUploadFailed' => '无法保存图标，请使用 PNG、JPG、WEBP 或 SVG。',
			'workspace.iconUseDefault' => '使用默认',
			'workspace.mcpAssignedCount' => ({required int assigned, required int total}) => '已为本工作区启用 ${assigned}/${total}',
			'workspace.mcpManage' => '管理 MCP',
			'workspace.noAdditionalDirectories' => '暂无附加目录',
			'workspace.pluginsAssignedCount' => ({required int assigned, required int total}) => '已为本工作区选用 ${assigned}/${total}',
			'workspace.pluginsEmpty' => '尚未安装插件',
			'workspace.pluginsEmptyHint' => '在「发现」中安装插件后，可在此处为本工作区启用。',
			'workspace.pluginsManage' => '管理插件',
			'workspace.primaryPath' => '主目录',
			'workspace.primaryPathNotSelected' => '尚未选择主目录',
			'workspace.primaryPathRequired' => '请先选择主目录。',
			'workspace.runningSessionsSection' => '已打开',
			'workspace.searchBackend' => ({required String backend}) => '引擎：${backend}',
			'workspace.searchCancel' => '取消',
			'workspace.searchCaseSensitive' => '大小写',
			'workspace.searchContent' => '内容',
			'workspace.searchEmptyHint' => '输入以搜索文件内容',
			'workspace.searchError' => '搜索失败——请检查正则',
			'workspace.searchExcludeHint' => '排除 (glob，逗号分隔)',
			'workspace.searchFilesEmptyHint' => '输入关键词搜索文件',
			'workspace.searchFilesSection' => '文件',
			'workspace.searchFilesToExclude' => '排除的文件：',
			'workspace.searchFilesToInclude' => '包含的文件：',
			'workspace.searchFilterAll' => '全部',
			'workspace.searchFilterConversations' => '任务',
			'workspace.searchFilterFiles' => '文件',
			'workspace.searchGitignore' => '.gitignore',
			'workspace.searchHint' => '搜索会话、文件和会话内容',
			'workspace.searchIncludeHint' => '包含 (glob，逗号分隔)',
			'workspace.searchIndexing' => '正在索引…',
			'workspace.searchNoResults' => '没有匹配结果',
			'workspace.searchPanel' => '搜索',
			'workspace.searchQueryHint' => '搜索文件',
			'workspace.searchRecentSessions' => '最近会话',
			'workspace.searchRegex' => '正则',
			'workspace.searchReplace' => '替换',
			'workspace.searchReplaceAll' => '全部替换',
			'workspace.searchReplaceAllMessage' => ({required int count}) => '替换 ${count} 处匹配？',
			'workspace.searchReplaceAllTitle' => '全部替换？',
			'workspace.searchReplaceHint' => '替换为',
			'workspace.searchReplacedCount' => ({required int count}) => '已替换 ${count} 处',
			'workspace.searchResultSummary' => ({required int matches, required int files}) => '${matches} 个结果 · ${files} 个文件',
			'workspace.searchSearching' => '正在搜索文件…',
			'workspace.searchShowMore' => '查看更多结果',
			'workspace.searchSliceError' => ({required String directory}) => '「${directory}」目录搜索失败',
			'workspace.searchTitle' => '搜索',
			_ => null,
		} ?? switch (path) {
			'workspace.searchToggleDetails' => '展开搜索选项',
			'workspace.searchTruncated' => '结果过多已截断——请细化查询',
			'workspace.searchUseGitignore' => '使用 .gitignore 设置',
			'workspace.sessionCount' => '会话数',
			'workspace.sidebarGroupsView' => '分组',
			'workspace.sidebarProjectTreeView' => '项目树',
			'workspace.skillsAssignedCount' => ({required int assigned, required int total}) => '已为本工作区启用 ${assigned}/${total}',
			'workspace.skillsManage' => '管理 Skills',
			'workspace.targetSubtitle' => '该工作区的目录所在并运行的机器。会话在此 target 上启动；切换不会移动文件。',
			'workspace.targetTitle' => '工作区所在机器',
			'workspace.terminal' => '终端',
			'workspace.terminalClose' => '关闭终端面板',
			'workspace.terminalCloseSession' => '关闭终端',
			'workspace.terminalNewSession' => '新建终端',
			'workspace.terminalNewSessionMenu' => '新建终端会话菜单',
			'workspace.terminalNewSshSession' => '新建 SSH 会话…',
			'workspace.terminalNoWorkingDirectory' => '请先连接会话以打开 Shell 终端',
			'workspace.terminalRestoring' => '正在恢复终端…',
			'workspace.terminalSettings' => '设置',
			'workspace.terminalSshConnectFailed' => 'SSH 配置未找到或连接失败',
			'workspace.terminalThemeAdaptive' => '跟随主题',
			'workspace.terminalThemeClassicDark' => '经典暗色',
			'workspace.terminalThemeHighContrast' => '高对比',
			'workspace.toolsResolveFailed' => '无法打开工作区工具',
			'workspace.toolsResolveFailedHint' => '请确认远程机器可连通后再重试。',
			'workspace.topologyLocal' => '本地工作区',
			'workspace.topologyMixed' => '混合工作区',
			'workspace.topologyRemote' => '远程工作区',
			'workspace.typeLabel' => '类型',
			'workspace.updatedAt' => '更新时间',
			'workspace.workbenchAdvancedSettingsSubtitle' => '本工作区的 Agent 预设与额外 CLI 参数。',
			'worktree.baseSelectorHint' => '分支或基线',
			'worktree.branchLabel' => '分支名',
			'worktree.createAction' => '创建',
			'worktree.createFailed' => ({required Object error}) => '创建 worktree 失败：${error}',
			'worktree.createTitle' => '新建 worktree',
			'worktree.creating' => '正在创建…',
			'worktree.deleteAction' => '删除',
			'worktree.deleteBody' => ({required Object branch}) => '删除 ${branch} 的 worktree？',
			'worktree.deleteBranchToo' => '同时删除分支',
			'worktree.deleteBusyWarning' => '请先停止该 worktree 下正在运行的会话，再删除。',
			'worktree.deleteFailed' => ({required Object error}) => '删除 worktree 失败：${error}',
			'worktree.deleteForce' => '即使有未提交改动也强制删除',
			'worktree.deleteSessionsToo' => ({required Object count}) => '同时删除该 worktree 下的 ${count} 个会话',
			'worktree.deleteTitle' => '删除 worktree',
			'worktree.menuCopyPath' => '复制路径',
			'worktree.menuRemove' => '删除 worktree',
			'worktree.more' => '更多',
			'worktree.newConversationHere' => '在此新建会话',
			'worktree.newWorktreeTooltip' => '新建 worktree',
			'worktree.orphanGroup' => '其他',
			'worktree.pathLabel' => '位置',
			'worktree.randomNameTooltip' => '随机名称',
			'worktree.refreshTooltip' => '刷新 worktree 列表',
			'worktree.showLess' => '收起',
			'worktree.showMore' => ({required Object count}) => '显示更多 ${count} 个',
			_ => null,
		};
	}
}
