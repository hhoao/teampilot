# ACP Idle Reclaim + Session Resume Design

**Date:** 2026-10-15

## Problem

Two related gaps in the ACP (terminal-less chat) stack:

1. **Idle reclaim does not cover ACP seats.** The reclaim watch
   (`TabMemberReclaimWatch.tick`) only enumerates `ChatTab.memberShells` (PTY
   `TerminalSession`). ACP runtimes live in the parallel
   `ChatTab.memberAcpRuntimes` map and have no `TerminalSession`, so a mixed
   session's background ACP seats keep their agent process resident forever.
2. **Every ACP (re)start is `session/new`.** `AcpSessionRuntime.start` never
   calls `session/load` / `session/resume`, and the agent `sessionId` returned
   by `session/new` is not persisted anywhere. So manual close+reopen, app
   restart, and any future reclaim lose the **agent's own** conversation
   context. The UI still shows history because the app replays its own
   transcript (`AcpChatTranscriptWriter` → `_hydrateTranscript`), but the agent
   is amnesiac.

## Goals

- **A (reclaim):** extend idle reclaim to background ACP seats in mixed
  sessions, with a protection set, reversible via the existing lazy
  re-materialize path.
- **B (resume):** persist the ACP agent session id and resume it via
  `session/load` (fallback `session/resume`, then `session/new`), so restarts
  are lossless when the agent supports it. This also fixes manual reopen and
  app restart, not just reclaim.

## Non-goals

- Reclaiming `personal`/`simple` ACP sessions — lifted by the follow-up plan
  [2026-10-22-personal-acp-idle-reclaim](../plans/2026-10-22-personal-acp-idle-reclaim.md)
  (see D1).
- A new settings knob for the ACP threshold (see D2).
- `session/fork`, `session/delete`.
- Remote/SSH ACP (no ACP over SSH transport exists today).
- Changing the app-side transcript format or the history replay/merge logic.

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Reclaim scope = **mixed ACP seats only**. `personal`/`simple` ACP (`isAcpChatSession`) is never reclaimed. **Lifted (2026-10-22):** personal ACP is now reclaimed when its tab is *not* centre-active — see [personal ACP idle reclaim](../plans/2026-10-22-personal-acp-idle-reclaim.md). | A personal ACP session has exactly one seat which **is** the visible surface; reclaiming an *active* tab is thrash (close then immediately restore) and tears down the only agent. Only mixed sessions have "background seats"; a backgrounded personal tab does not, so discarding it is safe (visibility is the gate). |
| D2 | ACP idle threshold = `reclaimIdleTerminalAfterSeconds * 2` (no new setting). | A restart costs a fresh handshake + `session/load` + replay, higher than PTY `--resume`; doubling is a safe default without expanding the settings surface. |
| D3 | B attempts resume on **every** ACP start (reclaim, manual reopen, app restart), capability-gated per connection. | One code path; also fixes the amnesia that already exists for manual reopen. No per-CLI branching — the negotiated capability decides. |
| D4 | The agent session id is persisted in a sidecar JSON next to the transcript (`acp-session.json` / `acp-session-<memberId>.json`). | Colocated with the transcript it belongs to; no cross-layer coupling to the session repository. |
| D5 | Resume preference order: recover cwd via `session/list` when available; then `loadSession` → `session/load`; else `sessionResume` → `session/resume`; else `session/new`. | `session/load` is the ACP v1 standard (replays history); `resume` is the newer capability; `session/list` reports the session's current directory after a move. |
| D6 | A reclaim = close the cubit (persists transcript + agent id, kills the process), remove it from `memberAcpRuntimes`, and mark `reclaimedMemberIds`. Restore = the existing member-connect path re-attaching a fresh cubit. | Reuses the PTY reclaim shape and the existing connect/materialize funnel. No new restore machinery. |
| D7 | On resume, the agent's replayed history (`session/update` notifications emitted by `session/load`) is **suppressed** until the first prompt. | The app transcript is the UI source of truth; replaying it would double every message. |

## B — Agent-side session resume

### Capability choice

The `initialize` handshake already caches `AcpNegotiatedCapabilities`
(`AcpAgentConnection._capabilities`) with `loadSession` and `sessionResume`.
The spawner runs `initialize` before returning the connection, so by the time
`AcpSessionRuntime.start` opens a session the capabilities are known.

Selection (D5), all on the same live connection:

```
resumeId  = stored agent session id (may be null/empty)
resumeCwd = recorded sidecar cwd, else the session folder's launch cwd
if resumeId != null:
    if capabilities.sessionList:
        resumeCwd = session/list[resumeId].cwd ?? resumeCwd
    if capabilities.loadSession:        session/load   with resumeCwd
    else if capabilities.sessionResume: session/resume with resumeCwd
    else:                               session/new
```

