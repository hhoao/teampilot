# Silent wait for composer surface — Design

**Date:** 2026-08-20
**Status:** Approved

## Problem

Landing (and History continue) inject waits on
`ensureMemberInputReady(..., directToPty: true)` then paste+CR into the CLI
composer. That waiter already does the right thing:

1. PTY process is up
2. `TerminalActivityTracker.isBootFrameReady` — visible glyphs, fingerprint
   unchanged for 500ms
3. CLI `inputReadiness` needles (Cursor `→`, Codex `›` / `default ·`)

Cursor-agent can spend **minutes** in a black PTY while it scans plugin
skills (`CursorPluginsAgentSkillsService`), with `ptyObserved=false` and no
composer chrome. The outer landing helper nevertheless fails at a **fixed
120s** `TimeoutException`, cancels the optimistic Chat bubble, and shows an
error — even though the process is still alive and the composer appears
shortly after (observed: fail at ~118s, first paint at ~145s).

Black screen is not "still." The boot-frame tracker correctly refuses to
latch on silence or ANSI-only clear. The 120s wall clock is what drops the
first message.

## Goals

1. While the member PTY is still starting or silently booting, **keep waiting
   for the input box** (`inputReadiness` needles, or boot-frame-only CLIs
   after visible quiet). Do not fail at 120s.
2. Fail fast when the wait cannot succeed: tab gone, cubit closed, PTY
   launch failed, or process exited.
3. Keep a long safety cap so a wedged process cannot wait forever.
4. Do not paste into a black / splash / trust screen.

## Non-goals

- Do not treat "no PTY bytes for 500ms" as `isBootFrameReady`.
- Do not change cursor-agent plugin/skill loading, isolated HOME seeding, or
  `--model` / auth cache behavior.
- Do not pass the landing prompt as a cursor-agent argv / headless print
  prompt.
- Do not invent a second inject path. Reuse
  `ensureMemberInputReady` + `deliverUserCommandToMember(directToPty: true)`.
- Do not serialize follow-up Chat sends beyond the existing PTY inject lock
  (landing already races with a second send today inside the 120s window).

## Decisions

| Topic | Choice |
|-------|--------|
| Wait target | Composer surface (existing needles + 500ms visible still) |
| 120s timeout | Remove as a failure. Replace with process-lifetime wait + cap |
| Safety cap | **10 minutes** from wait start |
| Submit UX | Keep today's optimistic pending bubble. Do **not** cancel it unless the wait really fails. History continue already clears compose and holds `HistoryContinueSubmitLock` until inject |
| Silence | `ptyObserved=false` stays not-ready. Waiter idles. |

## Design

### Ready signal (unchanged)

`TabMemberMaterializer.ensureMemberInputReady(directToPty: true)` stays the
single waiter:

- Shell coordination `isReadyForAutomationInput(directToPty: true)` (boot
  frame for mixed/personal).
- Direct-PTY lifecycle gate (team sessions).
- `isMemberComposerSurfaceReady` — boot frame **and**
  `FullscreenInputReadiness` needles / dwell.
- Boot-gate CR nudge only when `bootGateNeedles` match (Codex trust copy).
  Cursor has none; a black screen must not receive CR.

`TerminalActivityTracker.isBootFrameReady` is unchanged. Visible content +
500ms fingerprint quiet remains the definition of "still."

### Wait lifetime (new)

Replace the two identical `.timeout(120s)` wrappers:

- `workspace_session_actions.dart` `_ensureLandingSessionConnected`
- `session_history_review_submit.dart` `readyTimeout` default

with one policy, owned next to the waiter (prefer a small helper used by
both call sites, not a second timeout constant copied in pages):

1. **Success** — `ensureMemberInputReady` returns because composer (or
   boot-frame-only surface) is ready.
2. **Abort** — tab missing, cubit closed, or member shell is **dead**.
   Dead means the shell exists and is not connecting, not running, and not
   connected. Do **not** abort while connect is still queued
   (`membersPendingConnect` / no shell yet / `isConnecting`). Return
   failure immediately on death; do not sit until the cap.
3. **Cap** — if still not ready after **10 minutes**, fail. Log distinctly
   from process-death (`composer wait cap`, not `member not ready` from
   120s).

`ensureMemberInputReady` itself should stop looping on a dead shell
(today it can spin until the outer timeout). The 10-minute cap may live on
the helper that calls it, but death must be detected **inside** the 100ms
poll loop so a crash at t=5s does not wait until t=10min.

Tests that pass `readyTimeout: Duration(milliseconds: 1)` keep an injectable
cap; production default is 10 minutes.

### Failure UX

On abort / cap:

- Landing: cancel optimistic `seedHistoryPending` (same as today) and toast
  an error. Do **not** do this merely because composer is slow.
- History continue: `HistoryContinueSubmitResult.failed()` so compose text
  is restored (existing path).

### What this does not change

Claude / OpenCode / flashskyai `bootFrameOnly` still become ready on first
visible quiet frame. They usually finish in seconds; the longer cap is
harmless.

TeamBus doorbell `deferForBoot` is unchanged. Operator landing stays
wait-then-inject so the first paste still has grid ACK.

## Testing

- Waiter stays pending past 120s while `isRunning` and composer needles are
  absent; completes when needles appear (Cursor `→`).
- Escape-only / empty PTY never latches boot frame (existing tracker tests).
- Dead shell (`!connecting && !running`) fails the waiter without waiting
  for the cap.
- Default cap is 10 minutes; History continue test can still inject a 1ms
  cap.
- Landing no longer treats `TimeoutException` at 120s as `member not ready`.

## Evidence

Session `000ab5e7-5001-4b26-90ad-83fad8e96b4e` (2026-08-20):

- PTY started 11:14:57; `ptyObserved=false` until 11:17:22
- Landing failed 11:16:55 (`member not ready`, 120s)
- `CursorPluginsAgentSkillsService` 144274ms; `first_paint_ms` 145076
- Materializer `input-ready` immediately after first paint
