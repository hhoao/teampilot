import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/session_activity.dart';
import '../../models/team_config.dart';
import '../../services/team/session_working_resolver.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Aggregates per-session [SessionBusyReason] sets from every open tab.
final class SessionActivityAggregator {
  SessionActivityAggregator({
    required ChatTabStore tabStore,
    required SessionWorkingResolver sessionWorking,
    required List<CliPreset> Function() globalPresets,
    required TeamProfile? Function() activeTeam,
    required String? Function() activeSessionId,
    required Map<String, MemberPresence> Function() presence,
    bool Function(String sessionId)? sessionBusyFromAttention,
    bool Function(String sessionId)? sessionBusyFromDeliveryInFlight,
  }) : _tabStore = tabStore,
       _sessionWorking = sessionWorking,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _activeSessionId = activeSessionId,
       _presence = presence,
       _sessionBusyFromAttention = sessionBusyFromAttention,
       _sessionBusyFromDeliveryInFlight = sessionBusyFromDeliveryInFlight;

  final ChatTabStore _tabStore;
  final SessionWorkingResolver _sessionWorking;
  final List<CliPreset> Function() _globalPresets;
  final TeamProfile? Function() _activeTeam;
  final String? Function() _activeSessionId;
  final Map<String, MemberPresence> Function() _presence;
  final bool Function(String sessionId)? _sessionBusyFromAttention;
  final bool Function(String sessionId)? _sessionBusyFromDeliveryInFlight;

  Map<String, Set<SessionBusyReason>> computeReasons() {
    final reasonsBySession = <String, Set<SessionBusyReason>>{};
    final activeSessionId = _activeSessionId();
    final presence = _presence();

    for (final tab in _tabStore.openTabs) {
      final sessionId = tab.info.id;
      final reasons = <SessionBusyReason>{};

      final usesPresenceSnapshot = _sessionWorking.usesPresenceSnapshotForTab(
        tab: tab,
        activeSessionId: activeSessionId,
        presenceNonEmpty: presence.isNotEmpty,
      );
      final sessionWorking = usesPresenceSnapshot
          ? presence.values.any((p) => p.isWorking)
          : _sessionWorking.tabHasWorkingMember(
              tab: tab,
              team: _teamForTab(tab),
              globalPresets: _globalPresets(),
            );
      if (sessionWorking) {
        reasons.add(SessionBusyReason.inTurn);
      }

      if (_sessionBusyFromAttention?.call(sessionId) ?? false) {
        reasons.add(SessionBusyReason.attention);
      }

      if (_sessionBusyFromDeliveryInFlight?.call(sessionId) ?? false) {
        reasons.add(SessionBusyReason.delivering);
      }

      reasonsBySession[sessionId] = reasons;
    }
    return reasonsBySession;
  }

  TeamProfile? _teamForTab(ChatTab tab) {
    final session = tab.persistedSession;
    if (session == null || session.sessionTeam.trim().isEmpty) return null;
    final teamId = session.sessionTeam.trim();
    final activeTeam = _activeTeam();
    if (activeTeam?.id == teamId) return activeTeam;
    return null;
  }
}
