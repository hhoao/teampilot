import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';

/// Builds the profile list fed to `SshConnectionCubit.syncProfiles`.
///
/// The status bar shows the home-plane workload catalog (B source) only. The
/// current SSH home is itself a storage-pool connection managed by the same
/// cubit, so it must stay in the cubit's profile map: boot reconnect and
/// `SshHomeDisconnectedBanner` still call `connect(pid)` on it. This helper
/// therefore appends the home profile (resolved from the device-local A
/// source) when it is not already present in the B source; the status bar
/// hides that host again via `SshConnectionState.excluding`.
///
/// Pure: never mutates its inputs and returns an unmodifiable list.
List<SshProfile> assembleSshHostProfiles({
  required List<SshProfile> workloadProfiles,
  required List<SshProfile> deviceProfiles,
  required RuntimeTarget home,
}) {
  final homeProfileId =
      home.kind == RuntimeKind.ssh ? home.sshProfileId : null;
  if (homeProfileId == null ||
      homeProfileId.isEmpty ||
      workloadProfiles.any((p) => p.id == homeProfileId)) {
    return List<SshProfile>.unmodifiable(workloadProfiles);
  }

  SshProfile? homeProfile;
  for (final profile in deviceProfiles) {
    if (profile.id == homeProfileId) {
      homeProfile = profile;
      break;
    }
  }
  if (homeProfile == null) {
    return List<SshProfile>.unmodifiable(workloadProfiles);
  }

  return List<SshProfile>.unmodifiable([...workloadProfiles, homeProfile]);
}
