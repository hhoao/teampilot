# Extension System — Phase 3a (Management UI core + rtk cutover) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user one control surface to install/enable/disable extensions (rtk + codegraph) inside Settings, and make `ExtensionRepository` the single source of truth for enablement (rtk migrated off its old toggle).

**Architecture:** An `ExtensionCubit` (mirroring `McpCubit`) aggregates, per built-in manifest, its install/probe status + global-enabled flag from `ExtensionRepository`, and exposes install/uninstall/enable actions (install via `ExtensionAcquisitionEngine`). The existing `_RtkSettingsSection` in `config_workspace.dart` is replaced by a generic `_ExtensionsSection` driven by that cubit. rtk's enablement is read from `ExtensionRepository.globalEnabled` (the `loadRtkEnabled` callback wired in `app_shell` is repointed at the repo, with a one-time migration of the old `AppSettingsRepository` flag). The `script`-kind install path is hardened (Phase-2 review minor).

**Tech Stack:** Dart / Flutter, `flutter_bloc`, `equatable`, `package:test` + `flutter_test`, the Phase-1/2 extension engine (`ExtensionManifest`/`ExtensionDetector`/`ExtensionRepository`/`ExtensionAcquisitionEngine`/`builtInExtensionManifests`), the settings widgets `SettingsGroupHeader`/`SettingsLabeledRow`/`SettingsSurfaceCard`.

**Builds on Phase 1 + 2 (landed):** `ExtensionManifest`, `ExtensionDetector`, `ExtensionProbe`, `ExtensionProvisioner`, `ExtensionState`, `ExtensionRepository`, `ExtensionAcquisitionEngine`, `builtInExtensionManifests()` (rtk + codegraph).

**Phase boundary — NOT in 3a (→ Phase 3b):**
- Per-team override UI (a `_TeamExtensionsSection` in `team_config_page.dart` mirroring `_TeamMcpSection`, with a `TeamConfigSection.extensions` route/nav).
- Per-team override of the **rtk settings-hook** effect (`config_profile_service` reads repo *global* enablement in 3a; per-team rtk needs threading teamId through `ConfigProfileDelegate`, deferred).

**Scope note:** codegraph already works once enabled (Phase 2 wired `team_cubit`). 3a adds the UI to install + enable it, and unifies rtk onto the same store. Per-team override for codegraph's MCP path already resolves through `ExtensionRepository.effectiveEnabled` (Phase 2) — 3b only adds its *UI*.

---

## File Structure

**New files:**

| File | Responsibility |
|------|----------------|
| `client/lib/cubits/extension_cubit.dart` | `ExtensionUiState` + `ExtensionRow` + `ExtensionCubit`: aggregate status, install/uninstall/enable actions. |
| `client/lib/services/extension/extension_state_migration.dart` | One-time copy of the legacy `rtkEnabled` flag into `ExtensionRepository.globalEnabled`. |
| `client/test/cubits/extension_cubit_test.dart` | Cubit behaviour (status derivation, enable, install). |
| `client/test/services/extension/extension_state_migration_test.dart` | Migration idempotency. |

**Modified files:**

| File | Change |
|------|--------|
| `client/lib/services/extension/extension_acquisition_engine.dart` | Harden `script` kind (https-only, reject shell metacharacters); add a default local `Process.run` runner so `ExtensionAcquisitionEngine()` works in production. |
| `client/lib/app/app_shell.dart` | Build `ExtensionRepository` + `ExtensionCubit`; provide them; run the migration; repoint `loadRtkEnabled` at the repo. |
| `client/lib/pages/config_workspace.dart` | Replace `_RtkSettingsSection` with `_ExtensionsSection` (BlocBuilder over `ExtensionCubit`). |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Extension settings strings. |

**Test updated:** `client/test/services/extension/extension_acquisition_engine_test.dart` (script-hardening cases).

> All commands run from `client/` unless noted.

---

## Task 1: Harden the `script` install kind + default local runner

