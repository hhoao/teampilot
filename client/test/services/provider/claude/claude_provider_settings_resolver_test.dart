import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/cli/claude/provider/claude_provider_settings_resolver.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late AppProviderRepository repository;
  late ClaudeProviderSettingsResolver resolver;
  const base = '/data/tp';

  const thirdPartyPreset = CliPreset(
    id: 'preset-third',
    name: 'Third',
    cli: CliTool.claude,
    provider: 'third-party',
    model: 'third-model',
    createdAt: 0,
    updatedAt: 0,
  );

  setUp(() {
    fs = InMemoryFilesystem();
    repository = AppProviderRepository(basePath: base, fs: fs);
    resolver = ClaudeProviderSettingsResolver(
      basePath: base,
      repository: repository,
    );
  });

  Future<void> seedProviders() async {
    await repository.saveProviders(CliTool.claude, [
      const AppProviderConfig(
        id: 'official',
        cli: CliTool.claude,
        name: 'Official',
        category: AppProviderCategory.official,
      ),
      const AppProviderConfig(
        id: 'third-party',
        cli: CliTool.claude,
        name: 'Third',
        category: AppProviderCategory.thirdParty,
        apiKey: 'third-token',
        baseUrl: 'https://api.third.example/anthropic',
      ),
    ]);
  }

  test('resolveProviderId uses preset provider when shape is preset', () async {
    await seedProviders();

    final team = TeamProfile(
      id: 't',
      name: 'T',
      cli: CliTool.claude,
      activePresetId: 'preset-third',
      providerIdsByTool: {'claude': 'official'},
    ).normalizedLaunchConfig();

    expect(
      await resolver.resolveProviderId(
        team,
        globalPresets: const [thirdPartyPreset],
      ),
      'third-party',
    );
  });

  test('resolveTeamClaudeSettings uses preset provider when shape is preset', () async {
    await seedProviders();

    final team = TeamProfile(
      id: 't',
      name: 'T',
      cli: CliTool.claude,
      activePresetId: 'preset-third',
      providerIdsByTool: {'claude': 'official'},
    ).normalizedLaunchConfig();

    final settings = await resolver.resolveTeamClaudeSettings(
      team,
      globalPresets: const [thirdPartyPreset],
    );
    final env = settings?['env'] as Map?;
    expect(
      env?['ANTHROPIC_API_KEY'] ?? env?['ANTHROPIC_AUTH_TOKEN'],
      'third-token',
    );
    expect(env?['ANTHROPIC_BASE_URL'], 'https://api.third.example/anthropic');
  });

  test('resolveProviderId uses custom maps when shape is custom', () async {
    await seedProviders();

    const team = TeamProfile(
      id: 't',
      name: 'T',
      cli: CliTool.claude,
      providerIdsByTool: {'claude': 'official'},
    );

    expect(await resolver.resolveProviderId(team), 'official');
  });

  test('resolveMemberClaudeSettings prefers launch-resolved member provider', () async {
    await seedProviders();

    const team = TeamProfile(
      id: 't',
      name: 'T',
      cli: CliTool.claude,
      activePresetId: 'preset-third',
    );
    final normalized = team.normalizedLaunchConfig();

    const member = TeamMemberConfig(
      id: 'developer-0',
      name: 'developer #0',
      provider: 'third-party',
      model: 'third-model',
    );

    final settings = await resolver.resolveMemberClaudeSettings(
      team: normalized,
      member: member,
      globalPresets: const [thirdPartyPreset],
    );
    final env = settings?['env'] as Map?;
    expect(
      env?['ANTHROPIC_API_KEY'] ?? env?['ANTHROPIC_AUTH_TOKEN'],
      'third-token',
    );
  });
}
