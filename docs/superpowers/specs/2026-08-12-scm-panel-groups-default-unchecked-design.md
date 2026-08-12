# SCM 面板分组与默认勾选设计

日期:2026-08-12

## 背景与动机

内置 IDE 的源代码管理面板当前把所有变更(已跟踪修改 + 未跟踪新文件)混在一个统一的 "Changes" 树里,且**所有**新出现的变更都会自动勾选(选中 = 纳入下次提交)。用户希望对齐 IntelliJ IDEA 的 Commit 窗口体验:

1. 未跟踪的新文件**默认不勾选**(已跟踪修改仍默认勾选)
2. 变更分为两个分组:**Changes**(已跟踪修改/删除/重命名/冲突)**Unversioned Files**(未跟踪新文件)

## 现状

- 自动勾选:`GitCubit._reconcileSelectedPaths`(`client/lib/cubits/git_cubit.dart:274`)在每次状态刷新时把 `changedNow - _knownChangedPaths` 的所有路径(含 untracked)加入 `selectedPaths`;手动取消的勾选会保留。
- 勾选是纯 UI 选择模型(对应 IDEA 的 "include in the next commit"),不执行 `git add`;`commitSelected` 在提交时才 `git add -- <paths>` + `git commit -- <paths>`。
- 树构建:`visibleUnifiedGitChangesTreeView`(`client/lib/widgets/git/git_changes_visible_rows.dart:211`)把 index + worktree 变更按路径合并成单个文件夹树,`staged` 字段被 `selectedPaths` 覆盖用于勾选框显示。
- 分组标题:根部 `_GitChangesRootHeader` 三态全选框 → `selectAll`/`selectNone`(`git_cubit.dart:372`)。
- 未跟踪文件已能区分:`git status --porcelain=v2` 的 `?` 行 → `GitChangeKind.untracked`;diff 用 `git diff --no-index /dev/null <path>`,discard 用 `git clean -f`。

## 设计

### 1. 默认勾选规则

在 `_reconcileSelectedPaths` 中,新出现的变更仅当满足以下任一条件才自动勾选:

- 已跟踪文件(kind 为 modified / deleted / renamed / conflicted)
- 已在 git index 中暂存(`staged == true`)

未跟踪且未暂存(`kind == untracked && !staged`)的新文件**不自动勾选**。手动勾选行为不变(持久保留)。

### 2. 双分组布局

- **Changes 组**:所有已跟踪变更(含已暂存的 added),保留现有文件夹折叠树与三态全选框。
- **Unversioned Files 组**:所有未跟踪文件,同样按文件夹折叠,带自己的三态全选框。
- 组为空时整组隐藏;两组均空时面板显示空态(现有行为)。
- 展开/收起全部按钮作用于两个组;文件夹展开状态(`expandedFolderPaths`)跨组共享(同一文件夹出现在两组时折叠状态一致)。
- 提交按钮(`selectedPaths.isNotEmpty`)、repo 选择器、右键菜单、badge、diff/discard 行为均不变。

### 3. 代码改动

| 文件 | 改动 |
|------|------|
| `client/lib/cubits/git_cubit.dart` | `_reconcileSelectedPaths` 按规则自动勾选;`selectAll`/`selectNone` 拆分为按分组(或加分组参数) |
| `client/lib/widgets/git/git_changes_visible_rows.dart` | 拆出 unversioned 树的构建(复用现有文件夹折叠/排序逻辑) |
| `client/lib/widgets/git/git_changes_tree_list.dart` | `_GitChangesRootHeader` 支持分组标题 + 分组级全选回调 |
| `client/lib/widgets/git/git_source_control_panel.dart` | 挂载两个分组,空组隐藏 |
| `client/test/widgets/git/git_changes_tree_list_test.dart` 等 | 更新自动勾选断言(untracked 不再自动选中),新增分组/勾选规则测试 |

## 测试

- `_reconcileSelectedPaths`:新出现的 untracked 不自动勾选;tracked 修改自动勾选;index 中已暂存的 untracked 自动勾选;手动勾选的 untracked 在刷新后保留。
- 树构建:按 kind 拆到正确分组;同路径 staged 优先归 Changes;空组隐藏。
- 分组全选:仅影响该分组路径。
