# 统一搜索框为胶囊样式 — 设计

日期：2026-11-06
状态：待评审

## 背景与目标

应用内搜索/筛选输入框风格分散：圆角有 2/4/6/8/9/12 等多种，搜索图标有的有、有的没有，清空按钮与边框也各写各的。聊天查找栏目前是"方盒子里套一个带边框的小输入框"，与目标样式差异最大。

目标：在不改变任何功能和行为的前提下，把所有搜索类输入框统一为参考图的胶囊样式——一条圆角搜索栏，左侧搜索图标，输入区无内层边框，右侧保留各页面已有的计数、上下箭头、关闭/清空等控件。

参考图：

- 胶囊外形，浅色白底 + 淡边框 + 柔和阴影。
- 左：搜索图标 + 占位文字。
- 右：`n/N` 计数、上下箭头、关闭。
- 分组之间有 1px 细分隔线。

## 非目标

- 不新增或删除任何按钮、快捷键、回调、状态。
- 不改变搜索算法、debounce、结果导航、清空逻辑、焦点行为。
- 不修改全局 `InputDecorationTheme`（会波及所有表单输入框）。
- 不引入命令面板/快速打开等新 UI。

## 视觉规范

| 项 | 规范 |
| --- | --- |
| 形状 | 胶囊，圆角 = 高度 / 2（实现用 `BorderRadius.circular(999)`） |
| 高度 | 查找栏沿用 `FindField.kHeight`（34）；内嵌筛选框沿用各控件现有高度（主题 input 32、工作区搜索 44、用量 40 等），仅改圆角 |
| 填充 | 浮层查找栏：浅色主题白色，深色主题沿用现有浮层深色；内嵌筛选框沿用现有填充（client 的 `workspaceCard` 即 `ColorScheme.surfaceContainer`） |
| 边框 | 浅色 `outlineVariant`（约 0.7 透明度）；聚焦态 `primary` 1.5px |
| 阴影 | 仅浮层查找栏有柔和阴影；内嵌筛选框无阴影 |
| 搜索图标 | 左侧统一 `Icons.search_rounded`，muted 色，尺寸 `context.tpIconSizes.md`；原本没有图标的搜索框补上 |
| 内层输入框 | 移除独立背景与边框，整条胶囊即输入框 |
| 分隔线 | 浮层查找栏在计数/导航/关闭分组之间加 1px 竖线（`FindBarDivider`） |
| 展开态 | 查找栏出现结果列表或替换行时，外层圆角退化为 16 的卡片；收起时恢复胶囊 |
| 清空按钮 | 保持现状：原本有的保留，原本没有的不新增 |
| 文本/提示色 | 沿用现有 `FindBarPalette` 与主题 `onSurfaceVariant`，不新增颜色体系 |

## 组件设计

### 1. 共享胶囊装饰助手（shared_ui）

新增 `tpSearchPillDecoration(BuildContext context, {...})`，位于
`client/packages/shared_ui/lib/src/components/input/tp_search_pill.dart`，并从 `shared_ui.dart` 导出。

- 返回标准胶囊 `InputDecoration`：stadium 圆角、填充、边框、聚焦边框、提示色、可选前置搜索图标、可选前置/后置控件。
- 内嵌搜索框只替换 `decoration`，controller、`onChanged`、清空按钮、chips、布局均不动。
- `TpCatalogDiscoveryHeader` 与 `TpSelectSearchField` 在 shared_ui 内直接改用该助手。
- `TpInput` 增加可选的 `decoration` 覆盖参数，供 Git 提交搜索这种"输入框内嵌选择器"的场景传入胶囊装饰。

shared_ui 是 git 子模块：样式改动在子模块提交，再更新主仓子模块指针（仓库已有先例）。

### 2. 查找栏公共基元（client）

`client/lib/widgets/find/find_bar_widgets.dart`：

- `FindBarPanel`
  - 新增 `borderRadius` 参数，默认胶囊（999）。
  - 新增可选 `focusNode`：聚焦时外边框使用 `focusBorder`（仅胶囊态启用）。
  - 阴影调整为更柔和的浮层阴影。
- `FindField`
  - 移除内层 `Container` 的填充与边框。
  - 左侧增加搜索图标与内边距。
  - 新增 `standalone` 模式：不在 `FindBarPanel` 内时（右侧 Search 面板）自身渲染胶囊边框/填充。
  - 新增可选 `trailing` 槽位（位于 toggles 之前），供终端查找栏显示 "No results / regex" 状态文字。
  - `width` 语义不变。
- 新增 `FindBarDivider`：1px 竖线，高度约 18，颜色 `panelBorder`。

`client/lib/widgets/find/find_bar_palette.dart`：

- 浅色：`panelBg` 改为白色，`panelBorder` 更淡（约 `0xFFE3E3E3`），`shadow` 降低透明度。
- 深色：保持现有值，`panelBorder` 略调淡。
- 分隔线复用 `panelBorder`，不新增 token。

### 3. 各查找栏

