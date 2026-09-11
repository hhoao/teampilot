# 中央事件发布层（YARN 风格 AsyncDispatcher）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `client/lib/services/event/` 实现仿 YARN `org.apache.hadoop.yarn.event` 的中央 AsyncDispatcher，迁移 `CatalogMutationBus` 与 `WorkspaceFsWatcher` 为首批事件源，并新增 Session 生命周期事件族。

**Architecture:** 单一中央 `AsyncDispatcher`（无界队列 + 单 Future 消费循环 + 按事件族路由 + 多播 + 错误隔离），从 `app_shell.dart` 构造注入。事件词汇表分域：每族自带 sealed class + kind 枚举，dispatcher 只认 `DispatcherEvent<K>` 接口。设计 spec：`docs/superpowers/specs/2026-09-10-central-event-dispatcher-design.md`。

**Tech Stack:** Dart 3 / Flutter（纯 Dart 代码，无新依赖）；测试用 `flutter_test`。

## Global Constraints

- **绝不直接运行 `flutter test`**——一律 `cd client && dart run tool/run_tests.dart <paths>`（共享 build cache 会被并发直跑损坏）。
- 内层循环 = `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件验证 = `dart run tool/run_tests.dart test/<path> --plain-name <name>`；全套 = `dart run tool/run_tests.dart`（只在收尾跑一次，后台）。
- 文件大小软限：`services/` ~600 行。
- 日志一律 `AppLogger`（`package:teampilot/utils/logging/logger.dart` 的 `appLogger`），禁止 `print`。
- 迁移类（`CatalogMutationBus`、`WorkspaceFsWatcher`）**对外 API 保持不变**，现有测试原样必须通过——这是"行为等价"的验收证据。
- 本期不触碰 `client/lib/services/agent_runtime/` 的任何文件。
- 在新 worktree（`superpowers:using-git-worktrees` 创建，建议名 `feat-event-dispatcher`）中实施，基于 `origin/main`。
- 用户错误文案 → l10n（本计划无用户可见文案，全走 AppLogger，不涉及）。

---

### Task 1: `DispatcherEvent` / `EventHandler` / `Dispatcher` 接口

**Files:**
- Create: `client/lib/services/event/dispatcher.dart`
- Test: `client/test/services/event/dispatcher_test.dart`

**Interfaces:**
- Consumes: 无（首任务）。
- Produces（后续所有任务依赖）:
  - `abstract interface class DispatcherEvent<K extends Enum<K>> { K get kind; DateTime get timestamp; }`
  - `abstract interface class EventHandler<T extends DispatcherEvent> { void handle(T event); }`
  - `abstract interface class Dispatcher { void dispatch(DispatcherEvent event); void register<K extends Enum<K>>(EventHandler handler); void unregister(EventHandler handler); }`

注意：`register` 泛型按 YARN 是"按事件族（kind 枚举类型）注册"。Dart 无运行时 `Class<Enum>` reify，实现上由**事件族注册辅助**完成（见 Task 2 的 `FamilyKey`），接口层 `register` 的 `K` 约束即族标识。

- [ ] **Step 1: 写失败测试**（先只测接口可被实现与使用——具体行为在 Task 2；这里锁死签名）

```dart
// client/test/services/event/dispatcher_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/dispatcher.dart';

enum _TestKind { a, b }

class _TestEvent implements DispatcherEvent<_TestKind> {
  const _TestEvent(this.kind, this.timestamp);
  @override
  final _TestKind kind;
  @override
  final DateTime timestamp;
}

class _RecordingHandler implements EventHandler<_TestEvent> {
  final events = <_TestEvent>[];
  @override
  void handle(_TestEvent event) => events.add(event);
}

class _StubDispatcher implements Dispatcher {
  final dispatched = <DispatcherEvent>[];
  final registered = <EventHandler>[];
  @override
  void dispatch(DispatcherEvent event) => dispatched.add(event);
  @override
  void register<K extends Enum<K>>(EventHandler handler) =>
      registered.add(handler);
  @override
  void unregister(EventHandler handler) {}
}

