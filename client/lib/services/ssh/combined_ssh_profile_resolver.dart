import '../../models/ssh_profile.dart';

/// Resolves a workload/home SSH profile by id for the remote-session and
/// provisioning chain (`ChatCubit.sshProfileById` /
/// `buildSessionConnectOrchestrator(profileById:)`).
///
/// Looks up the home-plane workload catalog (B source) first; on a miss it
/// falls back to the device-local A source home profile. This is an **id
/// resolver**, a point lookup — NOT the status-bar list assembler
/// `assembleSshHostProfiles` (which belongs to a different consumption chain).
///
/// The A-source fallback is deliberate and must be kept: a B-only workload
/// host resolves from the B source, while an A-source home profile (or any
/// id absent from B, e.g. when the home plane is unreachable and B is empty)
/// still resolves from the device-local catalog. That preserves SSH home mode
/// and offline home binding. The `?? _sshProfileResolver?.call()` selected-
/// profile fallback in `ChatSessionShellFactory._profileFor` remains the last
/// resort when even this resolver returns null — do not replace this with a
/// B-only lookup.
SshProfile? Function(String id) combinedSshProfileResolver({
  required SshProfile? Function(String id) workloadById,
  required SshProfile? Function(String id) homeById,
}) {
  return (id) => workloadById(id) ?? homeById(id);
}
