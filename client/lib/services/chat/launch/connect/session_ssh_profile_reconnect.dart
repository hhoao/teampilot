import '../../session/session_open_request.dart';
import '../session_launch_host.dart';
import '../../../../models/app_session.dart';
import '../../../../models/member_instance.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/workspace_launch_context.dart';
import '../../../../utils/logging/logger.dart';
import '../session/session_launch_coordinator.dart';
import '../session/session_launch_workspace_index.dart';
import 'ssh_reconnect_seats.dart';

/// Re-enqueues affected open sessions after an SSH profile change.
class SessionSshProfileReconnect {
  SessionSshProfileReconnect({
    required SessionLaunchHost host,
    required SessionReconnectIntentPort coordinator,
    required WorkspaceLaunchContext Function(AppSession session)
    launchContextFor,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required SshReconnectSeatPort seats,
  }) : _host = host,
       _coordinator = coordinator,
       _launchContextFor = launchContextFor,
       _workspaceIndex = workspaceIndex,
       _seats = seats;

  final SessionLaunchHost _host;
  final SessionReconnectIntentPort _coordinator;
  final WorkspaceLaunchContext Function(AppSession session) _launchContextFor;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final SshReconnectSeatPort _seats;

  Future<void> reconnect(String profileId) async {
    if (_host.isClosed) return;
    appLogger.i('[session-launch] reconnectSshProfile profile=$profileId');

    Object? firstError;
    StackTrace? firstStack;
    for (final open in _seats.openSessions) {
      try {
        final session = open.session;
        final requests = session.sessionTeam.trim().isEmpty
            ? await _personalRequests(open.sessionId, session, profileId)
            : await _teamRequests(open.sessionId, session, profileId);
        if (requests.isNotEmpty) {
          await _coordinator.reconnectTab(open.sessionId, requests);
        }
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  Future<List<SessionOpenRequest>> _teamRequests(
    String sessionId,
    AppSession session,
    String profileId,
  ) async {
    final team = await _host.teamProfileById(session.sessionTeam.trim());
    if (team == null) return const [];
    final workspace = _workspaceIndex().byId(session.workspaceId);
    final requests = <SessionOpenRequest>[];
    final rosterMembers = session.members.isNotEmpty
        ? sessionRosterMembers(session, team)
        : runtimeRosterMembers(team);
    for (final member in rosterMembers.where((member) => member.isValid)) {
      final target = _host.lifecycle.launchWorkTarget(
        _launchContextFor(session),
        memberId: member.id,
      );
      if (!_targetUsesProfile(target, profileId)) continue;
      final shell = _seats.memberShell(sessionId, member.id);
      if (shell == null || shell.isDisposed || shell.isConnecting) continue;

      shell.disconnect();
      await _seats.closeMemberRemotePlane(sessionId, member.id);
      _host.clearAgentStatusSeat(sessionId: sessionId, memberId: member.id);
      requests.add(
        SessionOpenRequest(
          session: session,
          workspace: workspace,
          team: team,
          member: member,
          repo: _host.sessionRepository,
        ),
      );
    }
    return requests;
  }

  Future<List<SessionOpenRequest>> _personalRequests(
    String sessionId,
    AppSession session,
    String profileId,
  ) async {
    final target = _host.lifecycle.launchWorkTarget(_launchContextFor(session));
    if (!_targetUsesProfile(target, profileId)) return const [];
    final shell = _seats.personalResumeShell(sessionId, session);
    if (shell == null || shell.isConnecting) return const [];

    shell.disconnect();
    await _seats.closeMemberRemotePlane(sessionId, session.sessionId);
    _host.clearAgentStatusSeat(
      sessionId: sessionId,
      memberId: session.sessionId,
    );
    final workspace = _workspaceIndex().byId(session.workspaceId);
    if (workspace == null) return const [];
    return [
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        repo: _host.sessionRepository,
        shellAcquisition: SessionShellAcquisition.personalResumeSession,
      ),
    ];
  }

  bool _targetUsesProfile(RuntimeTarget target, String profileId) {
    if (!usesSshTransport(target.kind)) return false;
    final id = target.sshProfileId ?? sshProfileIdOfId(target.id);
    return id == profileId;
  }
}
