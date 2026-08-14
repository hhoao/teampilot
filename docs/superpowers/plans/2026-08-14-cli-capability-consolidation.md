# CLI 能力接口合并实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `client/lib/services/cli/registry/capabilities/` 的 46 个能力接口按功能组收敛为 14 个(6 个 Hub 契约 + 8 个基础设施),解散 `ConfigProfileCapability`。

**Architecture:** 纯重构,零行为变更。能力接口 = 物化器契约(声明式);共享服务 = 注册器(收集虚拟实例 + 编排);启动时统一物化。每个合并任务:建新接口 → 合并每 CLI 实现(文件收敛)→ 更新工具定义注册 → 更新消费方 → analyze/测试兜底 → 提交。

**Tech Stack:** Dart / Flutter。类型系统(`capability<T>()` 泛型查找)是每个任务的主要回归工具。

**Spec:** `docs/superpowers/specs/2026-08-14-cli-capability-consolidation-design.md`

## Global Constraints

- **纯重构,零行为变更**:不引入新功能、不改输出文本、不改警告语义
- 每任务后必须:`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 零 error/零 warning
- 每任务后跑受影响的测试文件;任务 6/11/13/14 完成后跑 `flutter test --exclude-tags integration`(工作树基线:703 个 CLI 测试通过)
- 文件收敛用 `git mv` 保留历史;类重命名遵守各任务给出的新旧映射
- 每 CLI 实现文件按领域收敛:`cli/{cli}/capabilities/<domain>.dart`,不再每能力一个孤儿文件
- 不新增注释;现有注释随代码迁移
- 接口文件位置:`registry/capabilities/<name>.dart`;共享纯函数/枚举可与接口同文件
- 每个任务独立提交,一个任务一个 commit,消息前缀 `refactor(cli-capability):`

---

### Task 0: 基线验证

**Files:**
- 验证(无文件改动)

- [x] **Step 1: 验证 analyze 基线**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors, 0 warnings(仅存量 infos,~212 条)

- [x] **Step 2: 验证 CLI 测试基线**

Run: `cd client && flutter test test/services/cli/ 2>&1 | tail -3`
Expected: `All tests passed!`(703 tests)

- [x] **Step 3: 确认分支与工作树**

Run: `git branch --show-current`
Expected: `feat/cli-capability-consolidation`

---

### Task 1: TerminalBehaviorCapability(3→1)

**Files:**
- Modify: `lib/services/cli/registry/capabilities/terminal_behavior_capability.dart`(吸收 TurnInterrupt + TitleAttention)
- Delete: `lib/services/cli/registry/capabilities/turn_interrupt_capability.dart`, `lib/services/cli/registry/capabilities/title_attention_capability.dart`
- Modify: 每 CLI 的 `capabilities/terminal_behavior.dart`(5 个)吸收其 `turn_interrupt.dart`(有则)/`title_attention.dart` 的实现;删除被吸收文件
- Modify: 5 个 `cli/{cli}/{cli}_tool.dart` 注册表
- Modify: `lib/services/terminal/member_turn_interrupt_service.dart`, `lib/pages/chat/session_chat_compose_section.dart`, `lib/pages/chat/session_chat_view.dart`, `lib/services/launch/session_shell_connector.dart`, `lib/services/terminal/terminal_session.dart`, `lib/cubits/chat/tab_member_pty_delivery.dart`
- Modify: `test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart`(并入 terminal_behavior 测试)

**Interfaces:**
- Produces: `TerminalBehaviorCapability` = 原 TerminalBehaviorCapability 全部成员 + 以下新增:

```dart
// 来自 TurnInterruptCapability
bool get supportsTurnInterrupt;
TurnInterruptPlan get interruptPlan;

// 来自 TitleAttentionCapability
bool get bindTitleAttention;
```

- Produces: `TurnInterruptPlan` 类(`steps`, `gapBetweenSteps`)与默认实现 `CtrlCTurnInterrupt` 移入 `terminal_behavior_capability.dart`(保留类名)

- [x] **Step 1: 合并接口文件**

在 `terminal_behavior_capability.dart` 末尾追加 `TurnInterruptPlan`、`CtrlCTurnInterrupt`(原内容原样迁入),接口增加 `supportsTurnInterrupt` / `interruptPlan` / `bindTitleAttention` 三个成员。

- [x] **Step 2: 更新每 CLI 实现**

对每个 CLI(claude/codex/cursor/flashskyai/opencode):
- 把 `capabilities/turn_interrupt.dart` 的 `CtrlCTurnInterrupt`(已注册的实例)、`capabilities/title_attention.dart` 的实现类内容合并进 `capabilities/terminal_behavior.dart` 的对应类;类保留原名(如 `CodexTerminalBehavior`)
- `git rm` 被吸收的两个文件

- [x] **Step 3: 更新工具定义**

5 个 `{cli}_tool.dart`:删 `turnInterrupt = const CtrlCTurnInterrupt()`、`titleAttention = const XxxTitleAttention()` 字段与注册;确保 `terminalBehavior` 字段类型仍为 `TerminalBehaviorCapability` 且实例现在包含三个新成员的值。

- [x] **Step 4: 更新消费方**

- `member_turn_interrupt_service.dart`: `capability<TurnInterruptCapability>(cli)` → `capability<TerminalBehaviorCapability>(cli)`,取 `supportsTurnInterrupt` / `interruptPlan`
- `session_chat_compose_section.dart` / `session_chat_view.dart`: 同上取 `supportsTurnInterrupt`
- `session_shell_connector.dart`: `capability<TitleAttentionCapability>(cli)?.bindTitleAttention` → `capability<TerminalBehaviorCapability>(cli)?.bindTitleAttention ?? false`
- `terminal_session.dart` / `tab_member_pty_delivery.dart`: 已是 `capability<TerminalBehaviorCapability>`,无需改

- [x] **Step 5: 更新测试**

`test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart` 的测试对象改为 `TerminalBehaviorCapability`(经注册表取 cursor 或 codex),断言 `interruptPlan.steps == ['\x03']`。

- [x] **Step 6: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 errors 0 warnings
Run: `flutter test test/services/cli/registry/capabilities/opencode_terminal_behavior_test.dart test/services/cli/registry/capabilities/turn_interrupt_capability_test.dart test/services/cli/cli_tool_registry_test.dart`
Expected: 全部通过

- [x] **Step 7: 提交**

```bash
git add -A client/lib/services/cli client/lib/pages/chat client/lib/services/terminal client/lib/services/launch client/lib/cubits/chat test/services/cli
git commit -m "refactor(cli-capability): merge TurnInterrupt+TitleAttention into TerminalBehaviorCapability"
```

---

### Task 2: TeamBehaviorCapability(6→1)

**Files:**
- Create: `lib/services/cli/registry/capabilities/team_behavior_capability.dart`
- Delete: `native_team_capability.dart`, `bus_transport_capability.dart`, `turn_completion_capability.dart`, `wait_before_stop_capability.dart`, `presence_capability.dart`, `member_agent_preset_capability.dart`
- Modify: `lib/services/cli/registry/cli_tool_registry.dart`, `lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: 每 CLI 新建/合并 `capabilities/team_behavior.dart`(从 `presence.dart`/`wait_before_stop.dart`/`marketplace_consumer.dart` 等合并),5 个工具定义
- Modify: `lib/services/launch/member_bus_mcp_transport_resolver.dart`, `lib/services/team_bus/remote/remote_bus_binding_resolver.dart`, `lib/cubits/chat/tab_team_bus_coordinator.dart`, `lib/services/team/member_coordination.dart`, `lib/services/team/member_presence_service.dart`, `lib/cubits/chat_cubit.dart`, `lib/widgets/cli/member_agent_preset_field.dart`, `lib/models/team_config.dart`
- Modify: `test/integration/support/cli_test_profile.dart`, `test/services/team_bus/relay_provisioner_test.dart`, `test/services/cli/cli_tool_registry_test.dart`, `test/services/cli/registry/capabilities/turn_completion_capability_test.dart`

**Interfaces:**
- Produces: `TeamBehaviorCapability`(新接口,包含全部吸收成员的声明):

