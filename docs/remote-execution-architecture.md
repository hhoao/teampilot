# 远程执行架构（Remote Execution Architecture）

> 状态：**设计稿（待评审）** · 适用范围：整体远程 / 项目远程 / 成员远程三级形态
> 关联代码：`services/storage/runtime_storage_context.dart`、`services/terminal/`、`services/team_bus/`、`models/`

本文统一 TeamPilot 中"远程"的概念，使"整体远程""项目远程""成员远程"三种形态**共享同一套抽象**，而不是三套散落的 `if` 分支。文档先描述现状与问题，再给出目标模型，最后给出数据模型变更、单例迁移清单与分期落地计划。

---

## 1. 背景与目标

### 1.1 当前能做到的
- **桌面**：默认本地 PTY + 本地文件系统；可全局切到 SSH（`ConnectionMode.ssh` + 单个 active SSH profile）。
- **Android**：强制走 SSH（控制面与工作面都在远端）。
- **WSL**：Windows 上可选 WSL 后端，distro 从 CLI 可执行路径解析。

### 1.2 要支持的三级形态
| 形态 | 含义 | 典型场景 |
|---|---|---|
| **整体远程** | 整个 App 默认在某台远程机上工作 | Android；或桌面接管一台开发服务器 |
| **项目远程** | 某个项目的文件 + 会话 + CLI 跑在远程机，其它项目本地 | 一个项目需要服务器算力/环境，其余在本地 |
| **成员远程** | 同一团队会话内，某个成员的 agent 跑在远程机，其余本地 | 把重负载成员下放到 GPU/大内存机器 |

### 1.3 设计目标
1. **单一抽象**：三级形态都是"把同一个执行位点（target）绑定到不同作用域"。
2. **可继承**：作用域解析复用仓库已有的 `app → team → project → session` 隔离习惯。
3. **渐进迁移**：每一期都能独立交付，P0 行为不变。
4. **不回退**：Android / WSL / 现有 SSH 全局模式在新模型下等价可表达。

### 1.4 已定决策（2026-06-17 评审）

1. **三级形态都做**（整体 / 项目 / 成员远程）。
2. **成员位置 = target + 工作目录**：每个成员各自设定工作目录——远程成员设远程目录、本地成员设本地目录。**不共享同一份文件系统**，成员间协作纯走 TeamBus 消息（见 §4.1）。天然契合 per-member git worktree。
3. **凭证可推送到远程主机**：远程 target 的 CLI 凭证由本地生成后物化到远程 `providers/` 树，信任边界已接受（见 §5.1）。
4. **symlink 在远程可用**（澄清纠错）：SFTP 协议支持、dartssh2 `SftpClient.link` 已实现、`SftpFilesystem.createSymlink` 已接通。**不需要**为远程强制 copy 或加 manifest 缓存；只需补 `SftpFilesystem.readSymlinkTarget`（当前恒返回 null，破坏物化幂等）。
5. **连接弹性倾向**：某远程主机掉线时，只降级该主机上的会话/成员，其余团队继续（待最终确认，见 §11）。

---

## 2. 现状：四个各自为政的全局轴

"远程"今天不是一个概念，而是**四个必须手动对齐的全局旋钮**，由一个单例 `RuntimeStorageContext` 兜底。

| 轴 | 决定 | 配置位置 | 作用域 | 运行时可切 |
|---|---|---|---|---|
| Storage backend（native/wsl/ssh） | 文件系统在哪 | `RuntimeStorageContext.install()` (`runtime_storage_context.dart:55`) | App 全局（单例，启动装一次） | 是，经 `reinstallStorageContext()` |
| Connection mode（localPty/ssh） | CLI 进程在哪跑 | `SessionPreferences.connectionMode` (`session_preferences.dart:58`) | App 全局（SharedPrefs） | 是，`setConnectionMode()` |
| SSH profile（active） | 连哪台远程机 | `ssh-profiles/selected_profile.txt` (`ssh_profile_repository.dart`) | App 全局，单选 | 是，`selectProfile()` |
| WSL distro | 哪个发行版 | 从 claude 可执行路径解析 (`runtime_storage_context.dart:252` `parseWslDistro`) | App 全局 | 仅随可执行路径变化 |

