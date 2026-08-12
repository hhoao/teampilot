import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/utils/session/workspace_tab_session_scope.dart';

void main() {
  testWidgets('bar center-active change rebuilds a scoped-active consumer',
      (tester) async {
    final workbench = WorkbenchCubit();
    var rebuilds = 0;

    await tester.pumpWidget(
      BlocProvider<WorkbenchCubit>.value(
        value: workbench,
        child: _ActiveIdProbe(
          tabScopeId: 'ws-1',
          onBuild: () => rebuilds++,
        ),
      ),
    );
    expect(rebuilds, 1);

    workbench.openSession('ws-1', 'sess-a', preview: true);
    // Cubit stream delivery + provider notify each take a frame.
    await tester.pump();
    await tester.pump();
    expect(rebuilds, 2);

    workbench.openSession('ws-1', 'sess-b', preview: true);
    await tester.pump();
    await tester.pump();
    expect(rebuilds, 3);
  });
}

/// Mirrors the `_WorkspaceRightToolsPane` subscription exactly: any bar
/// center-active change must rebuild the consumer.
class _ActiveIdProbe extends StatelessWidget {
  const _ActiveIdProbe({required this.tabScopeId, required this.onBuild});

  final String tabScopeId;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final _ = context.select<WorkbenchCubit, String?>(
      (w) => scopedActiveSessionId(w, tabScopeId),
    );
    onBuild();
    return const SizedBox.shrink();
  }
}
