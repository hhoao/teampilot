# OpenCode ACP Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let new personal OpenCode sessions and new mixed OpenCode seats launch as terminal-less ACP chat (`opencode acp`) behind `opencodePersonalAcpDefault` (default on), without replacing PTY OpenCode.

**Architecture:** Reuse the existing ACP stack (`acpd` + `AcpProcessTransport` + `AcpSessionRuntime`). `OpencodeCliTool` declares `OpencodeAcpCapability` (`[opencode, acp]`, preserve `baseEnv` `OPENCODE_*` keys, skip `authenticate`, omit `session/new` MCP). Preference seeds new personal launches and mixed seats; `AppSession.acp` / `SessionMemberBinding.acp` are the durable facts. Prompt `auth_required` maps through a shared translator sentinel to the existing not-logged-in copy.

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, existing ACP chat cubit / transcript, OpenCode session-home env from `prepareSimpleConnect` / `prepareTeamConnect`.

**Spec:** `docs/superpowers/specs/2026-10-13-opencode-acp-session-design.md`

## Global Constraints

- Desktop-local only. No `SshExecTransport`, no Android ACP (disable the switch when `Platform.isAndroid`).
- No `CliTool.opencodeAcp`. Do not replace PTY OpenCode. Native teams stay PTY (`createSession` already forces session `acp = false`).
- Argv is `[opencode, acp]`. Never probe `--acp`. No adapter installer. No `--login`.
- `authenticateMethodId` is null. Do not send `opencode-login`.
- `forwardSessionNewMcpServers` is false. MCP (including mixed teammate-bus) stays in staged `opencode.json`.
- `buildEnvironment` must **preserve** `OPENCODE_CONFIG_DIR` / `OPENCODE_DB` / `OPENCODE_AUTH_CONTENT` / `OPENCODE_CLI_CONFIG_CONTENT` from `baseEnv`. Never invent `HOME` from `sessionToolDir`.
- Handshake / spawn / attach failure must not fall back to PTY.
- No `if (cli == opencode)` in `services/acp/`, `AcpSessionRuntime`, `AcpChatRuntimeCubit`, or `app_shell.dart` strings. OpenCode-only behavior lives in `services/cli/opencode/`. Extending existing allow-lists (`resolveLaunchAcp`, `readPersonalAcpDefault`, `_requestedMemberAcpSeed`, `_buildCliRow`) is required.
- Do not call `session/load` / `session/resume` / `session/fork`. Do not persist OpenCode ACP session ids. Do not advertise `fs` / `terminal` / `auth.terminal` / `elicitation.form`.
- User copy → `app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- After arb edits, `cd client && flutter gen-l10n` before tests that read new getters.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_preferences.dart` | `opencodePersonalAcpDefault` (default true) |
| `client/lib/cubits/session_preferences_cubit.dart` | setter |
| `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart` | Allow OpenCode in `resolveLaunchAcp`; `readPersonalAcpDefault` branch |
| `client/lib/services/cli/opencode/capabilities/acp.dart` | translator + capability |
| `client/lib/services/cli/opencode/opencode_tool.dart` | register capability |
| `client/lib/services/acp/acp_agent_translator.dart` | `acpStopAuthRequired` sentinel |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | map sentinel → `notLoggedIn` |
| `client/lib/services/chat/launch/session/member_acp_stamp.dart` | `seedOpencodeMemberAcp` |
| `client/lib/services/chat/session/session_create_request.dart` | seed field |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | thread seed + comment |
| `client/lib/repositories/session_repository.dart` | thread seed into `stampMemberAcp` |
| `client/lib/services/chat/launch/session/session_launch_coordinator.dart` | thread seed |
| `client/lib/services/chat/session/session_data_store.dart` | thread seed |
| `client/lib/services/catalog/workspace_catalog.dart` | thread seed |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | OpenCode ACP copy |
| `client/lib/pages/config/cli_config_section.dart` | OpenCode settings switch |
| `client/lib/utils/ui/app_keys.dart` | `opencodePersonalAcpSwitch` |
| `client/lib/services/acp/acp_frame_logger.dart` | redact `OPENCODE_AUTH_CONTENT` |
| `docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md` | first-wave line now includes OpenCode |

