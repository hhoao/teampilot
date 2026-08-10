# 源代码管理变更树：楼梯式缩进（chevron 对齐父复选框 + 子复选框对齐父复选框右缘）

**日期:** 2026-08-10
**状态:** 已实现

## 背景

变更树当前把所有复选框对齐成一列：文件夹行前导 = `depth×16` 缩进 + chevron(16px) + 复选框(18px)，文件行前导 = `depth×16` 缩进 + 复选框(18px)。由于 chevron 宽(16)恰好等于每层缩进（`kGitChangesIndentWidth` = 16），文件夹（depth N）与它内部的文件（depth N+1）的复选框和名称落在同一列 → 文件名和父文件夹名在同一水平位置，看起来像同级，层级感弱。

用户希望：箭头独立占一列（宽 = 复选框宽），使**子复选框左缘精确对齐父复选框右缘**、**子文件夹的 chevron 对齐父复选框（左缘）**，名称逐层嵌套。与 `version-control-sidebar.html` 里已有的"嵌套"原型一致。

实现后用户反馈修正：最初用 `depth×36` 缩进，子文件夹的 chevron 落在父复选框**右缘**、自身复选框又被推后一列，观感不对。最终改为每层只缩进一格（18px），文件行额外 offset 一格 chevron 宽——子文件夹 chevron 恰好落在父复选框那格（左缘齐平），子复选框仍在父复选框右缘。

## 目标

1. 树呈现楼梯式：子复选框（文件或文件夹）左缘 = 父文件夹复选框右缘；子文件夹的 chevron = 父文件夹复选框（左缘对齐）。
2. 每层缩进一格（18px = chevron 列 = 复选框列），同一深度上文件夹与文件的复选框、名称对齐；名称每层右移一格。
3. chevron 字形（16px）在其 18px 列内左对齐，与父复选框左缘齐平，避免图标与复选框过挤。

## 非目标

- 不改树构建 / 选择模型 / 提交语义（仅布局常量）。
- 不改变 "Changes" 组头（独立分组头，保持现状）。

## 设计

### 1. 常量（`git_changes_visible_rows.dart`）

| 常量 | 值 | 说明 |
|------|-----|------|
| `kGitChangesIndentWidth` | 18 | 每层缩进一格 = chevron 列宽 |
| `kGitChangesChevronWidth` | 18（= `kGitChangesCheckboxWidth`） | chevron 列宽与复选框列宽一致，形成统一网格 |

### 2. 行前导

- **文件夹行**（`git_change_folder_tile.dart`）：padding = `depth × 18 + base`；行内 `[chevron 列 18][复选框 18][图标][名称]`。chevron 列内用 `Align(centerLeft)` 把 16px 字形左对齐到列左缘。
- **文件行**（`git_change_tile.dart`）：padding = `depth × 18 + 18 + base`（多 offset 一格 chevron 宽）；行内 `[复选框 18][图标][名称]`。

### 3. 几何验证（padding base = `kGitChangesNodePaddingLeft(6) + kGitChangesRowHorizontalPadding(2)` = 8）

- 文件夹 depth N：padding = `18N+8`，chevron `[18N+8, 18N+26]`，复选框 `[18N+26, 18N+44]`。
- 文件 depth N：padding = `18N+26`，复选框 `[18N+26, 18N+44]` —— 与同深度文件夹的复选框**同列**。
- 子文件夹 depth N+1：padding = `18(N+1)+8` = `18N+26`，其 chevron `[18N+26, 18N+44]` = 父文件夹复选框 → **左缘齐平** ✓（配合 Align，字形左缘 = 父复选框左缘）。
- 子文件 depth N+1：padding = `18N+44`，其复选框左缘 = `18N+44` = 父文件夹复选框**右缘** ✓。
- 名称：每层右移一格（18px）；同深度文件夹与文件名称对齐。

### 4. 行宽计算（`git_changes_visible_rows.dart`）

- `gitChangesMinContentWidth` 文件分支：`row.depth × kGitChangesIndentWidth` 后再加 `kGitChangesChevronWidth`（文件行的额外 offset）。
- `_rowWidthEstimate` depth 系数 `2.0`（缩进回到 18px）。

### 5. 副作用（可接受）

- 顶层文件与顶层文件夹（同 depth 0）的复选框、名称对齐（文件夹多一个 chevron 列，文件多一格缩进，互相抵消）。
- 每层只占 18px，横向占用比最初 36px 方案更省。

## 技术改动清单

| 文件 | 改动 |
|------|------|
| `client/lib/services/git/git_changes_visible_rows.dart` | `kGitChangesIndentWidth`=18；`kGitChangesChevronWidth`=18（=复选框宽）；文件分支行宽加 chevron offset；估算系数 2.0 |
| `client/lib/widgets/git/git_change_tile.dart` | 文件行 padding 加 `kGitChangesChevronWidth` |
| `client/lib/widgets/git/git_change_folder_tile.dart` | chevron 列 `kGitChangesChevronWidth`，字形 `Align(centerLeft)` 左对齐 |
| `client/test/services/git/git_changes_visible_rows_test.dart` | 宽度差断言 = `kGitChangesTrailingBadgeWidth`（22） |

## 测试

- 现有 `git_changes_tree_list_test.dart` / `git_source_control_panel_*_test.dart` 无几何断言，应保持通过。
- 验证方式：`flutter analyze` → `flutter test --exclude-tags integration` → 实际跑应用目视右栏变更树。
