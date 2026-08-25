import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/capabilities/runtime_event_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/runtime_event_hook_contribution_provider.dart';

void main() {
  final registry = CliToolRegistry.builtIn();
  const seat = RuntimeSeatKey(sessionId: 'session-1', memberId: 'member-1');
  final now = DateTime.utc(2026, 8, 25, 12);

  test('Codex UserPromptSubmit becomes a serialized promptSubmitted event', () {
    final event = registry
        .capability<RuntimeEventCapability>(CliTool.codex)!
        .normalizeRuntimeEvent(
          {'hook_event_name': 'UserPromptSubmit', 'prompt': 'ship it'},
          seat,
          now,
        );

    expect(event!.kind, RuntimeEventKind.promptSubmitted);
    expect(event.prompt, 'ship it');
    expect(
      event.correlationStrength,
      RuntimeCorrelationStrength.serializedPromptEpoch,
    );
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
}