void main() {
  test('interfaces compile and are implementable', () {
    final d = _StubDispatcher();
    const e = _TestEvent(_TestKind.a, null);
    // ignore: unnecessary_type_check
    expect(e is DispatcherEvent<_TestKind>, isTrue);
  });
}
```

注意：`_TestEvent` 构造里 `timestamp` 用 `DateTime.now()` 由调用处传入（事件自带时间戳，YARN `AbstractEvent` 同义）；上面 `null` 占位改成测试里 `DateTime(2026)`。写计划时以能编译为准，实现者可微调测试代码但**不得改接口签名**。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/dispatcher_test.dart`
Expected: FAIL — `dispatcher.dart` 不存在，import 报错。

- [ ] **Step 3: 最小实现**

```dart
// client/lib/services/event/dispatcher.dart
/// YARN-style central event dispatch interfaces.
///
/// Port of org.apache.hadoop.yarn.event {Event, EventHandler, Dispatcher}.
/// Vocabulary is per-family: each event family defines its own sealed class
/// + kind enum (like YARN's per-domain *EventType enums); the dispatcher is
/// generic over families and knows no concrete vocabulary.
library;

/// An event flowing through a [Dispatcher]. `K` is the family's kind enum.
abstract interface class DispatcherEvent<K extends Enum<K>> {
  K get kind;
  DateTime get timestamp;
}

/// A consumer registered for an event family (YARN EventHandler).
abstract interface class EventHandler<T extends DispatcherEvent> {
  void handle(T event);
}

/// The central dispatcher (YARN Dispatcher). Publishing via [dispatch] is
/// fire-and-forget; consumers register per family.
abstract interface class Dispatcher {
  /// Enqueue [event]; returns immediately, never blocks (YARN
  /// getEventHandler().handle()).
  void dispatch(DispatcherEvent event);

  /// Register [handler] for the family identified by `K`. If a handler is
  /// already registered for `K`, both are invoked (YARN MultiListenerHandler).
  void register<K extends Enum<K>>(EventHandler handler);

  /// Remove [handler] from every family it was registered for.
  void unregister(EventHandler handler);
}
```

（`register<K>` 的运行时族识别：实现类从 `handler` 的 `EventHandler<T>` 形参 reify `T`，取 `T` 里 `DispatcherEvent<K>` 的 `K`。若 reify 困难，允许给 `EventHandler` 加一个 `Type get familyKind` getter——**由实现者在 Task 2 决定，二选一，写进实现并在 doc comment 说明**。）

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/dispatcher_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/dispatcher.dart client/test/services/event/dispatcher_test.dart
git commit -m "feat(event): YARN-style dispatcher interfaces"
```

---

### Task 2: `AsyncDispatcher` 实现（队列 + 消费循环 + 路由 + 多播 + 错误隔离 + drain + 可观测）

**Files:**
- Create: `client/lib/services/event/async_dispatcher.dart`
- Test: `client/test/services/event/async_dispatcher_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `DispatcherEvent` / `EventHandler` / `Dispatcher`。
- Produces: `class AsyncDispatcher implements Dispatcher`，构造 `AsyncDispatcher({void Function()? onWarn})`；另有 `Future<void> start()`、`Future<void> stop()`（drain 后关闭）、`int get queued`、`Map<String, int> get handledCounts`（key = 族枚举名，用于测试与可观测）。

- [ ] **Step 1: 写失败测试**（覆盖 spec 列出的全部行为）