```dart
/// 团队协作:原生团队、Bus 传输、turn 结束语义、wait-before-stop、presence、成员 agent 预设。
abstract interface class TeamBehaviorCapability implements CliCapability {
  // 来自 NativeTeamCapability(标记 → 布尔)
  bool get supportsNativeTeam;

  // 来自 BusTransportCapability
  bool get longBlockingWaitForMessage;
  bool get supportsLocalStdioBridge;

  // 来自 TurnCompletionCapability
  Set<String> get doneEventNames;
  bool get requiresPtyFallback;
  bool get usesDoorbellPush;

  // 来自 WaitBeforeStopCapability
  bool get defaultForceWaitBeforeStop;

  // 来自 PresenceCapability
  bool get usesClaudeRoster;
  bool get usesShellActivity;

  // 来自 MemberAgentPresetCapability(未支持 agent 预设的 CLI 返回 null)
  MemberAgentPresetStyle? get agentPresetStyle;
}
```

- Consumes: `MemberAgentPresetStyle` 枚举(原 `member_agent_preset_capability.dart`,移到 `team_behavior_capability.dart` 保留原名)

- [x] **Step 1: 创建接口文件**

按上面接口创建 `team_behavior_capability.dart`,把 `MemberAgentPresetStyle` 枚举原样迁入;删 6 个旧接口文件。

- [x] **Step 2: 更新每 CLI 实现**

每个 CLI 建 `capabilities/team_behavior.dart`,类实现全部 11 个成员,值来自被吸收的旧实现:
- claude/flashskyai:`supportsNativeTeam=true`(曾注册 `NativeTeamSupport`);codex/cursor/opencode:`false`
- claude/flashskyai/codex/opencode:`longBlockingWaitForMessage=true`;cursor:`false`
- `agentPresetStyle`:claude→`MemberAgentPresetStyle.claudeAgentType`,flashskyai→`MemberAgentPresetStyle.flashskyaiCatalog`,其余 `null`
- 其余成员按各 CLI 旧值迁移(见 `wait_before_stop.dart`/`presence.dart`/`turn_completion.dart` 旧实现)
- `git rm` 各 CLI 被吸收的实现文件(`presence.dart`、`wait_before_stop.dart` 等;注意 marketplace_consumer 属于 Task 8,不要动)

- [x] **Step 3: 更新注册表辅助方法**

`cli_tool_registry.dart`:
- `nativeTeamLaunchable` / `supportsNativeTeam`: `capability<NativeTeamCapability>` → `capability<TeamBehaviorCapability>(id)?.supportsNativeTeam == true`
- `memberAgentPresetStyle` / `supportsMemberAgentPreset`: 取 `agentPresetStyle`
- 删除 `NativeTeamCapability` / `MemberAgentPresetCapability` import

`built_in_cli_tools.dart`:
- `withCapability<MemberAgentPresetCapability>`(131 行附近)→ `registry.all.where((d) => registry.memberAgentPresetStyle(d.id) != null)`,错误消息同旧文本
- `withCapability<NativeTeamCapability>`(如存在)→ `supportsNativeTeam`

- [x] **Step 4: 更新消费方**

- `member_bus_mcp_transport_resolver.dart` / `remote_bus_binding_resolver.dart`: `capability<BusTransportCapability>` → `capability<TeamBehaviorCapability>`,取 `longBlockingWaitForMessage` / `supportsLocalStdioBridge`
- `tab_team_bus_coordinator.dart` / `member_coordination.dart` / `member_presence_service.dart`: 取 `defaultForceWaitBeforeStop` / `usesClaudeRoster` / `usesShellActivity`
- `chat_cubit.dart`: 取 `doneEventNames` / `requiresPtyFallback` / `usesDoorbellPush`
- `member_agent_preset_field.dart`: `registry.capability<MemberAgentPresetCapability>` → 用 `registry.memberAgentPresetStyle(cli)`(已存在辅助方法,改调用)
- `team_config.dart`(`team_config.dart` 中如引用 `supportsNativeTeam` 等帮助函数):核对更新

- [x] **Step 5: 更新测试**

- `turn_completion_capability_test.dart`: 改从注册表取 `TeamBehaviorCapability` 断言
- `cli_test_profile.dart` / `relay_provisioner_test.dart`: `BusTransportCapability` 引用改为 `TeamBehaviorCapability`

- [x] **Step 6: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/cli_tool_registry_test.dart test/services/cli/registry/capabilities/turn_completion_capability_test.dart test/services/team_bus/relay_provisioner_test.dart test/cubits/chat_cubit_ask_user_answer_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 7: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge 6 team capabilities into TeamBehaviorCapability"
```

---

### Task 3: ChatInteractionCapability(3→1)

**Files:**
- Create: `lib/services/cli/registry/capabilities/chat_interaction_capability.dart`
- Delete: `ask_user_question_capability.dart`, `agent_status_normalizer_capability.dart`, `exit_plan_mode_capability.dart`, `pty_ask_user_question_capability.dart`
- Modify: `lib/services/agent_status/agent_status_normalizer.dart`, `lib/services/agent_status/ask_user_question_policy.dart`, `lib/services/terminal/ask_user_question_answer_service.dart`, `lib/pages/chat/agent_permission_attention_banner.dart`, `lib/services/agent_status/agent_status_http_handler.dart`
- Modify: 每 CLI 建 `capabilities/chat_interaction.dart`(cursor/opencode 已有 `agent_status_normalizer.dart` + `ask_user_question.dart`;claude/codex/flashskyai 组合共享 `ClaudeFamilyAgentStatusNormalizer` + `PtyAskUserQuestionCapability` + Hook/No 审批),5 个工具定义
- Modify: 测试 `test/services/agent_status/ask_user_question_policy_test.dart`, `test/services/cli/ask_user_question_capability_test.dart`, `test/services/terminal/ask_user_question_answer_service_test.dart`, `test/cubits/chat_cubit_ask_user_answer_test.dart`, `test/services/cli/registry/exit_plan_mode_capability_test.dart`

**Interfaces:**
- Produces: `ChatInteractionCapability`:

```dart
/// 聊天交互:向聊天上报 seat 状态、向用户提问、收 ExitPlanMode 审批。
abstract interface class ChatInteractionCapability implements CliCapability {
  // 来自 AgentStatusNormalizerCapability
  AgentStatusEvent? normalize(Map<String, Object?> body);

  // 来自 AskUserQuestionCapability
  bool get supportsStructuredAsk;
  bool get supportsInChatAnswer;
  bool get supportsMultiSelectInChat;
  bool get supportsMultiQuestionInChat;
  bool get supportsInChatPermissionReply;
  AskUserAnswerKind get answerKind;

  // 来自 ExitPlanModeCapability
  bool get supportsInChatApproval;
  ExitPlanApprovalKind get approvalKind;
}
```

- Produces(同文件,原样迁入):`AskUserAnswerKind` 枚举、`ExitPlanApprovalKind` 枚举
- Consumes: `ClaudeFamilyAgentStatusNormalizer`(保留为共享实现,`registry/capabilities/claude_family_agent_status_normalizer.dart` 不动)

- [x] **Step 1: 创建接口文件**

按上面接口创建;枚举原样迁入;删 4 个旧接口文件。

- [x] **Step 2: 更新每 CLI 实现**

每个 CLI 建 `capabilities/chat_interaction.dart`,类实现 9 个成员:
- claude/codex/flashskyai:`normalize` 委托 `const ClaudeFamilyAgentStatusNormalizer()`,`supportsStructuredAsk/InChatAnswer/MultiSelect/MultiQuestion=true`、`supportsInChatPermissionReply=false`、`answerKind=AskUserAnswerKind.ptyPicker`(即旧 `PtyAskUserQuestionCapability` 值);`supportsInChatApproval/approvalKind`:claude/flashskyai=`true`+`hookReply`,codex=`false`+`none`
- cursor/opencode:迁移各自旧的 `agent_status_normalizer.dart` + `ask_user_question.dart` 实现值(`OpencodeAskUserQuestionCapability` 等),`supportsInChatApproval=false`+`none`
- `git rm` 每 CLI 被吸收文件(`cursor/capabilities/agent_status_normalizer.dart` 等)

- [x] **Step 3: 更新消费方**

- `agent_status_normalizer.dart`: `capability<AgentStatusNormalizerCapability>` → `capability<ChatInteractionCapability>`,调 `normalize`
- `ask_user_question_policy.dart` / `ask_user_question_answer_service.dart` / `agent_permission_attention_banner.dart`: `AskUserQuestionCapability` → `ChatInteractionCapability`
- `agent_status_http_handler.dart`: `ExitPlanModeCapability` → `ChatInteractionCapability`,取 `supportsInChatApproval` / `approvalKind`

- [x] **Step 4: 更新测试**

`ask_user_question_capability_test.dart` / `exit_plan_mode_capability_test.dart`: 改经注册表取 `ChatInteractionCapability` 断言各成员;其余引用改类型名。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/agent_status/ask_user_question_policy_test.dart test/services/cli/ask_user_question_capability_test.dart test/services/terminal/ask_user_question_answer_service_test.dart test/cubits/chat_cubit_ask_user_answer_test.dart test/services/cli/registry/exit_plan_mode_capability_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge chat-status/question/approval into ChatInteractionCapability"
```

