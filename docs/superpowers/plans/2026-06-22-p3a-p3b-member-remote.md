# P3a+P3b — 成员→目录分配 + 反向隧道（含修复 Android mixed）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** P3a 让每成员按其分配目录解析自己的工作目录与 target（`AppSession.folderAssignments`，一个 agent 一台机），并修复 CLI-state 入口的 session/member 解析缺陷；P3b 用反向隧道 + bus raw-socket(行分隔 JSON-RPC) + per-session token + 分层 relay 让远程成员连回本地 bus，**顺手修好现网已坏的 Android mixed**。POSIX 优先、零兼容。

**Architecture:** `folderAssignments: Map<memberId, List<folderPath>>` 决定成员机器；`session_lifecycle` 按成员 `forTarget` 解析。`ReverseTunnel` 抽象（包 dartssh2 `forwardRemote(0)`）+ 内存 `FakeReverseTunnel` 使隧道泵脱真机可测；bus 旁挂 `BusRawSocketServer`（复用 `TeammateBusMcpHandler`，token 握手）；`_busMcpServerConfig` 按成员 target 选 relay-over-tunnel(长阻塞 CLI) / HTTP-over-tunnel(cursor) / 本地。relay 能力位 `longBlockingWaitForMessage` 门控。

**Tech Stack:** Dart / Flutter，vendored `dartssh2`（`SSHClient.forwardRemote`/`SSHRemoteForward`/`SSHForwardChannel`），`dart:io ServerSocket/Socket`，`package:flutter_test`/`package:test`。

**Branch:** 基于 `feat/p1-p2-runtime-context`（3c6ed00）——切 `feat/p3-member-remote`。

## Global Constraints

- **零兼容、最优终态**：`folderAssignments` 只写新形状；不读旧。
- **POSIX 优先**：relay 静态二进制本轮仅 linux-x64/arm64 + socat/nc 探测；**不**做 Windows/macos relay、不做 `remoteOs` 探测（`remoteOs` 保持 nullable 占位）——属 P3e。
- **本轮端到端可用边界**：成员 target = **home 本地 / home ssh（成员在 home 机）**；成员落**异于 home 的远程机**的 CLI/config 物化属 P3c，不在本轮（Android mixed 成员在 home ssh，已覆盖）。
- **不含**：跨机产物 MCP（P3d）、凭证物化到远程（P3c；本轮仅预留 opt-in 接口）、P4 连接弹性。
- 设计权威：[docs/superpowers/specs/2026-06-22-p3a-p3b-member-remote-design.md](../specs/2026-06-22-p3a-p3b-member-remote-design.md)。
- 完成判据（每任务+总验收）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。真实 loopback socket 测试可在普通测试内（无需真 SSH）；若某测试需长时端口可标 `@Tags(['integration'])`。
- 频繁提交：每任务 ≥1 commit。

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `client/lib/models/app_session.dart` | `folderAssignments` 字段 | 改 |
| `client/lib/services/session/session_lifecycle_service.dart` | `_workTargetForMember` + `_resolveRoots({session,memberId})` + CLI-state 入口修复 + 每成员工作目录 | 改 |
| `client/lib/cubits/chat/session_launch_service.dart` | `_busMcpServerConfig` 按成员 target 选传输 + 串 memberId | 改 |
| `client/lib/services/team_bus/remote/reverse_tunnel.dart` | `ReverseTunnel`/`TunnelChannel` 抽象 + `SshReverseTunnel` + 泵 | 新增 |
| `client/lib/services/team_bus/remote/bus_raw_socket_server.dart` | raw-socket（行分隔 JSON-RPC + token） | 新增 |
| `client/lib/services/team_bus/remote/relay_provisioner.dart` | relay 分层（探测 → bundle 静态 relay 物化） | 新增 |
| `client/lib/services/cli/registry/capabilities/bus_transport_capability.dart` | `longBlockingWaitForMessage` 能力位 | 新增 |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_server.dart` | 旁挂 raw-socket server + token | 改 |
| 成员配置 UI | per-member target+工作目录分配（最小） | 改 |

---

## Phase P3a — 成员→目录分配 + 每成员解析

### Task 1: `AppSession.folderAssignments`

**Files:** Modify `client/lib/models/app_session.dart`; Test `client/test/models/app_session_folder_assignments_test.dart`

**Interfaces:** Produces `final Map<String,List<String>> folderAssignments;` on `AppSession` + ctor/copyWith/json.

- [ ] **Step 1: 失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('folderAssignments round-trips and defaults empty', () {
    final s = AppSession(
      sessionId: 's1', workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/repo')],
      folderAssignments: const {'m1': ['/repo']},
      createdAt: 1,
    );
    expect(s.folderAssignments['m1'], ['/repo']);
    final r = AppSession.fromJson(s.toJson());
    expect(r.folderAssignments['m1'], ['/repo']);
    expect(AppSession.fromJson({'sessionId':'x','workspaceId':'w','folders':[{'path':'/a','targetId':'local'}],'createdAt':1}).folderAssignments, isEmpty);
  });
}
```

