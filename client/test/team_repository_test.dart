import 'package:flashskyai_client/models/team_config.dart';
import 'package:flashskyai_client/repositories/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads an empty list when no teams are saved', () async {
    final repository = TeamRepository(await SharedPreferences.getInstance());

    expect(await repository.loadTeams(), isEmpty);
  });

  test('saves and loads multiple teams', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = TeamRepository(preferences);
    const teams = [
      TeamConfig(
        id: '1',
        name: 'hhoa',
        workingDirectory: '/work/hhoa',
        members: [TeamMemberConfig(id: 'member-0', name: 'planner')],
      ),
      TeamConfig(
        id: '2',
        name: 'agent',
        workingDirectory: '/work/agent',
        members: [
          TeamMemberConfig(id: 'member-1', name: 'planner', model: 'sonnet'),
        ],
      ),
    ];

    await repository.saveTeams(teams);

    expect(await repository.loadTeams(), teams);
  });

  test('falls back to an empty list for invalid json', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(TeamRepository.storageKey, 'not-json');
    final repository = TeamRepository(preferences);

    expect(await repository.loadTeams(), isEmpty);
  });
}