Do **not** modify `built_in_cli_tools.dart` unless `OpencodeCliTool` stops default-constructing the capability. Cursor already registers ACP via the tool constructor default.

---

### Task 1: Preference + personal launch gate

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (comment on `buildWorkspaceConversationCreateRequest` only)
- Test: `client/test/models/session_preferences_test.dart`
- Test: `client/test/cubits/session_preferences_cubit_test.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `session_preferences_test.dart` next to the Cursor case:

```dart
test('opencodePersonalAcpDefault defaults true and round-trips', () {
  expect(SessionPreferences().opencodePersonalAcpDefault, isTrue);
  expect(
    SessionPreferences.fromJson(const {}).opencodePersonalAcpDefault,
    isTrue,
  );
  final off = SessionPreferences(opencodePersonalAcpDefault: false);
  expect(off.toJson()['opencodePersonalAcpDefault'], isFalse);
  expect(
    SessionPreferences.fromJson(off.toJson()).opencodePersonalAcpDefault,
    isFalse,
  );
});
```

Add to `session_preferences_cubit_test.dart` next to the Cursor setter test:

```dart
test('setOpencodePersonalAcpDefault persists the flag', () async {
  final cubit = await makeCubit();
  await cubit.load();
  expect(cubit.state.preferences.opencodePersonalAcpDefault, true);

  await cubit.setOpencodePersonalAcpDefault(false);
  expect(cubit.state.preferences.opencodePersonalAcpDefault, false);

  final cubit2 = await makeCubit();
  await cubit2.load();
  expect(cubit2.state.preferences.opencodePersonalAcpDefault, false);
});
```

In `claude_acp_launch_switch_test.dart` `resolveLaunchAcp` group, add next to the Codex true test:

```dart
test('true for personal OpenCode when requested on desktop', () {
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.opencode,
      requested: true,
      isAndroidOverride: false,
    ),
    isTrue,
  );
});

test('false for OpenCode team, not requested, or Android', () {
  expect(
    resolveLaunchAcp(
      isPersonal: false,
      cli: CliTool.opencode,
      requested: true,
      isAndroidOverride: false,
    ),
    isFalse,
  );
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.opencode,
      requested: false,
      isAndroidOverride: false,
    ),
    isFalse,
  );
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.opencode,
      requested: true,
      isAndroidOverride: true,
    ),
    isFalse,
  );
});
```

In the same file, add to `buildWorkspaceConversationCreateRequest` group:

```dart
test('personal OpenCode with ACP requested sets request.acp', () {
  final request = buildWorkspaceConversationCreateRequest(
    workspace: workspace,
    isPersonal: true,
    cli: CliTool.opencode,
    acp: true,
    isAndroidOverride: false,
  );
  expect(request.acp, isTrue);
});
```

Keep the existing Claude / Cursor / Codex `resolveLaunchAcp` tests. Do **not** change `resolve(cli: CliTool.opencode)` inside `resolveMemberBindingAcp` in this task — that stays false until Task 2 registers `AcpCapability`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: FAIL — `opencodePersonalAcpDefault` / `setOpencodePersonalAcpDefault` undefined; OpenCode `resolveLaunchAcp` is false.

- [ ] **Step 3: Implement preference + gate**

In `session_preferences.dart`:

1. Constructor: add `this.opencodePersonalAcpDefault = true,` after `cursorPersonalAcpDefault`.
2. `fromJson`: `opencodePersonalAcpDefault: json['opencodePersonalAcpDefault'] as bool? ?? true,`
3. Field + dartdoc (mirror Cursor: default true; existing sessions keep their runtime).
4. `copyWith`: named `bool? opencodePersonalAcpDefault` and pass `opencodePersonalAcpDefault ?? this.opencodePersonalAcpDefault`.
5. `toJson`: `'opencodePersonalAcpDefault': opencodePersonalAcpDefault,`

In `session_preferences_cubit.dart` next to `setCursorPersonalAcpDefault`:

```dart
Future<void> setOpencodePersonalAcpDefault(bool value) {
  return _save(
    state.preferences.copyWith(opencodePersonalAcpDefault: value),
  );
}
```

In `claude_acp_launch_switch.dart`:

```dart
bool _personalAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) =>
    isPersonal &&
    (cli == CliTool.claude ||
        cli == CliTool.cursor ||
        cli == CliTool.codex ||
        cli == CliTool.opencode) &&
    !_isAndroid(isAndroidOverride);
