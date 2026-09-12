# Session List Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 侧栏读 home 上的一份 `sessions-index.json`；打开一个 session 只再读那一个 `session.json`；工作区索引重建不再扫全部 `session.json`。

**Architecture:** 派生行索引与 `session.json` 同住 home（无手机缓存）。`SessionListIndexStore` 负责单工作区读写；`SessionRepository` 变异时增量更新，缺失/id 对不上才重建。`ChatCubit.ensureSessionsForWorkspace` 只灌列表行；`hydrateSessionDocument` 再灌完整文档；`requestOpenSession` 打开前必须 hydrate。

**Tech Stack:** Dart 3 / Flutter；现有 `Filesystem` + `HomeStorage`；测试 `flutter_test` + 包装 Filesystem 计数 `session.json` 读取。

**Spec:** `docs/superpowers/specs/2026-09-12-session-list-index-design.md`

## Global Constraints

- **绝不直接运行 `flutter test`** —— 一律 `cd client && dart run tool/run_tests.dart <paths>`。
- 内层循环：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件：`dart run tool/run_tests.dart test/<path> --plain-name <name>`。读摘要行，**不信 runner 退出码**（失败时仍可能为 0）。
- 日志用 `appLogger`，禁止 `print`。无新用户可见文案，不改 arb。
- 路径走 `HomeStorage` / `WorkspaceLayout`，禁止 `Directory.current`。
- `loadSessions()` / `loadSessionsForWorkspace()` **保持读完整文档**（clone、automation、既有测试）。Chat 列表与打开热路径改走 `loadSessionListForWorkspace` / `loadSession`。
- 不要把 `ChatCubit.ensureSession(TeamProfile)` 改名或复用；新方法叫 `hydrateSessionDocument`。
- 完整文档判定用 `_documentSessionIds`，禁止 `folders.isEmpty` 启发式。
- 文件大小软限：repositories / cubits 超限按职责拆文件，不要把 index store 塞进 `session_repository.dart`。
- 在 worktree `.worktrees/feat-session-list-index` 分支 `feat-session-list-index` 上实施。
- 跑全套若看到 `floating_workspace_panel_gestures_test.dart` / `overflow keeps +` —— 与本路线无关，不要修。

### 文件地图

| 文件 | 职责 |
|---|---|
| `client/lib/models/session_list_entry.dart` | 侧栏行字段；from/to JSON；fromSession；toListSession |
| `client/lib/repositories/session_list_index_store.dart` | 单工作区 `sessions-index.json` |
| `client/lib/services/storage/workspace_layout.dart` | `sessionsIndexFile` |
| `client/lib/repositories/session_repository.dart` | 列表加载、单文档、indexOnly 重建、变异写索引 |
| `client/lib/cubits/chat/session_data_store.dart` | 列表 hydrate vs 文档 hydrate |
| `client/lib/cubits/chat_cubit.dart` | `hydrateSessionDocument`；打开前 hydrate |
| `client/lib/pages/home_workspace/workspace/workspace_page.dart` | 深链不等整仓文档 |
| `docs/workspace-storage-layout.md` | 目录树补一行 |

---

### Task 1: SessionListEntry + SessionListIndexStore

**Files:**
- Create: `client/lib/models/session_list_entry.dart`
- Create: `client/lib/repositories/session_list_index_store.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart`（加 `sessionsIndexFile`）
- Test: `client/test/models/session_list_entry_test.dart`
- Test: `client/test/repositories/session_list_index_store_test.dart`

**Interfaces:**
- Consumes: `AppSession`, `SessionPurpose`, `SessionRepositoryFs`, `WorkspaceLayout`
- Produces:
  - `class SessionListEntry` 字段：`sessionId`, `display`, `purpose`, `workflowId`, `sessionTeam`, `createdAt`, `updatedAt`, `archived`, `pinned`, `sortOrder`
  - `factory SessionListEntry.fromJson(Map<String, Object?> json)`
  - `Map<String, Object?> toJson()`
  - `factory SessionListEntry.fromSession(AppSession session)`
  - `AppSession toListSession(String workspaceId)`（只填行字段，folders/members 默认空）
  - `class SessionListIndexStore`：`tryRead` / `writeAll` / `upsert` / `remove`
  - `static const indexVersion = 1`
  - `WorkspaceLayout.sessionsIndexFile(String workspaceId)` → `{workspaceDir}/sessions-index.json`

