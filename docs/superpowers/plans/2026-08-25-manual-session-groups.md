# Manual Session Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create named session groups ("todo"-style) in the workspace left sidebar and tag-style add/remove sessions to them.

**Architecture:** A per-workspace `session-groups.json` file holds ordered `SessionGroup`s (id, name, member session ids, collapsed flag). A `SessionGroupRepository` wraps IO, a `SessionGroupsCubit` owns optimistic mutations, and an app-lifetime registry hands one cubit per workspace to `WorkspaceSplitPane`. The sidebar renders one collapsible `SessionGroupSection` block per group above the conversation list; membership toggles come from the session row's existing context menu.

**Tech Stack:** Flutter, flutter_bloc, shared_ui (`Tp*` components), existing `WorkspaceLayout` / `AppStorage.fs` IO conventions, `uuid`, Flutter gen-l10n ARBs.

**Spec:** `docs/superpowers/specs/2026-08-25-manual-session-groups-design.md`

## Global Constraints

- All paths below are relative to `client/`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Single-file test runs: `flutter test <path>` from `client/`.
- l10n strings go ONLY in `client/lib/l10n/app_en.arb` + `app_zh.arb`, then `cd client && flutter gen-l10n`. Generated `app_localizations*.dart` files are committed.
- File IO only through `AppStorage.fs` / `WorkspaceLayout`; never `Directory.current`.
- Follow existing doc-comment style (this codebase documents public members).
- No `print`; no user-facing string literals outside l10n.
- Membership is tag-style: a session id may appear in many groups; group blocks never remove sessions from the main list.
- Do NOT commit unless the step says so; never touch `client/google_fonts/`.

---

### Task 1: `SessionGroup` model + storage layout path

**Files:**
- Create: `client/lib/models/session_group.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart` (after `projectConfigFile`, ~L63; plus one line in the class doc-comment tree at ~L16)
- Modify: `docs/workspace-storage-layout.md` (add `session-groups.json` under the workspace dir listing)
- Test: `client/test/models/session_group_test.dart`

**Interfaces:**
- Produces: `SessionGroup{id:String, name:String, sessionIds:List<String>, collapsed:bool}` with `fromJson(Map<String,Object?>)`, `toJson()`, `copyWith({String? name, List<String>? sessionIds, bool? collapsed})`, value equality; `SessionGroupsFile{version:int, groups:List<SessionGroup>}` with `static const currentVersion = 1`, `fromJson`, `toJson`, equality; `WorkspaceLayout.sessionGroupsFile(String workspaceId) -> String`.

- [ ] **Step 1: Write the failing model test**

Create `client/test/models/session_group_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_group.dart';

void main() {
  group('SessionGroup', () {
    test('json round-trip preserves fields', () {
      const group = SessionGroup(
        id: 'g1',
        name: '待办',
        sessionIds: ['s1', 's2'],
        collapsed: true,
      );
      final decoded = SessionGroup.fromJson(
        Map<String, Object?>.from(group.toJson()),
      );
      expect(decoded, group);
    });

    test('fromJson tolerates junk and dedupes session ids', () {
      final decoded = SessionGroup.fromJson(const {
        'id': ' g2 ',
        'name': 42,
        'sessionIds': ['a', 'a', 'b', 7],
        'collapsed': 'yes',
      });
      expect(decoded.id, 'g2');
      expect(decoded.name, '');
      expect(decoded.sessionIds, ['a', 'b']);
      expect(decoded.collapsed, isFalse);
    });

    test('copyWith replaces only given fields', () {
      const group = SessionGroup(id: 'g1', name: 'A', sessionIds: ['s1']);
      final renamed = group.copyWith(name: 'B');
      expect(renamed.name, 'B');
      expect(renamed.id, 'g1');
      expect(renamed.sessionIds, ['s1']);
      expect(renamed.collapsed, isFalse);
    });
  });

  group('SessionGroupsFile', () {
    test('round-trip keeps group order and default version', () {
      const file = SessionGroupsFile(groups: [
        SessionGroup(id: 'g1', name: 'A'),
        SessionGroup(id: 'g2', name: 'B', collapsed: true),
      ]);
      final decoded = SessionGroupsFile.fromJson(
        Map<String, Object?>.from(file.toJson()),
      );
      expect(decoded.version, SessionGroupsFile.currentVersion);
      expect(decoded.groups, file.groups);
    });

    test('fromJson on empty map yields empty groups', () {
      expect(SessionGroupsFile.fromJson(const {}).groups, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/session_group_test.dart`
Expected: FAIL — `session_group.dart` does not exist (compile error).

- [ ] **Step 3: Write the model**

Create `client/lib/models/session_group.dart`:

```dart
import 'package:flutter/foundation.dart';

/// One manual session group ("todo", "review", …) in a workspace sidebar.
///
/// Membership is tag-style: the same session id may appear in several groups,
/// and grouped sessions stay in the main conversation list.
@immutable
class SessionGroup {
  const SessionGroup({
    required this.id,
    required this.name,
    this.sessionIds = const [],
    this.collapsed = false,
  });

  /// Tolerant decode: junk fields fall back to defaults instead of throwing;
  /// blank/duplicate member ids are dropped.
  factory SessionGroup.fromJson(Map<String, Object?> json) {
    final rawIds = json['sessionIds'];
    final ids = <String>{
      if (rawIds is List)
        for (final entry in rawIds)
          if (entry is String && entry.trim().isNotEmpty) entry,
    };
    return SessionGroup(
      id: json['id'] is String ? (json['id'] as String).trim() : '',
      name: json['name'] is String ? json['name'] as String : '',
      sessionIds: ids.toList(),
      collapsed: json['collapsed'] == true,
    );
  }

  final String id;

  /// Display label; may be any non-empty user-entered text.
  final String name;

  /// Member session ids in insertion order. Rendering re-sorts by the current
  /// sidebar sort, so no dedicated order is persisted.
  final List<String> sessionIds;

  /// Persisted block-collapse state.
  final bool collapsed;

  bool containsSession(String sessionId) => sessionIds.contains(sessionId);

  SessionGroup copyWith({
    String? name,
    List<String>? sessionIds,
    bool? collapsed,
  }) => SessionGroup(
    id: id,
    name: name ?? this.name,
    sessionIds: sessionIds ?? this.sessionIds,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'sessionIds': sessionIds,
    'collapsed': collapsed,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionGroup &&
          id == other.id &&
          name == other.name &&
          collapsed == other.collapsed &&
          listEquals(sessionIds, other.sessionIds);

  @override
  int get hashCode =>
      Object.hash(id, name, collapsed, Object.hashAll(sessionIds));
}

/// Root document of `{workspaceId}/session-groups.json`.
@immutable
class SessionGroupsFile {
  static const int currentVersion = 1;

  const SessionGroupsFile({
    this.version = currentVersion,
    this.groups = const [],
  });

  factory SessionGroupsFile.fromJson(Map<String, Object?> json) {
    final rawGroups = json['groups'];
    return SessionGroupsFile(
      version: json['version'] is int
          ? json['version'] as int
          : currentVersion,
      groups: [
        if (rawGroups is List)
          for (final entry in rawGroups)
            if (entry is Map)
              SessionGroup.fromJson(entry.cast<String, Object?>()),
      ],
    );
  }

  final int version;
  final List<SessionGroup> groups;

  Map<String, Object?> toJson() => {
    'version': version,
    'groups': [for (final group in groups) group.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionGroupsFile &&
          version == other.version &&
          listEquals(groups, other.groups);

  @override
  int get hashCode => Object.hash(version, Object.hashAll(groups));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/session_group_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Add the layout path**

In `client/lib/services/storage/workspace_layout.dart`, immediately after `projectConfigFile` (L62–63) add:

```dart
  /// Manual sidebar session groups ("todo" etc.), tag-style membership.
  String sessionGroupsFile(String workspaceId) =>
      _ctx.join(workspaceDir(workspaceId), 'session-groups.json');
