# tp_sshd direct-tcpip 转发设计（生产级，对齐 OpenSSH）

- 日期：2026-09-12
- 状态：待审阅
- 前置：
  - 事件通道（`2026-09-12-event-transport-design.md`）：手机用 `forwardLocal('127.0.0.1', port)` 经同一条 SSH 连接订阅桌面的允许列表事件；`tp_sshd` 尚未支持 `direct-tcpip`，一旦合入只换通道不换帧。
  - 远程端口转发（`tcpip-forward` / `forwarded-tcpip`）已合入，走 `SSHServerConfig.bindServerSocket` 注入 seam，loopback-only 绑定策略，见 `client/packages/tp_sshd/lib/src/server_forward.dart`。
  - 对照源码：OpenSSH `openssh/openssh-portable`（`HEAD`，2026 年拉取）。关键命中：`serverloop.c:418` `server_request_direct_tcpip`（门控 + reason）、`serverloop.c:776` `tcpip-forward` 门控、`channels.c:4790-4800` `channel_connect_to_port`（per-user/per-admin PermitOpen 逐连接裁决）、`channels.c:4747` `connect_to_helper`（解析失败→CONNECT_FAILED）、`servconf.c:1086-1090` `AllowTcpForwarding` 位掩码关键字表。
- 交接：`docs/superpowers/HANDOFF.md`
- 目标：让嵌入式 SSH server 在生产级语义下服务 `direct-tcpip` 通道（RFC 4254 §7.1），使 `EventTransportClient` 的 `forwardLocal` 真正打通，手机 presence 改走推送而非磁盘+轮询；库核心能力对标 OpenSSH（`AllowTcpForwarding` / `PermitOpen` / 服务端解析拨号 / 正确拒绝码），不做版本兼容。
- 开发对照原则：实现每个语义点时与 `/tmp/opencode/openssh`（`openssh/openssh-portable` HEAD）复核；发现其它不一致处（消息路径、门控顺序、错误码、生命周期）**随时修正本设计及实现**，不局限于本节列出的点。

## 背景（已核对代码）

- 手机（ssh home）读 `<teampilotRoot>/event-transport.json` 拿到桌面 `EventTransportServer` 的端口，然后 `sshClientFactory.clientForStorage(profile)` + `client.forwardLocal('127.0.0.1', port)`（`client/lib/services/ssh/event_transport_ssh_channel.dart:67`）。`forwardLocal` 开的是 `direct-tcpip` 通道。
- 桌面嵌入式 `tp_sshd` 对 `direct-tcpip` 统一拒绝：`SSHServerConnection._handleChannelOpen`（`client/packages/tp_sshd/lib/src/server_connection.dart:236`）只接受 `channelType == 'session'`，其余一律 `SSH_Message_Channel_Open_Failure` reason 1。因此运行日志里反复出现 `SSHChannelOpenError(... 'direct-tcpip' is not supported)` 的 WARN，事件通道退化为磁盘+轮询。
- `SSH_Message_Channel_Open` 已能完整 decode/encode `direct-tcpip`（`client/packages/dartssh2/lib/src/message/msg_channel.dart:169`），携带 `host` / `port` / `originatorIP` / `originatorPort`；无需改 dartssh2。
- 拒绝码常量已就位：`codeAdministrativelyProhibited = 1`、`codeConnectFailed = 2`、`codeUnknownChannelType = 3`、`codeResourceShortage = 4`（`msg_channel.dart:324-327`）。
- 服务器侧没有 channel request 需求的通道靠 `onRequest == null` 全拒（`server_channel.dart:237`）；`direct-tcpip` 通道只传数据，不需要挂 handler。
- 反向转发的双向泵流实现是 `SSHServerForwarder._pump`（`server_forward.dart:236`），已涵盖窗口/半关闭/任一侧结束的完整语义，将被抽为共享实现。

## 目标与非目标

### 目标

1. `tp_sshd` 以生产级语义服务 `direct-tcpip`：目标地址任意（服务端解析 + 拨号）、`AllowTcpForwarding` / `PermitOpen` 门控、正确拒绝码。
2. 两类 TCP 转发（`direct-tcpip` 与 `tcpip-forward`）由同一套转发配置管控，语义对齐 OpenSSH。
3. `direct-tcpip` 与 `forwarded-tcpip` 复用同一份泵流实现。
4. 拨号失败只拒绝该通道（reason 2），不断开 SSH 连接；拨号不悬挂 pending 通道表。
5. app 接线（`embedded_ssh_server.dart`）注入转发配置，事件推送链路端到端打通：手机 presence 走推送。
6. 测试覆盖拒绝/成功/失败/上限/拆除全路径。

