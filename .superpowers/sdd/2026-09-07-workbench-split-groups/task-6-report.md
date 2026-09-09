# Task 6 Report: Floating panel split groups + split commands/shortcuts + l10n

Branch `worktree-workbench-split-groups`, on top of Task 5 (`0c6c8a81e`).

## What was built

### 1. Floating panel split layout (`floating_workspace_panel.dart`)

- The panel projection (`_FloatingPanelView`) now carries the whole floating
  `WorkbenchGroupLayout` (Equatable-deduped) instead of a merged `TabStrip`;
  whole-surface consumers (empty-launcher visibility, minimized keep-alive)
  derive "has tabs" from the layout's groups.
- The title-bar strip's data source is the **focused group's strip**
  (`_focusedFloatingStrip`), projected through `resolveFloatingTabForId` via
  the new `projectFloatingStrip` helper. With a single group this is exactly
  today's panel (merged strip == focused strip); with multiple groups the
  title bar keeps showing the focused group's tabs (controller ruling 1 wins
  over the brief's "title bar strip is hidden" wording).
- The body slot (`_FloatingPanelBodySlot`) now hosts `WorkbenchSplitLayoutView`
  with:
  - `holdHandle`: the panel's existing `_terminalHold` (reuses the
    `FloatingTerminalPtyHoldScope` already in the panel — ruling 7);
  - `splitEnabled`: `floatingPanelSplitEnabled(panelRect.size)` — panel width
    **and** height each >= `2 * 180 + 1` (divider allowance); `false` renders
    the focused group only (ruling 6; `kFloatingMinGroupExtent = 180`);
  - `minGroupExtent: kFloatingMinGroupExtent` (180);
  - `onResizeCommit` → `commitSplitResize(..., floating: true)`;
  - `onGroupFocused` → `focusGroup(..., floating: true)`;
  - `onDividerDoubleTap` → `toggleMaximizeGroup` reading the focused group
    **inside** the callback (no stale closure — mirrors `chat_page_shell.dart`);
  - `groupBuilder` → `FloatingGroupHost` keyed `floating_group_host_$groupId`,
    focused = focused-or-maximized group (mirrors the center).
- A `WorkbenchTabDragHost` wraps the whole `_PanelChromeFrame` (inside the PTY
  hold scope) so **both** the title-bar strip and the per-group slim headers
  can host drag sources while group bodies register drop regions.
- Empty launcher and minimized keep-alive behavior unchanged (regression tests
  still pass; new empty-state assertion added).
- The title-bar strip gained split menu entries ("Split Right/Down") whenever
  `splitEnabled && focused strip has > 1 tabs`, and chip drag sources
  (`FloatingTabStripDrag`, source = focused group). This is the only UI entry
  point that can create the *first* floating split (tab drags onto the tab's
  own group are rejected by `dispatchSplitDrop`, and the keyboard commands act
  on the center layout per ruling 3) — noted as a deliberate deviation from
  the literal "single group is exactly today's chrome" wording of ruling 1,
  which would otherwise make the feature unreachable.
  Title-bar pin/unpin/bulk-close callbacks keep their whole-surface reads
  (`mergedFloatingStrip`); reorder mutates the focused group, which is exactly
  the strip the title bar shows.

### 2. `FloatingGroupHost` (new `floating_group_host.dart`)

- Slim per-group header (34px): that group's own `FloatingWorkspaceTabBar`
  instance (compact strip, no "+" button) re-instantiated from the group's
  strip projected through `resolveFloatingTabForId` (`projectFloatingStrip`).
  Pin/unpin/double-tap read **this group's** strip preview/pin state; bulk
  closes go through the whole-surface close pipeline; reorder focuses the
  group first (`reorderFloating` mutates the focused group); split entries
  and chip drags only while `splitEnabled && strip.order.length > 1`.
