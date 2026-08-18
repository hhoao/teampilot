# CLI Architecture

TeamPilot 支持多个 CLI 工具（Claude Code、Cursor、Codex、OpenCode、FlashskyAI）。本文档定义 CLI 代码的组织规范、能力接口模式、以及新增 CLI 的完整流程。

## 目录结构

每个 CLI 的所有代码集中在 `services/cli/{cli_name}/` 一个目录下：

```
services/cli/{cli_name}/
  {cli_name}_tool.dart              # CliToolDefinition 实现（必需）
  {cli_name}_bootstrap_entry.dart   # 运行时服务注入（如需要）
  capabilities/                     # CliCapability 实现（按功能域一个文件）
    provider.dart                   # ProviderCapability（必需）
    session.dart                    # CliSessionCapability（必需；cursor 拆为 session_lifecycle.dart + session_lifecycle_paths.dart）
    team_behavior.dart              # TeamBehaviorCapability（必需）
    chat_interaction.dart           # ChatInteractionCapability（必需）
    terminal_behavior.dart          # TerminalBehaviorCapability（必需）
    plugin.dart                     # PluginCapability（必需）
    executable.dart                 # CliExecutableCapability（必需）
    skill.dart                      # SkillCapability（codex/opencode 覆盖；claude/flashskyai 用共享 DefaultSkillCapability）
    mcp.dart                        # McpCapability（claude/flashskyai 共用 claude/capabilities/mcp.dart）
    prompt.dart                     # PromptCapability
    headless.dart                   # HeadlessCapability（如支持无头运行）
    launch providers               # 启动参数能力（按语义拆分）
    history/                        # AiHistoryCapability 相关
      ai_history_capability.dart    # 该 CLI 的 AiHistoryCapability 实现（含 tool call resolvers）
      ai_transcript.dart
      side_resolver.dart
      ...
  provider/                         # Provider 层（凭证、模型、表单等）
    {cli_name}_provider_credentials_service.dart
    {cli_name}_provider_form_section.dart
    {cli_name}_model_catalog.dart
    {cli_name}_live_import.dart
    codex_hook_writer.dart          # HookCapability 实现（codex/cursor 在此；opencode 在 capabilities/，claude/flashskyai 共享 registry/config_profile/claude_family_hook_writer.dart）
    ...
  provider_presets.dart             # 预设 provider 数据
  provider_persistence.dart         # 凭证持久化策略
```

每个 CLI 的**所有**具体能力实现都放在自己的目录下；`registry/capabilities/` 里不允许出现
按 CLI 命名的具体类（`ClaudeXxx`/`CursorXxx`/…），只能有接口定义、共享数据类和被多个 CLI
共用的共享实现（如 `ClaudeFamilyAgentStatusNormalizer`、`SharedToolCallResolvers`、
`DefaultCliConfigLayout`、`NoopCliSessionCapability`、`ClaudeFamilyHookWriter`、
`DefaultSkillCapability`）。

CLI 专属 UI 组件（表单段、binding 字段）也放在 `services/cli/{cli_name}/provider/` 下，由对应
ProviderForm / CredentialBinding 能力引用；不要在 `widgets/` 下散落 `claude_*` 组件。

### 共享基础设施

`services/cli/` 根下的共享辅助（如 `cli_executable_discovery.dart`）与
`services/cli/registry/` 共同构成**跨 CLI 共享基础设施**；`registry/` 只保留能力接口定义、
解析引擎和共享子目录，**不包含任何 CLI 特定实现**：

