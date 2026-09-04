# Git 文件项字号统一设计

**日期：** 2026-09-04
**状态：** 已确认

## 背景

Git Graph 的 commit 列表行使用 `TpTextStyles.md`（bodyMedium）渲染文本，但两处文件列表仍使用 `sm`（bodySmall），视觉上明显偏小：

- Git Graph 点击 commit 后右侧详情栏的修改文件列表（`git_graph_detail_pane.dart` 的 `_FileRow`）
- 工作区 diff / Git Compare 面板的文件树（`git_compare_file_tree.dart` 的 `_FolderRow` 与 `_FileRow`）

Source Control 面板的 `GitChangeTile` 已经是 `md`，无需改动。

## 目标

只统一字号，不重排行布局：文件项文本从 `sm` 提升到 `md`，与 commit 列表行及 Source Control 面板一致。

## 改动

| 文件 | 位置 | 改动 |
|------|------|------|
| `client/lib/pages/git_graph/git_graph_detail_pane.dart` | `_FileRow` 文件名 | `sm` → `md` |
| `client/lib/pages/git_graph/git_graph_detail_pane.dart` | `_FileRow` 行高 | `SizedBox(height: 22)` → `28`（容纳 `md` 文本） |
| `client/lib/pages/git_compare/git_compare_file_tree.dart` | `_FolderRow` 文件夹名 | `sm` → `md` |
| `client/lib/pages/git_compare/git_compare_file_tree.dart` | `_FileRow` 文件名 | `sm` → `md` |

## 不做的事

- 状态字母徽章（A/M/D…）保持 `xs`：它是徽章而非正文，同 commit 行 ref chip 中小图标惯例。
- 不改 hover / 选中背景、内边距、`kGitChangesTrailingBadgeWidth` 徽章列宽。
- 不动 Source Control 面板（已是 `md`）。
- 不改 `kGitChangesNodeHeight`（28 已足够容纳 `md` 文本）。

## 验证

1. `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
2. 跑相关 widget 测试（`git_graph_row_tile_test` 等，若 detail pane / compare tree 有测试一并跑）
3. 启动 app，目测 Git Graph 详情栏与 Git Compare 文件树两处字号
