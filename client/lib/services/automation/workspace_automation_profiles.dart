import '../../cubits/launch_profile_cubit.dart';
import '../../models/automation_tab_scope.dart';
import '../../models/launch_profile.dart';
import '../../models/workspace.dart';

/// Launch profiles that may own automations for [workspace].
///
/// Simple mode uses the fixed [AutomationTabScope.simpleLaunchProfileId] key
/// and is not a [LaunchProfile] document — callers that need the Simple scope
/// should use that constant directly.
List<LaunchProfile> launchProfilesForWorkspaceAutomations({
  required Workspace workspace,
  required LaunchProfileState profiles,
}) {
  final ids = <String>{};
  final defaultId = workspace.defaultProfileId.trim();
  if (defaultId.isNotEmpty &&
      defaultId != AutomationTabScope.simpleLaunchProfileId) {
    ids.add(defaultId);
  }
  for (final teamId in workspace.memberTargetsByTeam.keys) {
    final trimmed = teamId.trim();
    if (trimmed.isNotEmpty) ids.add(trimmed);
  }

  final result = <LaunchProfile>[];
  for (final id in ids) {
    final profile = profiles.byId(id);
    if (profile != null) result.add(profile);
  }
  return result;
}

String defaultLaunchProfileIdForWorkspace({
  required Workspace workspace,
  required LaunchProfileState profiles,
}) {
  final preferred = workspace.defaultProfileId.trim();
  if (preferred.isNotEmpty) return preferred;
  final candidates = launchProfilesForWorkspaceAutomations(
    workspace: workspace,
    profiles: profiles,
  );
  if (candidates.isEmpty) {
    return AutomationTabScope.simpleLaunchProfileId;
  }
  return candidates.first.id;
}
