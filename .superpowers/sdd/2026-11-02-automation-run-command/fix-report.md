# runCommand review findings — fix report

Branch: `sdd-run-command` (worktree `.codebuddy/worktrees/automation-run-command`)
Date: 2026-11-02

All 11 findings (C1, C2, I3–I8, I10) are addressed. Each fix has at least one
new or extended test. `flutter analyze --no-fatal-infos --no-fatal-warnings`
reports the 39 pre-existing issues (none in touched files). The affected test
files all pass.

## Per-finding changes

### C1 [Critical] — never rely on `ProcessRunExecutor.shell:` for the command line
**File:** `client/lib/services/automation/automation_command_runner.dart`
(`_invocationFor`, ~L247–263)

`HostAutomationCommandRunner` now computes the shell invocation explicitly and
always passes `shell: false` to `_executor.start`:

- Local POSIX → `command: 'sh', args: ['-c', line]`
- Local Windows (native, via injectable `isWindows`) → `command: 'cmd.exe', args: ['/c', line]`
- WSL → `command: 'sh', args: ['-c', line]` (with `shell:false`,
  `ProcessRunExecutor._spawnWsl` passes `arguments` through as argv to
  `wsl.exe … sh -c <line>`, no extra quoting)
- SSH / Termux → `command: 'sh', args: ['-c', line]` (the executor's
  `_spawnSsh` wraps argv via `HostShellArgv.command` into a single remote
  shell string, so the line stays one `sh -c` argument)

`Platform.isWindows` is wrapped in an injectable `bool Function()? isWindows`
so tests can exercise both branches without running on Windows.

**Tests added** (`automation_command_runner_test.dart`):
- `runs local POSIX commands through sh -c`
- `runs local Windows commands through cmd.exe /c`
- `WSL argv keeps the command line as one sh -c argument` (asserts the full
  `wsl.exe -d Ubuntu --cd /repo sh -c 'npm ci && npm run build'` argv)
- `SSH argv keeps the command line as one sh -c argument` (asserts the remote
  shell string is `cd '/repo' && 'sh' '-c' 'npm ci && npm run build'`)

### C2 [Critical] — bound the ENTIRE runner invocation; queue always drains
**File:** `automation_command_runner.dart` (`run`, ~L86–155; `_stopQuietly`,
~L319–325)

`run()` now wraps the whole invocation in a `Completer<AutomationCommandOutcome>
deadline` plus a `Timer(timeoutSeconds + timeoutGrace)` (default grace 5s). The
real work runs `unawaited` in the background via `_execute`:

- On expiry the timer kills the started process best-effort (`_stopQuietly`,
  itself bounded by a 2s `timeout`) and completes `deadline` with a terminal
  `timedOut` outcome — even if `_execute` is stuck in `start()` or `stop()`.
- If `_execute` finishes first, it completes `deadline` with the real outcome.
- `_execute` catches `Object` and records `runner_failed` so the queue never
  sees an unhandled exception.

The executor's serial `_queue` already wraps `_run` with
`onError: (Object _, StackTrace __) {}`, so a throwing or hung runner cannot
block subsequent commands: the runner itself returns within
`timeoutSeconds + grace`, and any lingering background work is fire-and-forget.

**Test added:** `times out when start() never returns so the queue can drain`
— uses a `_HangingStartExecutor` whose `start()` returns a never-completing
future; asserts the run returns `timedOut` within 5s with `timeoutSeconds: 1`
and `timeoutGrace: 50ms`.

### I3 [Important] — mark all stale runs interrupted; kill before cancel
**Files:**
- `automation_scheduler.dart` (`_markInterruptedRuns`, ~L134–162)
- `services/run/process_run_executor.dart` (`stop`, ~L126–133)

`_markInterruptedRuns` dropped the `timeoutSeconds + 60s` recency check. In a
fresh process nothing is executing for a `runCommand` automation, so every
`pending`/`dispatching` row is stale by definition and is marked
`dispatchFailed(error: 'interrupted')` unconditionally. This runs once at
start-up via `_processMissedRuns`, and `_missedRunsProcessed` prevents repeats
within the same process lifetime.

`ProcessRunExecutor.stop()` now calls `handle.kill()` BEFORE awaiting
`subscription.cancel()` for each stream. Cancelling first could block on the
socket/pipes and never reach the kill when the transport is wedged.

**Tests added:**
- `automation_scheduler_test.dart`: `marks a recently started dispatching run as
  interrupted on start` — a run started 1s ago is still marked interrupted.
- `process_run_executor_test.dart`: `stop kills the handle before cancelling
  output subscriptions` — records `kill`/`cancel` events via
  `StreamController.onCancel` and asserts `kill` is first.

### I4 [Important] — serialize overlap recording on `_queue`
**File:** `automation_command_executor.dart` (`enqueue`, ~L45–61; `_enqueueSerial`,
~L63–67)

`_recordOverlap` is now dispatched through `_enqueueSerial(() => …)` so it rides
the same serial `_queue` as the in-flight `_run`'s read-modify-write of
`automations.json`. The overlap run is recorded only after the in-flight run
releases the queue, eliminating the lost-write race.

