import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/config_profile/cursor_team_bus_plugin.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  group('CursorTeamBusPlugin', () {
    test('manifest wires teammate-bus MCP, hooks, and rules', () {
      final m = CursorTeamBusPlugin.manifest(memberId: 'planner', port: 4321);

      expect(m['name'], 'teampilot-bus-planner');
      expect(m['hooks'], './hooks/hooks.json');
      expect(m['rules'], './rules/*.mdc');

      final servers = m['mcpServers'] as Map<String, Object?>;
      final bus = servers[teammateBusMcpServerName] as Map<String, Object?>;
      expect(bus['type'], 'http');
      expect(bus['url'], 'http://127.0.0.1:4321/mcp');
      expect((bus['headers'] as Map)['X-Member'], 'planner');
    });

    test('hooksConfig fires idle script on stop via bash, no loop cap', () {
      final h = CursorTeamBusPlugin.hooksConfig(
        idleScriptPath: '/cfg/hooks/idle.sh',
      );
      final stop = (h['hooks'] as Map)['stop'] as List;
      final entry = stop.single as Map;
      expect(entry['command'], "bash '/cfg/hooks/idle.sh'");
      expect(entry['loop_limit'], isNull);
    });

    test('idleScript POSTs /idle and translates decision:block', () {
      final s = CursorTeamBusPlugin.idleScript(memberId: 'planner', port: 4321);

      expect(s, contains('X-Member: planner'));
      expect(s, contains('http://127.0.0.1:4321/idle'));
      expect(s, contains('"decision":"block"'));
      expect(s, contains('followup_message'));
    });

    test('parseBusPort extracts the port', () {
      expect(
        CursorTeamBusPlugin.parseBusPort('http://127.0.0.1:5050/idle'),
        5050,
      );
      expect(CursorTeamBusPlugin.parseBusPort(null), isNull);
      expect(CursorTeamBusPlugin.parseBusPort(''), isNull);
    });
  });
}
