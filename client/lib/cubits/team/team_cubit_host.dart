import '../../models/team_config.dart';
import 'model/team_state.dart';

/// Seam between [TeamCubit] and its collaborator services.
///
/// Services read the current snapshot via [state], emit through the single
/// [applyState] entry point (which the cubit guards against post-close emits),
/// and persist roster changes through [saveTeams]. They never call the cubit's
/// protected `emit` directly.
abstract interface class TeamCubitHost {
  TeamState get state;
  bool get isClosed;

  /// Single emit entry point; no-op once the cubit is closed.
  void applyState(TeamState next);

  /// Persists [teams] to the team repository.
  Future<void> saveTeams(List<TeamIdentity> teams);
}
