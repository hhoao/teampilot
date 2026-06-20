# Worktree 侧栏分组 — 设计文档

- 日期：2026-06-20
- 状态：设计已确认，待写实现计划
- 参考实现：orca（`/home/hhoa/git/opensource/orca`，`src/main/git/worktree.ts`、`src/shared/types.ts` 的 `GitWorktreeInfo` / `Worktree`）

## 1. 目标与动机

在项目工作区左侧会话栏（`WorkspaceSidebar`）按 **git worktree** 对会话分组，并支持在侧栏里**创建/删除** worktree。让用户能用"每个分支一个工作树、各跑一个 agent"的方式并行开发，并在一个界面里统一管理。

核心借鉴 orca 的三点精华，但**复用 TeamPilot 已有的 `Workspace` 容器层**，把 worktree 退化为 workspace 内的分组维度，避免大重构：

1. **路径派生身份** —— worktree 不持久化为独立实体，靠 `git worktree list` + 会话 `primaryPath` 自动匹配分组。
2. **git 实时列表** —— 列表/状态来自 git，不靠 app 自己维护的镜像。
3. **每会话独立工作目录** —— 会话的 `primaryPath` 可以是某个 worktree 目录，而非永远等于仓库根。

### 与 orca 的关键差异

orca 里 **worktree 就等于 workspace**，删 worktree = 删整个工作区。TeamPilot 里会话的对话记录存在 `workspace/projects/{projectId}/sessions/{sessionId}/`，**和 worktree 的 git 工作目录是两回事**，`git worktree remove` 物理上不碰会话数据。因此"删 worktree 要不要删会话"是独立的产品决策（见 §6）。

## 2. 范围

### v1 包含
- 解析 `git worktree list`，把会话按"路径前缀最长匹配"归到所属 worktree 分组。
- 侧栏：渐进式分组显示（只有 main 时扁平、≥2 时分组）、可折叠分组头、分组内复用现有会话 tile/排序/搜索/拖拽。
- 创建 worktree（新建分支 **和** 挂载已有分支）、删除 worktree（默认不删会话，可选连带）。
- 在某个 worktree 分组里"新建会话"，会话 `primaryPath` = 该 worktree 目录。
- 文件树 + 源代码管理面板跟随"单一当前 worktree"（§7）。
- desktop-local（与现有 `GitService` 一致），SSH/远程不在 v1。

### v1 推迟（YAGNI）
git 状态徽章 / ahead-behind、worktree 置顶 / 归档、分组拖拽排序、sparse worktree、SSH/远程 worktree、`Cmd+J` 快速跳转 palette、每 worktree 未读角标、自动重命名分支、面包屑下拉快速切换。

## 3. 已确认的设计决策

| 决策点 | 结论 |
|---|---|
| worktree 含义 | git 多工作树 + 在侧栏里管理 |
| 会话归属方式 | 路径派生（`primaryPath` 前缀最长匹配 worktree path），不存额外字段 |
| 侧栏结构 | 会话为主 + worktree 分组头（复用 `Workspace` 容器，不做 orca 的 worktree-as-container） |
| 渐进显示 | 只有 main worktree 时扁平列表；≥2 时显示分组头。"+ 新建 worktree"入口始终显示 |
| 删除策略 | 默认只删 git worktree、保留会话；删除对话框提供可选"同时删除这 N 个会话" |
| worktrees 根目录 | App 管理目录 `<teampilotRoot>/worktrees/<repo>/<branch>`，可配置 |
| 分支来源 | 新建分支（`-b`）+ 挂载已有分支（`add <path> <existing>`），二者都支持 |
| 文件树 / 源代码管理 | 单一"当前 worktree"，终端/文件树/git 三者同步；双入口切换 + 分支面包屑 |
| 适用范围 | 任何 `primaryPath` 是 git 仓库的 workspace（团队/个人都适用）；非 git 仓库无分组、保持今天的扁平列表 |

## 4. 数据模型与服务

### 4.1 模型 `GitWorktree`
新增 `client/lib/models/git_worktree.dart`，对应 orca 的 `GitWorktreeInfo`：

```
class GitWorktree {
  final String path;          // 工作树绝对路径（归一化）
  final String branch;        // refs/heads/... 或空（detached）
  final String head;          // commit oid
  final bool isBare;
  final bool isMainWorktree;  // git worktree list 的第一条
  bool get isDetached => branch.isEmpty;
  String get shortBranch;     // 去掉 refs/heads/ 前缀；detached 显示短 oid
}
```

不持久化；每次从 git 读出。

### 4.2 服务 `GitWorktreeService`
新增 `client/lib/services/git/git_worktree_service.dart`，与 `GitService` 同构（构造注入 `ProcessRunner`，便于测试；`debugOverrideFactory` 测试种子；`--no-optional-locks` / `core.quotePath=false` 全局 flag 复用）。方法：

