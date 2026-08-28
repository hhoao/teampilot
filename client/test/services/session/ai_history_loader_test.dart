import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_side_resolver.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/terminal_tool_result_enricher.dart';
import 'package:teampilot/services/ai_history/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/tool_output_backfill_enricher.dart';
import 'package:teampilot/services/cli/opencode/capabilities/sqlite_worker_pool.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/tasks/cli_task_board.dart';
import 'package:teampilot/services/session/ai_history_load_result.dart';
import 'package:teampilot/services/session/ai_history_load_timings.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_page.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/chat_transcript_find_controller.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/session/session_history_pagination.dart';
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
    AiHistoryLoadTimings? timings,
  }) {
    final resolvedRegistry = registry ?? CliToolRegistry.builtIn();
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext:
          resolveWorkContext ?? ((_, {String? memberId}) async => fixedRoots()),
      registry: resolvedRegistry,
      locator: locator ?? AiHistoryLocator(registry: resolvedRegistry),
      resolveCacheToken: useCapabilityToken ? null : (_) async => mtimeToken,
      timings: timings,
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

  tearDown(() async {
    await OpencodeSqliteWorkerPool.instance.disposeAllAndWait();
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
      await loader.fullIndex(sessionId: session.sessionId, memberId: '');
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
    expect(enricher.lastSourceToken, mtimeToken);
    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'enriched');
  });

  test('invalidate drops the tool-result index for the session', () async {
    var batches = 0;
    final enricher = ClaudeCompatibleToolResultEnricher(
      decodeLines: (lines) {
        batches++;
        return [
          for (final line in lines)
            tryDecodeJsonlLine(line),
        ];
      },
    );
    const jsonl =
        '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_0","type":"tool_result","content":"tool output truncated","is_error":false}]},"toolUseResult":{"stdout":"pwd","stderr":"","exitCode":0}}\n';
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [
          AiTranscriptFragment(name: 't.jsonl', bytes: utf8.encode(jsonl)),
        ],
      ),
    );
    final loader = buildLoader(registry: registry);
    final session = simpleSession();
    final ctx = launchContextFor(session);

    await loader.load(session: session, memberId: '', launchContext: ctx);
    expect(batches, 1);

    loader.invalidate(sessionId: session.sessionId, memberId: '');
    await loader.load(session: session, memberId: '', launchContext: ctx);
    expect(batches, 2);
  });

  test('records load phase timings when enabled', () async {
    final timings = AiHistoryLoadTimings();
    final enricher = _RecordingEnricher();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: _EchoAdapter(),
      toolResultEnricher: enricher,
      locate: (_) async => const AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [
          AiTranscriptFragment(name: 't.jsonl', bytes: [1, 2, 3]),
        ],
      ),
    );
    final loader = buildLoader(registry: registry, timings: timings);
    await loader.load(
      session: simpleSession(),
      memberId: '',
      launchContext: launchContextFor(simpleSession()),
    );

    expect(timings.order, contains(AiHistoryLoadPhase.locate));
    expect(timings.order, contains(AiHistoryLoadPhase.parse));
    expect(timings.order, contains(AiHistoryLoadPhase.enrich));
    expect(timings.order, contains(AiHistoryLoadPhase.firstPublish));
    expect(timings.sideTranscriptReads, 0);
    expect(
      timings.order.indexOf(AiHistoryLoadPhase.locate),
      lessThan(timings.order.indexOf(AiHistoryLoadPhase.firstPublish)),
    );
  });

  test('cursor missing shell result triggers the gate and backfills from terminals',
      () async {
    // The cursor Shell part has no result at all (not a truncation marker) —
    // the loader guard must still fire so the terminal enricher backfills
    // stdout from the terminals dir. Regression for the dead-path bug where
    // only String+marker results opened the gate.
    final fixture = await File(
      'test/fixtures/session_history/cursor/projects/home-me-proj/'
      'agent-transcripts/chat-shell-missing-result/chat-shell-missing-result.jsonl',
    ).readAsBytes();
    final terminal = await File(
      'test/fixtures/session_history/cursor/projects/home-me-proj/'
      'terminals/shell-pwd.txt',
    ).readAsString();

    final rootPath = p.join(
      base.path,
      'proj',
      'agent-transcripts',
      'chat',
      'chat.jsonl',
    );
    await Directory(p.dirname(rootPath)).create(recursive: true);
    await Directory(p.join(base.path, 'proj', 'terminals')).create(
      recursive: true,
    );
    await File(
      p.join(base.path, 'proj', 'terminals', 'shell-pwd.txt'),
    ).writeAsString(terminal);

    final registry = fakeAiHistoryRegistry(
      cli: CliTool.cursor,
      adapter: const CursorAiTranscriptAdapter(),
      toolResultEnricher: const CursorTerminalToolResultEnricher(
        shellResolver: ConfigurableAiShellToolTargetResolver(
          toolNames: {
            'bash', 'shell', 'shell_command', 'exec_command',
            'run_shell_command', 'run_terminal_cmd', 'execute',
          },
        ),
      ),
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'cursor',
        fragments: [AiTranscriptFragment(name: 'chat.jsonl', bytes: fixture)],
        hints: AiHistoryWatchMeta(
          changeWatchRoot: p.join(base.path, 'proj'),
          cacheTokenPaths: [rootPath],
        ).toHints(),
      ),
    );
    final loader = buildLoader(registry: registry);

    final result = await loader.load(
      session: simpleSession().copyWith(cli: CliTool.cursor),
      memberId: '',
      launchContext: launchContextFor(
        simpleSession().copyWith(cli: CliTool.cursor),
      ),
    );

    final part = result.messages
        .expand((m) => m.parts)
        .whereType<AiToolCallPart>()
        .single;
    expect(part.toolName, 'Shell');
    expect(part.result, '/home/hhoa/proj');
    expect(part.status, AiToolCallStatus.complete);
    expect(part.isError, isFalse);
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
    final indexed = await loader.fullIndex(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(indexed, isNotNull);
    expect(indexed!.messages, hasLength(1));

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
    expect(identical(second.messages, indexed.messages), isFalse,
        reason: '增量 tail 原地变异 state 列表,必须返回新 List 实例,'
            '否则 seat 的 identical 判定会把新内容当成没变而跳过渲染');
    expect(identical(second.messages[0], indexed.messages[0]), isTrue,
        reason: '未变化消息保持实例身份');
    expect(second.messages, hasLength(2));
    expect(
      (second.messages[1].parts.single as AiTextPart).text,
      'part1 part2',
    );
  });

  group('incremental subagent attachment freshness', () {
    test(
      'appended agent call after first load is lazy-loadable (tail path)',
      () async {
        mtimeToken = 'mtime-1';
        final session = simpleSession();
        final ctx = launchContextFor(session);
        final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
          '/work/project',
        );
        final toolRoot = layout.sessionRuntimeToolDir(
          'ws-1',
          session.sessionId,
          'claude',
        );
        final projects = p.join(toolRoot, 'projects', bucket);
        await Directory(projects).create(recursive: true);
        final parentPath = p.join(projects, '${session.sessionId}.jsonl');
        await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

        final subagentsDir = p.join(projects, session.sessionId, 'subagents');
        await Directory(subagentsDir).create(recursive: true);
        await File(
          p.join(subagentsDir, 'agent-abc.meta.json'),
        ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
        await File(
          p.join(subagentsDir, 'agent-abc.jsonl'),
        ).writeAsString(_sideTranscriptJsonl(lines: 1));

        final loader = buildLoader();
        final first = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        expect(first.subagentAttachments, isEmpty);
        await loader.fullIndex(sessionId: session.sessionId, memberId: '');

        // CLI 流式追加:父 transcript 新出现一条 assistant 消息,内含第二个
        // Agent 调用。增量 tail 只追加事件,不重跑全量 parse。
        await File(parentPath).writeAsString(
          '${jsonEncode({
            'type': 'assistant',
            'message': {
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'toolu_agent2',
                  'name': 'Agent',
                  'input': {'description': 'explore 2'},
                },
              ],
            },
            'uuid': 'a-2',
            'timestamp': '2026-07-10T10:00:02.000Z',
          })}\n',
          mode: FileMode.append,
        );
        mtimeToken = 'mtime-2';
        final second = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );

        expect(second.subagentAttachments, isEmpty);
        final seat = await _resolveSeatForLoader(
          session,
          fs: fs,
          layout: layout,
        );
        final loaded = await loader.loadSubagentAttachment(
          cacheKey: AiHistoryLoader.cacheKeyFor(session.sessionId, ''),
          toolCallId: 'toolu_agent2',
          ctx: seat.ctx,
          capability: seat.cap,
          messages: second.messages,
          cli: seat.cli,
        );
        expect(loaded, isNotNull);
        expect(loaded!.toolCallId, 'toolu_agent2');
      },
    );

    test(
      'incremental tick without task-call changes reuses the attachment map instance',
      () async {
        mtimeToken = 'mtime-1';
        final session = simpleSession();
        final ctx = launchContextFor(session);
        final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
          '/work/project',
        );
        final toolRoot = layout.sessionRuntimeToolDir(
          'ws-1',
          session.sessionId,
          'claude',
        );
        final projects = p.join(toolRoot, 'projects', bucket);
        await Directory(projects).create(recursive: true);
        final parentPath = p.join(projects, '${session.sessionId}.jsonl');
        await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

        final subagentsDir = p.join(projects, session.sessionId, 'subagents');
        await Directory(subagentsDir).create(recursive: true);
        await File(
          p.join(subagentsDir, 'agent-abc.meta.json'),
        ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
        await File(
          p.join(subagentsDir, 'agent-abc.jsonl'),
        ).writeAsString(_sideTranscriptJsonl(lines: 1));

        final loader = buildLoader();
        final first = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        expect(first.subagentAttachments, isEmpty);
        final seat = await _resolveSeatForLoader(
          session,
          fs: fs,
          layout: layout,
        );
        final cacheKey = AiHistoryLoader.cacheKeyFor(session.sessionId, '');
        await loader.loadSubagentAttachment(
          cacheKey: cacheKey,
          toolCallId: 'toolu_agent',
          ctx: seat.ctx,
          capability: seat.cap,
          messages: first.messages,
          cli: seat.cli,
        );
        final warmed = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        expect(warmed.subagentAttachments, isNotEmpty);
        await loader.fullIndex(sessionId: session.sessionId, memberId: '');

        // 追加一条纯文本 user 行:增量路径触发,但任务调用集合没有变化。
        await File(parentPath).writeAsString(
          '${jsonEncode({
            'type': 'user',
            'message': {'role': 'user', 'content': 'follow-up'},
            'uuid': 'u-2',
            'timestamp': '2026-07-10T10:00:03.000Z',
          })}\n',
          mode: FileMode.append,
        );
        mtimeToken = 'mtime-2';
        final second = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );

        expect(
          identical(second.subagentAttachments, warmed.subagentAttachments),
          isTrue,
          reason: '任务调用集合未变时增量 tick 必须复用同一附件 map 实例,'
              '否则 seat 的 identical / 内容比较每次都要重建(性能回归)',
        );
      },
    );

    test(
      'completed agent call re-resolves its attachment on demand (result lands)',
      () async {
        mtimeToken = 'mtime-1';
        final session = simpleSession();
        final ctx = launchContextFor(session);
        final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
          '/work/project',
        );
        final toolRoot = layout.sessionRuntimeToolDir(
          'ws-1',
          session.sessionId,
          'claude',
        );
        final projects = p.join(toolRoot, 'projects', bucket);
        await Directory(projects).create(recursive: true);
        final parentPath = p.join(projects, '${session.sessionId}.jsonl');
        // 运行中的 agent:父 transcript 只有 tool_use,没有 side 数据。
        await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

        final loader = buildLoader();
        final first = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );
        expect(first.subagentAttachments, isEmpty);
        final seat = await _resolveSeatForLoader(
          session,
          fs: fs,
          layout: layout,
        );
        final cacheKey = AiHistoryLoader.cacheKeyFor(session.sessionId, '');
        final degraded = await loader.loadSubagentAttachment(
          cacheKey: cacheKey,
          toolCallId: 'toolu_agent',
          ctx: seat.ctx,
          capability: seat.cap,
          messages: first.messages,
          cli: seat.cli,
        );
        expect(degraded, isNotNull);
        expect(
          degraded!.source,
          AiSubagentAttachmentSource.toolResult,
          reason: '没有 side 数据时首次解析退化为 toolResult 占位',
        );
        await loader.fullIndex(sessionId: session.sessionId, memberId: '');

        // 子 agent 完成:side transcript 出现 + 父 transcript 追加
        // tool_result(part 从 incomplete 变成 complete 且带 result)。
        final subagentsDir = p.join(projects, session.sessionId, 'subagents');
        await Directory(subagentsDir).create(recursive: true);
        await File(
          p.join(subagentsDir, 'agent-abc.meta.json'),
        ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
        await File(
          p.join(subagentsDir, 'agent-abc.jsonl'),
        ).writeAsString(_sideTranscriptJsonl(lines: 1));
        await File(parentPath).writeAsString(
          '${jsonEncode({
            'type': 'assistant',
            'message': {
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': 'toolu_agent',
                  'content': 'done',
                },
              ],
            },
            'uuid': 'r-1',
            'timestamp': '2026-07-10T10:00:02.000Z',
          })}\n',
          mode: FileMode.append,
        );
        mtimeToken = 'mtime-2';
        final second = await loader.load(
          session: session,
          memberId: '',
          launchContext: ctx,
        );

        final reResolved = await loader.loadSubagentAttachment(
          cacheKey: cacheKey,
          toolCallId: 'toolu_agent',
          ctx: seat.ctx,
          capability: seat.cap,
          messages: second.messages,
          cli: seat.cli,
        );
        expect(reResolved, isNotNull);
        expect(
          reResolved!.source,
          AiSubagentAttachmentSource.sideTranscript,
          reason: '调用完成(part 状态/结果变化)后必须重新解析,不能停留在'
              '退化占位——否则预览永远看不到真实的子会话内容',
        );
        expect(reResolved.messages, hasLength(1));
        expect(
          (reResolved.messages.single.parts.single as AiTextPart).text,
          'progress 0',
        );
      },
    );
  });

  group('loads one subagent attachment on demand', () {
    test('initial load makes zero side-resolver calls', () async {
      mtimeToken = 'mtime-1';
      final session = simpleSession();
      final ctx = launchContextFor(session);
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        '/work/project',
      );
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        session.sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final parentPath = p.join(projects, '${session.sessionId}.jsonl');
      await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

      final subagentsDir = p.join(projects, session.sessionId, 'subagents');
      await Directory(subagentsDir).create(recursive: true);
      await File(
        p.join(subagentsDir, 'agent-abc.meta.json'),
      ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 1));

      final resolver = _CountingSubagentSideResolver();
      final builtInCap =
          CliToolRegistry.builtIn().capability<AiHistoryCapability>(
            CliTool.claude,
          )!;
      final registry = fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: const ClaudeAiTranscriptAdapter(),
        locate: builtInCap.locate,
        subagentSideResolver: resolver,
        subagentToolNames: builtInCap.subagentToolNames,
      );
      final loader = buildLoader(registry: registry);
      final result = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );

      expect(result.subagentAttachments, isEmpty);
      expect(resolver.resolveCount, 0);
    });

    test('two concurrent requests for one id share one resolver call', () async {
      mtimeToken = 'mtime-1';
      final session = simpleSession();
      final ctx = launchContextFor(session);
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        '/work/project',
      );
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        session.sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final parentPath = p.join(projects, '${session.sessionId}.jsonl');
      await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

      final subagentsDir = p.join(projects, session.sessionId, 'subagents');
      await Directory(subagentsDir).create(recursive: true);
      await File(
        p.join(subagentsDir, 'agent-abc.meta.json'),
      ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 1));

      final gate = Completer<void>();
      final resolver = _CountingSubagentSideResolver(
        onResolve: () async {
          await gate.future;
          return SubagentSideResolveResult(
            messages: [
              AiMessage(
                id: 'side-1',
                role: AiRole.assistant,
                parts: const [AiTextPart(text: 'side')],
              ),
            ],
            handle: const SubagentFileHandle('/side.jsonl'),
          );
        },
      );
      final builtInCap =
          CliToolRegistry.builtIn().capability<AiHistoryCapability>(
            CliTool.claude,
          )!;
      final registry = fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: const ClaudeAiTranscriptAdapter(),
        locate: builtInCap.locate,
        subagentSideResolver: resolver,
        subagentToolNames: builtInCap.subagentToolNames,
      );
      final loader = buildLoader(registry: registry);
      final loaded = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final seat = await _resolveSeatForLoader(
        session,
        fs: fs,
        layout: layout,
        registry: registry,
      );
      final cacheKey = AiHistoryLoader.cacheKeyFor(session.sessionId, '');
      final args = (
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: loaded.messages,
        cli: seat.cli,
      );
      expect(resolver.resolveCount, 0);
      final a = loader.loadSubagentAttachment(
        cacheKey: args.cacheKey,
        toolCallId: args.toolCallId,
        ctx: args.ctx,
        capability: args.capability,
        messages: args.messages,
        cli: args.cli,
      );
      final b = loader.loadSubagentAttachment(
        cacheKey: args.cacheKey,
        toolCallId: args.toolCallId,
        ctx: args.ctx,
        capability: args.capability,
        messages: args.messages,
        cli: args.cli,
      );
      await Future<void>.delayed(Duration.zero);
      expect(resolver.resolveCount, 1);
      gate.complete();
      final results = await Future.wait([a, b]);
      expect(results[0], isNotNull);
      expect(identical(results[0], results[1]), isTrue);
      expect(resolver.resolveCount, 1);
    });

    test('successful request is cached', () async {
      mtimeToken = 'mtime-1';
      final session = simpleSession();
      final ctx = launchContextFor(session);
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        '/work/project',
      );
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        session.sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final parentPath = p.join(projects, '${session.sessionId}.jsonl');
      await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

      final subagentsDir = p.join(projects, session.sessionId, 'subagents');
      await Directory(subagentsDir).create(recursive: true);
      await File(
        p.join(subagentsDir, 'agent-abc.meta.json'),
      ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 1));

      final resolver = _CountingSubagentSideResolver();
      final builtInCap =
          CliToolRegistry.builtIn().capability<AiHistoryCapability>(
            CliTool.claude,
          )!;
      final registry = fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: const ClaudeAiTranscriptAdapter(),
        locate: builtInCap.locate,
        subagentSideResolver: resolver,
        subagentToolNames: builtInCap.subagentToolNames,
      );
      final loader = buildLoader(registry: registry);
      final loaded = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final seat = await _resolveSeatForLoader(
        session,
        fs: fs,
        layout: layout,
        registry: registry,
      );
      final cacheKey = AiHistoryLoader.cacheKeyFor(session.sessionId, '');
      final first = await loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: loaded.messages,
        cli: seat.cli,
      );
      final second = await loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: loaded.messages,
        cli: seat.cli,
      );
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
      expect(resolver.resolveCount, 1);
    });

    test('in-flight load dropped after side-token invalidation', () async {
      mtimeToken = 'mtime-1';
      final session = simpleSession();
      final ctx = launchContextFor(session);
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        '/work/project',
      );
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        session.sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final parentPath = p.join(projects, '${session.sessionId}.jsonl');
      await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

      final subagentsDir = p.join(projects, session.sessionId, 'subagents');
      await Directory(subagentsDir).create(recursive: true);
      await File(
        p.join(subagentsDir, 'agent-abc.meta.json'),
      ).writeAsString(jsonEncode({'toolUseId': 'toolu_agent'}));
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 1));

      final gate = Completer<void>();
      var fingerprint = 'fp-1';
      final delegate = const ClaudeCompatibleSideResolver();
      final resolver = _GatedSubagentSideResolver(
        gate: gate,
        fingerprintProvider: () => fingerprint,
        resolveResult: SubagentSideResolveResult(
          messages: [
            AiMessage(
              id: 'stale',
              role: AiRole.assistant,
              parts: const [AiTextPart(text: 'stale side')],
            ),
          ],
          handle: const SubagentFileHandle('/stale.jsonl'),
        ),
        delegate: delegate,
      );
      final builtInCap =
          CliToolRegistry.builtIn().capability<AiHistoryCapability>(
            CliTool.claude,
          )!;
      final registry = fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: const ClaudeAiTranscriptAdapter(),
        locate: builtInCap.locate,
        subagentSideResolver: resolver,
        subagentToolNames: builtInCap.subagentToolNames,
      );
      final loader = buildLoader(registry: registry);
      final loaded = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final seat = await _resolveSeatForLoader(
        session,
        fs: fs,
        layout: layout,
        registry: registry,
      );
      final cacheKey = AiHistoryLoader.cacheKeyFor(session.sessionId, '');

      final inFlight = loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: loaded.messages,
        cli: seat.cli,
      );
      await Future<void>.delayed(Duration.zero);
      expect(resolver.resolveCount, 1);

      fingerprint = 'fp-2';
      await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );

      gate.complete();
      final attachment = await inFlight;
      expect(attachment, isNull);

      final fresh = await loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: loaded.messages,
        cli: seat.cli,
      );
      expect(fresh, isNotNull);
      expect(
        (fresh!.messages.single.parts.single as AiTextPart).text,
        'progress 0',
      );
      expect(resolver.resolveCount, 2);
    });

    test('missing side transcript produces tool-result fallback', () async {
      mtimeToken = 'mtime-1';
      final session = simpleSession();
      final ctx = launchContextFor(session);
      final bucket = RuntimeLayout.workspaceBucketForPrimaryPath(
        '/work/project',
      );
      final toolRoot = layout.sessionRuntimeToolDir(
        'ws-1',
        session.sessionId,
        'claude',
      );
      final projects = p.join(toolRoot, 'projects', bucket);
      await Directory(projects).create(recursive: true);
      final parentPath = p.join(projects, '${session.sessionId}.jsonl');
      await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

      final resolver = _CountingSubagentSideResolver();
      final builtInCap =
          CliToolRegistry.builtIn().capability<AiHistoryCapability>(
            CliTool.claude,
          )!;
      final registry = fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: const ClaudeAiTranscriptAdapter(),
        locate: builtInCap.locate,
        subagentSideResolver: resolver,
        subagentToolNames: builtInCap.subagentToolNames,
      );
      final loader = buildLoader(registry: registry);
      final loaded = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final seat = await _resolveSeatForLoader(
        session,
        fs: fs,
        layout: layout,
        registry: registry,
      );
      final attachment = await loader.loadSubagentAttachment(
        cacheKey: AiHistoryLoader.cacheKeyFor(session.sessionId, ''),
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: loaded.messages,
        cli: seat.cli,
      );
      expect(attachment, isNotNull);
      expect(attachment!.source, AiSubagentAttachmentSource.toolResult);
      expect(resolver.resolveCount, 1);
    });
  });

  test(
    'running subagent side transcript growth re-resolves on demand while parent mtime is frozen',
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
      await File(parentPath).writeAsString('${_agentToolUseJsonl()}\n');

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
      expect(first.subagentAttachments, isEmpty);
      final fullAfterFirst = await loader.fullIndex(
        sessionId: session.sessionId,
        memberId: '',
      );
      expect(fullAfterFirst, isNotNull);
      final seat = await _resolveSeatForLoader(
        session,
        fs: fs,
        layout: layout,
      );
      final cacheKey = AiHistoryLoader.cacheKeyFor(session.sessionId, '');
      final firstAttachment = await loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: fullAfterFirst!.messages,
        cli: seat.cli,
      );
      expect(firstAttachment, isNotNull);
      expect(firstAttachment!.source, AiSubagentAttachmentSource.sideTranscript);
      expect(firstAttachment.messages, hasLength(1));

      // The running sub-agent appends its own transcript; the parent jsonl
      // (and thus the cache token) does not move. Side fingerprint move clears
      // the lazy cache; the next on-demand load picks up the growth.
      await File(
        p.join(subagentsDir, 'agent-abc.jsonl'),
      ).writeAsString(_sideTranscriptJsonl(lines: 2));
      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      expect(
        identical(second.messages, fullAfterFirst.messages),
        isTrue,
        reason: 'side-only change must reuse the cached parent parse',
      );
      expect(second.subagentAttachments, isEmpty);
      final secondAttachment = await loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: second.messages,
        cli: seat.cli,
      );
      expect(secondAttachment, isNotNull);
      expect(secondAttachment!.messages, hasLength(2));
      expect(
        (secondAttachment.messages.last.parts.single as AiTextPart).text,
        'progress 1',
      );

      // Side data stable again → cached attachment instance, no re-resolve.
      final third = await loader.load(
        session: session,
        memberId: '',
        launchContext: ctx,
      );
      final thirdAttachment = await loader.loadSubagentAttachment(
        cacheKey: cacheKey,
        toolCallId: 'toolu_agent',
        ctx: seat.ctx,
        capability: seat.cap,
        messages: third.messages,
        cli: seat.cli,
      );
      expect(
        identical(thirdAttachment, secondAttachment),
        isTrue,
        reason: 'unchanged side data must reuse the attachment instance',
      );
    },
  );

  test('publishes recent page before older history', () async {
    final all = _pagedHistoryMessages();
    final recent = all.sublist(all.length - kSessionHistoryInitialTurns);
    final older = all.sublist(0, all.length - kSessionHistoryInitialTurns);
    final parseGate = Completer<void>();
    final adapter = _GatedParseAdapter(all, parseGate);
    final reader = _FakePageReader(latest: recent, older: older);
    final session = simpleSession();
    final loader = buildLoader(
      locator: _CountingLocator(
        () async => const AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
        ),
      ),
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: adapter,
        pageReader: reader,
        locate: (_) async => const AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
        ),
      ),
    );

    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    );

    expect(first.messages, hasLength(kSessionHistoryInitialTurns));
    expect(first.messages.map((m) => m.id), recent.map((m) => m.id));
    expect(identical(first.messages.first, recent.first), isTrue);
    expect(first.hasOlder, isTrue);
    expect(first.cursor, isNotNull);
    expect(first.isComplete, isFalse);
    expect(parseGate.isCompleted, isFalse);
    expect(reader.latestCalls, 1);
    expect(reader.olderCalls, 0);

    final olderResult = await loader.loadOlder(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(olderResult, isNotNull);
    expect(olderResult!.messages, hasLength(older.length));
    expect(olderResult.messages.map((m) => m.id), older.map((m) => m.id));
    expect(identical(olderResult.messages[1], older[1]), isTrue);
    expect(parseGate.isCompleted, isFalse);
    expect(reader.olderCalls, 1);

    parseGate.complete();
    final full = await loader.fullIndex(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(full, isNotNull);
    expect(full!.isComplete, isTrue);
    expect(full.messages, hasLength(all.length));
    expect(full.messages.map((m) => m.id), all.map((m) => m.id));
    expect(adapter.parseCalls, greaterThan(0));

    final concatenated = [...olderResult.messages, ...first.messages];
    expect(concatenated.map((m) => m.id), full.messages.map((m) => m.id));

    final board = reduceCliTaskBoard(full.messages);
    expect(board.tasks.map((t) => t.subject), contains('old-task'));

    final finder = ChatTranscriptFindController(
      messagesProvider: () => full.messages,
    );
    addTearDown(finder.dispose);
    finder.search('msg-1');
    expect(finder.hits, isNotEmpty);
    expect(finder.hits.first.messageId, 'm-1');
  });

  test('loadOlder still prepends after background full index completes', () async {
    final all = _pagedHistoryMessages();
    final recent = all.sublist(all.length - kSessionHistoryInitialTurns);
    final older = all.sublist(0, all.length - kSessionHistoryInitialTurns);
    final adapter = _GatedParseAdapter(all, Completer<void>()..complete());
    final reader = _FakePageReader(latest: recent, older: older);
    final session = simpleSession();
    final loader = buildLoader(
      locator: _CountingLocator(
        () async => const AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
        ),
      ),
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: adapter,
        pageReader: reader,
        locate: (_) async => const AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
        ),
      ),
    );

    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: launchContextFor(session),
    );
    expect(first.hasOlder, isTrue);
    expect(first.isComplete, isFalse);

    final full = await loader.fullIndex(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(full, isNotNull);
    expect(full!.isComplete, isTrue);
    expect(full.messages.map((m) => m.id), all.map((m) => m.id));

    final olderResult = await loader.loadOlder(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(
      olderResult,
      isNotNull,
      reason: 'background full index must not drop the page cursor',
    );
    expect(olderResult!.messages.map((m) => m.id), older.map((m) => m.id));
    expect(
      [...olderResult.messages, ...first.messages].map((m) => m.id),
      full.messages.map((m) => m.id),
    );
  });

  test(
    'unchanged-token load after fullIndex returns the hydrated full index',
    () async {
      final all = _pagedHistoryMessages();
      final recent = all.sublist(all.length - kSessionHistoryInitialTurns);
      final older = all.sublist(0, all.length - kSessionHistoryInitialTurns);
      final adapter = _GatedParseAdapter(all, Completer<void>()..complete());
      final reader = _FakePageReader(latest: recent, older: older);
      final session = simpleSession();
      final loader = buildLoader(
        locator: _CountingLocator(
          () async => const AiTranscriptBundle(
            adapterId: 'claude',
            fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
          ),
        ),
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: adapter,
          pageReader: reader,
          locate: (_) async => const AiTranscriptBundle(
            adapterId: 'claude',
            fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
          ),
        ),
      );

      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchContextFor(session),
      );
      expect(first.messages.map((m) => m.id), recent.map((m) => m.id));
      expect(first.isComplete, isFalse);

      final full = await loader.fullIndex(
        sessionId: session.sessionId,
        memberId: '',
      );
      expect(full, isNotNull);
      expect(full!.messages.map((m) => m.id), all.map((m) => m.id));

      final cached = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchContextFor(session),
      );
      expect(
        cached.messages.map((m) => m.id),
        full.messages.map((m) => m.id),
        reason: 'token-cache load must not drop the hydrated full index',
      );
      expect(cached.isComplete, isTrue);
      expect(
        identical(cached.messages, full.messages),
        isTrue,
        reason: 'token-cache load must reuse the full-index list instance',
      );
    },
  );

  test('page reader null or throw uses the full adapter path', () async {
    final all = _pagedHistoryMessages();
    final adapter = _GatedParseAdapter(all, Completer<void>()..complete());
    final session = simpleSession();

    Future<AiHistoryLoadResult> loadWith(
      AiTranscriptPageReader? reader,
    ) {
      return buildLoader(
        locator: _CountingLocator(
          () async => const AiTranscriptBundle(
            adapterId: 'claude',
            fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
          ),
        ),
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: adapter,
          pageReader: reader,
          locate: (_) async => const AiTranscriptBundle(
            adapterId: 'claude',
            fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
          ),
        ),
      ).load(
        session: session,
        memberId: '',
        launchContext: launchContextFor(session),
      );
    }

    adapter.parseCalls = 0;
    final fromNull = await loadWith(_NullPageReader());
    expect(fromNull.isComplete, isTrue);
    expect(fromNull.messages, hasLength(all.length));
    expect(adapter.parseCalls, greaterThan(0));

    adapter.parseCalls = 0;
    final fromThrow = await loadWith(_ThrowingPageReader());
    expect(fromThrow.isComplete, isTrue);
    expect(fromThrow.messages, hasLength(all.length));
    expect(adapter.parseCalls, greaterThan(0));
  });

  test(
    'concatenated pages match background full parse for fixture families',
    () async {
      final families = await _loaderFixtureFamilies(
        layout: layout,
        sessionFor: simpleSession,
      );
      expect(families, isNotEmpty);
      for (final family in families) {
        mtimeToken = 'mtime-${family.label}';
        final loader = buildLoader();
        final first = await loader.load(
          session: family.session,
          memberId: '',
          launchContext: launchContextFor(family.session),
        );
        final concatenated = [...first.messages];
        var hasOlder = first.hasOlder;
        var guard = 0;
        while (hasOlder) {
          expect(guard++, lessThan(64), reason: family.label);
          final older = await loader.loadOlder(
            sessionId: family.session.sessionId,
            memberId: '',
          );
          if (older == null) break;
          concatenated.insertAll(0, older.messages);
          hasOlder = older.hasOlder;
        }
        final full = await loader.fullIndex(
          sessionId: family.session.sessionId,
          memberId: '',
        );
        expect(full, isNotNull, reason: family.label);
        expect(
          concatenated.map((m) => m.id),
          full!.messages.map((m) => m.id),
          reason: '${family.label} concatenated pages must equal full index ids',
        );
        expect(
          sameMessageListContent(concatenated, full.messages),
          isTrue,
          reason: '${family.label} concatenated pages must equal full index',
        );
      }
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
  String? lastSourceToken;

  @override
  bool get requiresFilesystem => false;

  @override
  bool matchesTruncationMarker(String result) =>
      result.contains('tool output truncated');

  @override
  bool needsEnrichment(AiToolCallPart part) =>
      defaultToolResultNeedsEnrichment(this, part);

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
    String? sourceToken,
  }) async {
    calls++;
    lastSourceToken = sourceToken;
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
  bool needsEnrichment(AiToolCallPart part) =>
      defaultToolResultNeedsEnrichment(this, part);

  @override
  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? rootTranscriptPath,
    required AiTranscriptBundle? bundle,
    String? sourceToken,
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

class _SeatResolve {
  const _SeatResolve({
    required this.ctx,
    required this.cap,
    required this.cli,
  });

  final SessionHistoryContext ctx;
  final AiHistoryCapability cap;
  final CliTool cli;
}

Future<_SeatResolve> _resolveSeatForLoader(
  AppSession session, {
  required LocalFilesystem fs,
  required RuntimeLayout layout,
  CliToolRegistry? registry,
}) async {
  final reg = registry ?? CliToolRegistry.builtIn();
  final builder = const SessionHistoryContextBuilder();
  final cli = session.cli ?? CliTool.claude;
  final cap = reg.capability<AiHistoryCapability>(cli);
  if (cap == null) {
    throw StateError('missing AiHistoryCapability for $cli');
  }
  final ctx = builder.build(
    fs: fs,
    layout: layout,
    appDataRoot: layout.teampilotRoot,
    session: session,
    memberId: '',
    cli: cli,
    workingDirectory: null,
    teamId: null,
  );
  return _SeatResolve(ctx: ctx, cap: cap, cli: cli);
}

class _GatedSubagentSideResolver implements SubagentSideResolver {
  _GatedSubagentSideResolver({
    required this.gate,
    required this.fingerprintProvider,
    required this.resolveResult,
    required this.delegate,
  });

  final Completer<void> gate;
  final String Function() fingerprintProvider;
  final SubagentSideResolveResult resolveResult;
  final SubagentSideResolver delegate;
  var resolveCount = 0;

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    resolveCount++;
    await gate.future;
    if (resolveCount == 1) return resolveResult;
    return delegate.resolve(
      part: part,
      ctx: ctx,
      parentHandle: parentHandle,
      rootTranscriptPath: rootTranscriptPath,
      toolCallAt: toolCallAt,
    );
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async =>
      fingerprintProvider();
}

class _CountingSubagentSideResolver implements SubagentSideResolver {
  _CountingSubagentSideResolver({this.onResolve});

  int resolveCount = 0;
  final Future<SubagentSideResolveResult?> Function()? onResolve;

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    resolveCount++;
    if (onResolve != null) return onResolve!();
    return null;
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async =>
      'fp-static';
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

List<AiMessage> _pagedHistoryMessages() => [
  for (var i = 0; i < 50; i++)
    AiMessage(
      id: 'm-$i',
      role: i == 0 ? AiRole.assistant : AiRole.user,
      parts: i == 0
          ? [
              AiToolCallPart(
                toolCallId: 'c-old',
                toolName: 'TaskCreate',
                args: {'subject': 'old-task'},
                result: {'taskId': 'task-old'},
                status: AiToolCallStatus.complete,
              ),
            ]
          : [AiTextPart(text: 'msg-$i')],
    ),
];

class _GatedParseAdapter implements AiTranscriptAdapter {
  _GatedParseAdapter(this._messages, this._gate);

  final List<AiMessage> _messages;
  final Completer<void> _gate;
  var parseCalls = 0;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    parseCalls++;
    await _gate.future;
    return List.of(_messages);
  }
}

class _FakePageReader implements AiTranscriptPageReader {
  _FakePageReader({required this.latest, required this.older});

  final List<AiMessage> latest;
  final List<AiMessage> older;
  var latestCalls = 0;
  var olderCalls = 0;

  @override
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  }) async {
    latestCalls++;
    return AiHistoryPage(
      messages: latest,
      hasOlder: older.isNotEmpty,
      nextCursor: older.isEmpty
          ? null
          : const AiHistoryCursor(
              sourceToken: 'page-token',
              offset: 0,
              lineHash: 1,
            ),
      sourceToken: 'page-token',
      rebuilt: false,
    );
  }

  @override
  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  }) async {
    olderCalls++;
    return AiHistoryPage(
      messages: older,
      hasOlder: false,
      nextCursor: null,
      sourceToken: 'page-token',
      rebuilt: false,
    );
  }
}

