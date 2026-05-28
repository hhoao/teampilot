import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/mcp/mcp_oauth_server_key.dart';

void main() {
  test('server key matches Claude Code hash for stable config', () {
    const serverName = 'Context7';
    final config = {
      'type': 'http',
      'url': 'https://context7-mcp--upstash.run.tools',
      'headers': <String, Object?>{},
    };
    final key = mcpOAuthServerKey(serverName, config);
    expect(key.startsWith('$serverName|'), isTrue);
    expect(key.split('|').last.length, 16);
  });

  test('headers affect server key', () {
    final a = mcpOAuthServerKey('srv', {
      'type': 'http',
      'url': 'https://example.com',
      'headers': {'X': '1'},
    });
    final b = mcpOAuthServerKey('srv', {
      'type': 'http',
      'url': 'https://example.com',
      'headers': <String, Object?>{},
    });
    expect(a, isNot(equals(b)));
  });
}
