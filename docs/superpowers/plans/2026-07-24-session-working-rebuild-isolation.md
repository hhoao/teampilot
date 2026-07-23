# Session Working Rebuild Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate high-frequency `workingSessionIds` (and row title/time) rebuilds to leaf widgets so the first Session message no longer freezes on bulk `RenderParagraph` layout.

**Architecture:** Split sidebar/workbench subscriptions into Structure / RowContent / RunningIds / ephemeral presence. Parents select structure only; tiles and tab chips live-select content and working. `ChatPageShell` structural `buildWhen` drops working and title-bearing session equality; tab chips select working + title locally.

**Tech Stack:** Flutter / Dart, `flutter_bloc` `context.select` / `BlocBuilder.buildWhen`, existing `WorkspaceSidebarSessions` equality pattern.

**Spec:** `docs/superpowers/specs/2026-07-24-session-working-rebuild-isolation-design.md`

**Commits:** Do **not** git commit unless the user explicitly asks. Tick commit steps only when requested.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/utils/session/session_list_structure.dart` | Post-sort ordered `{sessionId, pinned, sortOrder}` snapshot + factory from sessions + `AppSessionSort` |
| `client/lib/utils/session/session_row_content.dart` | `sessionId`, `display`, `updatedAt`, `createdAt` + `fromSession` / `fromChatState` helpers |
| `client/lib/utils/session/running_session_ids.dart` | Order-sensitive immutable id list from `workspaceRunningSessions` |
| `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | Remove parent working select; always-mount `RunningSessionsHost`; conversation host selects structure |
| `client/lib/pages/home_workspace/workspace/worktree_group_section.dart` | Take ordered session ids; build tiles by id |
| `client/lib/widgets/sidebar_session_tile.dart` | Paint title/time from `SessionRowContent` select; accept `sessionId` primary |
| `client/lib/pages/chat/chat_scoped_tab_view.dart` | Remove `workingSessionIds` |
| `client/lib/pages/chat/chat_page_shell.dart` | Structural `buildWhen`; project tabs with `working: false` + placeholder title; no working/sessionWorking in structural builder |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Tab chip live-selects working + title when `sessionId` known |
| `client/lib/services/workbench/workbench_tab_projection.dart` | Allow placeholder title / default working false from shell |
| `docs/PERFORMANCE.md` | Document leaf-only presence subscription rule |
| Tests under `client/test/utils/session/`, `client/test/pages/` | Equality + inner rebuild probes |

---

### Task 1: Snapshot value types (TDD)

