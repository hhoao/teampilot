# AI History seat isolation (multi-workspace)

## Goal

Stop cross-workspace / cross-session chat History contamination when multiple workspaces keep sessions alive. Align History ownership with the existing per-tab PTY / TeamBus model so each seat renders and refreshes its own transcript.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Architecture | **Seat-scoped History runtimes** (`sessionId\|memberId`), not a single shared `ExternalStoreAiThreadRuntime` |
| Cubit shape | Keep one app-wide `AiHistoryCubit` as a **registry facade**; move per-seat mutable state into `AiHistorySeat` |
| Background live refresh | **Yes** while seat is **hot** (route foreground **or** member PTY running) |
| Background idle | **Warm**: keep last messages; stop file watchers / softReload loops |
| Eviction | Drop seat when its chat tab / session closes; no unbounded dormant cache (optional small LRU later if needed) |
| UI binding | `SessionHistoryThread` binds **that seat’s** `runtime` + seat state — never a global singleton message list |
| Scoped identity | Chat UI uses `widget.selectedMemberId` / scoped tab APIs; never foreground-only `ChatState.selectedMemberId` for History/submit |
| Member running | `isMemberRunning` resolves against the **target session’s tab**, not only `_activeTab` |
| `routeActive` | Wire from `WorkspaceRouteActiveScope` into chat shell so background tabs do not steal focus-seat chrome |

## Non-goals (v1)

- Per-workspace `AiHistoryCubit` providers (facade + seats is enough)
- Persisting in-memory History seats to disk (loader remains source of truth)
- Changing TeamBus / Mailbox / Board isolation (already per-tab)
- Reworking terminal Alacritty engines (already per-tab)

## Problem (current)

1. `AiHistoryCubit` owns one `runtime` and one `_lastSession` / `_lastMemberId`.
2. `HomeWorkspaceBodyStack` keep-alives multiple `SessionChatView` trees.
3. Any seat `load` / `softReload` / live refresh replaces the shared `runtime.messages`; every mounted `SessionHistoryThread` repaints with the wrong transcript.
4. Secondary leaks: `SessionChatView` reads `ChatCubit.state.selectedMemberId`; `isMemberRunning` only checks `_activeTab`; `ChatPageShell.routeActive` defaults true for background workspaces.

PTY and TeamBus are already isolated per `ChatTab`. History is the layer that mixes.

## Product UX

- Switching workspaces never shows another workspace’s bubbles.
- While a background workspace’s seat is still generating (PTY running), its History may continue to update so returning is current.
- Idle background seats freeze watchers; returning soft-reloads if needed without wiping unrelated seats.
- Landing `seedPendingUser` and continue-send pendings attach to the **target seat**, even if another seat is focused.

## Architecture

```
AiHistoryCubit (app singleton facade)
  loader: AiHistoryLoader
  seats: Map<seatKey, AiHistorySeat>
  focusSeatKey?          // optional; for app-level stale hooks / diagnostics
  seedPending (session, member, text)  // survives until that seat loads

AiHistorySeat
  key = sessionId|memberId
  runtime: ExternalStoreAiThreadRuntime
  state: AiHistoryState (status, awaiting, counts, …)
  load generation, pendings, sticky locals, tip-hold
  last Session / Team / launchContext / workingDirectory
  liveRefresh?: AiHistoryLiveRefreshController

SessionChatView(session, selectedMemberId, routeActive, …)
  → cubit.seatFor(session, member)  // ensure + bind
  → Bloc/listenable on that seat only
  → SessionHistoryThread(runtime: seat.runtime)
```

### Seat key

Extract a shared helper (e.g. `historySeatKey(sessionId, selectedMemberId)` / reuse shell-member normalization):

```
shellMemberId = selectedMemberId.trim().isEmpty ? sessionId : selectedMemberId.trim()
seatKey = '$sessionId|$shellMemberId'
```

Simple mode must **not** use an empty member segment. The same `shellMemberId` is the key into `ChatTab.memberShells` and the `memberId` argument to `isMemberRunning(sessionId:, memberId:)` — History seat, PTY lookup, and mailbox-style seat strings stay aligned.

### Hot / warm / dispose

| Mode | Condition | Behavior |
|------|-----------|----------|
| **Hot** | Workspace `routeActive` **or** seat member PTY `isRunning` | Live refresh allowed; softReload on stale / watch events |
| **Warm** | Mounted keep-alive, not hot | Keep `runtime.messages`; stop live refresh; ignore other seats’ reloads |
| **Dispose** | Chat tab closed / session removed from open tabs | `seat.dispose()`; remove from map; cancel timers/watchers |

**Eviction owner:** `ChatCubit` (or tab-store close hooks) calls `AiHistoryCubit.disposeSeatsForSession(sessionId)` when a chat tab is closed / removed from open tabs. `SessionChatView` may release its live-refresh attachment on dispose / seat change, but must **not** be the sole eviction path (keep-alive background views would otherwise leak seats until process end).

