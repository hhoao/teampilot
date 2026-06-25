import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

void main() {
  test('member assigned to an ssh folder resolves an ssh work target', () async {
    final resolved = <String>[];
    final home = testRuntimeContext('/home-root');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return target.kind == RuntimeKind.ssh
            ? RuntimeContext(
                target: target,
                filesystem: InMemoryFilesystem(),
                home: '/remote',
                cwd: '/remote',
                appDataRoot: '/remote/app',
                paths: home.paths,
              )
            : home;
      },
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team',
      cliTeamName: 'team-1',
      folders: const [
        WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
        WorkspaceFolder(path: '/local', targetId: 'local'),
      ],
      folderAssignments: const {
        'm1': ['/repo'], // ssh folder
        'm2': ['/local'], // local folder
      },
      createdAt: 1,
    );

    final ctxM1 = await lifecycle.debugResolveWorkContext(session, memberId: 'm1');
    expect(resolved.last, 'ssh:p1');
    expect(ctxM1.appDataRoot, '/remote/app');

    resolved.clear();
    final ctxM2 = await lifecycle.debugResolveWorkContext(session, memberId: 'm2');
    expect(resolved.last, 'local');
    expect(identical(ctxM2, home), isTrue);
  });

  test('unassigned member falls back to the session first folder target',
      () async {
    final resolved = <String>[];
    final home = testRuntimeContext('/home-root');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return home;
      },
    );
    final session = AppSession(
      sessionId: 's2',
      workspaceId: 'w2',
      folders: const [WorkspaceFolder(path: '/repo', targetId: 'ssh:p9')],
      createdAt: 1,
    );
    await lifecycle.debugResolveWorkContext(session, memberId: 'unknown');
    expect(resolved.last, 'ssh:p9'); // fell back to session first folder
  });

  // #4 CLI-state regression: when a member is assigned a remote (ssh) folder,
  // hasCliState must probe on that member's ssh forTarget — not home. And
  // destroyCliState cleans the runtime tree on the session workspace's machine
  // (folders.first target), also ssh here — not home.
  SessionLifecycleService _capturingLifecycle(List<String> resolved) {
    final home = testRuntimeContext('/home-root');
    return SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return target.kind == RuntimeKind.ssh
            ? RuntimeContext(
                target: target,
                filesystem: InMemoryFilesystem(),
                home: '/remote',
                cwd: '/remote',
                appDataRoot: '/remote/app',
                paths: home.paths,
              )
            : home;
      },
    );
  }

  AppSession _sshSession() => AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        cliTeamName: 'team-1',
        folders: const [
          WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
          WorkspaceFolder(path: '/local', targetId: 'local'),
        ],
        folderAssignments: const {
          'm1': ['/repo'],
        },
        createdAt: 1,
      );

  test('hasCliState for a member assigned an ssh folder probes ssh forTarget',
      () async {
    final resolved = <String>[];
    final lifecycle = _capturingLifecycle(resolved);
    await lifecycle.hasCliState(
      _sshSession(),
      teamId: 'team',
      memberBinding:
          const SessionMemberBinding(rosterMemberId: 'm1', taskId: 't1'),
    );
    expect(resolved, isNotEmpty);
    expect(resolved.last, 'ssh:p1'); // not home/local
  });

  test('destroyCliState cleans on the session workspace machine (ssh, not home)',
      () async {
    final resolved = <String>[];
    final lifecycle = _capturingLifecycle(resolved);
    await lifecycle.destroyCliState(
      workspaceId: 'w1',
      teamId: 'team',
      sessionId: 's1',
      session: _sshSession(),
    );
    expect(resolved, isNotEmpty);
    expect(resolved.last, 'ssh:p1');
  });

  test('memberWorkContext resolves the member ssh work plane', () async {
    final resolved = <String>[];
    final home = testRuntimeContext('/home-root');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return target.kind == RuntimeKind.ssh
            ? RuntimeContext(
                target: target,
                filesystem: InMemoryFilesystem(),
                home: '/remote',
                cwd: '/remote',
                appDataRoot: '/remote/app',
                paths: home.paths,
              )
            : home;
      },
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
      ],
      folderAssignments: const {'m1': ['/repo']},
      createdAt: 1,
    );

    final ctx = await lifecycle.memberWorkContext(session, 'm1');
    expect(resolved.last, 'ssh:p1');
    expect(ctx.appDataRoot, '/remote/app');
  });

  test('member assigned to ssh folder resolves ssh even when local is first',
      () async {
    final resolved = <String>[];
    final home = testRuntimeContext('/home-root');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return target.kind == RuntimeKind.ssh
            ? RuntimeContext(
                target: target,
                filesystem: InMemoryFilesystem(),
                home: '/remote',
                cwd: '/remote',
                appDataRoot: '/remote/app',
                paths: home.paths,
              )
            : home;
      },
    );
    final session = AppSession(
      sessionId: 's-mixed-order',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1'),
      ],
      folderAssignments: const {
        'builder': ['/root/hhoa'],
      },
      createdAt: 1,
    );

    expect(lifecycle.memberWorkTarget(session, 'builder').id, 'ssh:p1');
    await lifecycle.debugResolveWorkContext(session, memberId: 'builder');
    expect(resolved.last, 'ssh:p1');
  });

  test('member assigned subpath under ssh folder resolves ssh target', () {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-sub',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1'),
      ],
      folderAssignments: const {
        'builder': ['/root/hhoa/project'],
      },
      createdAt: 1,
    );
    expect(lifecycle.memberWorkTarget(session, 'builder').id, 'ssh:p1');
  });

  test('invalid assignment fails folder resolution check', () {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-invalid',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1'),
      ],
      folderAssignments: const {
        'builder': ['/other/machine/path'],
      },
      createdAt: 1,
    );
    expect(lifecycle.memberFolderAssignmentIsValid(session, 'builder'), isFalse);
    expect(lifecycle.memberWorkTarget(session, 'builder').id, RuntimeTarget.localId);
  });

  test('prepareShellLaunch rejects unresolved member folder assignment', () async {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-invalid',
      workspaceId: 'w1',
      sessionTeam: 'team',
      cliTeamName: 'team-1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
      ],
      folderAssignments: const {
        'm1': ['/other/machine/path'],
      },
      members: const [],
      createdAt: 1,
    );
    const team = TeamProfile(
      id: 'team',
      name: 'Team',
      members: [
        TeamMemberConfig(id: 'm1', name: 'Builder', agent: 'builder'),
      ],
    );
    await expectLater(
      lifecycle.prepareShellLaunch(
        session: session,
        team: team,
        member: team.members.first,
        memberBinding: const SessionMemberBinding(
          rosterMemberId: 'm1',
          taskId: 't1',
        ),
      ),
      throwsStateError,
    );
  });

  test('memberWorkDirs: assigned first is workdir, rest are add-dirs', () {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's',
      workspaceId: 'w',
      folders: const [
        WorkspaceFolder(path: '/main'),
        WorkspaceFolder(path: '/x'),
      ],
      folderAssignments: const {
        'm1': ['/main/sub', '/extra'],
      },
      createdAt: 1,
    );
    final m1 = lifecycle.memberWorkDirs(session, 'm1');
    expect(m1.workingDirectory, '/main/sub');
    expect(m1.addDirs, ['/extra']);

    final unassigned = lifecycle.memberWorkDirs(session, 'm2');
    expect(unassigned.workingDirectory, '/main');
    expect(unassigned.addDirs, ['/x']);
  });
}
