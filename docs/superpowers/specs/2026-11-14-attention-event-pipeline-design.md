# Attention 事件流水线设计

- 日期：2026-11-14
- 状态：待审阅
- 来源：移动端连接桌面端后，桌面 session 跑完一轮进入空闲，移动端希望可靠收到并通知；进一步要求按“最好的架构与可扩展性”重做，不考虑向下/向后兼容。
- 关联现状：
  - `client/lib/services/session_sync/chat_session_activity_source.dart`：busy → idle 边沿检测，直接 `publishAttention`
  - `client/lib/services/session_protocol/session_authority.dart`：内存广播 `attention` 流
  - `client/lib/services/session_protocol/session_server.dart` / `session_client.dart`：实时 `attention` 帧
  - `client/lib/app/bootstrap/session_runtime_wiring.dart`：远程 idle 的 `notifyRemoteAttention`
  - `client/lib/services/notification/session_idle_notification_service.dart`：本地 idle 通知
  - `client/lib/widgets/notification/session_idle_notification_listener.dart`：本地 idle 监听
  - `client/lib/cubits/notification_cubit.dart` + `notification_repository.dart`：应用内通知中心
  - `tools/teampilot_connect_relay/`：现有 pairing / SSH 拨号 relay
  - `client/lib/services/event/`：进程内 AsyncDispatcher（best-effort，不是持久日志）

## 结论

把“通知”从 session protocol 的旁路事件升级为**有持久化、有游标、可重放的 Attention 事件流水线**：

1. **Authority 是唯一生产者**：哪个进程拥有 seat 的运行时，哪个进程产生该 seat 的 attention。
2. **先 append 再广播**：attention 写入 authority 本地的 append-only log，成功后才发布到实时通道；崩溃恢复靠游标补发。
3. **至少一次投递 + 幂等消费**：客户端按 `eventId` 去重，按 `(authorityId, epoch, seq)` 游标推进。
4. **实时连接与 push 都只是 transport**：push 只做 wake-up hint，默认不携带敏感内容；内容由客户端通过 live/relay 拉取。
5. **通知策略只有一个实现**：本地、远程、前台、后台、push 全部走同一个 `NotificationPolicy`。
6. **后台能力抽成 ConnectionSupervisor**：Android 前台服务、桌面 tray、未来 iOS push-only 都是它的平台实现，不散落在 boot wiring。

不保留旧协议、旧 attention id、旧本地/远程两套通知分叉。

## 目标

1. 桌面端正常完成一轮后，移动端在以下场景都能收到通知：
   - 前台且未看该 session：应用内通知 + OS 通知。
   - 后台 / 锁屏 / 息屏：保持连接时收到 OS 通知。
   - 断线后重连：补发断线期间的 idle 事件（至少一次）。
   - App 被杀 / 手机离线：有 push 时由 push 唤醒；没有 push 时至少下次打开能补到应用内通知。
2. 同一个事件无论经几条通道到达，只通知一次。
3. 通知开关、前台判断、静音、免打扰、当前会话过滤只实现一次。
4. 未来新增事件类型（等待审批、失败、后台任务完成）、新增 transport（relay、FCM、UnifiedPush、APNs）、新增设备角色，不改业务层。

## 非目标

- 不做完整事件溯源，不把聊天内容 delta 放进 attention log。
- 不替换现有 session protocol 的 `state` / `content` 通道。
- 不在本期实现 iOS / APNs。
- 不在本期实现端到端加密；但协议与 payload 设计必须为 E2EE 留缝。
- 不做跨 authority 的分布式共识；一个 seat 只有一个 writer，用 epoch 做 fencing。
- 不保证“App 被系统强杀后仍能实时收到”在没有 push 的情况下成立。

## 术语

