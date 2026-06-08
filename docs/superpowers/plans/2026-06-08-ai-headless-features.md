# AI Headless Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AI commit-message generation (in the source-control panel) and AI team-config generation (in the new-team flow), both powered by a shared headless one-shot CLI invocation subsystem with per-feature provider/model/effort config.

**Architecture:** Approach A — a registry capability `HeadlessRunCapability` (one impl per CLI) behind a thin `HeadlessAiService` that builds prompts into one-shot CLI runs and returns text. Per-feature `(CLI, provider, model, effort)` lives in `AppSettings` and is surfaced by an "AI Features" config section. The two features are thin consumers of `HeadlessAiService`.

**Tech Stack:** Dart/Flutter, `flutter_bloc`, the existing CLI tool registry/capability system, `ProcessRunner`/`Process.run`, `shared_preferences`, `flutter_test`.

**Working directory:** All paths are relative to repo root. Flutter commands run from `client/`.

**Verification command (run after every implementation task):**
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

---

## File Structure

**Phase 1 — Shared subsystem**
- Create `client/lib/services/cli/registry/capabilities/headless_run_capability.dart` — interface + value types (`HeadlessRunContext`, `HeadlessConfigFile`, `HeadlessInvocation`).
- Create `client/lib/services/cli/registry/headless/claude_headless_run_capability.dart` — Claude impl.
- Create `client/lib/services/cli/registry/headless/codex_headless_run_capability.dart` — Codex impl.
- Create `client/lib/services/cli/registry/headless/cursor_headless_run_capability.dart` — Cursor impl.
- Create `client/lib/services/cli/registry/headless/opencode_headless_run_capability.dart` — opencode impl.
- Create `client/lib/services/cli/registry/headless/flashskyai_headless_run_capability.dart` — flashskyai impl.
- Create `client/lib/services/ai/headless_ai_service.dart` — orchestrator + `HeadlessAiResult` + `HeadlessAiException` + runner typedefs.
- Modify `client/lib/services/cli/registry/tools/{claude,codex,cursor,opencode,flashskyai}_cli_tool.dart` — register the new capability.

**Phase 2 — Per-feature config**
- Create `client/lib/models/ai_feature_setting.dart` — `AiFeatureSetting` + `AiFeatureId`.
- Modify `client/lib/repositories/app_settings_repository.dart` — load/save `aiFeatures`.
- Create `client/lib/cubits/ai_feature_settings_cubit.dart` — state + cubit.
- Create `client/lib/pages/config/ai_features_config_section.dart` — settings UI.
- Modify `client/lib/cubits/config_cubit.dart`, `client/lib/pages/config/config_workspace.dart`, `client/lib/router/app_router.dart` — mount the section.
- Modify `client/lib/app/app_shell.dart`, `client/lib/main.dart` — provide the cubit.

**Phase 3 — Commit message generation**
- Modify `client/lib/services/git/git_service.dart` — `stagedDiff()`.
- Create `client/lib/services/ai/commit_message_prompt.dart` — pure prompt builder + output cleaner.
- Modify `client/lib/cubits/git_cubit.dart` — `generateCommitMessage()` + state flag.
- Modify `client/lib/widgets/git/git_source_control_panel.dart` — Generate button.

**Phase 4 — Team config generation**
- Create `client/lib/services/ai/team_config_prompt.dart` — pure prompt builder.
- Create `client/lib/services/ai/team_config_draft.dart` — draft value types + pure parser/clamp.
- Create `client/lib/services/ai/team_config_generator.dart` — orchestration + retry.
- Create `client/lib/pages/home_workspace/home_workspace_team_generate_section.dart` — UI section.
- Modify `client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart` — mount the section + apply draft.

**l10n** (modified throughout): `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`.

---

# Phase 1 — Shared headless subsystem

### Task 1: Headless capability interface + value types

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/headless_run_capability.dart`
- Test: `client/test/services/cli/registry/headless_run_capability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/headless_run_capability_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';

