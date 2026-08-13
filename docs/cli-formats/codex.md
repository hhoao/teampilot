# Codex 消息与工具调用格式参考

**日期:** 2026-08-12
**来源:** 夹具 `client/test/fixtures/session_history/codex/{basic,response_item_messages,response_item_message_echo,reasoning_and_tools}.jsonl`、
adapter `client/lib/services/cli/codex/capabilities/history/{ai_transcript,ai_history_capability,side_resolver}.dart`、
测试断言 `client/test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart`

## Transcript 存储

| 项目 | 值 |
|---|---|
| 位置 | `$CODEX_HOME/sessions/**/rollout-*.jsonl`——`locateCodexTranscript` 对 `{CODEX_HOME}/sessions` **递归**扫描；实测目录为日期分层：测试写入 `sessions/2026/07/10/rollout-2026-07-10T12-00-00-<uuid>.jsonl`（`codex_ai_transcript_test.dart`） |
| 会话关联 | `_rolloutId` 正则 `rollout-.*-<uuid8>-<uuid4>-<uuid4>-<uuid4>-<uuid12>\.jsonl$` 提取文件名尾部 UUID；与 `ctx.persistedNativeId` 相等才候选（`ai_transcript.dart:68`）；`persistedNativeId` 为空时按全路径**字典序取最大**（时间戳前缀 ⇒ 最新） |
| 文件格式 | JSONL（每行一个事件，UTF-8，`utf8.decode` allowMalformed） |
| 解析入口 | `CodexAiTranscriptAdapter` / `CodexAiHistoryCapability`（`ai_transcript.dart` / `ai_history_capability.dart`） |
| 增量能力 | **有**——`lineAppend = appendCodexJsonlEvent`（全量 parse 与增量 tailer 共用同一逐事件函数，零分叉）；`tailFallbackPrefix = 'codex'`；`liveCacheToken` 返回 null（无活动缓存 token） |

## 消息 schema

每行顶层字段：`type` / `timestamp` / `payload`（嵌套对象）。顶层 `type` 实测枚举：`session_meta`、`turn_context`、`event_msg`、`response_item`（四个夹具覆盖前三种，`event_msg`+`response_item` 共 25 行）。文本消息一律走 `payload` 内层。

| 顶层 type | payload.type | 关键字段 | AiMessage 映射 |
|---|---|---|---|
| event_msg | user_message | `message` | AiTextPart(role=user)；trim 后空则丢弃；文本含 `<environment_context>` 整个丢弃；与相邻 user 文本相同（echo）则丢弃 |
| event_msg | agent_message | `message` | AiTextPart(role=assistant)；相邻 assistant 文本相同（echo）则丢弃 |
| event_msg | agent_reasoning | `text` | AiReasoningPart（与 `response_item.reasoning` 双写，先到先得） |
| event_msg | token_count | `info` | 无（忽略，返回 false） |
| event_msg | task_started / task_complete | `turn_id` / `last_agent_message` | 无（忽略，返回 false） |
| response_item | message | `role`（user/assistant/developer/system/tool）+ `content[]` | 仅 user/assistant 产生 AiTextPart；developer/system/tool 隐藏；content 块只认 `type=input_text` / `output_text`，`text` 以 `\n` 连接（`_messageText`） |
| response_item | reasoning | `summary[]`（元素 `{type: summary_text, text}`） | AiReasoningPart，块间以 `\n\n` 连接；与 `event_msg.agent_reasoning` 双写先到先得 |
| response_item | function_call | `name` / `arguments` / `call_id` | AiToolCallPart（详见工具调用 schema） |
| response_item | function_call_output | `call_id` / `output` | **不产生新消息**；`applyAiToolResult` 按 `call_id` 关联到前面的 AiToolCallPart（写入 `result`、`status=complete`） |
| response_item | custom_tool_call | `name` / `call_id` / `input`（String 或 Map） | AiToolCallPart（源码支持，夹具未覆盖；`input` 为 Map → args，为 String → argsText） |
| response_item | custom_tool_call_output | `call_id` / `output` | 同 function_call_output 按 `call_id` 关联（源码支持，夹具未覆盖） |

