# 源代码管理面板：IDEA 选择模型（勾选=纳入提交，提交时才 git add）

**日期:** 2026-08-09
**状态:** 已确认设计（待实现）

## 背景

当前面板复选框绑定 git **index 暂存**：勾选立即跑 `git add` / `git reset`。用户指出这不符合 IDEA 模型——IDEA 的复选框只是"**纳入下次提交**"的选择（changelist 成员），勾选不执行 git，`git add` 发生在提交那一刻。现状带来的问题：每次勾选都有 git 子进程往返（即便已做乐观更新，仍有后台开销），且面板里的"暂存"与真实 index 语义混淆。

目标：切换为 **IDEA 选择模型**——复选框 = 提交勾选集（纯 UI 状态，零 git、零延迟）；提交时对勾选集批量 `git add` + `git commit -- <paths>`。

## 目标

1. **勾选是纯 UI 状态**：`GitState.selectedPaths`（`Set<String>`），点击复选框不触发任何 git 命令，瞬时反馈。
2. **默认全选 + 保留手动调整**：首载/换根默认勾选全部变更；刷新时新增文件自动勾选、消失路径自动移除、用户手动取消的保持不变。
3. **提交 = 勾选集**：`git add -- <勾选>` + `git commit -m <msg> -- <勾选>`，只提交勾选的路径（忽略 index 里其它内容）。
4. 文件夹三态、组头全选按 `selectedPaths` 计算。
5. Diff 简化为 `HEAD vs 工作区`；右键菜单 `暂存/取消暂存` → `纳入/排除本次提交`。

## 非目标

- 不做 git index 的 UI 暂存区（面板里不再有"staged"概念；已在 index 的其它内容保持不变，直到用户用别的工具处理）。
- 勾选集不持久化到磁盘（会话内状态）。
- `discard` / `discardAll` / `discardFolder` 语义不变（真实 git、确认后执行）。

## 设计

### 1. 选择状态与树模型

- `GitState` 新增 `final Set<String> selectedPaths;`（默认 `{}`）。
- `GitChangesTreeViewData`：`stagedCount` → `selectedCount`；`allStaged`/`noneStaged` → `allSelected`/`noneSelected`。`totalCount` 不变。
- `GitChangesVisibleRow.folder`：`subtreeStagedCount` → `subtreeSelectedCount`（仍与 `subtreeTotalCount` 并列）。
- `visibleUnifiedGitChangesTreeView` 新增 `required Set<String> selectedPaths` 参数：文件夹子树计数按 `selectedPaths` 计算（文件行已选 = `selectedPaths.contains(path)`）。
- `_publish` 把 `state.selectedPaths` 传入树构建器；任何选择变化都 `_publish(copyWith(selectedPaths: next))` 重算树（O(n)，无子进程）。

### 2. 复选框语义

| 行 | 勾选值 | 点击 |
|----|--------|------|
| 文件 | `selectedPaths.contains(change.path)` | `cubit.toggleSelect(path)` |
| 文件夹 | 三态：`subtreeSelectedCount`/`subtreeTotalCount`（0→false、全→true、部分→null） | `cubit.toggleSelectFolder(folderPath)`：全选时全部移出，否则全部加入 |
| "Changes" 组头 | 三态：`selectedCount`/`totalCount` | `cubit.selectAll()` / `cubit.selectNone()` |

这些方法**只改内存集合 + 重算树**，不触发 git。

### 3. 默认选择与刷新对账

`GitCubit` 持有私有 `Set<String> _knownChangedPaths`（上一次 status 的变更路径集）。

`_runRefresh` 拿到新 status 后：
1. `changedNow = status.staged ∪ status.unstaged 的 path 集合`。
2. `selectedPaths = (state.selectedPaths ∩ changedNow)`（丢弃已消失路径）。
3. `newOnes = changedNow - _knownChangedPaths`（新增的变更）→ 全部加入 `selectedPaths`（默认勾选）。
4. `_knownChangedPaths = changedNow`。

首载/换根时 `_knownChangedPaths` 置空 → 全部变更默认勾选。之后刷新保留手动调整、新增自动勾选。

### 4. 提交流程

- `GitService.commitSelected(String dir, String message, List<String> paths)`：
  ```
  git add -- <paths>
  git commit -m <message> -- <paths>
  ```
  （`git add` 处理未跟踪/删除；`-- <paths>` 只提交这些路径，index 里其它内容保持不变。`paths` 空则不应调用。）
