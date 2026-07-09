import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/chat/model/session_open_status.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/launch/session_launch_open_validator.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: [WorkspaceFolder(path: '/project')],
    createdAt: 0,
  );

  final mixedWorkspace = Workspace(
    workspaceId: 'ws-mixed',
    folders: [
      WorkspaceFolder(path: '/local', targetId: 'local'),
      WorkspaceFolder(path: '/remote', targetId: 'ssh:host'),
    ],
    createdAt: 0,
  );

  const team = TeamProfile(
    id: 'team-a',
    name: 'A',
    members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
  );

  Workspace? workspaceById(String id) => switch (id) {
    'ws-1' => workspace,
    'ws-mixed' => mixedWorkspace,
    _ => null,
  };

  group('validateSessionOpenRequest', () {
    test('personal session requires workspace', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'missing',
        folders: workspace.folders,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(session: session),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, SessionOpenStatus.missingWorkspace);
    });

    test('team session requires team and member', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: workspace.workspaceId,
        folders: workspace.folders,
        sessionTeam: team.id,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(session: session, workspace: workspace),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, SessionOpenStatus.missingTeamMember);
    });

    test('mixed workspace blocks when placement not initialized', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: mixedWorkspace.workspaceId,
        folders: mixedWorkspace.folders,
        sessionTeam: team.id,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(
          session: session,
          workspace: mixedWorkspace,
          team: team,
          member: team.members.first,
        ),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, SessionOpenStatus.blockedMixedMemberTargets);
    });

    test('mixed workspace allows open when initialized with valid lead', () {
      final initialized = mixedWorkspace.copyWith(
        memberTargetsByTeam: {
          team.id: {'team-lead': 'local'},
        },
        memberPlacementInitializedByTeam: {team.id: true},
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: initialized.workspaceId,
        folders: initialized.folders,
        sessionTeam: team.id,
        memberTargets: const {'team-lead': 'local'},
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(
          session: session,
          workspace: initialized,
          team: team,
          member: team.members.first,
        ),
        session: session,
        workspaceById: (_) => initialized,
      );
      expect(status, isNull);
    });

    test('returns null when request is valid', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: workspace.workspaceId,
        folders: workspace.folders,
        createdAt: 0,
      );
      final status = validateSessionOpenRequest(
        request: SessionOpenRequest(session: session, workspace: workspace),
        session: session,
        workspaceById: workspaceById,
      );
      expect(status, isNull);
    });
  });
}
