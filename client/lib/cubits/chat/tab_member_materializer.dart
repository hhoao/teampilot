import 'dart:async';

import '../../models/team_config.dart';
import '../../services/team/member_coordination.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../utils/logger.dart';
import 'chat_tab_store.dart';
import 'member_connector.dart';
import 'tab_session_runtime_coordinator.dart';

/// Bridges TeamBus [MemberMaterializer] to PTY shells and team member connects.
class TabMemberMaterializer implements MemberMaterializer {
  TabMemberMaterializer({
    required TabSessionRuntimeCoordinator runtime,
    required ChatTabStore tabStore,
    required MemberConnector connector,
    required TeamProfile? Function() activeTeam,
    required bool Function() isClosed,
  }) : _runtime = runtime,
       _tabStore = tabStore,
       _connector = connector,
       _activeTeam = activeTeam,
       _isClosed = isClosed;

  final TabSessionRuntimeCoordinator _runtime;
  final ChatTabStore _tabStore;
  final MemberConnector _connector;
  final TeamProfile? Function() _activeTeam;
  final bool Function() _isClosed;

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
      if (_runtime.isMemberReadyForAutomationInput(
        sessionId,
        memberId,
        directToPty: directToPty,
      )) {
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
    final tab = _tabStore.bySessionId(sessionId);
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
    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      if (shell.isConnected) {
        appLogger.d(
          '[member-materializer] materialize already-connected '
          'member=$memberId session=$sessionId',
        );
      }
      markMemberReady(sessionId, memberId);
    } else {
      appLogger.d(
        '[member-materializer] materialize await-connect '
        'member=$memberId session=$sessionId '
        'isRunning=${shell?.isRunning ?? false} '
        'isConnecting=${shell?.isConnecting ?? false}',
      );
      _connector.scheduleMemberConnect(team, member, tab);
    }
    await ready.future;
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
