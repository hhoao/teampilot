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
                                └─ awaitingAck: submitCr → 等 hook isAcked
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
      pasted     → _sendOnce()      # settle → (ESC @) → CR → 等 hook ack
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
                 hook ack (promptSubmitted)    │ submitCr
                                     ▼          ▼
                               ┌─────────────────────────────┐
                               │        awaitingAck          │
                               │  submitCr → 等 hook 确认     │
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
| `awaitingAck` | CR 已发，等待提交确认 | 只补 CR / 等待 | ① `isAcked`（hook）→ `done` ② CR 预算 + 超时耗尽 → `failed`(crStuck) ③ abort → `aborted` |
| `done` | 提交成功（hook 确认） | — | 终态 |
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

- **粘贴确认**靠「composer 前缀限定的网格 needle」：文本上屏且位于输入框附近即确认（见 §4）。
- **发送确认**靠 CLI 的提交 hook（`hookSubmitAck` 时**只信 hook**，网格不再参与提交判据）：
  - `promptSubmitted` 事件 = 权威"已提交"；coordinator 据此置 `confirmed`。
  - opencode = `userMessageSubmitted`；claude / codex / flashskyai = `UserPromptSubmit`；cursor = `beforeSubmitPrompt`。

状态机里 `isAcked` 一旦为真，任何在途重试立即停（防重复）；`awaitingAck` 超时且 hook 未到 → `crStuck`。

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

## 4. 粘贴检测机制（paste ACK）— 现状与边界

粘贴是否成功，靠「**网格里能否在输入框区域找到 needle 字符串**」来判定。这是"能粘上 vs 能发出去"中的第一环。

### 4.1 判定逻辑（光标输入区）

粘贴 ACK 与提交判定都以**终端光标行**（`TerminalScreenGrid.cursorRow`，由 alacritty 引擎透传）为锚——它是 TUI 自己宣告的输入位置，最可靠。

- **输入区窗口** `[top, cursor]`：从光标行**向上跨过连续非空行**到第一个空行为止（`_cursorZoneTop`）。光标行 + 上方整个输入框体（多行长粘贴 + 路径行都可能在这里）。
- **向下不扩**：光标下方的行（status/footer）不参与，避免单字符 needle（如 "1"）撞上状态行的 "17%"。
- 窗口内逐行匹配 needle（`_matchesNeedleAt`：跨行软换行拼接、CJK 宽字符、wrap 空格折叠）。
- 光标不可用时（`cursorRow < 0`）回退到"屏幕底部 scanRows 行"搜索。

`locateNeedleInCursorZone` 找粘贴文本；`needleStaysInCursorZone` 判"文本是否仍在输入区"（提交判定 / CR 重试守卫）。

### 4.2 关键特性与边界

- **光标锚定**：不用任何 per-CLI 前缀字符，也不依赖"输入框在屏幕底部"的假设。
- **避免下方干扰**：单字符 needle（"1"）只匹配光标输入区，不会命中下方 status 行的同字符。
- **多行粘贴 / 光标偏下**：光标可能停在输入框下方的空行（cursor-agent 把终端光标放在空 composer 行，paste 本体在其上方若干行）→ 窗口无上限地向**上**跨连续非空行，让 need 起点永远落在窗口内。
- **长文本软换行**：`_matchesNeedleAt` 的 wrap 拼接使其仍可命中；极长文本用 `pollTimeout` 放大（`_pastePollBudget`）。
- **非字母数字的全局容差**：needle 逐 cell 匹配，**精确匹配优先**；失配时若网格当前 cell 是**非字母/数字**（空格、TUI 行首框线 `│`、提示符 `❯ › >`、标点、padding），视为 painted chrome 跨过并重试同一字符——不限于行首、不需要 per-CLI 白名单。**字母/数字（含 CJK）失配即失败**，内容永远不被跳过。续行若**一个 needle 字符都没匹配**（纯 chrome/边框行）则直接失败，不会把两个分开的输入区拼接起来。提交正确性仍由 hook 兜底，"误 ACK"最坏只是多一次 CR 重试。

### 4.3 hook 提交兜底（为什么"粘贴误判"不会被当成成功）

提交是否成功**只信 CLI hook**（`hookSubmitAck`）。因此哪怕粘贴定位偶尔误判/漏判，最终结果也只有两种安全结局之一：

- hook 到了 → `submitted`（真实提交，绝不会假）；
- hook 不到 → `crStuck` / `unconfirmed`（可能多按了一次 CR，但不会被谎报成功）。

这就把「粘贴定位的误差」从"可能误报成功"降级为"浪费一次 CR 重试"。

### 4.4 粘贴前的清理

`_stagingOnce` 粘贴前先 `clearStagedInput`（清空输入框残留），使 resume/重试时输入框里的旧 staged 不会与本次粘贴混淆。粘贴后只需在光标输入区找到 needle 即锁定；**不再维护"基线行号"**——光标输入区本身已把状态行/历史 echo 排除在外。

## 5. 相关文件

- `services/terminal/fullscreen_pty_submission_machine.dart` — 投递状态机（纯逻辑、阶段、预算）
- `services/terminal/fullscreen_pty_automation.dart` — 状态机驱动（`deliverPasteAndSubmit` / `continueSubmission`）、grid 探针 + CR（I/O）
- `services/terminal/member_pty_inject_service.dart` — 门铃投递：per-seat `FullscreenPtySubmission`，`deliver`/`retry` 复用同一机器
- `services/terminal/fullscreen_input_screen_probe.dart` — 网格 needle / anchor 探测
- `services/terminal/pty_inject_ack_retry.dart` — 延迟/重试常量（`afterClear`/`afterPaste`/`crMaxAttempts` 等）
- `services/prompt_delivery/prompt_delivery_coordinator.dart` — 持久化投递状态机（`issueSubmit` / `isAcked`）
- `services/cli/{cli}/capabilities/terminal_behavior.dart` — 每个 CLI 的投递配置
  （`fullscreenCrAckStrategy` / `fullscreenComposerPrefix` / `inputReadiness` / `mentionAutocompletePopup`）