```

Update the `resolveLaunchAcp` dartdoc to name OpenCode.

```dart
bool readPersonalAcpDefault(BuildContext context, CliTool? cli) {
  try {
    final prefs = context.read<SessionPreferencesCubit>().state.preferences;
    return switch (cli) {
      CliTool.claude => prefs.claudePersonalAcpDefault,
      CliTool.cursor => prefs.cursorPersonalAcpDefault,
      CliTool.codex => prefs.codexPersonalAcpDefault,
      CliTool.opencode => prefs.opencodePersonalAcpDefault,
      _ => false,
    };
  } on ProviderNotFoundException {
    return cli == CliTool.claude ||
        cli == CliTool.cursor ||
        cli == CliTool.opencode;
  }
}
```

Codex stays out of the `ProviderNotFoundException` true list (its default is false).

In `workspace_session_actions.dart`, change the comment on `buildWorkspaceConversationCreateRequest` from "personal Claude, Cursor, or Codex" to include OpenCode.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart \
  client/lib/cubits/session_preferences_cubit.dart \
  client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/test/models/session_preferences_test.dart \
  client/test/cubits/session_preferences_cubit_test.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
git commit -m "$(cat <<'EOF'
feat(opencode): add personal ACP preference and launch gate

New OpenCode sessions can opt into ACP chat via opencodePersonalAcpDefault
(default on). Existing sessions keep the runtime they were started with.
EOF
)"
```

---

### Task 2: Native `opencode acp` capability

**Files:**
- Create: `client/lib/services/cli/opencode/capabilities/acp.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Modify: `client/lib/services/acp/acp_agent_translator.dart`
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/services/cli/opencode/opencode_acp_capability_test.dart`
- Test: `client/test/services/cli/opencode/opencode_registry_acp_test.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` (`resolveMemberBindingAcp` OpenCode assertion)

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/cli/opencode/opencode_acp_capability_test.dart`:

```dart
import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/opencode/capabilities/acp.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';

