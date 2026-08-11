# Claude Code 消息与工具调用格式参考

**日期:** 2026-08-12
**来源:** 夹具 `client/test/fixtures/session_history/claude/{basic,streamed_turn,truncated_bash}.jsonl`、
adapter `client/lib/services/cli/claude/capabilities/history/{ai_transcript,ai_history_capability,compatible_jsonl,compatible_side_resolver,compatible_tool_result_enricher,side_resolver,workflow_resolver}.dart`

## Transcript 存储

| 项目 | 值 |
|---|---|
| 位置 | `{root}/projects/{bucket}/{taskId}.jsonl`（`{root}` = CLI config 目录对应的 transcript roots；`layoutSegments: ['projects']`） |
| bucket 规则 | 实测确认：由 workspace 主路径派生——`workspaceBucketForPrimaryPath()` 先 `\`→`/`、再做 WSL 路径转换，最后把 `/` 替换为 `-`（如 `/home/hhoa/proj` → `home-hhoa-proj`） |
| 定位细节 | `probePinnedTranscript`：bucket 只是 hint 不是权威——扫描所有 bucket，**按文件大小取最全的 `.jsonl`**，等大时 pin 的 bucket 优先；`matchDirectories: false`，`{sessionId}/` 目录不参与（防 workflow sidecar 目录遮蔽真实文件）；含 `/members/` 的 root 优先扫描 |
| 文件格式 | JSONL（每行一个事件，UTF-8） |
| 解析入口 | `ClaudeAiTranscriptAdapter` / `ClaudeAiHistoryCapability`（`ai_transcript.dart`） |
| 增量能力 | **有**——`lineAppend = appendClaudeJsonlEvent`（全量 parse 与增量 tailer 共用同一逐事件函数，零分叉）；`tailFallbackPrefix = 'claude'` |

## 消息 schema

JSONL 每行顶层字段：`type`（user / assistant / 其他）、`message`（`{role, content, id?}`）、`uuid`、`timestamp`，
以及实测出现的元数据字段 `parentUuid`、`isSidechain`、`promptId`、`permissionMode`、`userType`、`entrypoint`、`cwd`、`sessionId`、`version`、`gitBranch`（streamed_turn.jsonl）。

| JSONL 事件 type | 关键字段 | AiMessage 映射 | 说明 |
|---|---|---|---|
| user | `message.content` = string | AiTextPart(role=user) | trim 后为空则整事件丢弃（返回 false） |
| user | `message.content[]` type=`text` | AiTextPart | 与同事件内 tool_result 并存时保留文本 |
| user | `message.content[]` type=`tool_result`，字段 `tool_use_id` / `content` / `is_error` | **不产生新消息**；经 `applyAiToolResult` 关联到同 `tool_use_id` 的 AiToolCallPart（写入 `result`、`status=complete`、`isError \|= is_error`） | 只有 tool_result 的 user turn（如 basic.jsonl 的 u-2）不生成消息；`content` 为列表时逐 `type=text` 块取文本、其余 toString，以 `\n` 连接；`tool_use_id` 非 string 或为空则跳过 |
| assistant | `message.content` = string | AiTextPart(role=assistant) | 同上 trim 规则 |
| assistant | `message.content[]` type=`text` | AiTextPart | |
| assistant | `message.content[]` type=`thinking` | AiReasoningPart | 非空才保留（streamed_turn.jsonl 实测：thinking 与 text 分片共享 `message.id`） |
| assistant | `message.content[]` type=`tool_use`，字段 `id` / `name` / `input` | AiToolCallPart(toolCallId=`id`, toolName=`name`, args=`input`(Map)) | **仅 assistant 事件挂 tool parts**（user 事件的 tool_use 被忽略）；`id` 为空则跳过；`name` 缺省兜底 `'tool'`；`input` 非 Map → args=null |
| 其他（`queue-operation` 等元数据/噪音） | — | 无 | 返回 false：不产生消息、不消耗 fallback id、增量下不推进锚点 |
| 通用 | `message.id` / `uuid` / `timestamp` | `id` / `createdAt` | 消息 id 优先级：`message.id` → 事件 `uuid` → fallback `claude-{seq}`；`timestamp` 仅当合法 ISO 字符串才设置 createdAt |

解析后处理（`finalizeAiMessagesForHistory`，ai_message_core）：合并相邻 assistant 消息；`result==null` 且 status 非 running 且非 error 的 tool call → `status=incomplete`（磁盘 transcript 不发明 running）。

## 工具调用 schema

> 说明：Claude adapter 对工具名**不做白名单**——`name` 从 JSONL 原样透传，所以表中工具名来自夹具实测（Bash）与源码字面量（agent / task / workflow，见 `ai_history_capability.dart:32`）。「解析类别」来自共享类别表 `services/ai_history/tool_call_categories.dart`（claude 专属代码不写死类别）。

| tool name | args 关键 key | 解析类别 | 解析器配置位置 |
|---|---|---|---|
| Bash | `command`；实测还有可选 `description`（truncated_bash.jsonl） | command（共享表 `'bash'`） | `compatible_jsonl.dart` tool_use 分支；截断结果回填见 `compatible_tool_result_enricher.dart` |
| agent | 无白名单；子代理定位可读 args/result 的 `agentId` / `agent_id`（`subagentAgentIdFromPart`） | subagent | `subagentToolNames` 含 `'agent'` + `ClaudeCompatibleSideResolver` |
| task | 同 agent | subagent | `subagentToolNames` 含 `'task'` + `ClaudeCompatibleSideResolver` |
| workflow / Workflow / work_flow | 不依赖 args；由 `toolCallId` 经 task-notification 解析 run | subagent | `subagentToolNames` 含 `'workflow'`；`isWorkflowTool()`（workflow_resolver.dart）匹配三种大小写变体 → `ClaudeWorkflowResolver` |
| （缺省兜底）tool | 无 | other | `compatible_jsonl.dart:81`——`name` 字段缺失时的默认工具名 |

工具结果截断回填（`ClaudeCompatibleToolResultEnricher`，`requiresFilesystem: false`，直接吃 bundle）：
- 触发条件：tool_result `content` 含 sentinel `tool output truncated`（不区分大小写），且同一 user 事件**顶层**存在 `toolUseResult`；
- 回填规则：`toolUseResult` 为 Map 时取 `stdout` / `stderr`（非空则 `stdout\nstderr` 拼接）、`exitCode != 0` → `isError`；为字符串则直接使用；
- 实测字段（truncated_bash.jsonl）：`{"stdout":…,"stderr":"","exitCode":0,"isTruncated":true}`；
- 替换后写回 `result`、`status=complete`、`isError \|= 原 is_error`。

## Reasoning / 子代理形态

- **thinking 块**：`message.content[] type=thinking` → `AiReasoningPart`（streamed_turn.jsonl 实测）。Claude 用 `thinking`，不是 `reasoning` 类型名。
- **agent / task 子代理**（`ClaudeCompatibleSideResolver`）：
  - side transcript：`{parentStem}/subagents/agent-{agentId}.jsonl`（`{parentStem}` = 父 transcript 去掉 `.jsonl` 后缀）；
  - 映射：`subagents/` 下 `agent-*.meta.json`（内容 `{"toolUseId": …}`）建立 toolUseId→agentId 索引；查不到时回退 `subagentAgentIdFromPart`（从 part args/result 的 `agentId` / `agent_id`）；
  - 解析失败返回 null，inflater 回退到工具 result 合成子代理消息（`syntheticSubagentMessagesFromResult`）。
- **Workflow**（`ClaudeWorkflowResolver`）确定性映射（源码注释声称在真实会话上验证过）：
  ```
  Workflow tool_use id
    → <task-notification><tool-use-id>…</tool-use-id><task-id>…</task-id>   （parent transcript）
    → run record {parentStem}/workflows/wf_{runId}.json[taskId]              （字段：taskId/runId/workflowName/status/phases/agentCount/summary/durationMs）
    → run dir {parentStem}/subagents/workflows/{runId}/agent-*.jsonl         （+ journal.jsonl）
  ```
  - `journal.jsonl` 每行 `{"type":"started"|"result","agentId":…,"result":{status,approved,summary/notes}}`——取每个 agent 最后一次 result 的 status/summary 与首次出现顺序；
  - 子代理角色（`SubagentWorkflowAgent.role`）取子 transcript 首条 user 文本去掉 `You are (the )` 前缀后的首行；
  - run 摘要合成 assistant 消息 `workflow-summary-{runId}`；run 未落地（cancelled/立即停止，无 task-notification 或 agent transcript）→ resolve 返回 null 回退工具 result；
  - 增量缓存：按 parent transcript 路径 LRU(4) 缓存 notification/run-record 索引（parent 文件 mtime+size 变化才重建），agent/journal 按 (mtime, size) 复用，避免 live refresh 每 ~750ms 全量重读。
- **fingerprint**：`subagents/` 树递归列出 `*.jsonl` / `*.meta.json` 的 `name|size|mtime`，供 loader 判断是否需要重灌子代理附件。

## 增量 vs 全量

- **分叉点**：两者共用 `appendClaudeJsonlEvent`——全量走 `parseClaudeCompatibleJsonl`（逐行 `tryDecodeJsonlLine`，坏 JSON 行静默跳过）；增量走 `AiTranscriptTailReader`（锚点=最后一条已消费行的整行 FNV-1a hash）。
- **增量窗口**：尾部窗口 64KB → 256KB → 全文件；锚点找不到（重写/压缩/截断）→ 全量重建；每累计 30 次成功增量强制一次全量校验；文件末尾半行（无 `\n` 结尾）本轮忽略、下轮补全。
- **消费语义**：`lineAppend` 只消费 user/assistant 事件；元数据/噪音事件（`queue-operation`、缺 `message`、空 content）返回 false——不推进锚点、**不消耗 fallback 序号**。
- **id 序列约定**：`message.id` 优先 → 事件 `uuid` → fallback `claude-{seq}`；fallback id 惰性求值（被丢弃的事件不占号），且 `tailFallbackPrefix='claude'` 与 adapter 全量 parse 的 `'claude-${seq}'` 一致——保证增量与全量（或重建）产出的消息 id 序列完全相同。
- **同 id 合并**：同 `message.id` + 同 role 的连续事件合并 parts，边界 text 段（尾部 text 连续段 + 头部 text 连续段）用空格连接成一个 AiTextPart（实测 streamed_turn.jsonl 的 thinking+text 两行合一条）。
- **相邻 assistant 合并**：全量经 `finalizeAiMessagesForHistory` 的 `coalesceAdjacentAssistants`；增量经 tailer 原地 `_coalesceAssistantsInPlace`——语义等价（相邻 assistant 不论 id 都合并），保证增量与全量输出同一消息序列。

## 已知陷阱

- **截断工具输出**：tool_result 文本含 `tool output truncated` 时只是占位，需 `ClaudeCompatibleToolResultEnricher` 用同事件顶层 `toolUseResult`（stdout/stderr/exitCode）回填；enricher 不可用时（无 bundle 也无 root 路径）保持占位文本。
- **嵌套/列表 tool_result**：`content` 为列表时只取 `type=text` 块的文本、其余 `toString`，`\n` 连接——非 text 块（如图片）会变成字符串化对象。
- **tool_result-only turn**：纯工具结果的 user 事件不生成 user 消息（basic.jsonl u-2 断言不存在），只把结果关联到前面的 assistant tool call。
- **流式分片**：同 `message.id` 跨多个 `uuid`（streamed_turn.jsonl）合并；若流式分片各自独立 id，靠相邻 assistant 合并兜底——增量与全量必须一致，否则 UI 会出现不同消息条数。
- **坏 JSON 行**：静默跳过（`skips corrupt JSONL lines` 测试覆盖）。
- **加密/空 thinking**：`thinking` 内容 trim 后为空即丢弃，不会保留空的 reasoning 块。
- **bucket 只是 hint**：probe 按文件大小选最全 `.jsonl`，等大才偏向 pin 的 bucket；`{sessionId}/` 目录（workflow sidecar）在 transcript 定位时不算数，避免把目录当 transcript。
- **`name` 缺失**：工具名兜底为字面量 `'tool'`，不是报错——解析时会得到名为 `tool` 的 AiToolCallPart。
