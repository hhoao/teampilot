# Cursor ACP Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let new personal Cursor sessions launch as terminal-less ACP chat (`cursor-agent acp`) behind `cursorPersonalAcpDefault` (default on), including authenticate, isolated-home MCP, permission cards, and all five Cursor client extension methods, without replacing PTY Cursor.

**Architecture:** Reuse the existing ACP stack (`acpd` + `AcpProcessTransport` + `AcpSessionRuntime`). `CursorCliTool` declares `CursorAcpCapability` (`[cursor-agent, acp]`, preserve `baseEnv` HOME). Handshake optionally sends `authenticate`. Cursor extension methods are declared on the translator, registered in a new `acp_client_extensions.dart`, folded by `acp_chat_extension_fold.dart`, and shown through existing `AiAskUserQuestionCard` / `AiExitPlanModeCard`. Preference seeds new launches only; `AppSession.acp` is the session fact.

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, existing ACP chat cubit / transcript, Cursor isolated `$HOME` from `prepareSimpleConnect`.

**Spec:** `docs/superpowers/specs/2026-10-12-cursor-acp-session-design.md`

## Global Constraints

- Desktop-local only. No `SshExecTransport`, no Android ACP (disable the switch when `Platform.isAndroid`).
- No `CliTool.cursorAcp`. Do not replace PTY Cursor. Team sessions stay PTY (`createSession` already forces `acp = false`).
- Argv is `[cursor-agent, acp]`. Never probe `--acp`. No adapter installer.
- `buildEnvironment` must **preserve** `HOME` / `CURSOR_CONFIG_DIR` from `baseEnv`. Never point Cursor auth at `sessionToolDir`.
- Handshake / spawn failure must not fall back to PTY for that connect.
- No `if (cli == cursor)` in `services/acp/`, `AcpSessionRuntime`, or `AcpChatRuntimeCubit`. Cursor-only behavior lives in `services/cli/cursor/` and in extension codecs keyed by method name `cursor/…` (protocol, not `CliTool`).
- Do not grow `acp_session.dart` (~568) or `acp_chat_runtime_cubit.dart` (~714) with extension logic — extract files listed below.
- User copy → `app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- After arb edits, `cd client && flutter gen-l10n` before tests that read new getters.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_preferences.dart` | `cursorPersonalAcpDefault` |
| `client/lib/cubits/session_preferences_cubit.dart` | setter |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Cursor ACP copy + generic version failure |
| `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart` | Allow Claude **or** Cursor; `readPersonalAcpDefault` |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | Draft uses selected CLI preference |
| `client/lib/services/cli/registry/capabilities/acp_capability.dart` | `authenticateMethodId` |
| `client/lib/services/acp/acp_agent_translator.dart` | blocking / notification method lists |
| `client/lib/services/cli/cursor/capabilities/acp.dart` | translator + capability |
| `client/lib/services/cli/cursor/cursor_tool.dart` | register capability |
| `client/lib/services/cli/registry/built_in_cli_tools.dart` | wire Cursor ACP |
| `client/lib/cubits/session/acp/acp_launch_wiring.dart` | copy `authenticateMethodId` into `AcpLaunchPlan` |
| `client/lib/services/acp/acp_session_runtime.dart` | `AcpLaunchPlan.authenticateMethodId` |
| `client/lib/services/acp/acp_connection.dart` | optional `authenticate` after `initialize` |
| `client/lib/services/acp/acp_client_extensions.dart` | parse/encode + pending types + hold replies |
| `client/lib/services/acp/acp_session.dart` | register translator methods; one hold gate |
| `client/lib/services/acp/acp_chat_extension_fold.dart` | todos / task / image → `AiMessage` parts |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | one `pendingClient`; delegate fold |
| `client/lib/pages/chat/acp_ask_card.dart` | ACP host for `AiAskUserQuestionCard` |
| `client/lib/pages/chat/acp_plan_card.dart` | ACP host for `AiExitPlanModeCard` |
| `client/lib/pages/chat/session_chat_compose_section.dart` | switch pending permission / ask / plan |
| `client/lib/pages/config/cli_config_section.dart` | Cursor settings switch |
| `client/lib/utils/ui/app_keys.dart` | `cursorPersonalAcpSwitch` |
| `client/lib/services/acp/acp_frame_logger.dart` | redact `CURSOR_API_KEY` / `CURSOR_AUTH_TOKEN` |

---

### Task 1: Preference + launch gate

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` (the `resolveLaunchAcp` call in `_currentDraft`)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` (comment on `buildWorkspaceConversationCreateRequest`)
- Test: `client/test/models/session_preferences_test.dart`
- Test: `client/test/cubits/session_preferences_cubit_test.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `session_preferences_test.dart` next to the Claude case:

```dart
test('cursorPersonalAcpDefault defaults true and round-trips', () {
  expect(SessionPreferences().cursorPersonalAcpDefault, isTrue);
  expect(
    SessionPreferences.fromJson(const {}).cursorPersonalAcpDefault,
    isTrue,
  );
  final off = SessionPreferences(cursorPersonalAcpDefault: false);
  expect(off.toJson()['cursorPersonalAcpDefault'], isFalse);
  expect(
    SessionPreferences.fromJson(off.toJson()).cursorPersonalAcpDefault,
    isFalse,
  );
});
```

Add to `session_preferences_cubit_test.dart`:

```dart
test('setCursorPersonalAcpDefault persists the flag', () async {
  final cubit = await makeCubit();
  await cubit.load();
  expect(cubit.state.preferences.cursorPersonalAcpDefault, true);

  await cubit.setCursorPersonalAcpDefault(false);
  expect(cubit.state.preferences.cursorPersonalAcpDefault, false);

  final cubit2 = await makeCubit();
  await cubit2.load();
  expect(cubit2.state.preferences.cursorPersonalAcpDefault, false);
});
```

Replace the non-Claude case in `claude_acp_launch_switch_test.dart` so Cursor is true and Gemini stays false:

```dart
test('true for personal Cursor when requested on desktop', () {
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.cursor,
      requested: true,
      isAndroidOverride: false,
    ),
    isTrue,
  );
});