void main() {
  test('launchArgCandidates is opencode acp', () {
    const cap = OpencodeAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/opencode'), [
      ['/usr/bin/opencode', 'acp'],
    ]);
    expect(cap.agentExecutable('/usr/bin/opencode'), '/usr/bin/opencode');
    expect(cap.authenticateMethodId, isNull);
    expect(cap.forwardSessionNewMcpServers, isFalse);
  });

  test('buildEnvironment preserves OPENCODE_* keys from baseEnv', () {
    const cap = OpencodeAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/opencode',
      workingDirectory: '/work',
      baseEnv: {
        'PATH': '/bin',
        'HOME': '/iso/home',
        OpencodeProviderCapability.configDirEnv: '/iso/config',
        OpencodeProviderCapability.dbPathEnv: '/iso/config/opencode.db',
        OpencodeProviderCapability.authContentEnv: '{"anthropic":"secret"}',
        OpencodeProviderCapability.cliConfigContentEnv:
            OpencodeProviderCapability.cliConfigContent,
      },
    );
    expect(env['HOME'], '/iso/home');
    expect(env['PATH'], '/bin');
    expect(env[OpencodeProviderCapability.configDirEnv], '/iso/config');
    expect(
      env[OpencodeProviderCapability.dbPathEnv],
      '/iso/config/opencode.db',
    );
    expect(
      env[OpencodeProviderCapability.authContentEnv],
      '{"anthropic":"secret"}',
    );
    expect(
      env[OpencodeProviderCapability.cliConfigContentEnv],
      OpencodeProviderCapability.cliConfigContent,
    );
  });

  test('buildEnvironment does not invent HOME from sessionToolDir', () {
    const cap = OpencodeAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/opencode',
      workingDirectory: '/work',
      baseEnv: const {'PATH': '/bin'},
    );
    expect(env['HOME'], isNull);
    expect(env[OpencodeProviderCapability.configDirEnv], isNull);
    expect(env['PATH'], '/bin');
  });

  test('translator has no client extension methods', () {
    const cap = OpencodeAcpCapability();
    expect(cap.translator, isA<OpencodeAcpTranslator>());
    expect(cap.translator.flagCandidates, isEmpty);
    expect(cap.translator.blockingClientMethods, isEmpty);
    expect(cap.translator.notificationClientMethods, isEmpty);
  });

  test('translator maps authRequired to acpStopAuthRequired', () {
    const translator = OpencodeAcpTranslator();
    final error = RpcError.fromCode(ErrorCode.authRequired);
    expect(
      translator.translateStopError(error, suppressAbort: false),
      acpStopAuthRequired,
    );
  });

  test('translator leaves other RpcErrors as ACP error text', () {
    const translator = OpencodeAcpTranslator();
    final error = RpcError.fromCode(ErrorCode.internalError);
    expect(
      translator.translateStopError(error, suppressAbort: false),
      'ACP error ${ErrorCode.internalError.code}: ${error.message}',
    );
  });
}
```

Create `client/test/services/cli/opencode/opencode_registry_acp_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/acp.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('opencode registers AcpCapability that spawns opencode acp', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final cap = registry.capability<AcpCapability>(CliTool.opencode);
    expect(cap, isA<OpencodeAcpCapability>());
    expect(cap!.agentExecutable('/usr/bin/opencode'), '/usr/bin/opencode');
    expect(cap.launchArgCandidates('/usr/bin/opencode'), [
      ['/usr/bin/opencode', 'acp'],
    ]);
    expect(cap.authenticateMethodId, isNull);
    expect(capabilityToPlan(cap)!.authenticateMethodId, isNull);
    expect(capabilityToPlan(cap)!.forwardSessionNewMcpServers, isFalse);
  });
}
```

In `acp_chat_runtime_cubit_test.dart`, next to `error stop → inline system message`, add (import `package:teampilot/services/acp/acp_agent_translator.dart`):

```dart
test('authRequired sentinel stop uses notLoggedIn copy, not Turn failed', () async {
  final cubit = bootCubit();
  await cubit.start(
    executable: 'opencode',
    sessionToolDir: '/tmp/tool',
    workingDirectory: '/w',
  );
  runtime.emit(
    const AcpStop(kind: AcpStopKind.error, message: acpStopAuthRequired),
  );
  await pumpEventQueue();

  expect(cubit.state.phase, AcpChatPhase.idle);
  final message = cubit.state.messages.single;
  expect(message.role, AiRole.system);
  expect((message.parts.single as AiTextPart).text, 'Not logged in');
  expect((message.parts.single as AiTextPart).text, isNot(contains('Turn failed')));
  expect((message.parts.single as AiTextPart).text, isNot(contains(acpStopAuthRequired)));
  await cubit.close();
});
```

`bootCubit` already injects `notLoggedIn: 'Not logged in'`.

In `claude_acp_launch_switch_test.dart` `resolveMemberBindingAcp` test, change:

```dart
expect(resolve(cli: CliTool.opencode), isTrue);
expect(resolve(cli: CliTool.opencode, requested: false), isFalse);
expect(resolve(cli: CliTool.flashskyai), isFalse);
```

Remove the old `expect(resolve(cli: CliTool.opencode), isFalse)`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/opencode/opencode_acp_capability_test.dart test/services/cli/opencode/opencode_registry_acp_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: FAIL — missing `opencode/capabilities/acp.dart`; registry has no OpenCode `AcpCapability`; `resolveMemberBindingAcp` OpenCode is still false; cubit shows `Turn failed: __acp_stop_auth_required__` (or compile error on the sentinel).

- [ ] **Step 3: Implement capability, register it, map auth_required**

Add to `acp_agent_translator.dart` under `acpStopCancelled`:

```dart
/// Sentinel returned when the agent reports ACP `auth_required` (-32000).
/// Cubit surfaces the generic not-logged-in copy instead of the raw RPC error.
const String acpStopAuthRequired = '__acp_stop_auth_required__';
```

Update the `translateStopError` dartdoc to mention both sentinels.

Create `client/lib/services/cli/opencode/capabilities/acp.dart`:

```dart
import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class OpencodeAcpTranslator implements AcpAgentTranslator {
  const OpencodeAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      if (error.code == ErrorCode.authRequired.code) {
        return acpStopAuthRequired;
      }
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class OpencodeAcpCapability implements AcpCapability {
  const OpencodeAcpCapability();

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, 'acp'],
  ];

  @override
  String? get authenticateMethodId => null;

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  AcpAgentTranslator get translator => const OpencodeAcpTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    return Map<String, String>.of(baseEnv);
  }
}
```

In `opencode_tool.dart`:

1. `import 'capabilities/acp.dart';`
2. Constructor: `this.acp = const OpencodeAcpCapability(),`
3. Field: `final OpencodeAcpCapability acp;`
4. Include `acp` at the end of the `capabilities` list.

In `acp_chat_runtime_cubit.dart`:

1. Import `../../../services/acp/acp_agent_translator.dart`.
2. Replace the `AcpStopKind.error` branch in `_onStop`:

```dart
case AcpStopKind.error:
  final text = stop.message == acpStopAuthRequired
      ? (_strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn)
      : (stop.message == null || stop.message!.isEmpty
            ? (_strings?.turnFailed ?? 'Turn failed')
            : '${_strings?.turnFailed ?? 'Turn failed'}: ${stop.message}');
  _appendSystemMessage(text);
  unawaited(_persist());
  _endTurn();