---

### Task 4: HeadlessCapability(2→1)

**Files:**
- Create: `lib/services/cli/registry/capabilities/headless_capability.dart`
- Delete: `headless_provision_capability.dart`, `headless_run_capability.dart`
- Modify: `lib/services/ai/headless_ai_service.dart`, `lib/services/cli/registry/headless/headless_provision_support.dart`
- Modify: 每 CLI 合并 `capabilities/headless_run.dart` + `headless_provision.dart` → `capabilities/headless.dart`,5 个工具定义
- Modify: 测试 `test/services/ai/headless_ai_service_test.dart`, `test/services/cli/registry/headless/claude_headless_run_capability_test.dart`, `test/services/cli/registry/headless/other_headless_run_capabilities_test.dart`, `test/services/cli/registry/headless_provision_registration_test.dart`, `test/services/cli/registry/headless_registration_test.dart`

**Interfaces:**
- Produces: `HeadlessCapability` = HeadlessRunCapability 全部成员 + `provision`:

```dart
Future<HeadlessProvisionResult> provision(HeadlessProvisionContext ctx);
```

- Produces(同文件):`HeadlessRunContext`, `HeadlessConfigFile`, `HeadlessInvocation`, `HeadlessProvisionResult`, `HeadlessProvisionContext`(原样迁入)
- Consumes: 每 CLI 现有实现类(`ClaudeHeadlessRunCapability` / `ClaudeHeadlessProvisionCapability` 等)合并为单个类(如 `ClaudeHeadlessCapability`)

- [x] **Step 1: 创建接口文件**

按上面定义;上下文类原样迁入;删两个旧文件。

- [x] **Step 2: 合并每 CLI 实现**

每 CLI 把 `headless_run.dart` + `headless_provision.dart` 合并为 `headless.dart` 单个类(保留所有方法体),如 claude:`ClaudeHeadlessCapability implements HeadlessCapability`。删被吸收文件。

- [x] **Step 3: 更新消费方与测试**

`headless_ai_service.dart` / `headless_provision_support.dart`: `capability<HeadlessRunCapability>` / `HeadlessProvisionCapability` → `capability<HeadlessCapability>`。测试文件同步改类型引用。

- [x] **Step 4: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/ai/headless_ai_service_test.dart test/services/cli/registry/headless/ test/services/cli/registry/headless_registration_test.dart test/services/cli/registry/headless_provision_registration_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 5: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge HeadlessProvision+HeadlessRun into HeadlessCapability"
```

---

### Task 5: CliExecutableCapability(5→1)

**Files:**
- Create: `lib/services/cli/registry/capabilities/cli_executable_capability.dart`
- Delete: `display_capability.dart`, `executable_resolver_capability.dart`, `remote_cli_locator_capability.dart`, `installer_capability.dart`, `cli_config_ui_capability.dart`
- Modify: `lib/services/cli/registry/cli_display_name.dart`, `lib/services/cli/cli_executable_discovery.dart`, `lib/services/cli/remote_cli_locator.dart`, `lib/services/cli/cli_installer_service.dart`, `lib/services/remote/remote_cli_readiness.dart`, `lib/cubits/session_preferences_cubit.dart`, `lib/pages/config/cli_config_section.dart`, `lib/pages/onboarding/steps/cli_step.dart`, `lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`, `lib/pages/llm_config/llm_config_workspace.dart`, `lib/pages/llm_config/llm_providers_tab_content.dart`, `lib/pages/team_config/team_config_info_section.dart`, `lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart`, `lib/widgets/plugins/plugin_cli_support_disclosure.dart`
- Modify: 每 CLI 合并 `display.dart` + `executable_resolver.dart` + `installer.dart` + `config_ui.dart` → `capabilities/executable.dart`(cursor 另含 `remote_cli_locator` 如独立文件),5 个工具定义
- Modify: 测试 `test/pages/onboarding/cli_step_test.dart`, `test/services/cli/cli_tool_registry_test.dart`, `test/services/cli/unix_node_bootstrap_strategy_test.dart`

**Interfaces:**
- Produces: `CliExecutableCapability`:

```dart
/// 身份与二进制:显示名、可执行文件、远程定位、安装、设置页路径行。
abstract interface class CliExecutableCapability implements CliCapability {
  // 来自 DisplayCapability
  String label(AppLocalizations l10n);

  // 来自 ExecutableResolverCapability
  String get defaultExecutableName;
  String get preferencesPathKey;

  // 来自 RemoteCliLocatorCapability
  Future<String?> locateRemote(SshCommandRunner run);

  // 来自 InstallerCapability
  bool get supportsInstaller;
  Future<CliInstallResult> install(CliInstallContext context);

  // 来自 CliConfigUiCapability
  CliExecutablePathRowSpec get executablePathRowSpec;
}
```

- Produces(同文件):`CliExecutablePathRowSpec`(原样迁入), `SshCommandResult`, `SshCommandRunner` typedef
- Consumes: `DefaultRemoteCliLocator` 保留为共享帮助类(`remote_cli_locator.dart` 里),每 CLI 实现 `locateRemote(run) => const DefaultRemoteCliLocator(defaultExecutableName).locate(run)`;`UnsupportedInstallerCapability` 删除,flashskyai 的 executable 实现返回 `supportsInstaller=false` + `install` 返回原错误结果;`NpmInstallerCapability`(registry/installer/)保留为基类供实现继承

- [x] **Step 1: 创建接口文件**

按上面定义;`CliExecutablePathRowSpec`/`SshCommandResult`/`SshCommandRunner` 原样迁入;删 5 个旧接口文件。

- [x] **Step 2: 合并每 CLI 实现**

每 CLI 建 `capabilities/executable.dart`,类实现 7 个成员(值迁移自旧 5 个实现类):
- `label`: 原 `display.dart` 实现
- `defaultExecutableName` / `preferencesPathKey`: 原 `executable_resolver.dart`
- `locateRemote`: 委托 `DefaultRemoteCliLocator`
- `supportsInstaller` / `install`: 原 installer(flashskyai 用 `UnsupportedInstallerCapability` 的值:false + `CliInstallResult(success: false, message: 'In-app installation is not supported for this CLI.')`)
- `executablePathRowSpec`: 原 `config_ui.dart`

- [x] **Step 3: 更新消费方**

- `cli_display_name.dart`: `capability<DisplayCapability>` → `capability<CliExecutableCapability>`,调 `label`
- `cli_executable_discovery.dart`: `ExecutableResolverCapability` + `RemoteCliLocatorCapability` → `CliExecutableCapability`
- `remote_cli_locator.dart`: `capability<RemoteCliLocatorCapability>` → `CliExecutableCapability`
- `cli_installer_service.dart` / `remote_cli_readiness.dart`: `InstallerCapability` → `CliExecutableCapability`,`supportsInstaller` 判空逻辑保持
- `session_preferences_cubit.dart`: `ExecutableResolverCapability` → `CliExecutableCapability`
- `cli_config_section.dart`: `CliConfigUiCapability` → `CliExecutableCapability`
- 其余 UI 文件(DisplayCapability 消费方): `capability<DisplayCapability>` → `capability<CliExecutableCapability>`

- [x] **Step 4: 更新测试**

`cli_step_test.dart` / `unix_node_bootstrap_strategy_test.dart` / `cli_tool_registry_test.dart`: 引用改 `CliExecutableCapability`(installer 相关断言取 `supportsInstaller`)。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/pages/onboarding/cli_step_test.dart test/services/cli/cli_tool_registry_test.dart test/services/cli/unix_node_bootstrap_strategy_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge executable/install/display/ui into CliExecutableCapability"
```

---

### Task 6: AiHistoryCapability(5→1)

