import '../models/workspace.dart';
import '../models/launch_profile_ref.dart';
import '../models/launch_profile.dart';
import '../services/storage/launch_profile_provisioner.dart';

/// Resolves which identity to use when opening [workspace].
///
/// When [workspace.defaultProfileId] is set but no longer exists, falls back to
/// the provisioned default personal identity.
LaunchProfileRef resolveWorkspaceLaunchProfileRef(
  Workspace workspace,
  LaunchProfile? Function(String id) lookupById,
) {
  final preferred = workspace.defaultProfileId.trim();
  if (preferred.isNotEmpty && lookupById(preferred) != null) {
    return LaunchProfileRef(preferred);
  }
  return const LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId);
}
