import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/hub_publish/bundle_provenance_lookup.dart';
import 'package:teampilot/services/hub_publish/team_profile_publish_mapper.dart';

void main() {
  final portableSkill = Skill(
    id: 'o/r:dir',
    name: 'N',
    description: '',
    directory: 'skills/dir',
    repoOwner: 'o',
    repoName: 'r',
    repoBranch: 'main',
    installedAt: 1,
    updatedAt: 1,
  );

  BundleProvenanceLookup lookupWith({List<Skill> skills = const []}) =>
      BundleProvenanceLookup(
        skills: skills,
        plugins: const [],
        mcps: const [],
      );

  test('mapper strips secrets and emits DiscoverableTeam', () {
    final team = TeamProfile(
      id: 'research',
      name: 'Research Squad',
      description: 'A team for deep research.',
      extraArgs: '--foo',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      skillIds: ['o/r:dir'],
      providerIdsByTool: {'claude': 'secret-provider-id'},
      modelsByTool: {'claude': 'claude-opus'},
      activePresetId: 'personal-preset',
      roster: const [
        TeamRosterSlot(
          id: 'team-lead',
          expertKey: 'teampilot/builtin/team-lead',
        ),
      ],
    );

    final result = TeamProfilePublishMapper.map(
      team: team,
      expertKeyRemap: const {},
      lookup: lookupWith(skills: [portableSkill]),
      key: 'hhoao/teampilot-resources/team-hub/research-squad',
      category: 'Research',
      author: 'flashskyai',
      updatedAt: 1700000000000,
    );

    expect(result, isA<PublishReadyTeam>());
    final ready = result as PublishReadyTeam;
    final json = ready.team.toJson();
    expect(json['name'], 'Research Squad');
    expect(json['description'], 'A team for deep research.');
    expect(json['category'], 'Research');
    expect(json['author'], 'flashskyai');
    expect(json['cli'], 'claude');
    expect(json['teamMode'], 'mixed');
    expect(json['extraArgs'], '--foo');
    expect(json['skillDeps'], isNotEmpty);
    expect(json.containsKey('providerIdsByTool'), isFalse);
    expect(json.containsKey('modelsByTool'), isFalse);
    expect(json.containsKey('activePresetId'), isFalse);
    expect(json.containsKey('cliEffortLevels'), isFalse);
    expect(ready.team.roster.single.expertKey, 'teampilot/builtin/team-lead');
    expect(ready.team.skillDeps.single.repoOwner, 'o');
  });

  test('mapper remaps local expert keys', () {
    final team = TeamProfile(
      id: 't',
      name: 'T',
      roster: const [
        TeamRosterSlot(id: 'arch', expertKey: 'local/abc'),
      ],
    );

    final result = TeamProfilePublishMapper.map(
      team: team,
      expertKeyRemap: const {'local/abc': 'hhoao/teampilot-resources/member-hub/arch'},
      lookup: lookupWith(),
      key: 'o/r/t',
      category: 'General',
    );

    expect(result, isA<PublishReadyTeam>());
    final ready = result as PublishReadyTeam;
    expect(ready.team.roster.single.expertKey, 'hhoao/teampilot-resources/member-hub/arch');
  });

  test('mapper fails closed when local expert keys remain', () {
    final team = TeamProfile(
      id: 't',
      name: 'T',
      roster: const [
        TeamRosterSlot(id: 'arch', expertKey: 'local/abc'),
      ],
    );

    final result = TeamProfilePublishMapper.map(
      team: team,
      expertKeyRemap: const {},
      lookup: lookupWith(),
      key: 'o/r/t',
      category: 'General',
    );

    expect(result, isA<PublishBlocked>());
    final blocked = result as PublishBlocked;
    expect(blocked.reasons, isNotEmpty);
    expect(
      blocked.reasons.any((r) => r.contains('local/abc')),
      isTrue,
    );
  });

  test('mapper fails closed when bundle deps are non-portable', () {
    final team = TeamProfile(
      id: 't',
      name: 'T',
      skillIds: ['local-only'],
      roster: const [
        TeamRosterSlot(
          id: 'team-lead',
          expertKey: 'teampilot/builtin/team-lead',
        ),
      ],
    );

    final result = TeamProfilePublishMapper.map(
      team: team,
      expertKeyRemap: const {},
      lookup: lookupWith(
        skills: [
          Skill(
            id: 'local-only',
            name: 'L',
            description: '',
            directory: 'local-only',
            installedAt: 1,
            updatedAt: 1,
          ),
        ],
      ),
      key: 'o/r/t',
      category: 'General',
    );

    expect(result, isA<PublishBlocked>());
    final blocked = result as PublishBlocked;
    expect(blocked.reasons.any((r) => r.contains('local-only')), isTrue);
  });
}
