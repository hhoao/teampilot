# Install Job Logs — Remote CLI/Adapter Install Visibility

Date: 2026-11-17
Status: Approved for planning

## Problem

When a workspace runs on a remote host that lacks an AI agent CLI (or its ACP
adapter), the user installs it from the readiness panel or the config card. The
install runs as a one-shot SSH exec with no PTY (`remote_cli_readiness.dart:259`
-> `buildRemotePreflightCliInstall` -> `SshClientFactory.runOnStorage`,
`ssh_client_factory.dart:301`). stdout/stderr is buffered and discarded: the UI
only sees a phase label plus one `detail` line (`install_job_registry.dart:37`),
and on failure a concatenated message. There is no progress, no live output, and
nothing to inspect afterwards.

Local installs already stream lines into the progress subtitle
(`cli_installer_service.dart:138-156`) but still persist nothing.

## Goals

1. Every install job writes a per-job log to local disk.
2. The log is viewable live while the job runs.
3. Completed jobs are viewable later, opened from the notification that reports
   the outcome.
4. Works identically for local and SSH installs, with minimal per-CLI changes.

## Non-goals

- Not a real terminal/PTY surface. Output is line-oriented, read-only.
- Not persisted on the remote host.
- Not a general-purpose command log for arbitrary workspace runs.

## Terminology

- **Job**: one `InstallJobRegistry.enqueue` invocation identified by
  `InstallJobKey` (`models/install_job/install_job_key.dart`).
- **Token**: filesystem-safe identifier derived from `InstallJobKey.activityId`;
  travels in the notification payload and names the log file.

## Components

### 1. `JobLogStore` / `JobLogWriter`

New file `client/lib/services/install/job_log_store.dart`.

```dart
class JobLogStore {
  JobLogStore({required String appDataRoot});
  String tokenFor(InstallJobKey key);
  JobLogWriter begin({required InstallJobKey key, required String title});
  bool isLive(String token);
  Stream<String> follow(String token);
  Future<List<String>> read(String token);
  Future<void> purge();
}

class JobLogWriter {
  void line(String text);
  Future<void> close();
}
```

- `tokenFor`: replace `[^A-Za-z0-9._-]` with `_` on `activityId`, append
  `-<8 hex chars of FNV-1a(activityId)>` so distinct keys cannot collide after
  sanitization.
- File: `<appDataRoot>/logs/install-jobs/<token>.log`. First line is a header
  with the job title and start time.
- In-memory ring buffer of the last 2000 lines, replayed by `follow` before live
  lines, so opening the view mid-run shows history.
- `read` parses the file for finished jobs (also valid after an app restart).
- `purge`: keep the newest 20 files, delete older than 7 days, mark files over
  5 MB truncated. Runs fire-and-forget from the store constructor.

### 2. `InstallJobContext` + `InstallJobRegistry`

- `InstallJobContext` gains an optional `void Function(String line)? appendLog`
  (no-op when absent; existing tests unaffected).
- `InstallJobRegistry.enqueue` calls `store.begin(...)` and writes:
  - `[start] <iso> — <title>`
  - `[phase] <label>` / `[phase] <label> — <detail>` on every `reportPhase`
  - `[ok] <message>` / `[fail] <error>` / `[cancel]` in the terminal paths
- `InstallJobRegistry` takes an optional `JobLogStore`; when null (tests) no log
  file is written but behavior is otherwise unchanged.
- Wiring: `wireInstallJobs` (`app/bootstrap/install_wiring.dart`) creates
  `JobLogStore(appDataRoot: storage.appDataRoot)` and passes it to the registry;
  the registry exposes a `logs` getter so UI code opens logs through the
  existing `context.read<InstallJobRegistry>()` provider.
- Registry passes `logToken` into `startForInstallJob` and
  `historyPayload: 'install-log:<token>'` into `progressCubit.complete`.

### 3. Output capture plumbing

Changes stay inside `client/lib/services/cli/` so no capability or locator call
site changes:

- `CliInstallerService.install` / `installAdapter` gain
  `void Function(String line)? onOutputLine`.
- `_runInstall` holds it for the duration of one install.
- Local: `_runLocalStreaming` forwards every line to `onOutputLine` in addition
  to the existing progress-detail path (`streamOutput` semantics unchanged).
- Remote: `_CliInstallerHost.runSsh` uses a new `_runSshStreaming` when
  `onOutputLine != null`, built on `SshClientFactory.startProcess`
  (`ssh_client_factory_narrow_operations.dart:5`, already returns streaming
  `stdout`/`stderr` and an exit code). When no callback is registered it keeps
  the existing one-shot `runOnStorage` path.
- `_runSshStreaming`: line-split both streams, forward lines, accumulate only
  the last 1 MB of each stream for the returned `CliInstallerCommandResult`,
  enforce `SshStorageIo.provisionPhaseTimeout`, and register
  `handle.kill` through `ctx.registerCancelHook` (wired by the runner).
- Node bootstrap (`teampilot_node_install.dart`) runs through the same
  `CliInstallerHost`, so it is covered without further changes.
- Toolchain: `GitInstaller` (`services/cli/git_installer.dart`) gains an
  optional `onOutputLine` and an optional streaming `ProcessRunner` variant used
  when the callback is set; `ToolchainInstallJobRunner` passes
  `ctx.appendLog`. Linux only reports phases (it never runs a package manager).

### 4. `JobLogView` / `JobLogDialog`

New file `client/lib/widgets/install/job_log_view.dart`.

