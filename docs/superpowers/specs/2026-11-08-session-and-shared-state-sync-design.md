# Session 与共享状态同步设计

- 日期：2026-11-08
- 状态：待审阅
- 前置：期 1 中央事件层、期 2 presence、期 3 Event Transport（`docs/superpowers/specs/2026-09-12-event-transport-design.md`）
- 目标：让 TeamPilot 在“桌面持有 runtime、手机远程参与”的场景下，支持实时输出、完成通知、远程取消；同时把 open tabs / closed workspaces / favorites / display prefs / recents 等 UI 状态做成多设备可用、离线可用、合并安全。

## 结论

做**三个平面**，不要把不同一致性模型塞进同一套协议：

| 平面 | 一致性 | 传输 | 典型数据 |
|---|---|---|---|
| Device plane | 本机唯一 | 无 | theme、locale、快捷键、窗口大小、密度 |
| Shared state plane | 多写者、最终一致、可离线 | home plane 文件 + 可选失效通知 | favorites、open tabs、closed workspaces、display prefs、recents |
| Session plane | 单写者 authority、有序、实时 | 全双工协议（SSH / Connect relay） | activity、transcript、terminal、intent、attention |

**不做独立运行时。** authority 内嵌在 TeamPilot App；桌面 App 在线即为 host，手机为 client。将来需要 headless 时，用同一二进制加 `--host` 模式，而不是每平台发一个 runtime。

## 背景与现状

当前问题：

1. `EventTransportServer/Client` 是单向的：手机只 `subscribe`，桌面只推送 `agentPresence` / `sessionLifecycle`；握手后的客户端行被 `_ClientSession._checkPostHandshake()` 丢弃。
2. 手机端 idle 通知只监听本地 `ChatCubit.sessionActivities`；桌面持有的 PTY/ACP runtime 在手机上不可见。
3. ACP 会话在手机上只读一次 `AcpSeatTranscriptReader` 快照，不参与 live refresh；PTY 会话靠 SFTP 2s poll。
4. `services/home_workspace/` 下的 UI 状态 store 都是 `load → 改 → save`，多设备并发写会丢更新：
   - `workspace_favorites_store.dart`
   - `home_open_workspaces_store.dart`
   - `home_closed_workspaces_store.dart`
   - `home_recent_workspaces_store.dart`
   - `workspace_display_prefs_store.dart`

本设计把“实时会话”和“共享 UI 状态”分开解决。

## 非目标

- 不新做 daemon / 系统服务。
- 不把 home plane 当实时消息总线。
- 不追求 PTY 字节级多端同步；终端视图用 host 侧屏幕模型。
- 不在本期做浏览器/第三方客户端。
- 不把 device-local 偏好纳入同步。

## Session Plane

### 角色

| 概念 | 含义 |
|---|---|
| Authority | 实际持有 session PTY/ACP 的进程；每个 session 唯一 |
| Participant | attach 到 session 的客户端，带 capabilities |
| Controller lease | 某个 seat 的可写租约，避免多端同时发 prompt |
| Epoch | authority 生命周期；重启/迁移 +1 |
| Revision | session 状态版本；每次 delta +1 |
| TurnId | 一次 agent turn 的标识；取消必须携带 |

一个设备可以同时是 A session 的 authority、B session 的 observer。角色是 per-session 的，不是 per-device。

### 传输与分帧

- 传输：现有 SSH `forwardLocal` 字节通道；Connect relay 复用同一套字节流。
- 分帧：`u32` 大端长度 + 固定头 + Protobuf payload。
- 序列化：Protobuf envelope；`Content` 使用 `bytes`，不做 base64。
- `SessionTransport` 抽象；未来可加 WebSocket / LAN TLS 适配器，语义不变。

```text
frame = u32 length + Envelope(protobuf)

Envelope {
  uint32 proto = 1;
  Channel ch = 2;          // CONTROL / STATE / CONTENT / ATTENTION / BULK
  uint64 seq = 3;
  uint64 ack = 4;
  string corr = 5;
  oneof body {
    Hello hello = 10;
    Attach attach = 11;
    Snapshot snapshot = 12;
    Delta delta = 13;
    Content content = 14;
    Intent intent = 15;
    IntentResult intentResult = 16;
    Attention attention = 17;
    Ping ping = 18;
    Error error = 19;
  }
}
```

