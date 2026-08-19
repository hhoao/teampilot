# Hooks 格式参考（用户可配置 hooks 的统一物化管线）

**日期:** 2026-08-14
**设计:** [docs/superpowers/specs/2026-08-13-hook-management-design.md](../superpowers/specs/2026-08-13-hook-management-design.md)
**代码:** 归一化模型 `client/lib/models/{hook_entry,hook_definition,hook_event}.dart`；能力接口
`client/lib/services/cli/registry/capabilities/hook_writer_capability.dart`；每 CLI writer
`services/cli/registry/config_profile/claude_family_hook_writer.dart`（claude/flashskyai 共用）、
`services/cli/codex/provider/codex_hook_writer.dart`、`services/cli/cursor/provider/cursor_hook_writer.dart`、
`services/cli/opencode/capabilities/opencode_hook_writer.dart`；胶水 `services/hook/glue_script_builder.dart`；
来源组装 `services/cli/registry/config_profile/hook_seat_context_completer.dart`；库解析
`services/hook/{hook_repository,hook_library_resolver}.dart`

> 用户可配置 hooks（运行时机事件 → 命令/脚本的规则，按 team > expert > workspace 启用，随
> session 启动物化到各 CLI 原生配置）。内部托管 hooks（agent-status、team-bus idle、
> team-lead delegate、扩展 settings-hook、插件 `hooks/hooks.json`）经同一管线收敛渲染——
> 本页的格式契约对**所有来源**统一生效。UI 编辑与启用见 `/hooks` 全局库。

## 1. 归一化事件目录（13 事件 × 5 CLI 支持矩阵）

`HookEvent`（`models/hook_event.dart`）为唯一事实源：writer 与 UI 能力矩阵共用
`HookEventCapability.matrix`，`≈` = 近似语义（UI 矩阵以 tooltip 如实标注）。

| 归一化事件 | claude | flashskyai | codex | cursor | opencode（plugin 桥） |
|---|---|---|---|---|---|
| `sessionStart` | `SessionStart` | `SessionStart` | `SessionStart` | `sessionStart` | – |
| `sessionEnd` | `SessionEnd` | `SessionEnd` | `SessionEnd` | `sessionEnd` | – |
| `userPromptSubmit` | `UserPromptSubmit` | `UserPromptSubmit` | `UserPromptSubmit` | `beforeSubmitPrompt` | `chat.message`（≈） |
| `preToolUse` | `PreToolUse` | `PreToolUse` | `PreToolUse` | `preToolUse` | `tool.execute.before`（≈） |
| `postToolUse` | `PostToolUse` | `PostToolUse` | `PostToolUse` | `postToolUse` | `tool.execute.after`（≈） |
| `postToolUseFailure` | `PostToolUseFailure` | `PostToolUseFailure` | `PostToolUseFailure` | `postToolUseFailure` | – |
| `permissionRequest` | `PermissionRequest` | `PermissionRequest` | `PermissionRequest` | – | `permission.asked`（≈） |
| `stop` | `Stop` | `Stop` | `Stop` | `stop` | `session.idle`（≈） |
| `stopFailure` | `StopFailure` | `StopFailure` | `StopFailure` | – | – |
| `subagentStop` | `SubagentStop` | `SubagentStop` | `SubagentStop` | `subagentStop` | – |
| `preCompact` | `PreCompact` | `PreCompact` | `PreCompact` | `preCompact` | – |
| `notification` | `Notification` | `Notification` | `Notification` | – | – |
| `shellCommandRequest` | – | – | `ShellCommandRequest` | `beforeShellExecution`（≈） | – |

- **拦截类事件**（可携带静态决策 policy）：`preToolUse` / `permissionRequest` / `shellCommandRequest`
  （`HookEvent.isIntercepting`）；其余事件 policy 必须为 `none`（UI 校验 + writer 侧
  `hook_policy_ignored_<id>_<event>` 警告兜底）。
- **matcher**（工具名/命令正则）：claude/flashskyai/codex/cursor ✓；opencode 桥仅
  `tool.execute.before/after` 按 tool 键限定，其余事件上的 matcher 忽略并警告
  （`hook_matcher_ignored_<id>_<event>`）。
- **http action**：claude/flashskyai/codex 原生 http hook ✓；cursor 渲染为 bash curl 转发脚本
  （`teampilot-http-<id>-<event>.sh`，见 §3 末注）；opencode 不支持（`hook_http_unsupported_<id>` 警告跳过）。
