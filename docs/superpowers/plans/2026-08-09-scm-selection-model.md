# 源代码管理面板：IDEA 选择模型 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把面板复选框从"git index 暂存"改为"IDEA 选择模型"——勾选 = `selectedPaths`（纯 UI 状态，零 git），提交时才对勾选集 `git add + git commit --`。

**Architecture:** `GitState` 新增 `selectedPaths`（`Set<String>`），勾选/取消只改这个集合并重算树（O(n)，无子进程）。树构建器把每个变更行的 `staged` 字段**投影**为"是否被选中"（UI 投影语义，非 git index），因此文件复选框、文件夹三态、组头全选沿用现有渲染逻辑。提交改为 `GitService.commitSelected`（`git add -- <勾选>` + `git commit -m -- <勾选>`）。刷新时用 `_knownChangedPaths` 对账：新增变更自动勾选、消失路径移除、手动取消保留。

**Tech Stack:** Flutter / flutter_bloc / Material `Checkbox` / `GitService` / l10n。

## Global Constraints

- **勾选是纯 UI**：`toggleSelect` 等选择操作不得调用任何 git 服务方法（测试用 stub 断言 service 未被调用）。
- **投影语义**：在 `visibleUnifiedGitChangesTreeView` 产出的树里，`GitFileChange.staged` 表示"选中用于下次提交"，**不是** git index；`mergeGitChangesByPath` 去重仍在投影前用真实 index 的 `staged`（staged 侧胜出）。
- **提交 = 勾选集**：`GitService.commitSelected(dir, message, paths)` = `git add -- <paths>` + `git commit -m <message> -- <paths>`；`paths` 为空不得调用。
- **默认全选 + 对账**：首载/换根 `_knownChangedPaths` 置空 → 全部变更默认勾选；刷新时 `selectedPaths ∩ changedNow` + `changedNow - _knownChangedPaths`（新增自动勾选）。
- **Diff**：`_openDiff` 用 `_cubit.diffAgainstHead(change.path, ...)` + `source: WorkbenchDiffSource.changes`（HEAD vs 工作区），不再区分 staged/unstaged。
- **提交纪律**：工作区有其他未提交/并发改动；只 `git add <明确路径>` + `git commit -o <paths>`，绝不 `git add -A` / 裸 `git commit`。
- **l10n**：只改 `client/lib/l10n/app_en.arb` / `app_zh.arb`，然后 `flutter gen-l10n`（生成文件一并提交）。
- **TDD**：每个任务先写失败测试 → 确认失败 → 实现 → 确认通过 → 提交。
- 本计划**保持每个 HEAD 可编译**：Task 2 保留旧方法名（`stage`/`unstage`…）作为选择操作的过渡别名，Task 3 统一改名清理。

---

### Task 1: `GitService.commitSelected` + 新 l10n

**Files:**
- Modify: `client/lib/services/git/git_service.dart`
- Modify: `client/lib/l10n/app_en.arb`、`app_zh.arb`（+ 生成的 `app_localizations*.dart`）
- Test: `client/test/services/git/git_service_test.dart`

**Interfaces:**
- Produces:
  - `Future<void> GitService.commitSelected(String dir, String message, List<String> paths)`。
  - `AppLocalizations.gitIncludeInCommit`、`gitExcludeFromCommit`、`gitIncludeFolderInCommit`、`gitExcludeFolderFromCommit`（en: "Include in Commit" / "Exclude from Commit" / "Include Folder in Commit" / "Exclude Folder from Commit"；zh: "纳入本次提交" / "排除出本次提交" / "纳入文件夹到本次提交" / "从本次提交排除文件夹"）。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/git/git_service_test.dart`（用文件里既有的 `_FakeRunner` 模式）加：

```dart
  test('commitSelected stages the paths then commits only those paths', () async {
    final runner = _FakeRunner();
    final service = GitService.forTesting(runner);
    await service.commitSelected('/repo', 'feat: x', ['a.txt', 'b.dart']);
    expect(runner.calls, [
      ['add', '--', 'a.txt', 'b.dart'],
      ['commit', '-m', 'feat: x', '--', 'a.txt', 'b.dart'],
    ]);
  });
