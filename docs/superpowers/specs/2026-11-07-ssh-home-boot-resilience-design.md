# SSH Home 启动韧性与连接恢复设计

- 日期：2026-11-07
- 状态：待审阅
- 来源：用户反馈启动卡在 splash 长达 3.5 分钟、期间无任何提示；要求根因修复而非只解决这一次

## 背景

一次实测（`client/adb.log`）中，App 在 `StorageBackendMode.ssh` 下启动：

| 时间点 | 事件 | 说明 |
|---|---|---|
| +140ms | `installing home runtime context` | |
| +17,433ms | `home runtime context ensured +17433ms` | home SSH 解析超时 ~17s，回退到缓存路径 |
| +35s | `cli row sweep failed` / `home index prefetch failed`（`SSH worker storage opening was invalidated`） | 多个子系统各自再开一次 SSH 存储，各等 ~17s 后失败 |
| +122,080ms | `loading layout` | 中间 ~87s 全耗在其它 subsystem 的 SSH 超时上 |
| +139,394ms | `layout ready` | |
| +209,503ms | `bootstrap complete` | 合计 ≈3.5 分钟 |
| 全程 | `reconnect attempt 1/5 … 5/5` 全部 `Worker storage operation failed`；`connect failed: TimeoutException after 0:00:05` | 后台重连 5 次全部失败 |
| 结果 | `workspaces=0`；`skills/plugins/extensions` 全部 `opening was invalidated` | 远端数据一个都没加载出来 |

本次的**触发条件**是 home SSH 目标不可达：笔记本局域网 IP 由 `192.168.8.87` 变为 `192.168.18.174`，而 App 内保存的目标仍是旧 IP（手机 `192.168.18.213` 与新 IP 同网段、22 端口可达，仅旧 IP 100% 丢包）。

但真正的缺陷是：**任何一个不可达或缓慢的 home 都会把"依赖远端"放大成一次无声的数分钟卡死。** 修 IP 只解决这一次，不改架构仍会复发。

## 根因（四层叠加）

1. **splash 阻塞在远端数据上**：`bootstrapAppData`（`client/lib/app/app_shell.dart:3231`）在 `markAppReady` 之前 `await` 了 `homeIndexPrefetch`、远端 `bootstrapHomeIndex`、`warmShellConfig`、`prepareInteractiveShell` 等远端重操作。
2. **没有快速失败**：每次 SSH 存储打开要等 ~17s 才超时（`client/lib/services/ssh/ssh_client_factory_storage.dart` 的 `_open` → `storage.connect`）。
3. **并发打开不去重**：`_SshWorkerStoragePool.clientFor` 对同一 profile 的并发调用各自新建一个 opening token 并替换前一个（`_isCurrentOpening`，`ssh_client_factory_storage.dart:311`），先到的被作废并抛 `SSH worker storage opening was invalidated`；~10 个子系统并行时相互作废，把等待成倍放大。
4. **零用户可见性**：splash 期间没有主机信息、没有进度、没有超时、没有退路。

## 目标

1. splash **只等本地引导**，永不因远端 IO 卡住；本地引导完成后必定进入可交互的界面。
2. home 连接改为**有界、可观测、可恢复**：一次有界尝试失败即进入连接页，后台持续重试。
3. 连接页让用户**知情且可操作**：显示目标 `host:port`、尝试次数、错误类型，并提供「取消重试 / 继续重试 / 切换连接」。
4. 消除并发打开放大：同一 profile 的进行中打开**单飞共享**。
5. 重连成功后**热恢复**：自动补跑被跳过的远端引导并进入正式界面，无需用户手动操作。
6. 不改 SSH 协议 / worker / 传输层语义。

## 非目标

- 不做完整 offline 模式（不渲染大量本地缓存数据的界面）——用户明确未选择该方向。
- 不做多 home 并行连接。
- 不改 PTY / 终端交付状态机。
- 不在本增量内解决"目标 IP 会变"的寻址问题（静态 IP、mDNS、配对中继属于独立配置/后续工作）。

## 术语

- **home**：控制平面绑定的运行时目标（`RuntimeKind.ssh` 时为某 SSH profile）。
- **首次尝试**：App 冷启动时对 home 建立的第一次连接尝试。
- **不可达**：首次尝试在有界预算内未成功（TCP 不通，或 SSH 握手/解析超时/失败后回退到缓存路径）。
- **热恢复**：重连成功后自动补跑首次启动时被跳过的远端引导，并切换到正式界面。