- Body: the group's tab bodies with the existing keep-alive pattern
  (`TpKeepAliveLayer` + `TpDeferredForegroundMount` per tab, keyed by tab id)
  — `_FloatingTabBodyStack` moved here unchanged in semantics, one stack per
  group (a tab lives in exactly one group).
- `WorkbenchTabDropRegions(groupId, ...)` wraps the body only (headers stay
  outside — Task 4 ruling); drops dispatch through `dispatchSplitDrop(...,
  floating: true)`.
- `SplitGroupFocusFrame(focused: ...)` mirrors the center group host.
- Header is shown only while the layout hosts more than one group.

### 3. `FloatingWorkspaceTabBar` extension

- Optional `onSplitRight` / `onSplitDown` (`ValueChanged<String>` chip tab id)
  wired into the chip context menus via `WorkbenchStripTabChip` (entries
  omitted when null — `SplitTabMenuSource` behavior).
- Optional `tabDrag: FloatingTabStripDrag` (`sourceGroupId`, `resolveTabId`,
  `onDrop`) wrapping every chip in `WorkbenchTabDraggable`.

### 4. Split commands

- `command_ids.dart`: `workbenchSplitRight` / `workbenchSplitDown` /
  `workbenchSplitReset` / `workbenchFocusNextGroup` /
  `workbenchMoveTabToNextGroup`.
- `command_catalog.dart` (category `tabs`, `when: hasWorkspace`,
  `terminalPassthrough: true`):
  - `workbenchSplitRight` → `Mod+\` (Ctrl/Cmd+\);
  - `workbenchSplitDown` → `Mod+Alt+\` — **documented deviation**: `KeyChord`
    supports only single `SingleActivator`s + double-tap Shift (no chord
    sequences), so the planned `Ctrl/Cmd+K → Ctrl/Cmd+\` two-step is not
    expressible; the plan pre-authorized `Ctrl/Cmd+Alt+\`;
  - `workbenchSplitReset` → `Mod+Ctrl+T`;
  - `workbenchFocusNextGroup` → `Mod+Alt+F` (Cmd/Ctrl+Alt+Right is taken by
    `workspaceNextTab`);
  - `workbenchMoveTabToNextGroup` → shipped unbound (no plan default; surfaced
    via the cheatsheet / rebind UI).
- `key_chord.dart`: added `'\\'` ↔ `LogicalKeyboardKey.backslash` mapping in
  both `logicalKeyForChordKey` and `chordKeyForLogicalKey` (the backslash key
  was previously unsupported and would throw on activation).
- New `split_command_registrar.dart` — `registerSplitCommands(bus, chat,
  workbench)`:
  - splitRight/Down act on the **center layout's** focused-group active tab in
    the active workspace (`chat.tabStore.activeWorkspaceId`; empty → no-op,
    active tab null → no-op);
  - reset → `collapseSplitLayout` on **both** center and floating layouts of
    the active workspace;
  - focusNextGroup cycles `focusedGroupId` through `centerLayout.leafGroupIds`
    (wraps; no-op with a single group);
  - moveTabToNextGroup moves the focused center group's active tab to the next
    leaf group (wraps).
- Wired in `app_shell.dart` right after `registerSessionCommands`.

### 5. l10n

New keys in **both** `app_en.arb` and `app_zh.arb` (ruling 4; the
`tabMenuSplitRight` / `tabMenuSplitDown` keys already existed from Task 5 and
were not re-added):

| key | en | zh |
|-----|----|----|
| `shortcutsWorkbenchSplitRight` | Split Editor Right | 向右拆分编辑组 |
| `shortcutsWorkbenchSplitDown` | Split Editor Down | 向下拆分编辑组 |
| `shortcutsWorkbenchSplitReset` | Reset Editor Layout | 重置编辑组布局 |
| `shortcutsWorkbenchFocusNextGroup` | Focus Next Editor Group | 聚焦下一个编辑组 |
| `shortcutsWorkbenchMoveTabToNextGroup` | Move Tab to Next Editor Group | 将标签页移到下一个编辑组 |

`command_l10n.dart` `_titleForKey` gained the five mappings; generated
`app_localizations*.dart` refreshed via `flutter gen-l10n`.

## Files touched

Modified:
- `client/lib/app/app_shell.dart` (register split commands + import)
- `client/lib/cubits/…` — none
- `client/lib/l10n/app_en.arb`, `app_zh.arb`, generated `app_localizations*.dart`
- `client/lib/pages/floating_workspace/floating_workspace_panel.dart`
- `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart`
- `client/lib/services/commands/command_catalog.dart`, `command_ids.dart`,
  `command_l10n.dart`, `key_chord.dart`
- `client/test/services/commands/command_catalog_test.dart` (new default-chord
  assertions)
- `client/test/services/commands/key_chord_test.dart` (backslash round-trip)
- `client/test/services/floating_workspace/close_pinned_test.dart`
  (ruling 9: whole-surface assertions switched from `floatingOrder` to
  `mergedFloatingStrip().order`; the pinned-survivor behavior those tests pin
  is whole-surface — the tests never split the floating layout, so values are
  unchanged, only the read is aligned)

Created:
- `client/lib/pages/floating_workspace/floating_group_host.dart`
- `client/lib/services/commands/split_command_registrar.dart`
- `client/test/pages/floating_workspace/floating_split_test.dart`
- `client/test/services/commands/split_command_registrar_test.dart`

## Test list

`client/test/pages/floating_workspace/floating_split_test.dart`:
- `floatingPanelSplitEnabled` threshold math (both axes must fit 2×180+1)
- splitTab (floating) renders two group hosts + divider; title bar shows the
  focused group's strip; single group renders exactly today's panel
- narrow panel renders the focused group only (layout still multi-group)
- title-bar "Split Down" context-menu entry splits the focused group vertically
- mouse drag of a group-header chip onto another group's body center moves the
  tab (`dispatchSplitDrop`, `floating: true`)
- empty launcher still renders with no tabs

`client/test/services/commands/split_command_registrar_test.dart`:
- splitRight / splitDown act on the focused center group active tab
- silent no-ops without an active workspace and on a sole-tab group
- reset collapses both center and floating layouts
- focusNextGroup cycles and no-ops on a single group
- moveTabToNextGroup moves + activates the focused group's active tab

## Commands run

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` — no
  errors in touched files (pre-existing baseline warnings unchanged).