**Files:**
- Modify: `client/lib/services/extension/extension_acquisition_engine.dart`
- Test: `client/test/services/extension/extension_acquisition_engine_test.dart` (extend)

- [ ] **Step 1: Add the failing tests (append inside the existing `main()`)**

```dart
  test('script kind accepts an https url', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.0.0'),
    );
    await engine.install(_manifest({
      'kind': 'script',
      'binary': 'x',
      'alternatives': <String>[],
    }).copyForScript('https://example.com/install.sh'));
    expect(commands.single.executable, 'sh');
    expect(commands.single.arguments.last, contains('https://example.com/install.sh'));
  });

  test('script kind rejects non-https / metacharacter urls (no command run)', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.0.0'),
    );
    final result = await engine.install(_manifest({
      'kind': 'script',
      'binary': 'x',
    }).copyForScript('https://example.com/i.sh; rm -rf /'));
    expect(commands, isEmpty);
    expect(result.success, isFalse);
  });
```

Add this helper near the top of the test file (after `_manifest`):

```dart
extension on ExtensionManifest {
  /// Rebuilds the manifest with a `script` acquire pointing at [url].
  ExtensionManifest copyForScript(String url) => ExtensionManifest.fromJson({
        'id': id,
        'name': name,
        'acquire': {'kind': 'script', 'package': url, 'binary': 'x'},
        'detect': {'executable': 'x', 'versionArgs': ['--version']},
      });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/services/extension/extension_acquisition_engine_test.dart`
Expected: FAIL — the metacharacter URL currently builds a command (commands not empty).

- [ ] **Step 3: Implement hardening + default runner**

In `client/lib/services/extension/extension_acquisition_engine.dart`:

Add the import:

```dart
import 'dart:io';
```

Change the constructor so `runner` is optional with a local default:

```dart
  ExtensionAcquisitionEngine({
    ExtensionInstallRunner? runner,
    ExtensionDetector? detector,
  })  : _runner = runner ?? _defaultLocalRunner,
        _detector = detector ?? ExtensionDetector();
```

Add the default runner (static):

```dart
  static Future<CliInstallerCommandResult> _defaultLocalRunner(
    CliInstallerCommand command,
  ) async {
    try {
      final result = await Process.run(command.executable, command.arguments);
      return CliInstallerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on ProcessException catch (e) {
      return CliInstallerCommandResult(exitCode: 127, stderr: e.message);
    }
  }
```

Replace the `script` case in `_commandForKind` with a validated form:

```dart
      case 'script':
        if (!_isSafeScriptUrl(target)) return null;
        return CliInstallerCommand('sh', ['-c', 'curl -fsSL "$target" | sh']);
```

Add the validator (private method):

