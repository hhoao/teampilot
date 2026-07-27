# Conversation Timeline + Mailbox User Mail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge consumed `from:user` mailbox mail into the Chat History thread via a seat-scoped ConversationTimeline (pluggable sources), while unread mail stays in Queued / Parked only, with a light ✉ marker on mailbox user bubbles.

**Architecture:** Pure merge of `TimelineEvent`s from `CliTranscriptSource` (existing loader output) and `MailboxUserSource` (`BusMessageLog` / inbox `snapshotRecords`, `from:user` only). `AiHistorySeat` treats merged messages as `_allMessages`; PTY optimistic pending stays a tip overlay. Queued / Parked keep unread UX; consume triggers mailbox re-merge (not sticky persistence).

**Tech Stack:** Flutter / Dart, `ai_message_core`, `ai_message_ui`, TeamBus `BusMessageLog` / `MemberInbox`, existing `AiHistoryLoader` / `AiHistorySeat`.

**Spec:** `docs/superpowers/specs/2026-07-27-conversation-timeline-mailbox-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/ai_message_core/lib/src/message.dart` | Add optional `deliveryChannel` on `AiMessage` |
| `client/packages/ai_message_core/test/message_delivery_channel_test.dart` | Core field / copyWith tests |
| `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | ✉ marker on mailbox user bubbles |
| `client/packages/ai_message_ui/test/user_bubble_mailbox_marker_test.dart` | UI marker widget test |
| `client/lib/services/conversation_timeline/timeline_models.dart` | `TimelineSeat`, `TimelineEvent`, `UnreadUserMail`, `TimelineSnapshot` |
| `client/lib/services/conversation_timeline/timeline_merge.dart` | Pure merge / dedupe / sort → `AiMessage` + unread |
| `client/lib/services/conversation_timeline/mailbox_user_source.dart` | Partition log records → events + unread |
| `client/lib/services/conversation_timeline/conversation_timeline.dart` | Resolve helpers (CLI list + mailbox load → snapshot) |
| `client/test/services/conversation_timeline/timeline_merge_test.dart` | Merge unit tests |
| `client/test/services/conversation_timeline/mailbox_user_source_test.dart` | Source unit tests |
| `client/lib/services/team_bus/team_bus.dart` | Expose `memberMailRecords(memberId)` |
| `client/lib/cubits/ai_history_seat.dart` | Merge mailbox into `_allMessages`; retire sticky-as-truth |
| `client/lib/cubits/ai_history_cubit.dart` | Replace / thin `appendStickyLocalUser`; add mailbox refresh entry |
| `client/lib/pages/chat/session_chat_view.dart` | On Queued consume → timeline refresh (not sticky append) |
| `client/test/cubits/ai_history_cubit_test.dart` | Update sticky → mailbox merge expectations |
| `client/test/integration/support/chat_thread_assertions.dart` | Assert mailbox `deliveryChannel` / reopen persistence |
| `client/test/integration/support/cli_message_matrix_harness.dart` | Stop forcing sticky; rely on timeline after consume |

**Out of scope this plan:** Landing compose, teammate mail in thread, new timeline sources beyond CLI + mailbox user.

---

### Task 1: `AiMessage.deliveryChannel`

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/message.dart`
- Create: `client/packages/ai_message_core/test/message_delivery_channel_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  test('AiMessage carries deliveryChannel through copyWith', () {
    const msg = AiMessage(
      id: 'mailbox:m1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
      deliveryChannel: 'mailbox',
    );
    expect(msg.deliveryChannel, 'mailbox');
    expect(msg.copyWith(deliveryChannel: null).deliveryChannel, isNull);
    expect(
      msg.copyWith(clearDeliveryChannel: true).deliveryChannel,
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/ai_message_core && dart test test/message_delivery_channel_test.dart`

Expected: FAIL (undefined `deliveryChannel`)

- [ ] **Step 3: Minimal implementation**

Add to `AiMessage`:

```dart
final String? deliveryChannel; // null | 'mailbox' | future channels

// copyWith: deliveryChannel + clearDeliveryChannel bool
```

Keep `coalesceAdjacentAssistants` preserving the first message's `deliveryChannel` (assistants ignore it).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/ai_message_core && dart test test/message_delivery_channel_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_core/lib/src/message.dart \
  client/packages/ai_message_core/test/message_delivery_channel_test.dart
git commit -m "feat(ai_message_core): add optional deliveryChannel on AiMessage"
```

---

### Task 2: Mailbox marker on user bubble

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart` (`_UserBubble`)
- Create: `client/packages/ai_message_ui/test/user_bubble_mailbox_marker_test.dart`

- [ ] **Step 1: Write the failing widget test**

