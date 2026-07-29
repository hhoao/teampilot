import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/compose/compose_prompt_enhance.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  const providers = AppProviderState(
    providersByCli: {
      CliTool.claude: [
        AppProviderConfig(
          id: 'claude-official',
          cli: CliTool.claude,
          name: 'Official',
          defaultModel: 'sonnet',
        ),
      ],
      CliTool.cursor: [
        AppProviderConfig(
          id: 'cursor-account',
          cli: CliTool.cursor,
          name: 'Cursor Account',
          defaultModel: 'gpt',
        ),
      ],
    },
    selectedProviderIdByCli: {
      CliTool.claude: 'claude-official',
      CliTool.cursor: 'cursor-account',
    },
  );

  const presets = [
    CliPreset(
      id: 'preset-a',
      name: 'Fast',
      cli: CliTool.claude,
      provider: 'claude-official',
      model: 'sonnet',
      createdAt: 1,
      updatedAt: 1,
    ),
  ];

  const teams = [
    TeamProfile(
      id: 'team-1',
      name: 'Core',
      cli: CliTool.claude,
      providerIdsByTool: {'claude': 'claude-official'},
      modelsByTool: {'claude': 'sonnet'},
    ),
  ];

  test('buildComposeEnhancePrompt includes draft text', () {
    final prompt = buildComposeEnhancePrompt('fix the login bug');
    expect(prompt, contains('fix the login bug'));
    expect(prompt, contains('Output ONLY the improved prompt'));
  });

  test('cleanComposeEnhanceOutput strips code fences', () {
    expect(
      cleanComposeEnhanceOutput('```\nBetter prompt here\n```'),
      'Better prompt here',
    );
  });

  test('resolveLandingEnhanceSetting returns null when personal has no presets',
      () {
    expect(
      resolveLandingEnhanceSetting(
        draft: const LandingLaunchContext(isPersonal: true),
        presets: const [],
        teams: const [],
        appProviders: providers,
        registry: registry,
      ),
      isNull,
    );
  });

  test('resolveLandingEnhanceSetting uses selected personal preset', () {
    final setting = resolveLandingEnhanceSetting(
      draft: const LandingLaunchContext(
        isPersonal: true,
        presetId: 'preset-a',
      ),
      presets: presets,
      teams: const [],
      appProviders: providers,
      registry: registry,
    );

    expect(setting, isNotNull);
    expect(setting!.cli, CliTool.claude);
    expect(setting.providerId, 'claude-official');
    expect(setting.model, 'sonnet');
  });

  test('resolveLandingEnhanceSetting uses custom cli/provider when presetId empty',
      () {
    final setting = resolveLandingEnhanceSetting(
      draft: const LandingLaunchContext(
        isPersonal: true,
        cli: CliTool.cursor,
        provider: 'cursor-account',
        model: 'gpt',
      ),
      presets: const [],
      teams: const [],
      appProviders: providers,
      registry: registry,
    );

    expect(setting, isNotNull);
    expect(setting!.cli, CliTool.cursor);
    expect(setting.providerId, 'cursor-account');
    expect(setting.model, 'gpt');
  });

  test(
      'resolveLandingEnhanceSetting empty personal still falls back to first preset',
      () {
    final setting = resolveLandingEnhanceSetting(
      draft: const LandingLaunchContext(isPersonal: true),
      presets: presets,
      teams: const [],
      appProviders: providers,
      registry: registry,
    );

    expect(setting, isNotNull);
    expect(setting!.cli, CliTool.claude);
    expect(setting.providerId, 'claude-official');
    expect(setting.model, 'sonnet');
  });

  test('resolveLandingEnhanceSetting returns null when team has no provider',
      () {
    expect(
      resolveLandingEnhanceSetting(
        draft: const LandingLaunchContext(
          isPersonal: false,
          teamId: 'team-empty',
        ),
        presets: presets,
        teams: const [
          TeamProfile(id: 'team-empty', name: 'Empty', cli: CliTool.claude),
        ],
        appProviders: providers,
        registry: registry,
      ),
      isNull,
    );
  });

  test('resolveLandingEnhanceSetting uses selected team provider', () {
    final setting = resolveLandingEnhanceSetting(
      draft: const LandingLaunchContext(
        isPersonal: false,
        teamId: 'team-1',
      ),
      presets: presets,
      teams: teams,
      appProviders: providers,
      registry: registry,
    );

    expect(setting, isNotNull);
    expect(setting!.cli, CliTool.claude);
    expect(setting.providerId, 'claude-official');
    expect(setting.model, 'sonnet');
  });
}
