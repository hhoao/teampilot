import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_actions_controller.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
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
      tester.widget<ElevatedButton>(find.byType(ElevatedButton).last).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton).last).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'main');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton).last);
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
    await tester.tap(find.byType(ElevatedButton).last);
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
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(actions.calls.single, ['checkout-commit', 'deadbeef']);
  });
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