- [ ] **Step 1: 写失败测试（模型）**

```dart
// client/test/models/session_list_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_list_entry.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('fromSession keeps list fields and toListSession drops folders', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      display: 'Hello',
      sessionTeam: 't1',
      folders: [WorkspaceFolder(path: '/repo')],
      createdAt: 10,
      updatedAt: 20,
      archived: true,
      pinned: true,
      sortOrder: 3,
      purpose: SessionPurpose.teamGeneration,
      workflowId: 'wf',
    );
    final entry = SessionListEntry.fromSession(session);
    expect(entry.sessionId, 's1');
    expect(entry.display, 'Hello');
    expect(entry.sessionTeam, 't1');
    expect(entry.archived, isTrue);
    expect(entry.pinned, isTrue);
    expect(entry.sortOrder, 3);
    expect(entry.purpose, SessionPurpose.teamGeneration);
    expect(entry.workflowId, 'wf');
    final list = entry.toListSession('w1');
    expect(list.display, 'Hello');
    expect(list.folders, isEmpty);
    expect(list.members, isEmpty);
    expect(list.archived, isTrue);
  });

  test('round-trips json including unknown-purpose fail-closed to normal', () {
    final entry = SessionListEntry.fromJson({
      'sessionId': 's',
      'display': 'd',
      'purpose': 'not-a-purpose',
      'createdAt': 1,
    });
    expect(entry.purpose, SessionPurpose.normal);
    expect(SessionListEntry.fromJson(entry.toJson()).sessionId, 's');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/session_list_entry_test.dart`

Expected: FAIL — `session_list_entry.dart` 不存在。

- [ ] **Step 3: 最小实现模型 + layout 路径**

`SessionListEntry` 用 `SessionPurpose.decode`。`toListSession` 构造 `AppSession(sessionId:, workspaceId:, createdAt:, ...行字段)`。

`WorkspaceLayout` 增加：

```dart
String sessionsIndexFile(String workspaceId) =>
    _ctx.join(workspaceDir(workspaceId), 'sessions-index.json');
```

- [ ] **Step 4: 写失败测试（store）**

```dart
// client/test/repositories/session_list_index_store_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_list_entry.dart';
import 'package:teampilot/repositories/session_list_index_store.dart';
import 'package:teampilot/repositories/session_repository_fs.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('session_list_index_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SessionListIndexStore store() => SessionListIndexStore(
    SessionRepositoryFs(teampilotRoot: tmp.path, fs: LocalFilesystem()),
    'ws-1',
  );

  SessionListEntry entry(String id) => SessionListEntry(
    sessionId: id,
    display: id,
    createdAt: 1,
    updatedAt: 1,
  );

  test('tryRead returns null when missing and writeAll round-trips', () async {
    final s = store();
    expect(await s.tryRead(), isNull);
    await s.writeAll([entry('a'), entry('b')]);
    final read = await s.tryRead();
    expect(read!.map((e) => e.sessionId), ['a', 'b']);
  });

  test('upsert inserts then replaces by sessionId', () async {
    final s = store();
    await s.upsert(entry('a'));
    await s.upsert(SessionListEntry(sessionId: 'a', display: 'renamed', createdAt: 1));
    final read = await s.tryRead();
    expect(read, hasLength(1));
    expect(read!.single.display, 'renamed');
  });

  test('remove drops the id; unknown version is treated as missing', () async {
    final s = store();
    await s.writeAll([entry('a'), entry('b')]);
    await s.remove('a');
    expect((await s.tryRead())!.map((e) => e.sessionId), ['b']);
    final fs = SessionRepositoryFs(teampilotRoot: tmp.path, fs: LocalFilesystem());
    await File(fs.layout.sessionsIndexFile('ws-1')).writeAsString('{"version": 99, "sessions": []}');
    expect(await s.tryRead(), isNull);
  });
}
```

- [ ] **Step 5: 跑 store 测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/session_list_index_store_test.dart`

Expected: FAIL — store 不存在。

- [ ] **Step 6: 最小实现 store**

仿 `WorkspaceIndexStore`：`_mutationLocks` keyed by index 文件路径；payload `{version: 1, updatedAt, sessions}`；坏 JSON / version != 1 → `null`；`isStorageTransportFailure` rethrow。`upsert` 保序：已有 id 原地替换，新 id 追加。

- [ ] **Step 7: 跑两个测试文件确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/session_list_entry_test.dart test/repositories/session_list_index_store_test.dart`

