# 工作区/会话数据增量一致性 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** mutation 后不再全量重扫——repository 返回值增量 patch 内存快照并维护 `workspaces-index.json`,创建 workspace/session 从 ~500ms 降到 ~10ms。

**Architecture:** `SessionRepository` 保持唯一磁盘写入方;mutation 返回新对象 → `SessionDataStore` 增量维护内存快照(含 `Workspace.sessionIds`);mutation 同时增量维护 `WorkspaceIndexStore` 磁盘快照 + `_workspacesIndexByRoot` 缓存;全量重扫(`loadWorkspaceData`)仅保留给 `reloadAll`(home/SSH 切换)。

**Tech Stack:** Dart/Flutter,`flutter_bloc` cubit,`WorkspaceIndexStore`(已有未接线),`SessionSnapshotReader`(同步快路径)。

## Global Constraints

- 单实例前提:同一时间只有一个 TeamPilot 写数据(用户已确认),无需外部变更检测。
- `Workspace.sessionIds` 顺序统一为 **createdAt desc**(稳定排序,同 createdAt 保持原列表顺序)。
- 不要改动 `WorkspaceCatalog`(未接线的平行实现)、`loadSessionsForWorkspace` 按需 hydration 路径、`reloadAll` 的 `loadWorkspaceData`。
- 不要改 `_readManifest(indexOnly: true)` 的语义(createSession 热路径依赖它不读 session.json)。
- 验收:`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` 全绿。
- 提交粒度:每个任务一个 commit,提交信息风格参考 `git log`(如 `feat:`, `refactor:`)。

---

### Task 1: SessionDataStore 增量原语 + sessionIds 维护

**Files:**
- Modify: `client/lib/cubits/chat/session_data_store.dart`
- Modify: `client/lib/cubits/chat_cubit.dart:1474-1487`(patchWorkspace 改用新原语)
- Test: `client/test/cubits/chat/session_data_store_test.dart`

**Interfaces:**
- Produces(本任务新增,后续任务消费):
  - `List<String> SessionDataStore.sortedSessionIdsByCreatedAt(Iterable<AppSession>)`(静态)
  - `ChatDataSnapshot SessionDataStore.appendSession(ChatDataSnapshot base, AppSession session)`(改造:维护 sessionIds)
  - `ChatDataSnapshot SessionDataStore.removeSession(ChatDataSnapshot base, String sessionId)`(改造:维护 sessionIds)
  - `ChatDataSnapshot SessionDataStore.snapshotWithWorkspace(ChatDataSnapshot base, Workspace updated)`
  - `ChatDataSnapshot SessionDataStore.snapshotWithWorkspaceAndSessions(ChatDataSnapshot base, {required Workspace workspace, required List<AppSession> sessions})`
  - `ChatDataSnapshot SessionDataStore.snapshotWithoutWorkspace(ChatDataSnapshot base, String workspaceId)`
- 不改变 `replaceSession`(不维护 sessionIds,顺序不变)。

- [ ] **Step 1: 写失败的测试**

在 `client/test/cubits/chat/session_data_store_test.dart` 追加:

```dart
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';

// 已有 import 不变;若 AppSession 需要额外必填参数,以 models/app_session.dart 构造要求为准。

Workspace _ws(String id, {List<String> sessionIds = const []}) => Workspace(
      workspaceId: id,
      folders: [WorkspaceFolder(path: '/$id')],
      createdAt: 0,
      sessionIds: sessionIds,
    );

AppSession _sess(String id, String wsId, {int createdAt = 0}) => AppSession(
      sessionId: id,
      workspaceId: wsId,
      folders: [WorkspaceFolder(path: '/$wsId')],
      createdAt: createdAt,
    );

void main() {
  // ...既有测试保留...

  test('sortedSessionIdsByCreatedAt is createdAt desc with stable ties', () {
    final ids = SessionDataStore.sortedSessionIdsByCreatedAt([
      _sess('old', 'p', createdAt: 1),
      _sess('mid', 'p', createdAt: 5),
      _sess('new', 'p', createdAt: 10),
      _sess('tie-a', 'p', createdAt: 5),
      _sess('tie-b', 'p', createdAt: 5),
    ]);
    expect(ids, ['new', 'mid', 'tie-a', 'tie-b', 'old']);
  });

  test('appendSession inserts sessionId into workspace sessionIds (createdAt order)', () {
    final store = SessionDataStore();
    final ws = _ws('p', sessionIds: ['old']);
    final base = store.deriveSnapshot(
      workspaces: [ws],
      sessions: [_sess('old', 'p', createdAt: 1)],
    );
    final snap = store.appendSession(base, _sess('new', 'p', createdAt: 9));
    expect(
      snap.workspaces.single.sessionIds,
      ['new', 'old'],
    );
    expect(snap.sessions.map((s) => s.sessionId), ['old', 'new']);
  });

  test('appendSession is idempotent for an existing session id', () {
    final store = SessionDataStore();
    final ws = _ws('p', sessionIds: ['s1']);
    final base = store.deriveSnapshot(
      workspaces: [ws],
      sessions: [_sess('s1', 'p')],
    );
    final snap = store.appendSession(base, _sess('s1', 'p'));
    expect(snap.workspaces.single.sessionIds, ['s1']);
  });

  test('appendSession for unknown workspace leaves sessionIds untouched', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p')],
      sessions: const [],
    );
    final snap = store.appendSession(base, _sess('orphan', 'other'));
    expect(snap.workspaces.single.sessionIds, isEmpty);
    expect(snap.sessions.single.sessionId, 'orphan');
  });

  test('removeSession removes id from sessions and workspace sessionIds', () {
    final store = SessionDataStore();
    final ws = _ws('p', sessionIds: ['a', 'b']);
    final base = store.deriveSnapshot(
      workspaces: [ws],
      sessions: [_sess('a', 'p'), _sess('b', 'p')],
    );
    final snap = store.removeSession(base, 'a');
    expect(snap.workspaces.single.sessionIds, ['b']);
    expect(snap.sessions.map((s) => s.sessionId), ['b']);
  });

  test('snapshotWithWorkspace replaces workspace but preserves sessionIds', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p', sessionIds: ['a', 'b'])],
      sessions: [_sess('a', 'p'), _sess('b', 'p')],
    );
    final updated = _ws('p').copyWith(display: 'renamed');
    final snap = store.snapshotWithWorkspace(base, updated);
    expect(snap.workspaces.single.display, 'renamed');
    expect(snap.workspaces.single.sessionIds, ['a', 'b']);
  });

  test('snapshotWithWorkspace adds a brand-new workspace', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(workspaces: [_ws('p')], sessions: const []);
    final snap = store.snapshotWithWorkspace(base, _ws('q'));
    expect(snap.workspaces.map((w) => w.workspaceId), ['p', 'q']);
  });

  test('snapshotWithWorkspaceAndSessions replaces workspace sessions and rebuilds sessionIds', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p', sessionIds: ['old'])],
      sessions: [_sess('old', 'p')],
    );
    final snap = store.snapshotWithWorkspaceAndSessions(
      base,
      workspace: _ws('p'),
      sessions: [_sess('n1', 'p', createdAt: 2), _sess('n2', 'p', createdAt: 1)],
    );
    expect(snap.workspaces.single.sessionIds, ['n1', 'n2']);
    expect(snap.sessions.map((s) => s.sessionId), ['n1', 'n2']);
  });

  test('snapshotWithoutWorkspace removes workspace and its sessions', () {
    final store = SessionDataStore();
    final base = store.deriveSnapshot(
      workspaces: [_ws('p'), _ws('q')],
      sessions: [_sess('a', 'p'), _sess('b', 'q')],
    );
    final snap = store.snapshotWithoutWorkspace(base, 'p');
    expect(snap.workspaces.map((w) => w.workspaceId), ['q']);
    expect(snap.sessions.map((s) => s.sessionId), ['b']);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test --no-pub test/cubits/chat/session_data_store_test.dart`
