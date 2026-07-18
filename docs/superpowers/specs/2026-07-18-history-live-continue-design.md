# History live continue: stay on History + transcript hot reload

**Date:** 2026-07-18  
**Status:** Approved for planning (spec review 2026-07-18)  
**Related:** [`2026-07-17-history-review-virtualized-thread-design.md`](2026-07-17-history-review-virtualized-thread-design.md), [`2026-07-18-history-claude-aligned-light-open-design.md`](2026-07-18-history-claude-aligned-light-open-design.md)

## Problem

History review already renders CLI transcripts as a conversation thread (`SessionHistoryReview` + `ai_message_*`). Live work still happens only in the Alacritty PTY. Submitting from History **always** switches the workbench to Terminal (`chat_workbench.dart` → `setSessionWorkbenchView(...terminal)`), so the conversation surface cannot follow the turn. There is no live refresh of parsed messages while the seat PTY runs.

Users want a Claude Code extension–like **conversation continue** experience without replacing the PTY as the runtime.

## Goals

- History remains the default **review + continue** surface after submit.
- Terminal remains the only **true runtime** (connect, inject, permissions, raw TTY).
- After continue, History updates **near-real-time** from on-disk transcripts for **all five** launch CLIs (Claude, flashskyai, Codex, OpenCode, Cursor).
- Preference controls whether submit switches to Terminal (default: stay on History).
- Works across storage backends: local watch when available; WSL/SFTP via `Filesystem.stat` polling.

## Non-goals

- Replacing PTY with stream-json / SDK as the primary agent transport.
- Per-CLI incremental tail parsers or a second message pipeline.
- WebView / React rewrite of History.
- A dedicated `/history` route (History stays a session workbench view).
- Making History the place to answer CLI permission prompts (offer jump-to-Terminal only).

## Product decisions (locked)

| Choice | Decision |
|--------|----------|
| Runtime | PTY inject path unchanged (`submitSessionHistoryReviewMessage`) |
| Default after submit | Stay on History |
| Preference | `SessionPreferences.historySubmitSwitchesToTerminal` (default `false`) |
| Live updates | Transcript change signal → soft reload via existing locate/parse |
| Change signal | Local: `FsWatcher.watchTree`; else cache-token poll |
| CLI scope | All five via shared controller + provider watch metadata |
| Optimistic UI | Pending user message on successful inject; drop by concrete match rule below |
| Multi-seat | Refresh only the selected seat; restart on seat change |
| softReload window | Tip-anchored: grow `_visibleCount` by tip Δ so older `start` is preserved; stick vs chip is scroll-only |

## Architecture

```
SessionHistoryReview (visible) + seat PTY running
  → AiHistoryLiveRefreshController
       ├─ TranscriptChangeSignal
       │     ├─ fs is FsWatcher → watchTree(watchRoot), debounce ~150ms
       │     └─ else → Timer poll cache tokens (~750ms local-like, ~1.2s SFTP)
       └─ onChange → AiHistoryCubit.softReload()
              → AiHistoryLoader (invalidate → full parse)
              → ExternalStoreAiThreadRuntime merge
              → SessionHistoryThread (sticky bottom / “new messages”)

onSubmit:
  connect + ensure ready + inject (unchanged)
  optimistic pending user AiMessage
  if historySubmitSwitchesToTerminal → Terminal (legacy)
  else → stay History + ensure live refresh running
```

### Components

| Unit | Responsibility |
|------|----------------|
| `historySubmitSwitchesToTerminal` | Persisted preference; settings UI beside `openExistingSessionStartsTerminal` |
| `AiHistoryLiveRefreshController` | Start/stop lifecycle; debounce; coalesce in-flight reloads |
| `TranscriptChangeSignal` | Emits “transcript may have changed”; watch or poll |
| Provider watch metadata | Each `AiHistoryProvider` / locate path exposes `changeWatchRoot` + `cacheTokenPaths` (hints or typed fields) so the controller does not hardcode CLI layouts |
| `AiHistoryCubit.softReload` | Reload without flipping UI to full-screen `loading`; preserve prior messages until new parse succeeds; **pagination invariants below** |
| Submit wiring | Remove unconditional Terminal switch in `chat_workbench` / callers; gate on preference |

### softReload pagination invariants (locked)

Visible slice is **tip-anchored**: `start = length - _visibleCount` (same as today’s cubit). Live softReload **must not** call the initial-load path that resets `_visibleCount` to `kSessionHistoryInitialTurns` while status is already `ready`.

On successful softReload:

1. Let `oldLength = _allMessages.length` (before replace), `oldVisible = _visibleCount`.
2. Replace `_allMessages` with the new full parse (`newLength`).
3. **Grow visible count by tip Δ** (preserve `start` when the transcript only appends):
   - `tipDelta = max(0, newLength - oldLength)`
   - `_visibleCount = min(newLength, oldVisible + tipDelta)`
   - If `newLength < oldLength` (rare truncate/rewrite): `_visibleCount = min(oldVisible, newLength)`.
4. Never emit `AiHistoryViewStatus.loading` on softReload when already `ready` / showing prior content; keep `AiHistoryRenderScope` (History light-open budget).
5. On parse failure: leave `_allMessages` / `_visibleCount` / runtime messages unchanged; show non-blocking error.
6. After applying the parsed window, **re-merge** any still-unmatched optimistic pendings onto the runtime tip.