Expected: 摘要全 PASS。

- [ ] **Step 8: Commit**

```bash
git add client/lib/models/session_list_entry.dart \
  client/lib/repositories/session_list_index_store.dart \
  client/lib/services/storage/workspace_layout.dart \
  client/test/models/session_list_entry_test.dart \
  client/test/repositories/session_list_index_store_test.dart
git commit -m "$(cat <<'EOF'
feat(session): add sessions-index store for sidebar rows

Keep list metadata in one home-side JSON so SSH clients do not
read every session.json to paint the sidebar.
EOF
)"
```

---

### Task 2: 仓库热路径 — 列表加载、单文档、indexOnly 重建、变异写索引

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/lib/repositories/session_repository_fs.dart`（仅当需要把 `_readSession` 路径留给仓库；不要改 `loadSessionsForWorkspace` 语义）
- Test: `client/test/repositories/session_repository_test.dart`（追加，不改既有断言语义）
- Test: `client/test/repositories/session_list_load_test.dart`（新建，带读计数）

**Interfaces:**
- Consumes: Task 1 的 `SessionListIndexStore` / `SessionListEntry`
- Produces:
  - `Future<List<AppSession>> loadSessionListForWorkspace(String workspaceId)`
  - `Future<AppSession?> loadSession(String workspaceId, String sessionId)`
  - `loadWorkspacesIndex` 缺失与 snapshot stale：`_loadWorkspaces(indexOnly: true)`
  - `_writeSession` 之后 upsert 行索引；`deleteSession` 之后 `remove`

**计数包装：** 测试里写一个薄委托，只记 `readString` 路径以 `/session.json` 或 `\session.json` 结尾的次数。`HomeStorage.forTesting(filesystem: counting, paths: AppPaths(tmp.path), home: tmp.path, cwd: tmp.path)`。

- [ ] **Step 1: 写失败测试**

`client/test/repositories/session_list_load_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

class _CountingFs implements Filesystem {
  _CountingFs(this._inner);
  final Filesystem _inner;
  int sessionJsonReads = 0;

  bool _isSessionJson(String path) {
    final n = path.replaceAll('\\', '/');
    return n.endsWith('/session.json');
  }

  @override
  p.Context get pathContext => _inner.pathContext;
  @override
  Future<String?> readString(String path) async {
    if (_isSessionJson(path)) sessionJsonReads++;
    return _inner.readString(path);
  }
  // 其余方法全部转发给 _inner（stat/listDir/atomicWrite/ensureDir/...）
}

HomeStorage _storage(Directory tmp, Filesystem fs) => HomeStorage.forTesting(
  filesystem: fs,
  paths: AppPaths(tmp.path),
  home: tmp.path,
  cwd: tmp.path,
);

Future<void> _plantSessions(Directory tmp, String workspaceId, int n) async {
  final root =
      '${tmp.path}/workspace/workspaces/$workspaceId/sessions';
  for (var i = 0; i < n; i++) {
    final dir = Directory('$root/seed-$i')..createSync(recursive: true);
    File('${dir.path}/session.json').writeAsStringSync(
      jsonEncode({
        'sessionId': 'seed-$i',
        'workspaceId': workspaceId,
        'display': 'Seed $i',
        'createdAt': i,
        'updatedAt': i,
        'folders': [
          {'path': '/tmp/ws', 'targetId': 'local'},
        ],
      }),
    );
  }
}

