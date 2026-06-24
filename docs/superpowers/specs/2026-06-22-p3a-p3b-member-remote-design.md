# 远程执行架构 · P3a+P3b 设计稿（成员→目录分配 + 反向隧道，含修复 Android mixed）

> 状态：**已澄清待实现** · **最优终态、零向后兼容** · POSIX 优先 · 建立在分支 `feat/p1-p2-runtime-context`（3c6ed00，预备+P0+P1+P2 已提交）之上
> 上游设计：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §4.1 成员位置、§5.3 远程 preflight（部分）、§7/§7.1 反向隧道与 stdio relay、§12 P3 行、§11 风险
> 决策来源：2026-06-22 用户就 P3 范围拍板（P3a+P3b、POSIX 优先、不含跨机产物、凭证 per-target opt-in、relay 能力位门控）

## 0. 范围（本轮 = P3a + P3b）

| 子阶段 | 内容 | 解锁 |
|---|---|---|
| **P3a** | `AppSession.folderAssignments` + 每成员按其分配目录解析**自己的工作目录与 target**（一个 agent 一台机）；修复 CLI-state 入口的 session/member 解析缺陷 | per-member 工作目录 / git worktree；成员→机器模型 |
| **P3b** | 反向隧道 `forwardRemote(0)` + bus raw-socket（行分隔 JSON-RPC）+ per-session token + relay 分层分发；**修复现网已坏的 Android mixed** | 远程成员协调 + Android mixed 修复 |

**明确不在本轮（后续闸门）**：P3c 远程 preflight 完整版/CLI 定位泛化 5 CLI/ancestry·凭证·skills 物化到非 home 工作机；P3d 跨机产物 MCP；P3e Windows 远程（`remoteOs` 探测/symlink→copy/windows 静态 relay）；P4 连接弹性。`remoteOs` 保持 nullable 占位。

> **P3a/P3b 与 P3c 的依赖**：**修 Android mixed 只需 P3b**——成员都跑在 home ssh 机上，app-data/CLI/config 已在 home（本机），无需跨机物化。**桌面真·成员远程**（成员落在**非 home** 机）要等 P3c 把 CLI/config 物化到那台工作机才能端到端启动。故本轮 P3b 的端到端可用目标锁定在 **Android mixed（成员在 home ssh）** 与 **桌面成员落 home-local 或 home 同机** 两种"成员机 = home 机或本地"情形；成员落**异于 home 的远程机**留 P3c。

## 1. P3a：成员→目录分配 + 每成员解析

### 1.1 数据模型

```dart
// AppSession 新增（启动态快照，便于 resume 定位）
final Map<String, List<String>> folderAssignments; // memberId -> [folderPath...]
```

- 每成员分到一组**同机**目录：第一个 = 工作目录，其余 = `--add-dir`；**缺省继承**工作区全部 folder（未分配成员 = 用 `workspace.folderPaths`）。
- 约束：一成员的所有分配目录必须同 `targetId`（一个 agent 一台机）；分配是**启动时**确定，不做跨 target 迁移（要换机即重新分配/重建）。
- `toJson`/`fromJson`：仅写 `folderAssignments`（非空时），零兼容读旧。

### 1.2 每成员 target / 工作目录解析

今天 `session_lifecycle_service._workTargetFor(session)` 用 `session.folders.first.targetId`（**整会话一 target**，P2）。P3a 泛化为**按成员**：

```dart
// 解析成员的工作面 target：其分配目录的 targetId（缺省 = 工作区主 folder 的 target）
RuntimeTarget _workTargetForMember(AppSession s, Workspace ws, String memberId) {
  final assigned = s.folderAssignments[memberId];
  final firstPath = (assigned != null && assigned.isNotEmpty)
      ? assigned.first
      : (ws.folders.isEmpty ? null : ws.folders.first.path);
  final folder = ws.folders.firstWhereOrNull((f) => f.path == firstPath) ?? ws.folders.firstOrNull;
  final id = folder?.targetId ?? RuntimeTarget.localId;
  return _runtimeTargetFromId(id); // 复用现有 runtimeKindOfId/ssh/wsl/local 构造
}
// 成员工作目录 = assigned.first（缺省 ws.folders.first.path）；--add-dir = assigned.skip(1)（缺省 extraFolderPaths）
```

