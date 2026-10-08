# Git Graph Commit Compare Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Git graph commit (or branch/tag) open the existing Git Compare pane against the working tree, another ref, or a currently loaded commit, from one shared **Compare with…** target picker.

**Architecture:** Extract the compare-target overlay from `GitGraphRefsMenu` into `git_graph_compare_targets.dart`. Menu values are `GitCompareSide`. The picker reads `GitGraphState` only (no git, no `loadMore`). Commit-row compare uses `GitCompareRef(row.hash)` as left; branch/tag compare keeps the ref name. `GitComparePane` and `GitHistoryService` stay unchanged.

**Tech Stack:** Flutter/Dart, `shared_ui` `TpActionMenuSpec` / `showTpActionMenuOverlay`, `GitCompareSpec` / `openGitCompareTab`, ARB l10n, Flutter widget tests via `dart run tool/run_tests.dart`.

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart <paths>`.
- Inner loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` on touched files, then the one test file for that task.
- Edit l10n source only in `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`; regenerate with `cd client && flutter gen-l10n`. Do not hand-edit `app_localizations*.dart`.
- Do not change `GitComparePane` or `GitHistoryService`.
- Do not add graph multi-select, click-second-commit, in-menu search, picker `loadMore`, or Compare-header side swapping.
- Preserve unrelated existing worktree changes.

---

## File Map

