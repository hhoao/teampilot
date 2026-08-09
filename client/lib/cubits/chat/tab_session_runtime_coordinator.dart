import 'package:flutter/foundation.dart';

import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../../services/team/session_working_resolver.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/terminal/terminal_reclaim_policy.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'tab_member_coordination_factory.dart';
import 'tab_member_pty_delivery.dart';
import 'tab_member_reclaim_watch.dart';
import 'tab_session_idle_watch.dart';
import 'tab_working_aggregator.dart';

/// Per-tab PTY delivery, automation retry, cross-tab idle watch, and working aggregation.
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
    TabMemberReclaimWatch? reclaimWatch,
    bool Function()? reclaimEnabled,
    int Function()? reclaimIdleAfterSeconds,
    void Function(String sessionId, String memberId)? onReclaimMember,
    TabWorkingAggregator? workingAggregator,
    VoidCallback? onAfterIdleWatchTick,
    void Function(String sessionId, String memberId)? onAfterTurnLatched,
    void Function(String sessionId, String memberId)? onAfterTurnEnded,
    String? Function()? activeSessionId,
    Map<String, MemberPresence> Function()? presence,
    bool Function(String sessionId)? sessionBusyFromAttention,
    SessionWorkingResolver? sessionWorking,
  }) {
    final working =
        sessionWorking ?? coordinationFactory?.sessionWorking ??
        SessionWorkingResolver();
    final coordination =
        coordinationFactory ??
        TabMemberCoordinationFactory(
          tabStore: tabStore,
          globalPresets: globalPresets,
          activeTeam: activeTeam,
          sessionWorking: working,
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
          onAfterTurnEnded: onAfterTurnEnded,
        );
    final reclaimSeconds = reclaimIdleAfterSeconds ?? () => 180;
    final reclaim =
        reclaimWatch ??
        (onReclaimMember == null
            ? null
            : TabMemberReclaimWatch(
                tabStore: tabStore,
                reclaimEnabled: reclaimEnabled ?? () => true,
                activeTeam: activeTeam,
                policy: () =>
                    TerminalReclaimPolicy(idleAfter: Duration(seconds: reclaimSeconds())),
                onDiscardMember: onReclaimMember,
              ));
    final aggregator =
        workingAggregator ??
        TabWorkingAggregator(
          tabStore: tabStore,
          sessionWorking: working,
          globalPresets: globalPresets,
          activeTeam: activeTeam,
          activeSessionId: activeSessionId ?? () => null,
          presence: presence ?? () => const {},
          sessionBusyFromAttention: sessionBusyFromAttention,
        );
    return TabSessionRuntimeCoordinator._(
      coordinationFactory: coordination,
      delivery: ptyDelivery,
      idleWatch: idle,
      reclaimWatch: reclaim,
      workingAggregator: aggregator,
    );
  }

  TabSessionRuntimeCoordinator._({
    required TabMemberCoordinationFactory coordinationFactory,
    required TabMemberPtyDelivery delivery,
    required TabSessionIdleWatch idleWatch,
    required TabMemberReclaimWatch? reclaimWatch,
    required TabWorkingAggregator workingAggregator,
  }) : _coordinationFactory = coordinationFactory,
       _delivery = delivery,
       _idleWatch = idleWatch,
       _reclaimWatch = reclaimWatch,
       _workingAggregator = workingAggregator;

  final TabMemberCoordinationFactory _coordinationFactory;
  final TabMemberPtyDelivery _delivery;
  final TabSessionIdleWatch _idleWatch;
  final TabMemberReclaimWatch? _reclaimWatch;
  final TabWorkingAggregator _workingAggregator;

  SessionWorkingResolver get sessionWorking =>
      _coordinationFactory.sessionWorking;

  void abortMemberInject(String sessionId, String memberId) =>
      _delivery.abortMemberInject(sessionId, memberId);

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

  Future<String?> deliverUserCommandToMember(
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

  Set<String> recomputeWorkingSessions() => _workingAggregator.compute();

  /// Starts both the idle-watch heartbeat and the reclaim watch; existing
  /// callers of [ensureIdleWatch] automatically drive the reclaim pass too.
  void ensureIdleWatch() {
    _idleWatch.ensureStarted();
    _reclaimWatch?.ensureStarted();
  }

  void maybeStopIdleWatch() {
    _idleWatch.maybeStop();
    _reclaimWatch?.maybeStop();
  }

  void disposeIdleWatch() {
    _idleWatch.dispose();
    _reclaimWatch?.dispose();
  }

  void debugTickIdleWatch() => _idleWatch.tick();

  void debugTickReclaimWatch() => _reclaimWatch?.tick();
}
