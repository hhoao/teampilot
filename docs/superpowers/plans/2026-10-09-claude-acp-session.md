# Claude ACP Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let personal Claude sessions opt into ACP chat (adapter process) while PTY Claude stays the default; team sessions stay PTY.

**Architecture:** Persist `AppSession.acp` as the session fact. `isAcpChatSession` becomes `isSimple && acp`. `ClaudeCliTool` declares `ClaudeAcpCapability` (spawn `claude-agent-acp`, not `claude`). Existing `AcpSessionRuntime` is unchanged except launch wiring reads `agentExecutable` and uses `session.cli` for the tool-dir slot. Preference `claudePersonalAcpDefault` only seeds new personal launches.

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, `AcpProcessTransport` (`Process.start`, no PTY), npm installer for `@agentclientprotocol/claude-agent-acp`, existing `AgentPermissionRequest` card.

**Spec:** `docs/superpowers/specs/2026-10-09-claude-acp-session-design.md`

## Global Constraints

- Desktop-local only. No `SshExecTransport`, no Android ACP UI (hide/disable the switch when `Platform.isAndroid`).
- No `CliTool.claudeAcp`. No FlutterFlow `dart_acp_claude`. No replacing PTY Claude.
- Team sessions: `createSession` / provisional builder force `acp = false`.
- Never spawn `claude --acp`. ACP argv is the adapter binary only.
- Official login: never set `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN`. Isolate `CLAUDE_CONFIG_DIR` under `sessionToolDir`.
- Handshake / install failure must not fall back to PTY for that connect.
- User copy → `app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- No `if (cli == …)` in `services/acp/` or the connect executor. Claude-only behavior lives in `services/cli/claude/`.
- `ClaudeExecutableCapability.npmPackage` stays `@anthropic-ai/claude-code`.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/app_session.dart` | `acp` field, JSON, equality, constructor inference |
| `client/lib/services/chat/session/chat_tab.dart` | `isAcpChatSession` |
| `client/lib/models/session_preferences.dart` | `claudePersonalAcpDefault` |
| `client/lib/cubits/session_preferences_cubit.dart` | setter |
| `client/lib/services/cli/registry/capabilities/acp_capability.dart` | `agentExecutable` |
| `client/lib/cubits/session/acp/acp_launch_wiring.dart` | copy `agentExecutable` into `AcpLaunchPlan` |
| `client/lib/services/acp/acp_session_runtime.dart` | `AcpLaunchPlan.agentExecutable` |
| `client/lib/services/cli/claude/capabilities/acp.dart` | translator + capability + adapter locate |
| `client/lib/services/cli/claude/claude_tool.dart` | register capability |
| `client/lib/services/cli/registry/built_in_cli_tools.dart` | wire credential resolver |
| `client/lib/services/chat/session/session_persist_params.dart` | `acp` on persist |
| `client/lib/services/chat/session/session_create_request.dart` | `acp` on create |
| `client/lib/services/chat/launch/session/session_provisional_builder.dart` | provisional `acp` |
| `client/lib/repositories/session_repository.dart` | persist + team force-false + gemini default |
| `client/lib/services/chat/launch/session_launch_service.dart` | CLI-agnostic ACP attach |
| `client/lib/pages/config/cli_config_section.dart` | settings switch |
| `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart` | landing switch widget |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | copy |

---

### Task 1: `AppSession.acp` and `isAcpChatSession`

**Files:**
- Modify: `client/lib/models/app_session.dart` (constructor, `fromJson`, `copyWith`, `toJson`, `==`, `hashCode`)
- Modify: `client/lib/services/chat/session/chat_tab.dart` (`isAcpChatSession`)
- Test: `client/test/models/app_session_acp_test.dart` (create)
- Test: `client/test/services/chat/session/is_acp_chat_session_test.dart` (create)

**Interfaces:**
- Consumes: existing `AppSession` factory
- Produces: `AppSession.acp` (`bool`). Factory: `bool? acp` — if null, `true` when `sessionTeam` is empty **and** `cli == CliTool.gemini`, else `false`. `fromJson` missing key → pass `null` so inference runs. `toJson` omits when false. `isAcpChatSession(session) => session.isSimple && session.acp`.

- [ ] **Step 1: Write the failing tests**

