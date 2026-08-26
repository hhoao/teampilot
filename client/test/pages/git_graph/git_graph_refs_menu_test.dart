import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_refs_menu.dart';

import '../../support/git_graph_test_fakes.dart';

void main() {
  testWidgets('refs menu lists sections and deletes branch via submenu', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    final history = FakeHistoryForGraph(
      branchInfos: [
        GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
        GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
        GitBranchInfo('origin/main', 'h0', isRemote: true, isCurrent: false),
      ],
      tagInfos: [GitTagInfo('v1.0', 'h1')],
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
      actions: actions,
    );
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: Center(child: GitGraphRefsMenu(state: cubit.state)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开弹层后出现平铺分区头与条目。
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Local branches'), findsOneWidget);
    expect(find.text('Remote branches'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('v1.0'), findsOneWidget);

    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Delete branch feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TpButton).last); // 接受确认
    await tester.pumpAndSettle();
    expect(actions.calls.single, ['branch', '-d', 'feature']);
  });

  testWidgets('remote branch submenu offers no enabled action (v1)', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    final history = FakeHistoryForGraph(
      branchInfos: [
        GitBranchInfo('origin/main', 'h0', isRemote: true, isCurrent: false),
      ],
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
      actions: actions,
    );
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: Center(child: GitGraphRefsMenu(state: cubit.state)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('origin/main'));
    await tester.pumpAndSettle();
    // v1：远程分支仅列出，checkout 禁用（禁用条目点击不弹子菜单）。
    final item = tester.widget<TpActionMenuItem>(
      find.widgetWithText(TpActionMenuItem, 'Checkout origin/main'),
    );
    expect(item.enabled, isFalse);
    expect(find.widgetWithText(TpActionMenuItem, 'Delete branch'), findsNothing);
    expect(actions.calls, isEmpty);
  });
}
