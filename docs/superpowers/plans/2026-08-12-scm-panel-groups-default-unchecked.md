# SCM 面板分组与默认勾选 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 源代码管理面板把变更分为「Changes」(已跟踪)与「Unversioned Files」(未跟踪)两个分组,未跟踪新文件默认不勾选(对齐 IDEA)。

**Architecture:** 数据层 `visibleGitChangesSections` 把合并后的变更按 `GitChangeKind.untracked` 分成两组,复用现有 `visibleGitChangesRows` 折叠树逻辑构建两个 `GitChangesTreeViewData`。`GitState` 增加 `unversionedTreeView` 字段;`_reconcileSelectedPaths` 只对「已跟踪或已暂存」的新变更自动勾选。UI 层 `GitChangesTreeList` 在同一 `CustomScrollView` 里渲染两个分组(各自带三态全选头),面板传入两个视图。

**Tech Stack:** Flutter/Dart, flutter_bloc cubits, `flutter gen-l10n`, flutter_test。

## Global Constraints

- l10n:只改 `client/lib/l10n/app_en.arb` + `app_zh.arb`,然后 `cd client && flutter gen-l10n`(生成文件 `app_localizations*.dart` 需一并提交,不手改)。
- 勾选 = 「纳入下次提交」的纯 UI 选择模型(`selectedPaths`),不执行 `git add`;`commitSelected` 在提交时 `git add -- <paths>`。不得引入真实 git stage 命令。
- 禁止 `print`;用户可见文案走 l10n;诊断走 `AppLogger`。
- 验证命令:`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`(单任务可先跑相关测试文件)。
- 不在 `docs/` 之外新建文件;遵循现有命名/风格。

---

### Task 1: 数据层 — 分组构建器

**Files:**
- Modify: `client/lib/services/git/git_changes_visible_rows.dart:211-237`
- Modify: `client/lib/cubits/git_cubit.dart:9-13`(export)与 `:140-154`(`_publish` 调用点)
- Test: `client/test/services/git/git_changes_visible_rows_test.dart`

**Interfaces:**
- Produces:
  - `enum GitChangesSection { changes, unversioned }`
  - `class GitChangesSections extends Equatable { final GitChangesTreeViewData changes; final GitChangesTreeViewData unversioned; }`
  - `GitChangesSections visibleGitChangesSections({required List<GitFileChange> staged, required List<GitFileChange> unstaged, required Set<String> expandedFolderPaths, required Set<String> selectedPaths})`
  - `GitChangesTreeViewData visibleGitChangesTreeView({required List<GitFileChange> changes, required Set<String> expandedFolderPaths, required Set<String> selectedPaths})`
- Removes: `visibleUnifiedGitChangesTreeView`(调用点同步迁移到 `visibleGitChangesSections(...).changes`)

- [ ] **Step 1: 写失败测试**

在 `client/test/services/git/git_changes_visible_rows_test.dart` 末尾追加:

```dart
  test('sections split untracked files into the unversioned group', () {
    final sections = visibleGitChangesSections(
      staged: [change('a.txt', staged: true)],
      unstaged: [
        change('b.dart'),
        change('new.ts', kind: GitChangeKind.untracked),
      ],
      expandedFolderPaths: const {},
      selectedPaths: const {'b.dart'},
    );
    expect(
      sections.changes.rows
          .where((r) => !r.isFolder)
          .map((r) => r.change!.path),
      ['a.txt', 'b.dart'],
    );
    expect(
      sections.unversioned.rows
          .where((r) => !r.isFolder)
          .map((r) => r.change!.path),
      ['new.ts'],
    );
    expect(sections.changes.selectedCount, 1); // b.dart selected
    expect(sections.changes.totalCount, 2);
    expect(sections.unversioned.selectedCount, 0); // new.ts unchecked
    expect(sections.unversioned.totalCount, 1);
  });

  test('sections project checkbox state per section from selectedPaths', () {
    final sections = visibleGitChangesSections(
      staged: const [],
      unstaged: [
        change('a.txt'),
        change('new.ts', kind: GitChangeKind.untracked),
      ],
      expandedFolderPaths: const {},
      selectedPaths: const {'a.txt', 'new.ts'}, // tracked auto-checked + manual check of an unversioned file
    );
    final a = sections.changes.rows
        .firstWhere((r) => !r.isFolder && r.change!.path == 'a.txt');
    final n = sections.unversioned.rows
        .firstWhere((r) => !r.isFolder && r.change!.path == 'new.ts');
    expect(a.change!.staged, isTrue);
    expect(n.change!.staged, isTrue); // manual check survives projection
    expect(sections.changes.selectedCount, 1);    expect(sections.unversioned.selectedCount, 1);
  });
```

