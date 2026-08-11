# CLI 格式参考库实施计划（子项目 1/5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `docs/cli-formats/` 格式参考库（README 总览矩阵 + 5 个 CLI 页面），沉淀每个 CLI 的原生 transcript 位置、消息 schema、工具调用 schema，作为后续消息层/工具层补齐的单一事实来源。

**Architecture:** 纯文档子项目（spec `2026-08-12-cli-parsing-unification-design.md` 实施顺序第 1 步）。每页内容只允许来自两类来源：① 仓库内 adapter 源码（`client/lib/services/cli/<cli>/capabilities/history/`）② 仓库内测试夹具（`client/test/fixtures/session_history/<cli>/`，真实 JSONL 样本）。不修改任何 `.dart` 代码。

**Tech Stack:** Markdown、jq（JSONL 抽查）、grep/rg（文档表格与源码交叉校验）。

## Global Constraints

- 文档语言：中文（与 `docs/tool-call-parsing-convention.md` 一致）
- 每页内容必须逐条来自 adapter 源码或测试夹具；**禁止凭记忆写格式**
- 文档表格中的每个 tool name / arg key 必须能 grep 回源码（adapter、`SharedToolCallResolvers`、该 CLI 的 resolver 配置）
- 不修改任何 `.dart` 文件；不运行 flutter 命令
- commit 沿用仓库规范：`docs(cli-formats): <scope>: <description>`
- 统一页面模板（见 Task 2），5 个 CLI 页结构完全一致
- README 矩阵行在对应页面完成后回填，禁止提前填写

---

### Task 1: README.md 总览矩阵骨架

**Files:**
- Create: `docs/cli-formats/README.md`

**Interfaces:**
- Consumes: 无
- Produces: 总览矩阵（5 行）；后续每个页面任务回填本行；Task 6 校验矩阵无「待调研」残留

- [ ] **Step 1: 创建目录与 README**

创建 `docs/cli-formats/README.md`，内容为：

```markdown
# CLI 格式参考库

**日期:** 2026-08-12
**状态:** 建立中（每完成一页回填矩阵，Task 6 校验无残留）

各 CLI 原生 transcript 的消息格式与工具调用格式参考。统一解析体系设计见
[docs/superpowers/specs/2026-08-12-cli-parsing-unification-design.md](../superpowers/specs/2026-08-12-cli-parsing-unification-design.md)；
分层约定见 [docs/tool-call-parsing-convention.md](../tool-call-parsing-convention.md)。

## 总览矩阵

| CLI | transcript 位置 | 文件格式 | 消息 schema 页 | 解析入口 | 增量能力 | 状态 |
|-----|----------------|---------|---------------|---------|---------|------|
| claude | `{config}/projects/{bucket}/{taskId}.jsonl` | JSONL | [claude.md](claude.md) | `services/cli/claude/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| codex | `$CODEX_HOME/sessions/**/rollout-*.jsonl` | JSONL | [codex.md](codex.md) | `services/cli/codex/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| opencode | `$XDG_DATA_HOME/opencode/opencode.db` | SQLite(WAL) | [opencode.md](opencode.md) | `services/cli/opencode/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| cursor | `{configDir}/projects/{project}/agent-transcripts/…` | JSONL | [cursor.md](cursor.md) | `services/cli/cursor/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |
| flashskyai | `~/.flashskyai/projects/{bucket}/{id}.jsonl` | JSONL | [flashskyai.md](flashskyai.md) | `services/cli/flashskyai/capabilities/history/ai_transcript.dart` | 待调研 | 待调研 |

> 注：位置列来自 adapter 源码注释，各 CLI 页面需核实并给出实测结论；
> 「增量能力」= 该 CLI 的 `AiHistoryCapability.lineAppend` 是否非空（opencode 走 sqlite 增量 locate，需在页面中说明机制）。

## 新增 CLI

见 [adding-a-cli.md](adding-a-cli.md)（随子项目 4 落地）。
```

- [ ] **Step 2: 提交**

```bash
git add docs/cli-formats/README.md
git commit -m "docs(cli-formats): add overview matrix skeleton"
```

