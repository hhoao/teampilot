import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_session_registry.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

void main() {
  test(
    'register returns token and resolves handler by sessionId and token',
    () {
      final registry = TeammateBusSessionRegistry();
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final handler = TeammateBusMcpHandler(bus: bus);

      final reg = registry.register(sessionId: 'sess-a', handler: handler);

      expect(registry.handlerForSession('sess-a'), same(handler));
      expect(registry.sessionForToken(reg.token), 'sess-a');
    },
  );

  test('unregister removes session and invalidates token', () {
    final registry = TeammateBusSessionRegistry();
    final handler = TeammateBusMcpHandler(
      bus: TeamBus(launcher: FakeMemberLauncher()),
    );
    final reg = registry.register(sessionId: 'sess-a', handler: handler);

    registry.unregister('sess-a');

    expect(registry.handlerForSession('sess-a'), isNull);
    expect(registry.sessionForToken(reg.token), isNull);
  });
}
