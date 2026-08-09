# CLI Architecture

TeamPilot 支持多个 CLI 工具（Claude Code、Cursor、Codex、OpenCode、FlashskyAI）。本文档定义 CLI 代码的组织规范、能力接口模式、以及新增 CLI 的完整流程。

## 目录结构

每个 CLI 的所有代码集中在 `services/cli/{cli_name}/` 一个目录下：

```
services/cli/{cli_name}/
  {cli_name}_tool.dart              # CliToolDefinition 实现（必需）
  {cli_name}_bootstrap_entry.dart   # 运行时服务注入（如需要）
  capabilities/                     # CliCapability 接口实现
    config_profile.dart             # ConfigProfileCapability（必需）
    launch_args.dart                # LaunchArgsCapability（必需）
    wait_before_stop.dart           # WaitBeforeStopCapability（必需）
    provider_display.dart           # ProviderDisplayCapability（必需）
    config_ui.dart                  # CliConfigUiCapability（必需）
    installer.dart                  # InstallerCapability
    headless_run.dart               # HeadlessRunCapability
    headless_provision.dart         # HeadlessProvisionCapability
    mcp_config_writer.dart          # McpConfigWriterCapability
    plugin_provisioner.dart         # PluginProvisionerCapability
    resume_strategy.dart            # SessionResumeCapability
    provider_catalog.dart           # ProviderCatalogCapability
    history/                        # AiHistoryCapability 相关
      ai_transcript.dart
      side_resolver.dart
      ...
  provider/                         # Provider 层（凭证、模型、表单等）
    {cli_name}_provider_credential_capability.dart
    {cli_name}_provider_credentials_service.dart
    {cli_name}_provider_form_capability.dart
    {cli_name}_provider_model_capability.dart
    {cli_name}_live_import.dart
    {cli_name}_effort_capability.dart
    ...
  provider_presets.dart             # 预设 provider 数据
  provider_persistence.dart         # 凭证持久化策略
```

### 共享基础设施

`services/cli/registry/` 目录只保留能力接口定义和解析引擎，**不包含任何 CLI 特定实现**：

```
registry/
  cli_capability.dart               # CliCapability marker 接口
  cli_tool_definition.dart          # CliToolDefinition 抽象接口
  cli_tool_registry.dart            # 能力解析引擎
  built_in_cli_tools.dart           # 注册函数
  cli_bootstrap.dart                # 运行时服务注入
  capabilities/                     # 所有能力接口定义
    launch_args_capability.dart
    config_profile_capability.dart
    wait_before_stop_capability.dart
    provider_display_capability.dart
    cli_config_ui_capability.dart
    mcp_config_writer_capability.dart
    installer_capability.dart
    headless_run_capability.dart
    headless_provision_capability.dart
    plugin_provisioner_capability.dart
    provider_credential_capability.dart
    provider_model_capability.dart
    session_resume_capability.dart
    bus_transport_capability.dart
    turn_completion_capability.dart
    ...
```

## 能力接口模式

### 原则

**外部代码不得通过 `if (cli == CliTool.X)` 判断 CLI 身份。** 所有 CLI 差异化行为通过能力接口暴露。

```dart
// ❌ 禁止
if (cli == CliTool.cursor) return false;

// ✅ 正确
final cap = registry.capability<WaitBeforeStopCapability>(cli);
return cap?.defaultForceWaitBeforeStop ?? true;
```

### 模式定义

1. **接口** — 在 `registry/capabilities/` 中定义，继承 `CliCapability`：

```dart
// registry/capabilities/wait_before_stop_capability.dart
abstract interface class WaitBeforeStopCapability implements CliCapability {
  bool get defaultForceWaitBeforeStop;
}
```

2. **实现** — 在 `{cli_name}/capabilities/` 中提供具体实现：

```dart
// cursor/capabilities/wait_before_stop.dart
final class CursorWaitBeforeStop implements WaitBeforeStopCapability {
  const CursorWaitBeforeStop();
  @override
  bool get defaultForceWaitBeforeStop => false;
}
```

3. **注册** — 在 `{cli_name}_tool.dart` 中声明：

```dart
final class CursorCliTool implements CliToolDefinition {
  // 字段
  final WaitBeforeStopCapability waitBeforeStop;

  // 构造函数默认值
  CursorCliTool({
    ...
    this.waitBeforeStop = const CursorWaitBeforeStop(),
    ...
  });

  // 注册到 capabilities 列表
  @override
  Iterable<CliCapability> get capabilities => [
    ...
    waitBeforeStop,
    ...
  ];
}
```

4. **使用** — 通过 registry 解析：

```dart
final cap = CliToolRegistry.builtIn()
    .capability<WaitBeforeStopCapability>(cli);
```

