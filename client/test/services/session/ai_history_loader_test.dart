import 'dart:convert';
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
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/tool_output_backfill_enricher.dart';
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
    bool useCapabilityToken = false,
  }) {
    final resolvedRegistry = registry ?? CliToolRegistry.builtIn();
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext:
          resolveWorkContext ?? ((_, {String? memberId}) async => fixedRoots()),
      registry: resolvedRegistry,
      locator: locator ?? AiHistoryLocator(registry: resolvedRegistry),
      resolveCacheToken: useCapabilityToken ? null : (_) async => mtimeToken,
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

  test('annotates tool call categories after parse (built-in resolver)', () async {
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final sessionId = 'sess-cat';
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
    expect(result.cli, CliTool.claude);
    final parts = [
      for (final m in result.messages) ...m.parts.whereType<AiToolCallPart>(),
    ];
    expect(parts, isNotEmpty);
    // fixture 只有 Bash(basic.jsonl 仅含一条 tool_use):
    expect(parts.single.category, AiToolCallCategory.command);
  });

  test('Cursor transcript parses via the capability adapter', () async {
    // Cursor rows use a top-level `role` field (not claude's `type`), wrap
    // user text in <user_query>, and omit tool_use ids. The loader parses them
    // through the capability's adapter — not a claude-compatible dialect.
    final session = simpleSession().copyWith(cli: CliTool.cursor);
    final fixture = await File(
      'test/fixtures/session_history/cursor/agent_transcript_no_tool_id.jsonl',
    ).readAsBytes();

    final registry = fakeAiHistoryRegistry(
      cli: CliTool.cursor,
      adapter: const CursorAiTranscriptAdapter(),
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'cursor',
        fragments: [AiTranscriptFragment(name: 't.jsonl', bytes: fixture)],
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

  test('capability liveCacheToken gates reloads when unchanged', () async {
    // Simulates an OpenCode-style store: the capability owns the fingerprint
    // (the default pinned-transcript probe misses), so an unchanged token
    // must skip locate + parse + inflate entirely.
    var token = 'oc-1';
    var locateCalls = 0;
    final session = simpleSession(id: 'sess-o').copyWith(cli: CliTool.opencode);
    final ctx = launchContextFor(session);
    final locator = _CountingLocator(() async {
      locateCalls++;
      return AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: const [
          AiTranscriptFragment(name: 'm.json', bytes: [1, 2, 3]),
        ],
      );
    });
    final loader = buildLoader(
      locator: locator,
      useCapabilityToken: true,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.opencode,
        adapter: _HolderAdapter(() => [
          AiMessage(
            id: 'm1',
            role: AiRole.user,
            parts: const [AiTextPart(text: 'hi')],
          ),
        ]),
        locate: (_) => locator.locate(
          ctx: SessionHistoryContext(
            fs: LocalFilesystem(),
            taskId: 't',
            env: const {},
            transcriptRoots: const [],
            bucket: '',
          ),
          cli: CliTool.opencode,
        ),
        liveCacheToken: (_) async => token,
      ),
    );

    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(first.messages, isNotEmpty);
    expect(locateCalls, 1);

    // Unchanged store token → cache hit, no locate.
    final second = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(identical(second.messages, first.messages), isTrue);
    expect(locateCalls, 1);

    // Store moved (e.g. a running sub-agent appended) → reload.
    token = 'oc-2';
    final third = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(locateCalls, 2);
    expect(identical(third.messages, first.messages), isFalse);
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
    // The adapter emits a tool result carrying the truncation sentinel, so the
    // loader's enricher guard fires; the enricher output is what is returned.
    final enricher = _RecordingEnricher();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: const [
          AiTranscriptFragment(name: 't.jsonl', bytes: [1, 2, 3]),
        ],
      ),
    );
    final loader = buildLoader(registry: registry);

    final result = await loader.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchContextFor(simpleSession()),
    );

    expect(enricher.calls, 1);
    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'enriched');
  });

  test('opencode truncation marker triggers the gate and backfills from hint file',
      () async {
    // The opencode placeholder carries `...N bytes truncated...`, which the
    // loader guard must also detect (not just the Claude sentinel), so the
    // backfill enricher runs and replaces the placeholder with the file body.
    final hintPath = p.join(base.path, 'tool-output', 'tool_abc');
    await Directory(p.dirname(hintPath)).create(recursive: true);
    await File(hintPath).writeAsString('full webfetch output\n第二行');
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.opencode,
      adapter: const _OpencodeMarkerAdapter(),
      toolResultEnricher: const OpencodeToolOutputBackfillEnricher(),
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'opencode',
        fragments: [AiTranscriptFragment(name: hintPath, bytes: const [1])],
      ),
    );
    final loader = buildLoader(registry: registry);

    final result = await loader.load(
      session: simpleSession().copyWith(cli: CliTool.opencode),
      memberId: '',
      launchContext: launchContextFor(simpleSession().copyWith(cli: CliTool.opencode)),
    );
    final part = result.messages.single.parts.single as AiToolCallPart;

    expect(part.result, 'full webfetch output\n第二行');
    expect(part.status, AiToolCallStatus.complete);
  });

  test('filesystem toolResultEnricher runs on caller isolate for large bundles',
      () async {
    // Bundles >= _isolateParseMinBytes parse on a worker isolate where ctx is
    // unavailable; filesystem-backed enrichers must still run on the caller
    // isolate with a non-null ctx instead of being skipped.
    final enricher = _RecordingFsEnricher();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [
          AiTranscriptFragment(
            name: 'big.jsonl',
            bytes: List.filled(300 * 1024, 0x20),
          ),
        ],
      ),
    );
    final loader = buildLoader(registry: registry);

    final result = await loader.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchContextFor(simpleSession()),
    );

    expect(enricher.calls, 1);
    expect(enricher.sawCallerCtx, isTrue);
    expect(result.messages.single.id, 'enriched');
  });

  test('unchanged reload returns cached enriched messages, not the raw tail',
      () async {
    // The adapter emits a tool result carrying the truncation sentinel so the
    // first load enriches (storing the enriched list in _messages). With the
    // same cache token, the second load hits the loader's token cache and must
    // hand back the cached enriched messages without re-parsing/re-enriching.
    mtimeToken = 'mtime-1';
    final session = simpleSession();
    final enricher = _RecordingEnricher();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: const [
          AiTranscriptFragment(name: 't.jsonl', bytes: [1, 2, 3]),
        ],
      ),
    );
    final loader = buildLoader(registry: registry);
    final ctx = launchContextFor(session);

    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(first.messages.single.id, 'enriched');

    // Same token → cache hit; no re-parse, no re-enrich.
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

  test('incremental load reuses message instances across appends', () async {
    mtimeToken = 'mtime-1';
    final session = simpleSession();
    final ctx = launchContextFor(session);
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final toolRoot = layout.sessionRuntimeToolDir(
      'ws-1',
      session.sessionId,
      'claude',
    );
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final transcriptPath = p.join(projects, '${session.sessionId}.jsonl');

    String line(String type, String id, String text) =>
        '{"type":"$type","uuid":"$id","message":{"id":"$id","content":"$text"},'
        '"timestamp":"2026-08-10T00:00:00Z"}';

    await File(transcriptPath).writeAsString(
      '${line('user', 'u1', 'hello')}\n',
    );
    final loader = buildLoader();
    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(first.messages, hasLength(1));

    // 追加流式分片 + 元数据行
    await File(transcriptPath).writeAsString(
      '${line('assistant', 'a1', 'part1 ')}\n'
      '${line('assistant', 'a1', 'part2')}\n'
      '{"type":"last-prompt","lastPrompt":"x"}\n',
      mode: FileMode.append,
    );
    // Touch the cache token so the loader gate opens and the incremental tail
    // refresh runs (a closed gate would return the cached list untouched).
    mtimeToken = 'mtime-2';
    final second = await loader.load(
      session: session,
      memberId: '',
      launchContext: ctx,
    );
    expect(identical(second.messages, first.messages), isFalse,
        reason: '增量 tail 原地变异 state 列表,必须返回新 List 实例,'
            '否则 seat 的 identical 判定会把新内容当成没变而跳过渲染');
    expect(identical(second.messages[0], first.messages[0]), isTrue,
        reason: '未变化消息保持实例身份');
    expect(second.messages, hasLength(2));
    expect(
      (second.messages[1].parts.single as AiTextPart).text,
      'part1 part2',
    );
  });

  test(
    'running subagent side transcript growth re-inflates attachments while parent mtime is frozen',
    () async {
      mtimeToken = 'mtime-1';
      // Parent transcript with an `agent` tool_use but no tool_result yet
      // (the sub-agent is still running — the parent jsonl stays frozen).
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
      final session = simpleSession();
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        session.sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final parentPath = p.join(projects, '${session.sessionId}.jsonl');
      await File(parentPath).writeAsString(_agentToolUseJsonl());

      final subagentsDir = p.join(projects, session.sessionId, 'subagents');
      await Directory(subagentsDir).create(recursive: true);
      await File(
        p.join(subagentsDir, 'agent-abc.meta.json'),
      ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 1));

      final loader = buildLoader();
      final ctx = launchContextFor(session);
      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final firstAttachment = first.subagentAttachments['toolu_agent'];
      expect(firstAttachment, isNotNull);
      expect(firstAttachment!.source, AiSubagentAttachmentSource.sideTranscript);
      expect(firstAttachment.messages, hasLength(1));

      // The running sub-agent appends its own transcript; the parent jsonl
      // (and thus the cache token) does not move. The loader must re-inflate
      // from the cached messages without re-parsing the parent.
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 2));
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        identical(second.messages, first.messages),
        isTrue,
        reason: 'side-only change must reuse the cached parent parse',
      );
      final secondAttachment = second.subagentAttachments['toolu_agent']!;
      expect(secondAttachment.messages, hasLength(2));
      expect(
        (secondAttachment.messages.last.parts.single as AiTextPart).text,
        'progress 1',
      );

      // Side data stable again → same attachment map instance, no re-inflate.
      final third = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        identical(third.subagentAttachments, second.subagentAttachments),
        isTrue,
        reason: 'unchanged side data must reuse the attachment map',
      );
    },
  );
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