### 非目标

- 不实现 `x11` 与 `direct-streamlocal@openssh.com` 通道（OpenSSH 中分别受 `X11Forwarding` / `AllowStreamLocalForwarding` 独立管控，属后续独立特性；本期仍按 reason 1 拒绝）。
- 不做 agent forwarding / `auth-agent-req@openssh.com`。
- 不改 `EventTransportClient` 的字节流接口与 `services/event/` 分层（`services/event/` 仍不 import dartssh2）。
- 不改 dartssh2 fork（decode/encode 已齐、客户端 `forwardLocal` 已好用）。

## 设计

### 1. 转发配置表面：`SSHForwardingConfig`

对标 OpenSSH 四个概念：`AllowTcpForwarding`（方向位掩码主开关）、`PermitOpen`（逐连接目标谓词）、`GatewayPorts`（绑定地址行为，本项目沿用现有 loopback 规范化 = `no`）以及硬禁用（等价 `sshd -d` / 整体关）。

**`allowTcpForwarding` 是方向位掩码，不是 bool**（`servconf.c:1086-1090`：`yes|all|no|local|remote` 映射 `FORWARD_ALLOW/DENY/LOCAL/REMOTE`）。`direct-tcpip` 需要 `local` 位，`tcpip-forward` 需要 `remote` 位：

```dart
enum SshTcpForwardingMode {
  deny,   // AllowTcpForwarding no
  local,  // direct-tcpip 允许，tcpip-forward 拒绝
  remote, // tcpip-forward 允许，direct-tcpip 拒绝
  both,   // AllowTcpForwarding yes/all
}
```

`SSHServerConfig` 新增可选字段 `SSHForwardingConfig? forwarding`；**移除**顶层 `bindServerSocket`（不做向后兼容，全部调用点与测试对齐）。`forwarding == null` 等价 `deny` + OpenSSH 的 `disable_forwarding`（硬禁用）：两类转发全部拒绝。

```dart
class SSHForwardingConfig {
  /// 等价 AllowTcpForwarding 位置。direct-tcpip 看 local，tcpip-forward 看 remote。
  final SshTcpForwardingMode allowTcpForwarding;

  /// 等价 PermitOpen + authorized_keys permitopen/permitlisten 的合成：
  /// 逐连接裁决（OpenSSH 在 channel_connect_to_port 同时查 permitted_user
  /// 与 permitted_admin，两套都要放行；这里合成一个谓词，由嵌入方
  /// 自行实现分层）。对 direct-tcpip 校验拨号目标 (host, port)，对
  /// tcpip-forward 校验绑定地址。收到 connection —— 嵌入方可据
  /// onAuthenticated 记录的设备身份做 per-device 决策。null = 全放行
  /// （OpenSSH 缺省 PermitOpen any）。
  final Future<bool> Function(SSHServerConnection connection, String host, int port)? permitOpen;

  /// 拨号 seam：服务端拿到 host 字符串 + port，由 seam 自行解析并连接
  /// （等价 OpenSSH 服务端 getaddrinfo + connect）。见 §2。
  final SSHDialSocket dialSocket;

  /// 绑定 seam：现有远程转发注入点原样移入；loopback-only 绑定
  /// 规范化（= GatewayPorts no）保留。
  final SSHBindServerSocket bindServerSocket;

  /// 拨号 + 确认的完整守卫宽度，防止悬挂的通道打开（默认 30s）。
  final Duration dialTimeout;
}
```

新类型（`server_forward.dart` 中定义并随 `tp_sshd.dart` 导出）：

```dart
/// 对端连接抽象：拨入的 socket 与绑定收到的连接是同一个接口
/// （input / output / done / destroy），dial 与 bind 复用同一份泵流。
typedef SSHDialSocket = Future<ForwardConnection> Function(
    String host, int port);
```

`dialSocket` 直接复用现有 `ForwardConnection`（`server_forward.dart:37`）作为返回类型，不加别名新类。

### 2. `direct-tcpip` 消息路径（RFC 4254 §7.1 / §5.1）

`_handleChannelOpen`（`server_connection.dart:228`）改为按 `channelType` 分派：

