import 'dart:async';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/team/member_coordination.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../utils/logging/logger.dart';
import 'model/chat_tab.dart';
import 'chat_tab_store.dart';
import 'member_connector.dart';
import 'tab_session_runtime_coordinator.dart';

/// Bridges TeamBus [MemberMaterializer] to PTY shells.
///
/// Mixed sessions never race the primary tab launch: this type waits until the
/// teammate bus is registered and only schedules a member connect when no other
/// path already owns that member's PTY attach.
class TabMemberMaterializer implements MemberMaterializer {
  TabMemberMaterializer({
    required TabSessionRuntimeCoordinator runtime,
    required ChatTabStore tabStore,
    required MemberConnector connector,
    required TeamProfile? Function() activeTeam,
    required bool Function() isClosed,
    required bool Function(String sessionId) isMixedBusRegistered,
    required bool Function(String sessionId, String memberId)
    isMemberConnectOwnedElsewhere,
    Future<bool> Function(String sessionId, String memberId)?
    isDirectPtyLifecycleReady,
  }) : _runtime = runtime,
       _tabStore = tabStore,
       _connector = connector,
       _activeTeam = activeTeam,
       _isClosed = isClosed,
       _isMixedBusRegistered = isMixedBusRegistered,
       _isMemberConnectOwnedElsewhere = isMemberConnectOwnedElsewhere,
       _isDirectPtyLifecycleReady = isDirectPtyLifecycleReady;

  final TabSessionRuntimeCoordinator _runtime;
  final ChatTabStore _tabStore;
  final MemberConnector _connector;
  final TeamProfile? Function() _activeTeam;
  final bool Function() _isClosed;
  final bool Function(String sessionId) _isMixedBusRegistered;
  final bool Function(String sessionId, String memberId)
  _isMemberConnectOwnedElsewhere;
  final Future<bool> Function(String sessionId, String memberId)?
  _isDirectPtyLifecycleReady;

  final Map<(String, String), Completer<void>> _memberReady = {};

  void markMemberReady(String sessionId, String memberId) {
    _memberReady.remove((sessionId, memberId))?.complete();
  }

