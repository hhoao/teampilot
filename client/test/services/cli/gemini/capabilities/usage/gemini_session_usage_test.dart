import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/gemini/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _root = '/tp/cli-defaults/gemini';

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.gemini,
  env: const {'GEMINI_CONFIG_DIR': _root},
  transcriptRoots: const [],
  taskId: 'task-1',
  nativeSessionId: 'native-1',
  sessionId: 's1',
  memberId: 'dev',
  teamId: 'team1',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _jsonlSession() {
  final header = {
    'sessionId': 'gemini-1',
    'startTime': '2026-10-26T10:00:00.000Z',
  };
  final user = {
    'id': 'u1',
    'timestamp': '2026-10-26T10:00:00.000Z',
    'type': 'user',
    'content': 'hello',
  };
  final gemini = {
    'id': 'g1',
    'timestamp': '2026-10-26T10:00:05.000Z',
    'type': 'gemini',
    'model': 'gemini-3.1-pro-preview',
    'tokens': {'input': 120, 'cached': 20, 'output': 30, 'thoughts': 5},
  };
  return '${[header, user, gemini].map(jsonEncode).join('\n')}\n';
}

void main() {
  test('discovers session JSONL under GEMINI_CONFIG_DIR', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(
      p.join(_root, 'tmp', 'proj', 'chats', 'session-1.jsonl'),
      _jsonlSession(),
    );

    final sources = await const GeminiSessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(sources.single.id, startsWith('gemini-jsonl:'));
  });

  test('parses tokens, cache, and thoughts', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'tmp', 'proj', 'chats', 'session-1.jsonl');
    await ctx.fs.writeString(path, _jsonlSession());
    final capability = const GeminiSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final first = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(first.events, hasLength(1));
    final event = first.events.single;
    expect(event.requestId, 'gemini:gemini-1:g1');
    expect(event.cli, CliTool.gemini);
    expect(event.model, 'gemini-3.1-pro-preview');
    expect(event.inputTokens, 120);
    expect(event.cacheReadTokens, 20);
    expect(event.outputTokens, 35);
    expect(event.inputSemantics, UsageInputSemantics.total);
    expect(event.freshInputTokens, 100);

    final second = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );
    expect(second.events, isEmpty);
  });

  test('re-reads a JSONL session after a rewrite', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'tmp', 'proj', 'chats', 'session-3.jsonl');
    final header = jsonEncode({
      'sessionId': 'gemini-3',
      'startTime': '2026-10-26T10:00:00.000Z',
    });
    final firstMessage = {
      'id': 'g1',
      'timestamp': '2026-10-26T10:00:05.000Z',
      'type': 'gemini',
      'model': 'gemini-3-pro',
      'content': 'first',
      'tokens': {'input': 10, 'output': 3},
    };
    await ctx.fs.writeString(
      path,
      '${[header, jsonEncode(firstMessage)].join('\n')}\n',
    );
    final capability = const GeminiSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;
    final first = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );
    expect(first.events, hasLength(1));

    await ctx.fs.writeString(
      path,
      '${[
        header,
        jsonEncode({...firstMessage, 'content': 'first changed'}),
        jsonEncode({
          'id': 'g2',
          'timestamp': '2026-10-26T10:00:10.000Z',
          'type': 'gemini',
          'model': 'gemini-3-pro',
          'tokens': {'input': 20, 'output': 4},
        }),
      ].join('\n')}\n',
    );
    final second = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.map((e) => e.requestId), [
      'gemini:gemini-3:g1',
      'gemini:gemini-3:g2',
    ]);
  });

  test('reads older single-JSON sessions', () async {
    final ctx = _ctx();
    final path = p.join(_root, 'tmp', 'proj', 'chats', 'session-2.json');
    await ctx.fs.writeString(
      path,
      jsonEncode({
        'sessionId': 'gemini-2',
        'startTime': '2026-10-26T10:00:00.000Z',
        'messages': [
          {
            'id': 'g1',
            'timestamp': '2026-10-26T10:00:05.000Z',
            'type': 'gemini',
            'model': 'gemini-3-pro',
            'tokens': {'input': 10, 'cached': 2, 'output': 3},
          },
        ],
      }),
    );
    final capability = const GeminiSessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final first = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(first.events, hasLength(1));
    expect(first.events.single.requestId, 'gemini:gemini-2:g1');
    expect(first.events.single.outputTokens, 3);

    final second = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );
    expect(second.events, isEmpty);
  });
}