- `cd client && flutter gen-l10n`
- `cd client && dart run tool/run_tests.dart test/pages/floating_workspace/` — 38 passed
- `cd client && dart run tool/run_tests.dart test/services/commands/` — 95 passed
- `cd client && dart run tool/run_tests.dart test/services/floating_workspace/` — 23 passed
- `cd client && dart run tool/run_tests.dart test/widgets/workbench/ test/cubits/workbench/ test/cubits/floating_workspace/` — 169 passed
- `cd client && dart run tool/run_tests.dart` (full suite) — see below

## Notes / deviations

1. **splitDown binding**: `Ctrl/Cmd+Alt+\` instead of the planned chord
   sequence — `KeyChord` has no sequence support (pre-authorized deviation).
2. **Title bar with multiple groups**: kept visible showing the focused
   group's strip per controller ruling 1 (overriding the brief's "hidden"
   wording).
3. **Title-bar split menu entries**: offered even with a single group (gated
   on splitEnabled + multi-tab); otherwise the first floating split would be
   unreachable from the UI (tab drags onto the tab's own group are rejected,
   and keyboard split commands act on the center layout).
4. **close_pinned_test.dart** (ruling 9): assertions switched from
   `floatingOrder` (focused-group read) to `mergedFloatingStrip().order`
   (whole-surface read) to match the whole-surface semantics the bulk-close
   pipeline uses; the tests never split, so the pinned values are identical.
5. Known pre-existing baseline failures (not touched): workspace_shell_sidebar_toggle_test,
   opencode config_profile suite, run/launch_adapter_client suite.
