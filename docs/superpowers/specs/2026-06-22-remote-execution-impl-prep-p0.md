# 远程执行 — 实现方案（预备 + P0）

**Date:** 2026-06-22
**Status:** 实现计划（待执行）
**范围:** 仅 **预备**（WorkspaceFolder 值对象）+ **P0**（`RuntimeTarget` + targets 注册表）。后续 P1–P4 等这两期落定再展开。
**关联:**
- 设计: [../../remote-execution-architecture.md](../../remote-execution-architecture.md)（§3、§9、§12）
- 模型: 见设计文档 §4 / §9（原独立的 2026-06-18 workspace-folders spec 已不在仓库，设计文档为权威）

---

## 0. 命名对账（先读这条）

**设计文档与 spec 已对代码现实过时。** 二者都写"`AppProject` 不改名、目录类型 `ProjectFolder`"，但代码里：

| 文档里的名字 | 代码现实（2026-06-22 核对） |
|---|---|
| `AppProject`（`app_project.dart`） | **`Workspace`（`models/workspace.dart`）** — 字段 `workspaceId` / `primaryPath` / `additionalPaths` / `display` / `defaultProfileId` / `sessionIds` |
| `ProjectFolder` | 本计划用 **`WorkspaceFolder`**（与实体 `Workspace` 对齐；spec 最初也是这个名） |
| `TeamConfig` | **`TeamIdentity`**（rename 已落，提交 `62f68b4`） |
| `TeamMemberConfig`（`team_config.dart`） | 仍是 `TeamMemberConfig`，仍在 `team_config.dart`（未改）|

**本计划一律用代码现实的名字。** 设计文档 `remote-execution-architecture.md` 的命名**已于 2026-06-22 修正**为 `Workspace`/`WorkspaceFolder`（并删除了对已不在仓库的 2026-06-18 workspace-folders spec 的链接，改为自含权威）。

---

## 1. 预备 — `WorkspaceFolder` 值对象

### 1.1 为什么先做这个
- **不依赖 `RuntimeTarget`**：folder 先全 `targetId == 'local'`，单机形态即可落地、行为不变（设计文档 §9）。
- **独立有价值**：多目录工作区 + `--add-dir`、未来 per-folder 机器都建立在它上面。
- **解耦后续**：把散落的 `primaryPath` + `additionalPaths: List<String>` 收敛成一个带机器/显示名的值对象，给 P0 的 `targetId` 上车铺路。

### 1.2 现状（已核对）
`primaryPath` / `additionalPaths` 在 **~30 个文件、约 100 处**被读/写（`grep -rn additionalPaths client/lib | wc -l` = 100）。直接全替换风险大。故用**并行字段 + 兼容 getter** 的渐进迁移：新增 `folders` 为权威字段，`primaryPath`/`additionalPaths` 降级为**派生 getter**，读侧 30 处先不动，只迁移写侧。

### 1.3 新类型 `WorkspaceFolder`

新文件 `client/lib/models/workspace_folder.dart`：

```dart
@immutable
class WorkspaceFolder {
  const WorkspaceFolder({
    required this.path,
    this.targetId = 'local',   // = RuntimeTarget.id；预备期恒 'local'
    this.name = '',            // 可选显示名（VSCode 风格）
  });

  final String path;
  final String targetId;
  final String name;

  factory WorkspaceFolder.fromJson(Map<String, Object?> json) => ...;
  Map<String, Object?> toJson() => ...;  // 省略 name/targetId 默认值以保持 JSON 紧凑
  WorkspaceFolder copyWith({...});
  // == / hashCode
}
```

- `targetId` 复用 P0 的 `RuntimeTarget` id 空间；预备期注入恒 `'local'`，P0 落地后才会出现 `ssh:*`。
- 是值对象（非裸 String）的理由（见设计文档 §4.1）：folder 要携带机器 + 显示名 + 运行时增删（§1.6）。

### 1.4 `Workspace` 模型改造（`models/workspace.dart`）

并行字段策略：