## 设计

### 1. 状态机与真相来源

新增 `HomeConnectionCubit`（`client/lib/cubits/home_connection_cubit.dart`），单一职责：home 是否可达，以及用户下一步能做什么。

状态 `HomeConnectionStatus`：

- `connecting`：首次尝试进行中（或用户点了「继续重试」后立即进入）。
- `connected`：home 可用。
- `unreachable`：首次尝试失败，且当前**没有**在自动重试（例如用户取消了重试）。
- `reconnecting`：`unreachable` 之后后台自动重试进行中。

状态字段（`Equatable`）：

- `status`
- `profileId`、`host`、`port`
- `attempt`（当前这一轮的第几次）
- `lastErrorKind`（仅错误**类别**：`tcpUnreachable` / `sshTimeout` / `authFailed` / `transportError` / `unknown`）
- `canCancelRetry` / `canRetryNow`（供 UI 决定按钮可用性）

"不可达"的判定信号：

- 首次尝试前先做 **TCP 预探活**（见 §5）；不通即 `unreachable`。
- 预探活通过后，SSH 解析若回退到缓存路径（现有 `RuntimeContext.pathsFromCache == true`，见 `client/lib/services/storage/runtime_context_resolver.dart:141-180`），即视为不可达。
- 任何显式超时同样视为不可达。

> `HomeConnectionCubit` 只向外暴露状态与动作，不直接持有凭据；`host/port` 仅用于展示。

### 2. 组件与职责

| 组件 | 位置 | 动作 |
|---|---|---|
| `HomeConnectionCubit`（新） | `client/lib/cubits/home_connection_cubit.dart` | 驱动 home 连接生命周期；暴露 `retryNow()`、`cancelRetry()`、`switchConnection()`；被 `StartupGate` 监听 |
| `HomeConnectResult`（新，值对象） | 同上或 `models/` | 承载一次尝试的结果：`reachable`、`RuntimeContext context`、`lastErrorKind` |
| `StartupGate`（改） | `client/lib/pages/startup_gate.dart` | 新增分支：`connecting` → 带主机名的进度页；`unreachable/reconnecting` → 连接页；`connected` → 原有逻辑（`child`） |
| `RemoteConnectionsPage`（改，复用） | `client/lib/pages/remote_connections_page.dart` | 顶部新增"连接状态卡"（`host:port`、第 N 次、错误类型）+ 三动作；页面本已列出目标，天然承载「切换连接」，不新建重复页 |
| `SshProfileConnectionCoordinator`（改/复用） | `client/lib/services/ssh/ssh_profile_connection_coordinator.dart` | 后台退避重试；`cancelRetry` 复用 `userDisconnect` 的 latch 语义；`retryNow` 重置计数并立即重试；在连接页展示期间不因 `maxAttempts` 静默放弃（改为持续退避或交由用户取消） |
| `_SshWorkerStoragePool`（改） | `client/lib/services/ssh/ssh_client_factory_storage.dart` | `clientFor` 对同一 profile **单飞**：命中 `_openings[id]` 的 pending 时 await 其 future，而不是新建 token 覆盖 |
| `bootstrapAppData` 及 boot 编排（改） | `client/lib/app/app_shell.dart:3227-3350` | 远端重步骤只在 `connected` 时跑；`unreachable` 时跳过并置 app-ready；重连成功后补跑（热恢复） |
| home 解析入口（改） | `client/lib/app/app_shell.dart:1139-1143` + `runtime_context_resolver.dart` | 首次尝试改为"TCP 预探活 + 有界 SSH 联接"，并把结果（含是否回退缓存）交给 `HomeConnectionCubit` |
| `SshProfileReconnectPolicy`（复用/微调） | `client/lib/services/ssh/ssh_profile_reconnect_policy.dart` | 退避 `2→4→8→16→30s`（封顶 30s）；连接页展示期间可持续重试直到用户取消 |

### 3. 启动时序（改后）

