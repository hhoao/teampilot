# Workspace folders 收敛（远程执行架构「预备」阶段）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `Workspace`/`AppSession` 的 `primaryPath: String` + `additionalPaths: List<String>` 收敛为单一 `folders: List<WorkspaceFolder>`（本阶段 `targetId` 恒 `'local'`），收敛 `session_repository.dart` 的路径变异点，旧数据无损迁移、行为不变。

**Architecture:** 新增 `WorkspaceFolder` 值对象 + `foldersFromLegacyJson` 容忍读取器。两模型字段换 folders、暴露 `firstFolderPath`/`extraFolderPaths`/`folderPaths` 永久新 API。迁移窗口内临时保留 `@Deprecated primaryPath/additionalPaths` getter 与 factory 兼容入参，使 ~20 文件按批迁移时每步保持编译/测试绿；**最终任务删除全部脚手架**，达成 Q4(b) 硬切终态。`toJson` 双写旧字段 + `schemaVersion` bump 实现无损回滚。

**Tech Stack:** Dart / Flutter，`flutter_bloc`，`package:flutter_test`，仓库测试经构造注入 mock fs（见 `client/test/support/`）。

## Global Constraints

- 仅「预备」阶段；**不引入** `RuntimeTarget`、不动存储单例、不写非 `'local'` 的 `targetId` 逻辑（这些属 P0–P4）。
- 设计权威：[docs/superpowers/specs/2026-06-22-workspace-folders-preparation-design.md](../specs/2026-06-22-workspace-folders-preparation-design.md)。
- l10n 改动走 `app_en.arb`/`app_zh.arb`（本计划预计无 UI 文案变化）。
- 完成判据（每个任务结尾及总验收）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
- 所有路径经 `normalizeWorkspacePath`（`lib/utils/workspace_path_utils.dart`）规范化，语义不变。
- 仓库对外 API 在本阶段**保持 string 形参**（`createWorkspace(String primaryPath, {List<String> additionalPaths})` 等不变签名），folders 仅为内部表示。
- 频繁提交：每个任务至少一个 commit；commit message 用 `feat:`/`refactor:`/`test:` 前缀。

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `client/lib/models/workspace_folder.dart` | `WorkspaceFolder` 值对象 + `foldersFromLegacyJson` 读取器 | 新增 |
| `client/test/models/workspace_folder_test.dart` | 值对象 + 读取器单测 | 新增 |
| `client/lib/models/workspace.dart` | 字段换 folders、新 getter、序列化、factory 脚手架 | 改 |
| `client/test/models/workspace_test.dart` | 既有测试 + 新形状/旧形状/双写测试 | 改 |
| `client/lib/models/app_session.dart` | 同 Workspace 对称改造 | 改 |
| `client/test/models/app_session_folders_test.dart` | AppSession 迁移单测 | 新增 |
| `client/lib/repositories/session_repository.dart` | 6 处变异点收敛为 folders | 改 |
| `client/test/repositories/session_repository_folders_test.dart` | 仓库变异点回归 | 新增 |
| 批 A：services + cubits（8 文件，见 Task 6） | 读/构造点硬切 folders | 改 |
| 批 B：widgets + pages（~10 文件，见 Task 7） | 读/喂入点硬切 folders | 改 |
| 终态：上述全部模型文件 | 删除脚手架 getter / factory 兼容入参 | 改 |

---

### Task 1: `WorkspaceFolder` 值对象 + 旧 JSON 读取器

**Files:**
- Create: `client/lib/models/workspace_folder.dart`
- Test: `client/test/models/workspace_folder_test.dart`