1. **新增权威字段** `final List<WorkspaceFolder> folders;`（构造器必填或由 primaryPath 推导）。
2. **`primaryPath` / `additionalPaths` 改为派生 getter**（保留同名，读侧零改动）：
   ```dart
   String get primaryPath => folders.isEmpty ? '' : folders.first.path;
   List<String> get additionalPaths =>
       folders.skip(1).map((f) => f.path).toList(growable: false);
   ```
   ——同时**删掉**这两个 final 字段与构造器参数（改由 folders 提供）。
3. **`fromJson` 双读**：
   - 若 `json['folders']` 存在 → 直接解析。
   - 否则（旧数据）→ 由 `primaryPath` + `additionalPaths` 构造 `folders`，每项 `targetId='local'`、第一项为 primary。
4. **`toJson` 写 `folders`**（权威）。过渡期**同时镜像** `primaryPath`/`additionalPaths`，让回滚到旧版本仍可读；下一个大版本再移除镜像。
5. `copyWith` 改为接收 `folders`；保留一个便捷 `copyWithFolderAt`/`addFolder`/`removeFolder` 给增删用。
6. `effectiveDisplay` 不变（仍基于 `primaryPath` getter）。
7. `WorkspacesIndex` 不变（schemaVersion 仍可保留；folders 是 Workspace 内部演进，可不动 index 版本，靠 fromJson 兼容）。

### 1.5 写侧（mutation）迁移点
重点改"创建/更新工作区目录集"的地方，让它们经 `folders`：

| 文件 | 改什么 |
|---|---|
| `repositories/session_repository.dart` | 工作区 CRUD：创建（含 `ensureDefaultPersonalProject` / 默认个人工作区）、改路径、加/删附加目录 → 走 `folders`（注入 `targetId:'local'`）|
| `services/team/default_workspace_service.dart` | 默认工作区构造 → `folders` |
| `widgets/create_workspace_dialog.dart`、`pages/home_workspace/home_new_workspace_dialog.dart` | 新建工作区 UI 收集多 folder（预备期都 local）→ 传 `folders` |
| `widgets/workspace_details_dialog.dart`、`pages/home_workspace/workspace/workspace_info_section.dart` | 编辑目录 → `folders` |

读侧（file_tree_cubit、chat 启动、git、worktree 分组、session_lifecycle 等 ~25 处）**先靠派生 getter 不动**；后续按需逐个迁移到 `folders`（享受 per-folder name/targetId 时再改）。

### 1.6 运行时增删目录 MCP（可选子任务，见设计文档 §4.2）
单机形态可顺带落 `list_workspace_folders` / `add_workspace_folder(path)` / `remove_workspace_folder(path)`：
- 经 Workspace 仓库/cubit 改 `folders`（单一数据源，UI 响应式更新）。
- `WorkspaceFoldersCapability`（每 CLI 一致，AGENTS.md "加能力别 `if(cli==)`"）：claude 走运行时 `/add-dir`（stdin 注入，复用 `FirstUserLineCapture`/门铃）；其余 CLI 退化为"改模型 + relaunch(resume)"。
- 预备期仅单机；mixed/远程目录浏览待 P0 的 target + SFTP listDir。

> 若想缩小预备期，这一节可推迟到 P3（跨机增删才真正需要）。建议**预备期至少落 `list_workspace_folders`**（纯读、零风险）。

### 1.7 测试（预备）
- `test/models/workspace_folder_test.dart`：fromJson/toJson round-trip、默认值省略、copyWith、==。
- `test/models/workspace_test.dart`：
  - 旧 JSON（只有 `primaryPath`+`additionalPaths`）→ 迁出正确 `folders`（全 local、primary 为首）。
  - 新 JSON（有 `folders`）→ 正确解析；`primaryPath`/`additionalPaths` getter 与 folders 一致。
  - toJson 同时含 folders 与镜像字段（过渡期断言）。
- 仓库测试：创建/改路径/增删目录后 `folders` 与持久化一致（用 `setUpTestAppStorage()`）。
- 回归：现有依赖 `primaryPath`/`additionalPaths` 的 cubit/widget 测试**全绿不改**（验证派生 getter 等价）。