void main() {
  test('HeadlessRunContext exposes its fields verbatim', () {
    const ctx = HeadlessRunContext(
      prompt: 'hi',
      model: 'sonnet',
      effort: 'high',
      configDir: '/tmp/cfg',
      workingDirectory: '/repo',
      expectJson: true,
    );
    expect(ctx.prompt, 'hi');
    expect(ctx.model, 'sonnet');
    expect(ctx.effort, 'high');
    expect(ctx.configDir, '/tmp/cfg');
    expect(ctx.workingDirectory, '/repo');
    expect(ctx.expectJson, isTrue);
  });

  test('HeadlessInvocation defaults environment to empty', () {
    const inv = HeadlessInvocation(executable: 'claude', arguments: ['-p', 'x']);
    expect(inv.executable, 'claude');
    expect(inv.arguments, ['-p', 'x']);
    expect(inv.environment, isEmpty);
  });

  test('HeadlessConfigFile holds relative path and contents', () {
    const f = HeadlessConfigFile(relativePath: 'settings.json', contents: '{}');
    expect(f.relativePath, 'settings.json');
    expect(f.contents, '{}');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/headless_run_capability_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / types not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/cli/registry/capabilities/headless_run_capability.dart
import 'dart:io';

import '../cli_capability.dart';

/// Inputs for building a one-shot headless CLI call.
class HeadlessRunContext {
  const HeadlessRunContext({
    required this.prompt,
    required this.model,
    required this.effort,
    required this.configDir,
    this.workingDirectory,
    this.expectJson = false,
  });

  /// The full prompt text to send to the model.
  final String prompt;

  /// Resolved model id (may be empty to use the CLI default).
  final String model;

  /// Resolved reasoning effort (empty = not applicable / CLI default).
  final String effort;

  /// Isolated, already-created temp config dir the CLI may use.
  final String configDir;

  /// Working directory for the run (repo root for commit generation).
  final String? workingDirectory;

  /// When true, ask the CLI for machine-readable output if it supports it.
  final bool expectJson;
}

/// A file the service writes into [HeadlessRunContext.configDir] before running.
class HeadlessConfigFile {
  const HeadlessConfigFile({
    required this.relativePath,
    required this.contents,
  });

  final String relativePath;
  final String contents;
}

/// A fully-specified one-shot process invocation.
class HeadlessInvocation {
  const HeadlessInvocation({
    required this.executable,
    required this.arguments,
    this.environment = const {},
  });

  /// Executable name (resolved to a path by the service via the locator).
  final String executable;
  final List<String> arguments;

  /// Extra environment entries (merged onto the parent environment).
  final Map<String, String> environment;
}

/// Per-CLI one-shot (non-interactive) invocation support.
///
/// One implementation per CLI tool, registered alongside [LaunchArgsCapability]
/// on the tool definition. Pure: it returns data (files, invocation) and parses
/// stdout; the service owns the filesystem and process execution.
abstract interface class HeadlessRunCapability implements CliCapability {
  /// Whether this CLI can run a one-shot headless call.
  bool get isSupported;

  /// Config files to materialize into [HeadlessRunContext.configDir] first.
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx);

  /// Build the executable + args + env for the one-shot call.
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx);

  /// Extract the model's final text from process stdout (unwrap any envelope).
  String extractText(ProcessResult result);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/headless_run_capability_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/headless_run_capability.dart client/test/services/cli/registry/headless_run_capability_test.dart
git commit -m "feat(headless): add HeadlessRunCapability interface + value types"
```

---

### Task 2: Claude headless capability

**Files:**
- Create: `client/lib/services/cli/registry/headless/claude_headless_run_capability.dart`
- Test: `client/test/services/cli/registry/headless/claude_headless_run_capability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/headless/claude_headless_run_capability_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/claude_headless_run_capability.dart';

HeadlessRunContext _ctx({
  String model = 'sonnet',
  String effort = '',
  bool expectJson = false,
}) => HeadlessRunContext(
      prompt: 'Write a commit message',
      model: model,
      effort: effort,
      configDir: '/tmp/cfg',
      expectJson: expectJson,
    );

void main() {
  const cap = ClaudeHeadlessRunCapability();

  test('isSupported is true', () => expect(cap.isSupported, isTrue));

  test('buildInvocation passes -p, model, json flag and CONFIG_DIR env', () {
    final inv = cap.buildInvocation(_ctx(expectJson: true));
    expect(inv.executable, 'claude');
    expect(inv.arguments, [
      '-p', 'Write a commit message',
      '--model', 'sonnet',
      '--output-format', 'json',
    ]);
    expect(inv.environment['CLAUDE_CONFIG_DIR'], '/tmp/cfg');
  });

  test('buildInvocation omits json flag when expectJson is false', () {
    final inv = cap.buildInvocation(_ctx());
    expect(inv.arguments.contains('--output-format'), isFalse);
  });

  test('configFiles writes effortLevel settings only when effort set', () {
    expect(cap.configFiles(_ctx()), isEmpty);
    final files = cap.configFiles(_ctx(effort: 'high'));
    expect(files, hasLength(1));
    expect(files.first.relativePath, 'settings.json');
    expect(files.first.contents, contains('"effortLevel":"high"'));
  });

  test('extractText unwraps the JSON result field', () {
    final r = ProcessResult(0, 0, '{"result":"feat: add thing"}', '');
    expect(cap.extractText(r), 'feat: add thing');
  });

  test('extractText returns raw stdout when not JSON', () {
    final r = ProcessResult(0, 0, 'feat: plain text', '');
    expect(cap.extractText(r), 'feat: plain text');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/headless/claude_headless_run_capability_test.dart`
Expected: FAIL — class not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/cli/registry/headless/claude_headless_run_capability.dart
import 'dart:convert';
import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// Claude one-shot via `claude -p`. Effort is expressed through a temp
/// `settings.json` (`effortLevel`) under `CLAUDE_CONFIG_DIR`.
final class ClaudeHeadlessRunCapability implements HeadlessRunCapability {
  const ClaudeHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) {
    final effort = ctx.effort.trim();
    if (effort.isEmpty) return const [];
    return [
      HeadlessConfigFile(
        relativePath: 'settings.json',
        contents: jsonEncode({'effortLevel': effort}),
      ),
    ];
  }

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['-p', ctx.prompt];
    final model = ctx.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }
    if (ctx.expectJson) {
      args.addAll(['--output-format', 'json']);
    }
    return HeadlessInvocation(
      executable: 'claude',
      arguments: args,
      environment: {'CLAUDE_CONFIG_DIR': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) {
    final out = (result.stdout as String? ?? '').trim();
    if (out.isEmpty) return '';
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map && decoded['result'] is String) {
        return (decoded['result'] as String).trim();
      }
    } on FormatException {
      // Plain-text mode: stdout is the message itself.
    }
    return out;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/headless/claude_headless_run_capability_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/headless/claude_headless_run_capability.dart client/test/services/cli/registry/headless/claude_headless_run_capability_test.dart
git commit -m "feat(headless): add Claude headless run capability"
```

---

### Task 3: `HeadlessAiService` orchestrator

**Files:**
- Create: `client/lib/services/ai/headless_ai_service.dart`
- Test: `client/test/services/ai/headless_ai_service_test.dart`

This service: resolves provider + model + effort, materializes a temp config dir, writes the capability's config files, resolves the executable, runs the process (with timeout), and unwraps the text.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/ai/headless_ai_service_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/headless_ai_service.dart';

void main() {
  late Directory tempRoot;

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('tp_headless_test_'));
  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  AiFeatureSetting setting({String effort = ''}) => AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'claude-official',
        model: 'sonnet',
        effort: effort,
      );

  test('runs the resolved invocation and returns extracted text', () async {
    late String ranExecutable;
    late List<String> ranArgs;
    final service = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => '/usr/bin/$name',
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory}) async {
        ranExecutable = exe;
        ranArgs = args;
        return ProcessResult(0, 0, '{"result":"feat: x"}', '');
      },
    );

    final result = await service.run(
      setting: setting(),
      prompt: 'p',
      expectJson: true,
    );

    expect(ranExecutable, '/usr/bin/claude');
    expect(ranArgs, contains('--output-format'));
    expect(result.text, 'feat: x');
    expect(result.exitCode, 0);
  });

  test('writes effort settings file into the temp config dir', () async {
    Directory? usedDir;
    final service = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => name,
      tempDirFactory: () async => usedDir = tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory}) async =>
          ProcessResult(0, 0, 'ok', ''),
    );

    await service.run(setting: setting(effort: 'high'), prompt: 'p');

    final settingsFile = File('${usedDir!.path}/settings.json');
    expect(settingsFile.existsSync(), isTrue);
    expect(settingsFile.readAsStringSync(), contains('"effortLevel":"high"'));
  });

  test('throws when executable is not found', () async {
    final service = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (_) async => null,
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory}) async =>
          ProcessResult(0, 0, '', ''),
    );

    expect(
      () => service.run(setting: setting(), prompt: 'p'),
      throwsA(isA<HeadlessAiException>()),
    );
  });

  test('throws on non-zero exit code', () async {
    final service = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => name,
      tempDirFactory: () async => tempRoot.createTempSync('run_'),
      run: (exe, args, {environment, workingDirectory}) async =>
          ProcessResult(0, 2, '', 'boom'),
    );

    expect(
      () => service.run(setting: setting(), prompt: 'p'),
      throwsA(
        isA<HeadlessAiException>().having((e) => e.message, 'message', contains('boom')),
      ),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/ai/headless_ai_service_test.dart`
Expected: FAIL — `HeadlessAiService` / `HeadlessAiException` not defined (and `AiFeatureSetting` not defined yet — see note below).

> **Note:** `AiFeatureSetting` is created in Task 5. This test will not compile until Task 5 lands. Implement Task 3's production code now; if running standalone before Task 5, temporarily skip this test file. The dependency is intentional — keep the commit order Task 3 → Task 5, then re-run this suite. (Simpler alternative: do Task 5 first, then Task 3. Either order works; the plan lists Task 3 first because it is the architectural core.)

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/ai/headless_ai_service.dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/ai_feature_setting.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../../utils/logger.dart';
import '../cli/cli_tool_locator.dart';
import '../cli/registry/capabilities/cli_effort_capability.dart';
import '../cli/registry/capabilities/headless_run_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

/// Thrown when a headless AI call cannot run or fails.
class HeadlessAiException implements Exception {
  HeadlessAiException(this.message);
  final String message;
  @override
  String toString() => 'HeadlessAiException: $message';
}

class HeadlessAiResult {
  const HeadlessAiResult({
    required this.text,
    required this.rawStdout,
    required this.exitCode,
  });
  final String text;
  final String rawStdout;
  final int exitCode;
}

typedef HeadlessProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

typedef HeadlessProviderResolver =
    Future<AppProviderConfig?> Function(CliTool cli, String id);

typedef HeadlessExecutableResolver = Future<String?> Function(String name);

Future<ProcessResult> headlessDefaultProcessRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
}) {
  return Process.run(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: true,
    workingDirectory: workingDirectory,
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );
}

/// Runs a single one-shot CLI call for AI features. Reuses the CLI registry's
/// [HeadlessRunCapability] per tool; all IO is injectable for tests.
class HeadlessAiService {
  HeadlessAiService({
    CliToolRegistry? registry,
    HeadlessProcessRunner run = headlessDefaultProcessRun,
    HeadlessProviderResolver? resolveProvider,
    HeadlessExecutableResolver? resolveExecutable,
    Future<Directory> Function()? tempDirFactory,
  }) : _registry = registry ?? CliToolRegistry.builtIn(),
       _run = run,
       _resolveProvider =
           resolveProvider ?? AppProviderRepository().findById,
       _resolveExecutable =
           resolveExecutable ?? ((name) => CliToolLocator(name).locate()),
       _tempDirFactory =
           tempDirFactory ??
           (() => Directory.systemTemp.createTemp('tp_headless_'));

  final CliToolRegistry _registry;
  final HeadlessProcessRunner _run;
  final HeadlessProviderResolver _resolveProvider;
  final HeadlessExecutableResolver _resolveExecutable;
  final Future<Directory> Function() _tempDirFactory;

  Future<HeadlessAiResult> run({
    required AiFeatureSetting setting,
    required String prompt,
    bool expectJson = false,
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final cli = setting.cli;
    final cap = _registry.capability<HeadlessRunCapability>(cli);
    if (cap == null || !cap.isSupported) {
      throw HeadlessAiException(
        'Headless mode is not supported for ${cli.value}.',
      );
    }

    final provider = await _resolveProvider(cli, setting.providerId);
    final model = setting.model.trim().isNotEmpty
        ? setting.model.trim()
        : (provider?.defaultModel.trim() ?? '');
    final effort = _resolveEffort(cli, model, provider, setting.effort);

    final dir = await _tempDirFactory();
    try {
      final ctx = HeadlessRunContext(
        prompt: prompt,
        model: model,
        effort: effort,
        configDir: dir.path,
        workingDirectory: workingDirectory,
        expectJson: expectJson,
      );

      for (final file in cap.configFiles(ctx)) {
        final out = File(p.join(dir.path, file.relativePath));
        await out.parent.create(recursive: true);
        await out.writeAsString(file.contents);
      }

      final inv = cap.buildInvocation(ctx);
      final exe = await _resolveExecutable(inv.executable);
      if (exe == null) {
        throw HeadlessAiException('${inv.executable} not found on PATH.');
      }

      final ProcessResult result;
      try {
        result = await _run(
          exe,
          inv.arguments,
          environment: inv.environment.isEmpty ? null : inv.environment,
          workingDirectory: ctx.workingDirectory,
        ).timeout(timeout);
      } on TimeoutException {
        throw HeadlessAiException(
          'AI call timed out after ${timeout.inSeconds}s.',
        );
      }

      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        final out = (result.stdout as String? ?? '').trim();
        final detail = err.isNotEmpty ? err : out;
        appLogger.d('[Headless] ${cli.value} exit ${result.exitCode}: $detail');
        throw HeadlessAiException(
          detail.isEmpty ? 'AI call failed (${cli.value}).' : detail,
        );
      }

      return HeadlessAiResult(
        text: cap.extractText(result),
        rawStdout: (result.stdout as String? ?? ''),
        exitCode: result.exitCode,
      );
    } finally {
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup; ignore.
        }
      }
    }
  }

  String _resolveEffort(
    CliTool cli,
    String model,
    AppProviderConfig? provider,
    String requested,
  ) {
    final cap = _registry.capability<CliEffortCapability>(cli);
    if (cap == null || !cap.isApplicable(model: model)) return '';
    final r = requested.trim();
    if (r.isNotEmpty) return r;
    return cap.defaultEffort(model: model, provider: provider);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes** (after Task 5 lands)

Run: `cd client && flutter test test/services/ai/headless_ai_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ai/headless_ai_service.dart client/test/services/ai/headless_ai_service_test.dart
git commit -m "feat(headless): add HeadlessAiService orchestrator"
```

---

### Task 4: Remaining CLI headless capabilities (codex, cursor, opencode, flashskyai)

**Files:**
- Create: `client/lib/services/cli/registry/headless/codex_headless_run_capability.dart`
- Create: `client/lib/services/cli/registry/headless/cursor_headless_run_capability.dart`
- Create: `client/lib/services/cli/registry/headless/opencode_headless_run_capability.dart`
- Create: `client/lib/services/cli/registry/headless/flashskyai_headless_run_capability.dart`
- Test: `client/test/services/cli/registry/headless/other_headless_run_capabilities_test.dart`

> **Verify CLI flags before/while implementing** (these are best-effort defaults aligned to known CLI behavior and the project memory notes; confirm with `--help`):
> - `codex exec --help`
> - `cursor-agent --help` (print mode `-p`; env `CURSOR_CONFIG_DIR`)
> - `opencode run --help` (env `OPENCODE_CONFIG_DIR`)
> - `flashskyai --help` (assumed `-p` print mode like Claude)
> If a flag differs, adjust both the implementation and its test assertion in this task.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/headless/other_headless_run_capabilities_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/codex_headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/cursor_headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/opencode_headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/headless/flashskyai_headless_run_capability.dart';

HeadlessRunContext ctx({String effort = '', String model = 'm'}) =>
    HeadlessRunContext(
      prompt: 'P',
      model: model,
      effort: effort,
      configDir: '/tmp/c',
    );

void main() {
  test('codex: exec + model + effort override + CODEX_HOME', () {
    const cap = CodexHeadlessRunCapability();
    expect(cap.isSupported, isTrue);
    final inv = cap.buildInvocation(ctx(effort: 'high'));
    expect(inv.executable, 'codex');
    expect(inv.arguments.first, 'exec');
    expect(inv.arguments, containsAllInOrder(['--model', 'm']));
    expect(inv.arguments, containsAllInOrder(['-c', 'model_reasoning_effort=high']));
    expect(inv.arguments.last, 'P');
    expect(inv.environment['CODEX_HOME'], '/tmp/c');
    expect(cap.extractText(ProcessResult(0, 0, ' out ', '')), 'out');
  });

  test('cursor: -p prompt + model + CURSOR_CONFIG_DIR', () {
    const cap = CursorHeadlessRunCapability();
    final inv = cap.buildInvocation(ctx());
    expect(inv.executable, 'cursor-agent');
    expect(inv.arguments, containsAllInOrder(['-p', 'P']));
    expect(inv.arguments, containsAllInOrder(['--model', 'm']));
    expect(inv.environment['CURSOR_CONFIG_DIR'], '/tmp/c');
  });

  test('opencode: run prompt + model + OPENCODE_CONFIG_DIR', () {
    const cap = OpencodeHeadlessRunCapability();
    final inv = cap.buildInvocation(ctx());
    expect(inv.executable, 'opencode');
    expect(inv.arguments.first, 'run');
    expect(inv.arguments, containsAllInOrder(['--model', 'm']));
    expect(inv.environment['OPENCODE_CONFIG_DIR'], '/tmp/c');
  });

  test('flashskyai: -p print mode', () {
    const cap = FlashskyaiHeadlessRunCapability();
    final inv = cap.buildInvocation(ctx());
    expect(inv.executable, 'flashskyai');
    expect(inv.arguments, containsAllInOrder(['-p', 'P']));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/headless/other_headless_run_capabilities_test.dart`
Expected: FAIL — classes not defined.

- [ ] **Step 3: Write the implementations**

```dart
// client/lib/services/cli/registry/headless/codex_headless_run_capability.dart
import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// Codex one-shot via `codex exec`. Effort via `-c model_reasoning_effort=`.
final class CodexHeadlessRunCapability implements HeadlessRunCapability {
  const CodexHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['exec'];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    final effort = ctx.effort.trim();
    if (effort.isNotEmpty) {
      args.addAll(['-c', 'model_reasoning_effort=$effort']);
    }
    args.add(ctx.prompt);
    return HeadlessInvocation(
      executable: 'codex',
      arguments: args,
      environment: {'CODEX_HOME': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();
}
```

```dart
// client/lib/services/cli/registry/headless/cursor_headless_run_capability.dart
import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// Cursor one-shot via `cursor-agent -p`.
final class CursorHeadlessRunCapability implements HeadlessRunCapability {
  const CursorHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['-p', ctx.prompt];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    return HeadlessInvocation(
      executable: 'cursor-agent',
      arguments: args,
      environment: {'CURSOR_CONFIG_DIR': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();
}
```

```dart
// client/lib/services/cli/registry/headless/opencode_headless_run_capability.dart
import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// opencode one-shot via `opencode run`.
final class OpencodeHeadlessRunCapability implements HeadlessRunCapability {
  const OpencodeHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['run'];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    args.add(ctx.prompt);
    return HeadlessInvocation(
      executable: 'opencode',
      arguments: args,
      environment: {'OPENCODE_CONFIG_DIR': ctx.configDir},
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();
}
```

```dart
// client/lib/services/cli/registry/headless/flashskyai_headless_run_capability.dart
import 'dart:io';

import '../capabilities/headless_run_capability.dart';

/// flashskyai one-shot via `-p` print mode (Claude-style CLI).
final class FlashskyaiHeadlessRunCapability implements HeadlessRunCapability {
  const FlashskyaiHeadlessRunCapability();

  @override
  bool get isSupported => true;

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  HeadlessInvocation buildInvocation(HeadlessRunContext ctx) {
    final args = <String>['-p', ctx.prompt];
    final model = ctx.model.trim();
    if (model.isNotEmpty) args.addAll(['--model', model]);
    return HeadlessInvocation(
      executable: 'flashskyai',
      arguments: args,
    );
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/headless/other_headless_run_capabilities_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/headless/ client/test/services/cli/registry/headless/other_headless_run_capabilities_test.dart
git commit -m "feat(headless): add codex/cursor/opencode/flashskyai headless capabilities"
```

---

### Task 5: Register headless capabilities on the CLI tool definitions

**Files:**
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/codex_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/cursor_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/opencode_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/tools/flashskyai_cli_tool.dart`
- Test: `client/test/services/cli/registry/headless_registration_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/headless_registration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every supported CLI exposes a HeadlessRunCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in [
      CliTool.claude,
      CliTool.codex,
      CliTool.cursor,
      CliTool.opencode,
      CliTool.flashskyai,
    ]) {
      final cap = registry.capability<HeadlessRunCapability>(cli);
      expect(cap, isNotNull, reason: '${cli.value} missing HeadlessRunCapability');
      expect(cap!.isSupported, isTrue);
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/headless_registration_test.dart`
Expected: FAIL — capability is null for each CLI.

- [ ] **Step 3: Wire the capability into `claude_cli_tool.dart`**

Add the import near the other capability imports:

```dart
import '../headless/claude_headless_run_capability.dart';
```

Add a constructor default and field (place alongside `effort`):

```dart
    this.effort = const ClaudeEffortCapability(),
    this.headlessRun = const ClaudeHeadlessRunCapability(),
    ProviderCredentialCapability? providerCredential,
```

```dart
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
```

Add the import for the interface type:

```dart
import '../capabilities/headless_run_capability.dart';
```

Add `headlessRun` to the `capabilities` list:

```dart
  @override
  Iterable<CliCapability> get capabilities => [
    launchArgs,
    configProfile,
    transcriptProbe,
    executableResolver,
    installer,
    presence,
    display,
    terminalBehavior,
    pluginManifest,
    providerCatalog,
    providerModel,
    providerCredential,
    effort,
    headlessRun,
  ];
```

- [ ] **Step 4: Wire the capability into the other four tool files**

For each of `codex_cli_tool.dart`, `cursor_cli_tool.dart`, `opencode_cli_tool.dart`, `flashskyai_cli_tool.dart`:
1. Add imports:
   ```dart
   import '../capabilities/headless_run_capability.dart';
   import '../headless/<cli>_headless_run_capability.dart';
   ```
   (use the matching file: `codex_headless_run_capability.dart`, `cursor_headless_run_capability.dart`, `opencode_headless_run_capability.dart`, `flashskyai_headless_run_capability.dart`)
2. Add a constructor default + field:
   ```dart
   this.headlessRun = const CodexHeadlessRunCapability(), // Cursor/Opencode/Flashskyai for the others
   ```
   ```dart
   final HeadlessRunCapability headlessRun;
   ```
3. Add `headlessRun,` to the `capabilities` getter list.

> If a tool file constructs its capabilities differently (e.g. via a builder), follow that file's existing pattern — the requirement is only that `headlessRun` ends up in `capabilities`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/headless_registration_test.dart`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/registry/tools/ client/test/services/cli/registry/headless_registration_test.dart
git commit -m "feat(headless): register headless capabilities on all CLI tools"
```

---

# Phase 2 — Per-feature config

### Task 6: `AiFeatureSetting` + `AiFeatureId` model

**Files:**
- Create: `client/lib/models/ai_feature_setting.dart`
- Test: `client/test/models/ai_feature_setting_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/ai_feature_setting_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('AiFeatureId.tryParse maps keys and rejects junk', () {
    expect(AiFeatureId.tryParse('commitMessage'), AiFeatureId.commitMessage);
    expect(AiFeatureId.tryParse('teamGenerate'), AiFeatureId.teamGenerate);
    expect(AiFeatureId.tryParse('nope'), isNull);
  });

  test('round-trips through json', () {
    const setting = AiFeatureSetting(
      cli: CliTool.claude,
      providerId: 'claude-official',
      model: 'sonnet',
      effort: 'high',
    );
    final restored = AiFeatureSetting.fromJson(setting.toJson());
    expect(restored.cli, CliTool.claude);
    expect(restored.providerId, 'claude-official');
    expect(restored.model, 'sonnet');
    expect(restored.effort, 'high');
  });

  test('fromJson tolerates missing fields', () {
    final s = AiFeatureSetting.fromJson(const {});
    expect(s.cli, CliTool.claude);
    expect(s.providerId, '');
    expect(s.model, '');
    expect(s.effort, '');
  });

  test('copyWith overrides selected fields', () {
    const s = AiFeatureSetting(cli: CliTool.claude, providerId: 'p', model: 'm');
    final s2 = s.copyWith(model: 'opus', effort: 'low');
    expect(s2.model, 'opus');
    expect(s2.effort, 'low');
    expect(s2.providerId, 'p');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/models/ai_feature_setting_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/models/ai_feature_setting.dart
import 'team_config.dart';

/// AI features that have their own (CLI, provider, model, effort) config.
enum AiFeatureId {
  commitMessage('commitMessage'),
  teamGenerate('teamGenerate');

  const AiFeatureId(this.key);

  final String key;

  static AiFeatureId? tryParse(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty) return null;
    for (final id in AiFeatureId.values) {
      if (id.key == v) return id;
    }
    return null;
  }
}

/// Which CLI provider/model/effort a single AI feature should use.
class AiFeatureSetting {
  const AiFeatureSetting({
    required this.cli,
    required this.providerId,
    required this.model,
    this.effort = '',
  });

  final CliTool cli;
  final String providerId;
  final String model;

  /// Empty = use the capability default.
  final String effort;

  factory AiFeatureSetting.fromJson(Map<String, Object?> json) {
    return AiFeatureSetting(
      cli: CliTool.parse(json['cli'], fallback: CliTool.claude),
      providerId: (json['providerId'] as String? ?? '').trim(),
      model: (json['model'] as String? ?? '').trim(),
      effort: (json['effort'] as String? ?? '').trim(),
    );
  }

  Map<String, Object?> toJson() => {
    'cli': cli.value,
    'providerId': providerId,
    'model': model,
    'effort': effort,
  };

  AiFeatureSetting copyWith({
    CliTool? cli,
    String? providerId,
    String? model,
    String? effort,
  }) {
    return AiFeatureSetting(
      cli: cli ?? this.cli,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      effort: effort ?? this.effort,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/models/ai_feature_setting_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/ai_feature_setting.dart client/test/models/ai_feature_setting_test.dart
git commit -m "feat(ai-config): add AiFeatureSetting + AiFeatureId model"
```

---

### Task 7: Persist `aiFeatures` in `AppSettingsRepository`

**Files:**
- Modify: `client/lib/repositories/app_settings_repository.dart`
- Test: `client/test/repositories/app_settings_repository_ai_features_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/repositories/app_settings_repository_ai_features_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves and loads a per-feature setting', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsAppSettingsRepository(prefs);

    await repo.saveAiFeatureSetting(
      AiFeatureId.commitMessage,
      const AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'claude-official',
        model: 'sonnet',
        effort: 'high',
      ),
    );

    final all = await repo.loadAiFeatureSettings();
    final s = all[AiFeatureId.commitMessage]!;
    expect(s.cli, CliTool.claude);
    expect(s.model, 'sonnet');
    expect(s.effort, 'high');
  });

  test('returns empty map when nothing stored', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsAppSettingsRepository(prefs);
    expect(await repo.loadAiFeatureSettings(), isEmpty);
  });

  test('in-memory implementation round-trips', () async {
    final repo = InMemoryAppSettingsRepository();
    await repo.saveAiFeatureSetting(
      AiFeatureId.teamGenerate,
      const AiFeatureSetting(cli: CliTool.codex, providerId: 'p', model: 'm'),
    );
    final all = await repo.loadAiFeatureSettings();
    expect(all[AiFeatureId.teamGenerate]!.cli, CliTool.codex);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/repositories/app_settings_repository_ai_features_test.dart`
Expected: FAIL — `loadAiFeatureSettings` / `saveAiFeatureSetting` not defined.

- [ ] **Step 3: Extend the abstract interface**

In `app_settings_repository.dart`, add to `abstract class AppSettingsRepository`:

```dart
  Future<Map<AiFeatureId, AiFeatureSetting>> loadAiFeatureSettings();
  Future<void> saveAiFeatureSetting(AiFeatureId id, AiFeatureSetting setting);
```

Add imports at the top:

```dart
import '../models/ai_feature_setting.dart';
```

- [ ] **Step 4: Implement in `SharedPrefsAppSettingsRepository`**

Add the key constant near the others:

```dart
  static const _aiFeaturesKey = 'aiFeatures';
```

Add the methods:

```dart
  @override
  Future<Map<AiFeatureId, AiFeatureSetting>> loadAiFeatureSettings() async {
    final raw = _readMap()[_aiFeaturesKey];
    final result = <AiFeatureId, AiFeatureSetting>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final id = AiFeatureId.tryParse(entry.key.toString());
        if (id == null || entry.value is! Map) continue;
        result[id] = AiFeatureSetting.fromJson(
          Map<String, Object?>.from(entry.value as Map),
        );
      }
    }
    return result;
  }

  @override
  Future<void> saveAiFeatureSetting(
    AiFeatureId id,
    AiFeatureSetting setting,
  ) async {
    final current = _readMap();
    final rawFeatures = current[_aiFeaturesKey];
    final features = rawFeatures is Map
        ? Map<String, Object?>.from(rawFeatures)
        : <String, Object?>{};
    features[id.key] = setting.toJson();
    current[_aiFeaturesKey] = features;
    await _writeMap(current);
  }
```

- [ ] **Step 5: Implement in `InMemoryAppSettingsRepository`**

Add a backing field and methods:

```dart
  final Map<AiFeatureId, AiFeatureSetting> _aiFeatures = {};

  @override
  Future<Map<AiFeatureId, AiFeatureSetting>> loadAiFeatureSettings() async =>
      Map<AiFeatureId, AiFeatureSetting>.from(_aiFeatures);

  @override
  Future<void> saveAiFeatureSetting(
    AiFeatureId id,
    AiFeatureSetting setting,
  ) async {
    _aiFeatures[id] = setting;
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd client && flutter test test/repositories/app_settings_repository_ai_features_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add client/lib/repositories/app_settings_repository.dart client/test/repositories/app_settings_repository_ai_features_test.dart
git commit -m "feat(ai-config): persist aiFeatures in AppSettingsRepository"
```

---

### Task 8: `AiFeatureSettingsCubit`

**Files:**
- Create: `client/lib/cubits/ai_feature_settings_cubit.dart`
- Test: `client/test/cubits/ai_feature_settings_cubit_test.dart`

The cubit loads all settings into memory, exposes a per-feature lookup with a sensible fallback, and persists edits.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/ai_feature_settings_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  test('load hydrates state from the repository', () async {
    final repo = InMemoryAppSettingsRepository();
    await repo.saveAiFeatureSetting(
      AiFeatureId.commitMessage,
      const AiFeatureSetting(cli: CliTool.claude, providerId: 'p', model: 'm'),
    );
    final cubit = AiFeatureSettingsCubit(repository: repo);

    await cubit.load();

    expect(cubit.state.settingFor(AiFeatureId.commitMessage)?.model, 'm');
  });

  test('settingFor returns null for unconfigured feature', () {
    final cubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    expect(cubit.state.settingFor(AiFeatureId.teamGenerate), isNull);
  });

  test('updateSetting persists and updates state', () async {
    final repo = InMemoryAppSettingsRepository();
    final cubit = AiFeatureSettingsCubit(repository: repo);

    await cubit.updateSetting(
      AiFeatureId.teamGenerate,
      const AiFeatureSetting(cli: CliTool.codex, providerId: 'p', model: 'm'),
    );

    expect(cubit.state.settingFor(AiFeatureId.teamGenerate)?.cli, CliTool.codex);
    expect(
      (await repo.loadAiFeatureSettings())[AiFeatureId.teamGenerate]?.cli,
      CliTool.codex,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/cubits/ai_feature_settings_cubit_test.dart`
Expected: FAIL — cubit not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/cubits/ai_feature_settings_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ai_feature_setting.dart';
import '../repositories/app_settings_repository.dart';

class AiFeatureSettingsState extends Equatable {
  const AiFeatureSettingsState({this.settings = const {}});

  final Map<AiFeatureId, AiFeatureSetting> settings;

  AiFeatureSetting? settingFor(AiFeatureId id) => settings[id];

  AiFeatureSettingsState copyWith({
    Map<AiFeatureId, AiFeatureSetting>? settings,
  }) => AiFeatureSettingsState(settings: settings ?? this.settings);

  @override
  List<Object?> get props => [settings];
}

class AiFeatureSettingsCubit extends Cubit<AiFeatureSettingsState> {
  AiFeatureSettingsCubit({required AppSettingsRepository repository})
    : _repository = repository,
      super(const AiFeatureSettingsState());

  final AppSettingsRepository _repository;

  Future<void> load() async {
    final loaded = await _repository.loadAiFeatureSettings();
    emit(state.copyWith(settings: loaded));
  }

  Future<void> updateSetting(AiFeatureId id, AiFeatureSetting setting) async {
    final next = Map<AiFeatureId, AiFeatureSetting>.from(state.settings);
    next[id] = setting;
    emit(state.copyWith(settings: next));
    await _repository.saveAiFeatureSetting(id, setting);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/cubits/ai_feature_settings_cubit_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/ai_feature_settings_cubit.dart client/test/cubits/ai_feature_settings_cubit_test.dart
git commit -m "feat(ai-config): add AiFeatureSettingsCubit"
```

---

### Task 9: Provide the cubit in the app shell

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`

No new test (wiring only); covered by the analyzer and existing boot tests.

- [ ] **Step 1: Create the cubit in `app_shell.dart`**

Find where `appSettings` is created (`final appSettings = SharedPrefsAppSettingsRepository(preferences);` around line 180) and add, right after it:

```dart
final aiFeatureSettingsCubit = AiFeatureSettingsCubit(repository: appSettings);
unawaited(aiFeatureSettingsCubit.load());
```

Add the import at the top of `app_shell.dart`:

```dart
import '../cubits/ai_feature_settings_cubit.dart';
```

Add a field to the shell class (near the other cubit fields, e.g. next to `final AppSettingsRepository appSettings;`):

```dart
final AiFeatureSettingsCubit aiFeatureSettingsCubit;
```

And pass it through the shell's constructor / return object the same way the other cubits (e.g. `configCubit`) are threaded. Follow the existing pattern in this file for how a created cubit becomes a `shell.xxxCubit` field.

- [ ] **Step 2: Provide it in `main.dart`**

In `main.dart`, in the `MultiBlocProvider` `providers:` list (around line 199), add:

```dart
                BlocProvider.value(value: shell.aiFeatureSettingsCubit),
```

- [ ] **Step 3: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart lib/main.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(ai-config): provide AiFeatureSettingsCubit app-wide"
```

---

### Task 10: AI Features config section UI + l10n

**Files:**
- Create: `client/lib/pages/config/ai_features_config_section.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/config/ai_features_config_section_test.dart`

- [ ] **Step 1: Add l10n strings**

In `client/lib/l10n/app_en.arb` add (keep the trailing comma style of the file):

```json
  "aiFeatures": "AI Features",
  "aiFeaturesPageSubtitle": "Choose which CLI provider, model, and effort each AI feature uses.",
  "aiFeatureCommitMessageTitle": "Commit message generation",
  "aiFeatureCommitMessageSubtitle": "Used by the ✨ button in the source control panel.",
  "aiFeatureTeamGenerateTitle": "Team configuration generation",
  "aiFeatureTeamGenerateSubtitle": "Used when generating a team from a description.",
  "aiFeatureCliLabel": "CLI",
  "aiFeatureModelLabel": "Model",
  "aiFeatureEffortLabel": "Effort",
```

In `client/lib/l10n/app_zh.arb` add:

```json
  "aiFeatures": "AI 功能",
  "aiFeaturesPageSubtitle": "为每个 AI 功能选择使用的 CLI provider、模型与 effort。",
  "aiFeatureCommitMessageTitle": "提交信息生成",
  "aiFeatureCommitMessageSubtitle": "由源代码管理面板里的 ✨ 按钮使用。",
  "aiFeatureTeamGenerateTitle": "团队配置生成",
  "aiFeatureTeamGenerateSubtitle": "从描述生成团队时使用。",
  "aiFeatureCliLabel": "CLI",
  "aiFeatureModelLabel": "模型",
  "aiFeatureEffortLabel": "Effort",
```

Run: `cd client && flutter pub get` (regenerates `app_localizations*.dart`).

- [ ] **Step 2: Write the failing widget test**

```dart
// client/test/pages/config/ai_features_config_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/ai_features_config_section.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

void main() {
  testWidgets('renders a card per AI feature', (tester) async {
    final cubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: AiFeaturesConfigWorkspace(showHeading: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Commit message generation'), findsOneWidget);
    expect(find.text('Team configuration generation'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && flutter test test/pages/config/ai_features_config_section_test.dart`
Expected: FAIL — `AiFeaturesConfigWorkspace` not defined.

- [ ] **Step 4: Write the implementation**

```dart
// client/lib/pages/config/ai_features_config_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/ai_feature_setting.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../widgets/app_provider/provider_model_picker_field.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

/// Global "AI Features" settings: per-feature CLI/provider/model/effort.
class AiFeaturesConfigWorkspace extends StatelessWidget {
  const AiFeaturesConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AiFeatureSettingsCubit, AiFeatureSettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHeading) ...[
                SettingsGroupHeader(title: l10n.aiFeatures),
                const SizedBox(height: 8),
              ],
              _FeatureCard(
                feature: AiFeatureId.commitMessage,
                title: l10n.aiFeatureCommitMessageTitle,
                subtitle: l10n.aiFeatureCommitMessageSubtitle,
                setting: state.settingFor(AiFeatureId.commitMessage),
              ),
              const SizedBox(height: 12),
              _FeatureCard(
                feature: AiFeatureId.teamGenerate,
                title: l10n.aiFeatureTeamGenerateTitle,
                subtitle: l10n.aiFeatureTeamGenerateSubtitle,
                setting: state.settingFor(AiFeatureId.teamGenerate),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.feature,
    required this.title,
    required this.subtitle,
    required this.setting,
  });

  final AiFeatureId feature;
  final String title;
  final String subtitle;
  final AiFeatureSetting? setting;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<AiFeatureSettingsCubit>();
    final registry = CliToolRegistryScope.of(context);
    final appProviders = context.watch<AppProviderCubit>().state;

    // Resolve the effective setting with a sensible default.
    final cli = setting?.cli ?? CliTool.claude;
    final providers = appProviders.providersFor(cli);
    final providerId = setting?.providerId.isNotEmpty == true
        ? setting!.providerId
        : (appProviders.selectedProviderIdByCli[cli] ??
              providers.firstOrNull?.id ??
              '');
    final provider = providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    final modelCap = registry.capability<ProviderModelCapability>(cli);
    final model = setting?.model.isNotEmpty == true
        ? setting!.model
        : (modelCap?.defaultModel(provider: provider, providerId: providerId) ??
              '');
    final effort = setting?.effort ?? '';

    final current = AiFeatureSetting(
      cli: cli,
      providerId: providerId,
      model: model,
      effort: effort,
    );

    void update(AiFeatureSetting next) =>
        cubit.updateSetting(feature, next);

    final cliItems = [
      CliTool.claude,
      CliTool.codex,
      CliTool.flashskyai,
      CliTool.cursor,
      CliTool.opencode,
    ];

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsLabeledRow(
            title: title,
            subtitle: subtitle,
            trailing: const SizedBox.shrink(),
            showDividerBelow: true,
          ),
          const SizedBox(height: 8),
          Text(l10n.aiFeatureCliLabel),
          AppDropdownField<CliTool>(
            items: cliItems,
            initialItem: cli,
            itemLabel: (c) => cliDisplayName(c),
            onChanged: (c) {
              if (c == null) return;
              update(current.copyWith(cli: c, providerId: '', model: '', effort: ''));
            },
          ),
          const SizedBox(height: 8),
          Text(l10n.aiFeatureModelLabel),
          ProviderModelPickerField(
            cli: cli,
            providerId: providerId,
            provider: provider,
            value: model,
            onChanged: (m) => update(current.copyWith(model: m)),
          ),
          const SizedBox(height: 8),
          Text(l10n.aiFeatureEffortLabel),
          CliEffortPickerField(
            cli: cli,
            value: effort,
            model: model,
            provider: provider,
            allowInherit: true,
            inheritLabel: '(default)',
            onChanged: (e) => update(current.copyWith(effort: e)),
          ),
        ],
      ),
    );
  }
}
```

> **Note on `cliDisplayName`:** confirm the exact helper name/import in `client/lib/services/cli/registry/cli_display_name.dart` (the new-team dialog imports it). If the API is a method on the registry instead, use that form. Likewise confirm `AppProviderCubit` state exposes `providersFor(cli)` and `selectedProviderIdByCli` (used by `home_workspace_new_team_dialog.dart`).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd client && flutter test test/pages/config/ai_features_config_section_test.dart`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/config/ai_features_config_section.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/config/ai_features_config_section_test.dart
git commit -m "feat(ai-config): add AI Features settings section"
```

---

### Task 11: Mount the AI Features section in the settings navigation

**Files:**
- Modify: `client/lib/cubits/config_cubit.dart`
- Modify: `client/lib/pages/config/config_workspace.dart`
- Modify: `client/lib/router/app_router.dart`

Wiring only; verified by analyzer + a manual nav check.

- [ ] **Step 1: Add the enum value + title**

In `config_cubit.dart`:

```dart
enum ConfigSection { layout, session, cli, aiFeatures, about, logs }
```

In the `title` getter's `switch (section)` add a case:

```dart
    ConfigSection.aiFeatures => 'AI Features',
```

- [ ] **Step 2: Render it in `config_workspace.dart`**

Add the import:

```dart
import 'ai_features_config_section.dart';
```

In the `body: switch (currentSection)` (around line 180) add:

```dart
        ConfigSection.aiFeatures => AiFeaturesConfigWorkspace(
          showHeading: showHeading,
        ),
```

Add a `SettingsDialogEntry` in `showWorkspaceSettingsDialog`'s `entries:` list (after the CLI entry, around line 59):

```dart
      SettingsDialogEntry(
        icon: Icons.auto_awesome_outlined,
        navLabel: l10n.aiFeatures,
        title: l10n.aiFeatures,
        subtitle: l10n.aiFeaturesPageSubtitle,
        body: const AiFeaturesConfigWorkspace(showHeading: false),
      ),
```

Add a nav-rail item in the `ConfigWorkspace` rail (mirror the `cli` entry around line 235), and a `WorkspaceHubEntry` in `ConfigSettingsHubPage` (mirror the cli hub entry around line 110):

```dart
        WorkspaceHubEntry(
          title: l10n.aiFeatures,
          icon: Icons.auto_awesome_outlined,
          onTap: throttledTap('config_hub_ai_features', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.aiFeatures);
            context.push('/config/ai-features');
          }),
        ),
```

> Match each surrounding call's exact constructor params (the `cli` entries are the template). Keep `AppKeys` usage consistent — add a key constant if the adjacent entries use one.

- [ ] **Step 3: Add the route in `app_router.dart`**

After the `/config/cli` route (around line 263), add:

```dart
            GoRoute(
              path: '/config/ai-features',
              builder: (context, state) =>
                  const ConfigWorkspace(section: ConfigSection.aiFeatures),
            ),
```

> Match the exact `GoRoute`/builder shape used by the adjacent `/config/cli` route (it may wrap in a shell or use `pageBuilder`).

- [ ] **Step 4: Verify it compiles and the section opens**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No errors.

Manual check (document result): launch the app, open Settings → AI Features, confirm both feature cards render and selections persist across reopen.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/config_cubit.dart client/lib/pages/config/config_workspace.dart client/lib/router/app_router.dart
git commit -m "feat(ai-config): mount AI Features section in settings navigation"
```

---

# Phase 3 — AI commit message generation

### Task 12: `GitService.stagedDiff()`

**Files:**
- Modify: `client/lib/services/git/git_service.dart`
- Test: `client/test/services/git/git_service_staged_diff_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/git/git_service_staged_diff_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_service.dart';

class _FakeRunner {
  _FakeRunner(this.stagedDiffOut);
  final String stagedDiffOut;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    if (!arguments.contains('-C')) return ProcessResult(0, 0, '/usr/bin/git\n', '');
    calls.add(arguments);
    return ProcessResult(0, 0, stagedDiffOut, '');
  }
}

void main() {
  test('stagedDiff runs git diff --cached --no-color', () async {
    final runner = _FakeRunner('diff body');
    final service = GitService(runner: runner.call);

    final out = await service.stagedDiff('/repo');

    expect(out, 'diff body');
    expect(runner.calls.single.sublist(2), ['diff', '--cached', '--no-color']);
  });

  test('stagedDiff truncates oversized output', () async {
    final big = 'x' * 20000;
    final service = GitService(runner: _FakeRunner(big).call);

    final out = await service.stagedDiff('/repo', maxChars: 100);

    expect(out.length, lessThan(big.length));
    expect(out, contains('diff truncated'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/git/git_service_staged_diff_test.dart`
Expected: FAIL — `stagedDiff` not defined.

- [ ] **Step 3: Add the method to `GitService`**

Add after the existing `diff(...)` method:

```dart
  /// Unified diff of staged changes (`git diff --cached`), capped at
  /// [maxChars] to bound prompt size.
  Future<String> stagedDiff(String dir, {int maxChars = 12000}) async {
    final out = await _run(dir, ['diff', '--cached', '--no-color']);
    if (out.length <= maxChars) return out;
    final dropped = out.length - maxChars;
    return '${out.substring(0, maxChars)}\n\n'
        '[diff truncated: $dropped more characters]';
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/git/git_service_staged_diff_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/git/git_service.dart client/test/services/git/git_service_staged_diff_test.dart
git commit -m "feat(git): add GitService.stagedDiff with size cap"
```

---

### Task 13: Commit message prompt + output cleaner

**Files:**
- Create: `client/lib/services/ai/commit_message_prompt.dart`
- Test: `client/test/services/ai/commit_message_prompt_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/ai/commit_message_prompt_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai/commit_message_prompt.dart';

void main() {
  test('prompt includes the diff and Conventional Commits guidance', () {
    final prompt = buildCommitMessagePrompt('diff --git a/x b/x');
    expect(prompt, contains('diff --git a/x b/x'));
    expect(prompt, contains('Conventional Commits'));
    expect(prompt.toLowerCase(), contains('english'));
  });

  test('cleaner strips code fences and surrounding whitespace', () {
    const raw = '```\nfeat: add thing\n\nbody line\n```\n';
    expect(cleanCommitMessageOutput(raw), 'feat: add thing\n\nbody line');
  });

  test('cleaner strips a leading language fence tag', () {
    const raw = '```text\nfix: bug\n```';
    expect(cleanCommitMessageOutput(raw), 'fix: bug');
  });

  test('cleaner passes through plain text unchanged', () {
    expect(cleanCommitMessageOutput('  feat: x  '), 'feat: x');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/ai/commit_message_prompt_test.dart`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/ai/commit_message_prompt.dart

/// Builds the prompt for generating a commit message from a staged diff.
String buildCommitMessagePrompt(String stagedDiff) {
  return '''
You are a tool that writes a single git commit message for the staged changes.

Rules:
- Use the Conventional Commits format: type(scope): subject
- Subject in the imperative mood, no trailing period, <= 72 characters.
- If helpful, add a blank line then a short body with "- " bullet points.
- Write the message in English.
- Output ONLY the commit message. No explanations, no code fences, no quotes.

Staged diff:
$stagedDiff
''';
}

/// Cleans model output into a bare commit message: trims whitespace and strips
/// a surrounding triple-backtick code fence (with optional language tag).
String cleanCommitMessageOutput(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline != -1) {
      text = text.substring(firstNewline + 1);
    } else {
      text = text.substring(3);
    }
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd != -1) {
      text = text.substring(0, fenceEnd);
    }
  }
  return text.trim();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/ai/commit_message_prompt_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ai/commit_message_prompt.dart client/test/services/ai/commit_message_prompt_test.dart
git commit -m "feat(commit-ai): add commit message prompt builder + output cleaner"
```

---

### Task 14: `GitCubit.generateCommitMessage()`

**Files:**
- Modify: `client/lib/cubits/git_cubit.dart`
- Test: `client/test/cubits/git_cubit_generate_commit_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/git_cubit_generate_commit_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/headless_ai_service.dart';
import 'package:teampilot/services/git/git_service.dart';

class _StubGitService extends GitService {
  _StubGitService(this._diff);
  final String _diff;
  @override
  Future<bool> get isAvailable async => true;
  @override
  Future<String> stagedDiff(String dir, {int maxChars = 12000}) async => _diff;
}

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

GitState _withStaged() => const GitState(
  repoRoot: '/repo',
  status: GitRepoStatus(
    isRepository: true,
    staged: [GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true)],
    unstaged: [],
  ),
);

