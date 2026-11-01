# CLI 身份判断收口 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把个人 ACP 白名单/默认值、opencode question-tool env、cursor bus-awareness hook 契约、flashskyai provider 配置归一化从 `if (cli == CliTool.X)` 改为能力查询，行为不变。

**Architecture:** 每项都落到既有能力接口上（`CliTransportCapability` / `AcpCapability` / `HookCapability` / `ProviderCapability`），调用点只做 `registry.capability<T>(cli)` 查询；新增 CLI 时无需回头改这些文件。

**Tech Stack:** Flutter/Dart，`flutter_bloc`，`package:test`，`dart run tool/run_tests.dart`。

## Global Constraints

- 禁止直接 `flutter test`；一律 `cd client && dart run tool/run_tests.dart <paths>`。
- 内层循环 `flutter analyze`，外层全量只在最后跑一次。
- 不改 l10n 的 `.arb`；不改 `SessionCreateRequest` / `stampMemberAcp` 的 4 个 seed 参数。
- 每一步改完必须 `flutter analyze` 通过再进下一步。
- 不新增第三方依赖。

---

### Task 1: 个人 ACP 开关改由 transport 派生

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/cli_transport_capability.dart:44-46`
- Modify: `client/lib/services/cli/registry/capabilities/acp_settings_capability.dart:4-27`
- Modify: `client/lib/services/cli/codebuddy/codebuddy_tool.dart:69-72`
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart:17-27`
- Modify: `client/lib/pages/config/cli_readiness_card.dart:106-109,586-587,617`
- Modify: `client/test/services/cli/acp_settings_capability_test.dart:16,30`
- Modify: `client/test/services/cli/codebuddy/codebuddy_registry_test.dart:52`
- Test: `client/test/services/cli/registry/capabilities/cli_transport_capability_test.dart`（新建）
- Modify: `docs/cli-architecture.md:267`