```

Do not add `if (cli == opencode)` here. Any translator may return the sentinel.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/opencode/opencode_acp_capability_test.dart test/services/cli/opencode/opencode_registry_acp_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: PASS. `resolveMemberBindingAcp` OpenCode is now true when requested because `_memberAcpGates` finds `AcpCapability`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/opencode/capabilities/acp.dart \
  client/lib/services/cli/opencode/opencode_tool.dart \
  client/lib/services/acp/acp_agent_translator.dart \
  client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/test/services/cli/opencode/opencode_acp_capability_test.dart \
  client/test/services/cli/opencode/opencode_registry_acp_test.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
git commit -m "$(cat <<'EOF'
feat(opencode): register native opencode acp capability

Spawn the same OpenCode binary with the acp subcommand. Credentials stay
in the isolated session home; prompt auth_required uses the shared
not-logged-in copy.
EOF
)"
```

---

### Task 3: Mixed-seat seed plumbing

**Files:**
- Modify: `client/lib/services/chat/session/session_create_request.dart`
- Modify: `client/lib/services/chat/launch/session/member_acp_stamp.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/lib/services/chat/launch/session/session_launch_coordinator.dart`
- Modify: `client/lib/services/chat/session/session_data_store.dart`
- Modify: `client/lib/services/catalog/workspace_catalog.dart`
- Modify: `client/test/services/chat/launch/session_launch_pipeline_stable_task_id_test.dart`
- Modify: `client/test/services/chat/launch/session_generation_purpose_pipeline_test.dart`
- Modify: `client/test/services/chat/launch/session_default_materializer_test.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

- [ ] **Step 1: Write the failing tests**

In `claude_acp_launch_switch_test.dart`:

1. Extend the `stamp` helper with `bool seedOpencode = true` and pass `seedOpencodeMemberAcp: seedOpencode`.
2. Add:

```dart
test('OpenCode follows seedOpencodeMemberAcp', () {
  expect(
    stamp(
      members: [member(CliTool.opencode, 'oc')],
      seedOpencode: true,
    ).single.acp,
    isTrue,
  );
  expect(
    stamp(
      members: [member(CliTool.opencode, 'oc')],
      seedOpencode: false,
    ).single.acp,
    isFalse,
  );
});
```

3. In `team create keeps request.acp false and copies CLI seeds`, pass `seedOpencodeMemberAcp: true` and expect `request.seedOpencodeMemberAcp` is true.
4. In `team create seed defaults match preference defaults`, expect `request.seedOpencodeMemberAcp` is true.

Add a `shouldAttachMemberAcp` case for OpenCode (copy the existing Claude case, `cli: CliTool.opencode`, local true / ssh false).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: FAIL — `seedOpencodeMemberAcp` undefined; OpenCode stamp ignores a dedicated seed.

- [ ] **Step 3: Thread the seed**

`session_create_request.dart`: `this.seedOpencodeMemberAcp = true,` and field dartdoc "Mixed-seat OpenCode ACP seed (`opencodePersonalAcpDefault`, default true)."

`member_acp_stamp.dart`:

```dart
bool _requestedMemberAcpSeed(
  CliTool? cli, {
  required bool seedClaudeMemberAcp,
  required bool seedCodexMemberAcp,
  required bool seedCursorMemberAcp,
  required bool seedOpencodeMemberAcp,
}) => switch (cli) {
  CliTool.claude => seedClaudeMemberAcp,
  CliTool.codex => seedCodexMemberAcp,
  CliTool.cursor => seedCursorMemberAcp,
  CliTool.opencode => seedOpencodeMemberAcp,
  _ => false,
};
```

Add `bool seedOpencodeMemberAcp = true` to `stampMemberAcp` and pass it into `_requestedMemberAcpSeed`.

`buildWorkspaceConversationCreateRequest`: add `bool seedOpencodeMemberAcp = true` and forward it.

`_requestCreateWorkspaceConversation`:

```dart
final seedOpencodeMemberAcp = readPersonalAcpDefault(
  context,
  CliTool.opencode,
);
```

Pass it into `buildWorkspaceConversationCreateRequest`.

`session_repository.dart` `createSession`: add `bool seedOpencodeMemberAcp = true` and pass it to `stampMemberAcp`.

`session_launch_coordinator.dart` stamp call: `seedOpencodeMemberAcp: request.seedOpencodeMemberAcp`.

`session_data_store.dart` and `workspace_catalog.dart`: add the named param (default true) and forward to `repo.createSession`.

The three pipeline test fakes that copy `createSession`'s named params must add `bool seedOpencodeMemberAcp = true` so they keep compiling against `SessionRepository.createSession` if they `@override` it:

- `client/test/services/chat/launch/session_launch_pipeline_stable_task_id_test.dart`
- `client/test/services/chat/launch/session_generation_purpose_pipeline_test.dart`
- `client/test/services/chat/launch/session_default_materializer_test.dart`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart test/services/chat/launch/session_launch_pipeline_stable_task_id_test.dart test/services/chat/launch/session_generation_purpose_pipeline_test.dart test/services/chat/launch/session_default_materializer_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/session/session_create_request.dart \
  client/lib/services/chat/launch/session/member_acp_stamp.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/lib/repositories/session_repository.dart \
  client/lib/services/chat/launch/session/session_launch_coordinator.dart \
  client/lib/services/chat/session/session_data_store.dart \
  client/lib/services/catalog/workspace_catalog.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart \
  client/test/services/chat/launch/session_launch_pipeline_stable_task_id_test.dart \
  client/test/services/chat/launch/session_generation_purpose_pipeline_test.dart \
  client/test/services/chat/launch/session_default_materializer_test.dart
git commit -m "$(cat <<'EOF'
feat(opencode): seed mixed-team ACP seats from settings

New mixed OpenCode members follow opencodePersonalAcpDefault. Existing
team sessions stay on the runtime stamped at create.
EOF
)"
```

