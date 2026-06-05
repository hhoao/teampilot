import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late InMemoryFilesystem fs;
  late ConfigProfileService service;
  late AppProviderRepository repository;
  const base = '/data/tp';

  setUp(() {
    setUpTestAppStorage();
    fs = InMemoryFilesystem();
    service = ConfigProfileService(basePath: base, fs: fs);
    repository = AppProviderRepository(basePath: base, fs: fs);
  });

  tearDown(() => tearDownTestAppStorage());

  TeamConfig teamWithProvider(String teamId, String providerId) => TeamConfig(
    id: teamId,
    name: teamId,
    cli: CliTool.claude,
    providerIdsByTool: {'claude': providerId},
  );

  Future<void> seedOfficialProvider(String id) async {
    await repository.saveProviders(CliTool.claude, [
      AppProviderConfig(
        id: id,
        cli: CliTool.claude,
        name: id,
        category: AppProviderCategory.official,
        config: const {'env': {}},
      ),
    ]);
  }

  test('official launch links provider credentials into session dir', () async {
    await repository.saveProviders(CliTool.claude, [
      const AppProviderConfig(
        id: 'work',
        cli: CliTool.claude,
        name: 'work',
        category: AppProviderCategory.official,
        config: {'env': {}},
      ),
      const AppProviderConfig(
        id: 'personal',
        cli: CliTool.claude,
        name: 'personal',
        category: AppProviderCategory.official,
        config: {'env': {}},
      ),
    ]);
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    await fs.writeString(
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'personal',
        '.credentials.json',
      ),
      '{"claudeAiOauth":{"accessToken":"personal"}}',
    );

    final workOutcome = await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: 'session-a',
      cli: CliTool.claude,
      team: teamWithProvider('team-a', 'work'),
    );
    final personalOutcome = await service.prepareTeamLaunch(
      teamId: 'team-b',
      runtimeTeamId: 'session-b',
      cli: CliTool.claude,
      team: teamWithProvider('team-b', 'personal'),
    );

    final workSessionDir = workOutcome.environment['CLAUDE_CONFIG_DIR']!;
    final personalSessionDir =
        personalOutcome.environment['CLAUDE_CONFIG_DIR']!;

    expect(
      fs.symlinks[fs.pathContext.join(workSessionDir, '.credentials.json')],
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
    );
    expect(
      fs.symlinks[fs.pathContext.join(personalSessionDir, '.credentials.json')],
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'personal',
        '.credentials.json',
      ),
    );
  });

  test('missing credentials adds launch warning without failing', () async {
    await seedOfficialProvider('work');

    final outcome = await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: 'session-a',
      cli: CliTool.claude,
      team: teamWithProvider('team-a', 'work'),
    );

    expect(outcome.warnings, contains('claude_credentials_missing'));
    expect(outcome.environment['CLAUDE_CONFIG_DIR'], isNotEmpty);
  });
}
