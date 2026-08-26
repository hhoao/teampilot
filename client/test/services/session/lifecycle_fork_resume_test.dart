import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late SessionRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lifecycle_fork_resume_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: tmp.path, fs: fs);
    repo = SessionRepository(rootDir: tmp.path);
  });

  test('forked simple claude session pins --resume to the source transcript',
      () async {
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/tmp/my-workspace'),
    ]);
    final source = (await repo.createSession(
      workspace.workspaceId,
      cli: CliTool.claude,
    )).session;
    // clientPinned: the source transcript lives under its own sessionId.
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      '/tmp/my-workspace',
    );
    final sourceToolDir = layout.sessionRuntimeToolDir(
      workspace.workspaceId,
      source.sessionId,
      'claude',
    );
    await fs.ensureDir(fs.pathContext.join(sourceToolDir, 'projects', bucket));
    final transcriptPath = fs.pathContext.join(
      sourceToolDir,
      'projects',
      bucket,
      '${source.sessionId}.jsonl',
    );
    await fs.writeString(
      transcriptPath,
      '{"type":"user","message":{"content":"hi"}}\n',
    );

    final fork = await repo.duplicateSession(source.sessionId, display: 'Fork');

    // Resume-resolution inputs built exactly the way
    // SessionLifecycleService._resolveResume builds them for a Simple
    // session: taskId == fork id, transcript root == the fork's runtime
    // tool dir, persisted id from nativeSessionIds.
    final ctx = ResumeContext(
      fs: fs,
      toolValue: 'claude',
      taskId: fork.sessionId,
      env: const {},
      transcriptRoots: [
        layout.sessionRuntimeToolDir(
          fork.workspaceId,
          fork.sessionId,
          'claude',
        ),
      ],
      bucket: bucket,
      persistedNativeId: fork.nativeSessionIds['claude'],
    );
    expect(
      await ClaudeAiHistoryCapability().detectNativeId(ctx),
      source.sessionId,
      reason: 'launch must resolve --resume {sourceId} for the fork',
    );

    final service = SessionLifecycleService(appDataBasePath: tmp.path);
    final liveWorkspace = (await repo.loadWorkspaces()).firstWhere(
      (w) => w.workspaceId == workspace.workspaceId,
    );
    expect(
      await service.hasCliState(fork, workspace: liveWorkspace),
      isTrue,
      reason: 'hasCliState must see the copied transcript via the persisted '
          'id even though launchState is still created',
    );
  });
}
