import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/expert_hub/expert_landing_chip_menu.dart';
import 'package:teampilot/widgets/menu/sidebar_action_menu.dart';

void main() {
  group('buildExpertLandingChipMenuSpecs', () {
    test('orders clear, recent, divider, browse all', () {
      final specs = buildExpertLandingChipMenuSpecs(
        noneSelectedLabel: 'No expert',
        browseAllLabel: 'Browse all',
        selectedExpertKey: null,
        recentExperts: const [
          (key: 'a/dev', name: 'Developer'),
          (key: 'a/rev', name: 'Reviewer'),
        ],
      );

      expect(specs.map((s) => s.isDivider ? '|' : s.label).toList(), [
        'No expert',
        'Developer',
        'Reviewer',
        '|',
        'Browse all',
      ]);
      expect(specs[0].value, ExpertLandingChipAction.clear);
      expect(specs[0].selected, isTrue);
      expect(specs[1].value, 'a/dev');
      expect(specs[2].value, 'a/rev');
      expect(specs.last.value, ExpertLandingChipAction.browseAll);
    });

    test('omits recent section when empty', () {
      final specs = buildExpertLandingChipMenuSpecs(
        noneSelectedLabel: 'No expert',
        browseAllLabel: 'Browse all',
        selectedExpertKey: null,
        recentExperts: const [],
      );

      expect(specs.map((s) => s.isDivider ? '|' : s.label).toList(), [
        'No expert',
        '|',
        'Browse all',
      ]);
    });

    test('caps recent at kExpertLandingChipRecentLimit', () {
      final many = [
        for (var i = 0; i < 8; i++) (key: 'k$i', name: 'E$i'),
      ];
      final specs = buildExpertLandingChipMenuSpecs(
        noneSelectedLabel: 'No expert',
        browseAllLabel: 'Browse all',
        selectedExpertKey: 'k1',
        recentExperts: many,
      );

      final recentLabels = specs
          .where((s) => !s.isDivider && s.value is String)
          .map((s) => s.label)
          .toList();
      expect(recentLabels, hasLength(kExpertLandingChipRecentLimit));
      expect(recentLabels.first, 'E0');
      expect(recentLabels.last, 'E4');
      expect(
        specs.where((s) => s.value == 'k1').single.selected,
        isTrue,
      );
      expect(
        specs.where((s) => s.value == ExpertLandingChipAction.clear).single.selected,
        isFalse,
      );
    });
  });
}
