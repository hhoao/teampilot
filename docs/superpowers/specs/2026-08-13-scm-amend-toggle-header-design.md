# SCM Amend Toggle Relocation + Rename Design

Date: 2026-08-13

## Problem

The amend feature merged in `feat/scm-commit-amend` places the amend checkbox inside the commit box, below the message textarea. The user wants the toggle relocated into the header button group (like the AI generate button), and the label shortened: `gitAmend` en "Amend last commit" → "Amend", zh "修改上一次提交" → "修正".

## Goals

- Move the amend checkbox (checkbox + label, not an icon toggle) from `_CommitBox` into the `_Header` row.
- Rename the `gitAmend` l10n strings (en "Amend", zh "修正").
- Keep all amend behavior unchanged: sticky `amend` state, empty-selection message-only amend, `hasCommits` gating, confirmation dialog, button label switch (Commit ↔ Amend Commit).

## Non-goals

- No change to git-layer or cubit-layer logic (`GitService.commitAmend`, `GitCubit.commit` amend path, `GitState.amend`).
- No change to `_confirmAmend` dialog.
- No icon-toggle redesign (user explicitly wants the checkbox + text form).

## Design

### 1. `_Header` (`client/lib/widgets/git/git_source_control_panel.dart`)

- Add params: `required bool amend`, `required bool canAmend`, `required ValueChanged<bool> onAmend` + fields.
- Insert between the `Expanded` branch label and the expand/collapse `TpIconButton`: a compact `Row` with a `Checkbox` (key `ValueKey('git-amend-checkbox')`, `visualDensity: VisualDensity.compact`, `onChanged: canAmend ? (v) => onAmend(v ?? false) : null`) and a `Text(l10n.gitAmend, style: TpTextStyles.of(context).sm)`.
- Panel builder: header `BlocSelector` tuple grows from 7 to 9 elements — append `state.amend` and `state.status.hasCommits`; destructure accordingly; pass `amend`, `canAmend: hasCommits`, `onAmend: _cubit.setAmend`.

### 2. `_CommitBox`

- Remove the checkbox row and the `canAmend` / `onAmend` params.
- Keep `amend` (drives `canCommit: amend ? (hasCommits && !busy) : (hasSelection && !busy)` and the button label/icon switch).

### 3. l10n

Edit `client/lib/l10n/app_en.arb` and `app_zh.arb`, then `flutter gen-l10n` (generated files committed):

| Key | en (was → now) | zh (was → now) |
|-----|----------------|----------------|
| `gitAmend` | "Amend last commit" → **"Amend"** | "修改上一次提交" → **"修正"** |
| `gitAmendCommit` | unchanged "Amend Commit" | unchanged "修改提交" |

### 4. Tests

`client/test/widgets/git/git_source_control_panel_amend_test.dart`:

- Existing tests keep working: checkbox key is unchanged, so "checkbox toggles the commit button label", "cancel does not amend", "confirm amends", and the unborn-branch disabled test all still apply; the checkbox is now found in the header but finders are key-based.
- Adjust only if a test asserts on the checkbox's parent layout (none known); verify by running the file.

## Risks

- Header row width: adding a checkbox + label to an already busy row; the label is short ("Amend" / "修正") and the branch label is `Expanded`, so the icon cluster stays fixed-width. Acceptable per user request.

## Verification

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/widgets/git/git_source_control_panel_amend_test.dart test/widgets/git/git_source_control_panel_generate_test.dart test/cubits/git_cubit_test.dart`
