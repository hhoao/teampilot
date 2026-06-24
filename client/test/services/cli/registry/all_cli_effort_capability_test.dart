import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_effort_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_config_profile_capability.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';
import 'package:teampilot/services/provider/flashskyai/flashskyai_effort_capability.dart';
import 'package:teampilot/services/provider/opencode/opencode_effort_capability.dart';

void main() {
  test('built-in registry registers effort on all five CLIs', () {
    final registry = CliToolRegistry.builtIn();
    for (final tool in CliTool.values) {
      if (!registry.tryGet(tool)!.isLaunchSupported) continue;
      expect(
        registry.capability<CliEffortCapability>(tool),
        isNotNull,
        reason: tool.name,
      );
    }
  });

  test('OpencodeEffortCapability uses provider placement', () {
    const capability = OpencodeEffortCapability();
    const provider = AppProviderConfig(
      id: 'p1',
      cli: CliTool.opencode,
      name: 'P',
      defaultModel: 'gpt-5',
    );
    expect(capability.providerPickerPlacement(provider),
        EffortPickerPlacement.provider);
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
    final providerEntry =
        (merged['provider'] as Map)['anthropic'] as Map;
    final modelEntry =
        (providerEntry['models'] as Map)['claude-sonnet-4-20250514'] as Map;
    final options = modelEntry['options'] as Map;
    expect(options['reasoningEffort'], 'high');
  });

  test('cursor adapter emits reasoning effort flag', () {
    const adapter = CursorCliToolAdapter();
    final team = TeamProfile(
      id: 't1',
      name: 'Team',
      cli: CliTool.cursor,
      members: const [],
      cliEffortLevels: const {'cursor': 'low'},
    );
    final member = TeamMemberConfig(
      id: 'm1',
      name: 'M',
      model: 'gpt-5',
    );
    final args = adapter.buildArguments(
      CliLaunchContext(team: team, member: member),
    );
    expect(args, containsAll(['--reasoning-effort', 'low']));
  });

  test('FlashskyaiEffortCapability mirrors Claude placement', () {
    const capability = FlashskyaiEffortCapability();
    expect(capability.teamPickerPlacement(), EffortPickerPlacement.team);
    expect(
      capability.memberPickerPlacement(),
      EffortPickerPlacement.member,
    );
    expect(capability.isApplicable(model: 'sonnet'), isTrue);
  });
}
