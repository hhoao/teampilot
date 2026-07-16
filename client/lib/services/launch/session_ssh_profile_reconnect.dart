import 'dart:async';

import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace_launch_context.dart';
import '../../services/launch/session_shell_connector.dart';
import '../../utils/logging/logger.dart';
import 'session_launch_workspace_index.dart';

typedef ScheduleMemberConnectFn =
    void Function(TeamProfile team, TeamMemberConfig member, ChatTab tab);

/// Reconnects open session tabs after an SSH profile change.
class SessionSshProfileReconnect {
  SessionSshProfileReconnect({
    required SessionLaunchHost host,
    required SessionShellConnector shellConnector,
    required WorkspaceLaunchContext Function(AppSession session) launchContextFor,
    required ScheduleMemberConnectFn scheduleMemberConnect,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required Iterable<ChatTab> Function() openTabs,
  }) : _host = host,
       _shellConnector = shellConnector,
       _launchContextFor = launchContextFor,
       _scheduleMemberConnect = scheduleMemberConnect,
       _workspaceIndex = workspaceIndex,
       _openTabs = openTabs;

  final SessionLaunchHost _host;
  final SessionShellConnector _shellConnector;
  final WorkspaceLaunchContext Function(AppSession session) _launchContextFor;
  final ScheduleMemberConnectFn _scheduleMemberConnect;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final Iterable<ChatTab> Function() _openTabs;

  Future<void> reconnect(String profileId) async {
    if (_host.isClosed) return;
    appLogger.i('[session-launch] reconnectSshProfile profile=$profileId');

    for (final tab in _openTabs()) {
      final session = tab.persistedSession;
      if (session == null) continue;

      if (session.sessionTeam.trim().isEmpty) {
        await _reconnectPersonalTab(tab, session, profileId);
      } else {
        final team = await _host.teamProfileById(session.sessionTeam.trim());
        if (team == null) continue;
        for (final member in team.members.where((m) => m.isValid)) {
          await _reconnectTeamMemberTab(
            tab: tab,
            team: team,
            member: member,
            session: session,
            profileId: profileId,
          );
        }
      }
    }
  }

  bool _targetUsesProfile(RuntimeTarget target, String profileId) {
    if (target.kind != RuntimeKind.ssh) return false;
    final id = target.sshProfileId ?? sshProfileIdOfId(target.id);
    return id == profileId;
  }

  Future<void> _reconnectTeamMemberTab({
    required ChatTab tab,
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required String profileId,
  }) async {
    final target = _host.lifecycle.launchWorkTarget(
      _launchContextFor(session),
      memberId: member.id,
    );
    if (!_targetUsesProfile(target, profileId)) return;

    final shell = tab.memberShells[member.id];
    if (shell == null || shell.isDisposed || shell.isConnecting) return;

    shell.disconnect();
    await tab.closeMemberRemotePlane(member.id);
    tab.membersPendingConnect.remove(member.id);
    _scheduleMemberConnect(team, member, tab);
  }

  Future<void> _reconnectPersonalTab(
    ChatTab tab,
    AppSession session,
    String profileId,
  ) async {
    final target = _host.lifecycle.launchWorkTarget(_launchContextFor(session));
    if (!_targetUsesProfile(target, profileId)) return;

    final shell =
        tab.resumeSession ??
        tab.memberShells[session.sessionId] ??
        (tab.memberShells.length == 1
            ? tab.memberShells.values.first
            : null);
    if (shell == null || shell.isDisposed || shell.isConnecting) return;

    shell.disconnect();
    await tab.closeMemberRemotePlane(session.sessionId);

    final workspace = _workspaceIndex().byId(session.workspaceId);
    if (workspace == null) return;

    tab.membersPendingConnect.add(session.sessionId);
    _host.beginSessionConnect(tab.info.id);
    try {
      await _shellConnector.connect(
        tab: tab,
        session: session,
        shell: shell,
        launched: session.launchState == AppSessionLaunchState.started,
        workspace: workspace,
      );
      _host.updateTabRunning(tab.info.id);
    } on Object catch (e, st) {
      appLogger.e(
        '[session-launch] personal reconnect failed session=${session.sessionId}: $e',
        error: e,
        stackTrace: st,
      );
      _host.failSessionConnect(tab.info.id, 'Failed to reconnect: $e');
    } finally {
      tab.membersPendingConnect.remove(session.sessionId);
    }
  }
}
