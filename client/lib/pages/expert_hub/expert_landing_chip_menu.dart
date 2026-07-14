import 'package:flutter/material.dart';

import '../../widgets/menu/sidebar_action_menu.dart';

/// Max recent experts shown in the Landing expert chip menu.
const kExpertLandingChipRecentLimit = 5;

/// Actions other than a concrete expert key in the Landing expert chip menu.
enum ExpertLandingChipAction { clear, browseAll }

/// Builds Landing expert-chip menu: clear → recent (≤5) → divider → browse all.
List<SidebarActionMenuSpec> buildExpertLandingChipMenuSpecs({
  required String noneSelectedLabel,
  required String browseAllLabel,
  required String? selectedExpertKey,
  required List<({String key, String name})> recentExperts,
}) {
  final selected = selectedExpertKey?.trim() ?? '';
  final noneSelected = selected.isEmpty;

  final specs = <SidebarActionMenuSpec>[
    SidebarActionMenuSpec.item(
      value: ExpertLandingChipAction.clear,
      icon: Icons.person_off_outlined,
      label: noneSelectedLabel,
      selected: noneSelected,
    ),
  ];

  final recent = recentExperts
      .where((e) => e.key.trim().isNotEmpty && e.name.trim().isNotEmpty)
      .take(kExpertLandingChipRecentLimit)
      .toList();

  for (final expert in recent) {
    specs.add(
      SidebarActionMenuSpec.item(
        value: expert.key,
        icon: Icons.psychology_outlined,
        label: expert.name,
        selected: expert.key == selected,
      ),
    );
  }

  specs.add(const SidebarActionMenuSpec.divider());
  specs.add(
    SidebarActionMenuSpec.item(
      value: ExpertLandingChipAction.browseAll,
      icon: Icons.travel_explore_outlined,
      label: browseAllLabel,
    ),
  );
  return specs;
}
