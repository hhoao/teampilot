# SSH Home 连通性监督层设计

- 日期：2026-11-12
- 状态：待审阅
- 来源：移动端「切换到一个能连通的远程后仍跳回重试页」及「已进入应用内却仍显示需要重新连接」两处缺陷；用户要求按最好的架构与可扩展性做根因修复，并选定「监督层」方案（方案 C 中的方案 1：绞杀式 Supervisor）

## 背景

近期两个已提交的修复只解决了症状链上的单点：

- `9c82e0c45 fix(ssh): keep an edited home profile retryable` —— 编辑 host 后旧 lease 被当成 `hostIdentityChanged` 退役，coordinator latch + suspend + `onNonRetryableClose` → home `markUnreachable` → 跳回重试页。改为 `profileInvalidated`（可重试的本地 re-target）。
- `83645aca3 fix(ssh): gate reconnects behind one coordinator` —— 新增 `SshConnectionGate`，让普通 storage/member I/O 在共享传输 down 时快速失败，只有 coordinator 能重新武装；storage lease 的自行退役改为 plane-scoped，不再把整个 home 打 down。

第二份 logcat 显示：`profileInvalidated` 修复生效了（单行 debug、无 latch），但**进入应用内后 banner 仍显示「需要重新连接」**，并伴随 `SSH worker storage opening was invalidated`。用户据此要求从架构上收敛，而非继续打补丁。

## 根因：六个各自写/读「是否已连接」的地方

| # | 源 | 持有的「真相」 |
|---|---|---|
| 1 | `SshClientFactory` 的 pool（`hasLiveStorageClient`，`ssh_client_factory.dart:185`） | 是否存在可用 lease |
| 2 | `SshConnectionGate`（`idle/connecting/up/down/suspended`） | 拨号许可 / 熔断 |
| 3 | `RemoteConnectionMonitor`（`connected/degraded/reconnecting/down`） | 心跳存活 |
| 4 | `SshProfileConnectionCoordinator` | 重试账本：`_reconnectAttempts`、`_reconnectInFlight`、`_userDisconnectLatched`、合并定时器、退避定时器 |
| 5 | `SshConnectionCubit` | `_lastFailureStatus`（粘性）、`_connectingIds`，且 `_resolveStatus` 又从 pool 反推一次（`ssh_connection_cubit.dart:363`） |
| 6 | `HomeConnectionCubit` | `HomeConnectionStatus`，由 `app_shell.dart:3176-3219` 的 4 个 hook 加一堆 `markX` 驱动 |

它们之间没有单一所有权，靠 hook / latch / 流订阅互相"通知"。三条具体的失配链：

1. **并发 open 相互作废**：`switchHomeTarget`（`app_shell.dart:4283`）会同时触发 `retryNow()`、`applyHomeEventTransport(restart: true)`、boot 补跑与 `reconnectHomeSshIfNeeded`，多个路径各自调用 `ensureStorageConnected` / `clientFor`。`clientFor` 对同一 `hostIdentifier` 的在途打开去重（`ssh_client_factory_storage.dart:53-56`），但当各路径持有的 `SshProfile` 内容略有差异（paired profile 的 `withLastGoodEndpoint` 改 host/port，或编辑后 host 变化）时，`hostIdentifier` 不同 → 判定 pending 为 stale → `disconnectProfile(profileInvalidated)` 移除 `_openings`（`:63`、`:227`）→ 先发的 `_open` 在 `_isCurrentOpening` 处抛 `SSH worker storage opening was invalidated`（`:146`）。
2. **gate 卡 down**：lease 没落地 → `_onStoragePoolChanged` 不 `markUp`/`resume`；同时 `persistRetry` 在 home cubit 已 `connected` 时返回 false（`app_shell.dart:3209`）→ 循环提前放弃，无人再把 gate 拉回 `up`。
3. **粘性失败状态**：`_lastFailureStatus` 只在 `connect()` 成功或 `_onPoolChanged` 见到 live client 时清除；上面两条使这两个时机都没到达，于是 `SshHomeDisconnectedBanner`（`ssh_home_disconnected_banner.dart:42-47`）在已连接后仍显示。