- **AttentionEvent**：一个用户可能想知道的、可持久化的语义事实（idle / waiting / failed / info）。
- **AttentionLog**：authority 本地的 append-only 事件日志，按 `seq` 单调递增，有保留策略。
- **AttentionInbox**：客户端侧的消费端。负责去重、持久化、推进游标、向 UI 发新事件。
- **Cursor**：客户端已消费到的位置 `{authorityId, epoch, seq}`。
- **Authority**：拥有 seat 运行时的进程。桌面 local home 通常是 authority；手机通过 SSH 自己拉起的 session，手机是 authority。
- **Transport**：把事件从 authority 搬到 inbox 的通道。live SSH、relay WebSocket、push 都是 transport。
- **NotificationPolicy**：纯函数，决定 center / OS banner / sound / badge / push 的最终行为。
- **ConnectionSupervisor**：决定当前用 live 还是 push-only，并驱动平台保活能力的唯一 owner。

## 架构

```
Runtime owner (authority)
  SessionActivity / seat state
        │
        ▼
  AttentionProducer ── append ──▶ AttentionLog (durable, seq, epoch)
        │                              │
        │                              ├── LiveReplicator
        │                              │     ├─ session protocol v2 (SSH forward)
        │                              │     └─ relay WebSocket
        │                              └── PushGateway
        │                                    └─ pushHint {eventId, authorityId}
        ▼
  AttentionInbox (每设备、每 home)
        │  dedupe(eventId) + persist(cursor)
        ▼
  NotificationPolicy
        ├── NotificationCubit / in-app center
        ├── DesktopSystemNotifier / OS notification
        └── deep link payload
```

组件边界：

| 组件 | 位置 | 职责 | 不做什么 |
|---|---|---|---|
| `AttentionEvent` | `services/attention/attention_event.dart` | 领域模型、序列化、事件类型 | 不知道 transport |
| `AttentionLog` | `services/attention/attention_log.dart` | append、按 seq 读取、保留策略、快照 | 不广播、不通知 |
| `AttentionProducer` | `services/attention/attention_producer.dart` | 从 seat 状态边沿产生事件、生成 id、写 log | 不直接发通知 |
| `AttentionChannel` | `services/attention/channels/` | live/relay/push 的统一接口 | 不做策略 |
| `AttentionInbox` | `services/attention/attention_inbox.dart` | 去重、游标、持久化、fresh 流 | 不决定 UI 行为 |
| `NotificationPolicy` | `services/attention/notification_policy.dart` | 纯策略 | 不 I/O |
| `NotificationDispatcher` | `services/notification/` | 调 NotificationCubit / OS notifier | 不判断业务 |
| `ConnectionSupervisor` | `services/attention/background/` | live/push-only 选择、保活生命周期 | 不持有 UI |
| `BackgroundKeeper` | 平台实现 | Android FGS / 桌面 tray / iOS no-op | 不承载业务 |

分层规则：

- `services/attention/` 是纯 Dart 领域层，不 import Flutter/Bloc/UI。
- cubit 只依赖 `AttentionInbox` 的流，不直接依赖 transport。
- `app_shell` 只负责组装，不写通知判断。
- `services/event/` 的 AsyncDispatcher 可以用于进程内 fan-out，但**不能**当作持久日志；持久化以 `AttentionLog` 为准。

## 领域模型

```dart
enum AttentionKind { idle, waiting, failed, info }

final class AttentionEvent {
  const AttentionEvent({
    required this.eventId,
    required this.authorityId,
    required this.epoch,
    required this.seq,
    required this.sessionId,
    required this.memberId,
    required this.kind,
    required this.occurredAt,
    this.turnId,
    this.title = '',
    this.payload = const {},
    required this.expiresAt,
  });

  final String eventId;      // UUIDv7 / ULID；产生时生成一次
  final String authorityId;  // 设备或 home authority 标识
  final int epoch;           // authority 进程代次
  final int seq;             // authority 内单调递增，用于游标
  final String sessionId;
  final String memberId;
  final String? turnId;
  final AttentionKind kind;
  final DateTime occurredAt;
  final String title;        // 可选；push 默认不发送
  final Map<String, Object?> payload;
  final DateTime expiresAt;
}
```

不变量：

- `eventId` 全局唯一，是唯一幂等键。
- `seq` 由 `AttentionLog` 分配，不是 producer 生成；同一 `(authorityId, epoch)` 内严格单调。
- `epoch` 在 authority 每次启动时生成新值。
- `sessionId` + `memberId` + `turnId` 共同定位 seat 回合；不要求唯一。
- `payload` 只放展示所需的小字段，禁止放聊天正文。

