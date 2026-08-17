import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/opencode/capabilities/agent_status_plugin.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  Future<SessionHomeContribution> contribute(
    OpencodeProviderCapability capability,
    ConfigProfileLaunchContext ctx,
  ) => capability.materializeSessionHome(
    sessionHomeContextFromLaunch(ctx, CliTool.opencode),
  );

  test('opencodeAgentStatusPluginSource polls Bus and replies via SDK', () {
    final source = opencodeAgentStatusPluginSource;
    // question.asked payload fields for Dart normalizer / chat card.
    expect(source, contains('request_id'));
    expect(source, contains('session_id'));
    // Poll gateway for user answer (Task 6).
    expect(source, contains('/ask-user-answer?request_id='));
    // OpenCode SDK reply / reject (flat requestID API; see plugin comment).
    expect(source, contains('client.question.reply'));
    expect(source, contains('client.question.reject'));
    // The plugin `input.client` (v1 SDK) has no `question` member, so answers
    // must fall back to the OpenCode HTTP API. Default TUI mode has no TCP
    // listener (in-process RPC bridge), so delivery must go through the
    // client's own request pipeline (`client._client.post`) — a raw
    // `fetch(input.serverUrl)` would hit a dead localhost:4096.
    expect(source, contains('deliverQuestionReply'));
    expect(source, contains('client?._client'));
    expect(source, contains('raw?.post'));
    expect(source, contains(r'/question/${encodeURIComponent(requestId)}/'));
    expect(source, contains('input?.serverUrl'));
    expect(source, contains('"reject"'));
    // SDK error AND poll timeout both POST reply_failed.
    expect(source, contains('question.reply_failed'));
    expect(source, contains('ask-user-answer poll timed out'));
    // Poll loop bound to attention TTL (30 minutes).
    expect(source, contains('30 * 60 * 1000'));
    // permission.asked forwards the structured payload for the chat card and
    // polls for a permission reply (accept / reject / always).
    expect(source, contains('props.permission'));
    expect(source, contains('props.patterns'));
    expect(source, contains('props.always'));
    expect(source, contains('pollAndReply(requestId, "permission")'));
    expect(source, contains('deliverPermissionReply'));
    expect(source, contains('client.permission.reply'));
    expect(source, contains('body.permission_reply'));
    expect(
      source,
      contains(r'/permission/${encodeURIComponent(requestId)}/reply'),
    );
    expect(source, contains('"reject" : "once"'));
    // Native answers (terminal TUI / reject) publish replied/rejected; the
    // plugin forwards them so the chat card clears immediately and the
    // pending poll stops without posting reply_failed.
    expect(source, contains('question.replied'));
    expect(source, contains('question.v2.replied'));
    expect(source, contains('question.rejected'));
    expect(source, contains('question.v2.rejected'));
    expect(source, contains('permission.replied'));
    expect(source, contains('permission.v2.replied'));
    expect(source, contains('"question.answered"'));
    expect(source, contains('"permission.answered"'));
    expect(source, contains('resolvedRequests'));
    expect(source, contains('isResolved(requestId)'));
  });

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

  test('mergeOpencodeAgentStatusPlugin replaces stale same-member entry when '
      'the gateway port changes', () {
    // Every connect stamps a fresh gateway port, so the old entry with the
    // dead URL must be replaced — not appended alongside.
    final once = mergeOpencodeAgentStatusPlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
      sessionId: 'session-1',
    );
    final twice = mergeOpencodeAgentStatusPlugin(
      once,
      'm1',
      'http://127.0.0.1:23456/agent-status',
      sessionId: 'session-1',
    );
    final plugin = twice['plugin'] as List;
    expect(plugin, hasLength(1));
    final entry = plugin.first as List;
    expect(entry[0], './$opencodeAgentStatusPluginFileName');
    final opts = entry[1] as Map;
    expect(opts['url'], 'http://127.0.0.1:23456/agent-status');
  });

  test('mergeOpencodeAgentStatusPlugin preserves unrelated plugin entries and '
      'other members', () {
    final merged = mergeOpencodeAgentStatusPlugin(
      <String, Object?>{
        'plugin': <Object?>[
          './plugins/other/plugin.js',
          <Object?>[
            './$opencodeAgentStatusPluginFileName',
            <String, Object?>{
              'member': 'm2',
              'url': 'http://127.0.0.1:1/agent-status',
            },
          ],
        ],
      },
      'm1',
      'http://127.0.0.1:23456/agent-status',
    );
    final plugin = merged['plugin'] as List;
    expect(plugin, hasLength(3));
    final last = plugin.last as List;
    final opts = last[1] as Map;
    expect(opts['member'], 'm1');
    expect(opts['url'], 'http://127.0.0.1:23456/agent-status');
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
      const capability = OpencodeProviderCapability();
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

      await contribute(capability,
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
      expect(source, contains('session_id'));
      // Poll Bus for answers, then reply/reject via OpenCode SDK.
      expect(source, contains('/ask-user-answer?request_id='));
      expect(source, contains('client.question.reply'));
      expect(source, contains('client.question.reject'));
      expect(source, contains('question.reply_failed'));
      // Poll deadline matches attention TTL (30 minutes).
      expect(source, contains('30 * 60 * 1000'));
      expect(source, contains('ask-user-answer poll timed out'));
      // Native TUI answers / rejects are forwarded as answered events so the
      // chat card clears immediately; the poll stops without reply_failed.
      expect(source, contains('question.replied'));
      expect(source, contains('question.rejected'));
      expect(source, contains('permission.replied'));
      expect(source, contains('"question.answered"'));
      expect(source, contains('"permission.answered"'));
      expect(source, contains('resolvedRequests'));
      expect(source, contains('isResolved(requestId)'));

      final configPath =
          '$opencodeDir/${OpencodeProviderCapability.opencodeConfigFileName}';
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