void main() {
  test('fills commit message from the AI result', () async {
    final headless = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (name) async => name,
      tempDirFactory: () async =>
          Directory.systemTemp.createTempSync('gc_'),
      run: (exe, args, {environment, workingDirectory}) async =>
          ProcessResult(0, 0, '```\nfeat: generated\n```', ''),
    );
    final cubit = GitCubit(service: _StubGitService('diff'), headless: headless);
    cubit.emit(_withStaged());

    await cubit.generateCommitMessage(_setting);

    expect(cubit.state.commitMessage, 'feat: generated');
    expect(cubit.state.generatingCommitMessage, isFalse);
  });

  test('sets error on headless failure', () async {
    final headless = HeadlessAiService(
      resolveProvider: (_, __) async => null,
      resolveExecutable: (_) async => null, // not found → throws
      tempDirFactory: () async => Directory.systemTemp.createTempSync('gc_'),
      run: (exe, args, {environment, workingDirectory}) async =>
          ProcessResult(0, 0, '', ''),
    );
    final cubit = GitCubit(service: _StubGitService('diff'), headless: headless);
    cubit.emit(_withStaged());

    await cubit.generateCommitMessage(_setting);

    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.generatingCommitMessage, isFalse);
  });

  test('no-op when nothing staged', () async {
    final cubit = GitCubit(service: _StubGitService('diff'));
    cubit.emit(const GitState(repoRoot: '/repo'));
    await cubit.generateCommitMessage(_setting);
    expect(cubit.state.commitMessage, '');
  });
}
```

> `GitCubit.emit` is protected; expose a test seam OR set state via existing public methods. Simplest: add `@visibleForTesting` to allow `emit` in tests is not possible across libraries. Instead, in the test use `cubit.setCommitMessage`/`setRepoRoot` is insufficient for staged status. Therefore add a small `@visibleForTesting void debugSetState(GitState s) => emit(s);` to `GitCubit` (see Step 3) and call `cubit.debugSetState(_withStaged())` in the test instead of `cubit.emit(...)`.

Replace `cubit.emit(_withStaged());` with `cubit.debugSetState(_withStaged());` and `cubit.emit(const GitState(repoRoot: '/repo'));` with `cubit.debugSetState(const GitState(repoRoot: '/repo'));` in the test above.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/cubits/git_cubit_generate_commit_test.dart`
Expected: FAIL — `headless` param, `generateCommitMessage`, `generatingCommitMessage`, `debugSetState` not defined.

