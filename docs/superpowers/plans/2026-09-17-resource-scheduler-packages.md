# Resource scheduler packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `teampilot_fs`, `teampilot_apply`, and `teampilot_scheduler` as pure Dart packages, then run Session init through `SessionScheduler.init` so the Flutter app only injects two filesystems plus plugins and opens a PTY from the spawn spec.

**Architecture:** Dependency order is `teampilot_fs` → `teampilot_apply` → `teampilot_scheduler` → `teampilot`. Client keeps thin `export` shims at the old `package:teampilot/...` paths so the first two extracts are import-stable. Scheduler owns projection + apply + spawn assembly. Cursor/Claude stay in the app as `SessionCliPlugin` adapters. SSH bash/tar is deleted only in the last task, after flush always uses `WorkPlaneApplier` on `targetFs`.

**Tech Stack:** Dart 3.8, `package:path`, `package:crypto`, `package:test` inside the new packages; Flutter client still uses `cd client && dart run tool/run_tests.dart`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-17-resource-scheduler-packages-design.md`.
- Packages live at `client/packages/teampilot_{fs,apply,scheduler}`, `publish_to: none`, SDK `^3.8.1`, no Flutter.
- Dependency only downward: scheduler may import apply and fs; apply may import fs; fs imports neither.
- Never `flutter test` in `client/`. Package tests: `cd client/packages/<pkg> && dart test`. Client tests: `cd client && dart run tool/run_tests.dart <path>`.
- Do not add `teampilot-apply` binary, on-disk `cas/`, or `dartssh2` to the new packages.
- Do not move `services/cli/**` implementations into the packages.
- Do not put `AppSession` / `TeamProfile` / `CliLaunchContext` into the packages.
- `WorkPathProjector` in the scheduler must not import `AppLogger`; drop those debug logs or take `void Function(String)? log`.
- Do not auto-rollback failed apply.
- Do not commit unless the user asks; skip commit steps during execution if they have not.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/teampilot_fs/lib/teampilot_fs.dart` | Export `Filesystem`, stats, watcher, lstat, `LocalFilesystem`, `InMemoryFilesystem` |
| `client/packages/teampilot_apply/lib/teampilot_apply.dart` | Export ApplyPlan, BlobStore, WorkPlaneApplier |
| `client/packages/teampilot_scheduler/lib/teampilot_scheduler.dart` | Export DTO, layout, manifest, projector, plugin interfaces, `SessionScheduler` |
| `client/lib/services/io/filesystem.dart` | `export 'package:teampilot_fs/teampilot_fs.dart';` after Task 1 |
| `client/lib/services/launch/apply_plan.dart` | Re-export apply package after Task 3 |
| `client/lib/services/launch/session_connect_orchestrator.dart` | Call `SessionScheduler.init` after Task 6 |
| `client/lib/services/launch/manifest_executor.dart` | Always applier; delete SSH compiler in Task 7 |

---

### Task 1: `teampilot_fs` package (interface + memory + local)

**Files:**
- Create: `client/packages/teampilot_fs/pubspec.yaml`
- Create: `client/packages/teampilot_fs/analysis_options.yaml`
- Create: `client/packages/teampilot_fs/lib/teampilot_fs.dart`
- Create: `client/packages/teampilot_fs/lib/src/filesystem.dart` (move from `client/lib/services/io/filesystem.dart`)
- Create: `client/packages/teampilot_fs/lib/src/in_memory_filesystem.dart` (class only from `client/test/support/in_memory_filesystem.dart`)
- Create: `client/packages/teampilot_fs/lib/src/lock_pool.dart`
- Create: `client/packages/teampilot_fs/lib/src/windows_junction.dart` (move from `client/lib/services/io/windows_junction.dart`)
- Create: `client/packages/teampilot_fs/lib/src/local_filesystem.dart` (move from `client/lib/services/io/local_filesystem.dart`)
- Create: `client/packages/teampilot_fs/test/in_memory_filesystem_test.dart`
- Create: `client/packages/teampilot_fs/test/local_filesystem_test.dart`
- Modify: `client/pubspec.yaml` (add path dependency)
- Modify: `client/lib/services/io/filesystem.dart` → export shim
- Modify: `client/lib/services/io/local_filesystem.dart` → export shim
- Modify: `client/lib/services/io/windows_junction.dart` → export shim
- Modify: `client/test/support/in_memory_filesystem.dart` — keep `fakeHomeStorage`, import `InMemoryFilesystem` from the package
- Modify: `docs/DEVELOPMENT.md` — one bullet: package tests via `dart test` in `client/packages/teampilot_*`

**Interfaces:**
- Consumes: `package:path`, `package:ffi`, `package:synchronized`
- Produces: `package:teampilot_fs/teampilot_fs.dart` public types identical to today's `Filesystem` / `LocalFilesystem` / `InMemoryFilesystem`

- [ ] **Step 1: Write the failing package tests**

`client/packages/teampilot_fs/pubspec.yaml`:

```yaml
name: teampilot_fs
description: Filesystem interface and local/memory backends for TeamPilot.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  path: ^1.9.0
  ffi: ^2.2.0
  synchronized: ^3.3.1

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

`analysis_options.yaml`:

```yaml
include: package:lints/recommended.yaml
```

`test/in_memory_filesystem_test.dart` (package:test, not flutter_test):

```dart
import 'package:test/test.dart';
import 'package:teampilot_fs/teampilot_fs.dart';

void main() {
  test('readBytesRange returns slice and fewer bytes at EOF', () async {
    final fs = InMemoryFilesystem();
    await fs.writeBytes('/a.bin', [0, 1, 2, 3, 4]);
    expect(await fs.readBytesRange('/a.bin', 1, 2), [1, 2]);
    expect(await fs.readBytesRange('/a.bin', 3, 10), [3, 4]);
    expect(await fs.readBytesRange('/a.bin', 5, 4), <int>[]);
    expect(await fs.readBytesRange('/missing', 0, 4), isNull);
  });

  test('appendBytes creates and extends', () async {
    final fs = InMemoryFilesystem();
    await fs.appendBytes('/a.bin', [1, 2]);
    await fs.appendBytes('/a.bin', [3]);
    expect(await fs.readBytes('/a.bin'), [1, 2, 3]);
  });

  test('lstat reports symlink without following', () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/t');
    await fs.createSymlink(target: '/t', linkPath: '/l');
    expect((await fs.lstat('/l')).isSymlink, isTrue);
  });
}
```

Copy `client/test/services/io/local_filesystem_test.dart` into `client/packages/teampilot_fs/test/local_filesystem_test.dart`, changing:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
```

to:

```dart
import 'package:test/test.dart';
import 'package:teampilot_fs/teampilot_fs.dart';
```

Keep the same cases (`rename`, dir tree, dangling symlink `ensureDir`, etc.).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_fs && dart pub get && dart test
```

Expected: FAIL resolving `package:teampilot_fs` types / missing lib.

- [ ] **Step 3: Move implementation**

`lib/src/lock_pool.dart` (same behavior as `client/lib/utils/lock_pool.dart`):

```dart
import 'package:synchronized/synchronized.dart';

class LockPool {
  final _locks = <String, Lock>{};

  Future<T> synchronized<T>(String key, Future<T> Function() fn) {
    return _locks.putIfAbsent(key, Lock.new).synchronized(fn);
  }
}
```

- `git mv` `client/lib/services/io/filesystem.dart` → `client/packages/teampilot_fs/lib/src/filesystem.dart` (no `package:teampilot` imports).
- Copy `InMemoryFilesystem` **class only** (not `fakeHomeStorage`) into `lib/src/in_memory_filesystem.dart`. Import `filesystem.dart`. Do not import `HomeStorage` / `RuntimeTarget`.
- `git mv` `windows_junction.dart` and `local_filesystem.dart` into `lib/src/`. Change local_filesystem imports to `filesystem.dart`, `windows_junction.dart`, `lock_pool.dart`.

`lib/teampilot_fs.dart`:

```dart
export 'src/filesystem.dart';
export 'src/in_memory_filesystem.dart';
export 'src/local_filesystem.dart';
```

Do **not** export `LockPool` or `WindowsJunction` unless client still needs them from this barrel. Client `windows_junction.dart` shim should export the src file:

```dart
export 'package:teampilot_fs/src/windows_junction.dart';
```

If `src/` export is too leaky, export `windows_junction.dart` from the barrel too. Prefer barrel export of `WindowsJunction` so client does not import `src/`.

Replace moved client files with:

```dart
export 'package:teampilot_fs/teampilot_fs.dart';
```

`local_filesystem.dart` and `filesystem.dart` can share that barrel. `windows_junction.dart`:

```dart
export 'package:teampilot_fs/teampilot_fs.dart' show WindowsJunction;
```

(Add `WindowsJunction` to the barrel if shown.)

`client/test/support/in_memory_filesystem.dart` becomes:

```dart
import 'package:path/path.dart' as p;
import 'package:teampilot_fs/teampilot_fs.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

export 'package:teampilot_fs/teampilot_fs.dart' show InMemoryFilesystem;

HomeStorage fakeHomeStorage({ ... existing body ... });
```

Add to `client/pubspec.yaml` dependencies:

```yaml
  teampilot_fs:
    path: packages/teampilot_fs
```

Run `cd client && dart pub get`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_fs && dart test
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/io/local_filesystem_test.dart test/services/io/in_memory_filesystem_range_test.dart
```

Expected: PASS. Client io tests still compile via shims.

- [ ] **Step 5: Commit**

```bash
git add client/packages/teampilot_fs client/pubspec.yaml client/pubspec.lock \
  client/lib/services/io/filesystem.dart \
  client/lib/services/io/local_filesystem.dart \
  client/lib/services/io/windows_junction.dart \
  client/test/support/in_memory_filesystem.dart \
  docs/DEVELOPMENT.md
git commit -m "$(cat <<'EOF'
feat: extract teampilot_fs package

EOF
)"
```

---

### Task 2: `teampilot_apply` package

**Files:**
- Create: `client/packages/teampilot_apply/pubspec.yaml`
- Create: `client/packages/teampilot_apply/analysis_options.yaml`
- Create: `client/packages/teampilot_apply/lib/teampilot_apply.dart`
- Move: `apply_plan.dart`, `blob_store.dart`, `work_plane_applier.dart` into `lib/src/`
- Create: package tests copied from `client/test/services/launch/apply_plan_test.dart`, `blob_store_test.dart`, `work_plane_applier_test.dart` using `package:test` + `InMemoryFilesystem` from `teampilot_fs`
- Modify: those three client lib files → `export 'package:teampilot_apply/teampilot_apply.dart';`
- Modify: `client/pubspec.yaml` add `teampilot_apply`

**Interfaces:**
- Consumes: `package:teampilot_fs`, `package:crypto`, `package:path`
- Produces: `ApplyPlan`, `ApplyOp` subclasses, `assertApplyPath`, `contentSha256Hex`, `BlobStore`, `MemoryBlobStore`, `WorkPlaneApplier` with the same constructors as today

`pubspec.yaml`:

```yaml
name: teampilot_apply
description: ApplyPlan + in-process work-plane applier.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  crypto: ^3.0.7
  path: ^1.9.0
  teampilot_fs:
    path: ../teampilot_fs

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

- [ ] **Step 1: Write failing package tests**

Port `apply_plan_test.dart` 1:1 (`json roundtrip`, sandbox, missing protocolVersion). Change imports to:

```dart
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot_apply/teampilot_apply.dart';
```

Port `blob_store_test.dart` and `work_plane_applier_test.dart` the same way. Applier test uses `InMemoryFilesystem` from `package:teampilot_fs/teampilot_fs.dart`. Copy `_AtomicWriteRecordingFilesystem` into the package test file.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_apply && dart pub get && dart test
```

Expected: FAIL missing library.

- [ ] **Step 3: Move implementation**

`git mv` the three launch files into `lib/src/`. Fix imports:

- `apply_plan.dart`: `crypto` + `path` only
- `blob_store.dart`: `import 'apply_plan.dart';`
- `work_plane_applier.dart`: `import 'package:teampilot_fs/teampilot_fs.dart';` plus local `apply_plan.dart` / `blob_store.dart`

Barrel:

```dart
export 'src/apply_plan.dart';
export 'src/blob_store.dart';
export 'src/work_plane_applier.dart';
```

Client shims:

```dart
export 'package:teampilot_apply/teampilot_apply.dart';
```

in `apply_plan.dart`, `blob_store.dart`, `work_plane_applier.dart`.

Add `teampilot_apply` path dep to `client/pubspec.yaml`. `dart pub get` in client.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_apply && dart test
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart \
  test/services/launch/apply_plan_test.dart \
  test/services/launch/blob_store_test.dart \
  test/services/launch/work_plane_applier_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: extract teampilot_apply package

EOF
)"
```

---

### Task 3: Scheduler DTO and errors

**Files:**
- Create: `client/packages/teampilot_scheduler/pubspec.yaml`
- Create: `client/packages/teampilot_scheduler/analysis_options.yaml`
- Create: `client/packages/teampilot_scheduler/lib/teampilot_scheduler.dart`
- Create: `lib/src/session_init_request.dart`
- Create: `lib/src/session_init_result.dart`
- Create: `lib/src/session_init_exception.dart`
- Create: `lib/src/session_security_policy.dart`
- Test: `test/session_init_dto_test.dart`

Plugin interfaces (`SessionCliPlugin`, `ResourceContributor`) land in Task 4 with `SessionLayout` / `LaunchManifest` so this package compiles at every task boundary.

**Interfaces:**
- Consumes: none beyond `path` (apply/fs deps declared for later tasks)
- Produces: types below (names locked)

```dart
enum SessionInitStage { layout, contribute, project, apply, afterApply, spawn }

final class SessionInitException implements Exception {
  SessionInitException(this.stage, {this.path, this.cause, this.message});
  final SessionInitStage stage;
  final String? path;
  final Object? cause;
  final String? message;
  @override
  String toString() => 'SessionInitException($stage, path: $path, $message)';
}

enum SessionApprovalPolicy { cliDefault, ask, autoApprove, never }
enum SessionSandboxPolicy { cliDefault, readOnly, workspaceWrite, fullAccess }
enum SessionHookTrustPolicy { cliDefault, trustedOnly, bypass }

final class SessionSecurityPolicy {
  const SessionSecurityPolicy({
    this.approval = SessionApprovalPolicy.never,
    this.sandbox = SessionSandboxPolicy.fullAccess,
    this.hookTrust = SessionHookTrustPolicy.bypass,
  });
  static const fullAccess = SessionSecurityPolicy();
  final SessionApprovalPolicy approval;
  final SessionSandboxPolicy sandbox;
  final SessionHookTrustPolicy hookTrust;
}

final class SessionInitRequest {
  const SessionInitRequest({
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.cli,
    required this.cliExecutablePath,
    required this.homeRoot,
    required this.workRoot,
    this.providerId = '',
    this.identityId = '',
    this.workingDirectory = '',
    this.additionalDirectories = const [],
    this.cliTeamName = '',
    this.resumeSessionId,
    this.createSessionId,
    this.securityPolicy = SessionSecurityPolicy.fullAccess,
    this.skillIds = const [],
    this.pluginIds = const [],
    this.mcpIds = const [],
  });

  final String workspaceId;
  final String sessionId;
  final String memberId;
  final String cli;
  final String cliExecutablePath;
  final String homeRoot;
  final String workRoot;
  final String providerId;
  final String identityId;
  final String workingDirectory;
  final List<String> additionalDirectories;
  final String cliTeamName;
  final String? resumeSessionId;
  final String? createSessionId;
  final SessionSecurityPolicy securityPolicy;
  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpIds;
}

final class SessionSpawnSpec {
  const SessionSpawnSpec({
    required this.executable,
    required this.argv,
    required this.env,
    required this.cwd,
  });
  final String executable;
  final List<String> argv;
  final Map<String, String> env;
  final String cwd;
}

final class SessionInitResult {
  const SessionInitResult({
    required this.spawn,
    this.warnings = const [],
    this.nativeSessionIdToPersist,
  });
  final SessionSpawnSpec spawn;
  final List<String> warnings;
  final String? nativeSessionIdToPersist;
}
```

Do not add `SessionCliPlugin` until Task 4.

- [ ] **Step 1: Write failing test**

```dart
import 'package:test/test.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

void main() {
  test('SessionInitException carries stage and path', () {
    final e = SessionInitException(
      SessionInitStage.project,
      path: '/work/a',
      message: 'cannot project',
    );
    expect(e.stage, SessionInitStage.project);
    expect(e.path, '/work/a');
    expect(e.toString(), contains('project'));
  });

  test('fullAccess policy defaults match client fullAccess', () {
    const p = SessionSecurityPolicy.fullAccess;
    expect(p.approval, SessionApprovalPolicy.never);
    expect(p.sandbox, SessionSandboxPolicy.fullAccess);
    expect(p.hookTrust, SessionHookTrustPolicy.bypass);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart pub get && dart test
```

Expected: FAIL missing package.

- [ ] **Step 3: Implement DTO types** as listed. `pubspec.yaml`:

```yaml
name: teampilot_scheduler
description: Session work-plane init to spawn spec.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.8.1

dependencies:
  path: ^1.9.0
  teampilot_fs:
    path: ../teampilot_fs
  teampilot_apply:
    path: ../teampilot_apply

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add teampilot_scheduler session init DTOs

EOF
)"
```

---

### Task 4: Move LaunchManifest, SessionLayout, CLI cache, projector

**Files:**
- Move: `client/lib/services/launch/launch_manifest.dart` → `teampilot_scheduler/lib/src/launch_manifest.dart`
- Create: `lib/src/session_layout.dart` (path math only, `String` tool ids)
- Create: `lib/src/workspace_cli_cache.dart` (bindings keyed by tool id string, no `CliTool`)
- Move: `work_path_projector.dart` → `lib/src/work_path_projector.dart` (delete `appLogger` calls)
- Client shims: `launch_manifest.dart` and `work_path_projector.dart` re-export
- Client `WorkspaceCliCache` / `RuntimeLayout` keep working: delegate path helpers to `SessionLayout` **or** leave them in client for this task and have scheduler `SessionLayout` duplicate the path formulas (must match `docs/workspace-storage-layout.md`)
- Create: `lib/src/session_cli_plugin.dart`
- Create: `lib/src/resource_contributor.dart`
- Test: `client/packages/teampilot_scheduler/test/work_path_projector_test.dart` (port the 13 cases from `client/test/services/launch/work_path_projector_test.dart` to `package:test`)
- Test: `test/session_layout_test.dart`

**Interfaces:**
- Consumes: `Filesystem`, `ApplyPlan`, `MemoryBlobStore`, `LaunchManifest`
- Produces plugin contracts (exact signatures):

```dart
abstract interface class SessionCliPlugin {
  String get toolId;

  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  });

  String sessionConfigDir(SessionLayout layout, SessionInitRequest request);

  Future<void> afterApply({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  });

  SessionSpawnSpec buildSpawn({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  });
}

abstract interface class ResourceContributor {
  String get id;
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required LaunchManifest manifest,
  });
}
```

Also produces:

```dart
final class SessionLayout {
  SessionLayout({
    required this.teampilotRoot,
    required this.pathContext,
  });
  final String teampilotRoot;
  final p.Context pathContext;

  String get cliDefaultsDir;
  String identityToolDir(String profileId, String tool);
  String workspaceConfigToolDir(String workspaceId, String tool);
  String sessionRuntimeToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  });
}

Future<ApplyPlanBuild> buildApplyPlan({
  required LaunchManifest manifest,
  required Filesystem sourceFs,
  required Filesystem workFs,
  required String homeRoot,
  required String workRoot,
});
```

Path formulas (must match current `WorkspaceLayout` / `RuntimeLayout`):

```dart
workspaceRootDir = join(teampilotRoot, 'workspace')
workspacesDir = join(workspaceRootDir, 'workspaces')
workspaceDir(id) = join(workspacesDir, id.trim())
workspaceConfigToolDir(ws, tool) = join(workspaceDir(ws), 'config', tool.trim())
sessionDir(ws, sid) = join(workspaceDir(ws), 'sessions', sid.trim())
sessionRuntimeDir(ws, sid) = join(sessionDir(ws, sid), 'runtime')
sessionRuntimeToolDir: if memberId non-empty
  join(sessionRuntimeDir, memberId.trim(), tool)
else
  join(sessionRuntimeDir, tool)
cliDefaultsDir = join(teampilotRoot, 'cli-defaults')
identitiesRuntimeDir = join(teampilotRoot, 'identities-runtime')
identityToolDir(profileId, tool) = join(identitiesRuntimeDir, profileId.trim(), tool.trim())
```

`WorkspaceCliCache` in scheduler:

```dart
final class WorkspaceCliCache {
  WorkspaceCliCache({required this.layout});
  final SessionLayout layout;
  static const sharedProviderKey = '_shared';
  static String providerKey(String? providerId);
  String globalRoot({required String tool, String? providerId});
  static List<CliCacheBinding> bindingFor(String tool);
}
```

`bindingFor('cursor'|'opencode'|'codex'|other)` returns the same lists as today's `CliTool` switch; unknown tool → `const []`.

- [ ] **Step 1: Write failing layout + projector tests**

`session_layout_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

void main() {
  final ctx = p.Context(style: p.Style.posix);
  final layout = SessionLayout(teampilotRoot: '/tp', pathContext: ctx);

  test('session runtime dir uses member segment when present', () {
    expect(
      layout.sessionRuntimeToolDir('w', 's', 'cursor', memberId: 'm1'),
      '/tp/workspace/workspaces/w/sessions/s/runtime/m1/cursor',
    );
    expect(
      layout.sessionRuntimeToolDir('w', 's', 'cursor'),
      '/tp/workspace/workspaces/w/sessions/s/runtime/cursor',
    );
  });

  test('cli cache global root is workspace/cache/cli/tool/provider', () {
    final cache = WorkspaceCliCache(layout: layout);
    expect(
      cache.globalRoot(tool: 'cursor', providerId: 'acct'),
      '/tp/workspace/cache/cli/cursor/acct',
    );
    expect(
      cache.globalRoot(tool: 'cursor', providerId: ''),
      '/tp/workspace/cache/cli/cursor/_shared',
    );
  });
}
```

Port projector tests; import `package:teampilot_fs` + scheduler barrel. Keep the cases: provided-link stays ln; in-plan catalog ln; child of copyTree; overlay parent symlink; first-fill dangling statsig kept; missing unprojectable throws.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart test
```

Expected: FAIL missing `SessionLayout` / `buildApplyPlan`.

- [ ] **Step 3: Implement**

Move `launch_manifest.dart` unchanged (already has no Flutter).

Move projector; remove:

```dart
import '../../utils/logging/logger.dart';
```

and both `appLogger.d(...)` blocks (behavior must stay).

Implement `SessionLayout` + scheduler `WorkspaceCliCache`.

Client `launch_manifest.dart` / `work_path_projector.dart`:

```dart
export 'package:teampilot_scheduler/teampilot_scheduler.dart'
    show LaunchManifest, LaunchManifestEntry, ManifestEnsureDir, ManifestWriteFile,
         ManifestSymlink, ManifestCopyFile, ManifestCopyTree, ManifestRemoveRecursive,
         ManifestRename, buildApplyPlan, ApplyPlanBuild;
```

Export whatever the client already imported from those files (grep if a type is missing). Add `teampilot_scheduler` to `client/pubspec.yaml`.

Do **not** delete client `RuntimeLayout` yet; it still uses `CliTool` and `LockPool`. Path strings must stay equal so existing `runtime_layout_test.dart` still passes.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart test
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart \
  test/services/launch/work_path_projector_test.dart \
  test/services/storage/runtime_layout_test.dart \
  test/services/storage/workspace_cli_cache_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: move ApplyPlan projector and session layout into teampilot_scheduler

EOF
)"
```

---

### Task 5: `SessionScheduler.init` with fake plugin

**Files:**
- Create: `client/packages/teampilot_scheduler/lib/src/session_scheduler.dart`
- Test: `client/packages/teampilot_scheduler/test/session_scheduler_init_test.dart`

**Interfaces:**
- Consumes: types from Tasks 3–4, `WorkPlaneApplier`, `buildApplyPlan`
- Produces:

```dart
final class SessionScheduler {
  const SessionScheduler();

  Future<SessionInitResult> init({
    required SessionInitRequest request,
    required Filesystem homeFs,
    required Filesystem workFs,
    required SessionCliPlugin plugin,
    List<ResourceContributor> resources = const [],
  });
}
```

Body, in order, wrapping each stage in `try/on Object` → `SessionInitException(stage, cause: e)`:

1. `layout` — `SessionLayout(teampilotRoot: request.workRoot, pathContext: workFs.pathContext)` for work paths; plugins also receive this layout. Home-rooted contribute paths use `request.homeRoot` on `homeFs`.
2. `contribute` — empty `LaunchManifest(pathContext: workFs.pathContext)`; for `resources` then `plugin.contribute`.
3. `project` — `buildApplyPlan(manifest:, sourceFs: homeFs, workFs:, homeRoot: request.homeRoot, workRoot: request.workRoot)`.
4. `apply` — `WorkPlaneApplier(fs: workFs, blobs: built.blobs, workRoot: request.workRoot).apply(built.plan)`.
5. `afterApply` — create `final env = <String, String>{}` before contribute; pass that same map into `afterApply` and `buildSpawn`.
6. `spawn` — `plugin.buildSpawn(...)` then `SessionInitResult(spawn: spec)`.

If `plugin.toolId != request.cli` throw `SessionInitException(layout, message: 'plugin/tool mismatch')`.

- [ ] **Step 1: Write failing tests**

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:teampilot_fs/teampilot_fs.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

class _WritePlugin implements SessionCliPlugin {
  @override
  String get toolId => 'cursor';

  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) async {
    manifest.writeFile('${request.workRoot}/hello.txt', 'hi');
  }

  @override
  String sessionConfigDir(SessionLayout layout, SessionInitRequest request) =>
      layout.sessionRuntimeToolDir(
        request.workspaceId,
        request.sessionId,
        request.cli,
        memberId: request.memberId,
      );

  @override
  Future<void> afterApply({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  }) async {}

  @override
  SessionSpawnSpec buildSpawn({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  }) {
    return SessionSpawnSpec(
      executable: request.cliExecutablePath,
      argv: const ['--version'],
      env: environment,
      cwd: request.workingDirectory,
    );
  }
}

void main() {
  final posix = p.Context(style: p.Style.posix);

  SessionInitRequest req() => SessionInitRequest(
        workspaceId: 'w',
        sessionId: 's',
        memberId: 's',
        cli: 'cursor',
        cliExecutablePath: '/bin/cursor-agent',
        homeRoot: '/home-tp',
        workRoot: '/work-tp',
        workingDirectory: '/proj',
      );

  test('init applies plugin writes and returns spawn spec', () async {
    final home = InMemoryFilesystem(pathContext: posix);
    final work = InMemoryFilesystem(pathContext: posix);
    await work.ensureDir('/work-tp');
    final result = await const SessionScheduler().init(
      request: req(),
      homeFs: home,
      workFs: work,
      plugin: _WritePlugin(),
    );
    expect(await work.readString('/work-tp/hello.txt'), 'hi');
    expect(result.spawn.executable, '/bin/cursor-agent');
    expect(result.spawn.argv, ['--version']);
    expect(result.spawn.cwd, '/proj');
  });

  test('unprojectable missing source becomes SessionInitException project', () async {
    final home = InMemoryFilesystem(pathContext: posix);
    final work = InMemoryFilesystem(pathContext: posix);
    await work.ensureDir('/work-tp');

    try {
      await const SessionScheduler().init(
        request: req(),
        homeFs: home,
        workFs: work,
        plugin: _BadLinkPlugin(),
      );
      fail('expected SessionInitException');
    } on SessionInitException catch (e) {
      expect(e.stage, SessionInitStage.project);
    }
  });
}

class _BadLinkPlugin extends _WritePlugin {
  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) async {
    manifest.symlink(
      linkPath: '${request.workRoot}/l',
      target: '${request.homeRoot}/nope',
    );
  }
}
```

Also add a `ResourceContributor` that writes `${request.workRoot}/from-resource.txt` and assert the file after `init`.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart test test/session_scheduler_init_test.dart
```

Expected: FAIL missing `SessionScheduler`.

- [ ] **Step 3: Implement `SessionScheduler.init`** as specified. Do not call SSH. Do not install CLI binaries.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart test
```

Expected: PASS including projector ports from Task 4.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add SessionScheduler.init for work-plane apply and spawn spec

EOF
)"
```

---

### Task 6: Wire client orchestrator through `SessionScheduler.init`

**Files:**
- Create: `client/lib/services/launch/delegating_session_cli_plugin.dart`
- Create: `client/lib/services/launch/session_init_request_mapper.dart`
- Modify: `client/lib/services/launch/session_connect_orchestrator.dart`
- Test: `client/test/services/launch/session_init_request_mapper_test.dart`
- Test: `client/test/services/launch/delegating_session_cli_plugin_test.dart`

**Interfaces:**
- Consumes: `SessionScheduler.init`, existing staging that already returns `LaunchManifest` + env + `ShellLaunchSpec` pieces
- Produces: orchestrator still returns `({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})` this task. Fill `ShellLaunchSpec` from `SessionInitResult` (migration shim in the spec).

Mapper:

```dart
SessionInitRequest sessionInitRequestFromConnect({
  required String workspaceId,
  required String sessionId,
  required String memberId,
  required String cli,
  required String cliExecutablePath,
  required String homeRoot,
  required String workRoot,
  String providerId = '',
  String identityId = '',
  String workingDirectory = '',
  List<String> additionalDirectories = const [],
  String cliTeamName = '',
  String? resumeSessionId,
  String? createSessionId,
  required LaunchSecurityPolicy securityPolicy,
  List<String> skillIds = const [],
  List<String> pluginIds = const [],
  List<String> mcpIds = const [],
}) { ... map LaunchSecurityPolicy field-by-field onto SessionSecurityPolicy ... }
```

`DelegatingSessionCliPlugin`:

```dart
final class DelegatingSessionCliPlugin implements SessionCliPlugin {
  DelegatingSessionCliPlugin({
    required this.toolId,
    required this.onContribute,
    required this.onSessionConfigDir,
    required this.onAfterApply,
    required this.onBuildSpawn,
  });

  @override
  final String toolId;
  final Future<void> Function({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) onContribute;
  // similarly typed fields for the other three methods; forward to them.
}
```

Orchestrator change inside `_prepareConnectFromPlan` after workspace provision / `remoteCliPath` resolution:

1. Build `SessionInitRequest` via mapper (`cli: cli.value`, roots from `homeContext().appDataRoot` and `workContext.appDataRoot`, `cliExecutablePath: remoteCliPath`).
2. Construct `DelegatingSessionCliPlugin` whose `onContribute` runs the **existing** `staged = ...` block (simple vs team contributeLaunch) but writes into the `manifest` argument instead of a local-only manifest. If today's code builds its own `LaunchManifest`, copy `staged.manifest.entries` into the scheduler manifest via `copyWithEntries` / replay.
3. `onAfterApply` calls current `afterManifestFlush` + `provisionNativePlugins`.
4. `onBuildSpawn` returns `SessionSpawnSpec` from the existing `ShellLaunchSpec` argv/env/cwd (use current `prepareShellLaunch` / staged outcome). Executable is `request.cliExecutablePath`.
5. Replace `manifestExecutor.flush(...)` with:

```dart
final initResult = await const SessionScheduler().init(
  request: request,
  homeFs: offHome ? homeContext().fs : workContext.fs,
  workFs: workContext.fs,
  plugin: plugin,
);
```

6. Map `initResult` back to the existing return record. Keep `ManifestExecutor` in the class for now but unused on this path (deleted in Task 7).

Do not move Cursor provisioner.

PTY this task: keep returning today's `ShellLaunchSpec` from the orchestrator (terminal code unchanged). `onBuildSpawn` must still return a real `SessionSpawnSpec` whose `executable` is `remoteCliPath` and whose `argv`/`env`/`cwd` are copied from that `ShellLaunchSpec` (close over `TeamProfile` / `CliLaunchContext` inside the adapter). Store `initResult.spawn` only on the return record if easy; do not point the PTY at an empty argv.

- [ ] **Step 1: Write failing mapper test**

```dart
test('maps LaunchSecurityPolicy.fullAccess to SessionSecurityPolicy.fullAccess', () {
  final req = sessionInitRequestFromConnect(
    workspaceId: 'w',
    sessionId: 's',
    memberId: 's',
    cli: 'cursor',
    cliExecutablePath: '/bin/cursor-agent',
    homeRoot: '/h',
    workRoot: '/w',
    securityPolicy: LaunchSecurityPolicy.fullAccess,
  );
  expect(req.securityPolicy.sandbox, SessionSandboxPolicy.fullAccess);
  expect(req.cli, 'cursor');
});
```

Delegating plugin test: `onContribute` writes a file into the passed manifest; `SessionScheduler.init` on two memory fs (from `package:teampilot_fs` via client support) sees the file. This can live in client tests with `flutter_test`.

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart \
  test/services/launch/session_init_request_mapper_test.dart
```

Expected: FAIL missing mapper.

- [ ] **Step 3: Implement mapper, delegating plugin, orchestrator wire**

`init` replaces `manifestExecutor.flush`. Staging stays in `onContribute` (existing contributeLaunch). `onAfterApply` is existing `afterManifestFlush` + `provisionNativePlugins`. `onBuildSpawn` copies executable/cwd/env from the `ShellLaunchSpec` already built for the return value; argv is `const []` on the spawn spec **only because the PTY still consumes `ShellLaunchSpec.launchContext`**, not `initResult.spawn`. Do not change terminal spawn in this task.

- [ ] **Step 4: Run tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart \
  test/services/launch/session_init_request_mapper_test.dart \
  test/services/launch/delegating_session_cli_plugin_test.dart \
  test/services/launch/work_path_projector_test.dart
```

Also run whatever existing orchestrator / connect tests grep finds (`session_connect_orchestrator`).

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(launch): run session work-plane apply through SessionScheduler

EOF
)"
```

---

### Task 7: Always apply on `targetFs`; delete SSH bash compiler

**Files:**
- Modify: `client/lib/services/launch/manifest_executor.dart` — if anything still calls it, make `flush` always `WorkPlaneApplier` (no `compileApplyPlanForSsh`). After Task 6, orchestrator may not call it; delete dead `flush` SSH branch anyway.
- Delete: `client/lib/services/launch/apply_plan_ssh_compiler.dart`
- Modify/delete: `client/test/services/launch/apply_plan_ssh_compiler_test.dart` — replace with a test that two different `InMemoryFilesystem` instances (home vs work) apply via `SessionScheduler.init` or `WorkPlaneApplier` (already covered). Any test that asserted bash `mkdir` / `_tp_ensure_dir` is removed, not rewritten as mkdir defense.
- Grep `compileApplyPlanForSsh` / `ApplyPlanSsh` and delete callers.

**Interfaces:**
- Consumes: `WorkPlaneApplier` on whatever `Filesystem` the work context already has (`SftpFilesystem` included)
- Produces: no SSH apply compiler in repo

- [ ] **Step 1: Write a failing test that off-home apply does not need a script runner**

Add to `session_scheduler_init_test.dart` (package) or client projector tests: homeFs has `/home-tp/identities-runtime/x/cursor/a.json` content `{"k":1}`; plugin contributes `copyFile` or symlink that projector materializes or links; workFs after init has the projected path under `/work-tp`. No SSH.

If a client test still constructs `ManifestExecutor.flush` with `sshProfileId` and asserts script contents, change it to assert work filesystem state instead **before** deleting the compiler (test fails on missing assertion), then delete compiler so the old assertion cannot compile.

- [ ] **Step 2: Run tests to see old compiler tests fail or still pass for the wrong reason**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart \
  test/services/launch/apply_plan_ssh_compiler_test.dart
```

- [ ] **Step 3: Delete compiler; always applier**

`ManifestExecutor.flush` after `buildApplyPlan`:

```dart
await WorkPlaneApplier(
  fs: targetFs,
  blobs: built.blobs,
  workRoot: effectiveWorkRoot,
).apply(built.plan);
```

Remove `runner != null && !sameHost` branch, `compileApplyPlanForSsh`, and unused SSH runner fields if nothing else needs them. If `SshWorkPlaneScriptRunner` is only used for flush, leave it for `afterManifestFlush` in the client adapter (Task 6 `onAfterApply`) until that adapter stops using `remoteRunner`. **Do not** pass `WorkPlaneScriptRunner` into `teampilot_scheduler`.

- [ ] **Step 4: Run tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart \
  test/services/launch/
cd /home/hhoa/git/hhoa/teampilot/client/packages/teampilot_scheduler && dart test
```

Expected: PASS. No references to `compileApplyPlanForSsh`.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(launch): apply work plane through Filesystem and drop SSH bash compiler

EOF
)"
```

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| `teampilot_fs` | 1 |
| `teampilot_apply` | 2 |
| DTO + plugin interfaces, no Flutter models | 3 |
| Layout, manifest, projector in scheduler; no AppLogger | 4 |
| `SessionScheduler.init` order + `SessionInitException` | 5 |
| Client injects plugins, maps models, PTY still in app | 6 |
| Work plane is just Filesystem; delete bash compiler | 7 |
| `teampilot-apply` binary | non-goal |
| CLI implementations stay in app | 6 adapter |
| No auto-rollback | 5 (exceptions only) |

## Execution notes

Tasks 1–2 are mechanical moves; keep shims so `package:teampilot/...` imports stay valid. Task 6 is the behavior cutover. Task 7 is safe only after Task 6 uses scheduler apply on the same `workContext.fs` already used for SFTP.
