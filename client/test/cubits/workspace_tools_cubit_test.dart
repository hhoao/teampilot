import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/models/right_tool_open_set.dart';

void main() {
  group('WorkspaceToolsCubit', () {
    test('defaults to an empty open set for every scope', () {
      final cubit = WorkspaceToolsCubit();
      expect(cubit.openIdsFor('p1'), isEmpty);
      expect(cubit.selectedIdFor('p1'), isNull);
      expect(cubit.openIdsFor('p2'), isEmpty);
      addTearDown(cubit.close);
    });

    test('open and select are global across scopes', () {
      final cubit = WorkspaceToolsCubit();
      cubit.ensureOpenAndSelect('p1', 'fileTree');
      cubit.ensureOpenAndSelect('p2', 'git');
      expect(cubit.openIdsFor('p1'), ['fileTree', 'git']);
      expect(cubit.openIdsFor('other'), ['fileTree', 'git']);
      expect(cubit.selectedIdFor('p1'), 'git');
      addTearDown(cubit.close);
    });

    test('closeTool records dismissed and persists', () {
      final persisted = <RightToolOpenSet>[];
      final cubit = WorkspaceToolsCubit(persist: persisted.add)
        ..ensureOpenAndSelect('p1', 'members')
        ..ensureOpenAndSelect('p1', 'mailbox');
      cubit.closeTool('p1', 'mailbox', catalog: const ['members', 'mailbox']);
      expect(cubit.openIdsFor('p1'), ['members']);
      expect(cubit.state.openSet.dismissedIds, ['mailbox']);
      expect(persisted.last.dismissedIds, ['mailbox']);
      addTearDown(cubit.close);
    });

    test('pruneToAvailable does not drop ids missing from this catalog', () {
      final cubit = WorkspaceToolsCubit()
        ..ensureOpenAndSelect('p1', 'members')
        ..ensureOpenAndSelect('p1', 'fileTree');
      cubit.pruneToAvailable('p1', const ['fileTree', 'git']);
      expect(cubit.openIdsFor('p1'), ['members', 'fileTree']);
      expect(cubit.selectedIdFor('p1'), 'fileTree');
      addTearDown(cubit.close);
    });

    test('seedTeamDefaults appends even when file tree is already open', () {
      final cubit = WorkspaceToolsCubit()
        ..ensureOpenAndSelect('p1', 'fileTree');
      cubit.seedTeamDefaults('p1', const ['fileTree', 'members', 'mailbox']);
      expect(cubit.openIdsFor('p1'), ['fileTree', 'members', 'mailbox']);
      expect(cubit.selectedIdFor('p1'), 'fileTree');
      addTearDown(cubit.close);
    });

    test('hydrate replaces state without persisting', () {
      final persisted = <RightToolOpenSet>[];
      final cubit = WorkspaceToolsCubit(persist: persisted.add);
      cubit.hydrate(
        const RightToolOpenSet(openIds: ['mailbox'], selectedId: 'mailbox'),
      );
      expect(cubit.openIdsFor('p1'), ['mailbox']);
      expect(persisted, isEmpty);
      addTearDown(cubit.close);
    });

    test('removeWorkspace does not clear the open set', () {
      final cubit = WorkspaceToolsCubit()..ensureOpenAndSelect('p1', 'git');
      cubit.removeWorkspace('p1');
      expect(cubit.openIdsFor('p1'), ['git']);
      addTearDown(cubit.close);
    });
  });
}
