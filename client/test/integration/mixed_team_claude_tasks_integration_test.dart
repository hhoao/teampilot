@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/integration_test_setup.dart';
import 'support/mixed_team_task_scenario.dart';

void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'leader add_tasks and worker wait_for_message auto-claim over real Claude PTYs',
    MixedTeamTaskScenario.runTaskDispatch,
  );

  test(
    'wait_for_message delivers urgent mail before auto-claiming a queued task',
    MixedTeamTaskScenario.runMailPriorityOverTask,
  );

  test(
    'add_tasks doorbells idle-at-prompt worker to claim from wait_for_message',
    MixedTeamTaskScenario.runDoorbellDispatch,
  );
}
