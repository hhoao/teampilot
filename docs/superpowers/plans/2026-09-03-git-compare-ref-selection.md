# Git Compare Ref Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users start a ref↔ref (or ref↔working tree) Git Compare from the Git Graph branches/tags popup, by adding a "Compare with…" item to each entry's submenu and a second-level target picker menu.

**Architecture:** Pure UI wiring on top of existing compare plumbing. `GitCompareSpec` / `GitHistoryService.listDiffFiles` / `fileDiff` already support ref↔ref; the only work is threading `workspaceId` into `GitGraphRefsMenu` and building the target-picker menu from `GitGraphState.branches` / `tags` / `currentBranch`. No model, service, cubit, or pane changes.

**Tech Stack:** Flutter + flutter_bloc (`GitGraphCubit`), shared_ui `Tp*` menu components (`showTpActionMenuFromSpecs`, `TpActionMenuSpec`), ARB-based l10n (en + zh).

**Spec:** `docs/superpowers/specs/2026-09-03-git-compare-ref-selection-design.md`

## Global Constraints

- l10n: edit `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` only (generated `app_localizations*.dart` files are regenerated, not hand-edited beyond what `flutter gen-l10n` emits).
- UI uses `Tp*` components from `shared_ui`; no new generic controls under `client/lib/widgets/`.
- State stays in `flutter_bloc`; no IO in `build()`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- All new user-visible strings must have both en and zh ARB entries.
- Commit messages end with `Co-Authored-By: Claude <noreply@anthropic.com>`.

---

### Task 1: Thread `workspaceId` into `GitGraphRefsMenu`

Pure mechanical threading so Task 2's menu code can call `openGitCompareTab`. No behavior change.

**Files:**
- Modify: `client/lib/pages/git_graph/git_graph_refs_menu.dart` (widget field)
- Modify: `client/lib/pages/git_graph/git_graph_toolbar.dart:17-48` (field + pass-through)
- Modify: `client/lib/pages/git_graph/git_graph_pane.dart:176` (pass-through at construction site)
- Modify: `client/test/pages/git_graph/git_graph_refs_menu_test.dart` (both existing call sites)

**Interfaces:**
- Consumes: `_PaneBody.workspaceId` (already exists in `git_graph_pane.dart`, `String`).
- Produces: `GitGraphRefsMenu({required GitGraphState state, required String workspaceId})` and `GitGraphToolbar({required GitGraphState state, required String workspaceId})` — Task 2 relies on both signatures.

- [ ] **Step 1: Add `workspaceId` to `GitGraphRefsMenu`**

In `client/lib/pages/git_graph/git_graph_refs_menu.dart`, change the constructor and add the field:

```dart
class GitGraphRefsMenu extends StatefulWidget {
  const GitGraphRefsMenu({
    super.key,
    required this.state,
    required this.workspaceId,
  });

  final GitGraphState state;
  final String workspaceId;
```

- [ ] **Step 2: Add `workspaceId` to `GitGraphToolbar` and pass it to the refs menu**

In `client/lib/pages/git_graph/git_graph_toolbar.dart`:

```dart
class GitGraphToolbar extends StatelessWidget {
  const GitGraphToolbar({
    super.key,
    required this.state,
    required this.workspaceId,
  });

  final GitGraphState state;
  final String workspaceId;
```

And at the `GitGraphRefsMenu` construction site (~line 48):

```dart
GitGraphRefsMenu(state: state, workspaceId: workspaceId),
```

- [ ] **Step 3: Pass `workspaceId` from `_PaneBody`**

In `client/lib/pages/git_graph/git_graph_pane.dart:176` (inside `_PaneBody.build`, which already has a `workspaceId` field):

```dart
GitGraphToolbar(state: state, workspaceId: workspaceId),
```

- [ ] **Step 4: Update existing test call sites**

Check for any other constructors the compiler will flag:

```bash
grep -rn "GitGraphRefsMenu(\|GitGraphToolbar(" /home/hhoa/git/hhoa/teampilot/client/lib /home/hhoa/git/hhoa/teampilot/client/test --include="*.dart"
```

