# 截断回填可行性调研（codex P1 / opencode P2）

**日期:** 2026-08-13
**来源（本机真实数据，只读扫描）:**
- codex: `~/.codex/sessions/**/rollout-*.jsonl`（526 文件 / 198,801 记录，2026-03 ~ 2026-08）、`~/.codex/{thread_history_1,logs_2,state_5}.sqlite`、`~/.codex/{history,session_index}.jsonl`；安装版本 `codex-cli 0.147.0`（npm wrapper `@openai/codex`，truncation 在 Rust core）
- opencode: 个人库 `~/.local/share/opencode/opencode.db`（WAL；22,708 part / 5,671 message / 90 session；2026-07-21 ~ 2026-08-12，数据文件快照 `/tmp/opencode/live-backup.db`）、TeamPilot 会话 runtime 库 `…/sessions/3ae35a45-…/runtime/opencode/opencode.db`（10,686 part，数据文件快照 `/tmp/opencode/tp-runtime.db`）、`~/.local/share/opencode/tool-output/`（15 个完整输出文件）；安装版本 `opencode-ai 1.18.4`；源码 `~/git/opensource/opencode`（dev 分支，`f9ba23ab6`）
- 参考实现: `client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart`（`ClaudeCompatibleToolResultEnricher`）、`client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart`（`ToolResultEnricher` 接口）

**状态:** 调研结论已落地——opencode 按 §3.2 方案实现为 `OpencodeToolOutputBackfillEnricher`（子项目 Task 6，commits `f74e48c0` / `14ba676c`，挂载于 `opencode/capabilities/history/ai_history_capability.dart:15`）；codex 维持 §1.4 不可行结论（`NoOpToolResultEnricher` 不变）。§3.1「现状」为调研时点快照。

## 结论摘要

| CLI | 可行性 | 依据（一句话） |
|-----|--------|----------------|
| codex | **不可行**（截断即永久） | 737/37,266 条 `function_call_output` 被中段截断为 `…N tokens truncated…`（头尾 ~40KB）；同会话**无任何完整副本**（同 `call_id` 零重复、`exec_command_end.aggregated_output` 同为头部截断版 ≤10KB、sqlite/日志均无工具输出全文） |
| opencode | **有条件可行**（P2） | 核心截断服务把完整输出落盘到 `<data>/tool-output/tool_<id>`（实测 1 例，webfetch 171,512B 全文件在），占位文本含 `Full output saved to: <path>`；但有 **7 天保留期**限制，且工具内自截断（read/grep）无副本不可回填 |

---

## Step 1: codex 截断形态调查

### 1.1 扫描方法

```bash
grep -rl "truncated" ~/.codex/sessions/          # 候选文件（215 个）
# 逐文件逐行 jsonDecode，只统计 response_item.function_call_output：
#   payload 键集合 / output 中截断标记（regex）位置 / 同 call_id 出现次数 /
#   同 call_id 的 event_msg.exec_command_end.aggregated_output 是否截断
```

完整统计脚本在 `/tmp/opencode/codex_audit*.py`（本任务一次性审计脚本，未入库）。

### 1.2 统计

| 指标 | 数值 |
|------|------|
| rollout 文件总数 | 526（`~/.codex/sessions/2026/{03..08}` 日期分层） |
| 总记录数（顶层 type 分布） | 198,801 = session_meta 802 / event_msg 77,414 / response_item 118,120 / turn_context 2,350 / compacted 114 / world_state 1 |
| 含 "truncated" 的文件 | 215（含工具输出内容本身含 truncated 字样，见 1.4 排除项） |
| `function_call_output` 总数 | 37,266 |
| **被截断的 fco** | **737（1.98%）**，唯一 call_id 722 |
| fco payload 键集合 | 仅 `{type, call_id, output}`；极少数含 `internal_chat_message_metadata_passthrough`（67 例，用户消息用）与 `id`（1 例）——**无 usage / 无 truncation 标记字段** |

### 1.3 三问

**Q1: 截断占位文本形态？**

