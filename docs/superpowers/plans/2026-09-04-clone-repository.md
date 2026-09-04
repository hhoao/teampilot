# Clone Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Clone Repository…" flow reachable from the title-bar ⋯ workspace switcher menu that runs `git clone` on local/WSL/SSH targets as a cancellable background progress activity, then lets the user create a new workspace from the clone or add it to an existing workspace.

**Architecture:** A pure `RepoCloneService` resolves the target and runs `git clone --progress` via `ProcessRunExecutor` (which already handles local spawn, `wsl.exe` wrapping, and SSH exec). A `RepoCloneCubit` maps each clone onto the existing `ProgressActivityCubit` + notification-history infra. A dialog collects URL/target/destination; a completion dialog offers new-vs-add workspace wiring through `ChatCubit`.

**Tech Stack:** Flutter (`client/`, package `teampilot`), flutter_bloc, shared_ui `Tp*` primitives, path package, existing host/run services.

**Spec:** `docs/superpowers/specs/2026-09-04-clone-repository-design.md`

## Global Constraints

- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` **only** (never hand-edit `app_localizations*.dart` — they are generated).
- No `Process.run` or raw paths in UI (`pages/`); all execution lives in `services/`.
- State is `flutter_bloc` only. Logging via `AppLogger`; user-facing errors via l10n strings.
- New generic widgets go in `client/packages/shared_ui` as `Tp*`; the dialogs here are product UI and belong in `pages/home_workspace/`.
- Constructor-inject subprocess/filesystem dependencies for testability (project convention).
- File size soft limits: dialogs ~400 lines, cubits ~500, services ~600 — split if exceeded.
- Commits end with `Co-Authored-By: Claude <noreply@anthropic.com>`.

---

### Task 1: `ProgressActivityKind.repoClone` + tile icon + l10n strings

**Files:**
- Modify: `client/lib/models/progress_activity.dart` (enum, ~line 5)
- Modify: `client/lib/widgets/notification/progress_activity_tile.dart` (icon map, ~line 9)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

**Interfaces:**
- Produces: enum value `ProgressActivityKind.repoClone` used by Tasks 3–6; all l10n keys listed below used by Tasks 4–6.

**l10n keys to add** (both arb files; copy the English value verbatim into `app_en.arb`, the Chinese value into `app_zh.arb`):

```json
"cloneRepositoryMenu": "Clone Repository…",
"cloneRepositorySubmit": "Clone",
"cloneRepositoryTitle": "Clone Repository",
"cloneRepositoryUrlLabel": "Repository URL",
"cloneRepositoryUrlHint": "https://github.com/owner/repo.git",
"cloneRepositoryUrlInvalid": "Enter a valid git URL (https://, git@, git://, ssh://)",
"cloneRepositoryTargetLabel": "Clone to target",
"cloneRepositoryParentDirLabel": "Clone into folder",
"cloneRepositoryParentDirRequired": "Choose a destination folder",
"cloneRepositoryDirNameLabel": "Folder name",
"cloneRepositoryDirNameRequired": "Enter a folder name",
"cloneRepositoryDestExists": "Folder already exists and is not empty",
"cloneRepositoryGitMissing": "git was not found on the selected target machine",
"cloneRepositoryStarted": "Cloning {url} started",
"cloneRepositoryProgressTitle": "Cloning {repo}",
"cloneRepositorySucceeded": "Cloned {repo}",
"cloneRepositoryFailed": "Clone failed: {repo}",
"cloneRepositoryCancelled": "Clone cancelled: {repo}",
"cloneRepositoryCompletedTitle": "Clone complete",
"cloneRepositoryCompletedBody": "{path} is ready.",
"cloneRepositoryCreateWorkspace": "New workspace",
"cloneRepositoryAddToWorkspace": "Add to existing workspace…",
"cloneRepositoryChooseWorkspace": "Choose a workspace",
"cloneRepositoryAddToExistingSucceeded": "Added {repo} to workspace {workspace}"
```

`app_zh.arb` values:

```json
"cloneRepositoryMenu": "克隆仓库…",
"cloneRepositorySubmit": "克隆",
"cloneRepositoryTitle": "克隆仓库",
"cloneRepositoryUrlLabel": "仓库 URL",
"cloneRepositoryUrlHint": "https://github.com/owner/repo.git",
"cloneRepositoryUrlInvalid": "请输入有效的 git URL（https://、git@、git://、ssh://）",
"cloneRepositoryTargetLabel": "克隆到目标",
"cloneRepositoryParentDirLabel": "克隆到文件夹",
"cloneRepositoryParentDirRequired": "请选择目标文件夹",
"cloneRepositoryDirNameLabel": "文件夹名称",
"cloneRepositoryDirNameRequired": "请输入文件夹名称",
"cloneRepositoryDestExists": "文件夹已存在且不为空",
"cloneRepositoryGitMissing": "所选目标机器上未找到 git",
"cloneRepositoryStarted": "已开始克隆 {url}",
"cloneRepositoryProgressTitle": "正在克隆 {repo}",
"cloneRepositorySucceeded": "已克隆 {repo}",
"cloneRepositoryFailed": "克隆失败：{repo}",
"cloneRepositoryCancelled": "已取消克隆：{repo}",
"cloneRepositoryCompletedTitle": "克隆完成",
"cloneRepositoryCompletedBody": "{path} 已就绪。",
"cloneRepositoryCreateWorkspace": "新建工作区",
"cloneRepositoryAddToWorkspace": "加入现有工作区…",
"cloneRepositoryChooseWorkspace": "选择工作区",
"cloneRepositoryAddToExistingSucceeded": "已将 {repo} 加入工作区 {workspace}"
```

For keys with `{placeholders}` add a `"@key"` metadata entry in **both** arb files (required for codegen), e.g.:

```json
"@cloneRepositoryStarted": { "placeholders": { "url": {} } },
"@cloneRepositoryProgressTitle": { "placeholders": { "repo": {} } },
"@cloneRepositorySucceeded": { "placeholders": { "repo": {} } },
"@cloneRepositoryFailed": { "placeholders": { "repo": {} } },
"@cloneRepositoryCancelled": { "placeholders": { "repo": {} } },
"@cloneRepositoryCompletedBody": { "placeholders": { "path": {} } },
"@cloneRepositoryAddToExistingSucceeded": { "placeholders": { "repo": {}, "workspace": {} } }
```

- [ ] **Step 1: Add the enum value and tile icon**

In `client/lib/models/progress_activity.dart`, add `repoClone` to `ProgressActivityKind`:

```dart
enum ProgressActivityKind {
  fileTreeImport,
  appUpdate,
  hubClone,
  packAcquire,
  cliProvision,
  repoClone,
}
```

In `client/lib/widgets/notification/progress_activity_tile.dart`, extend the icon map (follow the existing switch/expression style in that file):

```dart
ProgressActivityKind.repoClone => Icons.cloud_download_outlined,
```

- [ ] **Step 2: Add l10n keys to both arb files**

Append the keys and `@`-metadata above to `client/lib/l10n/app_en.arb` and the Chinese values to `client/lib/l10n/app_zh.arb`. Run codegen:

```bash
cd client && flutter gen-l10n
```

- [ ] **Step 3: Run analyze to verify codegen**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add client/lib/models/progress_activity.dart client/lib/widgets/notification/progress_activity_tile.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart
git commit -m "feat(clone): add repoClone activity kind and l10n strings"
```

