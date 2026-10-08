# tp_sshd direct-tcpip 转发实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `tp_sshd` 以生产级（对齐 OpenSSH）语义服务 `direct-tcpip` 通道，打通手机→桌面的事件推送（`forwardLocal`），并适配 app 注入面。

**Architecture:** 新增 `SSHForwardingConfig` 统一两类 TCP 转发（`SshTcpForwardingMode` 方向位 + 逐连接 `permitOpen` 谓词 + dial/bind 两个注入 seam）；`direct-tcpip` 在 `_handleChannelOpen` 分派给 `SSHServerDirectDialer` 门控→拨号→确认；双向泵流抽为共享顶层函数；`embedded_ssh_server.dart` 注入「both + loopback-only permitOpen + Socket.connect」配置。

**Tech Stack:** Dart 3 / `tp_sshd`（纯 Dart）/ `dartssh2`（fork）/ 库测试 `package:test`（VM-only）/ app 测试 `flutter_test`。对照源码：`/tmp/opencode/openssh`（`openssh/openssh-portable` HEAD）。

## Global Constraints

- **tp_sshd 纯 Dart**：不 import Flutter / app 代码；只能在 `cd client/packages/tp_sshd` 下 `dart analyze` 与 `dart test`。dartssh2 / tp_sshd 包绝不能跑 `flutter test`。
- **app 测试**：一律 `cd client && dart run tool/run_tests.dart <path>`（严禁直接 `flutter test`，锁保护共享构建缓存）。
- 库核心保持「不碰 DNS」：目标解析由注入的 dial seam（`Socket.connect`）完成，tp_sshd 只传 host 字符串。
- `direct-tcpip` 通道**不挂** `onRequest`；`x11` / `direct-streamlocal@openssh.com` 维持 reason 1 拒绝。
- 不做向后兼容：顶层 `SSHServerConfig.bindServerSocket` 移除，改用 `forwarding`。
- 拒绝码常量（不得改值）：reason 1 `codeAdministrativelyProhibited`、2 `codeConnectFailed`、4 `codeResourceShortage`。
- 端口校验对齐 `serverloop.c:434`：`direct-tcpip` 目标端口 `> 0xFFFF` → reason 1。
- 每个语义点对照 `/tmp/opencode/openssh`：`serverloop.c`（`server_request_direct_tcpip`:418、`tcpip-forward` 门控:776）、`channels.c`（`channel_connect_to_port`:4790、`connect_to_helper`:4747）、`servconf.c`（`AllowTcpForwarding` 关键字表:1086）。发现其它不一致随时修正实现并回写 spec。
- 仓库文件超过 ~500 行即拆分信号；`server_connection.dart`、`server_forward.dart` 增改时注意保持单一职责（dial 逻辑进新文件）。

## 文件地图

| 文件 | 责任 | 动作 |
|---|---|---|
| `client/packages/tp_sshd/lib/src/ssh_server.dart` | `SshTcpForwardingMode`、`SSHForwardingConfig`、`SSHServerConfig`（`bindServerSocket`→`forwarding`） | 改 |
| `client/packages/tp_sshd/lib/src/server_forward.dart` | `SSHDialSocket` typedef、`pumpForwardConnection`、forwarder 门控 | 改 |
| `client/packages/tp_sshd/lib/src/server_connection.dart` | `_handleChannelOpen` 分派 `direct-tcpip`、forwarder 装配、`permitOpen` 谓词装配 | 改 |
| `client/packages/tp_sshd/lib/src/server_dial.dart` | `SSHServerDirectDialer`（门控/拨号/失败映射，单一职责、可独立测试） | **建** |
| `client/packages/tp_sshd/test/dual_test_utils.dart` | 测试缝合：`forwarding` 参数替换 `bindServerSocket` | 改 |
| `client/packages/tp_sshd/test/server_direct_tcpip_test.dart` | direct-tcpip 全路径测试 | **建** |
| `client/packages/tp_sshd/test/server_forward_test.dart`、`server_channel_test.dart` | 适配新配置面 + 新门控测试 | 改 |
| `client/packages/tp_sshd/example/demo_sshd.dart`、`README.md` | 示例与文档适配 | 改 |
| `client/lib/services/connect/embedded_ssh_server.dart` | 注入 `SSHForwardingConfig`（both + loopback permitOpen + 真拨号/绑定适配） | 改 |
| `client/test/integration/embedded_event_transport_test.dart` | 端到端：SSH forwardLocal → EventTransportServer 推送 | **建** |

## Task 1: 抽取共享泵流 `pumpForwardConnection`（纯重构，行为不变）

**Files:**
- Modify: `client/packages/tp_sshd/lib/src/server_forward.dart`（`SSHServerForwarder._pump`:236）
- Verify: `client/packages/tp_sshd/test/server_forward_test.dart`

**Interfaces:**
- Produces: 顶层 `void Future<void> pumpForwardConnection(SSHServerChannel channel, ForwardConnection connection)` —— Task 4 的 dial 路径调用它；语义与现 `_pump` 完全一致（TCP→channel、channel→TCP 双向订阅，任一侧 done 半关闭对侧，`channel.done` 销毁 connection，`connection.done` 关闭 channel）。

- [ ] **Step 1: 抽取**

