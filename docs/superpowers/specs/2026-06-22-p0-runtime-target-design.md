# 远程执行架构 · P0 设计稿（四旋钮 → RuntimeTarget + targets.json 注册表）

> 状态：**已澄清待实现** · 行为不变重构 · 建立在分支 `feat/workspace-folders-preparation`（预备阶段已提交）之上
> 上游设计：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §3 / §3.1 / §9 前半 / §12 P0 行
> 决策来源：2026-06-22 用户就 P0 的 Q1–Q8 拍板（经 team-lead 转达）

## 1. 目标（行为不变）

把今天四个**各自为政的全局旋钮**折成**一个值** `RuntimeTarget`，并新增独立的 `targets.json` 注册表持有目标列表与默认目标：

| 今天的旋钮 | 位置 | 折入 RuntimeTarget |
|---|---|---|
| Storage backend `{native,wsl,ssh}` | `runtime_storage_context.dart:14` | `kind` |
| Connection mode `{localPty,ssh}` | `SessionPreferences.connectionMode` | `kind`（ssh 与否） |
| active SSH profile | `ssh_profiles/selected_profile.txt` | `sshProfileId`（载于 `defaultTargetId='ssh:<id>'`） |
| WSL distro | 解析 claude 可执行路径（`parseWslDistro`） | `wslDistro`（显式存储） |

**单 target = 今天行为**：P0 不引入任何多机解析、不去单例、不拆控制面/工作面、无反向隧道。只把"同一台机的四个侧面"归一为一个值与单一推导来源。

## 2. 已锁定决策（Q1–Q8）

| # | 决策 |
|---|------|
| Q1 | 只做 P0 并交付，再决定是否续 P1 |
| Q2 | **落独立 `targets.json`**（非内存视图）；含 schema、读写位置、从 `ssh_profiles/` 一次性迁移落库、与平台隐式条目 `local`/`wsl:*` 的合并规则 |
| Q3 | id 命名 `'local'` / `'wsl:<distro>'` / `'ssh:<profileId>'`（与预备阶段 `WorkspaceFolder.targetId='local'` 对齐，P2 复用） |
| Q4 | **逻辑归一、单例不动**：RuntimeTarget 成为存储 install 与传输工厂的**单一来源**（都从 `target.kind` 推导、`isSshMode` 归一），但**不**去单例/不实例化 `RuntimeStorageContext`（属 P2） |
| Q5 | UI 保持现状（连接模式开关 + 选 SSH profile），target 仅内部表示；"选 target" UI 留 P1 |
| Q6 | WSL distro 显式化：从"解析 claude 路径"改为显式存储（并入 `defaultTargetId='wsl:<distro>'`，迁移时从现有解析值一次性落库） |
| Q7 | 迁移/双写窗口：容忍旧 `connectionMode`/`windowsStorageBackend` 映射成 `defaultTargetId`；双写旧字段一个版本周期 + schemaVersion bump；下版撤双写 |
| Q8 | `remoteOs` 引入为 nullable 占位，**不**实现 connect 探测、**无** Windows-remote 分支（属 P3） |

### 2.1 已解决的内部张力（记录在案，非待答）

任务简报曾提到"`SessionPreferences` 新增 `defaultTargetId`"，而 Q2(b) 定 `targets.json` 持有 `defaultTargetId`。二者取一：**`defaultTargetId` 权威落在 `targets.json`**（Q2(b) 更具体、更新）。`SessionPreferences.connectionMode`/`windowsStorageBackend` 降级为**遗留双写字段**（保留一个版本周期供回滚），不再是真相源；迁移仅**一次性读**它们来播种初始 `defaultTargetId`。

## 3. 数据模型

### 3.1 `RuntimeTarget`（新增 `lib/models/runtime_target.dart`）

```dart
enum RuntimeKind { local, wsl, ssh }
enum RemoteOs { posix, windows }   // P0 恒 null

@immutable
class RuntimeTarget {
  const RuntimeTarget({
    required this.id,        // 'local' | 'wsl:<distro>' | 'ssh:<profileId>'
    required this.label,     // UI 显示名
    required this.kind,
    this.sshProfileId,       // kind == ssh
    this.wslDistro,          // kind == wsl
    this.remoteOs,           // P0 恒 null（探测属 P3）
  });
  static const String localId = 'local';
  factory RuntimeTarget.local({String label = 'This device'});
  factory RuntimeTarget.wsl(String distro, {String? label});      // id 'wsl:<distro>'
  factory RuntimeTarget.ssh(String profileId, {required String label}); // id 'ssh:<profileId>'
  factory RuntimeTarget.fromJson(Map<String,Object?>);
  Map<String,Object?> toJson();
  RuntimeTarget copyWith({...});
  // == / hashCode
}
```

