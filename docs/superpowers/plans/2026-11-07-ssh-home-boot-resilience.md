# SSH Home Boot Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop an unreachable/slow SSH home from hanging the splash for minutes; fail fast with visible status and recovery, keep retrying in the background, and hot-recover once reachable.

**Architecture:** Introduce a `HomeConnectionCubit` (navigation-grade status: connecting / connected / unreachable / reconnecting) driven by a single bounded connect attempt (TCP pre-probe ≤2s + SSH resolve ≤8s). `StartupGate` branches on this status; `bootstrapAppData` no longer awaits remote-heavy steps before `markAppReady` — it gates them on `connected` and replays them once on reconnect (hot recovery). The existing `SshProfileConnectionCoordinator` provides background retry and cancel/resume; the storage pool's existing single-flight/`_openings` semantics are left untouched.

**Tech Stack:** Flutter, `flutter_bloc` (Cubit + Equatable), `dart:io` (`Socket`), existing `RuntimeContextRegistry` / `RuntimeContextResolver` / `SshClientFactory` / `SshProfileConnectionCoordinator`.

## Global Constraints

- 禁止直接运行 `flutter test`；统一用 `cd client && dart run tool/run_tests.dart <path/options>`。
- 提交前跑 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`（0 errors）。
- 路径必须走注入的 `HomeStorage` / `RuntimeContext`，禁止 `Directory.current`。
- 用户可见文案只改 `client/lib/l10n/app_en.arb` 与 `client/lib/l10n/app_zh.arb`（并 `flutter gen-l10n`）。
- 诊断日志用 `AppLogger`，禁止 `print`；凭据永不写入远端 profile，也不进入日志。
- 每个任务结束前单独 commit（`feat:` / `test:` / `refactor:` 前缀）。
- 连接页/日志只暴露 `host:port`、错误**类别**、尝试次数；不含凭据、私钥、文件内容。
- 不改存储池 `clientFor` 的去重/作废语义；不改 SSH 协议 / worker / PTY。

## File Structure

| File | Responsibility |
|---|---|
| `client/lib/services/ssh/tcp_reachability_probe.dart` (new) | 廉价 TCP 连通性探活（可注入 fake） |
| `client/lib/services/storage/home_connect_attempt.dart` (new) | 一次有界 home 连接尝试：探活 → 有界解析 → 产出 `HomeConnectResult` |
| `client/lib/cubits/home_connection_cubit.dart` (new) | home 连接状态机 + 三个动作 |
| `client/lib/pages/startup_gate.dart` (modify) | 按 `HomeConnectionCubit` 状态分支 |
| `client/lib/pages/remote_connections_page.dart` (modify) | 连接状态卡 + 三动作（复用目标列表） |
| `client/lib/app/app_shell.dart` (modify) | 首次有界尝试、boot 解耦、热恢复、协调器接线 |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` (modify) | 连接页文案 |

---

### Task 1: 有界 home 连接尝试（探活 + 结果对象）

**Files:**
- Create: `client/lib/services/ssh/tcp_reachability_probe.dart`
- Create: `client/lib/services/storage/home_connect_attempt.dart`
- Test: `client/test/services/storage/home_connect_attempt_test.dart`

**Interfaces:**
- Produces:
  - `abstract class TcpReachabilityProbe { Future<bool> isReachable(String host, int port, {required Duration timeout}); }`
  - `class SocketTcpReachabilityProbe implements TcpReachabilityProbe`
  - `enum HomeErrorKind { tcpUnreachable, sshTimeout, authFailed, transportError, unknown }`
  - `class HomeConnectResult { final bool reachable; final RuntimeContext? context; final HomeErrorKind? errorKind; }` with `.connected(ctx)` / `.unreachable(kind, {RuntimeContext? context})`（不可达时仍携带**缓存路径**上下文，供构建壳使用）
  - `class HomeConnectAttempt { HomeConnectAttempt({required TcpReachabilityProbe probe, required Future<RuntimeContext> Function() resolve, required Future<RuntimeContext> Function() cacheContext, required SshProfile? Function(String id) profileById, Duration tcpTimeout, Duration connectBudget}); Future<HomeConnectResult> run(String profileId); }`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/storage/home_connect_attempt_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_auth_type.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/tcp_reachability_probe.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