把 `SSHServerForwarder._pump` 的方法体原样提为同文件顶层函数 `pumpForwardConnection(SSHServerChannel channel, ForwardConnection connection)`（注释照搬），`_serveAcceptedConnection` 改为调用 `await pumpForwardConnection(channel, connection)`，删除方法 `_pump`。

- [ ] **Step 2: 验证现有行为不变**

Run: `cd client/packages/tp_sshd && dart analyze && dart test test/server_forward_test.dart`
Expected: analyze 无告警，6 个 forward 用例全过。

- [ ] **Step 3: Commit**

```bash
cd client/packages/tp_sshd && git add lib/src/server_forward.dart && git commit -m "refactor(tp_sshd): extract shared forward pump"
```

## Task 2: 转发配置表面 `SSHForwardingConfig` + 反连门控（库）

**Files:**
- Modify: `client/packages/tp_sshd/lib/src/ssh_server.dart`（枚举 + 配置类 + 字段替换）
- Modify: `client/packages/tp_sshd/lib/src/server_forward.dart`（`SSHDialSocket` typedef + forwarder 门控）
- Modify: `client/packages/tp_sshd/lib/src/server_connection.dart`（forwarder 装配、permitOpen 谓词装配）
- Test: `client/packages/tp_sshd/test/dual_test_utils.dart`、`server_forward_test.dart`、`server_channel_test.dart`
- Modify: `client/packages/tp_sshd/example/demo_sshd.dart`

**Interfaces:**
- Consumes: 无（本任务从零建面）。
- Produces:
  - `enum SshTcpForwardingMode { deny, local, remote, both }` + `bool get allowsLocal`（`local`/`both`）、`bool get allowsRemote`（`remote`/`both`）。
  - `typedef SSHDialSocket = Future<ForwardConnection> Function(String host, int port);`（`server_forward.dart`）
  - `final class SSHForwardingConfig` 字段：
    `SshTcpForwardingMode allowTcpForwarding;`
    `Future<bool> Function(SSHServerConnection connection, String host, int port)? permitOpen;`（null=全放行）
    `SSHDialSocket dialSocket;`
    `SSHBindServerSocket bindServerSocket;`
    `Duration dialTimeout;`
  - `SSHServerConfig`：删 `SSHBindServerSocket? bindServerSocket`，加 `SSHForwardingConfig? forwarding`（`null` == 硬禁用：两类转发全部拒绝）。
  - `SSHServerConnection` 内部装配：`allowTarget` 回调 `Future<bool> Function(String, int)`（绑定 `permitOpen?.call(this, host, port) ?? true`），随构造透传给 `SSHServerForwarder`。

- [ ] **Step 1: 写失败测试（新门控语义）**

在 `server_forward_test.dart` 追加两个用例（TDD，先红）：

```dart
test('permitOpen gates the bind target before the seam is consulted', () async {
  final seamCalls = <(String, int)>[];
  var allow = false;
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: SSHForwardingConfig(
      allowTcpForwarding: SshTcpForwardingMode.remote,
      permitOpen: (connection, host, port) async {
        return allow;
      },
      dialSocket: (host, port) => throw StateError('no dail'),
      bindServerSocket: (address, port) async {
        seamCalls.add((address.address, port));
        return _RealServerSocketHandle(await ServerSocket.bind(address, port));
      },
      dialTimeout: const Duration(seconds: 5),
    ),
  );
  expect(await client.forwardRemote(host: '127.0.0.1', port: 0), isNull);
  expect(seamCalls, isEmpty);
  allow = true;
  final forward = await client.forwardRemote(host: '127.0.0.1', port: 0);
  expect(forward, isNotNull);
  await forward!.close();
  await client.close();
  await server.close();
});

test('remote forwarding is refused when the mode lacks the remote bit',
    () async {
  var failures = 0;
  final (connection, client) = await startRawAuthenticatedConnection(
    forwarding: SSHForwardingConfig(
      allowTcpForwarding: SshTcpForwardingMode.local,
      permitOpen: null,
      dialSocket: (host, port) => throw StateError('no dial'),
      bindServerSocket: _bindRealLoopback,
      dialTimeout: const Duration(seconds: 5),
    ),
    onServerMessage: (payload) {
      if (SSHMessage.readMessageId(payload) ==
          SSH_Message_Request_Failure.messageId) {
        failures += 1;
      }
    },
  );
  client.sendPacket(
    SSH_Message_Global_Request.tcpipForward('127.0.0.1', 0).encode(),
  );
  await waitUntil(() => failures == 1);
  await connection.close();
  client.close();
});
```

（`dual_test_utils.dart` 同步把 `bindServerSocket` 形参换成 `SSHForwardingConfig? forwarding`，`startRawAuthenticatedConnection` 同样；此时上述新用例引用的新签名不存在，测试必然编译失败 = 红。）

- [ ] **Step 2: 确证失败**

Run: `cd client/packages/tp_sshd && dart analyze 2>&1 | head -30`
Expected: SSHForwardingConfig / forwarding 形参不存在 → 编译错误。**这是本步骤的目的**。

- [ ] **Step 3: 实现配置面**

`ssh_server.dart`：

