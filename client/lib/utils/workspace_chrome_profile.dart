import '../cubits/launch_profile_cubit.dart';
import '../models/launch_profile.dart';
import '../models/workspace.dart';

/// Fixed scope key for Simple (unteamed) launch — workspace tabs and routes.
const kSimpleLaunchProfileId = 'simple';

/// Stable workspace identity for chrome that must not follow compose-landing drafts
/// (right tools, manage panel, automations scope, …).
LaunchProfile? resolveWorkspaceChromeProfile(
  LaunchProfileCubit launchProfiles,
  Workspace workspace, {
  String? routeProfileId,
}) {
  final route = routeProfileId?.trim() ?? '';
  if (route.isNotEmpty) {
    if (route == kSimpleLaunchProfileId) return null;
    return launchProfiles.byId(route);
  }
  final defaultId = workspace.defaultProfileId.trim();
  if (defaultId.isEmpty || defaultId == kSimpleLaunchProfileId) {
    return null;
  }
  return launchProfiles.byId(defaultId);
}

String workspaceChromeProfileId(Workspace workspace, {String? routeProfileId}) {
  final route = routeProfileId?.trim() ?? '';
  if (route.isNotEmpty) return route;
  final defaultId = workspace.defaultProfileId.trim();
  if (defaultId.isNotEmpty) return defaultId;
  return kSimpleLaunchProfileId;
}