### 通道

| 通道 | 内容 | 可靠性 |
|---|---|---|
| CONTROL | hello、attach、intent、intentResult、lease、ping | 必达、优先 |
| STATE | session snapshot / delta | 有序、可 resync |
| CONTENT | transcript delta / terminal screen diff | 可合并、可丢弃、可 resync |
| ATTENTION | idle / needs_input / failed | 至少一次、可补拉 |
| BULK | 历史回填、大附件 | 可分块、可限速 |

控制通道优先；内容通道落后时发 `resyncRequired`，不阻塞控制。

### 关键语义

- `attach { sessionId, since: {epoch, stateRevision, contentSeq} }`：能续传就续传，否则 snapshot。
- `delta.base` 必须等于客户端当前 revision；否则 resync。
- `intent` 带 `id`、`op`、`expectedEpoch`、可选 `expectedTurnId`、`deadline`。
- `intentResult` 返回 `applied | noop | rejected | expired`。
- 取消的收敛以 STATE delta 为准，不以 intentResult 为准。
- `attention` 可持久化并由客户端 ack；离线后 attach 可补拉未 ack 项。

### 控制操作

首期只做：

- `turn.cancel`：PTY 走 `ChatCubit.interruptSelectedMemberTurn`；ACP 走 `AcpChatRuntimeCubit.cancelTurn`。
- `session.pauseFollowUp`：`ChatCubit.pauseFollowUpQueue`。

后续可加 `prompt.send`、`ask.answer`、`session.close`、`authority.handoff`。全部是类型化 intent，不开放任意 shell。

### 实时内容

- Chat 视图：host 推送 `transcript.delta` / `transcript.commit`；原生支持结构化输出的 CLI 用其事件流，TUI-only CLI 由 host 解析 transcript，至少 commit 级。
- Terminal 视图：host 维护 headless terminal 模型，推送 screen diff，不传原始 PTY 字节。
- 重连：按 `contentSeq` 续传；落后太多回退到 home 里的 transcript/journal。

### 失败与一致性

- authority 重启：新 epoch；客户端重连拿 snapshot；在途 intent 返回 `authority_restarted`。
- 网络分区：intent 带 deadline，过期丢弃；content 可丢，state 不可丢。
- 半开连接：应用层 ping 15s，30s 无 pong 判定断开。
- 多客户端：同一 seat 默认一个 controller lease；其他参与者只读；需要协作时显式 handoff。

### 通知

- host 产生 `attention {id, sessionId, seat, kind, turnId, createdAt, expiresAt}`。
- 客户端决定是否弹本地通知（前台且正在看该 session 则不弹）。
- App 被杀死仍要通知时，增加 `push.register` 与系统 push；协议本身只负责 attention 事实。

## Shared State Plane

### 原则

- 本地优先：本地 replica 立即更新，UI 不等网络。
- home plane 是 rendezvous + 持久化，不是消息总线。
- 多写者安全：合并而不是覆盖。
- 离线可用：不依赖另一端 App 在线。

### 合并原语

只实现三个：

1. **LWW Register**：单值字段，带 Hybrid Logical Clock（HLC）。
2. **OR-Set**：集合字段，带 add/remove tombstone。
3. **Per-device lane**：每设备一条有序列表，合并按设备区分或取并集。

不引入重型 CRDT 框架。

### 文档结构

```json
{
  "schema": 2,
  "revision": "uuid",
  "hlc": "2026-11-08T...",
  "favorites": {
    "ws1": {"present": true, "hlc": "..."},
    "ws2": {"present": false, "tombstone": "..."}
  },
  "deviceLanes": {
    "deviceA": {"tabs": ["ws1", "ws3"], "active": "ws1", "updatedAt": "..."},
    "deviceB": {"tabs": ["ws2"], "active": "ws2", "updatedAt": "..."}
  },
  "prefs": {
    "gridView": {"value": true, "hlc": "..."}
  }
}
```

实现上可按 domain 拆文件，也可一个 doc 分节；按 domain 拆更容易扩展和排障。