1. **本地引导**（原样、快速）：加载 session preferences、workspace 目录、本地快照等。
2. **首次 home 尝试**（有界）：TCP 预探活（≤2s）→ 有界 SSH 解析（≤8s 总预算）。
3. 成功 → 状态 `connected` → 正常执行远端 boot（home 索引、launchProfiles、warmShellConfig、prepareInteractiveShell 等）→ `markAppReady` → 正常界面。
4. 失败 → 状态 `unreachable` → **照常构建壳并 `markAppReady`**；`StartupGate` 显示连接页；**跳过**远端重步骤；**不写**任何远端状态（不持久化 path cache、不写 profile）。
5. **后台重试**：按退避持续尝试；状态在 `unreachable ↔ reconnecting` 间流转；连接页实时刷新"正在重试…第 N 次"。
6. **热恢复**：重连成功 → 状态 `connected` → 补跑第 4 步跳过的远端 boot（幂等、单次）→ 自动切到正式界面。

**关键不变量**：`buildAppShell` 不再因 home 不可达而长时间挂起；`markAppReady` 一定在本地引导完成后触发。

> 时序说明：首次有界尝试发生在 `buildAppShell` 内（`ensureHome` 需先产出 `homeCtx` 才能构建依赖它的仓储/Cubit），此时壳尚未构建，界面仍是既有加载页/原生 splash，最长约 `homeConnectBudget`。`StartupGate` 的 `connecting` 分支主要服务于**壳已存在后**的用户触发重试（如「继续重试」）。可选增强：把目标 `host` 传给加载页显示"正在连接 …"，但非必需。

**`StartupGate` 分支优先级**（自上而下，先命中先返回）：

1. `sshState.isLoading` → 现有 spinner。
2. `mode.requiresSshProfileSetup`（无 profile）→ `RemoteConnectionsPage`（配置模式，沿用现状）。
3. home 状态 `unreachable` / `reconnecting` → `RemoteConnectionsPage`（连接状态卡模式）。
4. home 状态 `connecting`（壳内、用户触发重试）→ 带主机名的进度页。
5. 其余 → 现有 `androidNeedsWorkHome ? WorkEnvironmentChooserPage : child`。

（SSH 模式下 `hasBoundAndroidWorkHome` 为真，故第 2–4 分支不会与 `androidNeedsWorkHome` 冲突。）

### 4. 连接页与三个动作

复用 `RemoteConnectionsPage`，顶部加一张状态卡：

- 文案（全部走 l10n）：`无法连接 <host>:<port>`、`第 N 次重试`、错误类型本地化描述。
- 动作：
  - **取消重试**：置 latch（复用 coordinator `userDisconnect` 语义），停止自动重试；状态停在 `unreachable`，按钮变为「继续重试」。
  - **继续重试**：清 latch、重置计数、立即尝试一次，随后继续退避。
  - **切换连接**：滚动/跳到目标列表，可编辑 `host/port` 或改选其它目标；保存后自动触发一次重试（等价 `retryNow`）。
- 不展示凭据；不展示文件内容；仅展示 `host:port`、错误**类别**、尝试次数。

### 5. 超时、探活与退避参数

| 参数 | 取值 | 说明 |
|---|---|---|
| `tcpProbeTimeout` | 2s | 首次尝试前的 TCP 连通性探活；不通即判不可达（快速失败） |
| `homeConnectBudget` | 8s | 首次/单次 SSH 解析总预算；覆盖正常的慢网握手，同时避免 17s 级等待 |
| `retryAttemptBudget` | 10s | 后台每次重试的总预算 |
| 退避 | `2→4→8→16→30s`（封顶 30s） | 复用 `SshProfileReconnectPolicy` |
| 重试持续性 | 连接页展示期间持续，直到用户「取消重试」 | 不在页面上静默 give-up |

> 数值集中定义（常量/策略对象），便于后续按真机体验调整。

### 6. 热恢复（补跑被跳过的远端引导）

- 首次 `unreachable` 时，把远端重步骤封装成一个可重复调用、**幂等**的 `runRemoteBootAfterConnect()`（复用现有 `AppDataBootstrap.bootstrapHomeIndex` / `warmAuxiliaryData` 的逻辑）。
- 重连成功回调里调用一次；用一次性护栏防止重复执行（例如 `bool _remoteBootCompleted` 或单飞 Future）。
- 补跑期间 UI 显示正常骨架/加载态；完成后 `markAppReady` 已在首次触发过，界面直接由骨架切换到数据（热恢复，不重进 splash）。
- 若补跑失败，记录 `AppLogger.w`（内容无关），保留在 `connected` 但数据为空，用户可下拉/手动重试（沿用各面板现有重试）。

