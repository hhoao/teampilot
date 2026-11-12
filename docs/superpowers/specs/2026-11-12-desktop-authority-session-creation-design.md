# 桌面 Authority 会话创建与全量委托设计

- 日期：2026-11-12
- 状态：待审阅
- 来源：用户提出「移动端连接桌面 TeamPilot 时，若桌面 App 在场，是否让桌面通过 session-protocol 创建会话更好」
- 前置：
  - [Session 与共享状态同步设计](2026-11-08-session-and-shared-state-sync-design.md)（session plane / authority / intent / contentDelta）
  - [PTY 全屏投递架构](../../pty-fullscreen-delivery.md)（`FullscreenPtySubmission` 状态机）
  - [移动端远程连接与 SSH 服务器拆分设计](2026-11-06-mobile-remote-connection-design.md)（远端为最终权威，本地先行写入）
  - [SSH Home 启动韧性与连接恢复设计](2026-11-07-ssh-home-boot-resilience-design.md)（有界失败 + 后台恢复）
- 目标：让「手机连接桌面 TeamPilot」时，会话由桌面 authority 创建并持有运行时；桌面 App 不在场时保持现有手机自建模式；把 PTY 终端做成只读屏幕 + 语义输入，使所有会话类型都能委托。

## 结论

1. **双路径**：桌面 App 在场（session-protocol client ready 且协商出 `intent.session.spawn` 等能力）→ 委托桌面创建；不在场 → 维持现状（手机自建 PTY/ACP，`session.create` 只通知列表行）。
2. **全量委托**：ACP 与 PTY 会话都委托桌面创建，桌面 App 成为唯一 authority，server 与运行时同进程。
3. **PTY 终端形态**：只读屏幕（grid diff）+ 语义输入（`prompt.send` / `ask.answer`），不做按键流、不传原始 PTY 字节。
4. **兼容性**：路由按 capability 分级自动降级；旧版桌面 App 只委托 ACP，能力不足时退回手机自建。

## 背景与现状

设计稿 `2026-11-08` 定义 session plane 为「单写者 authority」，authority 是实际持有 session PTY/ACP 的进程，且角色是 per-session 的。但当前实现存在双 authority 不一致：

- 手机在 SSH home 下创建会话时**自己**起远程 PTY：`SessionLaunchService._shellForLaunch` 依据 `usesSshTransport(workTarget.kind)` 调用 `shellFactory.newSession(cli, workTarget)`（`client/lib/services/chat/launch/session_launch_service.dart:706-728`）。
- 创建后 `app_shell.dart:3506-3521` 才把 `SessionListEntry` 通过 `session.create` intent 发给桌面；桌面 `SessionAuthority.handleIntent` 只调 `_controlPort.adoptSession`（`session_authority.dart:208-245`），`ChatSessionControlPort.adoptSession` 注入一个列表快照（`chat_session_control_port.dart:11-29`），**不接管运行时**。
- authority 的活动源明确「Only open tabs are authority-owned sessions」（`chat_session_activity_source.dart:9`），因此手机创建的会话不进入桌面 authority 的 snapshot/delta，`turn.cancel` 查不到 tab 直接返回（`chat_session_control_port.dart:56-74`），content / attention 也不覆盖它。
- 结果：桌面侧栏那一行只显示、不可控；手机 SSH 断开时运行时随之结束；存在「手机写一遍 + 通知桌面 adopt」的双写。

判定「桌面 App 在不在」的机制已现成，无需新增探测：只有桌面 `applyServer` 才写 `<home>/session-protocol.json`（`client/lib/app/session_protocol_home.dart:20-26`），手机 `openSshSessionProtocolChannel` 读不到即抛错（`client/lib/services/ssh/session_protocol_ssh_channel.dart:37-42`）；因此 `isClient && client.isReady` 等价于「桌面 App 在线且完成 helloAck」（`session_client.dart:270-275`）。

## 非目标

