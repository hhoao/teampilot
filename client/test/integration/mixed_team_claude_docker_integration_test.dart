@Tags(['integration'])
@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/integration_test_setup.dart';
import 'support/mixed_team_ping_pong_scenario.dart';

/// Local team-lead + Docker SSH worker, full ChatCubit launch path including
/// remote preflight (Node bootstrap + Claude install) and bus ping/pong.
///
/// Run from `client/` (Docker daemon, outbound network, local `claude` on PATH,
/// `libflutter_pty.so` after `flutter build linux --debug`):
/// ```bash
/// flutter test test/integration/mixed_team_claude_docker_integration_test.dart --tags integration
/// ```
void main() {
  setUp(setUpIntegrationAppStorage);
  tearDown(tearDownIntegrationAppStorage);

  test(
    'local lead + docker worker exchange ping/pong via ChatCubit',
    MixedTeamPingPongScenario.runDocker,
  );
}