### 数据归属

| 数据 | 平面 | 合并 |
|---|---|---|
| favorites | shared | OR-Set |
| open workspace tabs | per-device lane + shared pinned | 每设备 lane；需要“所有设备一致”再改 shared OR-Set |
| closed workspaces | per-device 为主 | 每设备最近关闭；需要“全局关闭”再用 shared tombstone |
| display prefs | device 为主 | grid/list、密度、主题按设备；workspace 级展示配置才共享 |
| recently visited | per-device | 最近访问是设备视角；可选 shared `lastVisitedBy` LWW |
| 通知已读 | 产品决定 | per-device 或 shared |

### 读写路径

写：

```text
本地 replica 立即更新
  → debounce 200–500ms
  → 读 home 共享 doc
  → merge
  → 带 revision 做 CAS 原子写
  → 冲突则重读再 merge
```

读：

- 本地 home：文件 watcher。
- SSH home：SFTP 轮询；或由 session transport 发 `state.invalidated {domain, revision}` 作为重读提示，数据本身不走 session 协议。

离线：本地照常写；下次连上 home merge。

### 迁移

把现有 store 迁移到 `SharedStateStore`：

- `WorkspaceFavoritesStore` → OR-Set
- `HomeOpenWorkspacesStore` → per-device lane
- `HomeClosedWorkspacesStore` → per-device lane
- `HomeRecentWorkspacesStore` → per-device lane
- `WorkspaceDisplayPrefsStore` → device LWW（或按产品决定共享字段）

保留文件路径可减少迁移风险；格式升级用 `schema` 做一次性迁移。

## Device Plane

以下保持本机存储，不跨设备：

- theme / locale / typography / zoom
- 快捷键
- 窗口大小、密度
- 设备级通知偏好

与 `docs/superpowers/specs/2026-11-07-home-plane-runtime-isolation-design.md` 的设备/平面拆分保持一致。

## 进程与部署

- 本期：authority 内嵌桌面 App；手机是 client。
- 桌面关闭 App 即结束任务；若产品要求“关 UI 任务继续”，先做托盘常驻。
- 需要 headless 时，同一二进制加 `--host` 模式；仍不按平台发独立 runtime。
- 移动端默认不做 host；iOS 不提供 daemon。

## 安全

- 第一版信任边界：SSH 登录 / Connect relay；server 只绑 `127.0.0.1`。
- 直连 LAN 必须 TLS 1.3 或 Noise。
- 后续加设备公钥、per-session capability、intent 审计。
- 永不开放通用 `exec`。

## 扩展性与版本

- `hello` 做 protocol version + capability 协商；客户端只启用交集。
- 消息用 Protobuf `oneof` 加字段号；字段只加不删，`reserved` 防复用。
- 未知 content 类型忽略；未知 control 类型返回 `unsupported`。
- 新功能 = 新 capability + 新字段/类型，不改帧、不改端口。
- 兼容性测试：新解码器读旧 fixture；冻结的旧解码器读新消息。

## 测试

- 帧编解码：半包、粘包、超长、版本错、fuzz。
- 协议：snapshot/delta、resume、intent 幂等、stale turn、authority restart。
- 共享状态：两设备并发写不同 key；离线 merge；tombstone 压缩；HLC 时钟偏移。
- 通知：busy→idle 边沿、前台抑制、离线补拉。
- 现有测试不被修改地通过（行为等价）。

## 分阶段

1. **Shared state 层**：抽象 + 三个合并原语 + 迁移现有 store；修多设备丢更新。
2. **Session 协议核心**：帧 + Protobuf envelope + attach/snapshot/delta + 现有 SSH 字节通道适配。
3. **三条链路**：sessionActivity（覆盖 personal）、transcript 推送、turn.cancel。
4. **桌面可用性**：托盘常驻（可选）；`--host` 留到真有 headless 需求。
5. **后续**：ATTENTION 补拉、push、controller lease/handoff、Web 客户端。

## 待拍板

