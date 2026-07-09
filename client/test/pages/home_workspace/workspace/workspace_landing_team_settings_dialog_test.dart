import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart';
import 'package:teampilot/services/launch/member_placement_save.dart';

void main() {
  group('landingTeamSettingsNeedsAttention', () {
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'dev', name: 'Dev'),
      ],
      createdAt: 1,
    );

    test('alerts when mixed placement is uninitialized', () {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [
          WorkspaceFolder(path: '/a'),
          WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ],
        createdAt: 1,
      );
      expect(
        landingTeamSettingsNeedsAttention(workspace: workspace, team: team),
        isTrue,
      );
    });

    test('does not alert for local with empty remembered targets', () {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/a')],
        createdAt: 1,
      );
      expect(
        landingTeamSettingsNeedsAttention(workspace: workspace, team: team),
        isFalse,
      );
    });

    test('alerts when remembered lead pin is invalid', () {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [
          WorkspaceFolder(path: '/a'),
          WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ],
        createdAt: 1,
        memberTargetsByTeam: {
          team.id: {'team-lead': 'ssh:p1'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );
      expect(
        landingTeamSettingsNeedsAttention(workspace: workspace, team: team),
        isTrue,
      );
    });
  });

  group('landing settings save enablement (prepareMemberPlacementSave)', () {
    test('mixed defaults allow save with lead only (non-leads at 0)', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'dev', name: 'Dev'),
        ],
        createdAt: 1,
      );
      const folders = [
        WorkspaceFolder(path: '/a'),
        WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
      ];
      final placement = defaultMemberPlacement(
        folders: folders,
        members: team.members,
      );
      final prepared = prepareMemberPlacementSave(
        team: team,
        folders: folders,
        placement: placement,
      );
      expect(prepared.leadValid, isTrue);
      expect(prepared.members.firstWhere((m) => m.id == 'dev').replicas, 0);
      expect(memberPlacementComplete(
        workspaceFolders: folders,
        members: team.members,
        placement: placement,
      ), isFalse);
    });
  });
}
