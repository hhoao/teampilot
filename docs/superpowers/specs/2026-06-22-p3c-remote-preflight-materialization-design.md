# 远程执行架构 · P3c 设计稿（远程 preflight + CLI 定位泛化 + 物化到工作机）

> 状态：**已澄清待实现** · **最优终态、零向后兼容** · POSIX 优先 · 建立在分支 `feat/p3-member-remote`（63aec9b，预备+P0+P1+P2+P3a+P3b 已提交）之上
> 上游设计：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §5.1 物化到解析 target、§5.2 跨机运行时树与继承、§5.3 远程 preflight checklist、§10 第2/8/9/10 项、§11 远程 CLI 定位/凭证信任边界
> 决策来源：2026-06-22 用户就 P3c 的 Q1–Q5 拍板（一体交付、5 CLI locate+手填+opt-in 安装、凭证 per-target opt-in 默认关、哈希 manifest 跳过、不含远程目录浏览器）

## 0. 目标与边界

**解锁**：成员落在**异于 home 的远程机**也能端到端启动（P3b 只覆盖"成员在 home 机/home ssh"）。三件套**一体交付**（缺一不可才能远程成员起来且能认证）：

1. **远程 preflight checklist**（§5.3）：连接 → CLI 就位 → app-data 物化 → bus 可达（顶接 P3b 隧道）。
2. **CLI 定位泛化**：今天仅 `RemoteFlashskyaiCliLocator`；泛化成走 target transport 的 capability、覆盖全 5 CLI；缺失且支持安装器 → **opt-in** SSH 安装（带进度）；否则 per-target 手填路径 / 清晰报错。
3. **物化随 target 走**（§5.1/§5.2）：ancestry（`cli-defaults/{tool}` + workspace config）铺到工作机 `<machineRoot>` 使继承 symlink 在该机根内闭合；skills/plugins 在该机内链接；凭证本地生成 → **per-target opt-in** 物化到远程 `providers/`、链接 target 按远程 root 重算；内容哈希/manifest 跳过未变子树。

**明确不在 P3c**：P3d 跨机产物、P3e Windows 远程/`remoteOs` 探测、P4 连接弹性、远程 SFTP 目录浏览器 UX（成员目录来自工作区 target folders，独立 UX 留后续）。

## 1. 已锁定决策（Q1–Q5）

| # | 决策 |
|---|------|
| Q1 | **一体交付**：locate/install + ancestry/skills/plugins 物化 + 凭证 opt-in 三件套一起 |
| Q2 | locate 泛化全 5 CLI + per-target 手填兜底 + SSH auto-install（**opt-in 带进度**，不装则手填/报错） |
| Q3 | 凭证推远程 **per-target 显式开关，默认关**；首次推送前确认弹窗明示信任边界；密钥轮换需重推已 opt-in 机器 |
| Q4 | 物化含**内容哈希/manifest 跳过未变子树**（首 launch 后增量） |
| Q5 | **不**纳入远程 SFTP 目录浏览器 UX |

## 2. 关键前提（现网已核实，feat/p3-member-remote）

- `runtime_layout._ensureInheritedChild`(:311) **完全 fs 注入**：`createSymlink` 失败兜底 `copyTree`，幂等判断用 P2 补的 `readSymlinkTarget`(:355)/`resolveSymlink`/`listDir`。**故：用工作机的 `fs`+`teampilotRoot` 构造 `RuntimeLayout`，继承链自动在该机根内闭合**——前提是该机根上**已存在**被继承的 parent（`cli-defaults/{tool}`、workspace config）。今天 parent 默认在 home；P3c 的活就是**先把 ancestry 物化到工作机根**，再跑现成继承逻辑。
- `ResourceProvisioningService`(fs 注入, `provisionForLaunch`)、`ResourceMaterializer`(`reconcile`)、provider 凭证服务（claude/codex/opencode/cursor）均 fs/runner 注入 → **可 fake 测**。
- `RemoteFlashskyaiCliLocator` 已抽象在 `SshCommandRunner = Future<SshCommandResult> Function(String)` 之上（`locateWithRunner`）——泛化只需把"探测命令"能力化、覆盖 5 CLI。
- `InstallerCapability{supportsInstaller, install(CliInstallContext)}` + 每 CLI 安装器齐备；`CliInstallContext` 走 `HostScriptRunner`——远程安装 = 给它一个**绑定到 target transport 的 script runner**。
- `RuntimeContextRegistry.forTarget` 持/复用 SSHClient（P2/P3b），提供工作机 `RuntimeContext`(fs=SftpFilesystem, appDataRoot=`<machineRoot>`) 与命令/脚本 runner。

