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
    this.workingDirectory,
    this.emptyDisplayTitleFallback = 'New Chat',
  });

  final Workspace workspace;
  final bool isPersonal;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final SessionRepository? repo;
  final String personalIdentityId;
  final CliTool? cli;
  final String? workingDirectory;
  final String emptyDisplayTitleFallback;
}