```

（若该文件没有 `_FakeRunner` / `GitService.forTesting`，按文件既有 stub 模式建：记录每次 `_run` 的 dir+args。）

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/git/git_service_test.dart`
Expected: FAIL（`commitSelected` 不存在）。

- [ ] **Step 3: 实现 GitService**

在 `client/lib/services/git/git_service.dart` 的 `commit` 后加：

```dart
  /// Stages [paths] then commits exactly those paths. `git add` handles
  /// untracked and deleted files; `git commit -- <paths>` restricts the commit
  /// to the selected set, leaving any other index entries alone.
  Future<void> commitSelected(
    String dir,
    String message,
    List<String> paths,
  ) async {
    await _run(dir, ['add', '--', ...paths]);
    await _run(dir, ['commit', '-m', message, '--', ...paths]);
  }
```

- [ ] **Step 4: l10n 新 key**

`app_en.arb` 的 `"gitOpenFile": "Open File",` 后加：

```json
  "gitIncludeInCommit": "Include in Commit",
  "gitExcludeFromCommit": "Exclude from Commit",
  "gitIncludeFolderInCommit": "Include Folder in Commit",
  "gitExcludeFolderFromCommit": "Exclude Folder from Commit",
```

`app_zh.arb` 对应加：

```json
  "gitIncludeInCommit": "纳入本次提交",
  "gitExcludeFromCommit": "排除出本次提交",
  "gitIncludeFolderInCommit": "纳入文件夹到本次提交",
  "gitExcludeFolderFromCommit": "从本次提交排除文件夹",
```

Run: `cd client && flutter gen-l10n`。

- [ ] **Step 5: 运行确认通过**

Run: `cd client && flutter test test/services/git/git_service_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/lib/services/git/git_service.dart \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/services/git/git_service_test.dart
git commit -o \
  client/lib/services/git/git_service.dart \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/services/git/git_service_test.dart \
  -m "feat(git): commitSelected stages and commits only the selected paths"
```

---

### Task 2: 选择模型生效（树投影 + cubit + 面板）

**Files:**
- Modify: `client/lib/services/git/git_changes_visible_rows.dart`
- Modify: `client/lib/cubits/git_cubit.dart`
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Test: `client/test/services/git/git_changes_visible_rows_test.dart`、`client/test/cubits/git_cubit_test.dart`

**Interfaces:**
- Consumes: `GitService.commitSelected`（Task 1）、`GitFileChange.copyWith`（已有）。
- Produces:
  - `GitState.selectedPaths`（`Set<String>`，默认 `{}`）。
  - `GitCubit` 私有 `Set<String> _knownChangedPaths` + `_reconcileSelectedPaths(GitRepoStatus)`。
  - `stage/unstage/stageFolder/unstageFolder/stageAll/unstageAll` **改为选择操作**（body 替换，签名不变 → 现有调用方不破坏）：
    - `stage(change)` = 把 `change.path` 加入 `selectedPaths`；`unstage(change)` = 移除。
    - `stageFolder(path)` = 加入该目录下所有变更路径；`unstageFolder(path)` = 移除。
    - `stageAll()` = 全选所有变更；`unstageAll()` = 清空。
  - `commit()` 改用 `commitSelected(state.repoRoot, message, state.selectedPaths.toList())`。
  - `visibleUnifiedGitChangesTreeView` 新增 `required Set<String> selectedPaths`；投影 `staged = selectedPaths.contains(path)`；`stagedCount` 字段语义 = 已选数量（字段名 Task 3 再改）。
  - 移除 `_optimisticMutate`、`_moveOptimistic`、`_moveFolderOptimistic`、`_moveAllOptimistic`。
  - 面板：`canCommit`/`canGenerate` 用 `selectedPaths.isNotEmpty`；`_openDiff` 用 `diffAgainstHead` + `changes` 源。

