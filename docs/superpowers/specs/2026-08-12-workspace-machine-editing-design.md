# Workspace Machine Editing — Design

Date: 2026-08-12

## Problem

Created workspaces cannot add or change **machines** (local / WSL / SSH targets)
in workspace manage → Settings. The "Directories & machines" editor renders
with `lockTargets: true` (hardcoded since the 2026-07-05 project-config
refactor, commit `9d4c1333`), and the "add on another machine", "change
machine (group)", and batch-target affordances were removed in commit
`018c348f` (2026-06-26). Only per-machine "add directory" remains. All
necessary l10n keys are still present in `app_en.arb` / `app_zh.arb`.

Goal: users can add machines and their directories to an **already-created
workspace** of any topology (local / project-remote / mixed), and move folders
between machines — with no workspace-type restriction.

## Design

### 1. Unlock machine editing in workspace manage

`workspace_info_section.dart:100` — `WorkspaceFoldersSection(workspace: live,
lockTargets: true)` → `lockTargets: false`. The `lockTargets` parameter stays
(no current caller besides this one, but the editor API keeps it for future
identity contexts).

### 2. Restore machine-editing affordances in `WorkspaceFoldersEditor`

`client/lib/widgets/workspace_folders_editor.dart`:

- **`_targetsLocked`** becomes `widget.lockTargets` only — the `topology ==
  mixed` clause is removed. Local, project-remote, and mixed workspaces are
  all fully editable.
- **Row-level machine switch** (`_pickTargetForRow`): already implemented,
  becomes active once unlocked.
- **Group-level machine switch** (`_setTargetForGroup` /
  `_pickTargetForGroup`): restore, gated by `!widget.enabled ||
  _targetsLocked`. `_MachineFolderCard` re-gains the "Change"
  (`workspaceFoldersChangeTarget`) `TextButton` on the machine header row
  (right of the machine label, left of "Add directory"), shown when
  `enabled && !_targetsLocked` — matching the pre-`018c348f` placement.
- **Add folder on another machine** (`_addFolderOnAnotherMachine`): restore a
  toolbar row above the machine groups showing "Add on another machine"
  (`workspaceFoldersAddOnAnotherMachine`) when `enabled && !_targetsLocked`
  **and** at least one unused selectable target exists (candidates = selectable
  targets minus `workspaceTargetIds(_folders)`). Single candidate → directory
  picker directly on it; multiple candidates → machine `SimpleDialog`
  (`workspaceFoldersPickTarget`), then directory picker on the chosen target.
  The old `groups.length == 1` gate is replaced by the candidates-non-empty
  rule (more correct: works with 2+ existing machines too).
- The "Set all to local / Set all to remote…" batch buttons are **not**
  restored (YAGNI).
- `allowRowTargetChange` drops its `topology != mixed` extra check.

Directory picker stays `pickWorkspaceDirectoryPath` (SFTP remote browser for
SSH targets, local OS dialog otherwise) — unchanged.

### 3. Hint text

`workspaceFoldersEditorHint` (`workspace_folders_editor.dart:17`) drops the
mixed branch; all topologies use the generic hint ("Set machine and path per
directory. All local = local workspace; all one remote = project-remote;
cross-machine = mixed (member-remote)."). The
`workspaceFoldersMixedTargetsLockedHint` key ("Mixed workspace: folder
machines are fixed…") is removed from `app_en.arb`, `app_zh.arb`, and the
generated `app_localizations*.dart` files.

### 4. Member-placement reset on any mixed folder change

`SessionRepository.updateWorkspaceFolders` (session_repository.dart:473-497)
currently resets `memberPlacementInitializedByTeam` only on becoming-mixed or
target-set change. A mixed workspace whose folder moves between two already
present machines keeps stale placement (e.g. the "lead must be local when a
local folder exists" rule can be violated). Strengthen:

```
foldersChanged = !listEquals(nextFolders, existing.folders)
mixedInvolved = previousTopology == mixed || nextTopology == mixed
reset = becameMixed || targetSetChanged || (foldersChanged && mixedInvolved)
```

Reset clears `memberPlacementInitializedByTeam` for all teams, surfacing the
existing "Confirm machine assignment in Team Settings" flow before the next
launch. No changes to `memberTargetsByTeam` pins themselves.

### 5. Dead code removal

Delete (both orphaned since `9d4c1333`, no references):

- `client/lib/pages/home_workspace/workspace/workspace_settings_view.dart`
- `client/lib/widgets/workspace_details_dialog.dart`

### 6. Tests

- **Editor widget tests** (`client/test/pages/home_workspace/workspace/`):
  - local-only controller (`testHomeTargetController`): no unused candidates →
    "Add on another machine" hidden; with `lockTargets: true` → "Change" and
    row target affordance hidden.
  - with a saved SSH profile: "Add on another machine" visible; tapping opens
    the machine picker dialog listing the SSH target (assert dialog step only —
    the directory picker is an OS/SFTP dialog and not driven in tests).
  - group "Change" visible when unlocked; tapping opens the pick-target
    dialog.
  - mixed workspace (2 targets): buttons still visible (not locked).
- **Repository test** (`session_repository_folders_test.dart`): mixed
  workspace, move a folder between two present machines (target set
  unchanged) → `memberPlacementInitializedByTeam` resets to false.
- Existing `workspace_folders_section_test.dart` /
  `workspace_info_section_target_test.dart` keep passing (assertions are
  content-level; no locked-behavior assertions).

## Out of scope

- **File migration** across machines: switching a folder's machine only
  re-associates the path with another target; the path must already exist on
  the destination. Real cross-filesystem copy/sync is a separate feature.
- Batch "Set all to local/remote" buttons.
- Creating new SSH profiles from the editor (done under `/config`).

## Verification

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