- [ ] **Step 3: Extend `GitState` and `GitCubit`**

In `GitState`, add the field, constructor default, `copyWith` param, and `props` entry:

```dart
    this.generatingCommitMessage = false,
```
```dart
  final bool generatingCommitMessage;
```
In `copyWith` signature add `bool? generatingCommitMessage,` and in the returned `GitState(...)`:
```dart
      generatingCommitMessage:
          generatingCommitMessage ?? this.generatingCommitMessage,
```
Add `generatingCommitMessage,` to the `props` list.

In `GitCubit`, update the constructor and add imports:

```dart
import '../models/ai_feature_setting.dart';
import '../services/ai/commit_message_prompt.dart';
import '../services/ai/headless_ai_service.dart';
```

```dart
  GitCubit({GitService? service, HeadlessAiService? headless})
    : _service =
          service ?? GitService.debugOverrideFactory?.call() ?? GitService(),
      _headless = headless ?? HeadlessAiService(),
      super(const GitState());

  final GitService _service;
  final HeadlessAiService _headless;

  @visibleForTesting
  void debugSetState(GitState next) => emit(next);
```

Add the import for `@visibleForTesting`:

```dart
import 'package:flutter/foundation.dart';
```

Add the method:

```dart
  /// Generates a commit message draft from the staged diff via [setting].
  /// Fills [GitState.commitMessage]; never commits.
  Future<void> generateCommitMessage(AiFeatureSetting setting) async {
    final dir = state.repoRoot;
    if (dir.isEmpty ||
        state.status.staged.isEmpty ||
        state.generatingCommitMessage) {
      return;
    }
    emit(state.copyWith(generatingCommitMessage: true, clearError: true));
    try {
      final diff = await _service.stagedDiff(dir);
      if (diff.trim().isEmpty) {
        emit(state.copyWith(generatingCommitMessage: false));
        return;
      }
      final result = await _headless.run(
        setting: setting,
        prompt: buildCommitMessagePrompt(diff),
        workingDirectory: dir,
      );
      emit(
        state.copyWith(
          commitMessage: cleanCommitMessageOutput(result.text),
          generatingCommitMessage: false,
        ),
      );
    } on GitException catch (e) {
      emit(state.copyWith(generatingCommitMessage: false, errorMessage: e.message));
    } on HeadlessAiException catch (e) {
      emit(state.copyWith(generatingCommitMessage: false, errorMessage: e.message));
    }
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/cubits/git_cubit_generate_commit_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/git_cubit.dart client/test/cubits/git_cubit_generate_commit_test.dart
git commit -m "feat(commit-ai): add GitCubit.generateCommitMessage"
```

