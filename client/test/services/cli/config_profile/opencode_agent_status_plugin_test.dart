import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_agent_status_plugin.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('mergeOpencodeAgentStatusPlugin adds plugin entry with url', () {
    final merged = mergeOpencodeAgentStatusPlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
      sessionId: 'session-1',
    );
    final plugin = merged['plugin'] as List;
    expect(plugin, hasLength(1));
    final entry = plugin.first as List;
    expect(entry[0], './$opencodeAgentStatusPluginFileName');
    final opts = entry[1] as Map;
    expect(opts['member'], 'm1');
    expect(opts['url'], 'http://127.0.0.1:12345/agent-status');
    expect(opts['session'], 'session-1');
  });

  test('mergeOpencodeAgentStatusPlugin is idempotent for same url', () {
    final once = mergeOpencodeAgentStatusPlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
    );
    final twice = mergeOpencodeAgentStatusPlugin(
      once,
      'm1',
      'http://127.0.0.1:12345/agent-status',
    );
    expect(twice['plugin'], hasLength(1));
  });

  test(
    'contributeLaunch writes agent-status plugin when agentStatus is set',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_status_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const capability = OpencodeConfigProfileCapability();
      const member = TeamMemberConfig(id: 'm1', name: 'Member', model: 'test');
      // Native (non-mixed) team — status must still install.
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.opencode,
        teamMode: TeamMode.native,
      );

      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          team: team,
          member: member,
          members: const [member],
          paths: service,
          catalog: service,
          agentStatus: const MemberAgentStatusEndpoint(
            url: 'http://127.0.0.1:12345/agent-status',
            sessionId: 'session-1',
          ),
        ),
      );

      final opencodeDir = service.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        'opencode',
        memberId: scope.memberId,
      );
      final pluginPath = '$opencodeDir/$opencodeAgentStatusPluginFileName';
      expect(await fs.stat(pluginPath), isNotNull);
      final source = await fs.readString(pluginPath);
      expect(source, opencodeAgentStatusPluginSource);
      expect(source, contains('permission.asked'));
      expect(source, contains('question.asked'));
      expect(source, contains('session.idle'));
      expect(source, contains('/agent-status'));
      // question.asked forwards the structured payload for the chat card.
      expect(source, contains('event.properties ?? event.data'));
      expect(source, contains('Array.isArray(props.questions)'));
      expect(source, contains('request_id'));

      final configPath =
          '$opencodeDir/${OpencodeConfigProfileCapability.opencodeConfigFileName}';
      final raw = await fs.readString(configPath);
      expect(raw, isNotNull);
      final config = jsonDecode(raw!) as Map<String, dynamic>;
      final plugin = config['plugin'] as List;
      expect(plugin, hasLength(1));
      final entry = plugin.first as List;
      expect(entry[0], './$opencodeAgentStatusPluginFileName');
      final opts = entry[1] as Map;
      expect(opts['member'], 'm1');
      expect(opts['url'], 'http://127.0.0.1:12345/agent-status');
      expect(opts['session'], 'session-1');
    },
  );
}
