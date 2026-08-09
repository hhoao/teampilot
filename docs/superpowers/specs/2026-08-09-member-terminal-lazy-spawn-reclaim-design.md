# Member Terminal Lazy Spawn & Idle Reclaim — Design

**Date:** 2026-08-09
**Status:** Proposed

## Problem

1. **Lazy spawn** — Opening or reconnecting a mixed/team session with
   `autoLaunchAllMembersOnConnect` (default `true`) spawns a PTY for **every**
   valid roster member at once. A 6-member team burns 6 CLI processes + embedded
   terminals on connect, most of which the user never touches. Startup is slow
   and memory-heavy.

2. **Idle reclaim** — Long-running sessions accumulate idle member terminals
   that hold process + memory forever. There is no automatic reclamation; the
   only escape is the manual Resource Manager kill, which additionally leaves
   the TeamBus lifecycle stale (member stays `running` while its PTY is dead, so
   later doorbell/stdin injects silently go nowhere and nothing re-materializes
   the member).

Both apply to Simple mode too: every open session tab holds a terminal that is
never released.

## Goals

1. **Lazy spawn**: on session open/reconnect, connect only the team lead (or the
   explicitly pinned member). All other members stay `declared` (no PTY) and
   spawn on demand when — and only when — they are needed.
2. **Idle reclaim** (Chrome-style discard): configurable idle threshold (default
   3 minutes) after which an idle member terminal is torn down and its bus state
   reset to `declared`, so a later bus message/task or user interaction
   transparently re-materializes it (`--resume`).
3. Apply reclaim to Simple mode as well; submitting restores the session.
4. **Integration coverage** — mixed lazy spawn → demand spawn → idle reclaim →
   re-materialize; and Simple-mode reclaim → submit restore. The reclaim
   threshold must be configurable at runtime so integration tests run in
   seconds, not minutes.

Non-goals (YAGNI): changing TeamBus message routing, mailbox-delivery, the
doorbell watchdog, `MemberTurnIdleSync`, or the work-queue claim model. The
existing 30-minute stale seats TTL stays as a backstop.

## Design decisions (author's call, reviewable)

| Decision | Choice | Why |
|----------|--------|-----|
| `autoLaunchAllMembersOnConnect` default | `false` | Lazy spawn is the point; existing toggle stays for power users. No backward-compat constraint. |
| What spawns a member lazily | Select member **and** show its terminal view; or a bus message/task targets it | Matches the requested trigger; bus path already exists. |
| Reclaim protection set | Team lead, the currently displayed member terminal, and any working / unread / connecting member are **never** reclaimed | Best UX + correctness. Mirrors Chrome "do not discard the tab you are looking at"; avoids the fiddly "reconnect on first keystroke into a dead PTY" path and per-message reconnect latency on the leader. Overrides earlier "reclaim even displayed/leader" notes. |
| What happens when a protected member eventually idles | It becomes reclaimable as soon as it leaves the protected set (turn ends, unread drains, view switches away) | No hard "never" flags; protection is dynamic. |
| Bus state on reclaim | New `PtyClosed` event: `running|materializing → declared`; inbox preserved | Materialize funnel then re-brings the member online with zero special-casing. |
| Reclaim vs. session in-flight work | Reclaim is synchronous teardown after guards pass; never races `membersPendingConnect` | No interleaving window for a lost message. |
| Reclaim applies to | Every member terminal, mixed and native teams; and every Simple-mode session terminal | Uniform resource policy. |
| Simple-mode restore | Submit from chat reconnects (existing history-review connect path); the displayed placeholder offers tap-to-restore | Reuses existing connect-on-submit seams. |

## Design

### 1. Preferences & config (`session_preferences.dart`, `session_config_section.dart`)

New fields on `SessionPreferences` (with `fromJson` / `copyWith` / `toJson`):

- `autoLaunchAllMembersOnConnect` — default flips to **`false`** (existing
  toggle, existing wiring unchanged).
- `reclaimIdleTerminals` — `bool`, default `true`. Master switch.
- `reclaimIdleTerminalAfterSeconds` — `int`, default `180` (3 min). Stored in
  seconds so integration tests can set a few seconds; the settings UI presents
  it as minutes.

Settings UI in the "terminal / session" section:
- switch "空闲回收终端" (`reclaimIdleTerminals`);
- minute stepper "回收阈值（分钟）" bound to `reclaimIdleTerminalAfterSeconds`
  (converted);
- existing "连接时启动全部成员" switch now defaults off.

### 2. Bus lifecycle: `PtyClosed` (`bus_event.dart`, `presence_reducer.dart`, `team_bus.dart`)