```dart
// client/test/services/event/async_dispatcher_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';

enum _FamKind { ping, pong }

class _FamEvent implements DispatcherEvent<_FamKind> {
  const _FamEvent(this.kind, this.timestamp, [this.tag = '']);
  @override
  final _FamKind kind;
  @override
  final DateTime timestamp;
  final String tag;
}

class _Recorder implements EventHandler<_FamEvent> {
  final tags = <String>[];
  @override
  void handle(_FamEvent event) => tags.add(event.tag);
}

class _ThrowingHandler implements EventHandler<_FamEvent> {
  @override
  void handle(_FamEvent event) => throw StateError('boom');
}

void main() {
  test('dispatch returns before handlers run; order preserved globally', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.register<_FamKind>(r);
    d.dispatch(const _FamEvent(_FamKind.ping, null, 'a'));
    expect(r.tags, isEmpty); // enqueue-only, not yet consumed
    d.dispatch(const _FamEvent(_FamKind.pong, null, 'b'));
    await d.stop(); // drains
    expect(r.tags, ['a', 'b']);
  });

  test('routes by family; unregistered families dropped silently', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.register<_FamKind>(r);
    // 未注册族:直接丢弃并计数(YARN: 无 handler 时仅 log)
    await d.stop();
    expect(r.tags, isEmpty);
  });

  test('multiple handlers for same family all invoked (multicast)', () async {
    final d = AsyncDispatcher()..start();
    final r1 = _Recorder(), r2 = _Recorder();
    d.register<_FamKind>(r1);
    d.register<_FamKind>(r2);
    d.dispatch(const _FamEvent(_FamKind.ping, null, 'x'));
    await d.stop();
    expect(r1.tags, ['x']);
    expect(r2.tags, ['x']);
  });

  test('unregister stops delivery', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.register<_FamKind>(r);
    d.unregister(r);
    d.dispatch(const _FamEvent(_FamKind.ping, null, 'x'));
    await d.stop();
    expect(r.tags, isEmpty);
  });

  test('handler exception is isolated; subsequent events still processed', () async {
    final d = AsyncDispatcher()..start();
    final good = _Recorder();
    d.register<_FamKind>(_ThrowingHandler());
    d.register<_FamKind>(good);
    d.dispatch(const _FamEvent(_FamKind.ping, null, '1'));
    d.dispatch(const _FamEvent(_FamKind.ping, null, '2'));
    await d.stop();
    // 抛错 handler 不阻断同事件的其他 handler,也不阻断后续事件
    expect(good.tags, ['1', '2']);
  });

  test('stop drains queued events before closing', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.register<_FamKind>(r);
    for (var i = 0; i < 50; i++) {
      d.dispatch(_FamEvent(_FamKind.ping, DateTime(2026), '$i'));
    }
    await d.stop();
    expect(r.tags.length, 50);
    expect(d.queued, 0);
  });

  test('handled counts exposed per family kind', () async {
    final d = AsyncDispatcher()..start();
    final r = _Recorder();
    d.register<_FamKind>(r);
    d.dispatch(const _FamEvent(_FamKind.ping, null, 'a'));
    d.dispatch(const _FamEvent(_FamKind.pong, null, 'b'));
    await d.stop();
    expect(d.handledCounts['_FamKind.ping'], 1);
    expect(d.handledCounts['_FamKind.pong'], 1);
  });
}
```

（同 Task 1：`null` timestamp 占位在实现时改为真实 `DateTime(2026)` 之类；测试意图不变。）

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/async_dispatcher_test.dart`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现 AsyncDispatcher**

实现要点（YARN `AsyncDispatcher` 逐条对应，doc comment 里标注）：

```dart
// client/lib/services/event/async_dispatcher.dart
import 'dart:collection';

import '../../utils/logging/logger.dart';
import 'dispatcher.dart';

/// YARN AsyncDispatcher port: unbounded queue + single consume loop +
/// per-family routing with auto-multicast.
///
/// Deviations from YARN (deliberate, see design spec):
/// - handler exceptions are logged and skipped (YARN exits the process);
/// - unbounded queue with a depth warning at [_warnDepth] (YARN uses a
///   bounded LinkedBlockingQueue for multi-threaded producers).
class AsyncDispatcher implements Dispatcher {
  AsyncDispatcher({int warnDepth = 1000})
    : _warnDepth = warnDepth;

  static const _tag = 'event-dispatcher';
  final int _warnDepth;
  final Queue<DispatcherEvent> _queue = Queue();
  final Map<Type, List<EventHandler>> _handlers = {}; // key: kind enum Type
  final Map<String, int> _handledCounts = {};
  bool _running = false;
  bool _draining = false;
  Future<void> _loop = Future.value();

