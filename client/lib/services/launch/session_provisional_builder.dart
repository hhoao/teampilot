import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../models/team_config.dart';
import '../../utils/workspace_path_utils.dart';

/// In-memory session used to stage the workbench before disk persistence.
AppSession buildProvisionalSession({
  required String sessionId,
  required Workspace workspace,
  required bool isPersonal,
  String personalIdentityId = '',
  CliTool? cli,
  String? workingDirectory,
  String sessionTeamId = '',
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final trimmedTeam = sessionTeamId.trim();
  final folders = (workingDirectory != null && workingDirectory.trim().isNotEmpty)
      ? [
          WorkspaceFolder(
            path: normalizeWorkspacePath(workingDirectory),
            targetId: workspace.folders.isEmpty
                ? WorkspaceFolder.localTargetId
                : workspace.folders.first.targetId,
          ),
          ...workspace.folders.skip(1),
        ]
      : workspace.folders;

  return AppSession(
    sessionId: sessionId,
    workspaceId: workspace.workspaceId,
    folders: folders,
    display: '',
    sessionTeam: trimmedTeam,
    profileId: isPersonal ? personalIdentityId.trim() : '',
    cliTeamName: '',
    cli: isPersonal ? cli : null,
    members: const [],
    memberTargets: const {},
    launchState: AppSessionLaunchState.created,
    createdAt: now,
    updatedAt: now,
  );
}
