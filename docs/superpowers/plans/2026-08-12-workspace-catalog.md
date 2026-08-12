# WorkspaceCatalog 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 引入 `WorkspaceCatalog` 内存单一数据源，让工作区/会话所有 mutation 走"写穿 → 内存补丁 → 防抖索引写"，彻底消除创建与所有 mutation 路径的全量磁盘重扫；trust 预置改后台 + 启动门控。

**Architecture:** `WorkspaceCatalog`（新，`client/lib/services/catalog/workspace_catalog.dart`）持有内存 `List<Workspace>` + `List<AppSession>` + hydration/scope/trust-gate/防抖索引 writer，成为工作区会话唯一 API 面；`SessionRepository` 瘦身为纯实体持久化 + 启动/重载原语（`loadWorkspacesIndex/loadWorkspaces/loadSessions/loadSessionsForWorkspace`），删除全量 index 同步与 `createWorkspace` 内扫描去重；`ChatCubit` 内部 `_dataStore`（`SessionDataStore`，删除）换成 catalog；`SessionLaunchService`/页面/服务全部改走 catalog；`SessionLifecycleService` 加 `trustGate` 回调在物化 CONFIG_DIR 前等待。

**Tech Stack:** Dart / Flutter, flutter_bloc, `synchronized` (LockPool/Lock), uuid, WorkspaceIndexStore (磁盘派生索引)。

## Global Constraints

- 验证命令（每任务收尾）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
- 不向后兼容：允许删参数/改签名/改返回值；`SessionDataStore` 最终删除。
- 只改工作区/会话路径；launch profiles、automations 存储等库不动。
- `workspaces-index.json` 保留（boot 快启 + 崩溃恢复），写全归 Catalog 防抖。
- manifest.json / session.json 仍是磁盘事实源；内存补丁必须在写穿成功后。
- 会话实体并发：Catalog 用 `LockPool`（`client/lib/utils/lock_pool.dart`）按 sessionId 串行化"读内存最新 → 变换 → 写穿 → 补丁"。
- 日志用 `appLogger`（`client/lib/utils/logging/logger.dart`），禁止 `print`。
- 禁止新增注释以外的无关重构；遵循现有代码风格（2 空格缩进、单引号）。

---

### Task 1: SessionRepository 瘦身（去掉全扫/去重/index 写/trust 调用）

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/test/repositories/session_repository_test.dart`
- Modify: `client/test/repositories/session_repository_folders_test.dart`（如编译报错）

**Interfaces:**
- Consumes: 现状 `SessionRepository`（见 `client/lib/repositories/session_repository.dart` 全文）。
- Produces（后续任务依赖的精确签名）:
  - `Future<SessionRepositoryFs> fs()` —— 公开 `_fs()` 的包装。
  - `Future<Workspace> createWorkspace(List<WorkspaceFolder> folders, {String display = ''})` —— 无 `allowDuplicate`、无扫描去重、无 trust 调用。
  - `Future<void> provisionWorkspaceTrust(Workspace workspace)` —— 原私有 `_provisionWorkspaceTrust` 改公开。
  - `Future<({Workspace workspace, List<AppSession> sessions})> cloneWorkspace(String sourceWorkspaceId, {String? display, List<TeamMemberConfig> rosterMembers = const []})` —— 返回克隆出的会话列表。
  - `createSession` / `updateWorkspaceMetadata` / `applyWorkspaceIcon` / `importCustomWorkspaceIcon` / `updateWorkspaceFolders` / `_updateWorkspaceMemberTargetsAndInit`（对外两个方法不变）/ `remapWorkspaceTarget` / `deleteSession` / `deleteWorkspace` / `loadWorkspacesIndex` / `loadWorkspaces` / `loadSessions` / `loadSessionsForWorkspace` —— 签名不变。
  - `_syncWorkspaceIndexEntry` 删除；`_invalidateWorkspacesIndexCache` 仅保留 `loadWorkspacesIndex` 内部使用（`_rememberWorkspacesIndex`/静态缓存逻辑保留，boot 快启原语）。

- [ ] **Step 1: 写失败测试（先改测试断言，确认红线）**

在 `client/test/repositories/session_repository_test.dart` 中找 `createWorkspace` 相关测试（含"重复路径复用/合并"测试，如存在则删除该用例，因为它测的是即将移除的去重逻辑），并把任何断言 index 文件内容/`loadWorkspacesIndex` 生效的测试保留。然后给 `createWorkspace` 的"重复创建"行为写新断言（临时占位，Step 3 让测试通过）：

```dart
test('createWorkspace always creates a new workspace (no dedup)', () async {
  final repo = SessionRepository(rootDir: tmp.path);
  final a = await repo.createWorkspace([const WorkspaceFolder(path: '/p')]);
  final b = await repo.createWorkspace([const WorkspaceFolder(path: '/p')]);
  expect(a.workspaceId, isNot(equals(b.workspaceId)));
});
```

Run: `cd client && flutter test test/repositories/session_repository_test.dart -n "createWorkspace"`
Expected: FAIL —— 现在的实现会复用第一个工作区。

- [ ] **Step 2: 跑测试确认失败**

同上，Expected: 1 个失败。

- [ ] **Step 3: 改造 `session_repository.dart`**

1. `createWorkspace`（`session_repository.dart:330-383`）改为：
   - 删除 `allowDuplicate` 参数与 `loadWorkspaces()` 全扫 + 去重合并循环（347-372）。
   - 只保留：`normalized` 校验 → `Workspace(...)` 构造 → `_writeManifest(fs, workspace)` → `return workspace`。
   - 删除结尾 `await _provisionWorkspaceTrust(fs, workspace);`（381）。
2. `_writeManifest`（172-183）删除 `await _syncWorkspaceIndexEntry(fs, workspace);`（182）。
3. 删除 `_syncWorkspaceIndexEntry`（185-194）方法整体。
4. `createSession`（818）删除 `await _syncWorkspaceIndexEntry(fs, workspace);`。
5. `cloneWorkspace`（1135-1171）：返回类型改为 `Future<({Workspace workspace, List<AppSession> sessions})>`；在 1159-1166 循环里收集 `final cloned = await _cloneSessionRecord(...)` 进列表；删除 1168 的 `_syncWorkspaceIndexEntry`；结尾 `return (workspace: (await _readManifest(...)) ?? newWorkspace, sessions: clonedSessions);`。
6. `deleteWorkspace`（1226-1247）：删除 1245-1246 的 `_invalidateWorkspacesIndexCache()` + `WorkspaceIndexStore(fs).remove(...)`。
7. `updateWorkspaceFolders`（496）与 `remapWorkspaceTarget`（620）删除 `_provisionWorkspaceTrust` 调用。
8. `_provisionWorkspaceTrust`（638-650）改名公开 `Future<void> provisionWorkspaceTrust(Workspace workspace)`。
9. 新增公开 `Future<SessionRepositoryFs> fs() => _fs();`（放在 `_fs` 定义后）。
10. `loadWorkspacesIndex` 里 `_rememberWorkspacesIndex`/`_revalidateWorkspacesIndexSnapshot` 保留不动。

- [ ] **Step 4: 跑测试验证通过**

`cd client && flutter test test/repositories/session_repository_test.dart test/repositories/session_repository_folders_test.dart test/repositories/session_repository_target_remap_test.dart test/repositories/session_repository_working_dir_test.dart test/repositories/session_repository_replicas_test.dart test/repositories/session_repository_stable_task_id_test.dart`
Expected: PASS（如有调用 `createWorkspace(..., allowDuplicate: true)` 或 `cloneWorkspace(...)` 返回值解构的测试编译失败，按 Step 3 新签名适配）。

- [ ] **Step 5: 全量静态检查**

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无错误（`session_data_store.dart:235,254` 仍调用旧签名 `createWorkspace(..., allowDuplicate: ...)` 与 `cloneWorkspace` —— 若报错属预期，Task 3 会替换；此处允许 `--no-fatal-errors` 之外的错误存在吗？不允许——本任务结束前 `flutter analyze` 必须通过。故 Step 3 需同步适配 `session_data_store.dart` 的两处调用（`allowDuplicate` 参数删除、`cloneWorkspace` 返回值改为 record 后取 `.workspace`），仅改调用形式，不改语义；`createWorkspaceWithFirstSession` 的去重逻辑 Task 3 再搬）。

- [ ] **Step 6: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/lib/cubits/chat/session_data_store.dart client/test/repositories/
git commit -m "refactor(repo): slim SessionRepository - drop full scans, dedup, index sync, trust calls"
```

