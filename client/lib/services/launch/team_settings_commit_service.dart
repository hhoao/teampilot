import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../repositories/session_repository.dart';
import 'member_placement_save.dart';

/// Single commit entry for team-settings saves (landing dialog, workspace
/// member-targets dialog).
///
/// Persists the team profile via [LaunchProfileCubit.updateSelected] and the
/// member placement, then patches the in-memory workspace in [ChatCubit] —
/// never a full workspace/session disk rescan (see [ChatCubit.patchWorkspace]).
class TeamSettingsCommitService {
  TeamSettingsCommitService({
    required LaunchProfileCubit launchProfileCubit,
    required SessionRepository sessionRepository,
    required ChatCubit chatCubit,
  }) : _launchProfileCubit = launchProfileCubit,
       _sessionRepository = sessionRepository,
       _chatCubit = chatCubit;

  final LaunchProfileCubit _launchProfileCubit;
  final SessionRepository _sessionRepository;
  final ChatCubit _chatCubit;

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
    await _launchProfileCubit.selectTeam(
      teamId,
      silent: true,
      syncResources: false,
    );
    // Persist placement totals on roster.overrides.replicas (members alone
    // are runtime-only and would be dropped on the next materialize).
    await _launchProfileCubit.updateSelected(prepared.team);
    final updated = await _sessionRepository.updateWorkspaceMemberPlacement(
      workspaceId,
      teamId,
      targets: prepared.targets,
    );
    if (updated != null) {
      _chatCubit.patchWorkspace(updated);
    }
    return true;
  }
}