---

### Task 2: `RepoCloneService` (target resolution, git discovery, clone execution, progress parsing)

**Files:**
- Create: `client/lib/services/workspace/repo_clone_service.dart`
- Test: `client/test/services/workspace/repo_clone_service_test.dart`

**Interfaces:**
- Consumes (all existing):
  - `RuntimeTarget` / `RuntimeKind` from `client/lib/models/runtime_target.dart` (fields `id`, `kind`, `sshProfileId`, `wslDistro`)
  - `RunTargetResolver` + `RunTargetPlan` from `client/lib/services/run/run_target_resolver.dart`; `resolver.resolve({required WorkspaceFolder owner, String? cwd})`
  - `ProcessRunExecutor` from `client/lib/services/run/process_run_executor.dart`; `start({required String sessionId, required String command, required List<String> args, required RunTargetPlan plan, required void Function(ProcessRunOutput output) onOutput})` → `ProcessRunResult` (`exitCode: Future<int>`, `stop()`)
  - `HostOneShotRunner` from `client/lib/services/host/host_one_shot_runner.dart`; `run(HostRunRequest)` → `HostRunResult` (`exitCode`, `stdout`, `stderr`)
  - `WorkspaceFolder` from `client/lib/models/workspace_folder.dart` (`path`, `targetId`)
  - `Filesystem` from `client/lib/services/io/filesystem.dart` (`stat(path)` → `FsStat` with `.exists`, `.isDirectory`)
- Produces (used by Tasks 3, 5, 6):

```dart
class RepoCloneRequest {
  const RepoCloneRequest({
    required this.url,
    required this.targetId,
    required this.parentDir,
    required this.dirName,
  });
  final String url;      // validated https://, git@, git://, ssh://
  final String targetId; // canonical id (local / wsl:<distro> / ssh:<profile>)
  final String parentDir;// absolute path on the target machine
  final String dirName;  // clone folder name under parentDir
}

class RepoCloneProgress {
  const RepoCloneProgress({this.fraction, this.subtitle});
  final double? fraction;   // null = indeterminate
  final String? subtitle;   // latest git progress line
}

enum RepoCloneOutcome { succeeded, failed, cancelled }

class RepoCloneResult {
  const RepoCloneResult({
    required this.outcome,
    required this.destPath, // absolute path on target
    this.errorDetail,      // git stderr tail on failure
  });
  final RepoCloneOutcome outcome;
  final String destPath;
  final String? errorDetail;
}

abstract interface class RepoCloneHostRunner {
  /// Verify git exists: `git --version`.
  Future<HostRunResult> checkGit(RepoCloneRequest request);
  /// Target-machine filesystem for destination checks + partial cleanup.
  Future<Filesystem> filesystemFor(String targetId);
}

class RepoCloneService {
  RepoCloneService({
    RunTargetResolver? resolver,
    ProcessRunExecutor? executor,
    RepoCloneHostRunner? hostRunner,
    Duration pollInterval = const Duration(milliseconds: 50),
  });
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  });
}

/// Pure helpers (exported for tests + used by the dialog in Task 5):
String repoCloneDirNameFromUrl(String url);       // 'repo' from .../repo.git
bool repoCloneUrlLooksValid(String url);          // prefix + non-empty name check
double? repoCloneParseFraction(String line);      // 'Receiving objects:  45% ...' → 0.45
```

**Design notes for the implementer:**

- `clone()` flow:
  1. `destPath` = parentDir joined with dirName using the plan's path style: build `owner = WorkspaceFolder(path: request.parentDir, targetId: request.targetId)`, `plan = resolver.resolve(owner: owner)`, then `destPath = plan.pathContext.join(parentDir, dirName)` — use the `Filesystem.pathContext` from `hostRunner.filesystemFor(targetId)` instead if simpler; both give target-native joins. **Never** hardcode `/`.
  2. Pre-check: `fs.stat(destPath)` — if `exists && isDirectory`, list is unnecessary; treat "exists at all" as an error (message key `cloneRepositoryDestExists`, surfaced by the caller; the service returns `outcome: failed` with `errorDetail` set to a stable marker string `dest-exists`).
  3. `checkGit` — non-zero exit → `failed` with marker `git-missing`.
  4. `executor.start(sessionId: 'repo-clone', command: 'git', args: ['clone', '--progress', '--', request.url, request.dirName], plan: plan, onOutput: ...)`; `workingDirectory` comes from the plan (parentDir) because `resolve(owner: owner)` uses `owner.path` as cwd.
  5. On output with `category == 'stderr'`: split on `\r` and `\n`; for each line call `repoCloneParseFraction`; emit `RepoCloneProgress(fraction: parsed ?? lastFraction, subtitle: lastNonEmptyLine)`; accumulate the last ~40 stderr/stdout lines into a ring buffer for `errorDetail`.
  6. Exit: `exitCode == 0` → `succeeded`; non-zero → `failed` with the ring-buffer tail. If `isCancelled()` flips true (checked in the output callback and after exit), call `result.stop()`, wait for exit, return `cancelled`.
