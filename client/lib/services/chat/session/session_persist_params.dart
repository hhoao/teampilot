import '../../../models/app_session.dart';
import '../../../models/simple_launch_identity.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';

/// Disk-write parameters for a session that is already surfaced in the UI.
class SessionPersistParams {
  const SessionPersistParams({
    required this.sessionTeamId,
    this.purpose = SessionPurpose.normal,
    this.workflowId = '',
    this.rosterMembers = const [],
    this.cli,
    this.simpleIdentity,
    this.workingDirectory,
    this.expertKey,
    this.continueOverrides,
  });

  final String sessionTeamId;

  /// Durable role of the new session (builder sessions use teamGeneration).
  final SessionPurpose purpose;

  /// Team-generation workflow id when [purpose] is teamGeneration.
  final String workflowId;
  final List<TeamMemberConfig> rosterMembers;
  final CliTool? cli;

  /// Simple launch: denormalized identity written to [AppSession].
  final SimpleLaunchIdentity? simpleIdentity;
  final String? workingDirectory;
  final String? expertKey;
  final SessionContinueOverrides? continueOverrides;
}
