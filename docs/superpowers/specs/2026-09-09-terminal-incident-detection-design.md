# Terminal Incident Detection Design

Date: 2026-09-09
Status: Approved (brainstorming)

## Problem

AI CLI 工具在运行时会向终端打印"意外"信息——更新通知、额度用尽、请求失败/超时、
认证失效等。这些信息只存在于终端字节流中：聊天界面看起来像卡住了，用户不知道发生
了什么，也不知道需要去终端确认或处理。

`TerminalStartupFailureDetector` 只覆盖启动阶段（execvp、glibc 等），运行中的此类
输出完全没有检测。

## Goals

- 每个 CLI 声明自己的一组"意外事件"（incident）模式。
- 终端输出命中模式时：该成员 seat 置 `waiting`（复用 attention 通道）+ 进入独立
  事件流，UI 横幅提示用户，可跳转终端、可确认。
- 内置模式表（每 CLI）+ 用户自定义正则规则（设置页追加）。
- 本地 PTY 与 SSH 双端生效（走同一 observation bus 管线）。

## Non-Goals

- 不做意外事件的持久化存储（会话内存态即可）。
- 不做自动处理（不代替用户回应 CLI）。

## Decisions

- **通知形式**：双通道——置 `AgentSeatAttention.waiting`（sidebar/History banner
  已有消费方，保证可见）+ 独立 `TerminalIncidentCubit` 事件流（信息更丰富：
  kind、触发行原文、确认状态）。
- **扩展性**：内置声明式模式表 + 用户自定义规则合并。
- **架构**：共享检测引擎 + 每模式数据（方案 A）。不做每 CLI 各写一份扫描代码
  （方案 B），不借道 managed hook（方案 C，hook 是命令执行模型，不适合逐字节
  PTY 扫描且无法覆盖 SSH）。

## Architecture

### 数据模型

`client/lib/services/terminal/incident/terminal_incident.dart`:

- `enum TerminalIncidentKind` — `updateAvailable`, `creditExhausted`,
  `authRequired`, `rateLimited`, `requestFailed`, `timeout`, `networkError`,
  `other`.
- `TerminalIncidentPattern` — `{ id, kind, patterns: List<RegExp>, severity
  (info/warning/error), presentation (bannerOnly/actionCard),
  actions: List<TerminalIncidentAction>?, replyOptions:
  List<TerminalIncidentReplyOption>? }`；声明式、可独立测试。
  - `actions` / `replyOptions` 省略时回落到 kind 级默认动作集。
- `TerminalIncidentAction`（封闭集合，禁止开放式扩展）— `openTerminal` /
  `acknowledge` / `loginAgain`（跳现有 provider 凭证登录 UI）/
  `switchProvider`（打开模型/provider 选择） / `copyLine`（复制触发行）。
- `TerminalIncidentReplyOption` — `{ id, labelKey, inject: String }`：
  卡片渲染为按钮，点击后把 `inject` 文本注入该成员 PTY（走
  `MemberPtyInjectService` 的 paste+CR 管线，与 AskUserQuestion 聊天内回答
  同一机制），注入成功即 acknowledge + 清 waiting。注入的是发给 CLI 自身
  提示的按键数据而非 shell 命令；每个 pattern 声明的选项数 ≤ 4，只有
  显式声明 replyOptions 的 pattern 才出现注入按钮。
- `TerminalIncident`（运行时事件）— `{ patternId, identity, kind, severity,
  presentation, actions, replyOptions, cli, sessionId, memberId,
  matchedLine, timestamp }`。

### 锚定身份（去重的精确化）

pattern 的正则以**捕获组约定**表达"前后锚点 + 中间身份"：`RegExp` 的
第一个捕获组（若有）即事件身份；无捕获组则身份为 null（等同 pattern 级
折叠）。

- 匹配用 `firstMatch` + `group(1)`；
- 去重/折叠键 = `(patternId, identity)`；
- 锚点选法约定：**让"事件身份"落在捕获组里，把变化的噪音（重试计数、
  时间戳、attempt 序号）留在组外**。示例：`API Error: (\d+)` →
  identity="500"（稳定，跨冷却折叠）；`(rate limit reached)` → 固定身份
  （每次折叠）；`not logged in to (\S+)` → 账号名（可区分不同账号）。

两层去重：模块冷却挡瞬时刷屏（同键 30s 只报一次）；cubit 折叠挡长期
重复（见下）。

### 能力接口

`registry/capabilities/terminal_incident_capability.dart`:

```dart
abstract interface class TerminalIncidentCapability implements CliCapability {
  List<TerminalIncidentPattern> get terminalIncidentPatterns;
}
```

可选能力（同 `TerminalObservationContributor` 的 `is` 扫描方式接入）。每个 CLI 在
`{cli}/capabilities/terminal_incidents.dart` 提供内置表；claude 与 flashskyai 共享
同一份表（类似 `ClaudeFamilyAgentStatusNormalizer` 的共享模式，放 registry 共享
目录或 claude 目录下由 flashskyai 复用）。

内置模式示例（claude 家族）：

- `updateAvailable`: `Claude Code update available`
- `creditExhausted`: `credit balance too low`, `usage limit reached`
- `rateLimited`: `rate limit exceeded`, `API Error: 429`
- `requestFailed`: `API Error: 5xx`, `request failed`
- `timeout`: `timeout`/`timed out`（需按 CLI 实际文案校准）
- `authRequired`: `authentication`/`login required`/token 失效文案

