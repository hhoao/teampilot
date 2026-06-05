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
  String get rightToolsPanelVisible => '显示工具栏';

  @override
  String get rightToolsPanelHidden => '隐藏工具栏';

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
  String get typographyScaleTitle => '字号';

  @override
  String get typographyScaleDescription => '界面文字整体大小（菜单、列表、表单与终端）。';

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
  String get typographyScaleCustomHint => '75–135';

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
  String get appearancePageSubtitle => '界面外观与启动时打开的视图。';

  @override
  String get workspaceEntryModeTitle => '启动视图';

  @override
  String get workspaceEntryModeDescription => 'App 启动后默认打开的页面。';

  @override
  String get workspaceEntryModeHome => '主页';

  @override
  String get workspaceEntryModeHub => '工作区';

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
  String get gitStage => '暂存更改';

  @override
  String get gitUnstage => '取消暂存';

  @override
  String get gitStageAll => '暂存所有更改';

  @override
  String get gitUnstageAll => '取消暂存所有更改';

  @override
  String get gitDiscard => '放弃更改';

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
  String get memberPresenceOffline => '未连接';

  @override
  String get memberPresenceConnecting => '连接中…';

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
  String get homeWorkspaceMyTeams => '我的团队';

  @override
  String get homeWorkspaceNewTeam => '新建团队';

  @override
  String get homeWorkspaceProviders => '供应商';

  @override
  String get homeWorkspaceTeamProjects => '团队项目';

  @override
  String get homeWorkspaceOwner => '团队所有者';

  @override
  String get homeWorkspaceImportProject => '导入项目';

  @override
  String get homeWorkspaceSessionsLabel => '会话';

  @override
  String get homeWorkspaceEmptyProjects => '该团队还没有项目';

  @override
  String get homeWorkspaceEmptyProjectsHint => '新建或导入一个项目开始吧';

  @override
  String get homeWorkspaceComingSoon => '功能开发中';

  @override
  String get homeWorkspaceNewTeamSubtitle => '选择团队协作模式，并填写团队名称。';

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
  String get homeWorkspaceNewProjectSubtitle => '选择项目的工作目录，并为它命名。';

  @override
  String get homeWorkspaceNewProjectDirectoryLabel => '项目目录';

  @override
  String get homeWorkspaceNewProjectChooseDirectory => '选择文件夹';

  @override
  String get homeWorkspaceNewProjectDirectoryHint => '尚未选择目录';

  @override
  String get homeWorkspaceNewProjectNameHint => '默认使用文件夹名';

  @override
  String get homeWorkspaceCreateProject => '创建项目';

  @override
  String get homeWorkspaceCloseProjectTitle => '关闭项目？';

  @override
  String homeWorkspaceCloseProjectMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '关闭该标签会终止此项目中 $count 个运行中的会话。',
      one: '关闭该标签会终止此项目中 1 个运行中的会话。',
    );
    return '$_temp0';
  }

  @override
  String get homeWorkspaceCloseProjectConfirm => '关闭并终止会话';

  @override
  String get homeWorkspaceConversations => '对话管理';

  @override
  String get homeWorkspaceProjectSettings => '项目设置';

  @override
  String get homeWorkspaceProjectSettingsSectionBasic => '基本设置';

  @override
  String get homeWorkspaceProjectSettingsBasicInfo => '基本信息';

  @override
  String get homeWorkspaceProjectId => '项目 ID';

  @override
  String homeWorkspaceProjectAdditionalDirsCount(int count) {
    return '$count 个附加目录';
  }

  @override
  String get homeWorkspaceProjectSettingsPathsHint =>
      '在「附加目录」行点击编辑，可添加或移除工作区文件夹。';

  @override
  String get deleteProjectSubtitle => '将删除该项目及其下所有会话，且无法恢复。';

  @override
  String get homeWorkspaceInviteMembers => '邀请成员';

  @override
  String get homeWorkspaceNewConversation => '新建对话';

  @override
  String get homeWorkspaceNoConversations => '该项目还没有对话';

  @override
  String get homeWorkspaceSearchHint => '搜索';

  @override
  String get newProjectTooltip => '创建项目';

  @override
  String get switchProjectTooltip => '切换项目';

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
  String get sessionReadyTitle => '准备开始对话';

  @override
  String sessionReadySubtitle(String memberName) {
    return '与 $memberName 在此工作区开始对话';
  }

  @override
  String get sessionReadySubtitleGeneric => '在此工作区开始新对话';

  @override
  String get sessionReadyHint => '用日常语言描述你想做的事即可，无需输入命令。';

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
  String get terminalFind => '在终端中查找';

  @override
  String get terminalFindNoResults => '无匹配';

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
  String get editorCouldNotReadFile => '无法读取文件';

  @override
  String get editorFileReadOnly => '文件为只读';

  @override
  String editorSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get fileTreeRevealActiveFile => '定位当前文件';

  @override
  String get fileTreeRevealFailed => '无法在文件树中定位该文件';

  @override
  String get fileTreeOpenWithSystemApp => '用系统应用打开';

  @override
  String get fileTreeCopyPath => '复制路径';

  @override
  String get fileTreeDeleteItemTitle => '删除';

  @override
  String fileTreeDeleteItemConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get terminalOpenLink => '打开链接';

  @override
  String get terminalExportScrollback => '导出滚动缓冲…';

  @override
  String get terminalCopySelectHint => '按住 Shift 选择复制';

  @override
  String get workspaceTerminal => '终端';

  @override
  String get workspaceTerminalShow => '显示终端';

  @override
  String get workspaceTerminalHide => '隐藏终端';

  @override
  String get workspaceTerminalClose => '关闭终端面板';

  @override
  String get workspaceTerminalNoWorkingDirectory => '请先连接会话以打开 Shell 终端';

  @override
  String get workspaceTerminalNewSession => '新建终端';

  @override
  String get workspaceTerminalCloseSession => '关闭终端';

  @override
  String get terminalScrollbackLinesTitle => '终端滚动缓冲行数';

  @override
  String get terminalScrollbackLinesDescription => '每个会话终端保留的最大行数';

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
  String get claudeOfficialCredentialsAuthenticated => '已认证';

  @override
  String get claudeOfficialCredentialsUnauthenticated => '未认证';

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
  String teamHubClonePartial(Object name, Object count) {
    return '已克隆「$name」；有 $count 个依赖未能自动安装。';
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
  String teamMcpAssignedCount(int assigned, int total) {
    return '已启用 $assigned/$total';
  }

  @override
  String get teamMcpManage => '管理 MCP';

  @override
  String get mcpNavTitle => 'MCP 服务器';

  @override
  String get mcpSubtitle => '为 Claude 与 FlashskyAI 会话管理 MCP 服务器配置。';

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
  String get memberLaunchOrder => '成员启动顺序';

  @override
  String get saveMember => '保存成员';

  @override
  String get editTeamSubtitle => '编辑团队标识、工作目录和启动顺序。';

  @override
  String get memberName => '成员名称';

  @override
  String get memberNameSubtitle => '仅作界面展示用。若要指明职责与边界，请编辑下方的提示词。';

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
  String get agentBuiltInSubtitle => '指定该成员以哪种 Agent 身份协作，影响其行为与可用能力。';

  @override
  String get agentCustomIdHint => '自定义 Agent 标识';

  @override
  String get memberExtraArgs => '成员额外 CLI 参数';

  @override
  String get memberExtraArgsSubtitle => '仅附加在该成员的 CLI 启动参数。';

  @override
  String get memberDangerouslySkipPermissions => '跳过所有权限检查';

  @override
  String get memberDangerouslySkipPermissionsHint => '仅限隔离或无网络沙箱使用，否则风险极高。';

  @override
  String get prompt => '提示词';

  @override
  String get memberPromptSubtitle => '简要写明职责边界与角色备注，方便队长识别分工。';

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
      '只在约定范围内实现分配的任务。\n优先小 diff，跑相关测试，并简要说明改了哪些文件及原因。';

  @override
  String get memberPromptPresetReviewer => '审查';

  @override
  String get memberPromptPresetReviewerText =>
      '只做代码审查，除非被要求否则不要改文件。\n每条意见需包含：文件路径、行号、问题、建议改法。';

  @override
  String get memberPromptPresetResearcher => '调研';

  @override
  String get memberPromptPresetResearcherText =>
      '只调研并汇报，除非被要求否则不要改生产代码。\n输出需含文件路径、相关符号与建议的下一步。';

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
  String get appProviderToolOpencode => 'OpenCode';

  @override
  String get appProviderTeamToolSection => '团队默认服务商';

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
  String get aboutGitHub => 'GitHub';

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
