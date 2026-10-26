import '../../../../models/cli_binary_kind.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/landing_launch_context.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_topology.dart';
import '../../../../utils/workspace/landing_draft_resolver.dart';
import '../../../remote/remote_cli_readiness.dart';
import '../../../remote/remote_cli_requirements.dart';
import '../../../storage/home_storage.dart';
import '../session/team_config_launch_validator.dart';
import 'local_binary_requirements.dart';

/// Answers whether a local binary is known (configured path or discovery).
typedef LocalBinaryKnown = bool Function(CliTool cli, CliBinaryKind kind);

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
final class TeamConfigIncompleteLaunchBlock
    extends WorkspaceLandingLaunchBlock {
  const TeamConfigIncompleteLaunchBlock(this.validation);

  final TeamConfigValidation validation;
}

/// SSH-placed members need CLIs that are not located on their remote hosts.
final class RemoteCliMissingLaunchBlock extends WorkspaceLandingLaunchBlock {
  const RemoteCliMissingLaunchBlock(this.missing);

  final List<RemoteCliRequirement> missing;
}

/// Local launches need CLIs (or ACP adapters) this device has not located.
final class LocalCliMissingLaunchBlock extends WorkspaceLandingLaunchBlock {
  const LocalCliMissingLaunchBlock(this.missing);

  final List<LocalBinaryRequirement> missing;
}

/// Placement used by the landing gate (saved pins or in-memory defaults).
MemberPlacementByTarget memberPlacementForLaunch({
  required Workspace workspace,
  required TeamProfile team,
}) {
  final remembered = rememberedMemberTargets(
    workspace.memberTargetsByTeam,
    team.id,
  );
  final members = healMemberReplicasFromTargets(
    members: team.members,
    targets: remembered,
  );
  if (remembered.isEmpty) {
    return defaultMemberPlacement(folders: workspace.folders, members: members);
  }
  return memberPlacementFromMemberTargets(
    members: members,
    targets: remembered,
  );
}

/// Pre-launch checks for compose landing (mirrors session create/open gates).
class WorkspaceLandingLaunchGate {
  WorkspaceLandingLaunchGate({
    TeamConfigLaunchValidator? teamConfigValidator,
    required HomeStorage storage,
    LocalBinaryKnown? localBinaryKnown,
    MemberAcpSeed? localMemberAcpSeed,
    RuntimeTarget Function()? homeTargetResolver,
  }) : _storage = storage,
       _localBinaryKnown = localBinaryKnown,
       _localMemberAcpSeed = localMemberAcpSeed,
       _homeTargetResolver = homeTargetResolver,
       _teamConfigValidator =
           teamConfigValidator ?? TeamConfigLaunchValidator(storage: storage);

  final HomeStorage _storage;
  final LocalBinaryKnown? _localBinaryKnown;
  final MemberAcpSeed? _localMemberAcpSeed;
  final RuntimeTarget Function()? _homeTargetResolver;
  final TeamConfigLaunchValidator _teamConfigValidator;

  RuntimeTarget get _home =>
      _homeTargetResolver?.call() ?? RuntimeTarget.local();

  /// Fast checks that do not need provider catalog IO.
  ///
  /// Includes the local binary check: user-configured paths and startup
  /// discovery are already in memory, so it never blocks on IO.
  WorkspaceLandingLaunchBlock? syncBlock({
    required Workspace workspace,
    required LandingLaunchContext draft,
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
  }) {
    final placementBlock = _placementBlock(
      workspace: workspace,
      draft: draft,
      team: team,
    );
    if (placementBlock != null) return placementBlock;
    return localBlock(
      workspace: workspace,
      draft: draft,
      team: team,
      globalPresets: globalPresets,
    );
  }

