# Editable diff + hunk apply design

**Date:** 2026-07-31  
**Status:** Approved for planning  
**Problem:** TeamPilot’s SCM side-by-side / unified diff is read-only. There is no in-diff editing and no IDEA-style left→right hunk apply (`>>`). Users must switch to the File surface or discard whole files to change working-tree content from a diff.

**Builds on:** existing `DiffViewer` / `SideBySideDiffView` / `DiffEngine` / `DiffBlock`, `EditorCubit` (`DiffTabState`, `openDiff`, `diffReloadFor`, `saveFile`), `WorkbenchEditorOpener.openDiff`, `GitSourceControlPanel` unstaged/staged open paths, `Filesystem.atomicWrite`.

## Goal

For **Unstaged** side-by-side diffs only:

1. **Editable right pane** bound to the working-tree file (dirty + Save).
2. **Gutter `>>`** apply one `DiffBlock` from left → right, write the working-tree file immediately, then reload the diff and refresh SCM status.

Write path never persists filler/alignment blank lines.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Scope (v1) | `WorkbenchDiffSource.unstaged` only; side-by-side only |
| Writable side | Right only (working tree). Left is always read-only |
| Apply direction | `>>` left → right only (no `<<`) |
| Apply persistence | Immediate `atomicWrite` + reload |
| Hand edits | Dirty → existing Save UX; then reload |
| Other diff sources | `staged`, `changes`, and Unified remain read-only; no `>>` |
| File ↔ Diff buffers | **Separate** buffers (not a live shared controller) |
| Merge conflict three-way | Out of scope |
| Disk change watcher | Out of scope (no new file-watch subsystem in v1) |
| Architecture | Canonical right file text + pure `DiffHunkApplier`; display may keep filler alignment |

## Non-goals

- Staged / index mutation via apply or edit
- Writable `WorkbenchDiffSource.changes` (worktree vs HEAD compare) in v1
- Bidirectional `<<` into HEAD/index
- Merge conflict Ours/Theirs UI
- Editable unified view
- Stage single hunk (git add -p)
- Background “external file changed” detection / prompt
- Binary / oversized files beyond current diff limits

## Invariants

1. **Canonical right text has no fillers.** Alignment blanks are display-only; Save and `>>` always write real file bytes.
2. **Apply and Save share one write path:** `atomicWrite(absolutePath, text)` → `diffReload` → Git status refresh.
3. **Only `unstaged` is writable.** `WorkbenchDiffSource.staged` and `WorkbenchDiffSource.changes` must not enable edit or `>>`.
4. **Fail soft:** write failure must not leave the UI claiming success; keep prior editor/diff state.
5. **SSH / WSL / local:** all writes go through the workspace `Filesystem` (same as `EditorCubit.saveFile`).
6. **`>>` never unlinks.** It may create/recreate a missing working-tree file via `atomicWrite`; an apply that yields empty content writes an empty file, it does not delete the path.

## Design

### 1. Modules

```text
DiffResult / DiffBlock
  → DiffHunkApplier.applyLeftToRight(result, block, rightFileText) → newRightText
  → EditorCubit.applyDiffHunk / saveDiffWorkingTree
  → Filesystem.atomicWrite
  → DiffReload + GitCubit status refresh
```

| Piece | Role |
|-------|------|
| `DiffHunkApplier` | Pure function; unit-tested; no Flutter |
| `EditorCubit` | Owns writable unstaged diff state (canonical right text, dirty), apply/save/reload |
| `SideBySideDiffView` | Renders `>>` on change blocks when writable; right `CodeEditor` editable |
| `DiffEditorSurface` / opener | Passes `writable: true` only for unstaged |
| `GitCubit` | Status refresh after successful write (caller or cubit hook) |

### 2. `DiffHunkApplier`

Inputs: `DiffResult`, target `DiffBlock`, current right file text (newline-normalized consistently with the diff engine).

For the block’s row range:

- Collect left non-filler lines (`leftText` where `hasLeft`) in order.
- Collect the right file line span covered by the block (`rightLineNo` min/max among rows with `hasRight`). Delete blocks with no right lines insert at the surrounding right cursor (after previous right line / before next).
- Replace that right span with the collected left lines.
- Return the full new right file text.