**Interfaces:**
- Produces: `CliTransportCapability.canChooseTransport -> bool`；`AcpSettingsCapability` 只剩 `usesSeparateAdapter` / `adapterExecutableName` / `adapterInstaller`。

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/cli/registry/capabilities/cli_transport_capability_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('only dual-transport CLIs let the user choose', () {
    final choosable = {
      for (final cli in CliTool.values)
        if (registry.capability<CliTransportCapability>(cli)!.canChooseTransport)
          cli,
    };
    expect(choosable, {
      CliTool.claude,
      CliTool.cursor,
      CliTool.codex,
      CliTool.opencode,
    });
  });

  test('canChooseTransport equals pty && acp', () {
    for (final cli in CliTool.values) {
      final transport = registry.capability<CliTransportCapability>(cli)!;
      expect(
        transport.canChooseTransport,
        transport.supports(CliTransport.pty) &&
            transport.supports(CliTransport.acp),
        reason: 'cli=$cli',
      );
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/cli_transport_capability_test.dart`
Expected: 编译失败 — `canChooseTransport` 未定义。

- [ ] **Step 3: 实现 transport getter**

`cli_transport_capability.dart` 在 `acpOnly` 之后追加：

```dart
  /// True when the user can pick between PTY and ACP: both transports are
  /// declared. ACP-only CLIs have nothing to choose, so no personal switch.
  bool get canChooseTransport =>
      supports(CliTransport.pty) && supports(CliTransport.acp);
```

- [ ] **Step 4: 删除 `showsPersonalAcpSwitch`**

`acp_settings_capability.dart` 改为：

```dart
abstract interface class AcpSettingsCapability implements CliCapability {
  bool get usesSeparateAdapter;
  String? get adapterExecutableName;
  NpmInstallerCapability? get adapterInstaller;
}

final class DefaultAcpSettingsCapability implements AcpSettingsCapability {
  const DefaultAcpSettingsCapability({
    this.usesSeparateAdapter = false,
    this.adapterExecutableName,
    this.adapterInstaller,
  });

  @override
  final bool usesSeparateAdapter;
  @override
  final String? adapterExecutableName;
  @override
  final NpmInstallerCapability? adapterInstaller;
}
```

`codebuddy_tool.dart:69-72` 删除 `showsPersonalAcpSwitch: false,` 一行（保留 `usesSeparateAdapter: false`）。

- [ ] **Step 5: 调用点改读 transport**

`claude_acp_launch_switch.dart` 的 `_personalAcpAllowed`：

```dart
bool _personalAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (!isPersonal || cli == null) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  return CliToolRegistry.builtIn()
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
}
```

`cli_readiness_card.dart` 在 `_separateAdapter` 后新增：

```dart
  bool get _canChooseTransport =>
      _registry.capability<CliTransportCapability>(widget.cli)
          ?.canChooseTransport ??
      false;
```

把 `:587` 的 `_settings?.showsPersonalAcpSwitch == true` 与 `:617` 的
`_settings?.showsPersonalAcpSwitch == true` 都替换为 `_canChooseTransport`，
并补 import `../../services/cli/registry/capabilities/cli_transport_capability.dart`。

- [ ] **Step 6: 更新既有测试**

`test/services/cli/acp_settings_capability_test.dart`：删除第 16 行 `expect(claude.showsPersonalAcpSwitch, isTrue);` 与第 30 行的同类断言。
`test/services/cli/codebuddy/codebuddy_registry_test.dart:52` 删除该断言。

- [ ] **Step 7: 跑测试与 analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/capabilities/cli_transport_capability_test.dart test/services/cli/acp_settings_capability_test.dart test/services/cli/codebuddy/codebuddy_registry_test.dart`
Expected: PASS
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 8: 更新文档**

`docs/cli-architecture.md:267` 改为：
`| AcpSettingsCapability | Settings extras: usesSeparateAdapter / adapterExecutableName / adapterInstaller。个人 ACP 开关不在这里——由 CliTransportCapability.canChooseTransport（同时声明 pty+acp）派生 |`

- [ ] **Step 9: 提交**

```bash
git add -A client/lib client/test docs/cli-architecture.md
git commit -m "refactor(cli): derive personal ACP switch from transport capability"
```

---

### Task 2: 个人 ACP 默认值改为按 CLI 键的 map

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart:198-219,387-401`
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart:45-62`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart:1617-1638`
- Test: `client/test/models/session_preferences_test.dart:112-170`
- Test: `client/test/cubits/session_preferences_cubit_test.dart:118-170,499`
- Test: `client/test/pages/home_workspace/workspace/unbound_compose_*_acp_test.dart`（构造签名）

**Interfaces:**
- Consumes: 无
- Produces: `SessionPreferences.personalAcpDefaults -> Map<String,bool>`、
  `SessionPreferences.personalAcpDefaultFor(CliTool) -> bool`、
  `SessionPreferences.withPersonalAcpDefault(CliTool, bool) -> SessionPreferences`；
  `SessionPreferencesCubit.personalAcpDefaultFor(CliTool)`、
  `SessionPreferencesCubit.setPersonalAcpDefaultFor(CliTool, bool)`

- [ ] **Step 1: 写失败测试（模型层）**

`test/models/session_preferences_test.dart` 中把 112-170 的四个字段测试替换为：

```dart
    test('personalAcpDefaults defaults true and round-trips', () {
      final defaults = SessionPreferences();
      expect(defaults.personalAcpDefaultFor(CliTool.claude), isTrue);
      expect(defaults.personalAcpDefaultFor(CliTool.gemini), isTrue);
      expect(
        SessionPreferences.fromJson(const {}).personalAcpDefaultFor(
          CliTool.codex,
        ),
        isTrue,
      );

      final off = defaults.withPersonalAcpDefault(CliTool.cursor, false);
      expect(off.personalAcpDefaultFor(CliTool.cursor), isFalse);
      expect(off.personalAcpDefaultFor(CliTool.claude), isTrue);
      expect(off.toJson()['personalAcpDefaults'], {
        CliTool.cursor.value: false,
      });
      expect(
        SessionPreferences.fromJson(off.toJson()).personalAcpDefaultFor(
          CliTool.cursor,
        ),
        isFalse,
      );
    });

    test('legacy per-CLI keys migrate into personalAcpDefaults', () {
      final migrated = SessionPreferences.fromJson(const {
        'claudePersonalAcpDefault': false,
        'codexPersonalAcpDefault': true,
        'cursorPersonalAcpDefault': false,
        'opencodePersonalAcpDefault': true,
      });
      expect(migrated.personalAcpDefaultFor(CliTool.claude), isFalse);
      expect(migrated.personalAcpDefaultFor(CliTool.codex), isTrue);
      expect(migrated.personalAcpDefaultFor(CliTool.cursor), isFalse);
      expect(migrated.personalAcpDefaultFor(CliTool.opencode), isTrue);
      expect(migrated.toJson().containsKey('claudePersonalAcpDefault'), isFalse);
    });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart`
Expected: 编译失败 — `personalAcpDefaultFor` / `withPersonalAcpDefault` 未定义。

- [ ] **Step 3: 改模型**

`session_preferences.dart`：

1. 顶部 `import 'team_config.dart';`
2. 构造参数：删除 4 个 bool，新增 `Map<String, bool> personalAcpDefaults = const {}`，
   初始化列表加 `personalAcpDefaults = Map.unmodifiable(personalAcpDefaults),`
3. 字段：删除 4 个 bool，新增

```dart
  /// 个人 ACP 默认值，key 为 [CliTool.value]。缺省 true。
  final Map<String, bool> personalAcpDefaults;
```

4. `fromJson`：删除 4 行旧键读取，改为 `personalAcpDefaults: _personalAcpDefaultsFromJson(json),`
5. `copyWith`：删除 4 个 bool 参数，新增 `Map<String, bool>? personalAcpDefaults,`，
   并传 `personalAcpDefaults: personalAcpDefaults ?? this.personalAcpDefaults,`
6. `toJson`：删除 4 行旧键，新增 `'personalAcpDefaults': personalAcpDefaults,`
7. 新增方法：

```dart
  bool personalAcpDefaultFor(CliTool cli) =>
      personalAcpDefaults[cli.value] ?? true;

  SessionPreferences withPersonalAcpDefault(CliTool cli, bool value) =>
      copyWith(personalAcpDefaults: {...personalAcpDefaults, cli.value: value});
```

8. 文件末尾新增迁移解析：

```dart
  /// 旧版把四个 CLI 的默认值写成独立 bool 键。
  static const Map<String, String> _legacyPersonalAcpKeys = {
    'claude': 'claudePersonalAcpDefault',
    'codex': 'codexPersonalAcpDefault',
    'cursor': 'cursorPersonalAcpDefault',
    'opencode': 'opencodePersonalAcpDefault',
  };

  static Map<String, bool> _personalAcpDefaultsFromJson(
    Map<String, Object?> json,
  ) {
    final raw = json['personalAcpDefaults'];
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is bool)
            entry.key as String: entry.value as bool,
      };
    }
    return {
      for (final entry in _legacyPersonalAcpKeys.entries)
        if (json[entry.value] case final bool value) entry.key: value,
    };
  }
