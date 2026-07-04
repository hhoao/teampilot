import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';

/// User intent to create a new conversation and surface it immediately.
class SessionCreateRequest {
  const SessionCreateRequest({
    required this.workspace,
    required this.isPersonal,
    this.team,
    this.member,
    this.repo,
    this.personalIdentityId = '',
    this.cli,
    this.personalPresetId,
    this.workingDirectory,
    this.emptyDisplayTitleFallback = 'New Chat',
    this.fixedSessionId,
  });

  final Workspace workspace;
  final bool isPersonal;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final SessionRepository? repo;
  final String personalIdentityId;
  final CliTool? cli;

  /// Personal launch: pin provider/model via a global CLI preset.
  final String? personalPresetId;
  final String? workingDirectory;
  final String emptyDisplayTitleFallback;

  /// When set, the staged session uses this id instead of a fresh UUID.
  final String? fixedSessionId;
}
