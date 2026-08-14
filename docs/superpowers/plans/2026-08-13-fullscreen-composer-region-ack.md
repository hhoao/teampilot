# Fullscreen Composer Region ACK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `FullscreenCrAckConfig`/`FullscreenCrAckStrategy` machinery with a generic **Composer Region protocol** (prefix/border-declared staged-input regions + region-cleared/region-moved-down/timed submit semantics) so short messages like `"1"` are ACKed inside the composer region — ending the duplicate-user-message retry storm.

**Architecture:** `TerminalBehaviorCapability` declares a `FullscreenComposerRegionSpec` (prefix candidates, optional border chars, submit semantics). The probe layer (`fullscreen_input_screen_probe.dart`) locates the region rectangle on the mirror grid with pure functions; `FullscreenPtyAutomation` ACKs paste inside the region and CR by region-cleared (or region-moved-down / timed). The in-flight reinject loop is already ACK-aware in the working tree (uncommitted — Task 0 lands it first).

**Tech Stack:** Dart/Flutter, `flutter_alacritty` mirror grid (`codepointAt`/`flagsAt`), existing test harnesses `_FakeGrid` / `FakeFullscreenPtyDeliveryPort`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-13-fullscreen-composer-region-ack-design.md` (commit `47612103`, with cursor moved to `regionMovedDown`).
- **No backward-compat layer**: delete `fullscreen_cr_ack_config.dart`, `FullscreenCrAckConfig`, `FullscreenCrAckStrategy` outright; migrate every caller/test in the same change.
- Per-CLI semantics: claude/flashskyai/opencode = `regionCleared`; cursor/codex = `regionMovedDown`; `timed` kept as legal value (no CLI uses it).
- opencode border chars (verified live): left `┃` U+2503 (candidates `┃│`), bottom `▀` U+2580 (candidates `▀─`), bottom-left corner `╹` U+2579 (candidates `╹╰└`).
- Probe scans stay bottom-window (`scanRows`, default 24) — never full-grid, no engine changes.
- Region is re-located after every `syncDisplayGrid` round.
- Working tree already contains an **uncommitted** ACK-aware reinject implementation (`fullscreen_pty_automation.dart`, `member_pty_inject_service.dart`, `tab_member_pty_delivery.dart`, `fullscreen_pty_automation_test.dart`, `member_pty_inject_service_test.dart`, `member_pty_inject_abort_test.dart`). Task 0 commits it **before** any region work. The `opencode/capabilities/config_profile.dart` external-directories change is **unrelated** — do not commit or touch it.
- Verification before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 0: Land the uncommitted ACK-aware reinject

**Files:**
- Commit (already modified in working tree): `client/lib/services/terminal/fullscreen_pty_automation.dart`, `client/lib/services/terminal/member_pty_inject_service.dart`, `client/lib/cubits/chat/tab_member_pty_delivery.dart`, `client/test/services/terminal/fullscreen_pty_automation_test.dart`, `client/test/services/terminal/member_pty_inject_service_test.dart`, `client/test/services/terminal/member_pty_inject_abort_test.dart`
- Do NOT touch: `client/lib/services/cli/opencode/capabilities/config_profile.dart` (unrelated external-directories work)

**Interfaces:**
- Produces: `FullscreenPtyAutomation.deliverPasteAndSubmit({..., bool Function()? isAcked})`, `.retry({..., bool Function()? isAcked})`, `MemberPtyInjectService.deliver/retry(..., bool Function()? isAcked)` — all already wired in the working tree. Later tasks keep these signatures.

- [ ] **Step 1: Verify the working-tree changes compile and tests pass**

Run: `cd client && flutter test test/services/terminal/fullscreen_pty_automation_test.dart test/services/terminal/member_pty_inject_service_test.dart test/services/terminal/member_pty_inject_abort_test.dart`
Expected: PASS (the uncommitted ACK-aware tests: "skips re-paste entirely when hook already acked", "hook ACK during crStuck poll cancels reinject").

- [ ] **Step 2: Stage only the ACK-aware files and commit**

```bash
cd client
git add lib/services/terminal/fullscreen_pty_automation.dart \
  lib/services/terminal/member_pty_inject_service.dart \
  lib/cubits/chat/tab_member_pty_delivery.dart \
  test/services/terminal/fullscreen_pty_automation_test.dart \
  test/services/terminal/member_pty_inject_service_test.dart \
  test/services/terminal/member_pty_inject_abort_test.dart
cd ..
git commit -m "fix(pty): ACK-aware reinject cancels duplicate re-paste storm"
```

Verify `git status` still shows only the unrelated `opencode/capabilities/config_profile.dart` + its test modified (untouched).

---

### Task 1: Add the Composer Region spec types

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/terminal_composer_region.dart`
- Test: `client/test/services/cli/registry/capabilities/terminal_composer_region_test.dart`

**Interfaces:**
- Produces (consumed by Tasks 2–6):
  - `enum ComposerSubmitSemantics { regionCleared, regionMovedDown, timed }`
  - `final class ComposerBorderSpec { const ComposerBorderSpec({this.left = const [], this.bottom = const [], this.corner = const []}); final List<String> left; final List<String> bottom; final List<String> corner; }`
  - `final class FullscreenComposerRegionSpec { const FullscreenComposerRegionSpec({required this.submitSemantics, this.prefixes = const [], this.border = const ComposerBorderSpec()}); final ComposerSubmitSemantics submitSemantics; final List<String> prefixes; final ComposerBorderSpec border; }`
  - `const fullscreenDefaultComposerSpec = FullscreenComposerRegionSpec(submitSemantics: ComposerSubmitSemantics.regionCleared);`
  - `const fullscreenTimedComposerSpec = FullscreenComposerRegionSpec(submitSemantics: ComposerSubmitSemantics.timed);`

- [ ] **Step 1: Write the failing test**

`client/test/services/cli/registry/capabilities/terminal_composer_region_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';

void main() {
  test('default spec is regionCleared with empty prefix/border', () {
    expect(fullscreenDefaultComposerSpec.submitSemantics,
        ComposerSubmitSemantics.regionCleared);
    expect(fullscreenDefaultComposerSpec.prefixes, isEmpty);
    expect(fullscreenDefaultComposerSpec.border.left, isEmpty);
    expect(fullscreenDefaultComposerSpec.border.bottom, isEmpty);
    expect(fullscreenDefaultComposerSpec.border.corner, isEmpty);
  });

  test('opencode box spec carries border candidates', () {
    const spec = FullscreenComposerRegionSpec(
      submitSemantics: ComposerSubmitSemantics.regionCleared,
      prefixes: ['\u2503'],
      border: ComposerBorderSpec(
        left: ['\u2503', '\u2502'],
        bottom: ['\u2580', '\u2500'],
        corner: ['\u2579', '\u2570', '\u2514'],
      ),
    );
    expect(spec.prefixes, ['\u2503']);
    expect(spec.border.left, ['\u2503', '\u2502']);
  });

  test('timed spec keeps semantics only', () {
    expect(fullscreenTimedComposerSpec.submitSemantics,
        ComposerSubmitSemantics.timed);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/terminal_composer_region_test.dart`
