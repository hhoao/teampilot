# Project / Identity Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple a project (a working directory) from its launch identity (a team, or simple/personal mode); the identity is chosen when opening a project via an "open with…" dialog, not baked into the project at creation.

**Architecture:** `AppProject` loses `teamId` entirely — a project is just directory(s)+name+icon. The launch identity (`personal | team:<id>`) is carried on the project route as `?as=` and resolved by the launch/config chain off the **session's** `sessionTeam` instead of the project's team. The home grid lists all projects; clicking one opens a launch dialog. No backward compatibility and no migration (the app has no users yet — old `workspace/projects/` data is discarded).

**Tech Stack:** Flutter, `flutter_bloc` cubits, `go_router`, `flutter_test` + `bloc_test`. Filesystem via `AppStorage.fs` with constructor-injected overrides for tests.

**Design doc:** [docs/project-identity-launch-architecture.md](../../project-identity-launch-architecture.md)

**Before you start:** Read `AGENTS.md` (architecture + conventions) and `docs/CODE_QUALITY.md`. Wipe any stale dev data once before testing the UI manually: delete `~/.local/share/com.hhoa.teampilot/workspace/projects/` (Linux). All commands run from the `client/` directory.

**Verification gate (run before every commit):**
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

---

## Phase 1 — Model, repository, launch chain (backend, no UI)

After this phase the app will not compile against the UI yet (the UI still passes `teamId`); that is expected and fixed in Phase 3. Phase 1 lands the model/service core and its tests. Work top-down: model → repo → data store → cubit → lifecycle.

### Task 1: Add the `LaunchIdentity` value type

**Files:**
- Create: `client/lib/models/launch_identity.dart`
- Test: `client/test/models/launch_identity_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/launch_identity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';

void main() {
  test('personal round-trips through query encoding', () {
    expect(LaunchIdentity.personal.encode(), 'personal');
    expect(LaunchIdentity.decode('personal'), LaunchIdentity.personal);
  });

  test('team encodes/decodes with id', () {
    const id = LaunchIdentity.team('abc');
    expect(id.encode(), 'team:abc');
    expect(LaunchIdentity.decode('team:abc'), id);
  });

  test('decode returns null for missing or malformed input', () {
    expect(LaunchIdentity.decode(null), isNull);
    expect(LaunchIdentity.decode(''), isNull);
    expect(LaunchIdentity.decode('team:'), isNull);
    expect(LaunchIdentity.decode('bogus'), isNull);
  });

  test('teamId is empty for personal and the id for team', () {
    expect(LaunchIdentity.personal.teamId, '');
    expect(const LaunchIdentity.team('abc').teamId, 'abc');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/launch_identity_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/models/launch_identity.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
// client/lib/models/launch_identity.dart
import 'package:flutter/foundation.dart';

/// How a project is opened: simple/personal mode, or as a specific team.
/// Encoded on the project route as `?as=personal` or `?as=team:<teamId>`.
@immutable
class LaunchIdentity {
  const LaunchIdentity._(this.teamId);

  /// Simple mode — no team. [teamId] is empty.
  const LaunchIdentity.personal() : teamId = '';

  /// Team mode for [teamId] (must be non-empty).
  const LaunchIdentity.team(this.teamId);

  static const personal = LaunchIdentity.personal();

  /// Stable team id, or empty string for personal.
  final String teamId;

  bool get isPersonal => teamId.isEmpty;

  String encode() => isPersonal ? 'personal' : 'team:$teamId';

  /// Parses the `?as=` query value. Returns null when absent or malformed.
  static LaunchIdentity? decode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value == 'personal') return LaunchIdentity.personal;
    const prefix = 'team:';
    if (value.startsWith(prefix)) {
      final id = value.substring(prefix.length).trim();
      if (id.isEmpty) return null;
      return LaunchIdentity.team(id);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchIdentity &&
          runtimeType == other.runtimeType &&
          teamId == other.teamId;

  @override
  int get hashCode => teamId.hashCode;

  @override
  String toString() => 'LaunchIdentity(${encode()})';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/launch_identity_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/launch_identity.dart client/test/models/launch_identity_test.dart
git commit -m "feat(model): add LaunchIdentity value type"
```

---

### Task 2: Remove `teamId` from `AppProject`

The model carries no team. `defaultPersonalId` / `isDefaultPersonal` are also deleted (personal is now a launch identity, not a built-in project).

**Files:**
- Modify: `client/lib/models/app_project.dart`
- Test: `client/test/models/app_project_test.dart` (create if absent)

- [ ] **Step 1: Write the failing test**

```dart
// client/test/models/app_project_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';

void main() {
  test('json round-trip carries no teamId', () {
    final project = AppProject(
      projectId: 'p1',
      primaryPath: '/tmp/repo',
      display: 'Repo',
      createdAt: 1,
      updatedAt: 2,
    );
    final json = project.toJson();
    expect(json.containsKey('teamId'), isFalse);
    final restored = AppProject.fromJson(json);
    expect(restored.projectId, 'p1');
    expect(restored.primaryPath, '/tmp/repo');
    expect(restored.display, 'Repo');
  });

  test('legacy teamId key in json is ignored on read', () {
    final restored = AppProject.fromJson({
      'projectId': 'p1',
      'primaryPath': '/tmp/repo',
      'teamId': 'old-team',
      'createdAt': 1,
    });
    expect(restored.projectId, 'p1');
    // No teamId surface exists; the field is simply dropped.
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/app_project_test.dart`
Expected: FAIL — the constructor still accepts `teamId` and `toJson` still emits it, so `json.containsKey('teamId')` is true.

