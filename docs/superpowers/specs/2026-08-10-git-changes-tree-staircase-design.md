# 源代码管理变更树：楼梯式缩进（箭头独立列 + 子复选框对齐父复选框右缘）

**日期:** 2026-08-10
**状态:** 已确认设计（待实现）

## 背景

变更树当前把所有复选框对齐成一列：文件夹行前导 = `depth×16` 缩进 + chevron(16px) + 复选框(18px)，文件行前导 = `depth×16` 缩进 + 复选框(18px)。由于 chevron 宽(16)恰好等于每层缩进（`kGitChangesIndentWidth` = 16），文件夹（depth N）与它内部的文件（depth N+1）的复选框和名称落在同一列 → 文件名和父文件夹名在同一水平位置，看起来像同级，层级感弱。

用户希望：箭头独立占一列（宽 = 复选框宽），每层缩进 = 箭头 + 复选框，使**子复选框左缘精确对齐父复选框右缘**，名称逐层嵌套。与 `version-control-sidebar.html` 里已有的"嵌套"原型一致。

## 目标

1. 树呈现楼梯式：子文件复选框左缘 = 父文件夹复选框右缘；文件名每层右移一格。
2. 箭头列宽 = 复选框宽（18px），形成统一网格。

## 非目标

- 不改树构建 / 选择模型 / 提交语义（仅布局常量）。
- 不改变 "Changes" 组头（独立分组头，保持现状）。
- 不改文件行结构（它本就是"缩进 + 复选框"）。

## 设计

### 1. 常量（`git_changes_visible_rows.dart`）

| 常量 | 现值 | 新值 | 说明 |
|------|------|------|------|
| `kGitChangesIndentWidth` | 16 | 36 | 每层缩进 = 箭头列 18 + 复选框 18 |
| `kGitChangesChevronWidth` | （无，硬编码 16） | 18 | 新增，= `kGitChangesCheckboxWidth` |

### 2. 文件夹行（`git_change_folder_tile.dart`）

chevron 的 `SizedBox` 宽 `16` → `kGitChangesChevronWidth`（18）。

### 3. 行宽计算（`git_changes_visible_rows.dart`）

- `gitChangesMinContentWidth` 文件夹 `leading`：`kGitChangesIndentWidth + kGitChangesCheckboxWidth + 16 + 6` → `kGitChangesChevronWidth + kGitChangesCheckboxWidth + 16 + 6`（原 16 是 chevron，改引新常量）。
- `_rowWidthEstimate` depth 系数 `2.0` → `4.0`（缩进变大，候选采样估计跟紧，避免横向最小宽度算小）。

### 4. 几何验证（padding base = 8）

- 文件夹 depth N：复选框 `[36N+26, 36N+44]`，名称在 `36N+70`。
- 子文件 depth N+1：复选框左缘 = `36(N+1)+8` = `36N+44` = 父复选框右缘 ✓；名称在 `36N+88`，比父名右移 18px ✓。

### 5. 副作用（可接受）

- 顶层文件与顶层文件夹（同 depth 0）仍不同列（文件夹带箭头），现状语义不变。
- 深层路径横向占用变大；面板已有横向滚动，`gitChangesMinContentWidth` 同步更新。

## 技术改动清单

| 文件 | 改动 |
|------|------|
| `client/lib/services/git/git_changes_visible_rows.dart` | `kGitChangesIndentWidth`→36；新增 `kGitChangesChevronWidth`=18；行宽/估算更新 |
| `client/lib/widgets/git/git_change_folder_tile.dart` | chevron 宽 16→`kGitChangesChevronWidth` |

## 测试

- 现有 `git_changes_tree_list_test.dart` / `git_source_control_panel_*_test.dart` 无几何断言，应保持通过。
- 验证方式：`flutter analyze` → `flutter test --exclude-tags integration` → 实际跑应用目视右栏变更树。