test('false for team, Gemini, not requested, or Android', () {
  bool resolve({
    bool isPersonal = true,
    CliTool? cli = CliTool.claude,
    bool requested = true,
    bool isAndroid = false,
  }) => resolveLaunchAcp(
    isPersonal: isPersonal,
    cli: cli,
    requested: requested,
    isAndroidOverride: isAndroid,
  );
  expect(resolve(isPersonal: false), isFalse);
  expect(resolve(cli: CliTool.gemini), isFalse);
  expect(resolve(cli: null), isFalse);
  expect(resolve(requested: false), isFalse);
  expect(resolve(isAndroid: true), isFalse);
  expect(
    resolve(cli: CliTool.cursor, isAndroid: true),
    isFalse,
  );
});
```

Keep the existing personal-Claude-true test.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: FAIL — `cursorPersonalAcpDefault` / `setCursorPersonalAcpDefault` undefined; Cursor `resolveLaunchAcp` is false.

- [ ] **Step 3: Implement**

`SessionPreferences`: add `this.cursorPersonalAcpDefault = true` to the constructor; `json['cursorPersonalAcpDefault'] as bool? ?? true` in `fromJson`; field + doc (mirror Claude); `copyWith` param; `toJson` key.

Cubit: add `setCursorPersonalAcpDefault` mirroring `setClaudePersonalAcpDefault`.

`claude_acp_launch_switch.dart`:

```dart
bool _personalAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) =>
    isPersonal &&
    (cli == CliTool.claude || cli == CliTool.cursor) &&
    !(isAndroidOverride ?? Platform.isAndroid);

bool resolveLaunchAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) =>
    requested &&
    _personalAcpAllowed(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    );

bool readPersonalAcpDefault(BuildContext context, CliTool? cli) {
  try {
    final prefs = context.read<SessionPreferencesCubit>().state.preferences;
    return switch (cli) {
      CliTool.claude => prefs.claudePersonalAcpDefault,
      CliTool.cursor => prefs.cursorPersonalAcpDefault,
      _ => false,
    };
  } on ProviderNotFoundException {
    return cli == CliTool.claude || cli == CliTool.cursor;
  }
}

bool readClaudePersonalAcpDefault(BuildContext context) =>
    readPersonalAcpDefault(context, CliTool.claude);
```

Keep `readClaudePersonalAcpDefault` as a wrapper so existing Claude tests compile.

`unbound_compose_body.dart` `_currentDraft`:

```dart
acp: resolveLaunchAcp(
  isPersonal: isSimple,
  cli: launchCli,
  requested: readPersonalAcpDefault(context, launchCli),
),
```

Update the comment on `buildWorkspaceConversationCreateRequest` to say personal Claude **or** Cursor.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart \
  client/lib/cubits/session_preferences_cubit.dart \
  client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart \
  client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/test/models/session_preferences_test.dart \
  client/test/cubits/session_preferences_cubit_test.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
git commit -m "$(cat <<'EOF'
feat: seed personal Cursor ACP from an independent settings default

New Cursor sessions should follow cursorPersonalAcpDefault instead of
Claude's switch, and resolveLaunchAcp must allow both CLIs on desktop.
EOF
)"
```

---

### Task 2: l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Edit arb only**

Change `acpLaunchFailedVersion`:

en: `This CLI version does not support ACP chat mode. Update the CLI and try again.`

zh: `当前 CLI 版本不支持 ACP 聊天模式，请更新后再试。`

Add next to the Claude ACP strings:

en:

```json
"cursorPersonalAcpDefaultLabel": "Personal sessions use ACP chat",
"cursorPersonalAcpDefaultDescription": "Run new personal Cursor sessions as terminal-less ACP chat via cursor-agent acp. Existing sessions stay as they were started. Team sessions always use the terminal."
```

zh:

```json
"cursorPersonalAcpDefaultLabel": "个人会话使用 ACP 聊天",
"cursorPersonalAcpDefaultDescription": "新建个人 Cursor 会话走无终端 ACP（cursor-agent acp）。已有会话保持原启动方式。团队会话始终用终端。"
```

Reuse `claudePersonalAcpAndroidDisabled` for the Android subtitle (do not add a second Android string).

- [ ] **Step 2: Generate l10n**

Run: `cd client && flutter gen-l10n`

Expected: `app_localizations*.dart` gain `cursorPersonalAcpDefaultLabel` / `Description`; `acpLaunchFailedVersion` uses the new copy.

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart
git commit -m "$(cat <<'EOF'
l10n: add Cursor personal ACP copy and generic ACP version error