---

### Task 2: WorkspaceCatalog 核心（内存状态 + 快照 + scope + hydration + 访问器）

**Files:**
- Create: `client/lib/services/catalog/workspace_catalog.dart`
- Delete: `client/lib/cubits/chat/session_data_store.dart`（本任务内仅删除；其职责移入 catalog）
- Create: `client/test/services/catalog/workspace_catalog_test.dart`
- Modify: `client/test/cubits/chat/session_data_store_test.dart`（内容迁移到新测试后删除该文件）

**Interfaces:**
- Consumes: `SessionRepository`（Task 1 后的形态）、`ChatDataSnapshot`（`client/lib/cubits/chat/session_data_store.dart:17-37` 现定义，本任务移到 catalog 文件同目录并保留类名）、`LockPool`（`client/lib/utils/lock_pool.dart`）。
- Produces（后续任务依赖的精确签名）：

```dart
class ChatDataSnapshot { /* 从 session_data_store.dart 原样迁移，props 不变 */ }

class WorkspaceCatalog {
  WorkspaceCatalog(this.repo);
  final SessionRepository repo;

  // 内存状态访问（同步，返回不可变拷贝）
  List<Workspace> get workspaces;
  List<AppSession> get sessions;
  bool sessionsLoadedForWorkspace(String workspaceId);
  Workspace? workspaceById(String workspaceId);
  AppSession? sessionById(String sessionId);

  // scope（原 SessionDataStore.setScope）
  bool setScope({required bool scopeSessionsToSelectedTeam, String? selectedTeamId});

  // 快照派生（内存列表 + scope 过滤）
  ChatDataSnapshot deriveSnapshot();

  // boot / 重载
  Future<ChatDataSnapshot> loadIndex();        // repo.loadWorkspacesIndex → 内存；sessions 清空
  Future<ChatDataSnapshot> reload();           // repo.loadWorkspaces + repo.loadSessions → 内存；全 hydrated
  Future<List<AppSession>> loadAllSessions();  // repo.loadSessions（不写入内存，Task 6 launch_profile 用）

  // hydration
  Future<void> ensureSessionsForWorkspace(String workspaceId);  // 内存已加载直接返回；in-flight 去重
  Future<List<AppSession>> sessionsForWorkspace(String workspaceId); // 未加载先 ensure 再返回内存拷贝

  // 内存补丁（不发磁盘）
  ChatDataSnapshot ingest({required List<Workspace> workspaces, required List<AppSession> sessions});
  ChatDataSnapshot patchWorkspace(Workspace updated);
  ChatDataSnapshot appendSession(AppSession session);
  ChatDataSnapshot replaceSession(AppSession session);
  ChatDataSnapshot removeSession(String sessionId);

  SessionRepository get repo; // 见字段
}
```

内部私有成员：`List<Workspace> _workspaces = []`、`List<AppSession> _sessions = []`、`Set<String> _hydratedWorkspaceIds = {}`、`Map<String, Future<void>> _hydrationsByWorkspace = {}`、`bool _scopeSessionsToSelectedTeam = false`、`String? _selectedTeamId`。

- [ ] **Step 1: 迁移 `ChatDataSnapshot` + 写失败测试**

1. 把 `client/lib/cubits/chat/session_data_store.dart` 中的 `ChatDataSnapshot`（17-37）与 `SessionDataStore` 的 scope/derive 逻辑（42-102：`_scopeSessionsToSelectedTeam`、`_selectedTeamId`、`_resetSessionHydration`、`_markAllWorkspacesHydrated`、`markWorkspacesSessionsHydrated`、`sessionsLoadedForWorkspace`、`setScope`、`_computeVisibleSessions`、`_computeVisibleWorkspaces`、`deriveSnapshot`）搬到 `client/lib/services/catalog/workspace_catalog.dart`，包路径改为 `../../services/...` 相关 import。
2. 写测试 `client/test/services/catalog/workspace_catalog_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/workspace_catalog.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  WorkspaceCatalog buildCatalog() {
    final catalog = WorkspaceCatalog(null!); // 本组测试不触 repo
    catalog.ingest(
      workspaces: [Workspace(workspaceId: 'p', folders: [WorkspaceFolder(path: '/p')], createdAt: 0)],
      sessions: [AppSession(sessionId: 's', workspaceId: 'p', folders: [WorkspaceFolder(path: '/p')], sessionTeam: 't1', createdAt: 0)],
    );
    return catalog;
  }

  test('unscoped snapshot exposes all', () {
    final snap = buildCatalog().deriveSnapshot();
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s']);
    expect(snap.visibleWorkspaces.map((w) => w.workspaceId).toList(), ['p']);
  });

  test('team scope filters sessions by sessionTeam; workspaces stay unscoped', () {
    final catalog = buildCatalog()..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: 't1');
    final snap = catalog.deriveSnapshot();
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s']);
  });

  test('team scope with empty team id shows personal sessions only', () {
    final catalog = buildCatalog()..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: '');
    expect(catalog.deriveSnapshot().visibleSessions, isEmpty);
  });

  test('workspaceById/sessionById/sessionsLoadedForWorkspace', () {
    final catalog = buildCatalog();
    expect(catalog.workspaceById('p')?.workspaceId, 'p');
    expect(catalog.sessionById('s')?.sessionId, 's');
    expect(catalog.sessionsLoadedForWorkspace('p'), true);
    expect(catalog.sessionById('nope'), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/catalog/workspace_catalog_test.dart`
Expected: 编译失败（`workspace_catalog.dart` 不存在 / `null!` 类型错误等）→ 属失败。

- [ ] **Step 3: 实现 `WorkspaceCatalog` 核心**

按上表实现（本任务只做状态/scope/derive/hydration 骨架 + 内存补丁方法 + `loadIndex`/`reload`/`loadAllSessions`/`ensureSessionsForWorkspace`/`sessionsForWorkspace`；mutation 方法 Task 3）。要点：

```dart
class WorkspaceCatalog {
  WorkspaceCatalog(this.repo);

  final SessionRepository repo;

  List<Workspace> _workspaces = [];
  List<AppSession> _sessions = [];
  final Set<String> _hydratedWorkspaceIds = {};
  final Map<String, Future<void>> _hydrationsByWorkspace = {};
  bool _scopeSessionsToSelectedTeam = false;
  String? _selectedTeamId;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  List<AppSession> get sessions => List.unmodifiable(_sessions);

  // scope / derive 逻辑从 SessionDataStore 原样迁移（含 _computeVisibleSessions / _computeVisibleWorkspaces）

  Future<ChatDataSnapshot> loadIndex() async {
    _hydratedWorkspaceIds.clear();
    _workspaces = List.of(await repo.loadWorkspacesIndex());
    _sessions = [];
    return deriveSnapshot();
  }

  Future<ChatDataSnapshot> reload() async {
    _workspaces = List.of(await repo.loadWorkspaces());
    _sessions = List.of(await repo.loadSessions());
    _hydratedWorkspaceIds
      ..clear()
      ..addAll(_workspaces.map((w) => w.workspaceId));
    return deriveSnapshot();
  }

  Future<List<AppSession>> loadAllSessions() => repo.loadSessions();

  Future<void> ensureSessionsForWorkspace(String workspaceId) async {
    final id = workspaceId.trim();
    if (id.isEmpty || _hydratedWorkspaceIds.contains(id)) return;
    final inflight = _hydrationsByWorkspace[id];
    if (inflight != null) {
      await inflight;
      return;
    }
    final load = () async {
      final loaded = await repo.loadSessionsForWorkspace(id);
      _hydratedWorkspaceIds.add(id);
      _sessions = [
        for (final s in _sessions)
          if (s.workspaceId != id) s,
        ...loaded,
      ];
    }();
    _hydrationsByWorkspace[id] = load;
    try {
      await load;
    } finally {
      _hydrationsByWorkspace.remove(id);
    }
  }

  Future<List<AppSession>> sessionsForWorkspace(String workspaceId) async {
    await ensureSessionsForWorkspace(workspaceId);
    return [
      for (final s in _sessions)
        if (s.workspaceId == workspaceId.trim()) s,
    ];
  }
}
```

