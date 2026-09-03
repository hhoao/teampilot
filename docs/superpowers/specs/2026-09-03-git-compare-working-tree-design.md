# Git Compare with Working Tree（Git Graph → 浮动对比 tab）

**Date:** 2026-09-03  
**Status:** Approved (conversation)  
**Related:** [2026-08-25-git-graph-design.md](./2026-08-25-git-graph-design.md)

## Goal

从 Git Graph 对任意提交（有本地分支时优先以分支名作为 git 操作数与标题）发起 **Show Diff with Working Tree**，在浮动工作区打开独立「对比文件列表」tab，列出该 ref 与当前 working tree 的全部不同文件；点击文件再开现有浮动 Diff tab。模型按一等「对比」能力设计，便于后续 Swap、ref↔ref、左右分屏。

参考：JetBrains IDEA「Changes Between \<branch\> and Current Working Tree」。

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Entry | Any commit row; git operand = local branch name if present, else full hash; titles may shorten hash |
| Host | New floating tab (not Graph detail pane, not Source Control) |
| File click | Open separate floating Diff tab; keep file-list tab |
| Architecture | First-class compare domain + new FloatingSurface (not Graph/Diff special-case) |
| Compat | No backward-compat constraint; prefer clean extensibility over incremental shims |
| Out of v1 | Swap sides, ref↔ref UI, split pane, discard/checkout from compare results, custom cross-restart recovery |

## Interaction

### Entry

- Git Graph commit context menu adds **Show Diff with Working Tree**.
- Resolves `compareRef` (git operand): first local-branch decoration on the row, else the commit’s **full** hash.
- `titleRef` (UI): same branch name, or first 7–8 chars of the hash.
- Opening the same `(repoRoot, GitCompareSpec)` again activates the existing floating tab (no duplicate).

### File-list floating tab

- Title: `<titleRef> ↔ Working Tree`.
- Subtitle: difference between `<titleRef>` and current working tree.
- Body: directory tree of differing files (reuse `git_changes_*` tree presentation; folder file-counts OK).
- No stage / discard / commit actions on this pane.
- Empty: no differences. Loading: spinner. Failure: readable error in-pane (l10n); do not crash Graph.

### File → Diff

- Click file → floating `diffPreview` tab via opener.
- Diff content: `git diff <ref> -- <path>` (working tree includes staged+unstaged vs that tree-ish).
- Untracked paths: same `--no-index` convention as Source Control.
- Same path again focuses existing Diff tab.
- File-list tab remains open (split view later can host both without changing this contract).

## Architecture

Compare is a first-class capability. v1 only wires **ref ↔ workingTree**; the model already supports two arbitrary sides.

```
Git Graph context menu
  → resolve compareRef + titleRef + repoRoot + workspaceId
  → openGitCompareTab(...)
  → WorkbenchCubit.openFloating(WorkbenchTabId.gitCompare(...))
  → GitCompareFloatingSurface
      → GitComparePane + GitCompareCubit (per tab)
            → GitService / GitHistoryService (listDiffFiles, fileDiff)
  → on file tap: WorkbenchEditorOpener.openCompareDiff(...)
      → EditorCubit + DiffPreviewFloatingSurface
```

### Domain: `GitCompareSpec`

- `repoRoot: String`
- `left` / `right`: `GitCompareSide` = `ref(String)` | `workingTree`
- v1 fixed: `left = ref(compareRef)`, `right = workingTree`
- Stable tab id derived from `repoRoot` + normalized left + normalized right (use full hash / branch name, not short title)
- Display labels: branch name preferred; else short hash; working tree uses fixed l10n string

Future (same model, no rewrite):

- Swap → flip left/right (UI only in a later milestone)
- ref↔ref → both sides `ref(...)`
- Split pane → same cubit + two visual hosts; tabs stay valid as an alternate layout

### Git layer

Add (or extend) read APIs on `GitHistoryService` / `GitService`:

| API | Behavior |
|-----|----------|
| `listDiffFiles(dir, from, to)` | `List<GitFileChange>` for the two sides. When `to` is working tree: `git diff --name-status <ref>` plus untracked handling aligned with Source Control status. When both refs: `git diff --name-status A B` (ready for later UI). |
| `fileDiff(dir, from, to, path, {ignoreWhitespace, fullContext})` | Unified diff. Untracked vs empty: `--no-index`. |

Diff exit code `1` (differences present) remains success, matching existing `_runDiff`.

### State: `GitCompareCubit`

