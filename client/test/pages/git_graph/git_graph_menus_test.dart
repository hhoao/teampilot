import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_actions_controller.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
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
}