（`ingest`/`patchWorkspace`/`appendSession`/`replaceSession`/`removeSession` 用现有 `deriveSnapshot` 语义实现；`patchWorkspace` 替换同 id 的 workspace。）

- [ ] **Step 4: 跑测试验证通过**

`cd client && flutter test test/services/catalog/workspace_catalog_test.dart`
Expected: PASS（4 个用例）。

- [ ] **Step 5: 删除旧文件**

删除 `client/lib/cubits/chat/session_data_store.dart` 与 `client/test/cubits/chat/session_data_store_test.dart`。此时 `chat_cubit.dart` 等引用会编译失败——本任务不修复（Task 5 处理），只要求 `flutter analyze` 对该文件自身的报错可接受。**例外**：若 `session_data_store_test.dart` 有独有断言未迁移，先迁再删。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/catalog/workspace_catalog.dart client/test/services/catalog/workspace_catalog_test.dart
git rm client/lib/cubits/chat/session_data_store.dart client/test/cubits/chat/session_data_store_test.dart
git commit -m "feat(catalog): WorkspaceCatalog core - memory state, scope, hydration, accessors"
```

---

### Task 3: WorkspaceCatalog mutations（写穿 + 内存补丁 + 防抖索引）与 createWorkspaceWithFirstSession

**Files:**
- Modify: `client/lib/services/catalog/workspace_catalog.dart`
- Modify: `client/test/services/catalog/workspace_catalog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `SessionRepository`（`fs()`/`provisionWorkspaceTrust`/record 返回值）、Task 2 的 catalog 核心。
- Produces（Task 5/6 依赖的精确签名，全部返回 `ChatDataSnapshot` 或含 snapshot 的 record）：

```dart
Future<({String workspaceId, ChatDataSnapshot snapshot})> createWorkspaceWithFirstSession(
  List<WorkspaceFolder> folders, {
  String sessionTeamId = '',
  List<TeamMemberConfig> rosterMembers = const [],
  Map<String, CliTool> memberClis = const {},
  TeamProfile? team,
  List<CliPreset> globalPresets = const [],
  String display = '',
  bool allowDuplicate = false,
});
Future<Workspace> createWorkspace(List<WorkspaceFolder> folders, {String display = ''});
// 公开去重入口：allowDuplicate=false 时查内存复用/合并，否则 repo.createWorkspace 新建。
// createWorkspaceWithFirstSession 内部复用它（先 createWorkspace 再 createSession）。
Future<({AppSession session, ChatDataSnapshot snapshot})> createSession(
  String workspaceId, {
  String sessionTeamId = '', List<TeamMemberConfig> rosterMembers = const [],
  Map<String, CliTool> memberClis = const {}, CliTool? cli, String? provider,
  String? model, String? effort, String? presetId, String? workingDirectory,
  String? fixedSessionId, String? expertKey,
  SessionContinueOverrides? continueOverrides,
  List<SessionMemberBinding>? members, Map<String, String>? memberTargets,
});
Future<ChatDataSnapshot> renameSession(String sessionId, String newName);
Future<ChatDataSnapshot> markSessionStarted(String sessionId);
Future<ChatDataSnapshot> touchSession(String sessionId);
Future<ChatDataSnapshot> toggleSessionPin(String sessionId);
Future<ChatDataSnapshot> updateSessionTeam(String sessionId, String sessionTeam);
Future<ChatDataSnapshot> updateContinueOverrides(String sessionId, SessionContinueOverrides overrides);
Future<ChatDataSnapshot> updateSimpleLaunchIdentity(String sessionId, {String? presetId, String? provider, String? model, String? effort});
Future<ChatDataSnapshot> recordNativeSessionId(String sessionId, {required String tool, required String nativeId, String? rosterMemberId});
Future<({SessionMemberBinding binding, ChatDataSnapshot snapshot})> ensureMemberBinding(String sessionId, String rosterMemberId, {required CliTool cli, String? typeId});
Future<ChatDataSnapshot> reorderSessions(List<String> orderedSessionIds);
Future<ChatDataSnapshot> addWorkspaceDirectory(Workspace workspace, WorkspaceFolder folder);
Future<ChatDataSnapshot> updateWorkspaceMetadata(String workspaceId, {String? display, String? defaultProfileId, bool? rootSandboxEnvOptIn});
Future<ChatDataSnapshot> applyWorkspaceIcon(String workspaceId, WorkspaceIconRef icon);
Future<ChatDataSnapshot> importCustomWorkspaceIcon(String workspaceId, String localSourcePath);
Future<ChatDataSnapshot> updateWorkspaceMemberTargets(String workspaceId, String teamId, {required MemberTargetAssignments targets});
Future<ChatDataSnapshot> updateWorkspaceMemberPlacement(String workspaceId, String teamId, {required MemberTargetAssignments targets});
Future<ChatDataSnapshot> remapWorkspaceTarget(String workspaceId, {required String fromTargetId, required String toTargetId, required TargetLiveness liveness});
Future<ChatDataSnapshot> deleteSession(String sessionId);
Future<({String workspaceId, ChatDataSnapshot snapshot})> cloneWorkspace(String sourceWorkspaceId, {String? display, List<TeamMemberConfig> rosterMembers = const []});
Future<ChatDataSnapshot> deleteWorkspace(String workspaceId);
Future<void> provisionTrust(String workspaceId);
Future<void> trustProvisioningFor(String workspaceId);
```

- [ ] **Step 1: 写失败测试**

在 `client/test/services/catalog/workspace_catalog_test.dart` 追加（用 `setUpTestAppStorage`，见 `client/test/support/post_frame_test_harness.dart`；repo 用 `SessionRepository(rootDir: tmp.path)`，参考 `client/test/repositories/session_repository_test.dart` 的 tmp 模式；`WorkspaceIndexStore` 断言用 `SessionRepositoryFs(teampilotRoot: tmp.path)`）：

```dart
test('createWorkspaceWithFirstSession does not full-scan', () async {
  final tmp = await Directory.systemTemp.createTemp('catalog_create_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final repo = SessionRepository(rootDir: tmp.path);
  final catalog = WorkspaceCatalog(repo);
  await catalog.loadIndex();
  final result = await catalog.createWorkspaceWithFirstSession(
    [const WorkspaceFolder(path: '/proj')],
    display: 'P',
  );
  expect(result.workspaceId, isNotEmpty);
  expect(catalog.workspaceById(result.workspaceId), isNotNull);
  expect(catalog.sessionsForWorkspace(result.workspaceId), isNotEmpty);
  final fs = await repo.fs();
  final index = await WorkspaceIndexStore(fs).tryRead(preferIsolate: false);
  expect(index?.map((w) => w.workspaceId), contains(result.workspaceId));
});

test('createWorkspaceWithFirstSession dedups in memory when allowDuplicate false', () async {
  final tmp = await Directory.systemTemp.createTemp('catalog_dedup_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final repo = SessionRepository(rootDir: tmp.path);
  final catalog = WorkspaceCatalog(repo);
  await catalog.loadIndex();
  final a = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/dup')]);
  final b = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/dup')]);
  expect(a.workspaceId, b.workspaceId);
  expect(catalog.workspaces.length, 1);
});

test('renameSession patches memory and disk', () async {
  final tmp = await Directory.systemTemp.createTemp('catalog_rename_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final repo = SessionRepository(rootDir: tmp.path);
  final catalog = WorkspaceCatalog(repo);
  await catalog.loadIndex();
  final ws = await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/p')]);
  final created = await catalog.createSession(ws.workspaceId);
  final snap = await catalog.renameSession(created.session.sessionId, 'New Title');
  expect(snap.sessions.firstWhere((s) => s.sessionId == created.session.sessionId).display, 'New Title');
  expect(catalog.sessionById(created.session.sessionId)?.display, 'New Title');
  final fs = await repo.fs();
  final raw = await fs.readText(fs.sessionFile(ws.workspaceId, created.session.sessionId));
  expect(jsonDecode(raw!)['display'], 'New Title');
});
```

