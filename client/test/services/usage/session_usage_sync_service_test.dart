import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/usage/session_usage_sync_service.dart';
import 'package:teampilot/services/usage/usage_cursor_store.dart';
import 'package:teampilot/services/usage/usage_scan_target_provider.dart';
import 'package:teampilot/services/usage/usage_store.dart';

import '../../support/in_memory_filesystem.dart';

final class _FakeTargets implements UsageScanTargetProvider {
  _FakeTargets(this.contexts);

  final List<UsageScanContext> contexts;

  @override
  Future<List<UsageScanContext>> targets() async => contexts;
}

final class _FakeTool implements CliToolDefinition {
  _FakeTool(this.id, this.capabilities);

  @override
  final CliTool id;
  @override
  final List<CliCapability> capabilities;
  @override
  bool get isLaunchSupported => true;
}

final class _FakeCapability implements SessionUsageCapability {
  _FakeCapability({required this.sources, this.failOn});

  final List<SessionUsageSource> sources;
  final String? failOn;
  int scans = 0;

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async => sources;

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async {
    scans++;
    if (source.id == failOn) throw StateError('boom');
    return UsageScanResult(
      events: [_event(source.id)],
      nextCursor: const UsageCursor(byteOffset: 7),
    );
  }
}

final class _FakeStore implements UsageStore {
  final events = <SessionUsageEvent>[];

  @override
  Future<UsageAppendResult> upsert(
    Iterable<SessionUsageEvent> next,
  ) async {
    final list = next.toList();
    events.addAll(list);
    return UsageAppendResult(inserted: list.length);
  }

  @override
  Future<List<SessionUsageEvent>> readLatest() async => List.of(events);
}

final class _FakeCursors implements UsageCursorStore {
  final saved = <String, UsageCursor>{};

  @override
  Future<UsageCursor?> read(String sourceId) async => saved[sourceId];

  @override
  Future<void> save(String sourceId, UsageCursor cursor) async {
    saved[sourceId] = cursor;
  }

  @override
  Future<void> remove(String sourceId) async {
    saved.remove(sourceId);
  }
}

SessionUsageEvent _event(String id) => SessionUsageEvent(
  requestId: 'claude:$id',
  cli: CliTool.claude,
  model: 'claude-sonnet-4',
  inputTokens: 10,
  outputTokens: 2,
  cacheReadTokens: 0,
  cacheCreationTokens: 0,
  inputSemantics: UsageInputSemantics.fresh,
  timestampMs: 1,
  sessionId: 's1',
);

UsageScanContext _ctx() => UsageScanContext(
  fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  cli: CliTool.claude,
  env: const {},
  transcriptRoots: const [],
  taskId: 'task',
  nativeSessionId: 'native',
  sessionId: 's1',
  memberId: '',
  teamId: '',
  workingDirectory: '/home/me/proj',
  appDataRoot: '/tp',
);

SessionUsageSource _source(String id) => SessionUsageSource(
  id: id,
  path: '/tp/$id.jsonl',
  kind: UsageSourceKind.jsonl,
  sessionId: 's1',
  memberId: '',
  teamId: '',
);

void main() {
  test('discovers, scans, stores, and advances cursors', () async {
    final capability = _FakeCapability(sources: [_source('a'), _source('b')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final store = _FakeStore();
    final cursors = _FakeCursors();
    final service = SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: store,
      cursors: cursors,
      registry: registry,
    );

    final result = await service.syncAll();

    expect(result.targetsScanned, 1);
    expect(result.sourcesScanned, 2);
    expect(result.inserted, 2);
    expect(capability.scans, 2);
    expect(store.events, hasLength(2));
    expect(cursors.saved.keys, containsAll(['a', 'b']));
    expect(result.errors, isEmpty);
  });

  test('re-running scans again and keeps cursors', () async {
    final capability = _FakeCapability(sources: [_source('a')]);
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final cursors = _FakeCursors();
    final service = SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: _FakeStore(),
      cursors: cursors,
      registry: registry,
    );

    await service.syncAll();
    await service.syncAll();

    expect(capability.scans, 2);
    expect(cursors.saved['a']?.byteOffset, 7);
  });

  test('one source failure does not abort the other source', () async {
    final capability = _FakeCapability(
      sources: [_source('bad'), _source('good')],
      failOn: 'bad',
    );
    final registry = CliToolRegistry()
      ..register(_FakeTool(CliTool.claude, [capability]));
    final store = _FakeStore();
    final service = SessionUsageSyncService(
      targets: _FakeTargets([_ctx()]),
      store: store,
      cursors: _FakeCursors(),
      registry: registry,
    );

    final result = await service.syncAll();

    expect(result.errors, hasLength(1));
    expect(result.errors.single.sourceId, 'bad');
    expect(store.events, hasLength(1));
  });
}