- [ ] **Step 2: 运行→失败**  `cd client && flutter test test/models/app_session_folder_assignments_test.dart` → FAIL（`folderAssignments` 未定义）。

- [ ] **Step 3: 实现** — 在 `AppSession` 加字段：ctor `this.folderAssignments = const {}`；`fromJson` 解析 `json['folderAssignments']`（`Map<String,List<String>>`，容错跳过非法项）；`toJson` `if (folderAssignments.isNotEmpty) 'folderAssignments': folderAssignments`；`copyWith` 加参；`==`/`hashCode` 用 `mapEquals`/`Object.hashAll(entries)`。

- [ ] **Step 4: 运行→通过** + 既有 app_session 测试。`cd client && flutter test test/models/`

- [ ] **Step 5: Commit** `git commit -m "feat: AppSession.folderAssignments (member->folder startup assignment)"`

---

### Task 2: 每成员 target / 工作目录解析（在已传 session 的基础上扩展 memberId）

> **协调注记（team-lead 2026-06-22）**：cursor reviewer 发现的 CLI-state 缺陷（`hasCliState`/`destroyCliState`/`destroyStandaloneCliState` 未传 session→误打 home）**已由另一 builder 在 `feat/p1-p2-runtime-context` 上作为 P2 follow-up 单独修好**（这些入口现已透传 `session` 给 `_resolveRoots`）。P3 分支从**修好后**的 P2 分支切出。故本 Task **不再重复修该缺陷**，而是在"已传 session"的现状上**扩展为按 `memberId` 解析**——避免重复改动/制造冲突。

**Files:** Modify `client/lib/services/session/session_lifecycle_service.dart`; Test `client/test/services/session/member_work_target_test.dart`

**Interfaces:** Consumes `folderAssignments`(Task 1), `Workspace.folders`, `RuntimeContextRegistry.forTarget`, 以及 P2 follow-up 后**已接收 `session`** 的 CLI-state 入口。Produces `_workTargetForMember(AppSession, Workspace, String memberId)`; `_resolveRoots({AppSession? session, String? memberId})`（在现有 `{session}` 签名上**加 `memberId`**）; CLI-state 入口**追加** `memberId` 透传（其 `session` 透传已就位，本 Task 只补 memberId）.

- [ ] **Step 1: 失败测试**

```dart
// 注入 fake forTarget 记录被请求的 target id。
test('member assigned to ssh folder resolves ssh work target', () async {
  // workspace.folders: [{path:/repo, targetId:'ssh:p1'}]; folderAssignments {m1:[/repo]}
  // _workTargetForMember(session, ws, 'm1').kind == ssh
});
test('unassigned member falls back to workspace first folder target', () async { ... });
test('hasCliState/destroyCliState resolve work context (not home) for remote workspace', () async {
  // 断言这些入口请求的是 forTarget(ws target) 的 ctx，而非 home
});
```

- [ ] **Step 2: 运行→失败**  `flutter test test/services/session/member_work_target_test.dart`

