# 用户可配置 Hooks（全局库 + 按 scope 启用 + 统一物化管线）— 设计

日期：2026-08-13
状态：已评审（brainstorming 各节通过；用户委托定案：最优架构、不设工作量与兼容性约束）

## 1. Context

用户需要一个「hook 功能，类似于 skills、mcp、插件管理」：让用户定义**运行时机事件 → 执行命令/脚本**的规则，并按 scope（team > expert > workspace）启用，随 session 启动物化到各 CLI 的原生配置。与内部已有的"托管 hook"（agent-status HTTP hooks、team-bus Stop/StopFailure、team-lead delegate、扩展 settings-hook、插件 `hooks/hooks.json`）不同，这是**用户可配置、可管理**的 hook。

### 现状痛点

各 CLI 的 hook 写入链是**六条各自为政的 merge 路径**，且每个 CLI 的事件模型/配置格式不同：

| CLI | hooks 机制 | 现有写入点 |
|-----|-----------|-----------|
| claude / flashskyai | settings.json `hooks` map（http + command 两类） | `mergeAgentStatusHooks`、`mergeStopIdleHook`、`ClaudeFamilyHookRegistry.render` + `mergeHooksInto`、`maybeApplyTeamLeadHooks`、`SettingsHookEffectApplier` |
| codex | config.toml `[[hooks.<Event>]]` + `CODEX_HOME/hooks/` 脚本 | `CodexAgentStatusOverlay` / `CodexTeamBusOverlay`（`CodexCommandHookProvisioner`） |
| cursor | `~/.cursor/hooks.json`（`{"version":1,"hooks":{<event>:[...]}}`，command 类，无 matcher） | `CursorHomeAgentStatusOverlay.mergeHooksConfig` / `CursorHomeBusOverlay` |
| opencode | 无原生 hooks；经生成的 JS plugin（SDK 事件订阅）注册进 `opencode.json` `plugin` 数组 | `agent_status_plugin.dart` / `idle_plugin.dart` |

代码库已有明确的收敛基础：`CliHookSpec`（归一化 hook 声明，`hook_registry.dart`）、`CliAssetRegistry`（`AssetKind.hooks` 已存在）、`ClaudeFamilyHookRegistry`（claude/flashskyai 的 settings.json 渲染器）。

### 目标（brainstorming 确认）

1. 用户定义 hook：**事件（生命周期 + 工具拦截都要）→ 命令字符串或托管脚本**，支持 matcher、policy（静态决策）、timeout、env。
2. **全局库** 管理 hook 定义，**按 scope 启用**（复用 `ConfigBundle` enable-list 模式）。
3. 覆盖**全部五个 CLI**，按各 CLI 能力映射（opencode 经生成 plugin 桥接；不支持的事件如实标注）。
4. 拦截类 hook 的静态决策：**粘合脚本包命令**，空输出 → writer 写决策 JSON；有输出 → 透传。
5. 架构定案：**收敛为统一 hook 管线** —— 一个归一化模型，每个 CLI 一个 HookWriter，所有来源（用户库 / 插件 / 扩展 / 内部托管）走同一管线。内部托管 hooks 全量迁移，删除各自独立的 merge 函数。

**明确不在范围**：
- 聊天内卡片审批（AskUserQuestion/ExitPlanMode 那类 hook-gate 交互）—— hook 只是"运行命令 + 静态决策"。
- hooks 的 hub 发布/目录订阅（`TeamHub`/`ExpertHub` 那类 registry）—— 未来可加，模型不堵死。
- codex 专属 `ShellCommandRequest` 事件之外的 codex 专属事件枚举扩展。

## 2. 统一模型

### 2.1 归一化事件目录

`HookEvent`（sealed enum，claude 命名为规范）。各 CLI 支持矩阵（writer 层映射到原生事件名）：

