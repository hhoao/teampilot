import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/hub_publish/bundle_provenance_lookup.dart';
import 'package:teampilot/services/hub_publish/expert_publish_mapper.dart';

void main() {
  test('expert mapper stamps registry fields and keeps portable skillDeps', () {
    final lookup = BundleProvenanceLookup(
      skills: [
        Skill(
          id: 'o/r:dir',
          name: 'N',
          description: '',
          directory: 'skills/dir',
          repoOwner: 'o',
          repoName: 'r',
          repoBranch: 'main',
          installedAt: 1,
          updatedAt: 1,
        ),
      ],
      plugins: const [],
      mcps: const [],
    );

    final local = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: 'Architect',
      category: 'Engineering',
      source: ExpertMemberSource.local,
      originTeamKey: 'some-team',
      tags: const {'design'},
      member: const DiscoverableTeamMember(
        name: 'Arch',
        prompt: 'design systems',
      ),
      skillDeps: const [
        SkillDependencyRef(
          repoOwner: 'o',
          repoName: 'r',
          repoBranch: 'main',
          directory: 'skills/dir',
          name: 'N',
        ),
      ],
    );

    final result = ExpertPublishMapper.map(
      member: local,
      lookup: lookup,
      key: 'hhoao/teampilot/member-hub/arch',
      author: 'flashskyai',
      updatedAt: 1700000000000,
    );

    expect(result, isA<PublishReadyExpert>());
    final ready = result as PublishReadyExpert;
    expect(ready.member.key, 'hhoao/teampilot/member-hub/arch');
    expect(ready.member.source, ExpertMemberSource.registry);
    expect(ready.member.originTeamKey, isNull);
    expect(ready.member.author, 'flashskyai');
    expect(ready.member.skillDeps.single.repoOwner, 'o');
    final json = ready.member.toJson();
    expect(json['source'], 'registry');
    expect(json.containsKey('originTeamKey'), isFalse);
  });

  test('expert mapper keeps portable pluginDeps and mcpDeps', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: const [],
      mcps: const [],
    );

    final local = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: '',
      category: 'Engineering',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
      pluginDeps: const [
        PluginDependencyRef(
          marketplaceOwner: 'acme',
          marketplaceName: 'tools',
          marketplaceBranch: 'main',
          entryName: 'lint',
          name: 'Lint',
        ),
      ],
      mcpDeps: const [
        McpDependencyRef(
          id: 'mcp-fs',
          name: 'Filesystem',
          description: 'fs',
          server: {'command': 'npx', 'args': ['mcp-fs']},
        ),
      ],
    );

    final result = ExpertPublishMapper.map(
      member: local,
      lookup: lookup,
      key: 'hhoao/teampilot/member-hub/arch',
    );

    expect(result, isA<PublishReadyExpert>());
    final ready = result as PublishReadyExpert;
    expect(ready.member.pluginDeps.single.entryName, 'lint');
    expect(ready.member.mcpDeps.single.id, 'mcp-fs');
    expect(ready.member.toJson()['pluginDeps'], isNotEmpty);
    expect(ready.member.toJson()['mcpDeps'], isNotEmpty);
  });

  test('expert mapper resolves plugin/MCP ids via BundleProvenanceLookup', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: [
        Plugin(
          id: 'acme/tools/lint',
          name: 'Lint',
          description: '',
          version: '1',
          directory: 'plugins/lint',
          marketplaceOwner: 'acme',
          marketplaceName: 'tools',
          marketplaceBranch: 'main',
          installedAt: 1,
          updatedAt: 1,
        ),
      ],
      mcps: [
        McpServer(
          id: 'mcp-fs',
          name: 'Filesystem',
          description: 'fs',
          server: const {
            'command': 'npx',
            'args': ['mcp-fs'],
            'env': {'TOKEN': 'secret'},
          },
        ),
      ],
    );

    final local = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: '',
      category: 'Engineering',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
    );

    final result = ExpertPublishMapper.map(
      member: local,
      lookup: lookup,
      pluginIds: const ['acme/tools/lint'],
      mcpServerIds: const ['mcp-fs'],
      key: 'hhoao/teampilot/member-hub/arch',
    );

    expect(result, isA<PublishReadyExpert>());
    final ready = result as PublishReadyExpert;
    expect(ready.member.pluginDeps.single.marketplaceOwner, 'acme');
    expect(ready.member.mcpDeps.single.id, 'mcp-fs');
    expect(ready.member.mcpDeps.single.server.containsKey('env'), isFalse);
  });

  test('expert mapper blocks when skillDeps are non-portable', () {
    final lookup = BundleProvenanceLookup(
      skills: [
        Skill(
          id: 'local-skill',
          name: 'L',
          description: '',
          directory: 'local-skill',
          installedAt: 1,
          updatedAt: 1,
        ),
      ],
      plugins: const [],
      mcps: const [],
    );

    final local = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: '',
      category: 'Engineering',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
      skillDeps: const [],
    );

    final result = ExpertPublishMapper.map(
      member: local,
      lookup: lookup,
      skillIds: const ['local-skill'],
      key: 'hhoao/teampilot/member-hub/arch',
    );

    expect(result, isA<PublishBlockedExpert>());
    final blocked = result as PublishBlockedExpert;
    expect(blocked.reasons.any((r) => r.contains('local-skill')), isTrue);
  });

  test('expert mapper blocks non-portable plugin ids', () {
    final lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: [
        Plugin(
          id: 'local-plugin',
          name: 'Local',
          description: '',
          version: '1',
          directory: 'plugins/local',
          installedAt: 1,
          updatedAt: 1,
        ),
      ],
      mcps: const [],
    );

    final local = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: '',
      category: 'Engineering',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
    );

    final result = ExpertPublishMapper.map(
      member: local,
      lookup: lookup,
      pluginIds: const ['local-plugin'],
      key: 'hhoao/teampilot/member-hub/arch',
    );

    expect(result, isA<PublishBlockedExpert>());
    final blocked = result as PublishBlockedExpert;
    expect(blocked.reasons.any((r) => r.contains('local-plugin')), isTrue);
  });
}
