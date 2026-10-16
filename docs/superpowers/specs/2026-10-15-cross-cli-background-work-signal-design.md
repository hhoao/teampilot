# 跨 CLI 后台工作信号与"仍在跑"指示器

Date: 2026-10-15
Status: 设计中（方向已定：两条轴分开展示 —— 在途回合「运行中」，回合外「后台任务」）

## 问题

会话"运行中"目前只由注意力驱动：

```
ChatCubit.sessionBusyFromAttention → AgentAttentionCubit.sessionIsAgentActive
  → SessionBusyReason.attention → SessionActivity.isBusy
```

当 CLI **回合结束后**仍在干活（后台 shell 任务、后台子 agent、monitor、workflow），
seat 已经 `done`，界面显示"会话结束"，用户以为没在跑。已有的 `SeatLeaseCubit`
只是用来**保护终端不被回收**，没有任何 UI 信号（见
`docs/specs/2026-09-07-background-task-terminal-protection-design.md` 非目标 #6）。

## 目标

- 会话在**回合外仍有活没干完**时，界面明确显示"后台任务运行中"。
- 覆盖所有 CLI：claude / flashskyai / codex / cursor / opencode / gemini，能拿到信号的就接。
- 子 agent 算"活"：在父回合内的子 agent 归注意力（"运行中"），回合外的子 agent（后台/派生）归后台任务。
- 不改 `SessionBusyReason` / `isReadyToChat` / 空闲通知 / 配额语义（那会让"后台在跑"误伤这些判断）。

## 两条轴

| 轴 | 语义 | 状态载体 | 展示 |
|----|------|----------|------|
| **在途回合** | 需要操作员 / 正在一个回合里 | `AgentAttentionCubit`（已有） | 「运行中…」（已有） |
| **回合外仍在跑** | 回合已结束，但还有 live 工作 | `SeatLeaseCubit`（已有，新增读取方） | 「后台任务运行中…」（新增） |

判定：先看在途回合；没有在途回合但有 lease → 后台任务。二者都不满足 → 无 footer。

> 传输依赖：后台轴只在 **PTY** 会话成立（claude hook / opencode plugin 都跑在 CLI 进程侧）。
> **ACP 会话看不到后台轴**——见文末「已知限制（ACP 会话）」。

## 各 CLI 信号矩阵（本机反编译/实测证据）

### 后台 shell / 长任务

| CLI | 信号 | TeamPilot 现状 |
|-----|------|----------------|
| **claude** 2.1.211 | `Stop` hook 输入带 `background_tasks[]`：`{id, type('shell'\|'subagent'\|'monitor'\|'workflow'), status, description, command?, agent_type?, server?, tool?, name?}`；文案明确 L"If in-flight background work ... Lets hooks distinguish session is done from session paused waiting for background work" | 只用了 `PreToolUse(Bash, run_in_background)` + `<task-notification>` 的旧启发式 |
| **flashskyai**（2026-04-29 构建） | fork 自较早 claude：有 `run_in_background`，**无** `background_tasks` | 复用 claude-family normalizer（latch 生效） |
| **codex**（2026-09-11 构建） | 无 `run_in_background` / `background_tasks` | 无（正确：没有后台 shell 概念） |
| **cursor** 2026.10.14 | `beforeShellExecution` / `afterShellExecution` hook，工具带 `is_background` | 只把 `beforeShellExecution` 当 working，未识别后台 |
| **opencode** 2.0.24 | 事件 `session.shell.started` / `session.shell.ended`，负载 `data.shell = {id, command, status, exit, metadata.background}` | 未接 |
| **gemini**（2026-07-06） | 工具 `run_shell_command` 有 `is_background`；hook 事件存在（`BeforeTool` 等）但 TeamPilot 侧 gemini hook 是 no-op | 未接 |

### 子 agent

| CLI | 信号 | TeamPilot 现状 |
|-----|------|----------------|
| **claude** 2.1.211 | `SubagentStart`/`SubagentStop`（输入带 `agent_id`/`agent_type`）；**Agent 工具默认 `run_in_background: true`**（"Agents run in the background by default"） | 只注册了 `SubagentStop`，没注册 `SubagentStart` → 后台子 agent 无跟踪 |
| **flashskyai** | 有 `SubagentStart` | 同 claude（只注册了 Stop） |
| **codex** | `SubagentStart`/`SubagentStop` | ✅ 已注册，计数完整 |
| **cursor** | 有 `subagentStart`/`subagentStop` | 只注册 `subagentStop`，且 `CursorChatInteraction.normalize` 未处理该事件（返回 null） |
| **opencode** | 无独立事件；子会话 = `session.created`/`session.updated` 带 `info.parentID`（DB `session_v2.parent_id`），子会话 `session.idle` 结束 | 未接；`OpencodeSideResolver._pickRunningChild` 已能查运行中子会话，但只用于历史 live refresh |
| **gemini** | 有 subagent 概念，无 subagent hook | 未接 |