---

### Task 4: Settings switch + l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/pages/config/cli_config_section.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart`

- [ ] **Step 1: Add copy and the failing widget tests**

In `app_en.arb` next to the Cursor keys:

```json
"opencodePersonalAcpDefaultLabel": "Personal sessions use ACP chat",
"opencodePersonalAcpDefaultDescription": "Run new personal and mixed-team OpenCode sessions as terminal-less ACP chat via opencode acp. Existing sessions stay as they were started. Native teams and remote members still use the terminal."
```

In `app_zh.arb`:

```json
"opencodePersonalAcpDefaultLabel": "个人会话使用 ACP 聊天",
"opencodePersonalAcpDefaultDescription": "新建个人和混合团队 OpenCode 会话走无终端 ACP（opencode acp）。已有会话保持原启动方式。原生团队和远程成员仍用终端。"
```

Do not add a new Android string; reuse `claudePersonalAcpAndroidDisabled`.

In `app_keys.dart` next to `opencodeCliInstallButton`:

```dart
static const opencodePersonalAcpSwitch = Key('opencode-personal-acp-switch');
```

Add `_wrapOpencodeAcpRow` in `cli_config_section_test.dart` next to `_wrapCursorAcpRow`:

```dart
Widget _wrapOpencodeAcpRow(
  SessionPreferencesCubit cubit, {
  bool isAndroid = false,
}) {
  return BlocProvider.value(
    value: cubit,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: OpencodePersonalAcpSettingsRow(
          cubit: cubit,
          isAndroidOverride: isAndroid,
        ),
      ),
    ),
  );
}
```

