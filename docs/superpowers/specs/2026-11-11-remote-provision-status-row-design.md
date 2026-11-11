# 远程环境准备改为聊天状态行反馈

## 背景

移动端（Android）的终端固定走 SSH，AI CLI 跑在远程主机上（`onboarding_zh.i18n.json:28`、
`startup_gate.dart:26`）。会话是懒启动的：打开标签页、只读历史不会启动 agent，真正的连接
发生在下一次发送消息（"connect-then-send"，`chat_cubit.dart:1173-1176`；
`session_history_review_submit.dart:88` 先 `connectWorkspaceSession` 再投递）。

连接 SSH 目标前需要"准备远程环境"：确认/安装 Node 与 CLI、下载 adapter、把 app-data 与
工作区配置 materialize 到远端（`workspace_provisioner.dart:117-152`）。这一步可能持续几十秒
到两分钟（`SshStorageIo.provisionPhaseTimeout = 2min`，`ssh_storage_io.dart:17`）。

当前实现在这段时间用 `ChatWorkbenchRemoteProvisionView` 盖住整个工作区：

- `chat_workbench.dart:560` 计算 `showRemoteProvision = remoteProvision != null && !session.isRunning`；
- `chat_workbench_overlay.dart:29` 的 `resolveChatWorkbenchOverlay` 让 `showRemoteProvision`
  无条件压过其它 overlay（`if (showRemoteProvision) return ChatWorkbenchOverlay.remoteProvision`）；
- `chat_workbench.dart:634` 在 `showRemoteProvision` 时渲染全屏 `ChatWorkbenchRemoteProvisionView`
  （标题「正在准备远程环境（host）」+ `CliInstallProgressPanel` 进度条）。

结果是：用户点发送后，聊天界面被整块替换为进度页，看不到已发出的消息气泡、无法滚动历史。
用户希望发送与等待始终停留在聊天界面（或新建对话打开的聊天标签页）里。

值得注意的是，聊天界面**本来就有**为连接期设计的状态行：
`SessionHistoryLiveChrome.starting` 的注释写明它是"乐观气泡已上屏、seat PTY 还没好（connect /
landing deliver）"的反馈，且 "Chat suppresses the full-screen session-starting overlay, so this
footer is the only connect feedback after an optimistic bubble"
（`session_history_live_chrome.dart:6-8, 40-42`）。该 footer 渲染在消息列表底部，是
一个小转圈 + 一行文案（`session_history_thread.dart:1003` `_buildRunningInMessage`），
当前文案为「启动中…」（`session.historyStarting`）/「运行中…」（`session.historyRunning`）。
全屏遮罩是后来插入的、与它重复的反馈通道。

## 目标

1. Chat 视图（含新建对话 create+send 打开的标签页）在远程准备期间不显示任何全屏遮罩，
   聊天界面完整保留：已发送的用户气泡、历史消息可滚动、输入框可见可用。
2. 准备状态由**现有的那一行状态行**承载，不新增行、不加进度条、不改变 spinner。
3. 状态行文案固定为「正在准备远程环境…」，全程不随阶段变化、不带主机名。
4. 桌面本地 PTY 行为完全不变。
5. 准备失败时错误仍可见、可重试。

## 非目标

- 不删除 `ChatWorkbenchRemoteProvisionView`、`memberRemoteProvision` 状态、
  `setMemberRemoteProvisionProgress` 上报链路；Terminal 视图继续使用它们。
- 不改 Terminal 视图在准备期间的行为（仍显示现有遮罩）。
- 不改远程准备本身：不缩短、不跳过、不并行化 materialize / CLI 安装。
- 不新增或改写 i18n key；复用现有 `session.remoteProvisionPreparing`。
- 不新增进度条、百分比、阶段明细、日志面板，也不把状态做成消息气泡或浮层卡片。
- 不改 `shouldMountWorkbenchTerminal` 的挂载判断。
- 不改会话懒启动策略、connect-then-send 流程、SSH 连接复用逻辑。

## 行为定义

