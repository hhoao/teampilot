import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import 'session_tab_connect_prep.dart';

typedef ScheduleShellConnectFn =
    void Function({
      required int generation,
      required ChatTab tab,
      required AppSession session,
      required TerminalSession shell,
      required SessionOpenRequest request,
      required bool launched,
      required Workspace? workspace,
      required TeamProfile? team,
      required TeamMemberConfig? member,
      VoidCallback? onFinally,
    });

typedef RollbackStagedLaunchFn =
    void Function({
      required ChatTab tab,
      required String sessionId,
      required SessionOpenRequest request,
      required String message,
    });

/// Whether an existing-tab reuse must (re)install the mixed team runtime:
/// personal sessions never need it, and an installed bus makes it a no-op.
bool needsTeamRuntimeOnReuse(ChatTab tab, {required bool isPersonal}) =>
    !isPersonal && tab.teamBus == null;

/// Runs async tab-connect prep for new, existing, and deferred team tabs.
class SessionLaunchConnectPrepRunner {
  SessionLaunchConnectPrepRunner({
    required SessionLaunchHost host,
    required SessionTabConnectPrepCallbacks prepCallbacks,
    required bool Function(SessionOpenRequest request) shouldAutoConnect,
    required ScheduleShellConnectFn scheduleShellConnect,
    required RollbackStagedLaunchFn rollbackStagedLaunch,
    required Future<void> Function({
      required ChatTab tab,
      required AppSession session,
      required TeamProfile? team,
      required int generation,
    })
    installTeamRuntimeIfNeeded,
  }) : _host = host,
       _prepCallbacks = prepCallbacks,
       _shouldAutoConnect = shouldAutoConnect,
       _scheduleShellConnect = scheduleShellConnect,
       _rollbackStagedLaunch = rollbackStagedLaunch,
       _installTeamRuntimeIfNeeded = installTeamRuntimeIfNeeded;

  final SessionLaunchHost _host;
  final SessionTabConnectPrepCallbacks _prepCallbacks;
  final bool Function(SessionOpenRequest request) _shouldAutoConnect;
  final ScheduleShellConnectFn _scheduleShellConnect;
  final RollbackStagedLaunchFn _rollbackStagedLaunch;
  final Future<void> Function({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile? team,
    required int generation,
  })
  _installTeamRuntimeIfNeeded;

  Future<void> prepareNewTabConnect({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
    required Workspace? workspace,
    required bool connect,
  }) async {
    final started = Stopwatch()..start();
    appLogger.d(
      '[session-launch] prepareNewTab begin '
      'session=${session.sessionId} connect=$connect',
    );
    try {
      final prep = await runSessionTabConnectPrep(
        callbacks: _prepCallbacks,
        generation: generation,
        tab: tab,
        session: session,
        request: request,
        workspace: workspace,
        installTeamRuntime: true,
      );
      if (prep == null) return;

      if (!connect) {
        _host.updateTabRunning(prep.launchSession.sessionId);
        return;
      }
      final launched =
          prep.launchSession.launchState == AppSessionLaunchState.started;
      appLogger.d(
        '[session-launch] prepareNewTab schedule-connect '
        'session=${prep.launchSession.sessionId} '
        'ms=${started.elapsedMilliseconds}',
      );
      _scheduleShellConnect(
        generation: generation,
        tab: tab,
        session: prep.launchSession,
        shell: prep.shell,
        request: request,
        launched: launched,
        workspace: workspace,
        team: prep.resolved.team,
        member: request.isPersonal ? null : prep.resolved.member,
      );
    } on Object catch (e, st) {
      await _handlePrepFailure(
        error: e,
        stackTrace: st,
        logLabel: 'prepare new tab failed',
        tab: tab,
        session: session,
        request: request,
        generation: generation,
      );
    }
  }

