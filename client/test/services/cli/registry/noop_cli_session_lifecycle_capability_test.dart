import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/noop_cli_session_lifecycle_capability.dart';

void main() {
  test('no-op gateConnect always allows', () {
    const cap = NoopCliSessionLifecycleCapability();
    expect(
      cap.gateConnect(const CliSessionGateContext(
        workspaceId: 'w',
        sessionId: 's',
        memberId: 'm',
        tool: CliTool.claude,
      )).allowed,
      isTrue,
    );
  });
}
