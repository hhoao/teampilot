import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/remote/member_bus_mcp_config.dart';

void main() {
  final localEndpoint = Uri.parse('http://127.0.0.1:5005/mcp');

  group('local member (no remote binding) — behaviour preserved', () {
    test('long-blocking with bridge → stdio bridge to the bare endpoint', () {
      final cfg = buildMemberBusMcpConfig(
        memberId: 'm1',
        localEndpoint: localEndpoint,
        longBlocking: true,
        localStdioBridgePath: '/opt/bridge',
      );
      expect(cfg['command'], '/opt/bridge');
      expect((cfg['args'] as List).join(' '), contains('5005'));
      expect(cfg.containsKey('type'), isFalse);
    });

    test('no bridge → plain HTTP to the bare endpoint', () {
      final cfg = buildMemberBusMcpConfig(
        memberId: 'm1',
        localEndpoint: localEndpoint,
        longBlocking: false,
      );
      expect(cfg['type'], 'http');
      expect(cfg['url'], 'http://127.0.0.1:5005/mcp');
    });
  });

  group('remote member — points at the tunnel port, not the bare endpoint', () {
    const tunnelPort = 47213;

    test('long-blocking CLI → stdio relay over the tunnel (token in handshake)',
        () {
      final cfg = buildMemberBusMcpConfig(
        memberId: 'worker',
        localEndpoint: localEndpoint,
        longBlocking: true,
        remote: const RemoteBusBinding(
          tunnelPort: tunnelPort,
          token: 'tok',
          relayArgv: [
            'sh',
            '-c',
            "{ printf '%s\\n' '{\"token\":\"tok\",\"memberId\":\"worker\"}'; cat; } "
                '| socat - TCP:127.0.0.1:$tunnelPort',
          ],
        ),
      );
      expect(cfg['command'], 'sh');
      final args = (cfg['args'] as List).join(' ');
      expect(args, contains('TCP:127.0.0.1:$tunnelPort'));
      expect(args, contains('tok'));
      // crucially: NOT the bare in-process bus port.
      expect(args, isNot(contains('5005')));
      expect(cfg.containsKey('url'), isFalse);
    });

    test('cursor (doorbell) → HTTP over the tunnel with token header', () {
      final cfg = buildMemberBusMcpConfig(
        memberId: 'cur',
        localEndpoint: localEndpoint,
        longBlocking: false,
        remote: const RemoteBusBinding(tunnelPort: tunnelPort, token: 'tok'),
      );
      expect(cfg['type'], 'http');
      expect(cfg['url'], 'http://127.0.0.1:$tunnelPort/mcp');
      expect((cfg['url'] as String), isNot(contains('5005')));
      final headers = cfg['headers'] as Map;
      expect(headers[teammateBusMcpMemberHeader], 'cur');
      expect(headers[teammateBusTokenHeader], 'tok');
    });

    test('long-blocking remote without a relay argv is rejected', () {
      expect(
        () => buildMemberBusMcpConfig(
          memberId: 'worker',
          localEndpoint: localEndpoint,
          longBlocking: true,
          remote: const RemoteBusBinding(tunnelPort: tunnelPort, token: 'tok'),
        ),
        throwsArgumentError,
      );
    });
  });
}
