# Launch error card retry parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Chat launch-error card Retry identical to failed-bubble Retry when a failed/sending outbound record exists (pending + History 启动中 via the deliver path).

**Architecture:** Add a small pure orchestrator that chooses "redeliver latest failed" vs "reconnect only". `SessionChatView` uses it for compose/card Retry. `ChatCubit.retrySessionLaunch` stops post-connect auto-redelivery so Chat has a single deliver path.

**Tech Stack:** Flutter/Dart, `FailedMessageStore`, `SessionChatView`, `ChatCubit`, `flutter_test`

**Spec:** `docs/superpowers/specs/2026-09-02-launch-error-card-retry-parity-design.md`

## Global Constraints

- Chat card Retry with a latest failed/sending record must call the bubble deliver path (`_deliverComposeMessage(retryRecord: …)`), not connect-then-redeliver.
- No failed record → still `retrySessionLaunch` (reconnect only).
- Terminal compact banner / placeholder restore stay reconnect-only.
- Do not reintroduce full-screen session-starting overlay in Chat view.
- Keep using `latestFailedMessageRecord` for "which record" (failed preferred, else sending).

## File map

| File | Role |
|------|------|
| `client/lib/pages/chat/launch_error_card_retry.dart` | Pure `runLaunchErrorCardRetry` orchestrator |
| `client/test/pages/chat/launch_error_card_retry_test.dart` | Unit tests for the orchestrator |
| `client/lib/pages/chat/session_chat_view.dart` | `_retryLaunchOrLatestFailed`; wire compose `onRetry` |
| `client/lib/cubits/chat_cubit.dart` | Remove post-connect `_redeliverLatestFailedAfterLaunchRetry` from `retrySessionLaunch` |
| `client/test/cubits/chat/retry_session_launch_test.dart` | Expect reconnect without operator redelivery |

---

### Task 1: Pure launch-error card retry orchestrator

**Files:**
- Create: `client/lib/pages/chat/launch_error_card_retry.dart`
- Test: `client/test/pages/chat/launch_error_card_retry_test.dart`

**Interfaces:**
- Consumes: `latestFailedMessageRecord`, `FailedMessageRecord`
- Produces:

```dart
Future<void> runLaunchErrorCardRetry({
  required Future<List<FailedMessageRecord>> Function() loadRecords,
  required Future<void> Function(FailedMessageRecord record) retryFailed,
  required void Function() reconnectOnly,
});
```

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/pages/chat/launch_error_card_retry.dart';