事件生成规则（第一版）：

| 输入 | 条件 | 事件 |
|---|---|---|
| seat 从 busy → 非 busy | 正常完成，`readyToChat == true` | `idle` |
| seat 从 busy → 非 busy | 失败 | `failed`（后续阶段） |
| seat 进入等待用户输入/审批 | 由 attention 源提供 | `waiting`（后续阶段） |

第一版只实现 `idle`，但模型、存储、策略从一开始就按多 kind 设计。

## 存储

### Authority log

- 位置：authority 本地的 `<teampilotRoot>/attention/log-<epoch>.jsonl`。
- 写入：`Filesystem.appendString` 追加一行 JSON；成功后更新内存索引。
- 读取：内存索引按 `seq` 排序；启动时扫描文件重建索引，损坏行跳过并告警。
- 保留：默认 7 天或 1000 条，二者先到为准；压缩时原子重写文件。
- 快照：客户端首次连接或游标过期时，服务端发送当前可用的最早 `seq` 与保留窗口；客户端游标小于最早 `seq` 时降级为“只拉最新 N 条”，并标记 `gap: true`。

> 不用 SQLite：log 在 authority 本地，但读取路径需要兼容 `Filesystem` 抽象；append-only JSONL 与现有 `notifications.json`、`session-protocol.json` 风格一致。若未来事件量变大，可在 `AttentionLog` 接口后替换为 SQLite，不影响上层。

### Client inbox / cursor

- 位置：**设备本地**应用数据目录，不写 home 平面；避免每次事件走 SFTP。
- `attention_inbox.json`：`{version, cursors: {homeId: {authorityId, epoch, seq}}, recentEventIds: [...], lastSeenAt}`
- `recentEventIds` 保留最近 N 条（默认 512）用于跨通道去重；超出后由游标兜底。
- 应用内通知继续写现有 `NotificationCubit` 的 home 平面 `notifications.json`，保持通知中心跨设备一致。

## 协议 v2

既然不兼容旧版，直接替换 `sessionProtocolVersion` 为 2，删除 `attention` / `attentionAck` 的旧语义，改为日志复制：

```text
hello {
  deviceId,
  cursors: {
    <authorityId>: { epoch, seq }
  }
}

helloAck {
  proto: 2,
  authorityId,
  epoch,
  earliestSeq,
  latestSeq,
  caps: [attention.log.v1, ...]
}

events {
  authorityId,
  epoch,
  fromSeq,
  toSeq,
  events: [AttentionEvent...],
  gap: bool
}

ack {
  authorityId,
  epoch,
  seq
}

resync { authorityId, reason }
```

流程：

1. 客户端连接后发 `hello`，带每个 authority 的游标。
2. 服务端先发 `helloAck`，再发 backlog：从 `seq > cursor` 开始批量 `events`。
3. 客户端持久化事件、推进游标，发 `ack`（可合并/节流）。
4. backlog 完成后进入 live：新事件立即 `events`。
5. 连接断开：客户端保留游标，下一轮 `hello` 继续补发。
6. epoch 不一致：客户端丢弃该 authority 的旧游标，按 `helloAck.earliestSeq` 决定补发还是降级。
7. 服务端发现客户端游标早于保留窗口：`gap: true`，客户端标记该区间不可恢复，只展示后续事件。

`events` 批量上限默认 200 条或 256 KiB，避免一次帧过大。

## 生产与所有权

- 每个 seat 只有一个 writer：
  - 桌面 local home 拥有桌面 App 打开的 session。
  - 手机通过 SSH 自己拉起的 session，手机拥有。
  - 远程 authority 拥有的 seat，手机只消费，不重复生产。
- `SeatOwnership` 来自 session protocol 的 seat 快照与本地 tab 运行时状态；`AttentionProducer` 只对“本地拥有”的 seat 产生事件。
- 手机本地产生的 attention 直接进入本地 `AttentionInbox`（进程内 channel），不经过 session protocol server。
- epoch fencing：authority 重启后旧 epoch 的事件不参与新游标；客户端收到新 epoch 的 `helloAck` 时重置该 authority 游标。

