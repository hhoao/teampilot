import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/utils/app_session_sort.dart';

AppSession _session(
  String id, {
  int createdAt = 0,
  int updatedAt = 0,
  bool pinned = false,
  int sortOrder = 0,
}) {
  return AppSession(
    sessionId: id,
    workspaceId: 'p',
    primaryPath: '/p',
    createdAt: createdAt,
    updatedAt: updatedAt,
    pinned: pinned,
    sortOrder: sortOrder,
  );
}

List<String> _ids(List<AppSession> sessions) =>
    [for (final s in sessions) s.sessionId];

void main() {
  group('sortAppSessions manual', () {
    test('orders by ascending sortOrder', () {
      final sessions = [
        _session('a', sortOrder: 3),
        _session('b', sortOrder: 1),
        _session('c', sortOrder: 2),
      ];
      final sorted = sortAppSessions(sessions, sort: AppSessionSort.manual);
      expect(_ids(sorted), ['b', 'c', 'a']);
    });

    test('never-stamped rows (sortOrder 0) sort first, newest created first',
        () {
      final sessions = [
        _session('stamped', sortOrder: 1, createdAt: 100),
        _session('older', createdAt: 10),
        _session('newer', createdAt: 20),
      ];
      final sorted = sortAppSessions(sessions, sort: AppSessionSort.manual);
      // 0-order rows (newer, older) come before the stamped row; newest first.
      expect(_ids(sorted), ['newer', 'older', 'stamped']);
    });

    test('pinned always wins over manual order', () {
      final sessions = [
        _session('a', sortOrder: 1),
        _session('pinned', sortOrder: 9, pinned: true),
        _session('b', sortOrder: 2),
      ];
      final sorted = sortAppSessions(sessions, sort: AppSessionSort.manual);
      expect(sorted.first.sessionId, 'pinned');
    });
  });
}
