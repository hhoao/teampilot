# Qoder CN CLI 集成 设计文档

日期：2026-11-10

## 目标

把 Qoder 国内版 CLI（`qoderclicn`）作为独立 agent 接入 TeamPilot，与国际版 Qoder（`qodercli`）并存。用户可以在同一台机器上同时安装、配置 Provider、登录并启动两个版本，二者在可执行文件、凭据、模型缓存、会话配置目录和 UI 标签上互不影响。

## 背景与已确认事实

- 现有 `CliTool.qoder` 只对应国际版：
  - 二进制：`qodercli`
  - npm 包：`@qoder-ai/qodercli`
  - 安装入口：`https://download.qoder.com/qodercli/install.sh`
  - 官网：`https://qoder.com`
- Qoder 国内版是独立发行版：
  - 二进制：`qoderclicn`
  - 安装入口：`https://qoder.com.cn/install`（跳转到 `https://static.qoder.com.cn/qoder-cli-cn/install.sh`）
  - 官网：`https://qoder.com.cn`
  - 不在 `@qoder-ai/qodercli` 的 npm bin 列表中
- Qoder 的 Agent 接入是 ACP-only：启动 `[executable, '--acp']`，用 `QODER_CONFIG_DIR` 隔离配置与 `.auth`，不调用 `authenticate`，不做 in-place `session/load`，后台 tail `projects/**/*.jsonl`。
- 国内版与国际版同源，合理假设沿用同一套 `--acp` 与 `QODER_CONFIG_DIR` 协议；该假设必须用真实 `qoderclicn --acp` 握手验证。
- TeamPilot 的可执行路径、远程探测、Provider、登录态、模型缓存、session 配置目录都以 `CliTool` 身份为粒度，因此国内版需要独立身份，而不是在现有身份上动态切二进制。
- Qoder 余额与用量查询已经有独立的 Managed Provider 预设 `qoder` / `qoder-cn`，与本次 Agent 接入不是同一条链路；本次只补 CLI 标签，不改查询实现。

## 需求（已确认）

1. 新增独立 CLI 身份 `qoder-cn`，二进制 `qoderclicn`，可与 `qoder` 同时安装和使用。
2. 国内版拥有独立的 Provider 预设、登录流程、凭据存储、模型缓存和 session 配置目录。
3. 国内版默认不读取机器上的 `~/.qoder` 登录态，避免把国际版账号注入国内版。
4. 应用内安装支持本地与 SSH 的官方脚本；Windows 应用内安装不支持，明确提示手动安装并填路径。
5. 国内版沿用 ACP、headless、hook、session usage、history 的现有 Qoder 行为，仅按身份参数化。
6. 现有 `qoder` 的行为、配置和持久化数据保持不变。

## 方案总览

采用「独立身份 + 发行版描述符」：

- 新增 `CliTool.qoderCn('qoder-cn')`。
- 新增 `QoderFlavor`，集中描述 Global 与 CN 的差异（身份、二进制、Provider id、官网、安装入口、凭据命名空间、是否允许机器登录 fallback）。
- `QoderCliTool`、`QoderProviderCapability`、`QoderHeadlessCapability`、`QoderSessionUsageCapability`、`QoderPromptCapability`、`QoderAiHistoryCapability`、`QoderHookWriter`、`QoderAcpCapability` 接收 flavor，默认值为 Global，保证现有测试与调用点不被迫改动。
- 注册表注册两个 `QoderCliTool` 实例。

| 字段 | Global | CN |
|------|--------|----|
| `CliTool` | `qoder` | `qoderCn` |
| 持久化值 | `qoder` | `qoder-cn` |
| 二进制 | `qodercli` | `qoderclicn` |
| Provider id | `qoder` | `qoder-cn` |
| 官网 | `https://qoder.com` | `https://qoder.com.cn` |
| 安装入口 | npm / `https://download.qoder.com/qodercli/install.sh` | `https://qoder.com.cn/install` |
| 凭据命名空间 | `qoder` | `qoder-cn` |
| 机器 `~/.qoder` fallback | 允许 | 禁止 |
| 显示名 | Qoder | Qoder CN |

## 身份与注册

### `CliTool`

`client/lib/models/team_config.dart`：

