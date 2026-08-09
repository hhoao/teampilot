import 'dart:async';

import '../../cubits/chat/member_lifecycle_connect_gate.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace_launch_context.dart';
import '../../services/launch/connect_shell_result.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';

typedef ScheduleMemberConnectFn =
    void Function(TeamProfile team, TeamMemberConfig member, ChatTab tab);

/// Lifecycle gate evaluation, deferred retries, and direct-PTY readiness checks.
class SessionLifecycleConnectCoordinator {
  SessionLifecycleConnectCoordinator({
    required SessionLaunchHost host,
    required WorkspaceLaunchContext Function(AppSession session) launchContextFor,
    required RuntimeTarget Function(AppSession session, {String? memberId})
    launchWorkTarget,
    required ScheduleMemberConnectFn scheduleMemberConnect,
    required int Function(String sessionId) tabIndexOfSession,
    Duration retryDelay = const Duration(seconds: 2),
  }) : _host = host,
       _launchContextFor = launchContextFor,
       _launchWorkTarget = launchWorkTarget,
       _scheduleMemberConnect = scheduleMemberConnect,
       _tabIndexOfSession = tabIndexOfSession,
       _retryDelay = retryDelay;

  final SessionLaunchHost _host;
  final WorkspaceLaunchContext Function(AppSession session) _launchContextFor;
  final RuntimeTarget Function(AppSession session, {String? memberId})
  _launchWorkTarget;
  final ScheduleMemberConnectFn _scheduleMemberConnect;
  final int Function(String sessionId) _tabIndexOfSession;
  final Duration _retryDelay;
  final _retryTimers = <(String, String), Timer>{};

  MemberLifecycleConnectGate _gate() => MemberLifecycleConnectGate(
    cliRegistry: _host.cliRegistry,
    teammateBusMcpGateway: _host.teammateBusMcpGateway,
    globalPresets: () => _host.lifecycle.globalPresets,
    resolvePaths: (session, memberId) async {
      final launchCtx = _launchContextFor(session);
      final workCtx = await _host.lifecycle.launchWorkContext(
        launchCtx,
        memberId: memberId,
      );
      return _host.lifecycle.configProfileServiceFor(
        workCtx,
        launchWorkspaceId: session.workspaceId,
      );
    },
    memberWorkDirs: (session, memberId) =>
        _host.lifecycle.memberWorkDirs(_launchContextFor(session), memberId),
    launchWorkTarget: (session, {String? memberId}) =>
        _launchWorkTarget(session, memberId: memberId),
  );

  void cancelRetry(String sessionId, String memberId) {
    _retryTimers.remove((sessionId, memberId))?.cancel();
  }

  void _scheduleRetry({
    required TeamProfile team,
    required TeamMemberConfig member,
    required ChatTab tab,
  }) {
    final sessionId = tab.info.id;
    final key = (sessionId, member.id);
    _retryTimers.remove(key)?.cancel();
    _retryTimers[key] = Timer(_retryDelay, () {
      _retryTimers.remove(key);
      if (_host.isClosed || _tabIndexOfSession(sessionId) == -1) return;
      _scheduleMemberConnect(team, member, tab);
    });
  }

  /// Returns null when PTY attach may proceed; otherwise the connect abort reason.
  Future<ConnectShellResult?> gateBeforeAttach({
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required ChatTab tab,
    String? remoteMemberKeyForRollback,
  }) async {
    final outcome = await _gate().evaluate(
      team: team,
      member: member,
      session: session,
      tab: tab,
    );
    switch (outcome) {
      case LifecycleConnectGateAllowed():
        return null;
      case LifecycleConnectGateDeferred(:final reason):
        appLogger.d(
          '[session-launch] lifecycle gate defer member=${member.id} '
          'reason=$reason',
        );
        if (remoteMemberKeyForRollback != null) {
          unawaited(tab.closeMemberRemotePlane(remoteMemberKeyForRollback));
        }
        if (lifecycleGateReasonNeedsMemberRetry(reason)) {
          _scheduleRetry(team: team, member: member, tab: tab);
        }
        return ConnectShellResult.deferred;
      case LifecycleConnectGateBlocked(:final reason, :final userMessage):
        appLogger.d(
          '[session-launch] lifecycle gate block member=${member.id} '
          'reason=$reason',
        );
        if (remoteMemberKeyForRollback != null) {
          unawaited(tab.closeMemberRemotePlane(remoteMemberKeyForRollback));
        }
        _host.failSessionConnect(tab.info.id, userMessage);
        return ConnectShellResult.failed;
    }
  }

  Future<bool> isDirectPtyInputReady({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
  }) =>
      _gate().evaluateDirectPtyInputReady(
        team: team,
        member: member,
        session: session,
        tab: tab,
      );
}