## 客户端消费与通知策略

### AttentionInbox

```dart
final class AttentionInbox {
  Future<void> ingest(Iterable<AttentionEvent> events);
  Stream<AttentionEvent> get fresh; // 已去重、已持久化
  Cursor? cursorFor(String homeId);
}
```

- `ingest` 在单个串行队列内执行：去重 → 持久化 → 推进游标 → emit。
- 同一事件重复到达时返回，不重复 emit。
- 游标推进必须是幂等的；ack 失败只影响补发，不影响已展示。

### NotificationPolicy

```dart
final class NotificationDecision {
  const NotificationDecision({
    this.recordCenter = false,
    this.showOsNotification = false,
    this.sound = false,
    this.badge = false,
    this.push = false,
    this.aggregateKey = '',
  });
  // ...
}

NotificationDecision decide({
  required AttentionEvent event,
  required AttentionPreferences prefs, // 从 SessionPreferences 派生
  required AppFocusState focus,        // resumed / background / pushOnly
  required String? activeSessionId,
  required DeviceRole role,            // desktop / phone
});
```

策略表（第一版）：

| 条件 | center | OS banner | 备注 |
|---|---|---|---|
| `notifyOnSessionIdle == false` | ✅ | ❌ | 应用内仍记录 |
| App 在前台且 `activeSessionId == event.sessionId` | ❌ | ❌ | 用户正看着它 |
| App 在前台但看别的 session | ✅ | ✅ | 与本地路径一致 |
| App 在后台 / 锁屏 | ✅ | ✅ | 受系统权限限制 |
| push-only（无 live 连接） | ✅ | ✅ | push 唤醒后补拉 |
| 同一 aggregateKey 在窗口内多条 | 合并 | 合并 | 默认 5 秒窗口 |
| `waiting` / `failed` | ✅ | ✅ | 优先级高于 idle |

- 所有路径只调用一次 `decide`。
- OS 通知仍由 `DesktopSystemNotifier` 执行；策略只决定“要不要”。
- 通知中心继续用 `NotificationCubit.record`；不再在 wiring 里手写。

### 深链

payload 统一为：

```text
teampilot://home/<homeId>/session/<sessionId>?member=<memberId>&event=<eventId>
```

点击时：

1. 若当前 home 不是 `<homeId>`，先切 home。
2. 打开 session，定位 member。
3. 将 eventId 标记已读，避免重复通知。

## Transport

### 统一接口

```dart
abstract interface class AttentionChannel {
  Stream<AttentionBatch> get incoming;
  Future<void> start(CursorStore cursors);
  Future<void> ack(String authorityId, int epoch, int seq);
  Future<void> stop();
}
```

### Live channels

- `LocalAttentionChannel`：手机本地 producer → inbox，进程内直连。
- `SshAttentionChannel`：现有 `session-protocol.json` + `forwardLocal`，承载协议 v2。
- `RelayAttentionChannel`：连接 relay 的 WebSocket，适合 NAT/无法直连 SSH 的场景；与 SSH 通道互斥或并存，由 ConnectionSupervisor 选择。
- 多通道并存时，`AttentionInbox` 用 `eventId` 去重。

### Push channel

- 接口：

```dart
abstract interface class PushProvider {
  Future<void> register({required String deviceId, required String token});
  Future<void> unregister(String deviceId);
}
```

- 第一版参考实现：relay + FCM。
  - 桌面在 `AttentionLog.append` 成功后向 relay 发送 `POST /events`，带 `hostId`、`eventId`、`kind`、`sessionIdHash`。
  - relay 按 host 绑定的设备列表发 FCM data message：`{type: "attention", hostId, eventId}`。
  - 手机后台 handler 只做两件事：发通用本地通知（如果拉取不到详情），或拉起短连接拉取事件后再走 `NotificationPolicy`。
- 备用实现：UnifiedPush / ntfy。relay 只依赖 `PushProvider` 接口。
- push 内容默认不含 session title；用户显式允许锁屏详情时才在加密 payload 中携带。

## 后台：ConnectionSupervisor

