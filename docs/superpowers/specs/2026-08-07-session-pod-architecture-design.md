# SessionPod architecture: session-scoped runtime + cache-first HistoryStore + keep-alive workbench

## Problem

The chat workbench couples per-session state into pane/global scopes, producing three visible defects and a structural tangle:

1. **Switching conversations flashes a loading pane.** `AiHistorySeat.load()` unconditionally clears the message list and emits `status: loading` before reading the transcript from disk (`ai_history_seat.dart`). `softReloadOrLoad()` only skips that hard load when the seat is already `ready` for the exact `(sessionId, memberId)` — otherwise it falls through to `load()` and blanks the list. Any conversation opened for the first time in a mount flashes "正在加载对话历史…".

2. **Launch progress is a pane-global boolean.** `workspace_chat_pane.dart::_submitting` replaces the **entire** center pane with a full-screen spinner for the whole duration of `submitWorkspaceLandingMessage` (create + PTY connect + deliver; the connect wait alone is bounded at 120 s). Every conversation shown in that pane during the window — including one the user just switched to — is obscured.

3. **Connection state is a single global sentinel.** `ChatState.sessionConnectingId` plus the literal `'pending'` sentinel (`chat_state.dart`, `session_launch_pipeline.dart`) makes `isActiveSessionConnecting` return true for **any** active session while a connect is pending. One session connecting can mis-color another session's overlay.

Underlying structural cause: per-session state (launch phase, connect phase, transcript, selected member, compose draft, view identity) is scattered across `ChatCubit`, `SessionLaunchService`, `ChatWorkbench`, `SessionChatView`, and widget-local `State` objects, with no per-session boundary. Views are not kept alive, so switching tabs unmounts and remounts `SessionChatView`, re-running `_loadHistory()`.

## Decision

Introduce a **`SessionPod`**: a stable, session-scoped runtime object that owns everything that belongs to one open conversation. The center workbench becomes a **keep-alive stack of one `SessionHost` per open pod**. Transcript loading becomes **cache-first read-through** with a no-blank invariant. Launch and connect phases become **per-session statuses** with pure-function overlays. No backward compatibility is required for TeamPilot-owned state and storage; CLI-owned transcript files remain the source of truth and are indexed, not rewritten.

## Architecture

```
WorkspacePage
 └─ WorkspaceIdeShell
     ├─ left:  sidebar (session list)
     ├─ center: WorkbenchCenter
     │    └─ KeepAliveSessionStack              ← constant container
     │         ├─ SessionHost[POD_A]  (Offstage, TickerMode off)
     │         ├─ SessionHost[POD_B]  (active)  └─ SessionWorkbench (Chat | Terminal toggle)
     │         └─ SessionHost[POD_C] …
     └─ right: tools
```

### `SessionPod` — the per-session domain object

One pod per open conversation. It owns:

| Member | Role |
|--------|------|
| `AppSession session` | The persisted session model. |
| `SessionPhase phase` | Launch/connect lifecycle: `idle → provisioning → connecting → running → paused → error`. |
| `String? launchError` | Launch failure, scoped to this pod. |
| `HistoryStore history` | Cache-first transcript store (below). |
| `String selectedMemberId` | Active member for mixed teams (simple: `''`). |
| `ComposeDraft draft` | Session compose draft, externalized off the widget tree. |
| `TeamBusHandle? bus` | Mixed-team coordination handle, owned by the pod. |
| `int keepAliveIdentity` | Stable identity so the keep-alive host does not re-key across state churn. |

Rules:

- A pod is created when a session opens and disposed only when the session is closed or its workspace is removed. It is **never** recreated by a tab switch.
- All per-session mutations go through the pod. `ChatCubit` does not reach into another pod's internals.
- Pods are pure-Dart (no `BuildContext`), so launch, phase transitions, and the history store are unit-testable without a widget tree.

### `ChatCubit` — thin coordinator

`ChatCubit` no longer holds the session detail graph. It holds:

- a `Map<sessionId, SessionPod>` registry;
- per-workspace `activeSessionId`;
- the workspace index from `SessionRepository`.

It exposes narrow queries and commands (`openSession`, `closeSession`, `submitOn(landing | session)`, `selectMember`, `setWorkbenchView`, `activePod`) and fans state changes to the UI through immutable snapshots of the pod registry (pod id + phase + status versions), not the pods themselves.

### `KeepAliveSessionStack`

An `IndexedStack`-like constant container (implemented with `Offstage` + `TickerMode`, reusing the existing `TpDeferredForegroundMount` pattern from the terminal):

- One `SessionHost` per open pod; the host is keyed by `keepAliveIdentity` so it survives pod state churn.
- Switching conversations changes only the active index: **no unmount, no remount, no `_loadHistory()`**. Scroll position, compose draft, and transcript stay in the widget.
- Active host has `TickerMode` on; inactive hosts are offstage and ticker-paused.
- Safety valve for very large session counts: an optional LRU that evicts pods whose session is not in the active workspace bucket (default off; the design does not require it).

### `SessionWorkbench` overlay — pure function

Each host renders its own `SessionWorkbench` (Chat | Terminal). The overlay it shows is a pure function of **its own** pod:

```dart
WorkbenchOverlay overlayFor({
  required SessionPhase phase,
  required HistoryStatus historyStatus,
  required bool terminalView,
  required bool hasCachedTranscript,
}) => /* exhaustive switch, unit-tested */
```