- 新增 `qoderCn('qoder-cn')`，枚举顺序放在 `qoder` 之后。
- 更新类型注释，列出 `qoder-cn`。
- `tryParse` 已按 `.value` 小写匹配，无需额外逻辑。

### `QoderFlavor`

新增 `client/lib/services/cli/qoder/qoder_flavor.dart`：

```dart
final class QoderFlavor {
  const QoderFlavor({
    required this.cli,
    required this.executableName,
    required this.displayName,
    required this.providerId,
    required this.providerLabel,
    required this.websiteUrl,
    required this.installUrl,
    required this.authNamespace,
    required this.allowMachineAuthFallback,
  });

  final CliTool cli;
  final String executableName;
  final String displayName;
  final String providerId;
  final String providerLabel;
  final String websiteUrl;
  final String installUrl;
  final String authNamespace;
  final bool allowMachineAuthFallback;

  bool get isCn => cli == CliTool.qoderCn;

  static const global = QoderFlavor(
    cli: CliTool.qoder,
    executableName: 'qodercli',
    displayName: 'Qoder CLI',
    providerId: 'qoder',
    providerLabel: 'Qoder',
    websiteUrl: 'https://qoder.com',
    installUrl: 'https://download.qoder.com/qodercli/install.sh',
    authNamespace: 'qoder',
    allowMachineAuthFallback: true,
  );

  static const cn = QoderFlavor(
    cli: CliTool.qoderCn,
    executableName: 'qoderclicn',
    displayName: 'Qoder CLI CN',
    providerId: 'qoder-cn',
    providerLabel: 'Qoder CN',
    websiteUrl: 'https://qoder.com.cn',
    installUrl: 'https://qoder.com.cn/install',
    authNamespace: 'qoder-cn',
    allowMachineAuthFallback: false,
  );
}
```

### `QoderCliTool`

`client/lib/services/cli/qoder/qoder_tool.dart`：

- 构造函数接收 `QoderFlavor flavor = QoderFlavor.global`。
- flavor 相关能力在构造时派生，避免 CN 注册时漏传：
  - `executable`：Global 用 `QoderExecutableCapability()`，CN 用 `QoderCnExecutableCapability()`。
  - `provider`：默认 `QoderProviderCapability(flavor: flavor)`。
  - `headless`：默认 `QoderHeadlessCapability(flavor: flavor)`。
  - `sessionUsage`：默认 `QoderSessionUsageCapability(flavor: flavor)`。
  - `prompt`：默认 `QoderPromptCapability(flavor: flavor)`。
  - `aiHistory`：默认 `QoderAiHistoryCapability(flavor: flavor)`。
  - `hookWriter`：默认 `QoderHookWriter(flavor: flavor)`。
  - `acp`：默认 `QoderAcpCapability(transcriptFallbackPrefix: flavor.cli.value)`。
- `id => flavor.cli`。
- 注册表仍可显式传入 provider / headless（需要 `storage`）。
- 因为构造函数在 initializer list 中派生默认值，`QoderCliTool` 不再是 `const`；唯一受影响的测试 `qoder_acp_local_smoke_test.dart` 去掉 `const`。

### 注册

`client/lib/services/cli/registry/built_in_cli_tools.dart` 在现有 Qoder 注册之后增加：

```dart
registry.register(
  QoderCliTool(
    flavor: QoderFlavor.cn,
    provider: QoderProviderCapability(
      flavor: QoderFlavor.cn,
      storage: storage,
      modelsService: storage == null
          ? null
          : QoderModelsService(
              storage: storage,
              namespace: QoderFlavor.cn.authNamespace,
              executable: QoderFlavor.cn.executableName,
              useMachineAuthFallback: false,
            ),
    ),
    headless: QoderHeadlessCapability(
      flavor: QoderFlavor.cn,
      storage: storage,
    ),
  ),
);
```

现有 Global 注册补上 `flavor: QoderFlavor.global`，并显式传入
`QoderModelsService(namespace: 'qoder', executable: 'qodercli', useMachineAuthFallback: true)`；行为不变。

## 可执行文件与安装

### 共享展示

新增一个 flavor 驱动的展示辅助（放在 `capabilities/executable.dart` 或 `qoder_flavor.dart`），统一生成：