---

### Task 2: claude.md — Claude Code 格式参考页

**Files:**
- Create: `docs/cli-formats/claude.md`
- Research sources（只读）: `client/lib/services/cli/claude/capabilities/history/ai_transcript.dart`、`.../ai_history_capability.dart`、`.../compatible_jsonl.dart`、`.../compatible_side_resolver.dart`、`client/test/fixtures/session_history/claude/basic.jsonl`、`streamed_turn.jsonl`、`truncated_bash.jsonl`

**Interfaces:**
- Consumes: README 总览矩阵（Task 1）
- Produces: `claude.md`（模板见下）；回填 README claude 行（位置实测、格式、增量能力、状态 → 完成）

- [ ] **Step 1: 通读源码与夹具**

读 `client/lib/services/cli/claude/capabilities/history/` 下全部文件，重点提取：
- JSONL 每行的 `type` 枚举与各自结构（user / assistant / summary / system 等）
- `message.content` 中 block 的 `type` 枚举（text / tool_use / tool_result 等）
- 消息如何映射到 `AiMessage`（role、reasoning、tool call id/name/args、result、isError、status）
- 增量 `lineAppend` 与全量 parse 的分叉点、`tailFallbackPrefix` 值

再用 jq 抽查夹具（确认字段名与源码一致）：

```bash
cd client/test/fixtures/session_history/claude
jq -c '{type, role: .message.role, blocks: [.message.content[]?.type]}' basic.jsonl | head -20
jq -c 'select(.message.content != null) | .message.content[]? | select(.type=="tool_use") | {name, input}' basic.jsonl | head -10
jq -c 'select(.message.content != null) | .message.content[]? | select(.type=="tool_result") | {tool_use_id, is_error, content}' basic.jsonl | head -5
```

- [ ] **Step 2: 写 claude.md**

按以下统一模板写页面（表格内容以 Step 1 调研结果为准，**不得照抄模板示例值**）：