### 简单标记能力 vs 服务能力

| 类型 | 示例 | 特点 |
|------|------|------|
| **标记能力** | `WaitBeforeStopCapability`（bool）<br>`ProviderDisplayCapability`（多个 bool） | 纯数据，无依赖，`const` 实例 |
| **服务能力** | `ProviderCredentialCapability`<br>`McpConfigWriterCapability` | 包含方法，可能有运行时依赖，通过 BootstrapEntry 注入 |

## 必需能力 vs 可选能力

每个 CLI **必须**实现以下能力（在 `built_in_cli_tools.dart` 中有 assert 校验）：

| 能力 | 接口 | 说明 |
|------|------|------|
| `ProviderModelCapability` | `registry/capabilities/provider_model_capability.dart` | 模型列表 |
| `MemberConfigInspectionCapability` | `registry/capabilities/member_config_inspection_capability.dart` | 成员配置 |
| `ConfigProfileCapability` | `registry/capabilities/config_profile_capability.dart` | 会话配置 |
| `LaunchArgsCapability` | `registry/capabilities/launch_args_capability.dart` | 启动参数 |
| `WaitBeforeStopCapability` | `registry/capabilities/wait_before_stop_capability.dart` | 停止前等待 |
| `ProviderDisplayCapability` | `registry/capabilities/provider_display_capability.dart` | Provider UI 展示 |
| `CliConfigUiCapability` | `registry/capabilities/cli_config_ui_capability.dart` | 设置页 UI |
| `TitleAttentionCapability` | `registry/capabilities/title_attention_capability.dart` | OSC 标题注意力 |
| `MarketplaceConsumerCapability` | `registry/capabilities/marketplace_consumer_capability.dart` | 市场插件消费 |
| `AgentStatusNormalizerCapability` | `registry/capabilities/agent_status_normalizer_capability.dart` | Agent 状态事件归一化 |
| `HistoryContextEnvCapability` | `registry/capabilities/history_context_env_capability.dart` | 历史上下文环境变量 |
| `CredentialExportCapability` | `registry/capabilities/credential_export_capability.dart` | 凭证导出（远程推送） |
| `RemoteAppDataCapability` | `registry/capabilities/remote_app_data_capability.dart` | 远程应用数据预置 |

以下能力根据 CLI 是否支持决定：