- Monospace, auto-follow with a pause toggle, copy button, title row.
- Live when `store.isLive(token)` (subscribe `follow`), otherwise `read` the
  file. Both paths render the same widget.
- `ProgressActivity` gains `logToken`; `startForInstallJob` accepts it. The
  progress detail dialog (`progress_activity_detail_dialog.dart`) shows a
  "View log" button only when `logToken != null`, opening `JobLogDialog`.
- `JobLogDialog` stays open after the job finishes (the `follow` stream ends and
  the final lines remain). The existing "activity disappears -> pop" behavior of
  the progress detail dialog is untouched.

### 5. Notification entry

- `openNotificationCenterItem` (`services/notification/notification_center_open.dart`)
  gains an optional `void Function(String token)? showInstallLog` parameter and a
  `install-log:` branch: mark read, then call `showInstallLog` instead of `go`.
  The `/home-v2/workspace/` whitelist branch is unchanged; unknown payloads are
  ignored.
- The notification center panel wires `showInstallLog` to `JobLogDialog`.
- If the log file was purged, the dialog shows an "unavailable" empty state.

## Data flow

```
readiness panel / config card
  -> InstallJobRegistry.enqueue
     -> JobLogStore.begin(key, title)          [file + ring + broadcast]
     -> ProgressActivityCubit.startForInstallJob(logToken)
     -> spec.run(ctx)
        -> CliInstallJobRunner -> CliInstallerService(onOutputLine: ctx.appendLog)
           -> local: Process.start line loop
           -> ssh:  SshClientFactory.startProcess line loop
        -> writer.line (ANSI stripped, capped)
     -> complete(historyPayload: 'install-log:<token>')
        -> NotificationCubit history (persisted notifications.json)
```

- Live view: `JobLogDialog(token)` -> `follow` (ring replay + live).
- History view: notification tap -> `install-log:<token>` -> `JobLogDialog` ->
  `read` from `<appDataRoot>/logs/install-jobs/<token>.log`.

## Storage and retention

```
<appDataRoot>/logs/
  install-jobs/
    install-cliExecutable-claude-ssh-<id>-<hash>.log
    ...
```

- Keep newest 20 files, max age 7 days, per-file cap 5 MB (then a
  `[truncated]` line, no further writes).
- Rerunning the same key overwrites the file with a fresh header; the previous
  run's output remains until then.

## Error handling

- File write failure: fall back to memory-only, log one `AppLogger` diagnostic.
  Live view still works; history view shows "unavailable".
- Remote stream failure/timeout: kill the handle, append `[fail] timed out`,
  return exit 124 so the existing failure message path runs unchanged.
- Cancellation: `ctx.registerCancelHook(handle.kill)` plus `[cancel]` footer.
- Output volume: 4 KB per line, 2000-line ring, 1 MB accumulation cap per remote
  stream.
- Control characters: strip CSI/OSC sequences and `\r` rewrites before storage.
- Concurrency: `InstallJobRegistry` already dedupes non-terminal jobs per key.
- Payload compatibility: `AppNotification.payload` stays a free string; the new
  prefix does not affect existing session-idle payloads.

## i18n

New keys in `client/lib/i18n/log_en.i18n.json` / `log_zh.i18n.json`:

- `log.installJob.title`
- `log.installJob.viewLog`
- `log.installJob.empty`
- `log.installJob.unavailable`
- `log.installJob.truncated`
- `log.installJob.followPaused` / `log.installJob.followResume`

Regenerate with `cd client && dart run slang`.

## Testing

Unit (`client/test/services/install/`):

- `JobLogStore`: token sanitization and uniqueness; write order; ring replay;
  purge by count/age; 5 MB truncation; missing token read; ANSI stripping.
- `InstallJobRegistry`: start/phase/terminal line sequence and
  `historyPayload` for success, failure, cancellation.
- `CliInstallerService`: fake streaming runner emits lines to `onOutputLine`;
  timeout returns 124 with `[fail]`; `onOutputLine == null` keeps the one-shot
  path.
- `GitInstaller`: streaming runner forwards lines when `onOutputLine` is set;
  existing `ProcessResult` runner path unchanged.

Notification (`client/test/services/notification/notification_center_open_test.dart`):

- `install-log:<token>` marks read, calls `showInstallLog`, does not navigate;
  workspace deep links unchanged; empty/unknown payload ignored.

Widget (`client/test/widgets/install/`):

- Live: ring replay then follow; after completion it becomes static.
- Static: reads file content; missing file shows unavailable state.
- Progress detail dialog shows "View log" only when `logToken` is set.

Verification commands:

```
cd client && flutter analyze
cd client && dart run tool/run_tests.dart \
  test/services/install test/services/cli test/services/notification test/widgets/install
```

If public signatures of `ProgressActivityCubit` or `CliInstallerService` change,
also run the affected cubit/cli test directories per the change ->
verification table in `docs/DEVELOPMENT.md`.

## Risks and rollback

- Remote installs move from the storage plane to the member plane
  (`startProcess`). This is the same transport used by repo clone and run
  targets, but it must be verified on a real device. Rollback is structural: the
  one-shot `runOnStorage` path stays for `onOutputLine == null`, so removing the
  callback from `CliInstallJobRunner` restores today's behavior exactly.
- Watching long output can grow the in-memory ring; capped at 2000 lines.

## Out of scope / later

- Remote-side log retention (`tee` on the host) and browsing remote log files.
- Attaching install logs to OS-level notifications.