class _NullPageReader implements AiTranscriptPageReader {
  @override
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  }) async => null;

  @override
  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  }) async => null;
}

class _ThrowingPageReader implements AiTranscriptPageReader {
  @override
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  }) async => throw StateError('page reader boom');

  @override
  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  }) async => throw StateError('page reader boom');
}

typedef _LoaderFamily = ({String label, AppSession session});

Future<List<_LoaderFamily>> _loaderFixtureFamilies({
  required RuntimeLayout layout,
  required AppSession Function({String id}) sessionFor,
}) async {
  return [
    await _installPinnedJsonlFamily(
      layout: layout,
      sessionFor: sessionFor,
      cli: CliTool.claude,
      name: 'basic.jsonl',
    ),
    await _installPinnedJsonlFamily(
      layout: layout,
      sessionFor: sessionFor,
      cli: CliTool.claude,
      name: 'streamed_turn.jsonl',
    ),
    await _installPinnedJsonlFamily(
      layout: layout,
      sessionFor: sessionFor,
      cli: CliTool.claude,
      name: 'truncated_bash.jsonl',
    ),
    await _installPinnedJsonlFamily(
      layout: layout,
      sessionFor: sessionFor,
      cli: CliTool.flashskyai,
      name: 'basic.jsonl',
    ),
    await _installPinnedJsonlFamily(
      layout: layout,
      sessionFor: sessionFor,
      cli: CliTool.flashskyai,
      name: 'streamed_tools.jsonl',
    ),
    await _installPinnedJsonlFamily(
      layout: layout,
      sessionFor: sessionFor,
      cli: CliTool.flashskyai,
      name: 'edit_real.jsonl',
    ),
    await _installCodexFamily(
      layout: layout,
      sessionFor: sessionFor,
      name: 'reasoning_and_tools.jsonl',
      uuid: '11111111-1111-1111-1111-111111111111',
    ),
    await _installCodexFamily(
      layout: layout,
      sessionFor: sessionFor,
      name: 'custom_tool_call_dual_form.jsonl',
      uuid: '22222222-2222-2222-2222-222222222222',
    ),
    await _installCodexFamily(
      layout: layout,
      sessionFor: sessionFor,
      name: 'response_item_messages.jsonl',
      uuid: '33333333-3333-3333-3333-333333333333',
    ),
    await _installCursorFamily(
      layout: layout,
      sessionFor: sessionFor,
      chatId: 'chat-aaaa-bbbb-cccc-dddd',
    ),
    await _installCursorFamily(
      layout: layout,
      sessionFor: sessionFor,
      chatId: 'chat-strreplace-write',
    ),
    await _installCursorFamily(
      layout: layout,
      sessionFor: sessionFor,
      chatId: 'chat-shell-missing-result',
    ),
    await _installOpencodeFamily(
      layout: layout,
      sessionFor: sessionFor,
      label: 'opencode/storage',
      storageRoot: 'test/fixtures/session_history/opencode/storage',
      nativeId: 'ses_demo001',
    ),
    await _installOpencodeFamily(
      layout: layout,
      sessionFor: sessionFor,
      label: 'opencode/from_db_shape',
      storageRoot:
          'test/fixtures/session_history/opencode/from_db_shape/storage',
      nativeId: 'ses_dbdemo001',
    ),
  ];
}

