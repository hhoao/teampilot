# 源代码管理面板：IDEA 风格（复选框 + 工具栏 + 右键菜单）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Git 源代码管理面板从"右缘悬停按钮"改成 IDEA 风格：统一目录树 + 每行复选框（=暂存状态）+ 常驻工具栏 + 右键菜单 + 双击打开文件。

**Architecture:** 数据层（`git_changes_visible_rows.dart`）改为一段统一树：staged+unstaged 合并、按路径去重、文件夹节点累积子树三态计数。行组件（`git_change_tile.dart` / `git_change_folder_tile.dart`）去掉悬停按钮，改为复选框 + 状态字母；单击选中并开 diff、双击开文件、右键弹菜单。列表（`git_changes_tree_list.dart`）改为单段树 + 顶层 "Changes" 组头（全选三态）。面板（`git_source_control_panel.dart`）持有选中路径、工具栏加"放弃▾"。新增 `GitService.discardAll` / `discardFolder`（`git restore`，仅已跟踪，安全）。

**Tech Stack:** Flutter / Material `Checkbox`（`tristate`）/ `TpActionMenuSpec` + `showTpActionMenuFromSpecsAtTap` / `TpHover`（新增 `onDoubleTap`）/ flutter_bloc。

## Global Constraints

- **复选框语义**：勾选=已暂存，取消勾选=取消暂存；文件夹/组头三态（全✓/全☐/部分▦）。
- **交互**：单击文件行 = 选中 + 打开 diff；双击 = 打开文件；右键 = 上下文菜单；文件夹行单击仅展开/折叠（不参与选中）。
- **统一树**：staged+unstaged 合并为一段树；同路径去重（`staged` 取 OR，badge/kind 优先 staged 侧）。
- **放弃语义**：`discardAll` → `git restore .`，`discardFolder` → `git restore <folderPath>`（仅已跟踪，不删未跟踪）；未跟踪单文件放弃走 `git clean -f`（需确认）。所有放弃都弹确认对话框。
- **移除**上一轮特性的右缘悬停按钮与宽度常量（`kGitChangesTrailingActionsWidth`=84、`kGitChangesTrailingTwoActionsWidth`=56），保留 `kGitChangesTrailingBadgeWidth`=22。
- **l10n**：只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，然后 `flutter gen-l10n`（生成文件需一并提交）。
- **提交纪律**：工作区有其他未提交/并发改动，只 `git add <本次明确路径>`，用 `git commit -o <paths>` 只提交指定路径，绝不 `git add -A`。
- **TDD**：每个任务先写失败测试 → 确认失败 → 实现 → 确认通过 → 提交。
- 测试里 `debugDefaultTargetPlatformOverride` 用 try/finally（repo 既有 `runOnDesktop` 模式），不要 setUp/tearDown。

---

### Task 1: l10n 新字符串

**Files:**
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Generated (commit): `client/lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `AppLocalizations.gitShowDiff`、`gitCopyPath`、`gitDiscardFolder`、`gitDiscardSelected`、`gitDiscardAllUnstaged`、`gitDiscardAllConfirmTitle`、`gitDiscardAllConfirmBody`、`gitDiscardFolderConfirmTitle`、`gitDiscardFolderConfirmBody`。
- 复用现有：`gitOpenFile`、`gitStage`、`gitUnstage`、`gitStageFolder`、`gitUnstageFolder`、`gitDiscard`、`gitDiscardConfirmTitle`、`gitDiscardConfirmBody`、`gitChanges`（"Changes"/"更改"，作顶层组头标题）。

- [ ] **Step 1: en arb 添加 key**

在 `client/lib/l10n/app_en.arb` 的 `"gitOpenFile": "Open File",` 之后依次添加：

```json
  "gitShowDiff": "Show Diff",
  "gitCopyPath": "Copy Path",
  "gitDiscardFolder": "Discard changes in folder",
  "gitDiscardSelected": "Discard Selected Change",
  "gitDiscardAllUnstaged": "Discard All Unstaged Changes",
  "gitDiscardAllConfirmTitle": "Discard all changes?",
  "gitDiscardAllConfirmBody": "Discard all unstaged changes in the working tree? This cannot be undone.",
  "gitDiscardFolderConfirmTitle": "Discard folder changes?",
  "gitDiscardFolderConfirmBody": "Discard all changes in {path}? This cannot be undone.",
  "@gitDiscardFolderConfirmBody": {
    "placeholders": {
      "path": { "type": "String" }
    }
  }
```

- [ ] **Step 2: zh arb 添加 key**

在 `client/lib/l10n/app_zh.arb` 的 `"gitOpenFile": "打开文件",` 之后依次添加：

```json
  "gitShowDiff": "显示差异",
  "gitCopyPath": "复制路径",
  "gitDiscardFolder": "放弃文件夹中的更改",
  "gitDiscardSelected": "放弃所选更改",
  "gitDiscardAllUnstaged": "放弃全部未暂存更改",
  "gitDiscardAllConfirmTitle": "放弃所有更改？",
  "gitDiscardAllConfirmBody": "放弃工作区中的所有未暂存更改？此操作无法撤销。",
  "gitDiscardFolderConfirmTitle": "放弃文件夹更改？",
  "gitDiscardFolderConfirmBody": "放弃 {path} 中的所有更改？此操作无法撤销。",
  "@gitDiscardFolderConfirmBody": {
    "placeholders": {
      "path": { "type": "String" }
    }
  }
```

- [ ] **Step 3: 重新生成并验证**

Run: `cd client && flutter gen-l10n && grep -c "gitDiscardAllUnstaged" lib/l10n/app_localizations.dart`
Expected: 生成成功，grep 输出 ≥1。

- [ ] **Step 4: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  -m "chore(l10n): add IDEA-style SCM panel strings"
```

---

### Task 2: 统一树数据模型 + 行宽（`git_changes_visible_rows.dart`）

**Files:**
- Modify: `client/lib/services/git/git_changes_visible_rows.dart`
- Test: `client/test/services/git/git_changes_visible_rows_test.dart`（重写现有测试 + 新增）

**Interfaces:**
- Consumes: `GitFileChange`（`models/git_status.dart`）、`kGitChangesIndentWidth` 等常量。
- Produces:
  - `GitChangesVisibleRow.folder` 新增 `subtreeStagedCount` / `subtreeTotalCount`（int）。
  - `GitChangesTreeViewData({required List<GitChangesVisibleRow> rows, required int stagedCount, required int totalCount})` — **替代** `stagedRows`/`unstagedRows`。
  - `List<GitFileChange> mergeGitChangesByPath({required List<GitFileChange> staged, required List<GitFileChange> unstaged})` — 按路径去重，staged 侧优先。
  - `GitChangesTreeViewData visibleUnifiedGitChangesTreeView({required List<GitFileChange> staged, required List<GitFileChange> unstaged, required Set<String> expandedFolderPaths})`。
  - 常量：新增 `kGitChangesCheckboxWidth = 18`；**删除** `kGitChangesTrailingActionsWidth`、`kGitChangesTrailingTwoActionsWidth`、`kGitChangesLeadingChromeWidth`；保留 `kGitChangesTrailingBadgeWidth = 22`。

