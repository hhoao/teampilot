# CLI + ACP Readiness Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the settings AI CLI block with one readiness card per launchable CLI that shows detect / install / locate / version / upgrade for the CLI and, when needed, its ACP adapter — including boot-time adapter discovery.

**Architecture:** Optional `AcpSettingsCapability` declares adapter vs `cli acp` and whether the personal-ACP switch shows. Shared `locateAcpAdapter` (Windows PATH included) feeds `AcpAdapterDiscovery` at boot into in-memory cubit maps, same as CLI discovery. `CliVersionProbe` runs `--version` after locate and `npm view` only when Settings is visible. The card is registry-driven. Launch prefers an absolute discovered adapter path via `capabilityToPlan`.

**Tech Stack:** Flutter/Dart (`teampilot`), existing `CliInstallerService` / `InstallJobRegistry`, `TpCard` / `TpStatusBadge` / `TpPreferenceStack`.

**Spec:** `docs/superpowers/specs/2026-10-14-cli-acp-readiness-card-design.md`

## Global Constraints

- No `if (cli == …)` in `pages/config/` (card asks the registry + cubit keyed helpers).
- Connect never installs. Upgrade reuses `installCli` / `installClaudeAcpAdapter` / `installCodexAcpAdapter`.
- No `acpExecutablePaths` JSON. Adapter paths stay in cubit memory (`_locatedAcpAdapters`).
- No `npm view` at process start. Boot only locates + local `--version`.
- Cursor: Install when missing; never Upgrade (not npm).
- Android: skip boot discovery (existing). Card shows; ACP switch disabled; adapter actions hidden.
- Adapter install jobs stay local-only. No SSH adapter discovery.
- User copy → `client/lib/l10n/app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- Inner loop: one test file (`--plain-name` to narrow). Full suite only before claiming done, in the background.
- Do not grow `cli_config_section.dart` further — extract `CliReadinessCard`. Soft limits: pages ~500, services ~600.
- Do not change which sessions launch as ACP, permission chips, or onboarding CLI rows.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/registry/capabilities/acp_settings_capability.dart` | Optional capability: separate adapter, installer, personal switch |
| `client/lib/services/cli/{claude,codex,cursor,opencode}/*_tool.dart` | Register `AcpSettingsCapability` |
| `client/lib/services/cli/acp_adapter_locator.dart` | Shared PATH / `~/.local/bin` / node prefix / Windows locate |
| `client/lib/services/cli/{claude,codex}/capabilities/acp_adapter_installer.dart` | Thin wrappers around `locateAcpAdapter` |
| `client/lib/services/cli/acp_adapter_discovery.dart` | Boot/settings locate of separate adapters |
| `client/lib/services/cli/cli_version_probe.dart` | `--version` + `npm view` |
| `client/lib/services/cli/cli_local_discovery_bootstrap.dart` | One desktop boot callback: CLI + adapters + toolchain + versions |
| `client/lib/cubits/session_preferences_cubit.dart` | `_locatedAcpAdapters`, version cache, `personalAcpDefaultFor` |
| `client/lib/app/app_shell.dart` | Call bootstrap from existing non-Android `unawaited` |
| `client/lib/cubits/session/acp/acp_launch_wiring.dart` | Prefer absolute discovered adapter path |
| `client/lib/pages/config/cli_readiness_card.dart` | One CLI card |
| `client/lib/pages/config/cli_config_section.dart` | Iterate cards; delete SwitchListTile ACP rows |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Chip / upgrade / shared switch / Codex adapter copy |
| `docs/cli-architecture.md` | Document `AcpCapability` + `AcpSettingsCapability` |

**Why `AcpSettingsCapability` instead of new getters on `AcpCapability`:** Dart `implements` does not inherit default method bodies. Every ACP test fake would need four new getters. An optional capability keeps `AcpCapability` fakes unchanged and matches the spec table.

---

### Task 1: `AcpSettingsCapability`

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/acp_settings_capability.dart`
- Modify: `client/lib/services/cli/claude/claude_tool.dart` (add to `capabilities`)
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Test: `client/test/services/cli/cli_tool_registry_test.dart` (or new `client/test/services/cli/acp_settings_capability_test.dart`)

**Interfaces:**
- Consumes: `CliCapability`, existing `ClaudeAcpAdapterInstaller` / `CodexAcpAdapterInstaller`
- Produces:
  - `abstract interface class AcpSettingsCapability implements CliCapability`
  - `final class DefaultAcpSettingsCapability`
  - Fields: `bool usesSeparateAdapter`, `String? adapterExecutableName`, `NpmInstallerCapability? adapterInstaller`, `bool showsPersonalAcpSwitch`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/acp_settings_capability_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_settings_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('Claude and Codex declare a separate ACP adapter', () {
    final claude = registry.capability<AcpSettingsCapability>(CliTool.claude)!;
    expect(claude.usesSeparateAdapter, isTrue);
    expect(claude.adapterExecutableName, 'claude-agent-acp');
    expect(claude.adapterInstaller, isA<ClaudeAcpAdapterInstaller>());
    expect(claude.showsPersonalAcpSwitch, isTrue);

    final codex = registry.capability<AcpSettingsCapability>(CliTool.codex)!;
    expect(codex.usesSeparateAdapter, isTrue);
    expect(codex.adapterExecutableName, 'codex-acp');
    expect(codex.adapterInstaller, isA<CodexAcpAdapterInstaller>());
  });

  test('Cursor and OpenCode reuse the CLI binary and show the switch', () {
    for (final cli in [CliTool.cursor, CliTool.opencode]) {
      final settings = registry.capability<AcpSettingsCapability>(cli)!;
      expect(settings.usesSeparateAdapter, isFalse);
      expect(settings.adapterExecutableName, isNull);
      expect(settings.adapterInstaller, isNull);
      expect(settings.showsPersonalAcpSwitch, isTrue);
    }
  });

  test('Gemini has ACP but no personal-ACP settings capability', () {
    expect(
      registry.capability<AcpSettingsCapability>(CliTool.gemini),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_settings_capability_test.dart --plain-name 'Claude and Codex'`

