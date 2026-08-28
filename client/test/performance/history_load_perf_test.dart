import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_load_timings.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_page.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/session/session_history_pagination.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

/// Performance evidence: counts, identity, and publish order — never wall-clock
/// milliseconds. Synthetic large JSONL + many subagent records.
void main() {
  late Directory base;
  late LocalFilesystem fs;

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('history_load_perf_');
    fs = LocalFilesystem();
  });

  tearDown(() {
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
    tearDownTestAppStorage();
  });

  test('page-first load is one decoder batch, lazy sides, identity refresh',
      () async {
    final all = _syntheticHistory();
    final recent = all.sublist(all.length - kSessionHistoryInitialTurns);
    final older = all.sublist(0, all.length - kSessionHistoryInitialTurns);
    final jsonl = _largeTranscriptJsonl();
    final jsonlLines = const LineSplitter()
        .convert(jsonl)
        .where((line) => line.trim().isNotEmpty)
        .length;
    final parseGate = Completer<void>();
    final adapter = _GatedParseAdapter(
      const ClaudeAiTranscriptAdapter(),
      parseGate,
    );
    final reader = _FakePageReader(latest: recent, older: older);
    final side = _CountingSideResolver();
    var decoderBatches = 0;
    var decoderLines = 0;
    final enricher = ClaudeCompatibleToolResultEnricher(
      decodeLines: (lines) {
        decoderBatches++;
        decoderLines += lines.length;
        return [for (final line in lines) tryDecodeJsonlLine(line)];
      },
    );
    final timings = AiHistoryLoadTimings();
    final registry = fakeAiHistoryRegistry(
      cli: CliTool.claude,
      adapter: adapter,
      pageReader: reader,
      subagentSideResolver: side,
      subagentToolNames: const {'agent', 'task'},
      toolResultEnricher: enricher,
      locate: (_) async => AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [
          AiTranscriptFragment(name: 'large.jsonl', bytes: utf8.encode(jsonl)),
        ],
      ),
    );
    final loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: base.path,
        cwd: base.path,
        appDataRoot: base.path,
        paths: AppPaths(base.path),
      ),
      registry: registry,
      locator: AiHistoryLocator(registry: registry),
      resolveCacheToken: (_) async => 'mtime-perf',
      timings: timings,
    );
    final session = AppSession(
      sessionId: 'sess-perf',
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work/project')],
      cli: CliTool.claude,
      createdAt: 1,
      updatedAt: 1,
    );
    final launch = WorkspaceLaunchContext(
      session: session,
      workspace: Workspace(
        workspaceId: session.workspaceId,
        folders: session.folders,
        createdAt: 1,
      ),
    );

    final first = await loader.load(
      session: session,
      memberId: '',
      launchContext: launch,
    );

    expect(first.isComplete, isFalse);
    expect(first.hasOlder, isTrue);
    expect(first.messages, hasLength(kSessionHistoryInitialTurns));
    expect(first.messages.map((m) => m.id), recent.map((m) => m.id));
    expect(parseGate.isCompleted, isFalse);
    expect(adapter.parseCalls, 0);
    expect(reader.latestCalls, 1);
    expect(side.resolveCalls, 0);
    expect(timings.sideTranscriptReads, 0);
    expect(timings.order, contains(AiHistoryLoadPhase.firstPublish));
    expect(timings.order, isNot(contains(AiHistoryLoadPhase.parse)));
    expect(timings.decoderBatches, 0);
    expect(decoderBatches, 0);

    parseGate.complete();
    final full = await loader.fullIndex(
      sessionId: session.sessionId,
      memberId: '',
    );
    expect(full, isNotNull);
    expect(full!.isComplete, isTrue);
    expect(full.messages, isNotEmpty);
    expect(adapter.parseCalls, 1);
    expect(decoderBatches, 1);
    expect(decoderLines, jsonlLines);
    expect(timings.decoderBatches, 1);
    expect(timings.decoderLines, jsonlLines);
    expect(timings.order, contains(AiHistoryLoadPhase.parse));
    expect(timings.order, contains(AiHistoryLoadPhase.decode));
    expect(side.resolveCalls, 0);
    expect(timings.sideTranscriptReads, 0);

    final refresh = await loader.load(
      session: session,
      memberId: '',
      launchContext: launch,
    );
    expect(
      identical(refresh.messages, full.messages),
      isTrue,
      reason: 'unchanged token must keep the same message list instance',
    );
    expect(adapter.parseCalls, 1);
    expect(decoderBatches, 1);
    expect(timings.decoderBatches, 1);
    expect(side.resolveCalls, 0);
  });
}

