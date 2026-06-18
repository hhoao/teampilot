import '../../models/team_config.dart';
import 'model/identity_state.dart';

/// Seam between [IdentityCubit] and its collaborator services.
///
/// Services read the current snapshot via [state], emit through the single
/// [applyState] entry point (which the cubit guards against post-close emits),
/// and persist roster changes through [saveTeams]. They never call the cubit's
/// protected `emit` directly.
abstract interface class IdentityCubitHost {
  IdentityState get state;
  bool get isClosed;

  /// Single emit entry point; no-op once the cubit is closed.
  void applyState(IdentityState next);

  /// Persists [teams] to the identity repository.
  Future<void> saveTeams(List<TeamIdentity> teams);
}