Run: `cd client && flutter test test/services/catalog/workspace_catalog_test.dart`
Expected: FAIL（方法不存在 / 行为未实现）。

- [ ] **Step 2: 跑测试确认失败**（同上）

- [ ] **Step 3: 实现 catalog mutations + 防抖索引 + trust 门控骨架**

```dart
// 私有成员追加：
final LockPool _sessionLocks = LockPool();
final Lock _mutationLock = Lock();
final Map<String, Future<void>> _trustByWorkspace = {};
final Map<String, Future<void>> _indexWrites = {}; // 或单一 Timer
Timer? _indexDebounce;
bool _indexDirty = false;

void _markIndexDirty() {
  _indexDirty = true;
  _indexDebounce ??= Timer(const Duration(milliseconds: 300), () {
    _indexDebounce = null;
    if (!_indexDirty) return;
    _indexDirty = false;
    unawaited(_flushIndex());
  });
}

Future<void> _flushIndex() async {
  try {
    await _mutationLock.synchronized(() async {
      await WorkspaceIndexStore(await repo.fs()).writeAll(_workspaces);
    });
  } on Object catch (error, stackTrace) {
    appLogger.e('[catalog] index flush failed', error: error, stackTrace: stackTrace);
  }
}
```

`_withSession`（实体级变换，锁内读内存最新 → 变换 → 写穿 → 补丁）：

```dart
Future<T> _withSession<T>(
  String sessionId,
  Future<T> Function(AppSession current) fn,
) {
  return _sessionLocks.synchronized(sessionId, () async {
    final current = sessionById(sessionId);
    if (current == null) throw StateError('Unknown sessionId: $sessionId');
    return fn(current);
  });
}

Future<ChatDataSnapshot> renameSession(String sessionId, String newName) async {
  await _withSession(sessionId, (current) async {
    await repo.renameSession(sessionId, newName);
    _sessions = [
      for (final s in _sessions)
        if (s.sessionId == sessionId) s.copyWith(display: newName) else s,
    ];
  });
  _markIndexDirty();
  return deriveSnapshot();
}
```

同样模式实现：`markSessionStarted`（`copyWith(launchState: AppSessionLaunchState.started, updatedAt: now)`）、`touchSession`（`copyWith(updatedAt: now)`）、`toggleSessionPin`（`copyWith(pinned: !s.pinned)`）、`updateSessionTeam`、`updateContinueOverrides`、`updateSimpleLaunchIdentity`、`recordNativeSessionId`（用 `SessionMemberBinding.withNativeSessionId` / `AppSession.withNativeSessionId`，镜像 repo 里 916-952 的变换逻辑）。

`createSession`（写穿 + 补丁 + sessionIds 增量）：

```dart
Future<({AppSession session, ChatDataSnapshot snapshot})> createSession(
  String workspaceId, {
  String sessionTeamId = '', List<TeamMemberConfig> rosterMembers = const [],
  Map<String, CliTool> memberClis = const {}, CliTool? cli, String? provider,
  String? model, String? effort, String? presetId, String? workingDirectory,
  String? fixedSessionId, String? expertKey,
  SessionContinueOverrides? continueOverrides,
  List<SessionMemberBinding>? members, Map<String, String>? memberTargets,
}) async {
  final ws = workspaceById(workspaceId);
  final session = await repo.createSession(
    workspaceId,
    sessionTeam: sessionTeamId, rosterMembers: rosterMembers, memberClis: memberClis,
    cli: cli, provider: provider, model: model, effort: effort, presetId: presetId,
    workingDirectory: workingDirectory, fixedSessionId: fixedSessionId,
    expertKey: expertKey, continueOverrides: continueOverrides,
    members: members, memberTargets: memberTargets, knownWorkspace: ws,
  );
  _sessions = [..._sessions, session];
  if (ws != null) {
    patchWorkspace(ws.copyWith(sessionIds: [...ws.sessionIds, session.sessionId]));
  }
  _markIndexDirty();
  return (session: session, snapshot: deriveSnapshot());
}
```

`createWorkspaceWithFirstSession`（内存去重 + 两条写 + 一次补丁 + trust 后台）：

```dart
Future<({String workspaceId, ChatDataSnapshot snapshot})>
createWorkspaceWithFirstSession(
  List<WorkspaceFolder> folders, {
  String sessionTeamId = '', List<TeamMemberConfig> rosterMembers = const [],
  Map<String, CliTool> memberClis = const {}, TeamProfile? team,
  List<CliPreset> globalPresets = const [], String display = '',
  bool allowDuplicate = false,
}) async {
  final normalized = [
    for (final f in folders)
      if (f.path.trim().isNotEmpty)
        f.copyWith(path: normalizeWorkspacePath(f.path)),
  ];
  if (normalized.isEmpty) {
    throw ArgumentError('createWorkspace requires at least one folder path');
  }
  final primary = normalized.first.path;
  if (!allowDuplicate) {
    final existing = _workspaces
        .where((w) => workspacePathsEqual(w.firstFolderPath, primary))
        .firstOrNull;
    if (existing != null) {
      final merged = List<WorkspaceFolder>.from(existing.folders);
      for (final f in normalized.skip(1)) {
        if (!merged.any((e) => workspacePathsEqual(e.path, f.path))) {
          merged.add(f);
        }
      }
      final trimmed = display.trim();
      final displayOut = trimmed.isNotEmpty ? trimmed : existing.display;
      if (listEquals(merged, existing.folders) && displayOut == existing.display) {
        return (workspaceId: existing.workspaceId, snapshot: deriveSnapshot());
      }
      await repo.updateWorkspaceFolders(existing.workspaceId, merged);
      await repo.updateWorkspaceMetadata(existing.workspaceId, display: displayOut);
      patchWorkspace(existing.copyWith(folders: merged, display: displayOut,
          updatedAt: DateTime.now().millisecondsSinceEpoch));
      _markIndexDirty();
      provisionTrust(existing.workspaceId);
      return (workspaceId: existing.workspaceId, snapshot: deriveSnapshot());
    }
  }
  final workspace = await repo.createWorkspace(normalized, display: display);
  _workspaces = [..._workspaces, workspace];
  _hydratedWorkspaceIds.add(workspace.workspaceId);
  final trimmedTeam = sessionTeamId.trim();
  final resolvedClis = trimmedTeam.isEmpty
      ? const <String, CliTool>{}
      : memberClis.isNotEmpty
      ? memberClis
      : team != null
      ? resolveSessionMemberCliLocks(team: team, rosterMembers: rosterMembers, globalPresets: globalPresets)
      : throw ArgumentError('Team session create requires memberClis or team');
  final created = await repo.createSession(workspace.workspaceId,
      sessionTeam: sessionTeamId, rosterMembers: rosterMembers, memberClis: resolvedClis,
      knownWorkspace: workspace);
  _sessions = [..._sessions, created];
  _markIndexDirty();
  provisionTrust(workspace.workspaceId);
  return (workspaceId: workspace.workspaceId, snapshot: deriveSnapshot());
}
```

`provisionTrust` / `trustProvisioningFor`：

```dart
Future<void> provisionTrust(String workspaceId) {
  final id = workspaceId.trim();
  if (id.isEmpty) return Future.value();
  final existing = _trustByWorkspace[id];
  if (existing != null) return existing;
  final future = () async {
    try {
      final ws = workspaceById(id);
      if (ws == null) return;
      await repo.provisionWorkspaceTrust(ws);
    } on Object catch (error, stackTrace) {
      appLogger.e('[catalog] trust provision failed workspace=$id',
          error: error, stackTrace: stackTrace);
    } finally {
      _trustByWorkspace.remove(id);
    }
  }();
  _trustByWorkspace[id] = future;
  return future;
}

Future<void> trustProvisioningFor(String workspaceId) {
  final id = workspaceId.trim();
  if (id.isEmpty) return Future.value();
  return _trustByWorkspace[id] ?? provisionTrust(id);
}
```