```dart
// client/test/models/app_session_acp_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('claude simple defaults acp false', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
    );
    expect(s.acp, isFalse);
    expect(s.toJson().containsKey('acp'), isFalse);
  });

  test('gemini simple infers acp true when omitted', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.gemini,
    );
    expect(s.acp, isTrue);
    expect(s.toJson()['acp'], isTrue);
  });

  test('legacy JSON without acp: gemini simple is true, claude is false', () {
    expect(
      AppSession.fromJson({
        'sessionId': 's1',
        'workspaceId': 'w1',
        'createdAt': 1,
        'cli': 'gemini',
      }).acp,
      isTrue,
    );
    expect(
      AppSession.fromJson({
        'sessionId': 's1',
        'workspaceId': 'w1',
        'createdAt': 1,
        'cli': 'claude',
      }).acp,
      isFalse,
    );
  });

  test('acp true round-trips; explicit false wins over gemini inference', () {
    final on = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
    );
    expect(AppSession.fromJson(on.toJson()).acp, isTrue);

    final geminiOff = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.gemini,
      acp: false,
    );
    expect(geminiOff.acp, isFalse);
  });
}
```

```dart
// client/test/services/chat/session/is_acp_chat_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';

void main() {
  AppSession session({
    CliTool? cli,
    String team = '',
    bool? acp,
  }) => AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    createdAt: 1,
    cli: cli,
    sessionTeam: team,
    acp: acp,
  );

  test('gemini simple is ACP', () {
    expect(isAcpChatSession(session(cli: CliTool.gemini)), isTrue);
  });

  test('claude simple default is not ACP', () {
    expect(isAcpChatSession(session(cli: CliTool.claude)), isFalse);
  });

  test('claude simple with acp is ACP', () {
    expect(
      isAcpChatSession(session(cli: CliTool.claude, acp: true)),
      isTrue,
    );
  });

  test('teamed claude with acp true is not ACP', () {
    expect(
      isAcpChatSession(
        session(cli: CliTool.claude, team: 't1', acp: true),
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/app_session_acp_test.dart test/services/chat/session/is_acp_chat_session_test.dart`

Expected: FAIL — `acp` isn't defined on `AppSession`.

- [ ] **Step 3: Implement**

In `AppSession._` / factory: add `this.acp = false` is wrong for inference. Use:

```dart
factory AppSession({
  // existing params...
  bool? acp,
}) {
  final trimmedTeam = sessionTeam; // already a param default ''
  final resolvedAcp =
      acp ??
      (trimmedTeam.trim().isEmpty && cli == CliTool.gemini);
  return AppSession._(..., acp: resolvedAcp);
}
```

`fromJson`:

```dart
acp: json.containsKey('acp') ? json['acp'] == true : null,
```

`toJson`: `if (acp) 'acp': acp`.

`copyWith`: add `bool? acp` and pass through (explicit `false` must stick; use a sentinel or pass `acp ?? this.acp`).

`==` / `hashCode`: include `acp`.

`isAcpChatSession`:

```dart
bool isAcpChatSession(AppSession session) =>
    session.isSimple && session.acp;
```

- [ ] **Step 4: Re-run tests**

Run: `cd client && dart run tool/run_tests.dart test/models/app_session_acp_test.dart test/services/chat/session/is_acp_chat_session_test.dart test/pages/chat/session_chat_view_acp_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: PASS (Gemini fixtures infer `acp: true`).

- [ ] **Step 5: Commit** (only if the user asked to commit)

```bash
git add client/lib/models/app_session.dart client/lib/services/chat/session/chat_tab.dart \
  client/test/models/app_session_acp_test.dart \
  client/test/services/chat/session/is_acp_chat_session_test.dart
git commit -m "$(cat <<'EOF'
feat(acp): persist AppSession.acp and gate ACP chat on the flag