New event `class PtyClosed extends BusEvent {}`. Reducer case:

```
case PtyClosed():
  if (!s.ptyRunning) return _stay(s);
  return _to(s.copyWith(
    lifecycle: MemberLifecycle.declared,
    activity: ctx.hasUnread ? MemberActivity.mailQueued : MemberActivity.none,
  ));
```

- Inbox is **not** touched — a message that races in stays queued
  (`declared + mailQueued`) and materializes on next `send`.
- New `TeamBus.markMemberDiscarded(String memberId)` → `_apply(node,
  PtyClosed())`. No doorbell/effect produced.
- The transition is documented as a reducer case in `presence_reducer.dart`
  alongside the other lifecycle transitions.

### 3. Pure reclaim policy (`services/terminal/terminal_reclaim_policy.dart`)

A pure, unit-testable policy mirroring `PresenceReducer`'s style:

```dart
class TerminalReclaimSnapshot {
  final String sessionId;
  final String memberId;
  final bool shellRunning;      // PTY running
  final bool shellConnecting;   // or connect pending / membersPendingConnect
  final bool isTeamLead;
  final bool isDisplayed;       // workbenchView == SessionWorkbenchView.liveTerminal
                                // && selectedMemberId == memberId
  final bool inTurn;            // bus isMemberInTurn OR user turn active
  final bool hasUnread;         // bus unread / doorbell pending / delivery in-flight
}

class TerminalReclaimPolicy {
  const TerminalReclaimPolicy({required this.idleAfter});
  final Duration idleAfter;

  /// true when [idleSince] has been idle long enough and no guard applies.
  bool shouldReclaim(TerminalReclaimSnapshot s, DateTime? idleSince, DateTime now);
}
```

Rules inside `shouldReclaim` (single source of truth for the protection set):

1. not reclaimable if `shellConnecting`, `isTeamLead`, `isDisplayed`,
   `inTurn`, or `hasUnread`;
2. otherwise reclaimable iff `idleSince != null && now - idleSince >= idleAfter`.

The watch owns `idleSince` state: reset to `null` on any guard, seeded on first
unprotected tick. Pure policy = direct unit tests for every guard.

### 4. Reclaim watch (`cubits/chat/tab_member_reclaim_watch.dart`)

New collaborator beside `TabSessionIdleWatch`, sharing `ChatTabStore` and the
same `Timer.periodic(1s)` heartbeat lifecycle (starts when tabs open, stops when
none). Each tick, for every open tab and every member shell that `isRunning`:

1. build `TerminalReclaimSnapshot` from `tab.teamBus` presence / shell state /
   `selectedMemberId` + workbench view;
2. update `idleSince` per policy;
3. when `shouldReclaim` → `discardMemberTerminal(sessionId, memberId)`.

Simple mode: `teamBus == null` → presence fields fall back to shell activity
(`shell.activityTracker`/`userTurnActive`) and `isTeamLead=false`,
`isDisplayed = selectedMemberId == sessionId && workbenchView == terminal`.

### 5. Teardown & restore (`session_launch_service.dart`, `chat_tab.dart`)

`ChatTab` gains `final Set<String> reclaimedMemberIds = {}` — the UI marker for
"was running, now reclaimed" (distinct from never-launched `declared`).

`SessionLaunchService.discardMemberTerminal(String sessionId, String memberId)`
(sibling of `disconnectMemberShell`, **synchronous**):

1. re-run guards (defense in depth; the watch already checked);
2. mixed/native: `tab.teamBus?.markMemberDiscarded(memberId)` first — flips
   lifecycle to `declared` before the shell goes away, closing the
   send-into-dead-PTY window;
3. `tab.membersPendingConnect.remove(memberId)`; `shell.disconnect()`; remove
   from `tab.memberShells`; fire-and-forget `closeMemberRemotePlane(memberId)`;
   `clearAgentStatusSeat`; `clearLaunchError`; `updateTabRunning`;
4. `tab.reclaimedMemberIds.add(memberId)`.

Simple mode: same teardown on the session's shell (`memberShells[sessionId]` /
`resumeSession`), marked reclaimed.

`SessionLaunchService.ensureMemberTerminalForView(String sessionId, String
memberId)` — lazy spawn / restore entry:

- if the member's shell `isRunning || isConnecting`, or `membersPendingConnect`
  contains it → no-op;
- else `scheduleMemberConnect(team, member, tab)` (creates a fresh shell when
  one was removed, connects with `--resume`);
- clears `reclaimedMemberIds` on attach (hook into the connect success path,
  e.g. `SessionMemberConnectScheduler` after `ConnectShellResult.attached`, and
  in `markMemberRunning`).