- `_resolveRoots({AppSession? session, String? memberId})`：当 `memberId` 给定走 `_workTargetForMember`，否则回退 `_workTargetFor(session)`（整会话，personal/无 roster 情形）。
- **prepareLaunch / _scheduleMemberConnect** 串入 `memberId`：每成员 launch 用其 `forTarget(memberTarget)` 上下文 + 其工作目录。runtime 树已按 `memberId` 分（`RuntimeLayout.sessionRuntimeToolDir(..., memberId)`），天然 per-member。

### 1.3 CLI-state 入口：在已传 session 的基础上扩展 memberId（**不重复修缺陷**）

> **协调注记（team-lead 2026-06-22）**：cursor reviewer 发现的 CLI-state 缺陷（`hasCliState`/`destroyCliState`/`destroyStandaloneCliState` 未传 session→误打 home）**已由另一 builder 在 `feat/p1-p2-runtime-context` 上作为 P2 follow-up 单独修好**；P3 分支从修好后切出。故 P3a **不重复修该缺陷**。

P3a 在这些入口**已透传 `session`** 的现状上，仅**追加 `memberId`**（团队 roster 情形）：调 `_resolveRoots(session: session, memberId: memberId)`，使 has/destroy 命中**成员**工作面 context 而非整会话/home。**验收**：多成员跨机时，has/destroy CLI-state 命中**该成员**的工作面 context。

### 1.4 UI（最小）

成员→目录/机器分配：在会话/成员配置加 per-member"目标 + 工作目录"选择（来自 `registry.listTargets()` + 工作区 folders）。P3a 最小可用即可（模型 + 解析为重点；分配 UI 简洁）。未分配成员沿用工作区默认（行为不变）。

## 2. P3b：反向隧道 + bus raw-socket + token + relay（修 Android mixed）

### 2.1 现状坏点（已核实）

- MCP server 绑死 `127.0.0.1`（`teammate_bus_mcp_server.dart:22/23/31` `HttpServer.bind(loopbackIPv4,0)`）。
- `session_launch_service._busMcpServerConfig`（:910-931）仅 `claude + localNative` 用 stdio 桥；其余（非 claude / SSH/WSL 远端）回落 **HTTP@127.0.0.1**，经 SFTP 写到远程 fs → 远程成员读到**自己机的 loopback**，连不回本地 bus。**这就是 Android mixed 坏因**，也是桌面成员远程的拦路点。

### 2.2 拓扑（不分布式化 bus，只让远程够得着本地 bus）

```
本地 App 进程
  ├─ TeamBus（in-process，不动）
  ├─ teammate-bus HTTP MCP @127.0.0.1（保留，本地/cursor 用）
  └─ bus raw-socket @127.0.0.1:<Q>（新增：行分隔 JSON-RPC，复用 wait_for_message 逻辑，加 token 校验）
              ▲ SSH remote forward（反向隧道）：远程 127.0.0.1:<P> → 本地 127.0.0.1:<Q>
   远程机 ────┘
     └─ 成员 CLI ── stdio ── relay（socat/nc 或 bundle 静态）── 127.0.0.1:<P> ── 隧道 ── 本地 bus
```

### 2.3 反向隧道抽象（**可测试性核心**）

把 SSH 细节藏在接口后，使隧道泵可脱离真实远程机单测：

```dart
// lib/services/team_bus/remote/reverse_tunnel.dart
abstract class ReverseTunnel {
  Future<int> open();                 // forwardRemote(0) → 返回远程实际绑定端口 <P>
  Stream<TunnelChannel> get channels; // 每来一个远程连接一个 channel
  Future<void> close();
}
abstract class TunnelChannel { Stream<List<int>> get input; void add(List<int> data); Future<void> close(); }

// 真实实现：包 dartssh2 SSHClient.forwardRemote(port:0) → SSHRemoteForward.assignedPort + .connections(SSHForwardChannel)
class SshReverseTunnel implements ReverseTunnel { SshReverseTunnel(SSHClient client, {String bindHost='127.0.0.1'}); ... }
// 伪实现（测试）：FakeReverseTunnel.open() 返回固定端口；emitChannel(FakeChannel) 注入内存 channel
```

**隧道泵**：消费 `channels`，每个 channel 连一条本地 socket 到 bus raw-socket(`127.0.0.1:<Q>`)，双向 pipe（即 dartssh2 `example/forward_remote.dart` 模式）。泵逻辑对 `ReverseTunnel` 抽象编程 → 用 `FakeReverseTunnel` + 内存 channel + 本地 raw-socket server 可**完整单测**无需真实 SSH。

