import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/session_reorder_merge.dart';

void main() {
  group('mergeGroupSessionReorder', () {
    test('replaces group members in place with the new group order', () {
      final merged = mergeGroupSessionReorder(
        workspaceOrderedIds: ['a', 'g1', 'b', 'g2', 'c', 'g3'],
        groupOrderedIds: ['g3', 'g1', 'g2'],
      );
      expect(merged, ['a', 'g3', 'b', 'g1', 'c', 'g2']);
    });

    test('no-ops when group is empty', () {
      expect(
        mergeGroupSessionReorder(
          workspaceOrderedIds: ['a', 'b'],
          groupOrderedIds: const [],
        ),
        ['a', 'b'],
      );
    });
  });

  group('reorderVisibleSessionIds', () {
    test('reorders within a capped window and keeps the tail', () {
      // onReorderItem semantics: newIndex is already post-removal.
      final next = reorderVisibleSessionIds(
        allIds: ['a', 'b', 'c', 'd', 'e'],
        visibleIds: ['a', 'b', 'c'],
        oldIndex: 0,
        newIndex: 1,
      );
      expect(next, ['b', 'a', 'c', 'd', 'e']);
    });

    test('full-window reorder matches a plain list move', () {
      final next = reorderVisibleSessionIds(
        allIds: ['a', 'b', 'c'],
        visibleIds: ['a', 'b', 'c'],
        oldIndex: 2,
        newIndex: 0,
      );
      expect(next, ['c', 'a', 'b']);
    });
  });
}
