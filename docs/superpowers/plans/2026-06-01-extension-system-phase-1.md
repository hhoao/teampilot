# Extension System — Phase 1 (Foundation + rtk migration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace rtk's bespoke detection + settings-hook merge with a generic, manifest-driven extension engine, preserving today's rtk behavior exactly.

**Architecture:** A declarative `ExtensionManifest` (identity + detect spec + effects) drives a generic `ExtensionDetector` (absorbs `RtkDetector`) and a `SettingsHookEffectApplier` (absorbs `RtkSettingsMerge`), orchestrated by an `ExtensionProvisioner`. `ConfigProfileService` keeps its existing `ConfigProfileDelegate` methods (`isRtkEnabled` / `maybeApplyRtk`) and the `rtk_enabled_*` warning behavior, but re-implements their bodies on top of the engine. This is a strangler refactor: no UI, no acquisition, no MCP effect yet (those are Phases 2 and 3). rtk's enablement source stays `AppSettingsRepository.loadRtkEnabled()`, adapted into the engine as `isEnabled('rtk')`.

**Tech Stack:** Dart / Flutter, `flutter_bloc` (not touched this phase), `package:test` + `flutter_test`, existing `Filesystem` / `HostExecutionEnvironment` / `ScriptFileHookProvisioner` infrastructure.

**Phase boundary (what is explicitly NOT in Phase 1):**
- `extensions/state.json`, `ExtensionRepository`, `ExtensionCubit` → Phase 3 (with UI).
- `mcp-server` effect, `AcquisitionEngine`, codegraph manifest → Phase 2.
- `/extensions` page, `team_config_page` overrides, moving rtk probe UI out of `config_workspace.dart` → Phase 3.
- The `ConfigProfileDelegate.isRtkEnabled` / `maybeApplyRtk` method *names* stay (renaming them is Phase 3 cleanup). Built-in manifests are an embedded JSON string this phase (externalizing to `assets/extensions/*.json` is Phase 2/3).

**One intentional behavior change:** the warning code `rtk_enabled_jq_missing` becomes the generic `rtk_enabled_dependency_missing`. This code is **never matched on** — it flows `prepareTeamLaunch` → `SessionLifecycleService` → `chat_cubit` → `chat_page.dart`, where the snackbar shows the raw code verbatim for every non-`claude_credentials_missing` warning. So the literal is user-visible but the rename is safe (no `switch`/equality consumer). Tests that assert the old string are updated.

> **Implementation status (added 2026-06-01, post code-review):** Phase 1 was implemented in this session and verified independently — `flutter analyze` clean on the touched files and the **full suite (685 tests) passes**. Three places where the as-written tasks below needed correction (already reflected in the landed code):
> 1. **`client/lib/pages/config_workspace.dart`** also imported the deleted `RtkDetector`/`RtkProbeResult` (its rtk probe UI). Phase 1 **must** rewire it to `ExtensionDetector`/`ExtensionProbe` (`jqFound`→`missingRequirements.contains('jq')`, `isVersionSupported`→`satisfiesMinVersion`) or it won't compile. This file is a Phase-1 modified file (Task 7), not deferred to Phase 3 — only the *widget relocation* is Phase 3.
> 2. **Task 6 test scaffold:** `HostScriptRunner` is a `final class` (cannot be `implements`-ed/`extends`-ed). The test constructs a real `HostScriptRunner(HostExecutionEnvironment.resolve(...))` instead of a stub.
> 3. **Task 6 fake filesystem:** the in-memory `Filesystem` is `InMemoryFilesystem` from `client/test/support/in_memory_filesystem.dart` (not `MemoryFilesystem` under `lib/services/io/`).

---

## File Structure

**New files:**

| File | Responsibility |
|------|----------------|
| `client/lib/models/extension_manifest.dart` | `ExtensionManifest` + `ExtensionDetectSpec` + `ExtensionEffect` + `ExtensionAcquireSpec` value types with `fromJson`. Pure data, no I/O. |
| `client/lib/services/extension/extension_probe.dart` | `ExtensionProbe` result type (`found` / `version` / `satisfiesMinVersion` / `missingRequirements` / `isReady`). |
| `client/lib/services/extension/extension_detector.dart` | Generic host probe driven by an `ExtensionDetectSpec`. Absorbs `RtkDetector`. |
| `client/lib/services/extension/effect/settings_hook_effect_applier.dart` | Idempotent merge of a `{event, matcher, command}` hook into Claude-style settings, keyed by a marker. Absorbs `RtkSettingsMerge`. |
| `client/lib/services/extension/extension_provisioner.dart` | Orchestrates enabled manifests: collects warnings + applies settings-hook effects. The seam `ConfigProfileService` calls. |
| `client/lib/services/extension/builtin_manifests.dart` | The rtk manifest (embedded JSON) + `builtInExtensionManifests()` parser. |

**Modified files:**

| File | Change |
|------|--------|
| `client/lib/services/provider/config_profile_service.dart` | Drop `RtkDetector`/`RtkSettingsMerge` usage; build an `ExtensionProvisioner`; re-implement `_collectRtkWarnings` + `_maybeApplyRtk` through it; update the 3 `rtkWarning*` constants. |

**Deleted files:**

| File | Reason |
|------|--------|
| `client/lib/services/team/rtk_detector.dart` | Absorbed by `ExtensionDetector`. |
| `client/lib/services/team/rtk_settings_merge.dart` | Absorbed by `SettingsHookEffectApplier`. |
| `client/test/services/team/rtk_detector_test.dart` | Replaced by `extension_detector_test.dart`. |
| `client/test/services/team/rtk_settings_merge_test.dart` | Replaced by `settings_hook_effect_applier_test.dart`. |

**New test files:**

- `client/test/models/extension_manifest_test.dart`
- `client/test/services/extension/extension_detector_test.dart`
- `client/test/services/extension/settings_hook_effect_applier_test.dart`
- `client/test/services/extension/builtin_manifests_test.dart`
- `client/test/services/extension/extension_provisioner_test.dart`

