# 流式期间折叠已完成推理块 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 流式输出期间只展开当前正在输出的那块推理，把已输出完成的推理块折成标题行，消除会话列表因思考内容堆积而难以滚动的问题。

**Architecture:** 在 `AiChainOfThoughtView` 内计算「活跃推理索引」（仅当 `autoExpand` 为真且链尾是 `AiReasoningPart` 时为最后一块），带索引遍历内部 parts，只对活跃块传 `initiallyExpanded/autoFollow = true`；`AiReasoningPartView` 的 `didUpdateWidget` 补上 `autoFollow` false→true 时展开的分支。不改 host 层接口、不加设置项。

**Tech Stack:** Flutter / Dart（SDK `^3.8.1`，Flutter `>=3.27.0`）；`ai_message_ui` / `ai_message_core`（`client/packages/` 下的 path 依赖）；`AiMessageTheme`（`ThemeExtension`）；`flutter_test` widget tests。

**Spec:** `docs/superpowers/specs/2026-11-06-cot-completed-reasoning-fold-design.md`

## Global Constraints

- **Never invoke `flutter test` directly.** Always `cd client && dart run tool/run_tests.dart <paths/options>`；用 `--plain-name` 缩小范围。
- Test loop：内层循环 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；行为验证一次只跑一个测试文件；全量套件**只在收尾跑一次**，并在后台启动。
- 完成前：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`。
- 包内测试路径从 `client/` 根目录给：`packages/ai_message_ui/test/chain_of_thought_view_test.dart`（已验证可用）。
- 只改以下文件，不改 `AiMessageView` / `AiMessageParts` / `AiThread` / `SessionHistoryThread` 实现 / `LayoutPreferences` / l10n ARB / `AiToolCallPartView`。
- 不新增设置项、不新增 l10n 文案、不引入新组件文件。
- 工作区存在大量未提交的用户改动；**禁止 `git add -A` / `git add .`**，每个 commit 只 `git add` 本任务明确列出的文件。
- 不提交 `client/google_fonts/`（gitignored）；本计划不涉及 zh UI 字体。
- 每个代码步骤都要给出完整替换代码；沿用现有 widget 测试写法（`MaterialApp` + `AiMessageTheme.test()`，默认已折叠）。

### 文件结构

| 文件 | 职责 | 本计划中的改动 |
|---|---|---|
| `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | 单块推理的折叠/展开与内层滚动跟随 | `didUpdateWidget` 增加 `autoFollow` false→true 分支；更新 `autoFollow` 注释 |
| `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart` | 「思考过程」外层块，渲染内部 parts | 计算活跃索引、带索引遍历、per-part 展开参数；更新 `autoExpand` 注释 |
| `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart` | 上述两个组件的 widget 测试 | 新增 5 个测试 + 1 个 helper |
| `client/test/pages/chat/session_history_thread_test.dart` | host 层会话历史行为测试 | 新增 1 个集成回归测试 |

---

### Task 1: `AiReasoningPartView` 成为活跃目标时自动展开

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart:24-28` (`autoFollow` 注释), `:50-59` (`didUpdateWidget`)
- Test: `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`

**Interfaces:**
- Consumes: `AiReasoningPartView.autoFollow`（现有 `bool`，语义扩展为「当前活跃展开目标」）、`initiallyExpanded`（现有 `bool`）、私有 `_open` / `_stickToBottom` / `_scheduleScrollToBottom()`。
- Produces: `AiReasoningPartView.didUpdateWidget` 在 `autoFollow` false→true 时设 `_open = true` 并调度滚到底；Task 2 依赖此分支来打开活跃块。

- [ ] **Step 1: Write the failing test**

在 `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart` 的 `void main() {` 之后插入 helper（后续 Task 2 复用），并在 `main()` 末尾、`class _SummaryFileResolver` 之前插入测试：

```dart
  Widget buildLiveChain(List<AiMessagePart> parts, {bool autoExpand = true}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiChainOfThoughtView(parts: parts, autoExpand: autoExpand),
        ),
      ),
    );
  }