- `GitCubit.commit()`：取 `state.selectedPaths.toList()`，为空 → 不发命令（`canCommit` 已拦）；否则 `_mutate(() => _service.commitSelected(...))`。
- 提交成功 → `refresh()` → 对账：被提交路径不再在变更集中 → 自动移出勾选。
- 面板 `canCommit` / `canGenerate`：`selectedPaths.isNotEmpty`。

### 5. Diff 简化

- `_openDiff` 的 `source` 一律 `WorkbenchDiffSource.changes`（HEAD vs 工作区）；diff 内容取该路径的工作区变更。不再有 staged/unstaged 的 diff 区分。

### 6. 右键菜单

- 文件行菜单项 `Stage/Unstage` → `l10n.gitIncludeInCommit`（"纳入本次提交"，未勾选时）/ `l10n.gitExcludeFromCommit`（"排除出本次提交"，已勾选时）。icon `Icons.add`/`Icons.remove`。
- 文件夹行 `Stage Folder/Unstage Folder` → `gitIncludeFolderInCommit` / `gitExcludeFolderFromCommit`。
- 移除 `gitStage`/`gitUnstage`/`gitStageFolder`/`gitUnstageFolder` 的 UI 使用（l10n key 可移除或保留，倾向移除）。

### 7. 移除乐观 stage/unstage

- 删除 `_optimisticMutate`、`_moveOptimistic`、`_moveFolderOptimistic`、`_moveAllOptimistic`（上一轮为"暂存"加的）。
- `GitCubit.stage`/`unstage`/`stageFolder`/`unstageFolder`/`stageAll`/`unstageAll` 替换为 `toggleSelect`/`toggleSelectFolder`/`selectAll`/`selectNone`。
- 清理不再使用的成员：实现后 `grep` 检查 `GitFileChange.copyWith`、`GitRepoStatus.copyWith`、`stage`/`unstage`/`stageAll`/`unstageAll`（含 `stageFolder`/`unstageFolder`）以及 l10n key（`gitStage`、`gitUnstage`、`gitStageFolder`、`gitUnstageFolder`、`gitStageAll`、`gitUnstageAll`）——**确认无其它引用后删除**；若个别仍被引用则保留并注明。

### 8. 技术改动清单

| 文件 | 改动 |
|------|------|
| `client/lib/cubits/git_cubit.dart` | `selectedPaths` 状态、`_knownChangedPaths` 对账、`toggleSelect`/`toggleSelectFolder`/`selectAll`/`selectNone`（纯 UI）、`commit` 改 `commitSelected`、删除乐观逻辑 |
| `client/lib/services/git/git_service.dart` | 新增 `commitSelected` |
| `client/lib/models/git_status.dart` | 视使用情况保留/移除 `copyWith` |
| `client/lib/services/git/git_changes_visible_rows.dart` | 树构建器加 `selectedPaths`，文件夹计数改为已选 |
| `client/lib/widgets/git/git_change_tile.dart` | 复选框绑定 `selectedPaths`（经 cubit/回调） |
| `client/lib/widgets/git/git_change_folder_tile.dart` | 三态按 `subtreeSelectedCount` |
| `client/lib/widgets/git/git_changes_tree_list.dart` | 组头/文件夹三态按选择；`selectedCount` |
| `client/lib/widgets/git/git_context_menu.dart` | `纳入/排除本次提交` 菜单项 |
| `client/lib/widgets/git/git_source_control_panel.dart` | `canCommit`=选择非空；`_openDiff` 用 `changes` 源 |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 新增 include/exclude 文案；移除 stage/unstage 相关 |
| 测试 | cubit（选择瞬时/对账/commitSelected）、tile（复选框绑定选择）、tree-list（三态按选择）、panel（canCommit/diff/提交）重写 |

### 9. 测试

- 单元（`git_changes_visible_rows_test.dart`）：文件夹三态按 `selectedPaths` 计算。
- Cubit：`toggleSelect` 瞬时（无 git 调用，用 stub 断言 service 未被调用）；`selectAll`/`selectNone`；刷新对账（新文件自动勾选、消失路径移除、手动取消保留）；`commit` 调用 `commitSelected`（argv 含 `add` + `commit --`）。
- Tile：复选框值来自选择集；点击触发 toggle。
- Tree-list：文件夹/组头三态按选择。
- Panel：`canCommit` 随选择变化；提交流程。

### 10. 性能

- 勾选 = 内存集合更新 + O(n) 树重算，无子进程 → **彻底瞬时**（优于乐观更新方案）。
- 提交才触发 git（`add` + `commit` 两次子进程，提交是低频操作，可接受）。