**Files:**
- Create: `client/lib/utils/session/session_list_structure.dart`
- Create: `client/lib/utils/session/session_row_content.dart`
- Create: `client/lib/utils/session/running_session_ids.dart`
- Create: `client/test/utils/session/session_rebuild_snapshots_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/session/app_session_sort.dart';
import 'package:teampilot/utils/session/running_session_ids.dart';
import 'package:teampilot/utils/session/session_list_structure.dart';
import 'package:teampilot/utils/session/session_row_content.dart';

AppSession _s({
  required String id,
  String display = '',
  int createdAt = 1,
  int updatedAt = 0,
  bool pinned = false,
  int sortOrder = 0,
}) => AppSession(
  sessionId: id,
  workspaceId: 'ws',
  folders: const [WorkspaceFolder(path: '/a')],
  display: display,
  createdAt: createdAt,
  updatedAt: updatedAt,
  pinned: pinned,
  sortOrder: sortOrder,
);

void main() {
  test('SessionListStructure ignores display/updatedAt/working-only noise', () {
    final a = SessionListStructure.fromSessions(
      [_s(id: 'a', display: 'old', updatedAt: 10)],
      sort: AppSessionSort.createdDesc,
    );
    final b = SessionListStructure.fromSessions(
      [_s(id: 'a', display: 'new', updatedAt: 99)],
      sort: AppSessionSort.createdDesc,
    );
    expect(a, b);
  });

  test('SessionListStructure changes when recentlyUpdated reorder changes', () {
    final a = SessionListStructure.fromSessions(
      [_s(id: 'a', updatedAt: 1), _s(id: 'b', updatedAt: 2)],
      sort: AppSessionSort.recentlyUpdated,
    );
    final b = SessionListStructure.fromSessions(
      [_s(id: 'a', updatedAt: 3), _s(id: 'b', updatedAt: 2)],
      sort: AppSessionSort.recentlyUpdated,
    );
    expect(a, isNot(b));
    expect(b.sessionIds, ['a', 'b']);
  });

  test('SessionRowContent changes on display/updatedAt/createdAt', () {
    final base = SessionRowContent.fromSession(_s(id: 'a', display: 't', createdAt: 1));
    expect(base, isNot(SessionRowContent.fromSession(_s(id: 'a', display: 'u', createdAt: 1))));
    expect(base, isNot(SessionRowContent.fromSession(_s(id: 'a', display: 't', createdAt: 1, updatedAt: 5))));
    expect(base, isNot(SessionRowContent.fromSession(_s(id: 'a', display: 't', createdAt: 2))));
  });

  test('RunningSessionIds order-sensitive equality', () {
    final a = RunningSessionIds.fromWorkspace(
      sessions: [_s(id: 'a'), _s(id: 'b')],
      workingSessionIds: {'b'},
      openTabSessionIds: {'a'},
    );
    final same = RunningSessionIds.fromWorkspace(
      sessions: [_s(id: 'a'), _s(id: 'b')],
      workingSessionIds: {'b'},
      openTabSessionIds: {'a'},
    );
    final different = RunningSessionIds.fromWorkspace(
      sessions: [_s(id: 'a'), _s(id: 'b')],
      workingSessionIds: {'a'},
      openTabSessionIds: {'b'},
    );
    expect(a, same);
    expect(a.ids, ['b', 'a']);
    expect(a, isNot(different));
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL (missing libraries)**

```bash
cd client && flutter test test/utils/session/session_rebuild_snapshots_test.dart
```

- [ ] **Step 3: Implement the three snapshot types**

Mirror `WorkspaceSidebarSessions` `@immutable` + deep `==` / `hashCode`.

`SessionListStructure.fromSessions` must call `sortAppSessions` then map to rows `{sessionId, pinned, sortOrder}` only.

`RunningSessionIds.fromWorkspace` wraps `workspaceRunningSessions(...).map((s) => s.sessionId)`.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/utils/session/session_rebuild_snapshots_test.dart
```

- [ ] **Step 5: Commit (only if user asked)**

---

### Task 2: `SidebarSessionTile` paints from `SessionRowContent`

**Files:**
- Modify: `client/lib/widgets/sidebar_session_tile.dart`
- Create: `client/test/widgets/sidebar_session_tile_row_content_test.dart` (or extend an existing tile test if present)

- [ ] **Step 1: Write failing widget test**

Mount tile with `sessionId: 'a'` under `ChatCubit` that has session display `'Hello'`. Assert `find.text('Hello')`. Then `applyState` rename to `'World'` without rebuilding parent key — assert text updates via select.

Also assert relative-time inputs use `SessionRowContent` (updatedAt/createdAt), not a stale `widget.session`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

- Prefer ctor `sessionId` (+ keep optional `AppSession? session` for actions if needed, but **Text never uses it**).
- In `build`:
  ```dart
  final content = context.select<ChatCubit, SessionRowContent>(
    (c) => SessionRowContent.fromChatState(c.state, sessionId),
  );
  // title Text(content.displayTitleOrFallback)
  // timestamp from content.updatedAt / createdAt
  ```
- Keep existing working / waiting / selected selects.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit (only if user asked)**

---

### Task 3: Sidebar Running host + structure list (TDD rebuild probes)

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- Modify: `client/lib/pages/home_workspace/workspace/worktree_group_section.dart`
- Create: `client/test/pages/home_workspace/workspace_sidebar_working_rebuild_test.dart`

- [ ] **Step 1: Write failing rebuild-probe test**

