# Extension System — Phase 2 (Acquisition + mcp-server effect + codegraph) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make codegraph work end-to-end as an installable MCP extension — enabled/installed via a new `ExtensionRepository` (state.json), contributed into a team's MCP snapshot, and installable via a generic `ExtensionAcquisitionEngine`.

**Architecture:** Add the `mcp-server` effect kind: enabled+ready extensions contribute `McpServer` entries that `team_cubit._syncMcpForSelected` merges into the catalog + id list it already passes to `TeamMcpLinkerService.syncForTeam` (so `TeamMcpLinkerService` is unchanged). Enablement/install state lives in `{teampilotRoot}/extensions/state.json` via `ExtensionRepository` (global default + per-team override). A generic `ExtensionAcquisitionEngine` installs the underlying tool by mapping `acquire.kind` → a shell command, reusing the installer value types (`CliInstallerCommand` / `CliInstallerCommandResult`). No visual UI this phase (Phase 3).

**Tech Stack:** Dart / Flutter, `flutter_bloc`, `package:test` + `flutter_test`, the Phase-1 extension engine (`ExtensionManifest` / `ExtensionDetector` / `ExtensionProvisioner`), `McpServer` + `TeamMcpLinkerService`, `cli/installer_types.dart`.

**Builds on Phase 1 (already landed):** `client/lib/models/extension_manifest.dart`, `client/lib/services/extension/{extension_detector,extension_probe,extension_provisioner,builtin_manifests}.dart`, `client/lib/services/extension/effect/settings_hook_effect_applier.dart`.

**Phase boundary — NOT in Phase 2 (Phase 3):**
- Any visual UI: `/extensions` page, install/enable buttons, per-team override UI in `team_config_page.dart`, moving rtk probe UI.
- Migrating the rtk settings-hook path off its Phase-1 global toggle (`AppSettingsRepository.loadRtkEnabled`) onto `ExtensionRepository`; per-team override of the settings-hook effect (needs a `ConfigProfileDelegate` change).
- `ExtensionCubit` (Phase 3; Phase 2 uses `ExtensionRepository` directly + DI function injection).
- SSH/Android remote one-click install (engine is desktop/local; remote stays detect-only).

**Scope note on enablement:** Phase 2 introduces `ExtensionRepository` and uses it for **codegraph** (the MCP path, via `team_cubit`). The **rtk** settings-hook path keeps reading `AppSettingsRepository.loadRtkEnabled` exactly as in Phase 1 — untouched. The two converge in Phase 3.

---

## File Structure

**New files:**

| File | Responsibility |
|------|----------------|
| `client/lib/models/extension_state.dart` | `ExtensionState` + `InstalledExtension` value types; `effectiveEnabled(teamId,id)` resolution; JSON round-trip. |
| `client/lib/repositories/extension_repository.dart` | Read/write `extensions/state.json`; enablement queries; install/enable mutations. Mirrors `McpRepository` shape. |
| `client/lib/services/extension/extension_acquisition_engine.dart` | Map `acquire.kind`(+`alternatives`) → install/uninstall commands; run via an injected runner; re-probe + report result. |
| `client/test/models/extension_state_test.dart` | State resolution + round-trip tests. |
| `client/test/repositories/extension_repository_test.dart` | Repository read/write/mutation tests over an in-memory FS. |
| `client/test/services/extension/extension_acquisition_engine_test.dart` | Per-kind command + alternatives-fallback tests. |
| `client/test/services/extension/extension_provisioner_mcp_test.dart` | `collectMcpContributions` tests. |
| `client/test/cubits/team_cubit_extension_mcp_test.dart` | team_cubit merges extension MCP contribution into the snapshot. |

**Modified files:**

| File | Change |
|------|--------|
| `client/lib/models/extension_manifest.dart` | Add `ExtensionEffect.mcpServer` getter. |
| `client/lib/services/extension/extension_provisioner.dart` | Make `hookProvisionerFor` optional; add `collectMcpContributions()`. |
| `client/lib/services/extension/builtin_manifests.dart` | Add the codegraph manifest; return both. |
| `client/lib/services/storage/app_storage.dart` | Add `AppPaths.extensionsStateJson` (+ `extensionsStateJsonForTeampilotRoot`). |
| `client/lib/cubits/team_cubit.dart` | Inject an extension-MCP contributor fn; merge its output into `_syncMcpForSelected`. |
| `client/lib/app/app_shell.dart` | Wire the default contributor (ExtensionRepository-backed) into `TeamCubit`. |

> All commands below run from the `client/` directory unless noted.

---

## Task 1: `ExtensionState` model