```

- [ ] **Step 4: 跑模型测试**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart`
Expected: PASS

- [ ] **Step 5: 改 cubit**

`session_preferences_cubit.dart:198-219` 替换为：

```dart
  bool personalAcpDefaultFor(CliTool cli) =>
      state.preferences.personalAcpDefaultFor(cli);

  Future<void> setPersonalAcpDefaultFor(CliTool cli, bool value) =>
      _save(state.preferences.withPersonalAcpDefault(cli, value));
```

`:387-401` 四个 setter 改为委托：

```dart
  Future<void> setClaudePersonalAcpDefault(bool value) =>
      setPersonalAcpDefaultFor(CliTool.claude, value);

  Future<void> setCodexPersonalAcpDefault(bool value) =>
      setPersonalAcpDefaultFor(CliTool.codex, value);

  Future<void> setCursorPersonalAcpDefault(bool value) =>
      setPersonalAcpDefaultFor(CliTool.cursor, value);

  Future<void> setOpencodePersonalAcpDefault(bool value) =>
      setPersonalAcpDefaultFor(CliTool.opencode, value);
```

- [ ] **Step 6: 改读取点**

`claude_acp_launch_switch.dart` 的 `readPersonalAcpDefault`：

```dart
bool readPersonalAcpDefault(BuildContext context, CliTool? cli) {
  if (cli == null) return false;
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .personalAcpDefaultFor(cli);
  } on ProviderNotFoundException {
    return CliToolRegistry.builtIn()
            .capability<CliTransportCapability>(cli)
            ?.defaultTransport ==
        CliTransport.acp;
  }
}
```

`unbound_compose_body.dart:1617-1638` 的 select 元组改为：

```dart
    context.select<
      SessionPreferencesCubit,
      (
        int,
        Map<String, String>,
        Map<String, String>,
        Map<String, bool>,
      )
    >(
      (c) => (
        c.state.locatedExecutablesRevision,
        c.state.preferences.cliExecutablePaths,
        c.state.preferences.acpAdapterPaths,
        c.state.preferences.personalAcpDefaults,
      ),
    );
```