void main() {
  test('loadWorkspacesIndex rebuild does not read session.json', () async {
    final tmp = await Directory.systemTemp.createTemp('list_index_rebuild_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final inner = LocalFilesystem();
    final counting = _CountingFs(inner);
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
    await _plantSessions(tmp, ws.workspaceId, 40);
    File(WorkspaceLayout(teampilotRoot: tmp.path, fs: inner).workspacesIndexFile)
        .deleteSync();
    SessionRepository.clearWorkspacesIndexCacheForTest(); // 见 Step 3；若无此测试缝，新 Repo 实例即可（不同进程内缓存键）
    counting.sessionJsonReads = 0;
    final fresh = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final indexed = await fresh.loadWorkspacesIndex();
    expect(indexed, isNotEmpty);
    expect(counting.sessionJsonReads, 0);
  });

  test('loadSessionListForWorkspace hits sessions-index without reading session.json', () async {
    final tmp = await Directory.systemTemp.createTemp('list_index_hit_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final inner = LocalFilesystem();
    final counting = _CountingFs(inner);
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, counting),
    );
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
    final created = (await repo.createSession(ws.workspaceId)).session;
    await _plantSessions(tmp, ws.workspaceId, 40);
    // 目录比索引多 → 第一次 list 会重建；再清计数测命中
    await repo.loadSessionListForWorkspace(ws.workspaceId);
    counting.sessionJsonReads = 0;
    final listed = await repo.loadSessionListForWorkspace(ws.workspaceId);
    expect(counting.sessionJsonReads, 0);
    expect(listed.map((s) => s.sessionId), contains(created.sessionId));
    expect(
      listed.firstWhere((s) => s.sessionId == created.sessionId).folders,
      isEmpty,
    );
    final full = await repo.loadSession(ws.workspaceId, created.sessionId);
    expect(full!.folders, isNotEmpty);
  });

  test('createSession and deleteSession keep sessions-index in lockstep', () async {
    final tmp = await Directory.systemTemp.createTemp('list_index_mutate_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(
      rootDir: tmp.path,
      storage: _storage(tmp, LocalFilesystem()),
    );
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/tmp/ws')]);
    final created = (await repo.createSession(ws.workspaceId)).session;
    final listed = await repo.loadSessionListForWorkspace(ws.workspaceId);
    expect(listed.single.sessionId, created.sessionId);
    await repo.deleteSession(created.sessionId);
    expect(await repo.loadSessionListForWorkspace(ws.workspaceId), isEmpty);
  });
}
```

测试文件必须把 `_CountingFs` 的 **全部** `Filesystem` 方法转发给 inner（打开 `filesystem.dart` 抄方法列表）。`p` import：`package:path/path.dart`。

若静态缓存让 `loadWorkspacesIndex` 命中内存：用 **新的** `SessionRepository` 实例（缓存键是 rootDir）。删掉 `workspaces-index.json` 后新实例应走重建。`createWorkspace` 会写索引——测试里 `File(...workspacesIndexFile).deleteSync()` 后再 `SessionRepository(...)`。`_plantSessions` 发生在 delete 之前，重建应 `listDir` 看到 40+1 个目录。

不要添加 `clearWorkspacesIndexCacheForTest` 生产测试缝，除非没有别的办法；优先新实例。缓存是 `static Map` keyed by rootDir，**同一 root 的新实例仍命中**。因此：

1. `createWorkspace` + plant；
2. 删 `workspaces-index.json`；
3. 必须清静态缓存。允许在 `SessionRepository` 加：

```dart
@visibleForTesting
static void debugResetWorkspacesIndexCache() => _workspacesIndexByRoot.clear();
```

测试在 load 前调用。这是为了测「无快照重建」，不是给生产用。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/session_list_load_test.dart`

Expected: FAIL — `loadSessionListForWorkspace` / `loadSession` 未定义，或重建仍读 session.json。

- [ ] **Step 3: 实现**

`session_repository.dart`：

- `debugResetWorkspacesIndexCache` 如上。
- `loadWorkspacesIndex` 的 `else` 分支与 `_revalidateWorkspacesIndexSnapshot` 里 `_loadWorkspaces(indexOnly: false)` 改为 `true`。
- `loadSession(workspaceId, sessionId)` → `_readSession`。
- `loadSessionListForWorkspace`：
  ```dart
  final fs = await _fs();
  final store = SessionListIndexStore(fs, workspaceId);
  final dirIds = (await fs.listSessionDirectoryIds(workspaceId)).toSet();
  final snapshot = await store.tryRead();
  final snapshotIds = {for (final e in snapshot ?? const []) e.sessionId};
  if (snapshot != null && setEquals(snapshotIds, dirIds)) {
    return [for (final e in snapshot) e.toListSession(workspaceId)];
  }
  final maps = await fs.listSessionJsonMapsForWorkspace(workspaceId);
  final sessions = <AppSession>[];
  for (final json in maps) {
    try { sessions.add(AppSession.fromJson(json)); } on Object { continue; }
  }
  await store.writeAll([for (final s in sessions) SessionListEntry.fromSession(s)]);
  return [for (final s in sessions) SessionListEntry.fromSession(s).toListSession(workspaceId)];
  ```