```
services/cli/
  cli_executable_discovery.dart     # 可执行文件发现（共享）
  registry/
    cli_capability.dart             # CliCapability marker 接口
    cli_tool_definition.dart        # CliToolDefinition 抽象接口
    cli_tool_registry.dart          # 能力解析引擎
    built_in_cli_tools.dart         # 注册函数 + 必需能力 assert 校验
    cli_bootstrap.dart              # 运行时服务注入（Map 驱动）
    capabilities/                   # 14 个功能域能力接口 + 共享实现/辅助
      provider_capability.dart      # ProviderCapability（6 个 Hub 契约之一）
      skill_capability.dart         # SkillCapability
      plugin_capability.dart        # PluginCapability
      mcp_capability.dart           # McpCapability
      hook_capability.dart          # HookCapability
      prompt_capability.dart        # PromptCapability
      cli_session_capability.dart   # CliSessionCapability（8 个基础设施之一）
      team_behavior_capability.dart # TeamBehaviorCapability
      chat_interaction_capability.dart
      terminal_behavior_capability.dart
      cli_executable_capability.dart
      headless_capability.dart
      ai_history_capability.dart
      member_config_inspection_capability.dart
      claude_family_agent_status_normalizer.dart   # 共享：claude 家族状态归一化
      claude_family_hook_registry.dart             # 共享：claude 家族 hook 注册表
      hook_registry.dart                           # 共享：hook 事件注册表
      noop_cli_session_capability.dart             # 共享：无会话逻辑的 CliSessionCapability 默认
      plugin_manifest_paths.dart                   # 共享：插件 manifest 路径
      shared_tool_call_resolvers.dart              # 共享：工具调用解析器基线
      history/                                     # 共享：subagent 侧解析器 / 结果回填
      resume/                                      # 共享：pinned transcript 探测
    config_profile/               # 共享：config profile 作用域 / agent 状态钩子 / claude 家族 hook writer
    headless/                     # 共享：无头供给支撑
    hook/                         # 共享：托管 hook 供给器（ManagedHookProvisioner）
    installer/                    # 共享：npm / node / termux 安装策略
    mcp_writers/                  # 共享：MCP 元数据合并
    plugins/                      # 共享：claude-flavor 插件注册表写入器
    prompt/                       # 共享：PromptHubService（多源 prompt 收集/物化）
    resources/                    # 共享：默认 ResourceCapability
    launch/                       # 共享：启动上下文、参数 provider、贡献与装配器
      cli_launch_context.dart
      cli_headless_launch_context.dart
      cli_launch_arg_provider.dart
      cli_headless_launch_arg_provider.dart
      cli_launch_constraint.dart
      cli_headless_launch_constraint.dart
      cli_launch_arg_contribution.dart
      cli_launch_arg_assembler.dart
```

共享基础设施（如被 Claude/FlashskyAI/Cursor 共用的 `plugins/claude_flavor_registry_writer.dart`）
放 registry 子目录；只有单一 CLI 使用的实现必须留在 `{cli_name}/` 下。

## 能力接口模式

### 原则

**外部代码不得通过 `if (cli == CliTool.X)` 判断 CLI 身份。** 所有 CLI 差异化行为通过能力接口暴露。

```dart
// ❌ 禁止
if (cli == CliTool.cursor) return false;

// ✅ 正确
final cap = registry.capability<TeamBehaviorCapability>(cli);
return cap?.defaultForceWaitBeforeStop ?? true;
```

### 模式定义

1. **接口** — 在 `registry/capabilities/` 中定义，继承 `CliCapability`：

```dart
// registry/capabilities/team_behavior_capability.dart
abstract interface class TeamBehaviorCapability implements CliCapability {
  bool get defaultForceWaitBeforeStop;
}
```

2. **实现** — 在 `{cli_name}/capabilities/` 中提供具体实现：

```dart
// cursor/capabilities/team_behavior.dart
final class CursorTeamBehavior implements TeamBehaviorCapability {
  const CursorTeamBehavior();
  @override
  bool get defaultForceWaitBeforeStop => false;
}
```

3. **注册** — 在 `{cli_name}_tool.dart` 中声明：

```dart
final class CursorCliTool implements CliToolDefinition {
  // 字段
  final TeamBehaviorCapability teamBehavior;

  // 构造函数默认值
  CursorCliTool({
    ...
    this.teamBehavior = const CursorTeamBehavior(),
    ...
  });

  // 注册到 capabilities 列表
  @override
  Iterable<CliCapability> get capabilities => [
    ...
    teamBehavior,
    ...
  ];
}
```

4. **使用** — 通过 registry 解析：

```dart
final cap = CliToolRegistry.builtIn()
    .capability<TeamBehaviorCapability>(cli);
```

### Hub 契约 vs 基础设施能力

| 类型 | 示例 | 特点 |
|------|------|------|
| **Hub 契约（物化器）** | `ProviderCapability` / `SkillCapability` / `PluginCapability` / `McpCapability` / `HookCapability` / `PromptCapability` | 对应用户可见的 6 个功能库；注册器收集虚拟实例，启动时统一物化到 CLI 原生配置 |
| **基础设施能力** | `CliSessionCapability`<br>`TerminalBehaviorCapability` | 会话/终端等行为差异；多为纯数据 + 少量方法，`const` 实例，可能经 BootstrapEntry 注入运行时服务 |

## 必需能力 vs 可选能力

每个 CLI **必须**实现以下能力（在 `built_in_cli_tools.dart` 中有 `_verifyRequired<T>` / assert 全量校验）：

