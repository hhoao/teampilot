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

  test('forLocale overlays zh display fields and falls back otherwise', () {
    const m = DiscoverableMember(
      key: 'hhoao/teampilot-resources/member-hub/gstack-reviewer',
      name: 'gstack Reviewer',
      description: 'Staff-engineer review',
      category: 'Development',
      source: ExpertMemberSource.registry,
      member: DiscoverableTeamMember(
        name: 'review',
        responsibilities: 'Review for correctness.',
        playbook: 'Follow /review.',
      ),
      i18n: {
        'zh': DiscoverableMemberLocaleText(
          name: 'gstack 评审官',
          description: 'Staff 工程师评审',
          category: '开发',
          responsibilities: '评审正确性。',
          playbook: '遵循 /review。',
        ),
      },
    );

    final zh = m.forLocale('zh-CN');
    expect(zh.name, 'gstack 评审官');
    expect(zh.description, 'Staff 工程师评审');
    expect(zh.category, '开发');
    expect(zh.member.responsibilities, '评审正确性。');
    expect(zh.member.playbook, '遵循 /review。');
    expect(zh.member.name, 'review');

    final en = m.forLocale('en');
    expect(en.name, m.name);
    expect(en.member.responsibilities, m.member.responsibilities);

    final roundTrip = DiscoverableMember.fromJson(m.toJson());
    expect(roundTrip, m);
    expect(roundTrip.forLocale('zh').name, 'gstack 评审官');
  });

  test('clone source and clonedAt round-trip through JSON', () {
    final m = DiscoverableMember(
      key: 'acme/experts/pm',
      name: 'Product Manager',
      description: 'Plans.',
      category: 'Business',
      source: ExpertMemberSource.clone,
      member: const DiscoverableTeamMember(name: 'pm'),
      originTeamKey: 'acme/teams/squad',
      clonedAt: 1723000000000,
    );
    final decoded = DiscoverableMember.fromJson(m.toJson());
    expect(decoded, m);
    expect(decoded.source, ExpertMemberSource.clone);
    expect(decoded.clonedAt, 1723000000000);
  });

  test('copyWith overrides source, originTeamKey and clonedAt', () {
    const m = DiscoverableMember(
      key: 'acme/experts/pm',
      name: 'PM',
      description: '',
      category: 'Business',
      source: ExpertMemberSource.registry,
      member: DiscoverableTeamMember(name: 'pm'),
    );
    final updated = m.copyWith(
      source: ExpertMemberSource.clone,
      originTeamKey: 'acme/teams/squad',
      clonedAt: 1723000000000,
    );
    expect(updated.source, ExpertMemberSource.clone);
    expect(updated.originTeamKey, 'acme/teams/squad');
    expect(updated.clonedAt, 1723000000000);
    expect(updated.key, 'acme/experts/pm');
  });
}
