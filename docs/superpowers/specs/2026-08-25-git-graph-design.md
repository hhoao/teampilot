# Git Graph（浮动工作区）设计文档

日期：2026-08-25
状态：已确认（用户批准设计后成文）

## 背景

参考 [asispts/neo-git-graph](https://github.com/asispts/neo-git-graph)（VS Code Git Graph 的 MIT fork），在 TeamPilot 内置 IDE 中提供提交拓扑可视化与历史操作能力。

现状：TeamPilot 已有完整的 git CLI 执行层——`GitCommandRunner`（native / WSL / SSH 三后端）、`GitService`（status/diff/commit/push/pull/checkout/createBranch）、`GitRepoStore`（每仓库 LRU 托管 `GitCubit`）以及 `DiffViewer`。缺失的是：任何形式的 `git log` 历史查询（仅有 `headCommitMessage()`）、commit 模型、图渲染 UI。

## 目标

1. **可视化**：单图中展示所有分支的提交 DAG、分支/标签/HEAD 装饰、未提交变更节点。
2. **详情**：点击提交查看元数据与变更文件列表，面板内直接查看 per-file diff。
3. **操作**：分支（创建/checkout/重命名/删除/合并）、标签（创建/删除/推送）、提交级（checkout/cherry-pick/revert/reset soft·mixed·hard）、stash（list/pop/apply/drop）、远端（fetch/pull/push）。
4. **搜索**：按消息（`--grep -i`）、作者（`--author`）、hash 前缀（客户端过滤）过滤历史。
5. **多仓库**：每个 repoRoot 一个浮动标签页，可同时打开多个。
6. **三后端透明**：local / WSL / SSH 经现有 `GitCommandRunner` 自动支持，无特殊分支逻辑。

## 非目标（v1）

- 头像抓取（上游 neo-git-graph 已弃用）。
- 图配色设置页（跟随 Tp 主题派生调色板；angular 线型仅预留策略接口）。
- blame 视图。
- 提交编辑（amend/reword 已由 Source Control 面板覆盖 amend 场景）。

## 方案选型

采用 **方案 A：原生 Flutter 渲染 + 解析 `git log --graph` ASCII 输出**。

- 拓扑正确性（排序、lane 走向、octopus merge 边界情况）由 git 自身的 `--graph` 输出保证，Dart 侧只做"ASCII 列 → 结构化行模型"的映射。
- 渲染用 `CustomPainter` 画节点圆点、直通竖线、分叉/合并三次贝塞尔曲线，零新依赖，与 Tp 主题一致。
- 否决的替代方案：WebView + JS 图库（IPC 开销大、主题割裂、Android 重量级）；自研 lane 分配算法（拓扑边界情况多，git 已解决这些问题）。

## 架构总览

```
Source Control 面板头部 [Graph] 按钮
  → WorkbenchCubit.openFloating(WorkbenchTabId.gitGraph(repoRoot))
  → FloatingWorkspacePanel（拖拽/缩放/最大化，TpKeepAliveLayer 保活）
      → GitGraphFloatingSurface.build(tab)
          → GitGraphPane(workspaceId, repoRoot)
              └── GitRepoStore 托管的 GitGraphCubit（key 同 GitCubit，LRU≤8）
                    ├── 左：提交图列表（虚拟化 ListView + 每行 CustomPainter 片元）
                    └── 右：详情栏（提交信息 / 文件列表 / 内嵌 DiffViewer）
```

新增代码集中四处：

| 层 | 路径 | 内容 |
|----|------|------|
| 服务 | `client/lib/services/git/git_history_service.dart` | 只读历史查询 |
| 服务 | `client/lib/services/git/git_history_actions.dart` | 历史写操作 |
| 解析器 | `client/lib/services/git/parser/` | `git_graph_parser.dart`、`git_decoration_parser.dart` |
| 模型 | `client/lib/models/git_graph.dart` | 纯数据类型 |
| 状态 | `client/lib/cubits/git_graph_cubit.dart` | `GitGraphState` + cubit |
| UI | `client/lib/pages/git_graph/` | pane、行片元、详情栏、菜单 |
| 接入 | `services/floating_workspace/surfaces/git_graph_floating_surface.dart` 等 | surface 注册 |

分层遵循 `docs/CODE_QUALITY.md`：UI 无 IO、状态 flutter_bloc、服务层持有命令执行。

## 数据层

### 拓扑查询（核心）

```sh
git log --all --date-order --max-count=<N> --skip=<M> \
  --pretty=format:%x1e%H%x1f%P%x1f%an%x1f%at%x1f%d%x1f%s --graph
```

- 每行以 `\x1e`（record separator）切分：之前是 `--graph` ASCII 前缀（如 `* | \|/`），之后是 `\x1f` 分隔的字段：hash / parents / author name / author timestamp / decorations / subject。
- `--graph` 默认启用 topo-order，叠加 `--date-order` 保证同时序内按时间展示（同 VS Code Git Graph）。
- **分页**：首屏 `--max-count=300`，滚动到底追加 `--skip=已加载数 --max-count=100`。
- **装饰解析**：`%d` 形如 `(HEAD -> main, origin/main, tag: v1.0)` → `[GitRefDecoration]`（区分 HEAD、本地分支、远程分支、tag）。

### 行模型

解析器把每行 ASCII 映射为：

```dart
class GitCommitRow {
  final String hash;
  final List<String> parents;
  final String authorName;
  final DateTime authorDate;
  final String subject;
  final List<GitRefDecoration> refs;
  final GitGraphNode node;        // 节点所在 lane 序号
  final List<GitGraphEdge> edges; // 本行的直通竖线 + 分叉/合并曲线端点规格
}
```

### 其余查询

| 查询 | 实现 |
|------|------|
| 单提交元数据 | `git show -s --pretty=format:... <hash>` |
| 变更文件列表 | `git diff-tree --no-commit-id --name-status -r <hash>`（root commit 用 `--root`） |
| per-file diff 文本 | `git diff <parent>..<hash> -- <path>`；root commit 对空树 diff |
| 未提交变更节点 | status 非干净时置顶插入合成行；diff 复用 `GitService.diffAgainstHead()` |
| 分支/标签清单 | `git for-each-ref --format=...`（refs/heads、refs/remotes、refs/tags），含当前 HEAD 解析 |
| stash 清单 | `git stash list --format=...` |

### 搜索

| 模式 | 实现 |
|------|------|
| 消息 | 追加 `--grep=<q> -i` |
| 作者 | 追加 `--author=<q>`（git 默认子串不区分大小写匹配） |
| hash 前缀 | 对已加载结果客户端过滤；无结果时提示继续加载 |

## 状态层

新 `GitGraphCubit`（`cubits/git_graph_cubit.dart`），由 `GitRepoStore` 以与 `GitCubit` 相同的 key 托管（LRU≤8、轮询刷新复用现有生命周期）。

```dart
class GitGraphState {
  final List<GitCommitRow> rows;
  final bool hasMore, loadingMore;
  final String? selectedHash;
  final GitCommitDetail? commitDetail;   // 元数据 + 文件列表 + 当前 diff
  final List<GitBranchInfo> branches;
  final List<GitTagInfo> tags;
  final String currentBranch;
  final List<GitStashEntry> stashList;
  final bool uncommittedDirty;
  final String searchQuery;
  final GitSearchMode searchMode;        // message / author / hash
  final String? errorMessage;
}
```

约定：

- 所有写操作走统一 `_mutate(() async { ... })` 包装：执行 → 重刷图 + status → 失败写入 `errorMessage` 并经 `AppLogger` 记录，绝不抛出到 UI 层崩溃。
- 选中提交变化时懒加载 commitDetail 与文件 diff（避免点击风暴拉全量 diff）。
- 刷新采用与 `GitCubit.refresh()` 相同的 coalescing（合并并发请求 + trailing 补跑）。

## UI 层

### 接入点

- `WorkbenchTabKind` 新增 `gitGraph`，仅浮动 strip；payload = repoRoot 绝对路径；`allowMultipleTabs = true`。
- 注册链路（对齐现有五个 surface）：`app_shell.dart` 构造 `GitGraphFloatingSurface` 注入 `FloatingSurfaceRegistry.withDefaults` → `workbench_tab.dart` 的 `surfaceIdFor` 映射 → `floating_workspace_tab_bar.dart` 图标映射 → `workbench_shell_run_sync.dart` 的 id 解析 → `close_floating_tab.dart` 关闭路径。
- 入口按钮：`GitSourceControlPanel._Header` 增加 `[Graph]`；并注册命令（`registerFloatingWorkspaceCommands` 同款）支持命令面板唤起。

### `GitGraphPane` 布局

```
┌──────────────────────────────────────────────────────────┐
│ 工具条: [分支▾ 全部|当前] [Fetch][Pull][Push] [Stash▾]    │
│         [搜索框: 消息/作者/hash] [刷新]                    │
├───────────────────────────────┬──────────────────────────┤
│ 图列表 (虚拟化 ListView, 行高~26px) │ 详情栏                  │
│ ◉─● merge commit  main tag:v1   │ subject / author / date  │
│ │ ● 分叉提交        origin/x    │ hash [复制]              │
│ ●─┘ 初始提交       dev          │ ─ 变更文件列表             │
│ ◎ 未提交变更 (脏时置顶)           │ └ 点击→内嵌 DiffViewer    │
│ [滚动到底自动加载更多]             │                          │
├───────────────────────────────┴──────────────────────────┤
│ 状态栏: 当前分支 · ahead/behind · 错误提示                   │
└──────────────────────────────────────────────────────────┘
```

- **图形渲染**：固定行高的行片元各自持一个轻量 `CustomPainter`；lane 颜色取 `TpTheme` 派生的循环调色板（相邻 lane 颜色不相邻重复）。绘制策略抽象为 `GitGraphLanePainter` 接口，v1 提供 rounded 实现，angular 后续可插拔。
- **详情栏**：左右可拖分隔条；文件点击后在栏内切换到 `DiffViewer`（复用 `widgets/diff/diff_viewer.dart` + `unified_diff_parser.dart`），带返回文件列表入口。
- **l10n**：全部用户可见文案进 `app_en.arb` / `app_zh.arb`。

## 操作矩阵

| 类别 | 操作 | 危险级别 |
|------|------|---------|
| 分支 | 创建(指向选中提交)、checkout、重命名、删除(-d/-D)、合并(到当前分支) | 删除需确认 |
| 标签 | 创建(轻量/附注)、删除、推送指定 tag | 删除需确认 |
| 提交 | checkout(detach HEAD)、cherry-pick、revert、reset(soft/mixed/hard) | hard 需键入分支名确认 |
| Stash | list、pop、apply、drop | drop 需确认 |
| 远端 | fetch、pull(当前分支)、push、push 指定 tag | — |
| 其他 | copy hash、copy subject、"在此创建分支" | — |

- 写操作全部落在 `git_history_actions.dart`（branch/tag/stash/merge/cherry-pick/revert/reset/checkout-commit/fetch/push-tag）；push/pull 沿用 `GitService` 现有方法。
- 危险操作统一走 Tp 风格确认对话框；reset --hard 额外要求输入当前分支名方可执行。

## 错误处理

| 场景 | 处理 |
|------|------|
| 目录非 git 仓库 | 空态引导页（提示从 Source Control 打开有效仓库） |
| SSH/WSL runner 不可用 | 复用 runner 探测缓存与既有错误文案 |
| 单条命令失败 | 状态栏 + l10n snackbar 展示 stderr 摘要；`AppLogger` 记录全文；UI 不崩溃 |
| 合并/reset 冲突 | 检测 exit code + stderr 关键字，提示去 Source Control 面板解决冲突（冲突 UI 不在本期范围） |

## 测试策略

1. **解析器单测**：直线历史、分叉、多次合并、octopus merge、decorations（HEAD/remote/tag 组合）、分页边界样本的快照测试。
2. **服务层**：构造注入 fake `GitCommandRunner`（沿用现有测试缝），断言参数拼接（分页 skip/max-count、搜索 flags）与结果映射。
3. **Cubit 测试**：选中态懒加载、搜索模式切换、`_mutate` 错误路径（errorMessage 置位且 rows 不丢）。
4. **Widget 测试**：行渲染（节点/lane 数）、右键菜单触发对应 cubit 方法、危险操作确认框拦截（取消则不调用）、加载更多触发条件。
5. 涉及 `AppStorage` 的测试使用 `setUpTestAppStorage()` / `tearDownTestAppStorage()`（`client/test/support/post_frame_test_harness.dart`）。

## 实施分期（实现计划顺序）

1. **数据层**：模型、`git_graph_parser` / `git_decoration_parser`、`GitHistoryService`、cubit（含全部单测）。
2. **可视化接入**：FloatingSurface 注册链路、`GitGraphPane` 图列表 + lane painter、详情栏 + 内嵌 diff、入口按钮与命令。
3. **分支/标签/远端**：操作矩阵前两类 + fetch/pull/push + 确认对话框组件。
4. **提交级/stash/搜索**：cherry-pick/revert/reset、stash 全套、三种搜索模式。

## 涉及文件清单

新增：

- `client/lib/models/git_graph.dart`
- `client/lib/services/git/git_history_service.dart`
- `client/lib/services/git/git_history_actions.dart`
- `client/lib/services/git/parser/git_graph_parser.dart`
- `client/lib/services/git/parser/git_decoration_parser.dart`
- `client/lib/cubits/git_graph_cubit.dart`
- `client/lib/services/floating_workspace/surfaces/git_graph_floating_surface.dart`
- `client/lib/pages/git_graph/`（pane、行片元、详情栏、上下文菜单、确认对话框）

修改：

- `client/lib/services/workspace/git_repo_store.dart`（托管 graph cubit）
- `client/lib/cubits/workbench/workbench_tab.dart`（新 tab kind）
- `client/lib/app/app_shell.dart`、`main.dart`（装配）
- `client/lib/widgets/git/git_source_control_panel.dart`（入口按钮）
- `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart`、`widgets/workbench/workbench_shell_run_sync.dart`、`services/floating_workspace/close_floating_tab.dart`（kind 映射）
- `client/lib/l10n/app_en.arb`、`app_zh.arb`