  int get queued => _queue.length;
  Map<String, int> get handledCounts => Map.unmodifiable(_handledCounts);

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _loop = _consume();
  }

  @override
  void dispatch(DispatcherEvent event) {
    if (!_running && _draining) return; // closed: drop
    _queue.add(event);
    if (_queue.length > _warnDepth) {
      appLogger.w('$_tag queue depth ${_queue.length} exceeds $_warnDepth');
    }
  }

  Future<void> _consume() async {
    while (_running || _queue.isNotEmpty) {
      if (_queue.isEmpty) {
        await Future<void>.delayed(Duration.zero);
        continue;
      }
      final event = _queue.removeFirst();
      _dispatchToListeners(event);
    }
  }

  void _dispatchToListeners(DispatcherEvent event) {
    final kindType = event.kind.runtimeType;
    final handlers = _handlers[kindType];
    if (handlers == null || handlers.isEmpty) {
      appLogger.d('$_tag no handler for $kindType');
      return;
    }
    for (final h in List.of(handlers)) {
      try {
        // ignore: avoid_dynamic_calls
        (h as dynamic).handle(event);
      } catch (e, s) {
        appLogger.e('$_tag handler error for $kindType', e, s);
      }
    }
    _bumpCount('${kindType.toString()}.${event.kind.name}');
  }

  void _bumpCount(String key) =>
      _handledCounts[key] = (_handledCounts[key] ?? 0) + 1;

  @override
  void register<K extends Enum<K>>(EventHandler handler) {
    // K 的运行时识别:在 register 的调用点我们拿不到 K 的 TypeTag,
    // 因此按 handler 的 EventHandler<T> 形参 reify T,再从 T 取族枚举。
    // 简化实现:注册时同时记录 K 的 Type —— 由调用方泛型直接传入。
    // (实现者:若 Dart reify 取 Type 困难,改用 registerFamily(Type, handler)
    //  便捷方法 + 保留 register<K> 为转发,见下方说明。)
    // ... 实现细节见 Step 3 说明
  }

  @override
  void unregister(EventHandler handler) {
    for (final list in _handlers.values) {
      list.remove(handler);
    }
  }

  Future<void> stop() async {
    _running = false;
    _draining = true;
    await _loop; // drain remaining
    _draining = false;
  }
}
```

**族识别的实现决策（Task 1 遗留，在这里定死）**：Dart 泛型不携带 `K` 的 `Type` 到运行时（`register<K>` 拿不到 `Type` 除非传参）。定案方案：`Dispatcher` 接口在 Task 1 的三个方法之外**增加**一个便捷方法：

```dart
void registerFamily<K extends Enum<K>>(Type kindType, EventHandler handler);
```

`register<K>` 不再单独存在——把 Task 1 接口里的 `register<K>` 替换为 `registerFamily<K extends Enum<K>>(Type kindType, EventHandler handler)`（`K` 仅为静态类型检查用，运行时族用 `kindType`）。**实现 Task 1 时就直接写这个签名**，避免事后改接口。本任务的测试里 `d.register<_FamKind>(r)` 相应改为 `d.registerFamily<_FamKind>(_FamKind.ping.runtimeType, r)`（或定义 `Type get _famType => _FamKind.ping.runtimeType`）。路由表 key 即 `event.kind.runtimeType`，与 `kindType` 匹配。

消费循环中 `await Future.delayed(Duration.zero)` 的空转仅用于测试环境让出；实现者可将 `_consume` 改为事件驱动（`completer`/`StreamController` 非广播 + 监听循环），**语义不变：单循环、全局有序、stop drain**。空转轮询若保留，须在 `stop()` 后终止（上面的 `while (_running || _queue.isNotEmpty)` 已保证）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/async_dispatcher_test.dart`
Expected: PASS（7 个测试全绿）

