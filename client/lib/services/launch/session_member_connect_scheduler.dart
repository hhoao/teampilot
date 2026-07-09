import 'dart:async';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace_launch_context.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/launch/session_shell_connector.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logger.dart';
import 'personal_launch_context_resolver.dart';
import 'session_launch_workspace_index.dart';

typedef ShellForLaunchFn =
    TerminalSession Function({
      required ChatTab tab,
      required String shellKey,
      required CliTool cli,
      required AppSession session,
      String? rosterMemberId,
    });

typedef SessionForMemberConnectFn =
    AppSession? Function(ChatTab tab, TeamProfile team);

/// Schedules per-member PTY connects for an existing team session tab.
class SessionMemberConnectScheduler {
  SessionMemberConnectScheduler({
    required SessionLaunchHost host,
    required SessionShellConnector shellConnector,
    required ShellForLaunchFn shellForLaunch,
    required SessionForMemberConnectFn sessionForMemberConnect,
    required ChatTabStore tabStore,
    required ChatState Function() state,
  }) : _host = host,
       _shellConnector = shellConnector,
       _shellForLaunch = shellForLaunch,
       _sessionForMemberConnect = sessionForMemberConnect,
       _tabStore = tabStore,
       _state = state;

  final SessionLaunchHost _host;
  final SessionShellConnector _shellConnector;
  final ShellForLaunchFn _shellForLaunch;
  final SessionForMemberConnectFn _sessionForMemberConnect;
  final ChatTabStore _tabStore;
  final ChatState Function() _state;

  TerminalSession memberShellForConnect({
    required ChatTab tab,
    required TeamProfile team,
    required TeamMemberConfig member,
    AppSession? session,
  }) {
    final activeSession = session ?? tab.persistedSession;
    if (activeSession == null) {
      return tab.memberShells.putIfAbsent(
        member.id,
        () => _host.shellFactory.newSession(
          memberLaunchCli(
            team: team,
            member: member,
            globalPresets: _host.lifecycle.globalPresets,
          ),
        ),
      );
    }
    return _shellForLaunch(
      tab: tab,
      shellKey: member.id,
      cli: memberLaunchCli(
        team: team,
        member: member,
        globalPresets: _host.lifecycle.globalPresets,
      ),
      session: activeSession,
      rosterMemberId: member.id,
    );
  }

  void schedule(TeamProfile team, TeamMemberConfig member, ChatTab tab) {
    appLogger.d(
      '[session-launch] scheduleMemberConnect '
      'session=${tab.info.id} member=${member.id} team=${team.id}',
    );
    tab.selectedMemberId = member.id;
    final session = tab.persistedSession ?? _sessionForMemberConnect(tab, team);
    final shell = memberShellForConnect(
      tab: tab,
      team: team,
      member: member,
      session: session,
    );
    final state = _state();
    _host.applyState(
      state.copyWith(
        tabs: _tabStore.activeTabInfos(),
        activeSessionId: tab.info.id,
        selectedMemberId: member.id,
        composeActive: false,
      ),
    );
    if (shell.isRunning || shell.isConnecting) {
      appLogger.d(
        '[session-launch] scheduleMemberConnect skip '
        'session=${tab.info.id} member=${member.id} '
        'reason=shell_active running=${shell.isRunning} '
        'connecting=${shell.isConnecting}',
      );
      _host.updateTabRunning(tab.info.id);
      return;
    }
    if (tab.membersPendingConnect.contains(member.id)) {
      appLogger.d(
        '[session-launch] scheduleMemberConnect skip '
        'session=${tab.info.id} member=${member.id} reason=pending',
      );
      return;
    }
    tab.membersPendingConnect.add(member.id);
    _tabStore.workingDirectoryAndAddDirsForTab(
      tab,
      state.sessions,
      workspaces: state.workspaces,
    );
    final ownsConnectToken = state.sessionConnectingId != tab.info.id;
    if (ownsConnectToken) {
      _host.beginSessionConnect(tab.info.id);
    }
    _host.postFrameScheduler(() async {
      try {
        if (shell.isRunning) {
          _host.memberMaterializer.markMemberReady(tab.info.id, member.id);
          if (ownsConnectToken) {
            _host.finishSessionConnect(tab.info.id);
          }
          return;
        }
        final connectSession = _sessionForMemberConnect(tab, team);
        if (connectSession == null) {
          _host.failSessionConnect(
            tab.info.id,
            'No persisted session for this tab. Create a team session first.',
          );
          return;
        }
        if (team.teamMode == TeamMode.mixed &&
            (tab.teamBus == null ||
                !_host.teammateBusMcpGateway.isSessionRegistered(
                  connectSession.sessionId,
                ))) {
          await _host.teamBus.installBusForTab(tab, team, connectSession);
        }
        final result = await _shellConnector.connect(
          tab: tab,
          session: connectSession,
          shell: shell,
          launched: connectSession.launchState == AppSessionLaunchState.started,
          team: team,
          member: member,
        );
        if (result == ConnectShellResult.attached) {
          _host.updateTabRunning(tab.info.id);
        }
      } on Object catch (e, st) {
        appLogger.e(
          '[session-launch] member connect failed for ${member.name}: $e',
          error: e,
          stackTrace: st,
        );
        final message = 'Failed to start session: $e';
        shell.write('\r\n[$message]\r\n');
        _host.failSessionConnect(tab.info.id, message);
      } finally {
        tab.membersPendingConnect.remove(member.id);
      }
    });
  }
}