In `client/test/pages/git_graph/git_graph_refs_menu_test.dart`, update both pump sites (lines ~41 and ~91):

```dart
child: GitGraphRefsMenu(state: cubit.state, workspaceId: 'ws'),
```

- [ ] **Step 5: Verify compile + existing tests pass**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/git_graph/
```

Expected: no new analyzer issues; all git graph tests pass.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/git_graph/git_graph_refs_menu.dart client/lib/pages/git_graph/git_graph_toolbar.dart client/lib/pages/git_graph/git_graph_pane.dart client/test/pages/git_graph/git_graph_refs_menu_test.dart
git commit -m "Thread workspaceId through git graph toolbar to refs menu

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: "Compare with…" submenu + target picker + tests

The feature itself: submenu entry on every local/remote/tag entry, a second-level target menu (working tree + local/remote/tags, source grayed out), and opening the git compare floating tab.

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (2 new keys)
- Modify: `client/lib/pages/git_graph/git_graph_refs_menu.dart` (submenu items, `_openCompareTargetMenu`, target specs builder)
- Test: `client/test/pages/git_graph/git_graph_refs_menu_test.dart` (3 new widget tests)

**Interfaces:**
- Consumes: `GitGraphRefsMenu.workspaceId` (Task 1); `openGitCompareTab(BuildContext, {required String workspaceId, required GitCompareSpec spec})` from `client/lib/pages/git_compare/open_git_compare.dart`; `GitCompareSpec(repoRoot, left, right)`, `GitCompareRef(nameOrHash, {titleOverride})`, `GitCompareWorkingTree()` from `client/lib/models/git_compare.dart`; `showTpActionMenuFromSpecs<String>(context:, globalPosition:, specs:)` from `shared_ui`.
- Produces: nothing downstream — this is the terminal UI wiring.

- [ ] **Step 1: Add l10n keys and regenerate**

In `client/lib/l10n/app_en.arb`, next to the existing `gitGraphShowDiffWithWorkingTree` key (~line 3832):

```json
"gitGraphCompareWith": "Compare with…",
"gitGraphCompareWorkingTree": "Working Tree ({branch})",
"@gitGraphCompareWorkingTree": { "placeholders": { "branch": { "type": "String" } } },
```

In `client/lib/l10n/app_zh.arb`, next to `gitGraphShowDiffWithWorkingTree` (~line 3349):

```json
"gitGraphCompareWith": "与…比较",
"gitGraphCompareWorkingTree": "工作区（{branch}）",
"@gitGraphCompareWorkingTree": { "placeholders": { "branch": { "type": "String" } } },
```

Regenerate and confirm the getters exist:

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter gen-l10n && grep -n "gitGraphCompareWith" lib/l10n/app_localizations_en.dart
```

Expected: the generated file contains `String get gitGraphCompareWith` and `String gitGraphCompareWorkingTree(String branch)`.

- [ ] **Step 2: Write the failing tests**

Append to `client/test/pages/git_graph/git_graph_refs_menu_test.dart`. Add these imports at the top:

```dart
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/git_compare.dart';
```

Add a shared pump helper and three tests inside `main()`:

```dart
Future<GitGraphCubit> _pumpRefsMenuWithCompare(
  WidgetTester tester, {
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
}) async {
  final actions = RecordingGraphActions();
  final history = FakeHistoryForGraph(
    branchInfos: [
      GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
      GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
      GitBranchInfo('origin/main', 'h0', isRemote: true, isCurrent: false),
    ],
    tagInfos: [GitTagInfo('v1.0', 'h1')],
  );
  final cubit = GitGraphCubit(
    history: history,
    git: FakeGitForGraph(repoStatus()),
    actions: actions,
  );
  addTearDown(cubit.close);
  await cubit.setRepoRoot('/repo');
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: workbench),
        RepositoryProvider.value(value: floating),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: Center(
              child: GitGraphRefsMenu(state: cubit.state, workspaceId: 'ws'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.account_tree_outlined));
  await tester.pumpAndSettle();
  return cubit;
}

GitCompareSpec? _openedCompareSpec(WorkbenchCubit workbench) {
  final tabId = workbench.state
      .bar('ws')
      .floating
      .order
      .firstWhere((t) => t.kind == WorkbenchTabKind.gitCompare)
      .id;
  return GitCompareSpec.tryParseTabId(tabId);
}

testWidgets('compare submenu opens branch vs working tree tab', (
  tester,
) async {
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  addTearDown(workbench.close);
  addTearDown(floating.close);
  await _pumpRefsMenuWithCompare(
    tester,
    workbench: workbench,
    floating: floating,
  );

  await tester.tap(find.text('feature'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Compare with…'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Working Tree (main)'));
  await tester.pumpAndSettle();

  final spec = _openedCompareSpec(workbench);
  expect(spec?.repoRoot, '/repo');
  expect(spec?.left, const GitCompareRef('feature'));
  expect(spec?.right, const GitCompareWorkingTree());
});

testWidgets('compare submenu opens branch vs remote branch tab', (
  tester,
) async {
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  addTearDown(workbench.close);
  addTearDown(floating.close);
  await _pumpRefsMenuWithCompare(
    tester,
    workbench: workbench,
    floating: floating,
  );

  await tester.tap(find.text('feature'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Compare with…'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('origin/main'));
  await tester.pumpAndSettle();

  final spec = _openedCompareSpec(workbench);
  expect(spec?.left, const GitCompareRef('feature'));
  expect(spec?.right, const GitCompareRef('origin/main'));
});

testWidgets('tag compare target menu grays out source tag', (tester) async {
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  addTearDown(workbench.close);
  addTearDown(floating.close);
  await _pumpRefsMenuWithCompare(
    tester,
    workbench: workbench,
    floating: floating,
  );

  await tester.tap(find.text('v1.0'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Compare with…'));
  await tester.pumpAndSettle();
  final item = tester.widget<TpActionMenuItem>(
    find.widgetWithText(TpActionMenuItem, 'v1.0'),
  );
  expect(item.enabled, isFalse);

  await tester.tap(find.text('main'));
  await tester.pumpAndSettle();
  final spec = _openedCompareSpec(workbench);
  expect(spec?.left, const GitCompareRef('v1.0'));
  expect(spec?.right, const GitCompareRef('main'));
});
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/pages/git_graph/git_graph_refs_menu_test.dart
```

Expected: FAIL — tapping `feature`'s submenu shows no `Compare with…` item (menu closes / nothing happens; the new tests fail on missing text).

- [ ] **Step 4: Implement the submenu items**

In `client/lib/pages/git_graph/git_graph_refs_menu.dart`, add imports:

```dart
import '../../models/git_compare.dart';
import '../git_compare/open_git_compare.dart';
```

In `_openSubmenu`, add a `compare` entry to each section's `specs`:

- local (after the `history` item):
```dart
TpActionMenuSpec.item(
  value: 'compare',
  icon: Icons.difference_outlined,
  label: l10n.gitGraphCompareWith,
),
```
- remote (after the disabled checkout item):
```dart
TpActionMenuSpec.item(
  value: 'compare',
  icon: Icons.difference_outlined,
  label: l10n.gitGraphCompareWith,
),
```
- tag (after the `delete` item):
```dart
TpActionMenuSpec.item(
  value: 'compare',
  icon: Icons.difference_outlined,
  label: l10n.gitGraphCompareWith,
),
```

In the `switch (action)` inside `_openSubmenu`, add:

```dart
case 'compare':
  await _openCompareTargetMenu(entry);
```

- [ ] **Step 5: Implement the target picker**

In the same file, add to `_GitGraphRefsMenuState`:

```dart
static const String _kWorkingTreeTarget = '__wt__';

/// 二级目标菜单：首条工作区（当前分支），其后本地 / 远程 / 标签三分区；
/// 源 ref 自身置灰。选中后打开 gitCompare 浮动 tab（left = 源，right = 目标）。
Future<void> _openCompareTargetMenu(_RefEntry source) async {
  if (!mounted) return;
  final l10n = context.l10n;
  final target = await showTpActionMenuFromSpecs<String>(
    context: context,
    globalPosition: _buttonGlobalPosition(),
    specs: _compareTargetSpecs(l10n, source),
  );
  if (target == null || !mounted) return;
  openGitCompareTab(
    context,
    workspaceId: widget.workspaceId,
    spec: GitCompareSpec(
      repoRoot: widget.state.repoRoot,
      left: GitCompareRef(source.name),
      right: target == _kWorkingTreeTarget
          ? const GitCompareWorkingTree()
          : GitCompareRef(target),
    ),
  );
}

List<TpActionMenuSpec> _compareTargetSpecs(
  AppLocalizations l10n,
  _RefEntry source,
) {
  final state = widget.state;
  final locals = state.branches.where((b) => !b.isRemote);
  final remotes = state.branches.where((b) => b.isRemote);
  return [
    TpActionMenuSpec.item(
      value: _kWorkingTreeTarget,
      icon: Icons.difference_outlined,
      label: l10n.gitGraphCompareWorkingTree(
        state.currentBranch.isEmpty ? 'HEAD' : state.currentBranch,
      ),
    ),
    const TpActionMenuSpec.divider(),
    if (locals.isNotEmpty) ...[
      _sectionHeader(Icons.call_split, l10n.gitGraphLocalBranches),
      TpActionMenuSpec.scroll(children: [
        for (final branch in locals)
          TpActionMenuSpec.item(
            value: branch.name,
            icon: Icons.call_split_outlined,
            label: branch.name,
            enabled: branch.name != source.name,
          ),
      ]),
    ],
    if (remotes.isNotEmpty) ...[
      _sectionHeader(Icons.cloud_outlined, l10n.gitGraphRemoteBranches),
      TpActionMenuSpec.scroll(children: [
        for (final branch in remotes)
          TpActionMenuSpec.item(
            value: branch.name,
            icon: Icons.cloud_outlined,
            label: branch.name,
            enabled: branch.name != source.name,
          ),
      ]),
    ],
    if (state.tags.isNotEmpty) ...[
      _sectionHeader(Icons.sell_outlined, l10n.gitGraphTags),
      TpActionMenuSpec.scroll(children: [
        for (final tag in state.tags)
          TpActionMenuSpec.item(
            value: tag.name,
            icon: Icons.sell_outlined,
            label: tag.name,
            enabled: tag.name != source.name,
          ),
      ]),
    ],
  ];
}
```

Notes for the implementer:
- `_RefSection` values are unmodified; `source.name` for a remote entry is the full `origin/…` name, so comparing `branch.name != source.name` never accidentally disables a same-named local branch.
- The existing test "remote branch submenu offers no enabled action (v1)" asserts checkout is disabled and no `Delete branch` item exists — adding the enabled compare item does not break it.

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/pages/git_graph/git_graph_refs_menu_test.dart
```

Expected: PASS (all 3 new + 2 existing tests).

- [ ] **Step 7: Full gate**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart
```

Expected: clean analyze, full suite green.

- [ ] **Step 8: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/git_graph/git_graph_refs_menu.dart client/test/pages/git_graph/git_graph_refs_menu_test.dart
git commit -m "Add branch/tag ref compare entry to git graph refs menu

Co-Authored-By: Claude <noreply@anthropic.com>"
```

- [ ] **Step 9: Manual verification (spec's manual checklist)**

Launch the app, open a workspace with a git repo, open the Git Graph branches/tags popup:
1. Local branch → "Compare with…" → "Working Tree (branch)" opens the compare tab with untracked files included.
2. Local branch → "Compare with…" → remote branch opens ref↔ref compare with the correct file list and file diffs.
3. Tag → "Compare with…" → the tag itself is grayed out; picking another branch works.
4. Opening the same pair again activates the existing tab instead of duplicating.