## 3. 架构

### 3.1 远程 CLI 定位（能力化，覆盖 5 CLI）

```dart
// lib/services/cli/registry/capabilities/remote_cli_locator_capability.dart
abstract interface class RemoteCliLocatorCapability implements CliCapability {
  /// 走 target transport 的探测命令序列（command -v / which / 版本探测）。
  Future<String?> locate(SshCommandRunner run);
}
```

- 每 CLI 在其 `CliToolDefinition` 注册自己的探测命令（claude/flashskyai/codex/opencode/cursor）。
- `RemoteCliLocator.resolve(target, cli, {manualPathOverride})`：先 per-target 手填覆盖 → 否则 `capability.locate(runnerForTarget)`；命中路径**缓存到 target**（避免每 launch 重探）。
- 取代 `RemoteFlashskyaiCliLocator`（删；其逻辑并入 claude/flashskyai 的能力实现）。

### 3.2 远程 CLI 安装（opt-in，带进度）

- locate 失败 + `InstallerCapability.supportsInstaller` + **用户 opt-in** → 以**绑定 target transport 的 `HostScriptRunner`** 跑 `InstallerCapability.install(CliInstallContext)`，进度经回调上抛 UI。
- 不支持安装器 / 用户未 opt-in / 安装失败 → 清晰报错 + 提示 **per-target 手填路径**（落 target 配置）。

### 3.3 工作机物化（ancestry + skills/plugins + manifest 哈希跳过）

`WorkMachineMaterializer`（fs = 工作机 SftpFilesystem，root = `<machineRoot>`）：

1. **ancestry 铺设**：把 home 的 `cli-defaults/{tool}`（仅用到的 tool）+ 该 workspace 的 config **拷到工作机 `<machineRoot>` 对应相对路径**（本地 App 是唯一同时够得着两边 fs 的进程：home fs 读 → 工作机 fs 写）。
2. **跑现成继承**：用工作机 `fs`+`<machineRoot>` 构造 `RuntimeLayout`，调既有 provision/继承——`_ensureInheritedChild` 的 symlink **在该机根内闭合**（源/目标同在 `<machineRoot>`），POSIX 远程 symlink 可用（§1.4 决策4）。
3. **skills/plugins**：经工作机 fs 在该机内链接（复用 TeamSkill/PluginLinkerService，注入工作机 fs）。
4. **relay**：复用 P3b `RelayProvisioner`（已物化到工作机）。
5. **哈希/manifest 跳过**：`MaterializationManifest`（`<machineRoot>/.materialized.json`）记录每子树内容哈希；reconcile 时**未变子树跳过**，避免 SFTP 每次全量重铺。
6. **接受陈旧**：home 改 app 默认/workspace config 不实时同步；下次 launch 重物化时按哈希更新（类 build cache）。

> **物理布局**：各机同一套相对布局、根不同——`<machineRoot>/cli-defaults/…`、`<machineRoot>/workspace/projects/{wsId}/sessions/{sId}/runtime/members/{memberId}/…`。layout 方法全 root-relative，"免费"成立。session 元数据仍只在 home。

### 3.4 凭证物化到远程（per-target opt-in）

`RemoteCredentialMaterializer`：

- 凭证仍**本地生成**（既有 per-CLI 凭证服务，登录/导出 `Process.run` 在本地）。
- 若 **target opt-in 开**：把凭证文件物化到工作机 `<machineRoot>/providers/{tool}/`；**链接 target 的绝对路径按工作机 root 重算**（今天是本地绝对路径，跨机失效）。
- 默认 **关**：不铺任何 key；远程成员若无凭证则该 provider 不可用（清晰提示需 opt-in）。
- opt-in 存 `targets.json` 的 `credentialOptIn: [targetId...]`（consent 是配置，不进 RuntimeTarget 运行时身份）。
- **首次推送前确认弹窗**：明示"密钥将落到远程主机 <host>"信任边界；**密钥轮换**后对已 opt-in 的 N 台需重推（manifest 哈希变更触发）。

### 3.5 远程 preflight 编排（§5.3）

`RemotePreflightService.prepare({target, cli, workspaceId, memberId, optInCredentials})`：

```
1. 连接：registry.forTarget(target) 建/复用 SSHClient（失败→该 target 不可用，清晰错误）
2. CLI 就位：RemoteCliLocator.resolve(target, cli) → 缺则 opt-in 安装 / 手填 / 报错；缓远程路径
3. app-data：WorkMachineMaterializer.reconcile（ancestry+skills/plugins+relay+(opt-in)凭证），哈希跳过
4. bus 可达（仅协调/团队成员）：顶接 P3b——RemoteBusMount.bindLongBlockingMember（隧道+raw-socket+token+relay）
返回：ready-to-launch（远程 CLI 路径 + 工作机 RuntimeContext + bus binding）
```

