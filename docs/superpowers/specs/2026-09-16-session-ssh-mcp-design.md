# Session SSH MCP 设计

- 日期：2026-09-16（2026-09-17 修订：远程座位也注入）
- 状态：已批准
- 来源：把 [classfang/ssh-mcp-server](https://github.com/classfang/ssh-mcp-server) 的四个工具做成 TeamPilot 进程内 Dart MCP，自动注入给工作区里有 `ssh:*` folder 的本机和远程座位

## 目标

工作区只要有 `ssh:*` folder，开关开着，本机和远程 CLI 座位都自动获得托管 MCP `ssh`，用来对该工作区全部 SSH 目标执行命令和传文件（含座位当前所在的那一台）。实现用 [mcp_dart](https://pub.dev/packages/mcp_dart) + 现有 dartssh2 / SSH profile，不跑 Node/`npx`。工作区可关掉注入（默认开）。

远程座位不能打 App loopback：配置写成 catalog 同一条 idle HTTP 隧道上的 `/ssh/mcp`。

## 非目标

- 不为 SSH MCP 单独开反向隧道。
- 不在远程机器再跑一份 MCP。
- 不把 `upload`/`download` 的 `localPath` 解释成远程座位自己的磁盘（始终是 App home plane）。
- `/ssh/mcp` 不新做 `X-Bus-Token` 校验（对齐 catalog `/catalog/mcp`：靠 `X-Session` + 隧道隔离）。
- 不把 `ssh` 写入用户 MCP 目录，不能从目录卸载。
- 不迁移 TeamBus / catalog / team-composer 到手写 JSON-RPC 之外的 `mcp_dart`。
- 不移植原仓库的命令黑白名单、`~/.ssh/config`、SOCKS/HTTP 代理、堡垒机 `shell` 模式、2FA、`command-template`、独立 SSH 连接池。
- 不引入 `@fangjunjie/ssh-mcp-server`。
- WSL folder 不进入 `list-servers`（只有 `ssh:*`）。
- 纯本地、纯 WSL、没有任何 `ssh:*` 的 mixed 不注入。

## 架构

Session SSH MCP 是 App 进程内、工作区作用域的托管 MCP。网关仍只挂一次 `/ssh/mcp`。

```text
本机座位
  extra["ssh"] → http://127.0.0.1:<gateway>/ssh/mcp
                 （Claude native 可走 teammate_bus_bridge stdio，
                   --bus-url 仍指向该 URL）

远程座位（ssh / termux）
  extra["ssh"] → http://127.0.0.1:<idleHttpTunnelPort>/ssh/mcp
                 headers: X-Session, X-Member, X-Bus-Token
       │
       ▼  idle HTTP 隧道（与 catalog / team-composer 同一条）
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

`mcp_dart` 不自己 `HttpServer.bind`。DNS rebinding：`allowedHosts` 为 `127.0.0.1` 与 `localhost`。依赖：`mcp_dart: ^2.4.2`（已落地）。

TeamPilot 拓扑：全部 folder 在同一 `ssh:` 目标上是 `WorkspaceTopology.remote`；两个不同 SSH profile（即使没有本机目录）是 `mixed`。两种只要有 `ssh:*` 都注入。

## 注入条件

拆成工作区谓词和座位注入两层。

**工作区启用**（Handler `enabled` 也用这个，不再硬传 `launchKind: local`）：

1. `Workspace.injectSessionSshMcp` 不是 `false`（缺省视为开）
2. folders 里至少有一个 `ssh:*` target

**写入 `extra["ssh"]`**（`composeRuntimeExtraMcpServers`，在 catalog / team-composer 之后）：

1. 工作区启用
2. `sessionSshMcpEndpoint` 非空
3. 若 `usesSshTransport(launchKind)`（`ssh` / `termux`）：必须已有 `remoteBinding`；否则省略 `ssh`，避免指向打不通的 `127.0.0.1`
4. 本机座位（`local` / `wsl`）不要求隧道

个人 session 与团队 session 同一套规则。

关掉开关或删光 `ssh:*` 之后，已经打开的 session 仍带着旧 MCP，直到重连。新的 `prepareConnect` 不再写入 `ssh`。

`remoteBinding` 的合成保持现状：`mixedRemoteBinding`，否则 `agentStatus` 上的 idle 隧道端口 + token。SSH MCP 不自己开隧道。

## 组件

| 单元 | 职责 | 依赖 |
|------|------|------|
| `Workspace.injectSessionSshMcp` | 工作区开关 | `Workspace` / `SessionRepository` |
| `SessionSshMcpConstants` | server 名 `ssh`，path `/ssh/mcp` | 无 |
| `session_ssh_mcp_targets.dart` | 从 folders 收集去重后的 ssh profile + folderPaths | `RuntimeTarget` / `SshProfile` 仓储 |
| `session_ssh_mcp_paths.dart` | App 本机路径 / 远程路径必须落在对应 workspace folder 下 | 现有 workspace path utils |
| `SessionSshMcpHandler` | 注册四个 tool，按 `X-Session` 解析工作区 | `SshClientFactory` |
| `TeammateBusMcpGateway` | 把 `/ssh/mcp` 交给 mcp_dart transport | 已有 loopback server |
| `workspaceSessionSshMcpEnabled` / `shouldInjectSessionSshMcp` | 工作区谓词；compose 再加隧道守卫 | `Workspace` / `RuntimeKind` / `RemoteBusBinding` |
| `resolveSessionSshMcpTransportConfig` | 本机 HTTP / stdio，或远程隧道 HTTP + token | catalog 同款 `remoteBinding` / `teammate_bus_bridge` |
| `SessionSshMcpPolicy` | Claude `mcp__ssh__*` / Cursor `Mcp(ssh:…)` allow 四条 | member role provision |
| Workspace Info 开关 | 有 `ssh:*` folder 时显示 | ChatCubit / SessionRepository |

代码仍在 `client/lib/services/ssh/mcp/`。网关只做挂载，不把 SSH 语义写进 `team_bus`。

### 开关持久化

- 字段：`injectSessionSshMcp`，类型 `bool`，构造默认 `true`。
- JSON：**缺省或省略 = 开**。只有关掉时写入 `'injectSessionSshMcp': false`。
- `copyWith` / `==` / `hashCode` 带上该字段。

## 工具契约

参数名贴近原仓库；目标用 TeamPilot profile，不把凭据放进 MCP 配置。四个 tool 与路径边界相对第一版不变。

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

不含密码、私钥、passphrase。同一 profile 出现在多个 folder 上时合并 `folderPaths`，只列一次。纯远程工作区也返回那一台。

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
| `localPath` | 是 | App home plane 上的路径（TeamPilot 本机磁盘），**不是**远程座位的文件系统 |
| `remotePath` | 是 | 远程绝对 POSIX 路径 |
| `connectionName` | 单台时可省 | 同 `execute-command` |

走 `SshClientFactory.sftpFor`。超时用现有存储面 SFTP 超时；不另做传输体积上限。

路径边界：

- `localPath` 规范化后必须落在本机 workspace folder，或该成员在 App 侧的 cwd / add-dirs 下。远程座位调用时同样按这条校验。
- `remotePath` 必须是绝对 POSIX，且落在该 SSH 目标的 workspace `folderPaths` 下。
- `..` 逃逸、symlink 指到边界外 → `path_not_in_workspace`。不跟随边界外的本地 symlink 作为 upload 源。

远程座位要动另一台 SSH 机器：用 `execute-command` 或对该 profile 的 SFTP。跨机拷贝若需要经过本机，先 `download` 到 App 磁盘再 `upload`。

### `connectionName` 解析

1. 先按 `profileId` 精确匹配允许列表。
2. 再按 profile `name` 匹配；匹配到 0 或大于 1 个 → `unknown_ssh_target`，提示用 `list-servers` 的 `profileId`。
3. 省略时：允许列表恰好 1 个 profile 则用它；否则 `unknown_ssh_target`。

调用中途增删 folder：按**本次调用**解析到的工作区快照校验，不重放旧快照。

## 传输与权限

**本机**：`type: http`，`url` 为 gateway `/ssh/mcp`，headers 含 `X-Session`、`X-Member`。Claude / flashskyai 本机 native 且 `teammate_bus_bridge` 可解析时，改 stdio：`command` 为 bridge，`--bus-url` 为 SSH MCP URL（不是 TeamBus `/mcp`）。

**远程**：始终 HTTP（不走 stdio bridge）。`url` 为 `http://127.0.0.1:${remoteBinding.idleHttpTunnelPort}/ssh/mcp`，headers 另加 `X-Bus-Token`。形状对齐 `resolveCatalogMcpTransportConfig` 的 `remoteBinding` 分支。

注入即同意。Claude/Cursor 把四个 tool 全部写入 allow。Codex/OpenCode 启用 server 即全部 tool，无需另写 allow 文件。

## 数据流

1. App 启动时 gateway `ensureStarted`；attach `SessionSshMcpHandler`（已落地）。
2. `prepareConnect` → `composeRuntimeExtraMcpServers` 已算出 catalog 用的 `remoteBinding`。
3. 工作区启用：本机写入 loopback `/ssh/mcp`；远程有 binding 则写隧道 URL + token；远程无 binding 则省略。
4. CLI MCP writer 与 catalog / TeamBus 一并写入该座位配置；Claude/Cursor 合并 `SessionSshMcpPolicy` allow。
5. 第一次 tool 调用才使用连接池（不预连）。尚未接受 host key 时走现有 prompt；拒绝 → `ssh_unavailable`。

```text
CLI →（本机 loopback 或远程 idle 隧道）/ssh/mcp
  → Host 校验
  → X-Session 解析工作区
  → 工作区启用（开关开且仍有 ssh:*），否则 ssh_mcp_disabled
  → connectionName → 允许的 ssh profile
  → execute-command / sftp + 路径边界
```

## 错误处理

给模型的是 tool / JSON-RPC error。不把密码、私钥、passphrase 写进错误文本。缺 `X-Session` 或未知 session：**HTTP 200** + 协议/tool error，不 4xx（对齐 catalog，避免 CLI 把网关当宕机）。

远程座位没有 `RemoteBusBinding`：compose **省略** `ssh`，不在 tool 调用时报错。

| 代码 | 何时 |
|------|------|
| `ssh_mcp_disabled` | 开关已关，或工作区已没有任何 `ssh:*` folder |
| `unknown_ssh_target` | 缺省但多台、名字对不上、profile 不属于该工作区 |
| `path_not_in_workspace` | local/remote 路径越出允许根 |
| `ssh_unavailable` | 连不上、握手失败、host key 拒绝 |
| `command_timeout` | exec 超过 timeout；存储面超时按现有逻辑 eviction 该 profile |
| `OUTPUT_LIMIT_EXCEEDED` | stdout+stderr > 10MiB |
| `sftp_error` | SFTP 失败（响应不含文件内容） |

非法 `Host`：拒绝请求（DNS rebinding），不进入 tool 分发。

## UI

工作区 Info（`WorkspaceInfoSection`）开关仍在 `rootSandboxEnvOptIn` 附近：

- 标题：注入 Session SSH MCP / Inject Session SSH MCP
- 说明：本机和远程座位都可通过 MCP 在本工作区的 SSH 机器上执行命令和传文件。更改后需重连 session.
- **有 `ssh:*` folder 才显示**（含纯远程）。纯本地、纯 WSL、无 ssh 的 mixed 不显示。
- 切换立即持久化；已开 session 需重连才生效。

ARB 键名保持 `injectSessionSshMcpTitle` / `injectSessionSshMcpSubtitle`，只改文案。

## 测试

构造注入，不打真 SSH。`SshClientFactory` 用假实现。新集成测试加 `@Tags(['integration'])`。内环：`flutter analyze` + 相关单测文件。跑测试用 `cd client && dart run tool/run_tests.dart`，不要直接 `flutter test`。

**工作区启用 / 注入**

- 有 `ssh:*` + 开 → `workspaceSessionSshMcpEnabled` 为 true（mixed、纯远程、wsl+ssh 都算）
- 纯本地 / 纯 WSL / 无 `ssh:*` 的 mixed / 开关关 → false
- compose 本机：`extra` 含 `ssh`，url 为 gateway `/ssh/mcp`
- compose 远程 + binding：url 为 `http://127.0.0.1:<idleHttpTunnelPort>/ssh/mcp`，headers 含 `X-Bus-Token`、`X-Session`、`X-Member`
- compose 远程无 binding：省略 `ssh`
- JSON 无字段视为开；`false` 不注入
- Claude native 本机：stdio bridge，`--bus-url` 含 `/ssh/mcp`；远程座位即使该 CLI 支持 bridge 也走 HTTP 隧道

**Handler**

- `list-servers` 只返回该工作区 ssh profile，无密钥；纯远程也返回该机
- 一台可省略 `connectionName`；多台省略或写错 → `unknown_ssh_target`
- `execute-command` 打到对应 profile 的 `runOnStorage`；超时与 10MiB 错误码稳定
- 路径在 folder 内成功；`../` 与逃出绝对路径 → `path_not_in_workspace`
- 关开关或删光 `ssh:*` → `ssh_mcp_disabled`
- 缺 `X-Session`：HTTP 200 + error，不是 4xx

**Gateway**

- `/ssh/mcp` 交给 mcp_dart；非法 Host 拒绝
- `/mcp`、catalog、composer 路由不变

**持久化 / UI**

- `Workspace` round-trip：缺省为开，显式 `false` 保留
- 纯远程 Info 页显示开关；纯本地不展示

## 文件落点（本修订）

已落地的 MCP 本体、网关挂载、四个 tool、allow、开关字段不重做。本修订改：

- `client/lib/services/ssh/mcp/session_ssh_mcp_transport.dart` — 工作区谓词、远程 `remoteBinding` 传输
- `client/lib/services/ssh/mcp/session_ssh_mcp_resolver.dart` — `enabled` 用工作区谓词
- `client/lib/services/launch/session_shell_connector.dart` — compose 隧道守卫
- `client/lib/pages/home_workspace/workspace/workspace_info_section.dart` — 按有无 `ssh:*` 显示开关
- `client/lib/l10n/app_en.arb`、`app_zh.arb` — 文案
- `client/test/services/ssh/mcp/session_ssh_mcp_transport_test.dart` 等对应单测
- `client/test/pages/home_workspace/workspace/workspace_info_section_target_test.dart` — 纯远程显示 / 纯本地不显示
