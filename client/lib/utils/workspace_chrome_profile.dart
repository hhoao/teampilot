import '../cubits/launch_profile_cubit.dart';
import '../models/launch_profile.dart';
import '../models/workspace.dart';
import '../services/storage/launch_profile_provisioner.dart';

/// Stable workspace identity for chrome that must not follow compose-landing drafts
/// (right tools, manage panel, automations scope, …).
LaunchProfile? resolveWorkspaceChromeProfile(
  LaunchProfileCubit launchProfiles,
  Workspace workspace, {
  String? routeProfileId,
}) {
  final route = routeProfileId?.trim() ?? '';
  if (route.isNotEmpty) {
    return launchProfiles.byId(route);
  }
  final defaultId = workspace.defaultProfileId.trim().isNotEmpty
      ? workspace.defaultProfileId.trim()
      : LaunchProfileProvisioner.defaultPersonalId;
  return launchProfiles.byId(defaultId);
}

String workspaceChromeProfileId(
  Workspace workspace, {
  String? routeProfileId,
}) {
  final route = routeProfileId?.trim() ?? '';
  if (route.isNotEmpty) return route;
  final defaultId = workspace.defaultProfileId.trim();
  if (defaultId.isNotEmpty) return defaultId;
  return LaunchProfileProvisioner.defaultPersonalId;
}
