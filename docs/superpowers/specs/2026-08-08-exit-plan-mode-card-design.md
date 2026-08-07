# ExitPlanMode 卡片优化 + Claude/flashskyai 聊天内批准 — 设计

日期：2026-08-08
状态：已评审（brainstorming 各节通过）

## 1. Context

Chat 卡片 `client/lib/pages/chat/exit_plan_mode_card.dart` 渲染 Claude `ExitPlanMode`：当前以**纯文本**展示 plan（220px 滚动盒），复用通用权限横幅文案，路径不可点击，唯一 CTA 是「打开终端」。用户需切到终端手动批准。

本文档覆盖两块（brainstorming 确认范围）：
1. **卡片全面优化** — Markdown 渲染、专属标题/图标、长 plan 展开/收起、复制按钮、可点击路径（内置 IDE）。
2. **Claude/flashskyai 聊天内批准/拒绝** — 挂起 `PreToolUse` HTTP hook，回复官方 `permissionDecision: allow/deny`（复用 AskUserQuestion 的成熟机制）。

**明确不在范围**（brainstorming 结论）：
- codex、opencode、cursor **不做聊天内批准**，保持现有「打开终端」回退。
- plan 文件从磁盘回退读取（用户未选）。
- cursor 的 plan 模式切换（`SwitchMode`）无法被 preToolUse hook 拦截（实测证据见 §5），故不实现 cursor 聊天内批准。

## 2. 行为变化（已确认）

一旦 Claude/flashskyai 启用聊天内批准，ExitPlanMode 的 `PreToolUse` hook 会被**挂起**直到用户在卡片上批准/拒绝（或 24h hook 超时，与 AskUserQuestion 现状一致）。挂起期间终端原生弹窗被抑制，「打开终端」降级为次要动作。这与现有 AskUserQuestion 流程一致。

## 3. 卡片优化

`exit_plan_mode_card.dart` 从 StatelessWidget 改为 StatefulWidget：

| 项 | 方案 | 复用 |
|----|------|------|
| Plan 正文 | `MarkdownView(document: compileMarkdown(planText), tokens: buildAppMarkdownTokens(theme, MarkdownProfile.compact, width), resolvers: const MarkdownResolvers())` | `tp_markdown`（`compileMarkdown` + `MarkdownView`）；`theme/app_markdown_style_sheet.dart:19` 的 `buildAppMarkdownTokens`（chat 同款，见 `session_chat_view.dart:1334`） |
| 标题/图标 | 专属 `l10n.exitPlanModeTitle` + `Icons.fact_check_rounded` | 新增 l10n |
| 长 plan | `_expanded` 状态；收起 = `maxHeight:160` 滚动盒 + 「展开」；展开 = 无上限 + 「收起」；plan 非空即显示开关 | — |
| 复制 | `TpIconButton(Icons.copy_rounded)` → `Clipboard.setData(ClipboardData(text: planText))` | chat 已有复制模式（`chat_workbench_context_menu.dart`） |
| 路径 | 可点击 → `WorkbenchEditorOpener.openFile(workspaceId, path, preview: true, fs: filesystemForComposeAtFileOpen(path))` | `session_chat_view.dart:1827` `onOpenAtFile` 同款 |
| 批准/拒绝 | 仅 `supportsInChatApproval` 时显示；否则保留主按钮「打开终端」 | §4 |

**取舍**：Markdown 渲染牺牲文本选中（原 `SelectableText`），用复制按钮补偿。`compileMarkdown` 已 LRU 缓存，无性能顾虑。

## 4. Claude/flashskyai 聊天内批准（hook-gate）

### 4.1 Capability

新文件 `client/lib/services/cli/registry/capabilities/exit_plan_mode_capability.dart`：
- `enum ExitPlanApprovalKind { hookReply, none }`
- `abstract interface class ExitPlanModeCapability implements CliCapability`：`supportsInChatApproval` + `approvalKind`
- `HookExitPlanModeCapability`（true/hookReply）、`NoExitPlanModeCapability`（false/none）

接线（仿各 tool 定义里 `askUserQuestion` 的写法）：
- `claude_cli_tool.dart`、`flashskyai_cli_tool.dart` → `HookExitPlanModeCapability`
- `codex_cli_tool.dart`、`opencode_cli_tool.dart`、`cursor_cli_tool.dart` → `NoExitPlanModeCapability`

### 4.2 Hook gate

新文件 `client/lib/services/agent_status/exit_plan_mode_hook_gate.dart`，平行于 `AskUserQuestionHookGate`（wait/complete/hasWaiter/clearSeat/clearSession + `session/member/toolUseId` 键）：
```dart
final class ExitPlanModeHookReply {
  const ExitPlanModeHookReply.allow();
  const ExitPlanModeHookReply.deny();
  final bool deny;
}
```

### 4.3 HTTP handler 挂起

`client/lib/services/agent_status/agent_status_http_handler.dart`：
- 新增参数 `ExitPlanModeHookGate? exitPlanModeHookGate` + `CliToolRegistry? registry`（默认 `CliToolRegistry.builtIn()`）。
- 新分支 `_maybeAnswerExitPlanModeHook(...)`：`hookEventName == 'PreToolUse' && isExitPlanModeTool(event.toolName)`、plan 载荷非空（`planText`/`planFilePath`）、**capability 支持**、gate 已配置 → `gate.wait(...)`：
  - allow → `{'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow'}}`
  - deny → `{'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'permissionDecisionReason': 'User rejected the plan'}}`
  - null（超时）→ 落回现有空 200（原生 TUI）
