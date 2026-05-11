import 'dart:convert';
import 'dart:io';

import 'package:flashskyai_client/models/team_config.dart';
import 'package:flashskyai_client/repositories/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('save/load', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('teams_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('loads an empty list when no teams are saved', () async {
      final repository = TeamRepository(rootDir: tempRoot.path);

      expect(await repository.loadTeams(), isEmpty);
    });

    test('saves and reloads multiple teams', () async {
      final repository = TeamRepository(rootDir: tempRoot.path);
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

      await repository.saveTeams(teams);
      final loaded = await repository.loadTeams();

      expect(loaded.map((t) => t.name).toSet(), {'hhoa', 'agent'});
      final agent = loaded.firstWhere((t) => t.name == 'agent');
      expect(agent.members.single.model, 'sonnet');
    });

    test('writes one json file per team', () async {
      final repository = TeamRepository(rootDir: tempRoot.path);
      const team = TeamConfig(
        id: 'demo',
        name: 'demo',
        members: [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      );

      await repository.saveTeams(const [team]);

      final file = File(p.join(tempRoot.path, 'demo.json'));
      expect(await file.exists(), isTrue);
      final raw = await file.readAsString();
      expect(raw, contains('"name": "demo"'));
    });

    test('stamps createdAt on first save', () async {
      final repository = TeamRepository(rootDir: tempRoot.path);
      const team = TeamConfig(
        id: 'demo',
        name: 'demo',
        members: [TeamMemberConfig(id: 'm', name: 'm')],
      );

      final before = DateTime.now().millisecondsSinceEpoch;
      await repository.saveTeams(const [team]);
      final loaded = await repository.loadTeams();

      expect(loaded.single.createdAt, greaterThanOrEqualTo(before));
    });

    test('removes files for teams no longer in the list', () async {
      final repository = TeamRepository(rootDir: tempRoot.path);
      await repository.saveTeams(const [
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

      await repository.saveTeams(const [
        TeamConfig(
          id: 'keep',
          name: 'keep',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      expect(await File(p.join(tempRoot.path, 'drop.json')).exists(), isFalse);
      expect(await File(p.join(tempRoot.path, 'keep.json')).exists(), isTrue);
    });
  });

  group('importFromCli', () {
    late Directory uiRoot;
    late Directory cliRoot;

    setUp(() async {
      uiRoot = await Directory.systemTemp.createTemp('teams_ui_');
      cliRoot = await Directory.systemTemp.createTemp('teams_cli_');
    });

    tearDown(() async {
      if (await uiRoot.exists()) {
        await uiRoot.delete(recursive: true);
      }
      if (await cliRoot.exists()) {
        await cliRoot.delete(recursive: true);
      }
    });

    Future<void> writeCliTeam(String folder, Map<String, Object?> json) async {
      final dir = Directory(p.join(cliRoot.path, folder));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'config.json'));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
      );
    }

    test('returns 0 when CLI dir does not exist', () async {
      final nonExistent = p.join(cliRoot.path, 'gone');
      final repository = TeamRepository(
        rootDir: uiRoot.path,
        cliTeamsDir: nonExistent,
      );
      expect(await repository.importFromCli(), 0);
    });

    test('imports teams not already present', () async {
      await writeCliTeam('huji', {
        'name': 'huji',
        'createdAt': 1778231391883,
        'leadAgentId': 'team-lead@huji',
        'members': [
          {
            'agentId': 'team-lead@huji',
            'name': 'team-lead',
            'agentType': 'team-lead',
            'joinedAt': 1778231391883,
            'cwd': '/home/hhoa/git/hhoa/huji',
            'sessionId': 'e8730ce7-49c3-4cbf-8132-fe62c261e08a',
            'isActive': true,
          },
          {
            'agentId': 'deepseek@huji',
            'name': 'deepseek',
            'joinedAt': 1778231408429,
            'cwd': '/home/hhoa/git/hhoa/huji',
            'sessionId': 'a3af3f87-1876-4c86-963c-a36a43b2fdc2',
            'isActive': true,
          },
        ],
      });

      final repository = TeamRepository(
        rootDir: uiRoot.path,
        cliTeamsDir: cliRoot.path,
      );
      expect(await repository.importFromCli(), 1);

      final teams = await repository.loadTeams();
      expect(teams.single.name, 'huji');
      expect(teams.single.createdAt, 1778231391883);
      expect(teams.single.members.length, 2);
      expect(
        teams.single.members.map((m) => m.name).toSet(),
        {'team-lead', 'deepseek'},
      );
    });

    test('skips teams that already exist by name', () async {
      await writeCliTeam('existing', {
        'name': 'existing',
        'createdAt': 1,
        'members': [
          {'name': 'team-lead', 'cwd': '/tmp', 'joinedAt': 1},
        ],
      });

      // Pre-seed UI with a team of the same name.
      final repository = TeamRepository(
        rootDir: uiRoot.path,
        cliTeamsDir: cliRoot.path,
      );
      await repository.saveTeams(const [
        TeamConfig(
          id: 'existing',
          name: 'existing',
          members: [TeamMemberConfig(id: 'x', name: 'x')],
        ),
      ]);

      expect(await repository.importFromCli(), 0);

      final teams = await repository.loadTeams();
      expect(teams.length, 1);
      expect(teams.single.name, 'existing');
    });

    test('is idempotent', () async {
      await writeCliTeam('demo', {
        'name': 'demo',
        'createdAt': 42,
        'members': [
          {'name': 'team-lead', 'cwd': '/work', 'joinedAt': 42},
        ],
      });

      final repository = TeamRepository(
        rootDir: uiRoot.path,
        cliTeamsDir: cliRoot.path,
      );
      expect(await repository.importFromCli(), 1);
      expect(await repository.importFromCli(), 0);

      final teams = await repository.loadTeams();
      expect(teams.length, 1);
    });

    test('ignores non-directory entries and missing config.json', () async {
      // Place a stray file in the CLI dir — should be silently skipped.
      await File(p.join(cliRoot.path, 'README.md'))
          .writeAsString('ignore me');
      // Empty directory with no config.json.
      await Directory(p.join(cliRoot.path, 'orphan')).create();

      final repository = TeamRepository(
        rootDir: uiRoot.path,
        cliTeamsDir: cliRoot.path,
      );
      expect(await repository.importFromCli(), 0);
    });
  });
}