- Create: `client/lib/pages/git_graph/git_graph_compare_targets.dart` — `gitCompareTargetSpecs` + `showGitCompareTargetMenu`.
- Create: `client/test/pages/git_graph/git_graph_compare_targets_test.dart` — specs-builder unit tests.
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` — add `gitGraphCommits`; later remove `gitGraphShowDiffWithWorkingTree`.
- Modify: `client/lib/pages/git_graph/git_graph_refs_menu.dart` — delete private compare overlay; call `showGitCompareTargetMenu`.
- Modify: `client/lib/pages/git_graph/git_graph_menus.dart` — replace **Show Diff with Working Tree** with **Compare with…**.
- Modify: `client/test/pages/git_graph/git_graph_refs_menu_test.dart` — keep WT/ref compare; add branch vs loaded commit.
- Modify: `client/test/pages/git_graph/git_graph_menus_test.dart` — commit-menu compare cases; drop WT-only item assertion.
- Delete: `client/lib/pages/git_compare/git_compare_refs.dart` and `client/test/pages/git_compare/git_compare_refs_test.dart` after the last caller is gone.

### Task 1: Shared compare-target specs

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Create: `client/test/pages/git_graph/git_graph_compare_targets_test.dart`
- Create: `client/lib/pages/git_graph/git_graph_compare_targets.dart`

**Interfaces:**
- Consumes: `GitGraphState`, `GitCompareRef`, `GitCommitRow`, `AppLocalizations.gitGraphCompareWorkingTree` / `gitGraphLocalBranches` / `gitGraphRemoteBranches` / `gitGraphTags` / `gitGraphCommits`.
- Produces: `List<TpActionMenuSpec> gitCompareTargetSpecs({required AppLocalizations l10n, required GitGraphState state, required GitCompareRef source})`.
- Menu item `value` is a `GitCompareSide` (`GitCompareWorkingTree` or `GitCompareRef`). Commit labels are `'${GitCompareRef(row.hash).titleLabel()} ${row.subject}'`. Disable when `GitCompareRef.nameOrHash` equals `source.nameOrHash`. Skip `GitGraphSpacerRow`. Omit empty ref/commit groups. Do not call git or `loadMore`.

- [ ] **Step 1: Add the commits section string**

In `client/lib/l10n/app_en.arb`, immediately after `"gitGraphTags": "Tags",` add:

~~~~json
  "gitGraphCommits": "Commits",
~~~~

In `client/lib/l10n/app_zh.arb`, immediately after `"gitGraphTags": "标签",` add:

~~~~json
  "gitGraphCommits": "提交",
~~~~

Do not remove `gitGraphShowDiffWithWorkingTree` in this task.

- [ ] **Step 2: Regenerate l10n**

Run:

~~~~bash
cd client && flutter gen-l10n
~~~~

Expected: exit 0. `AppLocalizations.gitGraphCommits` exists in generated files.

- [ ] **Step 3: Write the failing specs tests**

Create `client/test/pages/git_graph/git_graph_compare_targets_test.dart`:

~~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_compare_targets.dart';

import '../../support/git_graph_test_fakes.dart';

List<TpActionMenuSpec> flattenItems(List<TpActionMenuSpec> specs) {
  final out = <TpActionMenuSpec>[];
  for (final spec in specs) {
    if (spec.isDivider) continue;
    if (spec.isScrollBlock) {
      out.addAll(spec.scrollChildren!);
    } else {
      out.add(spec);
    }
  }
  return out;
}

GitGraphState sampleState({
  required List<GitGraphRow> rows,
}) =>
    GitGraphState(
      repoRoot: '/repo',
      currentBranch: 'main',
      branches: const [
        GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
        GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
        GitBranchInfo('origin/main', 'h0', isRemote: true, isCurrent: false),
      ],
      tags: const [GitTagInfo('v1.0', 'h1')],
      rows: rows,
    );

void main() {
  final l10n = AppLocalizationsEn();
  final commitA = graphCommitRow('aaaaaaaaaaaaaaaa');
  final commitB = graphCommitRow('bbbbbbbbbbbbbbbb');

  test('order is working tree, refs, then loaded commits; spacers skipped', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(
        rows: [
          commitA,
          const GitGraphSpacerRow(edges: []),
          commitB,
        ],
      ),
      source: GitCompareRef(commitA.hash),
    );
    final labels = flattenItems(specs).map((s) => s.label).toList();
    expect(labels, [
      'Working Tree (main)',
      'Local branches',
      'main',
      'feature',
      'Remote branches',
      'origin/main',
      'Tags',
      'v1.0',
      'Commits',
      'aaaaaaaa ${commitA.subject}',
      'bbbbbbbb ${commitB.subject}',
    ]);
    expect(
      flattenItems(specs).map((s) => s.value).whereType<GitCompareWorkingTree>(),
      hasLength(1),
    );
  });

  test('source commit hash is disabled; other commit and same-tip branch stay enabled', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA, commitB]),
      source: GitCompareRef(commitA.hash),
    );
    final items = flattenItems(specs);
    final sourceCommit = items.singleWhere(
      (s) => s.value == GitCompareRef(commitA.hash),
    );
    final otherCommit = items.singleWhere(
      (s) => s.value == GitCompareRef(commitB.hash),
    );
    final feature = items.singleWhere((s) => s.value == const GitCompareRef('feature'));
    expect(sourceCommit.enabled, isFalse);
    expect(otherCommit.enabled, isTrue);
    expect(feature.enabled, isTrue);
  });

  test('source branch name is disabled in the branch list', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA]),
      source: const GitCompareRef('feature'),
    );
    final items = flattenItems(specs);
    expect(
      items.singleWhere((s) => s.value == const GitCompareRef('feature')).enabled,
      isFalse,
    );
    expect(
      items.singleWhere((s) => s.value == GitCompareRef(commitA.hash)).enabled,
      isTrue,
    );
  });

  test('omits empty commit group', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: const []),
      source: const GitCompareRef('feature'),
    );
    expect(flattenItems(specs).any((s) => s.label == 'Commits'), isFalse);
  });
}
~~~~

- [ ] **Step 4: Run the specs tests and confirm they fail to compile**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/pages/git_graph/git_graph_compare_targets_test.dart
~~~~

Expected: FAIL — `git_graph_compare_targets.dart` / `gitCompareTargetSpecs` does not exist.

- [ ] **Step 5: Implement `gitCompareTargetSpecs`**

Create `client/lib/pages/git_graph/git_graph_compare_targets.dart` with this builder (overlay opener comes in Task 2; you may leave a file with only the specs function for now):

~~~~dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/git_compare.dart';
import '../../models/git_graph.dart';

List<TpActionMenuSpec> gitCompareTargetSpecs({
  required AppLocalizations l10n,
  required GitGraphState state,
  required GitCompareRef source,
}) {
  final locals = state.branches.where((b) => !b.isRemote);
  final remotes = state.branches.where((b) => b.isRemote);
  final commits = state.rows.whereType<GitCommitRow>();
  return [
    TpActionMenuSpec.item(
      value: const GitCompareWorkingTree(),
      icon: Icons.difference_outlined,
      label: l10n.gitGraphCompareWorkingTree(
        state.currentBranch.isEmpty ? 'HEAD' : state.currentBranch,
      ),
    ),
    const TpActionMenuSpec.divider(),
    if (locals.isNotEmpty) ...[
      _sectionHeader(Icons.call_split, l10n.gitGraphLocalBranches),
      TpActionMenuSpec.scroll(
        children: [
          for (final branch in locals)
            TpActionMenuSpec.item(
              value: GitCompareRef(branch.name),
              icon: Icons.call_split_outlined,
              label: branch.name,
              enabled: branch.name != source.nameOrHash,
            ),
        ],
      ),
    ],
    if (remotes.isNotEmpty) ...[
      _sectionHeader(Icons.cloud_outlined, l10n.gitGraphRemoteBranches),
      TpActionMenuSpec.scroll(
        children: [
          for (final branch in remotes)
            TpActionMenuSpec.item(
              value: GitCompareRef(branch.name),
              icon: Icons.cloud_outlined,
              label: branch.name,
              enabled: branch.name != source.nameOrHash,
            ),
        ],
      ),
    ],
    if (state.tags.isNotEmpty) ...[
      _sectionHeader(Icons.sell_outlined, l10n.gitGraphTags),
      TpActionMenuSpec.scroll(
        children: [
          for (final tag in state.tags)
            TpActionMenuSpec.item(
              value: GitCompareRef(tag.name),
              icon: Icons.sell_outlined,
              label: tag.name,
              enabled: tag.name != source.nameOrHash,
            ),
        ],
      ),
    ],
    if (commits.isNotEmpty) ...[
      _sectionHeader(Icons.commit, l10n.gitGraphCommits),
      TpActionMenuSpec.scroll(
        children: [
          for (final row in commits)
            TpActionMenuSpec.item(
              value: GitCompareRef(row.hash),
              icon: Icons.commit,
              label:
                  '${GitCompareRef(row.hash).titleLabel()} ${row.subject}',
              enabled: row.hash != source.nameOrHash,
            ),
        ],
      ),
    ],
  ];
}

TpActionMenuSpec _sectionHeader(IconData icon, String label) =>
    TpActionMenuSpec.item(icon: icon, label: label, enabled: false);
~~~~

- [ ] **Step 6: Re-run specs tests and analyze**

Run:

~~~~bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/git_graph/git_graph_compare_targets.dart test/pages/git_graph/git_graph_compare_targets_test.dart && dart run tool/run_tests.dart test/pages/git_graph/git_graph_compare_targets_test.dart
~~~~

Expected: analyze clean; all four tests PASS.

- [ ] **Step 7: Commit**

~~~~bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/pages/git_graph/git_graph_compare_targets.dart client/test/pages/git_graph/git_graph_compare_targets_test.dart
git commit -m "$(cat <<'EOF'
Add shared git compare target specs including loaded commits.

EOF
)"
~~~~

### Task 2: Shared overlay + branch/tag Compare with…

**Files:**
- Modify: `client/lib/pages/git_graph/git_graph_compare_targets.dart`
- Modify: `client/lib/pages/git_graph/git_graph_refs_menu.dart`
- Modify: `client/test/pages/git_graph/git_graph_refs_menu_test.dart`

**Interfaces:**
- Consumes: `gitCompareTargetSpecs` from Task 1; `openGitCompareTab`; `GitGraphRefsMenu.state` / `workspaceId`.
- Produces: `Future<void> showGitCompareTargetMenu({required BuildContext context, required Offset globalPosition, required String workspaceId, required GitGraphState state, required GitCompareRef source})`.
- On selection: `openGitCompareTab(..., spec: GitCompareSpec(repoRoot: state.repoRoot, left: source, right: target))`. Cancel (`null`) is a no-op. Overlay uses `showTpActionMenuOverlay<GitCompareSide>` with `useRootNavigator: true`, 160ms `easeOutCubic`, `TpActionMenuPanel(minWidth: 200, menuAnchorShell: true)`.

- [ ] **Step 1: Write the failing branch-vs-commit widget test**

In `client/test/pages/git_graph/git_graph_refs_menu_test.dart`, add rows to a dedicated test (do not change existing compare tests' empty `rows`). After the existing `tag compare target menu grays out source tag` test, add:

~~~~dart
  testWidgets('compare submenu opens branch vs loaded commit tab', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);
    final commit = graphCommitRow('abcdef1234567890');
    final actions = RecordingGraphActions();
    final history = FakeHistoryForGraph(
      rows: [commit],
      branchInfos: [
        GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
        GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
      ],
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
                child: GitGraphRefsMenu(
                  state: cubit.state,
                  workspaceId: 'ws',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abcdef12 ${commit.subject}'));
    await tester.pumpAndSettle();

    final spec = openedCompareSpec(workbench);
    expect(spec?.left, const GitCompareRef('feature'));
    expect(spec?.right, GitCompareRef(commit.hash));
  });
~~~~

- [ ] **Step 2: Run the refs-menu tests and confirm the new case fails**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/pages/git_graph/git_graph_refs_menu_test.dart --plain-name "compare submenu opens branch vs loaded commit tab"
~~~~

Expected: FAIL — commit section is not in the branch compare menu (label not found).

- [ ] **Step 3: Add `showGitCompareTargetMenu` and switch the refs menu onto it**

Add these imports to `client/lib/pages/git_graph/git_graph_compare_targets.dart`:

~~~~dart
import '../../l10n/l10n_extensions.dart';
import '../git_compare/open_git_compare.dart';
~~~~

Append:

~~~~dart
Future<void> showGitCompareTargetMenu({
  required BuildContext context,
  required Offset globalPosition,
  required String workspaceId,
  required GitGraphState state,
  required GitCompareRef source,
}) async {
  if (!context.mounted) return;
  final l10n = context.l10n;
  final target = await showTpActionMenuOverlay<GitCompareSide>(
    context: context,
    globalPosition: globalPosition,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 160),
    transitionCurve: Curves.easeOutCubic,
    menuBuilder: (overlayContext, complete) {
      final children = buildTpActionMenuChildren(
        context: overlayContext,
        specs: gitCompareTargetSpecs(
          l10n: l10n,
          state: state,
          source: source,
        ),
        menuController: TpActionMenuController(TpPopoverController()),
        onSelect: (value) => complete(value as GitCompareSide?),
      );
      return DecoratedBox(
        decoration: TpActionMenuMetrics.panelDecoration(overlayContext),
        child: Padding(
          padding: TpActionMenuMetrics.panelPadding,
          child: TpActionMenuPanel(
            minWidth: 200,
            menuAnchorShell: true,
            children: children,
          ),
        ),
      );
    },
  );
  if (target == null || !context.mounted) return;
  openGitCompareTab(
    context,
    workspaceId: workspaceId,
    spec: GitCompareSpec(
      repoRoot: state.repoRoot,
      left: source,
      right: target,
    ),
  );
}
~~~~

In `client/lib/pages/git_graph/git_graph_refs_menu.dart`:

1. Add `import 'git_graph_compare_targets.dart';` and keep `import '../../models/git_compare.dart';`.
2. Remove `import '../git_compare/open_git_compare.dart';` if unused after the change.
3. Replace the `'compare'` switch case with:

~~~~dart
      case 'compare':
        await showGitCompareTargetMenu(
          context: context,
          globalPosition: _buttonGlobalPosition(),
          workspaceId: widget.workspaceId,
          state: widget.state,
          source: GitCompareRef(entry.name),
        );
~~~~

4. Delete `_kWorkingTreeTarget`, `_openCompareTargetMenu`, and `_compareTargetSpecs` entirely.

- [ ] **Step 4: Re-run refs-menu tests and analyze**

Run:

~~~~bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/git_graph/git_graph_compare_targets.dart lib/pages/git_graph/git_graph_refs_menu.dart test/pages/git_graph/git_graph_refs_menu_test.dart && dart run tool/run_tests.dart test/pages/git_graph/git_graph_refs_menu_test.dart test/pages/git_graph/git_graph_compare_targets_test.dart
~~~~

Expected: analyze clean; all refs-menu compare tests still pass (WT and `origin/main` / `main` targets); new branch-vs-commit test PASS.

- [ ] **Step 5: Commit**

~~~~bash
git add client/lib/pages/git_graph/git_graph_compare_targets.dart client/lib/pages/git_graph/git_graph_refs_menu.dart client/test/pages/git_graph/git_graph_refs_menu_test.dart
git commit -m "$(cat <<'EOF'
Share git compare target menu between refs and upcoming commit actions.

EOF
)"
~~~~

### Task 3: Commit context menu Compare with…

**Files:**
- Modify: `client/test/pages/git_graph/git_graph_menus_test.dart`
- Modify: `client/lib/pages/git_graph/git_graph_menus.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Delete: `client/lib/pages/git_compare/git_compare_refs.dart`
- Delete: `client/test/pages/git_compare/git_compare_refs_test.dart`