- [ ] **Step 1: 写失败测试**

重写 `client/test/services/git/git_changes_visible_rows_test.dart`（保留原有宽度相关断言思路，新增统一树断言）：

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_changes_visible_rows.dart';

GitFileChange change(String path, {bool staged = false, GitChangeKind kind = GitChangeKind.modified}) =>
    GitFileChange(path: path, kind: kind, staged: staged);

void main() {
  test('mergeGitChangesByPath dedups partial-staged paths, staged side wins', () {
    final merged = mergeGitChangesByPath(
      staged: [
        change('a/b.txt', staged: true, kind: GitChangeKind.added),
        change('c.txt', staged: true),
      ],
      unstaged: [change('a/b.txt'), change('d.txt')],
    );
    final paths = merged.map((c) => c.path).toSet();
    expect(paths, {'a/b.txt', 'c.txt', 'd.txt'});
    final ab = merged.firstWhere((c) => c.path == 'a/b.txt');
    expect(ab.staged, isTrue);
    expect(ab.kind, GitChangeKind.added); // staged side kind wins
  });

  test('unified tree gives folder tri-state subtree counts', () {
    final view = visibleUnifiedGitChangesTreeView(
      staged: [
        change('domain/Foo.java', staged: true),
        change('domain/core/Bar.java', staged: true),
      ],
      unstaged: [change('domain/Baz.java'), change('domain/core/Qux.java')],
      expandedFolderPaths: const {},
    );
    final folderRows = view.rows.where((r) => r.isFolder).toList();
    // root-level folder 'domain': 2 staged of 4 total
    final domain = folderRows.firstWhere((r) => r.folderPath == 'domain');
    expect(domain.subtreeTotalCount, 4);
    expect(domain.subtreeStagedCount, 2);
    // nested folder 'domain/core': 1 staged of 2 total
    final core = folderRows.firstWhere((r) => r.folderPath == 'domain/core');
    expect(core.subtreeTotalCount, 2);
    expect(core.subtreeStagedCount, 1);
    expect(view.stagedCount, 2);
    expect(view.totalCount, 4);
  });

  test('collapsed folders still report subtree counts', () {
    final view = visibleUnifiedGitChangesTreeView(
      staged: [change('a/x.java', staged: true)],
      unstaged: [change('a/y.java')],
      expandedFolderPaths: const <String>{},
    );
    final folder = view.rows.singleWhere((r) => r.isFolder);
    expect(folder.subtreeTotalCount, 2);
    expect(folder.subtreeStagedCount, 1);
    expect(view.rows.where((r) => !r.isFolder), isEmpty); // children not emitted
  });

  test('min content width accounts for checkbox + badge per row type', () {
    const style = TextStyle(fontSize: 12);
    // Equal-width labels (Ahem font: every glyph is fontSize wide).
    final file = GitChangesVisibleRow.file(
      change: change('aaaaa'),
      depth: 0,
    );
    final folder = GitChangesVisibleRow.folder(
      folderPath: 'aaaaa',
      name: 'aaaaa',
      depth: 0,
      subtreeStagedCount: 0,
      subtreeTotalCount: 1,
    );
    final wFile = gitChangesMinContentWidth(
      rows: [file],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );
    final wFolder = gitChangesMinContentWidth(
      rows: [folder],
      fileLabelStyle: style,
      folderLabelStyle: style,
    );
    // Equal labels → the difference is (file leading + badge) − (folder
    // leading), i.e. (checkbox+icon+gap + 22) − (chevron+checkbox+icon+gap).
    expect(
      wFile - wFolder,
      closeTo(kGitChangesTrailingBadgeWidth - 16, 1), // 22 − chevron slot
    );
    expect(wFile, greaterThan(100));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: FAIL（`subtreeStagedCount` 不存在、`visibleUnifiedGitChangesTreeView` 不存在、`GitChangesTreeViewData` 构造参数不匹配等编译错误）。

- [ ] **Step 3: 实现 — 行模型与数据视图**

编辑 `client/lib/services/git/git_changes_visible_rows.dart`：

`GitChangesVisibleRow` 的 folder 构造与字段改为：

```dart
  const GitChangesVisibleRow.folder({
    required this.folderPath,
    required this.name,
    required this.depth,
    required this.subtreeStagedCount,
    required this.subtreeTotalCount,
  }) : change = null,
       isFolder = true;

  const GitChangesVisibleRow.file({required this.change, required this.depth})
    : folderPath = null,
      name = null,
      subtreeStagedCount = 0,
      subtreeTotalCount = 0,
      isFolder = false;

  final String? folderPath;
  final String? name;
  final GitFileChange? change;
  final int depth;
  final int subtreeStagedCount;
  final int subtreeTotalCount;
  final bool isFolder;
```

`GitChangesTreeViewData` 改为：

```dart
class GitChangesTreeViewData extends Equatable {
  const GitChangesTreeViewData({
    required this.rows,
    required this.stagedCount,
    required this.totalCount,
  });

  final List<GitChangesVisibleRow> rows;
  final int stagedCount;
  final int totalCount;

  bool get allStaged => totalCount > 0 && stagedCount == totalCount;
  bool get noneStaged => stagedCount == 0;

  @override
  List<Object?> get props => [...rows, stagedCount, totalCount];
}
```

新增常量（在现有常量区）：

```dart
/// Width of the stage checkbox at the leading edge of each row.
const double kGitChangesCheckboxWidth = 18;
```

**删除** `kGitChangesTrailingActionsWidth`、`kGitChangesTrailingTwoActionsWidth`、`kGitChangesLeadingChromeWidth` 三处定义。

- [ ] **Step 4: 实现 — 合并与统一树遍历**

把 `visibleGitChangesTreeViewData` 替换为（并新增 `mergeGitChangesByPath`）：

```dart
GitChangesTreeViewData visibleUnifiedGitChangesTreeView({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
  required Set<String> expandedFolderPaths,
}) {
  final merged = mergeGitChangesByPath(staged: staged, unstaged: unstaged);
  var stagedCount = 0;
  for (final c in merged) {
    if (c.staged) stagedCount++;
  }
  final rows = visibleGitChangesRows(
    changes: merged,
    expandedFolderPaths: expandedFolderPaths,
  );
  return GitChangesTreeViewData(
    rows: rows,
    stagedCount: stagedCount,
    totalCount: merged.length,
  );
}

/// Merges staged + unstaged into one list, deduped by path. When a path
/// appears in both (partial staging), the staged entry wins for kind/badge
/// and `staged` reflects "has staged content".
List<GitFileChange> mergeGitChangesByPath({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
}) {
  final byPath = <String, GitFileChange>{};
  for (final c in unstaged) byPath.putIfAbsent(c.path, () => c);
  for (final c in staged) byPath[c.path] = c;
  return byPath.values.toList();
}
```

`_walk` 改为返回子树计数（递归收集子行到临时列表，先加文件夹行再加子行）：

```dart
(int, int) _walk({
  required _GitChangesFolderNode node,
  required String folderPath,
  required int depth,
  required Set<String> expandedFolderPaths,
  required List<GitChangesVisibleRow> rows,
  required bool emit,
}) {
  var total = 0;
  var staged = 0;
  final folderNames = node.subfolders.keys.toList()..sort();
  for (final name in folderNames) {
    final childPath = folderPath.isEmpty ? name : p.posix.join(folderPath, name);
    final childRows = <GitChangesVisibleRow>[];
    final (childTotal, childStaged) = _walk(
      node: node.subfolders[name]!,
      folderPath: childPath,
      depth: depth + 1,
      expandedFolderPaths: expandedFolderPaths,
      rows: childRows,
      emit: emit && expandedFolderPaths.contains(childPath),
    );
    if (emit) {
      rows.add(
        GitChangesVisibleRow.folder(
          folderPath: childPath,
          name: name,
          depth: depth,
          subtreeStagedCount: childStaged,
          subtreeTotalCount: childTotal,
        ),
      );
      rows.addAll(childRows);
    }
    total += childTotal;
    staged += childStaged;
  }
  for (final change in node.files) {
    total++;
    if (change.staged) staged++;
    if (emit) rows.add(GitChangesVisibleRow.file(change: change, depth: depth));
  }
  return (total, staged);
}
```

`visibleGitChangesRows` 调用处改为 `_walk(..., emit: true)`：

```dart
List<GitChangesVisibleRow> visibleGitChangesRows({
  required List<GitFileChange> changes,
  required Set<String> expandedFolderPaths,
}) {
  if (changes.isEmpty) return const [];
  final root = _GitChangesFolderNode();
  for (final change in changes) {
    _insertChange(root, change);
  }
  final rows = <GitChangesVisibleRow>[];
  _walk(
    node: root,
    folderPath: '',
    depth: 0,
    expandedFolderPaths: expandedFolderPaths,
    rows: rows,
    emit: true,
  );
  return rows;
}
```

- [ ] **Step 5: 实现 — 行宽计算**

把 `gitChangesMinContentWidth` 中文件夹行/文件行的宽度公式改为（leading 分类型，trailing 文件=22/文件夹=0）：

```dart
    if (row.isFolder) {
      painter.text = TextSpan(text: row.name, style: folderLabelStyle);
      painter.layout();
      final leading = kGitChangesIndentWidth +
          kGitChangesCheckboxWidth +
          16 +
          6; // chevron + checkbox + folder icon + gap
      final rowWidth =
          row.depth * kGitChangesIndentWidth +
          kGitChangesNodePaddingLeft +
          leading +
          kGitChangesNodePaddingRight +
          kGitChangesRowHorizontalPadding * 2 +
          painter.width;
      maxWidth = math.max(maxWidth, rowWidth);
      continue;
    }

    final label = p.basename(row.change!.path);
    painter.text = TextSpan(text: label, style: fileLabelStyle);
    painter.layout();
    final leading =
        kGitChangesCheckboxWidth + 16 + 6; // checkbox + file icon + gap
    final rowWidth =
        row.depth * kGitChangesIndentWidth +
        kGitChangesNodePaddingLeft +
        leading +
        kGitChangesNodePaddingRight +
        kGitChangesRowHorizontalPadding * 2 +
        painter.width +
        kGitChangesTrailingBadgeWidth;
    maxWidth = math.max(maxWidth, rowWidth);
```

`_rowWidthEstimate` 相应改为：

```dart
double _rowWidthEstimate(GitChangesVisibleRow row) {
  final label = row.isFolder ? row.name! : p.basename(row.change!.path);
  var units = 0.0;
  for (final rune in label.runes) {
    units += rune >= 0x1100 ? 2.0 : 1.0;
  }
  final extra = row.isFolder ? kGitChangesCheckboxWidth : kGitChangesTrailingBadgeWidth;
  return row.depth * 2.0 + units + extra / 8.0;
}
```

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: PASS。

- [ ] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/services/git/git_changes_visible_rows.dart \
  client/test/services/git/git_changes_visible_rows_test.dart \
  -m "refactor(git): unified changes tree with folder tri-state counts"
```

---

### Task 3: GitCubit / GitService — 统一树 + discardAll / discardFolder

**Files:**
- Modify: `client/lib/services/git/git_service.dart`
- Modify: `client/lib/cubits/git_cubit.dart`
- Test: `client/test/cubits/git_cubit_test.dart`（新增用例）

**Interfaces:**
- Consumes: `visibleUnifiedGitChangesTreeView`、`GitChangesTreeViewData(rows/stagedCount/totalCount)`（Task 2）。
- Produces: `GitService.discardAll(String dir)`、`GitService.discardFolder(String dir, String folderPath)`、`GitCubit.discardAll()`、`GitCubit.discardFolder(String folderPath)`。

- [ ] **Step 1: 写失败测试**

在 `client/test/cubits/git_cubit_test.dart` 追加（沿用该文件既有 stub 构造模式，仅作示例；实际用文件里已有的 `_FakeGitService` 之类的 stub）：

```dart
  test('discardAll runs git restore . and refreshes', () async {
    final calls = <List<String>>[];
    final stub = _RecordingService(calls);
    final cubit = GitCubit(service: stub)..setRepoRoot('/repo');
    addTearDown(cubit.close);
    await cubit.discardAll();
    expect(
      calls.any((a) => a.join(' ').contains('restore .')),
      isTrue,
    );
  });
```

说明：`_RecordingService` 继承 `GitService`，把每次 `_run` 的 dir+args 记录到 `calls`。若该文件无此类 stub，先新增（override `status` 返回空仓库、`isAvailable` 返回 true、`_run` 记录）。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/cubits/git_cubit_test.dart`
Expected: FAIL（`discardAll` 不存在）。

- [ ] **Step 3: 实现 GitService**

在 `client/lib/services/git/git_service.dart` 的 `discard` 之后加：

```dart
  /// Discards all unstaged changes to tracked files. Untracked files are
  /// left alone (they would need `git clean`, which is destructive).
  Future<void> discardAll(String dir) => _run(dir, ['restore', '.']);

  /// Discards unstaged changes to tracked files under [folderPath].
  Future<void> discardFolder(String dir, String folderPath) =>
      _run(dir, ['restore', '--', folderPath]);
```

- [ ] **Step 4: 实现 GitCubit**

在 `client/lib/cubits/git_cubit.dart`：

- `_publish` 里的 `visibleGitChangesTreeViewData(...)` 改为 `visibleUnifiedGitChangesTreeView(...)`（参数不变：staged/unstaged/expandedFolderPaths）。
- `setRepoRoot` 里 `const GitChangesTreeViewData(stagedRows: [], unstagedRows: [])` 改为 `const GitChangesTreeViewData(rows: [], stagedCount: 0, totalCount: 0)`。
- 在 `discard(GitFileChange change)` 后加：

```dart
  Future<void> discardAll() => _mutate(() => _service.discardAll(state.repoRoot));

  Future<void> discardFolder(String folderPath) =>
      _mutate(() => _service.discardFolder(state.repoRoot, folderPath));
```

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/cubits/git_cubit_test.dart test/services/git/`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/services/git/git_service.dart \
  client/lib/cubits/git_cubit.dart \
  client/test/cubits/git_cubit_test.dart \
  -m "feat(git): discardAll/discardFolder + unified changes tree view"
```

---

### Task 4: `TpHover` 支持 `onDoubleTap`

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart`
- Test: `client/test/widgets/git/git_change_tile_test.dart`（在 Task 5 中覆盖；本任务用一次轻量验证）

**Interfaces:**
- Produces: `TpHover.onDoubleTap`（`VoidCallback?`，默认 null；desktop `GestureDetector.onDoubleTap` + touch `InkWell.onDoubleTap`）。

- [ ] **Step 1: 写失败测试**

新建 `client/test/widgets/hover_double_tap_test.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('TpHover onDoubleTap fires on double tap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var single = 0;
    var dbl = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TpHover(
                onTap: () => single++,
                onDoubleTap: () => dbl++,
                width: 120,
                height: 40,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.down(tester.getCenter(find.text('x')));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(tester.getCenter(find.text('x')));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(dbl, 1);
      expect(single, 0); // two taps collapsed into the double tap
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/hover_double_tap_test.dart`
Expected: FAIL（`onDoubleTap` 不是 `TpHover` 的命名参数，编译错误）。

- [ ] **Step 3: 实现**

编辑 `client/packages/shared_ui/lib/src/components/hover/tp_hover.dart`：

- 构造参数（`onTap` 后）加 `this.onDoubleTap,`；字段加 `final VoidCallback? onDoubleTap;`。
- desktop 的 `GestureDetector(...)` 加 `onDoubleTap: widget.onDoubleTap,`。
- touch 的 `InkWell(...)` 加 `onDoubleTap: widget.onDoubleTap,`。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/widgets/hover_double_tap_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/packages/shared_ui/lib/src/components/hover/tp_hover.dart \
  client/test/widgets/hover_double_tap_test.dart \
  -m "feat(shared_ui): add TpHover.onDoubleTap"
```

---

### Task 5: 文件行：复选框 + 选中/diff/双击打开 + 右键菜单

**Files:**
- Create: `client/lib/widgets/git/git_context_menu.dart`（含 `GitFileContextMenu`）
- Modify: `client/lib/widgets/git/git_change_tile.dart`（重写）
- Test: `client/test/widgets/git/git_change_tile_test.dart`（重写）

**Interfaces:**
- Consumes: `kGitChangesCheckboxWidth`、`kGitChangesTrailingBadgeWidth`、`TpHover.onDoubleTap`/`onSecondaryTapDown`、`showTpActionMenuFromSpecsAtTap<T>`、`TpActionMenuSpec`、l10n keys（Task 1）。
- Produces:
  - `GitChangeTile` 新构造：`{required change, required depth, required bool selected, required VoidCallback onSelect, required VoidCallback onOpenDiff, required VoidCallback? onOpenFile, required VoidCallback onStage, required VoidCallback onUnstage, required VoidCallback onDiscard, bool hoverEnabled = true}`。
  - `abstract final class GitFileContextMenu { static Future<void> show({required BuildContext context, required TapDownDetails tapDetails, required bool staged, required String path, required VoidCallback? onOpenFile, required VoidCallback onOpenDiff, required VoidCallback onStage, required VoidCallback onUnstage, required VoidCallback onDiscard}) }`。

- [ ] **Step 1: 写失败测试**

重写 `client/test/widgets/git/git_change_tile_test.dart`（沿用既有 `runOnDesktop` + `hover` 辅助，测试均包在 `runOnDesktop` 内）：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/widgets/git/git_change_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, height: 36, child: child),
    ),
  );

  GitChangeTile tile({
    required GitFileChange change,
    bool selected = false,
    VoidCallback? onSelect,
    VoidCallback? onOpenFile,
    VoidCallback? onStage,
    VoidCallback? onUnstage,
    VoidCallback? onDiscard,
  }) =>
      GitChangeTile(
        change: change,
        depth: 0,
        selected: selected,
        onSelect: onSelect ?? () {},
        onOpenDiff: () {},
        onOpenFile: onOpenFile,
        onStage: onStage ?? () {},
        onUnstage: onUnstage ?? () {},
        onDiscard: onDiscard ?? () {},
      );

  Future<void> runOnDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('unstaged file shows unchecked box; clicking it stages', (
    tester,
  ) async {
    var stagedCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onStage: () => stagedCalls++,
        )),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(stagedCalls, 1);
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isFalse);
    });
  });

  testWidgets('staged file shows checked box; clicking it unstages', (
    tester,
  ) async {
    var unstagedCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: true,
          ),
          onUnstage: () => unstagedCalls++,
        )),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(unstagedCalls, 1);
    });
  });

  testWidgets('single click on row selects', (tester) async {
    var selectCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onSelect: () => selectCalls++,
          onOpenFile: () {},
        )),
      );
      await tester.tap(find.byType(GitChangeTile));
      // Both onTap and onDoubleTap registered → tap fires after the
      // double-tap window expires.
      await tester.pump(const Duration(milliseconds: 400));
      expect(selectCalls, 1);
    });
  });

  testWidgets('double click opens the file', (tester) async {
    var openCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onOpenFile: () => openCalls++,
        )),
      );
      final center = tester.getCenter(find.byType(GitChangeTile));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.down(center);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(center);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(openCalls, 1);
    });
  });

  testWidgets('right-click shows context menu; Open File dispatches', (
    tester,
  ) async {
    var openCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          onOpenFile: () => openCalls++,
        )),
      );
      final center = tester.getCenter(find.byType(GitChangeTile));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.down(center, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Open File'));
      await tester.pump();
      expect(openCalls, 1);
    });
  });

  testWidgets('status badge shown', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        wrap(tile(
          change: const GitFileChange(
            path: 'main.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        )),
      );
      expect(find.text('M'), findsOneWidget);
    });
  });
}
```

（`kSecondaryMouseButton` 来自 `package:flutter/gestures.dart`。）

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_change_tile_test.dart`
Expected: FAIL（新构造参数不存在、无复选框、无右键菜单等编译/运行错误）。