```dart
  static bool _isSafeScriptUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    // Reject anything that could break out of the double-quoted shell context.
    return !RegExp(r'''[\s"'`$\\;|&<>()]''').hasMatch(url);
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/services/extension/extension_acquisition_engine_test.dart`
Expected: PASS (the 6 Phase-2 tests + the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/extension_acquisition_engine.dart client/test/services/extension/extension_acquisition_engine_test.dart
git commit -m "feat(extensions): harden script-kind install + default local runner"
```

---

## Task 2: One-time legacy rtk-flag migration

**Files:**
- Create: `client/lib/services/extension/extension_state_migration.dart`
- Test: `client/test/services/extension/extension_state_migration_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/extension_state_migration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_state_migration.dart';

import '../../support/in_memory_filesystem.dart';

ExtensionRepository _repo(InMemoryFilesystem fs) => ExtensionRepository(
      fs: fs,
      stateFilePath: '/root/extensions/state.json',
      manifests: builtInExtensionManifests(),
    );

void main() {
  test('migrates legacy rtk=true into globalEnabled exactly once', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);

    await ExtensionStateMigration.run(repository: repo, legacyRtkEnabled: () async => true);
    expect((await repo.load(forceReload: true)).globalEnabled, contains('rtk'));

    // Second run with the legacy flag now false must NOT re-disable: migration
    // is one-shot, guarded by the `migrated` marker.
    await ExtensionStateMigration.run(repository: repo, legacyRtkEnabled: () async => false);
    expect((await repo.load(forceReload: true)).globalEnabled, contains('rtk'));
  });

  test('does not enable rtk when legacy flag was false', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await ExtensionStateMigration.run(repository: repo, legacyRtkEnabled: () async => false);
    expect((await repo.load(forceReload: true)).globalEnabled, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/services/extension/extension_state_migration_test.dart`
Expected: FAIL — "ExtensionStateMigration isn't defined".

- [ ] **Step 3: Add a `migrated` flag to `ExtensionRepository`**

The migration must run once. Add a lightweight marker to the repository (it already owns state.json). In `client/lib/repositories/extension_repository.dart`, add:

```dart
  Future<bool> isMigrated(String key) async =>
      (await load()).teamOverrides['__migrations__']?[key] == true;

  Future<void> markMigrated(String key) async {
    final state = await load();
    await save(state.withTeamOverride('__migrations__', key, true));
  }
```

> This reuses the `teamOverrides` map under a reserved `__migrations__` pseudo-team — no schema change, and `effectiveEnabledIds`/`effectiveEnabled` never query that team id for a real team.

- [ ] **Step 4: Implement the migration**

```dart
// client/lib/services/extension/extension_state_migration.dart
import '../../repositories/extension_repository.dart';

/// One-time migrations of legacy settings into [ExtensionRepository].
class ExtensionStateMigration {
  static const _rtkFlagKey = 'rtk_flag_v1';

  /// Copies the legacy `AppSettingsRepository.loadRtkEnabled` value into
  /// `globalEnabled` exactly once (guarded by a marker), so the old rtk
  /// toggle's state carries over to the unified store.
  static Future<void> run({
    required ExtensionRepository repository,
    required Future<bool> Function() legacyRtkEnabled,
  }) async {
    if (await repository.isMigrated(_rtkFlagKey)) return;
    if (await legacyRtkEnabled()) {
      await repository.setGlobalEnabled('rtk', true);
    }
    await repository.markMigrated(_rtkFlagKey);
  }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/services/extension/extension_state_migration_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add client/lib/repositories/extension_repository.dart client/lib/services/extension/extension_state_migration.dart client/test/services/extension/extension_state_migration_test.dart
git commit -m "feat(extensions): one-time legacy rtk-flag migration"
```

---

## Task 3: `ExtensionCubit`

**Files:**
- Create: `client/lib/cubits/extension_cubit.dart`
- Test: `client/test/cubits/extension_cubit_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/extension_cubit_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/extension_cubit.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/cli/installer_types.dart';

import '../support/in_memory_filesystem.dart';

ExtensionRepository _repo(InMemoryFilesystem fs) => ExtensionRepository(
      fs: fs,
      stateFilePath: '/root/extensions/state.json',
      manifests: builtInExtensionManifests(),
    );

/// Detector reporting rtk present (0.24.0, jq present) and codegraph absent.
ExtensionDetector _detector() => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return ProcessResult(0, 0, '/usr/bin/${args.first}', '');
        }
        if (args.length == 1 && args.first == 'codegraph') {
          return ProcessResult(0, 1, '', ''); // not found
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'rtk 0.24.0', '');
        return ProcessResult(0, 1, '', '');
      },
    );

void main() {
  test('load derives a row per built-in manifest with status', () async {
    final cubit = ExtensionCubit(
      _repo(InMemoryFilesystem()),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );

    await cubit.load();

    expect(cubit.state.status, ExtensionLoadStatus.ready);
    final rtk = cubit.state.rows.firstWhere((r) => r.id == 'rtk');
    final cg = cubit.state.rows.firstWhere((r) => r.id == 'codegraph');
    expect(rtk.status, ExtensionStatusCode.ready);
    expect(rtk.version, '0.24.0');
    expect(rtk.globalEnabled, isFalse);
    expect(cg.status, ExtensionStatusCode.notInstalled);
  });

  test('setGlobalEnabled persists and updates the row', () async {
    final fs = InMemoryFilesystem();
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(runner: (c) async => const CliInstallerCommandResult(exitCode: 0)),
      detector: _detector(),
    );
    await cubit.load();

    await cubit.setGlobalEnabled('rtk', true);

    expect(cubit.state.rows.firstWhere((r) => r.id == 'rtk').globalEnabled, isTrue);
    // persisted
    expect((await _repo(fs).load()).globalEnabled, contains('rtk'));
  });

  test('install records installed state and clears busy', () async {
    final fs = InMemoryFilesystem();
    // detector that reports codegraph present AFTER install
    var codegraphInstalled = false;
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'codegraph') {
          return codegraphInstalled
              ? ProcessResult(0, 0, '/usr/bin/codegraph', '')
              : ProcessResult(0, 1, '', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'codegraph 1.4.0', '');
        return ProcessResult(0, 1, '', '');
      },
    );
    final cubit = ExtensionCubit(
      _repo(fs),
      ExtensionAcquisitionEngine(
        runner: (c) async {
          codegraphInstalled = true;
          return const CliInstallerCommandResult(exitCode: 0);
        },
        detector: detector,
      ),
      detector: detector,
    );
    await cubit.load();

    await cubit.install('codegraph');

    expect(cubit.state.busyIds, isEmpty);
    expect((await _repo(fs).load()).installed.containsKey('codegraph'), isTrue);
    expect(cubit.state.rows.firstWhere((r) => r.id == 'codegraph').status, ExtensionStatusCode.ready);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/cubits/extension_cubit_test.dart`
Expected: FAIL — "ExtensionCubit isn't defined".

- [ ] **Step 3: Implement the cubit**

```dart
// client/lib/cubits/extension_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/extension_manifest.dart';
import '../repositories/extension_repository.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_detector.dart';

enum ExtensionLoadStatus { idle, loading, ready, error }

enum ExtensionStatusCode {
  notInstalled,
  ready,
  dependencyMissing,
  versionTooOld,
}

class ExtensionRow extends Equatable {
  const ExtensionRow({
    required this.id,
    required this.name,
    required this.description,
    required this.homepage,
    required this.globalEnabled,
    required this.installed,
    required this.status,
    this.version,
  });

  final String id;
  final String name;
  final String description;
  final String homepage;
  final bool globalEnabled;
  final bool installed;
  final ExtensionStatusCode status;
  final String? version;

  @override
  List<Object?> get props =>
      [id, name, description, homepage, globalEnabled, installed, status, version];
}

class ExtensionUiState extends Equatable {
  const ExtensionUiState({
    this.rows = const [],
    this.status = ExtensionLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
  });

  final List<ExtensionRow> rows;
  final ExtensionLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;

  ExtensionUiState copyWith({
    List<ExtensionRow>? rows,
    ExtensionLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
  }) =>
      ExtensionUiState(
        rows: rows ?? this.rows,
        status: status ?? this.status,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        busyIds: busyIds ?? this.busyIds,
      );

  @override
  List<Object?> get props => [rows, status, errorMessage, busyIds];
}

class ExtensionCubit extends Cubit<ExtensionUiState> {
  ExtensionCubit(
    this._repository,
    this._engine, {
    ExtensionDetector? detector,
  })  : _detector = detector ?? ExtensionDetector(),
        super(const ExtensionUiState());

  final ExtensionRepository _repository;
  final ExtensionAcquisitionEngine _engine;
  final ExtensionDetector _detector;

  Future<void> load() async {
    emit(state.copyWith(status: ExtensionLoadStatus.loading, clearError: true));
    try {
      final rows = <ExtensionRow>[];
      for (final manifest in _repository.manifests) {
        rows.add(await _buildRow(manifest));
      }
      emit(state.copyWith(rows: rows, status: ExtensionLoadStatus.ready, clearError: true));
    } catch (e) {
      emit(state.copyWith(status: ExtensionLoadStatus.error, errorMessage: e.toString()));
    }
  }

  Future<ExtensionRow> _buildRow(ExtensionManifest manifest) async {
    final probe = await _detector.probe(manifest.detect);
    final globalEnabled = (await _repository.load()).globalEnabled.contains(manifest.id);
    final status = !probe.found
        ? ExtensionStatusCode.notInstalled
        : probe.missingRequirements.isNotEmpty
            ? ExtensionStatusCode.dependencyMissing
            : !probe.satisfiesMinVersion
                ? ExtensionStatusCode.versionTooOld
                : ExtensionStatusCode.ready;
    return ExtensionRow(
      id: manifest.id,
      name: manifest.name,
      description: _description(manifest),
      homepage: manifest.homepage,
      globalEnabled: globalEnabled,
      installed: probe.found,
      status: status,
      version: probe.version,
    );
  }

  String _description(ExtensionManifest manifest) {
    final effect = manifest.effects.isEmpty ? '' : manifest.effects.first.kind;
    return effect; // UI maps kind → localized blurb; raw kind is a safe fallback.
  }

  Future<void> setGlobalEnabled(String id, bool enabled) async {
    await _withBusy(id, () async {
      await _repository.setGlobalEnabled(id, enabled);
      await _replaceRow(id);
    });
  }

  Future<void> install(String id) async {
    await _withBusy(id, () async {
      final manifest = _repository.manifests.firstWhere((m) => m.id == id);
      final result = await _engine.install(manifest);
      if (result.success) {
        await _repository.recordInstalled(id, result.version ?? '');
      } else {
        emit(state.copyWith(errorMessage: result.message));
      }
      await _replaceRow(id);
    });
  }

  Future<void> uninstall(String id) async {
    await _withBusy(id, () async {
      final manifest = _repository.manifests.firstWhere((m) => m.id == id);
      final result = await _engine.uninstall(manifest);
      if (result.success) {
        await _repository.recordUninstalled(id);
      } else {
        emit(state.copyWith(errorMessage: result.message));
      }
      await _replaceRow(id);
    });
  }

  Future<void> _replaceRow(String id) async {
    final manifest = _repository.manifests.firstWhere((m) => m.id == id);
    final updated = await _buildRow(manifest);
    emit(state.copyWith(
      rows: [for (final r in state.rows) if (r.id == id) updated else r],
    ));
  }

  Future<void> _withBusy(String id, Future<void> Function() body) async {
    emit(state.copyWith(busyIds: {...state.busyIds, id}, clearError: true));
    try {
      await body();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    } finally {
      emit(state.copyWith(busyIds: {...state.busyIds}..remove(id)));
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/cubits/extension_cubit_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/extension_cubit.dart client/test/cubits/extension_cubit_test.dart
git commit -m "feat(extensions): add ExtensionCubit"
```

---

## Task 4: Wire repository + cubit + migration + rtk cutover in `app_shell`

**Files:**
- Modify: `client/lib/app/app_shell.dart`

- [ ] **Step 1: Read the relevant app_shell regions**

Run: `grep -n "mcpCubit = McpCubit\|mcpRepository = McpRepository\|loadRtkEnabled\|BlocProvider\|MultiBlocProvider\|MultiRepositoryProvider\|extensionMcpContributor" client/lib/app/app_shell.dart`
Expected: shows where `mcpRepository`/`mcpCubit` are built (~L331/L374), where `loadRtkEnabled: appSettings.loadRtkEnabled` is passed (~L315), where the Phase-2 `extensionMcpContributor` closure builds an `ExtensionRepository` (~L347), and the provider list. Use these as anchors.

- [ ] **Step 2: Build a single shared `ExtensionRepository` + the cubit + migration**

Replace the Phase-2 inline `extensionMcpContributor` closure's repository construction with a shared instance built once. Near where `mcpRepository` is built, add:

```dart
  final extensionRepository = ExtensionRepository(
    fs: AppStorage.fs,
    stateFilePath: AppStorage.paths.extensionsStateJson,
    manifests: builtInExtensionManifests(),
  );
  await ExtensionStateMigration.run(
    repository: extensionRepository,
    legacyRtkEnabled: appSettings.loadRtkEnabled,
  );
  final extensionCubit = ExtensionCubit(
    extensionRepository,
    ExtensionAcquisitionEngine(),
  );
```

Add the imports:

```dart
import '../cubits/extension_cubit.dart';
import '../repositories/extension_repository.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_state_migration.dart';
// builtin_manifests + ExtensionProvisioner already imported by Phase 2
```

- [ ] **Step 3: Repoint `loadRtkEnabled` at the repository**

Change the `loadRtkEnabled:` argument (currently `appSettings.loadRtkEnabled`, passed into `SessionLifecycleService`/`ConfigProfileService`) to read the repo's global flag:

```dart
    loadRtkEnabled: () async =>
        (await extensionRepository.load(forceReload: true)).globalEnabled.contains('rtk'),
```

- [ ] **Step 4: Reuse the shared repository in the Phase-2 contributor**

Change the Phase-2 `extensionMcpContributor` closure to use `extensionRepository` instead of constructing a new one:

```dart
      extensionMcpContributor: (teamId) async {
        final enabled = await extensionRepository.effectiveEnabledIds(teamId);
        final provisioner = ExtensionProvisioner(
          manifests: builtInExtensionManifests(),
          isEnabled: (id) async => enabled.contains(id),
        );
        return provisioner.collectMcpContributions();
      },
```

- [ ] **Step 5: Provide `ExtensionCubit` in the widget tree**

In the provider list where `mcpCubit` is provided (find `BlocProvider.value(value: mcpCubit)` or the `providers:`/`blocs:` aggregation), add `BlocProvider.value(value: extensionCubit)`. Mirror exactly how `mcpCubit` is provided (same construct). If the app shell holds cubits on a state object for disposal, add `extensionCubit` there and `extensionCubit.close()` in its dispose, mirroring `mcpCubit`.

- [ ] **Step 6: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(extensions): provide ExtensionCubit, migrate + cut rtk over to repository"
```

---

## Task 5: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add keys to `app_en.arb`** (next to the existing `rtkSettings*` block)

```json
  "extensionsSettingsTitle": "Extensions",
  "extensionsSettingsDescription": "Install and enable external tools that augment your agents.",
  "extensionEnableLabel": "Enabled",
  "extensionInstall": "Install",
  "extensionUninstall": "Uninstall",
  "extensionInstallGuide": "Install guide",
  "extensionStatusNotInstalled": "Not installed",
  "extensionStatusReady": "Ready",
  "extensionStatusReadyVersion": "Ready ({version})",
  "@extensionStatusReadyVersion": {
    "placeholders": { "version": { "type": "String" } }
  },
  "extensionStatusDependencyMissing": "Missing dependency",
  "extensionStatusVersionTooOld": "Installed version is too old",
  "extensionKindMcpServer": "Code intelligence (MCP)",
  "extensionKindSettingsHook": "Token savings (hook)",
```

- [ ] **Step 2: Add the same keys to `app_zh.arb`** (translations; keep the `@`-metadata only in `app_en.arb` per repo convention — check an existing placeholder key to confirm whether `app_zh.arb` repeats `@`-blocks; mirror that)

```json
  "extensionsSettingsTitle": "扩展",
  "extensionsSettingsDescription": "安装并启用增强 Agent 的外部工具。",
  "extensionEnableLabel": "已启用",
  "extensionInstall": "安装",
  "extensionUninstall": "卸载",
  "extensionInstallGuide": "安装指引",
  "extensionStatusNotInstalled": "未安装",
  "extensionStatusReady": "就绪",
  "extensionStatusReadyVersion": "就绪（{version}）",
  "extensionStatusDependencyMissing": "缺少依赖",
  "extensionStatusVersionTooOld": "已安装版本过旧",
  "extensionKindMcpServer": "代码智能（MCP）",
  "extensionKindSettingsHook": "Token 节省（hook）",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter pub get`
Expected: `app_localizations*.dart` regenerated with the new getters (the repo generates l10n on `pub get`; see AGENTS.md).

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "i18n(extensions): add extension settings strings"
```

---

## Task 6: Replace `_RtkSettingsSection` with `_ExtensionsSection`

**Files:**
- Modify: `client/lib/pages/config_workspace.dart`

- [ ] **Step 1: Swap the section usage**

At `config_workspace.dart:197`, replace:

```dart
          SettingsSurfaceCard(child: _RtkSettingsSection()),
```
with:

```dart
          SettingsSurfaceCard(child: _ExtensionsSection()),
```

- [ ] **Step 2: Delete the old `_RtkSettingsSection` + `_RtkSettingsSectionState`** (the class block starting at `class _RtkSettingsSection extends StatefulWidget`) and remove now-unused imports (`builtin_manifests.dart`, `extension_detector.dart`, `extension_probe.dart`, and `AppSettingsRepository` if no longer referenced — verify with analyze in Step 4).

- [ ] **Step 3: Add the new section** (replace the deleted block). It reads `ExtensionCubit` from context (provided in Task 4) and renders one row per extension.

```dart
class _ExtensionsSection extends StatefulWidget {
  const _ExtensionsSection();

  @override
  State<_ExtensionsSection> createState() => _ExtensionsSectionState();
}

class _ExtensionsSectionState extends State<_ExtensionsSection> {
  @override
  void initState() {
    super.initState();
    context.read<ExtensionCubit>().load();
  }

  String _statusText(BuildContext context, ExtensionRow row) {
    final l10n = context.l10n;
    switch (row.status) {
      case ExtensionStatusCode.notInstalled:
        return l10n.extensionStatusNotInstalled;
      case ExtensionStatusCode.dependencyMissing:
        return l10n.extensionStatusDependencyMissing;
      case ExtensionStatusCode.versionTooOld:
        return l10n.extensionStatusVersionTooOld;
      case ExtensionStatusCode.ready:
        final v = row.version?.trim();
        return (v == null || v.isEmpty)
            ? l10n.extensionStatusReady
            : l10n.extensionStatusReadyVersion(v);
    }
  }

  Future<void> _openHomepage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<ExtensionCubit, ExtensionUiState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroupHeader(title: l10n.extensionsSettingsTitle),
            if (state.status == ExtensionLoadStatus.loading && state.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              for (var i = 0; i < state.rows.length; i++)
                _extensionRow(context, state, state.rows[i],
                    last: i == state.rows.length - 1),
          ],
        );
      },
    );
  }

  Widget _extensionRow(
    BuildContext context,
    ExtensionUiState state,
    ExtensionRow row, {
    required bool last,
  }) {
    final l10n = context.l10n;
    final cubit = context.read<ExtensionCubit>();
    final busy = state.busyIds.contains(row.id);
    final trailing = busy
        ? const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: row.installed
                    ? () => cubit.uninstall(row.id)
                    : () => cubit.install(row.id),
                child: Text(row.installed
                    ? l10n.extensionUninstall
                    : l10n.extensionInstall),
              ),
              Switch(
                value: row.globalEnabled,
                onChanged: row.installed
                    ? (v) => cubit.setGlobalEnabled(row.id, v)
                    : null,
              ),
            ],
          );
    return SettingsLabeledRow(
      title: row.name,
      subtitle: '${_statusText(context, row)} · '
          '${row.homepage.isNotEmpty ? row.homepage : row.description}',
      trailing: trailing,
      showDividerBelow: !last,
    );
  }
}
```

- [ ] **Step 4: Ensure imports**

Add to `config_workspace.dart` imports (if missing): `import 'package:flutter_bloc/flutter_bloc.dart';`, `import '../cubits/extension_cubit.dart';`. Keep `url_launcher` (`launchUrl`) — already used by the deleted rtk section.

- [ ] **Step 5: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/config_workspace.dart`
Expected: "No issues found!" (fix any unused-import the deletion left).

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/config_workspace.dart
git commit -m "feat(extensions): Extensions settings section replaces rtk block"
```

---

## Task 7: Full verification gate

- [ ] **Step 1: Analyze (whole project)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: "No issues found!" — fix any new error/warning.

- [ ] **Step 2: Full test suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all pass (Phase-1/2 + the new 3a cubit/migration/acquisition tests). Investigate any failure.

- [ ] **Step 3: Confirm rtk still applies via the new source**

Run: `flutter test test/services/provider/config_profile_service_rtk_test.dart`
Expected: PASS — unchanged; rtk hook behaviour is independent of where `loadRtkEnabled` resolves (the test injects its own `loadRtkEnabled`).

- [ ] **Step 4: Commit any fixups**

```bash
git add -A && git commit -m "chore(extensions): phase 3a verification fixups" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage (Phase 3 core slice of the design spec §9–§10):**

| Spec element | Task |
|------|------|
| Extensions management surface: install status, install/uninstall, global enable, status display (§9) | Tasks 3, 6 |
| Move rtk probe UI off `config_workspace`'s bespoke section (§10) | Task 6 (replaces `_RtkSettingsSection`) |
| rtk enablement unified into `ExtensionRepository`; old flag migrated (§7, §10) | Tasks 2, 4 |
| `ExtensionCubit` (§7 state mgmt) | Task 3 |
| script-kind hardening (Phase-2 review minor) | Task 1 |
| l10n only in arb files (AGENTS.md) | Task 5 |

Deferred to **Phase 3b** (called out in phase boundary): per-team override **UI** (`team_config_page` `_TeamExtensionsSection` + `TeamConfigSection.extensions` route/nav); per-team override of the rtk **settings-hook** effect (needs `ConfigProfileDelegate` teamId threading). codegraph's per-team MCP override already *resolves* via Phase 2 — only its UI is pending.

**2. Placeholder scan:** No "TBD/TODO". Every code step has full code; run steps have commands + expected output. Task 4 Steps 1 & 5 and Task 5 Step 2 are read-then-mirror against named anchors (app_shell provider construct, arb `@`-metadata convention) — concrete, not deferred work.

**3. Type consistency:**
- `ExtensionRepository` gains `isMigrated`/`markMigrated` (Task 2) consumed by `ExtensionStateMigration` (Task 2); `manifests`/`load`/`setGlobalEnabled`/`recordInstalled`/`recordUninstalled`/`effectiveEnabledIds` (Phase 2) consumed by `ExtensionCubit` (Task 3) + `app_shell` (Task 4).
- `ExtensionAcquisitionEngine({runner?, detector?})` — `runner` made optional in Task 1, used parameterless in Task 4 (`ExtensionAcquisitionEngine()`).
- `ExtensionCubit(repo, engine, {detector})` + `ExtensionUiState`/`ExtensionRow`/`ExtensionLoadStatus`/`ExtensionStatusCode` (Task 3) consumed by the widget in Task 6 and provided in Task 4.
- l10n getters added in Task 5 (`extensionsSettingsTitle`, `extensionStatus*`, `extensionInstall`/`extensionUninstall`, `extensionStatusReadyVersion(version)`) consumed in Task 6.
- `loadRtkEnabled` callback contract (`Future<bool> Function()`) unchanged — only its body repointed (Task 4), so `ConfigProfileService` and `config_profile_service_rtk_test` are untouched (Task 7 Step 3).

No inconsistencies found.