class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this.messages);

  final List<AiMessage> Function() messages;

  @override
  String get id => 'opencode';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(messages());
}

class _RecordingEnricher implements ToolResultEnricher {
  var calls = 0;

  @override
  bool get requiresFilesystem => false;

  @override
  bool matchesTruncationMarker(String result) =>
      result.contains('tool output truncated');

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
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

class _RecordingFsEnricher implements ToolResultEnricher {
  var calls = 0;
  var sawCallerCtx = false;

  @override
  bool get requiresFilesystem => true;

  @override
  bool matchesTruncationMarker(String result) =>
      result.contains('tool output truncated');

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
  }) async {
    calls++;
    sawCallerCtx = ctx != null;
    return [
      AiMessage(
        id: 'enriched',
        role: AiRole.user,
        parts: [AiTextPart(text: 'enriched')],
      ),
    ];
  }
}

class _OpencodeMarkerAdapter implements AiTranscriptAdapter {
  const _OpencodeMarkerAdapter();

  @override
  String get id => 'opencode';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    // Carries the opencode core-truncation placeholder; the hint path is
    // passed through the fragment name so the class stays isolate-sendable.
    final hintPath = bundle.fragments.first.name;
    return [
      AiMessage(
        id: 'parsed',
        role: AiRole.user,
        parts: [
          AiToolCallPart(
            toolCallId: 'call_0',
            toolName: 'webfetch',
            result: 'preview\n\n...120935 bytes truncated...\n\n'
                'The tool call succeeded but the output was truncated. '
                'Full output saved to:\n$hintPath\n'
                'Use Grep to search the full content or Read with offset/limit '
                'to view specific sections.',
            status: AiToolCallStatus.complete,
          ),
        ],
      ),
    ];
  }
}