- [ ] **Step 7: 更新测试**

- `test/cubits/session_preferences_cubit_test.dart`：`preferences.claudePersonalAcpDefault` 等改为
  `preferences.personalAcpDefaultFor(CliTool.claude)`（同文件 118-170、499 行）。
- `test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart:100-101`、
  `unbound_compose_cursor_acp_test.dart:100-101,173-223`、
  `unbound_compose_remote_acp_readiness_test.dart:171`：把
  `SessionPreferences(claudePersonalAcpDefault: x, codexPersonalAcpDefault: y)` 改为
  `SessionPreferences(personalAcpDefaults: {CliTool.claude.value: x, CliTool.codex.value: y})`。

- [ ] **Step 8: analyze + 窄测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart test/pages/home_workspace/workspace/unbound_compose_cursor_acp_test.dart`
Expected: PASS

- [ ] **Step 9: 提交**

```bash
git add -A client/lib client/test
git commit -m "refactor(prefs): store personal ACP defaults in a CLI-keyed map"
```

---

### Task 3: opencode question tool env 归位 AcpCapability

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/acp_capability.dart:44-50`
- Modify: `client/lib/services/cli/opencode/capabilities/acp.dart:60-73`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart:18-20,187-189,424-429`
- Test: `client/test/services/cli/opencode/opencode_acp_capability_test.dart`（新建，若目录已有同名测试则追加用例）

**Interfaces:**
- Produces: `AcpCapability.agentStatusEnvironment -> Map<String,String>`（默认 `const {}`）

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/cli/opencode/opencode_acp_capability_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/acp.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('only opencode needs extra env once agent status is staged', () {
    expect(
      const OpencodeAcpCapability().agentStatusEnvironment,
      {opencodeEnableQuestionToolEnvKey: 'true'},
    );
    for (final cli in CliTool.values) {
      if (cli == CliTool.opencode) continue;
      final acp = registry.capability<AcpCapability>(cli);
      expect(acp?.agentStatusEnvironment ?? const {}, isEmpty, reason: '$cli');
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/opencode/opencode_acp_capability_test.dart`
Expected: 编译失败 — `agentStatusEnvironment` 未定义。

- [ ] **Step 3: 加接口默认实现**

`acp_capability.dart` 在 `forwardSessionNewMcpServers` 之后：

```dart
  /// Extra spawn env needed once the agent-status plugin is staged for this
  /// seat. Default empty; CLIs that must enable a tool to answer agent-status
  /// questions override it. Callers gate on "agent status staged", never on
  /// the CLI identity.
  Map<String, String> get agentStatusEnvironment => const {};
```

- [ ] **Step 4: opencode 覆写**

`opencode/capabilities/acp.dart` 的 `OpencodeAcpCapability` 内新增：

```dart
  @override
  Map<String, String> get agentStatusEnvironment => const {
    opencodeEnableQuestionToolEnvKey: 'true',
  };
```

并把 `buildEnvironment` 里的注释改为：

```dart
    // Question tool env is declared by [agentStatusEnvironment]; the ACP
    // attach path merges it only when the agent-status plugin is staged, so an
    // unanswered `Question.ask` can never hang the turn.
```

- [ ] **Step 5: 调用点改为能力查询**

`acp_runtime_attach.dart`：
- 删除 import `'../../../cli/opencode/capabilities/acp.dart' show opencodeEnableQuestionToolEnvKey;`
- 新增 `import '../../../cli/registry/capabilities/acp_capability.dart';`
- `:187-189` 替换为：

```dart
      env = _withAgentStatusEnvironment(cli, agentStatus != null, env);
```

- `:424-429` 替换为：

```dart
      baseEnv: _withAgentStatusEnvironment(
        cli,
        agentStatus != null,
        staged.env,
      ),
```

- 在类内新增：

```dart
  Map<String, String> _withAgentStatusEnvironment(
    CliTool cli,
    bool agentStatusStaged,
    Map<String, String> env,
  ) {
    if (!agentStatusStaged) return env;
    final cap = CliToolRegistry.builtIn().capability<AcpCapability>(cli);
    final extra = cap?.agentStatusEnvironment ?? const <String, String>{};
    return extra.isEmpty ? env : {...env, ...extra};
  }
```

