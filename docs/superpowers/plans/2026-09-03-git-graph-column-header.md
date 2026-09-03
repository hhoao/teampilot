# Git Graph column header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a VS Code–style hideable column header (`Graph | Description | Date | Author | Commit`), reorder row meta to Date→Author, show 8-char hash with tap-to-copy, and persist visibility in `LayoutPreferences`.

**Architecture:** Shared `GitGraphColumns` metrics drive both `GitGraphColumnHeader` and `GitGraphRowTile`. Visibility is `LayoutPreferences.gitGraphHeaderVisible` toggled from the toolbar and header context menu via `LayoutCubit`. Header sits above the list (does not scroll).

**Tech Stack:** Flutter, flutter_bloc `LayoutCubit`, existing `TpIconButton` / `TpActionMenu`, arb l10n.

**Spec:** `docs/superpowers/specs/2026-09-03-git-graph-column-header-design.md`

## Global Constraints

- Edit only `app_en.arb` / `app_zh.arb` for l10n (then regenerate or hand-sync generated locals if the project expects it).
- Do not commit unless the user asks (ignore per-task commit steps during execution; leave working tree ready to commit).
- Keep narrow-pane overflow protection (existing row tile regression tests must still pass).
- Out of scope: resizable/reorderable columns, per-column hide.

---

### Task 1: Persist `gitGraphHeaderVisible`

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Test: `client/test/models/layout_preferences_default_test.dart`

**Interfaces:**
- Produces: `LayoutPreferences.gitGraphHeaderVisible` (`bool`, default `true`); `LayoutCubit.setGitGraphHeaderVisible(bool visible)` → `_save(copyWith(...))`

- [ ] **Step 1: Write the failing test**

Add to `layout_preferences_default_test.dart`:

```dart
test('gitGraphHeaderVisible defaults true and round-trips', () {
  expect(LayoutPreferences.fromJson(const {}).gitGraphHeaderVisible, isTrue);
  final parsed = LayoutPreferences.fromJson(const {
    'gitGraphHeaderVisible': false,
  });
  expect(parsed.gitGraphHeaderVisible, isFalse);
  final restored = LayoutPreferences.fromJson(parsed.toJson());
  expect(restored.gitGraphHeaderVisible, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart --name gitGraphHeaderVisible`

Expected: FAIL (getter / key missing)

- [ ] **Step 3: Minimal implementation**

In `LayoutPreferences`:
- Add field `this.gitGraphHeaderVisible = true` to constructor
- `fromJson`: `gitGraphHeaderVisible: json['gitGraphHeaderVisible'] as bool? ?? true`
- `copyWith`: optional `bool? gitGraphHeaderVisible`
- `toJson`: `'gitGraphHeaderVisible': gitGraphHeaderVisible`
- Update `==` / `hashCode` / any `withAtLeastOneToolVisible` clone that rebuilds `LayoutPreferences(...)` to pass the field through

In `LayoutCubit`:

```dart
Future<void> setGitGraphHeaderVisible(bool visible) =>
    _save(state.preferences.copyWith(gitGraphHeaderVisible: visible));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart --name gitGraphHeaderVisible`

Expected: PASS

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 2: Shared column metrics + row Date/Author/Commit

**Files:**
- Create: `client/lib/pages/git_graph/git_graph_columns.dart`
- Modify: `client/lib/pages/git_graph/git_graph_row_tile.dart`
- Test: `client/test/pages/git_graph/git_graph_row_tile_test.dart`

**Interfaces:**
- Produces:

```dart
abstract final class GitGraphColumns {
  static const double headerHeight = 26;
  static const double rowHeight = 28;
  static const double trailingPadding = 12;
  static const double afterGraphGap = 8;
  static const double metaGap = 8;
  static const double commitWidth = 72; // ~8 monospace chars
  static const double dateMinWidth = 88;
  static const int descriptionFlex = 10;
  static const int dateFlex = 2;
  static const int authorFlex = 2;
  static const int refsFlex = 3;
  static double graphWidthFor({required int maxLane}) =>
      (maxLane + 1) * GitGraphLanePainter.defaultLaneWidth;
  static String shortHash(String hash) =>
      hash.length <= 8 ? hash : hash.substring(0, 8);
}
```