**Existing test updated:** `client/test/services/provider/config_profile_service_rtk_test.dart`.

> All commands below run from the `client/` directory unless noted.

---

## Task 1: Extension manifest model

**Files:**
- Create: `client/lib/models/extension_manifest.dart`
- Test: `client/test/models/extension_manifest_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/extension_manifest_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';

void main() {
  group('ExtensionManifest.fromJson', () {
    test('parses identity, detect, and a settings-hook effect', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'rtk',
        'name': 'RTK (Rust Token Killer)',
        'version': '0.x',
        'homepage': 'https://github.com/rtk-ai/rtk',
        'detect': {
          'executable': 'rtk',
          'versionArgs': ['--version'],
          'minVersion': '0.23.0',
          'requires': ['jq'],
        },
        'effects': [
          {
            'kind': 'settings-hook',
            'appliesTo': ['claude', 'flashskyai'],
            'event': 'PreToolUse',
            'matcher': 'Bash',
            'scriptAsset': 'rtk-rewrite',
            'marker': 'rtk-rewrite',
          },
        ],
      });

      expect(manifest.id, 'rtk');
      expect(manifest.name, 'RTK (Rust Token Killer)');
      expect(manifest.detect.executable, 'rtk');
      expect(manifest.detect.versionArgs, ['--version']);
      expect(manifest.detect.minVersion, '0.23.0');
      expect(manifest.detect.requires, ['jq']);

      expect(manifest.effects, hasLength(1));
      final effect = manifest.effects.single;
      expect(effect.kind, 'settings-hook');
      expect(effect.appliesTo, ['claude', 'flashskyai']);
      expect(effect.hookEvent, 'PreToolUse');
      expect(effect.hookMatcher, 'Bash');
      expect(effect.scriptAsset, 'rtk-rewrite');
      expect(effect.marker, 'rtk-rewrite');
    });

    test('applies defaults when optional fields are missing', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'x',
        'name': 'X',
        'detect': {'executable': 'x'},
      });

      expect(manifest.version, '');
      expect(manifest.detect.versionArgs, ['--version']);
      expect(manifest.detect.minVersion, isNull);
      expect(manifest.detect.requires, isEmpty);
      expect(manifest.effects, isEmpty);
      expect(manifest.acquire, isNull);
    });

    test('parses acquire spec when present', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'rtk',
        'name': 'RTK',
        'acquire': {
          'kind': 'cargo',
          'package': 'rtk',
          'binary': 'rtk',
          'alternatives': ['brew:rtk'],
        },
        'detect': {'executable': 'rtk'},
      });

      expect(manifest.acquire, isNotNull);
      expect(manifest.acquire!.kind, 'cargo');
      expect(manifest.acquire!.package, 'rtk');
      expect(manifest.acquire!.alternatives, ['brew:rtk']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/extension_manifest_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot' ... extension_manifest.dart` / "ExtensionManifest isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/models/extension_manifest.dart

/// Declarative description of an external extension (e.g. rtk, codegraph).
///
/// Phase 1 only consumes [detect] and `settings-hook` [effects]; [acquire]
/// is parsed for forward-compatibility (used from Phase 2 onward).
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    this.version = '',
    this.homepage = '',
    this.acquire,
    required this.detect,
    this.effects = const [],
  });

  final String id;
  final String name;
  final String version;
  final String homepage;
  final ExtensionAcquireSpec? acquire;
  final ExtensionDetectSpec detect;
  final List<ExtensionEffect> effects;

  factory ExtensionManifest.fromJson(Map<String, Object?> json) {
    final detectRaw = json['detect'];
    final acquireRaw = json['acquire'];
    final effectsRaw = json['effects'];
    return ExtensionManifest(
      id: (json['id'] as String?)?.trim() ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      homepage: json['homepage'] as String? ?? '',
      acquire: acquireRaw is Map
          ? ExtensionAcquireSpec.fromJson(acquireRaw.cast<String, Object?>())
          : null,
      detect: detectRaw is Map
          ? ExtensionDetectSpec.fromJson(detectRaw.cast<String, Object?>())
          : const ExtensionDetectSpec(executable: ''),
      effects: effectsRaw is List
          ? effectsRaw
              .whereType<Map>()
              .map((e) => ExtensionEffect.fromJson(e.cast<String, Object?>()))
              .toList()
          : const [],
    );
  }
}

/// How to verify the underlying tool is present and usable on the host.
class ExtensionDetectSpec {
  const ExtensionDetectSpec({
    required this.executable,
    this.versionArgs = const ['--version'],
    this.minVersion,
    this.requires = const [],
  });

  final String executable;
  final List<String> versionArgs;
  final String? minVersion;

  /// Companion binaries that must also be on PATH (e.g. rtk requires `jq`).
  final List<String> requires;

  factory ExtensionDetectSpec.fromJson(Map<String, Object?> json) {
    final versionArgs = json['versionArgs'];
    final requires = json['requires'];
    return ExtensionDetectSpec(
      executable: (json['executable'] as String?)?.trim() ?? '',
      versionArgs: versionArgs is List
          ? versionArgs.map((e) => e.toString()).toList()
          : const ['--version'],
      minVersion: (json['minVersion'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['minVersion'] as String).trim(),
      requires: requires is List
          ? requires.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
    );
  }
}

/// One way the extension wires into an agent CLI's config profile.
///
/// [config] holds the full effect map; kind-specific getters read it.
class ExtensionEffect {
  const ExtensionEffect({
    required this.kind,
    this.appliesTo = const [],
    this.config = const {},
  });

  final String kind;
  final List<String> appliesTo;
  final Map<String, Object?> config;

  // settings-hook accessors (Phase 1).
  String? get hookEvent => config['event'] as String?;
  String? get hookMatcher => config['matcher'] as String?;
  String? get scriptAsset => config['scriptAsset'] as String?;
  String? get marker => config['marker'] as String?;

