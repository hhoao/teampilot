import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/git_graph_actions_controller.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_menus.dart';

import '../../support/git_graph_test_fakes.dart';

Widget _host(WidgetBuilder builder) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Builder(builder: builder),
);

void main() {
  testWidgets('confirmDangerAction blocks until typed branch matches', (
    tester,
  ) async {
    late bool result;
    await tester.pumpWidget(
      _host(
        (context) => Center(
          child: TextButton(
            onPressed: () async {
              result = await confirmDangerAction(
                context,
                title: 'Reset',
                body: 'hard reset main',
                typeToConfirm: 'main',
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 未输入时禁用
    expect(
      tester.widget<TpButton>(find.byType(TpButton).last).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.pump();
    expect(
      tester.widget<TpButton>(find.byType(TpButton).last).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'main');
    await tester.pump();
    await tester.tap(find.byType(TpButton).last);
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('commit menu triggers cherryPick through controller', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    final cubit = GitGraphCubit(
      history: FakeHistoryForGraph(rows: [graphCommitRow('c1')]),
      git: FakeGitForGraph(repoStatus()),
      actions: actions,
    );
    await cubit.setRepoRoot('/repo');
    final controller = GitGraphActionsController(cubit: cubit);

    await tester.pumpWidget(
      _host(
        (context) => BlocProvider.value(
          value: cubit,
          child: Center(
            child: TextButton(
              onPressed: () => showCommitContextMenu(
                context,
                const Offset(200, 200),
                graphCommitRow('c1'),
                controller,
                cubit.state,
                workspaceId: 'ws',
                repoRoot: '/repo',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cherry-pick'));
    await tester.pumpAndSettle();
    expect(actions.calls.single, ['cherry-pick', 'c1']);
    await cubit.close();
  });

  testWidgets('delete-branch menu action runs after confirm accept', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    final row = graphCommitRow('c1', refs: const [
      GitRefDecoration(GitRefDecorationKind.localBranch, 'feature'),
    ]);
    await _pumpMenuHost(tester, actions, row);
    await tester.tap(find.text('Delete branch feature'));
    await tester.pumpAndSettle();
    expect(find.text('Delete branch'), findsOneWidget); // 确认对话框
    await tester.tap(find.byType(TpButton).last);
    await tester.pumpAndSettle();
    expect(actions.calls.single, ['branch', '-d', 'feature']);
  });

  testWidgets('rename-branch menu action prefills old name and renames', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    final row = graphCommitRow('c1', refs: const [
      GitRefDecoration(GitRefDecorationKind.localBranch, 'feature'),
    ]);
    await _pumpMenuHost(tester, actions, row);
    await tester.tap(find.text('Rename branch…'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'feature',
    );
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.calls.single, ['rename-branch', 'feature', 'renamed']);
  });

  testWidgets('tag menu actions delete (with confirm) and push', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    final row = graphCommitRow('c1', refs: const [
      GitRefDecoration(GitRefDecorationKind.tag, 'v1.0'),
    ]);
    await _pumpMenuHost(tester, actions, row);
    await tester.tap(find.text('Push tag v1.0'));
    await tester.pumpAndSettle();
    // 菜单随动作关闭，重新打开执行删除。
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete tag v1.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm')); // 删除标签确认
    await tester.pumpAndSettle();
    expect(
      actions.calls.map((c) => c.first),
      containsAll(['push-tag', 'delete-tag']),
    );
  });

  testWidgets('checkout-commit menu action requires confirmation', (
    tester,
  ) async {
    final actions = RecordingGraphActions();
    await _pumpMenuHost(tester, actions, graphCommitRow('deadbeef'));
    await tester.tap(find.textContaining('detached HEAD'));
    await tester.pumpAndSettle();
    // 未确认前不得执行。
    expect(actions.calls, isEmpty);
    await tester.tap(find.byType(TpButton).last);
    await tester.pumpAndSettle();
    expect(actions.calls.single, ['checkout-commit', 'deadbeef']);
  });

  testWidgets('menu shows Show Diff with Working Tree item', (tester) async {
    final actions = RecordingGraphActions();
    await _pumpMenuHost(tester, actions, graphCommitRow('c1'));
    expect(find.text('Show Diff with Working Tree'), findsOneWidget);
  });

  testWidgets('diff-working-tree menu opens git compare tab for branch', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final actions = RecordingGraphActions();
    final row = graphCommitRow(
      'abcdef1234567890',
      refs: const [
        GitRefDecoration(GitRefDecorationKind.localBranch, 'main'),
      ],
    );
    await _pumpCompareMenuHost(tester, actions, row, workbench, floating);
    await tester.tap(find.text('Show Diff with Working Tree'));
    await tester.pumpAndSettle();

    expect(
      workbench.state.bar('ws').floating.order.map((t) => t.kind),
      contains(WorkbenchTabKind.gitCompare),
    );
    final tabId = workbench.state.bar('ws').floating.order
        .firstWhere((t) => t.kind == WorkbenchTabKind.gitCompare)
        .id;
    final spec = GitCompareSpec.tryParseTabId(tabId);
    expect(spec?.repoRoot, '/repo');
    expect(spec?.left, const GitCompareRef('main'));
    expect(spec?.right, const GitCompareWorkingTree());
  });

  testWidgets('diff-working-tree menu uses commit hash when no branch', (
    tester,
  ) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final actions = RecordingGraphActions();
    await _pumpCompareMenuHost(
      tester,
      actions,
      graphCommitRow('abcdef1234567890'),
      workbench,
      floating,
    );
    await tester.tap(find.text('Show Diff with Working Tree'));
    await tester.pumpAndSettle();

    final tabId = workbench.state.bar('ws').floating.order
        .firstWhere((t) => t.kind == WorkbenchTabKind.gitCompare)
        .id;
    final spec = GitCompareSpec.tryParseTabId(tabId);
    expect(spec?.left, const GitCompareRef('abcdef1234567890'));
    expect(spec?.right, const GitCompareWorkingTree());
  });
}

Future<void> _pumpCompareMenuHost(
  WidgetTester tester,
  RecordingGraphActions actions,
  GitCommitRow row,
  WorkbenchCubit workbench,
  FloatingWorkspaceCubit floating,
) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final cubit = GitGraphCubit(
    history: FakeHistoryForGraph(rows: [graphCommitRow('c0')]),
    git: FakeGitForGraph(repoStatus()),
    actions: actions,
  );
  addTearDown(cubit.close);
  await cubit.setRepoRoot('/repo');
  final controller = GitGraphActionsController(cubit: cubit);
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
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showCommitContextMenu(
                context,
                const Offset(200, 200),
                row,
                controller,
                cubit.state,
                workspaceId: 'ws',
                repoRoot: '/repo',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _pumpMenuHost(
  WidgetTester tester,
  RecordingGraphActions actions,
  GitCommitRow row,
) async {
  // 全量提交菜单（分支 + 标签 + reset 组）高约 600px，默认测试表面放不下。
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final cubit = GitGraphCubit(
    history: FakeHistoryForGraph(rows: [graphCommitRow('c0')]),
    git: FakeGitForGraph(repoStatus()),
    actions: actions,
  );
  addTearDown(cubit.close);
  await cubit.setRepoRoot('/repo');
  final controller = GitGraphActionsController(cubit: cubit);
  await tester.pumpWidget(
    _host(
      (context) => BlocProvider.value(
        value: cubit,
        child: Center(
          child: TextButton(
            onPressed: () => showCommitContextMenu(
              context,
              const Offset(200, 200),
              row,
              controller,
              cubit.state,
              workspaceId: 'ws',
              repoRoot: '/repo',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