| 文件 | 改动 |
| --- | --- |
| `client/lib/pages/chat/chat_find_bar.dart` | 输入框改为 `Expanded`（去掉固定 300）；计数与上下箭头、关闭之间加分隔线；`hits` 非空时 `FindBarPanel` 圆角传 16，否则胶囊 |
| `client/lib/widgets/workbench/code_editor_find_panel.dart` | `FindBarPanel` 的 `focusNode` 传查找焦点；`showReplace` 时圆角传 16；加分组分隔线；其余布局与宽度不变 |
| `client/lib/widgets/workbench/markdown_preview_find_bar.dart` | 传 `focusNode`；单行始终胶囊；加分组分隔线 |
| `client/lib/widgets/terminal_find_bar.dart` | 改用 `FindBarPanel` + `FindField`（`trailing` 显示原状态文字）替换自绘 `Material`/`TextField`；保留搜索、步进、关闭与快捷键逻辑 |
| `client/lib/widgets/right_tools/search_panel.dart` | `FindField` 使用 `standalone` 胶囊；查询/替换字段、搜索中取消按钮逻辑不变 |
| `client/lib/widgets/right_tools/search_panel_form.dart` | 包含/排除字段使用 `standalone` 胶囊 |

### 4. 内嵌筛选/搜索框

以下位置仅替换 `InputDecoration` 为 `tpSearchPillDecoration`（或等价胶囊），保留 controller、回调、清空按钮、chips 与布局：

- `client/lib/pages/home_workspace/workspace/workspace_search_widgets.dart`（`WorkspaceSearchField`）
- `client/lib/pages/home_workspace/workspace/workspace_search_content_section.dart`
- `client/lib/widgets/right_tools/file_tree_panel.dart`（`_FileTreeFilterField`）
- `client/lib/pages/home_workspace/workspaces_tab.dart`（`WorkspacesFilterField`，手写 `AnimatedContainer` 改为胶囊圆角，保留焦点动画）
- `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_discovery_header.dart`
- `client/lib/pages/team_hub/team_hub_body.dart`
- `client/lib/pages/expert_hub/expert_hub_body.dart`
- `client/lib/pages/team_hub/team_landing_picker_catalog_body.dart`
- `client/lib/pages/git_graph/git_graph_toolbar.dart`（提交搜索，保留内嵌模式选择器）
- `client/lib/pages/git_graph/git_graph_filterable_action_menu_panel.dart`
- `client/lib/pages/system/log_viewer_toolbar.dart`
- `client/lib/pages/usage/widgets/usage_table_toolbar.dart`
- `client/lib/pages/config/shortcuts_config_section.dart`
- `client/lib/pages/vault/vault_page.dart`
- `client/lib/widgets/app_provider/app_provider_list_panel.dart`
- `client/packages/shared_ui/lib/src/components/select/tp_select_search_field.dart`
- `client/packages/shared_ui/lib/src/components/file_selection/ui/widgets/tp_full_disk_search_dialog.dart`

## 展开态细节

- 聊天查找栏：仅在 `total > 0`（结果列表出现）时退化为 16 圆角卡片；结果行的内边距、选中态、高亮不变。
- 编辑器查找栏：仅在替换行展开时退化为 16 圆角卡片；`preferredSize` 高度计算不变。
- Markdown 查找栏、终端查找栏：始终胶囊。
- 右侧 Search 面板：不在浮层内，每个输入框自身是胶囊，面板外框不变。

## 行为保持不变（验收点）

- 所有搜索仍按原有 controller / 回调触发，debounce 时长不变。
- 聊天/编辑器查找的 `n/N`、无匹配文案、上下步进、高亮与结果列表展开逻辑不变。
- Aa / ab / .* / AB / 替换 等开关位置与行为不变。
- 终端查找的 Ctrl+Shift+F、F3、Shift+F3、Esc 与状态文字不变。
- 原本没有清空按钮的字段不新增清空按钮。
- 窄屏/移动端布局不因圆角变化而溢出。

## 测试与验证

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- 针对性测试（通过 `dart run tool/run_tests.dart`）：
  - 聊天查找栏与查找基元相关测试
  - 编辑器 / Markdown 查找测试
  - 工作区搜索对话框与内容搜索测试
  - 文件树筛选测试
  - 技能/插件/MCP 目录头测试
  - 终端查找测试
- 人工检查：浅色/深色主题下逐一打开上述搜索框；重点检查聊天查找结果列表、编辑器替换行、终端查找状态文字、Git 提交搜索内嵌选择器、窄屏布局。

## 风险与缓解

- **shared_ui 子模块**：改动需在子模块提交并更新主仓指针；范围限制在搜索装饰助手与既有两个目录组件。
- **胶囊裁切**：内容需保留左右内边距，避免贴住半圆端。
- **内嵌选择器**：Git 提交搜索的右侧模式选择器可能被胶囊圆角裁切，需人工确认，必要时仅对该字段使用较大但仍为胶囊的半径。
- **展开态**：结果列表/替换行出现时退化为 16 圆角卡片，避免长内容被两端切成半圆。
