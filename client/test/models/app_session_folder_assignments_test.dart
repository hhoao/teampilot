import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('folderAssignments round-trips and defaults empty', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/repo')],
      folderAssignments: const {
        'm1': ['/repo'],
        'm2': ['/repo/sub', '/extra'],
      },
      createdAt: 1,
    );
    expect(s.folderAssignments['m1'], ['/repo']);
    expect(s.folderAssignments['m2'], ['/repo/sub', '/extra']);

    final r = AppSession.fromJson(s.toJson());
    expect(r.folderAssignments['m1'], ['/repo']);
    expect(r.folderAssignments['m2'], ['/repo/sub', '/extra']);
    expect(r, s);

    final empty = AppSession.fromJson({
      'sessionId': 'x',
      'workspaceId': 'w',
      'folders': [
        {'path': '/a', 'targetId': 'local'},
      ],
      'createdAt': 1,
    });
    expect(empty.folderAssignments, isEmpty);
  });

  test('toJson omits folderAssignments when empty', () {
    final s = AppSession(sessionId: 's', workspaceId: 'w', createdAt: 1);
    expect(s.toJson().containsKey('folderAssignments'), isFalse);
  });

  test('copyWith updates folderAssignments', () {
    final s = AppSession(sessionId: 's', workspaceId: 'w', createdAt: 1);
    final next = s.copyWith(folderAssignments: const {
      'm1': ['/x'],
    });
    expect(next.folderAssignments['m1'], ['/x']);
    expect(s.folderAssignments, isEmpty);
    expect(next == s, isFalse);
  });
}