## 设计

### 1. claude：用 `Stop.background_tasks` 作为权威来源

`Stop`（以及 `SubagentStop`）hook 输入里的 `background_tasks[]` 是 claude 自己维护的
"当前在途后台工作"快照，比 `run_in_background` + 再调用通知的启发式更准，且天然包含
subagent / monitor / workflow。

- `background_task_latch.dart` 新增：`List<BackgroundTaskRef> parseBackgroundTasks(body)`
  → `{id, type}`。
- `ClaudeFamilyAgentStatusNormalizer` 在 `Stop` / `SubagentStop` 上填充
  `AgentStatusEvent.backgroundTaskRefs`。
- `seat_lease_projection`：收到快照 → **对账**该 seat 的 `backgroundTask` lease
  （缺的 acquire、不在快照里的 release），而不是只做增量 acquire。这样：
  - 旧 latch 的 `tool_use_id` lease 仍保留（终端保护，兜底旧版本 claude / flashskyai）；
  - 快照把"已完成"的任务清掉，不依赖 `task-notification` 一定到达。
- `<task-notification>` 仍是增量 release 路径：同时尝试 `<tool-use-id>` 与 `<task-id>`
  两个 id 空间（`background_tasks[].id` 是 task id，不是 tool_use_id）。

> 兼容：`background_tasks` 缺省（旧 claude / flashskyai）→ 行为与今天一致。

### 2. claude / flashskyai：注册 `SubagentStart`

`SubagentStart` 已在 claude 2.1.211 与 flashskyai 可用，注册后
`AgentAttentionCubit._applySubagentLifecycle` 的并发子 agent 计数生效，父 `Stop`
在子 agent 未结束时保持 `working`（"运行中"），最后一个子结束才 `done`。
纯配置改动：`hook_event.dart` 的支持矩阵 + `docs/cli-formats/hooks.md`。

### 3. opencode：plugin 上报 shell + 子会话

`agent_status_plugin.dart` 的 `handleEvent` 增加：

- `session.shell.started`（`data.shell.metadata.background === true`）→ `post('shell.started', {id, command})`；
  `session.shell.ended` → `post('shell.ended', {id, output})`。
- 子会话跟踪：`session.created` / `session.updated` 且 `info.parentID` 非空 → 记入
  `childSessionIds`，`post('subagent.started', {id: sessionID})`；
  该子会话 `session.idle` / `session.deleted` → `post('subagent.stopped', {id})`。
- **修正**：`session.idle` 只对**根会话**上报 `session.idle`（当前对所有会话 ID 都上报，
  子会话 idle 会把父 seat 提前标成 done）。

`OpencodeChatInteraction.normalize` 增加映射：

- `shell.started` → `backgroundTaskStarted`（id = shell id）
- `shell.ended` → `taskNotificationToolUseId`（id = shell id）
- `subagent.started` / `subagent.stopped` → `AgentStatusEvent(state: working, hookEventName:
  'SubagentStart'/'SubagentStop', toolAgentId: id)`，复用现有子 agent 计数机。

### 4. cursor / gemini / codex（后续增量）

- **cursor**：`subagentStart` 注册进矩阵 + `CursorChatInteraction.normalize` 处理
  `subagentStart`/`subagentStop`（带 `agent_id`）；`beforeShellExecution` 负载若带
  `is_background` 则发后台信号。
- **gemini**：需要先做 gemini 的 hook writer（现在是 no-op）——单独立项，不阻塞本设计。
- **codex**：无后台 shell；子 agent 已覆盖，无需改动。

### 5. 指示器（UI）

只读 `SeatLeaseCubit`，**不改** `SessionBusyReason`：

- `sessionHasLeases(sessionId)`（已有方法，目前无消费方）→ 新增消费方。
- **History tip chrome**：`!turnInFlight && sessionHasLeases` → 显示
  `sessionHistoryBackgroundRunning`（"后台任务运行中…"，配一个非 spinner 的图标，
  避免与"运行中"的 spinner 混淆）。
