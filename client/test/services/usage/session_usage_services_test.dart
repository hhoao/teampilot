import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/session_usage_services.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUpTestAppStorage();
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
}
