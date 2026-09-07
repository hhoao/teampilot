# Workbench Split Groups Design

Date: 2026-09-07
Status: Approved (design phase)

## Problem

The center workbench (chat / file / diff tabs) and the floating workspace
panel each render exactly one active tab at a time. `WorkspaceTabBar` holds
one `TabStrip` per surface with a single `activeId`; `WorkbenchBody`
renders one keep-alive stack for the center strip, and
`FloatingWorkspacePanel._FloatingTabBodyStack` keeps every tab mounted but
skips layout/paint for all non-active tabs. There is no way to see two tabs
side by side — e.g. one session's transcript next to another's, or a
terminal next to a file preview.

This spec introduces VSCode-style editor groups (split panes) for both the
center workbench and the floating workspace panel. Workload and backward
compatibility are explicitly out of scope as constraints: we take the
cleanest model even where it forces a breaking change to the bar state.

## Goals

- Split any tab (session / file / diff on center; terminal / run / file /
  diff / html / gitGraph / gitCompare on floating) right or down; recursive
  splits produce arbitrarily deep layouts.
- One shared state model and one shared recursive renderer for center and
  floating surfaces.
- Group-level focus with a visible highlight; all existing "active tab"
  consumers keep correct semantics without case-by-case edits.
- Split layouts persist per workspace and survive app restart.
- Graceful narrow-screen degradation: one group visible, tree preserved.

## Non-goals

- No tab duplication (sessions own live terminals; split semantics are
  *move*, never copy).
- No changes to tab-strip semantics themselves — preview / pin / landing
  behavior stays exactly as specified in
  `docs/specs/2026-09-05-floating-tab-preview-pin-design.md`, now scoped
  per group.
- No `panes`-package controller tree for the split layout (dual
  source-of-truth; rejected in the approach comparison).

## State Model

New file: `client/lib/cubits/workbench/workbench_split_layout.dart`.

```dart
sealed class SplitNode {
  const SplitNode();
}

class SplitLeaf extends SplitNode {
  final String groupId;
}

class SplitBranch extends SplitNode {
  final Axis axis;
  final SplitNode first;
  final SplitNode second;
  final double firstFraction; // 0–1; committed on drag end
}

class WorkbenchGroupLayout extends Equatable {
  final SplitNode root;                     // single leaf == today's behavior
  final Map<String, TabStrip> groups;       // groupId → strip
  final String focusedGroupId;              // always a live leaf
  final String? maximizedGroupId;           // leaf rendered full-size, tree kept
}
```

- `WorkspaceTabBar` becomes
  `{ center: WorkbenchGroupLayout, floating: WorkbenchGroupLayout }`.
- `TabStrip` and `TabStripReducer` are unchanged. Preview / pin / landing
  fields live on the strip and therefore become group-scoped automatically.
- A tab id belongs to exactly one group of one layout (global uniqueness
  invariant, enforced by the reducer).

### Reducer

New pure `SplitLayoutReducer` (mirrors `TabStripReducer` style — pure
functions returning the next layout, never mutating):

- `split(layout, {tab, direction})` — moves `tab` into a newly created
  sibling group in `direction` (right/down = new group is `second`;
  left/up = new group is `first`). The target leaf is replaced by a
  `SplitBranch`; the fresh group receives the moved tab as its active tab
  and becomes the focused group.
- `closeGroup(layout, groupId)` — removes the group's branch; the sibling
  subtree replaces the branch in its parent (tree rolling-up). Empty
  groups are also auto-pruned by `remove`.
- `moveTab(layout, {tab, targetGroupId, index})` — moves a tab between
  groups; activates it in the target and focuses the target group.
- `remove(layout, tabId)` — delegates to `TabStripReducer.remove` on the
  owning group; prunes the group when it becomes empty (invariant: no
  empty leaves).