**Tests added** (`automation_command_executor_test.dart`):
- `serializes overlap recording behind the in-flight run` — asserts the overlap
  future does NOT complete while the run is still in flight, and that both the
  `completed` and `skippedOverlap` runs land afterwards.
- The existing overlap test was adjusted to `await` the overlap after releasing
  the runner, reflecting the serialized semantics.

### I5 [Important] — do not resurrect a deleted automation
**Files:**
- `automation_command_executor.dart` (`_run`, ~L137–146; `_currentAutomation`,
  ~L167–173)
- `repositories/automation_repository.dart` (`deleteRun`, ~L141–149)

`_currentAutomation` now returns `Automation?` (null when the row is gone)
instead of falling back to the snapshot captured at enqueue. After a run
finishes, if the automation was deleted while the command was executing, the
executor skips the advance and calls `_repository.deleteRun(workspaceId,
finished.id)` so history does not reference a dead automation. `onAfterRun` is
still fired so the UI reloads.

`AutomationRepository.deleteRun` is a new helper that removes a single run by
id (no-op if absent).

**Test added:** `does not resurrect an automation deleted while running` —
deletes the automation mid-run, releases the runner, and asserts the workspace
and runs collections are both empty afterwards.

### I6 [Important] — tick path applies `missedRunGraceMinutes` for runCommand
**File:** `automation_scheduler.dart` (`_runCommandBeyondGrace`, ~L164–174;
`_dispatchDueAutomations`, ~L176–196)

`_dispatchDueAutomations` now checks `_runCommandBeyondGrace(automation, dueAt,
now)` before dispatching. For a `runCommand` automation with
`catchUpPolicy == none` whose `nextRunAtMs` is overdue beyond
`missedRunGraceMinutes`, it records a `skippedMissed` run and advances the
schedule via the shared `_recordSkippedMissed` helper — exactly what
`_processMissedRuns` does. `catchUpPolicy == once` and non-`runCommand`
automations are unaffected, so `scheduledMessage` / `launchPrompt` behavior is
unchanged.

This covers the laptop-resume case: the periodic timer can fire hours late,
and `_missedRunsProcessed` prevents `_processMissedRuns` from re-running, so
without this check every overdue `runCommand` would fire immediately.

**Test added:** `tick path skips an overdue runCommand beyond grace without
catch-up` — uses a 20ms tick interval, starts the scheduler, then mutates the
automation's `nextRunAtMs` to 2h in the past and waits for a tick; asserts a
single `skippedMissed` run lands and the executor was never called.

### I7 [Important] — `exitCode.then` needs `onError`
**File:** `automation_command_runner.dart` (`_awaitExit`, ~L266–297)

`_awaitExit` now passes an `onError` to `result.exitCode.then` that completes
with `(exitCode: null, error: _unreachable(kind) ? 'target_unreachable' :
'spawn_failed')`. `_execute` translates a non-null `error` into a
`dispatchFailed` outcome. `_unreachable` now uses the shared
`usesSshTransport(kind)` helper (covers `ssh` + `termux`).

**Tests added:**
- `reports an SSH exit-code failure as target_unreachable` — uses an
  `_ErrorExitHandle` whose `exitCode` future errors; asserts
  `outcome.error == 'target_unreachable'` and
  `outcome.status == dispatchFailed`.
- `reports a local exit-code failure as spawn_failed` — same handle on a local
  target; asserts `outcome.error == 'spawn_failed'`.

### I8 [Important] — pick the LONGEST matching folder path
**File:** `automation_command_runner.dart` (`_folderFor`, ~L329–347)

`_folderFor` now iterates all folders and keeps the one with the longest
matching `path` (instead of returning the first prefix match). With `/repo`
and `/repo/svc` on different targets, a cwd of `/repo/svc` now resolves to the
`/repo/svc` folder. Exact-match and empty-cwd (main folder) cases are
preserved.

**Test added:** `picks the longest matching folder path` — workspace with
`/repo` (local) and `/repo/svc` (`ssh:profile-2`); asserts the captured plan's
`targetId` and `workingDirectory` come from the `/repo/svc` folder.

### I10 [Important] — UI: working-directory control + timeout on command field
**Files:**
- `pages/automations/automation_command_working_directory_field.dart` (new)
- `pages/automations/automation_editor_form_body.dart` (~L144–167)
- `pages/automations/automation_editor_dialog.dart`
  (`_resolvedCommandWorkingDirectory` ~L300–307; save path ~L456–458,
  L474–498, L531–538; form wiring ~L644–651)
- `l10n/app_en.arb`, `l10n/app_zh.arb` (+ generated `_localizations*.dart`)

New `AutomationCommandWorkingDirectoryField` reuses the launch-prompt folder
picker (`WorkspaceLandingSelectorBar` + `WorkspaceLandingProjectResolver`)
over `Workspace.folders`, with an explicit "Workspace default folder" entry
whose value is `''` (empty → null at persist time). It is rendered in the form
body only for `runCommand` when a workspace is present.