- **id**：fallback `codex-{seq}`（惰性求值，被丢弃的事件不占号）；**createdAt**：`timestamp` 可被 `DateTime.tryParse` 解析才设置。
- **去重**：user / assistant 文本与 reasoning 都有相邻重复检测（`_isAdjacentDuplicateUserText` / `_isAdjacentDuplicateAssistantText` / `_isAdjacentDuplicateAssistantReasoning`），用于抑制 response_item.message 与 event_msg 的 echo 双写（实测 `response_item_message_echo.jsonl`）。
- 解析后处理（`finalizeAiMessagesForHistory`，ai_message_core）：合并相邻 assistant 消息；`result==null` 且 status=complete（非 error）或 running 的 tool call → `status=incomplete`。

## 工具调用 schema

> 说明：Codex adapter 对工具名**不做白名单**——`name` 从 JSONL 原样透传，`name` 为空时兜底字面量 `'tool'`。表中工具名来自夹具实测（exec_command / shell_command）与源码字面量（spawn_agent / agent / task，见 `ai_history_capability.dart:30`）。「解析类别」来自共享类别表 `services/ai_history/tool_call_categories.dart`（codex 专属代码不写死类别，`CodexToolCallResolvers` 直接继承共享 resolver）。

**arguments 形态（实测）**：`arguments` 是 **JSON 字符串**，不是对象——`basic.jsonl` 实测 `"arguments":"{\"cmd\":\"ls\"}"`。`_parseArgs` 对字符串做 `jsonDecode` 得 Map → `args`；非 JSON 字符串 → `args=null`、原始字符串保留在 `argsText`；`arguments` 本身为 Map 时直接使用。

| tool name | args 关键 key | 解析类别 | 来源 |
|---|---|---|---|
| exec_command | `cmd` | command（共享表 `'exec_command'`） | basic.jsonl / response_item_messages.jsonl 实测 |
| shell_command | `command` | command（共享表 `'shell_command'`） | reasoning_and_tools.jsonl 实测 |
| spawn_agent / agent / task | 无白名单；子代理定位读 part args/result 的 `agentId` / `agent_id`（`subagentAgentIdFromPart`，ai_message_core） | subagent | `subagentToolNames`（`ai_history_capability.dart:30`） |
| （缺省兜底）tool | 无 | other | `ai_transcript.dart`——`name` 字段为空时的默认工具名 |

**function_call_output 关联**：`payload.call_id` 必须是非空 string，经 `applyAiToolResult` 在已有消息中按 `toolCallId == call_id` 回填 `result`；找不到匹配的孤儿 output 被静默忽略。实测 `reasoning_and_tools.jsonl`：`call_demo1` 的 output `"Exit code: 0\n/tmp/demo"` 原样写入 result（含 `Exit code:` 前缀，不做解析）。

## Reasoning / 子代理形态

- **Reasoning 双形态**：新版 `response_item.reasoning`（`summary[].type=summary_text`）；旧版 `event_msg.agent_reasoning`（`text` 字段）。两者常同时出现（源码注释 + `_isAdjacentDuplicateAssistantReasoning`）——保留先到的一条。
- **子代理工具**（`CodexSideResolver`）：
  - 工具名集合 `subagentToolNames = {'spawn_agent', 'agent', 'task'}`（`ai_history_capability.dart:30`）；
  - agent id 只能从 part args/result 的 `agentId` / `agent_id` 取（`subagentAgentIdFromPart`）——没有目录级指纹；
  - side transcript 定位：父 transcript 位于 `{CODEX_HOME}/sessions` 下时先按父目录（含直接子目录、**跳过 `subagents` 目录**）找文件名 UUID == agentId 的 rollout；否则全局递归 `{CODEX_HOME}/sessions`（跳过路径含 `subagents` 段的文件）——两种搜索都取字典序最大；
  - 解析失败返回 null → inflater 回退 `syntheticSubagentMessagesFromResult`（从工具 result 合成子代理消息）；
  - **fingerprint 恒为 null**：源码注释说明 rollout 不在 `projects/` 下、父 cache token 必然 miss，所以 live refresh 每次都重新定位解析。
