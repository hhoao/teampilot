# Desktop / touch press-scale click effect

## Problem

Since the platform-adaptive `TpHover` migration, desktop clicks have **zero press feedback**: hover shows a color fade and a hand cursor (arrow when disabled), but pressing a button produces no visual response (the InkWell ripple was intentionally removed on desktop, and `pressScale` — `TpHover`'s built-in press animation — is currently `1.0` everywhere, so it is a no-op at every one of the ~98 `TpHover`/`TpHoverRow` call sites). Primary actions (send, attach, chips, icon buttons) feel "dead" on press; the user can't tell the click registered.

## Decision

Enable a **subtle press-scale effect** as the default press affordance on the `TpHover` primitive, applied on **both platforms** (desktop scale + cursor/hover; touch scale layered over the existing InkWell ripple):

1. **Flip `TpHover.pressScale` default from `1.0` to `0.96`** — a 4% shrink while the pointer is down (120 ms, spring back on release/cancel). The mechanism already exists (`_onTapDown`/`_onTapUp`/`_onTapCancel` press bookkeeping + `AnimatedScale`); this only changes the default.
2. **`TpHoverRow` passes `pressScale: 1.0`** to its internal `TpHover` — row-type surfaces opt out centrally (4 current call sites + all future rows).
3. **~24 direct `TpHover` row/menu/native-chrome call sites get explicit `pressScale: 1.0`** — full-width rows, menu/suggestion rows, and native window chrome keep hover-only feedback.

Compact button / chip / pill / icon sites (~26) keep the new default and gain the effect for free.

## Architecture

### 1. `TpHover` default (`client/packages/shared_ui/lib/src/components/hover/tp_hover.dart`)

```dart
this.pressScale = 0.96,   // was 1.0
```

No other change to the widget: the existing `AnimatedScale(scale: _pressed && _interactive ? widget.pressScale : 1.0, …)` and the `_onTapDown`/`_onTapUp`/`_onTapCancel` getters already activate once `pressScale != 1.0`. Sites that pass a custom `onTapDown` (menu behavior) keep their custom callback and get no scale — same as today.

### 2. `TpHoverRow` opt-out (`client/packages/shared_ui/lib/src/components/hover/tp_hover_row.dart`)

Add to the delegated `TpHover(…)` construction: `pressScale: 1.0`. Row semantics are hover-highlight + select, not press-scale.

### 3. Explicit opt-out list (`pressScale: 1.0`)

| File | Site |
|---|---|
| `lib/widgets/compose/compose_trigger_field.dart` | suggestion/menu rows |
| `lib/widgets/window_chrome_controls.dart` | min/max/close chrome buttons |
| `lib/pages/home_workspace/home_workspace_sidebar.dart` | sidebar nav rows |
| `lib/pages/home_workspace/workspace/workspace_sidebar.dart` | workspace sidebar rows |
| `lib/pages/home_workspace/workspaces_tab.dart` | workspace tab rows |
| `lib/pages/home_workspace/home_workspace_team_tab.dart` | team tab rows |
| `lib/pages/home_workspace/workspace/worktree_group_section.dart` | worktree rows |
| `lib/pages/home_workspace/workspace/workspace_search_dialog.dart` | search result rows |
| `lib/widgets/file_tree_node.dart` | tree node rows |
| `lib/widgets/git/git_change_folder_tile.dart` / `git_change_tile.dart` | git change tiles |
| `lib/widgets/git/git_source_control_panel.dart` | branch row |
| `lib/widgets/notification/notification_list_tile.dart` | notification list tiles |
| `lib/widgets/right_tools/tabbed_panel.dart` | panel tab rows |
| `lib/widgets/right_tools/board_panel.dart` | task card rows |
| `lib/widgets/notification/progress_activity_tile.dart` | progress tile rows |
| `lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart` | member placement rows |
| `lib/widgets/settings/workspace_hub_shell.dart` | hub nav rows |
| `lib/widgets/workspace_status_bar/resource_manager_panel.dart` / `ssh_hosts_panel.dart` | resource / ssh rows |
| `lib/pages/mcp/mcp_registries_section.dart` / `mcp_form_page.dart` | registry / metadata rows |
| `lib/pages/team_config/team_config_nav_panel.dart` | add-tile row |
| `packages/shared_ui/…/dialog/tp_dialog_nav_shell.dart` | nav item + dropdown entries |
| `packages/shared_ui/…/sidebar/tp_sidebar_menu.dart` | sidebar menu items |

(The exact opt-out set is re-verified per site during implementation; any full-width row or menu-like surface found in the sweep also gets `1.0`.)

## Testing

- **shared_ui**: adjust/extend `tp_hover_test.dart` — default press produces `AnimatedScale` at `0.96`; explicit `pressScale: 1.0` produces none. Confirm the existing `pressScale wraps with AnimatedScale when not 1.0` still passes; run the full shared_ui suite.
- **Main repo**: `flutter analyze --no-fatal-infos --no-fatal-warnings`; run affected widget tests (`test/widgets/compose`, `test/widgets/git`, `test/pages/home_workspace`, router tests). No structure assertions on `AnimatedScale` absence are expected to break — verify in the gate.
- **Manual (desktop)**: primary buttons (send, chips, icon buttons) shrink ~4% while pressed and spring back; rows, menus, and window chrome show no scale; hover/cursor behavior unchanged.
- **Manual (touch)**: buttons show ripple + subtle scale; rows ripple only.

## Risks / notes

- Existing tests that pump `TpHover` without `pressScale` now render an `AnimatedScale`; only tests asserting its *absence* could break — none found in the sweep, but the gate confirms.
- A future row-style `TpHover` added directly (not via `TpHoverRow`) will scale by default unless it sets `pressScale: 1.0` — an intentional, documented default; the opt-out list is the current sweep.
- No l10n, no new deps, no theme changes.