| 能力 | 接口 | 说明 |
|------|------|------|
| `ProviderCapability` | `registry/capabilities/provider_capability.dart` | Provider 目录、凭证、模型、effort、`materializeSessionHome`（session home 材料化） |
| `MemberConfigInspectionCapability` | `registry/capabilities/member_config_inspection_capability.dart` | 成员配置检查 |
| `CliSessionCapability` | `registry/capabilities/cli_session_capability.dart` | 会话持久化/初始化/finalize、配置目录 |
| `TeamBehaviorCapability` | `registry/capabilities/team_behavior_capability.dart` | 团队协作行为（native team、wait-before-stop、presence、agent 预设） |
| `ChatInteractionCapability` | `registry/capabilities/chat_interaction_capability.dart` | Agent 状态归一化 + 结构化 ask / 审批 |
| `TerminalBehaviorCapability` | `registry/capabilities/terminal_behavior_capability.dart` | turn interrupt、标题注意力、全屏输入 |
| `CliExecutableCapability` | `registry/capabilities/cli_executable_capability.dart` | 可执行文件解析 / 安装 / UI |
| `PluginCapability` | `registry/capabilities/plugin_capability.dart` | 插件物化 |

以下能力根据 CLI 是否支持决定：

| 能力 | 说明 |
|------|------|
| `SkillCapability` | Skill 物化（codex/opencode 覆盖；claude/flashskyai 用共享 `DefaultSkillCapability`） |
| `McpCapability` | MCP 配置写入（claude/flashskyai 共用 `FlashskyaiMcpCapability`） |
| `HookCapability` | 用户 hook 渲染（claude/flashskyai 共用 `ClaudeFamilyHookWriter`） |
| `PromptCapability` | 成员 prompt 收集（`virtualize`）+ 物化（`materialize`），经 `PromptHubService` 装配 |
| `HeadlessCapability` | 无头运行（一次性调用 + 供给） |
| `AiHistoryCapability` | transcript 定位/解析、会话恢复、tool call 解析器 |
| 团队能力细分 | `TeamBehaviorCapability.supportsNativeTeam`（仅 claude、flashskyai）、`agentPresetStyle`（agent 预设） |

`CliSessionCapability.sessionConfigDir` 是所有历史定位 / 环境构造的**唯一**配置目录来源：如
`SessionHistoryContextBuilder` 通过它解析 toolRoot 后传给
`AiHistoryCapability.sessionEnv(toolRoot:)`，各 CLI 自行推导所需 env（cursor 的
`HOME` = 配置目录的父目录），外部代码不做 `if (cli == …)` 特判。

## BootstrapEntry 模式

当 CLI 需要运行时注入的服务（如凭证服务、模型目录），在 CLI 目录下创建 `{cli_name}_bootstrap_entry.dart`：

```dart
// claude/claude_bootstrap_entry.dart
final class ClaudeBootstrapEntry implements CliBootstrapEntry {
  const ClaudeBootstrapEntry({required this.credentialsService});
  final ClaudeProviderCredentialsService credentialsService;
}
```

然后在 `built_in_cli_tools.dart` 中通过 `bootstrap.entry<T>(cli)` 获取：

```dart
final claudeEntry = bootstrap.entry<ClaudeBootstrapEntry>(CliTool.claude);
registry.register(ClaudeCliTool(
  provider: ClaudeProviderCapability(
    credentials: claudeEntry?.credentialsService,
  ),
));
```

在 `app_shell.dart` 中构造 BootstrapEntry 并放入 Map：

```dart
cliToolRegistry.configure(CliBootstrap({
  CliTool.claude: ClaudeBootstrapEntry(
    credentialsService: claudeCredentialsService,
  ),
  CliTool.cursor: CursorBootstrapEntry(
    credentialsService: cursorCredentialsService,
    agentModelsService: CursorAgentModelsService(),
  ),
  // ...
}));
```

不需要注入服务的 CLI（如 flashskyai）不在 Map 中添加条目。

## 新增 CLI 流程

### 1. 添加枚举值

在 `models/team_config.dart` 的 `CliTool` 枚举中添加：

```dart
enum CliTool {
  // ... existing values
  newcli('newcli');

  const CliTool(this.value);
  final String value;
}
```

### 2. 创建目录和必需文件

```bash
mkdir -p services/cli/newcli/{capabilities/history,provider}
```

### 3. 实现必需的能力

最少需要创建以下文件：

| 文件 | 内容 |
|------|------|
| `newcli_tool.dart` | `CliToolDefinition` 实现 |
| `capabilities/provider.dart` | `ProviderCapability` 实现 |
| `capabilities/session.dart` | `CliSessionCapability` 实现 |
| `capabilities/team_behavior.dart` | `TeamBehaviorCapability` 实现 |
| `capabilities/chat_interaction.dart` | `ChatInteractionCapability` 实现 |
| `capabilities/terminal_behavior.dart` | `TerminalBehaviorCapability` 实现 |
| `capabilities/plugin.dart` | `PluginCapability` 实现 |
| `capabilities/executable.dart` | `CliExecutableCapability` 实现 |