- `label(l10n)`：Global 用 `l10n.appProvider.toolQoder`，CN 用 `toolQoderCn`。
- `preferencesPathKey`：`flavor.cli.value`。
- `defaultExecutableName` / `executableName`：`flavor.executableName`。
- 远程探测：`DefaultRemoteCliLocator(flavor.executableName).locate(run)`。
- `CliExecutablePathRowSpec` 的 key 前缀按 flavor 区分，例如 CN：
  - `qoder-cn-cli-executable-path-field`
  - `qoder-cn-cli-executable-path-browse-button`
  - `qoder-cn-cli-executable-path-reset-button`
  - `qoder-cn-cli-executable-install-button`
  - `debouncerTag = qoder_cn_cli_executable_path`

### Global 安装

`QoderExecutableCapability extends NpmInstallerCapability` 的 npm 安装流程保持不变；`label`、`preferencesPathKey`、remote locator、row spec 改由 `QoderFlavor.global` 经共享辅助函数派生。

### CN 安装

新增 `client/lib/services/cli/qoder/capabilities/executable_cn.dart`，实现 `CliExecutableCapability`：

- `supportsInstaller => !Platform.isWindows`。
- 本地 / SSH 都执行官方脚本：

  ```text
  curl -fsSL https://qoder.com.cn/install | bash
  ```

- 安装后复用 `NpmInstallerCapability.remotePostInstallLocateScript('qoderclicn')` 定位可执行文件。
- 失败信息使用 `installerFailureMessage(...)`，只包含 stderr 摘要，不写入额外敏感信息。
- Windows 上 `supportsInstaller` 为 false，设置页只提供路径输入；如果仍收到安装请求，返回明确的手动安装提示。

## ACP 与运行时

### ACP

`client/lib/services/cli/qoder/capabilities/acp.dart`：

- `QoderAcpCapability` 增加 `transcriptFallbackPrefix`（默认 `'qoder'`）。
- 其余行为完全共享：`--acp`、`QODER_CONFIG_DIR`、无 `authenticate`、`supportsInPlaceSessionLoad = false`、`forwardSessionNewMcpServers = false`。
- `createBackgroundTranscriptSource` 把 `fallbackPrefix` 传给 `QoderAcpBackgroundTranscriptSource`。

### Headless

`capabilities/headless.dart`：

- `QoderHeadlessCapability({this.storage, this.flavor = QoderFlavor.global})`。
- `executable => flavor.executableName`。
- `interactiveContextForHeadless(ctx, flavor.cli)`。
- 构造 `QoderAuthStore` 时传 `namespace: flavor.authNamespace`、`useMachineFallback: flavor.allowMachineAuthFallback`。
- 构造 `QoderProviderSettingsResolver` 时传 `cli` 与 `toolKey`，保证 CN one-shot 解析 CN Provider。

### Prompt

`capabilities/prompt.dart`：

- `QoderPromptCapability({this.flavor = QoderFlavor.global})`。
- `toolId => flavor.cli.value`，用于 `sessionToolDir(...)`。
- contribution id / origin sourceId 使用 `'${toolId}-member-role'`，避免 Global 与 CN 的资源来源混淆。

### Session usage

`capabilities/usage/session_usage.dart`：

- `QoderSessionUsageCapability({this.flavor = QoderFlavor.global})`。
- `SessionUsageEvent.cli = flavor.cli`。
- `requestId` 前缀与 source id 使用 `flavor.cli.value`（例如 `qoder-cn:<messageId>`、`qoder-cn-jsonl:<path>`）。
- `QODER_CONFIG_DIR` 读取逻辑不变。

### History

`capabilities/history/ai_history_capability.dart`：

- `QoderAiHistoryCapability({this.flavor = QoderFlavor.global})`。
- `tailFallbackPrefix => flavor.cli.value`。
- adapter 使用 `QoderAiTranscriptAdapter(id: flavor.cli.value)`；Global 仍为 `qoder`。

## Provider、登录与模型

### 预设

`provider_presets.dart` 拆分为：

- `QoderProviderPresets.global`：现有 `qoder` 预设，内容不变。
- `QoderProviderPresets.cn`：新增预设：

  ```dart
  AppProviderPreset(
    id: 'qoder-cn',
    label: 'Qoder CN',
    template: AppProviderConfig(
      id: 'qoder-cn',
      cli: CliTool.qoderCn,
      name: 'Qoder CN',
      websiteUrl: 'https://qoder.com.cn',
      category: AppProviderCategory.official,
      isOfficial: true,
      apiKeyField: 'api_key',
      defaultModel: 'auto',
      icon: 'qoder',
      notes:
          'Isolated login: Sign in opens a Qoder CN login terminal that does '
          'not touch your global ~/.qoder account.',
    ),
  )
  ```