Gemini simple sessions still infer acp so existing rows and fixtures keep working.
EOF
)"
```

---

### Task 2: Preference default

**Files:**
- Modify: `client/lib/models/session_preferences.dart` (field, `fromJson`, `copyWith`, `toJson`)
- Modify: `client/lib/cubits/session_preferences_cubit.dart` (`setClaudePersonalAcpDefault`)
- Test: `client/test/models/session_preferences_test.dart`
- Test: `client/test/cubits/session_preferences_cubit_test.dart` (add cases if the file already covers setters)

**Interfaces:**
- Consumes: `SessionPreferences` JSON map
- Produces: `bool claudePersonalAcpDefault` default `false`; cubit `Future<void> setClaudePersonalAcpDefault(bool value)`

- [ ] **Step 1: Extend `session_preferences_test.dart`**

```dart
test('claudePersonalAcpDefault defaults false and round-trips', () {
  expect(SessionPreferences().claudePersonalAcpDefault, isFalse);
  expect(
    SessionPreferences.fromJson(const {}).claudePersonalAcpDefault,
    isFalse,
  );
  final on = SessionPreferences(claudePersonalAcpDefault: true);
  expect(on.toJson()['claudePersonalAcpDefault'], isTrue);
  expect(
    SessionPreferences.fromJson(on.toJson()).claudePersonalAcpDefault,
    isTrue,
  );
});
```

- [ ] **Step 2: Run to verify fail**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart --plain-name "claudePersonalAcpDefault"`

Expected: FAIL — field missing.

- [ ] **Step 3: Implement field + cubit setter**

Follow `chatSubmitSwitchesToTerminal`: constructor param, `fromJson` `as bool? ?? false`, `copyWith`, `toJson` always write the bool (same as sibling flags).

```dart
Future<void> setClaudePersonalAcpDefault(bool value) {
  return _save(
    state.preferences.copyWith(claudePersonalAcpDefault: value),
  );
}
```

- [ ] **Step 4: Re-run**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart test/repositories/session_preferences_repository_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 3: `AcpCapability.agentExecutable`

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/acp_capability.dart`
- Modify: `client/lib/services/cli/gemini/capabilities/acp.dart` (explicit override returning `cliExecutable`)
- Modify: `client/lib/services/acp/acp_session_runtime.dart` (`AcpLaunchPlan`)
- Modify: `client/lib/cubits/session/acp/acp_launch_wiring.dart` (`capabilityToPlan`)
- Test: `client/test/services/cli/gemini/gemini_acp_capability_test.dart`

**Interfaces:**
- Consumes: `AcpCapability.launchArgCandidates(String executable)`
- Produces:

```dart
/// Binary that speaks ACP on stdio. Gemini returns [cliExecutable].
String agentExecutable(String cliExecutable);
```

`AcpLaunchPlan` gains the same function. `capabilityToPlan` copies it. Gemini: `agentExecutable(cli) => cli`.

Dart interfaces cannot have default methods. Add the method to the interface; every implementer must define it. Today that is only `GeminiAcpCapability` until Task 4.

- [ ] **Step 1: Failing test**

```dart
test('agentExecutable is the gemini binary', () {
  const cap = GeminiAcpCapability();
  expect(cap.agentExecutable('/usr/bin/gemini'), '/usr/bin/gemini');
});
```

- [ ] **Step 2: Run to verify fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/gemini/gemini_acp_capability_test.dart`

Expected: FAIL — method missing.

- [ ] **Step 3: Add method + plan field**

```dart
// acp_capability.dart
String agentExecutable(String cliExecutable);
```

```dart
// GeminiAcpCapability
@override
String agentExecutable(String cliExecutable) => cliExecutable;
```

```dart
class AcpLaunchPlan {
  const AcpLaunchPlan({
    required this.launchArgCandidates,
    required this.buildEnvironment,
    required this.agentExecutable,
  });
  final List<List<String>> Function(String executable) launchArgCandidates;
  final Map<String, String> Function({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv,
  }) buildEnvironment;
  final String Function(String cliExecutable) agentExecutable;
}
```

`capabilityToPlan` must pass `agentExecutable: capability.agentExecutable`.

`AcpSessionRuntime.start` currently calls `plan.launchArgCandidates(executable)` where `executable` is the CLI binary. Change it to:

```dart
final agent = plan.agentExecutable(executable);
for (final argv in plan.launchArgCandidates(agent)) {
```

Keep the `start({ required String executable, ...})` parameter name as the **CLI** executable from the shell factory; the plan maps it.

- [ ] **Step 4: Re-run Gemini ACP tests + session runtime tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/gemini/gemini_acp_capability_test.dart test/services/acp/acp_session_runtime_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 4: `ClaudeAcpCapability`

**Files:**
- Create: `client/lib/services/cli/claude/capabilities/acp.dart`
- Test: `client/test/services/cli/claude/claude_acp_capability_test.dart`