- `Future<List<GitWorktree>> list(String repoPath)`
  解析 `git worktree list --porcelain -z`（解析器照搬 orca `parseWorktreeList` 的 porcelain 块解析 + `-z` NUL 分隔；对 git <2.36 不支持 `-z` 的情况回退到非 `-z`）。非 git 仓库 / 路径不存在 → 返回空列表。
- `Future<void> add(String repoPath, String worktreePath, {required String branch, String? baseRef, bool existingBranch = false})`
  - 新建分支：`git worktree add --no-track -b <branch> <worktreePath> [<baseRef>]`（`--no-track` 照搬 orca，避免未发布分支被误报 behind）。
  - 挂载已有分支：`git worktree add <worktreePath> <branch>`。
- `Future<void> remove(String repoPath, String worktreePath, {bool force = false, bool deleteBranch = false})`
  `git worktree remove [--force] <worktreePath>`；`deleteBranch` 时随后 `git branch -d <branch>`（安全删，不用 `-D`，保住未合并提交；删不掉就保留并提示）。

v1 不做 orca 的 sparse / base-ref 刷新 / lineage 等高级逻辑。

### 4.3 分组纯函数
新增 `client/lib/utils/session_worktree_grouping.dart`，纯函数、可测：

```
List<WorktreeGroup> groupSessionsByWorktree({
  required List<GitWorktree> worktrees,
  required List<AppSession> sessions,
});
```

规则：
- 每个会话按 `primaryPath` 归到"path 为其前缀且最长"的 worktree（路径归一化后比较，复用现有 `workspacePathsEqual` / `normalizeWorkspacePath`）。
- 匹配不到任何 worktree → 进"其他/孤立"组（罕见；删 worktree 后的孤立会话落这里）。
- 空 worktree 也产出一个空 `WorktreeGroup`（便于新建会话/浏览）。
- 顺序：main 组在前，其余按分支名（后续可改 lastActivity）。组内沿用现有 `AppSessionSort`。

## 5. 启动改动（每会话独立目录）

现状：`SessionRepository.createSession` 写死 `primaryPath: workspace.primaryPath`（`client/lib/repositories/session_repository.dart:338`）。

改动：`createSession` 增加可选 `String? workingDirectory`（及对应 `additionalPaths` 覆盖）。在某 worktree 分组里"新建会话"时传入该 worktree 路径 → 会话 `primaryPath` = worktree 目录 → 自然归入该组、CLI 也跑在该目录。不传时维持旧行为（= `workspace.primaryPath` = main）。

下游 `SessionLifecycleService` 等已基于 `primaryPath`，无需大改。现有会话 `primaryPath` = 仓库根 → 自动落入 main 组，**零迁移**。

## 6. 创建 / 删除对话框

### 创建
- 分支名（自动建议，参考 orca `worktree-name-suggestion`）。
- 模式：新建分支 / 挂载已有分支（分支选择器）。
- base ref（新建分支时，默认仓库默认基或当前 HEAD）。
- 目录：默认 `<teampilotRoot>/worktrees/<repo>/<branch>`，可配置根目录；展示最终路径。
- 可选"创建后立即在此开新会话"。
- 提交后调用 `GitWorktreeService.add`，刷新列表。

### 删除
- 确认框，展示该 worktree 分支 + 其下会话数 N。
- 脏工作树（有未提交/未跟踪）→ 需勾选 force 才能删。
- 可选"同时删除分支"（`-d` 安全删）。
- 可选"同时删除这 N 个会话"（默认**不勾**；不勾则会话保留并落入"其他/孤立"组）。
- 运行中终端：先提示停止（其 cwd 即将消失），停止后再删。
- 提交后调用 `GitWorktreeService.remove`，刷新列表与会话分组。

## 7. 文件树 + 源代码管理：单一当前 worktree

### 现状
`workspace_split_pane.dart:56` 把 `cwd: widget.workspace.primaryPath` 写死成仓库根，所以右侧文件树/源代码管理永远显示 main，与激活会话无关。

### 设计：单一「当前 worktree」+ 双入口切换 + 分支面包屑

**单一当前 worktree** —— 工作区持有一个 per-workspace 状态 `currentWorktreePath`（放在 worktree cubit 或 chat state；默认 = 当前激活会话所属 worktree，无会话时 = `workspace.primaryPath`）。它同时锁定三栏：中间终端、右侧文件树、右侧源代码管理。三者永远指向同一个 worktree，杜绝"终端在 A、文件树在 B"的割裂。

**双入口切换**（都只改 `currentWorktreePath` 这一个值）：
- 点会话 → `currentWorktreePath` = 该会话目录 → 终端打开该会话 + 右侧切到该 worktree。
- 点分组头 → `currentWorktreePath` = 该 worktree 目录 → 右侧切到该 worktree；终端区显示该组会话，空组则显示"+ 在此开新会话"。分组头可点是为了让**没有会话的 worktree** 也能进入浏览/开第一个会话。

