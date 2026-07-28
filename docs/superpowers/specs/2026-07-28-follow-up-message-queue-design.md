# Follow-up message queue (Cursor-style)

## Goal

When the **selected member** is mid-turn (`working`), let the user queue follow-up messages from **History compose** and **Terminal** instead of injecting immediately. Queued items are editable / reorderable / deletable. When the member becomes idle and drain is **armed**, send the head of the queue one at a time through the same delivery path as a normal Send.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Surfaces | History compose **and** Terminal (shared queue) |
| Busy + empty input | Show **Stop** (existing turn interrupt) |
| Busy + non-empty input | Show **Send**; submit **enqueues** (does not deliver) |
| Queue UI | Collapsible **「N Queued」**; per-row edit / move-up / delete |
| Drain policy | On idle + armed: send **one** head item; if busy again, remainder waits |
| Stop + queue | Interrupt current turn **and** set drain to **paused**; keep items; **Resume** re-arms |
| Queue identity | Per seat: `sessionId` + `memberId` (Simple = sole seat) |
| History ↔ Terminal | **One store** per seat; both UIs bind the same queue |
| vs mailbox Queued / Parked | **Separate** — follow-up = not yet delivered; mailbox/Parked = delivered, awaiting consume |
| Persistence | In-memory for session lifetime; drop on session/tab dispose |
| Busy signal | Selected member `isMemberWorking` (same as Stop chrome) — not session-level `workingSessionIds` alone |

## Non-goals

- Disk persistence / restore queue across app restarts
- Changing TeamBus mailbox routing or `HistoryMailboxQueuedStrip` / `ParkedSendOverlay` consume semantics
- Parallel drain or “send entire queue while still busy”
- Auto-clear queue on Stop
- Attachments / images / slash chips as first-class queued payloads (v1 is plain text content; compose may still clear attachments with the field)
- Landing / Ask AI unbound compose (no live seat working signal)

## Problem

Today, submit while a member is working goes straight to PTY inject or mailbox deliver. Users cannot stage an ordered list of follow-ups the way Cursor does (“Add a follow-up” + 「N Queued」 with edit / reorder / delete). Existing 「N Queued」 UI is mailbox unread mail, not an unsent follow-up queue — reusing it would conflate “waiting for agent idle” with “waiting for member to read mail.”

## Design

### 1. `FollowUpQueueStore` (seat-scoped)

Own queue state outside route widgets so History and Terminal stay in sync.

```dart
typedef FollowUpSeatKey = String; // canonical "$sessionId:$memberId"

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
}

/// Held by ChatCubit (or a narrowly scoped collaborator it owns).
/// State only — does not call PTY/mailbox delivery.
abstract class FollowUpQueueStore {
  FollowUpQueue queueFor(FollowUpSeatKey seat);
  Stream<FollowUpQueue> watch(FollowUpSeatKey seat);

  void enqueue(FollowUpSeatKey seat, String content);
  void edit(FollowUpSeatKey seat, String id, String content);
  void moveUp(FollowUpSeatKey seat, String id);
  void remove(FollowUpSeatKey seat, String id);
  void pause(FollowUpSeatKey seat);   // Stop
  void resume(FollowUpSeatKey seat);  // Resume control
  void clearSeat(FollowUpSeatKey seat);
  void clearSession(String sessionId);
}
```

**Drain orchestration** lives next to ChatCubit (small helper or cubit methods), not inside the strip widgets: observe `isMemberWorking` edges for each seat that has items (or at least the selected seat plus any seat with a non-empty armed queue), call store + existing delivery APIs. UI only mutates the store and invokes Stop/Resume.

**Invariants**

- At most one in-flight drain delivery per seat (orchestrator flag).
- `edit` with empty trimmed content ≡ `remove`.
- `moveUp` on head ≡ no-op.
- `pause` / `resume` do not drop items.
- Closing a session clears all seats for that `sessionId`.

### 2. Submit gate (shared helper)

Used by History (`SessionChatView`) and Terminal compose/send:

```
if (permissionWaiting) → block (existing)
if (!memberWorking) → deliver via existing path
if (memberWorking && text.isEmpty) → Stop affordance only (no enqueue)
if (memberWorking && text.isNotEmpty) → enqueue; clear compose; no deliver
```

Placeholder while `memberWorking` (and optionally while queue non-empty): follow-up copy (l10n), e.g. “Add a follow-up”.

Compose action button (extends existing Stop/Send swap from turn-interrupt spec):

| `memberWorking` | trim(text) empty? | Action |
|-----------------|-------------------|--------|
| false | — | Send (deliver) |
| true | yes | Stop |
| true | no | Send (enqueue) |

