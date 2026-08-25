# 右侧工具栏搜索面板 VSCode 化重构 — 设计

Date: 2026-08-25
Status: Draft (brainstorming, rev 1)
Supersedes: 面板 UI 部分 of [2026-08-13-workspace-content-search-ui-design.md](2026-08-13-workspace-content-search-ui-design.md)

## 背景与前置

- 现有右侧工具栏搜索面板 `client/lib/widgets/right_tools/search_panel.dart`（+ `search_panel_results.dart`）功能完整（正则/大小写/gitignore、include/exclude glob、替换、流式结果、每文件替换），但视觉为 `TpInput` + `FilterChip` 堆叠，与 VSCode 搜索视图差距大。
- 编辑器查找替换栏已沉淀一套 VSCode 风格原语：`client/lib/widgets/find/find_bar_widgets.dart`（`FindField` / `FindToggleButton` / `FindActionButton`）+ `find_bar_palette.dart`（`FindBarPalette`：panelBg #252526、fieldBg #3C3C3C、focus #007FD4、hover #2A2D2E，含浅色变体），SVG 资产齐全（`case_sensitive` / `whole_word` / `regexp` / `replace` / `replace_all` / 保留大小写 AB）。
- 底层逻辑（`ContentSearchCubit` / `ContentSearchRunner` / `ContentReplacer` / `teampilot_search` 引擎）本次**零改动**。

## 目标（视觉 + 交互增强）

1. 表单区重构为 VSCode 搜索视图布局：搜索行（chevron + 内嵌 Aa/ab/.* 切换）、替换行（chevron 展开，内嵌 AB + 替换图标）、`⋯` 详情区（包含/排除文件 + gitignore 开关）。
2. 结果区增强：统计行（N 个结果 · M 个文件）、文件组可折叠、每文件替换按钮改为 hover 显示图标。
3. 配色与编辑器查找栏统一（`FindBarPalette`）。

## 非目标

- cubit / runner / replacer 接口与行为改动
- 搜索历史、跨工作区搜索、undo、差异高亮（维持原 spec 的非目标）
- 泛化 `FindField` 供浮层复用（面板使用专用字段组件，不动编辑器查找栏）

## 表单区布局

```
┌─────────────────────────────────────┐
│ [⌄] ┌──────────────────────────┐    │
│     │ codexPluginManifestPaths │Aa ab .*│  ← 搜索行：chevron 切换替换行；
│     └──────────────────────────┘    │    字段内嵌 Aa/ab/.* 切换
│     ┌──────────────────────────┐    │
│     │ 替换                     │ AB ⤿ │  ← 替换行（默认收起）：AB=保留大小写，
│     └──────────────────────────┘    │    右侧 全部替换 图标（带确认框）
│  ⋯                                   │
│  ┌ ─ ─ ─ '...' 详情区 ─ ─ ─ ─ ─ ┐  │
│    包含的文件                       │  ← 逗号分隔 glob（语义同现状）
│    ┌──────────────────────────┐    │
│    └──────────────────────────┘    │
│    排除的文件                       │
│    ┌──────────────────────────┐    │
│    └──────────────────────────┘    │
│    ☑ 使用 .gitignore 设置          │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  │
└─────────────────────────────────────┘
```

- 默认仅显示搜索行 + `⋯` 按钮；替换行由左侧 chevron 展开/收起（默认收起）。
- 包含文件 / 排除文件 / gitignore 全部收进 `⋯` 详情区；详情区展开时三项纵向排列。
- `⋯` 图标在有激活过滤条件时（include/exclude 非空 或 gitignore 开启）高亮提示（VSCode 同款行为）。
- 所有字段全宽，切换图标内嵌字段右侧（替代 `Wrap(FilterChip)`）。
- 替换行的"全部替换"从独立 `TpButton` 改为行内图标按钮，**保留确认对话框**；与 VSCode 搜索视图一致，替换行仅提供"全部替换"一个操作图标，单条/逐文件替换通过结果区完成（每文件 hover 图标 + 确认框；行级替换沿用 cubit 既有事件，不新增入口）。

