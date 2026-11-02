import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every launch-supported tool exposes AiHistoryCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in CliTool.values) {
      final def = registry.tryGet(tool);
      expect(def, isNotNull, reason: '$tool missing from built-in registry');
      if (!def!.isLaunchSupported) continue;
      final cap = registry.capability<AiHistoryCapability>(tool);
      expect(cap, isNotNull, reason: '$tool missing AiHistoryCapability');
      expect(cap!.adapter.id, isNotEmpty);
    }
  });
}
