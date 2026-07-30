import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
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

class _RepoGitStub extends GitService {
  _RepoGitStub() : super();

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
}

/// Reports a per-root change count derived from the folder name's last digit,
/// so the selector badges can be asserted independently per repo.
class _MultiRepoGitStub extends GitService {
  _MultiRepoGitStub() : super();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async {
    final count = dir.endsWith('repoB') ? 3 : 1;
    return GitRepoStatus(
      isRepository: true,
      staged: [
        for (var i = 0; i < count; i++)
          GitFileChange(
            path: 'f$i.txt',
            kind: GitChangeKind.modified,
            staged: true,
          ),
      ],
      unstaged: const [],
      branch: 'main',
    );
  }

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  late GitRepoStore store;
  late RuntimeContext workContext;

  setUp(() {
    setUpTestAppStorage();
    workContext = testRuntimeContext('/home');
    GitService.debugOverrideFactory = _RepoGitStub.new;
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

  testWidgets('shows a generate-commit action button', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );

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

    expect(
      find.byKey(const ValueKey('git-generate-commit-button')),
      findsOneWidget,
    );

    await aiSettingsCubit.close();
  });

  testWidgets('multi-root shows a repo selector with per-repo change badges', (
    tester,
  ) async {
    GitService.debugOverrideFactory = _MultiRepoGitStub.new;
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );

    await tester.pumpWidget(
      wrap(
        aiSettingsCubit,
        GitSourceControlPanel(
          roots: const ['/work/repoA', '/work/repoB'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // One selector chip per workspace folder.
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('repoA'), findsOneWidget);
    expect(find.text('repoB'), findsOneWidget);

    // repoB's badge reflects its 3 staged changes.
    expect(find.text('3'), findsWidgets);

    // Switching repos updates the selection.
    await tester.tap(find.text('repoB'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final selectedB = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('repoB'), matching: find.byType(ChoiceChip)),
    );
    expect(selectedB.selected, isTrue);

    await aiSettingsCubit.close();
  });
}