统一为**中段截断** `…N tokens truncated…`（Unicode 省略号包裹，N 为 token 数；`…252144 tokens truncated…` ~ `…65 tokens truncated…` 不等）。737 条全部命中，标记位置均值 **0.4996**（正中央），即**头尾各保留约一半、中间删除**；fco 总长集中在 36–40KB（len:40k=396、39k=156、38k=36、37k=38、36k=27），与 `tokens truncated` 数量无关——是按**固定长度上限**做头尾保留。另有少量 `…N chars truncated…`（9 例：1031626/4322/2279/1870×2/1447×4）为同一机制（个别工具的 output 按字符数截断）。13 条 fco output 非字符串（list）。

> 排除项：`...[truncated]` 字样仅出现在 2026-07-07 两个文件的 **user 消息文本内**（上游管线注入的上下文摘要），不是 codex 截断标记。

**Q2: 同会话是否有完整输出的副本？—— 没有。**

| 候选来源 | 结果 |
|----------|------|
| 同文件同 `call_id` 出现多次（一次截断 + 一次完整） | **0 例**——722 个唯一截断 call_id 全部只出现一次 |
| `event_msg.exec_command_end`（18,541 条；同 call_id 关联命中 375 条） | `aggregated_output` 为**头部截断版**：长度分布 max 10,025 / p90 9,938——与 fco 相同内容的更短版本，**非完整副本**（375/375 均截断） |
| `~/.codex/thread_history_1.sqlite`（thread_items 表） | 仅 7 行，最近 2 个线程的 userMessage/commandExecution/reasoning/agentMessage，无工具输出全文 |
| `~/.codex/logs_2.sqlite`（28,124 行） | 调试日志（session_loop 等），无工具输出 |
| `~/.codex/{history,session_index}.jsonl` | 用户消息与线程名索引，无工具输出 |
| `compacted` 记录（114 条） | 仅模型总结文本 + replacement_history，无原始输出 |

**Q3: 是否有 `call_id` 关联的扩展字段（usage / truncation 标记）？—— 没有。**

fco payload 键集合见 1.2；截断信息**只以文本形式嵌在 `output` 字符串里**，无结构化字段（无 `usage`、无 `truncated: true`、无 `output_path`）。

### 1.4 结论

**不可行。** codex 在 Rust core 侧将工具输出按固定长度做头尾保留并嵌入 `…N tokens truncated…` 标记后写入 rollout 持久化；**截断前的完整输出从未持久化**，任何地方都取不到副本。截断即永久丢失，无回填数据来源。

---

## Step 2: opencode 截断形态调查

### 2.1 扫描方法

```bash
sqlite3 "file:~/.local/share/opencode/opencode.db?mode=ro" .tables   # 只读连接
# part.data 逐行 jsonDecode，只统计 type=tool：
#   state.output 中的截断标记 / state.metadata.truncated / state.metadata.outputPath /
#   截断标记对应文件在 tool-output/ 是否存在
# 另扫 TeamPilot runtime 库（OPENCODE_DB=…/runtime/opencode/opencode.db，即 TeamPilot 实际加载的库）
```

### 2.2 统计

| 指标 | 个人库 | TeamPilot runtime 库 |
|------|--------|---------------------|
| part 总数 | 22,708 | 10,686 |
| tool part 数 | 5,604 | 3,096 |
| tool state 键集合 | `{status, input, output, metadata, title, time, error, raw}` | 同左 |
| output 长度分布 | p50 605 / p90 4,764 / p99 21,617 / max 75,698 | — |
| 含 "truncat" 的 tool output | 107 | 237 |
| 其中 **opencode 核心截断标记**（`...N lines/bytes truncated...` + hint） | **0** | **1**（webfetch，见 2.3） |
| `metadata.truncated == true` 的 tool | 822（read 780 / grep 42） | 119（read 112 / grep 6） |
| 其中带 `metadata.outputPath` | **0** | **1**（同核心截断那 1 例） |
| `tool-output/` 目录现存完整输出文件 | 15（51KB ~ 15.6MB） | — |

### 2.3 核心截断机制（源码 + 实测）

opencode 的核心截断服务在 `~/git/opensource/opencode/packages/opencode/src/tool/truncate.ts`（2026-01-07 引入 `feat: write truncated tool outputs to files (#7239)`；2026-03-17 effectify；2026-04-23 支持 `tool_output.max_lines/max_bytes` 配置）：

