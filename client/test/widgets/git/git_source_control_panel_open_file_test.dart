import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
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
  /// Recorded discardAll command args, mirroring the real `git restore .`.
  /// Static so tests can assert regardless of how many stub instances the
  /// [GitRepoStore] created.
  static final calls = <List<String>>[];

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
    staged: [],
    unstaged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: false),
      GitFileChange(
        path: 'gone.txt',
        kind: GitChangeKind.deleted,
        staged: false,
      ),
    ],
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];

  @override
  Future<void> discardAll(String dir) async {
    calls.add(['restore', '.']);
  }

  @override
  Future<String> diff(
    String dir,
    GitFileChange change, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
  }) async {
    return '--- a/${change.path}\n'
        '+++ b/${change.path}\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+new\n';
  }
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
  final openedDiffs = <String>[];

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

  @override
  void openDiff({
    required String workspaceId,
    required String absolutePath,
    required WorkbenchDiffSource source,
    required String title,
    required String diffText,
    DiffReload? reloadDiff,
    Future<void> Function()? onWorkingTreeWritten,
    bool preview = true,
  }) {
    openedDiffs.add(absolutePath);
  }
}

void main() {
  late RuntimeContext workContext;
  late GitRepoStore store;
  _RecordingOpener? opener;

  setUp(() {
    setUpTestAppStorage();
    _UnstagedGitStub.calls.clear();
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

  // TpHover renders its desktop (GestureDetector + animated fill) path on a
  // desktop platform. flutter_test defaults to Android, which would render the
  // touch (InkWell) path. The override must be reset inside the test body
  // (before flutter_test's invariant check runs), so it is set/reset via
  // try/finally rather than setUp/tearDown.
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

  /// Drives two quick left-clicks at [finder] (a double-click). Each tap must
  /// come from a fresh pointer — reusing one TestGesture for both downs trips a
  /// framework gesture-arena assertion ('isOpen': is not true).
  Future<void> doubleClick(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('double-click on a changed row opens the file', (tester) async {
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

      await doubleClick(tester, rowA);

      expect(opener!.openedPaths, ['/repo/a.txt']);
      expect(opener!.openedWorkspaceIds, ['ws-test']);
      // The opener must receive the backend filesystem (identical, not a copy)
      // so WSL/SSH workspace paths resolve against the backend.
      expect(opener!.openedFs, [same(workContext.filesystem)]);
    });
  });

  testWidgets('double-click on a deleted row does not open the file', (
    tester,
  ) async {
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

      await doubleClick(tester, rowGone);

      expect(opener!.openedPaths, isEmpty);
    });
  });

  testWidgets('single click on a changed row selects and opens the diff', (
    tester,
  ) async {
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

      // Single click selects AND opens the diff (desktop TpHover delays onTap
      // past the double-tap window when onDoubleTap is also wired). No file
      // open — that stays on double-click.
      await tester.tap(rowA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(opener!.openedDiffs, ['/repo/a.txt']);
      expect(opener!.openedPaths, isEmpty);

      // Selection enables "Discard Selected Change".
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final selectedItem = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Discard Selected Change'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(selectedItem.enabled, isTrue);
    });
  });

  testWidgets('toolbar discard-all confirms then calls discardAll', (
    tester,
  ) async {
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

    // Open the discard dropdown.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Discard All Unstaged Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Confirm dialog.
    await tester.tap(find.text('Discard changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _UnstagedGitStub.calls.any((a) => a.join(' ').contains('restore .')),
      isTrue,
    );
  });

  testWidgets('selecting a row enables Discard Selected Change', (tester) async {
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

      // Single click selects the row (desktop TpHover delays onTap past the
      // double-tap window when onDoubleTap is also wired).
      await tester.tap(rowA);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final selectedItem = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('Discard Selected Change'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(selectedItem.enabled, isTrue);
    });
  });
}