**共性**：`up` 与「清除 failure」分属两个异步源，无法保证原子；「是否要继续重试」读的是 UI cubit 的状态而非连接本身。

## 目标

1. 把 dial / liveness / reconnect / state 收敛到**唯一 owner**；`SshClientFactory` 退化为纯 pool。
2. 用**结构性不变量**（而非补丁）同时消灭上述三条失配链，且不再复发。
3. 保持现有全部 UI 状态语义与已提交的时序修复（单飞、合并窗口、`finally` 清 in-flight、plane-scoped 退役、`profileInvalidated` 可重试）。
4. 迁移分阶段、每阶段可独立验证，不与当前工作区里正在进行的其它改动纠缠。

## 非目标

- 不重写 `SshTransportClosePolicy` / `isNonRetryableTransportClose` / `SshProfileReconnectPolicy` 等纯策略。
- 不做事件溯源 / 纯 reducer 全量重写（方案 2）；本设计保留现有引擎作为 supervisor 的私有组件。
- 不改 PTY / 终端交付状态机、SSH 协议 / worker / 传输层语义。
- 不做多 home 并行连接、完整 offline 模式。
- 不改 `StartupGate` 的分支结构，也不改 banner 的展示条件，只改二者的**状态来源**。

## 术语

- **supervisor**：`SshHomeConnectivitySupervisor`，app 级单实例，内部按 `profileId` 持有子状态机；唯一写者 + 唯一发布者。
- **phase**：`SshPhase`，连接生命周期的规范状态。刻意不叫 `down`——代码里已有 `SshConnectionGateState.down` 与 `RemoteConnectionStatus.down` 两个不同含义的 `down`。
- **storageLive**：唯一「是否已连接」真相，值为存在可用 lease。
- **activeHome**：当前绑定的 home profile，由 supervisor 自己持有 `_activeHomeId`，仅 `activateHome(id)` 可写。

## 设计

### 1. 架构与组件边界

落位 `client/lib/services/ssh/`，纯 Dart，不 import Flutter/Bloc，维持「cubit 依赖 service、service 不反向依赖」的分层。新增 `ssh_home_connectivity_supervisor.dart`（含 `SshHomeConnectivityState` / `SshPhase` / `SshFailureKind`）。

**形状决策（1a）**：一个 app 级 supervisor 实例 + 内部 `Map<String, _ProfileConnectivity>`。刻意沿用现有 coordinator 的形状（`_monitors` / `_reconnectAttempts` 等都是 per-id map），让迁移只是「把字段搬进来」，不引入多实例 + Registry 的生命周期管理。构造依赖沿用现成的 `SshClientFactory` / `SshConnectionEvents` / `SshProfileResolver` / `SshProfileReconnectPolicy`。

**supervisor 独占（私有字段，外部不可访问）**：`SshConnectionGate`、重试账本（attempt / in-flight / latch / 合并定时器 / 退避定时器）、`RemoteConnectionMonitor`、`lastFailure`、**dial 单飞**。

| 对外 API | 类别 | 说明 |
|---|---|---|
| `stateFor(id)` / `changesFor(id)` / `changes` | 读 | 广播 `SshHomeConnectivityState` |
| `userConnect` / `userDisconnect` / `resumeRetries` | 命令 | 沿用现有语义 |
| `activateHome(id)` / `profileEdited(id)` / `dispose` | 命令 | 新增，取代 hook 分发 |
| `holdPlaneRebind()` / `releasePlaneRebind()` | 命令 | 取代 `markPlaneRebinding` / `markPlaneReady`（`home_connection_cubit.dart:187-203`）的 UI hold |
| `awaitAvailable(id)` | 读 | 取代 `sshClientFactory.connectionGate.waitUntilUp`（`app_shell.dart:985`），供消费者等待恢复 |

