import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_bus_overlay.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  const localIdle = MemberBusIdleEndpoint(url: 'http://127.0.0.1:4321/idle');
  const remoteIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:4321/idle',
    token: 'sess-tok',
  );

  group('CursorHomeBusOverlay', () {
    test('buildMcpJson includes teammate-bus server with correct url/headers', () {
      final json = CursorHomeBusOverlay.buildMcpJson(
        memberId: 'planner',
        idle: localIdle,
      );
      final decoded = jsonDecode(json) as Map<String, Object?>;
      final servers = decoded['mcpServers'] as Map<String, Object?>;
      final bus = servers[teammateBusMcpServerName] as Map<String, Object?>;
      expect(bus['type'], 'http');
      expect(bus['url'], 'http://127.0.0.1:4321/mcp');
      expect((bus['headers'] as Map)['X-Member'], 'planner');
    });

    test('buildMcpJson adds bus token for remote idle endpoints', () {
      final json = CursorHomeBusOverlay.buildMcpJson(
        memberId: 'planner',
        idle: remoteIdle,
      );
      final decoded = jsonDecode(json) as Map<String, Object?>;
      final bus =
          (decoded['mcpServers'] as Map)[teammateBusMcpServerName] as Map;
      expect((bus['headers'] as Map)[teammateBusTokenHeader], 'sess-tok');
    });

    test('hooksConfig fires idle script on stop via bash, no loop cap', () {
      final h = CursorHomeBusOverlay.hooksConfig(
        idleScriptPath: '/fake/home/.cursor/hooks/idle.sh',
      );
      final stop = (h['hooks'] as Map)['stop'] as List;
      final entry = stop.single as Map;
      expect(entry['command'], "bash '/fake/home/.cursor/hooks/idle.sh'");
      expect(entry['loop_limit'], isNull);
    });

    test('idleScript POSTs /idle and translates decision:block', () {
      final s = CursorHomeBusOverlay.idleScript(
        memberId: 'planner',
        idle: localIdle,
      );

      expect(s, contains('X-Member: planner'));
      expect(s, contains('http://127.0.0.1:4321/idle'));
      expect(s, contains('"decision":"block"'));
      expect(s, contains('followup_message'));
    });

    test('idleScript includes bus token for remote endpoints', () {
      final s = CursorHomeBusOverlay.idleScript(
        memberId: 'planner',
        idle: remoteIdle,
      );
      expect(s, contains('X-Bus-Token: sess-tok'));
    });

    test('roleRule has alwaysApply frontmatter', () {
      final rule = CursorHomeBusOverlay.roleRule('只做代码审查');

      expect(rule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(rule, contains('只做代码审查'));
    });
  });
}
