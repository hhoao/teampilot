import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory base;
  late LocalFilesystem fs;
  late RuntimeLayout layout;

  const workspaceId = 'ws-1';
  const sessionId = 'session-team-1';
  const teamId = 'team-a';
  const memberId = 'team-lead';
  const realTaskId = 'task-lead-stable-abc';
  const projectPath = '/work/project';

  WorkspaceLaunchContext launchContextFor(AppSession session) =>
      WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 1,
        ),
      );

  RuntimeContext fixedRoots() => RuntimeContext(
    target: RuntimeTarget.local(),
    filesystem: fs,
    home: base.path,
    cwd: base.path,
    appDataRoot: base.path,
    paths: AppPaths(base.path),
  );

  AiHistoryLoader buildLoader() => AiHistoryLoader(
    contextBuilder: const SessionHistoryContextBuilder(),
    resolveWorkContext: (_, {String? memberId}) async => fixedRoots(),
    locator: AiHistoryLocator(),
    resolveCacheToken: (_) async => 'mtime-stable',
  );

  AppSession teamSession({required String bindingTaskId}) => AppSession(
    sessionId: sessionId,
    workspaceId: workspaceId,
    folders: const [WorkspaceFolder(path: projectPath)],
    sessionTeam: teamId,
    members: [
      SessionMemberBinding(
        rosterMemberId: memberId,
        taskId: bindingTaskId,
      ),
    ],
    launchState: AppSessionLaunchState.started,
    createdAt: 1,
    updatedAt: 1,
  );

  Future<void> writeClaudeTranscript({
    required String transcriptTaskId,
  }) async {
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(projectPath);
    final toolRoot = layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      'claude',
      memberId: memberId,
    );
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, '$transcriptTaskId.jsonl')).writeAsBytes(
      fixture,
    );
  }

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('stable_task_id_history_');
    fs = LocalFilesystem(
      pathContext: p.Context(style: p.Style.posix, current: base.path),
    );
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
  });

  tearDown(() {
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
    tearDownTestAppStorage();
  });

  test('locate hits transcript when binding.taskId matches filename', () async {
    await writeClaudeTranscript(transcriptTaskId: realTaskId);

    final session = teamSession(bindingTaskId: realTaskId);
    final result = await buildLoader().load(
      session: session,
      memberId: memberId,
      launchContext: launchContextFor(session),
    );

    expect(result.messages, isNotEmpty);
    expect(result.messages.first.id, 'u-1');
  });

  test(
    'locate misses when binding.taskId equals sessionId (old bug shape)',
    () async {
      await writeClaudeTranscript(transcriptTaskId: realTaskId);

      final session = teamSession(bindingTaskId: sessionId);
      final result = await buildLoader().load(
        session: session,
        memberId: memberId,
        launchContext: launchContextFor(session),
      );

      expect(result.messages, isEmpty);
    },
  );
}
