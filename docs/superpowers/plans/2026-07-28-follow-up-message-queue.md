# Follow-up Message Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the selected member is `working`, queue follow-up text from History compose and Terminal (shared per-seat store), with Cursor-like 「N Queued」 edit/reorder/delete; drain one item on idle while armed; Stop pauses drain until Resume.

**Architecture:** Pure `FollowUpQueueStore` keyed by `sessionId:memberId`, cubit-owned `FollowUpQueueDrainer` that calls the existing `submitSessionHistoryReviewMessage` / `deliverUserCommandToMember` path, shared `FollowUpQueueStrip` + submit gate helpers. Terminal gains a compact follow-up compose bar (PTY alone cannot stage unsent follow-ups). Mailbox Queued / Parked stay separate.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing History continue delivery, `Tp*` / `shared_ui`, unit + widget tests under `client/test/`.

**Spec:** `docs/superpowers/specs/2026-07-28-follow-up-message-queue-design.md`

## Global Constraints

- History **and** Terminal share one seat queue (`sessionId` + `memberId`; Simple sole seat uses the same shell member id as continue).
- Busy + empty input → **Stop**; busy + non-empty → **Send enqueues** (no deliver).
- Drain: idle + `armed` → deliver **one** head; success then remove; failure leaves head; no chain-fire in same idle tick if busy again.
- Stop → interrupt turn **and** `pause` drain; Resume → `armed` + try drain if idle.
- Do **not** route follow-ups through `parkedUserSubmissions` or mailbox Queued streams.
- Busy signal: selected-member `isMemberWorking` (same as Stop), not session `workingSessionIds` alone.
- In-memory only; clear on session/tab dispose.
- l10n only via `app_en.arb` / `app_zh.arb` (distinct keys from mailbox Queued).
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and run all new/changed tests listed in tasks.

---

## File map

| File | Role |
|------|------|
| `client/lib/services/follow_up/follow_up_queue.dart` | **Create** — models + `FollowUpQueueStore` / `InMemoryFollowUpQueueStore` |
| `client/test/services/follow_up/follow_up_queue_store_test.dart` | **Create** |
| `client/lib/services/follow_up/follow_up_submit_gate.dart` | **Create** — enqueue vs deliver vs stop decision |
| `client/lib/pages/chat/compose_stop_visibility.dart` | Extend Stop visibility with empty-text gate |
| `client/test/pages/chat/compose_stop_visibility_test.dart` | Extend |
| `client/test/services/follow_up/follow_up_submit_gate_test.dart` | **Create** |
| `client/lib/services/follow_up/follow_up_queue_drainer.dart` | **Create** — idle-edge drain orchestration |
| `client/test/services/follow_up/follow_up_queue_drainer_test.dart` | **Create** |
| `client/lib/cubits/chat_cubit.dart` | Own store + drainer; clear on close; façades |
| `client/lib/widgets/follow_up/follow_up_queue_strip.dart` | **Create** — collapsible strip UI |
| `client/test/widgets/follow_up/follow_up_queue_strip_test.dart` | **Create** |
| `client/lib/pages/chat/session_chat_view.dart` | Gate submit; mount strip; Stop→pause; Resume |
| `client/lib/pages/chat/chat_workbench_terminal.dart` | Follow-up strip + compact compose when busy/queue |
| `client/lib/pages/chat_workbench.dart` | Wire Terminal follow-up deliver + Stop/Resume to cubit |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Follow-up strings |
| `client/test/pages/chat/session_follow_up_queue_test.dart` | **Create** — History gate + strip smoke (as feasible) |

---

### Task 1: `FollowUpQueueStore` (pure state)

**Files:**
- Create: `client/lib/services/follow_up/follow_up_queue.dart`
- Create: `client/test/services/follow_up/follow_up_queue_store_test.dart`

**Interfaces:**
- Produces:
  - `String followUpSeatKey(String sessionId, String memberId)`
  - `FollowUpQueuedMessage`, `FollowUpDrainMode`, `FollowUpQueue`
  - `InMemoryFollowUpQueueStore` with `queueFor` / `watch` / `enqueue` / `edit` / `moveUp` / `remove` / `pause` / `resume` / `clearSeat` / `clearSession`
