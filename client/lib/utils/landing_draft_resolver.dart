import '../models/landing_launch_context.dart';
import '../models/workspace.dart';
import '../services/home_workspace/landing_prefs_store.dart';
import '../services/storage/launch_profile_provisioner.dart';

/// Loads persisted compose-landing draft for a workspace (local to landing UI).
Future<LandingLaunchContext> resolveLandingDraft({
  required String workspaceId,
  required Workspace workspace,
  LandingPrefsStore? store,
}) async {
  final prefs = await (store ?? LandingPrefsStore()).prefsFor(workspaceId);
  final defaultProfile = workspace.defaultProfileId.trim().isNotEmpty
      ? workspace.defaultProfileId.trim()
      : LaunchProfileProvisioner.defaultPersonalId;
  if (prefs == null) {
    return LandingLaunchContext(
      isPersonal: true,
      personalProfileId: defaultProfile,
    );
  }
  return LandingLaunchContext(
    isPersonal: prefs.isPersonal,
    personalProfileId: prefs.personalProfileId ?? defaultProfile,
    presetId: prefs.presetId,
    teamId: prefs.teamId,
  );
}

Future<void> persistLandingDraft(
  String workspaceId,
  LandingLaunchContext draft, {
  LandingPrefsStore? store,
}) {
  return (store ?? LandingPrefsStore()).save(
    workspaceId,
    LandingPrefs(
      isPersonal: draft.isPersonal,
      presetId: draft.presetId,
      teamId: draft.teamId,
      personalProfileId: draft.personalProfileId,
    ),
  );
}