### 4. 实现可选的能力

根据 CLI 特性决定是否实现：`capabilities/skill.dart`、`capabilities/mcp.dart`、`capabilities/hook.dart`、`capabilities/prompt.dart`、`capabilities/headless.dart`、`capabilities/history/`（`AiHistoryCapability` + tool call resolvers）、等等。

### 5. 创建 Provider 层（如需要）

如果 CLI 有 OAuth 凭证或模型目录：

```
provider/
  newcli_provider_credentials_service.dart
  newcli_provider_form_section.dart
  newcli_model_catalog.dart
provider_presets.dart
provider_persistence.dart
```

### 6. 创建 BootstrapEntry（如需要注入服务）

```dart
// newcli_bootstrap_entry.dart
final class NewcliBootstrapEntry implements CliBootstrapEntry {
  const NewcliBootstrapEntry({required this.credentialsService});
  final NewcliProviderCredentialsService credentialsService;
}
```

### 7. 注册

在 `registry/built_in_cli_tools.dart` 中添加 import 和 `registry.register()`：

```dart
import '../newcli/newcli_tool.dart';

void registerBuiltInCliTools(...) {
  // ... existing registrations
  registry.register(NewcliCliTool(
    // ... capabilities
  ));
}
```

### 8. 在 app_shell.dart 中注入服务（如需要）

```dart
cliToolRegistry.configure(CliBootstrap({
  // ... existing entries
  CliTool.newcli: NewcliBootstrapEntry(
    credentialsService: newcliCredentialsService,
  ),
}));
```

### 验证

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

## 反模式（禁止）

### 禁止按能力类型分组

```dart
// ❌ 旧模式 — 能力类型作为顶级目录
registry/installer/claude_installer.dart
registry/installer/cursor_installer.dart
registry/installer/codex_installer.dart

// ✅ 新模式 — 每个 CLI 一个目录
claude/capabilities/installer.dart
cursor/capabilities/installer.dart
codex/capabilities/installer.dart
```

### 禁止外部 if (cli == ...) 判断

```dart
// ❌ 禁止 — 调用方判断 CLI 身份
if (cli == CliTool.cursor) return false;

// ✅ 正确 — 通过能力解析
final cap = registry.capability<TeamBehaviorCapability>(cli);
return cap?.defaultForceWaitBeforeStop ?? true;
```

### 禁止 CLI 特定类出现在非 CLI 目录中

```dart
// ❌ 禁止 — CLI 特定服务散落在通用目录
services/team/claude_team_roster_service.dart
services/session/remote_flashskyai_command_builder.dart
widgets/app_provider/claude_credential_binding_field.dart

// ✅ 正确 — 所有 CLI 代码在 services/cli/{cli_name}/ 下
services/cli/claude/team_roster_service.dart
services/cli/claude/provider/claude_credential_binding_field.dart
services/cli/flashskyai/remote_flashskyai_command_builder.dart
```

### 禁止所有 CLI 代码塞在一个文件

```dart
// ✅ 新模式 — 交互式与 headless 均由每个 CLI 的语义能力注册 Provider
claude/capabilities/workspace_access_launch.dart
cursor/capabilities/workspace_access_launch.dart
claude/capabilities/headless.dart
codex/capabilities/headless.dart
```

### 禁止 CliBootstrap 命名参数

```dart
// ❌ 旧模式 — 新增 CLI 需要修改 CliBootstrap 类
class CliBootstrap {
  final ClaudeProviderCredentialsService? claudeCredentialsService;
  final CursorProviderCredentialsService? cursorCredentialsService;
  // 新增 CLI → 需要加字段
}

// ✅ 新模式 — Map 驱动，新增 CLI 不改 CliBootstrap
class CliBootstrap {
  final Map<CliTool, CliBootstrapEntry> _entries;
}
```

### 禁止 UI 层硬编码 CLI 列表

```dart
// ❌ 旧模式 — 5 个重复的 widget 块
CliExecutablePathSettingsRow(cli: CliTool.claude, title: ...)
CliExecutablePathSettingsRow(cli: CliTool.codex, title: ...)
CliExecutablePathSettingsRow(cli: CliTool.cursor, title: ...)
...

// ✅ 新模式 — 循环 registry.launchable
for (final def in CliToolRegistry.builtIn().launchable)
  _buildCliRow(def.id, ...)
```

## 能力接口清单

