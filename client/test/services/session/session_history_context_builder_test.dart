import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex/codex_session_config_dir.dart';
import 'package:teampilot/services/provider/cursor/cursor_session_config_dir.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory base;
  late RuntimeLayout layout;
  late LocalFilesystem fs;
  late SessionHistoryContextBuilder builder;

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('session_history_ctx_');
    fs = LocalFilesystem(
      pathContext: p.Context(style: p.Style.posix, current: base.path),
    );
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
    builder = const SessionHistoryContextBuilder();
  });

  tearDown(() {
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
    tearDownTestAppStorage();
  });

  AppSession simpleSession({
    String id = 'session-1',
    CliTool cli = CliTool.claude,
    AppSessionLaunchState launchState = AppSessionLaunchState.started,
    Map<String, String> nativeSessionIds = const {},
    String folder = '/work/project',
  }) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: [WorkspaceFolder(path: folder)],
    cli: cli,
    launchState: launchState,
    nativeSessionIds: nativeSessionIds,
    createdAt: 1,
    updatedAt: 1,
  );

  test('simple claude returns isolation transcript roots and bucket', () {
    final session = simpleSession();
    final cwd = session.firstFolderPath;

    final ctx = builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: '',
      cli: CliTool.claude,
      workingDirectory: cwd,
    );

    final expectedRoots = [
      layout.appToolRoot('claude'),
      layout.workspaceConfigToolDir('ws-1', 'claude'),
      layout.sessionRuntimeToolDir('ws-1', 'session-1', 'claude'),
    ];
    expect(ctx.transcriptRoots, expectedRoots);
    expect(
      ctx.bucket,
      RuntimeLayout.workspaceBucketForPrimaryPath(cwd),
    );
    expect(ctx.taskId, 'session-1');
    expect(ctx.workspaceId, 'ws-1');
    expect(ctx.sessionId, 'session-1');
    expect(ctx.memberId, isNull);
    expect(ctx.teamId, isNull);
    expect(ctx.manifestDataRoot, base.path);
    expect(identical(ctx.fs, fs), isTrue);
  });

  test('never-launched session still points at would-be tool dirs', () {
    final session = simpleSession(
      cli: CliTool.codex,
      launchState: AppSessionLaunchState.created,
    );

    final ctx = builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: '',
      cli: CliTool.codex,
      workingDirectory: session.firstFolderPath,
    );

    final expectedHome = CodexSessionConfigDir.resolve(
      layout,
      workspaceId: 'ws-1',
      sessionId: 'session-1',
    );
    expect(ctx.env['CODEX_HOME'], expectedHome);
    expect(Directory(expectedHome).existsSync(), isFalse);
  });

  test('builder does not create session runtime dirs', () {
    final session = simpleSession(cli: CliTool.opencode);
    final toolDir = layout.sessionRuntimeToolDir(
      'ws-1',
      'session-1',
      'opencode',
    );

    builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: '',
      cli: CliTool.opencode,
      workingDirectory: session.firstFolderPath,
    );

    expect(Directory(toolDir).existsSync(), isFalse);
  });

  test('codex sets CODEX_HOME to session tool dir', () {
    final session = simpleSession(cli: CliTool.codex);
    final ctx = builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: '',
      cli: CliTool.codex,
      workingDirectory: session.firstFolderPath,
    );

    expect(
      ctx.env['CODEX_HOME'],
      CodexSessionConfigDir.resolve(
        layout,
        workspaceId: 'ws-1',
        sessionId: 'session-1',
      ),
    );
  });

  test('opencode sets OPENCODE_DATA_DIR to session tool dir', () {
    final session = simpleSession(cli: CliTool.opencode);
    final ctx = builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: '',
      cli: CliTool.opencode,
      workingDirectory: session.firstFolderPath,
    );

    expect(
      ctx.env['OPENCODE_DATA_DIR'],
      layout.sessionRuntimeToolDir('ws-1', 'session-1', 'opencode'),
    );
  });

  test('cursor sets CURSOR_CONFIG_DIR and HOME for isolated .cursor', () {
    final session = simpleSession(
      cli: CliTool.cursor,
      nativeSessionIds: const {'cursor': 'chat-abc'},
    );
    final ctx = builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: '',
      cli: CliTool.cursor,
      workingDirectory: session.firstFolderPath,
    );

    final cursorRoot = CursorSessionConfigDir.resolve(
      layout,
      workspaceId: 'ws-1',
      sessionId: 'session-1',
    );
    expect(ctx.env['CURSOR_CONFIG_DIR'], cursorRoot);
    expect(ctx.env['HOME'], p.dirname(cursorRoot));
    expect(ctx.persistedNativeId, 'chat-abc');
  });

  test('team member resolves taskId and native id from binding', () {
    const binding = SessionMemberBinding(
      rosterMemberId: 'builder-0',
      taskId: 'task-builder-0',
      nativeSessionIds: {'codex': 'rollout-id-1'},
    );
    final session = AppSession(
      sessionId: 'session-team',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work/project')],
      sessionTeam: 'team-a',
      members: const [binding],
      launchState: AppSessionLaunchState.started,
      createdAt: 1,
      updatedAt: 1,
    );

    final ctx = builder.build(
      fs: fs,
      layout: layout,
      appDataRoot: base.path,
      session: session,
      memberId: 'builder-0',
      cli: CliTool.codex,
      workingDirectory: '/work/project',
      teamId: 'team-a',
    );

    expect(ctx.taskId, 'task-builder-0');
    expect(ctx.persistedNativeId, 'rollout-id-1');
    expect(ctx.memberId, 'builder-0');
    expect(ctx.teamId, 'team-a');
    expect(
      ctx.env['CODEX_HOME'],
      CodexSessionConfigDir.resolve(
        layout,
        workspaceId: 'ws-1',
        sessionId: 'session-team',
        memberId: 'builder-0',
      ),
    );
    expect(
      ctx.transcriptRoots,
      layout.transcriptSearchRoots(
        workspaceId: 'ws-1',
        sessionId: 'session-team',
        profileId: 'team-a',
        memberId: 'builder-0',
        tools: const ['codex'],
      ),
    );
  });

  test('missing team member binding throws', () {
    final session = AppSession(
      sessionId: 'session-team',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work/project')],
      sessionTeam: 'team-a',
      members: const [],
      createdAt: 1,
    );

    expect(
      () => builder.build(
        fs: fs,
        layout: layout,
        appDataRoot: base.path,
        session: session,
        memberId: 'missing',
        cli: CliTool.claude,
        workingDirectory: '/work/project',
        teamId: 'team-a',
      ),
      throwsStateError,
    );
  });

  test('memberId without teamId throws', () {
    const binding = SessionMemberBinding(
      rosterMemberId: 'builder-0',
      taskId: 'task-builder-0',
    );
    final session = AppSession(
      sessionId: 'session-team',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work/project')],
      sessionTeam: '',
      members: const [binding],
      createdAt: 1,
    );

    expect(
      () => builder.build(
        fs: fs,
        layout: layout,
        appDataRoot: base.path,
        session: session,
        memberId: 'builder-0',
        cli: CliTool.claude,
        workingDirectory: '/work/project',
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('teamId'),
      )),
    );
  });

  test('empty workspaceId throws', () {
    final session = AppSession(
      sessionId: 'session-1',
      workspaceId: '',
      folders: const [WorkspaceFolder(path: '/work/project')],
      createdAt: 1,
    );

    expect(
      () => builder.build(
        fs: fs,
        layout: layout,
        appDataRoot: base.path,
        session: session,
        memberId: '',
        cli: CliTool.claude,
        workingDirectory: '/work/project',
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('workspaceId'),
      )),
    );
  });
}