```

In the class doc comment's directory tree (~L16, after the `project-config.json` line) insert:

```
///   session-groups.json # manual sidebar session groups
```

In `docs/workspace-storage-layout.md`, add the same line to the workspace directory listing wherever `project-config.json` appears (keep surrounding format).

- [ ] **Step 6: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add client/lib/models/session_group.dart client/lib/services/storage/workspace_layout.dart docs/workspace-storage-layout.md client/test/models/session_group_test.dart
git commit -m "feat: session group model and workspace layout path"
```

---

### Task 2: `SessionGroupRepository`

**Files:**
- Create: `client/lib/repositories/session_group_repository.dart`
- Test: `client/test/repositories/session_group_repository_test.dart`

**Interfaces:**
- Consumes: `SessionGroup`/`SessionGroupsFile` (Task 1), `WorkspaceLayout.sessionGroupsFile`.
- Produces: `SessionGroupRepository{Future<SessionGroupsFile> load(String workspaceId), Future<void> save(String workspaceId, SessionGroupsFile file)}` — same cache/corrupt-tolerance contract as `WorkspaceProjectConfigRepository`.

- [ ] **Step 1: Write the failing repository test**

Create `client/test/repositories/session_group_repository_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/repositories/session_group_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late SessionGroupRepository repository;
  late WorkspaceLayout layout;

  setUp(() {
    repository = SessionGroupRepository();
    layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
  });

  test('missing file loads empty without creating it', () async {
    final file = await repository.load('ws-1');
    expect(file.groups, isEmpty);
    expect(File(layout.sessionGroupsFile('ws-1')).existsSync(), isFalse);
  });

  test('save creates parent dirs and load round-trips', () async {
    const file = SessionGroupsFile(
      groups: [
        SessionGroup(id: 'g1', name: '待办', sessionIds: ['s1'], collapsed: true),
      ],
    );
    await repository.save('ws-1', file);
    expect(File(layout.sessionGroupsFile('ws-1')).existsSync(), isTrue);
    expect(await repository.load('ws-1'), file);
  });

  test('corrupt json loads empty', () async {
    final path = layout.sessionGroupsFile('ws-1');
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('{broken');
    expect((await repository.load('ws-1')).groups, isEmpty);
  });

  test('empty workspace id is a no-op', () async {
    await repository.save('  ', const SessionGroupsFile());
    expect((await repository.load('')).groups, isEmpty);
    expect((await repository.load('')).version, SessionGroupsFile.currentVersion);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/session_group_repository_test.dart`
Expected: FAIL — `session_group_repository.dart` does not exist.

- [ ] **Step 3: Write the repository**

Create `client/lib/repositories/session_group_repository.dart`:

```dart
import 'dart:convert';

import '../models/session_group.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/workspace_layout.dart';

/// Reads and writes `{workspaceDir}/session-groups.json` — manual sidebar
/// session groups for one workspace. Corrupt or missing files decode to an
/// empty document; the next save rebuilds the file.
class SessionGroupRepository {
  SessionGroupRepository({Filesystem? fs, WorkspaceLayout? layout})
    : _fs = fs ?? AppStorage.fs,
      _layout =
          layout ?? WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);

  final Filesystem _fs;
  final WorkspaceLayout _layout;
  final Map<String, SessionGroupsFile> _cache = {};

  Future<SessionGroupsFile> load(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return const SessionGroupsFile();
    final cached = _cache[id];
    if (cached != null) return cached;

    final path = _file(id);
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      return _cache[id] = const SessionGroupsFile();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _cache[id] = SessionGroupsFile.fromJson(
          decoded.cast<String, Object?>(),
        );
      }
    } on Object {
      // Corrupt file → empty; next save overwrites.
    }
    return _cache[id] = const SessionGroupsFile();
  }

  Future<void> save(String workspaceId, SessionGroupsFile file) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return;
    _cache[id] = file;
    final path = _file(id);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(file.toJson()),
    );
  }

  void invalidate(String workspaceId) => _cache.remove(workspaceId.trim());

  String _file(String workspaceId) =>
      _layout.sessionGroupsFile(workspaceId.trim());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/session_group_repository_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_group_repository.dart client/test/repositories/session_group_repository_test.dart
git commit -m "feat: session group repository for per-workspace session-groups.json"
```

---

### Task 3: `SessionGroupsCubit`

**Files:**
- Create: `client/lib/cubits/session_groups_cubit.dart`
- Test: `client/test/cubits/session_groups_cubit_test.dart`

**Interfaces:**
- Consumes: `SessionGroupRepository` (Task 2).
- Produces:
  - `enum SessionGroupsStatus { loading, ready }`
  - `SessionGroupsState{status, workspaceId, groups}` with `ready`, `SessionGroup? groupById(String)`, `Set<String> groupIdsContaining(String sessionId)`, `copyWith`.
  - `SessionGroupsCubit({SessionGroupRepository? repository, Set<String> Function()? knownSessionIds})` with `Future<void> load(String workspaceId)`, `void createGroup(String name)`, `void renameGroup(String groupId, String name)`, `void deleteGroup(String groupId)`, `void setMembership(String groupId, String sessionId, {required bool member})`, `void toggleCollapsed(String groupId)`.

- [ ] **Step 1: Write the failing cubit test**

Create `client/test/cubits/session_groups_cubit_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late WorkspaceLayout layout;
  late String basePath;

  setUp(() {
    basePath = AppStorage.paths.basePath;
    layout = WorkspaceLayout(teampilotRoot: basePath);
  });

  /// Reads the file back from disk through a fresh cubit (bypasses caches).
  Future<List<SessionGroup>> persistedGroups(String workspaceId) async {
    final raw = await File(layout.sessionGroupsFile(workspaceId)).readAsString();
    return SessionGroupsFile.fromJsonFromRaw(raw).groups;
  }

  test('load hydrates persisted groups', () async {
    File(layout.sessionGroupsFile('ws-1')).parent.createSync(recursive: true);
    File(layout.sessionGroupsFile('ws-1')).writeAsStringSync(
      '{"version":1,"groups":[{"id":"g1","name":"待办","sessionIds":["s1"]}]}',
    );

    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');

    expect(cubit.state.ready, isTrue);
    expect(cubit.state.workspaceId, 'ws-1');
    expect(cubit.state.groups, [
      const SessionGroup(id: 'g1', name: '待办', sessionIds: ['s1']),
    ]);
  });

  test('createGroup appends trimmed name and persists', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');

    cubit.createGroup('  待办  ');
    cubit.createGroup('   ');

    expect(cubit.state.groups.map((g) => g.name).toList(), ['待办']);
    await pumpEventQueue();
    expect(await persistedGroups('ws-1').then((g) => g.length), 1);
  });

  test('rename / delete mutate only the target group', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('A');
    cubit.createGroup('B');
    final idA = cubit.state.groups[0].id;

    cubit.renameGroup(idA, 'Todo');
    expect(cubit.state.groups[0].name, 'Todo');

    cubit.deleteGroup(cubit.state.groups[1].id);
    expect(cubit.state.groups.map((g) => g.name), ['Todo']);
    await pumpEventQueue();
    expect((await persistedGroups('ws-1')).map((g) => g.name), ['Todo']);
  });

  test('setMembership adds and removes tags across groups', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;

    cubit.setMembership(groupId, 'sess-1', member: true);
    expect(cubit.state.groupById(groupId)!.containsSession('sess-1'), isTrue);

    cubit.setMembership(groupId, 'sess-1', member: false);
    expect(cubit.state.groupById(groupId)!.containsSession('sess-1'), isFalse);
  });

  test('toggleCollapsed persists collapse flag', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;

    cubit.toggleCollapsed(groupId);
    expect(cubit.state.groupById(groupId)!.collapsed, isTrue);
    await pumpEventQueue();

    final reopened = SessionGroupsCubit();
    addTearDown(reopened.close);
    await reopened.load('ws-1');
    expect(reopened.state.groupById(groupId)!.collapsed, isTrue);
  });

  test('knownSessionIds prunes stale member ids on persist', () async {
    var known = {'s-live'};
    final cubit = SessionGroupsCubit(knownSessionIds: () => known);
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;
    cubit.setMembership(groupId, 's-live', member: true);
    cubit.setMembership(groupId, 's-stale', member: true);
    await pumpEventQueue();
    expect((await persistedGroups('ws-1')).single.sessionIds,
        containsAll(['s-live', 's-stale']));

    // s-stale vanished; next mutation persists the pruned membership.
    known = {'s-live'};
    cubit.toggleCollapsed(groupId);
    await pumpEventQueue();
    expect((await persistedGroups('ws-1')).single.sessionIds, ['s-live']);
    // Optimistic state still carries the unpruned list; rendering filters.
    expect(cubit.state.groupById(groupId)!.containsSession('s-stale'), isTrue);
  });
}
```

