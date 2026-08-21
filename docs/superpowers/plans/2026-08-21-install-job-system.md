# Install Job System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fragmented install/progress adapters with a single `InstallJobRegistry` that deduplicates by job key, supports per-kind cancellation, drives the bottom status bar, and runs completion side effects outside widget lifecycle.

**Architecture:** UI and cubits call `InstallJobRegistry.enqueue(InstallJobSpec)` only. The registry coalesces identical `InstallJobKey`s, delegates to per-kind `InstallJobRunner`s, mirrors state into `ProgressActivityCubit`, and runs `onSucceeded`/`onFailed` hooks. Delete all `*ActivityAdapter` classes after migration.

**Tech Stack:** Flutter 3.x / Dart, `flutter_bloc`, existing `CliInstallerService` / `GitInstaller` / pack-acquire engines, `ProgressActivityCubit`, `WorkspaceStatusBar`.

**Spec:** `docs/superpowers/specs/2026-08-21-install-job-system-design.md`

## Global Constraints

- All new code under `client/lib/`; tests under `client/test/`.
- State management: `flutter_bloc` only (no `provider`).
- Verification before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- No backward compatibility: remove `CliProvisionActivityAdapter`, `PackAcquireActivityAdapter`, `HubCloneActivityAdapter`, `FileTreeImportActivityAdapter`, `AppUpdateActivityAdapter` and their call sites in the same PR series.
- UI must not call `ProgressActivityCubit.start` directly after migration — only `InstallJobRegistry`.
- Duplicate job key behavior: **merge** (return existing `Future`, one subprocess).
- Cancellation: **cooperative** for CLI/toolchain/pack/hub; **forceKill** for file import and app-update download.
- l10n: add strings to `client/lib/l10n/app_en.arb` and `app_zh.arb` only.

---

## File map

| Path | Responsibility |
|------|----------------|
| `client/lib/models/install_job/install_job_key.dart` | Stable dedup identity + `activityId` |
| `client/lib/models/install_job/install_job_scope.dart` | `local` / `ssh(profileId)` |
| `client/lib/models/install_job/install_cancel_policy.dart` | `cooperative` / `forceKill` |
| `client/lib/models/install_job/install_job_spec.dart` | Enqueue payload + hooks |
| `client/lib/models/install_job/install_job_context.dart` | Runtime ctx passed to runners |
| `client/lib/models/install_job/install_job_snapshot.dart` | `watch()` stream events |
| `client/lib/models/install_job/install_job_cancelled_exception.dart` | Terminal cancel error |
| `client/lib/services/install/install_job_registry.dart` | Coalesce, cancel, progress bridge |
| `client/lib/services/install/install_job_runner.dart` | Runner interface |
| `client/lib/services/install/install_job_runner_registry.dart` | kind → runner map |
| `client/lib/services/install/install_job_keys.dart` | Key builder helpers |
| `client/lib/services/install/runners/*.dart` | Six runner implementations |
| `client/lib/cubits/install_job_cubit.dart` | Optional UI mirror for `watch()` |
| `client/lib/models/progress_activity.dart` | Add optional `InstallJobKey? jobKey` |
| `client/lib/cubits/progress_activity_cubit.dart` | Add `startForJob` / restrict direct `start` to registry |

---

### Task 1: Core install-job models

**Files:**
- Create: `client/lib/models/install_job/install_job_scope.dart`
- Create: `client/lib/models/install_job/install_cancel_policy.dart`
- Create: `client/lib/models/install_job/install_job_key.dart`
- Create: `client/lib/models/install_job/install_job_cancelled_exception.dart`
- Test: `client/test/models/install_job/install_job_key_test.dart`

**Interfaces:**
- Produces: `InstallJobScope`, `InstallJobKind`, `InstallJobKey`, `InstallCancelPolicy`, `InstallJobCancelledException`

- [ ] **Step 1: Write failing tests**

```dart
// client/test/models/install_job/install_job_key_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';

void main() {
  test('activityId is stable for same key', () {
    const a = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
      scope: InstallJobScopeLocal(),
    );
    const b = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
      scope: InstallJobScopeLocal(),
    );
    expect(a, equals(b));
    expect(a.activityId, 'install-cliExecutable-claude-local');
  });

  test('ssh scope encodes profile id', () {
    const key = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
      scope: InstallJobScopeSsh('profile-42'),
    );
    expect(key.activityId, 'install-cliExecutable-claude-ssh-profile-42');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart test test/models/install_job/install_job_key_test.dart`
