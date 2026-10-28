import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
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
import 'package:teampilot/widgets/app_toast/app_toast.dart';
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

  /// When set, `push` stays in flight until completed (drives the spinner).
  Completer<void>? pushGate;

  @override
  Future<void> push(String dir) async {
    final gate = pushGate;
    if (gate != null) await gate.future;
  }

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
    final editor = EditorCubit(storage: testHomeStorage);
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
    _HeaderGitStub? stub,
  }) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    final service =
        stub ?? _HeaderGitStub(branch: branch, ahead: ahead, behind: behind);
    GitService.debugOverrideFactory = () => service;

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

  testWidgets(
    'header action buttons stay right-aligned when the panel has extra space',
    (tester) async {
      await pumpPanel(tester, branch: 'main', ahead: 0, behind: 0, width: 720);

      final panel = tester.getRect(find.byType(GitSourceControlPanel));
      final refresh = tester.getRect(find.byIcon(Icons.refresh));
      // 10px panel padding; refresh sits in a 28px compact button around a
      // 16px icon, so the glyph's right edge is inset ~16px from the panel.
      expect(refresh.right, closeTo(panel.right - 16, 2));
    },
  );

  testWidgets('push spins inside its own button and disables the others', (
    tester,
  ) async {
    final stub = _HeaderGitStub(branch: 'main', ahead: 0, behind: 0)
      ..pushGate = Completer<void>();
    await pumpPanel(
      tester,
      branch: 'main',
      ahead: 0,
      behind: 0,
      width: 720,
      stub: stub,
    );

    await tester.tap(find.byKey(const ValueKey('git-push-button')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('git-push-button')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TpIconButton>(find.byKey(const ValueKey('git-fetch-button')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TpIconButton>(
            find.byKey(const ValueKey('git-refresh-button')),
          )
          .enabled,
      isFalse,
    );

    stub.pushGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<TpIconButton>(find.byKey(const ValueKey('git-fetch-button')))
          .enabled,
      isTrue,
    );

    AppToast.dismiss();
    await tester.pump(const Duration(seconds: 1));
  });
}
