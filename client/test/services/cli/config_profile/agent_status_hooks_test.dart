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
    'PostToolUseFailure',
    'Stop',
    'StopFailure',
    'UserPromptSubmit',
  ];

  test(
    'mergeAgentStatusHooks adds per-event http URLs so clear hooks survive dedupe',
    () {
      final merged = mergeAgentStatusHooks(const {}, memberId, endpoint);
      final hooks = merged['hooks']! as Map;
      for (final name in eventNames) {
        final entries = hooks[name]! as List;
        expect(entries, hasLength(1), reason: name);
        final entry = entries.first as Map;
        final eventHooks = entry['hooks']! as List;
        expect(eventHooks.first, {
          'type': 'http',
          'url': agentStatusHookUrl(endpoint.url, name),
          'headers': {'X-Member': memberId},
          'timeout': 5,
        }, reason: name);
        if (name == 'PermissionRequest' ||
            name == 'PreToolUse' ||
            name == 'PostToolUse' ||
            name == 'PostToolUseFailure') {
          expect(entry['matcher'], '*', reason: name);
        } else {
          expect(entry.containsKey('matcher'), isFalse, reason: name);
        }
      }
      final urls = eventNames
          .map((n) => agentStatusHookUrl(endpoint.url, n))
          .toSet();
      expect(urls, hasLength(eventNames.length));
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