Expected: FAIL (library not found / `AcpSettingsCapability` missing)

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/cli/registry/capabilities/acp_settings_capability.dart`:

```dart
import '../../installer/npm_installer_capability.dart';
import '../cli_capability.dart';

abstract interface class AcpSettingsCapability implements CliCapability {
  bool get usesSeparateAdapter;
  String? get adapterExecutableName;
  NpmInstallerCapability? get adapterInstaller;
  bool get showsPersonalAcpSwitch;
}

final class DefaultAcpSettingsCapability implements AcpSettingsCapability {
  const DefaultAcpSettingsCapability({
    this.usesSeparateAdapter = false,
    this.adapterExecutableName,
    this.adapterInstaller,
    this.showsPersonalAcpSwitch = true,
  });

  @override
  final bool usesSeparateAdapter;
  @override
  final String? adapterExecutableName;
  @override
  final NpmInstallerCapability? adapterInstaller;
  @override
  final bool showsPersonalAcpSwitch;
}
```

On `ClaudeCliTool`, import settings + installer, add a field:

```dart
this.acpSettings = const DefaultAcpSettingsCapability(
  usesSeparateAdapter: true,
  adapterExecutableName: ClaudeAcpCapability.adapterName,
  adapterInstaller: ClaudeAcpAdapterInstaller(),
),
```

Append `acpSettings` to `capabilities`. Same for Codex with `CodexAcpCapability.adapterName` and `CodexAcpAdapterInstaller()`. Cursor and OpenCode: `this.acpSettings = const DefaultAcpSettingsCapability(),` and append. Do **not** register it on Gemini or FlashskyAI.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_settings_capability_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/acp_settings_capability.dart \
  client/lib/services/cli/claude/claude_tool.dart \
  client/lib/services/cli/codex/codex_tool.dart \
  client/lib/services/cli/cursor/cursor_tool.dart \
  client/lib/services/cli/opencode/opencode_tool.dart \
  client/test/services/cli/acp_settings_capability_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): declare ACP settings capability per tool

Let the settings card ask the registry whether ACP is a separate adapter
and whether the personal switch shows, instead of switching on CliTool.
EOF
)"
```

---

### Task 2: Shared adapter locator with Windows PATH

**Files:**
- Create: `client/lib/services/cli/acp_adapter_locator.dart`
- Modify: `client/lib/services/cli/claude/capabilities/acp_adapter_installer.dart`
- Modify: `client/lib/services/cli/codex/capabilities/acp_adapter_installer.dart`
- Test: `client/test/services/cli/acp_adapter_locator_test.dart`
- Test: existing `claude_acp_adapter_installer_test.dart` / `codex_acp_adapter_installer_test.dart` must keep passing (wrappers)

**Interfaces:**
- Consumes: `AppPaths.teampilotAppDataDirName`
- Produces: `String locateAcpAdapter({required String name, Map<String, String>? environment, bool Function(String path)? fileExists, bool? isWindows})`
- Wrappers: `locateClaudeAcpAdapter` / `locateCodexAcpAdapter` call `locateAcpAdapter` with their name

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/acp_adapter_locator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/acp_adapter_locator.dart';

void main() {
  test('Windows PATH hit uses semicolon and PATHEXT', () {
    expect(
      locateAcpAdapter(
        name: 'claude-agent-acp',
        environment: const {
          'PATH': r'C:\Windows;C:\npm',
          'PATHEXT': '.EXE;.CMD',
        },
        fileExists: (p) => p == r'C:\npm\claude-agent-acp.EXE',
        isWindows: true,
      ),
      r'C:\npm\claude-agent-acp.EXE',
    );
  });

  test('Windows missing adapter returns the bare name', () {
    expect(
      locateAcpAdapter(
        name: 'codex-acp',
        environment: const {'PATH': r'C:\Windows', 'PATHEXT': '.EXE'},
        fileExists: (_) => false,
        isWindows: true,
      ),
      'codex-acp',
    );
  });
}
```

Add the same Windows “missing → bare name” case is enough; Unix cases already live on the wrappers.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_adapter_locator_test.dart --plain-name 'Windows PATH hit'`