- [ ] **Step 5: analyze 内层循环**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增 error/warning。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/event/async_dispatcher.dart client/test/services/event/async_dispatcher_test.dart client/lib/services/event/dispatcher.dart client/test/services/event/dispatcher_test.dart
git commit -m "feat(event): AsyncDispatcher with queue, routing, multicast, error isolation"
```

---

### Task 3: Session 生命周期事件族 + 发布点

**Files:**
- Create: `client/lib/services/event/session_lifecycle_event.dart`
- Create: `client/lib/services/event/event_publisher.dart`（极薄的注入辅助：持有 `Dispatcher?`，`null` 时所有发布为 no-op——避免大面积构造函数改动）
- Modify: `client/lib/cubits/chat_cubit.dart:320`（`SessionLaunchService` 构造处旁，挂 publisher）
- Modify: `client/lib/services/launch/session_launch_pipeline.dart`（`_runCreate` 成功路径发布 `sessionSpawned`/`sessionStarted`）
- Modify: `client/lib/cubits/chat_cubit.dart:2616`（`deleteSession` 发布 `sessionClosed`）
- Test: `client/test/services/event/session_lifecycle_event_test.dart`

**Interfaces:**
- Consumes: Task 1/2 的 `Dispatcher` / `DispatcherEvent` / `EventHandler`。
- Produces:
  - `enum SessionLifecycleKind { sessionSpawned, sessionStarted, seatStarted, seatInterrupted, seatExited, sessionClosed }`
  - `sealed class SessionLifecycleEvent implements DispatcherEvent<SessionLifecycleKind>`，字段 `sessionId`、`workspaceId`、`memberId?`（seat 事件）、`kind`、`timestamp`
  - `EventPublisher`：`void attach(Dispatcher d)` / `void dispatchSessionLifecycle(SessionLifecycleEvent e)` / 静态 `EventPublisher instance`（仅注入桥，**不承载业务状态**；app 生命周期单例，构造注入通过 `app_shell.dart` 完成 `attach`）

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/event/session_lifecycle_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/event_publisher.dart';
import 'package:teampilot/services/event/session_lifecycle_event.dart';

void main() {
  test('EventPublisher dispatches lifecycle events through the dispatcher',
      () async {
    final d = AsyncDispatcher()..start();
    final publisher = EventPublisher()..attach(d);
    final received = <SessionLifecycleEvent>[];
    d.registerFamily<SessionLifecycleKind>(
      SessionLifecycleKind.sessionStarted.runtimeType,
      _Recorder(received),
    );

    publisher.dispatchSessionLifecycle(
      SessionLifecycleEvent.sessionStarted(
        sessionId: 's-1',
        workspaceId: 'w-1',
        timestamp: DateTime(2026),
      ),
    );
    await d.stop();

    expect(received.single.kind, SessionLifecycleKind.sessionStarted);
    expect(received.single.sessionId, 's-1');
  });

  test('unattached publisher is a no-op', () {
    final publisher = EventPublisher();
    // 不应抛异常
    publisher.dispatchSessionLifecycle(
      SessionLifecycleEvent.sessionClosed(
        sessionId: 's-2',
        workspaceId: 'w-1',
        timestamp: DateTime(2026),
      ),
    );
  });
}

class _Recorder implements EventHandler<SessionLifecycleEvent> {
  _Recorder(this.events);
  final List<SessionLifecycleEvent> events;
  @override
  void handle(SessionLifecycleEvent event) => events.add(event);
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/session_lifecycle_event_test.dart`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现事件族与 publisher**

```dart
// client/lib/services/event/session_lifecycle_event.dart
import 'dispatcher.dart';

enum SessionLifecycleKind {
  sessionSpawned,
  sessionStarted,
  seatStarted,
  seatInterrupted,
  seatExited,
  sessionClosed,
}

sealed class SessionLifecycleEvent implements DispatcherEvent<SessionLifecycleKind> {
  const SessionLifecycleEvent._({
    required this.kind,
    required this.sessionId,
    required this.workspaceId,
    required this.timestamp,
    this.memberId,
  });

  factory SessionLifecycleEvent.sessionSpawned({
    required String sessionId, required String workspaceId, required DateTime timestamp,
  }) => // ... 每个 kind 一个工厂,seat* 的带 memberId
  ...

  @override
  final SessionLifecycleKind kind;
  final String sessionId;
  final String workspaceId;
  final String? memberId;
  @override
  final DateTime timestamp;
}
```

（6 个工厂全部写出，pattern 参考 `runtime_event.dart` 的 `RuntimeEventEnvelopeDraft` 工厂风格。`seatStarted`/`seatInterrupted`/`seatExited` 的 `memberId` 必填；session 级事件无 memberId。）

```dart
// client/lib/services/event/event_publisher.dart
import 'dispatcher.dart';
import 'session_lifecycle_event.dart';

/// Injection seam for the central dispatcher. Attach happens once from
/// app_shell; before attach (tests, early startup) all publishes are no-ops.
class EventPublisher {
  EventPublisher._();
  static final EventPublisher instance = EventPublisher._();

  Dispatcher? _dispatcher;
  void attach(Dispatcher d) => _dispatcher = d;

  void dispatchSessionLifecycle(SessionLifecycleEvent event) =>
      _dispatcher?.dispatch(event);
}
```

