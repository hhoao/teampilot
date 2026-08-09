# Git Changes Tree Staircase Indent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the source-control changes tree render stair-stepped — a dedicated checkbox-width chevron column plus a 36px per-level indent so a child file's checkbox left edge lands exactly on its parent folder's checkbox right edge and labels nest by depth.

**Architecture:** Layout-only change to the git changes tree. Two layout constants in `git_changes_visible_rows.dart` drive the geometry (`kGitChangesIndentWidth` 16→36, new `kGitChangesChevronWidth` = 18 = checkbox width); the folder tile swaps its hardcoded 16px chevron box for the new constant; the min-content-width math and row-width estimate follow. Tree build, selection model, and commit semantics are untouched (see `docs/superpowers/specs/2026-08-09-scm-selection-model-design.md` and `docs/superpowers/specs/2026-08-09-scm-panel-idea-style-design.md`).

**Tech Stack:** Dart / Flutter, Material `Checkbox`/`Icon` in `Row`s, `TextPainter`-based min-content-width estimation.

## Global Constraints

- Layout constants only. Do not change tree construction, folder/file row emission, `selectedPaths` semantics, checkbox tri-state logic, or commit behavior.
- "Changes" root header checkbox (`git_changes_tree_list.dart`) is a separate group header — leave it as-is.
- File rows (`git_change_tile.dart`) need no edits: they are `depth * kGitChangesIndentWidth` + checkbox, so the new indent applies automatically.
- Follow existing comment style (English, `///` doc comments with `k`-prefixed consts).
- No l10n changes.
- Gate before done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.

---

### Task 1: Staircase indent + chevron column

**Files:**
- Modify: `client/lib/services/git/git_changes_visible_rows.dart` (constants + width math)
- Modify: `client/lib/widgets/git/git_change_folder_tile.dart` (chevron box width)
- Test: `client/test/services/git/git_changes_visible_rows_test.dart` (width expectation)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `const double kGitChangesIndentWidth = 36;` (was `16`)
  - `const double kGitChangesChevronWidth = kGitChangesCheckboxWidth;` (new, `18`)
  - `gitChangesMinContentWidth(...)` folder `leading` now `kGitChangesChevronWidth + kGitChangesCheckboxWidth + 16 + 6`
  - `_rowWidthEstimate(...)` depth coefficient `4.0` (was `2.0`)

**Geometry check:** with padding base 8, a folder at depth N has its checkbox spanning `[36N+26, 36N+44]`; its child file at depth N+1 has checkbox left edge `36(N+1)+8 = 36N+44` = the folder's checkbox right edge, and the file label starts 18px right of the folder label.

- [ ] **Step 1: Write the failing test**

In `client/test/services/git/git_changes_visible_rows_test.dart`, the test `'min content width accounts for checkbox + badge per row type'` (around line 92). Replace the expectation at line 118-121:

```dart
    // Equal labels → the difference is (file leading + badge) − (folder
    // leading), i.e. (checkbox+icon+gap + 22) − (chevron+checkbox+icon+gap).
    expect(
      wFile - wFolder,
      closeTo(
        kGitChangesTrailingBadgeWidth - kGitChangesChevronWidth,
        1,
      ), // 22 − chevron column (18)
    );
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `client/`): `flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: FAIL — compile error "Undefined name 'kGitChangesChevronWidth'" (the new constant does not exist yet).

- [ ] **Step 3: Update the indent constant**

In `client/lib/services/git/git_changes_visible_rows.dart`, lines 79-80:

```dart
/// Per tree level, the whole leading column = chevron (18) + checkbox (18),
/// so a child file's checkbox aligns with its parent folder's checkbox right.
const double kGitChangesIndentWidth = 36;
```

- [ ] **Step 4: Add the chevron-width constant**

Immediately after the `kGitChangesCheckboxWidth` constant (currently line 90):

```dart
/// Width of the folder chevron column; equal to the checkbox width so a child
/// file's checkbox left edge lands exactly on its parent folder's checkbox
/// right edge.
const double kGitChangesChevronWidth = kGitChangesCheckboxWidth;
```

- [ ] **Step 5: Update the folder width math**

In `gitChangesMinContentWidth`, the folder branch's `leading` (currently lines 128-131) — swap the old chevron (which reused `kGitChangesIndentWidth`) for the new constant:

```dart
      final leading = kGitChangesChevronWidth +
          kGitChangesCheckboxWidth +
          16 +
          6; // chevron + checkbox + folder icon + gap
```

- [ ] **Step 6: Update the row-width estimate**

In `_rowWidthEstimate` (currently line 168), the depth term `2.0` → `4.0` so deep rows rank high enough in the candidate-sample sort to be measured:

```dart
  return row.depth * 4.0 + units + extra / 8.0;
```

- [ ] **Step 7: Update the folder tile chevron box**

In `client/lib/widgets/git/git_change_folder_tile.dart`, the chevron `SizedBox` (currently `width: 16, height: 16,`) — the import of `git_changes_visible_rows.dart` is already present:

```dart
              SizedBox(
                width: kGitChangesChevronWidth,
                height: 16,
                child: AnimatedRotation(
```

- [ ] **Step 8: Run the unit test to verify it passes**

Run (from `client/`): `flutter test test/services/git/git_changes_visible_rows_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 9: Run the full gate**

Run (from `client/`): `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze clean; all tests pass (no geometry assertions exist elsewhere — verified: `git_changes_tree_list_test.dart`, `git_change_tile_test.dart`, `git_change_folder_tile_test.dart`, and the two `git_source_control_panel_*_test.dart` files reference none of the changed constants).

- [ ] **Step 10: Manual visual check**

Run the app, open the source-control panel, and confirm with a changed file nested under a folder: the file's checkbox left edge meets the folder's checkbox right edge and the file name is visibly nested (18px right of the folder name). Deep paths may require the panel's horizontal scroll.

- [ ] **Step 11: Commit**

```bash
git add client/lib/services/git/git_changes_visible_rows.dart client/lib/widgets/git/git_change_folder_tile.dart client/test/services/git/git_changes_visible_rows_test.dart
git commit -m "$(cat <<'EOF'
refactor(git): staircase indent for changes tree

Arrow becomes a dedicated checkbox-width column (18px); per-level indent
becomes arrow+checkbox (36px) so a child file's checkbox left edge lands
exactly on its parent folder's checkbox right edge and labels nest.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
