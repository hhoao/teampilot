# Cursor 消息与工具调用格式参考

**日期:** 2026-08-12
**来源:** 夹具 `client/test/fixtures/session_history/cursor/{agent_transcript_no_tool_id.jsonl,chats/…/meta.json,projects/home-me-proj/agent-transcripts/chat-aaaa-bbbb-cccc-dddd/….jsonl,projects/home-me-proj/agent-transcripts/chat-shell-missing-result/….jsonl,projects/home-me-proj/terminals/shell-pwd.txt}`、
adapter `client/lib/services/cli/cursor/capabilities/history/{ai_transcript,side_resolver,ai_history_capability,terminal_file,terminal_tool_result_enricher}.dart`、
`client/lib/services/cli/cursor/capabilities/{history_context_env,tool_call_resolvers}.dart`、`client/lib/services/cli/cursor/provider/{cursor_windows_home_junction,cursor_session_config_dir,cursor_home_layout}.dart`

> 与 [claude.md](claude.md) 同属「JSONL + role/content blocks」家族，但顶层字段名、id 缺失处理、工具结果回填方式均不同——下文对比处显式标注。

## Transcript 存储

| 项目 | 值 |
|---|---|
| configDir 解析 | `CursorWindowsHomeJunction.resolveCursorConfigDir`：`CURSOR_CONFIG_DIR` env 优先（normalized absolute），否则 `HOME`（configDir = `$HOME/.cursor`）；Windows 上先读 `{parent(HOME)}/runtime-home` junction marker（`WindowsCliRuntimeJunction`，marker 文件名为 `runtime-home`），marker 非空则 configDir = `{agentHome}/.cursor` |
| 会话注入 | `CursorHistoryContextEnv.sessionEnv`：`CURSOR_CONFIG_DIR` = session runtime toolDir、`HOME`/`USERPROFILE` = `dirname(toolDir)`（fake HOME 隔离）。会话 config 根 = `<toolDir>/home/.cursor/`（`CursorSessionConfigDir`）——`CURSOR_CONFIG_DIR` 只重定位 `cli-config.json`/`chats`，`.cursor` 数据目录（plugins/MCP/skills）仍从 `HOME` 读，故必须隔离 fake HOME |
| chats 关联 | `chats/{wsHash}/{chatId}/meta.json`（夹具实测字段：`agentId` / `name` / `hasConversation` / `updatedAtMs` / `createdAt`）。`_resolveChatId`：优先 `persistedNativeId`；否则扫描全部 `chats/*/*`，取 `hasConversation == true` 且 `updatedAtMs` 最大者 |
| 位置 | `{configDir}/projects/{project}/agent-transcripts/{chatId}/{chatId}.jsonl`（nested，夹具实测）；源码亦支持扁平 `agent-transcripts/{chatId}.jsonl`（flat）。projectRoot = `projects/{project}`；定位时遍历所有 project 目录、两种形态都试 |
| 文件格式 | JSONL（每行一个事件，UTF-8；坏 JSON 行静默跳过） |
| 解析入口 | `CursorAiTranscriptAdapter` / `CursorAiHistoryCapability`（`ai_transcript.dart`） |
| 增量能力 | **有**——`lineAppend = appendCursorJsonlEvent`（全量 parse 与增量 tailer 共用同一逐事件函数，零分叉）；`tailFallbackPrefix = 'cursor'`；`liveCacheToken` 返回 null |
| cache token | `transcriptToken|terminalsFingerprint`——transcript 字节 hash 与 `{projectRoot}/terminals/` 目录指纹（`*.txt` 的 name/size/mtime）拼接；`changeWatchRoot` = projectRoot |

## 消息 schema

JSONL 每行顶层字段：`role`（user / assistant）、`message`（`{content, id?}`）、可选 `uuid` / `timestamp`。
**与 Claude 的差异：cursor 用顶层 `role` 区分消息（Claude 用顶层 `type`）；噪音事件反而用顶层 `type`**（夹具实测 `{"type":"turn_ended","status":"success"}`，无 `role` → 丢弃）。

