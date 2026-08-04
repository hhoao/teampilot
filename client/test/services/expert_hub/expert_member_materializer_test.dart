import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/services/expert_hub/expert_member_materializer.dart';

void main() {
  const expert = DiscoverableMember(
    key: 'test/builtin/dev',
    name: 'Developer',
    description: '',
    category: 'engineering',
    source: ExpertMemberSource.builtin,
    member: DiscoverableTeamMember(name: 'developer'),
  );

  TeamMemberConfig materialize({
    required TeamProfile team,
    TeamRosterSlotOverrides overrides = const TeamRosterSlotOverrides(),
  }) {
    return ExpertMemberMaterializer.materializeRosterSlot(
      slot: TeamRosterSlot(
        id: 'developer',
        expertKey: expert.key,
        overrides: overrides,
      ),
      expert: expert,
      team: team,
    );
  }

  group('inherit members under preset team', () {
    test('keeps empty provider after materialize', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
      ).normalizedLaunchConfig();

      final member = materialize(
        team: team,
        overrides: const TeamRosterSlotOverrides(
          activePresetId: TeamProfile.inheritPresetId,
        ),
      );

      expect(member.inheritsTeamPreset, isTrue);
      expect(member.activePresetId, TeamProfile.inheritPresetId);
      expect(member.provider, isEmpty);
      expect(member.model, isEmpty);
      expect(member.effort, isEmpty);
    });

    test('defaults empty slot activePresetId to inherit without stamping', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
      ).normalizedLaunchConfig();

      final member = materialize(team: team);

      expect(member.inheritsTeamPreset, isTrue);
      expect(member.activePresetId, TeamProfile.inheritPresetId);
      expect(member.provider, isEmpty);
    });
  });

  group('inherit members with dirty stamped overrides', () {
    test('clears provider model and effort on materialize', () {
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
      ).normalizedLaunchConfig();

      final member = materialize(
        team: team,
        overrides: const TeamRosterSlotOverrides(
          activePresetId: TeamProfile.inheritPresetId,
          provider: 'claude-official',
          model: 'sonnet',
          effort: 'high',
        ),
      );

      expect(member.inheritsTeamPreset, isTrue);
      expect(member.provider, isEmpty);
      expect(member.model, isEmpty);
      expect(member.effort, isEmpty);
    });

    test('does not stamp from residual custom maps on dirty preset team', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
        providerIdsByTool: {'claude': 'claude-official'},
        modelsByTool: {'claude': 'sonnet'},
        cliEffortLevels: {'claude': 'high'},
      );

      final member = materialize(
        team: team,
        overrides: const TeamRosterSlotOverrides(
          activePresetId: TeamProfile.inheritPresetId,
        ),
      );

      expect(member.provider, isEmpty);
      expect(member.model, isEmpty);
      expect(member.effort, isEmpty);
    });
  });

  group('custom team inherit members', () {
    test('does not stamp team custom maps onto inherit slot', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        providerIdsByTool: {'claude': 'deepseek'},
        modelsByTool: {'claude': 'deepseek-chat'},
        cliEffortLevels: {'claude': 'medium'},
      );

      final member = materialize(
        team: team,
        overrides: const TeamRosterSlotOverrides(
          activePresetId: TeamProfile.inheritPresetId,
        ),
      );

      expect(member.inheritsTeamPreset, isTrue);
      expect(member.provider, isEmpty);
      expect(member.model, isEmpty);
      expect(member.effort, isEmpty);
    });
  });

  group('non-inherit members on custom team', () {
    test('stamps empty provider from team custom maps', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        providerIdsByTool: {'claude': 'deepseek'},
        modelsByTool: {'claude': 'deepseek-chat'},
        cliEffortLevels: {'claude': 'medium'},
      );

      final member = materialize(
        team: team,
        overrides: const TeamRosterSlotOverrides(
          activePresetId: 'member-deepseek',
        ),
      );

      expect(member.hasExplicitPreset, isTrue);
      expect(member.provider, 'deepseek');
      expect(member.model, 'deepseek-chat');
      expect(member.effort, 'medium');
    });
  });
}
