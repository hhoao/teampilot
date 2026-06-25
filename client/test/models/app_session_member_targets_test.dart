import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('memberTargets round-trips and defaults empty', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      memberTargets: const {
        'm1': 'local',
        'm2': 'ssh:p1',
      },
      createdAt: 1,
    );
    expect(s.memberTargets['m1'], 'local');
    expect(s.memberTargets['m2'], 'ssh:p1');

    final r = AppSession.fromJson(s.toJson());
    expect(r.memberTargets['m1'], 'local');
    expect(r.memberTargets['m2'], 'ssh:p1');
  });

  test('workDirsForMember derives paths from target', () {
    const folders = [
      WorkspaceFolder(path: '/repo'),
      WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ];
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: folders,
      memberTargets: const {'m1': 'ssh:p1'},
      createdAt: 1,
    );
    final work = s.workDirsForMember('m1', folders: folders);
    expect(work.workingDirectory, '/remote');
    expect(work.addDirs, isEmpty);
  });

  test('toJson omits memberTargets when empty', () {
    final s = AppSession(sessionId: 's', workspaceId: 'w', createdAt: 1);
    expect(s.toJson().containsKey('memberTargets'), isFalse);
  });

  test('copyWith updates memberTargets', () {
    final s = AppSession(sessionId: 's', workspaceId: 'w', createdAt: 1);
    final next = s.copyWith(memberTargets: const {'m1': 'ssh:p1'});
    expect(next.memberTargets['m1'], 'ssh:p1');
    expect(s.memberTargets, isEmpty);
  });
}
