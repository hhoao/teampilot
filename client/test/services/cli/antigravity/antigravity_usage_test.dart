import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/usage.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

const _toolDir = '/tp/runtime/s1/dev/antigravity';

UsageScanContext _ctx({
  Map<String, String> env = const {'HOME': '$_toolDir/home'},
  List<String> transcriptRoots = const [],
}) => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.antigravity,
  env: env,
  transcriptRoots: transcriptRoots,
  taskId: 'task-1',
  nativeSessionId: 'native-1',
  sessionId: 's1',
  memberId: 'dev',
  teamId: 'team1',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

String _record({
  int used = 4096,
  int size = 1048576,
  int sequence = 1793091272751000,
  String? model,
  Map<String, Object?>? cost,
}) => jsonEncode({
  'sessionId': 's1',
  'used': used,
  'size': size,
  'sequence': sequence,
  if (model != null) 'model': model,
  if (cost != null) 'cost': cost,
});

void main() {
  test('discovers the usage JSONL beside the isolated HOME', () async {
    final ctx = _ctx();
    await ctx.fs.writeString(p.join(_toolDir, 'acp-usage.jsonl'), '');

    final sources = await const AntigravitySessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(
      sources.single.path,
      p.join(_toolDir, AntigravitySessionUsageCapability.usageFileName),
    );
    expect(sources.single.id, startsWith('antigravity-jsonl:'));
    expect(sources.single.kind, UsageSourceKind.jsonl);
  });

  test('falls back to transcript roots without an isolated HOME', () async {
    final root = p.join('/tp', 'cli-defaults', 'antigravity');
    final ctx = _ctx(env: const {}, transcriptRoots: [root]);
    await ctx.fs.writeString(p.join(root, 'acp-usage.jsonl'), '');

    final sources = await const AntigravitySessionUsageCapability()
        .discoverUsageSources(ctx);

    expect(sources, hasLength(1));
    expect(sources.single.path, p.join(root, 'acp-usage.jsonl'));
  });

  test('returns no source when the usage file is missing', () async {
    final ctx = _ctx(
      env: const {'HOME': '$_toolDir/home'},
      transcriptRoots: const [_toolDir],
    );

    expect(
      await const AntigravitySessionUsageCapability().discoverUsageSources(ctx),
      isEmpty,
    );
  });

  test('maps used to input tokens without inventing output or cost', () async {
    final ctx = _ctx();
    final path = p.join(_toolDir, 'acp-usage.jsonl');
    await ctx.fs.writeString(
      path,
      '${[
        // The probe sample right after session/new carries no context.
        _record(used: 0, size: 1048576, sequence: 1),
        _record(used: 4096, sequence: 1793091272751000),
        _record(
          used: 8192,
          sequence: 1793091272752000,
          model: 'gemini-3.8-flash',
        ),
      ].join('\n')}\n',
    );
    final capability = const AntigravitySessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events, hasLength(2));
    final first = result.events.first;
    expect(first.cli, CliTool.antigravity);
    expect(first.model, '');
    expect(first.inputTokens, 4096);
    expect(first.outputTokens, 0);
    expect(first.cacheReadTokens, 0);
    expect(first.cacheCreationTokens, 0);
    expect(first.inputSemantics, UsageInputSemantics.total);
    expect(first.timestampMs, 1793091272751);
    expect(first.costMicroUsd, isNull);

    final second = result.events.last;
    expect(second.model, 'gemini-3.8-flash');
    expect(second.inputTokens, 8192);
    expect(second.outputTokens, 0);
    expect(second.requestId, 's1:1793091272752000');
    expect(
      {first.requestId, second.requestId},
      hasLength(2),
      reason: 'request ids are unique per sample',
    );
  });

  test('incremental scan does not replay consumed records', () async {
    final ctx = _ctx();
    final path = p.join(_toolDir, 'acp-usage.jsonl');
    await ctx.fs.writeString(path, '${_record()}\n');
    final capability = const AntigravitySessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final first = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );
    expect(first.events, hasLength(1));

    final second = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: first.nextCursor,
    );
    expect(second.events, isEmpty);
  });

  test('skips malformed lines', () async {
    final ctx = _ctx();
    final path = p.join(_toolDir, 'acp-usage.jsonl');
    await ctx.fs.writeString(path, 'not-json\n${_record()}\n');
    final capability = const AntigravitySessionUsageCapability();
    final source = (await capability.discoverUsageSources(ctx)).single;

    final result = await capability.scanUsageSource(
      ctx: ctx,
      source: source,
      cursor: null,
    );

    expect(result.events, hasLength(1));
    expect(result.skippedLines, 1);
  });

  test('registers sessionUsage on the Antigravity tool', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    expect(
      registry.capability<SessionUsageCapability>(CliTool.antigravity),
      isNotNull,
    );
  });
}