**Interfaces:**
- Consumes: `AcpCapability`, `AcpAgentTranslator`, `AcpCredentialSource`
- Produces:

```dart
final class ClaudeAcpTranslator implements AcpAgentTranslator {
  const ClaudeAcpTranslator();
  @override
  List<String> get flagCandidates => const [];
  @override
  String translateStopError(Object error, {required bool suppressAbort}) { ... }
}

class ClaudeAcpAuth {
  const ClaudeAcpAuth({
    this.apiKey,
    this.authToken,
    this.official = false,
    this.officialCredentialsPath,
  });
  final String? apiKey;
  final String? authToken;
  final bool official;
  /// Absolute path to Official `.credentials.json` to copy into CLAUDE_CONFIG_DIR.
  final String? officialCredentialsPath;
}

typedef ClaudeAcpAuthSource = ClaudeAcpAuth Function();

final class ClaudeAcpCapability implements AcpCapability {
  const ClaudeAcpCapability({
    ClaudeAcpAuthSource? authSource,
    String Function(String cliExecutable)? locateAdapter,
    void Function(String destCredentialsPath, String srcPath)? copyFile,
  });
  @override
  String agentExecutable(String cliExecutable);
  @override
  List<List<String>> launchArgCandidates(String executable);
  @override
  Map<String, String> buildEnvironment({...});
}
```

Default `locateAdapter` returns `'claude-agent-acp'` (PATH name), ignoring `cliExecutable`.

`buildEnvironment` rules (spec):
- Preserve `baseEnv`
- `CLAUDE_CONFIG_DIR = '$sessionToolDir/claude'`
- If `official`: do **not** set `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN`; set `CCGUI_CLI_LOGIN_AUTHORIZED=1`; if `officialCredentialsPath` is set and `copyFile` is set, copy to `$CLAUDE_CONFIG_DIR/.credentials.json`
- Else if `apiKey` non-null: set `ANTHROPIC_API_KEY`
- Else if `authToken` non-null: set `ANTHROPIC_AUTH_TOKEN`

`translateStopError`: if `RpcError`, `'ACP error ${code}: ${message}'`; else `toString()`. Do not map Gemini abort phrases.

- [ ] **Step 1: Write failing tests** (file as above)

Cover: argv `[[adapter]]` not `claude --acp`; `agentExecutable` ignores cli path; API key env; official omits keys and copies credentials; base env preserved.

- [ ] **Step 2: Run to verify fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/claude/claude_acp_capability_test.dart`

Expected: FAIL — library missing.

- [ ] **Step 3: Implement `capabilities/acp.dart`**

Keep the file under the ~600 line service limit (this should stay small).

- [ ] **Step 4: Re-run**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/claude/claude_acp_capability_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 5: Register capability on `ClaudeCliTool`

**Files:**
- Modify: `client/lib/services/cli/claude/claude_tool.dart`
- Modify: `client/lib/services/cli/claude/claude_bootstrap_entry.dart` (optional `ClaudeAcpAuthSource? acpAuthSource`)
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: `client/lib/app/app_shell.dart` only if bootstrap construction lives there — wire auth from `ClaudeProviderCredentialsService` + current simple-launch provider. Prefer a small function in `claude/capabilities/acp.dart` or `claude_bootstrap_entry.dart` that reads the official vs key provider. If provider lookup is too heavy for this task, inject a lambda from `app_shell` that returns `ClaudeAcpAuth` from the credentials service + selected provider id; tests pass fakes.
- Test: `client/test/services/cli/cli_tool_registry_test.dart` or new `client/test/services/cli/claude/claude_registry_acp_test.dart`

**Interfaces:**
- Consumes: `ClaudeAcpCapability` from Task 4
- Produces: `registry.capability<AcpCapability>(CliTool.claude)` non-null. Presence does **not** make every Claude session ACP.

Auth is a closure invoked from `buildEnvironment`, not at registry construction (same as Gemini's `credentialSource`).

`ClaudeBootstrapEntry` gains `ClaudeAcpAuthSource? acpAuthSource`. `app_shell` (or the existing Claude bootstrap construction site) builds it from `credentialsService` + the CLI's current official-vs-key provider id:

- Official → `ClaudeAcpAuth(official: true, officialCredentialsPath: credentialsService.effectiveCredentialPath(id))`
- Key/token in resolved settings env → `apiKey` / `authToken`
- Else → empty `ClaudeAcpAuth()` (still sets `CLAUDE_CONFIG_DIR`)

`built_in_cli_tools` passes `ClaudeAcpCapability(authSource: claudeEntry?.acpAuthSource)`. Registry test: `capability<AcpCapability>(CliTool.claude)` non-null and `agentExecutable('claude') == 'claude-agent-acp'`.

- [ ] **Step 1: Failing registry test**

```dart
test('claude registers AcpCapability that spawns the adapter', () {
  final registry = CliToolRegistry();
  registerBuiltInCliTools(registry);
  final cap = registry.capability<AcpCapability>(CliTool.claude);
  expect(cap, isNotNull);
  expect(cap!.agentExecutable('/usr/bin/claude'), 'claude-agent-acp');
  expect(cap.launchArgCandidates('claude-agent-acp'), [
    ['claude-agent-acp'],
  ]);
});
```

- [ ] **Step 2: Run to verify fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/claude/claude_registry_acp_test.dart`

