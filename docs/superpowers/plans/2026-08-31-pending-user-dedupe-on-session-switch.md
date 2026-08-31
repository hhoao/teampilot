# Pending user bubble dedupe on session switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop duplicate user bubbles after session switch by confirming optimistic pendings against the transcript (hydrate + tip reconcile + conditional cold→hot softReload).

**Architecture:** Keep tip/id reconcile for in-session softReload. Add a pure hydrate confirm helper (time or normalized text). On fullIndex/loadOlder, drop pendings only when the **tip** changes (prepends must not clear). Gate `skipInitialRefresh` with `hasOptimisticPending || awaitingAssistant`.

**Tech Stack:** Flutter/Dart, `AiHistorySeat`, `FailedMessageStore`, `flutter_test`

**Spec:** `docs/superpowers/specs/2026-08-31-pending-user-dedupe-on-session-switch-design.md`

## Global Constraints

- Silent success when transcript confirms: remove disk record, no overlay.
- Do not text-match for in-session softReload (slash rewrite).
- Idle session switches must keep `skipInitialRefresh: true` when no pending/awaiting.
- loadOlder prepends with unchanged tip must not drop pendings.

## File map

| File | Role |
|------|------|
| `client/lib/services/session/ai_history_pending_confirm.dart` | Pure `transcriptConfirmsPendingRecord` |
| `client/lib/services/session/history_seat_key.dart` | `shouldSkipLiveRefreshInitialSoftReload` |
| `client/lib/cubits/ai_history_seat.dart` | Hydrate confirm-or-restore; tip-sync on fullIndex/loadOlder |
| `client/lib/pages/chat/session_chat_view.dart` | Conditional skipInitialRefresh |
| Tests next to each unit | TDD |

---

### Task 1: Hydrate confirm helper

**Files:**
- Create: `client/lib/services/session/ai_history_pending_confirm.dart`
- Test: `client/test/services/session/ai_history_pending_confirm_test.dart`

**Interfaces:**
- Consumes: `FailedMessageRecord`, `AiMessage`, `normalizeAiHistoryPendingText`
- Produces: `bool transcriptConfirmsPendingRecord({required FailedMessageRecord record, required List<AiMessage> messages, Duration skew})`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/services/session/ai_history_pending_confirm.dart';