**Interfaces:**
- Produces:
  - `class WorkspaceFolder { const WorkspaceFolder({required String path, String targetId = WorkspaceFolder.localTargetId}); static const String localTargetId = 'local'; final String path; final String targetId; factory WorkspaceFolder.fromJson(Map<String,Object?>); Map<String,Object?> toJson(); WorkspaceFolder copyWith({String? path, String? targetId}); }`
  - `List<WorkspaceFolder> foldersFromLegacyJson(Map<String,Object?> json)`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/workspace_folder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('defaults targetId to local and round-trips json', () {
    const f = WorkspaceFolder(path: '/tmp/repo');
    expect(f.targetId, 'local');
    final restored = WorkspaceFolder.fromJson(f.toJson());
    expect(restored.path, '/tmp/repo');
    expect(restored.targetId, 'local');
  });

  test('toJson always writes path and targetId', () {
    final json = const WorkspaceFolder(path: '/a', targetId: 'local').toJson();
    expect(json['path'], '/a');
    expect(json['targetId'], 'local');
  });

  test('foldersFromLegacyJson prefers new folders array', () {
    final folders = foldersFromLegacyJson({
      'folders': [
        {'path': '/a', 'targetId': 'local'},
        {'path': '/b', 'targetId': 'local'},
      ],
      'primaryPath': '/ignored',
      'additionalPaths': ['/ignored2'],
    });
    expect(folders.map((f) => f.path), ['/a', '/b']);
  });

  test('foldersFromLegacyJson upgrades legacy primaryPath + additionalPaths', () {
    final folders = foldersFromLegacyJson({
      'primaryPath': '/main',
      'additionalPaths': ['/x', '/y'],
    });
    expect(folders.map((f) => f.path), ['/main', '/x', '/y']);
    expect(folders.every((f) => f.targetId == 'local'), isTrue);
  });

  test('foldersFromLegacyJson tolerates empty primaryPath', () {
    final folders = foldersFromLegacyJson({
      'primaryPath': '',
      'additionalPaths': ['/only'],
    });
    expect(folders.map((f) => f.path), ['/only']);
  });

  test('foldersFromLegacyJson returns empty when nothing present', () {
    expect(foldersFromLegacyJson(<String, Object?>{}), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/workspace_folder_test.dart`
Expected: FAIL — `workspace_folder.dart` not found / `WorkspaceFolder` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// client/lib/models/workspace_folder.dart
import 'package:flutter/foundation.dart';

/// A workspace directory plus the machine ("target") it lives on.
///
/// Preparation phase: `targetId` is always [localTargetId]. P2 of the remote
/// execution architecture sets it to `ssh:*` / `wsl:*` per folder.
@immutable
class WorkspaceFolder {
  const WorkspaceFolder({required this.path, this.targetId = localTargetId});

  static const String localTargetId = 'local';

  final String path;
  final String targetId;

  factory WorkspaceFolder.fromJson(Map<String, Object?> json) {
    final id = (json['targetId'] as String?)?.trim();
    return WorkspaceFolder(
      path: json['path'] as String? ?? '',
      targetId: id == null || id.isEmpty ? localTargetId : id,
    );
  }

  Map<String, Object?> toJson() => {'path': path, 'targetId': targetId};

  WorkspaceFolder copyWith({String? path, String? targetId}) =>
      WorkspaceFolder(path: path ?? this.path, targetId: targetId ?? this.targetId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceFolder &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(path, targetId);
}

/// Reads `folders` if present, else upgrades legacy `primaryPath` +
/// `additionalPaths` into an all-`local` folder list (primaryPath first).
List<WorkspaceFolder> foldersFromLegacyJson(Map<String, Object?> json) {
  final raw = json['folders'];
  if (raw is List && raw.isNotEmpty) {
    return [
      for (final e in raw)
        if (e is Map<String, Object?>) WorkspaceFolder.fromJson(e),
    ];
  }
  final primary = (json['primaryPath'] as String? ?? '').trim();
  final add = json['additionalPaths'];
  final extra = add is List
      ? add.map((e) => '$e').where((s) => s.isNotEmpty)
      : const <String>[];
  return [
    if (primary.isNotEmpty) WorkspaceFolder(path: primary),
    for (final p in extra) WorkspaceFolder(path: p),
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/workspace_folder_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/workspace_folder.dart client/test/models/workspace_folder_test.dart
git commit -m "feat: add WorkspaceFolder value object and legacy folders reader"
```

---

### Task 2: `Workspace` 模型迁移到 folders（含脚手架）

**Files:**
- Modify: `client/lib/models/workspace.dart`
- Modify: `client/test/models/workspace_test.dart`

**Interfaces:**
- Consumes: `WorkspaceFolder`, `foldersFromLegacyJson` (Task 1).
- Produces (on `Workspace`):
  - `final List<WorkspaceFolder> folders;`
  - `String get firstFolderPath`, `List<String> get extraFolderPaths`, `List<String> get folderPaths`
  - SCAFFOLD (removed Task 8): `@Deprecated String get primaryPath`, `@Deprecated List<String> get additionalPaths`, and factory params `primaryPath` / `additionalPaths`.
  - `factory Workspace({required String workspaceId, List<WorkspaceFolder>? folders, String? primaryPath, List<String>? additionalPaths, String display, String defaultProfileId, WorkspaceIconRef icon, required int createdAt, int updatedAt, List<String> sessionIds})`
  - `WorkspacesIndex` `schemaVersion` 默认升至 `2`.

- [ ] **Step 1: Write the failing test** — append to `client/test/models/workspace_test.dart`

```dart
import 'package:teampilot/models/workspace_folder.dart';
// ... existing imports/tests stay ...

  test('folders round-trip and expose derived path getters', () {
    final ws = Workspace(
      workspaceId: 'p1',
      folders: const [
        WorkspaceFolder(path: '/main'),
        WorkspaceFolder(path: '/extra'),
      ],
      createdAt: 1,
    );
    expect(ws.firstFolderPath, '/main');
    expect(ws.extraFolderPaths, ['/extra']);
    expect(ws.folderPaths, ['/main', '/extra']);
    final restored = Workspace.fromJson(ws.toJson());
    expect(restored.folders.map((f) => f.path), ['/main', '/extra']);
    expect(restored.folders.every((f) => f.targetId == 'local'), isTrue);
  });

  test('reads legacy primaryPath + additionalPaths manifest', () {
    final restored = Workspace.fromJson({
      'workspaceId': 'p1',
      'primaryPath': '/main',
      'additionalPaths': ['/extra'],
      'createdAt': 1,
    });
    expect(restored.firstFolderPath, '/main');
    expect(restored.extraFolderPaths, ['/extra']);
  });

  test('toJson dual-writes legacy fields alongside folders', () {
    final ws = Workspace(
      workspaceId: 'p1',
      folders: const [WorkspaceFolder(path: '/main'), WorkspaceFolder(path: '/x')],
      createdAt: 1,
    );
    final json = ws.toJson();
    expect((json['folders'] as List).length, 2);
    expect(json['primaryPath'], '/main');
    expect(json['additionalPaths'], ['/x']);
  });

  test('legacy primaryPath/additionalPaths factory params still build folders', () {
    final ws = Workspace(
      workspaceId: 'p1',
      primaryPath: '/main',
      additionalPaths: const ['/x'],
      createdAt: 1,
    );
    expect(ws.folderPaths, ['/main', '/x']);
  });
```

Also update the existing first test: change `Workspace(... primaryPath: '/tmp/repo' ...)` stays compiling via the factory scaffold (no edit needed) — but assert `restored.firstFolderPath` equals `/tmp/repo` in addition to the existing `restored.primaryPath` deprecated check.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/workspace_test.dart`
Expected: FAIL — `folders` getter / `firstFolderPath` undefined.

- [ ] **Step 3: Write minimal implementation** — rewrite `client/lib/models/workspace.dart`

```dart
import 'package:flutter/foundation.dart';

import 'workspace_folder.dart';
import 'workspace_icon_ref.dart';

@immutable
class Workspace {
  const Workspace._({
    required this.workspaceId,
    required this.folders,
    this.display = '',
    this.defaultProfileId = '',
    this.icon = WorkspaceIconRef.auto,
    required this.createdAt,
    this.updatedAt = 0,
    this.sessionIds = const [],
  });

  /// During the preparation cutover this factory also accepts the legacy
  /// [primaryPath]/[additionalPaths] params (used only when [folders] is null).
  /// SCAFFOLD: both params are removed in the final cutover task.
  factory Workspace({
    required String workspaceId,
    List<WorkspaceFolder>? folders,
    String? primaryPath,
    List<String>? additionalPaths,
    String display = '',
    String defaultProfileId = '',
    WorkspaceIconRef icon = WorkspaceIconRef.auto,
    required int createdAt,
    int updatedAt = 0,
    List<String> sessionIds = const [],
  }) {
    final resolved = folders ??
        [
          if ((primaryPath ?? '').isNotEmpty) WorkspaceFolder(path: primaryPath!),
          for (final p in additionalPaths ?? const <String>[])
            if (p.isNotEmpty) WorkspaceFolder(path: p),
        ];
    return Workspace._(
      workspaceId: workspaceId,
      folders: List.unmodifiable(resolved),
      display: display,
      defaultProfileId: defaultProfileId,
      icon: icon,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sessionIds: sessionIds,
    );
  }

  factory Workspace.fromJson(Map<String, Object?> json) {
    final ids = json['sessionIds'];
    final sessionIds = ids is List
        ? ids.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return Workspace(
      workspaceId: json['workspaceId'] as String? ?? '',
      folders: foldersFromLegacyJson(json),
      display: json['display'] as String? ?? '',
      defaultProfileId: json['defaultProfileId'] as String? ?? '',
      icon: WorkspaceIconRef.fromJson(json['icon']),
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sessionIds: sessionIds,
    );
  }

  final String workspaceId;
  final List<WorkspaceFolder> folders;
  final String display;
  final String defaultProfileId;
  final WorkspaceIconRef icon;
  final int createdAt;
  final int updatedAt;
  final List<String> sessionIds;

  String get firstFolderPath => folders.isEmpty ? '' : folders.first.path;
  List<String> get extraFolderPaths => folders.length <= 1
      ? const []
      : folders.skip(1).map((f) => f.path).toList(growable: false);
  List<String> get folderPaths =>
      folders.map((f) => f.path).toList(growable: false);

  @Deprecated('SCAFFOLD: use firstFolderPath; removed after preparation cutover')
  String get primaryPath => firstFolderPath;
  @Deprecated('SCAFFOLD: use extraFolderPaths; removed after preparation cutover')
  List<String> get additionalPaths => extraFolderPaths;

  String get effectiveDisplay =>
      display.isNotEmpty ? display : _basename(firstFolderPath);

  static String _basename(String path) {
    if (path.isEmpty) return '';
    final parts = path.replaceAll(r'\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Workspace copyWith({
    String? workspaceId,
    List<WorkspaceFolder>? folders,
    String? primaryPath, // SCAFFOLD
    List<String>? additionalPaths, // SCAFFOLD
    String? display,
    String? defaultProfileId,
    WorkspaceIconRef? icon,
    int? createdAt,
    int? updatedAt,
    List<String>? sessionIds,
  }) {
    final nextFolders = folders ??
        ((primaryPath != null || additionalPaths != null)
            ? [
                if ((primaryPath ?? firstFolderPath).isNotEmpty)
                  WorkspaceFolder(path: primaryPath ?? firstFolderPath),
                for (final p in additionalPaths ?? extraFolderPaths)
                  if (p.isNotEmpty) WorkspaceFolder(path: p),
              ]
            : this.folders);
    return Workspace(
      workspaceId: workspaceId ?? this.workspaceId,
      folders: nextFolders,
      display: display ?? this.display,
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'workspaceId': workspaceId,
      'folders': folders.map((f) => f.toJson()).toList(),
      // SCAFFOLD dual-write (one version cycle; removed next version):
      'primaryPath': firstFolderPath,
      'additionalPaths': extraFolderPaths,
      'display': display,
      if (defaultProfileId.isNotEmpty) 'defaultProfileId': defaultProfileId,
      if (icon.toJson() case final json?) 'icon': json,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sessionIds': sessionIds,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Workspace &&
            runtimeType == other.runtimeType &&
            workspaceId == other.workspaceId &&
            listEquals(folders, other.folders) &&
            display == other.display &&
            defaultProfileId == other.defaultProfileId &&
            icon == other.icon &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            listEquals(sessionIds, other.sessionIds);
  }

  @override
  int get hashCode => Object.hash(
        workspaceId,
        Object.hashAll(folders),
        display,
        defaultProfileId,
        icon,
        createdAt,
        updatedAt,
        Object.hashAll(sessionIds),
      );
}

class WorkspacesIndex {
  const WorkspacesIndex({this.schemaVersion = 2, this.workspaces = const []});

  factory WorkspacesIndex.fromJson(Map<String, Object?> json) {
    final raw = json['workspaces'];
    final list = <Workspace>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, Object?>) {
          list.add(Workspace.fromJson(item));
        }
      }
    }
    return WorkspacesIndex(
      schemaVersion: json['schemaVersion'] as int? ?? 2,
      workspaces: list,
    );
  }

  final int schemaVersion;
  final List<Workspace> workspaces;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'workspaces': workspaces.map((p) => p.toJson()).toList(),
    };
  }
}
```

- [ ] **Step 4: Run model + analyze**

Run: `cd client && flutter test test/models/workspace_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models test/models`
Expected: tests PASS; analyze reports only `deprecated_member_use` infos on legacy getters elsewhere (acceptable — fixed by Task 8). No errors.

- [ ] **Step 5: Run full suite to confirm scaffold keeps green**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS (deprecated getters keep all existing call sites compiling).

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/workspace.dart client/test/models/workspace_test.dart
git commit -m "refactor: migrate Workspace to folders with legacy scaffold and dual-write"
```

