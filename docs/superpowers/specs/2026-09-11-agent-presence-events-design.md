# Agent Presence 事件族设计（期 2）

- 日期：2026-09-11
- 状态：待审阅
- 前置：期 1 中央事件发布层（`docs/superpowers/specs/2026-09-10-central-event-dispatcher-design.md`，已合入 main）
- 目标：把 agent 工作状态（booting / working / idle）从"轮询快照"改为"事件推送"，并让 presence 的消费方第一次真正通过中央 dispatcher 取数，为期 3 移动端同步打地基。

## 背景（现状事实，已核对代码）

availability 的当前推导链：

```
availability = MemberCoordination._bootingOr(whenReady)
  _bootingOr:            !activityTracker.isBootFrameReady → booting, 否则 whenReady
  whenReady(原生/单CLI):  shell.userTurnActive ? working : idle
  whenReady(Claude roster): claudeRosterWorking ? working : idle
```

- `booting` 来自 `TerminalActivityTracker.isBootFrameReady`，**惰性 getter + 超时驱动**（`bootQuietAfter` 静默或 `bootMaxWait` 上限），tracker 自身无定时器。
- `working/idle` 来自**回合锁存** `TerminalSession.userTurnActive`（`markUserTurnActive` 置位 / `markUserTurnIdle` 清除）或 roster 值——**不是** PTY 字节启发式。
- `TerminalActivityTracker.isWorking`（PTY 启发式）**不驱动** presence；它服务于 `usesShellActivity`、mixed 模式的 quiet 判定与 idle-watch。**本期不动这些路径。**
- 分发：`MemberPresenceCubit` 定时轮询 → `MemberPresenceService.compute()` → `MemberCoordination.resolve()`，把 `Map<memberId, MemberPresence>(connection + availability)` emit 给 UI。UI 读 cubit state。

## 目标与非目标

### 目标

1. 新增 `AgentPresenceEvent` 事件族（kind = `booting / working / idle`，与现有 `MemberAvailability` 1:1）。
2. 复合 availability 的**唯一权威规则仍由 `MemberCoordination` 持有**；新增 composer 在其输入变化时求值，**值变化才发事件**（去重）。
3. 新增 `AgentPresenceProjection`：订阅 dispatcher，维护 `Map<seatKey, MemberAvailability>`，向消费方提供查询与变更通知。
4. `MemberPresenceCubit` 的 availability 维度改为**读投影**；其轮询保留，只负责 connection 维度与 roster 输入采集。UI 契约不变。
5. 提供 posterity：期 3 移动端同步可直接订阅同一事件流 / 读同一投影。

### 非目标

- 不改 `TerminalActivityTracker.isWorking` 的语义与所有既有消费者（`usesShellActivity`、mixed quiet、idle-watch）。
- 不做 hook 路径（`agent_runtime` 的 `statusReported`/`seatIdle`）与 PTY 路径的合并语义——两个生产者写同一维度需要独立设计，留待期 2.5。
- 不改 UI 契约（UI 仍读 cubit state）。
- 不做跨进程传输（期 3）。

## 架构

```
生产者（原始输入，各自独立）
  ① TerminalSession 回合锁存转换   markUserTurnActive / markUserTurnIdle
  ② TerminalActivityTracker boot latch 转换   （需一次性定时器推送）
  ③ roster 值（由 cubit 轮询采集后推入）       setRosterWorking
                 │
                 ▼
  SeatPresenceComposer（每 seat 一个）
     · 持有 ② 的 bootReady 与 ① 的 turnActive 与 ③ 的 rosterWorking
     · 求值复用 MemberCoordination 的权威规则（_bootingOr）
     · 值变化才 publish(AgentPresenceEvent)
                 │
                 ▼
        AsyncDispatcher（期 1，中央）
                 │
                 ▼
  AgentPresenceProjection（订阅方）
     · Map<SeatKey, MemberAvailability>
     · query(seat) + changes 广播（供 cubit 重 emit）
                 │
                 ▼
  MemberPresenceCubit：availability 读投影；轮询保留（connection + roster 采集）
                 │
                 ▼
              UI（不变）
```