class _FakeProbe implements TcpReachabilityProbe {
  _FakeProbe(this.reachable);
  final bool reachable;
  int calls = 0;
  @override
  Future<bool> isReachable(String host, int port, {required Duration timeout}) async {
    calls++;
    return reachable;
  }
}

SshProfile _profile() => SshProfile(
      id: 'p1', name: 'p1', host: '10.0.0.9', port: 22, username: 'u',
      authType: SshAuthType.privateKey, createdAt: 0, updatedAt: 0,
    );

RuntimeContext _ctx({required bool fromCache}) => RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: throw UnimplementedError(),
      home: '/h', cwd: '/h', appDataRoot: '/app', paths: const AppPaths('/app'),
      pathsFromCache: fromCache,
    );

void main() {
  test('tcp unreachable short-circuits without resolving', () async {
    final probe = _FakeProbe(false);
    var resolved = 0;
    final attempt = HomeConnectAttempt(
      probe: probe,
      resolve: () async { resolved++; return _ctx(fromCache: false); },
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.tcpUnreachable);
    expect(resolved, 0);
  });

  test('reachable + cached fallback reports unreachable transportError', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () async => _ctx(fromCache: true),
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.transportError);
  });

  test('reachable + live resolve reports connected with context', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () async => _ctx(fromCache: false),
      profileById: (_) => _profile(),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isTrue);
    expect(result.context, isNotNull);
  });

  test('resolve over budget reports sshTimeout', () async {
    final attempt = HomeConnectAttempt(
      probe: _FakeProbe(true),
      resolve: () => Completer<RuntimeContext>().future,
      profileById: (_) => _profile(),
      connectBudget: const Duration(milliseconds: 20),
    );
    final result = await attempt.run('p1');
    expect(result.reachable, isFalse);
    expect(result.errorKind, HomeErrorKind.sshTimeout);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/home_connect_attempt_test.dart`
Expected: FAIL — `tcp_reachability_probe.dart` / `home_connect_attempt.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/services/ssh/tcp_reachability_probe.dart
import 'dart:io';

/// Fast reachability check before attempting a full SSH connect.
abstract class TcpReachabilityProbe {
  Future<bool> isReachable(String host, int port, {required Duration timeout});
}

class SocketTcpReachabilityProbe implements TcpReachabilityProbe {
  const SocketTcpReachabilityProbe();

  @override
  Future<bool> isReachable(String host, int port, {required Duration timeout}) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
```

```dart
// client/lib/services/storage/home_connect_attempt.dart
import 'dart:async';

import '../../models/ssh_profile.dart';
import '../ssh/tcp_reachability_probe.dart';
import 'runtime_context.dart';

enum HomeErrorKind { tcpUnreachable, sshTimeout, authFailed, transportError, unknown }

class HomeConnectResult {
  const HomeConnectResult.connected(RuntimeContext this.context)
      : reachable = true,
        errorKind = null;
  const HomeConnectResult.unreachable(HomeErrorKind this.errorKind, {this.context})
      : reachable = false;

  final bool reachable;
  final RuntimeContext? context;
  final HomeErrorKind? errorKind;
}

class HomeConnectAttempt {
  HomeConnectAttempt({
    required TcpReachabilityProbe probe,
    required Future<RuntimeContext> Function() resolve,
    required Future<RuntimeContext> Function() cacheContext,
    required SshProfile? Function(String profileId) profileById,
    this.tcpTimeout = const Duration(seconds: 2),
    this.connectBudget = const Duration(seconds: 8),
  })  : _probe = probe,
        _resolve = resolve,
        _cacheContext = cacheContext,
        _profileById = profileById;

  final TcpReachabilityProbe _probe;
  final Future<RuntimeContext> Function() _resolve;
  final Future<RuntimeContext> Function() _cacheContext;
  final SshProfile? Function(String profileId) _profileById;
  final Duration tcpTimeout;
  final Duration connectBudget;

  Future<HomeConnectResult> run(String profileId) async {
    final profile = _profileById(profileId);
    if (profile == null) {
      return HomeConnectResult.unreachable(
        HomeErrorKind.unknown,
        context: await _cacheContext(),
      );
    }
    final tcpOk = await _probe.isReachable(
      profile.host,
      profile.port,
      timeout: tcpTimeout,
    );
    if (!tcpOk) {
      return HomeConnectResult.unreachable(
        HomeErrorKind.tcpUnreachable,
        context: await _cacheContext(),
      );
    }
    try {
      final ctx = await _resolve().timeout(connectBudget);
      if (ctx.pathsFromCache) {
        return HomeConnectResult.unreachable(
          HomeErrorKind.transportError,
          context: ctx,
        );
      }
      return HomeConnectResult.connected(ctx);
    } on TimeoutException {
      return HomeConnectResult.unreachable(
        HomeErrorKind.sshTimeout,
        context: await _cacheContext(),
      );
    } on Object {
      return HomeConnectResult.unreachable(
        HomeErrorKind.transportError,
        context: await _cacheContext(),
      );
    }
  }
}
```

> `cacheContext` 由 `runtimeContextRegistry.ensureHomeCached()` 提供（Task 4 新增）：只用已保存的 `lastHome/lastAppDataRoot` 构造缓存上下文，**不发起任何网络连接**。

> If `RuntimeContext.native(...)` has a different constructor signature, adapt the test helper to the real one; do not change the production types.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/home_connect_attempt_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/ssh/tcp_reachability_probe.dart client/lib/services/storage/home_connect_attempt.dart client/test/services/storage/home_connect_attempt_test.dart
git commit -m "feat(storage): add bounded home connect attempt with tcp probe"
```

---

### Task 2: `HomeConnectionCubit` 状态机与三动作

**Files:**
- Create: `client/lib/cubits/home_connection_cubit.dart`
- Test: `client/test/cubits/home_connection_cubit_test.dart`

**Interfaces:**
- Consumes: `HomeConnectResult`, `HomeErrorKind` (Task 1).
- Produces:
  - `enum HomeConnectionStatus { connecting, connected, unreachable, reconnecting }`
  - `class HomeConnectionState extends Equatable { HomeConnectionStatus status; String? profileId; String? host; int? port; int attempt; HomeErrorKind? lastErrorKind; bool get canCancelRetry; bool get canRetryNow; }`
  - `class HomeConnectionCubit extends Cubit<HomeConnectionState>` with:
    - ctor `HomeConnectionCubit({required Future<HomeConnectResult> Function() connect, required Future<void> Function() cancelRetry, required Future<void> Function() resumeRetry, required void Function() onConnected})`
    - `Future<void> connectOnce()` — performs one attempt (status `connecting` → `connected`/`unreachable`), invokes `onConnected` on success.
    - `Future<void> retryNow()` — status `connecting`, resets attempt, calls `connectOnce`.
    - `Future<void> cancelRetry()` — status `unreachable`, calls `cancelRetry` callback.
    - `void markBackgroundAttempt(int attempt)` — status `reconnecting`, updates attempt.
    - `void markReconnected()` — status `connected`, invokes `onConnected`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/home_connection_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

RuntimeContext _ctx() => RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: throw UnimplementedError(),
      home: '/h', cwd: '/h', appDataRoot: '/app', paths: const AppPaths('/app'),
    );

void main() {
  test('connectOnce success transitions to connected and fires onConnected', () async {
    var connected = 0;
    final cubit = HomeConnectionCubit(
      connect: () async => HomeConnectResult.connected(_ctx()),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () => connected++,
    );
    await cubit.connectOnce();
    expect(cubit.state.status, HomeConnectionStatus.connected);
    expect(connected, 1);
  });

  test('connectOnce failure transitions to unreachable and does not fire onConnected', () async {
    var connected = 0;
    final cubit = HomeConnectionCubit(
      connect: () async => const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () => connected++,
    );
    await cubit.connectOnce();
    expect(cubit.state.status, HomeConnectionStatus.unreachable);
    expect(cubit.state.lastErrorKind, HomeErrorKind.tcpUnreachable);
    expect(connected, 0);
  });

  test('cancelRetry stops retries and keeps unreachable; retryNow resets attempt', () async {
    var cancelled = 0;
    var resume = 0;
    final cubit = HomeConnectionCubit(
      connect: () async => const HomeConnectResult.unreachable(HomeErrorKind.sshTimeout),
      cancelRetry: () async => cancelled++,
      resumeRetry: () async => resume++,
      onConnected: () {},
    );
    await cubit.connectOnce();
    await cubit.cancelRetry();
    expect(cancelled, 1);
    expect(cubit.state.status, HomeConnectionStatus.unreachable);
    await cubit.retryNow();
    expect(resume, 1);
    expect(cubit.state.attempt, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/home_connection_cubit_test.dart`
Expected: FAIL — `home_connection_cubit.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/cubits/home_connection_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/storage/home_connect_attempt.dart';

enum HomeConnectionStatus { connecting, connected, unreachable, reconnecting }

class HomeConnectionState extends Equatable {
  const HomeConnectionState({
    this.status = HomeConnectionStatus.connecting,
    this.profileId,
    this.host,
    this.port,
    this.attempt = 0,
    this.lastErrorKind,
  });

  final HomeConnectionStatus status;
  final String? profileId;
  final String? host;
  final int? port;
  final int attempt;
  final HomeErrorKind? lastErrorKind;

  bool get canCancelRetry => status == HomeConnectionStatus.reconnecting;
  bool get canRetryNow =>
      status == HomeConnectionStatus.unreachable ||
      status == HomeConnectionStatus.reconnecting;

  HomeConnectionState copyWith({
    HomeConnectionStatus? status,
    String? profileId,
    String? host,
    int? port,
    int? attempt,
    HomeErrorKind? lastErrorKind,
  }) =>
      HomeConnectionState(
        status: status ?? this.status,
        profileId: profileId ?? this.profileId,
        host: host ?? this.host,
        port: port ?? this.port,
        attempt: attempt ?? this.attempt,
        lastErrorKind: lastErrorKind ?? this.lastErrorKind,
      );

  @override
  List<Object?> get props => [status, profileId, host, port, attempt, lastErrorKind];
}

class HomeConnectionCubit extends Cubit<HomeConnectionState> {
  HomeConnectionCubit({
    required Future<HomeConnectResult> Function() connect,
    required Future<void> Function() cancelRetry,
    required Future<void> Function() resumeRetry,
    required void Function() onConnected,
  })  : _connect = connect,
        _cancelRetry = cancelRetry,
        _resumeRetry = resumeRetry,
        _onConnected = onConnected,
        super(const HomeConnectionState());

  final Future<HomeConnectResult> Function() _connect;
  final Future<void> Function() _cancelRetry;
  final Future<void> Function() _resumeRetry;
  final void Function() _onConnected;

  Future<void> connectOnce() async {
    emit(state.copyWith(status: HomeConnectionStatus.connecting));
    final result = await _connect();
    if (isClosed) return;
    if (result.reachable) {
      emit(state.copyWith(
        status: HomeConnectionStatus.connected,
        attempt: 0,
        lastErrorKind: null,
      ));
      _onConnected();
    } else {
      emit(state.copyWith(
        status: HomeConnectionStatus.unreachable,
        lastErrorKind: result.errorKind,
      ));
    }
  }

  Future<void> retryNow() async {
    emit(state.copyWith(attempt: 0, status: HomeConnectionStatus.connecting));
    await _resumeRetry();
    await connectOnce();
  }

  Future<void> cancelRetry() async {
    await _cancelRetry();
    if (isClosed) return;
    emit(state.copyWith(status: HomeConnectionStatus.unreachable));
  }

  void markBackgroundAttempt(int attempt) {
    if (isClosed) return;
    emit(state.copyWith(
      status: HomeConnectionStatus.reconnecting,
      attempt: attempt,
    ));
  }

  void markReconnected() {
    if (isClosed) return;
    emit(state.copyWith(status: HomeConnectionStatus.connected, attempt: 0));
    _onConnected();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/home_connection_cubit_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + Commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 errors.

```bash
git add client/lib/cubits/home_connection_cubit.dart client/test/cubits/home_connection_cubit_test.dart
git commit -m "feat(cubit): add HomeConnectionCubit state machine"
```

---

### Task 3: `StartupGate` 分支 + 连接状态卡 + l10n

**Files:**
- Modify: `client/lib/pages/startup_gate.dart`
- Modify: `client/lib/pages/remote_connections_page.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/startup_gate_test.dart` (extend), `client/test/pages/remote_connections_status_test.dart` (new)

**Interfaces:**
- Consumes: `HomeConnectionCubit` / `HomeConnectionState` (Task 2).
- Produces: `StartupGate` reads `context.watch<HomeConnectionCubit>()`; `RemoteConnectionsPage` renders a status card when status is `unreachable`/`reconnecting`.

- [ ] **Step 1: Add l10n keys** to `app_en.arb` and `app_zh.arb`:

```json
"homeConnectionUnreachable": "Can't reach {host}:{port}",
"@homeConnectionUnreachable": {"placeholders": {"host": {"type": "String"}, "port": {"type": "int"}}},
"homeConnectionRetrying": "Retrying… attempt {count}",
"@homeConnectionRetrying": {"placeholders": {"count": {"type": "int"}}},
"homeConnectionCancelRetry": "Stop retrying",
"homeConnectionRetryNow": "Retry now",
"homeConnectionSwitch": "Switch connection",
"homeConnectionErrorTcp": "Network unreachable",
"homeConnectionErrorTimeout": "Connection timed out",
"homeConnectionErrorAuth": "Authentication failed",
"homeConnectionErrorTransport": "Connection error",
"homeConnectionErrorUnknown": "Unknown error"
```

(zh 对应中文；`flutter gen-l10n` 后提交生成文件。)

- [ ] **Step 2: Wire `StartupGate`** — add a branch after the existing `isLoading` check, before `requiresSshProfileSetup`:

```dart
final homeConn = context.watch<HomeConnectionCubit>().state;
...
if (homeConn.status == HomeConnectionStatus.unreachable ||
    homeConn.status == HomeConnectionStatus.reconnecting ||
    homeConn.status == HomeConnectionStatus.connecting) {
  return const RemoteConnectionsPage();
}
```

> Order matters: keep `requiresSshProfileSetup` (no profiles) first; only show the status-driven page when a profile exists. Use the precedence in the spec §3.

- [ ] **Step 3: Add the status card** at the top of `RemoteConnectionsPage`'s body:

```dart
Widget build(BuildContext context) {
  final homeConn = context.watch<HomeConnectionCubit>().state;
  final showStatus = homeConn.status == HomeConnectionStatus.unreachable ||
      homeConn.status == HomeConnectionStatus.reconnecting;
  final body = SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showStatus) _ConnectionStatusCard(state: homeConn),
        const SizedBox(height: 12),
        const SshProfilesSection(showRemoteConfig: false),
      ],
    ),
  );
  if (embedded) return body;
  return Scaffold(body: body);
}
```

`_ConnectionStatusCard` shows `无法连接 host:port`, `第 N 次重试` (when reconnecting), an error-kind label, and three buttons wired to `context.read<HomeConnectionCubit>().cancelRetry()/retryNow()/switchConnection()` (switch = scroll to list / no-op if list already visible; a `ScrollController` is optional).

- [ ] **Step 4: Widget tests** — assert:
  - `unreachable` → status card visible with host/port + 「继续重试」.
  - tapping 「取消重试」 calls `cancelRetry`.
  - `connected` → `child` shown (no status card).

- [ ] **Step 5: Run + analyze**

Run: `cd client && dart run tool/run_tests.dart test/pages/startup_gate_test.dart test/pages/remote_connections_status_test.dart`
Then: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/startup_gate.dart client/lib/pages/remote_connections_page.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart client/test/pages/startup_gate_test.dart client/test/pages/remote_connections_status_test.dart
git commit -m "feat(ui): show home connection status and recovery actions"
```

---

### Task 4: boot 解耦 + 热恢复（`app_shell.dart`）

**Files:**
- Modify: `client/lib/app/app_shell.dart`:
  - `:1115-1162`（构造 registry 与 homeStorage）
  - `:3197-3203`（`reconnectHomeSshIfNeeded`）
  - `:3231-3350`（`bootstrapAppData`）

**Interfaces:**
- Consumes: `HomeConnectionCubit`, `HomeConnectAttempt`, `TcpReachabilityProbe`, `SocketTcpReachabilityProbe` (Tasks 1–2).
- Produces: `buildAppShell` seeds the cubit; `bootstrapAppData` gates remote steps on `connected`; `runRemoteBootAfterConnect()` is idempotent.

- [ ] **Step 1: First bounded attempt + cached context (no network)**

在 `runtime_context_registry.dart` 新增 `ensureHomeCached()`（只用已保存 `lastHome/lastAppDataRoot` 构造缓存上下文、不连接），并在 `runtime_context_resolver.dart` 复用现有 `_resolveSshFromCache` 逻辑暴露一个 `resolveCached(...)`：

```dart
// RuntimeContextRegistry
Future<RuntimeContext> ensureHomeCached() async {
  final target = _homeTarget;
  await _withTargetOperation(target.id, () async {
    _home = await _resolver.resolveCached(
      target,
      sshProfile: target.sshProfileId == null
          ? null
          : _sshProfileById?.call(target.sshProfileId!),
    );
  });
  return home();
}
```

在 `:1139-1143` 用有界尝试替换无界的 `await runtimeContextRegistry.ensureHome()`：

```dart
final homeAttempt = HomeConnectAttempt(
  probe: const SocketTcpReachabilityProbe(),
  resolve: () async {
    await runtimeContextRegistry.ensureHome();
    return runtimeContextRegistry.home();
  },
  cacheContext: () => runtimeContextRegistry.ensureHomeCached(),
  profileById: sshProfileById,
);
final homeProfileId = defaultTargetResolver().sshProfileId;
final initialHome = homeProfileId == null
    ? HomeConnectResult.unreachable(
        HomeErrorKind.unknown,
        context: await runtimeContextRegistry.ensureHomeCached(),
      )
    : await homeAttempt.run(homeProfileId);
final homeCtx = initialHome.context ?? await runtimeContextRegistry.ensureHomeCached();
```

> `HomeConnectResult.unreachable` 已携带缓存上下文，所以 `homeCtx` 无需等待任何网络即可得到；下方 `:1143` 起对 `homeCtx` 的既有使用保持不变。

- [ ] **Step 2: Construct + seed the cubit**

Before the shell widget tree is built, construct:

```dart
final homeConnectionCubit = HomeConnectionCubit(
  connect: () => homeAttempt.run(homeProfileId!),
  cancelRetry: () => sshProfileConnectionCoordinator.userDisconnect(homeProfileId!),
  resumeRetry: () => sshProfileConnectionCoordinator.userConnect(profileById(homeProfileId!)!),
  onConnected: () => unawaited(runRemoteBootAfterConnect()),
);
if (homeProfileId != null) {
  // seed synchronously from the first attempt result
  homeConnectionCubit.markInitial(initialHome); // add a method that emits connected/unreachable without re-connecting
}
```

Provide it via `BlocProvider.value` wherever `StartupGate` lives. (Add `markInitial(HomeConnectResult)` to the cubit in Task 2 if not present.)

- [ ] **Step 3: Extract idempotent remote boot**

Move the remote-heavy body of `bootstrapAppData` (the `if (!indexReady && isRemoteWorkPlane) { await homeIndexPrefetch; await bootstrapHomeIndex; ... }` + `warmAuxiliaryData`) into:

```dart
var remoteBootStarted = false;
Future<void> runRemoteBootAfterConnect() async {
  if (remoteBootStarted) return;
  remoteBootStarted = true;
  ... // bootstrapHomeIndex + warmAuxiliaryData, with existing try/catch/logging
}
```

- [ ] **Step 4: Gate `bootstrapAppData` on status**

```dart
final homeStatus = homeConnectionCubit.state.status;
if (homeStatus == HomeConnectionStatus.connected) {
  await runRemoteBootAfterConnect();
}
// when unreachable: skip; markAppReady still runs.
boot('bootstrapAppData index ready ...');
...
bootstrapCubit?.markAppReady(showOnboardingWizard: showOnboarding);
```

Also move `await reconnectHomeSshIfNeeded()` off the splash path (fire-and-forget after `markAppReady`), or let it run only when `connected`.

- [ ] **Step 5: Smoke + analyze**

Run: `cd client && dart run tool/run_tests.dart test/smoke/app_shell_smoke_test.dart test/pages/startup_gate_test.dart`
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 6: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(boot): defer remote boot and hot-recover on reconnect"
```

---

### Task 5: 后台重试生命周期（取消/继续，不静默放弃）

**Files:**
- Modify: `client/lib/services/ssh/ssh_profile_connection_coordinator.dart`
- Modify: `client/lib/app/app_shell.dart`（把 cubit 与协调器接线）
- Test: `client/test/services/ssh/ssh_profile_connection_coordinator_reconnect_test.dart` (extend/create)

**Interfaces:**
- Consumes: `SshProfileConnectionCoordinator.userConnect/userDisconnect`, `HomeConnectionCubit.markBackgroundAttempt/markReconnected`.
- Produces: a retry loop that keeps retrying while the error page is visible and stops on `cancelRetry`.

- [ ] **Step 1: Write the failing test** — a coordinator with a failing `reconnectStorage` keeps scheduling (does not give up after `maxAttempts` when a "keep alive on page" flag is set), and `userDisconnect` cancels the timer.

- [ ] **Step 2: Implement the "no silent give-up" behavior** — add an optional `bool persistWhileUnreachable`/callback so the home profile keeps retrying with the policy backoff instead of stopping at 5 attempts; expose a signal to update `HomeConnectionCubit.markBackgroundAttempt(attempt)` and `markReconnected()` on success.

- [ ] **Step 3: Run + analyze + commit**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_connection_coordinator_reconnect_test.dart`
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

```bash
git add client/lib/services/ssh/ssh_profile_connection_coordinator.dart client/lib/app/app_shell.dart client/test/services/ssh/ssh_profile_connection_coordinator_reconnect_test.dart
git commit -m "feat(ssh): keep retrying while home unreachable and surface progress"
```

---

### Task 6: 集成测试 + 回归 + 文档

**Files:**
- Create: `client/test/integration/home_unreachable_boot_test.dart` (`@Tags(['integration'])`)
- Modify: `docs/ARCHITECTURE.md`（追加 "Home connection resilience" 小节）

- [ ] **Step 1: Integration test** — boot with a fake probe returning `false` for the home host; assert:
  - `markAppReady` is reached well under the old ~17s×N path (assert the remote boot was **not** invoked);
  - `HomeConnectionCubit.state.status == unreachable`;
  - then flip the fake to reachable + emit reconnect success → `runRemoteBootAfterConnect` runs exactly once and status becomes `connected`.

- [ ] **Step 2: Docs** — append to `docs/ARCHITECTURE.md`:

```markdown
## Home connection resilience

Boot never blocks the splash on remote home I/O. The first home connect is a
bounded attempt (2s TCP probe + 8s SSH budget). On failure the shell still
builds, `StartupGate` shows a connection page (host/port, attempt, error kind)
with Stop retrying / Retry now / Switch connection, and the reconnect
coordinator keeps retrying in the background. A successful reconnect replays
the deferred remote boot once (hot recovery). The storage pool's existing
single-flight open semantics are unchanged.
```

- [ ] **Step 3: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`（0 errors）
Run (background, once): `cd client && dart run tool/run_tests.dart`
Expected: only the known pre-existing failure `test/pages/ssh_profiles/ssh_profiles_section_test.dart` "Test does not mark Cubit connected" (fails on `main` too); everything else green.

- [ ] **Step 4: Commit**

```bash
git add client/test/integration/home_unreachable_boot_test.dart docs/ARCHITECTURE.md
git commit -m "test(boot): cover unreachable home startup and hot recovery"
```

---

## Self-Review

**Spec coverage:**
- 根因 1（splash 阻塞远端）→ Task 4（boot 解耦）。
- 根因 2（无快速失败）→ Task 1（TCP 探活 + 有界预算）。
- 根因 3（失败重开 + 启动期重连）→ Task 1 + Task 4（重连移出关键路径）+ Task 5。
- 根因 4（零可见性）→ Task 3（连接页 + 三动作）。
- 状态机 / 三动作 → Task 2 + Task 3。
- 热恢复 → Task 4。
- 测试 → 各任务 + Task 6。

**Placeholder check:** 每个代码步骤都给出可编译代码或精确锚点；唯一需要实现者按真实签名适配的是 `RuntimeContext` 的构造与 `app_shell` 内已有变量的名字，已显式标注。

**Type consistency:** `HomeConnectResult` / `HomeErrorKind` / `HomeConnectionStatus` / `HomeConnectionState` / `HomeConnectionCubit` 的方法名在各任务间保持一致（`connectOnce` / `retryNow` / `cancelRetry` / `markBackgroundAttempt` / `markReconnected` / `markInitial`）。

**Open implementation detail:** `StartupGate` 的分支顺序需与 spec §3 的优先级一致（`requiresSshProfileSetup` 在状态分支之前）；`HomeConnectionCubit` 需补一个 `markInitial(HomeConnectResult)` 用于用首次尝试结果同步播种（不改 `connectOnce` 语义）。