**`SshClientFactory` 退化为纯 pool**：删 `connectionGate` 字段（`ssh_client_factory.dart:145`）与构造参数（`:85`、`:108`）、`storageFor` / `openMemberTransport` / `_GatedMemberTransport.open` 里全部 `beforeIo` / `markConnecting` / `markUp` / `markDown`（`:231-251`、`:262-301`、`:785-801`）、两个 `part` 文件里的同类调用（`ssh_client_factory_narrow_operations.dart:57-104`、`ssh_client_factory_legacy_storage.dart:49-100`）、`allowDialWhenDown` 参数、`disconnectProfile` 里的 `suspend`（`:483-485`）、`_close()` 里的 `connectionGate.dispose()`（`:611`）。gate 实例、它的 `onWaiter` / `onDown` 回调、以及 `dispose` 全部搬进 supervisor。保留 `storagePoolChanges` 但只发**原始** pool 变化，不解释语义。pool 只回答「有没有 lease」，不回答「该不该拨号」。

> `SshProfileDownException` / `isSshProfileDown` 是纯值与纯判定，**保持公开且不变**：它们被 `storage_failure.dart:34`、`vault_split_migration.dart:29/46`、`legacy_import.dart:506`、`remote_cli_readiness.dart:177/239`、`session_chat_view.dart:400` 及 `app_shell.dart` 多处（`:1038`、`:1701`、`:2086`、`:3466`、`:4765`）用作「预期失败、等恢复后重抛」的契约。gate 私有化不改这些调用方；唯一要改的是 `waitForSshProfileRecovery`（`:983-987`）转而调用 `supervisor.awaitAvailable(id)`。

**两个 cubit 变投影**：只做 `SshHomeConnectivityState → 现有枚举` 的映射，删 `_lastFailureStatus`、`_resolveStatus` 的 pool 反推、`_connectingIds`，不再独立写状态。

**app_shell**：一次 `supervisor.changes` 订阅取代 4 个 hook。

> 已知残留：gate / coordinator 账本 / monitor 作为私有引擎仍并存，属于「单一写者」而非「单一状态对象」，需靠纪律约束外部一律只碰 supervisor。这是刻意选择的低风险终态，也是后续演进到纯 reducer（方案 2）的同一条缝。

### 2. 状态机与不变量

```dart
enum SshPhase {
  idle, connecting, up, degraded, reconnecting, unreachable, suspended, failed,
}
enum SshFailureKind { hostIdentityChanged, authFailed, transportError, unknown }

@immutable
class SshHomeConnectivityState {
  final String profileId;
  final SshPhase phase;
  final SshFailureKind? failure;  // 进入 up 时同一次 emit 清空
  final String? errorDetail;      // UI 文案，同样在 up 时清空
  final int attempt;              // 1-based 重试号；非重试期为 0
  final bool storageLive;         // 唯一真相：存在可用 lease
  final bool planeRebinding;      // UI hold，不是连通性真相：恢复后换 home plane 期间按住门控
}
```

`failed` 与 `suspended` 拆成两个相位：UI 需要区分 `authFailed` / `error` 与 `disconnected`。

**跃迁表**（每行都是一次原子 `emit`；`↔` 表示成对跃迁）：

| 触发 | 跃迁 | effect | 不变量 |
|---|---|---|---|
| `userConnect` / `activateHome` / boot | * → `connecting` | 单飞 dial，attempt=0 | 1 |
| dial 成功 + lease 缓存完成 | `connecting` / `reconnecting` → `up` | `storageLive=true` **且** `failure=null` + `errorDetail=null` + `attempt=0`，同一次 emit | **2, 3** |
| 心跳超时（< 阈值）/ 恢复 | `up` ↔ `degraded` | `storageLive` 不变 | — |
| 传输 close / keepalive down / dial 失败（可重试） | * → `reconnecting` | 合并窗口后退避定时；`persist = (id == _activeHomeId)` | **4** |
| 退避到期 | `reconnecting` → `reconnecting` | 单飞 dial，attempt++ | 1 |
| 用尽 `maxAttempts` 且非 activeHome | `reconnecting` → `unreachable` | 停 timer | 4 |
| `hostIdentityChanged` / `authFailed` | * → `failed` | `failure=…`，suspend gate，停 loop | — |
| `profileInvalidated`（编辑 host） | * → `connecting` | 用**当前** profile 重新 dial，**绝不进 failed** | **5** |
| `userDisconnect` / `cancelRetry` | * → `suspended` | latch + suspend | — |
| `retryNow` / `resumeRetries` / 编辑后 | `suspended` / `unreachable` / `failed` → `reconnecting` | 清 latch + resume | — |