**Files:**
- Create: `client/lib/models/extension_state.dart`
- Test: `client/test/models/extension_state_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/extension_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_state.dart';

void main() {
  group('ExtensionState.effectiveEnabled', () {
    test('falls back to globalEnabled when no team override', () {
      const state = ExtensionState(globalEnabled: {'rtk'});
      expect(state.effectiveEnabled('team-a', 'rtk'), isTrue);
      expect(state.effectiveEnabled('team-a', 'codegraph'), isFalse);
    });

    test('team override wins over global', () {
      const state = ExtensionState(
        globalEnabled: {'rtk'},
        teamOverrides: {
          'team-a': {'rtk': false, 'codegraph': true},
        },
      );
      expect(state.effectiveEnabled('team-a', 'rtk'), isFalse);
      expect(state.effectiveEnabled('team-a', 'codegraph'), isTrue);
      // other teams still see global
      expect(state.effectiveEnabled('team-b', 'rtk'), isTrue);
    });
  });

  group('ExtensionState JSON round-trip', () {
    test('preserves installed + enabled + overrides', () {
      const state = ExtensionState(
        installed: {'codegraph': InstalledExtension(id: 'codegraph', version: '1.4.0', installedAt: 5)},
        globalEnabled: {'rtk'},
        teamOverrides: {
          'team-a': {'codegraph': true},
        },
      );
      final restored = ExtensionState.fromJson(state.toJson());
      expect(restored.installed['codegraph']!.version, '1.4.0');
      expect(restored.installed['codegraph']!.installedAt, 5);
      expect(restored.globalEnabled, {'rtk'});
      expect(restored.teamOverrides['team-a'], {'codegraph': true});
    });

    test('empty state round-trips to empty', () {
      final restored = ExtensionState.fromJson(const ExtensionState().toJson());
      expect(restored.installed, isEmpty);
      expect(restored.globalEnabled, isEmpty);
      expect(restored.teamOverrides, isEmpty);
    });
  });

  group('mutation helpers', () {
    test('withGlobalEnabled toggles membership', () {
      const state = ExtensionState();
      expect(state.withGlobalEnabled('rtk', true).globalEnabled, {'rtk'});
      expect(
        state.withGlobalEnabled('rtk', true).withGlobalEnabled('rtk', false).globalEnabled,
        isEmpty,
      );
    });

    test('withTeamOverride sets and clears', () {
      const state = ExtensionState();
      final set = state.withTeamOverride('team-a', 'rtk', false);
      expect(set.teamOverrides['team-a'], {'rtk': false});
      final cleared = set.withTeamOverride('team-a', 'rtk', null);
      expect(cleared.teamOverrides['team-a'] ?? const {}, isEmpty);
    });

    test('withInstalled / withUninstalled', () {
      const state = ExtensionState();
      final installed = state.withInstalled('codegraph', '1.0.0', 42);
      expect(installed.installed['codegraph']!.version, '1.0.0');
      expect(installed.withUninstalled('codegraph').installed, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/extension_state_test.dart`
Expected: FAIL — "ExtensionState isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/models/extension_state.dart