```dart
enum SshTcpForwardingMode {
  deny,
  local,
  remote,
  both;

  bool get allowsLocal => this == SshTcpForwardingMode.local || this == SshTcpForwardingMode.both;
  bool get allowsRemote => this == SshTcpForwardingMode.remote || this == SshTcpForwardingMode.both;
}

/// AllowTcpForwarding + PermitOpen + seams（见 spec §1）。
final class SSHForwardingConfig {
  SSHForwardingConfig({
    required this.allowTcpForwarding,
    required this.dialSocket,
    required this.bindServerSocket,
    this.permitOpen,
    this.dialTimeout = const Duration(seconds: 30),
  });

  final SshTcpForwardingMode allowTcpForwarding;
  final Future<bool> Function(SSHServerConnection connection, String host, int port)? permitOpen;
  final SSHDialSocket dialSocket;
  final SSHBindServerSocket bindServerSocket;
  final Duration dialTimeout;
}
```

`SSHServerConfig`：删 `bindServerSocket` 字段与构造参数，加 `this.forwarding` 与 `final SSHForwardingConfig? forwarding;`（原字段的 doc 注释移到 `SSHForwardingConfig.bindServerSocket` 上）。

`server_forward.dart`：加 typedef + forwarder 门控：

```dart
typedef SSHDialSocket = Future<ForwardConnection> Function(String host, int port);
```

`SSHServerForwarder` 构造新增 `required SshTcpForwardingMode allowTcpForwarding;` 与
`required Future<bool> Function(String host, int port) allowTarget;`
（由 `server_connection.dart` 装配 `allowTarget`，见下）。`_handleTcpipForward` 开头补两道门（复用现有 `_reply`）：

```dart
if (!allowTcpForwarding.allowsRemote) {
  printDebug?.call('tp_sshd: tcpip-forward disabled (mode $allowTcpForwarding)');
  _reply(request, success: false);
  return;
}
if (!await allowTarget(requestedHost, requestedPort)) {
  printDebug?.call('tp_sshd: refusing tcpip-forward for $requestedHost:$requestedPort');
  _reply(request, success: false);
  return;
}
```

（`requestedHost`/`requestedPort` 在现有代码第 134 行已取值：先空值检查后置；空值拒绝逻辑保持不变。）

`server_connection.dart` 装配（构造体内替换 `bindServerSocket` 分支）：

```dart
final forwarding = config.forwarding;
if (forwarding != null) {
  final targetAllowed = forwarding.permitOpen == null
      ? (String host, int port) async => true
      : (String host, int port) async =>
          forwarding.permitOpen!(this, host, port);
  _forwarder = SSHServerForwarder(
    allowTcpForwarding: forwarding.allowTcpForwarding,
    allowTarget: targetAllowed,
    bindServerSocket: forwarding.bindServerSocket,
    openForwardedChannel: _openForwardedChannel,
    sendPacket: _transport.sendPacket,
    printDebug: config.printDebug,
  );
}
```

- [ ] **Step 4: 适配既有调用点**

`dual_test_utils.dart`：`startDualPair` / `startDualConnection` / `startRawAuthenticatedConnection` 的 `SSHBindServerSocket? bindServerSocket` 形参换成 `SSHForwardingConfig? forwarding`，构造时传 `forwarding: forwarding`。
`server_forward_test.dart`：既有 5 个用例把 `bindServerSocket: _bindRealLoopback` 改为 `forwarding: _testForwardingConfig(bindServerSocket: _bindRealLoopback)`（本地小助手：`SSHForwardingConfig(allowTcpForwarding: SshTcpForwardingMode.remote, dialSocket: (h, p) => throw StateError('no dial'), bindServerSocket: bindServerSocket)`）；无 seam 的拒连用例用 `forwarding: null`。
`server_channel_test.dart` 的「tcpip-forward 仍拒绝」用例（:114-125）改为 `startDualPair(... forwarding: null)`。
`example/demo_sshd.dart`：`bindServerSocket:` → `forwarding: SSHForwardingConfig(allowTcpForwarding: SshTcpForwardingMode.both, dialSocket: <demo 真拨号>, bindServerSocket: <原适配>)`。

- [ ] **Step 5: 验证新门控用例转绿**

Run: `cd client/packages/tp_sshd && dart analyze && dart test test/server_forward_test.dart test/server_channel_test.dart`
Expected: 全部通过（含 Step 1 的两个新用例）。

- [ ] **Step 6: 全量回归 + Commit**

Run: `cd client/packages/tp_sshd && dart test`
Expected: 全绿。
```bash
cd client/packages/tp_sshd && git add lib/src/ssh_server.dart lib/src/server_forward.dart lib/src/server_connection.dart lib/src/tp_sshd.dart test/dual_test_utils.dart test/server_forward_test.dart test/server_channel_test.dart example/demo_sshd.dart && git commit -m "feat(tp_sshd): unified forwarding config with tcpip-forward gating"
```

## Task 3: app 注入新配置面（bind + dial + loopback permitOpen）