**投影表**（证明不丢现有 UI 状态）：

| SshPhase | `HomeConnectionStatus` | `SshHostUiStatus` |
|---|---|---|
| `idle` / `unreachable` / `suspended` | unreachable | disconnected |
| `connecting` | connecting | connecting |
| `up` / `degraded` | connected | connected |
| `reconnecting` | reconnecting | reconnecting |
| `failed(authFailed)` | unreachable (authFailed) | authFailed |
| `failed(hostKey \| transport)` | unreachable (hostIdentityChanged \| transportError) | error |

> `up && planeRebinding` 例外：投影成 `HomeConnectionStatus.connecting`（换 home plane 期间按住门控），`releasePlaneRebind()` 后回到 `connected`。

`degraded` 投影成 `connected` 是刻意的：保留现有「durable home 真相是 storage pool，心跳抖动不翻 connected」规则（`ssh_connection_cubit.dart:371`）。`StartupGate`（`startup_gate.dart:46-55`）的 `connecting`→进度页 / `reconnecting`→连接页 区分也因此保住。

**五条不变量与本次 bug 的对应**：

1. 单一 dial owner → 不再有 `SSH worker storage opening was invalidated`（根因 1）。
2. `storageLive` 只在 dial 成功且 lease 缓存完成后才 true → 不再有「cubit 说 connected、gate 说 down」（根因 2）。
3. 进入 `up` 的**同一次 emit** 清 `failure` / `errorDetail` → banner 不再粘住（根因 3）。这是整个修复的核心：过去 `up` 与「清 failure」分属 factory 与 cubit 两个异步源，现在结构上无法拆开。
4. 重试循环生命周期由 supervisor 相位与 `_activeHomeId` 决定，**不读任何 cubit 状态** → 循环不提前放弃。
5. `profileInvalidated` 永远是可重试的本地 re-target → 保住 `9c82e0c45`。

### 3. 数据流与所有权

**唯一 dial 路径**：所有命令（`userConnect` / `activateHome` / `profileEdited` / 退避到期 / `resumeRetries`）统一漏斗到 `_dial(profileId)`，由 `Map<String, Future<void>> _dialInFlight` 单飞。它同时取代 factory 里各消费者自发的 `storageFor` 与 coordinator 的 `_storageReconnects`（`ssh_profile_connection_coordinator.dart:538`）。同一时刻只存在一个 `clientFor(profile)`，且 supervisor 始终用**同一个** `SshProfile` 快照发起这一轮 dial —— 从源头消除根因 1 里「多个消费者持有内容略有差异的 profile」的情形。

**入站（全部降级为纯输入，不自带状态）**：

| 来源 | 处理 |
|---|---|
| `SshConnectionEvents.onTransportClosed` | `SshTransportClosePolicy` 分类 |
| `onKeepAliveFailed` | 心跳事件 |
| `factory.storagePoolChanges` | 原始 lease 存在性 |
| `SshProfileCubit` 编辑（`sshProfileConnectivityKey` 监听，`app_shell.dart:3986`） | `profileEdited(id)` |
| `HomeTargetController` 切换 | `activateHome(id)` |

**出站（单一 stream）**：`changes` 广播。app_shell 只订阅一次；两个 cubit 订阅 `changesFor(id)`。`awaitAvailable(id)` 是同一状态机上的等待原语，取代 gate 的 `waitUntilUp`；`onWaiter` / `onDown` 不再是跨对象回调，而是 supervisor 内部驱动重试循环的信号（`ssh_profile_connection_coordinator.dart:60-61`、`:359-376`）。

