# Tool card whole-card expand + shell mini-preview parity

**Date:** 2026-07-30  
**Status:** Approved

## Goal

Make History edit and shell tool cards behave like Cursor’s compact cards:
whole-card click toggles expand/collapse, while edit basename still opens the
file. Reshape the shell card so a mini `$ command` + truncated output preview
is always visible when collapsed (same structural pattern as the edit card).

## Locked decisions

| Topic | Choice |
|-------|--------|
| Edit click | Whole card toggles; basename → `onOpenFile` (no toggle) |
| Shell shape | Align with edit: always-visible mini panel; expand grows same region |
| Shell click | Whole card toggles (header + mini panel + chevron) |
| Architecture | Shared expandable card shell used by edit + shell |
| Preview depth | ~3–5 lines of body (diff lines / output lines) when collapsed |
| Out of scope | Command syntax highlight, exit-code chips, Read/legacy chrome, CoT changes |

## Problem

1. Edit card only toggles from status icon / chevron; the always-visible diff
   panel is not a hit target — unlike Cursor, where the card body expands.
2. Shell card collapses to header-only; the `$ command` + output appear only
   after expand in a separate below-header panel — inconsistent with the new
   edit card and with Cursor’s terminal tool chrome.

## Architecture

```
AiToolCallPartView
  Subagent | Shell | Edit | File summary | Legacy   (branch order unchanged)

Shell / Edit chrome:
  AiExpandableToolCard(onToggle)
    ├─ header row (icon, title, badges?, chevron)
    └─ body panel (always mounted)
         collapsed → truncated preview (~3–5 lines)
         expanded  → full content (same widget, longer list / text)
```

`AiExpandableToolCard` wraps the column in a card-level tap that calls
`onToggle`. Child widgets that need exclusive gestures (edit basename
`onOpenFile`) nest their own `GestureDetector` with opaque behavior so they
win over the parent tap.

Shell no longer uses the outer `if (_open) _ShellTerminalPanel` branch for its
body. Like edit, the panel lives inside the card; the shared
args/`Result:` column stays gated to non-shell / non-edit tools only.

## Edit card changes

- Wrap `EditToolCard` content with `AiExpandableToolCard`.
- Diff panel / badges / chevron / header chrome → toggle.
- Basename link → unchanged `onOpenFile`.
- Preview / expand / enricher / highlighter behavior unchanged except hit
  testing.

## Shell card changes

### Collapsed (default)

- Header: status + terminal icon + `summary` + chevron (same labels as today).
- Mini panel always shown:
  - `$` + full `command` (wrap or ellipsis per existing monospace style)
  - If `result != null`: up to ~3–5 lines of dimmed output (prefer first lines;
    truncate with ellipsis / “…” affordance only if needed — no second stacked
    panel)

### Expanded

- Same mini panel grows to show full output text (scroll + maxHeight if long).
- Still no `Result:` label, no JSON args dump.

### Missing command

- Resolver returns null → legacy chrome (unchanged).

### Expand branching in `AiToolCallPartView`

```dart
if (_open && shellTarget != null)
  // REMOVE dedicated outer shell panel — body is inside the card
else if (_open && editTarget == null)
  // existing args + Result: for file summary / legacy
```

When `shellTarget != null`, do **not** render an outer expand panel (parity
with edit).

## Shared shell widget

```dart
class AiExpandableToolCard extends StatelessWidget {
  const AiExpandableToolCard({
    required this.onToggle,
    required this.child,
    // optional semantics
  });
}
```

Implementation notes:

- Parent `GestureDetector(behavior: HitTestBehavior.opaque, onTap: onToggle)`.
- Prefer keeping text selectable inside expanded body where feasible; if
  selection and tap conflict, prioritize: (1) basename open, (2) text
  selection drag, (3) tap-to-toggle on non-drag. Do not block copy of
  command/output/diff when expanded.
- Chevron remains a visible affordance but is redundant with card tap.

## Testing

**Edit**

- Tap diff panel toggles open/closed.
- Tap basename still calls `onOpenFile` and does not toggle.
- Chevron still toggles.

**Shell**

- Collapsed shows `$` + command without tapping.
- Collapsed shows truncated output when `result` present.
- Tap header or mini panel toggles; expanded shows full output; no outer
  duplicate panel / no `Result:` label.
- Bash still wins over edit; Read unchanged.

## Implementation touchpoints

| Area | Path |
|------|------|
| Shared shell | `client/packages/ai_message_ui/lib/src/edit/expandable_tool_card.dart` (or `src/parts/`) |
| Edit card | `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` |
| Shell chrome | `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` (extract shell card widget if large) |
| Tests | `tool_call_edit_target_test.dart`, `tool_call_shell_target_test.dart` |

## Non-goals

- Redesigning Read / summary / legacy rows
- Shell command syntax highlighting
- Exit code / duration chips
- Changing CoT grouping or `cotExpandToolsOnOpen` semantics (parent `open`
  still drives expand)
