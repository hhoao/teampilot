# Source Control Git Repository Initialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Add a localized Source Control action that initializes the selected workspace folder as a Git repository and refreshes the panel.

**Architecture:** Keep Git execution behind \`GitCommandRunner\`. Add \`GitService.init\`, expose it through \`GitCubit.initializeRepository\`, and render the action only in the existing non-repository panel state. The cubit reuses \`_mutate\` so busy guarding, refresh, and error propagation match existing Git mutations.

**Tech Stack:** Flutter/Dart, \`flutter_bloc\`, \`GitService\`/\`GitCommandRunner\`, ARB localization, Flutter widget tests.

## Global Constraints

- Never invoke \`flutter test\` directly; use \`cd client && dart run tool/run_tests.dart ...\`.
- Edit only \`client/lib/l10n/app_en.arb\` and \`client/lib/l10n/app_zh.arb\` for localization source text.
- Preserve local/WSL/SSH behavior by calling the injected \`GitCommandRunner\`; do not spawn Git directly from a widget or cubit.
- User-facing errors use localized copy and the existing \`AppToast\`; diagnostics use \`AppLogger\` through \`GitService\`.
- Preserve unrelated existing worktree changes.

---

## File Map

- Modify \`client/lib/services/git/git_service.dart\`: expose \`Future<void> init(String dir)\` using the existing command runner and failure handling.
- Modify \`client/test/services/git/git_service_test.dart\`: verify the exact \`git init\` command and non-zero failure behavior.
- Modify \`client/lib/cubits/git_cubit.dart\`: add \`initializeRepository()\` using the existing mutation lifecycle.
- Modify \`client/test/cubits/git_cubit_test.dart\`: verify initialization calls the service, refreshes status, and reports errors.
- Modify \`client/lib/widgets/git/git_source_control_panel.dart\`: pass the active root's cubit action into the non-repository hint and render a button.
- Modify \`client/test/widgets/git/git_source_control_panel_selection_test.dart\`: verify visibility and selected-root routing of the button.
- Modify \`client/lib/l10n/app_en.arb\` and \`client/lib/l10n/app_zh.arb\`: add the button label.

### Task 1: Add Git service and cubit initialization behavior

**Files:**
- Modify: \`client/test/services/git/git_service_test.dart\`
- Modify: \`client/lib/services/git/git_service.dart\`
- Modify: \`client/test/cubits/git_cubit_test.dart\`
- Modify: \`client/lib/cubits/git_cubit.dart\`

**Interfaces:**
- Produces \`GitService.init(String dir) -> Future<void>\` and \`GitCubit.initializeRepository() -> Future<bool>\`.
- \`initializeRepository()\` operates on \`state.repoRoot\`, returns \`false\` when busy or when Git initialization fails, and refreshes status after a successful service call.

- [ ] **Step 1: Write the failing Git service test**

In the \`GitService mutations\` group, add:

~~~~dart
test('init issues the expected argv', () async {
  final runner = _FakeRunner({});
  final service = GitService(
    runner: LocalGitCommandRunner(runner: runner.call),
  );

  await service.init('/repo');

  expect(runner.calls, [
    ['init'],
  ]);
});

test('init throws GitException when git rejects the directory', () async {
  final runner = _FakeRunner({
    'init': ProcessResult(0, 128, '', 'permission denied'),
  });
  final service = GitService(
    runner: LocalGitCommandRunner(runner: runner.call),
  );

  expect(
    () => service.init('/repo'),
    throwsA(isA<GitException>()),
  );
});
~~~~

- [ ] **Step 2: Run the service tests and verify they fail for the missing API**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/services/git/git_service_test.dart --plain-name="init"
~~~~

Expected: compilation failure because \`GitService.init\` does not exist yet.

- [ ] **Step 3: Implement the minimal service operation**

Add this method to \`GitService\`, next to the other mutation methods:

~~~~dart
/// Initializes [dir] as a Git repository.
Future<void> init(String dir) async {
  await _run(dir, ['init']);
}
~~~~

- [ ] **Step 4: Run the service tests and verify they pass**

Run the same command from Step 2. Expected: both \`init\` tests pass.

- [ ] **Step 5: Extend the cubit fake and write the failing cubit test**

In \`client/test/cubits/git_cubit_test.dart\`, add an optional post-init status and record the operation in \`_FakeGitService\`:

~~~~dart
GitRepoStatus? statusAfterInit;

@override
Future<void> init(String dir) async {
  await _record('init:$dir');
  final next = statusAfterInit;
  if (next != null) statusToReturn = next;
}
~~~~

Then add this test:

~~~~dart
test('initializeRepository initializes the root and refreshes status', () async {
  final service = _FakeGitService(
    statusToReturn: const GitRepoStatus(
      isRepository: false,
      hasCommits: false,
    ),
  )..statusAfterInit = _repoWith();
  final cubit = GitCubit(service: service);

  await cubit.setRepoRoot('/repo');
  final initialized = await cubit.initializeRepository();

  expect(initialized, isTrue);
  expect(service.calls, contains('init:/repo'));
  expect(cubit.state.isRepository, isTrue);
  expect(cubit.state.busy, isFalse);

  await cubit.close();
});
~~~~

- [ ] **Step 6: Run the cubit test and verify it fails for the missing API**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/cubits/git_cubit_test.dart --plain-name="initializeRepository"
~~~~

Expected: compilation failure because \`GitCubit.initializeRepository\` does not exist yet.

- [ ] **Step 7: Implement the cubit action through \`_mutate\`**

Add this method before the other public Git mutations:

~~~~dart
/// Initializes the current root as a repository, then reloads its status.
Future<bool> initializeRepository() {
  final dir = state.repoRoot;
  if (dir.isEmpty) return Future<bool>.value(false);
  return _mutate(() => _service.init(dir));
}
~~~~

- [ ] **Step 8: Run the cubit test and verify it passes**

Run the same command from Step 6. Expected: the test passes and the state is a repository after refresh.

- [ ] **Step 9: Add the cubit failure regression test**

Add this test beside the success test:

~~~~dart
test('initializeRepository exposes service failures and clears busy', () async {
  final service = _FakeGitService(
    statusToReturn: const GitRepoStatus(
      isRepository: false,
      hasCommits: false,
    ),
  )..throwOnNext = GitException('permission denied');
  final cubit = GitCubit(service: service);

  await cubit.setRepoRoot('/repo');
  final initialized = await cubit.initializeRepository();

  expect(initialized, isFalse);
  expect(cubit.state.busy, isFalse);
  expect(cubit.state.errorMessage, 'permission denied');

  await cubit.close();
});
~~~~

- [ ] **Step 10: Run both cubit tests**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/cubits/git_cubit_test.dart --plain-name="initializeRepository"
~~~~

Expected: both initialization tests pass.

- [ ] **Step 11: Commit the service and cubit slice**

~~~~bash
git add client/lib/services/git/git_service.dart client/test/services/git/git_service_test.dart client/lib/cubits/git_cubit.dart client/test/cubits/git_cubit_test.dart
git commit -m "feat: support initializing git repositories"
~~~~

### Task 2: Add the localized Source Control button

**Files:**
- Modify: \`client/lib/l10n/app_en.arb\`
- Modify: \`client/lib/l10n/app_zh.arb\`
- Modify: \`client/lib/widgets/git/git_source_control_panel.dart\`
- Modify: \`client/test/widgets/git/git_source_control_panel_selection_test.dart\`

**Interfaces:**
- \`_GitCenteredHint\` accepts an optional \`action\` widget while retaining the existing hint-only rendering when no action is provided.
- \`_GitRepoBody\` passes \`_cubit.initializeRepository\` to the hint only when \`state.isRepository\` is false and Git is available.

- [ ] **Step 1: Add localization entries**

Add the same key to both ARB files:

~~~~json
"gitInitializeRepository": "Create Git repository"
~~~~

Use this value in \`app_zh.arb\`:

~~~~json
"gitInitializeRepository": "创建 Git 仓库"
~~~~

- [ ] **Step 2: Write the failing widget test for visibility and selected-root routing**

Update the test fake in \`git_source_control_panel_selection_test.dart\` with a static call list and override:

~~~~dart
static final initCalls = <String>[];

@override
Future<void> init(String dir) async {
  initCalls.add(dir);
}
~~~~

Clear \`initCalls\` in \`setUp\` and \`tearDown\`. Add this test:

~~~~dart
testWidgets('offers git initialization for the selected root', (tester) async {
  await tester.pumpWidget(
    wrap(
      GitSourceControlPanel(
        roots: const ['/repo-a', '/repo-b'],
        workContext: workContext,
        workspaceId: 'ws-test',
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Create Git repository'), findsOneWidget);

  await tester.tap(find.byTooltip('/repo-b'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create Git repository'));
  await tester.pumpAndSettle();

  expect(_EmptyGitStub.initCalls, ['/repo-b']);
});
~~~~

The existing non-repository stub means the button should remain visible after the action; the assertion is specifically that the selected root was used.

- [ ] **Step 3: Run the widget test and verify it fails**

Run:

~~~~bash
cd client && dart run tool/run_tests.dart test/widgets/git/git_source_control_panel_selection_test.dart --plain-name="offers git initialization"
~~~~

Expected: failure because the localized label and button are not rendered yet.

- [ ] **Step 4: Add the optional action slot to \`_GitCenteredHint\`**

Change its constructor and layout to:

~~~~dart
const _GitCenteredHint({
  required this.icon,
  required this.text,
  this.action,
});

final Widget? action;
~~~~

After the text, render the action only when supplied:

~~~~dart
if (action != null) ...[
  const SizedBox(height: 12),
  action!,
]
~~~~

- [ ] **Step 5: Wire the action into the non-repository state**

Replace the non-repository return in \`_GitRepoBody._buildShell\` with:

~~~~dart
return _GitCenteredHint(
  icon: Icons.source_outlined,
  text: l10n.gitNotARepository,
  action: TextButton.icon(
    onPressed: state.busy
        ? null
        : () => unawaited(_cubit.initializeRepository()),
    icon: const Icon(Icons.create_new_folder_outlined),
    label: Text(l10n.gitInitializeRepository),
  ),
);
~~~~

Keep the existing \`gitNotInstalled\` branch unchanged so the action is not offered when Git is unavailable. The \`BlocConsumer.buildWhen\` already rebuilds on \`busy\`, \`isRepository\`, and \`isLoading\`, which updates the button after initialization.

- [ ] **Step 6: Run the widget test and verify it passes**

Run the same command from Step 3. Expected: the test passes and records \`/repo-b\`.

- [ ] **Step 7: Verify the button is absent for the Git-unavailable state**

Run the existing widget test file:

~~~~bash
cd client && dart run tool/run_tests.dart test/widgets/git/git_source_control_panel_selection_test.dart
~~~~

Expected: all tests pass; no existing hint behavior regresses.

- [ ] **Step 8: Commit the UI and localization slice**

~~~~bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/widgets/git/git_source_control_panel.dart client/test/widgets/git/git_source_control_panel_selection_test.dart
git commit -m "feat: add source control git init action"
~~~~

### Task 3: Format, analyze, and run the required verification

**Files:**
- Modify only files touched by Tasks 1–2 if formatting or generated localization requires it.

- [ ] **Step 1: Format the changed Dart files**

Run:

~~~~bash
cd client && dart format lib/services/git/git_service.dart lib/cubits/git_cubit.dart lib/widgets/git/git_source_control_panel.dart test/services/git/git_service_test.dart test/cubits/git_cubit_test.dart test/widgets/git/git_source_control_panel_selection_test.dart
~~~~

Expected: formatter completes without errors.

- [ ] **Step 2: Run focused Git tests**

~~~~bash
cd client && dart run tool/run_tests.dart test/services/git/git_service_test.dart test/cubits/git_cubit_test.dart test/widgets/git/git_source_control_panel_selection_test.dart
~~~~

Expected: all selected tests pass.

- [ ] **Step 3: Run static analysis**

~~~~bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
~~~~

Expected: exit code 0 with no errors or warnings introduced by this change.

- [ ] **Step 4: Run the full required test suite once**

~~~~bash
cd client && dart run tool/run_tests.dart
~~~~

Expected: exit code 0. Do not invoke \`flutter test\` directly.

- [ ] **Step 5: Inspect the final diff and working tree**

~~~~bash
git diff --check
git status --short
git log -3 --oneline
~~~~

Expected: no whitespace errors; only the two feature commits plus pre-existing unrelated user changes are present.