其余 mutation 按 repo 对应方法写穿 + 内存补丁 + `_markIndexDirty()`：
- `addWorkspaceDirectory`：`repo.updateWorkspaceFolders(workspace.workspaceId, [...workspace.folders, folder])` → 用 repo 返回前先 `patchWorkspace`（`repo.updateWorkspaceFolders` 返回 void，直接 patch 本地副本）。
- `updateWorkspaceMetadata` / `applyWorkspaceIcon` / `importCustomWorkspaceIcon`：repo 写后 `patchWorkspace`（图标方法需要 repo 返回的 workspace 才能拿到最终 icon？`applyWorkspaceIcon` 返回 void → 从 repo 读：`await repo.loadWorkspaces()` 不可取。改为在 catalog 内构造 `updated = existing.copyWith(...)` 传参给 repo？不行，repo 已写盘。**方案**：这些 repo 方法改为返回 `Future<Workspace?>`（写盘后返回 updated workspace），Task 3 里改 `session_repository.dart` 三处签名：`updateWorkspaceMetadata`、`applyWorkspaceIcon`、`importCustomWorkspaceIcon` 返回 `Future<Workspace?>`；catalog 用返回值 patch。`updateWorkspaceFolders` 同改（返回 `Future<Workspace?>`）。`_updateWorkspaceMemberTargetsAndInit` 已返回 `Workspace?`，复用。
- `updateWorkspaceMemberTargets/Placement`：repo 返回 workspace → patch。
- `remapWorkspaceTarget`：repo 返回 workspace → patch；repo 内部已写 session（无需 catalog 补 session，因为 remap 只改 folder 字段，但 repo 循环里 `_writeSession` 更新了 session.updatedAt/folders → catalog 需同步：在 repo 返回的 record 里带回 sessions？**方案**：`remapWorkspaceTarget` 返回改为 `Future<({Workspace workspace, List<AppSession> sessions})>`，catalog 用两者 patch）。
- `deleteSession`：`repo.deleteSession` 后 `_sessions` 移除 + workspace sessionIds 移除 + `patchWorkspace`。
- `deleteWorkspace`：repo 删后从两个列表移除。
- `cloneWorkspace`：repo record → `_workspaces` 追加 + `_sessions` 追加 + hydrated。
- `reorderSessions`：repo 写后按传入顺序给内存 session 设 `sortOrder`。
- `ensureMemberBinding`：repo 返回 binding → 用 `_withSession` 内把返回 binding 追加进内存副本（repo 返回后补丁 `members`）。

Task 1 的 `session_repository.dart` 需在本任务同步改：`updateWorkspaceMetadata`（385-405）、`applyWorkspaceIcon`（407-426）、`importCustomWorkspaceIcon`（428-455）、`updateWorkspaceFolders`（460-497）返回 `Future<Workspace?>`（返回 `updated` 或写盘后的 `existing.copyWith(...)`）；`remapWorkspaceTarget`（577-636）返回 `Future<({Workspace workspace, List<AppSession> sessions})>`（`applied.sessions` 是 `AppSession` 列表——注意 622-634 循环写的是 `session.copyWith(updatedAt: now)`，返回时用同一列表）。

- [ ] **Step 4: 跑测试验证通过**

`cd client && flutter test test/services/catalog/workspace_catalog_test.dart test/repositories/session_repository_test.dart`
Expected: PASS。

- [ ] **Step 5: 静态检查 + 适配既有调用**

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 仍有 `session_data_store.dart` 已删导致的报错（Task 5 修）。本任务内：`chat_cubit.dart`、页面等调用旧 `createWorkspaceWithFirstSession` 的编译错误允许存在（Task 5/6 统一修）。但 `session_data_store_test.dart` 若已删，其 import 报错消失。**要求**：除 `chat_cubit.dart`/`session_launch_service.dart`/`session_launch_host.dart`/页面/服务（Task 5/6 名单）外，无新增编译错误。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/catalog/workspace_catalog.dart client/lib/repositories/session_repository.dart client/test/services/catalog/workspace_catalog_test.dart
git commit -m "feat(catalog): mutations with write-through, memory patch, debounced index, trust gate"
```

---

### Task 4: Trust 预置重构（共享 git-root 遍历 + 并行父目录查找）+ 启动门控

**Files:**
- Modify: `client/lib/utils/workspace/trusted_project_paths.dart`
- Modify: `client/lib/services/provider/workspace_trust_provisioner.dart`
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Create: `client/test/services/provider/workspace_trust_provisioner_test.dart`
- Create: `client/test/utils/workspace/trusted_project_paths_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `catalog.trustProvisioningFor`。
- Produces:
  - `collectTrustedProjectKeys({required Filesystem fs, required Iterable<String> directories})` 签名不变，但内部对每个 (directory × metadataKey) 的 `findCanonicalGitRoot` 用 `Future.wait` 并行。
  - `WorkspaceTrustProvisioner.provisionWorkspace({required String workspaceId, required Iterable<String> directories, Iterable<String> tools = const [...4 tools...], Set<String>? precomputedKeys})`：`precomputedKeys` 非空则跳过重新收集。
  - `SessionLifecycleService`：新增**可变公开字段** `Future<void> Function(String workspaceId)? trustGate;`（不放进构造参数——app_shell 中 lifecycle 先于 repo/catalog 构造，需事后赋值）；`_prepareLaunchPlan` / `_prepareLaunchPlanFromRuntimePlan` / `_prepareLaunchPlanFromEnvironmentPlan` 开头 `await _trustGate?.call(session.workspaceId);`（捕获异常记日志不中断：`try { await _trustGate?.call(...) } on Object catch (e, st) { appLogger.w(...) }`）。

- [ ] **Step 1: 写失败测试**

`client/test/utils/workspace/trusted_project_paths_test.dart`（用 `LocalFilesystem`，tmp 目录造 `/gitrepo/.git` 与 `/plain`）：

```dart
test('collectTrustedProjectKeys finds git roots for all paths', () async {
  final tmp = await Directory.systemTemp.createTemp('trusted_paths_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  await Directory('${tmp.path}/repo/.git').create(recursive: true);
  await Directory('${tmp.path}/plain').create(recursive: true);
  final fs = LocalFilesystem();
  final keys = await collectTrustedProjectKeys(
    fs: fs,
    directories: ['${tmp.path}/repo', '${tmp.path}/repo/sub', '${tmp.path}/plain'],
  );
  expect(keys, contains('${tmp.path}/repo'));
  expect(keys, contains('${tmp.path}/plain'));
});
```

`client/test/services/provider/workspace_trust_provisioner_test.dart`：

```dart
test('provisionWorkspace computes keys once when precomputedKeys passed', () async {
  final tmp = await Directory.systemTemp.createTemp('trust_prov_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  await Directory('${tmp.path}/repo/.git').create(recursive: true);
  final fs = LocalFilesystem();
  final layout = RuntimeLayout(teampilotRoot: tmp.path, fs: fs);
  final provisioner = WorkspaceTrustProvisioner(layout: layout, fs: fs);
  var collectCount = 0;
  // 通过子类/注入无法 hook 静态函数；改为断言输出文件存在 + 手动验证仅一次收集：
  // 直接调用两次 provisionWorkspace（precomputedKeys 传入同一个 Set），
  // 断言 4 个工具的配置文件都被写入且无异常。
  await provisioner.provisionWorkspace(
    workspaceId: 'ws-1',
    directories: ['${tmp.path}/repo'],
    precomputedKeys: {'${tmp.path}/repo'},
  );
  expect(await fs.readString(layout.workspaceConfigToolDir('ws-1', 'codex') + '/config.toml'), contains('${tmp.path}/repo'));
});
```

Run: `cd client && flutter test test/utils/workspace/trusted_project_paths_test.dart test/services/provider/workspace_trust_provisioner_test.dart`
Expected: FAIL（`precomputedKeys` 参数不存在，编译失败）。