```text
offline ──connect──▶ connecting ──ok──▶ connected
                         │                 │
                         │                 ├─ app background ─▶ backgroundLive (FGS)
                         │                 └─ no keeper/denied ─▶ pushOnly
                         └─ fail ─▶ backoff ─▶ offline
```

- `ConnectionSupervisor` 是唯一决定“现在用哪个 channel”的地方。
- 平台实现：

| 平台 | `BackgroundKeeper` |
|---|---|
| Android | 原生前台服务，`foregroundServiceType="connectedDevice"`，常驻低优先级通知；不额外起 Flutter engine |
| 桌面 | 窗口隐藏/托盘，进程本身常驻；不强制 |
| iOS（未来） | no-op + `pushOnly` |

- Android 前台服务只做保活与常驻通知，不承载业务；Dart 侧仍拥有 SSH/session-protocol 连接。
- 用户偏好新增 `keepRemoteConnectionInBackground`（默认 false）与 `pushOnlyFallback`（默认 true）。
- 设置页提供电池优化说明与系统设置入口，不直接申请敏感权限。
- 从最近任务划掉 App 时，`FlutterActivity` 默认销毁引擎；FGS 不能保证恢复。该场景由 push-only 覆盖，不承诺 live 保活。

## 与现有组件的迁移

删除/替换（不做兼容）：

| 现有 | 处理 |
|---|---|
| `SessionAuthority._attention` + `publishAttention` | 替换为 `AttentionLog` + `AttentionProducer`；保留 `attention` 名字仅作为对外语义 |
| `SessionMessageType.attention` / `attentionAck` | 删除，改用 `events` / `ack` |
| `ChatSessionActivitySource` 内直接 `publishAttention` | 改为产生 `AttentionEvent` 并 append |
| `notifyRemoteAttention` 闭包 | 删除，统一到 `AttentionInbox` + `NotificationPolicy` |
| `SessionIdleNotificationListener` 的本地路径 | 保留为 UI 触发，但决策改走 `NotificationPolicy`；或直接由 inbox 驱动 |
| `SessionPreferences.notifyOnSessionIdle` | 保留，作为 `AttentionPreferences` 的来源之一 |
| `services/event` 的 presence transport | 不混用；attention 有自己的持久日志。presence 仍可独立 |

## 故障语义

| 场景 | 保证 |
|---|---|
| append 后、广播前崩溃 | 客户端重连按 cursor 补发 |
| 客户端收到但未 ack 后崩溃 | 重连重发；eventId 去重 |
| 同一事件经 SSH + push 双到 | inbox 去重，只通知一次 |
| authority 重启 / epoch 变化 | 客户端重置该 authority 游标，按 `earliestSeq` 补发或标记 gap |
| 客户端游标早于保留窗口 | `gap: true`；只展示后续事件，UI 可提示“部分历史不可恢复” |
| push 先到、详情拉取失败 | 发通用通知；下次连上补详情 |
| 多设备 | 每设备独立 inbox/cursor/偏好；事件可重复投递，不重复展示 |
| 多个 home | inbox 按 `homeId` 分区；深链带 homeId |
| 网络抖动 | channel 退避重连；游标不丢 |

## 可扩展性

新增事件类型：加 `AttentionKind` + producer 边沿 + policy 表，不动传输。
新增 transport：实现 `AttentionChannel`，不动 inbox/policy。
新增 push 提供商：实现 `PushProvider`，不动 relay 语义。
新增平台：实现 `BackgroundKeeper`，不动 ConnectionSupervisor 上层。
新增设备角色：扩展 `DeviceRole` 与 policy，不动事件模型。
新增团队/工作区过滤：在 policy 输入加过滤维度，不动 log。

## 安全与隐私

- relay 只做事件会合与 push 分发，默认看不到聊天正文。
- push payload 默认只有 `eventId` / `hostId`；标题可选且需用户显式开启。
- 后续 E2EE：authority 用配对设备公钥加密事件 payload；relay 只转发密文。协议字段预留 `enc` 版本与 `keyId`。
- 设备 token 与 host 绑定；解除配对时撤销 token。
- 通知内容锁屏可见性作为独立偏好。

## 测试