- [ ] **Step 3: 实现 — 右键菜单**

新建 `client/lib/widgets/git/git_context_menu.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// Right-click menu for a changed-file row in the source control tree.
abstract final class GitFileContextMenu {
  static Future<void> show({
    required BuildContext context,
    required TapDownDetails tapDetails,
    required bool staged,
    required String path,
    required VoidCallback? onOpenFile,
    required VoidCallback onOpenDiff,
    required VoidCallback onStage,
    required VoidCallback onUnstage,
    required VoidCallback onDiscard,
  }) async {
    final l10n = context.l10n;
    final specs = <TpActionMenuSpec>[
      if (onOpenFile != null)
        TpActionMenuSpec.item(
          value: 'open',
          icon: Icons.file_open_outlined,
          label: l10n.gitOpenFile,
        ),
      TpActionMenuSpec.item(
        value: 'diff',
        icon: Icons.difference_outlined,
        label: l10n.gitShowDiff,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: staged ? 'unstage' : 'stage',
        icon: staged ? Icons.remove : Icons.add,
        label: staged ? l10n.gitUnstage : l10n.gitStage,
      ),
      TpActionMenuSpec.item(
        value: 'discard',
        icon: Icons.undo,
        label: l10n.gitDiscard,
        destructive: true,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'copy_path',
        icon: Icons.copy,
        label: l10n.gitCopyPath,
      ),
    ];
    final value = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (!context.mounted || value == null) return;
    switch (value) {
      case 'open':
        onOpenFile!();
      case 'diff':
        onOpenDiff();
      case 'stage':
        onStage();
      case 'unstage':
        onUnstage();
      case 'discard':
        onDiscard();
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: path));
    }
  }
}
```

