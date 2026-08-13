# SCM Commit Amend Design

Date: 2026-08-13

## Problem

The source control panel (`client/lib/widgets/git/git_source_control_panel.dart`)
only supports plain commits (`git commit -m <msg> -- <paths>`). There is no way
to merge changes into the last commit (amend), a common workflow in editors like
IntelliJ IDEA. Additionally, the AI commit-message generation button currently
sits inside the commit box next to the message textarea; it should move up into
the header button group.

## Goals

- Support IDEA-style amend: amend the selected changes into HEAD, optionally
  editing the commit message, via a checkbox inside the commit box.
- Move the AI message-generation button from the commit box into the header
  button group.
- Keep behavior conservative: no forced pushes, confirm before rewriting.

## Non-goals

- Amending non-HEAD commits (no history/rebasing UI).
- Force push support.
- Per-commit context menus in a history list (no history list exists).

## Design

### 1. GitService (`client/lib/services/git/git_service.dart`)

Add:

```dart
Future<void> commitAmend(String dir, String message, List<String> paths)
```

Runs `git add -- <paths>` when `paths` is non-empty, then
`git commit --amend -m <message> -- <paths>` (omit the `-- <paths>` pathspec
when `paths` is empty, i.e. message-only amend). Reuses `_run`, throws
`GitException` on failure like other commands.

### 2. GitRepoStatus (`client/lib/models/git_status.dart`)

Add `final bool hasCommits` (default `true`).

Parsed in `GitService._parseStatus`: porcelain v2 emits
`# branch.head (initial)` for an unborn branch — set `hasCommits = false` then.
No extra git command is needed. `props` updated.

`GitRepoStatus.notARepository` keeps `hasCommits = false`.

### 3. GitState / GitCubit (`client/lib/cubits/git_cubit.dart`)

- Add `final bool amend` (default `false`) to `GitState` + `copyWith` + `props`.
- Add `Future<void> setAmend(bool value)` publishing `copyWith(amend: value)`.
- `commit()`:
  - When `state.amend` is true: allow empty selection (message-only amend);
    require `state.status.hasCommits` and non-empty message. Call
    `_service.commitAmend(...)`.
  - Otherwise: unchanged (requires non-empty selection).
  - On success: clear `commitMessage`; keep `amend` checked (sticky, like IDEA)
    and `selectedPaths` (status refresh reconciles them).

### 4. UI (`client/lib/widgets/git/git_source_control_panel.dart`)

`_Header`:

- Add `required bool generating`, `required bool canGenerate`, and
  `required VoidCallback onGenerate` params.
- Add a `TpIconButton` with `Icons.auto_awesome_outlined`, tooltip
  `l10n.gitGenerateCommitMessage`, placed after the discard popup menu button;
  shows the same loading spinner as today when `generating`.

`_CommitBox`:

- Remove the `canGenerate` / `generating` / `onGenerate` params and the
  `IconButton` in the message row; the textarea now takes the full row width.
- Add `required bool amend`, `required bool canAmend` (== `status.hasCommits`),
  and `required ValueChanged<bool> onAmend` params.
- Render a checkbox row above the commit button using the plain Flutter
  `Checkbox` (matching the existing change-tile checkboxes in
  `git_change_tile.dart` — shared_ui has no `TpCheckbox`), labeled with
  `l10n.gitAmend`, enabled when `canAmend`; when unchecked, the button label
  is `l10n.gitCommit`; when checked it becomes `l10n.gitAmendCommit`.
- `canCommit` logic: when amend is checked, `hasCommits && !busy`; otherwise
  `hasSelection && !busy`.

Commit flow (in the panel builder):

- When the amend checkbox is checked and the user clicks the commit button,
  show a confirmation dialog first (mirror `_confirmDiscardAll` style): warn
  that the last commit will be rewritten and that force push is required if it
  was already pushed to a remote. On confirm, run `_cubit.commit()`.

### 5. l10n

`client/lib/l10n/app_en.arb` and `app_zh.arb` (only these two):

| Key | en | zh |
|-----|----|----|
| `gitAmend` | Amend last commit | 修改上一次提交 |
| `gitAmendCommit` | Amend Commit | 修改提交 |
| `gitAmendConfirmTitle` | Amend last commit? | 修改上一次提交？ |
| `gitAmendConfirmMessage` | This rewrites the last commit. If it was already pushed, a force push will be required afterwards. | 这将改写最后一次提交。如果该提交已推送到远程，之后需要强制推送。 |

Dialog buttons reuse the existing `cancel` and `confirm` keys.

### 6. Tests

- `test/services/git/git_service_test.dart`: `commitAmend` issues
  `add -- <paths>` + `commit --amend -m <msg> -- <paths>`, and the pathsless
  form omits the pathspec; `_parseStatus` sets `hasCommits = false` for
  `branch.head (initial)`.
- `test/cubits/git_cubit_test.dart`: amend commit with selection, amend commit
  without selection (message-only), amend disabled behavior, message cleared
  and `amend` kept checked after success.
- `test/widgets/git/git_source_control_panel_*` tests: checkbox toggles commit
  button label; generate button now lives in the header and is disabled without
  selection; confirmation dialog appears for amend commit.

## Risks

- Amending a pushed commit rewrites history (needs force push) — mitigated by
  the confirmation dialog.
- `git commit --amend -- <paths>` is only valid with paths; the pathsless
  branch is used for message-only amends.

## Verification

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