- Row order becomes: Graph | Description | Date | Author | Commit
- Commit cell: `GitGraphColumns.shortHash(row.hash)`, monospace/`TpTextStyles` mono if available else `fontFamily` from theme; `onTap` on hash must not steal row select — use a nested `GestureDetector` with `onTap` that copies hash + `showAppToast(l10n.gitGraphHashCopied)` and stop propagation, **or** wire `onCommitHashTap` callback from pane. Prefer callback `VoidCallback? onCommitHashTap` on the tile so tests can assert without clipboard flakiness; pane supplies copy+toast.

- [ ] **Step 1: Write failing tests**

Extend `git_graph_row_tile_test.dart`:

```dart
testWidgets('columns are Date then Author then short hash', (tester) async {
  await pump(tester, SizedBox(
    height: 28,
    width: 700,
    child: GitGraphRowTile(
      row: makeRow('abcdef12deadbeef'),
      selected: false,
      onTap: () {},
    ),
  ));
  expect(find.text('abcdef12'), findsOneWidget);
  final dateDx = tester.getTopLeft(find.textContaining('08/25')).dx;
  final authorDx = tester.getTopLeft(find.text('Ann')).dx;
  final hashDx = tester.getTopLeft(find.text('abcdef12')).dx;
  expect(dateDx, lessThan(authorDx));
  expect(authorDx, lessThan(hashDx));
});

testWidgets('commit hash tap invokes onCommitHashTap', (tester) async {
  var tapped = false;
  await pump(tester, SizedBox(
    height: 28,
    width: 700,
    child: GitGraphRowTile(
      row: makeRow('abcdef12deadbeef'),
      selected: false,
      onTap: () {},
      onCommitHashTap: () => tapped = true,
    ),
  ));
  await tester.tap(find.text('abcdef12'));
  expect(tapped, isTrue);
});
```

Keep existing overflow + subject-flex regression tests green (update if Date/Author swap breaks finders).

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/pages/git_graph/git_graph_row_tile_test.dart`

- [ ] **Step 3: Implement columns helper + row tile**

Create `git_graph_columns.dart` with the constants above.

Refactor `GitGraphRowTile` row children to:

```dart
SizedBox(width: graphW, child: CustomPaint(...)),
SizedBox(width: GitGraphColumns.afterGraphGap),
Expanded(
  flex: GitGraphColumns.descriptionFlex,
  child: /* refs Flexible + subject Expanded (existing) */,
),
SizedBox(width: GitGraphColumns.metaGap),
Flexible(
  flex: GitGraphColumns.dateFlex,
  fit: FlexFit.loose,
  child: Text(date, ...),
),
SizedBox(width: GitGraphColumns.metaGap),
Flexible(
  flex: GitGraphColumns.authorFlex,
  fit: FlexFit.loose,
  child: Text(author, ...),
),
SizedBox(width: GitGraphColumns.metaGap),
SizedBox(
  width: GitGraphColumns.commitWidth,
  child: GestureDetector(
    onTap: onCommitHashTap,
    child: Text(GitGraphColumns.shortHash(row.hash), ...),
  ),
),
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/pages/git_graph/git_graph_row_tile_test.dart`

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 3: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate or update: `app_localizations*.dart` per project convention (`flutter gen-l10n` from `client/`)

**Keys:**

| Key | en | zh |
|-----|----|----|
| `gitGraphColumnGraph` | Graph | 图 |
| `gitGraphColumnDescription` | Description | 说明 |
| `gitGraphColumnDate` | Date | 日期 |
| `gitGraphColumnAuthor` | Author | 作者 |
| `gitGraphColumnCommit` | Commit | 提交 |
| `gitGraphShowColumnHeader` | Show column header | 显示列头 |
| `gitGraphHideColumnHeader` | Hide column header | 隐藏列头 |

- [ ] **Step 1: Add arb entries** (both files)
- [ ] **Step 2: Run `cd client && flutter gen-l10n`** (or project’s documented command)
- [ ] **Step 3: Sanity** — new getters compile

- [ ] **Step 4: Commit** (skip unless user asks)

---

### Task 4: `GitGraphColumnHeader` widget

**Files:**
- Create: `client/lib/pages/git_graph/git_graph_column_header.dart`
- Test: `client/test/pages/git_graph/git_graph_column_header_test.dart`

**Interfaces:**
- Consumes: `GitGraphColumns`, l10n keys from Task 3
- Produces:

```dart
class GitGraphColumnHeader extends StatelessWidget {
  const GitGraphColumnHeader({
    super.key,
    this.graphWidth = 24,
    required this.onHide,
  });
  final double graphWidth;
  final VoidCallback onHide;
}
```

Header row mirrors data flex: empty/label over Graph (`graphWidth`), then Description/Date/Author/Commit labels with same flex/width as `GitGraphColumns`. Bottom border. `onSecondaryTapUp` → `TpActionMenu` / existing menu helper with one action calling `onHide`.

- [ ] **Step 1: Failing test**

```dart
testWidgets('renders five column labels', (tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: GitGraphColumnHeader(onHide: () {}),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Graph'), findsOneWidget);
  expect(find.text('Description'), findsOneWidget);
  expect(find.text('Date'), findsOneWidget);
  expect(find.text('Author'), findsOneWidget);
  expect(find.text('Commit'), findsOneWidget);
});

