import 'dart:async';

import '../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../../models/team_config.dart';
import 'pty/terminal_reclaim_policy.dart';
import '../../terminal/terminal_session.dart';
import '../../../utils/logging/logger.dart';
import '../../../utils/team/team_member_naming.dart';
import '../session/chat_tab_store.dart';
import '../session/chat_tab.dart';
import '../session/session_workbench_view.dart';

/// Chrome-style idle discard: reclaims a member terminal that has been idle
/// (not working, no unread, not the lead, not displayed, not session-pinned)
/// past the threshold.
/// Restoration is lazy — via the TeamBus materialize funnel or
/// `ensureMemberTerminalForView` — so reclaim is cheap to reverse.
class TabMemberReclaimWatch {
  TabMemberReclaimWatch({
    required ChatTabStore tabStore,
    required bool Function() reclaimEnabled,
    required TeamProfile? Function() activeTeam,
    required TerminalReclaimPolicy Function() policy,
    required void Function(String sessionId, String memberId) onDiscardMember,
    bool Function(String sessionId)? sessionBusyFromAttention,
    bool Function(String sessionId)? sessionBusyFromDeliveryInFlight,
    bool Function(String sessionId)? isSessionPinned,
    bool Function(String sessionId, String memberId)? seatHasActiveLeases,
    DateTime Function()? now,
    TerminalReclaimPolicy Function()? acpPolicy,
    void Function(String sessionId, String memberId)? onDiscardAcpSeat,
    String? Function()? activeSessionId,
    void Function(String sessionId)? onDiscardPersonalAcp,
  }) : _tabStore = tabStore,
       _reclaimEnabled = reclaimEnabled,
       _activeTeam = activeTeam,
       _policy = policy,
       _onDiscardMember = onDiscardMember,
       _sessionBusyFromAttention = sessionBusyFromAttention,
       _sessionBusyFromDeliveryInFlight = sessionBusyFromDeliveryInFlight,
       _isSessionPinned = isSessionPinned,
       _seatHasActiveLeases = seatHasActiveLeases,
       _acpPolicy = acpPolicy,
       _onDiscardAcpSeat = onDiscardAcpSeat,
       _activeSessionId = activeSessionId,
       _onDiscardPersonalAcp = onDiscardPersonalAcp,
       _now = now ?? DateTime.now;

  final ChatTabStore _tabStore;
  final bool Function() _reclaimEnabled;
  final TeamProfile? Function() _activeTeam;
  final TerminalReclaimPolicy Function() _policy;
  final void Function(String sessionId, String memberId) _onDiscardMember;
  final bool Function(String sessionId)? _sessionBusyFromAttention;
  final bool Function(String sessionId)? _sessionBusyFromDeliveryInFlight;
  final bool Function(String sessionId)? _isSessionPinned;
  final bool Function(String sessionId, String memberId)? _seatHasActiveLeases;
  final TerminalReclaimPolicy Function()? _acpPolicy;
  final void Function(String sessionId, String memberId)? _onDiscardAcpSeat;

  /// Bar-derived centre-active session (null when nothing is centre-active).
  /// Personal ACP has no per-member selection, so this is its "displayed" gate.
  final String? Function()? _activeSessionId;

  /// Personal ACP (`isAcpChatSession`) discard; the seat key is the session id.
  final void Function(String sessionId)? _onDiscardPersonalAcp;
  final DateTime Function() _now;

  Timer? _timer;

  /// Per (session, member) idle-start timestamp. Null = not yet idle.
  final Map<(String, String), DateTime> _idleSince = {};

