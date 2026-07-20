import '../../models/cli_preset.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../../services/team/session_working_resolver.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Aggregates [ChatState.workingSessionIds] from every open tab (all workspaces).
final class TabWorkingAggregator {
  TabWorkingAggregator({
    required ChatTabStore tabStore,
    required SessionWorkingResolver sessionWorking,
    required List<CliPreset> Function() globalPresets,
    required TeamProfile? Function() activeTeam,
    required String? Function() activeSessionId,
    required Map<String, MemberPresence> Function() presence,
    bool Function(String sessionId)? sessionBusyFromAttention,
  }) : _tabStore = tabStore,
       _sessionWorking = sessionWorking,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _activeSessionId = activeSessionId,
       _presence = presence,
       _sessionBusyFromAttention = sessionBusyFromAttention;

  final ChatTabStore _tabStore;
  final SessionWorkingResolver _sessionWorking;
  final List<CliPreset> Function() _globalPresets;
  final TeamProfile? Function() _activeTeam;
  final String? Function() _activeSessionId;
  final Map<String, MemberPresence> Function() _presence;
  final bool Function(String sessionId)? _sessionBusyFromAttention;

  Set<String> compute() {
    final working = <String>{};
    final activeSessionId = _activeSessionId();
    final presence = _presence();

    for (final tab in _tabStore.openTabs) {
      final sessionId = tab.info.id;
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
      // Why: Orca sidebar follows agent-hook waiting/working; PTY idle-watch
      // often ends the turn latch while a permission prompt is held, so after
      // approval the hook goes working but latch stays false without this OR.
      final attentionBusy =
          _sessionBusyFromAttention?.call(sessionId) ?? false;
      if (sessionWorking || attentionBusy) working.add(sessionId);
    }
    return working;
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
