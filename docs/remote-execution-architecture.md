# 远程执行架构（Remote Execution Architecture）

> 状态：**设计稿（待评审）** · 适用范围：目录远程（每目录带 target）+ home target（控制面默认）；整体 / 项目 / 成员远程是其不同粒度
> 关联代码：`services/storage/runtime_storage_context.dart`、`services/terminal/`、`services/team_bus/`、`models/`

> **数据模型已修订（2026-06-18）。** 机器（target）挂在**目录**上、成员位置 = 启动时的目录分配。**本文 §4 / §9 即数据模型权威**（原独立的 2026-06-18 workspace-folders spec 已不在仓库）。**命名以代码现实为准（2026-06-22 核对）**：实体是 `Workspace`（`models/workspace.dart`，字段 `workspaceId`），目录类型 `WorkspaceFolder`；旧称 `AppProject` / `ProjectFolder` 已过时。§3 / §5 / §6 / §7 的机制（`RuntimeTarget`、控制面/工作面、反向隧道）不变。

本文统一 TeamPilot 中"远程"的概念，使"整体远程""项目远程""成员远程"三种场景归结到**同一套抽象**——工作面的**目录远程**（每个目录带 `target`）加控制面的 **home target**——而不是三套散落的 `if` 分支。文档先描述现状与问题，再给出目标模型，最后给出数据模型变更、单例迁移清单与分期落地计划。

---

## 1. 背景与目标

### 1.1 当前能做到的
- **桌面**：默认本地 PTY + 本地文件系统；可全局切到 SSH（`ConnectionMode.ssh` + 单个 active SSH profile）。
- **Android**：强制走 SSH（控制面与工作面都在远端）。
- **WSL**：Windows 上可选 WSL 后端，distro 从 CLI 可执行路径解析。

### 1.2 要支持的场景

工作面只有一个原语——**目录远程**：每个目录（`WorkspaceFolder`）各带机器（`targetId`）。下面这些"形态"是它在不同粒度上的呈现，**不是三套独立机制**：

| 场景 | 在模型里 = 什么 | 典型 |
|---|---|---|
| **整体远程** | **home target（App 自身所在机）的 kind 是 `ssh:*`** —— 控制面 + 新建目录默认都随它，故"全 App 在远程" | Android（home 强制 ssh） |
| **项目远程** | 工作区**所有目录**同一 target（目录远程的"全同"特例） | 整个项目要服务器算力/环境 |
| **成员远程** | 工作区目录**跨机** + 启动时成员→目录分配（目录远程的"混合"形态） | 把重负载成员下放到 GPU/大内存机器 |

> 用户实际只配两样——**每个目录在哪台机**（工作面，目录远程）和 **home/默认 target**（控制面，整体远程）。"项目远程""成员远程"都只是目录机器的不同均匀度，不是新功能。

### 1.3 设计目标
1. **单一抽象**：机器 = 一个执行位点（`RuntimeTarget`）。三级形态都由"一个 home target（控制面）+ 每个目录各自的 target（工作面）"涌现，而非三套散落的 `if` 分支。
2. **机器挂目录**：唯一的作用域层是 home target；其余机器信息挂在 `WorkspaceFolder` 上，成员通过"被分到哪个目录"获得机器，不分 project/team/member 层。
3. **渐进迁移**：每一期都能独立交付，P0 行为不变。
4. **不回退**：Android / WSL / 现有 SSH 全局模式在新模型下等价可表达。

### 1.4 已定决策（2026-06-17 评审）

1. **三级形态都做**（整体 / 项目 / 成员远程）。
2. **成员位置 = 启动时分到的目录**（修订自原"target + 工作目录"）：每个成员分到一组同机目录，远程成员的目录在远程、本地成员的在本地。**不共享同一份文件系统**，成员间协作纯走 TeamBus 消息（见 §4.1）。天然契合 per-member git worktree。
3. **凭证可推送到远程主机**：远程 target 的 CLI 凭证由本地生成后物化到远程 `providers/` 树，信任边界已接受（见 §5.1；落地建议 per-target 显式 opt-in，见 §11）。
4. **symlink 在远程可用**（澄清纠错；限 **POSIX/SFTP 远程**）：SFTP 协议支持、dartssh2 `SftpClient.link` 已实现、`SftpFilesystem.createSymlink` 已接通。POSIX 远程**不需要**强制 copy 或加 manifest 缓存；只需补 `SftpFilesystem.readSymlinkTarget`（当前恒返回 null，破坏物化幂等）。**Windows 远程例外**：symlink 不可靠，继承退化为 copy（2026-06-22 决定支持 Windows 远程，见 §3 / §5.2）。
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
- **项目/会话无处声明 host**：`Workspace`（`models/workspace.dart`）与 `AppSession`（`app_session.dart:66`）只存 `primaryPath` 字符串，**没有任何 host/target 字段**，全靠当前全局后端解释路径。
- **成员只有 `cli`/`effort` 覆盖**：`TeamMemberConfig`（`team_config.dart`）无传输/host 覆盖字段。
- **单例**：`RuntimeStorageContext._current` 是全局唯一，天然无法让两个项目/成员同时落在不同后端。