- [ ] **Step 1: 写失败测试（visible_rows 投影）**

在 `client/test/services/git/git_changes_visible_rows_test.dart` 加：

```dart
  test('unified tree projects staged=true for selected paths only', () {
    final view = visibleUnifiedGitChangesTreeView(
      staged: const [change('b.txt', staged: true)],
      unstaged: const [change('a.txt')],
      expandedFolderPaths: const {},
      selectedPaths: const {'a.txt'},
    );
    final files = view.rows.where((r) => !r.isFolder).toList();
    final a = files.firstWhere((r) => r.change!.path == 'a.txt');
    final b = files.firstWhere((r) => r.change!.path == 'b.txt');
    expect(a.change!.staged, isTrue); // selected
    expect(b.change!.staged, isFalse); // not selected
    expect(view.stagedCount, 1); // selected count
    expect(view.totalCount, 2);
  });
```

（`change(...)` helper 已在该测试文件里。若 `visibleUnifiedGitChangesTreeView` 还没有 `selectedPaths` 参数，本测试编译失败 → RED。）

- [ ] **Step 2: 写失败测试（cubit 选择是纯 UI）**

在 `client/test/cubits/git_cubit_test.dart` 加：

```dart
  test('stage/unstage only change the selection, never run git', () async {
    final service = _FakeGitService(statusToReturn: _repoWith(unstaged: const [_unstaged]));
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    final unstagedPath = cubit.state.status.unstaged.single.path;
    await cubit.stage(_unstaged);
    expect(cubit.state.selectedPaths, contains(unstagedPath));
    expect(service.calls, isEmpty); // NO git call

    await cubit.unstage(_unstaged);
    expect(cubit.state.selectedPaths, isEmpty);
    expect(service.calls, isEmpty);
    await cubit.close();
  });

  test('refresh reconciles selection: new files checked, vanished dropped, manual uncheck kept', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(unstaged: const [_unstaged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // first load: b.txt selected by default
    expect(cubit.state.selectedPaths, {'b.txt'});

    // manual uncheck of b.txt
    await cubit.unstage(_unstaged);
    expect(cubit.state.selectedPaths, isEmpty);

    // next refresh adds a NEW file c.txt (auto-checked), b.txt stays unchecked
    service.statusToReturn = _repoWith(
      unstaged: const [_unstaged, GitFileChange(path: 'c.txt', kind: GitChangeKind.modified, staged: false)],
    );
    await cubit.refresh();
    expect(cubit.state.selectedPaths, {'c.txt'});
    await cubit.close();
  });

  test('commit passes the selected paths to commitSelected', () async {
    final service = _FakeGitService(statusToReturn: _repoWith(unstaged: const [_unstaged, _staged]));
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setCommitMessage('msg'); // setCommitMessage 已存在（面板在用）
    await cubit.stageAll(); // Task 2 阶段方法名仍是 stageAll
    service.calls.clear();

    final ok = await cubit.commit();
    expect(ok, isTrue);
    expect(service.commitSelectedCalls, [
      ['add', '--', 'a.txt', 'b.txt'],
      ['commit', '-m', 'msg', '--', 'a.txt', 'b.txt'],
    ]);
    await cubit.close();
  });
```

给 `_FakeGitService` 加一个独立的 argv 记录器 + `commitSelected` override（`calls` 是 `List<String>`，用独立列表存 argv 更清晰）：

```dart
  final List<List<String>> commitSelectedCalls = [];

  @override
  Future<void> commitSelected(String dir, String message, List<String> paths) async {
    commitSelectedCalls.add(['add', '--', ...paths]);
    commitSelectedCalls.add(['commit', '-m', message, '--', ...paths]);
  }
```