### 2.1 关键耦合与缺口
- **同一事实被推导两遍**：`isSshMode` 在 `app_shell.dart:226` 与 `connection_mode_service.dart:19` 各算一次——本质上这四个轴是"一台机器"的不同侧面，却被拆开。
- **传输与存储分家**：`RuntimeStorageContext` 拥有 filesystem，但 transport（PTY/SSH）由 `ConnectionMode` 在 `chat_session_shell_factory.dart` 另行决定。对 ssh/wsl 来说"文件在哪"和"进程在哪"本是同一台机，却没有统一持有者。
- **项目/会话无处声明 host**：`AppProject`（`app_project.dart:46`）与 `AppSession`（`app_session.dart:66`）只存 `primaryPath` 字符串，**没有任何 host/target 字段**，全靠当前全局后端解释路径。
- **成员只有 `cli`/`effort` 覆盖**：`TeamMemberConfig`（`team_config.dart`）无传输/host 覆盖字段。
- **单例**：`RuntimeStorageContext._current` 是全局唯一，天然无法让两个项目/成员同时落在不同后端。

---

## 3. 核心抽象：`RuntimeTarget`（执行位点）

把"文件在哪 + 进程在哪 + 连哪台 + 哪个 distro"折成**一个值**。对 local/wsl/ssh 来说，文件系统与进程传输天然同机，因此由同一个 target 同时提供二者。

```dart
enum RuntimeKind { local, wsl, ssh }

class RuntimeTarget {
  final String id;            // 'local' | 'wsl:Ubuntu' | 'ssh:<profileId>'
  final String label;         // UI 显示名
  final RuntimeKind kind;
  final String? sshProfileId; // kind == ssh
  final String? wslDistro;    // kind == wsl

  // 派生（由 RuntimeContextRegistry 物化，见 §6）：
  //   Filesystem   fs        — Local / Wsl / Sftp
  //   Transport    transport — LocalPty / SshPty
  //   String       appDataRoot / workDirBase
}
```

- `RuntimeTarget` 本质就是今天 `RuntimeStorageContext` 算出来的东西，**外加 transport 的归属**。统一后 `ConnectionMode`/`StorageBackendMode`/active profile/wsl distro 不再是四个独立旋钮，而是 `RuntimeTarget` 的字段。
- **`local` 与 `wsl:*` 是隐式条目**（按平台自动存在）；`ssh:*` 由现有 `ssh_profiles/` 升级而来的 **targets 注册表**提供。即：现有 `SshProfile` 列表 → 通用 target 列表的一个子集。

### 3.1 与现有类型的映射
| 现有 | 新 |
|---|---|
| `StorageBackendMode.native` + `ConnectionMode.localPty` | `RuntimeKind.local` |
| `WindowsStorageBackend.wsl` + distro | `RuntimeKind.wsl(distro)` |
| `ConnectionMode.ssh` + active `SshProfile` | `RuntimeKind.ssh(profileId)` |

`RuntimeStorageContext.resolve()` 的平台判定逻辑（`runtime_storage_context.dart:82`）整体迁入"由 `RuntimeTarget` 物化上下文"的工厂，不再从分散的 preferences 推导。

---

## 4. 作用域分层与解析

三级远程 = **同一个 target 绑在不同作用域**，解析时自下而上继承：

```
member.targetId
  ?? project.targetId
  ?? team.targetId          // 预留，当前不暴露 UI
  ?? app.defaultTargetId    // home target
```

```
            ┌─────────────────────────────────────────┐
 app.default│  home target (桌面=local, Android=ssh:..)│  ← 控制面永远在这
            └─────────────────────────────────────────┘
                 ▲            ▲                ▲
       team.target?    project.target?   member.target?
       (预留)          ← 项目远程         ← 成员远程
```