Note: the first test uses `SessionGroupsFile.fromJsonFromRaw(raw)` for brevity — either add that tiny static helper to `SessionGroupsFile` in this task:

```dart
  static SessionGroupsFile fromRawJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return SessionGroupsFile.fromJson(decoded.cast<String, Object?>());
      }
    } on Object {
      // Fall through to empty.
    }
    return const SessionGroupsFile();
  }
```

(add `import 'dart:convert';` to the model) and use `SessionGroupsFile.fromRawJson(raw).groups`, **or** replace that helper call in the test with direct `jsonDecode`. Prefer adding `fromRawJson` — the repository can then reuse it.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cubits/session_groups_cubit_test.dart`
Expected: FAIL — `session_groups_cubit.dart` does not exist.

- [ ] **Step 3: Write the cubit**

Create `client/lib/cubits/session_groups_cubit.dart`:

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/session_group.dart';
import '../repositories/session_group_repository.dart';

enum SessionGroupsStatus { loading, ready }

class SessionGroupsState {
  const SessionGroupsState({
    this.status = SessionGroupsStatus.loading,
    this.workspaceId = '',
    this.groups = const [],
  });

  final SessionGroupsStatus status;
  final String workspaceId;
  final List<SessionGroup> groups;

  bool get ready => status == SessionGroupsStatus.ready;

  SessionGroup? groupById(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  /// Ids of groups containing [sessionId] — drives context-menu checkmarks.
  Set<String> groupIdsContaining(String sessionId) => {
    for (final group in groups)
      if (group.sessionIds.contains(sessionId)) group.id,
  };

  SessionGroupsState copyWith({
    SessionGroupsStatus? status,
    String? workspaceId,
    List<SessionGroup>? groups,
  }) => SessionGroupsState(
    status: status ?? this.status,
    workspaceId: workspaceId ?? this.workspaceId,
    groups: groups ?? this.groups,
  );
}

/// Owns the manual session groups of one workspace: optimistic mutations with
/// whole-file persistence. One cubit per open workspace (see
/// `WorkspaceSessionGroupsRegistry`) so concurrent tabs share a single writer.
class SessionGroupsCubit extends Cubit<SessionGroupsState> {
  SessionGroupsCubit({SessionGroupRepository? repository, this.knownSessionIds})
    : _repository = repository ?? SessionGroupRepository(),
      super(const SessionGroupsState());

  final SessionGroupRepository _repository;

  /// Live workspace session ids; stale member ids are pruned from the file on
  /// every persist. Rendered blocks always filter unknown ids anyway.
  final Set<String> Function()? knownSessionIds;

  int _generation = 0;

  /// Loads (or switches to) [workspaceId]. A later load supersedes an earlier
  /// in-flight one via generation check.
  Future<void> load(String workspaceId) async {
    final id = workspaceId.trim();
    final generation = ++_generation;
    emit(const SessionGroupsState(status: SessionGroupsStatus.loading));
    final file = await _repository.load(id);
    if (generation != _generation || isClosed) return;
    emit(
      SessionGroupsState(status: SessionGroupsStatus.ready, workspaceId: id, groups: file.groups),
    );
  }

  void createGroup(String name) => _mutate((state) {
    final trimmed = name.trim();
    if (!state.ready || trimmed.isEmpty) return state;
    return state.copyWith(
      groups: [...state.groups, SessionGroup(id: const Uuid().v4(), name: trimmed)],
    );
  });

  void renameGroup(String groupId, String name) => _mutate((state) {
    final trimmed = name.trim();
    if (!state.ready || trimmed.isEmpty) return state;
    return state.copyWith(
      groups: [
        for (final group in state.groups)
          if (group.id == groupId) group.copyWith(name: trimmed) else group,
      ],
    );
  });

  void deleteGroup(String groupId) => _mutate(
    (state) => state.copyWith(
      groups: state.groups.where((group) => group.id != groupId).toList(),
    ),
  );

  void addSession(String groupId, String sessionId) =>
      setMembership(groupId, sessionId, member: true);

  void removeSession(String groupId, String sessionId) =>
      setMembership(groupId, sessionId, member: false);

  /// Tag-style toggle: joining never leaves other groups, leaving never
  /// touches the session itself.
  void setMembership(String groupId, String sessionId, {required bool member}) =>
      _mutate((state) {
        if (!state.ready || sessionId.trim().isEmpty) return state;
        return state.copyWith(
          groups: [
            for (final group in state.groups)
              if (group.id == groupId)
                group.copyWith(
                  sessionIds: member
                      ? group.sessionIds.contains(sessionId)
                            ? group.sessionIds
                            : [...group.sessionIds, sessionId]
                      : group.sessionIds.where((id) => id != sessionId).toList(),
                )
              else group,
          ],
        );
      });

  void toggleCollapsed(String groupId) => _mutate((state) {
    if (!state.ready) return state;
    return state.copyWith(
      groups: [
        for (final group in state.groups)
          if (group.id == groupId) group.copyWith(collapsed: !group.collapsed) else group,
      ],
    );
  });

  void _mutate(SessionGroupsState Function(SessionGroupsState state) mutate) {
    final next = mutate(state);
    if (identical(next, state)) return;
    emit(next);
    unawaited(_persist(next));
  }

  Future<void> _persist(SessionGroupsState next) async {
    var groups = next.groups;
    final known = knownSessionIds?.call();
    if (known != null && known.isNotEmpty) {
      groups = [
        for (final group in groups)
          group.copyWith(
            sessionIds: [
              for (final id in group.sessionIds)
                if (known.contains(id)) id,
            ],
          ),
      ];
    }
    try {
      await _repository.save(next.workspaceId, SessionGroupsFile(groups: groups));
    } on Object {
      // Keep the optimistic state; the next mutation retries the save.
    }
  }
}
```

