# Floating Tab Preview / Pin Design

Date: 2026-09-05
Status: Approved (design phase)

## Problem

The floating workspace tab strip has no preview concept: every file/diff
preview opened on the floating strip appends a new pinned tab. The center
strip already has a single replaceable preview slot
(`TabStrip.previewIds` + `TabStripReducer.add(preview: true)`), but
`WorkbenchCubit.openFloating` hard-codes `preview: false` and
`Workbench.pin` only routes to the center strip, so the machinery never
engages for floating tabs.

Users want VSCode-style behavior on the floating strip: transient
previews share one replaceable slot; editing a preview makes it
permanent; an explicit pin protects tabs from accidental close.

## State Model

`TabStrip` gains a `pinnedIds` set next to `previewIds`. A tab on either
strip (center or floating) is in exactly one of three states:

| State    | Replaceable by a new preview? | Close protection | Entered by |
|----------|-------------------------------|------------------|------------|
| preview  | yes (in-place slot swap)      | none             | opening a file/diff preview while `floatingPreviewTabs` is on |
| normal   | no                            | none             | preview promoted (dirty edit / re-open / explicit); preview opened while config off |
| pinned   | no                            | full             | context-menu "pin" / double-tap on a normal tab |

Transitions:

```
preview ──(dirty edit | re-open same tab | double-tap)──▶ normal
normal  ──(context-menu pin | double-tap)───────────────▶ pinned
pinned  ──(pin icon tap | context-menu unpin | double-tap)─▶ normal
```

- **Dirty edit promotes, not pins** (VSCode behavior): the listener in
  `file_editor_surface.dart` that currently calls `WorkbenchCubit.pin`
  calls the promote path instead. Works for both strips because strip
  routing is by presence.
- **Re-open of an existing preview tab** removes it from `previewIds`
  (existing reducer behavior; floating tabs now participate).
- Pin/unpin is a toggle between normal ↔ pinned only.

## Scope

Participating surfaces (config-gated): `filePreview`, `diffPreview`.
`htmlPreview`, `gitGraph`, `gitCompare`, `terminal`, `run` are always
normal tabs — behavior unchanged.

## Components & Changes

### 1. `client/lib/cubits/workbench/tab_strip.dart`

- Add `pinnedIds` to `TabStrip` (props, copyWith).
- Reducer:
  - `add`: existing preview-slot replace logic unchanged; also clean
    `pinnedIds` on removal paths.
  - `remove`: drop id from `pinnedIds`.
  - `promote(strip, id)`: move id from `previewIds` to neither-set
    (normal). No-op when absent or already normal.
  - `pin(strip, id)` / `unpin(strip, id)`: toggle membership in
    `pinnedIds`. No-op for preview-state tabs (pin only applies to
    normal).

### 2. `client/lib/cubits/workbench/workbench_cubit.dart`

- `openFloating(workspaceId, tab, {preview = false, activate})`:
  forward `preview` to `_r.add`; return the replaced tab id (same shape
  as `_openCenter`) so callers can run domain teardown.
- `pin` / new `unpin` / new `promote`: route through `_owningStrip`
  (presence wins) so both strips are supported. Center-strip callers
  keep working unchanged.
- `closeOthers` / `closeRight` / `closeAll` (center) and the floating
  close helpers skip tabs in `pinnedIds`.

### 3. `client/lib/services/workbench/workbench_editor_opener.dart`

- Floating branch of `openFile`/`openDiff` passes `preview:` through to
  `openFloating` (gated by the new preference).
- Before a replace would hit a dirty preview tab: promote it first, then
  open the new preview as a normal appended tab (never force-close a
  dirty file). Double-guard: if the reducer still reports a replaced
  tab that was dirty, treat it as no-replace.
- Replaced-tab teardown mirrors `_closeReplaced` for floating
  file/diff tabs (editor bucket close).

### 4. Close pipeline — `client/lib/services/floating_workspace/close_floating_tab.dart`

- `closeOtherFloatingTabs` / `closeFloatingTabsToTheRight` /
  `closeAllFloatingTabs` skip pinned ids (full protection — a pinned tab
  survives even "close all"; the user must unpin first).
- Single-tab close by the user: the chip shows a pin icon instead of
  the close X for pinned tabs (see UI), so there is no close affordance
  while pinned.

### 5. UI

- `client/packages/shared_ui` `TpTabChip`: add optional `onDoubleTap`.
  Pinned rendering (pin icon in place of close X) lands in
  `WorkbenchStripTabChip`, not shared_ui.
- `client/lib/pages/workspace_shell/workspace_shell_tabs.dart`
  (`WorkbenchStripTabChip`): add `pinned`-aware trailing — pinned shows
  `push_pin_rounded` (hover: rotated) whose tap is unpin; add
  `onDoubleTap` wiring; context menu gains a "pin/unpin tab" entry
  (l10n en/zh).
- `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart`
  + `floating_workspace_panel.dart`: panel projects
  `bar.floating.previewIds`/`pinnedIds` and passes them plus
  `onPin`/`onUnpin` into the tab bar (same parameter-injection pattern
  as `tabs`/`activeTabId`/`onSelect` today).
- Double-tap semantics: preview tab → promote to normal; normal/pinned
  tab → toggle pinned.
- Session tabs' existing pinned state (chat-domain `sessionPinned` map
  passed into the center-strip projection) **migrates** onto
  `TabStrip.pinnedIds`: the chat-domain map is deleted and
  `workbench_tab_projection.dart` reads the strip instead. This unifies
  the three-state model across both strips.

### 6. Config

- `client/lib/models/layout_preferences.dart`: `bool
  floatingPreviewTabs` (default `true`), serialized in layout prefs
  JSON.
- `/config` layout settings: toggle next to `filePreviewHost`, l10n in
  `app_en.arb` / `app_zh.arb`.

## Persistence

None. Floating strip state (order/active/preview/pinned) is rebuilt by
reconcilers after restart — same as today. Preview/pin state resets on
restart by design.

## Error Handling / Edge Cases

- Dirty preview tab (should not happen — dirty promotes immediately):
  opener double-checks before replacing; dirty tab is promoted instead
  and the new preview appends.
- Programmatic removal (run session ends, file deleted) ignores
  `pinnedIds` — pin protects against user close actions only.
- `canClose` dirty-file confirmation still applies when a promoted
  (normal) file tab is closed.

## Testing

- `client/test/cubits/workbench/tab_strip_test.dart`: preview-slot add /
  replace / promote / pin / unpin / remove-cleans-pinnedIds.
- `client/test/cubits/workbench/workbench_cubit_test.dart`:
  `openFloating(preview:)`, replaced-id return, pin/unpin routing both
  strips, closeOthers/closeRight/closeAll skip pinned.
- `client/test/services/workbench/` opener tests: dirty-promotes-not-
  replaces, config on/off branches, replaced-tab teardown.
- Floating close pipeline tests: pinned survives closeAll.
- Widget tests: pin icon tap unpin, double-tap toggles state, preview
  italic styling.