Expected: FAIL — 新方法未定义/`appendSession` 不改 sessionIds。

- [ ] **Step 3: 实现 SessionDataStore 增量原语**

`client/lib/cubits/chat/session_data_store.dart`,在 `deriveSnapshot` 之后追加:

```dart
  /// Stable createdAt-desc sort: equal createdAt keeps input order.
  static List<String> sortedSessionIdsByCreatedAt(
    Iterable<AppSession> sessions,
  ) {
    final indexed = <({AppSession session, int index})>[];
    var index = 0;
    for (final session in sessions) {
      indexed.add((session: session, index: index));
      index++;
    }
    indexed.sort((a, b) {
      final byCreated = b.session.createdAt.compareTo(a.session.createdAt);
      return byCreated != 0 ? byCreated : a.index.compareTo(b.index);
    });
    return [for (final e in indexed) e.session.sessionId];
  }
```

改造 `appendSession`(现 173-178 行):

```dart
  ChatDataSnapshot appendSession(ChatDataSnapshot base, AppSession session) {
    return deriveSnapshot(
      workspaces: [
        for (final workspace in base.workspaces)
          if (workspace.workspaceId == session.workspaceId)
            _withInsertedSessionId(base, workspace, session)
          else
            workspace,
      ],
      sessions: [...base.sessions, session],
    );
  }

  Workspace _withInsertedSessionId(
    ChatDataSnapshot base,
    Workspace workspace,
    AppSession session,
  ) {
    if (workspace.sessionIds.contains(session.sessionId)) return workspace;
    final workspaceSessions = [
      for (final s in base.sessions)
        if (s.workspaceId == workspace.workspaceId) s,
      session,
    ];
    return workspace.copyWith(
      sessionIds: sortedSessionIdsByCreatedAt(workspaceSessions),
    );
  }
```

改造 `removeSession`(现 191-199 行):

```dart
  ChatDataSnapshot removeSession(ChatDataSnapshot base, String sessionId) {
    return deriveSnapshot(
      workspaces: [
        for (final workspace in base.workspaces)
          if (workspace.sessionIds.contains(sessionId))
            workspace.copyWith(
              sessionIds: [
                for (final id in workspace.sessionIds)
                  if (id != sessionId) id,
              ],
            )
          else
            workspace,
      ],
      sessions: [
        for (final s in base.sessions)
          if (s.sessionId != sessionId) s,
      ],
    );
  }
```

在 `removeSession` 之后追加三个新原语:

```dart
  /// Replaces [updated] in the snapshot; keeps the current snapshot's
  /// sessionIds (in-memory maintenance is the source of truth for order).
  ChatDataSnapshot snapshotWithWorkspace(
    ChatDataSnapshot base,
    Workspace updated,
  ) {
    final existing = base.workspaces
        .where((w) => w.workspaceId == updated.workspaceId)
        .firstOrNull;
    final withIds = existing != null
        ? updated.copyWith(sessionIds: existing.sessionIds)
        : updated;
    final replaced = existing == null
        ? [...base.workspaces, withIds]
        : [
            for (final w in base.workspaces)
              if (w.workspaceId == updated.workspaceId) withIds else w,
          ];
    return deriveSnapshot(workspaces: replaced, sessions: base.sessions);
  }

  /// Replaces [workspace] and every session it owns with [sessions];
  /// sessionIds are rebuilt from [sessions] (createdAt desc).
  ChatDataSnapshot snapshotWithWorkspaceAndSessions(
    ChatDataSnapshot base, {
    required Workspace workspace,
    required List<AppSession> sessions,
  }) {
    final withIds = workspace.copyWith(
      sessionIds: sortedSessionIdsByCreatedAt(
        sessions.where((s) => s.workspaceId == workspace.workspaceId),
      ),
    );
    final replaced = [
      for (final w in base.workspaces)
        if (w.workspaceId == workspace.workspaceId) withIds else w,
    ];
    if (!base.workspaces.any((w) => w.workspaceId == workspace.workspaceId)) {
      replaced.add(withIds);
    }
    return deriveSnapshot(
      workspaces: replaced,
      sessions: [
        for (final s in base.sessions)
          if (s.workspaceId != workspace.workspaceId) s,
        ...sessions,
      ],
    );
  }

  ChatDataSnapshot snapshotWithoutWorkspace(
    ChatDataSnapshot base,
    String workspaceId,
  ) {
    return deriveSnapshot(
      workspaces: [
        for (final w in base.workspaces)
          if (w.workspaceId != workspaceId) w,
      ],
      sessions: [
        for (final s in base.sessions)
          if (s.workspaceId != workspaceId) s,
      ],
    );
  }
```

