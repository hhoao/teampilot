import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/acp.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('cursor registers AcpCapability that spawns cursor-agent acp', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final cap = registry.capability<AcpCapability>(CliTool.cursor);
    expect(cap, isA<CursorAcpCapability>());
    expect(cap!.agentExecutable('/usr/bin/cursor-agent'), '/usr/bin/cursor-agent');
    expect(cap.launchArgCandidates('/usr/bin/cursor-agent'), [
      ['/usr/bin/cursor-agent', 'acp'],
    ]);
    expect(cap.authenticateMethodId, 'cursor_login');
    expect(capabilityToPlan(cap)!.authenticateMethodId, 'cursor_login');
    expect(capabilityToPlan(cap)!.forwardSessionNewMcpServers, isFalse);
  });
}
