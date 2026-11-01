# 收口 CLI 身份判断（个人 ACP / opencode env / cursor hook / flashskyai provider）

- 日期：2026-11-01
- 依据：`docs/cli-architecture.md:124`、`:431-440` —— 外部代码不得用 `if (cli == CliTool.X)` 判断 CLI 身份

## 目标

把 A 组中「按 CLI 身份决定行为」的分支改为能力查询，行为保持不变（除下文标注的两处等价收敛）。
改完后，新增一个 CLI 只需注册能力，不必回头改这些调用点。

## 非目标

- `app_shell` 的 codex 专属 ACP 文案、`workspace_cli_cache` 缓存表、`managed_provider_*` 模板表、
  `models/hook_event.dart` 支持矩阵、各类 label/icon/color switch：本次不动。
  （chore：这些属于「CLI 身份数据表」，与行为分支不同，后续单独评估。）
- 不新增 CLI。

## 设计

### 1. 个人 ACP 开关（`CliTransportCapability.canChooseTransport`）

现状 `pages/home_workspace/workspace/claude_acp_launch_switch.dart:23-26` 硬编码四个 CLI。
真实语义是「这个 CLI 有没有第二条启动路径可选」，而这正是 transport 声明：

| CLI | `transport.supported` | 个人 ACP 可选 |
|-----|----------------------|--------------|
| claude / cursor / codex / opencode | `{pty, acp}` | 是 |
| gemini / codebuddy | `{acp}` | 否（ACP-only，无可选项） |

`built_in_cli_tools.dart:164-170` 已断言 `transport.supports(acp) == (AcpCapability != null)`，
transport 是可信的单一事实源；`showsPersonalAcpSwitch` 只是它的重复声明，且 codebuddy 必须手工
写 `false` 才能保持一致——一旦漏写就会漂移。

`CliTransportCapability` 新增：

```dart
/// 用户是否可以在 PTY / ACP 之间选择（两种传输都已声明）。
/// ACP-only 的 CLI 没有可选项。
bool get canChooseTransport =>
    supports(CliTransport.pty) && supports(CliTransport.acp);
```

调用点：

```dart
bool _personalAcpAllowed({required bool isPersonal, required CliTool? cli, bool? isAndroidOverride}) {
  if (!isPersonal || cli == null || _isAndroid(isAndroidOverride)) return false;
  return CliToolRegistry.builtIn()
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
}
```

`readPersonalAcpDefault` 的 switch 改为读偏好（见 2）；`ProviderNotFoundException`
分支继续用 `defaultTransport == acp`。

同时删除冗余声明：

- `AcpSettingsCapability.showsPersonalAcpSwitch`（含 `DefaultAcpSettingsCapability` 参数、
  `codebuddy_tool.dart:71` 的 `false`）
- `pages/config/cli_readiness_card.dart:587,617` 改读
  `_registry.capability<CliTransportCapability>(widget.cli)?.canChooseTransport ?? false`
  （该文件已有 `_registry`，`_separateAdapter` 同款写法）
- `test/services/cli/acp_settings_capability_test.dart:16,30`、
  `test/services/cli/codebuddy/codebuddy_registry_test.dart:52` 改为断言 transport

保留 `AcpSettingsCapability` 的其余字段（`usesSeparateAdapter` / `adapterExecutableName` /
`adapterInstaller`）——它们描述适配器，transport 表达不了。

> 唯一无法用 transport 表达的例外：某 CLI 同时支持两种传输但产品上故意不给开关。
> 真出现时再给 `AcpSettingsCapability` 加一个 `bool?` 覆盖字段，现在不预设。

### 2. 个人 ACP 默认值改为按 CLI 键的 map

`models/session_preferences.dart` 的 4 个 `*PersonalAcpDefault` 字段合并为：

```dart
final Map<String, bool> personalAcpDefaults; // key: CliTool.value，缺省 true

bool personalAcpDefaultFor(CliTool cli) => personalAcpDefaults[cli.value] ?? true;
SessionPreferences withPersonalAcpDefault(CliTool cli, bool value);
```

