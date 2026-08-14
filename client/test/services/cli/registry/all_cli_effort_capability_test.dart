import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/opencode/capabilities/config_profile.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/provider.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';

void main() {
  test('built-in registry registers effort on CLIs that support it', () {
    final registry = CliToolRegistry.builtIn();
    const withEffort = {
      CliTool.claude,
      CliTool.codex,
      CliTool.opencode,
      CliTool.flashskyai,
    };
    for (final tool in withEffort) {
      expect(
        registry.capability<ProviderCapability>(tool),
        isNotNull,
        reason: tool.name,
      );
    }
    final cursor = registry.capability<ProviderCapability>(CliTool.cursor)!;
    expect(cursor.teamPickerPlacement(), EffortPickerPlacement.hidden);
    expect(cursor.memberPickerPlacement(), EffortPickerPlacement.hidden);
    expect(cursor.isApplicable(model: 'gpt-5'), isFalse);
  });

  test('OpencodeEffortCapability uses provider placement', () {
    const capability = OpencodeProviderCapability();
    const provider = AppProviderConfig(
      id: 'p1',
      cli: CliTool.opencode,
      name: 'P',
      defaultModel: 'gpt-5',
    );
    expect(
      capability.providerPickerPlacement(provider),
      EffortPickerPlacement.provider,
    );
    expect(capability.teamPickerPlacement(), EffortPickerPlacement.hidden);
    expect(capability.isApplicable(model: 'gpt-5'), isTrue);
    expect(capability.isApplicable(model: 'gpt-4o'), isFalse);
  });

  test('mergeOpencodeReasoningEffort writes model-scoped options', () {
    const provider = AppProviderConfig(
      id: 'anthropic',
      cli: CliTool.opencode,
      name: 'Anthropic',
      defaultModel: 'claude-sonnet-4-20250514',
    );
    final merged = mergeOpencodeReasoningEffort(
      const {},
      provider,
      'high',
      memberModel: 'claude-sonnet-4-20250514',
    );
    final providerEntry = (merged['provider'] as Map)['anthropic'] as Map;
    final modelEntry =
        (providerEntry['models'] as Map)['claude-sonnet-4-20250514'] as Map;
    final options = modelEntry['options'] as Map;
    expect(options['reasoningEffort'], 'high');
  });

  test('FlashskyaiEffortCapability mirrors Claude placement', () {
    const capability = FlashskyaiProviderCapability();
    expect(capability.teamPickerPlacement(), EffortPickerPlacement.team);
    expect(capability.memberPickerPlacement(), EffortPickerPlacement.member);
    expect(capability.isApplicable(model: 'sonnet'), isTrue);
  });
}
