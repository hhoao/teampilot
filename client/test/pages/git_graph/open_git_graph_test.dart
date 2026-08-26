import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/pages/git_graph/open_git_graph.dart';

void main() {
  testWidgets('openGitGraphTab opens floating gitGraph tab for repo',
      (tester) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    floating.ensureOpen();
    floating.setActiveWorkspace('ws');
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: workbench),
        RepositoryProvider.value(value: floating),
      ],
      child: MaterialApp(home: Builder(builder: (context) {
        return Center(
          child: TextButton(
            onPressed: () => openGitGraphTab(context,
                workspaceId: 'ws', repoRoot: '/repo'),
            child: const Text('open'),
          ),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(
      workbench.state.bar('ws').floating.order.map((t) => t.kind),
      contains(WorkbenchTabKind.gitGraph),
    );
  });
}
