# Conversation timeline + mailbox user mail: design

## Problem

Mixed TeamBus sessions deliver operator text to waiting / in-turn members via
mailbox (`from: user`), not CLI stdin. History today treats the chat thread as
**CLI transcript + in-memory sticky overlays**, with a separate Queued strip for
unread mail.

That split causes:

- Mailbox user turns never appear in the CLI transcript, so they cannot
  reconcile like PTY user bubbles.
- Sticky bubbles are session-memory only: seat change / reopen drops them even
  though `BusMessageLog` already persisted the mail.
- Queued / Parked / sticky each own a fragment of UX; adding more sources
  (tasks, collab, system) would require more one-off overlays.

Related prior art: [2026-07-21-history-mixed-mailbox-continue-design.md](./2026-07-21-history-mixed-mailbox-continue-design.md)
(routing + Queued → sticky). This spec **supersedes the sticky-as-truth model**
for mailbox user display while keeping PTY/mailbox **routing** unchanged.

## Goal

- Introduce a seat-scoped **ConversationTimeline** that merges pluggable
  **TimelineSource**s into one thread model.
- Ship two sources in v1: CLI transcript and mailbox `from: user` mail.
- UX:
  - Unread user mail → Queued (Chat) + ParkedSendOverlay (Terminal); **not** in
    the thread body.
  - After the member consumes (read) → user bubble in the thread, same style as
    transcript users, with a light ✉ / mailbox marker (`deliveryChannel`).
  - Rebuild from `BusMessageLog` on load / softReload / seat reopen so read
    mailbox users interleave with transcript by time.
- Keep History continue channel routing (PTY vs mailbox) as today.

## Non-goals

- Landing compose routing changes
- Projecting teammate / coordination / full inbox mail into the History thread
- Edit / reorder / retract delivered mail
- Replacing the right-tools Mailbox panel
- Changing when Chat uses mailbox vs PTY (`resolveHistoryContinueChannel`)
- Immediate thread bubbles on deliver (unread stays out of the body)

## Architecture

```
TimelineSource (cli transcript | mailbox user | future…)
        │
        ▼
ConversationTimeline.resolve(seat)
        │
        ├── messages[]     → AiHistory / thread runtime (merged AiMessage)
        └── unreadUserMails[] → Queued strip + ParkedSendOverlay
```

| Layer | Responsibility |
|-------|----------------|
| `TimelineSource` | Load seat-scoped events; signal changes |
| `ConversationTimeline` | Merge, dedupe, sort; split read body vs unread projection |
| `AiHistorySeat` | Consume timeline snapshots (not sticky-as-truth); keep PTY optimistic pending on the CLI path |
| UI | Thread renders `messages`; Queued/Parked subscribe to `unreadUserMails` |

### Module placement

| Location | Contents |
|----------|----------|
| `client/lib/services/conversation_timeline/` | `TimelineSource`, `TimelineEvent`, `ConversationTimeline`, `CliTranscriptSource`, `MailboxUserSource`, pure merge helpers |
| `packages/ai_message_core` | Optional `deliveryChannel` on `AiMessage` (`null` \| `mailbox` \| …) |
| `packages/ai_message_ui` | User bubble: same chrome + light mailbox marker when `deliveryChannel == mailbox` |
| Chat / Terminal hosts | Wire unread projection; drop sticky-promote-as-persistence |

## Data model (sketch)

```dart
abstract class TimelineSource {
  Stream<void> get changes;
  Future<List<TimelineEvent>> load(TimelineSeat seat);
}

class TimelineEvent {
  final String id;              // e.g. mailbox:{mailId}, transcript uuid
  final AiRole role;
  final DateTime? createdAt;
  final List<AiMessagePart> parts;
  final String source;          // cli | mailbox | …
  final String? deliveryChannel;
}

class TimelineSnapshot {
  final List<AiMessage> messages;
  final List<UnreadUserMail> unreadUserMails;
}
```

**MailboxUserSource**

- Input: `BusMessageLog.load(memberId)` (and/or live inbox unread for freshness).
- Filter: `message.from == TeamBus.userSenderId`.
- `read == true` → `TimelineEvent` with `id: mailbox:{mailId}`,
  `deliveryChannel: mailbox`, `createdAt` from log.
- `read == false` → `UnreadUserMail` only (Queued / Parked); **not** in
  `messages`.

**CliTranscriptSource**

- Wraps existing `AiHistoryLoader` / transcript parse path.
- User turns from PTY have no mailbox `deliveryChannel`.

**Merge**

- Sort by `createdAt` ascending; missing timestamps keep relative CLI order as a
  stable secondary key.
- Same `id` → last write wins (reload-safe).
- Map events → `AiMessage` (carry `deliveryChannel` for UI).

## Lifecycle

1. **Deliver** (Chat continue or Terminal parked) → `deliverUserCommand`;
   append to bus log. No thread body insert.
2. **Unread projection** → Queued + Parked until `isUnread` is false.
3. **Consume** → wait_for_message / read path marks log read.
4. **Timeline resolve** → mailbox event enters `messages`; UI shows user bubble
   with ✉.
5. **Soft reload / reopen seat** → sources reload; merge rebuilds; unread
   projection rebuilds from log/inbox. No dependency on sticky memory.

Manual dismiss of Queued / Parked hides the row only; mail stays unread. When
later consumed, the bubble still appears (dismiss must not suppress timeline
promotion).

Seat / session change switches `TimelineSeat` and re-resolves (clear prior
unread UI token as today).

## PTY path

Unchanged: idle-at-prompt continues via stdin; transcript owns those user turns.
Optimistic pending + awaitingAssistant remain CLI-side concerns.

## Errors

- Bus / log unavailable → timeline is CLI-only; unread empty; History still
  usable.
- Deliver failure → no unread row; compose restore as today.
- Partial source failure → merge what succeeded; surface soft error on History
  if CLI load fails (existing behavior).

## Migration

- Phase out sticky-as-truth (`appendStickyLocalUser` as persistence). Optional
  thin adapter during cutover that feeds timeline, then delete.
- Update matrix / chat assertions: expect timeline mailbox bubbles after
  consume, not only in-memory sticky appends.
- Prior Queued → sticky spec remains valid for **routing** and unread strip;
  display persistence moves to this timeline.

## Testing

- Pure merge: interleaved CLI + read mailbox; dedupe by id.
- Unread excluded from `messages`, present in unread projection.
- After consume, snapshot gains mailbox user bubble with `deliveryChannel`.
- Soft reload / seat reopen rebuilds from log.
- Chat Queued and Terminal Parked share the same unread projection.
- Integration matrix (mixed + wait_for_message): deliver → Queued → consume →
  thread bubble with marker.

## Success criteria

- Operator can follow a mixed seat as one conversation: PTY users and consumed
  mailbox users share one thread, ordered by time.
- Unread feedback remains obvious (Queued + Parked) without pretending the
  agent has already “seen” the line in the transcript.
- New timeline sources can be added without new sticky/overlay hacks in
  `AiHistorySeat`.