**发布点接线**（行为新增，但不影响现有流程——纯旁路）：
- `session_launch_pipeline.dart` `_runCreate`：session 对象成功创建后（`sessionId` 确定处）`EventPublisher.instance.dispatchSessionLifecycle(SessionLifecycleEvent.sessionSpawned(...))`；pipeline 返回成功 `LaunchOpened` 前 `sessionStarted`。
- `chat_cubit.dart` `deleteSession`：删除流程开头（拿到 `session` 后）`sessionClosed`。
- `seatStarted`/`seatInterrupted`/`seatExited` 本期**只定义词汇不接发布点**（Runtime 接入期再挂），doc comment 写明。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/session_lifecycle_event_test.dart`
Expected: PASS

- [ ] **Step 5: 挂 app_shell 注入**

Modify `client/lib/app/app_shell.dart`：app 启动装配处构造 `AsyncDispatcher()..start()`，`EventPublisher.instance.attach(d)`，并在 app 退路（shell dispose）`await d.stop()`。找到现有装配点（`app_shell.dart` 构造/state 初始化处），加 3-5 行。

- [ ] **Step 6: analyze + 相关既有测试不破**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/cubits/chat`
Expected: 全绿（发布点是纯旁路，不应影响任何现有断言）。

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/event/ client/test/services/event/ client/lib/app/app_shell.dart client/lib/cubits/chat_cubit.dart client/lib/services/launch/session_launch_pipeline.dart
git commit -m "feat(event): session lifecycle family + publisher wiring"
```

---

### Task 4: 迁移 `CatalogMutationBus`（行为等价）

**Files:**
- Modify: `client/lib/services/catalog/catalog_mutation_bus.dart`
- Modify: `client/lib/services/catalog/catalog_runtime.dart:66`（默认 bus 携带 dispatcher）
- Modify: `client/lib/app/app_shell.dart`（把中央 dispatcher 传给 CatalogRuntime 构造）
- Test: `client/test/services/catalog/catalog_mutation_bus_test.dart`（**现有测试不动，必须原样通过**）
- Test: `client/test/services/event/catalog_event_migration_test.dart`（新增对照测试）

**Interfaces:**
- Consumes: Task 1/2 `Dispatcher`、Task 3 `EventPublisher`（复用 attach 机制）。
- Produces: `CatalogMutationBus` 对外 API 不变（`listen()` / `emit()`）。内部：`CatalogMutationEvent` 额外实现 `DispatcherEvent<CatalogMutationKind>`；新增 `enum CatalogMutationKind { mutated }`（单成员，词汇照搬原事件）。

- [ ] **Step 1: 写对照测试**（证明迁移后行为等价 + 事件双通道）

```dart
// client/test/services/event/catalog_event_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';

void main() {
  test('emit reaches both legacy listen() and dispatcher handlers', () async {
    final d = AsyncDispatcher()..start();
    final bus = CatalogMutationBus(dispatcher: d);

    final legacy = <CatalogMutationEvent>[];
    bus.listen().listen(legacy.add);
    final viaDispatcher = <CatalogMutationEvent>[];
    d.registerFamily<CatalogMutationKind>(
      CatalogMutationKind.mutated.runtimeType,
      _Handler(viaDispatcher),
    );

    const e = CatalogMutationEvent(
      kind: 'skill', op: CatalogOp.create,
      ids: ['local:x'], workspaceId: 'w-1',
    );
    bus.emit(e);
    await d.stop();

    expect(legacy.single, same(e));
    expect(viaDispatcher.single, same(e));
  });
}

class _Handler implements EventHandler<CatalogMutationEvent> {
  _Handler(this.events);
  final List<CatalogMutationEvent> events;
  @override
  void handle(CatalogMutationEvent event) => events.add(event);
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/catalog_event_migration_test.dart`
Expected: FAIL — `CatalogMutationBus` 无 `dispatcher` 参数。

- [ ] **Step 3: 实现迁移**

```dart
// client/lib/services/catalog/catalog_mutation_bus.dart (修改后)
import 'dart:async';

import '../event/dispatcher.dart';
import 'catalog_kind.dart';

/// Family kind for the central dispatcher. Single-member: the rich payload
/// (kind/op/ids) stays on the event itself — the dispatcher only routes.
enum CatalogMutationKind { mutated }

class CatalogMutationEvent implements DispatcherEvent<CatalogMutationKind> {
  const CatalogMutationEvent({
    required this.kind,
    required this.op,
    required this.ids,
    required this.workspaceId,
    [this.timestamp,]
  });

