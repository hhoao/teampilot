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

/// Mixed workspace: Machines placement has not been confirmed for this team.
final class MixedMemberPlacementUninitializedLaunchBlock
    extends WorkspaceLandingLaunchBlock {
  const MixedMemberPlacementUninitializedLaunchBlock();
}

/// Lead instance is missing or pinned to an invalid host.
final class LeadPlacementInvalidLaunchBlock
    extends WorkspaceLandingLaunchBlock {
  const LeadPlacementInvalidLaunchBlock();
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

    if (workspaceNeedsMixedPlacementInit(
      folders: workspace.folders,
      teamId: team.id,
      initializedByTeam: workspace.memberPlacementInitializedByTeam,
    )) {
      return const MixedMemberPlacementUninitializedLaunchBlock();
    }
    final targets = rememberedMemberTargets(
      workspace.memberTargetsByTeam,
      team.id,
    );
    final validMembers = team.members.where((m) => m.isValid).toList();
    // Empty targets on local/remote are OK until session create materializes
    // defaults (Task 6). Mixed (initialized) and any saved pins must keep
    // the lead on a valid preferred host.
    final mustValidateLead =
        targets.isNotEmpty ||
        workspaceTopologyOf(workspace.folders) == WorkspaceTopology.mixed;
    if (mustValidateLead &&
        !leadPlacementValid(
          folders: workspace.folders,
          members: validMembers,
          targets: targets,
        )) {
      return const LeadPlacementInvalidLaunchBlock();
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