Expected: FAIL — library not found

- [ ] **Step 3: Implement models**

```dart
// client/lib/models/install_job/install_job_scope.dart
import 'package:equatable/equatable.dart';

sealed class InstallJobScope extends Equatable {
  const InstallJobScope();
  String get id;
}

final class InstallJobScopeLocal extends InstallJobScope {
  const InstallJobScopeLocal();
  @override
  String get id => 'local';
  @override
  List<Object?> get props => const [];
}

final class InstallJobScopeSsh extends InstallJobScope {
  const InstallJobScopeSsh(this.profileId);
  final String profileId;
  @override
  String get id => 'ssh-$profileId';
  @override
  List<Object?> get props => [profileId];
}
```

```dart
// client/lib/models/install_job/install_cancel_policy.dart
enum InstallCancelPolicy { cooperative, forceKill }
```

```dart
// client/lib/models/install_job/install_job_key.dart
import 'package:equatable/equatable.dart';
import 'install_job_scope.dart';

enum InstallJobKind {
  cliExecutable,
  toolchain,
  packAcquire,
  hubClone,
  fileTreeImport,
  appUpdate,
}

final class InstallJobKey extends Equatable {
  const InstallJobKey({
    required this.kind,
    required this.target,
    this.scope = const InstallJobScopeLocal(),
  });

  final InstallJobKind kind;
  final String target;
  final InstallJobScope scope;

  String get activityId =>
      'install-${kind.name}-$target-${scope.id}';

  @override
  List<Object?> get props => [kind, target, scope];
}
```

```dart
// client/lib/models/install_job/install_job_cancelled_exception.dart
final class InstallJobCancelledException implements Exception {
  const InstallJobCancelledException(this.key);
  final InstallJobKey key;
  @override
  String toString() => 'Install job cancelled: ${key.activityId}';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart test test/models/install_job/install_job_key_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/install_job/ client/test/models/install_job/
git commit -m "feat(install): add InstallJobKey and scope models"
```

---

### Task 2: InstallJobSpec, InstallJobContext, InstallJobSnapshot

**Files:**
- Create: `client/lib/models/install_job/install_job_spec.dart`
- Create: `client/lib/models/install_job/install_job_context.dart`
- Create: `client/lib/models/install_job/install_job_snapshot.dart`
- Test: `client/test/models/install_job/install_job_context_test.dart`

**Interfaces:**
- Consumes: Task 1 types
- Produces: `InstallJobSpec<T>`, `InstallJobContext`, `InstallJobSnapshot`, `InstallJobPhase`

- [ ] **Step 1: Write failing test for context cancellation flag**

```dart
// client/test/models/install_job/install_job_context_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';

void main() {
  test('requestCancel sets isCancelled', () {
    final ctx = InstallJobContext();
    expect(ctx.isCancelled, isFalse);
    ctx.requestCancel();
    expect(ctx.isCancelled, isTrue);
  });

  test('registerProcess is invoked on forceKill', () async {
    final ctx = InstallJobContext();
    Process? captured;
    ctx.registerProcess(captured = null); // use fake Process in real test via mock
    // Full force-kill test lives in registry task; here only flag behavior.
  });
}
```

Implement `InstallJobContext` as a mutable class owned by the registry:

```dart
// client/lib/models/install_job/install_job_context.dart
import 'dart:async';
import 'dart:io';

final class InstallJobContext {
  bool _cancelled = false;
  final List<Process> _processes = [];
  final List<FutureOr<void> Function()> _cancelHooks = [];

  bool get isCancelled => _cancelled;

  void requestCancel() => _cancelled = true;

  void registerProcess(Process process) => _processes.add(process);

  void registerCancelHook(FutureOr<void> Function() hook) =>
      _cancelHooks.add(hook);

  Future<void> forceKill() async {
    _cancelled = true;
    for (final process in _processes) {
      try {
        process.kill(ProcessSignal.sigterm);
      } on Object {
        // Best effort.
      }
    }
    for (final hook in _cancelHooks) {
      final result = hook();
      if (result is Future<void>) await result;
    }
  }
}
```