- 保留 `all` 作为两者合集，供兼容与测试使用。
- `QoderProviderCapability.presets` 只返回当前 flavor 的预设。

### Provider capability

`capabilities/provider.dart`：

- 构造函数接收 `flavor`（默认 Global）。
- `catalogCli => flavor.cli`。
- `defaultOfficialProviderId => flavor.providerId`。
- `loginExecutableName => flavor.executableName`。
- `_authStore` 与 `buildLoginDialog` 构造 `QoderAuthStore` 时传 `namespace: flavor.authNamespace`、`useMachineFallback: flavor.allowMachineAuthFallback`。
- `materializeSessionHome`：
  - `sessionToolDir(..., flavor.cli.value, ...)`
  - `writeSettingsFile(..., tool: flavor.cli.value, ...)`
  - `QODER_CONFIG_DIR` 环境变量保持同名
- `_resolveLaunchProvider` 使用带 flavor 的 `QoderProviderSettingsResolver`。
- `buildExtraSection` 把 `flavor.cli` 传给 `QoderProviderFormSection`；表单内部用该值构造 effort picker 的 `CliTool` 与临时 `AppProviderConfig`。

### Provider 解析

`provider/qoder_provider_settings_resolver.dart`：

- 构造函数增加 `CliTool cli = CliTool.qoder` 与 `String toolKey = 'qoder'`（或直接从 flavor 派生）。
- `findById` / `resolveSole` 使用 `cli`。
- `resolveForLaunch` 读取 `team.providerIdsByTool[toolKey]`；CN 使用 `qoder-cn`。
- `QoderProviderCapability` 构造 resolver 时传 flavor。

### 凭据存储

`provider/qoder_auth_store.dart`：

- 构造函数增加：
  - `String namespace = 'qoder'`
  - `bool useMachineFallback = true`
- 路径改为：
  - `cli-login/<namespace>/...`
  - `providers/<namespace>/...`
- `authSourceDir`：只有 `useMachineFallback == true` 时才回退到 `<machineHome>/.qoder/.auth`；CN 传 false，只从 Provider 存储取。
- marker 文件名保持 `.qoder-provider`；由于目录已按 namespace 隔离，不会互相覆盖。
- `seedSessionAuth`、`writeProviderAuthFromLogin`、`markerFor`、partial-pair 保护逻辑不变。

### 模型目录

`provider/qoder_models_service.dart`：

- 构造函数增加：
  - `String namespace = 'qoder'`
  - `bool useMachineAuthFallback = true`
- 临时探测目录：`tmp/<namespace>-models/<providerId>`。
- 磁盘缓存：`cache/<namespace>_models/<providerId>.json`。
- 构造 `QoderAuthStore` 时传 namespace 与 fallback 开关。
- 默认 executable 仍为 `qodercli`；CN 注册时传 `qoderclicn`。
- 静态 fallback 模型表先复用 `QoderModelCatalog`；联网后以 ACP 实时目录为准。

### 登录对话框

`QoderLoginDialog` 不需要新增 flavor 参数：它只接收 executable、store、providerId，路径与成功判定都来自 store。登录环境仍是：

```text
HOME=<isolated login home>
QODER_CONFIG_DIR=<isolated login config>
```

如果国内版不接受 `QODER_CONFIG_DIR`，登录与 session 都会失效；这属于协议假设，列入风险与验收。

## UI、Hook、Usage

### 品牌与标签

- `client/lib/widgets/cli/cli_brand_icon.dart`：
  - `cliBrandIconKey(CliTool.qoderCn) => 'qoder'`
  - `cliToolIconData(CliTool.qoderCn) => Icons.terminal`
- `client/lib/pages/usage/usage_format.dart`：
  - `usageCliLabel(CliTool.qoderCn) => 'Qoder CN'`
  - `usageCliColor(CliTool.qoderCn)` 复用 Qoder 的紫色。
- `client/lib/l10n/l10n_extensions.dart`：
  - `appProviderToolLabel(CliTool.qoderCn) => appProvider.toolQoderCn`

