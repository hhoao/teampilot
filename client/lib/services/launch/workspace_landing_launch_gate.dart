import '../../models/cli_preset.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../team/team_config_launch_validator.dart';

/// Why compose landing cannot start a team session yet.
sealed class WorkspaceLandingLaunchBlock {
  const WorkspaceLandingLaunchBlock();
}

/// No team selected in team conversation mode.
final class TeamNotSelectedLaunchBlock extends WorkspaceLandingLaunchBlock {
  const TeamNotSelectedLaunchBlock();
}

/// Mixed workspace: [Workspace.memberTargetsByTeam] incomplete for the team.
final class MixedMemberTargetsIncompleteLaunchBlock
    extends WorkspaceLandingLaunchBlock {
  const MixedMemberTargetsIncompleteLaunchBlock();
}

/// Team provider/model preset configuration is incomplete for launch.
final class TeamConfigIncompleteLaunchBlock extends WorkspaceLandingLaunchBlock {
  const TeamConfigIncompleteLaunchBlock(this.validation);

  final TeamConfigValidation validation;
}

/// Pre-launch checks for compose landing (mirrors session create/open gates).
class WorkspaceLandingLaunchGate {
  WorkspaceLandingLaunchGate({TeamConfigLaunchValidator? teamConfigValidator})
    : _teamConfigValidator =
          teamConfigValidator ?? TeamConfigLaunchValidator();

  final TeamConfigLaunchValidator _teamConfigValidator;

  /// Fast checks that do not need provider catalog IO.
  WorkspaceLandingLaunchBlock? syncBlock({
    required Workspace workspace,
    required LandingLaunchContext draft,
    TeamProfile? team,
  }) {
    if (draft.isPersonal) return null;
    if (team == null) return const TeamNotSelectedLaunchBlock();

    if (workspaceTopologyRequiresMemberAssignment(workspace.folders) &&
        !memberTargetsComplete(
          workspaceFolders: workspace.folders,
          members: team.members.where((m) => m.isValid).toList(),
          targets: rememberedMemberTargets(
            workspace.memberTargetsByTeam,
            team.id,
          ),
        )) {
      return const MixedMemberTargetsIncompleteLaunchBlock();
    }
    return null;
  }

  /// Provider/model preset validation (same as [TeamConfigLaunchValidator]).
  Future<WorkspaceLandingLaunchBlock?> asyncBlock({
    required TeamProfile team,
    List<CliPreset> globalPresets = const [],
  }) async {
    final validation = await _teamConfigValidator.validate(
      team,
      globalPresets: globalPresets,
    );
    if (validation.hasIssues) {
      return TeamConfigIncompleteLaunchBlock(validation);
    }
    return null;
  }

  /// Runs [syncBlock] then [asyncBlock] for team-mode drafts.
  Future<WorkspaceLandingLaunchBlock?> evaluate({
    required Workspace workspace,
    required LandingLaunchContext draft,
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
  }) async {
    final sync = syncBlock(
      workspace: workspace,
      draft: draft,
      team: team,
    );
    if (sync != null) return sync;
    if (draft.isPersonal || team == null) return null;
    return asyncBlock(team: team, globalPresets: globalPresets);
  }
}