**Files:**
- Modify: `client/lib/services/connect/embedded_ssh_server.dart`
- Verify: `client/test/integration/embedded_pairing_test.dart`、`client/test/cubits/connect_cubit_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `SSHForwardingConfig` / `SshTcpForwardingMode` / `SSHDialSocket`。
- Produces: app 侧 `permitOpen` 谓词常量（供未来 per-device 白名单替换）；`embedded_ssh_server.dart` 不再引用 `bindServerSocket` 顶层字段。

- [ ] **Step 1: 写失败测试**

先改编译：给 `embedded_ssh_server.dart` 换成新配置面（Step 2），然后（本步前置）`cd client && dart analyze` 应报 `embedded_ssh_server.dart` 仍用旧 `bindServerSocket` 顶层字段的错误——确证旧面已移除。随后在 `client/test/services/connect/` 下新增 `embedded_ssh_server_test.dart`（若该目录不存在则建；用 `setUpTestAppStorage` 式真实临时根），断言：

- `server.start()` 后，一个已注册设备 key 的 `dartssh2 SSHClient` 能 `forwardRemote` 绑定 loopback（反连未回归）；
- 同一客户端 `forwardLocal('localhost', 端口)` 拨到 `127.0.0.1` 上真实 `ServerSocket` 的回显服务，双向字节往返成功（permitting loopback + dial 通）；
- `forwardLocal` 指向**非 loopback**目标（如 `store.example` 不可达主机）→ `permitOpen` 拒绝 → `SSHChannelOpenError.code == 1`。

（该用例在 Step 2 之前因新配置面未接而编译失败/运行失败——先红。）

- [ ] **Step 2: 改注入**

`embedded_ssh_server.dart` `start()` 里：

```dart
forwarding: SSHForwardingConfig(
  allowTcpForwarding: SshTcpForwardingMode.both,
  permitOpen: _loopbackOnlyPermit,
  dialSocket: (host, port) async =>
      _IoForwardConnection(await Socket.connect(host, port)),
  bindServerSocket: (address, port) async =>
      _IoServerSocketHandle(await ServerSocket.bind(address, port)),
),
```

同文件加：

```dart
/// App PermitOpen：只放行 loopback 拨号目标（host 字符串不解析）。
/// 未来 per-device 白名单只替换这一个谓词。
static Future<bool> _loopbackOnlyPermit(
  SSHServerConnection connection,
  String host,
  int port,
) async =>
    host == '127.0.0.1' || host == '::1' || host == 'localhost';
```

（`SSHServerConnection` 已由 `tp_sshd.dart` 导出；`Socket` 已 import `dart:io`。）

- [ ] **Step 3: 验证**

Run: `cd client && dart analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/services/connect/embedded_ssh_server_test.dart`
Expected: 编译通过，新用例绿。
Run: `dart run tool/run_tests.dart test/cubits/connect_cubit_test.dart test/integration/embedded_pairing_test.dart`
Expected: 既有 connect 行为未回归。

- [ ] **Step 4: Commit**

```bash
cd client && git add lib/services/connect/embedded_ssh_server.dart test/services/connect/embedded_ssh_server_test.dart && git commit -m "feat(connect): inject forwarding config with loopback-only direct-tcpip"
```

## Task 4: 服务 `direct-tcpip`（核心）

**Files:**
- Create: `client/packages/tp_sshd/lib/src/server_dial.dart`
- Modify: `client/packages/tp_sshd/lib/src/server_connection.dart`
- Modify: `client/packages/tp_sshd/lib/tp_sshd.dart`（导出 `server_dial.dart`）
- Create: `client/packages/tp_sshd/test/server_direct_tcpip_test.dart`
- Modify: `client/packages/tp_sshd/test/dual_test_utils.dart`（raw 用例需要 `forwarding` 已就绪，仍在本任务给 raw 增 `SSH_Message_Channel_Open.directTcpip` 需手工直送——用现有 `startRawAuthenticatedConnection(forwarding: …)` 即可）
- Modify: `client/packages/tp_sshd/test/server_channel_test.dart`（:32 用例改为断言 `forwardLocalUnix` 仍被拒，direct-tcpip 的拒绝语义移入新文件）

**Interfaces:**
- Consumes: Task 1 的 `pumpForwardConnection`、Task 2 的 `SSHForwardingConfig` / `SshTcpForwardingMode`。
- Produces:
  - `final class SSHServerDirectDialer`（构造：`required SSHForwardingConfig forwarding, required Future<bool> Function(String host,int port) allowTarget`；方法见下）。
  - `DirectDialResult` 三种结局：
    ```dart
    sealed class DirectDialResult {}
    class DirectDialRefused extends DirectDialResult { final int reasonCode; final String description; }
    class DirectDialConnected extends DirectDialResult { final ForwardConnection connection; }
    ```
  - `Future<DirectDialResult> dial(String host, int port)`：门控（mode.local 位 / 端口 ≤ 0xFFFF / `allowTarget`）→ 拨号 `forwarding.dialSocket(host, port).timeout(forwarding.dialTimeout)`。拨号期间连接关闭的竞态由调用方（`_serveDirectTcpip`）的 `_phase` 检查兜底，dialer 自身无连接知识。

- [ ] **Step 1: 写失败测试**

新建 `test/server_direct_tcpip_test.dart`（镜像 `server_forward_test.dart` 的 dual 形态；文件底部照抄该文件的 `_bindRealLoopback` / `_RealServerSocketHandle` / `_RealForwardConnection` 适配类 :225-271），用例：

```dart
final forwardingConfig = ({SSHDialSocket? dial, Future<bool> Function(SSHServerConnection,String,int)? permit}) => SSHForwardingConfig(
  allowTcpForwarding: SshTcpForwardingMode.both,
  permitOpen: permit,
  dialSocket: dial ?? (host, port) => throw StateError('no dial'),
  bindServerSocket: _bindRealLoopback,
  dialTimeout: const Duration(seconds: 5),
);

