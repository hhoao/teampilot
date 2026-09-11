# Event Transport 设计（期 3 第一刀）

- 日期：2026-09-12
- 状态：待审阅
- 前置：期 1 中央事件发布层；期 2 agent presence 事件化（均已合入 `main`）。交接：`docs/superpowers/HANDOFF.md`
- 目标：把进程内 `AsyncDispatcher` 的允许列表事件，经现有 SSH / Connect 通道送到手机上的同一个 dispatcher，使手机看到桌面正在占用的 session 及其 agent availability，且通道可扩展到后续 family（聊天失效不在本期）。

## 背景

2026-08-28 的原始需求是：手机看到桌面正在运行的 session，并及时更新聊天记录。失败分支 `feat-host-session-runtime` 用守护进程一次性重写，未合并。期 1/2 已把进程内事件基建做完；dispatcher 仍只在本进程里。

现状（已核对代码）：

- 手机经 SSH / Connect 挂同一份 desktop home。会话列表已经在磁盘上（`session.json`）；看不到的是桌面进程里的占用与 availability。
- `AgentPresenceProjection` 已是 app 生命周期投影；`MemberPresenceCubit` 读投影。发布边喂的是计算值，不是投影值。一跳延迟是正常的。
- `reportAvailability(null)` 只清 `PresenceEventBridge` 基线、**不发事件**；`removeSeat` 只在 cubit `close()` 时调用且不广播。纯订阅消费者会漏同值重连。本期修这条，否则手机接不上。
- 聊天记录已有 `TranscriptChangeSignal`（远程 FS 上 2s poll）。本期不改；下一刀在同一 transport 上加 `TranscriptInvalidated`。
- 嵌入式 sshd（`tp_sshd`）尚未合入。本期用 dartssh2 已有的 `forwardLocal`，协议与传输解耦，以后只换通道。
- 本仓库跨边界转发已有「relay」一词（catalog bus、Connect relay）；本期组件不叫 Hub / Relay，叫 **Transport**：它不是新总线，是 dispatcher 的过线方式。

## 目标与非目标

### 目标

1. 桌面（local home）在 loopback 上导出允许列表事件；手机（ssh home）经同一条 SSH 连接订阅，解码后 `dispatch` 到本地 `AsyncDispatcher`。
2. 线上 family 标签化：未知 family 丢弃。加新 family 只加 codec + 允许列表项，不改通道。
3. 本期上线两个 family：`agentPresence`（含 snapshot + 墓碑）与 `sessionLifecycle`（只直播、不 snapshot）。
4. 修期 2 墓碑：断连走出 `cleared` 事件；投影 `removeSeat` 且广播 `changes`。
5. 手机 occupancy：seat 出现在投影里 = 桌面仍占着该 session；不依赖手机是否拉起了 PTY。
6. transport 失败时手机退回今天的磁盘 + 轮询，不能卡死 home。

### 非目标

- 不新做 daemon / Runtime 进程。
- 不把 `WorkspaceFsChanged`、catalog 变更、PTY 字节送出站。
- 不做聊天失效事件、不上线 connection 维度、不事件化 roster / `isWorking`。
- 不做应用层 ping、不做额外鉴权（能 SSH 进这台机器的人已经能读整个 home）。
- 不从失败 runtime 分支搬 `runtime_framing`。
- 不实现 `tp_sshd`；不把 Unix domain socket 当默认（Windows 系统 sshd 的 streamlocal 不可靠）。
- 不做查询面 / RPC。连上时的 snapshot 是订阅握手的一部分，不是通用查询。
- 手机不向桌面回发 presence（无反向通道）。

## 拓扑

```
桌面 TeamPilot（生产者，local home）
  AsyncDispatcher
       │ 允许列表：agentPresence、sessionLifecycle
       ▼
  EventTransportServer  ← 绑定 127.0.0.1:0
       │ 广告文件：<teampilotRoot>/event-transport.json
       │
  ── SSH（现有 Connect / sshd）──  phone.forwardLocal('127.0.0.1', port)
       │
手机 TeamPilot（订阅者，ssh home）
  EventTransportClient 解码 → 本地 AsyncDispatcher
       ▼
  AgentPresenceProjection / cubit（纯订阅，无 PresenceEventBridge）
```

硬约束：

1. **不新做 daemon。** Server 活在桌面 app 进程里。
2. **dispatcher 词汇不过线改写。** 线上是 `{v, type, family, ...}`。
3. **只出站允许列表。** 默认拒绝未列出的 family。
4. **信任模型不升级。** Server 只绑 `127.0.0.1`。
5. **Windows 走 TCP loopback + 端口文件。** `tp_sshd` 合入后只换通道，不换帧。

角色由 home 互斥决定：

| home | 角色 | cubit |
|---|---|---|
| local（桌面） | 开 Server | **带** `PresenceEventBridge`（生产者） |
| ssh（手机） | 开 Client | **不带** bridge（纯消费者） |
| Termux / 纯本机手机 | 两端都不开 | 与今天相同 |