- Consumes: none

- [ ] **Step 1: Write the failing store tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';

void main() {
  late InMemoryFollowUpQueueStore store;

  setUp(() {
    store = InMemoryFollowUpQueueStore();
  });

  test('enqueue appends and watch emits', () async {
    final seat = followUpSeatKey('s1', 'm1');
    final events = <FollowUpQueue>[];
    final sub = store.watch(seat).listen(events.add);

    store.enqueue(seat, 'a');
    store.enqueue(seat, 'b');
    await Future<void>.delayed(Duration.zero);

    expect(store.queueFor(seat).items.map((e) => e.content), ['a', 'b']);
    expect(events.last.items.map((e) => e.content), ['a', 'b']);
    await sub.cancel();
  });

  test('edit empty removes; moveUp swaps with previous', () {
    final seat = followUpSeatKey('s1', 'm1');
    store.enqueue(seat, 'a');
    store.enqueue(seat, 'b');
    final idB = store.queueFor(seat).items[1].id;
    store.moveUp(seat, idB);
    expect(store.queueFor(seat).items.map((e) => e.content), ['b', 'a']);
    store.edit(seat, store.queueFor(seat).items.first.id, '   ');
    expect(store.queueFor(seat).items.map((e) => e.content), ['a']);
  });

  test('pause and resume toggle drain without dropping items', () {
    final seat = followUpSeatKey('s1', 'm1');
    store.enqueue(seat, 'x');
    store.pause(seat);
    expect(store.queueFor(seat).drain, FollowUpDrainMode.paused);
    expect(store.queueFor(seat).items, hasLength(1));
    store.resume(seat);
    expect(store.queueFor(seat).drain, FollowUpDrainMode.armed);
  });

  test('clearSession drops all seats for that session', () {
    store.enqueue(followUpSeatKey('s1', 'm1'), 'a');
    store.enqueue(followUpSeatKey('s1', 'm2'), 'b');
    store.enqueue(followUpSeatKey('s2', 'm1'), 'c');
    store.clearSession('s1');
    expect(store.queueFor(followUpSeatKey('s1', 'm1')).items, isEmpty);
    expect(store.queueFor(followUpSeatKey('s1', 'm2')).items, isEmpty);
    expect(store.queueFor(followUpSeatKey('s2', 'm1')).items, hasLength(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/follow_up/follow_up_queue_store_test.dart`

Expected: FAIL (missing library)

- [ ] **Step 3: Implement store**

Create `client/lib/services/follow_up/follow_up_queue.dart`:

```dart
import 'dart:async';

import 'package:uuid/uuid.dart';

String followUpSeatKey(String sessionId, String memberId) =>
    '${sessionId.trim()}:${memberId.trim()}';

final class FollowUpQueuedMessage {
  const FollowUpQueuedMessage({required this.id, required this.content});
  final String id;
  final String content;
}

enum FollowUpDrainMode { armed, paused }

final class FollowUpQueue {
  const FollowUpQueue({
    this.items = const [],
    this.drain = FollowUpDrainMode.armed,
  });
  final List<FollowUpQueuedMessage> items;
  final FollowUpDrainMode drain;

  FollowUpQueue copyWith({
    List<FollowUpQueuedMessage>? items,
    FollowUpDrainMode? drain,
  }) => FollowUpQueue(
    items: items ?? this.items,
    drain: drain ?? this.drain,
  );
}

final class InMemoryFollowUpQueueStore {
  final _queues = <String, FollowUpQueue>{};
  final _controllers = <String, StreamController<FollowUpQueue>>{};
  final _uuid = const Uuid();

  FollowUpQueue queueFor(String seat) =>
      _queues[seat] ?? const FollowUpQueue();

  Stream<FollowUpQueue> watch(String seat) {
    final c = _controllers.putIfAbsent(
      seat,
      () => StreamController<FollowUpQueue>.broadcast(),
    );
    return Stream.multi((multi) {
      multi.add(queueFor(seat));
      final sub = c.stream.listen(multi.add, onError: multi.addError);
      multi.onCancel = sub.cancel;
    });
  }

  void enqueue(String seat, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final q = queueFor(seat);
    _emit(
      seat,
      q.copyWith(
        items: [
          ...q.items,
          FollowUpQueuedMessage(id: _uuid.v4(), content: trimmed),
        ],
      ),
    );
  }

  void edit(String seat, String id, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      remove(seat, id);
      return;
    }
    final q = queueFor(seat);
    _emit(
      seat,
      q.copyWith(
        items: [
          for (final m in q.items)
            if (m.id == id) FollowUpQueuedMessage(id: id, content: trimmed) else m,
        ],
      ),
    );
  }

  void moveUp(String seat, String id) {
    final q = queueFor(seat);
    final i = q.items.indexWhere((m) => m.id == id);
    if (i <= 0) return;
    final next = [...q.items];
    final tmp = next[i - 1];
    next[i - 1] = next[i];
    next[i] = tmp;
    _emit(seat, q.copyWith(items: next));
  }

  void remove(String seat, String id) {
    final q = queueFor(seat);
    _emit(
      seat,
      q.copyWith(items: [for (final m in q.items) if (m.id != id) m]),
    );
  }

  void pause(String seat) =>
      _emit(seat, queueFor(seat).copyWith(drain: FollowUpDrainMode.paused));

  void resume(String seat) =>
      _emit(seat, queueFor(seat).copyWith(drain: FollowUpDrainMode.armed));

  void clearSeat(String seat) {
    _queues.remove(seat);
    _controllers[seat]?.add(const FollowUpQueue());
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}:';
    final keys = _queues.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      clearSeat(k);
    }
  }

  void _emit(String seat, FollowUpQueue q) {
    _queues[seat] = q;
    _controllers[seat]?.add(q);
  }
}
```

If `uuid` is awkward in this package, use a local counter / `UniqueKey`-style string id instead — match whatever nearby code uses for ephemeral ids (e.g. `DateTime.now().microsecondsSinceEpoch` + counter). Prefer existing project id helpers if present.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/follow_up/follow_up_queue_store_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/follow_up/follow_up_queue.dart \
  client/test/services/follow_up/follow_up_queue_store_test.dart
git commit -m "$(cat <<'EOF'
feat(follow-up): add in-memory per-seat follow-up queue store

EOF
)"
```

---

### Task 2: Submit gate + Stop visibility

**Files:**
- Create: `client/lib/services/follow_up/follow_up_submit_gate.dart`
- Create: `client/test/services/follow_up/follow_up_submit_gate_test.dart`
- Modify: `client/lib/pages/chat/compose_stop_visibility.dart`
- Modify: `client/test/pages/chat/compose_stop_visibility_test.dart`

**Interfaces:**
- Produces:
  - `enum FollowUpSubmitAction { deliver, enqueue, stop, block }`
  - `FollowUpSubmitAction resolveFollowUpSubmitAction({required bool permissionWaiting, required bool memberWorking, required bool composeTextEmpty, required bool supportsTurnInterrupt})`
  - `shouldShowComposeStop(..., {required bool composeTextEmpty})` → Stop only when working + supported + empty
- Consumes: none

- [ ] **Step 1: Write failing gate + Stop tests**

`follow_up_submit_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/follow_up/follow_up_submit_gate.dart';

void main() {
  test('permission waiting blocks', () {
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: true,
        memberWorking: false,
        composeTextEmpty: false,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.block,
    );
  });

  test('idle delivers; busy+text enqueues; busy+empty stops when supported', () {
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: false,
        composeTextEmpty: false,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.deliver,
    );
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: true,
        composeTextEmpty: false,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.enqueue,
    );
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: true,
        composeTextEmpty: true,
        supportsTurnInterrupt: true,
      ),
      FollowUpSubmitAction.stop,
    );
    expect(
      resolveFollowUpSubmitAction(
        permissionWaiting: false,
        memberWorking: true,
        composeTextEmpty: true,
        supportsTurnInterrupt: false,
      ),
      FollowUpSubmitAction.block,
    );
  });
}
```

Update `compose_stop_visibility_test.dart` so Stop requires empty text:

```dart
expect(
  shouldShowComposeStop(
    memberWorking: true,
    supportsTurnInterrupt: true,
    composeTextEmpty: false,
  ),
  isFalse,
);
expect(
  shouldShowComposeStop(
    memberWorking: true,
    supportsTurnInterrupt: true,
    composeTextEmpty: true,
  ),
  isTrue,
);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/follow_up/follow_up_submit_gate_test.dart test/pages/chat/compose_stop_visibility_test.dart`

Expected: FAIL (missing gate / wrong Stop signature)

- [ ] **Step 3: Implement**

`follow_up_submit_gate.dart`:

```dart
enum FollowUpSubmitAction { deliver, enqueue, stop, block }

FollowUpSubmitAction resolveFollowUpSubmitAction({
  required bool permissionWaiting,
  required bool memberWorking,
  required bool composeTextEmpty,
  required bool supportsTurnInterrupt,
}) {
  if (permissionWaiting) return FollowUpSubmitAction.block;
  if (!memberWorking) {
    return composeTextEmpty
        ? FollowUpSubmitAction.block
        : FollowUpSubmitAction.deliver;
  }
  if (!composeTextEmpty) return FollowUpSubmitAction.enqueue;
  if (supportsTurnInterrupt) return FollowUpSubmitAction.stop;
  return FollowUpSubmitAction.block;
}
```

`compose_stop_visibility.dart`:

```dart
bool shouldShowComposeStop({
  required bool memberWorking,
  required bool supportsTurnInterrupt,
  required bool composeTextEmpty,
}) =>
    memberWorking && supportsTurnInterrupt && composeTextEmpty;
```

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/follow_up/follow_up_submit_gate.dart \
  client/test/services/follow_up/follow_up_submit_gate_test.dart \
  client/lib/pages/chat/compose_stop_visibility.dart \
  client/test/pages/chat/compose_stop_visibility_test.dart
git commit -m "$(cat <<'EOF'
feat(follow-up): gate deliver vs enqueue vs stop by working and text

EOF
)"
```

---

### Task 3: `FollowUpQueueDrainer`

**Files:**
- Create: `client/lib/services/follow_up/follow_up_queue_drainer.dart`
- Create: `client/test/services/follow_up/follow_up_queue_drainer_test.dart`

**Interfaces:**
- Consumes: `InMemoryFollowUpQueueStore`
- Produces: `FollowUpQueueDrainer` with:
  - `void onMemberWorkingChanged(String seat, {required bool working})`
  - `Future<void> resumeAndMaybeDrain(String seat)`
  - `Future<HistoryContinueSubmitResult> Function(String seat, String content)? deliver` injected

- [ ] **Step 1: Write failing drainer tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/services/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/follow_up/follow_up_queue_drainer.dart';

void main() {
  late InMemoryFollowUpQueueStore store;
  late List<String> delivered;
  late FollowUpQueueDrainer drainer;
  final seat = followUpSeatKey('s1', 'm1');

  setUp(() {
    store = InMemoryFollowUpQueueStore();
    delivered = [];
    drainer = FollowUpQueueDrainer(
      store: store,
      deliver: (s, text) async {
        delivered.add('$s::$text');
        return const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.pty,
        );
      },
    );
  });

  test('idle edge drains one head then removes', () async {
    store.enqueue(seat, 'one');
    store.enqueue(seat, 'two');
    drainer.onMemberWorkingChanged(seat, working: true);
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(delivered, ['$seat::one']);
    expect(store.queueFor(seat).items.map((e) => e.content), ['two']);
  });

  test('paused blocks drain until resume', () async {
    store.enqueue(seat, 'one');
    store.pause(seat);
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(delivered, isEmpty);
    await drainer.resumeAndMaybeDrain(seat);
    expect(delivered, ['$seat::one']);
    expect(store.queueFor(seat).items, isEmpty);
  });

  test('failed deliver leaves head', () async {
    drainer = FollowUpQueueDrainer(
      store: store,
      deliver: (_, __) async => const HistoryContinueSubmitResult.failed(),
    );
    store.enqueue(seat, 'keep');
    await drainer.onMemberWorkingChanged(seat, working: false);
    expect(store.queueFor(seat).items.single.content, 'keep');
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement drainer**

```dart
import '../follow_up/follow_up_queue.dart';
import '../../pages/chat/history_continue_delivery.dart';
import '../../utils/logging/logger.dart';

final class FollowUpQueueDrainer {
  FollowUpQueueDrainer({
    required this.store,
    required this.deliver,
  });

  final InMemoryFollowUpQueueStore store;
  final Future<HistoryContinueSubmitResult> Function(String seat, String content)
      deliver;

  final _inFlight = <String>{};
  final _lastWorking = <String, bool>{};

  Future<void> onMemberWorkingChanged(
    String seat, {
    required bool working,
  }) async {
    final prev = _lastWorking[seat];
    _lastWorking[seat] = working;
    if (working) return;
    // Drain on true→false, or first observation already idle with queue.
    if (prev == true || prev == null) {
      await _tryDrain(seat);
    }
  }

  Future<void> resumeAndMaybeDrain(String seat) async {
    store.resume(seat);
    if (_lastWorking[seat] == true) return;
    await _tryDrain(seat);
  }

  Future<void> _tryDrain(String seat) async {
    if (_inFlight.contains(seat)) return;
    final q = store.queueFor(seat);
    if (q.drain != FollowUpDrainMode.armed || q.items.isEmpty) return;
    final head = q.items.first;
    _inFlight.add(seat);
    try {
      final result = await deliver(seat, head.content);
      if (result.ok) {
        store.remove(seat, head.id);
      } else {
        appLogger.d('follow-up drain failed seat=$seat id=${head.id}');
      }
    } finally {
      _inFlight.remove(seat);
    }
  }
}
```

Tune `onMemberWorkingChanged` so tests pass: when going busy→idle, drain once; do not drain while `working == true`. Prefer calling `_tryDrain` only on falling edge (`prev == true && !working`) plus `resumeAndMaybeDrain`; for the first test, explicitly: set working true then false.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/follow_up/follow_up_queue_drainer.dart \
  client/test/services/follow_up/follow_up_queue_drainer_test.dart
git commit -m "$(cat <<'EOF'
feat(follow-up): drain one queued message on idle when armed

EOF
)"
```

---

### Task 4: Wire store + drainer into `ChatCubit`

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/app/app_shell.dart` (or wherever `ChatCubit` is constructed) only if ctor needs inject
- Create or extend a small cubit-facing test if an existing chat cubit test harness is cheap; otherwise cover via Task 3 + integration in Task 6/7

**Interfaces:**
- Produces on `ChatCubit`:
  - `InMemoryFollowUpQueueStore get followUpQueue`
  - `void pauseFollowUpQueue(String sessionId, String memberId)`
  - `Future<void> resumeFollowUpQueue(String sessionId, String memberId)`
  - `void notifyFollowUpMemberWorking(String sessionId, String memberId, {required bool working})`
  - clear `followUpQueue.clearSession(sessionId)` inside `closeSessionTab` / session dispose paths that already clear attention
- Consumes: store, drainer; `deliver` closes over existing `deliverUserCommandToMember` + connect helpers **or** a callback set from workbench (prefer cubit methods that already power History continue)

**Implementation notes:**

- Construct `InMemoryFollowUpQueueStore` and `FollowUpQueueDrainer` in `ChatCubit` ctor (injectable for tests).
- Drainer `deliver(seat, text)`: parse seat → `sessionId`/`memberId`, then call the same stack as History continue (`ensureMemberInputReady` + `deliverUserCommandToMember` with channel resolution). If channel resolution needs TeamBus from `sessionRuntime`, do it inside cubit — **one** delivery entrypoint used by History drain and Terminal drain.
- From existing working recompute path (where member presence / working updates), call `notifyFollowUpMemberWorking` for seats that have non-empty queues **or** for the selected seat (spec: at least selected + any non-empty armed queue). Minimal correct approach: whenever `isMemberWorking` is consulted/updated for a seat, notify; or after each working-set recompute, iterate seats with `store` keys.

- [ ] **Step 1: Add failing test** (optional lightweight): construct cubit with fake deliver; enqueue; flip working; expect deliver called — only if existing `chat_cubit` test harness supports it without huge setup. If too heavy, skip and rely on drainer unit tests + widget wiring tests; document in commit message.

- [ ] **Step 2: Implement cubit wiring + clearSession on close**

In `closeSessionTab` / session teardown next to `_agentAttentionCubit?.clearSession(sessionId)`:

```dart
_followUpQueue.clearSession(sessionId);
```

Expose pause/resume façades used by UI Stop/Resume.

- [ ] **Step 3: Analyze + targeted tests PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(follow-up): own follow-up queue store and drainer on ChatCubit

EOF
)"
```

---

### Task 5: `FollowUpQueueStrip` UI + l10n

**Files:**
- Create: `client/lib/widgets/follow_up/follow_up_queue_strip.dart`
- Create: `client/test/widgets/follow_up/follow_up_queue_strip_test.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

**Interfaces:**
- Produces: `FollowUpQueueStrip` widget
  - `required FollowUpQueue queue`
  - `required ValueChanged<String> /*id*/ onDelete`
  - `required void Function(String id, String content) onEdit`
  - `required ValueChanged<String> onMoveUp`
  - `VoidCallback? onResume` (shown when `queue.drain == paused && items.isNotEmpty`)
- l10n keys (exact names):
  - `sessionFollowUpQueued` → `"{count} Queued"` / `"{count} 排队中"`
  - `sessionFollowUpAddPlaceholder` → `"Add a follow-up"` / `"添加跟进消息"`
  - `sessionFollowUpResume` → `"Resume"` / `"继续队列"`
  - `sessionFollowUpEdit` / `sessionFollowUpMoveUp` / `sessionFollowUpDelete` tooltips

- [ ] **Step 1: Add ARB entries** (both locales), run codegen if the project uses `flutter gen-l10n` on build.

- [ ] **Step 2: Write strip widget tests**

```dart
testWidgets('shows count and resume when paused', (tester) async {
  var resumed = false;
  await tester.pumpWidget(
    // MaterialApp + l10n delegates + FollowUpQueueStrip(
    //   queue: FollowUpQueue(
    //     items: [FollowUpQueuedMessage(id: '1', content: 'hello')],
    //     drain: FollowUpDrainMode.paused,
    //   ),
    //   onResume: () => resumed = true,
    //   ...
    // )
  );
  expect(find.textContaining('Queued'), findsOneWidget);
  expect(find.text('hello'), findsOneWidget);
  await tester.tap(find.byTooltip('Resume')); // or zh in zh locale test
  expect(resumed, isTrue);
});
```

Use the same l10n test harness pattern as `history_mailbox_queued_strip_test.dart`.

- [ ] **Step 3: Implement strip** — collapsible header, row actions (Icons.edit / arrow_upward / delete_outline), inline edit field on edit tap (TextField + submit → `onEdit`).

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(follow-up): add shared Queued strip UI and l10n

EOF
)"
```

---

### Task 6: Wire History `SessionChatView`

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: any call sites of `shouldShowComposeStop` that need `composeTextEmpty`
- Create: `client/test/pages/chat/session_follow_up_queue_test.dart` (gate behavior with mocks if full view is heavy — prefer testing `_handleSubmit` path via extracted helper if needed)

**Behavior:**

1. Compute `composeTextEmpty = _controller.text.trim().isEmpty`.
2. `showComposeStop = shouldShowComposeStop(..., composeTextEmpty: composeTextEmpty)`.
3. On submit:
   - `action = resolveFollowUpSubmitAction(...)`
   - `enqueue` → `chat.followUpQueue.enqueue(followUpSeatKey(...), text); clear controller; return` (no `onSubmit` deliver)
   - `deliver` → existing `_handleSubmit` path
   - `stop` / `block` → no-op on submit (Stop uses `onStop`)
4. `onStop`: existing `interruptSelectedMemberTurn` **then** `chat.pauseFollowUpQueue(sessionId, memberId)`.
5. Mount `FollowUpQueueStrip` above `HistoryMailboxQueuedStrip`, bound to `chat.followUpQueue.watch(seat)` (or `Bloc`/stream builder).
6. Placeholder: when `memberWorking`, use `l10n.sessionFollowUpAddPlaceholder`.
7. Ensure working changes notify cubit drainer (if cubit already observes globally, UI only enqueues; else call `notifyFollowUpMemberWorking` from existing working listener).

**Seat key:** use the same shell member id History continue uses (`shellMemberId` from workbench — pass into view or derive consistently). Simple mode: session id as member key if that matches cubit `isMemberWorking`.

- [ ] **Step 1: Failing widget/unit test for enqueue-not-deliver when working**

- [ ] **Step 2: Implement wiring**

- [ ] **Step 3: Run**  
  `flutter test test/pages/chat/compose_stop_visibility_test.dart test/pages/chat/session_follow_up_queue_test.dart test/pages/chat/session_review_compose_stop_test.dart`  
  Fix Stop tests that assumed Stop while text non-empty.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(follow-up): queue History compose submits while member working

EOF
)"
```

---

### Task 7: Terminal follow-up chrome

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart`
- Modify: `client/lib/pages/chat_workbench.dart` (pass callbacks / selected member working)
- Create: `client/test/pages/chat/terminal_follow_up_compose_test.dart` (widget-level if feasible)