- 不做 `authority.handoff`：桌面 App 后上线时不接管已由手机自建的会话。
- 不做按键流 / 原始 PTY 字节 / 字节级多端同步 / resize / 焦点同步（遵循前置设计稿的既定边界）。
- 不做 headless `--host` 模式、托盘常驻、桌面关窗后任务继续。
- 不改造桌面 App 不在场时的创建链路（保持现状即视为完成）。
- 不开放通用 `exec`；所有 intent 均为强类型白名单。
- 不做浏览器 / 第三方客户端。

## 已知限制（产品后果，需显式接受）

委托后 PTY/TUI 会话在手机上**只有只读屏幕 + 提交文本 / 回答 ask**，以下交互不可用：TUI 菜单选择、权限模式切换、Ctrl-C 中断、方向键与行编辑、@ 弹窗、任意按键序列。这是「不追求 PTY 字节级多端同步」的必然结果，不是待修缺陷。ACP 会话不受此限制。

## 决策记录

| # | 决策 | 理由 |
|---|---|---|
| 1 | 桌面 App 在场才委托，不在场用现状 | 用户明确：SSH home 不一定有运行中的桌面 TeamPilot App |
| 2 | ACP 与 PTY 全部委托 | 用户选择方案 3「所有会话都委托」 |
| 3 | PTY 终端 = 只读屏幕 + 语义输入 | 用户选择方案 1；符合前置设计稿边界，范围可控 |
| 4 | 路由按 capability 分级降级 | 旧版桌面 App 与桌面 App 中途上下线都必须可用 |
| 5 | `session.create` 保留为纯列表行通知 | 避免 `_pendingCreates` 重放把「有副作用的创建」执行两次 |

## 术语与命名

- **op**（`SessionIntent.op`）：沿用现有无前缀风格 —— `session.spawn`、`prompt.send`、`ask.answer`（对照 `turn.cancel`、`session.create`、`session.remove`）。
- **capability**（hello / helloAck 的 `caps`）：沿用现有带前缀风格 —— `intent.session.spawn`、`intent.prompt.send`、`intent.ask.answer`、`content.terminal.screen`（对照 `intent.turn.cancel`、`content.invalidated`）。
- **clientTurnId**：客户端生成的幂等键，用于 `prompt.send` / `ask.answer` 去重；与协议层的 `turnId`（运行时产生、见 `SessionSeatActivity.turnId`）不同，映射由 authority 维护。
- **占位 tab**：手机侧在等待远程创建期间的 UI 壳，不持有运行时、不持久化、不触发 `onSessionCreated`。
- **隐藏 tab**：桌面侧承载委托会话运行时的 tab，不进入 workbench UI。

## A. 架构与路由

### A.1 角色

桌面 App = 所有委托会话的 authority + session-protocol server，运行时与 server 同进程；手机 = 纯 client。桌面 App 不在场时，手机退回现状：自建 PTY/ACP，`session.create` 仅补列表行。

### A.2 capability 分级路由

客户端必须保存 helloAck 里的 server caps 并求交集（当前 `session_client.dart:270-275` 只取 `epoch`，两端 caps 硬编码 4 条 `session_server.dart:19-24`、`session_client.dart:110-115`）。

| 协商出的 caps | 行为 |
|---|---|
| `intent.session.spawn` + `intent.prompt.send` + `content.terminal.screen` | 全量委托（ACP + PTY） |
| `intent.session.spawn` + `intent.prompt.send`（无 `content.terminal.screen`） | 只委托 ACP；PTY 会话退回手机自建 |
| 其余组合（含仅 `intent.session.spawn`、或无任何 spawn cap） | 全部退回现状 |

ACP 会话不要求 `content.terminal.screen`（已有 `acp.messages` contentDelta），但必须能发 prompt，因此要求 `intent.prompt.send`；PTY 会话要求三个 cap 齐备才委托。`intent.ask.answer` 为可选能力，不参与路由必备条件（缺失时只是不提供 ask 回答入口）。cap 未就绪（client 未 ready / 后台重连中）等同「桌面 App 不在场」。

### A.3 判定入口与一次性归属

