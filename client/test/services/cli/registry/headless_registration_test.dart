import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_run_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every supported CLI exposes a HeadlessRunCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in [
      CliTool.claude,
      CliTool.codex,
      CliTool.cursor,
      CliTool.opencode,
      CliTool.flashskyai,
    ]) {
      final cap = registry.capability<HeadlessRunCapability>(cli);
      expect(cap, isNotNull, reason: '${cli.value} missing HeadlessRunCapability');
      expect(cap!.isSupported, isTrue);
    }
  });
}
