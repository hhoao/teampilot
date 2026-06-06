import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

class _RecordingLifecycleService extends SessionLifecycleService {
  _RecordingLifecycleService()
    : super(appDataBasePath: Directory.systemTemp.path);

  final destroyedTeams = <String>[];

  @override
  Future<void> destroyCliToolState(String teamId) async {
    destroyedTeams.add(teamId);
  }
}

void main() {
  group('save/load TeamPilot team metadata', () {
    late Directory uiRoot;
    late Directory cliRoot;

    setUp(() async {
      uiRoot = await Directory.systemTemp.createTemp('teams_ui_');
      cliRoot = await Directory.systemTemp.createTemp('teams_cli_');
    });

    tearDown(() async {
      if (await uiRoot.exists()) await uiRoot.delete(recursive: true);
      if (await cliRoot.exists()) await cliRoot.delete(recursive: true);
    });

    TeamRepository repo() => TeamRepository(rootDir: uiRoot.path);

    Future<void> writeCliTeam(String folder, Map<String, Object?> json) async {
      final dir = Directory(p.join(cliRoot.path, folder));
      await dir.create(recursive: true);
      await File(
        p.join(dir.path, 'config.json'),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    }

    test('loads an empty list when nothing is saved', () async {
      expect(await repo().loadTeams(), isEmpty);
    });

    test('saves and reloads multiple teams from UI dir only', () async {
      const teams = [
        TeamConfig(
          id: 'hhoa',
          name: 'hhoa',
          members: [TeamMemberConfig(id: 'planner', name: 'planner')],
        ),
        TeamConfig(
          id: 'agent',
          name: 'agent',
          members: [
            TeamMemberConfig(id: 'planner', name: 'planner', model: 'sonnet'),
          ],
        ),
      ];

      await repo().saveTeams(teams);
      final loaded = await repo().loadTeams();

      expect(loaded.map((t) => t.name).toSet(), {'hhoa', 'agent'});
      final agent = loaded.firstWhere((t) => t.name == 'agent');
      expect(agent.members.single.model, 'sonnet');
    });

    test('ignores CLI-only teams under .flashskyai teams dir', () async {
      await writeCliTeam('huji', {
        'name': 'huji',
        'createdAt': 1778231391883,
        'members': [
          {'name': 'team-lead', 'joinedAt': 1778231391883},
        ],
      });

      expect(await repo().loadTeams(), isEmpty);
    });

    test('does not let CLI files override UI metadata', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 'shared',
          name: 'shared',
          createdAt: 100,
          loop: false,
          members: [
            TeamMemberConfig(
              id: 'alice',
              name: 'alice',
              model: 'sonnet',
              provider: 'anthropic',
              joinedAt: 100,
            ),
          ],
        ),
      ]);

      await writeCliTeam('shared', {
        'name': 'shared',
        'createdAt': 999,
        'loop': true,
        'members': [
          {'name': 'alice', 'joinedAt': 999},
        ],
      });

      final shared = (await repo().loadTeams()).single;
      expect(shared.createdAt, 100);
      expect(shared.loop, false);
      expect(shared.members.single.joinedAt, 100);
      expect(shared.members.single.model, 'sonnet');
      expect(shared.members.single.provider, 'anthropic');
    });

    test('writes one json file per team in the UI dir', () async {
      const team = TeamConfig(
        id: 'demo',
        name: 'demo',
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );

      await repo().saveTeams(const [team]);

      final file = File(p.join(uiRoot.path, 'demo.json'));
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), contains('"name": "demo"'));
    });

    test('does not write CLI team config files on save', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 't',
          name: 't',
          createdAt: 42,
          loop: true,
          members: [
            TeamMemberConfig(
              id: 'alice',
              name: 'alice',
              model: 'sonnet',
              provider: 'anthropic',
              joinedAt: 42,
            ),
          ],
        ),
      ]);

      expect(await Directory(p.join(cliRoot.path, 't')).exists(), isFalse);
      expect(await File(p.join(uiRoot.path, 't.json')).exists(), isTrue);
    });

    test('sorts by sortOrder when any team has a custom order', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 'b',
          name: 'b',
          createdAt: 200,
          sortOrder: 2,
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
        TeamConfig(
          id: 'a',
          name: 'a',
          createdAt: 100,
          sortOrder: 1,
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      final loaded = await repo().loadTeams();
      expect(loaded.map((t) => t.name).toList(), ['a', 'b']);
    });

    test('stamps createdAt on first save', () async {
      const team = TeamConfig(
        id: 'demo',
        name: 'demo',
        members: [TeamMemberConfig(id: 'm', name: 'm')],
      );

      final before = DateTime.now().millisecondsSinceEpoch;
      await repo().saveTeams(const [team]);
      final loaded = await repo().loadTeams();

      expect(loaded.single.createdAt, greaterThanOrEqualTo(before));
    });

    test('removes UI files for teams no longer in the list', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 'keep',
          name: 'keep',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
        TeamConfig(
          id: 'drop',
          name: 'drop',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      await repo().saveTeams(const [
        TeamConfig(
          id: 'keep',
          name: 'keep',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      expect(await File(p.join(uiRoot.path, 'drop.json')).exists(), isFalse);
      expect(await File(p.join(uiRoot.path, 'keep.json')).exists(), isTrue);
    });

    test('concurrent saves do not fail when replacing the same UI file', () async {
      const team = TeamConfig(
        id: 'default',
        name: 'Default Team',
        members: [TeamMemberConfig(id: 'm', name: 'm')],
      );

      await repo().saveTeams(const [team]);

      await Future.wait([
        for (var i = 0; i < 200; i++) repo().saveTeams(const [team]),
      ]);

      expect(await File(p.join(uiRoot.path, 'Default Team.json')).exists(), isTrue);
    });
  });

  group('deleteTeam', () {
    late Directory uiRoot;
    late Directory cliRoot;

    setUp(() async {
      uiRoot = await Directory.systemTemp.createTemp('teams_ui_');
      cliRoot = await Directory.systemTemp.createTemp('teams_cli_');
    });

    tearDown(() async {
      if (await uiRoot.exists()) await uiRoot.delete(recursive: true);
      if (await cliRoot.exists()) await cliRoot.delete(recursive: true);
    });

    TeamRepository repo() => TeamRepository(rootDir: uiRoot.path);

    test('removes only the UI file', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 'gone',
          name: 'gone',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);
      final cliDir = Directory(p.join(cliRoot.path, 'gone'));
      await cliDir.create(recursive: true);
      await File(p.join(cliDir.path, 'config.json')).writeAsString('{}');

      await repo().deleteTeam('gone');

      expect(await File(p.join(uiRoot.path, 'gone.json')).exists(), isFalse);
      expect(await cliDir.exists(), isTrue);
    });

    test('destroys the team CLI state when deleting a team', () async {
      final lifecycle = _RecordingLifecycleService();
      final repository = TeamRepository(
        rootDir: uiRoot.path,
        lifecycleService: lifecycle,
      );
      await repository.saveTeams(const [
        TeamConfig(
          id: 'gone',
          name: 'gone',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      await repository.deleteTeam('gone');

      expect(lifecycle.destroyedTeams, ['gone']);
    });

    test('is idempotent on missing teams', () async {
      await repo().deleteTeam('never-existed');
    });
  });
}