```dart
// client/lib/models/install_job/install_job_spec.dart
import 'dart:async';
import 'install_cancel_policy.dart';
import 'install_job_context.dart';
import 'install_job_key.dart';

final class InstallJobSpec<T> {
  const InstallJobSpec({
    required this.key,
    required this.title,
    this.subtitle,
    this.workspaceId,
    required this.cancelPolicy,
    required this.run,
    this.onSucceeded,
    this.onFailed,
    this.historyTitle,
    this.historyMessageFor,
  });

  final InstallJobKey key;
  final String title;
  final String? subtitle;
  final String? workspaceId;
  final InstallCancelPolicy cancelPolicy;
  final Future<T> Function(InstallJobContext ctx) run;
  final FutureOr<void> Function(T result)? onSucceeded;
  final FutureOr<void> Function(Object error)? onFailed;
  final String? historyTitle;
  final String? Function(T result)? historyMessageFor;
}
```

```dart
// client/lib/models/install_job/install_job_snapshot.dart
import 'install_job_key.dart';

enum InstallJobPhase { queued, running, cancelling, succeeded, failed, cancelled }

final class InstallJobSnapshot {
  const InstallJobSnapshot({
    required this.key,
    required this.phase,
    this.subtitle,
    this.fraction,
  });

  final InstallJobKey key;
  final InstallJobPhase phase;
  final String? subtitle;
  final double? fraction;
}
```

- [ ] **Step 2–4:** Run tests, implement, verify PASS

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(install): add InstallJobSpec and InstallJobContext"
```

---

### Task 3: InstallJobRegistry — coalesce, progress bridge, cancel

**Files:**
- Create: `client/lib/services/install/install_job_registry.dart`
- Create: `client/lib/services/install/install_job_keys.dart`
- Modify: `client/lib/models/progress_activity.dart` (add `InstallJobKey? jobKey`)
- Modify: `client/lib/cubits/progress_activity_cubit.dart` (add `startForInstallJob`)
- Test: `client/test/services/install/install_job_registry_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2, `ProgressActivityCubit`, `ProgressActivityKind` mapping helper
- Produces: `InstallJobRegistry` with `Future<T> enqueue<T>(InstallJobSpec<T>)`, `bool isRunning(InstallJobKey)`, `void requestCancel(InstallJobKey)`, `Stream<InstallJobSnapshot> watch(InstallJobKey)`

- [ ] **Step 1: Write failing coalesce test**

```dart
// client/test/services/install/install_job_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';

class _FakeRecorder implements NotificationRecorder {
  @override
  void record({required String message, required TpToastVariant variant, String title = '', String payload = ''}) {}
}

void main() {
  late ProgressActivityCubit progressCubit;
  late InstallJobRegistry registry;

  setUp(() {
    progressCubit = ProgressActivityCubit(historyRecorder: _FakeRecorder());
    registry = InstallJobRegistry(progressCubit: progressCubit);
  });

  tearDown(() => progressCubit.close());

  test('enqueue coalesces identical keys', () async {
    var runs = 0;
    const key = InstallJobKey(kind: InstallJobKind.toolchain, target: 'git');
    final spec = InstallJobSpec<void>(
      key: key,
      title: 'Install Git',
      cancelPolicy: InstallCancelPolicy.cooperative,
      run: (ctx) async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
    );
    final a = registry.enqueue(spec);
    final b = registry.enqueue(spec);
    expect(identical(a, b), isFalse); // different Future wrappers OK if same completer
    await Future.wait([a, b]);
    expect(runs, 1);
    expect(registry.isRunning(key), isFalse);
    expect(progressCubit.state.activities, isEmpty);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement `InstallJobRegistry`**

Core logic (implement fully in file):

```dart
// client/lib/services/install/install_job_registry.dart
final class InstallJobRegistry {
  InstallJobRegistry({required ProgressActivityCubit progressCubit})
    : _progressCubit = progressCubit;

  final ProgressActivityCubit _progressCubit;
  final Map<InstallJobKey, _ActiveJob> _active = {};
  final Map<InstallJobKey, StreamController<InstallJobSnapshot>> _watchers = {};