- [ ] **Step 3: 实现**
  - 加 `_workTargetForMember`（见设计稿 §1.2，含 `folderAssignments` 查 + 缺省工作区主 folder + `_runtimeTargetFromId` 复用 `runtimeKindOfId/ssh/wsl/local`）。
  - `_resolveRoots({AppSession? session, String? memberId})`：`memberId != null && session != null && workResolver != null` → `workResolver(_workTargetForMember(session, <workspace>, memberId))`；否则维持现 `_workTargetFor(session)` 分支。（workspace 由现有 launch 上下文取；若 `_resolveRoots` 无 workspace 句柄，传入 `Workspace` 或其 `folders`。）
  - **CLI-state 入口（不重复修缺陷）**：这些入口的 `session` 透传已由 P2 follow-up 修好；本 Task 仅在其调 `_resolveRoots(session: session)` 处**追加 `memberId`**（团队 roster 情形），即 `_resolveRoots(session: session, memberId: memberId)`，使 has/destroy 命中**成员**工作面 context。**不要**重新引入 session 透传（已存在）。
  - 每成员工作目录：launch 计划里 `workingDirectory` = 成员 `assigned.first`（缺省 `session.firstFolderPath`），`--add-dir` = `assigned.skip(1)`（缺省 `extraFolderPaths`）。

- [ ] **Step 4: 运行→通过** + 既有 session 测试（含 P2 `debugResolveWorkContext`）。`flutter test test/services/session/ && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/session`

- [ ] **Step 5: Commit** `git commit -m "feat: per-member work target/dir resolution; fix CLI-state home mis-resolution"`

---

### Task 3: 成员→目录分配 UI（最小）

**Files:** Modify 成员/会话配置（`grep -rn "memberShells\|member config\|TeamMemberConfig" lib/pages lib/widgets` 定位现成员配置面板）；Test widget 渲染/写回。

**Interfaces:** Consumes `registry.listTargets()`, `Workspace.folders`; writes `folderAssignments` via repo（`SessionRepository` 加 `setFolderAssignments(sessionId, Map)` 或随 createSession 入参）。

- [ ] **Step 1:** 加 `SessionRepository.setMemberFolderAssignment(sessionId, memberId, List<String> folderPaths)`（写 session manifest）。单测往返。
- [ ] **Step 2:** 成员配置面板加一个"目标 + 工作目录"选择（target 来自 `listTargets`，目录来自工作区 folders 过滤同 target）；未分配 = 继承工作区默认（占位文案）。
- [ ] **Step 3:** widget 测试：渲染 target 选项；选中写 `setMemberFolderAssignment`。
- [ ] **Step 4:** `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` → CLEAN+PASS。
- [ ] **Step 5: Commit** `git commit -m "feat: minimal per-member target/folder assignment UI"`

---

## Phase P3b — 反向隧道 + bus raw-socket + token + relay

### Task 4: `BusRawSocketServer`（行分隔 JSON-RPC + token）

**Files:** Create `client/lib/services/team_bus/remote/bus_raw_socket_server.dart`; Test `client/test/services/team_bus/bus_raw_socket_server_test.dart`

**Interfaces:** Consumes `TeammateBusMcpHandler`(现有方法分发/`wait_for_message`). Produces `class BusRawSocketServer { BusRawSocketServer({required TeammateBusMcpHandler handler, required String token}); Future<int> start(); /* loopback port */ Future<void> close(); }` — 每连接首帧校验 token，后续行分隔 JSON-RPC 透 handler。

- [ ] **Step 1: 失败测试**（token 门控 + framing + 收发）

```dart
test('rejects connection with missing/wrong token first frame', () async {
  final server = BusRawSocketServer(handler: fakeHandler, token: 'T');
  final port = await server.start();
  final sock = await Socket.connect('127.0.0.1', port);
  sock.add(utf8.encode('{"token":"WRONG"}\n'));
  // 断言 server 端断开（sock.done 完成 / 后续 JSON-RPC 不被处理）
});
test('accepts valid token then dispatches line-delimited json-rpc', () async {
  // 首帧 {"token":"T"}\n；再发一条 {"jsonrpc":"2.0","id":1,"method":"...","params":{}}\n
  // 断言 fakeHandler 收到该 method，并回写一行响应
});
test('framing splits half/coalesced lines correctly', () async { ... });
```

- [ ] **Step 2: 运行→失败**  `flutter test test/services/team_bus/bus_raw_socket_server_test.dart`

- [ ] **Step 3: 实现** — `ServerSocket.bind(InternetAddress.loopbackIPv4, 0)`；每 `Socket`：累积 buffer 按 `\n` 切行；**首行**必须是 `{"token":...}` 且 `== token` 否则 `socket.destroy()`；之后每行 `jsonDecode` → 复用 `TeammateBusMcpHandler` 的方法分发（与 HTTP 路径同一 handler，只换 framing），响应按行写回。`wait_for_message` 的长阻塞由 handler 既有逻辑提供（不在 framing 层加超时）。