- **顺序约束**（§5.3）：远程协调成员 MCP 配置依赖隧道口 `<P>`（P3b），故序必须 bus→tunnel→写 MCP→launch；preflight 把这串成显式 checklist。
- 接入点：`session_launch_service`/`session_lifecycle_service` 在成员 target **为异于 home 的远程机**时，launch 前跑 `RemotePreflightService.prepare`；成员在 home/home-ssh（P3b 覆盖）走原路径。

## 4. 关键文件

| 文件 | 动作 |
|------|------|
| `lib/services/cli/registry/capabilities/remote_cli_locator_capability.dart` | 新增能力位（per-CLI 探测命令） |
| 5 个 `cli/registry/tools/*_cli_tool.dart` | 注册各自 `RemoteCliLocatorCapability` |
| `lib/services/cli/remote_cli_locator.dart` | 新增泛化 locator（取代 `RemoteFlashskyaiCliLocator`，删旧） |
| `lib/services/remote/remote_preflight_service.dart` | 新增 preflight 编排 |
| `lib/services/remote/work_machine_materializer.dart` | 新增 ancestry+skills/plugins 物化 + 调继承 |
| `lib/services/remote/materialization_manifest.dart` | 新增内容哈希 manifest（跳过未变子树） |
| `lib/services/remote/remote_credential_materializer.dart` | 新增凭证物化 + 链接 root 重算 + opt-in |
| `lib/services/storage/targets_repository.dart` | `TargetsRegistryFile` + `credentialOptIn: List<String>` + per-target 手填 CLI 路径 |
| `lib/services/cli/registry/installer/installer_context.dart` 等 | 安装走绑定 target transport 的 `HostScriptRunner` |
| `lib/cubits/chat/session_launch_service.dart`、`session_lifecycle_service.dart` | 远程成员 launch 前跑 preflight |
| 凭证 opt-in UI（target/profile 设置） | per-target "推送凭证到此机"开关 + 首推确认弹窗 |

## 5. 测试策略（重点：无真机可测试性）

全程经注入 `Filesystem`（`FakeSftpFilesystem`，已在 P3 测试栈）+ `SshCommandRunner`/`HostScriptRunner`（fake）编程，无真 SSH：

1. **locate（5 CLI）**：`FakeSshCommandRunner` 对探测命令返回路径 → `RemoteCliLocator.resolve` 命中并缓存；探测全失败 → null。每 CLI 探测命令各一测。
2. **auto-install opt-in**：locate 失败 + opt-in off → 报错 + 提示手填；opt-in on + supportsInstaller → fake runner 记录安装脚本被执行、进度回调被调用；安装后 re-locate 命中。
3. **ancestry 物化 + 继承闭合（§5.2 核心）**：两个 `FakeSftpFilesystem`（home 源 / 工作机目标）。物化后断言：① `cli-defaults/{tool}`+workspace config 出现在工作机 `<machineRoot>`；② 用工作机 fs+root 跑继承后，session runtime 的继承 symlink 的 `readSymlinkTarget` **指向工作机 `<machineRoot>` 内**（不指向 home），即"链在该机根内闭合"。
4. **哈希/manifest 跳过**：首次 reconcile 写 manifest；内容不变第二次 reconcile **不重拷**（断言工作机 fs 写调用计数为 0 / manifest 命中）；改一个文件 → 仅该子树重拷。
5. **凭证 opt-in**：opt-in **off** → 工作机 `providers/` **无** cred 文件；opt-in **on** → cred 文件落工作机 `providers/{tool}/` 且**链接 target 绝对路径按工作机 root 重算**（断言路径前缀 = `<machineRoot>` 而非本地 root）。轮换（内容变）→ 重推。
6. **preflight 编排**：fake 各步，断言**顺序** connect→locate/install→materialize→bus-bind，且任一步失败短路并清晰报错（如连接失败 target 不可用）。
7. **UI**：opt-in 开关默认关；开启触发首推确认弹窗（断言弹窗出现 + 确认后写 `credentialOptIn`）。
8. **全量**：`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿；边界 grep：`remoteOs` 仍占位、无 Windows/macos 物化分支、无跨机产物 MCP、无远程目录浏览器。

## 6. 不在 P3c（重申）

P3d 跨机产物、P3e Windows 远程（`remoteOs` 探测/symlink→copy/windows relay）、P4 连接弹性、远程 SFTP 目录浏览器 UX。