### 1.8 验收（预备）
- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` 全绿。
- 旧工作区数据加载后行为与今天一致（手测：打开既有工作区、文件树、git、会话启动）。
- 新建一个含 2 个本地目录的工作区，第二个目录作为 `--add-dir` 生效（手测 claude）。

### 1.9 风险（预备）
- **JSON 兼容**：必须保证旧数据无 `folders` 时迁移正确、且过渡期写回不破坏旧版本读取（镜像字段）。
- **派生 getter 的写语义**：原本可能有代码直接 `copyWith(primaryPath:)`——这些会编译失败（字段没了），属**有意暴露**，逐个改成 `folders` 操作（编译器帮你找全）。这是把"~6 处隐式变异"显式化的关键收益。

---

## 2. P0 — `RuntimeTarget` + targets 注册表（行为不变）

### 2.1 目标与铁律
四旋钮（storage backend / connection mode / active ssh profile / wsl distro）→ 一个 `RuntimeTarget` + targets 注册表。**P0 必须行为中性**：单 target = 今天行为；local/wsl/ssh/Android 全路径回归通过；`isSshMode` 单一来源。

### 2.2 新模型（`models/runtime_target.dart`）
```dart
enum RuntimeKind { local, wsl, ssh }
enum RemoteOs { posix, windows }      // 预留，P0 可只填 posix；探测留待 P3