Future<ServerSocket> _echoListener() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  listener.listen((socket) {
    socket.listen((data) => socket.add(data), onDone: socket.close);
  });
  return listener;
}

test('direct-tcpip round-trips bytes over a real loopback target', () async {
  final listener = await _echoListener();
  addTearDown(listener.close);
  final echoed = Completer<void>();
  final seenHosts = <String>[];
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: forwardingConfig(dial: (host, port) async {
      seenHosts.add(host);
      return _RealForwardConnection(await Socket.connect(host, port));
    }),
  );
  final channel = await client.forwardLocal('127.0.0.1', listener.port);
  final got = StringBuffer();
  channel.stream.listen((data) {
    got.write(utf8.decode(data));
    if (!echoed.isCompleted && got.toString().contains('ping')) echoed.complete();
  });
  channel.sink.add(utf8.encode('ping'));
  await echoed.future.timeout(const Duration(seconds: 5));
  expect(got.toString(), 'ping');
  expect(seenHosts, ['127.0.0.1']);
  await channel.close();
  await client.close();
  await server.close();
});

test('host string is handed to the seam verbatim', () async {
  final seen = <String>[];
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: forwardingConfig(dial: (host, port) async {
      seen.add(host);
      return _RealForwardConnection(await Socket.connect('127.0.0.1', port));
    }),
  );
  final listener = await _echoListener();
  addTearDown(listener.close);
  await client.forwardLocal('localhost', listener.port);
  expect(seen, ['localhost']);
  await client.close();
  await server.close();
});

test('forwarding disabled refuses direct-tcpip with reason 1', () async {
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
  );
  await expectLater(
    client.forwardLocal('127.0.0.1', 80),
    throwsA(isA<SSHChannelOpenError>()
        .having((e) => e.code, 'code', SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited)
        .having((e) => e.code, 'wire', 1)),
  );
  await client.close();
  await server.close();
});

test('permitOpen denial refuses with reason 1 and never dials', () async {
  var dialed = 0;
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: forwardingConfig(
      permit: (conn, host, port) async => host == '127.0.0.1',
      dial: (host, port) async {
        dialed += 1;
        throw StateError('should not dial');
      },
    ),
  );
  await expectLater(
    client.forwardLocal('10.0.0.1', 80),
    throwsA(isA<SSHChannelOpenError>()
        .having((e) => e.code, 'code', SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited)),
  );
  expect(dialed, 0);
  await client.close();
  await server.close();
});

test('dial failure refuses with reason 2 and keeps the connection alive',
    () async {
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: forwardingConfig(
      dial: (host, port) => Socket.connect('127.0.0.1', 1), // nothing there
    ),
  );
  await expectLater(
    client.forwardLocal('127.0.0.1', 1),
    throwsA(isA<SSHChannelOpenError>()
        .having((e) => e.code, 'code', SSH_Message_Channel_Open_Failure.codeConnectFailed)
        .having((e) => e.code, 'wire', 2)),
  );
  await expectLater(client.ping(), completes); // 连接存活
  await client.close();
  await server.close();
});

test('out-of-range target port refuses with reason 1', () async {
  // raw 驱动（真实 client 会拒绝 0x10000 端口）
  final refused = Completer<void>();
  final (connection, client) = await startRawAuthenticatedConnection(
    forwarding: forwardingConfig(),
    onServerMessage: (payload) {
      final m = SSHMessage.readMessageId(payload);
      if (m == SSH_Message_Channel_Open_Failure.messageId &&
          SSH_Message_Channel_Open_Failure.decode(payload).reasonCode ==
              SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited &&
          !refused.isCompleted) {
        refused.complete();
      }
    },
  );
  client.sendPacket(
    SSH_Message_Channel_Open.directTcpip(
      senderChannel: 3,
      initialWindowSize: 2 * 1024 * 1024,
      maximumPacketSize: 32768,
      host: '127.0.0.1',
      port: 0x10000,
      originatorIP: '127.0.0.1',
      originatorPort: 5,
    ).encode(),
  );
  await refused.future.timeout(const Duration(seconds: 5));
  await connection.close();
  client.close();
});

test('direct-tcpip channels count against the per-connection cap', () async {
  final listener = await _echoListener();
  addTearDown(listener.close);
  final (client, connection) = await startDualConnection(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: forwardingConfig(dial: (host, port) async =>
        _RealForwardConnection(await Socket.connect(host, port))),
  );
  // 10 个 session 通道（cap）后，direct-tcpip 打开被 reason 4 拒绝、表不膨胀：
  // 拒绝恰在分派前发生，拨号不会执行。
  for (var i = 0; i < 10; i++) {
    await openClientSessionChannel(client);
  }
  expect(connection.channels.length, 10);
  await expectLater(
    client.forwardLocal('127.0.0.1', listener.port),
    throwsA(isA<SSHChannelOpenError>()
        .having((e) => e.code, 'code', SSH_Message_Channel_Open_Failure.codeResourceShortage)
        .having((e) => e.code, 'wire', 4)),
  );
  expect(connection.channels.length, 10);
  await connection.close();
  await client.close();
});

