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
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/git/git_source_control_panel.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

/// 多项目工作区：面板把当前展示的 repo root 报给 lifecycle host，
/// 磁盘事件驱动的刷新以它为全速 root（GitRepoStore.refreshAll）。
class _EmptyGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async =>
      const GitRepoStatus(isRepository: false, hasCommits: false);
}

void main() {
  late RuntimeContext workContext;
  late GitRepoStore store;
  late ValueNotifier<String?> selectedRoot;

  setUp(() {
    setUpTestAppStorage();
    workContext = testRuntimeContext('/home');
    GitService.debugOverrideFactory = _EmptyGitStub.new;
    GitService.debugResetExecutableCache();
    store = GitRepoStore();
    selectedRoot = ValueNotifier<String?>(null);
  });

  tearDown(() {
    GitService.debugOverrideFactory = null;
    GitService.debugResetExecutableCache();
    store.dispose();
    tearDownTestAppStorage();
  });

  Widget wrap(Widget child) {
    final aiSettings = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit()..setActiveWorkspace('ws-test');
    addTearDown(aiSettings.close);
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RightToolsLifecycle(
        data: RightToolsLifecycleData(
          scope: const WorkspaceToolsScopeState(),
          fileTreeCubit: null,
          pokeOnTurnEnd: () {},
          ensureFileTreeReady: () {},
          selectedGitRoot: selectedRoot,
        ),
        child: MultiRepositoryProvider(
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
              BlocProvider.value(value: aiSettings),
              BlocProvider.value(value: editor),
              BlocProvider.value(value: workbench),
            ],
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  testWidgets('reports the active root on mount and selector switch', (
    tester,
  ) async {
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

    // 未选择时默认首个 root。
    expect(selectedRoot.value, '/repo-a');

    await tester.tap(find.byTooltip('/repo-b'));
    await tester.pumpAndSettle();
    expect(selectedRoot.value, '/repo-b');
  });

  testWidgets('reports fallback root when the selection is removed', (
    tester,
  ) async {
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
    await tester.tap(find.byTooltip('/repo-b'));
    await tester.pumpAndSettle();
    expect(selectedRoot.value, '/repo-b');

    // 选中项从工作区移除 → 回退首个 root 并重新上报。
    await tester.pumpWidget(
      wrap(
        GitSourceControlPanel(
          roots: const ['/repo-a'],
          workContext: workContext,
          workspaceId: 'ws-test',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(selectedRoot.value, '/repo-a');
  });
}