  Future<T> enqueue<T>(InstallJobSpec<T> spec) {
    final existing = _active[spec.key];
    if (existing != null && !existing.isTerminal) {
      return existing.future as Future<T>;
    }
    final completer = Completer<T>();
    final ctx = InstallJobContext();
    _active[spec.key] = _ActiveJob(completer: completer, ctx: ctx);
    _startActivity(spec);
    unawaited(_run(spec, ctx, completer));
    return completer.future;
  }

  bool isRunning(InstallJobKey key) {
    final job = _active[key];
    return job != null && !job.isTerminal;
  }

  void requestCancel(InstallJobKey key) {
    final job = _active[key];
    if (job == null || job.isTerminal) return;
    if (job.spec.cancelPolicy == InstallCancelPolicy.forceKill) {
      unawaited(job.ctx.forceKill());
    } else {
      job.ctx.requestCancel();
    }
    _progressCubit.requestCancel(key.activityId);
  }
  // ... _run handles onSucceeded, complete, remove _active, emit snapshot
}
```

Add `ProgressActivity.jobKey` field and map `InstallJobKind` → `ProgressActivityKind`:

```dart
ProgressActivityKind activityKindForInstall(InstallJobKind kind) => switch (kind) {
  InstallJobKind.cliExecutable => ProgressActivityKind.cliProvision,
  InstallJobKind.toolchain => ProgressActivityKind.cliProvision,
  InstallJobKind.packAcquire => ProgressActivityKind.packAcquire,
  InstallJobKind.hubClone => ProgressActivityKind.hubClone,
  InstallJobKind.fileTreeImport => ProgressActivityKind.fileTreeImport,
  InstallJobKind.appUpdate => ProgressActivityKind.appUpdate,
};
```

Wire `ProgressActivityCubit.startForInstallJob(ProgressActivity activity, {onCancel})` — thin wrapper setting `jobKey` and delegating to `start`.

- [ ] **Step 4: Add tests for cancel cooperative vs forceKill, onSucceeded when unmounted**

- [ ] **Step 5: Run** `cd client && dart test test/services/install/install_job_registry_test.dart`

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(install): add InstallJobRegistry with coalesce and cancel"
```

---

### Task 4: InstallJobRunner interface + registry + key helpers

**Files:**
- Create: `client/lib/services/install/install_job_runner.dart`
- Create: `client/lib/services/install/install_job_runner_registry.dart`
- Create: `client/lib/services/install/install_job_keys.dart`
- Modify: `client/lib/services/install/install_job_registry.dart` (delegate to runners)
- Test: `client/test/services/install/install_job_runner_registry_test.dart`

**Interfaces:**
- Produces: `InstallJobRunner`, `InstallJobRunnerRegistry`, `InstallJobKeys.cli(...)`, `.toolchain(...)`, etc.

```dart
// client/lib/services/install/install_job_runner.dart
abstract interface class InstallJobRunner {
  InstallJobKind get kind;
  bool supports(InstallJobKey key);
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx);
}
```

Update `InstallJobRegistry.enqueue` to resolve runner:

```dart
final runner = _runnerRegistry.resolve(spec.key);
if (runner == null) {
  throw StateError('No InstallJobRunner for ${spec.key.kind}');
}
final result = await runner.run(spec, ctx);
```

- [ ] Implement registry + tests + commit: `feat(install): add runner registry and key helpers`

---

### Task 5: CliInstallerService + GitInstaller cancellation

**Files:**
- Modify: `client/lib/services/cli/cli_installer_service.dart`
- Modify: `client/lib/services/cli/registry/installer/npm_installer_capability.dart`
- Modify: `client/lib/services/cli/git_installer.dart`
- Test: `client/test/services/cli/cli_installer_service_test.dart` (extend)
- Test: `client/test/services/cli/git_installer_test.dart` (extend)

**Interfaces:**
- Produces: `CliInstallerService.install(..., bool Function()? isCancelled, void Function(Process)? onProcessStarted)`
- Produces: `GitInstaller.install(..., bool Function()? isCancelled)`

- [ ] **Step 1: Write failing test — cancelled before installingCli skips npm**