testWidgets('secondary tap can hide via callback', (tester) async {
  var hidden = false;
  // pump header; simulate secondary tap / open menu and tap Hide
  // assert hidden == true
});
```

Use the same menu pattern as other git graph menus (`showTpActionMenu` / `TpActionMenuSpec`) — match `git_graph_menus.dart` style in the test.

- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Implement header widget**
- [ ] **Step 4: Run — PASS**
- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 5: Wire pane + toolbar toggle

**Files:**
- Modify: `client/lib/pages/git_graph/git_graph_toolbar.dart`
- Modify: `client/lib/pages/git_graph/git_graph_pane.dart`
- Modify: `_UncommittedTile` in pane to use the same trailing column scaffold (empty Date/Author/Commit slots) when practical
- Test: `client/test/pages/git_graph/git_graph_pane_header_test.dart` (new) **or** extend an existing pane test if one hosts `LayoutCubit`

**Interfaces:**
- Toolbar: read `context.select<LayoutCubit, bool>((c) => c.state.preferences.gitGraphHeaderVisible)`; `TpIconButton` toggles `setGitGraphHeaderVisible`; icon `Icons.view_column_outlined` (or `Icons.table_rows_outlined`); tooltip `gitGraphShowColumnHeader` / `gitGraphHideColumnHeader`
- `_PaneBody` Column children:

```dart
GitGraphToolbar(state: state),
if (headerVisible)
  GitGraphColumnHeader(
    graphWidth: /* min width used by list or fixed 24 */,
    onHide: () => context.read<LayoutCubit>().setGitGraphHeaderVisible(false),
  ),
Expanded(child: _GraphList(...)),
```

- Pass `onCommitHashTap` into `GitGraphRowTile` from `_commitTile`: copy `row.hash` + `showAppToast(gitGraphHashCopied)`.

- [ ] **Step 1: Widget test** — with fake/real `LayoutCubit` + prefs repo in memory: header present by default; tap toolbar hides; tap again shows; when visible, secondary-hide works

- [ ] **Step 2: Run — FAIL**
- [ ] **Step 3: Wire toolbar + pane**
- [ ] **Step 4: Run header + row + layout prefs tests**

Run:

```bash
cd client && flutter test \
  test/models/layout_preferences_default_test.dart \
  test/pages/git_graph/git_graph_row_tile_test.dart \
  test/pages/git_graph/git_graph_column_header_test.dart \
  test/pages/git_graph/git_graph_pane_header_test.dart
```

Expected: all PASS

- [ ] **Step 5: Commit** (skip unless user asks)

---

## Spec coverage checklist

| Spec item | Task |
|-----------|------|
| Column order Graph/Description/Date/Author/Commit | 2, 4 |
| Short hash + copy | 2, 5 |
| Hideable header default on | 1, 5 |
| Toolbar toggle | 5 |
| Header context menu hide | 4, 5 |
| Persist preference | 1 |
| Shared metrics | 2, 4 |
| l10n | 3 |
| Narrow overflow | 2 (keep existing test) |
| No resizable columns | — (out of scope) |
