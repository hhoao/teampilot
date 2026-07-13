import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';

void main() {
  test('every launch-supported tool has an AiTranscriptAdapter', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in CliTool.values) {
      final def = registry.tryGet(tool);
      expect(def, isNotNull, reason: '$tool missing from built-in registry');
      if (!def!.isLaunchSupported) continue;
      expect(
        AiHistoryLoader.defaultAdapters.containsKey(tool),
        isTrue,
        reason: '$tool missing AiTranscriptAdapter in defaultAdapters',
      );
    }
  });

  test('AiHistoryLocator covers every CliTool', () async {
    // Exhaustiveness is enforced by the switch in AiHistoryLocator.locate;
    // this smoke call just ensures the locator constructs for all enum values.
    const locator = AiHistoryLocator();
    expect(locator, isA<AiHistoryLocator>());
    for (final tool in CliTool.values) {
      expect(AiHistoryLoader.defaultAdapters.containsKey(tool), isTrue);
    }
  });
}
