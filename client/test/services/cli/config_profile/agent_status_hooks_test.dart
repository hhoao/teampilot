import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/registry/config_profile/agent_status_hooks.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  const endpoint = MemberAgentStatusEndpoint(
    url: 'http://127.0.0.1:12345/agent-status',
  );
  const remoteEndpoint = MemberAgentStatusEndpoint(
    url: 'http://127.0.0.1:54321/agent-status',
    token: 'sess-tok',
  );
  const memberId = 'member-a';

  const eventNames = [
    'PermissionRequest',
    'PreToolUse',
    'PostToolUse',
    'Stop',
    'UserPromptSubmit',
  ];

  test(
    'mergeAgentStatusHooks adds http hooks with X-Member for status events',
    () {
      final merged = mergeAgentStatusHooks(const {}, memberId, endpoint);
      final hooks = merged['hooks']! as Map;
      for (final name in eventNames) {
        final entries = hooks[name]! as List;
        expect(entries, hasLength(1), reason: name);
        final eventHooks = (entries.first as Map)['hooks']! as List;
        expect(eventHooks.first, {
          'type': 'http',
          'url': endpoint.url,
          'headers': {'X-Member': memberId},
        }, reason: name);
      }
    },
  );

  test('mergeAgentStatusHooks adds X-Bus-Token for remote endpoints', () {
    final merged = mergeAgentStatusHooks(const {}, memberId, remoteEndpoint);
    final hooks = merged['hooks']! as Map;
    for (final name in eventNames) {
      final eventHooks =
          (((hooks[name] as List).first as Map)['hooks'] as List);
      final headers = (eventHooks.first as Map)['headers'] as Map;
      expect(headers[teammateBusTokenHeader], 'sess-tok', reason: name);
    }
  });

  test('mergeAgentStatusHooks is idempotent for same status url', () {
    final once = mergeAgentStatusHooks(const {}, memberId, endpoint);
    final twice = mergeAgentStatusHooks(once, memberId, endpoint);
    final hooks = twice['hooks']! as Map;
    for (final name in eventNames) {
      final entries = hooks[name]! as List;
      expect(entries, hasLength(1), reason: name);
    }
  });
}