- [ ] **Step 3: 运行确认失败**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart test/cubits/git_cubit_test.dart`
Expected: FAIL（`selectedPaths` 参数/状态不存在、`stage` 仍走 git、`commit` 仍走旧 `commit`）。

- [ ] **Step 4: 实现 visible_rows**

编辑 `client/lib/services/git/git_changes_visible_rows.dart`：

`visibleUnifiedGitChangesTreeView` 替换为：

```dart
GitChangesTreeViewData visibleUnifiedGitChangesTreeView({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
  required Set<String> expandedFolderPaths,
  required Set<String> selectedPaths,
}) {
  final merged = mergeGitChangesByPath(staged: staged, unstaged: unstaged);
  // UI projection: in the tree, `staged` means "selected for the next commit"
  // (the checkbox state), NOT the git index. Merge dedup above still used the
  // real index `staged` (staged side wins).
  final projected = <GitFileChange>[
    for (final c in merged) c.copyWith(staged: selectedPaths.contains(c.path)),
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
    stagedCount: selectedCount,
    totalCount: merged.length,
  );
}
```

在 `GitChangesTreeViewData` 的 `stagedCount` / `allStaged` / `noneStaged` 上更新文档注释：它们现在表示"已选数量/全选/全不选"（Task 3 改字段名）。

- [ ] **Step 5: 实现 cubit**

编辑 `client/lib/cubits/git_cubit.dart`：

`GitState` 加字段与构造（`expandedFolderPaths` 附近）：

```dart
    this.expandedFolderPaths = const {},
    this.selectedPaths = const {},
    this.generatingCommitMessage = false,
```
```dart
  final Set<String> expandedFolderPaths;
  final Set<String> selectedPaths;
```
`copyWith` 加 `Set<String>? selectedPaths` 参数与赋值。

cubit 字段：`Set<String> _knownChangedPaths = {};`

`setRepoRoot` 的 reset `copyWith` 加 `selectedPaths: const {}`，并设 `_knownChangedPaths = {};`。

`_publish` 的 `visibleUnifiedGitChangesTreeView(...)` 调用加 `selectedPaths: next.selectedPaths,`。

`_runRefresh` 在构建 `next` 前对账；`next` 加 `selectedPaths: selected`；无变化早退条件加 `next.selectedPaths == state.selectedPaths`：

```dart
      final selected = _reconcileSelectedPaths(status);
      final next = state.copyWith(
        gitAvailable: true,
        isLoading: false,
        status: status,
        expandedFolderPaths: expanded,
        selectedPaths: selected,
      );
      if (next.status == state.status &&
          next.expandedFolderPaths == state.expandedFolderPaths &&
          next.selectedPaths == state.selectedPaths &&
          next.isLoading == state.isLoading &&
          next.gitAvailable == state.gitAvailable &&
          next.errorMessage == state.errorMessage) {
        return;
      }
```

新增对账方法：

```dart
  /// Keeps manual selection across refreshes: drops paths that vanished,
  /// auto-checks newly-appeared changes, preserves everything else.
  Set<String> _reconcileSelectedPaths(GitRepoStatus status) {
    final changedNow = <String>{
      for (final c in status.staged) c.path,
      for (final c in status.unstaged) c.path,
    };
    final next = <String>{
      ...state.selectedPaths.where(changedNow.contains),
      ...changedNow.difference(_knownChangedPaths),
    };
    _knownChangedPaths = changedNow;
    return next;
  }
