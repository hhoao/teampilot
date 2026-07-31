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
| Scope (v1) | Unstaged working-tree diffs; side-by-side only |
| Writable side | Right only (working tree). Left is always read-only |
| Apply direction | `>>` left → right only (no `<<`) |
| Apply persistence | Immediate `atomicWrite` + reload |
| Hand edits | Dirty → existing Save UX; then reload |
| Staged / compare-commit / Unified | Remain read-only; no `>>` |
| Merge conflict three-way | Out of scope |
| Architecture | Canonical right file text + pure `DiffHunkApplier`; display may keep filler alignment |

## Non-goals

- Staged / index mutation via apply or edit
- Bidirectional `<<` into HEAD/index
- Merge conflict Ours/Theirs UI
- Editable unified view
- Stage single hunk (git add -p)
- Binary / oversized files beyond current diff limits

## Invariants

1. **Canonical right text has no fillers.** Alignment blanks are display-only; Save and `>>` always write real file bytes.
2. **Apply and Save share one write path:** `atomicWrite(absolutePath, text)` → `diffReload` → Git status refresh.
3. **Staged tabs stay read-only.** `WorkbenchDiffSource.staged` must not enable edit or `>>`.
4. **Fail soft:** write failure must not leave the UI claiming success; keep prior editor/diff state.
5. **SSH / WSL / local:** all writes go through the workspace `Filesystem` (same as `EditorCubit.saveFile`).

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
- Hand edit updates canonical text + marks dirty (diff-tab dirty keyed by diff key or absolute path — prefer absolute path so an open File tab stays consistent if both are open).
- Save writes canonical text via the same filesystem path as `saveFile`.

If the same path is open as a File tab and a Diff tab, after Diff Save/apply: refresh or mark the File tab buffer from disk (match existing multi-surface refresh patterns if any; otherwise reload file handle text).

### 4. Interaction

| Action | Behavior |
|--------|----------|
| Click `>>` on a block | If dirty → confirm discard edits or cancel. Else apply → write → reload → SCM refresh |
| Type on right (unstaged SxS) | Dirty; Save enabled |
| Save | Write canonical → clear dirty → reload |
| Staged / Unified | No `>>`; right read-only |
| Deleted / untracked edge | Enable `>>` only when `absolutePath` is writable and apply can produce a valid file body; else disable + tooltip |

### 5. Errors

| Case | UX |
|------|----|
| Write failure | Snackbar / l10n; keep prior canonical + dirty state; do not reload as success |
| Reload failure after successful write | Message: saved but refresh failed; offer retry reload |
| External file change while dirty | Prompt reload vs keep edits |
| Binary / too large | Keep current non-editable diff policy |

### 6. l10n

Add strings for: apply hunk tooltip, dirty-discard confirm, apply/save failure, reload-after-save failure, disabled apply reason (e.g. staged read-only / missing path). Edit `app_en.arb` / `app_zh.arb` only.

## Testing

| Layer | Cases |
|-------|--------|
| Unit `DiffHunkApplier` | insert / delete / modify; head/tail; empty; multi-apply; invalid block |
| Cubit | apply writes + reload; dirty confirm cancel; write failure leaves state |
| Widget | unstaged SxS shows `>>`; staged / unified do not; tap invokes apply |

## Rollout

1. Land `DiffHunkApplier` + tests.
2. Wire `EditorCubit` apply/save + reload for unstaged.
3. Gutter `>>` + right editable in `SideBySideDiffView`.
4. Dirty confirm + error l10n.
5. Optional follow-up (not this spec): staged apply, `<<`, conflict UI, unified edit.
