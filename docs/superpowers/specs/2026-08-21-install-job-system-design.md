# Install Job System

**Date:** 2026-08-21  
**Status:** Approved design — ready for implementation plan

## Summary

TeamPilot runs many long-running install and acquisition flows (CLI executables,
toolchain binaries, skills, plugins, extensions, hub clones, workspace file
imports, app updates). Today these flows are split across widget-local state,
thin `*ActivityAdapter` wrappers, and direct service calls. Progress sometimes
appears in inline panels, sometimes in the bottom status bar, and closing a
settings dialog can orphan an in-flight install.

This design replaces that fragmentation with a single **Install Job System**:

```text
UI / cubit entry points
    -> InstallJobRegistry.enqueue(spec)
    -> InstallJobRunner (per kind)
    -> underlying service (CliInstallerService, GitInstaller, …)
    -> ProgressActivityCubit (presentation only)
    -> WorkspaceStatusBar + detail dialog
```

Every long-running install is an `InstallJob` with a stable **job key**, shared
**Future coalescing**, typed **cancellation policy**, and **completion hooks**
that run outside widget lifecycle.

## Problem

| Symptom | Root cause |
|---------|------------|
| Closing CLI settings mid-install loses UI and path persistence | Install lifecycle bound to `StatefulWidget`, not app-global |
| Duplicate `npm install -g` if user clicks Install twice | No deduplication key |
| Inconsistent cancel behavior | Some flows cancellable, others not; no policy per kind |
| Two progress UIs (inline panel + status bar) | Settings rows bypass `ProgressActivityCubit` |
| Adapters duplicate orchestration | `CliProvisionActivityAdapter`, `PackAcquireActivityAdapter`, etc. each reimplement start/update/complete |

## Goals

- **One entry point** for all long-running installs: `InstallJobRegistry`.
- **Stable job keys** so the same logical install coalesces to one in-flight
  `Future` (merge / attach — never spawn duplicate subprocesses).
- **Cancellation policies** per job kind (cooperative vs force-kill).
- **Global progress** in the existing bottom status bar for every job; remove
  inline install progress panels from settings and similar surfaces.
- **Completion side effects** (persist CLI path, refresh cubits) run in job
  completion hooks, independent of whether the originating UI is mounted.
- **Extensibility**: adding a new install kind = new `InstallJobRunner` +
  `InstallJobKind` enum value + key builder; no new adapter class.
- **Testability**: registry, runners, and cancellation are unit-testable without
  widgets.

## Non-goals

- Persist install job history across app restarts (notification history via
  `NotificationRecorder` on terminal outcomes is sufficient).
- Queue installs globally (only dedupe identical keys; different keys may run
  concurrently).
- Redesign the status bar visual language — reuse `ProgressActivitiesStatusItem`.
- Change what gets installed or CLI registry capabilities.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Scope | All long-running installs (CLI, toolchain, pack acquire, hub clone, file import, app update) |
| Duplicate job key | **Merge** — return existing `Future`, single subprocess |
| Cancellation | **Per-kind policy** (see below) |
| Backward compatibility | **None** — delete `*ActivityAdapter` classes after migration |

## Architecture

### Layering

```text
┌─────────────────────────────────────────────────────────────┐
│  pages/ / cubits/  (trigger only; no install orchestration) │
└───────────────────────────┬─────────────────────────────────┘
                            │ InstallJobSpec
┌───────────────────────────▼─────────────────────────────────┐
│  InstallJobRegistry                                         │
│  - enqueue / attach / cancel / isRunning / watch(key)         │
│  - Map<InstallJobKey, _ActiveJob>                           │
└───────────────┬─────────────────────────────┬─────────────────┘
                │ delegates run               │ mirrors state
┌───────────────▼──────────────┐   ┌──────────▼────────────────┐
│  InstallJobRunnerRegistry    │   │  ProgressActivityCubit    │
│  kind -> InstallJobRunner    │   │  (presentation only)      │
└───────────────┬──────────────┘   └──────────┬────────────────┘
                │                              │
┌───────────────▼──────────────┐   ┌──────────▼────────────────┐
│  InstallJobRunner impls      │   │  WorkspaceStatusBar       │
│  CliInstallJobRunner, …      │   │  ProgressActivityDetail   │
└───────────────┬──────────────┘   └───────────────────────────┘
                │
┌───────────────▼──────────────┐
│  Services (unchanged API     │
│  surface + cancellation)     │
└──────────────────────────────┘
```

