import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';

import '../../../../../support/in_memory_filesystem.dart';

const _home = '/tp/runtime/codex';
const _thread = '11111111-1111-1111-1111-111111111111';

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.codex,
  env: const {'CODEX_HOME': _home},
  transcriptRoots: const [],
  taskId: 'task-1',
  nativeSessionId: _thread,
  sessionId: 's1',
  memberId: '',
  teamId: '',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _tokenCount({
  Map<String, Object?>? last,
  Map<String, Object?>? total,
}) {
  return jsonEncode({
    'type': 'event_msg',
    'timestamp': '2026-10-26T10:00:00.000Z',
    'payload': {
      'type': 'token_count',
      'info': {
        if (last != null) 'last_token_usage': last,
        if (total != null) 'total_token_usage': total,
      },
    },
  });
}

Map<String, Object?> _usage({
  required int input,
  required int cached,
  required int output,
}) => {
  'input_tokens': input,
  'cached_input_tokens': cached,
  'output_tokens': output,
};

void main() {
  test('discovers rollouts under CODEX_HOME', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(path, '');

    final sources = await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(sources.single.kind, UsageSourceKind.jsonl);
  });

  test('uses last_token_usage and keeps the cumulative baseline', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_tokenCount(last: _usage(input: 100, cached: 40, output: 10), total: _usage(input: 100, cached: 40, output: 10))}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final first = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    final event = first.events.single;
    expect(event.requestId, startsWith('codex:$_thread:'));
    expect(event.inputTokens, 100);
    expect(event.cacheReadTokens, 40);
    expect(event.outputTokens, 10);
    expect(event.inputSemantics, UsageInputSemantics.total);
    expect(event.freshInputTokens, 60);
    expect(first.nextCursor.storeToken, '100,10,40,0');

    await ctx.fs.appendString(
      path,
      '${_tokenCount(last: _usage(input: 20, cached: 5, output: 3), total: _usage(input: 120, cached: 45, output: 13))}\n',
    );
    final second = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.single.inputTokens, 20);
    expect(second.events.single.cacheReadTokens, 5);
    expect(second.events.single.outputTokens, 3);
    expect(second.nextCursor.storeToken, '120,13,45,0');
  });

  test('derives a delta when only total_token_usage is present', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_tokenCount(total: _usage(input: 100, cached: 40, output: 10))}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final first = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    await ctx.fs.appendString(
      path,
      '${_tokenCount(total: _usage(input: 150, cached: 50, output: 18))}\n',
    );
    final second = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );

    expect(second.events.single.inputTokens, 50);
    expect(second.events.single.cacheReadTokens, 10);
    expect(second.events.single.outputTokens, 8);
  });

  test('clamps cache counters to input', () async {
    final ctx = _ctx();
    final path = p.join(
      _home,
      'sessions',
      '2026',
      '10',
      '26',
      'rollout-2026-10-26T10-00-00-$_thread.jsonl',
    );
    await ctx.fs.writeString(
      path,
      '${_tokenCount(last: {'input_tokens': 10, 'cached_input_tokens': 99, 'cache_write_input_tokens': 99, 'output_tokens': 1})}\n',
    );
    final source = (await const CodexSessionUsageCapability()
        .discoverUsageSources(ctx))
        .single;
    final scan = await const CodexSessionUsageCapability().scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(scan.events.single.cacheReadTokens, 10);
    expect(scan.events.single.cacheCreationTokens, 0);
  });
}
