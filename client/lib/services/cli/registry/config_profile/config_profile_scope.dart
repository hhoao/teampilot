import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../team/claude_team_roster_service.dart';

/// Profile directory key when launching without a chat [AppSession].
const configProfileAdhocSessionId = '_adhoc';

/// Workspace project id for local (`local-*`) team shells with no persisted project.
String effectiveLaunchProjectId({
  required String projectId,
  required String teamId,
}) {
  final trimmed = projectId.trim();
  if (trimmed.isNotEmpty) return trimmed;
  final team = teamId.trim();
  if (team.isEmpty) return '';
  return '_adhoc-$team';
}

/// Resolved launch path scope for a personal project session.
class StandaloneLaunchProfileScope {
  const StandaloneLaunchProfileScope({
    required this.projectId,
    required this.sessionId,
  });

  final String projectId;
  final String sessionId;
}

/// Resolved launch path scope for a team session.
class LaunchProfileScope {
  const LaunchProfileScope({
    required this.projectId,
    required this.teamId,
    required this.sessionId,
    required this.cliTeamName,
    this.memberId,
  });

  final String projectId;
  final String teamId;
  final String sessionId;
  final String cliTeamName;
  final String? memberId;
}

LaunchProfileScope resolveLaunchProfileScope({
  required String projectId,
  required String teamId,
  required String appSessionId,
  required String cliTeamName,
  String? memberId,
}) {
  final trimmedSession = appSessionId.trim();
  final trimmedCliTeam = cliTeamName.trim();
  return LaunchProfileScope(
    projectId: projectId.trim(),
    teamId: teamId.trim(),
    sessionId: trimmedSession.isNotEmpty ? trimmedSession : configProfileAdhocSessionId,
    cliTeamName: trimmedCliTeam.isNotEmpty ? trimmedCliTeam : teamId.trim(),
    memberId: memberId,
  );
}

/// Mixed-mode per-member runtime scope: nests the member under the session dir
/// so each agent process gets its own CONFIG_DIR.
String mixedModeMemberScopeSessionId(
  p.Context pathContext,
  String sessionId,
  TeamMemberConfig member,
) =>
    pathContext.join(
      sessionId,
      ClaudeTeamRosterService.safeClaudePathSegment(member.id),
    );