Pump an `AiMessageView` (or `_UserBubble` via public `AiMessageView`) with `deliveryChannel: 'mailbox'` and assert a finder for the mailbox icon / key (add `ValueKey('ai-user-bubble-mailbox-marker')` on the icon).

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client/packages/ai_message_ui && flutter test test/user_bubble_mailbox_marker_test.dart`

- [ ] **Step 3: Implement marker**

In `_UserBubble`, when `message.deliveryChannel == 'mailbox'`, place a small `Icons.mail_outline` (size ~12–14) beside the bubble text row, same foreground as user bubble text. No color theme fork.

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/ai_message_view.dart \
  client/packages/ai_message_ui/test/user_bubble_mailbox_marker_test.dart
git commit -m "feat(ai_message_ui): show light mailbox marker on user bubbles"
```

---

### Task 3: Timeline models + pure merge

**Files:**
- Create: `client/lib/services/conversation_timeline/timeline_models.dart`
- Create: `client/lib/services/conversation_timeline/timeline_merge.dart`
- Create: `client/test/services/conversation_timeline/timeline_merge_test.dart`

- [ ] **Step 1: Write failing merge tests**

Cover at least:

1. Interleave CLI user/assistant with mailbox user by `createdAt`.
2. Unread partition: unread mails appear only in `unreadUserMails`, not `messages`.
3. Same `id` last-wins dedupe.
4. Missing `createdAt` on CLI messages: preserve relative CLI order as secondary key (document the rule in a one-line comment on the merge function).

Sketch:

```dart
TimelineSnapshot mergeTimeline({
  required List<TimelineEvent> events,
  required List<UnreadUserMail> unread,
});
```

Where `events` are **already** body-eligible (read mailbox + all CLI). Unread passed through unchanged.

Alternative acceptable API: one function that accepts CLI events + mailbox `LoggedMessage`-like DTOs and partitions — prefer keeping partition in `MailboxUserSource` and merge pure over events only.

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/services/conversation_timeline/timeline_merge_test.dart`

- [ ] **Step 3: Implement models + merge**

`timeline_models.dart`:

```dart
class TimelineSeat {
  const TimelineSeat({required this.sessionId, required this.memberId});
  final String sessionId;
  final String memberId;
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.role,
    required this.parts,
    this.createdAt,
    required this.source,
    this.deliveryChannel,
    this.cliOrder = 0,
  });
  final String id;
  final AiRole role;
  final List<AiMessagePart> parts;
  final DateTime? createdAt;
  final String source; // 'cli' | 'mailbox'
  final String? deliveryChannel;
  final int cliOrder; // stable secondary key for CLI rows
}

class UnreadUserMail {
  const UnreadUserMail({required this.id, required this.content});
  final String id;
  final String content;
}

class TimelineSnapshot {
  const TimelineSnapshot({
    required this.messages,
    this.unreadUserMails = const [],
  });
  final List<AiMessage> messages;
  final List<UnreadUserMail> unreadUserMails;
}
```

Merge: sort by `(createdAt ?? epoch, cliOrder, id)`; map to `AiMessage` with `deliveryChannel`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/conversation_timeline/timeline_models.dart \
  client/lib/services/conversation_timeline/timeline_merge.dart \
  client/test/services/conversation_timeline/timeline_merge_test.dart
git commit -m "feat(timeline): add models and pure conversation merge"
```

---

### Task 4: `MailboxUserSource` + TeamBus snapshot API

**Files:**
- Modify: `client/lib/services/team_bus/team_bus.dart` — add `memberMailRecords`
- Create: `client/lib/services/conversation_timeline/mailbox_user_source.dart`
- Create: `client/test/services/conversation_timeline/mailbox_user_source_test.dart`
- Modify if needed: `client/test/services/team_bus/team_bus_user_command_test.dart`

- [ ] **Step 1: Write failing source tests**

Use `InMemoryBusMessageLog` + small `TeamBus` (existing test helpers) or feed `List<LoggedMessage>` directly into a pure partition function:

```dart
({List<TimelineEvent> events, List<UnreadUserMail> unread})
  partitionMailboxUserRecords(List<LoggedMessage> records);
```

Assert: only `from == TeamBus.userSenderId`; read → event `id: mailbox:{id}`, `deliveryChannel: 'mailbox'`, `createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAt)` (log stores int ms); unread → `UnreadUserMail`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

1. `TeamBus.memberMailRecords(String memberId)` → `inbox.snapshotRecords()` (empty if unknown member). This keeps log as truth via inbox’s log-backed snapshot (spec: no second unread truth source).
2. `MailboxUserSource` / `partitionMailboxUserRecords` as above.
3. Optional thin class:

