# 消息层统一实施计划（子项目 2/5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 审计并补齐 5 个 CLI（claude / codex / opencode / cursor / flashskyai）的 `AiTranscriptAdapter`，保证它们产出**语义一致**的 `AiMessage` 统一消息格式，为子项目 3（工具层）提供一致输入。

**Architecture:** 差异矩阵驱动（Task 1 产出审计矩阵，格式参考库 `docs/cli-formats/` 各页已含素材）；统一契约测试（Task 2）把"统一语义"变成可执行断言（TDD 载体）；Task 3-6 逐 CLI 按矩阵修复；Task 7 处理公共字段缺失（若有）；Task 8 收尾回填文档。

**Tech Stack:** Dart / flutter_test / ai_message_core（`AiMessage`、`AiToolCallPart`、`AiReasoningPart`、`finalizeAiMessagesForHistory`）/ 各 CLI adapter。

## Global Constraints

- 统一模型 `ai_message_core` 不改 schema——除非 Task 1 审计发现公共缺失（Task 7 才动）
- 不引入新的 CLI 硬编码：CLI 差异配置放各自 `capabilities/`，共享逻辑放 `ai_history/` 或 `ai_message_core`
- 消息 id 序列语义保持：增量 `lineAppend` 与全量 `parse` 同 id（`tailFallbackPrefix` 约束），修复不得破坏
- 修复必须伴随测试：每个修复先写失败断言，再改 adapter，最后既有测试 + 契约测试全绿
- 验证命令：`cd client && flutter test <具体测试文件>`；收尾全量 `flutter test --exclude-tags integration`
- commit 沿用仓库规范：`fix(history): <desc>` / `test(history): <desc>` / `docs(cli-formats): <desc>`
- 执行在隔离 worktree：`.worktrees/message-layer-audit`（分支 `message-layer-audit`）

---

### Task 1: 消息层差异矩阵审计

**Files:**
- Create: `docs/cli-formats/message-layer-audit.md`
- Research sources（只读）: 5 个 adapter 源码（`client/lib/services/cli/<cli>/capabilities/history/ai_transcript.dart`）、`client/packages/ai_message_core/lib/src/message.dart`、格式参考库 5 页（`docs/cli-formats/*.md`）

**Interfaces:**
- Consumes: 格式参考库各页（子项目 1 产出）
- Produces: `docs/cli-formats/message-layer-audit.md`（差异矩阵 + gap 清单）；Task 3-6 按此矩阵逐格修复；Task 8 回填结论列

- [ ] **Step 1: 通读素材**

读 `message.dart` 的 `AiMessage` / `AiMessagePart` 子类 / `finalizeAiMessagesForHistory`（约 :153-195），再通读 5 个 adapter 的 parse 路径与 `docs/cli-formats/*.md` 各页「消息 schema」章节。

- [ ] **Step 2: 写差异矩阵**

创建 `docs/cli-formats/message-layer-audit.md`，表格结构（每 CLI 一行）：

```markdown
# 消息层差异矩阵

**日期:** 2026-08-12
**来源:** 格式参考库各页 + 5 个 adapter 源码
**状态:** 审计中（Task 8 回填结论）

## 矩阵

| 维度 | claude | codex | opencode | cursor | flashskyai | 语义一致？ |
|------|--------|-------|----------|--------|------------|-----------|
| 消息 id 来源与优先级 | | | | | | |
| tool part 的 args 形态（Map / 字符串） | | | | | | |
| argsText 保留策略 | | | | | | |
| reasoning 映射（加密 thinking 处理） | | | | | | |
| tool part 挂载角色（是否仅 assistant） | | | | | | |
| toolCallId 来源与 fallback | | | | | | |
| result 回填机制（enricher） | | | | | | |
| status / isError 规范化 | | | | | | |
| 子代理附件（agentId 提取） | | | | | | |
| 增量/全量 id 一致性 | | | | | | |

## Gap 清单（Task 3-6 的修复依据）

| # | CLI | 维度 | 现状 | 应达到的语义 | 涉及函数 |
|---|-----|------|------|-------------|---------|
```

每个格子填「实测值 + 源码行号证据」。**「语义一致？」列如实写**：一致 / 不一致（详见 Gap 清单）。

- [ ] **Step 3: 交叉校验矩阵与源码**

矩阵每个「实测值」必须能 grep 回 adapter 源码行号；Gap 清单每条引用具体函数名。修正后再提交。

- [ ] **Step 4: 提交**

```bash
git add docs/cli-formats/message-layer-audit.md
git commit -m "docs(cli-formats): message layer audit matrix"
```

---

### Task 2: 统一格式契约测试

**Files:**
- Create: `client/test/services/cli/registry/capabilities/history/message_layer_contract_test.dart`
- Test: 同上

