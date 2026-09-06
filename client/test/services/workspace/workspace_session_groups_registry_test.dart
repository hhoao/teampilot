import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/services/workspace/workspace_session_groups_registry.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('cubitFor returns the same instance and loads the workspace', () async {
    final registry = WorkspaceSessionGroupsRegistry();
    addTearDown(registry.dispose);

    final cubit = registry.cubitFor('ws-1');
    expect(identical(registry.cubitFor(' ws-1 '), cubit), isTrue);
    expect(cubit.state.workspaceId, 'ws-1');
    // The load is real file IO on a temp dir; pumpEventQueue's fixed 20
    // event-loop turns can miss the IO completion on a loaded CI host
    // (observed on the Windows runner), so poll with a deadline instead.
    await waitUntil(() => cubit.state.ready, timeout: const Duration(seconds: 5));
    expect(cubit.state.ready, isTrue);
  });

  test('cubitFactory override is honored once per workspace', () async {
    final created = <SessionGroupsCubit>[];
    final registry = WorkspaceSessionGroupsRegistry(
      cubitFactory: () {
        final cubit = SessionGroupsCubit();
        created.add(cubit);
        return cubit;
      },
    );
    addTearDown(registry.dispose);

    final first = registry.cubitFor('ws-1');
    expect(identical(registry.cubitFor('ws-1'), first), isTrue);
    expect(created, hasLength(1));
  });

  test('removeWorkspace closes the cubit; empty id throws', () {
    final registry = WorkspaceSessionGroupsRegistry();
    addTearDown(registry.dispose);

    final cubit = registry.cubitFor('ws-1');
    registry.removeWorkspace('ws-1');
    expect(cubit.isClosed, isTrue);
    expect(() => registry.cubitFor(''), throwsArgumentError);
  });
}