---

### Task 15: Generate button in the source-control panel

**Files:**
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/widgets/git/git_source_control_panel_generate_test.dart`

- [ ] **Step 1: Add l10n strings**

`app_en.arb`:
```json
  "gitGenerateCommitMessage": "Generate commit message with AI",
  "gitGenerateCommitMessageNoProvider": "Configure an AI provider in Settings → AI Features first.",
```
`app_zh.arb`:
```json
  "gitGenerateCommitMessage": "用 AI 生成提交信息",
  "gitGenerateCommitMessageNoProvider": "请先在 设置 → AI 功能 中配置 AI provider。",
```
Run: `cd client && flutter pub get`.

- [ ] **Step 2: Write the failing widget test**

```dart
// client/test/widgets/git/git_source_control_panel_generate_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/git/git_source_control_panel.dart';

void main() {
  testWidgets('shows a generate-commit action button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: GitSourceControlPanel()),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('git-generate-commit-button')),
      findsOneWidget,
    );
  });
}
```

> If `GitSourceControlPanel` requires providers (e.g. `AiFeatureSettingsCubit`, `CliToolRegistryScope`) to build, wrap the test widget with them using the `setUpTestAppStorage()` harness and `GitService.debugOverrideFactory`. Mirror an existing `git_source_control_panel` widget test if one exists under `client/test/widgets/git/`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && flutter test test/widgets/git/git_source_control_panel_generate_test.dart`
Expected: FAIL — button key not found.