| 能力接口 | 文件 | 类型 | 必需 |
|---------|------|------|------|
| `ProviderCapability` | `registry/capabilities/provider_capability.dart` | Hub 契约 | ✅ |
| `SkillCapability` | `registry/capabilities/skill_capability.dart` | Hub 契约 | - |
| `PluginCapability` | `registry/capabilities/plugin_capability.dart` | Hub 契约 | ✅ |
| `McpCapability` | `registry/capabilities/mcp_capability.dart` | Hub 契约 | - |
| `HookCapability` | `registry/capabilities/hook_capability.dart` | Hub 契约 | - |
| `PromptCapability` | `registry/capabilities/prompt_capability.dart` | Hub 契约 | - |
| `CliSessionCapability` | `registry/capabilities/cli_session_capability.dart` | 基础设施 | ✅ |
| `TeamBehaviorCapability` | `registry/capabilities/team_behavior_capability.dart` | 基础设施 | ✅ |
| `ChatInteractionCapability` | `registry/capabilities/chat_interaction_capability.dart` | 基础设施 | ✅ |
| `TerminalBehaviorCapability` | `registry/capabilities/terminal_behavior_capability.dart` | 基础设施 | ✅ |
| `CliExecutableCapability` | `registry/capabilities/cli_executable_capability.dart` | 基础设施 | ✅ |
| `HeadlessCapability` | `registry/capabilities/headless_capability.dart` | 基础设施 | - |
| `AiHistoryCapability` | `registry/capabilities/ai_history_capability.dart` | 基础设施 | - |
| `MemberConfigInspectionCapability` | `registry/capabilities/member_config_inspection_capability.dart` | 基础设施 | ✅ |

> 注：46 → 14 收敛（2026-08-14）。`ConfigProfileCapability` 已解散：其"provider 解析 +
> home 材料化"编排归入 `ProviderCapability.materializeSessionHome`，managed hooks 归
> `ManagedHookProvisioner`（`registry/hook/`），prompt 归 `PromptHubService`（`registry/prompt/`）。

## 启动参数能力流

启动参数不是由调用方拼接，也不是由某个会话能力兼任。启动边界先把语义输入收集成
`CliLaunchContext`，再从已解析的 `CliToolDefinition` 的 `capabilities` 中发现所有
`CliLaunchArgProvider`，最后由唯一的 `CliLaunchArgAssembler` 生成扁平的 `List<String>`：

```text
TeamProfile + TeamMemberConfig + session/runtime inputs
                         │
                         ▼
                 CliLaunchContext
                         │
                         ▼
              CliToolDefinition.capabilities
                         │
              CliLaunchArgProvider.buildLaunchArgs
                         │
                         ▼
              CliLaunchArgAssembler.assemble
           校验 → 分阶段排序 → 展平为 CLI argv
```

### 上下文、Provider 与 Contribution

`CliLaunchContext` 是 CLI 无关的启动语义输入。它包含团队和成员、会话选择（resume 或
fixed id）、主工作目录、`additionalDirectories`、模型/设置/提示文件、WSL 路径开关、
原生团队开关，以及归一化的 `LaunchSecurityPolicy`。UI、PTY、SSH、预览和外部终端都应
通过同一上下文进入装配流程；它们不应自行解释 CLI flag。

实现某个语义区域的能力可以同时实现 `CliLaunchArgProvider`：

```dart
abstract interface class CliLaunchArgProvider implements CliCapability {
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  );
}
```

Provider 返回不可变语义片段 `CliLaunchArgContribution`，而不是修改共享 argv。每个片段
包含：

- `key`：语义贡献的稳定标识，不是单个 option token；
- `phase`：装配阶段；
- `args`：已经分词的原始 argv token，不做 shell quoting；
- `exclusiveGroup`：互斥选择（例如 resume 与 fixed session、权限模式）。

Provider 可以在语义未启用时返回空结果。是否存在某个 Provider 由实际的 CLI definition
注册决定，不能因为其他 CLI 支持同一语义就假定它也存在。当前五个内置可启动 CLI 的
注册形状如下：

| CLI | 已注册的启动 Provider 语义 |
|-----|----------------------------|
| Claude | 原生团队身份、会话、工作区、模型/设置、权限、提示、用户额外参数 |
| FlashskyAI | 原生团队身份、会话、工作区、模型、权限、提示、用户额外参数 |
| Codex | 会话、工作区、模型、权限、用户额外参数；不注册原生团队身份 Provider |
| Cursor | 团队行为、会话、工作区、模型、权限、用户额外参数 |
| OpenCode | 会话、模型、agent、用户额外参数；工作区外部目录走配置，不注册 argv Provider |