## 结果区布局

```
┌─────────────────────────────────────┐
│  12 个结果 · 3 个文件        [rust] │  ← 统计行（小号灰字）+ 后端标签
│ ┌─────────────────────────────────┐ │
│ │ ⌄ lib/foo.dart          5  [⤿] │ │  ← 文件组头：整行点击折叠/展开；
│ │   ───────────────────────────  │ │    hover 显示 全部替换 图标（确认框）
│ │    12│ const foo = bar(1);      │ │  ← 行匹配：行号右对齐 + 命中区间高亮
│ │    48│ foo(codexPluginPaths);   │ │
│ ├─────────────────────────────────┤ │
│ │ › lib/bar.dart          4  [⤿] │ │  ← 折叠态文件组
│ └─────────────────────────────────┘ │
│  已显示前 2000 条结果（结果被截断）  │  ← 截断提示（现状保留）
└─────────────────────────────────────┘
```

- **统计行**：搜索中显示"正在搜索…"；空结果显示居中空态提示（现状保留）；有结果显示"N 个结果 · M 个文件"；右侧保留 backend label（rust / dart-fallback）。
- **文件组折叠**：组头整行可点击展开/收起，chevron 旋转；默认全部展开；替换后该组待处理计数由 cubit 现有状态自动刷新。
- **hover 操作**：每文件"全部替换"从常显 `TpButton` 改为 hover 显示的图标按钮，确认对话框保留。
- **行匹配渲染**：沿用现有高亮逻辑（命中区间主色加粗 + 底色），按 `FindBarPalette` 微调配色。

## 组件结构

| 文件 | 内容 |
|------|------|
| `widgets/right_tools/search_panel.dart`（改造） | 面板骨架 + 本地 UI 状态（替换行/详情区展开、折叠组集合）+ 防抖搜索接线（300ms、结果上限 2000 不变） |
| `widgets/right_tools/search_panel_form.dart`（新增） | `SearchPanelField`（全宽字段 + 内嵌尾随切换图标）、chevron 切换、`⋯` 详情区（包含/排除/gitignore） |
| `widgets/right_tools/search_panel_results.dart`（改造） | 统计行、可折叠文件组、hover 替换图标、行匹配渲染 |

**复用**：`FindBarPalette`、`FindToggleButton`、`FindActionButton`、现有 SVG 资产。`FindField`（定宽、浮层导向）不复用，面板用专用 `SearchPanelField`。

**状态归属**：替换行展开、详情区展开、文件组折叠集合均为面板本地 `setState` 状态，不进 cubit。搜索/替换/选项语义与 `ContentSearchCubit` 现有接口完全一致（`search(TpSearchOptions)` / `replaceAll` / `replaceSingle` / `cancel` / `clear`）。

**打开结果**：沿用 `EditorCubit.openFile(...)` + `selectLines(...)`（`onOpenResult` 可注入供测试）。

## 错误处理

| 情形 | 行为 |
|------|------|
| 非法正则等搜索错误 | 表单下方内联红字（现状保留，l10n） |
| 全局替换 / 每文件替换 | 确认对话框保留（显示替换条数） |
| 结果截断 | 底部截断提示保留 |
| 替换写回失败 | cubit 现有错误态，不标记已替换 |

## l10n

新增字符串进 `client/lib/l10n/app_en.arb` / `app_zh.arb`：结果统计（"N 个结果 · M 个文件"）、"使用 .gitignore 设置"、"正在搜索…"等。已有键（包含的文件/排除的文件/替换等）复用。

## 测试

- 现有 `search_panel` 相关测试回归通过。
- 新增 widget 测试：
  - chevron 显隐替换行；`⋯` 显隐详情区；
  - gitignore / 正则 / 大小写切换反映到传给 cubit 的 `TpSearchOptions`；
  - 统计行计数与"正在搜索…"状态；
  - 文件组折叠/展开；hover 替换按钮触发每文件替换（确认框 → cubit 调用）。
- 收尾：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
