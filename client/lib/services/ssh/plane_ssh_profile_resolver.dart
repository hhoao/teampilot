import '../../models/ssh_profile.dart';

/// Builds the synchronous `profileOf` resolver over the home-plane (B source)
/// workload catalog for workspace MCP injection and remote sessions.
///
/// [planeProfiles] is a live getter: the B-source catalog cubit re-emits on a
/// home-plane swap, so reading on every call keeps the resolver current. The
/// cubit emits an empty list when the home plane is unreachable, so unknown ids
/// resolve to null — no error and no fallback to the device-local A source.
/// Callers keep their existing null handling.
SshProfile? Function(String id) planeSshProfileResolver(
  List<SshProfile> Function() planeProfiles,
) {
  return (id) {
    for (final profile in planeProfiles()) {
      if (profile.id == id) return profile;
    }
    return null;
  };
}