**Why:** Terminal is raw PTY today — typing always hits the CLI. Add a **compact follow-up bar** (strip + single-line/multi-line field + Send/Stop) docked above the terminal bottom when `memberWorking || queue.items.isNotEmpty`. Idle + empty queue → bar hidden; user uses PTY as today.

**Behavior:** Same gate/store/drainer as History. Submit enqueue/deliver via cubit delivery entrypoint (not raw `session.input`). Stop → interrupt + pause. Do not emit `parkedUserSubmissions`.

- [ ] **Step 1: Failing test** — when working, submitting follow-up field enqueues into store shared with History seat key.

- [ ] **Step 2: Implement overlay/bar in `ChatWorkbenchRunningTerminal`** (or a small `TerminalFollowUpCompose` widget under `client/lib/widgets/follow_up/`).

- [ ] **Step 3: Tests PASS; manually note Parked overlay still only for mailbox**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(follow-up): add Terminal follow-up compose sharing History queue

EOF
)"
```

---

### Task 8: Verification sweep

- [ ] **Step 1: Run analyze + targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && \
flutter test \
  test/services/follow_up/ \
  test/widgets/follow_up/ \
  test/pages/chat/compose_stop_visibility_test.dart \
  test/pages/chat/session_review_compose_stop_test.dart \
  test/pages/chat/session_follow_up_queue_test.dart \
  test/pages/chat/history_mailbox_queued_strip_test.dart \
  test/widgets/parked_send_overlay_test.dart
```

