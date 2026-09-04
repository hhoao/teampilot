# Clone Repository — Design

**Date:** 2026-09-04
**Status:** Approved (brainstorming complete)

## Summary

Add a "Clone Repository…" entry to the title-bar ⋯ workspace switcher menu
(the one that contains "New Workspace" and "Recently Closed"). It opens a
dialog collecting a repo URL, an execution target (local / WSL / SSH), and a
destination directory. The clone runs as a background progress activity with
cancellable, streamed progress. On success the user chooses, from a
completion dialog, to either create a new workspace from the cloned folder or
add the folder to an existing workspace.

## Requirements (decided during brainstorming)

| Decision | Choice |
|---|---|
| Execution targets | **All three**: local, WSL, SSH (termux follows the SSH path, same as `ProcessRunExecutor`) |
| Authentication | Reuse the system git configuration (credential helpers, `ssh-agent`). The app never handles credentials; git errors are surfaced verbatim |
| Progress UX | **Background task** via `ProgressActivityCubit` + notification history; the dialog closes immediately after submit |
| Post-clone choice | Made **after completion** via a completion dialog offering "New workspace" / "Add to existing workspace" (dismissible) |

## Non-goals

- In-app credential entry / token storage.
- Persistent clone job list or resuming clones across app restarts (matches
  `ProgressActivity`, which is in-memory by design).
- Concurrent-clone management UI beyond what per-activity tiles already give.

## Architecture

New code only; no existing large files are restructured.

```
client/lib/models/repo_clone_task.dart
client/lib/services/workspace/repo_clone_service.dart
client/lib/cubits/repo_clone_cubit.dart
client/lib/pages/home_workspace/clone_repository_dialog.dart
client/lib/pages/home_workspace/clone_completed_dialog.dart
client/lib/pages/home_workspace/clone_add_to_workspace_dialog.dart
```

Modified: `home_workspace_switcher_menu.dart` (menu item),
`home_workspace_shell.dart` (wiring + completion listener),
`models/progress_activity.dart` (new `ProgressActivityKind.repoClone`),
`widgets/notification/progress_activity_tile.dart` (icon for the new kind),
l10n `app_en.arb` / `app_zh.arb`.

### Data model

`RepoCloneTask` — id (uuid, doubles as the `ProgressActivity` id), `url`,
`targetId`, `destPath` (absolute path **on the target machine**), `dirName`,
`phase` (`cloning` / `succeeded` / `failed` / `cancelled`), `errorDetail`
(git stderr tail), plus parsed progress (fraction, subtitle).

### Execution layer — `RepoCloneService`

Pure service with constructor-injected `ProcessSpawner` /
`SshProcessSpawner` / `HostProcessRunner` for unit-testability.

`clone(RepoCloneRequest, {onProgress, isCancelled})`:

1. Resolve the target with `WorkTargetCanonicalizer.resolve(targetId)`;
   build `destPath = parentDir + dirName` using `pathStyleForTarget`
   (POSIX style on WSL/SSH/termux).
2. Pre-check that the destination directory does not already exist
   (non-empty) via the target's `Filesystem` from
   `RuntimeContextRegistry.forTarget(target)` — fail early with a friendly
   message instead of a mid-clone git error.
3. Verify git exists on the target via `HostOneShotRunner`
   (local / WSL / Remote implementations) running `git --version`; fail
   fast if absent.
4. Build a `RunTargetPlan` (workingDirectory = parentDir) and start
   `git clone --progress -- <url> <dirName>` through
   `ProcessRunExecutor.start()` — which already handles local spawn,
   `wsl.exe` argv wrapping, and SSH exec quoting, and provides streamed
   stdout/stderr plus a kill handle for cancellation.
5. Parse stderr progress lines
   (`Receiving objects: 45% (56/123)`, `Resolving deltas: …`) into
   fraction + subtitle; unparsed lines update only the subtitle.

### Task layer — `RepoCloneCubit`

- `startClone(request)` creates the task, registers a
  `ProgressActivity` of the new kind `repoClone` (icon:
  `Icons.cloud_download_outlined`) in `ProgressActivityCubit`, and runs the
  service in the background (unawaited), forwarding progress via
  `update(fraction, subtitle)`.
