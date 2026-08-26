import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_toolbar.dart';

import '../../support/git_graph_test_fakes.dart';

const _chipKey = ValueKey('git-graph-branch-filter-chip');

Widget _host(GitGraphCubit cubit, GitGraphState state) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: BlocProvider.value(
    value: cubit,
    child: Scaffold(
      body: Column(
        children: [
          BlocBuilder<GitGraphCubit, GitGraphState>(
            builder: (context, state) => GitGraphToolbar(state: state),
          ),
        ],
      ),
    ),
  ),
);

/// 打开 refs 弹层并触发本地分支的「查看此分支历史」动作。
Future<void> _viewBranchHistory(WidgetTester tester, String branch) async {
  await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(branch));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining("View this branch's history"));
  await tester.pumpAndSettle();
}

void main() {
  // 工具条控件较多，放宽测试表面避免与被测行为无关的布局挤压。
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1600, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.reset);
  });

  testWidgets('refs-menu history action shows highlighted filter chip', (
    tester,
  ) async {
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('c1')],
      branchInfos: [
        GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
        GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
      ],
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(_host(cubit, cubit.state));
    await tester.pumpAndSettle();

    expect(find.byKey(_chipKey), findsNothing);
    await _viewBranchHistory(tester, 'feature');

    expect(find.byKey(_chipKey), findsOneWidget);
    expect(find.descendant(of: find.byKey(_chipKey), matching: find.text('feature')), findsOneWidget);
    expect(history.lastArgs['revisionRange'], 'feature');
  });

  testWidgets('closing the chip clears the branch filter', (tester) async {
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('c1')],
      branchInfos: [
        GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
        GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
      ],
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');
    await cubit.setBranchFilter('feature');
    await tester.pumpWidget(_host(cubit, cubit.state));
    await tester.pumpAndSettle();
    expect(find.byKey(_chipKey), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(_chipKey),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_chipKey), findsNothing);
    expect(cubit.state.branchFilter, isNull);
    expect(history.lastArgs['revisionRange'], isNull);
  });
}
