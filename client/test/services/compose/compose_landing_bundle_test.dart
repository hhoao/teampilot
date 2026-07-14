import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/compose/compose_landing_bundle.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/team_hub/builtin_team_templates.dart';

DiscoverableMember _member({
  required String key,
  List<SkillDependencyRef> skillDeps = const [],
  List<PluginDependencyRef> pluginDeps = const [],
}) {
  return DiscoverableMember(
    key: key,
    name: 'Test',
    description: '',
    category: 'Test',
    source: ExpertMemberSource.local,
    member: const DiscoverableTeamMember(name: 'test'),
    skillDeps: skillDeps,
    pluginDeps: pluginDeps,
  );
}

void main() {
  final skillA = superpowersSkillDep('using-superpowers', 'Using Superpowers');
  final skillB = superpowersSkillDep('brainstorming', 'Brainstorming');

  group('slashBundleForLanding', () {
    test('Simple + explicit expert merges expectedLocalIds with workspace', () {
      final expert = _member(
        key: 'local/architect',
        skillDeps: [skillB],
        pluginDeps: const [
          PluginDependencyRef(
            marketplaceOwner: 'o',
            marketplaceName: 'm',
            marketplaceBranch: 'main',
            entryName: 'cmd',
            name: 'Cmd',
          ),
        ],
      );
      final hub = ExpertHubState(allMembers: [expert]);
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: true,
          expertKey: 'local/architect',
        ),
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
        hubState: hub,
      );
      expect(bundle.skillIds, [skillB.expectedLocalId, 'ws-skill']);
      expect(bundle.pluginIds, ['o/m/cmd']);
    });

    test('Simple + empty expertKey uses default expert deps', () {
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(isPersonal: true),
        workspace: const ConfigBundle(),
        hubState: null,
      );
      final defaultMember = builtinExpertMembers()
          .firstWhere((m) => m.key == kBuiltinDefaultExpertKey);
      expect(
        bundle.skillIds,
        defaultMember.skillDeps.map((d) => d.expectedLocalId).toList(),
      );
    });

    test('Team mode uses team + workspace and ignores expertKey', () {
      const team = TeamProfile(
        id: 't1',
        name: 'Team',
        skillIds: ['team-skill'],
        pluginIds: ['team-plugin'],
      );
      final expert = _member(key: 'local/x', skillDeps: [skillA]);
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: false,
          teamId: 't1',
          expertKey: 'local/x',
        ),
        team: team,
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
        hubState: ExpertHubState(allMembers: [expert]),
      );
      expect(bundle.skillIds, ['team-skill', 'ws-skill']);
      expect(bundle.pluginIds, ['team-plugin']);
    });

    test('unknown expert key yields workspace-only', () {
      final bundle = slashBundleForLanding(
        draft: const LandingLaunchContext(
          isPersonal: true,
          expertKey: 'missing/expert',
        ),
        workspace: const ConfigBundle(skillIds: ['ws-skill']),
        hubState: const ExpertHubState(),
      );
      expect(bundle.skillIds, ['ws-skill']);
      expect(bundle.pluginIds, isEmpty);
    });
  });
}