- [ ] **Step 3: Register on the tool + bootstrap**

Add `this.acp = const ClaudeAcpCapability()` to `ClaudeCliTool` and append `acp` to `capabilities`.

- [ ] **Step 4: Re-run registry tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/claude/claude_registry_acp_test.dart test/services/cli/cli_tool_registry_test.dart`

Expected: PASS. Built-in required-capability asserts still pass (AcpCapability is optional).

- [ ] **Step 5: Commit** (only if asked)

---

### Task 6: Persist `acp` on create

**Files:**
- Modify: `client/lib/services/chat/session/session_create_request.dart` (`bool acp = false`)
- Modify: `client/lib/services/chat/session/session_persist_params.dart` (`bool acp = false`)
- Modify: `client/lib/services/chat/launch/session/session_launch_coordinator.dart` (copy `request.acp` into persist + provisional)
- Modify: `client/lib/services/chat/launch/session/session_provisional_builder.dart` (`bool? acp`)
- Modify: `client/lib/services/chat/launch/session_launch_service.dart` (`createSession(..., acp: ...)`)
- Modify: `client/lib/repositories/session_repository.dart` (`createSession` param `bool acp = false`; if `trimmedTeam.isNotEmpty` force false; if personal && `cli == CliTool.gemini` treat as true when `acp` is false — still persist `acp: true` for Gemini)
- Test: extend an existing create-session / provisional-builder test, or add `client/test/services/chat/launch/session_provisional_builder_test.dart`

**Interfaces:**
- Consumes: Task 1 `AppSession.acp`
- Produces: new personal Claude with `acp: true` is ACP at connect; new personal Claude default is PTY; Gemini personal always persists `acp: true`; team always `acp: false`.

`createSession` resolution:

```dart
final resolvedAcp = trimmedTeam.isEmpty &&
    (acp || cli == CliTool.gemini);
```

Pass `acp: resolvedAcp` into `AppSession` **explicitly** so Gemini does not depend only on constructor inference.

Provisional builder: same formula using `isPersonal`, `acp`, and `identity?.cli ?? cli`.

- [ ] **Step 1: Failing tests** for provisional builder and createSession force-false on teams. Prefer a focused unit test on `buildProvisionalSession` (no disk). For `createSession`, use existing session repository tests with `setUpTestAppStorage` if that harness is already used there; otherwise test the resolved-acp formula via provisional builder + a thin repository test.

- [ ] **Step 2: Run to verify fail**

- [ ] **Step 3: Thread `acp` through create → persist → AppSession**

`SessionLaunchCoordinator` persistParams:

```dart
persistParams: SessionPersistParams(
  ...
  acp: request.acp,
),
```

`SessionLaunchService` `createSession`: pass `acp: params.acp`.

- [ ] **Step 4: Re-run**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_launch_coordinator_test.dart` plus any new tests.

- [ ] **Step 5: Commit** (only if asked)

---

### Task 7: CLI-agnostic `attachAcpRuntime`

**Files:**
- Modify: `client/lib/services/chat/launch/session_launch_service.dart` (`attachAcpRuntime`, `_acpSessionToolDir`)
- Test: `client/test/services/chat/launch/session_connect_executor_test.dart` — add a case whose session is `cli: claude, acp: true, sessionTeam: ''` and assert `attach-acp` is called and shell stages are **not**. Existing Claude PTY fixtures must still fall through.