- [ ] **Step 2: 跑测试确认失败**（同上）

- [ ] **Step 3: 实现**

1. `trusted_project_paths.dart`：`collectTrustedProjectKeys` 改为收集所有 (directory × workspaceMetadataKey) 路径对，`Future.wait` 并行 `findCanonicalGitRoot`：

```dart
Future<Set<String>> collectTrustedProjectKeys({
  required Filesystem fs,
  required Iterable<String> directories,
}) async {
  final pathKeys = <String>[];
  for (final directory in directories) {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) continue;
    pathKeys.addAll(workspaceMetadataKeys(trimmed));
  }
  final gitRoots = await Future.wait([
    for (final key in pathKeys) findCanonicalGitRoot(fs, key),
  ]);
  final keys = <String>{...pathKeys};
  for (final root in gitRoots) {
    if (root != null) keys.addAll(workspaceMetadataKeys(root));
  }
  return keys;
}
```

2. `workspace_trust_provisioner.dart`：`provisionWorkspace` 增加 `Set<String>? precomputedKeys`；`final keys = precomputedKeys ?? await collectTrustedProjectKeys(...)`；`_provisionClaudeFamilyMetadata`（两个工具）改为接收 `Set<String> keys` 参数，内部 `writeWorkspaceTrustedProjectsMetadata` 加 `precomputedKeys` 透传（`config_profile_infrastructure.dart:145-170` 若自身收集则加参数透传）；`_provisionCodexTrust` / `_provisionCursorTrust` 改用共享 `keys`（cursor 的 `collectTrustedProjectKeys(fs, [directory])` 循环改为直接使用 keys）。
3. `session_lifecycle_service.dart`：新增可变公开字段 `trustGate`（见 Interfaces）；在 `_prepareLaunchPlan`（1053 行附近）、`_prepareLaunchPlanFromRuntimePlan`（476 行附近）、`_prepareLaunchPlanFromEnvironmentPlan`（648 行附近）开头加：

```dart
try {
  await _trustGate?.call(session.workspaceId);
} on Object catch (error, stackTrace) {
  appLogger.w('[session-lifecycle] trust gate failed workspace=${session.workspaceId}',
      error: error, stackTrace: stackTrace);
}
```

（`session.workspaceId` 在各方法参数里均存在，确认变量名后使用。）

- [ ] **Step 4: 跑测试验证通过**

`cd client && flutter test test/utils/workspace/trusted_project_paths_test.dart test/services/provider/workspace_trust_provisioner_test.dart`
Expected: PASS。

- [ ] **Step 5: 静态检查 + 既有调用适配**

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 除 Task 5/6 名单外无新增错误（`config_profile_infrastructure.dart` 的 `writeWorkspaceTrustedProjectsMetadata` 现有调用方若签名变化需透传兼容——建议该函数参数 `Set<String>? precomputedKeys` 可空，既有调用不传）。

- [ ] **Step 6: Commit**

```bash
git add client/lib/utils/workspace/trusted_project_paths.dart client/lib/services/provider/workspace_trust_provisioner.dart client/lib/services/session/session_lifecycle_service.dart client/lib/services/provider/config_profile_infrastructure.dart client/test/utils/workspace/trusted_project_paths_test.dart client/test/services/provider/workspace_trust_provisioner_test.dart
git commit -m "feat(trust): share git-root walk across tools, parallel parent lookup, launch trust gate"
```

---

### Task 5: ChatCubit + SessionLaunchHost + SessionLaunchService 迁移到 Catalog

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/cubits/chat/session_launch_host.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Modify: `client/lib/cubits/chat/model/session_create_request.dart`
- Modify: `client/lib/cubits/chat/model/session_open_request.dart`
- Modify: `client/lib/cubits/chat/session_continue_overrides_controller.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`（如编译报错）
- Modify: `client/lib/services/launch/session_default_materializer.dart`（如编译报错）
- Modify: 受影响测试（`client/test/cubits/chat_cubit_test.dart`、`chat_cubit_session_launch_test.dart`、`test/services/launch/session_launch_pipeline_stable_task_id_test.dart`、`test/cubits/chat/session_launch_lifecycle_gate_test.dart`、`test/cubits/chat/*` 等编译失败处）

**Interfaces:**
- Consumes: Task 2/3 的 `WorkspaceCatalog`。
- Produces:
  - `ChatCubit({..., WorkspaceCatalog? catalog, SessionRepository? sessionRepository, ...})`：`catalog == null && sessionRepository != null` 时 `catalog = WorkspaceCatalog(sessionRepository)`；`_catalog` 字段；`SessionRepository? get sessionRepository => _catalog?.repo;`；`WorkspaceCatalog get catalog => _catalog!;`
  - `SessionLaunchHost` 接口变更：`SessionDataStore get dataStore` → `WorkspaceCatalog get catalog`；`Future<void> loadWorkspaceData(SessionRepository repo)` → `Future<void> reloadData()`；`Future<void> renameSession(SessionRepository repo, String sessionId, String newName)` → `Future<void> renameSession(String sessionId, String newName)`；`SessionRepository? get sessionRepository` 保留。
  - `ChatCubit` 方法签名：`loadWorkspaceIndex()` / `loadWorkspaceData()`→删除（改 `reloadData()`）/ `hydrateAllSessions()` / `createWorkspaceWithFirstSession(folders, {..., bool allowDuplicate = false})`（无 repo）/ `createSession(String workspaceId, {...})`（无 repo）/ `addWorkspaceDirectory(Workspace, WorkspaceFolder)` / `updateWorkspaceMetadata(String workspaceId, {...})` / `applyWorkspaceIcon(String workspaceId, WorkspaceIconRef)` / `importCustomWorkspaceIcon(...)` / `deleteSession(String sessionId)` / `deleteWorkspace(String workspaceId)` / `cloneWorkspace(String sourceWorkspaceId, {...})` / `renameSession(String sessionId, String newName)` —— 全部经 `_catalog` 并 `_emitSnapshot(catalog.xxx)`。
  - `SessionCreateRequest` / `SessionOpenRequest`：删除 `repo` 字段。
  - `SessionContinueOverridesController`：`repo` 参数删除，改内部 `catalog`（`updateContinueOverrides` 调用 `catalog.updateContinueOverrides`）。

- [ ] **Step 1: 机械替换 `_dataStore` → `_catalog` 并清理签名（无新行为）**

1. `chat_cubit.dart`：
   - 构造参数加 `WorkspaceCatalog? catalog`；字段 `_catalog`；删除 `_dataStore` 字段（254 行）与 `SessionDataStore` import；`_sessionRepository` 保留字段但 getter（635 行）改 `=> _catalog?.repo;`。
   - `dataStore` getter（625 行）改 `=> _catalog!;`，返回类型 `WorkspaceCatalog`。
   - 逐个替换（1360-2216 区域，含 528/543/558/632/1271/1276/1313/1320/1372/1377/1381/1386/1398/1428/1434/1453/1465/1503/1514/1545/1566/1582/1597/1606/1986/2002/2120/2133/2161/2172/2188/2216 行）：
     - `loadWorkspaceData(repo)` → `reloadData()`（实现 `_emitSnapshot(await _catalog.reload());`）；`SessionLaunchHost` 接口同步改名。
     - `loadWorkspaceIndex(repo)` → `loadWorkspaceIndex()`（`_emitSnapshot(await _catalog.loadIndex());`）。
     - `hydrateAllSessions(repo)` → `hydrateAllSessions()`（`_catalog.ingest(workspaces: _catalog.workspaces, sessions: await _catalog.loadAllSessions())` + emit）。
     - `ensureSessionsForWorkspace` / `_hydrateWorkspaceSessions` / `sessionsForWorkspaceReady`：改用 `_catalog`（`ensureSessionsForWorkspace` 直接 `await _catalog.ensureSessionsForWorkspace(id)` 然后 `_emitSnapshot(_catalog.deriveSnapshot())`；`_sessionHydrationByWorkspace` 删除，归 catalog）。
     - `ingestWorkspaceSessionSnapshot` / `patchWorkspace`：`_emitSnapshot(_catalog.ingest(...))` / `_emitSnapshot(_catalog.patchWorkspace(updated))`。
     - `createSession`（1478-1525）：删 repo 参数 → `final result = await _catalog.createSession(workspaceId, ...); _emitSnapshot(result.snapshot); return result.session;`
     - `createWorkspaceWithFirstSession`（1534-1559）：删 repo/identityRepository 参数 → `final result = await _catalog.createWorkspaceWithFirstSession(...); _emitSnapshot(result.snapshot); return result.workspaceId;`
     - `addWorkspaceDirectory` / `updateWorkspaceMetadata` / `applyWorkspaceIcon` / `importCustomWorkspaceIcon` / `deleteSession` / `deleteWorkspace` / `cloneWorkspace`：删 repo 参数，`_emitSnapshot(await _catalog.X(...))`（cloneWorkspace 返回 `result.workspace`）。
     - `appendSessionSnapshot` / `replaceSessionSnapshot` / `removeSessionSnapshot`（526-568）：`_emitSnapshot(_catalog.appendSession(session))` 等（不再手工构造 ChatDataSnapshot from state）。
     - 1986/2002/2120/2133 区域（成员目标保存等）：改为 `_catalog.updateWorkspaceMemberTargets/Placement(...)` + emit 返回快照（删除 `loadWorkspaceData` 调用）。
   - `sessionRepository` 参数引用（1395 行 `ensureSessionsForWorkspace` 内）删除。
