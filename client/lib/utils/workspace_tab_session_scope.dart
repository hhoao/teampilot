import '../models/launch_profile.dart';
import '../models/launch_profile_kind.dart';
import '../models/launch_profile_ref.dart';

/// Team id used by [ChatCubit.setTeamSessionScope] for a title-bar workspace tab.
/// Personal identities scope to '' (no team filter).
String workspaceTabSessionTeamScopeId(
  LaunchProfileRef identity,
  LaunchProfile? resolvedIdentity,
) {
  if (resolvedIdentity?.kind == LaunchProfileKind.personal) return '';
  return identity.profileId;
}
