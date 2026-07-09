import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/workspace_team_member_targets_section.dart';
import 'package:teampilot/services/launch/member_placement_save.dart';

void main() {
  group('workspace member targets save enablement', () {
    test('mixed defaults allow save when leadValid (not full completeness)', () {
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
      expect(
        memberPlacementComplete(
          workspaceFolders: folders,
          members: team.members,
          placement: placement,
        ),
        isFalse,
      );
    });
  });

  group('workspaceMemberTargetsStatus', () {
    test('mixed uninitialized uses needsConfirmation', () {
      expect(
        workspaceMemberTargetsStatus(
          needsMixedInit: true,
          placed: 0,
          total: 2,
        ),
        WorkspaceMemberTargetsStatus.needsConfirmation,
      );
      expect(
        workspaceMemberTargetsStatus(
          needsMixedInit: true,
          placed: 2,
          total: 2,
        ),
        WorkspaceMemberTargetsStatus.needsConfirmation,
      );
    });

    test('after init incomplete pins are soft partial, not hard failure', () {
      expect(
        workspaceMemberTargetsStatus(
          needsMixedInit: false,
          placed: 1,
          total: 3,
        ),
        WorkspaceMemberTargetsStatus.partiallyAssigned,
      );
      expect(
        workspaceMemberTargetsStatus(
          needsMixedInit: false,
          placed: 0,
          total: 2,
        ),
        WorkspaceMemberTargetsStatus.partiallyAssigned,
      );
    });

    test('after init full placement is assigned', () {
      expect(
        workspaceMemberTargetsStatus(
          needsMixedInit: false,
          placed: 2,
          total: 2,
        ),
        WorkspaceMemberTargetsStatus.assigned,
      );
      expect(
        workspaceMemberTargetsStatus(
          needsMixedInit: false,
          placed: 0,
          total: 0,
        ),
        WorkspaceMemberTargetsStatus.assigned,
      );
    });
  });
}
