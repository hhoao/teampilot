import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/session_usage_services.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('startSync returns a handle for the current home plane', () async {
    final services = SessionUsageServices.forStorage(
      storage: testHomeStorage,
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
    );

    final handle = services.startSync();
    final result = await handle.done;

    expect(result.targetsScanned, 0);
    expect(result.cancelled, isFalse);
  });

  test('merges the injected account usage into the event view', () async {
    final event = SessionUsageEvent(
      requestId: 'cursor-account:acct1:1:auto',
      cli: CliTool.cursor,
      model: 'auto',
      inputTokens: 10,
      outputTokens: 5,
      cacheReadTokens: 100,
      cacheCreationTokens: 2,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: 1,
      sessionId: 'cursor-account-usage',
      costMicroUsd: 35000,
    );
    final services = SessionUsageServices.forStorage(
      storage: testHomeStorage,
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
      loadCursorAccountUsage: () async => [event],
    );

    final events = await services.loadEvents();

    expect(events, hasLength(1));
    expect(events.single.requestId, event.requestId);
    expect(events.single.cli, CliTool.cursor);
  });
}