String _sessionConfigDir(RuntimeLayout layout, CliTool cli, String sessionId) =>
    sessionConfigDirForTool(
      cli,
      layout,
      workspaceId: 'ws-1',
      sessionId: sessionId,
    );

Future<_LoaderFamily> _installPinnedJsonlFamily({
  required RuntimeLayout layout,
  required AppSession Function({String id}) sessionFor,
  required CliTool cli,
  required String name,
}) async {
  final label = '${cli.value}/$name';
  final sessionId = 'sess-${label.replaceAll('/', '-')}';
  final toolRoot = _sessionConfigDir(layout, cli, sessionId);
  final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
  final dest = p.join(toolRoot, 'projects', bucket, '$sessionId.jsonl');
  await _copyFile(
    'test/fixtures/session_history/${cli.value}/$name',
    dest,
  );
  return (
    label: label,
    session: sessionFor(id: sessionId).copyWith(cli: cli),
  );
}

Future<_LoaderFamily> _installCodexFamily({
  required RuntimeLayout layout,
  required AppSession Function({String id}) sessionFor,
  required String name,
  required String uuid,
}) async {
  final label = 'codex/$name';
  final sessionId = 'sess-${label.replaceAll('/', '-')}';
  final toolRoot = _sessionConfigDir(layout, CliTool.codex, sessionId);
  await _copyFile(
    'test/fixtures/session_history/codex/$name',
    p.join(
      toolRoot,
      'sessions',
      '2026',
      '07',
      '10',
      'rollout-2026-07-10T12-00-00-$uuid.jsonl',
    ),
  );
  return (
    label: label,
    session: sessionFor(id: sessionId).copyWith(
      cli: CliTool.codex,
      nativeSessionIds: {CliTool.codex.value: uuid},
    ),
  );
}