新增 CLI 时，先在该 CLI 的 `capabilities/` 中实现它实际支持的 Provider，再把实例按
稳定语义顺序放入 `{cli_name}_tool.dart` 的 `capabilities` 列表。不要在测试或调用方为
了凑齐一组“通用 Provider”而注册该 CLI 不支持的能力。启动契约测试会遍历
`CliToolRegistry` 中的全部可启动 definition，检查 Provider 已注册、注册顺序稳定，并
在相同上下文下检查贡献 key 稳定且不重复。

Assembler 的公共调用入口是：

```dart
final args = const CliLaunchArgAssembler().assemble(tool, context);
```

其签名为 `List<String> assemble(CliToolDefinition tool, CliLaunchContext context)`；它接收
definition 而不是裸的 CLI 枚举，因而只会装配该 definition 实际注册的能力。

### 阶段、顺序与冲突校验

`LaunchArgPhase` 的顺序就是最终 argv 的跨 Provider 主顺序：

```text
command → session → workspace → identity → model → behavior → security
        → prompt → user
```

Assembler 按以下顺序工作：

1. 按 definition 中的能力注册顺序收集每个 `CliLaunchArgProvider` 的贡献；
2. 拒绝重复的 `key`；同一语义不能由两个 Provider 隐式覆盖；
3. 拒绝同一 `exclusiveGroup` 中出现多个贡献，并在异常中保留冲突 key；
4. Provider 对不支持的请求抛出带 CLI、贡献 key 和原因的
   `CliLaunchCapabilityException`；禁止静默降级或丢弃请求；
5. 先按 `LaunchArgPhase`，再按 Provider 注册顺序，最后按同一 Provider 内的贡献顺序
   稳定排序；
6. 按原始 token 展平为最终 `List<String>`。

`CliSessionCapability` 只负责会话生命周期和配置目录；它不是 argv 的备用来源。启动
调用链不能因为没有找到 Provider 就回退到另一套按 CLI 分支的参数逻辑。

### 归一化安全策略映射

调用方只传递 `LaunchSecurityPolicy` 的三个正交维度：
`approval`（`cliDefault` / `ask` / `autoApprove` / `never`）、`sandbox`
（`cliDefault` / `readOnly` / `workspaceWrite` / `fullAccess`）和 `hookTrust`
（`cliDefault` / `trustedOnly` / `bypass`）。UI 文案（例如 plan、auto、manual）必须在
进入 Provider 前映射为明确的策略组合，不能把某个文案直接当成通用 CLI flag。

`LaunchSecurityPolicy()` 与 `LaunchSecurityPolicy.fullAccess` 表示应用的完全访问默认值；
只有需要明确委托给 CLI 时才使用 `LaunchSecurityPolicy.cliDefault`。这样“应用默认权限”和
“CLI 默认权限”不会再依赖一个含义模糊的空构造函数。

当前启动参数 Provider 的映射是：

