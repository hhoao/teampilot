import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_ai_transcript.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory base;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  var mtimeToken = 'mtime-1';

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );

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

  AiHistoryLoader buildLoader({
    AiHistoryLocator? locator,
    Map<CliTool, AiTranscriptAdapter>? adapters,
    AiHistoryWorkContextResolver? resolveWorkContext,
  }) {
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext:
          resolveWorkContext ?? ((_, {String? memberId}) async => fixedRoots()),
      locator: locator ?? AiHistoryLocator(),
      adapters: adapters,
      resolveCacheToken: (_) async => mtimeToken,
    );
  }

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('ai_history_loader_');
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

  test('missing transcript returns empty list', () async {
    final session = simpleSession();
    final result = await buildLoader().load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    );
    expect(result.messages, isEmpty);
    expect(result.subagentAttachments, isEmpty);
  });

  test('parses Claude fixture bytes via locate + adapter', () async {
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final sessionId = 'sess-a';
    final toolRoot = layout.sessionRuntimeToolDir('ws-1', sessionId, 'claude');
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, '$sessionId.jsonl')).writeAsBytes(fixture);

    final session = simpleSession(id: sessionId);
    final result = await buildLoader().load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    );
    final messages = result.messages;

    expect(messages, isNotEmpty);
    expect(messages.first.id, 'u-1');
    expect(messages.first.role, AiRole.user);
    expect(
      messages.where((m) => m.role == AiRole.assistant),
      isNotEmpty,
    );
  });

  test('load uses work-context FS from resolver, not home FS', () async {
    final workRoot = Directory.systemTemp.createTempSync('ai_history_work_');
    try {
      final workFs = LocalFilesystem(
        pathContext: p.Context(style: p.Style.posix, current: workRoot.path),
      );
      final workRuntime = RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: workFs,
        home: workRoot.path,
        cwd: workRoot.path,
        appDataRoot: workRoot.path,
        paths: AppPaths(workRoot.path),
      );
      final workLayout = workRuntime.layout;

      final session = simpleSession();
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        '/work/project',
      );
      final sessionId = session.sessionId;
      final toolRoot = workLayout.sessionRuntimeToolDir(
        'ws-1',
        sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final fixture = await File(
        'test/fixtures/session_history/claude/basic.jsonl',
      ).readAsBytes();
      await File(p.join(projects, '$sessionId.jsonl')).writeAsBytes(fixture);

      SessionHistoryContext? locatedCtx;
      final loader = buildLoader(
        locator: _CapturingLocator(
          onLocate: (ctx) => locatedCtx = ctx,
        ),
        resolveWorkContext: (_, {String? memberId}) async => workRuntime,
      );

      final result = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchContextFor(session),
      );

      expect(result.messages, isNotEmpty);
      expect(locatedCtx?.fs, same(workFs));
      expect(locatedCtx?.fs, isNot(same(fs)));
    } finally {
      if (workRoot.existsSync()) {
        workRoot.deleteSync(recursive: true);
      }
    }
  });

  test('resolve failure does not fall back to home FS', () async {
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final session = simpleSession();
    final sessionId = session.sessionId;
    final toolRoot = layout.sessionRuntimeToolDir('ws-1', sessionId, 'claude');
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, '$sessionId.jsonl')).writeAsBytes(fixture);

    final loader = buildLoader(
      resolveWorkContext: (_, {String? memberId}) async =>
          throw StateError('ssh down'),
    );

    await expectLater(
      () => loader.load(
        session: session,
        memberId: '',
        launchContext: launchContextFor(session),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('throws StateError when adapter missing for launch CLI', () async {
    final session = simpleSession();
    final loader = buildLoader(adapters: const {});
    await expectLater(
      () => loader.load(
        session: session,
        memberId: '',
        launchContext: launchContextFor(session),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('AiTranscriptAdapter missing'),
        ),
      ),
    );
  });

  test('mtime unchanged reuses cache on reload', () async {
    var locateCalls = 0;
    final locator = _CountingLocator(() async {
      locateCalls++;
      return null;
    });
    final loader = buildLoader(locator: locator);

    final session = simpleSession();
    final ctx = launchContextFor(session);
    expect(
      (await loader.load(session: session, memberId: '', launchContext: ctx))
          .messages,
      isEmpty,
    );
    expect(locateCalls, 1);

    expect(
      (await loader.load(session: session, memberId: '', launchContext: ctx))
          .messages,
      isEmpty,
    );
    expect(locateCalls, 1);

    mtimeToken = 'mtime-2';
    expect(
      (await loader.load(session: session, memberId: '', launchContext: ctx))
          .messages,
      isEmpty,
    );
    expect(locateCalls, 2);
  });

  test('clearCache drops token hits', () async {
    var locateCalls = 0;
    final locator = _CountingLocator(() async {
      locateCalls++;
      return null;
    });
    final loader = buildLoader(locator: locator);
    final session = simpleSession();
    final ctx = launchContextFor(session);

    expect(
      (await loader.load(session: session, memberId: '', launchContext: ctx))
          .messages,
      isEmpty,
    );
    expect(locateCalls, 1);
    expect(
      (await loader.load(session: session, memberId: '', launchContext: ctx))
          .messages,
      isEmpty,
    );
    expect(locateCalls, 1);

    loader.clearCache();
    expect(
      (await loader.load(session: session, memberId: '', launchContext: ctx))
          .messages,
      isEmpty,
    );
    expect(locateCalls, 2);
  });

  test('default adapters include Claude', () {
    expect(
      AiHistoryLoader.defaultAdapters[CliTool.claude],
      isA<ClaudeAiTranscriptAdapter>(),
    );
  });

  test('resolveWatchMeta returns hints from locate without parsing', () async {
    final locator = _CountingLocator(() async {
      return AiTranscriptBundle(
        adapterId: 'claude',
        fragments: const [
          AiTranscriptFragment(name: 'canned.jsonl', bytes: []),
        ],
        hints: const AiHistoryWatchMeta(
          changeWatchRoot: '/proj',
          cacheTokenPaths: ['/proj/a.jsonl'],
        ).toHints(),
      );
    });
    final loader = buildLoader(
      locator: locator,
      adapters: const {}, // parse must not be required
    );

    final session = simpleSession();
    final meta = await loader.resolveWatchMeta(
      launchContext: launchContextFor(session),
      memberId: '',
    );
    expect(meta?.changeWatchRoot, '/proj');
    expect(meta?.cacheTokenPaths, ['/proj/a.jsonl']);
  });

  test('resolveWatchMeta returns null when locate misses', () async {
    final loader = buildLoader(
      locator: _CountingLocator(() async => null),
      adapters: const {},
    );
    final session = simpleSession();
    expect(
      await loader.resolveWatchMeta(
        launchContext: launchContextFor(session),
        memberId: '',
      ),
      isNull,
    );
  });
}

class _CountingLocator extends AiHistoryLocator {
  _CountingLocator(this._onLocate);

  final Future<AiTranscriptBundle?> Function() _onLocate;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) =>
      _onLocate();
}

class _CapturingLocator extends AiHistoryLocator {
  _CapturingLocator({required this.onLocate});

  final void Function(SessionHistoryContext ctx) onLocate;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) {
    onLocate(ctx);
    return super.locate(ctx: ctx, cli: cli);
  }
}
