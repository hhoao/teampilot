import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../team/claude_team_roster_service.dart';

/// Profile directory key when launching without a chat [AppSession].
const configProfileAdhocSessionId = '_adhoc';

/// Resolved launch path scope for a team session.
class LaunchProfileScope {
  const LaunchProfileScope({
    required this.teamId,
    required this.sessionId,
    required this.cliTeamName,
  });

  final String teamId;
  final String sessionId;
  final String cliTeamName;
}

LaunchProfileScope resolveLaunchProfileScope({
  required String teamId,
  required String runtimeTeamId,
}) {
  final runtime = runtimeTeamId.trim();
  final sessionId = runtime.isNotEmpty ? runtime : configProfileAdhocSessionId;
  final cliTeamName = runtime.isNotEmpty ? runtime : teamId;
  return LaunchProfileScope(
    teamId: teamId,
    sessionId: sessionId,
    cliTeamName: cliTeamName,
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
