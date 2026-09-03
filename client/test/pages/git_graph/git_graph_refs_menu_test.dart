import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_compare.dart';
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
            body: Center(
              child: GitGraphRefsMenu(state: cubit.state, workspaceId: 'ws'),
            ),
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
            body: Center(
              child: GitGraphRefsMenu(state: cubit.state, workspaceId: 'ws'),
            ),
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

  Future<GitGraphCubit> _pumpRefsMenuWithCompare(
    WidgetTester tester, {
    required WorkbenchCubit workbench,
    required FloatingWorkspaceCubit floating,
  }) async {
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
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: workbench),
          RepositoryProvider.value(value: floating),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: Center(
                child: GitGraphRefsMenu(state: cubit.state, workspaceId: 'ws'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    return cubit;
  }

  GitCompareSpec? _openedCompareSpec(WorkbenchCubit workbench) {
    final tabId = workbench.state
        .bar('ws')
        .floating
        .order
        .firstWhere((t) => t.kind == WorkbenchTabKind.gitCompare)
        .id;
    return GitCompareSpec.tryParseTabId(tabId);
  }

  testWidgets('compare submenu opens branch vs working tree tab', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);
    await _pumpRefsMenuWithCompare(
      tester,
      workbench: workbench,
      floating: floating,
    );

    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working Tree (main)'));
    await tester.pumpAndSettle();

    final spec = _openedCompareSpec(workbench);
    expect(spec?.repoRoot, '/repo');
    expect(spec?.left, const GitCompareRef('feature'));
    expect(spec?.right, const GitCompareWorkingTree());
  });

  testWidgets('compare submenu opens branch vs remote branch tab', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);
    await _pumpRefsMenuWithCompare(
      tester,
      workbench: workbench,
      floating: floating,
    );

    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('origin/main'));
    await tester.pumpAndSettle();

    final spec = _openedCompareSpec(workbench);
    expect(spec?.left, const GitCompareRef('feature'));
    expect(spec?.right, const GitCompareRef('origin/main'));
  });

  testWidgets('tag compare target menu grays out source tag', (tester) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);
    await _pumpRefsMenuWithCompare(
      tester,
      workbench: workbench,
      floating: floating,
    );

    await tester.tap(find.text('v1.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    final item = tester.widget<TpActionMenuItem>(
      find.widgetWithText(TpActionMenuItem, 'v1.0'),
    );
    expect(item.enabled, isFalse);

    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    final spec = _openedCompareSpec(workbench);
    expect(spec?.left, const GitCompareRef('v1.0'));
    expect(spec?.right, const GitCompareRef('main'));
  });
}
