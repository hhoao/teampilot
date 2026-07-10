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
    this.cli,
    this.personalPresetId,
    this.workingDirectory,
    this.emptyDisplayTitleFallback = 'New Chat',
    this.fixedSessionId,
    this.expertKey,
  });

  final Workspace workspace;

  /// True for Simple (unteamed) launch — empty [sessionTeam].
  final bool isPersonal;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final SessionRepository? repo;
  final CliTool? cli;

  /// Simple launch: pin provider/model via a global CLI preset.
  final String? personalPresetId;
  final String? workingDirectory;
  final String emptyDisplayTitleFallback;

  /// When set, the staged session uses this id instead of a fresh UUID.
  final String? fixedSessionId;

  /// Simple summon: catalog expert key resolved at connect.
  final String? expertKey;
}
