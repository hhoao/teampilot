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

    test('requires member assignment only for mixed', () {
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

    test('memberTargetsComplete requires every instance', () {
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
          targets: const {
            'lead': 'local',
            'dev-0': 'local',
          },
        ),
        isFalse,
      );
      expect(
        memberTargetsComplete(
          workspaceFolders: folders,
          members: members,
          targets: const {
            'lead': 'local',
            'dev-0': 'local',
            'dev-1': 'ssh:p1',
          },
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
        memberPlacementFromMemberTargets(
          members: members,
          targets: targets,
        ),
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
  });
}