---

## 3. 核心抽象：`RuntimeTarget`（执行位点）

把"文件在哪 + 进程在哪 + 连哪台 + 哪个 distro"折成**一个值**。对 local/wsl/ssh 来说，文件系统与进程传输天然同机，因此由同一个 target 同时提供二者。

```dart
enum RuntimeKind { local, wsl, ssh }

enum RemoteOs { posix, windows }   // ssh target 在 connect 时探测

class RuntimeTarget {
  final String id;            // 'local' | 'wsl:Ubuntu' | 'ssh:<profileId>'
  final String label;         // UI 显示名
  final RuntimeKind kind;
  final String? sshProfileId; // kind == ssh
  final String? wslDistro;    // kind == wsl
  final RemoteOs? remoteOs;   // kind == ssh：连上后探测，决定 fs/shell/relay/symlink 分支

  // 派生（由 RuntimeContextRegistry 物化，见 §6）：
  //   Filesystem   fs        — Local / Wsl / Sftp
  //   Transport    transport — LocalPty / SshPty
  //   String       appDataRoot / workDirBase
}
```

- `RuntimeTarget` 本质就是今天 `RuntimeStorageContext` 算出来的东西，**外加 transport 的归属**。统一后 `ConnectionMode`/`StorageBackendMode`/active profile/wsl distro 不再是四个独立旋钮，而是 `RuntimeTarget` 的字段。
- **远程 OS 不限 POSIX**：ssh target 在 connect 时探测 `remoteOs`。Windows 远程在几处走不同分支——symlink 继承退化为 copy（§5.2）、relay 用 windows 静态二进制（§7.1）、登录 shell / 路径语义不同（§5.3）。其余抽象（控制面/工作面、隧道、物化）不变。
- **`local` 与 `wsl:*` 是隐式条目**（按平台自动存在）；`ssh:*` 由现有 `ssh_profiles/` 升级而来的 **targets 注册表**提供。即：现有 `SshProfile` 列表 → 通用 target 列表的一个子集。

### 3.1 与现有类型的映射
| 现有 | 新 |
|---|---|
| `StorageBackendMode.native` + `ConnectionMode.localPty` | `RuntimeKind.local` |
| `WindowsStorageBackend.wsl` + distro | `RuntimeKind.wsl(distro)` |
| `ConnectionMode.ssh` + active `SshProfile` | `RuntimeKind.ssh(profileId)` |

`RuntimeStorageContext.resolve()` 的平台判定逻辑（`runtime_storage_context.dart:82`）整体迁入"由 `RuntimeTarget` 物化上下文"的工厂，不再从分散的 preferences 推导。

---

## 4. 解析模型：home target + 每目录 target

**home target = App 自身所在的机器**——控制面数据（`teams/`、项目 manifest、`ui/`、`ssh_profiles/`、`cli-defaults/`）落在这、App 进程在这跑，且**新建目录默认随它**。它只有一个、永远在线（桌面=`local`，Android=`ssh:*`，即今天 `RuntimeStorageContext` 那个全局单例算出来的东西）。

机制上**只有两种 target 绑定**：唯一特权的 home target，加每个目录各自的 target。其余机器信息**挂在目录上**：`Workspace` 的每个 `WorkspaceFolder` 各带 `targetId`，因此一个工作区可"混合"（目录跨机）。成员不直接持有 target，而是**启动时被分配到目录**，从而获得机器：

```
member 的机器 = 其所分配目录(WorkspaceFolder)的 targetId
              ↑ 启动时分配，存 AppSession.folderAssignments
兜底          = app.defaultTargetId (home target)
```

