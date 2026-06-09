import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/cursor/cursor_provider_settings_resolver.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late AppProviderRepository repository;
  late CursorProviderSettingsResolver resolver;
  const base = '/data/tp';

  setUp(() {
    fs = InMemoryFilesystem();
    repository = AppProviderRepository(basePath: base, fs: fs);
    resolver = CursorProviderSettingsResolver(
      basePath: base,
      repository: repository,
    );
  });

  Future<void> seedCursorProviders(List<AppProviderConfig> providers) async {
    await repository.saveProviders(CliTool.cursor, providers);
  }

  test('resolveProviderId prefers member provider over team binding', () async {
    await seedCursorProviders([
      const AppProviderConfig(id: 'member-p', cli: CliTool.cursor, name: 'Member'),
      const AppProviderConfig(id: 'team-p', cli: CliTool.cursor, name: 'Team'),
    ]);

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      providerIdsByTool: {'cursor': 'team-p'},
      members: [
        TeamMemberConfig(id: 'worker', name: 'worker', provider: 'member-p'),
      ],
    );
    const member = TeamMemberConfig(
      id: 'worker',
      name: 'worker',
      provider: 'member-p',
    );

    expect(
      await resolver.resolveProviderId(team, member: member),
      'member-p',
    );
  });

  test('resolveProviderId falls back to team cursor binding', () async {
    await seedCursorProviders([
      const AppProviderConfig(id: 'team-p', cli: CliTool.cursor, name: 'Team'),
    ]);

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      providerIdsByTool: {'cursor': 'team-p'},
      members: [TeamMemberConfig(id: 'worker', name: 'worker')],
    );

    expect(await resolver.resolveProviderId(team), 'team-p');
  });

  test('resolveProviderId falls back to roster member provider', () async {
    await seedCursorProviders([
      const AppProviderConfig(id: 'roster-p', cli: CliTool.cursor, name: 'Roster'),
    ]);

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      members: [
        TeamMemberConfig(id: 'lead', name: 'lead'),
        TeamMemberConfig(id: 'worker', name: 'worker', provider: 'roster-p'),
      ],
    );

    expect(await resolver.resolveProviderId(team), 'roster-p');
  });

  test('resolveProviderId auto-picks sole cursor provider', () async {
    await seedCursorProviders([
      const AppProviderConfig(id: 'only', cli: CliTool.cursor, name: 'Only'),
    ]);

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      members: [TeamMemberConfig(id: 'worker', name: 'worker')],
    );

    expect(await resolver.resolveProviderId(team), 'only');
  });

  test('resolveProviderId returns null when ambiguous', () async {
    await seedCursorProviders([
      const AppProviderConfig(id: 'a', cli: CliTool.cursor, name: 'A'),
      const AppProviderConfig(id: 'b', cli: CliTool.cursor, name: 'B'),
    ]);

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      members: [TeamMemberConfig(id: 'worker', name: 'worker')],
    );

    expect(await resolver.resolveProviderId(team), isNull);
  });

  test('resolveForLaunch returns member provider config', () async {
    await seedCursorProviders([
      const AppProviderConfig(
        id: 'member-p',
        cli: CliTool.cursor,
        name: 'Member',
        baseUrl: 'https://api.example.com',
      ),
      const AppProviderConfig(id: 'team-p', cli: CliTool.cursor, name: 'Team'),
    ]);

    const team = TeamConfig(
      id: 't1',
      name: 'T1',
      providerIdsByTool: {'cursor': 'team-p'},
      members: [
        TeamMemberConfig(id: 'worker', name: 'worker', provider: 'member-p'),
      ],
    );
    const member = TeamMemberConfig(
      id: 'worker',
      name: 'worker',
      provider: 'member-p',
    );

    final config = await resolver.resolveForLaunch(team: team, member: member);
    expect(config?.id, 'member-p');
    expect(config?.baseUrl, 'https://api.example.com');
  });

  test('findById ignores unknown provider ids', () async {
    await seedCursorProviders([
      const AppProviderConfig(id: 'known', cli: CliTool.cursor, name: 'Known'),
    ]);

    expect(await resolver.findById('known'), isNotNull);
    expect(await resolver.findById('missing'), isNull);
    expect(await resolver.findById(''), isNull);
    expect(await resolver.findById(null), isNull);
  });
}
