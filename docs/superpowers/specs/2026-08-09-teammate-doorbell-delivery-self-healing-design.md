# TeamBus 门铃投递自愈化 + 诚实工作状态

**日期:** 2026-08-09
**状态:** 已确认设计（待实现）

## 背景

mixed 团队会话中，lead 用 `send_message {"to":"*"}` 广播打招呼后，5 个成员里恰好 2 个（builder-0、reviewer）**永久显示"工作中"、门铃从不响、消息从不被消费**。实测数据（进程真实 spawn 时间 vs 邮箱投递时间）：

| 成员 | spawn | 门铃注入(MaterializeCompleted) | 距 spawn | 结果 |
|------|-------|-------------------------------|----------|------|
| architect | 55.194 | 55.346 | +151ms | 门铃成功，正常 park |
| builder-0 | 55.274 | 55.347 | +72ms | 门铃失败，卡死 active |
| builder-1 | 55.404 | 55.553 | +148ms | 门铃成功，正常 park |
| reviewer | 55.494 | 55.554 | +59ms | 门铃失败，卡死 active |

根因链条（代码已确认，非推断）：

1. **门铃投递绕过 boot 门控**：`MaterializeCompleted`（`presence_reducer.dart`）无条件置 `active` 并派发 `DoorbellEffect` → `wake` → `injectMemberStdin` → `deliverMemberStdin`。这条路径**不检查** `isBootFrameReady`/`isReadyForAutomationInput`——是唯一不等 boot 就注入的输入路径（对比 `ensureMemberInputReady` 明确等 boot frame）。注入时机靠广播交错运气：落在 spawn 后 ~150ms 的（TUI 已切 alternate screen/composer 可用）成功，落在 ~60ms 的（仍在启动屏）被清屏吞掉 → `pasteNotFound`。
2. **失败即终态，无恢复**：重试预算因 `MailDeliveryStarted`+`MailDeliveryFailed` 各计一次（`mailbox_delivery_reducer.dart`），实际约 3 轮就 `deliveryPhase=failed`。之后门铃被多处永久抑制：`_ringDoorbell`（`team_bus.dart:876`）短路、`pendingDoorbellNoticeFor`（`:140`）返回 null、看门狗 `reengageIdleWorkers`（`:1028`）只覆盖 `turnDoneReady`、`_onMail` 只响 atPrompt。成员卡在 `active`（乐观置位）+ unread=1，**没有任何代码路径能拉出来**。
3. 结果：bus 永远认为"in_turn" → UI"工作中"；邮箱永远未读 → "消息不被消费"；门铃被抑制 → "不响铃"。

## 目标

1. **诚实状态**：`MemberActivity.active` 只等于"真实回合进行中"，由 `TurnStarted` 置位（用户提交 / 门铃投递成功确认），不再由 `MaterializeCompleted` 乐观置位。成员门铃未落地时显示 idle + 未读徽标，而非假"工作中"。
2. **门铃 = 自愈投递义务**：义务条件 = `running && !parked && 邮箱有未读 && 投递未确认`。投递失败永不封死，由看门狗持续驱动重试，直到消费或 park。
3. **投递时机与 TUI 就绪解耦**：门铃注入等 boot frame ready 再粘，杜绝"盲粘进启动屏"。
4. 消灭"成员永久 stuck `active` + 未读 + 不响铃"这一整类状态。

## 非目标

- 不改动 `receiveWork`/`wait_for_message`/TeamBus 消息路由等消费侧逻辑。
- 不改动 task-queue 的认领与 `add_tasks` 流程（其门铃走同一投递管道，自然受益）。
- 不为门铃投递增加新的重试间隔参数（复用现有 `doorbellRetryMs`/`PtyAutomationRetryQueue`）。
- 不改 `ensureMemberInputReady`（正常首条输入路径，已等 boot）。

## 设计

### 1. Presence：诚实置位（`presence_reducer.dart`）

`MaterializeCompleted` 改为置 `turnDoneReady`：

```dart
case MaterializeCompleted():
  return PresenceTransition(
    s.copyWith(
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.turnDoneReady,   // 原: active
    ),
    [DoorbellEffect(ctx.memberId)],
  );
```

`active` 仅剩两个来源：
- `TurnStarted` 事件本身（`markTurnStarted`，用户在成员 prompt 直接提交）；
- `noteMailDeliverySubmitted`（`team_bus.dart:277`）里已有的 `TurnStarted`——门铃真正投递落地后才置 active。

由此派生：门铃投递失败 → 成员停在 `turnDoneReady`（atPrompt）+ unread → `_mixedAvailability`（`member_coordination.dart`）走 idle 分支 → UI 显示 idle + 未读徽标，不再假"工作中"。且 `turnDoneReady` 落入看门狗现有 atPrompt 覆盖范围，重试可及。

