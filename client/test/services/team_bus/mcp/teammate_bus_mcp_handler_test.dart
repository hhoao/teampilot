import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

TeammateBusMcpHandler _handler() =>
    TeammateBusMcpHandler(bus: TeamBus(launcher: FakeMemberLauncher()));

void main() {
  test('initialize advertises tools capability and fixed protocol version', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(id: 0, method: 'initialize'),
    );
    expect(res!.result!['protocolVersion'], '2025-06-18');
    expect(res.result!['capabilities'], {'tools': <String, Object?>{}});
    expect((res.result!['serverInfo'] as Map)['name'], isNotEmpty);
  });

  test('notifications/initialized returns null (202, no body)', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(method: 'notifications/initialized'),
    );
    expect(res, isNull);
  });

  test('tools/list returns the four bus tools', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(id: 1, method: 'tools/list'),
    );
    final names = [
      for (final t in res!.result!['tools'] as List) (t as Map)['name'],
    ];
    expect(names, containsAll(['send_message', 'wait_for_message', 'finish_task', 'leave']));
  });
}
