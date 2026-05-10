import 'package:flashskyai_client/models/team_config.dart';
import 'package:flashskyai_client/controllers/team_controller.dart';
import 'package:flashskyai_client/repositories/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<TeamController> createController({
    TeamLauncher? launcher,
    String currentDirectory = '/work/current',
    List<String> ids = const ['new-id'],
  }) async {
    var index = 0;
    final repository = TeamRepository(await SharedPreferences.getInstance());
    final controller = TeamController(
      repository: repository,
      launcher: launcher ?? (_, _) async {},
      currentDirectoryProvider: () => currentDirectory,
      idProvider: () => ids[index++ % ids.length],
    );
    await controller.load();
    return controller;
  }

  test(
    'creates a default team with a default member when storage is empty',
    () async {
      final controller = await createController();

      expect(controller.teams, hasLength(1));
      expect(controller.selectedTeam?.name, 'Default Team');
      expect(controller.selectedTeam?.workingDirectory, '/work/current');
      expect(controller.selectedTeam?.members, hasLength(1));
      expect(controller.selectedTeam?.members.single.name, 'team-lead');
    },
  );

  test('adds and selects a new team', () async {
    final controller = await createController();

    await controller.addTeam();

    expect(controller.teams, hasLength(2));
    expect(controller.selectedTeam?.id, 'new-id');
    expect(controller.selectedTeam?.members.single.name, 'New Member');
  });

  test('updates selected team and persists it', () async {
    final controller = await createController();

    await controller.updateSelected(
      const TeamConfig(
        id: 'default',
        name: 'agent',
        workingDirectory: '/work/agent',
        members: [
          TeamMemberConfig(
            id: 'member-1',
            name: 'planner',
            provider: 'anthropic',
            model: 'sonnet',
          ),
        ],
      ),
    );

    final reloaded = await createController();
    expect(reloaded.selectedTeam?.name, 'agent');
    expect(reloaded.selectedTeam?.members.single.model, 'sonnet');
  });

  test('adds updates and deletes members', () async {
    final controller = await createController(ids: ['member-2']);

    await controller.addMember();
    expect(controller.selectedTeam?.members, hasLength(2));

    await controller.updateMember(
      'member-2',
      const TeamMemberConfig(
        id: 'member-2',
        name: 'reviewer',
        provider: 'openai',
        model: 'gpt-5.4',
      ),
    );
    expect(controller.selectedTeam?.members.last.name, 'reviewer');
    expect(controller.selectedTeam?.members.last.provider, 'openai');

    await controller.deleteMember('member-2');
    expect(controller.selectedTeam?.members, hasLength(1));
  });

  test('does not delete the final member', () async {
    final controller = await createController();
    final memberId = controller.selectedTeam!.members.single.id;

    await controller.deleteMember(memberId);

    expect(controller.selectedTeam?.members, hasLength(1));
    expect(controller.statusMessage, 'A team needs at least one member.');
  });

  test('launches one valid member', () async {
    final launches = <String>[];
    final controller = await createController(
      launcher: (team, member) async {
        launches.add('${team.name}:${member.name}');
      },
    );
    final member = controller.selectedTeam!.members.single;

    await controller.launchMember(member.id);

    expect(launches, ['Default Team:team-lead']);
    expect(controller.statusMessage, startsWith('Started team-lead:'));
  });

  test('launches every valid member in selected team', () async {
    final launches = <String>[];
    final controller = await createController(
      launcher: (team, member) async {
        launches.add(member.name);
      },
      ids: ['member-2'],
    );
    await controller.addMember();
    await controller.updateMember(
      'member-2',
      const TeamMemberConfig(id: 'member-2', name: 'reviewer'),
    );

    await controller.launchSelectedTeam();

    expect(launches, ['team-lead', 'reviewer']);
    expect(controller.statusMessage, 'Started 2 members.');
  });
}
