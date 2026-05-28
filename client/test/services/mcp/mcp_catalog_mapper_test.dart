import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/mcp/mcp_catalog_mapper.dart';

void main() {
  test('fromSmitheryJson uses gateway when list omits deploymentUrl', () {
    final listing = McpCatalogMapper.fromSmitheryJson({
      'qualifiedName': 'github',
      'displayName': 'GitHub',
      'description': 'GitHub MCP',
      'remote': true,
    });
    expect(listing, isNotNull);
    expect(listing!.serverSpec['url'], 'https://server.smithery.ai/@github');
    expect(listing.smitheryQualifiedName, 'github');
  });

  test('fromSmitheryJson builds http spec from deploymentUrl', () {
    final listing = McpCatalogMapper.fromSmitheryJson({
      'qualifiedName': 'github',
      'displayName': 'GitHub',
      'description': 'GitHub MCP',
      'deploymentUrl': 'https://github.run.tools',
      'remote': true,
      'verified': true,
    });
    expect(listing, isNotNull);
    expect(listing!.id, 'github');
    expect(listing.serverSpec['type'], 'http');
    expect(listing.serverSpec['url'], 'https://github.run.tools');
  });

  test('fromRegistryEntry keeps only latest active', () {
    final latest = McpCatalogMapper.fromRegistryEntry({
      'server': {
        'name': 'ai.example/demo',
        'description': 'Demo',
        'remotes': [
          {'type': 'streamable-http', 'url': 'https://example.com/mcp'},
        ],
      },
      '_meta': {
        'io.modelcontextprotocol.registry/official': {
          'isLatest': true,
          'status': 'active',
        },
      },
    });
    expect(latest, isNotNull);
    expect(latest!.serverSpec['type'], 'http');

    final old = McpCatalogMapper.fromRegistryEntry({
      'server': {
        'name': 'ai.example/demo',
        'remotes': [
          {'type': 'streamable-http', 'url': 'https://example.com/mcp'},
        ],
      },
      '_meta': {
        'io.modelcontextprotocol.registry/official': {
          'isLatest': false,
          'status': 'active',
        },
      },
    });
    expect(old, isNull);
  });
}
