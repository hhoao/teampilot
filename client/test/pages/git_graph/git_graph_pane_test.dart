import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_pane.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope_registry.dart';
import 'package:teampilot/services/git/git_repo_store.dart';

import '../../support/git_graph_test_fakes.dart';
import '../../support/fixed_resume_lifecycle_service.dart';
import '../../support/test_runtime_context.dart';

Widget host(GitGraphCubit cubit, {WorkbenchEditorOpener? opener}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MultiProvider(
        providers: [
          BlocProvider.value(value: cubit),
          if (opener != null) Provider<WorkbenchEditorOpener>.value(value: opener),
        ],
        child: const Scaffold(
          body: GitGraphPane(workspaceId: 'ws', repoRoot: '/repo'),
        ),
      ),
    );

/// 记录 openChangesDiff 调用的 [WorkbenchEditorOpener] 替身。
class _RecordingOpener implements WorkbenchEditorOpener {
  final Map<String, Object?> calls = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> openChangesDiff({
    required String workspaceId,
    required String absolutePath,
    required Future<String?> Function({bool ignoreWhitespace, bool fullContext})
    loadDiff,
    String? title,
    bool preview = true,
  }) async {
    calls['workspaceId'] = workspaceId;
    calls['absolutePath'] = absolutePath;
    calls['title'] = title;
    calls['diff'] = await loadDiff(ignoreWhitespace: false, fullContext: true);
  }
}

