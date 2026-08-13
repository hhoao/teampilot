# SCM Commit Amend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add IDEA-style amend (merge selected changes into HEAD, optionally editing the message) to the source control panel, and move the AI commit-message generation button into the header button group.

**Architecture:** `GitService.commitAmend` issues `git add` + `git commit --amend -m <msg> [-- <paths>]`; `GitRepoStatus.hasCommits` (parsed from `branch.head (initial)`) gates the amend checkbox; `GitState.amend` drives the UI (checkbox + button label + confirm dialog); the generate button moves from `_CommitBox` to `_Header`.

**Tech Stack:** Dart/Flutter, flutter_bloc cubits, `GitService` on the active storage backend (native/WSL/SSH).

## Global Constraints

- l10n: edit only `client/lib/l10n/app_en.arb` and `app_zh.arb`; then run `flutter gen-l10n` from `client/` (the generated `app_localizations*.dart` files ARE committed).
- Verification before done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`.
- No comments in new code beyond what existing file style already has.
- Tests never spawn real `git`; service tests use the `_FakeRunner` pattern, cubit tests subclass `GitService`, widget tests use `GitService.debugOverrideFactory` (see `test/support/post_frame_test_harness.dart`).
- The generated l10n files must be committed together with the arb changes.

---

### Task 1: `GitRepoStatus.hasCommits` + `GitService.commitAmend`

**Files:**
- Modify: `client/lib/models/git_status.dart` (add `hasCommits` field)
- Modify: `client/lib/services/git/git_service.dart` (parse `(initial)`, add `commitAmend`)
- Test: `client/test/services/git/git_service_test.dart`

**Interfaces:**
- Produces: `GitRepoStatus({..., this.hasCommits = true})` — `GitRepoStatus.notARepository` sets `hasCommits: false`.
- Produces: `Future<void> GitService.commitAmend(String dir, String message, List<String> paths)` — stages `paths` (when non-empty) then runs `git commit --amend -m <message>`; appends `-- <paths>` when `paths` is non-empty. Throws `GitException` on failure via `_run`.

- [ ] **Step 1: Write the failing tests** — append to `client/test/services/git/git_service_test.dart`. In the existing `'parses porcelain v2 into staged/unstaged/branch/ahead-behind'` test, after `expect(status.behind, 1);` add:

```dart
expect(status.hasCommits, isTrue);
```

Append a new `test` to the `GitService.status` group:

```dart
test('reports hasCommits=false for an unborn branch', () async {
  const statusOut =
      '# branch.oid abcdef\n'
      '# branch.head (initial)\n'
      '1 M. N... 100644 100644 100644 h h staged_mod.txt\n';
  final runner = _FakeRunner({
    _inRepo: _ok('true\n'),
    'status': _ok(statusOut),
  });
  final service = GitService(
    runner: LocalGitCommandRunner(runner: runner.call),
  );

  final status = await service.status('/repo');

  expect(status.isRepository, isTrue);
  expect(status.hasCommits, isFalse);
});
```

Append two new tests to the `GitService mutations` group:

```dart
test('commitAmend stages the paths then amends those paths', () async {
  final runner = _FakeRunner({});
  final service = GitService(
    runner: LocalGitCommandRunner(runner: runner.call),
  );

  await service.commitAmend('/repo', 'feat: x', ['a.txt', 'b.dart']);

  expect(runner.calls, [
    ['add', '--', 'a.txt', 'b.dart'],
    ['commit', '--amend', '-m', 'feat: x', '--', 'a.txt', 'b.dart'],
  ]);
});

