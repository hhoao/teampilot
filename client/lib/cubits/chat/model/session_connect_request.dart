import '../../../models/team_config.dart';

/// Target for [SessionLaunchService.connectWorkspaceSession].
sealed class SessionConnectRequest {}

/// Connect the active team workspace session (materialize when tabs are empty).
final class TeamSessionConnect extends SessionConnectRequest {
  TeamSessionConnect(this.team);

  final TeamProfile team;
}

/// Connect the active personal workspace session (materialize when tabs are empty).
final class PersonalSessionConnect extends SessionConnectRequest {
  PersonalSessionConnect({
    required this.workspaceId,
    this.personalIdentityId = '',
    this.cliOverride,
  });

  final String workspaceId;
  final String personalIdentityId;
  final CliTool? cliOverride;
}