1. open tabs：默认 per-device lane，还是要求多设备完全一致？
2. closed workspaces：只影响本设备，还是“对所有设备关闭”？
3. display prefs 哪些字段共享？哪些留在 device plane？
4. 通知已读：per-device 还是 shared？
5. 是否接受 Protobuf codegen？若不接受，退回 CBOR，语义不变。
6. 桌面关窗：退出结束任务，还是托盘常驻？
7. 是否首期就要 token 级终端流，还是先做 chat 级 + 屏幕 diff？

## Implementation notes（2026-11-08）

已落地：

- Shared state plane
  - `client/lib/services/shared_state/`：HLC、LWW register/map、OR-Set、per-device lane、document、CAS store、device id store、identity。
  - `client/lib/services/home_workspace/home_workspace_shared_state.dart`：五个 domain 的 merge registry。
  - favorites / open tabs / closed workspaces / recents / display prefs 已迁到新层，旧文件格式一次性迁移。
  - `HomeOpenWorkspacesStore` / `HomeClosedWorkspacesStore` / `HomeRecentWorkspacesStore` 按设备 lane 隔离；favorites 是 OR-Set；display prefs 按 key LWW。
- Session plane
  - `client/lib/services/session_protocol/`：长度前缀帧、envelope、authority、server、client、control port。
  - `client/lib/services/session_sync/`：ChatCubit → authority 的 activity source、ChatCubit 控制端口、TCP loopback server/client 控制器。
  - `client/lib/app/session_protocol_home.dart` + `app_shell.dart` 接线：local home 起 server（广告文件 `<home>/session-protocol.json`），SSH home 起 client（`forwardLocal`）。
  - 取消：`turn.cancel` → PTY `interruptSelectedMemberTurn` / ACP `cancelTurn`。
  - 实时内容：`onSessionHistoryStale` 在桌面发布 `content` 失效；手机收到后触发 history soft reload。ACP history-only 座位额外每 2s 重读 app transcript，覆盖没有 commit hook 的情况。
  - 通知：authority 在 working → idle 且 readyToChat 时发布 `attention{kind:idle}`；手机 client 走 `DesktopSystemNotifier` + 通知中心。
  - UI：`RemoteSessionControlBanner` 在远程 client 上显示 Stop；`SessionRemoteActivityCubit` 提供远端 busy/seat 投影。
  - 新会话发现：snapshot/delta 带 `workspaceId`；手机收到未知 session 时调用 `ChatCubit.refreshSessionsForWorkspace`，补上 SFTP 没有 watcher 的缺口。EventTransport 的 `sessionLifecycle`（spawned/started/closed）也注册了 consumer 作为兜底（含自动化创建、非打开 tab 的会话）。
  - 广告文件自愈：EventTransport 与 session protocol 的 server 每 10s 检查广告文件，缺失时重写；手机读取失败时日志带绝对路径与 homeRoot，便于定位 home 不一致。
- Device plane
  - `DeviceIdStore` 在 `nativeAppDataPath/shared-state/device-id` 生成稳定 id；`SharedStateIdentity` 注入 shared-state 时钟。
- 测试
  - `test/services/shared_state/`：HLC / LWW / OR-Set / lane / store / device id。
  - `test/services/home_workspace/shared_state_stores_test.dart`：多设备 merge、legacy 迁移。
  - `test/services/session_protocol/`：帧、authority、server/client 往返。
  - `test/cubits/session_remote_activity_cubit_test.dart`：远端投影。

已知偏离 / 待补：

1. **序列化**：当前 envelope 用 JSON（长度前缀帧）；原计划的 Protobuf 需要 `protoc` + `protoc_plugin`，当前构建环境没有 `protoc`。语义层已隔离，后续只替换 codec。
2. **attention 持久化**：当前是 live-only；断线期间的 idle 通知不会补发。需要 journal + ack 才能做到“离线后补拉”。
3. **内容流**：目前是失效信号 + softReload / ACP 2s poll，不是 token 级 delta；屏幕 diff 也未实现。
4. **安全**：仍是 SSH / loopback 信任模型；设备公钥、capability ACL、intent 审计未做。
5. **多 controller / handoff**：未做；同一 seat 目前没有显式 controller lease。
6. **headless / tray**：未做；桌面关窗仍退出。
7. **ACP commit hook**：没有在 `AcpChatTranscriptWriter.append` 发布 content 失效；2s poll 是兜底。
