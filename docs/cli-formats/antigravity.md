# Antigravity CLI（`agy`，ACP-only）格式参考

**日期:** 2026-11-02
**来源:** 设计 [2026-10-28-antigravity-acp-cli-design](../superpowers/specs/2026-10-28-antigravity-acp-cli-design.md)、
代码 `client/lib/services/cli/antigravity/**`、`client/lib/services/acp/**`、
ACP 探针（adapter `1.4.3`）。

> 与 [claude.md](claude.md)/[cursor.md](cursor.md) 家族的根本差异：TeamPilot **不启动 PTY**，
> 也不解析 CLI 原生 transcript。所有聊天、权限、状态、历史回放与用量都走**应用自有 ACP 栈**
> （`AcpSessionRuntime` + `acp-transcript.jsonl` + `acp-usage.jsonl`）。

## 1. 启动形态（ACP-only）

| 项目 | 值 |
|---|---|
| `CliTransportCapability` | `supported: {acp}`（`launchesAcpOnly == true`） |
| ACP 可执行文件 | 独立 adapter `agy_acp_server.par`（Windows `agy_acp_server.exe`），不是 `agy` 本身 |
| adapter 安装 | 置顶版本 `1.4.3`，`<appData>/toolchain/antigravity-acp/1.4.3/`（sha256 校验 + 解压 + 原子移动） |
| `agy` 本体 | 仅用于安装/登录/`agy models`/headless 一次性运行；不参与聊天启动 |
| 无 PTY | 无终端渲染、无 `TerminalObservationContributor`、无 PTY 回退（`requiresPtyFallback = false`） |
| 原生团队 | 不支持（`supportsNativeTeam = false`）；仅 mixed 团队本地席位经 ACP 接入 |
| 平台 | Phase 1 桌面本地；Android / SSH 目标上的 ACP 明确拒绝 |

### argv / env

- `launchArgCandidates`：
  - macOS / Windows：`[[adapter]]`；
  - Linux：`[[adapter, '--uid='], [adapter]]`。`--uid` 是 google3 的**降权**开关（不是账号 id）；
    空值关闭开关，非空且组不存在会导致启动中止——代码永远只传空值。
- `buildEnvironment`：
  - `HOME` / `USERPROFILE` = `<sessionToolDir>/home`；
  - `GEMINI_HOME` = `<sessionToolDir>/home/.gemini`（指向 `.gemini` 本体，隔离强度高于 `HOME`）；
  - `AGY_ACP_DEFAULT_MODEL` = 选中模型 slug（非空时）；
  - API key 供应商：`GEMINI_API_KEY`、`GOOGLE_GEMINI_BASE_URL`（仅进程 env，不落盘）；
  - ADC：`AGY_ADC_AUTH=true`、`GOOGLE_CLOUD_PROJECT`、`GOOGLE_CLOUD_LOCATION`。
- `authenticateMethodId` 为 `null`：认证方式由 `~/.gemini/antigravity-acp/settings.json` 的
  `auth.type` 预置；`oauth-personal` **不能**走非交互 `authenticate`（会阻塞在浏览器流程）。
  缺失/无效认证时服务端返回 `-32000 Authentication required`，translator 映射为
  `acpStopAuthRequired`。
- `startupTimeout = 120s`（覆盖 PyInstaller 解包 + `session/new`）；`session/new` 不转发
  MCP（`forwardSessionNewMcpServers = false`），MCP 走 `mcp_config.json`。

## 2. 配置路径

### 会话内 fake HOME（`<sessionToolDir>/home`）

| 面 | 路径 |
|---|---|
| CLI 设置 | `<home>/.gemini/antigravity-cli/settings.json`（`model`、API-key 行的 `modelProvider: gemini`） |
| ACP 设置 | `<home>/.gemini/antigravity-acp/settings.json`（`auth.type`） |
| 资源根（`sessionConfigDir`） | `<home>/.gemini/config` |
| Skills | `<configDir>/skills/` |
| MCP | `<configDir>/mcp_config.json`（`{"mcpServers": …}`，merge 保留未知键） |
| Hooks | `<configDir>/hooks.json` |
| Plugins | `<configDir>/plugins/<name>/`（`plugin.json` 投影） |
| Rules / 提示词 | `<configDir>/rules/teampilot.md` |

