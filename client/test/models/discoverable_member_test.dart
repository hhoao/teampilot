import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';

void main() {
  test('round-trips JSON with nested member fields', () {
    const m = DiscoverableMember(
      key: 'teampilot/builtin/developer',
      name: 'Developer',
      description: 'Implements features',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(
        name: 'developer',
        responsibilities: 'You implement code.',
        playbook: 'Use TDD.',
        capabilities: {'implementation'},
      ),
    );
    final decoded = DiscoverableMember.fromJson(m.toJson());
    expect(decoded, m);
  });

  test('toMemberConfig assigns slug id and joinedAt', () {
    const m = DiscoverableMember(
      key: 'local/abc',
      name: 'PM',
      description: '',
      category: 'Business',
      source: ExpertMemberSource.local,
      member: DiscoverableTeamMember(name: 'Product Manager', responsibilities: 'Plan.'),
    );
    final cfg = m.toMemberConfig(joinedAt: 1);
    expect(cfg.id, isNotEmpty);
    expect(cfg.responsibilities, 'Plan.');
    expect(cfg.joinedAt, 1);
  });

  test('round-trips JSON with pluginDeps and mcpDeps', () {
    const m = DiscoverableMember(
      key: 'teampilot/builtin/pack-expert',
      name: 'Pack Expert',
      description: 'Full capability pack',
      category: 'Development',
      source: ExpertMemberSource.builtin,
      member: DiscoverableTeamMember(
        name: 'pack-expert',
        responsibilities: 'Ship with deps.',
      ),
      pluginDeps: [
        PluginDependencyRef(
          marketplaceOwner: 'o',
          marketplaceName: 'n',
          marketplaceBranch: 'main',
          entryName: 'plug',
          name: 'Plug',
        ),
      ],
      mcpDeps: [
        McpDependencyRef(
          id: 'srv',
          name: 'Server',
          server: {
            'command': 'npx',
            'args': ['-y', 'pkg'],
          },
        ),
      ],
    );
    final decoded = DiscoverableMember.fromJson(m.toJson());
    expect(decoded, m);
  });

  test('defaults pluginDeps and mcpDeps to empty lists when omitted', () {
    const member = DiscoverableTeamMember(name: 'test');
    final m = DiscoverableMember(
      key: 'k',
      name: 'n',
      description: '',
      category: 'c',
      source: ExpertMemberSource.builtin,
      member: member,
    );
    final json = m.toJson();
    expect(json.containsKey('pluginDeps'), isFalse);
    expect(json.containsKey('mcpDeps'), isFalse);

    final decoded = DiscoverableMember.fromJson(json);
    expect(decoded.pluginDeps, isEmpty);
    expect(decoded.mcpDeps, isEmpty);
  });

  test('source encodes and decodes correctly', () {
    for (final source in ExpertMemberSource.values) {
      const member = DiscoverableTeamMember(name: 'test');
      final m = DiscoverableMember(
        key: 'k',
        name: 'n',
        description: '',
        category: 'c',
        source: source,
        member: member,
      );
      final json = m.toJson();
      expect(json['source'], source.value);
      expect(DiscoverableMember.fromJson(json).source, source);
    }
  });
}
