# Cursor PTY reinject guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `deliverPasteAndSubmit` from re-pasting a message that Cursor/Codex already committed when CR grid-ACK fails (`composerMovesDown`).

**Architecture:** Pure grid probe (`isComposerChromeEmpty`) + pure policy (`shouldSkipReinjectAfterCrStuck`) + port method + one gate in the reinject loop. Unit-test policy/probe exhaustively; automation fakes cover the duplicate-submit bug; integration adds a short-needle Cursor deliver case.

**Tech Stack:** Dart / Flutter test (`flutter_test`), existing `FullscreenPtyAutomation` + `TerminalFullscreenPtyPort`.

## Global Constraints

- Guard applies only to `FullscreenCrAckStrategy.composerMovesDown` (Cursor + Codex).
- Skip reinject only when **both** composer chrome empty **and** paste needle still visible.
- Do not change `anchorCellClears`, Chat pending merge, or transcript parsers.
- TDD: failing tests before production code.
- Do not commit unless the user asks.

---

## File map

| File | Role |
|------|------|
| `client/lib/services/terminal/fullscreen_reinject_guard.dart` | Pure `shouldSkipReinjectAfterCrStuck` |
| `client/lib/services/terminal/fullscreen_input_screen_probe.dart` | `isComposerChromeEmpty` |
| `client/lib/services/terminal/fullscreen_pty_delivery_port.dart` | Port API |
| `client/lib/services/terminal/terminal_fullscreen_pty_port.dart` | Production port |
| `client/lib/services/terminal/fullscreen_pty_automation.dart` | Reinject gate |
| `client/test/services/terminal/support/fake_fullscreen_pty_delivery_port.dart` | Fake + new method |
| `client/test/services/terminal/fullscreen_input_screen_probe_test.dart` | Probe tests |
| `client/test/services/terminal/fullscreen_reinject_guard_test.dart` | Policy matrix |
| `client/test/services/terminal/fullscreen_pty_automation_test.dart` | Automation scenarios |
| `client/test/integration/cursor_agent_deliver_integration_test.dart` | Short-needle smoke |

---

### Task 1: Pure reinject policy + matrix tests

**Files:**
- Create: `client/lib/services/terminal/fullscreen_reinject_guard.dart`
- Create: `client/test/services/terminal/fullscreen_reinject_guard_test.dart`

**Interfaces:**
- Produces: `bool shouldSkipReinjectAfterCrStuck({required FullscreenCrAckStrategy strategy, required bool composerChromeEmpty, required bool needleStillVisible})`

- [ ] **Step 1: Write failing policy tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_reinject_guard.dart';

void main() {
  group('shouldSkipReinjectAfterCrStuck', () {
    test('composerMovesDown skips only when empty and needle visible', () {
      expect(
        shouldSkipReinjectAfterCrStuck(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          composerChromeEmpty: true,
          needleStillVisible: true,
        ),
        isTrue,
      );
    });

    for (final case_ in [
      (empty: false, needle: true),
      (empty: true, needle: false),
      (empty: false, needle: false),
    ]) {
      test(
        'composerMovesDown does not skip empty=${case_.empty} needle=${case_.needle}',
        () {
          expect(
            shouldSkipReinjectAfterCrStuck(
              strategy: FullscreenCrAckStrategy.composerMovesDown,
              composerChromeEmpty: case_.empty,
              needleStillVisible: case_.needle,
            ),
            isFalse,
          );
        },
      );
    }

    for (final strategy in [
      FullscreenCrAckStrategy.anchorCellClears,
      FullscreenCrAckStrategy.timed,
    ]) {
      test('$strategy never skips even when empty+needle', () {
        expect(
          shouldSkipReinjectAfterCrStuck(
            strategy: strategy,
            composerChromeEmpty: true,
            needleStillVisible: true,
          ),
          isFalse,
        );
      });
    }
  });
}
```

- [ ] **Step 2: Run tests — expect fail (library missing)**

```bash
cd client && flutter test test/services/terminal/fullscreen_reinject_guard_test.dart
```

Expected: compile/import failure for `fullscreen_reinject_guard.dart`

- [ ] **Step 3: Implement policy**

```dart
import 'fullscreen_cr_ack_config.dart';