  void ensureStarted() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void maybeStop() {
    if (!_tabStore.hasOpenTabs) {
      _timer?.cancel();
      _timer = null;
      _idleSince.clear();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _idleSince.clear();
  }

  void tick() {
    if (!_reclaimEnabled()) {
      _idleSince.clear();
      return;
    }
    final policy = _policy();
    final team = _activeTeam();
    final now = _now();
    for (final tab in _tabStore.openTabs) {
      final sessionId = tab.info.id;
      for (final entry in tab.memberShells.entries.toList()) {
        final memberId = entry.key;
        final shell = entry.value;
        final snapshot = _snapshotFor(tab, memberId, shell, team);
        final key = (sessionId, memberId);
        if (policy.isProtected(snapshot)) {
          _idleSince.remove(key);
          continue;
        }
        final idleSince = _idleSince[key] ?? now;
        _idleSince[key] = idleSince;
        if (policy.shouldReclaim(snapshot, idleSince, now)) {
          appLogger.d(
            '[reclaim-watch] discard member=$memberId session=$sessionId '
            'idle=${now.difference(idleSince).inSeconds}s',
          );
          _idleSince.remove(key);
          _onDiscardMember(sessionId, memberId);
        }
      }
    }

    final acpPolicy = _acpPolicy?.call();
    if (acpPolicy != null) {
      for (final tab in _tabStore.openTabs) {
        final session = tab.persistedSession;
        // Personal ACP lives in the same map (keyed by the session id) but its
        // visibility is tab-level: the chat surface has no member selection.
        final personal = session != null && isAcpChatSession(session);
        for (final entry in tab.memberAcpRuntimes.entries.toList()) {
          final memberId = entry.key;
          final snapshot = _acpSnapshotFor(
            tab,
            memberId,
            entry.value,
            team,
            personal: personal,
          );
          final key = (tab.info.id, memberId);
          if (acpPolicy.isProtected(snapshot)) {
            _idleSince.remove(key);
            continue;
          }
          final idleSince = _idleSince[key] ?? now;
          _idleSince[key] = idleSince;
          if (acpPolicy.shouldReclaim(snapshot, idleSince, now)) {
            appLogger.d(
              '[reclaim-watch] discard acp member=$memberId session=${tab.info.id} '
              'personal=$personal idle=${now.difference(idleSince).inSeconds}s',
            );
            _idleSince.remove(key);
            if (personal) {
              _onDiscardPersonalAcp?.call(tab.info.id);
            } else {
              _onDiscardAcpSeat?.call(tab.info.id, memberId);
            }
          }
        }
      }
    }
  }

  TerminalReclaimSnapshot _acpSnapshotFor(
    ChatTab tab,
    String memberId,
    AcpChatRuntimeCubit cubit,
    TeamProfile? team, {
    required bool personal,
  }) {
    final phase = cubit.state.phase;
    final sessionId = tab.info.id;
    return TerminalReclaimSnapshot(
      sessionId: sessionId,
      memberId: memberId,
      shellRunning: phase != AcpChatPhase.ended,
      shellConnecting: phase == AcpChatPhase.launching,
      isTeamLead: personal ? false : _isTeamLead(team, memberId),
      isDisplayed: personal
          ? _activeSessionId?.call() == sessionId
          : tab.selectedMemberId == memberId,
      inTurn:
          cubit.state.inTurn ||
          cubit.state.pendingClient != null ||
          (personal &&
              ((_sessionBusyFromAttention?.call(sessionId) ?? false) ||
                  (_sessionBusyFromDeliveryInFlight?.call(sessionId) ?? false))),
      hasUnread:
          (tab.teamBus?.memberById(memberId)?.inbox.unreadCount ?? 0) > 0,
      isSessionPinned:
          _isSessionPinned?.call(sessionId) ??
          (tab.persistedSession?.pinned ?? false),
      hasActiveLeases:
          _seatHasActiveLeases?.call(
            sessionId,
            personal ? AcpChatRuntimeCubit.acpMemberId : memberId,
          ) ??
          false,
    );
  }

  TerminalReclaimSnapshot _snapshotFor(
    ChatTab tab,
    String memberId,
    TerminalSession shell,
    TeamProfile? team,
  ) {
    final bus = tab.teamBus;
    // Team sessions scope the "displayed" protection to the selected roster
    // member; background member terminals are the reclaim target. A simple
    // session has one terminal which is the displayed surface whenever the
    // tab is in Terminal view — protect it too, so the terminal the user is
    // looking at is never discarded under them. Reclaim still applies while
    // Chat is shown (terminal hidden behind the overlay).
    final isTeamSession =
        (tab.persistedSession?.sessionTeam.trim().isNotEmpty ?? false) ||
        (bus != null);
    return TerminalReclaimSnapshot(
      sessionId: tab.info.id,
      memberId: memberId,
      shellRunning: shell.isRunning,
      shellConnecting:
          shell.isConnecting || tab.membersPendingConnect.contains(memberId),
      isTeamLead: _isTeamLead(team, memberId),
      isDisplayed:
          tab.workbenchView == SessionWorkbenchView.terminal &&
          (!isTeamSession || tab.selectedMemberId == memberId),
      inTurn:
          (bus?.isMemberInTurn(memberId) ?? shell.userTurnActive) ||
          (_sessionBusyFromAttention?.call(tab.info.id) ?? false) ||
          (_sessionBusyFromDeliveryInFlight?.call(tab.info.id) ?? false),
      hasUnread: (bus?.memberById(memberId)?.inbox.unreadCount ?? 0) > 0,
      isSessionPinned:
          _isSessionPinned?.call(tab.info.id) ??
          (tab.persistedSession?.pinned ?? false),
      hasActiveLeases:
          _seatHasActiveLeases?.call(tab.info.id, memberId) ?? false,
    );
  }

  bool _isTeamLead(TeamProfile? team, String memberId) {
    if (team == null) return false;
    for (final m in team.members) {
      if (m.id == memberId) return TeamMemberNaming.isTeamLead(m);
    }
    return false;
  }
}