- 默认阈值 `MAX_LINES = 2000`、`MAX_BYTES = 50 * 1024`（`tool_output` 配置可覆盖）
- 超限时：**完整输出原样写入** `<Global.Path.data>/tool-output/tool_<ascending-id>`（`TRUNCATION_DIR`，文件名 `tool_` + 时间序 ID，**非 part id 也非 call_id**）；`state.output` 只留 preview + 占位：
  - 方向 head（默认）：`{preview}\n\n...{N} {bytes|lines} truncated...\n\n{hint}`，hint 含 **`Full output saved to: {绝对路径}`**
- `state.metadata` 同步写入 `truncated: true` + `outputPath: <绝对路径>`
- 保留期 **7 天**（`RETENTION = Duration.days(7)`），每小时清理一次过期文件
- 应用点：`tool/tool.ts:134`（常规工具输出）、`tool/registry.ts:182`（插件工具输出）、`session/tools.ts:179`（MCP 工具输入）

**实测全链路 1 例**（TeamPilot runtime 库，part `prt_ff6ac43e3001jbE30vnJae53ac`，webfetch，session `ses_0095e46efffeUILzbyg59LNa0R`）：

```
...120935 bytes truncated...

The tool call succeeded but the output was truncated. Full output saved to:
/home/hhoa/.local/share/opencode/tool-output/tool_ff6ac489d001xFtFocxqK3mvnn
```

- `metadata.truncated = true`、`metadata.outputPath = <上述路径>`（实测存在）
- 目标文件存在，171,512 B，即完整输出（webfetch 抓取的 Claude Code 系统提示全文）

### 2.4 三问结论

**Q1 截断形态？** 核心截断：`...N {bytes|lines} truncated...`（N 与单位二选一）+ `Full output saved to: <绝对路径>` hint。工具内自截断（非核心机制，语义上是有意的窗口视图）：grep 尾注 `(Results truncated: showing first N of M matches (M−N hidden). Consider using a more specific path or pattern.)`（`tool/grep.ts:133-136`，limit 100）；read 有 `... (line truncated to N chars)`（`tool/read.ts:16`）与 `file.more/file.cut` 窗口化。

**Q2 同会话有完整副本吗？** **有（仅核心截断）**：`tool-output/tool_<id>` 文件即完整输出，且路径可通过 `state.output` 的 hint 文本或 `state.metadata.outputPath` 取到。局限：**7 天保留期**（过期文件被清理，旧会话不可回填）；个人库现存 15 个文件均未超期。工具内自截断（read/grep）**无副本**。

**Q3 有 call_id 关联扩展字段吗？** **有**：`state.metadata.truncated` / `state.metadata.outputPath`（核心截断才有 outputPath；read/grep 只置 `truncated`）。

---

## Step 3: 方案设计

### 3.1 现状

- opencode 与 codex 的 history capability 目前都挂 `NoOpToolResultEnricher`（`opencode/capabilities/history/ai_history_capability.dart:15`、`codex/capabilities/history/ai_history_capability.dart:13`）
- 参考实现 `ClaudeCompatibleToolResultEnricher`（`client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart`）：对 result 含截断 sentinel（`'tool output truncated'`）的 `AiToolCallPart`，从 transcript 侧文件的 `toolUseResult` 取全文，`copyWith(result: 全文, status: complete, isError: …)` 回填
- 挂载点：`AiHistoryCapability.toolResultEnricher` → `AiHistoryLoader` 在 parse 后调用（`ai_history_loader.dart:459-489`；`requiresFilesystem=true` 的 enricher 留在 caller isolate 且 `ctx` 可用，worker isolate 只跑 bundle-only enricher）

### 3.2 opencode：实现 `OpencodeToolOutputBackfillEnricher`（可行）

**判定条件（何时回填）：**
- 命中 `AiToolCallPart.result`（即 adapter 直通 `state.output`，`ai_transcript.dart:864`）含核心截断占位 `...N {bytes|lines} truncated...`，**且**同一 result 内可提取 `Full output saved to: (\S+)` 绝对路径
- 路径存在且可读 → 回填；路径缺失/不可读（7 天保留期已过、远程清理）→ **保持占位不变**（正确语义：文件已删，回填即失败），仅记诊断日志
- 不处理 read/grep 等工具内自截断（无副本来源，语义上是有意的窗口视图）

