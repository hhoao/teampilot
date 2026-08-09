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
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/cursor_ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/fake_ai_history_registry.dart';
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
    CliToolRegistry? registry,
    AiHistoryWorkContextResolver? resolveWorkContext,
  }) {
    final resolvedRegistry = registry ?? CliToolRegistry.builtIn();
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext:
          resolveWorkContext ?? ((_, {String? memberId}) async => fixedRoots()),
      registry: resolvedRegistry,
      locator: locator ?? AiHistoryLocator(registry: resolvedRegistry),
      resolveCacheToken: (_) async => mtimeToken,
    );
  }

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('ai_history_loader_');
    // Host context (not forced POSIX): on Windows `base.path` is a `C:\…`
    // path, so a POSIX context would produce mixed separators that never
    // match the host-context paths written by the fixture (p.join) and read
    // by the loader (fs.pathContext).
    fs = LocalFilesystem();
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

  test('Cursor transcript parses via tailer + appendCursorJsonlEvent', () async {
    // Cursor rows use a top-level `role` field (not claude's `type`), wrap
    // user text in <user_query>, and omit tool_use ids. The loader must parse
    // them with the cursor line dialect — not the claude-compatible tailer.
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final session = simpleSession().copyWith(cli: CliTool.cursor);
    final toolRoot = layout.sessionRuntimeToolDir(
      'ws-1',
      session.sessionId,
      'cursor',
    );
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final path = p.join(projects, '${session.sessionId}.jsonl');
    final fixture = await File(
      'test/fixtures/session_history/cursor/agent_transcript_no_tool_id.jsonl',
    ).readAsBytes();
    await File(path).writeAsBytes(fixture);

    final registry = fakeAiHistoryRegistry(
      cli: CliTool.cursor,
      adapter: const CursorAiTranscriptAdapter(),
      lineAppend: appendCursorJsonlEvent,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'cursor',
        fragments: [
          AiTranscriptFragment(name: 't.jsonl', bytes: [1, 2, 3]),
        ],
        hints: AiHistoryWatchMeta(
          changeWatchRoot: p.dirname(path),
          cacheTokenPaths: [path],
        ).toHints(),
      ),
    );
    final loader = buildLoader(registry: registry);

    final result = await loader.load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    );

    final messages = result.messages;
    // user(hello) + assistant(tool_use w/ no id) + assistant(text) — the two
    // consecutive assistant rows coalesce into one.
    expect(messages, isNotEmpty);
    expect(messages.first.role, AiRole.user);
    expect((messages.first.parts.single as AiTextPart).text, contains('hello'));
    expect(
      messages.where((m) => m.role == AiRole.assistant),
      isNotEmpty,
    );
  });

  test('load uses work-context FS from resolver, not home FS', () async {
    final workRoot = Directory.systemTemp.createTempSync('ai_history_work_');
    try {
      // Host context: a forced POSIX context over a `C:\…` workRoot would
      // produce mixed separators on Windows and fail to locate the fixture.
      final workFs = LocalFilesystem();
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

  test('throws StateError when capability missing for launch CLI', () async {
    final session = simpleSession();
    final loader = buildLoader(registry: CliToolRegistry());
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
          contains('AiHistoryCapability missing'),
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

  test('built-in registry exposes Claude AiHistoryCapability', () {
    final cap = CliToolRegistry.builtIn().capability<AiHistoryCapability>(
      CliTool.claude,
    );
    expect(cap, isNotNull);
    expect(cap!.adapter, isA<ClaudeAiTranscriptAdapter>());
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
    final loader = buildLoader(locator: locator);

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

  test('load calls toolResultEnricher once between parse and inflate', () async {
    // Seed a transcript whose tool result carries the truncation sentinel so
    // the loader's enricher guard fires (the tailer parses the real file now).
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final session = simpleSession();
    final toolRoot = layout.sessionRuntimeToolDir(
      'ws-1',
      session.sessionId,
      'claude',
    );
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final path = p.join(projects, '${session.sessionId}.jsonl');
    final fixture = await File(
      'test/fixtures/session_history/claude/truncated_bash.jsonl',
    ).readAsBytes();
    await File(path).writeAsBytes(fixture);

    final enricher = _RecordingEnricher();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      lineAppend: appendClaudeJsonlEvent,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: const [
          AiTranscriptFragment(name: 't.jsonl', bytes: [1, 2, 3]),
        ],
        hints: AiHistoryWatchMeta(
          changeWatchRoot: p.dirname(path),
          cacheTokenPaths: [path],
        ).toHints(),
      ),
    );
    final loader = buildLoader(registry: registry);

    final result = await loader.load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    );

    expect(enricher.calls, 1);
    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'enriched');
  });

  test('unchanged reload returns cached enriched messages, not the raw tail',
      () async {
    // Seed a transcript carrying the truncation sentinel so the first load
    // enriches (storing the enriched list in _messages), then bump the cache
    // token while leaving bytes byte-identical so the second load hits the
    // tailer's unchanged branch and must hand back the enriched messages.
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final session = simpleSession();
    final toolRoot = layout.sessionRuntimeToolDir(
      'ws-1',
      session.sessionId,
      'claude',
    );
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final path = p.join(projects, '${session.sessionId}.jsonl');
    final fixture = await File(
      'test/fixtures/session_history/claude/truncated_bash.jsonl',
    ).readAsBytes();
    await File(path).writeAsBytes(fixture);

    final enricher = _RecordingEnricher();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      lineAppend: appendClaudeJsonlEvent,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: const [
          AiTranscriptFragment(name: 't.jsonl', bytes: [1, 2, 3]),
        ],
        hints: AiHistoryWatchMeta(
          changeWatchRoot: p.dirname(path),
          cacheTokenPaths: [path],
        ).toHints(),
      ),
    );
    final loader = buildLoader(registry: registry);
    final ctx = launchContextFor(session);

    mtimeToken = 'mtime-1';
    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(first.messages.single.id, 'enriched');

    mtimeToken = 'mtime-2';
    File(path).setLastModifiedSync(
      DateTime.now().add(const Duration(seconds: 2)),
    );
    final second = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(
      second.messages.single.id,
      'enriched',
      reason: 'unchanged reload must return cached enriched messages, not the raw tail',
    );
    expect(enricher.calls, 1, reason: 'unchanged reload must not re-enrich');
  });

  test('appended transcript lines surface on reload; unchanged reload reuses attachments',
      () async {
    mtimeToken = 'mtime-1';
    // Seed a transcript under the located toolRoot so locate finds it.
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final session = simpleSession();
    final toolRoot = layout.sessionRuntimeToolDir(
      'ws-1',
      session.sessionId,
      'claude',
    );
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, '${session.sessionId}.jsonl')).writeAsBytes(
      fixture,
    );

    final loader = buildLoader();
    final ctx = launchContextFor(session);
    await loader.load(session: session, memberId: '', launchContext: ctx);
    final meta = await loader.resolveWatchMeta(launchContext: ctx, memberId: '');
    final paths = meta?.cacheTokenPaths ?? const [];
    final path = paths.isEmpty ? null : paths.first;
    expect(path, isNotNull, reason: 'transcript must be located');

    final before = (await fs.readString(path!))!;
    await fs.writeString(
      path,
      '$before{"type":"user","message":{"role":"user","content":"appended"}}\n',
    );
    // Touch mtime so the loader token gate opens. With the injected resolver
    // the gate token is [mtimeToken]; the real file mtime drives the default
    // _defaultCacheToken in production.
    final f = File(path);
    f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));
    mtimeToken = 'mtime-2';

    final second = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(
      second.messages.any(
        (m) =>
            m.parts.any(
              (p) => p is AiTextPart && p.text.contains('appended'),
            ),
      ),
      isTrue,
    );

    final third = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(
      identical(second.subagentAttachments, third.subagentAttachments),
      isTrue,
      reason: 'unchanged reload must reuse the attachment map',
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
  _CapturingLocator({
    required this.onLocate,
    CliToolRegistry? registry,
  }) : super(registry: registry ?? CliToolRegistry.builtIn());

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

class _RecordingEnricher implements ToolResultEnricher {
  var calls = 0;

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async {
    calls++;
    return [
      AiMessage(
        id: 'enriched',
        role: AiRole.user,
        parts: [AiTextPart(text: 'enriched')],
      ),
    ];
  }
}

class _EchoAdapter implements AiTranscriptAdapter {
  @override
  String get id => 'echo';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    return [
      AiMessage(
        id: 'parsed',
        role: AiRole.user,
        parts: [AiTextPart(text: 'parsed')],
      ),
    ];
  }
}