| 形态 | 绑定点 | 解析结果 |
|---|---|---|
| 整体远程 | `app.defaultTargetId = ssh:hostA` | 全员继承 hostA（≈ 今天 + Android） |
| 项目远程 | `AppProject.targetId = ssh:hostA` | 该项目工作面/会话/CLI 在 hostA，其它项目本地 |
| 成员远程 | `TeamMemberConfig` 设成员位置（target+dir） | 同会话内该成员在 hostA 自己的目录，其余沿用上层解析 |

> **Android 校验**：Android = `app.defaultTargetId` 指向某个 `ssh:*`、无任何下层覆盖。模型必须保证这等价于今天的强制 SSH（包括控制面落在远端，见 §5）。

### 4.1 成员位置与跨主机协作语义

成员的绑定单位不是单纯一个 `targetId`，而是**成员位置 = `targetId` + `workingDir`**：每个成员各设工作目录，远程成员设远程目录、本地成员设本地目录，两者缺省都继承项目。

由此**跨主机"共享文件系统"的难题被消解**——成员之间**不假装共享同一份盘**：

- 协作纯走 **TeamBus 消息**（这本就是总线的语义：消息协调，而非共享内存）。文件交接走显式产物 / git，而非同一份字节。
- lead 在本地、成员在 hostA 时，二者工作目录是各自主机上的不同目录，互不干扰。
- 若要"全员看同一份代码"，用**项目远程**（全员同机、共享该机 fs），而非把单个成员甩到异机。
- 附带：即便全员本地，per-member 工作目录天然支持每成员一个 **git worktree**，互不踩。

> 今天全员共用 `session.primaryPath` 作工作目录（`session_lifecycle_service.dart:284`）的假设要改为"每成员解析自己的工作目录"。

---

## 5. 控制面 vs 工作面：存储职责拆分

这是**项目远程的真正难点**。今天所有 app 元数据（`teams/`、项目 manifest、`ssh_profiles/`、`ui/`、`cli-defaults/`）和项目工作文件挤在同一个 `appDataRoot`。一旦项目能各自远程，不能让全部元数据跟着某个项目的远程机走。

拆成两类存储：

| 存储面 | 内容 | 落点 |
|---|---|---|
| **控制面（control plane）** | 团队/项目目录、target 注册表、UI 状态、CLI 默认 | 永远在 **home target**（桌面=local，Android=app.default 的 ssh） |
| **工作面（workspace plane）** | 项目工作目录、`sessions/{id}/runtime/`、CLI 执行 | 跟随**解析出的 target** |

含义：
- App 永远能读自己的目录（即便某项目远程机离线，项目列表仍可见）。
- `AppStorage.fs` 不再是"唯一全局"；它默认指向 home target（控制面），而项目/会话级操作走各自解析出的上下文（工作面）。
- `WorkspaceLayout` / `RuntimeLayout` 需要区分"控制面路径"（home）与"工作面路径"（按 target）。

> 这一步是 P2 的核心，也是从单例迈向多上下文的分水岭。

### 5.1 物化必须落到"解析出的 target"那台机

CLI 运行时树是**按 launch 惰性物化**的（`ConfigProfileService` / `ResourceProvisioningService.provisionForLaunch`），这点对远程友好——只要把物化的 fs 从全局换成"成员/项目解析出的 target 的 fs"即可。但有几处必须随 target 走：

- **skills/plugins 链接**：在**该 target 主机内部**把 skills/plugins 链进 session 运行时树。symlink 在远程可用（见 §1.4 决策 4），源与目标同在该机 app-data 树内，不跨主机。仅需补 `SftpFilesystem.readSymlinkTarget` 以恢复 `ResourceMaterializer` 的幂等判断（否则每次 launch 重链/重拷）。
- **凭证物化到远程**：凭证仍由本地生成（登录/导出流程 `Process.run` 在本地跑），随后**把凭证文件物化到远程 target 的 `providers/{tool}/` 树**，并把链接 target 的绝对路径按**远程 app-data root** 重算（今天是本地绝对路径，跨机失效）。信任边界：密钥会落到远程主机，已确认接受。
- **provisioning 性能**：SFTP 上一堆小文件写较慢；首 launch 用内容哈希 / manifest 跳过未变更的子树，避免每次全量重铺。

