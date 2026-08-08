import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/widgets/git/git_change_tile.dart';
import 'package:teampilot/widgets/git/git_source_control_panel.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

class _UnstagedGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
    staged: [],
    unstaged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: false),
      GitFileChange(path: 'gone.txt', kind: GitChangeKind.deleted, staged: false),
    ],
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

class _RecordingOpener extends WorkbenchEditorOpener {
  _RecordingOpener({
    required super.editor,
    required super.workbench,
    required super.floating,
  }) : super(
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );

  final openedPaths = <String>[];
  final openedWorkspaceIds = <String>[];
  final openedFs = <Filesystem>[];

  @override
  Future<void> openFile(
    String workspaceId,
    String path, {
    Filesystem? fs,
    bool preview = true,
  }) async {
    openedPaths.add(path);
    openedWorkspaceIds.add(workspaceId);
    openedFs.add(fs!);
  }
}

void main() {
  late RuntimeContext workContext;
  late GitRepoStore store;
  _RecordingOpener? opener;

  setUp(() {
    setUpTestAppStorage();
    workContext = testRuntimeContext('/home');
    GitService.debugOverrideFactory = _UnstagedGitStub.new;
    GitService.debugResetExecutableCache();
    store = GitRepoStore();
  });

  tearDown(() {
    GitService.debugOverrideFactory = null;
    GitService.debugResetExecutableCache();
    store.dispose();
    tearDownTestAppStorage();
  });

  Widget wrap(AiFeatureSettingsCubit aiSettingsCubit, Widget child) {
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws-test');
    opener = _RecordingOpener(editor: editor, workbench: workbench, floating: floating);
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<GitRepoStore>.value(value: store),
          RepositoryProvider<WorkbenchEditorOpener>.value(value: opener!),
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

  Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(finder));
    await tester.pump();
    return gesture;
  }

  // TpHover renders its desktop (GestureDetector + animated fill) path on a
  // desktop platform. flutter_test defaults to Android, which would render the
  // touch (InkWell) path with no onHoverChanged callback. The override must be
  // reset inside the test body (before flutter_test's invariant check runs), so
  // it is set/reset via try/finally rather than setUp/tearDown.
  Future<void> runOnDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('open-file button opens the changed file', (tester) async {
    await runOnDesktop(tester, () async {
      final aiSettingsCubit = AiFeatureSettingsCubit(
        repository: InMemoryAppSettingsRepository(),
      );
      addTearDown(aiSettingsCubit.close);

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

      final rowA = find.ancestor(
        of: find.text('a.txt'),
        matching: find.byType(GitChangeTile),
      );
      expect(rowA, findsOneWidget);

      final gesture = await hover(tester, rowA);
      await tester.tap(find.byIcon(Icons.file_open_outlined));
      await tester.pump();

      expect(opener!.openedPaths, ['/repo/a.txt']);
      expect(opener!.openedWorkspaceIds, ['ws-test']);
      // The opener must receive the backend filesystem (identical, not a copy)
      // so WSL/SSH workspace paths resolve against the backend.
      expect(opener!.openedFs, [same(workContext.filesystem)]);
      await gesture.removePointer();
    });
  });

  testWidgets('deleted rows do not show the open-file button', (tester) async {
    await runOnDesktop(tester, () async {
      final aiSettingsCubit = AiFeatureSettingsCubit(
        repository: InMemoryAppSettingsRepository(),
      );
      addTearDown(aiSettingsCubit.close);

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

      final rowGone = find.ancestor(
        of: find.text('gone.txt'),
        matching: find.byType(GitChangeTile),
      );
      expect(rowGone, findsOneWidget);

      final gesture = await hover(tester, rowGone);

      expect(find.byIcon(Icons.file_open_outlined), findsNothing);
      await gesture.removePointer();
    });
  });
}