### 2.4 bus raw-socket 传输（行分隔 JSON-RPC + token）

- 在 MCP server 旁新增 **raw-socket 监听**（`ServerSocket.bind(loopbackIPv4, 0)` → `<Q>`），每连接按**行分隔 JSON-RPC**（stdio MCP 的线格式）解析，**复用** `TeammateBusMcpHandler` 的方法分发与 `wait_for_message` 阻塞逻辑——只换 framing 入口（HTTP body → 行分隔流）。
- **per-session token**：raw-socket 连接首帧须带 `{"token":"<sessionToken>"}` 握手（或连接参数 `--token`）；bus 校验通过才接受该 socket，否则断开。token 每 session 随机生成、随 session 失效。**防同机其它本地用户冒充/窃听**（隧道远程 `127.0.0.1:<P>` 对该远程机所有本地用户可见）。

### 2.5 relay 分层分发（能力位门控）

- 新增 CLI 能力位 **`longBlockingWaitForMessage`**（放 `registry/capabilities/`，如 `bus_transport_capability.dart`）：`claude/flashskyai/codex/opencode = true`，**`cursor = false`**（门铃式、idle-at-prompt、不长阻塞）。
- **长阻塞 CLI（需 relay）**：远程成员 MCP 配置 = 经 relay 走 stdio ↔ `127.0.0.1:<P>`。relay 分层：① 探测远程 `socat`/`nc`（零分发，`socat STDIO TCP:127.0.0.1:<P>`）；② 缺则用 **bundle 静态 relay** 按远程 arch/OS 物化（本轮仅 **linux-x64/arm64**；windows/macos 留 P3e/后续）；③ 都没有 → 清晰报错。
- **门铃式 cursor（免 relay）**：远程时直接 **HTTP 短请求 over 隧道**（`127.0.0.1:<P>` 的 HTTP），无长阻塞 → 无 fetch 超时问题。
- 判定**能力化**，不散落 `if (cli==)`。

### 2.6 远程成员启动序（修 `_busMcpServerConfig`）

```
成员 m 的 target = _workTargetForMember(...)（P3a）
若 m.target == local/home-本地           → 现状（stdio 桥 / 本地 HTTP），不变
若 m.target 为 ssh（远程，本轮=home ssh 或同机）：
  1. registry.forTarget(m.target) 复用/建 SSHClient（P2 已持有）
  2. tunnel = SshReverseTunnel(client); P = await tunnel.open()  // forwardRemote(0)
  3. 启动隧道泵（channels → 本地 raw-socket <Q>）
  4. token = session token
  5. 长阻塞 CLI：写 m 的 MCP 配置 = relay(stdio↔127.0.0.1:P, --token)；
     cursor：写 HTTP@127.0.0.1:P + token
  6. launch m 的 CLI（其 stdin 门铃仍由本地 shell.writeln 透 SSH 通道，§门铃不动）
隧道/泵生命周期挂该 session；session 结束 close + cancelForwardRemote（与 registry.dispose 协同）
```

- **门铃不动**：`tab_team_bus_coordinator.injectMemberStdin`→`shell.writeln`（:201）在本地 shell、写进 SSH 通道即达远程成员，无需改。
- **Android mixed**：home=ssh，成员在 home ssh 机；上面"m.target 为 ssh"分支即覆盖——远程成员经隧道+relay 连回手机 bus，**坏点消除**。

## 3. 关键文件

