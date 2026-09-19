import '../../model/chat_tab.dart';
import '../../model/session_open_request.dart';
import '../../host/session_launch_host.dart';
import '../../../../models/app_session.dart';
import '../../../../models/member_instance.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/workspace_launch_context.dart';
import '../../../../utils/logging/logger.dart';
import '../session/session_launch_coordinator.dart';
import '../session/session_launch_workspace_index.dart';
import 'session_personal_shell.dart';

/// Re-enqueues affected open tabs after an SSH profile change.
class SessionSshProfileReconnect {
  SessionSshProfileReconnect({
    required SessionLaunchHost host,
    required SessionReconnectIntentPort coordinator,
    required WorkspaceLaunchContext Function(AppSession session)
    launchContextFor,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required Iterable<ChatTab> Function() openTabs,
  }) : _host = host,
       _coordinator = coordinator,
       _launchContextFor = launchContextFor,
       _workspaceIndex = workspaceIndex,
       _openTabs = openTabs;

  final SessionLaunchHost _host;
  final SessionReconnectIntentPort _coordinator;
  final WorkspaceLaunchContext Function(AppSession session) _launchContextFor;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final Iterable<ChatTab> Function() _openTabs;

  Future<void> reconnect(String profileId) async {
    if (_host.isClosed) return;
    appLogger.i('[session-launch] reconnectSshProfile profile=$profileId');

    Object? firstError;
    StackTrace? firstStack;
    for (final tab in _openTabs()) {
      try {
        final session = tab.persistedSession;
        if (session == null) continue;
        final requests = session.sessionTeam.trim().isEmpty
            ? await _personalRequests(tab, session, profileId)
            : await _teamRequests(tab, session, profileId);
        if (requests.isNotEmpty) {
          await _coordinator.reconnectTab(tab, requests);
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
    ChatTab tab,
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
      final shell = tab.memberShells[member.id];
      if (shell == null || shell.isDisposed || shell.isConnecting) continue;

      shell.disconnect();
      await tab.closeMemberRemotePlane(member.id);
      _host.clearAgentStatusSeat(sessionId: tab.info.id, memberId: member.id);
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
    ChatTab tab,
    AppSession session,
    String profileId,
  ) async {
    final target = _host.lifecycle.launchWorkTarget(_launchContextFor(session));
    if (!_targetUsesProfile(target, profileId)) return const [];
    final shell = displayedPersonalResumeShell(tab, session);
    if (shell == null || shell.isConnecting) return const [];

    shell.disconnect();
    await tab.closeMemberRemotePlane(session.sessionId);
    _host.clearAgentStatusSeat(
      sessionId: tab.info.id,
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