`ProgressActivityCubit` becomes a **view model** driven exclusively by
`InstallJobRegistry`. UI code must not call `ProgressActivityCubit.start`
directly.

### Core types

```dart
/// Canonical identity for deduplication. Equality is value-based.
final class InstallJobKey extends Equatable {
  const InstallJobKey({
    required this.kind,
    required this.target,
    this.scope = InstallJobScope.local,
  });

  final InstallJobKind kind;
  final String target;
  final InstallJobScope scope;

  /// Stable activity id for ProgressActivityCubit and status bar.
  String get activityId => 'install-${kind.name}-$target-${scope.id}';
}

enum InstallJobKind {
  cliExecutable,
  toolchain,
  packAcquire,
  hubClone,
  fileTreeImport,
  appUpdate,
}

/// Where the install runs.
sealed class InstallJobScope {
  const InstallJobScope();
  String get id;
}
final class InstallJobScopeLocal extends InstallJobScope { … }
final class InstallJobScopeSsh extends InstallJobScope { final String profileId; … }

enum InstallCancelPolicy {
  /// Check [InstallJobContext.isCancelled] between phases; let current
  /// subprocess finish; do not start next phase. Used for CLI/Git/Node.
  cooperative,

  /// Kill active download/stream/process immediately. Used for file import
  /// and app-update download.
  forceKill,
}

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

/// Passed into every runner; registry owns cancellation + progress bridge.
final class InstallJobContext {
  bool get isCancelled;
  void reportPhase(String label, {String? detail, double? fraction});
  void reportItems({required int completed, required int total});
  void registerProcess(Process process); // forceKill
  void registerCancelHook(FutureOr<void> Function() hook);
}
```

### Job key conventions

| Flow | `kind` | `target` | `scope` |
|------|--------|----------|---------|
| CLI executable | `cliExecutable` | `CliTool.value` e.g. `claude` | `local` or `ssh:<profileId>` |
| Toolchain (git/node) | `toolchain` | `git` / `node` | `local` or `ssh:<profileId>` |
| Skill install | `packAcquire` | `skill:<skillId>` | `local` |
| Plugin install | `packAcquire` | `plugin:<pluginId>` | `local` |
| Extension install | `packAcquire` | `extension:<extId>` | `local` |
| Hub team clone | `hubClone` | `team:<hubKey>` | `local` |
| Expert hub clone | `hubClone` | `expert:<hubKey>` | `local` |
| File tree import | `fileTreeImport` | `<workspaceId>:<planHash>` | workspace id in spec |
| App update | `appUpdate` | `<version>` | `local` |

`planHash` is a stable hash of `ImportPlan` identity (workspace + dest + file
count + max bytes) so repeated drops of the same plan coalesce.

### InstallJobRegistry

```dart
abstract interface class InstallJobRegistry {
  /// Enqueue or attach. Never throws for duplicate key while running.
  Future<T> enqueue<T>(InstallJobSpec<T> spec);

  bool isRunning(InstallJobKey key);

  void requestCancel(InstallJobKey key);

  /// Emits terminal + in-flight updates for UI that wants local spinners.
  Stream<InstallJobSnapshot> watch(InstallJobKey key);
}
```

**Enqueue algorithm:**

1. If `_active[key]` exists and not terminal → return existing `Future<T>`.
2. Create `InstallJobContext` with cancel flag + progress bridge.
3. `ProgressActivityCubit.start(activity from key, cancellable: policy != none)`.
4. Resolve `InstallJobRunner` for `key.kind`; `await runner.run(spec, ctx)`.
5. On success: run `onSucceeded`, `complete(succeeded)`.
6. On cancel: `complete(cancelled)`.
7. On error: run `onFailed`, `complete(failed)`.
8. Remove from `_active` in `finally`.

