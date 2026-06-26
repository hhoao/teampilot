@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 4))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/integration_test_setup.dart';
import 'support/mixed_team_ping_pong_scenario.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'two Claude members exchange ping/pong via ChatCubit launch path',
    MixedTeamPingPongScenario.runLocal,
  );
}