  @override
  CatalogMutationKind get kind => CatalogMutationKind.mutated;
  final String kind; // ← 命名冲突:原字段 kind(String) 与接口 kind(枚举)冲突
  ...
}
```

**命名冲突决策（实现者必读）**：`CatalogMutationEvent.kind`（`String`，catalog 域语义）与 `DispatcherEvent.kind`（枚举）撞名。定案：**接口侧改名**——`DispatcherEvent` 的 getter 改为 `K get eventKind`（回改 Task 1/2/3 的接口与测试），域字段 `kind` 保留不动，消费方零改动。这是 Dart port 的必要偏离（YARN `getType()` 无撞名问题），doc comment 标注。`CatalogMutationBus` 修改：

```dart
class CatalogMutationBus {
  CatalogMutationBus({Dispatcher? dispatcher}) : _dispatcher = dispatcher;

  final Dispatcher? _dispatcher;
  final StreamController<CatalogEventRecord> _controller =
      StreamController.broadcast(); // 泛型保持 CatalogMutationEvent 不变

  Stream<CatalogMutationEvent> listen() {
    // 行为等价:当无 dispatcher 时,listen() 仍直接来自本地 controller;
    // 有 dispatcher 时,本地 controller 由 dispatcher 处理循环回填。
    ...
  }

