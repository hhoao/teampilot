import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_pane.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/git_graph_test_fakes.dart';

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
}
