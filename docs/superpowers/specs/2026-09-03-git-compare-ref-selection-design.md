# Git Compare: 分支/标签弹层发起 ref↔ref 对比

**Date:** 2026-09-03
**Status:** Approved (conversation)
**Related:** [2026-09-03-git-compare-working-tree-design.md](./2026-09-03-git-compare-working-tree-design.md)

## Goal

从 Git Graph 工具条的分支/标签弹层发起任意 ref↔ref（或 ref↔工作区）对比。v1 的 Git Compare 仅能从 commit 行菜单发起「ref ↔ Working Tree」；模型层（`GitCompareSpec`）与 service 层（`listDiffFiles` / `fileDiff`）已支持 ref↔ref，只缺 UI 入口。

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| 入口 | 分支/标签弹层条目子菜单新增「与…比较」（local / remote / tag 三个分区统一加） |
| 目标选择 | 二级菜单（`showTpActionMenuFromSpecs`）：首条「工作区({当前分支})」+ 本地/远程/标签三分区滚动列表 |
| 源自身 | 二级菜单中源 ref 条目置灰（`enabled: false`） |
| 方向 | `left` = 点「比较」的源 ref，`right` = 选中的目标（工作区时为 `GitCompareWorkingTree`）——与行菜单 `diff-working-tree` 的方向约定一致 |
| 数据 | 全部来自 `GitGraphState.branches / tags / currentBranch / repoRoot`，不新增 service 调用 |
| Tab | 复用现有 `gitCompare` floating tab；`tabId` 已支持 `ref:xxx|ref:yyy` |
| Out of scope | 对比面板内切换两侧、搜索过滤二级菜单、commit 右键菜单入口、面板头可点击编辑 |

## Interaction

1. 分支/标签弹层 → 点某条目（如 `feat/x`）→ 子菜单含「与…比较」（icon: `difference_outlined`）。
2. 弹出二级菜单：
   - 首条固定：**「工作区({当前分支})」** → `feat/x ↔ Working Tree`
   - 本地分支 / 远程分支 / 标签三个滚动分区（复用主弹层分区结构）；源 ref 自身置灰。
   - 仅本地分支且无远程/标签且只剩源自身时：目标列表可能只剩工作区项——允许，不做特殊空态。
3. 选中目标 → 组装 `GitCompareSpec(repoRoot, left: GitCompareRef(源), right)` → `openGitCompareTab`，同一 `(repoRoot, left, right)` 再次打开激活已有 tab。

## Code changes

| 文件 | 改动 |
|------|------|
| `client/lib/pages/git_graph/git_graph_refs_menu.dart` | 三个分区子菜单各加 `compare` 项；`_openSubmenu` 增加 `case 'compare'` → `_openCompareTargetMenu(entry)`；widget 新增 `workspaceId` 参数 |
| `client/lib/pages/git_graph/git_graph_toolbar.dart` | `GitGraphToolbar` 新增 `workspaceId`，透传给 `GitGraphRefsMenu` |
| `client/lib/pages/git_graph/git_graph_pane.dart` | `_PaneBody` 传 `workspaceId` 给 toolbar |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 新增 `gitGraphCompareWith`、`gitGraphCompareWorkingTree(branch)` |
| models / service / cubit / pane | 无改动 |

## Error handling

- 目标 ref 失效（如分支被删）：`GitCompareCubit.load` 现有 `GitException` → `_LoadError` 重试路径兜底。
- `repoRoot` 为空（非仓库）：弹层本身不渲染可点条目，无需处理。
- 远程分支 / 标签：`GitCompareRef` 接受任意 ref 名，`git diff a origin/b` / tag 均有效。

## Testing

- 新建 `client/test/pages/git_graph/git_graph_refs_menu_test.dart`：mock `GitGraphState`（本地+远程分支、标签）→ 子菜单含「与…比较」→ 二级菜单列出工作区 + refs、源自身置灰 → 选中后断言 `WorkbenchCubit.openFloating` 收到的 `WorkbenchTabId.gitCompare(spec)` 的 left/right/repoRoot 正确（参考现有 git_graph widget 测试的 cubit mock 模式）。
- 覆盖三个用例：本地分支↔工作区、本地分支↔远程分支、标签↔标签以外的分支。
- 手动验证：分支↔分支、标签↔分支、远程分支↔工作区。
