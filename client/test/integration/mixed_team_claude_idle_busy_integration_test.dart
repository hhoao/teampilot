@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/integration_test_setup.dart';
import 'support/mixed_team_idle_busy_l2_scenario.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'mixed session idle at prompt on real PTYs (workingSessionIds + presence)',
    MixedTeamIdleBusyL2Scenario.runSessionIdleAtPrompt,
  );

  test(
    'worker kickoff returns to bus-idle session on real PTYs',
    MixedTeamIdleBusyL2Scenario.runWorkerKickoffThenSessionIdle,
  );

  test(
    'session returns idle after worker update_task(done) on real PTYs',
    MixedTeamIdleBusyL2Scenario.runSessionIdleAfterTaskComplete,
  );
}