- **会话列表 / tab**：同一信号加一个次要标记（presentation-only）。
- 回收保护逻辑不变（`TabMemberReclaimWatch` 已按 seat 读 lease）。

## 非目标

- 不把 `backgroundTask` 加进 `SessionBusyReason`（会污染 `isReadyToChat`、空闲通知、
  资源管理器"运行中会话"计数）。
- 不做 gemini hook writer（单独立项）。
- 不改 lease TTL / 回收阈值。

## 测试

- `background_task_latch_test`：`background_tasks` 解析（空 / 多类型 / 缺字段）。
- `claude_family_agent_status_normalizer_test`：`Stop` 带/不带 `background_tasks`。
- `seat_lease_projection_test`：快照对账（acquire + release 差集）、notification 双 id。
- `hook_event_test`：claude/flashskyai `SubagentStart` 支持。
- opencode：plugin 源字符串断言（含新分支）；`OpencodeChatInteraction.normalize`
  的 shell/subagent 映射；子会话不触发根 `session.idle`。
- UI：`session_history_live_chrome` 解析（后台态优先于 none、低于在途回合）、tip chrome widget 测试。
- 全部走 `dart run tool/run_tests.dart`。

## 实施阶段

1. **阶段 1（核心可见）**：claude `background_tasks` 对账 + 指示器（tip chrome + `sessionHasLeases`）。flashskyai/codex 沿用现有行为。
2. **阶段 2（opencode）**：plugin shell + 子会话上报，normalize 映射，根/子 idle 修正。
3. **阶段 3（claude/flashskyai SubagentStart 注册）**：子 agent 计数。
4. **阶段 4（可选）**：cursor `subagentStart` + `is_background`；gemini hook writer。

## 实施状态

- **阶段 1：已完成（未提交）**
  - `SeatLeaseKind.inFlightTask` + `SeatLeaseCubit.replaceKind`（快照对账，60 分钟 TTL 兜底）。
  - `parseBackgroundTasks` / `taskNotificationTaskId`（`background_task_latch.dart`）。
  - `<task-notification>` 释放路径同时尝试 `<tool-use-id>`（旧 latch 租约）与 `<task-id>`
    （`background_tasks[]` 快照租约，id 空间不同）；两者都无则不发释放。
  - `AgentStatusEvent.inFlightTaskIds`（`null` = 载荷没带该字段，保持原状；`[]` = 权威清空）。
  - `ClaudeFamilyAgentStatusNormalizer`：`Stop`/`SubagentStop` 填充快照；`seatLeaseProjection` 对账。
  - `SessionHistoryLiveChrome.background`：无在途回合但有 lease 时显示「后台任务运行中…」，
    用静态图标（不是 spinner）与「运行中…」区分。
  - `session_chat_message_area` 经 `ChatCubit.seatLeaseCubit` 读取租约（不强制要求
    `SeatLeaseCubit` provider，避免测试基建改动）。
  - `main.dart` / `AppShell` 暴露并 provide `SeatLeaseCubit`。
  - 测试：`background_task_latch_test`、`seat_lease_cubit_test`、`seat_lease_projection_test`、
    `claude_family_agent_status_normalizer_test`、`session_history_live_chrome_test`、
    `session_history_thread_test`。
- **阶段 2（opencode）：已完成（未提交）**
  - plugin 上报 `session.shell.started/ended`（仅 `shell.metadata.background`）与
    `session.created/updated/deleted`（`info.parentID` 子会话）→ `subagent.started/stopped`。
  - plugin 修正：子会话 `session.next.step.ended` / `session.idle` 不再当作父会话结束，
    改为 `subagent.stopped`。
  - **事件名已用二进制核实**：`strings ~/.opencode/bin/opencode` 只含
    `session.shell.started` / `session.shell.ended` / `session.step.ended`（**无** `.next.`
    前缀），SDK 生成类型（`@opencode-ai/sdk` v2）才写作 `session.next.shell.*`。plugin 两种
    拼写都订阅（`session.shell.*` 与 `session.next.shell.*`）。
  - **载荷形状已按 SDK 加固**：shell id 依次取 `properties.shell.id` → `properties.callID`
    → `properties.shellID`，`background` 取 `shell.metadata.background` 或扁平 `properties.background`。
  - `OpencodeChatInteraction.normalize`：`shell.started` / `subagent.started` →
    `backgroundTaskStarted`（id = shell_id / subagent_id）；`shell.ended` /
    `subagent.stopped` → `taskNotificationToolUseId`；全部 `attentionNeutral: true`。
  - 新增 `AgentStatusEvent.attentionNeutral`：`RuntimeEventProjection.attention` 直接跳过，
    只有租约投影消费。这样后台 shell / 子会话**不会**把 seat 卡在「运行中」，也不会污染
    `isReadyToChat`。
  - 复用租约的**增量** acquire/release（不引入 `parentCompletion`，不改注意力状态机；
    卡住的租约由 60 分钟 TTL 兜底）。
  - **待实测**：以上基于二进制/SDK 静态证据，尚未在真实 opencode 会话中跑通端到端
    （需要给工作区 agent 会话也装状态 plugin，见下方"非目标/待定"）。