- [ ] **Step 4: 运行→通过**  `flutter test test/services/team_bus/bus_raw_socket_server_test.dart`

- [ ] **Step 5: Commit** `git commit -m "feat: BusRawSocketServer (line-delimited JSON-RPC + per-session token)"`

---

### Task 5: `ReverseTunnel` 抽象 + `FakeReverseTunnel` + 隧道泵

**Files:** Create `client/lib/services/team_bus/remote/reverse_tunnel.dart`; Test `client/test/services/team_bus/reverse_tunnel_pump_test.dart`

**Interfaces:** Produces `abstract ReverseTunnel { Future<int> open(); Stream<TunnelChannel> channels; Future<void> close(); }`, `abstract TunnelChannel { Stream<List<int>> input; void add(List<int>); Future<void> close(); }`, `FakeReverseTunnel`（测试，`emitChannel`），`TunnelPump`（把每个 channel pipe 到 `127.0.0.1:<Q>` 的本地 socket）。`SshReverseTunnel` 留 Task 6。

- [ ] **Step 1: 失败测试**（泵把 channel ↔ 本地 raw-socket 双向 pipe）

```dart
test('pump pipes a tunnel channel to the local bus raw-socket end to end', () async {
  final server = BusRawSocketServer(handler: realHandlerOverFakeBus, token: 'T');
  final q = await server.start();
  final tunnel = FakeReverseTunnel(port: 12345);
  final pump = TunnelPump(tunnel: tunnel, localPort: q);
  await pump.start();
  final ch = FakeChannel();
  tunnel.emitChannel(ch);                       // 模拟远程来连
  ch.add(utf8.encode('{"token":"T"}\n'));       // 经隧道的 token 帧
  ch.add(utf8.encode('<a wait_for_message json-rpc>\n'));
  // 断言：另一成员 send_message 后，ch.input 收到投递帧（证明回环到本地 bus）
});
```

- [ ] **Step 2: 运行→失败**  `flutter test test/services/team_bus/reverse_tunnel_pump_test.dart`

- [ ] **Step 3: 实现** — 抽象 + `FakeReverseTunnel`（`open()` 返回构造端口，`emitChannel` 推到 `channels`）+ `TunnelPump`：监听 `tunnel.channels`，每 channel `Socket.connect('127.0.0.1', localPort)`，双向 `channel.input → socket.add` / `socket → channel.add`，任一端关则关另一端。

- [ ] **Step 4: 运行→通过**  `flutter test test/services/team_bus/reverse_tunnel_pump_test.dart`

- [ ] **Step 5: Commit** `git commit -m "feat: ReverseTunnel abstraction + pump (fake-tunnel testable)"`

---

### Task 6: `SshReverseTunnel`（包 dartssh2 forwardRemote）

**Files:** Modify `reverse_tunnel.dart`(加实现); Test `client/test/services/team_bus/ssh_reverse_tunnel_test.dart`

**Interfaces:** Produces `class SshReverseTunnel implements ReverseTunnel { SshReverseTunnel(SSHClient client, {String bindHost='127.0.0.1'}); }` — `open()` → `client.forwardRemote(host: bindHost, port: 0)` → `SSHRemoteForward.port` 作 `<P>`；`channels` 映射 `SSHRemoteForward.connections`(`SSHForwardChannel`) → `TunnelChannel`；`close()` → `cancelForwardRemote`.

- [ ] **Step 1: 失败测试**（薄封装映射；用 dartssh2 的可注入 forward 或 mock SSHClient）

```dart
// 用 mock SSHClient（或 dartssh2 的测试替身）断言：
// open() 调 forwardRemote(port:0) 并返回 assignedPort；
// 远程来一个 SSHForwardChannel 时 channels 发出一个 TunnelChannel，其 input/add 映射到 channel 的 stream/sink；
// close() 调 cancelForwardRemote。
```

- [ ] **Step 2: 运行→失败**

- [ ] **Step 3: 实现** — 薄封装；`SSHForwardChannel` 的 `stream`/`sink` ↔ `TunnelChannel.input`/`add`。（逻辑已在 Task 5 抽象层测；此处只测映射正确。）

- [ ] **Step 4: 运行→通过**

- [ ] **Step 5: Commit** `git commit -m "feat: SshReverseTunnel wrapping dartssh2 forwardRemote(0)"`

