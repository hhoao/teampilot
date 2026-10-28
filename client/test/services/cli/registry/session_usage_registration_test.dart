import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('local transcript CLIs register usage extraction', () {
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
    expect(
      registry.capability<SessionUsageCapability>(CliTool.gemini),
      isNotNull,
    );
    expect(
      registry.capability<SessionUsageCapability>(CliTool.codebuddy),
      isNotNull,
    );
  });

  test('clis without transcript extraction stay null', () {
    final registry = CliToolRegistry.builtIn();

    // Cursor uses the dashboard import path instead of a session parser.
    expect(registry.capability<SessionUsageCapability>(CliTool.cursor), isNull);
    expect(
      registry.capability<SessionUsageCapability>(CliTool.flashskyai),
      isNull,
    );
  });
}
