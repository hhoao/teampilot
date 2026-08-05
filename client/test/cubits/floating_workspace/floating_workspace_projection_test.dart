import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_projection.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_state.dart';

/// Mirrors the file tree consumer: the active file-preview path of [ws].
String? filePreviewPath(FloatingWorkspaceCubit cubit, String ws) {
  final active = cubit.activeTabFor(ws);
  if (active == null || active.surfaceId != 'filePreview') return null;
  return active.payload is String ? active.payload as String : null;
}

void main() {
  test('chrome emit triggers recompute and notifies on value change', () async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final projection = FloatingWorkspaceProjection<String?>(
      cubit,
      (c) => c.state.activeWorkspaceId.isEmpty
          ? null
          : c.state.activeWorkspaceId,
      initial: null,
    );
    addTearDown(projection.dispose);

    expect(projection.value, isNull);
    cubit.setActiveWorkspace('ws-a');
    // [Cubit.stream] is a broadcast stream — events arrive on a microtask.
    await Future<void>.delayed(Duration.zero);
    expect(projection.value, 'ws-a');
  });

  test('tab mutations recompute; unchanged projection is not notified', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.setActiveWorkspace('ws-a');
    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );

    var notifications = 0;
    final projection = FloatingWorkspaceProjection<String?>(
      cubit,
      (c) => filePreviewPath(c, 'ws-a'),
      initial: null,
    );
    addTearDown(projection.dispose);
    projection.addListener(() => notifications++);

    expect(projection.value, '/a.txt', reason: 'initial recompute');

    // Opening an unrelated terminal tab changes the active tab → path clears.
    cubit.ensureTab(
      FloatingTab(id: 't1', surfaceId: 'terminal', title: 'term', payload: 'e1'),
    );
    expect(notifications, 1);
    expect(projection.value, isNull);

    // Back to the file preview → path returns.
    cubit.selectTab('f1');
    expect(notifications, 2);
    expect(projection.value, '/a.txt');

    // Re-ensure the SAME tab with the same path → active id + payload
    // unchanged → projection unchanged → dedup (no notification).
    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    expect(notifications, 2, reason: 'same path → dedup');

    // Chrome emit (visibility) with unchanged projection → dedup.
    cubit.ensureOpen();
    expect(notifications, 2, reason: 'chrome emit → dedup');
  });

  test('dispose unsubscribes from both change planes', () {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    cubit.setActiveWorkspace('ws-a');

    final projection = FloatingWorkspaceProjection<String?>(
      cubit,
      (c) => filePreviewPath(c, 'ws-a'),
      initial: null,
    );
    var notifications = 0;
    projection.addListener(() => notifications++);
    expect(projection.value, isNull);

    projection.dispose();
    cubit.ensureTab(
      FloatingTab(
        id: 'f1',
        surfaceId: 'filePreview',
        title: 'a.txt',
        payload: '/a.txt',
      ),
    );
    cubit.setMaximized(true);
    expect(notifications, 0);
  });
}