- **policy**：claude/flashskyai/codex flat `permissionDecision`；cursor `permission` + exit 2；
  opencode 桥 `decision`（≈，见 §2）。

### 1.1 Cursor 官方 docs 全集（已修正，官方 https://cursor.com/docs/hooks）

agent hooks 全集为：`sessionStart` / `sessionEnd` / `preToolUse` / `postToolUse` /
`postToolUseFailure` / `subagentStart` / `subagentStop` / `beforeShellExecution` /
`afterShellExecution` / `beforeMCPExecution` / `afterMCPExecution` / `beforeReadFile` /
`afterFileEdit` / `beforeSubmitPrompt` / `preCompact` / `stop` / `afterAgentResponse` /
`afterAgentThought`。另有 Tab hooks 与 `workspaceOpen`（均不在归一化目录内）；cloud agent
不跑用户级 hooks，本地 cursor-agent 不受影响。归一化目录只取其中的 10 个（含
`beforeShellExecution` ≈ `shellCommandRequest`）；`subagentStart`、`afterShellExecution`、
`before/afterMCPExecution`、`beforeReadFile`、`afterFileEdit`、`afterAgentResponse`、
`afterAgentThought` 未纳入。

## 2. 决策 JSON 契约（拦截类事件 + policy）

粘合脚本在用户命令 **stdout 为空**且 policy ≠ none 时输出 writer 提供的决策 JSON（exit 0）；
stdout 非空则原样透传（假定已是该 CLI 响应格式，CLI 按原生语义解释）。

| CLI | 决策 JSON | 说明 |
|---|---|---|
| claude / flashskyai | `{"permissionDecision":"allow"}` / `{"permissionDecision":"deny","permissionDecisionReason":"TeamPilot hook policy"}` | flat，无嵌套；timeout 缺省 5s（settings.json `timeout` 秒） |
| codex | 同上（flat `permissionDecision`） | `[[hooks.<Event>]]` 的 `timeout` 缺省 5s |
| cursor | `{"permission":"allow"}` / `{"permission":"deny","user_message":"TeamPilot hook policy"}` | **exit code 2 = 阻塞**（胶水 `exit 2` 承担）；默认 fail-open（无输出 / 非 0、非 2 退出按原生默认处理） |
| opencode（桥） | `{"decision":"allow"}` / `{"decision":"deny","reason":"TeamPilot hook policy"}` | ≈：插件内 `tool.execute.before` 对 `decision:"deny"` 抛错阻断工具调用；`event` 订阅将 stdout 原样 JSON.parse 回传——**运行时行为以 opencode 实际实现验证为准，验证待 release** |

- deny reason 文案来自各 writer 的 `denyReason` 构造参数（默认 `'TeamPilot hook policy'`）。
- `blockOnDecision`（内部 idle 语义，用户库 UI 不暴露）：粘合脚本末尾 `exit 2`。

## 3. 粘合脚本契约（GlueScriptBuilder，bash / powershell 双方言）

所有 command 类用户 hook 的原始命令被包进生成的 `teampilot-hook-<id>-<event>.sh`（cursor /
opencode 恒 bash；claude 家族按 `HostScriptRunner.dialect`，powershell 时 `.ps1`）。行为：

1. **stdin 透传**：hook payload JSON 由 CLI 经 stdin 注入，脚本 stdin 沿袭给用户命令
   （`bash` 方言经 `out="$(eval $inner 2>&1)"` 继承 stdin；用户脚本可直接 `cat` 读取 payload）；
2. **env 合并**：`hook.env` 逐键 export（powershell：`$env:KEY`）后跑用户命令；
3. **非空 stdout → 原样透传**（假定已是 CLI 响应格式）；**空 stdout 且 policy ≠ none →
   输出决策 JSON 并 exit 0**（见 §2）；空 stdout 且 policy = none → 无输出（CLI 原生默认处理）；
4. **exit code 透传**；`blockOnDecision` → 末尾追加 `exit 2`（cursor 阻塞语义 / idle 托管钩子）；
5. **timeout**：bash 方言 `timeout <t>s bash -c <quoted>` 包裹（null 时不加）；powershell 方言
   经 `cmd /c` 无 timeout；
6. 生成文件头注释 `# TeamPilot hook glue — do not edit.`，装配点覆写（内容不可手改）。

> cursor 的 http action 是特例（§1.1 之外）：渲染为 bash curl 转发脚本
> `teampilot-http-<id>-<event>.sh`——非阻塞（agent-status）恒 exit 0 best-effort POST；
> 阻塞（bus idle）POST 后响应含 `decision:block` 时输出 `followup_message`（与旧
> `CursorHomeAgentStatusOverlay` / `CursorHomeBusOverlay` 语义一致，Task 16 迁移）。