  /// PTY connect + TUI/agent startup complete — used before automation inject.
  ///
  /// [directToPty]: compose-landing operator input — wait until the CLI's input
  /// surface is ready (boot frame, plus composer chrome when the CLI declares
  /// it), then inject at the TUI prompt (never wait for bus `wait_for_message`).
  Future<void> ensureMemberInputReady(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) async {
    appLogger.d(
      '[member-materializer] input-ready wait start member=$memberId '
      'session=$sessionId directToPty=$directToPty '
      '${_inputReadyGateSummary(sessionId, memberId)}',
    );
    await materializeMember(sessionId, memberId, '');
    appLogger.d(
      '[member-materializer] materialize done member=$memberId '
      'session=$sessionId '
      '${_inputReadyGateSummary(sessionId, memberId)}',
    );
    if (_tabStore.openTabBySessionId(sessionId) == null) {
      appLogger.d(
        '[member-materializer] input-ready cancelled no-tab '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    var waitTicks = 0;
    while (!_isClosed()) {
      if (_tabStore.openTabBySessionId(sessionId) == null) {
        appLogger.d(
          '[member-materializer] input-ready cancelled no-tab '
          'member=$memberId session=$sessionId ticks=$waitTicks',
        );
        return;
      }
      final shellReady = _runtime.isMemberReadyForAutomationInput(
        sessionId,
        memberId,
        directToPty: directToPty,
      );
      if (shellReady) {
        if (directToPty) {
          final lifecycleReady = _isDirectPtyLifecycleReady;
          if (lifecycleReady != null &&
              !await lifecycleReady(sessionId, memberId)) {
            waitTicks++;
            if (waitTicks == 1 || waitTicks % 50 == 0) {
              appLogger.d(
                '[member-materializer] input-ready blocked lifecycle '
                'member=$memberId session=$sessionId ticks=$waitTicks '
                '${_inputReadyGateSummary(sessionId, memberId)}',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
            continue;
          }
          await _runtime.syncMemberInputSurface(sessionId, memberId);
          if (!_runtime.isMemberComposerSurfaceReady(sessionId, memberId)) {
            _runtime.maybeNudgeMemberBootGate(sessionId, memberId);
            waitTicks++;
            if (waitTicks == 1 || waitTicks % 50 == 0) {
              appLogger.d(
                '[member-materializer] input-ready blocked composer '
                'member=$memberId session=$sessionId ticks=$waitTicks '
                '${_inputReadyGateSummary(sessionId, memberId)}',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
            continue;
          }
        }
        appLogger.d(
          '[member-materializer] input-ready member=$memberId '
          'session=$sessionId directToPty=$directToPty',
        );
        return;
      }
      waitTicks++;
      // Every ~5s while blocked — pin whether shell/boot/coordination is stuck.
      if (waitTicks == 1 || waitTicks % 50 == 0) {
        appLogger.d(
          '[member-materializer] input-ready still-waiting '
          'member=$memberId session=$sessionId ticks=$waitTicks '
          '${_inputReadyGateSummary(sessionId, memberId)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  String _inputReadyGateSummary(String sessionId, String memberId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return 'gate=no-tab';
    final shell = tab.memberShells[memberId];
    if (shell == null) {
      return 'gate=no-shell keys=${tab.memberShells.keys.toList()} '
          'selected=${tab.selectedMemberId}';
    }
    final coord = _runtime.isMemberReadyForAutomationInput(
      sessionId,
      memberId,
      directToPty: true,
    );
    return 'gate shellRunning=${shell.isRunning} '
        'shellConnected=${shell.isConnected} '
        'shellConnecting=${shell.isConnecting} '
        'boot=${shell.activityTracker.bootFrameDebugSummary} '
        'automationReady=$coord '
        'composer=${_runtime.isMemberComposerSurfaceReady(sessionId, memberId)} '
        'selected=${tab.selectedMemberId}';
  }

  @override
  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  ) async {
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab == null) return;

    if (MemberCoordinationScope.isPersonalSession(tab: tab)) {
      final ready = Completer<void>();
      _memberReady[(sessionId, memberId)] = ready;
      final shell = tab.memberShells[memberId];
      if (shell != null && shell.isRunning) {
        markMemberReady(sessionId, memberId);
      } else {
        appLogger.d(
          '[member-materializer] personal await-connect '
          'member=$memberId session=$sessionId '
          'shellNull=${shell == null} '
          'running=${shell?.isRunning} '
          'connecting=${shell?.isConnecting} '
          'keys=${tab.memberShells.keys.toList()} '
          'selected=${tab.selectedMemberId}',
        );
      }
      await _awaitMemberReady(sessionId, memberId, ready);
      return;
    }

    final team = _activeTeam();
    if (team == null) return;
    // Prefer session pods (builder-0/1) over type ids on team.members —
    // looking up "builder-1" in types-only roster returns empty and the bus
    // falsely completes MaterializeCompleted without a PTY.
    final member = _resolveMemberForMaterialize(tab, team, memberId);
    if (member == null || !member.isValid) {
      appLogger.w(
        '[member-materializer] materialize skip unknown member=$memberId '
        'session=$sessionId',
      );
      return;
    }

    final ready = Completer<void>();
    _memberReady[(sessionId, memberId)] = ready;

    if (_isMemberConnectOwnedElsewhere(sessionId, memberId) ||
        tab.membersPendingConnect.contains(memberId)) {
      final shell = tab.memberShells[memberId];
      if (shell != null && shell.isRunning) {
        // Reuse/connect-in-progress can set owned_elsewhere without a fresh
        // onProcessStarted (already-running PTY). Unblock ready waiters.
        markMemberReady(sessionId, memberId);
      }
      appLogger.d(
        '[member-materializer] materialize await-connect '
        'member=$memberId session=$sessionId owned_elsewhere=true '
        'shellRunning=${shell?.isRunning}',
      );
      await _awaitMemberReady(sessionId, memberId, ready);
      return;
    }

    if (team.teamMode == TeamMode.mixed) {
      await _awaitMixedBusReady(sessionId, tab);
      if (_tabStore.openTabBySessionId(sessionId) == null) {
        if (identical(_memberReady[(sessionId, memberId)], ready)) {
          _memberReady.remove((sessionId, memberId));
        }
        return;
      }
    }

    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      markMemberReady(sessionId, memberId);
      await _awaitMemberReady(sessionId, memberId, ready);
      return;
    }

    if (shell?.isConnecting ?? false) {
      appLogger.d(
        '[member-materializer] materialize await-connect '
        'member=$memberId session=$sessionId connecting=true',
      );
      await _awaitMemberReady(sessionId, memberId, ready);
      return;
    }

    appLogger.d(
      '[member-materializer] materialize schedule-connect '
      'member=$memberId session=$sessionId',
    );
    _connector.scheduleMemberConnect(team, member, tab);
    await _awaitMemberReady(sessionId, memberId, ready);
  }

  Future<void> _awaitMixedBusReady(String sessionId, ChatTab tab) async {
    while (!_isClosed()) {
      if (_tabStore.openTabBySessionId(sessionId) == null) return;
      if (tab.teamBus != null && _isMixedBusRegistered(sessionId)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _awaitMemberReady(
    String sessionId,
    String memberId,
    Completer<void> ready,
  ) async {
    final key = (sessionId, memberId);
    while (!_isClosed()) {
      if (_tabStore.openTabBySessionId(sessionId) == null) {
        if (identical(_memberReady[key], ready)) _memberReady.remove(key);
        appLogger.d(
          '[member-materializer] materialize cancelled no-tab '
          'member=$memberId session=$sessionId',
        );
        return;
      }
      final completed = await Future.any<bool>([
        ready.future.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
      ]);
      if (completed) return;
    }
    if (identical(_memberReady[key], ready)) _memberReady.remove(key);
  }

  TeamMemberConfig? _resolveMemberForMaterialize(
    ChatTab tab,
    TeamProfile team,
    String memberId,
  ) {
    final session = tab.persistedSession;
    if (session != null && session.members.isNotEmpty) {
      for (final m in sessionRosterMembers(session, team)) {
        if (m.id == memberId) return m;
      }
    }
    for (final m in team.members) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  @override
  void injectMemberStdin(String sessionId, String memberId, String text) {
    unawaited(
      _runtime.deliverMemberStdin(
        sessionId,
        memberId,
        text,
        automation: true,
        latchUserTurn: false,
      ),
    );
  }

  @override
  void retryDelivery(String sessionId, String memberId, String notice) {
    unawaited(_runtime.retryMemberDelivery(sessionId, memberId, notice));
  }
}
