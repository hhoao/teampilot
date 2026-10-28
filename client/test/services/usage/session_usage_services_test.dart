import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/session_usage_services.dart';
import 'package:teampilot/models/app_session.dart';
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

  test('imports Cursor dashboard rows into the merged event view', () async {
    final services = SessionUsageServices.forStorage(
      storage: testHomeStorage,
      loadSessions: () async => const <AppSession>[],
      loadTeams: () async => const <TeamProfile>[],
    );
    const csv =
        'Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,'
        'Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,'
        'Output Tokens,Total Tokens,Cost\n'
        '2026-10-26T10:00:00Z,,,chat,claude-sonnet-4,,0,100,10,20,130,\$0.50\n';

    final result = await services.importCursorCsv(csv);

    expect(result.inserted, 1);
    final events = await services.loadEvents();
    expect(events, hasLength(1));
    expect(events.single.cli, CliTool.cursor);
    expect(events.single.costMicroUsd, 500000);
    expect((await services.loadCursorStatus()).eventCount, 1);

    await services.clearCursorUsage();
    expect(await services.loadEvents(), isEmpty);
  });
}
