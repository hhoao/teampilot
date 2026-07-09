import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/hub_publish/bundle_provenance_lookup.dart';

Skill _skill({
  required String id,
  required String name,
  String directory = '',
  String? repoOwner,
  String? repoName,
  String? repoBranch,
}) => Skill(
  id: id,
  name: name,
  description: '',
  directory: directory,
  repoOwner: repoOwner,
  repoName: repoName,
  repoBranch: repoBranch,
  installedAt: 1,
  updatedAt: 1,
);

Plugin _plugin({
  required String id,
  required String name,
  String? marketplaceOwner,
  String? marketplaceName,
  String? marketplaceBranch,
}) => Plugin(
  id: id,
  name: name,
  description: '',
  version: '1.0.0',
  directory: 'dir',
  marketplaceOwner: marketplaceOwner,
  marketplaceName: marketplaceName,
  marketplaceBranch: marketplaceBranch,
  installedAt: 1,
  updatedAt: 1,
);

void main() {
  test('skill with repo fields maps to SkillDependencyRef', () {
    final lookup = BundleProvenanceLookup(
      skills: [
        _skill(
          id: 'o/r:dir',
          name: 'N',
          repoOwner: 'o',
          repoName: 'r',
          repoBranch: 'main',
          directory: 'skills/dir',
        ),
      ],
      plugins: const [],
      mcps: const [],
    );
    final result = lookup.resolve(
      skillIds: ['o/r:dir'],
      pluginIds: const [],
      mcpServerIds: const [],
    );
    expect(result.skillDeps.single.repoOwner, 'o');
    expect(result.skillDeps.single.repoName, 'r');
    expect(result.skillDeps.single.directory, 'skills/dir');
    expect(result.skillDeps.single.name, 'N');
    expect(result.nonPortableIds, isEmpty);
  });

  test('plugin with marketplace fields maps to PluginDependencyRef', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: [
        _plugin(
          id: 'o/m/entry',
          name: 'P',
          marketplaceOwner: 'o',
          marketplaceName: 'm',
          marketplaceBranch: 'main',
        ),
      ],
      mcps: const [],
    );
    final result = lookup.resolve(
      skillIds: const [],
      pluginIds: ['o/m/entry'],
      mcpServerIds: const [],
    );
    expect(result.pluginDeps.single.marketplaceOwner, 'o');
    expect(result.pluginDeps.single.marketplaceName, 'm');
    expect(result.pluginDeps.single.entryName, 'entry');
    expect(result.pluginDeps.single.name, 'P');
    expect(result.nonPortableIds, isEmpty);
  });

  test('local-only skill is non-portable', () {
    final lookup = BundleProvenanceLookup(
      skills: [_skill(id: 'local-skill', name: 'L', directory: 'local-skill')],
      plugins: const [],
      mcps: const [],
    );
    final result = lookup.resolve(
      skillIds: ['local-skill'],
      pluginIds: const [],
      mcpServerIds: const [],
    );
    expect(result.nonPortableIds, contains('local-skill'));
    expect(result.skillDeps, isEmpty);
  });

  test('MCP with command-only server map is portable after sanitize', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: const [],
      mcps: [
        McpServer(
          id: 'demo',
          name: 'Demo',
          server: {
            'command': 'npx',
            'args': ['-y', 'demo-mcp'],
            'env': {'API_KEY': 'secret'},
          },
        ),
      ],
    );
    final result = lookup.resolve(
      skillIds: const [],
      pluginIds: const [],
      mcpServerIds: ['demo'],
    );
    expect(result.mcpDeps.single.server.containsKey('env'), isFalse);
    expect(result.mcpDeps.single.server['command'], 'npx');
    expect(result.nonPortableIds, isEmpty);
  });

  test('MCP with empty server map is non-portable', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: const [],
      mcps: [const McpServer(id: 'empty', name: 'E', server: {})],
    );
    final result = lookup.resolve(
      skillIds: const [],
      pluginIds: const [],
      mcpServerIds: ['empty'],
    );
    expect(result.nonPortableIds, contains('empty'));
    expect(result.mcpDeps, isEmpty);
  });

  test('unknown ids are non-portable', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: const [],
      mcps: const [],
    );
    final result = lookup.resolve(
      skillIds: ['missing-skill'],
      pluginIds: ['missing-plugin'],
      mcpServerIds: ['missing-mcp'],
    );
    expect(
      result.nonPortableIds,
      unorderedEquals(['missing-skill', 'missing-plugin', 'missing-mcp']),
    );
  });

  test('MCP sanitize strips nested headers and Authorization', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: const [],
      mcps: [
        McpServer(
          id: 'remote',
          name: 'Remote',
          server: {
            'url': 'https://example.com/mcp',
            'type': 'http',
            'headers': {'Authorization': 'Bearer secret'},
            'Authorization': 'Bearer secret',
            'nested': {
              'headers': {'X-Token': 't'},
              'keep': true,
            },
          },
        ),
      ],
    );
    final result = lookup.resolve(
      skillIds: const [],
      pluginIds: const [],
      mcpServerIds: ['remote'],
    );
    final server = result.mcpDeps.single.server;
    expect(server.containsKey('headers'), isFalse);
    expect(server.containsKey('Authorization'), isFalse);
    expect(server['url'], 'https://example.com/mcp');
    expect((server['nested'] as Map)['keep'], isTrue);
    expect((server['nested'] as Map).containsKey('headers'), isFalse);
    expect(result.nonPortableIds, isEmpty);
  });
}