```dart
class MailboxUserSource {
  MailboxUserSource({required this.loadRecords});
  final Future<List<LoggedMessage>> Function(String memberId) loadRecords;
  Future<({List<TimelineEvent> events, List<UnreadUserMail> unread})>
      load(TimelineSeat seat) async { ... }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/team_bus.dart \
  client/lib/services/conversation_timeline/mailbox_user_source.dart \
  client/test/services/conversation_timeline/mailbox_user_source_test.dart
git commit -m "feat(timeline): mailbox user source from bus mail records"
```

---

### Task 5: `ConversationTimeline` resolve helper + seat merge on load

**Files:**
- Create: `client/lib/services/conversation_timeline/conversation_timeline.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/lib/cubits/ai_history_cubit.dart` (constructor / DI for mailbox loader)
- Modify: `client/lib/app/app_shell.dart` (wire bus → seat mailbox loader)
- Test: `client/test/cubits/ai_history_cubit_test.dart` (extend)

- [ ] **Step 1: Write failing cubit/seat test**

Simulate: CLI returns one user + one assistant; mailbox loader returns one **read** `from:user` with timestamp between them. After `load`, runtime messages order is user → mailbox user → assistant, and mailbox message has `deliveryChannel: 'mailbox'`.

Also: unread mail in loader partition does **not** appear in runtime messages.

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/cubits/ai_history_cubit_test.dart --name mailbox`

- [ ] **Step 3: Implement resolve + seat wiring**

```dart
// conversation_timeline.dart
TimelineSnapshot buildConversationTimeline({
  required List<AiMessage> cliMessages,
  required List<LoggedMessage> mailboxRecords,
}) {
  final cliEvents = <TimelineEvent>[
    for (var i = 0; i < cliMessages.length; i++)
      TimelineEvent(
        id: cliMessages[i].id,
        role: cliMessages[i].role,
        parts: cliMessages[i].parts,
        createdAt: cliMessages[i].createdAt,
        source: 'cli',
        cliOrder: i,
      ),
  ];
  final part = partitionMailboxUserRecords(mailboxRecords);
  return mergeTimeline(events: [...cliEvents, ...part.events], unread: part.unread);
}
```

In `AiHistorySeat`:

- Inject `Future<List<LoggedMessage>> Function(String sessionId, String memberId)? loadMailboxRecords`.
  Wire in `app_shell` like other bus UI: resolve via
  `chatCubit.sessionRuntime.busForSession(sessionId)?.memberMailRecords(memberId)`;
  personal / no-bus sessions return `const []`.
- After successful `_loader.load`, call `buildConversationTimeline` and set `_allMessages` from `snapshot.messages` (keep tip-hold / visible window / pending overlay as today).
- **Mailbox load failures:** try/catch around `loadMailboxRecords`; on failure log + merge with empty mailbox records (CLI-only). Never fail the whole History load because the bus log is unavailable.
- Soft reload: same merge after CLI soft load (still skip empty-parse wipe rule for CLI-only emptiness — if CLI empty but mailbox read messages exist, prefer showing mailbox-only thread: adjust the early `messages.isEmpty && _allMessages.isNotEmpty` guard so mailbox-only seats can still apply when CLI is empty **and** mailbox has read users; document in code comment). After Task 6 introduces `_cliMessages`, this guard must key off `_cliMessages.isNotEmpty`, not merged `_allMessages`.
- Cache last `unreadUserMails` on seat if useful for hosts (optional); Queued can keep its stream for in-session deliver.

Remove use of `_stickyLocalUsers` as persistence path in load/softReload (Task 6 finishes deletion).

- [ ] **Step 4: Run targeted cubit tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/conversation_timeline/conversation_timeline.dart \
  client/lib/cubits/ai_history_seat.dart \
  client/lib/cubits/ai_history_cubit.dart \
  client/lib/app/app_shell.dart \
  client/test/cubits/ai_history_cubit_test.dart
git commit -m "feat(history): merge read mailbox users into seat timeline"
```

---

### Task 6: Consume path — refresh timeline instead of sticky

**Files:**
- Modify: `client/lib/cubits/ai_history_cubit.dart` / `ai_history_seat.dart` — add `refreshMailboxTimeline()` that reloads mailbox records + remerges with last CLI `_allMessages` **CLI-only slice** OR re-softReloads CLI then merges (prefer: keep last CLI messages separately if needed).

**Preferred approach to avoid double-counting:**

- Store `_cliMessages` separately from `_allMessages`.
- `_allMessages = buildConversationTimeline(cli: _cliMessages, mailbox: ...).messages`.
- Sticky list deleted; `appendStickyLocalUser` becomes `refreshMailboxTimeline()` or deprecated wrapper that only refreshes mailbox merge (for one release).

