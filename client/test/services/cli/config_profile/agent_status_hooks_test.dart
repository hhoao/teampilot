import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/config_profile/agent_status_hooks.dart';

void main() {
  const endpointUrl = 'http://127.0.0.1:12345/agent-status';

  const eventNames = [
    'PermissionRequest',
    'PreToolUse',
    'PostToolUse',
    'PostToolUseFailure',
    'Stop',
    'StopFailure',
    'UserPromptSubmit',
  ];

  test('agentStatusHookUrl adds per-event query so dedupe keeps every hook', () {
    final urls = eventNames.map((n) => agentStatusHookUrl(endpointUrl, n));
    expect(urls, hasLength(eventNames.length));
    for (final name in eventNames) {
      expect(agentStatusHookUrl(endpointUrl, name), contains('event=$name'));
    }
  });

  test('agentStatusHookUrl preserves existing query parameters', () {
    final url = agentStatusHookUrl('$endpointUrl?ack=1&seat=s1', 'Stop');
    expect(url, contains('ack=1'));
    expect(url, contains('seat=s1'));
    expect(url, contains('event=Stop'));
  });
}
