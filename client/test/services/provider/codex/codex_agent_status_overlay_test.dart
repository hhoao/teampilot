import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/provider/codex/codex_agent_status_overlay.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  group('CodexAgentStatusOverlay', () {
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:12345/agent-status',
      sessionId: 'sess-codex',
    );
    const remoteEndpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:54321/agent-status',
      token: 'sess-tok',
    );

    test(
      'build hooks curl PermissionRequest (and clear events) to /agent-status',
      () {
        final toml = CodexAgentStatusOverlay.build(
          memberId: 'worker-1',
          endpoint: endpoint,
        );

        expect(toml, contains('/agent-status'));
        expect(toml, contains('[[hooks.PermissionRequest]]'));
        expect(toml, contains('[[hooks.PermissionRequest.hooks]]'));
        expect(toml, contains('[[hooks.PostToolUse]]'));
        expect(toml, contains('[[hooks.Stop]]'));
        expect(toml, contains('type = "command"'));
        expect(toml, contains('hook_event_name'));
        expect(toml, contains('PermissionRequest'));
        expect(
          toml,
          contains(
            'command = "curl -sS -X POST -H \\"X-Member: worker-1\\" '
            '-H \\"X-Session: sess-codex\\" '
            '-H \\"Content-Type: application/json\\" '
            '-d \'{\\"hook_event_name\\":\\"PermissionRequest\\"}\' '
            'http://127.0.0.1:12345/agent-status"',
          ),
        );
        expect(
          toml,
          contains(
            '-d \'{\\"hook_event_name\\":\\"PostToolUse\\"}\'',
          ),
        );
      },
    );

    test('build includes X-Bus-Token for remote endpoints', () {
      final toml = CodexAgentStatusOverlay.build(
        memberId: 'worker-1',
        endpoint: remoteEndpoint,
      );
      expect(toml, contains('${teammateBusTokenHeader}: sess-tok'));
      expect(toml, contains('http://127.0.0.1:54321/agent-status'));
    });
  });
}