- **capability 门控**：未验证 CLI（codex）永不阻塞回合。

### 4.4 批准服务

新文件 `client/lib/services/terminal/exit_plan_mode_approval_service.dart`：
- `sealed class ExitPlanApprovalResult` + `ExitPlanApprovalOk` / `ExitPlanApprovalFailed(reason)`
- `approve({sessionId, memberId, toolUseId})`、`reject(...)` → 完成 gate；无 waiter / gate null → `Failed('no_pending_approval')`
- 构造注入 gate（测试用）

### 4.5 Cubit 接线

- `client/lib/cubits/agent_attention_cubit.dart`：新增 `dismissWaiting({sessionId, memberId})` — 置 attention 为 working 保留 lastEvent（批准/拒绝成功后的乐观隐藏，仿 `markAskAnswered`）。
- `client/lib/cubits/chat_cubit.dart`：新增 `ExitPlanModeApprovalService? exitPlanApprovalService` 构造参数 → `_exitPlanApproval`；`approveExitPlanMode({sessionId, memberId, toolUseId})` / `rejectExitPlanMode(...)`，成功后调 `_agentAttentionCubit?.dismissWaiting(...)`。
- `client/lib/app/app_shell.dart`（`askUserQuestionHookGate` 附近，~1127 行）：构造 `ExitPlanModeHookGate` + `ExitPlanModeApprovalService`，gate 注入 `AgentStatusHttpHandler(...)`、service 注入 `ChatCubit(...)`。

### 4.6 载荷关联修正

`client/lib/services/agent_status/exit_plan_mode.dart` 的 `preserveExitPlanModePayload` 额外保留 `toolUseId`（next 为空时取 previous；仿 `preserveAskUserQuestionPayload` 保留 `askRequestId`），使卡片能用 PreToolUse 的 `tool_use_id` 关联挂起的 hook。

### 4.7 Banner + 卡片接线

`client/lib/pages/chat/agent_permission_attention_banner.dart`：
- 用已解析的 `lockedCli` + registry 解析 `ExitPlanModeCapability`（仿 AskUserQuestion capability 查询）。
- 传 `session`、`seatId`、`toolUseId: lastEvent?.toolUseId`、`supportsInChatApproval` 给卡片。
- 新增 `onOpenPlanFile` → `WorkbenchEditorOpener.openFile(...)`。

## 5. 实验证据（cursor 排除依据）

2026-08-08 在隔离 HOME + 真实认证下用 cursor-agent v2026.08.04 headless 实测：

| 测试 | 结果 |
|------|------|
| preToolUse 触发 | ✅ Shell 等常规工具触发，payload 含 `tool_name`/`tool_use_id`/`generation_id`/`session_id` |
| `{"permission":"allow"}` | ✅ 放行 |
| `{"permission":"deny"}` | ✅ 拦截 |
| hook 挂起（sleep 30s） | ✅ cursor 等待 hook 决策，无短超时（总耗时 53s） |
| SwitchMode（plan 切换） | ❌ 不触发 preToolUse；仅 `afterAgentThought`（观察事件，无决策能力） |

结论：cursor 的 preToolUse 能门控常规工具，但**无法拦截 plan 模式切换**；故 cursor 的聊天内批准不可行，回退「打开终端」。此发现同时意味着 cursor 的 hook 脚本保持现状（fire-and-forget），不改动。

## 6. 错误处理

- 批准/拒绝失败（`no_pending_approval`、session/member 缺失）：卡片内联错误（l10n），按钮恢复可点。
- hook 超时（24h）：HTTP 落回空 200，Claude 走原生 TUI。
- `permissionDecision: deny` 后 agent 留在 plan mode；卡片被 `dismissWaiting` 隐藏。

## 7. 测试

- 单元：capability 每 CLI 值；`exit_plan_mode_hook_gate_test.dart`（wait/complete/clear，仿 `ask_user_question_hook_gate_test.dart`）；`agent_status_http_handler_exit_plan_test.dart`（PreToolUse 挂起 → allow/deny/无 gate，仿 `agent_status_http_handler_ask_user_test.dart`）；`exit_plan_mode_approval_service_test.dart`（approve/reject/no-waiter）；`chat_cubit_exit_plan_approval_test.dart`（成功 dismiss waiting，仿 `chat_cubit_ask_user_answer_test.dart`）。
- 单元：`preserveExitPlanModePayload` 保留 `toolUseId`。
- Widget：`exit_plan_mode_card_test.dart` 扩展 — Markdown 渲染、展开/收起、复制（Clipboard mock）、路径点击回调、`supportsInChatApproval` 时按钮显示/点击/错误态。
- 全量：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。

## 8. 验证

1. `flutter gen-l10n` 后 `flutter analyze` + 相关测试。
2. 手动（launch app，`verify` 技能）：启动 Claude/flashskyai 会话进入 plan 模式使模型调用 `ExitPlanMode`，确认卡片显示 Markdown plan + 批准/拒绝；批准 → 卡片清除、agent 继续；拒绝 → 留在 plan mode；复制按钮与路径点击打开编辑器正常；cursor/codex 会话仍回退「打开终端」。