```

替换 `stage`/`unstage`/`stageFolder`/`unstageFolder`/`stageAll`/`unstageAll` 的 body（签名不变）为纯选择操作，并删除 `_optimisticMutate` 及 `_moveOptimistic`/`_moveFolderOptimistic`/`_moveAllOptimistic`：

```dart
  /// Selection-model ops: these are pure UI state (no git), matching IDEA's
  /// "include in the next commit" checkboxes. Names are the legacy stage
  /// vocabulary; Task 3 renames them.
  Future<void> stage(GitFileChange change) {
    _publish(
      state.copyWith(selectedPaths: {...state.selectedPaths, change.path}),
    );
  }

  Future<void> unstage(GitFileChange change) {
    final next = {...state.selectedPaths}..remove(change.path);
    _publish(state.copyWith(selectedPaths: next));
  }

  Future<void> stageFolder(String folderPath) {
    final changed = _changedPathsUnder(folderPath);
    _publish(state.copyWith(selectedPaths: {...state.selectedPaths, ...changed}));
  }

  Future<void> unstageFolder(String folderPath) {
    final changed = _changedPathsUnder(folderPath);
    final next = {...state.selectedPaths}..removeAll(changed);
    _publish(state.copyWith(selectedPaths: next));
  }

  Future<void> stageAll() {
    _publish(
      state.copyWith(
        selectedPaths: <String>{
          for (final c in [...state.status.staged, ...state.status.unstaged])
            c.path,
        },
      ),
    );
  }

  Future<void> unstageAll() {
    _publish(state.copyWith(selectedPaths: const <String>{}));
  }

  Set<String> _changedPathsUnder(String folderPath) => <String>{
    for (final c in [...state.status.staged, ...state.status.unstaged])
      if (c.path == folderPath || c.path.startsWith('$folderPath/')) c.path,
  };
```

`commit()` 替换为：

```dart
  Future<bool> commit() async {
    final message = state.commitMessage.trim();
    final paths = state.selectedPaths.toList();
    if (message.isEmpty || paths.isEmpty) {
      return false;
    }
    final ok = await _mutate(
      () => _service.commitSelected(state.repoRoot, message, paths),
    );
    if (ok) {
      _publish(state.copyWith(commitMessage: ''), recomputeRows: false);
    }
    return ok;
  }
```

- [ ] **Step 6: 实现面板**

编辑 `client/lib/widgets/git/git_source_control_panel.dart`：

`_CommitBox` 的 BlocSelector 现在取 `(bool, bool, bool, String)`，把 `state.status.staged.isNotEmpty` 改为 `state.selectedPaths.isNotEmpty`（其余不变，`hasStaged` 变量改名为 `hasSelection`）。

`_openDiff` 改为：

```dart
  Future<void> _openDiff(GitFileChange change) async {
    final diff = await _cubit.diffAgainstHead(change.path, fullContext: true);
    if (!mounted || diff == null) return;
    final absolutePath = p.join(_cubit.state.repoRoot, change.path);
    context.read<WorkbenchEditorOpener>().openDiff(
      workspaceId: widget.workspaceId,
      absolutePath: absolutePath,
      source: WorkbenchDiffSource.changes,
      title: change.path,
      diffText: diff,
      reloadDiff: (ignoreWhitespace, fullContext) => _cubit.diffAgainstHead(
        change.path,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      ),
      onWorkingTreeWritten: () => _cubit.refresh(),
    );
  }
```

- [ ] **Step 7: 运行确认通过**

Run: `cd client && flutter test test/services/git/git_changes_visible_rows_test.dart test/cubits/git_cubit_test.dart test/widgets/git/git_changes_tree_list_test.dart test/widgets/git/git_change_tile_test.dart test/widgets/git/git_change_folder_tile_test.dart test/widgets/git/git_source_control_panel_open_file_test.dart test/widgets/git/git_source_control_panel_generate_test.dart`
Expected: PASS（旧用例若因语义变化失败，按新语义修正断言：`stagedCount` 现为已选数、勾选行为变了等）。

- [ ] **Step 8: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/lib/services/git/git_changes_visible_rows.dart \
  client/lib/cubits/git_cubit.dart \
  client/lib/widgets/git/git_source_control_panel.dart \
  client/test/services/git/git_changes_visible_rows_test.dart \
  client/test/cubits/git_cubit_test.dart
git commit -o \
  client/lib/services/git/git_changes_visible_rows.dart \
  client/lib/cubits/git_cubit.dart \
  client/lib/widgets/git/git_source_control_panel.dart \
  client/test/services/git/git_changes_visible_rows_test.dart \
  client/test/cubits/git_cubit_test.dart \
  -m "feat(git): selection model — checkboxes are pure UI state, commit stages the selection"
```

