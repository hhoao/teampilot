import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/team_bus/teammate_bus_permission.dart';

void main() {
  test('Cursor ACP teammate-bus tool titles are host-owned', () {
    expect(
      isTeammateBusPermissionRequest(
        const AgentPermissionRequest(
          id: 'p1',
          description: 'teammate-bus-read_messages: read_messages',
        ),
      ),
      isTrue,
    );
  });

  test('unrelated tool permission is not host-owned', () {
    expect(
      isTeammateBusPermissionRequest(
        const AgentPermissionRequest(
          id: 'p2',
          description: 'Run `npm install`',
        ),
      ),
      isFalse,
    );
  });

  test('Claude ACP mcpServer meta is host-owned', () {
    expect(
      isTeammateBusToolCall(
        title: 'Use MCP tool',
        meta: const {
          'claudeCode': {
            'mcpServer': {'name': 'teammate-bus', 'source': 'sdk'},
            'toolName': 'mcp__teammate-bus__list_teammates',
          },
        },
      ),
      isTrue,
    );
  });

  test('isTeammateBusPermissionText matches the bus server name', () {
    expect(
      isTeammateBusPermissionText('teammate-bus-read_messages: read_messages'),
      isTrue,
    );
    expect(isTeammateBusPermissionText('Run `npm install`'), isFalse);
  });

  test('isTeammateBusToolCall matches title, rawInput, and meta', () {
    expect(
      isTeammateBusToolCall(title: 'teammate-bus-read_messages: read_messages'),
      isTrue,
    );
    expect(isTeammateBusToolCall(rawInput: {'server': 'teammate-bus'}), isTrue);
    expect(
      isTeammateBusToolCall(meta: {'_serverName': 'teammate-bus'}),
      isTrue,
    );
    expect(isTeammateBusToolCall(title: 'Run npm install'), isFalse);
  });

  test('bare teammate-bus tool names are not host-owned', () {
    expect(isTeammateBusToolCall(title: 'read_messages'), isFalse);
    expect(isTeammateBusPermissionText('list_teammates'), isFalse);
  });
}
