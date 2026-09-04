import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/cli/registry/capabilities/claude_family_agent_status_normalizer.dart';

void main() {
  group('ClaudeFamilyAgentStatusNormalizer', () {
    test('PermissionRequest for a general tool carries a permissionRequest payload',
        () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
        'tool_input': {'command': 'rm -rf node_modules'},
        'permission_suggestions': [
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
            ],
            'behavior': 'allow',
            'destination': 'localSettings',
          },
        ],
      });
      expect(status, isNotNull);
      expect(status!.state, AgentSeatAttention.waiting);
      expect(status.permissionRequest, isNotNull);
      expect(status.permissionRequest!.description, contains('Bash'));
      expect(status.permissionRequest!.always, hasLength(1));
      expect(status.permissionRequest!.always.first.label,
          'Bash(rm -rf node_modules)');
    });

    test('PermissionRequest for ExitPlanMode carries no permissionRequest payload',
        () {
      final status = const ClaudeFamilyAgentStatusNormalizer().normalize({
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'ExitPlanMode',
        'tool_input': {'plan': 'Do the thing'},
      });
      expect(status, isNotNull);
      expect(status!.state, AgentSeatAttention.waiting);
      expect(status.permissionRequest, isNull);
      expect(status.planText, isNotNull); // plan card path, unchanged
    });
  });
}
