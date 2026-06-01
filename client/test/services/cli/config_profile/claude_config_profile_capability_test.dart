import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/registry/capabilities/config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
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
    const team = TeamConfig(id: 'team-a', name: 'agent', cli: TeamCli.claude);

    final scope = ConfigProfileService.resolveLaunchScope(
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
      const team = TeamConfig(
        id: 'team-a',
        name: 'agent',
        cli: TeamCli.claude,
        teamMode: TeamMode.mixed,
      );

      final scope = ConfigProfileService.resolveLaunchScope(
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
    },
  );
}
