import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/opencode/capabilities/agent_status_plugin.dart';
import 'package:teampilot/services/cli/opencode/capabilities/opencode_hook_writer.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/runtime_event_hook_contribution_provider.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  setUpAll(() {
    CliToolRegistry.builtIn().configure(
      CliBootstrap(const {}, storage: fakeHomeStorage()),
    );
  });

  Future<SessionHomeContribution> contribute(
    OpencodeProviderCapability capability,
    ConfigProfileLaunchContext ctx,
  ) => capability.materializeSessionHome(
    sessionHomeContextFromLaunch(ctx, CliTool.opencode),
  );

  Map<String, Object?> mergeRuntimePlugin(
    Map<String, Object?> config,
    String memberId,
    String url, {
    String? token,
    String? sessionId,
    bool questionsOnly = false,
  }) {
    final entries =
        RuntimeEventHookContributionProvider(
              endpoint: MemberAgentStatusEndpoint(
                url: url,
                token: token,
                sessionId: sessionId,
                questionsOnly: questionsOnly,
              ),
              memberId: memberId,
            )
            .provide(
              HookProviderContext(cli: CliTool.opencode, supportsHttp: false),
            )
            .map((contribution) => contribution.entry)
            .toList();
    final rendered = const OpencodeHookWriter().render(
      entries: entries,
      ctx: const HookRenderContext(
        hooksDir: '/runtime/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    final fragment = rendered.configFragments['opencode.json']! as Map;
    return mergeOpencodePluginEntries(config, fragment['plugins'] as List);
  }

  test('opencodeAgentStatusPluginSource polls Bus and replies via SDK', () {
    final source = opencodeAgentStatusPluginSource;
    // question.asked payload fields for Dart normalizer / chat card.
    expect(source, contains('request_id'));
    expect(source, contains('session_id'));
    // Poll gateway for user answer (Task 6).
    expect(source, contains('/ask-user-answer?request_id='));
    // OpenCode SDK reply / reject (flat requestID API; see plugin comment).
    expect(source, contains('ctx.question.reply'));
    expect(source, contains('ctx.question.reject'));
    expect(source, contains('deliverQuestionReply'));
    expect(source, contains('ctx._client'));
    expect(source, contains('raw?.post'));
    expect(source, contains(r'/question/${encodeURIComponent(requestId)}/'));
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
    expect(
      source,
      contains('pollAndReply(requestId, "permission", sessionID)'),
    );
    expect(source, contains('deliverPermissionReply'));
    expect(source, contains('ctx.permission.reply'));
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

  test('opencodeAgentStatusPluginSource supports a question-only channel', () {
    final source = opencodeAgentStatusPluginSource;
    // ACP seats pass questionsOnly so the plugin bridges only question.* —
    // permissions ride the ACP protocol and idle rides the ACP cubit/TeamBus,
    // so re-reporting them would double-card or leave stale attention.
    expect(source, contains('options.questionsOnly'));
    expect(source, contains('questionsOnly'));
    expect(
      source,
      contains('if (questionsOnly && !event.type.startsWith("question."))'),
    );
  });

  test(
    'opencodeAgentStatusPluginSource reports background shell + subagents',
    () {
      final source = opencodeAgentStatusPluginSource;
      // Background shell tasks → lease (backgroundTaskStarted).
      expect(source, contains('session.shell.started'));
      expect(source, contains('session.shell.ended'));
      // The SDK types spell these `session.next.shell.*`; accept both.
      expect(source, contains('session.next.shell.started'));
      expect(source, contains('session.next.shell.ended'));
      expect(source, contains('shell.metadata.background'));
      // Payload shape varies: nested `properties.shell` or flattened callID.
      expect(source, contains('props.callID'));
      expect(source, contains('"shell.started"'));
      expect(source, contains('"shell.ended"'));
      expect(source, contains('backgroundShellIds'));
      // Subagent child sessions → lease, and a child idle is never the parent
      // session finishing.
      expect(source, contains('info.parentID'));
      expect(source, contains('childSessionIds'));
      expect(source, contains('"subagent.started"'));
      expect(source, contains('"subagent.stopped"'));
    },
  );

  test('mergeRuntimePlugin adds plugin entry with url', () {
    final merged = mergeRuntimePlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
      sessionId: 'session-1',
    );
    final plugin = merged['plugins'] as List;
    expect(plugin, hasLength(1));
    final entry = plugin.first as Map;
    expect(entry['package'], './$opencodeAgentStatusPluginFileName');
    final opts = entry['options'] as Map;
    expect(opts['member'], 'm1');
    expect(opts['url'], 'http://127.0.0.1:12345/agent-status');
    expect(opts['session'], 'session-1');
  });

  test('mergeRuntimePlugin forwards the ACP question-only channel', () {
    final merged = mergeRuntimePlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
      questionsOnly: true,
    );
    final opts = (merged['plugins'] as List).first as Map;
    expect((opts['options'] as Map)['questionsOnly'], isTrue);
  });

  test('mergeRuntimePlugin omits the question-only flag by default', () {
    final merged = mergeRuntimePlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
    );
    final opts = (merged['plugins'] as List).first as Map;
    expect((opts['options'] as Map).containsKey('questionsOnly'), isFalse);
  });

  test('mergeRuntimePlugin is idempotent for same url', () {
    final once = mergeRuntimePlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
    );
    final twice = mergeRuntimePlugin(
      once,
      'm1',
      'http://127.0.0.1:12345/agent-status',
    );
    expect(twice['plugins'], hasLength(1));
  });

  test('mergeRuntimePlugin replaces stale same-member entry when '
      'the gateway port changes', () {
    // Every connect stamps a fresh gateway port, so the old entry with the
    // dead URL must be replaced — not appended alongside.
    final once = mergeRuntimePlugin(
      const {},
      'm1',
      'http://127.0.0.1:12345/agent-status',
      sessionId: 'session-1',
    );
    final twice = mergeRuntimePlugin(
      once,
      'm1',
      'http://127.0.0.1:23456/agent-status',
      sessionId: 'session-1',
    );
    final plugin = twice['plugins'] as List;
    expect(plugin, hasLength(1));
    final entry = plugin.first as Map;
    expect(entry['package'], './$opencodeAgentStatusPluginFileName');
    final opts = entry['options'] as Map;
    expect(opts['url'], 'http://127.0.0.1:23456/agent-status');
  });

  test('mergeRuntimePlugin preserves unrelated plugin entries and '
      'other members', () {
    final merged = mergeRuntimePlugin(
      <String, Object?>{
        'plugins': <Object?>[
          './plugins/other/plugin.js',
          <String, Object?>{
            'package': './$opencodeAgentStatusPluginFileName',
            'options': <String, Object?>{
              'member': 'm2',
              'url': 'http://127.0.0.1:1/agent-status',
            },
          },
        ],
      },
      'm1',
      'http://127.0.0.1:23456/agent-status',
    );
    final plugin = merged['plugins'] as List;
    expect(plugin, hasLength(3));
    final last = plugin.last as Map;
    final opts = last['options'] as Map;
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
        storage: fakeHomeStorage(),
      );
      final capability = OpencodeProviderCapability(storage: fakeHomeStorage());
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

      await contribute(
        capability,
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
      expect(source, contains('ctx.question.reply'));
      expect(source, contains('ctx.question.reject'));
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
      final plugin = config['plugins'] as List;
      expect(plugin, hasLength(1));
      final entry = plugin.first as Map;
      expect(entry['package'], './$opencodeAgentStatusPluginFileName');
      final opts = entry['options'] as Map;
      expect(opts['member'], 'm1');
      expect(opts['url'], 'http://127.0.0.1:12345/agent-status');
      expect(opts['session'], 'session-1');
    },
  );

  test('prepareSimpleSessionLaunch with agentStatus writes the assembled JS '
      'plugin', () async {
    final base = await Directory.systemTemp.createTemp('opencode_status_fs_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      storage: fakeHomeStorage(),
    );
    const workspaceId = 'workspace-1';
    const sessionId = 'session-1';
    const member = TeamMemberConfig(
      id: sessionId,
      name: 'Solo',
      cli: CliTool.opencode,
    );

    await service.prepareSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: const ConfigBundle(),
      member: member,
      agentStatus: const MemberAgentStatusEndpoint(
        url: 'http://127.0.0.1:12345/agent-status',
        sessionId: sessionId,
      ),
    );

    final opencodeDir = service.sessionToolDir(
      workspaceId,
      sessionId,
      'opencode',
    );
    final pluginPath = '$opencodeDir/$opencodeAgentStatusPluginFileName';
    expect(await fs.stat(pluginPath), isNotNull);
    final configPath =
        '$opencodeDir/${OpencodeProviderCapability.opencodeConfigFileName}';
    final raw = await fs.readString(configPath);
    expect(raw, isNotNull);
    final config = jsonDecode(raw!) as Map<String, dynamic>;
    final plugin = config['plugins'] as List;
    expect(plugin, isNotEmpty);
    final entry = plugin.first as Map;
    expect(entry['package'], './$opencodeAgentStatusPluginFileName');
    final opts = entry['options'] as Map;
    expect(opts['url'], 'http://127.0.0.1:12345/agent-status');
  });
}
