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
  (info/warning/error) }`；声明式、const、可独立测试。
- `TerminalIncident`（运行时事件）— `{ patternId, kind, cli, sessionId,
  memberId, matchedLine, timestamp, status: open/acknowledged }`。

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
4. 去重：同 `(memberId, patternId)` 在一个用户 turn 内只报一次，另有冷却窗口
   （默认 30s）防 CLI 反复重试刷屏。
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
- 操作：`acknowledge(incidentId)`（横幅消失，事件保留）；`clear()`。

聊天页顶部横幅（`pages/` 或 `widgets/` 下按 CODE_QUALITY 归层）：

- error 红 / warning 橙 / info 蓝色条。
- l10n 文案（"Claude Code 额度可能已用尽，需要你确认"等，按 kind 映射）+
  触发行原文（可折叠）。
- 操作按钮：「查看终端」切换到该成员终端 tab；「知道了」→ acknowledge。
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

- 模式表单元测试：每条内置正则对样例文案（含肯定/否定样例）。
- 引擎测试：跨 chunk 行拼装、ANSI 剥离、turn 内去重、冷却窗口、多模式命中。
- cubit 测试：事件推入、acknowledge、按 seat 分组。
- 横幅 widget 测试：severity 颜色、kind l10n 文案、操作回调。
- 全部走 `cd client && dart run tool/run_tests.dart`。

## Open Items（实现阶段处理）

- 各 CLI 内置正则清单需对照真实输出校准，并回填 `docs/cli-formats/`。
- "查看终端"跳转的具体路由（复用现有成员终端 tab 切换逻辑）。
