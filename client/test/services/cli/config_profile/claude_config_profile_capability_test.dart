import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

void main() {
  test('contributeLaunch sets agent-teams env in native mode', () async {
    final base = await Directory.systemTemp.createTemp('claude_cap_native_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: CliDataLayout(teampilotRoot: base.path, fs: fs),
    );
    const capability = ClaudeConfigProfileCapability();
    const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
    const team = TeamConfig(id: 'team-a', name: 'agent', cli: CliTool.claude);

    final scope = resolveLaunchProfileScope(
      teamId: 'team-a',
      runtimeTeamId: 'session-1',
    );

    final contribution = await capability.contributeLaunch(
      ConfigProfileLaunchContext(
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        team: team,
        member: member,
        members: const [member],
        workingDirectory: '/workspace/project',
        paths: service,
      ),
    );

    expect(
      contribution.environment['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'],
      '1',
    );
  });

  test(
    'contributeLaunch omits agent-teams env in mixed mode',
    () async {
      final base = await Directory.systemTemp.createTemp('claude_cap_mixed_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: CliDataLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = ClaudeConfigProfileCapability();
      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
      final repository = AppProviderRepository(basePath: base.path);
      await repository.saveProviders(CliTool.claude, [
        const AppProviderConfig(
          id: 'leaky',
          cli: CliTool.claude,
          name: 'leaky',
          category: AppProviderCategory.thirdParty,
          config: {
            'env': {
              'ANTHROPIC_BASE_URL': 'https://api.example.com/anthropic',
              'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
            },
            'teammateMode': 'in-process',
          },
        ),
      ]);
      const team = TeamConfig(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        providerIdsByTool: {'claude': 'leaky'},
      );

      final scope = resolveLaunchProfileScope(
        teamId: 'team-a',
        runtimeTeamId: 'session-1',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/project',
          paths: service,
        ),
      );

      expect(
        contribution.environment,
        isNot(contains('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')),
      );
      expect(contribution.environment['CLAUDE_CODE_NO_FLICKER'], '1');

      // The member settings file must not re-enable agent-teams either: a
      // mixed member is a standalone process driven by the teammate-bus Stop
      // hook, and agent-teams mode would suppress that hook.
      final settingsPath = p.join(
        base.path,
        'config-profiles',
        'teams',
        'team-a',
        'members',
        'session-1',
        'claude',
        'settings',
        'm1.json',
      );
      final settings =
          jsonDecode(await File(settingsPath).readAsString()) as Map;
      expect(
        (settings['env'] as Map),
        isNot(contains('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')),
      );
      expect(settings.containsKey('teammateMode'), isFalse);
      expect(
        (settings['hooks'] as Map?)?['Stop'],
        isNull,
        reason: 'no idle URL passed → no Stop hook here',
      );
    },
  );
}
