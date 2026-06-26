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
    const mcpRawTunnelPort = 47213;
    const idleHttpTunnelPort = 47214;

    test('long-blocking CLI → stdio relay over the tunnel (token in handshake)',
        () {
      final cfg = buildMemberBusMcpConfig(
        memberId: 'worker',
        localEndpoint: localEndpoint,
        longBlocking: true,
        remote: const RemoteBusBinding(
          token: 'tok',
          idleHttpTunnelPort: idleHttpTunnelPort,
          mcpRawTunnelPort: mcpRawTunnelPort,
          mcpRelayArgv: [
            'sh',
            '-c',
            "{ printf '%s\\n' '{\"token\":\"tok\",\"memberId\":\"worker\"}'; cat; } "
                '| socat - TCP:127.0.0.1:$mcpRawTunnelPort',
          ],
        ),
      );
      expect(cfg['command'], 'sh');
      final args = (cfg['args'] as List).join(' ');
      expect(args, contains('TCP:127.0.0.1:$mcpRawTunnelPort'));
      expect(args, contains('tok'));
      expect(args, isNot(contains('5005')));
      expect(cfg.containsKey('url'), isFalse);
    });

    test('cursor (doorbell) → HTTP over the tunnel with token header', () {
      final cfg = buildMemberBusMcpConfig(
        memberId: 'cur',
        localEndpoint: localEndpoint,
        longBlocking: false,
        remote: const RemoteBusBinding(
          token: 'tok',
          idleHttpTunnelPort: mcpRawTunnelPort,
          mcpHttpTunnelPort: mcpRawTunnelPort,
        ),
      );
      expect(cfg['type'], 'http');
      expect(cfg['url'], 'http://127.0.0.1:$mcpRawTunnelPort/mcp');
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
          remote: const RemoteBusBinding(
            token: 'tok',
            idleHttpTunnelPort: idleHttpTunnelPort,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
