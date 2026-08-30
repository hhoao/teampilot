import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/team_config.dart';
import '../../services/session/pty_quiet_turn_end.dart';
import '../../services/team/member_turn_idle_sync.dart';
import '../../utils/logging/logger.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';
import 'tab_member_coordination_factory.dart';

/// Cross-tab idle watch: TeamBus reengage and turn quiet sync.
final class TabSessionIdleWatch {
  TabSessionIdleWatch({
    required ChatTabStore tabStore,
    required TabMemberCoordinationFactory coordinationFactory,
    required bool Function() isClosed,
    CliTool? Function(ChatTab tab, String memberId)? memberCli,
    VoidCallback? onAfterTick,
    void Function(String sessionId, String memberId)? onAfterTurnEnded,
  }) : _tabStore = tabStore,
       _coordinationFactory = coordinationFactory,
       _isClosed = isClosed,
       _memberCli = memberCli,
       _onAfterTick = onAfterTick,
       _onAfterTurnEnded = onAfterTurnEnded;

  final ChatTabStore _tabStore;
  final TabMemberCoordinationFactory _coordinationFactory;
  final bool Function() _isClosed;
  final CliTool? Function(ChatTab tab, String memberId)? _memberCli;
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
          endTurn: () {
            final cli = _memberCli?.call(tab, memberId);
            if (cli == null || !ptyQuietEndsTurn(cli)) return;
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