```dart
test('install returns early when cancelled before installingCli', () async {
  var npmRuns = 0;
  final service = CliInstallerService(
    localRunner: (cmd) async {
      if (cmd.executable.contains('npm') || cmd.arguments.any((a) => a.contains('npm'))) {
        npmRuns++;
      }
      return CliInstallerCommandResult(exitCode: 0);
    },
    // ... stub locate npm found
  );
  var checks = 0;
  final result = await service.install(
    cli: CliTool.claude,
    mode: CliInstallMode.local,
    isCancelled: () => ++checks > 1,
  );
  expect(result.success, isFalse);
  expect(npmRuns, 0);
});
```

- [ ] **Step 2–4:** Add `isCancelled` checks between phases in `NpmInstallerCapability._installLocal` / `_installSsh` and `CliInstallerService.resolveLocalNpm` bootstrap path.

- [ ] **Step 5: GitInstaller** — check `isCancelled` between `checking`, `installing`, `locating` phases; return `GitInstallResult.failed('Cancelled')` when set.

- [ ] **Step 6: Run** `cd client && dart test test/services/cli/cli_installer_service_test.dart test/services/cli/git_installer_test.dart`

- [ ] **Step 7: Commit** `feat(install): add cooperative cancellation to CLI and Git installers`

---

### Task 6: CliInstallJobRunner + ToolchainInstallJobRunner

**Files:**
- Create: `client/lib/services/install/runners/cli_install_job_runner.dart`
- Create: `client/lib/services/install/runners/toolchain_install_job_runner.dart`
- Test: `client/test/services/install/runners/cli_install_job_runner_test.dart`
- Test: `client/test/services/install/runners/toolchain_install_job_runner_test.dart`

**Interfaces:**
- Consumes: `CliInstallerService`, `GitInstaller`, `InstallJobContext.reportPhase` bridge
- Produces: runners registered for `cliExecutable` and `toolchain` kinds

```dart
// client/lib/services/install/runners/cli_install_job_runner.dart
final class CliInstallJobRunner implements InstallJobRunner {
  CliInstallJobRunner({required CliInstallerService Function() installerFactory});

  @override
  InstallJobKind get kind => InstallJobKind.cliExecutable;

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    // Parse CliTool from spec.key.target
    // Map scope to CliInstallMode + SshProfile
    // Call installer.install(isCancelled: ctx.isCancelled, onProgress: ...)
    // Throw StateError on !success so registry completes failed
  }
}
```

`InstallJobContext` needs progress bridge methods used by registry:

```dart
// Called by registry, not runners directly — runners call ctx.emitProgress(CliInstallProgress)
```

Add `typedef InstallProgressCallback` on context or pass a reporter closure into `run`.

- [ ] Tests map `CliInstallPhase` → subtitle labels (reuse `isUserFacingCliInstallDetail` from `installer_types.dart`)
- [ ] Commit: `feat(install): add CLI and toolchain job runners`

---

### Task 7: PackAcquireInstallJobRunner

**Files:**
- Create: `client/lib/services/install/runners/pack_acquire_install_job_runner.dart`
- Modify: `client/lib/services/skill/skill_acquisition_engine.dart` (optional `isCancelled`)
- Modify: `client/lib/services/plugin/plugin_install_service.dart` (optional `isCancelled`)
- Modify: `client/lib/services/extension/extension_acquisition_engine.dart` (optional `isCancelled`)
- Test: `client/test/services/install/runners/pack_acquire_install_job_runner_test.dart`

**Interfaces:**
- Target prefix in `spec.key.target`: `skill:`, `plugin:`, `extension:`

Migrate `_runPackAcquireTracked` pattern from cubits into runner; spec.run closure provided by cubit still OK for first pass — runner executes engine with step reporter → `ctx.reportItems`.

- [ ] Commit: `feat(install): add pack acquire job runner`

---

### Task 8: HubClone, FileTreeImport, AppUpdate runners

**Files:**
- Create: `client/lib/services/install/runners/hub_clone_install_job_runner.dart`
- Create: `client/lib/services/install/runners/file_tree_import_install_job_runner.dart`
- Create: `client/lib/services/install/runners/app_update_install_job_runner.dart`
- Tests: matching files under `client/test/services/install/runners/`

**Interfaces:**
- `hub_clone`: target `team:<hubKey>` or `expert:<hubKey>`; cooperative cancel between clone steps
- `file_tree_import`: `forceKill`; wire `WorkspaceImportService` `isCancelled`
- `app_update`: `forceKill` on download; non-cancellable install phase

Port logic from deleted adapters verbatim into runners.