---

## 6. 去单例：`RuntimeContextRegistry`

`RuntimeStorageContext._current` 单例 → 按 target 缓存的注册表：

```dart
class RuntimeContextRegistry {
  RuntimeContext home();                       // 控制面（app.defaultTargetId）
  Future<RuntimeContext> forTarget(String id); // 工作面，按需物化 + 缓存
  Future<void> dispose(String id);             // 远程断开/项目关闭时回收
}

class RuntimeContext {       // 即今天 RuntimeStorageContext 的"实例化"形态
  Filesystem get fs;
  Transport  get transport;
  String     get appDataRoot;
  AppPaths   get paths;
}
```

- 物化逻辑复用现有 `RuntimeStorageContext.resolve()` 的平台分支，只是**入参从全局 preferences 变成具体 `RuntimeTarget`**。
- SSH target 的 `SSHClient` 由注册表持有并复用（多个项目/成员连同一台机时共享连接）。
- `StorageRoots`（`storage_resolver.dart`）从"全局快照"变成"按上下文的快照"，失效触发从 active-profile 变更扩展到 target 解析变更。

---

## 7. 协调面：成员远程的反向隧道

TeamBus 仍是**本地进程内**（`team_bus.dart:27`），MCP 绑死 `127.0.0.1`（`teammate_bus_mcp_server.dart:31`）。成员远程**不需要把总线分布式化**，只需让远程成员够得着本地总线：

```
本地 App 进程
  ├─ TeamBus (in-process)
  └─ teammate-bus MCP @ 127.0.0.1:PORT
              ▲
              │ SSH remote port forward（反向隧道）
              │ 远程 127.0.0.1:PORT → 本地 127.0.0.1:PORT
   远程机 ────┘
     └─ 成员 CLI：MCP 配置照写 127.0.0.1:PORT → 透回本地总线
```

> **现状（2026-06-17 核查）：Android 的 mixed/TeamBus 模式当前是坏的。** mixed 模式无平台 gate（`session_launch_service.dart:176`），但 MCP 端点写死 `127.0.0.1`（`teammate_bus_mcp_server.dart:22`）并经 SFTP 写到远程主机 fs，远程成员读到的是**它自己那台机的 loopback**，连不回手机上的总线。`session_launch_service.dart:609` 注释承认了此问题但所谓 "fallback to HTTP" 仍是 127.0.0.1，未真正解决。**本工作的反向隧道既启用桌面成员远程，又一并修复当前损坏的 Android mixed 模式**——二者是同一拓扑（总线在本地、成员 CLI 在远程主机）。注：native 团队模式在 Android 上正常，因为它不用总线/MCP。

机制（净新增，无现成可复用）：
- **门铃/stdin 注入不用动**：注入发生在本地 `shell.writeln()`（`tab_team_bus_coordinator.dart:180`），shell 对象在本地、写进 SSH 通道即可送达远程成员。
- **端口自协商免冲突**：`forwardRemote(port: 0)` 让远程 SSH server 自选空闲端口 → 由 `SSHRemoteForward.port` 拿到实际绑定端口 → 把 `127.0.0.1:<该端口>` 注入**该成员**的 MCP 配置（HTTP transport，不用把 bridge 送远程，无需改 endpoint 生成逻辑）。
- **隧道泵**：App 侧消费 `SSHRemoteForward.connections` 流，每来一个 `SSHForwardChannel` 就对接本地 MCP socket（即 dartssh2 `example/forward_remote.dart` 模式）。
- 隧道生命周期挂在该成员 session 上，断开时回收（与 §6 的 `dispose` 协同）。
- 前置条件：远程 SSH server 允许 TCP forwarding（OpenSSH `AllowTcpForwarding` 默认开；绑 loopback 不需 `GatewayPorts`）。