**Files:**
- Modify: `lib/services/cli/registry/capabilities/ai_history_capability.dart`(吸收 AiTranscriptIncremental + HistoryContextEnv + SessionResume + ToolCallResolvers)
- Delete: `history_context_env_capability.dart`, `session_resume_capability.dart`, `tool_call_resolver_capability.dart`
- Modify: `lib/services/cli/registry/cli_tool_registry.dart`, `lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`, `lib/services/cli/opencode/capabilities/tool_call_resolvers.dart`, `lib/services/cli/cursor/capabilities/tool_call_resolvers.dart`(如有)
- Modify: 每 CLI 的 `capabilities/history/ai_history_capability.dart` + `capabilities/history_context_env.dart` + `capabilities/resume_strategy.dart` 合并,5 个工具定义
- Modify: `lib/services/session/ai_history_loader.dart`, `lib/services/session/session_history_context_builder.dart`, `lib/services/session/session_lifecycle_service.dart`, `lib/services/session/ai_history_locator.dart`, `lib/services/session/subagent_attachment_inflater.dart`, `lib/services/session/workspace_session_content_index.dart`, `lib/pages/chat/session_chat_message_area.dart`, `lib/pages/chat/session_chat_view.dart`
- Modify: `test/support/fake_ai_history_registry.dart` 及 `test/services/session/ai_history_loader_test.dart` 等历史测试

**Interfaces:**
- Produces: `AiHistoryCapability` 新增成员(原有成员全部保留):

```dart
// 来自 AiTranscriptIncrementalCapability(接口加默认实现,非 SQLite CLI 不必覆盖)
AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

// 来自 HistoryContextEnvCapability
Map<String, String> sessionEnv({String? toolRoot});

// 来自 SessionResumeCapability
ResumeBinding get binding;
Future<String?> detectNativeId(ResumeContext ctx);

// 来自 ToolCallResolversCapability
AiEditToolTargetResolver get editResolver;
AiToolFileTargetResolver get fileResolver;
AiShellToolTargetResolver get shellResolver;
AiToolCallCategoryResolver get categoryResolver;
```

- Produces(同文件,原样迁入):`AiTranscriptIncrementalRefresher`, `AiTranscriptIncrementalState`, `AiTranscriptIncrementalResult`, `ResumeBinding`, `ResumeContext`
- Consumes: `SharedToolCallResolvers` 保留为共享实现(`shared_tool_call_resolvers.dart` 改 implements `AiHistoryCapability` 或作为每 CLI history 实现的组合成员——推荐后者:每 CLI history 实现持 `const SharedToolCallResolvers()` 并在 4 个 getter 委托)

- [x] **Step 1: 合并接口文件**

`ai_history_capability.dart` 增加上面 8 个新成员;迁入 3 个被吸收文件的类型(`AiTranscriptIncrementalRefresher` 等);删 3 个旧文件。`tool_call_resolvers.dart` 的内容并入后删除。

- [x] **Step 2: 合并每 CLI 实现**

每 CLI 的 `history/ai_history_capability.dart` 实现类新增:4 个 resolver getter(委托 `const SharedToolCallResolvers()`,cursor/opencode 若曾有自定义 resolver 则保留其覆盖)、`sessionEnv`(自旧 `history_context_env.dart`)、`binding`/`detectNativeId`(自旧 `resume_strategy.dart`)、`incrementalRefresher`(仅 opencode 覆盖,其余不写)。删各 CLI 被吸收文件。

- [x] **Step 3: 更新注册表与消费方**

- `cli_tool_registry.dart`: `toolCallResolvers(cli)` → `capability<AiHistoryCapability>(cli)` 上取 4 个 resolver(或直接删该帮助方法,消费方改 `capability<AiHistoryCapability>(cli)`)
- `ai_history_loader.dart`: `AiTranscriptIncrementalCapability` 查找 → `capability<AiHistoryCapability>(cli)?.incrementalRefresher`
- `session_history_context_builder.dart`: `HistoryContextEnvCapability` → `capability<AiHistoryCapability>(cli)?.sessionEnv(toolRoot: …)`
- `session_lifecycle_service.dart`: `SessionResumeCapability` → `capability<AiHistoryCapability>(cli)` 取 `binding`/`detectNativeId`
- 其余消费方已用 `AiHistoryCapability`,无改动

- [x] **Step 4: 更新测试**

`fake_ai_history_registry.dart`: 假实现类补上 8 个新成员的桩。`session_history_registration_test.dart` / `ai_history_capability_wiring_test.dart` 引用改新成员。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/session/ai_history_loader_test.dart test/services/session/subagent_attachment_inflater_test.dart test/services/cli/registry/ai_history_capability_wiring_test.dart test/services/cli/registry/session_history_registration_test.dart test/services/cli/registry/capabilities/tool_call_resolvers_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): absorb incremental/env/resume/resolvers into AiHistoryCapability"
```

---

### Task 7: SkillCapability(ResourceCapability skill 部分 + SkillInvocationSyntax)

**Files:**
- Create: `lib/services/cli/registry/capabilities/skill_capability.dart`
- Delete: `skill_invocation_syntax_capability.dart`;`resource_capability.dart` 中 skill 部分移除(plugin 部分留给 Task 8)
- Modify: `lib/services/cli/registry/resources/default_resource_capability.dart`(拆为 DefaultSkillCapability + 保留 plugin 位)
- Modify: `lib/services/resource/resource_provisioning_service.dart`(skill 分支用 SkillCapability)
- Modify: `lib/services/cli/registry/capabilities/member_config_inspection_capability.dart`(skill 读回改 SkillCapability)
- Modify: 每 CLI 建/改 `capabilities/skill.dart`(opencode/cursor 已有 `resource.dart`;codex 有 `skill_invocation_syntax.dart`),5 个工具定义
- Modify: 消费方 `lib/services/compose/compose_slash_catalog.dart`, `lib/widgets/compose/compose_trigger_field.dart`, `lib/widgets/compose/workspace_compose_card.dart`, `lib/pages/chat/session_chat_compose_section.dart`, `lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: 测试 `test/services/cli/registry/resource_capability_test.dart`, `test/services/cli/registry/skill_invocation_syntax_capability_test.dart`, `test/services/compose/compose_slash_catalog_test.dart`

**Interfaces:**
- Produces: `SkillCapability`:

```dart
/// SkillHub 契约:skill 如何进 CONFIG_DIR + prompt 里如何调用。
abstract interface class SkillCapability implements CliCapability {
  // 来自 ResourceCapability(skill 部分)
  String get skillsSubdir;                          // 旧 subdirFor(ResourceKind.skill)
  ResourceRepresentation get skillsRepresentation;  // 旧 representationFor(skill)

  // 来自 SkillInvocationSyntaxCapability
  String get skillInvocationPrefix;
  String skillInvocationText(String skillName, {String? namespace});
}
```

- Produces(同文件):`ResourceRepresentation` 枚举迁入;`DefaultSkillInvocationSyntaxCapability` 保留为共享帮助类(每 CLI skill 实现可组合)
- Consumes: `ResourceKind` 枚举(`lib/services/resource/resource_kind.dart`)保持不动;`DefaultResourceCapability` 拆分

- [x] **Step 1: 创建接口文件**

按上面定义;迁入 `ResourceRepresentation` 与 `DefaultSkillInvocationSyntaxCapability`;删 `skill_invocation_syntax_capability.dart`;`resource_capability.dart` 删 skill 部分(成员与方法),仅留 plugin 相关声明(Task 8 再删除整文件)。

- [x] **Step 2: 更新每 CLI 实现**

每 CLI 建/改 `capabilities/skill.dart`:
- 值来自旧 `resource.dart`(skill 部分:`skillsSubdir='skills'` 等)+ 旧 `skill_invocation_syntax.dart`(codex:`skillInvocationPrefix='\$'`;其余 `/`;opencode 用 `DefaultSkillInvocationSyntaxCapability(leadingSeparator: ' ')` 值)
- claude/cursor/flashskyai 未注册过 ResourceCapability 的:用共享默认值注册(见旧 `DefaultResourceCapability`)
- 删被吸收实现文件(`opencode/capabilities/resource.dart` 等,仅删 skill 相关类)

- [x] **Step 3: 更新消费方**

- `resource_provisioning_service.dart`: skill 分支 `capability<ResourceCapability>(cli)?.subdirFor(ResourceKind.skill)` → `capability<SkillCapability>(cli)?.skillsSubdir`;plugin 分支保留(Task 8)
- `member_config_inspection_capability.dart`: `_readSkills` 改 `capability<SkillCapability>(cli)`
- compose 相关 5 个文件: `capability<SkillInvocationSyntaxCapability>` → `capability<SkillCapability>` 取 prefix/text