**Interfaces:**
- Consumes: 5 个 adapter（`ClaudeAiTranscriptAdapter` 等，均 `const` 构造 + `parse(AiTranscriptBundle)`）；`finalizeAiMessagesForHistory`（ai_message_core）
- Produces: `checkContract(label, messages)` 断言函数（Task 3-6 复用）；契约失败项 = 修复任务的目标清单

- [ ] **Step 1: 写契约测试（先跑通，作为统一语义的可执行定义）**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';

Future<AiTranscriptBundle> jsonlBundle(String adapterId, String path) async {
  return AiTranscriptBundle(
    adapterId: adapterId,
    fragments: [
      AiTranscriptFragment(name: path.split('/').last, bytes: await File(path).readAsBytes()),
    ],
  );
}

void checkContract(String label, List<AiMessage> messages) {
  final ids = <String>{};
  var toolParts = 0;
  for (final m in messages) {
    expect(m.id, isNotEmpty, reason: '$label: 消息 id 非空');
    expect(ids.add(m.id), isTrue, reason: '$label: 消息 id 唯一 ${m.id}');
    for (final part in m.parts) {
      if (part is AiToolCallPart) {
        toolParts++;
        expect(part.toolCallId, isNotEmpty, reason: '$label: toolCallId 非空');
        expect(part.toolName, isNotEmpty, reason: '$label: toolName 非空');
        expect(part.args, anyOf(isNull, isA<Map<String, Object?>>()),
            reason: '$label: args 必须是 Map 或 null，不得是裸字符串');
        if (part.result != null) {
          expect(part.status, isNot(AiToolCallStatus.running),
              reason: '$label: 有 result 的 tool call 不得是 running');
        }
      }
      if (part is AiTextPart) {
        expect(part.text, isNotEmpty, reason: '$label: 文本 part 非空');
      }
    }
  }
  expect(toolParts, greaterThan(0), reason: '$label: 夹具应包含工具调用');
  final finalized = finalizeAiMessagesForHistory(messages);
  for (final m in finalized) {
    final hasRunning = m.parts.any(
      (p) => p is AiToolCallPart && p.status == AiToolCallStatus.running,
    );
    final hasIncomplete = m.parts.any(
      (p) => p is AiToolCallPart && p.status == AiToolCallStatus.incomplete,
    );
    if (hasRunning || hasIncomplete) {
      expect(m.status, AiMessageStatus.incomplete,
          reason: '$label: 有未完成 tool part 的消息应为 incomplete');
    } else {
      expect(m.status, AiMessageStatus.complete,
          reason: '$label: 全部完成的夹具消息应为 complete');
    }
  }
}

void main() {
  test('claude: 统一契约', () async {
    final bundle = await jsonlBundle(
      'claude',
      'test/fixtures/session_history/claude/streamed_turn.jsonl',
    );
    checkContract('claude', await const ClaudeAiTranscriptAdapter().parse(bundle));
  });

  test('codex: 统一契约', () async {
    final bundle = await jsonlBundle(
      'codex',
      'test/fixtures/session_history/codex/reasoning_and_tools.jsonl',
    );
    checkContract('codex', await const CodexAiTranscriptAdapter().parse(bundle));
  });

  test('cursor: 统一契约', () async {
    final bundle = await jsonlBundle(
      'cursor',
      'test/fixtures/session_history/cursor/projects/home-me-proj/'
      'agent-transcripts/chat-aaaa-bbbb-cccc-dddd/chat-aaaa-bbbb-cccc-dddd.jsonl',
    );
    checkContract('cursor', await const CursorAiTranscriptAdapter().parse(bundle));
  });

  test('flashskyai: 统一契约', () async {
    final bundle = await jsonlBundle(
      'flashskyai',
      'test/fixtures/session_history/flashskyai/streamed_tools.jsonl',
    );
    checkContract('flashskyai', await const FlashskyaiAiTranscriptAdapter().parse(bundle));
  });

  test('opencode: 统一契约（JSON tree 布局）', () async {
    final bundle = AiTranscriptBundle(
      adapterId: 'opencode',
      fragments: [
        AiTranscriptFragment(
          name: 'message/msg_asst1.json',
          bytes: utf8.encode(jsonEncode({
            'id': 'msg_asst1',
            'role': 'assistant',
            'time': {'created': 1720612802000},
          })),
        ),
        AiTranscriptFragment(
          name: 'part/msg_asst1/prt_text1.json',
          bytes: utf8.encode(jsonEncode({
            'id': 'prt_text1',
            'messageID': 'msg_asst1',
            'type': 'text',
            'text': 'done',
          })),
        ),
        AiTranscriptFragment(
          name: 'part/msg_asst1/prt_tool1.json',
          bytes: utf8.encode(jsonEncode({
            'id': 'prt_tool1',
            'messageID': 'msg_asst1',
            'type': 'tool',
            'toolCallID': 'call_1',
            'tool': 'edit',
            'state': {
              'status': 'completed',
              'input': {'filePath': 'a.txt', 'oldString': 'x', 'newString': 'y'},
            },
          })),
        ),
      ],
    );
    checkContract('opencode', await const OpencodeAiTranscriptAdapter().parse(bundle));
  });
}
```

- [ ] **Step 2: 运行并记录失败项**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/message_layer_contract_test.dart`

