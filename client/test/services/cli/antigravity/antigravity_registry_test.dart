import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_settings_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('antigravity registers the ACP vertical slice plus headless', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    final def = registry.tryGet(CliTool.antigravity);
    expect(def, isNotNull, reason: 'antigravity must be registered');
    expect(def!.isLaunchSupported, isTrue);

    final exe = registry.capability<CliExecutableCapability>(
      CliTool.antigravity,
    );
    expect(exe, isNotNull);
    expect(exe!.defaultExecutableName, 'agy');
    expect(exe.supportsInstaller, isTrue);

    expect(
      registry.capability<AcpCapability>(CliTool.antigravity),
      isNotNull,
      reason: 'ACP is the only launch mode',
    );
    expect(
      registry.capability<HeadlessCapability>(CliTool.antigravity),
      isNotNull,
      reason: 'agy -p one-shot runs are supported',
    );
    expect(registry.capability<McpCapability>(CliTool.antigravity), isNotNull);

    final acpSettings = registry.capability<AcpSettingsCapability>(
      CliTool.antigravity,
    );
    expect(acpSettings, isNotNull);
    expect(acpSettings!.usesSeparateAdapter, isTrue);
    expect(acpSettings.adapterExecutableName, isNotNull);
    expect(acpSettings.showsPersonalAcpSwitch, isFalse);

    final transport = registry.capability<CliTransportCapability>(
      CliTool.antigravity,
    );
    expect(transport, isNotNull);
    expect(transport!.supports(CliTransport.acp), isTrue);
    expect(transport.supports(CliTransport.pty), isFalse);
    expect(registry.launchesAcpOnly(CliTool.antigravity), isTrue);
  });

  test('antigravity stays out of native-team and member-agent-preset sets', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    expect(registry.supportsNativeTeam(CliTool.antigravity), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.antigravity), isFalse);
  });
}