### l10n

- `client/lib/i18n/appProvider_en.i18n.json`：`"toolQoderCn": "Qoder CN"`
- `client/lib/i18n/appProvider_zh.i18n.json`：`"toolQoderCn": "Qoder 国内版"`
- 运行 `cd client && dart run slang` 重新生成 `translations_*.g.dart`。

### 凭据 UI

- `provider_credential_action_bar.dart` 的所有 `switch (cli)`：
  - 工具栏标题 / importGlobal / importFile / revoke / revokeConfirm 使用 `l10n.appProvider.toolQoderCn`。
  - login 动作使用 `l10n.qoder.credentialsLogin`（复用 Qoder 文案）。
- `provider_credential_messages.dart`：
  - 成功消息复用 `l10n.qoder.credentialsSignedIn`。
  - 通用失败复用 `l10n.qoder.credentialsActionFailed`。

### Hook

- `client/lib/models/hook_event.dart`：在每张 `Map<CliTool, HookCliSupport>` 中，为 `CliTool.qoderCn` 添加与 `CliTool.qoder` 完全相同的条目。
- `client/lib/services/hook/import/hook_event_name_mapper.dart`：加入 `CliTool.qoderCn` 的事件名集合，内容与 Qoder 相同。
- `client/lib/services/hook/import/hook_import_parser.dart`：加入 `CliTool.qoderCn: const ClaudeFamilyHooksJsonDialect()`。
- `client/lib/pages/hooks/hook_import_dialog.dart`：CLI 列表中 Qoder 之后加入 `CliTool.qoderCn`。
- `QoderHookWriter` 通过 flavor 查询矩阵，保证 `nativeEvent` 与 UI 支持徽标一致。

### 其他穷举点

- `client/lib/services/storage/workspace_cli_cache.dart`：`CliTool.qoderCn => const []`。
- `runtimeLayoutDefaultTools` 会自动为 `qoder-cn` 创建运行时目录，无需额外改动。
- `app_shell.dart`、`vault_cubit.dart`、`app_provider_cubit.dart` 等 `CliTool.values` 循环会自动覆盖 CN，无需特判。

## 错误处理与降级

| 情况 | 行为 |
|------|------|
| 设置页未配置 CN 可执行路径 | 使用默认 `qoderclicn` 探测；找不到时启动失败并给出常规 CLI 不可用提示 |
| 本地/SSH 安装脚本非 0 退出 | `CliInstallResult(success: false)`，消息包含阶段与 stderr 摘要 |
| 安装完成但定位不到 `qoderclicn` | 失败消息提示把安装目录加入 PATH 或手动填写路径 |
| Windows 请求应用内安装 | `supportsInstaller == false`，提示手动安装 |
| CN 未登录 | ACP 握手返回 auth-required；现有 Qoder auth sentinel 逻辑直接适用 |
| CN 不支持 `--acp` / `QODER_CONFIG_DIR` | 启动超时，runtime 标记该 CLI 不可用；不静默降级到 PTY |
| CN 没有 Provider 且机器 `~/.qoder` 有登录 | 不读取机器登录；提示用户创建 Provider 并登录 |
| 模型实时探测失败 | 使用 `QoderModelCatalog` 静态 fallback |

## 改动文件

### 新增

- `client/lib/services/cli/qoder/qoder_flavor.dart`
- `client/lib/services/cli/qoder/capabilities/executable_cn.dart`
- `client/test/services/cli/qoder/qoder_cn_registry_test.dart`
- `client/test/services/cli/qoder/qoder_cn_provider_test.dart`
- `client/test/services/cli/qoder/qoder_cn_auth_store_test.dart`

### 修改

