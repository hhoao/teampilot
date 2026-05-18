import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/config_profile_service.dart';

void main() {
  late Directory base;
  late ConfigProfileService service;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cfg_profile_');
    service = ConfigProfileService(basePath: base.path);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test(
    'ensureTeamProfile for flashskyai creates flashskyai dir and metadata only',
    () async {
      await service.ensureTeamProfile('team-a', cli: TeamCli.flashskyai);

      final teamRoot = Directory(
        p.join(base.path, 'config-profiles', 'teams', 'team-a'),
      );
      expect(await teamRoot.exists(), isTrue);
      expect(
        await Directory(p.join(teamRoot.path, 'flashskyai')).exists(),
        isTrue,
      );
      expect(await Directory(p.join(teamRoot.path, 'codex')).exists(), isFalse);
      expect(
        await Directory(p.join(teamRoot.path, 'claude')).exists(),
        isFalse,
      );

      final metadata = File(
        p.join(
          teamRoot.path,
          'flashskyai',
          ConfigProfileService.flashskyaiMetadataFileName,
        ),
      );
      expect(await metadata.exists(), isTrue);
      final decoded =
          jsonDecode(await metadata.readAsString()) as Map<String, Object?>;
      expect(decoded['hasCompletedOnboarding'], isTrue);
    },
  );

  test('ensureTeamProfile for codex creates codex dir only', () async {
    await service.ensureTeamProfile('team-a', cli: TeamCli.codex);

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
    expect(await Directory(p.join(teamRoot, 'codex')).exists(), isTrue);
    expect(
      await Directory(p.join(teamRoot, 'flashskyai')).exists(),
      isFalse,
    );
  });

  test('does not overwrite existing team flashskyai metadata', () async {
    final metadata = File(
      p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'flashskyai',
        ConfigProfileService.flashskyaiMetadataFileName,
      ),
    );
    await metadata.parent.create(recursive: true);
    await metadata.writeAsString('{"hasCompletedOnboarding":false}');

    await service.ensureTeamProfile('team-a', cli: TeamCli.flashskyai);

    expect(await metadata.readAsString(), '{"hasCompletedOnboarding":false}');
  });

  test('prepareTeamLaunch for flashskyai returns flashskyai env only', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.flashskyai,
    );

    final commonFlashDir = p.join(
      base.path,
      'config-profiles',
      'common',
      'flashskyai',
    );
    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');

    expect(await Directory(commonFlashDir).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'flashskyai')).exists(), isTrue);
    expect(await Directory(p.join(teamRoot, 'codex')).exists(), isFalse);
    expect(env.keys, ['FLASHSKYAI_CONFIG_DIR', 'LLM_CONFIG_PATH']);
    expect(env['FLASHSKYAI_CONFIG_DIR'], p.join(teamRoot, 'flashskyai'));
    expect(env['LLM_CONFIG_PATH'], p.join(commonFlashDir, 'llm_config.json'));

    final metadata = File(
      p.join(
        teamRoot,
        'flashskyai',
        ConfigProfileService.flashskyaiMetadataFileName,
      ),
    );
    expect(await metadata.exists(), isTrue);
  });

  test('prepareTeamLaunch for codex returns CODEX_HOME only', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.codex,
    );

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
    expect(env.keys, ['CODEX_HOME']);
    expect(env['CODEX_HOME'], p.join(teamRoot, 'codex'));
    expect(
      File(p.join(env['CODEX_HOME']!, 'auth.json')).existsSync(),
      isFalse,
    );
  });

  test('prepareTeamLaunch for claude returns CLAUDE_CONFIG_DIR only', () async {
    final env = await service.prepareTeamLaunch(
      teamId: 'team-a',
      cli: TeamCli.claude,
    );

    final teamRoot = p.join(base.path, 'config-profiles', 'teams', 'team-a');
    expect(env.keys, ['CLAUDE_CONFIG_DIR']);
    expect(env['CLAUDE_CONFIG_DIR'], p.join(teamRoot, 'claude'));
  });
}