**Interfaces:**
- Consumes: `isAcpChatSession` (Task 1), `AcpLaunchPlan.agentExecutable` (Task 3)
- Produces: Claude ACP sessions attach `AcpSessionRuntime`; PTY Claude unchanged.

Replace:

```dart
tool: session.cli ?? CliTool.gemini,
executable: _h.shellFactory.executableFor(session.cli ?? CliTool.gemini),
sessionRuntimeToolDir(..., 'gemini'),
```

with:

```dart
final cli = session.cli;
if (cli == null) {
  throw StateError('ACP session requires session.cli');
}
...
tool: cli,
executable: _h.shellFactory.executableFor(cli),
sessionRuntimeToolDir(..., cli.value),
```

`AcpSessionRuntime.start` already maps through `plan.agentExecutable` (Task 3), so the shell-factory Claude path is rewritten to `claude-agent-acp` by `ClaudeAcpCapability`.

Adapter missing: `Process.start` throws → surface existing ACP launch error / l10n. Do **not** catch and spawn PTY.

- [ ] **Step 1: Executor test for claude+acp attaches ACP and skips shell**

Look at how the fake preparation records `attach-acp`. Add a job whose `session` is simple Claude `acp: true`. Expect events contain `attach-acp` and, when the fake returns `true`, no `resolve-member`. When fake returns `false` (today's default), PTY fixtures stay valid — for the new test make `attachAcpRuntime` return `true` for ACP sessions:

```dart
@override
Future<bool> attachAcpRuntime(...) async {
  events.add('attach-acp');
  return isAcpChatSession(session);
}
```

If that changes existing tests that used gemini, update those expected event lists.

- [ ] **Step 2: Run to verify fail** (Claude ACP still not treated as ACP until Task 1 is in — this task assumes Task 1 done)

- [ ] **Step 3: Fix `session_launch_service.dart` hardcoding**

- [ ] **Step 4: Re-run**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_connect_executor_test.dart test/services/acp/`

- [ ] **Step 5: Commit** (only if asked)

---

### Task 8: Settings switch + l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/config/cli_config_section.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (`claudePersonalAcpSwitch`)
- Test: `client/test/pages/config/` — add a small widget test if a CLI config test exists; otherwise a cubit+row test. Prefer a widget test that pumps the Claude switch on desktop.

**Copy:**

| Key | en | zh |
|-----|----|----|
| `claudePersonalAcpDefaultLabel` | Personal sessions use ACP chat | 个人会话使用 ACP 聊天 |
| `claudePersonalAcpDefaultDescription` | Run new personal Claude sessions as terminal-less ACP chat via claude-agent-acp. Existing sessions stay as they were started. Team sessions always use the terminal. | 新建个人 Claude 会话走无终端 ACP（claude-agent-acp）。已有会话保持原启动方式。团队会话始终用终端。 |
| `claudePersonalAcpAndroidDisabled` | ACP chat is desktop-only until remote SSH exec is available. | 在远程 SSH exec 就绪前，ACP 聊天仅限桌面。 |
| `acpLaunchFailedAdapter` | Could not start the Claude ACP adapter (claude-agent-acp). Install it and try again. | 无法启动 Claude ACP 适配器（claude-agent-acp）。请安装后重试。 |

Claude has one argv candidate. Missing adapter (`Process.start` executable-not-found / `PathNotFoundException`) is mapped in `attachAcpRuntime` to l10n key `acpLaunchFailedAdapter`. Probe exhaustion (`AcpLaunchException.reason == acpLaunchFailedVersion`) stays the Gemini flag-probe message. Do not catch those errors and spawn PTY.

Settings UI: after the Claude `CliExecutablePathSettingsRow`, if `cli == CliTool.claude` (this **is** allowed: the row is built per `def.id` in CLI settings, not scattered feature code), show a `SwitchListTile` bound to `SessionPreferencesCubit.setClaudePersonalAcpDefault`. If `Platform.isAndroid`, show disabled + `claudePersonalAcpAndroidDisabled`.

Do not grow `cli_config_section.dart` past the page soft limit; extract `pages/config/claude_acp_settings_row.dart` if the section file is already large.

- [ ] **Step 1: Add arb keys, run codegen if the project requires it** (`flutter gen-l10n` is already part of the Flutter build; follow existing l10n workflow in `docs/DEVELOPMENT.md`)

- [ ] **Step 2: Widget or cubit test for the setter**

- [ ] **Step 3: Implement the row**

- [ ] **Step 4: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` plus the new test file**

- [ ] **Step 5: Commit** (only if asked)

---

### Task 9: Landing / personal compose switch

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart` (desktop-only switch; reads preference; local override for this compose)
- Modify: landing compose (`unbound_compose_body.dart` or the simple-launch settings sheet it already opens) — insert the switch when selected CLI is Claude and not Android. Do **not** add large private `Widget` methods; use the extracted class.
- Modify: `workspace_session_actions.dart` / `_requestCreateWorkspaceConversation` / `SessionCreateRequest` to pass `acp:`
- Test: widget test for the switch; a unit/widget test that creating with the switch on sets `request.acp == true`

**Interfaces:**
- Consumes: `claudePersonalAcpDefault`, `SessionCreateRequest.acp`
- Produces: user can start one personal Claude as ACP without changing all future sessions unless they also flip settings. Initialize compose state from the preference. Flipping the compose switch does **not** have to write the preference (session fact is enough). Updating the settings switch still changes the default for the next compose.

Pass `acp: isPersonal && cli == claude && composeAcp` into `SessionCreateRequest`. Gemini stays default inference (`acp: false` on the request is OK because `createSession` ORs gemini).

- [ ] **Step 1: Failing widget test for the switch visibility (Claude + desktop)**

- [ ] **Step 2: Implement extracted switch + wire create**

- [ ] **Step 3: Analyze + tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` (the new widget test plus `is_acp_chat_session_test`)

- [ ] **Step 4: Commit** (only if asked)

---

### Task 10: Adapter auto-install (npm)

**Files:**
- Create: `client/lib/services/cli/claude/capabilities/acp_adapter_installer.dart` — `NpmInstallerCapability` subclass: `npmPackage = '@agentclientprotocol/claude-agent-acp'`, `executableName = 'claude-agent-acp'`, `displayName = 'Claude ACP adapter'`
- Modify: `ClaudeAcpCapability.locateAdapter` / `attachAcpRuntime` to install once when the adapter is not on PATH, then re-resolve. Inject the installer so tests never hit npm.
- Test: capability test with a fake locator that first returns empty then a path after `install` is invoked.

Do **not** change `ClaudeExecutableCapability.npmPackage`.

Install from the Claude ACP settings row using the same `CliInstallContext` host as other CLI install buttons. `locateAdapter` is PATH (then TeamPilot node prefix) only. Missing adapter at connect shows `acpLaunchFailedAdapter`.

- [ ] **Step 1: Installer class + test that npm package / executable names are correct**

- [ ] **Step 2: Settings row install action (desktop)**

- [ ] **Step 3: Analyze + tests**

- [ ] **Step 4: Commit** (only if asked)

---

### Task 11: Verification

- [ ] **Step 1:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] **Step 2:** `cd client && dart run tool/run_tests.dart` (full suite, background if running locally)
- [ ] **Step 3: Manual desktop**
  1. Settings: Claude ACP default off. New personal Claude → terminal.
  2. Landing: turn ACP on for one Claude session → chat-only, no terminal toggle; permission card still works if the adapter requests it.
  3. Existing PTY Claude session still opens a terminal.
  4. Gemini personal session still ACP.
  5. Team Claude unchanged.

---

## Self-review (spec coverage)

| Spec item | Task |
|-----------|------|
| Keep PTY Claude | 1, 6, 9 (default false) |
| `AppSession.acp` + JSON + gemini legacy | 1 |
| `isAcpChatSession` | 1, 7 |
| Preference default | 2, 8, 9 |
| Team never ACP | 1, 6 |
| `agentExecutable` / not `claude --acp` | 3, 4, 5 |
| `claude-agent-acp` npm | 10 |
| Env / Official vs API key | 4, 5 |
| CLI-agnostic attach + tool dir slot | 7 |
| Settings + landing UI | 8, 9 |
| Android hide | 8, 9 |
| No dart_acp_claude / no SSH | Global constraints |
| Tests listed in spec | 1, 2, 4, 6, 7 |
| Failure no PTY fallback | 7 |
