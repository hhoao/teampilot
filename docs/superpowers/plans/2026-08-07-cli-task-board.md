# CLI Task Board + Task-Tool Bubbles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the CLI's task board (derived from `TaskCreate`/`TaskUpdate` tool calls) as a persistent floating panel in the top-right of the chat, and render those tool calls as dedicated task bubbles instead of generic tool rows.

**Architecture:** Pure reduction (`reduceCliTaskBoard`) turns the seat transcript into a `CliTaskBoard`; a `ChangeNotifier` presenter memoizes it on message-list instance identity. Two render surfaces consume it: a `Positioned` floating panel (collapsed pill → 320 px card) and name-keyed task bubbles via a new additive `AiToolCallBubbleScope` hook in `ai_message_ui`. Scope is per-seat (selected member).

**Tech Stack:** Flutter, `ai_message_core`/`ai_message_ui` (vendored package, plain tracked dir — not a submodule), `shared_ui` (`Tp*` design system), app l10n via ARB.

**Spec:** `docs/superpowers/specs/2026-08-07-cli-task-board-design.md`

## Global Constraints

- Logic lives in `client/lib/services/`, chat-specific chrome in `client/lib/pages/chat/`; no generic controls under `client/lib/widgets/`.
- l10n: edit `client/lib/l10n/app_en.arb` + `app_zh.arb` **only**, then run `flutter gen-l10n` from `client/`. Generated files under `lib/l10n/app_localizations*.dart` are committed.
- Verification before done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
- `ai_message_ui` edits land in the main repo (not a submodule) and are committed normally.
- The controller is a **derived projection** of the seat runtime (not app state) — a `ChangeNotifier`, not a cubit. Do not wire it into any cubit graph.
- No `print`; diagnostics via `AppLogger` only (none expected here).
- The transcript parser (`claude_compatible_jsonl.dart`) already correlates tool `result` onto each `AiToolCallPart` — the reducer relies on that.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/tasks/cli_task_board.dart` (new) | `CliTaskStatus`, `CliTask`, `CliTaskBoard` value types + pure `reduceCliTaskBoard(List<AiMessage>)` + `cliTaskStatusFromString`. No Flutter/IO. |
| `client/lib/services/cli/tasks/cli_task_board_controller.dart` (new) | `CliTaskBoardController extends ChangeNotifier` — subscribes to an `AiThreadRuntime`, memoizes derivation on message-list instance identity. |
| `client/packages/ai_message_ui/lib/src/tool_call_bubble_scope.dart` (new) | `AiToolCallBubbleScope` InheritedWidget + `AiToolCallBubbleBuilder` typedef; consulted by `AiToolCallPartView`. |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` (modify) | Early-return custom bubble when the scope matches `part.toolName`. |
| `client/packages/ai_message_ui/lib/ai_message_ui.dart` (modify) | Export the new scope. |
| `client/lib/pages/chat/cli_task_bubbles.dart` (new) | `CliTaskCreateBubble` / `CliTaskUpdateBubble` + `cliTaskBubbleBuilders()` registry. |
| `client/lib/pages/chat/session_cli_task_panel.dart` (new) | `SessionCliTaskPanel` — collapsed pill / expanded 320 px card. |
| `client/lib/pages/chat/session_chat_view.dart` (modify) | Owns the controller (per seat), wraps the thread in `AiToolCallBubbleScope`, adds the `Positioned` panel. |
| Tests | `test/services/cli/tasks/cli_task_board_test.dart`, `.../cli_task_board_controller_test.dart`, `packages/ai_message_ui/test/tool_call_bubble_scope_test.dart`, `test/pages/chat/cli_task_bubbles_test.dart`, `test/pages/chat/session_cli_task_panel_test.dart`. |

---

## Task 1: Domain model + pure reducer

**Files:**
- Create: `client/lib/services/cli/tasks/cli_task_board.dart`
- Test: `client/test/services/cli/tasks/cli_task_board_test.dart`

**Interfaces:**
- Consumes: `AiMessage` / `AiToolCallPart` / `AiRole` from `package:ai_message_core/ai_message_core.dart` (already available).
- Produces:
  - `enum CliTaskStatus { pending, inProgress, completed, cancelled, unknown }`
  - `class CliTask` with fields `taskId` (`String?`), `subject`, `description`, `activeForm` (all `String`), `status` (`CliTaskStatus`), `seq` (`int`); `copyWith({CliTaskStatus? status})`.
  - `class CliTaskBoard { List<CliTask> tasks; int get totalCount; int get completedCount; }`
  - `CliTaskBoard reduceCliTaskBoard(List<AiMessage> messages)`
  - `CliTaskStatus cliTaskStatusFromString(String raw)`

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/tasks/cli_task_board_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board.dart';

AiMessage _assistant(AiToolCallPart part) =>
    AiMessage(id: 'm', role: AiRole.assistant, parts: [part]);

AiToolCallPart _create({
  Map<String, Object?>? args,
  Object? result,
}) =>
    AiToolCallPart(
      toolCallId: 'c',
      toolName: 'TaskCreate',
      args: args,
      result: result,
      status: AiToolCallStatus.complete,
    );

AiToolCallPart _update(Map<String, Object?> args) => AiToolCallPart(
  toolCallId: 'u',
  toolName: 'TaskUpdate',
  args: args,
  status: AiToolCallStatus.complete,
);