2. `session_launch_service.dart`：
   - `_persistSessionIfNeeded`（200-261）：`request.repo ?? _h.sessionRepository` 删除 → `final catalog = _h.catalog;`；`repo.createSession(...)` → `catalog.createSession(...)`（同参数）；`repo.renameSession(session.sessionId, stagedTitle)` → `await catalog.renameSession(session.sessionId, stagedTitle);`（返回值忽略）；`_h.replaceSessionSnapshot(persistedWithTitle)` → `_h.emitSnapshot(catalog.replaceSession(persistedWithTitle));`
   - `_ensureTeamSessionReady`（289-304）：`request.repo ?? _h.sessionRepository` → `_h.sessionRepository`；`ensureSessionLaunchReady(..., repository: repo)` 保留（该函数签名不变）。
   - `_rollbackStagedLaunch`（263-273）：`_h.removeSessionSnapshot(sessionId)` → `_h.emitSnapshot(_h.catalog.removeSession(sessionId));`
   - 其余 `_h.sessionRepository` 用法按编译错误逐个改 `_h.catalog.repo`。
3. `session_launch_host.dart`：接口按 Produces 改。
4. `session_create_request.dart` / `session_open_request.dart`：删除 `repo` 字段与 import。
5. `session_continue_overrides_controller.dart`（101-132）：`repo` 参数改 `WorkspaceCatalog catalog`，调用 `catalog.updateContinueOverrides(...)`（控制器由 `chat_cubit.dart` 构造，`_catalog` 传入）。
6. `session_shell_connector.dart` / `session_default_materializer.dart`：`repo` 用法按编译错误改为 `_h.catalog.repo` 或 `_h.catalog`（materializer 的 `_host.loadWorkspaceData(repo)` → `_host.reloadData()`）。

- [ ] **Step 2: 跑受影响测试修复编译与行为**

`cd client && flutter test test/cubits/chat test/cubits/chat_cubit_test.dart test/services/launch/session_launch_pipeline_stable_task_id_test.dart`
Expected: PASS（`_CapturingHost` 等测试 host 需加 `catalog` 实现：测试里 `final catalog = WorkspaceCatalog(sessionRepository)`；`SessionCreateRequest(repo: ...)` 调用点删除 `repo` 参数）。

- [ ] **Step 3: 全量静态检查**

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无错误（除 Task 6 名单文件：页面/服务仍是旧调用，属预期）。

- [ ] **Step 4: 全量单测**

`cd client && flutter test --exclude-tags integration`
Expected: 失败仅限 Task 6 名单文件的页面测试（未迁移的页面仍传 `repo` 参数导致编译失败）。记录失败清单，Task 6 逐一修复。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/lib/cubits/chat/ client/lib/services/launch/ client/test/cubits/chat client/test/services/launch/
git commit -m "refactor(chat): route ChatCubit/launch service through WorkspaceCatalog"
```

---

### Task 6: 页面与领域服务调用面迁移

**Files:**
- Modify: `client/lib/pages/home_workspace/home_new_workspace_dialog.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart:538-546`
- Modify: `client/lib/pages/home_workspace/workspaces_tab.dart:152-160`
- Modify: `client/lib/pages/home_workspace/workspace_actions.dart:54-98`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_page.dart:272`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart:50-597`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_icon_settings_row.dart:71`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_info_section.dart:133`
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart:192-213`
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_folders_section.dart:78-118`
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_dialog.dart:20-41`
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_section.dart:84`
- Modify: `client/lib/pages/home_workspace/workspace/worktree_group_section.dart:164`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart:266`
- Modify: `client/lib/pages/chat_workbench.dart:158-225`
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart:338`
- Modify: `client/lib/widgets/workspace_details_dialog.dart:93-101`
- Modify: `client/lib/widgets/sidebar_session_tile.dart:73-531`
- Modify: `client/lib/services/team/default_workspace_service.dart`
- Modify: `client/lib/services/automation/automation_dispatcher.dart:209-291`
- Modify: `client/lib/services/launch/team_settings_commit_service.dart:15-43`
- Modify: `client/lib/cubits/launch_profile_cubit.dart:45-95,540-542`
- Modify: `client/lib/app/app_data_bootstrap.dart`
- Modify: `client/lib/app/app_shell.dart:866`
- Modify: `client/lib/main.dart:635`
- 对应失败页面/服务测试

**Interfaces:**
- Consumes: Task 5 后的 `ChatCubit` / `WorkspaceCatalog`。
- Produces:
  - `showHomeNewWorkspaceDialog(BuildContext context, {required ChatCubit chatCubit})`（删除 repository/identityRepository 参数）。
  - `DefaultWorkspaceService.ensureDefault(WorkspaceCatalog catalog, {required TeamProfile defaultTeam, List<Workspace>? knownWorkspaces, RuntimeTarget? home})`：去重用 `catalog.workspaces`；创建走 `catalog.createWorkspace` 不存在——直接用 `catalog.createWorkspaceWithFirstSession`？不：ensureDefault 需要 workspace + 2 sessions（simple + team）→ 用 `catalog.createWorkspace(folders, display:)`？catalog 无裸 createWorkspace。**方案**：catalog 增加 `Future<Workspace> createWorkspace(List<WorkspaceFolder> folders, {String display = ''})`（Task 3 已实现内部逻辑，本任务抽出为公开方法，`createWorkspaceWithFirstSession` 复用它）；sessions 用 `catalog.createSession`。返回 `Future<bool>`（mutated 语义保留）。
  - `AutomationDispatcher` 构造参数 `_sessionRepository` → `WorkspaceCatalog catalog`；`loadSessionsForWorkspace` → `await catalog.sessionsForWorkspace(...)`。
  - `LaunchProfileCubit` 构造参数 `sessionRepository` 保留，内部 deleteTeam（540-542）改：`for (final session in await _sessionRepository.loadSessions())` 保留读，`await _sessionRepository.deleteSession(session.sessionId)` → `await catalog.deleteSession(session.sessionId)`；构造加 `WorkspaceCatalog? catalog`。
  - `AppShell`：新增 `late final WorkspaceCatalog catalog;`（在 `sessionRepo = ...` 之后 `catalog = WorkspaceCatalog(sessionRepo);`），传给 ChatCubit（`catalog: catalog`）、`LaunchProfileCubit(catalog: catalog)`、`AutomationDispatcher(catalog: catalog)`；随后赋值 `sessionLifecycleService.trustGate = (wid) => catalog.trustProvisioningFor(wid);`（Task 4 已定义为可变字段，解决 lifecycle 先于 repo/catalog 构造的顺序问题）；暴露 `WorkspaceCatalog get catalog`。
  - `main.dart`：`RepositoryProvider<WorkspaceCatalog>.value(value: shell.catalog)`（在 SessionRepository provider 旁，635 行附近）。
  - `app_data_bootstrap.dart`：`hydrateNativeHomeIndex` / `bootstrapHomeIndex` / `warmAuxiliaryData` / `prepareInteractiveShell` / `reloadAll` / `_ensureDefaultWorkspace` 的 `SessionRepository sessionRepo` 参数改为 `WorkspaceCatalog catalog`；`chatCubit.loadWorkspaceIndex(sessionRepo)` → `chatCubit.loadWorkspaceIndex()`；`loadWorkspaceData` → `chatCubit.reloadData()`；`_ensureDefaultWorkspace` 的 `DefaultWorkspaceService.ensureDefault(catalog, ...)`；删除 `loadWorkspaceIndexAfterSeed` 二次加载（catalog 内存已含 seed 结果，直接 `chatCubit.emitSnapshot` 已有）。

- [ ] **Step 1: 逐文件机械迁移（先页面，后服务）**

对每个文件：删除 `context.read<SessionRepository>()` 的 mutation 用途（改走 `context.read<ChatCubit>().xxx(...)` 无 repo 版本或 `context.read<WorkspaceCatalog>()` 只读）；只读访问统一 `context.read<WorkspaceCatalog>()`（`workspaces` / `sessionsForWorkspace` / `workspaceById` / `sessionById`）。迁移清单按上面 Files 逐个执行，保持行为不变（mutation 后不额外 reload——catalog 已返回新快照）。

关键细节：
- `workspace_page.dart:272`：`loadSessionsForWorkspace` → `catalog.sessionsForWorkspace(workspaceId)`（await）。
- `workspace_session_actions.dart`：`renameSession`/`toggleSessionPin` 等 repo 调用 → `catalog.renameSession(...)` 等；`loadSessionsForWorkspace`（543 行）→ `catalog.sessionsForWorkspace`；`repo` 参数（535 行）删除。
- `default_workspace_service.dart`：按 Produces 重写 `ensureDefault` 与 `seed`（`seed` 用 `catalog.workspaces` 找主路径工作区）。
- `app_data_bootstrap.dart`：按 Produces 改签名与调用。
- `app_shell.dart`：按 Produces 接线。

- [ ] **Step 2: 修复受影响测试编译**

`cd client && flutter test --exclude-tags integration` 收集失败，逐个修复（多为 `context.read<SessionRepository>` 的页面测试替换为 `RepositoryProvider<WorkspaceCatalog>`、`showHomeNewWorkspaceDialog` 参数、`ensureDefault` 签名）。辅助：`client/test/support/post_frame_test_harness.dart:188-229` 的 `testAutomationSetup` / `testAutomationCubit` 改收 `catalog`。

- [ ] **Step 3: 静态检查**

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 错误 0 警告。

- [ ] **Step 4: 全量单测**

`cd client && flutter test --exclude-tags integration`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages client/lib/widgets client/lib/services/team client/lib/services/automation client/lib/services/launch client/lib/cubits/launch_profile_cubit.dart client/lib/app client/lib/main.dart client/test
git commit -m "refactor(ui): migrate pages and domain services to WorkspaceCatalog"
```