  /// Blocks when a CLI (or ACP adapter) the draft will spawn locally is unknown.
  ///
  /// Personal drafts check the launch CLI plus its separate ACP adapter; team
  /// drafts check every member placed on a local host, plus the adapter for
  /// mixed-team members whose CLI settings default enables ACP chat.
  ///
  /// Disabled when no [LocalBinaryKnown] probe was injected (tests, Android
  /// where local CLI discovery never runs).
  LocalCliMissingLaunchBlock? localBlock({
    required Workspace workspace,
    required LandingLaunchContext draft,
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
  }) {
    final known = _localBinaryKnown;
    if (known == null) return null;

    final requirements = draft.isPersonal
        ? localBinaryRequirementsForSimpleLaunch(
            workspace: workspace,
            projectFolderPath: draft.projectFolderPath ?? '',
            cli: resolveLandingSimpleLaunchIdentity(
              presets: globalPresets,
              presetId: draft.presetId,
              cli: draft.cli,
              provider: draft.provider,
              model: draft.model,
              effort: draft.effort,
              expertKey: draft.expertKey,
            ).cli,
            requestedAcp: draft.acp,
            home: _home,
            usesPosixPaths: _storage.usesPosixPaths,
          )
        : team == null
        ? const <LocalBinaryRequirement>[]
        : localBinaryRequirementsForPlacement(
            team: team,
            placement: memberPlacementForLaunch(
              workspace: workspace,
              team: team,
            ),
            globalPresets: globalPresets,
            home: _home,
            acpSeed: _localMemberAcpSeed,
          );

    final missing = [
      for (final requirement in requirements)
        if (!known(requirement.cli, requirement.kind)) requirement,
    ];
    if (missing.isEmpty) return null;
    return LocalCliMissingLaunchBlock(missing);
  }

  WorkspaceLandingLaunchBlock? _placementBlock({
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

  /// Probes required remote CLIs for the current placement; never installs.
  Future<WorkspaceLandingLaunchBlock?> asyncRemoteCliBlock({
    required Workspace workspace,
    required TeamProfile team,
    required List<CliPreset> globalPresets,
    required List<RuntimeTarget> selectableTargets,
    required RemoteCliReadinessService readiness,
  }) async {
    final placement = memberPlacementForLaunch(
      workspace: workspace,
      team: team,
    );
    final requirements = remoteCliRequirementsForPlacement(
      workspace: workspace,
      team: team,
      placement: placement,
      globalPresets: globalPresets,
      selectableTargets: selectableTargets,
    );
    return _probeRemoteCliRequirements(requirements, readiness);
  }

  /// Probes the SSH host for a Simple launch on a remote project folder.
  Future<WorkspaceLandingLaunchBlock?> asyncRemoteCliBlockForSimple({
    required Workspace workspace,
    required LandingLaunchContext draft,
    required String projectFolderPath,
    required List<CliPreset> globalPresets,
    required List<RuntimeTarget> selectableTargets,
    required RemoteCliReadinessService readiness,
    required RuntimeTarget home,
  }) async {
    if (!draft.isPersonal) return null;
    final identity = resolveLandingSimpleLaunchIdentity(
      presets: globalPresets,
      presetId: draft.presetId,
      cli: draft.cli,
      provider: draft.provider,
      model: draft.model,
      effort: draft.effort,
    );
    final requirements = remoteCliRequirementsForSimpleLaunch(
      workspace: workspace,
      projectFolderPath: projectFolderPath,
      cli: identity.cli,
      requestedAcp: draft.acp,
      selectableTargets: selectableTargets,
      home: home,
      usesPosixPaths: _storage.usesPosixPaths,
    );
    return _probeRemoteCliRequirements(requirements, readiness);
  }

  Future<WorkspaceLandingLaunchBlock?> _probeRemoteCliRequirements(
    List<RemoteCliRequirement> requirements,
    RemoteCliReadinessService readiness,
  ) async {
    if (requirements.isEmpty) return null;

    final missing = <RemoteCliRequirement>[];
    for (final requirement in requirements) {
      final result = await readiness.probe(
        target: requirement.target,
        cli: requirement.cli,
        kind: requirement.kind,
      );
      if (result is RemoteCliMissing || result is RemoteCliFailed) {
        missing.add(requirement);
      }
    }
    if (missing.isEmpty) return null;
    return RemoteCliMissingLaunchBlock(missing);
  }

  /// Runs [syncBlock] then [asyncBlock] for team-mode drafts.
  Future<WorkspaceLandingLaunchBlock?> evaluate({
    required Workspace workspace,
    required LandingLaunchContext draft,
    TeamProfile? team,
    List<CliPreset> globalPresets = const [],
    List<RuntimeTarget> selectableTargets = const [],
    RemoteCliReadinessService? remoteCliReadiness,
  }) async {
    final sync = syncBlock(
      workspace: workspace,
      draft: draft,
      team: team,
      globalPresets: globalPresets,
    );
    if (sync != null) return sync;
    if (draft.isPersonal || team == null) return null;
    final configBlock = await asyncBlock(
      team: team,
      globalPresets: globalPresets,
    );
    if (configBlock != null) return configBlock;
    if (remoteCliReadiness == null || selectableTargets.isEmpty) {
      return null;
    }
    return asyncRemoteCliBlock(
      workspace: workspace,
      team: team,
      globalPresets: globalPresets,
      selectableTargets: selectableTargets,
      readiness: remoteCliReadiness,
    );
  }
}