id 解析辅助（顶层或静态，供 registry/迁移复用）：

```dart
RuntimeKind runtimeKindOfId(String id);     // 前缀 'wsl:'/'ssh:' 否则 local
String? sshProfileIdOfId(String id);        // 'ssh:<x>' -> x
String? wslDistroOfId(String id);           // 'wsl:<x>' -> x
```

### 3.2 `targets.json`（新增独立注册表文件，控制面）

**位置**：`<teampilotRoot>/targets.json`（与 `ssh_profiles/`、`teams/`、`cli-defaults/` 同级，属控制面）。新增 `AppPaths.targetsFile => join(basePath, 'targets.json')`。

**Schema**（`TargetsRegistryFile`）：

```json
{
  "schemaVersion": 1,
  "defaultTargetId": "local",
  "wslDistro": "",
  "targets": [
    {"id": "ssh:<profileId>", "label": "prod-box", "kind": "ssh", "sshProfileId": "<profileId>"}
  ]
}
```

- `targets[]` **只持久化 ssh-kind 目标**（一次性从 `ssh_profiles/` 迁移落库，之后随 profile 增删**在加载时对账**——见 §3.3）。
- ssh 目标**不复制连接细节**（host/user/auth 仍在 `ssh_profiles/profiles.json`，按 `sshProfileId` join）——避免双源漂移。
- `local` / `wsl:<distro>` 为**平台隐式条目**，不进 `targets[]`，在 registry 合并时注入（见 §3.3）。
- `defaultTargetId`：真相源；`wslDistro`：显式存储的 distro（Q6）。

### 3.3 `RuntimeTargetRegistry`（新增 `lib/services/storage/runtime_target_registry.dart`）

```dart
class RuntimeTargetRegistry {
  RuntimeTargetRegistry({
    required TargetsRepository repo,            // 读写 targets.json
    required SshProfileRepository sshProfileRepo,
    required bool isWindows,                    // 注入便于测试
    required bool isAndroid,
  });
  Future<List<RuntimeTarget>> listTargets();    // 合并 + 对账（见下）
  Future<RuntimeTarget> defaultTarget();        // 解析 defaultTargetId → RuntimeTarget；缺失/孤儿回落 local
  Future<void> setDefaultTargetId(String id);   // 写 targets.json
  Future<String> wslDistro();                   // targets.json.wslDistro
}
```

**合并规则**（`listTargets`）：
1. 隐式 `local` 永远在列。
2. Windows 且 `wslDistro` 非空 → 注入 `wsl:<distro>`。
3. ssh 目标 = `targets[]` 与 live `ssh_profiles` 按 `sshProfileId` **对账**：
   - profile 存在但 `targets[]` 缺 → 追加 ssh 目标并**回写** `targets.json`（surface 新建 profile）。
   - `targets[]` 有但 profile 已删 → **剔除**并回写（清孤儿）。
   - label 取 profile.name。
4. `defaultTarget()`：按 `defaultTargetId` 在合并列表中查；查不到（如指向已删 profile）回落 `local`。

### 3.4 `TargetsRepository`（新增 `lib/services/storage/targets_repository.dart`）

仿 `SshProfileRepository` 模式：构造注入 `rootDir`/`fs`（测试用），方法 `Future<TargetsRegistryFile> load()` / `Future<void> save(TargetsRegistryFile)`，文件 `AppStorage.paths.targetsFile`，写用 `atomicWrite`。

## 4. 一次性迁移（`targets.json` 不存在时）

`RuntimeTargetRegistry.load`（或专门的 `RuntimeTargetMigration`）在 `targets.json` 缺失时构建初版并落库：

```
defaultTargetId 由旧真相源计算：
  - Android                              → 第一个 ssh 目标的 id（无 profile 则 'local'，与今天 Android 强制 ssh 等价由 install() 兜底）
  - connectionMode == ssh 且有 selectedProfileId → 'ssh:<selectedProfileId>'
  - Windows backend == wsl               → 'wsl:<parsedDistro>'
  - 否则                                  → 'local'
wslDistro:
  - 一次性 = RuntimeStorageContext.parseWslDistro(resolveExecutable())（之后显式，不再解析）
targets[]:
  - 每个现有 SshProfile 生成一个 {id:'ssh:<pid>', label:name, kind:ssh, sshProfileId:pid}
```