- [ ] **Step 3: Edit `app_project.dart`**

Delete every `teamId` reference and the personal-project constants. Concretely:

1. Delete the `defaultPersonalId` const (lines ~7-9) and the `isDefaultPersonal` getter (lines ~55-57).
2. Remove `this.teamId = ''` from the constructor.
3. In `fromJson`, delete `teamId: json['teamId'] as String? ?? '',`.
4. Delete the `final String teamId;` field.
5. In `copyWith`, delete the `String? teamId,` parameter and `teamId: teamId ?? this.teamId,`.
6. In `toJson`, delete `'teamId': teamId,`.
7. In `operator ==`, delete `teamId == other.teamId &&`.
8. In `hashCode`, delete `teamId,`.

After editing, the class has: `projectId, primaryPath, additionalPaths, display, icon, createdAt, updatedAt, sessionIds`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/app_project_test.dart`
Expected: PASS (2 tests). Other files will not compile yet — that is fixed in the next tasks.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/app_project.dart client/test/models/app_project_test.dart
git commit -m "feat(model)!: remove teamId and defaultPersonal from AppProject"
```

---

### Task 3: `SessionRepository.createProject` keyed by path only; delete personal-project seeding

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Test: `client/test/repositories/session_repository_test.dart`

Reference current behavior: `createProject(primaryPath, {required teamId, additionalPaths, display})` dedups by `(teamId, primaryPath)` (lines ~135-187); `ensureDefaultPersonalProject` (lines ~118-133); a guard at line ~707 references `AppProject.defaultPersonalId`.

- [ ] **Step 1: Write the failing test**

Add to `session_repository_test.dart`:

```dart
test('createProject dedups by primaryPath regardless of caller', () async {
  final tmp = await Directory.systemTemp.createTemp('fs_session_repo_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final repo = SessionRepository(rootDir: tmp.path);

  final a = await repo.createProject('/tmp/shared');
  final b = await repo.createProject(
    '/tmp/shared',
    additionalPaths: ['/tmp/extra'],
    display: 'Shared',
  );

  expect(b.projectId, a.projectId, reason: 'same path => same project');
  final projects = await repo.loadProjects();
  expect(projects.length, 1);
  expect(projects.single.additionalPaths, contains('/tmp/extra'));
  expect(projects.single.display, 'Shared');
});
```

