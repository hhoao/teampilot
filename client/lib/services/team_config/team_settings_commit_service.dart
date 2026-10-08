import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import 'member_placement_save.dart';

/// Persist team identity (launch-profile cubit implements this).
abstract interface class TeamSettingsPersistPort {
  Future<void> selectTeam(
    String teamId, {
    bool silent = false,
    bool syncResources = true,
  });

  Future<void> updateSelected(TeamProfile team);
}

/// Patch the in-memory workspace snapshot (chat cubit implements this).
abstract interface class WorkspaceSnapshotPatchPort {
  void patchWorkspace(Workspace updated);
}

/// Single commit entry for team-settings saves (landing dialog, workspace
/// member-targets dialog).
///
/// Persists the team profile via [TeamSettingsPersistPort] and the member
/// placement, then patches the in-memory workspace — never a full
/// workspace/session disk rescan.
class TeamSettingsCommitService {
  TeamSettingsCommitService({
    required TeamSettingsPersistPort profiles,
    required SessionRepository sessionRepository,
    required WorkspaceSnapshotPatchPort workspaces,
  }) : _profiles = profiles,
       _sessionRepository = sessionRepository,
       _workspaces = workspaces;

  final TeamSettingsPersistPort _profiles;
  final SessionRepository _sessionRepository;
  final WorkspaceSnapshotPatchPort _workspaces;

  /// Persists [prepared] for [teamId] in [workspaceId].
  ///
  /// Returns `false` (and persists nothing) when the lead placement is
  /// invalid. Callers may close their dialog on `true`.
  Future<bool> commit({
    required String workspaceId,
    required String teamId,
    required PreparedMemberPlacementSave prepared,
  }) async {
    if (!prepared.leadValid) return false;
    await _profiles.selectTeam(teamId, silent: true, syncResources: false);
    // Persist placement totals on roster.overrides.replicas (members alone
    // are runtime-only and would be dropped on the next materialize).
    await _profiles.updateSelected(prepared.team);
    final updated = await _sessionRepository.updateWorkspaceMemberPlacement(
      workspaceId,
      teamId,
      targets: prepared.targets,
    );
    if (updated != null) {
      _workspaces.patchWorkspace(updated);
    }
    return true;
  }
}
