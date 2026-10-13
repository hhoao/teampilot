import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/acp.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('opencode registers AcpCapability that spawns opencode acp', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final cap = registry.capability<AcpCapability>(CliTool.opencode);
    expect(cap, isA<OpencodeAcpCapability>());
    expect(cap!.agentExecutable('/usr/bin/opencode'), '/usr/bin/opencode');
    expect(cap.launchArgCandidates('/usr/bin/opencode'), [
      ['/usr/bin/opencode', 'acp'],
    ]);
    expect(cap.authenticateMethodId, isNull);
    expect(capabilityToPlan(cap)!.authenticateMethodId, isNull);
    expect(capabilityToPlan(cap)!.forwardSessionNewMcpServers, isFalse);
  });
}
