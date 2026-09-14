# PTY 全屏投递架构（Full-screen PTY Submission）

TeamPilot 通过 PTY 向全屏 TUI CLI（Claude Code、Cursor、Codex、OpenCode、FlashskyAI）投递用户消息。
本文档描述投递链路的架构：从 operator 输入到 PTY 写入的调用链、**投递状态机**（`FullscreenPtySubmission`）、
各阶段的时间预算、以及为什么"粘贴成功与否"是每次投递的确认基础。

## 1. 一次投递走完的链路

```
operator 输入
  └─ workspace_session_actions.submitWorkspaceLandingMessage
       └─ TabMemberPtyDelivery.deliverUserCommandToMember(directToPty: true)
            └─ PromptDeliveryCoordinator.issueSubmit
                 └─ TabPromptDeliveryCommands.submit            # operator / 会话首条消息
                      └─ FullscreenPtyAutomation.deliverPasteAndSubmit
                           └─ FullscreenPtySubmission            # 状态机（本文档）
                                ├─ staging   : clear → bracketed-paste → probe needle
                                ├─ pasted    : needle 已上屏（锁定）
                                └─ awaitingAck: submitCr → probe anchor 清除 / hook isAcked
TeamBus 信箱门铃（机器人消息）走同一底层：
  TeamBus.reengageIdleWorkers ─ retryDelivery
       └─ TabMemberPtyDelivery.retryMemberDelivery
            └─ MemberPtyInjectService.retry  # 持有 per-seat FullscreenPtySubmission
                 └─ FullscreenPtyAutomation.continueSubmission(machine, …)
```

两条入口（operator 直投 + 门铃）共用同一个「粘贴 → 确认 → 发送 → 确认」的底层语义，
区别只在上一层是否带重试/节流（门铃 5s 重敲；operator 由状态机内的 staging 预算兜底）。

**统一原则**：所有全屏投递都走 `FullscreenPtySubmission` 状态机，由
`FullscreenPtyAutomation` 驱动；不存在绕过状态机的旁路（旧的 `retry` /
`nudgeCrUntilClear` 入口已删除）。

- operator / 会话首条消息：`deliverPasteAndSubmit`（内部创建新机器并驱动）。
- 门铃首敲：`MemberPtyInjectService.deliver`（同一批 payload 创建机器）。
- 门铃重敲：`MemberPtyInjectService.retry` 复用 **per-seat** 机器，连续投递同一
  payload 时状态机跨次保留（`staging` 可续、`pasted` 锁住不重贴）；机器到终态后
  下一次重敲换新机器（等价重新投递）。

`FullscreenPtyAutomation` 暴露两个驱动入口：

```
deliverPasteAndSubmit(port, text, settle, {isAcked, dismissMentionPopup})
  = FullscreenPtySubmission()..begin()  +  continueSubmission(machine, …)

continueSubmission(machine, port, text, settle, {isAcked, dismissMentionPopup})
  → _driveToTerminal(machine)   # 按 phase 执行原语直到终态
      staging    → _stagingOnce()   # clear → paste → probe（预算内重贴）
      pasted     → _sendOnce()      # settle → (ESC @) → CR → anchor/hook ack
      awaitingAck→ _sendOnce()      # 只补 CR / 等 hook，绝不重贴
```

## 2. 投递状态机 `FullscreenPtySubmission`

代码：`client/lib/services/terminal/fullscreen_pty_submission_machine.dart`

```
                    begin()
      ┌────────┐  ──────────►  ┌─────────────────────────────┐
      │  idle  │               │          staging            │
      └────────┘               │  clear → paste → probe      │
                               └──────────────┬──────────────┘
                           pasteNotFound       │  needle 确认
                    （预算内回退自身 staging）  ▼
                               ┌─────────────────────────────┐
      ┌────────┐              │          pasted              │ ← 锁定，永不回退 staging
      │  done  │ ◄─────────   │  （本阶段只允许 submitCr）    │
      └────────┘              └──────────────┬──────────────┘
                     anchor 清除 / hook ack    │ submitCr
                                    ▼          ▼
                               ┌─────────────────────────────┐
                               │        awaitingAck          │
                               │  submitCr → 探测/anchor 清除 │
                               │  失败时只补 CR，绝不重贴      │
                               └──────────────┬──────────────┘
                                              │ crStuck / 超时
                                              ▼
                               ┌─────────────────────────────┐
                               │          failed             │  （pasteNotFound / crStuck）
                               └─────────────────────────────┘

abort（shell 断开 / fence 关闭）从任意非终态 → aborted
```

### 状态与转移

| 状态 | 语义 | 可执行动作 | 退出条件 |
|---|---|---|---|
| `idle` | 无投递进行中 | `begin()` | `begin` → `staging` |
| `staging` | 清理 + 粘贴 + 探针 needle | clear / paste / probe | ① needle 确认 → `pasted`（**锁定**）② 预算耗尽 → `failed`(pasteNotFound) ③ `isAcked` → `done` ④ abort → `aborted` |
| `pasted` | needle 已上屏，**锁定** | `submitCr` | `submitCr` → `awaitingAck` |
| `awaitingAck` | CR 已发，等待提交确认 | 只补 CR / 等待 | ① anchor 清除或 `isAcked` → `done` ② CR 预算 + 超时耗尽 → `failed`(crStuck) ③ abort → `aborted` |
| `done` | 提交成功（grid 或 hook 确认） | — | 终态 |
| `failed` | 预算耗尽未提交 | — | 终态（区别于 `done`） |
| `aborted` | shell 断开 / fence 关闭 | — | 终态 |