1. `session`：现状路径不变。
2. `direct-tcpip`：
   - 无 `forwarding` 或 `allowTcpForwarding` 无 `local` 位 → `SSH_Message_Channel_Open_Failure` **reason 1**，文案对齐 OpenSSH（如 `"TCP forwarding is disabled"`）。
   - 端口越界（`port > 0xFFFF`，对齐 `serverloop.c:434`）→ 同上 **reason 1**。
   - `permitOpen` 拒绝 `(host, port)` → **reason 1**，文案标注地址（如 `"forwarding disabled for <host>:<port>"`）。`permitOpen` 先于任何解析/拨号；谓词收到 connection，嵌入方可做 per-device 决策。
   - 拨号：`dialSocket(host, port)`。解析失败 / 抛 `SocketException` / 超时 → **reason 2**（`codeConnectFailed`），文案源自异常信息；**不断开 SSH 连接**——失败的通道只是被拒（对齐 `channel_connect_to_port` 的 `connect_to_helper` 语义）。
   - 成功 → 构造 `SSHServerChannel`（`channelType: 'direct-tcpip'`，不挂 `onRequest`），先注册进 `_channels` 再发 `CHANNEL_OPEN_CONFIRMATION`（携带 `initialReceiveWindow` / `maximumPacketSize`），随后启动共享泵流 `pumpForwardConnection(channel, connection)`。
   - 竞态：拨号完成前连接已关（`_phase != running`）→ 直接 `destroy()` 拨入连接，不发任何包。

拨号 await 用 `dialTimeout` 守卫（`future.timeout(dialTimeout)`），超时按 reason 2 处理并销毁连接，杜绝悬挂的 pending 打开。（`_handleChannelOpen` 里 `direct-tcpip` 是同步分派对异步拨号，失败回包在异步段发送，不阻塞消息循环。）

`maxChannels` 上限照旧在类型分派之前检查，`direct-tcpip` 通道计入同一配额（防拨号把通道表打穿）。

（`tcpip-forward` 侧的顺序对齐 `serverloop.c:781-796`：`remote` 位、per-connection 谓词（绑定对象 host:port），再 loopback 规范化（= `GatewayPorts no`），最后 bind seam；端口 > `INT_MAX` 直接拒绝。）

### 3. 共享泵流：抽 `_pump`

把 `SSHServerForwarder._pump` 提为 `server_forward.dart` 的库内顶层函数 `pumpForwardConnection(SSHServerChannel channel, ForwardConnection connection)`（`server_connection.dart` 已 import 该文件），两条路径调用同一份：

- `forwarded-tcpip`（server→client 方向，反向转发）现状行为不变。
- `direct-tcpip`（client→server 方向）：TCP 一旦连上即由同一 pump 接管。

泵流语义沿用现状（已测）：TCP→channel、channel→TCP 两向订阅，任一侧 `onDone` 半关闭对侧，`channel.done` 销毁拨入 socket，`connection.done` 关闭 channel。窗口/包大小由 `SSHServerChannel` 承担，无需新增逻辑。

### 4. 生命周期与拆除

- 拨入连接随通道进 `_channels` 表；连接关时 `_teardownChannels()` detach 所有通道 → `channel.done` 完成 → pump 的 `whenComplete` 销毁拨入 socket。与 `session` 通道同路径，**无新增拆除路径**。
- 连接 `close()` / `_onTransportClosed()` 同时关 `_forwarder`（释放全部 binds）；拨入的连接不在 forwarder 名下，全由通道表管理。
- `SSHServerForwarder` 名字与职责不变（只管反连）；direct-tcpip 的拨号处理做成与之平行、单一职责的 `SSHServerDirectDialer`（构造注入 `SSHDialSocket` / `permitOpen` / `dialTimeout`，负责门控、拨号、确认和泵流启动），与 forwarder 彼此不依赖；`SSHServerConnection` 只按 `channelType` 分派给它。

### 5. app 接线（`embedded_ssh_server.dart`）

`start()` 里 `SSHServerConfig` 的注入改为：

- `forwarding: SSHForwardingConfig(allowTcpForwarding: both, permitOpen: <app 策略>, dialSocket: <Socket.connect 适配>, bindServerSocket: <现有 _IoServerSocketHandle 适配>)`。
- `permitOpen` 默认为逐连接谓词，**仅 loopback**（`127.0.0.1` / `::1` / `localhost` 放行，其余拒绝）：TeamPilot 这台自管 sshd 的「sshd_config」只导出本机 loopback，与既有信任模型一致，事件通道只需拨 `127.0.0.1`；桌面不当任意出口代理。签名收到 connection，未来做 per-device PermitOpen（等价 authorized_keys `permitopen`）即改谓词体，库能力不受限。
- `dialSocket` 用 `Socket.connect` 适配：`(host, port) async => _RealForwardConnection(await Socket.connect(host, port))`，host 解析交给 dart:io（等价服务端 getaddrinfo）。
- 涉及该注入点的既有测试与调用点全部适配新配置面。