  Future<void> prepareDeferredTeamTab({
    required int generation,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
  }) async {
    final team = request.team;
    if (team == null || request.member == null) return;
    try {
      await _installTeamRuntimeIfNeeded(
        tab: tab,
        session: session,
        team: team,
        generation: generation,
      );
      if (!_prepCallbacks.launchStillValid(tab, generation)) return;
      _host.assignSelectedMember(tab, request.member!.id);
      _host.updateTabRunning(session.sessionId);
    } on Object catch (e, st) {
      appLogger.e(
        '[session-launch] deferred team tab prep failed session=${session.sessionId}: $e',
        error: e,
        stackTrace: st,
      );
      if (_prepCallbacks.launchStillValid(tab, generation)) {
        _host.setLaunchError(session.sessionId, e.toString());
      }
    }
  }

  Future<void> prepareExistingTabConnect({
    required int generation,
    required ChatTab tab,
    required SessionOpenRequest request,
    required bool connect,
    required Workspace? Function(String workspaceId) workspaceById,
  }) async {
    var session = request.session;
    final persisted = tab.persistedSession;
    if (!request.isPersonal &&
        session.cliTeamName.isEmpty &&
        persisted != null &&
        persisted.cliTeamName.isNotEmpty) {
      session = persisted;
    }
    final workspace = request.workspace ?? workspaceById(session.workspaceId);
    if (request.isPersonal && workspace == null) return;

    try {
      final prep = await runSessionTabConnectPrep(
        callbacks: _prepCallbacks,
        generation: generation,
        tab: tab,
        session: session,
        request: request,
        workspace: workspace,
        installTeamRuntime: needsTeamRuntimeOnReuse(tab, isPersonal: request.isPersonal),
      );
      if (prep == null) return;

      final launchSession = prep.launchSession;
      final shell = prep.shell;

      if (shell.isRunning || shell.isConnecting) {
        _host.updateTabRunning(tab.info.id);
        if (_host.isSessionConnecting(launchSession.sessionId)) {
          _host.finishSessionConnect(launchSession.sessionId);
        }
        return;
      }
      if (tab.membersPendingConnect.contains(prep.resolved.member.id)) return;

      if (!connect) {
        _host.updateTabRunning(tab.info.id);
        return;
      }

      if (_shouldAutoConnect(request) &&
          !_host.isSessionConnecting(launchSession.sessionId)) {
        _host.beginSessionConnect(launchSession.sessionId);
      }

      tab.membersPendingConnect.add(prep.resolved.member.id);
      final launched =
          launchSession.launchState == AppSessionLaunchState.started;
      _scheduleShellConnect(
        generation: generation,
        tab: tab,
        session: launchSession,
        shell: shell,
        request: request,
        launched: launched,
        workspace: workspace,
        team: prep.resolved.team,
        member: request.isPersonal ? null : prep.resolved.member,
        onFinally: () =>
            tab.membersPendingConnect.remove(prep.resolved.member.id),
      );
    } on Object catch (e, st) {
      await _handlePrepFailure(
        error: e,
        stackTrace: st,
        logLabel: 'prepare existing tab failed',
        tab: tab,
        session: session,
        request: request,
        generation: generation,
      );
    }
  }

  Future<void> _handlePrepFailure({
    required Object error,
    required StackTrace stackTrace,
    required String logLabel,
    required ChatTab tab,
    required AppSession session,
    required SessionOpenRequest request,
    required int generation,
  }) async {
    appLogger.e(
      '[session-launch] $logLabel session=${session.sessionId}: $error',
      error: error,
      stackTrace: stackTrace,
    );
    if (_prepCallbacks.launchStillValid(tab, generation)) {
      if (request.persistParams != null) {
        _rollbackStagedLaunch(
          tab: tab,
          sessionId: session.sessionId,
          request: request,
          message: error.toString(),
        );
      } else {
        _host.failSessionConnect(session.sessionId, error.toString());
      }
    }
  }
}
