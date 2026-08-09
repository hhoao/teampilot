# 源代码管理面板：IDEA 风格（复选框 + 工具栏 + 右键菜单）

**日期:** 2026-08-09
**状态:** 已确认设计（待实现）

## 背景

当前 Git 源代码管理面板（`GitSourceControlPanel`）采用 VS Code 风格：每行**右缘**的悬停操作按钮（暂存/放弃/打开文件）在宽屏下离文件名太远、点击麻烦。用户希望改为 IntelliJ IDEA 的版本控制面板交互：

- 每行左侧**常驻复选框**（紧挨文件名），复选框 = 暂存状态。
- 顶部**常驻工具栏**承载全局操作。
- 行**单击** = 选中并打开 diff；**双击** = 打开文件；**右键** = 上下文菜单。
- 不再有每行右缘的悬停按钮。

## 目标

1. **统一树 + 复选框**：staged + unstaged 合并为一段目录树；文件复选框勾选=暂存、取消=取消暂存；文件夹复选框三态；顶层 "Changes" 组头全选。
2. **常驻工具栏**：分支选择、展开/折叠全部、放弃下拉、拉取、推送、刷新。
3. **选择模型 + 右键菜单**：单击选中当前行（供工具栏/菜单共用），右键弹出文件/文件夹操作菜单。
4. **打开文件**：双击行 + 右键菜单"打开文件"。
5. **放弃**：`git restore .` 放弃全部未暂存（不删未跟踪）；单文件未跟踪放弃走 `clean -f`（确认）。

## 非目标

- 不做多行多选（选择模型保留扩展点，本次单选）。
- 不在面板内嵌 diff 预览分栏（diff 仍走现有浮动预览/编辑器 tab）。
- 不做历史/分组方式切换/Locate 等 IDEA 完整工具栏项。

## 设计

### 1. 布局

```
┌────────────────────────────────────────────────┐
│ [分支 ▾]          [展开/折叠][放弃▾][拉取][推送][刷新] │
│ [提交框: 文本域]              [✨生成][✓提交]          │
│ ▸ ☐ Changes · 8                                     │
│    ▾ ☑ 📁 domain                                   │
│       ☐ 📄 TableLabelResultRepository.java  M      │
│       ☑ 📄 Foo.java                                 │
│    ☐ 📄 README.md                                   │
└────────────────────────────────────────────────┘
```

顺序：工具栏 → 提交框 → 统一树。

### 2. 统一树 + 复选框

**树构建（`git_changes_visible_rows.dart`）：**

- 新增统一树视图：输入 `List<GitFileChange> changes`（staged + unstaged **合并**），输出一段 `GitChangesVisibleRow` 列表，目录分组（复用现有 `_GitChangesFolderNode` / `_walk`）。
- **路径去重**：同一路径同时出现在 staged 与 unstaged（部分暂存 "MM"/"AM"）时合并为一行。勾选状态 = 是否有已暂存内容（`staged` 取 OR）；badge/kind 优先取 staged 侧。
- **文件夹三态**：构建时对每个文件夹节点累积 `stagedCount` / `totalCount`（子树），一次遍历 O(n) 算好，供复选框渲染三态。
- `GitChangesVisibleRow` 扩展字段：
  - `folder`：新增 `subtreeStagedCount`、`subtreeTotalCount`（三态用）。
  - `file`：沿用 `change`（含 `staged`）。
- 顶层 "Changes" 组头：面板/树列表自行渲染（不计入行列表），显示 `Changes · N`（N=总变更文件数），全选复选框三态与文件夹一致。

**复选框语义（`git_change_tile.dart` / `git_change_folder_tile.dart`）：**

- 文件复选框：`checked = change.staged`。点击 `onTap` → `cubit.stage(change)`（未暂存）或 `cubit.unstage(change)`（已暂存）。
- 文件夹复选框：三态（全 ✓ / 全 ☐ / 部分 ▦，用 Material `Checkbox`/自定义 `TpCheckbox` 的 tri-state）。点击 → `cubit.stageFolder(path)` / `cubit.unstageFolder(path)`。
- 顶层 "Changes" 全选：点击 → `cubit.stageAll()` / `cubit.unstageAll()`（依据全选状态：部分/全未暂存→暂存全部，全已暂存→取消全部）。

**行布局（文件）：** `[复选框][文件图标][文件名 Expanded+ellipsis][状态字母 M/A/D]`，状态字母常驻（非按钮）。
**行布局（文件夹）：** `[chevron][复选框][文件夹图标][文件夹名 Expanded+ellipsis]`。

**行宽计算：** `gitChangesMinContentWidth` 更新——去掉 hover 按钮宽度（84/56），trailing = 状态字母 badge（22）+ 复选框/间距常量。移除不再使用的 `kGitChangesTrailingActionsWidth` / `kGitChangesTrailingTwoActionsWidth`（或按新行重定义）。

### 3. 选择模型

