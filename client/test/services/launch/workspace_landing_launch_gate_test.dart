import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/workspace_landing_launch_gate.dart';
import 'package:teampilot/services/team/team_config_launch_validator.dart';
import 'package:teampilot/utils/team_member_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gate = WorkspaceLandingLaunchGate(
    teamConfigValidator: _AlwaysValidTeamConfigValidator(),
  );

  group('WorkspaceLandingLaunchGate.syncBlock', () {
    test('allows personal draft', () {
      final block = gate.syncBlock(
        workspace: _mixedWorkspace(),
        draft: const LandingLaunchContext(isPersonal: true),
        team: null,
      );
      expect(block, isNull);
    });

    test('blocks mixed workspace when placement not initialized', () {
      final team = _team();
      final block = gate.syncBlock(
        workspace: _mixedWorkspace(),
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );
      expect(block, isA<MixedMemberPlacementUninitializedLaunchBlock>());
    });

    test('allows mixed when initialized even if non-lead has zero replicas', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 0),
        ],
        createdAt: 1,
      );
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/a', targetId: 'local'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'team-lead': 'local'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );
      expect(
        gate.syncBlock(
          workspace: workspace,
          draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
          team: team,
        ),
        isNull,
      );
    });

    test('blocks when lead placement is invalid', () {
      final team = _singleMemberTeam();
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/a', targetId: 'local'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'team-lead': 'ssh:host-a'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );
      final block = gate.syncBlock(
        workspace: workspace,
        draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
        team: team,
      );
      expect(block, isA<LeadPlacementInvalidLaunchBlock>());
    });
  });
}

Workspace _mixedWorkspace() {
  return Workspace(
    workspaceId: 'ws-1',
    folders: [
      const WorkspaceFolder(path: '/a', targetId: 'local'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
    ],
    createdAt: 1,
  );
}

TeamProfile _team() {
  return TeamProfile(
    id: 'team-1',
    name: 'Team',
    roster: TeamMemberNaming.defaultRoster(),
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Team Lead'),
      TeamMemberConfig(id: 'developer', name: 'Developer'),
      TeamMemberConfig(id: 'reviewer', name: 'Reviewer'),
    ],
    createdAt: 1,
  );
}

TeamProfile _singleMemberTeam() {
  return TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    ],
    createdAt: 1,
  );
}

class _AlwaysValidTeamConfigValidator extends TeamConfigLaunchValidator {
  @override
  Future<TeamConfigValidation> validate(
    TeamProfile team, {
    List<CliPreset> globalPresets = const [],
  }) async {
    return TeamConfigValidation(
      teamId: team.id,
      teamName: team.name,
      mode: team.teamMode,
      issues: const [],
    );
  }
}