- Modify: `client/lib/pages/chat/session_chat_view.dart` — `HistoryMailboxQueuedStrip.onConsumed` calls cubit/seat mailbox refresh instead of `appendStickyLocalUser`.
- Keep Queued strip + dismiss behavior (dismiss must not block later bubble).
- Modify tests that call `appendStickyLocalUser`.

- [ ] **Step 1: Failing test — after refresh with newly read mail, bubble appears with mailbox id**

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement `_cliMessages` + `refreshMailboxTimeline` + wire Chat onConsumed**

- Keep `_cliMessages` as the last successful CLI parse; `_allMessages` is always the merged timeline output.
- Update soft-reload empty-CLI guard to use `_cliMessages` (see Task 5).
- `refreshMailboxTimeline`: reload mailbox records (try/catch → empty on failure), remerge with `_cliMessages`, re-emit window + pending overlay.
- Ensure Terminal Parked path unchanged (still overlay); when operator later opens Chat on same seat, load/softReload shows consumed mail from log.

- [ ] **Step 4: Run cubit + `history_mailbox_queued_strip` / session chat tests**

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/ai_history_seat.dart \
  client/lib/cubits/ai_history_cubit.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/test/cubits/ai_history_cubit_test.dart \
  client/test/pages/chat/
git commit -m "feat(chat): promote consumed mailbox mail via timeline refresh"
```

---

### Task 7: Remove sticky-as-truth leftovers

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart` — delete `_StickyLocalUser` / `_stickyLocalUsers` / `appendStickyLocalUser` body
- Modify: `client/lib/cubits/ai_history_cubit.dart` — remove or redirect public API
- Update: all tests / harness still calling `appendStickyLocalUser`

- [ ] **Step 1: Grep for `appendStickyLocalUser` / `_stickyLocalUsers` and convert call sites**

- [ ] **Step 2: Delete sticky types; keep pending overlay only**

- [ ] **Step 3: `cd client && flutter test test/cubits/ai_history_cubit_test.dart test/pages/chat/`**

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(history): remove sticky mailbox persistence"
```

---

### Task 8: Integration assertions + matrix harness

**Files:**
- Modify: `client/test/integration/support/chat_thread_assertions.dart`
- Modify: `client/test/integration/support/cli_message_matrix_harness.dart`
- Modify: `client/test/integration/support/chat_thread_assertions_test.dart` if needed

- [ ] **Step 1: Update `awaitMailboxUserBubble` / helpers**

Expect message id `mailbox:$mailId` **and** `deliveryChannel == 'mailbox'` after consume, without harness manually calling `appendStickyLocalUser`.

- [ ] **Step 2: Add unit-level seat reopen assertion** (can be cubit test if L2 expensive): load seat → consume/read mail in log → `clearPendings` / new seat load same ids → mailbox bubble still present.

- [ ] **Step 3: Run**

`cd client && flutter test test/integration/support/chat_thread_assertions_test.dart`

If a mixed L2 cell is cheap locally: run the relevant `cli_message_matrix_*` mailbox cell.

- [ ] **Step 4: Commit**

```bash
git commit -m "test: assert timeline mailbox bubbles after consume and reopen"
```

---

### Task 9: Analyze + docs touch

**Files:**
- Optionally note supersession in `docs/superpowers/specs/2026-07-21-history-mixed-mailbox-continue-design.md` (one-line pointer to 2026-07-27) — only if already implied; skip if noisy.
- Run analyze on touched packages.

- [ ] **Step 1: Run**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/conversation_timeline lib/cubits/ai_history_seat.dart \
  lib/cubits/ai_history_cubit.dart lib/pages/chat/session_chat_view.dart \
  packages/ai_message_core packages/ai_message_ui
```

Expected: no new errors in touched paths

- [ ] **Step 2: Run unit suite slice**

```bash
cd client && flutter test \
  test/services/conversation_timeline/ \
  test/cubits/ai_history_cubit_test.dart \
  test/pages/chat/history_mailbox_queued_strip_test.dart \
  test/pages/chat/history_continue_delivery_test.dart
```

- [ ] **Step 3: Commit only if doc pointer added; otherwise done**

---

## Standing rules

1. TDD each task: fail → implement → pass → commit.
2. Do not change `resolveHistoryContinueChannel` behavior.
3. Unread must never enter `_allMessages`.
4. `BusMessageLog` / `snapshotRecords` is the only read/unread truth for mailbox source.
5. No teammate mail in thread.
6. Prefer small files under `conversation_timeline/`; no new `helpers`/`utils` dumping ground.

---

## Execution note

After plan approval, implement with @superpowers:subagent-driven-development (recommended) or @superpowers:executing-plans.
