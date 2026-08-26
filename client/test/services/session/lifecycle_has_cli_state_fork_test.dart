import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late SessionLifecycleService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lifecycle_cli_state_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: tmp.path, fs: fs);
    service = SessionLifecycleService(appDataBasePath: tmp.path);
  });

  Future<void> seedClaudeTranscript(String sessionId, String transcriptId) async {
    final toolDir = layout.sessionRuntimeToolDir('ws1', sessionId, 'claude');
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/tmp/proj');
    final dir = fs.pathContext.join(toolDir, 'projects', bucket);
    await fs.ensureDir(dir);
    await fs.writeString(fs.pathContext.join(dir, '$transcriptId.jsonl'), '{}\n');
  }

  AppSession sessionWith(Map<String, String> nativeIds) => AppSession(
        sessionId: 'fork-session-id',
        workspaceId: 'ws1',
        folders: [WorkspaceFolder(path: '/tmp/proj')],
        cli: CliTool.claude,
        nativeSessionIds: nativeIds,
        createdAt: 1,
      );

  Workspace workspaceFor(AppSession session) => Workspace(
        workspaceId: session.workspaceId,
        folders: session.folders,
        display: 'ws',
        createdAt: 1,
      );

  test('finds forked state via persisted native id', () async {
    await seedClaudeTranscript('fork-session-id', 'source-session-id');
    final session = sessionWith({'claude': 'source-session-id'});
    final has = await service.hasCliState(session, workspace: workspaceFor(session));
    expect(has, isTrue);
  });

  test('still false when neither taskId nor persisted state exists', () async {
    final session = sessionWith({'claude': 'source-session-id'});
    final has = await service.hasCliState(session, workspace: workspaceFor(session));
    expect(has, isFalse);
  });

  test('taskId probe still works without persisted ids', () async {
    await seedClaudeTranscript('fork-session-id', 'fork-session-id');
    final session = sessionWith(const {});
    final has = await service.hasCliState(session, workspace: workspaceFor(session));
    expect(has, isTrue);
  });
}
