# 自动化遵循 CLI 的 ACP 偏好（不新增 automation 配置）设计

日期：2026-11-01
状态：已评审（待实现）

## 背景

TeamPilot 的定时任务（automation）目前完全不感知 ACP：

- `services/automation/`、`models/automation.dart`、`pages/automations/` 中没有任何 `acp` 引用。
- `AutomationDispatcher._createSessionForLaunchPrompt` 构造 `SessionCreateRequest` 时不传
  `acp`（`automation_dispatcher.dart:261-289`），该字段默认 `false`
  （`session_create_request.dart:26`）。桌面端 Claude / Codex / Cursor / OpenCode 的
  `launchPrompt` 任务因此一律创建 PTY 会话，即使 CLI 设置里已开启「个人会话使用 ACP 聊天」。
- 团队模式相反：`seedClaudeMemberAcp` 等四个 seed 在 `SessionCreateRequest` 中默认 `true`
  （`session_create_request.dart:27-30`），automation 未显式传值，于是 mixed 团队的 ACP 席位
  被无条件打开，与用户偏好无关。
- 投递通道只有 PTY：`TabTeamBusGateway.deliverUserCommandToMember` 调
  `sessionRuntime.deliverUserCommandToMember(directToPty: true)`，最终落到
  `TabPromptDeliveryCommands.submit` 取 `memberShells[memberId]`
  （`tab_member_pty_delivery.dart:642-645`）。ACP 席位是 terminal-less 的，不在
  `memberShells` 里（`session_connect_executor.dart:105-112`），提交直接返回 `failed`。
  网关又把返回值丢掉（`automation_bus_gateway.dart:26-38`），于是 run 被记为
  `completed`，用户看到的是「任务跑了但什么也没发生」。

## 目标

让 automation 复用 CLI 设置里已有的 ACP 偏好，覆盖三段：

1. `launchPrompt` 的个人（Simple）会话按该 CLI 的偏好决定传输；
2. 团队 mixed ACP 席位按同一份偏好打标（不再写死 `true`）；
3. `scheduledMessage` / `launchPrompt` 的投递真正送达 ACP 会话，失败可见。

非目标：

- 不新增 automation 字段、编辑器开关或迁移；
- 不改 catalog MCP 的 `create_automation` 工具契约（无 ACP 参数）；
- 不迁移已有 automation 绑定的旧 PTY 会话；
- 不改 landing / history 的投递行为（只把策略下沉成共享实现）。

## 决策

- 偏好来源：`SessionPreferences.personalAcpDefaultFor(cli)`
  （`models/session_preferences.dart:154-156`，缺省 `true`），在**派发时**读取，不落盘快照。
  UI 的 `readPersonalAcpDefault` 走同一份数据。
- 权限：automation 会话固定 `LaunchSecurityPolicy.fullAccess`
  （`models/launch_security_policy.dart:19`）。无人值守任务若用 `ask` 档会卡在审批卡片上；
  PTY 自动化现状同样是全权限。
- 传输策略：抽一条服务层共享实现（方案 1），gateway 改为返回投递结果；不把 ACP 分支下沉到
  `TabMemberPtyDelivery`（其 `String?` 返回值表达不了 ACP 的三态结果，且 landing / history
  已在该层之上自行处理 ACP）。

## 架构与接线

### 新增文件

- `client/lib/services/chat/launch/session/seat_prompt_delivery.dart`
  - `bool seatUsesAcp(AppSession session, String memberId)`：即
    `isAcpChatSession(session) || isAcpChatSeat(session, memberId)`。
  - `Future<SeatPromptDeliveryResult> deliverSeatPrompt({session, memberId, message,
    acpRuntime, ptySubmit})`：ACP → `acpRuntime.sendPrompt`（launching 阶段内部自动排队），
    否则调用 `ptySubmit`。返回 `delivered` / `runtimeUnavailable` / `rejected`。
  - 该结果是座位级（landing 只关心成功与否）；automation 侧的
    `AutomationDeliveryOutcome` 是网关级，多带一个失败原因码，由 gateway 映射。
