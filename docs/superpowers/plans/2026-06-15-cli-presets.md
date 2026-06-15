# CLI Configuration Presets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-CLI provider/model/effort mappings in personal projects with global, named CLI configuration presets that users can create, edit, delete, and switch between.

**Architecture:** Introduce `CliPreset` model and global `cli-presets.json` storage. `ProjectProfile` simplifies to store only `activePresetId`. Preset resolution (CLI, provider, model, effort) happens at session launch and config profile generation time — not in the cubit load path.

**Tech Stack:** Dart/Flutter, flutter_bloc, JSON file storage via Repository pattern

---

### Task 1: Create CliPreset model (test-first)

**Files:**
- Create: `client/lib/models/cli_preset.dart`
- Create: `client/test/models/cli_preset_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/cli_preset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  group('CliPreset', () {
    test('fromJson and toJson round-trip', () {
      final now = 1718400000000;
      final preset = CliPreset(
        id: 'abc-123',
        name: 'Claude Work',
        cli: CliTool.claude,
        provider: 'prov-1',
        model: 'claude-sonnet-4-6',
        effort: 'high',
        createdAt: now,
        updatedAt: now,
      );

      final json = preset.toJson();
      final restored = CliPreset.fromJson(json);

      expect(restored.id, 'abc-123');
      expect(restored.name, 'Claude Work');
      expect(restored.cli, CliTool.claude);
      expect(restored.provider, 'prov-1');
      expect(restored.model, 'claude-sonnet-4-6');
      expect(restored.effort, 'high');
      expect(restored.createdAt, now);
      expect(restored.updatedAt, now);
    });

    test('fromJson with missing optional fields uses defaults', () {
      final preset = CliPreset.fromJson({
        'id': 'x',
        'name': 'Minimal',
        'cli': 'claude',
        'provider': 'p',
        'model': 'm',
      });
      expect(preset.effort, '');
      expect(preset.createdAt, isNonZero); // auto-set by copyWith or fromJson default
    });

    test('copyWith updates individual fields', () {
      final preset = CliPreset(
        id: '1',
        name: 'Original',
        cli: CliTool.claude,
        provider: 'p1',
        model: 'm1',
        effort: '',
        createdAt: 1000,
        updatedAt: 1000,
      );
      final updated = preset.copyWith(name: 'Updated', effort: 'high');
      expect(updated.name, 'Updated');
      expect(updated.effort, 'high');
      expect(updated.id, '1'); // unchanged
      expect(updated.cli, CliTool.claude); // unchanged
    });

    test('equality and hashCode', () {
      final a = CliPreset(
        id: '1', name: 'A', cli: CliTool.claude,
        provider: 'p', model: 'm', effort: '',
        createdAt: 1, updatedAt: 1,
      );
      final b = CliPreset(
        id: '1', name: 'A', cli: CliTool.claude,
        provider: 'p', model: 'm', effort: '',
        createdAt: 1, updatedAt: 1,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/models/cli_preset_test.dart
```

Expected: FAIL — file/model doesn't exist.

- [ ] **Step 3: Write CliPreset model**

```dart
// client/lib/models/cli_preset.dart
import 'package:flutter/foundation.dart';

import 'team_config.dart';

@immutable
class CliPreset {
  const CliPreset({
    required this.id,
    required this.name,
    required this.cli,
    required this.provider,
    required this.model,
    this.effort = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory CliPreset.fromJson(Map<String, Object?> json) {
    return CliPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      cli: CliTool.parse(json['cli']),
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      effort: json['effort'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final CliTool cli;
  final String provider;
  final String model;
  final String effort;
  final int createdAt;
  final int updatedAt;

  CliPreset copyWith({
    String? id,
    String? name,
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    int? createdAt,
    int? updatedAt,
  }) {
    return CliPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      cli: cli ?? this.cli,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'cli': cli.value,
      'provider': provider,
      'model': model,
      if (effort.isNotEmpty) 'effort': effort,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CliPreset &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            cli == other.cli &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, cli, provider, model, effort, createdAt, updatedAt);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd client && flutter test test/models/cli_preset_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/cli_preset.dart client/test/models/cli_preset_test.dart
git commit -m "feat(cli-presets): add CliPreset model with JSON serialization

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Create CliPresetsRepository (test-first)

**Files:**
- Create: `client/lib/repositories/cli_presets_repository.dart`
- Create: `client/test/repositories/cli_presets_repository_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/repositories/cli_presets_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../support/memory_filesystem.dart';

