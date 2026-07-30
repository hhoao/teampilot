# User bubble fade-expand + shared AiFadeExpandBody

**Date:** 2026-07-30  
**Status:** Approved

## Amends

This spec **extends** (does not replace) locked decisions in:

| Prior spec | Still in force | This spec adds |
|------------|----------------|----------------|
| `2026-07-30-tool-card-expand-click-design.md` | Whole-card tap via `AiExpandableToolCard`; expanded max height **320**; edit basename + line gutter → `onOpenFile` | Collapsed body chrome: bottom gradient fade + centered chevron; shared shell also used by user bubbles |
| `2026-07-30-edit-tool-card-design.md` / shell design | CoT nesting, resolvers, enricher, no shell syntax highlight | Collapsed preview shifts from “mount only first 5 lines” toward “mount full body + clip/fade” |

Whole-card tap, selection dead-zone rules for tool chrome, and out-of-scope items from the expand-click spec remain unless explicitly overridden below.

## Goal

Match Cursor’s long-content chrome for History **user bubbles**: collapsed max height with a bottom fade mask and centered down-chevron; tap to expand. Expand still caps height and scrolls internally. Extract the fade/clip/chevron behavior into a shared **`AiFadeExpandBody`** and wire it into user bubbles **and** edit/shell tool card bodies in the same change set.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Scope | History **sent user bubbles** + edit/shell **body panels**; not Composer input |
| Architecture | Shared `AiFadeExpandBody` in `ai_message_ui`; user bubble first consumer in wiring order, same PR also migrates edit/shell bodies |
| Collapsed chrome | Bottom gradient fade + centered `expand_more`; tap fade strip / chevron toggles |
| Expanded chrome | `maxHeight` **320** + `SingleChildScrollView`; centered `expand_less` (or equivalent) to collapse |
| Collapsed height | Shared fixed **`kAiFadeExpandCollapsedMaxHeight = 120.0`** logical px (approx. former 5-line tool preview; v1 callers do not override) |
| Expanded height | Shared **`kAiFadeExpandExpandedMaxHeight = 320.0`** (= `kAiToolCardExpandedMaxHeight`); **`AiFadeExpandBody` exclusively owns** the expanded scroll viewport |
| User bubble hit testing | **No** whole-bubble `GestureDetector`; only fade/chevron toggles (preserve text selection / copy) |
| Tool card hit testing | Keep `AiExpandableToolCard` whole-card tap; fade/chevron uses an **opaque child `GestureDetector`** (same pattern as basename/gutter) so the tap is absorbed once and calls the same `onToggle` — no double toggle |
| Tool card body content | Pass **full** body into `AiFadeExpandBody` (clip + fade); stop using `previewEditHunkLines` / `previewToolCardText` on this path |
| User bubble selection | Collapsed and expanded body remain selectable; fade hit strip **32** logical px tall |
| Tool selection | Unchanged: collapsed preview non-selectable; **expanded** body selectable |
| Short content | After layout, if child height ≤ active max (`collapsed` or `expanded`) → no fade, no chevron, no toggle |
| Animation | No required outer `AnimatedSize`; natural height change like current tool cards |
| Out of scope | Composer max-height; assistant message blocks; History markdown IR “Show more”; CoT / reasoning chrome redo |

## Problem

1. Long user messages in History grow without bound and dominate the thread.
2. Cursor-style affordance (fade + centered chevron) is missing; tool cards already expand but collapsed UI is line-truncated without the bottom dissolve mask.
3. Duplicating fade/clip logic in bubble vs edit vs shell would drift; a shared body shell keeps heights and chrome consistent.

## Architecture

```
AiFadeExpandBody (new, ai_message_ui)
  open / onToggle
  collapsedMaxHeight = kAiFadeExpandCollapsedMaxHeight (120)
  expandedMaxHeight  = kAiFadeExpandExpandedMaxHeight (320)
  fadeColor
  child: full content (caller does not line-truncate or IR-truncate for this path)

  after layout, compare child height to active max:
  if child height <= active max:
    render child only
  else if !open:
    Clip + maxHeight(collapsed)
    Stack: child (top-aligned) + bottom gradient + centered expand_more
    opaque GestureDetector on fade strip / chevron → onToggle
  else:
    ConstrainedBox(maxHeight: expanded) + SingleChildScrollView(child)
    // AiFadeExpandBody OWNS this viewport — edit/shell must NOT wrap another maxHeight 320
    opaque GestureDetector on collapse chevron → onToggle

User bubble:
  _UserBubble (local StatefulHost for _open; reset on message text change)
    └─ AiFadeExpandBody(fadeColor: resolveUserBubble)
         └─ parts

Edit / shell:
  AiExpandableToolCard(onToggle)          // whole-card tap unchanged
    └─ header + body panel
         └─ AiFadeExpandBody(open, onToggle, fadeColor: resolveToolPanel)
              └─ full diff lines / full command+output
```