- `_writeSession` 末尾：`await SessionListIndexStore(fs, workspaceId).upsert(SessionListEntry.fromSession(session));`
- `deleteSession` 在删目录成功后：`await SessionListIndexStore(fs, workspaceId).remove(sessionId);`

`loadSessionsForWorkspace` **不要改**。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/repositories/session_list_load_test.dart test/repositories/session_repository_test.dart`

Expected: 摘要 PASS。若 `session_repository_test` 里依赖 `indexOnly: false` 的 createdAt 排序，改测试为「id 集合相等」或接受目录序——**不要**为了排序把 `indexOnly` 改回 false。

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/test/repositories/session_list_load_test.dart \
  client/test/repositories/session_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(session): load sidebar rows from sessions-index

Rebuild workspaces-index from directory names only, and keep the
per-workspace row snapshot in lockstep with session.json writes.
EOF
)"
```

---

### Task 3: ChatCubit 列表 hydrate vs 文档 hydrate

**Files:**
- Modify: `client/lib/cubits/chat/session_data_store.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/cubits/chat_cubit_test.dart`（追加 group）

**Interfaces:**
- Consumes: `loadSessionListForWorkspace`, `loadSession`
- Produces:
  - `SessionDataStore.sessionHasDocument(String sessionId)`
  - `SessionDataStore.markSessionDocument(String sessionId)`（create/loadWorkspaceData 已是完整文档的 id）
  - `mergeWorkspaceSessions`：已有文档的 id 保留 folders/members，只 overlay 行字段
  - `ChatCubit.hydrateSessionDocument(workspaceId, sessionId) → Future<AppSession?>`
  - `_hydrateWorkspaceSessions` 改调 `loadSessionListForWorkspace`（经 data store 新方法 `loadSessionListForWorkspace`）
  - `loadWorkspaceData` / `createSession` 路径把写入内存的 session id 标成 document

- [ ] **Step 1: 写失败测试**

在 `chat_cubit_test.dart` 追加（沿用该文件已有 `_registerTempCubitCleanup` / `testHomeStorage` / `PostFrameTestHarness`）：

```dart
  test('ensureSessionsForWorkspace loads list rows without folders', () async {
    final tmp = await Directory.systemTemp.createTemp('chat_list_hydrate_');
    final repo = SessionRepository(rootDir: tmp.path, storage: testHomeStorage);
    final postFrame = PostFrameTestHarness();
    final cubit = ChatCubit(
      executableResolver: () => 'true',
      automationRepository: testAutomationRepository(),
      storage: testHomeStorage,
      sessionRepository: repo,
      postFrameScheduler: postFrame.scheduler,
    );
    _registerTempCubitCleanup(tmp: tmp, cubit: cubit, postFrame: postFrame);

    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
    final created = (await repo.createSession(ws.workspaceId)).session;
    await cubit.loadWorkspaceIndex(repo);
    await cubit.ensureSessionsForWorkspace(ws.workspaceId);
    final row = cubit.state.sessions.singleWhere((s) => s.sessionId == created.sessionId);
    expect(row.display, created.display);
    expect(cubit.sessionHasDocument(created.sessionId), isFalse);

    final full = await cubit.hydrateSessionDocument(ws.workspaceId, created.sessionId);
    expect(full!.folders, isNotEmpty);
    expect(cubit.sessionHasDocument(created.sessionId), isTrue);
    expect(
      cubit.state.sessions.singleWhere((s) => s.sessionId == created.sessionId).folders,
      isNotEmpty,
    );

    await cubit.ensureSessionsForWorkspace(ws.workspaceId); // 第二次应 no-op
    expect(
      cubit.state.sessions.singleWhere((s) => s.sessionId == created.sessionId).folders,
      isNotEmpty,
    );
  });
```

`sessionHasDocument` 可以是 `ChatCubit` 上的 `@visibleForTesting` 转发。若 `ensureSessionsForWorkspace` 第二次因为已标记 loaded 直接 return，folders 保持即可。再加一条：手动清 hydration 标记后二次 list merge 仍保留 folders——若没有测试缝，用「先 hydrate 再在 data store 里未 loaded 时 merge」覆盖 `mergeWorkspaceSessions`。最小：hydrate 后 folders 非空即够；第二次 ensure 是 no-op 也符合 spec。