```
            ┌─────────────────────────────────────────┐
 app.default│  home target (桌面=local, Android=ssh:..)│  ← 控制面永远在这；唯一的作用域层
            └─────────────────────────────────────────┘

  工作面机器全部来自目录（无 project / team / member 层）：
    WorkspaceFolder { path, targetId }   ← 机器挂在目录上
    AppSession.folderAssignments       ← 启动时把成员分到目录 → 成员获得机器
```

三级形态不再是三个并列的绑定点，而是同一机制的**涌现描述**：

| 形态（用户视角） | 机制实现 | 解析结果 |
|---|---|---|
| 整体远程 | `app.defaultTargetId = ssh:hostA` | 控制面 + 默认工作面在 hostA（≈ 今天 + Android） |
| 项目远程 | 一个工作区的**所有目录**共用 `ssh:hostA` | 该工作区全员同机、共享 hostA fs；其它工作区不受影响 |
| 成员远程 | **mixed 工作区**（目录跨机）+ 启动时分配 | 被分到 hostA 目录的成员在 hostA，被分到本地目录的成员在本地 |

> **Android 校验**：Android = `app.defaultTargetId` 指向某个 `ssh:*`。单机工作区下全员落该 ssh（包括控制面，见 §5），等价于今天的强制 SSH；mixed 工作区下每个成员按其目录解析（这也是 §7 反向隧道必须修好 Android mixed 的原因）。

### 4.1 成员位置与跨主机协作语义

成员的位置 = **它被分到的目录**（启动时分配，存 `AppSession.folderAssignments`，**不存在 team 上**）：每个成员分到一组目录（必须同机），第一个是工作目录、其余作 `--add-dir`，缺省继承工作区主目录。一个成员**只能被分到同一台机上的目录**（一个 agent 一台机）。

由此**跨主机"共享文件系统"的难题被消解**——成员之间**不假装共享同一份盘**：

- 协作纯走 **TeamBus 消息**（这本就是总线的语义：消息协调，而非共享内存）。文件交接走显式产物（机制见 §4.2）/ git，而非同一份字节。
- lead 在本地、成员在 hostA 时，二者工作目录是各自主机上的不同目录，互不干扰。
- 若要"全员看同一份代码"，用**项目远程**（工作区所有目录同机、共享该机 fs），而非把单个成员甩到异机。
- 附带：即便全员本地，per-member 工作目录天然支持每成员一个 **git worktree**，互不踩。

> 今天全员共用 `session.primaryPath` 作工作目录（`session_lifecycle_service.dart:284`）的假设要改为"每成员按其目录分配解析自己的工作目录"。

### 4.2 跨机文件交接（bus 中介的产物传输）

§4.1 说"文件交接走显式产物"——这里给它具体机制。成员不共享盘，但**本地 App 是唯一同时够得着两边文件系统的进程**（本地 fs + 各远程 target 的 SFTP，见 §6 注册表）。故文件交接由 **bus 记句柄、App 搬字节**：

- **发布**：成员 A 调 teammate-bus 的 `publish_artifact(path, name)`（`path` 在 A 自己机上）。bus 只记一个**句柄**（member / machine / path / name），**不把文件塞进消息**（消息是 JSON，大文件走旁路）。
- **通知**：bus 给相关成员发"产物 `name` 可取"。
- **拉取**：成员 B 调 `fetch_artifact(name, destPath)`（`destPath` 在 B 自己机上）。App 用 A 的 target fs 读、B 的 target fs 写（本地读/SFTP 读 → 本地写/SFTP 写），拷到 B 机上并回执最终落点。

要点：

- **没有成员直接碰对方盘**——全由 App 经两边 fs 搬运，契合"消息协调 + App 搬字节"。
- **拉取式（pull）** 优于推送：大文件惰性传、B 自选落点、避免不请自来的写入。
- **双远程跨机**（A 在 hostX、B 在 hostY）：App 从 hostX SFTP 读、向 hostY SFTP 写，经本地中转一跳（可接受；将来要省一跳可加 host-to-host scp，非默认）。
- **大文件走旁路 + 流式**：绝不 base64 进 bus 消息；只有句柄/元数据走消息，字节由 App 流式拷贝，带进度与大小上限。
- **边界**：写入对方机限定在该 session 的 inbox 目录（如 `…/runtime/members/{B}/inbox/`），受 per-target 信任约束。