**Interfaces:**
- Consumes: `showGitCompareTargetMenu` from Task 2; `showCommitContextMenu(..., GitGraphState state, workspaceId, repoRoot)`.
- Commit **Compare with…** uses `source: GitCompareRef(row.hash)` — never `gitCompareRefsForCommit` / branch decorations.
- After this task `gitCompareRefsForCommit` has no callers; delete it.

- [ ] **Step 1: Rewrite commit-menu compare tests as failing tests**

In `client/test/pages/git_graph/git_graph_menus_test.dart`:

Replace `menu shows Show Diff with Working Tree item` with:

~~~~dart
  testWidgets('commit menu shows Compare with… and not Working Tree shortcut', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    await _pumpMenuHost(tester, actions, graphCommitRow('c1'));
    expect(find.text('Compare with…'), findsOneWidget);
    expect(find.text('Show Diff with Working Tree'), findsNothing);
  });
~~~~

Replace `diff-working-tree menu opens git compare tab for branch` and `diff-working-tree menu uses commit hash when no branch` with tests that open **Compare with…** then pick a target. Update `_pumpCompareMenuHost` so `FakeHistoryForGraph.rows` includes the commits used as targets (the menu reads `cubit.state.rows`).

~~~~dart
  testWidgets('compare with working tree uses commit hash even when row has a branch', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final actions = RecordingGraphActions();
    final row = graphCommitRow(
      'abcdef1234567890',
      refs: const [
        GitRefDecoration(GitRefDecorationKind.localBranch, 'main'),
      ],
    );
    await _pumpCompareMenuHost(
      tester,
      actions,
      row,
      workbench,
      floating,
      historyRows: [row],
    );
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working Tree (main)'));
    await tester.pumpAndSettle();

    final tabId = workbench.mergedFloatingStrip('ws').order
        .firstWhere((t) => t.kind == WorkbenchTabKind.gitCompare)
        .id;
    final spec = GitCompareSpec.tryParseTabId(tabId);
    expect(spec?.repoRoot, '/repo');
    expect(spec?.left, const GitCompareRef('abcdef1234567890'));
    expect(spec?.right, const GitCompareWorkingTree());
  });

  testWidgets('compare with another loaded commit uses both hashes', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final actions = RecordingGraphActions();
    final left = graphCommitRow('aaaaaaaaaaaaaaaa');
    final right = graphCommitRow('bbbbbbbbbbbbbbbb');
    await _pumpCompareMenuHost(
      tester,
      actions,
      left,
      workbench,
      floating,
      historyRows: [left, right],
    );
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bbbbbbbb ${right.subject}'));
    await tester.pumpAndSettle();

    final tabId = workbench.mergedFloatingStrip('ws').order
        .firstWhere((t) => t.kind == WorkbenchTabKind.gitCompare)
        .id;
    final spec = GitCompareSpec.tryParseTabId(tabId);
    expect(spec?.left, GitCompareRef(left.hash));
    expect(spec?.right, GitCompareRef(right.hash));
  });

  testWidgets('source commit is disabled in compare target list', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final actions = RecordingGraphActions();
    final row = graphCommitRow('aaaaaaaaaaaaaaaa');
    await _pumpCompareMenuHost(
      tester,
      actions,
      row,
      workbench,
      floating,
      historyRows: [row],
    );
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    final item = tester.widget<TpActionMenuItem>(
      find.widgetWithText(
        TpActionMenuItem,
        'aaaaaaaa ${row.subject}',
      ),
    );
    expect(item.enabled, isFalse);
  });