A load/resume failure is **surfaced** (the cubit shows `sessionOpenFailed`
with the agent's reason). It must never be swallowed into `session/new`:
that silently replaces the user's conversation (the agent loses all context)
while the UI keeps showing the old transcript.

Why `session/list`: a session's directory can change after creation.
OpenCode's worktree tool relocates the session (`location-switched`), and both
`session/load` and `session/resume` reject any directory other than the
session's current one (`ACPSessionDirectoryMismatchError`). The launch cwd
(`session.folders.first`) can therefore be stale. When the agent advertises
`sessionCapabilities.list`, TeamPilot walks `session/list` first and resumes in
the directory the agent reports for that id.

### Suppressing replayed history (D7)

`session/load` replays the conversation as `session/update` notifications. The
app already renders its own transcript, so a loaded/resumed session starts with
`AcpAgentSession.suppressBootstrapUpdates = true`: `_onSessionUpdate` drops
everything until the first `prompt()` call, which clears the flag. `session/new`
sessions are constructed with the flag false (no behavior change).

### Persistence (D4)

New `AcpAgentSessionStore`:

```dart
class AcpAgentSessionStore {
  AcpAgentSessionStore({required Filesystem fs, required this.path});
  Future<AcpAgentSessionRecord?> readRecord();
  Future<String?> read();
  Future<void> write(String sessionId, {String? cwd});
  Future<void> clear();
}
```

File content: `{"v":1,"sessionId":"<id>","cwd":"<directory>"}`. `cwd` is optional
on read for sidecars written before it existed. Same directory as the
transcript; file name mirrors `acpTranscriptFileName` (`acp-session.json`
personal, `acp-session-<memberId>.json` seat). `AcpChatRuntimeCubit` owns it:

- `start()` reads the record, resumes in the recorded `cwd` when present, and
  passes the id to `_runtime.start(resumeSessionId: id)`.
- After a successful start, persist the live id and the directory it was opened
  with.
- `close()` does **not** clear the id (reopen must find it). A failed resume is
  surfaced to the user instead of overwriting the id with a fresh session.

## A — Idle reclaim for ACP seats

### Enumeration

`TabMemberReclaimWatch.tick` grows a second loop over
`tab.memberAcpRuntimes`, skipped when the tab is a personal ACP session
(`isAcpChatSession(tab.persistedSession)`). PTY and ACP enumerations share the
`_idleSince` map keyed by `(sessionId, memberId)` — a member lives in exactly
one map.

### Snapshot mapping

Reuses `TerminalReclaimSnapshot` / `TerminalReclaimPolicy` unchanged:

| Snapshot field | ACP source |
|----------------|------------|
| `shellRunning` | `cubit.state.phase != AcpChatPhase.ended` |
| `shellConnecting` | `cubit.state.phase == AcpChatPhase.launching` |
| `isTeamLead` | unchanged (`_isTeamLead(team, memberId)`) |
| `isDisplayed` | `tab.selectedMemberId == memberId` (chat **is** the ACP surface) |
| `inTurn` | `cubit.state.inTurn \|\| cubit.state.pendingClient != null` |
| `hasUnread` | unchanged (bus inbox unread count) |
| `isSessionPinned` | unchanged |
| `hasActiveLeases` | unchanged (seat lease port) |

`isProtected` already returns true for `!shellRunning`, launching, lead,
displayed, in-turn, unread, pinned, or leased — so an `ended` seat (process
already dead) is "protected" and never triggers a discard (nothing to discard).

The ACP pass uses its own policy instance:
`TerminalReclaimPolicy(idleAfter: Duration(seconds: acpIdleAfterSeconds))`.

### Discard

New `SessionLaunchService.discardAcpSeat(String sessionId, String memberId)`:

```dart
final tab = _tabStore.getOpenTabBySessionId(id); if (tab == null) return;
final cubit = tab.memberAcpRuntimes[mid]; if (cubit == null) return;
tab.teamBus?.markMemberDiscarded(mid);
tab.memberAcpRuntimes.remove(mid);
tab.reclaimedMemberIds.add(mid);
unawaited(cubit.close());           // persists transcript + agent id, kills process
_h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: mid);
_h.clearLaunchError(tab.info.id);
_h.updateTabRunning(tab.info.id);
```

Wired into `ChatCubit` as a second reclaim callback alongside
`discardMemberTerminal`, threaded through
`TabSessionRuntimeCoordinator` into `TabMemberReclaimWatch`.

### Restore

No new machinery: `ensureMemberTerminalForView` (team path) →
`scheduleMemberConnect` → `SessionConnectExecutor` routes an ACP seat to
`attachMemberAcpRuntime`, which re-creates the cubit because it was removed
from the map. `onConnectResult` already clears `reclaimedMemberIds` on
`ConnectShellResult.attached`. The launching phase protects the seat from being
re-reclaimed while it comes back.

### UI

Reuse the existing reclaimed placeholder (`chat_workbench.dart` →
`isMemberTerminalReclaimed` → `memberTerminalReclaimedTitle/Body`). The tap
already calls `ensureMemberTerminalForView`. No new UI is required; copy is
generic enough ("Terminal reclaimed to save memory"). Optionally reword to
"Agent 已回收" in a follow-up — out of scope here.

## Interfaces (exact)

```dart
// services/acp/acp_connection.dart
AcpNegotiatedCapabilities? get negotiatedCapabilities; // nullable, non-throwing
Future<AcpAgentSession> loadSession({
  required String sessionId, required String cwd,
  List<acpd.McpServer> mcpServers = const [],
  Map<String, Object?> meta = const {},
  Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout,
});
Future<AcpAgentSession> resumeSession({ /* same shape */ });

// services/acp/acp_session.dart
AcpAgentSession({..., bool suppressBootstrapUpdates = false});

// services/acp/acp_agent_session_store.dart
class AcpAgentSessionStore { read/write/clear }

// services/acp/acp_session_runtime.dart
Future<void> start({... , String? resumeSessionId});   // AcpSessionRuntimeApi + impl

// services/acp/acp_chat_runtime_cubit.dart
AcpChatRuntimeCubit({..., AcpAgentSessionStore? agentSession});

// services/chat/launch/session_launch_service.dart
void discardAcpSeat(String sessionId, String memberId);

// services/chat/runtime/tab_member_reclaim_watch.dart
TabMemberReclaimWatch({
  ...,
  TerminalReclaimPolicy Function()? acpPolicy,
  void Function(String sessionId, String memberId)? onDiscardAcpSeat,
});
```

## File map

| File | Change |
|------|--------|
| `client/lib/services/acp/acp_connection.dart` | `negotiatedCapabilities`; refactor `openSession` into a shared establish helper; add `loadSession` / `resumeSession` |
| `client/lib/services/acp/acp_session.dart` | `suppressBootstrapUpdates` latch; clear on first `prompt()` |
| `client/lib/services/acp/acp_agent_session_store.dart` | new store |
| `client/lib/services/acp/acp_session_runtime.dart` | `resumeSessionId` param; capability-gated load/resume/new; fallback |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | `agentSession` store; read id before start; persist live id after; pass `resumeSessionId` |
| `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` | build/expose `AcpAgentSessionStore` for both personal and seat cubits |
| `client/lib/services/chat/runtime/tab_member_reclaim_watch.dart` | ACP enumeration + snapshot + discard callback |
| `client/lib/services/chat/runtime/tab_session_runtime_coordinator.dart` | thread `acpPolicy` + `onReclaimAcpSeat` |
| `client/lib/cubits/chat_cubit.dart` | wire `onReclaimAcpSeat: _launchService.discardAcpSeat` + `acpIdleAfterSeconds` |
| `client/lib/services/chat/launch/session_launch_service.dart` | `discardAcpSeat` |
| tests | see plan |

## Edge cases / risks

- **Capabilities unavailable (fake spawners):** `negotiatedCapabilities` is
  nullable; null → `session/new`. No behavior change for tests that don't
  negotiate.
- **Stale agent session id:** load/resume failure falls back to `session/new`
  and overwrites the id. Never surface an error to the user for this.
- **Replay duplication:** handled by `suppressBootstrapUpdates` (D7).
- **Reclaim loop:** a restored seat is protected while `launching`;
  `onConnectResult` clears `reclaimedMemberIds` only on `attached`.
- **Personal ACP leakage:** the ACP loop explicitly skips
  `isAcpChatSession(tab.persistedSession)`.
- **Pending permission/ask/plan at reclaim time:** `pendingClient != null` maps
  to `inTurn` → protected. A held card is never discarded.
- **Lead seat:** protected as today.
- **All ACP seats of a mixed session included:** if the roster member is ACP and
  hidden, it is reclaimed; the selected member stays.

## Testing strategy

- **Unit:** `acp_connection_test` (load/resume choose the right acpd method,
  capability gating), `acp_session_runtime_test` (selection order + fallback),
  new `acp_agent_session_store_test`, `tab_member_reclaim_watch_test` (ACP seat
  discarded when idle/hidden; not when displayed/in-turn/launching/pending; not
  for personal), `acp_chat_runtime_cubit_test` (reads id before start; writes
  live id after; suppression until first prompt).
- **Integration:** extend `member_terminal_reclaim_integration_test` (or a new
  mixed-ACP variant) to assert an idle background ACP seat is discarded and
  re-attached on demand.
- All through `cd client && dart run tool/run_tests.dart <paths>`.

## Docs to update

- `docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md`: note ACP
  seats now participate in idle reclaim and resume.
- `docs/ARCHITECTURE.md` reclaim/runtime row if it enumerates the protection set.