| 文件 | 动作 |
|------|------|
| `lib/models/app_session.dart` | + `folderAssignments` 字段 + json |
| `lib/services/session/session_lifecycle_service.dart` | `_workTargetForMember` + `_resolveRoots({session, memberId})`；CLI-state 入口透传 session/memberId（修缺陷）；每成员工作目录 |
| `lib/cubits/chat/session_launch_service.dart` | `_busMcpServerConfig` 按成员 target 选 relay-over-tunnel / HTTP-over-tunnel / 本地；串 memberId |
| `lib/services/team_bus/remote/reverse_tunnel.dart` | 新增 `ReverseTunnel`/`TunnelChannel` 抽象 + `SshReverseTunnel`（包 dartssh2 forwardRemote）+ 泵 |
| `lib/services/team_bus/remote/bus_raw_socket_server.dart` | 新增 raw-socket（行分隔 JSON-RPC + token 握手），复用 `TeammateBusMcpHandler` |
| `lib/services/team_bus/remote/relay_provisioner.dart` | 新增 relay 分层（探测 socat/nc → bundle 静态 relay 物化 linux-x64/arm64） |
| `lib/services/cli/registry/capabilities/bus_transport_capability.dart` | 新增能力位 `longBlockingWaitForMessage`（各 CLI 定义里赋值；cursor=false） |
| `lib/services/team_bus/mcp/teammate_bus_mcp_server.dart` | 旁挂 raw-socket server；token 生成/校验接入 |
| 成员配置 UI（会话/成员） | per-member target+工作目录分配（最小） |

## 4. 测试策略（团队三重点）

### 4.1 (a) Android mixed 修复的可验证性

- **单测**：给定一个成员 target=ssh（mock），`_busMcpServerConfig` 产出的 MCP 配置指向 **隧道端口 `127.0.0.1:<P>`**（relay 或 HTTP），**不再**是裸 bus 的 127.0.0.1——断言坏点已换。
- **集成（无真机）**：`FakeReverseTunnel` 开端口 `<P>`，注入一个内存 `TunnelChannel`，泵把它连到真实本地 `BusRawSocketServer(<Q>)`；从 channel 写一条 `wait_for_message` JSON-RPC，断言：① bus 校验 token 通过；② 该 worker 真正 park 在 `wait_for_message`；③ 另一成员 `send_message` 后，channel 收到投递帧。**这证明"远程成员经隧道连回本地 bus 并收发"全链路**，不依赖真实 SSH。
- **手验金路径**：Android mixed 团队，远程成员实际调 `wait_for_message` 不再 transport-dropped、能收到 lead 的派发/消息。

### 4.2 (b) 跨机隧道可测试性（不依赖真实远程机）

- `ReverseTunnel` 抽象 + `FakeReverseTunnel`：泵逻辑、channel↔raw-socket pipe 全内存单测。
- **token 门控单测**：raw-socket server 对**无/错 token** 首帧立即断开；对**正确 token** 接受并进入 JSON-RPC 分发。
- **行分隔 JSON-RPC framing 单测**：半包/粘包/多行一次到达的切分正确；与 stdio MCP 线格式一致。
- `SshReverseTunnel` 对 dartssh2 的薄包装单测：用 dartssh2 既有 mock/loopback（若有）或仅断言它把 `SSHRemoteForward.assignedPort`/`.connections` 正确映射为 `open()`/`channels`（薄封装，逻辑在抽象层测）。

### 4.3 (c) 每成员工作目录解析对 forTarget 的影响

- `_workTargetForMember` 单测：分配目录在 ssh folder → 成员 target=ssh；未分配 → 工作区主 folder target；多成员分到不同 folder/机 → 各自 target 独立。
- **CLI-state 缺陷回归**：`hasCliState`/`destroyCliState`/`destroyStandaloneCliState` 在远程工作区命中**工作面** context（断言用的 fs/root = forTarget 而非 home）。
- 既有 P2 `debugResolveWorkContext` 测试扩展为按 memberId。

### 4.4 全量

`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。隧道/raw-socket 集成测试用 `@Tags(['integration'])` 若需真实 socket（本地 loopback 可在普通测试内，无需真 SSH）。

## 5. 凭证 / relay opt-in（Q4，本轮定调，物化落 P3c）

- 凭证推远程 = **per-target 显式 opt-in + UI 明示**（默认不铺 key）。本轮 P3a/P3b 不做凭证物化（成员在 home ssh，凭证已在 home）；**接口预留** opt-in 标志，P3c 实装物化。
- relay 分发分层（§2.5）；本轮仅 linux-x64/arm64 静态 relay + socat/nc 探测；macos/windows 静态 relay 留 P3e/后续。

## 6. 不在本轮范围（重申）

P3c（远程 preflight 完整/CLI 定位泛化 5 CLI/ancestry·凭证·skills 物化到非 home 工作机）、P3d（跨机产物）、P3e（Windows 远程/`remoteOs` 探测/symlink→copy/windows relay）、P4（连接弹性）。成员落**异于 home 的远程机**的端到端启动需 P3c，本轮不覆盖。