`ChatCubit.onSessionHistoryStale(sessionId)` should soft-reload **all open seats for that sessionId** (or the specific member if available), not only “whatever was last loaded”.

### Facade API (preserve call sites where possible)

Keep method names used by UI / landing, but make them seat-addressed:

- `load` / `softReloadOrLoad` / `softReload` — already take session+member (or use last seat for softReload only when caller is seat-bound)
- `seedPendingUser` / `cancelSeedPendingUser` — store by seat key; apply when that seat finishes load
- `enqueuePendingUser` / `appendStickyLocalUser` / `removePendingMatching` / `setAwaitingAssistant` / `flushHeldTip` / `clearPendings` — operate on an **explicit seat** (pass session+member, or obtain `AiHistorySeat` handle from `SessionChatView`)
- `softReloadIfSession(sessionId)` — iterate matching seats
- Expose `AiHistorySeat? seatOf(sessionId, memberId)` and `ExternalStoreAiThreadRuntime runtimeFor(...)` for widgets

Avoid a second global “current seat” mutation path that UI can accidentally share: prefer `SessionChatView` holding a seat handle for the widget lifetime.

### UI / ChatCubit fixes (same change set)

1. **`SessionChatView`**: use `widget.selectedMemberId` for submit, permission banner, and History; stop `context.select` of foreground `selectedMemberId` for those paths.
2. **`AgentPermissionAttentionBanner`**: also stop reading foreground `ChatCubit.state.selectedMemberId`; take scoped session + member (or resolve via widget props).
3. **`ChatCubit.isMemberRunning`**: resolve shell via `openTabBySessionId(sessionId)`; API uses **shell member id** (`shellMemberId` above), e.g. `isMemberRunning({required sessionId, required memberId})`.
4. **`ChatPage` / `ChatPageShell`**: pass `routeActive` from `WorkspaceRouteActiveScope`.
5. **Live refresh**: one controller **per seat**, started/stopped by hot/warm; `AiHistoryLiveRefreshController` must softReload **its bound seat** (today it calls bare facade `softReload()` — change in the same deliverable). Background warm seats must not refresh other seats.
6. **`SessionHistoryThread`**: subscribe only to the runtime instance passed in; update comments — runtime is seat-scoped, not app-scoped. Keep scheduler-phase guard if still useful under deferred mount.

## State emission

Options (pick during implementation; prefer simplest that keeps BlocBuilder working):

1. **Seat is a `Cubit<AiHistoryState>`** (or `ChangeNotifier`) nested under the facade; `SessionChatView` listens to the seat directly.
2. **Facade emits a map / focus + version token**; widgets `select` their seat slice.

Recommendation: **(1)** — each `AiHistorySeat` is a small `Cubit` (or change notifier + seat state). Facade owns lifecycle and loader. Avoids rewriting every `BlocBuilder<AiHistoryCubit>` into fragile global selects; migrate `SessionChatView` to `BlocProvider.value(value: seat)` or `BlocBuilder` on the seat type.

Landing / stale hooks keep using the facade.

## Error handling

- Load errors stay on that seat’s state (`error` / `softReloadError`); other seats unaffected.
- Failed live refresh remains best-effort (log + keep last good messages), same as today.
- Closing a tab mid-load increments seat generation / disposes seat so late results do not resurrect into a new seat with the same key unless re-opened intentionally.

## Testing

| Case | Expectation |
|------|-------------|
| Two seats load different transcripts | Each `SessionHistoryThread` shows only its seat’s messages |
| SoftReload seat A while B mounted | B’s `runtime.messages` unchanged |
| Live refresh hot background seat | A updates; B unchanged |
| Warm background seat | Watcher stopped; no cross softReload |
| `seedPendingUser` for seat B while A focused | Pending appears on B when B loads, not on A |
| `selectedMemberId` scoped | Background view submit/history uses widget member, not foreground |
| `isMemberRunning(session, member)` | True for background running PTY |
| Tab close | Seat disposed; no listener leaks |

Prefer unit tests on registry/seat + a widget test with two `SessionHistoryThread`s bound to two seat runtimes. Extend or replace the old “app-scoped runtime” comment/test accordingly.

## Migration / compatibility

- Single `BlocProvider<AiHistoryCubit>` in `app_shell` remains.
- Integration harness (`CliMessageMatrixHarness`) can keep one cubit; matrix cells usually one seat — add a multi-seat unit test rather than expanding every matrix cell.
- No on-disk format change.

## Success criteria

1. Two workspaces with live sessions never show each other’s History bubbles.
2. Hot background seats can still refresh; warm seats do not thrash disk or overwrite others.
3. Scoped member / running / routeActive leaks fixed in the same deliverable.
4. Existing single-seat History behaviors (pending, sticky mailbox, tip-hold, softReloadOrLoad) preserved per seat.
