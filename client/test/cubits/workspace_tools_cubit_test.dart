import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';

void main() {
  group('WorkspaceToolsCubit', () {
    test('defaults a project to selected index 0', () {
      final cubit = WorkspaceToolsCubit();
      expect(cubit.selectedIndexFor('p1'), 0);
      addTearDown(cubit.close);
    });

    test('remembers a per-project selected index', () {
      final cubit = WorkspaceToolsCubit();
      cubit.setSelectedIndex('p1', 2);
      cubit.setSelectedIndex('p2', 1);
      expect(cubit.selectedIndexFor('p1'), 2);
      expect(cubit.selectedIndexFor('p2'), 1);
      expect(cubit.selectedIndexFor('p3'), 0);
      addTearDown(cubit.close);
    });

    test('emits a new state when a selection changes', () {
      final cubit = WorkspaceToolsCubit();
      final seen = <Map<String, int>>[];
      final sub = cubit.stream.listen((s) => seen.add(Map.of(s.selectedByProject)));
      cubit.setSelectedIndex('p1', 3);
      cubit.setSelectedIndex('p1', 3); // no-op, same value
      return Future<void>.delayed(Duration.zero, () {
        expect(seen.length, 1);
        expect(seen.single['p1'], 3);
        sub.cancel();
        cubit.close();
      });
    });

    test('removeProject drops the stored selection', () {
      final cubit = WorkspaceToolsCubit();
      cubit.setSelectedIndex('p1', 2);
      cubit.removeProject('p1');
      expect(cubit.selectedIndexFor('p1'), 0);
      addTearDown(cubit.close);
    });
  });
}
