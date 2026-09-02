# Follow-up drain History send UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Follow-up queue items auto-drain, Chat shows the same channel-aware History send UX as manual continue (PTY pending bubble + refresh; mailbox Queued strip).

**Architecture:** Add a pure `runOperatorHistorySend` helper. Wire `_deliverFollowUpAtSeat` through it. Expose a cubit mailbox-queued stream for `SessionChatView` to feed the existing Queued strip. Keep bare `submitSessionOperatorMessage` unchanged.

**Tech Stack:** Flutter/Dart, `FailedMessageStore` / History seat APIs, `FollowUpQueueDrainer`, `flutter_test`

**Spec:** `docs/superpowers/specs/2026-09-03-follow-up-drain-history-ux-design.md`

## Global Constraints

- Follow-up drain must use the same channel-aware History send UX as manual History continue.
- Do **not** put optimistic UX inside bare `submitSessionOperatorMessage`.
- PTY: `persistHistoryPending` before deliver; fail → `markHistoryPendingFailed`; success → History soft-reload/stale so pending reconciles.
- Mailbox: no History pending; success → cubit mailbox-queued event → existing Queued strip + mailbox timeline refresh.
- No feature flags / dual paths / backward-compat shims.

## File map

| File | Role |
|------|------|
| `client/lib/pages/chat/operator_history_send.dart` | Pure `runOperatorHistorySend` + `OperatorMailboxQueuedEvent` |
| `client/test/pages/chat/operator_history_send_test.dart` | Unit tests for the helper |
| `client/lib/cubits/chat_cubit.dart` | Wire `_deliverFollowUpAtSeat`; mailbox-queued stream |
| `client/lib/pages/chat/session_chat_view.dart` | Subscribe to cubit mailbox-queued; feed `_mailboxQueued` |
| `client/test/cubits/chat/follow_up_deliver_history_ux_test.dart` | Cubit-level PTY pending / mailbox emit (focused) |

---

### Task 1: Pure `runOperatorHistorySend`

**Files:**
- Create: `client/lib/pages/chat/operator_history_send.dart`
- Test: `client/test/pages/chat/operator_history_send_test.dart`

**Interfaces:**
- Consumes: `HistoryContinueChannel`, `HistoryContinueSubmitResult`, `FailedMessageRecord`
- Produces:

```dart
final class OperatorMailboxQueuedEvent {
  const OperatorMailboxQueuedEvent({
    required this.sessionId,
    required this.memberId,
    required this.mailId,
    required this.text,
  });
  final String sessionId;
  final String memberId;
  final String mailId;
  final String text;
}

typedef OperatorHistorySendPorts = ({
  Future<HistoryContinueChannel> Function() resolveChannel,
  Future<FailedMessageRecord?> Function(String text) persistPending,
  Future<void> Function(FailedMessageRecord record) markFailed,
  Future<HistoryContinueSubmitResult> Function(String text) deliver,
  void Function() onPtyDelivered,
  void Function(OperatorMailboxQueuedEvent event) onMailboxQueued,
  Future<void> Function() refreshMailboxTimeline,
});

Future<HistoryContinueSubmitResult> runOperatorHistorySend({
  required String sessionId,
  required String memberId,
  required String text,
  required OperatorHistorySendPorts ports,
});
```

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/operator_history_send.dart';