### 7. 并发打开去重（存储池单飞）

`_SshWorkerStoragePool.clientFor(profile)` 当前逻辑：每次调用 `_openings[profile.id] = _WorkerStorageOpening(token: Object(), …)`，新 token 使旧 opening 失效。

改为：

- 若 `_openings[profile.id]` 存在且未被取消，**返回/await 同一个 pending future**，不新建 token。
- 仅在 pending 已结束或已被显式作废时才新建。
- 保留 `_isCurrentOpening` 作为"作废/丢弃"的保护（例如 profile 被删除、home 被显式切换），但不再因"并发请求"而互相作废。

效果：启动期 N 个子系统共享同一次 SSH 打开，消除 `opening was invalidated` 与 N×超时。

### 8. 安全与日志

- 连接页与日志只包含 `host:port`、错误**类别**、尝试次数；**不含**用户名之外的凭据、私钥内容、文件内容。
- 复用现有 `AppLogger`；不新增 `print`。
- 用户可见文案只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`。

## 边界情况

| 情况 | 行为 |
|---|---|
| 首次即不可达（TCP 不通） | ~2s 内进入连接页（快速失败），后台退避重试 |
| TCP 通但 SSH 认证失败 | `unreachable` + `authFailed`；提示检查凭据/主机；重试不放大（单飞） |
| SSH 慢但可用（>8s 握手） | 首次判不可达进连接页，后台重试在退避窗口内成功 → 热恢复；用户几乎无感或短暂看到连接页 |
| 用户在连接页取消重试 | 停止后台重试；状态 `unreachable`；可随时「继续重试」 |
| 用户切换/编辑目标后 | 触发一次 `retryNow`；成功后热恢复 |
| 重连成功后远端 boot 失败 | 保持 `connected`，数据面板各自显示错误/重试，不退回连接页 |
| 本地引导本身失败 | 沿用现有错误处理（不在本设计范围） |

## 测试策略

- **单测**：`HomeConnectionCubit` 全状态迁移（`connecting→connected`、`connecting→unreachable→reconnecting→connected`）、三动作（取消后不再自动重试、继续恢复、切换后重试）。
- **单测**：`_SshWorkerStoragePool` 单飞——两个并发 `clientFor` 只触发一次 `_open`，二者得到同一 storage，且**不抛** `opening was invalidated`。
- **单测**：`HomeConnectResult` / 判定逻辑—— TCP 不通、SSH 超时回退缓存、正常连接三条路径分别映射到正确的 `status` 与 `lastErrorKind`。
- **Widget**：`StartupGate` 在 `connecting/unreachable/connected` 三种状态下的渲染；连接页三动作接线（点击回调触发对应方法）。
- **集成**：用不可达的 fake dialer 启动 → splash 在 `homeConnectBudget + 余量` 内撤下、连接页出现、无 17s 级联、无 `opening was invalidated`；随后模拟可达 → 热恢复进入正式界面。
- **回归**：`test/pages/startup_gate_test.dart`、`test/smoke/app_shell_smoke_test.dart`，以及现有 ssh 连接/重连相关测试。

## 迁移与兼容

- 不改变 `RemoteConnectionsPage` 既有用法（`embedded`、无参数直开）；新增的状态卡仅在"作为启动门控展示且 home 不可达"时出现。
- 不改变 `SshProfileConnectionCoordinator` 的对外契约；新增/调整的重试入口保持内部语义一致。
- 单飞改动对现有调用方透明（返回类型不变）。
- `bootstrapAppData` 的远端步骤改为可重复调用，需保证幂等，避免热恢复时重复 hydrate。

## 未决 / 后续（非本增量）

- home 目标寻址稳定性：静态 IP / DHCP 保留 / mDNS / 配对中继（`pairedDesktopId`、`relayUrl` 已有字段）。
- 完整 offline 模式（本地缓存渲染 + 可编辑）。
- 对"慢但可用"的 home 做连接预热/多 endpoint 竞速（现有 `EndpointDialPlanner`）。