## 4. 配置落点（物化产物）

| CLI | 配置文件 | 脚本目录 | 去重/合并 |
|---|---|---|---|
| claude / flashskyai | session `settings.json` `hooks` map（`mergeHooksInto` 幂等并入） | `{sessionToolDir}/hooks/`（`teampilot-hook-<id>.sh`；托管脚本 `<id>/<fileName>`） | 按 `(event, url\|command)` 判重、append-if-absent——**保留首位（首次写入胜出）**，命中判重时 timeout/headers 不刷新 |
| codex | `CODEX_HOME/config.toml` `[[hooks.<Event>]]`（`matcher` 在数组级；`[[hooks.<Event>.hooks]]` 条目级 `type = "http"|"command"`、`command`、`timeout`） | `CODEX_HOME/hooks/` | managed（agent-status/bus）与用户 hook 同一次 `CodexHookWriter.render`，fragment 经 `CodexTomlMerge` 并入 config.toml |
| cursor | 成员 fake HOME `~/.cursor/hooks.json`（`{"version":1,"hooks":{<event>:[…]}}`，per-script `command` / `matcher` / `timeout` / `loop_limit`；`stop` 恒 `loop_limit: null`） | `~/.cursor/hooks/` | `mergeCursorHooksConfig` 按 `(event, command)` 去重，保留 agent-status / bus 条目 |
| opencode | `<configDir>/opencode.json` `plugin` 数组追加 `./teampilot-user-hooks.js` | `<configDir>/hooks/` 胶水 + `<configDir>/teampilot-user-hooks.js` | `mergeOpencodePluginEntries` 按路径去重；与 `teampilot-agent-status.js` / `teampilot-idle-bus.js` 平行共存（内部托管为 opencode 特有能力，不迁移进本 writer） |

**来源汇聚**（`HookSeatContextCompleter`，各 CLI config_profile 装配点调用一次统一 writer）：

| 来源 | 组装 | 说明 |
|---|---|---|
| 用户全局库 | `HookLibraryResolver.resolve(runtimeBundle.hookIds)` | `HookEntry(source: userLibrary)`；未知 id（库中已删）跳过 + `hook_missing_<id>` warning |
| agent-status | `completer.agentStatusHooks` | http action，事件集 `permissionRequest/preToolUse/postToolUse/postToolUseFailure/stop/stopFailure/userPromptSubmit`；`preToolUse` matcher `*` + timeout 86400（AskUserQuestion 挂起） |
| team-bus idle | `completer.busIdleHooks` | `stop`/`stopFailure` http，`blockOnDecision: true`，timeout 5 |
| team-lead delegate | `completer.delegateHooks` | `preToolUse` command，matcher = `TeamLeadDelegateSettingsMerge.blockedToolsMatcher` |
| 扩展 settings-hook | `completer.extensionHooks` | id `teampilot-extension-settings-hook-<extensionId>-<eventName>`（碰撞安全） |
| 插件 `hooks/hooks.json` | `completer.pluginHooks` | 事件名接受 camelCase 与 PascalCase 双拼写 |

## 5. 磁盘布局

```
<teampilotRoot>/hooks/{id}/hook.json                 # 全局库定义（HookDefinition）
<hookDir>/hook.sh | hook.ps1                         # 托管脚本（方言多文件，可选）

session 物化:
…/workspaces/{wid}/sessions/{sid}/runtime/{tool}/hooks/teampilot-hook-<id>.sh   # 胶水（command 类）
…/runtime/{tool}/hooks/<id>/hook.sh                  # 托管脚本副本（resolver 读库内容 → writer 落盘）
…/runtime/{memberId}/{tool}/…                       # mixed 团队按 member 分段
claude/flashskyai:  session settings.json  hooks map（并入）
codex:              CODEX_HOME/config.toml [[hooks.*]] + CODEX_HOME/hooks/teampilot-hook-*
cursor:             ~/.cursor/hooks.json（member fake HOME）+ ~/.cursor/hooks/teampilot-hook-<id>.sh
opencode:           <configDir>/teampilot-user-hooks.js + <configDir>/hooks/ + opencode.json plugin[]
```

- 托管脚本随 session 物化（manifest copy，SSH/Android 同管线，与 skills/plugin bundle 一致）；
- 远程机器上的 raw 命令字符串 hook 不做路径改写（命令在远端执行环境运行）；
- 脚本缺失（script action 文件不存在）→ 物化失败 + `hook_script_missing_*` warning，条目不写入。

