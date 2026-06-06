import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_bus_overlay.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  group('CursorHomeBusOverlay', () {
    test('buildMcpJson includes teammate-bus server with correct url/headers', () {
      final json = CursorHomeBusOverlay.buildMcpJson(
        memberId: 'planner',
        port: 4321,
      );
      final decoded = jsonDecode(json) as Map<String, Object?>;
      final servers = decoded['mcpServers'] as Map<String, Object?>;
      final bus = servers[teammateBusMcpServerName] as Map<String, Object?>;
      expect(bus['type'], 'http');
      expect(bus['url'], 'http://127.0.0.1:4321/mcp');
      expect((bus['headers'] as Map)['X-Member'], 'planner');
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
      final s = CursorHomeBusOverlay.idleScript(memberId: 'planner', port: 4321);

      expect(s, contains('X-Member: planner'));
      expect(s, contains('http://127.0.0.1:4321/idle'));
      expect(s, contains('"decision":"block"'));
      expect(s, contains('followup_message'));
    });

    test('parseBusPort extracts the port', () {
      expect(
        CursorHomeBusOverlay.parseBusPort('http://127.0.0.1:5050/idle'),
        5050,
      );
      expect(CursorHomeBusOverlay.parseBusPort(null), isNull);
      expect(CursorHomeBusOverlay.parseBusPort(''), isNull);
    });

    test('roleRule has alwaysApply frontmatter', () {
      final rule = CursorHomeBusOverlay.roleRule('只做代码审查');

      expect(rule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(rule, contains('只做代码审查'));
    });
  });
}
