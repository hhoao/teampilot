import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Max recent teams shown in the Landing team chip menu.
const kTeamLandingChipRecentLimit = 5;

/// Actions other than a concrete team id in the Landing team chip menu.
enum TeamLandingChipAction { generateLaunch, browseAll }

/// Builds Landing team-chip menu: recent (≤5) → divider → generate-and-launch
/// → browse all.
List<TpActionMenuSpec> buildTeamLandingChipMenuSpecs({
  required String browseAllLabel,
  String? generateLaunchLabel,
  required String? selectedTeamId,
  bool generateLaunchSelected = false,
  required List<({String id, String name})> recentTeams,
}) {
  final selected = selectedTeamId?.trim() ?? '';
  final includeGenerate = generateLaunchLabel != null;

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
  if (includeGenerate) {
    specs.add(
      TpActionMenuSpec.item(
        value: TeamLandingChipAction.generateLaunch,
        icon: Icons.auto_awesome_outlined,
        label: generateLaunchLabel,
        selected: generateLaunchSelected,
      ),
    );
  }
  specs.add(
    TpActionMenuSpec.item(
      value: TeamLandingChipAction.browseAll,
      icon: Icons.travel_explore_outlined,
      label: browseAllLabel,
    ),
  );
  return specs;
}