**Constants** (define next to or replace usage of the old tool-card height helpers):

| Name | Value | Role |
|------|-------|------|
| `kAiFadeExpandCollapsedMaxHeight` | `120.0` | Collapsed clip for bubble + edit/shell body |
| `kAiFadeExpandExpandedMaxHeight` | `320.0` | Expanded scroll viewport (alias / equal to `kAiToolCardExpandedMaxHeight`) |
| Fade hit strip height | `32.0` | Bottom tap target over the gradient |

**Relationship to `AiExpandableToolCard`:** that widget remains the whole-card tap wrapper only. `AiFadeExpandBody` exclusively owns clip, expanded scroll, fade, and chevron chrome. Both are controlled (`open` + `onToggle`). On tool cards, the fade/chevron detector must be opaque so the gesture does not also fire the parent card tap (one `onToggle` per tap).

## Implementation touchpoints

| Area | Path / symbol |
|------|----------------|
| Shared shell | `client/packages/ai_message_ui/lib/src/parts/fade_expand_body.dart` (`AiFadeExpandBody` + height constants) |
| Barrel export | `client/packages/ai_message_ui/lib/ai_message_ui.dart` |
| User bubble | `client/packages/ai_message_ui/lib/src/ai_message_view.dart` (`_UserBubble` + thin stateful host) |
| Edit body | `client/packages/ai_message_ui/lib/src/edit/edit_tool_card.dart` (`_EditDiffPanel` — remove line-preview mount + local 320 box) |
| Shell body | `client/packages/ai_message_ui/lib/src/shell/shell_tool_card.dart` (same migration) |
| Preview helpers | Stop calling `previewEditHunkLines` / `previewToolCardText` from fade-expand body path (helpers may remain for tests until unused) |
| Tests | New `fade_expand_body_test.dart`; extend user-bubble / edit / shell widget tests |

## User bubble changes

- Wrap `parts` inside `_UserBubble` with `AiFadeExpandBody`.
- Own `_open` in a small stateful host; when the message body identity/text changes, reset to collapsed.
- Do not wrap the entire bubble in a card-level tap target.
- Mailbox marker, action bar, and existing max-width layout stay as today.

## Edit / shell body changes

- Body panel children go through `AiFadeExpandBody` with the same `open` / `onToggle` as the card.
- Collapsed: mount **full** body content; `AiFadeExpandBody` clips to 120 and paints fade + chevron (replaces “only first 5 lines mounted”).
- Expanded: **`AiFadeExpandBody` alone** provides the 320 scroll viewport; remove the ad-hoc `ConstrainedBox(maxHeight: 320)` / `SingleChildScrollView` from edit/shell panels when migrating (no nested double viewport).
- Basename / line gutter `onOpenFile` and whole-card tap remain.
- Header chevron may stay as a visual affordance; not required to remove in this spec.

## Interaction details

- Fade gradient: transparent → `fadeColor` (bubble fill or tool panel fill).
- Chevron: low-contrast, horizontally centered on the fade band (Cursor-like).
- User bubble: text drag-select must not toggle expand; only the fade/chevron hit target toggles.
- Tool cards: basename, gutter, and fade/chevron each use opaque child detectors so they win over (and do not double-fire with) whole-card tap; fade/chevron remains an additional toggle affordance.

## Testing

Package: `client/packages/ai_message_ui`.

1. Short user message → no fade, no chevron.
2. Content height exactly ≤ collapsed max → no fade, no chevron.
3. Long user message → collapsed shows fade + down chevron; tap expands to height ≤ 320 and scrolls; tap again collapses.
4. Long user message → body text remains selectable outside the fade hit strip.
5. Edit/shell → fade chevron toggles once (no double toggle); whole-card tap still toggles; basename/gutter still open file.
6. Edit/shell → collapsed body non-selectable; expanded body selectable (regression).
7. User message text update → bubble returns to collapsed.
8. Unit/widget: `AiFadeExpandBody` alone — overflow collapsed paints chevron; expanded scrolls; short child bypasses chrome.

## Out of scope

- Bottom Composer / follow-up input max-height scroll.
- Assistant message block fade-expand.
- `_ExpandableHistoryMarkdown` IR budget “Show more / Show less”.
- CoT / reasoning / legacy tool chrome redesign.
- Command syntax highlighting, exit-code chips, Read tool chrome.
