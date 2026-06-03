import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/storage/app_storage.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';

/// Owns the open-tab list and all pure queries/derivations over it.
/// Never emits — callers read results and update ChatState themselves.
class ChatTabStore {
  final List<ChatTab> _tabs = [];

  List<ChatTab> get tabs => _tabs;
  int get length => _tabs.length;
  bool get isEmpty => _tabs.isEmpty;

  void clear() => _tabs.clear();

  List<ChatTabInfo> toInfos() => _tabs.map((t) => t.info).toList();

  ChatTab? activeTab(int activeTabIndex) {
    if (_tabs.isEmpty) return null;
    final index = activeTabIndex.clamp(0, _tabs.length - 1);
    return _tabs[index];
  }

  ChatTab? bySessionId(String id) {
    for (final tab in _tabs) {
      if (tab.info.id == id) return tab;
    }
    return null;
  }

  int indexOfSession(String id) => _tabs.indexWhere((t) => t.info.id == id);

  void append(ChatTab tab) => _tabs.add(tab);

  ChatTab removeAt(int index) => _tabs.removeAt(index);

  String defaultMemberId(TeamConfig team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  ChatTabInfo localSessionInfo(TeamConfig team) => ChatTabInfo(
    id: 'local-${team.id}',
    title: team.name,
    subtitle: 'local session',
  );

  ChatTab appendLocalTab(TeamConfig team, {required String cliTeamName}) {
    final tab = ChatTab(
      info: localSessionInfo(team),
      cliTeamName: cliTeamName,
      selectedMemberId: defaultMemberId(team),
    );
    _tabs.add(tab);
    return tab;
  }

  (String, List<String>) workingDirectoryAndAddDirsForTab(
    ChatTab tab,
    List<AppSession> sessions,
  ) {
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (AppStorage.cwd, const <String>[]);
    }
    for (final s in sessions) {
      if (s.sessionId != tabId) continue;
      final wd = s.primaryPath.trim();
      final addl = s.additionalPaths
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (wd.isNotEmpty) {
        return (wd, addl);
      }
      return (AppStorage.cwd, addl);
    }
    return (AppStorage.cwd, const <String>[]);
  }

  AppSession? sessionForTab(ChatTab tab, List<AppSession> sessions) {
    final cached = tab.persistedSession;
    if (cached != null) return cached;
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return null;
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return null;
  }
}
