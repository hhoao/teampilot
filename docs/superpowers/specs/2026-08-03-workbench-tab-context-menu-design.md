# Workbench tab context menu (multi-source)

**Date:** 2026-08-03  
**Status:** Approved for planning  
**Scope:** Extensible workbench tab right-click menus composed from ordered sources with dividers between groups; v1 file-path actions on center strip + floating strip; extract shared file-path actions for file tree reuse.

## Problem

Workbench tabs (`WorkbenchStripTabChip`) already show a context menu, but items are hard-coded close/pin actions. There is no way for tab kinds (file, session, diff, run, …) to contribute their own actions. File-path operations (copy path, reveal in file manager, open in terminal, open with system app) exist only on the file-tree row menu (`FileTreeContextMenu`), not on file/diff tabs. Call sites (center strip vs floating strip) would otherwise fork menu logic.

## Goals

1. **Multi-source menus:** Tab context menus are assembled from an ordered list of `WorkbenchTabMenuSource`s.
2. **Group separators:** Composer inserts one divider between adjacent non-empty source groups; empty groups are skipped (no double dividers, no leading/trailing divider).
3. **Built-in close group:** Pin (when pinnable) + Close / Close Others / Close Right is a first-class source that is **always last**.
4. **Type actions above close:** Kind-specific groups appear above the built-in close group (VS Code–style).
5. **File actions v1:** File (and diff-with-path) tabs get: Copy Path, Copy Relative Path, Reveal in File Manager, Open in Terminal, Open with System App — gated by the same capability flags as the file tree.
6. **Shared path actions:** Extract `FilePathActions` (or equivalent) so file tree and tab menus share behavior; add Copy Relative Path to the file tree as well.
7. **Surfaces:** Center workbench strip and floating workspace tab strip share the same composer + default sources. Home workspace title-bar tabs are out of scope.
8. **All kinds on one mechanism:** session / file / diff / run (and future kinds) use the same composition path; unused sources return empty groups in v1.

## Non-goals

- Home top-bar workspace tab menus beyond today’s Close.
- Extension/plugin contribution registry or dynamic load-time registration.
- Submenus / nested menus.
- Keyboard shortcut binding for each new item (can follow later).
- Reworking `TpActionMenu` primitives beyond using existing `TpActionMenuSpec` (+ `onAction`).
- Deleting unused `FileEditorTab` unless it becomes an obvious one-line cleanup during wiring.

## Approach

**Ordered MenuSource + Composer (not a global registry, not ad-hoc `extraSpecs` bags).**

Each source receives a `WorkbenchTabMenuContext` and returns zero or more actionable items (one group). A composer merges groups in source order. Handlers attach via `TpActionMenuSpec.onAction` (existing pattern used by selection-AI / editor toolbar). Action ids remain namespaced (`file.copy_path`, `builtin.close`) for tests and logging even when dispatch is callback-based.

## Architecture

### 1. Context

```dart
class WorkbenchTabMenuContext {
  final BuildContext buildContext;
  final WorkbenchTabKind kind;
  final String tabId;
  final String? filePath; // file id, or diff absolute path when known
  final String? workspaceRoot; // for relative path
  final bool pinnable;
  final bool pinned;
  final bool desktopShellActions;
  final bool remoteFileManagerActions;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? onCloseRight;
  final VoidCallback? onPin;
  // RuntimeContext / path context as needed by FilePathActions
}
```

Strip builders populate this from workbench / floating tab state. Missing `filePath` simply yields an empty FilePath group.

### 2. Source + item + composer

```dart
abstract class WorkbenchTabMenuSource {
  /// Returns items for this group, or empty to omit the group.
  List<WorkbenchTabMenuItem> buildItems(WorkbenchTabMenuContext ctx);
}

class WorkbenchTabMenuItem {
  final String id; // namespaced
  final IconData icon;
  final String label;
  final bool enabled;
  final bool destructive;
  final VoidCallback onAction;
}

abstract final class WorkbenchTabMenuComposer {
  static List<TpActionMenuSpec> compose(
    List<WorkbenchTabMenuSource> sources,
    WorkbenchTabMenuContext ctx,
  );
}
```

Composer rules:

1. Call each source in order.
2. Drop empty item lists.
3. Between adjacent kept groups, insert `TpActionMenuSpec.divider()`.
4. Map each item to `TpActionMenuSpec.item(value: id, …, onAction: …)`.

### 3. Default sources (order)