If Step 1 added `fromRawJson` to the model, also simplify `SessionGroupRepository.load`'s decode body to `return _cache[id] = SessionGroupsFile.fromRawJson(raw);` (behavior identical).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/cubits/session_groups_cubit_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session_groups_cubit.dart client/test/cubits/session_groups_cubit_test.dart client/lib/models/session_group.dart
git commit -m "feat: session groups cubit with optimistic persistence"
```

---

### Task 4: Registry + app wiring

**Files:**
- Create: `client/lib/services/workspace/workspace_session_groups_registry.dart`
- Modify: `client/lib/app/app_shell.dart` (local ~L1469 near `workspaceWorktreeRegistry`; constructor param ~L423; field ~L517; pass-through ~L2267; cubit factory closure referencing the bootstrap `chatCubit`)
- Modify: `client/lib/main.dart` (RepositoryProvider after `WorkspaceWorktreeRegistry` at ~L665)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` (resolve + provide cubit ~L236/L245)
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart` (~L398, next to worktree `removeWorkspace`)
- Test: `client/test/services/workspace/workspace_session_groups_registry_test.dart`

**Interfaces:**
- Consumes: `SessionGroupsCubit` (Task 3).
- Produces: `WorkspaceSessionGroupsRegistry.cubitFor(String workspaceId) -> SessionGroupsCubit` (creates + kicks off `unawaited(load(ws))` once), `removeWorkspace(String)`, `dispose()`; `SessionGroupsCubit` provided via `BlocProvider<SessionGroupsCubit>` above `WorkspaceIdeShell`.

- [ ] **Step 1: Write the failing registry test**

Create `client/test/services/workspace/workspace_session_groups_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/services/workspace/workspace_session_groups_registry.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('cubitFor returns the same instance and loads the workspace', () async {
    final registry = WorkspaceSessionGroupsRegistry();
    addTearDown(registry.dispose);

    final cubit = registry.cubitFor('ws-1');
    expect(identical(registry.cubitFor(' ws-1 '), cubit), isTrue);
    expect(cubit.state.workspaceId, 'ws-1');
    await pumpEventQueue();
    expect(cubit.state.ready, isTrue);
  });

  test('cubitFactory override is honored once per workspace', () async {
    final created = <SessionGroupsCubit>[];
    final registry = WorkspaceSessionGroupsRegistry(
      cubitFactory: () {
        final cubit = SessionGroupsCubit();
        created.add(cubit);
        return cubit;
      },
    );
    addTearDown(registry.dispose);

    final first = registry.cubitFor('ws-1');
    expect(identical(registry.cubitFor('ws-1'), first), isTrue);
    expect(created, hasLength(1));
  });

  test('removeWorkspace closes the cubit; empty id throws', () {
    final registry = WorkspaceSessionGroupsRegistry();
    addTearDown(registry.dispose);

    final cubit = registry.cubitFor('ws-1');
    registry.removeWorkspace('ws-1');
    expect(cubit.isClosed, isTrue);
    expect(() => registry.cubitFor(''), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/workspace/workspace_session_groups_registry_test.dart`
Expected: FAIL — registry file does not exist.

- [ ] **Step 3: Write the registry**

Create `client/lib/services/workspace/workspace_session_groups_registry.dart`:

```dart
import 'dart:async';

import '../../cubits/session_groups_cubit.dart';

/// Retains long-lived [SessionGroupsCubit]s per open workspace so multiple
/// tabs on the same workspace share one owner/writer of session-groups.json.
class WorkspaceSessionGroupsRegistry {
  WorkspaceSessionGroupsRegistry({SessionGroupsCubit Function()? cubitFactory})
    : _cubitFactory = cubitFactory;

  final SessionGroupsCubit Function()? _cubitFactory;
  final Map<String, SessionGroupsCubit> _cubits = {};

  /// Returns the retained cubit for [workspaceId], creating and loading it on
  /// first request. Throws on an empty id — callers always have a workspace.
  SessionGroupsCubit cubitFor(String workspaceId) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw ArgumentError.value(workspaceId, 'workspaceId', 'must not be empty');
    }
    final existing = _cubits[ws];
    if (existing != null && !existing.isClosed) return existing;
    final cubit = _cubitFactory?.call() ?? SessionGroupsCubit();
    _cubits[ws] = cubit;
    unawaited(cubit.load(ws));
    return cubit;
  }

  /// Closes the cubit when a workspace tab closes.
  void removeWorkspace(String workspaceId) {
    final ws = workspaceId.trim();
    if (ws.isEmpty) return;
    _cubits.remove(ws)?.close();
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/workspace/workspace_session_groups_registry_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Wire into the app shell**

In `client/lib/app/app_shell.dart`:

1. Import `../services/workspace/workspace_session_groups_registry.dart` and `../cubits/session_groups_cubit.dart`.
2. Next to the `workspaceWorktreeRegistry` local (~L1469):

```dart
  final workspaceSessionGroupsRegistry = WorkspaceSessionGroupsRegistry(
    cubitFactory: () => SessionGroupsCubit(
      knownSessionIds: () => {
        for (final s in chatCubit.state.sessions) s.sessionId,
      },
    ),
  );
```

(`chatCubit` is assigned at ~L1610 in the same scope; the closure runs lazily so assignment order is safe. Verify the identifier with `rg -n "chatCubit =" client/lib/app/app_shell.dart` and adapt if it is a field access.)

3. Constructor parameter (~L423 area, beside `required this.workspaceWorktreeRegistry`): `required this.workspaceSessionGroupsRegistry,`
4. Field (~L517): `final WorkspaceSessionGroupsRegistry workspaceSessionGroupsRegistry;`
5. Pass-through at the construction site (~L2267, beside `workspaceWorktreeRegistry: workspaceWorktreeRegistry`): `workspaceSessionGroupsRegistry: workspaceSessionGroupsRegistry,`

In `client/lib/main.dart`, after `RepositoryProvider<WorkspaceWorktreeRegistry>.value(...)` (~L667):

```dart
                RepositoryProvider<WorkspaceSessionGroupsRegistry>.value(
                  value: shell.workspaceSessionGroupsRegistry,
                ),
```

(import `../services/workspace/workspace_session_groups_registry.dart` — match main.dart's existing import style.)

In `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`, in `build()` beside the `worktreeCubit` resolution (~L236):

```dart
    final sessionGroupsCubit = context
        .read<WorkspaceSessionGroupsRegistry>()
        .cubitFor(widget.workspace.workspaceId);
```

and add to the `MultiBlocProvider.providers` list (~L249):

```dart
        BlocProvider<SessionGroupsCubit>.value(value: sessionGroupsCubit),
```

In `client/lib/pages/home_workspace/home_workspace_shell.dart` (~L398):

```dart
    context.read<WorkspaceSessionGroupsRegistry>().removeWorkspace(
      tab.workspaceId,
    );
```

- [ ] **Step 6: Analyze + full unit suite**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/services/workspace/workspace_session_groups_registry_test.dart test/cubits/session_groups_cubit_test.dart`
Expected: analyze clean, tests PASS. (Full `dart run tool/run_tests.dart` happens in the final task.)

- [ ] **Step 7: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart client/lib/pages/home_workspace/workspace/workspace_split_pane.dart client/lib/pages/home_workspace/home_workspace_shell.dart client/lib/services/workspace/workspace_session_groups_registry.dart client/test/services/workspace/workspace_session_groups_registry_test.dart
git commit -m "feat: provide per-workspace session groups cubit via registry"
```

---

### Task 5: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerates (committed): `client/lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `l10n.sessionGroupCreateTooltip`, `l10n.sessionGroupCreateTitle`, `l10n.sessionGroupNameLabel`, `l10n.sessionGroupRenameTitle`, `l10n.sessionGroupMenuRemove`, `l10n.sessionGroupAddSessionsTooltip`, `l10n.sessionGroupAddSessionsTitle`, `l10n.sessionGroupEmpty` (all plain getters; reused existing keys `save`, `cancel`, `delete` stay untouched).

- [ ] **Step 1: Add keys to both ARBs**

In `app_en.arb` (place near other `worktree*` sidebar keys, e.g. after `"worktreeShowLess"`):

```json
  "sessionGroupCreateTooltip": "New group",
  "@sessionGroupCreateTooltip": {},
  "sessionGroupCreateTitle": "New Group",
  "@sessionGroupCreateTitle": {},
  "sessionGroupNameLabel": "Group name",
  "@sessionGroupNameLabel": {},
  "sessionGroupRenameTitle": "Rename Group",
  "@sessionGroupRenameTitle": {},
  "sessionGroupMenuRemove": "Remove group",
  "@sessionGroupMenuRemove": {},
  "sessionGroupAddSessionsTooltip": "Add conversations",
  "@sessionGroupAddSessionsTooltip": {},
  "sessionGroupAddSessionsTitle": "Add conversations",
  "@sessionGroupAddSessionsTitle": {},
  "sessionGroupEmpty": "No conversations",
  "@sessionGroupEmpty": {},
```

Match whatever `@key` metadata convention the surrounding entries use — if neighbors have no `@` entries, omit them entirely.

In `app_zh.arb` (same position):

```json
  "sessionGroupCreateTooltip": "新建分组",
  "sessionGroupCreateTitle": "新建分组",
  "sessionGroupNameLabel": "分组名称",
  "sessionGroupRenameTitle": "重命名分组",
  "sessionGroupMenuRemove": "删除分组",
  "sessionGroupAddSessionsTooltip": "添加会话",
  "sessionGroupAddSessionsTitle": "添加会话",
  "sessionGroupEmpty": "暂无会话",
```

- [ ] **Step 2: Regenerate and verify**

Run: `flutter gen-l10n && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: generated getters appear in `app_localizations.dart` / `_en` / `_zh`; analyze clean.

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/
git commit -m "feat: l10n strings for manual session groups"
```

---

### Task 6: `SessionGroupSection` widget

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/session_group_section.dart`
- Test: `client/test/pages/home_workspace/workspace/session_group_section_test.dart`

**Interfaces:**
- Consumes: `SessionGroup` (Task 1), `SessionGroupsCubit` (Task 3), `SidebarSessionTile` (existing), `kWorkspaceSidebarRowMinHeight/kWorkspaceSidebarRowPadding/kWorkspaceSidebarGroupTextInset/workspaceSidebarRowHoverFill` from `workspace_sidebar_row_metrics.dart`, row-cap constants mirroring `worktree_group_section.dart` (46 px row height, 8-row collapsed cap, 10-row expanded viewport).
- Produces: `SessionGroupSection({required SessionGroup group, required Workspace workspace, required String tabScopeId, required AppSessionSort sessionSort, String? highlightSessionId})` — used verbatim by Task 8.

Behavior:
- Header row: leading icon (`Icons.label_outline`, chevron swap on hover like `_GroupCollapseLeading`), label + `· N` live-member count, hover-revealed trailing `+` (opens add-sessions dialog), right-click menu with Rename / Remove(destructive, confirm dialog).
- Header tap toggles `SessionGroupsCubit.toggleCollapsed`.
- Members resolve through `ChatCubit.state.sessions`, filtered to ids present in the group AND `workspace.workspaceId`, sorted with `sortAppSessions(sort: sessionSort)`; capped at 8 rows with `More`/`Show less` toggle (`worktreeMore`/`worktreeShowLess` keys); expanded shows a fixed-height viewport of `min(10, n)` rows.
- Expanded with zero live members → muted placeholder row `l10n.sessionGroupEmpty`.
- Add-sessions dialog: `showDialog` listing all workspace sessions with `CheckboxListTile`s prechecked from current membership; Save applies `setMembership(groupId, id, member:)` for every changed row; Cancel discards.

- [ ] **Step 1: Write the failing widget test**

Create `client/test/pages/home_workspace/workspace/session_group_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/session_group_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/utils/session/app_session_sort.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session(String id, {int createdAt = 1}) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  display: id,
  createdAt: createdAt,
  updatedAt: createdAt,
);

Future<SessionGroupsCubit> _readyGroupsCubit(
  List<SessionGroup> groups,
) async {
  final cubit = SessionGroupsCubit();
  await cubit.load(_workspace.workspaceId);
  // Tests start from an explicit group list instead of pre-seeding files.
  cubit.emit(cubit.state.copyWith(groups: groups));
  return cubit;
}

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionGroupsCubit groupsCubit;

  setUp(() {
    setUpTestAppStorage();
    chatCubit = testChatCubit(executableResolver: () => 'claude');
    automationCubit = testAutomationCubit();
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    required List<AppSession> sessions,
    required List<SessionGroup> groups,
  }) async {
    chatCubit.emit(chatCubit.state.copyWith(sessions: sessions));
    groupsCubit = await _readyGroupsCubit(groups);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(
                value: SessionRepository(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: chatCubit),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>.value(value: groupsCubit),
              ],
              child: SizedBox(
                width: 280,
                child: SessionGroupSection(
                  group: groups.first,
                  workspace: _workspace,
                  tabScopeId: 'tab-1',
                  sessionSort: AppSessionSort.recentlyUpdated,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders sorted member rows and header count', (tester) async {    await pumpSection(
      tester,
      sessions: [_session('old', createdAt: 1), _session('new', createdAt: 5)],
      groups: const [
        SessionGroup(id: 'g1', name: '待办', sessionIds: ['old', 'new']),
      ],
    );

    expect(find.text('待办'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets); // member count
    final tiles = tester.widgetList<SidebarSessionTile>(
      find.byType(SidebarSessionTile),
    ).map((t) => t.session.sessionId).toList();
    expect(tiles, ['new', 'old']); // recentlyUpdated sort
  });

  testWidgets('collapse header hides rows; expand restores them', (
    tester,
  ) async {
    await pumpSection(
      tester,
      sessions: [_session('a')],
      groups: const [
        SessionGroup(id: 'g1', name: 'G', sessionIds: ['a']),
      ],
    );

    await tester.tap(find.text('G'));
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsNothing);
    expect(groupsCubit.state.groupById('g1')!.collapsed, isTrue);

    await tester.tap(find.text('G'));
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsOneWidget);
  });

  testWidgets('caps at eight rows with a More toggle', (tester) async {
    await pumpSection(
      tester,
      sessions: [
        for (var i = 0; i < 12; i++)
          _session('s$i', createdAt: 20 - i),
      ],
      groups: [
        SessionGroup(
          id: 'g1',
          name: 'Big',
          sessionIds: [for (var i = 0; i < 12; i++) 's$i'],
        ),
      ],
    );

    expect(find.byType(SidebarSessionTile), findsNWidgets(8));
    expect(find.text('More'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsNWidgets(10));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('expanded empty group shows placeholder', (tester) async {
    await pumpSection(
      tester,
      sessions: [_session('a')],
      groups: const [SessionGroup(id: 'g1', name: 'Empty')],
    );

    expect(find.text('No conversations'), findsOneWidget);
  });

  testWidgets('header + opens add dialog; checking adds membership', (
    tester,
  ) async {
    await pumpSection(
      tester,
      sessions: [_session('a'), _session('b')],
      groups: const [SessionGroup(id: 'g1', name: 'G', sessionIds: [])],
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'a'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(groupsCubit.state.groupById('g1')!.containsSession('a'), isTrue);
    expect(groupsCubit.state.groupById('g1')!.containsSession('b'), isFalse);
  });
}
```

- The Save/Cancel labels come from existing l10n (`save`, `cancel`); resolve them via `AppLocalizations.of(tester.element(find.byType(SessionGroupSection)))` instead of hard-coded English where practical.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pages/home_workspace/workspace/session_group_section_test.dart`
Expected: FAIL — `session_group_section.dart` does not exist.

- [ ] **Step 3: Write the widget**

Create `client/lib/pages/home_workspace/workspace/session_group_section.dart` following the structure of `worktree_group_section.dart` (same row metrics, cap constants, show-more pattern). Full content:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat/model/chat_state.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/session_groups_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/session_group.dart';
import '../../../models/workspace.dart';
import '../../../utils/session/app_session_sort.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_session_actions.dart';
import 'workspace_sidebar_row_metrics.dart';

/// Approximate row height of a session tile in the sidebar list.
const double _groupSessionRowHeight = 46;

/// Max session rows shown before the user expands a group.
const int _groupCollapsedCap = 8;

/// Row count of the fixed-height scrollable an expanded group reveals.
const int _groupExpandedRowCount = 10;

/// One manual ("todo"-style) session group block in [WorkspaceSidebar]:
/// collapsible header, tag-style member rows, context-managed lifecycle.
class SessionGroupSection extends StatelessWidget {
  const SessionGroupSection({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    this.highlightSessionId,
    super.key,
  });

  final SessionGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final String? highlightSessionId;

  void _toggleCollapse(BuildContext context) {
    context.read<SessionGroupsCubit>().toggleCollapsed(group.id);
  }

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<SessionGroupsCubit>();
    final l10n = context.l10n;
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.sessionGroupRenameTitle,
      initialText: group.name,
      labelText: l10n.sessionGroupNameLabel,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
    );
    if (name == null || name.trim().isEmpty || name.trim() == group.name) {
      return;
    }
    cubit.renameGroup(group.id, name.trim());
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final cubit = context.read<SessionGroupsCubit>();
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sessionGroupMenuRemove),
        content: Text(group.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    cubit.deleteGroup(group.id);
  }

  Future<void> _openAddSessionsDialog(BuildContext context) async {
    final cubit = context.read<SessionGroupsCubit>();
    final l10n = context.l10n;
    final workspaceSessions = context
        .read<ChatCubit>()
        .state
        .sessions
        .where((s) => s.workspaceId == workspace.workspaceId)
        .toList();
    if (workspaceSessions.isEmpty) return;

    final selected = group.sessionIds.toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.sessionGroupAddSessionsTitle),
          content: SizedBox(
            width: 360,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: workspaceSessions.length,
              itemBuilder: (dialogContext, index) {
                final session = workspaceSessions[index];
                final title = session.resolveDisplayTitle(
                  l10n.defaultNewChatSessionTitle,
                );
                return CheckboxListTile(
                  value: selected.contains(session.sessionId),
                  onChanged: (checked) => setState(
                    () => checked ?? false
                        ? selected.add(session.sessionId)
                        : selected.remove(session.sessionId),
                  ),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    for (final session in workspaceSessions) {
      final member = selected.contains(session.sessionId);
      if (member != group.containsSession(session.sessionId)) {
        cubit.setMembership(group.id, session.sessionId, member: member);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveMemberCount = _liveMembers(context.read<ChatCubit>().state).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionGroupHeader(
          group: group,
          liveMemberCount: liveMemberCount,
          onToggleCollapse: () => _toggleCollapse(context),
          onRename: () => unawaited(_rename(context)),
          onDelete: () => unawaited(_confirmAndDelete(context)),
          onAddSessions: () => unawaited(_openAddSessionsDialog(context)),
        ),
        if (!group.collapsed)
          _SessionGroupMemberList(
            group: group,
            workspace: workspace,
            tabScopeId: tabScopeId,
            sessionSort: sessionSort,
            highlightSessionId: highlightSessionId,
          ),
      ],
    );
  }

  List<AppSession> _liveMembers(ChatState state) {
    final byId = {for (final s in state.sessions) s.sessionId: s};
    return [
      for (final id in group.sessionIds)
        if (byId[id] case final session?)
          if (session.workspaceId == workspace.workspaceId) session,
    ];
  }
}

class _SessionGroupHeader extends StatefulWidget {
  const _SessionGroupHeader({
    required this.group,
    required this.liveMemberCount,
    required this.onToggleCollapse,
    required this.onRename,
    required this.onDelete,
    required this.onAddSessions,
  });

  final SessionGroup group;
  final int liveMemberCount;
  final VoidCallback onToggleCollapse;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddSessions;

  @override
  State<_SessionGroupHeader> createState() => _SessionGroupHeaderState();
}

class _SessionGroupHeaderState extends State<_SessionGroupHeader> {
  var _rowHovered = false;
  var _menuOpen = false;

  bool get _showRowActions => _rowHovered || _menuOpen;

  Future<void> _showContextMenu(TapDownDetails details) async {
    final l10n = context.l10n;
    setState(() => _menuOpen = true);
    final selected = await showTpActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: details,
      specs: [
        TpActionMenuSpec.item(
          value: 'add_sessions',
          icon: Icons.playlist_add_rounded,
          label: l10n.sessionGroupAddSessionsTitle,
        ),
        TpActionMenuSpec.item(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: l10n.sessionGroupRenameTitle,
        ),
        TpActionMenuSpec.item(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: l10n.sessionGroupMenuRemove,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    switch (selected) {
      case 'add_sessions':
        widget.onAddSessions();
      case 'rename':
        widget.onRename();
      case 'delete':
        widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.tpIconSizes;
    final collapsed = widget.group.collapsed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TpHoverRow(
        forceShowTrailing: _menuOpen,
        forceHover: _menuOpen,
        padding: kWorkspaceSidebarRowPadding,
        hoverColor: workspaceSidebarRowHoverFill(cs),
        onHoverChanged: (hovered) => setState(() => _rowHovered = hovered),
        onTap: widget.onToggleCollapse,
        onSecondaryTapDown: (details) => unawaited(_showContextMenu(details)),
        trailing: TpIconButton(
          icon: Icons.add_rounded,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: context.l10n.sessionGroupAddSessionsTooltip,
          onTap: widget.onAddSessions,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: Icon(
                  _showRowActions
                      ? collapsed
                            ? Icons.chevron_right_rounded
                            : Icons.expand_more_rounded
                      : Icons.label_outline,
                  size: icons.md,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kWorkspaceSidebarRowMinHeight,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.group.name} · ${widget.liveMemberCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Member tiles for one manual group: sorted by the workspace sort, capped at
/// [_groupCollapsedCap]; expanding reveals a fixed-height scrollable viewport
/// so a large group never floods the sidebar. Read-only ordering — no drag.
class _SessionGroupMemberList extends StatefulWidget {
  const _SessionGroupMemberList({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    this.highlightSessionId,
  });

  final SessionGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final String? highlightSessionId;

  @override
  State<_SessionGroupMemberList> createState() =>
      _SessionGroupMemberListState();
}

class _SessionGroupMemberListState extends State<_SessionGroupMemberList> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chatState = context.read<ChatCubit>().state;
    final byId = {for (final s in chatState.sessions) s.sessionId: s};
    final all = sortAppSessions(
      [
        for (final id in widget.group.sessionIds)
          if (byId[id] case final session?)
            if (session.workspaceId == widget.workspace.workspaceId) session,
      ],
      sort: widget.sessionSort,
    );
    if (all.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          kWorkspaceSidebarGroupTextInset,
          0,
          kWorkspaceSidebarRowPadding.right,
          kWorkspaceSidebarRowPadding.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kWorkspaceSidebarRowMinHeight,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.sessionGroupEmpty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context).mdColored(
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      );
    }

    final overflow = all.length - _groupCollapsedCap;
    final visible = (_showAll || overflow <= 0)
        ? all
        : all.take(_groupCollapsedCap).toList();
    final height =
        math.min(_groupExpandedRowCount, visible.length) *
        _groupSessionRowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: overflow > 0 || visible.length > _groupCollapsedCap
              ? height
              : null,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            physics:
                overflow > 0 || visible.length > _groupCollapsedCap
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            shrinkWrap: !(overflow > 0 || visible.length > _groupCollapsedCap),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final session = visible[index];
              return SidebarSessionTile(
                key: ValueKey('manual-group-session-${session.sessionId}'),
                session: session,
                highlightSessionId: widget.highlightSessionId,
                tapThrottleKeyPrefix: 'manual_group_session',
                onTap: () => openWorkspaceSessionTab(
                  context,
                  widget.workspace,
                  session,
                  tabScopeId: widget.tabScopeId,
                ),
              );
            },
          ),
        ),
        if (overflow > 0)
          _SessionGroupShowMoreRow(
            label: _showAll ? l10n.worktreeShowLess : l10n.worktreeMore,
            onTap: () => setState(() => _showAll = !_showAll),
          ),
      ],
    );
  }
}
```

Notes:
- Import `'workspace_session_actions.dart'` for `openWorkspaceSessionTab`, exactly as `worktree_group_section.dart:482` uses it.
- If `openWorkspaceSessionTab`'s transitive imports break the bare test harness at compile time, keep the tile `onTap` a no-op `() {}` — these tests never tap rows.
- `_SessionGroupShowMoreRow` is a copy of `_GroupShowMoreRow` from `worktree_group_section.dart:504-555` (same padding, hover fill, muted text style) — duplicate it into this file since the original is private.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/pages/home_workspace/workspace/session_group_section_test.dart`
Expected: PASS (all five tests). Adjust the add-dialog finder (`CheckboxListTile` text, `Save`) to actual rendered labels if l10n differs.

- [ ] **Step 5: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/session_group_section.dart client/test/pages/home_workspace/workspace/session_group_section_test.dart
git commit -m "feat: collapsible manual session group section in sidebar"
```

---

### Task 7: Session-row context-menu membership toggles

**Files:**
- Modify: `client/lib/widgets/sidebar_session_tile.dart` (`_contextMenuItems` ~L144, `_handleContextAction` ~L196; import)
- Test: modify `client/test/widgets/sidebar_session_tile_test.dart` (extend `_host`, add tests)

**Interfaces:**
- Consumes: `SessionGroupsCubit` (Task 3) — resolved defensively (`try context.read` → absent provider yields no extra items), so every existing `SidebarSessionTile` call site stays valid.
- Produces: menu values `'toggle_group:<groupId>'`; handled inside the tile.

- [ ] **Step 1: Extend the tile test harness and add failing tests**

In `client/test/widgets/sidebar_session_tile_test.dart`:

1. Imports: add `session_groups_cubit.dart`, `models/session_group.dart`.
2. Change `_host` signature to accept `SessionGroupsCubit? groupsCubit` and, when non-null, add `BlocProvider<SessionGroupsCubit>.value(value: groupsCubit)` to the providers list.
3. Add a `_groupsCubit(List<SessionGroup> groups)` helper next to `_tileCubits`:

```dart
Future<SessionGroupsCubit> _groupsCubit(List<SessionGroup> groups) async {
  final cubit = SessionGroupsCubit();
  await cubit.load(_session.workspaceId);
  cubit.emit(cubit.state.copyWith(groups: groups));
  return cubit;
}
```
4. New tests (inside `main`, after the automations ones), following the `_openContextMenu`/`_dismissContextMenu` helpers:

```dart
  testWidgets('context menu lists groups with membership checkmarks', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    final groupsCubit = await _groupsCubit([
      const SessionGroup(id: 'g1', name: '待办'),
      const SessionGroup(id: 'g2', name: 'Review', sessionIds: ['sess-1']),
    ]);
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);
    addTearDown(groupsCubit.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
        groupsCubit: groupsCubit,
      ),
    );
    await tester.pump();

    await _openContextMenu(tester);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    // sess-1 already in g2 → check-box icon present twice (leading icons).
    expect(
      find.byIcon(Icons.check_box_outlined),
      findsOneWidget,
    );
    await _dismissContextMenu(tester);
  });

  testWidgets('tapping a group item toggles membership', (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    final groupsCubit = await _groupsCubit([
      const SessionGroup(id: 'g1', name: '待办'),
    ]);
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);
    addTearDown(groupsCubit.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
        groupsCubit: groupsCubit,
      ),
    );
    await tester.pump();

    await _openContextMenu(tester);
    await tester.tap(find.text('待办'));
    await tester.pump();
    expect(groupsCubit.state.groupById('g1')!.containsSession('sess-1'), isTrue);

    await _openContextMenu(tester);
    await tester.tap(find.text('待办'));
    await tester.pump();
    expect(groupsCubit.state.groupById('g1')!.containsSession('sess-1'), isFalse);
  });

  testWidgets('no group provider → menu unchanged', (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final (attention, automationCubit) = _tileCubits();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);
    addTearDown(attention.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        attentionCubit: attention,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();
    await _openContextMenu(tester);
    expect(find.byIcon(Icons.check_box_outlined), findsNothing);
    await _dismissContextMenu(tester);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/widgets/sidebar_session_tile_test.dart`
Expected: NEW tests FAIL (helper `_groupsCubit` undefined until added — add the helper first so failures are assertion-level, i.e. missing menu items).

- [ ] **Step 3: Implement menu items**

In `client/lib/widgets/sidebar_session_tile.dart`:

Import `../cubits/session_groups_cubit.dart` and `../models/session_group.dart` (only if needed for types).

In `_contextMenuItems` (L144–194), insert after the pin item:

```dart
      ..._sessionGroupItems(session),
```

Add the methods:

```dart
  /// Tag-style group toggles from [SessionGroupsCubit]; silently omitted when
  /// the caller has no group provider (e.g. floating windows).
  List<TpActionMenuPopupItem<String>> _sessionGroupItems(AppSession session) {
    final SessionGroupsCubit cubit;
    try {
      cubit = context.read<SessionGroupsCubit>();
    } on Object {
      return const [];
    }
    final state = cubit.state;
    if (!state.ready || state.groups.isEmpty) return const [];
    final memberOf = state.groupIdsContaining(session.sessionId);
    return [
      for (final group in state.groups)
        TpActionMenuPopupItem(
          value: 'toggle_group:${group.id}',
          iconWidget: Icon(
            memberOf.contains(group.id)
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank_outlined,
            size: context.tpIconSizes.sm,
          ),
          label: group.name,
        ),
    ];
  }
```

In `_handleContextAction`'s `switch (selected)` add a guarded clause (Dart 3 switch-statement pattern):

```dart
      case String value when value.startsWith('toggle_group:'):
        final groupId = value.substring('toggle_group:'.length);
        final groups = context.read<SessionGroupsCubit>().state;
        final group = groups.groupById(groupId);
        if (group != null) {
          context.read<SessionGroupsCubit>().setMembership(
            groupId,
            session.sessionId,
            member: !group.containsSession(session.sessionId),
          );
        }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/widgets/sidebar_session_tile_test.dart`
Expected: PASS including all pre-existing tests.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/sidebar_session_tile.dart client/test/widgets/sidebar_session_tile_test.dart
git commit -m "feat: add-to-group toggles in session row context menu"
```

---

### Task 8: Sidebar integration — host + create-group button

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` (imports; header row ~L136; `_ConversationListHost.build` ~L361–396; new private widgets)
- Test: create `client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart`

**Interfaces:**
- Consumes: `SessionGroupsCubit` (Task 3, provided in Task 4), `SessionGroupSection` (Task 6).
- Produces: `_ManualGroupsHost` rendered above the list in every layout mode; `+` create button in the conversations-section header row (always visible, independent of `toolsContext`).

- [ ] **Step 1: Write the failing sidebar test**

Create `client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart`, modeled on `workspace_sidebar_grouped_virtualization_test.dart` (reuse its `pumpSidebar` harness shape verbatim, adding one provider):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  display: id,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionGroupsCubit groupsCubit;
  late SessionRepository sessionRepository;

  setUp(() {
    setUpTestAppStorage();
    sessionRepository = SessionRepository();
    chatCubit = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: sessionRepository,
    );
    automationCubit = testAutomationCubit();
    worktreeCubit = WorktreeCubit();
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
    groupsCubit = SessionGroupsCubit();
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
    await groupsCubit.load(_workspace.workspaceId);
    chatCubit.emit(
      chatCubit.state.copyWith(sessions: [_session('a'), _session('b')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(
                value: sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>(create: (_) => chatCubit),
                BlocProvider<WorkbenchCubit>(create: (_) => WorkbenchCubit()),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>.value(value: groupsCubit),
              ],
              child: SizedBox(
                width: 320,
                height: 1000,
                child: WorkspaceSidebar(
                  workspace: _workspace,
                  tabScopeId: 'ws-1',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('created group renders above the list with its members', (
    tester,
  ) async {
    await pumpSidebar(tester);
    expect(find.byType(SidebarSessionTile), findsNWidgets(2)); // main list

    groupsCubit.createGroup('待办');
    groupsCubit.addSession(groupsCubit.state.groups.single.id, 'a');
    await tester.pump();

    // Member 'a' now appears twice: manual block + main list (tag-style).
    expect(find.byType(SidebarSessionTile), findsNWidgets(3));
    expect(find.text('待办'), findsOneWidget);
  });

  testWidgets('collapsing a manual block hides only block rows', (
    tester,
  ) async {
    await pumpSidebar(tester);
    groupsCubit.createGroup('G');
    groupsCubit.addSession(groupsCubit.state.groups.single.id, 'a');
    await tester.pump();

    await tester.tap(find.text('G'));
    await tester.pump();
    // Block rows hidden; main list untouched.
    expect(find.byType(SidebarSessionTile), findsNWidgets(2));
  });

  testWidgets('+ header button opens create dialog and creates group', (
    tester,
  ) async {
    await pumpSidebar(tester);

    await tester.tap(find.byTooltip('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '待办');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(groupsCubit.state.groups.single.name, '待办');
    expect(find.text('待办'), findsOneWidget);
  });
}
```

(Add the missing `workbench/workbench_cubit.dart` import; adjust the tooltip/save finders to actual l10n output if different.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart`
Expected: FAIL — no `SessionGroupsCubit` provider in tree / no group UI.

- [ ] **Step 3: Implement sidebar changes**

In `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`:

Imports:

```dart
import '../../../cubits/session_groups_cubit.dart';
import '../../../models/session_group.dart';
import 'session_group_section.dart';
```

Header row (L126–173): after the `_SessionSortButton` widget and before the worktree buttons, insert:

```dart
                const SizedBox(width: 2),
                TpIconButton(
                  icon: Icons.new_label_outlined,
                  compact: true,
                  size: TpIconButton.kCompactSize,
                  tooltip: l10n.sessionGroupCreateTooltip,
                  onTap: throttledTap(
                    'workspace_sidebar_new_group',
                    () => unawaited(_createSessionGroup(context)),
                  ),
                ),
```

and the method on `_WorkspaceSidebarState`:

```dart
  Future<void> _createSessionGroup(BuildContext context) async {
    final l10n = context.l10n;
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.sessionGroupCreateTitle,
      labelText: l10n.sessionGroupNameLabel,
      confirmLabel: l10n.save,
      cancelLabel: l10n.cancel,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    context.read<SessionGroupsCubit>().createGroup(name.trim());
  }
```

(`showTpTextPromptDialog` comes from `shared_ui`, already imported.)

`_ConversationListHost.build` (L361–396): wrap the deferred body so manual groups sit above every layout branch. Replace the `TpDeferredMountShell(...)` child construction with:

```dart
        child: _buildWithManualGroups(
          context,
          TpDeferredMountShell(
            delayFrames: 1,
            placeholder: const _SessionListSkeleton(),
            child: _buildBody(
              context,
              sortedSessions,
              structure,
              wtView,
              sessionsHydrated: sessionsHydrated,
            ),
          ),
        ),
```

and add on `_ConversationListHost`:

```dart
  /// Manual group blocks ride ABOVE every automatic layout (flat, worktree-
  /// grouped, multi-project): bounded stack with its own scroll so a
  /// scrollable is never nested inside the list's scrollable.
  Widget _buildWithManualGroups(BuildContext context, Widget listArea) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ManualGroupsHost(
          workspace: workspace,
          tabScopeId: tabScopeId,
          sessionSort: sessionSort,
          highlightSessionId: scopedActiveSessionId(
            context.read<WorkbenchCubit>(),
            tabScopeId,
          ),
        ),
        Expanded(child: listArea),
      ],
    );
  }
