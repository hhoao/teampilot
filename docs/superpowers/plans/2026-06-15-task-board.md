# Task Board (AI Agent Work Tracker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only task board panel to the right tools switcher that mirrors the active mixed-mode team's TeamBus task queue (pending / claimed / done).

**Architecture:** Three new components — `BoardColumn` (status→lane mapping), `BoardCubit` (1.5s poll of `TeamBus.listTasks()`, isomorphic to `MailboxCubit`), `BoardPanel` (vertical 3-lane rendering). Zero new persistence; read-only over existing in-memory `TaskQueue`. Wired into `RightToolsPanel` gated identically to mailbox (mixed-mode + active bus only), plus a `boardVisible` layout preference.

**Tech Stack:** Flutter, flutter_bloc (`Cubit`/`Equatable`), existing `TeamBus`/`TeamTask`/`TaskStatus`, Flutter Material.

**Spec:** `docs/superpowers/specs/2026-06-15-task-board-design.md`

---

## File Structure

### New files

| File | Responsibility |
|------|----------------|
| `client/lib/models/board_column.dart` | `BoardColumn` enum + `TaskStatus`↔`BoardColumn` pure mapping |
| `client/lib/cubits/board_cubit.dart` | `BoardCard`, `BoardState`, `BoardCubit` (read-only poll, mirrors MailboxCubit) |
| `client/lib/widgets/right_tools/board_panel.dart` | `BoardPanel` StatefulWidget (attach/detach, 3 lanes, assignee resolution) |
| `client/test/cubits/board_cubit_test.dart` | BoardCubit unit tests (bucketing, lifecycle) |
| `client/test/models/board_column_test.dart` | BoardColumn mapping round-trip |
| `client/test/widgets/board_panel_test.dart` | BoardPanel widget test (render, empty, tap→openMemberTab) |

### Modified files

| File | Change |
|------|--------|
| `client/lib/app/app_shell.dart` | Construct `boardCubit`; expose as field |
| `client/lib/main.dart` | `BlocProvider.value(boardCubit)`; pass to `_AppShutdownScope`; close in dispose |
| `client/lib/widgets/right_tools/right_tools_panel.dart` | Add board `ToolView` gated like mailbox |
| `client/lib/models/layout_preferences.dart` | Add `boardVisible` field (5 places) |
| `client/lib/cubits/layout_cubit.dart` | Add `boardVisible` to `setRegionVisibility` |
| `client/lib/pages/config/layout_region_visibility_section.dart` | Add board `Switch` row |
| `client/lib/utils/app_keys.dart` | Add `boardVisibilitySwitch` key |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | New keys |

---

## Task 1: BoardColumn enum + status mapping

**Files:**
- Create: `client/lib/models/board_column.dart`
- Test: `client/test/models/board_column_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/models/board_column_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/board_column.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  group('BoardColumn', () {
    test('maps each TaskStatus to a lane', () {
      expect(BoardColumn.forStatus(TaskStatus.pending), BoardColumn.pending);
      expect(BoardColumn.forStatus(TaskStatus.claimed), BoardColumn.claimed);
      expect(BoardColumn.forStatus(TaskStatus.done), BoardColumn.done);
      expect(BoardColumn.forStatus(TaskStatus.failed), BoardColumn.done);
      expect(BoardColumn.forStatus(TaskStatus.cancelled), BoardColumn.done);
    });

    test('statusesFor round-trips every status into exactly one column', () {
      for (final s in TaskStatus.values) {
        final col = BoardColumn.forStatus(s);
        expect(BoardColumn.statusesFor(col), contains(s));
      }
      // every column is non-empty
      for (final c in BoardColumn.values) {
        expect(BoardColumn.statusesFor(c), isNotEmpty);
      }
    });

    test('pending and claimed columns hold exactly one status', () {
      expect(BoardColumn.statusesFor(BoardColumn.pending),
          [TaskStatus.pending]);
      expect(BoardColumn.statusesFor(BoardColumn.claimed),
          [TaskStatus.claimed]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/board_column_test.dart`
Expected: FAIL — `board_column.dart` does not exist / `BoardColumn` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/models/board_column.dart`:

```dart
import '../services/team_bus/tasks/team_task.dart';

