# P0 — 四旋钮 → RuntimeTarget + targets.json 注册表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 storage backend / connection mode / active SSH profile / WSL distro 四个全局旋钮折成单一 `RuntimeTarget`，新增独立 `targets.json` 注册表持有目标列表与 `defaultTargetId`，并把 `isSshMode` 的多重推导归一到单一来源——**行为完全不变**（单 target = 今天）。

**Architecture:** 新增 `RuntimeTarget` 值对象 + `targets.json`（`TargetsRepository`）+ `RuntimeTargetRegistry`（合并/对账/一次性迁移）。`RuntimeStorageContext` 加 `installForTarget` 把 target 映射成既有 `resolve()` 入参后复用（**单例/resolve 不动**）。存储 install、传输工厂、`ConnectionModeService`、`StorageRoots` 全部改由单一 `RuntimeTarget Function() defaultTargetResolver` 推导。UI 控件保持现状但漏斗汇入 `defaultTargetId`（旧字段双写一个版本周期供回滚）。

**Tech Stack:** Dart / Flutter，`flutter_bloc`，`package:flutter_test`；fs/subprocess 经构造注入 mock（见 `client/test/support/`）。

**Branch:** 建立在 `feat/workspace-folders-preparation`（预备阶段已提交）之上——从该分支切 `feat/p0-runtime-target` 或在其后继续。

## Global Constraints

- **行为不变**：单 target 必须复刻今天 local/wsl/ssh/Android 全路径；任何语义差异都是 bug。
- **单例不动**：`RuntimeStorageContext._current`、`resolve()`、`_resolveNative/_resolveWsl/_resolveSsh` **不改**（去单例属 P2）。只新增 `installForTarget` 映射层。
- **不引入**：多机解析、控制面/工作面拆分、反向隧道、`remoteOs` 探测、Windows-remote 分支、"选 target" UI（分属 P1–P3）。
- id 命名固定：`'local'` / `'wsl:<distro>'` / `'ssh:<profileId>'`（与预备阶段 `WorkspaceFolder.targetId='local'` 对齐）。
- `defaultTargetId` 权威在 `targets.json`；`SessionPreferences.connectionMode`/`windowsStorageBackend` 与 `selected_profile.txt` 保留双写一个版本周期（迁移只读不毁）。
- 设计权威：[docs/superpowers/specs/2026-06-22-p0-runtime-target-design.md](../specs/2026-06-22-p0-runtime-target-design.md)。
- 完成判据（每任务结尾及总验收）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
- 频繁提交：每任务 ≥1 commit，前缀 `feat:`/`refactor:`/`test:`。

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `client/lib/models/runtime_target.dart` | `RuntimeTarget`/`RuntimeKind`/`RemoteOs` + id 解析辅助 | 新增 |
| `client/lib/services/storage/targets_repository.dart` | `TargetsRegistryFile` + 读写 `targets.json` | 新增 |
| `client/lib/services/storage/runtime_target_registry.dart` | 合并/对账/一次性迁移、`defaultTarget`、`setDefaultTargetId` | 新增 |
| `client/lib/services/storage/app_storage.dart` | `AppPaths.targetsFile` | 改 |
| `client/lib/services/storage/runtime_storage_context.dart` | `installForTarget`（映射层；resolve/单例不动） | 改 |
| `client/lib/services/app/connection_mode_service.dart` | `isSshMode` 由 `defaultTargetResolver` 推导 | 改 |
| `client/lib/cubits/chat/chat_session_shell_factory.dart` | 传输选择由 `defaultTargetResolver` 推导 | 改 |
| `client/lib/services/storage/storage_resolver.dart` | `StorageRoots` 判据来源换 target | 改 |
| `client/lib/app/app_shell.dart` | 装配 registry；删两处内联 isSshMode；install/reinstall/StorageRoots/factory 从 registry 取 | 改 |
| `client/lib/cubits/ssh_profile_cubit.dart` | 选 profile/改模式时 `setDefaultTargetId` 漏斗 | 改 |
| 对应 `client/test/...` | 单测 | 新增/改 |

---

### Task 1: `RuntimeTarget` 值对象 + id 解析辅助

**Files:**
- Create: `client/lib/models/runtime_target.dart`
- Test: `client/test/models/runtime_target_test.dart`

**Interfaces:**
- Produces:
  - `enum RuntimeKind { local, wsl, ssh }`, `enum RemoteOs { posix, windows }`
  - `class RuntimeTarget { const RuntimeTarget({required String id, required String label, required RuntimeKind kind, String? sshProfileId, String? wslDistro, RemoteOs? remoteOs}); static const String localId='local'; factory RuntimeTarget.local({String label}); factory RuntimeTarget.wsl(String distro,{String? label}); factory RuntimeTarget.ssh(String profileId,{required String label}); factory RuntimeTarget.fromJson(Map); Map toJson(); RuntimeTarget copyWith({...}); }`
  - `RuntimeKind runtimeKindOfId(String id)`, `String? sshProfileIdOfId(String id)`, `String? wslDistroOfId(String id)`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/runtime_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';

