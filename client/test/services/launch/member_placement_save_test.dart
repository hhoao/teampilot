import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/member_placement_save.dart';

void main() {
  group('prepareMemberPlacementSave', () {
    test('applies replicas, targets, and init flag when lead is valid', () {
      final prepared = prepareMemberPlacementSave(
        team: TeamProfile(
          id: 't1',
          name: 'T',
          members: const [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'dev', name: 'Dev'),
          ],
          createdAt: 1,
        ),
        folders: const [
          WorkspaceFolder(path: '/a'),
          WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ],
        placement: {
          'local': {'team-lead': 1, 'dev': 1},
          'ssh:p1': {'dev': 1},
        },
      );
      expect(prepared.members.firstWhere((m) => m.id == 'dev').replicas, 2);
      expect(prepared.targets['dev-0'], 'local');
      expect(prepared.targets['dev-1'], 'ssh:p1');
      expect(prepared.targets['team-lead'], 'local');
      expect(prepared.markInitialized, isTrue);
      expect(prepared.leadValid, isTrue);
    });

    test('leadValid is false when lead is on wrong host', () {
      final prepared = prepareMemberPlacementSave(
        team: TeamProfile(
          id: 't1',
          name: 'T',
          members: const [
            TeamMemberConfig(id: 'team-lead', name: 'Lead'),
            TeamMemberConfig(id: 'dev', name: 'Dev'),
          ],
          createdAt: 1,
        ),
        folders: const [
          WorkspaceFolder(path: '/a'),
          WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ],
        placement: {
          'local': {'dev': 1},
          'ssh:p1': {'team-lead': 1, 'dev': 1},
        },
      );
      expect(prepared.members.firstWhere((m) => m.id == 'dev').replicas, 2);
      expect(prepared.targets['team-lead'], 'ssh:p1');
      expect(prepared.markInitialized, isTrue);
      expect(prepared.leadValid, isFalse);
    });
  });
}
