# Codex ACP Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let personal Codex sessions opt into ACP chat via `codex-acp` while PTY Codex stays the default; team sessions stay PTY.

**Architecture:** Reuse the CLI-agnostic ACP stack (`AcpSessionRuntime`, `AcpChatRuntimeCubit`, permission card, app-owned transcript). `CodexCliTool` declares `CodexAcpCapability` (spawn `codex-acp`, not `codex` / not `codex app-server`). `AppSession.acp` remains the session fact. Preference `codexPersonalAcpDefault` (default false) only seeds new personal launches. Credentials reuse PTY `contributeLaunch` / `CodexHomeProvisioner`; `buildEnvironment` only patches env (`CODEX_HOME`, `CODEX_PATH`, key inject/blank).

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, `AcpProcessTransport` (`Process.start`, no PTY), npm installer for `@agentclientprotocol/codex-acp`, existing `AgentPermissionRequest` card.

**Spec:** `docs/superpowers/specs/2026-10-12-codex-acp-session-design.md`

## Global Constraints

- Desktop-local only. No `SshExecTransport`, no Android ACP UI (hide/disable the switch when `Platform.isAndroid`).
- No `CliTool.codexAcp`. Never spawn `codex --acp` or talk to `codex app-server` from TeamPilot. ACP argv is the adapter binary only.
- Team sessions: `createSession` / `resolveLaunchAcp` force `acp = false`.
- Official ChatGPT login: never inject `OPENAI_API_KEY` / `CODEX_API_KEY` (empty-string unset so `mergeAcpProcessEnvironment` drops them). Isolate `CODEX_HOME` under `sessionToolDir` (`…/runtime/codex`).
- Handshake / missing adapter must not fall back to PTY for that connect.
- Connect never auto-installs the adapter. Install is user-initiated from settings.
- User copy → `app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- No `if (cli == …)` in `services/acp/` or the connect executor. Codex-only behavior lives in `services/cli/codex/` plus the existing Claude/Codex settings/compose gates.
- `CodexExecutableCapability.npmPackage` stays `@openai/codex`.
- Do not generalize Claude+Codex preferences into one per-CLI map. Two bool fields.
- Do not advertise `fs/*` / `terminal/*`. Do not set `INITIAL_AGENT_MODE`.
- Do not read `$CODEX_HOME/sessions/**/rollout-*.jsonl` for `session.acp` rows.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_preferences.dart` | `codexPersonalAcpDefault` |
| `client/lib/cubits/session_preferences_cubit.dart` | setter |
| `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart` | `resolveLaunchAcp` allows Codex; `readCodexPersonalAcpDefault` |
| `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` | pick Claude vs Codex preference at create |
| `client/lib/services/cli/codex/capabilities/acp.dart` | translator + capability + auth types |
| `client/lib/services/cli/codex/capabilities/acp_adapter_installer.dart` | npm adapter install + locator |
| `client/lib/services/cli/codex/codex_tool.dart` | register `AcpCapability` |
| `client/lib/services/cli/codex/codex_bootstrap_entry.dart` | `acpAuthSource`, `codexPathSource`, pick/auth helpers |
| `client/lib/services/cli/registry/built_in_cli_tools.dart` | wire Codex ACP capability |
| `client/lib/services/install/install_job_keys.dart` | `codexAcpAdapter()` |
| `client/lib/services/install/install_job_enqueue.dart` | `installCodexAcpAdapter` |
| `client/lib/services/install/runners/cli_install_job_runner.dart` | run Codex adapter jobs |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Codex ACP copy |
| `client/lib/services/chat/launch/session_launch_host.dart` | `acpChatStrings(CliTool)` |
| `client/lib/cubits/chat_cubit.dart` | resolver takes `CliTool` |
| `client/lib/services/chat/launch/session_launch_service.dart` | `ensureStrings` with `cli` |
| `client/lib/app/app_shell.dart` | Codex provider cache + CLI-aware strings |
| `client/lib/pages/config/cli_config_section.dart` | Codex settings row |
| `client/lib/utils/ui/app_keys.dart` | Codex ACP widget keys |

---

### Task 1: `codexPersonalAcpDefault` preference

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Test: `client/test/models/session_preferences_test.dart`
- Test: `client/test/cubits/session_preferences_cubit_test.dart`

**Interfaces:**
- Consumes: existing `SessionPreferences` constructor / `fromJson` / `copyWith` / `toJson`
- Produces: `SessionPreferences.codexPersonalAcpDefault` (`bool`, default `false`). Omitted JSON key → `false`. `SessionPreferencesCubit.setCodexPersonalAcpDefault(bool value)`.

- [ ] **Step 1: Write the failing tests**

Add to `client/test/models/session_preferences_test.dart`:

```dart
test('codexPersonalAcpDefault defaults false and round-trips', () {
  expect(SessionPreferences().codexPersonalAcpDefault, isFalse);
  expect(
    SessionPreferences.fromJson(const {}).codexPersonalAcpDefault,
    isFalse,
  );
  final on = SessionPreferences(codexPersonalAcpDefault: true);
  expect(on.toJson()['codexPersonalAcpDefault'], isTrue);
  expect(
    SessionPreferences.fromJson(on.toJson()).codexPersonalAcpDefault,
    isTrue,
  );
  final claude = SessionPreferences(claudePersonalAcpDefault: false);
  expect(claude.codexPersonalAcpDefault, isFalse);
});
```

Add to `client/test/cubits/session_preferences_cubit_test.dart` next to `setClaudePersonalAcpDefault`:

```dart
test('setCodexPersonalAcpDefault persists the flag', () async {
  final cubit = await makeCubit();
  await cubit.load();
  expect(cubit.state.preferences.codexPersonalAcpDefault, false);

  await cubit.setCodexPersonalAcpDefault(true);
  expect(cubit.state.preferences.codexPersonalAcpDefault, true);

  final cubit2 = await makeCubit();
  await cubit2.load();
  expect(cubit2.state.preferences.codexPersonalAcpDefault, true);
  expect(cubit2.state.preferences.claudePersonalAcpDefault, true);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart --plain-name "codexPersonalAcpDefault"`

Expected: FAIL — `codexPersonalAcpDefault` is not defined.

- [ ] **Step 3: Add the field and setter**

In `SessionPreferences`:
- Constructor arg `this.codexPersonalAcpDefault = false`
- `fromJson`: `json['codexPersonalAcpDefault'] as bool? ?? false`
- Field + dartdoc: when true, new personal Codex sessions launch as ACP chat. Default false. Existing sessions keep the runtime they started with.
- `copyWith` + `toJson` include the field.

In `SessionPreferencesCubit`:

```dart
Future<void> setCodexPersonalAcpDefault(bool value) {
  return _save(state.preferences.copyWith(codexPersonalAcpDefault: value));
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart`

Expected: PASS. Claude preference tests still pass.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart \
  client/lib/cubits/session_preferences_cubit.dart \
  client/test/models/session_preferences_test.dart \
  client/test/cubits/session_preferences_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat: add Codex personal ACP preference default

New personal Codex sessions can opt into ACP later; persist the flag off by default so existing PTY behavior is unchanged.
EOF
)"
```

---

### Task 2: `resolveLaunchAcp` allows personal Codex

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` (the `LandingLaunchContext.acp:` assignment)
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`
- Test: `client/test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart`

**Interfaces:**
- Consumes: `SessionPreferences.codexPersonalAcpDefault` (Task 1), existing `resolveLaunchAcp({required bool isPersonal, required CliTool? cli, required bool requested, bool? isAndroidOverride})`
- Produces: `resolveLaunchAcp` returns true for personal desktop Claude **or** Codex when `requested` is true. `readCodexPersonalAcpDefault(BuildContext)` (missing cubit → `false`). `readPersonalAcpDefault(BuildContext, CliTool?)` picks Claude / Codex / false.

- [ ] **Step 1: Write the failing tests**

Add to `claude_acp_launch_switch_test.dart`:

```dart
test('true for personal Codex when requested on desktop', () {
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.codex,
      requested: true,
      isAndroidOverride: false,
    ),
    isTrue,
  );
});

test('false for Codex team, not requested, or Android', () {
  expect(
    resolveLaunchAcp(
      isPersonal: false,
      cli: CliTool.codex,
      requested: true,
      isAndroidOverride: false,
    ),
    isFalse,
  );
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.codex,
      requested: false,
      isAndroidOverride: false,
    ),
    isFalse,
  );
  expect(
    resolveLaunchAcp(
      isPersonal: true,
      cli: CliTool.codex,
      requested: true,
      isAndroidOverride: true,
    ),
    isFalse,
  );
});
```

Add a create-request case:

```dart
test('personal Codex with ACP requested sets request.acp', () {
  final request = buildWorkspaceConversationCreateRequest(
    workspace: workspace,
    isPersonal: true,
    cli: CliTool.codex,
    acp: true,
    isAndroidOverride: false,
  );
  expect(request.acp, isTrue);
});
```

In `unbound_compose_claude_acp_test.dart`, extend `pumpCompose` so the mock preferences include `codexPersonalAcpDefault` (add a named arg `codexPreferenceDefault` defaulting to `false`). Add:

```dart
testWidgets('Codex submit uses the Codex settings default', (tester) async {
  final submitted = <LandingLaunchContext>[];
  await pumpCompose(
    tester,
    cli: CliTool.codex,
    preferenceDefault: false,
    codexPreferenceDefault: true,
    submitted: submitted,
  );
  await submit(tester);
  expect(submitted.single.acp, isTrue);
});

testWidgets('Codex submit ignores the Claude ACP default', (tester) async {
  final submitted = <LandingLaunchContext>[];
  await pumpCompose(
    tester,
    cli: CliTool.codex,
    preferenceDefault: true,
    codexPreferenceDefault: false,
    submitted: submitted,
  );
  await submit(tester);
  expect(submitted.single.acp, isFalse);
});
```

Keep the existing Claude submit tests using `preferenceDefault` (Claude field) unchanged.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart --plain-name "personal Codex"`

Expected: FAIL — `resolveLaunchAcp` still returns false for Codex.

- [ ] **Step 3: Implement the gate and compose read**

Replace `_personalClaudeAcpAllowed` in `claude_acp_launch_switch.dart`:

```dart
bool _personalAdapterAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) =>
    isPersonal &&
    (cli == CliTool.claude || cli == CliTool.codex) &&
    !_isAndroid(isAndroidOverride);

bool resolveLaunchAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) =>
    requested &&
    _personalAdapterAcpAllowed(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    );

bool readCodexPersonalAcpDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .codexPersonalAcpDefault;
  } on ProviderNotFoundException {
    return false;
  }
}

bool readPersonalAcpDefault(BuildContext context, CliTool? cli) {
  if (cli == CliTool.claude) return readClaudePersonalAcpDefault(context);
  if (cli == CliTool.codex) return readCodexPersonalAcpDefault(context);
  return false;
}
```

Update the file's dartdoc: `requested` counts for personal Claude **or** Codex on desktop.

