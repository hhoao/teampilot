# SSH Home Connectivity Supervisor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 抽出 `SshHomeConnectivitySupervisor` 作为 dial/liveness/reconnect/state 的唯一 owner，`SshClientFactory` 退化为纯 pool，连接状态收敛为单一发布源，从而结构性修复「切到可达的远程后已进入应用内却仍显示需要重新连接」。

**Architecture:** 绞杀式（strangler）监督层：一个 app 级 `SshHomeConnectivitySupervisor` 持有 `SshConnectionGate` 与它自己构造的 `SshProfileConnectionCoordinator`，实现窄接口 `SshConnectivitySource` 并发布单一 `Stream<SshHomeConnectivityState>`；`SshClientFactory` 只保留 lease 池，通过一个注入的只读 `SshIoGuard` 转发 down 信号；`SshConnectionCubit` 退化为纯投影，`HomeConnectionCubit` 由 app_shell 的**单一订阅**驱动（不再有 4 个 hook）。分 5 个可独立验证的提交，每步 TDD。

**Tech Stack:** Flutter / Dart 3、flutter_bloc (Cubit)、`dart:async` Stream/Timer、`flutter_test`、仓库自研 `dart run tool/run_tests.dart`。

**设计依据：** `docs/superpowers/specs/2026-11-12-ssh-home-connectivity-supervisor-design.md`（`eb8de7fae` + 本计划附带的补订）。该 spec 写的是「4 个提交」，本计划拆成 5 个：把「state + supervisor 骨架」拆成两步，使每步都能独立 `flutter analyze` + 定向测试通过。

## Global Constraints

- **绝不直接跑 `flutter test`** —— 一律 `cd client && dart run tool/run_tests.dart <paths/options>`；并发直跑会污染共享 build cache。
- 内循环 `cd client && flutter analyze`；验证只跑改动覆盖到的测试文件，本地改动**不跑全量套件**；全量套件只在交付前跑一次 `cd client && dart run tool/run_tests.dart`。
- 工作区有其它会话的并发未提交改动（chat / compose / reasoning 等）：每个提交只用 `git commit -- <显式文件列表>`，**禁止** `git add -A` / `git commit -a` / `git add .` / 通配符。提交前用 `git status --short` 核对清单。
- 纯 Dart service 不得 import `flutter_bloc`；投影函数放 cubit 内，不放 service。
- `SshProfileDownException` / `isSshProfileDown` 是公开契约，**签名与行为不变**：`storage_failure.dart:34`、`vault_split_migration.dart:29/46`、`legacy_import.dart:506`、`remote_cli_readiness.dart:177/239`、`session_chat_view.dart:400`、`app_shell.dart:1038/1701/2086/3466/4765` 都依赖它。
- `SshProfileConnectionCoordinator` 是 `main.dart:641` 的 `RepositoryProvider` 类型，被 `workspace_terminal_panel.dart:158` 读取 `sessionReconnectSignals`。**本增量不删除该类**：supervisor 构造并持有它，`AppShell` 暴露 `supervisor.coordinator` 供 DI，`workspace_terminal_panel.dart` 零改动。
- 已提交的时序修复必须保留：合并窗口 `_disconnectCoalesceTimers`、`_shouldPreferDisconnectError`、hook 调用包在 try/finally 内（`ssh_profile_connection_coordinator.dart:427`）、storage plane-scoped 退役（`:226-231`）、`profileInvalidated` 可重试（`9c82e0c45`）、gate 的 `suspend` 不可被 `allowNextDial` 绕过。
- 日志用 `appLogger`（`utils/logging/logger.dart`），不用 `print`；用户可见文案走 l10n（本增量不新增文案）。
- `SshPhase` 无 `down` 值（避免与 `SshConnectionGateState.down` / `RemoteConnectionStatus.down` 混淆），对应概念叫 `unreachable`。

---

## 文件结构与职责

| 文件 | 动作 | 职责 |
|---|---|---|
| `client/lib/services/ssh/ssh_connection_gate.dart` | 改（+1 typedef） | 新增 `SshIoGuard = void Function(String)` |
| `client/lib/services/ssh/ssh_home_connectivity_state.dart` | 新建 | `SshPhase` / `SshFailureKind` / `SshHomeConnectivityState`（不可变值对象）/ `SshConnectivitySource`（窄接口）/ re-export `SshIoGuard` |
| `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart` | 新建 | 唯一 owner：持有 gate + coordinator，发布 `changes`，持有 `_activeHomeId` / `_dialInFlight` / `planeRebinding` |
| `client/lib/services/ssh/ssh_client_factory.dart` + 2 个 `part` | 改 | 退化为纯 pool：删 gate 字段/构造参数/所有 `markX`/`allowDialWhenDown`/`suspend`/`dispose`/`_GatedMemberTransport`，入口改调注入的 `SshIoGuard` |
| `client/lib/services/ssh/ssh_profile_connection_coordinator.dart` | 改 | 构造参数加 `gate` + `dial`；15 处 `_factory.connectionGate` → `_gate`；`userConnect`/`_runReconnect` 改走注入的 `_dial`；删 `_storageReconnects` |
| `client/lib/cubits/ssh_connection_cubit.dart` | 改 | 变投影：删 `_lastFailureStatus`/`_connectingIds`/`_resolveStatus`/`_monitorSubscriptions`/`_poolSubscription`，注入 `SshConnectivitySource` |
| `client/lib/cubits/home_connection_cubit.dart` | **不改** | API 保留；由 app_shell 单一订阅驱动（不再有 4 hook 分发） |
| `client/lib/app/app_shell.dart` | 改 | 构造 supervisor；`changes` 单一订阅；删 4 hook + `markX` 分发；`waitForSshProfileRecovery` → `awaitAvailable`；`switchHomeTarget` → `activateHome`；boot 特例删除；热恢复接 `changes` |
| `client/lib/main.dart` | 改（1 行） | `RepositoryProvider<SshProfileConnectionCoordinator>.value(value: shell.supervisor.coordinator)` |
| `client/lib/widgets/workspace_terminal_panel.dart` | **不改** | 继续读 `RepositoryProvider<SshProfileConnectionCoordinator>` |
| `client/test/support/ssh_connectivity_test_harness.dart` | 新建 | `TestSshConnectivity implements SshConnectivitySource`（测试用可控状态源） |
| 测试文件 | 新建/改 | 见各 Task |

## 关键决策（供零上下文执行者）

- **D1 — supervisor 构造签名全程稳定**（Task 2–5 不变），避免中途改签名把所有 harness 改两遍：

```dart
SshHomeConnectivitySupervisor({
  required SshClientFactory factory,
  required SshConnectionEvents events,
  required SshProfileResolver profileResolver,
  required SshConnectionGate gate,
  SshProfileReconnectPolicy policy = const SshProfileReconnectPolicy(),
  SshProfileDisconnectHandler? onDisconnect,
  SshSessionPlaneReconnectHandler? onReconnectSessionPlane,
  Future<void> Function(SshProfile)? dialProfile, // 构造注入，测试用
})
```

  supervisor **自己构造** `SshProfileConnectionCoordinator` 并把 4 个 hook 内部接到自己的方法上；app_shell 不再提供 hook。`coordinator` 作为 getter 暴露给 DI。

- **D2 — gate 所有权从 factory 移到 supervisor，但 `beforeIo` 语义不删**。factory 构造参数 `SshConnectionGate? connectionGate` 改为 `SshIoGuard ioGuard = _noopGuard`，入口调 `_ioGuard(profile.id)`，仍抛 `SshProfileDownException`。supervisor 的 `ioGuard` getter 返回 `_gate.beforeIo`。重连拨号前 supervisor 先把 gate 置 `connecting`，`beforeIo` 放行，因此 `allowDialWhenDown` 可删。
- **D3 — `SshConnectionGate` 没有 `onUp` 回调**（只有已被 coordinator 独占的 `onDown` / `onWaiter`）。所以 supervisor 不订阅 gate 事件，而是靠 `factory.storagePoolChanges`、`coordinator.changesFor(id)`、内部 hook（`onReconnectAttempt` / `onReconnected` / `onNonRetryableClose`）以及显式的 `observeProfile(id)` 触发重新推导。
- **D4 — 窄接口 `SshConnectivitySource`**：`SshConnectionCubit` 依赖它而非整个 supervisor，测试注入 `TestSshConnectivity` 即可，`SshClientFactory` / `SshProfileConnectionCoordinator` 继续作为命令依赖留在 cubit 构造参数里（`userConnect` / `userDisconnect` / `syncProfiles` 要用）。这样 ~16 个 cubit 测试的迁移只是**加一个参数**，不用重写套件。
- **D5 — `HomeConnectionCubit` 不改**。spec 里写的「cubit 变投影」通过「app_shell 只留一个 `supervisor.changes` 订阅去调用它既有的 `markX`」实现：单一发布者成立，且 `home_connection_cubit_test.dart` / `startup_gate_test.dart` 零改动。
- **D6 — 不删除 `SshProfileConnectionCoordinator` 类**，`main.dart` 只改一行取 `shell.supervisor.coordinator`。终端面板与 ~16 个测试继续拿到同一个类型。