Add these tests after the Cursor ACP switch tests:

```dart
testWidgets('OpenCode ACP switch is shown in the OpenCode CLI section', (
  tester,
) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(_wrap(cubit));
  await tester.pump();

  final tile = find.byKey(AppKeys.opencodePersonalAcpSwitch);
  expect(tile, findsOneWidget);
  expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  expect(
    find.descendant(of: tile, matching: find.textContaining('mixed-team')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: tile, matching: find.textContaining('Native teams')),
    findsOneWidget,
  );

  await tester.pumpWidget(_wrapOpencodeAcpRow(cubit));
  await tester.pump();
  expect(find.text('Install ACP adapter'), findsNothing);
});

testWidgets('OpenCode ACP switch toggles opencodePersonalAcpDefault', (
  tester,
) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(_wrapOpencodeAcpRow(cubit));
  await tester.pump();
  await tester.tap(find.byKey(AppKeys.opencodePersonalAcpSwitch));
  await tester.pump();

  expect(cubit.state.preferences.opencodePersonalAcpDefault, isFalse);
  expect(
    tester
        .widget<SwitchListTile>(find.byKey(AppKeys.opencodePersonalAcpSwitch))
        .value,
    isFalse,
  );
});

testWidgets('OpenCode ACP switch is disabled with a note on Android', (
  tester,
) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(_wrapOpencodeAcpRow(cubit, isAndroid: true));
  await tester.pump();

  final tile = tester.widget<SwitchListTile>(
    find.byKey(AppKeys.opencodePersonalAcpSwitch),
  );
  expect(tile.onChanged, isNull);
  expect(
    find.text('ACP chat is desktop-only until remote SSH exec is available.'),
    findsOneWidget,
  );

  await tester.tap(find.byKey(AppKeys.opencodePersonalAcpSwitch));
  await tester.pump();
  expect(cubit.state.preferences.opencodePersonalAcpDefault, isTrue);
});
```

Extend `ACP settings descriptions mention mixed teams in English and Chinese`:

```dart
expect(
  en.opencodePersonalAcpDefaultDescription,
  'Run new personal and mixed-team OpenCode sessions as terminal-less ACP chat via opencode acp. Existing sessions stay as they were started. Native teams and remote members still use the terminal.',
);
expect(
  zh.opencodePersonalAcpDefaultDescription,
  '新建个人和混合团队 OpenCode 会话走无终端 ACP（opencode acp）。已有会话保持原启动方式。原生团队和远程成员仍用终端。',
);
```

- [ ] **Step 2: Generate l10n and run tests to verify they fail**

```bash
cd client && flutter gen-l10n
cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart
```

Expected: FAIL — `OpencodePersonalAcpSettingsRow` missing; switch key not found.

- [ ] **Step 3: Implement the settings row**

In `_buildCliRow` (same file as Cursor/Codex branches), after the Codex `if`:

```dart
if (cli == CliTool.opencode) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      pathRow,
      OpencodePersonalAcpSettingsRow(cubit: cubit),
    ],
  );
}
```

Add `OpencodePersonalAcpSettingsRow` cloned from `CursorPersonalAcpSettingsRow`:

- `buildWhen` on `opencodePersonalAcpDefault`
- `switchKey: AppKeys.opencodePersonalAcpSwitch`
- `label` / `description` from the new l10n getters
- `androidDescription: l10n.claudePersonalAcpAndroidDisabled`
- `onChanged`: `cubit.setOpencodePersonalAcpDefault`
- no `trailing` adapter button

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/pages/config/cli_config_section.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "$(cat <<'EOF'
feat(opencode): add personal ACP settings switch

Mirror the Cursor ACP row: default on, desktop-only, no adapter install
button. Copy names opencode acp and mixed-team seats.
EOF
)"
```

Include generated l10n Dart files if `flutter gen-l10n` changed them.

---

### Task 5: Redact OpenCode auth content in ACP logs

**Files:**
- Modify: `client/lib/services/acp/acp_frame_logger.dart`
- Test: `client/test/services/acp/acp_frame_logger_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('redacts OPENCODE_AUTH_CONTENT values in frames', () {
  final logger = AcpFrameLogger();
  logger.logOutgoing(
    jsonEncode({
      'method': 'session/prompt',
      'env': {'OPENCODE_AUTH_CONTENT': 'super-secret'},
    }),
  );
  final text = logger.snapshot().join('\n');
  expect(text, contains('[REDACTED]'));
  expect(text, isNot(contains('super-secret')));
});