**Cancel algorithm:**

1. Set `ctx._cancelled = true`.
2. If `forceKill`: invoke registered process kills / stream cancel hooks.
3. If `cooperative`: runner checks `isCancelled` between phases only.
4. `ProgressActivityCubit.requestCancel(activityId)` → phase `cancelling`.

### InstallJobRunner

```dart
abstract interface class InstallJobRunner {
  InstallJobKind get kind;
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx);
}
```

Registered implementations (bootstrap in `app_shell.dart`):

| Runner | Delegates to | Cancel policy |
|--------|--------------|---------------|
| `CliInstallJobRunner` | `CliInstallerService.install` | cooperative |
| `ToolchainInstallJobRunner` | `GitInstaller` / node bootstrap | cooperative |
| `PackAcquireInstallJobRunner` | skill/plugin/extension engines | cooperative |
| `HubCloneInstallJobRunner` | `TeamCloneService` / expert clone | cooperative |
| `FileTreeImportInstallJobRunner` | `WorkspaceImportService` | forceKill |
| `AppUpdateInstallJobRunner` | `AppUpdateService` download/install | forceKill (download only) |

Runners are thin: map service progress callbacks → `ctx.reportPhase` /
`ctx.reportItems`, pass `ctx.isCancelled` into services.

### Service cancellation contracts

**CliInstallerService** (and remote preflight path):

```dart
Future<CliInstallResult> install({
  …,
  bool Function()? isCancelled,
  void Function(Process process)? onProcessStarted,
});
```

Check `isCancelled` before each `CliInstallPhase`. For streaming local npm
install, register process via `onProcessStarted` so `forceKill` can kill if ever
used for CLI (default remains cooperative — kill only between phases).

**GitInstaller:** same `isCancelled` between phases.

**Pack acquire engines:** check `isCancelled` between download/extract/install
steps; register HTTP cancel tokens where applicable.

**WorkspaceImportService:** existing `isCancelled` callback — wire through runner.

**AppUpdateService:** existing download cancel — wire through runner; flip to
non-cancellable when entering OS install phase.

### ProgressActivity model changes

Add optional `InstallJobKey? jobKey` on `ProgressActivity` for lookup and
tests. `id` **must** equal `jobKey.activityId` for install jobs.

Map `InstallJobKind` → `ProgressActivityKind` (1:1 except `packAcquire` and
`toolchain` which already have kinds).

Remove direct use of:

- `CliProvisionActivityAdapter`
- `PackAcquireActivityAdapter`
- `HubCloneActivityAdapter`
- `FileTreeImportActivityAdapter`
- `AppUpdateActivityAdapter`

Delete these files after migration.

### UI contract

**Trigger surfaces** (settings rows, onboarding, remote readiness, cubits):

```dart
await installJobRegistry.enqueue(
  InstallJobSpec(
    key: InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: cli.value,
      scope: isRemote
          ? InstallJobScopeSsh(profileId)
          : const InstallJobScopeLocal(),
    ),
    title: l10n.cliInstallTitle(cliLabel),
    cancelPolicy: InstallCancelPolicy.cooperative,
    run: (ctx) => cliInstallJobRunner.execute(cli, ctx, …),
    onSucceeded: (result) => sessionPreferencesCubit
        .setCliExecutablePathFor(cli, result.executablePath!),
  ),
);
```

**Local button state:**

```dart
final running = installJobRegistry.isRunning(key);
// or BlocBuilder on a thin InstallJobCubit that mirrors registry snapshots
```

**Remove:**

- `CliInstallProgressPanel` from settings/toolchain rows
- Widget-local `_isInstalling`, `_installPhase`, `_installLog`
- Duplicate toasts on success (registry → `ProgressActivityCubit.complete` →
  `NotificationRecorder` is the single user-visible outcome; callers may skip
  extra `AppToast` unless immediate inline feedback is required)

**Keep:**

- `ProgressActivitiesStatusItem` in `WorkspaceStatusBar`
- `ProgressActivityDetailDialog` for log/detail view
- `ProgressActivityTile` cancel button → `registry.requestCancel(key)`

### Completion side effects