### 用户真实目录（只读参考）

- `~/.gemini/config/*`：`hooks.json`、`mcp_config.json`、`skills/`、`rules/`；
- `~/.gemini/antigravity-cli/*`：`settings.json`、`skills/`，以及 Phase 2 的
  `brain/<conversation-id>/.system_generated/logs/transcript.jsonl`；
- `~/.gemini/antigravity-acp/settings.json`：ACP 认证类型；
- `antigravity-acp`：app-data 中的 adapter 安装目录名（`toolchain/antigravity-acp/<version>/`）。

TeamPilot 会话不写真实 `~/.gemini`：ACP / headless / `materializeSessionHome` 都注入
隔离的 `HOME` / `GEMINI_HOME`。

## 3. Transcript / 历史

- **Phase 1**：`AntigravityAiHistoryCapability` 是 stub——`locate => null`、adapter 解析为空；
  历史来自应用自有 `acp-transcript.jsonl`（ACP `session/load` 回放视为权威，不重复落盘）。
- `sessionEnv(toolRoot)`：由 `<configDir>` 反推 `HOME`/`USERPROFILE`（祖父目录）与
  `GEMINI_HOME`（父目录）。
- `tailFallbackPrefix = 'antigravity'`；`binding = postCaptured`；无 line append / page reader。
- **Phase 2**（未实现）：解析 `brain/<id>/…/transcript.jsonl`（`step_index` / `source` /
  `type` / `status` / `content` / `tool_calls`）。

## 4. 工具调用名与键

工具名来自 `agy` hook/tool payload（snake_case 工具名 + CamelCase 参数键）；共享
snake_case 别名仍然接受（兼容 ACP 回放与夹具）。解析器：
`AntigravityToolCallResolvers`（`capabilities/tool_call_resolvers.dart`）。

| 类别 | 工具名 | 关键参数键 | 备注 |
|---|---|---|---|
| Shell（command） | `run_command` + 共享 `bash` / `shell_command` / `exec_command` | `CommandLine` / `command` | 共享 shell resolver 名集 |
| Read（file） | `view_file` + 共享 read 名 | `AbsolutePath` / `path`；`StartLine`/`start_line`、`EndLine`/`end_line` | `view_file` 命中 read 规则（offset/limit 语义）；`list_dir`/`find_by_name`/`grep_search` 仅归类 read（无文件目标） |
| Write（file） | `write_to_file` + 共享 write 名 | `TargetFile`/`AbsolutePath`/`path`；`CodeContent`/`content` | `WriteEditHunkCodec` |
| Edit | `replace_file_content`、`multi_replace_file_content`、共享 edit/diff 名 | 路径：`TargetFile`/`AbsolutePath`/`path`；旧串：`TargetContent`/`old_string`；新串：`ReplacementContent`/`new_string` | `StrReplaceEditHunkCodec` + `UnifiedDiffEditHunkCodec` |
| Subagent | `invoke_subagent`、`send_message` | 由工具 result 合成（无 side resolver） | `subagentToolNames = {'invoke_subagent'}` |
| Task | `manage_task`、`schedule` | — | `AiToolCallCategory.task` |
| Ask user | `ask_question` | — | `AiToolCallCategory.askUser` |
| Search | `search_web`、`read_url_content` | — | `read_url_content` 归 search |
| Other | `generate_image` | — | 显式 `other` |

## 5. Hooks

`AntigravityHookWriter` 渲染 `<configDir>/hooks.json`，结构为「hook 名 → 原生事件 → 分组」：

```json
{
  "teampilot-<id>": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {"type": "command", "command": "<script>", "timeout": 10}
        ]
      }
    ]
  }
}
```

原生事件共 6 个；归一化映射（`HookEventCapability.matrix`）：

| 归一化事件 | Antigravity 原生事件 | 说明 |
|---|---|---|
| `sessionStart` | `SessionStart` | — |
| `userPromptSubmit` | `PreInvocation` | ≈ 近似语义（UI 标注） |
| `preToolUse` | `PreToolUse` | 支持 matcher；可携带 policy |
| `postToolUse` | `PostToolUse` | 支持 matcher |
| `stop` | `Stop` | — |
| — | `PostInvocation` | 无归一化对应事件；仅存在于原生契约，writer 永不发射 |
| `sessionEnd` / `postToolUseFailure` / `permissionRequest` / `subagentStop` / `preCompact` / `notification` / `shellCommandRequest` | 不支持 | 渲染时告警 `hook_unsupported_event_<id>_<event>` |

