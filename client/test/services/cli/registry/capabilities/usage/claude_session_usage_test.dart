import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _root = '/tp/cli-defaults/claude';

UsageScanContext _ctx({String nativeId = 'native-1'}) => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.claude,
  env: const {},
  transcriptRoots: const [_root],
  taskId: 'task-1',
  nativeSessionId: nativeId,
  sessionId: 's1',
  memberId: 'dev',
  teamId: 'team1',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _line({
  required String id,
  int input = 10,
  int output = 2,
  int cacheRead = 0,
  int cacheCreate = 0,
  String? stopReason = 'end_turn',
  int cache1h = 0,
}) {
  return jsonEncode({
    'type': 'assistant',
    'timestamp': '2026-10-26T10:00:00.000Z',
    'message': {
      'id': id,
      'model': 'claude-sonnet-4',
      'stop_reason': stopReason,
      'usage': {
        'input_tokens': input,
        'output_tokens': output,
        'cache_read_input_tokens': cacheRead,
        'cache_creation_input_tokens': cacheCreate,
        if (cache1h > 0)
          'cache_creation': {'ephemeral_1h_input_tokens': cache1h},
      },
    },
  });
}

void main() {
  test('discovers the seat transcript and its subagent children', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(
      p.join(_root, 'projects', '-home-me-proj', 'native-1.jsonl'),
      '',
    );
    await ctx.fs.writeString(
      p.join(
        _root,
        'projects',
        '-home-me-proj',
        'native-1',
        'subagents',
        'agent-a.jsonl',
      ),
      '',
    );
    await ctx.fs.writeString(
      p.join(_root, 'projects', '-home-me-proj', 'other.jsonl'),
      '',
    );

    final sources = await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(2));
    expect(sources.every((s) => s.id.startsWith('claude-jsonl:')), isTrue);
  });

  test('parses usage, finality, cache, and 1h cache', () async {
    final ctx = _ctx();
    final path = p.join(
      _root,
      'projects',
      '-home-me-proj',
      'native-1.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_line(id: 'm1', input: 100, output: 20, cacheRead: 30, cacheCreate: 10, cache1h: 5)}\n',
    );
    final source = (await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;

    final scan = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    final event = scan.events.single;
    expect(event.requestId, 'claude:m1');
    expect(event.cli, CliTool.claude);
    expect(event.model, 'claude-sonnet-4');
    expect(event.inputTokens, 100);
    expect(event.outputTokens, 20);
    expect(event.cacheReadTokens, 30);
    expect(event.cacheCreationTokens, 10);
    expect(event.cacheCreation1hTokens, 5);
    expect(event.inputSemantics, UsageInputSemantics.fresh);
    expect(event.isFinal, isTrue);
    expect(event.sessionId, 's1');
    expect(event.memberId, 'dev');
    expect(event.teamId, 'team1');
  });

  test('non-final message stays importable and is replaced later', () async {
    final ctx = _ctx();
    final path = p.join(
      _root,
      'projects',
      '-home-me-proj',
      'native-1.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_line(id: 'm1', output: 1, stopReason: null)}\n',
    );
    final source = (await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final first = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(first.events.single.isFinal, isFalse);
    expect(first.events.single.outputTokens, 1);

    await ctx.fs.appendString(
      path,
      '${_line(id: 'm1', output: 9, stopReason: 'end_turn')}\n',
    );
    final second = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.single.isFinal, isTrue);
    expect(second.events.single.outputTokens, 9);
  });

  test('skips zero-usage and malformed lines', () async {
    final ctx = _ctx();
    final path = p.join(
      _root,
      'projects',
      '-home-me-proj',
      'native-1.jsonl',
    );
    await ctx.fs.writeString(
      path,
      'not-json\n${_line(id: 'm1', input: 0, output: 0)}\n${_line(id: 'm2')}\n',
    );
    final source = (await const ClaudeSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;

    final scan = await const ClaudeSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(scan.events, hasLength(1));
    expect(scan.events.single.requestId, 'claude:m2');
    expect(scan.skippedLines, 1);
  });
}
