import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/expert_hub/expert_clone_service.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

DiscoverableTeam team() => const DiscoverableTeam(
  key: 'o/r/squad',
  name: 'Squad',
  description: 'd',
  category: 'AI',
  updatedAt: 1,
  cli: CliTool.claude,
  teamMode: TeamMode.mixed,
  roster: [
    TeamRosterSlot(
      id: 'team-lead',
      expertKey: 'teampilot/builtin/team-lead',
    ),
  ],
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
  mcpDeps: [McpDependencyRef(id: 'context7', name: 'Context7', server: {})],
);

void main() {
  test('clone installs all deps and creates a team', () async {
    String? createdName;
    List<String>? createdSkillIds;
    final service = TeamCloneService(
      installSkill: (d) async => 'anthropics/skills:deep-research',
      installPlugin: (d) async => 'acme/plugins/linter',
      installMcp: (d) async => 'context7',
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(key: expertKey, cloned: false),
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async {
            createdName = name;
            createdSkillIds = skillIds;
            expect(pluginIds, ['acme/plugins/linter']);
            expect(mcpServerIds, ['context7']);
            expect(roster.single.id, 'team-lead');
            return 'squad';
          },
    );

    final result = await service.clone(team());
    expect(result.teamId, 'squad');
    expect(result.failedDeps, isEmpty);
    expect(result.installed.totalCount, 3);
    expect(result.installed.skillIds, ['anthropics/skills:deep-research']);
    expect(createdName, 'Squad');
    expect(createdSkillIds, ['anthropics/skills:deep-research']);
  });

  test('a failed dependency is non-blocking; team still created', () async {
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => 'acme/plugins/linter',
      installMcp: (d) async => 'context7',
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(key: expertKey, cloned: false),
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
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
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(key: expertKey, cloned: false),
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async => null,
    );
    expect(() => service.clone(team()), throwsA(isA<CloneException>()));
  });

  test('repoints roster slots to cloned local expert keys', () async {
    TeamRosterSlot? createdSlot;
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => null,
      installMcp: (d) async => null,
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          expertKey == 'catalog/pm'
              ? ExpertCloneOutcome(key: 'local/cloned-pm', cloned: true)
              : ExpertCloneOutcome(key: expertKey, cloned: false),
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async {
            createdSlot = roster.single;
            return 'squad';
          },
    );

    final result = await service.clone(
      const DiscoverableTeam(
        key: 'o/r/squad',
        name: 'Squad',
        description: 'd',
        category: 'AI',
        updatedAt: 1,
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        roster: [TeamRosterSlot(id: 'pm', expertKey: 'catalog/pm')],
      ),
    );

    expect(createdSlot!.expertKey, 'local/cloned-pm');
    expect(result.installed.expertCount, 1);
    expect(result.installed.expertKeys, ['local/cloned-pm']);
    expect(result.failedDeps, isEmpty);
  });

  test('unresolvable expert is a non-blocking failure, key kept', () async {
    TeamRosterSlot? createdSlot;
    final service = TeamCloneService(
      installSkill: (d) async => null,
      installPlugin: (d) async => null,
      installMcp: (d) async => null,
      expertClonerFactory: () => ({required expertKey, originTeamKey}) async =>
          null,
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async {
            createdSlot = roster.single;
            return 'squad';
          },
    );

    final result = await service.clone(
      const DiscoverableTeam(
        key: 'o/r/squad',
        name: 'Squad',
        description: 'd',
        category: 'AI',
        updatedAt: 1,
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        roster: [TeamRosterSlot(id: 'pm', expertKey: 'catalog/pm')],
      ),
    );

    expect(createdSlot!.expertKey, 'catalog/pm',
        reason: 'original key kept on failure');
    expect(result.failedDeps, hasLength(1));
    expect(result.failedDeps.single.kind, DependencyKind.expert);
    expect(result.failedDeps.single.name, 'catalog/pm');
    expect(result.installed.expertCount, 0);
  });
}