## 组件契约

### 1) 事件族 `client/lib/services/event/agent_presence_event.dart`

```dart
enum AgentPresenceKind { booting, working, idle }

final class AgentPresenceEvent implements DispatcherEvent<AgentPresenceKind> {
  const AgentPresenceEvent({
    required this.sessionId,
    required this.memberId,
    required this.eventKind,
    required this.timestamp,
  });
  final String sessionId;
  final String memberId;
  @override final AgentPresenceKind eventKind;
  @override final DateTime timestamp;
}
```

`SeatKey` 复用 `RuntimeSeatKey` 的形状（sessionId + memberId）；若 `agent_runtime` 的 `RuntimeSeatKey` 可直接复用则复用，否则在 event 包内定义等价 key 并注明。

### 2) 发布接口（窄接口，保持分层）

```dart
abstract interface class AgentPresenceSink {
  void publish(AgentPresenceEvent event);
}
```

- 实现类由 `app_shell` 用期 1 的 `EventPublisher.instance.attachedDispatcher` 构造并注入。
- `TerminalSession` 构造新增可选 `AgentPresenceSink?`；**默认 no-op**（未接线时行为与今天一致：不发事件）。
- 领域层（`services/team/`、`services/terminal/`）**不 import** `services/event/` 的 dispatcher；只依赖这个窄接口。tracker 连这个接口都不依赖（见下）。

### 3) tracker 改造 `terminal_activity_tracker.dart`

- 保留全部现有惰性 getter 与内部状态，**判定规则零改动**。
- 新增可选回调 `void Function(bool bootReady)? onBootFrameChanged`：在 `notePtyBytes`（PTY 热路径，位于既有单遍扫描之后）与 boot latch 求值处检查 `isBootFrameReady` 的翻转，**翻转才回调**。
- 新增**一次性定时器** `_bootTimer`：未 latch 且已有首个可见内容时，按 `bootQuietAfter` / `bootMaxWait` 中先到者排期；到期求值并回调；每次 `notePtyBytes` 重排。非周期轮询。
- `reset()`：cancel `_bootTimer`、清 latch 回调基线。
- tracker **不依赖事件层**、不知道 seat 身份。

### 4) composer（新，`client/lib/services/team/seat_presence_composer.dart`）

```dart
final class SeatPresenceComposer {
  SeatPresenceComposer({
    required this.seatKey,
    required MemberCoordination Function() currentCoordination,
    AgentPresenceSink? sink,
    DateTime Function()? clock,
  });

  void onTurnLatchChanged();              // ① 回合锁存转换时调用
  void onBootFrameChanged(bool ready);    // ② boot latch 翻转时调用
  void setRosterWorking(bool working);    // ③ cubit 轮询采集后推入
  MemberAvailability evaluate();          // 复用 MemberCoordination 规则求值
  void dispose();                         // 解绑：不再发、清状态
}
```

- 每次输入变化调用 `_publishIfChanged()`：求值 → 与上次发布值比较 → 变化才 `sink.publish(...)`。
- `sink == null` 时只维护内部值不发事件（测试与未接线场景）。
- 规则来源：调用方注入的 `currentCoordination()` 返回当前 `MemberCoordination`，`availability()` 即权威结果。**规则不复制**。

### 5) 投影 `client/lib/services/event/agent_presence_projection.dart`

- `implements EventHandler<AgentPresenceEvent>`；app_shell 注册到 dispatcher 的 `AgentPresenceKind` 族。
- 持有 `Map<SeatKey, MemberAvailability>`；`availabilityFor(seatKey)` 查询。
- 暴露 `Stream<SeatKey> changes`（广播；投影实现为 handler，向 Stream 适配是既定的消费形态），供 cubit 重 emit。
- 提供 `removeSeat(seatKey)`：会话关闭 / seat 解绑时清理条目。

### 6) cubit 迁移 `member_presence_cubit.dart`

