import 'dart:convert';
import 'dart:io';

import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('save/load (UI dir only)', () {
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

    TeamRepository repo() => TeamRepository(
          rootDir: uiRoot.path,
          cliTeamsDir: cliRoot.path,
        );

    test('loads an empty list when nothing is saved', () async {
      expect(await repo().loadTeams(), isEmpty);
    });

    test('saves and reloads multiple teams', () async {
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
  });

  group('loadTeams merges UI + CLI dirs', () {
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

    TeamRepository repo() => TeamRepository(
          rootDir: uiRoot.path,
          cliTeamsDir: cliRoot.path,
        );

    Future<void> writeCliTeam(String folder, Map<String, Object?> json) async {
      final dir = Directory(p.join(cliRoot.path, folder));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'config.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
      );
    }

    test('returns CLI-only teams when UI dir is empty', () async {
      await writeCliTeam('huji', {
        'name': 'huji',
        'createdAt': 1778231391883,
        'members': [
          {'name': 'team-lead', 'joinedAt': 1778231391883},
          {'name': 'deepseek', 'joinedAt': 1778231408429},
        ],
      });

      final teams = await repo().loadTeams();
      expect(teams.single.name, 'huji');
      expect(teams.single.createdAt, 1778231391883);
      expect(
        teams.single.members.map((m) => m.name).toList(),
        ['team-lead', 'deepseek'],
      );
    });

    test('returns UI-only teams when CLI dir is empty', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 'ui-only',
          name: 'ui-only',
          members: [
            TeamMemberConfig(id: 'a', name: 'a', model: 'sonnet'),
          ],
        ),
      ]);
      // saveTeams writes to CLI too — wipe CLI to simulate UI-only state.
      await Directory(cliRoot.path).delete(recursive: true);
      await Directory(cliRoot.path).create();

      final teams = await repo().loadTeams();
      expect(teams.single.name, 'ui-only');
      expect(teams.single.members.single.model, 'sonnet');
    });

    test('on collision, CLI fields override but UI extras survive', () async {
      // Pre-seed UI with full schema including model/provider.
      await repo().saveTeams(const [
        TeamConfig(
          id: 'shared',
          name: 'shared',
          createdAt: 100,
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

      // CLI changes createdAt, loop, and member's joinedAt.
      await writeCliTeam('shared', {
        'name': 'shared',
        'createdAt': 999,
        'loop': true,
        'leadAgentId': 'alice@shared',
        'members': [
          {
            'agentId': 'alice@shared',
            'name': 'alice',
            'joinedAt': 999,
            'cwd': '/work',
            'isActive': true,
          },
        ],
      });

      final teams = await repo().loadTeams();
      final shared = teams.single;

      // CLI fields win:
      expect(shared.createdAt, 999);
      expect(shared.loop, true);
      expect(shared.members.single.joinedAt, 999);
      // UI extras preserved:
      expect(shared.members.single.model, 'sonnet');
      expect(shared.members.single.provider, 'anthropic');
    });

    test('member union: CLI-only and UI-only members both kept', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 't',
          name: 't',
          createdAt: 1,
          members: [
            TeamMemberConfig(id: 'ui-only', name: 'ui-only', model: 'haiku'),
          ],
        ),
      ]);

      await writeCliTeam('t', {
        'name': 't',
        'createdAt': 1,
        'members': [
          {'name': 'cli-only', 'joinedAt': 5},
        ],
      });

      final teams = await repo().loadTeams();
      final names = teams.single.members.map((m) => m.name).toList();
      // CLI members first, UI-only appended.
      expect(names, ['cli-only', 'ui-only']);
    });

    test('skips CLI dirs without config.json and non-directory entries',
        () async {
      await File(p.join(cliRoot.path, 'README.md')).writeAsString('x');
      await Directory(p.join(cliRoot.path, 'orphan')).create();

      expect(await repo().loadTeams(), isEmpty);
    });
  });

  group('saveTeams syncs CLI subset back', () {
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

    TeamRepository repo() => TeamRepository(
          rootDir: uiRoot.path,
          cliTeamsDir: cliRoot.path,
        );

    test('creates CLI <name>/config.json with CLI subset only', () async {
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

      final file = File(p.join(cliRoot.path, 't', 'config.json'));
      expect(await file.exists(), isTrue);
      final json = jsonDecode(await file.readAsString()) as Map;
      expect(json['name'], 't');
      expect(json['createdAt'], 42);
      expect(json['loop'], true);
      final members = json['members'] as List;
      // CLI subset only — no model/provider in CLI config.
      expect((members.single as Map)['name'], 'alice');
      expect((members.single as Map)['joinedAt'], 42);
      expect((members.single as Map).containsKey('model'), isFalse);
      expect((members.single as Map).containsKey('provider'), isFalse);
    });

    test('preserves CLI-side extras (agentId, cwd, isActive, ...) on rewrite',
        () async {
      // Existing CLI config with extras the UI doesn't model.
      final dir = Directory(p.join(cliRoot.path, 't'));
      await dir.create(recursive: true);
      final configFile = File(p.join(dir.path, 'config.json'));
      await configFile.writeAsString(jsonEncode({
        'name': 't',
        'createdAt': 1,
        'leadAgentId': 'alice@t',
        'members': [
          {
            'agentId': 'alice@t',
            'name': 'alice',
            'agentType': 'team-lead',
            'joinedAt': 1,
            'cwd': '/work',
            'sessionId': 's-1',
            'isActive': true,
          },
        ],
      }));

      // UI saves: should update CLI-known fields but preserve unknown ones.
      await repo().saveTeams(const [
        TeamConfig(
          id: 't',
          name: 't',
          createdAt: 2,
          members: [
            TeamMemberConfig(
              id: 'alice',
              name: 'alice',
              joinedAt: 2,
              model: 'opus',
            ),
          ],
        ),
      ]);

      final json = jsonDecode(await configFile.readAsString()) as Map;
      expect(json['leadAgentId'], 'alice@t');
      expect(json['createdAt'], 2);
      final member = (json['members'] as List).single as Map;
      expect(member['agentId'], 'alice@t');
      expect(member['agentType'], 'team-lead');
      expect(member['cwd'], '/work');
      expect(member['sessionId'], 's-1');
      expect(member['isActive'], true);
      expect(member['joinedAt'], 2);
      // UI-only fields don't leak into CLI config.
      expect(member.containsKey('model'), isFalse);
    });

    test('does NOT prune CLI dirs absent from input (preserves temp teams)',
        () async {
      // Simulate a temp session team the CLI created during this run, which
      // the UI never tracks in state.teams.
      final tempDir = Directory(p.join(cliRoot.path, 'demo-1'));
      await tempDir.create(recursive: true);
      await File(p.join(tempDir.path, 'config.json')).writeAsString(jsonEncode({
        'name': 'demo-1',
        'createdAt': 1,
        'members': [],
      }));

      await repo().saveTeams(const [
        TeamConfig(
          id: 'real',
          name: 'real',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      // Real team got synced.
      expect(await Directory(p.join(cliRoot.path, 'real')).exists(), isTrue);
      // Temp team survived an unrelated saveTeams call.
      expect(await tempDir.exists(), isTrue);
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

    TeamRepository repo() => TeamRepository(
          rootDir: uiRoot.path,
          cliTeamsDir: cliRoot.path,
        );

    test('removes the UI file and the CLI directory', () async {
      await repo().saveTeams(const [
        TeamConfig(
          id: 'gone',
          name: 'gone',
          members: [TeamMemberConfig(id: 'm', name: 'm')],
        ),
      ]);

      await repo().deleteTeam('gone');

      expect(await File(p.join(uiRoot.path, 'gone.json')).exists(), isFalse);
      expect(await Directory(p.join(cliRoot.path, 'gone')).exists(), isFalse);
    });

    test('refuses to delete a CLI subdir without config.json', () async {
      // A subdir that doesn't look like a team dir must survive.
      final imposter = Directory(p.join(cliRoot.path, 'gone'));
      await imposter.create(recursive: true);
      await File(p.join(imposter.path, 'note.txt')).writeAsString('hi');

      await repo().deleteTeam('gone');

      expect(await File(p.join(imposter.path, 'note.txt')).exists(), isTrue);
    });

    test('is idempotent on missing teams', () async {
      // Nothing to delete — should not throw.
      await repo().deleteTeam('never-existed');
    });
  });
}