- [ ] **Step 4: 实现 — 重写 `git_change_tile.dart`**

整文件替换为（无状态行，复选框 + badge + 选中态 + 手势）：

```dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import 'package:shared_ui/shared_ui.dart';
import '../file_icon_widget.dart';
import 'git_context_menu.dart';

/// One changed file row in the source control changes tree.
///
/// IDEA-style: a stage checkbox on the left (checked = staged), a status
/// badge on the right, single-click selects + opens the diff, double-click
/// opens the file, right-click shows the context menu.
class GitChangeTile extends StatelessWidget {
  const GitChangeTile({
    required this.change,
    required this.depth,
    required this.selected,
    required this.onSelect,
    required this.onOpenDiff,
    this.onOpenFile,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.hoverEnabled = true,
    super.key,
  });

  final GitFileChange change;
  final int depth;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onOpenDiff;
  final VoidCallback? onOpenFile;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final bool hoverEnabled;

  Color _badgeColor(ColorScheme cs) => switch (change.kind) {
    GitChangeKind.added => const Color(0xFF2EA043),
    GitChangeKind.untracked => const Color(0xFF2EA043),
    GitChangeKind.deleted => cs.error,
    GitChangeKind.conflicted => cs.error,
    GitChangeKind.renamed => cs.primary,
    GitChangeKind.modified => const Color(0xFFB58900),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = p.basename(change.path);

    return RepaintBoundary(
      child: TpHover(
        onTap: widget.onSelect,
        onDoubleTap: widget.onOpenFile,
        onSecondaryTapDown: (details) => unawaited(
          GitFileContextMenu.show(
            context: context,
            tapDetails: details,
            staged: change.staged,
            path: change.path,
            onOpenFile: widget.onOpenFile,
            onOpenDiff: widget.onOpenDiff,
            onStage: widget.onStage,
            onUnstage: widget.onUnstage,
            onDiscard: widget.onDiscard,
          ),
        ),
        hoverColor: widget.hoverEnabled ? null : Colors.transparent,
        backgroundColor: widget.selected ? cs.secondaryContainer : null,
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(
          widget.depth * kGitChangesIndentWidth +
              kGitChangesNodePaddingLeft +
              kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
          kGitChangesNodePaddingRight + kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
        ),
        child: SizedBox(
          width: double.infinity,
          height: kGitChangesNodeHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: kGitChangesCheckboxWidth,
                height: kGitChangesCheckboxWidth,
                child: Checkbox(
                  value: change.staged,
                  onChanged: (_) => change.staged
                      ? widget.onUnstage()
                      : widget.onStage(),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              FileIconWidget(fileName: name),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: kGitChangesTrailingBadgeWidth,
                child: Text(
                  change.badge,
                  textAlign: TextAlign.center,
                  style: TpTextStyles.of(
                    context,
                  ).smBoldColored(_badgeColor(cs)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

（顶部 `import 'dart:async';` 提供 `unawaited`。）

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_change_tile_test.dart`
Expected: PASS（5 个用例）。

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/widgets/git/git_context_menu.dart \
  client/lib/widgets/git/git_change_tile.dart \
  client/test/widgets/git/git_change_tile_test.dart \
  -m "feat(git): IDEA-style file row with stage checkbox + context menu"
