import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/codex/codex_team_bus_overlay.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  group('CodexTeamBusOverlay', () {
    final toml = CodexTeamBusOverlay.buildLocal(
      memberId: 'worker-1',
      port: 54321,
    );

    test('registers the teammate-bus HTTP MCP server with X-Member identity', () {
      expect(toml, contains('[mcp_servers.teammate-bus]'));
      expect(toml, contains('url = "http://127.0.0.1:54321/mcp"'));
      expect(toml, contains('http_headers = { "X-Member" = "worker-1" }'));
    });

    test('keeps the bus tool timeout far above any real idle wait', () {
      expect(
        toml,
        contains('tool_timeout_sec = ${CodexTeamBusOverlay.busToolTimeoutSec}'),
      );
    });

    test('auto-approves all teammate-bus MCP tools without prompting', () {
      expect(
        toml,
        contains(
          'default_tools_approval_mode = '
          '"${CodexTeamBusOverlay.defaultToolsApprovalMode}"',
        ),
      );
    });

    test('wires a Stop hook that curls /idle and passes the response through',
        () {
      expect(toml, contains('[[hooks.Stop]]'));
      expect(toml, contains('[[hooks.Stop.hooks]]'));
      expect(toml, contains('type = "command"'));
      // curl writes the /idle JSON ({"decision":"block"} | {}) to stdout, which
      // codex reads as the Stop-hook decision — no shim file, no chmod.
      expect(
        toml,
        contains(
          'command = "curl -sS -X POST -H \\"X-Member: worker-1\\" '
          'http://127.0.0.1:54321/idle"',
        ),
      );
    });
  });

  group('CodexTeamBusOverlay remote stop hook', () {
    test('buildStopHook includes X-Bus-Token for remote idle endpoints', () {
      const idle = MemberBusIdleEndpoint(
        url: 'http://127.0.0.1:54321/idle',
        token: 'sess-tok',
      );
      final toml = CodexTeamBusOverlay.buildStopHook(
        memberId: 'worker-1',
        idle: idle,
      );
      expect(toml, contains('X-Bus-Token: sess-tok'));
      expect(toml, contains('http://127.0.0.1:54321/idle'));
      expect(toml, isNot(contains('[mcp_servers.teammate-bus]')));
    });
  });
}
