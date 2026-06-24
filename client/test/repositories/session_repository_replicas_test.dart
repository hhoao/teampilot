import 'dart:io';

import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createSession allocates one binding per instance via replicas',
      () async {
    final tmp = await Directory.systemTemp.createTemp('fs_session_repo_rep_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([WorkspaceFolder(path: '/replicas')]);
    final workspaceId = workspace.workspaceId;

    final session = await repo.createSession(
      workspaceId,
      sessionTeam: 'team-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
      ],
    );
    expect(
      session.members.map((b) => b.rosterMemberId),
      ['team-lead', 'builder-0', 'builder-1'],
    );
    expect(
      session.members.map((b) => b.typeId),
      ['team-lead', 'builder', 'builder'],
    );
    expect(session.members.map((b) => b.taskId).toSet().length, 3);
  });
}
