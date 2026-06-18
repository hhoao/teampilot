import '../models/app_project.dart';
import '../models/launch_identity.dart';
import '../models/identity.dart';
import '../services/storage/identity_provisioner.dart';

/// Resolves which identity to use when opening [project].
///
/// When [project.defaultIdentityId] is set but no longer exists, falls back to
/// the provisioned default personal identity.
LaunchIdentity resolveProjectLaunchIdentity(
  AppProject project,
  Identity? Function(String id) lookupById,
) {
  final preferred = project.defaultIdentityId.trim();
  if (preferred.isNotEmpty && lookupById(preferred) != null) {
    return LaunchIdentity(preferred);
  }
  return const LaunchIdentity(IdentityProvisioner.defaultPersonalId);
}
