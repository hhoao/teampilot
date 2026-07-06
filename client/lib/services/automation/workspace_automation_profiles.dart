import '../../cubits/launch_profile_cubit.dart';
import '../../models/launch_profile.dart';
import '../../models/workspace.dart';
import '../storage/launch_profile_provisioner.dart';

/// Launch profiles that may own automations for [workspace].
List<LaunchProfile> launchProfilesForWorkspaceAutomations({
  required Workspace workspace,
  required LaunchProfileState profiles,
}) {
  final ids = <String>{};
  final defaultId = workspace.defaultProfileId.trim();
  if (defaultId.isNotEmpty) ids.add(defaultId);
  for (final teamId in workspace.memberTargetsByTeam.keys) {
    final trimmed = teamId.trim();
    if (trimmed.isNotEmpty) ids.add(trimmed);
  }
  ids.add(LaunchProfileProvisioner.defaultPersonalId);

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
  final candidates = launchProfilesForWorkspaceAutomations(
    workspace: workspace,
    profiles: profiles,
  );
  if (candidates.isEmpty) {
    return LaunchProfileProvisioner.defaultPersonalId;
  }
  final preferred = workspace.defaultProfileId.trim();
  if (preferred.isNotEmpty && candidates.any((p) => p.id == preferred)) {
    return preferred;
  }
  return candidates.first.id;
}