端到端结果：手机 `forwardLocal('127.0.0.1', port)` 拨到桌面 `EventTransportServer`；`direct-tcpip not supported` WARN 消失；presence 事件走推送。

### 6. 错误语义汇总

| 场景 | 行为 | 码 |
|---|---|---|
| 无 `forwarding`（硬禁用）或 `allowTcpForwarding` 无对应方向位 | `CHANNEL_OPEN_FAILURE`（文案 `TCP forwarding is disabled`） | 1 |
| `permitOpen` 拒绝目标 | `CHANNEL_OPEN_FAILURE`（文案含 host:port） | 1 |
| 目标端口 > 0xFFFF（对齐 `serverloop.c:434`） | `CHANNEL_OPEN_FAILURE` | 1 |
| 解析失败 / 拨号抛错 / 超时 | `CHANNEL_OPEN_FAILURE`（文案含异常）；SSH 连接存活 | 2 |
| 拨号期间连接已关 | 销毁拨入连接，不发包 | — |
| 通道数达到 `maxChannels` | `CHANNEL_OPEN_FAILURE`（文案 `Too many open channels`） | 4 |
| `x11` / `direct-streamlocal@openssh.com` | 维持现状拒绝 | 1 |
| 通道请求（exec/shell 等）打在 direct-tcpip 通道上 | `CHANNEL_FAILURE`（`onRequest == null`） | — |

## 测试计划

### tp_sshd（`client/packages/tp_sshd/test/`）

新增 `server_direct_tcpip_test.dart`（沿用 `dual_test_utils.dart` 的 dual/raw 双形态）：

1. **端到端环回**：dual pair + 配置 `forwarding`，`client.forwardLocal('127.0.0.1', <真实 loopback 服务>)`，双向字节往返（镜像 `server_forward_test.dart` 第一个用例）。
2. **host 解析**：`forwardLocal('localhost', ...)` 经 seam 解析到 loopback 并连通（seam 记录收到的 host 字符串原样）。
3. **转发关闭**：无 `forwarding` → `SSHChannelOpenError` reason 1（wire 值 1）。
4. **PermitOpen 拒绝**：谓词放行白名单外 → reason 1；seam 不被调用。
5. **拨号失败**：连一个无人监听的 loopback 端口 → reason 2（wire 值 2）；随后 `client.ping()` 仍成功（连接存活）。
6. **通道上限**：10 个 session 后再开 direct-tcpip → reason 4；表不膨胀。
7. **拆除**：server 关闭销毁拨入 socket（拨入侧 `done` 完成）。
8. **适配**：`server_channel_test.dart:32` 的「unknown channel type」用例改成真实可达场景（原断言 `forwardLocal` 必抛，现在已能连，需改为对 `x11` 等仍被拒）；`server_forward_test.dart` 全量改用新 `forwarding` 配置面。

### app 层 / 集成

- 把 `openSshEventTransportChannel` / 事件通道的既有测试适配：现在 `forwardLocal` 会真实成功，不再落入「退化磁盘+轮询」分支。
- 端到端集成（`@Tags(['integration'])`）：ssh home 的手机经 `forwardLocal` 收到桌面 `EventTransportServer` 的 presence 推送；断言推送事件到达而非轮询兜底。
- 验证运行日志不再出现 `'direct-tcpip' is not supported` WARN。

## 风险与说明

- **拨号目标任意性**：库能力等价 OpenSSH 缺省（可拨任意目标）；安全边界在 app 注入的逐连接 `permitOpen`（默认 loopback-only）。如未来放宽为非 loopback，需把 access 日志（originator 设备/地址 + 目标）补上——本期不实现，风险自 app 默认策略封住。
- **hostname 解析在 seam**：tp_sshd 核心继续保持「不碰 DNS」（与现有 loopback-only bind 策略、`services/event/` 无 DNS 的约定一致）；解析由注入的 `Socket.connect` 完成，核心可测（fake seam 无需真网络/DNS）。
- **`originatorIP`/`originatorPort` 非对称**：拨号是出站方向，source 端口无法由 `Socket.connect` 指定，`forwardLocal` 里 originator 恒为客户端填的占位。仅作信息字段；`forwarded-tcpip` 才有确切来源。