# File Tree Blank-Area Context Menu — Design

Date: 2026-08-14
Status: Approved
Author: hhoa

## Problem

Right-clicking the blank area of the file-tree panel (below the last row, or on
the `(empty)` placeholder) does nothing. VSCode's explorer opens a context menu
there with new-file / new-folder / paste / refresh / collapse-all etc., with
actions targeting the root folder under the pointer. TeamPilot should behave the
same way.

Existing state: row right-click is already wired — `FileTreeNode`'s
`onSecondaryTapDown` calls `FileTreeContextMenu.show` (file_tree_node.dart:194)
with New File / New Folder / Cut / Copy / Paste / Rename / Delete / Copy Path /
Open in Terminal etc. The blank area only hosts drop-target logic
(`FileTreeDropRegion`), no secondary-tap handling.

## Design

### 1. `client/lib/widgets/file_tree/file_tree_context_menu.dart`

Add a blank-area entry point to `FileTreeContextMenu`:

```
static Future<void> showForBlankArea({
  required BuildContext context,
  required TapDownDetails tapDetails,
  required FileTreeCubit cubit,
  required String targetRootDir,
  required String workspaceId,
  required bool desktopShellActions,
  required RuntimeContext workContext,
})
```

Menu spec (trimmed, VSCode-style):

- 新建文件 — `cubit.createFile(targetRootDir, name)` via existing `_promptCreate`
- 新建文件夹 — `cubit.createFolder(targetRootDir, name)` via existing `_promptCreate`
- divider
- 粘贴 — enabled only when `cubit.state.clipboard != null`; `cubit.pasteInto(targetRootDir)` via existing `_runOp`
- divider
- 刷新 — `cubit.refresh()`
- 全部折叠 — `cubit.collapseAllFolders()`
- 显示/隐藏隐藏文件 — `cubit.toggleShowHidden()`
- 在终端打开 — only when `desktopShellActions`; `FilePathActions.openInTerminal(targetRootDir, isDirectory: true)`, failure toast via existing pattern

All helpers (`_promptCreate`, `_runOp`, error mapping) are reused unchanged.

### 2. `client/lib/widgets/right_tools/file_tree_panel.dart`

Wrap the list area (`FileTreeDropRegion`'s child / `_FileTreeList`) with a
`GestureDetector(onSecondaryTapDown:)`:

- When a row owns the secondary tap, the row's `TpHover` recognizer wins the
  gesture arena and the blank-area handler never fires — no hit-testing on rows
  needed.
- When it does fire: resolve the target root with the same math as
  `_FileTreeDropRegionState._hitAt` (`contentY = localY + scrollOffset` →
  `resolveFileTreePanelDropHit`), which already returns the containing root for
  empty areas (single root → the only root; multi-root → the root band under the
  pointer via `resolveNearestRootDest`). Pass `hit.destDir` as `targetRootDir`.
- If `cubit.state.anyRootExists == false`, show nothing.
- `desktopShellActions` reuses existing `_desktopShellActionsFor(_workContext)`.

### Interaction (VSCode-aligned)

- Right-click on a row → row menu (unchanged).
- Right-click on the `(empty)` placeholder or blank space below the last row →
  blank-area menu targeting the root the pointer is in.
- Multi-root: actions target the root band under the pointer. Single root: the
  only root.
- No roots (root path unavailable): no menu.

### Error handling

Create / paste / terminal-open failures reuse `_runOp`'s
`FileTreeOperationException` → localized toast mapping, identical to row menus.

### Tests

- Widget test: blank-area right-click opens the blank-area menu (single root).
- Paste item disabled when clipboard is null.
- `(empty)` placeholder row right-click opens the menu (targeting its root).
- Multi-root: right-click in a root band targets that root's dir.
- Right-click on a regular row still opens the row menu (no blank menu).

## Non-goals

- No changes to row context menu behavior.
- No new dependencies.
- No changes to drag & drop behavior in the blank area.