同时把本文件里 4 处 `visibleUnifiedGitChangesTreeView(` 改为 `visibleGitChangesSections(` 并追加 `.changes`(第 27、50、64、77 行;输入全是已跟踪变更,语义不变)。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: FAIL — `visibleGitChangesSections` 未定义。

- [ ] **Step 3: 实现分组构建器**

把 `client/lib/services/git/git_changes_visible_rows.dart:211-237` 的 `visibleUnifiedGitChangesTreeView` 整体替换为:

```dart
/// Which change group a source-control section shows.
enum GitChangesSection { changes, unversioned }

/// The two source-control sections: tracked changes and unversioned files.
class GitChangesSections extends Equatable {
  const GitChangesSections({required this.changes, required this.unversioned});

  final GitChangesTreeViewData changes;
  final GitChangesTreeViewData unversioned;

  @override
  List<Object?> get props => [changes, unversioned];
}

/// Builds both source-control sections from a status snapshot.
GitChangesSections visibleGitChangesSections({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
  required Set<String> expandedFolderPaths,
  required Set<String> selectedPaths,
}) {
  final merged = mergeGitChangesByPath(staged: staged, unstaged: unstaged);
  final changes = <GitFileChange>[];
  final unversioned = <GitFileChange>[];
  for (final c in merged) {
    (c.kind == GitChangeKind.untracked ? unversioned : changes).add(c);
  }
  return GitChangesSections(
    changes: visibleGitChangesTreeView(
      changes: changes,
      expandedFolderPaths: expandedFolderPaths,
      selectedPaths: selectedPaths,
    ),
    unversioned: visibleGitChangesTreeView(
      changes: unversioned,
      expandedFolderPaths: expandedFolderPaths,
      selectedPaths: selectedPaths,
    ),
  );
}

/// One section's tree: projects the checkbox state from [selectedPaths] (the
/// UI "include in next commit" selection, not the git index).
GitChangesTreeViewData visibleGitChangesTreeView({
  required List<GitFileChange> changes,
  required Set<String> expandedFolderPaths,
  required Set<String> selectedPaths,
}) {
  final projected = <GitFileChange>[
    for (final c in changes) c.copyWith(staged: selectedPaths.contains(c.path)),
  ];
  var selectedCount = 0;
  for (final c in projected) {
    if (c.staged) selectedCount++;
  }
  final rows = visibleGitChangesRows(
    changes: projected,
    expandedFolderPaths: expandedFolderPaths,
  );
  return GitChangesTreeViewData(
    rows: rows,
    selectedCount: selectedCount,
    totalCount: changes.length,
  );
}
```

- [ ] **Step 4: 迁移 cubit 调用点,保持编译**

`client/lib/cubits/git_cubit.dart:9-13` 的 export 改为:

```dart
export '../services/git/git_changes_visible_rows.dart'
    show GitChangesTreeViewData, GitChangesVisibleRow, GitChangesSection, GitChangesSections;
```

`git_cubit.dart:144-149` 的 `_publish` 改为:

```dart
    if (recomputeRows) {
      final sections = visibleGitChangesSections(
        staged: next.status.staged,
        unstaged: next.status.unstaged,
        expandedFolderPaths: next.expandedFolderPaths,
        selectedPaths: next.selectedPaths,
      );
      published = next.copyWith(changesTreeView: sections.changes);
    }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart test/cubits/git_cubit_test.dart`