注:`firstOrNull` 需确认本文件可用(chat_cubit.dart 已在用;若 analyze 报错,改用手写循环查找)。

- [ ] **Step 4: 升级 ChatCubit.patchWorkspace 走新原语**

`client/lib/cubits/chat_cubit.dart:1474-1487` 改为:

```dart
  void patchWorkspace(Workspace updated) {
    _emitSnapshot(
      _dataStore.snapshotWithWorkspace(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        updated,
      ),
    );
  }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test --no-pub test/cubits/chat/session_data_store_test.dart`
Expected: PASS(新测试 + 既有 3 个 scope 测试)。

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/chat/session_data_store.dart client/lib/cubits/chat_cubit.dart client/test/cubits/chat/session_data_store_test.dart
git commit -m "feat: SessionDataStore 增量快照原语并维护 workspace.sessionIds"
```

---

### Task 2: SessionDataStore mutation 方法改为增量(不再全量重扫)

**Files:**
- Modify: `client/lib/cubits/chat/session_data_store.dart`(mutation 方法签名 + 实现)
- Modify: `client/lib/cubits/chat_cubit.dart`(调用点适配新签名)
- Test: `client/test/cubits/chat/session_data_store_test.dart`(mutation 行为测试)

**Interfaces:**
- Consumes: Task 1 的 `snapshotWithWorkspace` / `snapshotWithWorkspaceAndSessions` / `snapshotWithoutWorkspace` / `appendSession` / `removeSession`。
- Produces(签名变更,调用方同步改):
  - `Future<ChatDataSnapshot?> updateWorkspaceMetadata(ChatDataSnapshot base, SessionRepository repo, String workspaceId, {String? display, String? defaultProfileId, bool? rootSandboxEnvOptIn})`
  - `Future<ChatDataSnapshot?> applyWorkspaceIcon(ChatDataSnapshot base, SessionRepository repo, String workspaceId, WorkspaceIconRef icon)`
  - `Future<ChatDataSnapshot?> importCustomWorkspaceIcon(ChatDataSnapshot base, SessionRepository repo, String workspaceId, String localSourcePath)`
  - `Future<ChatDataSnapshot?> addWorkspaceDirectory(ChatDataSnapshot base, SessionRepository repo, Workspace workspace, WorkspaceFolder folder)`
  - `Future<ChatDataSnapshot> deleteSessionRecord(ChatDataSnapshot base, SessionRepository repo, String sessionId)`
  - `Future<ChatDataSnapshot> deleteWorkspaceRecord(ChatDataSnapshot base, SessionRepository repo, String workspaceId)`
  - `Future<({String workspaceId, ChatDataSnapshot snapshot})> createWorkspaceWithFirstSession(ChatDataSnapshot base, List<WorkspaceFolder> folders, SessionRepository repo, {...})`(原参数保留)
  - `Future<({Workspace workspace, ChatDataSnapshot snapshot})> cloneWorkspace(ChatDataSnapshot base, SessionRepository repo, String sourceWorkspaceId, {String? display, List<TeamMemberConfig> rosterMembers = const []})`

- [ ] **Step 1: 写失败的测试**

在 `client/test/cubits/chat/session_data_store_test.dart` 追加(需要 `session_repository.dart` 导入与临时目录仓库;仓库构造参考 `client/test/repositories/session_repository_test.dart` 的 `setUpTestAppStorage` / `rootDir` 用法,如该测试用 `SessionRepository(rootDir: tmp)` 则照抄):

```dart
// 在既有 imports 后追加:
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/session_repository.dart';
// WorkspaceIconRef 若 applyWorkspaceIcon 测试需要则 import models/workspace_icon_ref.dart

