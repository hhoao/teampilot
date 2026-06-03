import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

DiscoverableTeam team() => const DiscoverableTeam(
      key: 'o/r/squad',
      name: 'Squad',
      description: 'd',
      category: 'AI',
      updatedAt: 1,
      cli: TeamCli.claude,
      teamMode: TeamMode.mixed,
      members: [DiscoverableTeamMember(name: 'team-lead')],
      skillDeps: [
        SkillDependencyRef(
          repoOwner: 'anthropics',
          repoName: 'skills',
          repoBranch: 'main',
          directory: 'skills/deep-research',
          name: 'deep-research',
        ),
      ],
      pluginDeps: [
        PluginDependencyRef(
          marketplaceOwner: 'acme',
          marketplaceName: 'plugins',
          marketplaceBranch: 'main',
          entryName: 'linter',
          name: 'Linter',
        ),
      ],
      mcpDeps: [
        McpDependencyRef(id: 'context7', name: 'Context7', server: {}),
      ],
    );

void main() {
  test('clone installs all deps and creates a team', () async {
    String? createdName;
    List<String>? createdSkillIds;
    final service = TeamCloneService(
      installSkill: (d) async => 'anthropics/skills:deep-research',
      installPlugin: (d) async => 'acme/plugins/linter',
      installMcp: (d) async => 'context7',
      createTeam: ({
        required name,
        required cli,
        required teamMode,
        required members,
        required skillIds,
        required pluginIds,
        required mcpServerIds,
        required description,
        required extraArgs,
      }) async {
        createdName = name;
        createdSkillIds = skillIds;
        expect(pluginIds, ['acme/plugins/linter']);
        expect(mcpServerIds, ['context7']);
        expect(members.single.name, 'team-lead');
        return 'squad';
      },
    );

    final result = await service.clone(team());
    expect(result.teamId, 'squad');
    expect(result.failedDeps, isEmpty);
    expect(result.installedDeps, hasLength(3));
    expect(createdName, 'Squad');
    expect(createdSkillIds, ['anthropics/skills:deep-research']);
  });

  test('a failed dependency is non-blocking; team still created', () async {
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => 'acme/plugins/linter',
      installMcp: (d) async => 'context7',
      createTeam: ({
        required name,
        required cli,
        required teamMode,
        required members,
        required skillIds,
        required pluginIds,
        required mcpServerIds,
        required description,
        required extraArgs,
      }) async {
        expect(skillIds, isEmpty, reason: 'failed skill is dropped');
        return 'squad';
      },
    );

    final result = await service.clone(team());
    expect(result.teamId, 'squad');
    expect(result.failedDeps, hasLength(1));
    expect(result.failedDeps.single.name, 'deep-research');
  });

  test('throws CloneException when team creation returns null', () async {
    final service = TeamCloneService(
      installSkill: (d) async => 's',
      installPlugin: (d) async => 'p',
      installMcp: (d) async => 'm',
      createTeam: ({
        required name,
        required cli,
        required teamMode,
        required members,
        required skillIds,
        required pluginIds,
        required mcpServerIds,
        required description,
        required extraArgs,
      }) async =>
          null,
    );
    expect(() => service.clone(team()), throwsA(isA<CloneException>()));
  });
}
