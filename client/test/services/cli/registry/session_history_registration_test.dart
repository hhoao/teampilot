import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/session/ai_history_providers.dart';

void main() {
  test('every launch-supported tool has an AiHistoryProvider', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in CliTool.values) {
      final def = registry.tryGet(tool);
      expect(def, isNotNull, reason: '$tool missing from built-in registry');
      if (!def!.isLaunchSupported) continue;
      expect(
        kAiHistoryProviders.containsKey(tool),
        isTrue,
        reason: '$tool missing from kAiHistoryProviders',
      );
      expect(kAiHistoryProviders[tool]!.adapter.id, isNotEmpty);
    }
  });

  test('defaultAdapters mirror kAiHistoryProviders', () {
    final adapters = aiHistoryDefaultAdapters();
    expect(adapters.keys.toSet(), kAiHistoryProviders.keys.toSet());
    for (final tool in kAiHistoryProviders.keys) {
      expect(adapters[tool], same(kAiHistoryProviders[tool]!.adapter));
    }
  });
}
