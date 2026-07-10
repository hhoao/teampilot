import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';

/// Target for [SessionLaunchService.connectWorkspaceSession].
sealed class SessionConnectRequest {}

/// Connect the active team workspace session (materialize when tabs are empty).
final class TeamSessionConnect extends SessionConnectRequest {
  TeamSessionConnect(this.team);

  final TeamProfile team;
}

/// Connect the active Simple (unteamed) workspace session.
final class PersonalSessionConnect extends SessionConnectRequest {
  PersonalSessionConnect({
    required this.workspaceId,
    this.cliOverride,
  });

  final String workspaceId;
  final CliTool? cliOverride;
}

/// Connect an already-open review tab for a specific persisted session.
///
/// Used by session history review submit — must resume [session], not
/// materialize a new workspace default or pick another personal session.
final class ExistingSessionConnect extends SessionConnectRequest {
  ExistingSessionConnect({
    required this.session,
    this.team,
    this.member,
    this.workspace,
  });

  final AppSession session;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final Workspace? workspace;
}
