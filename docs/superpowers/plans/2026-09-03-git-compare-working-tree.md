# Git Compare with Working Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From Git Graph, open a floating “ref ↔ Working Tree” file-list tab and open per-file floating Diff tabs, with a first-class compare domain and `DiffIdentity` reload model.

**Architecture:** `GitCompareSpec` / `GitCompareSide` own two-sided compare identity. `GitCompareCubit` + `GitCompareFloatingSurface` host the file list. Git APIs `listDiffFiles` / `fileDiff` feed the cubit and Diff opener. `DiffIdentity` replaces `WorkbenchDiffSource` so compare-vs-ref diffs reload without ambient Graph state.

**Tech Stack:** Flutter, flutter_bloc, existing `GitCommandRunner` / `GitHistoryService` / `GitService`, floating workspace surfaces, `git_changes_visible_rows` helpers, arb l10n.

**Spec:** `docs/superpowers/specs/2026-09-03-git-compare-working-tree-design.md`

## Global Constraints

- Edit only `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` for new strings; sync generated locals the same way other tasks in this repo do.
- Do not commit unless the user asks (ignore per-task commit steps during execution; leave the working tree ready to commit).
- No Swap UI, no ref↔ref picker, no split pane, no discard/checkout from the compare file list (v1).
- Prefer a single `DiffIdentity` model over leaving `WorkbenchDiffSource` dual-pathed.
- UI performs no git IO; cubits/services own commands (`docs/CODE_QUALITY.md`).

## File map

| Path | Role |
|------|------|
| `client/lib/models/git_compare.dart` | `GitCompareSide`, `GitCompareSpec`, title/id helpers |
| `client/lib/models/diff_identity.dart` | `DiffIdentity` sealed hierarchy; replaces `WorkbenchDiffSource` |
| `client/lib/services/git/git_history_service.dart` | `listDiffFiles`, `fileDiff` |
| `client/lib/cubits/git_compare_cubit.dart` | Per-tab compare state |
| `client/lib/pages/git_compare/git_compare_pane.dart` | File-list UI |
| `client/lib/pages/git_compare/open_git_compare.dart` | `openGitCompareTab` |
| `client/lib/pages/git_compare/git_compare_refs.dart` | `compareRef` / `titleRef` from `GitCommitRow` |
| `client/lib/services/floating_workspace/surfaces/git_compare_floating_surface.dart` | Floating host |
| `client/lib/cubits/workbench/workbench_tab.dart` | `gitCompare` kind + `DiffIdentity` tab ids |
| `client/lib/cubits/editor_cubit.dart` | `DiffTabState.identity` |
| `client/lib/services/workbench/workbench_editor_opener.dart` | `openCompareDiff` + SCM opens via `DiffIdentity` |
| `client/lib/pages/git_graph/git_graph_menus.dart` | Menu entry |

---

### Task 1: `GitCompareSide` / `GitCompareSpec`

**Files:**
- Create: `client/lib/models/git_compare.dart`
- Test: `client/test/models/git_compare_test.dart`

**Interfaces:**
- Produces:

```dart
sealed class GitCompareSide extends Equatable {
  const GitCompareSide();
  String get idKey; // 'wt' | 'ref:<nameOrHash>'
  String titleLabel({int shortHashLen = 8});
}

final class GitCompareWorkingTree extends GitCompareSide {
  const GitCompareWorkingTree();
  @override String get idKey => 'wt';
  // titleLabel uses a plain English fallback; UI prefers l10n
  @override String titleLabel({int shortHashLen = 8}) => 'Working Tree';
}

final class GitCompareRef extends GitCompareSide {
  const GitCompareRef(this.nameOrHash, {this.titleOverride});
  final String nameOrHash;
  final String? titleOverride; // short hash for titles when nameOrHash is full
  @override String get idKey => 'ref:$nameOrHash';
  @override String titleLabel({int shortHashLen = 8}) =>
      titleOverride ??
      (nameOrHash.length > shortHashLen && _looksLikeHash(nameOrHash)
          ? nameOrHash.substring(0, shortHashLen)
          : nameOrHash);
}

class GitCompareSpec extends Equatable {
  const GitCompareSpec({
    required this.repoRoot,
    required this.left,
    required this.right,
  });
  final String repoRoot;
  final GitCompareSide left;
  final GitCompareSide right;
  String get tabId => 'gitCompare:$repoRoot|${left.idKey}|${right.idKey}';
  String tabTitle() =>
      '${left.titleLabel()} ↔ ${right.titleLabel()}';
}
```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_compare.dart';