Also update the existing test at line ~44 that calls `repo.createProject('/tmp/my-project', teamId: '')` — remove the `teamId: ''` argument.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/repositories/session_repository_test.dart`
Expected: FAIL to compile — `createProject` still requires `teamId`.

- [ ] **Step 3: Edit `session_repository.dart`**

1. Delete the entire `ensureDefaultPersonalProject` method (lines ~118-133).
2. Change the `createProject` signature from:
   ```dart
   Future<AppProject> createProject(
     String primaryPath, {
     required String teamId,
     List<String> additionalPaths = const [],
     String display = '',
   }) async {
   ```
   to:
   ```dart
   Future<AppProject> createProject(
     String primaryPath, {
     List<String> additionalPaths = const [],
     String display = '',
   }) async {
   ```
3. In the dedup loop, change the guard from:
   ```dart
   if (existing.teamId != teamId ||
       !projectPathsEqual(existing.primaryPath, trimmed)) {
     continue;
   }
   ```
   to:
   ```dart
   if (!projectPathsEqual(existing.primaryPath, trimmed)) {
     continue;
   }
   ```
4. In the new-project `AppProject(...)` constructor call, delete `teamId: teamId,`.
5. Find the guard at line ~707 (`if (projectId == AppProject.defaultPersonalId) return;`) and delete that statement (the surrounding method no longer needs to special-case it).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/repositories/session_repository_test.dart`
Expected: PASS (existing tests + the new dedup test).

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/session_repository_test.dart
git commit -m "feat(repo)!: key createProject by path; drop teamId and personal-project seeding"
```

---

### Task 4: `session_data_store.createProjectWithFirstSession` — drop the `teamId` write path

Current (lines ~105-133) passes `teamId: sessionTeamId` to `createProject` and seeds a default profile only when `sessionTeamId` is empty. Personal-vs-team config is now decided by the session's `sessionTeam`, not the project, so the profile should be created for the project regardless, and the team binding lives on the session.

**Files:**
- Modify: `client/lib/cubits/chat/session_data_store.dart`
- Test: `client/test/cubits/session_data_store_personal_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `session_data_store_personal_test.dart` (mirror the existing setup there for constructing a `SessionDataStore` + temp `SessionRepository`):

```dart
test('createProjectWithFirstSession writes no teamId on the project '
    'and tags the session with sessionTeam', () async {
  // ... arrange repo (SessionRepository(rootDir: tmp.path)) and data store
  final result = await store.createProjectWithFirstSession(
    '/tmp/proj',
    repo,
    sessionTeamId: 'team-x',
  );
  final projects = await repo.loadProjects();
  final project = projects.firstWhere((p) => p.projectId == result.projectId);
  expect(project.toJson().containsKey('teamId'), isFalse);

  final sessions = await repo.loadSessions();
  final session = sessions.firstWhere((s) => s.projectId == result.projectId);
  expect(session.sessionTeam, 'team-x');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cubits/session_data_store_personal_test.dart`
Expected: FAIL to compile — `createProject` no longer accepts `teamId:`.

- [ ] **Step 3: Edit `createProjectWithFirstSession`**

Replace the body (lines ~114-130) with:

```dart
final project = await repo.createProject(
  primaryPath,
  additionalPaths: additionalPaths,
  display: display,
);
if (projectProfileRepository != null) {
  final profile = await projectProfileRepository.createDefault(
    project.projectId,
  );
  await projectProfileRepository.save(profile);
}
await repo.createSession(
  project.projectId,
  sessionTeam: sessionTeamId,
  rosterMembers: rosterMembers,
);
```

(The `sessionTeamId`/`rosterMembers`/`additionalPaths`/`display`/`projectProfileRepository` parameters keep their existing names and defaults.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/cubits/session_data_store_personal_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/session_data_store.dart client/test/cubits/session_data_store_personal_test.dart
git commit -m "feat(chat)!: stop writing teamId on projects in data store"
```

---

### Task 5: Re-key the launch chain off `sessionTeam`, not `project.teamId`

`_isPersonalLaunch` (lines ~458-461) currently requires `project.teamId.isEmpty`. With `teamId` gone, personal is determined solely by the session.

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Test: `client/test/services/session/session_lifecycle_personal_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/session/session_lifecycle_personal_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

class _Svc extends SessionLifecycleService {
  _Svc() : super(appDataBasePath: Directory.systemTemp.path);
  bool personalFor(AppProject p, AppSession s) =>
      debugIsPersonalLaunch(p, s);
}

void main() {
  final project = AppProject(
    projectId: 'p1',
    primaryPath: '/tmp/repo',
    createdAt: 0,
  );

  test('empty sessionTeam => personal launch', () {
    final session = AppSession(
      sessionId: 's1',
      projectId: 'p1',
      primaryPath: '/tmp/repo',
      sessionTeam: '',
      createdAt: 0,
    );
    expect(_Svc().personalFor(project, session), isTrue);
  });

  test('non-empty sessionTeam => team launch', () {
    final session = AppSession(
      sessionId: 's1',
      projectId: 'p1',
      primaryPath: '/tmp/repo',
      sessionTeam: 'team-x',
      createdAt: 0,
    );
    expect(_Svc().personalFor(project, session), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/session/session_lifecycle_personal_test.dart`
Expected: FAIL — `debugIsPersonalLaunch` does not exist and `_isPersonalLaunch` still reads `project.teamId`.

- [ ] **Step 3: Edit `session_lifecycle_service.dart`**

Replace the private helper (lines ~458-461):

```dart
bool _isPersonalLaunch(AppProject? project, AppSession session) =>
    project != null &&
    project.teamId.isEmpty &&
    session.sessionTeam.trim().isEmpty;
```

with (personal iff the session has no team; a project is still required because personal config is per-project):

```dart
bool _isPersonalLaunch(AppProject? project, AppSession session) =>
    project != null && session.sessionTeam.trim().isEmpty;

/// Test-only seam for [_isPersonalLaunch].
@visibleForTesting
bool debugIsPersonalLaunch(AppProject project, AppSession session) =>
    _isPersonalLaunch(project, session);
```

Add `import 'package:flutter/foundation.dart';` at the top if not already present (for `@visibleForTesting`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/session/session_lifecycle_personal_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the full backend suite + analyze**

Run: `flutter test --exclude-tags integration test/models test/repositories test/cubits test/services && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models lib/repositories lib/services lib/cubits`
Expected: model/repo/service/cubit tests PASS. Analyze may still report errors in `lib/pages/**` (UI passes `teamId`) — those are fixed in Phase 3 and are expected now.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session/session_lifecycle_service.dart client/test/services/session/session_lifecycle_personal_test.dart
git commit -m "feat(session)!: derive personal launch from sessionTeam not project.teamId"
```

---

## Phase 2 — Launch identity routing, prefs store, and dialog

### Task 6: Per-project launch prefs store

Mirrors `HomeWorkspaceProjectDisplayPrefsStore` (`client/lib/services/home_workspace/home_workspace_project_display_prefs_store.dart`).

**Files:**
- Create: `client/lib/services/home_workspace/home_workspace_project_launch_prefs_store.dart`
- Modify: `client/lib/services/storage/app_storage.dart` (add a path getter)
- Test: `client/test/services/home_workspace/home_workspace_project_launch_prefs_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/home_workspace/home_workspace_project_launch_prefs_store_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/home_workspace_project_launch_prefs_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('round-trips per-project launch prefs', () async {
    final tmp = await Directory.systemTemp.createTemp('launch_prefs_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = HomeWorkspaceProjectLaunchPrefsStore(
      fs: LocalFilesystem(),
      pathOverride: '${tmp.path}/launch-prefs.json',
    );

    expect(await store.prefsFor('p1'), isNull);

    await store.save('p1', const ProjectLaunchPref(
      lastIdentity: 'team:abc',
      remember: true,
    ));
    final loaded = await store.prefsFor('p1');
    expect(loaded?.lastIdentity, 'team:abc');
    expect(loaded?.remember, isTrue);

    // Unrelated project unaffected.
    expect(await store.prefsFor('p2'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/home_workspace/home_workspace_project_launch_prefs_store_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3a: Add the storage path getter**

In `client/lib/services/storage/app_storage.dart`, find the existing getter `homeWorkspaceProjectDisplayPrefsJson` and add directly beneath it (same `home-workspace/` directory):

```dart
String get homeWorkspaceProjectLaunchPrefsJson =>
    join(homeWorkspaceDir, 'project-launch-prefs.json');
```

(Use the same `join(...)` helper and `homeWorkspaceDir` base that `homeWorkspaceProjectDisplayPrefsJson` uses — match its exact form.)

- [ ] **Step 3b: Write the store**

```dart
// client/lib/services/home_workspace/home_workspace_project_launch_prefs_store.dart
import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Remembered "open with…" choice for one project.
class ProjectLaunchPref {
  const ProjectLaunchPref({required this.lastIdentity, required this.remember});

  /// Encoded [LaunchIdentity] ("personal" | "team:<id>").
  final String lastIdentity;

  /// When true, opening the project skips the dialog and uses [lastIdentity].
  final bool remember;
}

/// Persists per-project launch choices at
/// `home-workspace/project-launch-prefs.json` as `{ projectId: {...} }`.
class HomeWorkspaceProjectLaunchPrefsStore {
  HomeWorkspaceProjectLaunchPrefsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.homeWorkspaceProjectLaunchPrefsJson;

  Future<Map<String, ProjectLaunchPref>> _loadAll() async {
    try {
      final text = await _fs.readString(_path);
      if (text == null || text.isEmpty) return {};
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final out = <String, ProjectLaunchPref>{};
      for (final entry in root.entries) {
        final value = entry.value;
        if (value is Map) {
          final m = value.cast<String, Object?>();
          final id = m['lastIdentity'] as String?;
          if (id == null || id.isEmpty) continue;
          out[entry.key] = ProjectLaunchPref(
            lastIdentity: id,
            remember: m['remember'] as bool? ?? false,
          );
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<ProjectLaunchPref?> prefsFor(String projectId) async =>
      (await _loadAll())[projectId];

  Future<void> save(String projectId, ProjectLaunchPref pref) async {
    final all = await _loadAll();
    all[projectId] = pref;
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(_path));
    await _fs.atomicWrite(
      _path,
      jsonEncode({
        for (final e in all.entries)
          e.key: {
            'lastIdentity': e.value.lastIdentity,
            'remember': e.value.remember,
          },
      }),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/home_workspace/home_workspace_project_launch_prefs_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/home_workspace/home_workspace_project_launch_prefs_store.dart client/lib/services/storage/app_storage.dart client/test/services/home_workspace/home_workspace_project_launch_prefs_store_test.dart
git commit -m "feat(home): add per-project launch prefs store"
```

---

### Task 7: Add the `?as=` identity to the project route

**Files:**
- Modify: `client/lib/router/app_router.dart` (route at lines ~130-144)
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_page.dart` (constructor, lines ~25-43)

- [ ] **Step 1: Write the failing test**

```dart
// client/test/router/project_identity_route_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';

void main() {
  test('?as= query value decodes to the launch identity', () {
    // The route reads state.uri.queryParameters['as'] and passes it through
    // LaunchIdentity.decode. This guards the contract the route relies on.
    expect(LaunchIdentity.decode('team:abc'),
        const LaunchIdentity.team('abc'));
    expect(LaunchIdentity.decode('personal'), LaunchIdentity.personal);
    expect(LaunchIdentity.decode(null), isNull);
  });
}
```

(The route itself is exercised by the widget tests in Task 11; this unit test pins the decode contract.)

- [ ] **Step 2: Run test to verify it fails... or passes**

Run: `flutter test test/router/project_identity_route_test.dart`
Expected: PASS immediately (depends only on Task 1). This is a guard, not a red test — proceed to wire the route.

- [ ] **Step 3: Edit the route pageBuilder**

In `app_router.dart`, change the `/home-v2/project/:projectId` `pageBuilder` to read `as` and pass a decoded identity:

```dart
GoRoute(
  path: '/home-v2/project/:projectId',
  pageBuilder: (context, state) {
    final query = state.uri.queryParameters;
    return NoTransitionPage(
      child: HomeWorkspaceProjectPage(
        projectId: state.pathParameters['projectId']!,
        identity: LaunchIdentity.decode(query['as']),
        view: query['view'],
        configSection: ProjectConfigSection.fromSegment(query['section']),
      ),
    );
  },
),
```

Add `import '../models/launch_identity.dart';` to `app_router.dart`.

- [ ] **Step 4: Edit `HomeWorkspaceProjectPage` constructor**

Add the field + param (constructor at lines ~25-43):

```dart
const HomeWorkspaceProjectPage({
  required this.projectId,
  this.identity,
  this.view,
  this.configSection,
  super.key,
});

final String projectId;

/// Launch identity from `?as=`. Null means "no identity chosen" → the page
/// redirects to the project grid + opens the launch dialog (see Task 10).
final LaunchIdentity? identity;

final String? view;
final ProjectConfigSection? configSection;
```

Add `import '../../../models/launch_identity.dart';`. (Full use of `identity` lands in Task 10; this task only adds the wiring so the project compiles with the new route.)

- [ ] **Step 5: Run test + analyze the touched files**

Run: `flutter test test/router/project_identity_route_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings lib/router/app_router.dart`
Expected: test PASS; `app_router.dart` analyzes clean.

- [ ] **Step 6: Commit**

```bash
git add client/lib/router/app_router.dart client/lib/pages/home_workspace/project/home_workspace_project_page.dart client/test/router/project_identity_route_test.dart
git commit -m "feat(router): carry launch identity on the project route as ?as="
```

---

### Task 8: The launch ("open with…") dialog

A modal listing **简单模式** + teams (teams sorted by most-recent use for the project), with a **记住选择** checkbox. Returns the chosen `LaunchIdentity` and the remember flag.

**Files:**
- Create: `client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart`
- Test: `client/test/pages/home_workspace/home_workspace_launch_project_dialog_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/pages/home_workspace/home_workspace_launch_project_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_launch_project_dialog.dart';

void main() {
  testWidgets('returns personal identity when simple mode is chosen',
      (tester) async {
    LaunchProjectChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showHomeWorkspaceLaunchProjectDialog(
                  context,
                  projectName: 'Repo',
                  teams: const <LaunchProjectTeamOption>[
                    LaunchProjectTeamOption(id: 't1', name: 'Backend'),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('简单模式'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.identity, LaunchIdentity.personal);
    expect(result!.remember, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pages/home_workspace/home_workspace_launch_project_dialog_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the dialog**

```dart
// client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart
import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/launch_identity.dart';
import '../../widgets/app_dialog.dart';

/// One selectable team in the launch dialog (already sorted by the caller).
class LaunchProjectTeamOption {
  const LaunchProjectTeamOption({required this.id, required this.name});
  final String id;
  final String name;
}

/// Result of the launch dialog.
class LaunchProjectChoice {
  const LaunchProjectChoice({required this.identity, required this.remember});
  final LaunchIdentity identity;
  final bool remember;
}

/// Asks which identity to open a project as. Returns null on cancel.
Future<LaunchProjectChoice?> showHomeWorkspaceLaunchProjectDialog(
  BuildContext context, {
  required String projectName,
  required List<LaunchProjectTeamOption> teams,
  LaunchIdentity? preselected,
}) {
  return showDialog<LaunchProjectChoice>(
    context: context,
    builder: (_) => _LaunchProjectDialog(
      projectName: projectName,
      teams: teams,
      preselected: preselected,
    ),
  );
}

class _LaunchProjectDialog extends StatefulWidget {
  const _LaunchProjectDialog({
    required this.projectName,
    required this.teams,
    this.preselected,
  });

  final String projectName;
  final List<LaunchProjectTeamOption> teams;
  final LaunchIdentity? preselected;

  @override
  State<_LaunchProjectDialog> createState() => _LaunchProjectDialogState();
}

class _LaunchProjectDialogState extends State<_LaunchProjectDialog> {
  late LaunchIdentity _selected =
      widget.preselected ?? LaunchIdentity.personal;
  bool _remember = false;

  void _choose(LaunchIdentity identity) {
    Navigator.of(context).pop(
      LaunchProjectChoice(identity: identity, remember: _remember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AppDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.homeWorkspaceLaunchProjectTitle),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(l10n.homeWorkspaceSimpleMode),
            selected: _selected == LaunchIdentity.personal,
            onTap: () => _choose(LaunchIdentity.personal),
          ),
          for (final team in widget.teams)
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(team.name),
              selected: _selected == LaunchIdentity.team(team.id),
              onTap: () => _choose(LaunchIdentity.team(team.id)),
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(l10n.homeWorkspaceRememberLaunchChoice),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add the l10n strings**

In `client/lib/l10n/app_en.arb` add:
```json
"homeWorkspaceLaunchProjectTitle": "Open with…",
"homeWorkspaceSimpleMode": "Simple mode",
"homeWorkspaceRememberLaunchChoice": "Remember my choice"
```
In `client/lib/l10n/app_zh.arb` add:
```json
"homeWorkspaceLaunchProjectTitle": "选择启动方式",
"homeWorkspaceSimpleMode": "简单模式",
"homeWorkspaceRememberLaunchChoice": "记住选择"
```
Then run `flutter pub get` to regenerate `app_localizations*.dart`.

> Note: the test taps `find.text('简单模式')`, so the test must run with the zh locale OR assert on the English string. Simplest: change the test's `find.text('简单模式')` to `find.text('Simple mode')` (default test locale is `en`). Update the test accordingly before Step 5.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter pub get && flutter test test/pages/home_workspace/home_workspace_launch_project_dialog_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_launch_project_dialog.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/home_workspace/home_workspace_launch_project_dialog_test.dart
git commit -m "feat(home): add open-with launch dialog"
```

---

### Task 9: Recent-team ordering helper (derive from session history)

Sort teams by the newest session for this project whose `sessionTeam` matches; teams with no session for the project sort last (stable by original order).

**Files:**
- Create: `client/lib/pages/home_workspace/launch_project_team_order.dart`
- Test: `client/test/pages/home_workspace/launch_project_team_order_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/pages/home_workspace/launch_project_team_order_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/home_workspace/launch_project_team_order.dart';

AppSession _s(String team, int updatedAt) => AppSession(
      sessionId: 's-$team-$updatedAt',
      projectId: 'p1',
      primaryPath: '/tmp/p1',
      sessionTeam: team,
      createdAt: 0,
      updatedAt: updatedAt,
    );

void main() {
  test('sorts team ids by most recent session for the project', () {
    final order = orderTeamIdsByRecentUse(
      projectId: 'p1',
      teamIds: const ['a', 'b', 'c'],
      sessions: [_s('b', 10), _s('a', 30), _s('b', 5)],
    );
    // a (30) > b (10) > c (none, keeps relative position last)
    expect(order, ['a', 'b', 'c']);
  });

  test('teams without sessions keep input order after used ones', () {
    final order = orderTeamIdsByRecentUse(
      projectId: 'p1',
      teamIds: const ['x', 'y', 'z'],
      sessions: [_s('z', 100)],
    );
    expect(order, ['z', 'x', 'y']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pages/home_workspace/launch_project_team_order_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the helper**

```dart
// client/lib/pages/home_workspace/launch_project_team_order.dart
import '../../models/app_session.dart';

/// Orders [teamIds] by the most-recent session for [projectId] whose
/// `sessionTeam` matches. Teams with no matching session keep their original
/// relative order, after all used teams.
List<String> orderTeamIdsByRecentUse({
  required String projectId,
  required List<String> teamIds,
  required List<AppSession> sessions,
}) {
  final lastUsed = <String, int>{};
  for (final s in sessions) {
    if (s.projectId != projectId) continue;
    final team = s.sessionTeam.trim();
    if (team.isEmpty) continue;
    final stamp = s.updatedAt != 0 ? s.updatedAt : s.createdAt;
    final existing = lastUsed[team];
    if (existing == null || stamp > existing) lastUsed[team] = stamp;
  }
  final indexed = [
    for (var i = 0; i < teamIds.length; i++) (i: i, id: teamIds[i]),
  ];
  indexed.sort((a, b) {
    final ua = lastUsed[a.id];
    final ub = lastUsed[b.id];
    if (ua != null && ub != null) return ub.compareTo(ua);
    if (ua != null) return -1;
    if (ub != null) return 1;
    return a.i.compareTo(b.i);
  });
  return [for (final e in indexed) e.id];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/pages/home_workspace/launch_project_team_order_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/launch_project_team_order.dart client/test/pages/home_workspace/launch_project_team_order_test.dart
git commit -m "feat(home): add recent-team ordering for launch dialog"
```

---

## Phase 3 — Navigation switch and final cleanup

This phase changes UI entry points and deletes the old `teamId` fork. After it, the app compiles and runs end-to-end.

### Task 10: Project page resolves personal/team by `identity`, not `project.teamId`

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_page.dart`

Current code (lines ~84-96, 145) reads `project.teamId.isEmpty`. Replace with the route `identity`.

- [ ] **Step 1: Edit `_syncProjectContext` and `build`**

1. In `build()` (line ~145) replace:
   ```dart
   final isPersonal = project.teamId.isEmpty;
   ```
   with:
   ```dart
   final identity = widget.identity;
   if (identity == null) {
     // No identity chosen (e.g. hand-typed URL) — bounce to the grid.
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (mounted) context.go('/home-v2?projects=1');
     });
     return WorkspacePageCardShell(
       chrome: WorkspacePageChrome.project,
       child: const SizedBox.shrink(),
     );
   }
   final isPersonal = identity.isPersonal;
   ```
2. In `_syncProjectContext()` (lines ~84-96) replace the `project.teamId` branch:
   ```dart
   if (project.teamId.isEmpty) {
     _loadPersonalProfile(project.projectId);
     return;
   }
   _syncSelectedTeam(project.teamId);
   ```
   with:
   ```dart
   final identity = widget.identity;
   if (identity == null || identity.isPersonal) {
     _loadPersonalProfile(project.projectId);
     return;
   }
   _syncSelectedTeam(identity.teamId);
   ```
3. In `_onSectionChanged` (line ~117) replace `if (project.teamId.isNotEmpty) return;` with `if (widget.identity?.isPersonal != true) return;` and append `?as=personal` to the built paths so navigation preserves the identity, e.g.:
   ```dart
   final base = '/home-v2/project/${project.projectId}?as=personal';
   final path = switch (section) {
     HomeWorkspaceProjectSection.conversations => base,
     HomeWorkspaceProjectSection.manage => '$base&view=manage',
     _ => base,
   };
   ```

- [ ] **Step 2: Pass identity into the workbench for session filtering**

`HomeWorkspaceProjectSplitPane` → `ChatPage` currently takes `isPersonalProject`. Add the team identity so the session list can filter. In `_buildPersonalCardBody` / `_buildTeamCardBody`, pass `sessionTeamFilter: identity.teamId` (empty for personal) down through `HomeWorkspaceProjectSplitPane` to `ChatPage`. Add a `final String sessionTeamFilter;` field to both `HomeWorkspaceProjectSplitPane` and `ChatPage`, and where `ChatPage` builds its session/tab list, filter `sessions.where((s) => s.sessionTeam.trim() == sessionTeamFilter)`.

> Search first: `rtk grep -n "isPersonalProject" lib/pages/home_workspace/project/ lib/pages/chat_page.dart` to find every constructor hop, and thread `sessionTeamFilter` alongside it through the same call sites.

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/project/`
Expected: clean (any remaining errors point to a missed `teamId` reference — fix it).

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/
git commit -m "feat(project)!: resolve identity from route and filter sessions by it"
```

---

### Task 11: Project grid lists all projects; card click opens the launch dialog

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_content.dart` (remove team filter + projects tab)
- Modify: `client/lib/pages/home_workspace/home_workspace_projects_tab.dart` (card `onTap` → dialog)
- Test: `client/test/pages/home_workspace/projects_tab_launch_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// client/test/pages/home_workspace/projects_tab_launch_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_launch_project_dialog.dart';
import 'package:teampilot/pages/home_workspace/launch_project_team_order.dart';

void main() {
  test('open-with flow composes ordering + dialog choice into a route', () {
    // Ordering feeds the dialog; the chosen identity builds the route. This
    // pins the contract the card onTap relies on (the widget wiring itself is
    // covered by manual golden-path; see plan notes).
    final order = orderTeamIdsByRecentUse(
      projectId: 'p1', teamIds: const ['a'], sessions: const []);
    expect(order, ['a']);
    const choice = LaunchProjectChoice(
        identity: LaunchIdentity.team('a'), remember: true);
    final route = '/home-v2/project/p1?as=${choice.identity.encode()}';
    expect(route, '/home-v2/project/p1?as=team:a');
  });
}
```

- [ ] **Step 2: Run test to verify it fails... or passes**

Run: `flutter test test/pages/home_workspace/projects_tab_launch_test.dart`
Expected: PASS (depends only on prior tasks). Guard test — proceed to wire the UI.

- [ ] **Step 3: Replace the card `onTap` in `home_workspace_projects_tab.dart`**

At lines ~448 and ~482 the cards do:
```dart
onTap: () => context.go('/home-v2/project/${project.projectId}'),
```
Replace each with a call to a shared handler `_openProject(context, project)` and add this method to the `HomeWorkspaceProjectsTab` (it needs `teams`, `sessions`, and the launch-prefs store — thread them in as fields; `teams` from `context.read<TeamCubit>().state.teams`, `sessions` is already a constructor field):

```dart
Future<void> _openProject(BuildContext context, AppProject project) async {
  final store = HomeWorkspaceProjectLaunchPrefsStore();
  final pref = await store.prefsFor(project.projectId);
  if (!context.mounted) return;

  // Remembered choice: skip the dialog.
  if (pref != null && pref.remember) {
    final id = LaunchIdentity.decode(pref.lastIdentity);
    if (id != null) {
      context.go('/home-v2/project/${project.projectId}?as=${id.encode()}');
      return;
    }
  }

  final teams = context.read<TeamCubit>().state.teams;
  final orderedIds = orderTeamIdsByRecentUse(
    projectId: project.projectId,
    teamIds: teams.map((t) => t.id).toList(),
    sessions: sessions,
  );
  final byId = {for (final t in teams) t.id: t};
  final options = [
    for (final id in orderedIds)
      if (byId[id] != null)
        LaunchProjectTeamOption(id: id, name: byId[id]!.name),
  ];
  final choice = await showHomeWorkspaceLaunchProjectDialog(
    context,
    projectName: project.effectiveDisplay,
    teams: options,
    preselected: LaunchIdentity.decode(pref?.lastIdentity ?? ''),
  );
  if (choice == null || !context.mounted) return;
  await store.save(
    project.projectId,
    ProjectLaunchPref(
      lastIdentity: choice.identity.encode(),
      remember: choice.remember,
    ),
  );
  if (!context.mounted) return;
  context.go('/home-v2/project/${project.projectId}?as=${choice.identity.encode()}');
}
```

Add imports: `launch_identity.dart`, `home_workspace_launch_project_dialog.dart`, `launch_project_team_order.dart`, the launch prefs store, `team_cubit.dart`, and `flutter_bloc`.

- [ ] **Step 4: Make the grid show all projects in `home_workspace_content.dart`**

1. Delete the `_projectsForTeam` method (lines ~213-224) and its cache fields `_lastAllProjects` / `_lastTeamId` / `_teamProjects`.
2. Remove tab index 0 ("Projects"): drop the leading `null` from `_sections` (line ~55) so it becomes `[TeamConfigSection.members, .skills, .plugins, .mcp, .extensions, .team]`, and remove `l10n.homeWorkspaceTeamProjects` from the `tabs` list (line ~152). The team pane is now config-only.
3. The all-projects grid moves to its own pane reached from the sidebar's **全部项目** entry (Task 12). Extract the `HomeWorkspaceProjectsTab(...)` block (lines ~174-183) into a small `HomeWorkspaceAllProjectsPane` widget that reads `context.select<ChatCubit, List<AppProject>>((c) => c.state.projects)` (no team filter) and keeps the existing grid/sort/favorite plumbing. Wire it in Task 12.

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/pages/home_workspace/projects_tab_launch_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/`
Expected: test PASS; analyze clean for the home_workspace UI.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_projects_tab.dart client/lib/pages/home_workspace/home_workspace_content.dart client/test/pages/home_workspace/projects_tab_launch_test.dart
git commit -m "feat(home)!: list all projects and open via launch dialog"
```

---

### Task 12: Sidebar — add **全部项目**, remove **简单模式**

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart` (personal row at lines ~92-97; callbacks)
- Modify: `client/lib/pages/home_workspace/home_workspace_page.dart` (scope + pane selection)

- [ ] **Step 1: Edit the sidebar**

1. Delete the **简单模式 / 个人** `_ShortcutRow` block (lines ~92-97) and the surrounding divider that becomes redundant.
2. Add an **全部项目** `_ShortcutRow` (above 我的团队) with `Icons.folder_copy_outlined`, label `l10n.homeWorkspaceAllProjects`, wired to a new `onSelectAllProjects` callback. Add `final VoidCallback? onSelectAllProjects;` and `final bool allProjectsActive;` to the widget and constructor; remove `onSelectPersonal` / `personalActive`.

- [ ] **Step 2: Edit `home_workspace_page.dart`**

1. Replace the `HomeWorkspaceScope` usage: the right pane shows the all-projects pane when selected. Add a bool `_allProjectsActive` (default `true` so the home opens on All Projects). Remove the `personal` scope path and `HomeWorkspacePersonalContent` usage.
2. In the `HomeWorkspaceSidebar(...)`, pass `allProjectsActive: _allProjectsActive`, `onSelectAllProjects: () => setState(() { _allProjectsActive = true; _globalView = null; _libraryView = null; })`, and in `onSelectTeam`/`onSelectGlobalView`/`onSelectLibraryView` set `_allProjectsActive = false`.
3. In the right-pane builder, when `_allProjectsActive` (and no global/library view) render `const HomeWorkspaceAllProjectsPane()` (from Task 11 step 4) instead of `HomeWorkspaceContent`. Keep `HomeWorkspaceContent` for the team-config view path.

- [ ] **Step 3: Add l10n string**

`app_en.arb`: `"homeWorkspaceAllProjects": "All projects"`; `app_zh.arb`: `"homeWorkspaceAllProjects": "全部项目"`. Run `flutter pub get`.

- [ ] **Step 4: Delete dead personal-home code**

Remove `client/lib/pages/home_workspace/home_workspace_personal_content.dart` and its imports/usages if nothing else references it (`rtk grep -rn HomeWorkspacePersonalContent lib test` must be empty before deleting).

- [ ] **Step 5: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/home_workspace/
git commit -m "feat(home)!: sidebar all-projects entry, remove simple-mode entry"
```

---

### Task 13: New-project dialog drops team selection

`showHomeWorkspaceNewProjectDialog` (`client/lib/pages/home_workspace/home_workspace_new_project_dialog.dart`) currently resolves a `resolvedTeamId` and passes `sessionTeamId` into `createProjectWithFirstSession`. A new project is now team-agnostic.

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_new_project_dialog.dart`

- [ ] **Step 1: Edit the create flow**

Replace the post-dialog block (lines ~37-57) with:

```dart
final projectId = await chatCubit.createProjectWithFirstSession(
  result.directories.first,
  repository,
  // New projects start in simple mode; identity is chosen at open time.
  sessionTeamId: '',
  additionalPaths: result.directories.skip(1).toList(growable: false),
  display: result.display,
  projectProfileRepository:
      projectProfileRepository ?? context.read<ProjectProfileRepository>(),
);
if (!context.mounted) return;
context.go('/home-v2/project/$projectId?as=personal');
```

Delete the now-unused `resolvedTeamId` / `rosterMembers` / `profileRepo` locals and the `teamCubit` / `sessionTeamId` parameters from `showHomeWorkspaceNewProjectDialog` (and update its call sites — `rtk grep -rn showHomeWorkspaceNewProjectDialog lib`).

- [ ] **Step 2: Analyze + run full suite**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze clean across the project; all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_new_project_dialog.dart
git commit -m "feat(home)!: new project is team-agnostic, opens in simple mode"
```

---

### Task 14: Config sections by identity; final teamId sweep

**Files:**
- Modify: `client/lib/pages/home_workspace/project/project_config_section.dart`
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_config_workspace.dart` (consumes `personalSections` vs `teamSections`)

- [ ] **Step 1: Drive the config surface by identity**

In `home_workspace_project_page.dart`, the config workspace already only opens for personal today. Confirm `_buildPersonalCardBody` is reached only when `identity.isPersonal`, and the team body shows `HomeWorkspaceProjectSettingsView`. Where `ProjectConfigSection.personalSections` / `teamSections` is selected, choose by `widget.identity!.isPersonal` instead of `project.teamId.isEmpty`. (`rtk grep -rn "personalSections\|teamSections\|\.teamId" lib/pages/home_workspace/project/` to find the exact spots.)

- [ ] **Step 2: Final repository-wide `teamId` sweep**

Run: `rtk grep -rn "\.teamId\|defaultPersonalId\|isDefaultPersonal\|ensureDefaultPersonalProject" lib`
Expected: zero hits in app code (matches in `team_config.dart` for `TeamConfig.id`/member fields are fine — those are team-side, not project-side; verify each remaining hit is unrelated to `AppProject`). Fix any `AppProject.teamId` leftover.

- [ ] **Step 3: Analyze + full test suite**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: clean; all PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/
git commit -m "refactor(project): drive config surface by identity; remove last teamId refs"
```

---

### Task 15: Manual golden-path verification

Automated widget coverage for the full open→dialog→workbench loop is brittle (nested `LayoutBuilder`s, PTY). Verify by hand and document the result.

- [ ] **Step 1: Launch the app on a clean workspace**

```bash
rm -rf ~/.local/share/com.hhoa.teampilot/workspace/projects/
cd client && flutter run -d linux
```

- [ ] **Step 2: Walk the flow and confirm each:**
  - Home opens on **全部项目**; the grid lists projects with no team duplication.
  - **新建项目** creates a directory-only project and opens it in simple mode.
  - Clicking a project card shows the **选择启动方式** dialog; teams are ordered by recent use; **记住选择** persists and skips the dialog next time.
  - Opening as a team shows only that team's sessions; opening as simple mode shows only personal sessions.
  - The card hover **▾** / right-click re-opens the dialog after a remembered choice.
  - **我的团队** entries open team config only (no project list); there is no **简单模式** sidebar entry.

- [ ] **Step 3: Record the result**

Append a short "Golden-path verified <date>" note (and any follow-ups) to `docs/project-identity-launch-architecture.md`, then commit:

```bash
git add docs/project-identity-launch-architecture.md
git commit -m "docs: record project-identity launch golden-path verification"
```

---

## Self-review notes (for the executor)

- **Spec coverage:** model/repo/lifecycle (Tasks 2–5) = doc "Core model" + "No migration" deletions; routing/store/dialog (Tasks 6–9) = doc "UX flow" + "launch prefs"; nav/cleanup (Tasks 10–14) = doc "What changes" table rows; manual check (Task 15) = doc verification.
- **Type consistency:** `LaunchIdentity.encode()`/`decode()`, `ProjectLaunchPref{lastIdentity, remember}`, `LaunchProjectTeamOption{id, name}`, `LaunchProjectChoice{identity, remember}`, `orderTeamIdsByRecentUse(projectId, teamIds, sessions)`, `showHomeWorkspaceLaunchProjectDialog(context, projectName, teams, preselected)` are used identically across tasks.
- **Known soft spots needing search-first care:** threading `sessionTeamFilter` through `HomeWorkspaceProjectSplitPane`→`ChatPage` (Task 10 Step 2), and finding every `showHomeWorkspaceNewProjectDialog` call site (Task 13). Use the `rtk grep` commands given inline.
- **Ordering:** Phases are sequential. Within Phase 1 the app intentionally won't fully analyze until Phase 3 removes UI `teamId` uses — only run scoped `flutter analyze <path>` until Task 13.