test('commitAmend with no paths amends the message only', () async {
  final runner = _FakeRunner({});
  final service = GitService(
    runner: LocalGitCommandRunner(runner: runner.call),
  );

  await service.commitAmend('/repo', 'fix typo', const []);

  expect(runner.calls, [
    ['commit', '--amend', '-m', 'fix typo'],
  ]);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/git/git_service_test.dart` (from `client/`)
Expected: FAIL — `hasCommits`/`commitAmend` don't exist (compile errors), or `hasCommits` is true for the unborn branch.

- [ ] **Step 3: Implement**

In `client/lib/models/git_status.dart`, add to the constructor (after `this.behind = 0`):

```dart
this.hasCommits = true,
```

and the field (after `final int behind;`):

```dart
/// False on an unborn branch (no commits yet); amend is impossible then.
final bool hasCommits;
```

Add to `GitRepoStatus.notARepository`:

```dart
static const GitRepoStatus notARepository = GitRepoStatus(
  isRepository: false,
  hasCommits: false,
);
```

Add `hasCommits` to the `props` list (after `behind`).

In `client/lib/services/git/git_service.dart` `_parseStatus`, add a local `var hasCommits = true;` at the top, and in the `# branch.head` branch make it:

```dart
if (header.startsWith('branch.head ')) {
  final value = header.substring('branch.head '.length).trim();
  if (value == '(initial)') {
    hasCommits = false;
  }
  branch = value == '(detached)' || value == '(initial)' ? null : value;
}
```

and pass it to the returned `GitRepoStatus`:

```dart
return GitRepoStatus(
  isRepository: true,
  branch: branch,
  upstream: upstream,
  ahead: ahead,
  behind: behind,
  hasCommits: hasCommits,
  staged: staged,
  unstaged: unstaged,
);
```

Add after `commitSelected`:

```dart
/// Stages [paths] (when non-empty) then amends the HEAD commit, optionally
/// restricting the amend to those paths. Empty [paths] rewrites only the
/// commit message.
Future<void> commitAmend(
  String dir,
  String message,
  List<String> paths,
) async {
  if (paths.isNotEmpty) {
    await _run(dir, ['add', '--', ...paths]);
    await _run(dir, ['commit', '--amend', '-m', message, '--', ...paths]);
  } else {
    await _run(dir, ['commit', '--amend', '-m', message]);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/git/git_service_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/git_status.dart client/lib/services/git/git_service.dart client/test/services/git/git_service_test.dart
git commit -m "feat(git): parse hasCommits and add commitAmend to GitService"
```

---

### Task 2: `GitState.amend` + cubit amend commit path

**Files:**
- Modify: `client/lib/cubits/git_cubit.dart`
- Test: `client/test/cubits/git_cubit_test.dart`

**Interfaces:**
- Consumes: `GitRepoStatus.hasCommits`, `GitService.commitAmend(String dir, String message, List<String> paths)` (Task 1).
- Produces: `GitState.amend` (bool, default `false`), `void GitCubit.setAmend(bool value)`. `GitCubit.commit()` returns `true` and clears `commitMessage` on success; when `state.amend` is true it calls `commitAmend(repoRoot, message, selectedPaths.toList())` (empty selection allowed, requires `status.hasCommits` and non-empty message), and keeps `amend` checked after success.

- [ ] **Step 1: Write the failing tests** — modify `client/test/cubits/git_cubit_test.dart`.

Add to `_FakeGitService` (after the `commitSelectedCalls` block):

```dart
final List<List<String>> commitAmendCalls = [];

@override
Future<void> commitAmend(String dir, String message, List<String> paths) async {
  commitAmendCalls.add([message, ...paths]);
}
```

Append to `main()`:

```dart
test('amend with selection stages and amends those paths', () async {
  final service = _FakeGitService(
    statusToReturn: _repoWith(staged: const [_staged]),
  );
  final cubit = GitCubit(service: service);
  await cubit.setRepoRoot('/repo'); // a.txt auto-selected
  cubit.setAmend(true);
  cubit.setCommitMessage('fix: amend');
  service.statusToReturn = _repoWith(); // clean after amend
  service.calls.clear();

  final ok = await cubit.commit();

  expect(ok, isTrue);
  expect(service.commitAmendCalls, [
    ['fix: amend', 'a.txt'],
  ]);
  expect(cubit.state.commitMessage, '');
  expect(cubit.state.amend, isTrue); // sticky after success
  await cubit.close();
});

test('amend without selection rewrites the message only', () async {
  final service = _FakeGitService(statusToReturn: _repoWith());
  final cubit = GitCubit(service: service);
  await cubit.setRepoRoot('/repo');
  cubit.setAmend(true);
  cubit.setCommitMessage('fix typo');
  service.calls.clear();

  final ok = await cubit.commit();

  expect(ok, isTrue);
  expect(service.commitAmendCalls, [
    ['fix typo'],
  ]);
  await cubit.close();
});

test('amend is a no-op when the repo has no commits yet', () async {
  final service = _FakeGitService(
    statusToReturn: GitRepoStatus(
      isRepository: true,
      branch: 'main',
      hasCommits: false,
      unstaged: const [_unstaged],
    ),
  );
  final cubit = GitCubit(service: service);
  await cubit.setRepoRoot('/repo');
  cubit.setAmend(true);
  cubit.setCommitMessage('msg');
  service.calls.clear();

  final ok = await cubit.commit();

  expect(ok, isFalse);
  expect(service.commitAmendCalls, isEmpty);
  await cubit.close();
});

test('amend is a no-op when the message is blank', () async {
  final service = _FakeGitService(
    statusToReturn: _repoWith(staged: const [_staged]),
  );
  final cubit = GitCubit(service: service);
  await cubit.setRepoRoot('/repo');
  cubit.setAmend(true);
  service.calls.clear();

  final ok = await cubit.commit();

  expect(ok, isFalse);
  expect(service.commitAmendCalls, isEmpty);
  await cubit.close();
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/cubits/git_cubit_test.dart`
Expected: FAIL — `setAmend`/`amend`/`commitAmend` don't exist.

- [ ] **Step 3: Implement** — in `client/lib/cubits/git_cubit.dart`:

Add to `GitState` constructor (after `this.generatingCommitMessage = false`):

```dart
this.amend = false,
```

Field (after `generatingCommitMessage`):

```dart
/// IDEA-style: when true the next commit amends HEAD instead of creating a
/// new commit (see [GitCubit.commit]).
final bool amend;
```

Add `bool? amend` to `copyWith` params, `amend: amend ?? this.amend,` in the body, and `amend` to `props`.

Replace the body of `commit()` (lines ~434-447) with:

```dart
Future<bool> commit() async {
  final message = state.commitMessage.trim();
  if (message.isEmpty) return false;
  if (state.amend) {
    if (!state.status.hasCommits) return false;
    final ok = await _mutate(
      () => _service.commitAmend(
        state.repoRoot,
        message,
        state.selectedPaths.toList(),
      ),
    );
    if (ok) {
      _publish(state.copyWith(commitMessage: ''), recomputeRows: false);
    }
    return ok;
  }
  final paths = state.selectedPaths.toList();
  if (paths.isEmpty) return false;
  final ok = await _mutate(
    () => _service.commitSelected(state.repoRoot, message, paths),
  );
  if (ok) {
    _publish(state.copyWith(commitMessage: ''), recomputeRows: false);
  }
  return ok;
}
```

Add a new method next to `setCommitMessage`:

```dart
void setAmend(bool value) => _publish(state.copyWith(amend: value));
```

Note: the amend branch deliberately does NOT reset `amend` on success, so consecutive amends keep working (IDEA behavior).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/cubits/git_cubit_test.dart`
Expected: PASS (existing + 4 new tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/git_cubit.dart client/test/cubits/git_cubit_test.dart
git commit -m "feat(git): amend commit path in GitCubit"
```

---

### Task 3: l10n keys + UI (header generate button, amend checkbox, confirm dialog) + widget tests

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (then `flutter gen-l10n` regenerates `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart` — commit these too)
- Modify: `client/lib/widgets/git/git_source_control_panel.dart`
- Test: `client/test/widgets/git/git_source_control_panel_generate_test.dart` (must still pass unchanged)
- Create: `client/test/widgets/git/git_source_control_panel_amend_test.dart`

**Interfaces:**
- Consumes: `GitState.amend`, `GitCubit.setAmend`, `GitState.status.hasCommits` (Tasks 1-2).
- Produces: `_Header` gains `generating` (bool), `canGenerate` (bool), `onGenerate` (VoidCallback). `_CommitBox` gains `amend` (bool), `canAmend` (bool), `onAmend` (ValueChanged<bool>); drops `canGenerate`/`onGenerate`. New `ValueKey('git-generate-commit-button')` on the header `TpIconButton`; new `ValueKey('git-amend-checkbox')` on the `Checkbox`.

- [ ] **Step 1: Add l10n keys**

In `client/lib/l10n/app_en.arb`, after the `"gitRefresh": "Refresh",` line (line ~261):

```json
  "gitAmend": "Amend last commit",
  "gitAmendCommit": "Amend Commit",
  "gitAmendConfirmTitle": "Amend last commit?",
  "gitAmendConfirmMessage": "This rewrites the last commit. If it was already pushed to a remote, a force push will be required afterwards.",
```

In `client/lib/l10n/app_zh.arb`, after the `"gitRefresh": "刷新",` line (line ~252):

```json
  "gitAmend": "修改上一次提交",
  "gitAmendCommit": "修改提交",
  "gitAmendConfirmTitle": "修改上一次提交？",
  "gitAmendConfirmMessage": "这将改写最后一次提交。如果该提交已推送到远程，之后需要强制推送。",
```

Run: `flutter gen-l10n` from `client/`.
Verify: `grep gitAmend client/lib/l10n/app_localizations.dart` shows the four getters, and `flutter analyze` reports no l10n errors.

- [ ] **Step 2: Move the generate button into `_Header`**

In `client/lib/widgets/git/git_source_control_panel.dart`:

1. In the panel builder (line ~511), change the header `BlocSelector` tuple from `(String, int, int, bool, bool)` to `(String, int, int, bool, bool, bool, bool)`, selector to:

```dart
selector: (state) => (
  state.status.branch ?? 'HEAD',
  state.status.ahead,
  state.status.behind,
  state.busy || state.isLoading,
  state.allChangeFoldersExpanded,
  state.generatingCommitMessage,
  state.selectedPaths.isNotEmpty,
),
```

and destructure `final (branch, ahead, behind, busy, allExpanded, generating, hasSelection) = header;`. Pass three new params to `_Header`:

```dart
generating: generating,
canGenerate: hasSelection && !busy && !generating,
onGenerate: () async {
  final stored = context
      .read<AiFeatureSettingsCubit>()
      .state
      .settingFor(AiFeatureId.commitMessage);
  final appProviders = context.read<AppProviderCubit>().state;
  final registry = CliToolRegistryScope.of(context);
  final presets = context.read<CliPresetsCubit>().state.presets;
  if (!aiFeatureIsConfigured(
    stored: stored,
    registry: registry,
    appProviders: appProviders,
    globalPresets: presets,
  )) {
    AppToast.show(
      context,
      message: l10n.gitGenerateCommitMessageNoProvider,
      variant: TpToastVariant.error,
    );
    return;
  }
  final setting = resolveAiFeatureSetting(
    stored: stored,
    appProviders: appProviders,
    registry: registry,
    presets: presets,
  );
  await _cubit.generateCommitMessage(setting);
},
```

2. In `_Header` (line ~677): add `required this.generating, required this.canGenerate, required this.onGenerate` to the constructor and fields:

```dart
final bool generating;
final bool canGenerate;
final VoidCallback onGenerate;
```

Insert a `TpIconButton` between the discard `PopupMenuButton` and the pull `TpIconButton` (line ~788):

```dart
TpIconButton(
  key: const ValueKey('git-generate-commit-button'),
  icon: Icons.auto_awesome_outlined,
  iconWidget: generating
      ? const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : null,
  compact: true,
  size: TpIconButton.kCompactSize,
  tooltip: l10n.gitGenerateCommitMessage,
  enabled: canGenerate && !generating,
  onTap: onGenerate,
),
```

3. In the `_CommitBox` builder (line ~540), change the selector tuple to `(bool, bool, bool, String, bool, bool)` and selector to:

```dart
selector: (state) => (
  state.selectedPaths.isNotEmpty,
  state.busy,
  state.generatingCommitMessage,
  state.status.branch ?? 'HEAD',
  state.status.hasCommits,
  state.amend,
),
```

destructure `final (hasSelection, busy, generating, branch, hasCommits, amend) = commit;`, and change the `_CommitBox` construction to:

```dart
return _CommitBox(
  controller: _commitController,
  hint: l10n.gitCommitMessageHint(branch),
  canCommit: amend ? (hasCommits && !busy) : (hasSelection && !busy),
  canAmend: hasCommits,
  amend: amend,
  generating: generating,
  onAmend: _cubit.setAmend,
  onChanged: _cubit.setCommitMessage,
  onCommit: () async {
    if (_cubit.state.amend) {
      if (!await _confirmAmend()) return;
    }
    final ok = await _cubit.commit();
    if (ok) _commitController.clear();
  },
);
```

Note: `generate` is no longer in the commit box; `canGenerate`/`onGenerate` params and the `onGenerate` closure at lines ~559-587 are deleted from this builder.

4. In `_CommitBox` (line ~815): drop `canGenerate`/`generating`/`onGenerate` from constructor + fields (keep `canCommit`, `controller`, `hint`, `onChanged`, `onCommit`); add `required this.amend, required this.canAmend, required this.onAmend` and fields `final bool amend; final bool canAmend; final ValueChanged<bool> onAmend;`. Keep `generating` usage: the `TpTextarea` keeps `enabled: !generating` — so keep the `generating` param too. The message `Row` becomes just the `Expanded(child: TpTextarea(...))` (delete the `IconButton` and the `SizedBox(width: 8)`). Between the textarea and the `FilledButton` (replacing the current `SizedBox(height: 8)`), insert:

```dart
const SizedBox(height: 4),
Row(
  children: [
    SizedBox(
      width: 24,
      height: 24,
      child: Checkbox(
        key: const ValueKey('git-amend-checkbox'),
        value: amend,
        onChanged: canAmend ? (v) => onAmend(v ?? false) : null,
        visualDensity: VisualDensity.compact,
      ),
    ),
    const SizedBox(width: 4),
    Text(l10n.gitAmend, style: TpTextStyles.of(context).sm),
  ],
),
const SizedBox(height: 4),
```

Change the button to:

```dart
FilledButton.icon(
  onPressed: canCommit ? onCommit : null,
  icon: Icon(amend ? Icons.edit_outlined : Icons.check, size: 16),
  label: Text(amend ? l10n.gitAmendCommit : l10n.gitCommit),
),
```

5. Add `_confirmAmend` next to `_confirmDiscardAll` (line ~393):

```dart
Future<bool> _confirmAmend() async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.gitAmendConfirmTitle,
            onClose: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: 16),
          Text(l10n.gitAmendConfirmMessage),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.confirm),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}
```

- [ ] **Step 3: Update the generate widget test**

`client/test/widgets/git/git_source_control_panel_generate_test.dart`:
The existing `'shows a generate-commit action button'` test finds `ValueKey('git-generate-commit-button')` — the key now lives on the header `TpIconButton`; it must still pass. Run it to confirm (Step 5).

- [ ] **Step 4: Write the amend widget test** — create `client/test/widgets/git/git_source_control_panel_amend_test.dart`, copying the harness (setUp/tearDown with `setUpTestAppStorage`, `testRuntimeContext`, `GitService.debugOverrideFactory`) and `wrap()` from `git_source_control_panel_generate_test.dart`, with this stub:

```dart
class _AmendRepoGitStub extends GitService {
  _AmendRepoGitStub() : super();

  final List<List<String>> commitAmendCalls = [];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    staged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true),
    ],
    unstaged: [],
    branch: 'main',
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];

  @override
  Future<void> commitAmend(String dir, String message, List<String> paths) async {
    commitAmendCalls.add([message, ...paths]);
  }
}
```

Tests:

```dart
testWidgets('amend checkbox toggles the commit button label', (tester) async {
  final aiSettingsCubit = AiFeatureSettingsCubit(
    repository: InMemoryAppSettingsRepository(),
  );
  final stub = _AmendRepoGitStub();
  GitService.debugOverrideFactory = () => stub;

  await tester.pumpWidget(
    wrap(
      aiSettingsCubit,
      GitSourceControlPanel(
        roots: const ['/repo'],
        workContext: workContext,
        workspaceId: 'ws-test',
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.text('Commit'), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('git-amend-checkbox')));
  await tester.pump();

  expect(find.text('Amend Commit'), findsOneWidget);
  expect(find.text('Commit'), findsNothing);

  await aiSettingsCubit.close();
});

testWidgets('amend requires confirmation; canceling does not amend', (tester) async {
  final aiSettingsCubit = AiFeatureSettingsCubit(
    repository: InMemoryAppSettingsRepository(),
  );
  final stub = _AmendRepoGitStub();
  GitService.debugOverrideFactory = () => stub;

  await tester.pumpWidget(
    wrap(
      aiSettingsCubit,
      GitSourceControlPanel(
        roots: const ['/repo'],
        workContext: workContext,
        workspaceId: 'ws-test',
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // Drive state through the cubit (the panel syncs its controller from it).
  final ctx = tester.element(find.byType(GitSourceControlPanel));
  final cubit = BlocProvider.of<GitCubit>(ctx);
  cubit.setAmend(true);
  cubit.setCommitMessage('fix: amend');
  await tester.pump();

  await tester.tap(find.text('Amend Commit'));
  await tester.pumpAndSettle();

  expect(find.text('Amend last commit?'), findsOneWidget);

  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();

  expect(stub.commitAmendCalls, isEmpty);

  await aiSettingsCubit.close();
});

testWidgets('confirming the amend dialog commits via commitAmend', (tester) async {
  final aiSettingsCubit = AiFeatureSettingsCubit(
    repository: InMemoryAppSettingsRepository(),
  );
  final stub = _AmendRepoGitStub();
  GitService.debugOverrideFactory = () => stub;

  await tester.pumpWidget(
    wrap(
      aiSettingsCubit,
      GitSourceControlPanel(
        roots: const ['/repo'],
        workContext: workContext,
        workspaceId: 'ws-test',
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  final ctx = tester.element(find.byType(GitSourceControlPanel));
  final cubit = BlocProvider.of<GitCubit>(ctx);
  cubit.setAmend(true);
  cubit.setCommitMessage('fix: amend');
  await tester.pump();

  await tester.tap(find.text('Amend Commit'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();

  expect(stub.commitAmendCalls, [
    ['fix: amend', 'a.txt'],
  ]);

  await aiSettingsCubit.close();
});
```

Required imports for the new test (mirror the generate test, plus):

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/cubits/git_cubit.dart';
```

Important: `GitRepoStore` builds the cubit's service by calling `GitService.debugOverrideFactory?.call()` (see `git_repo_store.dart` `_defaultFactory`), so the test must set `GitService.debugOverrideFactory = () => stub` with a **pre-created** stub and assert on that same `stub` — never call `debugOverrideFactory!()` after pumping (that yields a different instance than the panel's cubit uses).

Note: `tester.tap(find.text('Cancel'))` relies on the Material default English cancel label in tests.

- [ ] **Step 5: Run the tests**

Run:
```
flutter test test/services/git/git_service_test.dart test/cubits/git_cubit_test.dart test/widgets/git/git_source_control_panel_generate_test.dart test/widgets/git/git_source_control_panel_amend_test.dart
```
Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors (pre-existing warnings allowed).

- [ ] **Step 7: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/lib/widgets/git/git_source_control_panel.dart client/test/widgets/git/git_source_control_panel_amend_test.dart
git commit -m "feat(git): IDEA-style amend + move AI generate button to header"
```

---

### Task 4: Full verification

- [ ] **Step 1: Run the full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 2: Manual smoke check (optional, if a Flutter desktop build is available)**

Open the source control panel on a repo with at least one commit: toggle the amend checkbox, confirm the button label switches to "Amend Commit", cancel the dialog (no amend), then amend a selected change and verify `git log -1` reflects the amended message + changes. On an unborn branch (fresh `git init`), verify the checkbox is disabled.