- [x] **Step 4: 更新测试**

`resource_capability_test.dart`(skill 断言迁移)、`skill_invocation_syntax_capability_test.dart`、`compose_slash_catalog_test.dart`: 改经 `SkillCapability`。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/registry/resource_capability_test.dart test/services/cli/registry/skill_invocation_syntax_capability_test.dart test/services/compose/compose_slash_catalog_test.dart test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): introduce SkillCapability for skill provisioning + syntax"
```

---

### Task 8: PluginCapability(3→1 + plugin 位)

**Files:**
- Create: `lib/services/cli/registry/capabilities/plugin_capability.dart`
- Delete: `plugin_provisioner_capability.dart`, `marketplace_consumer_capability.dart`, `remote_app_data_capability.dart`, `resource_capability.dart`(Task 7 残留的 plugin 声明)
- Modify: 每 CLI 合并 `capabilities/plugin_provisioner.dart` + `marketplace_consumer.dart` + `remote_app_data.dart` → `capabilities/plugin.dart`,5 个工具定义
- Modify: `lib/services/provider/config_profile_service.dart`(pluginProvisionerForTool 调用), `lib/services/plugin/marketplace_shared_store.dart`, `lib/services/remote/remote_app_data_materializer.dart`, `lib/services/cli/registry/capabilities/member_config_inspection_capability.dart`(plugins 读回)
- Modify: 测试(plugin 相关注册测试)

**Interfaces:**
- Produces: `PluginCapability`:

```dart
/// PluginHub 契约:插件物化 + marketplace + 远程共享依赖播种。
abstract interface class PluginCapability implements CliCapability {
  // 来自 PluginProvisionerCapability
  PluginManifestPaths? get manifestPaths;
  List<String> get memberPluginsSubpath;
  Set<PluginComponentKind> get supported;
  Future<void> provision(PluginProvisionContext ctx);

  // 来自 MarketplaceConsumerCapability
  bool get consumesMarketplaces;

  // 来自 RemoteAppDataCapability
  bool get needsSharedPluginDepsBeforeReconcile;
  Future<void> seedSharedPluginDeps({required Filesystem homeFs, required String homeRoot});

  // 来自 ResourceCapability(plugin 部分)
  String get pluginsSubdir;                          // 旧 subdirFor(ResourceKind.plugin),默认 'plugins'
  ResourceRepresentation get pluginsRepresentation;
}
```

- Produces(同文件):`PluginComponentKind` 枚举, `PluginProvisionContext`(原样迁入), `neutralPluginManifestPaths` / `codexPluginManifestPaths` / `cursorPluginManifestPaths` 常量, `pluginManifestPathsForTool` / `pluginProvisionerForTool` 帮助函数改名 `pluginCapabilityForTool`
- Consumes: `PluginManifestPaths`(plugin_manifest_paths.dart 保持)

- [x] **Step 1: 创建接口文件**

按上面定义;迁入枚举/上下文/常量;删 3 个旧接口文件 + `resource_capability.dart`。

- [x] **Step 2: 合并每 CLI 实现**

每 CLI 建 `capabilities/plugin.dart` 单个类,值迁移自 `plugin_provisioner.dart` + `marketplace_consumer.dart` + `remote_app_data.dart`;`pluginsSubdir='plugins'`(cursor 用其 `memberPluginsSubpath` 对应值)。删被吸收文件。

- [x] **Step 3: 更新消费方**

- `config_profile_service.dart`: `pluginProvisionerForTool(tool)` / `pluginManifestPathsForTool(tool)` → `pluginCapabilityForTool(tool)`(改名后的帮助函数,行为不变)
- `marketplace_shared_store.dart`: `MarketplaceConsumerCapability` → `PluginCapability` 取 `consumesMarketplaces`
- `remote_app_data_materializer.dart`: `RemoteAppDataCapability` → `PluginCapability`
- `member_config_inspection_capability.dart`: plugins 分支用 `PluginCapability.memberPluginsSubpath`
- `resource_provisioning_service.dart`: plugin 分支用 `PluginCapability.pluginsSubdir`

- [x] **Step 4: 更新测试**

各 CLI plugin 测试与 `resource_capability_test.dart`(plugin 断言): 改 `PluginCapability`。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/registry/resource_capability_test.dart test/services/cli/config_profile/ 2>&1 | tail -3`(及 plugin 相关注册测试)
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge plugin provisioning into PluginCapability"
```

---

### Task 9: McpCapability(重命名)

**Files:**
- Modify: `lib/services/cli/registry/capabilities/mcp_config_writer_capability.dart` → `git mv` 为 `mcp_capability.dart`,接口改名 `McpCapability`
- Modify: 4 个 CLI 实现(`mcp_config_writer.dart` → `mcp.dart`,类名 `XxxMcpCapability`),工具定义
- Modify: `lib/services/mcp/mcp_registry_service.dart`, `lib/services/cli/registry/config_profile/claude_family_hook_writer.dart`(如引用)
- Modify: 测试

**Interfaces:**
- Produces: `McpCapability`(成员不变):

```dart
abstract interface class McpCapability implements CliCapability {
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  });
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {}
}
```

- [x] **Step 1: 重命名接口**

`git mv mcp_config_writer_capability.dart mcp_capability.dart`,接口改名 `McpCapability`。

- [x] **Step 2: 更新实现与消费方**

每 CLI `git mv` 实现文件为 `capabilities/mcp.dart`、类改名 `XxxMcpCapability`;`mcp_registry_service.dart` 等消费方改 `capability<McpCapability>`。

- [x] **Step 3: 验证 + 提交**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/mcp/mcp_registry_service_test.dart test/services/cli/registry/mcp_writers/ 2>&1 | tail -3`
```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): rename McpConfigWriterCapability to McpCapability"
```

---

### Task 10: HookCapability(重命名)

**Files:**
- Modify: `hook_writer_capability.dart` → `git mv` 为 `hook_capability.dart`,接口改名 `HookCapability`
- Modify: 5 个 CLI 实现(`codex_hook_writer.dart`/`cursor_hook_writer.dart`/`opencode_hook_writer.dart`/claude 与 flashskyai 的共享 `claude_family_hook_writer.dart`),工具定义
- Modify: 测试 `test/services/cli/registry/capabilities/hook_writer_test.dart`

**Interfaces:**
- Produces: `HookCapability`(成员不变:`nativeEvent`, `supportsMatcher`, `supportsHttp`, `supportsPolicy`, `supportsEvent`, `render`)

- [x] **Step 1: 重命名接口**

`git mv hook_writer_capability.dart hook_capability.dart`,接口改名 `HookCapability`。

- [x] **Step 2: 更新实现与消费方**

实现类改名(`CodexHookWriter` → `CodexHookCapability` 或保留原类名仅改 implements——保留原类名以减小 diff,仅改接口引用)。`claude_family_hook_writer.dart` 的 `ClaudeFamilyHookWriter` 保留为共享实现。

