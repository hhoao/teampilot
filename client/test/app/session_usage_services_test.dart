import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/app/session_usage_services.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/json_usage_store.dart';

import '../support/in_memory_filesystem.dart';

SessionUsageEvent _event() => const SessionUsageEvent(
  requestId: 'claude:1',
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

InMemoryFilesystem _fs() =>
    InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));

void main() {
  test('factory builds against empty storage and syncs nothing', () async {
    final storage = fakeHomeStorage(
      appDataRoot: '/tp-factory-${DateTime.now().microsecondsSinceEpoch}',
      filesystem: _fs(),
    );
    final services = SessionUsageServices.forStorage(
      storage: storage,
      loadSessions: () async => const [],
      loadTeams: () async => const [],
    );

    expect(await services.loadEvents(), isEmpty);

    final result = await services.syncAll();

    expect(result.targetsScanned, 0);
    expect(result.errors, isEmpty);
    expect(await services.loadEvents(), isEmpty);
  });

  test('loaders follow a home-plane swap', () async {
    final storage = fakeHomeStorage(
      appDataRoot: '/tp-plane-a',
      filesystem: _fs(),
    );
    final services = SessionUsageServices.forStorage(
      storage: storage,
      loadSessions: () async => const [],
      loadTeams: () async => const [],
    );

    expect(await services.loadEvents(), isEmpty);

    final planeB = fakeHomeStorage(
      appDataRoot: '/tp-plane-b',
      filesystem: _fs(),
    );
    await storage.swap(planeB.context);

    expect(await services.loadEvents(), isEmpty);

    await JsonUsageStore(
      fs: planeB.fs,
      filePath: storage.paths.usageEventsFile,
    ).upsert([_event()]);

    final events = await services.loadEvents();
    expect(events, hasLength(1));
    expect(events.single.requestId, 'claude:1');
  });
}
