# Agent Presence 事件族实施计划（期 2）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 agent 工作状态（booting/working/idle）从轮询快照改为事件推送，并让 presence 消费方首次通过中央 dispatcher 取数。

**Architecture:** 保有一条权威求值路径（现有 `MemberPresenceService.compute()` → `MemberCoordination.availability()`，规则零改动），在其上增加一个**去重发布边**（`PresenceEventBridge`）：输入变化即触发重算，值变化才 `publish`。推送触发来自两处 —— `TerminalSession` 的回合锁存转换与 `TerminalActivityTracker` 的 boot latch 翻转（新增一次性定时器）。事件经期 1 的 `AsyncDispatcher` 广播，`AgentPresenceProjection` 归约成 `Map<seat, availability>`，`MemberPresenceCubit` 读投影（connection 维度仍轮询）。

**Tech Stack:** Dart 3 / Flutter（纯 Dart 逻辑 + 少量 cubit 改动）；测试 `flutter_test`。

**Spec:** `docs/superpowers/specs/2026-09-11-agent-presence-events-design.md`

## Global Constraints

- **绝不直接运行 `flutter test`** —— 一律 `cd client && dart run tool/run_tests.dart <paths>`。
- 内层循环：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件：`dart run tool/run_tests.dart test/<path> --plain-name <name>`；全套只在收尾跑一次。
- 日志用 `appLogger`，禁止 `print`。用户可见文案走 l10n（本计划无用户可见文案）。
- **领域层不 import dispatcher**：`services/team/` 与 `services/terminal/` 只依赖窄接口；`services/event/` 不依赖 `services/agent_runtime/` 或任何 feature 包。
- **本期不触碰** `client/lib/services/agent_runtime/`。
- **既有测试是行为等价证据**：`test/services/team/`、presence/coordination 相关测试原样通过（仅允许放宽等待时序，断言不得改）。
- 文件大小软限：`services/` ~600 行、`cubits/` ~500 行。`member_presence_cubit.dart` 已 232 行，只做外科式改动。
- 在 worktree `feat-agent-presence-events`（基于 `main`）中实施。

### 两处对 spec 的落实细化（实施者必读）

1. **命名**：spec 写 `markUserTurnActive`，实际方法名是 **`markUserTurnStarted()`**（`terminal_session.dart:147`）；`markUserTurnIdle()` 名称正确。
2. **组合位置**：spec 的组件契约里 composer 自己 `evaluate()`。本计划**改为**：bridge 不复制求值规则，而是**触发既有求值路径**（`MemberPresenceCubit` 已有的 `tickFromIdleWatch()` 入口，`member_presence_cubit.dart:116`）后对结果去重发布。理由：`compute()` 已经组装了 coordination 所需的全部输入（team/presets/bus/session/roster），在 bridge 里重建会复制输入采集逻辑，产生漂移风险；保持唯一求值路径是行为等价的保障。

---

### Task 1: 事件族类型 `AgentPresenceEvent` + `PresenceSeatKey`

**Files:**
- Create: `client/lib/services/event/agent_presence_event.dart`
- Test: `client/test/services/event/agent_presence_event_test.dart`

**Interfaces:**
- Consumes: 期 1 的 `DispatcherEvent<K>`（`client/lib/services/event/dispatcher.dart`，getter 名为 **`eventKind`**）。
- Produces:
  - `enum AgentPresenceKind { booting, working, idle }`
  - `final class PresenceSeatKey { const PresenceSeatKey({required String sessionId, required String memberId}); }`（值相等性 + hashCode）
  - `final class AgentPresenceEvent implements DispatcherEvent<AgentPresenceKind>`，字段 `PresenceSeatKey seat, AgentPresenceKind eventKind, DateTime timestamp`；便捷 getter `sessionId`/`memberId` 转发到 seat。

**设计说明（写进文件 doc comment）**：`agent_runtime` 已有 `RuntimeSeatKey`，形状相同但属 feature 包；事件包不得依赖 feature 包（分层），故此处独立定义，期 2.5 合并 hook 事件时做适配映射。

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/event/agent_presence_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';

