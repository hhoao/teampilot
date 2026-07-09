import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';

void main() {
  group('workspaceTopologyOf', () {
    test('empty defaults to local', () {
      expect(workspaceTopologyOf(const []), WorkspaceTopology.local);
    });

    test('all local folders', () {
      expect(
        workspaceTopologyOf([
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b'),
        ]),
        WorkspaceTopology.local,
      );
    });

    test('all same ssh target is remote', () {
      expect(
        workspaceTopologyOf([
          const WorkspaceFolder(path: '/a', targetId: 'ssh:p1'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        WorkspaceTopology.remote,
      );
    });

    test('distinct targets is mixed', () {
      expect(
        workspaceTopologyOf([
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        WorkspaceTopology.mixed,
      );
    });

    test('workspaceTopologyRequiresMemberAssignment is true only for mixed', () {
      // Legacy mixed-topology helper; launch gates use init/lead helpers instead.
      expect(
        workspaceTopologyRequiresMemberAssignment([
          const WorkspaceFolder(path: '/a'),
        ]),
        isFalse,
      );
      expect(
        workspaceTopologyRequiresMemberAssignment([
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        isTrue,
      );
    });

    test('memberTargetsComplete reports every instance has a folder-backed target', () {
      // Completeness helper for UI progress — not the launch gate.
      const members = [
        TeamMemberConfig(id: 'lead', name: 'Lead', cli: CliTool.claude),
        TeamMemberConfig(
          id: 'dev',
          name: 'Dev',
          cli: CliTool.claude,
          replicas: 2,
        ),
      ];
      const folders = [
        WorkspaceFolder(path: '/local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      expect(
        memberTargetsComplete(
          workspaceFolders: folders,
          members: members,
          targets: const {'lead': 'local', 'dev-0': 'local'},
        ),
        isFalse,
      );
      expect(
        memberTargetsComplete(
          workspaceFolders: folders,
          members: members,
          targets: const {'lead': 'local', 'dev-0': 'local', 'dev-1': 'ssh:p1'},
        ),
        isTrue,
      );
    });

    test('member placement round-trips through member targets', () {
      const members = [
        TeamMemberConfig(id: 'lead', name: 'Lead', cli: CliTool.claude),
        TeamMemberConfig(
          id: 'dev',
          name: 'Dev',
          cli: CliTool.claude,
          replicas: 3,
        ),
      ];
      const folders = [
        WorkspaceFolder(path: '/local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      final placement = <String, Map<String, int>>{
        'local': {'lead': 1, 'dev': 2},
        'ssh:p1': {'dev': 1},
      };
      expect(
        memberPlacementComplete(
          workspaceFolders: folders,
          members: members,
          placement: placement,
        ),
        isTrue,
      );
      final targets = memberTargetsFromMemberPlacement(
        workspaceFolders: folders,
        members: members,
        placement: placement,
      );
      expect(targets['lead'], 'local');
      expect(targets['dev-0'], 'local');
      expect(targets['dev-1'], 'local');
      expect(targets['dev-2'], 'ssh:p1');
      expect(
        memberPlacementFromMemberTargets(members: members, targets: targets),
        placement,
      );
    });

    test('same path on local and remote disambiguates via target id', () {
      const folders = [
        WorkspaceFolder(path: '/repo'),
        WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
      ];
      expect(
        memberWorkDirsForTarget(folders, 'ssh:p1').workingDirectory,
        '/repo',
      );
      expect(
        memberWorkDirsForTarget(folders, 'local').workingDirectory,
        '/repo',
      );
    });

    test('personalWorkDirsForPrimaryPath keeps add-dirs on same target only', () {
      const folders = [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/local-extra', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      final local = personalWorkDirsForPrimaryPath(folders, '/local');
      expect(local.workingDirectory, '/local');
      expect(local.addDirs, ['/local-extra']);

      final remote = personalWorkDirsForPrimaryPath(folders, '/remote');
      expect(remote.workingDirectory, '/remote');
      expect(remote.addDirs, isEmpty);
    });
  });

  group('memberTypeReplicaCount', () {
    test('memberTypeReplicaCount allows 0 for non-lead', () {
      expect(
        memberTypeReplicaCount(
          const TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 0),
        ),
        0,
      );
    });
  });

  group('placement helpers', () {
    test('preferredLeadHost prefers local when present', () {
      expect(
        preferredLeadHost([
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        WorkspaceFolder.localTargetId,
      );
      expect(
        preferredLeadHost([
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ]),
        'ssh:p1',
      );
    });

    test('defaultMemberPlacement pins all types to sole host', () {
      const members = [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'dev', name: 'Dev'),
      ];
      final p = defaultMemberPlacement(
        folders: [const WorkspaceFolder(path: '/a')],
        members: members,
      );
      expect(p['local']?['team-lead'], 1);
      expect(p['local']?['dev'], 1);
    });

    test('defaultMemberPlacement for mixed pins only lead', () {
      const members = [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'dev', name: 'Dev'),
      ];
      final p = defaultMemberPlacement(
        folders: [
          const WorkspaceFolder(path: '/a'),
          const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
        ],
        members: members,
      );
      expect(p['local']?['team-lead'], 1);
      expect(memberPlacementCountForType(p, 'dev'), 0);
    });

    test('leadPlacementValid requires local lead when local exists', () {
      const folders = [
        WorkspaceFolder(path: '/a'),
        WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
      ];
      expect(
        leadPlacementValid(
          folders: folders,
          members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
          targets: const {'team-lead': 'ssh:p1'},
        ),
        isFalse,
      );
      expect(
        leadPlacementValid(
          folders: folders,
          members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
          targets: const {'team-lead': 'local'},
        ),
        isTrue,
      );
    });

    test('workspaceNeedsMixedPlacementInit is true until flag set', () {
      final folders = [
        const WorkspaceFolder(path: '/a'),
        const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
      ];
      expect(
        workspaceNeedsMixedPlacementInit(
          folders: folders,
          teamId: 't1',
          initializedByTeam: const {},
        ),
        isTrue,
      );
      expect(
        workspaceNeedsMixedPlacementInit(
          folders: folders,
          teamId: 't1',
          initializedByTeam: const {'t1': true},
        ),
        isFalse,
      );
      expect(
        workspaceNeedsMixedPlacementInit(
          folders: [const WorkspaceFolder(path: '/a')],
          teamId: 't1',
          initializedByTeam: const {},
        ),
        isFalse,
      );
    });

    test('applyPlacementReplicasToMembers sums counts', () {
      const members = [
        TeamMemberConfig(id: 'team-lead', name: 'Lead', replicas: 9),
        TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 9),
      ];
      final next = applyPlacementReplicasToMembers(
        members: members,
        placement: {
          'local': {'team-lead': 1, 'dev': 2},
          'ssh:p1': {'dev': 1},
        },
      );
      expect(next.firstWhere((m) => m.id == 'team-lead').replicas, 1);
      expect(next.firstWhere((m) => m.id == 'dev').replicas, 3);
    });

    test('inferMemberPlacementInitialized requires valid non-empty targets', () {
      const folders = [
        WorkspaceFolder(path: '/a'),
        WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
      ];
      expect(
        inferMemberPlacementInitialized(
          folders: folders,
          members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
          targets: const {'team-lead': 'local'},
          alreadyInitialized: false,
        ),
        isTrue,
      );
      expect(
        inferMemberPlacementInitialized(
          folders: folders,
          members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
          targets: const {'team-lead': 'ssh:gone'},
          alreadyInitialized: false,
        ),
        isFalse,
      );
    });
  });
}