---

### Task 7: relay 能力位 + `RelayProvisioner`（分层分发，linux 静态）

**Files:** Create `bus_transport_capability.dart` + `relay_provisioner.dart`; 各 CLI 定义里赋能力位; Test `relay_provisioner_test.dart`

**Interfaces:** Produces `class BusTransportCapability { final bool longBlockingWaitForMessage; }`（claude/flashskyai/codex/opencode=true，cursor=false）；`class RelayProvisioner { Future<RelayPlan> provision({required Filesystem remoteFs, required SshCommandRunner run, required int tunnelPort, required String token, required String arch}); }` → 返回 relay 调用 argv（socat/nc 探测 → bundle 静态 relay 物化路径 → 报错）。

- [ ] **Step 1: 失败测试**

```dart
test('long-blocking capability: claude true, cursor false', () { ... registry.capability<BusTransportCapability>(CliTool.cursor).longBlockingWaitForMessage == false; });
test('relay provision prefers remote socat when present', () async {
  // run('command -v socat') 返回路径 → RelayPlan.argv 含 socat STDIO TCP:127.0.0.1:<P>
});
test('falls back to bundled static relay materialized by arch when no socat/nc', () async {
  // 探测都失败 → remoteFs 写入 bundle 静态 relay(linux-x64) → argv 指向物化路径
});
test('errors clearly when neither socat/nc nor bundled relay for arch', () async { ... });
```

- [ ] **Step 2: 运行→失败**

- [ ] **Step 3: 实现** — 能力位类 + 在各 `CliToolDefinition` 注册（cursor=false）；`RelayProvisioner`：① `run('command -v socat||command -v nc')` 探测；② 缺则按 `arch` 选 bundle 静态 relay（本轮仅 `linux-x64`/`linux-arm64`，bundle 资源占位 + 物化到 remoteFs）；③ 否则抛清晰错误。token 经 relay 连接参数/首帧下发。

- [ ] **Step 4: 运行→通过**

- [ ] **Step 5: Commit** `git commit -m "feat: BusTransportCapability + layered RelayProvisioner (linux static)"`

---

### Task 8: `_busMcpServerConfig` 按成员 target 选传输（修 Android mixed）

**Files:** Modify `client/lib/cubits/chat/session_launch_service.dart`, `client/lib/services/team_bus/mcp/teammate_bus_mcp_server.dart`; Test `client/test/cubits/member_remote_mcp_config_test.dart`

**Interfaces:** Consumes Task 4–7 + `_workTargetForMember`(Task 2) + per-session token. teammate_bus_mcp_server 旁挂 `BusRawSocketServer` 并暴露其端口 `<Q>` + token。

- [ ] **Step 1: 失败测试**（**Android mixed 修复可验证性核心**）

```dart
test('remote (ssh) long-blocking member MCP config points at tunnel port via relay (not raw 127.0.0.1 bus)', () async {
  // member target ssh; cli claude
  // _busMcpServerConfig 产出指向 127.0.0.1:<P>（隧道）经 relay 的 stdio 配置，
  // 且不等于本地 bus 的 endpoint
});
test('remote cursor member uses HTTP-over-tunnel (no relay)', () async { ... });
test('local member keeps existing stdio-bridge / local HTTP', () async { ... });
```

- [ ] **Step 2: 运行→失败**

- [ ] **Step 3: 实现**
  - teammate_bus_mcp_server：bootstrap 时旁挂 `BusRawSocketServer(handler, token)`、生成 per-session token、暴露 `rawSocketPort`/`token`。
  - `session_launch_service`：成员 launch 前，若 `_workTargetForMember(...)` 为 ssh（远程）：经 `registry.forTarget` 的 SSHClient 建 `SshReverseTunnel`→`open()` 拿 `<P>`、起 `TunnelPump(tunnel, localPort: rawSocketPort)`；按能力位：长阻塞 CLI → `RelayProvisioner.provision(...)` 写 relay-stdio MCP 配置（指 `127.0.0.1:<P>` + token）；cursor → HTTP@`127.0.0.1:<P>` + token。`_busMcpServerConfig` 改为接 `memberId`+`memberTarget` 并据此分支。隧道/泵生命周期挂 session，结束 `close`/`cancelForwardRemote`（与 `registry.dispose` 协同）。