/// One installed underlying tool, recorded after a successful acquisition.
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    this.version = '',
    this.installedAt = 0,
  });

  final String id;
  final String version;
  final int installedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'installedAt': installedAt,
      };

  factory InstalledExtension.fromJson(Map<String, Object?> json) =>
      InstalledExtension(
        id: (json['id'] as String?)?.trim() ?? '',
        version: json['version'] as String? ?? '',
        installedAt: (json['installedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Persistent extension install + enablement state.
///
/// Enablement model: app-level [globalEnabled] is the default; [teamOverrides]
/// per `(teamId, extensionId)` win when present.
class ExtensionState {
  const ExtensionState({
    this.installed = const {},
    this.globalEnabled = const {},
    this.teamOverrides = const {},
  });

  final Map<String, InstalledExtension> installed;
  final Set<String> globalEnabled;
  final Map<String, Map<String, bool>> teamOverrides;

  bool effectiveEnabled(String teamId, String extensionId) {
    final override = teamOverrides[teamId]?[extensionId];
    if (override != null) return override;
    return globalEnabled.contains(extensionId);
  }

  ExtensionState withGlobalEnabled(String id, bool enabled) {
    final next = Set<String>.from(globalEnabled);
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return _copy(globalEnabled: next);
  }

  /// [value] null clears the override (fall back to global).
  ExtensionState withTeamOverride(String teamId, String id, bool? value) {
    final next = {
      for (final entry in teamOverrides.entries)
        entry.key: Map<String, bool>.from(entry.value),
    };
    final team = next.putIfAbsent(teamId, () => <String, bool>{});
    if (value == null) {
      team.remove(id);
    } else {
      team[id] = value;
    }
    if (team.isEmpty) next.remove(teamId);
    return _copy(teamOverrides: next);
  }

  ExtensionState withInstalled(String id, String version, int installedAt) {
    final next = Map<String, InstalledExtension>.from(installed);
    next[id] = InstalledExtension(id: id, version: version, installedAt: installedAt);
    return _copy(installed: next);
  }

  ExtensionState withUninstalled(String id) {
    final next = Map<String, InstalledExtension>.from(installed)..remove(id);
    return _copy(installed: next);
  }

  ExtensionState _copy({
    Map<String, InstalledExtension>? installed,
    Set<String>? globalEnabled,
    Map<String, Map<String, bool>>? teamOverrides,
  }) =>
      ExtensionState(
        installed: installed ?? this.installed,
        globalEnabled: globalEnabled ?? this.globalEnabled,
        teamOverrides: teamOverrides ?? this.teamOverrides,
      );

  Map<String, Object?> toJson() => {
        'installed': {
          for (final entry in installed.entries) entry.key: entry.value.toJson(),
        },
        'globalEnabled': globalEnabled.toList()..sort(),
        'teamOverrides': {
          for (final entry in teamOverrides.entries)
            entry.key: Map<String, bool>.from(entry.value),
        },
      };

  factory ExtensionState.fromJson(Map<String, Object?> json) {
    final installedRaw = json['installed'];
    final globalRaw = json['globalEnabled'];
    final overridesRaw = json['teamOverrides'];
    return ExtensionState(
      installed: installedRaw is Map
          ? {
              for (final entry in installedRaw.entries)
                entry.key.toString(): InstalledExtension.fromJson(
                  (entry.value as Map).cast<String, Object?>(),
                ),
            }
          : const {},
      globalEnabled: globalRaw is List
          ? globalRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet()
          : const {},
      teamOverrides: overridesRaw is Map
          ? {
              for (final entry in overridesRaw.entries)
                entry.key.toString(): {
                  if (entry.value is Map)
                    for (final inner in (entry.value as Map).entries)
                      inner.key.toString(): inner.value == true,
                },
            }
          : const {},
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/extension_state_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/extension_state.dart client/test/models/extension_state_test.dart
git commit -m "feat(extensions): add ExtensionState model"
```

---

## Task 2: `AppPaths.extensionsStateJson`

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart`

This is a small path-helper add; verified via Task 3's repository test (no standalone test needed — it is trivial string joining following the existing `teamsDir` / `pluginsJsonForTeampilotRoot` pattern).

- [ ] **Step 1: Add the instance getter**

In `class AppPaths`, next to `String get teamsDir => _ctx.join(basePath, 'teams');`, add:

```dart
  String get extensionsStateJson =>
      _ctx.join(basePath, 'extensions', 'state.json');
```

- [ ] **Step 2: Add the static teampilot-root helper**

Next to `static String pluginsJsonForTeampilotRoot(String teampilotRoot) => _pathUnderTeampilotRoot(teampilotRoot, 'plugins/plugins.json');`, add:

```dart
  static String extensionsStateJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'extensions/state.json');
```

- [ ] **Step 3: Verify it analyzes**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/storage/app_storage.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/storage/app_storage.dart
git commit -m "feat(extensions): add extensions/state.json path helper"
```

---

## Task 3: `ExtensionRepository`

**Files:**
- Create: `client/lib/repositories/extension_repository.dart`
- Test: `client/test/repositories/extension_repository_test.dart`

The repository owns `state.json`. It takes a `Filesystem` + explicit `stateFilePath` (tests inject an in-memory FS + temp path; production resolves `AppStorage.paths.extensionsStateJson`). It also holds the manifest list so `effectiveEnabledIds` can restrict to known ids.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/repositories/extension_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';

import '../support/in_memory_filesystem.dart'; // test/support/in_memory_filesystem.dart (class InMemoryFilesystem)

ExtensionRepository _repo(InMemoryFilesystem fs, {List<ExtensionManifest>? manifests}) =>
    ExtensionRepository(
      fs: fs,
      stateFilePath: '/root/extensions/state.json',
      manifests: manifests ?? builtInExtensionManifests(),
    );

void main() {
  test('load returns empty state when file absent', () async {
    final repo = _repo(InMemoryFilesystem());
    final state = await repo.load();
    expect(state.globalEnabled, isEmpty);
    expect(state.installed, isEmpty);
  });

  test('setGlobalEnabled persists and reloads', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.setGlobalEnabled('codegraph', true);

    final fresh = _repo(fs);
    expect((await fresh.load()).globalEnabled, contains('codegraph'));
  });

  test('effectiveEnabledIds applies override over global', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.setGlobalEnabled('codegraph', true);
    await repo.setTeamOverride('team-a', 'codegraph', false);

    expect(await repo.effectiveEnabledIds('team-b'), contains('codegraph'));
    expect(await repo.effectiveEnabledIds('team-a'), isNot(contains('codegraph')));
  });

  test('recordInstalled / recordUninstalled persist', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.recordInstalled('codegraph', '1.4.0');
    expect((await repo.load()).installed['codegraph']!.version, '1.4.0');
    await repo.recordUninstalled('codegraph');
    expect((await repo.load()).installed, isEmpty);
  });

  test('isEffectivelyEnabled reflects state', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    expect(await repo.isEffectivelyEnabled('team-a', 'codegraph'), isFalse);
    await repo.setGlobalEnabled('codegraph', true);
    expect(await repo.isEffectivelyEnabled('team-a', 'codegraph'), isTrue);
  });
}
```

> **Test-infra check:** before Step 1, confirm the in-memory FS import path and class name with `grep -rn "class InMemoryFilesystem" client/test client/lib`. Phase 1's provisioner test used `package:teampilot/test_support/in_memory_filesystem.dart` / `InMemoryFilesystem`; if the path differs, use the path that file actually resolves to (e.g. `package:teampilot/...` mapped from `test/support/`). Adjust the import in this test accordingly.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/extension_repository_test.dart`
Expected: FAIL — "ExtensionRepository isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/repositories/extension_repository.dart
import 'dart:convert';

import '../models/extension_manifest.dart';
import '../models/extension_state.dart';
import '../services/io/filesystem.dart';

/// Owns `{teampilotRoot}/extensions/state.json`: install + enablement state.
class ExtensionRepository {
  ExtensionRepository({
    required Filesystem fs,
    required String stateFilePath,
    required List<ExtensionManifest> manifests,
  })  : _fs = fs,
        _stateFilePath = stateFilePath,
        _manifests = manifests;

  final Filesystem _fs;
  final String _stateFilePath;
  final List<ExtensionManifest> _manifests;

  ExtensionState? _cache;

  List<ExtensionManifest> get manifests => _manifests;

  Future<ExtensionState> load({bool forceReload = false}) async {
    if (!forceReload && _cache != null) return _cache!;
    final stat = await _fs.stat(_stateFilePath);
    if (!stat.exists) {
      return _cache = const ExtensionState();
    }
    final raw = await _fs.readString(_stateFilePath);
    if (raw == null || raw.trim().isEmpty) {
      return _cache = const ExtensionState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _cache =
            ExtensionState.fromJson(decoded.cast<String, Object?>());
      }
    } on Object {
      // Corrupt file → treat as empty; next save overwrites.
    }
    return _cache = const ExtensionState();
  }

  Future<void> save(ExtensionState state) async {
    _cache = state;
    final dir = _fs.pathContext.dirname(_stateFilePath);
    await _fs.ensureDir(dir);
    await _fs.atomicWrite(
      _stateFilePath,
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  Future<void> setGlobalEnabled(String id, bool enabled) async =>
      save((await load()).withGlobalEnabled(id, enabled));

  Future<void> setTeamOverride(String teamId, String id, bool? value) async =>
      save((await load()).withTeamOverride(teamId, id, value));

  Future<void> recordInstalled(String id, String version) async => save(
        (await load()).withInstalled(
          id,
          version,
          DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Future<void> recordUninstalled(String id) async =>
      save((await load()).withUninstalled(id));

  Future<bool> isEffectivelyEnabled(String teamId, String id) async =>
      (await load()).effectiveEnabled(teamId, id);

  /// Known extension ids that are effectively enabled for [teamId].
  Future<Set<String>> effectiveEnabledIds(String teamId) async {
    final state = await load();
    return {
      for (final manifest in _manifests)
        if (state.effectiveEnabled(teamId, manifest.id)) manifest.id,
    };
  }
}
```

> **Filesystem API check:** before Step 3, confirm `Filesystem` exposes `stat(path)` (with `.exists`), `readString(path)`, `ensureDir(path)`, `atomicWrite(path, contents)`, and `pathContext.dirname(...)` — all are used by `McpCatalogService`/`CliDataLayout`/`config_profile_service`, so they exist; if `atomicWrite` is named differently in the concrete FS, match the name used in `client/lib/services/mcp/` catalog code.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/extension_repository_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/extension_repository.dart client/test/repositories/extension_repository_test.dart
git commit -m "feat(extensions): add ExtensionRepository (state.json)"
```

---

## Task 4: `mcp-server` effect accessor + `collectMcpContributions`

**Files:**
- Modify: `client/lib/models/extension_manifest.dart`
- Modify: `client/lib/services/extension/extension_provisioner.dart`
- Test: `client/test/services/extension/extension_provisioner_mcp_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/extension_provisioner_mcp_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/extension/extension_provisioner.dart';

ProcessResult _ok(String s) => ProcessResult(0, 0, s, '');
ProcessResult _fail() => ProcessResult(0, 1, '', '');

ExtensionManifest get _codegraph => ExtensionManifest.fromJson({
      'id': 'codegraph',
      'name': 'CodeGraph',
      'detect': {'executable': 'codegraph', 'versionArgs': ['--version']},
      'effects': [
        {
          'kind': 'mcp-server',
          'appliesTo': ['claude', 'flashskyai'],
          'name': 'codegraph',
          'server': {'command': 'codegraph', 'args': ['serve', '--mcp']},
        },
      ],
    });

ExtensionProvisioner _provisioner({
  required bool enabled,
  required ExtensionDetector detector,
}) =>
    ExtensionProvisioner(
      manifests: [_codegraph],
      isEnabled: (id) async => id == 'codegraph' && enabled,
      detector: detector,
    );

ExtensionDetector _present() => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'codegraph') {
          return _ok('/usr/bin/codegraph');
        }
        if (args.contains('--version')) return _ok('codegraph 1.4.0');
        return _fail();
      },
    );

void main() {
  test('contributes an McpServer when enabled and present', () async {
    final servers =
        await _provisioner(enabled: true, detector: _present()).collectMcpContributions();
    expect(servers, hasLength(1));
    final s = servers.single;
    expect(s.id, 'ext:codegraph');
    expect(s.name, 'codegraph');
    expect(s.enabled, isTrue);
    expect(s.server['command'], 'codegraph');
    expect(s.server['args'], ['serve', '--mcp']);
  });

  test('no contribution when disabled', () async {
    final servers =
        await _provisioner(enabled: false, detector: _present()).collectMcpContributions();
    expect(servers, isEmpty);
  });

  test('no contribution when tool not present', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final servers =
        await _provisioner(enabled: true, detector: detector).collectMcpContributions();
    expect(servers, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/extension_provisioner_mcp_test.dart`
Expected: FAIL — "collectMcpContributions isn't defined" (and the `mcpServer` getter missing).

- [ ] **Step 3a: Add the `mcpServer` getter to `ExtensionEffect`**

In `client/lib/models/extension_manifest.dart`, inside `class ExtensionEffect`, next to the existing settings-hook getters, add:

```dart
  // mcp-server accessors.
  String? get mcpName => config['name'] as String?;
  Map<String, Object?>? get mcpServer {
    final raw = config['server'];
    return raw is Map ? raw.cast<String, Object?>() : null;
  }
```

- [ ] **Step 3b: Make `hookProvisionerFor` optional and add `collectMcpContributions`**

In `client/lib/services/extension/extension_provisioner.dart`:

Add the import at the top:

```dart
import '../../models/mcp_server.dart';
```

Change the constructor param + field from required to optional:

```dart
    HookProvisionerFactory? hookProvisionerFor,
```
```dart
  final HookProvisionerFactory? _hookProvisionerFor;
```

In `applySettings`, replace the line `final provisioner = _hookProvisionerFor(effect.scriptAsset ?? manifest.id);` with:

```dart
        final factory = _hookProvisionerFor;
        if (factory == null) {
          throw StateError(
            'ExtensionProvisioner: settings-hook effect needs a hookProvisionerFor',
          );
        }
        final provisioner = factory(effect.scriptAsset ?? manifest.id);
```

Add the new method after `applySettings`:

```dart
  /// `McpServer` entries contributed by every ready, enabled extension with an
  /// `mcp-server` effect. Merged into the team MCP snapshot by the caller.
  Future<List<McpServer>> collectMcpContributions() async {
    final out = <McpServer>[];
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      final probe = await _detector.probe(manifest.detect);
      if (!probe.isReady) continue;
      for (final effect in manifest.effects) {
        if (effect.kind != 'mcp-server') continue;
        final serverMap = effect.mcpServer ?? const <String, Object?>{};
        if (serverMap.isEmpty) continue;
        final name = effect.mcpName?.trim();
        out.add(
          McpServer(
            id: 'ext:${manifest.id}',
            name: (name != null && name.isNotEmpty) ? name : manifest.id,
            server: serverMap,
            enabled: true,
          ),
        );
      }
    }
    return out;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/extension/extension_provisioner_mcp_test.dart test/services/extension/extension_provisioner_test.dart`
Expected: PASS (3 new + 7 existing Phase-1 tests still green — the optional `hookProvisionerFor` keeps Phase-1 callers working).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/extension_manifest.dart client/lib/services/extension/extension_provisioner.dart client/test/services/extension/extension_provisioner_mcp_test.dart
git commit -m "feat(extensions): mcp-server effect contributions in ExtensionProvisioner"
```

---

## Task 5: codegraph built-in manifest

**Files:**
- Modify: `client/lib/services/extension/builtin_manifests.dart`
- Test: `client/test/services/extension/builtin_manifests_test.dart` (extend existing)

- [ ] **Step 1: Add the failing test (append to the existing file)**

```dart
  // append inside the existing main() in builtin_manifests_test.dart
  test('built-in manifests include a valid codegraph mcp manifest', () {
    final cg = builtInExtensionManifests().firstWhere((m) => m.id == 'codegraph');
    expect(cg.detect.executable, 'codegraph');
    expect(cg.acquire!.kind, 'node-package');
    expect(cg.acquire!.package, '@colbymchenry/codegraph');

    final mcp = cg.effects.firstWhere((e) => e.kind == 'mcp-server');
    expect(mcp.mcpName, 'codegraph');
    expect(mcp.mcpServer!['command'], 'codegraph');
    expect(mcp.mcpServer!['args'], ['serve', '--mcp']);
    expect(mcp.appliesTo, containsAll(['claude', 'flashskyai']));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/builtin_manifests_test.dart`
Expected: FAIL — `Bad state: No element` (no codegraph manifest yet).

- [ ] **Step 3: Add the codegraph manifest**

In `client/lib/services/extension/builtin_manifests.dart`, add the constant and include it in the returned list:

```dart
const String codegraphManifestJson = '''
{
  "id": "codegraph",
  "name": "CodeGraph",
  "version": "1.x",
  "homepage": "https://github.com/colbymchenry/codegraph",
  "acquire": {
    "kind": "node-package",
    "package": "@colbymchenry/codegraph",
    "binary": "codegraph",
    "allowNpx": true
  },
  "detect": {
    "executable": "codegraph",
    "versionArgs": ["--version"]
  },
  "effects": [
    {
      "kind": "mcp-server",
      "appliesTo": ["claude", "flashskyai"],
      "name": "codegraph",
      "server": { "command": "codegraph", "args": ["serve", "--mcp"] }
    }
  ]
}
''';
```

Change `builtInExtensionManifests()` to:

```dart
List<ExtensionManifest> builtInExtensionManifests() => [
      ExtensionManifest.fromJson(
        jsonDecode(rtkManifestJson) as Map<String, Object?>,
      ),
      ExtensionManifest.fromJson(
        jsonDecode(codegraphManifestJson) as Map<String, Object?>,
      ),
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/builtin_manifests_test.dart`
Expected: PASS (rtk test + new codegraph test).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/builtin_manifests.dart client/test/services/extension/builtin_manifests_test.dart
git commit -m "feat(extensions): add built-in codegraph manifest"
```

---

## Task 6: Merge extension MCP contributions in `team_cubit`

**Files:**
- Modify: `client/lib/cubits/team_cubit.dart`
- Test: `client/test/cubits/team_cubit_extension_mcp_test.dart`

`team_cubit` gains an injected `ExtensionMcpContributor` = `Future<List<McpServer>> Function(String teamId)` (default: build from an `ExtensionRepository` + an `ExtensionProvisioner` with team-effective enablement). `_syncMcpForSelected` merges its output into the catalog + id list passed to `syncForTeam`, de-duped by id.

- [ ] **Step 1: Read the team_cubit constructor + `_syncMcpForSelected` to anchor edits**

Run: `sed -n '110,180p;448,505p' client/lib/cubits/team_cubit.dart`
Expected: shows the constructor field list (where to add `_extensionMcpContributor`) and the exact `_syncMcpForSelected` body (catalog build → `syncForTeam`). Use these exact anchors for Steps 3–4.

- [ ] **Step 2: Write the failing test**

```dart
// client/test/cubits/team_cubit_extension_mcp_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server.dart';

import 'team_cubit_test_harness.dart'; // see note below

void main() {
  test('extension MCP contribution is written into the team snapshot', () async {
    // Arrange a TeamCubit with: one selected team (no user mcpServerIds), a
    // fake mcpLinker capturing (mcpServerIds, catalog), and an injected
    // extensionMcpContributor returning codegraph.
    final captured = <String, List<McpServer>>{};
    final capturedIds = <String, List<String>>{};

    final cubit = makeTeamCubitForMcpTest(
      onSync: (teamId, ids, catalog) {
        capturedIds[teamId] = ids;
        captured[teamId] = catalog;
      },
      extensionMcpContributor: (teamId) async => [
        const McpServer(
          id: 'ext:codegraph',
          name: 'codegraph',
          server: {'command': 'codegraph', 'args': ['serve', '--mcp']},
        ),
      ],
    );

    await selectFirstTeamAndSyncMcp(cubit); // harness helper

    expect(capturedIds['team-a'], contains('ext:codegraph'));
    expect(
      captured['team-a']!.map((s) => s.id),
      contains('ext:codegraph'),
    );
  });
}
```

> **Harness note:** `TeamCubit` has many constructor dependencies. Before writing this test, inspect the existing `client/test/cubits/team_cubit_test.dart` to copy its construction/fakes pattern (it already fakes `mcpLinker` via the `_installedMcpLoader`/repository seams). Implement `team_cubit_test_harness.dart` (or inline in the test) to construct a `TeamCubit` with: a stub `TeamRepository` returning one team `id: 'team-a'`, an injected `mcpLinker` whose `syncForTeam` records its args and returns `const TeamMcpSyncResult()`, an `installedMcpLoader` returning `[]`, and the new `extensionMcpContributor` param. `selectFirstTeamAndSyncMcp` selects the team (which triggers `_syncMcpForSelected`) — match whatever public method `team_cubit_test.dart` uses to drive selection/sync. If a full harness is impractical, instead write a thinner unit test that calls a new extracted pure helper (see Step 3, `mergeExtensionMcp`).

- [ ] **Step 3: Add the constructor dependency + a pure merge helper**

In `TeamCubit`'s constructor parameter list, add (near `McpRepository? mcpRepository,`):

```dart
    Future<List<McpServer>> Function(String teamId)? extensionMcpContributor,
```

In the initializer list, add:

```dart
       _extensionMcpContributor = extensionMcpContributor ?? _noExtensionMcp,
```

Add the field + default near `final McpRepository _mcpRepository;`:

```dart
  final Future<List<McpServer>> Function(String teamId) _extensionMcpContributor;

  static Future<List<McpServer>> _noExtensionMcp(String teamId) async =>
      const <McpServer>[];
```

Add a top-level pure helper (above the class, or as a `static` on the class) so it is unit-testable:

```dart
  /// Appends extension-contributed servers to [catalog]/[ids], de-duped by id.
  static (List<McpServer>, List<String>) mergeExtensionMcp({
    required List<McpServer> catalog,
    required List<String> ids,
    required List<McpServer> contributions,
  }) {
    final existingIds = catalog.map((s) => s.id).toSet();
    final mergedCatalog = [...catalog];
    final mergedIds = [...ids];
    for (final server in contributions) {
      if (existingIds.add(server.id)) {
        mergedCatalog.add(server);
      }
      if (!mergedIds.contains(server.id)) {
        mergedIds.add(server.id);
      }
    }
    return (mergedCatalog, mergedIds);
  }
```

- [ ] **Step 4: Use the helper in `_syncMcpForSelected`**

In `_syncMcpForSelected`, after the line `final enabled = catalog.where((s) => s.enabled).toList(growable: false);`, insert:

```dart
      final contributions = await _extensionMcpContributor(team.id);
      final (mergedCatalog, mergedIds) = mergeExtensionMcp(
        catalog: enabled,
        ids: team.mcpServerIds,
        contributions: contributions,
      );
```

Then change BOTH `syncForTeam` calls to use the merged lists: replace `mcpServerIds: team.mcpServerIds,` → `mcpServerIds: mergedIds,` and `catalog: enabled,` → `catalog: mergedCatalog,` (first call). For the second call (inside the `skippedMissingIds` prune block), keep its pruning on `team.mcpServerIds` but re-merge: replace its `mcpServerIds: prunedIds,` with a re-merge of `prunedIds` + contribution ids, and `catalog: enabled,` → `catalog: mergedCatalog,`:

```dart
          final (_, prunedMergedIds) = mergeExtensionMcp(
            catalog: enabled,
            ids: prunedIds,
            contributions: contributions,
          );
          result = await _mcpLinker.syncForTeam(
            teamId: team.id,
            mcpServerIds: prunedMergedIds,
            catalog: mergedCatalog,
            layout: layout,
          );
```

> Note: extension contributions use ids prefixed `ext:` and are never user-pruned (they are not in `team.mcpServerIds`), so `skippedMissingIds` will never list them.

- [ ] **Step 5: Run tests**

Run: `flutter test test/cubits/team_cubit_extension_mcp_test.dart test/cubits/team_cubit_test.dart`
Expected: PASS. (If the full-harness MCP test proved impractical in Step 2, ensure at minimum a `mergeExtensionMcp` unit test asserts: contribution id appended to ids; contribution server appended to catalog; duplicate id not double-added.)

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/team_cubit.dart client/test/cubits/team_cubit_extension_mcp_test.dart
git commit -m "feat(extensions): merge extension MCP contributions into team snapshot"
```

---

## Task 7: Default contributor wiring in `app_shell`

**Files:**
- Modify: `client/lib/app/app_shell.dart`

Wire a production `extensionMcpContributor` into `TeamCubit` so codegraph actually flows at runtime once enabled. The contributor builds an `ExtensionRepository` (state.json) + an `ExtensionProvisioner` with team-effective enablement and calls `collectMcpContributions`.

- [ ] **Step 1: Read the TeamCubit construction site**

Run: `grep -n "TeamCubit(\|mcpLinker:\|ExtensionRepository\|AppStorage" client/lib/app/app_shell.dart | head`
Expected: shows where `TeamCubit(...)` is built (near `mcpLinker: TeamMcpLinkerService(),` at ~L341). Use that as the insertion anchor.

- [ ] **Step 2: Add the contributor argument to `TeamCubit(...)`**

Add these imports to `app_shell.dart` (with the other `services/`/`repositories/` imports):

```dart
import '../repositories/extension_repository.dart';
import '../services/extension/builtin_manifests.dart';
import '../services/extension/extension_provisioner.dart';
import '../services/storage/app_storage.dart';
```

In the `TeamCubit(...)` constructor call, add:

```dart
      extensionMcpContributor: (teamId) async {
        final repo = ExtensionRepository(
          fs: AppStorage.fs,
          stateFilePath: AppStorage.paths.extensionsStateJson,
          manifests: builtInExtensionManifests(),
        );
        final enabled = await repo.effectiveEnabledIds(teamId);
        final provisioner = ExtensionProvisioner(
          manifests: builtInExtensionManifests(),
          isEnabled: (id) async => enabled.contains(id),
        );
        return provisioner.collectMcpContributions();
      },
```

> Verify `AppStorage.fs` and `AppStorage.paths` are the accessors used elsewhere in `app_shell.dart`/`McpRepository` (they are — `McpRepository` uses `AppStorage.paths.mcpServersJson`). `ExtensionProvisioner` here omits `hookProvisionerFor` (optional after Task 4) since only `collectMcpContributions` is called.

- [ ] **Step 3: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(extensions): wire codegraph MCP contributor into TeamCubit"
```

---

## Task 8: `ExtensionAcquisitionEngine`

**Files:**
- Create: `client/lib/services/extension/extension_acquisition_engine.dart`
- Test: `client/test/services/extension/extension_acquisition_engine_test.dart`

Installs/uninstalls the underlying tool by mapping `acquire.kind`(+`alternatives`) to a `CliInstallerCommand`, run via an injected runner (`LocalCliInstallRunner`-shaped). On success it re-probes with `ExtensionDetector` to capture the version. Desktop/local only (Phase 2).

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/extension_acquisition_engine_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/extension/extension_acquisition_engine.dart';
import 'package:teampilot/services/extension/extension_detector.dart';

ExtensionManifest _manifest(Map<String, Object?> acquire) =>
    ExtensionManifest.fromJson({
      'id': 'x',
      'name': 'X',
      'acquire': acquire,
      'detect': {'executable': 'x', 'versionArgs': ['--version']},
    });

ExtensionDetector _present(String version) => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'x') {
          return ProcessResult(0, 0, '/usr/bin/x', '');
        }
        if (args.contains('--version')) return ProcessResult(0, 0, 'x $version', '');
        return ProcessResult(0, 1, '', '');
      },
    );

void main() {
  test('node-package runs npm install -g', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.4.0'),
    );

    final result = await engine.install(
      _manifest({'kind': 'node-package', 'package': '@scope/pkg', 'binary': 'x'}),
    );

    expect(commands.single.executable, 'npm');
    expect(commands.single.arguments, ['install', '-g', '@scope/pkg']);
    expect(result.success, isTrue);
    expect(result.version, '1.4.0');
  });

  test('cargo runs cargo install', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('0.24.0'),
    );

    await engine.install(_manifest({'kind': 'cargo', 'package': 'rtk', 'binary': 'rtk'}));

    expect(commands.single.executable, 'cargo');
    expect(commands.single.arguments, ['install', 'rtk']);
  });

  test('falls back to an alternative when primary fails', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        // cargo fails, brew succeeds
        return CliInstallerCommandResult(exitCode: cmd.executable == 'cargo' ? 1 : 0);
      },
      detector: _present('0.24.0'),
    );

    final result = await engine.install(_manifest({
      'kind': 'cargo',
      'package': 'rtk',
      'binary': 'rtk',
      'alternatives': ['brew:rtk'],
    }));

    expect(commands.map((c) => c.executable), ['cargo', 'brew']);
    expect(commands.last.arguments, ['install', 'rtk']);
    expect(result.success, isTrue);
  });

  test('fails when all commands fail', () async {
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async => const CliInstallerCommandResult(exitCode: 1, stderr: 'nope'),
      detector: _present('1.0.0'),
    );
    final result = await engine.install(_manifest({'kind': 'cargo', 'package': 'rtk'}));
    expect(result.success, isFalse);
    expect(result.message, contains('nope'));
  });

  test('fails cleanly when acquire is none/absent', () async {
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async => const CliInstallerCommandResult(exitCode: 0),
      detector: _present('1.0.0'),
    );
    final result = await engine.install(ExtensionManifest.fromJson({
      'id': 'x',
      'name': 'X',
      'detect': {'executable': 'x'},
    }));
    expect(result.success, isFalse);
  });

  test('uninstall runs the kind-appropriate command', () async {
    final commands = <CliInstallerCommand>[];
    final engine = ExtensionAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        return const CliInstallerCommandResult(exitCode: 0);
      },
      detector: _present('1.0.0'),
    );
    await engine.uninstall(
      _manifest({'kind': 'node-package', 'package': '@scope/pkg', 'binary': 'x'}),
    );
    expect(commands.single.executable, 'npm');
    expect(commands.single.arguments, ['uninstall', '-g', '@scope/pkg']);
  });
}
```

> **Type check:** before Step 1 confirm `CliInstallerCommandResult` has a `const` constructor with named `exitCode`/`stderr`/`stdout` (grep `installer_types.dart`). Phase-2 research confirmed `CliInstallerCommand(this.executable, this.arguments)` and `CliInstallerCommandResult{exitCode,stdout,stderr}` exist; if `CliInstallerCommandResult` lacks `const`/defaults, construct it with the fields it requires.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/extension_acquisition_engine_test.dart`
Expected: FAIL — "ExtensionAcquisitionEngine isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/extension/extension_acquisition_engine.dart
import '../../models/extension_manifest.dart';
import '../cli/installer_types.dart';
import 'extension_detector.dart';