## 6. 已知限制

| 项 | 说明 |
|---|---|
| opencode 事件缺失 | 无 `sessionStart` / `sessionEnd` / `postToolUseFailure` / `stopFailure` / `subagentStop` / `preCompact` / `notification` / `shellCommandRequest`（桥仅 5 个 ≈ 事件）；UI 矩阵标注 ✗ |
| cursor 事件缺失 | 无 `permissionRequest` / `stopFailure`（矩阵如实标注；旧行为一致，仅多一条 `hook_unsupported_event_*` 诊断警告） |
| opencode 桥 matcher | 仅 `tool.execute.*` 按 tool 键限定（JS plugin 内 `input.tool` 正则过滤）；其余事件 matcher 忽略并警告 |
| cursor agent-status 心跳 | 归一化事件集无 `afterAgentResponse` → agent-status working 信号少一个来源（增强信号丢失，等待信号依赖后续事件恢复）；Task 16 parity 表已记录 |
| flashskyai idle | bus idle 保持旧 exit-2 脚本通道（`flashskyai/capabilities/stop_idle_hook.dart`，**未迁移**统一 writer）——HookRunner 忽略 HTTP `decision:block`，仅 exit code 2 阻塞 |
| opencode 决策 JSON | `{"decision":…}` 契约为 ≈，插件侧行为（deny 抛错 / event 回传）以 opencode 实际实现验证为准，**运行时验证待 release** |
| cursor http | hooks.json 仅 command 类 → http action 走 bash curl 转发脚本（非阻塞恒 exit 0；阻塞响应含 `decision:block` 输出 followup_message） |
| policy 语义 | 非拦截事件上的 policy 被忽略并警告（writer `hook_policy_ignored_*`）；cursor 默认 fail-open |
| claude/flashskyai 默认 timeout | 胶水 command 条目 timeout 缺省 5s（`AskUserQuestion` PreToolUse 托管条目 86400s 保持挂起） |

## 7. 故障排查

| 症状 | 检查 |
|---|---|
| hook 未触发 / 条目缺失 | `hooks/` 物化目录与配置文件落点（§4/§5）是否含条目；运行日志 `[hook-writer] <cli> <warning>`（warning 键见下文）；未知 id → `hook_missing_<id>`（库中已删） |
| 决策未生效 | 确认事件是拦截类且 policy ≠ none；粘合脚本 stdout 为空时才会注入决策 JSON——用户命令有 stdout 会原样透传并被 CLI 按原生响应解释 |
| cursor 阻塞语义 | 胶水 `exit 2` 在 `blockOnDecision` 时追加；cursor 默认 fail-open |
| warning 键速查 | `hook_unsupported_event_<id>_<event>`（CLI 不支持事件）、`hook_http_unsupported_<id>`（opencode）、`hook_matcher_ignored_<id>_<event>`（opencode 非 tool 事件）、`hook_policy_ignored_<id>_<event>`、`hook_script_missing_<id>[_<fileName>]`、`hook_invalid_action_<id>`、`hook_missing_<id>` |

## 8. 导入既有 CLI hooks（JSON 粘贴）

把现有 CLI 的 hook 配置整体搬进 TeamPilot 全局库，避免逐个手建。入口：`/hooks` 全局库
「导入」→ `HookImportDialog`。代码：`client/lib/services/hook/import/`（`HookImportParser`
facade + `HookJsonDialect` 方言 + `HookScriptExtractor` 脚本提取）、
`client/lib/pages/hooks/hook_import_dialog.dart`、`HookImportService`（落库）。

### 8.1 支持 CLI 与输入格式

| CLI | 输入 JSON | 方言 |
|---|---|---|
| claude / flashskyai | `settings.json` 的 `hooks` map（`{"hooks":{"<Event>":[{"matcher","hooks":[…]}]}}`），或只贴 `hooks` 段本身 | `ClaudeFamilyHooksJsonDialect`（分组内核） |
| codex | `~/.codex/hooks.json`（分组结构，顶层允许 `description`） | `CodexHooksJsonDialect`（同一分组内核） |
| cursor | `~/.cursor/hooks.json`（`{"version":1,"hooks":{<event>:[扁平条目]}}`，matcher 在条目上） | `CursorHooksJsonDialect`（扁平适配） |

opencode 无 JSON 导入（其 hook 为 JS 插件桥，配置走 opencode.json，不在导入范围）。