**热恢复不能随 cubit 一起消失**：现有 `HomeConnectionCubit._onConnected`（`app_shell.dart:3938-3967`）在「进入 connected」时跑 `markPlaneRebinding` → `rebindHomeStoragePlane()` → `markPlaneReady()` → `runRemoteBootAfterConnect()` → `reconnectHomeSshIfNeeded()`。cubit 变投影后，这段编排改为 app_shell 在 `changes` 上监听「非 `up` → `up`」跃迁触发，**保留现有幂等单次护栏**；换 plane 期间通过 `holdPlaneRebind()` / `releasePlaneRebind()` 把 `planeRebinding` 置位，`StartupGate` 据此仍显示进度页。`markInitial`（boot 种子）、`markReconnected`（`onReconnected` hook，`:3189`）两个入口的语义由 `activateHome` / `up` 跃迁承接。

**删除清单**：4 个 hook（`:3176-3219`）、`persistRetry`、`markBackgroundAttempt` / `markReconnected` / `markUnreachable` 的 hook 分发、`waitForSshProfileRecovery` 对 factory gate 的直接引用（`:985`）、boot 的 `restartReconnect` 特例（`:3978-3980`）、`switchHomeTarget` 的 `rebind` + `retryNow` + `userDisconnect` 三段（`:4327-4342`）→ 收敛成一次 `activateHome(prev → next)`。

`app_shell` 的 `activeHomeProfileId`（`:1266`）保留给非连通性用途，但连通性决策只读 supervisor 的 `_activeHomeId`，且**只由 `activateHome` 写入**，杜绝第二个真相。

### 4. 错误处理与恢复

保留纯策略、不重写：`SshTransportClosePolicy` / `isNonRetryableTransportClose` / `SshProfileReconnectPolicy` 原样吸收，supervisor 是它们唯一调用方。

| close 类型 | 处理 |
|---|---|
| member 主动关闭 | ignore |
| storage 平面自行退役（probe / timeout） | 只置 `storageLive=false` 并重开 lease，**不**把 home 打 down（保住 `83645aca3`，`ssh_profile_connection_coordinator.dart:226-231`） |
| `hostIdentityChanged` / `authFailed` | `failed` + suspend + `failure` |
| 其余 | `reconnecting` |

退避沿用 `delayForAttempt`；sshd penalty refusal 不消耗 attempt；activeHome 用 `maxDelay` 续命；非 activeHome 用尽 `maxAttempts` → `unreachable`。合并窗口 `_disconnectCoalesceTimers`、`_shouldPreferDisconnectError`、以及「hook 调用必须包在 try/finally 内以免 wedged in-flight」（`ssh_profile_connection_coordinator.dart:427`）全部保留。session-plane 恢复（`sessionReconnectSignals` + `onReconnectSessionPlane`）变成 `up` 跃迁上的 effect。持久重试判据内化为 `id == _activeHomeId && phase != up`。

### 5. 测试策略与迁移

内循环每提交跑 `flutter analyze`；验证一律 `cd client && dart run tool/run_tests.dart <files>`（AGENTS.md 硬规则，禁直接 `flutter test`）。全量套件只在交付前跑一次。

**新增 TDD 测试**：

1. `ssh_home_connectivity_state_test.dart` —— 纯跃迁：`up` 清 failure、`profileInvalidated` 不进 `failed`、仅 activeHome 续命、投影表全覆盖。
2. `ssh_home_connectivity_supervisor_test.dart` —— 单飞 dial：并发 `activateHome` + `retryNow` 只产生一次 `clientFor`；断言无 invalidation；断言 `storageLive` 只在 lease 缓存后翻转。
3. **针对本 bug 的回归**：切 home 成功进入 `up` 后，无真实 transport close 时 stream 不得再出现 `reconnecting` / `disconnected`。
4. 两个 cubit 改为投影断言（无独立写状态）。
5. **热恢复不回归**：模拟「非 `up` → `up`」跃迁，断言 `runRemoteBootAfterConnect` 被触发且 `planeRebinding` hold 期间 `StartupGate` 仍显示进度页、`releasePlaneRebind()` 后进入应用。

