# ACP Gemini Terminal-less Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first ACP integration: Gemini CLI as a terminal-less standalone chat session, protocol mechanics in a CLI-agnostic `services/acp/` layer, Gemini declaring via `AcpCapability`.

**Architecture:** Mechanism-vs-declaration separation. `services/acp/` owns connection/session/transport/translator/frame-logger (CLI-agnostic, remote-ready via `AcpTransport` seam); `services/cli/gemini/` declares launch args, flag probing, env, and the gemini quirk translator. acpd is vendored as a git submodule. The session runtime is a new terminal-less branch in the chat session flow, parallel to `TerminalSession`.

**Tech Stack:** Flutter/Dart (package `teampilot`), vendored `acpd` + `acpd_test` submodules, `Process.start` (no PTY), existing `SeatHoldGate`, `AgentPermissionRequest` card, npm installer channel (`NpmInstallerCapability`).

**Spec:** `docs/superpowers/specs/2026-09-12-acp-gemini-session-design.md`

## Global Constraints

- Spec scope: desktop-local only. NO SSH transport, NO TeamBus/roster, NO OAuth, NO `session/load` resume UI, NO fs/*/terminal/* client capabilities (advertise false), NO MCP registration in initialize.
- acpd is vendored as a git submodule under `client/packages/acpd` (same pattern as dartssh2). Never add a pub.dev dependency on acpd.
- NEVER merge stderr into stdout in any ACP transport — the opposite of `SshPtyTransport`'s merge semantics. stderr routes to `AppLogger`.
- Every CliTool must register all required capabilities (`built_in_cli_tools.dart` asserts): Provider, MemberConfigInspection, CliSession, TeamBehavior, CliExecutable, TerminalBehavior, Plugin, ChatInteraction, RuntimeEvent. Gemini gets default/noop implementations for non-ACP ones.
- `CliTool.gemini` is NOT in `_verifyNativeTeamRegistration` / `_verifyMemberAgentPresetRegistration` allowed sets — those stay `{claude, flashskyai}`.
- No `if (cli == …)` checks outside capability declarations.
- User-facing errors → l10n (`client/lib/l10n/app_en.arb` + `app_zh.arb` only). Diagnostics → `AppLogger`. No `print`.
- Paths: injected `HomeStorage`/`RuntimeContextRegistry` only — never `Directory.current`.
- Tests: mock subprocess/filesystem via constructor injection; never invoke `flutter test` directly — always `cd client && dart run tool/run_tests.dart <paths>`. Inner loop is `flutter analyze`; full suite once at the end.
- One process = one sessionToolDir = one isolated env domain. No process pooling across sessions.
- Process teardown: SIGTERM → 5 s timeout → SIGKILL (process-group sweep).
- Frame logger: 200-entry ring buffer, credential redaction (`GEMINI_API_KEY` value never logged).

---

### Task 1: CliTool.gemini enum value

**Files:**
- Modify: `client/lib/models/team_config.dart:19-49` (enum)
- Test: `client/test/models/team_config_cli_tool_test.dart`

**Interfaces:**
- Produces: `CliTool.gemini` (value `'gemini'`) — every later task references this value. `tryParse('gemini')` must return it.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/team_config_cli_tool_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('CliTool has a gemini value that parses round-trip', () {
    expect(CliTool.gemini.value, 'gemini');
    expect(CliTool.tryParse('gemini'), CliTool.gemini);
    expect(CliTool.tryParse('GEMINI'), CliTool.gemini);
    expect(CliTool.tryParse('not-a-cli'), isNull);
  });

  test('CliTool.values length is 6 after adding gemini', () {
    expect(CliTool.values.length, 6);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/team_config_cli_tool_test.dart`
Expected: FAIL — `CliTool.gemini` undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

In `client/lib/models/team_config.dart`, extend the enum and update the doc comment:

```dart
/// Backend CLI identity (`flashskyai`, `codex`, `claude`, `opencode`,
/// `cursor`, or `gemini`).
///
/// Behavior (launch support, display name, provider catalog, etc.) lives in
/// [CliToolRegistry] capabilities — not on this enum.
enum CliTool {
  claude('claude'),
  codex('codex'),
  flashskyai('flashskyai'),
  opencode('opencode'),
  cursor('cursor'),
  gemini('gemini');
  // ... rest of enum (constructor, tryParse, parse, decode) unchanged —
  // tryParse already iterates CliTool.values so gemini parses automatically.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/models/team_config_cli_tool_test.dart`
Expected: PASS (2 tests).

Also run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` — it will surface every exhaustive switch / map keyed on `CliTool.values` that now misses `gemini`. These are compile errors listing the exact files to touch in Task 2 (the registry asserts make analyzer failures the roadmap). Do not fix them here; record the list in the commit message.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/team_config.dart client/test/models/team_config_cli_tool_test.dart
git commit -m "feat(acp): add CliTool.gemini enum value

analyzer now flags every CliTool-exhaustive site; the registry
registration in the next task is the single fix point.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Gemini CliToolDefinition with default capabilities

**Files:**
- Create: `client/lib/services/cli/gemini/gemini_tool.dart`
- Create: `client/lib/services/cli/gemini/capabilities/provider.dart`
- Create: `client/lib/services/cli/gemini/capabilities/executable.dart`
- Create: `client/lib/services/cli/gemini/capabilities/session.dart`
- Create: `client/lib/services/cli/gemini/capabilities/defaults.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/services/cli/gemini/gemini_registry_test.dart`

**Interfaces:**
- Consumes: `CliTool.gemini` (Task 1).
- Produces: `GeminiCliTool` — a const `CliToolDefinition` with constructor params for each capability (pattern mirrors `FlashskyaiCliTool`). Later tasks add `AcpCapability` to this definition's capability list. Registered via `registerBuiltInCliTools`.

The registry asserts require every CliTool to provide: Provider, MemberConfigInspection, CliSession, TeamBehavior, CliExecutable, TerminalBehavior, Plugin, ChatInteraction, RuntimeEvent. For this phase gemini uses existing shared defaults where possible; the exe-file-only capabilities (provider/model catalog) get minimal stubs.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/gemini/gemini_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';

void main() {
  test('gemini registers all required capabilities on the built-in registry',
      () {
    final registry = CliToolRegistry()..registerBuiltInCliToolsForTest();
    final def = registry.tryGet(CliTool.gemini);
    expect(def, isNotNull, reason: 'gemini must be registered');
    expect(def!.isLaunchSupported, isTrue);
    // Required-capability asserts already run inside registerBuiltInCliTools;
    // reaching here means they passed. Verify the executable identity.
    final exe = registry.capability<CliExecutableCapability>(CliTool.gemini);
    expect(exe!.defaultExecutableName, 'gemini');
    expect(exe.supportsInstaller, isTrue);
  });
}
```

Note: `registerBuiltInCliToolsForTest` does not exist yet — the built-in registry is normally constructed via `CliToolRegistry.builtIn()`. Check `cli_tool_registry_test.dart` for the existing test-time registration pattern and follow it; if tests there call `registerBuiltInCliTools(registry)` directly, drop the ForTest helper and do the same.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/gemini/gemini_registry_test.dart`
Expected: FAIL — no gemini registration.

- [ ] **Step 3: Implement the capabilities and definition**

`capabilities/defaults.dart` — shared no-op fills (check each interface's method set before writing; these follow the existing `Noop*`/`Default*` pattern):

```dart
// client/lib/services/cli/gemini/capabilities/defaults.dart
import '../../../../models/team_config.dart';
import '../../registry/capabilities/team_behavior_capability.dart';
import '../../registry/capabilities/chat_interaction_capability.dart';
import '../../registry/capabilities/runtime_event_capability.dart';
import '../../registry/capabilities/terminal_behavior_capability.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/member_config_inspection_capability.dart';

/// Gemini is not team-launchable in this phase.
final class GeminiTeamBehavior implements TeamBehaviorCapability {
  const GeminiTeamBehavior();
  // Implement interface members with "not supported" defaults following the
  // pattern of FlashskyaiTeamBehavior for unsupported surfaces.
}

/// Gemini has no TUI in ACP mode; chat interaction defaults are minimal.
final class GeminiChatInteraction implements ChatInteraction,
    RuntimeEventCapability {
  const GeminiChatInteraction();
  // RuntimeEventCapability: normalizeRuntimeEvent returns null,
  // managedHookEntries returns const [], promptCorrelationStrength => none.
}
```

`capabilities/session.dart`:

```dart
// client/lib/services/cli/gemini/capabilities/session.dart
import '../../registry/capabilities/noop_cli_session_capability.dart';

/// Gemini session capability: noop lifecycle + standard CONFIG_DIR layout.
final class GeminiCliSessionCapability extends NoopCliSessionCapability {
  const GeminiCliSessionCapability();
}
```

`capabilities/executable.dart` — mirrors `CodexExecutableCapability` (npm package `@google/gemini-cli`):

```dart
// client/lib/services/cli/gemini/capabilities/executable.dart
import '../../../../l10n/app_localizations.dart';
import '../../installer_types.dart';
import '../../remote_cli_locator.dart';
import '../../registry/capabilities/cli_executable_capability.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// Gemini identity & binary; npm install via the shared channel.
final class GeminiExecutableCapability extends NpmInstallerCapability
    implements CliExecutableCapability {
  const GeminiExecutableCapability();

  @override
  String get npmPackage => '@google/gemini-cli';

  @override
  String get executableName => 'gemini';

  @override
  String get displayName => 'Gemini CLI';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolGemini;

  @override
  String get defaultExecutableName => 'gemini';

  @override
  String get preferencesPathKey => 'gemini';

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('gemini').locate(run);

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'gemini-cli-executable-path-field',
        browseKey: 'gemini-cli-executable-path-browse-button',
        resetKey: 'gemini-cli-executable-path-reset-button',
        debouncerTag: 'gemini_cli_executable_path',
        installKey: 'gemini-cli-install-button',
        showDividerBelow: true,
      );
}
```

`capabilities/provider.dart` — minimal provider catalog (gemini models via key). Model Model IDs: consult `opencode_model_catalog.dart`'s google entry for current naming; keep the list short (3-4 models) and mark it as a static catalog for this phase.

`gemini_tool.dart` — follows `FlashskyaiCliTool` structure:

```dart
// client/lib/services/cli/gemini/gemini_tool.dart
final class GeminiCliTool implements CliToolDefinition {
  const GeminiCliTool({
    this.executable = const GeminiExecutableCapability(),
    this.session = const GeminiCliSessionCapability(),
    this.provider = const GeminiProviderCapability(),
    this.teamBehavior = const GeminiTeamBehavior(),
    this.chatInteraction = const GeminiChatInteraction(),
    // ... remaining required capabilities as fields
  });

  @override
  CliTool get id => CliTool.gemini;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    provider,
    executable,
    session,
    teamBehavior,
    chatInteraction,
    // ... all fields, semantic order
  ];
}
```

Modify `built_in_cli_tools.dart` — add imports and register:

```dart
registry.register(const GeminiCliTool());
```

Read each required capability interface before stubbing it — the registry assert names them; the analyzer is the checklist. Add `appProviderToolGemini` to both `.arb` files:

```json
"appProviderToolGemini": "Gemini CLI",
```
(zh: `"appProviderToolGemini": "Gemini CLI"`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/gemini/gemini_registry_test.dart`
Expected: PASS. Then `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` — fix remaining `CliTool`-exhaustive warnings surfaced by Task 1's enum change (HookEvent matrix in `models/hook_event.dart`, display-name maps, provider UI pickers) by adding gemini rows with "not supported" or minimal values as each file's existing pattern dictates.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/gemini client/lib/services/cli/registry/built_in_cli_tools.dart client/lib/l10n client/test/services/cli/gemini
git commit -m "feat(acp): register gemini CliToolDefinition with default capabilities

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Vendor acpd submodules

**Files:**
- Create: `client/packages/acpd` (git submodule → https://github.com/fluttercandies/acpd, pin the v1.0.0 tag ref)
- Create: `client/packages/acpd_test` (submodule of the same repo's companion package, or a path within one submodule if the repo is monorepo — check the repo layout first; if `acpd_test` lives in the same repo, one submodule suffices and `acpd_test` resolves via a relative path dependency)
- Modify: `client/pubspec.yaml` (dependency_overrides or path deps), `.gitmodules`

**Interfaces:**
- Produces: `package:acpd/acpd.dart` and `package:acpd_test/acpd_test.dart` importable from `package:teampilot`, locked to a pinned submodule ref.

- [ ] **Step 1: Inspect the acpd repo layout**

```bash
git ls-remote --tags https://github.com/fluttercandies/acpd
# Clone shallow to a temp dir and check: is acpd_test a sibling package in the
# same repo, or a separate repo? Are acpd_io / acpd_http needed for our scope?
# Scope answer: desktop-local only — we need core acpd + acpd_test. acpd_io
# (subprocess spawn) is NOT used: our ProcessTransport spawns the process
# itself and pipes byte streams into acpd's transport abstraction.
git clone --depth 1 https://github.com/fluttercandies/acpd /tmp/acpd-inspect && ls /tmp/acpd-inspect
```

- [ ] **Step 2: Add the submodule(s) at the pinned tag**

```bash
cd /home/hhoa/git/hhoa/teampilot
git submodule add https://github.com/fluttercandies/acpd client/packages/acpd
cd client/packages/acpd && git checkout <v1.0.0-tag-ref> && cd -
```

(If acpd_test is a package inside the same repo, no second submodule — the path dep below points inside `client/packages/acpd/acpd_test` or similar.)

- [ ] **Step 3: Wire pubspec path deps**

In `client/pubspec.yaml` dependencies (follow existing path-dep formatting):

```yaml
  acpd:
    path: packages/acpd
  acpd_test:
    path: packages/acpd/acpd_test  # adjust to actual layout from Step 1
```

If acpd itself depends on acpd_io via pub (not path), convert in `dependency_overrides`:

```yaml
dependency_overrides:
  acpd_io:
    path: packages/acpd/acpd_io
```

- [ ] **Step 4: Verify it resolves and analyzes**

Run: `cd client && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: pub resolves; no new analyzer errors. Write a trivial smoke test proving the import works:

```dart
// client/test/services/acp/acpd_import_smoke_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:acpd/acpd.dart' as acpd;

void main() {
  test('acpd resolves from the vendored submodule', () {
    // Touch one exported symbol; adjust to the package's actual exports.
    expect(acpd.acpProtocolVersion, isNotNull);
  });
}
```

(Adjust the symbol to a real export from the package's README/example — the point is the import path, not the symbol.)

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acpd_import_smoke_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .gitmodules client/packages/acpd client/pubspec.yaml client/pubspec.lock client/test/services/acp/acpd_import_smoke_test.dart
git commit -m "build(acp): vendor acpd submodule at v1.0.0

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: AcpTransport interface + NDJSON framing + process transport

**Files:**
- Create: `client/lib/services/acp/acp_transport.dart`
- Create: `client/lib/services/acp/acp_process_transport.dart`
- Create: `client/lib/services/acp/acp_frame_logger.dart`
- Test: `client/test/services/acp/acp_frame_logger_test.dart`
- Test: `client/test/services/acp/acp_transport_test.dart` (NDJSON decode helpers)

**Interfaces:**
- Consumes: nothing from earlier tasks (pure new layer).
- Produces:
  - `abstract class AcpTransport { Stream<Uint8List> get input; void write(String frame); Stream<List<int>> get stderr; Future<void> close(); bool get isClosed; }`
  - `class AcpProcessTransport implements AcpTransport` — constructor `AcpProcessTransport({required Process process, required void Function(List<int>) onStderr})`; static `Future<AcpProcessTransport> start({required String executable, required List<String> args, required Map<String, String> environment, required String workingDirectory})` that uses `Process.start(executable, args, environment: environment, workingDirectory: workingDirectory, runInShell: false)` — NO PTY.
  - `class AcpFrameLogger` — `void logOutgoing(String frame)`, `void logIncoming(String frame)`, `void logStderr(String line)`, `List<String> snapshot({AcpFrameDirection? direction})`, ring buffer cap 200, redaction of `GEMINI_API_KEY` values via `RegExp(r'"GEMINI_API_KEY"\s*:\s*"([^"]*)"')` replacement to `"[REDACTED]"`.
  - `class NdjsonDecoder` — `Stream<String> decode(Stream<Uint8List> bytes)` splitting on `\n`, buffering partial frames across chunk boundaries.

- [ ] **Step 1: Write the failing tests**

```dart
// client/test/services/acp/acp_frame_logger_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';

void main() {
  test('redacts GEMINI_API_KEY values in frames', () {
    final logger = AcpFrameLogger();
    logger.logOutgoing(jsonEncode({
      'method': 'session/prompt',
      'env': {'GEMINI_API_KEY': 'super-secret'},
    }));
    final text = logger.snapshot().join('\n');
    expect(text, contains('[REDACTED]'));
    expect(text, isNot(contains('super-secret')));
  });

  test('ring buffer caps at 200 entries, oldest dropped', () {
    final logger = AcpFrameLogger();
    for (var i = 0; i < 250; i++) {
      logger.logIncoming('frame-$i');
    }
    final all = logger.snapshot();
    expect(all.length, 200);
    expect(all.first, 'frame-50');
    expect(all.last, 'frame-249');
  });
}
```

```dart
// client/test/services/acp/acp_transport_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_transport.dart';

void main() {
  test('NDJSON decoder splits frames and buffers partial chunks', () async {
    final decoder = NdjsonDecoder();
    final controller = StreamController<Uint8List>();
    final frames = decoder.decode(controller.stream).toList();
    controller.add(utf8.encode('{"a":1}\n{"b"'));
    await Future<void>.delayed(Duration.zero);
    controller.add(utf8.encode(':2}\n{"c":3}'));
    await Future<void>.delayed(Duration.zero);
    controller.add(utf8.encode('\n'));
    await controller.close();
    expect(await frames, ['{"a":1}', '{"b":2}', '{"c":3}']);
  });
}
```

(StreamController needs `import 'dart:async';`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_frame_logger_test.dart test/services/acp/acp_transport_test.dart`
Expected: FAIL — classes undefined.

- [ ] **Step 3: Implement**

`acp_frame_logger.dart`: three ring buffers (`_incoming`, `_outgoing`, `_stderr`) each `ListQueue<String>` capped at 200 (drop oldest via `removeFirst` when length exceeds). Redaction regex applied to the string BEFORE storing. Also mirror to `AppLogger` (finer detail, gated by a `bool enableDiskLog` flag defaulting true — check `AppLogger` API for the appropriate level; use debug).

`acp_transport.dart`: interface + `NdjsonDecoder` (buffer `String` decoded with utf8 decoder; on each chunk, append and split on `\n`, emitting complete lines, keeping the tail buffered).

`acp_process_transport.dart`:

```dart
class AcpProcessTransport implements AcpTransport {
  AcpProcessTransport._(this._process, this._onStderr);
  final Process _process;
  final void Function(List<int>) _onStderr;

  static Future<AcpProcessTransport> start({
    required String executable,
    required List<String> args,
    required Map<String, String> environment,
    required String workingDirectory,
    void Function(List<int>)? onStderr,
  }) async {
    final process = await Process.start(
      executable, args,
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    return AcpProcessTransport._(process, onStderr ?? (_) {});
  }

  @override
  Stream<Uint8List> get input =>
      _process.stdout.map(Uint8List.fromList);

  @override
  void write(String frame) => _process.stdin.write('$frame\n');

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  bool get isClosed => _process.killSignalSent; // or track exitCode future

  @override
  Future<void> close() async {
    // SIGTERM to the process group, 5s timeout, SIGKILL.
    // Process.start without processGroup default: use
    // Process.killPid(process.pid) with ProcessSignal.sigterm, then
    // process.exitCode.timeout(5s) → killPid(sigkill). Track a flag.
  }
}
```

Implement `close()` fully: send SIGTERM (on Windows fall back to `process.kill()`), await exitCode with 5 s timeout, on timeout SIGKILL. Track a `_closed` flag for `isClosed`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_frame_logger_test.dart test/services/acp/acp_transport_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp client/test/services/acp
git commit -m "feat(acp): transport abstraction, NDJSON framing, frame logger

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: AcpAgentTranslator + gemini flag probing

**Files:**
- Create: `client/lib/services/acp/acp_agent_translator.dart`
- Create: `client/lib/services/cli/gemini/capabilities/acp.dart` (part 1: translator + probe, no full capability yet)
- Test: `client/test/services/acp/acp_agent_translator_test.dart`

**Interfaces:**
- Consumes: acpd error types (explore `package:acpd`'s exception/error exports in the submodule to use their real types — e.g. an `AcpError` with `code`/`data`).
- Produces:
  - `abstract class AcpAgentTranslator { String translateStopError(Object error, {required bool suppressAbort}); List<String> get flagCandidates; }` — return value is a human-readable error string OR the sentinel `AcpStopSentinels.cancelled` when the error should become a Cancelled stop reason.
  - `const acpStopCancelled = '__acp_stop_cancelled__'` sentinel in `acp_agent_translator.dart`.
  - `class GeminiAcpTranslator implements AcpAgentTranslator` — `flagCandidates => ['--acp', '--experimental-acp']`; translate: if error is a JSON-RPC InternalError whose `data.details` (or message) contains `'This operation was aborted'` or `'The user aborted a request'` and `suppressAbort` is true → sentinel; else stringify error with code + data.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/acp/acp_agent_translator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  const translator = GeminiAcpTranslator();

  test('flag candidates list acp then experimental-acp', () {
    expect(translator.flagCandidates, ['--acp', '--experimental-acp']);
  });

  test('aborted internal error with suppress → cancelled sentinel', () {
    final err = _FakeJsonRpcError(
      code: -32603,
      data: {'details': 'This operation was aborted'},
    );
    expect(
      translator.translateStopError(err, suppressAbort: true),
      acpStopCancelled,
    );
  });

  test('aborted internal error without suppress → surfaced error', () {
    final err = _FakeJsonRpcError(
      code: -32603,
      data: {'details': 'The user aborted a request'},
    );
    final out = translator.translateStopError(err, suppressAbort: false);
    expect(out, isNot(acpStopCancelled));
    expect(out, contains('-32603'));
  });

  test('non-aborted error passes through with code', () {
    final err = _FakeJsonRpcError(code: -32000, data: {'details': 'boom'});
    final out = translator.translateStopError(err, suppressAbort: true);
    expect(out, isNot(acpStopCancelled));
    expect(out, contains('boom'));
  });
}

class _FakeJsonRpcError implements Exception {
  _FakeJsonRpcError({required this.code, this.data});
  final int code;
  final Map<String, Object?>? data;
  @override
  String toString() => 'JsonRpcError($code, $data)';
}
```

(If acpd exports a typed error class with `code`/`data`, make the translator accept that type and make `_FakeJsonRpcError` implement/extend it instead — check the submodule exports first.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_agent_translator_test.dart`
Expected: FAIL — classes undefined.

- [ ] **Step 3: Implement**

```dart
// client/lib/services/acp/acp_agent_translator.dart
/// Sentinel returned when an agent error should become a Cancelled stop
/// reason instead of a surfaced error.
const String acpStopCancelled = '__acp_stop_cancelled__';

/// Per-agent absorption of protocol quirks. One implementation per ACP CLI,
/// declared by its AcpCapability — never an if (cli == …) at call sites.
abstract interface class AcpAgentTranslator {
  /// Candidate ACP flags in preference order (probed at launch).
  List<String> get flagCandidates;

  /// Map a prompt-phase error to a display string, or [acpStopCancelled].
  String translateStopError(Object error, {required bool suppressAbort});
}
```

`GeminiAcpTranslator` in `capabilities/acp.dart`: check error for `.code` (int) and `.data` (map) via duck-typing or acpd's error type; string-match the two abort phrases from gemini-cli (mirrors Zed `acp.rs:1925-1936` waiting on gemini-cli#6656).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_agent_translator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_agent_translator.dart client/lib/services/cli/gemini/capabilities/acp.dart client/test/services/acp/acp_agent_translator_test.dart
git commit -m "feat(acp): agent translator seam + gemini abort-error translation

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: AcpConnection over acpd

**Files:**
- Create: `client/lib/services/acp/acp_connection.dart`
- Test: `client/test/services/acp/acp_connection_test.dart`

**Interfaces:**
- Consumes: `AcpTransport`, `AcpFrameLogger`, acpd client APIs (explore the vendored package's example/README for the client connection API — likely `AcpConnection(client: ...)` over a custom transport, or a role-builder; adapt names to the real API).
- Produces:
  - `class AcpAgentConnection` — constructor takes `{required AcpTransport transport, required AcpFrameLogger logger, required AcpAgentTranslator translator}`. API:
    - `Future<AcpInitializeResult> initialize({required String clientName, required String clientVersion})` — negotiates protocolVersion; advertise `fs.readTextFile: false`, `fs.writeTextFile: false`, `terminal: false`; no MCP servers.
    - `AcpNegotiatedCapabilities get capabilities` — cached post-initialize (what session methods the agent supports: load/resume/close/list, loadSession, promptStreaming, etc. — map from acpd's initialize response).
    - `bool get isAlive`
    - `Future<void> dispose()` — transport.close() + drain.
  - `class AcpNegotiatedCapabilities` — plain data: `bool loadSession, sessionClose, sessionList, sessionResume, promptStreaming` (adjust fields to acpd's actual capability shape).

This task's integration tests use `acpd_test`'s in-memory transport pair to spin a mock agent — follow the package's own tests for the exact pairing API.

- [ ] **Step 1: Write the failing test**

Sketch (adapt to acpd_test's real API after reading its example):

```dart
// client/test/services/acp/acp_connection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_connection.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';
// + acpd_test mock-agent pair imports

void main() {
  test('initialize handshake caches agent capabilities', () async {
    // Spin the in-memory mock agent; wire its stream ends into an
    // AcpTransport adapter (acpd_test pairs are usually already
    // Stream-based — write a thin AcpTransport adapter for the test pair).
    final logger = AcpFrameLogger();
    final conn = AcpAgentConnection(
      transport: adapter, logger: logger,
      translator: const GeminiAcpTranslator(),
    );
    final result = await conn.initialize(
      clientName: 'teampilot', clientVersion: '1.0.0',
    );
    expect(result.protocolVersion, isNotNull);
    expect(conn.capabilities.sessionClose, isNotNull); // agent-declared
    expect(conn.isAlive, isTrue);
    await conn.dispose();
    expect(conn.isAlive, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_connection_test.dart`
Expected: FAIL — class undefined.

- [ ] **Step 3: Implement**

`acp_connection.dart` wraps the acpd client connection over our transport: mount the acpd client on the transport's streams (`input`/`write`), route stderr to `logger.logStderr`, log every outgoing/incoming frame via the logger, run `initialize` with the spec-mandated capability set (fs/terminal false, no MCP), and expose the negotiated capabilities snapshot. Dispose: close transport, mark dead. If acpd's transport is a different abstraction (e.g. its own `Transport` interface with `send`/`receive` string streams), write the adapter inside this file.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_connection_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_connection.dart client/test/services/acp/acp_connection_test.dart
git commit -m "feat(acp): AcpAgentConnection handshake + negotiated capabilities over vendored acpd

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: AcpSession — prompt/update/permission/cancel

**Files:**
- Create: `client/lib/services/acp/acp_session.dart`
- Test: `client/test/services/acp/acp_session_test.dart`

**Interfaces:**
- Consumes: `AcpAgentConnection`, `SeatHoldGate` (`services/agent_status/seat_hold_gate.dart`), `AgentPermissionRequest` + `AgentPermissionAlwaysOption` + `AgentPermissionReplyKind` (`services/agent_status/agent_permission_request.dart`), acpd session APIs.
- Produces:
  - `class AcpAgentSession` — created via `connection.openSession({required String cwd})`.
    - `Future<void> prompt(String text)` — returns when the stop reason arrives.
    - `Stream<AcpSessionUpdate> get updates` — where `AcpSessionUpdate` is a sealed union: `AcpMessageChunk({required AcpRole role, required String content, required bool isThought})`, `AcpToolCallUpdate(...)`, `AcpPlan(...)`, `AcpStop({required AcpStopKind kind})` (kind: end_turn/aborted/max_tokens/cancelled/error).
    - `Future<AgentPermissionReplyKind?> answerPermission(AgentPermissionReplyKind reply, {AgentPermissionAlwaysOption? always})` — completes the held request with the ACP outcome (allow-once → selected option 1; always → selected option with optionId echo; reject → outcome "rejected" or cancel semantics per acpd's outcome type).
    - `Stream<AgentPermissionRequest> get permissionRequests`
    - `void cancel()` — sends session/cancel; sets suppressAbort on the translator path; continues accepting tool-call updates until the stop reason.
  - All agent-specific error strings pass through the injected translator.

- [ ] **Step 1: Write the failing test**

Using acpd_test's mock agent (same harness as Task 6), script a mock sequence: prompt → 2 message chunks → stop(end_turn). Then a second script: prompt → request_permission → answer allowOnce → chunk → stop. Third: prompt → cancel → trailing tool update → stop(cancelled). Assert the `updates` stream yields the mapped events in order, the permission request surfaces on `permissionRequests`, and the mock agent received the outcome we sent.

Write these as three `test()` blocks; the mock agent scripting API comes from acpd_test (read its tests for how to script responses/notifications). Also test the permission timeout path: no answer within a short timeout (construct with `permissionTimeout: Duration(milliseconds: 50)`) → answer resolves `null` and the outcome sent is the reject/cancel default.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_test.dart`
Expected: FAIL — class undefined.

- [ ] **Step 3: Implement**

`acp_session.dart`: wrap acpd's session object. Map `session/update` notifications to the sealed `AcpSessionUpdate` union (message chunk → role/thought; tool call update → pending/running/completed; plan). Map `session/request_permission` server→client requests into `AgentPermissionRequest` (id from request id, description from the tool call's title/kind+input preview, always options from PermissionOptions with optionId payloads) and hold a single-slot wait using `SeatHoldGate<AgentPermissionReplyKind>` keyed by a synthetic seat (`sessionId`, memberId `acp`). `answerPermission` completes the hold; the acpd request completes with the mapped outcome. `prompt` wraps acpd's prompt future; on error route through `translator.translateStopError` — sentinel → emit `AcpStop(cancelled)` and complete normally. `cancel()` sends the notification, flips suppressAbort.

Permission option mapping detail: ACP `PermissionOption` has an optionId + name/description kind. "Yes" → allowOnce; option with rule-looking name → always option carrying `payload: optionId`; there is no deny option in ACP v1 — the card's reject maps to the request being answered with `cancelled` outcome (check acpd's outcome type; Zed maps deny → cancelled outcome).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_test.dart`
Expected: PASS (all scripted scenarios).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_session.dart client/test/services/acp/acp_session_test.dart
git commit -m "feat(acp): AcpAgentSession prompt/update stream/permission hold/cancel

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Gemini AcpCapability + launch env assembly

**Files:**
- Modify: `client/lib/services/cli/gemini/capabilities/acp.dart` (add capability)
- Create: `client/lib/services/cli/registry/capabilities/acp_capability.dart`
- Modify: `client/lib/services/cli/gemini/gemini_tool.dart` (add to capabilities)
- Test: `client/test/services/cli/gemini/gemini_acp_capability_test.dart`

**Interfaces:**
- Consumes: `AcpAgentTranslator` (Task 5), `AcpAgentConnection`/`AcpProcessTransport` (Tasks 4/6).
- Produces:
  - `abstract interface class AcpCapability implements CliCapability`:
    - `List<String> launchArgs(String executable)` — full argv including flags.
    - `AcpAgentTranslator get translator`
    - `Map<String, String> buildEnvironment({required String sessionToolDir, required String workingDirectory, Map<String, String> baseEnv})` — isolated config + auth env.
  - `class GeminiAcpCapability implements AcpCapability` — argv `[executable, ...flagCandidates]`; env: `{'GEMINI_CONFIG_DIR': '<sessionToolDir>/gemini', 'GEMINI_API_KEY': <injected key>, 'SURFACE': 'teampilot'}` where the key is passed in via a `GeminiAcpCredentialSource` typedef `String? Function()` injected at construction (tests inject fakes; production wires the credential store).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/gemini/gemini_acp_capability_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  test('launchArgs puts flags after executable', () {
    const cap = GeminiAcpCapability(credentialSource: null);
    expect(cap.launchArgs('/usr/bin/gemini'), [
      '/usr/bin/gemini', '--acp', '--experimental-acp',
    ]);
  });

  test('buildEnvironment isolates config and injects key + surface', () {
    String? key() => 'test-key';
    const cap = GeminiAcpCapability(credentialSource: key);
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/sessions/s1/tools',
      workingDirectory: '/work',
      baseEnv: const {'HOME': '/home/me'},
    );
    expect(env['GEMINI_CONFIG_DIR'], '/runtime/sessions/s1/tools/gemini');
    expect(env['GEMINI_API_KEY'], 'test-key');
    expect(env['SURFACE'], 'teampilot');
    expect(env.containsKey('HOME'), isTrue, reason: 'base env preserved');
  });

  test('buildEnvironment omits key when source returns null', () {
    String? key() => null;
    const cap = GeminiAcpCapability(credentialSource: key);
    final env = cap.buildEnvironment(
      sessionToolDir: '/d', workingDirectory: '/w', baseEnv: const {},
    );
    expect(env.containsKey('GEMINI_API_KEY'), isFalse);
  });
}
```

Note on `launchArgs` including both flags: `--experimental-acp` is NOT a second argv element in production — the connection probes `--acp` first (Task 6 connection start, Task 9 runtime). `launchArgs` returns the *candidate list per flag*: adjust the signature to `List<List<String>> launchArgCandidates(String executable)` so each candidate is a full argv; the first test then expects `[['/usr/bin/gemini', '--acp'], ['/usr/bin/gemini', '--experimental-acp']]`. Lock this shape now — Task 9 consumes it.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/gemini/gemini_acp_capability_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`acp_capability.dart` interface (see Produces above, with the `List<List<String>> launchArgCandidates` shape). `GeminiAcpCapability` in `capabilities/acp.dart`: argv = `[executable, flag]` per candidate; env assembly per test; `translator => const GeminiAcpTranslator()`. Add `acp` field to `GeminiCliTool` constructor + capabilities list.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/gemini/gemini_acp_capability_test.dart`
Expected: PASS. Re-run registry test to confirm gemini still registers: `dart run tool/run_tests.dart test/services/cli/gemini/gemini_registry_test.dart`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/acp_capability.dart client/lib/services/cli/gemini client/test/services/cli/gemini/gemini_acp_capability_test.dart
git commit -m "feat(acp): AcpCapability interface + gemini launch/env declaration

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: AcpSessionRuntime — process spawn, flag probe, chat message recording

**Files:**
- Create: `client/lib/services/acp/acp_session_runtime.dart`
- Test: `client/test/services/acp/acp_session_runtime_test.dart`

**Interfaces:**
- Consumes: `AcpCapability.launchArgCandidates`/`buildEnvironment` (Task 8), `AcpProcessTransport.start` (Task 4), `AcpAgentConnection` (Task 6), `AcpAgentSession` (Task 7), `CliToolRegistry.capability<AcpCapability>` lookup.
- Produces:
  - `class AcpSessionRuntime`:
    - Constructor `AcpSessionRuntime({required AcpConnectionSpawner spawner, required AcpFrameLogger logger})` where `typedef AcpConnectionSpawner = Future<AcpAgentConnection> Function(List<String> argv, Map<String, String> env)` — injectable for tests (fake connection, no process).
    - `Future<void> start({required CliTool tool, required String executable, required String sessionToolDir, required String workingDirectory, Map<String, String> baseEnv})` — looks up AcpCapability, builds env, probes flag candidates in order (spawner throws on initialize failure → try next candidate; all fail → throw `AcpLaunchException` with a version-message key), opens session with cwd=workingDirectory.
    - `Future<void> prompt(String text)`; `Stream<AcpSessionUpdate> get updates`; `Stream<AgentPermissionRequest> get permissionRequests`; `Future<AgentPermissionReplyKind?> answerPermission(...)` (delegate); `void cancel()`; `Future<void> close()`.
    - `AcpLaunchException({required this.reason})` with l10n key `acpLaunchFailedVersion`.

- [ ] **Step 1: Write the failing test**

Fake spawner: first call throws (simulating `--acp` rejected), second returns a fake connection. Assert: runtime start succeeds on candidate 2, the argv passed to the spawner on the second call was `[..., '--experimental-acp']`. Then: spawner always throws → `start` throws `AcpLaunchException` with `reason` containing the l10n key. Then: delegate test — `prompt`/`updates`/`cancel` pass through to the fake session; `close` disposes the connection.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Runtime composes the pieces; message recording into the app-side session message store happens at the ChatTab/cubit layer (Task 10) — this class only exposes streams. Flag probing: iterate candidates, catching initialize/handshake errors (distinguish "flag rejected" (process exits immediately / bad-argv error) from other failures — treat non-zero immediate exit as candidate failure; other errors rethrow).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_session_runtime.dart client/test/services/acp/acp_session_runtime_test.dart
git commit -m "feat(acp): AcpSessionRuntime with flag probing and session lifecycle

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Chat session integration — gemini branch in session creation + chat runtime cubit

**Files:**
- Create: `client/lib/cubits/chat/acp/acp_chat_runtime_cubit.dart`
- Modify: session creation flow — locate via `AppSession` factory callers (`cubits/chat` + session create page) by grepping for where `AppSession(cli: …)` selects CLI; add gemini branch that skips shell-connect and attaches `AcpChatRuntimeCubit`.
- Modify: `client/lib/cubits/chat/model/chat_tab.dart` — add `AcpChatRuntimeCubit? acpRuntime` field (parallel to `memberShells`; chat center view only, no terminal toggle).
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `AcpSessionRuntime` (Task 9), existing chat message model + cubit base patterns (read an existing member chat cubit for the message-append API), `AgentPermissionRequest` card plumbing.
- Produces: a cubit that: on start, launches the runtime; maps `AcpSessionUpdate` → chat messages (message chunk → chat message, thought → collapsed-style flag, tool call → tool card message, stop → member idle state); records every message into the app-side session message store (persistence decision from spec: app-side message table, single source); surfaces permission requests to the existing card; maps `AcpStop(cancelled)` silently, error stops → inline system message (l10n), process crash → inline system message with exit code + session ended.

This task is the UI seam. Its exact file list depends on how the existing new-session flow picks CLI — the executor must grep first (`rg "AppSession(" client/lib/cubits client/lib/pages` + the session-create page) and follow the existing pattern for a non-team (Simple) session. Keep the gemini branch minimal: no roster, no TeamBus, no shell connect.

- [ ] **Step 1: Write the failing test**

Cubit test with a fake `AcpSessionRuntime` (all-stub interface from Task 9 consumed as an interface — if Task 9 produced a concrete class, extract `interface class` in this task): fake updates stream emits a message chunk + stop(end_turn) → assert cubit state contains one chat message and member idle. Fake permission request → assert state exposes the pending card; answer → assert delegate called. Crash: fake runtime `start` throws `AcpLaunchException` → assert state has an inline error message and session-ended state.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Follow existing chat cubit patterns (read `cubits/chat/` siblings for state shape and message-append APIs). Use `setUpTestAppStorage()`/`tearDownTestAppStorage()` from `test/support/post_frame_test_harness.dart` for home-plane needs.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/acp client/lib/cubits/chat/model/chat_tab.dart client/test/cubits/chat/acp
git commit -m "feat(acp): chat runtime cubit + gemini terminal-less session branch

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Acceptance — real gemini end-to-end + full suite

**Files:**
- No new source files. Possibly small fixes surfaced by manual testing.

**Interfaces:**
- Consumes: everything.

- [ ] **Step 1: Full analyze + suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze clean, full suite green (run in background per test-loop rules).

- [ ] **Step 2: Manual acceptance (desktop-local, real gemini)**

With `GEMINI_API_KEY` in the credential store and gemini installed: create a gemini session, verify — conversation round-trip (prompt → streamed message chunks → idle), a tool call renders as a tool card, a permission request shows the existing card and allow/deny both work (allow → agent proceeds; deny → agent adapts), cancel mid-prompt → silent cancelled state, `kill <pid>` externally → inline crash message + session ended. Check the frame log view entry shows redacted frames.

- [ ] **Step 3: Record results**

Note any deviations in the commit; fix what's real before commit.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(acp): gemini ACP terminal-less session shipped

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Deferred (spec out-of-scope, tracked follow-ups)

SSH remote transport (`SshExecTransport`), TeamBus/roster mapping, claude/codex adapters + opencode native, OAuth, session/load resume, fs/*/terminal/* client capabilities, ACP registry-driven install.
