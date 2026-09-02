import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';

void main() {
  group('WorkspaceToolsCubit', () {
    test('defaults to an empty open set', () {
      final cubit = WorkspaceToolsCubit();
      expect(cubit.openIdsFor('p1'), isEmpty);
      expect(cubit.selectedIdFor('p1'), isNull);
      addTearDown(cubit.close);
    });

    test('ensureOpenAndSelect opens and selects a tool', () {
      final cubit = WorkspaceToolsCubit();
      cubit.ensureOpenAndSelect('p1', 'fileTree');
      cubit.ensureOpenAndSelect('p1', 'git');
      expect(cubit.openIdsFor('p1'), ['fileTree', 'git']);
      expect(cubit.selectedIdFor('p1'), 'git');
      cubit.ensureOpenAndSelect('p1', 'fileTree');
      expect(cubit.openIdsFor('p1'), ['fileTree', 'git']);
      expect(cubit.selectedIdFor('p1'), 'fileTree');
      addTearDown(cubit.close);
    });

    test('closeTool selects a neighbor and clears when empty', () {
      final cubit = WorkspaceToolsCubit();
      cubit.ensureOpenAndSelect('p1', 'a');
      cubit.ensureOpenAndSelect('p1', 'b');
      cubit.ensureOpenAndSelect('p1', 'c');
      cubit.selectTool('p1', 'b');
      cubit.closeTool('p1', 'b');
      expect(cubit.openIdsFor('p1'), ['a', 'c']);
      expect(cubit.selectedIdFor('p1'), 'a');
      cubit.closeTool('p1', 'a');
      cubit.closeTool('p1', 'c');
      expect(cubit.openIdsFor('p1'), isEmpty);
      expect(cubit.selectedIdFor('p1'), isNull);
      addTearDown(cubit.close);
    });

    test('pruneToAvailable drops missing ids', () {
      final cubit = WorkspaceToolsCubit();
      cubit.ensureOpenAndSelect('p1', 'members');
      cubit.ensureOpenAndSelect('p1', 'fileTree');
      cubit.pruneToAvailable('p1', const ['fileTree', 'git']);
      expect(cubit.openIdsFor('p1'), ['fileTree']);
      expect(cubit.selectedIdFor('p1'), 'fileTree');
      addTearDown(cubit.close);
    });

    test('removeWorkspace drops the stored selection', () {
      final cubit = WorkspaceToolsCubit();
      cubit.ensureOpenAndSelect('p1', 'git');
      cubit.removeWorkspace('p1');
      expect(cubit.openIdsFor('p1'), isEmpty);
      expect(cubit.selectedIdFor('p1'), isNull);
      addTearDown(cubit.close);
    });
  });
}