- **阶段 3（claude/flashskyai `SubagentStart` 注册）：flashskyai 已完成，claude 明确不做**
  - **claude：不做**。`background_tasks` 已覆盖后台子 agent；注册 `SubagentStart` 反而会让
    「后台任务运行中」变回「运行中」（父 Stop 等到子结束才 done），与阶段 1 语义冲突，
    且丢失快照的对账自愈性（漏事件时靠快照复正，而不是靠计数）。
  - **flashskyai：已做**。实测确认它**有** `SubagentStart`（含 schema），但**没有**
    `background_tasks` → 它的后台子 agent 之前两条通道都无信号。改动：
    `hook_event.dart` 的 `HookEvent.subagentStart` 支持矩阵加入 flashskyai（并补
    `hook_event_name_mapper` 映射）——它本来就在 `managedRuntimeEventHookEntries` 的事件集里，
    只是被支持矩阵过滤掉了。效果：已注册的 `SubagentStop` 才真正生效，子 agent 计数能工作，
    父 Stop 在子未结束时保持「运行中」。
  - 语义注意：对 flashskyai 而言子 agent 归**「运行中」**（注意力轴），不是「后台任务」——
    这是刻意的选择（它没有快照，无法在回合外单独跟踪）。claude 则相反，归「后台任务」。
  - 备选（未采用）：把 `isBackgroundTaskStart` 从只认 `Bash` 放宽到
    `PreToolUse` + `tool_name ∈ {Agent, Task}` + `tool_input.run_in_background == true`，
    让后台子 agent 进**后台租约桶**。两条路线语义不同，本设计选了「注意力轴」。
- **阶段 4：待做。**

## 已知限制（ACP 会话）

工作区 agent 会话走 ACP（终端无关），**不装** `teampilot-agent-status.js` plugin
（`RuntimeEventHookContributionProvider` 只在有 agentStatus 的团队成员 seat 上写），
且 **ACP v1 没有任何后台工作信号**（`state_update` 是 v2 draft 的东西，尚未稳定、
零 agent 实现）。因此在 ACP 会话下：

- 只能看到**在途回合**的活动（thinking / generating / toolRunning，来自 ACP 的流式更新）；
- **看不到**后台工作（后台 shell / 子 agent）——这不是实现缺陷，是 ACP v1 的协议缺口。

要让 ACP 会话也有后台信号，只有三条路：等 ACP v2 落地并实现 `state_update`；或让 agent
把它自己的后台任务通过 ACP 扩展（`_meta` / 自定义 notification）上报；或改走 PTY + plugin。

- **阶段 4：待做。**

## 证据来源（本机）

- claude `2.1.211`：`~/.nvm/.../claude-code/bin/claude.exe`（hook 事件表、`Stop`/`SubagentStop` 输入 schema、`background_tasks`、`AgentInput.run_in_background` 默认 true）。
- flashskyai：`~/Downloads/DingDing/flashshkyai/dist/flashskyai`（`SubagentStart`×24 — **有**该 hook，含 `SubagentStartHookInputSchema`；`SubagentStop`×28；`run_in_background`×30；`background_tasks`×0）。
- codex：`~/.nvm/.../@openai/codex/.../vendor/x86_64-unknown-linux-musl/bin/codex`（`SubagentStart`×32、无后台字段）。
- cursor：`~/.local/share/cursor-agent/versions/2026.10.14-0f9edde/`（`subagentStart`、`beforeShellExecution`、`is_background`）。
- opencode `2.0.24`：`~/.opencode/bin/opencode`（`session.shell.started/ended` 带 `shell.metadata.background`；`session.created` 带 `info.parentID`）。
- gemini：`~/.nvm/.../@google/gemini-cli/bundle`（`BeforeTool` 等 hook 事件、`is_background`）。