**Stick vs scrolled-up is viewport/chip only** (not a second cubit window model):

- softReload always applies the tip-Δ growth above so older pages already in the window stay mounted (`start` stable on append).
- If the user is stick-to-bottom: thread auto-scrolls to tip after reload.
- If the user has scrolled up: do **not** auto-scroll; show “↓ New messages”; chip / jump-to-bottom scrolls to tip (visible window already includes new tip turns via tip-Δ growth).

Cubit does not need a stick-state branch for pagination — host/thread owns stick and the chip.

### Optimistic pending user messages (locked)

- On successful inject, append a **local pending** user `AiMessage` (stable local id, e.g. `pending:<uuid>`) to the tip of the runtime view (and to a cubit-side pending queue), without waiting for disk.
- Normalize compare text: `trim` + collapse internal whitespace runs to a single space.
- **Drop rule:** after each successful softReload, for each pending (oldest first): remove it when **any** user-role message in the newly parsed tip window (last `N` user turns, `N = max(pendingQueue.length + 2, 5)`) has normalized text **equal** to the pending text. Prefer matching the chronologically latest unmatched user turn with that text.
- **Multi-submit before flush:** queue pendings in inject order; each softReload may clear zero or more from the front/middle per the rule above; unmatched pendings stay until matched or the seat/session changes (then clear all pendings).
- Pending bubbles are **not** written to disk and are **not** included in export/copy as persisted history.

### Pre-locate / missing transcript

While locate returns null (file not created yet): keep the change signal alive (poll tokens / re-locate on interval). Do not start `watchTree` until a `changeWatchRoot` is known; once locate succeeds, switch to watch-or-poll with real roots. softReload no-ops (keep prior / empty) until messages exist.

### Lifecycle

```
Start when: workbenchView == history AND History widget mounted
            AND selected seat PTY is running (or connect just succeeded for continue)
Stop when:  switch to Terminal, change seat, dispose review, leave History body
On return to History: force softReload once, then restart signal
```

### UX details

- Clear compose after successful inject; show pending user bubble immediately.
- Light “Running…” footer while live refresh is active and seat is not idle (best-effort; idle detection may reuse existing presence/idle hooks when available).
- Stick-to-bottom while user is at bottom; if user scrolls up, pause auto-stick and show a “↓ New messages” chip (host-owned chrome; virtualization viewport keeps spacer stick math — intentional product addition beyond the virtualization spec’s “no FAB required” note). Chip scrolls to tip; pagination already includes new tip turns via tip-Δ growth on softReload.
- Existing History ↔ Terminal tab toggle unchanged.
- Optional banner: “Needs Terminal confirmation” + jump action when we can detect wait-for-input; first ship may ship the jump affordance without perfect detection.

### Error handling

| Case | Behavior |
|------|----------|
| Connect / ready / inject failure | Keep compose text; remove pending; stay on History; surface via existing `launchError` |
| Transcript missing yet | Keep polling/watching; no hard error |
| Parse failure on reload | Keep last good messages; non-blocking error strip; retry on next change |
| Watch unsupported (SFTP) | Poll only; do not claim watch |

## Relation to existing History perf work

Virtualization (`VirtualThreadViewport`) and Claude-aligned IR budget (`AiHistoryRenderScope`) stay in force. Live softReload must not reintroduce full-tree flash or drop the light-open budget for History scope. Live path still uses History render scope (not “full live markdown”) until a separate decision says otherwise.

## Testing

- Preference default `false`, JSON round-trip, settings toggle.
- Submit with preference false → view stays History; true → Terminal.
- Controller starts/stops with view/seat/PTY state.
- `FsWatcher` branch vs poll branch (mock filesystem).
- `softReload` does not emit `AiHistoryViewStatus.loading` when already `ready`.
- Tip-Δ unit cases: append grows `_visibleCount` by Δ and preserves `start`; truncate clamps `_visibleCount`; snapshot `oldLength`/`oldVisible` immediately before replace (after await) so a concurrent `loadOlder` is not clobbered by a stale pre-await snapshot; honor load generation / seat-id so in-flight softReload no-ops after seat change or dispose.
- Optimistic pending drops once a reparsed tip user turn equals pending text under the normalize + tip-window rule above; multi-pending queue clears in order across reloads.
- SSH/poll path: token change triggers reload (unit with fake clock + stat).

## Success criteria

1. Continue from History without leaving the conversation surface (default prefs).
2. Within ~1–2s of CLI flushing transcript (local watch closer), new assistant/tool turns appear in History for each supported CLI.
3. Terminal remains reachable and correct for raw interaction.
4. No worse History open perf regression vs current light-open baseline when idle (refresh stopped).

## Implementation notes (guidance, not a plan)

Primary touch points:

- `client/lib/models/session_preferences.dart` (+ settings UI + l10n)
- `client/lib/pages/chat_workbench.dart` (gated view switch)
- `client/lib/cubits/ai_history_cubit.dart` (`softReload`, pending message API)
- New: `client/lib/services/session/ai_history_live_refresh_controller.dart`
- New: `client/lib/services/session/transcript_change_signal.dart`
- `AiHistoryProvider` locate / hints for watch roots (all five adapters)
- `SessionHistoryReview` / thread: sticky chip, running footer, wire controller
