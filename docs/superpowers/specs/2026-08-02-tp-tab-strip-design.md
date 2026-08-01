# Tp tab strip (shared_ui) + cross-surface reorder

**Date:** 2026-08-02  
**Status:** implemented  
**Scope:** New `TpTabChip` + `TpTabStrip` in `client/packages/shared_ui`; migrate floating / session (workbench) strip / run panel; **delete** `WorkspaceShellTabChip` and domain coupling.  
**Owner constraints:** best architecture / extensibility; **no** backward compatibility.

## Problem

Horizontal tab chrome is duplicated and inconsistently wired:

- `WorkspaceShellTabChip` lives under `workspace_shell/` but is reused by floating and run panels; it reaches into `ChatCubit` when `sessionId` is set (domain leak).
- Floating / shell / run each hand-roll horizontal scroll rows.
- None of those chip rows support **drag-to-reorder**. Sidebar already has session reorder; the **center strip** order is `WorkbenchCubit.tabOrder` (mixed kinds) — not `ChatCubit.reorderSessions`.

## Goals

1. **Presentation-only** `TpTabChip` + `TpTabStrip` in `shared_ui` (no TeamPilot cubits / l10n / CLI types).
2. **Optional horizontal drag-reorder** (`onReorder == null` ⇒ not reorderable).
3. Migrate **floating**, **workbench/session strip** (`WorkspaceShellTabRow`), and **run panel** chips onto `TpTabStrip`.
4. **Delete** `WorkspaceShellTabChip` (no typedef shim).
5. Extensible slots: leading, in-strip actions (`+`), outer trailing, context menus via host callbacks.

## Non-goals

- Unifying home title-bar `_WorkspaceTab` in v1 (follow-up if cheap).
- Tear-off / dock-out drag.
- Persisting floating tab order to disk.
- Syncing strip reorder into sidebar `reorderSessions` by default (optional follow-up only).

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Package | `shared_ui`: `TpTabChip`, `TpTabStrip`, `TpTabStripMetrics`, `reorderListItems` |
| Compat | **None** |
| Domain in chip | **Forbidden** — host passes `title`, `leading`, `working`, `preview`, etc. |
| Reorder API | `void Function(int oldIndex, int newIndex)? onReorder` — Material `ReorderableListView.onReorder` index semantics |
| In-strip actions | `Widget? inStripTrailing` — after tabs, **inside** horizontal scroll viewport, **excluded** from reorder indices (shell / floating `+`) |
| Outer trailing | `Widget? trailing` — outside scroll/reorder (pane actions, run clear button) |
| Leading | `Widget? leading` before scroll region |
| Context menu | Chip: `onSecondaryTapDown` / `onLongPress`; host builds `TpActionMenu` (pin / close / close others / close right) |
| Preview | `bool preview` — muted / italic title (today’s shell behavior) |
| Chrome visibility | Document hover / active / Android rules in metrics; close + leading fade via chip internals or host `actions` |
| Heights | `TpTabStripMetrics.shell` (40) vs `.compact` (36 floating); host passes `height` / metrics |
| Floating gestures | Title **Stack** already puts strip above pan layer; chips own reorder hits; remove any grab cursor on the chip row itself; test: chip drag does not move panel |
| Session strip reorder | **`WorkbenchCubit.reorderTabs(workspaceId, oldIndex, newIndex)`** on center `tabOrder` (all tab kinds). **Not** `ChatCubit.reorderSessions` |
| Sidebar sync | Out of scope for v1 |
| Floating reorder | `FloatingWorkspaceCubit.reorderTabs` |
| Run panel reorder | Stable display-order override: panel-local `List<String> tabOrderIds` merged with `RunCubit.state.sessions` (or `RunCubit` API). **Not** “setState on cubit’s list” |

## Architecture

```
shared_ui
  TpTabChip
  TpTabStrip  (scroll + optional reorder + leading / inStripTrailing / trailing)
       │
       ├─ FloatingWorkspaceTabBar  → FloatingWorkspaceCubit.reorderTabs
       ├─ WorkspaceShellTabRow     → WorkbenchCubit.reorderTabs
       └─ RunPanel tab row         → local/display order merge
```

### `TpTabChip`

```dart
class TpTabChip extends StatelessWidget {
  const TpTabChip({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.leading,
    this.working = false,
    this.preview = false,
    this.accentColor,
    this.maxWidth = 200,
    this.tooltip,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.actions,
    super.key,
  });
}
```

Visual parity with today’s shell chip (accent bar, active fill, hover, close). No `sessionId` / `CliTool`.

### `TpTabStrip`

```dart
class TpTabStrip extends StatelessWidget {
  const TpTabStrip({
    required this.itemCount,
    required this.itemBuilder,
    this.onReorder,
    this.leading,
    this.inStripTrailing, // e.g. + — scrolled, not reordered
    this.trailing,        // outer
    this.metrics = TpTabStripMetrics.compact,
    super.key,
  });
}
```

- `onReorder != null`: horizontal reorderable list; each item wrapped for drag-start on the chip (threshold so tap still selects).
- `onReorder == null`: horizontal scroll only.
- `reorderListItems<T>(items, oldIndex, newIndex)` exported beside the strip.

### Host sinks (corrected)

| Call site | Reorder sink |
|-----------|----------------|
| Floating | `FloatingWorkspaceCubit.reorderTabs` |
| `WorkspaceShellTabRow` / workbench strip | `WorkbenchCubit.reorderTabs` (permute `tabOrder`) |
| Run panel | Display-order id list merged over `RunCubit.state.sessions` |

Wire shell `onReorder` from `workspace_shell.dart` / chat page shell that already owns workspace id + workbench cubit.

### Floating chrome

Keep Stack title: pan/double-tap underlay; strip + window controls above. Chip row must not set `SystemMouseCursors.grab`. Add gesture regression: reorder chip ≠ panel move.

## Files (expected)

| Area | Change |
|------|--------|
| `shared_ui/.../tab/` | `tp_tab_chip.dart`, `tp_tab_strip.dart`, metrics, `reorder_list_items.dart`, export |
| `shared_ui/test/` | Chip + strip reorder + trailing exclusion |
| `floating_workspace_cubit.dart` | `reorderTabs` |
| `floating_workspace_tab_bar.dart` | `TpTabStrip` |
| `workbench_cubit.dart` | `reorderTabs` |
| `workspace_shell_tabs.dart` | Delete chip; row uses strip; selects moved to builders |
| `workspace_shell.dart` (+ shell host) | Pass chip props; `onReorder` → workbench |
| `run_panel.dart` | Strip + display-order merge |
| App tests | Cubit reorder; strip / gesture regressions |

## Test plan

1. shared_ui: reorder callback indices; `inStripTrailing` / `trailing` not in indices.
2. `FloatingWorkspaceCubit.reorderTabs` — order changes, `activeTabId` stable.
3. `WorkbenchCubit.reorderTabs` — `tabOrder` permutes for mixed kinds.
4. Run panel — display order survives session stream updates for still-present ids.
5. Floating: drag chip does not change panel rect; empty chrome still pans / double-taps.
6. Tap / close / context menu regressions on shell + floating.

## Extensibility

- Vertical axis later without new package.
- `proxyDecorator` for drag chrome.
- Home `_WorkspaceTab` may adopt `TpTabChip` later.

## Out of scope follow-ups

- Tear-off tabs.
- Floating order in layout prefs.
- Sidebar `reorderSessions` sync from strip.
- Force-unify home workspace title tabs in the same change set.