| 事件 | 关键字段 | AiMessage 映射 | 说明 |
|---|---|---|---|
| user / assistant | `message.content` = string | AiTextPart(role 对应) | 经 `_cursorVisibleText` 清理后 trim 为空则整事件丢弃（返回 false） |
| user / assistant | `message.content[]` type=`text` | AiTextPart | 与同事件 tool_use / tool_result 并存时保留 |
| user / assistant | `message.content[]` type=`tool_use`，字段 `id`? / `name` / `input` | AiToolCallPart(toolCallId, toolName=`name`, args=`input`(Map)) | **仅 assistant 事件挂 tool parts**（user 事件的 tool_use 被丢弃）；`name` 缺省兜底 `'tool'`；`input` 非 Map → args=null |
| user | `message.content[]` type=`tool_result`，字段 `tool_use_id` / `content` / `is_error` | **不产生新消息**；经 `applyAiToolResult` 关联到同 `tool_use_id` 的 AiToolCallPart（写入 `result`、`status=complete`、`isError \|= is_error`） | `tool_use_id` 非 string 或为空则跳过；`content` 为列表时逐 `type=text` 块取文本、其余 toString，以 `\n` 连接 |
| 噪音（`{"type":"turn_ended",…}` 等） | 无 `role` 或 `message` 非 Map | 无 | 返回 false：不产生消息、不消耗 fallback id、增量下不推进锚点 |
| 通用 | 事件 `uuid` → 事件 `id` → `message.id` → fallback `cursor-{seq}` | `id` / `createdAt` | **id 优先级与 Claude 相反**（Claude 是 `message.id` 优先）；`timestamp` 仅当合法 ISO 字符串才设置 createdAt（夹具无 timestamp 行） |

文本清理（`_cursorVisibleText`，夹具实测）：
- 整块 `[REDACTED]` → 丢弃；文本**尾部**的 `[REDACTED]` 后缀 → 剥离（no_tool_id 夹具相邻文本块）；这是 Cursor parent-facing transcript 中思考的占位，不是用户可见正文；
- `<timestamp>…</timestamp>` → 剥离；`<user_query>…</user_query>` → 解包为内部文本（no_tool_id 夹具首行 `<user_query>\nhello\n</user_query>` → `hello`）。

解析后处理（`finalizeAiMessagesForHistory`，ai_message_core）：合并相邻 assistant 消息；`result==null` 且 status 非 running 且非 error 的 tool call → `status=incomplete`（磁盘 transcript 不发明 running）。

## 工具调用 schema

> 说明：Cursor adapter 对工具名**不做白名单**——`name` 从 JSONL 原样透传。「解析类别」来自共享类别表 `services/ai_history/tool_call_categories.dart`（`defaultToolCallCategoryResolver`，cursor 专属代码不写死类别，仅 shell 工具名集合有专属配置）。

| tool name | args 关键 key | 解析类别 | 解析器配置位置 |
|---|---|---|---|
| Shell | `command`；实测还有可选 `description`（chat-shell-missing-result.jsonl） | command（共享表 `'shell'`） | `tool_call_resolvers.dart` shellResolver（`CursorToolCallResolvers`） |
| Read | `path` | read | 共享表 `'read'` |
| agent / task | 子代理定位读 args/result 的 `agentId` / `agent_id`，或 args 的 `resume` / `prompt` / `description`（见下节） | subagent | `subagentToolNames` 含 `'agent'` + `'task'`（`ai_history_capability.dart:33`）+ `CursorSideResolver` |
| bash / shell / execute / run_terminal_cmd / shell_command / exec_command / run_shell_command | `command` | command | `CursorToolCallResolvers` shellResolver 的 `toolNames` 集合（源码字面量，非夹具实测） |
| （缺省兜底）tool | 无 | other | `ai_transcript.dart`——`name` 字段缺失时的默认工具名 |
| mcp__ 前缀 | 无 | mcp | 共享表前缀规则 `('mcp__', …)` |

夹具实测（jq 抽查）：chat-aaaa-bbbb-cccc-dddd.jsonl 的 `Shell` `input={"command":"pwd"}`；chat-shell-missing-result.jsonl 的 `Shell` `input={"command":"pwd","description":"pwd"}`；agent_transcript_no_tool_id.jsonl 的 `Read` `input={"path":"/tmp/demo/SKILL.md"}`（**无 `id`**）。

### 无 id 的 tool_use（Cursor 特有）

