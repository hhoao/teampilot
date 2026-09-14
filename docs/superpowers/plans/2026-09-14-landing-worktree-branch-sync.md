# Landing Worktree 选择器与外部分支切换同步 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** landing 对话页的 worktree/git 选择器在外部分支切换后不再显示过期分支名，应用内操作即时刷新、终端等外部操作 ≤15s 校准。

**Architecture:** 两条刷新链路汇聚到新增的 `WorktreeCubit.reloadActiveRepo()`（带 in-flight/trailing 去重）：A) 应用内 git 分支类操作通过 `GitRepoStore` 新增的 `headChanged` 广播流通知，`WorktreeCubit` 构造时订阅并过滤匹配仓库；B) landing 挂载期间 15s TTL 定时校准（`WorkspaceLandingWorktreeRefresher`，SSH/Termux 跳过、route 不活跃/submitting 跳过）。重载复用 `load(force:true)` 的选择保留逻辑。

**Tech Stack:** Dart / Flutter, flutter_bloc cubits, `StreamController<String>` 广播流, injected test seams（`WorktreeLister`、`_injectedCubitFactory`、`debugOverrideFactory`）。

**Spec:** `docs/superpowers/specs/2026-09-14-landing-worktree-branch-sync-design.md`

## Global Constraints

- **测试命令**：绝不直接 `flutter test`；一律 `cd client && dart run tool/run_tests.dart <test paths>`（并发直跑会破坏共享构建缓存）。
- **收尾校验**：声称完成前 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`（全量，后台跑）。
- **测试缝**：mock 子进程/文件系统一律构造注入；cubit 测试要 home 平面时用 `setUpTestAppStorage()`/`tearDownTestAppStorage()`。
- **日志**：诊断用 `AppLogger`（`appLogger.d`），不 `print`。
- **l10n**：本改动不新增 UI 文案，不动 arb 文件。
- **成员放置 / 目录语义**：不改 `resolveSelectedWorktreePath` 选择优先级、不改 `_syncLaunchFromWorktree`。
- 提交粒度：每任务一个 commit，只 add 本任务涉及文件（工作区有其他在途改动，绝不 `git add -A`）。

**与 spec 的两处实现细节偏倚（行为不变，均为可测试性/集中接线考虑）：**
1. spec A.3 说订阅放在 `WorkspaceToolsScopeSync`；计划改为 **`WorktreeCubit` 自身订阅注入的 `gitMutationSignals` 流**，由 `WorkspaceWorktreeRegistry`/`app_shell` 从 `GitRepoStore.headChanged` 接线。避免为测试构造 `WorkspaceToolsScopeSync` 整套 Chat/Workbench 依赖，reload 过滤逻辑可直接单元测试（Task 4）。spec 的「WorkspaceToolsScopeSync 订阅」测试项相应改为 cubit 级测试。
2. spec 说 graph 侧 4 个 `GitGraphActionsController` 构造点传回调；计划改为 `GitGraphActionsController` 成功时回调 `GitGraphCubit.onHeadChanged`，`onHeadChanged` 在 `GitRepoStore._defaultGraphFactory` 统一注入 —— 单点接线、不用改 4 处调用点。

---

### Task 1: `WorktreeCubit.reloadActiveRepo()` 重载原语

**Files:**
- Modify: `client/lib/cubits/worktree_cubit.dart`（`_loadGeneration` 字段附近加 reload 去重字段；`load` 方法后加 `reloadActiveRepo`；新增 `dart:async` 已存在、`import '../utils/logging/logger.dart';`）
- Test: `client/test/cubits/worktree_cubit_test.dart`

**Interfaces:**
- Produces: `Future<void> reloadActiveRepo()` — 无参数、基于 `state.repoPath` 重载；`_lister == null` 或 repoPath 空则静默返回；并发调用合并为「1 条 in-flight + 至多 1 条 trailing」；git 错误吸收、不冒泡。

- [ ] **Step 1: 写失败测试**

在 `client/test/cubits/worktree_cubit_test.dart` 顶部现有 fake 区加入（`GitException` 需 `import 'package:teampilot/services/git/git_service.dart';`，文件里现尚未 import）：

```dart
class _CountingDelayedLister implements WorktreeLister {
  _CountingDelayedLister(this._list, this.delay);
  final List<GitWorktree> _list;
  final Duration delay;
  var calls = 0;
  @override
  Future<List<GitWorktree>> list(String repoPath) async {
    calls++;
    await Future<void>.delayed(delay);
    return _list;
  }
}

