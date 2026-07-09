import 'dart:async';

import '../../models/team_config.dart';
import '../../services/team/member_coordination.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../utils/logger.dart';
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
  /// [directToPty]: compose-landing operator input — boot frame only, inject at
  /// the TUI prompt (never wait for bus `wait_for_message`).
  Future<void> ensureMemberInputReady(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) async {
    await materializeMember(sessionId, memberId, '');
    while (!_isClosed()) {
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
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
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
      }
      await ready.future;
      return;
    }

    final team = _activeTeam();
    if (team == null) return;
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) return;

    final ready = Completer<void>();
    _memberReady[(sessionId, memberId)] = ready;

    if (_isMemberConnectOwnedElsewhere(sessionId, memberId) ||
        tab.membersPendingConnect.contains(memberId)) {
      appLogger.d(
        '[member-materializer] materialize await-connect '
        'member=$memberId session=$sessionId owned_elsewhere=true',
      );
      await ready.future;
      return;
    }

    if (team.teamMode == TeamMode.mixed) {
      await _awaitMixedBusReady(sessionId, tab);
    }

    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      markMemberReady(sessionId, memberId);
      await ready.future;
      return;
    }

    if (shell?.isConnecting ?? false) {
      appLogger.d(
        '[member-materializer] materialize await-connect '
        'member=$memberId session=$sessionId connecting=true',
      );
      await ready.future;
      return;
    }

    appLogger.d(
      '[member-materializer] materialize schedule-connect '
      'member=$memberId session=$sessionId',
    );
    _connector.scheduleMemberConnect(team, member, tab);
    await ready.future;
  }

  Future<void> _awaitMixedBusReady(String sessionId, ChatTab tab) async {
    while (!_isClosed()) {
      if (tab.teamBus != null && _isMixedBusRegistered(sessionId)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
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