- [ ] **Step 6: 跑测试 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/opencode/opencode_acp_capability_test.dart`
Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS / No issues found.

- [ ] **Step 7: 提交**

```bash
git add -A client/lib client/test
git commit -m "refactor(acp): let AcpCapability declare agent-status env"
```

---

### Task 4: cursor bus-awareness hook 契约归位 HookCapability

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/hook_capability.dart:47-60`
- Modify: `client/lib/services/cli/cursor/provider/cursor_hook_writer.dart:15-40`
- Modify: `client/lib/services/chat/team_bus/bus_awareness_prompt.dart:39-66`
- Modify: `client/lib/services/cli/registry/config_profile/hook_seat_context_completer.dart:68-97`
- Modify: `client/lib/services/resource/providers/bus_awareness_hook_contribution_provider.dart:25-29`
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart:336-344`
- Test: `client/test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart:39-78`
- Test: `client/test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart:125-133`
- Test: `client/test/services/cli/cursor/cursor_hook_payload_test.dart`（新建）

**Interfaces:**
- Produces: `HookCapability.pushesBusProtocol -> bool`、
  `HookCapability.sessionStartStdoutPayload({required String additionalContext}) -> Map<String,Object?>`
- `HookSeatContextCompleter.busAwarenessHooks({required TeamMemberConfig member, required CliTool cli})`
- `BusAwarenessPrompt.sessionStartScript({required Map<String,Object?> payload})`

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/cli/cursor/cursor_hook_payload_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('cursor pushes the bus protocol with a flat stdout payload', () {
    final cap = registry.capability<HookCapability>(CliTool.cursor)!;
    expect(cap.pushesBusProtocol, isTrue);
    expect(
      jsonEncode(cap.sessionStartStdoutPayload(additionalContext: 'ctx')),
      '{"additional_context":"ctx"}',
    );
  });

  test('other hook writers use the claude-family payload', () {
    final payload = const CursorHookWriter().sessionStartStdoutPayload(
      additionalContext: 'ctx',
    );
    expect(payload, isNotEmpty);
    final claude = registry.capability<HookCapability>(CliTool.claude)!;
    expect(claude.pushesBusProtocol, isFalse);
    expect(
      jsonEncode(claude.sessionStartStdoutPayload(additionalContext: 'ctx')),
      '{"hookSpecificOutput":{"hookEventName":"SessionStart",'
      '"additionalContext":"ctx"}}',
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_hook_payload_test.dart`
Expected: 编译失败 — `pushesBusProtocol` / `sessionStartStdoutPayload` 未定义。

- [ ] **Step 3: 接口加默认实现**

`hook_capability.dart` 在 `supportsEvent` 之后：

```dart
  /// 该 CLI 是否在 SessionStart 主动 push TeamBus 协议（影响 role addendum）。
  bool get pushesBusProtocol => false;

  /// 该 CLI 的 SessionStart hook 期望的 stdout JSON 负载。
  Map<String, Object?> sessionStartStdoutPayload({
    required String additionalContext,
  }) => {
    'hookSpecificOutput': {
      'hookEventName': 'SessionStart',
      'additionalContext': additionalContext,
    },
  };
```

- [ ] **Step 4: cursor 覆写**

`cursor_hook_writer.dart` 的 `CursorHookWriter` 内新增：

```dart
  @override
  bool get pushesBusProtocol => true;

  @override
  Map<String, Object?> sessionStartStdoutPayload({
    required String additionalContext,
  }) => {'additional_context': additionalContext};
```

- [ ] **Step 5: 改 BusAwarenessPrompt**

`bus_awareness_prompt.dart` 删除 `sessionStartStdout(cli:)`，`sessionStartScript` 改为：

```dart
  static String sessionStartScript({required Map<String, Object?> payload}) {
    final json = jsonEncode(payload);
    return '#!/usr/bin/env bash\n'
        '# TeamPilot bus awareness — do not edit.\n'
        "cat <<'$_jsonDelimiter'\n"
        '$json\n'
        '$_jsonDelimiter\n';
  }
```

- [ ] **Step 6: completer 改为能力驱动**

`hook_seat_context_completer.dart`：