- `client/lib/models/team_config.dart`
- `client/lib/services/cli/qoder/qoder_tool.dart`
- `client/lib/services/cli/registry/built_in_cli_tools.dart`
- `client/lib/services/cli/qoder/capabilities/executable.dart`
- `client/lib/services/cli/qoder/capabilities/acp.dart`
- `client/lib/services/cli/qoder/capabilities/headless.dart`
- `client/lib/services/cli/qoder/capabilities/prompt.dart`
- `client/lib/services/cli/qoder/capabilities/hook_writer.dart`
- `client/lib/services/cli/qoder/capabilities/usage/session_usage.dart`
- `client/lib/services/cli/qoder/capabilities/history/ai_history_capability.dart`
- `client/lib/services/cli/qoder/capabilities/acp_background_transcript.dart`
- `client/lib/services/cli/qoder/provider_presets.dart`
- `client/lib/services/cli/qoder/capabilities/provider.dart`
- `client/lib/services/cli/qoder/provider/qoder_provider_settings_resolver.dart`
- `client/lib/services/cli/qoder/provider/qoder_auth_store.dart`
- `client/lib/services/cli/qoder/provider/qoder_models_service.dart`
- `client/lib/services/cli/qoder/provider/qoder_provider_form_section.dart`
- `client/lib/pages/usage/usage_format.dart`
- `client/lib/widgets/cli/cli_brand_icon.dart`
- `client/lib/l10n/l10n_extensions.dart`
- `client/lib/widgets/app_provider/provider_credential_action_bar.dart`
- `client/lib/widgets/app_provider/provider_credential_messages.dart`
- `client/lib/models/hook_event.dart`
- `client/lib/services/hook/import/hook_event_name_mapper.dart`
- `client/lib/services/hook/import/hook_import_parser.dart`
- `client/lib/pages/hooks/hook_import_dialog.dart`
- `client/lib/services/storage/workspace_cli_cache.dart`
- `client/lib/i18n/appProvider_en.i18n.json`
- `client/lib/i18n/appProvider_zh.i18n.json`
- 生成：`client/lib/l10n/translations_en.g.dart`、`client/lib/l10n/translations_zh.g.dart`

### 修改测试

- `client/test/models/team_config_cli_tool_test.dart`（长度 9 → 10，新增 CN 解析）
- `client/test/models/simple_launch_identity_test.dart`（补 switch 分支）
- `client/test/integration/support/cli_test_profile.dart`（补 switch 分支）
- `client/test/integration/qoder_acp_local_smoke_test.dart`（去掉 `const QoderCliTool()`）
- `client/test/services/cli/qoder/qoder_registry_test.dart`（现有 Global 断言不受影响）
- `client/test/services/cli/qoder/qoder_headless_test.dart`（新增 CN executable / CLI 断言）
- `client/test/services/cli/qoder/capabilities/usage/qoder_session_usage_test.dart`（新增 CN 事件 cli / requestId 断言）
- `client/test/services/cli/qoder/qoder_provider_materialize_test.dart`（新增 CN sessionToolDir 与 settings tool 断言；Global 断言保持不变）

## 测试

### 身份与注册

- `CliTool.qoderCn.value == 'qoder-cn'`，`tryParse('qoder-cn')`、`tryParse('Qoder-CN')` 均返回 CN。
- `CliTool.values.length == 10`。
- 注册表中存在 `CliTool.qoderCn`，且：
  - `CliExecutableCapability.defaultExecutableName == 'qoderclicn'`
  - `preferencesPathKey == 'qoder-cn'`
  - `AcpCapability` 非空
  - `CliTransportCapability.supported == {CliTransport.acp}`
  - `ProviderCapability`、`HookCapability`、`HeadlessCapability` 非空
  - `launchesAcpOnly(CliTool.qoderCn) == true`

### 可执行与安装

- CN executable capability 的 label、默认名、row spec key 前缀、remote probe 命令使用 `qoderclicn`。
- CN 安装命令包含 `https://qoder.com.cn/install`，不包含 npm。
- `supportsInstaller` 在非 Windows 平台为 true。
- 安装后定位脚本使用 `qoderclicn`。

### Provider 与凭据

- CN capability 的 `presets` 只包含 `qoder-cn`，且 `template.cli == CliTool.qoderCn`、`websiteUrl == 'https://qoder.com.cn'`。
- Global capability 的 `presets` 仍只包含 `qoder`。
- `QoderProviderSettingsResolver` 对 CN 读取 `providerIdsByTool['qoder-cn']`，不会命中 `qoder` 的 team 默认。
- `QoderAuthStore(namespace: 'qoder-cn')` 的登录目录、Provider 目录位于 `.../qoder-cn/...`，与 Global 路径不重叠。
- CN `authSourceDir` 在 Provider 存储缺失时返回 null，即使临时 home 下存在 `.qoder/.auth`。
- Global 的 `authSourceDir` 仍会回退到机器 `~/.qoder/.auth`。

