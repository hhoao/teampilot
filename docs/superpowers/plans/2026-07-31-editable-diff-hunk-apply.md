# Editable Diff + Hunk Apply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unstaged side-by-side diffs get an editable working-tree right pane (dirty/Save) and IDEA-style `>>` hunk apply that writes the file and reloads.

**Architecture:** Pure `DiffHunkApplier` builds new working-tree text from a `DiffBlock`. `EditorCubit` owns per-diff-key writable state (`lastLoadedCanonical`, dirty canonical). Display may keep filler alignment; writes never persist fillers. Only `WorkbenchDiffSource.unstaged` is writable. File and Diff tabs use separate buffers and sync on successful write.

**Tech Stack:** Flutter/Dart, `re_editor` `CodeEditor`, existing `DiffEngine` / `DiffBlock`, `EditorCubit` + `Filesystem.atomicWrite`, `flutter_bloc`, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-31-editable-diff-hunk-apply-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/diff/diff_hunk_applier.dart` | Pure `applyLeftToRight` + `canonicalSideText` helper |
| `client/test/services/diff/diff_hunk_applier_test.dart` | Applier unit tests |
| `client/lib/cubits/editor_cubit.dart` | Writable diff state, apply/save, File↔Diff sync |
| `client/test/cubits/editor_cubit_test.dart` | Cubit apply/save/dirty/File sync tests |
| `client/lib/widgets/diff/diff_viewer.dart` | Plumb `writable` / apply / save / dirty callbacks |
| `client/lib/widgets/diff/side_by_side_diff_view.dart` | Right editable + gutter `>>` hit targets |
| `client/lib/widgets/diff/diff_hunk_apply_gutter.dart` | Center-gutter `>>` overlay (keeps ribbon painter paint-only) |
| `client/lib/pages/workbench/diff_editor_surface.dart` | Enable writable for unstaged; wire cubit + confirms |
| `client/lib/pages/workbench/file_editor_surface.dart` | Confirm when Diff dirty before File Save |
| `client/lib/services/workbench/workbench_editor_opener.dart` | Optional `onWorkingTreeWritten` for SCM refresh |
| `client/lib/widgets/git/git_source_control_panel.dart` | Pass refresh callback into `openDiff` |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | New strings |
| `client/test/widgets/diff/side_by_side_diff_writable_test.dart` | Widget: `>>` visible / absent / tap |

**Locked implementer rules:**

1. Writable iff `source == WorkbenchDiffSource.unstaged` **and** side-by-side mode.
2. `>>` never `unlink`s; may `atomicWrite` to recreate a deleted file; empty body → empty file.
3. Dirty `>>`: restore `lastLoadedCanonical` → clear dirty → apply → write → reload. Never apply against dirty text.
4. Do not live-recompute diff on each keystroke.
5. Newline policy: split/join with `\n`; preserve whether final file ends with `\n` by matching `lastLoadedCanonical`’s trailing-newline habit when rejoining (see helper below).

**Canonical text helper (shared):**

```dart
/// Non-filler lines from [side], joined with `\n`.
/// If [preferTrailingNewline] is true, ensure a trailing `\n` when non-empty.
String canonicalSideText(
  List<DiffRow> rows, {
  required bool right,
  bool preferTrailingNewline = false,
}) { /* ... */ }
```

Load `lastLoadedCanonical` for unstaged writable tabs by:
1. Prefer `fs.readString(absolutePath)` when the file exists.
2. Else (deleted): `canonicalSideText(result.rows, right: true)` (usually empty).

Apply always uses the applier against the chosen baseline (`lastLoadedCanonical` after dirty discard).

---

### Task 1: `DiffHunkApplier` pure core

**Files:**
- Create: `client/lib/services/diff/diff_hunk_applier.dart`
- Create: `client/test/services/diff/diff_hunk_applier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/diff/diff_engine.dart';
import 'package:teampilot/services/diff/diff_hunk_applier.dart';
import 'package:teampilot/services/diff/diff_model.dart';