In `unbound_compose_body.dart` `_currentDraft()`:

```dart
acp: resolveLaunchAcp(
  isPersonal: isSimple,
  cli: launchCli,
  requested: readPersonalAcpDefault(context, launchCli),
),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart`

Expected: PASS. Claude compose still reads the Claude preference. Gemini still does not use this function (create infers ACP).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart \
  client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart \
  client/test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart
git commit -m "$(cat <<'EOF'
feat: allow personal Codex launches to persist AppSession.acp

Extend the existing desktop personal ACP gate so Codex can opt in at create without touching Gemini or team sessions.
EOF
)"
```

---

### Task 3: `CodexAcpCapability`

**Files:**
- Create: `client/lib/services/cli/codex/capabilities/acp.dart`
- Test: `client/test/services/cli/codex/codex_acp_capability_test.dart`

**Interfaces:**
- Consumes: `AcpCapability`, `AcpAgentTranslator`, `isOfficialCodexOAuthProvider` (later used by bootstrap; this task only consumes `CodexAcpAuth`)
- Produces:

```dart
typedef CodexAcpAuthSource = CodexAcpAuth Function();

class CodexAcpAuth {
  const CodexAcpAuth({this.apiKey, this.official = false});
  final String? apiKey;
  final bool official;
}

final class CodexAcpTranslator implements AcpAgentTranslator { ... }

final class CodexAcpCapability implements AcpCapability {
  const CodexAcpCapability({
    CodexAcpAuthSource? authSource,
    String Function(String cliExecutable)? locateAdapter,
    String Function()? codexPathSource,
  });
  static const adapterName = 'codex-acp';
  String agentExecutable(String cliExecutable);
  List<List<String>> launchArgCandidates(String executable); // [[executable]]
  AcpAgentTranslator get translator;
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  });
}
```

`buildEnvironment` is **sync**. It does not call `CodexHomeProvisioner`.

- [ ] **Step 1: Write the failing test file**

Create `client/test/services/cli/codex/codex_acp_capability_test.dart`:

```dart
import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp.dart';

Map<String, String> _env(
  CodexAcpCapability cap, {
  Map<String, String> baseEnv = const {},
}) => cap.buildEnvironment(
  sessionToolDir: '/runtime/s1/codex',
  workingDirectory: '/work',
  baseEnv: baseEnv,
);

