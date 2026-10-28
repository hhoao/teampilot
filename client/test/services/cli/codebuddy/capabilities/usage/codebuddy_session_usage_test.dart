import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _root = '/tp/cli-defaults/codebuddy';

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.codebuddy,
  env: const {'CODEBUDDY_CONFIG_DIR': _root},
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
  String model = 'deepseek-v4.1-flash',
  int prompt = 23469,
  int completion = 3,
  int cached = 128,
}) {
  return jsonEncode({
    'type': 'message',
    'role': 'assistant',
    'id': 'line-$messageId',
    'timestamp': 1793091272751,
    'providerData': {
      'messageId': messageId,
      'model': model,
      'rawUsage': {
        'prompt_tokens': prompt,
        'completion_tokens': completion,
        'prompt_cache_hit_tokens': cached,
        'prompt_cache_miss_tokens': prompt - cached,
      },
    },
  });
}

void main() {
  test('discovers project JSONL under CODEBUDDY_CONFIG_DIR', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(
      p.join(_root, 'projects', 'proj', 's1.jsonl'),
      '${_assistantLine()}\n',
    );

    final sources = await const CodebuddySessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(sources.single.id, startsWith('codebuddy-jsonl:'));
  });

  test('parses rawUsage with cache and dedupes one request id', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'projects', 'proj', 's1.jsonl');
    await ctx.fs.writeString(
      path,
      '${[
        jsonEncode({'type': 'message', 'role': 'user', 'content': 'hello'}),
        _assistantLine(),
        _assistantLine(),
      ].join('\n')}\n',
    );
    final capability = const CodebuddySessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final first = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(first.events, hasLength(1));
    final event = first.events.single;
    expect(event.requestId, 'codebuddy:m1');
    expect(event.cli, CliTool.codebuddy);
    expect(event.model, 'deepseek-v4.1-flash');
    expect(event.inputTokens, 23469);
    expect(event.outputTokens, 3);
    expect(event.cacheReadTokens, 128);
    expect(event.inputSemantics, UsageInputSemantics.total);
    expect(event.freshInputTokens, 23341);
    expect(event.timestampMs, 1793091272751);

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
      '${[_assistantLine(messageId: 'partial', prompt: 10, completion: 1), _assistantLine(messageId: 'partial', prompt: 10, completion: 5)].join('\n')}\n',
    );
    final capability = const CodebuddySessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events, hasLength(1));
    expect(result.events.single.outputTokens, 5);
  });

  test('falls back to message.usage and skips missing request ids', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'projects', 'proj', 's2.jsonl');
    await ctx.fs.writeString(
      path,
      '${[
        jsonEncode({
          'type': 'message',
          'role': 'assistant',
          'timestamp': 1,
          'message': {
            'model': 'claude-sonnet-4',
            'usage': {'input_tokens': 10, 'output_tokens': 2, 'cache_read_input_tokens': 3},
          },
        }),
        jsonEncode({
          'type': 'message',
          'role': 'assistant',
          'id': 'fallback-id',
          'timestamp': 2,
          'providerData': {
            'usage': {'inputTokens': 20, 'outputTokens': 4},
          },
        }),
      ].join('\n')}\n',
    );
    final capability = const CodebuddySessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events, hasLength(1));
    expect(result.events.single.requestId, 'codebuddy:fallback-id');
    expect(result.events.single.inputTokens, 20);
    expect(result.events.single.outputTokens, 4);
    expect(result.skippedLines, 1);
  });
}
