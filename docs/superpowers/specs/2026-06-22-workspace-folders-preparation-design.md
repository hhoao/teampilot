# 远程执行架构 ·「预备」阶段设计稿（folders 值对象收敛）

> 状态：**已澄清待实现** · 作用范围：仅「预备」阶段（不依赖 target、低风险、可独立交付）
> 上游设计：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §12（预备行）、§9（数据模型）
> 决策来源：2026-06-22 用户就 Q1–Q6 拍板（经 team-lead 转达）

## 1. 目标

把 `Workspace` 与 `AppSession` 上分裂的 `primaryPath: String` + `additionalPaths: List<String>` 两字段，**收敛为单一** `folders: List<WorkspaceFolder>`，其中 `WorkspaceFolder { path, targetId }`、本阶段 `targetId` 恒为 `'local'`。同时收敛 `session_repository.dart` 中围绕这两个 `List<String>` 的变异点。

**为什么现在做**：这是远程执行架构分期工程的第 0 步。它不引入任何 `RuntimeTarget`、不动存储单例、不改行为，纯粹把"路径列表"升级成"带机器位点占位的目录值对象"，为 P2 给每个目录挂 `targetId` 铺路——届时只需把 `'local'` 改成解析出的 target，无需再迁移一次 JSON。

## 2. 已锁定决策（Q1–Q6）

| # | 决策 | 取值 |
|---|------|------|
| Q1 | 本轮范围 | **只做「预备」阶段**并交付，再回头决定是否继续 P0 |
| Q2 | 文档现有决策 | **接受为准**（§1.4 / §4 / §9） |
| Q3 | AppSession 是否一起收敛 | **是**——Workspace + AppSession 一起换 folders，保持两模型对称 |
| Q4 | 兼容策略 | **硬切**：所有调用点改用 folders 派生 API，**最终不保留** `primaryPath`/`additionalPaths` 旧访问路径 |
| Q5 | WorkspaceFolder 是否预置 targetId | **是**：`WorkspaceFolder { path, targetId = 'local' }`，为 P2 免二次迁移 |
| Q6 | 迁移/回滚 | `fromJson` 容忍新旧两形状；`toJson` **同时仍写** `primaryPath`/`additionalPaths`（派生自 folders）一个版本周期 + `schemaVersion` bump；下个版本再撤双写 |

## 3. 数据模型

### 3.1 `WorkspaceFolder`（新增，`lib/models/workspace_folder.dart`）

```dart
@immutable
class WorkspaceFolder {
  const WorkspaceFolder({required this.path, this.targetId = localTargetId});
  static const String localTargetId = 'local';
  final String path;     // 规范化后的目录路径
  final String targetId; // 机器位点 id；本阶段恒 'local'，P2 起可为 'ssh:*'/'wsl:*'
  // fromJson / toJson / copyWith / == / hashCode
}
```

`toJson`：始终写 `path` 与 `targetId`（即便 `'local'`，显式落盘便于 P2 演进与排查）。

旧→新读取由顶层迁移函数承担：

```dart
List<WorkspaceFolder> foldersFromLegacyJson(Map<String, Object?> json);
// 优先 json['folders']；否则由 json['primaryPath'] + json['additionalPaths'] 构造
// （primaryPath 非空时作 folders.first，其余依序追加，全 targetId='local'）。
```

### 3.2 `Workspace` / `AppSession` 改造

两模型对称改造：

- **字段**：`primaryPath` + `additionalPaths` → `final List<WorkspaceFolder> folders;`
- **永久新 API（硬切目标）**：
  - `String get firstFolderPath` —— `folders.isEmpty ? '' : folders.first.path`（替代 R 类"取单个工作目录"）
  - `List<String> get extraFolderPaths` —— 第 2 个起的 path 列表（替代 RA 类"取附加目录列表"）
  - `List<String> get folderPaths` —— 全部 path（替代 RALL 类 `[primaryPath, ...additionalPaths]`）
- **构造**：`const` 主构造改为私有 `const _(...)` + 公开 `factory`，factory 接受 `folders`，**并在迁移窗口内**额外接受 `primaryPath`/`additionalPaths`（仅当未传 `folders` 时据其构造）。
- **序列化**：
  - `fromJson` → `folders: foldersFromLegacyJson(json)`（容忍新旧）。
  - `toJson` → 写 `folders`，**且双写** `primaryPath: firstFolderPath` / `additionalPaths: extraFolderPaths`，`schemaVersion` 升至 `2`（Workspace 经 `WorkspacesIndex.schemaVersion`，AppSession 经自身 `schemaVersion`）。
- `==`/`hashCode`/`copyWith`/`effectiveDisplay` 改走 `folders`。

### 3.3 迁移脚手架（最终任务移除，确保硬切落地）

