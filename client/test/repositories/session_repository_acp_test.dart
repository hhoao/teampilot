import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late Directory tmp;
  late SessionRepository repo;
  late String workspaceId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fs_session_repo_acp_');
    repo = SessionRepository(rootDir: tmp.path, storage: fakeHomeStorage());
    final ws = await repo.createWorkspace([
      WorkspaceFolder(path: '/repo/main'),
    ]);
    workspaceId = ws.workspaceId;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('personal Claude acp true persists true', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.claude,
      acp: true,
    )).session;
    expect(session.acp, isTrue);
  });

  test('personal Claude default persists false', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.claude,
    )).session;
    expect(session.acp, isFalse);
  });

  test('personal Gemini persists true even when acp is false', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.gemini,
      acp: false,
    )).session;
    expect(session.acp, isTrue);
  });

  test('team session persists false even when acp is true', () async {
    final session = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-1',
      rosterMembers: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      memberClis: const {'team-lead': CliTool.claude},
      cli: CliTool.gemini,
      acp: true,
    )).session;
    expect(session.acp, isFalse);
  });
}