`automation_editor_dialog._save` for `runCommand`:
- Persists `workingDirectoryPath` via `_resolvedCommandWorkingDirectory()`,
  which returns `null` when the picker value is empty — so the user can both
  see and clear the field, and the runner resolves the workspace main folder
  at execution time.
- Command and timeout validation (empty command, >2000 chars, non-numeric
  timeout, out-of-range 30–1800) all set `_commandError`, which is rendered in
  the command field's `errorText` slot — not the name field. `validate()`
  failures for `runCommand` also land on `_commandError` instead of
  `form.setFieldError('name', …)`.
- `onCommandChanged` clears `_commandError` so the error goes away as the user
  types.

Five new l10n keys added to both `app_en.arb` and `app_zh.arb`, and
`flutter gen-l10n` regenerated `app_localizations.dart` /
`app_localizations_en.dart` / `app_localizations_zh.dart`. Re-running
`flutter gen-l10n` after the edits produced no further diff (verified).

**Tests added** (`automation_editor_dialog_test.dart`):
- `runCommand editor renders a working-directory picker` — asserts the label
  and "Workspace default folder" entry are present.
- `runCommand timeout errors surface on the command field` — enters `echo hi`
  + timeout `10`, taps Save, asserts `automationsCommandTimeoutRange` is shown
  and no automation was persisted.
- Existing `runCommand editor saves a command automation` extended to assert
  `saved.workingDirectoryPath` is `null` when no folder is chosen.

## Commands run

```
cd client && flutter gen-l10n
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart \
  test/services/automation/automation_command_runner_test.dart \
  test/services/automation/automation_command_executor_test.dart \
  test/services/automation/automation_scheduler_test.dart \
  test/services/run/process_run_executor_test.dart \
  test/pages/automations/automation_editor_dialog_test.dart
cd client && dart run tool/run_tests.dart \
  test/services/automation/ test/pages/automations/ test/models/automation_test.dart
cd client && dart run tool/run_tests.dart \
  test/services/automation/automation_dispatcher_test.dart \
  test/services/catalog/automation_catalog_module_test.dart
cd client && dart run tool/run_tests.dart \
  test/services/run/ test/services/workspace/repo_clone_service_test.dart
```

### `flutter analyze --no-fatal-infos --no-fatal-warnings`
39 issues — all pre-existing, none in touched files. Touched files:
`automation_command_runner.dart`, `automation_command_executor.dart`,
`automation_scheduler.dart`, `process_run_executor.dart`,
`automation_editor_dialog.dart`, `automation_editor_form_body.dart`,
`automation_command_working_directory_field.dart`,
`automation_repository.dart`, l10n files — all clean.

### Test summary
- Affected files: **59 tests passed**.
- Broader scope (`test/services/automation/`, `test/pages/automations/`,
  `test/models/automation_test.dart`): **171 tests passed**.
- Dispatcher + catalog: dispatcher 16/16 passed; catalog module 36/36 passed.
- `test/services/run/` + `repo_clone_service_test.dart` (other callers of
  `ProcessRunResult.stop()`): 146 tests passed — kill-before-cancel change is
  backward compatible.

One expected `WARN` log line in `automation_command_executor_test.dart`
(`runner failure records dispatchFailed and advances runCount`) — the test
fixture deliberately throws `Bad state: runner boom` to verify the executor
catches runner failures; not a regression.

## Verification notes / concerns

- C1 WSL argv: the WSL test asserts the exact `wsl.exe` argv
  (`-d Ubuntu --cd /repo sh -c 'npm ci && npm run build'`) by supplying a real
  `ProcessSpawner` and inspecting the captured `executable` / `arguments`.
  This verifies `ProcessRunExecutor._spawnWsl` with `shell:false` passes
  `arguments` through verbatim (no `RemoteFileStore.shellSingleQuote` on the
  line), matching the finding's requirement.
- C2: the background `_execute` future is `unawaited` by design once the
  deadline fires. It may linger until the OS reaps the process, but it holds
  no locks and writes nothing to disk after the deadline outcome is produced.
- I3: `_markInterruptedRuns` is run-once per process via
  `_missedRunsProcessed`. A long-lived process that crashes mid-run and is
  restarted will mark the leftover row interrupted on the next start —
  matching the finding's "stale by definition" reasoning.
- I5: `deleteRun` is a new `AutomationRepository` method. It does not touch
  the automation row, only the run record.
- I6: only `runCommand` is gated by grace in the tick path; the two legacy
  actions keep their existing "fire on resume" behavior, satisfying
  "Do not break scheduledMessage / launchPrompt behavior."
- I10: the working-directory picker is hidden when no workspace is in scope
  (`if (workspace != null)`), matching the launch-prompt section's existing
  guard.

## Pre-existing failures noted (not touched)

Per the task brief, `compose_text_controller_test.dart` and
`builtin_close_tab_menu_source_test.dart` have unrelated load failures and were
not run or modified.