**分支面包屑** —— 当前 worktree 的分组头高亮；右侧工具面板顶部显示当前分支名做面包屑，让并行多 worktree 时随时知道"现在在哪个 worktree"。

### 实现
- `workspace_split_pane` 传给 `RightToolsPanel` 的 `cwd` / `additionalPaths` 改为读 `currentWorktreePath`（及其会话的 additionalPaths），不再写死 `workspace.primaryPath`。
- 源代码管理面板自带 `GitCubit` 跟踪 `cwd`（`git_source_control_panel.dart:151`），cwd 一变即显示该 worktree 自己的 git 改动，无需额外改。
- 文件树跟随 cwd 切根；`anyRootExists` 已能处理孤立会话目录不存在的情况。
- `WorkspaceFsWatcher` 在 cwd 变化时重建到新目录。

## 8. 分层落点

| 落点 | 路径 |
|---|---|
| 模型 | `client/lib/models/git_worktree.dart` |
| 服务 | `client/lib/services/git/git_worktree_service.dart`（注入 `ProcessRunner`，desktop-local） |
| 分组纯函数 | `client/lib/utils/session_worktree_grouping.dart` |
| Cubit | `client/lib/cubits/worktree_cubit.dart`（per-workspace：worktree 列表、折叠态、`currentWorktreePath`） |
| 侧栏 UI 区块 | `client/lib/pages/home_workspace/workspace/worktree_group_section.dart` 等（route-only，复用 `SidebarSessionTile`） |
| 创建/删除对话框 | `client/lib/pages/home_workspace/workspace/`（route-only 区块） |
| 启动改动 | `client/lib/repositories/session_repository.dart`（`createSession` 加 `workingDirectory`） |
| 工具面板 cwd | `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`、`client/lib/widgets/right_tools/right_tools_panel.dart` |
| 存储 | `<teampilotRoot>/worktrees/<repo>/<branch>`（`WorkspaceLayout` / `RuntimeLayout` 加 worktrees 根；配置项） |
| l10n | `client/lib/l10n/app_en.arb`、`app_zh.arb`（改后跑 `dart run tool/gen_warmup_glyphs.dart`） |

折叠态 + `currentWorktreePath` 等 per-workspace UI 状态持久化到 `<teampilotRoot>/ui/`。

## 9. 刷新时机

workspace 打开时、`add`/`remove` 之后、手动刷新按钮触发 `GitWorktreeService.list`。v1 不做 orca 那种 3s 轮询；后续可挂到 `GitCubit` 的文件监听。

## 10. 测试

- 分组纯函数：前缀最长匹配、孤立会话进"其他"、空 worktree 产出空组、main 在前。
- `GitWorktreeService.list` 解析：多块 porcelain、`-z` NUL、detached、bare、回退路径——用 fake `ProcessRunner`（仿 `GitService` 注入）。
- `add` / `remove` 拼参正确（新建 vs 挂载、force、deleteBranch）。
- cubit：列表加载、`currentWorktreePath` 双入口切换、删除后会话重新分组。
- 连带删除：勾/不勾"删 N 个会话"两条路径。
- cubit 测试触碰 `AppStorage` 用 `setUpTestAppStorage()` / `tearDownTestAppStorage()`。

## 11. 完整 UX 场景

```
┌─ 左侧会话栏 ─────┐┌─ 中间终端 ──────┐┌─ 右侧工具面板 ──────┐
│ ▾ main          ││  $ claude ...    ││  feat/分组功能 ▾    │ ← 面包屑
│   · 优化启动     ││  (agent 在跑)    ││ ─────────────────── │
│ ▾ feat/分组功能◀││                  ││ [文件树] [源代码]   │
│   · 设计UI ←激活 ││                  ││ M lib/sidebar.dart  │
│ ▸ fix/ssh        ││                  ││ A test/group_test   │
└─────────────────┘└──────────────────┘└─────────────────────┘
```

- 点 `feat/分组功能` 的会话 → 终端 + 文件树 + git 改动全是该 worktree，面包屑显示该分支。
- 点 `fix/ssh` 分组头 → 三栏整体切到 `fix/ssh`；该组为空则终端区显示"+ 在此开新会话"。
- 删除 `feat/分组功能` 且不勾"删会话" → git worktree 没了，"设计UI"等会话落入"其他/孤立"组，历史不丢。

## 12. 待实现计划细化的点

- worktrees 根目录的配置项归属（全局设置 vs 每 workspace）与默认值落地。
- 孤立会话的后续处理 UX（重新指目录 / 一键清理）—— v1 至少能展示在"其他"组并可手动删。
- 面包屑分支名的具体取值（branch / detached 短 oid）与高亮样式。
