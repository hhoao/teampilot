# Cursor / Codex PTY reinject guard: design

## Problem

TeamPilot Chat → `cursor-agent` occasional **duplicate user bubbles** for short
replies (e.g. `A`). The agent transcript JSONL shows two identical
`<user_query>` events for one compose submit — not a UI-only optimistic merge
bug.

Root cause: `FullscreenPtyAutomation.deliverPasteAndSubmit` pastes, CRs, then
on `crStuck` **reinjects** (clear → paste → CR). Cursor (and Codex) use
`FullscreenCrAckStrategy.composerMovesDown`: submitted text stays visible as
transcript history while a fresh empty composer (`→` / `›`) appears below.
When grid ACK fails to observe that transition in time, the first CR has often
already committed the message; reinject pastes and submits it again.

Short needles are especially vulnerable because they remain at the old anchor
cells after submit, so ACK depends entirely on detecting the new composer row.

## Goal

- When CR polling returns `crStuck` but the composer is already **empty**
  (prefix-only), treat the first CR as successful and **do not reinject**.
- Keep true stuck-staged recovery: if the needle body is still on the composer
  row, reinject as today.

## Non-goals

- Changing Chat optimistic pending / transcript parsers
- Scheme B (forbid extra CR `onRetry` during ACK poll)
- Global `PtyInjectAckTiming` changes
- Changing `anchorCellClears` behavior (Claude / OpenCode / Flashsky)

## Scope

| CLI | Strategy | Affected |
|-----|----------|----------|
| Cursor | `composerMovesDown` + `→` | yes |
| Codex | `composerMovesDown` + `›` | yes (same guard; safer) |
| Claude / Flashsky / OpenCode | `anchorCellClears` | no |

## Behavior

In `deliverPasteAndSubmit`, after `_pollCrUntilAnchorClears` returns
`crStuck` and `reinject < maxReinject`:

1. `syncDisplayGrid`
2. Evaluate `shouldSkipReinjectAfterCrStuck` with
   `port.crAckConfig.strategy`, `port.isComposerChromeEmpty(...)`, and
   whether `locateNeedle` still finds the paste needle
3. If skip → log (optional `appLogger.i`) and return `submitted`
4. Else continue reinject as today

`nudgeCrUntilClear` / outer mailbox retry paths are unchanged in v1. Only
the `deliverPasteAndSubmit` reinject gate changes.

## Architecture

Three layers — keep policy testable without a fake PTY:

| Layer | Responsibility |
|-------|----------------|
| Grid probe | `isComposerChromeEmpty(grid, …)` — pure mirror-grid read |
| Delivery port | Expose `isComposerChromeEmpty({scanRows})` on `FullscreenPtyDeliveryPort` (production + fakes) |
| Reinject policy | Pure `shouldSkipReinjectAfterCrStuck({strategy, composerChromeEmpty, needleStillVisible})` — **only** `composerMovesDown` + both flags true skips |
| Automation | On `crStuck` before reinject: sync → evaluate policy → `submitted` or continue |

Do **not** bury the dual gate as an anonymous `if` inside the reinject loop
without a named policy helper — this path is shared by Chat continue, landing
seed, and TeamBus doorbell delivery.

## Probe API

```dart
/// Bottommost composer chrome row is prefix-only (no staged body).
bool isComposerChromeEmpty(
  TerminalScreenGrid grid, {
  required String composerPrefix,
  int scanRows = 24,
});

/// Whether deliverPasteAndSubmit may treat crStuck as success (no reinject).
bool shouldSkipReinjectAfterCrStuck({
  required FullscreenCrAckStrategy strategy,
  required bool composerChromeEmpty,
  required bool needleStillVisible,
});
```

Needle visibility reuses `locateNeedle` / `isTextVisible` on the port.

## Tests (required — core delivery path)

**Probe** (`fullscreen_input_screen_probe_test.dart`):

- Empty: `→` / `›` alone, or prefix + trailing spaces → true
- Staged: `→ A`, `› hello` → false
- No composer row in window → false (cannot claim empty)
- Whitespace-only after prefix → true

**Policy** (same file or small dedicated test):

- Matrix: strategy × empty × needleVisible → skip / don’t skip
- `anchorCellClears` never skips regardless of flags

**Automation** (`fullscreen_pty_automation_test.dart`):

1. **Guard fires (Cursor-shaped):** CR ACK never true; after CR composer
   empty + needle still locatable as transcript → `submitted`,
   `pasteCount == 1` (no reinject)
2. **Still reinjects when staged:** body remains on composer after failed
   ACK → second paste, then success
3. **Empty composer, needle gone:** reinject (recover swallowed CR)
4. **`anchorCellClears` unchanged:** crStuck still reinjects; guard never
   short-circuits that strategy
5. Existing Cursor transcript-after-submit + resume-same-text cases stay green

**Integration** (`cursor_agent_deliver_integration_test.dart`):

- Keep existing `hello` smoke at 24×80 and 52×80
- Add short-needle case: deliver `"A"` once → `submitted`; optionally a
  second deliver of `"A"` also `submitted` (regression: must not hang /
  crStuck from false-positive staged history). Tagged `integration &&
  linux-pty` as today.

## Risks

| Risk | Mitigation |
|------|------------|
| False `submitted` when CR swallowed and composer empty | Require needle still visible near composer |
| Codex false positive | Same dual condition; empty `›` + needle residual is the post-submit shape |
| Guard never fires (prefix mismatch) | No worse than today; duplicates remain until prefix fixed |

## Out of follow-up

- Scheme B: single CR for `composerMovesDown` ACK poll
- Logging when guard short-circuits reinject (`appLogger.i`) — optional in
  implementation if useful for field diagnosis