---

### Task 3: 改名与清理（tiles / 树字段 / 右键菜单 / 旧代码）

**Files:**
- Modify: `client/lib/services/git/git_changes_visible_rows.dart`（字段改名）
- Modify: `client/lib/cubits/git_cubit.dart`（方法改名 + 删别名）
- Modify: `client/lib/widgets/git/git_change_tile.dart`、`git_change_folder_tile.dart`、`git_changes_tree_list.dart`、`git_context_menu.dart`、`git_source_control_panel.dart`
- Modify: `client/lib/models/git_status.dart`（清理 copyWith）
- Modify: l10n（删旧 stage/unstage key）
- Test: 上述对应测试

**Interfaces:**
- Consumes: Task 2 的 `selectedPaths` / 投影语义。
- Produces（最终命名）：
  - `GitChangesTreeViewData.selectedCount` / `allSelected` / `noneSelected`（原 `stagedCount`/`allStaged`/`noneStaged`）。
  - `GitChangesVisibleRow.folder.subtreeSelectedCount`（原 `subtreeStagedCount`）。
  - `GitCubit.selectPath/deselectPath/selectFolder/deselectFolder/selectAll/selectNone`（原 `stage/unstage/stageFolder/unstageFolder/stageAll/unstageAll`）。
  - 右键菜单 `gitIncludeInCommit`/`gitExcludeFromCommit`/`gitIncludeFolderInCommit`/`gitExcludeFolderFromCommit`。

- [ ] **Step 1: 写失败测试（改名后编译即测）**

改名是机械重构；测试用"编译 + 现有用例通过"作为验收。先跑现有相关测试确认当前绿，再改名（每步可局部 `flutter analyze lib/widgets/git/ lib/cubits/git_cubit.dart lib/services/git/` 验证编译）。

- [ ] **Step 2: 树字段改名**

`git_changes_visible_rows.dart`：`stagedCount`→`selectedCount`、`allStaged`→`allSelected`、`noneStaged`→`noneSelected`、`subtreeStagedCount`→`subtreeSelectedCount`（`GitChangesVisibleRow.folder` 构造参数 + 字段 + `_walk` 里的实参 + `GitChangesTreeViewData` 构造/字段/getters）。同步改 `git_changes_tree_list.dart` 的 `_GitChangesRootHeader` 使用处（`stagedCount`/`allStaged`/`noneStaged` → 新名）、`git_change_folder_tile.dart` 的 `subtreeSelectedCount`/`subtreeTotalCount`。

- [ ] **Step 3: cubit 方法改名 + 删别名**

`git_cubit.dart`：`stage`→`selectPath`、`unstage`→`deselectPath`、`stageFolder`→`selectFolder`、`unstageFolder`→`deselectFolder`、`stageAll`→`selectAll`、`unstageAll`→`selectNone`。同步 `git_changes_tree_list.dart` 调用处（`cubit.stage(change)`→`cubit.selectPath(change.path)` 等）、`git_change_tile.dart` / `git_change_folder_tile.dart` 的 `onStage`/`onUnstage` 回调接线保持（树列表把它们连到新方法名即可）。

- [ ] **Step 4: 右键菜单 + 面板文案**

`git_context_menu.dart`：文件菜单 `staged ? 'unstage' : 'stage'` 项 label 改为 `staged ? l10n.gitExcludeFromCommit : l10n.gitIncludeInCommit`（icon `Icons.remove`/`Icons.add` 不变）；文件夹菜单 `'stage'`→`gitIncludeFolderInCommit`、`'unstage'`→`gitExcludeFolderFromCommit`。value 常量可保持 `'stage'`/`'unstage'`（内部 switch 不变）。