Expected: FAIL (library not found)

- [ ] **Step 3: Write minimal implementation**

`locateAcpAdapter` must:

1. If Windows: split `PATH` or `Path` on `;`. For each dir, probe `dir\name` then `dir\name$ext` for each `PATHEXT` entry. No `~/.local/bin` / node prefix on Windows. Else return `name`.
2. If Unix: keep today’s order — `PATH` split on `:`, then `$HOME/.local/bin/<name>`, then `$HOME/.local/share/<AppPaths.teampilotAppDataDirName>/toolchain/node/current/bin/<name>`, else `name`.

Replace the bodies of `locateClaudeAcpAdapter` / `locateCodexAcpAdapter` with:

```dart
return locateAcpAdapter(
  name: 'claude-agent-acp', // or 'codex-acp'
  environment: environment,
  fileExists: fileExists,
  isWindows: isWindows,
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_adapter_locator_test.dart test/services/cli/claude/claude_acp_adapter_installer_test.dart test/services/cli/codex/codex_acp_adapter_installer_test.dart`

Expected: PASS (existing Unix locate tests still pass through wrappers)

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/acp_adapter_locator.dart \
  client/lib/services/cli/claude/capabilities/acp_adapter_installer.dart \
  client/lib/services/cli/codex/capabilities/acp_adapter_installer.dart \
  client/test/services/cli/acp_adapter_locator_test.dart
git commit -m "$(cat <<'EOF'
fix(acp): locate adapters on Windows PATH

Share one locator for Claude and Codex adapters and walk PATH/PATHEXT
instead of returning the bare name on Windows.
EOF
)"
```

---

### Task 3: `AcpAdapterDiscovery`

**Files:**
- Create: `client/lib/services/cli/acp_adapter_discovery.dart`
- Test: `client/test/services/cli/acp_adapter_discovery_test.dart`

**Interfaces:**
- Consumes: `CliToolRegistry`, `AcpSettingsCapability`, `locateAcpAdapter`
- Produces:
  - `class AcpAdapterDiscovery`
  - `Future<Map<CliTool, String>> locateLocal({Map<String, String>? environment, bool Function(String path)? fileExists, bool? isWindows})`
  - Returns only **absolute** paths (contains `/` or `\`). Bare names are omitted.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/acp_adapter_discovery.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('locateLocal returns only absolute Claude/Codex adapter hits', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateLocal(
      environment: const {'PATH': '/opt/bin', 'HOME': '/home/u'},
      fileExists: (p) => p == '/opt/bin/claude-agent-acp',
      isWindows: false,
    );
    expect(located[CliTool.claude], '/opt/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_adapter_discovery_test.dart --plain-name 'locateLocal returns only'`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Iterate `registry.launchable`. Skip unless `AcpSettingsCapability.usesSeparateAdapter` and `adapterExecutableName` is non-empty. Call `locateAcpAdapter`. Keep the entry only when the result contains `/` or `\`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_adapter_discovery_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/acp_adapter_discovery.dart \
  client/test/services/cli/acp_adapter_discovery_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): discover separate ACP adapters

Boot and settings can locate Claude/Codex adapter binaries without
installing and without treating Cursor/OpenCode as extra packages.
EOF
)"
```

---

### Task 4: `CliVersionProbe`

**Files:**
- Create: `client/lib/services/cli/cli_version_probe.dart`
- Test: `client/test/services/cli/cli_version_probe_test.dart`

**Interfaces:**
- Consumes: `ProcessRunner` from `cli_tool_locator.dart`
- Produces:
  - `class CliVersionProbe`
  - `Future<String?> installed(String absolutePath)` — run `[path, '--version']`, trim first non-empty line; null on non-zero / throw
  - `Future<String?> latestNpm(String npmPackage)` — run `npm view <pkg> version`; null on failure (no throw)

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_version_probe.dart';