能力面：新增 teammate-bus MCP 工具 `publish_artifact` / `fetch_artifact` / `list_artifacts`，能力化（每 CLI 一致，见 AGENTS.md）。

已定（2026-06-22）：
- **单文件为核心**，`fetch_artifact` 一次一文件。**目录/树走 tar 流**作为后续增量（`publish_artifact` 标 `kind: dir` → App 在源端 tar、流式到目的端解包），不在首版。
- **落点冲突默认报错**：`destPath` 已存在则失败，需显式 `overwrite: true` 才覆盖。
- **inbox 生命周期**：产物句柄与落点是 **session 作用域**，会话结束随 runtime 树回收；另设 **TTL** 清理长期未取的句柄，避免 inbox 无限堆积。

---

## 5. 控制面 vs 工作面：存储职责拆分

这是**项目远程的真正难点**。今天所有 app 元数据（`teams/`、项目 manifest、`ssh_profiles/`、`ui/`、`cli-defaults/`）和项目工作文件挤在同一个 `appDataRoot`。一旦不同目录/项目能落到不同机器，不能让全部元数据跟着某台工作机走。

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
- **凭证物化到远程**：凭证仍由本地生成（登录/导出流程 `Process.run` 在本地跑），随后**把凭证文件物化到远程 target 的 `providers/{tool}/` 树**，并把链接 target 的绝对路径按**远程 app-data root** 重算（今天是本地绝对路径，跨机失效）。信任边界：密钥会落到远程主机，已确认接受（落地 per-target opt-in，见 §11）。
- **provisioning 性能**：SFTP 上一堆小文件写较慢；首 launch 用内容哈希 / manifest 跳过未变更的子树，避免每次全量重铺。

### 5.2 跨机的运行时树与继承

**好消息——两样已就绪：**

- per-member 运行时子树已存在：`RuntimeLayout.sessionRuntimeToolDir(workspaceId, sessionId, tool, {memberId})`（`runtime_layout.dart:78`）本就带 `memberId`，mixed 工作区里每成员一棵树按 `memberId` 区分即可。
- `RuntimeLayout` / `WorkspaceLayout` 已按 `teampilotRoot` + 注入 `fs` 参数化构造（`runtime_layout.dart:24`），天生 per-context，不是写死单例——§10 去单例因此更机械。

**真问题——继承靠"单根内 symlink"，跨机会断。** app → workspace → session 的配置继承是 symlink 物化（`runtime_layout.dart:353` `_ensureInheritedChild`）：session runtime 的 `agents/` → workspace config → `cli-defaults/{tool}/agents/`，**整条链都 join 在同一个 `teampilotRoot` 下**。而 `cli-defaults/`、workspace config 属控制面（home），远程成员的 session runtime 属工作面（工作机）——远程机上的 symlink 会指向 home 上不存在于本机的路径，**继承直接断**。

**规则：一台 target 机持有一棵自包含 app-data 子树；继承 symlink 永远在该机 `teampilotRoot` 内闭合。** 这是 §5.1 意图（"链接源与目标同在该机树内，不跨主机"）从"仅 skills/plugins/凭证"到"整条被继承 ancestry"的推广。

| 内容 | home target | 工作机（远程） |
|---|---|---|
| session 元数据（manifest、`folderAssignments`、`cliTeamName`、members[]） | ✅ 唯一权威 | ❌ 不放 |
| `cli-defaults/{tool}/`（app 默认） | ✅ 权威 | ✅ 物化副本（按 launch 惰性铺，仅用到的 tool） |
| workspace config | ✅ 权威 | ✅ 物化副本 |
| `sessions/{sId}/runtime/members/{memberId}/` | 本地成员的 | ✅ 该机成员的 |

- **物理路径**：各机同一套相对布局、只是根不同——`<machineRoot>/cli-defaults/…`、`<machineRoot>/workspace/projects/{wsId}/sessions/{sId}/runtime/members/{memberId}/…`。layout 方法全 root-relative，故"免费"成立。
- 于是一个 session 在 mixed 工作区里物理上被劈成 **home 上 1 条元数据 + 跨 N 台机的 N 棵自包含 runtime 子树**。
- **接受陈旧**：在 home 改 app 默认/workspace config **不实时同步**到远程副本，下次 launch 重物化时才更新（launch 本就是物化点，类似 build cache）。
- **Windows 远程**（`remoteOs == windows`，§3）：symlink 不可靠，继承退化为 **copy**——`_ensureInheritedChild` 现成的 copyTree 兜底正好覆盖；代价是改 app 默认后远程重物化要重拷而非重链。POSIX 远程仍走 symlink。