test('connection close destroys the dialed socket', () async {
  final listener = await _echoListener();
  addTearDown(listener.close);
  final (client, server) = await startDualPair(
    hostKeyPair: testHostKey,
    authenticate: (_) async => true,
    clientIdentities: [testDeviceKey],
    forwarding: forwardingConfig(dial: (host, port) async =>
        _RealForwardConnection(await Socket.connect(host, port))),
  );
  final channel = await client.forwardLocal('127.0.0.1', listener.port);
  await server.close();
await channel.done.timeout(const Duration(seconds: 5)); // 拨入 socket 被销毁
   await client.close();
});
```

另外把 `server_channel_test.dart:32-63` 的 `unknown channel type` 用例改为验证 `forwardLocalUnix`（`direct-streamlocal@openssh.com`）仍被拒 reason 1——direct-tcpip 的成功语义已由本文件覆盖。

- [ ] **Step 2: 确证失败**

Run: `cd client/packages/tp_sshd && dart analyze 2>&1 | head -40`
Expected: `SSHServerDirectDialer`、`forwarding` 形参缺失 → 编译错误。

- [ ] **Step 3: 实现 `server_dial.dart`**

```dart
import 'dart:async';

import 'package:dartssh2/protocol.dart'
    show SSH_Message_Channel_Open_Failure;

import 'server_forward.dart' show ForwardConnection, SSHDialSocket;
import 'ssh_server.dart' show SSHForwardingConfig, SshTcpForwardingMode;

/// Eventual outcome of a client-opened `direct-tcpip` open.
///
/// [DirectDialRefused] sends a CHANNEL_OPEN_FAILURE; [DirectDialConnected]
/// lets the connection confirm the channel and start the shared pump. A
/// connection that closes while the dial is in flight is the caller's
/// concern (its `_phase` check destroys [DirectDialConnected.connection]).
sealed class DirectDialResult {}

/// The server refuses the open (reason aligned with OpenSSH).
final class DirectDialRefused extends DirectDialResult {
  DirectDialRefused(this.reasonCode, this.description);
  final int reasonCode;
  final String description;
}

/// The dial succeeded; [connection] rides a `direct-tcpip` channel.
final class DirectDialConnected extends DirectDialResult {
  DirectDialConnected(this.connection);
  final ForwardConnection connection;
}

/// Gates and dials one `direct-tcpip` channel open (RFC 4254 §7.1).
///
/// Parallel to [SSHServerForwarder]: gate order mirrors OpenSSH
/// `server_request_direct_tcpip` + `channel_connect_to_port` — disabled /
/// bad port / PermitOpen first (reason 1), then dial; any dial failure is
/// reason 2 (`SSH2_OPEN_CONNECT_FAILED`), never a dropped connection.
class SSHServerDirectDialer {
  SSHServerDirectDialer({
    required SSHForwardingConfig forwarding,
    required Future<bool> Function(String host, int port) allowTarget,
  })  : _forwarding = forwarding,
        _allowTarget = allowTarget;

  final SSHForwardingConfig _forwarding;
  final Future<bool> Function(String host, int port) _allowTarget;

  static const _maxTargetPort = 0xffff;

  /// Runs the gates and the dial. Does not touch the connection.
  Future<DirectDialResult> dial(String host, int port) async {
    if (!_forwarding.allowTcpForwarding.allowsLocal) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'TCP forwarding is disabled',
      );
    }
    if (port < 0 || port > _maxTargetPort) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'invalid target port $port',
      );
    }
    if (!await _allowTarget(host, port)) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
        'forwarding disabled for $host:$port',
      );
    }

    final ForwardConnection connection;
    try {
      connection = await _forwarding
          .dialSocket(host, port)
          .timeout(_forwarding.dialTimeout);
    } on Object catch (error) {
      return DirectDialRefused(
        SSH_Message_Channel_Open_Failure.codeConnectFailed,
        error.toString(),
      );
    }
    return DirectDialConnected(connection);
  }
}
```

`server_connection.dart`：新增 `_serveDirectTcpip(SSH_Message_Channel_Open message)`；`_handleChannelOpen` 开头把 cap 检查挪到类型分派之前，再按类型分派（`_refuseChannelOpen` 小助手与结果处理后续给出）：

```dart
// cap 检查（现有代码 252-262 原样上移，先于类型分派）
// ...
if (message.channelType == 'direct-tcpip') {
  unawaited(_serveDirectTcpip(message));
  return;
}
if (message.channelType != 'session') { /* 现有 reason1 拒绝 */ return; }
// ... 现有 session 路径不变
```

```dart
Future<void> _serveDirectTcpip(SSH_Message_Channel_Open message) async {
  final forwarding = _config.forwarding;
  if (forwarding == null || message.host == null || message.port == null) {
    _refuseChannelOpen(
      message.senderChannel,
      SSH_Message_Channel_Open_Failure.codeAdministrativelyProhibited,
      'TCP forwarding is disabled',
    );
    return;
  }
  final dialer = SSHServerDirectDialer(
    forwarding: forwarding,
    allowTarget: _directTargetAllowed,
  );
  final result = await dialer.dial(message.host!, message.port!);
  switch (result) {
    case DirectDialRefused():
      _refuseChannelOpen(
          message.senderChannel, result.reasonCode, result.description);
    case DirectDialConnected():
      // 拨号期间连接关闭：销毁拨入 socket，不发任何包。
      if (_phase != _Phase.running) {
        result.connection.destroy();
        return;
      }
      final ourChannel = _nextChannelNumber++;
      final channel = SSHServerChannel(
        recipientChannel: message.senderChannel,
        ourChannel: ourChannel,
        channelType: 'direct-tcpip',
        peerInitialWindowSize: message.initialWindowSize,
        peerMaximumPacketSize: message.maximumPacketSize,
        sendPacket: _transport.sendPacket,
        onClosed: (channel) => _channels.remove(channel.ourChannel),
        printDebug: _config.printDebug,
      );
      _channels[ourChannel] = channel;
      _transport.sendPacket(
        SSH_Message_Channel_Confirmation(
          recipientChannel: message.senderChannel,
          senderChannel: ourChannel,
          initialWindowSize: SSHServerChannel.initialReceiveWindow,
          maximumPacketSize: SSHServerChannel.maximumPacketSize,
          data: Uint8List(0),
        ).encode(),
      );
      unawaited(pumpForwardConnection(channel, result.connection));
  }
}

