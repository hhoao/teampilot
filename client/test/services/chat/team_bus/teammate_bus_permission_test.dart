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

  test('bare teammate-bus tool names are host-owned', () {
    expect(
      isTeammateBusPermissionRequest(
        const AgentPermissionRequest(id: 'p3', description: 'list_teammates'),
      ),
      isTrue,
    );
    expect(
      isTeammateBusPermissionRequest(
        const AgentPermissionRequest(id: 'p4', description: 'read_messages'),
      ),
      isTrue,
    );
  });
}