- `repoCloneUrlLooksValid`: true when trimmed url starts with `https://`, `http://`, `git@`, `git://`, or `ssh://` **and** `repoCloneDirNameFromUrl` returns a non-empty name.
- `repoCloneDirNameFromUrl`: strip trailing `/`, take the last path segment, strip a trailing `.git`, return `''` if empty or the result contains no word characters. Handle scp-style `git@host:owner/repo.git` by also splitting on `:`.
- `pollInterval` is unused plumbing today — omit it; only add it if the executor needs polling (it doesn't — streams drive progress). **Do not include `pollInterval` in the constructor.**
- Log diagnostics with `appLogger.d('[RepoClone] ...')` (import `../../utils/logging/logger.dart`).

- [ ] **Step 1: Write the failing test**

Create `client/test/services/workspace/repo_clone_service_test.dart`. Use a fake `ProcessRunExecutor` is impossible (it's a concrete class) — instead inject its constructor seams: `ProcessSpawner` and `SshProcessSpawner`. Pattern:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/workspace/repo_clone_service.dart';

class _FakeHandle implements ProcessRunHandle {
  _FakeHandle(this.exit, {this.stderrLines = const []});
  final int exit;
  final List<String> stderrLines;
  final _stdoutCtrl = StreamController<List<int>>();
  final _stderrCtrl = StreamController<List<int>>(onListen: () {
    for (final line in stderrLines) {
      _stderrCtrl.add(line.codeUnits);
    }
    _stderrCtrl.close();
  });
  var killed = false;

  @override
  Future<int> get exitCode async => exit;
  @override
  Stream<List<int>> get stdout => _stdoutCtrl.stream;
  @override
  Stream<List<int>> get stderr => _stderrCtrl.stream;
  @override
  void kill() => killed = true;
}

class _RecordingSpawner {
  final calls = <({String executable, List<String> arguments})>[];
  ProcessSpawner get spawner => ({
    required executable,
    required arguments,
    required workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    bool includeParentEnvironment = true,
  }) async {
    calls.add((executable: executable, arguments: arguments));
    return pendingHandle;
  };
  _FakeHandle pendingHandle = _FakeHandle(0);
}

class _FakeHostRunner implements RepoCloneHostRunner {
  _FakeHostRunner({this.gitExit = 0, FsStat Function(String)? stat});
  int gitExit;
  final statResults = <String, FsStat>{};
  final deleted = <String>[];

  @override
  Future<HostRunResult> checkGit(RepoCloneRequest request) async =>
      HostRunResult(exitCode: gitExit, stdout: 'git version 2.43.0', stderr: '');

  @override
  Future<Filesystem> filesystemFor(String targetId) async => _FakeFs(this);
}

class _FakeFs implements Filesystem {
  _FakeFs(this.owner);
  final _FakeHostRunner owner;
  final files = <String>{};
  final dirs = <String>{};

  @override
  p.Context get pathContext => p.posixContext(contextStyle); // see note below

  @override
  Future<FsStat> stat(String path) async => FsStat(
    kind: dirs.contains(path)
        ? FsEntityKind.directory
        : files.contains(path)
        ? FsEntityKind.file
        : FsEntityKind.notFound,
  );

  @override
  Future<void> removeRecursive(String path) async {
    owner.deleted.add(path);
    dirs.remove(path);
  }

  // ... implement remaining abstract members with throws/empty stubs.
}
```

Note: `Filesystem` is a large interface; stub unimplemented members with `throw UnimplementedError()`. Check `client/lib/services/io/filesystem.dart` for the full member list and copy the exact signatures; `pathContext` is `p.Context` (from `package:path`) — return `p.Context(style: p.Style.posix)`.

Tests to write (each a `test(...)` in `main()`):

```dart
test('dirNameFromUrl strips .git and trailing slash', () {
  expect(repoCloneDirNameFromUrl('https://github.com/owner/repo.git'), 'repo');
  expect(repoCloneDirNameFromUrl('https://github.com/owner/repo/'), 'repo');
  expect(repoCloneDirNameFromUrl('git@host:owner/repo.git'), 'repo');
  expect(repoCloneDirNameFromUrl('ssh://git@host/owner/repo.git'), 'repo');
});

test('urlLooksValid accepts known schemes, rejects junk', () {
  expect(repoCloneUrlLooksValid('https://github.com/o/r.git'), isTrue);
  expect(repoCloneUrlLooksValid('git@github.com:o/r.git'), isTrue);
  expect(repoCloneUrlLooksValid('not a url'), isFalse);
  expect(repoCloneUrlLooksValid(''), isFalse);
});

test('parseFraction reads Receiving objects percent', () {
  expect(
    repoCloneParseFraction('Receiving objects:  45% (56/123), 3.2 MiB'),
    0.45,
  );
  expect(repoCloneParseFraction('Resolving deltas: 100% (12/12)'), 1.0);
  expect(repoCloneParseFraction('remote: Counting objects: 3, done.'), isNull);
});

test('clone builds git clone --progress with local plan and succeeds', () async {
  final spawner = _RecordingSpawner();
  final service = RepoCloneService(
    executor: ProcessRunExecutor(spawner: spawner.spawner),
    hostRunner: _FakeHostRunner(),
  );
  final result = await service.clone(
    RepoCloneRequest(
      url: 'https://github.com/o/r.git',
      targetId: 'local',
      parentDir: '/home/me/src',
      dirName: 'r',
    ),
    onProgress: (_) {},
    isCancelled: () => false,
  );
  expect(result.outcome, RepoCloneOutcome.succeeded);
  expect(result.destPath, '/home/me/src/r');
  expect(spawner.calls.single.executable, 'git');
  expect(
    spawner.calls.single.arguments,
    ['clone', '--progress', '--', 'https://github.com/o/r.git', 'r'],
  );
});

test('clone reports fraction and subtitle from stderr', () async {
  final spawner = _RecordingSpawner()
    ..pendingHandle = _FakeHandle(
      0,
      stderrLines: ['remote: Counting objects: 3, done.',
        'Receiving objects:  45% (56/123), 3.2 MiB | 1.1 MiB/s'],
    );
  final progress = <RepoCloneProgress>[];
  final service = RepoCloneService(
    executor: ProcessRunExecutor(spawner: spawner.spawner),
    hostRunner: _FakeHostRunner(),
  );
  await service.clone(
    RepoCloneRequest(
      url: 'https://github.com/o/r.git',
      targetId: 'local',
      parentDir: '/src', dirName: 'r'),
    onProgress: progress.add,
    isCancelled: () => false,
  );
  expect(progress.any((p) => p.fraction == 0.45), isTrue);
  expect(progress.any((p) => p.subtitle?.contains('Receiving') ?? false), isTrue);
});

test('clone fails when destination exists', () async {
  final host = _FakeHostRunner();
  final service = RepoCloneService(
    executor: ProcessRunExecutor(spawner: _RecordingSpawner().spawner),
    hostRunner: host,
  );
  // seed existing dir via host.filesystemFor → need a stat-hit: make the fake
  // expose dirs; add '/src/r' to the fake fs dirs before cloning.
  final result = await service.clone(
    RepoCloneRequest(
      url: 'https://github.com/o/r.git',
      targetId: 'local', parentDir: '/src', dirName: 'r'),
    onProgress: (_) {}, isCancelled: () => false,
  );
  expect(result.outcome, RepoCloneOutcome.failed);
  expect(result.errorDetail, 'dest-exists');
});

test('clone fails fast when git is missing on target', () async {
  final spawner = _RecordingSpawner();
  final service = RepoCloneService(
    executor: ProcessRunExecutor(spawner: spawner.spawner),
    hostRunner: _FakeHostRunner(gitExit: 127),
  );
  final result = await service.clone(
    RepoCloneRequest(
      url: 'https://github.com/o/r.git',
      targetId: 'local', parentDir: '/src', dirName: 'r'),
    onProgress: (_) {}, isCancelled: () => false,
  );
  expect(result.outcome, RepoCloneOutcome.failed);
  expect(result.errorDetail, 'git-missing');
  expect(spawner.calls, isEmpty);
});

test('clone failure carries stderr tail', () async {
  final spawner = _RecordingSpawner()
    ..pendingHandle = _FakeHandle(
      128,
      stderrLines: ['fatal: could not read Username for https://github.com'],
    );
  final service = RepoCloneService(
    executor: ProcessRunExecutor(spawner: spawner.spawner),
    hostRunner: _FakeHostRunner(),
  );
  final result = await service.clone(
    RepoCloneRequest(
      url: 'https://github.com/o/r.git',
      targetId: 'local', parentDir: '/src', dirName: 'r'),
    onProgress: (_) {}, isCancelled: () => false,
  );
  expect(result.outcome, RepoCloneOutcome.failed);
  expect(result.errorDetail, contains('could not read Username'));
});

test('cancelled clone kills the process and returns cancelled', () async {
  final handle = _FakeHandle(130, stderrLines: []);
  final spawner = _RecordingSpawner()..pendingHandle = handle;
  final service = RepoCloneService(
    executor: ProcessRunExecutor(spawner: spawner.spawner),
    hostRunner: _FakeHostRunner(),
  );
  var cancelled = false;
  final result = await service.clone(
    RepoCloneRequest(
      url: 'https://github.com/o/r.git',
      targetId: 'local', parentDir: '/src', dirName: 'r'),
    onProgress: (_) {},
    isCancelled: () => cancelled,
  );
  // flip cancellation once the process has started
  // (simplest: set cancelled = true in onProgress after first event, or
  // before the await — assert outcome + kill flag)
  cancelled = true; // if set before await, expect cancelled
  expect(result.outcome, anyOf(RepoCloneOutcome.cancelled, RepoCloneOutcome.succeeded));
  expect(handle.killed, isTrue);
});
```

(The cancel test is written loosely on purpose: pick the deterministic variant — set `cancelled = true` before the first output event (e.g. via a flag flipped inside `onProgress`) and assert `outcome == cancelled` and `handle.killed == true`.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/services/workspace/repo_clone_service_test.dart`
Expected: FAIL — `repo_clone_service.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/workspace/repo_clone_service.dart` implementing exactly the interfaces above. Keep it under ~300 lines: the parsing helpers as top-level functions, `RepoCloneHostRunner` as the seam for git discovery + fs access (production implementation `DefaultRepoCloneHostRunner` in the same file: `LocalHostOneShotRunner()`/`WslHostOneShotRunner(distro: …)`/`RemoteHostOneShotRunner(execShell: …)` selected from the resolved `RuntimeTarget.kind` the same way `hostOneShotRunnerForContext` does, and `filesystemFor` delegating to a `Future<RuntimeContext> Function(RuntimeTarget)` injected constructor param — **do not** import `AppStorage`).

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/services/workspace/repo_clone_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/workspace/repo_clone_service.dart client/test/services/workspace/repo_clone_service_test.dart
git commit -m "feat(clone): add RepoCloneService with cross-target git clone execution"
```

---

### Task 3: `RepoCloneCubit` (task state, progress activity, cancel, cleanup)

**Files:**
- Create: `client/lib/cubits/repo_clone_cubit.dart`
- Test: `client/test/cubits/repo_clone_cubit_test.dart`

**Interfaces:**
- Consumes: `RepoCloneService` + types from Task 2; `ProgressActivityCubit` (`start(activity, {onCancelRequested})`, `update(id, {fraction, subtitle, phase, errorMessage})`, `complete(id, {required outcome, errorMessage, historyTitle, historyMessage})`); `ProgressActivity`/`ProgressActivityKind.repoClone`/`ProgressActivityPhase` from Task 1.
- Produces (used by Tasks 4–6):

```dart
enum RepoCloneTaskPhase { cloning, succeeded, failed, cancelled }

class RepoCloneTask extends Equatable {
  const RepoCloneTask({
    required this.id,
    required this.url,
    required this.targetId,
    required this.destPath,
    required this.dirName,
    required this.phase,
    this.errorDetail,
    this.createdAt,
  });
  final String id;          // doubles as ProgressActivity id
  final String url;
  final String targetId;
  final String destPath;   // absolute on target
  final String dirName;
  final RepoCloneTaskPhase phase;
  final String? errorDetail;
  final DateTime? createdAt;
  // copyWith(…) for phase/errorDetail
}

class RepoCloneState extends Equatable {
  const RepoCloneState({this.tasks = const [], this.pendingChoice = const []});
  final List<RepoCloneTask> tasks;
  final List<RepoCloneTask> pendingChoice; // succeeded, awaiting new-vs-add
}

class RepoCloneCubit extends Cubit<RepoCloneState> {
  RepoCloneCubit({
    required ProgressActivityCubit progressActivityCubit,
    RepoCloneService? service,          // inject a fake in tests
    String Function()? uuid,
  });
  void startClone(RepoCloneRequest request);   // fire-and-forget; errors land in state
  void dismissChoice(String taskId);           // remove from pendingChoice
  RepoCloneTask? taskById(String taskId);
}
```

**Behavior:**

- `startClone`:
  1. `id = uuid() ?? const Uuid().v4()`, `task = RepoCloneTask(phase: cloning, createdAt: DateTime.now(), …)`.
  2. `progressActivityCubit.start(ProgressActivity(id: id, kind: ProgressActivityKind.repoClone, title: l10n-free repo string 'repo-name' (the cubit has no context — pass a `String Function(String repoLabel)` or store raw `dirName`; UI layers localize), phase: running, cancellable: true, createdAt/updatedAt: now), onCancelRequested: () { _cancelFlags[id] = true; })`. The service's `isCancelled` closure reads `_cancelFlags[id] ?? false`.
  3. `unawaited(_run(task, request))` — emits updated state immediately (task list add).
- `_run`:
  - `service.clone(request, onProgress: (p) => progressActivityCubit.update(id, fraction: p.fraction, subtitle: p.subtitle), isCancelled: () => _cancelFlags[id] ?? false)`.
  - Outcome mapping: `succeeded` → task phase succeeded + append to `pendingChoice`; `failed` → phase failed (map marker `dest-exists` / `git-missing` to `errorDetail` unchanged — the UI in Task 4/5 maps markers to l10n); `cancelled` → phase cancelled.
  - On `failed` **after the clone started** (not the pre-checks): best-effort `removeRecursive(destPath)` via `hostRunner.filesystemFor(targetId)` (add a `Future<Filesystem> Function(String targetId)` seam to the cubit, or expose `service.hostRunner`; simplest: inject `Future<Filesystem> Function(String targetId)? cleanupFs` — on exception log via `appLogger.d` and continue). Do the same on `cancelled`.
  - Finally call `progressActivityCubit.complete(id, outcome: …, errorMessage: …)`; `outcome` maps `succeeded→ProgressActivityPhase.succeeded`, `failed→failed`, `cancelled→cancelled`. Provide `historyTitle`/`historyMessage` as **raw repo-name strings** (the notification recorder stores plain strings; UI-localized strings are not available in a cubit — use `'Cloned <dirName>'`-style English defaults, consistent with how other cubits pass generic messages; if existing code shows cubits receiving l10n via injection, follow that pattern instead).
  - Remove `_cancelFlags[id]` when finished.
- `dismissChoice(taskId)` removes the task from `pendingChoice` only.
- All emissions copy lists immutably (Equatable props = `[tasks, pendingChoice]`).

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/repo_clone_cubit_test.dart`. Reuse the `_FakeNotificationRecorder` pattern from `client/test/cubits/progress_activity_cubit_test.dart` for the `ProgressActivityCubit`. Fake the service:

```dart
class _FakeService implements RepoCloneService {
  _FakeService();
  RepoCloneRequest? lastRequest;
  void Function(RepoCloneProgress progress)? onProgress;
  bool Function()? isCancelled;

  RepoCloneResult result = RepoCloneResult(
    outcome: RepoCloneOutcome.succeeded, destPath: '/src/r');

  @override
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    lastRequest = request;
    this.onProgress = onProgress;
    this.isCancelled = isCancelled;
    return result;
  }
}
```

(`RepoCloneService` is concrete — make `clone` overridable by marking it non-final or, cleaner, extract `abstract interface class RepoCloneGateway` with the single `clone` method and have both `RepoCloneService` and the fake implement it; the cubit takes `RepoCloneGateway?`. Do the gateway extraction in this task; it is the seam Task 4 also uses.)

Tests:

```dart
test('startClone registers a cancellable repoClone activity', () async {
  final recorder = _FakeNotificationRecorder();
  final progress = ProgressActivityCubit(historyRecorder: recorder);
  addTearDown(progress.close);
  final fake = _FakeService();
  final cubit = RepoCloneCubit(progressActivityCubit: progress, service: fake, uuid: () => 'id-1');
  addTearDown(cubit.close);

  cubit.startClone(RepoCloneRequest(
    url: 'https://github.com/o/r.git', targetId: 'local',
    parentDir: '/src', dirName: 'r'));

  expect(cubit.state.tasks.single.phase, RepoCloneTaskPhase.cloning);
  final activity = progress.state.activities.single;
  expect(activity.kind, ProgressActivityKind.repoClone);
  expect(activity.id, 'id-1');
  expect(activity.cancellable, isTrue);
});

test('succeeded clone lands in pendingChoice and completes the activity',
    () async {
  // same setup; await a pump/event-loop turn (await Future.delayed(Duration.zero))
  // until state.tasks.single.phase == succeeded
  expect(cubit.state.pendingChoice.single.id, 'id-1');
  expect(progress.state.activities, isEmpty); // completed removes it
  expect(recorder.records.single.variant, TpToastVariant.success);
});

test('failed clone sets errorDetail and completes failed', () async {
  fake.result = RepoCloneResult(
    outcome: RepoCloneOutcome.failed, destPath: '/src/r',
    errorDetail: 'fatal: could not read Username');
  // ... start, await; expect phase failed, errorDetail preserved,
  // recorder variant error, pendingChoice empty
});

test('dismissChoice removes only from pendingChoice', () async {
  // succeeded clone, then cubit.dismissChoice('id-1');
  // expect pendingChoice empty, tasks still contains the task
});

test('progress events forward to the activity', () async {
  // start, then fake.onProgress!(RepoCloneProgress(fraction: 0.45, subtitle: 'Receiving...'));
  // expect progress.state.activities.single.fraction, 0.45
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/cubits/repo_clone_cubit_test.dart`
Expected: FAIL — `repo_clone_cubit.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `client/lib/cubits/repo_clone_cubit.dart` per the interfaces + behavior above (with the `RepoCloneGateway` extraction). `uuid` defaults to `const Uuid().v4`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/cubits/repo_clone_cubit_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze + commit**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
git add client/lib/cubits/repo_clone_cubit.dart client/lib/services/workspace/repo_clone_service.dart client/test/cubits/repo_clone_cubit_test.dart
git commit -m "feat(clone): add RepoCloneCubit mapping clones onto progress activities"
```

---

### Task 4: DI wiring (`AppShell` + `main.dart`)

**Files:**
- Modify: `client/lib/app/app_shell.dart` (AppShell class field + constructor ~line 374–486; construction site ~line 2508; cubit creation near `progressActivityCubit` ~line 1311)
- Modify: `client/lib/main.dart` (shutdown-scope field + provider list ~lines 255–300 and 720–740)

**Interfaces:**
- Consumes: `RepoCloneCubit` (Task 3), `RepoCloneService` + `DefaultRepoCloneHostRunner` (Task 2), `RuntimeContextRegistry` (~line 846 in app_shell.dart), `sshProfileRepo` / `sshClientFactory` (fields on the shell builder scope in app_shell.dart), `RunTargetResolver`.
- Produces: `BlocProvider.value(value: shell.repoCloneCubit)` in `main.dart` so `context.read<RepoCloneCubit>()` works in `pages/` (Tasks 5–6).

- [ ] **Step 1: Construct the cubit in app_shell.dart**

Right after the `progressActivityCubit` creation (~line 1311), add:

```dart
final repoCloneSshSpawner = SshProcessSpawner? Function? — see below
```

Concretely, model the SSH spawner on `workspace_run_platform_factory.dart:157-175` (that file's `_sshSpawner` resolves the profile via `sshProfileRepository.findById` then `sshClientFactory.clientForStorage(profile)` then `client.execute(shellCommand)` wrapped in `SshProcessRunHandle`). Because app_shell already has `sshProfileRepo` and `sshClientFactory` in scope:

```dart
Future<ProcessRunHandle> repoCloneSshSpawner({
  required String sshProfileId,
  required String shellCommand,
}) async {
  final profile = await sshProfileRepo.findById(sshProfileId);
  if (profile == null) {
    throw StateError('SSH profile not found for this run target');
  }
  final client = await sshClientFactory.clientForStorage(profile);
  final session = await client.execute(shellCommand);
  return SshProcessRunHandle(session);
}

final repoCloneCubit = RepoCloneCubit(
  progressActivityCubit: progressActivityCubit,
  service: RepoCloneService(
    executor: ProcessRunExecutor(sshSpawner: repoCloneSshSpawner),
    hostRunner: DefaultRepoCloneHostRunner(
      resolveContext: runtimeContextRegistry.forTarget,
      sshSpawner: repoCloneSshSpawner,
    ),
  ),
);
```

`DefaultRepoCloneHostRunner` (Task 2) takes `resolveContext: Future<RuntimeContext> Function(RuntimeTarget)` and `sshSpawner`; its `checkGit` picks `LocalHostOneShotRunner()` / `WslHostOneShotRunner(distro: target.wslDistro)` / `RemoteHostOneShotRunner(execShell: ...)` from the resolved target kind — for the remote case shell-run `git --version` via the same spawner mechanism (`execShell` = `sshSpawner` adapted: `Future<HostRunResult> Function(String command)` built from `sshClientFactory` — reuse `RemoteFileStore.execShell` pattern or run through `RemoteHostOneShotRunner(execShell: …)`; if wiring the SSH one-shot path inline is awkward, give `DefaultRepoCloneHostRunner` a `SshProcessSpawner` and construct `HostRunRequest`-shaped `HostShellArgv.command(...)` manually). Verify exact `RunTargetResolver` default construction: `RunTargetResolver()` (home target defaults to local) — pass `RunTargetResolver(homeTarget: defaultTargetResolver())` if that helper exists in scope, else leave default.

- [ ] **Step 2: Add the field to AppShell and pass it in**

In `client/lib/app/app_shell.dart`: add `required this.repoCloneCubit,` + `final RepoCloneCubit repoCloneCubit;` to the `AppShell` class (next to `progressActivityCubit`, ~lines 388/486), and pass `repoCloneCubit: repoCloneCubit,` at the `AppShell(...)` construction (~line 2523, next to `progressActivityCubit:`).

- [ ] **Step 3: Provide it in main.dart**

In `client/lib/main.dart`: add `required this.repoCloneCubit,` / `final RepoCloneCubit repoCloneCubit;` to `_AppShutdownScope` (alongside `progressActivityCubit`, ~lines 269/289), pass it where `_AppShutdownScope` is built (~line 581 uses `shell.progressActivityCubit` — add `shell.repoCloneCubit`), and add `BlocProvider.value(value: shell.repoCloneCubit),` next to the `progressActivityCubit` provider (~line 726). Do **not** close it in the shutdown scope (it owns no streams; `ProgressActivityCubit` is the lifecycle owner) — unless the shell's dispose pattern requires it; check how `_AppShutdownScope` disposes `progressActivityCubit` (it does via `widget.progressActivityCubit.close()` at ~line 315) and mirror that line for consistency.

- [ ] **Step 4: Run analyze + full tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(clone): wire RepoCloneCubit into app DI and provider tree"
```

---

### Task 5: `CloneRepositoryDialog` + switcher-menu entry

**Files:**
- Create: `client/lib/pages/home_workspace/clone_repository_dialog.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_switcher_menu.dart` (new `onCloneRepository` callback + menu item)
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart` (`HomeTitleBar`/`HomeWorkspaceSwitcherMenu` plumbing: fields at ~lines 200/232, both construction sites at ~lines 344/414)
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart` (`_HomeShellTitleBar` pass-through + `onCloneRepository` handler near `onCreateWorkspace` at ~line 572)
- Test: `client/test/pages/home_workspace/clone_repository_dialog_test.dart`, extend `client/test/pages/home_workspace/home_workspace_switcher_menu_test.dart`

**Interfaces:**
- Consumes: `context.read<RepoCloneCubit>()` (Task 4), `context.read<HomeTargetController>()` (`.listSelectable()`, `.current`), `pickWorkspaceDirectoryPath(context, targetId: …)` from `client/lib/utils/workspace/workspace_path_picker.dart`, `WorkspaceCreateNameField` from `client/lib/widgets/workspace_create_directory_picker.dart`, `TpDialog`/`TpForm`/`TpFormField`/`TpButton` from shared_ui, `repoCloneUrlLooksValid` / `repoCloneDirNameFromUrl` from Task 2, l10n keys from Task 1.
- Produces:

```dart
Future<void> showCloneRepositoryDialog(BuildContext context);
```

**Dialog structure** (model it on `HomeNewWorkspaceDialog` in `home_new_workspace_dialog.dart` — same `TpDialog` + `TpForm` + `WorkspaceCreateNameField` skeleton):

- URL field: `TpInput`/ TextFormField; validator → `repoCloneUrlLooksValid(url) ? null : l10n.cloneRepositoryUrlInvalid`; on valid URL, if the dirName field is untouched, autofill `_dirNameController.text = repoCloneDirNameFromUrl(url)`.
- Target selector: dropdown fed by `context.read<HomeTargetController>().listSelectable()` (follow how `WorkspaceCreateDirectoryPicker` builds its target row — `WorkspaceFolder.localTargetId` default, `WorkTargetCanonicalizer.defaultFolderTargetId(homeController.current)` as initial value, same as `HomeNewWorkspaceDialog.didChangeDependencies`).
- "Clone into folder" row: button opening `pickWorkspaceDirectoryPath(context, targetId: _targetId)`; shows the picked path, validates non-empty (`cloneRepositoryParentDirRequired`).
- Dir name field: `WorkspaceCreateNameField(controller: _dirNameController, hint: derived-from-url, onSubmitted: submit)`; validator non-empty.
- Submit ("Clone" FilledButton + cancel TextButton): pops `null`? No — pops the request **after validation**:

```dart
Navigator.of(context).pop(
  RepoCloneRequest(
    url: _urlController.text.trim(),
    targetId: _targetId,
    parentDir: _parentDir,
    dirName: _dirNameController.text.trim(),
  ),
);
```

`showCloneRepositoryDialog` then calls `context.read<RepoCloneCubit>().startClone(request)` and shows an info toast via the shared_ui toast helper used elsewhere in `pages/` (search for the existing `showTpToast`/`TpToastWrapper` call pattern — e.g. in `home_workspace_shell.dart` — and copy it) with `l10n.cloneRepositoryStarted(url)`.

**Menu entry** in `HomeWorkspaceSwitcherMenu`: add `this.onCloneRepository` (`VoidCallback?`), and a `TpActionMenuItem(icon: Icons.download_outlined, label: l10n.cloneRepositoryMenu, menuController: _menuController, onTap: _onCloneTap)` directly below the existing "New Workspace" item (`_onCloneTap` mirrors `_onCreateTap`: hide popover, post-frame invoke callback). Plumb the same callback through `HomeTitleBar` (both `HomeWorkspaceSwitcherMenu` construction sites) and `_HomeShellTitleBar`/`HomeShellState` — handler next to `onCreateWorkspace` in `home_workspace_shell.dart`:

```dart
onCloneRepository: () {
  unawaited(showCloneRepositoryDialog(context));
},
```

- [ ] **Step 1: Write the failing widget tests**

`client/test/pages/home_workspace/clone_repository_dialog_test.dart` — use the `_wrap` harness pattern from `home_workspace_switcher_menu_test.dart` (TpTheme + MaterialApp with l10n delegates) **plus** the cubit/controller providers the dialog reads. For the cubit, wrap in `BlocProvider<RepoCloneCubit>.value(value: fakeCubit)` where `fakeCubit` is the Task 3 fake-service cubit; for `HomeTargetController` wrap in `RepositoryProvider<HomeTargetController>.value(value: …)` with a minimal stub (it needs `current` and `listSelectable()` — construct a real `HomeTargetController(registry: stubRegistry, current: () => RuntimeTarget.local(), switchTo: (_) async {})` where `stubRegistry` implements `RuntimeTargetRegistry` returning `[RuntimeTarget.local()]` — check `RuntimeTargetRegistry`'s surface and stub what `listTargets` needs).

Tests:

```dart
testWidgets('invalid URL shows validation error and does not pop', (tester) async {
  await tester.pumpWidget(_wrap(const HomeCloneRepositoryDialog())); // expose the dialog widget publicly for the test
  await tester.enterText(find.byType(TextFormField).first, 'not a url');
  await tester.tap(find.text(l10n.cloneRepositorySubmit)); // 'Clone' button label — add l10n key cloneRepositorySubmit: "Clone" / "克隆"
  await tester.pumpAndSettle();
  expect(find.text(l10n.cloneRepositoryUrlInvalid), findsOneWidget);
});

testWidgets('valid URL derives folder name', (tester) async {
  await tester.pumpWidget(_wrap(const HomeCloneRepositoryDialog()));
  await tester.enterText(urlField, 'https://github.com/owner/repo.git');
  await tester.pump();
  expect(dirNameControllerValue, 'repo'); // read via the dir-name field's controller from the widget state, or assert the hint/text field displays 'repo'
});

testWidgets('submit with target + dir + parent pops a RepoCloneRequest', ...);
// pick parent via a monkey-patched picker seam: make the picker function an
// injectable static (like FirstUserLineCapture tests do) or extract
// `Future<String?> Function(BuildContext, String targetId)` as a dialog
// constructor param defaulting to pickWorkspaceDirectoryPath; inject a fake
// returning '/tmp/src'. Assert the popped value's fields.
```

Add `cloneRepositorySubmit` to the l10n keys above (already included in the Task 1 key list) — do not re-add it in Task 5.

Extend `home_workspace_switcher_menu_test.dart`:

```dart
testWidgets('menu shows clone repository item and fires callback', (tester) async {
  var fired = false;
  await tester.pumpWidget(_wrap(HomeWorkspaceSwitcherMenu(
    openTabs: const [], onCloneRepository: () => fired = true, /* ... */)));
  await tester.tap(find.byIcon(Icons.more_horiz));
  await tester.pumpAndSettle();
  expect(find.text(l10n.cloneRepositoryMenu), findsOneWidget);
  await tester.tap(find.text(l10n.cloneRepositoryMenu));
  await tester.pumpAndSettle();
  expect(fired, isTrue);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/home_workspace/clone_repository_dialog_test.dart test/pages/home_workspace/home_workspace_switcher_menu_test.dart`
Expected: FAIL — dialog file missing, menu item missing.

- [ ] **Step 3: Implement the dialog, menu item, and plumbing**

Create the dialog; modify the three existing files per the structure above. Keep the parent-picker seam injectable for tests.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/home_workspace/clone_repository_dialog_test.dart test/pages/home_workspace/home_workspace_switcher_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze + commit**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
git add client/lib/pages/home_workspace/clone_repository_dialog.dart client/lib/pages/home_workspace/home_workspace_switcher_menu.dart client/lib/pages/home_workspace/home_workspace_title_bar.dart client/lib/pages/home_workspace/home_workspace_shell.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/home_workspace/clone_repository_dialog_test.dart client/test/pages/home_workspace/home_workspace_switcher_menu_test.dart client/lib/l10n/app_localizations*.dart
git commit -m "feat(clone): add clone repository dialog and switcher menu entry"
```

---

### Task 6: Completion dialog — new workspace or add to existing

**Files:**
- Create: `client/lib/pages/home_workspace/clone_completed_dialog.dart` (completion dialog + add-to-workspace picker in one file, both small)
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart` (BlocListener near the title bar)
- Test: `client/test/pages/home_workspace/clone_completed_dialog_test.dart`

**Interfaces:**
- Consumes: `RepoCloneCubit`/`RepoCloneState.pendingChoice` (Task 3), `ChatCubit.createWorkspaceWithFirstSession` (`showHomeNewWorkspaceDialog` at `home_new_workspace_dialog.dart:30-40` shows the exact call signature), `ChatCubit.addWorkspaceDirectory(workspaceId, folder)` (`chat_cubit.dart:1881`), `WorkspaceFolder`, `Workspace` records from `ChatCubit.state.workspaces`, `context.go('/home-v2/workspace/$id')` (go_router).
- Produces:

```dart
Future<void> showCloneCompletedDialog(
  BuildContext context, {
  required RepoCloneTask task,
});
```

**Completion dialog behavior:**

```dart
Future<void> showCloneCompletedDialog(
  BuildContext context, {
  required RepoCloneTask task,
}) async {
  final action = await showDialog<_CloneCompletionAction>(
    context: context,
    builder: (_) => CloneCompletedDialog(task: task),
  );
  if (action == null || !context.mounted) {
    if (context.mounted) context.read<RepoCloneCubit>().dismissChoice(task.id);
    return;
  }
  switch (action) {
    case _newWorkspace:
      final workspaceId =
          await context.read<ChatCubit>().createWorkspaceWithFirstSession(
                [WorkspaceFolder(path: task.destPath, targetId: task.targetId)],
                context.read<SessionRepository>(),
                sessionTeamId: '',
                display: task.dirName,
                allowDuplicate: true,
                identityRepository: context.read<LaunchProfileRepository>(),
              );
      if (context.mounted) context.go('/home-v2/workspace/$workspaceId');
    case _addToWorkspace:
      final workspaceId = await _showCloneAddToWorkspaceDialog(context, task);
      // inner dialog already performed the add + toast
  }
  context.read<RepoCloneCubit>().dismissChoice(task.id);
}
```

`CloneCompletedDialog`: `TpDialog` with `TpDialogHeader(title: l10n.cloneRepositoryCompletedTitle)`, body text `l10n.cloneRepositoryCompletedBody(task.destPath)`, buttons — `FilledButton` (new workspace) pops `_newWorkspace`, `OutlinedButton` (add to existing) pops `_addToWorkspace`, plus a dismiss affordance (default dialog dismiss = null).

`_showCloneAddToWorkspaceDialog`: `TpDialog` listing `context.read<ChatCubit>().state.workspaces` as `TpActionMenuItem`-style rows (or a simple `ListView` of `ListTile`s with workspace `display`/first-folder subtitle — follow an existing simple list dialog; check `pages/` for one, else plain `ListTile`s are fine inside `TpDialog`). On tap: `chatCubit.addWorkspaceDirectory(workspace.workspaceId, WorkspaceFolder(path: task.destPath, targetId: task.targetId))`, then a success toast `l10n.cloneRepositoryAddToExistingSucceeded(task.dirName, workspace.display)` (empty display → use first folder basename), pop.

**Shell listener** in `home_workspace_shell.dart` — wrap the shell body (or place as sibling of `_HomeShellTitleBar` inside the `Column`) with:

```dart
BlocListener<RepoCloneCubit, RepoCloneState>(
  listener: (context, state) {
    final task = state.pendingChoice.firstOrNull;
    if (task != null && task.id != _lastPresentedCloneChoiceId) {
      _lastPresentedCloneChoiceId = task.id;
      unawaited(showCloneCompletedDialog(context, task: task));
    }
  },
  child: …,
)
```

(`_lastPresentedCloneChoiceId` is a `String?` field on `_HomeShellState` guarding re-presentation on rebuilds while the dialog is open.)

- [ ] **Step 1: Write the failing widget test**

`client/test/pages/home_workspace/clone_completed_dialog_test.dart` — same harness as Task 5 plus `BlocProvider<ChatCubit>.value` with a real or stubbed `ChatCubit`. A full `ChatCubit` is heavy; instead assert the dialog UI + callbacks: inject handlers as constructor/function params where possible. Minimal viable test:

```dart
testWidgets('completed dialog offers new workspace and add-to-existing', (tester) async {
  await tester.pumpWidget(_wrap(CloneCompletedDialog(task: task)));
  expect(find.text(l10n.cloneRepositoryCreateWorkspace), findsOneWidget);
  expect(find.text(l10n.cloneRepositoryAddToWorkspace), findsOneWidget);
});

testWidgets('choosing new workspace pops _CloneCompletionAction.newWorkspace', ...);
testWidgets('add-to-existing lists workspaces and adds the folder on tap', ...);
```

For the add-to-existing test, use a lightweight `ChatCubit` fake via `BlocProvider<ChatCubit>.value` with a stub class implementing the used methods (`state.workspaces`, `addWorkspaceDirectory`) — if `ChatCubit` cannot be implemented (concrete class with huge surface), restructure the dialog to take the workspace list and `onAdd` callback as constructor params (the shell wiring passes the real cubit calls) and test those directly. **Prefer the callback-param design** — it keeps the dialog a pure widget.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/pages/home_workspace/clone_completed_dialog_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

Create the dialog file and the shell listener per the code above. Use the callback-param design if `ChatCubit` is not practically fakeable.

- [ ] **Step 4: Run tests + analyze**

Run: `cd client && flutter test test/pages/home_workspace/ && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS / clean.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/clone_completed_dialog.dart client/lib/pages/home_workspace/home_workspace_shell.dart client/test/pages/home_workspace/clone_completed_dialog_test.dart
git commit -m "feat(clone): offer new or existing workspace after clone completes"
```

---

### Task 7: Full verification gate + manual smoke notes

**Files:** none new (verification only)

- [ ] **Step 1: Run the full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: clean analysis, all tests pass.

- [ ] **Step 2: Self-review diff against the spec**

Check each spec item: menu entry (Task 5), URL/target/parent/dir dialog (5), three-target execution (2), git pre-check (2), dest-exists pre-check (2), streamed progress + fraction (2, 3), cancel + partial cleanup (3), notification history on complete (3), completion dialog with new/add (6), skip affordance (6), l10n (1, 5). Fix anything missing before commit.

- [ ] **Step 3: Manual smoke (optional but recommended)**

Launch the app (`flutter run` per docs/DEVELOPMENT.md), open the ⋯ menu → Clone Repository…, clone a small public repo (e.g. `https://github.com/octocat/Hello-World.git`) into a temp folder, watch the progress tile, then pick "New workspace" and confirm the file tree shows the repo. Record results in the commit message body if performed.

- [ ] **Step 4: Final commit (if Step 2/3 produced fixes)**

```bash
git add -A
git commit -m "fix(clone): verification fixes from full gate"
```
