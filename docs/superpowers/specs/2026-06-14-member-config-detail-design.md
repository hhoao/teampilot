# 成员配置详情（右键菜单 + 真实配置目录）设计

- 日期：2026-06-14
- 状态：已批准设计，待实现计划

## 背景与目标

项目页右侧工具面板的成员列表（[members_panel.dart](../../../client/lib/widgets/right_tools/members_panel.dart)）当前每个成员行仅支持左键点击打开/连接会话，没有右键菜单。

目标：为每个成员行增加右键（`onSecondaryTapDown`）/ 长按菜单，包含四项操作；其中"查看成员详情"打开一个**只读**弹窗对话框，内容来自该成员**真实的 CLI 配置目录**（CONFIG_DIR），结构化展示其配置、Skills、MCP、插件等信息。

## 已确认的需求决策

| 决策点 | 结论 |
|--------|------|
| 数据来源 | **运行目录优先，回退到团队层**：若该成员已在当前选中会话中启动过，读取其 member CONFIG_DIR；否则回退到团队层 `config-profiles/teams/{teamId}/{tool}/`（继承自 app 层）。两层都缺失时显示空状态。 |
| 呈现方式 | **弹窗对话框（Dialog）**，内部用标签页分区展示。 |
| 读写能力 | **只读** + 提供"在文件管理器中打开目录"入口。 |
| 右键菜单项 | 四项：查看成员详情 / 打开·连接成员会话 / 在文件管理器中打开配置目录 / 启动全部成员。 |
| 架构方案 | **统一服务 + 每 CLI 能力钩子**（新增 `MemberConfigInspectionCapability`），符合 registry/capability 架构，覆盖全部 5 个 CLI。 |
| "查看详情"启用条件 | 当项目存在活动会话标签（`chatCubit.activeTab != null`）时启用；否则禁用并提示"请先打开一个会话"。 |

## 范围

- 适用于**团队模式**项目（个人项目无成员列表，不在本次范围）。
- 覆盖全部 5 个 CLI（claude、flashskyai、codex、opencode、cursor）；以默认实现读取通用布局，按 CLI 差异在各自能力中覆盖。

## 架构总览

```
MembersPanel (成员行)
   │ onSecondaryTapDown / onLongPress
   ▼
showSidebarActionMenuFromSpecsAtTap  (复用现有 AppFlowy 风格菜单)
   菜单项: 查看详情 / 打开·连接会话 / 在文件管理器打开 / 启动全部
   │ (查看详情)
   ▼
MemberDetailDialog ◀── MemberConfigCubit ◀── MemberConfigInspector
                                                │ 解析目录 (运行→团队回退) + 读取
                                                ▼
   CliToolRegistry.capability<MemberConfigInspectionCapability>(memberCli)
```

## 组件设计

### MemberConfigInspector （服务）

- 位置：`client/lib/services/cli/member_config/member_config_inspector.dart`
- 输入：`team`、`member`、活动标签（`ChatTab`，提供 `cliTeamName` 与 `persistedSession`）、可选 `project`。
- 职责：
  1. 通过 `member.cliWithin(team)` 得到该成员的 tool。
  2. 解析 CONFIG_DIR：
     - 运行层（mixed）：`CliDataLayout.memberToolDir(teamId, mixedModeMemberScopeSessionId(cliTeamName, member), tool)`。
     - 运行层（native）：`CliDataLayout.memberToolDir(teamId, cliTeamName, tool)`。
     - 回退：`CliDataLayout.teamToolDir(teamId, tool)`。
  3. 判定来源层（`runtime` | `team` | `none`）：取第一个存在的目录；都不存在则 `none`。
  4. 调用该 CLI 的 `MemberConfigInspectionCapability.inspect(ctx)` 填充 `MemberConfigDetail`。
- 全部 I/O 经 `AppStorage.fs`，构造注入以便测试。

### MemberConfigInspectionCapability （能力接口）

- 位置：`client/lib/services/cli/registry/capabilities/member_config_inspection_capability.dart`
- 接口：`Future<MemberConfigDetail> inspect(MemberConfigContext ctx)`，其中 `MemberConfigContext` 携带已解析的 `configDir`、`sourceLayer`、`tool`、`fs`、`member`、`team`。
- 默认实现读取通用布局：
  - **Skills**：列出 `skills/` 下子目录（解析 `SKILL.md`/`skill.md` 名称与描述，缺失则用目录名）。
  - **插件**：复用 `pluginManifestPathsForTool(tool)`（回退 `claudePluginManifestPaths`）读取已安装插件 bundle 清单。
  - **MCP**：读取 MCP 快照（团队 `teamMcpServersFile` / 个人 `standaloneProjectMcpServersFile`）及 CLI CONFIG_DIR 内的覆盖（如有）。
  - **设置**：读取该 tool CONFIG_DIR 内的 settings/metadata json，扁平为键值对展示（敏感字段按需脱敏）。