### 3. Drain loop

Orchestrator triggers when a seat transitions `memberWorking: true → false`, or on `resume` if that seat is already idle:

1. If `drain != armed` or `items.isEmpty` or drain already in-flight for that seat → return.
2. Read head **without** removing yet.
3. Deliver via the **canonical seat delivery** API used by manual Send for that session seat (History continue and Terminal must share one delivery entrypoint so drain does not depend on which surface is mounted). Prefer extracting/reusing the existing continue/inject path rather than duplicating.
4. On **success**: remove that id from the queue. On **failure**: leave head in place; debug-log; do not tight-loop retry.
5. Do **not** chain-fire the next item in the same idle tick if delivery marks the member working again; wait for the next idle edge.

**Who drains when History and Terminal are both open:** the cubit-level orchestrator runs once per seat — not once per mounted strip.

Stop path:

1. Existing `interruptSelectedMemberTurn` (History / Terminal Stop).
2. `FollowUpQueueStore.pause(seat)`.

Resume path:

1. `FollowUpQueueStore.resume(seat)`.
2. If `!memberWorking`, attempt one drain immediately.

### 4. Shared UI: `FollowUpQueueStrip`

Cursor-like chrome above compose (History) and above/beside Terminal input:

- Collapsible header: `sessionFollowUpQueued(count)` — distinct l10n from mailbox `sessionHistoryMailboxQueued` even if English both say “Queued”.
- When `drain == paused` and `items.isNotEmpty`: header shows **Resume** (or play) control.
- Expanded rows: content preview; **edit**, **move up**, **delete**.
- Bind `watch(seat)` for the currently selected member; switching seats swaps visible queue without draining the hidden seat.

**Layout vs existing strips**

| Surface | Vertical order (top → bottom toward input) |
|---------|----------------------------------------------|
| History | Timeline → **FollowUpQueueStrip** → `HistoryMailboxQueuedStrip` → compose |
| Terminal | Engine → **FollowUpQueueStrip** (above input chrome) ; `ParkedSendOverlay` stays a separate overlay for delivered unread mail |

Mailbox / Parked semantics unchanged: unread delivered mail only.

### 5. Wiring

| Area | Change |
|------|--------|
| `ChatCubit` (or owned store) | Hold `FollowUpQueueStore`; clear on tab/session dispose; expose seat helpers |
| `compose_stop_visibility` / compose chrome | Extend gate: busy+text → Send(enqueue), not Stop |
| `session_chat_view.dart` | Gate submit; mount strip; Stop → pause; Resume → resume |
| Terminal workbench / input | Same gate + strip; shared store |
| l10n | Follow-up queued / placeholder / resume / edit strings (en + zh) |

Do **not** route follow-up items through `parkedUserSubmissions` or mailbox Queued streams.

## Error handling

| Case | Behavior |
|------|----------|
| Drain delivery fails | Restore head; keep remaining queue; no toast spam (debug log OK) |
| Busy again mid-queue | Wait for next idle; one-at-a-time |
| Switch selected member | Show that seat’s queue; do not auto-drain other seats from this UI |
| Session/tab closed | Drop queues for that session |
| Unsupported interrupt CLI | Keep turn-interrupt no-op policy; enqueue still works when working |
| Permission attention waiting | No submit / no enqueue (existing banner) |
| Dual History+Terminal open | Single store; edits visible on both |

## Testing

Prefer unit/widget tests without real PTY:

1. **Store**: enqueue / edit / moveUp / remove / pause / resume / clearSession pure state.
2. **Orchestrator**: idle+armed delivers one head then removes; busy stops further drain; pause blocks; resume+idle delivers; failure leaves head.
3. **Submit gate**: busy+empty → Stop path; busy+text → enqueue, delivery mock not called; idle+text → delivery called.
4. **Strip**: count header, edit, move-up, delete, Resume when paused.
5. **Isolation**: mailbox Queued / Parked paths do not create follow-up items; follow-up enqueue does not emit Parked overlay submissions.
6. **Shared seat**: History enqueue appears on Terminal strip for same seat.

Regression: existing turn-interrupt Stop tests; mailbox Queued strip tests.

## Success criteria

- § Locked decisions behavior on History and Terminal
- One seat queue shared across both surfaces
- Mailbox Queued / Parked / turn-interrupt unchanged in semantics
- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and targeted tests pass

## Out of scope follow-ups (explicit)

- Persist queue to workspace session JSON
- Queued rich attachments / multi-modal payloads
- Cross-seat “team queue” or broadcast follow-ups
- Renaming mailbox 「Queued」 copy globally (only add distinct follow-up keys unless collision forces a tweak)
