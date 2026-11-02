import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/qoder/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _root = '/tp/cli-defaults/qoder';

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.qoder,
  env: const {'QODER_CONFIG_DIR': _root},
  transcriptRoots: const [],
  taskId: 'task-1',
  nativeSessionId: 'native-1',
  sessionId: 's1',
  memberId: 'dev',
  teamId: 'team1',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _assistantLine({
  String messageId = 'm1',
  String model = 'auto',
  int input = 10,
  int output = 5,
  int cacheRead = 0,
  int cacheCreation = 0,
  String timestamp = '2026-11-02T16:57:33.552Z',
}) {
  return jsonEncode({
    'type': 'assistant',
    'uuid': 'line-$messageId',
    'timestamp': timestamp,
    'message': {
      'id': messageId,
      'model': model,
      'usage': {
        'input_tokens': input,
        'output_tokens': output,
        'cache_read_input_tokens': cacheRead,
        'cache_creation_input_tokens': cacheCreation,
      },
    },
  });
}

void main() {
  test('discovers project JSONL under QODER_CONFIG_DIR', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(
      p.join(_root, 'projects', 'proj', 's1.jsonl'),
      '${_assistantLine()}\n',
    );

    final sources = await const QoderSessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(sources.single.id, startsWith('qoder-jsonl:'));
    expect(sources.single.kind, UsageSourceKind.jsonl);
    expect(sources.single.path, p.join(_root, 'projects', 'proj', 's1.jsonl'));
  });

  test('ignores non-JSONL files and a missing projects dir', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(
      p.join(_root, 'projects', 'proj', 'notes.txt'),
      'ignore me\n',
    );

    expect(
      await const QoderSessionUsageCapability().discoverUsageSources(ctx),
      isEmpty,
    );

    final empty = UsageScanContext(
      fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      cli: CliTool.qoder,
      env: const {'QODER_CONFIG_DIR': '/nowhere'},
      transcriptRoots: const [],
      taskId: 'task-1',
      nativeSessionId: 'native-1',
      sessionId: 's1',
      memberId: 'dev',
      teamId: 'team1',
      workingDirectory: '/home/me/proj',
      appDataRoot: '/tp',
    );
    expect(
      await const QoderSessionUsageCapability().discoverUsageSources(empty),
      isEmpty,
    );
  });

  test('parses message.usage and dedupes by message id', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'projects', 'proj', 's1.jsonl');
    await ctx.fs.writeString(
      path,
      '${[
        jsonEncode({'type': 'user', 'uuid': 'u1', 'content': 'hello'}),
        _assistantLine(input: 10, output: 5, cacheRead: 2, cacheCreation: 3),
        _assistantLine(input: 10, output: 5, cacheRead: 2, cacheCreation: 3),
      ].join('\n')}\n',
    );
    final capability = const QoderSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final first = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(first.events, hasLength(1));
    final event = first.events.single;
    expect(event.cli, CliTool.qoder);
    expect(event.requestId, 'qoder:m1');
    expect(event.model, 'auto');
    expect(event.inputTokens, 10);
    expect(event.outputTokens, 5);
    expect(event.cacheReadTokens, 2);
    expect(event.cacheCreationTokens, 3);
    expect(event.inputSemantics, UsageInputSemantics.total);
    expect(
      event.timestampMs,
      DateTime.parse('2026-11-02T16:57:33.552Z').millisecondsSinceEpoch,
    );
    expect(event.sessionId, 's1');
    expect(event.memberId, 'dev');
    expect(event.teamId, 'team1');

    final second = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );
    expect(second.events, isEmpty);
  });

  test('keeps the largest snapshot for one message id', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'projects', 'proj', 's3.jsonl');
    await ctx.fs.writeString(
      path,
      '${[_assistantLine(messageId: 'partial', input: 10, output: 1), _assistantLine(messageId: 'partial', input: 10, output: 5)].join('\n')}\n',
    );
    final capability = const QoderSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events, hasLength(1));
    expect(result.events.single.outputTokens, 5);
  });

  test('skips zero-token records', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'projects', 'proj', 's4.jsonl');
    await ctx.fs.writeString(
      path,
      '${[_assistantLine(messageId: 'empty', input: 0, output: 0), _assistantLine(messageId: 'real', input: 7, output: 3)].join('\n')}\n',
    );
    final capability = const QoderSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events.map((e) => e.requestId), ['qoder:real']);
    expect(result.skippedLines, 0);
  });

  test('skips malformed lines and records without a message id', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'projects', 'proj', 's5.jsonl');
    await ctx.fs.writeString(
      path,
      '${[
        'not json at all',
        '[]',
        jsonEncode({
          'type': 'assistant',
          'timestamp': '2026-11-02T16:57:33.552Z',
          'message': {
            'model': 'auto',
            'usage': {'input_tokens': 4, 'output_tokens': 1},
          },
        }),
        jsonEncode({
          'type': 'assistant',
          'uuid': 'fallback-uuid',
          'timestamp': '2026-11-02T16:57:33.552Z',
          'message': {
            'model': 'auto',
            'usage': {'input_tokens': 6, 'output_tokens': 2},
          },
        }),
      ].join('\n')}\n',
    );
    final capability = const QoderSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events, hasLength(1));
    expect(result.events.single.requestId, 'qoder:fallback-uuid');
    expect(result.skippedLines, 3);
  });
}