```dart
  List<HookEntry> busAwarenessHooks({
    required TeamMemberConfig member,
    required CliTool cli,
  }) {
    final hook = CliToolRegistry.builtIn().capability<HookCapability>(cli);
    if (hook == null || !hook.supportsEvent(HookEvent.sessionStart)) {
      return const [];
    }
    final context = BusAwarenessPrompt.additionalContext(
      member: member,
      pushDelivery: hook.pushesBusProtocol,
    );
    return [
      HookEntry(
        id: 'teampilot-bus-awareness-sessionStart',
        source: HookSource.managed,
        event: HookEvent.sessionStart,
        action: CommandHookAction.script(
          fileName: 'hook.sh',
          scriptContent: BusAwarenessPrompt.sessionStartScript(
            payload: hook.sessionStartStdoutPayload(
              additionalContext: context,
            ),
          ),
        ),
        timeout: const Duration(seconds: 5),
      ),
    ];
  }
```

补 import：`../capabilities/hook_capability.dart` 与 `../cli_tool_registry.dart`。
`models/hook_event.dart` 的 import 保留（`_parseEventName` 仍在用 `HookEventCapability.nativeEvent`）。

- [ ] **Step 7: 调用点去掉身份判断**

`bus_awareness_hook_contribution_provider.dart`：删除 `pushDelivery: context.cli == CliTool.cursor,` 一行，并删除 `models/team_config.dart` 中不再使用的 `CliTool` 引用（若该 import 仅为此行）。

`cursor_home_provisioner.dart:338` 删除 `pushDelivery: true,`。

- [ ] **Step 8: 更新既有测试**

- `hook_seat_context_completer_test.dart`：三处 `busAwarenessHooks(member: ..., cli: ..., pushDelivery: ...)` 删除 `pushDelivery` 参数；
  期望脚本改为 `BusAwarenessPrompt.sessionStartScript(payload: <claude payload map>)`，用
  `CliToolRegistry.builtIn().capability<HookCapability>(CliTool.claude)!.sessionStartStdoutPayload(additionalContext: ...)` 生成。
- `claude_family_hook_writer_test.dart:127` 同上删除 `pushDelivery` 参数。

- [ ] **Step 9: analyze + 窄测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_hook_payload_test.dart test/services/cli/registry/config_profile/hook_seat_context_completer_test.dart test/services/cli/registry/config_profile/claude_family_hook_writer_test.dart`
Expected: PASS

- [ ] **Step 10: 提交**

```bash
git add -A client/lib client/test
git commit -m "refactor(hooks): move cursor bus-awareness contract into HookCapability"
```

---

### Task 5: flashskyai provider 配置归一化归位 ProviderCapability

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/provider_capability.dart:622-634`
- Modify: `client/lib/services/cli/flashskyai/capabilities/provider.dart`（在 ProviderFormCapability 段内加方法）
- Modify: `client/lib/cubits/app_provider_cubit.dart:781-812`
- Modify: `client/lib/pages/llm_config/llm_providers_tab_content.dart:120-129`
- Test: `client/test/services/cli/flashskyai/flashskyai_provider_normalize_test.dart`（新建）

