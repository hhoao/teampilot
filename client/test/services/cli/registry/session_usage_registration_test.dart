import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('claude, codex, and opencode register usage extraction', () {
    final registry = CliToolRegistry.builtIn();

    expect(
      registry.capability<SessionUsageCapability>(CliTool.claude),
      isNotNull,
    );
    expect(
      registry.capability<SessionUsageCapability>(CliTool.codex),
      isNotNull,
    );
    expect(
      registry.capability<SessionUsageCapability>(CliTool.opencode),
      isNotNull,
    );
  });

  test('clis without extraction stay null', () {
    final registry = CliToolRegistry.builtIn();

    expect(registry.capability<SessionUsageCapability>(CliTool.cursor), isNull);
    expect(registry.capability<SessionUsageCapability>(CliTool.gemini), isNull);
  });
}