void main() {
  test('PTY persists before deliver and notifies on success', () async {
    final calls = <String>[];
    FailedMessageRecord? persisted;
    final result = await runOperatorHistorySend(
      sessionId: 's1',
      memberId: 'm1',
      text: 'hello',
      ports: (
        resolveChannel: () async => HistoryContinueChannel.pty,
        persistPending: (t) async {
          calls.add('persist:$t');
          persisted = FailedMessageRecord(
            id: 'pending:1',
            text: t,
            createdAt: DateTime.utc(2026),
            status: FailedMessageStatus.sending,
          );
          return persisted;
        },
        markFailed: (_) async => calls.add('markFailed'),
        deliver: (t) async {
          calls.add('deliver:$t');
          return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          );
        },
        onPtyDelivered: () => calls.add('ptyDelivered'),
        onMailboxQueued: (_) => calls.add('mailboxQueued'),
        refreshMailboxTimeline: () async => calls.add('refreshMailbox'),
      ),
    );
    expect(result.ok, isTrue);
    expect(calls, ['persist:hello', 'deliver:hello', 'ptyDelivered']);
  });

  test('PTY failure marks pending failed', () async {
    final calls = <String>[];
    await runOperatorHistorySend(
      sessionId: 's1',
      memberId: 'm1',
      text: 'x',
      ports: (
        resolveChannel: () async => HistoryContinueChannel.pty,
        persistPending: (t) async => FailedMessageRecord(
          id: 'pending:1',
          text: t,
          createdAt: DateTime.utc(2026),
          status: FailedMessageStatus.sending,
        ),
        markFailed: (r) async => calls.add('markFailed:${r.id}'),
        deliver: (_) async => const HistoryContinueSubmitResult.failed(),
        onPtyDelivered: () => calls.add('ptyDelivered'),
        onMailboxQueued: (_) {},
        refreshMailboxTimeline: () async {},
      ),
    );
    expect(calls, ['markFailed:pending:1']);
  });

  test('mailbox success emits queued event and refreshes; no persist', () async {
    final calls = <String>[];
    OperatorMailboxQueuedEvent? queued;
    await runOperatorHistorySend(
      sessionId: 's1',
      memberId: 'm1',
      text: 'mail me',
      ports: (
        resolveChannel: () async => HistoryContinueChannel.mailbox,
        persistPending: (_) async {
          calls.add('persist');
          return null;
        },
        markFailed: (_) async => calls.add('markFailed'),
        deliver: (_) async => const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.mailbox,
          mailId: 'mail-9',
        ),
        onPtyDelivered: () => calls.add('ptyDelivered'),
        onMailboxQueued: (e) {
          queued = e;
          calls.add('mailboxQueued');
        },
        refreshMailboxTimeline: () async => calls.add('refreshMailbox'),
      ),
    );
    expect(calls, ['mailboxQueued', 'refreshMailbox']);
    expect(queued?.mailId, 'mail-9');
    expect(queued?.text, 'mail me');
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/pages/chat/operator_history_send_test.dart`

Expected: library / symbol missing

- [ ] **Step 3: Implement helper**

Implement `runOperatorHistorySend` per the Interfaces block and the channel table in the spec. Use a record typedef or a small ports class — match nearby style (`history_continue_delivery.dart`).

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/pages/chat/operator_history_send_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/operator_history_send.dart \
  client/test/pages/chat/operator_history_send_test.dart
git commit -m "$(cat <<'EOF'
Add operator History send UX helper for follow-up drain.

EOF
)"
```

---

### Task 2: Wire ChatCubit follow-up deliver

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat/follow_up_deliver_history_ux_test.dart`

**Interfaces:**
- Consumes: `runOperatorHistorySend`, `persistHistoryPending`, `markHistoryPendingFailed`, `submitSessionOperatorMessage`, `onSessionHistoryStale`, TeamBus channel resolve
- Produces:
  - `Stream<OperatorMailboxQueuedEvent> get operatorMailboxQueued`
  - `_deliverFollowUpAtSeat` runs through `runOperatorHistorySend`

- [ ] **Step 1: Add mailbox-queued broadcast + close on cubit dispose**

```dart
final _operatorMailboxQueued =
    StreamController<OperatorMailboxQueuedEvent>.broadcast();
Stream<OperatorMailboxQueuedEvent> get operatorMailboxQueued =>
    _operatorMailboxQueued.stream;
```

Close the controller in the existing `close()` path.

- [ ] **Step 2: Rewrite `_deliverFollowUpAtSeat`**

Resolve session + workspaceId from the tab’s `persistedSession`. Build ports:

- `resolveChannel`: same TeamBus logic as `submitSessionOperatorMessage`
- `persistPending`: `persistHistoryPending(workspaceId:, sessionId:, memberId:, text:)`
- `markFailed`: `markHistoryPendingFailed(...)`
- `deliver`: `() => submitSessionOperatorMessage(sessionId:, memberId:, message: text)`
- `onPtyDelivered`: `onSessionHistoryStale?.call(sessionId)`
- `onMailboxQueued`: `_operatorMailboxQueued.add`
- `refreshMailboxTimeline`: pod History seat `refreshMailboxTimeline()` when available

Use the shell member id consistently with `submitSessionOperatorMessage` (simple → sessionId; team → resolved connect member).

- [ ] **Step 3: Cubit test (focused)**

Prefer a small recording cubit / harness already used in chat tests. Assert:

1. After PTY follow-up deliver, History seat has an optimistic pending (or `persistHistoryPending` was invoked) and `onSessionHistoryStale` fired.
2. After mailbox success, `operatorMailboxQueued` emits once and no History pending was persisted.

If full ChatCubit harness is too heavy, test a package-visible wrapper around the ports wiring extracted next to `_deliverFollowUpAtSeat` — but prefer real `_deliverFollowUpAtSeat` if a light stub exists.

- [ ] **Step 4: Run tests**

```bash
cd client && flutter test \
  test/pages/chat/operator_history_send_test.dart \
  test/cubits/chat/follow_up_deliver_history_ux_test.dart \
  test/services/follow_up/follow_up_queue_drainer_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/test/cubits/chat/follow_up_deliver_history_ux_test.dart
git commit -m "$(cat <<'EOF'
Route follow-up drain through operator History send UX.

EOF
)"
```

---

### Task 3: SessionChatView subscribes to cubit mailbox-queued

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`