> 整体远程/项目远程若**全员同机**，同一反向隧道方案让那台机上的成员连回本地总线即可（Android 即此情形）。

---

## 8. 端到端解析时序（启动一个会话/成员）

```
openSessionTab / scheduleMemberConnect
  → 解析 targetId = member ?? project ?? team ?? app.default      // §4
  → ctx = RuntimeContextRegistry.forTarget(targetId)             // §6
        ├─ local : LocalFilesystem + LocalPty
        ├─ wsl   : WslFilesystem(distro) + wsl exec
        └─ ssh   : 复用/新建 SSHClient → SftpFilesystem + SshPty
  → 若 ssh 且需协调：建立反向隧道，MCP endpoint=127.0.0.1:PORT    // §7
  → SessionLifecycleService.prepareLaunch(workDir = 工作面解析)    // §5
  → TerminalSession.connect(ctx.transport)
```

控制面读写（项目列表、团队配置）始终走 `registry.home()`，与上面无关。

---

## 9. 数据模型变更清单

| 模型 | 变更 | 期 |
|---|---|---|
| 新增 `RuntimeTarget` + `RuntimeKind` | 见 §3 | P0 |
| 新增 targets 注册表（升级 `ssh_profiles/`） | `SshProfile` 成为 ssh-kind target 的载荷 | P0 |
| `SessionPreferences` | `connectionMode`/`windowsStorageBackend` → `defaultTargetId`（保留迁移读旧字段） | P0/P1 |
| `AppProject` (`app_project.dart`) | + `String? targetId` | P2 |
| `AppSession` (`app_session.dart`) | + `String? targetId`（会话快照，便于 resume 时定位） | P2 |
| `TeamMemberConfig` (`team_config.dart`) | + **成员位置**：`String? targetId` + `String? workingDir`（缺省继承项目，见 §4.1） | P3 |
| `TeamConfig` | + `String? targetId`（预留团队远程，可暂不出 UI） | P3 |

**兼容**：所有 `targetId` 为 `null` ⇒ 继承上层 ⇒ 旧数据等价于"全员 app.default"。旧 `connectionMode/ssh profile` 在加载时映射成 `defaultTargetId`。

---

## 10. 单例迁移清单（P2 重点）

1. `RuntimeStorageContext` 静态单例 → 可实例化 `RuntimeContext` + `RuntimeContextRegistry`。
2. `AppStorage.fs/cwd/paths` 全局访问 → 默认转发 `registry.home()`；新增按上下文取用的入口。
3. `WorkspaceLayout` / `RuntimeLayout` 拆控制面/工作面路径解析。
4. `StorageRoots` 快照从全局改为按上下文缓存 + 失效。
5. `app_shell.dart` 的 `install()` / `reinstallStorageContext()` / `reloadRemoteBackedAppData()` 改为：装配 home + 注册表，而非切换全局后端。
6. 审计所有直接读 `RuntimeStorageContext.current` 的点（尤其 CLI 注册表 provisioning、`CliBootstrap`），明确各自属于控制面还是工作面。
7. **堵掉绕过 fs 抽象的裸 `dart:io`**：`runtime_layout.dart:379` `Directory().list()`、`:404` `resolveSymbolicLinks()` 等假设本地盘的调用，改走 `Filesystem` 接口，否则远程 context 一用即崩。
8. **补 `SftpFilesystem.readSymlinkTarget`**（当前恒 null）：恢复 `ResourceMaterializer` 的物化幂等，避免远程每次 launch 重链/重拷。
9. **凭证物化随 target**（见 §5.1）：本地生成 → 物化到远程 `providers/`，链接 target 按远程 root 重算。

---

## 11. 风险与开放问题