### 5.3 远程 target 的初始化 preflight

今天 bootstrap 是 local-first——远程几乎没有"初始化"。启动远程会话/成员前，需把前置串成显式 checklist：

```
1. 连接：registry 建/复用该 target 的 SSHClient（失败 → 该 target 不可用）
2. CLI 就位：按 target transport 探测 CLI → 缺则 SSH 安装(opt-in) → 缓存远程路径
3. app-data：确保 <remoteRoot> 存在；物化 ancestry(§5.2) + 凭证(§5.1) + skills/plugins (+ relay,§7.1)
4. bus 可达（仅协调/团队成员）：
     等本地 bus server 起来（per-session、动态口）
     → forwardRemote(0) 建反向隧道，拿 <P>
     → 写该成员 MCP 配置：经 relay 走 stdio 回连 127.0.0.1:<P>（§7.1，非裸 HTTP）
5. 远程 SSH server 前置：AllowTcpForwarding on（默认开）
```

- **CLI 缺失（Q1）**：`RemoteFlashskyaiCliLocator` 今天找不到就硬失败，且**只有 flashskyai 有远程定位器**。需 (a) 把远程定位泛化成走 target transport 的 capability、覆盖全 5 CLI；(b) 缺失且 `InstallerCapability.supportsInstaller` 时复用已有 SSH install runner 装、带进度；(c) 否则清晰报错 + per-target 手填路径。解析出的远程路径缓存到 target。
- **顺序约束**：远程协调成员的 MCP 配置依赖隧道口 `<P>`，而 `<P>` 只有 **bus 起来 + 隧道建好**后才知道。故远程成员启动序必须是 **bus → tunnel → 写 MCP 配置 → launch CLI**，不能照搬本地"先全量 provision 再起 bus"。

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
- **端口自协商免冲突**：`forwardRemote(port: 0)` 让远程 SSH server 自选空闲端口 → 由 `SSHRemoteForward.port` 拿到实际绑定端口 → 注入**该成员**的 MCP 配置指向 `127.0.0.1:<该端口>`（传输层选择见 §7.1——远程**不能裸 HTTP**）。
- **隧道泵**：App 侧消费 `SSHRemoteForward.connections` 流，每来一个 `SSHForwardChannel` 就对接本地 MCP socket（即 dartssh2 `example/forward_remote.dart` 模式）。
- 隧道生命周期挂在该成员 session 上，断开时回收（与 §6 的 `dispose` 协同）。
- 前置条件：远程 SSH server 允许 TCP forwarding（OpenSSH `AllowTcpForwarding` 默认开；绑 loopback 不需 `GatewayPorts`）。

> 整体远程/项目远程若**全员同机**，同一反向隧道方案让那台机上的成员连回本地总线即可（Android 即此情形）。

### 7.1 传输层：远程必须 stdio（不能裸 HTTP）

长阻塞的 `wait_for_message` 下，**不能让远程 CLI 直连 bus 的 HTTP**：超时由 **CLI 自己的 HTTP 客户端**强制（claude ~6min、cursor agent 层 ~60s），bus 发再多 SSE keepalive 也救不了。必须让 CLI↔bus 之间是 **stdio**。

桥/relay 必须**跑在远程**（CLI 在远程、由它 spawn 那个 stdio 子进程），经反向隧道回连本地 bus。三种接法：

| 接法 | 远程要放什么 | 超时 | 成本 |
|---|---|---|---|
| 裸 HTTP over 隧道 | 无 | ❌ CLI 客户端硬掐 | 不可用 |
| Dart stdio 桥 over 隧道 | 按 arch 编的完整桥（`teammate_bus_bridge`） | ✅ stdio 稳 | 每远程 arch 一份桥 |
| **bus raw socket + 薄 relay（推荐）** | socat/nc 或按 arch 物化的极小静态 relay | ✅ 稳 | bus 加一个 socket 传输；relay 常已预装 |