- [ ] **Step 4: 运行→失败转通过 + analyze**  `flutter test test/cubits/member_remote_mcp_config_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 5: Commit** `git commit -m "feat: route remote member MCP via reverse tunnel/relay (fixes Android mixed)"`

---

### Task 9: 端到端集成测试（无真机证明远程成员连回本地 bus）

**Files:** Create `client/test/integration/member_remote_bus_loopback_test.dart`（`@Tags(['integration'])` 若需）

- [ ] **Step 1: 写集成测试** — `FakeReverseTunnel`+`TunnelPump`+真实 `BusRawSocketServer`+真实 `TeamBus`：
  1. 远程成员经隧道 channel 发 token 帧（正确）→ bus 接受；
  2. 发 `wait_for_message` → 该 worker park；
  3. lead `send_message(to: 远程成员)` → channel 收到投递帧；
  4. 错误 token → 立即断开。
  断言 1–4 全成立 → **证明远程成员经隧道连回本地 bus 并收发，Android mixed 拓扑可用**。

- [ ] **Step 2: 运行→通过**  `cd client && flutter test test/integration/member_remote_bus_loopback_test.dart`（或带 integration tag 的运行步骤，见 DEVELOPMENT.md）。

- [ ] **Step 3: 手验金路径文档** — 追加到设计稿 §4.1：Android mixed 团队，远程成员实际 `wait_for_message` 不再 transport-dropped、收到 lead 派发。

- [ ] **Step 4: Commit** `git commit -m "test: end-to-end remote-member bus loopback (Android mixed fix proof)"`

---

### Task 10: 全量验收 + 清理

- [ ] **Step 1: 全量** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` → CLEAN+PASS。
- [ ] **Step 2: 边界 grep 守卫** — 确认 `remoteOs` 仍仅占位（无探测分支）、无 Windows/macos relay 路径、无跨机产物 MCP（确属后续）。
- [ ] **Step 3: Commit** `git commit -m "chore: P3a+P3b acceptance sweep"`

---

## Self-Review

**Spec coverage:**
- §1.1 folderAssignments → Task 1 ✅；§1.2 每成员解析 → Task 2 ✅；§1.3 CLI-state 入口扩展 memberId（缺陷已在 P2 分支修，本轮不重复）→ Task 2 ✅；§1.4 分配 UI → Task 3 ✅
- §2.3 ReverseTunnel 抽象+泵 → Task 5；§2.3 SshReverseTunnel → Task 6 ✅
- §2.4 raw-socket+token → Task 4 ✅
- §2.5 relay 能力位+分层 → Task 7 ✅
- §2.6 `_busMcpServerConfig` 按成员选传输 + Android mixed 修复 → Task 8 ✅
- §4.1 Android mixed 可验证性 → Task 8 单测 + Task 9 集成 ✅；§4.2 隧道可测试性 → Task 4/5/6（fake tunnel、token、framing）✅；§4.3 每成员解析影响 → Task 2 ✅
- §5 opt-in/relay 分层（本轮 linux）→ Task 7（接口）✅；§6 边界 → Global Constraints + Task 10 ✅

**Placeholder scan:** relay 静态二进制 bundle 资源在 Task 7 标为"占位 + 物化"（实际二进制由 builder 随包；本轮 linux-x64/arm64）——明确边界非内容缺口。各核心类（raw-socket/tunnel/pump/capability）带具体测试与实现要点；dartssh2 映射在 Task 6 薄封装、逻辑在 Task 5 抽象层测。

**Type consistency:** `folderAssignments: Map<String,List<String>>`、`_workTargetForMember`、`_resolveRoots({session,memberId})`、`ReverseTunnel`/`TunnelChannel`/`TunnelPump`/`FakeReverseTunnel`/`SshReverseTunnel`、`BusRawSocketServer{start,close}`、`BusTransportCapability.longBlockingWaitForMessage`、`RelayProvisioner.provision` 跨任务一致。

**可测试性（团队三重点）落实:** (a) Android mixed → Task 8 单测(端点指向隧道) + Task 9 集成(全链路收发)；(b) 隧道不依赖真机 → ReverseTunnel 抽象 + FakeReverseTunnel + token/framing 单测(Task 4/5)；(c) 每成员解析 → Task 2 + CLI-state 缺陷回归。每任务结尾独立可运行验证命令。
