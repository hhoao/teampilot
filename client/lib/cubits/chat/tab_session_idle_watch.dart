import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/team/member_turn_idle_sync.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import 'chat_tab_store.dart';
import 'tab_member_coordination_factory.dart';
import 'tab_member_pty_delivery.dart';

/// Cross-tab idle watch: automation retry ticks, bus reengage, turn quiet sync.
final class TabSessionIdleWatch {
  TabSessionIdleWatch({
    required ChatTabStore tabStore,
    required TabMemberCoordinationFactory coordinationFactory,
    required TabMemberPtyDelivery delivery,
    required bool Function() isClosed,
    VoidCallback? onAfterTick,
    void Function(String sessionId, String memberId)? onAfterTurnEnded,
  }) : _tabStore = tabStore,
       _coordinationFactory = coordinationFactory,
       _delivery = delivery,
       _isClosed = isClosed,
       _onAfterTick = onAfterTick,
       _onAfterTurnEnded = onAfterTurnEnded;

  final ChatTabStore _tabStore;
  final TabMemberCoordinationFactory _coordinationFactory;
  final TabMemberPtyDelivery _delivery;
  final bool Function() _isClosed;
  final VoidCallback? _onAfterTick;
  final void Function(String sessionId, String memberId)? _onAfterTurnEnded;

  Timer? _timer;

  /// Per-member rising edge of in-turn (shell latch or bus `active`).
  final Map<String, bool> _wasInTurn = {};

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
      _onAfterTick?.call();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _wasInTurn.clear();
    _onAfterTick?.call();
  }

  void tick() {
    if (_isClosed()) return;
    _delivery.tickRetries(
      shouldSkip: (retryTick) {
        if (!_delivery.shouldSkipAutomationRetry(
          retryTick.sessionId,
          retryTick.memberId,
          dueRetryText: retryTick.text,
        )) {
          return false;
        }
        final shell = _tabStore
            .openTabBySessionId(retryTick.sessionId)
            ?.memberShells[retryTick.memberId];
        if (shell != null) {
          _delivery.dropStaleAutomationRetry(
            retryTick.sessionId,
            retryTick.memberId,
            shell,
          );
        } else {
          _delivery.clearPending(retryTick.sessionId, retryTick.memberId);
        }
        return true;
      },
      onTick: (retryTick) {
        unawaited(_delivery.retryAutomationTick(retryTick));
      },
    );
    for (final tab in _tabStore.openTabs) {
      final bus = tab.teamBus;
      if (bus != null) {
        if (bus.hasTaskQueue) bus.reclaimExpiredTasks();
        bus.reengageIdleWorkers();
      }
      final isPersonal = _coordinationFactory.sessionWorking.isPersonalTab(tab);
      tab.memberShells.forEach((memberId, shell) {
        final key = '${tab.info.id}:$memberId';
        final sessionId = tab.info.id;
        final pendingDelivery =
            _delivery.hasPendingRetry(sessionId, memberId) ||
            _delivery.isBusy(sessionId, memberId);
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
          endTurn: () {
            appLogger.d(
              '[idle-watch] end-turn member=$memberId '
              'session=${tab.info.id} '
              'busInTurn=${bus?.isMemberInTurn(memberId)}',
            );
            coordination.endTurn();
            _onAfterTurnEnded?.call(tab.info.id, memberId);
          },
        );
      });
    }
    _onAfterTick?.call();
  }
}