- Multiple concurrent clones are supported; state holds
  `List<RepoCloneTask>` plus `pendingChoice` (succeeded tasks awaiting the
  user's new-vs-add decision).
- Completion / failure / cancellation call
  `ProgressActivityCubit.complete()`, which writes to the notification
  history automatically. Failure puts the git stderr tail in
  `errorMessage`; the full streamed log is visible in the progress activity
  detail dialog.
- **Cleanup on cancel/failure**: after killing the process, best-effort
  delete the partial directory on the target via the target's `Filesystem`
  (same channel workspace folders use). Deletion failure only logs via
  `AppLogger`.

### UI layer

- `HomeWorkspaceSwitcherMenu`: new "Clone Repository…" item below
  "New Workspace" (`onCloneRepository` callback wired from `HomeShell`).
- `CloneRepositoryDialog`: URL field (validates `https://`, `git@`,
  `git://`, `ssh://` prefixes), target selector
  (reuses `HomeTargetController.listSelectable()`), "Clone into" row using
  `pickWorkspaceDirectoryPath(context, targetId)` (system picker for
  local/WSL, SFTP `RemoteDirectoryBrowserDialog` for SSH), and a directory
  name field defaulting to the name derived from the URL (editable).
  Submit → `startClone` → close dialog + info toast.
- `HomeShell` hosts a `BlocListener<RepoCloneCubit>` that opens
  `CloneCompletedDialog` when a task enters `pendingChoice`:
  - **New workspace** → `createWorkspaceWithFirstSession([folder],
    display: dirName, allowDuplicate: true)` → navigate to
    `/home-v2/workspace/:id`.
  - **Add to existing…** → `CloneAddToWorkspaceDialog` listing existing
    workspaces → `chatCubit.addWorkspaceDirectory(workspaceId, folder)`.
  - Dismissible (skip).
- The folder added is `WorkspaceFolder(path: destPath, targetId:
  canonicalizedTargetId)` — the same model workspace folders use, so the
  file tree / Git panels work immediately.

## Data flow

```
⋯ menu "Clone Repository…"
  → CloneRepositoryDialog (URL / target / parentDir / dirName)
  → RepoCloneCubit.startClone(request)
      ├─ WorkTargetCanonicalizer.resolve(targetId) → RuntimeTarget
      ├─ ProgressActivity registered (status-bar item appears)
      └─ background:
           RepoCloneService.clone(...)
             ├─ dest-exists pre-check (target Filesystem)
             ├─ HostOneShotRunner: git --version
             ├─ ProcessRunExecutor.start(git clone --progress -- url dir)
             ├    stderr → RepoCloneProgress → activity.update()
             └    exit code
                  ├─ 0   → complete(succeeded) → pendingChoice
                  │        → CloneCompletedDialog
                  │             ├─ new workspace  → create + navigate
                  │             └─ add to existing → addWorkspaceDirectory
                  ├─ ≠0  → complete(failed, stderr tail) → notification ✗
                  └─ cancel → kill → delete partial dir → complete(cancelled)
```

## Error handling

| Scenario | Handling |
|---|---|
| Invalid URL | Inline dialog validation; no request sent |
| Destination exists (non-empty) | Pre-check fails in dialog/task with a clear message |
| No git on target | `git --version` fails fast; error message says git is missing on the target machine |
| Auth failure (private repo) | git stderr shown verbatim; the user resolves credentials in their system git config |
| Network failure mid-clone | exit ≠ 0 → failed with stderr tail; partial directory best-effort deleted |
| User cancel | `requestCancel` → kill → delete partial → `complete(cancelled)` |
| Partial-dir delete fails | Log only; the next clone at the same path hits the exists pre-check and reports it |
| SSH channel exception | Task failed with the exception summary |
| App restart mid-clone | Activity lost (in-memory, consistent with install jobs); user re-clones manually |

## Testing

- `RepoCloneService` unit tests with fake spawners: success (progress
  parsing → fraction), failure (non-zero exit), cancel, git missing, and
  command construction per target kind (raw `git`, `wsl.exe` argv, SSH
  shell quoting).
- `RepoCloneCubit` unit tests with a fake service: activity registration,
  progress forwarding, success → `pendingChoice`, cancel cleanup invoked,
  failure `errorMessage`.
- Dialog widget tests: URL validation, dirName derivation from URL, submit
  callback.
- Full gate: `cd client && flutter analyze --no-fatal-infos
  --no-fatal-warnings && dart run tool/run_tests.dart`.

## l10n

Roughly 15 new strings in `app_en.arb` / `app_zh.arb` only (menu label,
dialog title/fields/buttons, progress subtitles, error messages, completion
dialog labels).