### Session 与运行时

- CN `materializeSessionHome`：
  - session config dir 路径包含 `qoder-cn`；
  - `settings.json` 写入时 `tool == 'qoder-cn'`；
  - 环境变量为 `QODER_CONFIG_DIR`；
  - Provider 解析使用 CN 的默认 Provider。
- CN headless 的 `executable == 'qoderclicn'`，`interactiveContextForHeadless` 的 CLI 为 `qoderCn`。
- CN session usage 事件 `cli == CliTool.qoderCn`，requestId 以 `qoder-cn:` 开头。
- CN prompt 的 `toolId == 'qoder-cn'`，AGENTS.md 写入 CN session config dir。
- CN ACP 后台 transcript 的 fallback prefix 为 `qoder-cn`。

### Hook 与 UI 映射

- `HookEventCapability` 对 CN 的支持情况与 Qoder 完全一致。
- hook import parser / mapper 能识别 CN。
- `usageCliLabel(CliTool.qoderCn) == 'Qoder CN'`。
- brand icon 与 tool label 映射存在。

### 真实 CLI 冒烟（条件执行）

如果开发机可安装 `qoderclicn`，增加或手工执行：

1. `qoderclicn --acp` 启动；
2. ACP `initialize` 成功；
3. `session/new` 成功（带已登录的 `.auth`）；
4. 发送一条 prompt 能收到 `end_turn`。

该用例使用 `@Tags(['integration'])`，不可用时跳过，不进入普通测试套件的必过集合。

### 完成前验证

```bash
cd client
dart run slang
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart \
  test/models/team_config_cli_tool_test.dart \
  test/services/cli/qoder/qoder_cn_registry_test.dart \
  test/services/cli/qoder/qoder_cn_provider_test.dart \
  test/services/cli/qoder/qoder_cn_auth_store_test.dart \
  test/services/cli/qoder/qoder_provider_materialize_test.dart \
  test/services/cli/qoder/qoder_headless_test.dart \
  test/services/cli/qoder/capabilities/usage/qoder_session_usage_test.dart
# 最后在后台跑完整测试套件
dart run tool/run_tests.dart
```

## 不做的事

- 不把国际版与国内版合并成一个 CLI 身份，也不做“区域下拉切换二进制”。
- 不复用国际版机器 `~/.qoder` 登录态到国内版。
- 不为国内版单独维护一套静态模型表；先复用并依赖 ACP 实时目录。
- 不新增国内版专属的 ACP translator；除非真实握手证明错误通道不同。
- 不改 Qoder 余额/用量查询适配器与 Managed Provider 预设。
- 不实现 Windows 应用内安装。
- 不做国内版专属的 hook 方言；先复用 Claude 家族 JSON 方言。

## 风险与待验证

1. **协议假设（最高风险）**：国内版是否支持隐藏参数 `--acp` 和 `QODER_CONFIG_DIR` 尚未用真实二进制验证。若任一不支持：
   - `--acp` 不支持 → runtime 启动超时并标记不可用；
   - `QODER_CONFIG_DIR` 不支持 → 登录与 session 凭据隔离失效。
   实现阶段必须做一次真实握手；如果结论是否定的，本次只保留身份与 Provider 骨架并把启动标为 unsupported，或重新设计 CN 的启动/隔离方式。
2. **机器登录目录**：国内版可能写入不同的默认目录。当前 CN 禁止机器 fallback，因此不受影响；若用户确认存在独立机器目录，再单独补 fallback。
3. **安装脚本支持面**：官方脚本可能在 Termux、旧 glibc 或非 Unix 环境失败。应用内安装只负责执行脚本并报告失败，不预判平台；Windows 直接隐藏安装按钮。
4. **模型目录差异**：国内版模型 id 可能与国际版不同。联网后以 ACP 探测结果为准；离线 fallback 可能不准确，但不影响已登录后的实际选择。
5. **Hook 方言差异**：国内版可能使用不同 hook 事件名或配置格式。当前按同源假设复用；如果真实结果不同，再为 CN 单独提供 hook 能力。
6. **枚举扩展成本**：新增 `CliTool` 值会触发多处穷举 switch 编译错误，这是有意的安全网；按本文件清单逐项补齐即可。