- `client/lib/services/chat/launch/session/launch_acp_policy.dart`
  - 从 `pages/home_workspace/workspace/claude_acp_launch_switch.dart:14-44` 移入
    `personalAcpAllowed` 与 `resolveLaunchAcp`（Android 禁用 + `canChooseTransport` 判定）。

### 既有文件改动

1. `pages/home_workspace/workspace/workspace_landing_prompt_delivery.dart`
   `deliverWorkspaceLandingPrompt` 改为委托 `deliverSeatPrompt`，保持 `Future<bool>` 返回；
   `landingPromptUsesAcp` 改为转发 `seatUsesAcp`（保留导出，调用方不变）。
2. `pages/home_workspace/workspace/claude_acp_launch_switch.dart`
   re-export `launch_acp_policy.dart` 的 `resolveLaunchAcp`，UI 调用点零改动。
3. `services/automation/automation_bus_gateway.dart`
   - 接口改为 `Future<AutomationDeliveryOutcome> deliverUserCommandToMember(...)`，
     outcome 携带 `delivered` 与失败原因码。
   - `TabTeamBusGateway` 构造新增 `ChatTabStore tabStore`、
     `Future<void> Function(String sessionId) activatePersonalAcp`、
     `Future<void> Function(String sessionId, String memberId) activateMemberSeat`。
   - 投递流程：取 tab 与 `AppSession` → `acpRuntimeForView(...)` →
     为空且 `seatUsesAcp` 则按会话类型调用 `activatePersonalAcp(sessionId)`
     （个人）或 `activateMemberSeat(sessionId, memberId)`（mixed 席位）后重取
     （上限 `_memberReadyTimeout`）→ ACP 走 `sendPrompt`，否则走现有 PTY submit。
   - 就绪等待复用现有链路：mixed 席位由 `_awaitAcpSeatInputReady`
     （`tab_member_materializer.dart:459`）等到 `AcpChatPhase.ready|idle`；个人 ACP
     在 launching 阶段的 `sendPrompt` 会排队，无需额外等待。
4. `services/automation/automation_dispatcher.dart`
   - 新增注入 `bool Function(CliTool cli) personalAcpDefaultFor`。
   - 个人模式：`simpleIdentity` 解析出 `cli` 后
     `acp: resolveLaunchAcp(isPersonal: true, cli: cli,
     requested: personalAcpDefaultFor(cli))`，并显式
     `acpPermission: LaunchSecurityPolicy.fullAccess`。
   - 团队模式：四个 seed 改为 `personalAcpDefaultFor(CliTool.claude / codex / cursor /
     opencode)`。
   - 投递结果非 `delivered` 时写 `dispatchFailed`（见下）。
5. `app/app_shell.dart:2579-2590`
   - 注入 `personalAcpDefaultFor: sessionPreferencesCubit.state.preferences.personalAcpDefaultFor`；
   - `TabTeamBusGateway` 传入 `chatCubit.tabStore`，
     `activatePersonalAcp: chatCubit.retrySessionLaunch`，
     `activateMemberSeat: chatCubit.ensureMemberTerminalForView`。

### 依赖边界

`seat_prompt_delivery` / `launch_acp_policy` 只依赖 models 与 `chat_tab` 的判定函数；
`TabTeamBusGateway` 依赖 `ChatTabStore`（已在 `services/chat/session/chat_tab.dart`），
不引用 `ChatCubit`，激活能力以纯回调注入，保持 automation 层可单测。

## 数据流