  factory ExtensionEffect.fromJson(Map<String, Object?> json) {
    final appliesTo = json['appliesTo'];
    return ExtensionEffect(
      kind: (json['kind'] as String?)?.trim() ?? '',
      appliesTo: appliesTo is List
          ? appliesTo.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      config: Map<String, Object?>.from(json),
    );
  }
}

/// How to install the underlying tool. Parsed in Phase 1, consumed from Phase 2.
class ExtensionAcquireSpec {
  const ExtensionAcquireSpec({
    required this.kind,
    this.package,
    this.binary,
    this.allowNpx = false,
    this.alternatives = const [],
  });

  final String kind;
  final String? package;
  final String? binary;
  final bool allowNpx;
  final List<String> alternatives;

  factory ExtensionAcquireSpec.fromJson(Map<String, Object?> json) {
    final alternatives = json['alternatives'];
    return ExtensionAcquireSpec(
      kind: (json['kind'] as String?)?.trim() ?? 'none',
      package: json['package'] as String?,
      binary: json['binary'] as String?,
      allowNpx: json['allowNpx'] as bool? ?? false,
      alternatives: alternatives is List
          ? alternatives.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/extension_manifest_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/extension_manifest.dart client/test/models/extension_manifest_test.dart
git commit -m "feat(extensions): add ExtensionManifest model"
```

---

## Task 2: Extension probe result type

**Files:**
- Create: `client/lib/services/extension/extension_probe.dart`
- Test: covered indirectly by Task 3 (`extension_detector_test.dart`); add a focused unit test for `isReady` here.

- [ ] **Step 1: Write the failing test**

Append to a new file:

```dart
// client/test/services/extension/extension_probe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/extension/extension_probe.dart';

void main() {
  group('ExtensionProbe.isReady', () {
    test('true when found, version OK, and no missing requirements', () {
      const probe = ExtensionProbe(
        found: true,
        version: '0.24.1',
        satisfiesMinVersion: true,
        missingRequirements: [],
      );
      expect(probe.isReady, isTrue);
    });

    test('false when a requirement is missing', () {
      const probe = ExtensionProbe(found: true, missingRequirements: ['jq']);
      expect(probe.isReady, isFalse);
    });

    test('false when version too old', () {
      const probe = ExtensionProbe(found: true, satisfiesMinVersion: false);
      expect(probe.isReady, isFalse);
    });

    test('false when not found', () {
      const probe = ExtensionProbe(found: false);
      expect(probe.isReady, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/extension_probe_test.dart`
Expected: FAIL — "ExtensionProbe isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/extension/extension_probe.dart

/// Result of probing the host for an extension's underlying tool.
class ExtensionProbe {
  const ExtensionProbe({
    required this.found,
    this.executablePath,
    this.version,
    this.satisfiesMinVersion = true,
    this.missingRequirements = const [],
  });

  final bool found;
  final String? executablePath;
  final String? version;
  final bool satisfiesMinVersion;
  final List<String> missingRequirements;

  bool get isReady =>
      found && satisfiesMinVersion && missingRequirements.isEmpty;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/extension_probe_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/extension_probe.dart client/test/services/extension/extension_probe_test.dart
git commit -m "feat(extensions): add ExtensionProbe result type"
```

---

## Task 3: Generic extension detector (absorbs RtkDetector)

**Files:**
- Create: `client/lib/services/extension/extension_detector.dart`
- Test: `client/test/services/extension/extension_detector_test.dart` (ports cases from `rtk_detector_test.dart`)

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/extension_detector_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/extension/extension_detector.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail() => ProcessResult(0, 1, '', 'not found');

void main() {
  const rtkDetect = ExtensionDetectSpec(
    executable: 'rtk',
    versionArgs: ['--version'],
    minVersion: '0.23.0',
    requires: ['jq'],
  );

  test('found with version and jq present is ready', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );

    final probe = await detector.probe(rtkDetect);

    expect(probe.found, isTrue);
    expect(probe.executablePath, '/usr/bin/rtk');
    expect(probe.version, '0.24.1');
    expect(probe.satisfiesMinVersion, isTrue);
    expect(probe.missingRequirements, isEmpty);
    expect(probe.isReady, isTrue);
  });

  test('not found returns found=false', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.found, isFalse);
    expect(probe.isReady, isFalse);
  });

  test('missing requirement is reported', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _fail();
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.found, isTrue);
    expect(probe.missingRequirements, ['jq']);
    expect(probe.isReady, isFalse);
  });

  test('version below minVersion fails satisfiesMinVersion', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk 0.22.9');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.version, '0.22.9');
    expect(probe.satisfiesMinVersion, isFalse);
    expect(probe.isReady, isFalse);
  });

  test('unparseable version is treated as satisfying (no false alarm)', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk dev-build');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.version, isNull);
    expect(probe.satisfiesMinVersion, isTrue);
  });

  test('major version >= 1 always satisfies 0.23.0', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _ok('/usr/bin/jq');
        if (args.contains('--version')) return _ok('rtk 1.0.0');
        return _fail();
      },
    );
    final probe = await detector.probe(rtkDetect);
    expect(probe.satisfiesMinVersion, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/extension_detector_test.dart`
Expected: FAIL — "ExtensionDetector isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/extension/extension_detector.dart
import 'dart:io';

import '../../models/extension_manifest.dart';
import '../host/host_executable_locator.dart';
import '../host/host_execution_environment.dart';
import '../storage/runtime_storage_context.dart';
import 'extension_probe.dart';

typedef ExtensionProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// Probes the host for an extension's tool + companion binaries, parameterized
/// by an [ExtensionDetectSpec]. Generalizes the former `RtkDetector`.
class ExtensionDetector {
  ExtensionDetector({ExtensionProcessRunner? processRunner, bool? probeHost})
      : _processRunner = processRunner ?? Process.run,
        _probeHost = probeHost ??
            (processRunner != null ||
                Platform.environment['FLUTTER_TEST'] != 'true');

  final ExtensionProcessRunner _processRunner;
  final bool _probeHost;

  static final _versionPattern = RegExp(r'(\d+)\.(\d+)\.(\d+)');

  Future<ExtensionProbe> probe(
    ExtensionDetectSpec spec, {
    Map<String, String>? environment,
  }) async {
    // Widget tests use fake async; default [Process.run] leaves pending timers.
    if (!_probeHost) return const ExtensionProbe(found: false);

    final locator = _pathLocator();
    final exePath = await _resolveExecutable(
      locator.whichCommand,
      spec.executable,
      environment,
    );
    if (exePath == null) return const ExtensionProbe(found: false);

    final missing = <String>[];
    for (final dep in spec.requires) {
      final depPath =
          await _resolveExecutable(locator.whichCommand, dep, environment);
      if (depPath == null) missing.add(dep);
    }

    String? version;
    try {
      final result = await _processRunner(
        exePath,
        spec.versionArgs,
        environment: environment,
      );
      if (result.exitCode == 0) {
        version = _parseVersion(result.stdout.toString());
      }
    } on Object {
      version = null;
    }

    final satisfies = spec.minVersion == null ||
        version == null ||
        _meetsMinVersion(version, spec.minVersion!);

    return ExtensionProbe(
      found: true,
      executablePath: exePath,
      version: version,
      satisfiesMinVersion: satisfies,
      missingRequirements: missing,
    );
  }

  String? _parseVersion(String raw) {
    final match = _versionPattern.firstMatch(raw);
    if (match == null) return null;
    return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
  }

  bool _meetsMinVersion(String version, String minVersion) {
    final v = _versionTriple(version);
    final min = _versionTriple(minVersion);
    if (v == null || min == null) return true;
    for (var i = 0; i < 3; i++) {
      if (v[i] != min[i]) return v[i] > min[i];
    }
    return true;
  }

  List<int>? _versionTriple(String raw) {
    final match = _versionPattern.firstMatch(raw.trim());
    if (match == null) return null;
    return [
      int.tryParse(match.group(1) ?? '') ?? 0,
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
    ];
  }

  HostExecutableLocator _pathLocator() {
    final env = RuntimeStorageContext.isInstalled
        ? HostExecutionEnvironment.fromStorage(RuntimeStorageContext.current)
        : HostExecutionEnvironment.resolve();
    return HostExecutableLocator(env);
  }

  Future<String?> _resolveExecutable(
    String locator,
    String name,
    Map<String, String>? environment,
  ) async {
    try {
      final result = await _processRunner(
        locator,
        [name],
        environment: environment,
      );
      if (result.exitCode != 0) return null;
      final line =
          result.stdout.toString().trim().split(RegExp(r'\r?\n')).first;
      return line.isEmpty ? null : line;
    } on Object {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/extension_detector_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/extension_detector.dart client/test/services/extension/extension_detector_test.dart
git commit -m "feat(extensions): add generic ExtensionDetector"
```

---

## Task 4: Settings-hook effect applier (absorbs RtkSettingsMerge)

**Files:**
- Create: `client/lib/services/extension/effect/settings_hook_effect_applier.dart`
- Test: `client/test/services/extension/settings_hook_effect_applier_test.dart` (ports `rtk_settings_merge_test.dart`)

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/settings_hook_effect_applier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/extension/effect/settings_hook_effect_applier.dart';

void main() {
  const applier = SettingsHookEffectApplier();

  Map<String, Object?> merge(Map<String, Object?> base) => applier.mergeIntoSettings(
        base: base,
        event: 'PreToolUse',
        matcher: 'Bash',
        hookCommand: 'bash /path/rtk-rewrite.sh',
        marker: 'rtk-rewrite',
      );

  test('inserts a PreToolUse/Bash hook when none exists', () {
    final result = merge({});
    final hooks = result['hooks'] as Map<String, Object?>;
    final pre = hooks['PreToolUse'] as List;
    expect(pre, hasLength(1));
    final entry = pre.single as Map;
    expect(entry['matcher'], 'Bash');
    final inner = entry['hooks'] as List;
    expect((inner.single as Map)['command'], 'bash /path/rtk-rewrite.sh');
  });

  test('is idempotent — does not double-insert when marker present', () {
    final once = merge({});
    final twice = merge(once);
    final hooks = twice['hooks'] as Map<String, Object?>;
    expect((hooks['PreToolUse'] as List), hasLength(1));
  });

  test('prepends without dropping existing PreToolUse entries', () {
    final base = {
      'hooks': {
        'PreToolUse': [
          {
            'matcher': 'Edit',
            'hooks': [
              {'type': 'command', 'command': 'echo keep'},
            ],
          },
        ],
      },
    };
    final result = merge(base);
    final pre = (result['hooks'] as Map)['PreToolUse'] as List;
    expect(pre, hasLength(2));
    expect((pre.first as Map)['matcher'], 'Bash');
    expect((pre.last as Map)['matcher'], 'Edit');
  });

  test('preserves unrelated top-level settings keys', () {
    final result = merge({'model': 'sonnet'});
    expect(result['model'], 'sonnet');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/settings_hook_effect_applier_test.dart`
Expected: FAIL — "SettingsHookEffectApplier isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/extension/effect/settings_hook_effect_applier.dart

/// Merges a `{event → [{matcher, hooks:[{type:command, command}]}]}` hook
/// entry into Claude Code-compatible settings, idempotent by [marker].
///
/// Generalizes the former `RtkSettingsMerge` (event/matcher/marker were fixed
/// to `PreToolUse` / `Bash` / `rtk-rewrite`).
class SettingsHookEffectApplier {
  const SettingsHookEffectApplier();

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String event,
    required String matcher,
    required String hookCommand,
    required String marker,
  }) {
    if (_hasMarkedHook(base, event, marker)) return base;

    final fragment = <String, Object?>{
      'matcher': matcher,
      'hooks': [
        {'type': 'command', 'command': hookCommand},
      ],
    };
    final hooks = Map<String, Object?>.from(
      (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existing = List<Object?>.from((hooks[event] as List?) ?? const []);
    hooks[event] = <Object?>[fragment, ...existing];
    return {...base, 'hooks': hooks};
  }

  bool _hasMarkedHook(Map<String, Object?> base, String event, String marker) {
    final entries = (base['hooks'] as Map?)?[event];
    if (entries is! List) return false;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final inner = entry['hooks'];
      if (inner is! List) continue;
      for (final h in inner) {
        if (h is Map) {
          final command = h['command']?.toString() ?? '';
          if (command.contains(marker)) return true;
        }
      }
    }
    return false;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/settings_hook_effect_applier_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/effect/settings_hook_effect_applier.dart client/test/services/extension/settings_hook_effect_applier_test.dart
git commit -m "feat(extensions): add SettingsHookEffectApplier"
```

---

## Task 5: Built-in manifests (rtk)

**Files:**
- Create: `client/lib/services/extension/builtin_manifests.dart`
- Test: `client/test/services/extension/builtin_manifests_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/builtin_manifests_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';

void main() {
  test('built-in manifests include a valid rtk manifest', () {
    final manifests = builtInExtensionManifests();
    final rtk = manifests.firstWhere((m) => m.id == 'rtk');

    expect(rtk.detect.executable, 'rtk');
    expect(rtk.detect.minVersion, '0.23.0');
    expect(rtk.detect.requires, contains('jq'));

    final hook = rtk.effects.firstWhere((e) => e.kind == 'settings-hook');
    expect(hook.hookEvent, 'PreToolUse');
    expect(hook.hookMatcher, 'Bash');
    expect(hook.scriptAsset, 'rtk-rewrite');
    expect(hook.marker, 'rtk-rewrite');
    expect(hook.appliesTo, containsAll(['claude', 'flashskyai']));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/builtin_manifests_test.dart`
Expected: FAIL — "builtInExtensionManifests isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/extension/builtin_manifests.dart
import 'dart:convert';

import '../../models/extension_manifest.dart';

/// rtk manifest, embedded as JSON to exercise the parser and keep the
/// "an extension is data" contract. Externalized to a bundled asset in a
/// later phase.
const String rtkManifestJson = '''
{
  "id": "rtk",
  "name": "RTK (Rust Token Killer)",
  "version": "0.x",
  "homepage": "https://github.com/rtk-ai/rtk",
  "acquire": {
    "kind": "cargo",
    "package": "rtk",
    "binary": "rtk",
    "alternatives": ["brew:rtk"]
  },
  "detect": {
    "executable": "rtk",
    "versionArgs": ["--version"],
    "minVersion": "0.23.0",
    "requires": ["jq"]
  },
  "effects": [
    {
      "kind": "settings-hook",
      "appliesTo": ["claude", "flashskyai"],
      "event": "PreToolUse",
      "matcher": "Bash",
      "scriptAsset": "rtk-rewrite",
      "marker": "rtk-rewrite"
    }
  ]
}
''';

/// All extensions TeamPilot ships with. Phase 1: rtk only.
List<ExtensionManifest> builtInExtensionManifests() => [
      ExtensionManifest.fromJson(
        jsonDecode(rtkManifestJson) as Map<String, Object?>,
      ),
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/builtin_manifests_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/builtin_manifests.dart client/test/services/extension/builtin_manifests_test.dart
git commit -m "feat(extensions): add built-in rtk manifest"
```

---

## Task 6: Extension provisioner (warnings + settings-hook application)

**Files:**
- Create: `client/lib/services/extension/extension_provisioner.dart`
- Test: `client/test/services/extension/extension_provisioner_test.dart`

The provisioner takes a `hookProvisionerFor(scriptAsset)` factory so that asset-specific script loading stays in `ConfigProfileService` (Task 7). Tests inject a fake factory backed by an in-memory `MemoryFilesystem` and a stub `HostScriptRunner`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/extension/extension_provisioner_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/services/extension/extension_detector.dart';
import 'package:teampilot/services/extension/extension_provisioner.dart';
import 'package:teampilot/services/host/host_script_dialect.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/host/script_file_hook_provisioner.dart';
import 'package:teampilot/services/io/memory_filesystem.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail() => ProcessResult(0, 1, '', '');

/// Minimal runner: bash dialect, deterministic file name + command string.
class _StubScriptRunner implements HostScriptRunner {
  @override
  HostScriptDialect get dialect => HostScriptDialect.bash;
  @override
  String hookFileName(String baseFileName) => '$baseFileName.sh';
  @override
  String commandStringForScriptFile(String scriptPath) => 'bash "$scriptPath"';
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExtensionManifest get _rtkManifest => ExtensionManifest.fromJson({
      'id': 'rtk',
      'name': 'RTK',
      'detect': {
        'executable': 'rtk',
        'minVersion': '0.23.0',
        'requires': ['jq'],
      },
      'effects': [
        {
          'kind': 'settings-hook',
          'event': 'PreToolUse',
          'matcher': 'Bash',
          'scriptAsset': 'rtk-rewrite',
          'marker': 'rtk-rewrite',
        },
      ],
    });

ExtensionDetector _detectorAllReady() => ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return _ok('/usr/bin/${args.first}');
        }
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );

ExtensionProvisioner _provisioner({
  required bool enabled,
  required ExtensionDetector detector,
  required MemoryFilesystem fs,
}) {
  return ExtensionProvisioner(
    manifests: [_rtkManifest],
    isEnabled: (id) async => id == 'rtk' && enabled,
    detector: detector,
    hookProvisionerFor: (scriptAsset) => ScriptFileHookProvisioner(
      fs: fs,
      runner: _StubScriptRunner(),
      baseFileName: scriptAsset,
      loadScript: (dialect) async => '#!/usr/bin/env bash\n# $scriptAsset\n',
    ),
  );
}

void main() {
  test('collectWarnings: empty when extension disabled', () async {
    final p = _provisioner(
      enabled: false,
      detector: _detectorAllReady(),
      fs: MemoryFilesystem(),
    );
    expect(await p.collectWarnings(), isEmpty);
  });

  test('collectWarnings: not-found code when binary missing', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: MemoryFilesystem(),
    );
    expect(await p.collectWarnings(), ['rtk_enabled_not_found']);
  });

  test('collectWarnings: dependency-missing code when jq absent', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && args.first == 'rtk') return _ok('/usr/bin/rtk');
        if (args.length == 1 && args.first == 'jq') return _fail();
        if (args.contains('--version')) return _ok('rtk 0.24.1');
        return _fail();
      },
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: MemoryFilesystem(),
    );
    expect(await p.collectWarnings(), ['rtk_enabled_dependency_missing']);
  });

  test('collectWarnings: version-too-old code', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async {
        if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
          return _ok('/usr/bin/${args.first}');
        }
        if (args.contains('--version')) return _ok('rtk 0.22.0');
        return _fail();
      },
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: MemoryFilesystem(),
    );
    expect(await p.collectWarnings(), ['rtk_enabled_version_too_old']);
  });

  test('applySettings: no-op when memberToolDir empty', () async {
    final p = _provisioner(
      enabled: true,
      detector: _detectorAllReady(),
      fs: MemoryFilesystem(),
    );
    expect(await p.applySettings({'model': 'x'}, ''), {'model': 'x'});
  });

  test('applySettings: merges hook when enabled and ready', () async {
    final fs = MemoryFilesystem();
    final p = _provisioner(
      enabled: true,
      detector: _detectorAllReady(),
      fs: fs,
    );
    final result = await p.applySettings({}, '/member/flashskyai');
    final pre = (result['hooks'] as Map)['PreToolUse'] as List;
    expect(pre, hasLength(1));
    final command = ((pre.single as Map)['hooks'] as List).single as Map;
    expect(command['command'], contains('rtk-rewrite.sh'));
  });

  test('applySettings: no-op when not ready', () async {
    final detector = ExtensionDetector(
      processRunner: (exe, args, {environment}) async => _fail(),
    );
    final p = _provisioner(
      enabled: true,
      detector: detector,
      fs: MemoryFilesystem(),
    );
    expect(await p.applySettings({}, '/member/flashskyai'), {});
  });
}
```

> **Note on test infra:** This test assumes `MemoryFilesystem` (in-memory `Filesystem`) and the `HostScriptRunner` interface exist. Before Step 1, verify with `grep -rn "class MemoryFilesystem\|abstract class HostScriptRunner\|class HostScriptRunner" client/lib/services/io client/lib/services/host`. If `MemoryFilesystem` does not exist, substitute the project's existing in-memory/fake `Filesystem` (check `client/test/` helpers for one already used by filesystem tests) and adjust the import. If `HostScriptRunner` is a concrete class rather than an interface, replace `_StubScriptRunner implements HostScriptRunner` with a thin subclass overriding `dialect`, `hookFileName`, and `commandStringForScriptFile`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/extension/extension_provisioner_test.dart`
Expected: FAIL — "ExtensionProvisioner isn't defined".

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/services/extension/extension_provisioner.dart
import '../../models/extension_manifest.dart';
import '../host/script_file_hook_provisioner.dart';
import 'effect/settings_hook_effect_applier.dart';
import 'extension_detector.dart';

/// Builds a hook-script provisioner for a given `scriptAsset`. Supplied by the
/// caller so asset-specific script loading stays out of this generic engine.
typedef HookProvisionerFactory = ScriptFileHookProvisioner Function(
  String scriptAsset,
);

/// Orchestrates enabled extension manifests: surfaces readiness warnings and
/// applies `settings-hook` effects into a settings map. The seam that replaces
/// the former bespoke rtk logic in `ConfigProfileService`.
class ExtensionProvisioner {
  ExtensionProvisioner({
    required List<ExtensionManifest> manifests,
    required Future<bool> Function(String extensionId) isEnabled,
    required HookProvisionerFactory hookProvisionerFor,
    ExtensionDetector? detector,
    SettingsHookEffectApplier settingsHookApplier =
        const SettingsHookEffectApplier(),
  })  : _manifests = manifests,
        _isEnabled = isEnabled,
        _hookProvisionerFor = hookProvisionerFor,
        _detector = detector ?? ExtensionDetector(),
        _settingsHookApplier = settingsHookApplier;

  final List<ExtensionManifest> _manifests;
  final Future<bool> Function(String extensionId) _isEnabled;
  final HookProvisionerFactory _hookProvisionerFor;
  final ExtensionDetector _detector;
  final SettingsHookEffectApplier _settingsHookApplier;

  /// Warning codes for enabled-but-unready extensions, mirroring the legacy
  /// `rtk_enabled_*` shape: `<id>_enabled_not_found`,
  /// `<id>_enabled_dependency_missing`, `<id>_enabled_version_too_old`.
  Future<List<String>> collectWarnings() async {
    final out = <String>[];
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      final probe = await _detector.probe(manifest.detect);
      if (!probe.found) {
        out.add('${manifest.id}_enabled_not_found');
        continue;
      }
      if (probe.missingRequirements.isNotEmpty) {
        out.add('${manifest.id}_enabled_dependency_missing');
        continue;
      }
      if (!probe.satisfiesMinVersion) {
        out.add('${manifest.id}_enabled_version_too_old');
      }
    }
    return out;
  }

  /// Applies every ready, enabled extension's `settings-hook` effects to [base].
  Future<Map<String, Object?>> applySettings(
    Map<String, Object?> base,
    String memberToolDir,
  ) async {
    if (memberToolDir.trim().isEmpty) return base;
    var settings = base;
    for (final manifest in _manifests) {
      if (!await _isEnabled(manifest.id)) continue;
      final probe = await _detector.probe(manifest.detect);
      if (!probe.isReady) continue;
      for (final effect in manifest.effects) {
        if (effect.kind != 'settings-hook') continue;
        final provisioner =
            _hookProvisionerFor(effect.scriptAsset ?? manifest.id);
        final scriptPath = await provisioner.provision(memberToolDir);
        final command = provisioner.commandForPath(scriptPath);
        settings = _settingsHookApplier.mergeIntoSettings(
          base: settings,
          event: effect.hookEvent ?? 'PreToolUse',
          matcher: effect.hookMatcher ?? 'Bash',
          hookCommand: command,
          marker: effect.marker ?? manifest.id,
        );
      }
    }
    return settings;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/extension/extension_provisioner_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/extension/extension_provisioner.dart client/test/services/extension/extension_provisioner_test.dart
git commit -m "feat(extensions): add ExtensionProvisioner orchestrator"
```

---

## Task 7: Wire the engine into ConfigProfileService; delete bespoke rtk code

This is the integration task. `ConfigProfileService` keeps its `loadRtkEnabled`, `rtkHookProvisioner`, and `loadRtkHookScript` constructor params (they build the engine), keeps `_resolveRtkProvisioner` (reused as the `rtk-rewrite` asset provisioner), and keeps the `isRtkEnabled` / `maybeApplyRtk` delegate methods. It drops the `RtkDetector` field/param and the `RtkSettingsMerge` call, routing both through `ExtensionProvisioner`.

**Files:**
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Modify: `client/test/services/provider/config_profile_service_rtk_test.dart`
- Delete: `client/lib/services/team/rtk_detector.dart`, `client/lib/services/team/rtk_settings_merge.dart`, `client/test/services/team/rtk_detector_test.dart`, `client/test/services/team/rtk_settings_merge_test.dart`

- [ ] **Step 1: Read the current rtk test to learn its injection style**

Run: `sed -n '1,80p' client/test/services/provider/config_profile_service_rtk_test.dart`
Expected: shows how the test constructs `ConfigProfileService` (which `loadRtkEnabled` / `rtkDetector` / hook params it injects) and which warning strings / settings shape it asserts. Note the constructor call and assertions — Step 6 rewrites them.

- [ ] **Step 2: Update imports and constructor in `config_profile_service.dart`**

Remove these imports:

```dart
import '../team/rtk_detector.dart';
import '../team/rtk_settings_merge.dart';
```

Add these imports (near the other `services/` imports):

```dart
import '../extension/builtin_manifests.dart';
import '../extension/extension_detector.dart';
import '../extension/extension_provisioner.dart';
import '../../models/extension_manifest.dart';
```

In the constructor parameter list, replace:

```dart
    RtkDetector? rtkDetector,
```

with:

```dart
    ExtensionDetector? extensionDetector,
    List<ExtensionManifest>? extensionManifests,
```

In the initializer list, replace:

```dart
       _rtkDetector = rtkDetector ?? RtkDetector(),
```

with:

```dart
       _extensionDetector = extensionDetector,
       _extensionManifests = extensionManifests,
```

In the field declarations, replace:

```dart
  final RtkDetector _rtkDetector;
```

with:

```dart
  final ExtensionDetector? _extensionDetector;
  final List<ExtensionManifest>? _extensionManifests;
  ExtensionProvisioner? _cachedExtensionProvisioner;
```

- [ ] **Step 3: Add the provisioner factory + asset-provisioner switch**

Add these members to `ConfigProfileService` (place next to `_resolveRtkProvisioner`):

```dart
  ExtensionProvisioner get _extensionProvisioner =>
      _cachedExtensionProvisioner ??= ExtensionProvisioner(
        manifests: _extensionManifests ?? builtInExtensionManifests(),
        isEnabled: (id) async => id == 'rtk' ? await _isRtkEnabled() : false,
        detector: _extensionDetector,
        hookProvisionerFor: _hookProvisionerForAsset,
      );

  ScriptFileHookProvisioner _hookProvisionerForAsset(String scriptAsset) {
    final host = _hostEnvironmentForProvision();
    switch (scriptAsset) {
      case 'rtk-rewrite':
        return _resolveRtkProvisioner(host);
      default:
        throw StateError('No hook provisioner for asset "$scriptAsset"');
    }
  }
```

- [ ] **Step 4: Re-implement `_collectRtkWarnings` and `_maybeApplyRtk` through the engine**

Replace the body of `_collectRtkWarnings` with:

```dart
  Future<void> _collectRtkWarnings(List<String> warnings) async {
    warnings.addAll(await _extensionProvisioner.collectWarnings());
  }
```

Replace the body of `_maybeApplyRtk` with:

```dart
  Future<Map<String, Object?>> _maybeApplyRtk(
    Map<String, Object?> settings,
    String? memberToolDir,
  ) async {
    return _extensionProvisioner.applySettings(
      settings,
      memberToolDir?.trim() ?? '',
    );
  }
```

Update the three warning constants (their value changes only for the dependency one):

```dart
/// [TeamLaunchOutcome.warnings] when an enabled extension is missing deps.
const rtkWarningEnabledNotFound = 'rtk_enabled_not_found';
const rtkWarningEnabledDependencyMissing = 'rtk_enabled_dependency_missing';
const rtkWarningEnabledVersionTooOld = 'rtk_enabled_version_too_old';
```

(Delete the old `rtkWarningEnabledJqMissing` constant. Grep confirmed it has no consumers in `lib/`; the test in Step 6 is updated to the new name.)

- [ ] **Step 5: Delete the absorbed source + test files**

```bash
git rm client/lib/services/team/rtk_detector.dart \
       client/lib/services/team/rtk_settings_merge.dart \
       client/test/services/team/rtk_detector_test.dart \
       client/test/services/team/rtk_settings_merge_test.dart
```

- [ ] **Step 6: Rewrite `config_profile_service_rtk_test.dart` to inject the engine**

Replace any `rtkDetector: <fake RtkDetector>` injection with an `extensionDetector: ExtensionDetector(processRunner: ...)` stub, and update warning assertions: any `rtk_enabled_jq_missing` → `rtk_enabled_dependency_missing`. Concretely, the construction becomes:

```dart
final service = ConfigProfileService(
  basePath: tempDir.path,
  fs: fs,
  loadRtkEnabled: () async => rtkEnabled, // existing test variable
  extensionDetector: ExtensionDetector(
    processRunner: (exe, args, {environment}) async {
      if (args.length == 1 && (args.first == 'rtk' || args.first == 'jq')) {
        return ProcessResult(0, 0, '/usr/bin/${args.first}', '');
      }
      if (args.contains('--version')) return ProcessResult(0, 0, 'rtk 0.24.1', '');
      return ProcessResult(0, 1, '', '');
    },
  ),
  // keep the test's existing loadRtkHookScript / rtkHookProvisioner injection
);
```

Adjust the per-scenario `processRunner` to drive each existing assertion (binary missing → `not_found`; jq missing → `dependency_missing`; old version → `version_too_old`; all present → settings contains the hook). Keep every other assertion (settings.json hook shape, idempotency) unchanged — behavior is identical.

> If the existing test imports `package:teampilot/services/team/rtk_detector.dart`, replace it with `package:teampilot/services/extension/extension_detector.dart` and `import 'dart:io';` for `ProcessResult`.

- [ ] **Step 7: Run the affected tests**

Run: `flutter test test/services/provider/config_profile_service_rtk_test.dart test/services/provider/config_profile_service_test.dart test/services/cli/config_profile/flashskyai_config_profile_capability_test.dart`
Expected: PASS. (The capability test exercises `delegate.isRtkEnabled()` / `maybeApplyRtk()`, whose names and contracts are unchanged.)

- [ ] **Step 8: Verify no dangling references to the deleted symbols**

Run: `grep -rn "RtkDetector\|RtkSettingsMerge\|RtkProbeResult\|rtkWarningEnabledJqMissing\|services/team/rtk_detector\|services/team/rtk_settings_merge" client/lib client/test`
Expected: **no output**. If anything prints, update that reference (most likely a stray import) and re-run.

- [ ] **Step 9: Commit**

```bash
git add client/lib/services/provider/config_profile_service.dart \
        client/test/services/provider/config_profile_service_rtk_test.dart
git commit -m "refactor(extensions): drive rtk via ExtensionProvisioner; remove bespoke rtk code"
```

---

## Task 8: Full verification gate

**Files:** none (verification only).

- [ ] **Step 1: Static analysis**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: "No issues found!" (or only pre-existing infos unrelated to `lib/services/extension/`, `lib/models/extension_manifest.dart`, `lib/services/provider/config_profile_service.dart`). Fix any new error/warning introduced by this phase.

- [ ] **Step 2: Full unit/widget test suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all pass. If a failure is in a file this phase did not touch and reproduces on a clean checkout of `main`, note it as pre-existing; otherwise fix it.

- [ ] **Step 3: Confirm the deletions and new layout landed**

Run: `ls client/lib/services/extension client/lib/services/extension/effect && ls client/lib/services/team/ | grep -i rtk || echo "rtk bespoke removed"`
Expected: the new `extension/` files are listed; the final line prints `rtk bespoke removed`.

- [ ] **Step 4: Commit any analyze/test fixups**

```bash
git add -A
git commit -m "chore(extensions): phase 1 verification fixups" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage (Phase 1 slice of `2026-06-01-extension-system-design.md`):**

| Spec element (Phase 1 scope) | Task |
|------------------------------|------|
| Extension manifest model (§5.1) | Task 1 |
| Detect spec incl. `minVersion` + `requires` (§5.1, §6.2) | Tasks 1, 3 |
| `ExtensionDetector` absorbs `RtkDetector` (§6.2, §10) | Task 3 (+ delete in Task 7) |
| `settings-hook` effect applier absorbs `RtkSettingsMerge` (§5.2, §6.3, §10) | Task 4 (+ delete in Task 7) |
| `ExtensionProvisioner` at `prepareTeamLaunch` seam (§6.3) | Tasks 6, 7 |
| rtk shipped as a manifest, not code (§1, §8) | Task 5 |
| Old rtk enable flag preserved → engine enablement (§10 migration) | Task 7 Step 3 (`isEnabled` adapter over `_isRtkEnabled`) |
| Tests: detector / applier / provisioner / manifest round-trip (§11) | Tasks 1–7 |
| Verification gate `analyze` + `test --exclude-tags integration` (§11) | Task 8 |

Deferred-by-design (Phases 2–3, called out in the phase boundary): `mcp-server` effect, `AcquisitionEngine`, codegraph manifest, `state.json` / `ExtensionRepository` / `ExtensionCubit`, `/extensions` UI + team overrides, moving rtk probe UI out of `config_workspace.dart`, externalizing manifests to bundled assets. No Phase 1 task is missing for the Phase 1 scope.

**2. Placeholder scan:** No "TBD/TODO/implement later". Every code step shows full code; every run step shows the exact command + expected result. The two `> Note` callouts (Task 6 test-infra check, Task 7 Step 1 read) are read-then-adapt instructions with concrete fallbacks, not deferred work.

**3. Type consistency check (cross-task):**
- `ExtensionDetectSpec` / `ExtensionEffect` / `ExtensionManifest` / `ExtensionAcquireSpec` — defined Task 1, used identically in Tasks 3, 5, 6, 7.
- `ExtensionProbe` fields (`found`, `version`, `satisfiesMinVersion`, `missingRequirements`, `isReady`) — defined Task 2, consumed identically in Tasks 3, 6.
- `ExtensionDetector.probe(ExtensionDetectSpec, {environment})` → `ExtensionProbe` — Task 3, called the same way in Task 6 and Task 7.
- `SettingsHookEffectApplier.mergeIntoSettings({base, event, matcher, hookCommand, marker})` — Task 4, called the same way in Task 6.
- `ExtensionProvisioner({manifests, isEnabled, hookProvisionerFor, detector, settingsHookApplier})` + `collectWarnings()` / `applySettings(base, memberToolDir)` — Task 6, constructed the same way in Task 7 Step 3.
- `HookProvisionerFactory = ScriptFileHookProvisioner Function(String)` — Task 6, satisfied by `_hookProvisionerForAsset` in Task 7 Step 3.
- Warning codes `rtk_enabled_not_found` / `rtk_enabled_dependency_missing` / `rtk_enabled_version_too_old` — produced in Task 6, asserted in Task 6, constants updated in Task 7 Step 4, asserted in Task 7 Step 6. Consistent (note the deliberate `jq_missing` → `dependency_missing` rename).

No inconsistencies found.
