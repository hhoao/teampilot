import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/pages/git_compare/open_git_compare.dart';

void main() {
  testWidgets('openGitCompareTab opens floating gitCompare tab for spec',
      (tester) async {
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    final spec = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('main'),
      right: const GitCompareWorkingTree(),
    );
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
            onPressed: () => openGitCompareTab(context,
                workspaceId: 'ws', spec: spec),
            child: const Text('open'),
          ),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(
      workbench.state.bar('ws').floating.order.map((t) => t.kind),
      contains(WorkbenchTabKind.gitCompare),
    );
    expect(
      workbench.state.bar('ws').floating.order.map((t) => t.id),
      contains(spec.tabId),
    );
  });
}
