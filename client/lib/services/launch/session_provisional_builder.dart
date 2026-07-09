import '../../models/app_session.dart';
import '../../models/workspace.dart';
import '../../models/team_config.dart';

/// In-memory session used to stage the workbench before disk persistence.
AppSession buildProvisionalSession({
  required String sessionId,
  required Workspace workspace,
  required bool isPersonal,
  String personalIdentityId = '',
  CliTool? cli,
  String? workingDirectory,
  String sessionTeamId = '',
  String? expertKey,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final trimmedTeam = sessionTeamId.trim();
  final folders = Workspace.foldersForPrimaryPath(
    workspace.folders,
    workingDirectory ?? '',
  );

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
    expertKey: expertKey?.trim() ?? '',
  );
}