路由判定发生在**创建动作发起处**（新建会话 / landing 提交入口，如 `submitWorkspaceLandingMessage` `workspace_session_actions.dart:454`、`requestCreateAndOpenSession` `session_launch_service.dart:259`），**不是** `onSessionCreated` 回调——委托路径下手机不本地创建会话，该回调不会触发。

判定结果写入会话文档字段 `originAuthority`（取值 `desktop` 或 `device:<deviceId>`），重连不重新判定。理由：离线时手机自建的会话若在桌面上线后被重判，会被误当作 desktop-owned 或被重复 spawn。

委托路径：手机发 `session.spawn`，本地先 stage 占位 tab 保持 UI 即时响应（沿用 `session_launch_service.dart:258` 的即时 staging 语义）；占位 tab 不持久化、不持有运行时。**绑定以 `session.list` delta 为触发**（`applied` 只表示受理成功，二者可能乱序）；若 `applied` 已到而 delta 超时未到，用 `session.refresh` 兜底重读列表后再绑定。

不委托路径：维持现有本地创建；`onSessionCreated` 仍发 `session.create`（纯列表行，可排队、幂等），桌面在场时补列表行，不在场时排队重放。

### A.4 spawn 失败回退

`session.spawn` 返回 `rejected` / `expired` / `not_connected` / 超时，一律回退到手机自建路径并记录日志，保证创建始终可用。spawn intent **不排队、不重放**。

## B. 协议与组件

### B.1 新增 typed intent `session.spawn`

字段白名单：`workspaceId`、客户端预生成的 `sessionId`、`team` / `preset` / `cli`、`workingDir`、首条 prompt、`acp` 标志、权限配置。**不透传 `SessionCreateRequest`**，authority 侧用白名单构造创建请求。

- 幂等：`deadline`（现有 `session_authority.dart:155-174` 已校验）+ `fixedSessionId`（`session_launch_service.dart:307`）保证重试不产生第二个会话。
- 返回：等到会话文档持久化后返回 `applied`（`SessionIntentStatus` 现有值，不改枚举，保持 `fromJson` 兼容 `session_models.dart:255,298-301`）；`sessionId` 由客户端预生成，无需在 result 中回传。运行时 connect 继续异步，状态通过 delta / attention 汇报。
- 桌面创建并持久化后自行 `publishSessionList`（`session_authority.dart:221,373-389`），手机经 `session.list` 接收。
- 首条 prompt 由桌面侧在运行时 connect 完成后按现有 `firstPrompt` 路径投递（`client/lib/services/chat/launch/connect/acp_runtime_attach.dart:145,251`），手机不重复投递。

**`applied` 语义补充**：对 `session.spawn` / `prompt.send` / `ask.answer` 这类长任务，`applied` 表示「已受理」，不代表运行时已连接或提交已成功；最终结果以 STATE delta / attention 为准（与前置设计稿 `:108`「取消的收敛以 STATE delta 为准，不以 intentResult 为准」一致）。

### B.2 保留 `session.create`

保持纯列表行通知语义，可排队、幂等、无副作用；与 `session.spawn` 严格区分。`session.remove` / `session.refresh` 不变。

### B.3 `SessionControlPort` 扩展

新增 `spawnSession` / `sendPrompt` / `answerAsk`，维持「`services/session_protocol/` 不依赖 ChatCubit / ACP runtime」的窄接口边界（`session_control_port.dart:1-31`）：参数全部为标量 / typed map，不传对象。

### B.4 桌面 headless 创建入口

把 create / persist / connect 从 `requestCreateAndOpenSession` 的 tab staging 中拆出（`session_launch_service.dart:259-261`、`:263-339`）。推荐做法：桌面为委托会话开一个**隐藏 tab**（不进 workbench UI），使 `ChatSessionActivitySource` 的「Only open tabs are authority-owned sessions」无需改动，cancel / activity / attention 自动生效。

隐藏 tab **不随手机 client 断线回收**（`onClosed` 只清手机侧投影）；仅在桌面 App 退出或会话被显式 `session.remove` 时回收。这样手机断线不中断运行时。