**双写/回滚（Q7）**：`SessionPreferences.connectionMode`/`windowsStorageBackend` 保留并继续**双写**一个版本周期；P0 不删这两字段（下个版本删）。`selected_profile.txt` 同样保留（ssh profile 选择 UI 仍写它，见 §5）。迁移**只读不毁**旧源。

## 5. 逻辑归一：单一来源消除 `isSshMode` 双重推导（Q4）

**今天**：`isSshMode` 在 `connection_mode_service.dart:19`、`app_shell.dart`（install :232、reinstall 判定 :291）各算一次；传输选择在 `chat_session_shell_factory.dart` 另读 `connectionMode`+`sshProfile`。

**P0**：引入单一 `RuntimeTarget Function() defaultTargetResolver`（由 registry 提供，app_shell 装配），所有消费方都从它推导：

- `ConnectionModeService`：改为持 `defaultTargetResolver`，`isSshMode => resolver().kind == RuntimeKind.ssh`（Android 由 `RuntimeStorageContext.resolve` 内既有 `Platform.isAndroid` 兜底，行为不变）。删除 app_shell 两处内联 `connectionMode == ssh` 计算，改用 `connectionModeService.isSshMode`。
- `RuntimeStorageContext`：**新增** `installForTarget(RuntimeTarget target, {sshClientFactory, sshProfile, native paths})`，内部把 `target.kind` 映射成既有 `resolve()` 的入参（`isSshMode`/`windowsStorageBackend`/`wslDistro`/`sshProfile`）后复用现有逻辑。**`resolve()`/`_resolveNative/_resolveWsl/_resolveSsh` 与单例 `_current` 一律不动**（Q4：单例不动）。app_shell 的 install/reinstall 闭包改为：先 `registry.defaultTarget()` 得 target，再 `installForTarget(target, …)`。
- `chat_session_shell_factory.dart`：把 `connectionModeResolver`+`sshProfileResolver` 两个入参合并为 `RuntimeTarget Function() defaultTargetResolver`；`useSsh => target.kind == ssh && profile != null`，profile 由 `target.sshProfileId` → `sshProfileCubit`/repo 取。行为与旧 `connectionMode==ssh && selectedProfile!=null` 等价。
- `StorageRoots`：`isSshMode`/`sshProfileResolver` 入参同样改由 target 推导（`_resolveUncached` 的判据不变，只换来源）。

**UI 写回（Q5 保持现状控件）**：现有四个输入仍在，但都**漏斗汇入 `defaultTargetId`**（同时双写旧字段）：

| UI 动作 | 写 defaultTargetId | 双写旧字段 |
|---|---|---|
| 连接模式切 ssh（已有选中 profile） | `'ssh:<selectedId>'` | `connectionMode=ssh` |
| 连接模式切 localPty | Windows+wsl 后端→`'wsl:<distro>'`，否则 `'local'` | `connectionMode=localPty` |
| 选另一个 ssh profile（ssh 模式下） | `'ssh:<newId>'` | `selected_profile.txt=newId` |
| Windows 后端 native↔wsl | `'local'`↔`'wsl:<distro>'` | `windowsStorageBackend` |

这些 handler 在 `SshProfileCubit.onActiveProfileChanged` / 连接模式切换 / Windows 后端切换处各加一行 `registry.setDefaultTargetId(...)`。`reinstallStorageContext` 之后照常 `installForTarget(registry.defaultTarget())`。

## 6. 关键文件

| 文件 | 动作 | 职责 |
|------|------|------|
| `lib/models/runtime_target.dart` | 新增 | `RuntimeTarget`/`RuntimeKind`/`RemoteOs` + id 解析辅助 |
| `lib/services/storage/targets_repository.dart` | 新增 | 读写 `targets.json`（`TargetsRegistryFile`） |
| `lib/services/storage/runtime_target_registry.dart` | 新增 | 合并/对账/迁移、`defaultTarget`、`setDefaultTargetId` |
| `lib/services/storage/app_storage.dart` | 改 | 加 `AppPaths.targetsFile` |
| `lib/services/storage/runtime_storage_context.dart` | 改 | 加 `installForTarget`（映射 target→既有 resolve 入参；resolve/单例不动） |
| `lib/services/app/connection_mode_service.dart` | 改 | `isSshMode` 由 `defaultTargetResolver` 推导（单一来源） |
| `lib/cubits/chat/chat_session_shell_factory.dart` | 改 | 传输选择由 `defaultTargetResolver` 推导 |
| `lib/services/storage/storage_resolver.dart` (`StorageRoots`) | 改 | 判据来源换为 target |
| `lib/app/app_shell.dart` | 改 | 装配 registry；build target；删两处内联 isSshMode；install/reinstall/StorageRoots/factory 从 registry 取 |
| `lib/cubits/ssh_profile_cubit.dart` | 改 | 选 profile / 改模式时 `setDefaultTargetId` 漏斗 |