| 归一化事件 | claude/flashskyai | codex | cursor | opencode(plugin 桥) |
|---|---|---|---|---|
| `sessionStart` | `SessionStart` | `SessionStart` | – | – |
| `sessionEnd` | `SessionEnd` | `SessionEnd` | – | – |
| `userPromptSubmit` | `UserPromptSubmit` | `UserPromptSubmit` | `beforeSubmitPrompt` | `chat.message`（≈） |
| `preToolUse` | `PreToolUse` | `PreToolUse` | `preToolUse` | `tool.execute.before`（≈） |
| `postToolUse` | `PostToolUse` | `PostToolUse` | `postToolUse` | `tool.execute.after`（≈） |
| `postToolUseFailure` | `PostToolUseFailure` | `PostToolUseFailure` | `postToolUseFailure` | – |
| `permissionRequest` | `PermissionRequest` | `PermissionRequest` | – | `permission.asked`（≈） |
| `stop` | `Stop` | `Stop` | `stop` | `session.idle`（≈） |
| `stopFailure` | `StopFailure` | `StopFailure` | – | – |
| `subagentStop` | `SubagentStop` | `SubagentStop` | – | – |
| `preCompact` | `PreCompact` | `PreCompact` | – | – |
| `notification` | `Notification` | `Notification` | – | – |
| `shellCommandRequest` | – | `ShellCommandRequest` | – | – |

- `≈` = 近似语义，UI 能力矩阵如实标注（tooltip：近似语义说明）。
- matcher 支持：claude/codex（工具名正则）；cursor **不支持 matcher**（writer 忽略并警告）；opencode 桥按 `tool.execute.*` 的 tool 键限定，其余事件 matcher 忽略并警告。

### 2.2 统一 HookEntry

```dart
@immutable
class HookEntry {
  final String id;                 // 身份键（用户库 id；内部源为稳定符号 id）
  final HookSource source;         // userLibrary | plugin | extension | managed
  final HookEvent event;
  final String? matcher;           // 工具名正则（事件支持才生效）
  final HookAction action;         // command | http
  final HookPolicy policy;         // none | allow | deny
  final Duration? timeout;
  final Map<String, String> env;
  final bool blockOnDecision;      // idle 语义（内部托管用）
}
```

- `HookAction.command`：`raw`（用户命令字符串）或 `script`（托管脚本引用 → 物化时解析为 session 内稳定路径 + 该机器方言）。
- `HookAction.http`：`url + headers`（claude/flashskyai/codex 原生支持 http 类 hook；cursor 的 hooks.json 仅 command 类、opencode 桥不支持，均忽略并警告）。
- `HookPolicy`：仅拦截类事件（`preToolUse` / `permissionRequest` / `shellCommandRequest`）有意义；非拦截事件 policy 必须为 `none`（UI 校验）。
- `blockOnDecision`：内部 idle 类钩子语义（末尾 `exit 2` = decision:block），用户库 UI 不暴露。

### 2.3 用户库模型（持久化）

```
<teampilotRoot>/hooks/{id}/hook.json
<hookDir>/hook.sh | hook.ps1        # 托管脚本（可选，方言多文件）
```

`HookDefinition`（`hook.json`）：`id / name / description / event / matcher / action（{type: raw|script, command|scriptFileName} 或 {type: http, url, headers}）/ policy / timeoutSec / env`。持久化 `fromJson/toJson` 值语义 `==/hashCode`（进 `ConfigBundle` 需值相等）。

`ConfigBundle` 新增 `hookIds`（空则 `toJson` 省略，同现有三个列表）。

## 3. 启用层

- `LayeredConfigBundle.merge` 增加 `hookIds` 维度：`team > expert > workspace` 按序覆盖（与 skillIds 同语义）。
- `WorkspaceProjectConfig.bundle.hookIds`、`TeamProfile/LaunchProfile ConfigBundle.hookIds` 持久化，随现有配置写入/读取自动生效（`toJson` 透传）。
- seat 物化时：`effectiveHookIds = runtimeBundle.hookIds`（已合并），由 `HookLibraryResolver` 加载对应 `HookDefinition` → 过滤出**该 CLI 支持的事件** → 解析 action（脚本路径解析、dialect 选择）→ 产出 `HookEntry(source: userLibrary)` 列表。未知 id（库中已删）跳过并记 warning。

## 4. 物化层：每 CLI 一个 HookWriter

### 4.1 能力接口

新 `client/lib/services/cli/registry/capabilities/hook_writer_capability.dart`：

```dart
abstract interface class HookWriterCapability implements CliCapability {
  /// 归一化事件 → 原生事件名映射；不支持的返回 null。
  String? nativeEvent(HookEvent event);

  /// 事件是否支持 matcher / http action / policy。
  HookEventSupport support(HookEvent event);

  /// 渲染：HookEntry 集 → 该 CLI 的配置文件片段 + 生成的脚本文件。
  /// 文件级输出（Map<relativePath, content>），不假设文件格式。
  HookWriteResult render(
    List<HookEntry> entries,
    HookRenderContext ctx,   // session 目录、HostScriptRunner、dialect
  );
}
```