Harness: `WorkspaceSidebar` with 2 sessions, group headers instrumented with inner `StatefulWidget` build counters (or wrap `_WorktreeGroupHeader` via test seam / find by text and check Element rebuild using a `RebuildProbe` child injected only in test — prefer extracting a small public/test-visible probe key on group label `Text` parent).

Simplest reliable approach used in-repo: pass optional `Key` / wrap section hosts:

```dart
// In production code, expose:
// - RunningSessionsHost (private OK if tested via keys AppKeys…)
// - Conversation list body under a Key('workspace-sidebar-conversation-list')

// Test inserts RebuildProbe as ancestor only if we add:
class RebuildProbe extends StatefulWidget { ... int buildCount; }
```

Assert on working-only emit:
- conversation list probe **unchanged**
- running host probe **+1**
- target tile working path updates (spinner present)

- [ ] **Step 2: Run — expect FAIL (parent still selects working)**

- [ ] **Step 3: Implement sidebar wiring**

1. **Delete** parent `context.select(WorkspaceSidebarSessions)` and any `workingSessionIds` / `runningSessionIds` select in `WorkspaceSidebar.build`. Keeping `WorkspaceSidebarSessions` would still rebuild the whole Column on `display`/`updatedAt`.
2. Always insert `RunningSessionsHost(workspace:, tabScopeId:)` which:
   - Builds `RunningSessionIds.fromWorkspace` with the **same membership inputs as today**: workspace-filtered sessions + `workingSessionIds` + `openTabSessionIdsForWorkspace` from tabs where `tab.isRunning` (not every open history tab)
   - if empty → `SizedBox.shrink()`
   - else section + `SidebarSessionTile(sessionId: …)`
3. Conversation body selects **only** `SessionListStructure` (factory inside the selector from workspace-filtered sessions + active `_sessionSort`) plus existing worktree view. Pass **ordered ids** into `WorktreeGroupSection` / list builders; resolve full `AppSession` only inside tile actions via cubit read, not for `Text`.
4. Do not select `AgentAttentionCubit` in parents for membership.
5. Rebuild probes must cover rename-only: conversation/group header unchanged; sibling tile title unchanged; target tile +1.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit (only if user asked)**

---

### Task 4: Remove working from `ChatScopedTabView` + structural `ChatPageShell`

**Files:**
- Modify: `client/lib/pages/chat/chat_scoped_tab_view.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart`
- Modify: `client/test/utils/session/workspace_tab_session_scope_test.dart` (ChatScopedTabView cases)
- Replace/fix: `client/test/pages/chat_page_rebuild_test.dart`

- [ ] **Step 1: Write failing tests**

1. Update `ChatScopedTabView` tests: type has no `workingSessionIds`; equality ignores working flips.
2. Replace outer `_ShellRebuildProbe` wrapping `ChatPageShell` with an **inner** probe:

```dart
// Add optional @visibleForTesting hook OR wrap body child:
// ChatPageShell(…, structuralBodyProbe: probe) // avoid if possible

// Preferred: put RebuildProbe inside ChatPageShell structural builder
// behind assert(() { ... }) or a test-only Key on WorkspaceShell body.
```

Minimal production seam: `WorkspaceShell` body wrapped with `KeyedSubtree(key: ValueKey('workspace-shell-body'))` and test uses a custom `ChatPageShell` test subclass — **better:** inject rebuild counter via:

```dart
// In chat_page_shell structural builder, wrap the WorkspaceShell child body:
child: _StructuralBody(
  key: const ValueKey('chat-page-structural-body'),
  child: WorkspaceShell(...),
)
```

where `_StructuralBody` is a tiny StatefulWidget that only returns child — tests find its State via `tester.state`.

Assert:
- working-only emit → structural body buildCount unchanged
- rename-only (sessions display change + tab title) → structural body unchanged
- open/close tab → structural body +1

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