具体正则在实现阶段对照各 CLI 真实输出校准（`docs/cli-formats/` 增补一页作为
事实来源）。

### 检测引擎

`terminal/observation/modules/incident_detection_module.dart` — 实现
`TerminalObservationContributor`，由 `TerminalSession._bindObservation` 作为
session module 绑定（与 `ActivityObservationModule`/`LaunchStartModule` 同级），
`isWorkspaceShell` 时不绑定（工作区 shell 不是 CLI 会话）。

引擎逻辑：

1. `bus.addOutputObserver`，phases = `{running}`（spawning/confirming 归
   `LaunchStartModule`，不重复检测）。
2. utf8 解码（`allowMalformed: true`）→ 剥离 ANSI 转义序列 → 跨 chunk 行拼装
   （保留未结尾的半行，与 `UserLineScanner` 同类做法）。
3. 逐行匹配合并后的模式表（内置在前、用户规则追加在后）。
4. 去重：同 `(memberId, patternId, identity)` 在冷却窗口（默认 30s）内只报
   一次，防止 CLI 反复重试刷屏。跨冷却的重复由 cubit 折叠兜底（见事件流）。
5. 命中时：
   - `seat.attention.applyEvent(... waiting)`（attention 为 null 时跳过此步，
     仅进事件流）；
   - 通过注入的回调把 `TerminalIncident` 推入 `TerminalIncidentCubit`。
6. 引擎内任何匹配/解码异常 catch 并记 `AppLogger`（`recordError: false`，与
   bus 现有观察器一致——单条坏正则不影响其他观察）。

本地 PTY 与 SSH 都经过 `TerminalObservationBus.dispatchOutput`，双端天然生效。

### 事件流与 UI

`client/lib/cubits/terminal_incident_cubit.dart` — session 级 cubit，seat key
与 attention 一致（`agentSeatKey(sessionId, memberId)`）：

- `Stream/状态`: 按 seat 分组的 `TerminalIncident` 列表（open + acknowledged）。
- **事件折叠**：新命中若同 `(sessionId, memberId, patternId, identity)` 已有
  open 事件 → **刷新**该事件（更新 timestamp 与 matchedLine），不追加。这层
  与模块冷却互补：冷却挡瞬时，折叠挡长期重复（CLI 每 40s 报一次、终端
  reclaim 重连后模式重放、全屏 TUI 重绘重发同文案）。重连重放场景折叠键
  不变，天然免疫。
- **有界性**：每 seat 的 open + acknowledged 事件总数封顶（默认 50），超出
  丢弃最旧。
- 操作：`acknowledge(incident)`（横幅消失，事件保留）；`clear()`；`reply`
  注入成功路径自动 acknowledge。

聊天页横幅（`widgets/chat/terminal_incident_banner.dart`）：

- error 红 / warning 橙 / info 蓝色条。
- `presentation: bannerOnly` → 只显示横幅（一行 kind 文案 + 触发行折叠）；
  `actionCard` → 显示操作卡片。
- 操作卡片按钮来自事件的 actions（kind 级默认、pattern 级可覆盖）：
  「查看终端」「知道了」为兜底；`loginAgain` 跳 provider 凭证登录 UI；
  `switchProvider` 打开模型/provider 选择；`copyLine` 复制触发行。
- **replyOptions 按键模拟**：pattern 声明的注入选项渲染为按钮，点击后
  经 `MemberPtyInjectService` 把 `inject` 文本注入该成员 PTY（paste+CR，
  与 AskUserQuestion 聊天内回答同一管线），成功后自动 acknowledge。
- l10n 文案（"Claude Code 额度可能已用尽，需要你确认"等，按 kind 映射）+
  触发行原文（可折叠；即使终端滚出 scrollback，卡片仍持有完整触发行）。
- sidebar 成员卡片叠加小角标显示该 seat 的未确认事件数。

### 用户自定义规则

设置页新增"CLI 意外检测"分区：

- 按 CLI 添加 `{ 正则, kind, severity }` 条目；存 AppStorage（json 文件，
  路径遵循 workspace-storage-layout）。
- bind 时合并：内置表在前、用户规则在后（用户规则可覆盖同类不同文案，不覆盖
  内置）。
- 正则保存时校验编译合法性，非法输入给 l10n 错误提示。

## Error Handling

- 模式编译失败（用户输入）：设置页即时校验，拒绝保存。
- 引擎运行期异常：catch + `AppLogger`，不影响终端输出渲染与其他观察器。
- attention 为 null（如无 cubit 的场景）：只进事件流不置 waiting。

## Testing

- 模式表单元测试：每条内置正则对样例文案（含肯定/否定样例）；锚定身份
  提取（捕获组 → identity、无组 → null）；actions/replyOptions 声明。
- 引擎测试：跨 chunk 行拼装、ANSI 剥离、`(patternId, identity)` 冷却去重、
  多模式命中、注入回调异常兜底。
- cubit 测试：事件推入、折叠刷新（同键不追加、timestamp 更新）、seat 封顶、
  acknowledge、按 seat 分组。
- 横幅 widget 测试：presentation 两态、severity 颜色、kind l10n 文案、
  动作按钮回调、replyOptions 注入（fake PTY port 断言注入文本 + 成功后
  acknowledge）。
- 全部走 `cd client && dart run tool/run_tests.dart`。

## Open Items（实现阶段处理）

- 各 CLI 内置正则清单需对照真实输出校准，并回填 `docs/cli-formats/`。
- "查看终端"跳转的具体路由（复用现有成员终端 tab 切换逻辑）。
