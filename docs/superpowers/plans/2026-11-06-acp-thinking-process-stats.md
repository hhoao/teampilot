# ACP 思考过程折叠确定性统计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 ACP 会话最后一个思考过程折叠头显示「思考过程 · N 步 · 本轮共 M 次工具调用」，PTY 会话行为完全不变。

**Architecture:** 在 `ai_message_ui` 共享包新增两个带默认值的可选扩展（`AiMessageStrings.formatThinkingProcessStats` hook 与 `AiChainOfThoughtView.toolCallCount`），由 `AiMessageParts` 从整条消息统计 `AiToolCallPart` 数量并只传给最后一个 CoT 节点；app 层仅对 ACP 会话注入 hook 与 l10n 文案。hook 为 `null` 时 phrase 计算逐字不变，因此 PTY 零外溢。不标注 `category`、不碰 `summarizeThinkingProcess` / resolver / 折叠集合。

**Tech Stack:** Flutter / Dart；本地 package `ai_message_core` + `ai_message_ui`；`flutter_localizations` gen-l10n；`client/tool/run_tests.dart` 测试入口。

## Global Constraints

- **禁止直接 `flutter test`**：一律 `cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart <paths/options>`；并发直接运行会破坏共享 build cache。
- **测试循环：快内层、慢外层**。内层 `flutter analyze`；用**单个测试文件**验证行为，需要时用 `--plain-name="..."` 收窄；完整套件仅在收尾前跑一次，后台运行。
- **收尾前**：`cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`。
- **l10n**：只编辑 `client/lib/l10n/app_en.arb` 与 `client/lib/l10n/app_zh.arb`；`app_localizations.dart` / `app_localizations_en.dart` / `app_localizations_zh.dart` 由 `flutter gen-l10n` 生成后提交。
- **工作区含多个与本任务无关的未提交改动**（文件与数量会随其他工作流变化，开工前自行 `git status --short` 重新确认；`session_chat_message_area.dart` 等文件可能再次变脏）。所有修改必须用 `Edit` 精确替换，**禁止 Write 整文件、禁止 `git add -A`、禁止 `git checkout --` 覆盖他人改动**；每个 commit 只 `git add` / `git commit --` 本任务列出的精确路径，提交前 `git diff` 核对不含无关改动。
- **并行改动**：`docs/superpowers/plans/2026-11-06-cot-completed-reasoning-fold.md` 也改 `chain_of_thought_view.dart`。开工前先 `git status --short` 确认该文件无未提交改动；若有，先协调那份改动落地再继续。本计划基于当前 HEAD 版本（该文件仍是 `for (final part in widget.parts)` 无索引遍历）。
- 不标注 `AiToolCallPart.category`，不改 `LayoutPreferences.foldToolCallCategories`，不改 `summarizeThinkingProcess`，不改任何 resolver。
- PTY 会话折叠头文案、折叠行为、工具统计与改动前逐字一致；ACP 工具卡仍独立显示。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `client/packages/ai_message_ui/lib/src/strings.dart` | 新增可选 `formatThinkingProcessStats` hook（`null` = 不启用） |
| `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart` | 新增 `toolCallCount`，phrase 计算改三段（summary → stats → steps） |
| `client/packages/ai_message_ui/lib/src/ai_message_parts.dart` | 统计整条消息工具数、独立算最后链下标、传参、`_NodeKey` 纳入计数 |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 新增统计文案 + `@` 占位符元数据 |
| `client/lib/l10n/app_localizations*.dart`（3 个，生成） | `aiMessageThinkingProcessStats(int steps, int toolCalls)` |
| `client/lib/pages/chat/ai_message_strings_from_l10n.dart` | 新增 `thinkingProcessToolCalls` 开关，映射 l10n → hook |
| `client/lib/pages/chat/session_chat_message_area.dart` | 按 `isAcpChatSession(session)` 启用开关 |
| `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart` | view 层 TDD |
| `client/packages/ai_message_ui/test/ai_message_parts_test.dart` | 分组/缓存层 TDD |
| `client/test/pages/chat/ai_message_strings_from_l10n_test.dart`（新建） | app 层开关 TDD |

