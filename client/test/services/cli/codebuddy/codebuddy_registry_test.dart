import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_settings_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('codebuddy registers all required capabilities on the built-in '
      'registry', () {
    // registerBuiltInCliTools asserts every CliTool registers Provider /
    // MemberConfigInspection / CliSession / TeamBehavior / CliExecutable /
    // TerminalBehavior / Plugin / ChatInteraction / RuntimeEvent — reaching
    // the expects below means they passed.
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final def = registry.tryGet(CliTool.codebuddy);
    expect(def, isNotNull, reason: 'codebuddy must be registered');
    expect(def!.isLaunchSupported, isTrue);

    final exe = registry.capability<CliExecutableCapability>(CliTool.codebuddy);
    expect(exe, isNotNull);
    expect(exe!.defaultExecutableName, 'codebuddy');
    expect(exe.supportsInstaller, isTrue);

    expect(
      registry.capability<AcpCapability>(CliTool.codebuddy),
      isNotNull,
      reason: 'ACP is the only launch mode',
    );
    expect(
      registry.capability<HeadlessCapability>(CliTool.codebuddy),
      isNotNull,
    );
    expect(registry.capability<McpCapability>(CliTool.codebuddy), isNotNull);

    final acpSettings = registry.capability<AcpSettingsCapability>(
      CliTool.codebuddy,
    );
    expect(acpSettings, isNotNull);
    expect(acpSettings!.usesSeparateAdapter, isFalse);
    expect(acpSettings.showsPersonalAcpSwitch, isFalse);
  });

  test('codebuddy stays out of native-team and member-agent-preset sets', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    expect(registry.supportsNativeTeam(CliTool.codebuddy), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.codebuddy), isFalse);
  });
}