class _ThrowingLister implements WorktreeLister {
  @override
  Future<List<GitWorktree>> list(String repoPath) async =>
      throw GitException('boom');
}
```

在 `main()` 内追加：

```dart
group('reloadActiveRepo', () {
  test('skips silently before the git runner is bound', () async {
    final cubit = WorktreeCubit(
      storage: fakeHomeStorage(),
      initialRepoPath: '/repo',
    );
    await cubit.reloadActiveRepo(); // must not throw StateError
    await cubit.close();
  });

  test('reloads the active repo with force and republishes worktrees',
      () async {
    var list = [_wt('/repo', main: true), _wt('/wt/a')];
    final lister = _CountingLister((_) => list);
    final cubit = WorktreeCubit(
      storage: fakeHomeStorage(),
      lister: lister,
      initialRepoPath: '/repo',
    );
    await cubit.reloadActiveRepo();
    expect(lister.calls, 1);
    expect(cubit.state.worktrees, hasLength(2));

    list = [_wt('/repo', main: true), _wt('/wt/a'), _wt('/wt/b')];
    await cubit.reloadActiveRepo();
    expect(lister.calls, 2);
    expect(cubit.state.worktrees, hasLength(3));
    await cubit.close();
  });

  test('coalesces concurrent reloads into one in-flight plus one trailing',
      () async {
    final lister = _CountingDelayedLister(
      [_wt('/repo', main: true)],
      const Duration(milliseconds: 20),
    );
    final cubit = WorktreeCubit(
      storage: fakeHomeStorage(),
      lister: lister,
      initialRepoPath: '/repo',
    );
    final first = cubit.reloadActiveRepo();
    final second = cubit.reloadActiveRepo();
    final third = cubit.reloadActiveRepo();
    await Future.wait([first, second, third]);
    // 第一条执行中；第二条排队；第三条看到已排队直接返回 → 共 2 次 list。
    expect(lister.calls, 2);
    await cubit.close();
  });

  test('absorbs git errors without leaving loading stuck', () async {
    final cubit = WorktreeCubit(
      storage: fakeHomeStorage(),
      lister: _ThrowingLister(),
      initialRepoPath: '/repo',
    );
    await cubit.reloadActiveRepo(); // must not throw
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.worktrees, isEmpty);
    await cubit.close();
  });
});
```

注意 `_CountingLister` 已存在于该测试文件（构造函数 `_CountingLister(this._listFor)`）。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/worktree_cubit_test.dart`
Expected: `reloadActiveRepo` 编译失败（方法不存在）。

- [ ] **Step 3: 实现**

在 `worktree_cubit.dart` 的 `_loadGeneration` 字段附近加：

```dart
bool _reloadInFlight = false;
bool _reloadQueued = false;
```

在 `selectProject` 方法之后加：

```dart
/// Reloads `git worktree list` for the current repo with a coalescing guard:
/// at most one in-flight chain per repo plus a single trailing run, mirroring
/// [GitCubit.refresh]. No-op until [bindWorktreeService] bound a runner.
/// Errors are absorbed (labels heal on the next event / TTL tick).
Future<void> reloadActiveRepo() async {
  if (_lister == null) return;
  final repo = state.repoPath.trim();
  if (repo.isEmpty) return;
  if (_reloadInFlight) {
    _reloadQueued = true;
    return;
  }
  _reloadInFlight = true;
  try {
    try {
      await load(repo, force: true);
    } on Object catch (e, st) {
      appLogger.d('[worktree] reload active repo failed: $repo ($e)',
          error: e, stackTrace: st);
      if (!isClosed && state.loading) emit(state.copyWith(loading: false));
    }
  } finally {
    _reloadInFlight = false;
  }
  if (_reloadQueued && !isClosed) {
    _reloadQueued = false;
    unawaited(reloadActiveRepo());
  }
}
```

顶部 import 区加：`import '../utils/logging/logger.dart';`

- [ ] **Step 4: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/worktree_cubit_test.dart`
Expected: 该文件全部 PASS（含既有用例）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/worktree_cubit.dart client/test/cubits/worktree_cubit_test.dart
git commit -m "feat(worktree): add coalesced reloadActiveRepo primitive"
```

