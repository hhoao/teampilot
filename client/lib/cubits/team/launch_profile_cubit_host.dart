import '../../models/team_config.dart';
import 'model/launch_profile_state.dart';

/// Seam between [LaunchProfileCubit] and its collaborator services.
///
/// Services read the current snapshot via [state], emit through the single
/// [applyState] entry point (which the cubit guards against post-close emits),
/// and persist roster changes through [saveTeamProfiles]. They never call the cubit's
/// protected `emit` directly.
abstract interface class LaunchProfileCubitHost {
  LaunchProfileState get state;
  bool get isClosed;

  /// Single emit entry point; no-op once the cubit is closed.
  void applyState(LaunchProfileState next);

  /// Persists [teams] to the identity repository.
  Future<void> saveTeamProfiles(List<TeamProfile> teams);
}