夹具 no_tool_id 与 `cursor_ai_transcript_test.dart` 内联事件均实测：真实 Cursor agent-transcript 的 tool_use **经常没有 `id`**。
- assistant 事件：fallback id = `{messageId}-tool-{seq}`（`messageId` = 该事件的最终消息 id，`seq` 按事件内 tool 顺序计数）；
- user 事件的 tool_use：本就被丢弃，fallback id 用 `user-tool-{seq}` 占位（不参与后续关联）；
- 没有 fallback 时这些 tool part 会整体丢失，只留下相邻的 `[REDACTED]` 占位文本（源码注释与回归测试覆盖）。

### 工具结果缺失的回填（`CursorTerminalToolResultEnricher`）

Cursor 的 agent transcript 中工具调用后**可能没有** `tool_result` 行（chat-shell-missing-result 夹具：只有 user 指令 + assistant tool_use 两行）。此时用终端侧文件回填：
- 触发条件：`AiToolCallPart.result` 为 null 或 trim 后为空（`_isResultMissing`），且 `requiresFilesystem: true`（需 `ctx.fs` + `rootTranscriptPath`，与 Claude enricher 直接吃 bundle 不同）；
- 数据源：`{projectRoot}/terminals/*.txt`（transcript 路径 → projectRoot 推导，nested/flat 两种形态都处理）；
- 文件格式（夹具 `shell-pwd.txt` 实测）：`---` 分节——header 键值（`pid` / `command` / `title` / `status` / `started_at` / `running_for_ms`）、body（`---` 到下一个 `---` 间的原始输出）、可选 trailer（`exit_code` / `elapsed_ms` / `ended_at`）；
- 匹配（`shellResolver` 解析 tool part → `AiShellToolTarget{command, description}`）：命令规范化（`\r\n`→`\n`、trim）相等为前提；tier1 = `description == title`（实测 fixture 的 `description:"pwd"` 命中 `title:"pwd"`），tier2 = 仅命令相等；多个候选按 `|startedAt - message.createdAt|` 最近者（其次取 endedAt/startedAt 最新者）去重；
- 回填：`result = body`、`status = complete`、`isError |= exitCode != 0`。实测：`Shell {command:"pwd",description:"pwd"}` → body `/home/hhoa/proj`、exitCode 0。

## Reasoning / 子代理形态

- **thinking 块**：Cursor parent-facing transcript **没有** thinking 块——思考位置用字面量 `[REDACTED]` 占位（解析时丢弃/剥离，见消息 schema）。`appendCursorJsonlEvent` 的 block switch 只认 `text` / `tool_use` / `tool_result`，其余类型（含 `thinking`）直接 continue。
- **agent / task 子代理**（`CursorSideResolver`，`subagentToolNames = {'agent','task'}`）：
  - transcript root：`cursorAgentTranscriptsRootFor`——parent 为 nested 形态 `…/agent-transcripts/{stem}/{stem}.jsonl` → root = `dirname(parentDir)`（即 `agent-transcripts/`）；扁平 `…/agent-transcripts/{id}.jsonl` → root = parentDir；
  - 解析路径一（uuid）：工具 args 中 `resume` / `agentId` / `agent_id`（string 非空）优先，再回退 `subagentAgentIdFromPart`（读 part args/result 的 `agentId` / `agent_id`）→ 尝试 `{uuid}/{uuid}.jsonl`（nested）或 `{uuid}.jsonl`（flat）；
  - 解析路径二（prompt 启发式，无 uuid 时）：args 的 `prompt` / `description` → `normalizeCursorTaskPrompt`（剥离 `<timestamp>`、解包 `<user_query>`）→ 扫描 root 下兄弟 transcript（排除自身 stem 与 `subagents` 目录），**首条 user 文本**（同样 normalize）完全相等者按 `|mtime - referenceAt|` 取距离最小且唯一者（`referenceAt` = 工具调用时刻，缺省 parent mtime）；
  - 解析失败返回 null，inflater 回退到工具 result 合成子代理消息（`syntheticSubagentMessagesFromResult`）。
- **fingerprint**：`CursorSideResolver.fingerprint`——transcript root 下除自身 stem 与 `subagents/` 外的兄弟（nested 目录 → `{name}/{name}.jsonl`，flat `*.jsonl`），输出 `name|size|mtime` 行，供 loader 判断是否重灌子代理附件。