为让 ~20 个文件的调用点能**按文件分批、每批保持编译与测试绿**，迁移窗口内临时保留：

- `@Deprecated` 读 getter：`primaryPath` → `firstFolderPath`、`additionalPaths` → `extraFolderPaths`。
- factory 的 `primaryPath`/`additionalPaths` 兼容入参。

**这些脚手架在计划最后一个任务被删除**——终态与 Q4(b)"硬切、不保留旧 API"完全一致；脚手架只为把"一次性触及 ~200 处"安全地切成可回归的小批，正是用户要求的"按文件分批 + 回归测试策略以控制风险"。

## 4. 仓库变异点收敛（`session_repository.dart`）

6 处围绕路径列表的逻辑改为面向 folders：

1. `createWorkspace`：**对外仍收 `String primaryPath` + `List<String> additionalPaths`**（调用方传字符串路径不变），内部构造 `List<WorkspaceFolder>`（全 `local`）；按 path 去重合并保持原幂等语义。
2. `updateWorkspacePaths`：同上，内部建 folders。
3. `updateWorkspaceMetadata`：`additionalPaths` 入参不变，内部映射进 folders（保留 first folder，替换其余）。
4. `_provisionWorkspaceTrust`：`directories: workspace.folderPaths`（替代 `[primaryPath, ...additionalPaths]`）。
5. `createSession`：`folders` 由 `workspace.folders` 派生；`workingDirectory` 覆盖时替换 first folder 的 `path`（保留其 `targetId`），其余 folder 原样保留。
6. `_cloneSessionRecord` / clone 工作区：`folders: List.of(source.folders)`。

**保持仓库对外 string 形参**是有意为之：本阶段全 local，对话框/调用方无需感知 folders；P2 再引入 folder 感知的写 API。

## 5. 调用点分批（硬切，~36 处有效命中 / ~20 文件）

> 排除项（非模型字段，不在本次范围）：`TeammateRosterProfile.additionalPaths`、`teammate_bus_mcp_handler` 的 `team.additionalPaths`、`RightToolsPanel`/`ChatPage`/`chat_page_shell` 自有的 `additionalPaths`/`cwd` 构造参数——这些是下游 widget/profile 的**独立形参**，保持 `List<String>` 不改名，调用方改为喂 `folderPaths`/`extraFolderPaths` 即可。

- **批 A · services + cubits**：`session_lifecycle_service.dart`、`cubits/chat/session_launch_service.dart`、`tab_team_bus_coordinator.dart`、`session_data_store.dart`、`chat_tab_store.dart`、`default_workspace_service.dart`、`home_closed_workspaces_store.dart`、`utils/session_worktree_grouping.dart`。
- **批 B · widgets + pages**：`workspace_details_dialog.dart`、`right_tools/right_tools_panel.dart`（喂入侧）、`home_workspace/*`（shell / title_bar / info_section / settings_view / split_pane / sidebar / search）、`chat_page.dart` / `chat_page_shell.dart`（喂入侧）。

每批逐文件改：`.primaryPath`→`.firstFolderPath`、`.additionalPaths`→`.extraFolderPaths`、`[primaryPath, ...additionalPaths]`→`.folderPaths`、构造 `primaryPath:`/`additionalPaths:`→`folders:`。

## 6. 迁移与兼容策略

- **读**：`foldersFromLegacyJson` 双形状容忍——旧 manifest（只有 `primaryPath`/`additionalPaths`）自动升为 folders；新 manifest 直接读 `folders`。**无一次性迁移脚本**，惰性升级（读到即升，写回即新形状）。
- **写**：双写一个版本周期（`folders` + 派生的 `primaryPath`/`additionalPaths`）+ `schemaVersion: 2`。旧版本 App 仍能读懂派生字段 → 无损回滚。
- **撤销窗口**：下个版本删除 `toJson` 双写与 `fromJson` 旧形状分支（独立后续任务，不在本计划）。

## 7. 验收点（对齐上游 §12 预备行）

1. 多目录工作区可建、可加目录（`--add-dir` 行为不变）。
2. 旧数据无损迁移：旧 manifest 读出后 folders 与原 primaryPath/additionalPaths 等价；写回含 `folders` 且仍双写旧字段。
3. 行为不变：`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
4. 终态硬切：全仓无对 `Workspace`/`AppSession` 的 `.primaryPath`/`.additionalPaths` 访问（脚手架 getter 已删）。

## 8. 不在本阶段范围（YAGNI）

- 任何 `RuntimeTarget` / targets 注册表 / 控制面-工作面拆分 / 反向隧道（属 P0–P4）。
- `WorkspaceFolder.targetId` 的任何**非 `'local'`** 取值与解析逻辑。
- 仓库 folder 感知写 API、远程目录浏览器、`AppSession.folderAssignments`（属 P2/P3）。
- `toJson` 双写的撤销（属下个版本）。
