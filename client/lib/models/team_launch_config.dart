import 'team_config.dart';

/// Team-level launch configuration shape: preset reference or per-CLI custom maps.
enum TeamLaunchShape { preset, custom }

TeamLaunchShape teamLaunchShape(TeamProfile team) {
  final id = team.activePresetId?.trim() ?? '';
  return id.isNotEmpty ? TeamLaunchShape.preset : TeamLaunchShape.custom;
}

extension TeamLaunchConfig on TeamProfile {
  /// Normalizes dirty on-disk state to a single launch shape.
  TeamProfile normalizedLaunchConfig() {
    if (teamLaunchShape(this) == TeamLaunchShape.preset) {
      return copyWith(
        activePresetId: activePresetId!.trim(),
        updateActivePresetId: true,
        providerIdsByTool: const {},
        modelsByTool: const {},
        cliEffortLevels: const {},
      );
    }
    return copyWith(
      activePresetId: null,
      updateActivePresetId: true,
    );
  }

  TeamProfile asPresetLaunch(String presetId, {CliTool? syncCli}) {
    final trimmed = presetId.trim();
    return copyWith(
      activePresetId: trimmed,
      updateActivePresetId: true,
      providerIdsByTool: const {},
      modelsByTool: const {},
      cliEffortLevels: const {},
      cli: syncCli ?? cli,
    );
  }

  TeamProfile asCustomLaunch({
    required CliTool cli,
    required String providerId,
    required String model,
    required String effort,
  }) {
    return copyWith(
      activePresetId: null,
      updateActivePresetId: true,
    ).withLaunchDefaultsForCli(
      cli: cli,
      providerId: providerId,
      model: model,
      effort: effort,
    );
  }
}