- **连接弹性（倾向已定，待最终确认）**：某远程 target 主机掉线时，**只降级该主机上的会话/成员，其余团队继续**（§1.4 决策 5）。注册表持有多个 `SSHClient`，需要心跳/重连/超时、per-target 连接状态 UI、掉线后会话可 resume。今天是"单连接掉=全 App 降级"，需改为按 target 隔离。
- **跨机协调边界**：成员远程的反向隧道方案假设"总线在本地、成员够得着即可"。若未来要"无本地 App 常驻、纯远程团队自治"，则需把总线本身做成可独立部署的 broker——本设计**显式不纳入**，避免过度工程。
- **控制面在远端（Android）时的 home target**：home 也可能是 ssh。需确认 §5 的"控制面永远在 home"在 Android 下与今天 `RemoteSshStoragePathResolver` 行为一致。
- **路径语义 / resume**：跨 target 的工作目录相对各自后端解释；`AppSession` 存 target 快照以便 resume 时正确定位；transcript probe、`--session-id`/`--resume` 路径按成员 target 的 fs 解析。**成员位置在配置时确定，不做跨 target 迁移**（要换主机即改配置/重建，不设自动迁移逻辑）。
- **WSL 与 SSH 共存**：Windows 上同时存在 wsl target 与 ssh target 时，distro 解析不能再依赖"从 claude 可执行路径解析"的隐式方式，应显式落进 wsl target 字段（P0 顺手清理）。
- **远程目录选择 UX**：成员/项目设远程工作目录需要一个**远程目录浏览器**（基于 SFTP listDir），不能只靠手填路径。

---

## 12. 分期与验收点

| 期 | 目标 | 核心改动 | 验收点 | 解锁 |
|---|---|---|---|---|
| **P0** 重构（行为不变） | 四旋钮 → `RuntimeTarget` + targets 注册表 | §3、§9 前半；单 target = 今天行为 | 现有 local/wsl/ssh/Android 全路径回归通过；`isSshMode` 单一来源 | 消除耦合 |
| **P1** 整体远程收尾 | app 默认 target 切换 | 清理 `install/reinstall`；UI 从"选 profile"升级为"选 target" | 桌面一键在 local↔ssh↔wsl 间切默认；Android 等价归一 | 整体远程 |
| **P2** 去单例 | 控制面/工作面拆分 + 注册表 | §5、§6、§10；`AppProject.targetId` | 两个项目同时分别落 local 与 ssh，互不影响；远程机离线时项目列表仍可读 | **项目远程** |
| **P3** 成员远程 | 成员位置（target+dir）+ 反向隧道 | §4.1、§7；`TeamMemberConfig` 成员位置；按成员传输 + 各自工作目录 | 混合团队会话中单成员在远程机自己的目录跑，门铃/读信/协调正常 | **成员远程** |

P0/P1 风险低、顺手修掉现有耦合；P2 是分水岭（动存储单例）；P3 最重，建立在 P2 之上。

---

## 附：关键代码索引

| 主题 | 位置 |
|---|---|
| 存储后端装配 | `services/storage/runtime_storage_context.dart`（`install:55`、`resolve:82`、`parseWslDistro:252`） |
| 存储路径解析/快照 | `services/storage/storage_resolver.dart`、`workspace_layout.dart`、`runtime_layout.dart` |
| 连接模式 | `models/connection_mode.dart`、`models/session_preferences.dart:58`、`services/app/connection_mode_service.dart` |
| SSH profile | `models/ssh_profile.dart`、`repositories/ssh_profile_repository.dart`、`cubits/ssh_profile_cubit.dart` |
| 传输选择 | `cubits/chat/chat_session_shell_factory.dart`、`services/terminal/terminal_transport_factory.dart`、`ssh_pty_transport.dart` |
| 项目/会话模型 | `models/app_project.dart:46`、`models/app_session.dart:66` |
| 成员模型 | `models/team_config.dart`（`TeamMemberConfig`） |
| 启动时序 | `services/session/session_lifecycle_service.dart`、`cubits/chat/session_launch_service.dart` |
| TeamBus / MCP | `services/team_bus/team_bus.dart:27`、`team_bus/mcp/teammate_bus_mcp_server.dart:31`、`cubits/chat/tab_team_bus_coordinator.dart:180` |
| Bootstrap | `app/app_shell.dart`（`install:225`、`reinstallStorageContext`、`reloadRemoteBackedAppData`） |