## 7. 测试策略（重点：单 target 回归证明行为不变）

1. **RuntimeTarget 单测**：id format/parse（local/wsl:<d>/ssh:<id>）、fromJson/toJson 往返、factory。
2. **TargetsRepository 单测**：内存 fs 往返；缺文件返回空默认。
3. **RuntimeTargetRegistry 单测**：
   - 迁移：`connectionMode=localPty`→default `local`；`=ssh`+selected→`ssh:<id>`；Windows wsl→`wsl:<distro>`；distro 播种自 `parseWslDistro`。
   - 合并：隐式 `local` 恒在；Windows+distro 注入 `wsl:*`；ssh 目标对账（新 profile 追加并回写、删 profile 剔除）。
   - `defaultTarget` 孤儿回落 `local`。
4. **ConnectionModeService 单测**：local→isSshMode false；ssh→true；（Android 兜底不变，由 resolve 层负责）。
5. **行为不变金标准（核心）**：`installForTarget(target)` 与旧 `install(isSshMode/backend/distro/...)` 在每种 kind 下产出**同一** `RuntimeStorageContext`（断言 `mode`/`appDataRoot`/`usesPosixPaths` 等价）——
   - `RuntimeTarget.local` ≡ 旧 native；`wsl:<d>` ≡ 旧 wsl(distro)；`ssh:<id>` ≡ 旧 ssh(profile)；Android 路径不变。
6. **传输选择等价**：`chat_session_shell_factory` 在 target.kind=ssh+profile 选 `SshPtyTransport`，否则 `LocalPtyTransport`——与旧 connectionMode 判据逐例等价。
7. **回归全量**：`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿（既有 ssh/storage/transport 测试不改语义）。
8. 桌面 local/wsl/ssh + Android(ssh) 四条手验金路径（CI 不覆盖处文档化）。

## 7.1 手验金路径（CI 不覆盖 PTY/SSH/WSL/Android）

P0 是行为不变重构。下列四条金路径需人工确认与 P0 前**完全一致**（每条：能启动、能落盘到预期 root、终端能连）：

1. **Linux 桌面 · local**：连接模式 localPty。启动后 `RuntimeStorageContext.mode == native`，数据落 `~/.local/share/com.hhoa.teampilot`；本地 PTY 终端可开会话。
2. **Windows · WSL 后端**：存储位置切 WSL（distro 显式）。`mode == wsl`，数据落 WSL `$HOME/.local/share/com.hhoa.teampilot`；切回 native 亦正常。
3. **桌面 · SSH profile**：连接模式 ssh + 选中一个 profile。`mode == ssh`，数据落远端 TeamPilot app dir；切换 profile 触发重装且数据源跟随。换/删 profile 后 `targets.json` 对账（新增 surface、删除剔除）。
4. **Android · 强制 SSH**：首启无 profile → 落 SSH 设置页（`requiresSshProfileSetup`）；建好 profile 后正常进入并走远端存储。

实现细节（落实「行为不变」）：`defaultTargetResolver` **实时**从遗留 prefs 派生 target（ssh kind 反映 *意图* `connectionMode==ssh`，与 profile 是否就绪无关——由 `installForTarget`→`resolve()` 既有 profile/Android 兜底决定有效后端），故 `connectionModeService.isSshMode`、启动门、传输选择逐路径与旧实现等价；`targets.json` 由迁移播种、每次 reinstall 经 `setDefaultTargetId` 镜像（Q5/Q7 双写窗口），供 P1「选 target」UI 反转为权威源。

## 8. 不在 P0 范围（YAGNI）

- 去单例 / `RuntimeContextRegistry` / `RuntimeContext` 实例化（P2）。
- 控制面/工作面拆分、`Workspace.folders[].targetId` 的多机解析、每目录 target（P2）。
- 反向隧道、bus raw socket、relay、跨机产物、`AppSession.folderAssignments`（P3）。
- `remoteOs` 探测与 Windows-remote 分支（P3）。
- "选 target" UI（P1）。
- 删除 `SessionPreferences` 旧字段双写（下个版本）。
