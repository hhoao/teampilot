import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';

/// How an SSH catalog diff affects the current home storage plane.
enum HomeSshProfileImpact {
  /// Unrelated catalog churn — keep workspaces alive.
  none,

  /// Home is `ssh:X` and X's connection identity changed — rebind + reload.
  homeConnectionChanged,

  /// Home is `ssh:X` and X was removed from the catalog — fall back home.
  homeProfileMissing,
}

/// Connection-facing identity for home invalidation (excludes display [SshProfile.name]).
String sshHomeConnectionFingerprint(SshProfile profile) =>
    '${profile.id}|${profile.host}|${profile.port}|${profile.username}|${profile.authType.name}';

/// Pure policy: only home-affecting SSH diffs require storage invalidation.
HomeSshProfileImpact resolveHomeSshProfileImpact({
  required String homeTargetId,
  required List<SshProfile> previous,
  required List<SshProfile> next,
}) {
  final profileId = sshProfileIdOfId(homeTargetId);
  if (profileId == null) return HomeSshProfileImpact.none;

  SshProfile? find(List<SshProfile> profiles) {
    for (final profile in profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  final before = find(previous);
  final after = find(next);

  if (before != null && after == null) {
    return HomeSshProfileImpact.homeProfileMissing;
  }
  if (before != null &&
      after != null &&
      sshHomeConnectionFingerprint(before) !=
          sshHomeConnectionFingerprint(after)) {
    return HomeSshProfileImpact.homeConnectionChanged;
  }
  return HomeSshProfileImpact.none;
}
