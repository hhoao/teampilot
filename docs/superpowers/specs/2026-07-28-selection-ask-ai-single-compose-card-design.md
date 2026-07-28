# Selection Ask AI: single compose card dialog

## Problem

`SelectionAskAi.openComposeDialog` currently hosts Ask AI as:

```
TpDialog (max 720×720)
  └── TpDialogHeader("用 AI 提问…")
  └── SizedBox(height: 600)
        └── WorkspaceChatLanding  // full landing: back, repo/worktree row, compose
```

That reads as a **dialog inside a dialog**: outer modal chrome plus the full
chat-landing shell (back control, project/worktree selectors, large empty
canvas). Users want **one** compose surface — the same input card as landing,
without the landing page chrome.

Related prior design: [2026-07-27-selection-ask-ai-design.md](2026-07-27-selection-ask-ai-design.md)
(entries, prefill, submit path). This doc only changes the **dialog chrome /
embedded surface**.

## Goal

Replace the nested landing host with a **single** compose card dialog:

1. One rounded compose surface (same controls as landing compose: mode, model /
   preset, expert, attach / enhance / voice, send).
2. No `TpDialogHeader` title row; close via `×` on the card (or dialog barrier /
   Escape as today).
3. Hide landing-only chrome: back-to-start, repo / project / worktree selector
   row, and the tall empty landing layout.
4. Keep submit semantics: `persistLandingDraft` → `submitWorkspaceLandingMessage`
   → pop when session opens.
5. Working directory / launch draft still come from `resolveLandingDraft` and
   `WorktreeCubit.pathForNewSession` (unchanged), not from in-dialog selectors.

## Non-goals

- Cursor-style ultra-minimal bar (input + one mode chip only) — rejected in
  brainstorming (that was option A; product choice is **B**).
- Overlay anchored to selection caret (option 3) — stay on `showDialog`.
- Redesigning `WorkspaceChatLanding` primary page layout for the main chat pane.
- Changing AI context formatting, FAB host, or menu entry points.
- Adding new launch parameters unique to Ask AI.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Product shape | **B** — single compose card; keep full bottom toolbar |
| Presentation | Modal `showDialog` (not selection-anchored Overlay) |
| Outer chrome | No `TpDialogHeader`; no fixed 600px landing shell |
| Landing chrome in dialog | Hide back + workspace/worktree selector row |
| Compose controls | Same as landing compose card |
| Launch / cwd | Draft resolver + WorktreeCubit (no in-dialog path pickers) |
| Submit | Existing `SelectionAskAi` → `submitWorkspaceLandingMessage` |

## Architecture

```
SelectionAskAi.openComposeDialog
        │
        ▼
showDialog + WorktreeCubit.value
        │
        ▼
_SelectionAskAiDialog
  · compact shell (TpDialog or equivalent; no header title)
  · compose-only body (reuse landing compose stack without landing chrome)
        │
        ▼
onSubmit(message, LandingLaunchContext)
  → persistLandingDraft
  → submitWorkspaceLandingMessage
  → Navigator.pop on session opened
```

### Implementation approach

Prefer extracting or parameterizing a **compose-only** mode on the existing
landing stack rather than forking a second full landing state machine:

| Option | Use when |
|--------|----------|
| `WorkspaceChatLanding(chrome: composeOnly)` (or equivalent flag) | Landing state (draft, chips, voice, enhance) stays one place |
| Thin Ask-AI host that mounts only `WorkspaceChatLandingComposeCard` + shared draft helpers | Only if a flag on landing would tangle the main landing layout too much |

Either way:

- Dialog max size should hug the card (width similar to landing card; height
  content-driven / capped), not a 720×720 empty frame.
- Prefill via existing `initialText` / `selectionAskAiPrefillText`.
- Continue capturing `WorktreeCubit` before the route boundary (tests already
  cover this).

### What stays in `selection_ai/`

- `SelectionAskAi.openComposeDialog` API and submit wiring
- FAB / menu entry points unchanged

### What changes

- `_SelectionAskAiDialog.build`: drop header + fixed-height full landing shell
- Landing (or new thin host): support compose-only embedding for Ask AI

## Error handling

Unchanged from prior Ask AI design:

- Empty / whitespace `aiContext` → do not open dialog
- Missing `WorktreeCubit` → log and return (no dialog)
- Submit failures → landing/toast paths already used by
  `submitWorkspaceLandingMessage`; keep dialog open until success pop

## Testing

Update `client/test/services/selection_ai/selection_ask_ai_test.dart`:

- Still: empty context → no dialog; WorktreeCubit inherited across route
- Assert: no `TpDialogHeader` / no landing back-to-start chrome in Ask AI dialog
- Assert: compose field present with prefilled context
- Submit path tests remain valid if they target `WorkspaceChatLanding` /
  compose submit; adjust finders if the host widget type changes

## Success criteria

- Ask AI opens as **one** compose card, not a titled empty modal wrapping a
  second full landing page.
- Mode / model / expert / attach / enhance / voice / send behave like landing
  compose.
- Submit still creates a session and delivers the prefilled (+ edited) message.
- Editor, terminal, and FAB entry points keep working without API churn beyond
  the dialog body.
