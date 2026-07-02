import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  group('teammateBusMcpServerConfigStdio', () {
    test('includes --session for gateway routing', () {
      final cfg = teammateBusMcpServerConfigStdio(
        bridgePath: '/path/to/teammate_bus_bridge',
        endpoint: Uri.parse('http://127.0.0.1:1234/mcp'),
        memberId: 'alice',
        sessionId: 'sess-1',
      );

      expect(
        cfg['args'],
        [
          '--member',
          'alice',
          '--session',
          'sess-1',
          '--bus-url',
          'http://127.0.0.1:1234/mcp',
        ],
      );
    });
  });
}