Expected: no analyzer errors; all listed tests PASS.

- [ ] **Step 2: Fix any fallout (Stop tests, canSubmit when working+text)**

When working + non-empty text, `canSubmit` must be true so Send shows; when working + empty, Stop shows (`canSubmit` false is OK).

- [ ] **Step 3: Final commit if fixes needed**

```bash
git commit -m "$(cat <<'EOF'
test(follow-up): finish analyze and regression sweep

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Per-seat store | 1, 4 |
| Busy empty → Stop; busy text → enqueue | 2, 6, 7 |
| Full strip UI edit/move/delete | 5 |
| Drain one on idle when armed | 3, 4 |
| Stop pauses; Resume re-arms | 3, 5, 6, 7 |
| Shared History + Terminal | 4, 6, 7 |
| Separate from mailbox/Parked | 6, 7, 8 |
| clear on session close | 4 |
| Canonical delivery entrypoint | 3, 4 |

## Self-review notes

- No TBD placeholders left in tasks; Terminal compose bar is an explicit Task 7 (required because PTY cannot stage unsent text).
- Types: `FollowUpQueue` / `FollowUpDrainMode` / `followUpSeatKey` / `FollowUpSubmitAction` / `FollowUpQueueDrainer` used consistently.
- `shouldShowComposeStop` gains `composeTextEmpty` — Task 6 must update all call sites.