**Interfaces:**
- Consumes: `ChatCubit.operatorMailboxQueued`
- Produces: events for the active seat feed `_mailboxQueued` + `_mailboxQueuedSeats` (same as compose mailbox success)

- [ ] **Step 1: Subscribe in state lifecycle**

In `initState` / after first frame with context (follow existing Bloc/cubit listen patterns in this file):

```dart
_operatorMailboxSub = context.read<ChatCubit>().operatorMailboxQueued.listen((e) {
  if (!mounted) return;
  if (e.sessionId != widget.session.sessionId) return;
  if (e.memberId != _shellMemberId && e.memberId != widget.selectedMemberId) {
    // Accept shell member id used at drain time.
    if (e.memberId.trim().isEmpty) return;
    // Prefer matching _shellMemberId only.
    if (e.memberId != _shellMemberId) return;
  }
  _mailboxQueuedSeats[e.mailId] = _mailboxSeatKey();
  _mailboxQueued.add(PendingUserMessage(id: e.mailId, content: e.text));
});
```

Tighten the member filter to **exact `_shellMemberId` match** (simple sessions use sessionId as shell id). Cancel subscription in `dispose`.

- [ ] **Step 2: Keep compose path unchanged**

Manual mailbox success still adds to `_mailboxQueued` locally; cubit events are the drain path only (no double-add for compose).

- [ ] **Step 3: Smoke**

Run: `cd client && flutter test test/pages/chat/operator_history_send_test.dart test/services/follow_up/`

Optional widget test only if a cheap harness already listens to streams; otherwise skip.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart
git commit -m "$(cat <<'EOF'
Feed follow-up mailbox drains into History Queued strip.

EOF
)"
```

---

### Task 4: Verification

- [ ] **Step 1: Analyze**

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 2: Related tests**

```bash
cd client && flutter test \
  test/pages/chat/operator_history_send_test.dart \
  test/cubits/chat/follow_up_deliver_history_ux_test.dart \
  test/services/follow_up/follow_up_queue_drainer_test.dart \
  test/services/follow_up/follow_up_queue_store_test.dart \
  test/pages/chat/session_chat_view_failed_message_test.dart
```

- [ ] **Step 3: Manual (if app available)**

1. Start a turn; enqueue a follow-up while busy.
2. When the turn ends, History shows pending user bubble (PTY) then reconciles.
3. On a waiting mixed-team seat, drained follow-up appears on Queued strip.

- [ ] **Step 4: Commit only if verification fixes remain**

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| Pure Operator History Send UX | 1 |
| `_deliverFollowUpAtSeat` uses UX | 2 |
| PTY pending + stale/refresh | 2 |
| Mailbox queued event | 2, 3 |
| Queued strip shared with compose | 3 |
| No optimism in bare submitSessionOperatorMessage | 2 (unchanged) |
| Tests | 1, 2, 4 |

## Self-review

- No TBD placeholders.
- Ports signatures match cubit wiring.
- Compose path not double-optimism on shared submit.