Future<_LoaderFamily> _installCursorFamily({
  required RuntimeLayout layout,
  required AppSession Function({String id}) sessionFor,
  required String chatId,
}) async {
  final label = 'cursor/$chatId';
  final sessionId = 'sess-${label.replaceAll('/', '-')}';
  final toolRoot = _sessionConfigDir(layout, CliTool.cursor, sessionId);
  await _copyTree('test/fixtures/session_history/cursor', toolRoot);
  return (
    label: label,
    session: sessionFor(id: sessionId).copyWith(
      cli: CliTool.cursor,
      nativeSessionIds: {CliTool.cursor.value: chatId},
    ),
  );
}

Future<_LoaderFamily> _installOpencodeFamily({
  required RuntimeLayout layout,
  required AppSession Function({String id}) sessionFor,
  required String label,
  required String storageRoot,
  required String nativeId,
}) async {
  final sessionId = 'sess-${label.replaceAll('/', '-')}';
  final toolRoot = _sessionConfigDir(layout, CliTool.opencode, sessionId);
  await _writeOpencodeDbFromJsonTree(
    p.join(toolRoot, 'opencode.db'),
    storageRoot,
  );
  return (
    label: label,
    session: sessionFor(id: sessionId).copyWith(
      cli: CliTool.opencode,
      nativeSessionIds: {CliTool.opencode.value: nativeId},
    ),
  );
}