- [ ] **Step 5: 清理**

- `grep -rn "\.stage\|unstage\|stageAll\|stageFolder" client/lib/ --include=*.dart | grep -v selectPath`：确认旧的 `stage`/`unstage`/`stageAll`/`stageFolder`/`unstageAll`/`unstageFolder` 方法在 cubit 里已全部改名且无其它引用（除右键菜单 value 字符串 `'stage'`/`'unstage'` 外）。
- `GitRepoStatus.copyWith` 若无引用则删；`GitFileChange.copyWith` 保留（投影在用）。
- l10n：`grep` 确认 `gitStage`/`gitUnstage`/`gitStageFolder`/`gitUnstageFolder`/`gitStageAll`/`gitUnstageAll` 无引用后从两个 arb + 生成的 `app_localizations*.dart` 移除；`flutter gen-l10n`。

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/services/git/ test/cubits/ test/widgets/git/ test/widgets/hover_double_tap_test.dart`
Expected: 全过。

- [ ] **Step 7: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/git/git_changes_visible_rows.dart client/lib/cubits/git_cubit.dart client/lib/widgets/git/git_change_tile.dart client/lib/widgets/git/git_change_folder_tile.dart client/lib/widgets/git/git_changes_tree_list.dart client/lib/widgets/git/git_context_menu.dart client/lib/widgets/git/git_source_control_panel.dart client/lib/models/git_status.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/services/git/git_changes_visible_rows_test.dart client/test/cubits/git_cubit_test.dart
git commit -o \
  client/lib/services/git/git_changes_visible_rows.dart \
  client/lib/cubits/git_cubit.dart \
  client/lib/widgets/git/git_change_tile.dart \
  client/lib/widgets/git/git_change_folder_tile.dart \
  client/lib/widgets/git/git_changes_tree_list.dart \
  client/lib/widgets/git/git_context_menu.dart \
  client/lib/widgets/git/git_source_control_panel.dart \
  client/lib/models/git_status.dart \
  client/lib/l10n/app_en.arb \
  client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/services/git/git_changes_visible_rows_test.dart \
  client/test/cubits/git_cubit_test.dart \
  -m "refactor(git): rename selection ops + tree fields, IDEA labels, prune legacy stage code"
```

---

### Task 4: 全量验证

- [ ] **Step 1: 静态分析**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error / warning（info 允许）。

- [ ] **Step 2: 全量测试（排除集成）**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 通过（如遇既有 smoke/automation 偶发加载失败，单独跑该文件确认通过即可，不属本特性）。

- [ ] **Step 3: 若有本特性导致的失败，修复并重跑**，直到全绿。

---

## 自检记录

- **Spec 覆盖**：选择状态/复选框语义 → Task 2/3；默认全选+对账 → Task 2（`_reconcileSelectedPaths`）；提交=勾选集 → Task 1 + Task 2 `commitSelected`；文件夹/组头三态按选择 → Task 2（投影）+ Task 3（改名）；Diff `changes` → Task 2；右键菜单 include/exclude → Task 3；移除乐观 stage/unstage → Task 2；清理 copyWith/旧 l10n → Task 3；全量验证 → Task 4。
- **无占位符**：每步含完整代码/命令。
- **类型一致性**：`selectedPaths`、`_reconcileSelectedPaths`、`commitSelected`、`diffAgainstHead`、`WorkbenchDiffSource.changes`、`toggleSelect`（Task 3 改名为 `selectPath` 等）跨任务命名一致；Task 3 的改名与 Task 2 的投影语义衔接（`staged` 字段语义=已选，改名只动字段名不动语义）。右键菜单内部 value 字符串 `'stage'`/`'unstage'` 保持不变（只改 label），避免误删。
- **已知注意点**：Task 2 保留 `stage`/`unstage` 过渡别名（语义=选择），Task 3 统一改名——两个 task 各自保持 HEAD 可编译、测试可跑。
