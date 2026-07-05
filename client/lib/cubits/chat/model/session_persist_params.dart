import '../../../models/expert_session_overlay.dart';
import '../../../models/team_config.dart';

/// Disk-write parameters for a session that is already surfaced in the UI.
class SessionPersistParams {
  const SessionPersistParams({
    required this.sessionTeamId,
    this.personalIdentityId = '',
    this.rosterMembers = const [],
    this.cli,
    this.personalPresetId,
    this.workingDirectory,
    this.expertOverlay,
  });

  final String sessionTeamId;
  final String personalIdentityId;
  final List<TeamMemberConfig> rosterMembers;
  final CliTool? cli;
  final String? personalPresetId;
  final String? workingDirectory;
  final ExpertSessionOverlay? expertOverlay;
}