### 两条铁律（防重复发送）

1. **staging 可回退重试**：首贴可能被启动期 TUI 吃掉（MCP/插件连接重绘覆盖刚粘的文本）。
   只要 needle 未上屏，就留在 `staging` 按预算重贴——消息在这里"没粘上"不是失败，而是排除了
   "已粘上但网格没显示"的歧义。
2. **`pasted` 是单向锁**：一旦 needle 在网格确认，永不回到 `staging`。发送阶段的重试**只补 CR**
   （或等待），绝不重新粘贴——重贴一个已 staged 的消息正是历史上"一条消息变成多行 user row / 气泡"
   的根源。

### 与发送确认的关系

粘贴确认靠「网格 needle 是否可见」——这是**可靠**的（文本上屏即确认）。
发送确认靠两种信号，都是**间接**的：

- **grid anchor 清除**（`isFullscreenPromptSubmitted`）：CR 后 staged 文本从 composer 消失。
- **hook `promptSubmitted`**（`RuntimeEventEnvelope.promptSubmitted`，opencode 经
  `chat_interaction.dart` 上报）：权威的"消息已提交"信号；coordinator 据此置 `confirmed`。

状态机里 `isAcked` 一旦为真，任何在途重试立即停（防重复）；`awaitingAck` 超时且 hook 未到 → `failed`。

## 3. 时间预算（`PtyAutomationTiming.production()`）

| 参数 | 默认 | 说明 |
|---|---|---|
| `afterClear` | 350ms | 清理（Ctrl-U）后等待 TUI 消化 |
| `afterPaste` | 700ms | bracketed-paste 后等待渲染 |
| `pollTimeout` | 8s | **单次**探针 needle 的窗口；MCP/插件重绘时 3s 太短（历史上 3s 是 pasteNotFound 根因之一） |
| `pollInterval` | 100ms | 探针轮询间隔 |
| `stagingMaxAttempts` | 90 | 首贴 + 重贴次数；`90 × 2s ≈ 3 分钟` 内等待启动期 TUI 稳定 |
| `stagingRetryInterval` | 2s | 两次重贴之间的静默间隔（给 MCP/插件重绘完成的机会） |
| `crMaxAttempts` | 4 | CR 重试轮数 |
| `sendAckTimeout` | 12s | `awaitingAck` 阶段总确认上限（grid poll + hook） |
| `afterCr` | 800ms | CR 后等待重绘 |
| `afterDismissPopup` | 150ms | ESC 关 @ 弹窗后再发 CR，避免被合并为 Alt+Enter |
| `afterPasteAck` | 800ms | paste ACK 与 CR 之间的额外静默（部分 TUI 在 bracketed-paste 内绘制阶段文本） |

测试档 `PtyAutomationTiming.instant()` 将以上全部归零并把预算压到最小值，保证单测瞬时完成。

## 4. 为什么"能粘上 ≠ 能发出去"

- **粘贴**：`pasteText` 写 bracketed-paste 到 PTY → 网格探针确认文本是 live composer 的 body
  （`isNeedleStagedInComposer` 严格门禁）。可靠、可自证；resume 时 transcript 中的旧文本
  不会被误认为已 staged（否则发空 CR，session 显示 working 而 CLI 从未收到消息）。
- **发送**：`submitCr` 之后，提交确认**只信 hook 事件**（`UserPromptSubmit` /
  `beforeSubmitPrompt` / `userMessageSubmitted` → `promptSubmitted`），
  `hookSubmitAck` 时网格**不再作为提交判据**（网格对 resume transcript 回声会误报
  submitted）。hook 未到则补 CR / 等 hook，直到预算耗尽 (`crStuck`)。
  这也是为什么 `pasted` 之后绝不回退到 `staging`：粘贴一旦确认成功，再贴只会制造重复。

## 5. 相关文件

- `services/terminal/fullscreen_pty_submission_machine.dart` — 投递状态机（纯逻辑、阶段、预算）
- `services/terminal/fullscreen_pty_automation.dart` — 状态机驱动（`deliverPasteAndSubmit` / `continueSubmission`）、grid 探针 + CR（I/O）
- `services/terminal/member_pty_inject_service.dart` — 门铃投递：per-seat `FullscreenPtySubmission`，`deliver`/`retry` 复用同一机器
- `services/terminal/fullscreen_input_screen_probe.dart` — 网格 needle / anchor 探测
- `services/terminal/pty_inject_ack_retry.dart` — 延迟/重试常量（`afterClear`/`afterPaste`/`crMaxAttempts` 等）
- `services/prompt_delivery/prompt_delivery_coordinator.dart` — 持久化投递状态机（`issueSubmit` / `isAcked`）
- `services/cli/{cli}/capabilities/terminal_behavior.dart` — 每个 CLI 的投递配置
  （`fullscreenCrAckStrategy` / `fullscreenComposerPrefix` / `inputReadiness` / `mentionAutocompletePopup`）