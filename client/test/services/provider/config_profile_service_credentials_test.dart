import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/claude_provider_credentials_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ConfigProfileService service;
  late ClaudeProviderCredentialsService credentials;
  const base = '/data/tp';

  setUp(() {
    fs = InMemoryFilesystem();
    credentials = ClaudeProviderCredentialsService(fs: fs, basePath: base);
    service = ConfigProfileService(
      basePath: base,
      fs: fs,
      claudeCredentialsService: credentials,
    );
  });

  test('official launch links provider credentials into session dir', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'personal', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"personal"}}',
    );

    final workOutcome = await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: 'session-a',
      cli: TeamCli.claude,
      claudeSettings: const {'env': {}},
      claudeProviderId: 'work',
    );
    final personalOutcome = await service.prepareTeamLaunch(
      teamId: 'team-b',
      runtimeTeamId: 'session-b',
      cli: TeamCli.claude,
      claudeSettings: const {'env': {}},
      claudeProviderId: 'personal',
    );

    final workSessionDir = workOutcome.environment['CLAUDE_CONFIG_DIR']!;
    final personalSessionDir = personalOutcome.environment['CLAUDE_CONFIG_DIR']!;

    expect(
      fs.symlinks[fs.pathContext.join(workSessionDir, '.credentials.json')],
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
    );
    expect(
      fs.symlinks[fs.pathContext.join(personalSessionDir, '.credentials.json')],
      fs.pathContext.join(base, 'providers', 'claude', 'personal', '.credentials.json'),
    );
  });

  test('missing credentials adds launch warning without failing', () async {
    final outcome = await service.prepareTeamLaunch(
      teamId: 'team-a',
      runtimeTeamId: 'session-a',
      cli: TeamCli.claude,
      claudeSettings: const {'env': {}},
      claudeProviderId: 'work',
    );

    expect(outcome.warnings, contains('claude_credentials_missing'));
    expect(outcome.environment['CLAUDE_CONFIG_DIR'], isNotEmpty);
  });
}
