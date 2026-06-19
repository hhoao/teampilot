import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server_spec.dart';

void main() {
  group('McpServerSpec.fromCatalogJson', () {
    test('parses stdio server', () {
      final spec = McpServerSpec.fromCatalogJson('fetch', {
        'type': 'stdio',
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-fetch'],
        'env': {'FOO': 'bar'},
      });
      expect(spec, isA<StdioMcpServer>());
      final stdio = spec! as StdioMcpServer;
      expect(stdio.name, 'fetch');
      expect(stdio.command, 'npx');
      expect(stdio.args, ['-y', '@modelcontextprotocol/server-fetch']);
      expect(stdio.env, {'FOO': 'bar'});
    });

    test('parses remote http server', () {
      final spec = McpServerSpec.fromCatalogJson('ctx', {
        'type': 'http',
        'url': 'https://example.com/mcp',
        'headers': {'Authorization': 'Bearer tok'},
      });
      expect(spec, isA<RemoteMcpServer>());
      final remote = spec! as RemoteMcpServer;
      expect(remote.url, 'https://example.com/mcp');
      expect(remote.headers['Authorization'], 'Bearer tok');
    });

    test('round-trips stdio catalog json', () {
      const original = {
        'type': 'stdio',
        'command': 'uvx',
        'args': ['pkg'],
      };
      final spec = McpServerSpec.fromCatalogJson('demo', original)!;
      expect(spec.toCatalogJson(), original);
    });

    test('round-trips remote catalog json', () {
      const original = {
        'type': 'http',
        'url': 'https://example.com/mcp',
        'headers': {'X-Test': '1'},
      };
      final spec = McpServerSpec.fromCatalogJson('demo', original)!;
      expect(spec.toCatalogJson(), original);
    });
  });
}