void main() {
  test('launch argv is the adapter alone, not codex --acp', () {
    const cap = CodexAcpCapability();
    final exe = cap.agentExecutable('/usr/bin/codex');
    expect(exe, 'codex-acp');
    expect(cap.launchArgCandidates(exe), [
      ['codex-acp'],
    ]);
  });

  test('agentExecutable uses locateAdapter and ignores cli path as argv', () {
    final cap = CodexAcpCapability(
      locateAdapter: (cli) {
        expect(cli, '/usr/bin/codex');
        return '/opt/adapter/codex-acp';
      },
    );
    expect(cap.agentExecutable('/usr/bin/codex'), '/opt/adapter/codex-acp');
    expect(cap.launchArgCandidates('/opt/adapter/codex-acp'), [
      ['/opt/adapter/codex-acp'],
    ]);
  });

  test('api key provider injects both key names and isolates CODEX_HOME', () {
    final cap = CodexAcpCapability(
      authSource: () => const CodexAcpAuth(apiKey: 'sk-test'),
      codexPathSource: () => '/usr/bin/codex',
    );
    final env = _env(cap, baseEnv: const {'HOME': '/home/me', 'PATH': '/bin'});
    expect(env['OPENAI_API_KEY'], 'sk-test');
    expect(env['CODEX_API_KEY'], 'sk-test');
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_PATH'], '/usr/bin/codex');
    expect(env['HOME'], '/home/me');
    expect(env.containsKey('SURFACE'), isFalse);
    expect(env.containsKey('INITIAL_AGENT_MODE'), isFalse);
  });

  test('official blanks keys even when auth or parent env has them', () {
    final cap = CodexAcpCapability(
      authSource: () => const CodexAcpAuth(
        official: true,
        apiKey: 'should-not-leak',
      ),
      codexPathSource: () => '/usr/bin/codex',
    );
    final env = _env(
      cap,
      baseEnv: const {
        'OPENAI_API_KEY': 'parent-key',
        'CODEX_API_KEY': 'parent-key',
        'CODEX_HOME': '/runtime/s1/codex',
      },
    );
    expect(env['OPENAI_API_KEY'], '');
    expect(env['CODEX_API_KEY'], '');
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_PATH'], '/usr/bin/codex');
  });

  test('PROXY_MANAGED is not injected as a real API key', () {
    final cap = CodexAcpCapability(
      authSource: () => const CodexAcpAuth(apiKey: 'PROXY_MANAGED'),
    );
    final env = _env(cap);
    expect(env['OPENAI_API_KEY'], '');
    expect(env['CODEX_API_KEY'], '');
  });

  test('no auth source blanks keys and sets CODEX_HOME plus default CODEX_PATH', () {
    const cap = CodexAcpCapability();
    final env = _env(cap, baseEnv: const {'A': 'b'});
    expect(env['A'], 'b');
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_PATH'], 'codex');
    expect(env['OPENAI_API_KEY'], '');
    expect(env['CODEX_API_KEY'], '');
  });

  test('does not nest another /codex under sessionToolDir', () {
    const cap = CodexAcpCapability();
    final env = _env(cap);
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_HOME']!.endsWith('/codex/codex'), isFalse);
  });

  test('translator formats RpcError without abort mapping', () {
    const cap = CodexAcpCapability();
    expect(cap.translator, isA<CodexAcpTranslator>());
    expect(cap.translator.flagCandidates, isEmpty);
    final abortLike = RpcError(
      code: ErrorCode.internalError.code,
      message: 'This operation was aborted',
    );
    expect(
      cap.translator.translateStopError(abortLike, suppressAbort: true),
      'ACP error ${ErrorCode.internalError.code}: This operation was aborted',
    );
    expect(
      cap.translator.translateStopError(StateError('x'), suppressAbort: false),
      StateError('x').toString(),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/codex/codex_acp_capability_test.dart`

Expected: FAIL — `acp.dart` does not exist.

- [ ] **Step 3: Implement `capabilities/acp.dart`**

```dart
import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class CodexAcpTranslator implements AcpAgentTranslator {
  const CodexAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

class CodexAcpAuth {
  const CodexAcpAuth({this.apiKey, this.official = false});

  final String? apiKey;
  final bool official;
}

typedef CodexAcpAuthSource = CodexAcpAuth Function();

final class CodexAcpCapability implements AcpCapability {
  const CodexAcpCapability({
    CodexAcpAuthSource? authSource,
    String Function(String cliExecutable)? locateAdapter,
    String Function()? codexPathSource,
  }) : _authSource = authSource,
       _locateAdapter = locateAdapter,
       _codexPathSource = codexPathSource;

  static const adapterName = 'codex-acp';
  static const _proxyManagedToken = 'PROXY_MANAGED';

  final CodexAcpAuthSource? _authSource;
  final String Function(String cliExecutable)? _locateAdapter;
  final String Function()? _codexPathSource;

  @override
  String agentExecutable(String cliExecutable) =>
      _locateAdapter?.call(cliExecutable) ?? adapterName;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const CodexAcpTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    env['CODEX_HOME'] = sessionToolDir;
    env['CODEX_PATH'] = _codexPathSource?.call() ?? 'codex';
    for (final key in _keyNames) {
      env[key] = '';
    }
    final auth = _authSource?.call();
    if (auth == null || auth.official) return env;
    final apiKey = auth.apiKey?.trim() ?? '';
    if (apiKey.isEmpty || apiKey == _proxyManagedToken) return env;
    env['OPENAI_API_KEY'] = apiKey;
    env['CODEX_API_KEY'] = apiKey;
    return env;
  }

  static const _keyNames = ['OPENAI_API_KEY', 'CODEX_API_KEY'];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/codex/codex_acp_capability_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/codex/capabilities/acp.dart \
  client/test/services/cli/codex/codex_acp_capability_test.dart
git commit -m "$(cat <<'EOF'
feat: add CodexAcpCapability for the codex-acp adapter

Declare adapter argv and env patches so Official ChatGPT login cannot inherit host API keys.
EOF
)"
```

---

### Task 4: Adapter installer, locator, and install jobs

**Files:**
- Create: `client/lib/services/cli/codex/capabilities/acp_adapter_installer.dart`
- Modify: `client/lib/services/install/install_job_keys.dart`
- Modify: `client/lib/services/install/install_job_enqueue.dart`
- Modify: `client/lib/services/install/runners/cli_install_job_runner.dart`
- Test: `client/test/services/cli/codex/codex_acp_adapter_installer_test.dart`
- Test: `client/test/services/install/runners/cli_install_job_runner_test.dart`

**Interfaces:**
- Consumes: `NpmInstallerCapability`, `CliInstallerService.installAdapter`, `CodexAcpCapability.adapterName`, `CodexExecutableCapability.npmPackage`
- Produces:

```dart
final class CodexAcpAdapterInstaller extends NpmInstallerCapability {
  static const package = '@agentclientprotocol/codex-acp';
  static const jobTarget = 'adapter:codex-acp';
  String get npmPackage => package;
  String get executableName => 'codex-acp';
  String get displayName => 'Codex ACP adapter';
}

String locateCodexAcpAdapter({
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
  bool? isWindows,
});

InstallJobKey InstallJobKeys.codexAcpAdapter();
Future<CliInstallResult> InstallJobEnqueue.installCodexAcpAdapter({required String title, ...});
```

`CliInstallJobRunner.supports` / `run` must distinguish Claude vs Codex adapter targets. Connect still never calls these.

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/cli/codex/codex_acp_adapter_installer_test.dart` cloned from `claude_acp_adapter_installer_test.dart` with these substitutions:

- `ClaudeAcpAdapterInstaller` → `CodexAcpAdapterInstaller`
- `@agentclientprotocol/claude-agent-acp` → `@agentclientprotocol/codex-acp`
- `claude-agent-acp` → `codex-acp`
- `locateClaudeAcpAdapter` → `locateCodexAcpAdapter`
- `ClaudeAcpCapability` → `CodexAcpCapability`
- `ClaudeExecutableCapability` still asserted **not** used; instead:

```dart
test('Codex CLI package is unchanged', () {
  expect(const CodexExecutableCapability().npmPackage, '@openai/codex');
});
```

The `installAdapter` test must assert commands do **not** contain `@openai/codex`.

Add to `cli_install_job_runner_test.dart` next to the Claude adapter group:

```dart
test('supports and runs the Codex ACP adapter key locally', () async {
  final service = _AdapterRecordingService();
  final runner = CliInstallJobRunner(installerFactory: () => service);
  final key = InstallJobKeys.codexAcpAdapter();

  expect(runner.supports(key), isTrue);
  final result = await runner.run(_spec(key), InstallJobContext());

  expect(result.executablePath, '/bin/codex-acp');
  expect(service.installer, isA<CodexAcpAdapterInstaller>());
  expect(service.cliInstallCalls, 0);
});
```

Extend `_AdapterRecordingService` so `installAdapter` records the installer and returns a path matching `installer.executableName` (`/bin/${installer.executableName}`). Update the existing Claude test to still expect `/bin/claude-agent-acp`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/codex/codex_acp_adapter_installer_test.dart test/services/install/runners/cli_install_job_runner_test.dart --plain-name "Codex ACP"`

Expected: FAIL — installer / job key missing.

- [ ] **Step 3: Implement installer + job plumbing**

`acp_adapter_installer.dart` — copy `claude/.../acp_adapter_installer.dart`, replace names/package/`jobTarget`/`locateClaudeAcpAdapter` → `locateCodexAcpAdapter` / binary `codex-acp`. Keep the same PATH → `~/.local/bin` → TeamPilot node prefix → bare name order. Windows returns the bare name.

`install_job_keys.dart`:

```dart
static InstallJobKey codexAcpAdapter() => const InstallJobKey(
  kind: InstallJobKind.cliExecutable,
  target: CodexAcpAdapterInstaller.jobTarget,
);
```

`install_job_enqueue.dart`: copy `installClaudeAcpAdapter` as `installCodexAcpAdapter` using `InstallJobKeys.codexAcpAdapter()`.

`cli_install_job_runner.dart`:

```dart
NpmInstallerCapability? _adapterFor(String target) {
  if (target == ClaudeAcpAdapterInstaller.jobTarget) {
    return const ClaudeAcpAdapterInstaller();
  }
  if (target == CodexAcpAdapterInstaller.jobTarget) {
    return const CodexAcpAdapterInstaller();
  }
  return null;
}

@override
bool supports(InstallJobKey key) {
  if (key.kind != kind) return false;
  return _adapterFor(key.target) != null || CliTool.tryParse(key.target) != null;
}

@override
Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
  final adapter = _adapterFor(spec.key.target);
  final cli = CliTool.tryParse(spec.key.target);
  if (adapter == null && cli == null) {
    throw StateError('Unknown CLI target: ${spec.key.target}');
  }

  final (mode, sshProfile) = _resolveInstallTarget(spec.key.scope);
  void onProgress(CliInstallProgress progress) =>
      _reportCliProgress(ctx, progress);
  final result = adapter != null
      ? await _installerFactory().installAdapter(
          installer: adapter,
          mode: mode,
          sshProfile: sshProfile,
          onProgress: onProgress,
          isCancelled: () => ctx.isCancelled,
          onProcessStarted: ctx.registerProcess,
        )
      : await _installerFactory().install(
          cli: cli!,
          mode: mode,
          sshProfile: sshProfile,
          onProgress: onProgress,
          isCancelled: () => ctx.isCancelled,
          onProcessStarted: ctx.registerProcess,
        );

  if (!result.success) {
    throw StateError(result.message);
  }
  return result as T;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/codex/codex_acp_adapter_installer_test.dart test/services/install/runners/cli_install_job_runner_test.dart`

Expected: PASS. Claude adapter job still installs `ClaudeAcpAdapterInstaller`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/codex/capabilities/acp_adapter_installer.dart \
  client/lib/services/install/install_job_keys.dart \
  client/lib/services/install/install_job_enqueue.dart \
  client/lib/services/install/runners/cli_install_job_runner.dart \
  client/test/services/cli/codex/codex_acp_adapter_installer_test.dart \
  client/test/services/install/runners/cli_install_job_runner_test.dart
git commit -m "$(cat <<'EOF'
feat: install codex-acp without changing the Codex npm package

Settings can install the ACP adapter through the existing npm job runner while @openai/codex stays the PTY CLI.
EOF
)"
```

---

### Task 5: Register capability and bootstrap auth

**Files:**
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/lib/services/cli/codex/codex_bootstrap_entry.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: `client/lib/app/app_shell.dart` (Codex bootstrap + provider cache; strings wait for Task 6)
- Test: `client/test/services/cli/codex/codex_registry_acp_test.dart`

**Interfaces:**
- Consumes: `CodexAcpCapability` (Task 3), `locateCodexAcpAdapter` (Task 4), `isOfficialCodexOAuthProvider`, `AppProviderConfig`, `CodexTomlParser.proxyManagedToken`
- Produces:

```dart
final class CodexBootstrapEntry {
  const CodexBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
    this.acpAuthSource,
    this.codexPathSource,
  });
  final CodexAcpAuthSource? acpAuthSource;
  final String Function()? codexPathSource;
}

AppProviderConfig? pickCodexAcpProvider({
  required List<AppProviderConfig> providers,
  required String? selectedId,
});

CodexAcpAuth codexAcpAuthForProvider(AppProviderConfig? provider);
```

`CodexCliTool` gains `this.acp = const CodexAcpCapability()` and includes `acp` in `capabilities`.

`registerBuiltInCliTools` wires:

```dart
acp: CodexAcpCapability(
  authSource: codexEntry?.acpAuthSource,
  locateAdapter: (_) => locateCodexAcpAdapter(),
  codexPathSource: codexEntry?.codexPathSource,
),
```

`pickCodexAcpProvider`: selected id match, else first Official Codex row (`isOfficialCodexOAuthProvider`), else null.

`codexAcpAuthForProvider`:
- null / `cli != codex` → `const CodexAcpAuth()`
- Official OAuth → `CodexAcpAuth(official: true)` (no apiKey)
- else apiKey from `config['env']['OPENAI_API_KEY']` or `provider.apiKey`; treat empty / `PROXY_MANAGED` as no key (`CodexAcpAuth()`)

App shell: `AppProviderConfig? cachedCodexProvider;` refresh via `loadProvidersFor(CliTool.codex)` + `selectedProviderIdByCli[CliTool.codex]`, same in-flight pattern as Claude. Pass:

```dart
CliTool.codex: CodexBootstrapEntry(
  credentialsService: codexCredentialsService,
  acpAuthSource: () => codexAcpAuthForProvider(cachedCodexProvider),
  codexPathSource: () =>
      sessionPreferencesCubit.resolveExecutable(CliTool.codex),
  modelsService: /* existing */,
),
```

Listen on `appProviderCubit.stream` also calls `refreshCodexProvider()`.

- [ ] **Step 1: Write the failing registry tests**

Create `client/test/services/cli/codex/codex_registry_acp_test.dart` modeled on `claude_registry_acp_test.dart`:

- `codex registers AcpCapability that spawns the adapter` — `agentExecutable` ends with `codex-acp`; argv is `[[exe]]`
- bootstrap `acpAuthSource` is not invoked at registration, is invoked at `buildEnvironment`
- Official provider → `official: true`, `apiKey == null`
- Key provider env `OPENAI_API_KEY` → `apiKey`
- `PROXY_MANAGED` / empty → empty auth
- `pickCodexAcpProvider` selected id / fallback to official / missing → official

Use `InMemoryFilesystem` + `CodexProviderCredentialsService` only if the helper needs it; `codexAcpAuthForProvider` does **not** take the credentials service (files are provisioned by `contributeLaunch`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/codex/codex_registry_acp_test.dart`

Expected: FAIL — Codex has no `AcpCapability`.

- [ ] **Step 3: Register and wire**

`CodexCliTool`: add `this.acp = const CodexAcpCapability()`, field `final CodexAcpCapability acp`, append `acp` to `capabilities`.

`codex_bootstrap_entry.dart`: add imports for `AppProviderConfig`, `acp.dart`, `codex_official_provider.dart`, `codex_toml_parser.dart`. Add the two optional closures and the two top-level functions exactly as specified in Interfaces.

`built_in_cli_tools.dart`: pass `acp:` into `CodexCliTool(...)`.

`app_shell.dart`: cache + refresh + bootstrap fields as specified. Do not change `acpChatStringsResolver` yet.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/codex/codex_registry_acp_test.dart test/services/cli/claude/claude_registry_acp_test.dart`

Expected: PASS. Claude registration unchanged.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/codex/codex_tool.dart \
  client/lib/services/cli/codex/codex_bootstrap_entry.dart \
  client/lib/services/cli/registry/built_in_cli_tools.dart \
  client/lib/app/app_shell.dart \
  client/test/services/cli/codex/codex_registry_acp_test.dart
git commit -m "$(cat <<'EOF'
feat: register Codex ACP capability with lazy provider auth

Wire Official vs API-key auth at spawn time so Codex ACP reuses the selected provider row without a second provisioner.
EOF
)"
```

---

### Task 6: l10n and CLI-aware ACP strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/services/chat/launch/session_launch_host.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/services/chat/launch/session_launch_service.dart`
- Modify: `client/lib/app/app_shell.dart` (`acpChatStringsResolver`)
- Test: `client/test/services/chat/launch/session_launch_acp_attach_test.dart`

**Interfaces:**
- Consumes: `session.cli` already in `attachAcpRuntime`
- Produces: arb keys below. Host hook becomes `AcpChatStrings? Function(CliTool tool)? acpChatStrings`. `attachAcpRuntime` calls `_h.acpChatStrings?.call(cli)`.

| Key | EN | ZH |
|-----|----|----|
| `codexPersonalAcpDefaultLabel` | Personal sessions use ACP chat | 个人会话使用 ACP 聊天 |
| `codexPersonalAcpDefaultDescription` | Run new personal Codex sessions as terminal-less ACP chat via codex-acp. Existing sessions stay as they were started. Team sessions always use the terminal. | 新建个人 Codex 会话走无终端 ACP（codex-acp）。已有会话保持原启动方式。团队会话始终用终端。 |
| `codexPersonalAcpAndroidDisabled` | ACP chat is desktop-only until remote SSH exec is available. | 在远程 SSH exec 就绪前，ACP 聊天仅限桌面。 |
| `codexAcpLaunchFailedAdapter` | Could not start the Codex ACP adapter (codex-acp). Install it and try again. | 无法启动 Codex ACP 适配器（codex-acp）。请安装后重试。 |
| `codexAcpChatNotLoggedIn` | Codex isn't logged in. Sign in with ChatGPT under Settings → Providers, or switch to an API key. | Codex 尚未登录。请到设置 → 服务商完成 ChatGPT 登录，或改用 API Key。 |

Reuse `claudeAcpAdapterInstallButton` (already generic). Do not change Gemini version-failure copy.

`app_shell.dart` resolver:

```dart
chatCubit.acpChatStringsResolver = (tool) {
  final locale = PlatformDispatcher.instance.locale;
  final l10n = lookupAppLocalizations(
    basicLocaleListResolution([locale], AppLocalizations.supportedLocales),
  );
  final adapter = tool == CliTool.codex
      ? l10n.codexAcpLaunchFailedAdapter
      : l10n.acpLaunchFailedAdapter;
  final notLoggedIn = tool == CliTool.codex
      ? l10n.codexAcpChatNotLoggedIn
      : l10n.acpChatNotLoggedIn;
  return AcpChatStrings(
    launchFailedVersion: l10n.acpLaunchFailedVersion,
    launchFailedAdapter: adapter,
    launchFailed: l10n.acpChatLaunchFailed,
    turnFailed: l10n.acpChatTurnFailed,
    processExited: l10n.acpChatProcessExited,
    notLoggedIn: notLoggedIn,
  );
};
```

- [ ] **Step 1: Write the failing attach test**

Add to `session_launch_acp_attach_test.dart`:

```dart
test('attachAcpRuntime injects Codex ACP strings for Codex sessions', () async {
  final tabStore = ChatTabStore(storage: fakeHomeStorage())
    ..setActiveWorkspaceId('w1');
  final tab = ChatTab(
    info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
    cliTeamName: '',
  );
  tabStore.registerSession(tab);
  CliTool? seenTool;
  final host = _Host(tabStore, acpStrings: (tool) {
    seenTool = tool;
    return const AcpChatStrings(
      launchFailedVersion: 'v',
      launchFailedAdapter: 'codex-adapter-missing',
      launchFailed: 'fail',
      turnFailed: 'turn',
      processExited: 'exit',
      notLoggedIn: 'codex-not-logged-in',
    );
  });
  final service = SessionLaunchService(
    host,
    storage: fakeHomeStorage(),
    acpRuntimeFactory: ({required logger, required tool}) {
      return _RecordingAcpRuntime();
    },
  );
  final session = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    cli: CliTool.codex,
    acp: true,
    createdAt: 1,
  );
  final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
  final job = SessionConnectJob(
    session: session,
    request: SessionOpenRequest(session: session, workspace: workspace),
    generation: 1,
    workspace: workspace,
    reason: LaunchReason.create,
  );

  await service.attachAcpRuntime(job, session);

  expect(seenTool, CliTool.codex);
  expect(tab.acpRuntime, isNotNull);
});
```

Give `_Host` an optional `AcpChatStrings? Function(CliTool)? acpStrings` and override `acpChatStrings` to return it. Default remains null (existing tests still use `defaultAcpChatStrings`).

Also add a contributeLaunch Codex case (can be the same test file):

```dart
test('attachAcpRuntime for Codex passes contributeLaunch env', () async {
  // same as the Claude contributeLaunch test, with cli: CliTool.codex
  // and env {'CODEX_HOME': '/runtime/s1/codex'}
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_launch_acp_attach_test.dart --plain-name "Codex"`

Expected: FAIL — `acpChatStrings` still has no `CliTool` argument, and/or arb getters missing after gen-l10n.

- [ ] **Step 3: Implement arb + signature change**

Append the five keys to both arb files (before the closing `}`).

Change:

```dart
// session_launch_host.dart
AcpChatStrings? Function(CliTool tool)? get acpChatStrings => null;

// chat_cubit.dart
AcpChatStrings? Function(CliTool tool)? get acpChatStrings =>
    _acpChatStringsResolver;
AcpChatStrings? Function(CliTool tool)? _acpChatStringsResolver;
set acpChatStringsResolver(AcpChatStrings? Function(CliTool tool)? value) =>
    _acpChatStringsResolver = value;

// session_launch_service.dart attachAcpRuntime
)..ensureStrings(_h.acpChatStrings?.call(cli) ?? defaultAcpChatStrings);
```

Update `app_shell.dart` resolver as specified.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_launch_acp_attach_test.dart`

Expected: PASS. Claude attach test still passes (resolver not used / default strings).

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/services/chat/launch/session_launch_host.dart \
  client/lib/cubits/chat_cubit.dart \
  client/lib/services/chat/launch/session_launch_service.dart \
  client/lib/app/app_shell.dart \
  client/test/services/chat/launch/session_launch_acp_attach_test.dart
git commit -m "$(cat <<'EOF'
feat: localize Codex ACP errors separately from Claude

Adapter-missing and not-logged-in copy follow session.cli so Codex users are not told to install claude-agent-acp.
EOF
)"
```

If gen-l10n files are gitignored, do not add them; tests will generate them.

---

### Task 7: Codex settings row

**Files:**
- Modify: `client/lib/pages/config/cli_config_section.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart`

**Interfaces:**
- Consumes: `setCodexPersonalAcpDefault` (Task 1), `InstallJobKeys.codexAcpAdapter` / `installCodexAcpAdapter` (Task 4), l10n keys (Task 6)
- Produces: `CodexPersonalAcpSettingsRow` + `_CodexAcpAdapterInstallButton`. Keys: `AppKeys.codexPersonalAcpSwitch`, `AppKeys.codexAcpAdapterInstallButton`. `_buildCliRow` wraps the Codex path row the same way as Claude.

- [ ] **Step 1: Write the failing widget tests**

Clone the four Claude ACP widget tests in `cli_config_section_test.dart` for Codex:

- Switch shown in the Codex CLI section (default **off** — `SwitchListTile.value` is false)
- Toggle writes `codexPersonalAcpDefault`
- Disabled on Android with `codexPersonalAcpAndroidDisabled` copy; preference stays false
- Install button records `'@agentclientprotocol/codex-acp'`
- Install button hidden on Android

Add `_wrapCodexAcpRow` parallel to `_wrapAcpRow`, pumping `CodexPersonalAcpSettingsRow`. Extend the adapter-install fake so `installCodexAcpAdapter` appends the Codex package (or branch on which method is called). If `_wrapAcpRow` stubs `installClaudeAcpAdapter` on a mock registry, add `installCodexAcpAdapter` the same way.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name "Codex ACP"`

Expected: FAIL — widgets / keys missing.

- [ ] **Step 3: Implement the settings row**

`app_keys.dart`:

```dart
static const codexPersonalAcpSwitch = Key('codex-personal-acp-switch');
static const codexAcpAdapterInstallButton = Key(
  'codex-acp-adapter-install-button',
);
```

`cli_config_section.dart` `_buildCliRow`:

```dart
if (cli == CliTool.codex) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      pathRow,
      CodexPersonalAcpSettingsRow(cubit: cubit),
    ],
  );
}
```

Copy `ClaudePersonalAcpSettingsRow` / `_ClaudeAcpAdapterInstallButton` to Codex-named widgets. Bind:

- title/subtitle → `codexPersonalAcpDefaultLabel` / `codexPersonalAcpDefaultDescription` / `codexPersonalAcpAndroidDisabled`
- value → `state.preferences.codexPersonalAcpDefault`
- onChanged → `cubit.setCodexPersonalAcpDefault`
- install → `registry.installCodexAcpAdapter`
- running → `InstallJobKeys.codexAcpAdapter()`
- button label still `l10n.claudeAcpAdapterInstallButton` (generic)

Keep Claude widgets untouched.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`

Expected: PASS. Claude ACP settings tests still pass.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/cli_config_section.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "$(cat <<'EOF'
feat: add Codex personal ACP switch and adapter install

Expose the same settings surface as Claude so users can opt new personal Codex sessions into ACP on desktop.
EOF
)"
```

---

### Task 8: Connect executor Codex ACP path

**Files:**
- Test: `client/test/services/chat/launch/session_connect_executor_test.dart`
- No production change expected if Tasks 2 and 5 are correct (`isAcpChatSession` + `attachAcpRuntime` are already CLI-agnostic). If a test finds a `cli == gemini/claude` leftover, delete that leftover — do not add `cli == codex`.

**Interfaces:**
- Consumes: `AppSession(cli: CliTool.codex, acp: true)` + existing executor ACP branch
- Produces: none. Confirms Codex ACP skips shell stages; Codex PTY still connects a shell.

- [ ] **Step 1: Write the failing tests**

Add next to the Claude ACP executor tests:

```dart
test('simple codex acp session attaches ACP and skips shell stages', () async {
  job = _job(cli: CliTool.codex, acp: true, simple: true);

  await executor.execute(job);

  expect(events, <String>['persist', 'ensure-ready', 'attach-acp']);
  expect(events, isNot(contains('resolve-member')));
  expect(shellConnector.connectCalls, 0);
});

