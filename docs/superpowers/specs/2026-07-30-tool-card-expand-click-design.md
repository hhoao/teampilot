# Tool card whole-card expand + shell mini-preview parity

**Date:** 2026-07-30  
**Status:** Approved

## Amends

This spec **supersedes** the following locked decisions in earlier specs:

| Prior spec | Prior choice | Now |
|------------|--------------|-----|
| `2026-07-30-edit-tool-card-design.md` | Expand primarily via chevron; diff not a card-wide hit target | Whole-card tap toggles; basename + line gutter still `onOpenFile` |
| `2026-07-29-shell-tool-card-design.md` | Collapsed = header only; expand mounts outer `$` + output panel | Collapsed = header + always-visible mini panel; expand grows **same** panel; no outer shell panel |

Other edit/shell decisions (CoT nesting, resolvers, no command → legacy, no
syntax highlight on shell, edit codecs/enricher) remain in force.

## Goal

Make History edit and shell tool cards behave like Cursor’s compact cards:
whole-card click toggles expand/collapse, while edit basename (and line
gutter) still opens the file. Reshape the shell card so a mini `$ command` +
truncated output preview is always visible when collapsed (same structural
pattern as the edit card).

## Locked decisions

| Topic | Choice |
|-------|--------|
| Edit click | Whole card toggles; basename **and** line-number gutter → `onOpenFile` (no toggle) |
| Shell shape | Align with edit: always-visible mini panel; expand grows same region |
| Shell click | Whole card toggles (header + mini panel + chevron) |
| Architecture | Shared `AiExpandableToolCard` used by edit + shell |
| Preview depth | Shared cap **5** body lines when collapsed (same as edit `_previewCap`) |
| Expanded max height | Shared **320** logical px scroll viewport (same as edit `_expandedMaxHeight`) |
| Selection | Header + collapsed preview stay non-selectable; **expanded** body is selectable/copyable |
| Animation | In-card body growth only (no outer `AnimatedSize` for shell/edit); optional short `AnimatedSize` **inside** the card around the body is OK if cheap |
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

  SelectionContainer.disabled wraps chrome headers as today, but for
  shell/edit the expandable card mounts expanded body OUTSIDE that dead
  zone (or only disables header + collapsed preview) so expanded text
  can be selected.

Shell / Edit chrome:
  AiExpandableToolCard(onToggle)          // wrap the leaf card, not Host
    ├─ header row (icon, title, badges?, chevron)
    └─ body panel (always mounted)
         collapsed → first 5 lines (diff lines / output lines)
         expanded  → full content in scroll view (maxHeight 320)
```

**Wrap site for edit:** put `AiExpandableToolCard` around the **presentational**
`EditToolCard` built by `EditToolCardHost` (inside Host’s `build`), not around
the Host itself — enricher state stays outside the tap wrapper.

`AiExpandableToolCard` wraps the column in a card-level tap that calls
`onToggle`. Exclusive child gestures win with opaque `GestureDetector`s:
edit basename, edit line-number gutter.

Shell no longer uses the outer `if (_open) _ShellTerminalPanel` branch.
Like edit, the panel lives inside the card; the shared args/`Result:`
column stays gated to non-shell / non-edit tools only.

## Edit card changes

- Wrap presentational `EditToolCard` with `AiExpandableToolCard`.
- Diff panel / badges / header chrome / chevron → toggle via card tap.
- Basename link **and** line-number gutter → unchanged `onOpenFile`.
- Inner redundant `onTap: onToggle` on status/chevron may be removed (chevron
  remains visual affordance); card-level tap is enough.
- Preview / expand / enricher / highlighter behavior unchanged except hit
  testing and selection dead-zone scope.

## Shell card changes

### Collapsed (default)

- Header: status + terminal icon + `summary` + chevron.
  - When `description` is present, header shows description and mini panel
    shows full `command` (intentional mild duplication of the command only
    when summary falls back to truncated command — matches Cursor).
- Mini panel always shown:
  - `$` + full `command`
  - If `result != null` and non-blank: first **5** lines after `\n` split
    (same cap as edit). Trailing incomplete line OK; no “…” widget required.
  - Whitespace-only / null `result` → command-only mini panel

### Expanded

- Same panel shows full output (and full command) inside
  `SingleChildScrollView` with `maxHeight: 320`.
- Still no `Result:` label, no JSON args dump.
- Expanded body text is selectable for copy.

### Missing command

- Resolver returns null → legacy chrome (unchanged).

### Expand branching in `AiToolCallPartView`

```dart
// shellTarget / editTarget: NO outer expand panel — body is inside the card
if (_open && shellTarget == null && editTarget == null)
  // existing args + Result: for file summary / legacy only
```

## Shared widget

Path: `client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart`
(shared under `parts/`, not under `edit/`).

```dart
class AiExpandableToolCard extends StatelessWidget {
  const AiExpandableToolCard({
    required this.onToggle,
    required this.child,
  });
  final VoidCallback onToggle;
  final Widget child;
}
```

Shared constants (export or private library shared by edit + shell):

```dart
const kAiToolCardPreviewLines = 5;
const kAiToolCardExpandedMaxHeight = 320.0;
```

## Testing

**Edit**

- Tap diff panel toggles open/closed.
- Tap basename calls `onOpenFile` and does **not** toggle.
- Tap line gutter calls `onOpenFile` and does **not** toggle.
- `initiallyExpanded: true` shows full hunk without a tap.
- `dense: true` still lays out without overflow regressions.

**Shell**

- Collapsed shows `$` + command without tapping.
- Collapsed shows at most 5 output lines when `result` has more.
- Tap header or mini panel toggles; expanded shows full output; no outer
  duplicate panel / no `Result:` label.
- `initiallyExpanded: true` shows full output immediately.
- Expanded output is selectable (`find` / selection APIs as available).
- Bash still wins over edit; Read unchanged.

Update existing shell tests that assert “collapsed hides command”.

## Implementation touchpoints

| Area | Path |
|------|------|
| Shared card + constants | `client/packages/ai_message_ui/lib/src/parts/expandable_tool_card.dart` |
| Edit card | `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` |
| Shell chrome | `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` (extract shell card widget if large) |
| Selection dead-zone | `tool_call_part_view.dart` — narrow `SelectionContainer.disabled` |
| Tests | `tool_call_edit_target_test.dart`, `tool_call_shell_target_test.dart` |

## Non-goals

- Redesigning Read / summary / legacy rows
- Shell command syntax highlighting
- Exit code / duration chips
- Changing CoT grouping or `cotExpandToolsOnOpen` semantics (parent `open`
  still drives expand)
