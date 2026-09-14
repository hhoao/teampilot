# Landing worktree 选择器与外部分支切换同步

- 日期：2026-09-14
- 状态：设计待审
- 目标：landing 对话页的 worktree/git 选择器在「别处切换分支」后不再显示过期分支名，并且选择能跟随外部 worktree 切换；界面看到的永远等于会话实际启动所在 worktree 的真实分支。
- 关联：[auto git fetch](2026-09-09-auto-git-fetch-design.md)（同为 git 状态驱动 UI 刷新的模式参考）。

## 背景

landing 顶部 `WorkspaceLandingHeaderRow`（项目 + worktree 两个下拉）展示的标签来自最近一次 `git worktree list` 的快照：

- 选中值解析是**路径优先**：`resolveSelectedWorktreePath`（`workspace_landing_selectors.dart:199`）先看持久化的 `_selectedWorktreePath`，再 fallback 到 `WorktreeCubit.currentWorktreePath`，最后取第一项。路径不因 checkout 失效，所以**选中项本身不会错**。
- 但菜单/芯片的**分支名**来自 `GitWorktree.shortBranch`（`git_worktree.dart:29`），是加载时刻的 `git worktree list` 结果，只随 `WorktreeCubit.load(force:true)` 刷新。
- 外部 `git checkout feature`（终端里，或 git 面板/graph 面板内）**不会**触发 `WorktreeCubit` 重载：
  - `gitCubit.checkoutBranch`/`createBranch`（`git_cubit.dart:576/582`）只 `ensureBranches`，不碰 worktree cubit。
  - `GitGraphActionsController._run`（`git_graph_actions_controller.dart:100`）成功后只 `cubit.refresh()`（刷新 graph cubit），不碰 worktree cubit。
  - 终端里的 checkout 完全不可见。
- 结果：芯片显示 `main` 但当前 worktree 已在 `feature` 上，新会话实际跑在 `feature` —— 用户看着错分支名开工。标签会一直过期，直到选中 worktree 被删除/重建、或走一遍「选择器手动刷新」、或 `WorktreeCubit` 因绑定/sync 重载。

约束（设计必须遵守的现有行为）：

- `WorktreeCubit.load`（`worktree_cubit.dart:237`）的 selection 优先级会保住当前/持久化的选中 worktree 不漂移，重载时应沿用。
- `_syncLaunchFromWorktree`（`unbound_compose_body.dart:858`，`BlocListener` 挂载于 `:1742`）只在 `currentWorktreePath` 变化时同步选中——「外部切到别的 worktree 持有的分支」这种场景天然由它接管，无需新逻辑。
- `git worktree list` 在 SSH/Termux 仓库上每次都是网络往返（`GitWorktreeService.forContext(tools.context)`），不能高频轮询。

## 目标与非目标

### 目标

1. 应用内 git 分支类操作（git 面板 checkout/create、graph 面板 checkout/create/delete/rename/reset 等）成功后，立即重载对应仓库的 worktree 列表。
2. 终端等外部变更：landing 挂载期间每 15s TTL 校准一次 worktree 列表（本地/WSL 仓库）；SSH/Termux 不轮询。
3. 重载后选择器芯片与下拉分支名实时正确；外部切换真正落到另一个 worktree 时，现有 `_syncLaunchFromWorktree` 让选择器跟随。
4. 重载绝不打断当前选中（沿用 `load` 的选择保留逻辑），并发/凑堆触发合并，且 `WorktreeCubit` 未绑定 git runner 时静默跳过。

### 非目标

- 不监听终端 PTY 输出解析命令（不做「识别 user 敲了 git checkout」）。
- 不改 `git worktree list` 服务、不改选择器解析优先级、不改 `_syncLaunchFromWorktree` 语义。
- 不做提交前的强制二次校验（本次只保证显示与跟随正确）。

## 设计

### A. 应用内变更 → 立即重载（事件驱动）

**1. `GitRepoStore` 增加 HEAD 变更信号**（`git_repo_store.dart`，本就是这个联邦层，零新增服务）

```
final _headChanged = StreamController<String>.broadcast(sync: true);
Stream<String> get headChanged;            // 事件 = repoRoot
void notifyHeadChanged(String repoRoot);   // 仅 repoRoot 非空时发
```

`dispose()` 时关闭 controller。

**2. 两个写入口上报事件**

- `GitCubit` 构造新增可选 `void Function(String repoRoot)? onHeadChanged`，由 `GitRepoStore._cubitFactory` 注入 `notifyHeadChanged`；`checkoutBranch`/`createBranch` 在 `_mutate(...)` 返回 true 时 `onHeadChanged?.call(state.repoRoot)`。构造参数默认 null（测试用 `_injectedCubitFactory` 不传即可），不破坏既有测试。
- `GitGraphActionsController` 新增可选 `void Function(String repoRoot)? onMutated`；`_run` 成功时 `onMutated?.call(_dir)`。四个构造点（`git_graph_pane.dart:407`、`git_graph_toolbar.dart:252/296`、`git_graph_refs_menu.dart:139`）统一传 `(root) => context.read<GitRepoStore>().notifyHeadChanged(root)`。一次覆盖 graph 全部 checkout/create/delete/rename/reset/tag 操作；失败不通知（`_run` 失败分支不动）。

**3. 消费端：`WorkspaceToolsScopeSync` 订阅**（`workspace_tools_scope_sync.dart`）

它已经同时持有 tools 平面与 `WorktreeCubit`（`bindWorktreeService`，`:112`）。新增：

- `initState` 中 `_headSub = context.read<GitRepoStore>().headChanged.listen(...)`，`dispose` 取消。
- 回调：repoRoot 与 `worktreeCubit.state.repoPath` 匹配（`workspacePathsEqual`）且路径非空时 `unawaited(worktreeCubit.reloadActiveRepo())`。
- 监听不区分 target 远端类型（应用内 mutation 是低频、用户主动的，SSH 网络往返可接受）。

