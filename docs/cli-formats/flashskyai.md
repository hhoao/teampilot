# FlashskyAI 消息与工具调用格式参考

**日期:** 2026-08-12
**来源:** 夹具 `client/test/fixtures/session_history/flashskyai/{basic,streamed_tools}.jsonl`、
adapter `client/lib/services/cli/flashskyai/capabilities/history/{ai_transcript,ai_history_capability}.dart`、
复用解析器 `client/lib/services/cli/claude/capabilities/history/{compatible_jsonl,compatible_side_resolver,compatible_tool_result_enricher}.dart`

> 概述：flashskyai 的 JSONL **完全复用 Claude 的兼容解析链路**（`parseClaudeCompatibleJsonl` /
> `appendClaudeJsonlEvent` / `ClaudeCompatibleSideResolver` / `ClaudeCompatibleToolResultEnricher`），
> shapes 与 Claude 同源。差异点仅在三处：① transcript 定位为 `projects` + `workspaces` 双探针
> （Claude 只有 `projects`）；② fallback 消息 id 前缀为 `flashskyai-{seq}`（Claude 为 `claude-{seq}`）；
> ③ **不含 workflow 解析**——`subagentToolNames` 只有 `{'agent', 'task'}`。

## Transcript 存储

| 项目 | 值 |
|---|---|
| 位置 | `{root}/projects|workspaces/{bucket}/{taskId}.jsonl`（`{root}` = CLI config 目录对应的 transcript roots；`layoutSegments: ['projects', 'workspaces']` 双探针，**projects 优先**） |
| 实测布局 | 磁盘安装见 `~/.flashskyai/projects/…`（非 `workspaces/`，源码注释明确）；`workspaces` 仅作为旧布局次级探针保留（测试 `locateFlashskyaiTranscript prefers projects over workspaces` 断言 projects 优先） |
| bucket 规则 | 同 Claude——由 `RuntimeLayout.workspaceBucketForPrimaryPath(cwd)` 生成（`session_history_context_builder.dart:91`）：先 `\`→`/`、再做 WSL 路径转换，最后把 `/` 替换为 `-` |
| 定位细节 | `probePinnedTranscript`（同 Claude）：bucket 只是 hint——扫描所有 bucket **按文件大小取最全的 `.jsonl`**，等大时 pin 的 bucket 优先；`matchDirectories: false`，`{sessionId}/` 目录不参与；含 `/members/` 的 root 优先扫描 |
| 文件格式 | JSONL（每行一个事件，UTF-8；`utf8.decode(allowMalformed: true)`） |
| 解析入口 | `FlashskyaiAiTranscriptAdapter` / `FlashskyaiAiHistoryCapability`（`ai_transcript.dart`） |
| 增量能力 | **有**——`lineAppend = appendClaudeJsonlEvent`（与 Claude 完全同一函数，零分叉）；`tailFallbackPrefix = 'flashskyai'` |

## 消息 schema

JSONL 每行顶层字段：`type`（user / assistant / 其他）、`message`（`{role, content, id?}`）、`uuid`、`timestamp`，
以及实测出现的元数据字段（streamed_tools.jsonl）：`parentUuid`、`isSidechain`、`teamName`、`agentName`、
`promptId`、`permissionMode`、`userType`、`entrypoint`、`cwd`、`sessionId`、`version`、`gitBranch`、`slug`、
`sourceToolAssistantUUID`。`message` 内还有 Claude API 风格字段 `message.type='message'`、`model`
（实测 `deepseek-v4-pro`）、`stop_reason`、`stop_sequence`、`usage`（实测含 `server_tool_use.web_search_requests` /
`web_fetch_requests` 等）。解析器不消费这些元数据字段，仅 `message.content` 与事件级 `timestamp` 生效。

| JSONL 事件 type | 关键字段 | AiMessage 映射 | 说明 |
|---|---|---|---|
| user | `message.content` = string | AiTextPart(role=user) | trim 后为空则整事件丢弃（返回 false） |
| user | `message.content[]` type=`text` | AiTextPart | 与同事件内 tool_result 并存时保留文本 |
| user | `message.content[]` type=`tool_result`，字段 `tool_use_id` / `content` / `is_error` | **不产生新消息**；经 `applyAiToolResult` 关联到同 `tool_use_id` 的 AiToolCallPart（写入 `result`、`status=complete`、`isError \|= is_error`） | 纯 tool_result 的 user turn（basic.jsonl 的 u-2 实测不生成消息）；`content` 为列表时逐 `type=text` 块取文本、其余 toString，以 `\n` 连接；`tool_use_id` 非 string 或为空则跳过 |
| assistant | `message.content` = string | AiTextPart(role=assistant) | 同上 trim 规则 |
| assistant | `message.content[]` type=`text` | AiTextPart | |
| assistant | `message.content[]` type=`thinking` | AiReasoningPart | 非空才保留（解析器支持，**flashskyai 夹具未实测到 thinking 行**——与 Claude 的 streamed_turn.jsonl 不同） |
| assistant | `message.content[]` type=`tool_use`，字段 `id` / `name` / `input` | AiToolCallPart(toolCallId=`id`, toolName=`name`, args=`input`(Map)) | **仅 assistant 事件挂 tool parts**（user 事件的 tool_use 被忽略）；`id` 为空则跳过；`name` 缺省兜底 `'tool'`；`input` 非 Map → args=null |
| 其他（元数据/噪音事件） | — | 无 | 返回 false：不产生消息、不消耗 fallback id、增量下不推进锚点 |
| 通用 | `message.id` / `uuid` / `timestamp` | `id` / `createdAt` | 消息 id 优先级：`message.id` → 事件 `uuid` → fallback `flashskyai-{seq}`；`timestamp` 仅当合法 ISO 字符串才设置 createdAt |

解析后处理（`finalizeAiMessagesForHistory`，ai_message_core）：合并相邻 assistant 消息；`result==null` 且
status 非 running 且非 error 的 tool call → `status=incomplete`（磁盘 transcript 不发明 running）。

## 工具调用 schema

> 说明：与 Claude 相同，adapter 对工具名**不做白名单**——`name` 从 JSONL 原样透传。表中 `Bash` / `Read`
> 来自夹具实测，`agent` / `task` 来自 `ai_history_capability.dart:32` 的 `subagentToolNames`。「解析类别」
> 来自共享类别表 `services/ai_history/tool_call_categories.dart`（**lowercase 匹配**：`Bash`→`bash`→command，
> `Read`→`read`→read）。

| tool name | args 关键 key | 解析类别 | 解析器配置位置 |
|---|---|---|---|
| Bash | `command`；实测还有可选 `description`（streamed_tools.jsonl 的 `"List working directory contents"`） | command（共享表 `'bash'`） | `compatible_jsonl.dart` tool_use 分支；截断结果回填见 `compatible_tool_result_enricher.dart` |
| Read | `file_path`（streamed_tools.jsonl 实测） | read（共享表 `'read'`） | 同上 |
| agent | 无白名单；子代理定位可读 args/result 的 `agentId` / `agent_id`（`subagentAgentIdFromPart`） | subagent | `subagentToolNames` 含 `'agent'` + `ClaudeCompatibleSideResolver` |
| task | 同 agent | subagent | `subagentToolNames` 含 `'task'` + `ClaudeCompatibleSideResolver` |
| （缺省兜底）tool | 无 | other | `compatible_jsonl.dart:81`——`name` 字段缺失时的默认工具名 |

工具结果截断回填（`ClaudeCompatibleToolResultEnricher`，与 Claude 同一实现，`requiresFilesystem: false`，直接吃 bundle）：
- 触发条件：tool_result `content` 含 sentinel `tool output truncated`（不区分大小写），且同一 user 事件**顶层**存在 `toolUseResult`；
- 回填规则：`toolUseResult` 为 Map 时取 `stdout` / `stderr`（非空则 `stdout\nstderr` 拼接）、`exitCode != 0` → `isError`；为字符串则直接使用；
- 实测字段（streamed_tools.jsonl 第 6 行，对应 `call_02` 的 Bash 截断结果）：`{"stdout":…,"stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false,"exitCode":0,"isTruncated":true}`——
  比 Claude 的 truncated_bash.jsonl 多出 `interrupted` / `isImage` / `noOutputExpected` 三个字段，**enricher 只读 stdout/stderr/exitCode，其余忽略**；
  另一处实测（第 5 行，对应 `call_01` 的 Read 失败）顶层 `toolUseResult` 为字符串 `"Error: File does not exist. …"`（同时 `is_error: true`）→ 字符串直接使用；
- 替换后写回 `result`、`status=complete`、`isError \|= 原 is_error`。

## Reasoning / 子代理形态

- **thinking 块**：解析器支持 `message.content[] type=thinking` → `AiReasoningPart`（compatible_jsonl.dart:73），
  但 flashskyai 夹具未实测（basic.jsonl 与 streamed_tools.jsonl 均无 thinking 行）——与 Claude 的 streamed_turn.jsonl 相比是覆盖缺口，非格式差异。
- **agent / task 子代理**（复用 `ClaudeCompatibleSideResolver`，与 Claude 同布局）：
  - side transcript：`{parentStem}/subagents/agent-{agentId}.jsonl`（`{parentStem}` = 父 transcript 去掉 `.jsonl` 后缀）；
  - 映射：`subagents/` 下 `agent-*.meta.json`（内容 `{"toolUseId": …}`）建立 toolUseId→agentId 索引；查不到时回退 `subagentAgentIdFromPart`（从 part args/result 的 `agentId` / `agent_id`）；
  - 解析失败返回 null，inflater 回退到工具 result 合成子代理消息（`syntheticSubagentMessagesFromResult`）。
- **无 workflow 解析**：`subagentToolNames` 仅 `{'agent', 'task'}`（`ai_history_capability.dart:32`），不含 `'workflow'`；
  flashskyai 的 capability 也不引用 `workflow_resolver.dart`——与 Claude 不同，workflow 类 tool_use 不会被做 run 侧解析，
  按普通工具处理（类别由共享表/prefix 规则决定）。
- **fingerprint**：复用 Claude 的 fingerprint——`subagents/` 树递归列出 `*.jsonl` / `*.meta.json` 的 `name|size|mtime`，
  供 loader 判断是否需要重灌子代理附件。

## 增量 vs 全量

- **分叉点**：与 Claude **完全共用** `appendClaudeJsonlEvent`——全量走 `parseClaudeCompatibleJsonl`（逐行 `tryDecodeJsonlLine`，坏 JSON 行静默跳过）；
  增量走共享层 `AiTranscriptTailReader`（`ai_transcript_tail_reader.dart`，锚点=最后一条已消费行的整行 FNV-1a hash）。
- **增量窗口**：尾部窗口 64KB → 256KB → 全文件；锚点找不到（重写/压缩/截断）→ 全量重建；每累计 30 次成功增量强制一次全量校验；
  文件末尾半行（无 `\n` 结尾）本轮忽略、下轮补全。
- **消费语义**：`lineAppend` 只消费 user/assistant 事件；元数据/噪音事件返回 false——不推进锚点、**不消耗 fallback 序号**。
- **id 序列约定**：`message.id` 优先 → 事件 `uuid` → fallback `flashskyai-{seq}`；fallback id 惰性求值（被丢弃的事件不占号），
  且 `tailFallbackPrefix='flashskyai'` 与 adapter 全量 parse 的 `'flashskyai-${seq}'` 一致——保证增量与全量（或重建）产出的消息 id 序列完全相同。
- **同 id 合并**：同 `message.id` + 同 role 的连续事件合并 parts，边界 text 段用空格连接成一个 AiTextPart
  （实测 streamed_tools.jsonl：3 行 assistant 共享 `msg_d32cf90b-…`，各挂 1 个 tool_use → 合并成 1 条 assistant 消息、3 个 tool parts：
  `Read` / `Read`(isError=true) / `Bash`；测试断言工具名序列 `['Read', 'Read', 'Bash']`）。
- **相邻 assistant 合并**：全量经 `finalizeAiMessagesForHistory` 的 `coalesceAdjacentAssistants`；增量经 tailer 原地
  `_coalesceAssistantsInPlace`——语义等价，保证增量与全量输出同一消息序列。

## 已知陷阱

- **双探针布局**：`projects` 优先、`workspaces` 只是旧布局回退（源码注释 + 测试断言）；磁盘上是 `workspaces/` 布局时定位仍成功，
  但新安装应落在 `~/.flashskyai/projects/`。
- **截断回填字段差异**：flashskyai 实测 `toolUseResult` map 比 Claude 夹具多 `interrupted` / `isImage` / `noOutputExpected`——
  enricher 只读 `stdout` / `stderr` / `exitCode`，多余字段被忽略。
- **无 workflow 解析**：Claude 的 Workflow run 解析（task-notification / wf_ 目录）对 flashskyai **不生效**——workflow 类
  tool_use 不挂子代理附件。
- **夹具未见 thinking / 流式 text 分片**：streamed_tools.jsonl 只覆盖了 tool_use 分片共享 `message.id` 的合并路径，
  text/thinking 流式分片合并由共享解析器覆盖但 flashskyai 夹具未实测。
- **工具名大小写敏感**：`Bash` / `Read` 原样透传；共享类别表按 lowercase 匹配（`Read`→`read` 才能命中 read 类别）。
- **其余与 Claude 相同**：tool_result-only turn 不生成 user 消息（basic.jsonl u-2 断言不存在）；嵌套/列表 tool_result 非 text 块
  toString 字符串化；坏 JSON 行静默跳过；空 thinking 丢弃；`name` 缺失兜底字面量 `'tool'`；bucket 只是 hint（按文件大小选最全
  `.jsonl`，等大才偏向 pin 的 bucket，`{sessionId}/` 目录不参与 transcript 定位）。