`services/event/` **不 import** dartssh2。SSH 接线只存在于 `app_shell` / ssh 层：读广告文件、`forwardLocal`、把 channel 交给 Client。Client 只依赖字节流（`Stream<List<int>>` + `void add(List<int>)`），测试用 fake。

## 线上协议

UTF-8 NDJSON，一行一个 JSON 对象（`jsonEncode`，不 pretty-print）。presence / 会话生命周期是低频事实，不是 PTY 字节。

每行必有整数 `v` 与字符串 `type`。`v != 1` 或未知 `type` / 未知 `family`：丢弃该行，**不断开**。单行硬上限 **65536** 字节（含换行前）；超过则对该连接写 `error` 后关闭。其它连接不受影响。

### 握手

客户端连上后第一条必须是 `subscribe`，否则 **5 秒**超时断开。

```json
{"v":1,"type":"subscribe","families":["agentPresence","sessionLifecycle"]}
{"v":1,"type":"subscribed","families":["agentPresence","sessionLifecycle"]}
```

`subscribed.families` = 请求 ∩ Server 允许列表 ∩ 本端已注册 codec。未知 family 不报错，只是不出现在结果里。Server 在发出 `subscribed` 之前不写业务行。

### Snapshot 后再直播

晚加入者不能空等下一次变化。只对 `agentPresence` 做 snapshot；`sessionLifecycle` 本期只直播（会话列表已在磁盘上；是否占用看 presence 投影里有没有该 `sessionId` 的 seat）。

```json
{"v":1,"type":"snapshotBegin","family":"agentPresence"}
{"v":1,"type":"event","family":"agentPresence","op":"set","seat":{"sessionId":"s","memberId":"dev"},"kind":"working","ts":"2026-09-12T00:00:00.000Z"}
{"v":1,"type":"snapshotEnd","family":"agentPresence"}
{"v":1,"type":"event","family":"agentPresence","op":"set","seat":{"sessionId":"s","memberId":"dev"},"kind":"idle","ts":"..."}
{"v":1,"type":"event","family":"agentPresence","op":"clear","seat":{"sessionId":"s","memberId":"dev"},"ts":"..."}
```

规则：

1. 接收端见到 `snapshotBegin`：调用 `AgentPresenceProjection.clearAll()`（丢掉全部条目，对每个被丢掉的 seat 发一次 `changes`），再应用窗口内的 `set`。重连不会留下上一轮 seat。
2. snapshot 窗口里只有 `op:set`。空投影 = `snapshotBegin` 紧挨 `snapshotEnd`。
3. `op:clear` 是墓碑，不是第四种 availability。`kind` 仅在 `op:set` 时出现，取值 `booting` / `working` / `idle`。
4. 桌面单线程、无 await 的顺序：拷贝 `projection.snapshot` → 为这条连接注册 dispatcher handler → 写 snapshot。投影对同值幂等，与 live `set` 重叠是安全的。
5. 不做应用层 ping。半开连接靠现有 SSH keepalive。
6. 协议错误行：`{"v":1,"type":"error","code":"oversize"|"protocol","message":"..."}`，然后关闭该连接。

`sessionLifecycle` 的 live `event` 行携带已有字段：`kind`（`sessionSpawned` / `sessionStarted` / `sessionClosed`；seat 级 kind 若日后有发布点，同一 codec 带上 `memberId`）、`sessionId`、`workspaceId`、`ts`。本期不要求 seat 级 publish 点（它们在期 1 仍是词汇 only）。手机对本 family **只入本地 dispatcher**，不做新 UI 消费者——列表已在磁盘上，占用看 presence 投影。上线它是为了通道在第一天就按 family 求交工作，避免下一刀再改握手。

### 广告文件

路径：`<teampilotRoot>/event-transport.json`（实施时写入 `docs/workspace-storage-layout.md` 顶层清单）。

```json
{"v":1,"bindHost":"127.0.0.1","port":49152,"pid":1234,"startedAt":"2026-09-12T00:00:00.000Z"}
```

Server 只绑 `127.0.0.1`。TCP 拒绝 = 桌面没开。手机不校验远程 pid（跨 SSH 无意义）；connect 失败则退避再读文件。桌面重启写新端口。

## 进程内墓碑（期 2 遗留，本期变为负载）

YARN 一个 family 一把 kind 枚举，`DispatcherEvent.eventKind` 非空。因此 `AgentPresenceKind` **增加** `cleared`（动词，与 `SessionLifecycleKind.sessionClosed` 同类）。

- `MemberAvailability` **不**增加值。`cleared` 不是 availability。
- 线上仍然用 `op:clear`，codec 映射：`booting|working|idle` ↔ `op:set`；`cleared` ↔ `op:clear`。
- 现有 `registerFamily<AgentPresenceKind>(AgentPresenceKind.working.runtimeType, …)` 已按枚举的 `runtimeType` 注册，覆盖新增值，不必二次注册。

连带：