### B.5 安全

`session.spawn` / `prompt.send` / `ask.answer` 全部字段白名单，永不开放通用 exec（前置设计稿 `:247`）；新增 cap 走 hello 协商，字段只加不删。

## C. 数据流

### C.1 创建

```text
手机创建动作
  → 读协商 caps + 会话 ACP 标志，判定路由
  → [委托] session.spawn → 桌面 authority.spawnSession
        → 隐藏 tab + launch pipeline（PTY/ACP 运行时在桌面）
        → repo.createSession 持久化到 shared home（fixedSessionId）
        → publishSessionList → session.list 广播
  → 手机 applyRemoteSessionList 补行、按需读完整文档、绑定占位 tab
  → [不委托] 现有本地创建链路，onSessionCreated 发 session.create
```

### C.2 输入上行

手机 compose → `prompt.send{sessionId, memberId, text, clientTurnId}` → 桌面 `sendPrompt`（`memberId` 与现有 `SessionSeatActivity.memberId` / `turn.cancel` 一致）：

- ACP → `AcpChatRuntimeCubit.sendPrompt`（`acp_chat_runtime_cubit.dart:672`）。
- PTY → `deliverUserCommandToMember` → `issueSubmit` → `FullscreenPtySubmission`（`tab_member_pty_delivery.dart:275,351,397`；状态机见前置 PTY 文档），使用桌面侧 `TerminalScreenGrid` 与 CLI 提交 hook 确认。
- **intent 立即返回 `applied`（已受理，见 B.1 语义补充）**，不做长 await。理由：staging 预算可达 `90 × 2s ≈ 3 分钟`、`sendAckTimeout 12s`（PTY 文档 `:123-126`），会撞客户端 `_pendingTimers` 请求超时（`session_client.dart:124-135,445`）。提交结果由 STATE delta + attention 汇报。
- 去重：`clientTurnId` 在 authority 侧幂等；`FullscreenPtySubmission` 的 `pasted` 单向锁（PTY 文档 `:97-104`）继续防止重复提交。
- `ask.answer` 同理，映射到 TUI 的确认 / 选择语义，不引入按键流。

### C.3 输出下行

- ACP → 现有 `acp.messages` contentDelta（前置设计稿 `:306`）。
- PTY → 新 content kind `terminal.screen`（`SessionContentDelta.kind == 'terminal.screen'`）：序列化 `TerminalScreenGrid`（`rows` / `columns` / `codepointAt` / `flagsAt` / `cursorRow` / 宽字符 spacer，`fullscreen_input_screen_probe.dart:12-23,46-47`），全量 snapshot + 增量 diff，复用 `SessionContentDelta` 的 `seq` / `baseSeq` / `epoch`（`session_authority.dart:391-416`）。
- 手机侧新增只读渲染组件，替换直连 `TerminalSession` 的终端面板；需扩展 `app_shell.dart:3475-3483` 的 `onContentDelta` 分发（当前只放行 `kind == 'acp.messages'`）以消费 `terminal.screen`。chat 视图仍走 home transcript + `onSessionHistoryStale` 重读。
- `turn.cancel`（`session_authority.dart:297-342`）与 `attention`（`:418-435`）已有，直接复用；手机远程 busy 的 Stop 按钮链路不变。

### C.4 明确不做

按键流、原始 PTY 字节、字节级同步、resize / 焦点同步。

## D. 错误、一致性与降级

