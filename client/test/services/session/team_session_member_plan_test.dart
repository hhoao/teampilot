import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/team_session_member_plan.dart';

void main() {
  var seq = 0;

  setUp(() => seq = 0);

  test('allocates unique taskIds not equal to sessionId; includes lead', () {
    final workspace = Workspace(
      workspaceId: 'ws',
      folders: [const WorkspaceFolder(path: '/proj')],
      createdAt: 1,
      updatedAt: 1,
    );
    const sessionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final plan = buildTeamSessionMemberPlan(
      workspace: workspace,
      teamId: 'team-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder'),
      ],
      memberClis: const {
        'team-lead': CliTool.claude,
        'builder': CliTool.claude,
      },
      allocateTaskId: () => 'task-${seq++}',
    );
    expect(plan.members, isNotEmpty);
    final ids = plan.members.map((m) => m.taskId).toSet();
    expect(ids.length, plan.members.length);
    expect(ids.contains(sessionId), isFalse);
    expect(
      plan.members.any((m) => m.rosterMemberId == 'team-lead'),
      isTrue,
    );
  });

  test('mixed workspace omits unpinned instances from members', () {
    final workspace = Workspace(
      workspaceId: 'ws-mixed',
      folders: const [
        WorkspaceFolder(path: '/local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
      memberTargetsByTeam: const {
        'team-1': {'team-lead': 'local'},
      },
      memberPlacementInitializedByTeam: const {'team-1': true},
      createdAt: 1,
      updatedAt: 1,
    );
    final plan = buildTeamSessionMemberPlan(
      workspace: workspace,
      teamId: 'team-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
      ],
      memberClis: const {
        'team-lead': CliTool.claude,
        'builder': CliTool.claude,
      },
      allocateTaskId: () => 'task-${seq++}',
    );
    expect(plan.members.map((m) => m.rosterMemberId), ['team-lead']);
    expect(
      plan.members.any((m) => m.rosterMemberId.startsWith('builder')),
      isFalse,
    );
    expect(plan.memberTargets.keys, {'team-lead'});
  });
}