typedef ExtensionInstallRunner = Future<CliInstallerCommandResult> Function(
  CliInstallerCommand command,
);

class ExtensionInstallResult {
  const ExtensionInstallResult({
    required this.success,
    this.message = '',
    this.version,
  });

  final bool success;
  final String message;
  final String? version;
}

/// Installs/uninstalls an extension's underlying tool on the local host by
/// mapping `acquire.kind`(+`alternatives`) to a shell command. Desktop/local
/// only in Phase 2 (no SSH/remote).
class ExtensionAcquisitionEngine {
  ExtensionAcquisitionEngine({
    required ExtensionInstallRunner runner,
    ExtensionDetector? detector,
  })  : _runner = runner,
        _detector = detector ?? ExtensionDetector();

  final ExtensionInstallRunner _runner;
  final ExtensionDetector _detector;

  Future<ExtensionInstallResult> install(ExtensionManifest manifest) async {
    final acquire = manifest.acquire;
    if (acquire == null || acquire.kind == 'none') {
      return const ExtensionInstallResult(
        success: false,
        message: 'No installer is defined for this extension.',
      );
    }

    final commands = _installCommands(acquire);
    if (commands.isEmpty) {
      return const ExtensionInstallResult(
        success: false,
        message: 'No installable target for this extension.',
      );
    }

    CliInstallerCommandResult? last;
    for (final command in commands) {
      last = await _runner(command);
      if (last.exitCode == 0) {
        final probe = await _detector.probe(manifest.detect);
        return ExtensionInstallResult(
          success: probe.found,
          version: probe.version,
          message: probe.found
              ? 'Installed.'
              : 'Install command succeeded but the tool was not found on PATH.',
        );
      }
    }
    return ExtensionInstallResult(
      success: false,
      message: last?.stderr.trim().isNotEmpty == true
          ? last!.stderr.trim()
          : 'Installation failed.',
    );
  }

