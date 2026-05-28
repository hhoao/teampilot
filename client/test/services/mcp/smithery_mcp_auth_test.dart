import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/mcp/smithery_mcp_auth.dart';

void main() {
  test('applyCatalogBearer adds Authorization for smithery gateway URL', () {
    final spec = SmitheryMcpAuth.applyCatalogBearer(
      {
        'type': 'http',
        'url': 'https://server.smithery.ai/@github',
      },
      'secret-token',
    );
    final headers = spec['headers'] as Map;
    expect(headers['Authorization'], 'Bearer secret-token');
  });

  test('applyCatalogBearer skips smithery deployment hosts', () {
    final spec = SmitheryMcpAuth.applyCatalogBearer(
      {
        'type': 'http',
        'url': 'https://context7-mcp--upstash.run.tools',
      },
      'secret-token',
    );
    expect(spec.containsKey('headers'), isFalse);
  });

  test('applyCatalogBearer skips stdio servers', () {
    final spec = SmitheryMcpAuth.applyCatalogBearer(
      const {'type': 'stdio', 'command': 'npx'},
      'secret-token',
    );
    expect(spec.containsKey('headers'), isFalse);
  });

  test('applyToCatalogServers only patches gateway entries', () {
    final out = SmitheryMcpAuth.applyToCatalogServers(
      {
        'gateway': {
          'type': 'http',
          'url': 'https://server.smithery.ai/@ctx',
        },
        'Context7': {
          'type': 'http',
          'url': 'https://context7-mcp--upstash.run.tools',
        },
      },
      'tok',
    );
    expect(
      (out['gateway']!['headers'] as Map)['Authorization'],
      'Bearer tok',
    );
    expect(out['Context7']!.containsKey('headers'), isFalse);
  });
}
