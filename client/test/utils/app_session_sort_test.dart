import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
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
    folders: const [WorkspaceFolder(path: '/p')],
    createdAt: createdAt,
    updatedAt: updatedAt,
    pinned: pinned,
    sortOrder: sortOrder,
  );
}

List<String> _ids(List<AppSession> sessions) => [
  for (final s in sessions) s.sessionId,
];

void main() {
  test('sidebarDefault is recentlyUpdated', () {
    expect(AppSessionSort.sidebarDefault, AppSessionSort.recentlyUpdated);
  });

  test('menuValues excludes manual', () {
    expect(AppSessionSort.menuValues, [
      AppSessionSort.recentlyUpdated,
      AppSessionSort.createdDesc,
    ]);
    expect(AppSessionSort.menuValues, isNot(contains(AppSessionSort.manual)));
  });

  group('sortAppSessions recentlyUpdated', () {
    test('orders by updatedAt descending', () {
      final sessions = [
        _session('old', updatedAt: 10),
        _session('new', updatedAt: 30),
        _session('mid', updatedAt: 20),
      ];
      final sorted = sortAppSessions(
        sessions,
        sort: AppSessionSort.recentlyUpdated,
      );
      expect(_ids(sorted), ['new', 'mid', 'old']);
    });

    test('falls back to createdAt when updatedAt is 0', () {
      final sessions = [
        _session('byCreated', createdAt: 50, updatedAt: 0),
        _session('byUpdated', createdAt: 1, updatedAt: 40),
      ];
      final sorted = sortAppSessions(
        sessions,
        sort: AppSessionSort.recentlyUpdated,
      );
      expect(_ids(sorted), ['byCreated', 'byUpdated']);
    });

    test('pinned always wins', () {
      final sessions = [
        _session('hot', updatedAt: 99),
        _session('pinned', updatedAt: 1, pinned: true),
      ];
      final sorted = sortAppSessions(
        sessions,
        sort: AppSessionSort.recentlyUpdated,
      );
      expect(_ids(sorted), ['pinned', 'hot']);
    });
  });

  group('sortAppSessions createdDesc', () {
    test('orders by createdAt descending', () {
      final sessions = [
        _session('a', createdAt: 1),
        _session('c', createdAt: 3),
        _session('b', createdAt: 2),
      ];
      final sorted = sortAppSessions(sessions, sort: AppSessionSort.createdDesc);
      expect(_ids(sorted), ['c', 'b', 'a']);
    });
  });

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

    test(
      'never-stamped rows (sortOrder 0) sort first, most recently updated first',
      () {
        final sessions = [
          _session('stamped', sortOrder: 1, createdAt: 100, updatedAt: 100),
          _session('olderActivity', createdAt: 50, updatedAt: 10),
          _session('newerActivity', createdAt: 1, updatedAt: 20),
        ];
        final sorted = sortAppSessions(sessions, sort: AppSessionSort.manual);
        // 0-order rows come before stamped; activity (updatedAt) newest first.
        expect(_ids(sorted), ['newerActivity', 'olderActivity', 'stamped']);
      },
    );

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
