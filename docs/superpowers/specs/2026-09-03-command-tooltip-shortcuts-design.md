# Command tooltip shortcuts

**Date:** 2026-09-03  
**Status:** Approved for planning

## Goal

Surface the effective keyboard shortcut in hover tooltips for a few
high-traffic chrome controls so users can discover bindings without opening
the shortcuts cheatsheet.

## Scope

| Control | Command id | Default chord |
|---------|------------|---------------|
| Title-bar sidebar visibility toggle | `CommandIds.toggleSidebar` | `Mod+B` |
| Title-bar right-tools visibility toggle | `CommandIds.toggleSecondarySidebar` | `Mod+Alt+B` |
| Workspace sidebar Search action tile | `CommandIds.workspaceSearch` | double-tap Shift |

### Out of scope

- Changing default keybindings or command registration
- Changing click / tap behavior of the three controls
- Shortcut badges next to icons (tooltip text only)
- Right-tools content search (`CommandIds.workspaceContentSearch` / Mod+Shift+F)
- Broader rollout to every chrome button

## Format

- Bound: `{label} ({chord})`  
  Examples: `Hide sidebar (Ctrl+B)`, `搜索 (Shift×2)`, macOS `Hide sidebar (⌘B)`
- Unbound or unresolved: `{label}` only (no empty parentheses)
- Chord rendering reuses `formatKeyChord` (including double-tap Shift →
  `Shift×2` / `⇧⇧`)
- When a command has multiple chords, show the first only (same as floating
  workspace empty-state shortcut labels)

Do not bake chords into l10n strings; labels stay as today
(`sidebarPanelHidden` / `sidebarPanelVisible`, `rightToolsPanelHidden` /
`rightToolsPanelVisible`, `workspaceSearchTitle`).

## Architecture

### Helper

Add `client/lib/services/commands/command_tooltip.dart`:

```dart
String commandTooltip(BuildContext context, String label, String commandId)
```

Behavior:

1. Resolve effective bindings via `ShortcutCubit.state.overrides` +
   `KeybindingResolver.effectiveBindings(catalog: CommandCatalog.v1, …)`.
2. Take the first chord for `commandId`, format with `formatKeyChord` and
   `defaultIsMacOS()`.
3. If no chord, or `ShortcutCubit` is missing from the tree, return `label`
   unchanged (no throw).

### Call sites

1. **`WorkspaceShellSidebarVisibilityToggle`**
   (`workspace_shell_tabs.dart`): set `TpIconButton.tooltip` to
   `commandTooltip(context, showOrHideLabel, CommandIds.toggleSidebar)`.
2. **`WorkspaceShellRightToolsVisibilityToggle`**: same pattern with
   `CommandIds.toggleSecondarySidebar`.
3. **Workspace sidebar Search** (`workspace_sidebar.dart`):
   - Extend `_SidebarActionTile` with optional `tooltip`.
   - When non-null/non-empty, wrap the tile in `Tooltip(message: …)`.
   - Search row passes
     `commandTooltip(context, l10n.workspaceSearchTitle, CommandIds.workspaceSearch)`.

Click handlers stay on `LayoutCubit` / `showWorkspaceSearchDialog`; do not
route these tooltips through `CommandBus`.

### Rebuild on rebind

Call sites that show a command tooltip must rebuild when
`ShortcutCubit.state.overrides` changes (`context.select` or
`BlocBuilder`), so a rebind/unbind in Settings updates the hover text
without restarting the app.

## Edge cases

| Case | Behavior |
|------|----------|
| Command unbound | Label only |
| No `ShortcutCubit` in ancestry | Label only |
| Multiple chords | First chord only |
| Double-tap Shift | Existing formatter strings |
| Missing command id in catalog | Label only |

## Testing

1. **`command_tooltip_test.dart`**
   - Default catalog binding appends formatted chord
   - Unbound / empty overrides → label only
   - Missing `ShortcutCubit` → label only
   - Double-tap Shift formats via `formatKeyChord`
2. **Widget tests** for sidebar / right-tools toggles: tooltip message
   contains the existing l10n label and a non-empty chord fragment when
   defaults are active.
3. **Search tile**: after adding `Tooltip`, assert message contains search
   title + double-Shift formatted chord.

## Success criteria

- Hovering the three controls shows label + current effective shortcut.
- Rebinding or unbinding in Keyboard Shortcuts updates tooltips.
- No behavior change on click; no new default chords.