| 场景 | 准备期间的表现 |
|---|---|
| Chat 视图，SSH 目标 | **无遮罩**；状态行显示「正在准备远程环境…」，聊天内容保持可见可滚动 |
| 新建对话（landing create+send） | 打开会话标签页后进入 Chat 视图，同上；合成用户气泡 + 状态行同时可见 |
| Chat 视图，本地 PTY（桌面默认） | `memberRemoteProvision` 恒为 null，行为与现状完全一致 |
| Terminal 视图，SSH 目标 | 保留现有 `ChatWorkbenchRemoteProvisionView` 全屏遮罩（含错误卡片） |
| 准备成功 | 进度置 null（`session_shell_connector.dart:786`），状态行回到既有逻辑 |
| 准备失败 | 状态行不显示准备文案；错误由 compose 区 `SessionLaunchErrorBanner`（带重试）呈现 |

## 状态行设计

沿用 `session_history_thread.dart:1003` 的 `_buildRunningInMessage`：左对齐、`TpIndeterminateSpinner`
（14px）+ 单行 `Text`（`maxLines: 1`、`TextOverflow.ellipsis`、`smColored(onSurfaceVariant)`）。
不新增 Widget，不新增行。

准备期间仅**替换文案**：

- 使用 `context.l10n.session.remoteProvisionPreparing`（zh「正在准备远程环境…」，
  en「Preparing remote environment…」，`session_zh.i18n.json:56`）。该 key 已存在，
  当前被遮罩标题使用，因此无需改 `client/lib/i18n/*`、无需 `dart run slang`。
- **不带主机名**：状态行是单行且会省略号，长主机名（如 `hhoa-ROG-Zephyrus-G16-GU605MV-GU605MV`）
  会被截断，反而更差。主机名信息在 Terminal 视图遮罩里仍然保留。
- 不使用 `CliInstallPhase` 的阶段文案（「正在安装 CLI…」「正在同步远程工作区…」等）：
  用户明确要求固定一句、不要进度类反馈。
- 不加进度条：`LinearProgressIndicator` 只属于 `CliInstallProgressPanel`，本次不复用该组件。

## 数据流

```
setMemberRemoteProvisionProgress (chat_connect_state_mixin.dart:136)
  → tab.memberRemoteProvision[memberId] = progress | null
  → emit(provisionVersion + 1)

session_chat_message_area.dart  buildChrome()                  [新增，独立 select]
  progress = seatSelect<ChatCubit, MemberRemoteProvisionProgress?>(
    (c) => c.tabStore.getOpenTabBySessionId(sid)
             ?.memberRemoteProvision[shellMemberId])
  liveChrome = SessionHistoryLiveChromeX.resolve(...)          [既有]
  provisioningLabel = liveChrome == background
      ? null
      : remoteProvisionFooterLabel(
          progress, context.l10n.session.remoteProvisionPreparing)
  → 若 provisioningLabel != null 且 liveChrome == none，
     把传给下游的 liveChrome 提升为 starting（保证 footer 一定出现）
SessionHistoryReviewMessages (session_history_review_messages.dart)  [透传新参数]
  → SessionHistoryThread (session_history_thread.dart)              [透传新参数]
      _buildRunningInMessage:
        label = provisioningLabel ?? 既有 switch(liveChrome) 文案
```

`session_chat_message_area.dart` 里的 `seatSelect` 是**独立的一次读取**，不从
`chat_workbench.dart:429` 的 `remoteProvision` 传下来。原因是 `chat_workbench.dart:394-423`
有两条 body 路径：`session == null && view == chat` 时直接构建 `_buildSessionChatView`
（不经过 `_buildTerminalBody`，本来就没有遮罩）；`session != null` 时才走
`_buildTerminalBody` 的 Stack。两条路径都会挂载 `SessionChatView` → `session_chat_message_area.dart`，
所以在那里读取可同时覆盖两者，且无需改动 `chat_workbench.dart` 的参数传递。

`seatSelect` 的返回值直接用 progress 对象（每次 `setMemberRemoteProvisionProgress` 都构造新
实例，clear 时变 `null`），配合 `emit(provisionVersion + 1)` 可保证状态变化时重建；实现时
不要把它退化成只 select 一个 bool 后再查表，否则中间阶段不会刷新。

新增一个可选 `String?` 参数（命名 `provisioningLabel`），从 `session_chat_message_area.dart`
的 `buildChrome` 透传两层到 `SessionHistoryThread`。所有现有调用方不传该参数时行为不变。

"由 progress 得到文案"抽成一个纯函数，放在 `session_history_live_chrome.dart`，与
`resolve()` 同处一层，便于单测且不依赖 `BuildContext` 之外的东西：