class _EchoAdapter implements AiTranscriptAdapter {
  @override
  String get id => 'echo';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    // Carries the truncation sentinel so the loader's enricher guard fires.
    return [
      AiMessage(
        id: 'parsed',
        role: AiRole.user,
        parts: [
          AiToolCallPart(
            toolCallId: 'call_0',
            toolName: 'Bash',
            result: 'tool output truncated',
            status: AiToolCallStatus.complete,
          ),
        ],
      ),
    ];
  }
}

String _agentToolUseJsonl() {
  return [
    jsonEncode({
      'type': 'user',
      'message': {'role': 'user', 'content': 'hello'},
      'uuid': 'u-1',
      'timestamp': '2026-07-10T10:00:00.000Z',
    }),
    jsonEncode({
      'type': 'assistant',
      'message': {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_agent',
            'name': 'Agent',
            'input': {'description': 'explore'},
          },
        ],
      },
      'uuid': 'a-1',
      'timestamp': '2026-07-10T10:00:01.000Z',
    }),
  ].join('\n');
}

/// Claude side-transcript lines: assistant progress rows only (as a live
/// sub-agent appends them).
String _sideTranscriptJsonl({required int lines}) {
  // Alternate roles so adjacent rows never coalesce into one message; a live
  // sub-agent's transcript interleaves assistant output and user tool results.
  final roles = ['assistant', 'user'];
  return [
    for (var i = 0; i < lines; i++)
      jsonEncode({
        'type': roles[i % 2],
        'message': {
          'role': roles[i % 2],
          'content': [
            {'type': 'text', 'text': 'progress $i'},
          ],
        },
        'uuid': 's-$i',
        'timestamp': '2026-07-10T10:00:0${i + 2}.000Z',
      }),
  ].join('\n');
}
