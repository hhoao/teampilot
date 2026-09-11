import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('gemini registers all required capabilities on the built-in registry',
      () {
    // registerBuiltInCliTools asserts every CliTool (incl. gemini) registers
    // Provider / MemberConfigInspection / CliSession / TeamBehavior /
    // CliExecutable / TerminalBehavior / Plugin / ChatInteraction /
    // RuntimeEvent capabilities — reaching the expects below means they passed.
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final def = registry.tryGet(CliTool.gemini);
    expect(def, isNotNull, reason: 'gemini must be registered');
    expect(def!.isLaunchSupported, isTrue);

    final exe = registry.capability<CliExecutableCapability>(CliTool.gemini);
    expect(exe, isNotNull);
    expect(exe!.defaultExecutableName, 'gemini');
    expect(exe.supportsInstaller, isTrue);
  });

  test('gemini stays out of native-team and member-agent-preset allowed sets',
      () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    expect(registry.supportsNativeTeam(CliTool.gemini), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.gemini), isFalse);
  });
}
