import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  test('staged members taskIds are preserved on createSession', () async {
    final tmp = await Directory.systemTemp.createTemp(
      'fs_session_repo_stable_',
    );
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([
      const WorkspaceFolder(path: '/proj'),
    ]);

    const staged = [
      SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: 'fixed-lead-task',
        cli: CliTool.claude,
      ),
      SessionMemberBinding(
        rosterMemberId: 'builder',
        taskId: 'fixed-builder-task',
        cli: CliTool.claude,
      ),
    ];

    final session = await repo.createSession(
      workspace.workspaceId,
      sessionTeam: 'team-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder'),
      ],
      memberClis: const {
        'team-lead': CliTool.claude,
        'builder': CliTool.claude,
      },
      fixedSessionId: 'sess-1',
      members: staged,
      memberTargets: const {
        'team-lead': WorkspaceFolder.localTargetId,
        'builder': WorkspaceFolder.localTargetId,
      },
    );

    expect(session.sessionId, 'sess-1');
    expect(session.bindingFor('team-lead')!.taskId, 'fixed-lead-task');
    expect(session.bindingFor('builder')!.taskId, 'fixed-builder-task');
    expect(session.members.map((m) => m.taskId).toSet(), {
      'fixed-lead-task',
      'fixed-builder-task',
    });
    expect(session.memberTargets, {
      'team-lead': WorkspaceFolder.localTargetId,
      'builder': WorkspaceFolder.localTargetId,
    });
  });

  test('staged members whose ids disagree with placement throw', () async {
    final tmp = await Directory.systemTemp.createTemp(
      'fs_session_repo_stable_disagree_',
    );
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final ws = await repo.createWorkspace([
      const WorkspaceFolder(path: '/local'),
      const WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ]);
    // Placement initialized but only pins the lead — builder pods are excluded.
    await repo.updateWorkspaceMemberPlacement(
      ws.workspaceId,
      'team-a',
      targets: const {'team-lead': WorkspaceFolder.localTargetId},
    );

    const staged = [
      SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: 'fixed-lead-task',
        cli: CliTool.claude,
      ),
      SessionMemberBinding(
        rosterMemberId: 'builder-0',
        typeId: 'builder',
        taskId: 'fixed-builder-task',
        cli: CliTool.claude,
      ),
    ];

    expect(
      () => repo.createSession(
        ws.workspaceId,
        sessionTeam: 'team-a',
        rosterMembers: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
        ],
        memberClis: const {
          'team-lead': CliTool.claude,
          'builder': CliTool.claude,
        },
        members: staged,
        memberTargets: const {
          'team-lead': WorkspaceFolder.localTargetId,
          'builder-0': WorkspaceFolder.localTargetId,
        },
      ),
      throwsA(isA<StateError>()),
    );
  });
}