---

### Task 1: 共享包 hook 与折叠头文案

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/strings.dart:27-28`, `:78-79`
- Modify: `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart:16-22`, `:62-67`
- Test: `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`

**Interfaces:**
- Consumes: `AiMessageStrings.of(BuildContext)`（`strings.dart:178`），无 scope 时返回 `const AiMessageStrings()`。
- Produces:
  - `AiMessageStrings.formatThinkingProcessStats` — `String Function(int steps, int toolCalls)?`，默认 `null`。
  - `AiChainOfThoughtView.toolCallCount` — `int`，默认 `0`。
  - `_statsLabel(int steps, int toolCalls)` — 测试用顶层函数，返回 `'Thinking process · $steps steps · $toolCalls tool calls'`。

- [ ] **Step 1: 写失败测试**

在 `chain_of_thought_view_test.dart` 的 `main()` 末尾（`reasoning body folds when streaming stops` 测试之后、`}` 之前）插入以下测试，并在文件末尾（`main()` 之外）加入顶层 `_statsLabel`：

```dart
  testWidgets('Cot trigger keeps steps phrase when stats hook is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiChainOfThoughtView(
            parts: [AiReasoningPart(text: 'thought')],
            toolCallCount: 3,
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 1 steps'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot trigger uses stats hook when toolCallCount is positive', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageStringsScope(
            strings: const AiMessageStrings(
              formatThinkingProcessStats: _statsLabel,
            ),
            child: AiChainOfThoughtView(
              parts: const [AiReasoningPart(text: 'thought')],
              toolCallCount: 3,
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Thinking process · 1 steps · 3 tool calls'),
      findsOneWidget,
    );
  });

  testWidgets('Cot trigger falls back to steps when toolCallCount is zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageStringsScope(
            strings: const AiMessageStrings(
              formatThinkingProcessStats: _statsLabel,
            ),
            child: AiChainOfThoughtView(
              parts: const [AiReasoningPart(text: 'thought')],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Thinking process · 1 steps'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot trigger prefers summary over stats hook', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageStringsScope(
            strings: const AiMessageStrings(
              formatThinkingProcessStats: _statsLabel,
            ),
            child: AiChainOfThoughtView(
              parts: const [
                AiReasoningPart(text: 'thought'),
                AiToolCallPart(
                  toolCallId: 'e1',
                  toolName: 'Edit',
                  category: AiToolCallCategory.edit,
                ),
              ],
              toolCallCount: 3,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Edited 1 file'), findsOneWidget);
    expect(find.textContaining('tool calls'), findsNothing);
  });

  testWidgets('Cot stats refresh without resetting manual open state', (
    tester,
  ) async {
    Widget build(int count) => MaterialApp(
      home: Scaffold(
        body: AiMessageStringsScope(
          strings: const AiMessageStrings(
            formatThinkingProcessStats: _statsLabel,
          ),
          child: AiChainOfThoughtView(
            parts: const [AiReasoningPart(text: 'thought')],
            toolCallCount: count,
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Thinking process'));
    await tester.pumpAndSettle();
    expect(find.textContaining('thought'), findsOneWidget);

    await tester.pumpWidget(build(3));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 steps · 3 tool calls'), findsOneWidget);
    expect(find.textContaining('thought'), findsOneWidget);
  });
```

在文件末尾追加：

```dart
String _statsLabel(int steps, int toolCalls) =>
    'Thinking process · $steps steps · $toolCalls tool calls';
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart
```

Expected: FAIL，编译错误 —— `AiMessageStrings` 未定义 `formatThinkingProcessStats`，`AiChainOfThoughtView` 未定义 `toolCallCount`。

- [ ] **Step 3: 实现最小代码**

`strings.dart` 构造函数，把：

```dart
    this.formatThinkingProcessSteps = _defaultThinkingProcessSteps,
    this.formatThinkingProcessSummary = defaultThinkingProcessSummaryLabel,
```

改为：

```dart
    this.formatThinkingProcessSteps = _defaultThinkingProcessSteps,
    this.formatThinkingProcessSummary = defaultThinkingProcessSummaryLabel,
    this.formatThinkingProcessStats,
```

`strings.dart` 字段区，把：

```dart
  final String Function(Object count) formatThinkingProcessSteps;
  final AiThinkingProcessSummaryFormatter formatThinkingProcessSummary;
```

改为：

```dart
  final String Function(Object count) formatThinkingProcessSteps;
  final AiThinkingProcessSummaryFormatter formatThinkingProcessSummary;
  final String Function(int steps, int toolCalls)? formatThinkingProcessStats;
```

`chain_of_thought_view.dart` 构造与字段，把：

```dart
  const AiChainOfThoughtView({
    required this.parts,
    this.autoExpand = false,
    super.key,
  });

  final List<AiMessagePart> parts;
```

改为：

```dart
  const AiChainOfThoughtView({
    required this.parts,
    this.autoExpand = false,
    this.toolCallCount = 0,
    super.key,
  });

  final List<AiMessagePart> parts;

  /// Total [AiToolCallPart]s in the owning message. Non-zero only on the last
  /// chain; renders the stats phrase instead of the steps phrase when the host
  /// supplies [AiMessageStrings.formatThinkingProcessStats].
  final int toolCallCount;
```

`chain_of_thought_view.dart` 的 phrase 计算（`:62-67`），把：

```dart
    final phrase = formatted.isNotEmpty
        ? formatted
        : strings.formatThinkingProcessSteps(widget.parts.length);
```

改为：

```dart
    final stats = strings.formatThinkingProcessStats;
    final phrase = formatted.isNotEmpty
        ? formatted
        : (stats != null && widget.toolCallCount > 0
            ? stats(widget.parts.length, widget.toolCallCount)
            : strings.formatThinkingProcessSteps(widget.parts.length));
```

`didUpdateWidget`、`semanticsLabel`、`showDiff` 均不动。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart
```

Expected: PASS，`All tests passed!`（含该文件的既有用例全部仍通过，即 PTY 默认路径未回归）。

- [ ] **Step 5: 提交**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/packages/ai_message_ui/lib/src/strings.dart client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart client/packages/ai_message_ui/test/chain_of_thought_view_test.dart && git commit -m "feat(ai_message_ui): optional thinking-process stats hook" -- client/packages/ai_message_ui/lib/src/strings.dart client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart client/packages/ai_message_ui/test/chain_of_thought_view_test.dart
```

---

### Task 2: 分组层统计与缓存键

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_parts.dart:50-86`, `:97-107`, `:110-144`
- Test: `client/packages/ai_message_ui/test/ai_message_parts_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `AiMessageStrings.formatThinkingProcessStats` 与 `AiChainOfThoughtView.toolCallCount`。
- Produces: 无新公开接口；`AiMessageParts` 内部把 `toolCallCount` 传给默认 CoT 构建器分支。
- 关键约束：**不能复用 `_lastChainOfThoughtIndex`**（`ai_message_parts.dart:90` 在 `chainOfThoughtAutoExpand == false` 时返回 -1）；本任务新增独立的「最后一个 CoT 节点下标」计算。

- [ ] **Step 1: 写失败测试**

在 `ai_message_parts_test.dart` 的 `main()` 末尾插入，并在文件末尾追加顶层 `_statsLabel`：

```dart
  testWidgets('only the last chain shows the message tool-call count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiMessageStringsScope(
          strings: const AiMessageStrings(
            formatThinkingProcessStats: _statsLabel,
          ),
          child: AiToolCallFoldScope(
            shouldFold: (_) => false,
            child: Scaffold(
              body: AiMessageView(
                message: AiMessage(
                  id: 'a1',
                  role: AiRole.assistant,
                  parts: const [
                    AiReasoningPart(text: 'first chain'),
                    AiToolCallPart(toolCallId: 'c1', toolName: 'Tool'),
                    AiReasoningPart(text: 'second chain'),
                    AiToolCallPart(toolCallId: 'c2', toolName: 'Tool'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('tool calls'), findsOneWidget);
    expect(find.textContaining('1 steps · 2 tool calls'), findsOneWidget);
    expect(
      find.textContaining('Thinking process · 1 steps'),
      findsNWidgets(2),
    );
  });

  testWidgets('chain stats refresh when tool-call count grows', (tester) async {
    Widget build(int toolCount) => MaterialApp(
      home: AiMessageStringsScope(
        strings: const AiMessageStrings(
          formatThinkingProcessStats: _statsLabel,
        ),
        child: AiToolCallFoldScope(
          shouldFold: (_) => false,
          child: Scaffold(
            body: AiMessageView(
              message: AiMessage(
                id: 'a1',
                role: AiRole.assistant,
                parts: [
                  const AiReasoningPart(text: 'chain'),
                  for (var i = 0; i < toolCount; i++)
                    AiToolCallPart(toolCallId: 'c$i', toolName: 'Tool'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 steps · 1 tool calls'), findsOneWidget);

    await tester.pumpWidget(build(3));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 steps · 3 tool calls'), findsOneWidget);
  });
```

文件末尾追加：

```dart
String _statsLabel(int steps, int toolCalls) =>
    'Thinking process · $steps steps · $toolCalls tool calls';
```

（`const AiReasoningPart(text: 'chain')` 在两次 `build` 中是同一常量实例，因此 `_NodeKey.parts` 不变；只有 `toolCallCount` 能触发缓存键变化 —— 这正是第二个测试要锁住的行为。）

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart packages/ai_message_ui/test/ai_message_parts_test.dart
```

Expected: FAIL —— 两个新增用例都找不到 `tool calls` 文案（此时 `AiMessageParts` 尚未传 `toolCallCount`）。

- [ ] **Step 3: 实现最小代码**

`ai_message_parts.dart` 的 `build()`：在 `final lastChainIndex = _lastChainOfThoughtIndex(nodes);` 之后插入：

```dart
    final toolCallCount = widget.parts.whereType<AiToolCallPart>().length;
    var lastStatsChainIndex = -1;
    for (var i = nodes.length - 1; i >= 0; i--) {
      if (nodes[i] is AiRenderChainOfThought) {
        lastStatsChainIndex = i;
        break;
      }
    }
```

`build()` 循环内做三处精确替换（不要动循环之前已声明的 `final liveKeys = <_NodeKey>{};`）：

替换一，把：

```dart
      final autoExpand = i == lastChainIndex;
```

改为：

```dart
      final autoExpand = i == lastChainIndex;
      final nodeToolCallCount =
          i == lastStatsChainIndex ? toolCallCount : 0;
```

替换二，把：

```dart
      final key = _NodeKey(node, autoExpand: autoExpand);
```

改为：

```dart
      final key = _NodeKey(
        node,
        autoExpand: autoExpand,
        toolCallCount: nodeToolCallCount,
      );
```

替换三，把：

```dart
        child = _buildNode(context, node, autoExpand: autoExpand);
```

改为：

```dart
        child = _buildNode(
          context,
          node,
          autoExpand: autoExpand,
          toolCallCount: nodeToolCallCount,
        );
```

`_buildNode` 签名与默认 CoT 分支，把：

```dart
  Widget _buildNode(
    BuildContext context,
    AiRenderNode node, {
    required bool autoExpand,
  }) {
    if (node is AiRenderChainOfThought &&
        widget.registry.chainOfThoughtBuilder == null) {
      return AiChainOfThoughtView(parts: node.parts, autoExpand: autoExpand);
    }
    return widget.registry.buildNode(context, node);
  }
```

改为：

```dart
  Widget _buildNode(
    BuildContext context,
    AiRenderNode node, {
    required bool autoExpand,
    required int toolCallCount,
  }) {
    if (node is AiRenderChainOfThought &&
        widget.registry.chainOfThoughtBuilder == null) {
      return AiChainOfThoughtView(
        parts: node.parts,
        autoExpand: autoExpand,
        toolCallCount: toolCallCount,
      );
    }
    return widget.registry.buildNode(context, node);
  }
```

`_NodeKey` 构造与相等性，把：

```dart
class _NodeKey {
  _NodeKey(AiRenderNode node, {required this.autoExpand})
    : parts = switch (node) {
        AiRenderPart(:final part) => <AiMessagePart>[part],
        AiRenderChainOfThought(:final parts) => parts,
        AiRenderToolGroup(:final tools) => tools,
        AiRenderReasoningGroup(:final parts) => parts,
      };

  final List<AiMessagePart> parts;
  final bool autoExpand;

  @override
  bool operator ==(Object other) {
    if (other is! _NodeKey ||
        other.autoExpand != autoExpand ||
        other.parts.length != parts.length) {
      return false;
    }
```

改为：

```dart
class _NodeKey {
  _NodeKey(
    AiRenderNode node, {
    required this.autoExpand,
    required this.toolCallCount,
  }) : parts = switch (node) {
        AiRenderPart(:final part) => <AiMessagePart>[part],
        AiRenderChainOfThought(:final parts) => parts,
        AiRenderToolGroup(:final tools) => tools,
        AiRenderReasoningGroup(:final parts) => parts,
      };

  final List<AiMessagePart> parts;
  final bool autoExpand;
  final int toolCallCount;

  @override
  bool operator ==(Object other) {
    if (other is! _NodeKey ||
        other.autoExpand != autoExpand ||
        other.toolCallCount != toolCallCount ||
        other.parts.length != parts.length) {
      return false;
    }
```

把 `hashCode`：

```dart
  int get hashCode => Object.hash(
    autoExpand,
    parts.length,
```

改为：

```dart
  int get hashCode => Object.hash(
    autoExpand,
    toolCallCount,
    parts.length,
```

（`_NodeKey` 是 Dart Map 缓存键，不是 Flutter `Key`；计数变化生成新 widget 实例，Flutter 复用 State，而 `AiChainOfThoughtView.didUpdateWidget` 只在 `autoExpand` 变化时重置 `_open`，因此用户手动展开态不丢失。）

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart packages/ai_message_ui/test/ai_message_parts_test.dart
```

Expected: PASS，`All tests passed!`。

- [ ] **Step 5: 提交**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/packages/ai_message_ui/lib/src/ai_message_parts.dart client/packages/ai_message_ui/test/ai_message_parts_test.dart && git commit -m "feat(ai_message_ui): pass message tool-call count to last CoT chain" -- client/packages/ai_message_ui/lib/src/ai_message_parts.dart client/packages/ai_message_ui/test/ai_message_parts_test.dart
```

---

### Task 3: app 层 l10n 文案、strings 开关与 ACP 接线

**Files:**
- Modify: `client/lib/l10n/app_en.arb`（`aiMessageThinkingProcessSteps` 的 `@` 块之后）
- Modify: `client/lib/l10n/app_zh.arb`（同上）
- Modify（生成）: `client/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`
- Modify: `client/lib/pages/chat/ai_message_strings_from_l10n.dart:9-14`, `:30-34`
- Modify: `client/lib/pages/chat/session_chat_message_area.dart:16` 之后新增 import, `:255-256`
- Test: `client/test/pages/chat/ai_message_strings_from_l10n_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 的 `AiMessageStrings.formatThinkingProcessStats`；`isAcpChatSession(AppSession)`（`client/lib/services/chat/session/chat_tab.dart:17`）；`AppLocalizations.aiMessageThinkingProcessStats(int steps, int toolCalls)`（本任务生成）。
- Produces: `aiMessageStringsFromL10n(AppLocalizations l10n, {String? permissionCliName, bool thinkingProcessToolCalls = false})`。

- [ ] **Step 1: 写失败测试**

新建 `client/test/pages/chat/ai_message_strings_from_l10n_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/pages/chat/ai_message_strings_from_l10n.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('stats hook is absent by default (PTY path)', () {
    final strings = aiMessageStringsFromL10n(l10n);
    expect(strings.formatThinkingProcessStats, isNull);
  });

  test('stats hook formats steps and tool calls when enabled (ACP path)', () {
    final strings = aiMessageStringsFromL10n(
      l10n,
      thinkingProcessToolCalls: true,
    );
    final hook = strings.formatThinkingProcessStats;
    expect(hook, isNotNull);
    expect(
      hook!(1, 2),
      'Thinking process · 1 steps · 2 tool calls this turn',
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/ai_message_strings_from_l10n_test.dart
```

Expected: FAIL，编译错误 —— `aiMessageStringsFromL10n` 无 `thinkingProcessToolCalls` 参数，`aiMessageThinkingProcessStats` 尚不存在。

- [ ] **Step 3: 实现最小代码**

`app_en.arb`：在 `"@aiMessageThinkingProcessSteps"` 块的结束 `},` 之后插入：

```json
  "aiMessageThinkingProcessStats": "Thinking process · {steps} steps · {toolCalls} tool calls this turn",
  "@aiMessageThinkingProcessStats": {
    "placeholders": {
      "steps": { "type": "int" },
      "toolCalls": { "type": "int" }
    }
  },
```

`app_zh.arb`：在 `"@aiMessageThinkingProcessSteps"` 块的结束 `},` 之后插入：

```json
  "aiMessageThinkingProcessStats": "思考过程 · {steps} 步 · 本轮共 {toolCalls} 次工具调用",
  "@aiMessageThinkingProcessStats": {
    "placeholders": {
      "steps": { "type": "int" },
      "toolCalls": { "type": "int" }
    }
  },
```

生成 l10n：

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter gen-l10n
```

然后核对：

```bash
cd /home/hhoa/git/hhoa/teampilot && git diff --stat client/lib/l10n/
```

Expected: 3 个生成文件中只新增 `aiMessageThinkingProcessStats` 的抽象声明、en 实现、zh 实现。若生成器因本地 Flutter 版本差异产生**与本改动无关**的大面积重排，只保留这三处新增、撤销其余 hunk（这三个文件当前无未提交改动，可用 `git diff` 逐 hunk 核对后手工保留）。

`client/lib/pages/chat/ai_message_strings_from_l10n.dart` 函数签名，把：

```dart
AiMessageStrings aiMessageStringsFromL10n(
  AppLocalizations l10n, {
  String? permissionCliName,
}) {
```

改为：

```dart
AiMessageStrings aiMessageStringsFromL10n(
  AppLocalizations l10n, {
  String? permissionCliName,
  bool thinkingProcessToolCalls = false,
}) {
```

在 `formatThinkingProcessSummary` 一行之后插入：

```dart
    formatThinkingProcessStats: thinkingProcessToolCalls
        ? (steps, toolCalls) =>
            l10n.aiMessageThinkingProcessStats(steps, toolCalls)
        : null,
```

`client/lib/pages/chat/session_chat_message_area.dart`：在 `import '../../services/chat/conversation/history/chat_transcript_find_controller.dart';` 之后新增一行：

```dart
import '../../services/chat/session/chat_tab.dart';
```

把 `:255-256`：

```dart
                        child: AiMessageStringsScope(
                          strings: aiMessageStringsFromL10n(l10n),
```

改为（用 `Edit` 精确替换，不要覆盖该文件已有的未提交改动）：

```dart
                        child: AiMessageStringsScope(
                          strings: aiMessageStringsFromL10n(
                            l10n,
                            thinkingProcessToolCalls:
                                isAcpChatSession(session),
                          ),
```

`session` 在该 widget 内已可用（`:132`）。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/ai_message_strings_from_l10n_test.dart
```

Expected: PASS，`All tests passed!`。

再跑两条回归（确认共享包与 host 接线未破坏既有行为）：

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart && dart run tool/run_tests.dart test/pages/chat/session_history_review_messages_test.dart
```

Expected: 两条均 PASS。

- [ ] **Step 5: 提交**

提交前先确认这 8 个文件没有夹带与本任务无关的改动。工作区仍有其他在途改动；`session_chat_message_area.dart` 曾含他人 24 行未提交改动，但本计划编写/复核时已回到干净状态，执行时仍可能再次变脏，因此先核对：

```bash
cd /home/hhoa/git/hhoa/teampilot && git status --short -- client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/chat/ai_message_strings_from_l10n.dart client/lib/pages/chat/session_chat_message_area.dart client/test/pages/chat/ai_message_strings_from_l10n_test.dart
```

Expected（当前状态）：每个文件只呈现本任务产生的 `M` / `??`，`session_chat_message_area.dart` 无额外无关改动，可安全整文件提交。

若届时某文件额外含无关改动：从下方 `git add` 与 `git commit --` 的文件列表中**删除该路径**，只提交其余文件，并在收尾报告里明确告知用户——被排除文件（尤其 `session_chat_message_area.dart`）的接线改动仍留在工作区、需与其既有改动一并处理。原因：`git commit -- <paths>` 提交的是工作区整文件内容，无法只取本任务的 2 行，夹带无关改动时不能整文件提交。

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/chat/ai_message_strings_from_l10n.dart client/lib/pages/chat/session_chat_message_area.dart client/test/pages/chat/ai_message_strings_from_l10n_test.dart && git commit -m "feat(chat): show deterministic thinking-process stats for ACP sessions" -- client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/chat/ai_message_strings_from_l10n.dart client/lib/pages/chat/session_chat_message_area.dart client/test/pages/chat/ai_message_strings_from_l10n_test.dart
```

Expected: 本次提交只含上述 8 个文件，不含 `docs/`、`.teampilot/`、其他在途改动文件。

- [ ] **Step 6: 静态检查**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 无新增 issue。

---

### Task 4: 全量验证

**Files:** 无（只读验证）

**Interfaces:**
- Consumes: Task 1–3 的全部改动。

- [ ] **Step 1: 静态分析**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 无新增 issue（AGENTS.md 收尾前硬规则）。

- [ ] **Step 2: 完整测试套件（后台，仅跑一次）**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart
```

以 `run_in_background: true` 运行；Expected: 全绿。若失败，定位到具体用例并回到对应 Task 修复，不要重复跑全量套件。

- [ ] **Step 3: 验收对照**

逐条核对 spec 的验收标准：

1. ACP 会话最后一个思考过程折叠头显示「思考过程 · N 步 · 本轮共 M 次工具调用」，N = 该链推理块数，M = 该消息 `AiToolCallPart` 总数，与可见工具卡数量一致。
2. PTY 会话折叠头文案、折叠行为、工具统计与改动前逐字一致（由 `hook == null` 保证，Task 1 的 `stats hook is absent` 用例锁定）。
3. ACP 工具卡位置与折叠状态不变（`shouldFold` 与 `category` 均未改动）。
4. `flutter analyze --no-fatal-infos --no-fatal-warnings` 无新增问题，`dart run tool/run_tests.dart` 全绿。

- [ ] **Step 4: 报告**

向用户报告：完成的任务、提交哈希列表、验证命令与结果，以及 Task 3 Step 5 中若 `session_chat_message_area.dart` 因含他人改动未提交而留下的待处理项。

---

## Self-Review（已执行）

- **Spec coverage**：背景/目标/非目标 → Global Constraints 与 Task 3 接线；三段 phrase 优先级 → Task 1；统计与最后链判定 → Task 2；`_NodeKey` 刷新 → Task 2 测试 2；l10n + `@` 元数据 → Task 3；PTY 不变 → Task 1 用例 1 与 Task 3 用例 1；并行文档共存 → Global Constraints；验收标准 → Task 4。无缺口。
- **Placeholder scan**：无 TBD/TODO/「类似的」/「适当处理」；每个代码步骤均含完整代码与精确命令。
- **Type consistency**：`formatThinkingProcessStats` 全篇统一为 `String Function(int steps, int toolCalls)?`；`toolCallCount` 统一为 `int`；`thinkingProcessToolCalls` 统一为 `bool`；`_statsLabel` 两个测试文件各自定义为相同签名与相同返回串；`aiMessageThinkingProcessStats(int steps, int toolCalls)` 与 ARB 占位符 `steps` / `toolCalls`（均 `int`）一致。