1. **领域单测**
   - busy → idle 边沿只产生一次事件。
   - 取消/失败不产生 idle。
   - 多 seat 只对选中/对应 seat 产生事件。
2. **Log 单测**
   - seq 单调、重启后从文件恢复。
   - 保留策略、损坏行跳过。
3. **Inbox 单测**
   - 重复、乱序、跨通道去重。
   - 游标推进幂等；ack 失败不影响已展示。
   - epoch 变化与 gap。
4. **Policy 单测**
   - 开关、前台/当前会话、后台、push-only、聚合窗口。
5. **协议 contract 测试**
   - hello/cursor/backlog/ack/live。
   - 批量上限、帧过大、断线重连。
6. **故障注入**
   - append 后断线、ack 前崩溃、push 与 live 双到、relay 延迟。
7. **平台**
   - Android FGS 手工验证：锁屏、切后台、息屏、Doze、电池优化、划掉 App。
   - 桌面托盘/后台行为。

所有纯 Dart 测试走 `cd client && dart run tool/run_tests.dart <paths>`，不使用 `flutter test`。

## 分阶段实施

- **Phase 0 — 领域与本地统一**
  - `AttentionEvent` / `AttentionLog` / `AttentionInbox` / `NotificationPolicy`。
  - 桌面本地 idle 通知改走新管线；删除 `notifyRemoteAttention` 旁路。
  - 保留现有 session protocol 的 attention 帧作为临时输入，但立即转成事件（仅本阶段）。
- **Phase 1 — 协议 v2 与游标补发**
  - `sessionProtocolVersion = 2`；`hello/events/ack/resync`。
  - authority log 持久化、客户端 cursor 持久化、断线补发。
  - 删除旧 `attention` / `attentionAck`。
- **Phase 2 — ConnectionSupervisor 与 Android 前台服务**
  - 新偏好、状态机、原生 service、常驻通知、push-only 降级。
- **Phase 3 — relay push gateway**
  - 设备注册、`POST /events`、FCM `PushProvider`、在线抑制、E2EE 预留。
- **Phase 4 — 多设备与体验**
  - 聚合窗口、免打扰、每 session/team 静音、锁屏详情、iOS/APNs。

Phase 0 + 1 解决“错过即丢、本地远程两套策略”，且不需要 Firebase；Phase 2 解决后台/锁屏；Phase 3 才解决 App 被杀/离线。

## 风险与取舍

| 风险 | 取舍 |
|---|---|
| 事件模型过重 | 第一版只实现 idle，但字段与接口按多 kind 设计；不提前实现 waiting/failed |
| JSONL 文件增长 | 保留窗口 + 压缩；接口后可换 SQLite |
| 多 authority 复杂 | 第一版单 home 单 authority；数据结构按多 authority 设计，不做并发调度 |
| FGS 被 OEM 杀 | 明确边界；提供电池优化引导；不承诺划掉 App 后 live 保活 |
| push 隐私 | 默认只推 hint；详情拉取；E2EE 预留 |
| relay 信任 | 只做会合与转发；后续 E2EE；token 可撤销 |
| 与现有 presence transport 重复 | attention 与 presence 语义不同：presence 是“现在忙不忙”，attention 是“发生过需要你知道的事”；不合并 |

## 验收标准

1. 桌面 session 正常完成，移动端前台/后台/断线重连三种场景都能收到且只收到一次通知。
2. 关闭 `notifyOnSessionIdle` 后，任何路径都不弹 OS 通知，但应用内仍记录。
3. 桌面重启、移动端重启、SSH 断线后，游标正确补发；不重复弹旧通知。
4. `flutter analyze` 无新增问题；Phase 0/1 的领域、log、inbox、policy、协议测试全绿。
5. 不引入 `print`；诊断走 `AppLogger`；l10n 走 slang。

## 待确认

1. Phase 0 + 1 是否作为第一份实现计划？建议是。
2. Android 前台服务是否接受常驻通知，以及默认开关是 on 还是 off？建议默认 off，用户显式开启。
3. push 阶段是否接受引入 Firebase/FCM，还是优先自建 UnifiedPush/ntfy？建议先做 `PushProvider` 接口，FCM 作为第一个实现。
