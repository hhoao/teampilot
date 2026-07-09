import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
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
      key: 'flashskyai/member-hub/arch',
      author: 'flashskyai',
      updatedAt: 1700000000000,
    );

    expect(result, isA<PublishReadyExpert>());
    final ready = result as PublishReadyExpert;
    expect(ready.member.key, 'flashskyai/member-hub/arch');
    expect(ready.member.source, ExpertMemberSource.registry);
    expect(ready.member.originTeamKey, isNull);
    expect(ready.member.author, 'flashskyai');
    expect(ready.member.skillDeps.single.repoOwner, 'o');
    final json = ready.member.toJson();
    expect(json['source'], 'registry');
    expect(json.containsKey('originTeamKey'), isFalse);
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
      skillDeps: const [
        // Non-portable: no repo provenance — mapper resolves via lookup ids
        // when skillIds are provided; here we pass skillIds separately.
      ],
    );

    final result = ExpertPublishMapper.map(
      member: local,
      lookup: lookup,
      skillIds: const ['local-skill'],
      key: 'flashskyai/member-hub/arch',
    );

    expect(result, isA<PublishBlockedExpert>());
    final blocked = result as PublishBlockedExpert;
    expect(blocked.reasons.any((r) => r.contains('local-skill')), isTrue);
  });
}