class RuntimeTarget {
  final String id;            // 'local' | 'wsl:<distro>' | 'ssh:<profileId>'
  final String label;
  final RuntimeKind kind;
  final String? sshProfileId; // kind==ssh
  final String? wslDistro;    // kind==wsl
  final RemoteOs? remoteOs;   // kind==ssh；P0 先不探测
  // fromJson/toJson/copyWith/==；id 解析 helper（从 'ssh:x' 拆出 kind+payload）
}
```

### 2.3 targets 注册表（升级 `ssh_profiles/`）
- 新 `repositories/runtime_target_repository.dart`（或扩 `ssh_profile_repository.dart`）：
  - **隐式条目**：`local`（恒有）、`wsl:<distro>`（Windows 上按已安装 distro，或从既有解析迁移而来，见 2.6）。
  - **显式条目**：每个 `SshProfile` → 一个 `ssh:<profileId>` target；`SshProfile` 成为该 target 的载荷（不改 `SshProfile` 模型，注册表做映射）。
  - `defaultTargetId` 的读写（取代 active profile 选择 + connectionMode）。
- `cubits/ssh_profile_cubit.dart` → 视情况升级/包一层 `RuntimeTargetCubit`（P0 可先最小：注册表 + default 读写，UI 改造留 P1）。

### 2.4 `SessionPreferences` 迁移（`models/session_preferences.dart`）
- 新增 `final String defaultTargetId;`。
- `fromJson`：若有 `defaultTargetId` → 用；否则**由旧字段映射**（见 2.7）。
- `connectionMode` / `windowsStorageBackend` **保留读旧字段**（迁移用），但新逻辑一律走 `defaultTargetId`；标注 deprecated，P1 再删。
- `copyWith` / `toJson` 加 `defaultTargetId`（同时仍写旧字段做过渡镜像）。

### 2.5 `RuntimeStorageContext` 物化改为吃 `RuntimeTarget`
- 现 `resolve()`（`runtime_storage_context.dart:82`，平台判定从分散 preferences 推导）→ 改为 **入参一个 `RuntimeTarget`**，按 `kind` 分支产出 `Filesystem` + `appDataRoot`（+ P0 暂不动 transport 归属，留接口）。
- `parseWslDistro(executable)`（`:252`，从可执行路径隐式解析）→ 退役为"迁移用一次性解析"，distro 改由 `wsl:<distro>` target 字段显式携带（2.6）。
- `install()` / `installForTesting()`（`:266`）签名调整为接受 target / 注册表；**P0 仍是单 target 单例**（去单例是 P2，别越界）。

### 2.6 WSL distro：隐式 → 显式（P0 顺手清理，§11）
- 启动迁移：用现有 `parseWslDistro` 把当前 distro 解析出来，落进 `wsl:<distro>` target 并设为（Windows 上的）默认；此后不再依赖可执行路径推导。

### 2.7 `isSshMode` 单一来源（消除双推导，§2.1）
- `services/app/connection_mode_service.dart:19` `isSshMode => effectiveMode == ConnectionMode.ssh` → 改为 `=> defaultTarget.kind == RuntimeKind.ssh`。
- `app_shell.dart:226/230/319/331/394/405/608` 的多处 `isSshMode` → 全部转发同一个来源（`connectionModeService.isSshMode` 或新 `runtimeTargetService`），不再各算一次。
- `requiresSshProfileSetup`（`:24`）相应改为基于 default target。

### 2.8 旧数据 → target 映射（兼容）
| 旧 | 新 `defaultTargetId` |
|---|---|
| `connectionMode==localPty` + `windowsStorageBackend==native` | `local` |
| `windowsStorageBackend==wsl` (+ distro) | `wsl:<distro>` |
| `connectionMode==ssh` + active `SshProfile` | `ssh:<activeProfileId>` |

加载时一次性映射；旧字段保留只为回滚兼容。

### 2.9 §3.1 映射落实
`RuntimeStorageContext.resolve` 的平台分支整体迁入"由 `RuntimeTarget` 物化"的工厂；不再从 `SessionPreferences.connectionMode`/`windowsStorageBackend`/active profile 三处拼。

### 2.10 测试（P0）
- `test/models/runtime_target_test.dart`：id 解析（`ssh:x`→kind+payload）、round-trip、隐式 local/wsl 条目。
- 注册表测试：SshProfile 列表 → ssh-kind targets；default 读写；隐式条目恒在。
- 迁移测试：三种旧 prefs 组合 → 正确 `defaultTargetId`（含 wsl distro）。
- **行为中性回归**：
  - local 默认 → resolve 出的 fs/appDataRoot 与今天逐字节一致。
  - 注入 `ssh:<id>` → 等价于今天 `connectionMode.ssh + active profile`。
  - `wsl:<distro>` → 等价今天 wsl 后端。
  - `isSshMode` 在三态下与旧实现一致（参数化测试，断言新旧两路同值）。
- mock 子进程/fs 经构造器注入（AGENTS.md）。

### 2.11 验收（P0）
- `flutter analyze … && flutter test --exclude-tags integration` 全绿。
- 手测四条全路径回归：桌面 local PTY、桌面 ssh、Windows wsl、Android（强制 ssh）——行为与今天无差。
- 代码层断言：全仓 `isSshMode` 只剩**一个**真实计算点（其余转发）。
- Linux PTY 集成测试（`@Tags(['integration'])`，见 DEVELOPMENT.md）跑通本地启动路径。

### 2.12 风险（P0）
- **行为漂移**：最大风险是迁移/映射处把某个边角行为改了。对策——回归测试逐态断言"新路径 == 旧路径"，旧字段保留可快速回滚。
- **WSL 隐式→显式**（2.6）是 P0 里唯一真的行为改动点，单独测：解析出的 distro 必须与今天 `parseWslDistro` 结果一致。
- **不要越界去单例**：`RuntimeStorageContext` P0 仍单例，注册表只是"算 target 的来源"。去单例是 P2。

---

## 3. 两期之间的次序与依赖
- **预备 ⟂ P0 基本独立**：预备只引入 `WorkspaceFolder.targetId`（恒 `'local'`，字符串）；P0 引入 `RuntimeTarget` 与 id 空间。**预备可先 merge**。
- 预备的 `targetId` 字面值 `'local'` 在 P0 落地后自然等于 `RuntimeTarget.id` 的 local 条目——无需回改预备数据。
- 两期都用"并行字段 + 兼容读旧 + 过渡镜像写"的同一套迁移手法，降回滚成本。

## 4. 完成前自检（两期通用，AGENTS.md）
```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```
- l10n 文案改动只动 `app_en.arb` / `app_zh.arb`，改后 `flutter pub get`；若动 ARB 再跑 `dart run tool/gen_warmup_glyphs.dart`。
- 不提交 `client/google_fonts/`。

## 5. 待你确认的实现决策
1. **运行时增删目录 MCP（§1.6）** 放预备还是推迟到 P3？建议预备只落只读 `list_workspace_folders`。
2. **targets 注册表落点**：扩 `ssh_profile_repository` 还是新 `runtime_target_repository`？建议新建，旧仓退化为 ssh-payload 存储。
3. **过渡镜像保留多久**：folders 的 `primaryPath`/`additionalPaths` 镜像、prefs 的旧字段——P1 删还是再观察一版？
