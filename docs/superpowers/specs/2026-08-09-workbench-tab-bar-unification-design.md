# Workbench Tab Bar Unification Design

Date: 2026-08-09
Status: Approved (design gate passed; implementation to follow via writing-plans)

## 1. Problem

### 1.1 The user-visible bug

Closing a session tab in the workspace strip intermittently makes the tab reappear at
the *end* of the strip. It takes several closes to actually dismiss. Switching between
sessions tends to bring it back.

### 1.2 Root cause: two sources of truth for the strip

Session tab state is owned by **two independent stores** that must be manually kept in
sync:

| Store | Owns | Sync mechanism |
|-------|------|----------------|
| `ChatTabStore` (inside `ChatCubit`) | Per-workspace buckets of `ChatTab` — presence-in-bar *and* session runtime (PTY, TeamBus, member shells, launch generation) | `closeTab(index)`, `surfaceNewTab`, `_publishActiveWorkspaceTabs` |
| `WorkbenchCubit` | Unified center-strip `tabOrder` + `activeTabId` + `previewTabIds` + `welcomeActive` | `syncSessions` (reconcile-by-append), `ensureTab`, `removeTab` |

Consequences that produce the bug:

1. **Close is index-based, and the index is taken from the wrong bucket.**
   `WorkbenchShellActions.closeAt` (`lib/services/workbench/workbench_shell_actions.dart:93`)
   computes the index from `chat.tabStore.tabsForWorkspace(tabScopeId)`, then calls
   `chat.closeTab(index)` (`lib/cubits/chat_cubit.dart:1651`), which removes at that index
   from `_tabStore._active` — the **foreground** bucket (`lib/cubits/chat/chat_tab_store.dart:19,189`).
   When `tabScopeId != tabStore.activeWorkspaceId`, the intended session tab is either left
   in place or a different tab is removed from the foreground bucket.

2. **Reconcile-by-append resurrects closed tabs.**
   `WorkbenchCubit.syncSessions` (`lib/cubits/workbench/workbench_cubit.dart:421-425`)
   appends any session id present in `sessionIds` but missing from `tabOrder` to the end.
   A session id still present in the `ChatTabStore` bucket (because the close missed it)
   is therefore re-added to the strip at the end on the next reconciliation.

3. **Every open action fans out to two cubits.**
   `openWorkspaceSessionTab` / `submitWorkspaceLandingMessage` / `createAndOpenWorkspaceConversation`
   (`lib/pages/home_workspace/workspace/workspace_session_actions.dart`) call both
   `chatCubit.requestOpenSession(...)` and `workbench.ensureTab(...)`. The sync is manual and
   easy to miss on any new path.

4. **Legacy `''` bucket.** `ChatTabStore` still carries an empty-string workspace bucket with
   special migration logic (`chat_tab_store.dart:94-138`) that the single-close path does not
   handle.

### 1.3 Class of problem

This is an architectural problem, not a typo: **two components own the same strip state and
reconcile by hand.** Fixing only the close math leaves the dual-ownership in place and the
bug class recurs. The fix is to give the strip exactly one owner.

## 2. Goals / Non-goals

### Goals

- **Single source of truth** for each strip: presence, order, active, preview. No manual
  reconciliation anywhere.
- **Close by id**, never by index into a foreign bucket.
- Clean separation: the bar owns *what's in the strip and in what order*; domain components
  (`ChatCubit` sessions, `EditorCubit` files/diffs, terminal registry, `RunCubit`) own *the
  runtime behind each tab*.
- One close path for every kind (session / file / diff / shell / run) that removes the bar
  entry *and* tears down the domain runtime.
- Better perf: strip structure changes emit rarely; hot paths (title/working) never touch the
  bar model.
- Testability: the core strip model is pure logic with unit tests.

### Non-goals

- No UI redesign of the strip or floating panel.
- No change to the session launch pipeline semantics (open / connect / member scheduling /
  teardown order) other than where bar mutations originate.