Future<bool> _directTargetAllowed(String host, int port) =>
    _config.forwarding!.permitOpen?.call(this, host, port) ?? true;

void _refuseChannelOpen(int recipientChannel, int reasonCode, String description) {
  try {
    _transport.sendPacket(
      SSH_Message_Channel_Open_Failure(
        recipientChannel: recipientChannel,
        reasonCode: reasonCode,
        description: description,
      ).encode(),
    );
  } on Object {
    // transport 已走；连接拆除负责收尾
  }
}
```

装配 `_directTargetAllowed` 复用 Task 2 的 targetAllowed 逻辑（两路谓词同源，forwarder 分支保持原样）。直接拨号期间连接关闭由 `_phase != running` 检查销毁拨入 socket、不发任何包（对齐 spec §6「拨号期间连接已关」行）。`tp_sshd.dart` 导出 `server_dial.dart`。

- [ ] **Step 4: 验证核心用例转绿**

Run: `cd client/packages/tp_sshd && dart analyze && dart test test/server_direct_tcpip_test.dart test/server_channel_test.dart`
Expected: 新文件全部用例绿；改过的 channel 用例绿。若 round-trip 用例失败，对照 OpenSSH `connect_to_helper`/`channel_connect_to_port` 复核（拨号返回时机、confirmation 载荷顺序），并回写 spec。

- [ ] **Step 5: 全量回归**

Run: `cd client/packages/tp_sshd && dart test`
Expected: 全绿。同步复核 `server_forward_test.dart`（Task 2 门控未受 `_serveDirectTcpip` 影响）。

- [ ] **Step 6: Commit**

```bash
cd client/packages/tp_sshd && git add lib/src/server_dial.dart lib/src/server_connection.dart lib/tp_sshd.dart test/server_direct_tcpip_test.dart test/server_channel_test.dart && git commit -m "feat(tp_sshd): serve direct-tcpip channels with OpenSSH semantics"
```

## Task 5: 端到端集成（SSH forwardLocal → 事件推送）

**Files:**
- Create: `client/test/integration/embedded_event_transport_test.dart`
- Verify: 运行日志不再出现 `'direct-tcpip' is not supported`；`openSshEventTransportChannel` 走真实推送。

**Interfaces:**
- Consumes: Task 3 的 `EmbeddedSshServer`（已带 forwarding 配置）、`EventTransportServer`、`agent_presence_*` 事件家族、dartssh2 `forwardLocal`。
- Produces: 无新 API。

- [ ] **Step 1: 写集成测试（先红）**

新建 `client/test/integration/embedded_event_transport_test.dart`，标签与运行方式照抄 `embedded_pairing_test.dart`（`@Tags(['integration', 'cross-platform'])`）。测试骨架（镜像 `event_transport_server_test.dart:30-40` 的 server 构造 + `embedded_pairing_test.dart:68-87` 的 server 构造）：

```dart
test('phone forwardLocal receives the presence push from EventTransportServer',
    () async {
  // 1) 嵌入式 sshd（真实 loopback + 已注册设备 key）
  final deviceKey = SshDeviceKey.generate();
  await deviceStore.issueDevice(
    deviceId: SshDeviceKey.deviceIdFor(deviceKey.openSshPublic),
    publicKey: deviceKey.openSshPublic,
    deviceName: 'integration-phone',
  );
  await server.start(); // EmbeddedSshServer(loopback, port 0, _pipePtySpawner 同 pairing 测试)

  // 2) 桌面事件 server：AsyncDispatcher + AgentPresenceProjection（镜像
  //    event_transport_server_test 的 Harness），真实 loopback bind + 广告文件
  final dispatcher = AsyncDispatcher()..start();
  addTearDown(dispatcher.stop);
  final presence = AgentPresenceProjection();
  dispatcher.registerFamily<AgentPresenceKind>(
    AgentPresenceKind.working.runtimeType,
    presence,
  );
  final eventServerRoot = Directory.systemTemp.createTempSync('tp-event-home-');
  addTearDown(() => eventServerRoot.delete(recursive: true).catchError((_) {}));
  final transportServer = EventTransportServer(
    dispatcher: dispatcher,
    presence: presence,
    fs: LocalFilesystem(),
    advertisementPath:
        '${eventServerRoot.path}/event-transport.json',
    codecs: const [AgentPresenceTransportCodec()],
  );
  await transportServer.start();
  addTearDown(transportServer.stop);

  // 3) 预置一条 presence，订阅快照应携带它
  presence.handle(
    const AgentPresenceEvent(
      seat: PresenceSeatKey(sessionId: 's1', memberId: 'm1'),
      eventKind: AgentPresenceKind.working,
      timestamp: _epoch,
    ),
  );

  // 4) 手机侧：dartssh2 经嵌入式 sshd forwardLocal('127.0.0.1', port)（即
  //    openSshEventTransportChannel 的底层动作），再走订阅握手
  final ssh = SSHClient(
    await SSHSocket.connect('127.0.0.1', server.port),
    username: 'dev-user',
    identities: [SSHKeyPair.fromPem(deviceKey.pem).single],
    onVerifyHostKey: (_, __) => true,
  );
  addTearDown(ssh.disconnect);
  await ssh.authenticated;
  final advertisement =
      jsonDecode(
            await File('${eventServerRoot.path}/event-transport.json')
                .readAsString(),
          )
          as Map<String, Object?>;
  final port = (advertisement['port'] as num).toInt();
  final forward = await ssh.forwardLocal('127.0.0.1', port);
  addTearDown(forward.close);
  forward.sink.add(utf8.encode(
    '{"type":"subscribe","families":["agentPresence"]}\n',
  ));

  // 5) 断言快照推送经 direct-tcpip 到达（wire 编码见 AgentPresenceTransportCodec）
  final lines = await utf8.decoder.bind(forward.stream).takeWhile(
    (line) => !line.trim().contains('snapshotEnd'),
  ).join();
  expect(lines, contains('"op":"set"'));
  expect(lines, contains('"kind":"working"'));
  expect(lines, contains('"sessionId":"s1"'));
});