Expected: FAIL — "not found" (file missing).

- [ ] **Step 3: Write the implementation**

`client/lib/services/cli/registry/capabilities/terminal_composer_region.dart`:

```dart
/// How a full-screen TUI confirms a CR submit on the mirror grid.
enum ComposerSubmitSemantics {
  /// Staged input vanished from the composer region (claude, flashskyai,
  /// opencode — was anchorCellClears).
  regionCleared,

  /// Staged text stays on-screen as history; a new composer region appears
  /// below (cursor, codex — was composerMovesDown).
  regionMovedDown,

  /// Skip grid polling after CR; rely on paste settle timing only.
  timed,
}

/// Candidate border glyphs for boxed composer regions (opencode: `┃`/`▀`/`╹`).
final class ComposerBorderSpec {
  const ComposerBorderSpec({
    this.left = const [],
    this.bottom = const [],
    this.corner = const [],
  });

  final List<String> left;
  final List<String> bottom;
  final List<String> corner;
}

/// Per-CLI staged-input region declaration for full-screen PTY automation.
final class FullscreenComposerRegionSpec {
  const FullscreenComposerRegionSpec({
    required this.submitSemantics,
    this.prefixes = const [],
    this.border = const ComposerBorderSpec(),
  });

  final ComposerSubmitSemantics submitSemantics;

  /// Row-leading prefix candidates that mark composer chrome (`❯`, `→`, `›`,
  /// `┃`, …). The region is the lowest prefix row plus consecutive prefix
  /// rows above it; boxed CLIs also supply [border].
  final List<String> prefixes;

  /// Box border candidates (opencode). When a left-border column is found,
  /// the region is the rectangle spanned by left border + bottom border row.
  final ComposerBorderSpec border;
}

const fullscreenDefaultComposerSpec = FullscreenComposerRegionSpec(
  submitSemantics: ComposerSubmitSemantics.regionCleared,
);

const fullscreenTimedComposerSpec = FullscreenComposerRegionSpec(
  submitSemantics: ComposerSubmitSemantics.timed,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/terminal_composer_region_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/terminal_composer_region.dart client/test/services/cli/registry/capabilities/terminal_composer_region_test.dart
git commit -m "feat(pty): composer region spec types replace strategy enum"
```

---

### Task 2: Migrate TerminalBehaviorCapability + per-CLI behaviors

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/terminal_behavior_capability.dart`
- Modify: `client/lib/services/cli/claude/capabilities/terminal_behavior.dart`, `client/lib/services/cli/flashskyai/capabilities/terminal_behavior.dart`, `client/lib/services/cli/cursor/capabilities/terminal_behavior.dart`, `client/lib/services/cli/codex/capabilities/terminal_behavior.dart`, `client/lib/services/cli/opencode/capabilities/terminal_behavior.dart`

**Interfaces:**
- Consumes: `FullscreenComposerRegionSpec`, `ComposerSubmitSemantics`, `ComposerBorderSpec` (Task 1).
- Produces: `TerminalBehaviorCapability.composerRegion` (getter), deleted `fullscreenCrAckStrategy` / `fullscreenComposerPrefix`.

- [ ] **Step 1: Replace capability interface**

In `terminal_behavior_capability.dart`: remove `import '../../../terminal/fullscreen_cr_ack_config.dart';`; add `import 'terminal_composer_region.dart';`. Delete the `fullscreenCrAckStrategy` and `fullscreenComposerPrefix` getters; add:

```dart
  /// Staged-input region declaration for grid automation (prefix / border /
  /// submit semantics). Replaces the old strategy + prefix pair.
  FullscreenComposerRegionSpec get composerRegion;
```

- [ ] **Step 2: Update the five CLI behaviors**

`claude/capabilities/terminal_behavior.dart` — replace imports and the two getters:

```dart
import '../../registry/capabilities/terminal_composer_region.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';
// ...
  @override
  FullscreenComposerRegionSpec get composerRegion => const FullscreenComposerRegionSpec(
    submitSemantics: ComposerSubmitSemantics.regionCleared,
    prefixes: ['\u276f'],
  );
```

`flashskyai/capabilities/terminal_behavior.dart` — same as claude (`prefixes: ['\u276f']`, regionCleared).

`cursor/capabilities/terminal_behavior.dart` — `regionMovedDown`, `prefixes: ['→']`:

```dart
  @override
  FullscreenComposerRegionSpec get composerRegion => const FullscreenComposerRegionSpec(
    submitSemantics: ComposerSubmitSemantics.regionMovedDown,
    prefixes: ['→'],
  );
```

`codex/capabilities/terminal_behavior.dart` — `regionMovedDown`, `prefixes: ['\u203a']` (same shape as cursor).

`opencode/capabilities/terminal_behavior.dart` — box spec:

```dart
  @override
  FullscreenComposerRegionSpec get composerRegion => const FullscreenComposerRegionSpec(
    submitSemantics: ComposerSubmitSemantics.regionCleared,
    prefixes: ['\u2503'],
    border: ComposerBorderSpec(
      left: ['\u2503', '\u2502'],
      bottom: ['\u2580', '\u2500'],
      corner: ['\u2579', '\u2570', '\u2514'],
    ),
  );
```

Each file: remove `import '../../../terminal/fullscreen_cr_ack_config.dart';`.

- [ ] **Step 3: Verify compile**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors **only** in files not yet migrated (probe/automation/port/tests reference deleted members — Tasks 3–6 fix them). Do not fix them here.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/terminal_behavior_capability.dart client/lib/services/cli/*/capabilities/terminal_behavior.dart
git commit -m "feat(cli): composerRegion spec on TerminalBehaviorCapability"
```

---

