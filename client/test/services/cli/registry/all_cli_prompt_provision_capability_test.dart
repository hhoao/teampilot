import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('registry wiring all launch CLIs expose PromptCapability', () {
    final registry = CliToolRegistry.builtIn();
    const launchClis = {
      CliTool.claude,
      CliTool.flashskyai,
      CliTool.codex,
      CliTool.opencode,
      CliTool.cursor,
    };
    for (final cli in launchClis) {
      expect(
        registry.capability<PromptCapability>(cli),
        isNotNull,
        reason: '$cli must expose PromptCapability',
      );
    }
  });
}