**推荐：bus 增开 raw socket 传输**（行分隔 JSON-RPC，即 stdio MCP 的线格式，复用现有 `wait_for_message` 逻辑、只换 framing 入口），远程只放一个 dumb relay：`socat STDIO TCP:127.0.0.1:<P>`（或 bundle 的微型静态 relay，随 §5.1/§5.2 物化按 arch 下发）。全程无 HTTP → 无 fetch 超时；stdio↔TCP 全持久流。反向隧道在三方案中**都不变**。

已定（2026-06-22）：

- **鉴权（必做）**：隧道的远程 `127.0.0.1:<P>` 对**该远程机所有本地用户可见**，而成员身份只是 `--member` 头——共享主机上同机用户可冒充/窃听。故 bus 为**每个 session 生成随机 token**，隧道建立时下发、注入该成员 relay 的连接参数（`--token`），bus 校验后才接受该 socket。token 随 session 失效。
- **relay 分发（分层）**：① 先探测远程主机的 `socat`/`nc`（零分发）；② 缺则用 **bundle 的微型静态 relay**，按远程 arch/OS 物化（覆盖 linux-x64/arm64、macos、**windows-x64**——Windows 远程通常没有 socat，故静态 relay 是其必需路径）；③ 都没有 → 清晰报错。
- **逐 CLI 才配 relay（§5）**：给 CLI 加一个能力位"是否长阻塞 `wait_for_message`"。长阻塞的（claude / flashskyai / codex / opencode）需要 relay；**门铃式的 cursor**（idle-at-prompt、不长阻塞）**不需要**——它远程时直接 HTTP 短请求即可，省掉 relay。能力化判定，不散落 `if (cli==)`。

---

## 8. 端到端解析时序（启动一个会话/成员）

