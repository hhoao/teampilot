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

    test('personalIdentityBlockedForWorkspace', () {
      expect(
        personalIdentityBlockedForWorkspace(
          isPersonal: true,
          folders: const [WorkspaceFolder(path: '/a')],
        ),
        isFalse,
      );
      expect(
        personalIdentityBlockedForWorkspace(
          isPersonal: false,
          folders: const [
            WorkspaceFolder(path: '/a'),
            WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
          ],
        ),
        isFalse,
      );
      expect(
        personalIdentityBlockedForWorkspace(
          isPersonal: true,
          folders: const [
            WorkspaceFolder(path: '/a'),
            WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
          ],
        ),
        isTrue,
      );
    });

    test('memberFolderAssignmentsComplete', () {
      const members = [
        TeamMemberConfig(id: 'lead', name: 'Lead', cli: CliTool.claude),
        TeamMemberConfig(id: 'dev', name: 'Dev', cli: CliTool.claude),
      ];
      const folders = [
        WorkspaceFolder(path: '/local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      expect(
        memberFolderAssignmentsComplete(
          workspaceFolders: folders,
          members: members,
          assignments: const {},
        ),
        isFalse,
      );
      expect(
        memberFolderAssignmentsComplete(
          workspaceFolders: folders,
          members: members,
          assignments: const {
            'lead': ['/local'],
            'dev': ['/remote'],
          },
        ),
        isTrue,
      );
    });
  });
}