void main() {
  testWidgets('scrolling to bottom twice triggers two loadMore fetches',
      (tester) async {
    final history = FullPagesChainHistory();
    final cubit = GitGraphCubit(history: history, git: FakeGitForGraph(repoStatus()));
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(host(cubit));
    await tester.pumpAndSettle();
    expect(cubit.state.rows.length, 300);
    expect(cubit.state.hasMore, isTrue);

    Future<void> scrollToEnd() async {
      // 多次小幅拖动，模拟真实滚轮到底；每次后等帧让 ListView 布局。
      for (var i = 0; i < 40; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    await scrollToEnd();
    expect(history.loadMoreCalls, greaterThanOrEqualTo(1),
        reason: '第一次触底应触发 loadMore');
    expect(cubit.state.isLoadingMore, isFalse);
    expect(cubit.state.rows.length, greaterThan(300));

    // 记录第一轮后继续滚动：应再次触发新的加载（链路可重复）。
    final callsAfterFirst = history.loadMoreCalls;
    final rowsAfterFirst = cubit.state.rows.length;

    await scrollToEnd();
    expect(history.loadMoreCalls, greaterThan(callsAfterFirst),
        reason: '第二次触底应继续触发 loadMore');
    expect(cubit.state.rows.length, greaterThan(rowsAfterFirst));
  });

  testWidgets('renders commit rows and uncommitted pseudo row when dirty', (
    tester,
  ) async {
    final history = FakeHistoryForGraph(rows: [graphCommitRow('c1')]);
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(dirtyStatus()),
    );
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(host(cubit));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-graph-row-c1')), findsOneWidget);
    expect(find.textContaining('Uncommitted'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('tapping uncommitted row opens workspace changes diff', (
    tester,
  ) async {
    final opener = _RecordingOpener();
    final history = FakeHistoryForGraph(rows: [graphCommitRow('c1')]);
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(dirtyStatus(), diffText: 'diff --git a/x b/x'),
    );
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(host(cubit, opener: opener));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Uncommitted'));
    await tester.pumpAndSettle();

    expect(opener.calls['workspaceId'], 'ws');
    expect(opener.calls['absolutePath'], '/repo');
    expect(opener.calls['title'], 'Uncommitted changes');
    expect(opener.calls['diff'], 'diff --git a/x b/x');
    await cubit.close();
  });

  testWidgets('hash mode with no matching loaded rows shows load-more hint', (
    tester,
  ) async {
    final history = FakeHistoryForGraph(rows: [graphCommitRow('abcdef1')]);
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(host(cubit));
    await tester.pumpAndSettle();
    await cubit.search('zzz', GitSearchMode.hash);
    await tester.pumpAndSettle();

    expect(find.textContaining('No loaded commit matches'), findsOneWidget);
    // 非 hash 模式或无过滤时不出现该提示。
    await cubit.clearSearch();
    await tester.pumpAndSettle();
    expect(find.textContaining('No loaded commit matches'), findsNothing);
    await cubit.close();
  });

  testWidgets('conflict errors append guidance hint in the status bar', (
    tester,
  ) async {
    final history = FakeHistoryForGraph(rows: [graphCommitRow('c1')]);
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(host(cubit));
    await tester.pumpAndSettle();

    cubit.surfaceError('boom failed');
    await tester.pumpAndSettle();
    expect(find.textContaining('boom failed'), findsOneWidget);
    expect(find.textContaining('Resolve the conflicts'), findsNothing);

    cubit.surfaceError('CONFLICT (content): Merge conflict in a.dart');
    await tester.pumpAndSettle();
    expect(find.textContaining('Resolve the conflicts'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('not-a-repo state shows hint', (tester) async {
    final cubit = GitGraphCubit(
      history: FakeHistoryForGraph(),
      git: FakeGitForGraph(notRepoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(host(cubit));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); // 工具条隐藏
    expect(find.text('Not a git repository'), findsOneWidget);
    await cubit.close();
  });

  testWidgets('remounting via store does not close or reuse a closed cubit', (
    tester,
  ) async {
    final workContext = testRuntimeContext('/home');
    var created = 0;
    final store = GitRepoStore(
      graphCubitFactory: (root, ctx) {
        created++;
        return GitGraphCubit(
          history: FakeHistoryForGraph(rows: [graphCommitRow('c1')]),
          git: FakeGitForGraph(repoStatus()),
        );
      },
    );
    addTearDown(store.dispose);

    final lifecycle = FixedResumeLifecycleService(resume: false);
    // 注册 'ws' 的 scope cubit：Pane 当前从 registry 直接解析后端上下文。
    final registry = WorkspaceToolsScopeRegistry();
    addTearDown(registry.dispose);
    final scopeCubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
    addTearDown(scopeCubit.close);
    await scopeCubit.sync(
      workspaceFolders: const [
        WorkspaceFolder(path: '/repo', targetId: 'local'),
      ],
      cwd: '/repo',
      additionalPaths: const [],
    );
    final registered = registry.cubitFor(tabScopeId: 'ws', lifecycle: lifecycle);
    await registered.sync(
      workspaceFolders: const [
        WorkspaceFolder(path: '/repo', targetId: 'local'),
      ],
      cwd: '/repo',
      additionalPaths: const [],
    );
    addTearDown(registered.close);

    Widget storeHost() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MultiProvider(
        providers: [
          Provider<GitRepoStore>.value(value: store),
          ListenableProvider<WorkspaceToolsScopeRegistry>.value(
            value: registry,
          ),
        ],
        child: const Scaffold(
          body: GitGraphPane(workspaceId: 'ws', repoRoot: '/repo'),
        ),
      ),
    );

    // 首次挂载：store 路径创建并渲染。
    await tester.pumpWidget(storeHost());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('git-graph-row-c1')), findsOneWidget);
    expect(created, 1);
    final retained = store.graphCubitFor(
      '/repo',
      workContext: workContext,
    );
    expect(retained.isClosed, isFalse);

    // 关闭浮动面板：卸载 pane（修复前此处 BlocProvider 会误关保留 cubit）。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    // 卸载不得关闭 store 保留的 cubit；重开复用同一存活实例，不抛 StateError。
    expect(store.graphCubitFor('/repo', workContext: workContext), same(retained));
    expect(retained.isClosed, isFalse);
    await tester.pumpWidget(storeHost());
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(find.byKey(const ValueKey('git-graph-row-c1')), findsOneWidget);
  });
}
