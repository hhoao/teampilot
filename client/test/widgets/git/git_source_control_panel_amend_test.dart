import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/widgets/git/git_source_control_panel.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

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

class _UnbornBranchGitStub extends GitService {
  _UnbornBranchGitStub() : super();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
    hasCommits: false,
    unstaged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: false),
    ],
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  late GitRepoStore store;
  late RuntimeContext workContext;

  setUp(() {
    setUpTestAppStorage();
    workContext = testRuntimeContext('/home');
    GitService.debugResetExecutableCache();
    store = GitRepoStore();
  });

  tearDown(() {
    store.dispose();
    GitService.debugOverrideFactory = null;
    GitService.debugResetExecutableCache();
    tearDownTestAppStorage();
  });

  Widget wrap(AiFeatureSettingsCubit aiSettingsCubit, Widget child) {
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws-test');
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<GitRepoStore>.value(value: store),
          RepositoryProvider<WorkbenchEditorOpener>.value(
            value: WorkbenchEditorOpener(
              editor: editor,
              workbench: workbench,
              floating: floating,
              markdownViewModes: MarkdownViewModeStore(),
              readMarkdownOpenMode: () => MarkdownOpenMode.preview,
            ),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: aiSettingsCubit),
            BlocProvider.value(value: editor),
            BlocProvider.value(value: workbench),
          ],
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  testWidgets('amend checkbox is disabled on an unborn branch', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    final stub = _UnbornBranchGitStub();
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

    final checkbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('git-amend-checkbox')),
    );
    expect(checkbox.onChanged, isNull);

    await aiSettingsCubit.close();
  });

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
    // The panel's cubit is the store's cached instance for this root.
    final GitCubit cubit = store.cubitFor('/repo', workContext: workContext);
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

    final GitCubit cubit = store.cubitFor('/repo', workContext: workContext);
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
}