No overlay reads another session's phase. `ChatState.sessionConnectingId` and the `'pending'` sentinel are deleted; `isActiveSessionConnecting` cross-session inference is removed.

## HistoryStore — cache-first read-through

Per-session singleton. Internally partitioned by member (`MemberTranscript` per roster member), each partition merging mailbox records into the timeline. Switching members swaps partitions in the same store — it never rebuilds the store.

### Two-level cache

- **Memory:** ordered `List<AiMessage>` for each member partition.
- **Disk index:** per-CLI-transcript-file parse cursor + mailbox offset, stored TeamPilot-side. CLI-owned `.jsonl` files remain the single source of truth; the index only enables incremental locate/parse. New CLIs plug in via a `TranscriptFormat` adapter.

### Status machine

| Status | Shown when | UI |
|--------|-----------|-----|
| `initialLoading` | **Cache completely empty** (first open) | Full-pane spinner |
| `ready` | Cached content present | Transcript |
| `refreshing` | Cached content present, background read-through in flight | Transcript + thin non-blocking strip |
| `error` | Read/merge failure | Cached content kept (if any) + non-blocking error strip; full error pane only when no cache |
| `empty` | No messages and not loading | Empty-state hint |

**No-blank invariant:** any status other than `initialLoading` must never clear the rendered message list. `refreshing` and `error` keep content visible. This is the root fix for the switching flash.

### Read-through semantics

- On first open with no cache → `initialLoading`, read, then `ready`/`empty`.
- On re-open with cache → render cache immediately, set `refreshing`, read-through in background, patch the list in place (append/diff), then `ready`.
- Live refresh (running PTY) is a `refreshing` pass, not a list reset.

## SessionPhase & launch flow

### Phase transitions

```
idle ──open──► provisioning ──shell ready──► connecting ──member input ready──► running
                │                              │                                   │
                │                              ▼                                   ▼
                └──── error ◄── fail ──────────┘                                paused (user/stop)
```

Each transition updates only the owning pod's `phase`; the UI for every other session is unaffected.

### Landing submit

`WorkspaceChatPane._submit` no longer toggles a pane-global `_submitting`. It:

1. Requests `ChatCubit.openSession(createRequest)` → a pod is created in `provisioning`.
2. Awaits phase `provisioning → connecting → running` by listening to that pod (not a widget-local bool).
3. The landing surface shows only **session-scoped** progress (compose button spinner + thin progress strip). The rest of the pane stays interactive; the user can switch away at any time and the new conversation keeps launching in the background.

`submitWorkspaceLandingMessage` is split into observable per-step phases (create pod → connect → deliver), each updating only the pod's `phase`.

## Data flow

```
open session ──► ChatCubit ──► create SessionPod ──► KeepAliveSessionStack mounts host
                                                        │
first open (no cache)                                  │   re-open (cache)
        │                                              │          │
   initialLoading ──read──► ready/empty                 │    render cache instantly
                                                        ▼          │
                                     refreshing (background read-through) ──patch──► ready
switch session ──► index change only (no load)
submit on landing ──► pod.phase provisioning → connecting → running (pod-scoped progress)
```

## Error handling

- Launch failure → `pod.phase = error` + `pod.launchError`, surfaced only in that session's workbench.
- Transcript read failure → `history.status = error` + retry action; cached content stays visible.
- Mailbox merge failure → isolated to the affected member partition.
- Pod teardown must be idempotent (close on session close, workspace removal, app shutdown).

## Extensibility

- **New CLI:** add a `TranscriptFormat` adapter for `HistoryStore`; the pod structure is unchanged.
- **New view surface:** mount it inside `SessionHost`; the pod owns its lifecycle.
- **High session counts:** LRU eviction of inactive pods is a future opt-in, not a core requirement.

## Testing

- **HistoryStore unit tests:** read-through cache semantics; the **no-blank invariant** (refreshing/error never clear rendered messages); first-open initialLoading; incremental disk-index cursor; mailbox merge.
- **SessionPhase state machine:** every transition; per-session isolation (one pod in `error` does not affect another).
- **Overlay selector:** pure-function test over every `(phase, historyStatus, terminalView, hasCachedTranscript)` combination.
- **KeepAliveSessionStack widget test:** switching tabs does not re-mount `SessionChatView` and does not call `load()`.
- **Landing submit test:** pane stays interactive while a pod is `provisioning`/`connecting`; switching away mid-launch does not block the other conversation.
- Existing `ChatCubit` tests are rewritten to the pod API.

## Migration (no backward compatibility)

TeamPilot-owned on-disk formats are redesigned without migration:

- `workspace/workspaces/{id}/sessions/{sessionId}/session.json` — new shape.
- TeamBus mailbox (`bus/mail/{memberId}.jsonl`, `bus/tasks.jsonl`) — new layout.
- Compose drafts — moved into pod-owned storage (new format).
- `identities-runtime/{profileId}/session-counter.json` — unchanged semantics (still a counter).

CLI-owned transcripts are **not** rewritten: the CLI owns their format. The new per-session disk index rebuilds cursors lazily on first open; stale index entries are discarded.

## Non-goals

- Rewriting CLI transcript formats.
- Data migration of old TeamPilot-owned files.
- Backward compatibility of `ChatState` shape or UI state contracts.
- LRU eviction as a default behavior (future opt-in only).
