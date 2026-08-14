# Fullscreen Composer Region ACK — Design

Date: 2026-08-13

## Problem

Sending a very short message (e.g. a single `"1"`) from the chat page to a
full-screen TUI CLI (opencode, claude, cursor, codex, flashskyai) can cause
**duplicate user messages**: one send visibly produces many `"1"` user
messages in the chat.

Verified reproduction (opencode, `app_2026-08-13.log`):

```
19:05:41.557  pty-inject chars=1 preview=1
19:05:49.747  prompt-submit acked           ← hook ACK 8s later
19:06:01.730  pty-automation-acked-skip-retry outcome=crStuck
```

Root cause chain:

1. **Non-distinctive needle.** `PtyAutomationNeedle.forText("1")` returns the
   single character `"1"`. The paste-ACK probe
   (`locateFullscreenPromptNeedle`, `fullscreen_input_screen_probe.dart:53`)
   scans the bottom N visible rows for that substring anywhere — a `"1"` in a
   timestamp, option number, or transcript line matches before the real
   staged input does. The automation anchors to a **false positive** cell.
2. **Anchor never clears → crStuck despite successful submit.** The real CR
   *did* submit the message; the probe's anchor cell (some other `"1"` on
   screen) never clears, so `isSubmittedAfterCr` reports `crStuck`
   (`fullscreen_pty_automation.dart:136-150`).
3. **Reinject + retry storm re-pastes the same text.** `deliverPasteAndSubmit`
   re-enters its clear→paste→CR loop up to `reinjectMaxAttempts` times
   (`fullscreen_pty_automation.dart:112-151`), and `MemberPtyInjectService`
   schedules 5s-interval retries up to 6 attempts (`member_pty_inject_service
   .dart:213-244`, `TeamBus.maxPtyNotifyAttempts`). Each re-paste submits
   another real user message → the chat shows many `"1"` user messages.
4. **ACK can't stop the in-flight loop.** `PromptSubmitAckTracker`
   (`prompt_submit_ack_tracker.dart`, committed today) cancels the *retry
   queue* when the CLI `UserPromptSubmit` hook event arrives — but the
   reinject loop inside `deliverPasteAndSubmit` never consults it; it only
   checks `port.isAborted`. Long messages survive because their needle is
   distinctive; short text systematically triggers the storm.

## Goals

1. Stop duplicate user messages for short text (single char / digits).
2. Make paste-ACK and CR-ACK generic across all five CLIs instead of
   opencode-specific hacks.
3. Keep probe cost in the same order of magnitude as today (bottom-window
   scans only; no full-grid scans, no engine changes).
4. No backward-compatibility layer — replace the strategy enum outright.

## Confirmed UX/architecture decisions