  void emit(CatalogMutationEvent event) {
    if (_dispatcher != null) {
      _dispatcher.dispatch(event);
    } else {
      _controller.add(event); // 旧路径保留:无 dispatcher 的测试直构场景
    }
  }
}
```

**listen() 等价实现细节**：为绝对保持现有测试（`emit` 后 `Future.delayed(Duration.zero)` 收到）行为，`listen()` 在无 dispatcher 时返回 `_controller.stream`；有 dispatcher 时同样返回 `_controller.stream`，但 bus 在构造时向 dispatcher `registerFamily` 一个内部 handler，把事件 `add` 回 `_controller`——保证单一事实来源（dispatcher），legacy 流是回填。注意异步时序：dispatcher 消费多一跳 event-loop，现有测试里 `await Future<void>.delayed(Duration.zero)` 一跳可能不够——若现有测试因此红，**把该测试的等待改为 `await d.stop()` 或两跳**，并在 commit message 注明"测试等待时序放宽,断言不变"。

`catalog_runtime.dart:66` 改为 `final mutationBus = bus ?? CatalogMutationBus(dispatcher: EventPublisher.instance.attachedDispatcher);`（`EventPublisher` 增加 `Dispatcher? get attachedDispatcher` getter）。

- [ ] **Step 4: 跑新旧测试**

Run: `cd client && dart run tool/run_tests.dart test/services/event/catalog_event_migration_test.dart test/services/catalog/`
Expected: 新对照测试 PASS；`catalog_mutation_bus_test.dart` 原样 PASS（或仅时序等待放宽，断言未动）；其余 catalog 测试 PASS。

- [ ] **Step 5: app_shell 接线**

`app_shell.dart` 构造 `CatalogRuntime` 处（经 `EventPublisher.instance.attachedDispatcher`）确认 dispatcher 已 attach 在前。若 CatalogRuntime 构造早于 app_shell attach，把 attach 提前到同一装配函数最前面。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/catalog/ client/lib/services/event/ client/test/services/event/catalog_event_migration_test.dart client/lib/app/app_shell.dart
git commit -m "refactor(event): route CatalogMutationBus through central dispatcher (behavior-equivalent)"
```

---

### Task 5: 迁移 `WorkspaceFsWatcher`（行为等价）

**Files:**
- Modify: `client/lib/services/io/workspace_fs_watcher.dart`（构造加可选 `Dispatcher? dispatcher`；`_emit` 发布 `WorkspaceFsChangedEvent`；`onChanged` 流保留为回填）
- Create: `client/lib/services/event/workspace_fs_event.dart`（`enum WorkspaceFsKind { changed }` + `WorkspaceFsChangedEvent` 携带 `root` + `FsChangeBatch batch`）
- Modify: `client/lib/widgets/right_tools/right_tools_lifecycle.dart:481`（构造时传 dispatcher）
- Test: `client/test/services/io/workspace_fs_watcher_test.dart`（**现有 15.5K 测试不动，必须原样通过**）
- Test: `client/test/services/event/workspace_fs_event_migration_test.dart`（新增对照）

**Interfaces:**
- Consumes: Task 1/2 `Dispatcher`、Task 3 `EventPublisher`。
- Produces: `WorkspaceFsWatcher` 对外 API 不变（`onChanged` / `poke()` / `isSupported` / `resume()` / `suspend()` / `stopAndDispose()`）。

- [ ] **Step 1: 写对照测试**

```dart
// client/test/services/event/workspace_fs_event_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/workspace_fs_event.dart';

void main() {
  test('fs change event carries batch and root', () async {
    final d = AsyncDispatcher()..start();
    final received = <WorkspaceFsChangedEvent>[];
    d.registerFamily<WorkspaceFsKind>(
      WorkspaceFsKind.changed.runtimeType,
      _Handler(received),
    );

    d.dispatch(WorkspaceFsChangedEvent(
      root: '/w/a',
      batch: (changedDirs: const {'/w/a/lib'}, structural: true),
      timestamp: DateTime(2026),
    ));
    await d.stop();

    expect(received.single.root, '/w/a');
    expect(received.single.batch.structural, isTrue);
  });
}

class _Handler implements EventHandler<WorkspaceFsChangedEvent> {
  _Handler(this.events);
  final List<WorkspaceFsChangedEvent> events;
  @override
  void handle(WorkspaceFsChangedEvent event) => events.add(event);
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/workspace_fs_event_migration_test.dart`
Expected: FAIL — `workspace_fs_event.dart` 不存在。

- [ ] **Step 3: 实现**（与 Task 4 同构：`_emit` 处 `dispatcher?.dispatch(WorkspaceFsChangedEvent(...))`，无 dispatcher 时维持原 `_controller.add` 路径；有 dispatcher 时构造即注册内部 handler 回填 `_controller`，`onChanged` 消费方零改动。`right_tools_lifecycle.dart:481` 构造处传 `dispatcher: EventPublisher.instance.attachedDispatcher`。）

- [ ] **Step 4: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/services/event/workspace_fs_event_migration_test.dart test/services/io/`
Expected: 新测试 PASS；现有 `workspace_fs_watcher_test.dart` 原样 PASS（15.5K 的存量是行为等价的主证据；若个别用例因双跳时序需放宽等待，同 Task 4 处理原则）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/workspace_fs_event.dart client/lib/services/io/workspace_fs_watcher.dart client/lib/widgets/right_tools/right_tools_lifecycle.dart client/test/services/event/workspace_fs_event_migration_test.dart
git commit -m "refactor(event): route WorkspaceFsWatcher batches through central dispatcher (behavior-equivalent)"
```

---

### Task 6: 收尾——全套验证 + 文档

**Files:**
- Create: `client/lib/services/event/README.md`（一页:包定位、与 YARN 的映射表、偏离点清单、如何接入新事件族）
- Modify: `docs/ARCHITECTURE.md`（"where to change code" 表加一行 `services/event/`）

- [ ] **Step 1: 写 README**

内容含：YARN 映射表（从设计 spec 抄）、三处偏离（错误隔离 log 不退出 / 无界队列+深度告警 / `eventKind` 命名）、接入新事件族三步（定义 sealed class + kind 枚举 → 发布点 dispatch → 消费方 registerFamily）。

- [ ] **Step 2: analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增问题。

- [ ] **Step 3: 全套测试（后台，仅此一次）**

Run: `cd client && dart run tool/run_tests.dart`（后台运行）
Expected: 全绿。任何失败先修复再提交。

- [ ] **Step 4: 更新 ARCHITECTURE.md 并提交**

```bash
git add client/lib/services/event/README.md docs/ARCHITECTURE.md
git commit -m "docs(event): event package README + architecture map entry"
```

- [ ] **Step 5: 汇报**

向用户汇报：worktree 路径、提交清单、全套测试结果、验收标准达成情况（测试绿 + 行为等价证据——迁移类既有测试原样通过的说明）。