| Order | Source | v1 behavior |
|------:|--------|-------------|
| 1 | `FilePathTabMenuSource` | Non-empty when `filePath != null` (file tabs; diff tabs with parsed absolute path; floating `filePreview` / `diffPreview` with path). |
| 2 | `SessionTabMenuSource` | Empty in v1 (pin lives in Builtin). Reserved for future session-only actions. |
| 3 | `RunTabMenuSource` | Empty in v1. |
| 4 | `BuiltinCloseTabMenuSource` | Always last: Pin if `pinnable && onPin != null`; Close; Close Others; Close Right. |

Default factory (e.g. `defaultWorkbenchTabMenuSources()`) is shared by center strip and floating strip. Call sites may pass a custom ordered list later without changing the chip.

### 4. File path actions (shared)

Extract a small service/helper used by both `FileTreeContextMenu` and `FilePathTabMenuSource`:

| Action id | Behavior |
|-----------|----------|
| `file.copy_path` | Clipboard absolute path. |
| `file.copy_relative_path` | Clipboard path relative to `workspaceRoot`. If not relativizable (no root / outside root), **disable** the item — do not silently copy absolute. |
| `file.reveal` | Existing `SystemFolderOpener` / `RuntimeFolderOpener` path. |
| `file.open_terminal` | Existing `SystemTerminalOpener` (parent dir for files). Shown only when desktop shell actions allow. |
| `file.open_external` | Open with system app. Shown only when desktop shell actions allow. |

Capability gating matches file tree: omit unavailable items rather than showing disabled rows (except Copy Relative Path, which stays visible but disabled when not relativizable so users understand the action exists).

l10n: reuse existing file-tree strings where labels match; add strings only for Copy Relative Path (and any missing labels).

### 5. Chip / strip wiring

- `WorkbenchStripTabChip` stops hard-coding `_tabMenuSpecs` / `_handleTabMenuSelection` for domain items.
- Chip receives either:
  - a `List<TpActionMenuSpec> Function(BuildContext)` / prebuilt specs from the parent, **or**
  - enough data to build `WorkbenchTabMenuContext` plus the shared sources list,
  and shows the menu via existing `showTpActionMenuFromSpecs*`. Prefer building specs at show-time so pin/close closures stay fresh.
- `WorkspaceShellTabRow` / floating `FloatingWorkspaceTabBar` construct context (kind, path, flags, callbacks) and use the shared default sources.
- `TabInfo` (or parallel strip model) must carry `kind` and resolvable `filePath` (today file `TabInfo.id` is already the absolute path; diff needs absolute path from `WorkbenchTabId.diffAbsolutePath` or floating surface metadata).

Home `_WorkspaceTab` unchanged.

### 6. Errors

- Clipboard / opener failures: same toast + `AppLogger` patterns as file tree.
- Missing path: FilePath source returns `[]` — no exception.
- Relative path unavailable: item present, `enabled: false`.

## Testing

1. **Composer unit tests:** empty groups skipped; single group → no divider; two+ groups → one divider between each; order preserved; trailing/leading dividers never appear.
2. **FilePathTabMenuSource:** with path + full desktop flags → five items; without desktop flags → omit terminal/external (and external-only paths); without path → empty.
3. **BuiltinCloseTabMenuSource:** pin only when pinnable; close trio always when callbacks present.
4. **FilePathActions:** relative path happy path + outside-root / null-root → not relativizable.
5. **Optional widget smoke:** file tab secondary-tap menu includes Copy Path label/id (only if harness cost stays low).

## File layout (expected)

```
client/lib/services/workbench/tab_menu/
  workbench_tab_menu_context.dart
  workbench_tab_menu_source.dart
  workbench_tab_menu_composer.dart
  sources/file_path_tab_menu_source.dart
  sources/session_tab_menu_source.dart
  sources/run_tab_menu_source.dart
  sources/builtin_close_tab_menu_source.dart
  default_workbench_tab_menu_sources.dart

client/lib/services/io/file_path_actions.dart   # or under services/files/

client/lib/pages/workspace_shell/workspace_shell_tabs.dart  # chip wiring
client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart
client/lib/widgets/file_tree/file_tree_context_menu.dart    # reuse helper
```

Exact paths may shift slightly to match existing `services/workbench/` conventions; keep menu composition out of `pages/` widgets beyond wiring.

## Success criteria

- Right-clicking a file tab on the center strip shows file actions above a divider, then close actions.
- Same behavior on floating strip for file/diff preview tabs with a path.
- Session tabs still show pin + close group; no spurious file group.
- File tree Copy Relative Path works via the shared helper.
- Adding a new source is: implement `WorkbenchTabMenuSource`, insert into the default ordered list — no chip edits required.
