import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_persist_params.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  test('createSession persists landing full-access permission override', () async {
    final tmp = await Directory.systemTemp.createTemp('landing_permission_create_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([
      const WorkspaceFolder(path: '/w'),
    ]);

    const draft = LandingLaunchContext(
      isPersonal: true,
      dangerouslySkipPermissions: true,
    );
    final params = SessionPersistParams(
      sessionTeamId: '',
      cli: CliTool.claude,
      continueOverrides: SessionContinueOverrides(
        dangerouslySkipPermissions: draft.dangerouslySkipPermissions,
      ),
    );

    final session = await repo.createSession(
      workspace.workspaceId,
      cli: params.cli,
      continueOverrides: params.continueOverrides,
    );

    expect(session.continueOverrides.dangerouslySkipPermissions, isTrue);
    expect(
      (await repo.loadSessions()).single.continueOverrides.dangerouslySkipPermissions,
      isTrue,
    );
  });
}
