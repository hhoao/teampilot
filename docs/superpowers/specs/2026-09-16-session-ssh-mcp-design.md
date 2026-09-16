# Session SSH MCP 设计

- 日期：2026-09-16
- 状态：已批准
- 来源：把 [classfang/ssh-mcp-server](https://github.com/classfang/ssh-mcp-server) 的四个工具做成 TeamPilot 进程内 Dart MCP，仅给混合工作区的本机座位自动注入

## 目标

混合工作区里跑在本机的 CLI 座位，自动获得一个托管 MCP `ssh`，用来对工作区里的远程 `ssh:*` folder 执行命令和传文件。实现用 [mcp_dart](https://pub.dev/packages/mcp_dart) + 现有 dartssh2 / SSH profile，不跑 Node/`npx`。工作区可关掉注入（默认开）。

## 非目标

- 纯本地或纯远程工作区不注入（远程座位已经在目标机上）。
- 混合工作区的远程座位不注入，不做 SSH MCP 隧道。
- 不把 `ssh` 写入用户 MCP 目录，不能从目录卸载。
- 不迁移 TeamBus / catalog / team-composer 到手写 JSON-RPC 之外的 `mcp_dart`。
- 不移植原仓库的命令黑白名单、`~/.ssh/config`、SOCKS/HTTP 代理、堡垒机 `shell` 模式、2FA、`command-template`、独立 SSH 连接池。
- 不引入 `@fangjunjie/ssh-mcp-server`。
- WSL folder 不进入 `list-servers`（只有 `ssh:*`）。

## 架构

Session SSH MCP 是 App 进程内、工作区作用域的托管 MCP。

```text
本机 CLI 座位（混合工作区）
  extraMcpServers["ssh"]  →  http://127.0.0.1:<port>/ssh/mcp
       │                      Claude 本机 native 可走 teammate_bus_bridge stdio，
       │                      --bus-url 仍指向该 URL（避开 HTTP 长命令超时）
       ▼
TeammateBusMcpGateway 已有 loopback HttpServer
  GET/POST/DELETE /ssh/mcp  →  mcp_dart StreamableHTTPServerTransport.handleRequest
       ▼
SessionSshMcpHandler（mcp_dart McpServer）
  X-Session → 工作区 → 该工作区全部 ssh:* folder 的 profile
       ▼
SshClientFactory 存储面连接池
  execute-command → runOnStorage
  upload/download → sftpFor
```

`mcp_dart` 不自己 `HttpServer.bind`。它只处理网关已经接受的 `HttpRequest`。DNS rebinding：`allowedHosts` 为 `127.0.0.1` 与 `localhost`。

依赖：`client/pubspec.yaml` 增加 `mcp_dart: ^2.4.2`（SDK 最低 3.4，与当前 `^3.8.1` 兼容）。

## 注入条件

`composeRuntimeExtraMcpServers` 在现有 catalog / team-composer 合并之后，当且仅当下列全部为真时写入 `extra["ssh"]`：

1. 工作区拓扑是 `WorkspaceTopology.mixed`
2. `Workspace.injectSessionSshMcp` 不是 `false`（字段缺省视为开）
3. 当前座位本机：`!usesSshTransport(launchKind)`（`local` / `wsl`；`ssh` / `termux` 不注入）
4. 工作区 folders 里至少有一个 `ssh:*` target

个人 session 与团队 session 同一套规则：本机座位注入，远程座位不注入。

关掉开关或拓扑不再是 mixed 之后，已经打开的 session 仍带着旧 MCP，直到重连。新的 `prepareConnect` 不再写入 `ssh`。

## 组件

| 单元 | 职责 | 依赖 |
|------|------|------|
| `Workspace.injectSessionSshMcp` | 工作区开关 | `Workspace` / `SessionRepository` |
| `SessionSshMcpConstants` | server 名 `ssh`，path `/ssh/mcp` | 无 |
| `session_ssh_mcp_targets.dart` | 从 folders 收集去重后的 ssh profile + folderPaths | `RuntimeTarget` / `SshProfile` 仓储 |
| `session_ssh_mcp_paths.dart` | 本机/远程路径必须落在对应 workspace folder 下 | 现有 workspace path utils |
| `SessionSshMcpHandler` | 注册四个 tool，按 `X-Session` 解析工作区 | `SshClientFactory` |
| `TeammateBusMcpGateway` | 把 `/ssh/mcp` 交给 mcp_dart transport | 已有 loopback server |
| `resolveSessionSshMcpTransportConfig` | HTTP headers，或 Claude native 的 stdio bridge | 与 catalog 同一套 `teammate_bus_bridge` |
| `SessionSshMcpPolicy` | Claude `mcp__ssh__*` / Cursor `Mcp(ssh:…)` allow 四条 | member role provision |
| Workspace Info 开关 | 仅混合工作区显示，样式对齐 `rootSandboxEnvOptIn` | ChatCubit / SessionRepository |

代码放在 `client/lib/services/ssh/mcp/`。网关只做挂载，不把 SSH 语义写进 `team_bus`。

### 开关持久化

- 字段：`injectSessionSshMcp`，类型 `bool`，构造默认 `true`。
- JSON：**缺省或省略 = 开**。只有关掉时写入 `'injectSessionSshMcp': false`（与 `rootSandboxEnvOptIn` 相反：那个默认关、只在 true 时落盘）。
- `copyWith` / `==` / `hashCode` 带上该字段。

## 工具契约

参数名贴近原仓库；目标用 TeamPilot profile，不把凭据放进 MCP 配置。

### `list-servers`

无参数。返回该 session 当前工作区快照：

```json
[
  {
    "profileId": "home-server",
    "name": "Home",
    "host": "192.168.1.8",
    "port": 22,
    "username": "alice",
    "folderPaths": ["/home/alice/proj"]
  }
]
```

不含密码、私钥、passphrase。同一 profile 出现在多个 folder 上时合并 `folderPaths`，只列一次。

### `execute-command`

| 参数 | 必填 | 含义 |
|------|------|------|
| `cmdString` | 是 | 远程执行的命令 |
| `connectionName` | 单台时可省 | `profileId` 或唯一的 profile `name` |
| `timeout` | 否 | 毫秒。默认 `SshStorageIo.ioTimeout`（30s） |
| `cwd` | 否 | 远程工作目录。默认该目标 `folderPaths.first`。相对路径先相对该默认目录解析。解析后必须落在该目标的 workspace folder 下 |

实现：`cd -- <quoted-cwd> && <cmdString>`，经 `SshClientFactory.runOnStorage`。stdout+stderr 合计上限 10MiB；超出则中止命令，返回 `OUTPUT_LIMIT_EXCEEDED` 和截断输出，不报成功。

### `upload` / `download`

| 参数 | 必填 | 含义 |
|------|------|------|
| `localPath` | 是 | 本机路径（TeamPilot home plane / 本机座位可见的磁盘） |
| `remotePath` | 是 | 远程绝对 POSIX 路径 |
| `connectionName` | 单台时可省 | 同 `execute-command` |

走 `SshClientFactory.sftpFor`。超时用现有存储面 SFTP 超时；不另做传输体积上限。

路径边界：

- `localPath` 规范化后必须落在本机 workspace folder，或该本机座位的 cwd / add-dirs 下。
- `remotePath` 必须是绝对 POSIX，且落在该 SSH 目标的 workspace `folderPaths` 下。
- `..` 逃逸、symlink 指到边界外 → `path_not_in_workspace`。不跟随边界外的本地 symlink 作为 upload 源。

### `connectionName` 解析

1. 先按 `profileId` 精确匹配允许列表。
2. 再按 profile `name` 匹配；匹配到 0 或大于 1 个 → `unknown_ssh_target`，提示用 `list-servers` 的 `profileId`。
3. 省略时：允许列表恰好 1 个 profile 则用它；否则 `unknown_ssh_target`。

调用中途增删 folder：按**本次调用**解析到的工作区快照校验，不重放旧快照。

## 传输与权限

本机 HTTP 配置与 catalog 相同：`type: http`，`url` 为 gateway `/ssh/mcp`，headers 含 `X-Session`、`X-Member`。

Claude / flashskyai 本机 native 且 `teammate_bus_bridge` 可解析时，改 stdio：`command` 为 bridge，`--bus-url` 为 SSH MCP URL（不是 TeamBus `/mcp`）。

注入即同意。Claude/Cursor 把四个 tool 全部写入 allow。Codex/OpenCode 启用 server 即全部 tool，无需另写 allow 文件。

## 数据流

1. App 启动时 gateway `ensureStarted`；attach `SessionSshMcpHandler`（`SshClientFactory` + session→workspace 解析器）。
2. 本机座位 `prepareConnect` → `composeRuntimeExtraMcpServers` 按注入条件写入 `ssh`。
3. CLI MCP writer 与 catalog / TeamBus 一并写入该座位配置；Claude/Cursor 合并 `SessionSshMcpPolicy` allow。
4. 第一次 tool 调用才使用连接池（不预连）。尚未接受 host key 时走现有 prompt；拒绝 → `ssh_unavailable`。

```text
CLI → loopback /ssh/mcp
  → Host 校验
  → X-Session 解析工作区
  → 仍 mixed 且开关开，否则 ssh_mcp_disabled
  → connectionName → 允许的 ssh profile
  → execute-command / sftp + 路径边界
```

## 错误处理

给模型的是 tool / JSON-RPC error。不把密码、私钥、passphrase 写进错误文本。缺 `X-Session` 或未知 session：**HTTP 200** + 协议/tool error，不 4xx（对齐 catalog，避免 CLI 把网关当宕机）。

| 代码 | 何时 |
|------|------|
| `ssh_mcp_disabled` | 开关已关，或工作区已不是 mixed |
| `unknown_ssh_target` | 缺省但多台、名字对不上、profile 不属于该工作区 |
| `path_not_in_workspace` | local/remote 路径越出允许根 |
| `ssh_unavailable` | 连不上、握手失败、host key 拒绝 |
| `command_timeout` | exec 超过 timeout；存储面超时按现有逻辑 eviction 该 profile |
| `OUTPUT_LIMIT_EXCEEDED` | stdout+stderr > 10MiB |
| `sftp_error` | SFTP 失败（响应不含文件内容） |

非法 `Host`：拒绝请求（DNS rebinding），不进入 tool 分发。

## UI

混合工作区 Info（`WorkspaceInfoSection`）增加开关，放在 `rootSandboxEnvOptIn` 附近：

- 标题/说明走 `app_en.arb` / `app_zh.arb`（例如：为本地成员注入 SSH MCP / 让本机座位通过 MCP 操作本工作区的远程机器；关闭后需重连 session）。
- 非混合：不显示开关。
- 切换立即持久化；已开 session 需重连才生效。

## 测试

构造注入，不打真 SSH。`SshClientFactory` 用假实现。新集成测试加 `@Tags(['integration'])`。内环：`flutter analyze` + 相关单测文件。

**注入**

- mixed + 开 + 本机 + 有 `ssh:*` → `extra` 含 `ssh`
- 纯本地 / 纯远程 / 远程座位 / 开关关 / 无 `ssh:*` → 不含
- JSON 无字段视为开；`false` 不注入
- Claude native 本机：stdio bridge，`--bus-url` 含 `/ssh/mcp`；其它 CLI：HTTP + `X-Session`

**Handler**

- `list-servers` 只返回该工作区 ssh profile，无密钥
- 一台可省略 `connectionName`；多台省略或写错 → `unknown_ssh_target`
- `execute-command` 打到对应 profile 的 `runOnStorage`；超时与 10MiB 错误码稳定
- 路径在 folder 内成功；`../` 与逃出绝对路径 → `path_not_in_workspace`
- 关开关 → `ssh_mcp_disabled`
- 缺 `X-Session`：HTTP 200 + error，不是 4xx

**Gateway**

- `/ssh/mcp` 交给 mcp_dart；非法 Host 拒绝
- `/mcp`、catalog、composer 路由不变

**持久化 / UI**

- `Workspace` round-trip：缺省为开，显式 `false` 保留
- 混合 Info 页可切换；非混合不展示

## 文件落点（实现时）

- `client/pubspec.yaml` — `mcp_dart`
- `client/lib/models/workspace.dart` — 开关字段
- `client/lib/services/ssh/mcp/` — constants / targets / paths / handler / transport / policy
- `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` — `/ssh/mcp` 路由
- `client/lib/services/launch/session_shell_connector.dart` — `composeRuntimeExtraMcpServers` 注入
- Claude/Cursor 启动时的 allow 合并（与 catalog allow 同一路径）
- `client/lib/pages/home_workspace/workspace/workspace_info_section.dart` — 开关
- `client/lib/l10n/app_en.arb`、`app_zh.arb`
- 对应 `client/test/...` 单测
