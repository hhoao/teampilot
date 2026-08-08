# Git 变更列表：右侧对齐操作按钮 + 打开文件功能

**日期:** 2026-08-08
**状态:** 已确认设计（待实现）

## 背景

编辑器工作台的「源代码管理」面板（`GitSourceControlPanel`）中，变更文件/文件夹行目前把状态字母（M/A/D…）和悬停操作按钮（暂存/放弃/取消暂存）放在文件名**后面**，全部靠左。用户希望像 VS Code 一样：操作按钮**右侧对齐**到行右缘，并新增一个「打开文件」按钮（在编辑器里打开真实文件，而非 diff）。

## 目标

1. 文件行：状态字母与悬停操作按钮**右侧对齐**（VS Code 风格）。
2. 新增「打开文件」按钮：点击后在编辑器打开该文件。
3. 文件夹行：悬停操作按钮同样右侧对齐（不加打开文件按钮）。

## 非目标

- 不改变悬停交互模型（悬停时才显示按钮，替换状态字母）。
- 不改变行点击打开 diff 的行为。
- 不新增「在文件树中定位文件」等功能。

## 设计

### 1. 文件行布局（`git_change_tile.dart`）

当前：`[缩进][图标][文件名][M/A/D…]` 全部靠左；悬停时按钮紧跟文件名。

改为：

```
普通状态:  │📄 main.dart                              M│
悬停状态:  │📄 main.dart              [打开文件][放弃][暂存]│
暂存行悬停: │📄 main.dart              [打开文件][取消暂存]  │
```

- 文件名改为 `Expanded`（`overflow: ellipsis`，`maxLines: 1`）。
- trailing（状态字母或按钮组）通过 `Row` 钉在行右缘。
- 非悬停显示状态字母（现有 `_badge`，右对齐）；悬停替换为按钮组。

**布局实现：**

- 移除 `OverflowBox(maxWidth: double.infinity, alignment: centerLeft)`。
- 改为 `SizedBox(width: double.infinity, height: kGitChangesNodeHeight)` + `Row`（`Expanded` 文件名 + 右侧 trailing）。
- `Row` 因此获得有界宽度，`Expanded` 可用；深度缩进仍由 `TpHover` 的 padding 承担。

### 2. 打开文件按钮

- 图标：`Icons.file_open_outlined`（Flutter 已内置 0xf05f9）。
- Tooltip：新增 l10n key `gitOpenFile`（en: `Open File`，zh: `打开文件`）。
- 位置：按钮组最左侧，顺序：
  - 未暂存行：`[打开文件][放弃][暂存]`
  - 暂存行：`[打开文件][取消暂存]`
- 行为：`WorkbenchEditorOpener.openFile(workspaceId: ws, path: p.join(repoRoot, change.path))`，在编辑器打开真实文件（非 diff）。
- **`GitChangeKind.deleted` 的行不显示**打开文件按钮（磁盘上文件不存在）。
- 回调管线（与现有 `onOpenDiff` 平行）：
  - `GitSourceControlPanel._openFile(GitFileChange)` → `GitChangesTreeList(onOpenFile: …)` → `GitChangeTile(onOpenFile: …)`。
  - `_openFile` 内 `absolutePath = p.join(_cubit.state.repoRoot, change.path)`，与 `_openDiff` 一致。

### 3. 文件夹行（`git_change_folder_tile.dart`）

- 同样的右对齐改造：`[▸][📁][文件夹名(Expanded)][悬停操作按钮]`。
- 文件夹行不加打开文件按钮。
- 行点击仍切换展开/收起。

### 4. 宽度常量（`git_changes_visible_rows.dart`）

`TpIconButton.kCompactSize` = 28，所以：未暂存行悬停 3 个按钮 = 84，暂存行/文件夹行 2 个按钮 = 56。

- 新增 `kGitChangesTrailingActionsWidth = 84`（未暂存行悬停、最宽的 trailing）。
- 新增 `kGitChangesTrailingTwoActionsWidth = 56`（暂存行/文件夹行悬停）。
- `gitChangesMinContentWidth` 与 `_rowWidthEstimate` 中 trailing 取值统一为：
  - 未暂存文件行 → `kGitChangesTrailingActionsWidth`（84）
  - 暂存文件行 → `kGitChangesTrailingTwoActionsWidth`（56）
  - 文件夹行 → `kGitChangesTrailingTwoActionsWidth`（56）
- 使最长文件名在悬停显示全部按钮时仍不被截断。
- 保留现有横向滚动：`contentWidth` 仍按最长行计算；普通状态下文件名不省略，需要时可横向滚动看全名。

### 5. 国际化

`client/lib/l10n/app_en.arb` 与 `app_zh.arb` 各加一条：

- `gitOpenFile`: `Open File` / `打开文件`

## 测试

新增 widget 测试（复用 `_RepoGitStub` / `setUpTestAppStorage()` 模式，见 `git_source_control_panel_generate_test.dart`）：

1. 悬停未暂存文件行 → 出现打开文件按钮（`Icons.file_open_outlined`）。
2. 点击打开文件按钮 → 编辑器打开该文件（校验 `WorkbenchEditorOpener`/floating surface 收到 `openFile`）。
3. `deleted` 类型行不显示打开文件按钮。
4. 文件夹行悬停仍显示暂存/取消暂存按钮且右对齐（结构断言）。

## 改动文件

| 文件 | 改动 |
|------|------|
| `client/lib/widgets/git/git_change_tile.dart` | 右对齐布局 + 打开文件按钮 |
| `client/lib/widgets/git/git_change_folder_tile.dart` | 右对齐布局 |
| `client/lib/widgets/git/git_changes_tree_list.dart` | 透传 `onOpenFile` |
| `client/lib/widgets/git/git_source_control_panel.dart` | 新增 `_openFile` 处理 |
| `client/lib/services/git/git_changes_visible_rows.dart` | 宽度常量 |
| `client/lib/l10n/app_en.arb`、`app_zh.arb` | `gitOpenFile` |
| `client/test/widgets/git/` | 新增测试 |