void main() {
  group('CliPresetsRepository', () {
    late MemoryFilesystem fs;
    late CliPresetsRepository repo;
    late String presetsPath;

    setUp(() {
      fs = MemoryFilesystem();
      presetsPath = '/teampilot/cli-presets.json';
      repo = CliPresetsRepository(fs: fs, presetsPath: presetsPath);
    });

    test('load returns empty list when file does not exist', () async {
      final presets = await repo.load();
      expect(presets, isEmpty);
    });

    test('load returns presets from valid JSON', () async {
      await fs.writeString(presetsPath, '''
[
  {"id":"1","name":"Claude Work","cli":"claude","provider":"p1","model":"m1","effort":"high","createdAt":1000,"updatedAt":1000}
]
''');

      final presets = await repo.load();
      expect(presets.length, 1);
      expect(presets.first.id, '1');
      expect(presets.first.name, 'Claude Work');
      expect(presets.first.cli, CliTool.claude);
      expect(presets.first.effort, 'high');
    });

    test('load returns empty list for malformed JSON', () async {
      await fs.writeString(presetsPath, '{not valid');
      final presets = await repo.load();
      expect(presets, isEmpty);
    });

    test('save writes presets to file and returns them', () async {
      final presets = [
        CliPreset(
          id: '1', name: 'Test', cli: CliTool.claude,
          provider: 'p', model: 'm', effort: '',
          createdAt: 1000, updatedAt: 1000,
        ),
      ];

      await repo.save(presets);

      final raw = await fs.readString(presetsPath);
      expect(raw, contains('"id":"1"'));
      expect(raw, contains('"name":"Test"'));
    });

    test('save then load round-trips', () async {
      final presets = [
        CliPreset(
          id: 'a', name: 'A', cli: CliTool.claude,
          provider: 'p', model: 'm1', effort: '',
          createdAt: 1, updatedAt: 1,
        ),
        CliPreset(
          id: 'b', name: 'B', cli: CliTool.flashskyai,
          provider: 'p2', model: 'm2', effort: 'low',
          createdAt: 2, updatedAt: 2,
        ),
      ];

      await repo.save(presets);
      final loaded = await repo.load();

      expect(loaded.length, 2);
      expect(loaded[0], presets[0]);
      expect(loaded[1], presets[1]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/repositories/cli_presets_repository_test.dart
```

Expected: FAIL — file doesn't exist.

- [ ] **Step 3: Write CliPresetsRepository**

```dart
// client/lib/repositories/cli_presets_repository.dart
import 'dart:convert';

import '../models/cli_preset.dart';
import '../services/io/filesystem.dart';
import '../utils/logger.dart';

class CliPresetsRepository {
  CliPresetsRepository({
    required this.fs,
    required this.presetsPath,
  });

  final Filesystem fs;
  final String presetsPath;

  Future<List<CliPreset>> load() async {
    try {
      final exists = await fs.exists(presetsPath);
      if (!exists) return const [];

      final raw = await fs.readString(presetsPath);
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map<String, Object?>>()
          .map((e) => CliPreset.fromJson(e))
          .toList(growable: false);
    } on Object catch (e) {
      appLogger.w('[cli-presets] load failed: $e');
      return const [];
    }
  }

  Future<List<CliPreset>> save(List<CliPreset> presets) async {
    try {
      final json = jsonEncode(presets.map((p) => p.toJson()).toList());
      await fs.writeString(presetsPath, json);
    } on Object catch (e) {
      appLogger.e('[cli-presets] save failed: $e');
    }
    return List.unmodifiable(presets);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd client && flutter test test/repositories/cli_presets_repository_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/cli_presets_repository.dart client/test/repositories/cli_presets_repository_test.dart
git commit -m "feat(cli-presets): add CliPresetsRepository with JSON persistence

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Create CliPresetsCubit (test-first)

**Files:**
- Create: `client/lib/cubits/cli_presets_cubit.dart`
- Create: `client/test/cubits/cli_presets_cubit_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/cli_presets_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../support/memory_filesystem.dart';

void main() {
  late MemoryFilesystem fs;
  late CliPresetsRepository repo;
  late CliPresetsCubit cubit;

  setUp(() {
    fs = MemoryFilesystem();
    repo = CliPresetsRepository(fs: fs, presetsPath: '/cli-presets.json');
    cubit = CliPresetsCubit(repository: repo);
  });

  test('initial state is empty loading', () {
    expect(cubit.state.presets, isEmpty);
    expect(cubit.state.status, CliPresetsLoadStatus.idle);
  });

  test('load populates presets', () async {
    await cubit.load();
    expect(cubit.state.status, CliPresetsLoadStatus.ready);
    expect(cubit.state.presets, isEmpty);
  });

  test('addPreset creates and persists a preset', () async {
    await cubit.load();

    await cubit.addPreset(
      name: 'New Preset',
      cli: CliTool.claude,
      provider: 'p1',
      model: 'm1',
      effort: 'high',
    );

    expect(cubit.state.presets.length, 1);
    final preset = cubit.state.presets.first;
    expect(preset.name, 'New Preset');
    expect(preset.cli, CliTool.claude);
    expect(preset.provider, 'p1');
    expect(preset.model, 'm1');
    expect(preset.effort, 'high');
    expect(preset.id, isNotEmpty);

    // Verify persistence
    final cubit2 = CliPresetsCubit(repository: repo);
    await cubit2.load();
    expect(cubit2.state.presets.length, 1);
    expect(cubit2.state.presets.first.id, preset.id);
  });

  test('updatePreset modifies an existing preset', () async {
    await cubit.load();
    await cubit.addPreset(name: 'Old', cli: CliTool.claude, provider: 'p', model: 'm');
    final id = cubit.state.presets.first.id;

    await cubit.updatePreset(
      id: id,
      name: 'Updated',
      cli: CliTool.flashskyai,
      provider: 'p2',
      model: 'm2',
      effort: 'low',
    );

    final updated = cubit.state.presets.first;
    expect(updated.name, 'Updated');
    expect(updated.cli, CliTool.flashskyai);
    expect(updated.provider, 'p2');
    expect(updated.model, 'm2');
    expect(updated.effort, 'low');
  });

  test('deletePreset removes a preset', () async {
    await cubit.load();
    await cubit.addPreset(name: 'To Delete', cli: CliTool.claude, provider: 'p', model: 'm');
    final id = cubit.state.presets.first.id;

    await cubit.deletePreset(id);

    expect(cubit.state.presets, isEmpty);
  });

  test('addPreset does not allow empty name', () async {
    await cubit.load();
    await cubit.addPreset(name: '  ', cli: CliTool.claude, provider: 'p', model: 'm');
    // Should not add — name must be non-blank
    expect(cubit.state.presets, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/cubits/cli_presets_cubit_test.dart
```

Expected: FAIL — cubit doesn't exist.

- [ ] **Step 3: Write CliPresetsCubit**

```dart
// client/lib/cubits/cli_presets_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/cli_preset.dart';
import '../models/team_config.dart';
import '../repositories/cli_presets_repository.dart';
import '../utils/logger.dart';

enum CliPresetsLoadStatus { idle, loading, ready, error }

class CliPresetsState extends Equatable {
  const CliPresetsState({
    this.presets = const [],
    this.status = CliPresetsLoadStatus.idle,
    this.errorMessage,
  });

  final List<CliPreset> presets;
  final CliPresetsLoadStatus status;
  final String? errorMessage;

  CliPresetsState copyWith({
    List<CliPreset>? presets,
    CliPresetsLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CliPresetsState(
      presets: presets ?? this.presets,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  CliPreset? presetById(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  List<Object?> get props => [presets, status, errorMessage];
}

class CliPresetsCubit extends Cubit<CliPresetsState> {
  CliPresetsCubit({required CliPresetsRepository repository})
      : _repository = repository,
        super(const CliPresetsState());

  final CliPresetsRepository _repository;
  final _uuid = const Uuid();

  Future<void> load() async {
    if (state.status == CliPresetsLoadStatus.loading) return;
    emit(state.copyWith(status: CliPresetsLoadStatus.loading, clearError: true));
    try {
      final presets = await _repository.load();
      emit(state.copyWith(presets: presets, status: CliPresetsLoadStatus.ready));
    } on Object catch (e) {
      appLogger.e('[cli-presets] load failed: $e');
      emit(state.copyWith(
        status: CliPresetsLoadStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> addPreset({
    required String name,
    required CliTool cli,
    required String provider,
    required String model,
    String effort = '',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final preset = CliPreset(
      id: _uuid.v4(),
      name: trimmedName,
      cli: cli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      createdAt: now,
      updatedAt: now,
    );

    final next = List<CliPreset>.from(state.presets)..add(preset);
    await _persist(next);
  }

  Future<void> updatePreset({
    required String id,
    required String name,
    required CliTool cli,
    required String provider,
    required String model,
    String effort = '',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    final index = state.presets.indexWhere((p) => p.id == id);
    if (index < 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final next = List<CliPreset>.from(state.presets);
    next[index] = next[index].copyWith(
      name: trimmedName,
      cli: cli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      updatedAt: now,
    );

    await _persist(next);
  }

  Future<void> deletePreset(String id) async {
    final next = state.presets.where((p) => p.id != id).toList(growable: false);
    if (next.length == state.presets.length) return; // nothing removed
    await _persist(next);
  }

  Future<void> _persist(List<CliPreset> presets) async {
    final saved = await _repository.save(presets);
    emit(state.copyWith(presets: saved));
  }
}
```

NOTE: If the project does not use the `uuid` package, replace the UUID generation with a simple ID generator utility already in the project. Check `client/pubspec.yaml` for available ID generation. If no UUID package, use: `DateTime.now().millisecondsSinceEpoch.toRadixString(36) + Math.Random().nextInt(100000).toRadixString(36)` via a helper.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd client && flutter test test/cubits/cli_presets_cubit_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/cli_presets_cubit.dart client/test/cubits/cli_presets_cubit_test.dart
git commit -m "feat(cli-presets): add CliPresetsCubit with CRUD operations

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Simplify ProjectAgentConfig

**Files:**
- Modify: `client/lib/models/project_profile.dart`
- Modify: `client/test/models/project_profile_test.dart` (if exists)

- [ ] **Step 1: Update ProjectAgentConfig — remove provider, model, effort**

In `client/lib/models/project_profile.dart`, modify `ProjectAgentConfig`:

Remove fields from constructor: `provider`, `model`, `effort`
Remove from `fromJson`: reading `provider`, `model`, `effort`
Remove from `copyWith`: `provider`, `model`, `effort` parameters
Remove from `toJson`: writing `provider`, `model`, `effort`
Remove from `==`: comparisons for `provider`, `model`, `effort`
Remove from `hashCode`: hashing of `provider`, `model`, `effort`

The constructor becomes:
```dart
const ProjectAgentConfig({
  this.agent = '',
  this.agentType = '',
  this.extraArgs = '',
  this.prompt = '',
  this.dangerouslySkipPermissions = false,
});
```

- [ ] **Step 2: Update ProjectProfile — remove cli, providerIdsByTool, modelsByTool, effortsByTool; add activePresetId**

In the same file, modify `ProjectProfile`:

Remove fields: `cli`, `_providerIdsByTool`, `_modelsByTool`, `_effortsByTool`
Remove getters: `providerIdsByTool`, `modelsByTool`, `effortsByTool`
Remove from constructor, `fromJson`, `copyWith`, `toJson`, `==`, `hashCode`

Add:
```dart
final String? activePresetId;
```

Add to constructor:
```dart
this.activePresetId,
```

Add to `fromJson`:
```dart
activePresetId: (json['activePresetId'] as String?)?.trim() ?? '',
```
(Use '' and treat '' as null — keeps it simple)

Add to `copyWith`:
```dart
String? activePresetId,
```

Add to `toJson`:
```dart
if (activePresetId != null && activePresetId!.isNotEmpty) 'activePresetId': activePresetId,
```

Add to `==` and `hashCode`: include `activePresetId`.

- [ ] **Step 3: Fix all compilation errors across the codebase**

After removing these fields, run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | head -100
```

Find every file that references:
- `profile.cli` → will need updating in later tasks
- `profile.providerIdsByTool` → will need updating in later tasks
- `profile.modelsByTool` → will need updating in later tasks
- `profile.effortsByTool` → will need updating in later tasks
- `agent.provider`, `agent.model`, `agent.effort` → will need updating in later tasks

For NOW, comment out the offending lines in consumers (adding `// TODO: migrate to presets`) so the code compiles. These will be properly fixed in Tasks 5-8.

- [ ] **Step 4: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors (warnings OK for now).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/project_profile.dart
git commit -m "refactor(cli-presets): simplify ProjectProfile and ProjectAgentConfig for preset migration

- Remove cli, providerIdsByTool, modelsByTool, effortsByTool from ProjectProfile
- Remove provider, model, effort from ProjectAgentConfig
- Add activePresetId to ProjectProfile
- Temporarily comment out consumers for incremental migration

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Wire CliPresetsCubit into app_shell.dart

**Files:**
- Modify: `client/lib/app/app_shell.dart`

- [ ] **Step 1: Add CliPresetsCubit provision**

Find where other global cubits are provided via `RepositoryProvider` or `BlocProvider` in `app_shell.dart`. Add:

```dart
import '../cubits/cli_presets_cubit.dart';
import '../repositories/cli_presets_repository.dart';
import '../services/storage/app_storage.dart';
```

Then in the BlocProvider/RepositoryProvider list:
```dart
RepositoryProvider<CliPresetsCubit>(
  create: (context) {
    final paths = context.read<AppPaths>();
    final fs = context.read<Filesystem>();
    final presetsPath = '${paths.basePath}/cli-presets.json';
    final repo = CliPresetsRepository(fs: fs, presetsPath: presetsPath);
    final cubit = CliPresetsCubit(repository: repo);
    // Eager-load presets so they're available when UI needs them
    unawaited(cubit.load());
    return cubit;
  },
),
```

CRITICAL: Check the actual DI pattern used in `app_shell.dart` — follow the exact same pattern as other cubits. If other cubits use `BlocProvider`, use that. If they use `RepositoryProvider`, use that. Find the correct `AppPaths` accessor and `Filesystem` accessor names used in existing code.

- [ ] **Step 2: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(cli-presets): wire CliPresetsCubit into app shell DI

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Update ProjectProfileCubit

**Files:**
- Modify: `client/lib/cubits/project_profile_cubit.dart`
- Modify: `client/test/cubits/project_profile_cubit_test.dart` (if exists)

- [ ] **Step 1: Remove setCli and setCliDefaults**

Delete the `setCli` and `setCliDefaults` methods from `ProjectProfileCubit`.

- [ ] **Step 2: Add setActivePreset**

```dart
Future<void> setActivePreset(String presetId) async {
  final profile = state.profile;
  if (profile == null) return;
  await _persist(profile.copyWith(activePresetId: presetId.trim()));
}
```

- [ ] **Step 3: Update load method — preserve activePresetId**

The `load` method already loads the profile from the repository. Since `activePresetId` is part of the stored JSON, it loads automatically. No code change needed for load — just verify the field round-trips correctly.

- [ ] **Step 4: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/project_profile_cubit.dart
git commit -m "refactor(cli-presets): remove setCli/setCliDefaults, add setActivePreset

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Update config profile resolution path

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_context.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Modify: `client/lib/services/cli/registry/config_profile/codex_config_profile_capability.dart`
- Modify: `client/lib/services/cli/registry/config_profile/claude_config_profile_capability.dart`

- [ ] **Step 1: Add a resolution helper**

Add to `config_profile_context.dart` (or a new helper):

```dart
import '../../../../models/cli_preset.dart';

/// Resolve CLI/provider/model/effort for a personal project from its active preset.
/// Falls back to empty strings if no preset is active or found.
CliPreset? resolveActivePreset(String? activePresetId, List<CliPreset> presets) {
  if (activePresetId == null || activePresetId.isEmpty) return null;
  for (final p in presets) {
    if (p.id == activePresetId) return p;
  }
  return null;
}
```

- [ ] **Step 2: Update standaloneProviderId and standaloneModelId**

Change signatures to accept preset info instead of reading from profile:

```dart
String standaloneProviderId(CliPreset? preset) {
  return preset?.provider.trim() ?? '';
}

String standaloneModelId(CliPreset? preset) {
  return preset?.model.trim() ?? '';
}

CliTool standaloneCli(CliPreset? preset, {CliTool fallback = CliTool.claude}) {
  return preset?.cli ?? fallback;
}
```

- [ ] **Step 3: Update standaloneTeamFromProfile and standaloneMemberFromProfile**

Change signatures to accept `CliPreset?`:

```dart
TeamConfig standaloneTeamFromProfile(
  ProjectProfile profile, {
  required String projectId,
  required String sessionTeamName,
  required CliPreset? preset,
}) {
  final member = standaloneMemberFromProfile(profile, preset: preset);
  return TeamConfig(
    id: projectId.trim(),
    name: sessionTeamName.trim(),
    cli: preset?.cli ?? CliTool.claude,
    members: [member],
    skillIds: profile.skillIds,
    pluginIds: profile.pluginIds,
    mcpServerIds: profile.mcpServerIds,
    teamMode: TeamMode.native,
    forceTeamLeadDelegateMode: false,
  );
}

TeamMemberConfig standaloneMemberFromProfile(
  ProjectProfile profile, {
  required CliPreset? preset,
}) {
  final agent = profile.agent;
  final name = _standaloneMemberDisplayName(agent);
  return TeamMemberConfig(
    id: TeamMemberNaming.slugMemberName(name),
    name: name,
    provider: preset?.provider.trim() ?? '',
    model: preset?.model.trim() ?? '',
    agent: agent.agent,
    agentType: agent.agentType,
    extraArgs: agent.extraArgs,
    prompt: agent.prompt,
    dangerouslySkipPermissions: agent.dangerouslySkipPermissions,
    cli: preset?.cli ?? CliTool.claude,
    effort: preset?.effort.trim() ?? '',
  );
}
```

- [ ] **Step 4: Update session_launch_service.dart**

In `_personalProfileForSession`:
```dart
ProjectProfile _personalProfileForSession(
  AppSession session,
  ProjectProfile profile,
) {
  // With presets, CLI selection is handled by activePresetId.
  // The session's cli field is no longer used for provider/model resolution.
  return profile;
}
```

In the method that builds the launch config (where `config_profile_service` is called), pass the resolved preset:
```dart
final presetsCubit = _readPresetsCubit(); // obtain via context or injection
final preset = resolveActivePreset(profile.activePresetId, presetsCubit.state.presets);
// ... pass `preset` to config_profile_service and standalone helpers
```

- [ ] **Step 5: Update config_profile_service.dart**

Where `profile.cli` is read (around L303), replace with:
```dart
final cli = preset?.cli ?? CliTool.claude;
```

Pass `preset` through to `standaloneTeamFromProfile` and `standaloneMemberFromProfile`.

- [ ] **Step 6: Update capability files**

In `claude_config_profile_capability.dart` and `codex_config_profile_capability.dart`, replace reads of `profile.agent.model`, `profile.agent.effort`, `profile.effortsByTool[toolId]` with the resolved preset's model/effort fields. The preset should be threaded through `ConfigProfileLaunchContext` or accessed directly.

Since these files receive `ConfigProfileLaunchContext` which has a `profile` field, the simplest approach is to accept the preset as a new field on `ConfigProfileLaunchContext`:

```dart
// In config_profile_context.dart, add to ConfigProfileLaunchContext:
final CliPreset? preset;
```

Then in capability files, read `context.preset?.model` / `context.preset?.effort` instead of `profile.agent.model` / `profile.agent.effort`.

- [ ] **Step 7: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/
git commit -m "refactor(cli-presets): update config profile resolution to use presets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Create CliPresetEditDialog

**Files:**
- Create: `client/lib/pages/home_workspace/project/config/cli_preset_edit_dialog.dart`

- [ ] **Step 1: Write the dialog widget**

```dart
// client/lib/pages/home_workspace/project/config/cli_preset_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/app_provider_cubit.dart';
import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/team_config.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../widgets/app_dialog.dart';
import '../../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../../widgets/app_provider/cli_effort_picker_field.dart';
import '../../../../widgets/app_provider/provider_model_picker_field.dart';
import '../../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'project_cli_config_helpers.dart';
import 'project_cli_effort_helpers.dart';

class CliPresetEditDialog extends StatefulWidget {
  const CliPresetEditDialog({
    this.existing,
    super.key,
  });

  /// If non-null, editing an existing preset.
  final CliPreset? existing;

  bool get isEditing => existing != null;

  @override
  State<CliPresetEditDialog> createState() => _CliPresetEditDialogState();
}

class _CliPresetEditDialogState extends State<CliPresetEditDialog> {
  late final TextEditingController _nameCtl;
  late CliTool _cli;
  late String _providerId;
  late String _modelId;
  late String _effortId;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtl = TextEditingController(text: p?.name ?? '');
    _cli = p?.cli ?? CliTool.claude;
    _providerId = p?.provider ?? '';
    _modelId = p?.model ?? '';
    _effortId = p?.effort ?? '';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  AppProviderConfig? _selectedProvider(Iterable<AppProviderConfig> providers) {
    for (final p in providers) {
      if (p.id == _providerId) return p;
    }
    return null;
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    if (_providerId.trim().isEmpty) return;

    final cubit = context.read<CliPresetsCubit>();
    if (widget.isEditing) {
      await cubit.updatePreset(
        id: widget.existing!.id,
        name: name,
        cli: _cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      );
    } else {
      await cubit.addPreset(
        name: name,
        cli: _cli,
        provider: _providerId,
        model: _modelId,
        effort: _effortId,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(_cli)
        .toList(growable: false);
    final selectedProvider = _selectedProvider(providers);
    final hideModelPicker = projectCliHidesModelPicker(
      registry, _cli, selectedProvider,
    );
    final showEffortPicker = projectCliShowsEffortPicker(
      registry: registry, cli: _cli,
      provider: selectedProvider, model: _modelId,
    );

    return AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: widget.isEditing
                ? l10n.projectCliEditPresetTitle
                : l10n.projectCliAddPresetTitle,
          ),
          const SizedBox(height: 16),
          SettingsLabeledStackedRow(
            title: l10n.projectCliPresetNameLabel,
            body: TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(),
              autofocus: !widget.isEditing,
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledRow(
            title: l10n.teamCliLabel,
            trailing: AppDropdownField<String>(
              items: [for (final def in registry.launchable) def.id.value],
              initialItem: _cli.value,
              decoration: dropdownDeco,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _cli = CliTool.decode(value);
                  _providerId = '';
                  _modelId = '';
                  _effortId = '';
                });
              },
              itemBuilder: (context, value) => cliDropdownRow(
                context,
                cli: CliTool.decode(value),
                label: cliDisplayName(
                  registry.tryGet(CliTool.decode(value))!,
                  l10n,
                ),
                registry: registry,
              ),
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledRow(
            title: l10n.provider,
            trailing: AppDropdownField<String>(
              key: ValueKey('preset-provider-$_cli-$_providerId'),
              items: providers.map((p) => p.id).toList()..sort(),
              initialItem: _providerId.isEmpty ? null : _providerId,
              hintText: l10n.selectProvider,
              decoration: dropdownDeco,
              onChanged: (value) {
                setState(() {
                  _providerId = value ?? '';
                  _modelId = '';
                  _effortId = '';
                });
              },
              itemBuilder: providerDropdownItemBuilder(
                providers: providers,
                labelFor: (value) {
                  for (final p in providers) {
                    if (p.id == value) return p.name;
                  }
                  return value;
                },
              ),
            ),
            showDividerBelow: hideModelPicker || showEffortPicker,
          ),
          if (!hideModelPicker)
            SettingsLabeledRow(
              title: l10n.model,
              trailing: ProviderModelPickerField(
                key: ValueKey('preset-model-$_providerId-$_modelId'),
                cli: _cli,
                providerId: _providerId,
                provider: selectedProvider,
                value: _modelId,
                hintText: l10n.selectModel,
                decoration: dropdownDeco,
                onChanged: (value) => setState(() {
                  _modelId = value.trim();
                  if (!projectCliShowsEffortPicker(
                    registry: registry, cli: _cli,
                    provider: selectedProvider, model: _modelId,
                  )) {
                    _effortId = '';
                  }
                }),
              ),
              showDividerBelow: showEffortPicker,
            ),
          if (showEffortPicker)
            SettingsLabeledRow(
              title: l10n.projectCliEffortLevel,
              subtitle: l10n.projectCliEffortLevelSubtitle,
              trailing: CliEffortPickerField(
                key: ValueKey('preset-effort-$_providerId-$_modelId-$_effortId'),
                cli: _cli,
                value: _effortId,
                provider: selectedProvider,
                model: _modelId,
                allowInherit: true,
                inheritLabel: l10n.projectCliEffortInheritHint,
                decoration: dropdownDeco,
                onChanged: (value) => setState(() => _effortId = value.trim()),
              ),
              showDividerBelow: false,
            ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _providerId.trim().isEmpty ? null : _save,
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add l10n strings**

Edit `client/lib/l10n/app_en.arb` and `app_zh.arb` to add the new strings used in the dialog. The widget references:
- `projectCliEditPresetTitle` — "Edit Preset" / "编辑预设"
- `projectCliAddPresetTitle` — "Add Preset" / "添加预设"
- `projectCliPresetNameLabel` — "Preset Name" / "预设名称"

After editing ARB files, run:
```bash
cd client && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 3: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/config/cli_preset_edit_dialog.dart client/lib/l10n/
git commit -m "feat(cli-presets): add CliPresetEditDialog

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Create CliPresetsManageDialog

**Files:**
- Create: `client/lib/pages/home_workspace/project/config/cli_presets_manage_dialog.dart`

- [ ] **Step 1: Write the dialog widget**

```dart
// client/lib/pages/home_workspace/project/config/cli_presets_manage_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/team_config.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../widgets/app_dialog.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'cli_preset_edit_dialog.dart';

class CliPresetsManageDialog extends StatelessWidget {
  const CliPresetsManageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<CliPresetsCubit>().state;
    final presets = state.presets;

    return AppDialog(
      maxWidth: 560,
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.projectCliPresetsManageTitle),
          const SizedBox(height: 16),
          if (presets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.projectCliPresetsEmptyHint,
                textAlign: TextAlign.center,
                style: AppTextStyles.of(context).bodySmall,
              ),
            )
          else
            ...presets.map((preset) => _PresetRow(preset: preset)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _openAddDialog(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.projectCliAddPresetTitle),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openAddDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const CliPresetEditDialog(),
    );
  }

  void _openEditDialog(BuildContext context, CliPreset preset) {
    showDialog<void>(
      context: context,
      builder: (_) => CliPresetEditDialog(existing: preset),
    );
  }

  Future<void> _deletePreset(BuildContext context, CliPreset preset) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.projectCliDeletePresetTitle),
        content: Text(l10n.projectCliDeletePresetConfirm(preset.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<CliPresetsCubit>().deletePreset(preset.id);
    }
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset});

  final CliPreset preset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final def = registry.tryGet(preset.cli);
    final cliName = def != null ? cliDisplayName(def, l10n) : preset.cli.value;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final subtitle = _subtitle(preset);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.name,
                  style: styles.prominent.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cliName · $subtitle',
                  style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: l10n.edit,
            onPressed: () {
              final dialog = context.findAncestorWidgetOfExactType<CliPresetsManageDialog>();
              if (dialog != null) {
                dialog._openEditDialog(context, preset);
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outlined, size: 20, color: cs.error),
            tooltip: l10n.delete,
            onPressed: () {
              final dialog = context.findAncestorWidgetOfExactType<CliPresetsManageDialog>();
              if (dialog != null) {
                dialog._deletePreset(context, preset);
              }
            },
          ),
        ],
      ),
    );
  }

  String _subtitle(CliPreset preset) {
    final parts = <String>[];
    if (preset.provider.isNotEmpty) parts.add(preset.provider);
    if (preset.model.isNotEmpty) parts.add(preset.model);
    if (preset.effort.isNotEmpty) parts.add(preset.effort);
    return parts.isNotEmpty ? parts.join(' · ') : 'Not configured';
  }
}
```

NOTE: The `_openEditDialog` and `_deletePreset` methods are called from `_PresetRow` via the parent widget reference. This is a common Flutter pattern. If it feels fragile, refactor to pass callbacks as constructor parameters to `_PresetRow`.

- [ ] **Step 2: Add l10n strings**

Edit `client/lib/l10n/app_en.arb` and `app_zh.arb`:
- `projectCliPresetsManageTitle` — "Manage Presets" / "管理预设"
- `projectCliPresetsEmptyHint` — "No presets yet. Create one to get started." / "还没有预设，创建一个开始使用"
- `projectCliDeletePresetTitle` — "Delete Preset" / "删除预设"
- `projectCliDeletePresetConfirm` — "Delete preset '{name}'? This cannot be undone." / "删除预设'{name}'？此操作不可撤销。"

Run:
```bash
cd client && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 3: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/config/cli_presets_manage_dialog.dart client/lib/l10n/
git commit -m "feat(cli-presets): add CliPresetsManageDialog with list and delete

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Update sidebar to use preset dropdown

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_sidebar.dart`

- [ ] **Step 1: Replace _DefaultCliDropdown with _PresetDropdown**

Replace the `_DefaultCliDropdown` class and its `_configuredCliValues` helper with a new `_PresetDropdown` widget that:
- Reads `CliPresetsCubit` and `ProjectProfileCubit`
- Shows all presets in a dropdown (preset names)
- Selected item = preset matching `profile.activePresetId`
- Gear button opens `CliPresetsManageDialog`
- Empty state shows "No presets" with create CTA

```dart
class _PresetDropdown extends StatelessWidget {
  const _PresetDropdown({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presetsState = context.watch<CliPresetsCubit>().state;
    final profileState = context.watch<ProjectProfileCubit>().state;
    final ready = profileState.status == ProjectProfileLoadStatus.ready &&
        profileState.profile != null;

    if (!ready || presetsState.status == CliPresetsLoadStatus.loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final profile = profileState.profile!;
    final presets = presetsState.presets;
    final activePreset = presetsState.presetById(profile.activePresetId ?? '');

    if (presets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: OutlinedButton.icon(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => const CliPresetsManageDialog(),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.projectCliAddPresetTitle),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }

    final presetNames = presets.map((p) => p.id).toList();
    final initialId = activePreset?.id ?? presets.first.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AppDropdownField<String>(
              key: ValueKey('project-sidebar-preset-$projectId-$initialId'),
              items: presetNames,
              initialItem: initialId,
              decoration: AppDropdownDecorations.themed(context),
              onChanged: (value) {
                if (value == null) return;
                context.read<ProjectProfileCubit>().setActivePreset(value);
              },
              itemBuilder: (context, presetId) {
                final preset = presetsState.presetById(presetId);
                if (preset == null) {
                  return Text(presetId, style: AppTextStyles.of(context).bodySmall);
                }
                return _PresetDropdownItem(preset: preset);
              },
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.tune_outlined,
            tooltip: l10n.projectCliPresetsManageTitle,
            onTap: throttledTap(
              'project_sidebar_presets_manage',
              () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => const CliPresetsManageDialog(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetDropdownItem extends StatelessWidget {
  const _PresetDropdownItem({required this.preset});

  final CliPreset preset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = CliToolRegistryScope.of(context);
    final def = registry.tryGet(preset.cli);
    final cliName = def != null ? cliDisplayName(def, l10n) : preset.cli.value;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          preset.name,
          style: AppTextStyles.of(context).prominent.copyWith(color: cs.onSurface),
        ),
        Text(
          cliName,
          style: AppTextStyles.of(context).bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Replace usage in build()**

In `_HomeWorkspaceProjectSidebarState.build()`, replace:
```dart
if (_isPersonal) ...[
  _DefaultCliDropdown(projectId: widget.project.projectId),
  const SizedBox(height: 12),
],
```

with:
```dart
if (_isPersonal) ...[
  _PresetDropdown(projectId: widget.project.projectId),
  const SizedBox(height: 12),
],
```

- [ ] **Step 3: Add imports**

Add to the top of the file:
```dart
import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../models/cli_preset.dart';
import 'config/cli_presets_manage_dialog.dart';
```

Remove unused imports:
- `project_cli_config_helpers.dart` — no longer needed
- `project_cli_defaults_section.dart` — no longer needed

- [ ] **Step 4: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/project/home_workspace_project_sidebar.dart
git commit -m "feat(cli-presets): replace sidebar CLI dropdown with preset dropdown

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Update ProjectAgentSection

**Files:**
- Modify: `client/lib/pages/home_workspace/project/config/project_agent_section.dart`

- [ ] **Step 1: Remove ProjectCliDefaultsSection; add preset info row**

In `ProjectAgentConfigFormState.build()`:

Remove:
```dart
ProjectCliDefaultsSection(profile: profile, cubit: widget.cubit),
const SizedBox(height: _kAgentCardGap),
```

Add after the first Column child list start:
```dart
_PresetInfoRow(profile: profile),
const SizedBox(height: _kAgentCardGap),
```

- [ ] **Step 2: Replace profile.cli references for agent preset**

The `showAgentPreset` and `agentPresetStyle` currently use `profile.cli`. Replace with resolving from `CliPresetsCubit`:

```dart
final presetsCubit = context.read<CliPresetsCubit>();
final activePreset = presetsCubit.state.presetById(profile.activePresetId ?? '');
final effectiveCli = activePreset?.cli ?? CliTool.claude;
final showAgentPreset = cliRegistry.supportsMemberAgentPreset(effectiveCli);
final agentPresetStyle = cliRegistry.memberAgentPresetStyle(effectiveCli);
```

And in `MemberAgentPresetField`:
```dart
cli: effectiveCli,
```

- [ ] **Step 3: Create _PresetInfoRow widget**

Add a simple widget at the bottom of the file:

```dart
class _PresetInfoRow extends StatelessWidget {
  const _PresetInfoRow({required this.profile});

  final ProjectProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presetsCubit = context.watch<CliPresetsCubit>();
    final preset = presetsCubit.state.presetById(profile.activePresetId ?? '');
    final registry = CliToolRegistryScope.of(context);

    return SettingsSurfaceCard(
      child: SettingsLabeledRow(
        title: l10n.projectCliPresetLabel,
        subtitle: preset != null
            ? _presetSubtitle(preset, registry, l10n)
            : l10n.projectCliNoPresetHint,
        trailing: TextButton(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => const CliPresetsManageDialog(),
            );
          },
          child: Text(l10n.projectCliManagePresets),
        ),
        showDividerBelow: false,
      ),
    );
  }

  String _presetSubtitle(CliPreset preset, CliToolRegistry registry, AppLocalizations l10n) {
    final def = registry.tryGet(preset.cli);
    final cliName = def != null ? cliDisplayName(def, l10n) : preset.cli.value;
    return cliName;
  }
}
```

Add l10n strings:
- `projectCliPresetLabel` — "Active Preset" / "当前预设"
- `projectCliNoPresetHint` — "No preset selected" / "未选择预设"
- `projectCliManagePresets` — "Manage" / "管理"

- [ ] **Step 4: Add imports**

```dart
import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../models/cli_preset.dart';
import 'cli_presets_manage_dialog.dart';
```

Remove import of `project_cli_defaults_section.dart`.

- [ ] **Step 5: Run gen_warmup_glyphs**

```bash
cd client && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 6: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/home_workspace/project/config/project_agent_section.dart client/lib/l10n/
git commit -m "feat(cli-presets): update agent section to show active preset

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Remove deprecated files and helpers

**Files:**
- Remove: `client/lib/pages/home_workspace/project/config/project_cli_defaults_section.dart`
- Remove: `client/lib/pages/home_workspace/project/config/project_cli_config_list.dart`
- Remove: `client/lib/pages/home_workspace/project/config/project_cli_config_helpers.dart`
- Remove: `client/lib/pages/home_workspace/project/config/project_cli_effort_helpers.dart`

- [ ] **Step 1: Verify no remaining references**

```bash
cd client && grep -r "project_cli_defaults_section\|project_cli_config_list\|project_cli_config_helpers\|project_cli_effort_helpers" lib/ --include="*.dart"
```

Expected: No output (all references already removed in tasks 10-11).

If any remaining references exist, update those files to remove the imports.

- [ ] **Step 2: Delete files**

```bash
rm client/lib/pages/home_workspace/project/config/project_cli_defaults_section.dart
rm client/lib/pages/home_workspace/project/config/project_cli_config_list.dart
rm client/lib/pages/home_workspace/project/config/project_cli_config_helpers.dart
rm client/lib/pages/home_workspace/project/config/project_cli_effort_helpers.dart
```

- [ ] **Step 3: Verify compilation**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/config/
git commit -m "refactor(cli-presets): remove deprecated per-CLI config files

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Final integration — run full test suite and fix issues

- [ ] **Step 1: Run all non-integration tests**

```bash
cd client && flutter test --exclude-tags integration
```

Expected: All tests pass. If any fail, fix them.

- [ ] **Step 2: Run flutter analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: No errors.

- [ ] **Step 3: Fix any remaining compilation or test issues**

Address any failures from steps 1-2.

- [ ] **Step 4: Commit final fixes**

```bash
git add -A
git commit -m "fix(cli-presets): resolve remaining compilation and test issues

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Dependency Order

Tasks must run sequentially due to model changes rippling through the codebase:
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13

## Spec Coverage Checklist

- [x] CliPreset model → Task 1
- [x] CliPresetsRepository → Task 2
- [x] CliPresetsCubit → Task 3
- [x] ProjectProfile simplification → Task 4
- [x] ProjectAgentConfig simplification → Task 4
- [x] Global DI wiring → Task 5
- [x] ProjectProfileCubit updates → Task 6
- [x] Config profile resolution → Task 7
- [x] Session launch updates → Task 7
- [x] CliPresetEditDialog → Task 8
- [x] CliPresetsManageDialog → Task 9
- [x] Sidebar preset dropdown → Task 10
- [x] Agent section update → Task 11
- [x] Remove deprecated code → Task 12
- [x] Full test suite pass → Task 13
- [x] Edge cases (empty, deleted preset, missing provider) → handled in cubit + UI tasks