- Owns one `GitCompareSpec`, file list, loading/error, folder expand state.
- `load()` / `refresh()`; race-safe so stale responses do not overwrite a newer load.
- Does **not** live inside `GitGraphCubit`.
- Lifecycle: created for the floating tab; disposed in surface `onTabClosed`.

### Floating / workbench wiring

- New `WorkbenchTabKind.gitCompare` and FloatingSurface id `gitCompare`.
- `allowMultipleTabs: true`; identity = compare spec id.
- `openGitCompareTab` mirrors `openGitGraphTab` (ensureOpen → setActiveWorkspace → openFloating).
- Register in `FloatingSurfaceRegistry.withDefaults` and all `WorkbenchTabKind` switch sites (`surfaceIdFor`, tab bar identity, shell actions, projection, opener close paths, etc.). No “compat shims” for old kinds.

### Diff identity

- Replace the overloaded “source enum only” path with a first-class **`DiffIdentity`** (repoRoot, absolute/relative path, left/right `GitCompareSide`, plus legacy SCM cases mapped as identities).
- Do **not** overload `WorkbenchDiffSource.changes` for compare-vs-ref; migrate staged / unstaged / HEAD-changes callers onto `DiffIdentity` as part of this work if that yields a cleaner single model (no dual systems left behind).
- Identity must carry enough to reload without ambient Graph state.
- `WorkbenchEditorOpener.openCompareDiff(...)` writes EditorCubit state and opens floating Diff.

### Graph trigger

- `git_graph_menus`: new menu item + handler.
- Thin helper / controller path resolves `compareRef` / `titleRef` and calls `openGitCompareTab`.
- Graph cubit stays free of compare state.

### Layering

| Layer | Responsibility |
|-------|----------------|
| `pages/git_graph/` | Menu entry only |
| `pages/git_compare/` | `GitComparePane` UI |
| `cubits/git_compare_cubit.dart` | Per-tab compare state |
| `models/git_compare.dart` | `GitCompareSide` / `GitCompareSpec` |
| `services/git/` | `listDiffFiles` / `fileDiff` |
| `services/floating_workspace/surfaces/` | `GitCompareFloatingSurface` |
| `services/workbench/` | `openGitCompareTab`, `openCompareDiff` |
| `widgets/git/` | Reuse changes tree list presentation without SCM actions |

UI performs no git IO; cubits/services own commands. Follow `docs/CODE_QUALITY.md`.

## Data flow

1. Menu → `compareRef` + `titleRef` + `repoRoot` + `workspaceId`.
2. `openGitCompareTab` builds `GitCompareSpec(left: ref(compareRef), right: workingTree)` → open floating tab.
3. Surface builds pane with cubit → `load()` → `listDiffFiles`.
4. File tap → `openCompareDiff` → `fileDiff` → Diff tab.
5. Diff reload (ignore whitespace / full context) reuses the same `fileDiff` path.

## Errors and edge cases

| Case | Behavior |
|------|----------|
| Invalid / stale ref, not a git dir | Cubit `error`; in-pane l10n message |
| Empty file list | Empty-state copy |
| Single-file diff fails | Diff tab may still open with error/empty body; file-list tab stays |
| Untracked then deleted | Skip or soft-fail that path; do not abort whole list load |
| Large repos | Full `name-status` like existing commit detail / status (no pagination in v1) |

## Non-goals (v1)

- Swap branches / sides UI
- Choosing an arbitrary second ref in UI
- Split view inside the compare tab (file list | diff) — deferred; architecture must not block it
- Write actions (discard, checkout path, apply hunk) from the compare file list
- Special persistence/restore beyond whatever generic floating tab persistence already does

## Testing

| Area | Coverage |
|------|----------|
| Model | Spec id stability; display labels (branch vs short hash) |
| Git APIs | Command args + name-status parsing with mocked runner; untracked path handling |
| Menu | compareRef / titleRef with/without local branch decoration |
| Cubit | Success / empty / error; refresh race (stale load ignored) |
| Widget | Pane loading/empty/error; file tap invokes opener (fake) |
| Out of scope | Real git integration, floating geometry, Swap/split |

## l10n

Add en + zh keys for:

- Menu: Show Diff with Working Tree
- Tab / title patterns involving Working Tree and ↔
- Subtitle describing difference vs working tree
- Empty and error strings for the compare pane

## Implementation notes

- Prefer deleting awkward legacy assumptions in DiffSource / tab switches over preserving unused cases when wiring `gitCompare`.
- Keep Graph, Compare, and Diff surfaces independently testable.
- When split view lands later: host file tree + DiffEditorSurface under one pane reading the same `GitCompareCubit` / opener contract; do not invent a second compare model.
