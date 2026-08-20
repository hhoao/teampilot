import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

void main() {
  test('findById returns created session and null for unknown id', () async {
    final tmp = await Directory.systemTemp.createTemp('session_find_by_id_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SessionRepository(rootDir: tmp.path);
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/tmp/find-by-id'),
    ]);
    final created = (await repo.createSession(workspace.workspaceId)).session;

    final found = await repo.findById(created.sessionId);
    expect(found, isNotNull);
    expect(found!.sessionId, created.sessionId);
    expect(found.workspaceId, workspace.workspaceId);

    expect(await repo.findById('missing-session'), isNull);
  });
}