```markdown
# Claude Code 消息与工具调用格式参考

**日期:** 2026-08-12
**来源:** 夹具 `client/test/fixtures/session_history/claude/*.jsonl`、adapter `services/cli/claude/capabilities/history/ai_transcript.dart`

## Transcript 存储
| 项目 | 值 |
|---|---|
| 位置 | {config}/projects/{bucket}/{taskId}.jsonl（实测确认 bucket 规则） |
| 文件格式 | JSONL（每行一个事件） |
| 解析入口 | ClaudeAiTranscriptAdapter / ClaudeAiHistoryCapability |
| 增量能力 | lineAppend 有/无 + tailFallbackPrefix 值 |

## 消息 schema
| JSONL 事件 type | 关键字段 | AiMessage 映射 | 说明 |
|---|---|---|---|
| user | message.content[].type=text | AiTextPart(role=user) | 含 input_text 等附件的处理? |
| assistant | message.content[].type=text | AiTextPart | |
| assistant | content[].type=tool_use | AiToolCallPart | 逐列填 id/name/args/result 来源 |
| assistant | content[].type=reasoning? | AiReasoningPart | 若存在 |

## 工具调用 schema
| tool name | args 关键 key | 解析类别 | 解析器配置位置 |
|---|---|---|---|
| （夹具与源码中实际出现的每个 tool name 一行） | | | |

## Reasoning / 子代理形态
（source 行 type、subagents/ 目录、Task 工具、journal.jsonl 等实际机制）

## 增量 vs 全量
（lineAppend 消费哪些事件、返回 false 的元数据事件、id 序列约定）

## 已知陷阱
（截断行、加密 thinking、嵌套 tool_result 等调研中发现的问题）
```

- [ ] **Step 3: 交叉校验文档与源码**

文档表格里每个 tool name / arg key 逐条 grep 回源码；adapter 中出现的 tool name 常量也要在表格中：

```bash
# 文档→源码：逐个工具名验证（Bash 只是示例，以文档实际内容为准）
for name in Bash Edit Read TodoWrite Task; do
  rg -l "\b${name}\b" client/lib/services/cli/claude/ | head -2
done
# 源码→文档：adapter 中字面量工具名是否都在文档里
rg -o 'case "[A-Za-z_]+"|"[A-Za-z_]+"' client/lib/services/cli/claude/capabilities/history/ai_transcript.dart | sort -u
```

若发现文档表格与源码不一致，修正文档。**本步骤结论是硬校验，不一致即不通过。**

- [ ] **Step 4: 回填 README claude 行并提交**

把 claude 行的「增量能力」「状态」两列改为实测值（状态 → 完成），位置列若与实测不符一并修正。然后：

```bash
git add docs/cli-formats/claude.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): add claude format reference"
```

---

### Task 3: codex.md — Codex 格式参考页

**Files:**
- Create: `docs/cli-formats/codex.md`
- Research sources（只读）: `client/lib/services/cli/codex/capabilities/history/ai_transcript.dart`、`.../ai_history_capability.dart`、`.../side_resolver.dart`、`client/test/fixtures/session_history/codex/basic.jsonl`、`response_item_messages.jsonl`、`response_item_message_echo.jsonl`、`reasoning_and_tools.jsonl`

**Interfaces:**
- Consumes: README 总览矩阵
- Produces: `codex.md`（与 Task 2 相同模板）；回填 README codex 行

- [ ] **Step 1: 通读源码与夹具**

读 `client/lib/services/cli/codex/capabilities/history/` 下全部文件，重点提取：
- rollout JSONL 行结构（`type: response_item` + `payload` 的嵌套），payload 的 `type` 枚举（message / reasoning / function_call / function_call_output / local_shell_call 等）
- `_rolloutId` 正则与会话关联方式
- 消息映射：function_call 的 `name`/`arguments`（注意 arguments 是字符串还是对象）、function_call_output 与 result 的关联（call_id）
- 增量 `lineAppend` 与全量 parse 的分叉点

用 jq 抽查夹具：

```bash
cd client/test/fixtures/session_history/codex
jq -c '{type, payload_type: .payload.type, role: .payload.role}' response_item_messages.jsonl | head -15
jq -c 'select(.payload.type=="function_call") | {name: .payload.name, args: .payload.arguments}' reasoning_and_tools.jsonl | head -10
jq -c 'select(.payload.type=="function_call_output") | {call_id, output}' reasoning_and_tools.jsonl | head -5
jq -c 'select(.payload.type=="reasoning") | keys' reasoning_and_tools.jsonl | head -3
```

- [ ] **Step 2: 写 codex.md**（同一模板，内容以调研为准）
- [ ] **Step 3: 交叉校验文档与源码**

```bash
for name in shell apply_patch read grep glob task web_search web_fetch; do
  rg -l "\b${name}\b" client/lib/services/cli/codex/ | head -2
done
rg -o '"[A-Za-z_]+"' client/lib/services/cli/codex/capabilities/history/ai_transcript.dart | sort -u
```

- [ ] **Step 4: 回填 README codex 行并提交**

```bash
git add docs/cli-formats/codex.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): add codex format reference"
```

---

### Task 4: opencode.md — opencode 格式参考页

**Files:**
- Create: `docs/cli-formats/opencode.md`
- Research sources（只读）: `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart`（重点：sqlite 表结构、JSON 内容列）、`.../side_resolver.dart`、`.../native_session_id.dart`、`client/test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart`（测试内嵌样本）、`client/lib/services/cli/opencode/capabilities/history_context_env.dart`

**Interfaces:**
- Consumes: README 总览矩阵
- Produces: `opencode.md`；回填 README opencode 行

- [ ] **Step 1: 通读源码与测试样本**

读 `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart` 与 `opencode_ai_transcript_test.dart`，重点提取：
- `opencode.db` 的表名、关键列（message 表的 role / content / time / modelID 等，part 表若存在）
- content 列内 JSON 的 part 结构：`text` / `reasoning` / `tool` part 的字段（toolCallID / name / arguments / state / result）
- 全量 locate 与增量 sqlite locate（`id > afterMessageId`）的分叉
- tool 参数 key 是 camelCase（filePath / oldString / newString / content）——与 snake_case 差异在页面突出说明

若本机有 opencode 数据可抽查：

```bash
ls ~/.local/share/opencode/opencode.db 2>/dev/null && sqlite3 ~/.local/share/opencode/opencode.db ".schema message" && sqlite3 ~/.local/share/opencode/opencode.db "select role, substr(content,1,200) from message limit 5;"
```

（无本机数据则完全以测试样本 + 源码为准，页面「来源」注明。）

- [ ] **Step 2: 写 opencode.md**（同一模板；「文件格式」列写 SQLite；「增量能力」列说明 lineAppend 为 null、走 sqlite 增量 locate + liveCacheToken 的机制）
- [ ] **Step 3: 交叉校验文档与源码**

```bash
rg -o "'[a-zA-Z_]+'" client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart | sort -u
# 并把文档中每个 tool name（edit/write/read/bash/task 等）逐条 grep 回 opencode/ 目录
```

- [ ] **Step 4: 回填 README opencode 行并提交**

```bash
git add docs/cli-formats/opencode.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): add opencode format reference"
```

---

### Task 5: cursor.md — Cursor 格式参考页

**Files:**
- Create: `docs/cli-formats/cursor.md`
- Research sources（只读）: `client/lib/services/cli/cursor/capabilities/history/ai_transcript.dart`、`.../side_resolver.dart`、`.../ai_history_capability.dart`、`client/lib/services/cli/cursor/capabilities/history_context_env.dart`（含 configDir 解析）、`client/test/fixtures/session_history/cursor/`（三个夹具：`agent_transcript_no_tool_id.jsonl`、`projects/home-me-proj/agent-transcripts/chat-aaaa-bbbb-cccc-dddd/…jsonl`、`chat-shell-missing-result/…jsonl`）

**Interfaces:**
- Consumes: README 总览矩阵
- Produces: `cursor.md`；回填 README cursor 行

- [ ] **Step 1: 通读源码与夹具**

读 cursor history 相关文件，重点提取：
- configDir 解析（`CursorWindowsHomeJunction.resolveCursorConfigDir`）、chats/meta.json 与 project 的关联
- agent JSONL 行的结构与 claude 的异同（role + content blocks）
- 工具调用 args 是字符串还是对象（夹具 `agent_transcript_no_tool_id.jsonl` 暗示无 id 场景）
- tool_result 缺失的容错（`chat-shell-missing-result` 夹具）
- 增量 `lineAppend` 与全量 parse 的分叉点

用 jq 抽查夹具：

```bash
cd client/test/fixtures/session_history/cursor
jq -c '{type, role, blocks: [.content[]?.type]}' projects/home-me-proj/agent-transcripts/chat-aaaa-bbbb-cccc-dddd/chat-aaaa-bbbb-cccc-dddd.jsonl | head -15
jq -c '.content[]? | select(.type=="tool_use") | {name, input}' projects/home-me-proj/agent-transcripts/chat-aaaa-bbbb-cccc-dddd/chat-aaaa-bbbb-cccc-dddd.jsonl | head -10
```

- [ ] **Step 2: 写 cursor.md**（同一模板）
- [ ] **Step 3: 交叉校验文档与源码**

```bash
rg -o '"[A-Za-z_]+"' client/lib/services/cli/cursor/capabilities/history/ai_transcript.dart | sort -u
# 文档中每个 tool name 逐条 grep 回 cursor/ 目录
```

- [ ] **Step 4: 回填 README cursor 行并提交**

```bash
git add docs/cli-formats/cursor.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): add cursor format reference"
```

---

### Task 6: flashskyai.md — FlashskyAI 格式参考页

**Files:**
- Create: `docs/cli-formats/flashskyai.md`
- Research sources（只读）: `client/lib/services/cli/flashskyai/capabilities/history/ai_transcript.dart`、`.../ai_history_capability.dart`、`client/lib/services/cli/claude/capabilities/history/compatible_jsonl.dart`（复用）、`client/test/fixtures/session_history/flashskyai/basic.jsonl`、`streamed_tools.jsonl`

**Interfaces:**
- Consumes: README 总览矩阵
- Produces: `flashskyai.md`；回填 README flashskyai 行

- [ ] **Step 1: 通读源码与夹具**

读 flashskyai history 文件 + 复用的 `compatible_jsonl.dart`，重点提取：
- 与 Claude 格式的相同点/差异点（同 shapes 但 tool name 可能是自研命名）
- `projects` 与 `workspaces` 双探针布局
- 流式工具调用形态（`streamed_tools.jsonl` 夹具）

用 jq 抽查夹具：

```bash
cd client/test/fixtures/session_history/flashskyai
jq -c '{type, role: .message.role, blocks: [.message.content[]?.type]}' basic.jsonl | head -20
jq -c '.message.content[]? | select(.type=="tool_use") | {name, input}' streamed_tools.jsonl | head -10
```

- [ ] **Step 2: 写 flashskyai.md**（同一模板；「工具调用 schema」逐行列出夹具实际出现的 tool name 与 args key）
- [ ] **Step 3: 交叉校验文档与源码**

```bash
rg -o '"[A-Za-z_]+"' client/lib/services/cli/flashskyai/capabilities/history/ai_transcript.dart | sort -u
# 文档中每个 tool name 逐条 grep 回 flashskyai/ 与 claude/compatible_jsonl.dart
```

- [ ] **Step 4: 回填 README flashskyai 行并提交**

```bash
git add docs/cli-formats/flashskyai.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): add flashskyai format reference"
```

---

### Task 7: 收尾校验 — 矩阵完整性与跨页一致性

**Files:**
- Review: `docs/cli-formats/README.md` + 5 个页面（只读校验，不修改代码）

**Interfaces:**
- Consumes: Task 2-6 全部页面
- Produces: 校验结论；若发现 README 矩阵残留「待调研」则修正并提交

- [ ] **Step 1: 校验矩阵完整性**

```bash
cd /home/hhoa/git/hhoa/teampilot
rg '待调研' docs/cli-formats/README.md && echo 'FAIL: 有残留' || echo 'PASS: 矩阵完整'
```

预期：PASS（5 行状态均为「完成」，增量能力均有实测值）。

- [ ] **Step 2: 校验 5 个页面模板一致性**

```bash
for f in claude codex opencode cursor flashskyai; do
  echo "== $f =="; rg -c '^## (Transcript 存储|消息 schema|工具调用 schema|Reasoning / 子代理|增量 vs 全量|已知陷阱)' docs/cli-formats/$f.md
done
```

预期：每页 6 个章节标题各出现一次（`##` 标题共 6 个）。

- [ ] **Step 3: 校验工具名跨页去重与共享配置一致**

将 5 页「工具调用 schema」表格中的 tool name 汇总，与 `client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart` 的 `toolNames` 集合对比：共享配置里的每个 tool name 必须至少在一个 CLI 页表格中出现；反之每页表格的每个 tool name 都能在源码中找到（Step 2-6 已逐页校验，本步骤做汇总抽查，抽查量 ≥ 10 个工具名）。

```bash
rg -n 'toolNames:|pathKeys:|oldStringKeys:|newStringKeys:|contentKeys:|shellToolNames' client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart
```

- [ ] **Step 4: 检查 git 历史并提交修正（如有）**

```bash
git log --oneline -8 -- docs/cli-formats/
```

预期：至少 6 个 commit（README + 5 页）。若 Step 1-3 有修正，合并提交：

```bash
git add docs/cli-formats/
git commit -m "docs(cli-formats): finalize matrix and cross-page consistency"
```

## 完成定义

- [ ] `docs/cli-formats/README.md` 矩阵 5 行全部「完成」，无「待调研」残留
- [ ] 5 个 CLI 页面结构一致（6 个章节），内容全部经源码/夹具核实
- [ ] 每页工具名/arg key 均 grep 回源码验证通过
- [ ] 产出物可作为子项目 2（消息层审计补齐）与子项目 3（工具层迁移+补齐）的输入：差异矩阵与工具调用覆盖矩阵从各页表格汇总得出