Reject out-of-range blocks / empty results that would no-op incorrectly with a clear error for the cubit to surface.

Covered cases in tests: insert, delete, modify; file head/tail; empty file; consecutive applies; invalid block.

### 3. Editor / display split

- **Left controller:** filler-aligned display text; `readOnly: true`.
- **Right:** keep visual filler alignment for 1:1 scroll with left (existing mapper), but maintain a **canonical** right string (real file lines only).
- Edits on filler visual rows are ignored/rejected so blanks never enter canonical text.
- Hand edit updates Diff canonical text + marks the **Diff surface** dirty (track dirty by diff key; do not imply a shared live buffer with the File tab). Cubit keeps **`lastLoadedCanonical`** (baseline that matches the current `DiffResult`) separate from the dirty working canonical.
- While Diff is dirty, side-by-side filler alignment **may break** (line-count drift). Do **not** live-recompute the diff on each keystroke in v1; alignment is restored on Save / `>>` reload.
- Diff Save writes Diff canonical via the same filesystem path as `saveFile`.

**Same path open as File tab + Diff tab (locked):**

| Event | Behavior |
|-------|----------|
| Diff Save / `>>` succeeds | Write Diff canonical. If a File tab is open for that path, **reload File buffer from the written text (or disk)** and clear File dirty. If File had unsaved edits, they are discarded; show a short l10n snackbar. |
| File Save while Diff is dirty | Confirm: discard Diff edits and save File, or cancel. On confirm: `saveFile`, then reload Diff from disk and clear Diff dirty. |
| File Save while Diff is clean | Normal `saveFile`, then reload Diff from disk. |

Buffers stay separate until a successful write; there is no live shared `CodeLineEditingController` across File and Diff in v1.

### 4. Interaction

| Action | Behavior |
|--------|----------|
| Click `>>` on a block | If Diff is clean → apply on current canonical → write → reload → SCM refresh. If Diff is dirty → confirm discard or cancel. On **confirm discard**: restore Diff canonical to the **last-loaded** working-tree text (the text that produced the current `DiffResult` / `DiffBlock` line map), clear Diff dirty, **then** apply that block → write → reload → SCM refresh. On cancel: no-op. Never apply a hunk against dirty/out-of-sync canonical text. |
| Type on right (unstaged SxS) | Diff dirty; Save enabled |
| Diff Save | Write canonical → clear Diff dirty → reload (+ File tab sync per §3) |
| `staged` / `changes` / Unified | No `>>`; right read-only |
| Deleted file (unstaged delete) | `>>` that restores left lines **recreates** the file via `atomicWrite`; never `unlink` |
| Untracked / no writable path | Disable `>>` + tooltip |

### 5. Errors

| Case | UX |
|------|----|
| Write failure | Snackbar / l10n; keep prior canonical + dirty state; do not reload as success |
| Reload failure after successful write | Message: saved but refresh failed; offer retry reload |
| Binary / too large | Keep current non-editable diff policy |

### 6. l10n

Add strings for: apply hunk tooltip, dirty-discard confirm, apply/save failure, reload-after-save failure, disabled apply reason (e.g. staged read-only / missing path). Edit `app_en.arb` / `app_zh.arb` only.

## Testing

| Layer | Cases |
|-------|--------|
| Unit `DiffHunkApplier` | insert / delete / modify; head/tail; empty; multi-apply; invalid block |
| Cubit | apply writes + reload; dirty confirm cancel; write failure leaves state; File tab reload after Diff write; File Save blocked/confirmed when Diff dirty |
| Widget | unstaged SxS shows `>>`; staged / unified do not; tap invokes apply |

## Rollout

1. Land `DiffHunkApplier` + tests.
2. Wire `EditorCubit` apply/save + reload for unstaged.
3. Gutter `>>` + right editable in `SideBySideDiffView`.
4. Dirty confirm + error l10n.
5. Optional follow-up (not this spec): staged apply, `<<`, conflict UI, unified edit.