---

### Task 1: 纯状态类型 + `SshIoGuard` + `SshConnectivitySource` + 单测

**Files:**
- Create: `client/lib/services/ssh/ssh_home_connectivity_state.dart`
- Modify: `client/lib/services/ssh/ssh_connection_gate.dart:31`（`isSshProfileDown` 之后）
- Test: `client/test/services/ssh/ssh_home_connectivity_state_test.dart`

**Interfaces:**
- Produces: `SshPhase`、`SshFailureKind`、`SshHomeConnectivityState`、`SshConnectivitySource`、`SshIoGuard`（re-export）。
- Consumes: `package:flutter/foundation.dart` 的 `@immutable`（与 `services/remote/remote_connection_monitor.dart` 现有用法一致）。

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/ssh/ssh_home_connectivity_state_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';

void main() {
  group('SshHomeConnectivityState', () {
    test('up() clears every failure surface in one value (invariant 3)', () {
      final dirty = const SshHomeConnectivityState(
        profileId: 'p1',
        phase: SshPhase.reconnecting,
        failure: SshFailureKind.authFailed,
        errorDetail: 'bad password',
        attempt: 4,
        storageLive: false,
      );
      final up = SshHomeConnectivityState.up('p1');

      expect(up.phase, SshPhase.up);
      expect(up.storageLive, isTrue);
      expect(up.failure, isNull);
      expect(up.errorDetail, isNull);
      expect(up.attempt, 0);
      expect(up.planeRebinding, isFalse);
      // The constructor, not callers, owns the invariant.
      expect(dirty.failure, SshFailureKind.authFailed);
    });

    test('copyWith preserves unrelated fields and value equality holds', () {
      const a = SshHomeConnectivityState(profileId: 'p1');
      final b = a.copyWith(phase: SshPhase.connecting, attempt: 1);
      expect(b.profileId, 'p1');
      expect(b.phase, SshPhase.connecting);
      expect(b.attempt, 1);
      expect(b.storageLive, isFalse);
      expect(a == const SshHomeConnectivityState(profileId: 'p1'), isTrue);
      expect(a == b, isFalse);
    });

    test('isUp / isDown / retryActive agree with the phase table', () {
      expect(SshHomeConnectivityState.up('p1').isUp, isTrue);
      for (final phase in [
        SshPhase.unreachable,
        SshPhase.suspended,
        SshPhase.failed,
      ]) {
        expect(
          SshHomeConnectivityState(profileId: 'p1', phase: phase).isDown,
          isTrue,
          reason: '$phase must be down',
        );
      }
      expect(
        const SshHomeConnectivityState(
          profileId: 'p1',
          phase: SshPhase.reconnecting,
        ).retryActive,
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_state_test.dart`
Expected: 编译失败 `Target of URI doesn't exist: 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart'`。

- [ ] **Step 3: 写实现**

`client/lib/services/ssh/ssh_connection_gate.dart:31` 之后追加：

```dart
/// Read-only I/O permission check. The supervisor implements it from its
/// private gate and injects it into the pure storage pool; the pool holds no
/// gate state but still surfaces SshProfileDownException to repositories.
typedef SshIoGuard = void Function(String profileId);
```

新建 `client/lib/services/ssh/ssh_home_connectivity_state.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ssh_connection_gate.dart' show SshIoGuard;

export 'ssh_connection_gate.dart' show SshIoGuard;

/// Canonical lifecycle phase of one SSH home/profile. Deliberately has no
/// `down`: the codebase already has two different `down` values
/// (SshConnectionGateState.down, RemoteConnectionStatus.down).
enum SshPhase {
  idle,
  connecting,
  up,
  degraded,
  reconnecting,
  unreachable,
  suspended,
  failed,
}

/// Why a home stopped; surfaced so the user knows whether to re-pair, fix
/// credentials, or just retry.
enum SshFailureKind {
  hostIdentityChanged,
  authFailed,
  transportError,
  unknown,
}

/// The single source of truth for "is this home connected".
@immutable
class SshHomeConnectivityState {
  const SshHomeConnectivityState({
    required this.profileId,
    this.phase = SshPhase.idle,
    this.failure,
    this.errorDetail,
    this.attempt = 0,
    this.storageLive = false,
    this.planeRebinding = false,
  });

  /// The one atomic transition into "connected". Clearing failure/errorDetail/
  /// attempt in the same value is what stops the "需要重新连接" banner from
  /// sticking after a successful home switch (invariant 3). Never build an
  /// `up` state with the generic constructor.
  factory SshHomeConnectivityState.up(String profileId) =>
      SshHomeConnectivityState(
        profileId: profileId,
        phase: SshPhase.up,
        storageLive: true,
      );

  final String profileId;
  final SshPhase phase;
  final SshFailureKind? failure;
  final String? errorDetail;

  /// 1-based retry number; 0 when no retry is running.
  final int attempt;

  /// The durable truth: a usable storage lease exists.
  final bool storageLive;

  /// UI hold during a home storage plane rebind; NOT connectivity truth.
  final bool planeRebinding;

  bool get isUp => phase == SshPhase.up;

  bool get isDown =>
      phase == SshPhase.unreachable ||
      phase == SshPhase.suspended ||
      phase == SshPhase.failed;

  bool get retryActive => phase == SshPhase.reconnecting;

  SshHomeConnectivityState copyWith({
    String? profileId,
    SshPhase? phase,
    SshFailureKind? failure,
    String? errorDetail,
    int? attempt,
    bool? storageLive,
    bool? planeRebinding,
    bool clearFailure = false,
    bool clearErrorDetail = false,
  }) => SshHomeConnectivityState(
    profileId: profileId ?? this.profileId,
    phase: phase ?? this.phase,
    failure: clearFailure ? null : (failure ?? this.failure),
    errorDetail: clearErrorDetail ? null : (errorDetail ?? this.errorDetail),
    attempt: attempt ?? this.attempt,
    storageLive: storageLive ?? this.storageLive,
    planeRebinding: planeRebinding ?? this.planeRebinding,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshHomeConnectivityState &&
          profileId == other.profileId &&
          phase == other.phase &&
          failure == other.failure &&
          errorDetail == other.errorDetail &&
          attempt == other.attempt &&
          storageLive == other.storageLive &&
          planeRebinding == other.planeRebinding;

  @override
  int get hashCode => Object.hash(
    profileId,
    phase,
    failure,
    errorDetail,
    attempt,
    storageLive,
    planeRebinding,
  );

  @override
  String toString() =>
      'SshHomeConnectivityState($profileId, ${phase.name}, '
      'live=$storageLive, attempt=$attempt, failure=${failure?.name}, '
      'rebind=$planeRebinding)';
}

/// Narrow read port consumed by cubits. Implemented by
/// SshHomeConnectivitySupervisor in production and by a test double in tests,
/// so cubit tests never need a real factory/coordinator to drive UI state.
abstract class SshConnectivitySource {
  Stream<SshHomeConnectivityState> get changes;
  SshHomeConnectivityState stateFor(String profileId);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_state_test.dart`
Expected: `All tests passed!`（3 个用例）

- [ ] **Step 5: analyze + 提交**

Run: `cd client && flutter analyze lib/services/ssh/ssh_home_connectivity_state.dart lib/services/ssh/ssh_connection_gate.dart test/services/ssh/ssh_home_connectivity_state_test.dart`
Expected: `No issues found!`

```bash
git commit -m "feat(ssh): add SshHomeConnectivityState as the single connectivity value" -- \
  client/lib/services/ssh/ssh_home_connectivity_state.dart \
  client/lib/services/ssh/ssh_connection_gate.dart \
  client/test/services/ssh/ssh_home_connectivity_state_test.dart
```

---

### Task 2: Supervisor 骨架（仅镜像，无生产消费者）

**Files:**
- Create: `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart`
- Create: `client/test/support/ssh_connectivity_test_harness.dart`
- Test: `client/test/services/ssh/ssh_home_connectivity_supervisor_test.dart`

**Interfaces:**
- `SshHomeConnectivitySupervisor implements SshConnectivitySource`，构造签名见 **D1**（Task 2–5 全程不变）。
- 读：`changes`、`changesFor(id)`、`stateFor(id)`；`SshIoGuard get ioGuard`；`SshConnectionGate get gate`；`SshProfileConnectionCoordinator get coordinator`；`Future<void> awaitAvailable(id)`。
- coordinator hook 接线口：`noteReconnectAttempt(id, attempt)`、`noteReconnected(id)`、`noteNonRetryableClose(id, error)`、`bool shouldPersistRetry(id)`。
- 命令：`activateHome(String? id)`、`profileEdited(id)`、`observeProfile(id)`、`holdPlaneRebind()`、`releasePlaneRebind()`、`userConnect(profile)`、`userDisconnect(id)`、`resumeRetries(id)`、`resetReconnectAttempts(id)`、`restartReconnect(id)`、`dispose()`。

> 本 Task 只做**镜像**：supervisor 订阅 `factory.storagePoolChanges` 与 `coordinator.changesFor(id)`，用 gate 状态 + monitor 状态 + `hasLiveStorageClient` 推导并发布状态。命令方法先转发给 coordinator（Task 4 才把 dial 单飞真正搬进来）。**生产代码不接线**，因此旧测试必须全绿。

- [ ] **Step 1: 写测试辅助 + 失败测试**

新建 `client/test/support/ssh_connectivity_test_harness.dart`：

```dart
import 'dart:async';

import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';

/// Controllable SshConnectivitySource for cubit/widget tests. Emit a state to
/// drive every projection without building a real SSH factory.
final class TestSshConnectivity implements SshConnectivitySource {
  final _controller = StreamController<SshHomeConnectivityState>.broadcast();
  final _states = <String, SshHomeConnectivityState>{};

  @override
  Stream<SshHomeConnectivityState> get changes => _controller.stream;

  @override
  SshHomeConnectivityState stateFor(String profileId) =>
      _states[profileId] ?? SshHomeConnectivityState(profileId: profileId);

  void emit(SshHomeConnectivityState state) {
    _states[state.profileId] = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  Future<void> dispose() => _controller.close();
}
```

新建 `client/test/services/ssh/ssh_home_connectivity_supervisor_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_supervisor.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';

import '../../support/post_frame_test_harness.dart' show waitUntil;

const _profile = SshProfile(
  id: 'home',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

class _Harness {
  _Harness() {
    gate = SshConnectionGate();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connectionGate: gate, // Task 4 改成 ioGuard: gate.beforeIo（唯一一行变化）
    );
    supervisor = SshHomeConnectivitySupervisor(
      factory: factory,
      events: events,
      profileResolver: (id) => id == _profile.id ? _profile : null,
      gate: gate,
    );
  }

  final events = SshConnectionEvents();
  late final SshConnectionGate gate;
  late final SshClientFactory factory;
  late final SshHomeConnectivitySupervisor supervisor;

  Future<void> dispose() async {
    await supervisor.dispose();
    await factory.close();
  }
}

void main() {
  test('observeProfile re-derives up and clears any prior failure', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    final states = <SshHomeConnectivityState>[];
    final sub = h.supervisor.changes.listen(states.add);
    addTearDown(sub.cancel);

    // A stale failure from an earlier wave.
    h.supervisor.noteNonRetryableClose(_profile.id, StateError('auth'));
    // Gate has no onUp callback (see D3), so observeProfile is the explicit
    // re-derive trigger. It always emits once, even when already subscribed.
    h.gate.markUp(_profile.id);
    h.supervisor.observeProfile(_profile.id);

    await waitUntil(() => states.isNotEmpty && states.last.isUp);
    expect(states.last.phase, SshPhase.up);
    expect(states.last.storageLive, isTrue);
    expect(states.last.failure, isNull);
  });

  test('activateHome persists retries only for the active home', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    h.supervisor.activateHome(_profile.id);
    expect(h.supervisor.shouldPersistRetry(_profile.id), isTrue);
    expect(h.supervisor.shouldPersistRetry('other'), isFalse);
  });

  test('profileEdited never publishes a failed phase', () async {
    final h = _Harness();
    addTearDown(h.dispose);

    h.supervisor.activateHome(_profile.id);
    final phases = <SshPhase>[];
    final sub = h.supervisor.changesFor(_profile.id).listen(
      (s) => phases.add(s.phase),
    );
    addTearDown(sub.cancel);

    h.supervisor.profileEdited(_profile.id);
    await waitUntil(() => phases.isNotEmpty);
    expect(phases.where((p) => p == SshPhase.failed), isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_supervisor_test.dart`
Expected: 编译失败 `Target of URI doesn't exist: ssh_home_connectivity_supervisor.dart`。

- [ ] **Step 3: 写实现**

新建 `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart`：

```dart
import 'dart:async';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../remote/remote_connection_monitor.dart';
import 'ssh_client_factory.dart';
import 'ssh_connection_events.dart';
import 'ssh_connection_failure.dart';
import 'ssh_connection_gate.dart';
import 'ssh_home_connectivity_state.dart';
import 'ssh_profile_connection_coordinator.dart';
import 'ssh_profile_reconnect_policy.dart';

export 'ssh_home_connectivity_state.dart'
    show SshHomeConnectivityState, SshPhase, SshFailureKind;

/// App-level single owner of SSH home connectivity. Pure Dart: no
/// flutter_bloc import. Publishes one state stream and drives the gate.
class SshHomeConnectivitySupervisor implements SshConnectivitySource {
  SshHomeConnectivitySupervisor({
    required SshClientFactory factory,
    required SshConnectionEvents events,
    required SshProfileResolver profileResolver,
    required SshConnectionGate gate,
    SshProfileReconnectPolicy policy = const SshProfileReconnectPolicy(),
    SshProfileDisconnectHandler? onDisconnect,
    SshSessionPlaneReconnectHandler? onReconnectSessionPlane,
    Future<void> Function(SshProfile)? dialProfile,
  }) : _factory = factory,
       _events = events,
       _profileResolver = profileResolver,
       _gate = gate,
       _dialProfile = dialProfile ??
           ((profile) => factory.ensureStorageConnected(profile)) {
    _coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: profileResolver,
      policy: policy,
      onDisconnect: onDisconnect,
      onReconnectSessionPlane: onReconnectSessionPlane,
      onReconnectAttempt: noteReconnectAttempt,
      onReconnected: noteReconnected,
      onNonRetryableClose: noteNonRetryableClose,
      persistRetry: shouldPersistRetry,
    );
    _poolSub = factory.storagePoolChanges.listen(_onPoolChanged);
  }

  final SshClientFactory _factory;
  final SshConnectionEvents _events;
  final SshProfileResolver _profileResolver;
  final SshConnectionGate _gate;
  final Future<void> Function(SshProfile) _dialProfile;
  late final SshProfileConnectionCoordinator _coordinator;

  final Map<String, SshHomeConnectivityState> _states = {};
  final Map<String, StreamSubscription<RemoteConnectionState>> _monitorSubs = {};
  final Map<String, Future<void>> _dialInFlight = {};
  final _changes = StreamController<SshHomeConnectivityState>.broadcast();
  StreamSubscription<String>? _poolSub;
  String? _activeHomeId;
  var _planeRebinding = false;
  var _disposed = false;

  @override
  Stream<SshHomeConnectivityState> get changes => _changes.stream;

  Stream<SshHomeConnectivityState> changesFor(String id) =>
      _changes.stream.where((s) => s.profileId == id);

  @override
  SshHomeConnectivityState stateFor(String id) =>
      _states[id] ?? SshHomeConnectivityState(profileId: id);

  SshIoGuard get ioGuard => _gate.beforeIo;
  SshConnectionGate get gate => _gate;

  /// DI compatibility: main.dart and workspace_terminal_panel.dart read this
  /// coordinator type. Owned here, never constructed elsewhere.
  SshProfileConnectionCoordinator get coordinator => _coordinator;

  Future<void> awaitAvailable(String id) => _gate.waitUntilUp(id);

  /// Reads supervisor state, never a cubit's status (invariant 4).
  bool shouldPersistRetry(String id) =>
      id == _activeHomeId && !stateFor(id).isUp;

  // --- coordinator hook surface (all state writes funnel through _emit) ---

  void noteReconnectAttempt(String id, int attempt) => _publish(
    id,
    stateFor(id).copyWith(phase: SshPhase.reconnecting, attempt: attempt),
  );

  void noteReconnected(String id) {
    _gate.markUp(id);
    _emit(id);
  }

  void noteNonRetryableClose(String id, Object error) {
    final failure = isSshHostKeyFailure(error)
        ? SshFailureKind.hostIdentityChanged
        : isSshAuthFailure(error)
        ? SshFailureKind.authFailed
        : SshFailureKind.transportError;
    _publish(
      id,
      stateFor(id).copyWith(
        phase: SshPhase.failed,
        failure: failure,
        storageLive: false,
      ),
    );
  }

  // --- commands ---

  void observeProfile(String id) {
    _monitorSubs.putIfAbsent(
      id,
      () => _coordinator.changesFor(id).listen((_) => _emit(id)),
    );
    // Always re-derive: gate has no onUp callback (D3).
    _emit(id);
  }

  void activateHome(String? id) {
    final previous = _activeHomeId;
    if (previous != null && previous != id) {
      _coordinator.userDisconnect(previous);
      _coordinator.resetReconnectAttempts(previous);
    }
    _activeHomeId = id;
    if (id != null) observeProfile(id);
  }

  void profileEdited(String id) {
    _gate.resume(id);
    _coordinator.resetReconnectAttempts(id);
    // Publish an explicit `connecting` (never `failed`, invariant 5) and
    // clear any stale failure so the local re-target stays retryable.
    // Must NOT be `_emit(id)`: after activateHome the derived idle state is
    // identical to the stored one, so _publish would dedupe it to silence.
    _publish(
      id,
      stateFor(id).copyWith(
        phase: SshPhase.connecting,
        attempt: 0,
        clearFailure: true,
        clearErrorDetail: true,
      ),
    );
  }

  void holdPlaneRebind() {
    _planeRebinding = true;
    final id = _activeHomeId;
    if (id != null) _emit(id);
  }

  void releasePlaneRebind() {
    _planeRebinding = false;
    final id = _activeHomeId;
    if (id != null) _emit(id);
  }

  Future<void> userConnect(SshProfile profile) =>
      _coordinator.userConnect(profile);
  Future<void> userDisconnect(String id) => _coordinator.userDisconnect(id);
  void resumeRetries(String id) => _coordinator.resumeRetries(id);
  void resetReconnectAttempts(String id) =>
      _coordinator.resetReconnectAttempts(id);
  void restartReconnect(String id) => _coordinator.restartReconnect(id);

  void _onPoolChanged(String id) {
    final live = _factory.hasLiveStorageClient(id);
    if (live) _gate.markUp(id);
    _emit(id);
  }

  void _emit(String id) => _publish(id, _derive(id));

  void _publish(String id, SshHomeConnectivityState next) {
    if (_disposed || _changes.isClosed || _states[id] == next) return;
    _states[id] = next;
    _changes.add(next);
  }

  SshHomeConnectivityState _derive(String id) {
    final previous = stateFor(id);
    final gateState = _gate.stateOf(id);
    final monitor = _coordinator.monitorFor(id).state.status;
    final live = _factory.hasLiveStorageClient(id);
    final isActiveHome = id == _activeHomeId;

    final phase = switch (gateState) {
      SshConnectionGateState.suspended => SshPhase.suspended,
      SshConnectionGateState.down =>
        monitor == RemoteConnectionStatus.reconnecting
            ? SshPhase.reconnecting
            : SshPhase.unreachable,
      SshConnectionGateState.connecting => SshPhase.connecting,
      SshConnectionGateState.up => SshPhase.up,
      SshConnectionGateState.idle =>
        monitor == RemoteConnectionStatus.reconnecting
            ? SshPhase.reconnecting
            : SshPhase.idle,
    };

    if (phase == SshPhase.up) {
      // Single atomic value: never carries a stale failure (invariant 3).
      return SshHomeConnectivityState.up(id).copyWith(
        planeRebinding: _planeRebinding && isActiveHome,
      );
    }
    return previous.copyWith(
      phase: phase,
      storageLive: live || gateState == SshConnectionGateState.up,
      planeRebinding: _planeRebinding && isActiveHome,
      clearFailure: phase == SshPhase.connecting,
    );
  }

  /// Single-flight dial. Task 4 routes coordinator's userConnect/reconnect
  /// through this so only one clientFor exists at a time (invariant 1).
  Future<void> dial(SshProfile profile) {
    final existing = _dialInFlight[profile.id];
    if (existing != null) return existing;
    _gate.markConnecting(profile.id);
    final future = _dialProfile(profile).whenComplete(
      () => _dialInFlight.remove(profile.id),
    );
    _dialInFlight[profile.id] = future;
    return future;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _poolSub?.cancel();
    for (final sub in _monitorSubs.values) {
      await sub.cancel();
    }
    _monitorSubs.clear();
    _dialInFlight.clear();
    await _coordinator.dispose();
    await _changes.close();
    _gate.dispose();
  }
}
```

> 说明：`gate.dispose()` 放在 supervisor 的 `dispose()` 里（Task 4 从 factory 的 `_close()` 删除）。`factory.close()` 与 supervisor.dispose() 都会被 shell 调用，顺序由 app_shell 保证（先 supervisor 后 factory）。

- [ ] **Step 4: 跑测试 + 回归确认通过**

Run:
```
cd client && dart run tool/run_tests.dart \
  test/services/ssh/ssh_home_connectivity_supervisor_test.dart \
  test/services/ssh/ssh_home_connectivity_state_test.dart \
  test/services/ssh/ssh_connection_gate_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_reconnect_test.dart
```
Expected: 全部 `All tests passed!`（旧 coordinator 测试零改动仍绿 = 镜像等价）。

- [ ] **Step 5: analyze + 提交**

Run: `cd client && flutter analyze lib/services/ssh/ssh_home_connectivity_supervisor.dart test/services/ssh/ssh_home_connectivity_supervisor_test.dart test/support/ssh_connectivity_test_harness.dart`
Expected: `No issues found!`

```bash
git commit -m "feat(ssh): add SshHomeConnectivitySupervisor mirror skeleton" -- \
  client/lib/services/ssh/ssh_home_connectivity_supervisor.dart \
  client/lib/services/ssh/ssh_home_connectivity_state.dart \
  client/test/support/ssh_connectivity_test_harness.dart \
  client/test/services/ssh/ssh_home_connectivity_supervisor_test.dart
```

---

### Task 3: `SshConnectionCubit` 变投影 + app_shell 单一订阅

**Files:**
- Modify: `client/lib/cubits/ssh_connection_cubit.dart`
- Modify: `client/lib/app/app_shell.dart:3135-3219, 3901-3971, 983-987, 4283-4344`
- Modify: `client/lib/main.dart:641`
- Test: `client/test/cubits/ssh_connection_cubit_test.dart`、`client/test/cubits/ssh_connection_cubit_sync_test.dart` 及 Step 5 列出的 harness 文件

**Interfaces:**
- `SshConnectionCubit` 构造参数**新增** `required SshConnectivitySource connectivity`（`factory` / `coordinator` 保留作命令依赖，见 D4）。
- `HomeConnectionCubit` **不改**。

- [ ] **Step 1: 写失败测试（投影表 + 不变量 3）**

在 `client/test/cubits/ssh_connection_cubit_test.dart` 的 `main()` 末尾追加（复用文件现有 `_Harness`；先在 Step 3 给 `_Harness` 加 `connectivity` 字段）：

```dart
test('a stale failure is cleared by the up transition (invariant 3)', () async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  final cubit = harness.createCubit();
  addTearDown(cubit.close);
  await cubit.syncProfiles([_p1]);

  harness.connectivity.emit(const SshHomeConnectivityState(
    profileId: 'p1',
    phase: SshPhase.failed,
    failure: SshFailureKind.authFailed,
  ));
  await pumpEventQueue();
  expect(cubit.state.hostsById['p1']!.status, SshHostUiStatus.authFailed);

  harness.connectivity.emit(SshHomeConnectivityState.up('p1'));
  await pumpEventQueue();
  expect(cubit.state.hostsById['p1']!.status, SshHostUiStatus.connected);
});

test('degraded heartbeat still projects connected', () async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  final cubit = harness.createCubit();
  addTearDown(cubit.close);
  await cubit.syncProfiles([_p1]);

  harness.connectivity.emit(const SshHomeConnectivityState(
    profileId: 'p1',
    phase: SshPhase.degraded,
    storageLive: true,
  ));
  await pumpEventQueue();
  expect(cubit.state.hostsById['p1']!.status, SshHostUiStatus.connected);
});

test('reconnecting projects to reconnecting with the attempt number', () async {
  final harness = _Harness();
  addTearDown(harness.dispose);
  final cubit = harness.createCubit();
  addTearDown(cubit.close);
  await cubit.syncProfiles([_p1]);

  harness.connectivity.emit(const SshHomeConnectivityState(
    profileId: 'p1', phase: SshPhase.reconnecting, attempt: 3,
  ));
  await pumpEventQueue();
  expect(cubit.state.hostsById['p1']!.status, SshHostUiStatus.reconnecting);
});
```

在文件顶部加 import：

```dart
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ssh_connection_cubit_test.dart`
Expected: 编译失败 `The named parameter 'connectivity' isn't defined`（`createCubit` 已升级）或断言失败（粘性 `_lastFailureStatus` 未清）。

- [ ] **Step 3: 实现投影**

`client/lib/cubits/ssh_connection_cubit.dart`：
- import `services/ssh/ssh_home_connectivity_state.dart`。
- 构造参数加 `required SshConnectivitySource connectivity`，字段 `final SshConnectivitySource _connectivity;`。
- 删字段：`_connectingIds`、`_lastFailureStatus`、`_monitorSubscriptions`、`_poolSubscription`；删 `close()` 里对它们的 cancel 循环，改为单个 `StreamSubscription<SshHomeConnectivityState> _connectivitySub`。
- 构造体改为 `_connectivitySub = _connectivity.changes.listen((_) => emit(_buildState()));`，删 `_poolSubscription = _factory.storagePoolChanges.listen(_onPoolChanged);`。
- 删方法 `_onPoolChanged`、`_onMonitorChanged`、`_subscribeMonitor`、`_unsubscribeMonitor`、`_resolveStatus`。
- `syncProfiles` 的 removed 分支：`await _unsubscribeMonitor(id)` → 删除该行（保留 `await _relayTunnels?.closeFor(id)` 与 `await _coordinator.userDisconnect(id)`）；`_connectingIds.remove(id)` / `_lastErrorDetail.remove(id)` / `_lastFailureStatus.remove(id)` 三行删除；末尾的 `for (profile in profiles) _subscribeMonitor(...)` 循环删除。
- `connect()`：`_connectingIds.add/remove` 全部删除；catch 里 `_lastFailureStatus[profileId] = status` 与 `_lastErrorDetail[profileId] = ...` 删除（保留 `appLogger.w` 日志）；`emit(_buildState())` 保留（命令成功后由 supervisor 的 `changes` 再驱动一次）。
- `disconnect()`：删 `_connectingIds` / `_lastErrorDetail` / `_lastFailureStatus` 三行。
- `_buildState()` 里 `status: _resolveStatus(id)` → `status: _project(_connectivity.stateFor(id))`，`errorDetail: _lastErrorDetail[id]` → `errorDetail: state.errorDetail`（在循环里取 `final state = _connectivity.stateFor(id);`）。
- 新增纯投影函数：

```dart
SshHostUiStatus _project(SshHomeConnectivityState s) => switch (s.phase) {
  SshPhase.connecting => SshHostUiStatus.connecting,
  SshPhase.up || SshPhase.degraded => SshHostUiStatus.connected,
  SshPhase.reconnecting => SshHostUiStatus.reconnecting,
  SshPhase.failed => s.failure == SshFailureKind.authFailed
      ? SshHostUiStatus.authFailed
      : SshHostUiStatus.error,
  SshPhase.idle || SshPhase.unreachable || SshPhase.suspended =>
      SshHostUiStatus.disconnected,
};
```

- `close()`：`await _connectivitySub?.cancel();` 后 `return super.close();`。

- [ ] **Step 4: app_shell 单一订阅 + 删 4 hook**

`client/lib/app/app_shell.dart`：
- **共享同一个 gate（关键）**：factory 在 `:967` 构造时没传 `connectionGate`，会自己 new 一个；supervisor 若也 new 一个就会出现两个互不相干的 gate。在 `:967` 的 factory 构造**之前**声明：

```dart
final sshConnectivityGate = SshConnectionGate();
```

  并给该 `SshClientFactory(...)` 加一行 `connectionGate: sshConnectivityGate,`（Task 4 把这唯一一行改成 `ioGuard: sshConnectivityGate.beforeIo,`）。这样 Task 3 期间 coordinator 里的 `_factory.connectionGate`、factory 的 `beforeIo`、supervisor 的 `_gate` 全是同一实例。

- 删 `SshProfileConnectionCoordinator(...)` 整块构造（`:3135-3219`），改为构造 supervisor（复用上面那个 gate）：

```dart
void onSshDisconnect(
  String profileId,
  Object error,
  StackTrace stackTrace,
) {
  final profile = sshProfileById(profileId);
  final label = profile == null
      ? profileId
      : () {
          final name = profile.name.trim();
          return name.isEmpty
              ? '${profile.username}@${profile.host}'
              : '$name (${profile.username}@${profile.host})';
        }();
  if (error is SshTransportClosed) {
    final cause = error.cause;
    final message = '[ssh] profile $profileId ($label) transport closed: '
        'reason=${error.reason.name} plane=${error.plane.name}'
        '${cause != null ? ' cause=$cause' : ''}';
    if (isExpectedLocalSshTransportClose(error)) {
      appLogger.i(message);
    } else {
      appLogger.w(
        message,
        error: cause,
        stackTrace: cause != null ? stackTrace : null,
      );
    }
    return;
  }
  appLogger.w(
    '[ssh] profile $profileId ($label) transport closed: $error',
    error: error,
    stackTrace: stackTrace,
  );
}

final sshHomeConnectivity = SshHomeConnectivitySupervisor(
  factory: sshClientFactory,
  events: sshConnectionEvents,
  profileResolver: sshProfileById,
  gate: sshConnectivityGate,
  onDisconnect: onSshDisconnect,
  onReconnectSessionPlane: chatCubit.reconnectSshProfile,
);
final sshProfileConnectionCoordinator = sshHomeConnectivity.coordinator;
```

  `onDisconnect` 的日志回调体（`:3139-3171`）原样保留。**删除** `onReconnectAttempt` / `onReconnected` / `onNonRetryableClose` / `persistRetry` 四个参数（supervisor 已内部接线）。
- `SshConnectionCubit(...)` 构造（`:3236`）加 `connectivity: sshHomeConnectivity,`。
- `AppShell`（`:678` 附近）加字段 `final SshHomeConnectivitySupervisor supervisor;`，构造处赋值 `sshHomeConnectivity`。
- `waitForSshProfileRecovery`（`:983-987`）**本 Task 不动**：它定义在 supervisor 构造（`:3135`）之前，引用不到 supervisor。由于 `sshConnectivityGate` 声明在 `:967`（更早），且 `supervisor.awaitAvailable` 本身就是 `_gate.waitUntilUp` 的转发，这里直接调 gate 是等价且无作用域问题的。Task 4 删掉 factory 的 `connectionGate` 字段后，把这一行从 `sshClientFactory.connectionGate.waitUntilUp(...)` 改为 `sshConnectivityGate.waitUntilUp(...)` 即可。
- **删 4 hook 的 `markX` 分发**：`markBackgroundAttempt` / `markReconnected` / `markUnreachable` 调用点全部删除。
- `HomeConnectionCubit` 的 `onConnected` 回调体（`:3938-3967`）**原样保留它在 cubit 构造参数里的位置**（不迁移）。新增一个 `sshHomeConnectivity.changes` 订阅来驱动它既有的 `markX`，放在 `..markInitial(initialHome);`（`:3971`）之后：

```dart
SshPhase? _previousHomePhase;
homeConnectivitySub = sshHomeConnectivity.changes.listen((state) {
  final cubit = homeConnectionCubit;
  if (cubit == null || cubit.isClosed) return;
  if (state.profileId != activeHomeProfileId) return;
  final previous = _previousHomePhase;
  _previousHomePhase = state.phase;

  if (state.planeRebinding) {
    cubit.markPlaneRebinding();
    return;
  }
  switch (state.phase) {
    case SshPhase.idle:
    case SshPhase.connecting:
      // Boot seeds the cubit with markInitial(); an `idle` supervisor state
      // must NOT override a connected seed. rebind()/retryNow() already show
      // the progress page.
      break;
    case SshPhase.up:
    case SshPhase.degraded:
      // Only a genuine recovery transition runs hot recovery (onConnected).
      if (previous == SshPhase.connecting ||
          previous == SshPhase.reconnecting ||
          previous == SshPhase.failed) {
        cubit.markReconnected();
      }
      cubit.markPlaneReady();
    case SshPhase.reconnecting:
      cubit.markBackgroundAttempt(state.attempt);
    case SshPhase.unreachable:
    case SshPhase.suspended:
    case SshPhase.failed:
      cubit.markUnreachable(
        switch (state.failure) {
          SshFailureKind.hostIdentityChanged =>
            HomeErrorKind.hostIdentityChanged,
          SshFailureKind.authFailed => HomeErrorKind.authFailed,
          SshFailureKind.transportError => HomeErrorKind.transportError,
          SshFailureKind.unknown => HomeErrorKind.unknown,
          null => HomeErrorKind.transportError,
        },
      );
  }
});
```

  > **热恢复不回归**：`markReconnected()` 内部调用 `_onConnected()`，而 `onConnected` 回调体仍挂在 `HomeConnectionCubit` 上（`:3938-3967` 原样保留），所以 plane rebind / `runRemoteBootAfterConnect` / `reconnectHomeSshIfNeeded` 全部照旧触发。`homeConnectivitySub` 在 shell 的 dispose 里 cancel。`markBackgroundAttempt` 自带「已 connected 则忽略」的守卫，不会把健康 home 踢回连接页。
- boot 的 `restartReconnect` 特例（`:3978-3980`）与 `homeProfileWatchSub` 的 `rebind + retryNow`（`:3992-4007`）**本 Task 保留**，Task 5 收敛。
- `switchHomeTarget`（`:4283`）**本 Task 保留** `userDisconnect(previous)` / `resetReconnectAttempts(previous)` / `rebind` / `retryNow`，Task 5 收敛为 `activateHome`。
- `main.dart:641`：`value: shell.sshProfileConnectionCoordinator` → `value: shell.supervisor.coordinator`。

- [ ] **Step 5: 机械升级 ~16 个测试 harness**

Run: `cd client && grep -rln "SshConnectionCubit(" test | sort`
对每个文件，在 harness 里加：

```dart
final connectivity = TestSshConnectivity();
```

并把 `SshConnectionCubit(factory: X, coordinator: Y, ...)` 改为 `SshConnectionCubit(factory: X, coordinator: Y, connectivity: connectivity, ...)`；`dispose()` 里补 `await connectivity.dispose();`。import `package:teampilot/services/ssh/ssh_home_connectivity_state.dart` 与 `../support/ssh_connectivity_test_harness.dart`（相对路径按文件位置调整）。
`_StubSshConnectionCubit` / `_ControllableSshConnectionCubit` / `_SeededSshConnectionCubit` / `_RecordingSshConnectionCubit` 等子类的 `super(...)` 同步加参数。
`client/test/support/performance_scenario_app.dart:396`、`desktop_app_harness.dart:463` 同样处理。

**必须改的语义位点**（这些测试直接操纵 monitor / pool 来驱动 UI，投影后它们不再驱动 cubit）：
Run: `cd client && grep -rn "monitorFor(.*)\.\(reconnectStarted\|heartbeatTimedOut\|reconnected\|markDown\)\|hasLiveStorageClient\|_notifyPoolChange" test/cubits test/pages test/widgets`
按下面这张固定映射逐处替换（`profileId` 用该测试原本的 id 常量，例如 `_p1.id`）：

| 旧调用 | 新 `connectivity.emit(...)` |
|---|---|
| `monitorFor(id).reconnectStarted()` | `SshHomeConnectivityState(profileId: id, phase: SshPhase.reconnecting, attempt: 1)` |
| `monitorFor(id).reconnected()` | `SshHomeConnectivityState.up(id)` |
| `monitorFor(id).reconnectFailed()` / `markDown()` | `SshHomeConnectivityState(profileId: id, phase: SshPhase.unreachable)` |
| `monitorFor(id).heartbeatTimedOut()` | `SshHomeConnectivityState(profileId: id, phase: SshPhase.degraded, storageLive: true)` |
| 让 pool 变 live 的 `clientFor(...)` / `ensureStorageConnected(...)` | `SshHomeConnectivityState.up(id)` |
| 让 pool 变冷的 `disconnectProfile(...)` | `SshHomeConnectivityState(profileId: id, phase: SshPhase.unreachable)` |

示例：

```dart
// 旧：harness.coordinator.monitorFor(_p1.id).reconnectStarted();
// 新：
harness.connectivity.emit(const SshHomeConnectivityState(
  profileId: 'p1', phase: SshPhase.reconnecting, attempt: 1,
));
```

几处原本断言的是「pool live → connected」的用例（例如 `ssh_connection_cubit_test.dart` 里 `'seed: pool already live → connected'`），改为在 `syncProfiles` 之前 `connectivity.emit(SshHomeConnectivityState.up(id))`。
断言保持不变（投影表保证同相位 → 同 `SshHostUiStatus`）。**不要**为了迁就测试而改投影函数。

- [ ] **Step 6: 跑测试 + analyze**

Run:
```
cd client && dart run tool/run_tests.dart \
  test/cubits/ssh_connection_cubit_test.dart \
  test/cubits/ssh_connection_cubit_sync_test.dart \
  test/cubits/home_connection_cubit_test.dart \
  test/pages/startup_gate_test.dart \
  test/widgets/ssh/ssh_home_disconnected_banner_test.dart \
  test/services/ssh/ssh_home_connectivity_supervisor_test.dart
```
Expected: 全部 `All tests passed!`。
Run: `cd client && flutter analyze lib/cubits lib/app/app_shell.dart lib/main.dart test/cubits test/support`
Expected: `No issues found!`。

- [ ] **Step 7: 提交**

```bash
git commit -m "refactor(ssh): make SshConnectionCubit a projection of the supervisor stream" -- \
  client/lib/cubits/ssh_connection_cubit.dart \
  client/lib/app/app_shell.dart \
  client/lib/main.dart \
  client/test/cubits/ssh_connection_cubit_test.dart \
  client/test/cubits/ssh_connection_cubit_sync_test.dart \
  <其余按 git status --short 逐个列出的测试/支持文件>
```

---

### Task 4: dial 所有权搬进 supervisor、factory 退化为纯池（本 bug 的修复点）

**Files:**
- Modify: `client/lib/services/ssh/ssh_client_factory.dart` + `ssh_client_factory_narrow_operations.dart` + `ssh_client_factory_legacy_storage.dart`
- Modify: `client/lib/services/ssh/ssh_profile_connection_coordinator.dart`
- Modify: `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart`
- Modify: `client/test/support/ssh_connectivity_test_harness.dart`（无需改）
- Test: `ssh_client_factory_worker_test.dart`、`ssh_connection_gate_factory_test.dart`、`ssh_profile_connection_coordinator_test.dart`、`ssh_profile_connection_coordinator_reconnect_test.dart`、`storage_failure_test.dart`、`event_transport_client_test.dart`、新建 `ssh_home_connectivity_regression_test.dart`

**Interfaces:**
- `SshClientFactory` 构造参数：`SshConnectionGate? connectionGate` → `SshIoGuard ioGuard = _noopGuard`；删 `final SshConnectionGate connectionGate` 字段。
- `SshProfileConnectionCoordinator` 构造参数新增 `required SshConnectionGate gate` 与 `required Future<void> Function(SshProfile) dial`；内部 15 处 `_factory.connectionGate` → `_gate`；`reconnectStorage` / `_storageReconnects` 删除。
- `SshHomeConnectivitySupervisor.dial(profile)` 已是单飞（Task 2 实现），本 Task 把它注入 coordinator。

- [ ] **Step 1: 写失败回归测试（针对本 bug）**

新建 `client/test/services/ssh/ssh_home_connectivity_regression_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_supervisor.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';

const _newProfile = SshProfile(
  id: 'b', name: 'new', host: '10.0.0.2', username: 'u',
);

void main() {
  test('concurrent home activation produces ONE dial and no post-up down state',
      () async {
    final events = SshConnectionEvents();
    var dials = 0;
    final gate = SshConnectionGate();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      ioGuard: gate.beforeIo,
    );
    final supervisor = SshHomeConnectivitySupervisor(
      factory: factory,
      events: events,
      profileResolver: (id) => id == _newProfile.id ? _newProfile : null,
      gate: gate,
      // Construct-injected fake dial (AGENTS.md): no SSHClient fake needed.
      dialProfile: (profile) async {
        dials += 1;
        gate.markUp(profile.id);
      },
    );
    addTearDown(() async {
      await supervisor.dispose();
      await factory.close();
    });

    supervisor.activateHome(_newProfile.id);
    final phases = <SshPhase>[];
    final sub = supervisor.changesFor(_newProfile.id).listen(
      (s) => phases.add(s.phase),
    );
    addTearDown(sub.cancel);

    // Mirrors switchHomeTarget + retryNow + boot firing together.
    await Future.wait([
      supervisor.dial(_newProfile),
      supervisor.dial(_newProfile),
      supervisor.dial(_newProfile),
    ]);
    supervisor.observeProfile(_newProfile.id);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(dials, 1, reason: 'single-flight: no invalidated openings');
    expect(phases.last, SshPhase.up);
    // Invariant 3: after up, no real transport close may reintroduce a down
    // phase. The banner stays hidden.
    expect(
      phases.where((p) => p == SshPhase.reconnecting ||
          p == SshPhase.unreachable || p == SshPhase.failed).toList(),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_regression_test.dart`
Expected: 编译失败（`ioGuard` 不是 `SshClientFactory` 的命名参数）。

- [ ] **Step 3: factory 退化为纯池**

`client/lib/services/ssh/ssh_client_factory.dart`：
- 构造参数 `SshConnectionGate? connectionGate` → `SshIoGuard ioGuard = _noopGuard`；删 `:108` 的 `connectionGate = connectionGate ?? SshConnectionGate(),`；删 `:145` 的 `final SshConnectionGate connectionGate;`，新增 `final SshIoGuard _ioGuard;` 并在初始化列表赋值 `_ioGuard = ioGuard`。
- 文件底部加 `void _noopGuard(String profileId) {}`。
- import `ssh_connection_gate.dart` 改为 `ssh_home_connectivity_state.dart`（re-export 了 `SshIoGuard`）；若其它 `part` 仍需要 gate 类型，保留 import。
- `storageFor`（`:224-252`）：删 `allowDialWhenDown` 参数与 `if (allowDialWhenDown) connectionGate.allowNextDial(...)` 分支；开头一行改为 `_ioGuard(profile.id);`；删 `connectionGate.markConnecting` / `markUp` / catch 里的 `markDown`。`_workerStoragePool.clientFor` 原样。
- `openMemberTransport`（`:258-301`）：`connectionGate.beforeIo` → `_ioGuard(profile.id)`；删 `markUp` / `markDown`；删 `_GatedMemberTransport(gate: ...)` 包装，直接 `return SshWorkerDirectMemberTransport(...)` / `SshWorkerLeaseMemberTransport(...)`。
- `ensureStorageConnected`（`:308-328`）：删 `bool allowDialWhenDown = false` 参数与其向 `storageFor` 的传递。
- `disconnectProfile`（`:479-488`）：删 `if (reason == userDisconnect) connectionGate.suspend(...)`。
- `_close()`（`:609-615`）：删 `connectionGate.dispose();`（gate 现在归 supervisor 的 `dispose()`）。
- 删除文件末尾整个 `_GatedMemberTransport` 类（`:771-827`）。
- `app_shell.dart:985`：`await sshClientFactory.connectionGate.waitUntilUp(error.profileId);` → `await sshConnectivityGate.waitUntilUp(error.profileId);`（共享 gate 变量在 `:967` 声明，作用域覆盖 `:983`）。

`client/lib/services/ssh/ssh_client_factory_narrow_operations.dart`（`:57-104`）与 `client/lib/services/ssh/ssh_client_factory_legacy_storage.dart`（`:49-100`）：所有 `connectionGate.beforeIo(profile.id)` → `_ioGuard(profile.id)`（`part` 可访问主文件私有字段）；删所有 `connectionGate.markConnecting` / `markUp` / `markDown`。**必须保留 `beforeIo` 等价的那一行**，否则 `SshProfileDownException` 契约断裂。

- [ ] **Step 4: coordinator 注入 gate + dial**

`client/lib/services/ssh/ssh_profile_connection_coordinator.dart`：
- 构造参数加 `required SshConnectionGate gate` 与 `required Future<void> Function(SshProfile) dial`；字段 `final SshConnectionGate _gate;`、`final Future<void> Function(SshProfile) _dial;`。
- 全局替换 `_factory.connectionGate` → `_gate`（`:60,61,123,135,181,202,203,232,326,392,416,560`）。
- 删 `final Map<String, Future<void>> _storageReconnects = {};`、整个 `reconnectStorage` 方法（`:538-556`）、`dispose()` 里的 `_storageReconnects.clear();`。
- `userConnect`（`:118-130`）：`await _factory.ensureStorageConnected(profile, timeout: timeout, allowDialWhenDown: true);` → `await _dial(profile);`。
- `_runReconnect`（`:439`）：`await reconnectStorage(profile);` → `await _dial(profile);`。
- `dispose()`：`_factory.connectionGate.onWaiter = null;` → `_gate.onWaiter = null;`。

`client/lib/services/ssh/ssh_home_connectivity_supervisor.dart`（Task 2 已建）：在构造 coordinator 时补两个参数：

```dart
_coordinator = SshProfileConnectionCoordinator(
  factory: factory,
  events: events,
  profileResolver: profileResolver,
  gate: _gate,
  dial: dial,               // supervisor 的单飞 dial（super 的方法，构造体内可引用）
  policy: policy,
  ...其余不变,
);
```

> `dial` 是实例方法，在构造体内作为 tear-off 引用是合法的（不访问未初始化字段之外的东西）。若 analyzer 报 `late` 初始化问题，改为 `dial: (p) => dial(p)`。

**coordinator 测试的机械改动**（`ssh_profile_connection_coordinator_test.dart` / `..._reconnect_test.dart`）：harness 构造 coordinator 时补 `gate: <独立 SshConnectionGate()>` 与 `dial: (p) => factory.ensureStorageConnected(p)`；`addTearDown` 里补 `gate.dispose()`。这些 harness 目前不传 gate，改后必须显式传，因为 factory 已无 `connectionGate` 字段。

`ssh_connection_gate_factory_test.dart`：把 `final gate = SshConnectionGate(); _factory(launcher, gate)` 里的 factory 构造改为 `ioGuard: gate.beforeIo`；涉及 `allowDialWhenDown` 的用例（`:78`）改为先 `gate.markConnecting(_profile.id)` 再调 `ensureStorageConnected(_profile)`；断言 `gate.isUp` 改为手动 `gate.markUp` 或改断言为「factory 不再改 gate 状态」。

- [ ] **Step 5: Task 2 的 supervisor 测试 harness 一行改动**

`client/test/services/ssh/ssh_home_connectivity_supervisor_test.dart` 的 `_Harness`：`connectionGate: gate,` → `ioGuard: gate.beforeIo,`。其余不变。

- [ ] **Step 6: 跑测试 + analyze**

Run:
```
cd client && dart run tool/run_tests.dart \
  test/services/ssh/ssh_home_connectivity_regression_test.dart \
  test/services/ssh/ssh_home_connectivity_supervisor_test.dart \
  test/services/ssh/ssh_client_factory_worker_test.dart \
  test/services/ssh/ssh_connection_gate_factory_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_reconnect_test.dart \
  test/services/ssh/storage_failure_test.dart \
  test/services/ssh/ssh_connection_failure_test.dart \
  test/services/event/event_transport_client_test.dart \
  test/services/event/event_transport_controller_test.dart \
  test/services/storage/storage_failure_test.dart
```
Expected: 全部 `All tests passed!`；回归用例 `dials == 1` 且 `phases.last == up`。

Run: `cd client && flutter analyze lib/services/ssh test/services/ssh`
Expected: `No issues found!`。

- [ ] **Step 7: 提交**

```bash
git commit -m "refactor(ssh): move dial ownership into the supervisor; factory becomes a pure pool" -- \
  <按 git status --short 显式列出本任务全部改动文件>
```

---

### Task 5: 收敛 app_shell 编排 + 热恢复/切 home + 全量验证

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart`（`profileEdited` / `activateHome` 补 dial 调用）
- Test: 全量验证

- [ ] **Step 1: 写失败测试（热恢复 hold 不回归）**

在 `client/test/services/ssh/ssh_home_connectivity_supervisor_test.dart` 追加：

```dart
test('holdPlaneRebind keeps the gate on the connecting page until released',
    () async {
  final h = _Harness();
  addTearDown(h.dispose);
  h.supervisor.activateHome(_profile.id);
  final states = <SshHomeConnectivityState>[];
  final sub = h.supervisor.changes.listen(states.add);
  addTearDown(sub.cancel);

  h.gate.markUp(_profile.id);
  h.supervisor.observeProfile(_profile.id);
  await waitUntil(() => states.isNotEmpty && states.last.isUp);

  h.supervisor.holdPlaneRebind();
  await waitUntil(() => states.last.planeRebinding);
  expect(states.last.phase, SshPhase.up);
  // app_shell 的订阅把 planeRebinding 投影成 markPlaneRebinding() →
  // StartupGate 停在进度页。
  expect(states.last.planeRebinding, isTrue);

  h.supervisor.releasePlaneRebind();
  await waitUntil(() => !states.last.planeRebinding);
  expect(states.last.phase, SshPhase.up);
});

test('activateHome latches the abandoned profile and observes the new one',
    () async {
  final h = _Harness();
  addTearDown(h.dispose);
  h.supervisor.activateHome(_profile.id);
  expect(h.supervisor.shouldPersistRetry(_profile.id), isTrue);

  h.supervisor.activateHome('other');
  expect(h.supervisor.shouldPersistRetry(_profile.id), isFalse);
  expect(h.supervisor.shouldPersistRetry('other'), isTrue);
});
```

- [ ] **Step 2: 跑测试确认失败或已通过**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_supervisor_test.dart`
Expected: 若 Task 2 的实现已满足则全绿（这两个用例是对已有行为的锁）；若失败，按 Step 3 补齐实现。**不得**为了让测试通过而放宽断言。

- [ ] **Step 3: supervisor 的 `profileEdited` / `activateHome` 补 dial**

`client/lib/services/ssh/ssh_home_connectivity_supervisor.dart`：
- `activateHome(String? id)`：设好 `_activeHomeId` 后，若 `id != null` 且 `profileResolver(id)` 非 null，则 `unawaited(dial(profile))`（单飞，重复调用安全）。
- `profileEdited(id)`：`_gate.resume(id)` → `_coordinator.resetReconnectAttempts(id)` → `unawaited(dial(profile))`；**绝不**置 `failed`（保住 `9c82e0c45`）。
- 保持 `dispose()` 里 `_gate.dispose()` 与 `_coordinator.dispose()` 的顺序。

- [ ] **Step 4: app_shell 收敛编排**

- 删 `homeProfileWatchSub`（`:3992-4007`）里的 `cubit.rebind(...)` + `unawaited(cubit.retryNow())`，改为：

```dart
final profile = sshProfileById(id);
sshHomeConnectivity.profileEdited(id); // 内部已重新 dial 当前 profile
cubit.rebind(profileId: id, host: profile?.host, port: profile?.port);
```

- 删 boot 的 `if (isSshHome && !initialHome.reachable) { ...restartReconnect(homeProfileId); }`（`:3978-3980`），改为一次 `sshHomeConnectivity.activateHome(homeProfileId);`（无论 reachable 与否，supervisor 自己按 pool 状态推导）。
- `switchHomeTarget`（`:4283-4344`）：删 `await sshProfileConnectionCoordinator.userDisconnect(previousSshProfileId)` / `resetReconnectAttempts(previousSshProfileId)` / `cubit.retryNow()` 三段，收敛为：

```dart
await sshHomeConnectivity.activateHome(nextSshProfileId);
```

  非 SSH home 时 `activateHome(null)`。`cubit.rebind(...)` 保留（更新展示用的 host/port）。
- `homeConnectionCubit` 的 `connect` 回调（`:3902-3918`）里 `sshProfileConnectionCoordinator.restartReconnect(id)` → `sshHomeConnectivity.activateHome(id)`；`cancelRetry` / `resumeRetry` 同理改为 `sshHomeConnectivity.userDisconnect(id)` / `resumeRetries(id)`。
- 确认 `waitForSshProfileRecovery` 已在 Task 3 改为 `awaitAvailable`。
- 确认 `main.dart:641` 已改为 `shell.supervisor.coordinator`。
- `startup_gate.dart` / `ssh_home_disconnected_banner.dart` **不改**。

- [ ] **Step 5: 全量验证（本增量唯一一次全量）**

Run: `cd client && flutter analyze`
Expected: `No issues found!`

Run: `cd client && dart run tool/run_tests.dart`
Expected: 全绿（后台执行，用 `dart run tool/test_status.dart --tail` 跟踪；`--reuse` 可跳过当前 clean HEAD 已绿的全量）。若 `sqlite3` 原生库下载失败（已知环境证书握手问题，**非本改动引入**），记录为环境阻塞并改用定向覆盖，报告里如实说明：

```
cd client && dart run tool/run_tests.dart \
  test/services/ssh test/cubits test/pages/startup_gate_test.dart \
  test/widgets/ssh test/services/storage/storage_failure_test.dart \
  test/services/event
```

定向回归（必跑）：
```
cd client && dart run tool/run_tests.dart \
  test/services/ssh/ssh_home_connectivity_regression_test.dart \
  test/services/ssh/ssh_home_connectivity_supervisor_test.dart \
  test/services/ssh/ssh_home_connectivity_state_test.dart \
  test/services/ssh/ssh_profile_connection_coordinator_reconnect_test.dart \
  test/cubits/ssh_connection_cubit_test.dart \
  test/pages/startup_gate_test.dart
```
Expected: 全部 `All tests passed!`。

- [ ] **Step 6: 提交 + 设计文档状态更新**

```bash
git commit -m "refactor(ssh): collapse connection orchestration into the supervisor" -- \
  <按 git status --short 显式列出本任务全部改动文件>
```

```bash
git commit -m "docs(ssh): mark the connectivity supervisor design as implemented" -- \
  docs/superpowers/specs/2026-11-12-ssh-home-connectivity-supervisor-design.md
```
（把该文档头部 `- 状态：待审阅` 改为 `- 状态：已实施`。）

---

## 自检（写计划时已执行）

- **Spec 覆盖**：五条不变量分别落在 Task 1（`up()` 原子清 failure，不变量 3）、Task 2/4（`dial` 单飞，不变量 1；`_onPoolChanged` 以 lease 就绪为 `storageLive`，不变量 2）、Task 2（`shouldPersistRetry` 读 supervisor 自身状态，不变量 4）、Task 2/5（`profileEdited` 不进 `failed`，不变量 5）。投影表由 Task 3 的 `_project` + app_shell 单一订阅覆盖；失败分类、plane-scoped 退役、penalty 退避由保留的 coordinator/策略覆盖；热恢复由 Task 3/5 的 `onConnected` 保留 + `planeRebinding` 覆盖。
- **类型一致性**：`SshHomeConnectivitySupervisor` 构造签名在 Task 2–5 **完全一致**；`SshConnectivitySource.changes` / `stateFor` 与 `TestSshConnectivity` 同名同签名；`SshIoGuard` 只在 `ssh_connection_gate.dart` 定义、由 `ssh_home_connectivity_state.dart` re-export；`supervisor.dial` 与 coordinator 的 `dial` 参数同为 `Future<void> Function(SshProfile)`；`SshPhase.up` 与 `SshConnectionGateState.up` 不混用。
- **占位符扫描**：无 TBD/TODO；所有新文件给出完整代码；修改类步骤给出确切行号与替换内容；测试给出完整用例代码。唯一「按 `git status` 列出文件」是提交纪律（Global Constraints 要求并发改动下显式列出），不是实现占位。
- **已修正的草稿缺陷**：①Task 2 测试原本靠 `gate.markUp()` 触发，但 gate 无 `onUp` 回调且 supervisor 不订阅它 → 改为显式 `observeProfile` 触发（D3）；②草稿曾让 supervisor 在 Task 5 改构造签名 → 改为全程稳定（D1）；③草稿的 `_FakeClient` 未定义 → 改用构造注入的 `dialProfile` 计数 lambda；④草稿低估了 ~16 个 cubit 测试的迁移 → 引入 `SshConnectivitySource` + `TestSshConnectivity`（D4）并点名必须改的 monitor 操纵位点；⑤发现 factory 无 gate 后无人抛 `SshProfileDownException` → 用 `SshIoGuard` 保留契约（D2，已同步进 spec）。
- **已知环境风险**：全量套件可能受 `sqlite3` 原生库下载阻塞（非本改动引入），Task 5 已给出定向回退与如实报告要求。