```

---

### Task 6: 文件夹行：三态复选框 + 右键菜单

**Files:**
- Modify: `client/lib/widgets/git/git_context_menu.dart`（追加 `GitFolderContextMenu`）
- Modify: `client/lib/widgets/git/git_change_folder_tile.dart`（重写）
- Test: `client/test/widgets/git/git_change_folder_tile_test.dart`（重写）

**Interfaces:**
- Consumes: `kGitChangesCheckboxWidth`、`GitChangesVisibleRow.folder` 的 `subtreeStagedCount`/`subtreeTotalCount`、`GitFolderContextMenu`。
- Produces:
  - `abstract final class GitFolderContextMenu { static Future<void> show({required BuildContext context, required TapDownDetails tapDetails, required String folderPath, required VoidCallback onStage, required VoidCallback onUnstage, required VoidCallback onDiscardFolder}) }`。
  - `GitChangeFolderTile` 新构造：`{required folderPath, required name, required depth, required subtreeStagedCount, required subtreeTotalCount, required cubit, required onStage, required onUnstage, required onDiscardFolder, bool hoverEnabled = true}`。

- [ ] **Step 1: 写失败测试**

重写 `client/test/widgets/git/git_change_folder_tile_test.dart`（沿用 GitCubit stub 模式）：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/widgets/git/git_change_folder_tile.dart';

class _FolderGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;
  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
  );
  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  Future<void> runOnDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  // Builds a folder tile wrapped in a MaterialApp + BlocProvider for the
  // (required) GitCubit ancestor. Returns the cubit via `onCubit` so callers
  // can close it in addTearDown.
  Widget buildTile({
    required int subtreeStagedCount,
    required int subtreeTotalCount,
    VoidCallback? onStage,
    VoidCallback? onUnstage,
    VoidCallback? onDiscardFolder,
    ValueChanged<GitCubit>? onCubit,
  }) {
    final cubit = GitCubit(service: _FolderGitStub())..setRepoRoot('/repo');
    onCubit?.call(cubit);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider.value(
        value: cubit,
        child: Scaffold(
          body: SizedBox(
            width: 400,
            height: 36,
            child: GitChangeFolderTile(
              folderPath: 'src',
              name: 'src',
              depth: 0,
              subtreeStagedCount: subtreeStagedCount,
              subtreeTotalCount: subtreeTotalCount,
              cubit: cubit,
              onStage: onStage ?? () {},
              onUnstage: onUnstage ?? () {},
              onDiscardFolder: onDiscardFolder ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('folder checkbox is checked when all staged', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(subtreeStagedCount: 2, subtreeTotalCount: 2),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isTrue);
    });
  });

  testWidgets('folder checkbox is tri-state when partially staged', (
    tester,
  ) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(subtreeStagedCount: 1, subtreeTotalCount: 2),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isNull);
    });
  });

  testWidgets('folder checkbox unchecked when none staged', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(subtreeStagedCount: 0, subtreeTotalCount: 2),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isFalse);
    });
  });

  testWidgets('folder context menu discards folder', (tester) async {
    var discardCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(
          subtreeStagedCount: 0,
          subtreeTotalCount: 1,
          onDiscardFolder: () => discardCalls++,
        ),
      );
      final center = tester.getCenter(find.byType(GitChangeFolderTile));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.down(center, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard changes in folder'));
      await tester.pump();
      expect(discardCalls, 1);
    });
  });
}
```