```

(`scopedActiveSessionId`, `WorkspaceToolsScope`… are already imported; `sessionSort` is an existing `_ConversationListHost` field.)

New private widget at the bottom of the file — it hard-requires `SessionGroupsCubit` via `context.select`, exactly like the existing `context.select<ChatCubit, …>` / `<WorktreeCubit, …>` calls in this class (Task 4 guarantees the provider inside `WorkspaceSplitPane`; the sidebar test in Step 1 provides it too):

```dart
/// Renders one [SessionGroupSection] per manual group, bounded to a fixed
/// maxHeight with its own scroll so several expanded blocks cannot overflow
/// the column. Hidden entirely when the workspace has no groups.
class _ManualGroupsHost extends StatelessWidget {
  const _ManualGroupsHost({
    required this.workspace,
    required this.tabScopeId,
    required this.sessionSort,
    required this.highlightSessionId,
  });

  final Workspace workspace;
  final String tabScopeId;
  final AppSessionSort sessionSort;
  final String? highlightSessionId;

  @override
  Widget build(BuildContext context) {
    final groups = context.select<SessionGroupsCubit, List<SessionGroup>>(
      (c) => c.state.ready ? c.state.groups : const <SessionGroup>[],
    );
    if (groups.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups)
              SessionGroupSection(
                key: ValueKey('manual-group-${group.id}'),
                group: group,
                workspace: workspace,
                tabScopeId: tabScopeId,
                sessionSort: sessionSort,
                highlightSessionId: highlightSessionId,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart test/pages/home_workspace/workspace_sidebar_grouped_virtualization_test.dart`
Expected: PASS — new tests green, existing virtualization/layout behavior unchanged (manual host collapses to `SizedBox.shrink` with no groups).

- [ ] **Step 5: Full verification**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: clean analyze; full suite green.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_sidebar.dart client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart
git commit -m "feat: render manual session groups in workspace sidebar"
```

---

## Verification checklist (spec coverage)

- Tag-style multi-membership → Task 3 (`setMembership` additive), Task 7 (toggles), Task 8 test asserts duplicate rows.
- Workspace scope → file path per workspace (Tasks 1–2), cubit per workspace (Task 4).
- Inline collapsible blocks → Task 6 (section), Task 8 (host placement).
- Context-menu add/remove → Task 7.
- Always-on-top across flat/grouped layouts → Task 8 wraps `_buildBody` output for all branches.
- Dedicated storage, models untouched → Tasks 1–3 (no `AppSession`/`Workspace` changes).
- Render-time filtering + prune-on-save → Task 3 `_persist` + `knownSessionIds` wiring in Task 4.
- Corrupt/missing file tolerance → Task 2 test; workspace-switch reload → Task 3 `load` generation guard.
- l10n en/zh → Task 5.
- Tests: store CRUD/prune/corrupt (Task 2), cubit behaviors (Task 3), registry (Task 4), section widget (Task 6), menu toggles (Task 7), sidebar integration (Task 8).