### 8.2 流程：CLI 选择 + JSON 粘贴 → 预览勾选 → 导入

1. **输入阶段**：选目标 CLI（claude/flashskyai/codex/cursor），粘贴完整文件或只贴 hooks
   片段，点「解析」；
2. **预览阶段**：每条解析出的 hook 一行（原生事件名 · matcher + action 摘要），默认全选，
   可勾选要导入的条目；解析 warning 在预览上方展示；
3. 解析失败（JSON 非法 / 无可导入条目）停留在输入阶段并展示原始 warning 行
   （如 `hook_import_invalid_json: <message>` / `hook_import_no_hooks`）；
4. **导入**：`HookImportService.import` 按确定性 id 幂等 upsert（重复导入覆盖），脚本
   内容写入 `hooks/{id}/{fileName}`。

### 8.3 脚本复制进库 + 命令重写

command 类条目经 `HookScriptExtractor` 启发式识别脚本引用：

- 首 token 是解释器（`bash`/`sh`/`zsh`/`python3`/`python`/`node`/`powershell`/`pwsh`/
  `ruby`/`perl`）且含路径参数，或首 token 本身是路径 → 读取脚本内容进库
  （`hooks/{id}/{fileName}`，`fileName` 为原文件名），命令重写为
  `<interpreter> <teampilotRoot>/hooks/<id>/<fileName>`；
- **降级 raw**：内联命令（无脚本路径）、`bash -c` 内联、路径含占位符
  （`${...}` / `$(...)` / `$VAR`，`~` 在无 host home 时也视为占位符）、读取失败 →
  保留原命令字符串，不复制脚本（`reason: placeholder` / `unreadable` 供预览标注）；
- http 条目不经提取，url/headers/timeout 直接入库。

### 8.4 字段旁路保留（`native`）

归一化模型只消费 `type/command/url/headers/matcher/timeout` 等已知字段；其余字段
（如 cursor 的 `loop_limit`/`failClosed`、各 CLI 的未来扩展字段）原样保留进
`HookDefinition.native`（零丢失旁路，writer/管线不消费），并在预览条目上以
`⚠ <field, …>` 标注"导入后不生效"（`HookImportDraft.unsupportedFields`）。

### 8.5 确定性幂等 id

每条目按 `event|matcher|command|url` 计算 **FNV-1a 64 位哈希**，id =
`import-<哈希十六进制前 12 位>`（`hookImportId`，`client/lib/services/hook/import/hook_import_parser.dart`）。
同一来源重复导入 → 同 id → upsert 覆盖，不产生重复条目；导入后再在 UI 修改定义
（id 不变）也不漂移。

**跨 CLI 去重是有意设计**：id 键基于**归一化**事件名（`HookEventNameMapper` 映射后），
因此 claude `PreToolUse` 与 cursor `preToolUse` 等不同 CLI 的同义事件，在
matcher/command 相同的情况下得到**同一个 id**——把同一条 hook 从多个 CLI 依次导入
会映射到同一条目（upsert 覆盖，而非新增重复）。预览阶段对已存在的 id 显示
「将覆盖」徽标（`hookImportOverwrite`，命中 `HookRepository.load` 非空），
导入前即可感知该条会覆盖库中现有条目。

### 8.6 事件映射与丢弃

- 原生事件名经 `HookEventNameMapper`（三张数据驱动表：claude-family PascalCase、
  codex、cursor camelCase）映射到归一化事件目录（§1 矩阵）；
- **不在目录内的事件**（如 `PostCompact`/`SubagentStart`/`afterAgentResponse`/
  `beforeReadFile` 等）→ `hook_import_event_unsupported_<name>` warning，**条目丢弃**；
- 其它 warning 键：`hook_import_invalid_json` / `hook_import_invalid_json_shape` /
  `hook_import_no_hooks` / `hook_import_bad_hooks_envelope` / `hook_import_bad_group_<event>` /
  `hook_import_bad_handler_<event>` / `hook_import_type_unsupported_<type>` /
  `hook_import_cli_unsupported_<cli>`。

验证基线：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings &&
dart run tool/run_tests.dart`（各 writer / glue / resolver / completer 单测：
`test/services/cli/{codex,cursor,opencode}/…hook_writer_test.dart`、
`test/services/cli/registry/config_profile/{claude_family_hook_writer,hook_seat_context_completer}_test.dart`、
`test/services/hook/`、`test/models/hook_{entry,event}_test.dart`；导入单测：
`test/services/hook/import/`、`test/pages/hooks/hook_import_dialog_test.dart`）。
