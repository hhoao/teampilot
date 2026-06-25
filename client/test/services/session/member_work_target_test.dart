import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

WorkspaceLaunchContext _ctx(
  AppSession session, {
  List<WorkspaceFolder>? workspaceFolders,
}) =>
    WorkspaceLaunchContext(
      session: session,
      workspace: Workspace(
        workspaceId: session.workspaceId,
        folders: workspaceFolders ?? session.folders,
        createdAt: 0,
      ),
    );

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
      memberTargets: const {
        'm1': 'ssh:p1',
        'm2': 'local',
      },
      createdAt: 1,
    );

    final ctxM1 = await lifecycle.debugResolveWorkContext(
      session,
      memberId: 'm1',
      workspace: _ctx(session).workspace,
    );
    expect(resolved.last, 'ssh:p1');
    expect(ctxM1.appDataRoot, '/remote/app');

    resolved.clear();
    await lifecycle.debugResolveWorkContext(
      session,
      memberId: 'm2',
      workspace: _ctx(session).workspace,
    );
    expect(resolved.last, 'local');
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
    await lifecycle.debugResolveWorkContext(
      session,
      memberId: 'unknown',
      workspace: _ctx(session).workspace,
    );
    expect(resolved.last, 'ssh:p9');
  });

  SessionLifecycleService capturingLifecycle(List<String> resolved) {
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

  AppSession sshSession() => AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team',
        cliTeamName: 'team-1',
        folders: const [
          WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
          WorkspaceFolder(path: '/local', targetId: 'local'),
        ],
        memberTargets: const {'m1': 'ssh:p1'},
        createdAt: 1,
      );

  test('hasCliState for a member assigned an ssh folder probes ssh forTarget',
      () async {
    final resolved = <String>[];
    final lifecycle = capturingLifecycle(resolved);
    await lifecycle.hasCliState(
      sshSession(),
      teamId: 'team',
      memberBinding:
          const SessionMemberBinding(rosterMemberId: 'm1', taskId: 't1'),
    );
    expect(resolved, isNotEmpty);
    expect(resolved.last, 'ssh:p1');
  });

  test('destroyCliState cleans on the session workspace machine (ssh, not home)',
      () async {
    final resolved = <String>[];
    final lifecycle = capturingLifecycle(resolved);
    await lifecycle.destroyCliState(
      workspaceId: 'w1',
      teamId: 'team',
      sessionId: 's1',
      session: sshSession(),
    );
    expect(resolved, isNotEmpty);
    expect(resolved.last, 'ssh:p1');
  });

  test('launchWorkContext resolves the member ssh work plane', () async {
    final resolved = <String>[];
    final lifecycle = capturingLifecycle(resolved);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
      ],
      memberTargets: const {'m1': 'ssh:p1'},
      createdAt: 1,
    );

    final ctx = await lifecycle.launchWorkContext(_ctx(session), memberId: 'm1');
    expect(resolved.last, 'ssh:p1');
    expect(ctx.appDataRoot, '/remote/app');
  });

  test('member assigned to ssh target resolves ssh even when local is first',
      () async {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-mixed-order',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1'),
      ],
      memberTargets: const {'builder': 'ssh:p1'},
      createdAt: 1,
    );

    expect(
      lifecycle.launchWorkTarget(_ctx(session), memberId: 'builder').id,
      'ssh:p1',
    );
  });

  test('invalid target falls back to first folder target', () {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-invalid',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1'),
      ],
      memberTargets: const {'builder': 'ssh:missing'},
      createdAt: 1,
    );
    expect(lifecycle.memberTargetIsValid(_ctx(session), 'builder'), isFalse);
    expect(
      lifecycle.launchWorkTarget(_ctx(session), memberId: 'builder').id,
      RuntimeTarget.localId,
    );
  });

  test('prepareShellLaunch rejects invalid member target on mixed workspace',
      () async {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-invalid',
      workspaceId: 'w1',
      sessionTeam: 'team',
      cliTeamName: 'team-1',
      folders: const [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
      memberTargets: const {'m1': 'ssh:missing'},
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
    final workspace = Workspace(
      workspaceId: 'w1',
      folders: [
        WorkspaceFolder(path: '/home/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
      createdAt: 0,
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
        workspace: workspace,
      ),
      throwsStateError,
    );
  });

  test('memberWorkDirs derives cwd from target', () {
    final lifecycle = SessionLifecycleService();
    const folders = [
      WorkspaceFolder(path: '/main'),
      WorkspaceFolder(path: '/x'),
    ];
    final session = AppSession(
      sessionId: 's',
      workspaceId: 'w',
      folders: folders,
      memberTargets: const {'m1': 'local'},
      createdAt: 1,
    );
    final ctx = _ctx(session, workspaceFolders: folders);
    final m1 = lifecycle.memberWorkDirs(ctx, 'm1');
    expect(m1.workingDirectory, '/main');
    expect(m1.addDirs, ['/x']);

    final unassigned = lifecycle.memberWorkDirs(ctx, 'm2');
    expect(unassigned.workingDirectory, '/main');
    expect(unassigned.addDirs, ['/x']);
  });

  test('personal session launchWorkTarget uses workspace session target', () {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-personal',
      workspaceId: 'w1',
      sessionTeam: '',
      folders: const [
        WorkspaceFolder(path: '/root/hhoa', targetId: 'ssh:p1'),
      ],
      createdAt: 1,
    );

    expect(
      lifecycle.launchWorkTarget(_ctx(session)).id,
      'ssh:p1',
    );
  });

  test('prepareShellLaunch rejects personal launch on mixed workspace', () async {
    final lifecycle = SessionLifecycleService();
    final session = AppSession(
      sessionId: 's-personal',
      workspaceId: 'w1',
      sessionTeam: '',
      folders: const [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
      createdAt: 1,
    );
    const personal = PersonalProfile(
      id: LaunchProfileProvisioner.defaultPersonalId,
      display: 'Me',
    );
    final workspace = Workspace(
      workspaceId: 'w1',
      folders: session.folders,
      createdAt: 0,
    );
    await expectLater(
      lifecycle.prepareShellLaunch(
        session: session,
        workspace: workspace,
        personal: personal,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'mixed_workspace_personal_launch_blocked',
        ),
      ),
    );
  });
}