void main() {
  test('applyLeftToRight restores a deleted line (left → right)', () {
    final result = computeLineDiff('a\nb\nc', 'a\nc');
    final block = result.blocks.single;
    expect(block.kind, DiffRowKind.delete);

    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: block,
      rightFileText: 'a\nc',
    );
    expect(next, 'a\nb\nc');
  });

  test('applyLeftToRight drops an inserted line', () {
    final result = computeLineDiff('a\nc', 'a\nb\nc');
    final block = result.blocks.single;
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: block,
      rightFileText: 'a\nb\nc',
    );
    expect(next, 'a\nc');
  });

  test('applyLeftToRight replaces a modify line', () {
    final result = computeLineDiff('hello world', 'hello there');
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: result.blocks.single,
      rightFileText: 'hello there',
    );
    expect(next, 'hello world');
  });

  test('invalid block throws StateError', () {
    final result = computeLineDiff('a', 'b');
    expect(
      () => DiffHunkApplier.applyLeftToRight(
        result: result,
        block: const DiffBlock(startRow: 9, endRow: 10, kind: DiffRowKind.modify),
        rightFileText: 'b',
      ),
      throwsStateError,
    );
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/services/diff/diff_hunk_applier_test.dart`

Expected: FAIL (library / class not found)

- [ ] **Step 3: Implement applier**

Create `diff_hunk_applier.dart`:

```dart
import 'diff_model.dart';

class DiffHunkApplier {
  /// Replace the right-file span covered by [block] with the block's left lines.
  static String applyLeftToRight({
    required DiffResult result,
    required DiffBlock block,
    required String rightFileText,
  }) {
    if (block.startRow < 0 ||
        block.endRow > result.rows.length ||
        block.startRow >= block.endRow) {
      throw StateError('DiffBlock out of range: $block');
    }
    final slice = result.rows.sublist(block.startRow, block.endRow);
    final leftLines = <String>[
      for (final row in slice)
        if (row.hasLeft) row.leftText!,
    ];

    final rightNos = [
      for (final row in slice)
        if (row.hasRight) row.rightLineNo!,
    ];

    final rightLines = _splitLines(rightFileText);
    final hadTrailingNl = rightFileText.endsWith('\n') && rightFileText.isNotEmpty;

    int startIdx; // 0-based inclusive index into rightLines
    int endIdx; // 0-based exclusive
    if (rightNos.isEmpty) {
      // Pure delete on right: insert leftLines at the gap.
      // Find previous right line before the block, else 0.
      startIdx = _insertionIndex(result.rows, block.startRow);
      endIdx = startIdx;
    } else {
      startIdx = rightNos.reduce((a, b) => a < b ? a : b) - 1;
      endIdx = rightNos.reduce((a, b) => a > b ? a : b);
    }

    final out = <String>[
      ...rightLines.sublist(0, startIdx),
      ...leftLines,
      ...rightLines.sublist(endIdx),
    ];
    if (out.isEmpty) return '';
    final body = out.join('\n');
    return hadTrailingNl || rightFileText.isEmpty ? '$body\n' : body;
  }
}

int _insertionIndex(List<DiffRow> rows, int blockStart) { /* prior hasRight → lineNo; else 0 */ }

List<String> _splitLines(String text) {
  if (text.isEmpty) return [];
  final endsWithNl = text.endsWith('\n');
  final core = endsWithNl ? text.substring(0, text.length - 1) : text;
  if (core.isEmpty) return ['']; // file was "\n" only → one empty line? prefer []
  return core.split('\n');
}
```

Also export `canonicalSideText` in the same file (or adjacent). Match `_splitLines` / join rules in tests for trailing newlines (add 1–2 cases).

Tune `_splitLines` / trailing-newline so the four tests above pass; add head/tail/empty/multi-apply cases once green.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/diff/diff_hunk_applier_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/diff/diff_hunk_applier.dart \
  client/test/services/diff/diff_hunk_applier_test.dart
git commit -m "feat(diff): add DiffHunkApplier for left-to-right hunk text"
```

---

### Task 2: EditorCubit writable diff state + apply/save

**Files:**
- Modify: `client/lib/cubits/editor_cubit.dart`
- Modify: `client/test/cubits/editor_cubit_test.dart`

**State shape (private map + public queries):**

```dart
class _WritableDiffHandle {
  _WritableDiffHandle({
    required this.lastLoadedCanonical,
    required this.canonical,
    required this.absolutePath,
    required this.diffKey,
  });

  String lastLoadedCanonical;
  String canonical;
  final String absolutePath;
  final String diffKey;
  bool get isDirty => canonical != lastLoadedCanonical;
}

final Map<String, _WritableDiffHandle> _writableDiffs = {}; // key = diffKey
final Map<String, Future<void> Function()?> _onWorkingTreeWritten = {};
```

Also store `DiffResult?` snapshot used for apply line maps **or** accept `DiffResult` as argument to `applyDiffHunk` from the UI (prefer **pass DiffResult from viewer** so cubit does not re-parse). Cubit still owns canonical strings.

API:

```dart
bool isDiffWritable(String diffKey);
bool isDiffDirty(String diffKey);
String? diffCanonicalFor(String diffKey);

Future<void> bindWritableDiff({
  required String workspaceId,
  required String diffKey,
  required String absolutePath,
  required String lastLoadedCanonical,
  Future<void> Function()? onWorkingTreeWritten,
});

void updateDiffCanonical(String diffKey, String canonical); // marks dirty via emit

/// [discardDirtyIfNeeded] must already be true after UI confirm, or false if clean.
Future<bool> applyDiffHunk({
  required String workspaceId,
  required String diffKey,
  required DiffResult result,
  required DiffBlock block,
  required bool discardDirtyIfNeeded,
});

Future<bool> saveDiffWorkingTree(String workspaceId, String diffKey);

void clearWritableDiff(String diffKey); // from closeDiff
```

`applyDiffHunk` algorithm:
1. If not writable unstaged handle → return false.
2. If dirty && !discardDirtyIfNeeded → return false.
3. If dirty && discardDirtyIfNeeded → `canonical = lastLoadedCanonical`.
4. `next = DiffHunkApplier.applyLeftToRight(...)`.
5. `atomicWrite(path, next)`.
6. On success: update handle + `lastLoadedCanonical = next`; clear dirty; sync File tab (§Task 3); try `diffReload` + `updateDiffText`. If reload returns null / throws: keep disk truth (`lastLoadedCanonical` already updated), set snackbar `diffReloadAfterSaveFailed`, expose `retryDiffReload(workspaceId, diffKey)` for UI retry button/action; still await `onWorkingTreeWritten`.
7. On write fail: snackbar via `diffApplyFailed` / `diffSaveFailed`; return false without reload.

Also add:

```dart
Future<bool> retryDiffReload(String workspaceId, String diffKey);
bool anyWritableDiffDirtyFor(String workspaceId, String absolutePath);
```

`bindWritableDiff` called when opening/updating unstaged diff surface after loading file text.

- [ ] **Step 1: Write failing cubit tests** (InMemoryFilesystem)

Cover:
- bind + updateDiffCanonical → isDiffDirty
- applyDiffHunk clean → file contents match expected; dirty false
- applyDiffHunk while dirty without discard → false, file unchanged
- applyDiffHunk while dirty with discard → restores then applies
- write failure (use a throwing FS stub if available, or chmod) → dirty preserved

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/cubits/editor_cubit_test.dart --name DiffHunk`

- [ ] **Step 3: Implement cubit methods**; call `clearWritableDiff` from `closeDiff`

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/editor_cubit.dart client/test/cubits/editor_cubit_test.dart
git commit -m "feat(editor): writable unstaged diff apply and save"
```

---

### Task 3: File ↔ Diff buffer sync

**Files:**
- Modify: `client/lib/cubits/editor_cubit.dart`
- Modify: `client/test/cubits/editor_cubit_test.dart`

- [ ] **Step 1: Failing tests**

1. Open File + bind writable Diff same path; Diff apply/save → File controller text equals written text; File dirty cleared; snackbar key / message for `diffFileReloadedAfterDiffWrite` when File dirty was discarded.
2. Diff dirty; `saveFile` returns false when called without `discardDiffDirty: true` — implement:

```dart
Future<bool> saveFile(
  String workspaceId,
  String path, {
  bool discardDiffDirty = false,
});

bool anyWritableDiffDirtyFor(String workspaceId, String absolutePath);
```

If any writable diff for `path` is dirty and `!discardDiffDirty` → return false (UI confirms).
3. **File Save while Diff is clean** (required by spec): after successful `saveFile`, always `_reloadDiffsForPath` (re-fetch via registered `DiffReload` + `updateDiffText`, refresh writable `lastLoadedCanonical` from written/disk text). Cover with a test.

- [ ] **Step 2: Implement sync helpers** `_syncFileHandleFromText` / `_reloadDiffsForPath`

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "feat(editor): sync File and Diff buffers on write"
```

---

### Task 4: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

Add keys (names exact):

| Key | EN | ZH |
|-----|----|----|
| `diffApplyHunkTooltip` | Apply change to working tree | 应用到工作区 |
| `diffDiscardEditsApplyTitle` | Discard edits? | 丢弃编辑？ |
| `diffDiscardEditsApplyBody` | Applying this change discards unsaved edits in the diff. | 应用此更改将丢弃 diff 中未保存的编辑。 |
| `diffApplyFailed` | Could not apply change: {error} | 无法应用更改：{error} |
| `diffSaveFailed` | Could not save: {error} | 无法保存：{error} |
| `diffReloadAfterSaveFailed` | Saved, but refreshing the diff failed. | 已保存，但刷新 diff 失败。 |
| `diffFileReloadedAfterDiffWrite` | File tab reloaded from disk. | 已从磁盘重新加载文件页。 |
| `diffDiscardDiffBeforeFileSaveTitle` | Discard diff edits? | 丢弃 diff 编辑？ |
| `diffDiscardDiffBeforeFileSaveBody` | Saving the file will discard unsaved edits in the diff view. | 保存文件将丢弃 diff 视图中未保存的编辑。 |
| `diffApplyDisabledNoPath` | Cannot apply: file path unavailable | 无法应用：文件路径不可用 |

- [ ] **Step 1: Add ARB entries** (both locales)
- [ ] **Step 2: Run codegen if required by project** (`flutter gen-l10n` / existing workflow)
- [ ] **Step 3: Commit**

```bash
git commit -m "l10n: strings for editable diff and hunk apply"
```

---

### Task 5: Wire opener, Git refresh, DiffEditorSurface (no SxS API yet)

**Files:**
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`
- Modify: `client/lib/cubits/editor_cubit.dart` (`openDiff` accepts `onWorkingTreeWritten`)
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Modify: `client/lib/pages/workbench/diff_editor_surface.dart`

Do **not** change `DiffViewer` / `SideBySideDiffView` constructor APIs in this task (that is Task 6). Here only bind cubit state + SCM callback so Task 6 can plug UI into an already-working write path.

- [ ] **Step 1: Extend `openDiff` / opener** with `Future<void> Function()? onWorkingTreeWritten`

In `git_source_control_panel.dart` `_openDiff`:

```dart
onWorkingTreeWritten: () => _cubit.refresh(),
```

(`GitCubit.refresh()` already exists.)

- [ ] **Step 2: DiffEditorSurface bind-only**

When `tab.source == WorkbenchDiffSource.unstaged`:
1. `readString(tab.absolutePath)` (missing → `''`).
2. `bindWritableDiff(...)` with `onWorkingTreeWritten` from opener/cubit map.
3. Keep rendering today’s read-only `DiffViewer.fromUnifiedDiff` (UI still read-only until Task 6).

Staged / changes: do not bind writable.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(diff): bind unstaged writable state and SCM refresh hook"
```

---

### Task 6: DiffViewer + side-by-side UI — editable right + `>>` gutter

**Files:**
- Modify: `client/lib/widgets/diff/diff_viewer.dart`
- Create: `client/lib/widgets/diff/diff_hunk_apply_gutter.dart`
- Modify: `client/lib/widgets/diff/side_by_side_diff_view.dart`
- Modify: `client/lib/pages/workbench/diff_editor_surface.dart` (pass writable props into DiffViewer)
- Create: `client/test/widgets/diff/side_by_side_diff_writable_test.dart`

**Display choice (locked for implementers):** When `writable == true`, right pane shows **canonical text only** (no fillers); left keeps filler-aligned `buildDiffPaneTexts.leftText`. Clean-state 1:1 scroll sync is **best-effort** (map via `rightLineNo` when cheap); do not block v1 on perfect dual-filler alignment. When `writable == false`, keep today’s dual-filler panes.

**UI behavior:**

1. When `writable == false`: current behavior (`readOnly: true`, no `>>`).
2. When `writable == true`:
   - Right `CodeEditor(readOnly: false)`.
   - Drive right controller from **canonical** text; on `result` / canonical reload, reset right from new canonical.
   - Center gutter: stack `DiffRibbonPainter` under a `DiffHunkApplyGutter` that positions a small `>>` button at each block’s vertical center (`topPadding + startRow * lineHeight - scrollOffset`).
   - Tooltip: `diffApplyHunkTooltip`.
   - `onApplyHunk(block)` callback.
3. `DiffViewer` accepts writable props and passes them **only** to `SideBySideDiffView`. Unified mode ignores `writable` (no `>>` even if flag true).

```dart
class DiffHunkApplyGutter extends StatelessWidget {
  const DiffHunkApplyGutter({
    required this.blocks,
    required this.scrollOffset,
    required this.lineHeight,
    required this.topPadding,
    required this.onApply,
    super.key,
  });
  // Stack Positioned IconButton / InkWell ">>" per block
}
```

Widen ribbon column from 24 → ~36 when writable so the button fits.

- [ ] **Step 1: Widget test**

```dart
testWidgets('shows apply control when writable', (tester) async {
  final result = computeLineDiff('a\nb', 'a');
  var applied = false;
  await tester.pumpWidget(
    MaterialApp(
      home: SideBySideDiffView(
        result: result,
        writable: true,
        onApplyHunk: (_) { applied = true; },
        canonicalText: 'a',
        onCanonicalChanged: (_) {},
      ),
    ),
  );
  expect(find.text('>>'), findsWidgets); // or find.byTooltip
  await tester.tap(find.text('>>').first);
  expect(applied, isTrue);
});

testWidgets('hides apply control when not writable', (tester) async {
  final result = computeLineDiff('a\nb', 'a');
  await tester.pumpWidget(
    MaterialApp(home: SideBySideDiffView(result: result)),
  );
  expect(find.text('>>'), findsNothing);
});

testWidgets('unified mode hides apply even when writable flag true', (tester) async {
  // Pump DiffViewer.fromTexts or fromUnifiedDiff with writable: true, mode unified.
  // Expect find.text('>>') findsNothing.
});
```

Wrap with `TpTheme` / localization if required by existing diff tests — copy harness from `side_by_side_diff_view_test.dart`.

- [ ] **Step 2: Implement DiffViewer props + gutter + editable right; wire DiffEditorSurface**

- [ ] **Step 3: Tests PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(diff): side-by-side apply gutter and editable right pane"
```

---

### Task 7: Confirm dialogs + File save gate + Save + reload-retry UX

**Files:**
- Modify: `client/lib/pages/workbench/diff_editor_surface.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`
- Modify: `client/lib/widgets/diff/diff_toolbar.dart` (Save when dirty; optional retry action)
- Modify: `client/lib/cubits/editor_cubit.dart` (ensure `retryDiffReload` from Task 2 is used)

- [ ] **Step 1:** On `>>`, if `isDiffDirty` → `showDialog` with discard title/body; confirm → `applyDiffHunk(..., discardDirtyIfNeeded: true)`; cancel → no-op.

- [ ] **Step 2:** File Save button: if `editor.anyWritableDiffDirtyFor(workspaceId, path)` → confirm → `saveFile(..., discardDiffDirty: true)`.

- [ ] **Step 3:** When Diff dirty, show Save in diff toolbar. Calling Save → `saveDiffWorkingTree`. Toolbar button is enough for v1 (no new global shortcut required).

- [ ] **Step 4: Reload-after-save failure** — when cubit snackbar is `diffReloadAfterSaveFailed` (or dedicated state flag), show a SnackBar **with Retry** action that calls `retryDiffReload(workspaceId, diffKey)`. Cover with a cubit unit test: write succeeds, reload callback throws/returns null → retry succeeds.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(diff): confirm discard flows, save gate, reload retry"
```

---

### Task 8: Verification

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 2: Targeted tests**

Run:

```bash
cd client && flutter test \
  test/services/diff/diff_hunk_applier_test.dart \
  test/cubits/editor_cubit_test.dart \
  test/widgets/diff/side_by_side_diff_writable_test.dart \
  test/widgets/diff/side_by_side_diff_view_test.dart \
  test/widgets/diff/diff_viewer_test.dart
```

- [ ] **Step 3: Fix any failures**

- [ ] **Step 4: Final commit if needed** (analyze/test fixes only)

---

## Manual test checklist (human)

1. Unstaged modify → side-by-side → `>>` restores left hunk → SCM list updates.
2. Type on right → dirty → Save → diff reloads; File tab (if open) matches.
3. Dirty + `>>` → confirm discard → apply succeeds; cancel leaves edits.
4. Staged diff → no `>>`, right read-only.
5. Unified mode → no apply UI.
6. Deleted file unstaged → `>>` recreates file on disk.