1. **grid diff 可靠性**：新增 CONTROL 侧 `content.ack{sessionId, memberId, seq}`（客户端 → 服务端）与 `resync` 触发；ack 方向与服务端的 `contentDelta` 相反，因此必须是独立消息类型，不能复用 `SessionContentDelta`。authority 在 `seq` 落后时回全量 grid snapshot。现有 `contentDelta` 无 ack/resume，丢包靠 turn-end invalidation + 2s 轮询收敛（前置设计稿 `:307,326`）；transcript 丢包可重读，网格丢包会花屏或状态错位。
2. **controller lease**：同一 seat 单 controller + 显式 handoff（前置设计稿 `:131`、实现记录 `:328`）。桌面创建的会话两端都能操作，没有 lease 会双发 prompt。
3. **桌面 App 下线**：desktop-owned 运行时随桌面 App 结束（前置设计稿 `:238` 关窗即结束任务）。手机侧显式降级为「已断开 / 只读」，清 busy 投影、不卡 Stop 按钮；epoch 变化由 `authority_moved` 兜底（`session_authority.dart:165-174`）。
4. **桌面 App 后上线**：手机自建会话不接管，只补列表行（`session.create` 排队重放）。
5. **桌面在场但 SSH 断**：后台重连恢复，重连后按 epoch 拿 snapshot（现有 `waitForRecovery` / `_flushPending*`，`session_protocol_controller.dart:194-241,304-377`）。
6. **手机断线**：运行时在桌面不中断；手机重连 attach 按 `since` 续传，落后太多回退全量 snapshot。

## E. 测试与验证

- 桌面侧 `client/tool/session_protocol_probe.dart`（前置设计稿 `:308`）可在不接手机时验证 `session.spawn` / `prompt.send` / `terminal.screen`，即桌面侧可独立开发与验证。
- 新增测试（`client/test/services/session_protocol/` 等）：spawn 幂等 / 超时 / epoch、caps 分级路由、grid diff 编解码与半包 / resync / `content.ack`、长任务 `applied` + 后续事件、controller lease、断线降级。`SessionControlPort` 扩展后，现有测试里的 fake 实现需补齐新方法，但 `session_server_client_test.dart` / `session_authority_test.dart` 的既有断言保持不变（行为等价）。
- 遵守仓库规则：不直接 `flutter test`，用 `cd client && dart run tool/run_tests.dart <paths>`；本地改动只跑覆盖测试 + `flutter analyze`，全量套件仅交付前运行一次。
- 新集成测试使用 `@Tags(['integration'])`。

## 分阶段

本 spec 是总体设计，范围跨协议 / 创建 / 输入 / 输出 / UI 多个子系统；实现按下列阶段拆成独立 plan，每阶段一个 writing-plans 周期，不合并为单个实现计划。

1. **协议与能力层**：caps 落地（客户端保存 server caps）+ typed `session.spawn` + 桌面 headless 创建入口 + 分级路由。桌面侧独立，probe 可验。
2. **ACP 输入闭环**：`prompt.send` 接入 ACP `sendPrompt`，最小可用。
3. **PTY 输入**：`prompt.send` 接入 `FullscreenPtySubmission`，`ask.answer` 落地。
4. **PTY 输出**：`terminal.screen` grid diff + 手机只读渲染 + ack / resume / resync。
5. **收敛**：controller lease、桌面下线降级、测试补齐，最后把路由切到全量委托。

阶段 1–4 期间，手机自建模式始终可用，可作为回退。

## 相关文件

| 关注点 | 路径 |
|---|---|
| session-protocol 帧 / envelope / authority / server / client | `client/lib/services/session_protocol/` |
| 协议控制器（角色、pending 队列、caps 待落地） | `client/lib/services/session_sync/session_protocol_controller.dart` |
| authority 控制端口 | `client/lib/services/session_protocol/session_control_port.dart` |
| ChatCubit 侧控制端口 / 活动源 | `client/lib/services/session_sync/chat_session_control_port.dart`、`chat_session_activity_source.dart` |
| 创建管线 / tab staging | `client/lib/services/chat/launch/session_launch_service.dart` |
| 创建接线（onSessionCreated） | `client/lib/app/app_shell.dart:3506-3537` |
| 角色选择 / SSH 通道 | `client/lib/app/session_protocol_home.dart`、`client/lib/services/ssh/session_protocol_ssh_channel.dart` |
| PTY 投递状态机 / 网格探针 | `client/lib/services/chat/runtime/pty/` |
| ACP prompt 与 contentDelta | `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` |
| 桌面侧调试工具 | `client/tool/session_protocol_probe.dart` |