List<AiMessage> _syntheticHistory() {
  return [
    for (var i = 0; i < 80; i++)
      AiMessage(
        id: 'm-$i',
        role: i.isEven ? AiRole.user : AiRole.assistant,
        parts: i.isOdd && i < 40
            ? [
                AiToolCallPart(
                  toolCallId: 'agent-$i',
                  toolName: 'Agent',
                  args: {'description': 'explore $i'},
                  result: 'ok',
                  status: AiToolCallStatus.complete,
                ),
              ]
            : i == 79
            ? [
                AiToolCallPart(
                  toolCallId: 'call_02',
                  toolName: 'Bash',
                  result: 'tool output truncated',
                  status: AiToolCallStatus.complete,
                ),
              ]
            : [AiTextPart(text: 'turn $i')],
      ),
  ];
}

String _largeTranscriptJsonl() {
  final buffer = StringBuffer();
  for (var i = 0; i < 80; i++) {
    if (i.isEven) {
      buffer.writeln(
        jsonEncode({
          'type': 'user',
          'uuid': 'u-$i',
          'message': {'role': 'user', 'content': 'turn $i'},
        }),
      );
    } else {
      buffer.writeln(
        jsonEncode({
          'type': 'assistant',
          'uuid': 'a-$i',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'reply $i'},
            ],
          },
        }),
      );
    }
  }
  buffer.writeln(
    jsonEncode({
      'type': 'assistant',
      'uuid': 'bash-call',
      'message': {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 'call_02',
            'name': 'Bash',
            'input': {'command': 'pwd'},
          },
        ],
      },
    }),
  );
  buffer.writeln(
    jsonEncode({
      'type': 'user',
      'uuid': 'tool-trunc',
      'message': {
        'role': 'user',
        'content': [
          {
            'tool_use_id': 'call_02',
            'type': 'tool_result',
            'content': 'tool output truncated',
            'is_error': false,
          },
        ],
      },
      'toolUseResult': {'stdout': 'pwd', 'stderr': '', 'exitCode': 0},
    }),
  );
  for (var i = 0; i < 20; i++) {
    buffer.writeln(
      jsonEncode({
        'type': 'assistant',
        'uuid': 'agent-$i',
        'message': {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'agent-$i',
              'name': 'Agent',
              'input': {'description': 'explore $i'},
            },
          ],
        },
      }),
    );
  }
  return buffer.toString();
}

class _GatedParseAdapter implements AiTranscriptAdapter {
  _GatedParseAdapter(this._inner, this._gate);

  final AiTranscriptAdapter _inner;
  final Completer<void> _gate;
  var parseCalls = 0;

  @override
  String get id => _inner.id;

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    parseCalls++;
    await _gate.future;
    return _inner.parse(bundle);
  }
}

class _FakePageReader implements AiTranscriptPageReader {
  _FakePageReader({required this.latest, required this.older});

  final List<AiMessage> latest;
  final List<AiMessage> older;
  var latestCalls = 0;

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
    return AiHistoryPage(
      messages: older,
      hasOlder: false,
      nextCursor: null,
      sourceToken: 'page-token',
      rebuilt: false,
    );
  }
}

class _CountingSideResolver implements SubagentSideResolver {
  var resolveCalls = 0;

  @override
  Future<SubagentSideResolveResult?> resolve({
    required AiToolCallPart part,
    required SessionHistoryContext ctx,
    required SubagentSideHandle? parentHandle,
    required String? rootTranscriptPath,
    DateTime? toolCallAt,
  }) async {
    resolveCalls++;
    return null;
  }

  @override
  Future<String?> fingerprint({
    required SessionHistoryContext ctx,
    required String? rootTranscriptPath,
  }) async =>
      null;
}