- `focusGroup(layout, groupId)` — sets `focusedGroupId`.
- `commitResize(layout, {branchIdentity, fraction})` — clamps to a sane
  min (each side keeps a minimum extent; UI enforces pixel minimums
  during drag, reducer clamps fraction to 0.05–0.95).
- `toggleMaximize(layout, groupId)` — sets/clears `maximizedGroupId`
  (tree untouched; renderer shows only that leaf while set).
- `activate(layout, tabId)` — activates the tab in its owning group and
  focuses that group.
- `reorder / pin / unpin / promote / enterLanding` — strip-level
  operations applied to the focused (or owning) group's strip.

Invariants (asserted, tested):

1. No `SplitLeaf` whose `groupId` is missing from `groups`, and no group
   not referenced by exactly one leaf.
2. No empty group (a group's `order` is never empty after any operation).
3. `focusedGroupId` always names a live group; `maximizedGroupId` is null
   or names a live group.
4. A tab id appears in exactly one group's `order`.

Degenerate form: a single group with root = `SplitLeaf(groupId)` is
semantically identical to today's single `TabStrip`; the initial bar state
is exactly that, so a fresh workspace needs no migration.

## UX Specification

### Entry points

1. **Context menu on a tab** (right-click desktop / long-press mobile):
   "Split Right" / "Split Down" — moves the tab into a new sibling group.
2. **Tab drag** onto another group's body: an overlay drop indicator
   shows four edge half-zones (right / left / up / down) plus the center:
   - Edge zone → split in that direction, moving the dragged tab into the
     new group.
   - Center zone → move the tab into the target group (no new split).
   Dropping on the tab bar of the target group is a plain reorder-move
   into that group.
3. **Keyboard**: `Ctrl/Cmd+\` split focused group's active tab right;
   `Ctrl/Cmd+K Ctrl/Cmd+\` split down. Registered through
   `CommandCatalog` / `CommandIds` like all commands.

### Focus

- Clicking (or focusing via keyboard) anywhere inside a group focuses it.
- The focused group's tab bar carries a border highlight (VSCode-style).
- New tabs open into the focused group.
- `centerActiveId(workspaceId)` / `floatingActiveId(workspaceId)` return
   the *focused group's* active id — every existing consumer
   (`WorkspaceActiveContext`, `scopedActiveSessionId`, routing, shortcuts)
   keeps "the session the user is looking at" semantics unchanged.

### Close behavior

- A group whose last tab closes auto-prunes; the sibling subtree rolls up
   into the parent's place. The rolled-up group gains focus.
- Double-click a divider → maximize that branch / restore (renders the
   single leaf subtree full-size without discarding the tree; state keeps
   a `maximizedGroupId` on the layout for this).
- "Reset layout" action collapses the tree into a single group containing
   all tabs in stable order (fallback for users lost in a deep tree).

### Landing

Group-scoped: a group whose strip has `activeId == null` renders the
landing compose inside that group's slot. `enterLanding` acts on the
focused group. The workspace-level "new chat" CTA routes to the focused
group.

### Narrow screens

`WorkspacePanePolicy` narrow (and the floating panel below minimum split
size): only the focused group renders; the tree and fractions survive in
state and re-materialize when width returns. Split entry points are
hidden while narrow.

## Rendering Architecture

### Shared recursive renderer

`client/lib/widgets/workbench/workbench_split_layout_view.dart`:

```dart
class WorkbenchSplitLayoutView extends StatefulWidget {
  // groupBuilder renders one group: its tab bar + its body slot.
  final Widget Function(BuildContext, String groupId, TabStrip strip)
      groupBuilder;
  final WorkbenchGroupLayout layout;
  final WorkspaceTerminalHoldHandle? holdHandle; // PTY resize bracketing
  final bool splitEnabled; // false on narrow / tiny floating panel
  final ValueChanged<double>? onResizeCommit;
  ...
}
```

- Branches render `first` + divider + `second` along `axis`. The divider
  is a drag handle that brackets PTY resizes via `holdHandle` (
  `beginPtyHold` on drag start, `endPtyHold(flush: true)` on drag end) —
  the same suppression pattern the IDE shell uses for sidebar drags.
- Drag live-updates a local `ValueNotifier<double>` (no cubit emit
  mid-drag); `onResizeCommit` fires once on drag end, matching the IDE
  shell's "never commit mid-drag" write-back rule.
- Divider double-click toggles the layout's `maximizedGroupId`.
- Leaf rendering delegates entirely to `groupBuilder`.
- Drop indicator overlay for tab drags is part of this view: while a
  workbench tab drag is in progress (draggable source wraps each group's
  body), the hovered group paints the four-edge + center indicator and
  reports the chosen zone on drop (callback into the drag controller,
  which dispatches `WorkbenchCubit.splitTab` / `moveTab`).

### Center workbench

- `ChatPageShell` restructures from "one `WorkspaceShell` tab bar + one
  body" to: `WorkbenchSplitLayoutView` whose `groupBuilder` renders one
  `WorkspaceShell` (tab strip + actions) + that group's `WorkbenchBody`.
- `WorkbenchBody` gains `groupId` + the group's strip; it already renders
  by active tab — the keep-alive session stack becomes per-group
  (`KeepAliveSessionStack` unchanged, instantiated once per group). Since
  tab ownership is globally unique, each `ChatWorkbench` host is still
  mounted exactly once. A cross-group tab move remounts the host; domain
  state lives in cubits/registries so only scroll position is lost.
  Scroll anchor restore: `ChatCubit` gains a
  `Map<String, double> sessionScrollAnchors` (sessionId → scroll offset),
  written on host dispose and applied on first layout — remounts restore
  reading position.
- File / diff surfaces remount across groups the same way; the editor
  buffer lives in `EditorCubit`, so content and dirty state survive.

### Floating workspace panel

- `_FloatingTabBodyStack` is replaced by `WorkbenchSplitLayoutView` with
  a floating-specific `groupBuilder`: one `FloatingWorkspaceTabBar` + the
  group's surface bodies (still through `TpKeepAliveLayer` /
  `TpDeferredForegroundMount` keep-alive per tab, now per group).
- With a single group the panel chrome and behavior are exactly today's.
- Multi-group: the title bar's tab strip is the *focused group's* strip
  (drag/resize chrome unchanged); each group's body slot carries a
  slim header strip with its own tabs so any group is directly clickable.
- `FloatingTerminalPtyHoldScope` wires the layout view's `holdHandle`.

## Focus & Active Semantics (compatibility)

- `centerActiveId` / `floatingActiveId` = focused group's active id.
- `activate(id)` additionally focuses the owning group.
- `_owningStrip` becomes `_owningGroup`: strip lookup by presence across
  the layout's groups; center/floating routing unchanged.
- `WorkspaceActiveContext.resolve` and `chatPageStructuralSignal` read
  the focused group's active id — no signature changes.

## Persistence

New `WorkbenchLayoutSnapshotRepository`
(`client/lib/repositories/workbench_layout_snapshot_repository.dart`):

- Persists per workspace to
  `workspace/workspaces/{id}/workbench-layout.json`:
  tree (serialized nodes), per-group tab ids / active / preview / pin,
  `focusedGroupId`, `maximizedGroupId`, branch fractions.
- Written on layout-changing commits (debounced, same pattern as layout
  preferences), read when the workspace tab is restored
  (`HomeWorkspaceBodyStack` re-mount).
- Tab entities themselves (sessions, terminals, run configs) stay owned
  by their repositories; the snapshot stores layout + placement only and
  tolerates missing ids (prunes references to tabs that no longer
  resolve, falling back to a single-group layout when the file is
  corrupt or the tree fails invariants).

## Commands & Shortcuts

- `CommandIds.workbenchSplitRight`, `CommandIds.workbenchSplitDown`,
  `CommandIds.workbenchSplitReset`, `CommandIds.workbenchFocusNextGroup`
  (Tab-style cycling), `CommandIds.workbenchMoveTabToNextGroup`.
- Default bindings: `Ctrl/Cmd+\`, `Ctrl/Cmd+K Ctrl/Cmd+\`,
  `Ctrl/Cmd+K Ctrl/Cmd+T` (reset), `Ctrl/Cmd+K Ctrl/Cmd+ArrowRight`
  (focus next group). Registered in `CommandCatalog.v1`; visible in the
  keybinding settings UI like every other command.

## Error Handling & Edge Cases

- Corrupt / inconsistent snapshot → discard, single-group fallback (log
  via `AppLogger`).
- Deep trees: no hard depth cap; the reducer clamps each branch fraction
  to 0.05–0.95 and the renderer enforces per-side pixel minimums
  (reusing `LayoutPreferences`-style min-width constants; new constants
  `minSplitGroupExtent = 240` center, `180` floating).
- Drag a tab into its own group's edge zone → no-op (splitting a group
  with itself is rejected by the reducer).
- Splitting the last tab out of a group: source group would become
  empty → reducer moves the split boundary instead (the source leaf is
  replaced by the branch, moved tab forms the new sibling, remaining tabs
  stay in the source group; only when exactly one tab remains does the
  source group end up empty → the split then behaves as a plain move into
  a fresh group).
- `closeAll` / `closeOthers` / `closeRight` act on the owning group's
  strip (closeAll keeps pinned tabs of *that group* only).
- Workspace removal clears its snapshot with the rest of the workspace
  dir (existing lifecycle).

## Testing

- `SplitLayoutReducer` unit tests: every operation + all four invariants
  + edge cases above (split-last-tab, self-split rejection, prune chains,
  fraction clamping).
- `WorkbenchCubit` tests: new API (`splitTab`, `moveTab`, `focusGroup`,
  `commitResize`, group-aware `activate`/`close`/`pin`/`enterLanding`),
  interaction with `WorkbenchDomainPort.onTabRemoved`, degenerate
  single-group equivalence with today's behavior.
- `WorkbenchSplitLayoutView` widget tests: recursive layout correctness,
  drag-bracket calls to the hold handle, drop-indicator zones, divider
  double-click maximize, `splitEnabled: false` fallback, resize commit
  (not mid-drag).
- `ChatPageShell` / `FloatingWorkspacePanel` integration tests: two
  groups side by side, focus highlight, cross-group move (scroll anchor
  restore), landing per group, narrow degradation.
- Snapshot repository tests: round-trip, prune of unresolved tab ids,
  corrupt-file fallback.
- All tests through `dart run tool/run_tests.dart` (never raw
  `flutter test`).

## Components & Files

| Change | File |
|--------|------|
| New split node / layout / reducer | `client/lib/cubits/workbench/workbench_split_layout.dart` |
| Bar state re-shape | `client/lib/cubits/workbench/workbench_tab_bar.dart` |
| Group-aware cubit API | `client/lib/cubits/workbench/workbench_cubit.dart` |
| Shared recursive renderer + drop overlay | `client/lib/widgets/workbench/workbench_split_layout_view.dart` |
| Center per-group shell | `client/lib/pages/chat/chat_page_shell.dart`, `pages/workbench/workbench_body.dart` |
| Floating per-group body | `client/lib/pages/floating_workspace/floating_workspace_panel.dart` |
| Scroll anchor cache | `client/lib/cubits/chat_cubit.dart` (+ `ChatWorkbench` apply) |
| Snapshot persistence | `client/lib/repositories/workbench_layout_snapshot_repository.dart` |
| Commands / bindings | `client/lib/services/commands/command_ids.dart`, `command_catalog.dart` |
| l10n | `client/lib/l10n/app_en.arb`, `app_zh.arb` |