---

### Task 2: `GitRepoStore` HEAD 变更信号 + `GitCubit` 上报

**Files:**
- Modify: `client/lib/services/git/git_repo_store.dart`
- Modify: `client/lib/cubits/git_cubit.dart`
- Test: `client/test/services/git/git_repo_store_refresh_test.dart`、`client/test/cubits/git_cubit_test.dart`

**Interfaces:**
- Consumes: `GitCubit({... onHeadChanged})`（本任务定义）
- Produces:
  - `Stream<String> get headChanged`（`GitRepoStore`，事件 = repoRoot）
  - `void notifyHeadChanged(String repoRoot)`（空串忽略）
  - `GitCubit.onHeadChanged` — checkout/create 成功后以 `state.repoRoot` 调用

- [ ] **Step 1: 写失败测试**

`client/test/services/git/git_repo_store_refresh_test.dart` 追加：

```dart
test('notifyHeadChanged publishes the repo root on headChanged', () async {
  final store = GitRepoStore();
  addTearDown(store.dispose);
  final seen = <String>[];
  final sub = store.headChanged.listen(seen.add);
  addTearDown(sub.cancel);

  store.notifyHeadChanged('/repo-a');
  store.notifyHeadChanged('  '); // 空白被忽略
  await Future<void>.delayed(Duration.zero);
  expect(seen, ['/repo-a']);
});
```

`client/test/cubits/git_cubit_test.dart`：

1) 给文件顶部的 `_FakeGitService` 加两个 override（放在 `_record` 附近，复用其调用记录/抛错机制）：

```dart
@override
Future<void> checkout(String dir, String name) => _record('checkout:$name');

@override
Future<void> createBranch(String dir, String name) => _record('createBranch:$name');
```

2) 追加测试（复用既有 `_repoWith()` 状态构造器）：

```dart
group('onHeadChanged', () {
  test('fires with repoRoot after a successful checkout', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final roots = <String>[];
    final cubit = GitCubit(service: service, onHeadChanged: roots.add);
    await cubit.setRepoRoot('/repo');
    await cubit.checkoutBranch('dev');
    expect(roots, ['/repo']);
    await cubit.close();
  });

  test('fires after a successful createBranch', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final roots = <String>[];
    final cubit = GitCubit(service: service, onHeadChanged: roots.add);
    await cubit.setRepoRoot('/repo');
    await cubit.createBranch('dev');
    expect(roots, ['/repo']);
    await cubit.close();
  });

  test('does not fire when the mutation fails', () async {
    final service = _FakeGitService(statusToReturn: _repoWith())
      ..throwOnNext = GitException('boom');
    final roots = <String>[];
    final cubit = GitCubit(service: service, onHeadChanged: roots.add);
    await cubit.setRepoRoot('/repo');
    await cubit.checkoutBranch('dev');
    expect(roots, isEmpty);
    await cubit.close();
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/git_cubit_test.dart test/services/git/git_repo_store_refresh_test.dart`
Expected: `onHeadChanged`「named parameter not found」编译失败。

- [ ] **Step 3: 实现**

`client/lib/cubits/git_cubit.dart`：

```dart
GitCubit({
  required GitService service,
  HeadlessAiService? headless,
  HomeStorage? storage,
  void Function(String repoRoot)? onHeadChanged,
}) : _service = service,
       _headless = headless ?? …,
       onHeadChanged = onHeadChanged,
       super(const GitState());

/// Fired after a branch-affecting mutation succeeds; `repoRoot` is the repo
/// whose HEAD moved. Used to keep worktree/branch labels fresh.
final void Function(String repoRoot)? onHeadChanged;
```

`checkoutBranch` / `createBranch`：

```dart
Future<void> checkoutBranch(String name) async {
  if (await _mutate(() => _service.checkout(state.repoRoot, name))) {
    onHeadChanged?.call(state.repoRoot);
    await ensureBranches(force: true);
  }
}

Future<void> createBranch(String name) async {
  if (await _mutate(
    () => _service.createBranch(state.repoRoot, name.trim()),
  )) {
    onHeadChanged?.call(state.repoRoot);
    await ensureBranches(force: true);
  }
}
```

