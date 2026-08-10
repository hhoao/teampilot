// test/cubits/workbench/close_no_resurrect_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

/// Regression: closing a session tab must never make it reappear at the end
/// of the strip. (Root cause of the historical dual-ownership bug.)
void main() {
  test('closing a session tab removes it and no reconcile re-adds it', () {
    final cubit = WorkbenchCubit();
    cubit.openSession('ws', 's1');
    cubit.openSession('ws', 's2');
    cubit.openSession('ws', 's3');

    cubit.close('ws', WorkbenchTabId.session('s2'));

    final order = cubit.state.bar('ws').center.order;
    expect(order.map((t) => t.id), ['s1', 's3']);

    // Any number of bar mutations must not resurrect the closed id.
    cubit.activate('ws', WorkbenchTabId.session('s1'));
    cubit.reorder('ws', 0, 1);
    cubit.openSession('ws', 's4');
    expect(cubit.state.bar('ws').center.order.map((t) => t.id),
        ['s3', 's1', 's4']);
    expect(cubit.state.bar('ws').center.order.contains(WorkbenchTabId.session('s2')),
        isFalse);
  });
}