预期：全部通过（或少量失败——失败项即 Gap 清单的实证，记录在报告里交给 Task 3-6）。**无论通过与否都要保留这个文件并提交**：通过 = 契约基线；失败 = 待修复清单。

- [ ] **Step 3: 提交**

```bash
git add client/test/services/cli/registry/capabilities/history/message_layer_contract_test.dart
git commit -m "test(history): unified message layer contract tests"
```

---

### Task 3: codex 修复

**Files:**
- Modify: `client/lib/services/cli/codex/capabilities/history/ai_transcript.dart`
- Test: `client/test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart`、契约测试

**Interfaces:**
- Consumes: Task 1 矩阵 codex 行 / Task 2 契约失败项
- Produces: codex adapter 语义与契约一致

**已知疑点（以矩阵实测为准）：**
- `_parseArgs`（约 :400-422）对 `arguments` 做 jsonDecode 兜底——确认 `args` 最终是 `Map<String, Object?>`，`argsText` 保留原始字符串
- `result` 回填：`NoOpToolResultEnricher`？确认有 result 的 tool call 的 `status` 不是 running
- reasoning：`agent_reasoning` / `reasoning` payload → `AiReasoningPart`

- [ ] **Step 1: 跑契约测试确认 codex 现状**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/message_layer_contract_test.dart --plain-name "codex"`

- [ ] **Step 2: 按矩阵修复（若契约失败或有 gap）**

对每个 gap：先在 `codex_ai_transcript_test.dart` 写失败断言（具体到字段），再修改 adapter，再跑既有测试确认无回归。

- [ ] **Step 3: 验证**

Run: `flutter test test/services/cli/registry/capabilities/history/message_layer_contract_test.dart test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart`

- [ ] **Step 4: 提交**

```bash
git add client/lib/services/cli/codex/ client/test/services/cli/registry/capabilities/history/
git commit -m "fix(history): align codex adapter with unified message contract"
```

（若契约已全绿且矩阵无 codex gap，跳过修复并提交空说明到报告，本任务以「验证通过」结束——无代码改动则不提交。）

---

### Task 4: cursor 修复

**Files:**
- Modify: `client/lib/services/cli/cursor/capabilities/history/ai_transcript.dart`（必要时 `.../side_resolver.dart`）
- Test: `client/test/services/cli/registry/capabilities/history/cursor_ai_transcript_test.dart`、契约测试

**Interfaces:**
- Consumes: Task 1 矩阵 cursor 行 / Task 2 契约失败项
- Produces: cursor adapter 语义与契约一致

**已知疑点（以矩阵实测为准）：**
- 消息 id 优先级与 Claude 相反（事件 uuid/id → 事件 id → `message.id` → fallback，约 :346-354）——确认 id 唯一性与增量/全量一致性不受影响
- 无 id tool_use fallback `{messageId}-tool-{seq}`（约 :249）——确认 toolCallId 非空
- args：`_asArgs` 非 Map 返回 null（约 :357-362）——确认不产出裸字符串 args
- `CursorTerminalToolResultEnricher` 从 `terminals/*.txt` 回填——确认有 result 时 status 非 running

- [ ] **Step 1: 跑契约测试确认 cursor 现状**
- [ ] **Step 2: 按矩阵修复（同 Task 3 流程：失败断言 → 修 adapter → 既有测试无回归）**
- [ ] **Step 3: 验证**（契约 + cursor 全部测试）
- [ ] **Step 4: 提交**（同 Task 3，commit 消息 `fix(history): align cursor adapter with unified message contract`）

---

### Task 5: opencode 修复

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart`
- Test: `client/test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart`、契约测试

**Interfaces:**
- Consumes: Task 1 矩阵 opencode 行 / Task 2 契约失败项
- Produces: opencode adapter 语义与契约一致

**已知疑点（以矩阵实测为准）：**
- part 类型：adapter 只消费 text / reasoning / tool（step-start / step-finish / patch 忽略）——确认忽略策略符合契约（文本 part 非空、reasoning → `AiReasoningPart`）
- args：`_asArgs(state['input'])`（约 :673）——确认 Map 或 null
- 子代理：`childSessionId` 从 `<task id="ses_…">` 正则或 `metadata.sessionId` 提取——确认 `AiSubagentAttachment` 的 agentId 非空语义
- camelCase key（filePath/oldString/newString/content）——属工具层（子项目 3），本任务不处理

- [ ] **Step 1: 跑契约测试确认 opencode 现状**
- [ ] **Step 2: 按矩阵修复（同 Task 3 流程）**
- [ ] **Step 3: 验证**（契约 + opencode 全部测试）
- [ ] **Step 4: 提交**（commit 消息 `fix(history): align opencode adapter with unified message contract`）

---

### Task 6: claude + flashskyai 修复

**Files:**
- Modify: `client/lib/services/cli/claude/capabilities/history/compatible_jsonl.dart`（共享解析，两 CLI 同源）
- Test: `client/test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart`、`flashskyai_ai_transcript_test.dart`、契约测试

**Interfaces:**
- Consumes: Task 1 矩阵 claude/flashskyai 行 / Task 2 契约失败项
- Produces: claude + flashskyai adapter 语义与契约一致

**已知疑点（以矩阵实测为准）：**
- 加密 thinking：无夹具场景，源码行为需在矩阵中记录（如丢弃 → 契约允许）；若有明文 reasoning 分支 → `AiReasoningPart`
- tool part 只挂 assistant 消息（compatible_jsonl.dart）
- `message['id']` 优先（约 :158）——与 cursor 反序，确认唯一性
- flashskyai 复用同一文件：claude 的修复自动作用于 flashskyai，需跑两个测试套件

- [ ] **Step 1: 跑契约测试确认 claude/flashskyai 现状**
- [ ] **Step 2: 按矩阵修复（同 Task 3 流程；一处修改两 CLI 受益）**
- [ ] **Step 3: 验证**（契约 + claude + flashskyai 全部测试）
- [ ] **Step 4: 提交**（commit 消息 `fix(history): align claude-compatible adapter with unified message contract`）

---

### Task 7: 共享字段补齐（若公共缺失）

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/message.dart`（或相关文件，仅当 Task 1 矩阵发现公共缺失）
- Modify: 受影响 adapter（同步新字段）
- Test: `client/packages/ai_message_core/test/` 相应测试

**Interfaces:**
- Consumes: Task 1 矩阵「Gap 清单」中标记为「公共缺失」的条目（例如：result 结构化 payload、session 元数据字段）
- Produces: `ai_message_core` 新增字段 + 类型（若确需）；同步后的 adapter；更新后的契约测试

- [ ] **Step 1: 对照矩阵 Gap 清单确认「公共缺失」条目**

仅当至少一个「公共缺失」条目存在时才执行本任务；否则在报告记录「无公共缺失，Task 7 跳过」，直接进入 Task 8。

- [ ] **Step 2: 在 ai_message_core 补字段（TDD）**

先写失败测试（`client/packages/ai_message_core/test/`），再在 `message.dart` 补字段（保持纯数据 + `copyWith` 模式），同步受影响 adapter 产出新字段，最后更新契约测试断言。

- [ ] **Step 3: 验证**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/message_layer_contract_test.dart` + 受影响 CLI 测试

- [ ] **Step 4: 提交**

```bash
git add client/packages/ai_message_core/ client/lib/services/cli/ client/test/
git commit -m "feat(history): add unified message fields for <字段名>"
```

---

### Task 8: 收尾 — 矩阵回填 + 全量验证

**Files:**
- Modify: `docs/cli-formats/message-layer-audit.md`（回填结论列与 Gap 状态）
- Review: 全部改动

**Interfaces:**
- Consumes: Task 1-7 全部产出
- Produces: 矩阵结论（每个 Gap 标记 已修复/接受差异/非公共缺失）；可交付状态

- [ ] **Step 1: 回填矩阵**

将「语义一致？」列改为最终结论，Gap 清单每条标记状态（已修复 + commit / 接受差异 + 理由）。

- [ ] **Step 2: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

- [ ] **Step 3: 提交**

```bash
git add docs/cli-formats/message-layer-audit.md
git commit -m "docs(cli-formats): finalize message layer audit conclusions"
```

## 完成定义

- [ ] `docs/cli-formats/message-layer-audit.md` 矩阵 10 维度 × 5 CLI 全部填写、Gap 清单全部有状态
- [ ] 契约测试 `message_layer_contract_test.dart` 全绿（5 CLI × 统一断言）
- [ ] 每个修复任务：失败断言 → 修复 → 既有测试无回归（报告记录）
- [ ] `flutter analyze` + 全量测试通过
- [ ] 产出物可支撑子项目 3（工具层迁移 + 补齐）在统一消息语义上推进