- [ ] **Step 4: Add the Generate button to `_CommitBox`**

Update `_CommitBox` to accept generation props and render the button. Change its constructor:

```dart
class _CommitBox extends StatelessWidget {
  const _CommitBox({
    required this.controller,
    required this.hint,
    required this.canCommit,
    required this.canGenerate,
    required this.generating,
    required this.onChanged,
    required this.onCommit,
    required this.onGenerate,
  });

  final TextEditingController controller;
  final String hint;
  final bool canCommit;
  final bool canGenerate;
  final bool generating;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onGenerate;
```

In its `build`, wrap the `TextField` with a `Stack`/row to add the action, e.g. replace the `TextField` widget with:

```dart
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enabled: !generating,
                decoration: InputDecoration(hintText: hint, isDense: true),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('git-generate-commit-button'),
              tooltip: l10n.gitGenerateCommitMessage,
              onPressed: (canGenerate && !generating) ? onGenerate : null,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
            ),
          ],
        ),
```

- [ ] **Step 5: Wire the panel's `_CommitBox` usage**

At the `_CommitBox(...)` call site (around line 182), pass the new props:

```dart
          _CommitBox(
            controller: _commitController,
            hint: l10n.gitCommitMessageHint(branch),
            canCommit: state.status.staged.isNotEmpty && !state.busy,
            canGenerate: state.status.staged.isNotEmpty && !state.busy,
            generating: state.generatingCommitMessage,
            onChanged: _cubit.setCommitMessage,
            onCommit: () async {
              final ok = await _cubit.commit();
              if (ok) _commitController.clear();
            },
            onGenerate: () async {
              final setting = context
                  .read<AiFeatureSettingsCubit>()
                  .state
                  .settingFor(AiFeatureId.commitMessage);
              if (setting == null || setting.providerId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.gitGenerateCommitMessageNoProvider),
                  ),
                );
                return;
              }
              await _cubit.generateCommitMessage(setting);
              if (!mounted) return;
              _commitController.text = _cubit.state.commitMessage;
            },
          ),
```

Add imports at the top of `git_source_control_panel.dart`:

```dart
import '../../cubits/ai_feature_settings_cubit.dart';
import '../../models/ai_feature_setting.dart';
```

> `context` and `mounted` must be available at the call site. The `_CommitBox` is built inside the panel `State`'s `build`/helper — ensure the `onGenerate` closure captures the `State`'s `context` and `mounted`. If the call site is in a separate builder method without `context`, thread `context` in or move the SnackBar logic into the panel `State`.

After generation, also keep the controller in sync when the cubit updates state externally: in the panel's `BlocListener`/`BlocConsumer` (the panel already has a listener for `errorMessage` around line 130), add a listener that updates `_commitController.text` when `state.commitMessage` changes and differs from the controller, so regeneration reflects in the field even without the manual assignment above. Concretely, extend the existing `listenWhen`/`listener`:

```dart
            listenWhen: (prev, next) =>
                (prev.errorMessage != next.errorMessage &&
                    next.errorMessage != null) ||
                prev.commitMessage != next.commitMessage,
            listener: (context, state) {
              if (state.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.gitError(state.errorMessage ?? ''))),
                );
              }
              if (_commitController.text != state.commitMessage) {
                _commitController.text = state.commitMessage;
              }
            },
```

(With this listener in place, the manual `_commitController.text = ...` in `onGenerate` is redundant — remove it to avoid double-setting.)

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd client && flutter test test/widgets/git/git_source_control_panel_generate_test.dart`
Expected: PASS (1 test).

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/git/git_source_control_panel.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/git/git_source_control_panel_generate_test.dart
git commit -m "feat(commit-ai): add AI generate button to source control panel"
```

---

# Phase 4 — AI team configuration generation

### Task 16: Team draft types + pure parser/clamp

**Files:**
- Create: `client/lib/services/ai/team_config_draft.dart`
- Test: `client/test/services/ai/team_config_draft_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/ai/team_config_draft_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';

void main() {
  const allowed = TeamDraftAllowedOptions(
    models: ['sonnet', 'opus'],
    efforts: ['low', 'high'],
    skillIds: ['code-review', 'testing'],
    defaultModel: 'sonnet',
  );

  test('parses members, clamping invalid model and effort', () {
    const json = '''
{
  "teamName": "Frontend",
  "mode": "native",
  "members": [
    {"name": "Lead Dev", "role": "lead", "model": "opus", "effort": "high"},
    {"name": "Bad One", "role": "dev", "model": "ghost-model", "effort": "ultra"}
  ],
  "skillIds": ["code-review", "unknown-skill"]
}
''';
    final draft = parseTeamConfigDraft(
      json,
      allowed: allowed,
      granularity: TeamGenGranularity.fullTeam,
      joinedAt: 100,
    );

    expect(draft.teamName, 'Frontend');
    expect(draft.mode, TeamMode.native);
    expect(draft.members, hasLength(2));
    expect(draft.members[0].model, 'opus');
    expect(draft.members[0].effort, 'high');
    // invalid model clamps to default, invalid effort clears
    expect(draft.members[1].model, 'sonnet');
    expect(draft.members[1].effort, '');
    // unknown skill dropped
    expect(draft.skillIds, ['code-review']);
  });

  test('roster-only ignores team name, mode, and skills', () {
    const json = '{"teamName":"X","members":[{"name":"Dev","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );
    expect(draft.teamName, isNull);
    expect(draft.mode, isNull);
    expect(draft.skillIds, isEmpty);
    expect(draft.members.single.name, 'Dev');
  });

  test('skips members without a name', () {
    const json = '{"members":[{"role":"dev"},{"name":"Ok","role":"dev"}]}';
    final draft = parseTeamConfigDraft(
      json,
      allowed: allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );
    expect(draft.members.single.name, 'Ok');
  });

  test('throws TeamDraftFormatException on non-JSON', () {
    expect(
      () => parseTeamConfigDraft(
        'not json',
        allowed: allowed,
        granularity: TeamGenGranularity.rosterOnly,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/ai/team_config_draft_test.dart`
Expected: FAIL — types/functions not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/ai/team_config_draft.dart
import 'dart:convert';

import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';

enum TeamGenGranularity { rosterOnly, fullTeam }