bool shouldSkipReinjectAfterCrStuck({
  required FullscreenCrAckStrategy strategy,
  required bool composerChromeEmpty,
  required bool needleStillVisible,
}) {
  if (strategy != FullscreenCrAckStrategy.composerMovesDown) return false;
  return composerChromeEmpty && needleStillVisible;
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd client && flutter test test/services/terminal/fullscreen_reinject_guard_test.dart
```

---

### Task 2: `isComposerChromeEmpty` probe + tests

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_input_screen_probe.dart`
- Modify: `client/test/services/terminal/fullscreen_input_screen_probe_test.dart`

**Interfaces:**
- Consumes: `bottomComposerChromeRow`, `_rowStartsWith` / `_logicalRowText` patterns already in file
- Produces: `bool isComposerChromeEmpty(TerminalScreenGrid grid, {required String composerPrefix, int scanRows = 24})`

- [ ] **Step 1: Write failing probe tests** (append to existing test file; reuse `_FakeGrid`)

```dart
  test('isComposerChromeEmpty true for prefix-only cursor row', () {
    final grid = _FakeGrid.fromRows([
      'A',
      '→ ',
    ]);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '→', scanRows: 8),
      isTrue,
    );
  });

  test('isComposerChromeEmpty false when body follows prefix', () {
    final grid = _FakeGrid.fromRows(['→ A']);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '→', scanRows: 8),
      isFalse,
    );
  });

  test('isComposerChromeEmpty false when no composer row', () {
    final grid = _FakeGrid.fromRows(['just history']);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '→', scanRows: 8),
      isFalse,
    );
  });

  test('isComposerChromeEmpty true for codex prefix with trailing spaces', () {
    final grid = _FakeGrid.fromRows(['›     ']);
    expect(
      isComposerChromeEmpty(grid, composerPrefix: '\u203a', scanRows: 8),
      isTrue,
    );
  });
```

- [ ] **Step 2: Run — expect fail (undefined function)**

```bash
cd client && flutter test test/services/terminal/fullscreen_input_screen_probe_test.dart --name isComposerChromeEmpty
```

- [ ] **Step 3: Implement**

Use `bottomComposerChromeRow`; read logical row text; after trimming left, require `startsWith(prefix)`; body = remainder after prefix trimmed — empty ⇒ true. If no composer row ⇒ false.

- [ ] **Step 4: Run — expect pass**

---

### Task 3: Port API + fake + production wire-up

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_pty_delivery_port.dart`
- Modify: `client/lib/services/terminal/terminal_fullscreen_pty_port.dart`
- Modify: `client/test/services/terminal/support/fake_fullscreen_pty_delivery_port.dart`
- Modify: any other `implements FullscreenPtyDeliveryPort` (grep; update `_CursorTranscriptAfterSubmitPort` in automation test)

**Interfaces:**
- Produces: `bool isComposerChromeEmpty({int scanRows = 24})` on the port
- Fake: configurable `composerChromeEmpty` flag (default: `staged == null || staged!.trim().isEmpty` when prefix strategy needs it — for default fake with `anchorCellClears`, return `staged == null`)

- [ ] **Step 1: Add method to interface + implement production via probe**

```dart
bool isComposerChromeEmpty({int scanRows = 24});
```

Production:

```dart
@override
bool isComposerChromeEmpty({int scanRows = 24}) {
  final prefix = _crAckConfig.composerPrefix?.trim();
  if (prefix == null || prefix.isEmpty) return false;
  return isComposerChromeEmptyGrid( // or same name via import prefix
    _probe.gridOrWhatever,
    ...
  );
}
```

Prefer calling the top-level probe with the same grid accessor used by other probe methods — follow `TerminalScreenProbeController` patterns already used by `isFullscreenPromptSubmitted`.

- [ ] **Step 2: Update all fakes / test ports to compile**

- [ ] **Step 3: `flutter analyze` on touched files / `flutter test` existing automation tests still pass**

```bash
cd client && flutter test test/services/terminal/fullscreen_pty_automation_test.dart
```

---

### Task 4: Automation reinject gate (TDD)

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_pty_automation.dart`
- Modify: `client/test/services/terminal/fullscreen_pty_automation_test.dart`
- Modify: fake / dedicated fake port for “ACK never, but empty composer + transcript needle”

**Interfaces:**
- Consumes: `shouldSkipReinjectAfterCrStuck`, `port.isComposerChromeEmpty`, `port.locateNeedle`

- [ ] **Step 1: Add failing automation tests**

```dart
test('skips reinject when composerMovesDown crStuck but empty+needle', () async {
  final port = _ComposerMovesDownStuckButCommittedPort(text: 'A');
  final outcome = await automation.deliverPasteAndSubmit(
    port: port,
    text: 'A',
    pasteSettle: Duration.zero,
  );
  expect(outcome, FullscreenPtyDeliveryOutcome.submitted);
  expect(port.pasteCount, 1);
});

test('reinjects when composerMovesDown crStuck and body still staged', () async {
  // first CR: ACK false, composer still has body; second paste then ACK
});

test('reinjects when composer empty but needle gone', () async {
  // after CR: empty composer, locateNeedle null → reinject
});

test('anchorCellClears crStuck still reinjects (guard inert)', () async {
  // default fake with crsToClear high enough to force reinject path...
});
```

Design `_ComposerMovesDownStuckButCommittedPort`:
- `crAckConfig` = Cursor strategy + `→`
- After first `submitCr`: keep `transcript = text`, `stagedOnComposer = false`, `isSubmittedAfterCr` always false
- `locateNeedle` finds text in transcript
- `isComposerChromeEmpty` true after first CR
- `pasteText` increments pasteCount and stages

- [ ] **Step 2: Run — expect fail (pasteCount == 2 today)**

```bash
cd client && flutter test test/services/terminal/fullscreen_pty_automation_test.dart --name 'skips reinject'
```

Expected: `pasteCount` 2 (or `crStuck`), not 1 + submitted

- [ ] **Step 3: Gate in `deliverPasteAndSubmit` on `crStuck` before `continue`**

```dart
case FullscreenPtyDeliveryOutcome.crStuck:
  if (reinject < maxReinject) {
    await port.syncDisplayGrid();
    final skip = shouldSkipReinjectAfterCrStuck(
      strategy: port.crAckConfig.strategy,
      composerChromeEmpty: port.isComposerChromeEmpty(
        scanRows: _probeScanRows(port),
      ),
      needleStillVisible: port.locateNeedle(
            needle,
            scanRows: _probeScanRows(port),
          ) !=
          null,
    );
    if (skip) {
      appLogger.i(
        '[pty] skip-reinject composerMovesDown empty+needle '
        'textChars=${text.length}',
      );
      return FullscreenPtyDeliveryOutcome.submitted;
    }
    continue;
  }
  return FullscreenPtyDeliveryOutcome.crStuck;
```

Also apply the same check when `reinject == maxReinject` before returning `crStuck`? Spec: skip when about to reinject **or** when exhausted after a successful-looking first commit. **Yes — also before final `crStuck` return** so the last failed ACK still reports `submitted` if empty+needle (otherwise callers treat as delivery failure after a successful agent receive).

- [ ] **Step 4: Run full automation + policy + probe tests**

```bash
cd client && flutter test \
  test/services/terminal/fullscreen_reinject_guard_test.dart \
  test/services/terminal/fullscreen_input_screen_probe_test.dart \
  test/services/terminal/fullscreen_pty_automation_test.dart
```

---

### Task 5: Cursor integration short-needle case

**Files:**
- Modify: `client/test/integration/cursor_agent_deliver_integration_test.dart`

- [ ] **Step 1: Add test** `deliverPasteAndSubmit short A then second A` at 80×52 (tall viewport, where ACK is flaky)

Both delivers must return `submitted`. Print grid on failure.

- [ ] **Step 2: Run when `cursor-agent` on PATH**

```bash
cd client && LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/cursor_agent_deliver_integration_test.dart \
  --tags "integration && linux-pty"
```

If env lacks binary/bundle, mark skipped as existing tests do — unit suite remains the merge gate.

---

### Task 6: Verify

- [ ] **Step 1:**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test \
  test/services/terminal/fullscreen_reinject_guard_test.dart \
  test/services/terminal/fullscreen_input_screen_probe_test.dart \
  test/services/terminal/fullscreen_pty_automation_test.dart
```

- [ ] **Step 2:** Confirm no commit unless user requests.

---

## Spec coverage checklist

| Spec item | Task |
|-----------|------|
| Pure policy helper | 1 |
| `isComposerChromeEmpty` probe | 2 |
| Port exposure | 3 |
| Reinject gate + final crStuck soften | 4 |
| Probe / policy / automation tests | 1–4 |
| Integration short needle | 5 |
| Non-goals (Chat/transcript/timing) | untouched |
