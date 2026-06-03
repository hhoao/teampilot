import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';
import 'package:teampilot/services/team_hub/git_registry_team_hub_source.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Map<Uri, String> network() {
    const reg = kDefaultTeamHubRegistry;
    return {
      reg.rawUri('index.json'): jsonEncode({
        'teams': [
          {'slug': 'research-squad'},
          {'slug': 'qa-pair'},
        ],
      }),
      reg.rawUri('teams/research-squad/team.json'): jsonEncode({
        'key': 'ignored',
        'name': 'Research Squad',
        'description': 'deep research',
        'category': 'Research',
        'updatedAt': 2,
        'cli': 'claude',
      }),
      reg.rawUri('teams/qa-pair/team.json'): jsonEncode({
        'key': 'ignored',
        'name': 'QA Pair',
        'description': 'qa',
        'category': 'Testing',
        'updatedAt': 1,
        'cli': 'flashskyai',
      }),
    };
  }

  test('fetches teams from the registry and stamps keys', () async {
    final net = network();
    final source = GitRegistryTeamHubSource(
      fetch: (uri) async => net[uri],
    );

    final teams = await source.fetchTeams();
    expect(teams, hasLength(2));
    expect(
      teams.map((t) => t.key),
      containsAll(<String>[
        'flashskyai/team-hub/research-squad',
        'flashskyai/team-hub/qa-pair',
      ]),
    );
    final categories = await source.categories();
    expect(categories, containsAll(<String>['Research', 'Testing']));
  });

  test('second call without forceRefresh serves from cache', () async {
    final net = network();
    var calls = 0;
    final source = GitRegistryTeamHubSource(
      fetch: (uri) async {
        calls++;
        return net[uri];
      },
    );

    await source.fetchTeams();
    final firstCalls = calls;
    expect(firstCalls, greaterThan(0));

    final cached = await source.fetchTeams();
    expect(cached, hasLength(2));
    expect(calls, firstCalls, reason: 'cache hit must not re-fetch');
  });

  test('forceRefresh re-fetches the network', () async {
    final net = network();
    var calls = 0;
    final source = GitRegistryTeamHubSource(
      fetch: (uri) async {
        calls++;
        return net[uri];
      },
    );
    await source.fetchTeams();
    final before = calls;
    await source.fetchTeams(forceRefresh: true);
    expect(calls, greaterThan(before));
  });
}