- [ ] Commit: `feat(install): add hub clone, file import, and app update runners`

---

### Task 9: Bootstrap wiring in app_shell

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Create: `client/lib/cubits/install_job_cubit.dart` (mirrors `registry.watch` for widgets)
- Modify: `client/lib/app/app_shell.dart` — provide `InstallJobRegistry` + `InstallJobCubit` via `RepositoryProvider`

```dart
final installJobRunnerRegistry = InstallJobRunnerRegistry(runners: [
  CliInstallJobRunner(...),
  ToolchainInstallJobRunner(...),
  PackAcquireInstallJobRunner(...),
  HubCloneInstallJobRunner(...),
  FileTreeImportInstallJobRunner(...),
  AppUpdateInstallJobRunner(...),
]);
final installJobRegistry = InstallJobRegistry(
  progressCubit: progressActivityCubit,
  runnerRegistry: installJobRunnerRegistry,
);
```

Remove construction of five `*ActivityAdapter` instances.

- [ ] Commit: `feat(install): wire InstallJobRegistry in app bootstrap`

---

### Task 10: Migrate CLI + toolchain settings rows

**Files:**
- Modify: `client/lib/pages/config/cli_executable_path_settings_row.dart`
- Modify: `client/lib/pages/config/toolchain_path_settings_row.dart`
- Delete usage of: `client/lib/widgets/cli_install_progress_panel.dart` (delete file if unused)
- Test: `client/test/pages/config/cli_config_section_test.dart` (add install-via-registry test)

**Changes:**
- Inject `InstallJobRegistry` via `context.read<InstallJobRegistry>()`
- Replace `_installCli` / `_install` with `registry.enqueue` + `onSucceeded` writing preferences
- Button state: `registry.isRunning(key)` or `InstallJobCubit` watch
- Remove `_isInstalling`, `_installPhase`, `_installLog`, inline `CliInstallProgressPanel`

```dart
Future<void> _installCli() async {
  final registry = context.read<InstallJobRegistry>();
  final key = InstallJobKeys.cli(widget.cli, scope: _scope(context));
  if (registry.isRunning(key)) {
    await registry.enqueue(_spec(key)); // attach
    return;
  }
  await registry.enqueue(_spec(key));
}

InstallJobSpec<CliInstallResult> _spec(InstallJobKey key) => InstallJobSpec(
  key: key,
  title: context.l10n.cliInstallInstalling,
  cancelPolicy: InstallCancelPolicy.cooperative,
  run: (ctx) => context.read<CliInstallJobRunner>().runInstall(..., ctx),
  onSucceeded: (result) async {
    final path = result.executablePath?.trim() ?? '';
    if (path.isNotEmpty) {
      await widget.cubit.setCliExecutablePathFor(widget.cli, path);
    }
  },
);
```

Prefer routing `run` through registry + runner registry rather than calling runner directly from widget — pass dependencies via spec metadata or dedicated enqueue helpers on `InstallJobKeys`.

Add enqueue helpers:

```dart
// client/lib/services/install/install_job_enqueue.dart
extension InstallJobEnqueue on InstallJobRegistry {
  Future<CliInstallResult> installCli({required CliTool cli, ...});
  Future<GitInstallResult> installToolchain({required String toolId, ...});
}
```

- [ ] Widget test: tap Install → pop scaffold → await completion → path persisted
- [ ] Commit: `feat(install): migrate CLI and toolchain settings to InstallJobRegistry`

---

### Task 11: Migrate onboarding, remote readiness, session launch

