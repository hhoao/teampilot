import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Max recent teams shown in the Landing team chip menu.
const kTeamLandingChipRecentLimit = 5;

/// Actions other than a concrete team id in the Landing team chip menu.
enum TeamLandingChipAction { browseAll }

/// Builds Landing team-chip menu: recent (≤5) → divider → browse all.
List<TpActionMenuSpec> buildTeamLandingChipMenuSpecs({
  required String browseAllLabel,
  required String? selectedTeamId,
  required List<({String id, String name})> recentTeams,
}) {
  final selected = selectedTeamId?.trim() ?? '';

  final specs = <TpActionMenuSpec>[];

  final recent = recentTeams
      .where((t) => t.id.trim().isNotEmpty && t.name.trim().isNotEmpty)
      .take(kTeamLandingChipRecentLimit)
      .toList();

  for (final team in recent) {
    specs.add(
      TpActionMenuSpec.item(
        value: team.id,
        icon: Icons.groups_outlined,
        label: team.name,
        selected: team.id == selected,
      ),
    );
  }

  specs.add(const TpActionMenuSpec.divider());
  specs.add(
    TpActionMenuSpec.item(
      value: TeamLandingChipAction.browseAll,
      icon: Icons.travel_explore_outlined,
      label: browseAllLabel,
    ),
  );
  return specs;
}
