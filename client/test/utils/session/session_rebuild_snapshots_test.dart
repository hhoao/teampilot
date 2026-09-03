import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/session/app_session_sort.dart';
import 'package:teampilot/utils/session/running_session_ids.dart';
import 'package:teampilot/utils/session/session_list_structure.dart';
import 'package:teampilot/utils/session/session_row_content.dart';

AppSession _s({
  required String id,
  String display = '',
  int createdAt = 1,
  int updatedAt = 0,
  bool pinned = false,
  int sortOrder = 0,
}) => AppSession(
  sessionId: id,
  workspaceId: 'ws',
  folders: const [WorkspaceFolder(path: '/a')],
  display: display,
  createdAt: createdAt,
  updatedAt: updatedAt,
  pinned: pinned,
  sortOrder: sortOrder,
);

void main() {
  test('SessionListStructure ignores display/updatedAt under createdDesc', () {
    final a = SessionListStructure.fromSessions(
      [_s(id: 'a', display: 'old', updatedAt: 10)],
      sort: AppSessionSort.createdDesc,
    );
    final b = SessionListStructure.fromSessions(
      [_s(id: 'a', display: 'new', updatedAt: 99)],
      sort: AppSessionSort.createdDesc,
    );
    expect(a, b);
  });

  test('SessionListStructure changes when recentlyUpdated reorder changes', () {
    final a = SessionListStructure.fromSessions(
      [_s(id: 'a', updatedAt: 1), _s(id: 'b', updatedAt: 2)],
      sort: AppSessionSort.recentlyUpdated,
    );
    final b = SessionListStructure.fromSessions(
      [_s(id: 'a', updatedAt: 3), _s(id: 'b', updatedAt: 2)],
      sort: AppSessionSort.recentlyUpdated,
    );
    expect(a, isNot(b));
    expect(b.sessionIds, ['a', 'b']);
  });

  test('SessionRowContent changes on display/updatedAt/createdAt', () {
    final base = SessionRowContent.fromSession(
      _s(id: 'a', display: 't', createdAt: 1),
    );
    expect(
      base,
      isNot(
        SessionRowContent.fromSession(_s(id: 'a', display: 'u', createdAt: 1)),
      ),
    );
    expect(
      base,
      isNot(
        SessionRowContent.fromSession(
          _s(id: 'a', display: 't', createdAt: 1, updatedAt: 5),
        ),
      ),
    );
    expect(
      base,
      isNot(
        SessionRowContent.fromSession(_s(id: 'a', display: 't', createdAt: 2)),
      ),
    );
  });

  test('RunningSessionIds order-sensitive equality', () {
    final a = RunningSessionIds.fromWorkspace(
      sessions: [_s(id: 'a'), _s(id: 'b')],
      busySessionIds: {'b'},
      openTabSessionIds: {'a'},
    );
    final same = RunningSessionIds.fromWorkspace(
      sessions: [_s(id: 'a'), _s(id: 'b')],
      busySessionIds: {'b'},
      openTabSessionIds: {'a'},
    );
    final different = RunningSessionIds.fromWorkspace(
      sessions: [_s(id: 'a'), _s(id: 'b')],
      busySessionIds: {'a'},
      openTabSessionIds: {'b'},
    );
    expect(a, same);
    expect(a.ids, ['b', 'a']);
    expect(a, isNot(different));
  });

  test('RunningSessionIds.fromOpenSessionTabs preserves bar order', () {
    final sessions = [_s(id: 'a'), _s(id: 'b'), _s(id: 'c')];
    final ids = RunningSessionIds.fromOpenSessionTabs(
      sessions: sessions,
      openTabSessionIdsInOrder: ['c', 'a', 'local-x', 'a', 'missing'],
    );
    expect(ids.ids, ['c', 'a']);
  });
}