class TeamDraftFormatException implements Exception {
  TeamDraftFormatException(this.message);
  final String message;
  @override
  String toString() => 'TeamDraftFormatException: $message';
}

/// Legal values the AI must choose from; used to clamp parsed output.
class TeamDraftAllowedOptions {
  const TeamDraftAllowedOptions({
    required this.models,
    required this.efforts,
    required this.skillIds,
    required this.defaultModel,
  });

  final List<String> models;
  final List<String> efforts;
  final List<String> skillIds;
  final String defaultModel;
}

/// A validated, legal team draft produced from AI output.
class TeamConfigDraft {
  const TeamConfigDraft({
    required this.members,
    this.teamName,
    this.mode,
    this.skillIds = const [],
  });

  final List<TeamMemberConfig> members;
  final String? teamName;
  final TeamMode? mode;
  final List<String> skillIds;
}

/// Parses [rawJson] into a clamped [TeamConfigDraft]. Illegal models fall back
/// to [TeamDraftAllowedOptions.defaultModel]; illegal efforts are cleared;
/// unknown skill ids are dropped; nameless members are skipped.
TeamConfigDraft parseTeamConfigDraft(
  String rawJson, {
  required TeamDraftAllowedOptions allowed,
  required TeamGenGranularity granularity,
  required int joinedAt,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_stripFences(rawJson));
  } on FormatException catch (e) {
    throw TeamDraftFormatException('Output was not valid JSON: ${e.message}');
  }
  if (decoded is! Map) {
    throw TeamDraftFormatException('Output JSON was not an object.');
  }

  final full = granularity == TeamGenGranularity.fullTeam;

  final rawMembers = decoded['members'];
  final members = <TeamMemberConfig>[];
  if (rawMembers is List) {
    for (final raw in rawMembers) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final role = (raw['role'] as String? ?? '').trim();
      final rawModel = (raw['model'] as String? ?? '').trim();
      final model = allowed.models.contains(rawModel)
          ? rawModel
          : allowed.defaultModel;
      final rawEffort = (raw['effort'] as String? ?? '').trim();
      final effort = allowed.efforts.contains(rawEffort) ? rawEffort : '';
      members.add(
        TeamMemberConfig(
          id: TeamMemberNaming.slugMemberName(name),
          name: name,
          agentType: role,
          model: model,
          effort: effort,
          joinedAt: joinedAt,
        ),
      );
    }
  }

  if (!full) {
    return TeamConfigDraft(members: members);
  }

  final teamName = (decoded['teamName'] as String? ?? '').trim();
  final rawMode = (decoded['mode'] as String? ?? '').trim();
  final mode = switch (rawMode) {
    'mixed' => TeamMode.mixed,
    'native' => TeamMode.native,
    _ => null,
  };
  final rawSkills = decoded['skillIds'];
  final skillIds = <String>[];
  if (rawSkills is List) {
    for (final s in rawSkills) {
      final id = s.toString().trim();
      if (allowed.skillIds.contains(id)) skillIds.add(id);
    }
  }

  return TeamConfigDraft(
    members: members,
    teamName: teamName.isEmpty ? null : teamName,
    mode: mode,
    skillIds: skillIds,
  );
}

/// Removes a surrounding ```json ... ``` fence if present.
String _stripFences(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final nl = text.indexOf('\n');
    if (nl != -1) text = text.substring(nl + 1);
    final end = text.lastIndexOf('```');
    if (end != -1) text = text.substring(0, end);
  }
  return text.trim();
}
```

> Confirm `TeamMode` has `native` and `mixed` values and `TeamMemberNaming.slugMemberName` exists (both used by existing code — see `team_config.dart` and `home_workspace_new_team_dialog.dart`).

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/ai/team_config_draft_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ai/team_config_draft.dart client/test/services/ai/team_config_draft_test.dart
git commit -m "feat(team-ai): add team draft types + clamping parser"
```

---

### Task 17: Team config prompt builder

**Files:**
- Create: `client/lib/services/ai/team_config_prompt.dart`
- Test: `client/test/services/ai/team_config_prompt_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/ai/team_config_prompt_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_prompt.dart';

void main() {
  const allowed = TeamDraftAllowedOptions(
    models: ['sonnet', 'opus'],
    efforts: ['low', 'high'],
    skillIds: ['code-review'],
    defaultModel: 'sonnet',
  );

  test('roster prompt lists allowed models/efforts and the description', () {
    final p = buildTeamConfigPrompt(
      description: 'Flutter frontend team',
      allowed: allowed,
      granularity: TeamGenGranularity.rosterOnly,
    );
    expect(p, contains('Flutter frontend team'));
    expect(p, contains('sonnet'));
    expect(p, contains('high'));
    expect(p, contains('"members"'));
    // roster-only must not ask for team-level fields
    expect(p.contains('"skillIds"'), isFalse);
  });

  test('full prompt asks for team name, mode and skills', () {
    final p = buildTeamConfigPrompt(
      description: 'x',
      allowed: allowed,
      granularity: TeamGenGranularity.fullTeam,
    );
    expect(p, contains('"teamName"'));
    expect(p, contains('"mode"'));
    expect(p, contains('"skillIds"'));
    expect(p, contains('code-review'));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/ai/team_config_prompt_test.dart`
Expected: FAIL — function not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/ai/team_config_prompt.dart
import 'team_config_draft.dart';

