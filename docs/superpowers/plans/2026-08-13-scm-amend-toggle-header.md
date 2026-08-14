# SCM Amend Toggle Relocation + Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the amend checkbox from the commit box into the source-control header button group and rename `gitAmend` l10n to en "Amend" / zh "修正".

**Architecture:** `_Header` gains `amend`/`canAmend`/`onAmend` params and renders a compact checkbox+label row between the branch label and the icon cluster; `_CommitBox` loses the checkbox row and `canAmend`/`onAmend` params, keeping `amend` for the button label switch; l10n values updated + regenerated.

**Tech Stack:** Dart/Flutter, flutter_bloc, TpIconButton/shared_ui, `flutter gen-l10n`.

## Global Constraints

- l10n: edit only `client/lib/l10n/app_en.arb` and `app_zh.arb`, then `flutter gen-l10n` (generated `app_localizations*.dart` committed).
- Verification: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/widgets/git/git_source_control_panel_amend_test.dart test/widgets/git/git_source_control_panel_generate_test.dart test/cubits/git_cubit_test.dart`.
- No comments beyond existing file style. No changes to git/cubit logic or `_confirmAmend`.

---

### Task 1: Relocate amend checkbox to `_Header` + rename l10n + update tests

**Files:**
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (+ regenerated `app_localizations*.dart`)
- Test: `client/test/widgets/git/git_source_control_panel_amend_test.dart`

**Interfaces:**
- Produces: `_Header` params `amend` (bool), `canAmend` (bool), `onAmend` (ValueChanged<bool>). `_CommitBox` params: `canAmend`/`onAmend` removed, `amend` kept. Header selector becomes a 9-tuple.

- [ ] **Step 1: Update l10n values**

`app_en.arb`: `"gitAmend": "Amend",`; `app_zh.arb`: `"gitAmend": "修正",`. Run `flutter gen-l10n` from `client/`.

- [ ] **Step 2: Move the checkbox into `_Header`**

In `client/lib/widgets/git/git_source_control_panel.dart`:

1. Panel builder header selector (currently `(String, int, int, bool, bool, bool, bool)`): extend to `(String, int, int, bool, bool, bool, bool, bool, bool)` with selector appending `state.amend, state.status.hasCommits`; destructure `final (branch, ahead, behind, busy, allExpanded, generating, hasSelection, amend, hasCommits) = header;`; pass `amend: amend, canAmend: hasCommits, onAmend: _cubit.setAmend` to `_Header`.
2. `_Header`: add `required this.amend, required this.canAmend, required this.onAmend` + fields `final bool amend; final bool canAmend; final ValueChanged<bool> onAmend;`. Between the `Expanded` branch label and the expand/collapse `TpIconButton` insert:

```dart
Checkbox(
  key: const ValueKey('git-amend-checkbox'),
  value: amend,
  onChanged: canAmend ? (v) => onAmend(v ?? false) : null,
  visualDensity: VisualDensity.compact,
),
Text(l10n.gitAmend, style: TpTextStyles.of(context).sm),
```

(with a 4px gap between; align with `Center`/`Row` as needed to keep the single-row layout).

3. `_CommitBox` builder: remove `canAmend`/`onAmend` from the constructor call (keep `amend`). `_CommitBox` widget: remove `canAmend`/`onAmend` params+fields and the checkbox row (the `Row` with `ValueKey('git-amend-checkbox')`), restoring a single `SizedBox(height: 8)` between textarea and button.

- [ ] **Step 3: Run tests**

Run: `flutter test test/widgets/git/git_source_control_panel_amend_test.dart test/widgets/git/git_source_control_panel_generate_test.dart test/cubits/git_cubit_test.dart`
Expected: all pass (checkbox key unchanged; finders are key-based).

- [ ] **Step 4: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/git/git_source_control_panel.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart
git commit -m "feat(git): move amend toggle to header and rename labels"
```

---

### Task 2: Full verification

- [ ] **Step 1: Full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS (13 pre-existing environment-dependent failures allowed — same set as baseline).
