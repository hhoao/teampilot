import 'package:flutter/foundation.dart';

import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/team_bus.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'tab_member_coordination_factory.dart';
import 'tab_member_pty_delivery.dart';
import 'tab_session_idle_watch.dart';

/// Per-tab PTY delivery, automation retry, and cross-tab idle watch.
///
/// Shared by personal (no TeamBus) and mixed team sessions. TeamBus lifecycle
/// lives in [TabTeamBusCoordinator].
class TabSessionRuntimeCoordinator {
  factory TabSessionRuntimeCoordinator({
    required ChatTabStore tabStore,
    required ChatSessionShellFactory shellFactory,
    required List<CliPreset> Function() globalPresets,
    required TeamProfile? Function() activeTeam,
    required bool Function() isClosed,
    TabMemberCoordinationFactory? coordinationFactory,
    TabMemberPtyDelivery? delivery,
    TabSessionIdleWatch? idleWatch,
    VoidCallback? onAfterIdleWatchTick,
    VoidCallback? onAfterTurnLatched,
  }) {
    final coordination =
        coordinationFactory ??
        TabMemberCoordinationFactory(
          tabStore: tabStore,
          globalPresets: globalPresets,
          activeTeam: activeTeam,
        );
    final ptyDelivery =
        delivery ??
        TabMemberPtyDelivery(
          tabStore: tabStore,
          shellFactory: shellFactory,
          globalPresets: globalPresets,
          activeTeam: activeTeam,
          isClosed: isClosed,
          coordinationFactory: coordination,
          onAfterTurnLatched: onAfterTurnLatched,
        );
    final idle =
        idleWatch ??
        TabSessionIdleWatch(
          tabStore: tabStore,
          coordinationFactory: coordination,
          delivery: ptyDelivery,
          isClosed: isClosed,
          onAfterTick: onAfterIdleWatchTick,
        );
    return TabSessionRuntimeCoordinator._(
      coordinationFactory: coordination,
      delivery: ptyDelivery,
      idleWatch: idle,
    );
  }

  TabSessionRuntimeCoordinator._({
    required TabMemberCoordinationFactory coordinationFactory,
    required TabMemberPtyDelivery delivery,
    required TabSessionIdleWatch idleWatch,
  }) : _coordinationFactory = coordinationFactory,
       _delivery = delivery,
       _idleWatch = idleWatch;

  final TabMemberCoordinationFactory _coordinationFactory;
  final TabMemberPtyDelivery _delivery;
  final TabSessionIdleWatch _idleWatch;

  TeamBus? busForSession(String sessionId) => _delivery.busForSession(sessionId);

  bool isMemberReadyForAutomationInput(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) {
    final coordination = _coordinationFactory.forMember(
      sessionId,
      memberId,
      directToPty: directToPty,
    );
    if (coordination == null) return false;
    return coordination.isReadyForAutomationInput(directToPty: directToPty);
  }

  Future<void> deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) =>
      _delivery.deliverMemberStdin(
        sessionId,
        memberId,
        text,
        automation: automation,
        latchUserTurn: latchUserTurn,
      );

  Future<void> retryMemberDelivery(
    String sessionId,
    String memberId,
    String notice,
  ) => _delivery.retryMemberDelivery(sessionId, memberId, notice);

  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
  }) =>
      _delivery.deliverUserCommandToMember(
        sessionId,
        memberId,
        message,
        directToPty: directToPty,
      );

  void ensureIdleWatch() => _idleWatch.ensureStarted();

  void maybeStopIdleWatch() => _idleWatch.maybeStop();

  void disposeIdleWatch() => _idleWatch.dispose();

  void debugTickIdleWatch() => _idleWatch.tick();
}