- `fromJson`：读新键 `personalAcpDefaults`；缺失时回退读 4 个旧键（升级迁移）。
- `toJson`：只写新键。
- `copyWith`：以 `personalAcpDefaults` 取代 4 个 bool 参数。

调用点：

| 位置 | 改法 |
|------|------|
| `cubits/session_preferences_cubit.dart:198-213` | `personalAcpDefaultFor` / `withPersonalAcpDefault`，四个公开 setter 收敛为一个内部实现 |
| `pages/home_workspace/workspace/claude_acp_launch_switch.dart:48-54` | 读 `prefs.personalAcpDefaultFor(cli)` |
| `pages/home_workspace/workspace/unbound_compose_body.dart:1617-1638` | select tuple 的 4 个 bool 换成 `Map<String, bool>` |
| `pages/home_workspace/workspace/workspace_session_actions.dart:891-897`、`acp_compose_permission.dart:203-209` | 4 个 `readPersonalAcpDefault` 收敛为 `Map<CliTool, bool> memberAcpSeeds` |

`SessionCreateRequest` 的 4 个 `seed*MemberAcp` 字段与 `stampMemberAcp` 的 4 个参数**保持不动**
（它们是调用方传入的数据管道，改动面 122 处、无身份判断收益）；`member_acp_stamp.dart:52-58`
的 `switch (cli)` 也保留——它是在调用方提供的 4 个值之间查表，不是按 CLI 身份决定行为，
真正的身份判断 `_memberAcpGates` 已经在用 `AcpCapability`。

### 3. opencode question tool env（`AcpCapability.agentStatusEnvironment`）

现状 `services/chat/launch/connect/acp_runtime_attach.dart:187-189`、`:424-429`
在调用点写 `agentStatus != null && cli == CliTool.opencode`。

接口新增（默认空实现）：

```dart
/// agent-status 插件在本 seat 落盘后，该 CLI 额外需要的 spawn env。
Map<String, String> get agentStatusEnvironment => const {};
```

`OpencodeAcpCapability` 覆写为 `{opencodeEnableQuestionToolEnvKey: 'true'}`；两个调用点改成

```dart
env = agentStatus == null ? env : {...env, ...cap.agentStatusEnvironment};
```

能力由 `CliToolRegistry.builtIn().capability<AcpCapability>(cli)` 取得，缺失时为空 map。

### 4. cursor hook 契约（`HookCapability`）

两处 cursor 特判都落在 hook 渲染契约上，一并归位：

```dart
abstract interface class HookCapability {
  /// 该 CLI 是否在 SessionStart 主动 push TeamBus 协议（决定 role addendum 变体）。
  bool get pushesBusProtocol => false;

  /// 该 CLI 的 SessionStart hook 期望的 stdout JSON 负载。
  Map<String, Object?> sessionStartStdoutPayload({required String additionalContext}) => {
        'hookSpecificOutput': {
          'hookEventName': 'SessionStart',
          'additionalContext': additionalContext,
        },
      };
}
```

- `CursorHookWriter` 覆写：`pushesBusProtocol => true`，
  payload 为 `{'additional_context': additionalContext}`（与现 `BusAwarenessPrompt.sessionStartStdout` 逐字节一致）。
- `services/chat/team_bus/bus_awareness_prompt.dart`：删除 `sessionStartStdout(cli:)`；
  `sessionStartScript` 改为接收 payload map。`additionalContext(pushDelivery:)` 保留（值来自能力）。
- `services/cli/registry/config_profile/hook_seat_context_completer.dart:70-97`：
  `busAwarenessHooks({member, cli})`，`pushDelivery` 与 payload 均由
  `registry.capability<HookCapability>(cli)` 提供，删除 `pushDelivery` 入参。
- `services/resource/providers/bus_awareness_hook_contribution_provider.dart:28`：删除 `cli == CliTool.cursor`。
- 同步改动调用方：`services/cli/cursor/provider/cursor_home_provisioner.dart:338`、
  `test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart`、
  `test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart`。