1. Generalize the "composer box" (opencode's bordered input) into a
   **Composer Region protocol**: every CLI's staged-input area is described
   by prefixes / border characters / submit semantics on the existing
   `TerminalBehaviorCapability`. opencode's box is just one region shape.
2. **Submit semantics converge** to region semantics:
   `regionCleared` (claude/flashskyai/opencode — was `anchorCellClears`),
   `regionMovedDown` (cursor/codex — was `composerMovesDown`),
   `timed` (unused, kept as a legal value).
3. **Primary CR ACK = original region no longer contains the needle**;
   "needle appears elsewhere" (the transcript message box) is a secondary
   signal only.
4. **ACK-aware reinject**: the in-flight reinject loop consults the prompt-
   submit ACK tracker and returns `submitted` immediately once acked.
5. Region is **re-located after every `syncDisplayGrid`** (paste grows the
   box; bottom border moves) — correctness over micro-optimization.

## Design

### 1. Capability layer — region spec replaces strategy config

New file `client/lib/services/cli/registry/capabilities/terminal_composer_region.dart`:

```dart
enum ComposerSubmitSemantics { regionCleared, regionMovedDown, timed }

final class ComposerBorderSpec {
  const ComposerBorderSpec({
    this.left = const [],     // 左边框候选：┃ │
    this.bottom = const [],   // 底边框候选：▀ ─
    this.corner = const [],   // 底角候选：  ╹ ╰ └
  });
  final List<String> left, bottom, corner;
}

final class FullscreenComposerRegionSpec {
  const FullscreenComposerRegionSpec({
    required this.submitSemantics,
    this.prefixes = const [],
    this.border = const ComposerBorderSpec(),
  });
  final ComposerSubmitSemantics submitSemantics;
  final List<String> prefixes;   // 行首前缀候选
  final ComposerBorderSpec border;
}
```

`TerminalBehaviorCapability` replaces `fullscreenComposerPrefix` /
`fullscreenCrAckStrategy` with one field:
`FullscreenComposerRegionSpec get composerRegion`.

Per-CLI config (`terminal_behavior.dart` under each CLI capability dir):

| CLI | prefixes | border | semantics |
|-----|----------|--------|-----------|
| claude | `['❯']` | — | regionCleared |
| flashskyai | `['❯']` | — | regionCleared |
| cursor | `['→']` | — | regionMovedDown |
| codex | `['›']` | — | regionMovedDown |
| opencode | `['┃']` | left `['┃','│']`, bottom `['▀','─']`, corner `['╹','╰','└']` | regionCleared |

`FullscreenCrAckConfig` is deleted; `FullscreenCrAckStrategy` enum is
deleted; `fullscreen_cr_ack_config.dart` is removed.

### 2. Probe layer — generic region parsing (pure functions)

`client/lib/services/terminal/fullscreen_input_screen_probe.dart`:

```dart
final class ComposerRegion {
  final int topRow, bottomRow, leftCol, rightCol;
}

/// Bottom-window scan: locate the staged-input region for [spec].
ComposerRegion? locateComposerRegion(
  TerminalScreenGrid grid,
  FullscreenComposerRegionSpec spec, {
  int scanRows = 24,
});

/// Multi-line (soft-wrap aware) needle match inside the region only.
bool regionContainsNeedle(
  TerminalScreenGrid grid,
  ComposerRegion region,
  String needle,
);

/// Region interior has no staged input (prefix-only rows, empty box).
bool isComposerRegionEmpty(
  TerminalScreenGrid grid,
  ComposerRegion region,
  FullscreenComposerRegionSpec spec,
);

/// Needle present somewhere outside the region (transcript / message box).
bool needleAppearsOutsideRegion(
  TerminalScreenGrid grid,
  ComposerRegion region,
  String needle, {
  int scanRows = 24,
});
```

**Locate algorithm** (bottom-up window scan, O(rows×cols)):

1. Find the bottom border row in the window: a row whose content starts with
   a `border.corner` or `border.bottom` char at some column **and** a
   `border.left` char appears in the same column on rows above.
2. If a left border column exists, walk upward collecting consecutive rows
   with that column char → the region rectangle (opencode's box).
3. Otherwise, find the lowest prefix row (`spec.prefixes`); the region is that
   row plus consecutive prefix rows above it (claude/flashskyai/cursor/codex).
4. No border and no prefix → return `null`; automation falls back to the
   existing whole-window needle search.

`regionContainsNeedle` reuses the existing soft-wrap matcher
(`_matchesNeedleAt`, `fullscreen_input_screen_probe.dart:252`) restricted to
the region's row/column bounds — short needles like `"1"` are matched inside
the region interior, never against transcript rows.

### 3. Automation layer — unified submit semantics

`client/lib/services/terminal/fullscreen_pty_automation.dart`:

```dart
// deliverPasteAndSubmit loop:
for (var reinject = 0; reinject <= maxReinject; reinject++) {
  if (port.isAborted) return aborted;
  if (port.isAcked) return submitted;        // NEW: ACK-aware reinject
  await port.syncDisplayGrid();
  final region = port.locateComposerRegion(); // re-locate every round
  ...
}
```

- **Paste ACK** = `regionContainsNeedle(region, needle)`; when the region is
  null, fall back to the current window search (backward behavior preserved
  by the fallback, not by a compat layer).
- **CR ACK** per semantics:
  - `regionCleared`: `!regionContainsNeedle(region, needle)` — the original
    position cleared (primary signal). `needleAppearsOutsideRegion` is
    checked as a secondary signal and logged.
  - `regionMovedDown`: a new prefix row appears below the region
    (equivalent to the old `composerMovesDown` check).
  - `timed`: settle-based, no polling (unchanged).

`_shouldSkipReinject` / `fullscreen_reinject_guard.dart` stays, keyed off
`regionMovedDown` semantics (codex only), same condition shape.

### 4. ACK-aware reinject plumbing

- `FullscreenPtyDeliveryPort` (`fullscreen_pty_delivery_port.dart`) adds:
  `bool get isAcked;` and `ComposerRegion? locateComposerRegion();`
- `TerminalFullscreenPtyPort` (`terminal_fullscreen_pty_port.dart`)
  implements both: `isAcked` delegates to the injected
  `PromptSubmitAckTracker.isAcked(sessionId, memberId)`; region comes from
  `TerminalScreenProbeController` → `fullscreen_input_screen_probe`.
- `MemberPtyInjectService` already passes `ackTracker` through to
  `TabMemberPtyDelivery`; the port constructor gains the session/member ids
  and tracker reference so `isAcked` works in-flight.

This closes both re-paste paths:
- in-flight reinject loop → returns `submitted` on ack;
- retry queue → existing `_handleOutcome` `isAcked` check
  (`member_pty_inject_service.dart:227-237`) already skips scheduling.

### 5. Probe controller surface

`TerminalScreenProbeController` (`terminal_screen_probe_controller.dart`):
- add `ComposerRegion? locateComposerRegion(FullscreenComposerRegionSpec spec,
  {int scanRows})`;
- keep `locateFullscreenPromptNeedle` etc. as-is for non-region fallback and
  tests; remove `bottomComposerChromeRow` / `isComposerChromeEmpty` /
  `isFullscreenPromptSubmitted` consumers migrate to region APIs.

## Verification

1. **Probe unit tests** (`fullscreen_input_screen_probe_test.dart`): region
   locate for all five shapes (opencode box with `┃`/`▀`/`╹`, claude `❯`
   prefix rows, cursor `→`, codex `›`), `regionContainsNeedle` with a
   single-char needle, region-cleared-after-CR, needle-appears-outside.
2. **Automation unit tests** (`fullscreen_pty_automation_test.dart`): fake
   port sets `isAcked` mid-loop → `deliverPasteAndSubmit` returns
   `submitted` without re-paste; `regionCleared`/`regionMovedDown`/`timed`
   semantics.
3. **Inject service tests**: ACK-first crStuck outcome skips retry
   (existing `member_pty_inject_service_test.dart` stays green).
4. **Integration** (`opencode_deliver_integration_test.dart`): add a
   single-char `"1"` delivery case asserting exactly one submission; keep the
   existing long-text case.
5. Regression: `cd client && flutter analyze --no-fatal-infos
   --no-fatal-warnings && flutter test --exclude-tags integration`.

## Files

- Add `services/cli/registry/capabilities/terminal_composer_region.dart`
  (spec types + semantics enum)
- Edit `services/cli/registry/capabilities/terminal_behavior_capability.dart`
  (`composerRegion` replaces prefix/strategy)
- Edit per-CLI `terminal_behavior.dart`: claude, flashskyai, cursor, codex,
  opencode
- Delete `services/terminal/fullscreen_cr_ack_config.dart`
- Edit `services/terminal/fullscreen_input_screen_probe.dart` (region
  parsing), `terminal_screen_probe_controller.dart`,
  `terminal_fullscreen_pty_port.dart`, `fullscreen_pty_delivery_port.dart`
  (port interface), `fullscreen_pty_automation.dart` (semantics + ACK-aware
  loop), `fullscreen_reinject_guard.dart`
- Edit `cubits/chat/tab_member_pty_delivery.dart` (port construction passes
  tracker/session ids)
- Tests: `fullscreen_input_screen_probe_test.dart`,
  `fullscreen_pty_automation_test.dart`, `fullscreen_reinject_guard_test.dart`,
  `opencode_deliver_integration_test.dart` (+ short-text case)

## Known trade-offs

- Region detection depends on opencode keeping its `┃`/`▀` box chrome; a
  future TUI redesign would degrade to the prefix fallback, not to
  duplicates (fallback returns null → old window search).
- `needleAppearsOutsideRegion` is advisory (message box may scroll out of
  view); the region-cleared signal is authoritative.
- No backward-compat: `FullscreenCrAckConfig` and callers are deleted in the
  same change; all tests migrate with it.
