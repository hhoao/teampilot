# TeamBus 成员状态机

mixed 模式下，每个队友在 [TeamBus](../client/lib/services/team_bus/team_bus.dart) 里对应一个 [AgentNode](../client/lib/services/team_bus/agent_node.dart)，用两条正交轴描述：

| 轴 | 类型 | 含义 |
|----|------|------|
| **Lifecycle** | [MemberLifecycle](../client/lib/services/team_bus/member_state.dart) | PTY / 进程是否存在 |
| **Activity** | [MemberActivity](../client/lib/services/team_bus/member_state.dart) | CLI 是否在 turn、是否阻塞在 `wait_for_message` |

转移由 `TeamBus`、`ChatCubit` PTY 回调、MCP `wait_for_message` 驱动。源码枚举定义见 `client/lib/services/team_bus/member_state.dart`。

英文版：[TEAM_BUS_MEMBER_STATE.en.md](TEAM_BUS_MEMBER_STATE.en.md)

## 1. Lifecycle（PTY / roster）

```mermaid
stateDiagram-v2
  direction LR
  [*] --> declared: declareMember
  declared --> materializing: send(首信物化)
  materializing --> running: materialize 完成
  declared --> running: markMemberRunning\n(PTY 已 spawn)
  note right of declared
    mixed 惰性启动：尚无 PTY
  end note
  note right of running
    PTY 已连接；activity 见下图
  end note
```

## 2. Activity（`running` 时主循环）

```mermaid
stateDiagram-v2
  direction TB
  [*] --> turnDoneReady: markMemberRunning\n(PTY 刚起来)
  turnDoneReady --> active: 门铃 wake\n(send 到 turnDoneReady 等)
  turnDoneReady --> turnDoneBusWait: MCP wait_for_message\n(TeamBus.receive 入口)
  turnDoneBusWait --> active: waitBatch 返回\n(receive finally)
  active --> turnDoneBusWait: 再次 wait_for_message
  active --> turnDoneReady: onMemberIdle\n(Stop hook / 终端 idle)\n且不在 bus_wait
  turnDoneReady --> active: 信箱非空 +\n门铃(doorbellNotice)
  turnDoneReady --> turnDoneReady: onMemberIdle\n信箱为空（不门铃）
  active --> active: send / 投递\n(仅入队，不 writeln)
  turnDoneBusWait --> turnDoneBusWait: send / 投递\n(仅入队；wait 内唤醒)
  note right of turnDoneBusWait
    isBusWaitBlocked；
    UI 输入走 deliverUserCommand
  end note
  note right of turnDoneReady
    acceptsImmediateDoorbell；
    下一条 send 可立刻门铃
  end note
```

## 3. Activity（`declared`，尚无 PTY）

```mermaid
stateDiagram-v2
  direction LR
  [*] --> none: declareMember\n信箱空
  none --> mailQueued: 入站信\n_syncDeclaredInboxActivity
  mailQueued --> none: 信箱清空
  mailQueued --> active: send(首信)\n→ materialize → running
```

## 4. 门铃与 idle 边

```mermaid
flowchart TD
  A[onMemberIdle / POST /idle] --> B{lifecycle == running\n且非 turnDoneBusWait?}
  B -->|否| Z[无操作]
  B -->|是| C[activity := turnDoneReady]
  C --> D{inbox 非空?}
  D -->|否| Z
  D -->|是| E[activity := active\ninject doorbellNotice]
  F[send / _deliverToMember] --> G{shouldEnqueueMailOnly?}
  G -->|是 active 或 bus_wait| H[仅入队]
  G -->|是 turnDoneReady| E
  I[worker idle] --> J[leader 信箱\nIDLE NOTIFICATION]
```

**门铃策略（当前实现）**

- 仅当信箱**有未读**时才 `wake` 并注入 `doorbellNotice`。
- 信箱为空时 `onMemberIdle` 只落到 `turnDoneReady`，**不**往 PTY stdin 塞协调提示。
- Worker turn 结束会向 team-lead 投递 `IDLE NOTIFICATION`（与门铃独立）。

## 5. 组合速查（`list_teammates` → `busPhaseLabel`）

| lifecycle | activity | bus.phase |
|-----------|----------|-----------|
| running | active | in_turn |
| running | turnDoneReady | turn_done · ready |
| running | turnDoneBusWait | turn_done · bus_wait |
| declared | mailQueued | no_pty · mail_queued |
| declared | none | offline |

## 相关代码

| 模块 | 路径 |
|------|------|
| 枚举与 `busPhaseLabel` | `client/lib/services/team_bus/member_state.dart` |
| 状态转移 | `client/lib/services/team_bus/team_bus.dart` |
| `acceptsImmediateDoorbell` 等 | `client/lib/services/team_bus/agent_node.dart` |
| MCP 工具 | `client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart` |
| mixed 角色说明 | `client/lib/services/session/member_role_provision.dart` |
