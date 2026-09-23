import '../../../../models/app_session.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../repositories/session_repository.dart';
import '../../../terminal/terminal_session.dart';
import 'connect_shell_result.dart';

/// Last-mile shell attach. Looks up tab internally; the connect flow
/// passes session identity only.
abstract interface class SessionShellConnectPort {
  Future<ConnectShellResult> connect({
    required String sessionId,
    required AppSession session,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
    TeamProfile? team,
    TeamMemberConfig? member,
    Workspace? workspace,
  });

  Future<void> cleanupAfterFailure({
    required String sessionId,
    required String memberId,
    required Object error,
    required StackTrace stackTrace,
    required bool reportFailure,
  });
}
