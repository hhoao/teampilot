import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/session_persist_params.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'createSession does not persist a landing permission override',
    () async {
      final tmp = await Directory.systemTemp.createTemp(
        'landing_permission_create_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(
        rootDir: tmp.path,
        storage: fakeHomeStorage(),
      );
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/w'),
      ]);

      final params = SessionPersistParams(
        sessionTeamId: '',
        cli: CliTool.claude,
        continueOverrides: const SessionContinueOverrides(),
      );

      final session = (await repo.createSession(
        workspace.workspaceId,
        cli: params.cli,
        continueOverrides: params.continueOverrides,
      )).session;

      expect(session.continueOverrides.toJson(), isEmpty);
      expect(
        (await repo.loadSessions()).single.continueOverrides.toJson(),
        isEmpty,
      );
    },
  );
}
