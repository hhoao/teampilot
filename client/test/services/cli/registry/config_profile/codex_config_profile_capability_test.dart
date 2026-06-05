import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/config_profile/codex_config_profile_capability.dart';

void main() {
  group('CodexConfigProfileCapability.buildCodexConfigToml', () {
    final toml = CodexConfigProfileCapability.buildCodexConfigToml(
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
        contains('tool_timeout_sec = '
            '${CodexConfigProfileCapability.busToolTimeoutSec}'),
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
}