`_scopedTabBuildWhen` must compare an **explicit title-free tuple** extracted from `prev`/`next` (do **not** use `previous.tabs != next.tabs`, full `ChatScopedTabView ==`, `workbenchSlice ==`, or bare `stateVersion` — `ChatTabInfo` equality includes `title`/`subtitle`/`isRunning` and would still rebuild on rename):

```dart
// Compare only:
// - open tab ids + order
// - activeTabIndex, newChatActive
// - selectedMemberId
// - sessionConnectingId / sessionLaunchError for active
// - pinned flags for open tab ids
// NEVER: workingSessionIds, full sessions list, tab titles, stateVersion alone
```

Structural builder:
- `sessionWorking` map → all false / omit
- `sessionTitles` → placeholder (`''` or id) — **never** live display
- **Must not** read `workingSessionIds` or pass live titles into `projectWorkbenchTabs`

- [ ] **Step 4: Fix all `ChatScopedTabView.workingSessionIds` call sites (compile)**

- [ ] **Step 5: Run targeted tests — expect PASS**

```bash
cd client && flutter test test/pages/chat_page_rebuild_test.dart test/utils/session/workspace_tab_session_scope_test.dart
```

- [ ] **Step 6: Commit (only if user asked)**

---

### Task 5: Tab chip live working + title

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart`
- Modify: `client/lib/services/workbench/workbench_tab_projection.dart` (if needed for sessionId on TabInfo)
- Create/extend: tab chip rebuild test

- [ ] **Step 1: Write failing test**

Open session tab chip: working-only emit flips working chrome without structural body rebuild; rename updates chip title text via select.

- [ ] **Step 2: Implement**

For session-kind tabs, pass `sessionId` into `WorkspaceShellTabChip`. Inside chip `build`:

```dart
final working = sessionId == null
    ? widget.working
    : context.select<ChatCubit, bool>((c) => c.state.workingSessionIds.contains(sessionId));
final title = sessionId == null
    ? widget.title
    : context.select<ChatCubit, String>((c) => SessionRowContent.fromChatState(c.state, sessionId).titleForPaint);
```

File/diff/shell tabs keep constructor title/working.

- [ ] **Step 3: Run tests — expect PASS**

- [ ] **Step 4: Commit (only if user asked)**

---

### Task 6: Docs + grep gate + analyze

**Files:**
- Modify: `docs/PERFORMANCE.md`
- Grep verification (manual step in CI-less workflow)

- [ ] **Step 1: Update PERFORMANCE.md** with leaf-only presence rule + “no full sessions/title tabs in page-shell buildWhen”.

- [ ] **Step 2: Grep gates**

```bash
# Structural builder must not use these (inspect chat_page_shell.dart by eye / rg in builder region)
rg -n "workingSessionIds|sessionWorking" client/lib/pages/chat/chat_page_shell.dart
# Live titles must not be passed into projectWorkbenchTabs from structural builder
rg -n "sessionTitles|projectWorkbenchTabs" client/lib/pages/chat/chat_page_shell.dart
# Parent sidebar must not select working / WorkspaceSidebarSessions for list shell
rg -n "workingSessionIds|WorkspaceSidebarSessions" client/lib/pages/home_workspace/workspace/workspace_sidebar.dart
```

Expect: no parent-level working / `WorkspaceSidebarSessions` select left in sidebar; shell structural path uses placeholder titles only and does not read working.

- [ ] **Step 3: Full verification**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test test/utils/session/session_rebuild_snapshots_test.dart \
                 test/pages/chat_page_rebuild_test.dart \
                 test/utils/session/workspace_running_sessions_test.dart \
                 test/utils/session/workspace_tab_session_scope_test.dart
```

Run any new sidebar/tile/chip tests added above.

- [ ] **Step 4: Commit (only if user asked)**

---

## Execution notes

- Prefer `context.select` returning the dedicated immutable snapshots (not raw `List`).
- `SessionRowContent.fromChatState`: if session missing, return empty display with sessionId (tile may shrink/hide via parent removing id).
- Do not debounce working emits.
- Keep `workspaceRunningSessions` membership rules unchanged.