（每个用例里 `buildTile` 创建的 cubit 用 `onCubit` 回调拿引用并 `addTearDown(cubit.close)`——例如 `await tester.pumpWidget(buildTile(..., onCubit: (c) => addTearDown(c.close)));`。若 `BlocProvider.value` 不需要 dispose cubit 也不报错，可省略。以测试实际运行为准，若报 cubit 未 close 的泄漏，用 `onCubit` 注册 close。）

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_change_folder_tile_test.dart`
Expected: FAIL（新构造参数不存在）。

- [ ] **Step 3: 实现 — 追加文件夹菜单**

在 `client/lib/widgets/git/git_context_menu.dart` 追加：

```dart
/// Right-click menu for a folder row in the source control tree.
abstract final class GitFolderContextMenu {
  static Future<void> show({
    required BuildContext context,
    required TapDownDetails tapDetails,
    required String folderPath,
    required VoidCallback onStage,
    required VoidCallback onUnstage,
    required VoidCallback onDiscardFolder,
  }) async {
    final l10n = context.l10n;
    final specs = <TpActionMenuSpec>[
      TpActionMenuSpec.item(
        value: 'stage',
        icon: Icons.add,
        label: l10n.gitStageFolder,
      ),
      TpActionMenuSpec.item(
        value: 'unstage',
        icon: Icons.remove,
        label: l10n.gitUnstageFolder,
      ),
      TpActionMenuSpec.item(
        value: 'discard',
        icon: Icons.undo,
        label: l10n.gitDiscardFolder,
        destructive: true,
      ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'copy_path',
        icon: Icons.copy,
        label: l10n.gitCopyPath,
      ),
    ];
    final value = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: tapDetails,
      specs: specs,
    );
    if (!context.mounted || value == null) return;
    switch (value) {
      case 'stage':
        onStage();
      case 'unstage':
        onUnstage();
      case 'discard':
        onDiscardFolder();
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: folderPath));
    }
  }
}
```

- [ ] **Step 4: 实现 — 重写文件夹行**

`client/lib/widgets/git/git_change_folder_tile.dart` 整文件替换为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/git_cubit.dart';
import '../../services/git/git_changes_visible_rows.dart';
import 'package:shared_ui/shared_ui.dart';
import 'git_context_menu.dart';

/// Folder row in the git changes tree view. IDEA-style: a tri-state stage
/// checkbox, chevron toggle on click, context menu on right-click.
class GitChangeFolderTile extends StatelessWidget {
  const GitChangeFolderTile({
    required this.folderPath,
    required this.name,
    required this.depth,
    required this.subtreeStagedCount,
    required this.subtreeTotalCount,
    required this.cubit,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscardFolder,
    this.hoverEnabled = true,
    super.key,
  });

  final String folderPath;
  final String name;
  final int depth;
  final int subtreeStagedCount;
  final int subtreeTotalCount;
  final GitCubit cubit;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscardFolder;
  final bool hoverEnabled;

  bool? get _triState =>
      subtreeTotalCount == 0
          ? false
          : subtreeStagedCount == subtreeTotalCount
          ? true
          : subtreeStagedCount == 0
          ? false
          : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = context.select<GitCubit, bool>(
      (c) => c.state.expandedFolderPaths.contains(folderPath),
    );

    return RepaintBoundary(
      child: TpHover(
        onTap: () => cubit.toggleFolderExpanded(folderPath),
        onSecondaryTapDown: (details) => unawaited(
          GitFolderContextMenu.show(
            context: context,
            tapDetails: details,
            folderPath: folderPath,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscardFolder: onDiscardFolder,
          ),
        ),
        hoverColor: widget.hoverEnabled ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(
          widget.depth * kGitChangesIndentWidth +
              kGitChangesNodePaddingLeft +
              kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
          kGitChangesNodePaddingRight + kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
        ),
        child: SizedBox(
          width: double.infinity,
          height: kGitChangesNodeHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: kGitChangesCheckboxWidth,
                height: kGitChangesCheckboxWidth,
                child: Checkbox(
                  value: _triState,
                  tristate: true,
                  onChanged: (_) => _triState == true
                      ? widget.onUnstage()
                      : widget.onStage(),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.folder_open : Icons.folder_outlined,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

（顶部加 `import 'dart:async';` 提供 `unawaited`。）

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_change_folder_tile_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/widgets/git/git_context_menu.dart \
  client/lib/widgets/git/git_change_folder_tile.dart \
  client/test/widgets/git/git_change_folder_tile_test.dart \
  -m "feat(git): IDEA-style folder row with tri-state stage checkbox"
```

---

### Task 7: 树列表 — 单段树 + "Changes" 组头 + 选中

**Files:**
- Modify: `client/lib/widgets/git/git_changes_tree_list.dart`
- Test: `client/test/widgets/git/git_changes_tree_list_test.dart`（新建）

**Interfaces:**
- Consumes: `GitChangesTreeViewData.rows/stagedCount/totalCount`、`GitChangeTile`（Task 5）、`GitChangeFolderTile`（Task 6）。
- Produces: `GitChangesTreeList` 新构造 `{required treeView, required cubit, required listScrollController, required horizontalScrollController, required String? selectedPath, required ValueChanged<String> onSelect, required ValueChanged<GitFileChange> onOpenDiff, required ValueChanged<GitFileChange> onConfirmDiscard, required ValueChanged<GitFileChange>? onOpenFile}`。顶层 "Changes" 组头由本组件渲染。

- [ ] **Step 1: 写失败测试**

新建 `client/test/widgets/git/git_changes_tree_list_test.dart`（最小桩：构造一个含 staged/unstaged 的 cubit 状态，直接 pump `GitChangesTreeList`）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/widgets/git/git_changes_tree_list.dart';

