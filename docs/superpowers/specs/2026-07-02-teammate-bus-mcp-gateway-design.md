# Teammate-Bus MCP Gateway 设计

> 状态：**已实现** · 日期：2026-07-02  
> 上游：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §7 反向隧道、§7.1 传输层  
> 实现计划：[docs/superpowers/plans/2026-07-02-teammate-bus-mcp-gateway.md](../plans/2026-07-02-teammate-bus-mcp-gateway.md)

## 1. 问题与目标

mixed 团队每个会话原先各自 `HttpServer.bind(0)` 起一个 loopback `TeammateBusMcpServer`，N 个 mixed 会话 = N 个动态端口。远程成员经 SSH 反向隧道回连时，每 mount 还要再包一层 token guard 和 raw-socket listener，端口与生命周期难管。

**目标：** App 进程内只保留**一个** loopback MCP gateway，按 `sessionId`（本地）或 per-session `token`（远程）把请求路由到该会话的 `TeammateBusMcpHandler`。`TeamBus` 仍是每 mixed 会话一个 in-process 实例；变的只是 MCP 入站层。

| 之前 | 之后 |
|------|------|
| 每 tab 一个 `TeammateBusMcpServer` + 动态 HTTP/raw 口 | 单例 `TeammateBusMcpGateway`（`app_shell.dart` 启动时 `ensureStarted()`） |
| 远程 mount 自带 `BusHttpTokenGuard` | Gateway `TeammateBusSessionRegistry` 统一 `token → sessionId` |
| MCP URL 因会话而异 | 所有 mixed 会话共用同一 `mcpEndpoint` / `idleEndpoint` / `rawSocketPort` |

## 2. 组件

```
app_shell
  └─ TeammateBusMcpGateway (singleton)
        ├─ HTTP  /mcp, /idle  @ 127.0.0.1:<httpPort>
        ├─ raw socket (multiplexed) @ 127.0.0.1:<rawPort>
        ├─ TeammateBusSessionRegistry   sessionId ↔ handler ↔ token
        └─ per-session TeammateBusMcpHttpDelegate (SSE wait streams)

TabTeamBusCoordinator.installBusForTab
  ├─ TeamBus + TeammateBusMcpHandler (per session, unchanged)
  └─ gateway.register(sessionId, handler) → TeammateBusSessionRegistration { token }

RemoteBusMount (per remote member)
  └─ reverse tunnel → gateway.httpPort / gateway.rawSocketPort + registration.token
```

关键文件：

| 文件 | 职责 |
|------|------|
| `teammate_bus_mcp_gateway.dart` | 单端口 HTTP + raw socket 监听与路由 |
| `teammate_bus_session_registry.dart` | `register` / `unregister`、token 生成与失效 |
| `teammate_bus_mcp_http_delegate.dart` | 单会话 HTTP/SSE（从旧 `TeammateBusMcpServer` 抽出） |
| `teammate_bus_mcp_config.dart` | `X-Session` / `X-Member` / `X-Bus-Token` 常量与 MCP dict 构建 |
| `tab_team_bus_coordinator.dart` | mixed 会话 register；`disposeSessionBus` → `unregister` |

## 3. 路由头（routing contract）

### 3.1 本地成员（loopback HTTP 或 stdio bridge）

```
POST http://127.0.0.1:<gatewayPort>/mcp
POST http://127.0.0.1:<gatewayPort>/idle
Headers:
  X-Session: <appSessionId>
  X-Member:  <rosterMemberId>
```

长阻塞 CLI（claude 等）走 `teammate_bus_bridge` stdio：`--session <id> --member <id> --bus-url <gateway /mcp>`，桥在转发时补上 `X-Session`。

缺少 `X-Session` 且无有效 `X-Bus-Token` → **400**。

### 3.2 远程成员 — HTTP（cursor 门铃式）

经反向隧道打到远程 loopback，再透回 App 侧 gateway **固定 HTTP 口**：

```
POST http://127.0.0.1:<remoteTunnelPort>/mcp   # tunnels → gateway httpPort
Headers:
  X-Bus-Token: <per-session token from registration>
  X-Member:    <rosterMemberId>
```

Gateway：`token → sessionId` → 该会话 delegate。无需 per-mount `BusHttpTokenGuard`。

### 3.3 远程成员 — raw socket（长阻塞 CLI）

所有远程 relay 隧道到**同一** `gateway.rawSocketPort`。连接后首行 JSON 握手（与旧设计相同，token 仍 per-session）：

```json
{"token":"<registration.token>","memberId":"<rosterMemberId>"}
```

`BusRawSocketServer.multiplexed` 经 registry 解析 token 后交给对应 handler。

## 4. 生命周期

| 阶段 | 行为 |
|------|------|
| **App 启动** | `TeammateBusMcpGateway()` + `ensureStarted()`（在 `ChatCubit` 之前）；绑定 loopback `0` 一次，进程存活期间端口不变 |
| **打开 mixed 会话** | `installBusForTab`：建 `TeamBus` + `TeammateBusMcpHandler` → `gateway.register` → `tab.busSessionRegistration` 保存 token |
| **成员 launch** | 本地 MCP config 用 `gateway.mcpEndpoint` + `X-Session`；远程用 `buildRemoteBusMount(gateway, registration)` |
| **关闭会话 / tab dispose** | `disposeSessionBus(sessionId)` → `unregister`：撤销 token、取消该会话 SSE wait 流、`TeamBus.dispose` |
| **第二 mixed 会话** | 再 `register` 另一 `sessionId`；**HTTP/raw 口与第一个相同**，靠头部分发 |

`hasTeamBusResources` / `teammateBusMcpEndpointForSession` 以 `gateway.isSessionRegistered(sessionId)` 为准；未注册则 endpoint 为 `null`。

## 5. 远程隧道（与 gateway 的关系）

拓扑不变（总线仍在 App 进程），变的只是隧道**本地目标**从「每会话动态口」改为「gateway 固定两口」：

```
本地 App
  ├─ TeamBus (per session, in-process)
  └─ TeammateBusMcpGateway @ 127.0.0.1:<httpPort> + :<rawPort>
              ▲
              │ SSH forwardRemote(0) — 每远程成员一个远程 loopback <P>
              │   HTTP 隧道  → local <httpPort>
              │   raw 隧道   → local <rawPort>
   远程机 ────┘
     └─ CLI：127.0.0.1:<P> + token（HTTP 或 relay stdio）
```

- **长阻塞**（claude / codex / opencode / flashskyai）：raw 隧道 + 远程 relay（socat / 静态二进制）。
- **门铃式**（cursor）：单 HTTP 隧道，短请求 `/mcp` 与 `/idle`。
- **鉴权**：`registration.token` 在 register 时生成，`unregister` 即失效；共享主机上仅靠 `X-Member` 不足，必须带 token。

## 6. 验收要点

1. 两个 mixed 会话同时打开 → `lsof` 仅见**一个** teammate-bus HTTP listener。
2. 同 gateway URL、不同 `X-Session` → 消息只进对应 `TeamBus` inbox。
3. `unregister(sessionA)` 不取消 session B 上活跃的 `wait_for_message` SSE。
4. 远程长阻塞：`token` 握手 + relay → `wait_for_message` 可跨会话小时级阻塞。
5. 每次 connect 从 `gateway.mcpEndpoint` 重新生成 MCP config（避免缓存旧 per-session 端口）。

## 7. 非目标

- 固定 well-known 端口号（仍 `bind(0)`，进程内稳定即可）。
- 跨会话共享队列或总线合并。
- native（非 mixed）Claude swarm 迁到 gateway。