`client/lib/services/git/git_repo_store.dart`：

```dart
final _headChanged = StreamController<String>.broadcast(sync: true);

/// HEAD-branch mutation notifications (repoRoot), e.g. git panel / graph
/// checkouts. Worktree loading subscribes to keep branch labels fresh.
Stream<String> get headChanged => _headChanged.stream;

void notifyHeadChanged(String repoRoot) {
  final root = repoRoot.trim();
  if (root.isEmpty) return;
  _headChanged.add(root);
}
```

`_cubitFactory` 的 `GitCubit(...)` 调用加：`onHeadChanged: notifyHeadChanged,`
`_defaultGraphFactory` 的 `GitGraphCubit(...)` 调用加：`onHeadChanged: notifyHeadChanged,`（GitGraphCubit 参数在 Task 3 才定义，先加会编译错 —— 见 Step 5 说明，此处的 graph 注入放到 Task 3 一起提交）

`dispose()` 末尾加：`_headChanged.close();`

> 因为 `GitGraphCubit.onHeadChanged` 在 Task 3 才存在，`_defaultGraphFactory` 的改动**不要**在本任务提交，避免半成编译错。本任务只提交 `_cubitFactory` 的注入 + `GitCubit` 改动。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/git_cubit_test.dart test/services/git/git_repo_store_refresh_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/git/git_repo_store.dart client/lib/cubits/git_cubit.dart client/test/cubits/git_cubit_test.dart client/test/services/git/git_repo_store_refresh_test.dart
git commit -m "feat(git): publish head-changed signal after branch mutations"
```

---

### Task 3: `GitGraphCubit.onHeadChanged` + 控制器成功上报

**Files:**
- Modify: `client/lib/cubits/git_graph_cubit.dart`
- Modify: `client/lib/cubits/git_graph_actions_controller.dart`
- Modify: `client/lib/services/git/git_repo_store.dart`（补上 Task 2 留的 `_defaultGraphFactory` 注入）
- Test: `client/test/cubits/git_graph_actions_controller_test.dart`

**Interfaces:**
- Consumes: `GitRepoStore.notifyHeadChanged`（Task 2）
- Produces: `GitGraphCubit.onHeadChanged`（`void Function(String repoRoot)?`）—— 图面板任何写操作成功后以 `state.repoRoot` 回调。

- [ ] **Step 1: 写失败测试**

`client/test/cubits/git_graph_actions_controller_test.dart` 追加：

```dart
test('successful action notifies onHeadChanged with repoRoot', () async {
  final roots = <String>[];
  final cubit = GitGraphCubit(
    history: FakeHistoryForGraph(rows: []),
    git: FakeGitForGraph(repoStatus()),
    actions: actions,
    onHeadChanged: roots.add,
  );
  await cubit.setRepoRoot('/repo');
  final controller = GitGraphActionsController(cubit: cubit);
  await controller.createBranch('dev', atHash: 'c1');
  expect(roots, ['/repo']);
  await cubit.close();
});