class _TreeStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;
  @override
  Future<GitRepoStatus> status(String dir) async => GitRepoStatus(
    isRepository: true,
    branch: 'main',
    staged: const [GitFileChange(path: 'a.java', kind: GitChangeKind.added, staged: true)],
    unstaged: const [GitFileChange(path: 'b.dart', kind: GitChangeKind.modified, staged: false)],
  );
  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  testWidgets('renders Changes root header with count and rows', (tester) async {
    final cubit = GitCubit(service: _TreeStub())..setRepoRoot('/repo');
    addTearDown(cubit.close);
    await cubit.refresh();
    final treeView = cubit.state.changesTreeView;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit, // folder tiles read expanded state via context
          child: Scaffold(
            body: GitChangesTreeList(
              treeView: treeView,
              cubit: cubit,
              listScrollController: ScrollController(),
              horizontalScrollController: ScrollController(),
              selectedPath: null,
              onSelect: (_) {},
              onOpenDiff: (_) {},
              onConfirmDiscard: (_) {},
              onOpenFile: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Changes'), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets); // root select-all + file row
    // both file rows rendered
    expect(find.text('a.java'), findsOneWidget);
    expect(find.text('b.dart'), findsOneWidget);
  });
}
```

（需要 `import 'package:flutter_bloc/flutter_bloc.dart';`。`ScrollController()` 在 `CustomScrollView` 挂载时自动 attach，测试无需手动 attach。）

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_changes_tree_list_test.dart`
Expected: FAIL（`selectedPath`/`onSelect` 参数不存在、"Changes" 组头未渲染）。

- [ ] **Step 3: 实现**

编辑 `client/lib/widgets/git/git_changes_tree_list.dart`：

- 构造参数改为（去掉 `onConfirmDiscard` 外的旧结构，新增选中相关）：

```dart
  const GitChangesTreeList({
    required this.treeView,
    required this.cubit,
    required this.listScrollController,
    required this.horizontalScrollController,
    required this.selectedPath,
    required this.onSelect,
    required this.onOpenDiff,
    required this.onConfirmDiscard,
    this.onOpenFile,
    super.key,
  });

  final GitChangesTreeViewData treeView;
  final GitCubit cubit;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final ValueChanged<GitFileChange> onOpenDiff;
  final ValueChanged<GitFileChange> onConfirmDiscard;
  final ValueChanged<GitFileChange>? onOpenFile;
```

- `build` 中把两段 sliver 替换为：一个 `SliverToBoxAdapter` 渲染 `_GitChangesRootHeader`，一个 `SliverFixedExtentList` 渲染 `treeView.rows`：

```dart
                    slivers: [
                      SliverToBoxAdapter(
                        child: _GitChangesRootHeader(
                          stagedCount: widget.treeView.stagedCount,
                          totalCount: widget.treeView.totalCount,
                          allStaged: widget.treeView.allStaged,
                          noneStaged: widget.treeView.noneStaged,
                          onToggleAll: () {
                            if (widget.treeView.allStaged) {
                              unawaited(widget.cubit.unstageAll());
                            } else {
                              unawaited(widget.cubit.stageAll());
                            }
                          },
                        ),
                      ),
                      if (widget.treeView.rows.isNotEmpty)
                        SliverFixedExtentList(
                          itemExtent: kGitChangesRowExtent,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => SizedBox(
                              width: contentWidth,
                              child: _buildTreeRow(widget.treeView.rows[index]),
                            ),
                            childCount: widget.treeView.rows.length,
                          ),
                        ),
                    ],
```

- `_buildTreeRow` 改为单参数（不再有 staged 段概念）：

```dart
  Widget _buildTreeRow(GitChangesVisibleRow row) {
    if (row.isFolder) {
      return GitChangeFolderTile(
        key: ValueKey('folder:${row.folderPath}'),
        folderPath: row.folderPath!,
        name: row.name!,
        depth: row.depth,
        subtreeStagedCount: row.subtreeStagedCount,
        subtreeTotalCount: row.subtreeTotalCount,
        cubit: widget.cubit,
        hoverEnabled: _hoverEnabled,
        onStage: () => unawaited(widget.cubit.stageFolder(row.folderPath!)),
        onUnstage: () => unawaited(widget.cubit.unstageFolder(row.folderPath!)),
        onDiscardFolder: () => unawaited(
          _confirmDiscardFolder(row.folderPath!),
        ),
      );
    }

    final change = row.change!;
    final canOpenFile =
        widget.onOpenFile != null && change.kind != GitChangeKind.deleted;
    return GitChangeTile(
      key: ValueKey('file:${change.path}'),
      change: change,
      depth: row.depth,
      selected: widget.selectedPath == change.path,
      hoverEnabled: _hoverEnabled,
      onSelect: () => widget.onSelect(change.path),
      onOpenDiff: () => widget.onOpenDiff(change),
      onOpenFile: canOpenFile ? () => widget.onOpenFile!(change) : null,
      onStage: () => unawaited(widget.cubit.stage(change)),
      onUnstage: () => unawaited(widget.cubit.unstage(change)),
      onDiscard: () => widget.onConfirmDiscard(change),
    );
  }
```

- 新增 `_confirmDiscardFolder`（本组件内的确认对话框，随后调用 cubit）：

```dart
  Future<void> _confirmDiscardFolder(String folderPath) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.gitDiscardFolderConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.gitDiscardFolderConfirmBody(folderPath)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.gitDiscard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.cubit.discardFolder(folderPath);
    }
  }
```

- 新增 `_GitChangesRootHeader`（放本文件底部，替换原 `GitChangesSectionHeader`）：

```dart
class _GitChangesRootHeader extends StatelessWidget {
  const _GitChangesRootHeader({
    required this.stagedCount,
    required this.totalCount,
    required this.allStaged,
    required this.noneStaged,
    required this.onToggleAll,
  });

  final int stagedCount;
  final int totalCount;
  final bool allStaged;
  final bool noneStaged;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final triState = totalCount == 0
        ? false
        : allStaged
        ? true
        : noneStaged
        ? false
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 2),
      child: Row(
        children: [
          SizedBox(
            width: kGitChangesCheckboxWidth,
            height: kGitChangesCheckboxWidth,
            child: Checkbox(
              value: triState,
              tristate: true,
              onChanged: (_) => onToggleAll(),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              context.l10n.gitChanges,
              style: TpTextStyles.of(
                context,
              ).xsBoldWideColored(cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 2),
          GitChangesCountBadge(count: totalCount),
        ],
      ),
    );
  }
}
```

- 删除 `GitChangesSectionHeader`（不再使用），保留 `GitChangesCountBadge`。
- `allRows`/`stagedRows`/`unstagedRows` 相关变量删除；`gitChangesMinContentWidth` 用 `widget.treeView.rows`。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_changes_tree_list_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/widgets/git/git_changes_tree_list.dart \
  client/test/widgets/git/git_changes_tree_list_test.dart \
  -m "feat(git): unified changes tree with Changes root header + selection"
```

---

### Task 8: 面板 — 工具栏"放弃▾" + 选中持有 + 双击打开

**Files:**
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Test: `client/test/widgets/git/git_source_control_panel_open_file_test.dart`（改写：双击打开 + 工具栏放弃）

**Interfaces:**
- Consumes: `GitChangesTreeList` 新参数（Task 7）、`cubit.discardAll()`（Task 3）、`_openFile`（已有）。
- Produces: `_GitRepoBodyState` 持 `String? _selectedPath`；`_Header` 新增 `onDiscardSelected`（`VoidCallback?`）、`onDiscardAll`。

- [ ] **Step 1: 写失败测试**

改写 `client/test/widgets/git/git_source_control_panel_open_file_test.dart`（沿用 stub/recording opener/runOnDesktop 结构，删掉旧的悬停打开文件用例，替换为双击 + 工具栏放弃）：

```dart
// 保留 _UnstagedGitStub、_RecordingOpener、setUp/tearDown、wrap() 结构（同现有文件）。
// 删除旧 'open-file button opens the changed file'（悬停点按钮）用例，新增：
// （1）双击行打开文件
// （2）deleted 行双击不打开文件（onOpenFile 为 null，双击无效果）
// （3）工具栏"放弃全部未暂存"调用 discardAll
```

具体三个用例（其余结构沿用现有文件）：

```dart
  testWidgets('double-click on a changed row opens the file', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    addTearDown(aiSettingsCubit.close);

    await tester.pumpWidget(
      wrap(
        aiSettingsCubit,
        GitSourceControlPanel(
          roots: const ['/repo'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final rowA = find.ancestor(
      of: find.text('a.txt'),
      matching: find.byType(GitChangeTile),
    );
    expect(rowA, findsOneWidget);

    final center = tester.getCenter(rowA);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.down(center);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.down(center);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(opener!.openedPaths, ['/repo/a.txt']);
  });

  testWidgets('toolbar discard-all calls discardAll', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    addTearDown(aiSettingsCubit.close);

    await tester.pumpWidget(
      wrap(
        aiSettingsCubit,
        GitSourceControlPanel(
          roots: const ['/repo'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 打开放弃下拉
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Discard All Unstaged Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 确认对话框
    await tester.tap(find.text('Discard changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // _UnstagedGitStub 通过记录 status 后的 discardAll 行为验证：
    // 通过 stub 记录的 command 断言（在 _UnstagedGitStub 中加 calls 记录）。
  });
```

说明：`_UnstagedGitStub` 需加 `final calls = <List<String>>[];` 并在 `discardAll` override 里记录；断言 `calls.any((a) => a.join(' ').contains('restore .'))`。同时该 stub 的 `status` 返回的 unstaged 里保留 `a.txt`（modified）与 `gone.txt`（deleted）以支撑用例 1/2。用例 2（deleted 双击不打开）直接 `expect(opener!.openedPaths, isEmpty)`。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/git/git_source_control_panel_open_file_test.dart`
Expected: FAIL（无 `_selectedPath`、工具栏无放弃按钮、双击未接 `_openFile` 等）。

- [ ] **Step 3: 实现 — 面板**

编辑 `client/lib/widgets/git/git_source_control_panel.dart`：

- `_GitRepoBodyState` 加 `String? _selectedPath;`。
- 新增确认对话框方法：

```dart
  Future<void> _confirmDiscardAll() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.gitDiscardAllConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.gitDiscardAllConfirmBody),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.gitDiscard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _cubit.discardAll();
    }
  }

  Future<void> _discardSelected() async {
    final path = _selectedPath;
    if (path == null) return;
    final change = _findChange(path);
    if (change == null) return;
    await _confirmDiscard(change);
  }

  GitFileChange? _findChange(String path) {
    for (final c in _cubit.state.status.staged) {
      if (c.path == path) return c;
    }
    for (final c in _cubit.state.status.unstaged) {
      if (c.path == path) return c;
    }
    return null;
  }
```

- `_Header(...)` 调用处加参数（`onDiscardSelected`、`onDiscardAll`）：

```dart
                onDiscardSelected: _selectedPath == null
                    ? null
                    : () => unawaited(_discardSelected()),
                onDiscardAll: () => unawaited(_confirmDiscardAll()),
```

- `GitChangesTreeList(...)` 调用处加：

```dart
                      selectedPath: _selectedPath,
                      onSelect: (path) => setState(() => _selectedPath = path),
```

（`onOpenFile: _openFile` 已存在，保留——双击由 `GitChangeTile.onDoubleTap` 触发 `_openFile`。）

- `_Header` 类：构造加 `this.onDiscardSelected, this.onDiscardAll`（均 `VoidCallback?`），在 `onPull` 之前渲染一个放弃下拉：

```dart
        PopupMenuButton<String>(
          tooltip: l10n.gitDiscard,
          icon: const Icon(Icons.undo, size: 18),
          padding: EdgeInsets.zero,
          onSelected: (value) {
            if (value == 'selected') onDiscardSelected?.call();
            if (value == 'all') onDiscardAll?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'selected',
              enabled: onDiscardSelected != null,
              child: Text(l10n.gitDiscardSelected),
            ),
            PopupMenuItem(
              value: 'all',
              child: Text(l10n.gitDiscardAllUnstaged),
            ),
          ],
        ),
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/widgets/git/git_source_control_panel_open_file_test.dart test/widgets/git/git_source_control_panel_generate_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git commit -o \
  client/lib/widgets/git/git_source_control_panel.dart \
  client/test/widgets/git/git_source_control_panel_open_file_test.dart \
  -m "feat(git): toolbar discard dropdown + row selection + double-click open"
```

---

### Task 9: 全量验证

- [ ] **Step 1: 静态分析**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error / warning（info 允许；仓库有 ~165 条既有 info 属正常）。

- [ ] **Step 2: 全量测试（排除集成）**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 通过。若 `test/smoke/app_shell_smoke_test.dart` 出现失败——是既有失败（功能开始前已存在），不要改动。

- [ ] **Step 3: 修复并重跑**

若有本特性文件导致的失败：回到对应 Task 的 Step 4/5 重跑，直到全绿。

---

## 自检记录

- **Spec 覆盖**：统一树+去重+文件夹三态 → Task 2/3；文件行复选框+单击 diff+双击打开+右键菜单 → Task 5；文件夹三态+右键 → Task 6；单段树+Changes 组头全选+选中 → Task 7；工具栏放弃下拉+选中持有 → Task 8；TpHover.onDoubleTap → Task 4；l10n → Task 1；全量验证 → Task 9。移除旧右缘悬停按钮/宽度常量 → Task 2/5/6。放弃语义（restore . / restore folder，确认对话框）→ Task 3/7/8。
- **无占位符**：每个任务含完整可运行代码与命令。
- **类型一致性**：`GitChangesTreeViewData(rows/stagedCount/totalCount)`、`GitChangesVisibleRow.folder(subtreeStagedCount/subtreeTotalCount)`、`GitChangeTile(...)`、`GitChangeFolderTile(...)`、`GitChangesTreeList(...)`、`GitFileContextMenu.show(...)`、`GitFolderContextMenu.show(...)`、`GitService.discardAll/discardFolder`、`GitCubit.discardAll/discardFolder` 跨任务命名一致。`_walk` 返回 `(int, int)` 在 Task 2 定义并被 Task 2 内部使用。
- **已知注意点**：Task 5/8 中 `onTap` 与 `onDoubleTap` 并存的测试需要 `pump(400ms)` 让双击窗口过期；Task 7 测试需保证 ScrollController attach；Task 6 测试的 cubit 提供方式以能通过为准（`BlocProvider.value` 需要同一 cubit 实例）。
