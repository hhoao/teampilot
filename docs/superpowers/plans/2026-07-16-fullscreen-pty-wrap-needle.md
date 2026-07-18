# Full-screen PTY Wrap-Aware Needle Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make fullscreen PTY paste/CR ACK locate needles that soft-wrap across rows so long Claude landing messages actually submit.

**Architecture:** Replace single-row `_matchesNeedleAt` in `fullscreen_input_screen_probe.dart` with wrap-aware matching (soft-wrap at row end / trailing padding; no blank-row stitching; strict continuation spaces). Locate and `isFullscreenPromptAtAnchor` share that primitive. No changes to needle policy, delivery, or CR strategies.

**Tech Stack:** Dart / Flutter tests (`flutter_test`), existing `_FakeGrid` in probe unit tests.

**Spec:** [`docs/superpowers/specs/2026-07-16-fullscreen-pty-wrap-needle-design.md`](../specs/2026-07-16-fullscreen-pty-wrap-needle-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| Modify: `client/lib/services/terminal/fullscreen_input_screen_probe.dart` | Wrap-aware `_matchesNeedleAt`; doc comments |
| Modify: `client/test/services/terminal/fullscreen_input_screen_probe_test.dart` | Wrapped CJK / blank-gap / isAtAnchor tests + multi-row wide CJK helper |

**Not in this plan:** `PtyAutomationNeedle` changes; Claude `FullscreenCrAckStrategy`; `MemberPtyInjectService` retry logic; live PTY integration tests.

---

### Task 1: Failing tests for wrap match

**Files:**
- Modify: `client/test/services/terminal/fullscreen_input_screen_probe_test.dart`

- [ ] **Step 1: Add multi-row wide-CJK helper on `_FakeGrid`**

Add a factory that builds a fixed-width grid with wide spacers for CJK (flag `1 << 5` on the spacer column), ASCII cells without spacers, and pads each row to `columns`:

```dart
/// Soft-wrapped composer lines with CJK wide spacers (alacritty mirror layout).
/// [lineTexts] are logical strings per row (may include ASCII and CJK).
factory _FakeGrid.wrappedWideLines({
  required int columns,
  required List<String> lineTexts,
}) {
  final rows = <List<int>>[];
  final flagRows = <List<int>>[];
  for (final text in lineTexts) {
    final codepoints = List<int>.filled(columns, 0x20);
    final flags = List<int>.filled(columns, 0);
    var col = 0;
    for (final cp in text.runes) {
      final isWide = cp > 0x7f; // good enough for these fixtures (CJK)
      final width = isWide ? 2 : 1;
      if (col + width > columns) break;
      codepoints[col] = cp;
      if (isWide) flags[col + 1] = 1 << 5;
      col += width;
    }
    rows.add(codepoints);
    flagRows.add(flags);
  }
  return _FakeGrid(rows, flagRows);
}
```

- [ ] **Step 2: Write failing wrapped-needle locate test**

Reproduce production shape: needle is the last 40 chars of a long CJK landing line, split across two rows.

```dart
test('locateNeedle finds soft-wrapped CJK tail across two rows', () {
  // Logical paste (no prefix in needle). Composer prefix only on first row.
  const line0 =
      '❯ 帮我估算一下这个需求的时间：分类分级系统接入银行统一身份认证体系，实现登录双因素认证（优先手机令牌方式），同时评估';
  const line1 = '是否支持 LDAP/AD 域认证作为标准登录方式，详细信息参考附件';
  const full =
      '帮我估算一下这个需求的时间：分类分级系统接入银行统一身份认证体系，实现登录双因素认证（优先手机令牌方式），同时评估是否支持 LDAP/AD 域认证作为标准登录方式，详细信息参考附件';
  final needle = full.substring(full.length - 40);
  // needle starts with "式），同时评估" which ends line0 and continues on line1.

  // columns must force the soft wrap used in fixtures: measure with wide=2.
  // Use a columns value that fits line0's cells exactly (no trailing content cell).
  final grid = _FakeGrid.wrappedWideLines(
    columns: _displayWidth(line0),
    lineTexts: [line0, line1],
  );

  final anchor = locateFullscreenPromptNeedle(grid, needle, scanRows: 8);
  expect(anchor, isNotNull, reason: 'needle spans soft wrap; single-row match misses');
  expect(anchor!.row, 0);
  expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);
});

int _displayWidth(String text) {
  var w = 0;
  for (final cp in text.runes) {
    w += cp > 0x7f ? 2 : 1;
  }
  return w;
}
```

Adjust `columns` / line split if the helper truncates: both lines must fully fit; `columns == _displayWidth(line0)` and `line1` display width ≤ columns.

- [ ] **Step 3: Write failing blank-row gap test**

`fromRows` pads short lines with spaces — a padding-only middle row is “blank” for the soft-wrap rule:

```dart
test('locateNeedle does not stitch across blank row', () {
  final grid = _FakeGrid.fromRows([
    'AAAAUNIQUEPART',
    '              ', // padding-only
    'CONTINUATIONZZ',
  ]);
  expect(
    locateFullscreenPromptNeedle(grid, 'UNIQUEPARTCONTINUATIONZZ'),
    isNull,
  );
});
```

Also add a positive ASCII soft-wrap control (no blank row) so the gap test is meaningful:

```dart
test('locateNeedle finds ASCII soft-wrapped needle across two rows', () {
  final grid = _FakeGrid.fromRows([
    '❯ hello_WORLD_PART',
    '_CONTINUES_HERE',
  ]);
  final anchor = locateFullscreenPromptNeedle(
    grid,
    'WORLD_PART_CONTINUES_HERE',
  );
  expect(anchor, isNotNull);
  expect(anchor!.row, 0);
});
```

- [ ] **Step 4: Write isAtAnchor clear-after-wrap test**

```dart
test('isAtAnchor false after clearing soft-wrapped staged cells', () {
  final grid = _FakeGrid.fromRows([
    '❯ hello_WORLD_PART',
    '_CONTINUES_HERE',
  ]);
  final anchor = locateFullscreenPromptNeedle(
    grid,
    'WORLD_PART_CONTINUES_HERE',
  )!;
  expect(isFullscreenPromptAtAnchor(grid, anchor), isTrue);

  grid.rowsData[0] = List.filled(grid.columns, 0x20);
  grid.rowsData[1] = List.filled(grid.columns, 0x20);
  expect(isFullscreenPromptAtAnchor(grid, anchor), isFalse);
});
```

- [ ] **Step 5: Run tests — expect wrap locate to FAIL**

```bash
cd client && flutter test test/services/terminal/fullscreen_input_screen_probe_test.dart
```

Expected: `locateNeedle finds soft-wrapped CJK tail across two rows` and `locateNeedle finds ASCII soft-wrapped needle across two rows` **FAIL** (`anchor` null). Existing tests still pass. Blank-row and clear-after-wrap tests may also fail or throw until locate works.

- [ ] **Step 6: Commit failing tests**

```bash
git add client/test/services/terminal/fullscreen_input_screen_probe_test.dart
git commit -m "$(cat <<'EOF'
test: add failing soft-wrap PTY needle probe cases

EOF
)"
```

---

### Task 2: Implement wrap-aware `_matchesNeedleAt`

**Files:**
- Modify: `client/lib/services/terminal/fullscreen_input_screen_probe.dart`

- [ ] **Step 1: Update doc comments**

Change `FullscreenPromptAnchor` comment from "one row, column-aligned" to note the needle may continue onto following rows via soft wrap.

Update `locateFullscreenPromptNeedle` dartdoc: search tries starts on each row; match may consume subsequent rows.

Update `isFullscreenPromptAtAnchor` dartdoc: needle may occupy cells on `anchor.row` and following soft-wrapped rows.

- [ ] **Step 2: Replace `_matchesNeedleAt` body**

Keep the same signature. Implement soft-wrap per spec. Suggested structure:

```dart
bool _matchesNeedleAt(
  TerminalScreenGrid grid,
  int row,
  int startCol,
  List<int> needleRunes,
) {
  var r = row;
  var col = startCol;
  for (final cp in needleRunes) {
    while (true) {
      if (r >= grid.rows) return false;
      col = _skipWideSpacers(grid, r, col);
      if (col < grid.columns && !_rowRemainderIsPadding(grid, r, col)) {
        break;
      }
      // Soft-wrap before comparing this rune.
      r += 1;
      col = 0;
      if (r >= grid.rows) return false;
      if (!_rowHasNonSpaceContent(grid, r) && cp != 0x20) return false;
    }
    if (grid.codepointAt(r, col) != cp) return false;
    col = _advancePastCell(grid, r, col);
  }
  return true;
}

bool _rowRemainderIsPadding(TerminalScreenGrid grid, int row, int fromCol) {
  for (var c = fromCol; c < grid.columns; c++) {
    if (_isWideSpacer(grid, row, c)) continue;
    final cp = grid.codepointAt(row, c);
    if (cp != 0 && cp != 0x20) return false;
  }
  return true;
}

bool _rowHasNonSpaceContent(TerminalScreenGrid grid, int row) {
  for (var c = 0; c < grid.columns; c++) {
    if (_isWideSpacer(grid, row, c)) continue;
    final cp = grid.codepointAt(row, c);
    if (cp != 0 && cp != 0x20) return true;
  }
  return false;
}
```

Comment near the soft-wrap gate: padding at end of row triggers wrap **before** comparing the current needle rune (so trailing spaces are not consumed as needle content unless the matcher is still on a content cell).

- [ ] **Step 3: Run probe unit tests**

```bash
cd client && flutter test test/services/terminal/fullscreen_input_screen_probe_test.dart
```

Expected: all PASS (including new wrap cases and existing regressions).

- [ ] **Step 4: Commit implementation**

```bash
git add client/lib/services/terminal/fullscreen_input_screen_probe.dart \
  client/test/services/terminal/fullscreen_input_screen_probe_test.dart
git commit -m "$(cat <<'EOF'
fix(terminal): match fullscreen PTY needles across soft wraps

EOF
)"
```

---

### Task 3: Sanity — automation suite still green

**Files:** none expected (callers unchanged)

- [ ] **Step 1: Run related unit tests**

```bash
cd client && flutter test \
  test/services/terminal/fullscreen_input_screen_probe_test.dart \
  test/services/terminal/fullscreen_pty_automation_test.dart \
  test/services/terminal/pty_automation_needle_test.dart
```

Expected: all PASS.

- [ ] **Step 2: Commit plan doc if not already committed**

```bash
git add docs/superpowers/plans/2026-07-16-fullscreen-pty-wrap-needle.md
git commit -m "$(cat <<'EOF'
docs: plan wrap-aware fullscreen PTY needle matching

EOF
)"
```

(Skip if this plan was committed earlier.)

---

## Manual verification (optional)

Landing a 90-char Chinese prompt into a Claude fullscreen session should log `pty-inject` then submit (no repeating `pty-probe-miss outcome=pasteNotFound` with the text already visible on r48/r49).
