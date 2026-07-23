# Session working-state rebuild isolation

## Goal

Stop the first Session message (and later agent-turn `workingSessionIds` flips) from freezing the UI for multi-second spans caused by bulk `Text` → `RenderParagraph` layout.

High-frequency session presence (`working` / waiting / attention) must only rebuild **leaf chrome** that displays that presence — never the conversation list shell, worktree group headers, file tree, compose field, or terminal subtree.

## Evidence (2026-07-24)

DevTools export `test76.json` (debug build):

| Signal | Value |
|--------|-------|
| Worst frame | `#9326` ≈ **6113 ms** (build 6050, raster 14) |
| BUILD marker | ≈ **133 ms** |
| Leaf cost aligned to wall clock | **`RenderParagraph` ≈ 6807 ms** |
| Rebuilds on that frame | worktree group headers + sidebar session tiles + `TpIconButton` Ink |
| Trigger | `ChatCubit.workingSessionIds` change on first send |

Parent Ink / Flex totals in the analyzer (tens of seconds) are nested/span artifacts and must not be read as additive wall time. The user-visible stall is text layout after a too-wide rebuild.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Scope | Sidebar **and** `ChatPageShell` / workbench **tab row** — unify the subscription boundary |
| Classification | **Structure** vs **row content** vs **ephemeral presence** |
| Working / waiting | Leaf-only: session tile spinner/hand, Running strip membership, **per-tab chip** working flag |
| List structure | Ordered session ids **after the active sidebar sort** (selector may read timestamps to compute order) |
| Row title / time | Painted only from live `SessionRowContent` `context.select` — never from a stale `widget.session` `Text` source |
| `touchSession` UX | Relative time on that row updates via row-content select. Under `AppSessionSort.recentlyUpdated`, list host **may** rebuild to reorder; sibling **titles** still come from per-tile selects (no forced title relayout of unchanged rows beyond list reorder). Under sorts that ignore `updatedAt`, list host stays put |
| `ChatWorkbenchSlice` | Structural workbench projection; **must not** be invalidated by working alone |
| `ChatScopedTabView` | **Remove** `workingSessionIds` from the type entirely. Working is not part of shell view `==` |
| `ChatPageShell` structural `buildWhen` | Compare **tab structure only**: open tab ids + order, active index, newChat, connecting id, launchError, pinned-for-open-tabs, and **`selectedMemberId`** (member switch is structural for the workbench body). **Exclude** `workingSessionIds`, full `sessions` equality, title-bearing `ChatTabInfo` / `display` / `updatedAt`, and bare `stateVersion` bumps that only exist to force broad rebuilds. If `stateVersion` remains in the codebase for other reasons, structural `buildWhen` must not treat it as sufficient alone |
| Tab working + title inject | Structural builder projects tabs with `working: false` and a **placeholder title** (e.g. empty or `sessionId`). `WorkspaceShellTabChip` (or thin wrapper **only around the tab row**) live-selects: (1) `workingSessionIds.contains(id)` and (2) display/title from `SessionRowContent` / open-tab title map. **Do not** re-call `projectWorkbenchTabs` in a parent that also owns terminal / file-tree |
| Running host | Always mounted; empty → `SizedBox.shrink()` / zero height — parent never selects working to toggle children |
| Attention | Parents must not `select` `AgentAttentionCubit` for list membership; tile already selects waiting; read-on-action (e.g. delete busy check) is fine |
| Debug vs profile | Fix rebuild fan-out. Absolute ms lower in profile; do not “fix” by suppressing Text in debug only |

## Non-goals

- Replacing `Text` with custom painters / caching paragraph layouts as the primary fix
- Debouncing or delaying `workingSessionIds` emits
- Reworking `TpIconButton` Ink as the main lever (secondary only if leaf rebuilds remain hot)
- Changing Running-strip product rules (`workspaceRunningSessions` membership)
- Splitting ChatCubit into multiple cubits

## Problem (architecture)

Today two places re-subscribe the **whole surface** to ephemeral working:

