import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/repositories/session_group_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/post_frame_test_harness.dart';

/// Repository stub whose IO always fails, simulating SSH/WSL filesystem
/// errors during load.
class _ThrowingLoadRepository extends SessionGroupRepository {
  @override
  Future<SessionGroupsFile> load(String workspaceId) async {
    throw StateError('filesystem unavailable');
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late WorkspaceLayout layout;
  late String basePath;

  setUp(() {
    basePath = AppStorage.paths.basePath;
    layout = WorkspaceLayout(teampilotRoot: basePath);
  });

  /// Persists are unawaited whole-file writes whose real IO completions
  /// `pumpEventQueue` alone does not drain; poll until the on-disk document
  /// satisfies [predicate].
  Future<void> waitForPersisted(
    String workspaceId,
    bool Function(List<SessionGroup> groups) predicate,
  ) {
    return waitUntil(
      () {
        final file = File(layout.sessionGroupsFile(workspaceId));
        if (!file.existsSync()) return false;
        try {
          return predicate(
            SessionGroupsFile.fromRawJson(file.readAsStringSync()).groups,
          );
        } on FileSystemException {
          return false;
        }
      },
      pump: () => drainPendingAsyncWork(rounds: 1),
    );
  }

  test('load degrades to an empty ready state when IO fails', () async {
    final cubit = SessionGroupsCubit(repository: _ThrowingLoadRepository());
    addTearDown(cubit.close);

    await cubit.load('ws-1');

    expect(cubit.state.ready, isTrue);
    expect(cubit.state.workspaceId, 'ws-1');
    expect(cubit.state.groups, isEmpty);
  });

  test('deleteGroup before ready is a no-op', () async {
    final cubit = SessionGroupsCubit(repository: _ThrowingLoadRepository());
    addTearDown(cubit.close);

    cubit.deleteGroup('g1');

    expect(cubit.state.status, SessionGroupsStatus.loading);
    expect(cubit.state.groups, isEmpty);
  });

  test('load hydrates persisted groups', () async {
    File(layout.sessionGroupsFile('ws-1')).parent.createSync(recursive: true);
    File(layout.sessionGroupsFile('ws-1')).writeAsStringSync(
      '{"version":1,"groups":[{"id":"g1","name":"待办","sessionIds":["s1"]}]}',
    );

    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');

    expect(cubit.state.ready, isTrue);
    expect(cubit.state.workspaceId, 'ws-1');
    expect(cubit.state.groups, [
      const SessionGroup(id: 'g1', name: '待办', sessionIds: ['s1']),
    ]);
  });

  test('createGroup appends trimmed name and persists', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');

    cubit.createGroup('  待办  ');
    cubit.createGroup('   ');

    expect(cubit.state.groups.map((g) => g.name).toList(), ['待办']);
    await waitForPersisted('ws-1', (groups) => groups.length == 1);
  });

  test('rename / delete mutate only the target group', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('A');
    cubit.createGroup('B');
    final idA = cubit.state.groups[0].id;

    cubit.renameGroup(idA, 'Todo');
    expect(cubit.state.groups[0].name, 'Todo');

    cubit.deleteGroup(cubit.state.groups[1].id);
    expect(cubit.state.groups.map((g) => g.name), ['Todo']);
    await waitForPersisted(
      'ws-1',
      (groups) => groups.length == 1 && groups.single.name == 'Todo',
    );
  });

  test('setMembership adds and removes tags across groups', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;

    cubit.setMembership(groupId, 'sess-1', member: true);
    expect(cubit.state.groupById(groupId)!.containsSession('sess-1'), isTrue);

    cubit.setMembership(groupId, 'sess-1', member: false);
    expect(cubit.state.groupById(groupId)!.containsSession('sess-1'), isFalse);
  });

  test('toggleCollapsed persists collapse flag', () async {
    final cubit = SessionGroupsCubit();
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;

    cubit.toggleCollapsed(groupId);
    expect(cubit.state.groupById(groupId)!.collapsed, isTrue);
    await waitForPersisted('ws-1', (groups) => groups.single.collapsed);

    final reopened = SessionGroupsCubit();
    addTearDown(reopened.close);
    await reopened.load('ws-1');
    expect(reopened.state.groupById(groupId)!.collapsed, isTrue);
  });

  test('knownSessionIds prunes stale member ids on persist', () async {
    var known = {'s-live', 's-stale'};
    final cubit = SessionGroupsCubit(knownSessionIds: () => known);
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;
    cubit.setMembership(groupId, 's-live', member: true);
    cubit.setMembership(groupId, 's-stale', member: true);
    await waitForPersisted(
      'ws-1',
      (groups) =>
          groups.single.sessionIds.contains('s-live') &&
          groups.single.sessionIds.contains('s-stale'),
    );

    // s-stale vanished; next mutation persists the pruned membership.
    known = {'s-live'};
    cubit.toggleCollapsed(groupId);
    await waitForPersisted(
      'ws-1',
      (groups) => groups.single.sessionIds.join(',') == 's-live',
    );
    // Optimistic state still carries the unpruned list; rendering filters.
    expect(cubit.state.groupById(groupId)!.containsSession('s-stale'), isTrue);
  });

  test('throwing knownSessionIds callback cannot poison the persist chain',
      () async {
    var failCallback = false;
    final cubit = SessionGroupsCubit(
      knownSessionIds: () {
        if (failCallback) throw StateError('callback boom');
        return const {'sess-1'};
      },
    );
    addTearDown(cubit.close);
    await cubit.load('ws-1');
    cubit.createGroup('G');
    final groupId = cubit.state.groups.single.id;
    cubit.setMembership(groupId, 'sess-1', member: true);

    // First persist runs with a throwing callback and is swallowed.
    failCallback = true;
    await Future<void>.delayed(Duration.zero);

    failCallback = false;
    cubit.toggleCollapsed(groupId);
    await waitForPersisted(
      'ws-1',
      (groups) => groups.single.name == 'G' && groups.single.collapsed,
    );
  });
}