- 各 CLI（opencode、cursor、codex 等）在其 `registry/tools/` 定义中注册子类，仅覆盖与默认布局不同之处（如 opencode 的 MCP 位于 `provider.options`、cursor 的 HOME 隔离布局）。

### MemberConfigDetail （模型）

```
MemberConfigDetail {
  String resolvedDir;
  MemberConfigSourceLayer sourceLayer;   // runtime | team | none
  CliTool cli;
  String provider;                       // 展示名
  String model;
  List<ConfigEntry> settings;            // 键值对
  List<SkillEntry> skills;               // 名称 + 描述 + 路径
  List<McpServerEntry> mcpServers;       // 名称 + 传输/命令摘要
  List<PluginEntry> plugins;             // 名称 + 版本/来源
  List<SectionWarning> warnings;         // 某分区读取失败时的告警
}
```

### MemberConfigCubit

- 位置：`client/lib/cubits/member_config_cubit.dart`
- 状态：`loading` / `loaded(MemberConfigDetail)` / `error`。
- 在打开对话框时触发异步加载，保证对话框 `build()` 内无 I/O。

### MemberDetailDialog

- 位置：`client/lib/pages/home_workspace/project/member_detail_dialog.dart`（路由内 UI 分区，遵循 `pages/<domain>/` 约定）。
- 标签页：**概览 / Skills / MCP / 插件 / 设置**。
  - 概览：CLI、Provider、Model、解析后的 CONFIG_DIR 路径；当来源层为 `team` 时显示"回退到团队层"提示横幅；为 `none` 时显示空状态。
  - 各列表页：分区读取失败显示告警 chip，不影响其它标签页。
- 底部：关闭 + "在文件管理器中打开目录"（远端文件系统下隐藏/禁用）。

### SystemFolderOpener （服务）

- 位置：`client/lib/services/io/system_folder_opener.dart`
- 将 [project_info_section.dart](../../../client/lib/pages/home_workspace/project/project_info_section.dart) 中现有的 `_openFolder`（`Process.run` 调 `open`/`start`/`xdg-open`）抽取为可注入服务，供菜单项与对话框底部复用，避免 UI 直接调用 `Process.run`。
- 仅桌面有效；远端（ssh）后端下隐藏/禁用。
- 顺带把 `project_info_section.dart` 的本地实现替换为调用该服务（小范围、与本任务直接相关的清理）。

## 数据流与菜单装配

- 菜单在 `MembersPanel` 内按行构建；四个 spec 的回调由 `RightToolsPanel`（已持有 `team`、`chatCubit`、`cwd`）传入，沿用现有 `onSelected` / `onLaunchAll` 注入风格。
- **"查看详情"启用 = `chatCubit.activeTab != null`**；无活动会话时禁用并提示"请先打开一个会话"。活动标签提供 `cliTeamName` + `persistedSession` 用于解析运行目录。
- "打开·连接会话" → 现有 `openMemberTab`。
- "启动全部" → 现有 `launchAllMembers`。
- "在文件管理器打开" → `SystemFolderOpener.reveal(resolvedDir)`；该项不依赖会话（无会话时走团队层回退）。

## 错误处理

- 各层 CONFIG_DIR 均缺失 → 对话框显示空状态（"该成员尚未在此会话中启动，且团队层无配置"），不视为错误。
- 某分区 json 损坏/不可读 → 该分区显示告警 chip，其它标签页仍正常渲染（分区级 try/catch，诊断写 `AppLogger`）。
- SSH/远端文件系统：经 `AppStorage.fs` 读取；"在文件管理器打开"仅桌面本地，远端后端下隐藏/禁用。

## 测试

- `MemberConfigInspector` 单元测试（注入临时/内存文件系统）：运行层存在、团队层回退、两层皆无；各 CLI 能力读取。
- `MemberConfigCubit` 测试（`setUpTestAppStorage` / `tearDownTestAppStorage`）：loading/loaded/error 状态。
- Widget 测试：右键打开菜单；无活动会话时"查看详情"禁用；对话框用伪造 detail 渲染各标签页。
- l10n 字符串仅改 `app_en.arb` 与 `app_zh.arb`，随后 `dart run tool/gen_warmup_glyphs.dart` 刷新 warmup glyphs。

## 约定与影响面

- 遵循 registry/capability 架构，不在各处散布 `if (cli == …)`。
- UI 不直接 `Process.run`、不用裸路径；路径经 `CliDataLayout` / `AppStorage`。
- 文件大小软上限：对话框若超出，按 `pages/<domain>/` 拆分分区文件。
- 状态一律 `flutter_bloc`。

## 非目标（YAGNI）

- 不在详情弹窗内编辑/管理配置（只读）。
- 不覆盖个人项目（无成员列表）。
- 不新增独立路由页面。