```dart
String? remoteProvisionFooterLabel(
  MemberRemoteProvisionProgress? progress,
  String preparingLabel, // 调用方传 context.l10n.session.remoteProvisionPreparing
) {
  if (progress == null || progress.hasFailed) return null;
  return preparingLabel;
}
```

传 `String` 而非 `AppLocalizations`，使该文件保持零 UI 依赖；文案仍由
`context.l10n.session.remoteProvisionPreparing` 提供（`session_chat_message_area.dart`
已有 `context.l10n` 用法）。

`liveChrome == background` 时 `buildChrome` 直接传 `null`：后台任务文案（可能带具体任务描述）
优先，因为此时并不处在"发送消息后的等待"中。纯函数本身只判断 `progress`。

`overlay` 侧：

- `resolveChatWorkbenchOverlay`（`chat_workbench_overlay.dart:24`）改为：先算
  `resolveWorkbenchOverlay(...)` 得到 `base`；仅当 `showRemoteProvision && base != chat`
  时返回 `remoteProvision`，否则返回 `base`。即 Chat 视图永远返回 `chat`。
- `chat_workbench.dart:634` 的渲染分支与 `:603` 的 `chatOverlayHidesTerminal` 改用
  `overlay == ChatWorkbenchOverlay.remoteProvision` 驱动，而不是裸 `showRemoteProvision`，
  保证 resolver 是唯一真相源。
- `shouldMountWorkbenchTerminal`（`chat_workbench.dart:565`）**继续传裸
  `showRemoteProvision`**：准备期间 PTY 正在连接，终端必须保持挂载，此判断不动。

## 失败与结束

- 失败：`_prepareConnectWithProvisionUi` 的 catch 会写入带 `error` 的 progress 并 rethrow
  （`session_shell_connector.dart:788-801`），外层 `connect()` 通过 `failSessionConnect`
  → `setLaunchError` 写入 launchError。`SessionLaunchErrorBanner`
  （`session_chat_compose_section.dart:722` `_composeLaunchErrorStrip`）据此显示错误与重试按钮。
  `provisioningLabel` 的条件含 `!progress.hasFailed`，失败后状态行不再显示准备文案，
  避免"失败后一直挂着准备中"。
- 成功：进度被置 null，状态行恢复为 `starting`/`running`/`none` 的既有文案。
- Chat 视图不再渲染遮罩，因此不会出现遮罩里的错误卡片；Terminal 视图仍保留原有错误卡片
  （`ChatWorkbenchRemoteProvisionView` 的 `hasFailed` 分支）。

## 测试

- `client/test/pages/chat/chat_workbench_overlay_test.dart`：把
  「remote provision wins over Chat and connect spinner」改为断言 Chat 视图 + provision → `chat`；
  新增 Terminal 视图 + provision → `remoteProvision` 的用例；保留其余用例。
- 新增 `remoteProvisionFooterLabel` 单测（放在 `session_history_live_chrome` 相关测试文件）：
  `progress == null` → null；正常 progress → 「正在准备远程环境…」；`hasFailed == true` → null。
- 新增 `SessionHistoryThread` widget 测试：传入 `provisioningLabel` 时 footer 显示
  「正在准备远程环境…」；未传（null）时仍显示既有「启动中…」/「运行中…」。
- `client/test/pages/chat/chat_workbench_remote_provision_view_test.dart` 保留不动
  （Terminal 视图仍使用该遮罩）。
- 按 `docs/DEVELOPMENT.md` 的测试循环：先 `flutter analyze`，再用
  `dart run tool/run_tests.dart` 跑上述定向文件，最后完整套件跑一次。

## 验收

1. 移动端（SSH 目标）在新建对话输入首条消息并发送，全程停留在聊天界面：
   可见自己的用户气泡、可上下滚动、输入框可用。
2. 消息列表底部状态行显示小转圈 +「正在准备远程环境…」，不出现进度条、不出现全屏遮罩、
   不出现第二条状态行。
3. 远程环境就绪后状态行自然过渡到既有「运行中…」/ 回复内容。
4. 已有会话里再次发送触发重连时表现相同。
5. 桌面本地 PTY 会话无任何可见变化。
6. Terminal 视图下准备期间仍显示原有遮罩；准备失败时 Chat 视图由 compose 错误横幅给出
   可重试的提示。