### 5. flashskyai provider config 归一化（`ProviderCapability.normalizeConfig`）

现状 `cubits/app_provider_cubit.dart:781-812` 的 `if (cli != CliTool.flashskyai) return config;`。

```dart
/// 持久化前的 per-CLI 配置修补；默认原样返回。
Map<String, Object?> normalizeConfig({
  required String providerId,
  required Map<String, Object?> config,
}) => config;
```

- `_normalizeFlashskyaiModelsProvider` 整体迁入 `services/cli/flashskyai/capabilities/provider.dart`（私有方法）。
- cubit 的 `_normalizedConfigForCli` 改为 registry 查询（该文件已有 3 处同样写法）。
- `pages/llm_config/llm_providers_tab_content.dart:121` 的 flashskyai 判断换成
  `capability<ProviderCapability>(selected.cli)?.hasModelPanel == true`
  （`hasModelPanel` 仅 flashskyai 为 true，已在 `:215` 使用同一判断）。

## 测试

新增/调整：

1. `test/services/cli/registry/capabilities/cli_transport_capability_test.dart`
   —— 断言 `canChooseTransport` 为 true 的集合等于 {claude, cursor, codex, opencode}，
   gemini / codebuddy 为 false；并断言它等价于 `supports(pty) && supports(acp)`。
2. `test/models/session_preferences_test.dart`：map 往返 + 旧键迁移（4 个旧键 → map）+ 缺省 true。
3. `test/cubits/session_preferences_cubit_test.dart`：改用 `personalAcpDefaultFor`。
4. opencode env：断言 `agentStatusEnvironment` 含 `OPENCODE_ENABLE_QUESTION_TOOL`，其余 CLI 为空。
5. cursor hook：断言 `pushesBusProtocol` 为 true 且 payload 形状；`ClaudeFamilyHookWriter` 走默认形状。
6. flashskyai normalize：归一化用例从 cubit 测试迁到 provider capability 测试；cubit 断言仍保留一条端到端。
7. 更新 `hook_seat_context_completer_test`、`claude_family_hook_writer_test`、`unbound_compose_*_acp_test` 的构造签名。

验证命令：

```
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart            # 全量，最后一次
```

## 风险

- `SessionPreferences` JSON 形状变化：旧键必须能读（升级迁移），新键只写新形状。
- `stampedLandingMembers` 签名从 4 个 bool 变为 map，涉及其测试；行为等价。
- cursor `sessionStartStdoutPayload` 必须与现输出逐字节相同，否则 hook 脚本内容变化会让
  `hook seat context` 相关测试/去重行为漂移。
- `AcpCapability` 新增带默认实现的 getter：7 个实现的 interface 兼容（无需逐个改）。
- 删除 `showsPersonalAcpSwitch` 会同时改动 settings 卡片与 2 个既有测试，行为等价；
  ACP-only CLI 仍由 `launchesAcpOnly` 在 session create 处强制 ACP，不受开关影响。
- 若将来出现「两种传输都支持但不给开关」的 CLI，需要重新引入显式覆盖字段（本 spec 不预设）。

## 实施结果（2026-11-01）

已按本 spec 实现：

- 个人 ACP 开关：`CliTransportCapability.canChooseTransport`，`showsPersonalAcpSwitch` 已删除。
- 个人 ACP 默认值：`SessionPreferences.personalAcpDefaults`（旧 JSON 键可读，只写新键）。
- opencode question tool env：`AcpCapability.agentStatusEnvironment`。
- cursor bus-awareness：`HookCapability.pushesBusProtocol` / `sessionStartStdoutPayload`，默认实现放在
  `BusProtocolHookDefaults` mixin。
- flashskyai 配置归一化：`ProviderCapability.normalizeConfig`，默认实现在 `CatalogModelCapability`。

Dart 语义修正：`abstract interface class` 的默认方法体不会被 `implements` 继承，因此两处「默认实现」
改放在 mixin / base class 上，接口本身声明抽象成员。
