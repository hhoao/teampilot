import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/workspace/workspace_target_remap.dart';

void main() {
  test('rewrites folders only', () {
    final result = WorkspaceTargetRemap.apply(
      folders: const [
        WorkspaceFolder(path: '/a', targetId: 'ssh:old'),
        WorkspaceFolder(path: '/b', targetId: 'local'),
      ],
      memberTargetsByTeam: const {},
      sessions: const [],
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
    );
    expect(result.folders.map((f) => f.targetId), ['ssh:new', 'local']);
    expect(result.sessions, isEmpty);
  });

  test('rewrites pins across teams', () {
    final result = WorkspaceTargetRemap.apply(
      folders: const [WorkspaceFolder(path: '/a', targetId: 'local')],
      memberTargetsByTeam: {
        'team-a': {'lead': 'ssh:old', 'dev': 'local'},
        'team-b': {'lead': 'ssh:old'},
      },
      sessions: const [],
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
    );
    expect(result.memberTargetsByTeam['team-a'], {
      'lead': 'ssh:new',
      'dev': 'local',
    });
    expect(result.memberTargetsByTeam['team-b'], {'lead': 'ssh:new'});
  });

  test('rewrites session memberTargets and folders; skips unchanged', () {
    final changed = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/a', targetId: 'ssh:old')],
      memberTargets: const {'lead': 'ssh:old'},
    );
    final untouched = AppSession(
      sessionId: 's2',
      workspaceId: 'w1',
      createdAt: 1,
      folders: const [WorkspaceFolder(path: '/b', targetId: 'local')],
      memberTargets: const {'lead': 'local'},
    );
    final result = WorkspaceTargetRemap.apply(
      folders: const [],
      memberTargetsByTeam: const {},
      sessions: [changed, untouched],
      fromTargetId: 'ssh:old',
      toTargetId: 'ssh:new',
    );
    expect(result.sessions, hasLength(1));
    expect(result.sessions.single.sessionId, 's1');
    expect(result.sessions.single.memberTargets['lead'], 'ssh:new');
    expect(result.sessions.single.folders.single.targetId, 'ssh:new');
  });

  test('from == to is no-op', () {
    final folders = const [
      WorkspaceFolder(path: '/a', targetId: 'ssh:x'),
    ];
    final result = WorkspaceTargetRemap.apply(
      folders: folders,
      memberTargetsByTeam: const {'t': {'m': 'ssh:x'}},
      sessions: const [],
      fromTargetId: 'ssh:x',
      toTargetId: 'ssh:x',
    );
    expect(identical(result.folders, folders) || result.folders == folders, isTrue);
    expect(result.sessions, isEmpty);
  });

  test('usesTarget reports folders ∪ pins ∪ sessions', () {
    expect(
      WorkspaceTargetRemap.usesTarget(
        folders: const [WorkspaceFolder(path: '/a', targetId: 'ssh:old')],
        memberTargetsByTeam: const {},
        sessions: const [],
        targetId: 'ssh:old',
      ),
      isTrue,
    );
    expect(
      WorkspaceTargetRemap.usesTarget(
        folders: const [],
        memberTargetsByTeam: const {'t': {'m': 'ssh:old'}},
        sessions: const [],
        targetId: 'ssh:old',
      ),
      isTrue,
    );
  });
}