**4. `WorktreeCubit.reloadActiveRepo()`**

```
Future<void> reloadActiveRepo() async {
  if (_lister == null) return;                 // 未绑定 git runner，静默跳过
  final repo = state.repoPath.trim();
  if (repo.isEmpty) return;
  // 去重（抄 gitCubit.refresh 的 in-flight/trailing 模式，git_cubit.dart:241）
  if (_reloadInFlight) { _reloadQueued = true; return; }
  _reloadInFlight = true;
  try { await load(repo, force: true); }
  finally {
    _reloadInFlight = false;
    if (_reloadQueued && !isClosed) { _reloadQueued = false; await reloadActiveRepo(); }
  }
}
```

`load(force:true)` 直接用 `lister.list(...)`，git 出错时会抛 `GitException`；`reloadActiveRepo` 用 `try/catch` 包住整段 `load`，失败静默、只记 `AppLogger.d`，不冒泡到 UI —— 过期标签靠下一轮事件/TTL 自愈。`_lister == null` 时 `load` 才会抛的 `StateError` 已由前置短路挡住。

### B. landing 挂载期定时校准（兜住终端等外部操作）

新增无渲染 widget `WorkspaceLandingWorktreeRefresher`，包在 `WorkspaceChatLanding` 的 `UnboundComposeBody` 外层（`workspace_chat_landing.dart:80`）。`selection_ask_ai.dart:157` 的 `UnboundComposeBody` 不经过它，不受影响。

- `Timer.periodic(const Duration(seconds: 15))`（`@visibleForTesting static const refreshInterval`），`initState` 启动、`dispose` 取消，不碰 setState（不触发 rebuild）。
- 每 tick 检查后调 `worktreeCubit.reloadActiveRepo()`，任一条件不满足即跳过：
  - `WorkspaceRouteActiveScope.maybeOf(context)` 为 true（`routeActive`，landing 不在前台不轮询）；
  - 当前工具 target 非远端：`tools.context.target.kind` 满足 `usesSshTransport`（`runtime_target.dart:24`，即 ssh/termux）→ 跳过轮询（A 仍覆盖应用内操作）；
  - `WorktreeCubit` 可取（`ProviderNotFoundException` 兜住）且 `state.repoPath` 非空；
  - 非 `widget.isSubmitting` / `widget.disabled`。

### 数据流

```
git 面板/ graph 切分支 ──► GitRepoStore.notifyHeadChanged ──► WorkspaceToolsScopeSync
                                                                  └► WorktreeCubit.reloadActiveRepo ──► load(force:true)
终端/外部 checkout ──► (≤15s) WorkspaceLandingWorktreeRefresher tick ──► reloadActiveRepo ──► load(force:true)
                                                                              └► emit 新 worktrees
                                                                                    └► landing 选择器 rebuild（标签/菜单变新）
                                                                                    └► currentWorktreePath 若变化 → 既有 _syncLaunchFromWorktree 跟随选中
```

## 边界与错误处理

- **重载不漂移选中**：`load` 的 `inList(state.currentWorktreePath)` 优先级天然保留当前 worktree；组件 A/B 都不改 `resolveSelectedWorktreePath` 和 `_selectedWorktreePath`。
- **未绑定**：tool 平面未 resolve 前 `_lister == null`，`reloadActiveRepo` 短路返回；首次 `bindWorktreeService` 本来就触发初次 `load`，不会丢。
- **git 错误 / 非仓库**：reload 静默吸收，不弹错、不闪 loading；`load` 对空列表（非 git）也正常 emit。
- **凑堆**：组件 B 的 15s 定时天然节流；组件 A 事件 + `_loadGeneration` 只让最后一次生效；`reloadActiveRepo` 的 in-flight/trailing 保证同一仓库并发 reload ≤2 条子进程链。
- **Ask AI 等其他 compose 宿主**：不加 refresher，行为不变。

## 成本

- A：`GitRepoStore` 信号 ~20 行；`GitCubit` 构造参数 + 2 处 notify ~10 行；`GitGraphActionsController` `onMutated` ~8 行 + 4 个构造点各 1 行；`WorkspaceToolsScopeSync` 订阅 ~25 行；`reloadActiveRepo` ~25 行。合计 ≈ 90-110 行。
- B：`WorkspaceLandingWorktreeRefresher` ≈ 60-90 行。
- 运行时：本地仓库每 TTL 1 次 `git worktree list --porcelain`（1 子进程，语义约等于 git 面板刷新）；SSH/Termux 只有 A 的「应用内 mutation」触发。

## 测试

- `WorktreeCubit.reloadActiveRepo`：
  - 未绑定 lister 时静默跳过（不抛错）；
  - 触发后 `load` 且 worktree 列表更新；
  - 并发调用合并：同一仓库 in-flight 期间第二次调用只排队一次 trailing；
  - git 错误被吸收、状态不脏。
- `WorkspaceToolsScopeSync` 订阅：匹配 repoPath 事件触发 reload；不匹配/空路径忽略；dispose 取消订阅。
- `GitCubit.checkoutBranch` / `GitGraphActionsController`：成功回调 `onHeadChanged`/`onMutated`（repoRoot 正确）；失败不回调。
- `WorkspaceLandingWorktreeRefresher`（widget 测试，注入假 lister）：
  - `Timer.periodic` 触发 reload；
  - SSH target / route 不活跃 / submitting 时不 reload；
  - 卸载取消定时器。
- 现有 landing 选择器测试不变（新 timer 无副作用；用 fake ticker/lister 隔离）。