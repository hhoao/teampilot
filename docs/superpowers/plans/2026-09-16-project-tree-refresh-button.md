# Project Tree Refresh Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the force-refresh worktree button to the Session sidebar toolbar when the Project tree view is selected.

**Architecture:** Keep the behavior in `WorkspaceSidebar`, alongside the existing Project tree-only new-worktree action. The button resolves the current repository path from `WorktreeCubit` and invokes the existing `load(..., force: true)` API; the Cubit remains responsible for cache bypass and state publication.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `shared_ui` `TpIconButton`, existing sidebar widget tests through `dart run tool/run_tests.dart`.

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart ...`.
- Before claiming done, run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Preserve existing uncommitted user changes and stage only files belonging to this task.
- Use existing l10n key `worktreeRefreshTooltip`; do not edit generated localization files.
- Keep worktree access through the injected `WorktreeCubit` and `WorkspaceToolsScope`; do not add filesystem or process calls to widget build methods.

---

### Task 1: Restore and test the Project tree refresh action

**Files:**
- Modify: `client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart` — add an injected counting lister and change the Project tree toolbar expectation to cover refresh behavior.
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart:265-310` — add the Project tree-only refresh button and callback.

**Interfaces:**
- Consumes: `WorktreeCubit.load(String repoPath, {String? preferCurrentPath, bool force = false})`, `WorktreeLister`, `WorkspaceToolsScope`, `throttledTap`, and `context.l10n.worktreeRefreshTooltip`.
- Produces: A visible `TpIconButton` with tooltip `Refresh worktrees` in Project tree mode; tapping it calls `WorktreeCubit.load` for `state.repoPath` or `workspace.firstFolderPath` with `force: true`.

- [ ] **Step 1: Add the failing widget assertion and test seam**

In `workspace_sidebar_manual_groups_test.dart`, add a local `WorktreeLister` fake near the workspace/session helpers:

```dart
class _CountingWorktreeLister implements WorktreeLister {
  var calls = 0;
  final listedPaths = <String>[];

  @override
  Future<List<GitWorktree>> list(String repoPath) async {
    calls++;
    listedPaths.add(repoPath);
    return const [];
  }
}
```

Add the fake to the `late` declarations and replace the current
`worktreeCubit = WorktreeCubit(storage: testHomeStorage);` setup line:

```dart
late _CountingWorktreeLister worktreeLister;

setUp(() {
  setUpTestAppStorage();
  sessionRepository = SessionRepository(storage: testHomeStorage);
  chatCubit = testChatCubit(
    executableResolver: () => 'claude',
    sessionRepository: sessionRepository,
  );
  automationCubit = testAutomationCubit();
  worktreeLister = _CountingWorktreeLister();
  worktreeCubit = WorktreeCubit(
    storage: testHomeStorage,
    lister: worktreeLister,
  );
  attentionCubit = AgentAttentionCubit(pruneInterval: null);
  groupsCubit = SessionGroupsCubit(storage: testHomeStorage);
});
```

In the existing `switches to project tree without changing sessions` test, replace the current negative refresh assertion:

```dart
expect(find.byTooltip('Refresh worktrees'), findsOneWidget);
```

Then tap the tooltip and wait for the asynchronous Cubit load to finish:

```dart
await tester.tap(find.byTooltip('Refresh worktrees'));
await tester.pump();
await tester.pump(const Duration(milliseconds: 120));

expect(worktreeLister.calls, 1);
expect(worktreeLister.listedPaths, [_workspace.firstFolderPath]);
```

Run only this test file before changing production code:

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart --plain-name="switches to project tree without changing sessions"
```

Expected: FAIL because the refresh tooltip is absent after switching to Project tree. If the test errors before reaching that assertion, fix only the test setup/imports until it fails for the missing button.

- [ ] **Step 2: Implement the smallest Project tree toolbar change**

`workspace_sidebar.dart` already imports `worktree_cubit.dart`. Replace its
current Project tree toolbar branch with this branch, leaving the Groups branch
and the following archive button unchanged:

In the toolbar row, insert the refresh button immediately before the existing
new-worktree button, using the same capability gate and repository fallback:

```dart
} else if (toolsContext != null &&
    worktreeManagementEnabled(toolsContext)) ...[
  const SizedBox(width: 2),
  TpIconButton(
    icon: Icons.refresh_rounded,
    compact: true,
    size: TpIconButton.kCompactSize,
    tooltip: l10n.worktreeRefreshTooltip,
    onTap: throttledTap(
      'workspace_sidebar_refresh_worktrees',
      () {
        final cubit = context.read<WorktreeCubit>();
        final repoPath = cubit.state.repoPath.trim().isNotEmpty
            ? cubit.state.repoPath
            : widget.workspace.firstFolderPath;
        unawaited(cubit.load(repoPath, force: true));
      },
    ),
  ),
  const SizedBox(width: 2),
  TpIconButton(
    icon: Icons.account_tree_outlined,
    compact: true,
    size: TpIconButton.kCompactSize,
    tooltip: l10n.worktreeNewWorktreeTooltip,
    onTap: throttledTap(
      'workspace_sidebar_new_worktree',
      () => unawaited(_createWorktree(context)),
    ),
  ),
]
```

Do not add a second refresh mechanism, change the `ProjectTreeSection` API, or put the button in the Groups branch.

- [ ] **Step 3: Run the focused test and confirm green**

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart --plain-name="switches to project tree without changing sessions"
```

Expected: PASS, including one injected lister call for `/tmp/huji`. The pre-existing Project tree tests must remain in the same file and continue to compile.

- [ ] **Step 4: Run the complete sidebar test file**

```bash
cd client
dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart
```

Expected: all tests in the file pass with zero failures.

- [ ] **Step 5: Run static analysis**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: exit code 0 with no new errors or warnings attributable to the change.

- [ ] **Step 6: Review the diff and commit the implementation**

```bash
git diff --check
git diff -- client/lib/pages/home_workspace/workspace/workspace_sidebar.dart client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart
git status --short
git add -- client/lib/pages/home_workspace/workspace/workspace_sidebar.dart client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart
git commit -m "fix(sidebar): restore project tree refresh action"
```

Confirm the staged diff contains only the two implementation files; leave unrelated existing modifications unstaged.

### Final Verification

- [ ] **Step 7: Run the required full verification before reporting completion**

Run exactly:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
```

Expected: analysis exits successfully and the test wrapper reports zero failures. If unrelated pre-existing failures occur, report their exact output and distinguish them from this change.