void main() {
  test('TaskCreate appends a pending task with subject/description/activeForm',
      () {
    final board = reduceCliTaskBoard([
      _assistant(_create(args: {
        'subject': 'T1: do a thing',
        'description': 'details',
        'activeForm': 'Doing a thing',
      })),
    ]);
    expect(board.totalCount, 1);
    final task = board.tasks.single;
    expect(task.subject, 'T1: do a thing');
    expect(task.description, 'details');
    expect(task.activeForm, 'Doing a thing');
    expect(task.status, CliTaskStatus.pending);
    expect(board.completedCount, 0);
  });

  test('TaskCreate reads taskId from the correlated result', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(
        args: {'subject': 'T1'},
        result: {'taskId': '9', 'subject': 'T1'},
      )),
    ]);
    expect(board.tasks.single.taskId, '9');
  });

  test('TaskUpdate flips status when taskId matches a created task', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(args: {'subject': 'T1'}, result: {'taskId': '9'})),
      _assistant(_update({'taskId': '9', 'status': 'in_progress'})),
    ]);
    expect(board.totalCount, 1);
    expect(board.tasks.single.status, CliTaskStatus.inProgress);
  });

  test('TaskUpdate before any matching create adds a placeholder', () {
    final board = reduceCliTaskBoard([
      _assistant(_update({'taskId': '9', 'status': 'completed'})),
    ]);
    expect(board.totalCount, 1);
    expect(board.tasks.single.subject, '');
    expect(board.tasks.single.taskId, '9');
    expect(board.tasks.single.status, CliTaskStatus.completed);
    expect(board.completedCount, 1);
  });

  test('unknown status string maps to unknown; tool name is case-insensitive',
      () {
    final board = reduceCliTaskBoard([
      AiMessage(
        id: 'm',
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: 'c',
            toolName: 'taskupdate',
            args: {'taskId': '1', 'status': 'weird'},
            status: AiToolCallStatus.complete,
          ),
        ],
      ),
    ]);
    expect(board.tasks.single.status, CliTaskStatus.unknown);
  });

  test('non-task tools and user messages are ignored', () {
    final board = reduceCliTaskBoard([
      _assistant(AiToolCallPart(
        toolCallId: 'c',
        toolName: 'Bash',
        args: const {'command': 'ls'},
        status: AiToolCallStatus.complete,
      )),
      const AiMessage(
        id: 'u',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hi')],
      ),
    ]);
    expect(board.totalCount, 0);
  });

  test('tasks keep creation order', () {
    final board = reduceCliTaskBoard([
      _assistant(_create(args: {'subject': 'A'})),
      _assistant(_create(args: {'subject': 'B'})),
    ]);
    expect(board.tasks.map((t) => t.subject).toList(), ['A', 'B']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/tasks/cli_task_board_test.dart`
Expected: FAIL — `package:teampilot/services/cli/tasks/cli_task_board.dart` not found (import error).

- [ ] **Step 3: Write the implementation**

`client/lib/services/cli/tasks/cli_task_board.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';

/// Task lifecycle statuses observed in CLI task transcripts.
enum CliTaskStatus { pending, inProgress, completed, cancelled, unknown }

/// One task in a CLI task board, derived from TaskCreate/TaskUpdate calls.
class CliTask {
  const CliTask({
    required this.taskId,
    required this.subject,
    required this.description,
    required this.activeForm,
    required this.status,
    required this.seq,
  });

  /// Server-assigned id from the TaskCreate result (may be null before the
  /// result arrives, or when the create predates the transcript window).
  final String? taskId;
  final String subject;
  final String description;
  final String activeForm;
  final CliTaskStatus status;

  /// Stable ordering for display.
  final int seq;

  CliTask copyWith({CliTaskStatus? status}) => CliTask(
    taskId: taskId,
    subject: subject,
    description: description,
    activeForm: activeForm,
    status: status ?? this.status,
    seq: seq,
  );
}

/// Immutable snapshot of all tasks derived from a transcript.
class CliTaskBoard {
  const CliTaskBoard({required this.tasks});

  final List<CliTask> tasks;

  int get totalCount => tasks.length;

  int get completedCount =>
      tasks.where((t) => t.status == CliTaskStatus.completed).length;
}

const String _kTaskCreate = 'taskcreate';
const String _kTaskUpdate = 'taskupdate';

/// Reduces a transcript into a [CliTaskBoard].
///
/// Walks assistant `AiToolCallPart`s in order: `TaskCreate` appends a pending
/// task (taskId from the correlated result); `TaskUpdate` flips a task's
/// status by id, or appends a placeholder when the id is unknown (resume
/// window where the create predates the transcript).
CliTaskBoard reduceCliTaskBoard(List<AiMessage> messages) {
  final tasks = <CliTask>[];
  var seq = 0;

  for (final message in messages) {
    if (message.role != AiRole.assistant) continue;
    for (final part in message.parts) {
      if (part is! AiToolCallPart) continue;
      final name = part.toolName.toLowerCase();
      if (name == _kTaskCreate) {
        final args = part.args ?? const <String, Object?>{};
        tasks.add(
          CliTask(
            taskId: _taskIdFromCreate(part),
            subject: _str(args['subject']),
            description: _str(args['description']),
            activeForm: _str(args['activeForm']),
            status: CliTaskStatus.pending,
            seq: seq++,
          ),
        );
      } else if (name == _kTaskUpdate) {
        final args = part.args ?? const <String, Object?>{};
        final taskId = _str(args['taskId']);
        if (taskId.isEmpty) continue;
        final status = cliTaskStatusFromString(_str(args['status']));
        final index = tasks.indexWhere((t) => t.taskId == taskId);
        if (index >= 0) {
          tasks[index] = tasks[index].copyWith(status: status);
        } else {
          tasks.add(
            CliTask(
              taskId: taskId,
              subject: '',
              description: '',
              activeForm: '',
              status: status,
              seq: seq++,
            ),
          );
        }
      }
    }
  }
  return CliTaskBoard(tasks: List.unmodifiable(tasks));
}

String _str(Object? value) => value == null ? '' : '$value';

String? _taskIdFromCreate(AiToolCallPart part) {
  final result = part.result;
  if (result is Map) {
    final id = result['taskId'] ?? result['id'];
    final s = id == null ? '' : '$id';
    if (s.isNotEmpty) return s;
  }
  return null;
}

/// Maps a CLI status string to [CliTaskStatus]; anything unrecognized → unknown.
CliTaskStatus cliTaskStatusFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'pending':
      return CliTaskStatus.pending;
    case 'in_progress':
      return CliTaskStatus.inProgress;
    case 'completed':
      return CliTaskStatus.completed;
    case 'cancelled':
      return CliTaskStatus.cancelled;
    default:
      return CliTaskStatus.unknown;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/tasks/cli_task_board_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/tasks/cli_task_board.dart client/test/services/cli/tasks/cli_task_board_test.dart
git commit -m "feat(cli-tasks): task board model + pure transcript reducer"
```

---

## Task 2: Memoizing controller

**Files:**
- Create: `client/lib/services/cli/tasks/cli_task_board_controller.dart`
- Test: `client/test/services/cli/tasks/cli_task_board_controller_test.dart`

**Interfaces:**
- Consumes: `CliTaskBoard` / `reduceCliTaskBoard` (Task 1); `AiThreadRuntime` from `ai_message_core`.
- Produces: `class CliTaskBoardController extends ChangeNotifier` with `CliTaskBoard get board`; `CliTaskBoardController(AiThreadRuntime runtime)`.

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/tasks/cli_task_board_controller_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board_controller.dart';

AiToolCallPart _create(String subject) => AiToolCallPart(
  toolCallId: 'c',
  toolName: 'TaskCreate',
  args: {'subject': subject},
  status: AiToolCallStatus.complete,
);

void main() {
  test('board reflects runtime messages and updates on change', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final controller = CliTaskBoardController(runtime);
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });

    expect(controller.board.totalCount, 0);

    runtime.setMessages([
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 1);
    expect(controller.board.tasks.single.subject, 'A');

    runtime.setMessages([
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
      AiMessage(id: 'm2', role: AiRole.assistant, parts: [_create('B')]),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 2);

    runtime.setMessages(const []);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 0);
  });

  test('does not re-derive when message instances are unchanged', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final controller = CliTaskBoardController(runtime);
    addTearDown(() {
      controller.dispose();
      runtime.close();
    });
    var notified = 0;
    controller.addListener(() => notified++);

    final message = AiMessage(
      id: 'm1',
      role: AiRole.assistant,
      parts: [_create('A')],
    );
    runtime.setMessages([message]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 1);

    // Same message instance, new list wrapper → the runtime reuses the
    // instance and does not notify; the controller must not re-derive either.
    runtime.setMessages([message]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });

  test('dispose cancels the runtime subscription', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final controller = CliTaskBoardController(runtime);
    controller.dispose();
    runtime.setMessages([
      AiMessage(id: 'm1', role: AiRole.assistant, parts: [_create('A')]),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.board.totalCount, 0);
    runtime.close();
  });
}
```

Note: the second test asserts `notified == 0` after feeding the *same instance* — this holds because `ExternalStoreAiThreadRuntime.setMessages` reuses the unchanged instance and skips its own `changes` notification, so the controller's listener never fires.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/tasks/cli_task_board_controller_test.dart`
Expected: FAIL — import not found.

- [ ] **Step 3: Write the implementation**

`client/lib/services/cli/tasks/cli_task_board_controller.dart`:

```dart
import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';

import 'cli_task_board.dart';

/// Memoizing presenter: re-derives [board] only when the runtime's message
/// list content actually changes.
///
/// The runtime reuses unchanged message instances and only notifies when
/// content changed, so an instance-identity comparison is a correct (and
/// cheap) change detector for the derivation.
class CliTaskBoardController extends ChangeNotifier {
  CliTaskBoardController(AiThreadRuntime runtime) {
    _runtime = runtime;
    _lastMessages = runtime.messages;
    _board = reduceCliTaskBoard(_lastMessages);
    _sub = runtime.changes.listen((_) => _onChanges());
  }

  late final AiThreadRuntime _runtime;
  late List<AiMessage> _lastMessages;
  late CliTaskBoard _board;
  StreamSubscription<void>? _sub;

  CliTaskBoard get board => _board;

  void _onChanges() {
    final messages = _runtime.messages;
    if (_sameInstancesInOrder(messages, _lastMessages)) return;
    _lastMessages = messages;
    _board = reduceCliTaskBoard(messages);
    notifyListeners();
  }

  static bool _sameInstancesInOrder(List<AiMessage> a, List<AiMessage> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/tasks/cli_task_board_controller_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/tasks/cli_task_board_controller.dart client/test/services/cli/tasks/cli_task_board_controller_test.dart
git commit -m "feat(cli-tasks): memoizing task-board controller over seat runtime"
```

---

## Task 3: l10n keys

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart` (via `flutter gen-l10n`)

**Interfaces:**
- Produces (generated getters on `AppLocalizations`): `cliTaskBoardTitle` (`String`), `cliTaskBoardCount(int completed, int total)` (`String`), `cliTaskBoardMore(int count)` (`String`), `cliTaskStatusPending/InProgress/Completed/Cancelled/Unknown` (`String`).

- [ ] **Step 1: Add English keys**

In `client/lib/l10n/app_en.arb`, append before the closing `}`:

```json
  "cliTaskBoardTitle": "Tasks",
  "cliTaskBoardCount": "{completed}/{total}",
  "@cliTaskBoardCount": {
    "placeholders": {
      "completed": { "type": "int" },
      "total": { "type": "int" }
    }
  },
  "cliTaskBoardMore": "… +{count} more",
  "@cliTaskBoardMore": {
    "placeholders": { "count": { "type": "int" } }
  },
  "cliTaskStatusPending": "Pending",
  "cliTaskStatusInProgress": "In progress",
  "cliTaskStatusCompleted": "Done",
  "cliTaskStatusCancelled": "Cancelled",
  "cliTaskStatusUnknown": "Unknown"
```

- [ ] **Step 2: Add Chinese keys**

In `client/lib/l10n/app_zh.arb`, append before the closing `}`:

```json
  "cliTaskBoardTitle": "任务",
  "cliTaskBoardCount": "{completed}/{total}",
  "@cliTaskBoardCount": {
    "placeholders": {
      "completed": { "type": "int" },
      "total": { "type": "int" }
    }
  },
  "cliTaskBoardMore": "… +{count} 更多",
  "@cliTaskBoardMore": {
    "placeholders": { "count": { "type": "int" } }
  },
  "cliTaskStatusPending": "待处理",
  "cliTaskStatusInProgress": "进行中",
  "cliTaskStatusCompleted": "已完成",
  "cliTaskStatusCancelled": "已取消",
  "cliTaskStatusUnknown": "未知"
```

- [ ] **Step 3: Regenerate**

Run: `cd client && flutter gen-l10n`
Expected: `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart` regenerated; `git diff --stat lib/l10n/` shows the new getters.

- [ ] **Step 4: Verify compile**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors (the keys are unused yet, which is fine — unused l10n getters do not warn).

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/
git commit -m "feat(l10n): CLI task board title, count, more, and status labels"
```

---

## Task 4: `ai_message_ui` name-keyed bubble hook

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/tool_call_bubble_scope.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`
- Test: `client/packages/ai_message_ui/test/tool_call_bubble_scope_test.dart`

**Interfaces:**
- Consumes: `AiToolCallPart` from `ai_message_core`.
- Produces: `typedef AiToolCallBubbleBuilder = Widget Function(BuildContext, AiToolCallPart)`; `class AiToolCallBubbleScope extends InheritedWidget` with `Map<String, AiToolCallBubbleBuilder> builders` and `static AiToolCallBubbleScope? maybeOf(BuildContext)`. `AiToolCallPartView` renders the matched bubble instead of the generic trigger.

- [ ] **Step 1: Write the failing test**

`client/packages/ai_message_ui/test/tool_call_bubble_scope_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required AiToolCallPart part,
    Map<String, AiToolCallBubbleBuilder> builders = const {},
  }) {
    final theme = ThemeData(
      useMaterial3: true,
      extensions: [AiMessageTheme.test()],
    );
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: AiToolCallBubbleScope(
          builders: builders,
          child: AiToolCallPartView(part: part),
        ),
      ),
    );
  }

  testWidgets('matched name renders custom bubble, not generic trigger',
      (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'c',
      toolName: 'TaskCreate',
      args: const {'subject': 'T1: hello'},
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(
      host(
        part: part,
        builders: {
          'taskcreate': (context, p) => Text('BUBBLE-${p.toolName}'),
        },
      ),
    );
    expect(find.text('BUBBLE-TaskCreate'), findsOneWidget);
    expect(find.textContaining('Used tool', findRichText: true), findsNothing);
  });

  testWidgets('unmatched name still renders generic trigger', (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'c',
      toolName: 'Read',
      args: const {'file_path': 'a.dart'},
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(host(part: part, builders: const {}));
    expect(find.textContaining('Used tool', findRichText: true), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/ai_message_ui && flutter test test/tool_call_bubble_scope_test.dart`
Expected: FAIL — `AiToolCallBubbleScope` / `AiToolCallBubbleBuilder` undefined.

- [ ] **Step 3: Create the scope**

`client/packages/ai_message_ui/lib/src/tool_call_bubble_scope.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/widgets.dart';

typedef AiToolCallBubbleBuilder = Widget Function(
  BuildContext context,
  AiToolCallPart part,
);

/// Name-keyed custom bubbles for tool calls, consulted by [AiToolCallPartView]
/// before any generic chrome. Builders are keyed by lowercase tool name; a
/// match short-circuits the generic trigger row.
///
/// [updateShouldNotify] is deliberately false: the registry is static per host
/// for the widget's lifetime, so dependents never need a scope-driven rebuild.
class AiToolCallBubbleScope extends InheritedWidget {
  const AiToolCallBubbleScope({
    required this.builders,
    required super.child,
    super.key,
  });

  final Map<String, AiToolCallBubbleBuilder> builders;

  static AiToolCallBubbleScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AiToolCallBubbleScope>();
  }

  @override
  bool updateShouldNotify(AiToolCallBubbleScope oldWidget) => false;
}
```

- [ ] **Step 4: Consult the scope in `AiToolCallPartView`**

In `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`:

Add import:

```dart
import '../tool_call_bubble_scope.dart';
```

In `_AiToolCallPartViewState.build`, immediately after the existing line `final part = widget.part;`, insert:

```dart
    final bubble = AiToolCallBubbleScope
        .maybeOf(context)
        ?.builders[part.toolName.toLowerCase()];
    if (bubble != null) {
      return SelectionContainer.disabled(
        child: bubble(context, part),
      );
    }
```

- [ ] **Step 5: Export the scope**

In `client/packages/ai_message_ui/lib/ai_message_ui.dart`, add:

```dart
export 'src/tool_call_bubble_scope.dart';
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client/packages/ai_message_ui && flutter test test/tool_call_bubble_scope_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/tool_call_bubble_scope.dart client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart client/packages/ai_message_ui/lib/ai_message_ui.dart client/packages/ai_message_ui/test/tool_call_bubble_scope_test.dart
git commit -m "feat(ai_message_ui): name-keyed tool-call bubble scope"
```

---

## Task 5: Task-tool bubbles

**Files:**
- Create: `client/lib/pages/chat/cli_task_bubbles.dart`
- Test: `client/test/pages/chat/cli_task_bubbles_test.dart`

**Interfaces:**
- Consumes: `CliTaskStatus` / `cliTaskStatusFromString` (Task 1); `AiToolCallBubbleBuilder` / `AiToolCallBubbleScope` (Task 4); `context.l10n.cliTaskStatus*` (Task 3).
- Produces: `Map<String, AiToolCallBubbleBuilder> cliTaskBubbleBuilders()`; `CliTaskCreateBubble`; `CliTaskUpdateBubble`.

- [ ] **Step 1: Write the failing test**

`client/test/pages/chat/cli_task_bubbles_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/cli_task_bubbles.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

Widget _host(Widget child) {
  final theme = ThemeData(
    useMaterial3: true,
    extensions: [AiMessageTheme.test()],
  );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('TaskCreate bubble shows subject and pending pill', (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'c',
      toolName: 'TaskCreate',
      args: const {
        'subject': 'T1: do a thing',
        'description': 'details',
        'activeForm': 'Doing it',
      },
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(_host(CliTaskCreateBubble(part: part)));
    // Header label + subject render as a rich Text — match with findRichText.
    expect(find.textContaining('TaskCreate', findRichText: true), findsOneWidget);
    expect(find.textContaining('T1: do a thing', findRichText: true), findsOneWidget);
    // The status pill is a plain Text.
    expect(find.text('Pending'), findsOneWidget);
    // Tapping the pill toggles the expanded detail.
    await tester.tap(find.text('Pending'));
    await tester.pump();
    expect(find.text('details'), findsOneWidget);
    expect(find.text('Doing it'), findsOneWidget);
  });

  testWidgets('TaskUpdate bubble shows task id and status transition',
      (tester) async {
    final part = AiToolCallPart(
      toolCallId: 'u',
      toolName: 'TaskUpdate',
      args: const {'taskId': '9', 'status': 'in_progress'},
      status: AiToolCallStatus.complete,
    );
    await tester.pumpWidget(_host(CliTaskUpdateBubble(part: part)));
    expect(find.textContaining('TaskUpdate · T9', findRichText: true), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('cliTaskBubbleBuilders returns create + update builders',
      () async {
    final builders = cliTaskBubbleBuilders();
    expect(builders.keys, containsAll(['taskcreate', 'taskupdate']));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/cli_task_bubbles_test.dart`
Expected: FAIL — `cli_task_bubbles.dart` not found.

- [ ] **Step 3: Write the bubbles**

`client/lib/pages/chat/cli_task_bubbles.dart`:

```dart
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/cli/tasks/cli_task_board.dart';

/// Registry of task-tool custom bubbles, keyed by lowercase tool name.
Map<String, AiToolCallBubbleBuilder> cliTaskBubbleBuilders() => {
  'taskcreate': (context, part) => CliTaskCreateBubble(part: part),
  'taskupdate': (context, part) => CliTaskUpdateBubble(part: part),
};

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}

String _statusLabel(BuildContext context, CliTaskStatus status) =>
    switch (status) {
      CliTaskStatus.pending => context.l10n.cliTaskStatusPending,
      CliTaskStatus.inProgress => context.l10n.cliTaskStatusInProgress,
      CliTaskStatus.completed => context.l10n.cliTaskStatusCompleted,
      CliTaskStatus.cancelled => context.l10n.cliTaskStatusCancelled,
      CliTaskStatus.unknown => context.l10n.cliTaskStatusUnknown,
    };

Color _statusColor(ColorScheme scheme, CliTaskStatus status) => switch (status) {
  CliTaskStatus.pending => scheme.onSurfaceVariant,
  CliTaskStatus.inProgress => scheme.primary,
  CliTaskStatus.completed => scheme.tertiary,
  CliTaskStatus.cancelled => scheme.error,
  CliTaskStatus.unknown => scheme.onSurfaceVariant,
};

/// Dedicated bubble for a TaskCreate tool call.
class CliTaskCreateBubble extends StatefulWidget {
  const CliTaskCreateBubble({required this.part, super.key});

  final AiToolCallPart part;

  @override
  State<CliTaskCreateBubble> createState() => _CliTaskCreateBubbleState();
}

class _CliTaskCreateBubbleState extends State<CliTaskCreateBubble> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final args = widget.part.args ?? const <String, Object?>{};
    final subject = _stringify(args['subject']).trim();
    final description = _stringify(args['description']).trim();
    final activeForm = _stringify(args['activeForm']).trim();

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: _BubbleHeader(
              icon: Icons.add_task_rounded,
              color: triggerColor,
              label: 'TaskCreate',
              emphasized: subject,
              pill: _statusLabel(context, CliTaskStatus.pending),
              pillColor: _statusColor(scheme, CliTaskStatus.pending),
              open: _open,
              onToggle: () => setState(() => _open = !_open),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (description.isNotEmpty)
                    _BubbleField(label: 'description', text: description),
                  if (description.isNotEmpty && activeForm.isNotEmpty)
                    const SizedBox(height: 8),
                  if (activeForm.isNotEmpty)
                    _BubbleField(label: 'activeForm', text: activeForm),
                  if (widget.part.result != null) ...[
                    const SizedBox(height: 8),
                    _BubbleField(
                      label: AiMessageStrings.of(context).result,
                      text: _stringify(widget.part.result),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dedicated bubble for a TaskUpdate tool call.
class CliTaskUpdateBubble extends StatefulWidget {
  const CliTaskUpdateBubble({required this.part, super.key});

  final AiToolCallPart part;

  @override
  State<CliTaskUpdateBubble> createState() => _CliTaskUpdateBubbleState();
}

class _CliTaskUpdateBubbleState extends State<CliTaskUpdateBubble> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final args = widget.part.args ?? const <String, Object?>{};
    final taskId = _stringify(args['taskId']).trim();
    final status = cliTaskStatusFromString(_stringify(args['status']));
    final label = taskId.isEmpty ? 'TaskUpdate' : 'TaskUpdate · T$taskId';

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: _BubbleHeader(
              icon: Icons.sync_alt_rounded,
              color: triggerColor,
              label: label,
              emphasized: '',
              pill: _statusLabel(context, status),
              pillColor: _statusColor(scheme, status),
              open: _open,
              onToggle: () => setState(() => _open = !_open),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BubbleField(label: 'args', text: _stringify(widget.part.args)),
                  if (widget.part.result != null) ...[
                    const SizedBox(height: 8),
                    _BubbleField(
                      label: AiMessageStrings.of(context).result,
                      text: _stringify(widget.part.result),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BubbleHeader extends StatelessWidget {
  const _BubbleHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.emphasized,
    required this.pill,
    required this.pillColor,
    required this.open,
    required this.onToggle,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String emphasized;
  final String pill;
  final Color pillColor;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final markdown = AiMessageTheme.of(context).markdown;
    final triggerStyle = markdown.toolTrigger(color);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: triggerStyle,
                    children: [
                      TextSpan(
                        text: label,
                        style: markdown.toolNameEmphasis(triggerStyle),
                      ),
                      if (emphasized.isNotEmpty) ...[
                        const TextSpan(text: ' '),
                        TextSpan(text: emphasized),
                      ],
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _Pill(label: pill, color: pillColor),
              const SizedBox(width: 2),
              Icon(
                open ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, height: 1.4, color: color),
      ),
    );
  }
}

class _BubbleField extends StatelessWidget {
  const _BubbleField({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: aiTheme.markdown.toolTrigger(scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: aiTheme.resolveToolPanel(scheme),
            borderRadius: BorderRadius.circular(aiTheme.panelRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              text,
              softWrap: true,
              style: aiTheme.markdown.codeBlock.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/chat/cli_task_bubbles_test.dart`
Expected: PASS (3 tests). (Do not use `pumpAndSettle` in tests that render the in-progress spinner.)

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/cli_task_bubbles.dart client/test/pages/chat/cli_task_bubbles_test.dart
git commit -m "feat(chat): TaskCreate/TaskUpdate task bubbles"
```

---

## Task 6: Floating task panel

**Files:**
- Create: `client/lib/pages/chat/session_cli_task_panel.dart`
- Test: `client/test/pages/chat/session_cli_task_panel_test.dart`

**Interfaces:**
- Consumes: `CliTaskBoard` / `CliTaskStatus` (Task 1).
- Produces: `class SessionCliTaskPanel extends StatefulWidget` with constructor `{ required CliTaskBoard board, required String title, required String countText, required String Function(int count) moreLabel, int maxVisible = 6 }`. Renders `SizedBox.shrink()` when `board.totalCount == 0`; a collapsed pill otherwise; expanding reveals the 320 px card.

- [ ] **Step 1: Write the failing test**

`client/test/pages/chat/session_cli_task_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/chat/session_cli_task_panel.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

Widget _host(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

CliTask _task(String subject, CliTaskStatus status) => CliTask(
  taskId: null,
  subject: subject,
  description: '',
  activeForm: '',
  status: status,
  seq: 0,
);

CliTaskBoard _board(List<CliTask> tasks) => CliTaskBoard(tasks: tasks);

void main() {
  testWidgets('hidden when there are no tasks', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board(const []),
          title: 'Tasks',
          countText: '0/0',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    expect(find.text('Tasks'), findsNothing);
  });

  testWidgets('collapsed pill shows count; tap expands to card', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task('T1: first', CliTaskStatus.inProgress),
            _task('T2: second', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '0/2',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    // Collapsed pill: count visible, title not yet.
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);

    await tester.tap(find.text('0/2'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('T1: first'), findsOneWidget);
    expect(find.text('T2: second'), findsOneWidget);
  });

  testWidgets('completed tasks are struck through and counted', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            _task('T1: done', CliTaskStatus.completed),
            _task('T2: wait', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '1/2',
          moreLabel: (n) => '… +$n more',
        ),
      ),
    );
    await tester.tap(find.text('1/2'));
    await tester.pump();
    expect(find.text('Tasks'), findsOneWidget);
    final doneText = tester.widget<Text>(find.text('T1: done'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('overflow shows +N more label', (tester) async {
    await tester.pumpWidget(
      _host(
        SessionCliTaskPanel(
          board: _board([
            for (var i = 1; i <= 8; i++) _task('T$i: item', CliTaskStatus.pending),
          ]),
          title: 'Tasks',
          countText: '0/8',
          moreLabel: (n) => '… +$n more',
          maxVisible: 6,
        ),
      ),
    );
    await tester.tap(find.text('0/8'));
    await tester.pump();
    expect(find.text('… +2 more'), findsOneWidget);
    expect(find.text('T1: item'), findsOneWidget);
    expect(find.text('T8: item'), findsNothing);
  });
}
```

Note: the in-progress spinner in the first expanded test is animated — use `tester.pump()` (never `pumpAndSettle`) in tests that render an `inProgress` task.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/session_cli_task_panel_test.dart`
Expected: FAIL — `session_cli_task_panel.dart` not found.

- [ ] **Step 3: Write the panel**

`client/lib/pages/chat/session_cli_task_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../services/cli/tasks/cli_task_board.dart';

/// Floating task-board card pinned to the top-right of the chat message area.
///
/// Collapsed to a small pill showing the count; tapping expands to a 320 px
/// card (title, completed/total, status-icon + subject rows, "+N more").
class SessionCliTaskPanel extends StatefulWidget {
  const SessionCliTaskPanel({
    required this.board,
    required this.title,
    required this.countText,
    required this.moreLabel,
    this.maxVisible = 6,
    super.key,
  });

  final CliTaskBoard board;
  final String title;

  /// Pre-formatted "{completed}/{total}" label.
  final String countText;

  /// Overflow label builder, e.g. "… +3 more".
  final String Function(int count) moreLabel;

  final int maxVisible;

  @override
  State<SessionCliTaskPanel> createState() => _SessionCliTaskPanelState();
}

class _SessionCliTaskPanelState extends State<SessionCliTaskPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    if (board.totalCount == 0) return const SizedBox.shrink();
    if (!_expanded) return _buildCollapsed(context);
    return _buildExpanded(context, board);
  }

  Widget _buildCollapsed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _expanded = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.task_alt_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                widget.countText,
                style: TpTextStyles.of(context).smColored(scheme.onSurface),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, CliTaskBoard board) {
    final scheme = Theme.of(context).colorScheme;
    final visible = board.tasks.take(widget.maxVisible).toList();
    final overflow = board.tasks.length - visible.length;
    return Material(
      color: scheme.surface,
      elevation: 4,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.title,
                    style: TpTextStyles.of(context).mdColored(
                      scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.countText,
                    style: TpTextStyles.of(context).smColored(
                      scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _expanded = false),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_fullscreen_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final task in visible) _TaskRow(task: task),
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.moreLabel(overflow),
                    style: TpTextStyles.of(context).smColored(
                      scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final CliTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = task.subject.trim().isEmpty ? '…' : task.subject;
    final done = task.status == CliTaskStatus.completed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _TaskStatusIcon(
              status: task.status,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context)
                  .smColored(scheme.onSurface)
                  .copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.status, required this.color});

  final CliTaskStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      CliTaskStatus.pending => Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: color,
      ),
      CliTaskStatus.inProgress => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      CliTaskStatus.completed => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: color,
      ),
      CliTaskStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 16,
        color: color,
      ),
      CliTaskStatus.unknown => Icon(
        Icons.help_outline,
        size: 16,
        color: color,
      ),
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/chat/session_cli_task_panel_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_cli_task_panel.dart client/test/pages/chat/session_cli_task_panel_test.dart
git commit -m "feat(chat): floating CLI task panel (collapsed pill + card)"
```

---

## Task 7: Wire into `SessionChatView`

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`

**Interfaces:**
- Consumes: `CliTaskBoardController` (Task 2), `AiToolCallBubbleScope` (Task 4), `cliTaskBubbleBuilders` + bubbles (Task 5), `SessionCliTaskPanel` (Task 6), `context.l10n.cliTaskBoard*` (Task 3).

- [ ] **Step 1: Add imports**

In `client/lib/pages/chat/session_chat_view.dart`, add to the import block (alphabetical, alongside the other `services/` and page imports):

```dart
import '../../services/cli/tasks/cli_task_board_controller.dart';
import 'cli_task_bubbles.dart';
import 'session_cli_task_panel.dart';
```

(`AiToolCallBubbleScope` comes from `package:ai_message_ui/ai_message_ui.dart`, already imported.)

- [ ] **Step 2: Add the controller field**

Near the other controller fields (e.g. after `AiHistorySeat? _seat;`):

```dart
  CliTaskBoardController? _taskBoardController;
```

- [ ] **Step 3: Create/dispose the controller in seat lifecycle**

In `_bindSeat()`, after the existing `_seat = ...ensureSeat(...)` assignment:

```dart
    final seat = _seat;
    _taskBoardController?.dispose();
    _taskBoardController = seat == null
        ? null
        : CliTaskBoardController(seat.runtime);
```

In `dispose()`, after the existing `_liveRefresh` teardown:

```dart
    _taskBoardController?.dispose();
    _taskBoardController = null;
```

(`_bindSeat` is already re-invoked from `didUpdateWidget` on seat change, so the controller is recreated with the new seat's runtime.)

- [ ] **Step 4: Wrap the thread in `AiToolCallBubbleScope`**

In `build`, replace:

```dart
          return MarkdownDisplayModeScope(
            userMessageMode: prefs.userMessageMode,
            codeBlockMode: prefs.chatCodeBlockMode,
            child: SessionHistoryReviewMessages(
```

with:

```dart
          return MarkdownDisplayModeScope(
            userMessageMode: prefs.userMessageMode,
            codeBlockMode: prefs.chatCodeBlockMode,
            child: AiToolCallBubbleScope(
              builders: cliTaskBubbleBuilders(),
              child: SessionHistoryReviewMessages(
```

and the corresponding closing parens: the block currently ends with `),\n          );\n        },` — the `SessionHistoryReviewMessages(` closes with `),` then `MarkdownDisplayModeScope` closes with `);`. After the change it needs one more `),` for `AiToolCallBubbleScope`. The new tail is:

```dart
              child: SessionHistoryReviewMessages(
                state: state,
                runtime: historySeat.runtime,
                onRetry: () => _loadHistory(force: true),
                onLoadOlder: historySeat.loadOlder,
                liveChrome: liveChrome,
              ),
              ),
            ),
          );
```

- [ ] **Step 5: Add the floating panel to the message Stack**

In the message-area `Stack(children: [ Builder(...), if (top != null) Positioned.fill(...) ])`, add as the **last** child (after the `if (top != null) ...` block):

```dart
          if (_taskBoardController != null)
            Positioned(
              top: spacing.sm,
              right: spacing.sm,
              child: ListenableBuilder(
                listenable: _taskBoardController!,
                builder: (context, _) {
                  final board = _taskBoardController!.board;
                  if (board.totalCount == 0) return const SizedBox.shrink();
                  return SessionCliTaskPanel(
                    board: board,
                    title: l10n.cliTaskBoardTitle,
                    countText: l10n.cliTaskBoardCount(
                      board.completedCount,
                      board.totalCount,
                    ),
                    moreLabel: (count) => l10n.cliTaskBoardMore(count),
                  );
                },
              ),
            ),
```

(`l10n` and `spacing` are already defined at the top of `build` as `final l10n = context.l10n;` and `final spacing = context.tpSpacing;`.)

- [ ] **Step 6: Analyze + run chat tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

Run: `cd client && flutter test test/pages/chat/ai_history_multi_seat_widget_test.dart test/pages/chat/cli_task_bubbles_test.dart test/pages/chat/session_cli_task_panel_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart
git commit -m "feat(chat): wire CLI task panel + bubble scope into session chat view"
```

---

## Task 8: Full verification

- [ ] **Step 1: Run the full suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze clean; all unit/widget tests pass.

- [ ] **Step 2: Manual smoke (desktop)**

Launch the app, open a session whose transcript contains `TaskCreate`/`TaskUpdate` tool calls (e.g. a session that ran a plan):
1. The task panel pill appears in the top-right of the chat; tap it → 320 px card with title, `completed/total`, status icons + subjects, `+N more` overflow.
2. The `TaskCreate`/`TaskUpdate` rows in the thread render as task bubbles (subject + status pill) instead of generic "Used tool:" rows.
3. Sending a new message that triggers more task updates refreshes the panel live.
4. Switching member tabs rebinds the panel to the new seat (per-seat board).

- [ ] **Step 3: Final commit (if any uncommitted changes remain)**

```bash
git status
```

If the smoke test surfaced no code changes, there is nothing to commit here — the previous tasks are already committed.

---

## Self-Review

**Spec coverage:**
- Domain model + reducer (spec §1) → Task 1 ✓
- Memoizing presenter (spec §2) → Task 2 ✓
- l10n (spec panel title/count/more/status) → Task 3 ✓
- Bubble hook (spec §4) → Task 4 ✓
- Task bubbles (spec §4) → Task 5 ✓
- Floating panel (spec §3) → Task 6 ✓
- Wiring (spec §5) → Task 7 ✓
- Verification (spec §6) → Task 8 ✓
- Error handling: placeholder on update-before-create (Task 1 test), id-less create (Task 1), unknown status (Task 1), empty board hides panel (Task 6 test) ✓
- Future work explicitly deferred (cross-member aggregation, more tools, interaction) — not implemented ✓

**Placeholder scan:** every code step contains full source; no TBD/TODO. ✓

**Type consistency:** `CliTaskStatus`, `CliTask`, `CliTaskBoard`, `reduceCliTaskBoard`, `cliTaskStatusFromString`, `CliTaskBoardController`, `AiToolCallBubbleBuilder`, `AiToolCallBubbleScope`, `SessionCliTaskPanel`, `cliTaskBubbleBuilders`, `CliTaskCreateBubble`, `CliTaskUpdateBubble` are defined once and referenced consistently across tasks. Generated l10n getter names (`cliTaskBoardCount(int, int)`, `cliTaskBoardMore(int)`, `cliTaskStatus*`) match the ARB placeholders. ✓
