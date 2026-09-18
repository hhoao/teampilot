import '../../../cubits/chat/model/chat_tab.dart';
import '../../../cubits/chat/model/session_open_request.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';

enum LaunchReason {
  create,
  openExisting,
  memberSelected,
  restore,
  retry,
  sshReconnect,
}

final class SessionConnectJob {
  const SessionConnectJob({
    required this.tab,
    required this.session,
    required this.request,
    required this.generation,
    required this.workspace,
    this.team,
    this.member,
    required this.reason,
    this.reused = false,
    this.connectShell = true,
    this.materializeShell = false,
    this.propagateErrors = false,
  });

  final ChatTab tab;
  final AppSession session;
  final SessionOpenRequest request;
  final int generation;
  final Workspace? workspace;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final LaunchReason reason;
  final bool reused;
  final bool connectShell;
  final bool materializeShell;
  final bool propagateErrors;

  String get sessionId => session.sessionId;
  String get memberId => member?.id.trim().isNotEmpty == true
      ? member!.id.trim()
      : session.sessionId;
}