注意：`createSession` 经 cubit 时会标 document；本测试用 **repo.createSession + cubit.loadWorkspaceIndex + ensureSessions**，内存里应是列表行，`sessionHasDocument` 为 false。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart --plain-name "ensureSessionsForWorkspace loads list rows without folders"`

Expected: FAIL — `hydrateSessionDocument` 未定义，或 ensure 仍走完整 `loadSessionsForWorkspace`（folders 非空且被标成 document）。

- [ ] **Step 3: 实现**

`SessionDataStore`：

```dart
final Set<String> _documentSessionIds = {};

bool sessionHasDocument(String sessionId) =>
    _documentSessionIds.contains(sessionId.trim());

void markSessionDocument(String sessionId) {
  final id = sessionId.trim();
  if (id.isNotEmpty) _documentSessionIds.add(id);
}

Future<List<AppSession>> loadSessionListForWorkspace(...) async {
  final sessions = await repo.loadSessionListForWorkspace(workspaceId);
  appLogger.i('[boot] SessionDataStore.loadSessionListForWorkspace ...');
  return sessions;
}

AppSession _overlayListFields(AppSession document, AppSession row) =>
    document.copyWith(
      display: row.display,
      sessionTeam: row.sessionTeam,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      archived: row.archived,
      pinned: row.pinned,
      sortOrder: row.sortOrder,
      purpose: row.purpose,
      workflowId: row.workflowId,
    );
```

`mergeWorkspaceSessions`：对每个 owned list row，若 `_documentSessionIds` 含该 id 且 `current.sessions` 里有完整对象，则放入 `_overlayListFields(existing, row)`，否则放入 row。

`_resetSessionHydration` 时 **不要** 清 `_documentSessionIds`（index reload 会清空 sessions；若一并清空文档标记，打开过的 tab 会变行）。`loadWorkspaceIndex` 调 `_resetSessionHydration`——此时 sessions 被换成 `[]`，文档对象已不在内存。应当同时 `_documentSessionIds.clear()`，与 sessions 清空一致。`loadWorkspaceData` 加载的全是文档：`for (final s in sessions) markSessionDocument(s.sessionId)`。

Cubit `createSession` 成功后 `markSessionDocument`。

`_hydrateWorkspaceSessions` 改调 `loadSessionListForWorkspace`。

```dart
Future<AppSession?> hydrateSessionDocument(
  String workspaceId,
  String sessionId,
) async {
  final repo = _sessionRepository;
  final id = sessionId.trim();
  final ws = workspaceId.trim();
  if (repo == null || id.isEmpty || ws.isEmpty) return null;
  if (_dataStore.sessionHasDocument(id)) {
    return state.sessions.where((s) => s.sessionId == id).firstOrNull;
  }
  final full = await repo.loadSession(ws, id);
  if (full == null || isClosed) return null;
  _dataStore.markSessionDocument(id);
  _emitSnapshot(
    _dataStore.mergeLoadedSession(current: stateSnapshot(), session: full),
  );
  return full;
}
```

`mergeLoadedSession`：替换同 id，或 append；标 document。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart --plain-name "ensureSessionsForWorkspace loads list rows without folders"`

以及该文件里现有 `ensureSessionsForWorkspace` / `touchSession` 相关测试。

Expected: PASS。`touchSession` 测的是完整文档上的 patch；若 ensure 之后 touch，需先 hydrate 或走 repo 已有完整对象。若现有测试 `createSession` 经 cubit，仍是 document，不应坏。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/session_data_store.dart \
  client/lib/cubits/chat_cubit.dart \
  client/test/cubits/chat_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): hydrate session documents on demand

Sidebar list rows come from sessions-index; opening a session
loads that one session.json instead of the whole workspace.
EOF
)"
```

---

### Task 4: 打开路径与深链等完整文档

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`（`requestOpenSession`）
- Modify: `client/lib/pages/home_workspace/workspace/workspace_page.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`（`_sessionById`）
- Test: `client/test/cubits/chat_cubit_test.dart` 或现有 `open_existing_session_gate_test.dart` 能断言 hydrate 被调用即可

**Interfaces:**
- Consumes: `hydrateSessionDocument`, `SessionOpenRequest.withSession`
- Produces: 打开已有 session 时 `request.session` 一定是完整文档（有 folders）

- [ ] **Step 1: 写失败测试**