  Future<ExtensionInstallResult> uninstall(ExtensionManifest manifest) async {
    final acquire = manifest.acquire;
    if (acquire == null) {
      return const ExtensionInstallResult(success: false, message: 'No installer.');
    }
    final command = _uninstallCommand(acquire);
    if (command == null) {
      return const ExtensionInstallResult(
        success: false,
        message: 'Uninstall is not supported for this install kind.',
      );
    }
    final result = await _runner(command);
    return ExtensionInstallResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'Uninstalled.' : result.stderr.trim(),
    );
  }

  /// Primary command for [acquire], then one per `alternatives` entry
  /// (`"<kind>:<arg>"`).
  List<CliInstallerCommand> _installCommands(ExtensionAcquireSpec acquire) {
    final commands = <CliInstallerCommand>[];
    final primary = _commandForKind(acquire.kind, acquire.package);
    if (primary != null) commands.add(primary);
    for (final alt in acquire.alternatives) {
      final idx = alt.indexOf(':');
      if (idx <= 0) continue;
      final kind = alt.substring(0, idx);
      final arg = alt.substring(idx + 1);
      final cmd = _commandForKind(kind, arg);
      if (cmd != null) commands.add(cmd);
    }
    return commands;
  }

  CliInstallerCommand? _commandForKind(String kind, String? arg) {
    final target = arg?.trim() ?? '';
    if (target.isEmpty && kind != 'none') return null;
    switch (kind) {
      case 'node-package':
        return CliInstallerCommand('npm', ['install', '-g', target]);
      case 'cargo':
        return CliInstallerCommand('cargo', ['install', target]);
      case 'brew':
        return CliInstallerCommand('brew', ['install', target]);
      case 'script':
        return CliInstallerCommand('sh', ['-c', 'curl -fsSL "$target" | sh']);
      default:
        return null;
    }
  }

  CliInstallerCommand? _uninstallCommand(ExtensionAcquireSpec acquire) {
    final target = acquire.package?.trim() ?? '';
    if (target.isEmpty) return null;
    switch (acquire.kind) {
      case 'node-package':
        return CliInstallerCommand('npm', ['uninstall', '-g', target]);
      case 'cargo':
        return CliInstallerCommand('cargo', ['uninstall', target]);
      case 'brew':
        return CliInstallerCommand('brew', ['uninstall', target]);
      default:
        return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/extension_acquisition_engine_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/extension_acquisition_engine.dart client/test/services/extension/extension_acquisition_engine_test.dart
git commit -m "feat(extensions): add ExtensionAcquisitionEngine (local install/uninstall)"
```

---

## Task 9: Full verification gate

**Files:** none (verification only).

- [ ] **Step 1: Static analysis (whole project)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: "No issues found!" (or only pre-existing infos unrelated to the Phase-2 files). Fix any new error/warning.

- [ ] **Step 2: Full test suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all pass (Phase-1's 685 + the new Phase-2 tests). Investigate any failure introduced by Phase 2.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A && git commit -m "chore(extensions): phase 2 verification fixups" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage (Phase 2 slice of `2026-06-01-extension-system-design.md`):**

| Spec element (Phase 2 scope) | Task |
|------------------------------|------|
| `mcp-server` effect kind (§5.2) | Tasks 4, 5 |
| Extension-contributed MCP merged into team `servers.json` via `TeamMcpLinkerService`, de-duped by configKey/id (§5.2, §6.3, §13 open-question) | Task 6 (merge at the `team_cubit` call site → `TeamMcpLinkerService` unchanged) |
| codegraph built-in manifest; CLI spawns `codegraph serve --mcp` itself (§5.1, §8) | Task 5 (+ Task 4 contribution shape) |
| `AcquisitionEngine` reusing installer types; `node-package`/`cargo`/`brew`/`script` + `alternatives` (§6.1) | Task 8 |
| `state.json` + `ExtensionRepository`; global default + per-team override (§5.3, §7) — pulled forward from Phase 3 because codegraph needs an enablement source | Tasks 1, 2, 3 |
| Runtime wiring so an enabled+installed codegraph reaches the agent (§8) | Task 7 |
| Tests per new unit (§11) | Tasks 1–8 |
| Verification gate (§11) | Task 9 |

Deferred to Phase 3 (per phase boundary): visual `/extensions` page + install/enable/override UI, migrating the rtk settings-hook path onto `ExtensionRepository`, per-team override of the settings-hook effect (delegate change), `ExtensionCubit`, SSH/remote install. §13 open-question on the MCP merge interface is **resolved** (merge at the `team_cubit` seam, not by changing `TeamMcpLinkerService`).

**2. Placeholder scan:** No "TBD/TODO/implement later". Every code step has full code; every run step has the command + expected result. The three `> ...check` callouts (in-memory FS path, Filesystem API names, `CliInstallerCommandResult` shape) and the Task-6 harness note are read-then-adapt guards with concrete fallbacks — not deferred work. Task 6 explicitly provides a thinner `mergeExtensionMcp` unit-test fallback if the full cubit harness is impractical, so the task always lands testable code.

**3. Type consistency check (cross-task):**
- `ExtensionState` / `InstalledExtension` (Task 1) — used by `ExtensionRepository` (Task 3) with matching constructors (`ExtensionState({installed, globalEnabled, teamOverrides})`, `InstalledExtension({id, version, installedAt})`) and methods (`effectiveEnabled`, `withGlobalEnabled`, `withTeamOverride`, `withInstalled`, `withUninstalled`).
- `ExtensionRepository({fs, stateFilePath, manifests})` + `effectiveEnabledIds(teamId)` / `setGlobalEnabled` / `recordInstalled` — defined Task 3, consumed in Task 7.
- `ExtensionEffect.mcpServer` / `mcpName` (Task 4 model edit) — consumed by `collectMcpContributions` (Task 4) and asserted in Task 5's test.
- `ExtensionProvisioner` `hookProvisionerFor` made optional (Task 4) — relied on by Task 7's hook-less construction; Phase-1 `applySettings` callers still pass it.
- `collectMcpContributions()` → `List<McpServer>` with `id: 'ext:<id>'` — Task 4, merged in Task 6, contributor returns it in Task 7. `mergeExtensionMcp({catalog, ids, contributions})` signature consistent Task 6 Steps 3–4.
- `ExtensionAcquisitionEngine({runner, detector})`, `ExtensionInstallResult{success, message, version}`, `ExtensionInstallRunner = Future<CliInstallerCommandResult> Function(CliInstallerCommand)` — Task 8, self-consistent with the real `installer_types.dart`.
- `AppPaths.extensionsStateJson` (Task 2) — consumed in Task 7.

No inconsistencies found.
