import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_mcp_servers.dart';

void main() {
  test('maps stdio and http extra MCP dicts', () {
    final servers = acpMcpServersFromExtra({
      'teammate-bus': {
        'command': '/bridge',
        'args': ['--member', 'lead', '--bus-url', 'http://127.0.0.1/mcp'],
      },
      'teampilot': {
        'type': 'http',
        'url': 'http://127.0.0.1/catalog/mcp',
        'headers': {'X-Member': 'lead'},
      },
    });
    expect(servers, hasLength(2));
    expect(servers[0], isA<acpd.McpServerStdio>());
    expect((servers[0] as acpd.McpServerStdio).name, 'teammate-bus');
    expect((servers[0] as acpd.McpServerStdio).command, '/bridge');
    expect((servers[0] as acpd.McpServerStdio).args, [
      '--member',
      'lead',
      '--bus-url',
      'http://127.0.0.1/mcp',
    ]);
    expect(servers[1], isA<acpd.McpServerHttp>());
    final http = servers[1] as acpd.McpServerHttp;
    expect(http.name, 'teampilot');
    expect(http.url, 'http://127.0.0.1/catalog/mcp');
    expect(http.headers, hasLength(1));
    expect(http.headers.single.name, 'X-Member');
    expect(http.headers.single.value, 'lead');
  });

  test('empty extra yields empty list', () {
    expect(acpMcpServersFromExtra(const {}), isEmpty);
  });

  test('skips entries with neither command nor url', () {
    final servers = acpMcpServersFromExtra({
      'broken': {'type': 'http'},
      'also-broken': {
        'args': ['--x'],
      },
    });
    expect(servers, isEmpty);
  });

  test('reads http headers from a name/value list', () {
    final servers = acpMcpServersFromExtra({
      'teampilot': {
        'type': 'http',
        'url': 'http://127.0.0.1/catalog/mcp',
        'headers': [
          {'name': 'X-Member', 'value': 'lead'},
        ],
      },
    });
    final http = servers.single as acpd.McpServerHttp;
    expect(http.headers.single.name, 'X-Member');
    expect(http.headers.single.value, 'lead');
  });
}