~~~~

Change `_pumpCompareMenuHost` signature to take `historyRows` and pass them into `FakeHistoryForGraph`:

~~~~dart
Future<void> _pumpCompareMenuHost(
  WidgetTester tester,
  RecordingGraphActions actions,
  GitCommitRow row,
  WorkbenchCubit workbench,
  FloatingWorkspaceCubit floating, {
  required List<GitGraphRow> historyRows,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final cubit = GitGraphCubit(
    history: FakeHistoryForGraph(rows: historyRows),
    git: FakeGitForGraph(repoStatus()),
    actions: actions,
  );
  addTearDown(cubit.close);
  await cubit.setRepoRoot('/repo');
  final controller = GitGraphActionsController(cubit: cubit);
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
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showCommitContextMenu(
                context,
                const Offset(200, 200),
                row,
                controller,
                cubit.state,
                workspaceId: 'ws',
                repoRoot: '/repo',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
~~~~

- [ ] **Step 2: Run commit-menu tests and confirm they fail**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/pages/git_graph/git_graph_menus_test.dart --plain-name "Compare with"
~~~~

Expected: FAIL — commit menu still shows **Show Diff with Working Tree**, not a second-level target picker keyed off the commit hash.

- [ ] **Step 3: Wire the commit menu and delete the old left-ref helper**

In `client/lib/pages/git_graph/git_graph_menus.dart`:

1. Replace `import '../git_compare/git_compare_refs.dart';` and `import '../git_compare/open_git_compare.dart';` with `import 'git_graph_compare_targets.dart';`.
2. Replace the `'diff-working-tree'` switch case with:

~~~~dart
    case 'compare':
      await showGitCompareTargetMenu(
        context: context,
        globalPosition: position,
        workspaceId: workspaceId,
        state: state,
        source: GitCompareRef(row.hash),
      );
~~~~

3. In `_menuSpecs`, replace the `diff-working-tree` item with:

~~~~dart
  TpActionMenuSpec.item(
    value: 'compare',
    icon: Icons.difference_outlined,
    label: l10n.gitGraphCompareWith,
  ),
~~~~

4. Delete `client/lib/pages/git_compare/git_compare_refs.dart` and `client/test/pages/git_compare/git_compare_refs_test.dart`.
5. Remove `"gitGraphShowDiffWithWorkingTree"` (and any `@gitGraphShowDiffWithWorkingTree` block) from `app_en.arb` and `app_zh.arb`.
6. Run `cd client && flutter gen-l10n`.

`repoRoot` remains a `showCommitContextMenu` parameter even if the picker uses `state.repoRoot`; do not churn the signature.

- [ ] **Step 4: Re-run menu tests, leftover refs-helper tests, and analyze**

Run:

~~~~bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/git_graph/git_graph_menus.dart lib/pages/git_graph/git_graph_compare_targets.dart lib/pages/git_graph/git_graph_refs_menu.dart test/pages/git_graph/ && dart run tool/run_tests.dart test/pages/git_graph/git_graph_menus_test.dart test/pages/git_graph/git_graph_refs_menu_test.dart test/pages/git_graph/git_graph_compare_targets_test.dart test/pages/git_compare/
~~~~

Expected: analyze clean; commit-menu tests PASS; refs-menu tests PASS; specs tests PASS; `git_compare_refs_test.dart` is gone and remaining `test/pages/git_compare/` tests PASS.

- [ ] **Step 5: Commit**

~~~~bash
git add client/lib/pages/git_graph/git_graph_menus.dart client/test/pages/git_graph/git_graph_menus_test.dart client/lib/pages/git_compare/git_compare_refs.dart client/test/pages/git_compare/git_compare_refs_test.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart
git commit -m "$(cat <<'EOF'
Open git compare from commits via the shared Compare with menu.

EOF
)"
~~~~

`git add` of the deleted refs helper should be `git add -u` on those two paths so the deletion is staged.