Cursor settings need their own switch strings, and the version-failure
message must not say Gemini when Cursor's acp subcommand is missing.
EOF
)"
```

If generated localizations are gitignored or produced at test time only, commit just the arb files.

---

### Task 3: `CursorAcpCapability`

**Files:**
- Create: `client/lib/services/cli/cursor/capabilities/acp.dart`
- Modify: `client/lib/services/cli/registry/capabilities/acp_capability.dart`
- Modify: `client/lib/services/acp/acp_agent_translator.dart`
- Modify: `client/lib/services/cli/gemini/capabilities/acp.dart`
- Modify: `client/lib/services/cli/claude/capabilities/acp.dart`
- Modify: `client/lib/cubits/session/acp/acp_launch_wiring.dart` (`_NoopAcpTranslator`)
- Test: `client/test/services/cli/cursor/cursor_acp_capability_test.dart`
- Test: `client/test/services/cli/gemini/gemini_acp_capability_test.dart` (assert `authenticateMethodId` is null)

- [ ] **Step 1: Write the failing capability test**

```dart
// client/test/services/cli/cursor/cursor_acp_capability_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/acp.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_launch_environment.dart';

void main() {
  test('launchArgCandidates is cursor-agent acp', () {
    const cap = CursorAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/cursor-agent'), [
      ['/usr/bin/cursor-agent', 'acp'],
    ]);
    expect(cap.agentExecutable('/usr/bin/cursor-agent'), '/usr/bin/cursor-agent');
    expect(cap.authenticateMethodId, 'cursor_login');
  });

  test('buildEnvironment preserves HOME and CURSOR_CONFIG_DIR from baseEnv', () {
    const cap = CursorAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/cursor',
      workingDirectory: '/work',
      baseEnv: {
        'PATH': '/bin',
        'HOME': '/iso/home',
        'CURSOR_CONFIG_DIR': '/iso/home/.cursor',
        CursorLaunchEnvironment.credentialStoreEnvKey:
            CursorLaunchEnvironment.credentialStoreFile,
      },
    );
    expect(env['HOME'], '/iso/home');
    expect(env['CURSOR_CONFIG_DIR'], '/iso/home/.cursor');
    expect(env['PATH'], '/bin');
    expect(env.containsKey('CURSOR_API_KEY'), isFalse);
  });

  test('buildEnvironment does not invent HOME from sessionToolDir', () {
    const cap = CursorAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/cursor',
      workingDirectory: '/work',
      baseEnv: const {'PATH': '/bin'},
    );
    expect(env['HOME'], isNull);
    expect(env['CURSOR_CONFIG_DIR'], isNull);
    expect(env['PATH'], '/bin');
  });

  test('translator lists Cursor client extension methods', () {
    const cap = CursorAcpCapability();
    expect(cap.translator, isA<CursorAcpTranslator>());
    expect(cap.translator.blockingClientMethods, [
      'cursor/ask_question',
      'cursor/create_plan',
    ]);
    expect(cap.translator.notificationClientMethods, [
      'cursor/update_todos',
      'cursor/task',
      'cursor/generate_image',
    ]);
    expect(cap.translator.flagCandidates, isEmpty);
  });
}
```

Add to `gemini_acp_capability_test.dart`:

```dart
test('authenticateMethodId is null', () {
  const cap = GeminiAcpCapability();
  expect(cap.authenticateMethodId, isNull);
  expect(cap.translator.blockingClientMethods, isEmpty);
  expect(cap.translator.notificationClientMethods, isEmpty);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_acp_capability_test.dart`

Expected: FAIL — library does not exist.

- [ ] **Step 3: Implement interfaces + Cursor capability**

`acp_capability.dart` add:

```dart
  /// ACP `authenticate` methodId after initialize, or null to skip.
  String? get authenticateMethodId;
```

`acp_agent_translator.dart` add:

```dart
  /// Client JSON-RPC methods that block until the client replies.
  List<String> get blockingClientMethods;

  /// Client JSON-RPC methods sent as notifications (no reply).
  List<String> get notificationClientMethods;
```

Gemini + Claude translators: `blockingClientMethods => const []`, `notificationClientMethods => const []`.
Gemini + Claude capabilities: `authenticateMethodId => null`.
`_NoopAcpTranslator`: empty lists.

`client/lib/services/cli/cursor/capabilities/acp.dart`:

```dart
import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class CursorAcpTranslator implements AcpAgentTranslator {
  const CursorAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [
    'cursor/ask_question',
    'cursor/create_plan',
  ];

  @override
  List<String> get notificationClientMethods => const [
    'cursor/update_todos',
    'cursor/task',
    'cursor/generate_image',
  ];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class CursorAcpCapability implements AcpCapability {
  const CursorAcpCapability();

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, 'acp'],
  ];

  @override
  String? get authenticateMethodId => 'cursor_login';

  @override
  AcpAgentTranslator get translator => const CursorAcpTranslator();

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

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_acp_capability_test.dart test/services/cli/gemini/gemini_acp_capability_test.dart test/services/cli/claude/claude_acp_capability_test.dart`

Expected: PASS (Claude tests still compile after the new getters).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cursor/capabilities/acp.dart \
  client/lib/services/cli/registry/capabilities/acp_capability.dart \
  client/lib/services/acp/acp_agent_translator.dart \
  client/lib/services/cli/gemini/capabilities/acp.dart \
  client/lib/services/cli/claude/capabilities/acp.dart \
  client/lib/cubits/session/acp/acp_launch_wiring.dart \
  client/test/services/cli/cursor/cursor_acp_capability_test.dart \
  client/test/services/cli/gemini/gemini_acp_capability_test.dart
git commit -m "$(cat <<'EOF'
feat: declare Cursor ACP launch argv, login method, and extensions

Cursor speaks ACP on cursor-agent acp and authenticates with
cursor_login; the capability must keep isolated HOME from baseEnv.
EOF
)"
```

---

### Task 4: Register Cursor ACP on the CLI tool

**Files:**
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Test: `client/test/services/cli/cursor/cursor_registry_acp_test.dart`

- [ ] **Step 1: Write the failing registry test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/acp.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('cursor registers AcpCapability that spawns cursor-agent acp', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final cap = registry.capability<AcpCapability>(CliTool.cursor);
    expect(cap, isA<CursorAcpCapability>());
    expect(cap!.agentExecutable('/usr/bin/cursor-agent'), '/usr/bin/cursor-agent');
    expect(cap.launchArgCandidates('/usr/bin/cursor-agent'), [
      ['/usr/bin/cursor-agent', 'acp'],
    ]);
    expect(cap.authenticateMethodId, 'cursor_login');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_registry_acp_test.dart`

Expected: FAIL — `capability<AcpCapability>(cursor)` is null.

- [ ] **Step 3: Register**

`CursorCliTool`: add `this.acp = const CursorAcpCapability()` constructor param, field `final CursorAcpCapability acp`, include `acp` in `capabilities`.

`built_in_cli_tools.dart` `CursorCliTool(...)` needs no extra bootstrap (capability is const). Default constructor already includes `acp`.

- [ ] **Step 4: Run test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cursor/cursor_registry_acp_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cursor/cursor_tool.dart \
  client/test/services/cli/cursor/cursor_registry_acp_test.dart
git commit -m "$(cat <<'EOF'
feat: register Cursor AcpCapability on the built-in CLI tool

Attach runtime can resolve cursor-agent acp the same way it resolves
Gemini and Claude ACP launch plans.
EOF
)"
```

---

### Task 5: Optional `authenticate` in the handshake

**Files:**
- Modify: `client/lib/services/acp/acp_connection.dart`
- Modify: `client/lib/services/acp/acp_session_runtime.dart` (`AcpLaunchPlan`)
- Modify: `client/lib/cubits/session/acp/acp_launch_wiring.dart` (`capabilityToPlan` + `productionAcpSpawner`)
- Test: `client/test/services/acp/acp_connection_test.dart`

- [ ] **Step 1: Write the failing handshake tests**

Append to `acp_connection_test.dart`:

```dart
test('initialize skips authenticate when methodId is null', () async {
  var authenticated = false;
  stubInitialize();
  agent.connection.onRequest('authenticate', (params) {
    authenticated = true;
    return const acpd.AuthenticateResponse().toJson();
  });

  await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');
  expect(authenticated, isFalse);
});

test('initialize sends authenticate when methodId is set', () async {
  String? methodId;
  stubInitialize();
  agent.connection.onRequest('authenticate', (params) {
    methodId = (params! as Map)['methodId'] as String?;
    return const acpd.AuthenticateResponse().toJson();
  });

  await conn.initialize(
    clientName: 'teampilot',
    clientVersion: '1.0.0',
    authenticateMethodId: 'cursor_login',
  );
  expect(methodId, 'cursor_login');
});

test('initialize fails when authenticate errors', () async {
  stubInitialize();
  agent.connection.onRequest('authenticate', (params) {
    throw acpd.RpcError(
      code: acpd.ErrorCode.internalError.code,
      message: 'not logged in',
    );
  });

  await expectLater(
    conn.initialize(
      clientName: 'teampilot',
      clientVersion: '1.0.0',
      authenticateMethodId: 'cursor_login',
    ),
    throwsA(isA<acpd.RpcError>()),
  );
});
```

`capabilityToPlan` tests: if none exist, add a small test in `client/test/cubits/session/acp/` or extend an existing launch-wiring test so `authenticateMethodId` is copied. If no dedicated wiring test, cover via `AcpLaunchPlan` construction in this file's comments and a unit assert in the Cursor registry test: `capabilityToPlan(cap)!.authenticateMethodId == 'cursor_login'`. Add that expect to `cursor_registry_acp_test.dart` after wiring exists.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_connection_test.dart`

Expected: FAIL — `authenticateMethodId` named arg missing.

- [ ] **Step 3: Implement**

`AcpAgentConnection.initialize` add optional `String? authenticateMethodId`. After caching capabilities, if non-null:

```dart
await _client.client.authenticate(
  acpd.AuthenticateRequest(methodId: authenticateMethodId),
  timeout: timeout,
);
```

`AcpLaunchPlan` add `this.authenticateMethodId` (`String?`, default null).

`capabilityToPlan`:

```dart
authenticateMethodId: capability.authenticateMethodId,
```

`productionAcpSpawner` after creating the connection, pass:

```dart
authenticateMethodId:
    registry.capability<AcpCapability>(tool)?.authenticateMethodId,
```

into `connection.initialize(...)`.

Authenticate errors must **not** become `AcpFlagRejected` (already true: only non-zero process exit before handshake is flag-rejected).

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_connection_test.dart test/services/cli/cursor/cursor_registry_acp_test.dart test/services/acp/acp_session_runtime_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_connection.dart \
  client/lib/services/acp/acp_session_runtime.dart \
  client/lib/cubits/session/acp/acp_launch_wiring.dart \
  client/test/services/acp/acp_connection_test.dart \
  client/test/services/cli/cursor/cursor_registry_acp_test.dart
git commit -m "$(cat <<'EOF'
feat: authenticate ACP agents that declare a login method

Cursor requires cursor_login after initialize; Gemini and Claude skip
the call so their handshakes stay initialize-only.
EOF
)"
```

---

### Task 6: Extension codecs (parse / encode)

**Files:**
- Create: `client/lib/services/acp/acp_client_extensions.dart`
- Test: `client/test/services/acp/acp_client_extensions_test.dart`

This file owns types + codecs only. No process, no cubit.

Types:

```dart
sealed class AcpPendingClientRequest {
  const AcpPendingClientRequest();
}

final class AcpPendingPermission extends AcpPendingClientRequest {
  const AcpPendingPermission(this.request);
  final AgentPermissionRequest request;
}

final class AcpPendingAsk extends AcpPendingClientRequest {
  const AcpPendingAsk({required this.questions, required this.toolCallId});
  final List<AiAskUserQuestion> questions;
  final String toolCallId;
}

final class AcpPendingPlan extends AcpPendingClientRequest {
  const AcpPendingPlan({
    required this.toolCallId,
    required this.planText,
    this.name,
    this.overview,
  });
  final String toolCallId;
  final String planText;
  final String? name;
  final String? overview;
}

sealed class AcpHoldReply {
  const AcpHoldReply();
}

final class AcpPermissionHoldReply extends AcpHoldReply { /* existing kind + always */ }
final class AcpAskHoldReply extends AcpHoldReply {
  const AcpAskHoldReply.answered(this.submission) : skipped = false, cancelled = false;
  const AcpAskHoldReply.skipped() : submission = null, skipped = true, cancelled = false;
  const AcpAskHoldReply.cancelled() : submission = null, skipped = false, cancelled = true;
  final AiAskUserSubmission? submission;
  final bool skipped;
  final bool cancelled;
}
final class AcpPlanHoldReply extends AcpHoldReply {
  const AcpPlanHoldReply.accepted() : rejected = false, cancelled = false, reason = null;
  const AcpPlanHoldReply.rejected([this.reason]) : rejected = true, cancelled = false;
  const AcpPlanHoldReply.cancelled() : rejected = false, cancelled = true, reason = null;
  final bool rejected;
  final bool cancelled;
  final String? reason;
}

sealed class AcpExtensionNotification {
  const AcpExtensionNotification();
}

final class AcpTodoListNotification extends AcpExtensionNotification {
  const AcpTodoListNotification({required this.todos, required this.merge});
  final List<AiTodoItem> todos;
  final bool merge;
}

final class AcpTaskNotification extends AcpExtensionNotification {
  const AcpTaskNotification({
    required this.toolCallId,
    required this.description,
    required this.subagentType,
  });
  final String toolCallId;
  final String description;
  final String subagentType;
}

final class AcpGeneratedImageNotification extends AcpExtensionNotification {
  const AcpGeneratedImageNotification({
    required this.toolCallId,
    required this.description,
    this.filePath,
  });
  final String toolCallId;
  final String description;
  final String? filePath;
}
```

Functions:

- `AcpPendingClientRequest? parseCursorBlockingRequest(String method, Map<String, Object?> params)`
- `Map<String, Object?> encodeCursorBlockingReply(String method, AcpHoldReply reply, {required List<AiAskUserQuestion> questions})`
- `AcpExtensionNotification? parseCursorNotification(String method, Map<String, Object?> params)`

Ask parse: `toolCallId` string; `parseQuestionsList(params['questions'])`. Null if no valid questions.

Ask encode answered: for each question index `i`, `questionId` = `questions[i].id ?? 'q$i'`; `selectedOptionIds` from `submission.answers[i]` mapped through option `id` else label. Skipped → `{outcome: skipped}`. Cancelled → `{outcome: cancelled}`. Wrap as `{outcome: {…}}` matching Cursor docs (`CursorAskQuestionResponse.outcome` is nested).

Plan parse: `toolCallId`, `plan` as `planText` (empty plan → null). Encode accepted/rejected/cancelled the same nested `outcome` shape.

Todos: keep raw `{id, content, status}` plus `merge` (fold later writes `AiToolCallPart` args).

Task: `toolCallId`, `description`, `subagentType` string (if map `{custom: x}` use `x`).

Image: `toolCallId`, `description`, optional `filePath`.

- [ ] **Step 1: Write the failing tests**

```dart
// client/test/services/acp/acp_client_extensions_test.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';

void main() {
  test('parses ask_question and encodes answered option ids', () {
    final pending = parseCursorBlockingRequest('cursor/ask_question', {
      'toolCallId': 'call_1',
      'questions': [
        {
          'id': 'q1',
          'prompt': 'Mode?',
          'options': [
            {'id': 'agent', 'label': 'Agent'},
            {'id': 'plan', 'label': 'Plan'},
          ],
        },
      ],
    });
    expect(pending, isA<AcpPendingAsk>());
    final ask = pending! as AcpPendingAsk;
    expect(ask.toolCallId, 'call_1');
    expect(ask.questions.single.id, 'q1');

    final encoded = encodeCursorBlockingReply(
      'cursor/ask_question',
      AcpAskHoldReply.answered(
        const AiAskUserSubmission(
          answers: [
            ['Agent'],
          ],
          optionIndices: [0],
        ),
      ),
      questions: ask.questions,
    );
    expect(encoded['outcome'], {
      'outcome': 'answered',
      'answers': [
        {
          'questionId': 'q1',
          'selectedOptionIds': ['agent'],
        },
      ],
    });
  });

  test('empty plan is not a pending request', () {
    expect(
      parseCursorBlockingRequest('cursor/create_plan', {
        'toolCallId': 'c',
        'plan': '',
      }),
      isNull,
    );
  });

  test('parses update_todos merge flag', () {
    final note = parseCursorNotification('cursor/update_todos', {
      'todos': [
        {'id': '1', 'content': 'A', 'status': 'pending'},
      ],
      'merge': true,
    });
    expect(note, isA<AcpTodoListNotification>());
    expect((note! as AcpTodoListNotification).merge, isTrue);
  });
}
```

Also add cases: skipped/cancelled ask, accepted/rejected plan, custom `{custom: explore}` subagentType.

- [ ] **Step 2: Run** `cd client && dart run tool/run_tests.dart test/services/acp/acp_client_extensions_test.dart`

Expected: FAIL — library missing.

- [ ] **Step 3: Implement the file** (keep under ~400 lines; if larger, split notifications into the same library's bottom section, not a third file unless needed).

- [ ] **Step 4: Run tests** — Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_client_extensions.dart \
  client/test/services/acp/acp_client_extensions_test.dart
git commit -m "$(cat <<'EOF'
feat: codec Cursor ACP ask, plan, todo, task, and image payloads

Blocking methods need exact JSON-RPC replies or the agent hangs;
notifications fold into the existing chat message parts.
EOF
)"
```

---

### Task 7: Register extensions on `AcpAgentSession`

**Files:**
- Modify: `client/lib/services/acp/acp_session.dart`
- Modify: `client/lib/services/acp/acp_session_runtime.dart` (`AcpSessionRuntimeApi`: `answerAsk`, `answerPlan`, `cancel` already exists)
- Test: `client/test/services/acp/acp_session_test.dart`

Keep permission handling. Change the hold gate type from `_PermissionReply` to `AcpHoldReply`. Permission wait/complete wrap `AcpPermissionHoldReply`. `staleReply` / timeout / dispose → cancelled-equivalent (permission: reject; ask/plan: `AcpAskHoldReply.cancelled()` / `AcpPlanHoldReply.cancelled()` — because one gate cannot know the method, use a dedicated `AcpHoldReply.cancelled()` singleton that **every** encoder maps to `{outcome: cancelled}` / permission cancelled).

Add `const AcpCancelledHoldReply()` as the shared stale/timeout value. Permission `_outcomeFor` treats it like reject. Ask/plan encoders treat it as cancelled.

Constructor: for each `connection.translator.blockingClientMethods`, `onRequest(method, ...)`. For each notification method, `onNotification(method, ...)` and push onto `updates` as new `AcpSessionUpdate` wrappers **or** a parallel `extensionNotifications` stream. Prefer adding these three notifications to `AcpSessionUpdate`:

```dart
final class AcpTodoListUpdate extends AcpSessionUpdate { ... }
final class AcpTaskUpdate extends AcpSessionUpdate { ... }
final class AcpGeneratedImageUpdate extends AcpSessionUpdate { ... }
```

Put those three classes in `acp_client_extensions.dart` extending `AcpSessionUpdate` (import `acp_session.dart`). Avoid growing `acp_session.dart` with class bodies.

Also emit `AcpPendingAsk` / `AcpPendingPlan` on a new `Stream<AcpPendingClientRequest> clientRequests` (permission continues on `permissionRequests` so existing tests pass). Cubit in Task 8 listens to both.

`answerAsk` / `answerPlan` on the session call `_gate.complete` with the matching hold reply. `cancel()` already exists — also `complete` cancelled if a waiter is held.

- [ ] **Step 1: Write failing session tests** (mock agent like existing permission tests):

1. Agent `cursor/ask_question` during prompt → clientRequests emits questions; `answerAsk(answered)` → agent sees nested answered outcome with option ids.
2. `cancel()` while ask held → agent sees cancelled.
3. `cursor/create_plan` → `answerPlan(accepted)`.
4. `cursor/update_todos` notification → `updates` contains `AcpTodoListUpdate`.
5. Gemini translator (empty method lists) → extra handlers not registered; existing permission tests still pass.

- [ ] **Step 2: Run** `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_test.dart`

Expected: FAIL — methods / update types missing.

- [ ] **Step 3: Implement registration in `AcpAgentSession` constructor.** Extract handler bodies to functions in `acp_client_extensions.dart` (e.g. `handleCursorBlockingRequest`) so `acp_session.dart` only loops method names.

Thread `AcpSessionRuntime.answerAsk` / `answerPlan` through to the open session. Add no-op / recording stubs on every `AcpSessionRuntimeApi` fake:

- `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` (`_FakeAcpRuntime`)
- `client/test/pages/chat/acp_permission_card_test.dart`
- `client/test/pages/chat/session_chat_view_acp_test.dart`
- `client/test/pages/home_workspace/workspace/workspace_landing_prompt_delivery_test.dart`
- `client/test/services/chat/launch/session_launch_acp_attach_test.dart` (`_RecordingAcpRuntime`)

- [ ] **Step 4: Run** `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_test.dart test/services/acp/acp_session_runtime_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: compile errors on fakes until Step 3 adds stubs; then PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_session.dart \
  client/lib/services/acp/acp_session_runtime.dart \
  client/lib/services/acp/acp_client_extensions.dart \
  client/test/services/acp/acp_session_test.dart \
  client/test/services/acp/acp_session_runtime_test.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat: handle Cursor ACP blocking and notification extension methods

Ask and plan requests must be answered on the JSON-RPC connection or
the Cursor agent waits forever; todos/task/image ride the update stream.
EOF
)"
```

---

### Task 8: Cubit pending slot + fold helper

**Files:**
- Create: `client/lib/services/acp/acp_chat_extension_fold.dart`
- Test: `client/test/services/acp/acp_chat_extension_fold_test.dart`
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Fold API (pure). There is no `AiImagePart`; store everything as `AiToolCallPart` so existing tool chrome / `TodoWrite` resolver can render it:

```dart
List<AiMessage> foldAcpExtensionNotification({
  required List<AiMessage> messages,
  required AcpSessionUpdate update,
  required String Function() newId,
})
```

- `AcpTodoListUpdate`: upsert tip assistant `AiToolCallPart(toolName: 'TodoWrite', category: AiToolCallCategory.task, status: complete, args: {'todos': ...})`. `merge: true` concatenates todos by `id` (keep previous content when the incoming item omits it); `false` replaces `args['todos']`.
- `AcpTaskUpdate`: append `AiToolCallPart(toolCallId, toolName: subagentType, category: subagent, args: {'description': description}, status: complete)`.
- `AcpGeneratedImageUpdate`: append `AiToolCallPart(toolCallId, toolName: 'generate_image', status: complete, args: {'description': description, if filePath != null 'filePath': filePath})`.
- Other updates: return `messages` unchanged.

Cubit:

- Subscribe to `clientRequests` in `start` (alongside permissions).
- Replace `pendingPermission` with `AcpPendingClientRequest? pendingClient`. Add getter:

```dart
AgentPermissionRequest? get pendingPermission {
  final pending = pendingClient;
  return pending is AcpPendingPermission ? pending.request : null;
}
```

Keep `copyWith(pendingPermission: …)` working by mapping onto `pendingClient` **or** update all three existing tests to `pendingClient`. Prefer a `pendingClient` field + the getter so permission tests that read `pendingPermission` still compile.

- `_onPermissionRequest` emits `AcpPendingPermission(request)`.
- `_onClientRequest` emits ask/plan variants; attention `waiting`.
- `answerAsk` / `answerPlan` / existing `answerPermission` / `cancelTurn` clear `pendingClient`. `cancelTurn` must call runtime.cancel (already) which completes the hold.
- `_onUpdate` cases for the three new updates call `foldAcpExtensionNotification` then persist (todos/task/image are committed).
- `_endTurn` / `_endWith` clear `pendingClient`.

Do not add more than thin emit/delegate methods to the cubit.

- [ ] **Step 1: Failing fold tests + cubit tests** for ask pending, cancelTurn clears ask, todo merge vs replace.

- [ ] **Step 2: Run** `cd client && dart run tool/run_tests.dart test/services/acp/acp_chat_extension_fold_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement helper + cubit wiring**

- [ ] **Step 4: Run same tests** — Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_chat_extension_fold.dart \
  client/test/services/acp/acp_chat_extension_fold_test.dart \
  client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat: fold Cursor ACP extensions into the ACP chat document

Ask/plan occupy the same pending slot as permissions; todos and images
commit as message parts so reopen shows them from acp-transcript.jsonl.
EOF
)"
```

---

### Task 9: Compose cards

**Files:**
- Create: `client/lib/pages/chat/acp_ask_card.dart`
- Create: `client/lib/pages/chat/acp_plan_card.dart`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart`
- Test: `client/test/pages/chat/acp_ask_card_test.dart`
- Test: `client/test/pages/chat/acp_plan_card_test.dart`
- Modify: `client/test/pages/chat/session_chat_view_acp_test.dart` if compose is covered there

`AcpAskCard`: wrap `AiAskUserQuestionCard` in `AiMessageStringsScope` like `AcpPermissionCard`. `onSubmit` → `runtime.answerAsk(AcpAskHoldReply.answered(submission))`. `onCancel` → `answerAsk(skipped)`. `onAnswerInTerminal` → `runtime.cancelTurn`.

`AcpPlanCard`: `AiExitPlanModeCard(planText: …, onApprove: answerPlan(accepted), onReject: answerPlan(rejected), onOpenTerminal: cancelTurn, onOpenPlanFile: (_) {})`.

Compose: change `acpPending` select to `AcpPendingClientRequest?`. Switch:

```dart
switch (acpPending) {
  case AcpPendingPermission(:final request):
    AcpPermissionCard(runtime: acpRuntime!, pendingPermission: request);
  case AcpPendingAsk(:final questions):
    AcpAskCard(runtime: acpRuntime!, questions: questions);
  case AcpPendingPlan(:final planText):
    AcpPlanCard(runtime: acpRuntime!, planText: planText);
  case null:
    AgentPermissionAttentionBanner(...);
}
```

`acpPermissionWaiting` is true for any non-null `acpPending` (locks compose the same way).

- [ ] **Step 1: Widget tests** mirroring `acp_permission_card_test.dart` (pump card, tap submit/approve, assert cubit/runtime received reply). Use the existing post-frame harness if permission tests do.

- [ ] **Step 2: Run** `cd client && dart run tool/run_tests.dart test/pages/chat/acp_ask_card_test.dart test/pages/chat/acp_plan_card_test.dart test/pages/chat/acp_permission_card_test.dart test/pages/chat/session_chat_view_acp_test.dart`

Expected: FAIL on new files.

- [ ] **Step 3: Implement widgets + compose switch**

- [ ] **Step 4: Re-run** — Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/acp_ask_card.dart \
  client/lib/pages/chat/acp_plan_card.dart \
  client/lib/pages/chat/session_chat_compose_section.dart \
  client/test/pages/chat/acp_ask_card_test.dart \
  client/test/pages/chat/acp_plan_card_test.dart \
  client/test/pages/chat/session_chat_view_acp_test.dart
git commit -m "$(cat <<'EOF'
feat: show Cursor ACP ask and plan cards in the compose slot

Blocking extension methods reuse the existing ask-user and plan chrome
so the agent is not left waiting on an unanswered JSON-RPC request.
EOF
)"
```

---

### Task 10: Settings switch

**Files:**
- Modify: `client/lib/pages/config/cli_config_section.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart`

Extract a private or public `PersonalAcpSettingsRow` parameterized by:

- `Key switchKey`
- `String label` / `String description` / Android description
- `bool value`
- `ValueChanged<bool>? onChanged` (null on Android)
- optional `Widget? trailing` (Claude adapter button; Cursor omits)

`_buildCliRow`:

```dart
if (cli == CliTool.claude) {
  return Column(..., [pathRow, ClaudePersonalAcpSettingsRow(...)]);
}
if (cli == CliTool.cursor) {
  return Column(..., [pathRow, CursorPersonalAcpSettingsRow(...)]);
}
```

Those two named widgets can be thin wrappers around the shared row. This is the existing per-CLI extra-row switch — do not put it in feature code.

`AppKeys.cursorPersonalAcpSwitch = Key('cursor-personal-acp-switch')`.

Tests: copy the three Claude switch tests for Cursor (default on, toggle off, Android disabled + `claudePersonalAcpAndroidDisabled` copy). Cursor row must **not** show the adapter install button.

- [ ] **Step 1: Write failing widget tests** looking up `AppKeys.cursorPersonalAcpSwitch`.

- [ ] **Step 2: Run** `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name="Cursor ACP"`

Expected: FAIL — key not found.

- [ ] **Step 3: Implement row + `_buildCliRow` branch**

- [ ] **Step 4: Run full** `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`

Expected: PASS (Claude tests still pass).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/cli_config_section.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "$(cat <<'EOF'
feat: add Cursor personal ACP settings switch

New personal Cursor sessions follow the same desktop-only ACP default
as Claude, without an adapter install button.
EOF
)"
```

---

### Task 11: Frame-log redaction + landing draft coverage

**Files:**
- Modify: `client/lib/services/acp/acp_frame_logger.dart`
- Test: `client/test/services/acp/acp_frame_logger_test.dart`
- Test: `client/test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart` (add Cursor cases or a sibling file `unbound_compose_cursor_acp_test.dart`)

- [ ] **Step 1: Failing tests**

Frame logger: outgoing JSON `"CURSOR_API_KEY": "secret"` and stderr `CURSOR_AUTH_TOKEN=secret` redact; secret must not appear.

Landing: with `cursorPersonalAcpDefault: true` and selected CLI Cursor, create request / draft `acp` is true on desktop. With Claude preference false and Cursor preference true, Cursor draft stays true (the coupling bug). Follow the existing unbound compose test harness.

- [ ] **Step 2: Run** `cd client && dart run tool/run_tests.dart test/services/acp/acp_frame_logger_test.dart test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart test/pages/home_workspace/workspace/unbound_compose_cursor_acp_test.dart`

Expected: FAIL on redaction / new compose file.

- [ ] **Step 3: Extend `_redact`** with quoted + env patterns for `CURSOR_API_KEY` and `CURSOR_AUTH_TOKEN` (same style as Gemini). Landing already uses `readPersonalAcpDefault` from Task 1 — this task only adds the Cursor compose test if Task 1 did not.

- [ ] **Step 4: Run tests** — Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_frame_logger.dart \
  client/test/services/acp/acp_frame_logger_test.dart \
  client/test/pages/home_workspace/workspace/unbound_compose_cursor_acp_test.dart
git commit -m "$(cat <<'EOF'
fix: redact Cursor ACP credentials and cover landing ACP drafts

Frame logs must not keep CURSOR_API_KEY values, and landing must honor
the Cursor preference independently of Claude's switch.
EOF
)"
```

---

### Task 12: Analyze + targeted tests (no full suite until the end)

- [ ] **Step 1:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues in files touched. Fix any new analyzer errors (missing stubs on `AcpSessionRuntimeApi` fakes are the usual leftovers).

- [ ] **Step 2:** Run the ACP/Cursor slice:

```
cd client && dart run tool/run_tests.dart \
  test/services/cli/cursor/ \
  test/services/acp/ \
  test/cubits/chat/acp/ \
  test/pages/chat/acp_ \
  test/pages/chat/session_chat_view_acp_test.dart \
  test/pages/config/cli_config_section_test.dart \
  test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart \
  test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart \
  test/models/session_preferences_test.dart \
  test/cubits/session_preferences_cubit_test.dart
```

Expected: PASS

- [ ] **Step 3:** Full suite once, in the background, before claiming done:

```
cd client && dart run tool/run_tests.dart
```

- [ ] **Step 4:** Manual desktop check (not CI): personal Cursor, switch on → ACP chat, login, permission, ask_question, plan card, MCP from isolated `.cursor/mcp.json`; switch off → new session is PTY; old PTY Cursor sessions unchanged.

---

## Self-review (spec coverage)

| Spec requirement | Task |
|------------------|------|
| `cursorPersonalAcpDefault` default true | 1 |
| `resolveLaunchAcp` Claude or Cursor, not Gemini | 1 |
| Landing reads selected CLI preference | 1, 11 |
| Generic `acpLaunchFailedVersion` | 2 |
| `cursor-agent acp` argv, preserve HOME | 3 |
| Register on `CursorCliTool` | 4 |
| `authenticate` / `cursor_login` | 5 |
| Five extension methods, blocking must reply | 6–9 |
| One pending slot permission/ask/plan | 8–9 |
| Fold todos/task/image; persist on commit | 8 |
| Settings switch, no adapter button, Android disabled | 10 |
| No `session/load`, no team, no SSH | out of scope (no tasks) |
| Frame log redaction | 11 |
| Cubit/session file-size extracts | 6–8 |