- **工具结果截断回填：无（已调研：不可行）**——`toolResultEnricher = NoOpToolResultEnricher`（`ai_history_capability.dart:13`）；截断占位无回填机制。已调研确认 codex 截断前完整输出从未持久化（同 `call_id` 零重复、`exec_command_end.aggregated_output` 同为头部截断版、sqlite/日志均无全文）——截断即永久，结论见 [truncation-backfill-audit.md](truncation-backfill-audit.md) §1.4。

## 增量 vs 全量

- **分叉点**：零分叉——全量 `parse` 与增量 `lineAppend` 共用 `appendCodexJsonlEvent`；全量逐行 `jsonDecode`（`_tryDecodeObject`，坏 JSON 行静默跳过），增量由 tailer 喂同样的事件对象。
- **增量窗口**：共享 `AiTranscriptTailReader`（`ai_transcript_tail_reader.dart:48`）——尾部窗口 64KB → 256KB → 全文件；锚点 = 最后一条已消费行的行 hash；锚点找不到（重写/压缩/截断）→ 全量重建；每累计 30 次成功增量强制一次全量校验。
- **消费语义**：`lineAppend` 只消费 event_msg（user_message / agent_message / agent_reasoning）与 response_item（message / reasoning / function_call / function_call_output / custom_tool_call / custom_tool_call_output）；`session_meta`、`turn_context`、`token_count`、`task_started` / `task_complete` 等返回 false——不推进锚点、**不消耗 fallback 序号**。
- **id 序列约定**：fallback `codex-{seq}`（adapter）与 `tailFallbackPrefix='codex'`（tailer）一致，且 fallback id 惰性求值——保证增量与全量（或重建）产出的消息 id 序列完全相同。
- **一致性验证**：`codex_ai_transcript_test.dart` 有 "line-parse matches adapter (tailer dialect)" 测试——逐行喂 `appendCodexJsonlEvent` 再 `finalizeAiMessagesForHistory`，与全量 parse 逐条比对 role / part 数量 / 文本 / toolName / toolCallId 全等。

## 已知陷阱

- **`arguments` 是 JSON 字符串不是对象**：夹具实测 `"arguments":"{\"cmd\":\"ls\"}"`；解析靠 `_parseArgs` 兜底 `jsonDecode`，非 JSON 字符串 → `args=null` 仅保留 `argsText`。
- **echo 双写**：旧版 codex 同一文本同时写 `response_item.message` 与 `event_msg.user_message` / `agent_message`（`response_item_message_echo.jsonl` 实测四行产出两条消息）——靠相邻重复检测丢弃后者。
- **reasoning 双写**：`response_item.reasoning` 与 `event_msg.agent_reasoning` 常同时出现——先到先得，按消息序列相邻比较去重（非全局去重）。
- **环境噪音**：user 文本含 `<environment_context>` 整个丢弃；AGENTS.md 注入 / developer 噪音（`<skills_instructions>` 等）不显示（`response_item_messages.jsonl` 测试断言 `developer noise` 不存在）。
- **多块 content**：`message.content[]` 只认 `input_text` / `output_text`，其余块类型忽略；多块文本以 `\n` 连接（同 user 事件里 AGENTS.md 与环境上下文被丢弃后只剩 `hello`）。
- **孤儿 output**：`function_call_output` 单独成行、靠 `call_id` 关联；无匹配 tool call 时静默忽略（不报错、不产生消息）。
- **截断回填：已调研不可行**：Codex 用 `NoOpToolResultEnricher`，工具输出截断占位不会被回填（claude 有 `ClaudeCompatibleToolResultEnricher`，codex 没有）。[truncation-backfill-audit.md](truncation-backfill-audit.md) 结论：737/37,266 条 `function_call_output` 被中段截断为 `…N tokens truncated…`，同会话无任何完整副本、无结构化标记字段——截断即永久丢失，无回填数据来源。
- **`custom_tool_call.input` 双形态**：`input` 既可能为 String（→ argsText）也可能为 Map（→ args），源码有分支处理但夹具暂无覆盖。
- **定位是暴力递归**：`locate` 递归扫描整个 `{CODEX_HOME}/sessions` 树；`persistedNativeId` 缺失时取字典序最大（时间戳前缀）——多会话同目录时靠文件名 UUID 区分，同名 UUID 只取一个。
