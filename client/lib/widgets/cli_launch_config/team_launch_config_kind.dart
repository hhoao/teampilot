import '../../models/team_config.dart';

/// Team default launch configuration mode (preset-backed or custom fields).
enum TeamLaunchConfigKind {
  preset,
  custom,
}

TeamLaunchConfigKind teamLaunchConfigKind(TeamProfile team) {
  return team.activePresetId != null
      ? TeamLaunchConfigKind.preset
      : TeamLaunchConfigKind.custom;
}

String teamLaunchPresetToken(TeamProfile team) => team.activePresetId ?? '';