| 归一化策略 | Claude / FlashskyAI | Codex | Cursor | OpenCode |
|------------|--------------------|-------|--------|----------|
| 显式 CLI 默认（三项均 `cliDefault`） | 不追加权限 argv | 不追加权限 argv | 不追加权限 argv | `OpencodePermissionLaunch` 显式验证；保留 CLI 默认配置 |
| `ask + readOnly + trustedOnly` | `--permission-mode plan` | 不支持，抛能力异常 | 不支持，抛能力异常 | 不由启动 argv 表达 |
| `autoApprove + workspaceWrite + trustedOnly` | `--permission-mode acceptEdits` | 不支持，抛能力异常 | 不支持，抛能力异常 | 不由启动 argv 表达 |
| `never + fullAccess + bypass`（`fullAccess`） | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` 与 `--dangerously-bypass-hook-trust` | `--force` | 不由启动 argv 表达；由 `OpencodePermissionLaunch` 校验，并由 provider 物化 `edit` / `bash` / `external_directory` |

如果 CLI 无法表示一个明确请求，Provider 或 Constraint 必须返回结构化能力错误；不能悄悄使用 CLI 默认
权限。OpenCode 的权限请求/应答属于配置和运行时能力：full-access 由 provider 物化为
`permission.edit`、`permission.bash` 与 `permission.external_directory`，其余当前无法
完整表达的策略由 `OpencodePermissionLaunch` 拒绝。

### 工作区目录的 CLI 差异

`workingDirectory` 和 `additionalDirectories` 是同一份归一化语义输入，但输出由 CLI
自己的 Provider 决定：

- Claude：主目录使用 `--dir`，每个额外目录使用一对 `--add-dir <path>`；
- FlashskyAI：主目录使用 `--dir`，额外目录同样逐个重复 `--add-dir <path>`；
- Codex：主目录使用 `--cd`，并且对每个非空、已归一化的额外目录重复一对
  `--add-dir <path>`。多个目录不能合并成一个参数，也不能只保留第一个；
- Cursor：主目录使用 `--workspace`，额外目录逐个使用 `--add-dir <path>`；
- OpenCode：进程工作目录和外部目录是配置/运行时问题。额外目录写入 OpenCode 配置的
  `permission.external_directory`（由配置能力物化），保持配置-only，不生成
  `--add-dir` argv。

因此，新增或修复工作区支持时应修改对应 CLI 的 workspace Provider 或配置能力；不要
给 `CliLaunchContext` 增加 CLI 专属字段，也不要在通用启动边界按 CLI 身份拼接参数。

## Hook 管线（用户可配置 hooks）

用户 hook（运行时机事件 → 命令/脚本）从全局库（`/hooks`，`<root>/hooks/{id}/hook.json`）按
scope 启用（`ConfigBundle.hookIds`，team > expert > workspace 合并），随 session 启动经
**统一 hook 管线**物化到各 CLI 原生配置。所有来源（用户库 / 插件 `hooks/hooks.json` /
扩展 settings-hook / 内部托管 agent-status·bus-idle·team-lead delegate）由
`HookSeatContextCompleter` 组装为 `HookEntry`，每 CLI 一个 `HookCapability` 实现
（`HookWriteResult` = 文件级配置片段 + 生成脚本 + 警告；claude/flashskyai 共用
`ClaudeFamilyHookWriter`），装配点经共享 `ManagedHookProvisioner` 只调自己的 writer。
Command 类 hook 经 `GlueScriptBuilder` 包成 `teampilot-hook-<id>-<event>.sh`（stdin 透传、
空 stdout → 决策 JSON 注入、非空 stdout 透传、exit code 透传、`timeout <t>s bash -c`、双方言）。

每 CLI writer 与配置落点、事件支持矩阵、决策 JSON 契约、已知限制的**唯一事实来源**：
[docs/cli-formats/hooks.md](cli-formats/hooks.md)（13 事件 × 5 CLI 矩阵，`HookEventCapability.matrix`
为代码侧唯一事实源，writer 与 UI 能力矩阵共用）。修改任何 hook 行为前先读该页；行为差异需回填。

## 消息与工具调用解析接入点

transcript 历史与工具气泡的解析链路按**三层职责**组织，详见
[docs/tool-call-parsing-convention.md](tool-call-parsing-convention.md)：

| 层 | 位置 | 职责 |
|----|------|------|
| **纯接口 + 数据** | `client/packages/ai_message_core` | `AiToolCallPart` / `AiEditHunk` / `AiEditHunkCodec` 等接口与数据类型，零实现、零 tool name 硬编码 |
| **可配置泛型实现** | `client/lib/services/ai_history/` | `Configurable*` resolver / edit codec / 类别表，配置经构造函数注入 |
| **每 CLI 具体配置** | `client/lib/services/cli/<cli>/capabilities/` | 各 CLI 的 resolver 配置与 history 实现（共享基线在 `registry/capabilities/`） |

解析行为经两个能力接口暴露（禁止外部 `if (cli == …)` 特判）：

1. **`AiHistoryCapability`**（`registry/capabilities/ai_history_capability.dart:118-166`，服务能力）
   — transcript 定位与解析面：`locate`（:119）、`adapter`（:120）、`lineAppend`
   （:124，逐事件增量钩子，null = 只能全量）、`tailFallbackPrefix`（:129，必须与全量
   adapter 的 fallback id 前缀一致）、`subagentToolNames`（:132）、`subagentSideResolver`
   （:133）、`toolResultEnricher`（:134）、`liveCacheToken`（:141，可选 live 缓存指纹）、
   `incrementalRefresher`（:145，非 JSONL 存储的行级增量刷新）、`sessionEnv`（:152，
   历史上下文环境变量，来自原 HistoryContextEnvCapability）、`binding` / `detectNativeId`
   （:155/:160，会话恢复，来自原 SessionResumeCapability）。
   每 CLI 一个实现，位于 `<cli>/capabilities/history/ai_history_capability.dart`。
2. **tool call resolvers** — 2026-08-14 起四个解析器 getter（`editResolver` /
   `fileResolver` / `shellResolver` / `categoryResolver`，分别对应 Edit/File/Shell/Category
   四类解析器）收编进 `AiHistoryCapability`（`ai_history_capability.dart:162-165`），
   不再单独成能力。共享基线 `SharedToolCallResolvers`
   （`registry/capabilities/shared_tool_call_resolvers.dart`）覆盖绝大多数键，单 CLI 专属键
   在各 CLI 的 `<cli>/capabilities/tool_call_resolvers.dart` 以追加语义覆盖。

### 截断回填机制（ToolResultEnricher）

工具结果解析以 adapter 的 parse 为**第一通道**，`ToolResultEnricher` 只补缺失结果：

- 接口：`registry/capabilities/history/tool_result_enricher.dart:5-28` —
  `matchesTruncationMarker(result)`（:10，命中截断占位符才值得回填，loader 据此跳过
  `enrich`）、`requiresFilesystem`（:18，是否必须留在主 isolate）、
  `enrich(...)`（:22-27）。
- 装配点：各 CLI 的 `AiHistoryCapability` 构造**默认值**注入 enricher，无需
  `switch (cli)`：claude / flashskyai → `ClaudeCompatibleToolResultEnricher`
  （`claude/capabilities/history/ai_history_capability.dart:15`、
  `flashskyai/capabilities/history/ai_history_capability.dart:15`；flashskyai 复用
  claude 目录下的同一类，`compatible_tool_result_enricher.dart:12`）、opencode →
  `OpencodeToolOutputBackfillEnricher`（`opencode/capabilities/history/ai_history_capability.dart:15`）、
  codex → `NoOpToolResultEnricher`（`codex/capabilities/history/ai_history_capability.dart:13`）。
- 范例：`opencode/capabilities/history/tool_output_backfill_enricher.dart:37` —
  按截断标记定位缺失结果并从 `tool-output/` 全量文件回填；可行性结论见
  [docs/cli-formats/truncation-backfill-audit.md](cli-formats/truncation-backfill-audit.md)
  （codex 不可行 / opencode 有条件可行）。

### 接入指引与格式事实来源

- 新增 CLI 的解析链路接入：按 **6 步清单**执行
  [docs/cli-formats/adding-a-cli.md](cli-formats/adding-a-cli.md)（Step 0 枚举/tool 定义
  → Step 1 history capability → Step 2 tool call resolvers → Step 3 注册 → Step 4 测试
  → Step 5 文档），其中 history capability 与 resolvers 的接口签名、实现模式、验证命令
  均在该文件内给出。
- 工具调用格式的**唯一事实来源**是 [docs/cli-formats/](cli-formats/)（总览矩阵
  `README.md` + 每 CLI 格式页 + `message-layer-audit.md` + `tool-layer-coverage.md`）：
  评审或修改任何解析代码前先读对应 CLI 页与覆盖矩阵，行为差异需回填文档。

## 共享模型与能力归属

- **Provider 凭证模型**：`CredentialProbe` / `CredentialStatus` 在 `models/credential_probe.dart`；
  `CredentialLinkResult`（claude/cursor 共用）在 `models/credential_link_result.dart`。
- **flashskyai 镜像**：`services/cli/flashskyai/provider/flashskyai_provider_mirror.dart`（把其它 CLI
  的 catalog 行镜像成 flashskyai 记录），`ProviderImportService` 只做编排。
- **AiHistory 增量前缀**：`AiHistoryCapability.tailFallbackPrefix` 由各 CLI 声明（必须与全量
  adapter 的 fallback id 前缀一致），loader 不再 `switch (cli)`。
- **官方 catalog id**：`ProviderCapability.defaultOfficialProviderId` 由各 CLI 声明；
  `CliToolRegistry.defaultOfficialProviderId(cli)` 供服务层取用。模型层不持有 cli 键控数据：
  `SimpleLaunchIdentity.resolve(..., officialProviderId:)` 由服务注入解析函数，
  `AppSession.simpleIdentity` 对旧数据的兜底在连接接缝处通过
  `SimpleLaunchIdentity.withOfficialDefaultProvider` 注入完成。
- **Agent 状态归一化**：`ChatInteractionCapability.normalize(body)` 承载（原
  `AgentStatusNormalizerCapability`），claude/codex/flashskyai 共用 registry 下的
  `ClaudeFamilyAgentStatusNormalizer`，cursor 与 opencode 各在自己的目录实现；共享
  `AgentStatusNormalizer` 门面只做能力查找。

## 能力清单中的 l10n 映射

UI 层的 CLI 标签映射（如 provider 凭证操作条）使用**穷尽式 `switch (cli)`**（覆盖全部
`CliTool.values`，无 `_` 默认分支）——新增 CLI 枚举值时编译强制补齐标签，杜绝静默落到
错误文案。工具名映射集中在 `l10n/l10n_extensions.dart#appProviderToolLabel`。
