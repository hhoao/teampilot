import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_projection.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

/// Mirrors the file tree consumer: the active floating file-preview path of
/// [ws] read from the bar's floating strip.
String? filePreviewPath(WorkbenchCubit workbench, String ws) {
  final activeId = workbench.state.bar(ws).floating.activeId;
  if (activeId == null || activeId.kind != WorkbenchTabKind.file) return null;
  return activeId.id;
}

void main() {
  test('chrome emit triggers recompute and notifies on value change', () async {
    final floating = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(floating.close);
    addTearDown(workbench.close);
    final projection = FloatingWorkspaceProjection<String?>(
      floating,
      workbench,
      (c, w) => c.state.activeWorkspaceId.isEmpty
          ? null
          : c.state.activeWorkspaceId,
      initial: null,
    );
    addTearDown(projection.dispose);

    expect(projection.value, isNull);
    floating.setActiveWorkspace('ws-a');
    // [Cubit.stream] is a broadcast stream — events arrive on a microtask.
    await Future<void>.delayed(Duration.zero);
    expect(projection.value, 'ws-a');
  });

  test('tab mutations recompute; unchanged projection is not notified', () async {
    final floating = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(floating.close);
    addTearDown(workbench.close);
    floating.setActiveWorkspace('ws-a');
    workbench.openFloating('ws-a', WorkbenchTabId.file('/a.txt'));

    var notifications = 0;
    final projection = FloatingWorkspaceProjection<String?>(
      floating,
      workbench,
      (c, w) => filePreviewPath(w, 'ws-a'),
      initial: null,
    );
    addTearDown(projection.dispose);
    projection.addListener(() => notifications++);

    expect(projection.value, '/a.txt', reason: 'initial recompute');

    // Opening an unrelated terminal tab changes the active tab → path clears.
    workbench.openFloating('ws-a', WorkbenchTabId.shell('e1'));
    await Future<void>.delayed(Duration.zero); // broadcast stream microtask
    expect(notifications, 1);
    expect(projection.value, isNull);

    // Back to the file preview → path returns.
    workbench.activate('ws-a', WorkbenchTabId.file('/a.txt'));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 2);
    expect(projection.value, '/a.txt');

    // Re-ensure the SAME tab with the same path → active id + path unchanged →
    // projection unchanged → dedup (no notification).
    workbench.openFloating('ws-a', WorkbenchTabId.file('/a.txt'));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 2, reason: 'same path → dedup');

    // Chrome emit (visibility) with unchanged projection → dedup.
    floating.ensureOpen();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 2, reason: 'chrome emit → dedup');
  });

  test('dispose unsubscribes from both change planes', () {
    final floating = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(floating.close);
    addTearDown(workbench.close);
    floating.setActiveWorkspace('ws-a');

    final projection = FloatingWorkspaceProjection<String?>(
      floating,
      workbench,
      (c, w) => filePreviewPath(w, 'ws-a'),
      initial: null,
    );
    var notifications = 0;
    projection.addListener(() => notifications++);
    expect(projection.value, isNull);

    projection.dispose();
    workbench.openFloating('ws-a', WorkbenchTabId.file('/a.txt'));
    floating.setMaximized(true);
    expect(notifications, 0);
  });
}