test('failed action does not notify', () async {
  final roots = <String>[];
  final cubit = GitGraphCubit(
    history: FakeHistoryForGraph(rows: []),
    git: FakeGitForGraph(repoStatus()),
    actions: actions,
    onHeadChanged: roots.add,
  );
  await cubit.setRepoRoot('/repo');
  actions.throwNext = GitException('conflict');
  final controller = GitGraphActionsController(cubit: cubit);
  expect(await controller.deleteBranch('dev'), isFalse);
  expect(roots, isEmpty);
  await cubit.close();
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/git_graph_actions_controller_test.dart`
Expected: `onHeadChanged` 编译失败。

- [ ] **Step 3: 实现**

`git_graph_cubit.dart` 构造函数加参数并存储：

```dart
GitGraphCubit({
  required GitHistoryService history,
  required GitService git,
  GitHistoryActions? actions,
  DateTime Function()? clock,
  void Function(String repoRoot)? onHeadChanged,
}) : _history = history,
     _git = git,
     _actions = actions ?? GitHistoryActions(),
     _now = clock ?? DateTime.now,
     onHeadChanged = onHeadChanged,
     super(const GitGraphState());

/// Fired after any graph write action succeeds; `repoRoot` is the graph repo.
final void Function(String repoRoot)? onHeadChanged;
```

`git_graph_actions_controller.dart` 的 `_run` 成功分支：

```dart
try {
  await action();
  await cubit.refresh();
  cubit.onHeadChanged?.call(_dir);
  return true;
} on GitException catch (e) {
  // 失败不通知
  ...
}
```

`git_repo_store.dart` `_defaultGraphFactory` 的 `GitGraphCubit(...)` 加：`onHeadChanged: notifyHeadChanged,`

- [ ] **Step 4: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/git_graph_actions_controller_test.dart test/cubits/git_graph_cubit_test.dart test/cubits/git_cubit_test.dart test/services/git/git_repo_store_refresh_test.dart`
Expected: 全 PASS；`flutter analyze` 无错（`_defaultGraphFactory` 现在有参数可填）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/git_graph_cubit.dart client/lib/cubits/git_graph_actions_controller.dart client/lib/services/git/git_repo_store.dart client/test/cubits/git_graph_actions_controller_test.dart
git commit -m "feat(git-graph): notify head-changed after successful write actions"
```

---

### Task 4: `WorktreeCubit` 订阅信号 + Registry/`app_shell` 接线

**Files:**
- Modify: `client/lib/cubits/worktree_cubit.dart`（构造函数收 `gitMutationSignals`、订阅、`close` 取消）
- Modify: `client/lib/services/workspace/workspace_worktree_registry.dart`
- Modify: `client/lib/app/app_shell.dart`（`:1702` 附近 registry 构造）
- Test: `client/test/cubits/worktree_cubit_test.dart`

**Interfaces:**
- Consumes: `WorktreeCubit.reloadActiveRepo`（Task 1）、`GitRepoStore.headChanged`（Task 2）
- Produces: `WorktreeCubit({... Stream<String>? gitMutationSignals})`；`WorkspaceWorktreeRegistry({... Stream<String>? gitMutationSignals})`。

- [ ] **Step 1: 写失败测试**

`worktree_cubit_test.dart` 追加（文件顶部已有 `_CountingLister`/`_wt`；加 `import 'dart:async';`）：

```dart
group('gitMutationSignals', () {
  test('reloads only when the event repo matches the active repo', () async {
    final controller = StreamController<String>.broadcast(sync: true);
    addTearDown(controller.close);
    final lister = _CountingLister((_) => [_wt('/repo', main: true)]);
    final cubit = WorktreeCubit(
      storage: fakeHomeStorage(),
      lister: lister,
      initialRepoPath: '/repo',
      gitMutationSignals: controller.stream,
    );

    controller.add('/repo');    // 匹配 → reload
    controller.add('/other');   // 不匹配 → 忽略
    controller.add('');         // 空 → 忽略
    await Future<void>.delayed(Duration.zero);
    expect(lister.calls, 1);

    await cubit.close();
    controller.add('/repo');    // close 后不得再触发
    await Future<void>.delayed(Duration.zero);
    expect(lister.calls, 1);
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/worktree_cubit_test.dart`
Expected: `gitMutationSignals` 编译失败。

- [ ] **Step 3: 实现**

`worktree_cubit.dart`：

```dart
StreamSubscription<String>? _gitSignalsSub;

WorktreeCubit({
  required HomeStorage storage,
  WorktreeLister? lister,
  this.workspaceId = '',
  WorktreeUiPrefsStore? prefsStore,
  WorkspaceWorktreeStore? worktreeStore,
  String? initialRepoPath,
  Stream<String>? gitMutationSignals,
}) : _storage = storage,
     _lister = lister,
     _prefsStore = prefsStore ?? WorktreeUiPrefsStore(storage: storage),
     _worktreeStore = worktreeStore,
     super(...) {
  final signals = gitMutationSignals;
  if (signals != null) {
    _gitSignalsSub = signals.listen(_onGitMutationSignal);
  }
}

void _onGitMutationSignal(String repoRoot) {
  if (isClosed) return;
  final path = repoRoot.trim();
  if (path.isEmpty) return;
  final active = state.repoPath.trim();
  if (active.isEmpty) return;
  if (!workspacePathsEqual(path, active, usesPosixPaths: _storage.usesPosixPaths)) {
    return;
  }
  unawaited(reloadActiveRepo());
}

@override
Future<void> close() async {
  await _gitSignalsSub?.cancel();
  _gitSignalsSub = null;
  await super.close();
}
```

注意构造函数的 super 初始化列表（含 `_initialState`）不变，`gitMutationSignals` 订阅放构造体尾部。

`workspace_worktree_registry.dart`：

```dart
WorkspaceWorktreeRegistry({
  WorkspaceWorktreeStore? store,
  this.storage,
  Stream<String>? gitMutationSignals,
}) : _store = store ?? WorkspaceWorktreeStore(),
     _gitMutationSignals = gitMutationSignals;

final Stream<String>? _gitMutationSignals;
```

`cubitFor` 里的 `WorktreeCubit(...)` 加：`gitMutationSignals: _gitMutationSignals,`

`app_shell.dart` `WorkspaceWorktreeRegistry(storage: homeStorage, ...)` 加：

```dart
final workspaceWorktreeRegistry = WorkspaceWorktreeRegistry(
  storage: homeStorage,
  gitMutationSignals: gitRepoStore.headChanged,
);
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/worktree_cubit_test.dart`
Expected: PASS（本文件全部）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/worktree_cubit.dart client/lib/services/workspace/workspace_worktree_registry.dart client/lib/app/app_shell.dart client/test/cubits/worktree_cubit_test.dart
git commit -m "feat(worktree): subscribe to git head-changed signals"
```

---

### Task 5: `WorkspaceLandingWorktreeRefresher` 定时校准 + landing 接线

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/workspace_landing_worktree_refresher.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Test: Create `client/test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart`

**Interfaces:**
- Consumes: `WorktreeCubit.reloadActiveRepo`（Task 1）、`WorkspaceToolsScope`/`WorkspaceRouteActiveScope`（既有）
- Produces: `WorkspaceLandingWorktreeRefresher({required Widget child, bool isSubmitting = false, bool disabled = false})` + `@visibleForTesting static const Duration refreshInterval = Duration(seconds: 15)`。

- [ ] **Step 1: 写失败测试**

创建 `client/test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_worktree_refresher.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_route_active_scope.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/test_runtime_context.dart';

class _CountingLister implements WorktreeLister {
  var calls = 0;
  @override
  Future<List<GitWorktree>> list(String repoPath) async => const [];
}

GitWorktree _wt(String p) => GitWorktree(
  path: p,
  branch: 'refs/heads/x',
  head: 'h',
  isBare: false,
  isMainWorktree: false,
);

class _Harness {
  _Harness({
    required this.routeActive,
    required this.target,
    this.isSubmitting = false,
    this.disabled = false,
  });
  final bool routeActive;
  final RuntimeTarget target;
  final bool isSubmitting;
  final bool disabled;
  late final lister = _CountingLister();
  late final cubit = WorktreeCubit(
    storage: fakeHomeStorage(),
    lister: lister,
    initialRepoPath: '/repo',
  );

  WorkspaceToolsContext get tools => WorkspaceToolsContext(
    targetId: target.id,
    context: RuntimeContext(
      target: target,
      filesystem: testRuntimeContext('/home').filesystem,
      home: '/home',
      cwd: '/home',
      appDataRoot: '/home',
      paths: testRuntimeContext('/home').paths,
    ),
  );

  Future<void> pump(WidgetTester tester, Widget refresher) async {
    await tester.pumpWidget(
      WorkspaceRouteActiveScope(
        routeActive: routeActive,
        child: WorkspaceToolsScope(
          state: WorkspaceToolsScopeState(
            tools: tools,
            roots: const ['/repo'],
            resolving: false,
          ),
          child: BlocProvider<WorktreeCubit>.value(
            value: cubit,
            child: refresher,
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('reloads the active repo on the refresh interval', (
    tester,
  ) async {
    final h = _Harness(routeActive: true, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, greaterThanOrEqualTo(1));
  });

  testWidgets('skips on route inactive', (tester) async {
    final h = _Harness(routeActive: false, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });

  testWidgets('skips on ssh/termux targets', (tester) async {
    final h = _Harness(
      routeActive: true,
      target: RuntimeTarget.ssh('prof', label: 'remote'),
    );
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });

  testWidgets('skips while submitting', (tester) async {
    final h = _Harness(routeActive: true, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(
        isSubmitting: true,
        child: SizedBox(),
      ),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });

  testWidgets('stops polling after unmount', (tester) async {
    final h = _Harness(routeActive: true, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pumpWidget(const SizedBox()); // unmount → dispose
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });
}
```

（若 `in_memory_filesystem.dart` 提供的共享 home 工厂名不是 `fakeHomeStorage`，用 `worktree_cubit_test.dart` 的 import/用法对齐。）

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart`
Expected: 文件不存在 → 失败；创建后刷新器类不存在 → 编译失败。

- [ ] **Step 3: 实现**

创建 `workspace_landing_worktree_refresher.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../cubits/worktree_cubit.dart';
import '../../../models/runtime_target.dart';
import '../../../services/workspace/workspace_tools_scope.dart';
import 'workspace_route_active_scope.dart';

/// Keeps the landing worktree selector's branch labels fresh against terminal /
/// other external git changes while the landing is mounted: reloads the active
/// repo's worktree list on the [refreshInterval] TTL. Skips when not route
/// active, the tools target is remote (SSH/Termux network round-trips), or the
/// compose is submitting/disabled. App-internal mutations are covered by
/// [WorktreeCubit]'s gitMutationSignals subscription, so this is purely the
/// external-change backstop.
class WorkspaceLandingWorktreeRefresher extends StatefulWidget {
  const WorkspaceLandingWorktreeRefresher({
    required this.child,
    this.isSubmitting = false,
    this.disabled = false,
    super.key,
  });

  final Widget child;
  final bool isSubmitting;
  final bool disabled;

  @visibleForTesting
  static const Duration refreshInterval = Duration(seconds: 15);

  @override
  State<WorkspaceLandingWorktreeRefresher> createState() =>
      _WorkspaceLandingWorktreeRefresherState();
}

class _WorkspaceLandingWorktreeRefresherState
    extends State<WorkspaceLandingWorktreeRefresher> {
  Timer? _timer;
  bool _isRemoteTarget = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      WorkspaceLandingWorktreeRefresher.refreshInterval,
      (_) => _tick(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registering read only here (build phase); the timer callback must not
    // touch dependOnInheritedWidgetOfExactType — cache the target kind instead.
    final tools = WorkspaceToolsScope.maybeOf(context)?.tools;
    _isRemoteTarget =
        tools != null && usesSshTransport(tools.context.target.kind);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final widget = this.widget;
    if (widget.isSubmitting || widget.disabled) return;
    if (!WorkspaceRouteActiveScope.peekRouteActiveOf(context)) return;
    if (_isRemoteTarget) return;

    WorktreeCubit? cubit;
    try {
      cubit = context.read<WorktreeCubit>();
    } on ProviderNotFoundException {
      return;
    }
    if (cubit == null || cubit.state.repoPath.trim().isEmpty) return;
    unawaited(cubit.reloadActiveRepo());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

`workspace_chat_landing.dart`：把 return 的整个 `Stack(...)` 包进刷新器：

```dart
return WorkspaceLandingWorktreeRefresher(
  isSubmitting: isSubmitting,
  disabled: disabled,
  child: Stack(
    children: [ ...原有的 ColoredBox 与 back button... ],
  ),
);
```

（顶部 import 该文件；原 `Stack` 内容原样搬入 `child`。）

- [ ] **Step 4: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart`
Expected: 新测试 PASS；既有 landing chrome 测试不受影响。

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_landing_worktree_refresher.dart client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart client/test/pages/home_workspace/workspace/workspace_landing_worktree_refresher_test.dart
git commit -m "feat(landing): TTL worktree refresh backstop for external branch changes"
```

---

### Task 6: 收尾验证

- [ ] **Step 1: 全量静态分析**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 错误 0 警告。

- [ ] **Step 2: 全量单测（后台）**

Run: `cd client && dart run tool/run_tests.dart`（全量）
Expected: 全绿；重点回归 `worktree_cubit_test`、`git_*` 组、`workspace_chat_landing_*`。

- [ ] **Step 3: 手动冒烟（可选注释给人类）**

门外场景：打开 landing → 内置 IDE git 面板切分支（立即刷新标签）→ 终端里 `git checkout another`（≤15s 后标签更新）→ 打开某 worktree 下会话再回来，选择跟随当前 worktree。

- [ ] **Step 4: 无额外改动确认**

`git status --short` 只含本计划 5 个 commit 涉及的文件（工作区其他在途改动不动）。