```

```dart
  testWidgets('reasoning body expands when it becomes the live target', (
    tester,
  ) async {
    Widget build({required bool live}) {
      return MaterialApp(
        home: Scaffold(
          body: AiReasoningPartView(
            part: const AiReasoningPart(text: 'live thought'),
            initiallyExpanded: live,
            autoFollow: live,
          ),
        ),
      );
    }

    await tester.pumpWidget(build(live: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('live thought'), findsNothing);

    await tester.pumpWidget(build(live: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('live thought'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart --plain-name "reasoning body expands when it becomes the live target"
```
Expected: **FAIL** — `Expected: exactly one matching node in the test tree; Actual: _TextContainingFinder:<zero widgets with text containing "live thought">`。原因：现有 `else if (!oldWidget.autoFollow && widget.autoFollow && _open)` 要求 `_open` 已为 true，折叠态下不会展开。

- [ ] **Step 3: Write minimal implementation**

把 `reasoning_part_view.dart` 的 `autoFollow` 注释（`:24-28`）替换为：

```dart
  /// True while this reasoning block is the live thinking target. The open
  /// body follows the streaming reasoning: the inner scroll view stays pinned
  /// to the newest line. Flipping to false (another block took over, or the
  /// turn stopped streaming) collapses the body to its trigger row so finished
  /// thinking does not bury the answer. Flipping from false to true opens the
  /// body again and re-arms the follow.
  final bool autoFollow;
```

把 `didUpdateWidget`（`:50-59`）整体替换为：

```dart
  @override
  void didUpdateWidget(covariant AiReasoningPartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoFollow && !widget.autoFollow) {
      // No longer the live thinking target: fold the body back into its row.
      _open = false;
      _stickToBottom = true;
    } else if (!oldWidget.autoFollow && widget.autoFollow) {
      // Became the live thinking target (the turn started while this block was
      // already mounted, or the chain resumed after a tool call): open it and
      // follow the newest line.
      _open = true;
      _stickToBottom = true;
      _scheduleScrollToBottom();
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart --plain-name "reasoning body expands when it becomes the live target"
```
Expected: **PASS** — `All tests passed!`。同文件其余既有测试也须全部通过（用整文件命令确认）：
```bash
cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart client/packages/ai_message_ui/test/chain_of_thought_view_test.dart
git commit -m "fix(ai_message_ui): open reasoning when it becomes the live target"
```

---

### Task 2: `AiChainOfThoughtView` 只展开活跃推理块

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart:24-29` (`autoExpand` 注释), `:49-56` (build 局部变量), `:135-144` (`if (_open)` 循环), `:150-165` (`_buildInnerPart`)
- Test: `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`

**Interfaces:**
- Consumes: `AiChainOfThoughtView.autoExpand`（`bool`）、`parts`（`List<AiMessagePart>`）、`AiMessageTheme.cotExpandReasoningOnOpen` / `cotExpandToolsOnOpen`、`AiReasoningPartView(part, initiallyExpanded, autoFollow)`（Task 1 已扩展）、`AiToolCallPartView(part, initiallyExpanded)`。
- Produces: 内部 per-part 展开策略。Task 3 的集成测试依赖「live 链内只有最后一个 `AiReasoningPart` 正文可见」。

- [ ] **Step 1: Write the failing tests**

在 `chain_of_thought_view_test.dart` 的 `main()` 末尾（Task 1 的测试之后、`class _SummaryFileResolver` 之前）插入以下 4 个测试。`buildLiveChain` helper 已在 Task 1 插入：

```dart
  testWidgets('live Cot opens only the last reasoning part', (tester) async {
    await tester.pumpWidget(
      buildLiveChain(const [
        AiReasoningPart(text: 'first thought'),
        AiReasoningPart(text: 'second thought'),
        AiReasoningPart(text: 'third thought'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsNothing);
    expect(find.textContaining('third thought'), findsOneWidget);
    expect(find.text('Reasoning'), findsNWidgets(3));
  });

  testWidgets('live Cot folds all reasoning when a tool call is the tail', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLiveChain(const [
        AiReasoningPart(text: 'first thought'),
        AiToolCallPart(toolCallId: 'c1', toolName: 'Read'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('first thought'), findsNothing);
    expect(find.text('Reasoning'), findsOneWidget);
  });

  testWidgets('live Cot folds the previous reasoning when a new one arrives', (
    tester,
  ) async {
    const first = AiReasoningPart(text: 'first thought');
    const second = AiReasoningPart(text: 'second thought');
    const third = AiReasoningPart(text: 'third thought');

    await tester.pumpWidget(buildLiveChain(const [first, second]));
    await tester.pumpAndSettle();
    expect(find.textContaining('second thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(const [first, second, third]));
    await tester.pumpAndSettle();

    expect(find.textContaining('second thought'), findsNothing);
    expect(find.textContaining('third thought'), findsOneWidget);
  });

  testWidgets('manually opened finished reasoning survives a new live part', (
    tester,
  ) async {
    const first = AiReasoningPart(text: 'first thought');
    const second = AiReasoningPart(text: 'second thought');
    const third = AiReasoningPart(text: 'third thought');

    await tester.pumpWidget(buildLiveChain(const [first, second]));
    await tester.pumpAndSettle();

    // Manually open the already-finished first block.
    await tester.tap(find.text('Reasoning').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('first thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(const [first, second, third]));
    await tester.pumpAndSettle();

    expect(find.textContaining('first thought'), findsOneWidget);
    expect(find.textContaining('third thought'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart
```
Expected: 4 个新测试 **FAIL**（`findsNothing` 处断言失败，因为现有代码把链内所有 `AiReasoningPart` 都展开）；其余既有测试 PASS。

- [ ] **Step 3: Write minimal implementation**

把 `chain_of_thought_view.dart` 的 `autoExpand` 注释（`:24-29`）替换为：

```dart
  /// While true, the chain stays expanded with only its live reasoning tail
  /// open: the last reasoning part (when it is the last part of the chain)
  /// follows the newest line, while already-finished reasoning parts stay
  /// folded to their trigger rows. The host turns this off once the reasoning
  /// tail is finished (answer starts streaming / turn ends), collapsing the
  /// whole chain back to its default collapsed chrome.
  final bool autoExpand;
```

在 `build` 中 `final actions = AiToolFileActions.of(context);` 之后、`final summary = summarizeThinkingProcess(` 之前插入活跃索引计算：

```dart
    // Only the reasoning part currently being streamed stays open. A tool
    // call at the tail means thinking paused, so nothing stays expanded.
    final activeReasoningIndex =
        widget.autoExpand &&
                widget.parts.isNotEmpty &&
                widget.parts.last is AiReasoningPart
            ? widget.parts.length - 1
            : -1;
```

把 `if (_open)` 里的 children 循环（`:135-144`）替换为：

```dart
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.parts.length; i++)
                    _buildInnerPart(widget.parts[i], i, activeReasoningIndex),
                ],
              ),
            ),
```

把 `_buildInnerPart`（`:150-165`）整体替换为：

```dart
  Widget _buildInnerPart(
    AiMessagePart part,
    int index,
    int activeReasoningIndex,
  ) {
    final aiTheme = AiMessageTheme.of(context);
    final isActive = index == activeReasoningIndex;
    return switch (part) {
      AiReasoningPart() => AiReasoningPartView(
        part: part,
        initiallyExpanded:
            isActive ||
            (!widget.autoExpand && aiTheme.cotExpandReasoningOnOpen),
        autoFollow: isActive,
      ),
      AiToolCallPart() => AiToolCallPartView(
        part: part,
        initiallyExpanded: aiTheme.cotExpandToolsOnOpen,
      ),
      _ => const SizedBox.shrink(),
    };
  }
```

说明：`activeReasoningIndex` 只在 `widget.autoExpand == true` 时可能非负，因此 `autoExpand == false`（手动展开思考链）时 `isActive` 恒为 false，公式退化为原来的 `cotExpandReasoningOnOpen`，手动展开路径行为不变。

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart
```
Expected: **All tests passed!**（含 Task 1 的测试与既有测试，特别是 `theme cotExpand*OnOpen auto-expands nested kinds`、`live reasoning follows streamed text to the bottom`、`reasoning body folds when streaming stops`）。

同时跑一次静态分析（内层循环）：
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 无与本次改动相关的 issue。

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart client/packages/ai_message_ui/test/chain_of_thought_view_test.dart
git commit -m "fix(ai_message_ui): fold finished reasoning parts during live thinking"
```

---

### Task 3: host 层回归、边界回归与收尾验证

**Files:**
- Modify: `client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`（追加 1 个回归测试）
- Modify: `client/test/pages/chat/session_history_thread_test.dart`（追加 1 个集成回归测试）

**Interfaces:**
- Consumes: `SessionHistoryThread` 的 `_harness(...)` / `_pumpLive(tester)` / `pumpUntilSettled(tester)`（该测试文件现有 helper）、`ExternalStoreAiThreadRuntime`、`SessionHistoryLiveChrome.running`、`AiMessageTheme.test(cotExpandLatestOnOpen: true)`（`_harness` 默认）。
- Produces: 无新接口；验证 Task 1/2 的改动在真实 host 路径下生效，且回合结束收起逻辑未被破坏。

- [ ] **Step 1: Write the regression tests**

在 `chain_of_thought_view_test.dart` 的 `main()` 末尾（Task 2 的测试之后、`class _SummaryFileResolver` 之前）插入：

```dart
  testWidgets('all reasoning folds when live auto-expand ends', (tester) async {
    const parts = [
      AiReasoningPart(text: 'first thought'),
      AiReasoningPart(text: 'second thought'),
    ];

    await tester.pumpWidget(buildLiveChain(parts));
    await tester.pumpAndSettle();
    expect(find.textContaining('second thought'), findsOneWidget);

    await tester.pumpWidget(buildLiveChain(parts, autoExpand: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('first thought'), findsNothing);
    expect(find.textContaining('second thought'), findsNothing);
  });
```

在 `client/test/pages/chat/session_history_thread_test.dart` 的 `main()` 末尾（最后一个 `testWidgets` 之后、`}` 之前）插入：

```dart
  testWidgets('live tip folds finished reasoning but keeps the active one open', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: const [
            AiReasoningPart(text: 'finished thought'),
            AiReasoningPart(text: 'active thought'),
          ],
        ),
      ]);

    await tester.pumpWidget(
      _harness(runtime: store, liveChrome: SessionHistoryLiveChrome.running),
    );
    await _pumpLive(tester);

    expect(find.textContaining('active thought'), findsOneWidget);
    expect(find.textContaining('finished thought'), findsNothing);

    await tester.pumpWidget(_harness(runtime: store));
    await pumpUntilSettled(tester);

    expect(find.textContaining('Thinking process'), findsOneWidget);
    expect(find.textContaining('active thought'), findsNothing);
    expect(find.textContaining('finished thought'), findsNothing);
  });
```

- [ ] **Step 2: Run the regression tests**

Run:
```bash
cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/chain_of_thought_view_test.dart --plain-name "all reasoning folds when live auto-expand ends"
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart --plain-name "live tip folds finished reasoning"
```
Expected: 两条均 **PASS**（Task 1/2 已实现）。若 `live tip folds finished reasoning` 失败，检查 `SessionHistoryThread` 的 `liveThinkingTail` 是否把 `chainOfThoughtAutoExpand` 传成了 true（该值由 `ai.id == realTipId && _liveTurnActive(liveChrome) && _endsWithThinking(ai)` 决定，本用例末尾是 `AiReasoningPart`，应为 true）。

- [ ] **Step 3: Static analysis**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: 无新增 issue。

- [ ] **Step 4: Full suite — run once, in the background**

用后台任务启动（本会话的 Bash 工具设 `run_in_background: true`，拿到 `task_id` 后用 `TaskOutput` 取结果；不要在它排队时另起其他测试进程，会阻塞在 `run_tests.lock` 上）：
```bash
cd client && dart run tool/run_tests.dart
```
Expected: 输出末尾 `All tests passed!`。这是本次改动唯一一次全量套件运行。

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/test/chain_of_thought_view_test.dart client/test/pages/chat/session_history_thread_test.dart
git commit -m "test(chat): cover folding finished reasoning in live thinking"
```

---

## Self-Review 记录（写计划时已完成）

- **Spec coverage**：spec 的「行为 1-5」「`cotExpandReasoningOnOpen` 行为变更」「实现」「边界」「测试」逐条对应：行为 1/2 → Task 2 Step 3；行为 3 → Task 1 Step 3；行为 4/5 → Task 2 Step 1 的四个测试 + Task 3 Step 1；设置项语义 → Task 2 Step 3 公式说明；边界 → Task 2 的 `parts.last` 判定与注释、Task 3 集成测试；测试清单 → Task 1/2/3 全部覆盖；「不做的事」→ Global Constraints。
- **Placeholder scan**：无 TBD/TODO/「适当处理」；所有代码步骤均含完整代码；命令均含精确路径与预期输出。
- **Type consistency**：`activeReasoningIndex`（`int`）、`isActive`（`bool`）、`_buildInnerPart(AiMessagePart, int, int)`、`autoFollow`（`bool`）在 Task 1/2/3 中命名与类型一致；`buildLiveChain(List<AiMessagePart>, {bool autoExpand = true})` 在 Task 1 定义、Task 2/3 复用。