- `_tickMemberPresence` 的 availability 部分改为 `projection.availabilityFor(seat)`；connection 仍由 `_connectionOf(shell)` 现算。
- 轮询保留：connection 维度仍需轮询；roster 值采集后经 `composer.setRosterWorking` 推入。
- 订阅 `projection.changes`，收到变更即重 emit（保持 UI 刷新延迟不劣于今天）。
- `MemberPresenceService.compute()` 的 availability 分支相应改为读投影（或由 cubit 直接组装，实现时按最小改动定；**规则仍只有 composer 一处**）。

## 生命周期与泄漏纪律（前两次 review 的考点，硬要求）

- composer 的 `dispose()` 必须在 seat 解绑路径调用（`TerminalSession._unbindObservation` 旁）；dispose 后不再发事件、从投影移除条目。
- tracker 的 `_bootTimer` 必须在 `reset()` 与 `dispose` 路径 cancel；不得有挂起定时器。
- 未绑定 seat（`sessionId`/`memberId` 为空）**不发事件**。
- 投影的 seat 条目必须随会话关闭清理，避免无界增长。

## 测试策略

- **tracker**：boot 翻转才回调（去重）、`bootQuietAfter` 与 `bootMaxWait` 两路触发、每次 notePtyBytes 重排、`reset()` 取消定时器（无挂起）、既有 tracker 测试原样通过。
- **composer**：组合值变化才发（去重）、boot/turn/roster 三输入各自的触发、`sink == null` 不发、`dispose()` 后不发。
- **投影**：多 seat 隔离、重复事件幂等、`removeSeat` 清理、changes 广播。
- **cubit**：availability 来自投影、connection 仍正确、roster 推入触发重 emit。
- **行为等价**：现有 presence / coordination / member_presence_cubit 测试原样通过。

### 验收标准

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净 + `dart run tool/run_tests.dart` 全套绿 + 既有 presence 相关测试未被修改地通过。

## Implementation notes (phase 2) — where shipped code deviates from the spec/plan

Recorded so the next reader knows these were deliberate, and why.

- **Composition ownership moved off `SeatPresenceComposer.evaluate()`.** The
  spec had a per-seat composer own the composition and publish on change. Shipped
  instead: the existing `MemberPresenceService.compute()` -> `MemberCoordination`
  path remains the single place that gathers inputs and computes availability,
  and `PresenceEventBridge` is a thin dedupe/publish edge fed the already-computed
  value (`MemberPresenceCubit._applyPresenceEvents`). Reason: a composer holding
  its own boot/turn/roster inputs would have duplicated input gathering that the
  poll path already does, with two copies of the rules to keep aligned.

- **`markUserTurnActive` -> `markUserTurnStarted`.** The spec named the setter
  `markUserTurnActive`; the real method on `TerminalSession` is
  `markUserTurnStarted`. No behaviour change, name only.

- **The bridge is built per bootstrap, not app-lifetime.** The spec implied one
  long-lived publish edge. Shipped instead: `app_shell` builds a fresh
  `PresenceEventBridge` per `buildAppShell`, owned by that shell's
  `MemberPresenceCubit`, which disposes it in `close()`. Reason: the cubit tears
  its bridge down on close, so a shared app-lifetime bridge would be killed by the
  first discarded shell. The `AgentPresenceProjection` and the sink stay
  app-lifetime (registered once in `_TeamPilotBootstrapState`).

- **`TerminalSession.onPresenceInputsChanged` is re-pointable.** It started as a
  final constructor-only field; it had to become a mutable field (null = detached)
  so the cubit could attach the push trigger when a target binds and clear only
  its own callback when the target changes. Read the current value, never cache
  it.

- **The publish edge takes the computed value, not the projected value.** Feeding
  the bridge the value the cubit is about to emit (the projection's) would make
  the edge self-referential — the projection's first output would be its own
  input and the loop would freeze. The fresh `MemberCoordination` result feeds the
  bridge; the projection is only a downstream cache. (Same point in the
  `services/event/README.md` family section.)

- **Deferred minors carried out of this phase** (accepted, not fixed here):
  tracker one-way-dispose interaction to revisit; projection dedupe baseline vs
  disconnect semantics; `MemberPresenceCubit._knownSeats` unbounded growth; a
  retained shell's teardown does not close its presence cubit; the wiring test
  asserts on source text.