- [x] **Step 3: 验证 + 提交**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/registry/capabilities/hook_writer_test.dart 2>&1 | tail -3`
```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): rename HookWriterCapability to HookCapability"
```

---

### Task 11: PromptCapability(PromptProvision 升级 + 虚拟实例)

**Files:**
- Modify: `lib/services/cli/registry/capabilities/prompt_provision_capability.dart` → `git mv` 为 `prompt_capability.dart`;接口升级为 `PromptCapability`(virtualize + materialize),新增 `PromptSpec` / `PromptScope` / `PromptMergeRole`
- Create: `lib/services/cli/registry/prompt/prompt_hub_service.dart`(共享收集编排)
- Modify: 5 个 CLI 实现(`prompt_provision.dart` → `prompt.dart`),工具定义
- Modify: 5 个 `config_profile.dart`(prompt 步骤改为调 PromptHubService——注意这是 Task 14 的一部分,本任务只做接口升级 + 每 CLI 实现改造 + 直接消费方更新,config_profile 的调用点 Task 14 再改;若 analyze 要求,最小改动为把调用点换成新方法名)
- Modify: 测试 `test/services/cli/config_profile/*_prompt_provision_test.dart`, `test/services/cli/registry/all_cli_prompt_provision_capability_test.dart`

**Interfaces:**
- Produces: `PromptCapability`:

```dart
enum PromptScope { cli, member, team, expert, workspace, global }
enum PromptMergeRole { replace, append, section }

class PromptSpec {
  const PromptSpec({
    required this.id,
    required this.title,
    required this.content,
    this.scope = PromptScope.cli,
    this.mergeRole = PromptMergeRole.replace,
  });
  final String id;
  final String title;
  final String content;
  final PromptScope scope;
  final PromptMergeRole mergeRole;
}

abstract interface class PromptCapability implements CliCapability {
  /// 源契约:声明我提供的 prompt 虚拟实例(纯函数,无 IO)。
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx);

  /// 物化器契约:把收集合并后的 PromptSpec 列表写入 CLI 原生位置。
  Future<PromptMaterializeResult> materialize(PromptMaterializeContext ctx);
}
```

- Produces(同文件):`PromptVirtualizeContext`(可空字段:`paths`, `scope`, `member`, `memberHome`), `PromptMaterializeContext`(字段 = 旧 `PromptProvisionContext` 全部字段), `PromptMaterializeResult`(字段 = 旧 `PromptProvisionContribution`:`environment` + `written`)
- Consumes: 每 CLI 现有实现:`virtualize` 返回与当前 `provision` 等价内容的一个 `PromptSpec`(claude/flashskyai: role.md 内容;codex/opencode: AGENTS.md 内容;cursor: role.mdc 内容);`materialize` 复用旧 `provision` 的全部逻辑(改签名)
- Consumes: `PromptHubService`(本任务创建):

```dart
class PromptHubService {
  Future<PromptMaterializeResult> provisionForCli({
    required CliTool cli,
    required PromptMaterializeContext ctx,
  });
}
```

实现:收集各作用域源(本任务先 CLI 级:该 CLI 自身的 PromptCapability.virtualize)→ 合并(scope 优先级,本任务单一源直接透传)→ 调 `materialize`。

- [x] **Step 1: 升级接口文件**

`git mv prompt_provision_capability.dart prompt_capability.dart`;保留旧上下文类(改名 `PromptMaterializeContext` / `PromptMaterializeResult`,字段不变);新增 `PromptSpec` / `PromptScope` / `PromptMergeRole` / `PromptVirtualizeContext` / `PromptCapability` 接口。

- [x] **Step 2: 升级每 CLI 实现**

每 CLI `git mv prompt_provision.dart prompt.dart`,类改名 `XxxPromptCapability implements PromptCapability`:
- `virtualize`: 返回 `[PromptSpec(id: '<cli>-member-role', title: 'Member role', content: <与旧 provision 相同的组合内容>)](scope: member)`
- `materialize`: 把旧 `provision(ctx)` 方法体原样迁入(参数类型改名),返回 `PromptMaterializeResult`
- 旧 `PromptProvisionCapability` 类型引用全部改新类型

- [x] **Step 3: 创建 PromptHubService**

`registry/prompt/prompt_hub_service.dart` 按上面接口实现:先只调该 CLI 的 `capability<PromptCapability>(cli)` 的 virtualize + materialize(与旧行为等价,后续任务 14 接收集编排)。

- [x] **Step 4: 更新直接消费方**

`config_profile.dart`(5 个)里 `promptProvision.provision(...)` 调用改 `PromptHubService().provisionForCli(...)`(若旧代码是 `promptProvision` 字段注入,改为注入/静态调用 `PromptHubService`)。`cursor_home_provisioner.dart` 同改。

- [x] **Step 5: 更新测试**

`all_cli_prompt_provision_capability_test.dart` 及 5 个 per-CLI prompt 测试: 断言 `materialize` 结果与旧 `provision` 一致(env/written),新增 `virtualize` 返回非空 `PromptSpec` 断言。

- [x] **Step 6: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/config_profile/ test/services/cli/registry/all_cli_prompt_provision_capability_test.dart 2>&1 | tail -3`
Expected: 全部通过(行为回归)

- [x] **Step 7: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): upgrade PromptProvision to PromptCapability with virtual instances"
```

---

### Task 12: ProviderCapability(8→1)

> 注:本任务拆为 12a / 12b 两个可编译步骤(原始单步 dispatch 两次被中止)。
> 12a 中每 CLI 合并类 `implements ProviderCapability` **并同时 implements 8 个旧接口**(成员相同,旧 `capability<T>` 查找仍命中),旧接口文件保留 → 全仓仍编译;12b 删除旧接口文件并切换全部消费方。

**12a: 新接口 + 每 CLI 合并类 + 工具定义注册**

**Files:**
- Create: `lib/services/cli/registry/capabilities/provider_capability.dart`(接口 + 全部上下文类型/枚举/帮助函数原样迁入)
- Create: 每 CLI `capabilities/provider.dart`(单个合并类,如 `ClaudeProviderCapability implements ProviderCapability, ProviderCatalogCapability, ProviderDisplayCapability, ProviderFormCapability, ProviderModelCapability, ProviderCredentialCapability, CredentialBindingCapability, CredentialExportCapability, CliEffortCapability`)
- Modify: 5 个工具定义(`provider` 字段替换 8 个旧字段,仅注册合并类)
- Delete: 每 CLI 被吸收的 provider 相关实现文件(credential_binding/credential_export/provider_catalog/provider_display 在 capabilities/,credential/effort/model/form/catalog 在 provider/)
- 验证:analyze 0 errors 无新 warnings;`flutter test test/services/cli/ test/services/provider/` 通过(旧接口查找仍命中合并类)
- 提交:`refactor(cli-capability): merge 8 provider-family capabilities into ProviderCapability`

**12b: 删除旧接口 + 消费方切换**

**Files:**
- Delete: 8 个旧接口文件;合并类降级为仅 `implements ProviderCapability`
- Modify: `passthrough_provider_form_capability.dart`(改实现 ProviderCapability + 默认成员)
- Modify: 全部消费方(见下方原列表)+ `cli_tool_registry.dart` + `built_in_cli_tools.dart` `_verifyRequired`
- Modify: 测试(原列表)
- 验证:analyze + provider 相关测试
- 提交:`refactor(cli-capability): switch provider consumers to ProviderCapability`

**Interfaces(12a/12b 共用):**
- Produces: `ProviderCapability`(成员 = 8 个旧接口成员并集,方法签名原样):

```dart
abstract interface class ProviderCapability implements CliCapability {
  // ---- ProviderCatalogCapability ----
  CliTool get catalogCli;
  String? get defaultOfficialProviderId;
  Future<ProviderCatalogSnapshot> loadFromLiveSources(ProviderCatalogLoadContext context);

  // ---- ProviderDisplayCapability ----
  bool get hasModelPanel;
  bool get showModelCount;
  bool get supportsDelegate;
  bool get supportsOAuthCredentials;
  bool get usesLlmConfigJsonPreview;

  // ---- ProviderFormCapability ----
  List<AppProviderPreset> get presets;
  Map<String, Object?> defaultConfig();
  String defaultApiKeyField();
  String normalizeApiKeyField(String? raw);
  Map<String, Object?> configForCliSwitch();
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing);
  Map<String, Object?> extraFromPreset(AppProviderPreset preset);
  Map<String, Object?> buildConfig(ProviderFormInput input);
  Widget buildExtraSection(BuildContext context, ProviderFormSectionProps props);

  // ---- ProviderModelCapability(+Refreshable) ----
  ProviderModelPickerMode pickerMode(AppProviderConfig provider);
  List<String> modelCandidates({required AppProviderConfig? provider, required String providerId, required String currentModel});
  String defaultModel({required AppProviderConfig? provider, required String providerId});
  bool get supportsModelTiers;
  Listenable get catalogUpdates;                        // 非异步刷新的 CLI 返回 no-op
  Future<void> refreshModelCatalog({required String providerId, String? executable, bool forceRefresh = false});

  // ---- ProviderCredentialCapability ----
  bool appliesTo(AppProviderConfig provider);
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider);
  Future<CredentialProbe> probe(AppProviderConfig provider);
  Future<CredentialActionResult> execute({required String providerId, required ProviderCredentialActionKind kind, ProviderCredentialActionInput input = const ProviderCredentialActionInput()});
  bool hidesApiKeyFields(AppProviderConfig provider);

  // ---- CredentialBindingCapability ----
  CredentialBindingKind defaultBinding(AppProviderConfig provider);
  Map<String, Object?> withBinding(Map<String, Object?> config, CredentialBindingKind binding);

  // ---- CredentialExportCapability ----
  Future<CredentialFile?> exportCredential({required Filesystem fs, required String basePath, required String home, required AppProviderConfig provider});

  // ---- CliEffortCapability ----
  EffortPickerPlacement teamPickerPlacement();
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider});
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider);
  bool isApplicable({required String model});
  List<String> effortCandidates({required String model, AppProviderConfig? provider});
  String defaultEffort({required String model, AppProviderConfig? provider});
}
```

注意:`appliesTo(provider)`(CredentialBinding 与 ProviderCredential 各有)合并为一个实现(语义相同:该 CLI 是否支持该 provider 的凭证概念),消费方判断不变。

- Produces(同文件,原样迁入):`ProviderCatalogSnapshot`, `ProviderCatalogLoadContext`, `ProviderCredentialActionKind/Spec/Input`, `ProviderFormInput`, `ProviderFormSectionProps`, `ProviderModelPickerMode`, `ProviderModelTier`(+`backgroundModelFromProvider`), `CatalogModelCapability` 基类, `ModelCatalogSource`, `ProviderRecordModelCapability`, `EffortPickerPlacement`, `EffortResolveContext`, `resolveLaunchEffort`, `resolveContextModel`, `mergeProviderModelCandidates`, `modelsDeclaredOnProvider`, `providerModelCount`, `resolveDefaultProviderModel`, `CredentialBindingKind`(从 `services/provider/credential_binding.dart` 复核)
- Consumes: `PassthroughProviderFormCapability` 改 implements `ProviderCapability`(其余成员用默认实现:display 全 false、catalog 空、model 用 `ProviderRecordModelCapability` 组合、effort hidden、credential 不适用、binding 直通、export null)

- [x] **Step 1: 创建接口文件**

按上面定义创建(上下文类原样迁入);删 8 个旧接口文件;`cli_effort_capability.dart` 的顶层帮助函数(`resolveLaunchEffort` 等)迁入新文件。

- [x] **Step 2: 合并每 CLI 实现**

每 CLI 把 provider 相关实现(`provider_catalog.dart`/`provider_display.dart`/`credential_binding.dart`/`credential_export.dart`/`provider/` 下 effort/model/form/credential 文件)合并为 `capabilities/provider.dart` 单个类(如 `ClaudeProviderCapability implements ProviderCapability`),方法体原样迁移。flashskyai 无 credential 概念:对应方法返回空/不适用值(与旧 `ProviderCredentialCapability` 未注册时的消费方默认一致——复核旧消费方默认分支,保持行为)。

- [x] **Step 3: 更新消费方**

批量替换(逐文件核对 import + `capability<T>` 参数):
- `capability<ProviderModelCapability>` → `capability<ProviderCapability>`:`ai_features_config_section.dart`, `workspace_cli_config_helpers.dart`, `ai_feature_setting_resolver.dart`, `app_provider_form_sheet.dart`, `provider_model_picker_field.dart`, `provider_models_editor.dart`, `provider_form_sheet` 等
- `capability<ProviderDisplayCapability>` → 同:`app_provider_detail_panel.dart`, `app_provider_list_panel.dart`, `plugin_cli_support_disclosure.dart`, `provider_models_editor.dart` 等
- `capability<ProviderCatalogCapability>` → 同:`home_workspace_new_team_dialog.dart`, `workspace_cli_config_helpers.dart`, `team_config_helpers.dart`, `ai_feature_setting_resolver.dart`, `provider_import_service.dart`, `members_panel.dart`, `simple_launch_identity.dart`
- `capability<ProviderCredentialCapability>` → 同:`app_provider_cubit.dart`, `app_provider_detail_panel.dart`, `app_provider_form_sheet.dart`, `provider_credential_action_bar.dart`
- `capability<ProviderFormCapability>` → 同:`app_provider_form_sheet.dart`
- `capability<CliEffortCapability>` → 同:`workspace_cli_effort_helpers.dart`, `team_config_helpers.dart`, `headless_ai_service.dart`, `app_provider_form_sheet.dart`, `cli_effort_picker_field.dart`(注意 `headless_ai_service.dart` 里 effort 解析用帮助函数,核对)
- `capability<CredentialBindingCapability>` → 同:`app_provider_cubit.dart`, `credential_binding.dart`, `app_provider_detail_panel.dart`, `app_provider_form_sheet.dart`
- `capability<CredentialExportCapability>` → 同:`local_credential_exporter.dart`
- `cli_tool_registry.dart` 的 `defaultOfficialProviderId` 帮助方法改 `capability<ProviderCapability>`(方法名/消费方不变)

- [x] **Step 4: 更新测试**

provider 相关测试全部改 `ProviderCapability`;`passthrough_provider_form_capability` 相关测试补默认成员断言。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/registry/provider_form_registration_test.dart test/services/cli/registry/provider_credential_capability_test.dart test/services/cli/registry/provider_model_capability_test.dart test/services/cli/registry/all_cli_effort_capability_test.dart test/services/provider/ test/services/cli/opencode/provider/ 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge 8 provider-family capabilities into ProviderCapability"
```

---

### Task 13: CliSessionCapability(CliSessionLifecycle + PostManifestFlush + LaunchArgs + CliConfigLayout)

**Files:**
- Modify: `lib/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart` → `git mv` 为 `cli_session_capability.dart`,接口改名 `CliSessionCapability` 并吸收 3 个接口
- Delete: `post_manifest_flush_capability.dart`, `launch_args_capability.dart`, `cli_config_layout_capability.dart`
- Modify: `noop_cli_session_lifecycle_capability.dart` → `noop_cli_session_capability.dart`(补 3 组默认成员)
- Modify: 每 CLI 实现(`cursor/capabilities/session_lifecycle.dart` + `post_manifest_flush.dart` + `cursor_cli_config_layout.dart`;其余 CLI 的 launch args 实现),5 个工具定义
- Modify: `lib/services/cli/registry/cli_tool_registry.dart`(lifecycleFor 帮助方法), `lib/services/session/launch_command_builder.dart`, `lib/services/launch/session_connect_orchestrator.dart`, `lib/services/cli/cli_tool_adapter.dart`
- Modify: 测试(`noop_cli_session_lifecycle_capability_test.dart`, `post_manifest_flush_capability_test.dart`, `session_launch_lifecycle_gate_test.dart`, `cursor_session_lifecycle_paths_test.dart`, `cli_tool_adapter_test.dart`)

**Interfaces:**
- Produces: `CliSessionCapability` = CliSessionLifecycleCapability 全部成员 + 以下:

```dart
// 来自 PostManifestFlushCapability
Future<void> afterManifestFlush(PostManifestFlushContext ctx);

// 来自 LaunchArgsCapability
List<String> buildArguments(CliLaunchContext context);

// 来自 CliConfigLayoutCapability
String sessionConfigDir(
  RuntimeLayout layout,
  CliTool tool, {
  required String workspaceId,
  required String sessionId,
  String? memberId,
  String? teamId,
});
```

- Produces(同文件):`CliSessionPersistContext`/`CliSessionInitContext`/`CliSessionGateContext`/`CliSessionFinalizeContext`/`CliSessionPersistResult`/`CliSessionInitResult`/`CliSessionGateDecision`/`CliSessionPhase`, `PostManifestFlushContext`(原样迁入);`DefaultCliConfigLayout` 保留为共享默认(消费方 `sessionConfigDirForTool` 帮助函数改经 `CliSessionCapability`)
- Consumes: `CliLaunchContext`(`cli_tool_adapter.dart`)

- [x] **Step 1: 合并接口文件**

`git mv cli_session_lifecycle_capability.dart cli_session_capability.dart`;接口改名并加 3 组成员;迁入 `PostManifestFlushContext`;删 3 个旧文件(注意 `cli_config_layout_capability.dart` 的 `sessionConfigDirForTool` 帮助函数迁到新文件或消费方)。

- [x] **Step 2: 更新默认与每 CLI 实现**

`noop_cli_session_lifecycle_capability.dart` → `noop_cli_session_capability.dart`: `afterManifestFlush` 空实现、`buildArguments` 返回 `const []`、`sessionConfigDir` 委托 `DefaultCliConfigLayout`。cursor 的实现合并 `session_lifecycle.dart` + `post_manifest_flush.dart` + `cursor_cli_config_layout.dart` 为一个类;其余 CLI 的 launch args(如 `claude_tool.dart` 内联 `launchArgs`)并入 session 实现或保留独立实现类(仅改 implements 类型)。`DefaultCliConfigLayout` 保留。

- [x] **Step 3: 更新消费方**

- `cli_tool_registry.dart`: `lifecycleFor` → `capability<CliSessionCapability>`(返回 `NoopCliSessionCapability`)
- `launch_command_builder.dart`: `LaunchArgsCapability` → `CliSessionCapability` 取 `buildArguments`
- `session_connect_orchestrator.dart`: `PostManifestFlushCapability` → `CliSessionCapability` 取 `afterManifestFlush`
- `sessionConfigDirForTool`(在 `history_context_env_capability.dart` 等处的引用): 改经 `capability<CliSessionCapability>(tool)?.sessionConfigDir ?? DefaultCliConfigLayout().sessionConfigDir`

- [x] **Step 4: 更新测试**

`noop_cli_session_lifecycle_capability_test.dart` / `post_manifest_flush_capability_test.dart` / `cursor_session_lifecycle_paths_test.dart` / `cli_tool_adapter_test.dart` / `session_launch_lifecycle_gate_test.dart`: 改 `CliSessionCapability`。

- [x] **Step 5: 验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/registry/noop_cli_session_lifecycle_capability_test.dart test/services/cli/registry/capabilities/post_manifest_flush_capability_test.dart test/cubits/chat/session_launch_lifecycle_gate_test.dart test/services/cli/session_lifecycle/ test/services/cli/cli_tool_adapter_test.dart 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 6: 提交**

```bash
git add -A client/lib test
git commit -m "refactor(cli-capability): merge lifecycle/flush/launch-args/layout into CliSessionCapability"
```

---

### Task 14: ConfigProfileCapability 解散(最大任务,分 4 个子步骤)

**Files:**
- Modify: 每 CLI `capabilities/config_profile.dart`(5 个,claude 1100 行)按职责拆解
- Modify: `lib/services/cli/registry/config_profile/config_profile_context.dart`(上下文按需迁移/改名)
- Modify: `lib/services/provider/config_profile_service.dart`, `lib/services/launch/session_bootstrap_coordinator.dart`, `lib/services/provider/workspace_trust_provisioner.dart`
- Delete: `lib/services/cli/registry/capabilities/config_profile_capability.dart`
- Modify: `built_in_cli_tools.dart`(_verifyRequired 列表去掉 ConfigProfileCapability)
- Modify: 大量测试(config_profile 目录)

**Interfaces:**
- Produces: `ProviderCapability.materializeSessionHome`(Task 12 接口补充):

```dart
class SessionHomeContext {
  const SessionHomeContext({
    required this.workspaceId, required this.sessionId, required this.memberId,
    required this.tool, required this.paths, this.team, this.member,
    this.busIdle, this.workingDirectory = '', this.crossMachine = false,
    this.resolvedProviderId, this.credentialBasePath, this.catalog, this.isSimple,
  });
  // 字段 = ConfigProfileLaunchContext 相关字段(逐字段复核迁移)
}

class SessionHomeContribution {
  const SessionHomeContribution({this.environment = const {}, this.warnings = const []});
  final Map<String, String> environment;
  final List<String> warnings;
}

// 加入 ProviderCapability:
Future<SessionHomeContribution> materializeSessionHome(SessionHomeContext ctx);
```

- Produces: 共享 managed-hooks 装配(如 `lib/services/cli/registry/hook/managed_hook_provisioner.dart`):

```dart
class ManagedHookProvisioner {
  /// 收集 busIdle/agentStatus managed entries + 用户 entries,渲染并写盘。
  Future<HookWriteResult> renderManagedAndUserHooks({
    required List<HookEntry> entries,
    required HookCapability writer,
    required HookRenderContext ctx,
  });
}
```

(从 claude/flashskyai/codex 的 config_profile 实现中提取同一段 `managedEntries` 组装 + render + 写盘逻辑;输出片段拼接语义与原实现一致)

- [x] **Step 14a: 提取 provider/home 材料化 → ProviderCapability.materializeSessionHome**

对每个 CLI(建议顺序:claude → flashskyai → codex → cursor → opencode):
- 在 `capabilities/provider.dart` 增加 `materializeSessionHome`(Task 12 后补);把 `config_profile.dart` 中"provider 解析 + home 装配 + settings/metadata/llm_config + 跨机凭证桥"的方法体迁入;返回 env(warnings 由调用方收集)
- `config_profile.dart` 的 `contributeLaunch` 缩减为:调 `providerCapability.materializeSessionHome` + managed hooks(14b)+ prompt(14c),聚合 env/warnings 顺序与原实现一致
- 每迁移一个 CLI 跑该 CLI 的 config_profile 测试回归

- [x] **Step 14b: 提取 managed hooks → 共享 ManagedHookProvisioner**

- 建 `registry/hook/managed_hook_provisioner.dart`;把 5 个 config_profile 实现里 `managedEntries`(HookSeatContextCompleter.busIdleHooks/agentStatusHooks)+ user hooks 的组装、`writer.render`、脚本写盘、fragment 拼接逻辑收敛为共享服务(参数差异用条件参数)
- 5 个 `config_profile.dart` 改为调用共享服务;删除各自拷贝
- 跑 `config_profile/*` 测试 + `test/services/cli/registry/capabilities/hook_writer_test.dart`

- [x] **Step 14c: prompt 步骤接 PromptHubService**

5 个 `config_profile.dart` 的 prompt 步骤调 `PromptHubService.provisionForCli`(Task 11 已建);删除各自 prompt 内联逻辑与 `PromptProvisionCapability` 字段。

- [x] **Step 14d: 删除 ConfigProfileCapability,收编会话编排**

- 删除 `registry/capabilities/config_profile_capability.dart` 与各 CLI 剩余 config_profile 文件;`ensureSessionProfile` 的职责(metadata/settings 脚手架,sessionToolDir 默认文件)迁入 `ProviderCapability.materializeSessionHome`(spec 的 ConfigProfile 解散表明确"metadata 脚手架"归 ProviderCapability;claude/flashskyai 的实现方法体原样迁入)
- `config_profile_service.dart` / `session_bootstrap_coordinator.dart` 改调:`capability<ProviderCapability>(cli).materializeSessionHome` + `capability<HookCapability>(cli)`(经 ManagedHookProvisioner)+ `PromptHubService` + `capability<CliSessionCapability>(cli)`;env/warnings 汇总顺序保持
- `built_in_cli_tools.dart`: `_verifyRequired<ConfigProfileCapability>` 移除
- `workspace_trust_provisioner.dart`: `XxxConfigProfileCapability.toolId` 静态引用改为各 CLI 的 `XxxProviderCapability.toolId`(或迁移 toolId 常量到新类)

- [x] **Step 15: 全量验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `flutter test test/services/cli/ test/services/provider/ test/services/session/ test/services/mcp/ test/cubits/chat_cubit_session_launch_test.dart test/services/launch/ 2>&1 | tail -3`
Expected: 全部通过

- [x] **Step 16: 全量测试 + 文档更新 + 提交**

Run: `flutter test --exclude-tags integration 2>&1 | tail -3`
Expected: 全部通过
- 更新 `docs/superpowers/specs/2026-08-14-cli-capability-consolidation-design.md` 状态为 Done(若实现中发现偏离,回填)
- 更新 `AGENTS.md`(如有引用旧能力名)
```bash
git add -A client docs AGENTS.md
git commit -m "refactor(cli-capability): dissolve ConfigProfileCapability into domain capabilities"
```

---

### Task 15: 收尾核对

- [x] **Step 1: 孤儿接口扫描**

Run: `ls client/lib/services/cli/registry/capabilities/` 与旧接口名清单(46 个)对比,确认仅剩 14 个目标接口 + 共享实现文件。

- [x] **Step 2: 注册表一致性**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration 2>&1 | tail -3`
Expected: 0 errors 0 warnings,全部通过

- [x] **Step 3: 每 CLI 文件收敛核对**

Run: `ls client/lib/services/cli/{claude,codex,cursor,flashskyai,opencode}/capabilities/`
Expected: 每个 CLI 下为领域文件集合(provider/skill/plugin/mcp/hook/prompt/session/team_behavior/chat_interaction/terminal_behavior/headless/ai_history/executable/member_config_inspection 等,不再有孤儿文件)

- [x] **Step 4: 提交(如 Step 1-3 有修正)**

```bash
git add -A client
git commit -m "refactor(cli-capability): final sweep"
```