```
AutomationScheduler → AutomationDispatcher.dispatch
  → personal: cli = SimpleLaunchIdentity.resolve(...).cli
      acp = resolveLaunchAcp(isPersonal: true, cli: cli, requested: pref(cli))
      SessionCreateRequest(acp: acp, acpPermission: fullAccess)
  → team: seed{Claude,Codex,Cursor,Opencode}MemberAcp = pref(对应 CLI)
  → requestCreateAndOpenSession / requestOpenSession(connectImmediately: true)
      personal ACP → attach AcpChatRuntimeCubit（session_connect_executor.dart:105-112）
      mixed ACP 席位 → attachMemberAcpRuntime（同文件 :126-143）
  → busGateway.deliver
      seatUsesAcp → acpRuntimeForView → sendPrompt
      否则 → TabPromptDeliveryCommands.submit（现有 PTY）
  → repository.upsertRun / upsert
```

## 失败语义

| 场景 | run 状态 | `error` |
|---|---|---|
| ACP 运行时激活后仍无 cubit（超时） | `dispatchFailed` | `acp_runtime_unavailable` |
| `sendPrompt` 返回 false（在跑别的回合 / 已结束） | `dispatchFailed` | `acp_prompt_rejected` |
| PTY 提交未确认或座位无 shell | `dispatchFailed` | `pty_submit_failed` |
| 会话解析失败（现有行为） | `skippedUnavailable` | 不变 |

三种 `dispatchFailed` 都沿用现有失败路径推进 `nextRunAtMs`，不会让调度卡死。
错误串只进 `AutomationRun.error`（诊断用），不走 l10n。

## 兼容性与安全

- 偏好缺省 `true`，因此桌面端 Claude / Codex / Cursor / OpenCode 的新 automation 会话
  会**默认从 PTY 变成 ACP**——这正是本设计的目的，需在实现说明里提示用户。
- Android 仍被 `resolveLaunchAcp` 挡回 PTY；ACP-only CLI（Gemini / CodeBuddy）继续由
  `session_provisional_builder.dart:45-49` 推导为 ACP，与偏好无关。
- 已有 automation 不动：`reuseSession` 绑定到旧 PTY 会话的继续用 PTY（会话传输在创建时
  固定），不做迁移；改动只影响之后新建的会话。
- 团队 seed 只在 mixed + local + CLI 具备 `AcpCapability` 时生效
  （`member_acp_stamp.dart:14-44`），native team 仍为 PTY。
- automation 会话固定 `fullAccess`：无人值守场景下 `ask` 档必然卡死；与 PTY 自动化现状一致。

## 测试

新增：

- `client/test/services/chat/seat_prompt_delivery_test.dart`
  ACP 有 cubit → `delivered` 且不触发 PTY 回调；无 cubit → `runtimeUnavailable`；
  `sendPrompt` 返回 false → `rejected`；PTY 席位 → 走 `ptySubmit`。
- `client/test/services/automation/automation_dispatcher_test.dart` 追加：
  偏好开启 → `SessionCreateRequest.acp == true` 且 `acpPermission == fullAccess`；
  偏好关闭 → `acp == false`；团队 seed 跟随偏好；
  gateway 返回失败 → run 状态 `dispatchFailed` 且 `error` 匹配上表。

更新（仅返回类型）：

- `test/support/post_frame_test_harness.dart` `_NoopAutomationBusGateway`
- `test/cubits/automation_cubit_test.dart` `_NoopBusGateway`
- `test/services/automation/automation_dispatcher_test.dart` `_RecordingBusGateway`、
  `_SlowBusGateway`
- `test/services/automation/automation_scheduler_test.dart` `_RecordingBusGateway`

收尾：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`，
`dart run tool/run_tests.dart` 跑上述文件，最后一次全量。

## 未决 / 后续

- 若希望「偏好切换后自动把新 automation 也套用到旧绑定会话」，需要另开一次性的会话迁移，
  本次不做。
- `read_automation` / UI 暂不展示「本次是否会走 ACP」；如需可加派生字段，不落盘。
- ACP 席位在自动化触发时的冷启动时间明显长于 PTY，执行历史目前只记录开始/结束时间，
  暂不加分段耗时。