- 决策 JSON：`{"decision":"allow"}` / `{"decision":"deny","reason":"TeamPilot hook policy"}`；
  非拦截事件的 policy 被忽略并告警（`hook_policy_ignored_<id>_<event>`）。
- matcher 仅在 `PreToolUse` / `PostToolUse` 生效；其余事件原样写出但被 CLI 忽略，并告警
  `hook_matcher_ignored_<id>_<event>`。
- **HTTP hook 与原生插件 hook 不支持**：分别告警 `hook_http_unsupported_<id>`、
  `hook_native_plugin_unsupported_<id>` 后跳过（不静默丢弃）。
- 复用 `GlueScriptBuilder`：stdin 透传、env 合并、stdout 透传、timeout（默认 10s）。

## 6. 用量（usage）

### ACP（已实现）

- ACP `usage_update` → `AcpUsageUpdate` → 每个 turn 追加一行到
  `<sessionToolDir>/acp-usage.jsonl`（`AcpChatTranscriptWriter.appendUsage`，与消息写入同一串行队列）。
- 记录字段：`sessionId`、`used`、`size`、`sequence`（微秒时间戳，append 时铸造）、可选
  `model` / `cost`。
- `AntigravitySessionUsageCapability.scanUsageSource`：`used` → 输入/上下文 token
  （`inputSemantics = total`），`outputTokens` / `cache*` 恒 0，`size` 只保留在 JSONL 中
  （`SessionUsageEvent` 无上下文字段），不合成 cost；`used == 0` 的 `session/new` 空样本跳过。
- 回放（`session/load` history reconciliation）不重复追加 usage 样本。
- 只对 Antigravity 接线；CodeBuddy/Gemini 仍走各自原生扫描器，避免双计。

### Headless（未接入收集）

`agy -p --output-format stream-json` 的 `{"event":"result","result":{…}}` 里带 `usage`；
Phase 1 只用它取 `result.response` 文本，**尚不落盘/汇总**。

## 7. 已知限制

| 限制 | 影响 | 现状 |
|---|---|---|
| 冷启动 | adapter 是 PyInstaller onefile，每次 spawn 解包（Linux 约 1.8 GB 到临时目录），首个 prompt 前约 12–25s | ACP 启动超时 120s，UI 显示 “Starting Antigravity” |
| Linux `--uid=` | 非空值要求存在同名组，否则启动中止；该 flag 是降权而非账号 | 只传 `--uid=`（空）并在失败时回退无 flag 候选 |
| `localharness_external` | 必须与 `agy_acp_server` 同目录；缺失时每个 `session/new` 都返回 `-32603 Could not find default localharness binary` | 安装器把 sidecar 一并解压 + `chmod 755` |
| Linux arm64 | 某些内核报 TCMalloc 崩溃 | 暴露 stderr + 建议规避，不静默重试 |
| 模型绑定 | 旧构建忽略 `session/new` 的 model/mode 元数据 | spawn 前用 `AGY_ACP_DEFAULT_MODEL`；运行中用 `session/set_config_option` |
| 账号隔离 | token 在 OS keyring，进程级共享 | 多个 official 行共享同一 Google 账号；按 provider 隔离留待后续 |
| Headless 凭证供给 | 隔离 HOME 不物化 API key / ADC 配置 | 已显式记录的能力缺口（OAuth 依赖 keyring；key/ADC 需调用方自带 env） |
| adapter 版本 | ACP release 滞后 `agy` | 置顶 `1.4.3`；不从 registry 静默升级 |
| 平台面 | Android / SSH ACP 不支持 | Phase 1 仅桌面本地；远程安装返回结构化失败 |
| Phase 2 历史 | 不解析 `brain/.../transcript.jsonl` | 历史以 ACP transcript 为准 |

## 8. 验证

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/cli/antigravity test/services/cli/registry \
  test/services/chat/launch/session
```

真实 adapter 冒烟（缺失或未登录自动 skip）：

```bash
dart run tool/run_tests.dart --tags integration \
  test/integration/antigravity_acp_local_smoke_test.dart
```
