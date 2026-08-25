import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/git_graph/git_graph_pane.dart';

import '../../support/git_graph_test_fakes.dart';

Widget host(GitGraphCubit cubit) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: BlocProvider.value(
    value: cubit,
    child: const Scaffold(
      body: GitGraphPane(workspaceId: 'ws', repoRoot: '/repo'),
    ),
  ),
);

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