final _epoch = DateTime.utc(2026);
```

（`AgentPresenceTransportCodec` 无字段 → 隐式 const 构造，`const [...]` 有效；若 analyzer 报非 const，去掉 `const`。）

- [ ] **Step 2: 确证失败**

运行迁移后的集成测试（需 Flutter 引擎，只能经 `run_tests.dart`）：
Run: `cd client && dart run tool/run_tests.dart --tags integration test/integration/embedded_event_transport_test.dart`
Expected: `SSHChannelOpenError(... 'direct-tcpip' is not supported)` 或 subscribe 后无快照 → 失败。

- [ ] **Step 3: 验证转绿**

（本步在 Task 3+4 完成后运行，直接看绿。）Run 同 Step 2。
Expected: `op:set working` 到达；日志不再出现 `'direct-tcpip' is not supported` WARN。

- [ ] **Step 4: 全量 app 回归**

Run: `cd client && dart analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/services/event/ test/services/connect/ test/integration/embedded_event_transport_test.dart`
Expected: 全绿。

- [ ] **Step 5: Commit**

```bash
cd client && git add test/integration/embedded_event_transport_test.dart && git commit -m "test(connect): end-to-end event push over direct-tcpip"
```

## Task 6: 收尾（文档 + 全量 + 对照复核）

**Files:**
- Modify: `client/packages/tp_sshd/README.md`（`bindServerSocket` 行改为 `forwarding` 表面）
- Modify: `docs/superpowers/specs/2026-09-12-direct-tcpip-forwarding-design.md`（如实施中发现新不一致，回写）

- [ ] **Step 1: tp_sshd 最终回归**

Run: `cd client/packages/tp_sshd && dart analyze && dart test`
Expected: 全绿。

- [ ] **Step 2: app 最终回归（后台启动）**

Run: `cd client && dart run tool/run_tests.dart` （全量，放后台；期间做 Step 3-4）
Expected: 提交前全量无新增失败。

- [ ] **Step 3: OpenSSH 对照复核**

对照 `/tmp/opencode/openssh`：`server_request_direct_tcpip`（serverloop.c:418）、`channel_connect_to_port`（channels.c:4790）、`connect_to_helper`（channels.c:4747）、`AllowTcpForwarding` 表（servconf.c:1086）。逐项核对：门控顺序、reason 码、拨号失败不动连接、端口界、originator 仅日志。发现差异 → 改实现并回写 spec。

- [ ] **Step 4: README 更新**

`client/packages/tp_sshd/README.md` 的配置表：`bindServerSocket` 行改为 `SSHForwardingConfig`（`allowTcpForwarding` / `permitOpen` / `dialSocket` / `bindServerSocket` / `dialTimeout`），并加一行 direct-tcpip 说明（reason 1/2 语义）。

- [ ] **Step 5: Commit**

```bash
cd client && git add client/packages/tp_sshd/README.md docs/superpowers/specs/2026-09-12-direct-tcpip-forwarding-design.md && git commit -m "docs(tp_sshd): document forwarding config surface"
```

（若 Step 2 全量有失败，先修再提交，绝不带着红灯收尾。）