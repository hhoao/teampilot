import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';
import 'pty/pty_quiet_turn_end.dart';
import 'member_turn_idle_sync.dart';
import '../../../utils/logging/logger.dart';
import '../session/chat_tab_store.dart';
import '../session/chat_tab.dart';
import 'member_coordination.dart';
import 'tab_member_coordination_factory.dart';

/// Cross-tab idle watch: TeamBus reengage and turn quiet sync.
final class TabSessionIdleWatch {
  TabSessionIdleWatch({
    required ChatTabStore tabStore,
    required TabMemberCoordinationFactory coordinationFactory,
    required bool Function() isClosed,
    CliTool? Function(ChatTab tab, String memberId)? memberCli,
    VoidCallback? onAfterTick,
    void Function(String sessionId, String memberId)? onAfterTurnStarted,
    Future<void> Function(String sessionId, String memberId)? onBeforeTurnEnded,
    void Function(String sessionId, String memberId)? onAfterTurnEnded,
  }) : _tabStore = tabStore,
       _coordinationFactory = coordinationFactory,
       _isClosed = isClosed,
       _memberCli = memberCli,
       _onAfterTick = onAfterTick,
       _onAfterTurnStarted = onAfterTurnStarted,
       _onBeforeTurnEnded = onBeforeTurnEnded,
       _onAfterTurnEnded = onAfterTurnEnded;

  final ChatTabStore _tabStore;
  final TabMemberCoordinationFactory _coordinationFactory;
  final bool Function() _isClosed;
  final CliTool? Function(ChatTab tab, String memberId)? _memberCli;
  final VoidCallback? _onAfterTick;
  final void Function(String sessionId, String memberId)? _onAfterTurnStarted;
  final Future<void> Function(String sessionId, String memberId)?
  _onBeforeTurnEnded;
  final void Function(String sessionId, String memberId)? _onAfterTurnEnded;

  Timer? _timer;

  /// Per-member rising edge of in-turn (shell latch or bus `active`).
  final Map<String, bool> _wasInTurn = {};

  /// Seats whose quiet end is still being prepared. The turn stays published
  /// as in-flight so a queued follow-up cannot start while the preparing
  /// step (the rewind checkpoint) is still reading the seat's runtime.
  final Set<String> _endingTurn = {};

  void ensureStarted() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void maybeStop() {
    // 任何打开的 tab（含简单 / 原生单 CLI）都靠该看门狗驱动 working 指示器，
    // 故仅在全部关闭后才停表。
    if (!_tabStore.hasOpenTabs) {
      _timer?.cancel();
      _timer = null;
      _wasInTurn.clear();
      _endingTurn.clear();
      _onAfterTick?.call();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _wasInTurn.clear();
    _endingTurn.clear();
    _onAfterTick?.call();
  }

  void tick() {
    if (_isClosed()) return;
    for (final tab in _tabStore.openTabs) {
      final bus = tab.teamBus;
      if (bus != null) {
        if (bus.hasTaskQueue) bus.reclaimExpiredTasks();
        bus.reengageIdleWorkers();
      }
      final isPersonal = _coordinationFactory.sessionWorking.isPersonalTab(tab);
      tab.memberShells.forEach((memberId, shell) {
        final key = '${tab.info.id}:$memberId';
        const pendingDelivery = false;
        final coordination = _coordinationFactory.forTabMember(
          tab: tab,
          memberId: memberId,
          shell: shell,
          isPersonal: isPersonal,
        );
        final inTurn = coordination.inTurn(pendingDelivery: pendingDelivery);
        MemberTurnIdleSync.tick(
          turnKey: key,
          inTurn: inTurn,
          shell: shell,
          wasInTurn: _wasInTurn,
          onTurnStarted: () => _onAfterTurnStarted?.call(tab.info.id, memberId),
          endTurn: () {
            final cli = _memberCli?.call(tab, memberId);
            if (cli == null || !ptyQuietEndsTurn(cli)) return;
            if (!_endingTurn.add(key)) return;
            appLogger.d(
              '[idle-watch] end-turn member=$memberId '
              'session=${tab.info.id} '
              'busInTurn=${bus?.isMemberInTurn(memberId)}',
            );
            unawaited(
              _finishTurn(
                sessionId: tab.info.id,
                memberId: memberId,
                turnKey: key,
                coordination: coordination,
              ),
            );
          },
        );
      });
    }
    _onAfterTick?.call();
  }

  /// Publishes the turn end only after [TabSessionIdleWatch]'s
  /// `onBeforeTurnEnded` work (the rewind checkpoint) has completed.
  Future<void> _finishTurn({
    required String sessionId,
    required String memberId,
    required String turnKey,
    required MemberCoordination coordination,
  }) async {
    try {
      await _onBeforeTurnEnded
          ?.call(sessionId, memberId)
          .timeout(const Duration(seconds: 60));
    } on Object {
      // A checkpoint must never keep the turn published as in-flight forever;
      // the store logs its own failure and the next turn can start.
    } finally {
      coordination.endTurn();
      _onAfterTurnEnded?.call(sessionId, memberId);
      _endingTurn.remove(turnKey);
      // The turn edge landed after this tick's post-tick pass, so recompute
      // the working indicators (and let a queued follow-up drain).
      _onAfterTick?.call();
    }
  }
}
