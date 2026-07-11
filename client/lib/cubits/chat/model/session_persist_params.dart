import '../../../models/simple_launch_identity.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';

/// Disk-write parameters for a session that is already surfaced in the UI.
class SessionPersistParams {
  const SessionPersistParams({
    required this.sessionTeamId,
    this.rosterMembers = const [],
    this.cli,
    this.simpleIdentity,
    this.workingDirectory,
    this.expertKey,
    this.continueOverrides,
  });

  final String sessionTeamId;
  final List<TeamMemberConfig> rosterMembers;
  final CliTool? cli;

  /// Simple launch: denormalized identity written to [AppSession].
  final SimpleLaunchIdentity? simpleIdentity;
  final String? workingDirectory;
  final String? expertKey;
  final SessionContinueOverrides? continueOverrides;
}