Future<void> _copyFile(String source, String destination) async {
  final file = File(destination);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(await File(source).readAsBytes());
}

Future<void> _copyTree(String source, String destination) async {
  final root = Directory(source);
  await for (final entity in root.list(recursive: true)) {
    if (entity is! File) continue;
    final dest = File(
      p.join(destination, p.relative(entity.path, from: root.path)),
    );
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(await entity.readAsBytes());
  }
}

Future<void> _writeOpencodeDbFromJsonTree(
  String dbPath,
  String storageRoot,
) async {
  await File(dbPath).parent.create(recursive: true);
  final db = sqlite3.open(dbPath);
  try {
    db.execute('''
CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, message_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
''');
    final messagesDir = Directory(p.join(storageRoot, 'message'));
    final partsDir = Directory(p.join(storageRoot, 'part'));
    final sessionIds = <String>{};
    if (await messagesDir.exists()) {
      await for (final entity in messagesDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final raw = await entity.readAsString();
        final obj = jsonDecode(raw);
        if (obj is! Map) continue;
        final id = '${obj['id'] ?? p.basenameWithoutExtension(entity.path)}';
        final sessionId = '${obj['sessionID'] ?? ''}';
        if (id.isEmpty || sessionId.isEmpty) continue;
        sessionIds.add(sessionId);
        final created = _jsonTime(Map<Object?, Object?>.from(obj)) ?? 1;
        db.execute('INSERT INTO message VALUES (?, ?, ?, ?, ?)', [
          id,
          sessionId,
          raw,
          created,
          created,
        ]);
      }
    }
    if (await partsDir.exists()) {
      await for (final entity in partsDir.list(recursive: true)) {
        if (entity is! File) continue;
        final raw = await entity.readAsString();
        Map<String, dynamic>? obj;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) obj = Map<String, dynamic>.from(decoded);
        } on Object {
          obj = null;
        }
        final id = obj == null
            ? p.basenameWithoutExtension(entity.path)
            : '${obj['id'] ?? p.basenameWithoutExtension(entity.path)}';
        final messageId = obj == null
            ? p.basename(p.dirname(entity.path))
            : '${obj['messageID'] ?? p.basename(p.dirname(entity.path))}';
        final sessionId = obj == null
            ? sessionIds.first
            : '${obj['sessionID'] ?? sessionIds.first}';
        final created = obj == null
            ? 1
            : (_jsonTime(Map<Object?, Object?>.from(obj)) ?? 1);
        db.execute('INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)', [
          id,
          sessionId,
          messageId,
          raw,
          created,
          created,
        ]);
      }
    }
    for (final sessionId in sessionIds) {
      db.execute('INSERT INTO session VALUES (?, ?, ?, ?)', [
        sessionId,
        null,
        1,
        1,
      ]);
    }
  } finally {
    db.dispose();
  }
}

int? _jsonTime(Map<Object?, Object?> obj) {
  final time = obj['time'];
  if (time is! Map) return null;
  final created = time['created'];
  if (created is int) return created;
  if (created is num) return created.toInt();
  return null;
}
