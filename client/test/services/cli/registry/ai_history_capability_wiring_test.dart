import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('all launch CLIs expose AiHistoryCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in [
      CliTool.claude,
      CliTool.flashskyai,
      CliTool.codex,
      CliTool.opencode,
      CliTool.cursor,
    ]) {
      expect(
        registry.capability<AiHistoryCapability>(cli),
        isNotNull,
        reason: '$cli',
      );
    }
  });
}