- No change to the top-level HomeShell workspace-tab bar (that bar models *which workspaces
  are open*, a different concern).

## 3. Target architecture

### 3.1 Core model: `TabStrip` — the single owner of one strip

New file: `lib/cubits/workbench/tab_strip.dart`.

```dart
/// One strip's entire state. Immutable, value-equal.
class TabStrip {
  final List<WorkbenchTabId> order;
  final WorkbenchTabId? activeId;
  final Set<WorkbenchTabId> previewIds;

  /// Landing / welcome is shown iff no tab is selected.
  bool get landingActive => activeId == null;
}
```

`WorkbenchTabId` (`lib/cubits/workbench/workbench_tab.dart`) is already `(kind, id)` and is
reused as the entry type. No new entry type.

All mutations are pure functions on `TabStrip` (a `TabStripReducer` or methods returning a new
`TabStrip`):

- `add(id, {preview, activate})` — append (or re-select if present); replaces the existing
  preview slot when `preview` and a preview exists (returns the replaced id).
- `removeById(id)` — remove, deterministically recompute `activeId`
  (previous neighbor → first → null), drop from `previewIds`.
- `reorder(oldIndex, newIndex)` — permute, preserve `activeId`.
- `activate(id)` — set active, drop from preview if permanent.
- `pin(id)` — remove from `previewIds`.
- `enterLanding()` — clear `activeId` (keep `order`; tabs remain in the bar).

Invariants (unit-tested):
- `order` has no duplicates.
- `activeId ∈ order` unless null.
- `previewIds ⊆ order`.
- `removeById` never re-adds; a removed id is gone until an explicit `add`.
- Removing the active id picks the previous neighbor, else first, else null.

### 3.2 `WorkbenchCubit` becomes the bar owner

`WorkbenchState` changes shape:

```dart
class WorkspaceTabBar {
  final TabStrip center;    // session | file | diff
  final TabStrip floating;  // shell | run
}

class WorkbenchState {
  final Map<String, WorkspaceTabBar> byWorkspace;
}
```

`WorkbenchCubit` API (replaces the old reconciliation API):

- `openSession(workspaceId, sessionId, {bool preview, bool activate = true})`
- `openFile(workspaceId, path, {preview, activate})`
- `openDiff(workspaceId, WorkbenchTabId diff, {preview, activate})`
- `openShell(workspaceId, entryId, {activate})`
- `openRun(workspaceId, runSessionId, {activate})`
- `close(workspaceId, WorkbenchTabId id) → WorkbenchTabId?` — removes from the owning strip
  (center for session/file/diff, floating for shell/run), returns the removed id.
- `closeOthers(workspaceId, keep) → List<WorkbenchTabId>`
- `closeRight(workspaceId, anchor) → List<WorkbenchTabId>`
- `closeAll(workspaceId) → List<WorkbenchTabId>`
- `reorder(workspaceId, strip, oldIndex, newIndex)`
- `activate(workspaceId, id)` (selects and exits landing)
- `pin(workspaceId, id)`
- `enterLanding(workspaceId)` (center strip: clear active)
- `clearWorkspace(workspaceId)`

Deleted: `syncSessions`, `ensureTab`, `removeTab` (replaced by `close`), `clearActive`.

**Teardown port.** `WorkbenchCubit` takes an optional `WorkbenchDomainPort` (implemented by a
bootstrap coordinator):

```dart
abstract class WorkbenchDomainPort {
  Future<void> onTabRemoved(WorkbenchTabId id, String workspaceId);
}
```

`close` / `closeOthers` / `closeRight` / `closeAll` remove from the bar and then call
`port.onTabRemoved` for each removed id so the domain tears down the runtime. The bar mutation
happens first; teardown is async and fire-and-forget.

### 3.3 Domain / bar separation

#### `ChatTabStore` → `SessionRegistry` (runtime only)

`lib/cubits/chat/chat_tab_store.dart` is reshaped into a runtime registry:

- Keep: `Map<String, ChatTab>` keyed by session id; `openTabBySessionId(id)`;
  `tabsForWorkspace(workspaceId)` as a derived query (no order semantics); `disposeSession(id)`;
  `sessionsForWorkspace(workspaceId)`.
- Remove: `append`, `removeAt`, `activeTabs`, `activeTabIndex`, `setActiveWorkspace`,
  `activeWorkspaceId`, `savedActiveIndexFor`, `removeWorkspace`'s bucket bookkeeping, the
  legacy `''` bucket, `openTabs` iteration used only for bar presence.

The name can stay `ChatTabStore` (less churn) or become `SessionRegistry`; the spec uses
`SessionRegistry` for clarity but the rename is mechanical.

`ChatTab` itself is unchanged (it is the session runtime object).

#### `ChatState` slimming

Remove from `ChatState` (`lib/cubits/chat/model/chat_state.dart`):

- `tabs` (List<ChatTabInfo>) — the strip source moves to the bar.
- `activeTabIndex`.
- `newChatActive` — derived as `bar.center.landingActive` for the active workspace.

Keep and still owned by the session domain:

- `workspaces`, `sessions`, `visibleWorkspaces`, `visibleSessions`.
- `workingSessionIds`.
- `sessionLaunchError`, `snackbarMessage`, `teamConfigValidation`, `stateVersion`.
- `activeSessionId` and `selectedMemberId` — **kept as a single-value mirror** of the bar's
  active center session, written only by the bridge (see 3.4). This is a one-way, event-driven
  mirror of one value — not a list/order reconciliation — and does not reintroduce the bug
  class. It keeps the ~13 consumers of these fields working.

`ChatTabInfo` (`lib/cubits/chat/model/chat_tab_info.dart`) stays as a domain view object
(title/subtitle/launchError/isRunning per session), but it is no longer aggregated into a
`ChatState.tabs` list; the strip projects it per-tab on demand.

### 3.4 Bridge: the only domain ↔ bar handshake

A `WorkbenchChatBridge` (new, wired in `lib/app/app_shell.dart`) implements the single
direction of causality:

```
session opened (ChatCubit)      → workbench.openSession(workspaceId, id, ...)
session closed (domain-driven)  → workbench.close(...)  [or bar removes then bridge tears down]
bar center active changed       → chat mirror activeSessionId / selectedMemberId
user close on bar               → workbench.close → WorkbenchDomainPort.onTabRemoved → chat teardown
```

Concretely:

- `ChatCubit` no longer touches `WorkbenchCubit` directly. The launch surface
  (`SessionTabSurfaceCoordinator.surfaceNewTab`) keeps creating the `ChatTab` runtime and then
  calls `bridge.onSessionTabOpened(workspaceId, sessionId, {preview, activate})` instead of
  `_tabStore.append` + `_publishActiveWorkspaceTabs`.
