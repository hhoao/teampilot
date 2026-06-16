import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

void main() {
  test('contributeLaunch returns FLASHSKYAI_CONFIG_DIR for valid member', () async {
    final base = await Directory.systemTemp.createTemp('flashskyai_cap_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const capability = FlashskyaiConfigProfileCapability();
    const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');

    final scope = resolveLaunchProfileScope(
      projectId: 'project-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final contribution = await capability.contributeLaunch(
      ConfigProfileLaunchContext(
        projectId: 'project-1',
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        member: member,
        members: const [member],
        workingDirectory: '/workspace/project',
        paths: service,
      ),
    );

    final expectedDir = p.join(
      base.path,
      'workspace',
      'projects',
      'project-1',
      'sessions',
      'session-1',
      'runtime',
      'flashskyai',
    );
    expect(
      contribution.environment[FlashskyaiConfigProfileCapability.configDirEnvKey],
      expectedDir,
    );
  });

  test('mixed member gets a Stop /idle hook redirecting to the bus', () async {
    final base = await Directory.systemTemp.createTemp('flashskyai_cap_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const capability = FlashskyaiConfigProfileCapability();
    const member = TeamMemberConfig(id: 'm1', name: 'Member');
    const team = TeamConfig(
      id: 'team-a',
      name: 'Team A',
      teamMode: TeamMode.mixed,
      members: [member],
    );

    final scope = resolveLaunchProfileScope(
      projectId: 'project-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    await capability.contributeLaunch(
      ConfigProfileLaunchContext(
        projectId: 'project-1',
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        team: team,
        member: member,
        members: const [member],
        workingDirectory: '/workspace/project',
        paths: service,
        busIdleUrl: 'http://127.0.0.1:54321/idle',
      ),
    );

    final settingsPath = p.join(
      base.path,
      'workspace',
      'projects',
      'project-1',
      'sessions',
      'session-1',
      'runtime',
      'm1',
      'flashskyai',
      'settings.json',
    );
    final settings =
        jsonDecode(await File(settingsPath).readAsString()) as Map;
    final stop = (settings['hooks'] as Map)['Stop'] as List;
    final urls = [
      for (final entry in stop)
        for (final h in (entry as Map)['hooks'] as List) (h as Map)['url'],
    ];
    expect(urls, contains('http://127.0.0.1:54321/idle'));
  });
}