**Interfaces:**
- Produces: `ProviderCapability.normalizeConfig({required String providerId, required Map<String,Object?> config}) -> Map<String,Object?>`

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/cli/flashskyai/flashskyai_provider_normalize_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('flashskyai stamps the provider id into every model entry', () {
    final cap = registry.capability<ProviderCapability>(CliTool.flashskyai)!;
    final normalized = cap.normalizeConfig(
      providerId: 'p1',
      config: {
        'models': {
          'm1': {'name': 'm1'},
          'm2': 'raw',
        },
      },
    );
    expect(normalized['models'], {
      'm1': {'name': 'm1', 'provider': 'p1'},
      'm2': 'raw',
    });
  });

  test('other CLIs leave config untouched', () {
    for (final cli in CliTool.values) {
      if (cli == CliTool.flashskyai) continue;
      final cap = registry.capability<ProviderCapability>(cli)!;
      const config = {'a': 1};
      expect(
        identical(cap.normalizeConfig(providerId: 'p', config: config), config),
        isTrue,
        reason: '$cli',
      );
    }
  });

  test('FlashskyaiProviderCapability keeps the same behavior', () {
    const cap = FlashskyaiProviderCapability();
    expect(
      cap.normalizeConfig(
        providerId: 'x',
        config: {
          'models': {
            'm': {'provider': 'old'},
          },
        },
      ),
      {
        'models': {
          'm': {'provider': 'x'},
        },
      },
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/flashskyai/flashskyai_provider_normalize_test.dart`
Expected: 编译失败 — `normalizeConfig` 未定义。

- [ ] **Step 3: 接口加默认实现**

`provider_capability.dart` 在 `configForCliSwitch()` 之后：

```dart
  /// 持久化前的 per-CLI 配置修补（如把 provider id 写进模型条目）。
  /// 默认原样返回。
  Map<String, Object?> normalizeConfig({
    required String providerId,
    required Map<String, Object?> config,
  }) => config;
```

- [ ] **Step 4: flashskyai 覆写**

`flashskyai/capabilities/provider.dart` 的 `FlashskyaiProviderCapability` 内新增：

```dart
  @override
  Map<String, Object?> normalizeConfig({
    required String providerId,
    required Map<String, Object?> config,
  }) {
    final rawModels = config['models'];
    if (rawModels is! Map) return config;
    final normalizedModels = <String, Object?>{};
    for (final entry in rawModels.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        normalizedModels[key] = {
          ...Map<String, Object?>.from(value),
          'provider': providerId,
        };
      } else {
        normalizedModels[key] = value;
      }
    }
    return {...config, 'models': normalizedModels};
  }
```

- [ ] **Step 5: cubit 改查能力**

`app_provider_cubit.dart`：删除 `_normalizedConfigForCli` 与 `_normalizeFlashskyaiModelsProvider`，
调用点 `:329-333` 改为：

```dart
    final normalizedConfig =
        CliToolRegistry.builtIn()
            .capability<ProviderCapability>(cli)
            ?.normalizeConfig(providerId: trimmedId, config: provider.config) ??
        provider.config;
```

- [ ] **Step 6: llm tab 改查能力**

`llm_providers_tab_content.dart:121`：

```dart
              onShowModels: (selected) {
                final canShowModels =
                    CliToolRegistry.builtIn()
                        .capability<ProviderCapability>(selected.cli)
                        ?.hasModelPanel ==
                    true;
                if (!canShowModels) return;
```

- [ ] **Step 7: analyze + 窄测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `cd client && dart run tool/run_tests.dart test/services/cli/flashskyai/flashskyai_provider_normalize_test.dart`
Expected: PASS

- [ ] **Step 8: 提交**

```bash
git add -A client/lib client/test
git commit -m "refactor(provider): move flashskyai config normalization into ProviderCapability"
```

---

### Task 6: 全量验证与文档收尾

**Files:**
- Modify: `docs/superpowers/specs/2026-11-01-cli-identity-branches-design.md`（勾掉已完成项，记录 `member_acp_stamp` 的保留决定）

- [ ] **Step 1: 全量 analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 2: 全量测试（最后一次）**

Run: `cd client && dart run tool/run_tests.dart`
Expected: All tests passed.

- [ ] **Step 3: 残留检查**

Run: `cd /home/hhoa/git/hhoa/teampilot && grep -rn "CliTool.cursor\|CliTool.opencode" client/lib/services/resource client/lib/services/chat/launch/connect client/lib/cubits/app_provider_cubit.dart`
Expected: 无 `== CliTool.x` 形式的行为分支（常量表 / 默认值不算）。

- [ ] **Step 4: 提交**

```bash
git add -A docs client
git commit -m "docs(cli): record CLI identity branch cleanup"
```

---

## 执行记录（2026-11-01）

- Task 1–5 已实现；`flutter analyze` 无 error（仅剩仓库既有的 info/warning）。
- 计划与实际的偏差：
  - `AcpCapability.agentStatusEnvironment` 与 `HookCapability` 的两个成员无法靠「接口默认实现」被
    `implements` 继承（Dart 语义），因此改为：接口声明抽象成员 + `CatalogModelCapability` /
    `BusProtocolHookDefaults` mixin 提供默认实现；6 个 ACP 实现各补一行空 map。
  - `HookCapability` 默认实现放在新 mixin `BusProtocolHookDefaults`（6 个 writer `with` 它，
    `CursorHookWriter` 覆写两项）。
  - `member_acp_stamp` 的 seed switch 保留（见 spec，属数据查表而非身份判断）。
- 新增测试：`cli_transport_capability_test.dart`、`cursor_hook_payload_test.dart`、
  `flashskyai_provider_normalize_test.dart`，以及 `opencode_acp_capability_test.dart` 中的
  `agentStatusEnvironment` 用例。
