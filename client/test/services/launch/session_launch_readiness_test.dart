import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/launch/session_launch_readiness.dart';

void main() {
  group('ensureSessionLaunchReady', () {
    test('returns in-memory session for remote workspace without disk reload', () async {
      final tmp = await Directory.systemTemp.createTemp('launch_ready_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/remote/project', targetId: 'ssh:host'),
      ]);
      final session = await repo.createSession(workspace.workspaceId);

      final result = await ensureSessionLaunchReady(
        workspace: workspace,
        session: session,
        team: const TeamProfile(
          id: 'team-a',
          name: 'A',
          members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
        ),
        repository: repo,
      );

      expect(result, session);
    });
  });
}
