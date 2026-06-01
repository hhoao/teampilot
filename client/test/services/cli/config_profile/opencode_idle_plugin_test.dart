import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/registry/capabilities/config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_idle_plugin.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

void main() {
  test('parseBusPortFromIdleUrl extracts port from idle endpoint', () {
    expect(
      parseBusPortFromIdleUrl('http://127.0.0.1:12345/idle'),
      12345,
    );
    expect(parseBusPortFromIdleUrl(null), isNull);
    expect(parseBusPortFromIdleUrl(''), isNull);
  });

  test(
    'mixed contributeLaunch writes idle plugin and opencode.json entry',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_idle_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: CliDataLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = OpencodeConfigProfileCapability();
      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
      const team = TeamConfig(
        id: 'team-a',
        name: 'agent',
        cli: TeamCli.opencode,
        teamMode: TeamMode.mixed,
      );

      final scope = ConfigProfileService.resolveLaunchScope(
        teamId: 'team-a',
        runtimeTeamId: 'session-1',
      );

      await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          paths: service,
          busIdleUrl: 'http://127.0.0.1:54321/idle',
        ),
      );

      final opencodeDir = service.sessionToolDir(
        scope.teamId,
        scope.sessionId,
        'opencode',
      );
      final pluginPath = '$opencodeDir/$opencodeIdlePluginFileName';
      expect(await fs.stat(pluginPath), isNotNull);
      expect(await fs.readString(pluginPath), opencodeIdlePluginSource);

      final configPath = '$opencodeDir/${OpencodeConfigProfileCapability.opencodeConfigFileName}';
      final raw = await fs.readString(configPath);
      expect(raw, isNotNull);
      final config = jsonDecode(raw!) as Map<String, dynamic>;
      final plugin = config['plugin'] as List;
      expect(plugin, hasLength(1));
      final entry = plugin.first as List;
      expect(entry[0], './$opencodeIdlePluginFileName');
      final opts = entry[1] as Map;
      expect(opts['member'], 'm1');
      expect(opts['port'], 54321);
    },
  );
}
