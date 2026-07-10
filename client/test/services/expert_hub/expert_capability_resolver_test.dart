import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/expert_hub/expert_capability_pack.dart';
import 'package:teampilot/services/expert_hub/expert_capability_resolver.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

DiscoverableMember expert({
  String key = 'teampilot/builtin/pack-expert',
  String name = 'Pack Expert',
  List<SkillDependencyRef> skillDeps = const [],
  List<PluginDependencyRef> pluginDeps = const [],
  List<McpDependencyRef> mcpDeps = const [],
}) => DiscoverableMember(
  key: key,
  name: name,
  description: 'Full capability pack',
  category: 'Development',
  source: ExpertMemberSource.builtin,
  member: DiscoverableTeamMember(
    name: 'pack-expert',
    prompt: 'You ship with deps.',
  ),
  skillDeps: skillDeps,
  pluginDeps: pluginDeps,
  mcpDeps: mcpDeps,
);

const skillDep = SkillDependencyRef(
  repoOwner: 'anthropics',
  repoName: 'skills',
  repoBranch: 'main',
  directory: 'skills/deep-research',
  name: 'deep-research',
);

const pluginDep = PluginDependencyRef(
  marketplaceOwner: 'o',
  marketplaceName: 'n',
  marketplaceBranch: 'main',
  entryName: 'plug',
  name: 'Plug',
);

const mcpDep = McpDependencyRef(
  id: 'context7',
  name: 'Context7',
  server: {'command': 'npx'},
);

void main() {
  test('resolve with no deps → empty ConfigBundle, non-empty persona', () async {
    final resolver = ExpertCapabilityResolver(
      installSkill: (_) async => fail('skill installer should not be called'),
      installPlugin: (_) async => fail('plugin installer should not be called'),
      installMcp: (_) async => fail('mcp installer should not be called'),
    );

    final pack = await resolver.resolve(expert());

    expect(pack.bundle, const ConfigBundle());
    expect(pack.failedDeps, isEmpty);
    expect(pack.member.name, 'Pack Expert');
    expect(pack.member.prompt, contains('ship'));
    expect(pack.member.id, isNotEmpty);
  });

  test('skill dep present → installSkill called; id in bundle.skillIds', () async {
    SkillDependencyRef? seen;
    final resolver = ExpertCapabilityResolver(
      installSkill: (dep) async {
        seen = dep;
        return 'anthropics/skills:deep-research';
      },
      installPlugin: (_) async => null,
      installMcp: (_) async => null,
    );

    final pack = await resolver.resolve(
      expert(skillDeps: const [skillDep]),
    );

    expect(seen, skillDep);
    expect(pack.bundle.skillIds, ['anthropics/skills:deep-research']);
    expect(pack.failedDeps, isEmpty);
    expect(pack.member.prompt, contains('ship'));
  });

  test('installSkill returns null → soft-fail; persona present; DependencyFailure listed', () async {
    final resolver = ExpertCapabilityResolver(
      installSkill: (_) async => null,
      installPlugin: (_) async => null,
      installMcp: (_) async => null,
    );

    final pack = await resolver.resolve(
      expert(skillDeps: const [skillDep]),
    );

    expect(pack.bundle.skillIds, isEmpty);
    expect(pack.member.name, 'Pack Expert');
    expect(pack.failedDeps, hasLength(1));
    expect(pack.failedDeps.single.kind, DependencyKind.skill);
    expect(pack.failedDeps.single.name, 'deep-research');
  });

  test('preflight / resolveKey unknown key → null (hard fail)', () async {
    final resolver = ExpertCapabilityResolver(
      installSkill: (_) async => 'should-not-run',
      installPlugin: (_) async => 'should-not-run',
      installMcp: (_) async => 'should-not-run',
    );

    expect(await resolver.preflight('unknown/missing/expert'), isNull);
    expect(await resolver.resolveKey('unknown/missing/expert'), isNull);
  });

  test('pluginDeps and mcpDeps install success → ids in bundle', () async {
    final seenPlugins = <PluginDependencyRef>[];
    final seenMcps = <McpDependencyRef>[];
    final resolver = ExpertCapabilityResolver(
      installSkill: (_) async => null,
      installPlugin: (dep) async {
        seenPlugins.add(dep);
        return 'o/n/plug';
      },
      installMcp: (dep) async {
        seenMcps.add(dep);
        return 'context7';
      },
    );

    final pack = await resolver.resolve(
      expert(pluginDeps: const [pluginDep], mcpDeps: const [mcpDep]),
    );

    expect(seenPlugins, [pluginDep]);
    expect(seenMcps, [mcpDep]);
    expect(pack.bundle.pluginIds, ['o/n/plug']);
    expect(pack.bundle.mcpServerIds, ['context7']);
    expect(pack.failedDeps, isEmpty);
    expect(pack, isA<ExpertCapabilityPack>());
  });

  test('resolve with team but no overrides → materialize path (slot id + inheritance)', () async {
    final resolver = ExpertCapabilityResolver(
      installSkill: (_) async => null,
      installPlugin: (_) async => null,
      installMcp: (_) async => null,
    );
    const team = TeamProfile(
      id: 'team-1',
      name: 'Test Team',
      cli: CliTool.claude,
      providerIdsByTool: {'claude': 'anthropic'},
      modelsByTool: {'claude': 'claude-sonnet-4'},
    );

    final pack = await resolver.resolve(
      expert(),
      team: team,
      slotId: 'slot-alpha',
    );

    expect(pack.member.id, 'slot-alpha');
    expect(pack.member.provider, 'anthropic');
    expect(pack.member.model, 'claude-sonnet-4');
    expect(pack.member.activePresetId, TeamProfile.inheritPresetId);
  });

  test('resolveKey for builtin default returns a pack', () async {
    final resolver = ExpertCapabilityResolver(
      installSkill: (_) async => null,
      installPlugin: (_) async => null,
      installMcp: (_) async => null,
    );

    final pack = await resolver.resolveKey('teampilot/builtin/default');
    expect(pack, isNotNull);
    expect(pack!.member.id, isNotEmpty);
    expect(pack.bundle, const ConfigBundle());
  });

  test(
    'onDepProgress fires after each install in skill→plugin→mcp order',
    () async {
      final progressNames = <String>[];
      var progressCount = 0;
      final installProgressAtInstall = <String, int>{};

      final resolver = ExpertCapabilityResolver(
        installSkill: (dep) async {
          installProgressAtInstall[dep.name] = progressCount;
          return 'anthropics/skills:deep-research';
        },
        installPlugin: (dep) async {
          installProgressAtInstall[dep.name] = progressCount;
          return 'o/n/plug';
        },
        installMcp: (dep) async {
          installProgressAtInstall[dep.name] = progressCount;
          return 'context7';
        },
      );

      await resolver.resolve(
        expert(
          skillDeps: const [skillDep],
          pluginDeps: const [pluginDep],
          mcpDeps: const [mcpDep],
        ),
        onDepProgress: (name) {
          progressCount++;
          progressNames.add(name);
        },
      );

      expect(progressNames, ['deep-research', 'Plug', 'Context7']);
      expect(progressCount, 3);
      expect(installProgressAtInstall['deep-research'], 0);
      expect(installProgressAtInstall['Plug'], 1);
      expect(installProgressAtInstall['Context7'], 2);
    },
  );
}
