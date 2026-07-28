import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/team_hub/team_landing_chip_menu.dart';

void main() {
  group('buildTeamLandingChipMenuSpecs', () {
    test('orders recent, divider, browse all without clear', () {
      final specs = buildTeamLandingChipMenuSpecs(
        browseAllLabel: 'Browse all teams',
        selectedTeamId: 't1',
        recentTeams: const [
          (id: 't1', name: 'Alpha'),
          (id: 't2', name: 'Beta'),
        ],
      );
      expect(specs.map((s) => s.isDivider ? '|' : s.label).toList(), [
        'Alpha',
        'Beta',
        '|',
        'Browse all teams',
      ]);
      expect(specs.last.value, TeamLandingChipAction.browseAll);
      expect(specs.where((s) => s.value == 't1').single.selected, isTrue);
    });

    test('empty recent still exposes browse all', () {
      final specs = buildTeamLandingChipMenuSpecs(
        browseAllLabel: 'Browse all teams',
        selectedTeamId: null,
        recentTeams: const [],
      );
      expect(specs.map((s) => s.isDivider ? '|' : s.label).toList(), [
        '|',
        'Browse all teams',
      ]);
    });

    test('caps recent at kTeamLandingChipRecentLimit', () {
      final many = [for (var i = 0; i < 8; i++) (id: 't$i', name: 'T$i')];
      final specs = buildTeamLandingChipMenuSpecs(
        browseAllLabel: 'Browse all',
        selectedTeamId: 't1',
        recentTeams: many,
      );
      final recent = specs
          .where((s) => !s.isDivider && s.value is String)
          .map((s) => s.label)
          .toList();
      expect(recent, hasLength(kTeamLandingChipRecentLimit));
    });
  });
}