test('simple codex PTY session falls through to the shell', () async {
  job = _job(cli: CliTool.codex, acp: false, simple: true);

  await executor.execute(job);

  expect(events, contains('resolve-member'));
  expect(events, contains('connect-shell'));
});
```

If `_job` rejects unknown CLIs, extend it the same way it already accepts `CliTool.claude`.

- [ ] **Step 2: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_connect_executor_test.dart --plain-name "codex"`

Expected: PASS without production edits. If FAIL because `_job` / fakes hardcode Claude, fix only the test helper. If FAIL because executor still special-cases CLI, remove that special case so `isAcpChatSession` is the only branch.

- [ ] **Step 3: Analyze the touched surface**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues in the files from Tasks 1–8.

- [ ] **Step 4: Run the Codex ACP test cluster**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart test/pages/home_workspace/workspace/unbound_compose_claude_acp_test.dart test/services/cli/codex/codex_acp_capability_test.dart test/services/cli/codex/codex_acp_adapter_installer_test.dart test/services/cli/codex/codex_registry_acp_test.dart test/services/install/runners/cli_install_job_runner_test.dart test/services/chat/launch/session_launch_acp_attach_test.dart test/pages/config/cli_config_section_test.dart test/services/chat/launch/session_connect_executor_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit only if Step 2 required production edits**

