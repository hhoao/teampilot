# Git Graph Commit Compare Design

## Goal

From the Git commit graph, compare two commits (or a commit against a branch,
tag, or the working tree) using the existing Git Compare pane. Commit and
branch/tag menus share one target picker.

## Current behavior

`GitHistoryService.listDiffFiles` / `fileDiff` already support `GitCompareRef`
on both sides. Branch and tag menus open Compare via **Compare with…** and a
second menu (working tree, local branches, remotes, tags).

A commit row only has **Show Diff with Working Tree**. The left side prefers
the first local-branch decoration (`gitCompareRefsForCommit`); otherwise it
uses the commit hash. There is no commit-to-commit entry, and the graph is
single-select.

## Design

### Shared target picker

Extract the compare-target overlay from `GitGraphRefsMenu` into
`client/lib/pages/git_graph/git_graph_compare_targets.dart`.

Both the commit context menu and the branch/tag **Compare with…** action call
it. Menu values are `GitCompareSide` instances (`GitCompareWorkingTree` or
`GitCompareRef`), not bare strings.

Target order:

1. Working tree (current branch name in the existing label)
2. Local branches
3. Remote branches
4. Tags
5. Commits already loaded in `GitGraphState.rows` (`GitCommitRow` only)

Each ref/commit group uses the existing `TpActionMenuSpec.scroll` region.
The picker does not call `loadMore` and does not run git.

Commit rows show `short hash + space + subject`, using the same shortening as
`GitCompareRef.titleLabel` (8 chars when the hash is longer). The value is
`GitCompareRef(fullHash)`. Compare tab titles keep using `titleLabel`.

Disable the item whose `nameOrHash` exactly equals the source. Do not also
disable other refs that happen to point at the same commit; an empty diff
uses the existing Compare empty state.

### Opening Compare

Selection opens the existing floating Git Compare tab:

```text
GitCompareSpec(
  repoRoot: current repo,
  left:  source,
  right: chosen GitCompareSide,
)
```

- Commit context menu: `left` is `GitCompareRef(row.hash)` — that snapshot,
  not a moving branch name.
- Branch/tag menu: `left` stays `GitCompareRef(ref name)`.

`GitComparePane` and the history service are unchanged.

### Commit context menu

Replace **Show Diff with Working Tree** with **Compare with…** (reuse
`gitGraphCompareWith`). Choosing it opens the shared picker at the same
anchor as the context menu.

Delete `gitCompareRefsForCommit` and `git_compare_refs.dart` when they have
no remaining callers, along with `git_compare_refs_test.dart`.

### Copy

- Reuse `gitGraphCompareWith` and `gitGraphCompareWorkingTree`.
- Add a commits section header in `app_en.arb` / `app_zh.arb`.
- Remove `gitGraphShowDiffWithWorkingTree` from both arb files.

Commit row labels are not localized.

## Errors

The picker only reads current graph state. Git failures stay in Compare:
`gitCompareLoadError` with retry, or `gitCompareEmpty` when the sides match.
A stale hash from a later graph refresh is the same load-error path.

## Testing

Widget tests, no real git:

- Commit menu shows **Compare with…** and does not show **Show Diff with
  Working Tree**.
- Compare with working tree: `left` is the commit hash even when the row has
  a local branch; `right` is working tree.
- Compare with another loaded commit: both sides are hashes.
- The source commit is disabled in the commits list.
- Branch **Compare with…** can select a loaded commit.
- Existing branch/tag compare tests still pass after the picker moves
  (working tree and ref targets); update them if menu values become
  `GitCompareSide` instead of strings.

Do not add `GitHistoryService` tests; ref-vs-ref diff is already covered.

## Scope

No graph multi-select, no click-second-commit shortcut, no in-menu search or
loadMore, no Compare header for changing sides after the tab is open.
