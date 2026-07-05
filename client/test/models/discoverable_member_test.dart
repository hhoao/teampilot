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
        prompt: 'You implement code.',
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
      member: DiscoverableTeamMember(name: 'Product Manager', prompt: 'Plan.'),
    );
    final cfg = m.toMemberConfig(joinedAt: 1);
    expect(cfg.id, isNotEmpty);
    expect(cfg.prompt, 'Plan.');
    expect(cfg.joinedAt, 1);
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
