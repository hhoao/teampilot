import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';
import 'package:teampilot/services/team_hub/git_registry_team_hub_source.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('default registry points to teampilot-resources', () {
    expect(kDefaultTeamHubRegistry.fullName, 'hhoao/teampilot-resources');
    expect(
      kDefaultTeamHubRegistry.catalogPrefix,
      'hhoao/teampilot-resources/team-hub',
    );
  });

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
    final source = GitRegistryTeamHubSource(fetch: (uri) async => net[uri], storage: testHomeStorage, );

    final teams = await source.fetchTeams();
    expect(teams, hasLength(2));
    expect(
      teams.map((t) => t.key),
      containsAll(<String>[
        'hhoao/teampilot-resources/team-hub/research-squad',
        'hhoao/teampilot-resources/team-hub/qa-pair',
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
                                             storage: testHomeStorage,
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
                                             storage: testHomeStorage,
    );
    await source.fetchTeams();
    final before = calls;
    await source.fetchTeams(forceRefresh: true);
    expect(calls, greaterThan(before));
  });

  test('cacheDirOverride writes via injected fs at the override path', () async {
    final net = network();
    final fs = InMemoryFilesystem();
    const cacheDir = '/device-local/catalog-cache/team-hub';
    final source = GitRegistryTeamHubSource(
      fetch: (uri) async => net[uri],
      fs: fs,
      cacheDirOverride: cacheDir,
                                             storage: testHomeStorage,
    );

    final teams = await source.fetchTeams();
    expect(teams, hasLength(2));

    final cacheFile = fs.pathContext.join(
      cacheDir,
      '${kDefaultTeamHubRegistry.owner}-${kDefaultTeamHubRegistry.name}',
      'teams.json',
    );
    final written = fs.files[cacheFile];
    expect(written, isNotNull, reason: 'cache must land at the override path');
    final decoded = (jsonDecode(written!) as List)
        .whereType<Map>()
        .map((m) => DiscoverableTeam.fromJson(m.cast<String, Object?>()))
        .toList();
    expect(decoded, hasLength(2));

    // Cache hit on a fresh source sharing the injected fs — no re-fetch.
    var calls = 0;
    final replay = GitRegistryTeamHubSource(
      fetch: (uri) async {
        calls++;
        return net[uri];
      },
      fs: fs,
      cacheDirOverride: cacheDir,
                                             storage: testHomeStorage,
    );
    final cached = await replay.fetchTeams();
    expect(cached, hasLength(2));
    expect(calls, 0, reason: 'cache read must go through the injected fs');
  });
}