If the executor needed a fix:

```bash
git add client/test/services/chat/launch/session_connect_executor_test.dart \
  client/lib/services/chat/launch/connect/session_connect_executor.dart
git commit -m "$(cat <<'EOF'
test: cover Codex ACP connect skipping the PTY shell

Lock the existing isAcpChatSession branch so personal Codex ACP never opens a member shell.
EOF
)"
```

If only tests were added, commit the test file with the same message.

Manual desktop check (not CI): install `codex-acp` from Codex settings → new personal Codex with the switch on + Official login → prompt + permission card → repeat with an API-key provider → new personal Codex with the switch off still gets a terminal. Team Codex stays PTY. Android shows the switch disabled.

---

## Spec coverage

| Spec section | Task |
|--------------|------|
| Clone shipped Claude surface; two preference fields; default false | 1, 2, 7 |
| Adapter `codex-acp`; no `codex --acp` / no app-server | 3, 4, 5 |
| `contributeLaunch` provisions `CODEX_HOME`; sync env patch; Official blanks keys; API key inject; `CODEX_PATH` | 3, 5 |
| `PROXY_MANAGED` not injected | 3, 5 |
| Connect never auto-installs | 4, 7 |
| Failure: missing adapter / no PTY fallback; no pre-flight auth.json | 3, 6, 8 |
| `isAcpChatSession` / executor CLI-agnostic | 8 |
| Compose reads Codex vs Claude preference; no compose widget | 2 |
| Settings switch + install button; Android disabled | 7 |
| CLI-aware `codexAcpLaunchFailedAdapter` / `codexAcpChatNotLoggedIn` | 6 |
| History stays ACP transcript | no code (existing `session.acp` path); out of scope for PTY rollout |
| Out of scope (SSH, team, OpenCode, `session/load`, fs/terminal caps) | no tasks |
