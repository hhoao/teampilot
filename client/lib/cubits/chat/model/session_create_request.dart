import '../../../models/simple_launch_identity.dart';
import '../../../models/session_continue_overrides.dart';
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
    this.simpleIdentity,
    this.workingDirectory,
    this.emptyDisplayTitleFallback = 'New Chat',
    this.fixedSessionId,
    this.expertKey,
    this.continueOverrides,
    this.preserveWorkbenchView = false,
  });

  final Workspace workspace;

  /// True for Simple (unteamed) launch — empty [sessionTeam].
  final bool isPersonal;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final SessionRepository? repo;
  final CliTool? cli;

  /// Simple launch: resolved identity (cli/provider/model/effort/expert/preset).
  final SimpleLaunchIdentity? simpleIdentity;
  final String? workingDirectory;
  final String emptyDisplayTitleFallback;

  /// When set, the staged session uses this id instead of a fresh UUID.
  final String? fixedSessionId;

  /// Simple summon: catalog expert key (also on [simpleIdentity.expertKey]).
  final String? expertKey;

  /// Session-level continue overrides (e.g. landing permission chip).
  final SessionContinueOverrides? continueOverrides;

  /// When true, keep the new tab on Chat instead of forcing Terminal on connect.
  final bool preserveWorkbenchView;
}