void main() {
  test('factories build canonical ids', () {
    expect(RuntimeTarget.local().id, 'local');
    expect(RuntimeTarget.wsl('Ubuntu').id, 'wsl:Ubuntu');
    expect(RuntimeTarget.ssh('p1', label: 'box').id, 'ssh:p1');
  });

  test('id parse helpers', () {
    expect(runtimeKindOfId('local'), RuntimeKind.local);
    expect(runtimeKindOfId('wsl:Ubuntu'), RuntimeKind.wsl);
    expect(runtimeKindOfId('ssh:p1'), RuntimeKind.ssh);
    expect(wslDistroOfId('wsl:Ubuntu'), 'Ubuntu');
    expect(sshProfileIdOfId('ssh:p1'), 'p1');
    expect(sshProfileIdOfId('local'), isNull);
  });

  test('json round-trip preserves payload and null remoteOs', () {
    final t = RuntimeTarget.ssh('p1', label: 'box');
    final r = RuntimeTarget.fromJson(t.toJson());
    expect(r.id, 'ssh:p1');
    expect(r.kind, RuntimeKind.ssh);
    expect(r.sshProfileId, 'p1');
    expect(r.remoteOs, isNull);
  });

  test('wsl target carries distro', () {
    final r = RuntimeTarget.fromJson(RuntimeTarget.wsl('Debian').toJson());
    expect(r.kind, RuntimeKind.wsl);
    expect(r.wslDistro, 'Debian');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/models/runtime_target_test.dart`
Expected: FAIL — `runtime_target.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/models/runtime_target.dart
import 'package:flutter/foundation.dart';

/// Where files live and processes run for a unit of work. P0: one global
/// default target reproduces today's behavior; P2 attaches targets per folder.
enum RuntimeKind { local, wsl, ssh }

/// Probed for ssh targets at connect (P3). P0 always null.
enum RemoteOs { posix, windows }

RuntimeKind runtimeKindOfId(String id) {
  if (id.startsWith('wsl:')) return RuntimeKind.wsl;
  if (id.startsWith('ssh:')) return RuntimeKind.ssh;
  return RuntimeKind.local;
}

String? wslDistroOfId(String id) =>
    id.startsWith('wsl:') ? id.substring(4) : null;

String? sshProfileIdOfId(String id) =>
    id.startsWith('ssh:') ? id.substring(4) : null;

@immutable
class RuntimeTarget {
  const RuntimeTarget({
    required this.id,
    required this.label,
    required this.kind,
    this.sshProfileId,
    this.wslDistro,
    this.remoteOs,
  });

  static const String localId = 'local';

  factory RuntimeTarget.local({String label = 'This device'}) =>
      const RuntimeTarget(id: localId, label: 'This device', kind: RuntimeKind.local)
          .copyWith(label: label);

  factory RuntimeTarget.wsl(String distro, {String? label}) => RuntimeTarget(
        id: 'wsl:$distro',
        label: label ?? 'WSL · $distro',
        kind: RuntimeKind.wsl,
        wslDistro: distro,
      );

  factory RuntimeTarget.ssh(String profileId, {required String label}) =>
      RuntimeTarget(
        id: 'ssh:$profileId',
        label: label,
        kind: RuntimeKind.ssh,
        sshProfileId: profileId,
      );

  final String id;
  final String label;
  final RuntimeKind kind;
  final String? sshProfileId;
  final String? wslDistro;
  final RemoteOs? remoteOs;

  factory RuntimeTarget.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? localId;
    final kindRaw = json['kind'] as String?;
    final kind = RuntimeKind.values.firstWhere(
      (e) => e.name == kindRaw,
      orElse: () => runtimeKindOfId(id),
    );
    final osRaw = json['remoteOs'] as String?;
    return RuntimeTarget(
      id: id,
      label: json['label'] as String? ?? id,
      kind: kind,
      sshProfileId: json['sshProfileId'] as String? ?? sshProfileIdOfId(id),
      wslDistro: json['wslDistro'] as String? ?? wslDistroOfId(id),
      remoteOs: osRaw == null
          ? null
          : RemoteOs.values.firstWhere((e) => e.name == osRaw,
              orElse: () => RemoteOs.posix),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        if (sshProfileId != null) 'sshProfileId': sshProfileId,
        if (wslDistro != null) 'wslDistro': wslDistro,
        if (remoteOs != null) 'remoteOs': remoteOs!.name,
      };

  RuntimeTarget copyWith({
    String? id,
    String? label,
    RuntimeKind? kind,
    String? sshProfileId,
    String? wslDistro,
    RemoteOs? remoteOs,
  }) =>
      RuntimeTarget(
        id: id ?? this.id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        sshProfileId: sshProfileId ?? this.sshProfileId,
        wslDistro: wslDistro ?? this.wslDistro,
        remoteOs: remoteOs ?? this.remoteOs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeTarget &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          kind == other.kind &&
          sshProfileId == other.sshProfileId &&
          wslDistro == other.wslDistro &&
          remoteOs == other.remoteOs;

  @override
  int get hashCode =>
      Object.hash(id, label, kind, sshProfileId, wslDistro, remoteOs);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/models/runtime_target_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/runtime_target.dart client/test/models/runtime_target_test.dart
git commit -m "feat: add RuntimeTarget value object and id parse helpers"
```

---

### Task 2: `targets.json` 位置 + `TargetsRepository`

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart` (add `AppPaths.targetsFile`)
- Create: `client/lib/services/storage/targets_repository.dart`
- Test: `client/test/services/storage/targets_repository_test.dart`

**Interfaces:**
- Consumes: `RuntimeTarget` (Task 1).
- Produces:
  - `class TargetsRegistryFile { const TargetsRegistryFile({int schemaVersion=1, String defaultTargetId=RuntimeTarget.localId, String wslDistro='', List<RuntimeTarget> targets=const []}); factory fromJson(Map); Map toJson(); copyWith(...); }`
  - `class TargetsRepository { TargetsRepository({String? rootDir, Filesystem? fs}); Future<TargetsRegistryFile> load(); Future<void> save(TargetsRegistryFile); Future<bool> exists(); }`
  - `String get AppPaths.targetsFile`

- [ ] **Step 1: Add `AppPaths.targetsFile`** — in `app_storage.dart` near `sshProfilesDir` (line ~268):

```dart
  String get targetsFile => _ctx.join(basePath, 'targets.json');
```

- [ ] **Step 2: Write the failing test**

```dart
// client/test/services/storage/targets_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
// Use the in-memory Filesystem already used by other storage tests
// (see client/test for the InMemory/Local fs helper pattern).

void main() {
  test('missing file loads empty defaults', () async {
    final repo = TargetsRepository(rootDir: '/root', fs: /* in-memory fs */ null!);
    expect(await repo.exists(), isFalse);
    final loaded = await repo.load();
    expect(loaded.defaultTargetId, 'local');
    expect(loaded.targets, isEmpty);
  });

  test('save then load round-trips', () async {
    final repo = TargetsRepository(rootDir: '/root', fs: /* in-memory fs */ null!);
    await repo.save(TargetsRegistryFile(
      defaultTargetId: 'ssh:p1',
      wslDistro: 'Ubuntu',
      targets: [RuntimeTarget.ssh('p1', label: 'box')],
    ));
    final loaded = await repo.load();
    expect(loaded.defaultTargetId, 'ssh:p1');
    expect(loaded.wslDistro, 'Ubuntu');
    expect(loaded.targets.single.id, 'ssh:p1');
  });
}
```

> Fill the `null!` fs by copying the in-memory `Filesystem` wiring used in existing storage tests (e.g. `ssh_profile_repository` style or the `LocalFilesystem` over a temp dir). Do not invent a new fs.

- [ ] **Step 3: Run to verify it fails**

Run: `cd client && flutter test test/services/storage/targets_repository_test.dart`
Expected: FAIL — `targets_repository.dart` not found.

- [ ] **Step 4: Write minimal implementation**

```dart
// client/lib/services/storage/targets_repository.dart
import 'dart:convert';

import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import 'app_storage.dart';

class TargetsRegistryFile {
  const TargetsRegistryFile({
    this.schemaVersion = 1,
    this.defaultTargetId = RuntimeTarget.localId,
    this.wslDistro = '',
    this.targets = const [],
  });

  final int schemaVersion;
  final String defaultTargetId;
  final String wslDistro;
  final List<RuntimeTarget> targets;

  factory TargetsRegistryFile.fromJson(Map<String, Object?> json) {
    final raw = json['targets'];
    return TargetsRegistryFile(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      defaultTargetId: json['defaultTargetId'] as String? ?? RuntimeTarget.localId,
      wslDistro: json['wslDistro'] as String? ?? '',
      targets: raw is List
          ? [
              for (final e in raw)
                if (e is Map<String, Object?>) RuntimeTarget.fromJson(e),
            ]
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'defaultTargetId': defaultTargetId,
        'wslDistro': wslDistro,
        'targets': targets.map((t) => t.toJson()).toList(),
      };

  TargetsRegistryFile copyWith({
    String? defaultTargetId,
    String? wslDistro,
    List<RuntimeTarget>? targets,
  }) =>
      TargetsRegistryFile(
        schemaVersion: schemaVersion,
        defaultTargetId: defaultTargetId ?? this.defaultTargetId,
        wslDistro: wslDistro ?? this.wslDistro,
        targets: targets ?? this.targets,
      );
}

class TargetsRepository {
  TargetsRepository({String? rootDir, Filesystem? fs})
      : _rootOverride = rootDir,
        _fsOverride = fs;

  final String? _rootOverride;
  final Filesystem? _fsOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _file => _rootOverride != null
      ? _fs.pathContext.join(_rootOverride!, 'targets.json')
      : AppStorage.paths.targetsFile;

  Future<bool> exists() async => (await _fs.stat(_file)).isFile;

  Future<TargetsRegistryFile> load() async {
    if (!await exists()) return const TargetsRegistryFile();
    try {
      final raw = await _fs.readString(_file);
      if (raw == null || raw.isEmpty) return const TargetsRegistryFile();
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) return TargetsRegistryFile.fromJson(json);
    } on Object {
      // fall through to defaults
    }
    return const TargetsRegistryFile();
  }

  Future<void> save(TargetsRegistryFile file) async {
    final dir = _fs.pathContext.dirname(_file);
    await _fs.ensureDir(dir);
    await _fs.atomicWrite(_file, jsonEncode(file.toJson()));
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd client && flutter test test/services/storage/targets_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/storage/app_storage.dart client/lib/services/storage/targets_repository.dart client/test/services/storage/targets_repository_test.dart
git commit -m "feat: add targets.json registry file and TargetsRepository"
```

---

### Task 3: `RuntimeTargetRegistry`（合并/对账/一次性迁移）

**Files:**
- Create: `client/lib/services/storage/runtime_target_registry.dart`
- Test: `client/test/services/storage/runtime_target_registry_test.dart`

**Interfaces:**
- Consumes: `TargetsRepository`/`TargetsRegistryFile` (Task 2), `SshProfileRepository` (`loadAll`, `loadSelectedProfileId`), `RuntimeTarget` (Task 1).
- Produces:
  - `class RuntimeTargetRegistry { RuntimeTargetRegistry({required TargetsRepository repo, required SshProfileRepository sshProfileRepo, required bool isWindows, required bool isAndroid}); Future<List<RuntimeTarget>> listTargets(); Future<RuntimeTarget> defaultTarget(); Future<void> setDefaultTargetId(String id); Future<String> wslDistro(); Future<void> migrateIfNeeded({required ConnectionMode legacyMode, required WindowsStorageBackend legacyBackend, required String? parsedWslDistro}); }`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/storage/runtime_target_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/windows_storage_backend.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
// Build TargetsRepository + SshProfileRepository over a shared in-memory fs root
// (reuse existing storage-test fs helper).

void main() {
  test('migration: localPty + native -> default local', () async {
    final reg = /* registry over empty fs, isWindows:false, isAndroid:false */ null!;
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.localPty,
      legacyBackend: WindowsStorageBackend.native,
      parsedWslDistro: null,
    );
    expect((await reg.defaultTarget()).id, 'local');
  });

  test('migration: ssh + selected profile -> ssh:<id> and persists target', () async {
    // seed ssh_profiles with profile p1 + selected_profile.txt = p1
    final reg = /* registry, isWindows:false, isAndroid:false */ null!;
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.ssh,
      legacyBackend: WindowsStorageBackend.native,
      parsedWslDistro: null,
    );
    final def = await reg.defaultTarget();
    expect(def.id, 'ssh:p1');
    expect(def.kind, RuntimeKind.ssh);
    expect((await reg.listTargets()).any((t) => t.id == 'ssh:p1'), isTrue);
  });

  test('migration: windows wsl backend -> wsl:<distro>', () async {
    final reg = /* registry, isWindows:true, isAndroid:false */ null!;
    await reg.migrateIfNeeded(
      legacyMode: ConnectionMode.localPty,
      legacyBackend: WindowsStorageBackend.wsl,
      parsedWslDistro: 'Ubuntu',
    );
    expect((await reg.defaultTarget()).id, 'wsl:Ubuntu');
    expect(await reg.wslDistro(), 'Ubuntu');
  });

  test('listTargets always includes implicit local', () async {
    final reg = /* registry over empty fs */ null!;
    expect((await reg.listTargets()).any((t) => t.id == 'local'), isTrue);
  });

  test('reconcile: new ssh profile appears; deleted profile pruned', () async {
    // start with persisted ssh target p1; ssh_profiles now has p1 + p2, missing p3
    final reg = /* registry with persisted targets [ssh:p1, ssh:p3], profiles [p1,p2] */ null!;
    final ids = (await reg.listTargets()).map((t) => t.id).toSet();
    expect(ids.contains('ssh:p1'), isTrue);
    expect(ids.contains('ssh:p2'), isTrue); // newly added & written back
    expect(ids.contains('ssh:p3'), isFalse); // orphan pruned
  });

  test('defaultTarget falls back to local when id points at deleted profile', () async {
    final reg = /* registry: defaultTargetId 'ssh:gone', no such profile */ null!;
    expect((await reg.defaultTarget()).id, 'local');
  });
}
```

> Build the registry over a shared in-memory fs root; seed `ssh_profiles/profiles.json` + `selected_profile.txt` via `SshProfileRepository(rootDir, fs).saveAll/saveSelectedProfileId`. Do not invent new fs plumbing.

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/storage/runtime_target_registry_test.dart`
Expected: FAIL — registry not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/services/storage/runtime_target_registry.dart
import '../../models/connection_mode.dart';
import '../../models/runtime_target.dart';
import '../../models/windows_storage_backend.dart';
import '../../repositories/ssh_profile_repository.dart';
import 'targets_repository.dart';

class RuntimeTargetRegistry {
  RuntimeTargetRegistry({
    required TargetsRepository repo,
    required SshProfileRepository sshProfileRepo,
    required this.isWindows,
    required this.isAndroid,
  })  : _repo = repo,
        _sshProfileRepo = sshProfileRepo;

  final TargetsRepository _repo;
  final SshProfileRepository _sshProfileRepo;
  final bool isWindows;
  final bool isAndroid;

  /// One-time: build targets.json from legacy sources when it does not exist.
  Future<void> migrateIfNeeded({
    required ConnectionMode legacyMode,
    required WindowsStorageBackend legacyBackend,
    required String? parsedWslDistro,
  }) async {
    if (await _repo.exists()) return;
    final profiles = await _sshProfileRepo.loadAll();
    final selected = await _sshProfileRepo.loadSelectedProfileId();
    final distro = (parsedWslDistro ?? '').trim();

    final sshTargets = [
      for (final p in profiles) RuntimeTarget.ssh(p.id, label: p.name),
    ];

    String defaultId;
    if (legacyMode == ConnectionMode.ssh && selected.isNotEmpty &&
        profiles.any((p) => p.id == selected)) {
      defaultId = 'ssh:$selected';
    } else if (isWindows && legacyBackend == WindowsStorageBackend.wsl &&
        distro.isNotEmpty) {
      defaultId = 'wsl:$distro';
    } else if (isAndroid && sshTargets.isNotEmpty) {
      defaultId = sshTargets.first.id;
    } else {
      defaultId = RuntimeTarget.localId;
    }

    await _repo.save(TargetsRegistryFile(
      defaultTargetId: defaultId,
      wslDistro: distro,
      targets: sshTargets,
    ));
  }

  Future<String> wslDistro() async => (await _repo.load()).wslDistro;

  /// Merge persisted ssh targets with live ssh_profiles (add new, prune orphans;
  /// write back if changed) plus implicit local / wsl entries.
  Future<List<RuntimeTarget>> listTargets() async {
    final file = await _repo.load();
    final profiles = await _sshProfileRepo.loadAll();
    final byId = {for (final p in profiles) p.id: p};

    final reconciled = <RuntimeTarget>[];
    var changed = false;
    for (final t in file.targets) {
      final pid = t.sshProfileId;
      if (pid != null && byId.containsKey(pid)) {
        reconciled.add(t.copyWith(label: byId[pid]!.name));
      } else {
        changed = true; // orphan dropped
      }
    }
    final existingPids =
        reconciled.map((t) => t.sshProfileId).whereType<String>().toSet();
    for (final p in profiles) {
      if (!existingPids.contains(p.id)) {
        reconciled.add(RuntimeTarget.ssh(p.id, label: p.name));
        changed = true;
      }
    }
    if (changed) {
      await _repo.save(file.copyWith(targets: reconciled));
    }

    return [
      RuntimeTarget.local(),
      if (isWindows && file.wslDistro.trim().isNotEmpty)
        RuntimeTarget.wsl(file.wslDistro.trim()),
      ...reconciled,
    ];
  }

  Future<RuntimeTarget> defaultTarget() async {
    final file = await _repo.load();
    final all = await listTargets();
    return all.firstWhere(
      (t) => t.id == file.defaultTargetId,
      orElse: () => RuntimeTarget.local(),
    );
  }

  Future<void> setDefaultTargetId(String id) async {
    final file = await _repo.load();
    await _repo.save(file.copyWith(defaultTargetId: id));
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/storage/runtime_target_registry_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/runtime_target_registry.dart client/test/services/storage/runtime_target_registry_test.dart
git commit -m "feat: add RuntimeTargetRegistry with migration, merge and reconcile"
```

---

### Task 4: `RuntimeStorageContext.installForTarget`（映射层，单例/resolve 不动）

**Files:**
- Modify: `client/lib/services/storage/runtime_storage_context.dart`
- Test: `client/test/services/storage/install_for_target_test.dart`

**Interfaces:**
- Consumes: `RuntimeTarget` (Task 1); existing `resolve()`/`install()`.
- Produces: `static Future<RuntimeStorageContext> RuntimeStorageContext.installForTarget(RuntimeTarget target, {SshProfile? sshProfile, SshClientFactory? sshClientFactory, RemoteSshStoragePathResolver? remotePathResolver, required String nativeAppDataPath, String? nativeHome, String? nativeCwd})`

- [ ] **Step 1: Write the failing test** (golden equivalence — behavior unchanged)

```dart
// client/test/services/storage/install_for_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  tearDown(RuntimeStorageContext.resetForTesting);

  test('local target installs native backend (== legacy native install)', () async {
    final viaTarget = await RuntimeStorageContext.installForTarget(
      RuntimeTarget.local(),
      nativeAppDataPath: '/data/app',
      nativeHome: '/home/u',
      nativeCwd: '/home/u/proj',
    );
    expect(viaTarget.mode, StorageBackendMode.native);
    expect(viaTarget.appDataRoot, '/data/app');

    final legacy = await RuntimeStorageContext.resolve(
      isSshMode: false,
      nativeAppDataPath: '/data/app',
      nativeHome: '/home/u',
      nativeCwd: '/home/u/proj',
    );
    expect(viaTarget.mode, legacy.mode);
    expect(viaTarget.appDataRoot, legacy.appDataRoot);
    expect(viaTarget.usesPosixPaths, legacy.usesPosixPaths);
  });
}
```

> ssh/wsl equivalence cases require platform/ssh mocks already used in existing `runtime_storage_context` tests — add cases mirroring those harnesses (`installForTarget(RuntimeTarget.wsl('Ubuntu'))` ≡ `resolve(windowsStorageBackend: wsl, wslDistro: 'Ubuntu')`; ssh case ≡ `resolve(isSshMode:true, sshProfile:..., sshClientFactory:...)`). Reuse the existing test's mock SSH/WSL plumbing; do not invent new mocks.

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/storage/install_for_target_test.dart`
Expected: FAIL — `installForTarget` undefined.

- [ ] **Step 3: Implement the mapping** — add to `RuntimeStorageContext` (do NOT touch `resolve`/`_resolve*`/`_current`):

```dart
  /// Installs the storage context for [target] by mapping its kind onto the
  /// existing [install] parameters. Single source of truth for P0; resolve()
  /// and the singleton are unchanged.
  static Future<RuntimeStorageContext> installForTarget(
    RuntimeTarget target, {
    SshProfile? sshProfile,
    SshClientFactory? sshClientFactory,
    RemoteSshStoragePathResolver? remotePathResolver,
    required String nativeAppDataPath,
    String? nativeHome,
    String? nativeCwd,
  }) {
    return install(
      isSshMode: target.kind == RuntimeKind.ssh,
      sshProfile: sshProfile,
      sshClientFactory: sshClientFactory,
      remotePathResolver: remotePathResolver,
      nativeAppDataPath: nativeAppDataPath,
      nativeHome: nativeHome,
      nativeCwd: nativeCwd,
      wslDistro: target.wslDistro,
      windowsStorageBackend: target.kind == RuntimeKind.wsl
          ? WindowsStorageBackend.wsl
          : WindowsStorageBackend.native,
    );
  }
```

Add `import '../../models/runtime_target.dart';` to the file.

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/storage/install_for_target_test.dart test/services/storage/`
Expected: PASS — new equivalence test + existing storage-context tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/runtime_storage_context.dart client/test/services/storage/install_for_target_test.dart
git commit -m "feat: add installForTarget mapping (resolve and singleton untouched)"
```

---

### Task 5: `ConnectionModeService` 归一到 `defaultTargetResolver`

**Files:**
- Modify: `client/lib/services/app/connection_mode_service.dart`
- Test: `client/test/services/connection_mode_service_test.dart` (create or extend)

**Interfaces:**
- Consumes: `RuntimeTarget` (Task 1).
- Produces: `ConnectionModeService({required RuntimeTarget Function() defaultTargetResolver, required bool Function() hasSshProfiles})` with `bool get isSshMode => defaultTargetResolver().kind == RuntimeKind.ssh;` and unchanged `requiresSshProfileSetup`. Keep `effectiveMode`/`preferredMode` returning `ConnectionMode` derived from the target (ssh→ssh else localPty) for back-compat callers.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/connection_mode_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';

void main() {
  test('isSshMode derives from default target kind', () {
    var target = RuntimeTarget.local();
    final svc = ConnectionModeService(
      defaultTargetResolver: () => target,
      hasSshProfiles: () => true,
    );
    expect(svc.isSshMode, isFalse);
    expect(svc.effectiveMode, ConnectionMode.localPty);

    target = RuntimeTarget.ssh('p1', label: 'box');
    expect(svc.isSshMode, isTrue);
    expect(svc.effectiveMode, ConnectionMode.ssh);
  });

  test('requiresSshProfileSetup when ssh and no profiles', () {
    final svc = ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
      hasSshProfiles: () => false,
    );
    expect(svc.requiresSshProfileSetup, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/services/connection_mode_service_test.dart`
Expected: FAIL — constructor signature mismatch.

- [ ] **Step 3: Implement**

```dart
import '../../models/connection_mode.dart';
import '../../models/runtime_target.dart';

class ConnectionModeService {
  const ConnectionModeService({
    required RuntimeTarget Function() defaultTargetResolver,
    required bool Function() hasSshProfiles,
  })  : _defaultTargetResolver = defaultTargetResolver,
        _hasSshProfiles = hasSshProfiles;

  final RuntimeTarget Function() _defaultTargetResolver;
  final bool Function() _hasSshProfiles;

  ConnectionMode get effectiveMode =>
      isSshMode ? ConnectionMode.ssh : ConnectionMode.localPty;
  ConnectionMode get preferredMode => effectiveMode;

  bool get isSshMode =>
      _defaultTargetResolver().kind == RuntimeKind.ssh;
  bool get isLocalMode => !isSshMode;

  bool get requiresSshProfileSetup => isSshMode && !_hasSshProfiles();
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/services/connection_mode_service_test.dart`
Expected: PASS. (app_shell still references old ctor — fixed in Task 7; this task's gate is the unit test + analyze of this file.)

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/app/connection_mode_service.dart client/test/services/connection_mode_service_test.dart
git commit -m "refactor: derive ConnectionModeService.isSshMode from RuntimeTarget"
```

---

### Task 6: 传输工厂 `chat_session_shell_factory` 归一到 target

**Files:**
- Modify: `client/lib/cubits/chat/chat_session_shell_factory.dart`
- Test: `client/test/cubits/chat_session_shell_factory_test.dart` (create or extend existing transport-selection test)

**Interfaces:**
- Consumes: `RuntimeTarget` (Task 1), `SshProfile` lookup by id.
- Produces: factory ctor takes `RuntimeTarget Function()? defaultTargetResolver` (replacing `connectionModeResolver` + the ssh-mode part of `sshProfileResolver`); `useSsh` ⇔ `target.kind == ssh && resolvedProfile != null`, where the profile is looked up from the target's `sshProfileId`.

- [ ] **Step 1: Write the failing test** asserting transport selection parity:

```dart
// Build the factory with defaultTargetResolver returning local -> expect LocalPty path;
// returning ssh:<id> with a matching profile -> expect Ssh path (sshProfileId wired through).
// Mirror the existing test that exercised connectionModeResolver==ssh.
```

(Implementer: extend whatever test currently covers `_connectionMode == ssh` selection; keep its mock transport starters.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/cubits/chat_session_shell_factory_test.dart`
Expected: FAIL — ctor/param mismatch.

- [ ] **Step 3: Implement** — replace `_connectionModeResolver`/`_connectionMode` usage:

```dart
  // ctor param:
  RuntimeTarget Function()? defaultTargetResolver,
  // ...
  final RuntimeTarget Function()? _defaultTargetResolver;

  RuntimeTarget get _target =>
      _defaultTargetResolver?.call() ?? RuntimeTarget.local();

  bool get _useSsh =>
      _target.kind == RuntimeKind.ssh && _resolveProfile() != null;

  SshProfile? _resolveProfile() {
    final pid = _target.sshProfileId;
    if (pid == null) return null;
    return _sshProfileResolver?.call(pid); // resolver now takes an id
  }
```

Adjust `_sshProfileResolver` type to `SshProfile? Function(String profileId)?` (look up by id) and update the ssh branch (line ~68/100) to use `_resolveProfile()` and `profile.id`. Add `import '../../models/runtime_target.dart';`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd client && flutter test test/cubits/chat_session_shell_factory_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/chat_session_shell_factory.dart client/test/cubits/chat_session_shell_factory_test.dart
git commit -m "refactor: select transport from RuntimeTarget in shell factory"
```

---

### Task 7: `app_shell` 装配 + `StorageRoots` + SshProfileCubit 漏斗（端到端归一）

**Files:**
- Modify: `client/lib/app/app_shell.dart` (install :229, reinstall :318, ConnectionModeService :312, StorageRoots :330, inline isSshMode :232/:291)
- Modify: `client/lib/services/storage/storage_resolver.dart` (`StorageRoots` judge source)
- Modify: `client/lib/cubits/ssh_profile_cubit.dart` (`setDefaultTargetId` funnel)

**Interfaces:**
- Consumes: `RuntimeTargetRegistry` (Task 3), `installForTarget` (Task 4), `ConnectionModeService` (Task 5), shell factory (Task 6).
- Produces: a single `RuntimeTarget Function() defaultTargetResolver` closure (caches the last `registry.defaultTarget()`), wired into ConnectionModeService, StorageRoots, shell factory, install/reinstall.

- [ ] **Step 1: Build the registry + resolver in `buildAppShell`** (after `sshProfileRepo` is created, before `connectionModeService`):

```dart
  final targetsRepo = TargetsRepository();
  final runtimeTargetRegistry = RuntimeTargetRegistry(
    repo: targetsRepo,
    sshProfileRepo: sshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
  );
  await runtimeTargetRegistry.migrateIfNeeded(
    legacyMode: sessionPreferencesCubit.state.preferences.connectionMode,
    legacyBackend: windowsStorageBackend(),
    parsedWslDistro: wslDistroFromPrefs(),
  );
  var _cachedDefaultTarget = await runtimeTargetRegistry.defaultTarget();
  RuntimeTarget defaultTargetResolver() => _cachedDefaultTarget;
  Future<void> refreshDefaultTarget() async {
    _cachedDefaultTarget = await runtimeTargetRegistry.defaultTarget();
  }
```

- [ ] **Step 2: Replace install/reinstall + inline isSshMode**

- Bootstrap install (line ~229): replace `RuntimeStorageContext.install(isSshMode: Platform.isAndroid || ...connectionMode==ssh, ..., wslDistro: parseWslDistro(...), windowsStorageBackend: ...)` with:
```dart
  await RuntimeStorageContext.installForTarget(
    defaultTargetResolver(),
    sshProfile: null,
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
```
> Note: the migration already folded Android/connectionMode into `defaultTargetId`; `installForTarget` + `resolve()`'s existing `Platform.isAndroid` guard keep Android behavior identical.

- `reinstallStorageContext` (line ~318): change body to `await refreshDefaultTarget(); return RuntimeStorageContext.installForTarget(defaultTargetResolver(), sshProfile: sshProfileCubit.state.selectedProfile, sshClientFactory: sshClientFactory, nativeAppDataPath: nativeAppDataPath, nativeHome: ..., nativeCwd: defaultWorkspaceDirectory);`

- `ConnectionModeService` (line ~312): `defaultTargetResolver: defaultTargetResolver` (drop `readPreferredMode`).

- Inline `enableRemoteCliDiscovery` (line ~289-292) and any remaining `...connectionMode == ConnectionMode.ssh`: replace with `connectionModeService.isSshMode` (declare `connectionModeService` earlier or use `defaultTargetResolver().kind == RuntimeKind.ssh`).

- [ ] **Step 3: `StorageRoots` source swap** — in `storage_resolver.dart`, change the `isSshMode`/`sshProfileResolver` inputs to be driven by the target (either pass `defaultTargetResolver` and derive, or keep the two closures but wire them from the resolver in app_shell):
```dart
  storageRoots = StorageRoots(
    isSshMode: () => defaultTargetResolver().kind == RuntimeKind.ssh,
    sshProfileResolver: () => sshProfileCubit.state.selectedProfile,
    reinstallContext: reinstallStorageContext,
  );
```
(No semantic change to `_resolveUncached`; only the source of the booleans.)

- [ ] **Step 4: Shell factory wiring** (line ~575-580): pass `defaultTargetResolver: defaultTargetResolver` and `sshProfileResolver: (id) => sshProfileCubit.state.profiles.firstWhereOrNull((p) => p.id == id)` instead of `connectionModeResolver`/`sshProfileResolver`.

- [ ] **Step 5: SshProfileCubit funnel** — wherever the active profile changes / connection mode toggles / Windows backend toggles, add a `runtimeTargetRegistry.setDefaultTargetId(...)` call mirroring §5 table, then `refreshDefaultTarget()`:
  - On active profile change (`onActiveProfileChanged`, app_shell ~293): if ssh mode, `await runtimeTargetRegistry.setDefaultTargetId('ssh:${selectedId}')`.
  - On connection-mode toggle handler (find the `setConnectionMode` call site): set `'local'`/`'wsl:<distro>'`/`'ssh:<selectedId>'` accordingly + keep dual-writing `connectionMode` (legacy).
  - On Windows backend toggle: set `'local'`↔`'wsl:<distro>'` + keep dual-writing `windowsStorageBackend`.
  - Always `await refreshDefaultTarget()` before `reinstallStorageContext()`.

> Keep legacy writes (`connectionMode`, `windowsStorageBackend`, `selected_profile.txt`) intact — dual-write window per Q7.

- [ ] **Step 6: Analyze + full regression**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze CLEAN; all tests PASS. Pay attention to any test constructing `ConnectionModeService`/`ChatSessionShellFactory`/`RuntimeStorageContext.install` directly — update them to the new wiring.

- [ ] **Step 7: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/services/storage/storage_resolver.dart client/lib/cubits/ssh_profile_cubit.dart
git commit -m "refactor: wire RuntimeTargetRegistry as single source for storage+transport"
```

---

### Task 8: 行为不变回归矩阵 + 手验金路径文档

**Files:**
- Create: `client/test/services/storage/p0_behavior_parity_test.dart`
- Modify: design/plan docs if any gap found (no production code).

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the parity matrix test** — assert each kind's resolved context matches the legacy param-based call:

```dart
// For local / wsl(Ubuntu) / ssh(profile) and the Android path, assert
// installForTarget(target) yields the same (mode, appDataRoot, usesPosixPaths)
// as the corresponding legacy resolve(...) call. Reuse mocks from Task 4.
// Also assert RuntimeTargetRegistry migration produces the defaultTargetId that
// reproduces today's effective backend for each legacy preference combination.
```

- [ ] **Step 2: Run it**

Run: `cd client && flutter test test/services/storage/p0_behavior_parity_test.dart`
Expected: PASS.

- [ ] **Step 3: Full suite + analyze (acceptance)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze CLEAN; all tests PASS.

- [ ] **Step 4: Document manual golden paths** (CI can't cover PTY/SSH/WSL/Android). Append a short checklist to the design spec's §7 or a `docs/` note: (1) Linux desktop local launch; (2) Windows WSL backend launch; (3) desktop SSH profile launch; (4) Android forced-SSH launch — each must behave identically to pre-P0.

- [ ] **Step 5: Commit**

```bash
git add client/test/services/storage/p0_behavior_parity_test.dart docs/superpowers/specs/2026-06-22-p0-runtime-target-design.md
git commit -m "test: P0 behavior-parity matrix and manual golden-path notes"
```

---

## Self-Review

**Spec coverage:**
- §3.1 RuntimeTarget + id helpers → Task 1 ✅
- §3.2 targets.json + location → Task 2 ✅
- §3.3/§3.4 registry merge/reconcile + repository → Tasks 2/3 ✅
- §4 one-time migration + dual-write → Task 3 (migrateIfNeeded) + Task 7 (legacy writes kept) ✅
- §5 single-source isSshMode (ConnectionModeService, installForTarget, shell factory, StorageRoots, UI funnel) → Tasks 4/5/6/7 ✅
- §6 file map → all tasks ✅
- §7 test strategy incl. behavior-parity → Tasks 4/8 + per-task unit tests ✅
- §8 out-of-scope → Global Constraints enforce ✅

**Placeholder scan:** Tasks 2/3/4/6/8 mark in-memory-fs / mock wiring and the transport-test extension with explicit "reuse existing harness, do not invent" instructions — intentional reuse pointers, not content gaps. All production code steps carry complete code; the mapping/registry/model code is fully specified.

**Type consistency:** `RuntimeTarget`/`RuntimeKind`, `runtimeKindOfId`/`sshProfileIdOfId`/`wslDistroOfId`, `TargetsRegistryFile`, `RuntimeTargetRegistry.{listTargets,defaultTarget,setDefaultTargetId,wslDistro,migrateIfNeeded}`, `installForTarget`, `ConnectionModeService(defaultTargetResolver:…)` used identically across tasks. `defaultTargetId` authority in targets.json (per spec §2.1) consistent throughout.

**Behavior-unchanged guard (核心验收):** Task 4 golden-equivalence + Task 8 parity matrix prove `installForTarget(target)` ≡ legacy `resolve(...)` per kind; resolve()/singleton untouched (Global Constraint); legacy fields dual-written (Q7) for rollback. Each task ends with an independently runnable verification command; Task 7/8 run the full `analyze` + `test` gate.