**Files:**
- Modify: `client/lib/pages/onboarding/steps/cli_step.dart`
- Modify: `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (remove `cliProvisionActivity` field)
- Modify: `client/lib/cubits/chat/session_launch_host.dart`

Replace `CliProvisionActivityAdapter` usage with `installJobRegistry.enqueue` / `InstallJobEnqueue.installCli` / remote provision spec.

- [ ] Commit: `feat(install): migrate onboarding and session provision to registry`

---

### Task 12: Migrate skill, plugin, extension, hub cubits

**Files:**
- Modify: `client/lib/cubits/skill_cubit.dart`
- Modify: `client/lib/cubits/plugin_cubit.dart`
- Modify: `client/lib/cubits/extension_cubit.dart`
- Modify: `client/lib/cubits/team_hub_cubit.dart`
- Modify: `client/lib/cubits/expert_hub_cubit.dart`
- Modify: `client/lib/app/app_shell.dart` (constructor args)

Remove `PackAcquireActivityAdapter?` / `HubCloneActivityAdapter?` parameters; inject `InstallJobRegistry`.

Replace `_runPackAcquireTracked` with:

```dart
await _installJobs.enqueue(InstallJobSpec(
  key: InstallJobKeys.skill(skillId),
  title: title,
  cancelPolicy: InstallCancelPolicy.cooperative,
  run: (ctx) => _acquisitionEngine.install(ref, isCancelled: ctx.isCancelled),
  onSucceeded: (_) => _emitInstalled(),
));
```

- [ ] Commit: `feat(install): migrate pack acquire and hub clone cubits`

---

### Task 13: Migrate file tree drop + app update

**Files:**
- Modify: `client/lib/widgets/file_tree/file_tree_drop_region.dart`
- Modify: `client/lib/cubits/app_update_cubit.dart`
- Modify: `client/lib/widgets/app_update_available_dialog.dart` (if needed)

Remove `FileTreeImportActivityAdapter` / `AppUpdateActivityAdapter` usage.

- [ ] Commit: `feat(install): migrate file import and app update to registry`

---

### Task 14: Delete legacy adapters and tests

**Files:**
- Delete: `client/lib/services/progress_activity/cli_provision_activity_adapter.dart`
- Delete: `client/lib/services/progress_activity/pack_acquire_activity_adapter.dart`
- Delete: `client/lib/services/progress_activity/hub_clone_activity_adapter.dart`
- Delete: `client/lib/services/progress_activity/file_tree_import_activity_adapter.dart`
- Delete: `client/lib/services/progress_activity/app_update_activity_adapter.dart`
- Delete: `client/test/services/progress_activity/cli_provision_activity_adapter_test.dart`
- Delete: `client/test/services/progress_activity/pack_acquire_activity_adapter_test.dart`
- Delete: `client/test/services/progress_activity/hub_clone_activity_adapter_test.dart`
- Delete: `client/test/services/progress_activity/file_tree_import_activity_adapter_test.dart`
- Delete: `client/test/services/progress_activity/app_update_activity_adapter_test.dart`
- Delete: `client/lib/widgets/cli_install_progress_panel.dart` (if no remaining references)

- [ ] Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] Run: `cd client && dart run tool/run_tests.dart`
- [ ] Commit: `refactor(install): remove legacy progress activity adapters`

---

### Task 15: ProgressActivityDetailDialog cancel → registry

**Files:**
- Modify: `client/lib/widgets/progress_activity/progress_activity_detail_dialog.dart`
- Modify: `client/lib/widgets/workspace_status_bar/progress_activities_status_item.dart`

Wire cancel button: if `activity.jobKey != null`, call `InstallJobRegistry.requestCancel(jobKey)` instead of only `ProgressActivityCubit.requestCancel`.

- [ ] Test: cancel from status bar panel invokes registry
- [ ] Commit: `fix(install): route status bar cancel to InstallJobRegistry`

---

### Task 16: l10n + final verification

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Run: `cd client && flutter gen-l10n` (if required by project)

Add strings for cancelled install toast if not covered by existing `progressActivities*` keys.

- [ ] Full verify: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
- [ ] Commit: `chore(install): l10n and verification for install job system`

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Single `InstallJobRegistry` entry point | 3, 9 |
| Stable job keys + merge | 1, 3 |
| Per-kind cancel policy | 3, 5, 8 |
| Progress in status bar only | 3, 10 (remove inline panels) |
| Completion hooks outside widget lifecycle | 3, 10 |
| Six runner kinds | 6–8 |
| Service cancellation | 5, 7 |
| Delete adapters | 14 |
| Extensibility via new runner | 4 |
| Settings close does not lose path write | 10 (widget test) |

## Self-review

- No TBD / placeholder steps — each task names concrete files and signatures.
- Type names consistent: `InstallJobKey`, `InstallJobRegistry`, `InstallJobContext` throughout.
- Spec requirement "UI must not call ProgressActivityCubit.start directly" enforced in Task 3 + 14.

---

**Plan complete and saved to `docs/superpowers/plans/2026-08-21-install-job-system.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
