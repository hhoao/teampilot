import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  const json = <String, Object?>{
    'key': 'hhoao/teampilot/team-hub/research-squad',
    'name': 'Research Squad',
    'description': 'A team for deep research.',
    'category': 'Research',
    'author': 'flashskyai',
    'updatedAt': 1700000000000,
    'cli': 'claude',
    'teamMode': 'mixed',
    'extraArgs': '--foo',
    'roster': [
      {
        'id': 'team-lead',
        'expertKey': 'teampilot/builtin/team-lead',
        'overrides': {
          'provider': 'anthropic',
          'model': 'claude-opus-4-8',
        },
      },
    ],
    'skillDeps': [
      {
        'repoOwner': 'anthropics',
        'repoName': 'skills',
        'repoBranch': 'main',
        'directory': 'skills/deep-research',
        'name': 'deep-research',
      },
    ],
    'pluginDeps': [
      {
        'marketplaceOwner': 'acme',
        'marketplaceName': 'plugins',
        'marketplaceBranch': 'main',
        'entryName': 'linter',
        'name': 'Linter',
      },
    ],
    'mcpDeps': [
      {
        'id': 'context7',
        'name': 'Context7',
        'description': 'docs',
        'server': {
          'command': 'npx',
          'args': ['-y', 'context7'],
        },
      },
    ],
  };

  test('round-trips through fromJson/toJson', () {
    final team = DiscoverableTeam.fromJson(json);
    expect(team.key, 'hhoao/teampilot/team-hub/research-squad');
    expect(team.cli, CliTool.claude);
    expect(team.teamMode, TeamMode.mixed);
    expect(team.roster.single.id, 'team-lead');
    expect(team.roster.single.expertKey, 'teampilot/builtin/team-lead');
    expect(team.skillDeps.single.directory, 'skills/deep-research');
    expect(team.pluginDeps.single.entryName, 'linter');
    expect(team.mcpDeps.single.server['command'], 'npx');
    expect(DiscoverableTeam.fromJson(team.toJson()), team);
  });

  test('undeclared teamMode/cli default to native/claude and are omitted on toJson', () {
    final team = DiscoverableTeam.fromJson(const {
      'key': 'o/r/s',
      'name': 'S',
      'description': '',
      'category': 'AI',
      'updatedAt': 1,
    });
    expect(team.teamMode, TeamMode.native);
    expect(team.cli, CliTool.claude);
    expect(team.teamModeDeclared, isFalse);
    expect(team.cliDeclared, isFalse);
    final json = team.toJson();
    expect(json.containsKey('teamMode'), isFalse);
    expect(json.containsKey('cli'), isFalse);
  });

  test('declared teamMode/cli are preserved', () {
    final team = DiscoverableTeam.fromJson(const {
      'key': 'o/r/s',
      'name': 'S',
      'description': '',
      'category': 'AI',
      'updatedAt': 1,
      'cli': 'codex',
      'teamMode': 'mixed',
    });
    expect(team.teamMode, TeamMode.mixed);
    expect(team.cli, CliTool.codex);
    expect(team.teamModeDeclared, isTrue);
    expect(team.cliDeclared, isTrue);
    final json = team.toJson();
    expect(json['teamMode'], 'mixed');
    expect(json['cli'], 'codex');
  });
}