**需保持全绿的既有测试**（`SshProfileDownException` / `waitUntilUp` 契约的调用方覆盖尤其重要）：`ssh_connection_gate_test.dart`、`ssh_connection_gate_factory_test.dart`、`ssh_profile_connection_coordinator_test.dart`、`ssh_profile_connection_coordinator_reconnect_test.dart`、`ssh_connection_cubit_test.dart`、`ssh_transport_close_test.dart`、`ssh_client_factory_worker_test.dart`、`ssh_connection_failure_test.dart`、`event_transport_client_test.dart`、`event_transport_controller_test.dart`、`storage_failure_test.dart`，以及 vault 迁移 / `remote_cli_readiness` / `session_chat_view` 的 down-gate 相关用例。

**四个提交（每步独立可验证）**：

| # | 提交 | 内容 | 验收 |
|---|---|---|---|
| 1 | `feat(ssh): add SshHomeConnectivityState and supervisor skeleton` | 新增文件，仅镜像现有 coordinator/gate/factory 事件；factory 与 cubit 不动 | 旧测试全绿 + 新状态机测试 |
| 2 | `refactor(ssh): make cubits projections of the supervisor stream` | 删 `_lastFailureStatus` / `_resolveStatus` 反推 / `_connectingIds` / `persistRetry` hook | 旧 SSH 测试全绿即等价 |
| 3 | `refactor(ssh): move dial ownership into the supervisor; factory becomes a pure pool` | 删 gate 字段、`part` 文件与 factory 里全部 `beforeIo`/`markX`；gate 私有化并把 `waitForSshProfileRecovery` 接到 `awaitAvailable`；单飞 dial；删 `_storageReconnects` | 新回归测试 + gate 消费者测试全绿，**本 bug 的修复点** |
| 4 | `refactor(ssh): collapse coordinator/gate/monitor into the supervisor` | 删 4 hook、`markX` 分发、boot `restartReconnect` 特例；接入 `activateHome`；把热恢复编排与 plane-rebind hold 接到 `changes` 跃迁 | 完整 SSH 测试目录 + 热恢复回归 |

## 边界情况

| 情况 | 行为 |
|---|---|
| 编辑 host 时正有在途 dial | `profileEdited` → `connecting`，用当前 profile 重新 dial；旧 in-flight 作废但**不**进 `failed` |
| 切到另一个 profile | `activateHome(prev → next)`：latch + suspend 旧，dial 新；旧 profile 不保留持久循环 |
| 进入 `up` 后 storage lease 自行退役 | 只重开 lease（plane-scoped），不翻 home `connected` |
| SSH 认证失败 / host key 变更 | `failed` + suspend，UI 提示改凭据 / 重新配对；`retryNow` 或编辑后可恢复 |
| 心跳抖动（`degraded`） | 仍投影 `connected`，不弹 banner |
| 非 activeHome 用尽重试 | `unreachable`，停止循环；用户点重连 → `reconnecting` |
| 用户在连接页取消重试 | `suspended`，停止循环，可随时「继续重试」 |
| 重连成功后远端 boot 失败 | 保持 `up`，数据面板各自重试，不退回连接页（沿用现有热恢复语义） |
| 恢复时需要换 home storage plane | `holdPlaneRebind()` 置位，`StartupGate` 停在进度页；`rebindHomeStoragePlane()` 完成后 `releasePlaneRebind()` 进入应用 |

## 未决 / 后续（非本增量）

- 演进到方案 2（纯 reducer / 事件溯源）：本设计的 `SshHomeConnectivityState` 就是那条缝，届时把三个私有引擎折叠成纯 `reduce(state, event)`。
- gate / coordinator 账本 / monitor 仍作为私有引擎并存，靠「外部一律只碰 supervisor」的纪律约束；可考虑后续加静态检查或把三者改成纯值对象。
- 多 home 并行连接、home 目标寻址稳定性（静态 IP / mDNS / 配对中继）。
