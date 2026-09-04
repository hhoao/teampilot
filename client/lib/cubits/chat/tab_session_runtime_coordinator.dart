import 'package:flutter/foundation.dart';

import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/session_activity.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/prompt_delivery/prompt_delivery.dart';
import '../../services/prompt_delivery/prompt_delivery_coordinator.dart';
import '../../services/team/session_working_resolver.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/terminal/terminal_reclaim_policy.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';
import 'session_activity_aggregator.dart';
import 'tab_member_coordination_factory.dart';
import 'tab_member_pty_delivery.dart';
import 'tab_member_reclaim_watch.dart';
import 'tab_session_idle_watch.dart';

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
    bool Function(String sessionId)? isSessionPinned,
    SessionActivityAggregator? activityAggregator,
    VoidCallback? onAfterIdleWatchTick,
    void Function(String sessionId, String memberId)? onAfterTurnLatched,
    void Function(String sessionId)? onUserActivity,
    void Function(String sessionId, String memberId)? onAfterTurnEnded,
    CliTool? Function(ChatTab tab, String memberId)? memberCli,
    String? Function()? activeSessionId,
    Map<String, MemberPresence> Function()? presence,
    bool Function(String sessionId)? sessionBusyFromAttention,
    bool Function(String sessionId)? sessionBusyFromDeliveryInFlight,
    SessionWorkingResolver? sessionWorking,
    PromptDeliveryCoordinator? promptDeliveries,
  }) {
    final working =
        sessionWorking ??
        coordinationFactory?.sessionWorking ??
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
          onUserActivity: onUserActivity,
          promptDeliveries: promptDeliveries,
        );
    final idle =
        idleWatch ??
        TabSessionIdleWatch(
          tabStore: tabStore,
          coordinationFactory: coordination,
          isClosed: isClosed,
          memberCli:
              memberCli ??
              (tab, memberId) {
                final session = tab.persistedSession;
                if (session == null) return null;
                return SessionMemberCliResolver.resolve(
                  persistedSession: session,
                  team: activeTeam(),
                  memberId: memberId,
                  globalPresets: globalPresets(),
                  cliForMember: (team, id, {globalPresets = const []}) =>
                      memberLaunchCli(
                        team: team,
                        member: team.members.firstWhere(
                          (m) => m.id == id,
                          orElse: () => TeamMemberConfig(id: id, name: id),
                        ),
                        globalPresets: globalPresets,
                      ),
                );
              },
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
                policy: () => TerminalReclaimPolicy(
                  idleAfter: Duration(seconds: reclaimSeconds()),
                ),
                onDiscardMember: onReclaimMember,
                sessionBusyFromAttention: sessionBusyFromAttention,
                sessionBusyFromDeliveryInFlight:
                    sessionBusyFromDeliveryInFlight,
                isSessionPinned: isSessionPinned,
              ));
    final aggregator =
        activityAggregator ??
        SessionActivityAggregator(
          tabStore: tabStore,
          sessionWorking: working,
          globalPresets: globalPresets,
          activeTeam: activeTeam,
          activeSessionId: activeSessionId ?? () => null,
          presence: presence ?? () => const {},
          sessionBusyFromAttention: sessionBusyFromAttention,
          sessionBusyFromDeliveryInFlight: sessionBusyFromDeliveryInFlight,
        );
    return TabSessionRuntimeCoordinator._(
      coordinationFactory: coordination,
      delivery: ptyDelivery,
      idleWatch: idle,
      reclaimWatch: reclaim,
      activityAggregator: aggregator,
    );
  }

  TabSessionRuntimeCoordinator._({
    required TabMemberCoordinationFactory coordinationFactory,
    required TabMemberPtyDelivery delivery,
    required TabSessionIdleWatch idleWatch,
    required TabMemberReclaimWatch? reclaimWatch,
    required SessionActivityAggregator activityAggregator,
  }) : _coordinationFactory = coordinationFactory,
       _delivery = delivery,
       _idleWatch = idleWatch,
       _reclaimWatch = reclaimWatch,
       _activityAggregator = activityAggregator;

  final TabMemberCoordinationFactory _coordinationFactory;
  final TabMemberPtyDelivery _delivery;
  final TabSessionIdleWatch _idleWatch;
  final TabMemberReclaimWatch? _reclaimWatch;
  final SessionActivityAggregator _activityAggregator;

  SessionWorkingResolver get sessionWorking =>
      _coordinationFactory.sessionWorking;

  void abortMemberInject(String sessionId, String memberId) =>
      _delivery.abortMemberInject(sessionId, memberId);

  TeamBus? busForSession(String sessionId) =>
      _delivery.busForSession(sessionId);

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

  Future<void> syncMemberInputSurface(String sessionId, String memberId) =>
      _delivery.syncMemberInputSurface(sessionId, memberId);

  bool isMemberComposerSurfaceReady(String sessionId, String memberId) =>
      _delivery.isMemberComposerSurfaceReady(sessionId, memberId);

  void maybeNudgeMemberBootGate(String sessionId, String memberId) =>
      _delivery.maybeNudgeMemberBootGate(sessionId, memberId);

  Future<void> deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) => _delivery.deliverMemberStdin(
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
  }) => _delivery.deliverUserCommandToMember(
    sessionId,
    memberId,
    message,
    directToPty: directToPty,
  );

  Future<PromptDeliverySubmission> deliverTrackedUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    required String deliveryId,
  }) => _delivery.deliverTrackedUserCommandToMember(
    sessionId,
    memberId,
    message,
    deliveryId: deliveryId,
  );

  Map<String, Set<SessionBusyReason>> computeReasons() =>
      _activityAggregator.computeReasons();

  /// Ends the seat turn the same way idle-watch does (`coordination.endTurn()`).
  void endMemberTurn(String sessionId, String memberId) =>
      _coordinationFactory.endTurnForMember(sessionId, memberId);

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