1. `PresenceEventBridge.reportAvailability(seat, null)`：**发布** `AgentPresenceKind.cleared`，并清基线（不再静默）。`forget` / `dispose` 语义不变。
2. `AgentPresenceProjection.handle(cleared)`：`removeSeat` **且** 向 `changes` 广播该 seat（今天 `removeSeat` 不广播）。新增 `clearAll()` 供 `snapshotBegin` 使用。
3. cubit：`cleared` → availability `null`。`close()` 仍对 `_knownSeats` 做清理；断连不再只靠 close。
4. 发布边继续喂**计算值**，不是投影值（期 2 坑 1）。一跳延迟仍是正常的（期 2 坑 2）。

## 组件

| 文件 | 职责 |
|---|---|
| `client/lib/services/event/event_transport_codec.dart` | NDJSON 行 ↔ 消息；family 注册表 |
| `client/lib/services/event/event_transport_server.dart` | bind、写广告、握手、snapshot、按连接 fan-out |
| `client/lib/services/event/event_transport_client.dart` | subscribe、把行变成 `dispatch`、重连退避 |
| `client/lib/services/event/agent_presence_transport_codec.dart` | `agentPresence` |
| `client/lib/services/event/session_lifecycle_transport_codec.dart` | `sessionLifecycle` |
| ssh / `app_shell` 接线 | 读广告、`forwardLocal`、按 home 起停角色 |

Server 是 dispatcher 的又一个 multicast handler，不取代 cubit。snapshot 读同一个 app-lifetime `AgentPresenceProjection`。每个 TCP 连接独立握手、独立 snapshot，之后加入同一 multicast；一条连接出错不影响其它手机。

启动顺序（桌面）：dispatcher `start` → 注册 projection → 启动 Server。

生命周期：Server / Client 与 dispatcher、projection 一样 **进程一份**。禁止每次 `buildAppShell` 再绑一个口。home 从 local 切到 ssh（或反过来）：停掉旧角色，按新 home 起另一角色；新握手的 `snapshotBegin` 负责清空。

Client 重连：指数退避 1s → 2s → 4s … 封顶 30s；广告文件内容变化则立刻重试。SSH 断开则停 Client；SSH 恢复后再读广告、再 `forwardLocal`。

### 手机 occupancy

「桌面正在跑这个 session」= `AgentPresenceProjection.snapshot` 里存在该 `sessionId` 的 seat（`booting` / `working` / `idle` 都算占用；`cleared` 或 snapshot 清空 = 不再占用）。connection 维度不上线：在投影里就当作 connected。

侧栏 Running / 忙闲不能只靠手机本地的 `ChatState.busySessionIds`（那是本进程 `sessionActivities`，手机没拉 PTY 时是空的）。Client 在线时，占用视图读投影。打开某个 session 的聊天仍走现有 History poll；本期不改是否发射 PTY。

## 失败模式

降级原则：transport 挂了，少一次实时刷新，不是进不去 home。

| 情况 | 行为 |
|---|---|
| 桌面没开 / 广告缺失 / TCP 拒绝 | Client 不抛给 UI；退避重读文件 |
| 桌面崩溃后端口文件过期 | connect 失败，同样退避；桌面重启写新文件 |
| SSH 断开 | 停 Client；SSH 恢复后再订 |
| 行不是 JSON / 缺字段 / 超 64KiB | 该连接 `error` 后关闭；其它连接不受影响 |
| `v != 1` 或未知 family / type | 丢弃该行 |
| subscribe 超时 | 关连接，走退避 |
| Server bind 失败 | 打日志，不写广告；桌面自己的 presence 不受影响 |
| 单条 handler 抛错 | 期 1 纪律：log + 继续 |

## 测试

假字节流，不启真 SSH。

- codec 往返：`set` / `clear` / sessionLifecycle；未知 family 与 `v != 1` 被丢。
- 握手：family 求交；subscribe 超时。
- `snapshotBegin` 清空再应用；空投影 = begin 紧挨 end。
- 两个 Client 都能收到同一条 fan-out。
- `reportAvailability(null)` 发出 `cleared`；投影 `removeSeat` 且 `changes` 含该 seat。
- cubit 把 `cleared` 映成 availability `null`。
- ssh home 路径不构造 `PresenceEventBridge`。
- Server 只 bind loopback。
- 既有 presence / coordination 测试 **一行不改** 仍通过（桌面行为等价）。

验收：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净 + `dart run tool/run_tests.dart` 全套绿。读摘要行，不信 runner 退出码。若测试要等真实定时器，用 `_waitFor(predicate, timeout)`，负向用例等待数倍于上限。

跑全套时 `floating_workspace_panel_gestures_test.dart` 的 overflow 失败与本路线无关，不要顺手改。

## 与后续期的接缝

- **聊天记录（期 3 第二刀）：** 同一 transport 增加 `transcriptInvalidated` family；手机收到后走现有 `AiHistoryLiveRefreshController.softReload`。本期协议的 family 求交就是为它留的。
- **`tp_sshd`：** 日后用 in-process subsystem 替代 `forwardLocal`；帧与 codec 不动。
- **期 4 Runtime daemon：** 仍冻结 `feat-host-session-runtime`。本 transport 是 app↔app，不是 daemon 接管 PTY。
- **期 2.5 hook 收敛：** 仍不碰 `agent_runtime/`。