```dart
  test('requestOpenSession hydrates list row before launch', () async {
    // 同一套 tmp/repo/cubit 脚手架
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/p')]);
    final created = (await repo.createSession(ws.workspaceId)).session;
    await cubit.loadWorkspaceIndex(repo);
    await cubit.ensureSessionsForWorkspace(ws.workspaceId);
    final row = cubit.state.sessions.singleWhere((s) => s.sessionId == created.sessionId);
    expect(row.folders, isEmpty);

    final status = await cubit.requestOpenSession(
      SessionOpenRequest(
        session: row,
        workspace: cubit.state.workspaces.single,
        connectImmediately: false,
        repo: repo,
      ),
    );
    expect(status, isNot(SessionOpenStatus.blockedMixed));
    expect(cubit.sessionHasDocument(created.sessionId), isTrue);
    expect(
      cubit.state.sessions.singleWhere((s) => s.sessionId == created.sessionId).folders,
      isNotEmpty,
    );
  });
```

用 `connectImmediately: false` 避免真启 PTY。若 mixed 校验挡住，workspace folders 用 `WorkspaceFolder(path: '/p')` 与 create 一致。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart --plain-name "requestOpenSession hydrates list row before launch"`

Expected: FAIL — 打开后仍是 list row / `sessionHasDocument` false。

- [ ] **Step 3: 实现**

```dart
Future<SessionOpenStatus> requestOpenSession(SessionOpenRequest request) async {
  final session = request.session;
  final hydrated = await hydrateSessionDocument(
        session.workspaceId,
        session.sessionId,
      ) ??
      session;
  return _launchService.requestOpenSession(request.withSession(hydrated));
}
```

`workspace_page.dart` `_applySessionFromRoute`：

```dart
unawaited(
  context.read<ChatCubit>().ensureSessionsForWorkspace(widget.workspaceId),
);
await _restoreWorkbenchLayoutSnapshot();
final session = await context.read<ChatCubit>().hydrateSessionDocument(
      widget.workspaceId,
      sessionId,
    ) ??
    await _resolveSessionForDeepLink(sessionId);
```

`_resolveSessionForDeepLink` 的 fallback 改为 `repo.loadSession(workspaceId, sessionId)`，禁止 `loadSessionsForWorkspace`。

`_sessionById`：若 `fromState` 存在且 `chatCubit.sessionHasDocument(sessionId)` 则用它，否则 `repo.loadSession`。

把 `sessionHasDocument` 做成公开方法（测试和 `_sessionById` 都要用）。

- [ ] **Step 4: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat_cubit_test.dart --plain-name "requestOpenSession hydrates list row before launch"`

再跑：`test/pages/chat/open_existing_session_gate_test.dart`

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart \
  client/lib/pages/home_workspace/workspace/workspace_page.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/test/cubits/chat_cubit_test.dart
git commit -m "$(cat <<'EOF'
fix(chat): hydrate session.json before opening a tab

Deep links and sidebar opens wait on one document read instead of
the full workspace session list.
EOF
)"
```

---

### Task 5: 文档 + 分析

**Files:**
- Modify: `docs/workspace-storage-layout.md`
- Modify: `docs/superpowers/specs/2026-09-12-session-list-index-design.md`（状态保持已审阅）

- [ ] **Step 1: 工作区目录树增加**

在 `workspace/workspaces/{workspaceId}/` 下列出：

```
sessions-index.json            # derived sidebar snapshot (source remains session.json)
```

- [ ] **Step 2: analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit 0。

- [ ] **Step 3: 相关测试再跑一遍**

Run: `cd client && dart run tool/run_tests.dart test/models/session_list_entry_test.dart test/repositories/session_list_index_store_test.dart test/repositories/session_list_load_test.dart test/repositories/session_repository_test.dart test/cubits/chat_cubit_test.dart`

Expected: 摘要 PASS。

- [ ] **Step 4: Commit**

```bash
git add docs/workspace-storage-layout.md
git commit -m "$(cat <<'EOF'
docs: record per-workspace sessions-index.json

EOF
)"
```

---

## Spec coverage

| Spec | Task |
|---|---|
| sessions-index.json 格式与 layout 路径 | 1 |
| SessionListIndexStore | 1 |
| loadSessionList / loadSession / indexOnly:true / 变异 upsert | 2 |
| Chat 列表 vs 文档 / 不覆盖已 hydrate | 3 |
| 打开与深链不 await 整仓文档 | 4 |
| workspace-storage-layout | 5 |
| 不改 page-first / 不做手机缓存 / 不改 loadSessions 语义 | 全局约束 |