void main() {
  test('spec tabId stable for branch vs working tree', () {
    final a = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('api-dev'),
      right: const GitCompareWorkingTree(),
    );
    final b = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('api-dev'),
      right: const GitCompareWorkingTree(),
    );
    expect(a.tabId, b.tabId);
    expect(a.tabId, contains('ref:api-dev'));
    expect(a.tabId, contains('wt'));
  });

  test('title shortens full hash via titleOverride', () {
    final side = GitCompareRef(
      'abcdef0123456789',
      titleOverride: 'abcdef01',
    );
    expect(side.titleLabel(), 'abcdef01');
    expect(side.idKey, 'ref:abcdef0123456789');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/git_compare_test.dart`

Expected: FAIL (library missing)

- [ ] **Step 3: Implement `git_compare.dart`**

Implement the interfaces above. `_looksLikeHash` = `RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/git_compare_test.dart`

Expected: PASS

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 2: `listDiffFiles` + `fileDiff` on `GitHistoryService`

**Files:**
- Modify: `client/lib/services/git/git_history_service.dart`
- Modify: `client/lib/models/git_status.dart` only if a shared status→kind helper is extracted (prefer keep mapping local to history service)
- Test: `client/test/services/git/git_compare_diff_test.dart`

**Interfaces:**
- Consumes: `GitCompareSide`, existing `_run` / `_runDiff`-style exit-1-ok helper (add private `_runDiff` on history service mirroring `GitService._runDiff` if missing)
- Produces:

```dart
Future<List<GitFileChange>> listDiffFiles(
  String dir,
  GitCompareSide from,
  GitCompareSide to,
);

Future<String> fileDiff(
  String dir,
  GitCompareSide from,
  GitCompareSide to,
  String path, {
  bool ignoreWhitespace = false,
  bool fullContext = false,
  bool untracked = false,
});
```

**Behavior (v1 + forward):**
- `from = ref(R)`, `to = workingTree`:
  - Tracked: `git diff --name-status --find-renames R` → map A/M/D/R to `GitChangeKind`, `staged: false`
  - Untracked: `git ls-files --others --exclude-standard` → `GitChangeKind.untracked`, skip paths already in name-status
- `from = ref(A)`, `to = ref(B)`: `git diff --name-status --find-renames A B` (no untracked)
- `fileDiff` ref→workingTree tracked: `git diff [--no-color] [-w] [-U1000000] R -- path`
- `fileDiff` untracked: `git diff --no-index [--no-color] [-w] [-U…] /dev/null path`
- `fileDiff` ref→ref: `git diff A B -- path`
- Exit code 0 or 1 ⇒ success for diff commands

- [ ] **Step 1: Write the failing test**

Use a fake `GitCommandRunner` (same pattern as existing git service tests under `client/test/services/git/` — copy the fake from the nearest test). Assert argv for:

```dart
test('listDiffFiles ref vs working tree requests name-status and ls-files', () async {
  // stub runner responses for diff --name-status and ls-files
  final files = await history.listDiffFiles(
    '/repo',
    const GitCompareRef('api-dev'),
    const GitCompareWorkingTree(),
  );
  expect(files.map((f) => f.path), containsAll(['a.txt', 'new.txt']));
  expect(
    files.firstWhere((f) => f.path == 'new.txt').kind,
    GitChangeKind.untracked,
  );
});

test('fileDiff untracked uses --no-index', () async {
  await history.fileDiff(
    '/repo',
    const GitCompareRef('HEAD'),
    const GitCompareWorkingTree(),
    'new.txt',
    untracked: true,
  );
  // assert last argv contains '--no-index' and '/dev/null'
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/git/git_compare_diff_test.dart`

Expected: FAIL (methods missing)

- [ ] **Step 3: Implement methods on `GitHistoryService`**

Parse name-status like `commitFiles` (Rxxx\told\tnew). Map letters: A→added, M→modified, D→deleted, R→renamed, else modified.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/git/git_compare_diff_test.dart`

Expected: PASS

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 3: Introduce `DiffIdentity`; remove `WorkbenchDiffSource`

**Files:**
- Create: `client/lib/models/diff_identity.dart`
- Modify: `client/lib/cubits/workbench/workbench_tab.dart`
- Modify: `client/lib/cubits/editor_cubit.dart` (`DiffTabState`)
- Test: `client/test/models/diff_identity_test.dart`
- Test: update `client/test/cubits/workbench/workbench_tab_git_graph_test.dart` and any `WorkbenchDiffSource` unit tests

**Interfaces:**
- Produces:

```dart
enum ScmDiffMode { staged, unstaged, changes }

sealed class DiffIdentity extends Equatable {
  const DiffIdentity();
  String get absolutePath;
  /// Stable workbench / editor map key (replaces path::source.name).
  String get storageKey;
  bool get isWritableWorkingTree; // true only for ScmDiffMode.unstaged
}

final class ScmDiffIdentity extends DiffIdentity {
  const ScmDiffIdentity(this.absolutePath, this.mode);
  @override final String absolutePath;
  final ScmDiffMode mode;
  @override String get storageKey => '$absolutePath::scm.${mode.name}';
  @override bool get isWritableWorkingTree => mode == ScmDiffMode.unstaged;
}

final class CompareDiffIdentity extends DiffIdentity {
  const CompareDiffIdentity({
    required this.absolutePath,
    required this.repoRoot,
    required this.left,
    required this.right,
  });
  @override final String absolutePath;
  final String repoRoot;
  final GitCompareSide left;
  final GitCompareSide right;
  @override String get storageKey =>
      '$absolutePath::compare:$repoRoot|${left.idKey}|${right.idKey}';
  @override bool get isWritableWorkingTree => false;
}
```

- Change `WorkbenchTabId.diff` to take `DiffIdentity identity` and use `identity.storageKey` as `id`.
- Replace helpers:

```dart
factory WorkbenchTabId.diffStaged(String absolutePath, {required bool staged}) =>
  WorkbenchTabId.diff(ScmDiffIdentity(
    absolutePath,
    staged ? ScmDiffMode.staged : ScmDiffMode.unstaged,
  ));

factory WorkbenchTabId.diffChanges(String absolutePath) =>
  WorkbenchTabId.diff(ScmDiffIdentity(absolutePath, ScmDiffMode.changes));

factory WorkbenchTabId.diffCompare(CompareDiffIdentity identity) =>
  WorkbenchTabId.diff(identity);
```

- Delete `WorkbenchDiffSource` and `diffKey`/`parseDiffKey` that keyed on `::staged` etc. Provide:

```dart
static DiffIdentity? parseDiffStorageKey(String key) { /* scm + compare */ }
```

- `DiffTabState`: replace `source: WorkbenchDiffSource` with `identity: DiffIdentity`; `key => identity.storageKey`; `staged => identity is ScmDiffIdentity && mode == staged`.

- [ ] **Step 1: Write failing identity + tab id tests**

```dart
test('scm and compare keys do not collide', () {
  final scm = ScmDiffIdentity('/r/a.dart', ScmDiffMode.changes);
  final cmp = CompareDiffIdentity(
    absolutePath: '/r/a.dart',
    repoRoot: '/r',
    left: const GitCompareRef('main'),
    right: const GitCompareWorkingTree(),
  );
  expect(scm.storageKey, isNot(cmp.storageKey));
  expect(WorkbenchTabId.diff(cmp).id, cmp.storageKey);
});
```

- [ ] **Step 2: Run to verify fail / compile errors**

Run: `cd client && flutter test test/models/diff_identity_test.dart`

- [ ] **Step 3: Implement model + tab/editor type changes**

Fix compile errors in this task only as far as types require; leave call-site migrations to Task 4 if the analyzer flood is large — prefer finishing identity + `DiffTabState` + `WorkbenchTabId` here so Task 4 is mechanical.

- [ ] **Step 4: Run focused tests**

Run: `cd client && flutter test test/models/diff_identity_test.dart`

Expected: PASS

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 4: Migrate all `WorkbenchDiffSource` call sites to `DiffIdentity`

**Files (non-exhaustive — search and fix every remaining reference):**
- `client/lib/services/workbench/workbench_editor_opener.dart`
- `client/lib/services/workbench/workbench_tab_projection.dart`
- `client/lib/services/floating_workspace/surfaces/diff_preview_floating_surface.dart`
- `client/lib/pages/workbench/diff_editor_surface.dart`
- `client/lib/widgets/git/git_source_control_panel.dart`
- `client/lib/widgets/workbench/file_diff_surface_toggle.dart`
- `client/lib/pages/git_graph/git_graph_pane.dart` (working-tree changes open)
- Matching tests under `client/test/`

**Interfaces:**
- Consumes: `DiffIdentity`, updated `WorkbenchTabId.diff` / `EditorCubit.openDiff`
- Produces: `WorkbenchEditorOpener.openDiff({required DiffIdentity identity, ...})` — drop `source:` parameter
- Produces: `openChangesDiff` builds `ScmDiffIdentity(path, ScmDiffMode.changes)`
- Produces: SCM panel opens `ScmDiffIdentity(..., staged ? staged : unstaged)` or `changes` as today’s semantics dictate
- Diff surface writability: `identity.isWritableWorkingTree`
- Title helpers switch on `ScmDiffIdentity.mode` / `CompareDiffIdentity`

- [ ] **Step 1: Grep for leftovers**

Run: `cd client && rg -n 'WorkbenchDiffSource' lib test`

Expected after this task: zero matches.

- [ ] **Step 2: Migrate opener + editor openDiff signatures**

```dart
void openDiff({
  required String workspaceId,
  required DiffIdentity identity,
  required String title,
  required String diffText,
  DiffReload? reloadDiff,
  Future<void> Function()? onWorkingTreeWritten,
  bool preview = true,
}) { ... }
```

- [ ] **Step 3: Migrate UI surfaces and tests; run opener + editor + SCM-related tests**

Run: `cd client && flutter test test/services/workbench/workbench_editor_opener_test.dart test/cubits/editor_cubit_test.dart test/widgets/git/git_source_control_panel_open_file_test.dart`

Expected: PASS

- [ ] **Step 4: Full leftover grep is empty**

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 5: `GitCompareCubit`

**Files:**
- Create: `client/lib/cubits/git_compare_cubit.dart`
- Test: `client/test/cubits/git_compare_cubit_test.dart`

**Interfaces:**
- Consumes: `GitCompareSpec`, `GitHistoryService.listDiffFiles`
- Produces:

```dart
class GitCompareState extends Equatable {
  const GitCompareState({
    required this.spec,
    this.files = const [],
    this.loading = false,
    this.error,
    this.expandedFolderPaths = const {},
    this.selectedPath,
  });
  final GitCompareSpec spec;
  final List<GitFileChange> files;
  final bool loading;
  final String? error;
  final Set<String> expandedFolderPaths;
  final String? selectedPath;
}

class GitCompareCubit extends Cubit<GitCompareState> {
  GitCompareCubit({
    required GitCompareSpec spec,
    required GitHistoryService history,
  });
  Future<void> load();
  Future<void> refresh(); // alias load with race token
  void toggleFolder(String folderPath);
  void selectPath(String? path);
  Future<String?> diffFor(
    String relativePath, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
  });
}
```

`diffFor` looks up whether the path is untracked in `state.files`, then calls `history.fileDiff`.

Race: increment `_loadGen` at start of `load`; ignore results when gen mismatches.

- [ ] **Step 1: Failing cubit tests** (fake history)

```dart
test('load success emits files', () async { ... });
test('load error emits error string', () async { ... });
test('stale load does not overwrite newer', () async { ... });
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/cubits/git_compare_cubit_test.dart`

- [ ] **Step 3: Implement cubit**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 6: Floating `gitCompare` tab kind + surface + opener

**Files:**
- Create: `client/lib/services/floating_workspace/surfaces/git_compare_floating_surface.dart`
- Create: `client/lib/pages/git_compare/open_git_compare.dart`
- Modify: `client/lib/cubits/workbench/workbench_tab.dart` — add `WorkbenchTabKind.gitCompare`
- Modify: `client/lib/services/floating_workspace/floating_surface_registry.dart` — accept `gitCompare`
- Modify: `client/lib/app/app_shell.dart` — register surface
- Modify every `switch (WorkbenchTabKind` / `surfaceIdFor` / floating tab-bar identity:
  - `workbench_tab.dart` (`surfaceIdFor`)
  - `floating_workspace_tab_bar.dart`
  - `workbench_shell_actions.dart`
  - `workbench_tab_projection.dart` (throw like gitGraph for center projection)
  - `workbench_editor_opener.dart` (`_closeReplaced`)
  - any other exhaustive switches the analyzer flags
- Test: `client/test/pages/git_compare/open_git_compare_test.dart` (mirror `open_git_graph_test.dart`)

**Interfaces:**
- Produces:

```dart
// workbench_tab.dart
factory WorkbenchTabId.gitCompare(GitCompareSpec spec) =>
  WorkbenchTabId._(WorkbenchTabKind.gitCompare, spec.tabId);

// surface
class GitCompareFloatingSurface extends FloatingSurface {
  static const surfaceId = 'gitCompare';
  bool get allowMultipleTabs => true;
  FloatingTab createTab(...) {
    final spec = payload as GitCompareSpec;
    return FloatingTab(
      id: spec.tabId,
      surfaceId: surfaceId,
      title: spec.tabTitle(),
      payload: spec,
    );
  }
  // build: provide GitCompareCubit via BlocProvider; child GitComparePane (Task 7 stub OK)
}

void openGitCompareTab(
  BuildContext context, {
  required String workspaceId,
  required GitCompareSpec spec,
}) {
  floating.ensureOpen();
  floating.setActiveWorkspace(workspaceId);
  workbench.openFloating(workspaceId, WorkbenchTabId.gitCompare(spec));
}
```

**Payload plumbing:** `WorkbenchCubit.openFloating` today keys tabs by `WorkbenchTabId`. Ensure floating projection / persistence can carry `GitCompareSpec` as payload when creating the `FloatingTab` — follow how `gitGraph` maps `WorkbenchTabId.id` (repo root string) into surface `createTab(payload:)`. If floating persistence only stores id strings, encode enough in `spec.tabId` to rebuild `GitCompareSpec` via a parser (`GitCompareSpec.tryParseTabId`) implemented in this task.

```dart
static GitCompareSpec? tryParseTabId(String tabId) {
  // gitCompare:<repo>|ref:<x>|wt  or ref|ref
}
```

Surface `createTab` may receive payload from opener; when restoring from id only, parse via `tryParseTabId`.

- [ ] **Step 1: Failing open test** (panel ensured open + floating order contains gitCompare id)

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Wire kind, surface, registry, app_shell, switches, `openGitCompareTab`, `tryParseTabId`**

Stub pane: `Center(child: Text(spec.tabTitle()))` until Task 7.

- [ ] **Step 4: Run open test + `flutter analyze` on touched files**

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 7: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Sync generated: `app_localizations*.dart` (project usual path)

**Keys:**

| Key | en | zh |
|-----|----|----|
| `gitGraphShowDiffWithWorkingTree` | Show Diff with Working Tree | 与工作区比较差异 |
| `gitCompareWorkingTree` | Working Tree | 工作区 |
| `gitCompareSubtitle` | Difference between {ref} and current working tree | {ref} 与当前工作区的差异 |
| `@gitCompareSubtitle` | placeholder `ref` String | |
| `gitCompareEmpty` | No differences | 没有差异 |
| `gitCompareLoadError` | Could not load differences | 无法加载差异 |

Update `GitCompareSpec.tabTitle` / surface title to use l10n at UI layer (pane/surface), not inside the pure model — model keeps English fallback; pane builds title with `l10n.gitCompareWorkingTree`.

- [ ] **Step 1: Add arb entries (en + zh)**

- [ ] **Step 2: Regenerate or hand-sync localizations**

- [ ] **Step 3: Smoke — code referencing new getters analyzes clean**

- [ ] **Step 4: Commit** (skip unless user asks)

---

### Task 8: `GitComparePane` file tree UI

**Files:**
- Create: `client/lib/pages/git_compare/git_compare_pane.dart`
- Create: `client/lib/pages/git_compare/git_compare_file_tree.dart` (read-only tree using `visibleGitChangesRows` / folder walk; **do not** require `GitCubit` or discard)
- Test: `client/test/pages/git_compare/git_compare_pane_test.dart`
- Modify: `git_compare_floating_surface.dart` to show real pane

**Interfaces:**
- Consumes: `GitCompareCubit`, `WorkbenchEditorOpener`
- Produces: pane with header (title + subtitle), loading/error/empty, file tree
- On file open:

```dart
Future<void> _openFile(BuildContext context, GitFileChange change) async {
  final cubit = context.read<GitCompareCubit>();
  final spec = cubit.state.spec;
  final abs = p.join(spec.repoRoot, change.path);
  final identity = CompareDiffIdentity(
    absolutePath: abs,
    repoRoot: spec.repoRoot,
    left: spec.left,
    right: spec.right,
  );
  final text = await cubit.diffFor(
        change.path,
        fullContext: true,
      ) ??
      '';
  if (!context.mounted) return;
  context.read<WorkbenchEditorOpener>().openDiff(
    workspaceId: workspaceId,
    identity: identity,
    title: p.basename(change.path),
    diffText: text,
    reloadDiff: (ignoreWhitespace, fullContext) => cubit.diffFor(
      change.path,
      ignoreWhitespace: ignoreWhitespace,
      fullContext: fullContext,
    ),
  );
}
```

Tree: single section (no Unversioned split required); untracked still appear with `?` badge via `GitFileChange.kind`. Expand/collapse via cubit `expandedFolderPaths`. No checkboxes / discard.

- [ ] **Step 1: Widget test — empty / loading / file tap calls opener (fake)**

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement pane + read-only tree; wire surface**

- [ ] **Step 4: Run pane tests — PASS**

- [ ] **Step 5: Commit** (skip unless user asks)

---

### Task 9: Graph menu entry + ref helpers + `openCompareDiff` convenience

**Files:**
- Create: `client/lib/pages/git_compare/git_compare_refs.dart`
- Modify: `client/lib/pages/git_graph/git_graph_menus.dart`
- Modify: `client/lib/pages/git_graph/git_graph_pane.dart` (pass workspaceId/repoRoot into menu handler if not already available)
- Test: `client/test/pages/git_compare/git_compare_refs_test.dart`
- Test: update `client/test/pages/git_graph/git_graph_menus_test.dart`

**Interfaces:**
- Produces:

```dart
({String compareRef, String titleRef}) gitCompareRefsForCommit(GitCommitRow row) {
  for (final ref in row.refs) {
    if (ref.kind == GitRefDecorationKind.localBranch) {
      return (compareRef: ref.name, titleRef: ref.name);
    }
  }
  final hash = row.hash;
  final short = hash.length <= 8 ? hash : hash.substring(0, 8);
  return (compareRef: hash, titleRef: short);
}
```

Menu item `value: 'diff-working-tree'` near copy actions (after divider with copies is fine; prefer above copy section):

```dart
TpActionMenuSpec.item(
  value: 'diff-working-tree',
  icon: Icons.difference_outlined,
  label: l10n.gitGraphShowDiffWithWorkingTree,
),
```

Handler:

```dart
case 'diff-working-tree':
  final refs = gitCompareRefsForCommit(row);
  openGitCompareTab(
    context,
    workspaceId: workspaceId,
    spec: GitCompareSpec(
      repoRoot: repoRoot,
      left: GitCompareRef(refs.compareRef, titleOverride: refs.titleRef == refs.compareRef ? null : refs.titleRef),
      right: const GitCompareWorkingTree(),
    ),
  );
```

Ensure `showCommitContextMenu` receives `workspaceId` + `repoRoot` (add params if missing).

Optional thin wrapper on opener:

```dart
Future<void> openCompareDiff({
  required String workspaceId,
  required CompareDiffIdentity identity,
  required Future<String?> Function({bool ignoreWhitespace, bool fullContext}) loadDiff,
  String? title,
}) async { ... } // mirrors openChangesDiff
```

- [ ] **Step 1: Refs unit tests + menu test expecting new item / callback**

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement helpers, menu, pane wiring**

- [ ] **Step 4: Run:**

`cd client && flutter test test/pages/git_compare/ test/pages/git_graph/git_graph_menus_test.dart test/cubits/git_compare_cubit_test.dart test/services/git/git_compare_diff_test.dart test/models/git_compare_test.dart test/models/diff_identity_test.dart`

Expected: PASS

- [ ] **Step 5: Broader verify**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no new errors in touched areas

- [ ] **Step 6: Commit** (skip unless user asks)

---

## Spec coverage checklist

| Spec item | Task |
|-----------|------|
| Menu Show Diff with Working Tree | 9 |
| compareRef branch else full hash; titleRef short | 1, 9 |
| Floating file-list tab; reuse same spec id | 6 |
| Tree of differing files; empty/loading/error | 5, 7, 8 |
| File → separate Diff tab; list kept | 8, 4 |
| `GitCompareSpec` two-sided model | 1 |
| `listDiffFiles` / `fileDiff` + untracked | 2 |
| `GitCompareCubit` not in Graph cubit | 5 |
| `WorkbenchTabKind.gitCompare` + surface | 6 |
| `DiffIdentity` replaces overloaded source | 3, 4 |
| l10n | 7 |
| Tests: model/git/menu/cubit/widget | 1–9 |
| Non-goals (Swap/split/write) | omitted intentionally |

## Self-review notes

- No TBD/placeholder steps left; Diff persistence restore uses `GitCompareSpec.tryParseTabId` defined in Task 6.
- `GitCompareWorkingTree.titleLabel` English fallback is intentional; UI uses l10n (Task 7–8).
- Task 4 blast radius is real — keep grep-clean exit criterion.