test('updateWorkspaceMetadata patches snapshot without disk rescan', () async {
  final tmp = await Directory.systemTemp.createTemp('sds_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final store = SessionDataStore();
  var base = store.deriveSnapshot(workspaces: [ws], sessions: const []);
  base = store.appendSession(
    base,
    await (await repo.createSession(ws.workspaceId)).session,
  );

  final snap = await store.updateWorkspaceMetadata(
    base,
    repo,
    ws.workspaceId,
    display: 'renamed',
  );
  expect(snap, isNotNull);
  expect(snap!.workspaces.single.display, 'renamed');
  expect(
    snap.workspaces.single.sessionIds,
    base.workspaces.single.sessionIds,
    reason: 'manifest-only update must preserve sessionIds',
  );
  expect(snap.sessions.length, base.sessions.length);
  await tmp.delete(recursive: true);
});

test('updateWorkspaceMetadata returns null when workspace missing', () async {
  final tmp = await Directory.systemTemp.createTemp('sds_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final store = SessionDataStore();
  final base = store.deriveSnapshot(workspaces: const [], sessions: const []);
  final snap = await store.updateWorkspaceMetadata(
    base,
    repo,
    'missing',
    display: 'x',
  );
  expect(snap, isNull);
  await tmp.delete(recursive: true);
});

test('deleteSessionRecord removes session and sessionIds incrementally', () async {
  final tmp = await Directory.systemTemp.createTemp('sds_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  final store = SessionDataStore();
  var base = store.deriveSnapshot(
    workspaces: [ws.copyWith(sessionIds: [created.session.sessionId])],
    sessions: [created.session],
  );
  final snap = await store.deleteSessionRecord(base, repo, created.session.sessionId);
  expect(snap.sessions, isEmpty);
  expect(snap.workspaces.single.sessionIds, isEmpty);
  await tmp.delete(recursive: true);
});

test('deleteWorkspaceRecord removes workspace and its sessions incrementally', () async {
  final tmp = await Directory.systemTemp.createTemp('sds_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  final store = SessionDataStore();
  final base = store.deriveSnapshot(
    workspaces: [ws.copyWith(sessionIds: [created.session.sessionId])],
    sessions: [created.session],
  );
  final snap = await store.deleteWorkspaceRecord(base, repo, ws.workspaceId);
  expect(snap.workspaces, isEmpty);
  expect(snap.sessions, isEmpty);
  await tmp.delete(recursive: true);
});

test('cloneWorkspace patches snapshot with cloned workspace and sessions', () async {
  final tmp = await Directory.systemTemp.createTemp('sds_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  final store = SessionDataStore();
  final base = store.deriveSnapshot(
    workspaces: [ws.copyWith(sessionIds: [created.session.sessionId])],
    sessions: [created.session],
  );
  final result = await store.cloneWorkspace(base, repo, ws.workspaceId);
  expect(result.workspace.workspaceId, isNot(ws.workspaceId));
  expect(result.snapshot.workspaces.length, 2);
  expect(result.snapshot.workspaces.last.sessionIds, [result.workspace.sessionIds.single]);
  expect(result.snapshot.sessions.length, 2);
  await tmp.delete(recursive: true);
});

test('createWorkspaceWithFirstSession returns snapshot with new workspace and session', () async {
  final tmp = await Directory.systemTemp.createTemp('sds_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final store = SessionDataStore();
  final base = store.deriveSnapshot(workspaces: const [], sessions: const []);
  final result = await store.createWorkspaceWithFirstSession(
    base,
    [WorkspaceFolder(path: '/p')],
    repo,
  );
  expect(result.snapshot.workspaces.single.sessionIds, [result.snapshot.sessions.single.sessionId]);
  expect(result.workspaceId, result.snapshot.workspaces.single.workspaceId);
  await tmp.delete(recursive: true);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test --no-pub test/cubits/chat/session_data_store_test.dart`
Expected: FAIL — 编译错误(签名不匹配)。

- [ ] **Step 3: 改写 SessionDataStore mutation 方法**

在 `session_data_store.dart` 顶部 import 处确认已有 `workspace_icon_ref.dart`。所有 mutation 方法加 `ChatDataSnapshot base` 首参并改为增量:

```dart
  Future<ChatDataSnapshot?> updateWorkspaceMetadata(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
  }) async {
    final updated = await repo.updateWorkspaceMetadata(
      workspaceId,
      display: display,
      defaultProfileId: defaultProfileId,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn,
    );
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot?> applyWorkspaceIcon(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId,
    WorkspaceIconRef icon,
  ) async {
    final updated = await repo.applyWorkspaceIcon(workspaceId, icon);
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot?> importCustomWorkspaceIcon(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId,
    String localSourcePath,
  ) async {
    final updated = await repo.importCustomWorkspaceIcon(
      workspaceId,
      localSourcePath,
    );
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot?> addWorkspaceDirectory(
    ChatDataSnapshot base,
    SessionRepository repo,
    Workspace workspace,
    WorkspaceFolder folder,
  ) async {
    if (folder.path.trim().isEmpty) return null;
    if (workspacePathsEqual(folder.path, workspace.firstFolderPath)) return null;
    if (workspace.folders.any(
      (f) => workspacePathsEqual(f.path, folder.path),
    )) {
      return null;
    }
    final updated = await repo.updateWorkspaceFolders(workspace.workspaceId, [
      ...workspace.folders,
      folder.copyWith(path: normalizeWorkspacePath(folder.path)),
    ]);
    if (updated == null) return null;
    return snapshotWithWorkspace(base, updated);
  }

  Future<ChatDataSnapshot> deleteSessionRecord(
    ChatDataSnapshot base,
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.deleteSession(sessionId);
    return removeSession(base, sessionId);
  }

  Future<ChatDataSnapshot> deleteWorkspaceRecord(
    ChatDataSnapshot base,
    SessionRepository repo,
    String workspaceId,
  ) async {
    await repo.deleteWorkspace(workspaceId);
    return snapshotWithoutWorkspace(base, workspaceId);
  }

  Future<({String workspaceId, ChatDataSnapshot snapshot})>
  createWorkspaceWithFirstSession(
    ChatDataSnapshot base,
    List<WorkspaceFolder> folders,
    SessionRepository repo, {
    String sessionTeamId = '',
    List<TeamMemberConfig> rosterMembers = const [],
    Map<String, CliTool> memberClis = const {},
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
    String display = '',
    bool allowDuplicate = false,
    LaunchProfileRepository? identityRepository,
  }) async {
    final workspace = await repo.createWorkspace(
      folders,
      display: display,
    );
    final trimmedTeam = sessionTeamId.trim();
    final resolvedClis = trimmedTeam.isEmpty
        ? const <String, CliTool>{}
        : memberClis.isNotEmpty
        ? memberClis
        : team != null
        ? resolveSessionMemberCliLocks(
            team: team,
            rosterMembers: rosterMembers,
            globalPresets: globalPresets,
          )
        : throw ArgumentError(
            'Team session create requires memberClis or team',
          );
    var snapshot = snapshotWithWorkspace(base, workspace);
    final created = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: sessionTeamId,
      rosterMembers: rosterMembers,
      memberClis: resolvedClis,
    );
    snapshot = appendSession(snapshot, created.session);
    snapshot = snapshotWithWorkspace(snapshot, created.workspace);
    return (workspaceId: workspace.workspaceId, snapshot: snapshot);
  }

  Future<({Workspace workspace, ChatDataSnapshot snapshot})> cloneWorkspace(
    ChatDataSnapshot base,
    SessionRepository repo,
    String sourceWorkspaceId, {
    String? display,
    List<TeamMemberConfig> rosterMembers = const [],
  }) async {
    final result = await repo.cloneWorkspace(
      sourceWorkspaceId,
      display: display,
      rosterMembers: rosterMembers,
    );
    return (
      workspace: result.workspace,
      snapshot: snapshotWithWorkspaceAndSessions(
        base,
        workspace: result.workspace,
        sessions: result.sessions,
      ),
    );
  }
```

注:`createWorkspaceWithFirstSession` 中 `created.workspace` 可能是 knownWorkspace 复用(带旧 sessionIds);先 `appendSession` 再 `snapshotWithWorkspace`(后者保留 appendSession 已写入的 sessionIds)。`deleteWorkspaceRecord` 内 `repo.deleteWorkspace` 内部循环 `deleteSession`(Task 3 会在此加 index 维护,当前任务不涉及)。

- [ ] **Step 4: 适配 ChatCubit 调用点**

`client/lib/cubits/chat_cubit.dart`:

```dart
  // createWorkspaceWithFirstSession(1556-1569) 改为传 base:
  final base = ChatDataSnapshot(
    workspaces: state.workspaces,
    sessions: state.sessions,
    visibleWorkspaces: state.visibleWorkspaces,
    visibleSessions: state.visibleSessions,
  );
  final result = await _dataStore.createWorkspaceWithFirstSession(
    base,
    folders,
    repo,
    ...原参数...,
  );
  _emitSnapshot(result.snapshot);
  return result.workspaceId;
```

```dart
  // addWorkspaceDirectory(1572-1583):
  final base = ChatDataSnapshot(
    workspaces: state.workspaces,
    sessions: state.sessions,
    visibleWorkspaces: state.visibleWorkspaces,
    visibleSessions: state.visibleSessions,
  );
  final snap = await _dataStore.addWorkspaceDirectory(
    base,
    repo,
    workspace,
    folder,
  );
  if (snap != null) _emitSnapshot(snap);
```

```dart
  // updateWorkspaceMetadata(1585-1601):
  final snap = await _dataStore.updateWorkspaceMetadata(
    ChatDataSnapshot(
      workspaces: state.workspaces,
      sessions: state.sessions,
      visibleWorkspaces: state.visibleWorkspaces,
      visibleSessions: state.visibleSessions,
    ),
    repo,
    workspaceId,
    display: display,
    defaultProfileId: defaultProfileId,
    rootSandboxEnvOptIn: rootSandboxEnvOptIn,
  );
  if (snap != null) _emitSnapshot(snap);
```

```dart
  // applyWorkspaceIcon(1603-1609) 与 importCustomWorkspaceIcon(1611-1623) 同模式:
  //   第一个参数传 ChatDataSnapshot(workspaces/sessions/visible* 四元组),
  //   结果 if (snap != null) _emitSnapshot(snap);
```

```dart
  // deleteSession(2197):_emitSnapshot(await _dataStore.deleteSessionRecord(
  //   ChatDataSnapshot(workspaces/sessions/visible* 四元组), repo, sessionId));

  // deleteWorkspace(2241):同模式传四元组 base。

  // cloneWorkspace(2213-2220):
  final result = await _dataStore.cloneWorkspace(
    ChatDataSnapshot(
      workspaces: state.workspaces,
      sessions: state.sessions,
      visibleWorkspaces: state.visibleWorkspaces,
      visibleSessions: state.visibleSessions,
    ),
    repo,
    sourceWorkspaceId,
    display: display,
    rosterMembers: rosterMembers,
  );
  _emitSnapshot(result.snapshot);
  return result.workspace;
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test --no-pub test/cubits/chat/session_data_store_test.dart test/cubits/chat_cubit_test.dart`
Expected: PASS。若有断言旧行为的测试失败(如断言 `loadWorkspaceData` 被调用),按新语义修正断言(见 Task 8 清单,若本任务内发现也一并改)。

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/chat/session_data_store.dart client/lib/cubits/chat_cubit.dart client/test/cubits/chat/session_data_store_test.dart
git commit -m "refactor: mutation 后增量 patch 快照,不再全量重扫"
```

---

### Task 3: SessionRepository index 增量维护 + 快照顺序统一

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Test: `client/test/repositories/session_repository_test.dart`

**Interfaces:**
- Consumes: `WorkspaceIndexStore`(workspace_index_store.dart,已有 `upsert`/`remove`);`_workspacesIndexByRoot` 静态缓存。
- Produces: 私有辅助 `_rememberWorkspace(Workspace)` / `_forgetWorkspace(String workspaceId)`,供 mutation 方法内部调用;`loadWorkspacesIndex` 重建路径的 sessionIds 变为 createdAt 序。

- [ ] **Step 1: 写失败的测试**

在 `client/test/repositories/session_repository_test.dart` 追加(先确认该文件测试基建——`setUpTestAppStorage` 或临时目录;参考文件内已有测试的建 repo 方式;新增 import:`dart:convert`、`dart:io`、`package:teampilot/services/io/local_filesystem.dart`、`package:teampilot/services/storage/workspace_layout.dart`):

```dart
// 追加到文件末尾 main() 内
test('mutation keeps workspaces-index fresh for a fresh repository', () async {
  final tmp = await Directory.systemTemp.createTemp('repo_index_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);

  // 直接断言 index 文件内容(不依赖静态内存缓存):
  final layout = WorkspaceLayout(
    teampilotRoot: tmp.path,
    fs: LocalFilesystem(),
  );
  final raw = await File(layout.workspacesIndexFile).readAsString();
  final decoded = jsonDecode(raw) as Map<String, Object?>;
  final list = decoded['workspaces'] as List;
  expect(list, hasLength(1));
  final wsJson = list.single as Map<String, Object?>;
  expect(wsJson['sessionIds'], [created.session.sessionId]);

  // 全新实例走快路径也能读到(缓存键按 rootDir 隔离):
  final fresh = SessionRepository(rootDir: tmp.path);
  final index = await fresh.loadWorkspacesIndex();
  expect(index, hasLength(1));
  expect(index.single.sessionIds, [created.session.sessionId]);

  await repo.deleteSession(created.session.sessionId);
  final raw2 = await File(layout.workspacesIndexFile).readAsString();
  final decoded2 = jsonDecode(raw2) as Map<String, Object?>;
  expect(decoded2['workspaces'] as List, isEmpty);

  await repo.deleteWorkspace(ws.workspaceId);
  final fresh2 = SessionRepository(rootDir: tmp.path);
  expect(await fresh2.loadWorkspacesIndex(), isEmpty);
  await tmp.delete(recursive: true);
});
```

注:若 `loadWorkspacesIndex` 的静态缓存跨测试串扰(不同 rootDir 缓存键不同,不会串),如遇 flake 可加 `SessionRepository(rootDir: tmp.path)` 且 rootDir 唯一即可。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test --no-pub test/repositories/session_repository_test.dart`
Expected: FAIL — 全新 repo 的 `loadWorkspacesIndex` 为空/缺 sessionIds(因为 mutation 不写 index)。

- [ ] **Step 3: 实现 index 增量维护**

`client/lib/repositories/session_repository.dart`,在 `_rememberWorkspacesIndex`(54-62)之后追加:

```dart
  /// Incremental mirror of [Workspace] into the in-memory index cache and the
  /// workspaces-index.json snapshot. Mutations call this so the fast boot path
  /// (loadWorkspacesIndex) never returns a stale workspace.
  Future<void> _rememberWorkspace(Workspace workspace) async {
    final key = _workspacesIndexCacheKey();
    final current = _workspacesIndexByRoot[key];
    if (current != null) {
      _workspacesIndexByRoot[key] = List<Workspace>.unmodifiable([
        for (final existing in current)
          if (existing.workspaceId == workspace.workspaceId)
            _withInferredMemberPlacementInit(workspace)
          else
            existing,
      ]);
    }
    await WorkspaceIndexStore(await _fs()).upsert(workspace);
  }

  /// Incremental removal from the in-memory index cache and the index snapshot.
  Future<void> _forgetWorkspace(String workspaceId) async {
    final key = _workspacesIndexCacheKey();
    final current = _workspacesIndexByRoot[key];
    if (current != null) {
      _workspacesIndexByRoot[key] = List<Workspace>.unmodifiable(
        [for (final existing in current)
          if (existing.workspaceId != workspaceId) existing],
      );
    }
    await WorkspaceIndexStore(await _fs()).remove(workspaceId);
  }
```

接入 mutation(每处就在 `_writeManifest` 之后、`return` 之前加一行):

- `createWorkspace`(332 后):`await _rememberWorkspace(workspace);`
- `updateWorkspaceMetadata`(355 后):`await _rememberWorkspace(updated);`
- `applyWorkspaceIcon`(378 后):`await _rememberWorkspace(updated);`
- `importCustomWorkspaceIcon`(406 后):`await _rememberWorkspace(updated);`
- `updateWorkspaceFolders`(453 后):`await _rememberWorkspace(updated);`
- `updateWorkspaceMemberTargets` / `updateWorkspaceMemberPlacement`(531 后):`await _rememberWorkspace(updated);`
- `createSession`(788 `return` 前):`await _rememberWorkspace(workspace);`
- `cloneWorkspace`(1135 `return` 前):`await _rememberWorkspace(newWorkspace);`
- `deleteSession`(1095 `}` 前,`_writeManifest` 之后):

```dart
      final key = _workspacesIndexCacheKey();
      final cached = _workspacesIndexByRoot[key]
          ?.where((w) => w.workspaceId == workspaceId)
          .firstOrNull;
      if (cached != null) {
        await _rememberWorkspace(
          cached.copyWith(
            sessionIds: [
              for (final id in cached.sessionIds)
                if (id != sessionId) id,
            ],
          ),
        );
      }
```

  (deleteSession 内已有局部变量 `workspaceId` 与 `sessionId`。若 `firstOrNull` 报错,改手写循环。)
- `deleteWorkspace`(1212 后):`await _forgetWorkspace(workspaceId);`

- [ ] **Step 4: 快照 sessionIds 顺序统一(createdAt 序)**

`loadWorkspacesIndex`(224 行)与 `_revalidateWorkspacesIndexSnapshot`(246 行)中两处 `_loadWorkspaces(indexOnly: true)` 改为 `_loadWorkspaces(indexOnly: false)`,使快照与全量路径 sessionIds 同为 createdAt 序。保留 `_readManifest(fs, workspaceId, indexOnly: true)`(createSession 热路径,672 行)不动。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && flutter test --no-pub test/repositories/session_repository_test.dart test/cubits/chat/session_data_store_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/session_repository_test.dart
git commit -m "feat: mutation 增量维护 workspaces-index 快照并统一 sessionIds 顺序"
```

---

### Task 4: touchSession / toggleSessionPin 返回更新后的 session

**Files:**
- Modify: `client/lib/repositories/session_repository.dart:948-969`
- Test: `client/test/repositories/session_repository_test.dart`

**Interfaces:**
- Produces:
  - `Future<AppSession?> SessionRepository.touchSession(String sessionId)`
  - `Future<AppSession?> SessionRepository.toggleSessionPin(String sessionId)`
  - 既有调用方忽略返回值,兼容。

- [ ] **Step 1: 写失败的测试**

在 `client/test/repositories/session_repository_test.dart` 追加:

```dart
test('touchSession returns the touched session', () async {
  final tmp = await Directory.systemTemp.createTemp('repo_touch_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  final touched = await repo.touchSession(created.session.sessionId);
  expect(touched, isNotNull);
  expect(touched!.sessionId, created.session.sessionId);
  expect(touched.updatedAt, greaterThanOrEqualTo(created.session.updatedAt));
  await tmp.delete(recursive: true);
});

test('toggleSessionPin flips pinned and returns the session', () async {
  final tmp = await Directory.systemTemp.createTemp('repo_pin_test_');
  final repo = SessionRepository(rootDir: tmp.path);
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  final toggled = await repo.toggleSessionPin(created.session.sessionId);
  expect(toggled!.pinned, isTrue);
  final untoggled = await repo.toggleSessionPin(created.session.sessionId);
  expect(untoggled!.pinned, isFalse);
  await tmp.delete(recursive: true);
});
```

注:测试里 createWorkspace 的返回要接住;上面第一个测试的 `'w'` 占位符必须换成 `ws.workspaceId`(照第二个测试的写法)。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test --no-pub test/repositories/session_repository_test.dart`
Expected: FAIL — `touchSession` 返回 `Future<void>`,赋值编译错误。

- [ ] **Step 3: 改写两个方法**

```dart
  Future<AppSession?> touchSession(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = existing.copyWith(updatedAt: now);
      await _writeSession(fs, updated);
      return updated;
    });
  }

  Future<AppSession?> toggleSessionPin(String sessionId) {
    return _withSessionFile(sessionId, () async {
      final fs = await _fs();
      final existing = await _findSession(fs, sessionId);
      if (existing == null) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = existing.copyWith(
        pinned: !existing.pinned,
        updatedAt: now,
      );
      await _writeSession(fs, updated);
      return updated;
    });
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test --no-pub test/repositories/session_repository_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/session_repository_test.dart
git commit -m "feat: touchSession/toggleSessionPin 返回更新后的 session"
```

---

### Task 5: ChatCubit touchSession/toggleSessionPin 增量 patch

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart:2028-2033, 2159-2164`
- Test: `client/test/cubits/chat_cubit_test.dart`

**Interfaces:**
- Consumes: Task 4 的返回类型;`replaceSessionSnapshot`(既有)。

- [ ] **Step 1: 写失败的测试**

在 `client/test/cubits/chat_cubit_test.dart` 追加(参考该文件既有测试的 cubit 构造方式——`ChatCubit(...)` 依赖注入 + 临时仓库;若该文件已有 toggleSessionPin 相关测试则扩展之):

```dart
test('touchSession patches the session in memory without rescan', () async {
  // 构造:临时 SessionRepository(rootDir: tmp),chatCubit 依赖注入(参考文件内已有 setup)
  final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
  final created = await repo.createSession(ws.workspaceId);
  await cubit.loadWorkspaceIndex(repo); // 快路径初始化
  await cubit.ensureSessionsForWorkspace(ws.workspaceId);

  await cubit.touchSession(created.session.sessionId);

  final session = cubit.state.sessions.singleWhere(
    (s) => s.sessionId == created.session.sessionId,
  );
  expect(session.updatedAt, greaterThan(created.session.updatedAt));
});
```

(测试细节以 chat_cubit_test.dart 既有模式为准;若构造过于复杂,至少验证 `touchSession` 后 state.sessions 仍含该 session 且 updatedAt 变大。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test --no-pub test/cubits/chat_cubit_test.dart`
Expected: FAIL — 测试断言不满足(updatedAt 未变)。

- [ ] **Step 3: 实现**

```dart
  Future<void> touchSession(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    final updated = await repo.touchSession(sessionId);
    if (updated != null) replaceSessionSnapshot(updated);
  }
```

```dart
  Future<void> toggleSessionPin(String sessionId) async {
    final repo = _sessionRepository;
    if (repo == null) return;
    final updated = await repo.toggleSessionPin(sessionId);
    if (updated != null) replaceSessionSnapshot(updated);
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test --no-pub test/cubits/chat_cubit_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/test/cubits/chat_cubit_test.dart
git commit -m "refactor: touchSession/toggleSessionPin 增量 patch 快照"
```

---

### Task 6: session_default_materializer 增量 patch

**Files:**
- Modify: `client/lib/services/launch/session_default_materializer.dart:85-96, 136-138`

**Interfaces:**
- Consumes: Task 1 的 `snapshotWithWorkspace` / `appendSession`;`SessionLaunchHost.dataStore` 与 `emitSnapshot`(既有接口,无签名变化)。
- Produces: 无新接口;materializer 不再调用 `_host.loadWorkspaceData`。

- [ ] **Step 1: 写失败的测试**

在 `client/test/services/launch/` 下没有 materializer 单测文件,新增 `client/test/services/launch/session_default_materializer_test.dart`(若现有 fake host 基建复杂,则此任务以编译 + 既有测试通过为准,测试步骤可改为运行相关既有测试):

```dart
// 新增文件:验证 materializePersonalSession 后 host snapshot 包含新 session
// 构造一个 _FakeHost implements SessionLaunchHost,记录 emitSnapshot 收到的快照;
// 复用 test/services/launch/session_launch_pipeline_stable_task_id_test.dart:444
// 的 _CapturingHost 结构(精简实现必需成员,其余 throw UnimplementedError)。
// 断言:emitSnapshot 被调用且快照 sessions 含新 session、workspace.sessionIds 含新 id,
// 且 loadWorkspaceData 未被调用(记录标志位)。
```

- [ ] **Step 2: 运行确认失败(或先实现)**

若新建 fake 成本高,可先实现后测,但**必须有回归验证**:`session_launch_pipeline_stable_task_id_test.dart` 通过 `_CapturingHost` 走 `SessionLaunchPipeline` 间接覆盖 materializer 路径(materializeTeamSession/materializePersonalSession 均在 pipeline 内被调用),该测试必须保持通过。

- [ ] **Step 3: 实现**

`materializeTeamSession`(85-96)改为:

```dart
    final created = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: team.id,
      rosterMembers: team.members,
      memberClis: resolveSessionMemberCliLocks(
        team: team,
        rosterMembers: team.members,
        globalPresets: _host.lifecycle.globalPresets,
      ),
    );
    session = created.session;
    if (_host.isClosed) return;
    _host.emitSnapshot(
      _host.dataStore.snapshotWithWorkspace(
        _host.stateSnapshot(),
        created.workspace,
      ),
    );
    _host.appendSessionSnapshot(session);
    if (_host.isClosed) return;
```

`materializePersonalSession`(136-138)改为:

```dart
    final created = await repo.createSession(workspace.workspaceId, cli: cli);
    if (_host.isClosed) return;
    _host.emitSnapshot(
      _host.dataStore.snapshotWithWorkspace(
        _host.stateSnapshot(),
        created.workspace,
      ),
    );
    _host.appendSessionSnapshot(created.session);
    if (_host.isClosed) return;
```

注:需要给 `SessionLaunchHost` 加一个便捷 getter `ChatDataSnapshot stateSnapshot()`(实现返回四元组,与 chat_cubit 内部构造一致),在 `session_launch_host.dart` 接口中声明、`chat_cubit.dart` 实现:

```dart
  // interface:
  ChatDataSnapshot stateSnapshot();

  // ChatCubit 实现:
  @override
  ChatDataSnapshot stateSnapshot() => ChatDataSnapshot(
        workspaces: state.workspaces,
        sessions: state.sessions,
        visibleWorkspaces: state.visibleWorkspaces,
        visibleSessions: state.visibleSessions,
      );
```

同时把 ChatCubit 中 Task 2 引入的四处内联四元组构造替换为 `stateSnapshot()`(减重复)。4 个测试 fake(`session_tab_surface_coordinator_test.dart:334`、`session_prompt_metadata_sync_test.dart:69`、`session_launch_pipeline_stable_task_id_test.dart:444`、`session_launch_host_agent_status_test.dart:133`)补 `stateSnapshot()` 实现(返回空快照 `ChatDataSnapshot(workspaces: const [], sessions: const [], visibleWorkspaces: const [], visibleSessions: const [])` 或照各自已有 `loadWorkspaceData` 实现风格)。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && flutter test --no-pub test/services/launch/`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/lib/services/launch/session_default_materializer.dart client/test/services/launch/session_default_materializer_test.dart
git commit -m "refactor: session default materializer 增量 patch 快照"
```

---

### Task 7: 页面调用点改增量(3 个文件)

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart:73-129`
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart:206-216`
- Modify: `client/lib/pages/chat_workbench.dart:218-227`
- Modify: `client/lib/cubits/chat_cubit.dart`(新增 `patchWorkspaceAndSessions`)
- Test: `client/test/pages/` 相关 widget 测试若存在则更新;否则以 analyze + 既有测试为准

**Interfaces:**
- Consumes: Task 1 的 `snapshotWithWorkspaceAndSessions`;`chat.patchWorkspace`(Task 1 已升级)。
- Produces: `void ChatCubit.patchWorkspaceAndSessions(Workspace workspace, List<AppSession> sessions)`。

- [ ] **Step 1: 新增 ChatCubit.patchWorkspaceAndSessions**

`client/lib/cubits/chat_cubit.dart`,紧跟 `patchWorkspace` 之后:

```dart
  /// Replaces [workspace] and its sessions from a targeted mutation (e.g.
  /// remapWorkspaceTarget) in memory; no disk rescan.
  void patchWorkspaceAndSessions(
    Workspace workspace,
    List<AppSession> sessions,
  ) {
    _emitSnapshot(
      _dataStore.snapshotWithWorkspaceAndSessions(
        ChatDataSnapshot(
          workspaces: state.workspaces,
          sessions: state.sessions,
          visibleWorkspaces: state.visibleWorkspaces,
          visibleSessions: state.visibleSessions,
        ),
        workspace: workspace,
        sessions: sessions,
      ),
    );
  }
```

- [ ] **Step 2: 改 workspace_folders_section._persist(81-85)**

```dart
      final updated = await repo.updateWorkspaceFolders(
        widget.workspace.workspaceId,
        valid,
      );
      if (updated != null) {
        chat.invalidateWorkspaceProvision(updated);
        chat.patchWorkspace(updated);
      }
      _invalidateDeadTargetCache();
```

(删除 `await chat.loadWorkspaceData(repo);`。)

- [ ] **Step 3: 改 workspace_folders_section._remapDeadTarget(111-119)**

```dart
      final updated = await repo.remapWorkspaceTarget(
        widget.workspace.workspaceId,
        fromTargetId: fromTargetId,
        toTargetId: to,
        liveness: liveness,
      );
      chat.invalidateWorkspaceProvision(updated.workspace);
      chat.patchWorkspaceAndSessions(updated.workspace, updated.sessions);
      _invalidateDeadTargetCache();
```

(删除 `await chat.loadWorkspaceData(repo);`。)

- [ ] **Step 4: 改 mixed_workspace_member_placement_panel(206-214)**

同 Step 3 模式:`remapWorkspaceTarget` 结果存为 `updated`(不再只取 `.workspace`),`chat.invalidateWorkspaceProvision(updated.workspace)` + `chat.patchWorkspaceAndSessions(updated.workspace, updated.sessions)`,删除 `await chat.loadWorkspaceData(repo);`。

- [ ] **Step 5: 改 chat_workbench(218-226)**

同 Step 3 模式,删除 `await chat.loadWorkspaceData(repo);`。

- [ ] **Step 6: 验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --no-pub test/pages/chat/ test/pages/home_workspace/ 2>/dev/null || flutter test --no-pub test/pages/chat/`
Expected: 无 analyze 错误;相关测试通过。

- [ ] **Step 7: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart client/lib/pages/chat_workbench.dart
git commit -m "refactor: 页面 mutation 路径增量 patch 快照"
```

---

### Task 8: 全量验证与测试清理

**Files:**
- Modify: 视 analyze/test 结果修正断言的文件(主要是 `client/test/cubits/chat_cubit_test.dart` 等)

- [ ] **Step 1: 全量 analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 issues。若有,修复(多为未用 import / fake 缺方法)。

- [ ] **Step 2: 全量单元测试**

Run: `cd client && flutter test --exclude-tags integration`
Expected: 全绿。若有失败:
- 断言 mutation 后全量重扫的测试 → 改为断言增量结果(新 session 在 sessions 列表、sessionIds 更新);
- 断言 `loadWorkspaceData` 被调用的测试(fake 记录调用)→ 移除该断言或改为断言 patch 方法被调用;
- 不确定时回到对应任务文件核对语义。

- [ ] **Step 3: 性能抽查(手动,可选)**

在本地跑 app(debug),日志中创建 workspace 后不应再出现 `SessionDataStore.loadWorkspaceData`;首启 `loadWorkspaceIndex` 走快路径。若 `createSession` 触发的 `ensure-dir`(workspace 存在时)仍慢,属既有行为,不在本计划范围。

- [ ] **Step 4: Commit**

```bash
git add -u client/test
git commit -m "test: 适配增量快照语义的测试断言"
```

(若无测试改动则跳过此 commit。)