1. **`WorkspaceSidebar`** — `context.select` builds `runningSessionIds` from `workingSessionIds`, so any working flip rebuilds the entire sidebar Column (conversation section headers, all group `Text`s, chrome `TpIconButton`s).
2. **`ChatPageShell._scopedTabBuildWhen`** — includes `workingSessionIds`, and also full `sessions` / `tabs` equality, so rename / `touchSession` / working can rebuild the workbench shell (and nested file-tree `Text`s).

This contradicts `ChatWorkbenchSlice`, which already documents that working must not rebuild the terminal subtree.

`SidebarSessionTile` already selects per-row `working` / `selected` — the fan-out is the **parent** shells.

`WorkspaceSidebarSessions` equality includes `display` and `updatedAt`, conflating structure and row content.

Even after dropping only `workingSessionIds` from `buildWhen`, structural builder today still reads `view.workingSessionIds` → `sessionWorking` → `projectWorkbenchTabs` — that read must move out of the structural builder.

## Design

### State classes (value snapshots)

New immutable types under `client/lib/utils/session/` (names flexible; pattern must match `WorkspaceSidebarSessions`):

| Type | `==` fields | Consumers |
|------|-------------|-----------|
| `SessionListStructure` | **Ordered** list of `{sessionId, pinned, sortOrder}` **in the post-sort order for the active `AppSessionSort`** | `ConversationListHost` / worktree grouping |
| `SessionRowContent` | `sessionId`, `display`, `updatedAt`, `createdAt` (tile uses `updatedAt` with `createdAt` fallback for relative time) | `SidebarSessionTile` painted title + time |
| `RunningSessionIds` | Order-sensitive `List<String>` with deep `==` / `hashCode` on a dedicated `@immutable` class — **not** a raw `List` return from `select` | `RunningSessionsHost` only |

`WorkspaceSidebarSessions`: replace call sites with the split types rather than expanding its equality further.

List keys remain `sessionId`. Group sections receive **ordered session ids** (or structure rows), not content-bearing `AppSession` for UI text.

### Sidebar widget tree

```
WorkspaceSidebar
├─ Automations / New chat / chrome (sort, search, worktree actions)
│    ← no working / attention selects
├─ RunningSessionsHost                ← select RunningSessionIds only
│    └─ SidebarSessionTile(sessionId) ← select SessionRowContent + working + selected + waiting
└─ ConversationListHost               ← select SessionListStructure (+ WorktreeCubit view)
     └─ WorktreeGroupSection(ordered ids)
          └─ SidebarSessionTile(sessionId) ← same leaf selects
```

### Chat / workbench widget tree

```
ChatPageShell
└─ BlocBuilder (structural buildWhen — see Locked decisions)
     └─ projects TabInfo with working: false + placeholder title
          └─ WorkspaceShell
               ├─ Tab row / WorkspaceShellTabChip
               │    ← per-tab select workingSessionIds.contains(id)
               │    ← per-tab select SessionRowContent.display (or tab title map)
               │    ← ONLY this subtree rebuilds on working / rename
               └─ body (file tree / terminal / compose)
                    ← must NOT rebuild on working-only or rename-only emits
```

Grep gate: `chat_page_shell.dart` structural builder must not reference `workingSessionIds`, `view.workingSessionIds`, or `sessionWorking`, and must not pass live session titles into `projectWorkbenchTabs` (placeholder only).

### ChatScopedTabView

**Remove** `workingSessionIds` from the type and from `==` / `hashCode`. Call sites that need working use a dedicated select or read inside tab chips.

### Leaf tile contract

`SidebarSessionTile`:

- Construct with `sessionId` (+ reorder index / highlight override / callbacks).
- Optional `AppSession` ctor arg, if kept, is for actions / ids only — **never** the `Text` source.
- Painted title and relative time **always** from `SessionRowContent` via `context.select` reading live cubit state during `build`.
- Keep `working` / `waiting` / `selected` as local `context.select`.
- Acceptance: first frame after mount, with the session already in `ChatState.sessions`, shows the correct title (no empty → fill flash).

### Conventions (docs)

Update `docs/PERFORMANCE.md` Known hotspots / checklist:

> High-frequency session presence (`workingSessionIds`, attention waiting) may only be selected in leaf widgets that render that presence. List shells select structure snapshots only. Row text fields select row-content snapshots. Do not add `workingSessionIds` to page-shell `buildWhen`. Do not put full `sessions` or title-bearing tab snapshots in page-shell `buildWhen`.

## UX acceptance

| Action | Expected UI | Expected rebuild scope |
|--------|-------------|------------------------|
| First message | Spinner on that row; session enters Running strip; tab chip working if tab open | Running host + that tile + tab chip(s). **Not** group headers’ forced title layout; **not** file tree / terminal / compose |
| Later turns (working on/off) | Same | Same |
| First-prompt auto-rename | Sidebar row title + open workbench tab chip title update | That tile’s + tab chip’s `SessionRowContent` selects; structural shell `buildWhen` / body builder do **not** fire from title alone |
| `touchSession` under `recentlyUpdated` | Relative time updates; row may move in list | That tile row-content; `ConversationListHost` may rebuild for **reorder only** |
| `touchSession` under sorts ignoring `updatedAt` | Relative time updates | That tile only |
| Open/close live PTY tab | Running strip membership | Running host |
| Working-only emit | Tab chip spinner may update | Structural `WorkspaceShell` **body** builder count unchanged |

## Testing

### Unit

- Snapshot equality: working-only state change → `SessionListStructure` `==`; `SessionRowContent` `==` unless display/updatedAt/createdAt change; `RunningSessionIds` `!=` when working adds the session.
- `createdAt`-only change invalidates `SessionRowContent` when it would change painted relative time inputs.
- `workspaceRunningSessions` existing tests remain source of truth for membership rules.

### Widget / shell (rebuild probes)

**Ban** outer-parent probes as acceptance evidence (e.g. wrapping outside `ChatPageShell` — see current `chat_page_rebuild_test.dart` pattern, which must be fixed/replaced).

Use keyed `StatefulWidget` build counters **inside**:

| Probe location | working-only emit | rename-only emit |
|----------------|-------------------|------------------|
| Structural `ChatPageShell` / `WorkspaceShell` body builder | unchanged | unchanged |
| `ConversationListHost` / group header | unchanged | unchanged (unless sort/structure) |
| `RunningSessionsHost` | +1 when membership changes | unchanged |
| Target `SidebarSessionTile` | +1 (working select) | +1 (row content) |
| Sibling tile / group header title | unchanged | unchanged |
| Tab chip working select | +1 | unchanged |
| Tab chip title select | unchanged | +1 |

Prefer these counters over `debugProfileBuildsEnabled`.

### Manual / perf

- Re-capture first-send (prefer **profile** for absolute ms; debug OK for fan-out).
- `analyze_performance_json.dart --format summary`: no multi-second frame dominated by sidebar `RenderParagraph` on working flip alone.

## File touch map

| Area | Paths |
|------|--------|
| Snapshots | `client/lib/utils/session/session_list_structure.dart`, `session_row_content.dart`, `running_session_ids.dart` |
| Running / list hosts | `workspace_sidebar.dart`, `worktree_group_section.dart` |
| Tile | `sidebar_session_tile.dart` |
| Shell / tabs | `chat_page_shell.dart`, `chat_scoped_tab_view.dart`, `workbench_tab_projection.dart`, `workspace_shell_tabs.dart` (or tab chip file) |
| Docs | `docs/PERFORMANCE.md` |
| Tests | `client/test/utils/session/…`, fix/replace `chat_page_rebuild_test.dart`, sidebar widget tests |

## Risks

| Risk | Mitigation |
|------|------------|
| First-frame empty title | Title/`Text` only from live `SessionRowContent` select |
| Running strip flicker | Always-mounted host |
| Working still in structural builder | Grep gate + probe table |
| Rename + working same emit | Structure `==` if order unchanged; row content + running + chip update — still far cheaper than full sidebar Text layout |
| `recentlyUpdated` reorder vs “tile only” | Spec explicitly allows list-host reorder rebuild; not a regression vs today |
