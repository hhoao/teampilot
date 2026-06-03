import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  const json = <String, Object?>{
    'key': 'flashskyai/team-hub/research-squad',
    'name': 'Research Squad',
    'description': 'A team for deep research.',
    'category': 'Research',
    'author': 'flashskyai',
    'updatedAt': 1700000000000,
    'cli': 'claude',
    'teamMode': 'mixed',
    'extraArgs': '--foo',
    'members': [
      {
        'name': 'team-lead',
        'provider': 'anthropic',
        'model': 'claude-opus-4-8',
        'agent': 'lead',
        'agentType': 'lead',
        'prompt': 'Coordinate.',
        'extraArgs': '',
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
        'server': {'command': 'npx', 'args': ['-y', 'context7']},
      },
    ],
  };

  test('round-trips through fromJson/toJson', () {
    final team = DiscoverableTeam.fromJson(json);
    expect(team.key, 'flashskyai/team-hub/research-squad');
    expect(team.cli, TeamCli.claude);
    expect(team.teamMode, TeamMode.mixed);
    expect(team.members.single.name, 'team-lead');
    expect(team.skillDeps.single.directory, 'skills/deep-research');
    expect(team.pluginDeps.single.entryName, 'linter');
    expect(team.mcpDeps.single.server['command'], 'npx');
    expect(DiscoverableTeam.fromJson(team.toJson()), team);
  });

  test('toMemberConfig produces a slugged, joined member', () {
    final team = DiscoverableTeam.fromJson(json);
    final member = team.members.single.toMemberConfig(joinedAt: 42);
    expect(member.id, 'team-lead');
    expect(member.name, 'team-lead');
    expect(member.model, 'claude-opus-4-8');
    expect(member.joinedAt, 42);
  });
}