### Task 3: Region parsing in the probe layer

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_input_screen_probe.dart`
- Test: `client/test/services/terminal/fullscreen_input_screen_probe_test.dart`

**Interfaces:**
- Consumes: `FullscreenComposerRegionSpec`, `ComposerBorderSpec`, `ComposerSubmitSemantics` (Task 1).
- Produces:
  - `final class ComposerRegion { final int topRow, bottomRow, leftCol, rightCol; }`
  - `ComposerRegion? locateComposerRegion(TerminalScreenGrid grid, FullscreenComposerRegionSpec spec, {int scanRows = 24})`
  - `bool regionContainsNeedle(TerminalScreenGrid grid, ComposerRegion region, String needle)`
  - `bool isComposerRegionEmpty(TerminalScreenGrid grid, ComposerRegion region, FullscreenComposerRegionSpec spec)`
  - `bool needleAppearsOutsideRegion(TerminalScreenGrid grid, ComposerRegion region, String needle, {int scanRows = 24})`
  - Keeps existing `locateFullscreenPromptNeedle` / `locateCollapsedPasteNeedle` / `isFullscreenPromptAtAnchor` / `bottomComposerChromeRow` / `isComposerChromeEmpty` / `isFullscreenPromptSubmitted` (still used by the fallback path and migrated tests until Task 5).

- [ ] **Step 1: Write failing tests (region locate + needle scoping)**

Append to `fullscreen_input_screen_probe_test.dart` (import
`package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart`):

```dart
  group('locateComposerRegion', () {
    const opencodeSpec = FullscreenComposerRegionSpec(
      submitSemantics: ComposerSubmitSemantics.regionCleared,
      prefixes: ['\u2503'],
      border: ComposerBorderSpec(
        left: ['\u2503', '\u2502'],
        bottom: ['\u2580', '\u2500'],
        corner: ['\u2579', '\u2570', '\u2514'],
      ),
    );

    test('finds opencode box rectangle from left border + bottom border', () {
      final lines = List<String>.filled(10, '');
      lines[6] = '                    \u2503';
      lines[7] = '                    \u2503  1';
      lines[8] = '                    \u2503  Build \u00b7 max';
      lines[9] = '                    \u2579\u2580\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);

      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10);
      expect(region, isNotNull);
      expect(region!.leftCol, 20);
      expect(region.bottomRow, 9);
      expect(region.topRow, lessThanOrEqualTo(6));
    });

    test('finds prefix-only region for claude', () {
      final lines = List<String>.filled(8, '');
      lines[5] = '\u276f  hello';
      lines[6] = '\u276f ';
      final grid = _FakeGrid.fromRows(lines);
      const spec = FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u276f'],
      );

      final region = locateComposerRegion(grid, spec, scanRows: 8);
      expect(region, isNotNull);
      expect(region!.bottomRow, 6);
    });

    test('returns null when no prefix and no border', () {
      final grid = _FakeGrid.fromRows(['just transcript', 'more text']);
      const spec = FullscreenComposerRegionSpec(
        submitSemantics: ComposerSubmitSemantics.regionCleared,
        prefixes: ['\u276f'],
      );
      expect(locateComposerRegion(grid, spec, scanRows: 8), isNull);
    });

    test('regionContainsNeedle scopes a short needle inside the box', () {
      final lines = List<String>.filled(10, '');
      lines[6] = '                    \u2503';
      lines[7] = '                    \u2503  1';
      lines[8] = '                    \u2503';
      lines[9] = '                    \u2579\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10)!;

      expect(regionContainsNeedle(grid, region, '1'), isTrue,
          reason: 'staged "1" inside the box must ACK');
      expect(regionContainsNeedle(grid, region, '99'), isFalse);
    });

    test('regionContainsNeedle ignores the same digit in transcript', () {
      final lines = List<String>.filled(12, '');
      lines[2] = '          1          '; // transcript "1" above the box
      lines[9] = '                    \u2503';
      lines[10] = '                    \u2503';
      lines[11] = '                    \u2579\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 12)!;

      expect(regionContainsNeedle(grid, region, '1'), isFalse,
          reason: 'transcript "1" must not count as staged input');
      expect(needleAppearsOutsideRegion(grid, region, '1', scanRows: 12), isTrue);
    });

    test('isComposerRegionEmpty true when box interior blank', () {
      final lines = List<String>.filled(10, '');
      lines[7] = '                    \u2503';
      lines[9] = '                    \u2579\u2580\u2580\u2580';
      final grid = _FakeGrid.fromRows(lines);
      final region = locateComposerRegion(grid, opencodeSpec, scanRows: 10)!;
      expect(isComposerRegionEmpty(grid, region, opencodeSpec), isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/terminal/fullscreen_input_screen_probe_test.dart`
Expected: FAIL — `locateComposerRegion` / `ComposerRegion` / `regionContainsNeedle` not defined.

- [ ] **Step 3: Write the implementation**

Append to `fullscreen_input_screen_probe.dart` (add import
`../cli/registry/capabilities/terminal_composer_region.dart`):

```dart
/// Rectangular staged-input region on the mirror grid.
final class ComposerRegion {
  const ComposerRegion({
    required this.topRow,
    required this.bottomRow,
    required this.leftCol,
    required this.rightCol,
  });

  final int topRow;
  final int bottomRow;
  final int leftCol;
  final int rightCol;
}

bool _rowHasChar(TerminalScreenGrid grid, int row, int col, String char) {
  if (row < 0 || row >= grid.rows || col < 0 || col >= grid.columns) {
    return false;
  }
  return grid.codepointAt(row, col) == char.codeUnitAt(0);
}

/// Bottom-window scan for the staged-input region declared by [spec].
///
/// Boxed CLIs (opencode): locate the bottom border row (a `border.corner` or
/// `border.bottom` char whose column also carries a `border.left` char on rows
/// above), then walk upward collecting consecutive left-border rows.
/// Prefix CLIs (claude/cursor/codex): lowest prefix row plus consecutive
/// prefix rows above. Returns null when neither shape is found.
ComposerRegion? locateComposerRegion(
  TerminalScreenGrid grid,
  FullscreenComposerRegionSpec spec, {
  int scanRows = 24,
}) {
  if (grid.rows == 0 || grid.columns == 0) return null;
  final windowStart = (grid.rows - scanRows).clamp(0, grid.rows - 1);

  // 1) Boxed shape: find the bottom border row.
  final border = spec.border;
  if (border.left.isNotEmpty || border.bottom.isNotEmpty) {
    for (var r = grid.rows - 1; r >= windowStart; r--) {
      final cornerCol = _cornerColumnOnRow(grid, r, border);
      if (cornerCol < 0) continue;
      final leftCol = _leftBorderColumnAbove(grid, r, cornerCol, border.left);
      if (leftCol < 0) continue;
      var topRow = r;
      while (topRow - 1 >= windowStart &&
          _rowHasChar(grid, topRow - 1, leftCol, border.left.first)) {
        topRow--;
      }
      return ComposerRegion(
        topRow: topRow,
        bottomRow: r,
        leftCol: leftCol,
        rightCol: grid.columns - 1,
      );
    }
  }

  // 2) Prefix shape: lowest prefix row + consecutive rows above.
  if (spec.prefixes.isNotEmpty) {
    for (var r = grid.rows - 1; r >= windowStart; r--) {
      if (_rowHasAnyPrefix(grid, r, spec.prefixes)) {
        var topRow = r;
        while (topRow - 1 >= windowStart &&
            _rowHasAnyPrefix(grid, topRow - 1, spec.prefixes)) {
          topRow--;
        }
        return ComposerRegion(
          topRow: topRow,
          bottomRow: r,
          leftCol: 0,
          rightCol: grid.columns - 1,
        );
      }
    }
  }
  return null;
}

int _cornerColumnOnRow(TerminalScreenGrid grid, int row, ComposerBorderSpec border) {
  for (var col = 0; col < grid.columns; col++) {
    for (final c in border.corner) {
      if (_rowHasChar(grid, row, col, c)) return col;
    }
    for (final b in border.bottom) {
      if (_rowHasChar(grid, row, col, b)) return col;
    }
  }
  return -1;
}

int _leftBorderColumnAbove(
  TerminalScreenGrid grid,
  int bottomRow,
  int col,
  List<String> left,
) {
  for (var r = bottomRow - 1; r >= 0; r--) {
    for (final c in left) {
      if (_rowHasChar(grid, r, col, c)) return col;
    }
  }
  return -1;
}

bool _rowHasAnyPrefix(TerminalScreenGrid grid, int row, List<String> prefixes) {
  final text = _logicalRowText(grid, row).trimLeft();
  for (final p in prefixes) {
    if (text.startsWith(p)) return true;
  }
  return false;
}

/// Soft-wrap-aware needle match restricted to [region]'s row/column bounds.
bool regionContainsNeedle(
  TerminalScreenGrid grid,
  ComposerRegion region,
  String needle,
) {
  if (needle.isEmpty) return false;
  final runes = needle.runes.toList();
  for (var r = region.topRow; r <= region.bottomRow; r++) {
    for (var col = region.leftCol; col <= region.rightCol; col++) {
      if (_isWideSpacer(grid, r, col)) continue;
      if (_matchesNeedleAtBounded(
        grid,
        r,
        col,
        runes,
        maxRow: region.bottomRow,
        maxCol: region.rightCol,
      )) {
        return true;
      }
    }
  }
  return false;
}

bool _matchesNeedleAtBounded(
  TerminalScreenGrid grid,
  int row,
  int startCol,
  List<int> needleRunes, {
  required int maxRow,
  required int maxCol,
}) {
  var r = row;
  var col = startCol;
  for (var i = 0; i < needleRunes.length; i++) {
    final cp = needleRunes[i];
    while (true) {
      if (r > maxRow) return false;
      col = _skipWideSpacers(grid, r, col);
      if (col <= maxCol && !_rowRemainderIsPadding(grid, r, col)) break;
      r += 1;
      col = 0;
      if (r > maxRow) return false;
      if (!_rowHasNonSpaceContent(grid, r) && cp != 0x20) return false;
    }
    if (col > maxCol || grid.codepointAt(r, col) != cp) return false;
    col = _advancePastCell(grid, r, col);
  }
  return true;
}

/// Region interior holds no staged input (prefix-only rows / blank box).
bool isComposerRegionEmpty(
  TerminalScreenGrid grid,
  ComposerRegion region,
  FullscreenComposerRegionSpec spec,
) {
  for (var r = region.topRow; r <= region.bottomRow; r++) {
    final bounds = _trimmedLogicalBounds(grid, r);
    if (bounds == null) continue;
    final text = _logicalText(grid, r, bounds.$1, bounds.$2);
    var isChrome = false;
    for (final p in spec.prefixes) {
      if (text.trimLeft().startsWith(p)) isChrome = true;
    }
    if (isChrome) continue;
    for (final c in spec.border.left) {
      if (text.trim() == c) isChrome = true;
    }
    if (isChrome) continue;
    if (text.trim().isNotEmpty) return false;
  }
  return true;
}

/// Needle present somewhere outside the region (transcript / message box).
bool needleAppearsOutsideRegion(
  TerminalScreenGrid grid,
  ComposerRegion region,
  String needle, {
  int scanRows = 24,
}) {
  final windowStart = (grid.rows - scanRows).clamp(0, grid.rows - 1);
  final runes = needle.runes.toList();
  for (var r = windowStart; r < grid.rows; r++) {
    if (r >= region.topRow && r <= region.bottomRow) continue;
    for (var col = 0; col < grid.columns; col++) {
      if (_isWideSpacer(grid, r, col)) continue;
      if (_matchesNeedleAtBounded(
        grid,
        r,
        col,
        runes,
        maxRow: grid.rows - 1,
        maxCol: grid.columns - 1,
      )) {
        return true;
      }
    }
  }
  return false;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/terminal/fullscreen_input_screen_probe_test.dart`
Expected: PASS (existing 30+ tests + 7 new region tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/fullscreen_input_screen_probe.dart client/test/services/terminal/fullscreen_input_screen_probe_test.dart
git commit -m "feat(pty): composer region locate/needle/empty probes"
```

---

### Task 4: Port interface — composerRegion, region probes, isAcked

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_pty_delivery_port.dart`
- Modify: `client/lib/services/terminal/terminal_fullscreen_pty_port.dart`
- Modify: `client/lib/services/terminal/terminal_screen_probe_controller.dart`
- Modify: `client/test/services/terminal/support/fake_fullscreen_pty_delivery_port.dart`

**Interfaces:**
- Consumes: `ComposerRegion`, `locateComposerRegion`, `regionContainsNeedle`, `isComposerRegionEmpty`, `needleAppearsOutsideRegion` (Task 3); `FullscreenComposerRegionSpec` (Task 1).
- Produces:
  - `FullscreenPtyDeliveryPort.composerRegion` (`FullscreenComposerRegionSpec`)
  - `FullscreenPtyDeliveryPort.isAcked` (`bool get`)
  - `FullscreenPtyDeliveryPort.locateComposerRegion({int scanRows = 24})` → `ComposerRegion?`
  - `FullscreenPtyDeliveryPort.regionContainsNeedle(ComposerRegion, String needle)` → `bool`
  - `FullscreenPtyDeliveryPort.isComposerRegionEmpty(ComposerRegion)` → `bool`
  - `FullscreenPtyDeliveryPort.needleAppearsOutsideRegion(ComposerRegion, String needle, {int scanRows})` → `bool`
  - `FullscreenPtyDeliveryPort.isAcked` defaults handled by fake.

- [ ] **Step 1: Update the port interface**

`fullscreen_pty_delivery_port.dart` — replace `crAckConfig` getter and add the region surface:

```dart
import 'terminal_composer_region.dart' show FullscreenComposerRegionSpec;

abstract interface class FullscreenPtyDeliveryPort {
  bool get isAborted;

  /// Hook-channel prompt-submit confirmation (authoritative over grid probes).
  bool get isAcked;

  int get viewportRows;

  FullscreenComposerRegionSpec get composerRegion;

  Future<void> syncDisplayGrid();

  ComposerRegion? locateComposerRegion({int scanRows = 24});

  bool regionContainsNeedle(ComposerRegion region, String needle);

  bool isComposerRegionEmpty(ComposerRegion region);

  bool needleAppearsOutsideRegion(
    ComposerRegion region,
    String needle, {
    int scanRows = 24,
  });

  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24});

  FullscreenPromptAnchor? locateCollapsedPasteNeedle({int scanRows = 24});

  bool isAtAnchor(FullscreenPromptAnchor anchor);

  bool isSubmittedAfterCr(FullscreenPromptAnchor anchor, {int scanRows = 24});

  bool isComposerChromeEmpty({int scanRows = 24});

  Future<void> clearStagedInput();

  Future<void> pasteText(String text);

  Future<void> submitCr();

  String describeProbeWindow({int scanRows = 24});
}
```

Move `ComposerRegion` to `fullscreen_input_screen_probe.dart` (already there from Task 3); remove the `import 'fullscreen_cr_ack_config.dart';` from the port file.

- [ ] **Step 2: Update `TerminalScreenProbeController`**

Add region passthroughs (keep existing anchor methods):

```dart
  ComposerRegion? locateComposerRegion(
    FullscreenComposerRegionSpec spec, {
    int scanRows = 24,
  }) =>
      probe.locateComposerRegion(
        _screenGrid,
        spec,
        scanRows: scanRows,
      );
```

Add `import '../cli/registry/capabilities/terminal_composer_region.dart';` and `import 'fullscreen_input_screen_probe.dart' as probe;` already present. Remove the `fullscreen_cr_ack_config.dart` import if nothing else uses it (the `isFullscreenPromptSubmitted` strategy param is still referenced by Task 5's interim state — keep it until Task 5).

- [ ] **Step 3: Update `TerminalFullscreenPtyPort`**

Replace `crAckConfig` with `composerRegion` + region delegates + `isAcked`:

```dart
final class TerminalFullscreenPtyPort implements FullscreenPtyDeliveryPort {
  TerminalFullscreenPtyPort({
    required TerminalInputController input,
    required TerminalScreenProbeController probe,
    required bool Function() aborted,
    required FullscreenComposerRegionSpec composerRegion,
    bool Function()? isAcked,
  }) : _input = input,
       _probe = probe,
       _aborted = aborted,
       _composerRegion = composerRegion,
       _isAcked = isAcked ?? (() => false);

  final TerminalInputController _input;
  final TerminalScreenProbeController _probe;
  final bool Function() _aborted;
  final FullscreenComposerRegionSpec _composerRegion;
  final bool Function() _isAcked;

  @override
  bool get isAborted => _aborted();

  @override
  bool get isAcked => _isAcked();

  @override
  int get viewportRows => _probe.viewportRows;

  @override
  FullscreenComposerRegionSpec get composerRegion => _composerRegion;

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) =>
      _probe.locateComposerRegion(_composerRegion, scanRows: scanRows);

  @override
  bool regionContainsNeedle(ComposerRegion region, String needle) =>
      _probe.regionContainsNeedle(region, needle);

  @override
  bool isComposerRegionEmpty(ComposerRegion region) =>
      _probe.isComposerRegionEmpty(region, _composerRegion);

  @override
  bool needleAppearsOutsideRegion(
    ComposerRegion region,
    String needle, {
    int scanRows = 24,
  }) =>
      _probe.needleAppearsOutsideRegion(
        region,
        needle,
        scanRows: scanRows,
      );

  // ... keep the remaining anchor/input methods unchanged, but the
  // isComposerChromeEmpty / isSubmittedAfterCr anchors now consult the
  // composer prefix list:
  @override
  FullscreenPromptAnchor? locateNeedle(String needle, {int scanRows = 24}) =>
      _probe.locateFullscreenPromptNeedle(
        needle,
        scanRows: scanRows,
        composerPrefix: _composerPrefix,
      );
  // where _composerPrefix = _composerRegion.prefixes.isEmpty
  //   ? null : _composerRegion.prefixes.first;
}
```

Note: add a private `String? get _composerPrefix` helper returning `_composerRegion.prefixes.isEmpty ? null : _composerRegion.prefixes.first`; use it in `locateNeedle`, `locateCollapsedPasteNeedle`, `isAtAnchor`, `isSubmittedAfterCr`, `isComposerChromeEmpty` in place of the old `_crAckConfig.composerPrefix`. Drop the `fullscreen_cr_ack_config.dart` import; import `terminal_composer_region.dart`.

- [ ] **Step 4: Update the fake port**

`support/fake_fullscreen_pty_delivery_port.dart` — constructor takes `composerRegion` (default `fullscreenDefaultComposerSpec`) and `isAckedOverride`; implements the new members:

```dart
  FakeFullscreenPtyDeliveryPort({
    this.aborted = false,
    this.crsToClear = 1,
    this.pastesBeforeVisible = 1,
    this.visibleAfterPaste = true,
    this.collapseAsClaudePaste = false,
    this.composerRegion = fullscreenDefaultComposerSpec,
    this.composerChromeEmptyOverride,
    this.isAckedOverride,
  });

  final bool? isAckedOverride;

  @override
  bool get isAcked => isAckedOverride ?? false;

  @override
  final FullscreenComposerRegionSpec composerRegion;

  @override
  ComposerRegion? locateComposerRegion({int scanRows = 24}) {
    if (staged == null) return null;
    return const ComposerRegion(
      topRow: 0, bottomRow: 0, leftCol: 0, rightCol: 200,
    );
  }

  @override
  bool regionContainsNeedle(ComposerRegion region, String needle) =>
      staged != null && staged!.contains(needle);

  @override
  bool isComposerRegionEmpty(ComposerRegion region) =>
      staged == null || staged!.trim().isEmpty;

  @override
  bool needleAppearsOutsideRegion(
    ComposerRegion region,
    String needle, {
    int scanRows = 24,
  }) =>
      false;
```

Update `isComposerChromeEmpty` to read `composerRegion.prefixes` (first non-empty, else fallback logic):

```dart
  @override
  bool isComposerChromeEmpty({int scanRows = 24}) {
    if (composerChromeEmptyOverride != null) {
      return composerChromeEmptyOverride!;
    }
    final prefix = composerRegion.prefixes.isEmpty
        ? null
        : composerRegion.prefixes.first;
    if (prefix == null || prefix.isEmpty) {
      return staged == null || staged!.trim().isEmpty;
    }
    if (staged == null) return true;
    final trimmed = staged!.trimLeft();
    if (!trimmed.startsWith(prefix)) {
      return staged!.trim().isEmpty;
    }
    return trimmed.substring(prefix.length).trim().isEmpty;
  }
```

Import `terminal_composer_region.dart`; drop `fullscreen_cr_ack_config.dart` import. Keep the `_AnchorCellStuckButHookAckedPort` and `_CursorTranscriptAfterSubmitPort` in the automation test compiling via their own `composerRegion` overrides (Task 5 handles them; if the automation test stops compiling here, move its port classes' `crAckConfig` to `composerRegion` now — the minimal change is: `FullscreenCrAckConfig(...)` → `const FullscreenComposerRegionSpec(submitSemantics: ..., prefixes: [...])`).

- [ ] **Step 5: Run tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: errors remaining only in `fullscreen_pty_automation.dart`, `member_pty_inject_service.dart`, `tab_member_pty_delivery.dart`, `fullscreen_reinject_guard.dart`, and their tests (Tasks 5–6).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/terminal/fullscreen_pty_delivery_port.dart client/lib/services/terminal/terminal_fullscreen_pty_port.dart client/lib/services/terminal/terminal_screen_probe_controller.dart client/test/services/terminal/support/fake_fullscreen_pty_delivery_port.dart
git commit -m "feat(pty): port exposes composer region + isAcked"
```

---

### Task 5: Automation — region-based paste/CR ACK + region re-locate

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_pty_automation.dart`
- Modify: `client/lib/services/terminal/fullscreen_reinject_guard.dart`
- Modify: `client/lib/services/terminal/member_pty_inject_service.dart`
- Modify: `client/lib/cubits/chat/tab_member_pty_delivery.dart`
- Test: `client/test/services/terminal/fullscreen_pty_automation_test.dart`, `client/test/services/terminal/fullscreen_reinject_guard_test.dart`

**Interfaces:**
- Consumes: Task 3 region functions, Task 4 port surface.
- Produces:
  - `FullscreenPtyAutomation` uses `port.composerRegion` / `port.locateComposerRegion()` / `port.regionContainsNeedle` / `port.isComposerRegionEmpty` / `port.needleAppearsOutsideRegion` / `port.isAcked`.
  - `shouldSkipReinjectAfterCrStuck({required ComposerSubmitSemantics semantics, required bool composerRegionEmpty, required bool needleStillVisible})`.
  - `MemberPtyInjectService.deliver/retry(..., required FullscreenComposerRegionSpec composerRegion, bool Function()? isAcked)` (replaces `crAckConfig`).
  - `TabMemberPtyDelivery` builds the spec from `TerminalBehaviorCapability.composerRegion` and passes `isAcked` from `_promptAckTracker`.

- [ ] **Step 1: Rewrite `fullscreen_pty_automation.dart` submit logic**

Replace `_pollCrUntilAnchorClears`'s strategy switch and `_shouldSkipReinject` with region logic:

```dart
  Future<FullscreenPtyDeliveryOutcome> _pollCrUntilSubmitted(
    FullscreenPtyDeliveryPort port,
    String needle, {
    int? maxAttempts,
    bool Function()? isAcked,
    ComposerRegion? beforeCrRegion,
  }) async {
    final spec = port.composerRegion;
    if (spec.submitSemantics == ComposerSubmitSemantics.timed) {
      await port.submitCr();
      await Future<void>.delayed(_timing.afterCr);
      return FullscreenPtyDeliveryOutcome.submitted;
    }

    await port.submitCr();
    final scanRows = _probeScanRows(port);
    final outcome = await ptyAckPollRetry(
      settle: _timing.afterCr,
      maxAttempts: maxAttempts ?? _timing.crMaxAttempts,
      aborted: () => port.isAborted,
      isAcked: (_) async {
        if (isAcked?.call() ?? false) return true;
        await port.syncDisplayGrid();
        return _regionSubmitted(
          port,
          needle,
          scanRows: scanRows,
          beforeCrRegion: beforeCrRegion,
        );
      },
      onRetry: (_) async => port.submitCr(),
    );
    return switch (outcome) {
      PtyAckPollOutcome.acked => FullscreenPtyDeliveryOutcome.submitted,
      PtyAckPollOutcome.aborted => FullscreenPtyDeliveryOutcome.aborted,
      PtyAckPollOutcome.exhausted => FullscreenPtyDeliveryOutcome.crStuck,
    };
  }

  bool _regionSubmitted(
    FullscreenPtyDeliveryPort port,
    String needle, {
    required int scanRows,
    ComposerRegion? beforeCrRegion,
  }) {
    final spec = port.composerRegion;
    final region = port.locateComposerRegion(scanRows: scanRows);
    switch (spec.submitSemantics) {
      case ComposerSubmitSemantics.regionCleared:
        if (region == null) return false;
        return !port.regionContainsNeedle(region, needle);
      case ComposerSubmitSemantics.regionMovedDown:
        return _hasComposerRegionBelow(port, beforeCrRegion, scanRows: scanRows);
      case ComposerSubmitSemantics.timed:
        return true;
    }
  }
```

Notes:
- Callers capture `final beforeCrRegion = port.locateComposerRegion();` **before** `port.submitCr()` and pass it to `_pollCrUntilSubmitted` so `regionMovedDown` can detect a new region painted below.
- `deliverPasteAndSubmit` loop becomes:

```dart
    for (var reinject = 0; reinject <= maxReinject; reinject++) {
      if (port.isAborted) return FullscreenPtyDeliveryOutcome.aborted;
      if (isAcked?.call() ?? false) {
        return FullscreenPtyDeliveryOutcome.submitted;
      }
      if (reinject > 0) {
        await Future<void>.delayed(_timing.afterReinject);
      }

      await port.syncDisplayGrid();
      final beforeCrRegion = port.locateComposerRegion();
      await port.clearStagedInput();
      await Future<void>.delayed(_timing.afterClear);
      await port.pasteText(text);

      final anchor = await _pollForNeedle(
        port,
        needle,
        minSettle: pasteSettle + _timing.afterPaste + _extraSettleForLength(text),
        pollTimeout: _pastePollBudget(text),
      );

      if (anchor == null) {
        // Region-scoped fallback: staged inside the region also ACKs.
        await port.syncDisplayGrid();
        final regionAck = port.locateComposerRegion();
        if (regionAck != null &&
            port.regionContainsNeedle(regionAck, needle)) {
          // paste confirmed inside region — proceed to CR
        } else {
          if (reinject < maxReinject) continue;
          _logProbeMiss(port, needle, text, outcome: 'pasteNotFound');
          return FullscreenPtyDeliveryOutcome.pasteNotFound;
        }
      }

      final crOutcome = await _pollCrUntilSubmitted(
        port,
        needle,
        isAcked: isAcked,
        beforeCrRegion: beforeCrRegion,
      );
      switch (crOutcome) {
        case FullscreenPtyDeliveryOutcome.submitted:
          return FullscreenPtyDeliveryOutcome.submitted;
        case FullscreenPtyDeliveryOutcome.aborted:
          return FullscreenPtyDeliveryOutcome.aborted;
        case FullscreenPtyDeliveryOutcome.crStuck:
          if (await _shouldSkipReinject(port, needle, text)) {
            return FullscreenPtyDeliveryOutcome.submitted;
          }
          if (reinject < maxReinject) continue;
          return FullscreenPtyDeliveryOutcome.crStuck;
        case FullscreenPtyDeliveryOutcome.pasteNotFound:
          return FullscreenPtyDeliveryOutcome.crStuck;
      }
    }
```

- `_shouldSkipReinject` becomes region-based:

```dart
  Future<bool> _shouldSkipReinject(
    FullscreenPtyDeliveryPort port,
    String needle,
    String text,
  ) async {
    await port.syncDisplayGrid();
    final scanRows = _probeScanRows(port);
    final region = port.locateComposerRegion(scanRows: scanRows);
    final skip = shouldSkipReinjectAfterCrStuck(
      semantics: port.composerRegion.submitSemantics,
      composerRegionEmpty: region != null &&
          port.isComposerRegionEmpty(region),
      needleStillVisible: port.locateNeedle(needle, scanRows: scanRows) != null,
    );
    if (skip) {
      appLogger.i(
        '[pty] skip-reinject regionMovedDown empty+needle '
        'textChars=${text.length}',
      );
    }
    return skip;
  }
```

- `_hasComposerRegionBelow` — port-level helper on `FullscreenPtyDeliveryPort`? No: implement in the automation using `locateNeedle` on the prefix? Simplest correct approach: after CR, locate the composer region again and check `region.topRow > previousBottomRow`:

```dart
  bool _hasComposerRegionBelow(
    FullscreenPtyDeliveryPort port,
    ComposerRegion? previous, {
    required int scanRows,
  }) {
    final current = port.locateComposerRegion(scanRows: scanRows);
    if (current == null) return false;
    if (previous == null) return false;
    return current.topRow > previous.bottomRow;
  }
```

Call sites in `_regionSubmitted` for `regionMovedDown` need the previous region captured **before** CR — pass it in from `_pollCrUntilSubmitted` callers (capture `region` before `submitCr()` and pass through). Signature: `_pollCrUntilSubmitted(port, {int? maxAttempts, bool Function()? isAcked, ComposerRegion? beforeCrRegion})`.

- [ ] **Step 2: Update `fullscreen_reinject_guard.dart`**

```dart
import 'terminal_composer_region.dart';

/// Whether [FullscreenPtyAutomation.deliverPasteAndSubmit] may treat a
/// `crStuck` outcome as success and skip clear→paste reinject.
///
/// Only [ComposerSubmitSemantics.regionMovedDown] (Cursor / Codex) leaves
/// submitted text on-screen while painting an empty composer. When that
/// empty chrome is visible **and** the paste needle still appears (transcript
/// residual), the first CR already committed — reinject would duplicate.
bool shouldSkipReinjectAfterCrStuck({
  required ComposerSubmitSemantics semantics,
  required bool composerRegionEmpty,
  required bool needleStillVisible,
}) {
  if (semantics != ComposerSubmitSemantics.regionMovedDown) return false;
  return composerRegionEmpty && needleStillVisible;
}
```

- [ ] **Step 3: Update `member_pty_inject_service.dart`**

Replace `required FullscreenCrAckConfig crAckConfig` with `required FullscreenComposerRegionSpec composerRegion` in `deliver`, `retry`, `_runLocked`; pass `composerRegion` into `TerminalFullscreenPtyPort(composerRegion: composerRegion, isAcked: isAcked, ...)`. Update imports (drop `fullscreen_cr_ack_config.dart`, add `terminal_composer_region.dart`). `_runLocked` currently constructs the port — add the `isAcked` param there too.

- [ ] **Step 4: Update `tab_member_pty_delivery.dart`**

Replace `_crAckForMember` with a spec builder and pass `composerRegion` + `isAcked`:

```dart
  FullscreenComposerRegionSpec _composerSpecForMember(
    String sessionId,
    String memberId,
  ) {
    final cli = _memberCli(sessionId, memberId);
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(cli);
    return behavior?.composerRegion ?? fullscreenDefaultComposerSpec;
  }
```

Update the four `_ptyInject.deliver/retry` call sites: replace `crAckConfig: _crAckForMember(...)` with `composerRegion: _composerSpecForMember(...)`; keep the `isAcked:` closures already added by the uncommitted ACK work. Import `terminal_composer_region.dart`; drop `fullscreen_cr_ack_config.dart` import.

- [ ] **Step 5: Update `fullscreen_reinject_guard_test.dart`**

Replace all `FullscreenCrAckStrategy` references with `ComposerSubmitSemantics`:

```dart
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';

    test('regionMovedDown skips only when empty and needle visible', () {
      // was: strategy: FullscreenCrAckStrategy.composerMovesDown
      final skip = shouldSkipReinjectAfterCrStuck(
        semantics: ComposerSubmitSemantics.regionMovedDown,
        composerRegionEmpty: true,
        needleStillVisible: true,
      );
      expect(skip, isTrue);
    });
    // ... all cases: semantics: regionMovedDown / regionCleared / timed
```

- [ ] **Step 6: Update `fullscreen_pty_automation_test.dart` port classes**

- `FakeFullscreenPtyDeliveryPort(...)` constructor usages: replace `crAckConfig:` args with `composerRegion:` where passed (the fake already defaults to `fullscreenDefaultComposerSpec`).
- `_CursorTranscriptAfterSubmitPort`: replace `crAckConfig` getter with `composerRegion => const FullscreenComposerRegionSpec(submitSemantics: ComposerSubmitSemantics.regionMovedDown, prefixes: ['→'])`.
- `_AnchorCellStuckButHookAckedPort`: `composerRegion => const FullscreenComposerRegionSpec(submitSemantics: ComposerSubmitSemantics.regionCleared, prefixes: ['\u2503'])`.
- `_ComposerMovesDown*Port` classes (there are several): same `regionMovedDown` replacement; any class overriding `isSubmittedAfterCr` can keep its behavior but the automation no longer calls it for region semantics — keep overrides for safety.
- `FullscreenPtyAutomation.deliverPasteAndSubmit(...)` — signature unchanged (isAcked stays optional).

- [ ] **Step 7: Run the full terminal test suite**

Run: `cd client && flutter test test/services/terminal/ test/services/cli/registry/capabilities/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/terminal/fullscreen_pty_automation.dart client/lib/services/terminal/fullscreen_reinject_guard.dart client/lib/services/terminal/member_pty_inject_service.dart client/lib/cubits/chat/tab_member_pty_delivery.dart client/test/services/terminal/fullscreen_reinject_guard_test.dart client/test/services/terminal/fullscreen_pty_automation_test.dart
git commit -m "feat(pty): region-based submit semantics in fullscreen automation"
```

---

### Task 6: Delete the old strategy config + migrate remaining tests

**Files:**
- Delete: `client/lib/services/terminal/fullscreen_cr_ack_config.dart`
- Modify: `client/test/services/terminal/fullscreen_input_screen_probe_test.dart` (migrate `isFullscreenPromptSubmitted` strategy tests), `client/test/services/terminal/member_pty_inject_service_test.dart`, `client/test/services/terminal/member_pty_inject_abort_test.dart`
- Modify: `client/test/integration/codex_deliver_integration_test.dart`, `client/test/integration/cursor_agent_deliver_integration_test.dart`, `client/test/integration/opencode_deliver_integration_test.dart` (+ add short-text case)

**Interfaces:**
- Consumes: everything from Tasks 0–5.

- [ ] **Step 1: Delete the config file and fix all remaining references**

```bash
cd client
git rm lib/services/terminal/fullscreen_cr_ack_config.dart
```

Fix remaining `import 'fullscreen_cr_ack_config.dart';` in:
- `test/services/terminal/fullscreen_input_screen_probe_test.dart` — replace `isFullscreenPromptSubmitted(..., strategy: FullscreenCrAckStrategy.composerMovesDown, composerPrefix: ...)` tests with region semantics: for the "prefix row appears below" case, use `locateComposerRegion` + a helper asserting `current.topRow > anchor.row` (or drop the now-redundant `isFullscreenPromptSubmitted` unit tests — the automation-level behavior is covered in `fullscreen_pty_automation_test.dart`). Keep `bottomComposerChromeRow` / `isComposerChromeEmpty` tests (functions still exist).
- `test/services/terminal/member_pty_inject_service_test.dart` and `member_pty_inject_abort_test.dart` — `_StuckAutomation`/`_ControlledPasteNotFoundAutomation` already extended for `isAcked`; if they still reference `crAckConfig`/`FullscreenCrAckConfig`, update to `composerRegion: fullscreenDefaultComposerSpec` at the `deliver/retry` call sites.
- Integration tests:

`codex_deliver_integration_test.dart`:
```dart
        crAckConfig: const FullscreenCrAckConfig(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          composerPrefix: '\u203a',
        ),
```
→
```dart
        composerRegion: const CodexTerminalBehavior().composerRegion,
```
(import `package:teampilot/services/cli/codex/capabilities/terminal_behavior.dart`; drop the `fullscreen_cr_ack_config.dart` import; update the assertion message "codex composerMovesDown ACK" → "codex regionMovedDown ACK").

`cursor_agent_deliver_integration_test.dart`:
```dart
        crAckConfig: FullscreenCrAckConfig(
          strategy: const CursorTerminalBehavior().fullscreenCrAckStrategy,
          composerPrefix:
              const CursorTerminalBehavior().fullscreenComposerPrefix,
        ),
```
→
```dart
        composerRegion: const CursorTerminalBehavior().composerRegion,
```
(keep `CursorTerminalBehavior` import; drop `fullscreen_cr_ack_config.dart` import.)

`opencode_deliver_integration_test.dart`:
```dart
            crAckConfig: const FullscreenCrAckConfig(
              strategy: FullscreenCrAckStrategy.anchorCellClears,
              composerPrefix: '\u2503',
            ),
```
→
```dart
            composerRegion: const OpencodeTerminalBehavior().composerRegion,
```
(import `package:teampilot/services/cli/opencode/capabilities/terminal_behavior.dart`.)

- [ ] **Step 2: Add the short-text integration case to `opencode_deliver_integration_test.dart`**

Inside the existing `for (final viewport in ...)` loop, after the long-text deliver, add a second block that boots a fresh session (or reuses the same one) and delivers a **single `'1'`**:

```dart
          // Short-text regression: a single digit must submit exactly once —
          // the old needle probe anchored to transcript "1"s and re-pasted
          // (duplicate user rows). Region-scoped ACK must prevent that.
          final shortText = '1';
          await session.probe.syncDisplayGrid();
          final outcomeShort = await automation.deliverPasteAndSubmit(
            port: port,
            text: shortText,
            pasteSettle: const Duration(milliseconds: 500),
          );
          await session.probe.syncDisplayGrid();
          expect(
            outcomeShort,
            FullscreenPtyDeliveryOutcome.submitted,
            reason: 'single-digit deliver must submit. '
                'Dump:\n'
                '${session.probe.describeProbeWindow(scanRows: viewport.rows)}',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          await session.probe.syncDisplayGrid();
          final afterShort = session.probe.describeProbeWindow(scanRows: viewport.rows);
          // The user row "1" now sits in the message box above the composer
          // (primary signal: original region cleared). Assert region cleared:
          final regionAfter = port.locateComposerRegion(
            scanRows: viewport.rows,
          );
          expect(
            regionAfter == null ||
                !port.regionContainsNeedle(regionAfter, shortText),
            isTrue,
            reason: 'region must no longer hold the staged digit after CR. '
                'Dump:\n$afterShort',
          );
```

Note: reuse the same session/port; boot gates (`_dismissOpencodeModals`) should already be clear from the first deliver. If flaky, deliver the short text first, then the long text.

- [ ] **Step 3: Run all unit + integration compile checks**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean.

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 4: Run the opencode integration test (if opencode on PATH)**

```bash
cd client && LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/opencode_deliver_integration_test.dart \
  --tags "integration && linux-pty"
```

Expected: PASS (both long-text and `'1'` cases).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal client/lib/cubits/chat/tab_member_pty_delivery.dart \
  client/lib/services/cli/registry/capabilities/terminal_behavior_capability.dart \
  client/lib/services/cli/*/capabilities/terminal_behavior.dart client/test
git commit -m "refactor(pty): drop legacy crAckConfig; region ACK everywhere"
```

Note: stage explicit paths (not `git add -A`) so the unrelated dirty
`opencode/capabilities/config_profile.dart` external-directories work stays
out of this commit.

---

### Task 7: Final regression + spec/plan consistency

**Files:**
- No source changes expected; fix anything surfaced.

- [ ] **Step 1: Full verification**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```
Expected: clean analyze + all tests pass.

- [ ] **Step 2: Verify no lingering references**

```bash
rg -n "FullscreenCrAckConfig|FullscreenCrAckStrategy|fullscreen_cr_ack_config|fullscreenCrAckStrategy|fullscreenComposerPrefix" client/lib client/test
```
Expected: no matches.

- [ ] **Step 3: Confirm spec coverage**

Check each spec section against landed code:
- Spec §1 (spec types on capability) → Task 1 + Task 2.
- Spec §2 (probe region parsing) → Task 3.
- Spec §3 (automation semantics) → Task 5.
- Spec §4 (ACK-aware reinject) → Task 0 (already in working tree) + Task 4 port `isAcked`.
- Spec §5 (probe controller surface) → Task 4.
- Spec Verification (unit + integration short-text) → Tasks 3/5/6.

- [ ] **Step 4: Commit any stragglers**

```bash
git add -A
git commit -m "chore(pty): finalize composer region migration" || echo "nothing to commit"
```

---

## Self-review notes

- **Spec coverage:** all five spec sections map to Tasks 0–6; the "cursor = regionMovedDown" correction is baked into Task 2 and the integration test migrations.
- **Type consistency:** `FullscreenComposerRegionSpec` / `ComposerSubmitSemantics` / `ComposerBorderSpec` / `ComposerRegion` names are identical across Tasks 1–6; port getters match the fake exactly.
- **Working-tree hazard:** Task 0 must land the uncommitted ACK-aware files **first**; the unrelated `opencode/config_profile.dart` external-directories diff must not be swept into any commit (Step 2 of Task 0 and Task 6 Step 5 stage explicit paths / `git add -A client/lib client/test` — for Task 6 Step 5 use explicit paths instead of `-A` if `config_profile.dart` is still dirty: `git add client/lib/services/terminal client/lib/cubits/chat/tab_member_pty_delivery.dart client/lib/services/cli/registry/capabilities/terminal_behavior_capability.dart client/lib/services/cli/*/capabilities/terminal_behavior.dart client/test`).