- **单选当前行**：单击文件行 = 选中 + 打开 diff。单击文件夹行仅切换展开/折叠，**不改变选中**；文件夹的操作用右键菜单（`暂存文件夹` / `取消暂存文件夹` / `放弃文件夹` / `复制路径`）。
- 选中状态提升到 `_GitRepoBodyState`（`String? _selectedPath`，仅指文件路径），经 `GitChangesTreeList` 下传、上回报。工具栏与右键菜单共用。
- 选中行高亮（TpHover 现有 hover 高亮基础上加 `selected` 态背景）。
- 工具栏"放弃所选"针对 `_selectedPath` 对应的文件；无选中时该项禁用。

### 4. 右键上下文菜单

- 文件行：**打开文件** / **显示 Diff** / **放弃** / **暂存 或 取消暂存** / **复制路径**。
- 文件夹行：**暂存文件夹** / **取消暂存文件夹** / **放弃文件夹**（`git restore <folderPath>`，确认）/ **复制路径**。
- 菜单项在不可用时不显示或禁用（如已暂存文件不再显示"暂存"；未跟踪文件"放弃"需确认并走 clean）。
- 用 `TpHover.onSecondaryTap` 或 `showMenu`/自定义菜单实现；跟随现有菜单组件风格。

### 5. 工具栏

| 按钮 | 行为 | 来源 |
|------|------|------|
| 分支 ▾ | 打开 `GitBranchSheet` | 保留 |
| 展开/折叠全部 | `toggleExpandAllFolders` | 保留 |
| **放弃 ▾** | 下拉：`放弃所选变更`（`_selectedPath` 非空时可用，确认）／`放弃全部未暂存更改`（`cubit.discardAll()`，确认） | 新增 |
| 拉取 | `cubit.pull()` | 保留 |
| 推送 | `cubit.push()` | 保留 |
| 刷新 | `cubit.refresh()` | 保留 |

去掉旧 Diff 按钮（行单击即 diff，冗余）。

### 6. 打开文件

- **双击行** = 打开文件（`_openFile(change)` → `WorkbenchEditorOpener.openFile(workspaceId, path, fs: widget.workContext.filesystem)`）。给 `TpHover` 增加可选 `onDoubleTap`（标准双击语义）。
- **右键菜单"打开文件"** 同入口。
- `gitOpenFile` l10n 保留（右键菜单 tooltip/label）。

### 7. 放弃语义（安全优先）

- `GitService.discardAll(dir)` → `git restore .`（仅已跟踪未暂存，不删未跟踪）。
- `GitCubit.discardAll()` 包装 + `refresh()`。
- 单文件：保留现有 `discard(dir, change)`（untracked → `clean -f`）。
- 全部放弃/文件夹放弃/未跟踪单文件放弃均需确认对话框（复用 `_confirmDiscard` 模式）。

### 8. 技术改动清单

| 文件 | 改动 |
|------|------|
| `client/lib/services/git/git_changes_visible_rows.dart` | 统一树构建（合并+去重+三态计数）；行宽计算更新；常量调整 |
| `client/lib/widgets/git/git_change_tile.dart` | 复选框 + 状态字母；单击选中+diff、双击打开、右键菜单；移除悬停按钮 |
| `client/lib/widgets/git/git_change_folder_tile.dart` | chevron + 三态复选框；右键菜单 |
| `client/lib/widgets/git/git_changes_tree_list.dart` | 单段树 + 顶层 "Changes" 组头（全选）；选择状态回传 |
| `client/lib/widgets/git/git_source_control_panel.dart` | 工具栏"放弃▾"；选择状态持有；提交框保留 |
| `client/lib/cubits/git_cubit.dart` | 新增 `discardAll` |
| `client/lib/services/git/git_service.dart` | 新增 `discardAll`（restore .） |
| `client/packages/shared_ui/.../tp_hover.dart` | 新增可选 `onDoubleTap` |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 右键菜单、放弃下拉、确认文案；`gitOpenFile` 保留 |
| 测试 | 复选框暂存/三态、单击 diff、双击打开、右键菜单、工具栏放弃、统一树去重 |

### 9. 测试

- 单元（`git_changes_visible_rows_test.dart`）：统一树合并/去重/文件夹三态计数；行宽计算。
- 行级 widget 测试：文件复选框勾选触发 `stage`/`unstage`；文件夹三态渲染；单击→diff 回调、双击→打开文件回调；右键菜单项。
- 面板级测试：工具栏放弃下拉（所选/全部）；顶层全选；部分暂存合并行表现。
- 回归：`git_source_control_panel_generate_test.dart` 保持通过。

### 10. 性能

- 统一树一次遍历完成去重 + 三态计数（O(n)）。
- 复选框交互仅触发 `stage`/`unstage` 单路径命令 + `refresh()`（沿用现有 busy 态与错误 toast）。
- 行宽估算沿用候选采样（`_kContentWidthCandidates`）。