- `WorkbenchCubit.close` invokes the port; the bridge's port implementation calls
  `chat.teardownSession(sessionId)` (the body of today's `_tearDownTab`) and equivalent domain
  teardown for file/diff/shell/run.
- The bridge listens to `WorkbenchCubit` center-active changes and writes
  `ChatState.activeSessionId` / `selectedMemberId` via a `chat.setForegroundSession(...)` call.
  `WorkbenchCubit` exposes a `ChangeNotifier`-style hook or the bridge compares states on each
  emit (cheap, single value).

### 3.5 UI projection

`_ChatWorkspaceShell` (`lib/pages/chat/chat_page_shell.dart`):

- Strip `TabInfo` list = project `bar.center.order` directly (presence + order from the one
  source). Per-tab title/working/cli/pinned resolved by id via `context.select<ChatCubit>`
  (already implemented in `WorkbenchStripTabChip` for title/working).
- `activeTabIndex` = `bar.center.order.indexOf(bar.center.activeId)`.
- `onTabClosed(index)` → `WorkbenchShellActions.close(context, workspaceId, tab: order[index])`
  → `workbench.close(workspaceId, id)` → port → domain teardown. No ChatCubit index math.
- `onNewConversation` → `workbench.enterLanding(workspaceId)` (previously
  `chat.enterNewChat`).

Deleted widgets/helpers:

- `WorkbenchSessionSync` (`lib/widgets/workbench/workbench_session_sync.dart`) — its purpose
  (reconcile chat sessions into workbench order) no longer exists.
- `ChatScopedTabView` foreground/background bucket split (`lib/pages/chat/chat_scoped_tab_view.dart`)
  — the bar is per-workspace, so each workspace page reads its own bar bucket directly; no
  global active-workspace gating for strip reads.
- `chat_page_structural_signal`'s dependence on `state.tabs` — signal compares the workspace's
  bar bucket instead.

Keyboard nav (`WorkbenchStripNavigator`) already operates on `workbench.tabOrder`; it switches
to reading the bar's center strip for the foreground workspace.

### 3.6 Floating strip alignment (phase 2)

`FloatingWorkspaceCubit` (`lib/cubits/floating_workspace/floating_workspace_cubit.dart`) keeps
its panel chrome (visibility / placement / attention) but its tab buckets become `TabStrip`
instances at `bar.floating`. `FloatingTab` payload is resolved by the domain (terminal registry
/ `RunCubit`) by id, matching how the center strip resolves session facts. This removes the
parallel third tab implementation and lets shell/run go through the same
`openShell`/`openRun`/`close`/`reorder` surface.

## 4. Data flows

### Open a session (landing / sidebar / resume)

1. `requestOpenSession` / `requestCreateAndOpenSession` (session domain) creates the `ChatTab`
   runtime (unchanged launch pipeline).
2. `surfaceNewTab` → `bridge.onSessionTabOpened(workspaceId, sessionId, {preview, activate})`.
3. Bridge → `workbench.openSession(workspaceId, sessionId, ...)` → bar adds entry + activates.
4. Bridge → `chat.setForegroundSession(sessionId, memberId)` → ChatState mirror updates.
5. Strip re-projects `bar.center.order`; per-tab chip reads title/working by id.

### Close a session (strip X / keyboard / menu)

1. `WorkbenchShellActions.close(context, workspaceId, tab)`.
2. `workbench.close(workspaceId, id)` → removes from `bar.center`, recomputes active, emits.
3. Port `onTabRemoved(id)` → bridge → `chat.teardownSession(id)` (pod, shells, bus).
4. Strip re-projects (entry gone). There is no reconciliation step that could re-add it.

### Session ends on its own (domain-driven close)

1. Session domain tears down the runtime.
2. Bridge → `workbench.close(workspaceId, sessionId)` (idempotent no-op if already gone).
3. Bar emits; strip re-projects.

### File / diff / shell / run

Same shape: domain creates runtime → `open*`; `close` → port teardown for that kind.

## 5. Performance

- `WorkbenchCubit` emits only on **structural** changes (open / close / reorder / activate /
  pin). Working-state and title changes go through `ChatCubit` and per-chip `context.select`,
  which never touch the bar state. This is strictly better than today, where the strip
  re-projects from `state.tabs` on many emissions.
- The `ChatState.activeSessionId` mirror is a single value; the bridge updates it only when the
  bar's center active changes.
- `TabStrip` is immutable and value-equal (`Equatable`), so BlocBuilder build-when comparisons
  stay cheap.

## 6. Testing

- `TabStrip` unit tests (pure): add / removeById / reorder / activate / preview replacement /
  landing-active; invariants (no duplicates, active ∈ order, preview ⊆ order); next-active
  selection on remove (prev → first → null).
- `WorkbenchCubit` tests: per-workspace isolation; close-by-id never resurrects a tab;
  closeOthers/right/all; port teardown called exactly once per removed id.
- Bridge tests: session open drives bar add+activate; bar close drives domain teardown;
  center-active changes drive the `activeSessionId` mirror.
- Regression test for the reported bug: open two session tabs, close the first, assert the
  strip order is `[second]` and the closed id never reappears (no sync/reconcile path exists).
- Existing `workbench_cubit_test.dart`, `chat_cubit_test.dart`, and integration tests updated
  to the new API.

## 7. Migration / deletion checklist

New files:
- `lib/cubits/workbench/tab_strip.dart` (model + reducer)
- `lib/cubits/workbench/workbench_tab_bar.dart` (workspace bar model, if separate from cubit)
- `lib/services/workbench/workbench_chat_bridge.dart` (bridge + `WorkbenchDomainPort`)

Modified:
- `lib/cubits/workbench/workbench_cubit.dart` (+ `workbench_tab.dart` `isCenterStripWorkbenchTab`
  helpers stay)
- `lib/cubits/chat/chat_tab_store.dart` → runtime registry
- `lib/cubits/chat_cubit.dart` (close/select/enterNewChat/_publishActiveWorkspaceTabs reworked)
- `lib/cubits/chat/model/chat_state.dart` (drop tabs/activeTabIndex/newChatActive)
- `lib/cubits/chat/chat_connect_state_mixin.dart` (drop `state.tabs` emits)
- `lib/services/workbench/workbench_shell_actions.dart` (close by id, not index)
- `lib/pages/chat/chat_page_shell.dart` (project from bar)
- `lib/pages/chat/chat_scoped_tab_view.dart`, `chat_page_structural_signal.dart`,
  `chat_workbench_slice.dart`
- `lib/utils/workspace/workspace_new_chat_active.dart`,
  `lib/utils/session/workspace_tab_session_scope.dart`
- `lib/services/commands/session_command_registrar.dart` (close by active id)
- `lib/app/app_shell.dart` (wire bridge)
- `lib/widgets/workbench/workbench_session_sync.dart` (delete)
- `lib/cubits/floating_workspace/...` (phase 2)

Deleted APIs:
- `ChatTabStore.append / removeAt / activeTabs / activeTabIndex / setActiveWorkspace /
  activeWorkspaceId / savedActiveIndexFor / legacy '' bucket path`
- `ChatState.tabs / activeTabIndex / newChatActive`
- `WorkbenchCubit.syncSessions / ensureTab / removeTab`
- `WorkbenchSessionSync` widget

## 8. Phased implementation order

1. **Core model + bar cubit**: `TabStrip` + `WorkspaceTabBar` + `WorkbenchCubit` rewrite +
   unit tests. (Compiler is red until later phases rewire callers; keep it green by adding the
   new surface alongside where possible, or land in one commit with the full migration.)
2. **Domain registry + ChatState slim + bridge**: `ChatTabStore` → runtime registry,
   `ChatState` field removal, bridge wiring, `surfaceNewTab` route through bridge.
3. **UI projection migration**: `chat_page_shell` + scoped view/signal/slice + strip actions +
   keyboard nav.
4. **Floating strip alignment**: `bar.floating` via `TabStrip`; floating projection.
5. **Verification**: `flutter analyze --no-fatal-infos --no-fatal-warnings` and
   `flutter test --exclude-tags integration` green; manual close regression check.

Each phase lands with its tests. Phases 1–3 are the critical path that removes the bug class;
phase 4 is architecture completion.

## 9. Risks

- **Broad consumer migration** (~40 files touch `ChatTabStore`, ~22 touch `WorkbenchCubit`,
  ~13 read `activeSessionId`/`newChatActive`). Mitigated by keeping the `activeSessionId`
  mirror and by mechanical, well-tested migrations.
- **`newChatActive`/landing semantics**: several call sites (landing, submit, toggle) depend on
  "landing shows while session tabs may remain in the bar". The bar model preserves this
  (`activeId == null` with non-empty `order`). Unit tests cover the transitions.
- **Preview replacement** must keep returning the replaced id so callers can close the replaced
  domain runtime (existing `closeReplacedPreview` behavior).
- **Ordering guarantee**: sessions currently surface at the end; `TabStrip.add` preserves
  append-at-end for new tabs while `reorder` is explicit — matches today's UX.