void main() {
  test('carries seat identity through the event', () {
    final e = AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's-1', memberId: 'dev'),
      eventKind: AgentPresenceKind.working,
      timestamp: DateTime(2026, 9, 11),
    );
    expect(e.eventKind, AgentPresenceKind.working);
    expect(e.sessionId, 's-1');
    expect(e.memberId, 'dev');
    expect(e.timestamp, DateTime(2026, 9, 11));
  });

  test('seat key has value equality', () {
    const a = PresenceSeatKey(sessionId: 's', memberId: 'm');
    const b = PresenceSeatKey(sessionId: 's', memberId: 'm');
    const c = PresenceSeatKey(sessionId: 's', memberId: 'other');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_event_test.dart`
Expected: FAIL — `agent_presence_event.dart` 不存在。

- [ ] **Step 3: 实现**

```dart
// client/lib/services/event/agent_presence_event.dart
import 'dispatcher.dart';

/// Availability phase of one agent seat. Mirrors the model enum
/// `MemberAvailability` one-to-one (booting / working / idle).
enum AgentPresenceKind { booting, working, idle }

/// Seat identity (session + team member) for presence events.
///
/// Deliberately NOT `agent_runtime`'s `RuntimeSeatKey`: the event package must
/// not depend on a feature package. Phase 2.5 (hook-event convergence) maps
/// between the two.
final class PresenceSeatKey {
  const PresenceSeatKey({required this.sessionId, required this.memberId});

  final String sessionId;
  final String memberId;

  @override
  bool operator ==(Object other) =>
      other is PresenceSeatKey &&
      other.sessionId == sessionId &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(sessionId, memberId);

  @override
  String toString() => 'PresenceSeatKey($sessionId/$memberId)';
}

/// Emitted when a seat's composed availability changes value.
final class AgentPresenceEvent implements DispatcherEvent<AgentPresenceKind> {
  const AgentPresenceEvent({
    required this.seat,
    required this.eventKind,
    required this.timestamp,
  });

  final PresenceSeatKey seat;

  @override
  final AgentPresenceKind eventKind;

  @override
  final DateTime timestamp;

  String get sessionId => seat.sessionId;
  String get memberId => seat.memberId;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_event_test.dart`
Expected: PASS（2 个测试）

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/agent_presence_event.dart client/test/services/event/agent_presence_event_test.dart
git commit -m "feat(event): agent presence event family types"
```

---

### Task 2: 发布接口 `AgentPresenceSink` + dispatcher 实现 + no-op

**Files:**
- Create: `client/lib/services/event/agent_presence_sink.dart`
- Test: `client/test/services/event/agent_presence_sink_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `AgentPresenceEvent`；期 1 的 `Dispatcher`（`dispatch(DispatcherEvent)`）与 `AsyncDispatcher`（`registerFamily<K extends Enum>(Type kindType, EventHandler handler)`）。
- Produces:
  - `abstract interface class AgentPresenceSink { void publish(AgentPresenceEvent event); }`
  - `final class DispatcherAgentPresenceSink implements AgentPresenceSink`，构造 `DispatcherAgentPresenceSink(this._dispatcher)`
  - `final class NoopAgentPresenceSink implements AgentPresenceSink`（`const`），`publish` 空实现

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/event/agent_presence_sink_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';

class _Recorder implements EventHandler<AgentPresenceEvent> {
  final events = <AgentPresenceEvent>[];
  @override
  void handle(AgentPresenceEvent event) => events.add(event);
}

void main() {
  test('dispatcher-backed sink delivers to a registered handler', () async {
    final d = AsyncDispatcher()..start();
    final sink = DispatcherAgentPresenceSink(d);
    final rec = _Recorder();
    d.registerFamily<AgentPresenceKind>(
      AgentPresenceKind.working.runtimeType,
      rec,
    );

    sink.publish(AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'm'),
      eventKind: AgentPresenceKind.working,
      timestamp: DateTime(2026, 9, 11),
    ));
    await d.stop();

    expect(rec.events.single.memberId, 'm');
  });

  test('noop sink accepts publishes without side effects', () {
    const sink = NoopAgentPresenceSink();
    sink.publish(AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'm'),
      eventKind: AgentPresenceKind.idle,
      timestamp: DateTime(2026, 9, 11),
    ));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_sink_test.dart`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现**

```dart
// client/lib/services/event/agent_presence_sink.dart
import 'agent_presence_event.dart';
import 'dispatcher.dart';

/// Narrow publish seam for presence events.
///
/// Domain layers (services/team, services/terminal) depend on THIS, never on
/// the dispatcher itself — keeps the heuristic/state-machine layers free of
/// event-layer imports.
abstract interface class AgentPresenceSink {
  void publish(AgentPresenceEvent event);
}

/// Publishes onto the central dispatcher.
final class DispatcherAgentPresenceSink implements AgentPresenceSink {
  const DispatcherAgentPresenceSink(this._dispatcher);

  final Dispatcher _dispatcher;

  @override
  void publish(AgentPresenceEvent event) => _dispatcher.dispatch(event);
}

/// Used when no dispatcher is wired (tests, early startup).
final class NoopAgentPresenceSink implements AgentPresenceSink {
  const NoopAgentPresenceSink();

  @override
  void publish(AgentPresenceEvent event) {}
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_sink_test.dart`
Expected: PASS（2 个测试）

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/agent_presence_sink.dart client/test/services/event/agent_presence_sink_test.dart
git commit -m "feat(event): agent presence sink + dispatcher-backed impl"
```

---

### Task 3: tracker boot 推送（回调 + 一次性定时器 + reset 取消）

**Files:**
- Modify: `client/lib/services/team/terminal_activity_tracker.dart`
- Test: `client/test/services/team/terminal_activity_tracker_presence_push_test.dart`（新文件；**不动现有测试**）

**Interfaces:**
- Consumes: 无（纯 Dart）。
- Produces：`TerminalActivityTracker` 构造新增可选 `void Function(bool bootReady)? onBootFrameChanged`；新增 `void disposePresencePush()`（cancel 定时器；供绑定层解绑时调用）。**现有 getter 与内部状态行为完全不变。**

**实现要点**：
- `isBootFrameReady` 的**判定逻辑零改动**；新增 `bool? _lastReportedBootReady`，在 `_publishBootIfChanged()` 中读取 `isBootFrameReady` 并与 `_lastReportedBootReady` 比较，**变化才回调**。
- `_publishBootIfChanged()` 调用点：`notePtyBytes` 末尾（既有单遍扫描之后，零额外扫描）；一次性定时器到期时。
- 新增 `Timer? _bootTimer` + `_scheduleBootTimer()`：当 `onBootFrameChanged != null`、尚未 latch、且已见到首个可见内容（`_bootVisibleContentSeen` 且 `_bootFirstVisibleAt != null`）时，按「到 `bootMaxWait` 或 `bootQuietAfter` 静默」先到者排期；`notePtyBytes` 每次重排（`cancel` + 重设）。到期调用 `_publishBootIfChanged()`；若仍未 ready 则继续按 `bootMaxWait` 剩余时间排期（有上限，不得无限自续）。
- `reset()`：`_bootTimer?.cancel(); _bootTimer = null; _lastReportedBootReady = null;`（并保留既有状态清理）。
- **无回调时**（`onBootFrameChanged == null`）不排定时器——零开销，行为与今天完全一致。

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/team/terminal_activity_tracker_presence_push_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';

/// Minimal visible-content PTY payload (a few printable glyphs + CR/LF).
Uint8List _visible(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('does not fire when no callback is wired', () async {
    final t = TerminalActivityTracker(bootQuietAfter: const Duration(milliseconds: 20));
    t.notePtyBytes(_visible('hello world'));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // No callback wired → nothing to assert beyond "no crash", but the boot
    // getter must still behave exactly as before.
    expect(t.isBootFrameReady, isTrue);
  });

  test('fires exactly once when the boot frame becomes ready', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 200),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('ready prompt'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(seen, [true], reason: 'deduped: only the false→true flip is reported');
  });

  test('bootMaxWait path fires without a quiet window', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(seconds: 30), // never quiet in time
      bootMaxWait: const Duration(milliseconds: 60),
      onBootFrameChanged: seen.add,
    );
    // Keep repainting so the quiet window never elapses.
    for (var i = 0; i < 6; i++) {
      t.notePtyBytes(_visible('repaint $i'));
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    expect(seen, [true]);
  });

  test('reset cancels the pending timer and clears the reported value', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 80),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.reset();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, isEmpty, reason: 'reset must cancel the one-shot push');
  });

  test('disposePresencePush stops further pushes', () async {
    final seen = <bool>[];
    final t = TerminalActivityTracker(
      bootQuietAfter: const Duration(milliseconds: 20),
      bootMaxWait: const Duration(milliseconds: 60),
      onBootFrameChanged: seen.add,
    );
    t.notePtyBytes(_visible('booting'));
    t.disposePresencePush();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/team/terminal_activity_tracker_presence_push_test.dart`
Expected: FAIL — 构造无 `onBootFrameChanged` 参数。

- [ ] **Step 3: 实现**

在 `terminal_activity_tracker.dart` 中（**只加不改**既有逻辑）：
- 构造加 `this.onBootFrameChanged`（`final void Function(bool bootReady)? onBootFrameChanged;`）与 `void disposePresencePush()`。
- 私有状态：`Timer? _bootTimer;`、`bool? _lastReportedBootReady;`、`bool _presencePushDisposed = false;`。
- `_publishBootIfChanged()`：`if (onBootFrameChanged == null || _presencePushDisposed) return; final ready = isBootFrameReady; if (ready == _lastReportedBootReady) return; _lastReportedBootReady = ready; onBootFrameChanged!(ready);`
- `_scheduleBootTimer()`：`if (onBootFrameChanged == null || _presencePushDisposed) return; final ready = isBootFrameReady; if (ready) return; if (!_bootVisibleContentSeen || _bootFirstVisibleAt == null) return;` 计算「静默到期」与「bootMaxWait 到期」中较早者，`_bootTimer?.cancel()` 后 `= Timer(delay, () { _bootTimer = null; _publishBootIfChanged(); _scheduleBootTimer(); });`（重排有 `bootMaxWait` 兜底，不会无限自续——latch 后 `isBootFrameReady` 为 true 即停止重排）。
- `notePtyBytes` 末尾追加：`_publishBootIfChanged(); _scheduleBootTimer();`
- `reset()` 追加：`_bootTimer?.cancel(); _bootTimer = null; _lastReportedBootReady = null;`
- `disposePresencePush()`：`_presencePushDisposed = true; _bootTimer?.cancel(); _bootTimer = null;`

**注意**：`isBootFrameReady` 内部有 `_bootFrameLatched` 立即返回 true 的短路；不改动。

- [ ] **Step 4: 跑新测试 + 既有 tracker 测试**

Run: `cd client && dart run tool/run_tests.dart test/services/team/`
Expected: 新测试 5 个全绿；**既有 tracker/presence 测试原样通过**（行为等价证据）。

- [ ] **Step 5: analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 触碰文件零新增问题。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team/terminal_activity_tracker.dart client/test/services/team/terminal_activity_tracker_presence_push_test.dart
git commit -m "feat(presence): push boot-frame transitions from the activity tracker"
```

---

### Task 4: 投影 `AgentPresenceProjection`

**Files:**
- Create: `client/lib/services/event/agent_presence_projection.dart`
- Test: `client/test/services/event/agent_presence_projection_test.dart`

**Interfaces:**
- Consumes: Task 1 `AgentPresenceEvent`/`PresenceSeatKey`/`AgentPresenceKind`；期 1 `EventHandler`。
- Produces:
  - `final class AgentPresenceProjection implements EventHandler<AgentPresenceEvent>`
  - `AgentPresenceKind? availabilityFor(PresenceSeatKey seat)`
  - `Map<PresenceSeatKey, AgentPresenceKind> get snapshot`（不可变视图）
  - `Stream<PresenceSeatKey> get changes`（广播）
  - `void removeSeat(PresenceSeatKey seat)`（幂等；清理条目不广播）
  - `Future<void> close()`（关闭 controller）

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/event/agent_presence_projection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';

AgentPresenceEvent _e(String session, String member, AgentPresenceKind k) =>
    AgentPresenceEvent(
      seat: PresenceSeatKey(sessionId: session, memberId: member),
      eventKind: k,
      timestamp: DateTime(2026, 9, 11),
    );

void main() {
  test('reduces the latest availability per seat, isolating seats', () async {
    final p = AgentPresenceProjection();
    p.handle(_e('s1', 'a', AgentPresenceKind.booting));
    p.handle(_e('s1', 'b', AgentPresenceKind.working));
    p.handle(_e('s1', 'a', AgentPresenceKind.idle));

    expect(p.availabilityFor(const PresenceSeatKey(sessionId: 's1', memberId: 'a')),
        AgentPresenceKind.idle);
    expect(p.availabilityFor(const PresenceSeatKey(sessionId: 's1', memberId: 'b')),
        AgentPresenceKind.working);
    expect(p.availabilityFor(const PresenceSeatKey(sessionId: 's2', memberId: 'a')),
        isNull);
    await p.close();
  });

  test('repeated identical events are idempotent and do not re-broadcast', () async {
    final p = AgentPresenceProjection();
    final seen = <PresenceSeatKey>[];
    final sub = p.changes.listen(seen.add);

    p.handle(_e('s', 'm', AgentPresenceKind.working));
    p.handle(_e('s', 'm', AgentPresenceKind.working));
    await Future<void>.delayed(Duration.zero);

    expect(seen.length, 1, reason: 'unchanged value must not re-notify');
    await sub.cancel();
    await p.close();
  });

  test('removeSeat clears the entry', () async {
    final p = AgentPresenceProjection();
    const seat = PresenceSeatKey(sessionId: 's', memberId: 'm');
    p.handle(_e('s', 'm', AgentPresenceKind.working));
    p.removeSeat(seat);
    expect(p.availabilityFor(seat), isNull);
    p.removeSeat(seat); // idempotent
    await p.close();
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_projection_test.dart`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现**

```dart
// client/lib/services/event/agent_presence_projection.dart
import 'dart:async';

import 'agent_presence_event.dart';
import 'dispatcher.dart';

/// Reduces [AgentPresenceEvent]s into the latest availability per seat.
///
/// Registered on the central dispatcher by app_shell. Consumers (the presence
/// cubit today, mobile sync in phase 3) read [availabilityFor] / [snapshot] and
/// listen to [changes] for re-render notifications.
final class AgentPresenceProjection implements EventHandler<AgentPresenceEvent> {
  final Map<PresenceSeatKey, AgentPresenceKind> _bySeat = {};
  final StreamController<PresenceSeatKey> _changes =
      StreamController<PresenceSeatKey>.broadcast();

  Map<PresenceSeatKey, AgentPresenceKind> get snapshot =>
      Map.unmodifiable(_bySeat);

  Stream<PresenceSeatKey> get changes => _changes.stream;

  AgentPresenceKind? availabilityFor(PresenceSeatKey seat) => _bySeat[seat];

  @override
  void handle(AgentPresenceEvent event) {
    final previous = _bySeat[event.seat];
    if (previous == event.eventKind) return; // idempotent
    _bySeat[event.seat] = event.eventKind;
    if (!_changes.isClosed) _changes.add(event.seat);
  }

  void removeSeat(PresenceSeatKey seat) {
    _bySeat.remove(seat);
  }

  Future<void> close() => _changes.close();
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_projection_test.dart`
Expected: PASS（3 个测试）

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/agent_presence_projection.dart client/test/services/event/agent_presence_projection_test.dart
git commit -m "feat(event): agent presence projection over the dispatcher"
```

---

### Task 5: 去重发布边 `PresenceEventBridge`

**Files:**
- Create: `client/lib/services/event/presence_event_bridge.dart`
- Test: `client/test/services/event/presence_event_bridge_test.dart`

**Interfaces:**
- Consumes: Task 1/2 的类型与 sink。
- Produces:
  - `final class PresenceEventBridge`，构造 `PresenceEventBridge({required AgentPresenceSink sink, DateTime Function()? clock})`
  - `void reportAvailability(PresenceSeatKey seat, AgentPresenceKind? availability)` —— `null` 表示该 seat 当前无 availability（未连接）；此时若之前发过值，则**不发**事件但清内部基线（避免重连后误判为"变化"而重复发）——见下"语义"。
  - `void forget(PresenceSeatKey seat)` —— 解绑/会话关闭时清基线
  - `void dispose()`

**语义（写进 doc comment）**：
- 与上次**上报值**比较，值变化才 `sink.publish`。`_last` 为空的首次上报视为变化（首次也要发，投影需要初始值）。
- 传 `null`（断开）：清 `_last[seat]` 但**不发布**"离线"事件——connection 维度不属于本事件族（本期）。

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/event/presence_event_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_sink.dart';
import 'package:teampilot/services/event/presence_event_bridge.dart';

class _SpySink implements AgentPresenceSink {
  final events = <AgentPresenceEvent>[];
  @override
  void publish(AgentPresenceEvent event) => events.add(event);
}

void main() {
  const seat = PresenceSeatKey(sessionId: 's', memberId: 'm');

  test('publishes on first report and on every change, deduping repeats', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink, clock: () => DateTime(2026, 9, 11));

    bridge.reportAvailability(seat, AgentPresenceKind.booting);
    bridge.reportAvailability(seat, AgentPresenceKind.booting); // repeat
    bridge.reportAvailability(seat, AgentPresenceKind.working);
    bridge.reportAvailability(seat, AgentPresenceKind.idle);

    expect(sink.events.map((e) => e.eventKind), [
      AgentPresenceKind.booting,
      AgentPresenceKind.working,
      AgentPresenceKind.idle,
    ]);
    expect(sink.events.first.seat, seat);
  });

  test('null report clears the baseline without publishing', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.reportAvailability(seat, AgentPresenceKind.working);
    bridge.reportAvailability(seat, null); // disconnected
    expect(sink.events.length, 1);

    // Reconnecting at the same value publishes again (fresh baseline).
    bridge.reportAvailability(seat, AgentPresenceKind.working);
    expect(sink.events.length, 2);
  });

  test('forget clears baseline', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.reportAvailability(seat, AgentPresenceKind.idle);
    bridge.forget(seat);
    bridge.reportAvailability(seat, AgentPresenceKind.idle);
    expect(sink.events.length, 2);
  });

  test('dispose stops publishing', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.dispose();
    bridge.reportAvailability(seat, AgentPresenceKind.idle);
    expect(sink.events, isEmpty);
  });

  test('seats are isolated', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(sink: sink);
    bridge.reportAvailability(const PresenceSeatKey(sessionId: 's', memberId: 'a'),
        AgentPresenceKind.working);
    bridge.reportAvailability(const PresenceSeatKey(sessionId: 's', memberId: 'b'),
        AgentPresenceKind.working);
    expect(sink.events.length, 2);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/presence_event_bridge_test.dart`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现**

要点：`Map<PresenceSeatKey, AgentPresenceKind> _last`；`_disposed` 标志；`reportAvailability` 中 `if (_disposed) return;` → `availability == null ? _last.remove(seat) : (if (_last[seat] == availability) return; _last[seat] = availability; sink.publish(AgentPresenceEvent(seat: seat, eventKind: availability, timestamp: _clock())));`

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/presence_event_bridge_test.dart`
Expected: PASS（5 个测试）

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/presence_event_bridge.dart client/test/services/event/presence_event_bridge_test.dart
git commit -m "feat(event): deduping presence publish bridge"
```

---

### Task 6: 会话侧推送触发（回合锁存 + boot 翻转）

**Files:**
- Modify: `client/lib/services/terminal/terminal_session.dart`（`_bindObservation`/`_unbindObservation`、`markUserTurnStarted`/`markUserTurnIdle`）
- Test: `client/test/services/terminal/terminal_session_presence_trigger_test.dart`（新文件；不动现有测试）

**Interfaces:**
- Consumes: Task 3 的 `onBootFrameChanged` / `disposePresencePush()`。
- Produces：`TerminalSession` 新增可选 `void Function()? onPresenceInputsChanged`（构造参数）与 `PresenceSeatKey? get presenceSeat`（绑定后非空，未绑定/未携带身份时为 null）。

**实现要点**：
- 构造加 `this.onPresenceInputsChanged`（`final void Function()? onPresenceInputsChanged;`）。
- 在**既有** `TerminalActivityTracker` 构造处（`terminal_session.dart:87-88`，`launchController?.activityTracker ?? TerminalActivityTracker()`）传入 `onBootFrameChanged: (_) => onPresenceInputsChanged?.call()`。注意：这条 tracker 可能是外部注入的（`launchController?.activityTracker`）——若注入的 tracker 已带自己的回调，**不要覆盖**；仅在自建 tracker 时传入（实现时按此判断，并在报告里说明所选分支）。
- `_bindObservation` 末尾：`presenceSeat` 由 `seat.sessionId`/`seat.memberId` 构造；**两者任一为空则不设置**（未绑定 seat 不发事件）。
- `_unbindObservation` 中：`activityTracker.disposePresencePush()`（仅当 tracker 为本 session 自建时）+ 清 `presenceSeat`。
- `markUserTurnStarted()` / `markUserTurnIdle()` 中各自追加 `onPresenceInputsChanged?.call()`（**在既有语句之后**，不改既有行为）。

- [ ] **Step 1: 写失败测试**（用构造注入的 fake tracker / 直接调用 latch，断言回调次数）

```dart
// client/test/services/terminal/terminal_session_presence_trigger_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/in_memory_filesystem.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  test('turn latch transitions request a presence refresh', () {
    var calls = 0;
    final s = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      fs: InMemoryFilesystem(),
      onPresenceInputsChanged: () => calls++,
    );
    addTearDown(s.dispose);
    s.markUserTurnStarted();
    s.markUserTurnIdle();
    expect(calls, 2);
  });

  test('presenceSeat is null until an observation binds an identity', () {
    final s = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      fs: InMemoryFilesystem(),
    );
    addTearDown(s.dispose);
    expect(s.presenceSeat, isNull);
  });
}
```

（构造形态照抄仓库既有测试 `test/services/terminal/member_pty_inject_abort_test.dart:34`；`InMemoryFilesystem` 的 import 路径以该文件为准。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/terminal_session_presence_trigger_test.dart`
Expected: FAIL — 构造无 `onPresenceInputsChanged`、无 `presenceSeat`。

- [ ] **Step 3: 实现**（按上面要点）

- [ ] **Step 4: 跑新测试 + 既有 terminal 测试**

Run: `cd client && dart run tool/run_tests.dart test/services/terminal/`
Expected: 新测试绿；既有 terminal 测试原样通过。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/terminal_session.dart client/test/services/terminal/terminal_session_presence_trigger_test.dart
git commit -m "feat(presence): session-side push triggers for turn latch and boot frame"
```

---

### Task 7: cubit 消费迁移（读投影 + 触发重算 + 发布）

**Files:**
- Modify: `client/lib/cubits/member_presence_cubit.dart`
- Modify: `client/lib/services/team/member_presence_service.dart`（仅在需要时：让 compute 的 availability 读投影，见下）
- Test: `client/test/cubits/member_presence_cubit_events_test.dart`（新文件；**不动现有 cubit 测试**）

**Interfaces:**
- Consumes: Task 2 `AgentPresenceSink`、Task 4 `AgentPresenceProjection`、Task 5 `PresenceEventBridge`、Task 6 `presenceSeat`/`onPresenceInputsChanged`。
- Produces：`MemberPresenceCubit` 构造新增可选 `{AgentPresenceProjection? presenceProjection, PresenceEventBridge? presenceBridge}`（都默认 null → 行为与今天完全一致，方便既有测试不改）。

**实现要点**：
- `_tickMemberPresence` 中：`connection` 仍由 `_connectionOf(shell)` 现算；`availability` 改为 **`presenceProjection?.availabilityFor(seat)` ?? 现有 compute 结果**（投影未接线时走老路径 = 行为等价；接线后以投影为准）。
  - 说明：为让投影成为唯一事实来源，接线后 compute 的 availability 结果被覆盖；`MemberPresenceService.compute()` 本身**不改签名**。
- 每个 tick 后：对每个 seat `presenceBridge?.reportAvailability(seat, availability)`（投影模式下即投影值；非投影模式即 compute 值），断开（connection != connected）时 `reportAvailability(seat, null)`。
- 给每个 `target.memberShells` 的 session 挂 `onPresenceInputsChanged`：指向一个**去抖的即时重算**（复用既有 `tickFromIdleWatch()`；用 `_presenceTickInFlight` 已有的在途保护避免风暴）。
- 订阅 `presenceProjection.changes`：收到即 `unawaited(tickFromIdleWatch())`，让 UI 刷新延迟不劣于今天。
- 生命周期：`close()` 时 cancel 订阅、`presenceBridge?.dispose()`、对每个 seat `projection.removeSeat(seat)`。

- [ ] **Step 1: 写失败测试**

```dart
// client/test/cubits/member_presence_cubit_events_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_projection.dart';

import '../support/post_frame_test_harness.dart'; // fakeHomeStorage()
import '../support/in_memory_filesystem.dart';

void main() {
  test('projection changes request a presence refresh', () async {
    final projection = AgentPresenceProjection();
    var refreshes = 0;
    final cubit = MemberPresenceCubit(
      storage: fakeHomeStorage(),
      presenceProjection: projection,
      onProjectionChanged: () => refreshes++, // injectable spy (见"可观测点")
    );
    addTearDown(cubit.close);

    projection.handle(AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'm'),
      eventKind: AgentPresenceKind.working,
      timestamp: DateTime(2026, 9, 11),
    ));
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
  });
}
```

**可观测点（已定案）**：cubit 构造新增可选 `void Function()? onProjectionChanged`，收到投影变更时调用后**再**请求重算。测试注入 spy 即可，无需 `@visibleForTesting` 钩子污染生产代码。（构造辅助 `fakeHomeStorage()` 与 import 路径照抄既有 `test/cubits/member_presence_cubit_test.dart:25-26`。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/member_presence_cubit_events_test.dart`
Expected: FAIL — 构造无 `presenceProjection`。

- [ ] **Step 3: 实现**（按上面要点；注意 `_emitMemberPresence` 的 post-frame 语义保持不变）

- [ ] **Step 4: 跑新测试 + 既有 cubit/presence 测试**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ test/services/team/`
Expected: 新测试绿；既有测试原样通过（**行为等价证据**）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/member_presence_cubit.dart client/test/cubits/member_presence_cubit_events_test.dart
git commit -m "refactor(presence): read availability from the event projection"
```

---

### Task 8: app_shell 接线

**Files:**
- Modify: `client/lib/app/app_shell.dart`

**实现要点**：
- 在期 1 已有 `AsyncDispatcher` 创建处旁（`EventPublisher.instance.attach(d)` 附近）：`final presenceProjection = AgentPresenceProjection();` → `d.registerFamily<AgentPresenceKind>(AgentPresenceKind.working.runtimeType, presenceProjection);`（**注意**：族按 `kind.runtimeType` 路由，`AgentPresenceKind` 的每个成员 `runtimeType` 都是 `AgentPresenceKind`，因此注册一次即可覆盖三个值——实现时确认 `registerFamily` 的路由键语义并写测试验证三个 kind 都能到达投影）。
- 构造 `DispatcherAgentPresenceSink(d)` 与 `PresenceEventBridge(sink: ...)`，注入到 `MemberPresenceCubit` 的创建处（找到现有 `MemberPresenceCubit(...)` 构造点）。
- shell dispose 路径：`await presenceProjection.close()`。

- [ ] **Step 1: 实现接线**（无独立测试文件：接线正确性由 Task 7 的 cubit 测试 + 全套回归覆盖；若 app_shell 现有 bootstrap/dispose 测试可扩展则一并断言）

- [ ] **Step 2: analyze + 相关测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/app/ test/cubits/`
Expected: 全绿。

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(presence): wire presence events through the app-shell dispatcher"
```

---

### Task 9: 收尾——文档 + 全套验证

**Files:**
- Modify: `client/lib/services/event/README.md`（追加 AgentPresence 族条目：kind 三值、来源两处触发 + 去重边、投影消费方式）
- Modify: `docs/superpowers/specs/2026-09-11-agent-presence-events-design.md`（追加"实施记录"小节：记录本计划对 spec 的两处细化——`markUserTurnStarted` 实名、组合改由 bridge 触发既有求值路径）

- [ ] **Step 1: 写文档**

- [ ] **Step 2: 全套测试（唯一一次，后台）**

Run: `cd client && dart run tool/run_tests.dart`
Expected: 全绿。任何失败先修再提交；确认与 main 基线对比无新增失败（main 基线：`4cf2791ba` 上全套通过）。

- [ ] **Step 3: Commit + 汇报**

```bash
git add client/lib/services/event/README.md docs/superpowers/specs/2026-09-11-agent-presence-events-design.md
git commit -m "docs(presence): README entry + spec implementation notes"
```

汇报：worktree 路径、提交清单、全套结果、验收达成情况（analyze 干净 + 全套绿 + 既有 presence/coordination 测试未修改通过）。