```
openSessionTab / scheduleMemberConnect
  → 解析 targetId：成员 = 其分配目录(WorkspaceFolder)的 targetId，兜底 app.default   // §4
  → ctx = RuntimeContextRegistry.forTarget(targetId)             // §6
        ├─ local : LocalFilesystem + LocalPty
        ├─ wsl   : WslFilesystem(distro) + wsl exec
        └─ ssh   : 复用/新建 SSHClient → SftpFilesystem + SshPty
  → 若 ssh：preflight（连接 / CLI 就位 / 物化 ancestry+凭证+relay）  // §5.3
  → 若需协调：bus 起 → 反向隧道拿 <P> → 经 relay 写成员 MCP 配置     // §7.1/§7
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
| `Workspace` (`models/workspace.dart`) | `primaryPath` + `additionalPaths: List<String>` → `folders: List<WorkspaceFolder>`（每项带 `path` + `targetId`） | P2 |
| `AppSession` (`app_session.dart`) | + `folderAssignments: Map<memberId, List<folderPath>>`（启动态：成员→目录分配，便于 resume 时定位，见 §4.1） | P2/P3 |

**team 不带任何 target**：保持 machine-agnostic、可跨工作区复用；成员机器纯由启动分配决定（见 §4.1）。

**兼容**：旧 `connectionMode/ssh profile` 在加载时映射成 `defaultTargetId`。旧 `Workspace.primaryPath`+`additionalPaths` 迁移为 `folders`，每项 `targetId = 'local'`（单机工作区，等价今天）。

---

## 10. 单例迁移清单（P2 重点）

1. `RuntimeStorageContext` 静态单例 → 可实例化 `RuntimeContext` + `RuntimeContextRegistry`。
2. `AppStorage.fs/cwd/paths` 全局访问 → 默认转发 `registry.home()`；新增按上下文取用的入口。
3. `WorkspaceLayout` / `RuntimeLayout` 拆控制面/工作面路径解析。两者已按 `teampilotRoot` + 注入 `fs` 参数化（`runtime_layout.dart:24`），故改造偏机械：**按解析出的 target 各构造一个 layout（其 root + 其 fs）**，而非全局 `AppStorage.fs`。
4. `StorageRoots` 快照从全局改为按上下文缓存 + 失效。
5. `app_shell.dart` 的 `install()` / `reinstallStorageContext()` / `reloadRemoteBackedAppData()` 改为：装配 home + 注册表，而非切换全局后端。
6. 审计所有直接读 `RuntimeStorageContext.current` 的点（尤其 CLI 注册表 provisioning、`CliBootstrap`），明确各自属于控制面还是工作面。
7. **堵掉绕过 fs 抽象的裸 `dart:io`**：`runtime_layout.dart:380` `Directory().list()`、`:402` `resolveSymbolicLinks()` 等假设本地盘的调用，改走 `Filesystem` 接口，否则远程 context 一用即崩。
8. **补 `SftpFilesystem.readSymlinkTarget`**（当前恒 null）：恢复 `ResourceMaterializer` 的物化幂等，避免远程每次 launch 重链/重拷。
9. **凭证物化随 target**（见 §5.1）：本地生成 → 物化到远程 `providers/`，链接 target 按远程 root 重算。
10. **被继承的 ancestry 物化到工作机**（见 §5.2）：provision 前把 `cli-defaults/{tool}` + workspace config 铺到工作机的 `<machineRoot>`，再跑现有继承逻辑——使 `_ensureInheritedChild` 的 symlink 在该机根内闭合，不跨机。配内容哈希/manifest 跳过未变更子树。session 元数据仍只在 home。

---

## 11. 风险与开放问题

- **连接弹性（已定：要做自动重连 + 会话恢复）**：某远程 target 主机掉线时，**只降级该主机上的会话/成员，其余团队继续**（§1.4 决策 5）。注册表持有多个 `SSHClient`，需心跳/超时、**自动重连 + 掉线后会话自动 resume**（含重建反向隧道、重注 MCP 端口、重发门铃）、per-target 连接状态 UI。今天是"单连接掉=全 App 降级"，改为按 target 隔离。**单列一期 P4（见 §12）**，非"先不做"。
- **凭证推远程的信任边界**：§5.1 的凭证物化应是 **per-target 显式 opt-in + UI 明示**（而非默认把 key 铺到任何远程机）；密钥轮换需重推已 opt-in 的 N 台。
- **远程 CLI 定位缺口**：今天只有 flashskyai 有远程 locator（`RemoteFlashskyaiCliLocator`）；需泛化成走 target transport 的 capability、覆盖全 5 CLI，并接入缺失→SSH 安装 opt-in（见 §5.3 Q1）。
- **relay/token 与按-arch 分发（已定，见 §7.1）**：bus 新增 raw socket（行分隔 JSON-RPC）传输 + per-session token 鉴权；远程 relay 分层分发（探测 `socat`/`nc` → bundle 静态 relay 按 arch/OS 物化，含 windows-x64 → 报错）；relay 仅为长阻塞 CLI 配（cursor 门铃式免）。
- **非 POSIX（Windows）远程（已定要支持，见 §3）**：ssh target connect 时探测 `remoteOs`；Windows 远程在 symlink→copy（§5.2）、relay 走 windows 静态二进制（§7.1）、登录 shell/路径语义（§5.3）三处分支。其余抽象不变。远程仍**仅限 local/wsl/ssh 三 kind**，不引入新后端。
- **跨机产物传输的边界（§4.2）**：写入对方机限定 session inbox；大文件流式 + 大小上限；双远程经本地中转一跳（暂不做 host-to-host 直传）；publish/fetch 受 per-target 信任约束。
- **跨机协调边界**：成员远程的反向隧道方案假设"总线在本地、成员够得着即可"。若未来要"无本地 App 常驻、纯远程团队自治"，则需把总线本身做成可独立部署的 broker——本设计**显式不纳入**，避免过度工程。
- **控制面在远端（Android）时的 home target**：home 也可能是 ssh。需确认 §5 的"控制面永远在 home"在 Android 下与今天 `RemoteSshStoragePathResolver` 行为一致。
- **路径语义 / resume**：跨 target 的工作目录相对各自后端解释；`AppSession` 存 `folderAssignments` 快照以便 resume 时正确定位；transcript probe、`--session-id`/`--resume` 路径按成员 target 的 fs 解析。**成员位置在启动分配时确定，不做跨 target 迁移**（要换主机即重新分配/重建，不设自动迁移逻辑）。
- **WSL 与 SSH 共存**：Windows 上同时存在 wsl target 与 ssh target 时，distro 解析不能再依赖"从 claude 可执行路径解析"的隐式方式，应显式落进 wsl target 字段（P0 顺手清理）。
- **远程目录选择 UX**：成员/项目设远程工作目录需要一个**远程目录浏览器**（基于 SFTP listDir），不能只靠手填路径。

---

## 12. 分期与验收点

| 期 | 目标 | 核心改动 | 验收点 | 解锁 |
|---|---|---|---|---|
| **预备**（可独立先行，不依赖 target） | folders 值对象 | `Workspace.primaryPath`+`additionalPaths: List<String>` → `folders: List<WorkspaceFolder>`（全 `local`）；收敛 `session_repository` 那 ~6 处 `List<String>` 变异点 | 多目录工作区 + `--add-dir` 可用；旧数据无损迁移；行为不变 | 给 §9 的 `targetId` 上车铺路 |
| **P0** 重构（行为不变） | 四旋钮 → `RuntimeTarget` + targets 注册表 | §3、§9 前半；单 target = 今天行为 | 现有 local/wsl/ssh/Android 全路径回归通过；`isSshMode` 单一来源 | 消除耦合 |
| **P1** home target 收尾 | home target 归一 | 清理 `install/reinstall`；UI 从"选 profile"升级为"选 target" | Android（home=ssh）在新模型下等价归一；桌面 home 由平台定为 `local` | 整体远程（Android） |
| **P2** 去单例 | 控制面/工作面拆分 + 注册表 | §5、§6、§10；`Workspace.folders[].targetId` | 两个工作区同时分别落 local 与 ssh，互不影响；远程机离线时项目列表仍可读 | **项目远程** |
| **P3** 成员远程（**含修复现网已坏的 Android mixed**） | 启动时成员→目录分配 + 反向隧道 + 远程初始化 | §4.1/§4.2、§5.3、§7/§7.1；`AppSession.folderAssignments`；反向隧道(启用桌面成员远程 + 修复 Android mixed)；bus raw-socket 传输 + per-session token + 远程 relay 物化(仅长阻塞 CLI)；跨机产物传输 MCP；Windows 远程分支(§3) | 混合工作区单成员在远程机自己目录跑，门铃/读信/协调正常；Android mixed 消息真正送达；A↔B 跨机 publish/fetch 产物可用；POSIX 与 Windows 远程各通一条路 | **成员远程** + Android mixed 修复 |
| **P4** 连接弹性 | per-target 掉线隔离 + 自动重连/恢复 | §11 首条；心跳/超时；重连后重建隧道+重注 MCP 端口+重发门铃；掉线会话自动 resume；per-target 状态 UI | 拔掉一台远程机：仅其成员降级、自动重连后会话恢复，其余团队不受影响 | 远程**可用性**（生产级） |

预备/P0/P1 风险低、顺手修掉现有耦合；P2 是分水岭（动存储单例）；P3 最重，建立在 P2 之上；P4 把远程从"能跑"抬到"生产级可用"。

> **桌面"整体远程"（把 home/控制面也搬到 ssh 服务器）暂不做**：那等于把项目列表/团队配置都挪到远程，更像多设备同步需求，且引入"桌面控制面离线"失败模式。桌面的一切远程在 **folder 层**表达（项目/成员远程，home 仍 `local`）。将来真有"桌面接管开发服务器当 home"的需求再加，不占 P1。

---

## 附：关键代码索引

| 主题 | 位置 |
|---|---|
| 存储后端装配 | `services/storage/runtime_storage_context.dart`（`install:55`、`resolve:82`、`parseWslDistro:252`） |
| 存储路径解析/快照 | `services/storage/storage_resolver.dart`、`workspace_layout.dart`、`runtime_layout.dart` |
| 连接模式 | `models/connection_mode.dart`、`models/session_preferences.dart:58`、`services/app/connection_mode_service.dart` |
| SSH profile | `models/ssh_profile.dart`、`repositories/ssh_profile_repository.dart`、`cubits/ssh_profile_cubit.dart` |
| 传输选择 | `cubits/chat/chat_session_shell_factory.dart`、`services/terminal/terminal_transport_factory.dart`、`ssh_pty_transport.dart` |
| 工作区/会话模型 | `models/workspace.dart`、`models/app_session.dart:66` |
| 成员模型 / 位置 | `models/team_config.dart`（`TeamMemberConfig`，machine-agnostic）；成员位置存 `models/app_session.dart`（`folderAssignments`，见 §4.1） |
| 启动时序 | `services/session/session_lifecycle_service.dart`、`cubits/chat/session_launch_service.dart` |
| TeamBus / MCP | `services/team_bus/team_bus.dart:27`、`team_bus/mcp/teammate_bus_mcp_server.dart:31`、`cubits/chat/tab_team_bus_coordinator.dart:180` |
| Bootstrap | `app/app_shell.dart`（`install:225`、`reinstallStorageContext`、`reloadRemoteBackedAppData`） |