`HookWriteResult = { Map<String, Object?> configFragments; List<GeneratedScript> scripts; List<String> warnings; }`。

**胶水脚本生成**（所有 command 类用户 hook 统一处理，`render` 内完成）：
1. 把用户命令包进生成的 `teampilot-hook-<id>-<event>.sh` / `.ps1`（按 `HostScriptRunner.dialect`）；
2. 粘合脚本：设置 env（合并 hook.env）→ 跑用户命令（`timeout` 限制）→ **空 stdout** → 输出 writer 提供的该 CLI 决策 JSON（policy 非 none 时）；**非空 stdout** → 原样透传（假定已是该 CLI 响应格式）；
3. policy 为 `none`：直接跑命令，粘合层不注入任何决策 JSON；用户命令的 stdout 原样透传（若 CLI 期望 hook 响应而命令无输出，CLI 按原生默认处理）。
4. `blockOnDecision` 内部钩子：命令末尾追加 `exit 2`。

### 4.2 各 CLI Writer

| CLI | Writer | 落点 |
|-----|--------|------|
| claude / flashskyai | 扩展现有 `ClaudeFamilyHookRegistry`（增补用户 HookEntry 渲染 + policy/glue 支持） | `mergeHooksInto(settings, rendered['settings.json'])`，沿用 `_writeMemberProfile` 现有链 |
| codex | 新 `CodexHookWriter`（复用 `CodexCommandHookProvisioner` TOML 片段 + 脚本） | config.toml 经 `CodexTomlMerge` 并入；脚本落 `CODEX_HOME/hooks/` |
| cursor | 新 `CursorHookWriter`（`{"version":1,"hooks":{...}}`，复用现有 merge 模式） | 成员 fake HOME `~/.cursor/hooks.json` |
| opencode | 新 `OpencodeHookWriter`（生成 JS plugin，复用 agent_status_plugin 的 SDK 订阅模式；policy 在 JS 胶水实现） | `<configDir>/teampilot-user-hooks.js` + `opencode.json` `plugin` 数组 |

### 4.3 收敛重构（定案：做全）

所有来源迁移为 `HookEntry`，删除各自独立的 merge 函数：

| 来源 | 现状 | 迁移后 |
|------|------|--------|
| 用户全局库 | 本次新建 | `HookLibraryResolver` → `HookEntry(source: userLibrary)` |
| agent-status HTTP hooks | `mergeAgentStatusHooks`（claude/flashskyai/codex/cursor/opencode 各自 overlay） | `HookEntry(source: managed, action: http, event: 各事件, matcher:'*')`，随 seat 上下文完成（endpoint/headers 注入） |
| team-bus idle | `mergeStopIdleHook` / `CodexTeamBusOverlay` / `CursorHomeBusOverlay` / opencode idle plugin | `HookEntry(source: managed, event: stop, blockOnDecision: true)` |
| team-lead delegate | `maybeApplyTeamLeadHooks`（`TeamLeadDelegateSettingsMerge`） | `HookEntry(source: managed, event: preToolUse, matcher: 'Bash\|Read\|...')` |
| 扩展 settings-hook | `SettingsHookEffectApplier` | `HookEntry(source: extension)` |
| 插件 `hooks/hooks.json` | `PluginHook`（`PluginManifestService._scanHooks`） | `HookEntry(source: plugin)` |

收敛后每个 CLI 的配置写入点只调自己的 HookWriter：claude `_writeMemberProfile`、flashskyai `_writeMemberProfile`、codex `CodexHomeProvisioner.provision`（composer 链）、cursor home provisioner、opencode config_profile。内部来源的 seat 上下文（endpoint、headers、memberId）在装配点注入（沿用 `completeBusIdleHooks` 的依赖反转模式，提升为通用 `HookSeatContextCompleter`）。

**合并纪律**（沿用现有 idempotent 语义，升级为统一规则）：
- 身份键 `(event, nativeCommand|url)`；重复不追加，更新（timeout/headers）刷新。
- 用户 hook 脚本路径 = session 内稳定路径，天然幂等。
- 各 writer 的 `render` 是纯函数，输出文件级 fragment，由调用方 merge。

## 5. 全局库 UI