test('redacts OPENCODE_AUTH_CONTENT in stderr env form too', () {
  final logger = AcpFrameLogger();
  logger.logStderr('OPENCODE_AUTH_CONTENT=super-secret-2');
  final text = logger.snapshot().join('\n');
  expect(text, isNot(contains('super-secret-2')));
  expect(text, contains('OPENCODE_AUTH_CONTENT=[REDACTED]'));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_frame_logger_test.dart`

Expected: FAIL — snapshot still contains `super-secret`.

- [ ] **Step 3: Implement redaction**

In `acp_frame_logger.dart`, add patterns next to the Cursor ones:

```dart
static final RegExp _opencodeAuthContentQuotedPattern =
    RegExp(r'"OPENCODE_AUTH_CONTENT"\s*:\s*"[^"]*"');
static final RegExp _opencodeAuthContentEnvPattern = RegExp(
  r'OPENCODE_AUTH_CONTENT\s*=\s*\S+',
);
```

In `_redact`, after the Cursor replacements:

```dart
redacted = redacted.replaceAll(
  _opencodeAuthContentQuotedPattern,
  '"OPENCODE_AUTH_CONTENT": "[REDACTED]"',
);
redacted = redacted.replaceAll(
  _opencodeAuthContentEnvPattern,
  'OPENCODE_AUTH_CONTENT=[REDACTED]',
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_frame_logger_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_frame_logger.dart \
  client/test/services/acp/acp_frame_logger_test.dart
git commit -m "$(cat <<'EOF'
fix(acp): redact OPENCODE_AUTH_CONTENT in frame logs

Isolated OpenCode auth payloads must not land in ACP diagnostics.
EOF
)"
```

---

### Task 6: Docs + analyze

**Files:**
- Modify: `docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md`

- [ ] **Step 1: Update the mixed-team first-wave line**

Replace:

```
- First-wave CLIs: Claude, Codex, Gemini (already declare
  `AcpCapability`). OpenCode, FlashskyAI, unshipped Cursor stay PTY.
```

with:

```
- First-wave CLIs: Claude, Codex, Gemini, Cursor, and OpenCode (each
  declares `AcpCapability`). FlashskyAI stays PTY.
  OpenCode mixed seats: docs/superpowers/specs/2026-10-13-opencode-acp-session-design.md.
```

- [ ] **Step 2: Analyze the client**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues in files touched by this plan.

- [ ] **Step 3: Re-run the focused tests**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart test/services/cli/opencode/opencode_acp_capability_test.dart test/services/cli/opencode/opencode_registry_acp_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart test/pages/config/cli_config_section_test.dart test/services/acp/acp_frame_logger_test.dart`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md
git commit -m "$(cat <<'EOF'
docs: note OpenCode in mixed-team ACP first wave

OpenCode now declares AcpCapability; FlashskyAI remains PTY-only.
EOF
)"
```

Full suite (`cd client && dart run tool/run_tests.dart`) is the slow outer loop before claiming done, not part of this task's inner loop.

## Manual desktop check

- Settings → CLI → OpenCode: switch on by default; Android shows the desktop-only note and is disabled; no adapter button.
- Personal OpenCode, switch on → ACP chat (no live terminal), permission card, catalog MCP from isolated `opencode.json`.
- Personal OpenCode, switch off → new session still gets a PTY.
- Mixed local OpenCode seat, switch on → ACP seat; teammate-bus via staged config.
- Existing PTY OpenCode sessions unchanged after toggling the switch.
- Old OpenCode without `acp` → version-unsupported launch error, not a silent PTY fallback.

## Out of scope (do not implement)

- Android / SSH ACP
- Native-team ACP
- `session/load` / persisting ACP session ids
- `session/new` `mcpServers` or `additionalDirectories`
- `opencode acp --login` / `auth.terminal`
- Elicitation, compaction, child-session chrome, usage meters
- FlashskyAI ACP
- Per-CLI preference map refactor