`onSucceeded` / `onFailed` run inside registry `try/finally`, **after** the
runner returns and **before** activity removal. They must not depend on
`BuildContext`.

Examples:

| Job | `onSucceeded` |
|-----|----------------|
| CLI settings install | `SessionPreferencesCubit.setCliExecutablePathFor` |
| Git toolchain | `SessionPreferencesCubit.setToolchainPath` |
| Skill/plugin/extension | cubit `loadAll` / state refresh |
| Hub clone | navigate or refresh hub cubit (caller-provided hook) |
| File import | refresh file tree store |

### Concurrency

- Same key: one runner, shared Future.
- Different keys: parallel allowed (e.g. install Claude + Codex simultaneously).
- Cancel of key A does not affect key B.

### Error handling

- Runner throws → `complete(failed)`, `onFailed`, Future completes with error.
- Cancel mid-run → terminal outcome `cancelled`, Future completes with
  `InstallJobCancelledException`.
- Attachors awaiting merged Future receive the same result/exception as the
  original enqueuer.

### Extensibility — adding a new install kind

1. Add `InstallJobKind` value.
2. Implement `InstallJobRunner`.
3. Register in `InstallJobRunnerRegistry` at bootstrap.
4. Add key builder helper on `InstallJobKeys` (e.g. `InstallJobKeys.cli(cli, scope)`).
5. Map to `ProgressActivityKind` if new icon needed in status bar.
6. Wire UI entry point to `enqueue` only.

No changes to `ProgressActivityCubit` or status bar widgets required.

## Migration map

| Current | After |
|---------|-------|
| `cli_executable_path_settings_row._installCli` | `InstallJobRegistry.enqueue` + `CliInstallJobRunner` |
| `toolchain_path_settings_row._install` | `ToolchainInstallJobRunner` |
| `onboarding/steps/cli_step.dart` | `enqueue` (drop dual adapter + local log) |
| `remote_cli_machine_readiness_panel` | `enqueue` |
| `session_shell_connector` remote provision | `enqueue` |
| `skill_cubit` / `plugin_cubit` / `extension_cubit` pack acquire | `PackAcquireInstallJobRunner` |
| `team_hub_cubit` / `expert_hub_cubit` clone | `HubCloneInstallJobRunner` |
| `file_tree_drop_region` import | `FileTreeImportInstallJobRunner` |
| `app_update_cubit` download | `AppUpdateInstallJobRunner` |
| `*_activity_adapter.dart` (5 files) | **Deleted** |

## File layout

```
client/lib/
  models/install_job/
    install_job_key.dart
    install_job_spec.dart
    install_job_context.dart
    install_cancel_policy.dart
    install_job_snapshot.dart
  services/install/
    install_job_registry.dart
    install_job_runner.dart
    install_job_runner_registry.dart
    runners/
      cli_install_job_runner.dart
      toolchain_install_job_runner.dart
      pack_acquire_install_job_runner.dart
      hub_clone_install_job_runner.dart
      file_tree_import_install_job_runner.dart
      app_update_install_job_runner.dart
    install_job_keys.dart          # key builders
  cubits/
    install_job_cubit.dart         # optional: watch mirror for widget rebuilds
  services/cli/cli_installer_service.dart   # + cancellation
  services/cli/git_installer.dart           # + cancellation
```

## Testing

| Area | Cases |
|------|-------|
| `InstallJobRegistry` | coalesce same key; parallel different keys; cancel cooperative; cancel forceKill; onSucceeded runs when widget unmounted |
| `CliInstallJobRunner` | phase progress mapping; cancelled before npm install skips remaining phases |
| `GitInstaller` | cooperative cancel between phases |
| Settings row widget | install button disabled while running; path persisted after dialog popped |
| Status bar | pill appears for install job; cancel from tile invokes registry |

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| SSH remote npm cannot be killed mid-command | Document cooperative cancel; close SSH session after phase |
| Partial npm install on cancel | Acceptable; user can re-run merged job or use Locate |
| Large migration touch surface | Runners are small; delete adapters in same PR to avoid dual paths |

## Open items

None — design approved 2026-08-21.