## 增量 vs 全量

- **分叉点**：两者共用 `appendCursorJsonlEvent`——全量走 `CursorAiTranscriptAdapter.parse`（`LineSplitter` 逐行 `_tryDecodeObject`，坏 JSON 行静默跳过）；增量走 `AiTranscriptTailReader`（锚点 = 最后一条已消费行的整行 hash）。
- **消费语义**：只消费 `role` ∈ {user, assistant} 且 `message` 为 Map 的事件；噪音事件（无 role、`message` 非 Map、空文本）返回 false——不推进锚点、**不消耗 fallback 序号**（line_append_test 实测：`{"content":"[REDACTED]"}` 事件返回 false 且 seq 不增）。
- **id 序列约定**：`uuid` → `id` → `message.id` → fallback `cursor-{seq}`；fallback id 惰性求值（被丢弃的事件不占号），`tailFallbackPrefix='cursor'` 与全量 parse 的 `'cursor-${seq}'` 一致——保证增量与全量（或重建）产出的消息 id 序列完全相同。
- **tool_result-only 事件**：只 mutate 前面的 tool call（`applyAiToolResult`），不新增消息；重复应用幂等（line_append_test「mutates without adding and is idempotent」）。
- **相邻 assistant 合并**：`appendCursorJsonlEvent` 内部**就地合并**（`messages.last.role == assistant` 时拼 parts），与全量 `finalizeAiMessagesForHistory` 的 `coalesceAdjacentAssistants` 语义等价——增量与全量输出同一消息序列（line_append_test 用 `finalize` 后内容级比对验证零分叉）。
- **幂等**：同一 fixture 重放两次结果一致（不重复、不漂移）。

## 已知陷阱

- **无 id tool_use**：Cursor 真实 transcript 常见；依赖 fallback `{messageId}-tool-{seq}`（仅 assistant 事件），user 事件的 tool_use 直接丢弃。若未来 fallback 规则变化，tool_result 关联会失配。
- **tool_result 缺失**：assistant 调用后无 user `tool_result` 行（shell-missing-result 夹具）→ result 保持 null，需 `CursorTerminalToolResultEnricher` 用 `terminals/*.txt` 回填；enricher 不可用（无 fs / 无 rootTranscriptPath / 无匹配 terminal 文件）时 result 仍为 null，finalize 会标 `incomplete`。
- **`[REDACTED]` 不是正文**：整块丢弃、尾部剥离——parent-facing transcript 里思考被替换为占位符，UI 上不会显示思考内容。
- **`<user_query>` / `<timestamp>` 包装**：解析（`_cursorVisibleText`）与子代理 prompt 匹配（`normalizeCursorTaskPrompt`）都要先解包，两处逻辑各自实现，改一处必须同步另一处。
- **chatId 定位依赖 chats/meta.json**：无 `persistedNativeId` 时取 `hasConversation==true` 且 `updatedAtMs` 最大者——多 chat 会话可能定位到最新而非当前会话；`meta.json` 缺失/损坏则定位失败。
- **project 目录遍历**：所有 project 都试 nested 与 flat 两种形态；`listDir` 抛错（如 projects 目录不存在）→ 整体返回 null。
- **thinking 块不映射**：block switch 只认 text/tool_use/tool_result，其他类型静默 continue（与 Claude 的 thinking → AiReasoningPart 不同）。
- **id 优先级与 Claude 相反**：cursor 先事件 `uuid`/`id` 后 `message.id`；两套 adapter 不能互读对方 JSONL 的 id 语义。
- **坏 JSON 行**：静默跳过（`_tryDecodeObject` 失败 continue）。
- **回合结束的最后一行**：真实 agent-transcript 常在 PTY quiet 之后才追加最终 assistant 文本，且文件末行可能没有 `\n`。增量 tailer 在 EOF 把完整 JSON 当一行消费（半行仍推迟）；History seat 在 `flushHeldTip(endAwaiting: true)` 时 `softReload(force: true)`（立即 + 800ms settle），不走 `invalidate`。见 [history-turn-end-settle-design](../superpowers/specs/2026-08-19-history-turn-end-settle-design.md)。
