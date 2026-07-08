import '../../cubits/chat/model/session_connect_request.dart';
import '../../cubits/chat/model/session_create_request.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';

/// User- or system-initiated launch operation routed through
/// [SessionLaunchPipeline].
sealed class LaunchOperation {}

/// Surface a persisted session in the workbench and optionally connect.
final class OpenSessionOperation extends LaunchOperation {
  OpenSessionOperation(this.request);

  final SessionOpenRequest request;
}

/// Stage a new conversation tab immediately, then persist and connect async.
final class CreateSessionOperation extends LaunchOperation {
  CreateSessionOperation(this.request);

  final SessionCreateRequest request;
}

/// Connect the active workspace session (materialize when tabs are empty).
final class ConnectWorkspaceOperation extends LaunchOperation {
  ConnectWorkspaceOperation(this.request, {this.repo});

  final SessionConnectRequest request;
  final SessionRepository? repo;
}

/// Disconnect then reconnect the active workspace session.
final class RestartWorkspaceOperation extends LaunchOperation {
  RestartWorkspaceOperation(this.request, {this.repo});

  final SessionConnectRequest request;
  final SessionRepository? repo;
}

/// Open a single team member tab and schedule PTY connect.
final class OpenMemberTabOperation extends LaunchOperation {
  OpenMemberTabOperation(
    this.team,
    this.member, {
    this.repo,
    this.workspaceCwd,
    this.scheduleTeamConfigValidation = true,
  });

  final TeamProfile team;
  final TeamMemberConfig member;
  final SessionRepository? repo;
  final String? workspaceCwd;
  final bool scheduleTeamConfigValidation;
}

/// Schedule PTY connect for every valid roster member on the active tab.
final class LaunchAllMembersOperation extends LaunchOperation {
  LaunchAllMembersOperation(this.team, {this.repo, this.workspaceCwd});

  final TeamProfile team;
  final SessionRepository? repo;
  final String? workspaceCwd;
}
