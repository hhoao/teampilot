# Git Operation Progress & Feedback Design

## Goal

Git actions in TeamPilot currently feel dead: clicking Fetch / Pull / Push /
Refresh moves a single anonymous spinner next to the graph icon (or nothing at
all for a warm manual refresh), a second click is silently dropped, and the
bottom status bar — which already tracks clone/install jobs — never shows git
work.

Make every user-triggered git operation self-announcing, IDEA-style:

- the **clicked button** animates while its operation runs;
- every other action is **visibly disabled** instead of silently ignoring taps;
- the **workspace status bar** shows a progress pill for the running operation;
- **Fetch / Pull / Push report completion with a success toast**.

Scope (locked with the user, 2026-10-28):

- Source-control panel (fetch, pull, push, refresh, commit, discard, init,
  branch checkout/create, generate commit message).
- Git Graph **toolbar** (fetch, pull, push, refresh).
- Commit-row context actions in the graph (cherry-pick, revert, merge, reset,
  tags, stash) stay untouched.

## Current state (evidence)

- `GitState.busy` is one global bool; `_mutate` returns `false` silently when
  another op is in flight.
- `_Header` renders a single `CircularProgressIndicator` next to the graph icon
  whenever `busy || isLoading`.
- `GitCubit._runRefresh` only sets `isLoading` on the first load for a root, so
  the header refresh button produces no state change on a warm panel.
- `GitGraphState.isRefreshing` exists but the toolbar refresh button ignores it;
  the toolbar's fetch/pull/push callbacks never touch cubit state.
- `ProgressActivityCubit` + `ProgressActivitiesStatusItem` already render a
  bottom-bar pill (used by `RepoCloneCubit` / install jobs) with history
  recording through `NotificationRecorder`.
- `AppToast._present` already records non-info variants, so any additional
  activity-history record must be suppressed to avoid duplicate entries.

## Architecture

### 1. Operation identity in the cubit

New `client/lib/models/git_operation.dart`:

```dart
enum GitOperation {
  refresh,
  fetch,
  pull,
  push,
  commit,
  discard,
  init,
  checkout,
  branchCreate,
}
```

`GitState.busy` becomes a derived getter over a new nullable
`GitOperation? operation` field (kept because ~80 call sites and tests reference
`busy`). `copyWith` clears the nullable field with the `_unset` sentinel pattern
already used by `GitGraphState`.

`GitCubit` gains a constructor parameter `minOperationVisible` (default
`Duration(milliseconds: 300)`) so fast `git` calls still show motion and tests
can pass `Duration.zero`.

- `_mutate(GitOperation op, Future<void> Function() action)` publishes
  `operation`, runs the action, refreshes, then clears the op — holding the
  operation for at least `minOperationVisible`.
- `refresh({bool manual = false})`: background polls stay silent; `manual: true`
  publishes `operation: refresh` and holds it for `minOperationVisible`, even
  when `git status` is instantaneous. Coalesced trailing refreshes are not
  manual.
- Callers map to operations: `push`, `pull`, `fetchAll`, `commit`,
  `discard*`, `initializeRepository`, `checkoutBranch`, `createBranch`.
- `generateCommitMessage` keeps its own flag but also holds it for
  `minOperationVisible` so the spinner does not flicker.

### 2. Source-control panel

`_Header` takes `operation` instead of `busy`:

- fetch/pull/push/refresh render a 14 px spinner **inside their own button**
  when they own the operation, and `enabled: false` otherwise.
- the anonymous header spinner next to the graph icon is removed.
- the branch icon shows a spinner during checkout/branch-create.

`_CommitBox`:

- commit button shows a spinner + `Committing…` label and is disabled while the
  commit runs;
- the textarea shows `Generating commit message…` as its hint and is disabled
  while generating.

### 3. Git Graph pane

- `GitGraphState.operation` (same enum) + `busy` getter.
- `GitGraphCubit.refresh({bool manual})` holds `isRefreshing` for
  `minOperationVisible` when manual.
- `GitGraphActionsController._run` takes an optional `GitOperation`; fetch,
  pull, and push pass one via a new `GitGraphCubit.runOperation` that guards
  re-entry. Row actions keep their current behaviour.
- Toolbar buttons animate individually and disable while another op runs; the
  refresh button uses `isRefreshing`.

### 4. Status bar activity + toasts

New `ProgressActivityKind.gitOperation` (icon `Icons.commit`).

New UI helper `client/lib/widgets/git/git_operation_activity.dart`:

```dart
Future<bool> runGitOperation(
  BuildContext context, {
  required String workspaceId,
  required String repoRoot,
  required String title,          // localized, e.g. "Pulling…"
  required String doneMessage,    // localized success toast
  required Future<bool> Function() body,
});
```

- starts a `ProgressActivity` keyed `git:<repoRoot>` (one per repo, so a new op
  replaces a stale one), scoped to the workspace when known;
- on completion calls `ProgressActivityCubit.complete(..., recordHistory: false)`
  (new flag) and, on success, `AppToast.show(variant: success)` — the toast is
  the single notification-history record;
- looks up `ProgressActivityCubit` defensively and degrades to a plain call when
  absent (widget tests, mobile without the status bar).

Failures keep the existing `GitCubit.errorMessage` → `AppToast` error path; the
helper does not toast failures.

### 5. l10n

New keys in `app_en.arb` / `app_zh.arb`: `gitFetching`, `gitPulling`,
`gitPushing`, `gitRefreshing`, `gitCommitting`, `gitGeneratingCommitMessage`,
`gitFetchDone`, `gitPullDone`, `gitPushDone`.

## Testing

- Cubit: operation is published/cleared for push/commit/fetch; re-entry is
  rejected while busy; manual refresh publishes `refresh` and honours the
  minimum visible duration; background refresh publishes nothing.
- Widget: tapping Fetch renders the spinner inside the fetch button and
  disables push/pull; the commit button swaps to the committing state.
- Helper: `runGitOperation` starts and completes a `gitOperation` activity and
  shows one success toast (history recorded once).

## Out of scope

- Git Graph commit-row context actions.
- Worktree operations panel.
- Real percentage progress (git subprocesses are not TTY-attached here, so
  progress is indeterminate).
