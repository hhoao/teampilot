import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/capabilities/runtime_event_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/config_profile/hook_seat_context_completer.dart';
import 'package:teampilot/services/cli/opencode/capabilities/opencode_hook_writer.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/runtime_event_hook_contribution_provider.dart';

void main() {
  final registry = CliToolRegistry.builtIn();
  const seat = RuntimeSeatKey(sessionId: 'session-1', memberId: 'member-1');
  final now = DateTime.utc(2026, 8, 25, 12);

  group('prompt event adapters', () {
    final cases = <({CliTool cli, Map<String, Object?> raw})>[
      (
        cli: CliTool.claude,
        raw: {'hook_event_name': 'UserPromptSubmit', 'prompt': 'claude'},
      ),
      (
        cli: CliTool.codex,
        raw: {'hook_event_name': 'UserPromptSubmit', 'prompt': 'codex'},
      ),
      (
        cli: CliTool.flashskyai,
        raw: {'hook_event_name': 'UserPromptSubmit', 'prompt': 'flashskyai'},
      ),
      (
        cli: CliTool.cursor,
        raw: {'hook_event_name': 'beforeSubmitPrompt', 'prompt': 'cursor'},
      ),
      (
        cli: CliTool.opencode,
        raw: {'event': 'userMessageSubmitted', 'prompt': 'opencode'},
      ),
    ];

    for (final testCase in cases) {
      test('${testCase.cli.value} normalizes its native prompt event', () {
        final event = registry
            .capability<RuntimeEventCapability>(testCase.cli)!
            .normalizeRuntimeEvent(testCase.raw, seat, now);

        expect(event!.kind, RuntimeEventKind.promptSubmitted);
        expect(event.prompt, testCase.cli.value);
        expect(
          event.correlationStrength,
          RuntimeCorrelationStrength.serializedPromptEpoch,
        );
      });
    }
  });

  test('managed runtime hooks are contributed as managed HookEntry values', () {
    final contributions = RuntimeEventHookContributionProvider(
      endpoint: const MemberAgentStatusEndpoint(
        url: 'http://127.0.0.1:4321/agent-status',
        sessionId: 'session-1',
      ),
      memberId: 'member-1',
    ).provide(HookProviderContext(cli: CliTool.codex)).toList();

    expect(contributions, isNotEmpty);
    expect(
      contributions.every(
        (contribution) =>
            contribution.entry.source.name == 'managed' &&
            contribution.origin.kind.name == 'managed',
      ),
      isTrue,
    );
  });

  test('HTTP CLIs contribute entries with their native event names', () {
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:4321/agent-status',
      sessionId: 'session-1',
    );
    for (final cli in [
      CliTool.claude,
      CliTool.codex,
      CliTool.flashskyai,
      CliTool.cursor,
    ]) {
      final contributions = RuntimeEventHookContributionProvider(
        endpoint: endpoint,
        memberId: 'member-1',
      ).provide(HookProviderContext(cli: cli)).toList();

      expect(contributions, isNotEmpty, reason: cli.value);
      for (final contribution in contributions) {
        final action = contribution.entry.action;
        expect(action, isA<HttpHookAction>());
        final native = HookEventCapability.nativeEvent(
          contribution.entry.event,
          cli,
        );
        expect((action as HttpHookAction).url, contains('event=$native'));
      }
    }
  });

  test(
    'OpenCode runtime plugin flows through hook assembly and writer',
    () async {
      final provider = RuntimeEventHookContributionProvider(
        endpoint: const MemberAgentStatusEndpoint(
          url: 'http://127.0.0.1:4321/agent-status',
          sessionId: 'session-1',
        ),
        memberId: 'member-1',
      );
      final assembly = await const HookSeatContextCompleter().assemble(
        cli: CliTool.opencode,
        supportsHttp: false,
        providers: [provider],
      );

      final action = assembly.entries.single.action as NativePluginHookAction;
      expect(action.fileName, 'teampilot-agent-status.js');
      expect(action.pluginPath, './teampilot-agent-status.js');
      expect(action.pluginOptions, {
        'member': 'member-1',
        'url': 'http://127.0.0.1:4321/agent-status',
        'session': 'session-1',
      });
      final rendered = const OpencodeHookWriter().render(
        entries: assembly.entries,
        ctx: const HookRenderContext(
          hooksDir: '/runtime/hooks',
          runner: null,
          glueBuilder: GlueScriptBuilder(),
        ),
      );

      expect(rendered.scripts.single.fileName, 'teampilot-agent-status.js');
      final config = rendered.configFragments['opencode.json']! as Map;
      expect((config['plugin'] as List).single, [
        './teampilot-agent-status.js',
        action.pluginOptions,
      ]);
    },
  );
}