/// Read-only board lanes. Collapses TaskStatus's three terminals into a
/// single [done] lane (per-card outcome icon distinguishes done/failed/
/// cancelled). See docs/superpowers/specs/2026-06-15-task-board-design.md §4.1.
enum BoardColumn { pending, claimed, done }

/// Pure mapping between [TaskStatus] and [BoardColumn].
extension BoardColumnMapping on BoardColumn {
  static BoardColumn forStatus(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return BoardColumn.pending;
      case TaskStatus.claimed:
        return BoardColumn.claimed;
      case TaskStatus.done:
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        return BoardColumn.done;
    }
  }

  static List<TaskStatus> statusesFor(BoardColumn column) {
    switch (column) {
      case BoardColumn.pending:
        return const [TaskStatus.pending];
      case BoardColumn.claimed:
        return const [TaskStatus.claimed];
      case BoardColumn.done:
        return const [
          TaskStatus.done,
          TaskStatus.failed,
          TaskStatus.cancelled,
        ];
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/board_column_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/board_column.dart client/test/models/board_column_test.dart
git commit -m "feat(board): add BoardColumn enum with TaskStatus mapping"
```

---

## Task 2: BoardCubit (read-only poll)

**Files:**
- Create: `client/lib/cubits/board_cubit.dart`
- Test: `client/test/cubits/board_cubit_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/board_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/board_cubit.dart';
import 'package:teampilot/models/board_column.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

/// Minimal double exposing only listTasks(), which is all BoardCubit reads.
class _StubBus implements TeamBus {
  _StubBus(this._tasks);
  final List<TeamTask> _tasks;

  @override
  List<TeamTask> listTasks({TaskStatus? status}) {
    if (status == null) return List.unmodifiable(_tasks);
    return _tasks.where((t) => t.status == status).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('StubBus: ${invocation.memberName}');
}

TeamTask _task(String id, int seq, TaskStatus s, {String? assignee}) =>
    TeamTask(
      id: id,
      seq: seq,
      title: 'Task $seq',
      brief: '',
      createdBy: 'team-lead',
      createdAt: 0,
      status: s,
      assignee: assignee,
    );

void main() {
  group('BoardCubit', () {
    test('emits empty state when bus is null', () async {
      final cubit = BoardCubit(activeBus: () => null);
      cubit.attach();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.total, 0);
      expect(cubit.state.columns[BoardColumn.pending], isNull);
      cubit.detach();
      await cubit.close();
    });

    test('buckets tasks by status on attach', () async {
      final bus = _StubBus([
        _task('a', 1, TaskStatus.pending),
        _task('b', 2, TaskStatus.claimed, assignee: 'developer'),
        _task('c', 3, TaskStatus.done, assignee: 'reviewer'),
        _task('d', 4, TaskStatus.failed, assignee: 'reviewer'),
      ]);
      final cubit = BoardCubit(
        activeBus: () => bus,
        pollInterval: const Duration(milliseconds: 10),
      );
      cubit.attach();
      // Allow the immediate _tick() to run.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.total, 4);
      expect(cubit.state.columns[BoardColumn.pending]!.length, 1);
      expect(cubit.state.columns[BoardColumn.claimed]!.length, 1);
      expect(cubit.state.columns[BoardColumn.done]!.length, 2);
      // seq preserved within a column
      expect(cubit.state.columns[BoardColumn.pending]!.first.seq, 1);
      expect(cubit.state.columns[BoardColumn.done]!.first.seq, 3);

      cubit.detach();
      await cubit.close();
    });

    test('detach clears state to empty', () async {
      final bus = _StubBus([_task('a', 1, TaskStatus.pending)]);
      final cubit = BoardCubit(activeBus: () => bus);
      cubit.attach();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state.total, 1);

      cubit.detach();
      expect(cubit.state.total, 0);
      expect(cubit.state.columns, isEmpty);
      await cubit.close();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/board_cubit_test.dart`
Expected: FAIL — `board_cubit.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/cubits/board_cubit.dart`:

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/board_column.dart';
import '../services/team_bus/tasks/team_task.dart';
import '../services/team_bus/team_bus.dart';

/// Immutable projection of a [TeamTask] for display. Derived per tick; never
/// persisted. Kept as a separate type so the UI doesn't depend on fields it
/// doesn't render (brief, dependsOn, timestamps).
class BoardCard extends Equatable {
  const BoardCard({
    required this.id,
    required this.seq,
    required this.title,
    required this.status,
    required this.column,
    this.assigneeId,
  });

  final String id;
  final int seq;
  final String title;
  final TaskStatus status;
  final BoardColumn column;

  /// Raw memberId; BoardPanel resolves to a display name. Null when pending.
  final String? assigneeId;

  @override
  List<Object?> get props => [id, seq, title, status, column, assigneeId];
}

class BoardState extends Equatable {
  const BoardState({
    Map<BoardColumn, List<BoardCard>>? columns,
    this.total = 0,
  }) : columns = columns ?? const {};

  final Map<BoardColumn, List<BoardCard>> columns;
  final int total;

  static const empty = BoardState();

  @override
  List<Object?> get props => [columns, total];
}

/// Read-only poll of the active tab's [TeamBus] task queue. Isomorphic to
/// [MailboxCubit]: attach()/detach() gate a periodic timer; each tick reads
/// the synchronous [TeamBus.listTasks] and buckets into [BoardState].
///
/// Mixed-mode only — in native mode the bus's task queue is null and
/// listTasks() returns an empty list, but the panel is gated out of the
/// views list before this cubit is ever attached (see RightToolsPanel).
class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    required TeamBus? Function() activeBus,
    Duration pollInterval = const Duration(milliseconds: 1500),
  })  : _activeBus = activeBus,
        _pollInterval = pollInterval,
        super(const BoardState());

  final TeamBus? Function() _activeBus;
  final Duration _pollInterval;
  Timer? _timer;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    _timer?.cancel();
    unawaited(_tick());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _timer?.cancel();
    _timer = null;
    if (state != BoardState.empty) emit(BoardState.empty);
  }

  Future<void> _tick() async {
    if (!_attached || isClosed) return;
    final bus = _activeBus();
    if (bus == null) {
      if (state != BoardState.empty) emit(BoardState.empty);
      return;
    }
    final tasks = bus.listTasks();
    if (!_attached || isClosed) return;
    emit(_bucket(tasks));
  }

  BoardState _bucket(List<TeamTask> tasks) {
    final columns = <BoardColumn, List<BoardCard>>{
      for (final c in BoardColumn.values) c: <BoardCard>[],
    };
    for (final t in tasks) {
      final column = BoardColumnMapping.forStatus(t.status);
      columns[column]!.add(BoardCard(
        id: t.id,
        seq: t.seq,
        title: t.title,
        status: t.status,
        column: column,
        assigneeId: t.assignee,
      ));
    }
    return BoardState(columns: columns, total: tasks.length);
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/board_cubit_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/board_cubit.dart client/test/cubits/board_cubit_test.dart
git commit -m "feat(board): add BoardCubit read-only poll of TeamBus tasks"
```

---

## Task 3: BoardPanel UI

**Files:**
- Create: `client/lib/widgets/right_tools/board_panel.dart`
- Test: `client/test/widgets/board_panel_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/widgets/board_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/board_cubit.dart';
import 'package:teampilot/models/board_column.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/widgets/right_tools/board_panel.dart';

void main() {
  testWidgets('renders columns and assignee chip', (tester) async {
    final boardCubit = BoardCubit(activeBus: () => null);
    boardCubit.emit(BoardState(
      columns: {
        BoardColumn.pending: [
          const BoardCard(
              id: 'a', seq: 1, title: 'Write docs', status: TaskStatus.pending,
              column: BoardColumn.pending),
        ],
        BoardColumn.claimed: [
          const BoardCard(
              id: 'b', seq: 2, title: 'Refactor', status: TaskStatus.claimed,
              column: BoardColumn.claimed, assigneeId: 'developer'),
        ],
        BoardColumn.done: const [],
      },
      total: 2,
    ));

    final team = TeamConfig(
      id: 't1',
      name: 'Team',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      members: [
        TeamMemberConfig(id: 'developer', name: 'Dev'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: boardCubit,
          // No ChatCubit in tree → BoardPanel taps are a no-op. The render
          // assertions below don't need it. (Tap→openMemberTab is exercised
          // in a manual golden-path check; see Task 8.)
          child: BoardPanel(team: team, cwd: '/proj'),
        ),
      ),
    );

    expect(find.text('Write docs'), findsOneWidget);
    expect(find.text('Refactor'), findsOneWidget);
    expect(find.text('› Dev'), findsOneWidget); // resolved assignee chip

    await boardCubit.close();
  });

  testWidgets('shows empty state when no tasks', (tester) async {
    final boardCubit = BoardCubit(activeBus: () => null);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: boardCubit,
          child: BoardPanel(
            team: TeamConfig(
              id: 't1', name: 'Team', cli: CliTool.claude,
              teamMode: TeamMode.mixed, members: const [],
            ),
            cwd: '/proj',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.view_kanban_outlined), findsOneWidget);

    await boardCubit.close();
  });
}
```

**Note:** This test renders `BoardPanel` without a `ChatCubit` in the widget tree. The render and empty-state assertions don't need one. `_openAssignee` (the tap handler) calls `context.read<ChatCubit>()` — tapping a claimed card in this test would throw, but we don't tap here. The tap→`openMemberTab` path is covered by the manual golden-path check in Task 8 (it needs a real cubit graph). If you want an automated tap test, first check `client/test/widgets/` for an existing `MockChatCubit` pattern to mirror — don't hand-stub `ChatCubit`'s constructor.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/board_panel_test.dart`
Expected: FAIL — `board_panel.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/widgets/right_tools/board_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/board_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/board_column.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/tasks/team_task.dart';

/// Live read-only task board for a mixed-mode team. Attaches [BoardCubit]'s
/// poll while mounted (mirrors MailboxPanel). Tapping a claimed card opens
/// the assignee's chat tab.
class BoardPanel extends StatefulWidget {
  const BoardPanel({required this.team, required this.cwd, super.key});

  final TeamConfig team;
  final String cwd;

  @override
  State<BoardPanel> createState() => _BoardPanelState();
}

class _BoardPanelState extends State<BoardPanel> {
  late final BoardCubit _boardCubit;

  @override
  void initState() {
    super.initState();
    _boardCubit = context.read<BoardCubit>()..attach();
  }

  @override
  void dispose() {
    _boardCubit.detach();
    super.dispose();
  }

  String _memberName(String? id) {
    if (id == null) return '';
    final m = widget.team.members.cast<TeamMemberConfig?>().firstWhere(
          (m) => m?.id == id,
          orElse: () => null,
        );
    return m?.name ?? id;
  }

  void _openAssignee(String? assigneeId) {
    if (assigneeId == null) return;
    final matches = widget.team.members.where((m) => m.id == assigneeId);
    if (matches.isEmpty) return;
    unawaited(context.read<ChatCubit>().openMemberTab(
          widget.team,
          matches.first,
          workspaceCwd: widget.cwd,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final state = context.watch<BoardCubit>().state;

    if (state.total == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_kanban_outlined,
                size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(l10n.boardEmpty,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final column in BoardColumn.values)
          _ColumnSection(
            column: column,
            cards: state.columns[column] ?? const [],
            memberName: _memberName,
            onTapCard: _openAssignee,
          ),
      ],
    );
  }
}

class _ColumnSection extends StatelessWidget {
  const _ColumnSection({
    required this.column,
    required this.cards,
    required this.memberName,
    required this.onTapCard,
  });

  final BoardColumn column;
  final List<BoardCard> cards;
  final String Function(String?) memberName;
  final void Function(String?) onTapCard;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final tt = Theme.of(context).textTheme;

    final (icon, label) = switch (column) {
      BoardColumn.pending =>
        (Icons.hourglass_top_outlined, l10n.boardPending),
      BoardColumn.claimed =>
        (Icons.play_circle_outline, l10n.boardClaimed),
      BoardColumn.done => (Icons.check_circle_outline, l10n.boardDone),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(icon, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label,
                  style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('(${cards.length})',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        for (final card in cards)
          _CardTile(
            card: card,
            memberName: memberName(card.assigneeId),
            onTap: card.column == BoardColumn.claimed
                ? () => onTapCard(card.assigneeId)
                : null,
          ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.memberName,
    required this.onTap,
  });

  final BoardCard card;
  final String memberName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isError =
        card.status == TaskStatus.failed || card.status == TaskStatus.cancelled;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('#${card.seq}',
                style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (memberName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('› $memberName',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (card.column == BoardColumn.done)
              Icon(
                card.status == TaskStatus.done
                    ? Icons.check
                    : card.status == TaskStatus.failed
                        ? Icons.close
                        : Icons.remove,
                size: 14,
                color: isError ? cs.error : cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/board_panel_test.dart`
Expected: PASS. If the `ChatCubit` fake doesn't compile, simplify the test per the note in Step 1 (drop the tap assertion; keep render + empty).

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/right_tools/board_panel.dart client/test/widgets/board_panel_test.dart
git commit -m "feat(board): add BoardPanel read-only task board UI"
```

---

## Task 4: Wire BoardCubit into app shell + main

**Files:**
- Modify: `client/lib/app/app_shell.dart` (around L578)
- Modify: `client/lib/main.dart` (L68-100, L231-235, L272-294)

- [ ] **Step 1: Construct and expose boardCubit in app_shell.dart**

In `client/lib/app/app_shell.dart`, find the mailbox cubit construction (L578-579):

```dart
  final mailboxCubit =
      MailboxCubit(activeBus: () => chatCubit.activeTab?.teamBus);
```

Add immediately after it:

```dart
  final boardCubit =
      BoardCubit(activeBus: () => chatCubit.activeTab?.teamBus);
```

Then expose `boardCubit` as a field on the `AppShell` class, exactly mirroring how `mailboxCubit` is exposed. Search for `mailboxCubit` declarations in this file (the `final MailboxCubit mailboxCubit;` field and the constructor parameter) and add `boardCubit` alongside each. Add the import at the top:

```dart
import '../cubits/board_cubit.dart';
```

- [ ] **Step 2: Provide + dispose in main.dart**

In `client/lib/main.dart`:

(a) Add `boardCubit` to `_AppShutdownScope` constructor + field + dispose. At L68-82, add `required this.boardCubit,` to the constructor and `final BoardCubit boardCubit;` field (mirror `mailboxCubit`). At L90-91, add after the mailbox close:

```dart
    unawaited(widget.boardCubit.close());
```

(b) At L231-235, pass it into the scope:

```dart
        return _AppShutdownScope(
          chatCubit: shell.chatCubit,
          mailboxCubit: shell.mailboxCubit,
          boardCubit: shell.boardCubit,
          notificationCubit: shell.notificationCubit,
          workspaceTerminalRegistry: shell.workspaceTerminalRegistry,
```

(c) At L272-294, add the provider after the mailbox provider (L276):

```dart
                BlocProvider.value(value: shell.boardCubit),
```

Add the import at the top:

```dart
import 'cubits/board_cubit.dart';
```

- [ ] **Step 3: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/main.dart lib/app/app_shell.dart`
Expected: No new errors (only pre-existing warnings if any).

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(board): wire BoardCubit into app shell and providers"
```

---

## Task 5: Add board ToolView to RightToolsPanel

**Files:**
- Modify: `client/lib/widgets/right_tools/right_tools_panel.dart` (L212-219, L197 region)

- [ ] **Step 1: Add the board view, gated like mailbox**

In `client/lib/widgets/right_tools/right_tools_panel.dart`, find the mailbox block (L212-219):

```dart
    if (showMailbox) {
      views.add(ToolView(
        icon: Icons.mail_outline,
        label: context.l10n.mailbox,
        badgeCount: mailboxState.totalUnread,
        child: MailboxPanel(team: team, cwd: widget.cwd),
      ));
    }
```

Add the board block immediately after it. Also add the `showBoard` computation near the `showMailbox` definition (around L117-122). The `showBoard` condition is identical to `showMailbox` minus the unread-count nuance — board reuses the same bus/mixed-mode gate.

Add after `showMailbox` is computed (around L122):

```dart
    // Board is mixed-mode-only and consumes the same TeamBus as mailbox; it
    // shares mailbox's gate (the unread badge is mailbox-specific and doesn't
    // affect whether the bus exists).
    final showBoard = showMailbox;
```

Then add the view after the mailbox `views.add` block:

```dart
    if (showBoard) {
      views.add(ToolView(
        icon: Icons.view_kanban_outlined,
        label: context.l10n.board,
        child: BoardPanel(team: team, cwd: widget.cwd),
      ));
    }
```

Add imports at top of file:

```dart
import 'board_panel.dart';
```

(`BoardCubit` is read via `context.read` inside `BoardPanel` — it comes from the provider added in Task 4, no panel-level wiring needed.)

- [ ] **Step 2: Verify it compiles + analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/right_tools/right_tools_panel.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/widgets/right_tools/right_tools_panel.dart
git commit -m "feat(board): add task board tab to right tools panel"
```

---

## Task 6: Add boardVisible layout preference + settings toggle

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart` (L58-72)
- Modify: `client/lib/pages/config/layout_region_visibility_section.dart`
- Modify: `client/lib/utils/app_keys.dart`

- [ ] **Step 1: Add boardVisible to LayoutPreferences**

In `client/lib/models/layout_preferences.dart`:

(a) Constructor (around L9-33): add `this.boardVisible = true,` near `this.gitVisible = true,`.

(b) `fromJson` (around L47): add after `gitVisible:`:

```dart
      boardVisible: json['boardVisible'] as bool? ?? true,
```

(c) Field declarations (around L134): add `final bool boardVisible;` after `final bool gitVisible;`.

(d) `copyWith` parameter (around L162): add `bool? boardVisible,`.

(e) `copyWith` body (around L186): add `boardVisible: boardVisible ?? this.boardVisible,`.

(f) `toJson` (around L272): add `'boardVisible': boardVisible,`.

- [ ] **Step 2: Add boardVisible to LayoutCubit.setRegionVisibility**

In `client/lib/cubits/layout_cubit.dart`, modify `setRegionVisibility` (L58-72) — add `bool? boardVisible,` parameter and `boardVisible: boardVisible,` to the `copyWith` call:

```dart
  Future<void> setRegionVisibility({
    required bool appRailVisible,
    required bool membersVisible,
    required bool fileTreeVisible,
    bool? gitVisible,
    bool? boardVisible,
  }) {
    return _save(
      state.preferences.copyWith(
        appRailVisible: appRailVisible,
        membersVisible: membersVisible,
        fileTreeVisible: fileTreeVisible,
        gitVisible: gitVisible,
        boardVisible: boardVisible,
      ),
    );
  }
```

- [ ] **Step 3: Add boardVisible Switch to settings UI**

In `client/lib/pages/config/layout_region_visibility_section.dart`:

(a) Expand the BlocSelector record type from `(bool, bool, bool)` to `(bool, bool, bool, bool)` (L17), adding `boardVisible`:

```dart
    return BlocSelector<LayoutCubit, LayoutState, (bool, bool, bool, bool)>(
      selector: (state) => (
        state.preferences.membersVisible,
        state.preferences.fileTreeVisible,
        state.preferences.gitVisible,
        state.preferences.boardVisible,
      ),
      builder: (context, visibility) {
        final (membersVisible, fileTreeVisible, gitVisible, boardVisible) =
            visibility;

        void setVisibility({
          bool? membersVisible,
          bool? fileTreeVisible,
          bool? gitVisible,
          bool? boardVisible,
        }) {
          controller.setRegionVisibility(
            appRailVisible: true,
            membersVisible: membersVisible ?? visibility.$1,
            fileTreeVisible: fileTreeVisible ?? visibility.$2,
            gitVisible: gitVisible ?? visibility.$3,
            boardVisible: boardVisible ?? visibility.$4,
          );
        }
```

(b) Add `showDividerBelow: true` to the git SettingsLabeledRow (currently `showDividerBelow: false` at L70), and append a new board row:

```dart
            SettingsLabeledRow(
              title: l10n.board,
              subtitle: l10n.visibilityBoardHint,
              trailing: Switch(
                key: AppKeys.boardVisibilitySwitch,
                value: boardVisible,
                onChanged: (value) => setVisibility(boardVisible: value),
              ),
              showDividerBelow: false,
            ),
```

- [ ] **Step 4: Add AppKeys.boardVisibilitySwitch**

In `client/lib/utils/app_keys.dart`, add (near the existing visibility switch keys):

```dart
  static const boardVisibilitySwitch = Key('boardVisibilitySwitch');
```

- [ ] **Step 5: Gate the board view on boardVisible**

In `client/lib/widgets/right_tools/right_tools_panel.dart`, change the board `showBoard` line added in Task 5 to also respect the preference:

```dart
    final showBoard =
        showMailbox && widget.preferences.boardVisible;
```

- [ ] **Step 6: Verify it compiles + analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models/layout_preferences.dart lib/cubits/layout_cubit.dart lib/pages/config/layout_region_visibility_section.dart lib/utils/app_keys.dart lib/widgets/right_tools/right_tools_panel.dart`
Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart client/lib/pages/config/layout_region_visibility_section.dart client/lib/utils/app_keys.dart client/lib/widgets/right_tools/right_tools_panel.dart
git commit -m "feat(board): add boardVisible layout preference and settings toggle"
```

---

## Task 7: l10n strings + regenerate

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations*.dart`, `client/lib/widgets/warmup_glyphs.g.dart`

- [ ] **Step 1: Add English keys**

In `client/lib/l10n/app_en.arb`, add (near the mailbox keys, L602-603):

```json
  "board": "Board",
  "boardEmpty": "No tasks yet",
  "boardPending": "Pending",
  "boardClaimed": "In progress",
  "boardDone": "Done",
  "visibilityBoardHint": "Show the task board for mixed-mode teams.",
```

Also add a `@key` metadata block for `boardEmpty` if the file uses them (check surrounding entries; many keys in this file have no metadata, so plain keys are fine).

- [ ] **Step 2: Add Chinese keys**

In `client/lib/l10n/app_zh.arb`, add the corresponding translations:

```json
  "board": "看板",
  "boardEmpty": "暂无任务",
  "boardPending": "待认领",
  "boardClaimed": "进行中",
  "boardDone": "已完成",
  "visibilityBoardHint": "显示混合模式团队的任务看板。",
```

- [ ] **Step 3: Regenerate localizations + warmup glyphs**

Run:
```bash
cd client && flutter pub get
```
(this regenerates `app_localizations*.dart`)

Then per AGENTS.md l10n rule:
```bash
cd client && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 4: Verify the new keys are present in generated code**

Run: `cd client && findstr /c:"boardEmpty" lib\l10n\app_localizations_en.dart`
Expected: a match (the generated accessor).

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/widgets/warmup_glyphs.g.dart
git commit -m "feat(board): add l10n strings for task board"
```

---

## Task 8: Full verification

- [ ] **Step 1: Run analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No errors related to board files.

- [ ] **Step 2: Run all non-integration tests**

Run: `cd client && flutter test --exclude-tags integration`
Expected: All pass, including the 3 new test files.

- [ ] **Step 3: Manual golden-path check (document per AGENTS.md)**

Since the board requires a live mixed-mode team session (real TeamBus), CI can't cover the end-to-end render. Manually verify:

1. Open a mixed-mode team project.
2. Launch members; have the leader agent create tasks (via its normal `add_tasks` MCP flow).
3. Confirm the Board tab appears in the right tools switcher (after Mailbox).
4. Confirm tasks appear in Pending; move to Claimed when a worker picks them up; move to Done (colored by outcome) on completion.
5. Switch away from the Board tab → confirm no continued polling (CPU settles).
6. Switch to a native-mode team → confirm the Board tab does NOT appear.
7. Toggle the Board visibility switch in Settings → confirm the tab hides/shows.

- [ ] **Step 4: Final commit if any fixes were needed**

If verification surfaced fixes, commit them. Otherwise nothing to commit.

---

## Out of scope (per spec §2, §9)

- Manual task creation/editing (read-only board only).
- Native-mode task visibility (CLI-private task tables).
- Drag-to-reassign.
- Board UI state persistence (collapsed columns/filters).