Expected: PASS(全部)。

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/git/git_changes_visible_rows.dart client/lib/cubits/git_cubit.dart client/test/services/git/git_changes_visible_rows_test.dart
git commit -m "feat(git): build changes/unversioned sections from one status snapshot"
```

---

### Task 2: GitCubit — 默认勾选规则与分组级选择操作

**Files:**
- Modify: `client/lib/cubits/git_cubit.dart`(state 字段、`_publish`、`_reconcileSelectedPaths`、`selectFolder`/`deselectFolder`/`selectAll`/`selectNone`)
- Modify: `client/lib/widgets/git/git_changes_tree_list.dart:150-154,192-193`(调用点带 `GitChangesSection.changes`)
- Test: `client/test/cubits/git_cubit_test.dart`

**Interfaces:**
- Consumes: `GitChangesSection`、`visibleGitChangesSections`(Task 1)
- Produces:
  - `GitState.unversionedTreeView` (`GitChangesTreeViewData`)
  - `Future<void> selectFolder(String folderPath, GitChangesSection section)`
  - `Future<void> deselectFolder(String folderPath, GitChangesSection section)`
  - `Future<void> selectAll(GitChangesSection section)`
  - `Future<void> selectNone(GitChangesSection section)`
- Removes: 无参 `selectAll()`/`selectNone()`(所有调用点迁到带参版本)

- [ ] **Step 1: 写失败测试**

`client/test/cubits/git_cubit_test.dart` 修改与追加:

(a) 第 156 行 `await cubit.selectNone();` → `await cubit.selectNone(GitChangesSection.changes);`
(b) 第 317 行 `await cubit.selectAll();` → `await cubit.selectAll(GitChangesSection.changes);`
(c) 第 291-310 行 reconcile 测试的第二次 status 追加未跟踪与已暂存文件,并改断言:

```dart
    // next refresh adds a NEW tracked file c.txt (auto-checked), an index-staged
    // file staged.txt (auto-checked), and a NEW untracked file new.ts (NOT
    // auto-checked). b.txt stays unchecked.
    service.statusToReturn = _repoWith(
      unstaged: const [
        _unstaged,
        GitFileChange(
          path: 'c.txt',
          kind: GitChangeKind.modified,
          staged: false,
        ),
        GitFileChange(
          path: 'new.ts',
          kind: GitChangeKind.untracked,
          staged: false,
        ),
      ],
      staged: const [
        GitFileChange(path: 'staged.txt', kind: GitChangeKind.added, staged: true),
      ],
    );
    await cubit.refresh();
    expect(cubit.state.selectedPaths, {'c.txt', 'staged.txt'});