void main() {
  final record = FailedMessageRecord(
    id: 'pending:1',
    text: 'hello   world',
    createdAt: DateTime.utc(2026, 1, 1, 12),
    status: FailedMessageStatus.sending,
  );

  test('empty messages do not confirm', () {
    expect(
      transcriptConfirmsPendingRecord(record: record, messages: const []),
      isFalse,
    );
  });

  test('normalized text match confirms', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hello world')],
          ),
        ],
      ),
      isTrue,
    );
  });

  test('prior unmatched history does not confirm', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u0',
            role: AiRole.user,
            parts: [AiTextPart(text: 'older')],
          ),
        ],
      ),
      isFalse,
    );
  });

  test('user createdAt within skew of record confirms', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: '<command-name>/x</command-name>')],
            createdAt: DateTime.utc(2026, 1, 1, 12, 0, 1),
          ),
        ],
      ),
      isTrue,
    );
  });

  test('user createdAt before record minus skew does not confirm', () {
    expect(
      transcriptConfirmsPendingRecord(
        record: record,
        messages: [
          AiMessage(
            id: 'u0',
            role: AiRole.user,
            parts: [AiTextPart(text: 'older')],
            createdAt: DateTime.utc(2025, 12, 31),
          ),
        ],
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/session/ai_history_pending_confirm_test.dart`
Expected: FAIL (library missing)

- [ ] **Step 3: Implement helper**

```dart
import 'package:ai_message_core/ai_message_core.dart';

import '../../models/failed_message_record.dart';
import 'ai_history_pending_text.dart';

const Duration kPendingConfirmClockSkew = Duration(seconds: 2);

bool transcriptConfirmsPendingRecord({
  required FailedMessageRecord record,
  required List<AiMessage> messages,
  Duration skew = kPendingConfirmClockSkew,
}) {
  final target = normalizeAiHistoryPendingText(record.text);
  if (target.isEmpty) return false;
  final earliest = record.createdAt.subtract(skew);
  for (final message in messages) {
    if (message.role != AiRole.user) continue;
    if (message.id.startsWith('pending:')) continue;
    final created = message.createdAt;
    if (created != null && !created.isBefore(earliest)) return true;
    final text = normalizeAiHistoryPendingText(
      message.parts.whereType<AiTextPart>().map((p) => p.text).join(' '),
    );
    if (text.isNotEmpty && text == target) return true;
  }
  return false;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/session/ai_history_pending_confirm_test.dart`
Expected: PASS

- [ ] **Step 5: Commit** (only if user asked to commit; otherwise skip)

---

### Task 2: Hydrate confirm-or-restore in AiHistorySeat

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart` (`hydratePendingUsers`)
- Test: `client/test/cubits/ai_history_seat_no_blank_test.dart`
- Test: `client/test/pages/chat/session_chat_view_failed_message_test.dart` (update if assertions conflict)

**Interfaces:**
- Consumes: `transcriptConfirmsPendingRecord`
- Produces: hydrate removes confirmed records; unconfirmed `sending` → failed overlay (unchanged)

- [ ] **Step 1: Write failing seat tests**

Add to `ai_history_seat_no_blank_test.dart`:

```dart
test('hydrate drops sending when transcript text matches', () async {
  holderMessages = [
    AiMessage(
      id: 'u-match',
      role: AiRole.user,
      parts: [AiTextPart(text: 'same text')],
    ),
  ];
  final current = session();
  await seat.load(
    session: current,
    memberId: '',
    launchContext: ctx(current),
  );
  final store = FailedMessageStore(
    fs: InMemoryFilesystem(),
    rootPath: '/teampilot',
  );
  final record = FailedMessageRecord(
    id: 'pending:matched',
    text: 'same text',
    createdAt: DateTime.utc(2026),
    status: FailedMessageStatus.sending,
  );
  await store.save(current.workspaceId, current.sessionId, record);

  await seat.hydratePendingUsers(
    store: store,
    workspaceId: current.workspaceId,
    sessionId: current.sessionId,
  );

  expect(
    seat.runtime.messages.where((m) => m.id.startsWith('pending:')),
    isEmpty,
  );
  expect(await store.load(current.workspaceId, current.sessionId), isEmpty);
});

test('hydrate keeps unmatched sending on prior history as failed', () async {
  // Existing test body renamed/kept: unmatched 'survives restart' on msg-0
});
```

Keep existing `hydrates stale sending as failed without latching awaiting` — text unmatched so still expects overlay.

- [ ] **Step 2: Run tests — new one FAIL, old PASS**

Run: `cd client && flutter test test/cubits/ai_history_seat_no_blank_test.dart --name hydrate`
Expected: new test FAIL (still overlays matched sending)

- [ ] **Step 3: Implement hydrate branch**

In `hydratePendingUsers`, after loading records, for each record skip `sent` / already-queued as today. Before enqueue:

```dart
if (transcriptConfirmsPendingRecord(
  record: record,
  messages: _allMessages,
)) {
  await store.remove(workspaceId, sessionId, record.id);
  continue;
}
```

Then existing sending→failed / enqueue path.

- [ ] **Step 4: Run hydrate tests PASS**

Run: `cd client && flutter test test/cubits/ai_history_seat_no_blank_test.dart test/pages/chat/session_chat_view_failed_message_test.dart`

---

### Task 3: Tip-only snapshot sync on fullIndex / loadOlder

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart` (`_applyOlderPage`, `_hydrateFullIndex`, add `_syncAppliedSnapshotAfterStructuralEdit`)
- Test: `client/test/cubits/ai_history_seat_no_blank_test.dart`

**Interfaces:**
- Produces: `void _syncAppliedSnapshotAfterStructuralEdit()` — if tip content changed vs `_lastAppliedTipContent`, `_dropAllPendings(removePersisted: true)`; always update `_lastAppliedIds` / tip / `_appliedSnapshotSeen`

- [ ] **Step 1: Failing test — softReload already covers tip drop; add fullIndex-style tip growth via softReload after remember bug is fixed**

Practical seat test without incomplete loader: enqueue pending after load, grow transcript tip via softReload (already exists). Add:

```dart
test('pending survives loadOlder-style prepend identity when tip unchanged', () async {
  // Document via unit on tip-sync: after load+pending, calling structural
  // sync with same tip (manually widen ids only) is covered by implementation
  // using tip-only compare — verified by softReload tip-change still dropping.
});
```

Prefer one concrete test:

```dart
test('softReload tip growth still drops pending after structural snapshot helper', () async {
  holderMessages = messages(1);
  final current = session();
  await seat.load(session: current, memberId: '', launchContext: ctx(current));
  final store = FailedMessageStore(fs: InMemoryFilesystem(), rootPath: '/teampilot');
  await seat.persistPendingUser(
    store: store,
    workspaceId: current.workspaceId,
    sessionId: current.sessionId,
    text: 'in flight',
  );
  holderMessages = messages(2);
  bumpCacheToken();
  await seat.softReload();
  await Future<void>.delayed(Duration.zero);
  expect(
    seat.runtime.messages.where((m) => m.id.startsWith('pending:')),
    isEmpty,
  );
});
```

And change `_applyOlderPage` / `_hydrateFullIndex` to use tip-sync helper instead of bare `_rememberAppliedSnapshot`.

- [ ] **Step 2: Implement**

```dart
void _syncAppliedSnapshotAfterStructuralEdit() {
  final ids = [for (final message in _allMessages) message.id];
  final tipContent = _allMessages.isEmpty
      ? null
      : messageContentIdentity(_allMessages.last);
  if (_appliedSnapshotSeen && tipContent != _lastAppliedTipContent) {
    _dropAllPendings(removePersisted: true);
  }
  _appliedSnapshotSeen = true;
  _lastAppliedIds = ids;
  _lastAppliedTipContent = tipContent;
}
```

Replace `_rememberAppliedSnapshot()` calls in `_applyOlderPage` and `_hydrateFullIndex` with `_syncAppliedSnapshotAfterStructuralEdit()`. Keep `_rememberAppliedSnapshot` for callers that only refresh baseline without drop intent, or make it delegate carefully.

- [ ] **Step 3: Run seat tests PASS**

---

### Task 4: Conditional skipInitialRefresh

**Files:**
- Modify: `client/lib/services/session/history_seat_key.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart` (`_maybeStartLiveRefreshForRunningPty`)
- Test: `client/test/services/session/history_seat_key_test.dart`

**Interfaces:**
- Produces: `bool shouldSkipLiveRefreshInitialSoftReload({required bool hasOptimisticPending, required bool awaitingAssistant})`

- [ ] **Step 1: Failing tests**

```dart
group('shouldSkipLiveRefreshInitialSoftReload', () {
  test('skips when idle', () {
    expect(
      shouldSkipLiveRefreshInitialSoftReload(
        hasOptimisticPending: false,
        awaitingAssistant: false,
      ),
      isTrue,
    );
  });
  test('does not skip with optimistic pending', () {
    expect(
      shouldSkipLiveRefreshInitialSoftReload(
        hasOptimisticPending: true,
        awaitingAssistant: false,
      ),
      isFalse,
    );
  });
  test('does not skip while awaiting assistant', () {
    expect(
      shouldSkipLiveRefreshInitialSoftReload(
        hasOptimisticPending: false,
        awaitingAssistant: true,
      ),
      isFalse,
    );
  });
});
```

- [ ] **Step 2: Implement helper + wire SessionChatView**

```dart
bool shouldSkipLiveRefreshInitialSoftReload({
  required bool hasOptimisticPending,
  required bool awaitingAssistant,
}) =>
    !hasOptimisticPending && !awaitingAssistant;
```

In `_maybeStartLiveRefreshForRunningPty`:

```dart
final seat = _seat;
final skip = shouldSkipLiveRefreshInitialSoftReload(
  hasOptimisticPending: seat?.hasOptimisticPending ?? false,
  awaitingAssistant: seat?.state.awaitingAssistant ?? false,
);
unawaited(_startLiveRefresh(skipInitialRefresh: skip));
```

Leave paths that already pass an explicit `skipInitialRefresh` after `softReloadOrLoad` as-is when they intentionally skip a second reload — `_maybeStartLiveRefreshForRunningPty` is the cold→hot / busy-flip entry.

- [ ] **Step 3: Run**

`cd client && flutter test test/services/session/history_seat_key_test.dart`

---

### Task 5: Verification

- [ ] Run: `cd client && flutter test test/services/session/ai_history_pending_confirm_test.dart test/services/session/history_seat_key_test.dart test/cubits/ai_history_seat_no_blank_test.dart test/pages/chat/session_chat_view_failed_message_test.dart test/cubits/ai_history_cubit_test.dart --name 'pending|hydrate|command-expanded|softReload after idle'`
- [ ] Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] Manual smoke (optional): send → switch session → switch back → one user bubble

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| Hydrate confirm-or-restore (time/text) | 1–2 |
| Real failure kept on prior history | 2 |
| Conditional cold→hot softReload | 4 |
| fullIndex/loadOlder tip reconcile | 3 |
| Performance: idle skip | 4 |
| Slash softReload regression | 5 (existing cubit test) |