---

### Task 3: `AppSession` 模型迁移到 folders（对称，含脚手架）

**Files:**
- Modify: `client/lib/models/app_session.dart`
- Test: `client/test/models/app_session_folders_test.dart`

**Interfaces:**
- Consumes: `WorkspaceFolder`, `foldersFromLegacyJson` (Task 1).
- Produces (on `AppSession`): same getter set as Workspace — `folders`, `firstFolderPath`, `extraFolderPaths`, `folderPaths`; SCAFFOLD deprecated `primaryPath`/`additionalPaths` getters; factory + copyWith accept `folders` plus scaffold `primaryPath`/`additionalPaths`. `toJson` writes `folders`, dual-writes legacy fields, bumps `schemaVersion` to `2`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/app_session_folders_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('folders round-trip and derived getters', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/main'), WorkspaceFolder(path: '/x')],
      createdAt: 1,
    );
    expect(s.firstFolderPath, '/main');
    expect(s.extraFolderPaths, ['/x']);
    expect(s.folderPaths, ['/main', '/x']);
    final restored = AppSession.fromJson(s.toJson());
    expect(restored.folders.map((f) => f.path), ['/main', '/x']);
  });

  test('reads legacy session manifest', () {
    final restored = AppSession.fromJson({
      'sessionId': 's1',
      'workspaceId': 'w1',
      'primaryPath': '/main',
      'additionalPaths': ['/x'],
      'createdAt': 1,
    });
    expect(restored.firstFolderPath, '/main');
    expect(restored.extraFolderPaths, ['/x']);
  });

  test('toJson dual-writes legacy fields and bumps schemaVersion', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/main')],
      createdAt: 1,
    );
    final json = s.toJson();
    expect(json['schemaVersion'], 2);
    expect(json['primaryPath'], '/main');
    expect(json['additionalPaths'], <String>[]);
    expect((json['folders'] as List).length, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/app_session_folders_test.dart`
Expected: FAIL — `folders` undefined.

- [ ] **Step 3: Write minimal implementation** — edit `client/lib/models/app_session.dart`

Apply the same pattern as Task 2 to `AppSession`:
1. Add `import 'workspace_folder.dart';`.
2. Convert the `const AppSession({...})` constructor to a private `const AppSession._({... required this.folders ...})` plus a public `factory AppSession({... List<WorkspaceFolder>? folders, String? primaryPath, List<String>? additionalPaths, ...})` that resolves folders exactly as Workspace does (primaryPath first, non-empty additionalPaths appended, all default `local`; wrap in `List.unmodifiable`).
3. Replace the `primaryPath` + `additionalPaths` fields with `final List<WorkspaceFolder> folders;`.
4. Add getters `firstFolderPath`, `extraFolderPaths`, `folderPaths` and the two `@Deprecated` getters (identical bodies to Task 2).
5. `fromJson`: replace the `add`/`paths` block and the `primaryPath:`/`additionalPaths:` args with `folders: foldersFromLegacyJson(json)`.
6. `toJson`: change `'schemaVersion': 1` → `'schemaVersion': 2`; replace `'primaryPath': primaryPath, 'additionalPaths': additionalPaths,` with:
```dart
      'folders': folders.map((f) => f.toJson()).toList(),
      // SCAFFOLD dual-write (one version cycle; removed next version):
      'primaryPath': firstFolderPath,
      'additionalPaths': extraFolderPaths,
```
7. `copyWith`: replace `primaryPath`/`additionalPaths` params with a `List<WorkspaceFolder>? folders` param plus scaffold `String? primaryPath`/`List<String>? additionalPaths`, resolving `nextFolders` exactly as Workspace.copyWith (Task 2 Step 3).
8. `operator ==`: replace the `primaryPath == other.primaryPath && listEquals(additionalPaths, other.additionalPaths)` pair with `listEquals(folders, other.folders)`.
9. `hashCode`: replace `primaryPath, Object.hashAll(additionalPaths)` with `Object.hashAll(folders)`.

- [ ] **Step 4: Run test + analyze**

Run: `cd client && flutter test test/models/app_session_folders_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models`
Expected: PASS; no analyze errors.

- [ ] **Step 5: Run full suite (scaffold keeps green)**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/app_session.dart client/test/models/app_session_folders_test.dart
git commit -m "refactor: migrate AppSession to folders with legacy scaffold and dual-write"
```

---

### Task 4: 仓库变异点收敛（`session_repository.dart`）

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Test: `client/test/repositories/session_repository_folders_test.dart`

**Interfaces:**
- Consumes: `Workspace.folders`/`folderPaths`/`firstFolderPath` (Task 2), `AppSession` folders (Task 3), `WorkspaceFolder`.
- Produces: unchanged public method signatures (`createWorkspace`, `updateWorkspaceMetadata`, `updateWorkspacePaths`, `createSession`) — internals now build/operate on `folders`.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/repositories/session_repository_folders_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
// Reuse the in-memory fs harness pattern from session_repository_test.dart.
// (Construct a SessionRepository over a temp/in-memory fs as that file does.)

void main() {
  // NOTE: copy the setUp/fs wiring from
  // client/test/repositories/session_repository_test.dart so the repo writes
  // to an isolated root.

  test('createWorkspace persists local folders and merges by path', () async {
    final repo = /* build repo over temp fs (see session_repository_test.dart) */ null!;
    final ws = await repo.createWorkspace('/main', additionalPaths: ['/x']);
    expect(ws.folders.map((f) => f.path), ['/main', '/x']);
    expect(ws.folders.every((f) => f.targetId == WorkspaceFolder.localTargetId), isTrue);

    final merged = await repo.createWorkspace('/main', additionalPaths: ['/y']);
    expect(merged.workspaceId, ws.workspaceId);
    expect(merged.folders.map((f) => f.path), ['/main', '/x', '/y']);
  });

  test('createSession inherits workspace folders; workingDirectory overrides first',
      () async {
    final repo = /* build repo over temp fs */ null!;
    final ws = await repo.createWorkspace('/main', additionalPaths: ['/x']);
    final s = await repo.createSession(ws.workspaceId, workingDirectory: '/override');
    expect(s.folders.map((f) => f.path), ['/override', '/x']);
  });
}
```

> The implementer fills the `null!` repo wiring by copying the harness already used in `client/test/repositories/session_repository_test.dart` (same constructor injection). Do not invent a new fs.

- [ ] **Step 2: Run to verify it fails**

Run: `cd client && flutter test test/repositories/session_repository_folders_test.dart`
Expected: FAIL (assertions on `.folders`).

- [ ] **Step 3: Implement — edit the 6 mutation points**

(a) `createWorkspace` merge branch (around lines 138–165): keep matching `existing` by `workspacePathsEqual(existing.firstFolderPath, trimmed)`; build `mergedPaths` from `existing.extraFolderPaths` (unchanged list logic), then write back via:
```dart
final updated = existing.copyWith(
  folders: [
    WorkspaceFolder(path: existing.firstFolderPath),
    for (final p in mergedPaths) WorkspaceFolder(path: p),
  ],
  display: displayOut,
  updatedAt: now,
);
```
New-workspace branch (around lines 166–175): construct
```dart
final workspace = Workspace(
  workspaceId: const Uuid().v4(),
  folders: [
    WorkspaceFolder(path: trimmed),
    for (final p in additionalPaths
        .map(normalizeWorkspacePath)
        .where((e) => e.isNotEmpty))
      WorkspaceFolder(path: p),
  ],
  display: display.trim(),
  createdAt: now,
  updatedAt: now,
);
```

(b) `updateWorkspaceMetadata` (lines 196–202): replace the `additionalPaths:` copyWith arg with:
```dart
folders: additionalPaths != null
    ? [
        WorkspaceFolder(path: existing.firstFolderPath),
        for (final p in additionalPaths
            .map(normalizeWorkspacePath)
            .where((e) => e.isNotEmpty))
          WorkspaceFolder(path: p),
      ]
    : existing.folders,
```

(c) `updateWorkspacePaths` (lines 267–271):
```dart
final updated = existing.copyWith(
  folders: [
    WorkspaceFolder(path: normalizeWorkspacePath(primaryPath)),
    for (final p in additionalPaths
        .map(normalizeWorkspacePath)
        .where((e) => e.isNotEmpty))
      WorkspaceFolder(path: p),
  ],
  updatedAt: now,
);
```

(d) `_provisionWorkspaceTrust` (lines 285–288): `directories: workspace.folderPaths,`.

(e) `createSession` (lines 349–352): replace the `primaryPath:`/`additionalPaths:` args with:
```dart
folders: (workingDirectory != null && workingDirectory.trim().isNotEmpty)
    ? [
        WorkspaceFolder(
          path: normalizeWorkspacePath(workingDirectory),
          targetId: workspace.folders.isEmpty
              ? WorkspaceFolder.localTargetId
              : workspace.folders.first.targetId,
        ),
        ...workspace.folders.skip(1),
      ]
    : workspace.folders,
```

(f) `_cloneSessionRecord` and the workspace-clone helper (around lines 649/704): replace `primaryPath: source.primaryPath, additionalPaths: List<String>.from(source.additionalPaths),` with `folders: List.of(source.folders),`.

Add `import '../models/workspace_folder.dart';` to the file.

- [ ] **Step 4: Run repo tests + existing repo suite**

Run: `cd client && flutter test test/repositories/`
Expected: PASS — new folders test + existing `session_repository_test.dart`, `session_repository_working_dir_test.dart`, `session_repository_replicas_test.dart` all green (they exercise createWorkspace/createSession/clone).

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/session_repository_folders_test.dart
git commit -m "refactor: converge session_repository path mutations onto WorkspaceFolder"
```

---

### Task 5: 收敛 `session_data_store.addWorkspaceDirectory`

**Files:**
- Modify: `client/lib/cubits/chat/session_data_store.dart:127-141`

**Interfaces:**
- Consumes: `Workspace.firstFolderPath`/`extraFolderPaths` (Task 2), `repo.createWorkspace` (Task 4).

> Split out from the cubits batch because it carries directory-merge logic worth its own gate.

- [ ] **Step 1: Edit `addWorkspaceDirectory`** (lines 134–138)

```dart
    if (workspacePathsEqual(trimmed, workspace.firstFolderPath)) return null;
    if (workspacePathsContains(workspace.extraFolderPaths, trimmed)) return null;
    await repo.createWorkspace(
      workspace.firstFolderPath,
      additionalPaths: [trimmed],
    );
```

- [ ] **Step 2: Run the cubit test that exercises it**

Run: `cd client && flutter test test/cubits/session_data_store_personal_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add client/lib/cubits/chat/session_data_store.dart
git commit -m "refactor: use folder getters in addWorkspaceDirectory"
```

---

### Task 6: 调用点硬切 — 批 A（services + cubits）

**Files (modify each):**
- `client/lib/services/session/session_lifecycle_service.dart` (R lines ~351-352, 592, 608, 822; RA lines ~593, 609, 656)
- `client/lib/cubits/chat/session_launch_service.dart` (R lines ~167, 342, 368, 862; RA line ~863; C lines ~735-736)
- `client/lib/cubits/chat/tab_team_bus_coordinator.dart` (R line ~94; RA line ~98)
- `client/lib/cubits/chat/chat_tab_store.dart` (R line ~158; RA line ~159)
- `client/lib/services/team/default_workspace_service.dart` (R line ~33)
- `client/lib/services/home_workspace/home_closed_workspaces_store.dart` (C line ~57 — receiver is `HomeClosedWorkspaceEntry`, see note)
- `client/lib/utils/session_worktree_grouping.dart` (R line ~29)

**Interfaces:**
- Consumes: folders getters (Tasks 2/3). The downstream params (`CliLaunchContext.workingDirectory`/`additionalDirectories`, `RightToolsPanel`, etc.) keep `String`/`List<String>` — feed them `firstFolderPath`/`extraFolderPaths`/`folderPaths`.

- [ ] **Step 1: Apply mechanical substitutions per file**

For each `<obj>` that is a `Workspace` or `AppSession`:
- `<obj>.primaryPath` → `<obj>.firstFolderPath`
- `<obj>.additionalPaths` → `<obj>.extraFolderPaths`
- `[<obj>.primaryPath, ...<obj>.additionalPaths]` → `<obj>.folderPaths`
- construct `... primaryPath: x, additionalPaths: y ...` → keep as-is ONLY if building a non-model type; for `AppSession(...)`/`Workspace(...)` switch to `folders:`.

Specifics:
- `session_launch_service.dart` `_sessionForMemberConnect` (lines ~735-736): if it constructs an `AppSession` with `primaryPath:`/`additionalPaths:`, change to `folders:` using the source session's `folders` (or build from `firstFolderPath`/`extraFolderPaths`).
- `home_closed_workspaces_store.dart:57`: `primaryPath: entry.primaryPath` — confirm receiver `entry` is `HomeClosedWorkspaceEntry` (its own field), NOT a Workspace. If so, **leave unchanged** (out of scope per design §5 exclusions). Only change the call site that READS a `Workspace` to populate that entry (e.g. `HomeClosedWorkspaceEntry(primaryPath: workspace.firstFolderPath, ...)`).

> `HomeClosedWorkspaceEntry` keeps its own `primaryPath` field this phase (not a Workspace/AppSession). Verify with: `grep -n "primaryPath" client/lib/models/home_closed_workspace_entry.dart` before editing.

- [ ] **Step 2: Analyze the touched tree**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services lib/cubits lib/utils`
Expected: no errors; `deprecated_member_use` infos drop for these files.

- [ ] **Step 3: Run affected suites**

Run: `cd client && flutter test test/cubits test/services --exclude-tags integration`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services client/lib/cubits client/lib/utils
git commit -m "refactor: cut services+cubits call sites over to workspace folders"
```

---

### Task 7: 调用点硬切 — 批 B（widgets + pages）

**Files (modify each):**
- `client/lib/widgets/workspace_details_dialog.dart` (R line ~83, ~142; RA lines ~50, ~91, list UI)
- `client/lib/pages/home_workspace/home_workspace_shell.dart` (R lines ~67, ~269)
- `client/lib/pages/home_workspace/home_workspace_title_bar.dart` (R tooltip)
- `client/lib/pages/home_workspace/workspace/workspace_info_section.dart` (R ~69; RA ~87 count)
- `client/lib/pages/home_workspace/workspace/workspace_settings_view.dart` (R ~69; RA ~87)
- `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` (R ~50, ~97; RA ~100)
- `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`, `workspace_search_dialog.dart`, `workspace_session_actions.dart` (R via helpers — verify, likely no direct field access)
- Feeders into independent widget params (keep their `List<String>`/`cwd` names): `client/lib/widgets/right_tools/right_tools_panel.dart`, `client/lib/pages/chat_page.dart`, `client/lib/pages/chat/chat_page_shell.dart`

**Interfaces:**
- Consumes: folders getters (Tasks 2/3). Independent widget params (`RightToolsPanel.additionalPaths`/`cwd`, `ChatPage.additionalPaths`) **keep their names**; only the call sites that read a Workspace/AppSession to fill them change to `firstFolderPath`/`extraFolderPaths`/`folderPaths`.

- [ ] **Step 1: Apply the same substitutions as Task 6** to widgets/pages. For `workspace_details_dialog.dart` `_additionalPaths` local state, initialise from `widget.workspace.extraFolderPaths` and on save still call `repo.updateWorkspacePaths(id, workspace.firstFolderPath, _additionalPaths)` (string API unchanged).

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets lib/pages`
Expected: no errors.

- [ ] **Step 3: Run widget/page suites**

Run: `cd client && flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets client/lib/pages
git commit -m "refactor: cut widgets+pages call sites over to workspace folders"
```

---

### Task 8: 移除脚手架（硬切终态）+ 全量验收

**Files:**
- Modify: `client/lib/models/workspace.dart`, `client/lib/models/app_session.dart`
- Modify: `client/test/models/workspace_test.dart`, `client/test/models/app_session_folders_test.dart` (drop any deprecated-getter assertions)

**Interfaces:**
- Produces: final API — `Workspace`/`AppSession` expose ONLY `folders` + `firstFolderPath`/`extraFolderPaths`/`folderPaths`. No `primaryPath`/`additionalPaths` getters or factory/copyWith params remain.

- [ ] **Step 1: Confirm no live deprecated usages remain**

Run:
```bash
cd client && grep -rn "\.primaryPath\|\.additionalPaths" lib --include=*.dart \
  | grep -v "home_closed_workspace_entry\|teammate_roster_profile\|right_tools_panel\|chat_page\|teammate_bus_mcp_handler"
```
Expected: empty output (only the intentionally-excluded independent-field receivers may remain). If any Workspace/AppSession access remains, fix it before proceeding.

- [ ] **Step 2: Delete scaffolding**

In both `workspace.dart` and `app_session.dart`:
- Remove the two `@Deprecated` getters (`primaryPath`, `additionalPaths`).
- Remove the `String? primaryPath` / `List<String>? additionalPaths` params from the `factory` and from `copyWith`, and simplify their bodies to require/use `folders` directly (drop the `??`-from-legacy branches).

- [ ] **Step 3: Update model tests**

Remove the "legacy factory params still build folders" test from `workspace_test.dart` and any deprecated-getter assertions; keep the legacy-**JSON**-read tests (those exercise `fromJson`/`foldersFromLegacyJson`, which stay).

- [ ] **Step 4: Full verification (acceptance)**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```
Expected: analyze CLEAN (no `deprecated_member_use`); all tests PASS.

- [ ] **Step 5: Migration smoke test — legacy manifest fixture**

Add a focused test asserting a real legacy on-disk shape upgrades correctly (already covered by Task 2/3 legacy-read tests; if a fixture file exists under `client/test/`, point it at the new reader). Confirm:
```bash
cd client && flutter test test/models/workspace_test.dart test/models/app_session_folders_test.dart
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models client/test/models
git commit -m "refactor: remove folders migration scaffold (hard cutover complete)"
```

---

## Self-Review

**Spec coverage:**
- §3.1 WorkspaceFolder + reader → Task 1 ✅
- §3.2 Workspace migration → Task 2 ✅; AppSession migration → Task 3 ✅
- §3.3 scaffold (temp getters/params, removed at end) → Tasks 2/3 add, Task 8 removes ✅
- §4 repository 6 mutation points → Task 4 (createWorkspace, updateWorkspaceMetadata, updateWorkspacePaths, _provisionWorkspaceTrust, createSession, clone) ✅
- §5 call-site batches A/B → Tasks 5 (data store), 6 (services+cubits), 7 (widgets+pages) ✅
- §6 migration (tolerant read, dual-write, schemaVersion) → Tasks 2/3 ✅
- §7 acceptance (multi-dir + --add-dir, lossless migration, behavior unchanged, hard-cutover terminal state) → Task 8 final verification ✅
- §8 out-of-scope (no RuntimeTarget, no non-local targetId) → enforced by Global Constraints ✅

**Placeholder scan:** Task 4 Step 1 uses `null!` repo wiring with an explicit instruction to copy the existing `session_repository_test.dart` harness — intentional (do not invent a new fs), not a content gap. All code steps carry concrete code.

**Type consistency:** Getter names `firstFolderPath` / `extraFolderPaths` / `folderPaths` and `WorkspaceFolder.localTargetId` used identically across Tasks 1–8. `foldersFromLegacyJson` signature stable. Repository public signatures unchanged throughout.

**Risk control (per user Q4 ask — batch ~200 hits by file + regression strategy):** scaffold keeps `flutter analyze`/`flutter test` green after every task; call sites cut over per-file in Tasks 5–7; final Task 8 removes scaffold and asserts zero residual old-API access. Each task ends with an independently runnable verification command.
