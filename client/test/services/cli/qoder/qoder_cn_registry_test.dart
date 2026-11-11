import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('qoder-cn registers every required capability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final def = registry.tryGet(CliTool.qoderCn);
    expect(def, isNotNull);
    expect(def!.isLaunchSupported, isTrue);

    final exe = registry.capability<CliExecutableCapability>(CliTool.qoderCn)!;
    expect(exe.defaultExecutableName, 'qoderclicn');
    expect(exe.preferencesPathKey, 'qoder-cn');
    expect(exe.supportsInstaller, !Platform.isWindows);

    expect(registry.capability<AcpCapability>(CliTool.qoderCn), isNotNull);
    final acp = registry.capability<AcpCapability>(CliTool.qoderCn)!;
    expect(
      acp.buildEnvironment(
        sessionToolDir: '/runtime/qoder-cn',
        workingDirectory: '/work',
      ),
      {
        'QODERCN_CONFIG_DIR': '/runtime/qoder-cn',
        'QODERCN_EXPOSE_TOKEN_USAGE': '1',
      },
    );
    expect(registry.capability<ProviderCapability>(CliTool.qoderCn), isNotNull);
    expect(
      registry.capability<CliTransportCapability>(CliTool.qoderCn)!.supported,
      {CliTransport.acp},
    );
    expect(registry.launchesAcpOnly(CliTool.qoderCn), isTrue);
    expect(registry.supportsNativeTeam(CliTool.qoderCn), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.qoderCn), isFalse);
  });
}
