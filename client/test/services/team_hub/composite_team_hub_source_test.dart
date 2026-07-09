import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_hub/builtin_team_templates.dart';
import 'package:teampilot/services/team_hub/composite_team_hub_source.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

class _FakeDelegate implements TeamHubSource {
  _FakeDelegate(this.teams);

  final List<DiscoverableTeam> teams;
  var fetchCalls = 0;

  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async {
    fetchCalls++;
    return teams;
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => [];
}

void main() {
  test('prepends built-ins and dedupes remote keys', () async {
    final remoteDup = DiscoverableTeam(
      key: '$kBuiltinTeamHubKeyPrefix/superpowers-trio',
      name: 'Remote override',
      description: '',
      category: 'X',
      updatedAt: 1,
    );
    const remoteOther = DiscoverableTeam(
      key: 'flashskyai/team-hub/other',
      name: 'Other',
      description: '',
      category: 'Y',
      updatedAt: 2,
    );
    final delegate = _FakeDelegate([remoteDup, remoteOther]);
    final source = CompositeTeamHubSource.withDefaults(delegate);

    final teams = await source.fetchTeams();
    expect(teams.first.key, kSuperpowersTrioTeamTemplate.key);
    expect(teams.first.name, kSuperpowersTrioTeamTemplate.name);
    expect(teams, hasLength(2));
    expect(teams.last.key, remoteOther.key);
  });

  test('built-in superpowers quartet is mixed with four roster slots', () {
    final team = kSuperpowersTrioTeamTemplate;
    expect(team.teamMode, TeamMode.mixed);
    expect(team.roster, hasLength(4));
    expect(team.roster.first.id, 'team-lead');
    expect(team.roster[1].id, 'architect');
    expect(team.roster[2].id, 'builder');
    expect(team.roster.last.id, 'reviewer');
    expect(team.skillDeps, isNotEmpty);
    expect(
      team.roster.every((slot) => slot.expertKey.contains('superpowers-')),
      isTrue,
    );
  });

  test('categories merges built-in and remote', () async {
    final delegate = _FakeDelegate(const [
      DiscoverableTeam(
        key: 'r/a',
        name: 'R',
        description: '',
        category: 'Remote',
        updatedAt: 1,
      ),
    ]);
    final source = CompositeTeamHubSource.withDefaults(delegate);
    final cats = await source.categories();
    expect(cats, containsAll(['Workflow', 'Remote']));
  });
}
