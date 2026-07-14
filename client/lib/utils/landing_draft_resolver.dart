import '../models/landing_launch_context.dart';
import '../services/home_workspace/landing_prefs_store.dart';

/// Loads persisted compose-landing draft for a workspace (local to landing UI).
Future<LandingLaunchContext> resolveLandingDraft({
  required String workspaceId,
  LandingPrefsStore? store,
}) async {
  final prefs = await (store ?? LandingPrefsStore()).prefsFor(workspaceId);
  if (prefs == null) {
    return const LandingLaunchContext(isPersonal: true);
  }
  return LandingLaunchContext(
    isPersonal: prefs.isPersonal,
    presetId: prefs.presetId,
    teamId: prefs.teamId,
    projectFolderPath: prefs.projectFolderPath,
    expertKey: prefs.expertKey,
    workingDirectoryPath: prefs.workingDirectoryPath,
    dangerouslySkipPermissions: prefs.dangerouslySkipPermissions,
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
      projectFolderPath: draft.projectFolderPath,
      expertKey: draft.expertKey,
      workingDirectoryPath: draft.workingDirectoryPath,
      dangerouslySkipPermissions: draft.dangerouslySkipPermissions,
    ),
  );
}