| 能力 | 说明 |
|------|------|
| `NativeTeamCapability` | 原生多 Agent 团队（仅 claude、flashskyai） |
| `MemberAgentPresetCapability` | 成员 Agent 预设（仅 claude、flashskyai） |
| `HeadlessRunCapability` | 无头运行 |
| `HeadlessProvisionCapability` | 无头配置 |
| `InstallerCapability` | CLI 安装 |
| `McpConfigWriterCapability` | MCP 配置写入 |
| `PluginProvisionerCapability` | 插件供给 |
| `SessionResumeCapability` | 会话恢复 |
| `CliSessionLifecycleCapability` | 会话生命周期（仅 cursor） |
| `CliConfigLayoutCapability` | CLI 配置布局（仅 cursor） |

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
  providerCredential: ClaudeProviderCredentialCapability(
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
| `capabilities/config_profile.dart` | `ConfigProfileCapability` 实现 |
| `capabilities/launch_args.dart` | `LaunchArgsCapability` 实现 |
| `capabilities/wait_before_stop.dart` | `WaitBeforeStopCapability` 实现 |
| `capabilities/provider_display.dart` | `ProviderDisplayCapability` 实现 |
| `capabilities/config_ui.dart` | `CliConfigUiCapability` 实现 |
| `capabilities/title_attention.dart` | `TitleAttentionCapability` 实现 |
| `capabilities/marketplace_consumer.dart` | `MarketplaceConsumerCapability` 实现 |
| `capabilities/agent_status_normalizer.dart` | `AgentStatusNormalizerCapability` 实现 |
| `capabilities/history_context_env.dart` | `HistoryContextEnvCapability` 实现 |
| `capabilities/credential_export.dart` | `CredentialExportCapability` 实现 |
| `capabilities/remote_app_data.dart` | `RemoteAppDataCapability` 实现 |

### 4. 实现可选的能力

根据 CLI 特性决定是否实现：installer、headless、mcp_writer、plugin_provisioner、resume_strategy、provider_catalog、AI history、等等。

### 5. 创建 Provider 层（如需要）

如果 CLI 有 OAuth 凭证或模型目录：

```
provider/
  newcli_provider_credential_capability.dart
  newcli_provider_credentials_service.dart
  newcli_provider_form_capability.dart
  newcli_provider_model_capability.dart
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
final cap = registry.capability<WaitBeforeStopCapability>(cli);
return cap?.defaultForceWaitBeforeStop ?? true;
```

### 禁止 CLI 特定类出现在非 CLI 目录中

```dart
// ❌ 禁止 — CLI 特定服务散落在通用目录
services/agent_status/claude_permission_sticky.dart
services/team/claude_roster_activity_source.dart

// ✅ 正确 — 所有 CLI 代码在 services/cli/{cli_name}/ 下
services/cli/claude/capabilities/permission_sticky.dart
services/cli/claude/roster_activity_source.dart
```

### 禁止所有 CLI 代码塞在一个文件

```dart
// ❌ 旧模式 — 5 个 adapter 在一个文件
cli_tool_adapter.dart  // ClaudeCodeCliToolAdapter, CursorCliToolAdapter, ...

// ✅ 新模式 — 每个 CLI 一个文件
claude/capabilities/launch_args.dart    // ClaudeCodeCliToolAdapter
cursor/capabilities/launch_args.dart    // CursorCliToolAdapter
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
| `ConfigProfileCapability` | `registry/capabilities/config_profile_capability.dart` | 服务 | ✅ |
| `LaunchArgsCapability` | `registry/capabilities/launch_args_capability.dart` | 服务 | ✅ |
| `ProviderModelCapability` | `registry/capabilities/provider_model_capability.dart` | 服务 | ✅ |
| `MemberConfigInspectionCapability` | `registry/capabilities/member_config_inspection_capability.dart` | 服务 | ✅ |
| `WaitBeforeStopCapability` | `registry/capabilities/wait_before_stop_capability.dart` | 标记 | ✅ |
| `ProviderDisplayCapability` | `registry/capabilities/provider_display_capability.dart` | 标记 | ✅ |
| `CliConfigUiCapability` | `registry/capabilities/cli_config_ui_capability.dart` | 标记 | ✅ |
| `ProviderCredentialCapability` | `registry/capabilities/provider_credential_capability.dart` | 服务 | - |
| `ProviderFormCapability` | `registry/capabilities/provider_form_capability.dart` | 服务 | - |
| `ProviderCatalogCapability` | `registry/capabilities/provider_catalog_capability.dart` | 服务 | - |
| `InstallerCapability` | `registry/capabilities/installer_capability.dart` | 服务 | - |
| `HeadlessRunCapability` | `registry/capabilities/headless_run_capability.dart` | 服务 | - |
| `HeadlessProvisionCapability` | `registry/capabilities/headless_provision_capability.dart` | 服务 | - |
| `McpConfigWriterCapability` | `registry/capabilities/mcp_config_writer_capability.dart` | 服务 | - |
| `PluginProvisionerCapability` | `registry/capabilities/plugin_provisioner_capability.dart` | 服务 | - |
| `SessionResumeCapability` | `registry/capabilities/session_resume_capability.dart` | 服务 | - |
| `BusTransportCapability` | `registry/capabilities/bus_transport_capability.dart` | 标记 | - |
| `TurnCompletionCapability` | `registry/capabilities/turn_completion_capability.dart` | 标记 | - |
| `TurnInterruptCapability` | `registry/capabilities/turn_interrupt_capability.dart` | 标记 | - |
| `CliSessionLifecycleCapability` | `registry/capabilities/cli_session_lifecycle_capability.dart` | 服务 | - |
| `CliConfigLayoutCapability` | `registry/capabilities/cli_config_layout_capability.dart` | 服务 | - |
| `NativeTeamCapability` | `registry/capabilities/native_team_capability.dart` | 标记 | - |
| `MemberAgentPresetCapability` | `registry/capabilities/member_agent_preset_capability.dart` | 服务 | - |
| `CliEffortCapability` | `registry/capabilities/cli_effort_capability.dart` | 服务 | - |
| `ResourceCapability` | `registry/capabilities/resource_capability.dart` | 标记 | - |
| `AiHistoryCapability` | `registry/capabilities/ai_history_capability.dart` | 服务 | - |
| `SkillInvocationSyntaxCapability` | `registry/capabilities/skill_invocation_syntax_capability.dart` | 标记 | - |
| `AgentStatusNormalizerCapability` | `registry/capabilities/agent_status_normalizer_capability.dart` | 标记 | ✅ |
| `HistoryContextEnvCapability` | `registry/capabilities/history_context_env_capability.dart` | 服务 | ✅ |
| `TitleAttentionCapability` | `registry/capabilities/title_attention_capability.dart` | 标记 | ✅ |
| `MarketplaceConsumerCapability` | `registry/capabilities/marketplace_consumer_capability.dart` | 标记 | ✅ |
| `CredentialExportCapability` | `registry/capabilities/credential_export_capability.dart` | 服务 | ✅ |
| `RemoteAppDataCapability` | `registry/capabilities/remote_app_data_capability.dart` | 服务 | ✅ |