void main() {
  test('no records → reconnectOnly', () async {
    var reconnect = 0;
    var retries = 0;
    await runLaunchErrorCardRetry(
      loadRecords: () async => const [],
      retryFailed: (_) async {
        retries++;
      },
      reconnectOnly: () => reconnect++,
    );
    expect(reconnect, 1);
    expect(retries, 0);
  });

  test('latest failed → retryFailed with that record', () async {
    FailedMessageRecord? seen;
    await runLaunchErrorCardRetry(
      loadRecords: () async => [
        FailedMessageRecord(
          id: 'pending:old',
          text: 'older',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.failed,
        ),
        FailedMessageRecord(
          id: 'pending:new',
          text: 'newer',
          createdAt: DateTime.utc(2026, 1, 2),
          status: FailedMessageStatus.failed,
        ),
      ],
      retryFailed: (r) async => seen = r,
      reconnectOnly: () {},
    );
    expect(seen?.id, 'pending:new');
  });

  test('sending fallback when no failed → retryFailed', () async {
    FailedMessageRecord? seen;
    await runLaunchErrorCardRetry(
      loadRecords: () async => [
        FailedMessageRecord(
          id: 'pending:send',
          text: 'inflight',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.sending,
        ),
      ],
      retryFailed: (r) async => seen = r,
      reconnectOnly: () {},
    );
    expect(seen?.id, 'pending:send');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart test test/pages/chat/launch_error_card_retry_test.dart`

Expected: FAIL — library / `runLaunchErrorCardRetry` not found

- [ ] **Step 3: Implement orchestrator**

```dart
import '../../cubits/chat/latest_failed_message.dart';
import '../../models/failed_message_record.dart';

/// Chat launch-error card Retry: redeliver latest failed/sending via the
/// bubble path, or reconnect-only when nothing to redeliver.
Future<void> runLaunchErrorCardRetry({
  required Future<List<FailedMessageRecord>> Function() loadRecords,
  required Future<void> Function(FailedMessageRecord record) retryFailed,
  required void Function() reconnectOnly,
}) async {
  final latest = latestFailedMessageRecord(await loadRecords());
  if (latest == null) {
    reconnectOnly();
    return;
  }
  await retryFailed(latest);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart test test/pages/chat/launch_error_card_retry_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/launch_error_card_retry.dart \
  client/test/pages/chat/launch_error_card_retry_test.dart
git commit -m "$(cat <<'EOF'
Add launch-error card retry orchestrator for bubble parity.

EOF
)"
```

---

### Task 2: Wire SessionChatView compose/card Retry

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Optional: `client/test/pages/chat/session_chat_view_launch_error_retry_test.dart` if a thin harness is practical; otherwise Task 1 + Task 3 cover logic.

**Interfaces:**
- Consumes: `runLaunchErrorCardRetry`, `_failedMessageStore`, `_deliverComposeMessage`, `_retryingFailedMessageIds`, `_isSubmitting`, `widget.onRetry`
- Produces: `_retryLaunchOrLatestFailed()` used as compose `onRetry`

- [ ] **Step 1: Add `_retryLaunchOrLatestFailed` on `_SessionChatViewState`**

Place near `_retryFailedMessage`:

```dart
Future<void> _retryLaunchOrLatestFailed() async {
  await runLaunchErrorCardRetry(
    loadRecords: () => _failedMessageStore.load(
      widget.session.workspaceId,
      widget.session.sessionId,
    ),
    retryFailed: (record) async {
      if (_isSubmitting || !_retryingFailedMessageIds.add(record.id)) {
        return;
      }
      try {
        if (!mounted) return;
        await _deliverComposeMessage(
          record.text,
          retryRecord: record,
          clearCompose: false,
        );
      } finally {
        _retryingFailedMessageIds.remove(record.id);
      }
    },
    reconnectOnly: () => widget.onRetry?.call(),
  );
}
```

Import `launch_error_card_retry.dart`.

- [ ] **Step 2: Wire compose section**

In compose construction, change:

```dart
onRetry: widget.onRetry,
```

to:

```dart
onRetry: () => unawaited(_retryLaunchOrLatestFailed()),
```

Do **not** change message-area `onRetry` (that reloads history).

Leave `chat_workbench`'s `SessionChatView(onRetry: … retrySessionLaunch …)` as the reconnect-only fallback callback.

Terminal compact `SessionLaunchErrorBanner.onRetry` in `chat_workbench.dart` stays `retrySessionLaunch` (no History bubble).

- [ ] **Step 3: Optional smoke test**

If adding a widget test is cheap with existing harness patterns, assert that compose launch-error Retry invokes deliver when a failed record exists and invokes `onRetry` when store is empty. Otherwise skip and rely on Task 1 + manual Chat check in Task 4.

- [ ] **Step 4: Analyze / targeted tests**

Run: `cd client && dart test test/pages/chat/launch_error_card_retry_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart
# plus optional test file if created
git commit -m "$(cat <<'EOF'
Route Chat launch-error Retry through bubble deliver path.

EOF
)"
```

---

### Task 3: Remove post-connect redelivery from `retrySessionLaunch`

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (`retrySessionLaunch`, delete `_redeliverLatestFailedAfterLaunchRetry` and `_resolveRedeliveryMemberId` if unused)
- Modify: `client/test/cubits/chat/retry_session_launch_test.dart`

**Interfaces:**
- Consumes: `beginSessionConnect`, `connectWorkspaceSession`, `awaitSessionConnectSettle`
- Produces: `retrySessionLaunch` reconnects only (no `submitSessionOperatorMessage` / seat retry)

- [ ] **Step 1: Rewrite redelivery expectations**

Change the test currently named like:

`retrySessionLaunch redelivers the latest failed message after connect succeeds`

to:

```dart
test(
  'retrySessionLaunch reconnects without redelivering failed messages',
  () async {
    // same setup with two failed records …
    await cubit.retrySessionLaunch(session.sessionId);

    expect(cubit.connects, hasLength(1));
    expect(cubit.operatorMessages, isEmpty);

    final remaining = await store.load(
      session.workspaceId,
      session.sessionId,
    );
    expect(remaining.map((r) => r.id).toSet(), {
      'pending:old',
      'pending:new',
    });
  },
);
```

Remove or rewrite tests that only cover `_redeliverLatestFailedAfterLaunchRetry` / transcript-confirm-on-redelivery when that helper is deleted. Keep `does not redeliver when connect still fails` (connects once, no operator messages).

- [ ] **Step 2: Run tests expecting mismatch until cubit is updated**

Run: `cd client && dart test test/cubits/chat/retry_session_launch_test.dart`

- [ ] **Step 3: Slim `retrySessionLaunch`**

After settle, do **not** call `_redeliverLatestFailedAfterLaunchRetry`. End after settle / still-failed logging as needed:

```dart
Future<void> retrySessionLaunch(String sessionId) async {
  // … existing resolve session/team/request …
  beginSessionConnect(id);
  await connectWorkspaceSession(request);
  if (isClosed) return;
  await awaitSessionConnectSettle(
    isConnecting: () => isSessionConnecting(id),
    isClosed: () => isClosed,
  );
  // No post-connect message redelivery — Chat card Retry uses bubble path.
}
```

Delete `_redeliverLatestFailedAfterLaunchRetry` and `_resolveRedeliveryMemberId` if nothing else references them. Grep before delete:

`rg "_redeliverLatestFailedAfterLaunchRetry|_resolveRedeliveryMemberId" client/`

- [ ] **Step 4: Run tests**

Run: `cd client && dart test test/cubits/chat/retry_session_launch_test.dart test/pages/chat/launch_error_card_retry_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/test/cubits/chat/retry_session_launch_test.dart
git commit -m "$(cat <<'EOF'
Stop launch Retry from auto-redelivering after reconnect.

EOF
)"
```

---

### Task 4: Verification

**Files:** none required beyond prior tasks

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new issues in touched files

- [ ] **Step 2: Run related tests**

Run:

```bash
cd client && dart test \
  test/pages/chat/launch_error_card_retry_test.dart \
  test/cubits/chat/retry_session_launch_test.dart \
  test/cubits/chat/latest_failed_message_test.dart \
  test/pages/chat/session_launch_error_banner_test.dart \
  test/pages/chat/session_launch_error_visibility_test.dart
```

Expected: all PASS

- [ ] **Step 3: Manual check (if app available)**

1. Force a session launch failure with a failed user bubble visible.
2. Tap compose launch-error card Retry → bubble goes pending; History shows 启动中.
3. Tap bubble Retry on another failure → same behavior as before.
4. Launch failure with **no** failed bubble → card Retry only reconnects.

- [ ] **Step 4: Final commit only if uncommitted verification fixes remain**

```bash
git status
```

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| Card Retry uses latest failed → bubble path | 1, 2 |
| No failed → `retrySessionLaunch` | 1, 2 |
| Remove Chat connect-then-redeliver | 3 |
| Terminal stays reconnect-only | 2 (no Terminal wiring change) |
| History 启动中 via awaiting/deliver | 2 (`_deliverComposeMessage`) |
| Tests for with/without failed bubble | 1, 3, 4 |

## Self-review

- No TBD/placeholder steps.
- Orchestrator signatures match SessionChatView wiring.
- Cubit redelivery removal matches rewritten tests.
- `latestFailedMessageRecord` sending fallback preserved for interrupted sends.
