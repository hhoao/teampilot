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

class _HeaderGitStub extends GitService {
  _HeaderGitStub({
    required this.branch,
    required this.ahead,
    required this.behind,
  }) : super();

  final String branch;
  final int ahead;
  final int behind;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => GitRepoStatus(
    isRepository: true,
    branch: branch,
    ahead: ahead,
    behind: behind,
    hasCommits: true,
    staged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true),
    ],
    unstaged: [
      GitFileChange(path: 'b.txt', kind: GitChangeKind.modified, staged: false),
    ],
  );

  @override
  Future<List<String>> branches(String dir) async => [branch];

  @override
  Future<String> headCommitMessage(String dir) async => 'feat: last commit';
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

  Widget wrap(
    AiFeatureSettingsCubit aiSettingsCubit,
    Widget child,
    double width,
  ) {
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
          child: Scaffold(
            body: SizedBox(width: width, height: 500, child: child),
          ),
        ),
      ),
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required String branch,
    required int ahead,
    required int behind,
    double width = 300,
  }) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    GitService.debugOverrideFactory = () =>
        _HeaderGitStub(branch: branch, ahead: ahead, behind: behind);

    await tester.pumpWidget(
      wrap(
        aiSettingsCubit,
        GitSourceControlPanel(
          roots: const ['/repo'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
        width,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    addTearDown(aiSettingsCubit.close);
  }

  testWidgets(
    'header shows a long branch name with ahead/behind in a narrow panel '
    'without overflowing',
    (tester) async {
      await pumpPanel(
        tester,
        branch: 'chore/ci-release-prep',
        ahead: 171,
        behind: 0,
        width: 240,
      );

      expect(find.text('chore/ci-release-prep'), findsOneWidget);
      expect(find.byIcon(Icons.account_tree_outlined), findsNWidgets(2));
    },
  );

  testWidgets(
    'header shows the ahead/behind counter when the panel is wide enough ',
    (tester) async {
      await pumpPanel(
        tester,
        branch: 'chore/ci-release-prep',
        ahead: 171,
        behind: 0,
        width: 520,
      );

      expect(find.text('chore/ci-release-prep'), findsOneWidget);
      expect(find.text('↑171 ↓0'), findsOneWidget);
    },
  );
}