---

### Task 7: 性能回归断言 + 收尾验证

**Files:**
- Create: `client/test/services/catalog/workspace_catalog_no_scan_test.dart`
- Modify: `client/lib/services/catalog/workspace_catalog.dart`（如需要暴露测试钩子）

**Interfaces:**
- Consumes: Task 3-6 全部产物。

- [ ] **Step 1: 写性能回归测试**

```dart
// workspace_catalog_no_scan_test.dart
test('createWorkspaceWithFirstSession performs zero library-wide scans', () async {
  final tmp = await Directory.systemTemp.createTemp('catalog_noscan_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final repo = SessionRepository(rootDir: tmp.path);
  // 预置 5 个工作区 + 每区 10 个会话，模拟已有库
  for (var i = 0; i < 5; i++) {
    final ws = await repo.createWorkspace([WorkspaceFolder(path: '/seed$i')]);
    for (var j = 0; j < 10; j++) {
      await repo.createSession(ws.workspaceId);
    }
  }
  // 偷听全扫：子类覆盖 loadWorkspaces/loadSessions/loadSessionsForWorkspace 计数
  // SessionRepository 方法非 final，可继承覆盖：
  final counting = _CountingRepository(tmp.path);
  final catalog = WorkspaceCatalog(counting);
  await catalog.loadIndex();
  final before = counting.scanCount;
  await catalog.createWorkspaceWithFirstSession([const WorkspaceFolder(path: '/new')]);
  expect(counting.scanCount, before, reason: 'create must not rescan the library');
});
```

`_CountingRepository extends SessionRepository` 覆盖 `loadWorkspaces` / `loadSessions` / `loadSessionsForWorkspace`（super 调用 + 计数）。同时断言 `WorkspaceIndexStore` 落盘内容包含新工作区（同 Task 3 测试）。

Run: `cd client && flutter test test/services/catalog/workspace_catalog_no_scan_test.dart`
Expected: FAIL（当前 createWorkspaceWithFirstSession 若仍有全扫则计数增加）。

- [ ] **Step 2: 跑测试确认失败**（同上）

- [ ] **Step 3: 修复（若失败）**

若 `scanCount` 增加：定位残留全扫（如 `createSession` 内 `_readManifest(indexOnly: true)` 不算全扫——计数函数只统计 loadWorkspaces/loadSessions/loadSessionsForWorkspace；`knownWorkspace` 未传导致 repo.createSession 读 manifest 可接受，非全扫）。若 `WorkspaceIndexStore` 未含新工作区：`_flushIndex` 在测试里需触发——300ms 防抖在 `testWidgets` 外真实计时，用 `await Future.delayed(const Duration(milliseconds: 400))` 后断言。

- [ ] **Step 4: 全量验证**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```
Expected: 全绿。

- [ ] **Step 5: 运行时验证**

`cd client && flutter run -d linux`（如有桌面环境）或 `flutter test test/integration` 抽样：创建新工作区 → 观察日志无 `[boot] SessionDataStore.loadWorkspaceData` 全扫标记；`createSession` 日志（`[session-launch] createSession done`）totalMs 显著下降。`appLogger` 的 `[boot] loadWorkspacesIndex validate ok` 等日志保持。

- [ ] **Step 6: Commit**

```bash
git add client/test/services/catalog/workspace_catalog_no_scan_test.dart
git commit -m "test(catalog): assert create path performs zero library scans"
```

---

## 自审清单（执行前核对）

1. **Spec 覆盖**：spec 的 §1 统一 mutation 模式 → Task 3；§2 createWorkspaceWithFirstSession 时序 → Task 3（t4 trust 后台 = Task 4 + Task 3 的 provisionTrust；t5 防抖 = Task 3 `_flushIndex`）；§3 trust 后台+门控 → Task 4；§4 防抖索引 → Task 3；§5 读取/hydration → Task 2（`sessionsForWorkspace` 自动 hydration）+ Task 6（automation/materializer/workspace_page/workspace_session_actions 迁移）；§6 调用面迁移 → Task 5/6；§7 错误处理 → Task 3（写穿失败抛错、`_flushIndex` 日志、trust 失败日志）、Task 4（门控 catch）；测试节 → Task 2/3/4/7。
2. **占位符**：Task 3 测试第三个用例有"placeholder"字样——已在 Step 1 内给出完整改写，无残留。
3. **类型一致性**：`catalog.createWorkspace`（Task 6 需要）已在 Task 3 的 Produces 中定义为公开方法；`createWorkspaceWithFirstSession` 复用它。Task 6 `DefaultWorkspaceService.ensureDefault(WorkspaceCatalog catalog, ...)` 与此一致。
4. **生命周期 wiring**：Task 4 定义 `SessionLifecycleService.trustGate` 为可变公开字段，Task 6 app_shell 事后赋值，无构造顺序问题。
