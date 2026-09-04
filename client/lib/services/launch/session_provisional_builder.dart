import '../../models/app_session.dart';
import '../../models/runtime_target.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/workspace.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/storage/work_target_canonicalizer.dart';

/// In-memory session used to stage the workbench before disk persistence.
AppSession buildProvisionalSession({
  required String sessionId,
  required Workspace workspace,
  required bool isPersonal,
  CliTool? cli,
  SimpleLaunchIdentity? simpleIdentity,
  String? workingDirectory,
  String sessionTeamId = '',
  String? expertKey,
  RuntimeTarget? home,
  SessionPurpose purpose = SessionPurpose.normal,
  String workflowId = '',
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final trimmedTeam = sessionTeamId.trim();
  final folders = Workspace.foldersForPrimaryPath(
    workspace.folders,
    workingDirectory ?? '',
    defaultTargetId: home == null
        ? null
        : WorkTargetCanonicalizer.defaultFolderTargetId(home),
  );
  final identity = isPersonal
      ? (simpleIdentity ??
            SimpleLaunchIdentity.resolve(
              cli: cli,
              expertKey: expertKey,
              officialProviderId:
                  CliToolRegistry.builtIn().defaultOfficialProviderId,
            ))
      : null;

  return AppSession(
    sessionId: sessionId,
    workspaceId: workspace.workspaceId,
    folders: folders,
    display: '',
    sessionTeam: trimmedTeam,
    profileId: '',
    cliTeamName: '',
    cli: isPersonal ? (identity?.cli ?? cli) : null,
    provider: identity?.provider ?? '',
    model: identity?.model ?? '',
    effort: identity?.effort ?? '',
    presetId: identity?.presetId ?? '',
    members: const [],
    memberTargets: const {},
    launchState: AppSessionLaunchState.created,
    createdAt: now,
    updatedAt: now,
    expertKey: identity?.expertKey.isNotEmpty == true
        ? identity!.expertKey
        : (expertKey?.trim() ?? ''),
    purpose: purpose,
    workflowId: workflowId,
  );
}
