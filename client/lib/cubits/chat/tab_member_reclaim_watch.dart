import 'dart:async';

import '../../models/team_config.dart';
import '../../services/terminal/terminal_reclaim_policy.dart';
import '../../services/terminal/terminal_session.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';
import 'model/session_workbench_view.dart';

/// Chrome-style idle discard: reclaims a member terminal that has been idle
/// (not working, no unread, not the lead, not displayed) past the threshold.
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
    DateTime Function()? now,
  }) : _tabStore = tabStore,
       _reclaimEnabled = reclaimEnabled,
       _activeTeam = activeTeam,
       _policy = policy,
       _onDiscardMember = onDiscardMember,
       _sessionBusyFromAttention = sessionBusyFromAttention,
       _now = now ?? DateTime.now;

  final ChatTabStore _tabStore;
  final bool Function() _reclaimEnabled;
  final TeamProfile? Function() _activeTeam;
  final TerminalReclaimPolicy Function() _policy;
  final void Function(String sessionId, String memberId) _onDiscardMember;
  final bool Function(String sessionId)? _sessionBusyFromAttention;
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
  }

  TerminalReclaimSnapshot _snapshotFor(
    ChatTab tab,
    String memberId,
    TerminalSession shell,
    TeamProfile? team,
  ) {
    final bus = tab.teamBus;
    // Simple sessions always show their one terminal in the terminal view, so
    // the "displayed" protection would permanently block reclaim there. Apply
    // it only to team sessions (roster member selection), where background
    // member terminals are the reclaim target.
    final isTeamSession =
        (tab.persistedSession?.sessionTeam.trim().isNotEmpty ?? false) ||
        (bus != null);
    return TerminalReclaimSnapshot(
      sessionId: tab.info.id,
      memberId: memberId,
      shellRunning: shell.isRunning,
      shellConnecting: shell.isConnecting ||
          tab.membersPendingConnect.contains(memberId),
      isTeamLead: _isTeamLead(team, memberId),
      isDisplayed: isTeamSession &&
          tab.workbenchView == SessionWorkbenchView.terminal &&
          tab.selectedMemberId == memberId,
      inTurn: (bus?.isMemberInTurn(memberId) ?? shell.userTurnActive) ||
          (_sessionBusyFromAttention?.call(tab.info.id) ?? false),
      hasUnread: (bus?.memberById(memberId)?.inbox.unreadCount ?? 0) > 0,
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
