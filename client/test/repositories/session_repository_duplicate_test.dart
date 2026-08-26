import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late SessionRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('session_duplicate_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: tmp.path, fs: fs);
    repo = SessionRepository(rootDir: tmp.path);
  });

  Future<AppSession> seedSimpleSession(CliTool cli) async {
    final workspace = await repo.createWorkspace([
      WorkspaceFolder(path: '/tmp/my-workspace'),
    ]);
    final created = (await repo.createSession(
      workspace.workspaceId,
      cli: cli,
    )).session;
    await repo.renameSession(created.sessionId, 'My chat');
    return created;
  }

  Future<String> writeClaudeTranscript(AppSession session, String id) async {
    final toolDir = layout.sessionRuntimeToolDir(
      session.workspaceId,
      session.sessionId,
      'claude',
    );
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
      '/tmp/my-workspace',
    );
    final dir = fs.pathContext.join(toolDir, 'projects', bucket);
    await fs.ensureDir(dir);
    final path = fs.pathContext.join(dir, '$id.jsonl');
    await fs.writeString(path, '{"type":"user","message":{"content":"hi"}}\n');
    return path;
  }

  test('duplicates a simple claude session with a history fork', () async {
    final source = await seedSimpleSession(CliTool.claude);
    final transcriptPath = await writeClaudeTranscript(
      source,
      source.sessionId,
    );

    final fork = await repo.duplicateSession(
      source.sessionId,
      display: 'My chat (copy)',
    );

    expect(fork.isSimple, isTrue);
    expect(fork.sessionId, isNot(source.sessionId));
    expect(fork.display, 'My chat (copy)');
    expect(fork.cli, CliTool.claude);
    expect(fork.folders.length, source.folders.length);
    expect(fork.firstFolderPath, source.firstFolderPath);
    expect(fork.launchState, AppSessionLaunchState.created);
    // clientPinned: seed the source sessionId so resume finds the copied
    // transcript filename.
    expect(fork.nativeSessionIds, {'claude': source.sessionId});

    final copiedPath = fs.pathContext.join(
      layout.sessionRuntimeToolDir(
        source.workspaceId,
        fork.sessionId,
        'claude',
      ),
      'projects',
      RuntimeLayout.workspaceBucketForPrimaryPath('/tmp/my-workspace'),
      '${source.sessionId}.jsonl',
    );
    expect(await fs.readString(copiedPath), isNotNull);

    // Source untouched.
    final reloadedSource = await repo.findById(source.sessionId);
    expect(reloadedSource!.display, 'My chat');
    expect(await fs.readString(transcriptPath), isNotNull);

    // Fork is listed and indexed.
    final sessions = await repo.loadSessionsForWorkspace(source.workspaceId);
    expect(
      sessions.map((s) => s.sessionId),
      containsAll([source.sessionId, fork.sessionId]),
    );
  });

  test('carries persisted postCaptured native ids across the fork', () async {
    final source = await seedSimpleSession(CliTool.codex);
    await repo.recordNativeSessionId(
      source.sessionId,
      tool: 'codex',
      nativeId: 'codex-native-uuid-1',
    );
    final sourceSessions = layout.sessionRuntimeToolDir(
      source.workspaceId,
      source.sessionId,
      'codex',
    );
    final rolloutDir = fs.pathContext.join(
      sourceSessions,
      'sessions',
      '2026',
      '08',
      '26',
    );
    await fs.ensureDir(rolloutDir);
    await fs.writeString(
      fs.pathContext.join(
        rolloutDir,
        'rollout-2026-08-26-codex-native-uuid-1.jsonl',
      ),
      '{"session_meta":{}}\n',
    );

    final fork = await repo.duplicateSession(
      source.sessionId,
      display: 'Fork codex',
    );

    expect(fork.nativeSessionIds['codex'], 'codex-native-uuid-1');
    final copiedRollout = fs.pathContext.join(
      layout.sessionRuntimeToolDir(source.workspaceId, fork.sessionId, 'codex'),
      'sessions',
      '2026',
      '08',
      '26',
      'rollout-2026-08-26-codex-native-uuid-1.jsonl',
    );
    expect(await fs.readString(copiedRollout), isNotNull);
  });

  test('skips the copy silently when the CLI never launched', () async {
    final source = await seedSimpleSession(CliTool.claude);
    final fork = await repo.duplicateSession(
      source.sessionId,
      display: 'Fresh fork',
    );
    expect(fork.nativeSessionIds, {'claude': source.sessionId});
    final toolDir = layout.sessionRuntimeToolDir(
      source.workspaceId,
      fork.sessionId,
      'claude',
    );
    expect((await fs.stat(toolDir)).isDirectory, isFalse);
  });

  test('rejects team sessions', () async {
    final source = await seedSimpleSession(CliTool.claude);
    await repo.updateSessionTeam(source.sessionId, 'some-team');
    expect(
      () => repo.duplicateSession(source.sessionId, display: 'x'),
      throwsStateError,
    );
  });

  test('throws for unknown session ids', () async {
    expect(
      () => repo.duplicateSession('missing-id', display: 'x'),
      throwsStateError,
    );
  });
}