```

(d) 追加新测试(放在 reconcile 测试之后):

```dart
  test('untracked files are not auto-checked on first load', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          _unstaged,
          GitFileChange(
            path: 'new.ts',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');

    expect(cubit.state.selectedPaths, {'b.txt'}); // new.ts NOT selected
    expect(cubit.state.unversionedTreeView.totalCount, 1);
    expect(cubit.state.changesTreeView.totalCount, 1);
    await cubit.close();
  });

  test('selectAll on a section only selects that section', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          _unstaged,
          GitFileChange(
            path: 'new.ts',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // b.txt auto-selected, new.ts not

    await cubit.selectNone(GitChangesSection.changes);
    expect(cubit.state.selectedPaths, isEmpty);

    await cubit.selectAll(GitChangesSection.unversioned);
    expect(cubit.state.selectedPaths, {'new.ts'});

    await cubit.selectAll(GitChangesSection.changes);
    expect(cubit.state.selectedPaths, {'new.ts', 'b.txt'});
    await cubit.close();
  });

  test('selectFolder is scoped to its section', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          GitFileChange(
            path: 'docs/a.md',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          GitFileChange(
            path: 'docs/new.md',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    await cubit.selectNone(GitChangesSection.changes);
    await cubit.selectNone(GitChangesSection.unversioned);

    await cubit.selectFolder('docs', GitChangesSection.changes);
    expect(cubit.state.selectedPaths, {'docs/a.md'});

    await cubit.selectFolder('docs', GitChangesSection.unversioned);
    expect(cubit.state.selectedPaths, {'docs/a.md', 'docs/new.md'});
    await cubit.close();
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/cubits/git_cubit_test.dart`
Expected: FAIL — `selectNone`/`selectAll` 参数不匹配、`unversionedTreeView` 不存在、untracked 被自动勾选。

- [ ] **Step 3: 实现 state 字段**

`GitState`(git_cubit.dart:28-32)默认值追加:

```dart
    this.unversionedTreeView = const GitChangesTreeViewData(
      rows: [],
      selectedCount: 0,
      totalCount: 0,
    ),
```

字段声明(`:53` 的 `changesTreeView` 之后):

```dart
  /// Flattened rows for the unversioned-files section (new/untracked paths).
  final GitChangesTreeViewData unversionedTreeView;
```

`copyWith`(`:78` 之后)追加 `GitChangesTreeViewData? unversionedTreeView,`;构造函数传参追加 `unversionedTreeView: unversionedTreeView ?? this.unversionedTreeView,`;`props`(`:111` 之后)追加 `unversionedTreeView,`。

`setRepoRoot`(git_cubit.dart:168-172)的 reset copyWith 追加:

```dart
        unversionedTreeView: const GitChangesTreeViewData(
          rows: [],
          selectedCount: 0,
          totalCount: 0,
        ),
```

- [ ] **Step 4: 实现 `_publish` 双视图**

git_cubit.dart:143-151 改为:

```dart
    if (recomputeRows) {
      final sections = visibleGitChangesSections(
        staged: next.status.staged,
        unstaged: next.status.unstaged,
        expandedFolderPaths: next.expandedFolderPaths,
        selectedPaths: next.selectedPaths,
      );
      published = next.copyWith(
        changesTreeView: sections.changes,
        unversionedTreeView: sections.unversioned,
      );
    }
```

- [ ] **Step 5: 实现默认勾选规则**

`_reconcileSelectedPaths`(git_cubit.dart:274-285)改为:

```dart
  /// Keeps manual selection across refreshes: drops paths that vanished,
  /// auto-checks newly-appeared tracked or index-staged changes (untracked
  /// worktree files stay unchecked, IDEA-style), preserves everything else.
  Set<String> _reconcileSelectedPaths(GitRepoStatus status) {
    final changedNow = <String>{
      for (final c in status.staged) c.path,
      for (final c in status.unstaged) c.path,
    };
    final autoCheckable = <String>{
      for (final c in status.staged) c.path,
      for (final c in status.unstaged)
        if (c.kind != GitChangeKind.untracked) c.path,
    };
    final next = <String>{
      ...state.selectedPaths.where(changedNow.contains),
      ...autoCheckable.difference(_knownChangedPaths),
    };
    _knownChangedPaths = changedNow;
    return next;
  }
```

- [ ] **Step 6: 实现分组级选择操作**

git_cubit.dart:361-390 替换为:

```dart
  Future<void> selectFolder(String folderPath, GitChangesSection section) async {
    final changed = _changedPathsUnder(folderPath, section);
    _publish(state.copyWith(selectedPaths: {...state.selectedPaths, ...changed}));
  }

  Future<void> deselectFolder(String folderPath, GitChangesSection section) async {
    final changed = _changedPathsUnder(folderPath, section);
    final next = {...state.selectedPaths}..removeAll(changed);
    _publish(state.copyWith(selectedPaths: next));
  }

  Future<void> selectAll(GitChangesSection section) async {
    _publish(
      state.copyWith(selectedPaths: {...state.selectedPaths, ..._sectionPaths(section)}),
    );
  }

  Future<void> selectNone(GitChangesSection section) async {
    final next = {...state.selectedPaths}..removeAll(_sectionPaths(section));
    _publish(state.copyWith(selectedPaths: next));
  }

  /// All changed paths that belong to [section] (untracked ⇔ unversioned).
  Set<String> _sectionPaths(GitChangesSection section) => <String>{
    for (final c in mergeGitChangesByPath(
      staged: state.status.staged,
      unstaged: state.status.unstaged,
    ))
      if ((c.kind == GitChangeKind.untracked) ==
          (section == GitChangesSection.unversioned))
        c.path,
  };

  Set<String> _changedPathsUnder(String folderPath, GitChangesSection section) =>
      <String>{
        for (final path in _sectionPaths(section))
          if (path == folderPath || path.startsWith('$folderPath/')) path,
      };
```

注意 `selectAll(section)` 语义是「在该分组上执行全选」= 并上该分组所有路径(原实现是整体替换,这里改为并集,保证跨分组选择互不覆盖);`selectNone(section)` 只移除该分组路径。

- [ ] **Step 7: 更新 lib 调用点**

`client/lib/widgets/git/git_changes_tree_list.dart:150-156`:

```dart
                          onToggleAll: () {
                            if (widget.treeView.allSelected) {
                              unawaited(widget.cubit.selectNone(GitChangesSection.changes));
                            } else {
                              unawaited(widget.cubit.selectAll(GitChangesSection.changes));
                            }
                          },
```

`git_changes_tree_list.dart:192-193`:

```dart
        onStage: () => unawaited(widget.cubit.selectFolder(row.folderPath!, GitChangesSection.changes)),
        onUnstage: () => unawaited(widget.cubit.deselectFolder(row.folderPath!, GitChangesSection.changes)),
```

- [ ] **Step 8: 运行测试确认通过**

Run: `cd client && flutter test test/cubits/git_cubit_test.dart test/widgets/git/git_changes_tree_list_test.dart`
Expected: PASS。

- [ ] **Step 9: 提交**

```bash
git add client/lib/cubits/git_cubit.dart client/lib/widgets/git/git_changes_tree_list.dart client/test/cubits/git_cubit_test.dart
git commit -m "feat(git): unversioned files unchecked by default; section-scoped selection"
```

---

### Task 3: l10n — Unversioned Files 标题

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated (commit): `client/lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `String get gitUnversionedFiles`(无参数 getter)

- [ ] **Step 1: en arb 添加 key**

在 `client/lib/l10n/app_en.arb` 的 `"gitStagedChanges": "Staged Changes",` 之后插入:

```json
  "gitUnversionedFiles": "Unversioned Files",
```

- [ ] **Step 2: zh arb 添加 key**

在 `client/lib/l10n/app_zh.arb` 的 `"gitStagedChanges": "暂存的更改",` 之后插入:

```json
  "gitUnversionedFiles": "未版本化的文件",
```

- [ ] **Step 3: 重新生成 l10n 并验证**

Run: `cd client && flutter gen-l10n && grep -c "gitUnversionedFiles" lib/l10n/app_localizations.dart`
Expected: `1`(抽象 getter 声明;`app_localizations_en.dart`/`app_localizations_zh.dart` 同步生成实现)。

- [ ] **Step 4: 提交**

```bash
git add client/lib/l10n/
git commit -m "chore(l10n): add unversioned files section title"
```

---

### Task 4: GitChangesTreeList — 双分组渲染

**Files:**
- Modify: `client/lib/widgets/git/git_changes_tree_list.dart`
- Test: `client/test/widgets/git/git_changes_tree_list_test.dart`

**Interfaces:**
- Consumes: `GitChangesSection`(Task 1)、`selectAll(section)`/`selectNone(section)`/`selectFolder(path, section)`(Task 2)、`context.l10n.gitUnversionedFiles`(Task 3)
- Produces: `GitChangesTreeList({required GitChangesTreeViewData changesTreeView, required GitChangesTreeViewData unversionedTreeView, ...})`(原 `treeView` 参数移除)

- [ ] **Step 1: 写失败测试**

(a) `_TreeStub`(git_changes_tree_list_test.dart:24-30)的 `unstaged` 追加:

```dart
      GitFileChange(
        path: 'new.cpp',
        kind: GitChangeKind.untracked,
        staged: false,
      ),
```

(b) `buildTreeList`(test 第 61 行)与第一个测试(第 93 行)的 `treeView:` 改为:

```dart
              changesTreeView: cubit.state.changesTreeView,
              unversionedTreeView: cubit.state.unversionedTreeView,
```

(c) 第一个测试(`renders Changes root header with count and rows`)的断言追加:

```dart
    expect(find.text('Unversioned Files'), findsOneWidget);
    expect(find.text('new.cpp'), findsOneWidget);
```

(d) 第四个测试(`root select-all is checked...`)改为用 key 定位,并追加 unversioned 分组测试:

```dart
  testWidgets(
    'root select-all is checked when all selected; tapping it clears the selection',
    (tester) async {
      final cubit = GitCubit(service: _TreeStub());
      addTearDown(cubit.close);
      await cubit.setRepoRoot('/repo'); // a.java + b.dart auto-selected; new.cpp not
      await tester.pumpWidget(buildTreeList(cubit: cubit));
      await tester.pump();

      final changesToggle = find.byKey(
        const ValueKey('git-section-toggle-changes'),
      );
      expect(tester.widget<Checkbox>(changesToggle).value, isTrue);

      await tester.tap(changesToggle);
      await tester.pump();
      // selectNone(changes) is a pure selection op now, so the tracked
      // selection clears; new.cpp was never selected.
      expect(cubit.state.selectedPaths, isEmpty);
    },
  );

  testWidgets('unversioned section select-all adds unversioned files', (
    tester,
  ) async {
    final cubit = GitCubit(service: _TreeStub());
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo'); // new.cpp unchecked by default
    await tester.pumpWidget(buildTreeList(cubit: cubit));
    await tester.pump();

    final unversionedToggle = find.byKey(
      const ValueKey('git-section-toggle-unversioned'),
    );
    expect(tester.widget<Checkbox>(unversionedToggle).value, isFalse);

    await tester.tap(unversionedToggle);
    await tester.pump();
    // selectAll(section) is additive: tracked a.java/b.dart stay selected.
    expect(cubit.state.selectedPaths, {'a.java', 'b.dart', 'new.cpp'});
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/widgets/git/git_changes_tree_list_test.dart`
Expected: FAIL — 构造参数 `treeView` 不存在/未传递 `unversionedTreeView`、`Unversioned Files` 文本缺失。

- [ ] **Step 3: 改造构造函数与 slivers**

`GitChangesTreeList` 构造函数(`:17-29`)的 `treeView` 参数替换为两个视图:

```dart
  final GitChangesTreeViewData changesTreeView;
  final GitChangesTreeViewData unversionedTreeView;
```

`_GitChangesTreeListState.build`(`:108-179`)的 `contentWidth` 计算改为覆盖两个视图:

```dart
        final contentWidth = math.max(
          constraints.maxWidth,
          math.max(
            gitChangesMinContentWidth(
              rows: widget.changesTreeView.rows,
              fileLabelStyle: fileLabelStyle,
              folderLabelStyle: folderLabelStyle,
              textScaler: MediaQuery.textScalerOf(context),
            ),
            widget.unversionedTreeView.rows.isEmpty
                ? 0.0
                : gitChangesMinContentWidth(
                    rows: widget.unversionedTreeView.rows,
                    fileLabelStyle: fileLabelStyle,
                    folderLabelStyle: folderLabelStyle,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
          ),
        );
```

`CustomScrollView.slivers`(`:144-170`)替换为:

```dart
                    slivers: [
                      ..._sectionSlivers(
                        view: widget.changesTreeView,
                        section: GitChangesSection.changes,
                        contentWidth: contentWidth,
                      ),
                      if (widget.unversionedTreeView.totalCount > 0)
                        ..._sectionSlivers(
                          view: widget.unversionedTreeView,
                          section: GitChangesSection.unversioned,
                          contentWidth: contentWidth,
                        ),
                    ],
```

新增方法(放在 `_buildTreeRow` 之前):

```dart
  /// Header + rows slivers for one section. Empty sections render only their
  /// header (the caller skips the whole group when [GitChangesTreeViewData.totalCount] is 0).
  List<Widget> _sectionSlivers({
    required GitChangesTreeViewData view,
    required GitChangesSection section,
    required double contentWidth,
  }) {
    return [
      SliverToBoxAdapter(
        child: _GitChangesRootHeader(
          section: section,
          title: section == GitChangesSection.changes
              ? context.l10n.gitChanges
              : context.l10n.gitUnversionedFiles,
          totalCount: view.totalCount,
          allSelected: view.allSelected,
          noneSelected: view.noneSelected,
          onToggleAll: () {
            if (view.allSelected) {
              unawaited(widget.cubit.selectNone(section));
            } else {
              unawaited(widget.cubit.selectAll(section));
            }
          },
        ),
      ),
      if (view.rows.isNotEmpty)
        SliverFixedExtentList(
          itemExtent: kGitChangesRowExtent,
          delegate: SliverChildBuilderDelegate(
            (context, index) => SizedBox(
              width: contentWidth,
              child: _buildTreeRow(view.rows[index], section),
            ),
            childCount: view.rows.length,
          ),
        ),
    ];
  }
```

- [ ] **Step 4: 行构建带 section**

`_buildTreeRow`(`:181-214`)改为接收 `section` 并在 key 与 folder 回调中传递:

```dart
  Widget _buildTreeRow(GitChangesVisibleRow row, GitChangesSection section) {
    final keyPrefix =
        section == GitChangesSection.changes ? 'changes' : 'unversioned';
    if (row.isFolder) {
      return GitChangeFolderTile(
        key: ValueKey('$keyPrefix:folder:${row.folderPath}'),
        folderPath: row.folderPath!,
        name: row.name!,
        depth: row.depth,
        subtreeSelectedCount: row.subtreeSelectedCount,
        subtreeTotalCount: row.subtreeTotalCount,
        cubit: widget.cubit,
        hoverEnabled: _hoverEnabled,
        onStage: () => unawaited(
          widget.cubit.selectFolder(row.folderPath!, section),
        ),
        onUnstage: () => unawaited(
          widget.cubit.deselectFolder(row.folderPath!, section),
        ),
        onDiscardFolder: () => unawaited(_confirmDiscardFolder(row.folderPath!)),
      );
    }

    final change = row.change!;
    final canOpenFile =
        widget.onOpenFile != null && change.kind != GitChangeKind.deleted;
    return GitChangeTile(
      key: ValueKey('$keyPrefix:file:${change.path}'),
      change: change,
      depth: row.depth,
      selected: widget.selectedPath == change.path,
      hoverEnabled: _hoverEnabled,
      onSelect: () => widget.onSelect(change.path),
      onOpenDiff: () => widget.onOpenDiff(change),
      onOpenFile: canOpenFile ? () => widget.onOpenFile!(change) : null,
      onStage: () => unawaited(widget.cubit.selectPath(change.path)),
      onUnstage: () => unawaited(widget.cubit.deselectPath(change.path)),
      onDiscard: () => widget.onConfirmDiscard(change),
    );
  }
```

- [ ] **Step 5: 根头组件支持标题与 section**

`_GitChangesRootHeader`(`:223-275`)改为:

```dart
class _GitChangesRootHeader extends StatelessWidget {
  const _GitChangesRootHeader({
    required this.section,
    required this.title,
    required this.totalCount,
    required this.allSelected,
    required this.noneSelected,
    required this.onToggleAll,
  });

  final GitChangesSection section;
  final String title;
  final int totalCount;
  final bool allSelected;
  final bool noneSelected;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final triState = totalCount == 0
        ? false
        : allSelected
        ? true
        : noneSelected
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
              key: ValueKey('git-section-toggle-${section.name}'),
              value: triState,
              tristate: true,
              onChanged: (_) => onToggleAll(),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
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

同步更新文件头注释(`:15-16`)为「Flattened git changes tree (Changes + Unversioned Files sections)」。

- [ ] **Step 6: 运行测试确认通过**

Run: `cd client && flutter test test/widgets/git/git_changes_tree_list_test.dart`
Expected: PASS(全部)。

- [ ] **Step 7: 提交**

```bash
git add client/lib/widgets/git/git_changes_tree_list.dart client/test/widgets/git/git_changes_tree_list_test.dart
git commit -m "feat(git): render Changes and Unversioned Files sections in SCM tree"
```

---

### Task 5: GitSourceControlPanel — 挂载双分组

**Files:**
- Modify: `client/lib/widgets/git/git_source_control_panel.dart:593-635`

**Interfaces:**
- Consumes: `GitChangesTreeList(changesTreeView:..., unversionedTreeView:...)`(Task 4)、`GitState.unversionedTreeView`(Task 2)

- [ ] **Step 1: 改 selector 与传参**

`git_source_control_panel.dart:593-635` 的 `BlocSelector` 块替换为:

```dart
          Expanded(
            child: BlocSelector<
              GitCubit,
              GitState,
              (bool, GitChangesTreeViewData, GitChangesTreeViewData)
            >(
              selector: (state) => (
                state.status.hasChanges,
                state.changesTreeView,
                state.unversionedTreeView,
              ),
              builder: (context, data) {
                final (hasChanges, changesTreeView, unversionedTreeView) = data;
                if (!hasChanges) {
                  final cs = Theme.of(context).colorScheme;
                  return Center(
                    child: Text(
                      l10n.gitNoChanges,
                      style: TpTextStyles.of(
                        context,
                      ).smColored(cs.onSurfaceVariant),
                    ),
                  );
                }
                if (!_changesListReady) {
                  return const SizedBox.shrink();
                }
                return GitChangesTreeList(
                  changesTreeView: changesTreeView,
                  unversionedTreeView: unversionedTreeView,
                  cubit: _cubit,
                  listScrollController: _changesScrollController,
                  horizontalScrollController: _horizontalScrollController,
                  selectedPath: _selectedPath,
                  onSelect: (path) {
                    setState(() => _selectedPath = path);
                    final change = _findChange(path);
                    if (change != null) unawaited(_openDiff(change));
                  },
                  onOpenDiff: (change) => unawaited(_openDiff(change)),
                  onConfirmDiscard: (change) =>
                      unawaited(_confirmDiscard(change)),
                  onOpenFile: _openFile,
                );
              },
            ),
          ),
```

- [ ] **Step 2: 运行相关测试确认通过**

Run: `cd client && flutter test test/widgets/git/ test/cubits/git_cubit_test.dart test/services/git/git_changes_visible_rows_test.dart`
Expected: PASS。

- [ ] **Step 3: 提交**

```bash
git add client/lib/widgets/git/git_source_control_panel.dart
git commit -m "feat(git): wire Changes and Unversioned Files sections into SCM panel"
```

---

### Task 6: 全量验证

**Files:** 无(仅验证)

- [ ] **Step 1: 静态分析**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error;若出现 `unused` 之类提示按提示修复后重跑。

- [ ] **Step 2: 全量测试**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 全部通过。

- [ ] **Step 3: 提交(如有验证期修复)**

```bash
git add -A client/lib client/test
git commit -m "fix(git): address analyzer/test findings from SCM sections change"
```

---

## Self-Review

**Spec 覆盖:**
- 默认勾选规则(untracked 且未暂存不自动勾选;已跟踪或 index 暂存自动勾选;手动勾选保留)→ Task 2 Step 5,测试 Task 2 Step 1(d/c)。
- 双分组布局(Changes / Unversioned Files,各自三态全选、空组隐藏、折叠状态共享)→ Task 1(数据层)+ Task 4(UI),空组隐藏由 `totalCount > 0` 条件覆盖。
- 展开/收起全部作用于两组(`expandAllFolders`/`collapseAllFolders` 基于 staged+unstaged 全路径,两组合用 `expandedFolderPaths`,无代码改动)。
- 提交按钮/repo 选择器/右键菜单/badge 不变 → 未改动这些路径。
- l10n → Task 3;测试更新 → Task 2/4。

**Placeholder 扫描:** 无 TBD/TODO;每个代码步骤含完整实现。

**Type 一致性:** `GitChangesSection`/`GitChangesSections`/`visibleGitChangesSections`/`visibleGitChangesTreeView` 在 Task 1 定义,Task 2/4/5 引用一致;`selectAll/selectNone/selectFolder/deselectFolder` 全部带 `GitChangesSection` 参数;`GitChangesTreeList` 双视图参数名在 Task 4/5 一致;`git-section-toggle-{section.name}` key 在 Task 3 的生成与 Task 4 的测试中一致。Task 2 中 `selectAll(section)` 语义为并集(非整体替换),与 Step 7 的调用点及测试(d)断言一致。