void main() {
  test('installed takes the first line of --version stdout', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        expect(exe, '/usr/bin/claude');
        expect(args, ['--version']);
        return ProcessResult(0, 0, '2.1.4 (Claude Code)\nextra\n', '');
      },
    );
    expect(await probe.installed('/usr/bin/claude'), '2.1.4 (Claude Code)');
  });

  test('installed returns null when --version fails', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        return ProcessResult(0, 1, '', 'not found');
      },
    );
    expect(await probe.installed('/missing/claude'), isNull);
  });

  test('latestNpm returns null on failure without throwing', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        throw Exception('offline');
      },
    );
    expect(
      await probe.latestNpm('@anthropic-ai/claude-code'),
      isNull,
    );
  });

  test('latestNpm reads npm view stdout', () async {
    final probe = CliVersionProbe(
      runner: (exe, args, {environment, stdoutEncoding, stderrEncoding}) async {
        expect(exe, 'npm');
        expect(args, ['view', '@anthropic-ai/claude-code', 'version']);
        return ProcessResult(0, 0, '2.2.0\n', '');
      },
    );
    expect(await probe.latestNpm('@anthropic-ai/claude-code'), '2.2.0');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_version_probe_test.dart --plain-name 'installed takes the first line'`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Default `runner` is `cliToolDefaultProcessRun`. Wrap `runner` in try/catch; any error → `null`. For `installed`, skip if path is empty or has no `/` and no `\`. Parse stdout with `LineSplitter` (or `split('\n')`) and return the first trimmed non-empty line.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_version_probe_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_version_probe.dart \
  client/test/services/cli/cli_version_probe_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): probe installed and npm latest versions

Settings can show --version and an Upgrade affordance without throwing
when npm view is offline.
EOF
)"
```

---

### Task 5: Cubit adapter maps, versions, and personal-ACP accessors

**Files:**
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Test: `client/test/cubits/session_preferences_cubit_test.dart`

**Interfaces:**
- Consumes: existing `mergeLocatedExecutables` pattern
- Produces:
  - Constructor arg `Map<CliTool, String> locatedAcpAdapters = const {}`
  - `void mergeLocatedAcpAdapters(Map<CliTool, String> discovered)`
  - `String discoveredAcpAdapterPath(CliTool cli)`
  - `bool hasKnownAcpAdapter(CliTool cli)` — absolute path only
  - `void mergeBinaryVersion({required CliTool cli, required CliBinaryKind kind, String? installed, String? latest})`
  - `String? installedVersion(CliTool cli, CliBinaryKind kind)`
  - `String? latestVersion(CliTool cli, CliBinaryKind kind)`
  - `bool personalAcpDefaultFor(CliTool cli)`
  - `Future<void> setPersonalAcpDefaultFor(CliTool cli, bool value)`
  - `enum CliBinaryKind { cli, adapter }` in the cubit file (or `models/cli_binary_kind.dart` if you need it from UI without importing cubit internals — prefer a tiny `client/lib/models/cli_binary_kind.dart`)

Put `enum CliBinaryKind { cli, adapter }` in `client/lib/models/cli_binary_kind.dart`.

- [ ] **Step 1: Write the failing tests**

Add to `client/test/cubits/session_preferences_cubit_test.dart` (same `makeCubit` harness):

```dart
test('mergeLocatedAcpAdapters bumps revision and ignores bare names', () async {
  final cubit = await makeCubit();
  await cubit.load();
  cubit.mergeLocatedAcpAdapters(const {
    CliTool.claude: '/opt/claude-agent-acp',
    CliTool.codex: 'codex-acp',
  });
  expect(cubit.discoveredAcpAdapterPath(CliTool.claude), '/opt/claude-agent-acp');
  expect(cubit.hasKnownAcpAdapter(CliTool.claude), isTrue);
  expect(cubit.hasKnownAcpAdapter(CliTool.codex), isFalse);
  final rev = cubit.state.locatedExecutablesRevision;
  cubit.mergeLocatedAcpAdapters(const {
    CliTool.claude: '/opt/claude-agent-acp',
  });
  expect(cubit.state.locatedExecutablesRevision, rev);
});

test('mergeBinaryVersion stores installed and latest per kind', () async {
  final cubit = await makeCubit();
  await cubit.load();
  cubit.mergeBinaryVersion(
    cli: CliTool.claude,
    kind: CliBinaryKind.cli,
    installed: '2.1.4',
    latest: '2.2.0',
  );
  expect(cubit.installedVersion(CliTool.claude, CliBinaryKind.cli), '2.1.4');
  expect(cubit.latestVersion(CliTool.claude, CliBinaryKind.cli), '2.2.0');
});

test('setPersonalAcpDefaultFor writes the matching preference', () async {
  final cubit = await makeCubit();
  await cubit.load();
  await cubit.setPersonalAcpDefaultFor(CliTool.cursor, false);
  expect(cubit.personalAcpDefaultFor(CliTool.cursor), isFalse);
  expect(cubit.state.preferences.cursorPersonalAcpDefault, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session_preferences_cubit_test.dart --plain-name 'mergeLocatedAcpAdapters'`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Mirror `mergeLocatedExecutables`: skip empty; skip values that are not absolute (`contains('/') || contains(r'\')`); skip unchanged; bump `locatedExecutablesRevision`.

Version cache: two maps keyed `'${cli.value}:${kind.name}'` or `Map<(CliTool, CliBinaryKind), …>` — `(CliTool, CliBinaryKind)` records are fine. `mergeBinaryVersion` overwrites only the provided non-null fields (so boot can set `installed` and settings later set `latest` without clearing installed). Always bump revision when a stored string changes.

`personalAcpDefaultFor` / `setPersonalAcpDefaultFor`:

```dart
bool personalAcpDefaultFor(CliTool cli) => switch (cli) {
  CliTool.claude => state.preferences.claudePersonalAcpDefault,
  CliTool.cursor => state.preferences.cursorPersonalAcpDefault,
  CliTool.codex => state.preferences.codexPersonalAcpDefault,
  CliTool.opencode => state.preferences.opencodePersonalAcpDefault,
  _ => false,
};

Future<void> setPersonalAcpDefaultFor(CliTool cli, bool value) => switch (cli) {
  CliTool.claude => setClaudePersonalAcpDefault(value),
  CliTool.cursor => setCursorPersonalAcpDefault(value),
  CliTool.codex => setCodexPersonalAcpDefault(value),
  CliTool.opencode => setOpencodePersonalAcpDefault(value),
  _ => Future.value(),
};
```

Keep the existing named setters; the card uses the keyed helpers.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session_preferences_cubit_test.dart --plain-name 'mergeLocatedAcpAdapters'`

Then: `cd client && dart run tool/run_tests.dart test/cubits/session_preferences_cubit_test.dart --plain-name 'mergeBinaryVersion'`

Then: `cd client && dart run tool/run_tests.dart test/cubits/session_preferences_cubit_test.dart --plain-name 'setPersonalAcpDefaultFor'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/cli_binary_kind.dart \
  client/lib/cubits/session_preferences_cubit.dart \
  client/test/cubits/session_preferences_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(prefs): cache located ACP adapters and binary versions

Boot and settings share in-memory adapter paths and --version results
without a new preferences JSON key.
EOF
)"
```

---

### Task 6: Desktop boot discovery helper

**Files:**
- Create: `client/lib/services/cli/cli_local_discovery_bootstrap.dart`
- Modify: `client/lib/app/app_shell.dart` (the existing non-Android `unawaited` around lines 693–704)
- Test: `client/test/services/cli/cli_local_discovery_bootstrap_test.dart`

**Interfaces:**
- Consumes: `CliExecutableDiscovery`, `AcpAdapterDiscovery`, `ToolchainExecutableDiscovery`, `CliVersionProbe`, `SessionPreferencesCubit`
- Produces: `Future<void> runLocalCliDiscovery({required SessionPreferencesCubit cubit, CliExecutableDiscovery? cliDiscovery, AcpAdapterDiscovery? acpDiscovery, ToolchainExecutableDiscovery? toolchainDiscovery, CliVersionProbe? versionProbe})`

- [ ] **Step 1: Write the failing test**

```dart
test('runLocalCliDiscovery merges CLI, adapter, toolchain, then versions', () async {
  final cubit = /* same makeCubit as session_preferences_cubit_test */;
  await cubit.load();
  await runLocalCliDiscovery(
    cubit: cubit,
    cliDiscovery: _FixedCliDiscovery({CliTool.claude: '/bin/claude'}),
    acpDiscovery: _FixedAcpDiscovery({CliTool.claude: '/bin/claude-agent-acp'}),
    toolchainDiscovery: _FixedToolchainDiscovery({'git': '/usr/bin/git'}),
    versionProbe: _FixedVersionProbe({
      '/bin/claude': '2.1.4',
      '/bin/claude-agent-acp': '0.12.1',
    }),
  );
  expect(cubit.discoveredExecutablePath(CliTool.claude), '/bin/claude');
  expect(cubit.discoveredAcpAdapterPath(CliTool.claude), '/bin/claude-agent-acp');
  expect(cubit.installedVersion(CliTool.claude, CliBinaryKind.cli), '2.1.4');
  expect(
    cubit.installedVersion(CliTool.claude, CliBinaryKind.adapter),
    '0.12.1',
  );
});
```

Use constructor-injected fakes (do not subclass production discovery unless a small interface is cleaner). Simplest: give `runLocalCliDiscovery` the already-located maps via optional callbacks, **or** accept the discovery objects with `locateLocal` as the only method you call.

If the production classes are hard to fake, accept:

```dart
typedef LocateCli = Future<Map<CliTool, String>> Function();
typedef LocateAdapters = Future<Map<CliTool, String>> Function();
typedef LocateToolchains = Future<Map<String, String>> Function();
typedef ProbeInstalled = Future<String?> Function(String path);
```

Production `runLocalCliDiscovery` in `app_shell` passes the real locators. The test passes fakes. Prefer this if `CliExecutableDiscovery` is awkward to subclass.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_local_discovery_bootstrap_test.dart --plain-name 'runLocalCliDiscovery merges'`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
Future<void> runLocalCliDiscovery({
  required SessionPreferencesCubit cubit,
  required Future<Map<CliTool, String>> Function() locateCli,
  required Future<Map<CliTool, String>> Function() locateAdapters,
  required Future<Map<String, String>> Function() locateToolchains,
  required Future<String?> Function(String path) probeInstalled,
}) async {
  final cliPaths = await locateCli();
  final acpPaths = await locateAdapters();
  final toolchainPaths = await locateToolchains();
  cubit.mergeLocatedExecutables(cliPaths);
  cubit.mergeLocatedAcpAdapters(acpPaths);
  cubit.mergeLocatedToolchains(toolchainPaths);

  Future<void> probe(CliTool cli, CliBinaryKind kind, String path) async {
    final version = await probeInstalled(path);
    cubit.mergeBinaryVersion(cli: cli, kind: kind, installed: version);
  }

  for (final e in cliPaths.entries) {
    await probe(e.key, CliBinaryKind.cli, e.value);
  }
  for (final e in acpPaths.entries) {
    await probe(e.key, CliBinaryKind.adapter, e.value);
  }
}
```

In `app_shell.dart`, replace the body of the existing `unawaited(() async { ... }())` with a call to this helper. Do **not** add a second boot task. Keep `if (!Platform.isAndroid)`. Wire:

```dart
await runLocalCliDiscovery(
  cubit: sessionPreferencesCubit,
  locateCli: () => cliExecutableDiscovery.locateLocal(),
  locateAdapters: () => AcpAdapterDiscovery(registry: cliToolRegistry).locateLocal(),
  locateToolchains: () => ToolchainExecutableDiscovery().locateLocal(),
  probeInstalled: CliVersionProbe().installed,
);
```

Keep the existing `[boot] CLI/toolchain discovery complete` log; extend counts to include adapters.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_local_discovery_bootstrap_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_local_discovery_bootstrap.dart \
  client/lib/app/app_shell.dart \
  client/test/services/cli/cli_local_discovery_bootstrap_test.dart
git commit -m "$(cat <<'EOF'
feat(boot): locate ACP adapters with CLI discovery

Desktop startup fills adapter paths and --version so Settings does not
require a manual Locate.
EOF
)"
```

---

### Task 7: Launch prefers discovered adapter path

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_launch_wiring.dart`
- Test: `client/test/cubits/session/acp/acp_launch_wiring_test.dart`

**Interfaces:**
- Consumes: `AcpLaunchPlan.agentExecutable`
- Produces: `capabilityToPlan(capability, {String? Function()? discoveredAdapterPath})` — if the callback returns an absolute path, use it; else `capability.agentExecutable`

- [ ] **Step 1: Write the failing test**

Add to `acp_launch_wiring_test.dart` using the existing `_FixedAuthCapability` (its `agentExecutable` returns `cliExecutable`):

```dart
test('capabilityToPlan prefers an absolute discovered adapter path', () {
  final plan = capabilityToPlan(
    _FixedAuthCapability(null),
    discoveredAdapterPath: () => '/opt/claude-agent-acp',
  )!;
  expect(plan.agentExecutable('/usr/bin/claude'), '/opt/claude-agent-acp');
});

test('capabilityToPlan ignores a bare discovered name', () {
  final plan = capabilityToPlan(
    _FixedAuthCapability(null),
    discoveredAdapterPath: () => 'claude-agent-acp',
  )!;
  expect(plan.agentExecutable('/usr/bin/claude'), '/usr/bin/claude');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart --plain-name 'capabilityToPlan prefers'`

Expected: FAIL (named param missing)

- [ ] **Step 3: Write minimal implementation**

```dart
bool _looksAbsolute(String value) =>
    value.contains('/') || value.contains(r'\');

AcpLaunchPlan? capabilityToPlan(
  AcpCapability? capability, {
  String? Function()? discoveredAdapterPath,
}) {
  if (capability == null) return null;
  return AcpLaunchPlan(
    // ...existing fields...
    agentExecutable: (cliExecutable) {
      final discovered = discoveredAdapterPath?.call()?.trim() ?? '';
      if (_looksAbsolute(discovered)) return discovered;
      return capability.agentExecutable(cliExecutable);
    },
  );
}
```

Update `acpLaunchPlanResolver` to accept an optional `String? Function(CliTool tool)? discoveredAdapterPath` and pass `() => discoveredAdapterPath?.call(tool)` into `capabilityToPlan`. Find production call sites of `acpLaunchPlanResolver(` / `capabilityToPlan(` and pass `() => sessionPreferencesCubit.discoveredAcpAdapterPath(tool)` where a cubit is in scope. If a call site has no cubit, leave the callback omitted (spawn still uses `locateAdapter`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_launch_wiring.dart \
  client/test/cubits/session/acp/acp_launch_wiring_test.dart
# also any production call sites wired to the cubit
git commit -m "$(cat <<'EOF'
feat(acp): spawn the boot-located adapter path

Prefer an absolute discovered adapter over a bare PATH name so Settings
Locate/Install matches what launch runs.
EOF
)"
```

---

### Task 8: l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

Do **not** hand-edit `app_localizations*.dart`. Flutter gen-l10n runs in tests.

**Produces keys:**

| Key | EN | ZH |
|-----|----|----|
| `cliReadinessReady` | Ready | 就绪 |
| `cliReadinessUpdateAvailable` | Update available | 有更新 |
| `cliReadinessNeedsSetup` | Needs setup | 需要安装 |
| `cliReadinessRowCli` | CLI | CLI |
| `cliReadinessRowAcp` | ACP | ACP |
| `cliReadinessUsesCli` | uses CLI · acp | 使用 CLI · acp |
| `cliReadinessAdapterMissing` | adapter not found | 未找到适配器 |
| `cliReadinessVersionUnknown` | — | — |
| `cliUpgradeButton` | Upgrade | 升级 |
| `cliInstallUpgrading` | Upgrading… | 正在升级… |
| `personalAcpSwitchLabel` | New personal / mixed sessions use ACP | 新建个人和混合会话使用 ACP |
| `personalAcpSwitchCaption` | Native teams and remote members still use the terminal | 原生团队和远程成员仍用终端 |
| `codexAcpAdapterInstallButton` | Install ACP adapter | 安装 ACP 适配器 |

Keep existing `claudeAcpAdapterInstallButton`. Codex must stop using Claude’s key (widget tests in Task 9 assert this).

- [ ] **Step 1: Add the keys to both ARB files** (no unit test required; next task’s widget tests fail if gen-l10n missing)

Place them near the existing `cliInstallButton` / `claudePersonalAcpDefaultLabel` entries.

- [ ] **Step 2: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "$(cat <<'EOF'
feat(l10n): readiness card copy for CLI and ACP

Add chip, upgrade, and shared personal-ACP switch strings, including a
Codex-specific adapter install label.
EOF
)"
```

---

### Task 9: `CliReadinessCard` + settings rewrite

**Files:**
- Create: `client/lib/pages/config/cli_readiness_card.dart`
- Modify: `client/lib/pages/config/cli_config_section.dart` — iterate cards; delete `PersonalAcpSettingsRow`, `*PersonalAcpSettingsRow`, `_ClaudeAcpAdapterInstallButton`, `_CodexAcpAdapterInstallButton`, `_buildCliPathRow` usage for AI CLIs
- Modify: `client/lib/utils/ui/app_keys.dart` — add locate/upgrade keys if missing:
  - `claudeAcpAdapterLocateButton`, `codexAcpAdapterLocateButton`
  - `claudeCliUpgradeButton`, `codexCliUpgradeButton`, `opencodeCliUpgradeButton`, `geminiCliUpgradeButton`
  - `claudeAcpAdapterUpgradeButton`, `codexAcpAdapterUpgradeButton`
- Test: rewrite `client/test/pages/config/cli_config_section_test.dart`

**Interfaces:**
- Consumes: `SessionPreferencesCubit`, `AcpSettingsCapability`, `CliExecutableCapability`, `InstallJobEnqueue`, `CliVersionProbe`, `AcpAdapterDiscovery`, `CliExecutableDiscovery`
- Produces: `class CliReadinessCard`

Chip rules (pure helper in the same file, testable without pumping the full page if you extract `CliReadinessChipKind`):

```dart
enum CliReadinessChipKind { ready, updateAvailable, needsSetup }

CliReadinessChipKind readinessChip({
  required bool cliKnown,
  required bool needsAdapter,
  required bool adapterKnown,
  required bool cliUpdate,
  required bool adapterUpdate,
}) {
  if (!cliKnown || (needsAdapter && !adapterKnown)) {
    return CliReadinessChipKind.needsSetup;
  }
  if (cliUpdate || adapterUpdate) return CliReadinessChipKind.updateAvailable;
  return CliReadinessChipKind.ready;
}

bool isNpmUpdate({required String? installed, required String? latest}) {
  if (installed == null || latest == null) return false;
  return installed.trim() != latest.trim();
}
```

`isNpmUpdate` is string inequality (not semver). Good enough: `npm view` returns a single version token.

Card layout (A1):

- Header: `CliBrandIcon` + `registry.capability<CliExecutableCapability>(cli)!.label(l10n)` + `TpStatusBadge` (`success` Ready, `warning` otherwise).
- Grid rows: CLI path (`cubit.resolveExecutable` / discovered) + `installedVersion` or `cliReadinessVersionUnknown`; ACP row from settings.
- CLI actions: Install if `!cubit.hasKnownCliExecutable(cli)` and `supportsInstaller`; Upgrade if CLI is `NpmInstallerCapability` and `isNpmUpdate`; Browse always (disabled on remote work plane, same as today); Reset if user path set else Locate if unknown.
- ACP separate: path text or `cliReadinessAdapterMissing`; Install / Locate / Upgrade with existing adapter job keys; **no Browse**.
- ACP not separate (`AcpCapability` present, settings null or `!usesSeparateAdapter`): `cliReadinessUsesCli`; no extra actions; version `cliReadinessVersionUnknown`.
- Switch: only `settings?.showsPersonalAcpSwitch == true`. Android: `onChanged: null`, caption `claudePersonalAcpAndroidDisabled` (existing). Desktop: `personalAcpSwitchLabel` + `personalAcpSwitchCaption`.
- Gemini: `AcpCapability` present, settings null → ACP row “uses CLI”, no switch.

When the card becomes visible (`initState` / first frame), if desktop: `unawaited` `npm view` for npm-backed CLI package and adapter package; `mergeBinaryVersion(..., latest: ...)`. Do not block first paint.

CLI path display: `Text` (monospace via `appMonoTextStyle` if that helper exists; otherwise `TpTextStyles` only — do **not** invent a raw `TextStyle`). Keep existing field keys on the path `Text` so tests can `find.byKey(AppKeys.claudeCliExecutablePathField)`.

Reuse install/locate/browse behavior from `CliExecutablePathSettingsRow` (copy the methods into the card, then delete the row’s use from the AI CLI group). Toolchain still uses `ToolchainPathSettingsRow`. After the rewrite, `CliExecutablePathSettingsRow` may be unused — if nothing imports it (onboarding does **not**), delete the file and its tests; if onboarding or elsewhere still imports it, leave the file.

Upgrade buttons call the **same** enqueue as Install, with `title: l10n.cliInstallUpgrading`.

After Install/Locate/Upgrade succeeds: `mergeLocatedExecutables` / `mergeLocatedAcpAdapters` with `result.executablePath` if absolute; re-run `CliVersionProbe.installed`.

- [ ] **Step 1: Write failing widget tests** (replace ACP/path assertions in `cli_config_section_test.dart`)

Must cover:

1. Ready: merge CLI + adapter paths + versions; no Install, no Upgrade; chip Ready.
2. Needs setup: adapter missing → `find.byKey(AppKeys.claudeAcpAdapterInstallButton)` and locate key; switch still present.
3. Update available: `mergeBinaryVersion` installed `0.42.0` latest `0.44.1` → Codex CLI Upgrade key.
4. Cursor / OpenCode: `find.textContaining` uses-CLI copy; no adapter install key.
5. Gemini: no `*PersonalAcpSwitch` (gemini has none today).
6. Cursor found: no Upgrade key.
7. Android override on the card/section: switch disabled, no adapter install.
8. Codex adapter install label is `l10n.codexAcpAdapterInstallButton`, not Claude’s string if they ever diverge — at minimum `find.byKey(AppKeys.codexAcpAdapterInstallButton)` and `find.text(l10n.codexAcpAdapterInstallButton)`.
9. Existing CLI Install still appears when CLI unknown (keep a current install test, updated to the card).

Keep `setUpTestAppStorage` / `InstallJobRegistry` fakes from the current file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name 'Ready'`

Expected: FAIL

- [ ] **Step 3: Implement the card and rewrite `_CliControls`**

```dart
TpCard.outlined(
  child: Column(
    children: [
      for (final def in CliToolRegistry.builtIn().launchable)
        if (registry.capability<CliExecutableCapability>(def.id) != null)
          CliReadinessCard(cli: def.id, cubit: cubit),
    ],
  ),
);
```

No `if (cli == CliTool.claude)` in this file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`

Expected: PASS

Also: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart` after `flutter analyze` on touched files if the inner loop is noisy.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/cli_readiness_card.dart \
  client/lib/pages/config/cli_config_section.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/pages/config/cli_config_section_test.dart
# delete unused path-row file only if unused
git commit -m "$(cat <<'EOF'
feat(settings): unify CLI and ACP into readiness cards

Show detect, version, and upgrade per binary, with Install only when
missing, and drop the hanging ACP adapter button.
EOF
)"
```

---

### Task 10: `cli-architecture.md`

**Files:**
- Modify: `docs/cli-architecture.md`

- [ ] **Step 1: Add `AcpCapability` and `AcpSettingsCapability` to the optional table (~line 253) and the inventory table (~line 490)**

Optional table rows:

```
| `AcpCapability` | ACP spawn argv / env / translator. Optional. Claude/Codex use a separate adapter binary; Cursor/OpenCode/Gemini pass `cli acp` / `--acp`. |
| `AcpSettingsCapability` | Settings extras: `usesSeparateAdapter`, adapter installer, `showsPersonalAcpSwitch`. Gemini omits this (no personal switch). |
```

Inventory: `AcpCapability` and `AcpSettingsCapability`, type 基础设施, 必需 `-`.

Two-sentence note under optional capabilities: boot discovery locates separate adapters via `AcpAdapterDiscovery`; Settings must not `if (cli == …)`.

- [ ] **Step 2: Commit**

```bash
git add docs/cli-architecture.md
git commit -m "$(cat <<'EOF'
docs(cli): document AcpCapability and adapter settings

Record separate-adapter vs cli-acp and that settings reads the registry.
EOF
)"
```

---

## Self-review (spec coverage)

| Spec item | Task |
|-----------|------|
| A1 card, chips, sibling rows, version, Upgrade only when newer | 8, 9 |
| Boot-time CLI + adapter locate + `--version`, no npm at boot | 3, 4, 5, 6 |
| Claude/Codex separate adapter detect/install/locate/version/upgrade | 1, 2, 3, 9 |
| ACP path shown, no text field, Browse on CLI only | 9 |
| Cursor/OpenCode “uses CLI · acp” | 1, 9 |
| Gemini no personal switch | 1, 9 |
| Cursor no Upgrade | 9 |
| Android switch disabled, no adapter actions, no boot discovery | 6, 9 |
| Toolchain unchanged | 9 (left in place) |
| Connect never installs; Upgrade = existing jobs | 9 |
| Registry-driven page | 1, 9 |
| Windows adapter PATH | 2 |
| Spawn prefers absolute discovered path | 7 |
| In-memory maps, no `acpExecutablePaths` JSON | 5 |
| Codex l10n not Claude’s key | 8, 9 |
| `cli-architecture.md` | 10 |
| Tests listed in spec | 2–7, 9 |

No TBD / “similar to Task N” leftovers. `runLocalCliDiscovery` typedefs in Task 6 match `SessionPreferencesCubit.merge*` from Task 5. `capabilityToPlan(discoveredAdapterPath:)` matches cubit `discoveredAcpAdapterPath`.