/// Builds the prompt that constrains AI output to legal team options.
String buildTeamConfigPrompt({
  required String description,
  required TeamDraftAllowedOptions allowed,
  required TeamGenGranularity granularity,
}) {
  final full = granularity == TeamGenGranularity.fullTeam;
  final models = allowed.models.join(', ');
  final efforts = allowed.efforts.join(', ');

  final memberShape = '{"name": string, "role": string, '
      '"model": one of [$models], "effort": one of [$efforts]}';

  final schema = full
      ? '{\n'
            '  "teamName": string,\n'
            '  "mode": "native" or "mixed",\n'
            '  "members": [$memberShape, ...],\n'
            '  "skillIds": subset of [${allowed.skillIds.join(', ')}]\n'
            '}'
      : '{\n  "members": [$memberShape, ...]\n}';

  return '''
You design an AI agent team from a description. Output STRICT JSON only.

Description:
$description

Constraints:
- "model" MUST be one of: [$models].
- "effort" MUST be one of: [$efforts], or omit it.
${full ? '- "skillIds" MUST be a subset of: [${allowed.skillIds.join(', ')}].\n- "mode" MUST be "native" or "mixed".' : '- Only output members; do not include team-level fields.'}
- Give each member a short human name and a concise role.
- Output ONLY the JSON object below, no prose, no code fences.

JSON schema:
$schema
''';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/ai/team_config_prompt_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ai/team_config_prompt.dart client/test/services/ai/team_config_prompt_test.dart
git commit -m "feat(team-ai): add constrained team config prompt builder"
```

---

### Task 18: `TeamConfigGenerator` (orchestration + retry)

**Files:**
- Create: `client/lib/services/ai/team_config_generator.dart`
- Test: `client/test/services/ai/team_config_generator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/ai/team_config_generator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_generator.dart';

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

const _allowed = TeamDraftAllowedOptions(
  models: ['sonnet'],
  efforts: ['high'],
  skillIds: [],
  defaultModel: 'sonnet',
);

void main() {
  test('returns a parsed draft on first success', () async {
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async =>
          '{"members":[{"name":"Dev","role":"dev","model":"sonnet"}]}',
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );

    expect(draft.members.single.name, 'Dev');
  });

  test('retries once on bad JSON then succeeds', () async {
    var calls = 0;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        calls++;
        return calls == 1
            ? 'garbage'
            : '{"members":[{"name":"Dev","role":"dev","model":"sonnet"}]}';
      },
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );

    expect(calls, 2);
    expect(draft.members, hasLength(1));
  });

  test('throws after two bad JSON attempts', () async {
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async =>
          'still garbage',
    );

    expect(
      () => gen.generate(
        setting: _setting,
        description: 'team',
        allowed: _allowed,
        granularity: TeamGenGranularity.rosterOnly,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/ai/team_config_generator_test.dart`
Expected: FAIL — class not defined.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/ai/team_config_generator.dart
import '../../models/ai_feature_setting.dart';
import 'headless_ai_service.dart' show HeadlessAiService;
import 'team_config_draft.dart';
import 'team_config_prompt.dart';

/// Function seam over HeadlessAiService.run that returns just the text.
typedef TeamHeadlessRunner =
    Future<String> Function({
      required AiFeatureSetting setting,
      required String prompt,
      required bool expectJson,
    });

/// Generates a clamped [TeamConfigDraft] from a description via a headless call.
class TeamConfigGenerator {
  TeamConfigGenerator({TeamHeadlessRunner? runHeadless, HeadlessAiService? service})
    : _run =
          runHeadless ??
          (({required setting, required prompt, required expectJson}) async {
            final svc = service ?? HeadlessAiService();
            final r = await svc.run(
              setting: setting,
              prompt: prompt,
              expectJson: expectJson,
            );
            return r.text;
          });

  final TeamHeadlessRunner _run;

  Future<TeamConfigDraft> generate({
    required AiFeatureSetting setting,
    required String description,
    required TeamDraftAllowedOptions allowed,
    required TeamGenGranularity granularity,
    required int joinedAt,
  }) async {
    final basePrompt = buildTeamConfigPrompt(
      description: description,
      allowed: allowed,
      granularity: granularity,
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      final prompt = attempt == 0
          ? basePrompt
          : '$basePrompt\n\nIMPORTANT: Your previous output was not valid JSON. '
                'Reply with ONLY the JSON object, nothing else.';
      final text = await _run(
        setting: setting,
        prompt: prompt,
        expectJson: true,
      );
      try {
        return parseTeamConfigDraft(
          text,
          allowed: allowed,
          granularity: granularity,
          joinedAt: joinedAt,
        );
      } on TeamDraftFormatException {
        if (attempt == 1) rethrow;
      }
    }
    // Unreachable: loop either returns or rethrows on the final attempt.
    throw TeamDraftFormatException('Failed to generate a valid team draft.');
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/ai/team_config_generator_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ai/team_config_generator.dart client/test/services/ai/team_config_generator_test.dart
git commit -m "feat(team-ai): add TeamConfigGenerator with JSON retry"
```

---

### Task 19: Team-generate UI section in the new-team dialog

**Files:**
- Create: `client/lib/pages/home_workspace/home_workspace_team_generate_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/home_workspace/home_workspace_team_generate_section_test.dart`

- [ ] **Step 1: Add l10n strings**

`app_en.arb`:
```json
  "teamGenTitle": "Generate with AI",
  "teamGenDescriptionHint": "Describe the team you want (e.g. Flutter frontend with code review and tests)",
  "teamGenGranularityRoster": "Members only",
  "teamGenGranularityFull": "Full team draft",
  "teamGenButton": "Generate",
  "teamGenNoProvider": "Configure an AI provider in Settings → AI Features first.",
  "teamGenFailed": "Could not generate a team. Please edit manually.",
  "teamGenApplied": "Draft applied. Review and adjust before creating.",
```
`app_zh.arb`:
```json
  "teamGenTitle": "用 AI 生成",
  "teamGenDescriptionHint": "描述你想要的团队（例如：做 Flutter 前端、需要代码审查和测试）",
  "teamGenGranularityRoster": "仅成员",
  "teamGenGranularityFull": "完整团队草稿",
  "teamGenButton": "生成",
  "teamGenNoProvider": "请先在 设置 → AI 功能 中配置 AI provider。",
  "teamGenFailed": "无法生成团队，请手动编辑。",
  "teamGenApplied": "草稿已应用，创建前请检查调整。",
```
Run: `cd client && flutter pub get`.

- [ ] **Step 2: Write the failing widget test**

```dart
// client/test/pages/home_workspace/home_workspace_team_generate_section_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_team_generate_section.dart';

void main() {
  testWidgets('renders description field, granularity toggle, generate button',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeWorkspaceTeamGenerateSection(
            cli: CliTool.claude,
            providerId: 'p',
            generating: false,
            onGenerate: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('team-gen-description')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-gen-button')), findsOneWidget);
    expect(find.text('Members only'), findsOneWidget);
  });

  testWidgets('generate button reports description + granularity',
      (tester) async {
    String? gotDescription;
    TeamGenGranularity? gotGranularity;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeWorkspaceTeamGenerateSection(
            cli: CliTool.claude,
            providerId: 'p',
            generating: false,
            onGenerate: (desc, gran) {
              gotDescription = desc;
              gotGranularity = gran;
            },
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('team-gen-description')),
      'My team',
    );
    await tester.tap(find.byKey(const ValueKey('team-gen-button')));
    await tester.pump();

    expect(gotDescription, 'My team');
    expect(gotGranularity, TeamGenGranularity.rosterOnly);
  });
}
```

> `TeamGenGranularity` is imported from `team_config_draft.dart`; re-export it from the section file or import it directly in the test. The test imports it via the section file, so add `export 'package:teampilot/services/ai/team_config_draft.dart' show TeamGenGranularity;` to the section file (Step 3).

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && flutter test test/pages/home_workspace/home_workspace_team_generate_section_test.dart`
Expected: FAIL — widget not defined.

- [ ] **Step 4: Write the section widget**

```dart
// client/lib/pages/home_workspace/home_workspace_team_generate_section.dart
import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/ai/team_config_draft.dart';

export '../../services/ai/team_config_draft.dart' show TeamGenGranularity;

typedef TeamGenerateCallback =
    void Function(String description, TeamGenGranularity granularity);

/// "Generate with AI" block inside the new-team dialog: a description field, a
/// granularity toggle, and a generate button. Stateless about the result; the
/// dialog owns generation and draft application.
class HomeWorkspaceTeamGenerateSection extends StatefulWidget {
  const HomeWorkspaceTeamGenerateSection({
    required this.cli,
    required this.providerId,
    required this.generating,
    required this.onGenerate,
    super.key,
  });

  final CliTool cli;
  final String providerId;
  final bool generating;
  final TeamGenerateCallback onGenerate;

  @override
  State<HomeWorkspaceTeamGenerateSection> createState() =>
      _HomeWorkspaceTeamGenerateSectionState();
}

class _HomeWorkspaceTeamGenerateSectionState
    extends State<HomeWorkspaceTeamGenerateSection> {
  final _controller = TextEditingController();
  TeamGenGranularity _granularity = TeamGenGranularity.rosterOnly;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.teamGenTitle,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('team-gen-description'),
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          enabled: !widget.generating,
          decoration: InputDecoration(
            hintText: l10n.teamGenDescriptionHint,
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<TeamGenGranularity>(
          segments: [
            ButtonSegment(
              value: TeamGenGranularity.rosterOnly,
              label: Text(l10n.teamGenGranularityRoster),
            ),
            ButtonSegment(
              value: TeamGenGranularity.fullTeam,
              label: Text(l10n.teamGenGranularityFull),
            ),
          ],
          selected: {_granularity},
          onSelectionChanged: widget.generating
              ? null
              : (s) => setState(() => _granularity = s.first),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('team-gen-button'),
          onPressed: widget.generating
              ? null
              : () => widget.onGenerate(_controller.text.trim(), _granularity),
          icon: widget.generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_outlined, size: 16),
          label: Text(l10n.teamGenButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run the section test to verify it passes**

Run: `cd client && flutter test test/pages/home_workspace/home_workspace_team_generate_section_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Wire the section into the new-team dialog**

In `home_workspace_new_team_dialog.dart`:

1. Add imports:
```dart
import '../../cubits/ai_feature_settings_cubit.dart';
import '../../models/ai_feature_setting.dart';
import '../../services/ai/team_config_draft.dart';
import '../../services/ai/team_config_generator.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../services/ai/team_config_generator.dart';
import 'home_workspace_team_generate_section.dart';
```
   (`CliToolRegistryScope`, `AppProviderCubit`, `DefaultTeamRoster`, `TeamMemberConfig`, and `TeamMode` are already imported by this dialog file — see its existing import block.)

2. Add dialog state fields in `_HomeWorkspaceNewTeamDialogState`:
```dart
  bool _generating = false;
  TeamConfigDraft? _draft;
```

3. Render the section inside the dialog body (place it above the create button area):
```dart
            HomeWorkspaceTeamGenerateSection(
              cli: _cli,
              providerId: _providerId,
              generating: _generating,
              onGenerate: _onGenerate,
            ),
```

4. Add the generation handler in the state class:
```dart
  Future<void> _onGenerate(
    String description,
    TeamGenGranularity granularity,
  ) async {
    final l10n = context.l10n;
    if (description.isEmpty) return;
    final setting = context
        .read<AiFeatureSettingsCubit>()
        .state
        .settingFor(AiFeatureId.teamGenerate);
    if (setting == null || setting.providerId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.teamGenNoProvider)));
      return;
    }

    final allowed = _collectAllowedOptions();
    setState(() => _generating = true);
    try {
      final draft = await TeamConfigGenerator().generate(
        setting: setting,
        description: description,
        allowed: allowed,
        granularity: granularity,
        joinedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        if (draft.teamName != null && _nameController.text.trim().isEmpty) {
          _nameController.text = draft.teamName!;
        }
        if (draft.mode != null) _mode = draft.mode!;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.teamGenApplied)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.teamGenFailed)));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  TeamDraftAllowedOptions _collectAllowedOptions() {
    final registry = CliToolRegistryScope.of(context);
    final appProviders = context.read<AppProviderCubit>().state;
    final provider = appProviders
        .providersFor(_cli)
        .where((p) => p.id == _providerId)
        .firstOrNull;
    final modelCap = registry.capability<ProviderModelCapability>(_cli);
    final effortCap = registry.capability<CliEffortCapability>(_cli);
    final models = modelCap?.modelCandidates(
          provider: provider,
          providerId: _providerId,
          currentModel: '',
        ) ??
        const <String>[];
    final defaultModel =
        modelCap?.defaultModel(provider: provider, providerId: _providerId) ??
            (models.isNotEmpty ? models.first : '');
    final efforts = effortCap?.effortCandidates(
          model: defaultModel,
          provider: provider,
        ) ??
        const <String>[];
    return TeamDraftAllowedOptions(
      models: models,
      efforts: efforts,
      skillIds: const [], // v1: no skill suggestions; see Step 7
      defaultModel: defaultModel,
    );
  }
```

5. Apply the draft's members when creating the team. Find the dialog's "create" action (the button that pops with the result record) and change the returned `members` source: the dialog currently returns only `name/mode/cli/providerIdsByTool`. Extend the returned record to include `members` and have the caller use them. Concretely:

   - Change the `showDialog<...>` return record type in `showHomeWorkspaceNewTeamDialog` to add `List<TeamMemberConfig>? members`:
   ```dart
   ({
     String name,
     TeamMode mode,
     CliTool cli,
     Map<String, String> providerIdsByTool,
     List<TeamMemberConfig>? members,
   })
   ```
   - In the create button handler inside the dialog state, include `members: _draft?.members` in the popped record.
   - In `showHomeWorkspaceNewTeamDialog`, use the draft members when present, else fall back to the default roster:
   ```dart
     await teamCubit.addTeam(
       result.name,
       cli: result.cli,
       teamMode: result.mode,
       providerIdsByTool: result.providerIdsByTool,
       members: (result.members != null && result.members!.isNotEmpty)
           ? result.members
           : DefaultTeamRoster.localized(
               l10n,
               joinedAt: DateTime.now().millisecondsSinceEpoch,
             ),
     );
   ```

- [ ] **Step 7: Skill suggestions (full-team mode) — v1 decision**

For v1, pass `skillIds: const []` in `_collectAllowedOptions` (the parser drops any skills the AI returns). This keeps the dialog free of a skills dependency. Document this as a known limitation: full-team mode generates team name + mode + members, but not skill selections. (Follow-up: source installed skill ids from `SkillCubit` and pass them in.)

- [ ] **Step 8: Run the full suite to verify nothing regressed**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS (all suites, including the new dialog wiring compiles).

Manual check (document result): open New Team, type a description, click Generate (Members only), confirm members populate; switch to Full team draft, confirm name/mode also populate; create the team and verify members landed.

- [ ] **Step 9: Commit**

```bash
git add client/lib/pages/home_workspace/ client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/home_workspace/home_workspace_team_generate_section_test.dart
git commit -m "feat(team-ai): add AI team generation to new-team dialog"
```

---

# Final verification

- [ ] **Run the full gate**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```
Expected: analyze clean; all tests pass.

- [ ] **Manual golden-path checks (document outcomes in the PR):**
  1. Settings → AI Features: configure both features; reopen app; settings persisted.
  2. Source control panel: stage changes, click ✨, message draft appears and is editable; commit works.
  3. New Team: generate roster-only and full-team drafts; create a team from a draft.
  4. Error paths: no provider configured → friendly SnackBar (commit + team gen); CLI missing → error surfaced, UI stays usable.

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** Section 1 → Tasks 1–5; Section 2 → Tasks 6–11; Section 3 → Tasks 12–15; Section 4 → Tasks 16–19; cross-cutting (tests/l10n/layering) → embedded in every task + Final verification.
- **Type consistency:** `HeadlessRunContext`, `HeadlessInvocation`, `HeadlessConfigFile`, `HeadlessRunCapability` (Task 1) are used unchanged in Tasks 2–5 and the service (Task 3). `AiFeatureSetting`/`AiFeatureId` (Task 6) are used by Tasks 7–11, 14, 18, 19. `TeamDraftAllowedOptions`/`TeamConfigDraft`/`TeamGenGranularity`/`parseTeamConfigDraft` (Task 16) are used by Tasks 17–19. `HeadlessAiService.run` signature (Task 3) is called by Tasks 14 and 18.
- **Known v1 limitations (intentional):** commit messages are English-only; full-team generation does not suggest skills; CLI headless flags for flashskyai/cursor/opencode/codex are best-effort and must be confirmed with `--help` (Task 4 note).
- **Ordering caveat:** Task 3's test depends on Task 6's `AiFeatureSetting`. If executing strictly in order, implement Task 3's production file, then return to run its test after Task 6 — or do Task 6 before Task 3. Both are noted inline.
