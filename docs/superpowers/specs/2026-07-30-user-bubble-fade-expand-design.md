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
| Collapsed height | Align with tool-card preview depth (~**5** lines, or equivalent fixed logical px) |
| Expanded height | Shared **320** logical px (same as `kAiToolCardExpandedMaxHeight`) |
| User bubble hit testing | **No** whole-bubble `GestureDetector`; only fade/chevron toggles (preserve text selection / copy) |
| Tool card hit testing | Keep `AiExpandableToolCard` whole-card tap; fade chevron calls the **same** `onToggle` |
| Tool card body content | Target: pass **full** body into `AiFadeExpandBody` (clip + fade); avoid double truncation via `previewEditHunkLines` / `previewToolCardText` |
| User bubble selection | Collapsed and expanded body remain selectable; fade hit strip ~28–36px tall |
| Tool selection | Unchanged: collapsed preview non-selectable; **expanded** body selectable |
| Short content | No fade, no chevron, no toggle affordance |
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
  collapsedMaxHeight / expandedMaxHeight
  fadeColor
  child: full content (caller does not IR-truncate for this path)

  if child intrinsic height <= active max:
    render child only
  else if !open:
    Clip + maxHeight(collapsed)
    Stack: child (top-aligned) + bottom gradient + centered expand_more
    fade strip / chevron → onToggle
  else:
    ConstrainedBox(maxHeight: expanded) + SingleChildScrollView(child)
    collapse chevron → onToggle

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

**Constants:** prefer reusing or co-locating with `kAiToolCardPreviewLines` / `kAiToolCardExpandedMaxHeight` so bubble and cards stay aligned.

**Relationship to `AiExpandableToolCard`:** that widget remains the whole-card tap wrapper only. `AiFadeExpandBody` owns clip, scroll, fade, and chevron chrome. Both are controlled (`open` + `onToggle`).

## User bubble changes

- Wrap `parts` inside `_UserBubble` with `AiFadeExpandBody`.
- Own `_open` in a small stateful host; when the message body identity/text changes, reset to collapsed.
- Do not wrap the entire bubble in a card-level tap target.
- Mailbox marker, action bar, and existing max-width layout stay as today.

## Edit / shell body changes

- Body panel children go through `AiFadeExpandBody` with the same `open` / `onToggle` as the card.
- Collapsed: mount full body content; shell clips to collapsed max and paints fade + chevron (replace “only first 5 lines mounted” as the primary preview mechanism).
- Expanded: shell provides the 320 scroll viewport (may replace the ad-hoc `ConstrainedBox` currently inside edit/shell panels).
- Basename / line gutter `onOpenFile` and whole-card tap remain.
- Header chevron may stay as a visual affordance; redundant if desired, but not required to remove in this spec.

## Interaction details

- Fade gradient: transparent → `fadeColor` (bubble fill or tool panel fill).
- Chevron: low-contrast, horizontally centered on the fade band (Cursor-like).
- User bubble: text drag-select must not toggle expand; only the fade/chevron hit target toggles.
- Tool cards: exclusive child gestures (basename, gutter) still win over whole-card tap; fade chevron is an additional toggle affordance.

## Testing

Package: `client/packages/ai_message_ui`.

1. Short user message → no fade, no chevron.
2. Long user message → collapsed shows fade + down chevron; tap expands to height ≤ 320 and scrolls; tap again collapses.
3. Long user message → body text remains selectable outside the fade hit strip.
4. Edit/shell → fade chevron and whole-card tap both toggle; basename/gutter still open file.
5. Edit/shell → collapsed body non-selectable; expanded body selectable (regression).
6. User message text update → bubble returns to collapsed.

## Out of scope

- Bottom Composer / follow-up input max-height scroll.
- Assistant message block fade-expand.
- `_ExpandableHistoryMarkdown` IR budget “Show more / Show less”.
- CoT / reasoning / legacy tool chrome redesign.
- Command syntax highlighting, exit-code chips, Read tool chrome.
