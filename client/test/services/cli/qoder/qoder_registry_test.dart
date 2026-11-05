import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('qoder registers every required capability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final def = registry.tryGet(CliTool.qoder);
    expect(def, isNotNull);
    expect(def!.isLaunchSupported, isTrue);
    final exe = registry.capability<CliExecutableCapability>(CliTool.qoder)!;
    expect(exe.defaultExecutableName, 'qodercli');
    expect(exe.supportsInstaller, isTrue);
    expect(registry.capability<AcpCapability>(CliTool.qoder), isNotNull);
    expect(
      registry.capability<CliTransportCapability>(CliTool.qoder)!.supported,
      {CliTransport.acp},
    );
    expect(registry.launchesAcpOnly(CliTool.qoder), isTrue);
    expect(registry.supportsNativeTeam(CliTool.qoder), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.qoder), isFalse);
  });
}