### 5.1 路由与页面

- 新路由 `/hooks`（全局库）：`pages/hooks/hook_management_page.dart`（列表 + 编辑表单 + 能力矩阵），平行于 `pages/mcp/mcp_management_page.dart`。
- `home_workspace_shell.dart` 的 `?global=` 视图加入 `hooks`（如现有 `skills`/`plugins`/`mcp` 模式）。
- workspace manage：`WorkspaceConfigSection` 新增 `hooks` 枚举项（routeSegment `hooks`，icon `Icons.bolt_outlined` 之类），section 页平行 `pages/skills/` 现有结构。
- team-config：新 `team_config_hooks_section.dart`，平行 `team_config_mcp_section.dart`（启用勾选 + 「管理全局」跳转）。

### 5.2 编辑器表单（`HookEditorPage` / dialog）

- 基础：name、description、event（下拉，选项带该事件支持矩阵徽标；事件切换时校验 policy/matcher 合法性）、matcher（仅拦截类事件显示）。
- Action：radio `命令字符串` / `托管脚本`（脚本编辑器，方言 tab `hook.sh` / `hook.ps1`；http 预留不上 UI）。
- Policy：`none` / `allow` / `deny`（仅拦截类事件）。
- timeout（秒）、env（键值对编辑）。
- 能力矩阵展示（只读）：每 CLI × 该 hook 事件的支持状态（✓ / ✗ / ≈ 近似），随 event 联动。

### 5.3 Cubit / Repository

- `HookRepository`：CRUD，目录 `hooks/{id}/`，读写 `hook.json` + 脚本文件（`Filesystem` 注入）。
- `HookCubit`：库列表状态，增删改后广播；提供 `effectiveForCli(cli, event)` 查询（UI 矩阵用）。

### 5.4 l10n

`app_en.arb` / `app_zh.arb` 新增 hooks 全部文案（页面标题、字段、矩阵、警告）。

## 6. 磁盘布局汇总

```
<teampilotRoot>/hooks/{id}/hook.json
<hookDir>/hook.sh | hook.ps1
session runtime: .../sessions/{sid}/runtime/hooks/{id}/{hook.sh|hook.ps1}   # 物化副本，路径稳定
claude/flashskyai:  session settings.json  hooks map（并入）
codex:              CODEX_HOME/config.toml [[hooks.*]] + CODEX_HOME/hooks/teampilot-hook-*
cursor:             ~/.cursor/hooks.json（member fake HOME）
opencode:           <configDir>/teampilot-user-hooks.js + opencode.json plugin[]
```

托管脚本随 session 物化（manifest copy，SSH/Android 同管线，与 skills/plugin bundle 一致）。远程机器上的原生命令字符串 hook（raw action）不做路径改写——命令在远端执行环境运行。

## 7. 错误处理与测试

- **未知 hookId / 库删除**：物化时跳过 + warning 进 `warnings`（沿 `ConfigProfileLaunchContribution.warnings` / `applySimpleSessionFilesystem` warnings 通道）。
- **不支持的事件 / matcher / http**：writer 产出 warning，UI 矩阵同步标注。
- **脚本缺失（script action 引用的文件不存在）**：物化失败 → warning，hook 条目不写入（避免 CLI 起 hook 报错）。
- **toml/JSON 校验**：codex fragment 沿用 `_generator.validateCodexToml` 校验路径。
- **测试**：
  - `HookDefinition` fromJson/toJson + 值语义（`client/test/models/`）。
  - `LayeredConfigBundle.merge` hookIds 分层（现有 bundle 测试扩展）。
  - `HookLibraryResolver`：id 过滤、事件过滤、action 解析、未知 id warning。
  - 各 Writer 单测：claude settings.json 合并幂等（含与 agent-status 共存）、codex TOML 片段、cursor hooks.json、opencode JS plugin + plugin 数组合并。
  - glue 脚本生成：policy 空输出 → 决策 JSON；非空输出 → 透传；timeout；方言。
  - 收敛迁移：agent-status/delegate/扩展/插件来源 → HookEntry 的映射单测（迁移后各来源的既有测试改道到统一 writer 断言）。

## 8. 不在范围（明确）

- 聊天内卡片审批 / hook-gate 交互。
- hub 发布与订阅目录。
- `ShellCommandRequest` 之外的新事件枚举扩展（目录可加，writer 矩阵随动）。