### 2. 投递：boot 门控注入（`tab_member_pty_delivery.dart`）

门铃投递（`deliverMemberStdin(…, latchUserTurn: false)`）在粘 paste 前检查 shell boot 就绪：

- 就绪检查用 `shell.activityTracker.isBootFrameReady`（门铃不需要 `directToPty`/forceWait 那部分语义）。
- 未就绪 → **推迟**：经现有 `_ptyInject`（`MemberPtyInjectService`）重试队列排入，`MailboxDeliveryPhase` 置 `pending`，不执行粘贴。重试命中（`tickRetries` → `retryAutomationTick`）时再检查，就绪后走正常 `deliverPasteAndSubmit`。
- 初始注入路径与重试路径都过此门（`_deliverFullScreen` 入口统一检查）。

实现要点：`MemberPtyInjectService` 暴露一个"推迟/未就绪"入口（如 `deferIfNotBootReady(sessionId, memberId, text)` → 内部 `_scheduleRetry`），避免首次盲粘产生的一次 `pasteNotFound` 及其双计开销。

### 3. 投递：失败非终态（`team_bus.dart` + `mailbox_delivery_reducer.dart`）

- **移除 `failed` 永久抑制**：`_ringDoorbell`（`team_bus.dart:876`）与 `pendingDoorbellNoticeFor`（`:140`）在义务仍成立（running + !parked + unread + 未确认）时照常返回门铃，不再因 `deliveryPhase == failed` 短路。
- **看门狗覆盖**：`reengageIdleWorkers`（`:1028`）条件从"仅 `turnDoneReady`"放宽为"`running && !parked && pendingDoorbellNoticeFor != null`"；重试时把 `failed` 重置为 `pending`（`noteMailDeliveryStarted` 语义），使投递义务可重入。
- **预算去双计**：`MailDeliveryFailed` 不再叠加 `Started` 的次数；`attempts` 只在 `Started` 时 +1，`failed` 判定 `attempts >= maxAttempts` 且最近一次失败。义务终止只取决于"成员消费（`MailConsumed`）或 park（`WaitEntered`）"。

### 状态流（修后）

```
send(materializeDeclared) → PTY up → MaterializeCompleted → turnDoneReady + DoorbellEffect
  → 门铃投递: 检查 boot ready
       ├─ 就绪 → 注入 → noteMailDeliverySubmitted → TurnStarted → active
       │         → CLI read_messages 消费 → TurnEnded → atPrompt → wait_for_message → parked
       └─ 未就绪/失败 → 推迟/重试（看门狗按 pendingDoorbellNoticeFor 持续驱动）→ 落地为止
```

任一环节失败都不再产生终态：成员要么消费后 park，要么保持 `turnDoneReady`+unread（idle 显示 + 未读徽标）且门铃持续可重试。

## 错误处理

- 投递失败（`pasteNotFound`/`crStuck`）：计入 attempts，未达上限则重试；达上限则 `failed`，但 `failed` 不再是终态——下次看门狗 tick 义务仍成立时重置重试。
- shell 中途断开（`aborted`）：`MailDeliveryAborted` 置 `pending`，等重连后看门狗重试。
- boot 长期未就绪：看门狗按 `doorbellRetryMs` 节流重试（5s），义务持续存在期间一直尝试；成员 TUI 正常启动时 ~2-3s 内就绪，重试即在窗口内落地。

## 测试

- **单测 `PresenceReducer`**：`MaterializeCompleted` → `running`/`turnDoneReady` + `DoorbellEffect`；`MailDeliverySubmitted` 后 `TurnStarted` → `active`；门铃失败后无 `TurnStarted`，成员保持 `turnDoneReady`。
- **单测 `MailboxDeliveryReducer`**：`failed` 可被后续 `MailDeliveryStarted` 重置为 `pending`；attempts 只随 `Started` 递增（去双计）。
- **单测看门狗**：`running + unread + deliveryPhase failed` 的成员被重新纳入重试（`pendingDoorbellNoticeFor != null`）。
- **单测投递**：`MemberPtyInjectService` 未就绪时排入推迟重试、不执行粘贴；就绪后落地。
- **集成测试**：复现"惰性连接 + lead 广播"，断言全部成员最终消费消息并进入 `wait_for_message`，无成员 stuck `active`；把门铃注入刻意压在 spawn 后 ~60ms，验证不再失败。

## 影响面

- 共享代码：`presence_reducer.dart`、`mailbox_delivery_reducer.dart`、`team_bus.dart`、`tab_member_pty_delivery.dart`、`member_pty_inject_service.dart`。
- 所有 mixed-bus CLI 统一受益；`active` 语义收紧为纯改进（消除假工作状态）。
- 不改消费侧（`receiveWork`/`wait_for_message`/路由）。
