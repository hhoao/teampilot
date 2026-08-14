import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('all launchable CLIs expose Ctrl+C turn interrupt', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in registry.launchable) {
      final cap = registry.capability<TerminalBehaviorCapability>(tool.id);
      expect(cap, isNotNull, reason: tool.id.name);
      expect(cap!.supportsTurnInterrupt, isTrue);
      expect(cap.interruptPlan.steps, ['\x03']);
    }
  });
}