Bus-driven restore needs **no** new code: `declared` member → existing
`send`/`addTasks` → `_bringOnline` → materializer → connect.

### 6. Lazy spawn triggers

- `ChatCubit.selectMember` + workbench terminal view → the workbench body calls
  `ensureMemberTerminalForView` whenever the effective displayed member changes
  while the view is the live terminal (covers select-then-view and
  view-then-select).
- Initial open: `autoLaunchAllMembersOnConnect=false` already connects only the
  resolved connect member (lead / pinned). Other members stay `declared`.
- Bus message/task: existing materialize funnel.

### 7. UI

- Terminal view placeholder for a non-running member:
  - `reclaimedMemberIds` contains member → "终端已回收 — 点击重新连接 / 提交即自动恢复";
  - otherwise (declared, never launched) → "终端未启动 — 点击启动".
  - Tap → `ensureMemberTerminalForView`. Compose submit to the member also
    restores (bus path for mixed; connect-on-submit for simple).
- Members panel: non-running members already surface presence as
  `declared`/offline; add a "已回收" label when the member is in
  `reclaimedMemberIds`.

## State transitions

```
Lazy spawn:
  declared ──select+terminal view / bus message / task──▶ materializing
  materializing ──PTY up──▶ running
  running ──turn ends, idle──▶ running (reclaimable once unprotected)

Reclaim:
  running|materializing ──PtyClosed (discardMemberTerminal)──▶ declared
  declared ──send/addTasks (existing funnel)──▶ materializing ──▶ running (--resume)

Restore on interaction:
  declared(reclaimed) ──ensureMemberTerminalForView──▶ materializing ──▶ running
```

`running → declared` keeps `MemberInbox` intact; `activity` recomputed by
`hasUnread`.

## Edge cases

- **Message races the reclaim**: reclaim is synchronous and flips bus state
  first; a message arriving after sees `declared` → materializes. A message
  already in the inbox stays queued (`declared + mailQueued`).
- **Leader never reclaimed**: leader is protected while the session is open, so
  compose-to-leader never pays reconnect latency.
- **Displayed terminal never reclaimed**: the exact terminal the user is looking
  at never disappears; background members are where the savings live.
- **SSH remote members**: reclaim closes SSH + bus mount + PTY via
  `closeMemberRemotePlane`; restore rebuilds the connection + resume. Heavier,
  but consistent — no special protection (works through the same funnel).
- **Task claims during reclaim**: `ptyRunning=false` →
  `reclaimExpiredTasks` treats the member as offline and returns leases —
  correct.
- **In-flight automation retry delivery**: guarded — pending delivery counts as
  `hasUnread`/busy and is never reclaimed.
- **Reclaim while connecting/pending**: `membersPendingConnect` / shell
  connecting → guard blocks.

## Testing

**Unit**
- `presence_reducer_test.dart`: `PtyClosed` legal (`running|materializing →
  declared`, activity via `hasUnread`) and illegal (`declared` stays) paths.
- `terminal_reclaim_policy_test.dart`: every guard (lead, displayed, in-turn,
  unread, connecting), threshold math, `idleSince` seeding.
- `tab_member_reclaim_watch_test.dart`: fake store/bus — idle counting, guard
  reset, firing discard.
- `session_launch_service_test.dart`: `discardMemberTerminal` teardown ordering
  (bus reset before shell teardown), `ensureMemberTerminalForView` no-op/restore.

**Integration** (`@Tags(['integration'])`, reclaim threshold seeded to a few
seconds via `SessionPreferences` so the test runs fast)

1. **mixed lazy spawn + demand spawn**: open a mixed session with lead + worker;
   assert worker PTY is **not** started; lead sends a message/task → worker PTY
   starts; worker idles → after threshold the worker PTY is reclaimed; lead
   sends again → worker PTY re-materializes (`--resume`), message delivered.
2. **mixed protected members**: while the worker is in-turn / has unread, the
   reclaim does not fire (extend beyond threshold and assert still running).
3. **simple mode reclaim + submit restore**: open a simple session, PTY up,
   idle past threshold → reclaimed (placeholder); submit from chat → reconnected
   and working.

## Risks

- Resuming after reclaim re-runs CLI startup (a few seconds) on first
  interaction — mitigated by protecting leader/displayed members so the hot
  surfaces are unaffected.
- Reclaim watch must not fight the doorbell watchdog / automation retries —
  guards reuse the same presence signals they consume.
- Behavior change for existing users (no all-members launch by default) is
  intentional and toggleable.