**数据来源路径：** `ctx.fs.readBytes(<hint 中绝对路径>)`（`SessionHistoryContext.fs` 为 Filesystem 抽象，本地 / SSH/SFTP 均走同一接口——hint 是绝对路径，远端会话指向远端文件，天然支持）

**回填语义（对齐 Claude 参考）：** `part.copyWith(result: 完整内容, status: AiToolCallStatus.complete, isError: 保持原值)`；回填后占位与 hint 一并被全文替换

**接口约束：** `requiresFilesystem => true`（需读盘）→ 自动落入 caller isolate 路径（loader 已支持）；读文件失败抛异常不扩散（try/catch 返回原 messages，参考 `compatible_tool_result_enricher.dart:66-74`）

**挂载：** `OpencodeAiHistoryCapability(toolResultEnricher: OpencodeToolOutputBackfillEnricher())`

**风险与边界：**
- 7 天保留期是硬上限——回填只对"截断发生后 7 天内查看"的会话生效；旧会话保持占位（占位本身含 hint，可指导用户去文件查看）
- hint 文本本身是给 agent 的指引（"Use Grep…/delegate to explore agent"），回填后应被全文替换而非拼接
- 文件可能超大（实测 15.6MB）——回填时与现有 `result` 一样整体进 AiMessage，内存/渲染同现有大输出路径，无新增风险
- **增量刷新路径不回填**：loader 的 sqlite 行级增量刷新（`OpencodeHistoryIncrementalRefresher`）只合并新增/变更行，不跑 enricher——增量期间新增的截断 part 保持占位，直到下次全量 parse 才回填（enricher 仅在全量路径挂载）

### 3.3 codex：不可行，UI 层展示策略（建议）

- 现状信息量已可用：截断后仍保留头尾 ~40KB，且标记 `…N tokens truncated…` 明确告知中段删除量与位置
- 建议 UI 层把该标记渲染为显式提示（如"中间 N tokens 被截断"折叠提示），不要当作普通文本展示
- 长期选项（超出本任务范围，仅记录）：TeamPilot 自持 PTY，可在会话运行期于终端层截获完整工具输出另行落盘（类似 opencode tool-output 机制）；对历史会话无解

### 3.4 明确不做

- 不实现 codex enricher（无数据来源，违背"调研结论驱动、禁止无证据实现"约束）
- 不回填 opencode read/grep 工具内自截断（无副本，且为语义窗口）

---

## 附: 证据位置清单

| 证据 | 路径 |
|------|------|
| codex rollout 文件（526 个） | `~/.codex/sessions/2026/{03..08}/rollout-*.jsonl` |
| codex 其他存储（无完整输出） | `~/.codex/{thread_history_1,logs_2,state_5}.sqlite`、`~/.codex/{history,session_index}.jsonl` |
| codex 版本 | `codex-cli 0.147.0`（`~/.nvm/versions/node/v24.15.0/lib/node_modules/@openai/codex`） |
| opencode 个人库 | `~/.local/share/opencode/opencode.db`（快照 `/tmp/opencode/live-backup.db`） |
| opencode TeamPilot runtime 库 | `…/sessions/3ae35a45-…/runtime/opencode/opencode.db`（快照 `/tmp/opencode/tp-runtime.db`） |
| opencode 完整输出文件 | `~/.local/share/opencode/tool-output/tool_*`（15 个，实测含 webfetch 171,512B 全文件） |
| opencode 截断源码 | `~/git/opensource/opencode/packages/opencode/src/tool/truncate.ts`（dev `f9ba23ab6`） |
| opencode 版本 | `opencode-ai 1.18.4`（`~/.local/lib/node_modules/opencode-ai`） |
| 参考 enricher | `client/lib/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart` |
| enricher 接口与挂载 | `client/lib/services/cli/registry/capabilities/history/tool_result_enricher.dart`、`client/lib/services/session/ai_history_loader.dart:459-489` |
